"""Virtual filesystem integration and fault tests in real Lua with bounded disks."""
import ast
from pathlib import Path
from lupa import LuaRuntime

root = Path(__file__).parent
tree = ast.parse((root / 'test_services.py').read_text(encoding='utf-8'))
base = next(ast.literal_eval(node.value) for node in tree.body
            if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'BASE' for t in node.targets))
setup = r'''
volumes={}; allVolumes={}; units={}; capacities={}
for i=1,9 do
  local name='drive'..i; local volume={root='member'..i,id=i}
  volumes[name]=volume; allVolumes[name]=volume; files[volume.root]=true
  capacities[volume.root]=128*1024; units[i]=M.capture(name)
end
local function mount(path) return path:match('^(member%d+)') or '' end
fs.getCapacity=function(path) return capacities[mount(path)] or 2*1024*1024 end
fs.getFreeSpace=function(path)
  local root=mount(path); local used=0
  for p,value in pairs(files) do
    if p~=root and mount(p)==root then used=used+(value==true and 500 or math.max(500,#value)) end
  end
  return math.max(0,fs.getCapacity(path)-used)
end
local originalOpen=fs.open
fs.open=function(path,mode)
  local handle,err=originalOpen(path,mode)
  if handle and mode:sub(1,1)=='w' then
    local write=handle.write
    handle.write=function(value)
      if #value>fs.getFreeSpace(path) then error('disk full',0) end
      write(value)
    end
  end
  return handle,err
end
peripheral.getNames=function() local names={}; for name in pairs(volumes) do names[#names+1]=name end; return names end
peripheral.hasType=function(name,kind) return kind=='drive' and volumes[name]~=nil end
fs.isDriveRoot=function(path) return path=='' or path:match('^member%d+$')~=nil or path=='disk' or path=='disk2' end
arrayFactory=assert(load(arraySource))()
volumeFactory=assert(load(volumeSource))()
function restart()
  V=volumeFactory(M,arrayFactory); F=V.fs; M.useFilesystem(F)
end
restart()
function create(mode,n)
  local selected={}; for i=1,n do selected[i]=units[i] end
  local c=V.create('Trabalho',mode,selected); rootPath=V.root(c); return c
end
function put(path,data)
  local f,err=F.open(path,'wb'); assert(f,err); f.write(data); f.close()
end
function get(path)
  local f,err=F.open(path,'rb'); assert(f,err); local data=f.readAll(); f.close(); return data
end
function remove(i) volumes['drive'..i]=nil end
function reconnect() for k,v in pairs(allVolumes) do volumes[k]=v end end
'''

def test(name, script):
    lua = LuaRuntime(unpack_returned_tuples=True)
    for key, name_ in [('serviceSource', 'diskdesk_services.lua'), ('arraySource', 'diskdesk_arrays.lua'),
                       ('volumeSource', 'diskdesk_volumes.lua')]:
        lua.globals()[key] = (root / name_).read_text(encoding='utf-8')
    lua.execute(base + setup + script)
    print('PASS:', name, flush=True)

for mode, count, useful in [('0', 2, 2), ('1', 2, 1), ('5', 3, 2), ('6', 5, 3), ('10', 4, 2)]:
    test(f'RAID {mode}: aggregate capacity and immediate raw file distribution', f'''
local c=create('{mode}',{count})
assert(F.getCapacity(rootPath)==(128*1024-8192)*{useful})
local before=F.getFreeSpace(rootPath)
local data=string.rep('0123456789abcdef',4096)..string.char(0,255)
put(rootPath..'/grande.bin',data)
assert(get(rootPath..'/grande.bin')==data)
assert(F.getSize(rootPath..'/grande.bin')==#data)
assert(F.getFreeSpace(rootPath)<before)
local entry=V.list()[1].entries['grande.bin']
assert(entry.object.size==#data+1, 'normal volume writes must not compress')
for i=1,{count} do
  local p='member'..i..'/.diskdesk-vdata/'..entry.object.id..'/shard'
  assert(type(files[p])=='string' and #files[p]==entry.object.shardSize)
end
restart(); assert(get(rootPath..'/grande.bin')==data)
''')

test('create nested dirs, rename, append, replace, delete and reclaim', '''
create('0',2); local freeBefore=F.getFreeSpace(rootPath)
F.makeDir(rootPath..'/PESSOAL/VAZIA')
put(rootPath..'/PESSOAL/TESTE LEGAL1','old')
local handle=assert(F.open(rootPath..'/PESSOAL/TESTE LEGAL1','a')); handle.write(' appended'); handle.close()
assert(get(rootPath..'/PESSOAL/TESTE LEGAL1')=='old appended')
F.move(rootPath..'/PESSOAL',rootPath..'/RENOMEADA')
assert(F.isDir(rootPath..'/RENOMEADA/VAZIA'))
put(rootPath..'/RENOMEADA/TESTE LEGAL1',string.rep('x',20000))
local used=F.getFreeSpace(rootPath)
F.delete(rootPath..'/RENOMEADA')
assert(not F.exists(rootPath..'/RENOMEADA') and F.getFreeSpace(rootPath)>used)
assert(F.getFreeSpace(rootPath)==freeBefore)
restart(); assert(#F.list(rootPath)==0)
''')
test('move real file to volume verifies before removing source; move back', '''
create('5',3); files['disk/real.bin']=string.rep('a',22000)..string.char(0,255)
local expected=files['disk/real.bin']
M.moveItem('disk/real.bin',rootPath..'/real.bin')
assert(not files['disk/real.bin'] and get(rootPath..'/real.bin')==expected)
M.moveItem(rootPath..'/real.bin','disk2/back.bin')
assert(files['disk2/back.bin']==expected and not F.exists(rootPath..'/real.bin'))
''')
test('full disk leaves move source and previous virtual content intact', '''
create('0',2); put(rootPath..'/old','keep')
files['member2/filler']=string.rep('x',fs.getFreeSpace('member2')-512)
files['disk/source']='do not remove'
assert(not pcall(M.moveItem,'disk/source',rootPath..'/source'))
assert(files['disk/source']=='do not remove' and get(rootPath..'/old')=='keep')
assert(not pcall(put,rootPath..'/old',string.rep('new',5000)))
assert(get(rootPath..'/old')=='keep')
''')
test('RAID6 reads after two losses, rejects writes, restores after reconnect', '''
local c=create('6',5); put(rootPath..'/test',string.rep('test',8000))
remove(1); remove(4)
assert(V.info(c).text=='Degradado' and F.isReadOnly(rootPath))
assert(get(rootPath..'/test')==string.rep('test',8000))
assert(not pcall(put,rootPath..'/test','bad')); assert(not pcall(F.delete,rootPath..'/test'))
remove(3); assert(not pcall(get,rootPath..'/test'))
reconnect(); put(rootPath..'/test','new'); assert(get(rootPath..'/test')=='new')
''')
test('RAID0 refuses reads with any member missing', '''
local c=create('0',2); put(rootPath..'/test','abc'); remove(1)
assert(V.info(c).text=='Indisponivel'); assert(not pcall(get,rootPath..'/test'))
''')
test('RAID10 reads with one missing per pair, fails with whole pair', '''
create('10',4); put(rootPath..'/test','abc'); remove(1); remove(3)
assert(get(rootPath..'/test')=='abc'); remove(2)
assert(not pcall(get,rootPath..'/test'))
''')
test('rebuild all files onto replacement, then resume writing', '''
local c=create('6',5); put(rootPath..'/first',string.rep('a',12000)); put(rootPath..'/second','bbb')
remove(1); local updated=V.rebuild(c,1,units[6]); assert(updated.members[1]==6)
put(rootPath..'/third','after rebuilding')
restart(); remove(2); remove(3)
assert(get(rootPath..'/first')==string.rep('a',12000))
assert(get(rootPath..'/third')=='after rebuilding')
''')
test('RAID6 rebuilds two absent members in successive steps', '''
local c=create('6',5); put(rootPath..'/first',string.rep('a',10000))
remove(1); remove(2)
local next=V.rebuild(c,1,units[6]); assert(V.info(next).text=='Degradado')
next=V.rebuild(next,2,units[7]); assert(V.info(next).writable)
put(rootPath..'/second','new'); restart(); remove(3); remove(4)
assert(get(rootPath..'/first')==string.rep('a',10000) and get(rootPath..'/second')=='new')
''')
test('disk swap during striped write preserves previous content', '''
create('5',3); put(rootPath..'/first','previous')
local open=fs.open
fs.open=function(path,mode)
  local f,err=open(path,mode)
  if f and mode=='wb' and path:find('/shard',1,true) then
    local write=f.write
    f.write=function(s) write(s); volumes.drive2={root='member2',id=999} end
  end
  return f,err
end
assert(not pcall(put,rootPath..'/first','new')); fs.open=open; reconnect()
restart(); assert(get(rootPath..'/first')=='previous')
''')
test('import catalogs on another computer recovers files and empty dirs', '''
create('5',3); F.makeDir(rootPath..'/empty'); put(rootPath..'/test','recovered')
fs.delete('.diskdesk-volumes'); restart(); assert(#V.list()==0)
assert(V.import()==1); assert(get(rootPath..'/test')=='recovered'); assert(F.isDir(rootPath..'/empty'))
''')
test('catalog publication failure preserves previous file across restart', '''
create('0',2); put(rootPath..'/test','original')
local move=fs.move
fs.move=function(a,b)
  if a:find('.diskdesk-volumes/',1,true)==1 and a:sub(-5)=='.next' then error('power loss') end
  return move(a,b)
end
assert(not pcall(put,rootPath..'/test','replacement')); fs.move=move
restart(); assert(get(rootPath..'/test')=='original')
''')
test('catalog recovery between old and new rename', '''
local c=create('1',2); put(rootPath..'/test','keep')
local p='.diskdesk-volumes/'..c.id..'/catalog'; fs.move(p,p..'.previous')
restart(); assert(get(rootPath..'/test')=='keep')
''')
test('metadata corruption refuses import; physical internal files protected', '''
local c=create('5',3); put(rootPath..'/test','keep')
assert(not pcall(F.delete,'.diskdesk-volumes/'..c.id))
assert(not pcall(F.delete,'member1/.diskdesk-vdata'))
assert(F.isReadOnly('member1/.diskdesk-vdata'))
for i=1,3 do files['member'..i..'/.diskdesk-vdata/volume-'..c.id..'/catalog']='bad' end
fs.delete('.diskdesk-volumes'); restart(); assert(V.import()==0)
''')
test('empty file, binary reads, handles and unchanged metadata operations', r'''
create('1',2); put(rootPath..'/zero',''); assert(get(rootPath..'/zero')=='')
put(rootPath..'/binary',string.char(0,255)..'\ntext\n')
local f=assert(F.open(rootPath..'/binary','rb')); assert(f.read()==0 and f.read(1)==string.char(255))
assert(f.readLine()==''); assert(f.readLine()=='text'); assert(f.readAll()==''); f.close()
assert(not pcall(f.read))
''')
test('compression and extraction through virtual filesystem', '''
create('5',3); F.makeDir(rootPath..'/docs'); put(rootPath..'/docs/a',string.rep('abc',1000))
M.compress(rootPath..'/docs','disk2/docs.ddz')
M.extract('disk2/docs.ddz',rootPath..'/restored')
assert(get(rootPath..'/restored/docs/a')==string.rep('abc',1000))
''')
test('delete volume removes its data and catalogs but preserves physical files', '''
local c=create('5',3); put(rootPath..'/test','delete me')
for i=1,3 do files['member'..i..'/keep.txt']='preserve' end
V.delete(c)
assert(#V.list()==0 and not fs.exists('.diskdesk-volumes/'..c.id))
for i=1,3 do
  assert(files['member'..i..'/keep.txt']=='preserve')
  assert(not fs.exists('member'..i..'/.diskdesk-vdata/volume-'..c.id))
end
restart(); assert(#V.list()==0 and V.import()==0)
''')
test('delete volume requires every member', '''
local c=create('1',2); put(rootPath..'/test','keep'); remove(2)
assert(not pcall(V.delete,c)); reconnect(); restart()
assert(get(rootPath..'/test')=='keep')
''')

# Drive the real explorer with the same storage mock to cover UI -> virtual FS -> stripes.
ui_tree = ast.parse((root / 'test_diskdesk.py').read_text(encoding='utf-8'))
ui_mock = next(ast.literal_eval(node.value) for node in ui_tree.body
               if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'MOCK' for t in node.targets))
lua = LuaRuntime(unpack_returned_tuples=True)
for key, file in [('serviceSource', 'diskdesk_services.lua'), ('arraySource', 'diskdesk_arrays.lua'),
                  ('volumeSource', 'diskdesk_volumes.lua')]:
    lua.globals()[key] = (root / file).read_text(encoding='utf-8')
lua.execute(ui_mock + '\nuiKeys=keys\n' + base + setup + r'''
keys=uiKeys
for i=3,9 do remove(i) end
os.epoch=function() return 1000 end
files['entrada.txt']=string.rep('linha teste\n',500)
local original=files['entrada.txt']
dofile=function(path)
  if path:find('diskdesk_services.lua',1,true) then return assert(load(serviceSource))() end
  if path:find('diskdesk_arrays.lua',1,true) then return assert(load(arraySource))() end
  if path:find('diskdesk_volumes.lua',1,true) then return function(s,a)
    activeVirtual=assert(load(volumeSource))()(s,a); return activeVirtual
  end end
  error('unexpected dofile '..path)
end
shell.execute=function(program,path)
  assert(program=='/rom/programs/edit.lua' and path:find('/.diskdesk-edit/',1,true)==1)
  files[path:sub(2)]=original..'editado'
  return true
end
-- Create RAID 0 via the actual menu and checkbox selection.
char('a'); key('down'); key('down'); key('enter'); key('enter')
key('enter'); key('enter'); key('enter'); key('down'); key('enter'); key('up'); key('up'); key('enter')
answer('Trabalho'); char('s')
-- Return to Computer, select real file, move to the new virtual drive and edit it.
char('d'); key('up'); key('up'); key('up'); key('enter')
char('f'); answer('entrada.txt'); char('m')
char('d'); key('down'); key('down'); key('down'); key('enter'); char('v')
char('e'); char('n'); answer('PESSOAL'); char('q')
''')
lua.execute((root / 'diskdesk.lua').read_text(encoding='utf-8'))
lua.execute(r'''
assert(output[#output]=='DiskDesk encerrado.',table.concat(output,' | '))
assert(#messages==0,table.concat(messages,' | '))
assert(not files['entrada.txt'])
local list=activeVirtual.list(); assert(#list==1 and list[1].mode=='0')
local path=activeVirtual.root(list[1]); local f=assert(activeVirtual.fs.open(path..'/entrada.txt','rb'))
assert(f.readAll()==string.rep('linha teste\n',500)..'editado'); f.close()
assert(activeVirtual.fs.isDir(path..'/PESSOAL'))
assert(activeVirtual.fs.getCapacity(path)==(128*1024-8192)*2)
''')
print('PASS: real explorer creates virtual RAID, moves, edits and makes folders', flush=True)
