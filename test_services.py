"""Storage fault tests and two-computer wireless simulation. Requires lupa."""
from pathlib import Path
from lupa import LuaRuntime

CODE = Path(__file__).with_name('diskdesk_services.lua').read_text(encoding='utf-8')
BASE = r'''
files = {['']=true, disk=true, disk2=true, ['disk/docs']=true,
  ['disk/docs/a.bin']='hello\0\255\nworld', ['disk/empty']=true, ['disk/root.txt']='root'}
volumes={left={root='disk',id=10},right={root='disk2',id=20}}
free, corrupt, now = 10000000, false, 0
fs = {}
fs.combine=function(a,b) local s=(a..'/'..b):gsub('^/',''):gsub('/$',''); return s end
fs.getDir=function(p) return p:match('^(.*)/[^/]+$') or '' end
fs.getName=function(p) return p:match('[^/]+$') or '' end
fs.exists=function(p) return files[p]~=nil end
fs.isDir=function(p) return files[p]==true end
fs.isDriveRoot=function(p) return p=='' or p=='disk' or p=='disk2' end
fs.isReadOnly=function() return false end
fs.getFreeSpace=function() return free end
fs.getSize=function(p) assert(type(files[p])=='string',p); return #files[p] end
fs.list=function(p)
  assert(files[p]==true,'not a directory: '..p)
  local out={}
  for k in pairs(files) do if k~=p and fs.getDir(k)==p then out[#out+1]=fs.getName(k) end end
  table.sort(out); return out
end
fs.makeDir=function(p)
  if p=='' then return end
  assert(files[p]==nil or files[p]==true,'file in the way')
  fs.makeDir(fs.getDir(p)); files[p]=true
end
fs.delete=function(p)
  for k in pairs(files) do if k==p or k:sub(1,#p+1)==p..'/' then files[k]=nil end end
end
fs.move=function(a,b)
  assert(not files[b] and files[a]~=nil)
  local moved={}
  for k,v in pairs(files) do
    if k==a or k:sub(1,#a+1)==a..'/' then moved[b..k:sub(#a+1)]=v end
  end
  fs.delete(a)
  for k,v in pairs(moved) do files[k]=v end
end
fs.open=function(p,mode)
  local closed,pos=false,1
  if mode:sub(1,1)=='r' then
    if type(files[p])~='string' then return nil,'not a file: '..p end
    return {read=function(n)
      assert(not closed); if pos>#files[p] then return nil end
      local s=files[p]:sub(pos,pos+n-1); pos=pos+#s; return s
    end, readAll=function() assert(not closed); return files[p] end,
    close=function() closed=true end}
  end
  assert(files[fs.getDir(p)]==true,'missing parent '..p)
  files[p]=''
  return {write=function(s)
    assert(not closed); files[p]=files[p]..(corrupt and 'X'..s or s)
  end, close=function() closed=true end}
end
disk={getID=function(d) return volumes[d] and volumes[d].id end,
  getMountPath=function(d) return volumes[d] and volumes[d].root end,
  getLabel=function(d) return 'Floppy '..volumes[d].id end}
local function serialize(v)
  if type(v)=='string' then return string.format('%q',v) end
  if type(v)~='table' then return tostring(v) end
  local out={'{'}
  for k,item in pairs(v) do out[#out+1]='['..serialize(k)..']='..serialize(item)..',' end
  return table.concat(out)..'}'
end
textutils={serialize=serialize,unserialize=function(s)
  local fn=load('return '..s,'manifest','t',{}); if not fn then return nil end
  local ok,res=pcall(fn); if ok then return res end
end}
os.getComputerID=function() return 1 end
os.epoch=function() return 1000 end
os.clock=function() return now end
keys={escape=1}
peripheral={getNames=function() return {'back'} end,
  hasType=function(n,t) return t=='modem' end,
  wrap=function() return {isWireless=function() return true end} end}
M=assert(load(serviceSource,'services'))()
src,dest=M.capture('left'),M.capture('right')
function fails(fn,pattern)
  local ok,err=pcall(fn); assert(not ok,'expected failure')
  if pattern then assert(tostring(err):find(pattern,1,true),tostring(err)) end
end
'''

def test(name, script):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().serviceSource = CODE
    lua.execute(BASE)
    lua.execute(script)
    print('PASS:', name)

test('binary snapshot and restore, empty folders', r'''
local snapshot=M.backup(src,dest)
assert(files[snapshot..'/data/docs/a.bin']==files['disk/docs/a.bin'])
assert(files[snapshot..'/data/empty']==true)
local restored=M.restore(snapshot,dest,src)
assert(files[restored..'/docs/a.bin']==files['disk/docs/a.bin'])
assert(files[restored..'/empty']==true and files['disk/root.txt']=='root')
assert(#M.snapshots(dest)==1)
''')
test('backup versions preserve old content', r'''
local old=M.backup(src,dest)
files['disk/root.txt']='new version'
local fresh=M.backup(src,dest)
assert(old~=fresh and files[old..'/data/root.txt']=='root')
assert(files[fresh..'/data/root.txt']=='new version' and #M.snapshots(dest)==2)
''')
test('same disk rejected', "fails(function() M.backup(src,src) end,'diferentes')")
test('low space rejected before writing', r'''
free=1; fails(function() M.backup(src,dest) end,'Espaco')
assert(not files['disk2/.diskdesk-backups'])
''')
test('disk swap interrupts without publishing snapshot', r'''
fails(function() M.backup(src,dest,function() volumes.right.id=99 end) end,'trocado')
volumes.right.id=20
assert(#M.snapshots(dest)==0)
''')
test('bad writes fail verification', r'''
corrupt=true; fails(function() M.backup(src,dest) end,'verificacao')
assert(#M.snapshots(dest)==0)
''')
test('restore detects corruption before writing', r'''
local snapshot=M.backup(src,dest)
files[snapshot..'/data/root.txt']='bad'
fails(function() M.restore(snapshot,dest,src) end,'corrompido')
for path in pairs(files) do assert(not path:find('Restaurado',1,true)) end
''')
test('restore rejects path traversal', r'''
local snapshot=M.backup(src,dest)
files[snapshot..'/manifest']=textutils.serialize({version=1,entries={{path='../escape',dir=true}}})
fails(function() M.restore(snapshot,dest,src) end,'Caminho invalido')
''')
test('backup history excluded', r'''
files['disk/.diskdesk-backups']=true; files['disk/.diskdesk-backups/history']='skip'
local snapshot=M.backup(src,dest)
assert(not files[snapshot..'/data/.diskdesk-backups'])
''')
test('known Adler32 checksum', "assert(M.checksum('Wikipedia')==300286872)")

RAID = '''
peripheral.getNames=function() return {'left','right','back'} end
peripheral.hasType=function(n,t) return (t=='drive' and (n=='left' or n=='right')) or (t=='modem' and n=='back') end
'''
test('RAID initial sync and persistent disk IDs', RAID + '''
M.raidConfigure(src,dest); assert(M.raidSync()=='Sincronizado')
assert(files['disk2/RAID1/docs/a.bin']==files['disk/docs/a.bin'])
assert(files['disk2/RAID1/empty']==true)
local reloaded=assert(load(serviceSource))()
assert(reloaded.raidLoad().primary==10 and reloaded.raidLoad().mirror==20)
assert(reloaded.raidSync()=='Sincronizado')
''')
test('RAID changes and deletions mirror, unrelated files survive', RAID + '''
files['disk2/unrelated']='keep'
M.raidConfigure(src,dest); M.raidSync()
files['disk/root.txt']='changed'; files['disk/docs/a.bin']=nil
M.raidSync()
assert(files['disk2/RAID1/root.txt']=='changed' and not files['disk2/RAID1/docs/a.bin'])
assert(files['disk2/unrelated']=='keep')
''')
test('RAID missing primary never wipes mirror', RAID + '''
M.raidConfigure(src,dest); M.raidSync(); volumes.left=nil
assert(M.raidSync()=='Degradado')
assert(files['disk2/RAID1/root.txt']=='root')
volumes.left={id=10,root='disk'}; files['disk/root.txt']='returned'
assert(M.raidSync()=='Sincronizado' and files['disk2/RAID1/root.txt']=='returned')
''')
test('RAID wrong floppy not used as mirror', RAID + '''
M.raidConfigure(src,dest); M.raidSync(); volumes.right.id=99
files['disk/root.txt']='new'
assert(M.raidSync()=='Degradado' and files['disk2/RAID1/root.txt']=='root')
''')
test('RAID low space preserves last complete mirror', RAID + '''
M.raidConfigure(src,dest); M.raidSync()
files['disk/root.txt']='new'; free=1
fails(function() M.raidSync() end,'Espaco')
assert(files['disk2/RAID1/root.txt']=='root')
''')
test('RAID interruption while staging preserves old mirror', RAID + '''
M.raidConfigure(src,dest); M.raidSync(); files['disk/root.txt']='new'
fails(function() M.raidSync(function() volumes.right.id=99 end) end,'trocado')
assert(files['disk2/RAID1/root.txt']=='root')
''')
test('RAID interrupted publication recovers on next sync', RAID + '''
M.raidConfigure(src,dest); M.raidSync(); files['disk/root.txt']='new'
local move=fs.move
fs.move=function(a,b) if a=='disk2/.diskdesk-raid-next' then error('commit failure') end; move(a,b) end
fails(function() M.raidSync() end,'commit failure')
assert(files['disk2/.diskdesk-raid-old/root.txt']=='root')
fs.move=move; assert(M.raidSync()=='Sincronizado')
assert(files['disk2/RAID1/root.txt']=='new')
''')
test('RAID write protection and disable keeps data', RAID + '''
M.raidConfigure(src,dest); M.raidSync()
fails(function() M.assertWritable('disk2/RAID1/root.txt') end,'protegido')
M.assertWritable('disk/root.txt')
M.raidDisable(); M.assertWritable('disk2/RAID1/root.txt')
assert(files['disk2/RAID1/root.txt']=='root' and not files['.diskdesk-raid.cfg'])
''')
test('backup RAID1 copies one verified version to multiple independent disks', r'''
files.disk3=true; volumes.top={root='disk3',id=30}; local third=M.capture('top')
local results=M.backupMany(src,{dest,third})
assert(#results==2 and files[results[1]..'/data/root.txt']=='root')
assert(files[results[2]..'/data/root.txt']=='root')
assert(#M.snapshots(dest)==1 and #M.snapshots(third)==1)
files[results[1]..'/data/root.txt']='changed backup copy'
assert(files[results[2]..'/data/root.txt']=='root')
''')
test('backup RAID1 rejects duplicate destination before writing', r'''
fails(function() M.backupMany(src,{dest,dest}) end,'diferentes')
assert(not files['disk2/.diskdesk-backups'])
''')
test('computer file backup to multiple disks restores original name and content', r'''
files['computer.txt']='from computer'
files.disk3=true; volumes.top={root='disk3',id=30}; local third=M.capture('top')
local results=M.backupItemMany('computer.txt','Computador / computer.txt','computador-1',{dest,third})
assert(files[results[1]..'/data/computer.txt']=='from computer')
assert(files[results[2]..'/data/computer.txt']=='from computer')
local snapshots=M.snapshots(dest)
assert(#snapshots==1 and snapshots[1].name:find('Computador / computer.txt',1,true))
local restored=M.restore(results[1],dest,src)
assert(files[restored..'/computer.txt']=='from computer')
''')
test('selected folder backup preserves top folder and empty descendants', r'''
files['work']=true; files['work/sub']=true; files['work/sub/empty']=true; files['work/a']='A'
local result=M.backupItemMany('work','Computador / work','computador-1',{dest})[1]
assert(files[result..'/data/work']==true and files[result..'/data/work/sub/empty']==true)
assert(files[result..'/data/work/a']=='A')
''')
test('root RAID copies everything and removes extra destination files', RAID + '''
files['disk/.diskdesk-backups']=true; files['disk/.diskdesk-backups/keep']='history'
files['disk2/extra']='old unrelated'
M.raidConfigure(src,dest,'root'); assert(M.raidSync()=='Sincronizado')
assert(files['disk2/root.txt']=='root' and files['disk2/docs/a.bin']==files['disk/docs/a.bin'])
assert(files['disk2/.diskdesk-backups/keep']=='history' and not files['disk2/RAID1'])
assert(not files['disk2/extra'] and not files['disk2/.diskdesk-raid-journal'])
files['disk/root.txt']=nil; M.raidSync(); assert(not files['disk2/root.txt'])
''')
test('root RAID recovers interrupted publication', RAID + '''
M.raidConfigure(src,dest,'root'); M.raidSync(); files['disk/root.txt']='new'
local move=fs.move
fs.move=function(a,b)
  if a=='disk2/.diskdesk-raid-next/root.txt' then error('root commit failure') end
  move(a,b)
end
fails(function() M.raidSync() end,'root commit failure')
assert(files['disk2/.diskdesk-raid-old/root.txt']=='root')
fs.move=move; M.raidSync()
assert(files['disk2/root.txt']=='new' and not files['disk2/.diskdesk-raid-old'])
''')
test('multiple RAID mirrors sync independently', RAID + '''
files.disk3=true; volumes.top={root='disk3',id=30}
peripheral.getNames=function() return {'left','right','top'} end
peripheral.hasType=function(n,t) return t=='drive' end
M.raidConfigure(src,{dest,M.capture('top')},'root'); M.raidSync()
assert(files['disk2/root.txt']=='root' and files['disk3/root.txt']=='root')
volumes.right=nil; files['disk/root.txt']='changed'
assert(M.raidSync()=='Degradado' and files['disk3/root.txt']=='changed')
fails(function() M.assertWritable('disk3/new') end,'protegido')
''')
test('DDZ compresses repeated text and restores full folder', r'''
files['disk/docs/repeated.txt']=string.rep('abcabcabc',3000)
files['disk/docs/empty']=true
local raw,packed=M.compress('disk/docs','disk2/docs.ddz')
assert(packed<raw)
M.extract('disk2/docs.ddz','disk2/unpacked')
assert(files['disk2/unpacked/docs/repeated.txt']==files['disk/docs/repeated.txt'])
assert(files['disk2/unpacked/docs/a.bin']==files['disk/docs/a.bin'])
assert(files['disk2/unpacked/docs/empty']==true)
''')
test('DDZ2 tiny folder has compact metadata and preserves both files', '''
files['disk/pessoal']=true
files['disk/pessoal/a.txt']='12345678'; files['disk/pessoal/b.txt']='123456789'
local raw,packed=M.compress('disk/pessoal','disk2/small.ddz')
assert(raw==17 and packed<80, 'tiny archive too large: '..packed)
assert(files['disk2/small.ddz']:sub(1,4)=='DDZ2')
M.extract('disk2/small.ddz','disk2/small')
assert(files['disk2/small/pessoal/a.txt']=='12345678' and files['disk2/small/pessoal/b.txt']=='123456789')
print('DDZ2 example: 17 bytes of content -> '..packed..' bytes including names and index')
''')
test('DDZ1 legacy archive remains readable', '''
local raw='old binary'..string.char(0,255)
local header=textutils.serialize({version=1,entries={{path='old.bin',dir=false,size=#raw,packed=#raw,hash=M.checksum(raw),codec='raw'}}})
files['disk2/legacy.ddz']='DDZ1\\n'..#header..'\\n'..header..raw
M.extract('disk2/legacy.ddz','disk2/legacy')
assert(files['disk2/legacy/old.bin']==raw)
''')
test('DDZ2 corrupt index and truncated payload never create destination', '''
M.compress('disk/docs','disk2/test.ddz')
local original=files['disk2/test.ddz']
for _,value in ipairs({original:sub(1,8), original:sub(1,-2), original:sub(1,10)..'X'..original:sub(12)}) do
  files['disk2/test.ddz']=value
  assert(not pcall(M.extract,'disk2/test.ddz','disk2/out'))
  assert(not files['disk2/out'] and not files['disk2/out.partial'])
end
''')
test('DDZ empty file and empty folder', '''
files['disk/zero']=''
M.compress('disk/zero','disk2/zero.ddz'); M.extract('disk2/zero.ddz','disk2/zero')
assert(files['disk2/zero/zero']=='')
M.compress('disk/empty','disk2/empty.ddz'); M.extract('disk2/empty.ddz','disk2/empty')
assert(files['disk2/empty/empty']==true)
''')
test('DDZ rejects corruption before extraction', '''
M.compress('disk/root.txt','disk2/test.ddz')
files['disk2/test.ddz']=files['disk2/test.ddz']:sub(1,-2)..'X'
fails(function() M.extract('disk2/test.ddz','disk2/output') end,'corrompido')
assert(not files['disk2/output.partial'] and not files['disk2/output'])
''')
test('DDZ rejects malicious paths', '''
local header=textutils.serialize({version=1,entries={{path='../startup',dir=true}}})
files['disk2/evil.ddz']='DDZ1\\n'..#header..'\\n'..header
fails(function() M.extract('disk2/evil.ddz','disk2/output') end,'Caminho')
assert(not files.startup and not files['disk2/output.partial'])
''')
test('DDZ refuses overwrites and archive inside source', '''
fails(function() M.compress('disk/docs','disk/docs/self.ddz') end,'fora')
files['disk2/existing.ddz']='keep'
fails(function() M.compress('disk/root.txt','disk2/existing.ddz') end,'existe')
assert(files['disk2/existing.ddz']=='keep')
''')
test('move binary file verifies then removes original', r'''
M.moveItem('disk/docs/a.bin','disk2/a.bin')
assert(files['disk2/a.bin']=='hello\0\255\nworld' and not files['disk/docs/a.bin'])
''')
test('move folder preserves empty directories', '''
files['disk/docs/empty']=true
M.moveItem('disk/docs','disk2/docs')
assert(not files['disk/docs'] and files['disk2/docs/empty']==true)
assert(files['disk2/docs/a.bin'])
''')
test('move failure preserves original', '''
corrupt=true; fails(function() M.moveItem('disk/root.txt','disk2/root.txt') end,'verificacao')
assert(files['disk/root.txt']=='root' and not files['disk2/root.txt'])
''')
test('move rejects own child and existing target', '''
fails(function() M.moveItem('disk/docs','disk/docs/child') end,'propria')
files['disk2/root.txt']='keep'
fails(function() M.moveItem('disk/root.txt','disk2/root.txt') end,'existe')
assert(files['disk/root.txt']=='root' and files['disk2/root.txt']=='keep')
''')

NETWORK = r'''
-- Real sender and receiver service functions, scheduled like two CC computers.
files['sender']=true; files['receiver']=true
files['sender/file.bin']=emptyFile and '' or string.rep('abcdef\0\255',3000)
local queue,timers,workers,modules,results,errors={},{},{},{},{},{}
local timerID,steps=0,0
local drops,duplicates=0,0
local function endpoint(id)
  local env=setmetatable({}, {__index=_G})
  env.os=setmetatable({getComputerID=function() return id end,
    pullEvent=function() return coroutine.yield() end,
    startTimer=function(seconds)
      timerID=timerID+1; timers[timerID]={id=id,at=now+seconds}; return timerID
    end,
    cancelTimer=function(t) timers[t]=nil end}, {__index=os})
  env.rednet={isOpen=function() return false end,open=function() end,close=function() end,
    send=function(peer,msg,protocol)
      if dropKind==msg.kind and (dropAll or drops==0) then drops=drops+1; return true end
      if badData and msg.kind=='chunk' then msg.data='X'..msg.data:sub(2) end
      local function push() queue[#queue+1]={id=peer,event={'rednet_message',id,msg,protocol}} end
      push()
      if duplicateChunks and msg.kind=='chunk' and duplicates==0 then push(); duplicates=duplicates+1 end
      return true
    end}
  return assert(load(serviceSource,'endpoint','t',env))()
end
modules[1],modules[2]=endpoint(1),endpoint(2)
local receiverGuard=function() if ejectOnReceive then error('disk removed') end end
workers[2]=coroutine.create(function()
  local ok,result=pcall(modules[2].receiveFile,'receiver',receiverGuard,function()
    return not refuse
  end)
  if ok then results[2]=result else errors[2]=result end
end)
workers[1]=coroutine.create(function()
  local ok,result=pcall(modules[1].sendFile,'sender/file.bin',2)
  if ok then results[1]=result else errors[1]=result end
end)
local function resume(id,event)
  if coroutine.status(workers[id])=='dead' then
    if event[1]=='rednet_message' then modules[id].handleMessage(event[2],event[3],event[4]) end
    return
  end
  local ok,err=coroutine.resume(workers[id],table.unpack(event)); assert(ok,err)
end
resume(2,{}); resume(1,{})
while coroutine.status(workers[1])~='dead' or coroutine.status(workers[2])~='dead' do
  steps=steps+1; assert(steps<1000,'scheduler stalled')
  local message=table.remove(queue,1)
  if message then
    now=now+0.001; resume(message.id,message.event)
  else
    local nextID,nextTimer
    for id,timer in pairs(timers) do
      if not nextTimer or timer.at<nextTimer.at then nextID,nextTimer=id,timer end
    end
    assert(nextTimer,'no event or timer available')
    now=nextTimer.at; timers[nextID]=nil; resume(nextTimer.id,{'timer',nextID})
  end
end
if expectError then
  assert(errors[1], 'sender unexpectedly succeeded')
  assert(not files['receiver/file.bin'], 'published failed transfer')
else
  assert(not errors[1] and not errors[2],tostring(errors[1])..' | '..tostring(errors[2]))
  assert(results[1] and results[2])
  assert(files[results[2]]==files['sender/file.bin'])
end
'''

for name, setup in [
    ('binary wireless transfer', ''),
    ('empty wireless file', 'emptyFile=true'),
    ('lost acceptance', "dropKind='accept'"),
    ('lost chunk acknowledgement', "dropKind='ack'"),
    ('lost final acknowledgement', "dropKind='done'"),
    ('duplicate chunk', 'duplicateChunks=true'),
    ('receiver refusal', 'refuse=true; expectError=true'),
    ('receiver disk full', 'free=1; expectError=true'),
    ('corrupt wireless data', 'badData=true; expectError=true'),
    ('all acknowledgements lost', "dropKind='ack'; dropAll=true; expectError=true"),
    ('destination name collision', "files['receiver/file.bin']='keep'"),
]:
    test(name, setup + '\n' + NETWORK + ("\nassert(files['receiver/file.bin']=='keep')" if 'collision' in name else ''))

test('malicious wireless filename rejected', r'''
rednet={isOpen=function() return true end}
os.startTimer=function() return 1 end; os.cancelTimer=function() end
os.pullEvent=function() return 'rednet_message',2,{kind='offer',token='x',name='../startup',size=0,hash=1},M.protocol end
fails(function() M.receiveFile('disk2',nil,function() error('should not ask') end) end,'invalida')
assert(not files.startup)
''')
