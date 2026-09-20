"""Real Lua archive-array roundtrips, erasures, corruption and publication faults."""
import ast
from pathlib import Path
from lupa import LuaRuntime

root = Path(__file__).parent
tree = ast.parse((root / 'test_services.py').read_text(encoding='utf-8'))
base = next(ast.literal_eval(node.value) for node in tree.body
            if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'BASE' for t in node.targets))
setup = r'''
A=assert(load(arraySource))()(M)
volumes={}; allVolumes={}; units={}
for i=1,9 do
  local name='drive'..i; local volume={root='member'..i,id=i}
  volumes[name]=volume; allVolumes[name]=volume; files[volume.root]=true
  units[i]=M.capture(name)
end
peripheral.getNames=function() local names={}; for name in pairs(volumes) do names[#names+1]=name end; return names end
peripheral.hasType=function(name,kind) return kind=='drive' and volumes[name]~=nil end
fs.isDriveRoot=function(p) return p=='' or p:match('^member%d+$')~=nil or p=='disk' or p=='disk2' end
files['original']=true; files['original/vazia']=true
local bytes={}; local seed=917
for i=1,53000 do seed=(seed*1664525+1013904223)%4294967296; bytes[i]=string.char(math.floor(seed/65536)%256) end
files['original/dados.bin']=table.concat(bytes); files['original/notas.txt']='oi mundo!'
payload=M.archivePack('original')
function create(mode,n)
  local selected={}; for i=1,n do selected[i]=units[i] end
  return A.create(payload,'original',mode,selected)
end
function remove(i) volumes['drive'..i]=nil end
function reconnect() for k,v in pairs(allVolumes) do volumes[k]=v end end
function checkRestore(m,target)
  A.restore(m,target)
  assert(files[target..'/original/dados.bin']==files['original/dados.bin'])
  assert(files[target..'/original/notas.txt']=='oi mundo!')
  assert(files[target..'/original/vazia']==true)
end
'''

def test(name, script):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().serviceSource = (root / 'diskdesk_services.lua').read_text(encoding='utf-8')
    lua.globals().arraySource = (root / 'diskdesk_arrays.lua').read_text(encoding='utf-8')
    lua.execute(base + setup + script)
    print('PASS:', name, flush=True)

test('all levels roundtrip binary data and empty dirs', '''
for _,mode in ipairs({'0','1','5','6','10'}) do
  local m=create(mode,4); checkRestore(m,'out'..mode)
  assert(A.status(m).text=='Integro')
end
assert(#A.list()==5)
''')
test('RAID0 refuses every missing member without output', '''
local m=create('0',4)
for i=1,4 do
  remove(i); assert(not A.status(m).readable)
  assert(not pcall(A.restore,m,'out')); assert(not files.out); reconnect()
end
''')
test('RAID1 survives all but one member', '''
local m=create('1',4)
for kept=1,4 do
  for i=1,4 do if i~=kept then remove(i) end end
  checkRestore(m,'one'..kept); reconnect()
end
''')
test('RAID5 recovers every single member with rotating parity', '''
local m=create('5',5)
for i=1,5 do remove(i); checkRestore(m,'five'..i); reconnect() end
remove(1); remove(2); assert(not A.status(m).readable)
assert(not pcall(A.restore,m,'failed')); assert(not files.failed)
''')
test('RAID6 recovers every pair among eight disks', '''
local m=create('6',8)
for i=1,8 do
  for j=i+1,8 do
    remove(i); remove(j); checkRestore(m,'six'..i..'-'..j); reconnect()
  end
end
remove(1); remove(2); remove(3); assert(not pcall(A.restore,m,'failed'))
''')
test('RAID10 every two-disk failure respects mirror pairs', '''
local m=create('10',6)
for i=1,6 do
  for j=i+1,6 do
    remove(i); remove(j)
    if math.ceil(i/2)==math.ceil(j/2) then
      assert(not A.status(m).readable); assert(not pcall(A.restore,m,'failed'))
    else checkRestore(m,'ten'..i..'-'..j) end
    reconnect()
  end
end
''')
test('RAID6 corruption plus missing disk, rebuild on replacements', '''
local m=create('6',4); local path='member1/.diskdesk-arrays/'..m.id..'/shard'
files[path]='X'..files[path]:sub(2); remove(2)
assert(#A.status(m).missing==2); checkRestore(m,'corrupt')
A.rebuild(m,1,units[5]); A.rebuild(m,2,units[6])
assert(A.status(m).text=='Integro'); remove(3); remove(4)
checkRestore(m,'rebuilt'); assert(files[path]:sub(1,1)=='X')
''')
test('fresh loader discovers replacement IDs without PC config', '''
local m=create('5',3); remove(1); A.rebuild(m,1,units[4]); remove(2)
A=assert(load(arraySource))()(M)
local sets=A.list(); assert(#sets==1); checkRestore(sets[1],'fresh')
''')
test('invalid layouts, duplicate disks, no room and no overwrites', '''
assert(not pcall(create,'5',2)); assert(not pcall(create,'6',3)); assert(not pcall(create,'10',5))
assert(not pcall(A.create,payload,'original','0',{units[1],units[1]}))
free=1; assert(not pcall(create,'5',3)); assert(#A.list()==0); free=10000000
local m=create('5',3); files.existing=true
assert(not pcall(A.restore,m,'existing')); remove(1)
assert(not pcall(A.rebuild,m,1,units[2]))
''')
test('bad staged write never publishes a set', '''
corrupt=true; assert(not pcall(create,'6',4)); corrupt=false
assert(#A.list()==0); assert(files['original/dados.bin'])
''')
test('disk swap while staging stops publication', '''
local write=fs.open
fs.open=function(path,mode)
  local f=write(path,mode)
  if mode=='wb' then
    local original=f.write
    f.write=function(data) original(data); volumes.drive2={root='member2',id=99} end
  end
  return f
end
assert(not pcall(create,'5',3)); assert(#A.list()==0)
''')
test('interrupted publication preserves previous set', '''
local previous=create('5',3); local move=fs.move; local count=0
fs.move=function(a,b)
  count=count+1; if count==2 then error('power loss') end; move(a,b)
end
assert(not pcall(create,'5',3)); checkRestore(previous,'previous')
local sets=A.list(); assert(#sets==2)
for _,m in ipairs(sets) do if m.id~=previous.id then assert(not A.status(m).readable) end end
''')
