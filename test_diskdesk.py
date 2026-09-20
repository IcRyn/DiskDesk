"""Smoke tests with Lua mocks, not an in-game CC: Tweaked integration test.

Requires the Python package lupa. Run: python test_diskdesk.py
"""
from pathlib import Path
from lupa import LuaRuntime

SOURCE = Path(__file__).with_name('diskdesk.lua').read_text(encoding='utf-8')
SERVICES = Path(__file__).with_name('diskdesk_services.lua').read_text(encoding='utf-8')
MOCK = r'''
colors = {black=1, white=2, blue=3, gray=4, lightGray=5, yellow=6, cyan=7, green=8, red=9}
keys = {up=1, down=2, enter=3, backspace=4, delete=5, q=6, escape=7, f1=8, left=9, right=10}
term = {}
for _, k in ipairs({'setBackgroundColor','setTextColor','setCursorPos','write',
  'clear','setCursorBlink'}) do term[k] = function() end end
screenW, screenH = 51, 19
term.getSize = function() return screenW, screenH end
messages = {}
screen, snapshots = {}, {}
local cursorX, cursorY, foreground, background = 1, 1, 2, 1
term.setCursorPos = function(x,y)
  assert(x>=1 and x<=screenW and y>=1 and y<=screenH, 'cursor out of bounds')
  cursorX, cursorY=x,y
end
term.setTextColor=function(c) assert(c); foreground=c end
term.setBackgroundColor=function(c) assert(c); background=c end
term.clear=function()
  screen={}
  for i=1,screenW*screenH do screen[i]={' ',foreground,background} end
end
term.write = function(s)
  if s:find('Erro:') then messages[#messages+1]=s end
  assert(cursorX+#s-1<=screenW, 'write out of bounds')
  for i=1,#s do
    screen[(cursorY-1)*screenW+cursorX+i-1]={s:sub(i,i),foreground,background}
  end
  cursorX=cursorX+#s
end
package.preload['cc.strings'] = function()
  return {wrap=function(s,w)
    local out = {}; for i=1,#s,w do out[#out+1]=s:sub(i,i+w-1) end
    return out
  end}
end
files = {['']='dir', ['disk']='dir', ['note.txt']='hello', ['disk/sub']='dir'}
mounted = true
fs = {}
fs.combine = function(a,b) return (a..'/'..b):gsub('^/',''):gsub('/$','') end
fs.exists = function(p) return files[p] ~= nil end
fs.isDir = function(p) return files[p] == 'dir' end
fs.getDir = function(p) return p:match('^(.*)/[^/]+$') or '' end
fs.getName = function(p) return p:match('[^/]+$') or '' end
fs.list = function(p)
  local r = {}
  for name in pairs(files) do
    if name ~= p and fs.getDir(name)==p then r[#r+1]=name:match('[^/]+$') end
  end
  return r
end
fs.getFreeSpace = function() return 10000 end
fs.getCapacity = function() return 20000 end
fs.getSize = function(p) return #files[p] end
fs.isReadOnly = function() return false end
fs.isDriveRoot = function(p) return p=='' or p=='disk' end
fs.open = function(p) return {readAll=function() return files[p] end, close=function() end} end
fs.makeDir = function(p) files[p]='dir' end
fs.copy = function(a,b) assert(not files[b]); files[b]=assert(files[a]) end
fs.move = function(a,b) fs.copy(a,b); files[a]=nil end
fs.delete = function(p) files[p]=nil end
disk = {
  getMountPath=function() if mounted then return 'disk' end end,
  getLabel=function() return 'Meu disco' end,
  getID=function() return 42 end,
  setLabel=function() end,
  eject=function() mounted=false; files.disk=nil; files['disk/sub']=nil end
}
pages, starts, ends, blockEnd, blockStart = {}, 0, 0, false, false
local page, row
printer = {
  newPage=function()
    if blockStart then blockStart=false; return false end
    assert(not page, 'overwrote pending page')
    starts=starts+1; page={}; return true
  end,
  getPageSize=function() return 5, 2 end,
  setPageTitle=function() end,
  setCursorPos=function(_,y) row=y end,
  write=function(s) page[row]=s end,
  endPage=function()
    ends=ends+1
    if blockEnd then blockEnd=false; return false end
    assert(page); pages[#pages+1]=page; page=nil; return true
  end
}
hasSpeaker, notes, speakerBroken = false, {}, false
speaker = {playNote=function(instrument,volume,pitch)
  if speakerBroken then error('disconnected') end
  notes[#notes+1]={instrument,volume,pitch}; return true
end}
peripheral = {
  getNames=function() return hasSpeaker and {'left','right','back'} or {'left','right'} end,
  hasType=function(n,t) return (n=='left' and t=='drive') or (n=='right' and t=='printer') or (hasSpeaker and n=='back' and t=='speaker') end,
  wrap=function(n) return n=='back' and speaker or printer end
}
shell = {run=function() end, execute=function() return true end,
  getRunningProgram=function() return 'diskdesk.lua' end}
dofile = function(path)
  if path:find('diskdesk_volumes.lua',1,true) then return assert(load(volumeSource))() end
  if path:find('diskdesk_arrays.lua',1,true) then return assert(load(arraySource))() end
  local module=assert(load(serviceSource))()
  if serviceOverride then serviceOverride(module) end
  return module
end
os.getComputerID = function() return 7 end
bootFrames={}
sleep = function() bootFrames[#bootFrames+1]=screen end
local timerID=0
os.startTimer=function() timerID=timerID+1; return timerID end
os.cancelTimer=function() end
events, answers, output = {}, {}, {}
os.pullEvent = function() return coroutine.yield() end
parallel = {waitForAny=function(...)
  local workers={}
  for _,fn in ipairs({...}) do workers[#workers+1]=coroutine.create(fn) end
  local event={}
  while true do
    for _,worker in ipairs(workers) do
      local ok,err=coroutine.resume(worker,table.unpack(event)); assert(ok,err)
      if coroutine.status(worker)=='dead' then return end
    end
    snapshots[#snapshots+1]=screen
    event=table.remove(events,1); assert(event,'event queue exhausted')
    if event.apply then event.apply() end
  end
end}
read = function() local s=table.remove(answers,1); assert(s, 'missing answer'); return s end
print = function(s) output[#output+1]=tostring(s) end
function char(c) events[#events+1]={'char',c} end
function key(k) events[#events+1]={'key',keys[k]} end
function answer(s) answers[#answers+1]=s end
function selectText() key('down') end
function chooseDisk() char('d'); key('down'); key('enter') end
function diskEvent(kind)
  events[#events+1]={kind,'left',apply=function()
    mounted=kind=='disk'
    files.disk=mounted and 'dir' or nil
    files['disk/sub']=mounted and 'dir' or nil
  end}
end
'''

def test(name, setup, check):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().serviceSource = SERVICES
    lua.globals().arraySource = Path(__file__).with_name('diskdesk_arrays.lua').read_text(encoding='utf-8')
    lua.globals().volumeSource = Path(__file__).with_name('diskdesk_volumes.lua').read_text(encoding='utf-8')
    lua.execute(MOCK)
    lua.execute(setup)
    lua.execute(SOURCE)
    lua.execute("assert(output[#output]=='DiskDesk encerrado.', table.concat(output,' | '))")
    lua.execute("assert(#messages==0, table.concat(messages,' | '))")
    lua.execute(check)
    print('PASS:', name)
    return lua

test('copy to floppy', "selectText(); char('c'); chooseDisk(); char('v'); char('q')",
     "assert(files['disk/note.txt']=='hello')")
test('create folder', "chooseDisk(); char('n'); answer('docs'); char('q')",
     "assert(files['disk/docs']=='dir')")
test('create text inside nested folder with spaces', '''
files['disk/sub/Meus textos']='dir'
shell.execute=function(program,...)
  assert(program=='/rom/programs/edit.lua' and select('#',...)==1)
  local path=...; assert(path=='/disk/sub/Meus textos/minha nota.txt')
  files[path:sub(2)]='conteudo salvo'; return true
end
chooseDisk(); key('enter'); key('enter'); char('t'); answer('minha nota.txt'); char('q')
''', "assert(files['disk/sub/Meus textos/minha nota.txt']=='conteudo salvo')")
test('edit existing filename with spaces', '''
files['minha nota.txt']='anterior'
shell.execute=function(program,...)
  assert(select('#',...)==1 and (...)=='/minha nota.txt')
  files['minha nota.txt']='novo'; return true
end
key('down'); char('e'); char('q')
''', "assert(files['minha nota.txt']=='novo')")
test('new text without saving has a visible notice', '''
local previous=term.write
term.write=function(s) if s:find('Nao foi salvo',1,true) then sawUnsaved=true end; previous(s) end
chooseDisk(); key('enter'); char('t'); answer('rascunho.txt'); char('q')
''', "assert(not files['disk/sub/rascunho.txt'] and sawUnsaved)")
test('cancel deletion', "selectText(); char('x'); char('n'); char('q')",
     "assert(files['note.txt']=='hello')")
test('eject', "chooseDisk(); char('j'); char('q')", "assert(not mounted)")
test('pagination', "files['note.txt']='12345678901'; selectText(); char('p'); char('s'); char('q')",
     "assert(#pages==2 and pages[1][1]=='12345' and pages[1][2]=='67890' and pages[2][1]=='1')")
test('resume full output', "blockEnd=true; selectText(); char('p'); char('s'); char('n'); char('p'); char('q')",
     "assert(#pages==1 and starts==1 and ends==2)")
test('resume missing paper', "blockStart=true; selectText(); char('p'); char('s'); char('n'); char('p'); char('q')",
     "assert(#pages==1 and starts==1)")
test('insert/remove sounds', "hasSpeaker=true; diskEvent('disk_eject'); diskEvent('disk'); char('q')",
     "assert(#notes==4 and notes[1][1]=='bass' and notes[3][1]=='pling')")
test('mute', "hasSpeaker=true; char('u'); diskEvent('disk_eject'); char('q')", "assert(#notes==0)")
test('no speaker', "diskEvent('disk_eject'); diskEvent('disk'); char('q')", "assert(#notes==0)")
test('speaker disconnect', "hasSpeaker=true; speakerBroken=true; diskEvent('disk_eject'); char('q')", "assert(#notes==0)")
test('sound inside help', "hasSpeaker=true; char('h'); diskEvent('disk_eject'); key('enter'); char('q')",
     "assert(#notes==2)")
test('search', "char('f'); answer('note'); char('c'); chooseDisk(); char('v'); char('q')",
     "assert(files['disk/note.txt']=='hello')")
test('sidebar click', "events[#events+1]={'mouse_click',1,4,5}; char('n'); answer('docs'); char('q')",
     "assert(files['disk/docs']=='dir')")
test('compact screen', "screenW=30; screenH=12; char('q')", "assert(#snapshots>0)")
test('F1 closes menu without exiting program', "char('a'); key('f1'); char('n'); answer('apos voltar'); char('q')", "assert(files['apos voltar']=='dir')")
test('help topic navigation and back button', "char('h'); key('right'); events[#events+1]={'mouse_click',1,3,19}; char('n'); answer('ajuda fechada'); char('q')", "assert(files['ajuda fechada']=='dir')")
test('boot and storage percentage', '''
local previous=term.write
term.write=function(s) if s:find('USO 50%',1,true) then sawUsage=true end; previous(s) end
char('q')
''', "assert(sawUsage and #bootFrames==4)")
test('main screen omits RAID status banner', '''
local write=term.write
term.write=function(s) assert(not s:find('RAID:',1,true)); write(s) end
char('q')
''', 'assert(#snapshots>0)')
test('backup selected computer file to floppy', '''
serviceOverride=function(m)
  m.backupItemMany=function(source,label,sourceID,destinations,guard,update)
    assert(source=='note.txt' and label=='Computador / note.txt' and sourceID=='computador-7')
    assert(#destinations==1 and destinations[1].id==42)
    guard(); update(1,1,'note.txt'); backedUp=true
    return {'disk/.diskdesk-backups/computador-7/version'}
  end
end
selectText(); char('b'); key('enter'); key('up'); key('enter'); char('s'); key('enter'); char('q')
''', 'assert(backedUp)')
test('move action and paste use verified service', '''
serviceOverride=function(m)
  m.moveItem=function(source,target,guard)
    guard(); assert(source=='note.txt' and target=='disk/note.txt')
    files[target]=files[source]; files[source]=nil; moved=true
  end
end
selectText(); char('m'); chooseDisk(); char('v'); char('q')
''', "assert(moved and files['disk/note.txt']=='hello' and not files['note.txt'])")
test('actions menu', "events[#events+1]={'mouse_click',1,15,19}; key('escape'); char('q')", "assert(#snapshots==3)")
test('context menu', "events[#events+1]={'mouse_click',2,20,6}; key('escape'); char('q')", "assert(#snapshots==3)")
test('bordered menus fit compact terminal', '''
screenW=30; screenH=12
local write=term.write
term.write=function(s) if s:sub(1,1)=='+' and s:sub(-1)=='+' then borderSeen=true end; write(s) end
char('a'); key('down'); key('down'); key('enter'); key('f1'); char('q')
''', 'assert(borderSeen)')
test('click confirm no', "selectText(); char('x'); events[#events+1]={'mouse_click',1,10,17}; char('q')", "assert(files['note.txt']=='hello')")
test('wireless send dialog and progress', '''
serviceOverride=function(m)
  m.openWireless=function() end
  m.sendFile=function(path,peer,guard,update)
    assert(path=='note.txt' and peer==12); guard(); update(5,5,'note.txt'); sent=true
  end
end
selectText(); char('s'); answer('12'); char('q')
''', "assert(sent)")
test('wireless receive confirmation and progress', '''
fs.getName=function(p) return p:match('[^/]+$') or '' end
serviceOverride=function(m)
  m.openWireless=function() end
  m.receiveFile=function(folder,guard,accept,update)
    assert(folder==''); guard(); assert(accept(12,'test.txt',5)); update(5,5,'test.txt')
    received=true; return 'test.txt'
  end
end
char('g'); char('s'); char('q')
''', "assert(received)")
preview = test('desktop render', "hasSpeaker=true; files['Projetos']='dir'; files['manual.txt']='DiskDesk'; char('q')", "assert(#snapshots>0)")
menu_preview = test('menu render', "char('a'); key('f1'); char('q')", "assert(#snapshots==3)")

# A deterministic visual preview of actual terminal writes, using only stdlib.
from html import escape
palette = {1:'#111111', 2:'#f0f0f0', 3:'#3366cc', 4:'#4c4c4c',
           5:'#999999', 6:'#dede6c', 7:'#4c99b2', 8:'#57a64e', 9:'#cc4c4c'}
for filename, frame in [('preview.svg', preview.globals().snapshots[1]),
                        ('preview-menu.svg', menu_preview.globals().snapshots[2])]:
    svg = ['<svg xmlns="http://www.w3.org/2000/svg" width="816" height="456" viewBox="0 0 816 456">',
           '<rect width="816" height="456" fill="#111111"/>',
           '<g font-family="Consolas, monospace" font-size="20">']
    for index, cell in frame.items():
        x, y = ((index-1) % 51)*16, ((index-1)//51)*24
        svg.append(f'<rect x="{x}" y="{y}" width="16" height="24" fill="{palette[cell[3]]}"/>')
        svg.append(f'<text x="{x}" y="{y+19}" fill="{palette[cell[2]]}">{escape(cell[1])}</text>')
    svg.append('</g></svg>')
    Path(__file__).with_name(filename).write_text('\n'.join(svg), encoding='utf-8')
