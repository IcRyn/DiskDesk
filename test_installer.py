"""Installer tests. Requires lupa; shares the filesystem mock with service tests."""
import ast
from pathlib import Path
from lupa import LuaRuntime

root = Path(__file__).parent
tree = ast.parse((root / 'test_services.py').read_text(encoding='utf-8'))
base = next(ast.literal_eval(node.value) for node in tree.body
            if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'BASE' for t in node.targets))
installer = (root / 'instalar_diskdesk.lua').read_text(encoding='utf-8')
setup = '''
colors={lightGray=1,black=2,blue=3,white=4}
term={setBackgroundColor=function() end,setTextColor=function() end,
      clear=function() end,setCursorPos=function() end}
output,answers={}, {'s','n'}
print=function(s) output[#output+1]=tostring(s) end
write=function() end
read=function() local value=table.remove(answers,1); assert(value,'missing answer'); return value end
shell={run=function(path) launched=path end}
'''

def test(name, before, check):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().serviceSource = (root / 'diskdesk_services.lua').read_text(encoding='utf-8')
    lua.globals().expectedMain = (root / 'diskdesk.lua').read_text(encoding='utf-8')
    lua.globals().expectedService = (root / 'diskdesk_services.lua').read_text(encoding='utf-8')
    lua.globals().expectedArrays = (root / 'diskdesk_arrays.lua').read_text(encoding='utf-8')
    lua.globals().expectedVolumes = (root / 'diskdesk_volumes.lua').read_text(encoding='utf-8')
    lua.execute(base + setup + before)
    lua.execute(installer)
    lua.execute(check)
    print('PASS:', name)

test('fresh installation matches source bytes', '', '''
assert(files['diskdesk-app/diskdesk.lua']==expectedMain)
assert(files['diskdesk-app/diskdesk_services.lua']==expectedService)
assert(files['diskdesk-app/diskdesk_arrays.lua']==expectedArrays)
assert(files['diskdesk-app/diskdesk_volumes.lua']==expectedVolumes)
assert(files['diskdesk.lua']:find('/diskdesk-app/diskdesk.lua',1,true))
assert(not files['diskdesk-backup-1000'])
''')
test('update preserves previous installation', '''
files['diskdesk-app']=true; files['diskdesk-app/diskdesk.lua']='old app'
files['diskdesk.lua']='old launcher'; files['startup.lua']='existing startup'
files['.diskdesk-volumes']=true; files['.diskdesk-volumes/config']='virtual catalog'
files['disk/.diskdesk-vdata']=true; files['disk/.diskdesk-vdata/shard']='virtual data'
''', '''
assert(files['diskdesk-backup-1000/previous/app/diskdesk.lua']=='old app')
assert(files['diskdesk-backup-1000/previous/diskdesk.lua']=='old launcher')
assert(files['diskdesk-app/diskdesk.lua']==expectedMain)
assert(files['startup.lua']=='existing startup')
assert(files['.diskdesk-volumes/config']=='virtual catalog')
assert(files['disk/.diskdesk-vdata/shard']=='virtual data')
''')
test('cancel leaves filesystem alone', "answers={'n'}", "assert(not files['diskdesk-app'] and not files['diskdesk.lua'])")
test('insufficient space leaves prior version', "free=1; files['diskdesk.lua']='old'",
     "assert(files['diskdesk.lua']=='old' and not files['diskdesk-app'])")
test('corrupt staging leaves prior version', "corrupt=true; files['diskdesk.lua']='old'",
     "assert(files['diskdesk.lua']=='old' and not files['diskdesk-app'])")
test('publish failure rolls back', '''
files['diskdesk-app']=true; files['diskdesk-app/diskdesk.lua']='old app'
files['diskdesk.lua']='old launcher'
local move=fs.move
fs.move=function(a,b)
  if a=='diskdesk-backup-1000/new/launcher' then error('simulated commit failure') end
  move(a,b)
end
''', '''
assert(files['diskdesk-app/diskdesk.lua']=='old app')
assert(files['diskdesk.lua']=='old launcher')
assert(files['diskdesk-backup-1000/failed-app/diskdesk.lua']==expectedMain)
''')
test('optional launch', "answers={'s','s'}", "assert(launched=='/diskdesk-app/diskdesk.lua')")
test('read-only destination', "fs.isReadOnly=function() return true end",
     "assert(not files['diskdesk-app'] and not files['diskdesk.lua'])")
test('command name conflict', "files.diskdesk='unrelated program'",
     "assert(files.diskdesk=='unrelated program' and not files['diskdesk.lua'])")
