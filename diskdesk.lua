-- DiskDesk para CC: Tweaked. Salve no computador como diskdesk.lua.
local VERSION='3.1.0'
local wrap = require('cc.strings').wrap
local services = dofile(fs.combine(fs.getDir(shell.getRunningProgram()), 'diskdesk_services.lua'))
local physicalFs=fs
local volumeFactory=dofile(fs.combine(fs.getDir(shell.getRunningProgram()),'diskdesk_volumes.lua'))
local virtual=volumeFactory(services,dofile(fs.combine(fs.getDir(shell.getRunningProgram()),'diskdesk_arrays.lua')))
local fs=virtual.fs
services.useFilesystem(fs)
-- Migrate away from the removed automatic RAID 1 feature without deleting its copies.
pcall(function() if services.raidStatus().enabled then services.raidDisable() end end)
local sources, source, folder = {}, 1, ''
local entries, selected, scroll, unitScroll = {}, 1, 0, 0
local clipboard, job, tempSerial
local status = 'Selecione um arquivo ou abra uma unidade.'
local running = true
local W, H = term.getSize()
local buttons = {}
local filter, muted = '', false
local listX, listTop, listRows = 1, 5, 1
local deviceCount = {printer = 0, speaker = 0, modem = 0}
local theme = {bg = colors.black, panel = colors.gray, accent = colors.cyan,
  text = colors.white, muted = colors.lightGray, select = colors.blue}
local lastClick
local function fit(text, width)
  text = tostring(text)
  if #text > width then return width < 3 and text:sub(1, width) or text:sub(1, width - 2) .. '..' end
  return text .. string.rep(' ', math.max(0, width - #text))
end
local function put(x, y, width, text, bg, fg)
  if y < 1 or y > H or x > W or width < 1 then return end
  term.setBackgroundColor(bg or theme.bg)
  term.setTextColor(fg or theme.text)
  term.setCursorPos(x, y)
  term.write(fit(text, math.min(width, W - x + 1)))
end
local function sizeLabel(bytes)
  if type(bytes) ~= 'number' then return tostring(bytes) end
  if bytes >= 1048576 then return string.format('%.1fM', bytes / 1048576) end
  if bytes >= 1024 then return string.format('%.1fK', bytes / 1024) end
  return bytes .. 'B'
end
local function line(y, text, bg, fg)
  term.setBackgroundColor(bg or theme.bg)
  term.setTextColor(fg or theme.text)
  term.setCursorPos(1, y)
  term.write((text .. string.rep(' ', W)):sub(1, W))
end
local function choose(title, items, initial, bottom, highlightFirst)
  local selectedOption, offset = initial or 1, 0
  while true do
    W, H = term.getSize()
    local width = math.min(46, W - 2)
    local rows = math.max(1, math.min(#items, H - 5))
    local x, y = math.floor((W - width) / 2) + 1, math.max(1, math.floor((H - rows - 3) / 2))
    if bottom then y = H - rows - 2 end
    offset = math.max(0, math.min(offset, selectedOption - 1))
    if selectedOption > offset + rows then offset = selectedOption - rows end
    put(x-1,y,width+2,'+'..fit(' '..title..' ',width):gsub(' +$',function(s) return string.rep('-',#s) end)..'+',theme.bg,theme.accent)
    for row = 1, rows do
      local i = offset + row
      local special=highlightFirst and i==1
      put(x, y + row, width, (i == selectedOption and ' > ' or '   ') .. items[i],
        special and theme.accent or (i == selectedOption and theme.select or theme.panel),special and colors.black or theme.text)
      put(x-1,y+row,1,'|',theme.bg,theme.accent)
      put(x+width,y+row,1,'|',theme.bg,theme.accent)
    end
    put(x, y + rows + 1, width, ' [Voltar] F1  |  Enter: escolher', theme.panel, theme.muted)
    put(x-1,y+rows+1,1,'|',theme.bg,theme.accent)
    put(x+width,y+rows+1,1,'|',theme.bg,theme.accent)
    put(x-1,y+rows+2,width+2,'+'..string.rep('-',width)..'+',theme.bg,theme.accent)
    local event, a, b, c = os.pullEvent()
    if event == 'key' then
      if a == keys.escape or a == keys.f1 or a == keys.backspace then return nil end
      if a == keys.enter then return selectedOption end
      if a == keys.up then selectedOption = math.max(1, selectedOption - 1) end
      if a == keys.down then selectedOption = math.min(#items, selectedOption + 1) end
    elseif event == 'mouse_click' and a == 1 and b >= x and b < x + width and c == y + rows + 1 then return nil
    elseif event == 'mouse_scroll' then selectedOption = math.max(1, math.min(#items, selectedOption + a))
    elseif event == 'mouse_click' and a == 1 and b >= x and b < x + width and c > y and c <= y + rows then
      return offset + c - y
    elseif event == 'char' and #items == 2 and items[1] == 'Sim' and items[2] == 'Nao' then
      if a:lower() == 's' then return 1 elseif a:lower() == 'n' then return 2 end
    end
  end
end
local function prompt(title)
  W, H = term.getSize()
  local lines = wrap(title, W - 2)
  for i, text in ipairs(lines) do line(H - #lines - 1 + i, ' ' .. text, theme.panel) end
  line(H, '> ', theme.bg, theme.text)
  term.setCursorPos(3, H)
  return read()
end
local function confirm(title)
  term.setBackgroundColor(theme.panel); term.clear()
  line(1, ' DiskDesk - Confirmacao', colors.blue, colors.white)
  local lines = wrap(title, W - 2)
  for i = 1, math.min(#lines, H - 6) do line(i + 1, ' ' .. lines[i], theme.panel) end
  return choose('Confirmar', {'Sim', 'Nao'}, 2, true) == 1
end
local function scan()
  local old = sources[source]
  sources = {{name = 'Computador', root = '', key = 'computer'}}
  local names = peripheral.getNames()
  deviceCount = {printer = 0, speaker = 0, modem = 0}
  table.sort(names)
  for _, name in ipairs(names) do
    for kind in pairs(deviceCount) do
      if peripheral.hasType(name, kind) then deviceCount[kind] = deviceCount[kind] + 1 end
    end
    if peripheral.hasType(name, 'drive') then
      local mount = disk.getMountPath(name)
      if mount then
        sources[#sources + 1] = {
          name = disk.getLabel(name) or ('Disquete ' .. name),
          root = fs.combine(mount, ''), drive = name,
          key = name .. ':' .. tostring(disk.getID(name)) .. ':' .. mount
        }
      end
    end
  end
  for _,volume in ipairs(virtual.list()) do
    sources[#sources+1]={name='RAID '..(volume.mode=='10' and '1+0' or volume.mode)..' - '..volume.name,
      root=virtual.root(volume),key='virtual:'..volume.id,virtual=volume}
  end
  source = 1
  if old then
    for i, item in ipairs(sources) do
      if old.key == item.key then source = i; return end
    end
    folder, selected, scroll, filter = '', 1, 0, ''
    status = 'Unidade removida. Voltando ao computador.'
  end
end
local function current() return sources[source] end
local function path() return fs.combine(current().root, folder) end
local function refresh()
  if not fs.exists(path()) or not fs.isDir(path()) then folder = '' end
  entries = {}
  for _, name in ipairs(fs.list(path())) do
    local full = fs.combine(path(), name)
    if name:lower():find(filter:lower(), 1, true) then
      entries[#entries + 1] = {name = name, path = full, dir = fs.isDir(full)}
    end
  end
  table.sort(entries, function(a, b)
    if a.dir ~= b.dir then return a.dir end
    return a.name:lower() < b.name:lower()
  end)
  selected = math.max(1, math.min(selected, #entries))
end
local function draw()
  W, H = term.getSize()
  term.setBackgroundColor(theme.bg); term.clear()
  buttons = {}
  if W < 30 or H < 12 then
    line(1, 'Use uma tela de pelo menos 30x12.')
    line(2, 'Q: sair'); return
  end
  local function button(x, y, label, command, bg, fg)
    if x + #label - 1 > W then return x end
    put(x, y, #label, label, bg or theme.panel, fg or theme.text)
    buttons[#buttons + 1] = {x=x,last=x+#label-1,y=y,action=command}
    return x + #label + 1
  end
  line(1, ' [D] DISKDESK '..VERSION..' / arquivos', theme.accent, colors.black)
  put(W-10,1,10,' ID '..os.getComputerID(),theme.accent,colors.black)
  local unitState=current().virtual and (' ['..virtual.info(current().virtual).text..']') or ''
  line(2, ' '..current().name..unitState..' > /'..folder, theme.panel)
  local sidebar = W >= 45 and 14 or 0
  listX, listTop, listRows = sidebar+2, 5, H-8
  local listWidth = W-listX
  if sidebar > 0 then
    for y=3,H-4 do put(1,y,sidebar,'',theme.panel) end
    put(2,3,sidebar-2,'UNIDADES',theme.panel,theme.muted)
    local capacity = math.max(1,H-10)
    unitScroll=math.max(0,math.min(unitScroll,math.max(0,#sources-capacity)))
    if source<=unitScroll then unitScroll=source-1 end
    if source>unitScroll+capacity then unitScroll=source-capacity end
    local first = unitScroll+1
    for i=first,math.min(#sources,first+capacity-1) do
      local item,y=sources[i],4+i-first
      put(2,y,sidebar-2,(item.virtual and '= ' or (item.drive and 'o ' or '# '))..item.name,
        i==source and theme.select or theme.panel)
      buttons[#buttons+1]={x=1,last=sidebar,y=y,action='source:'..i}
    end
    if #sources>capacity then put(2,H-5,sidebar-2,'rolar '..first..'-'..math.min(#sources,first+capacity-1)..'/'..#sources,theme.panel,theme.muted) end
    if H>=13 then put(2,H-4,sidebar-2,muted and 'SOM: mudo' or (deviceCount.speaker>0 and 'SOM: ligado' or 'Sem Speaker'),theme.panel,theme.muted) end
  end
  put(listX,3,listWidth,filter~='' and ('Busca: '..filter) or ('ARQUIVOS / '..#entries..' itens'),theme.bg,theme.accent)
  put(listX,4,listWidth,' NOME',theme.panel,theme.muted)
  put(W-7,4,7,'TAM.',theme.panel,theme.muted)
  scroll=math.max(0,math.min(scroll,math.max(0,#entries-listRows)))
  if selected<=scroll then scroll=selected-1 end
  if selected>scroll+listRows then scroll=selected-listRows end
  for row=1,listRows do
    local item=entries[scroll+row]
    if item then
      local bg=scroll+row==selected and theme.select or theme.bg
      local icon=item.dir and '[+] ' or (item.name:match('%.lua$') and '{ } ' or '[T] ')
      put(listX,row+listTop-1,listWidth-7,icon..item.name,bg,item.dir and colors.yellow or theme.text)
      put(W-7,row+listTop-1,7,item.dir and 'pasta' or sizeLabel(fs.getSize(item.path)),bg,theme.muted)
    end
  end
  if #entries==0 then
    put(listX,5,listWidth,filter~='' and 'Nenhum resultado.' or 'Esta pasta esta vazia.',theme.bg,theme.muted)
    put(listX,6,listWidth,filter~='' and 'F1: limpar busca' or 'N: pasta | T: texto',theme.bg,theme.muted)
  end
  line(H-3,' '..#entries..' itens',theme.panel,theme.muted)
  line(H-2,clipboard and ((clipboard.move and ' Mover: ' or ' Copiar: ')..#clipboard.items..' item(ns) | V: colar') or status,theme.bg,colors.yellow)
  local free,capacity=fs.getFreeSpace(path()),fs.getCapacity(path())
  local percent=type(free)=='number' and type(capacity)=='number' and capacity>0
    and math.max(0,math.min(100,math.floor((capacity-free)/capacity*100+0.5))) or nil
  line(H-1,(percent and (' USO '..percent..'%') or ' USO --')..' | Livre '..sizeLabel(free)..' / '..sizeLabel(capacity or '--'),theme.panel,theme.muted)
  line(H,'',theme.select)
  local x=1
  x=button(x,H,'D: unidades','d',theme.select)
  x=button(x,H,'A: menu','a',theme.select)
  button(x,H,'H: ajuda','h',theme.select)
end
local function show(lines, title)
  local offset = 0
  while true do
    W, H = term.getSize()
    term.setBackgroundColor(colors.black); term.clear()
    line(1, title, colors.blue, colors.white)
    for i = 1, H - 2 do line(i + 1, lines[offset + i] or '') end
    line(H, '[Voltar] F1/Enter | Setas: rolar', colors.gray)
    local event, key, mx, my = os.pullEvent()
    if event == 'mouse_click' and key == 1 and my == H then return
    elseif event == 'key' then
      if key == keys.enter or key == keys.q or key == keys.escape or key == keys.f1 then return end
      if key == keys.down then offset = offset + 1 end
      if key == keys.up then offset = offset - 1 end
    elseif event == 'mouse_scroll' then offset = offset + key end
    offset = math.max(0, math.min(offset, math.max(0, #lines - H + 2)))
  end
end
local function readFile(file)
  if fs.getSize(file) > 128 * 1024 then error('Limite de texto: 128 KiB.', 0) end
  local handle, err = fs.open(file, 'r')
  if not handle then error(err, 0) end
  local text = handle.readAll(); handle.close()
  return text
end
local function textLines(text, width)
  local result = {}
  text = text:gsub('\r\n', '\n'):gsub('\r', '\n'):gsub('\t', '    ')
  if text:sub(-1) == '\n' then text = text:sub(1, -2) end
  for raw in (text .. '\n'):gmatch('(.-)\n') do
    if raw == '' then result[#result + 1] = ''
    else for _, piece in ipairs(wrap(raw, width)) do result[#result + 1] = piece end end
  end
  return result
end
local function newName(title)
  services.assertWritable(path())
  local name = prompt(title)
  if name == '' then return end
  if name == '.' or name == '..' or name:find('[/\\:*?"<>|]') or name:find('%c') then
    error('Nome invalido. Digite apenas um nome, sem caminho.', 0)
  end
  local full = fs.combine(path(), name)
  if fs.exists(full) then error('Ja existe um item com esse nome.', 0) end
  return full
end
local function requireItem()
  local item = entries[selected]
  if not item then error('Selecione um arquivo ou pasta.', 0) end
  return item
end
local function protected(item)
  services.assertWritable(item.path)
  if fs.isDriveRoot(item.path) or fs.isReadOnly(item.path) then
    error('Esta unidade ou pasta e protegida.', 0)
  end
end
local function edit(file)
  services.assertWritable(file)
  if fs.isReadOnly(file) then error('Nao e possivel gravar: local somente leitura.', 0) end
  local existed = fs.exists(file)
  term.setBackgroundColor(colors.black); term.setTextColor(colors.white); term.clear()
  term.setCursorPos(1, 1)
  local editorFile=file
  local draft
  if virtual.isVirtual(file) then
    local n=1
    draft='.diskdesk-edit/'..n
    while physicalFs.exists(draft) do n=n+1; draft='.diskdesk-edit/'..n end
    physicalFs.makeDir(draft)
    editorFile=physicalFs.combine(draft,fs.getName(file))
    if existed then fs.copy(file,editorFile) end
    line(1,' RAID: salve e saia do editor para gravar nos discos.',theme.accent,colors.black)
  end
  -- execute preserves the path as one argument, including spaces in folders.
  if not shell.execute('/rom/programs/edit.lua', '/' .. editorFile) then
    error('O editor falhou. Confira o disco e o espaco livre.', 0)
  end
  if draft and physicalFs.exists(editorFile) then
    local ok,why=pcall(function()
      local input=assert(physicalFs.open(editorFile,'rb')); local data=input.readAll(); input.close()
      local output,err=fs.open(file,'wb'); if not output then error(err,0) end
      output.write(data); output.close()
    end)
    if not ok then error('Rascunho preservado em /'..editorFile..'. '..tostring(why),0) end
  end
  if draft then physicalFs.delete(draft) end
  if not fs.exists(file) then
    status = 'Nao foi salvo. No editor: Ctrl > Save.'
  elseif not existed then
    filter = ''
    refresh()
    for i, item in ipairs(entries) do if item.path == file then selected = i; break end end
    status = 'Arquivo criado: ' .. fs.getName(file)
  else status = 'Editor fechado.' end
end
local function switchSource(i)
  if sources[i] then
    source, folder, selected, scroll, filter = i, '', 1, 0, ''
    status = 'Unidade: ' .. current().name
  end
end
local function chooseSource()
  scan()
  local choice,offset=source,0
  while true do
    W,H=term.getSize()
    local rows=math.max(1,math.floor((H-4)/3))
    choice=math.max(1,math.min(choice,#sources))
    offset=math.max(0,math.min(offset,choice-1))
    if choice>offset+rows then offset=choice-rows end
    term.setBackgroundColor(theme.bg); term.clear()
    line(1,' UNIDADES / Armazenamento',theme.accent,colors.black)
    line(2,' Selecione uma unidade para abrir',theme.panel)
    for row=1,rows do
      local i=offset+row; local unit=sources[i]
      if unit then
        local y=3+(row-1)*3
        local bg=i==choice and theme.select or theme.panel
        local description=unit.virtual and (' / '..virtual.info(unit.virtual).text) or ('  /'..unit.root)
        line(y,(i==choice and ' > ' or '   ')..unit.name..description,bg)
        local free,capacity=fs.getFreeSpace(unit.root),fs.getCapacity(unit.root)
        local percent=type(free)=='number' and type(capacity)=='number' and capacity>0
          and math.max(0,math.min(100,math.floor((capacity-free)/capacity*100+0.5))) or nil
        put(3,y+1,10,percent and (percent..'% usado') or 'Uso --',theme.bg,theme.text)
        local width=math.max(1,W-16)
        put(14,y+1,width,'',theme.panel)
        if percent and percent>0 then put(14,y+1,math.max(1,math.floor(width*percent/100)),'',percent>=90 and colors.red or theme.accent) end
        put(3,y+2,W-4,'Livre: '..sizeLabel(free)..' / Total: '..sizeLabel(capacity or '--'),theme.bg,theme.muted)
      end
    end
    line(H,'[Voltar] F1 | Enter: abrir',theme.select)
    local event,a,b,c=os.pullEvent()
    if event=='key' then
      if a==keys.f1 or a==keys.escape or a==keys.q then return end
      if a==keys.enter then switchSource(choice); return end
      if a==keys.up then choice=math.max(1,choice-1) end
      if a==keys.down then choice=math.min(#sources,choice+1) end
    elseif event=='mouse_scroll' then choice=math.max(1,math.min(#sources,choice+a))
    elseif event=='mouse_click' and a==1 then
      if c==H then return end
      if c>=3 and c<3+rows*3 then
        local index=offset+math.floor((c-3)/3)+1
        if sources[index] then switchSource(index); return end
      end
    elseif event=='disk' or event=='disk_eject' or event=='peripheral' or event=='peripheral_detach' then scan() end
  end
end
local function resumePrint()
  local printer = peripheral.wrap(job.printer)
  if not printer or not peripheral.hasType(job.printer, 'printer') then
    error('Reconecte a impressora ' .. job.printer .. ' e pressione P.', 0)
  end
  while job do
    if not job.staged then
      if not printer.newPage() then
        if not confirm('Coloque papel e tinta. Tentar novamente?') then
          status = 'Impressao pausada. P: continuar'; return
        end
      else
        local width, height = printer.getPageSize()
        if not job.lines then job.lines = textLines(job.text, width); job.text = nil end
        job.last = math.min(#job.lines, job.next + height - 1)
        printer.setPageTitle((job.title .. ' ' .. job.page):sub(1, 32))
        for i = job.next, job.last do
          printer.setCursorPos(1, i - job.next + 1); printer.write(job.lines[i])
        end
        job.staged = true
      end
    end
    if job.staged then
      if printer.endPage() then
        job.next, job.page, job.staged = job.last + 1, job.page + 1, false
        if job.next > #job.lines then
          status = 'Impressao concluida: ' .. (job.page - 1) .. ' pagina(s).'
          job = nil
        end
      elseif not confirm('Esvazie a saida da impressora. Tentar?') then
        status = 'Pagina pendente na impressora. P: continuar'; return
      end
    end
  end
end
local function printFile()
  if job then resumePrint(); return end
  local item = requireItem()
  if item.dir then error('Selecione um arquivo de texto.', 0) end
  local printers = {}
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.hasType(name, 'printer') then printers[#printers + 1] = name end
  end
  table.sort(printers)
  if #printers == 0 then error('Conecte uma impressora ao computador.', 0) end
  local number = 1
  if #printers > 1 then
    number = choose('Escolha a impressora', printers)
    if not number or not printers[number] then return end
  end
  local text = readFile(item.path)
  if not confirm('Imprimir ' .. item.name .. '?') then return end
  job = {printer = printers[number], text = text, title = item.name, next = 1, page = 1}
  resumePrint()
end
local function progress(title)
  return function(done, total, name)
    W, H = term.getSize()
    term.setBackgroundColor(theme.panel); term.clear()
    line(1, ' DiskDesk - ' .. title, colors.blue, colors.white)
    local lines = wrap(name, W - 4)
    for i = 1, math.min(#lines, H - 7) do line(i + 2, '  ' .. lines[i], theme.panel) end
    local width = W - 6
    local fraction = total > 0 and math.min(1, done / total) or 0
    put(3, H-4, width, string.rep(' ', width), colors.white)
    local filled = math.floor(width * fraction)
    if filled > 0 then put(3, H-4, filled, string.rep(' ', filled), colors.blue) end
    line(H-2, '  ' .. math.floor(fraction * 100) .. '%  |  ' .. done .. ' / ' .. total, theme.panel)
    line(H, (title=='Enviar' or title=='Receber') and ' F1: voltar | mantenha o modem conectado.' or ' Mantenha os discos conectados ate terminar.', theme.panel)
  end
end
local function pickDisk(title, exclude, excludedIDs)
  scan()
  local volumes, labels = {}, {}
  for _, item in ipairs(sources) do
    if item.drive then
      local volume = services.capture(item.drive)
      if (not exclude or volume.id ~= exclude.id) and not (excludedIDs and excludedIDs[volume.id]) then
        volumes[#volumes+1] = volume
        labels[#labels+1] = volume.name .. ' (ID ' .. volume.id .. ')'
      end
    end
  end
  if #volumes == 0 then error('Conecte outro Disk Drive com um floppy disk.', 0) end
  local index = choose(title, labels)
  if index then services.guard(volumes[index]); return volumes[index] end
end
local selectDisks, pathGuard
local function backupDisk()
  local item=requireItem()
  local whole=false
  if current().drive then
    local choice=choose('O que deseja copiar?',{'Item selecionado: '..item.name,'Disquete inteiro: '..current().name})
    if not choice then return end; whole=choice==2
  end
  local src=current().drive and services.capture(current().drive) or nil
  local excluded={}
  if src then excluded[src.id]=true end
  if current().virtual then
    for _,id in ipairs(current().virtual.members) do excluded[id]=true end
  end
  if next(excluded)==nil then excluded=nil end
  local destinations=selectDisks('Marque os discos de BACKUP',1,8,excluded)
  if not destinations then return end
  local ids={}; for _,dest in ipairs(destinations) do ids[#ids+1]='#'..dest.id end
  local description=whole and ('disquete #'..src.id) or item.name
  if not confirm('Criar backup de '..description..' nos discos '..table.concat(ids,', ')..'? Versoes anteriores serao preservadas.') then return end
  local paths
  if whole then paths=services.backupMany(src,destinations,progress('Backup completo'))
  else
    local sourceID=(src and ('disco-'..src.id) or (current().virtual and ('raid-'..current().virtual.id) or ('computador-'..os.getComputerID())))
    paths=services.backupItemMany(item.path,current().name..' / '..item.name,sourceID,destinations,pathGuard(item.path),progress('Backup do item'))
  end
  local results={}; for i,dest in ipairs(destinations) do results[i]='#'..dest.id..': '..paths[i] end
  status='Backup verificado em '..#destinations..' disco(s).'
  local lines={'Backup concluido e verificado em todos os destinos.',''}
  for _,result in ipairs(results) do lines[#lines+1]=result end
  lines[#lines+1]=''; lines[#lines+1]='Cada disco possui uma copia restauravel independente.'
  lines[#lines+1]='Versoes antigas nao foram apagadas.'
  show(lines,' Backup concluido')
end
local function restoreDisk()
  if not current().drive then error('Abra o disquete que guarda os backups.', 0) end
  local src = services.capture(current().drive)
  local snapshots = services.snapshots(src)
  if #snapshots == 0 then error('Este disquete nao possui backups concluidos.', 0) end
  local labels = {}
  for i, snapshot in ipairs(snapshots) do labels[i] = snapshot.name end
  local index = choose('Escolha a versao do backup', labels)
  if not index then return end
  local dest = pickDisk('Disco para restaurar arquivos', src)
  if not dest then return end
  if not confirm('Restaurar para ' .. dest.name .. ' (#' .. dest.id .. ')? Os arquivos serao colocados em uma nova pasta.') then return end
  local result = services.restore(snapshots[index].path, src, dest, progress('Restaurar'))
  status = 'Restauracao concluida.'
  show({'Arquivos verificados e restaurados em:', '', result, '', 'Nenhum arquivo existente foi substituido.'}, ' Restauracao concluida')
end
pathGuard=function(target)
  if virtual.isVirtual(target) then return function() virtual.guard(target) end end
  for _, item in ipairs(sources) do
    if item.drive and (target == item.root or target:sub(1, #item.root+1) == item.root .. '/') then
      local volume = services.capture(item.drive)
      return function() services.guard(volume) end
    end
  end
  return function() end
end
local function selectItems(title,filesOnly,maximum)
  local candidates,checked={},{}
  for _,item in ipairs(entries) do if not filesOnly or not item.dir then candidates[#candidates+1]=item end end
  if #candidates==0 then error(filesOnly and 'Esta pasta nao possui arquivos.' or 'Esta pasta esta vazia.',0) end
  local currentItem=entries[selected]
  for i,item in ipairs(candidates) do if item==currentItem then checked[i]=true end end
  local cursor=1
  while true do
    local chosen,labels={},{}
    for i,item in ipairs(candidates) do if checked[i] then chosen[#chosen+1]=item end end
    labels[1]='>> CONFIRMAR '..#chosen..' ITEM(NS) <<'
    for i,item in ipairs(candidates) do labels[i+1]=(checked[i] and '[x] ' or '[ ] ')..(item.dir and '[+] ' or '')..item.name end
    local option=choose(title,labels,cursor,nil,true); if not option then return end; cursor=option
    if option==1 then
      if #chosen==0 then show({'Marque ao menos um item.'},' Selecao')
      else return chosen end
    elseif not checked[option-1] and #chosen>=maximum then show({'Maximo de '..maximum..' itens por operacao.'},' Selecao')
    else checked[option-1]=not checked[option-1] end
  end
end
local function sendWireless()
  local chosen=selectItems('Escolha os arquivos',true,32); if not chosen then return end
  services.openWireless()
  local peer=tonumber(prompt('ID do computador de destino (abra Receber nele):')); if not peer then return end
  local paths,total={ },0; for _,item in ipairs(chosen) do paths[#paths+1]=item.path; total=total+fs.getSize(item.path) end
  if not confirm('Enviar '..#paths..' arquivo(s), total '..sizeLabel(total)..', para o computador ID '..peer..'?') then return end
  services.sendFiles(paths,peer,function() for _,item in ipairs(chosen) do pathGuard(item.path)() end end,progress('Enviar'))
  status=#paths..' arquivo(s) entregues e verificados no ID '..peer..'.'
end
local function receiveWireless()
  services.openWireless()
  local destination = path()
  local update = progress('Receber')
  update(0, 1, 'Seu ID: ' .. os.getComputerID() .. '. Aguardando envio por 60 segundos. Pasta: /' .. destination)
  local results = services.receiveFiles(destination, pathGuard(destination), function(peer, offered, size)
    local label=type(offered)=='table' and (#offered..' arquivos') or offered
    return confirm('ID '..peer..' quer enviar '..label..' ('..sizeLabel(size)..'). Destino: /'..destination..'. Aceitar?')
  end, update)
  status = results and (#results..' arquivo(s) recebidos e verificados.') or 'Recebimento recusado.'
end
selectDisks=function(title,minimum,maximum,excluded,even)
  scan()
  local units,checked={},{}
  for _,unit in ipairs(sources) do
    if unit.drive then
      local volume=services.capture(unit.drive)
      if not excluded or not excluded[volume.id] then units[#units+1]=volume end
    end
  end
  if #units<minimum then error('Conecte ao menos '..minimum..' disquetes disponiveis.',0) end
  local cursor=2
  while true do
    local chosen,labels={},{}
    for i,unit in ipairs(units) do if checked[i] then chosen[#chosen+1]=unit end end
    labels[1]='Confirmar '..#chosen..' discos (min '..minimum..')'
    for i,unit in ipairs(units) do
      labels[i+1]=(checked[i] and '[x] ' or '[ ] ')..'#'..unit.id..' '..unit.name..' '..sizeLabel(fs.getFreeSpace(unit.root))..' livre'
    end
    local selected=choose(title,labels,cursor)
    if not selected then return end
    cursor=selected
    if selected==1 then
      if #chosen>=minimum and #chosen<=maximum and (not even or #chosen%2==0) then
        for _,unit in ipairs(chosen) do services.guard(unit) end
        return chosen
      end
      show({'Escolha de '..minimum..' a '..maximum..' discos.',even and 'RAID 1+0 exige uma quantidade par.' or 'Marque os discos com Enter ou clique.'},' Selecao de discos')
    elseif not checked[selected-1] and #chosen>=maximum then
      show({'Maximo de '..maximum..' discos.'},' Selecao de discos')
    else checked[selected-1]=not checked[selected-1] end
  end
end
local function virtualMenu()
  local operation=choose('Unidades RAID em tempo real',{'Criar unidade RAID','Gerenciar unidade RAID','Excluir unidade RAID','Importar unidade dos discos','Como usar'})
  if not operation then return end
  if operation==1 then
    local modeIndex=choose('Tipo da unidade RAID',{'RAID 0 - soma / sem redundancia','RAID 1 - espelho','RAID 5 - paridade simples','RAID 6 - paridade dupla','RAID 1+0 - pares de espelhos'})
    if not modeIndex then return end
    local mode=({'0','1','5','6','10'})[modeIndex]
    local excluded={}
    for _,volume in ipairs(virtual.list()) do for _,id in ipairs(volume.members) do excluded[id]=true end end
    local units=selectDisks('Marque os membros da unidade',({2,2,3,4,4})[modeIndex],16,excluded,mode=='10')
    if not units then return end
    local name=prompt('Nome da unidade RAID:'); if name=='' then return end
    local ids={}; for _,unit in ipairs(units) do ids[#ids+1]='#'..unit.id end
    if not confirm('Criar RAID '..mode..' em '..table.concat(ids,', ')..'? Copie os arquivos para a NOVA unidade em D.'..
      (mode=='10' and ' Pares seguem essa ordem.' or '')..(mode=='0' and ' Sem redundancia.' or '')) then return end
    local volume=virtual.create(name,mode,units)
    scan()
    for i,unit in ipairs(sources) do if unit.key=='virtual:'..volume.id then switchSource(i); break end end
    status='Unidade criada. Use C/M e V para copiar/mover para ela.'
  elseif operation==2 or operation==3 then
    local list=virtual.list(); if #list==0 then error('Crie ou importe uma unidade RAID primeiro.',0) end
    local labels={}; for i,volume in ipairs(list) do labels[i]='RAID '..volume.mode..' / '..volume.name end
    local index=choose('Unidade RAID',labels); if not index then return end
    local volume=list[index]; local state=virtual.info(volume)
    if operation==3 then
      if not state.writable then error('Conecte todos os membros antes de excluir a unidade.',0) end
      if confirm('EXCLUIR a unidade '..volume.name..' e TODOS os arquivos RAID dela? Outros arquivos fisicos dos disquetes serao preservados.') then
        virtual.delete(volume)
        scan(); source,folder,selected,scroll,filter=1,'',1,0,''
        status='Unidade RAID excluida dos discos e do computador.'
      end
      return
    end
    local task=choose(volume.name..' / '..state.text,{'Ver capacidade e discos','Verificar arquivos / catalogo','Substituir membro ausente'})
    if task==1 then
      local lines={'RAID '..volume.mode..' - '..state.text,'Capacidade util: '..sizeLabel(state.capacity),
        'Livre para novos dados: '..sizeLabel(state.free),'Conteudo dos arquivos: '..sizeLabel(state.used),
        'Discos de tamanhos diferentes: limita pelo menor.'}
      for slot,id in ipairs(volume.members) do lines[#lines+1]='Posicao '..slot..': #'..id..(state.members[slot] and ' conectado' or ' ausente') end
      lines[#lines+1]='Degradado: leitura; reconstrua antes de gravar.'
      show(lines,' Unidade RAID')
    elseif task==2 then
      local lines,result=virtual.verify(volume); table.insert(lines,1,result)
      show(lines,' Verificacao RAID')
    elseif task==3 then
      if #state.missing==0 then error('Retire o disco defeituoso antes de substitui-lo.',0) end
      local labels={}; for i,slot in ipairs(state.missing) do labels[i]='Posicao '..slot..' / disco #'..volume.members[slot] end
      local selectedSlot=choose('Membro ausente',labels); if not selectedSlot then return end
      local excluded={}; for _,v in ipairs(virtual.list()) do for _,id in ipairs(v.members) do excluded[id]=true end end
      local dest=pickDisk('Novo disco para reconstruir',nil,excluded); if not dest then return end
      if not confirm('Reconstruir todos os arquivos da posicao '..state.missing[selectedSlot]..' no disco #'..dest.id..'?') then return end
      local updated=virtual.rebuild(volume,state.missing[selectedSlot],dest,progress('Reconstruir unidade'))
      status=virtual.info(updated).writable and 'Unidade reconstruida. Pode gravar novamente.' or 'Membro reconstruido. Ainda faltam outros membros.'
    end
  elseif operation==4 then
    local count=virtual.import(); status=count..' unidade(s) importada(s). Abra com D.'
  else
    show({'Crie a unidade e abra-a em D: unidades.',
      'C/M + V copia/move arquivos para a unidade.',
      'N/T cria pastas/textos; R renomeia; Delete exclui.',
      'Dados sao divididos automaticamente, sem compactar.',
      'Editar: salvar e sair publica o arquivo nos discos.',
      'RAID 0 soma capacidade dos membros iguais.',
      'RAID 1 usa espelhos; 5/6 reservam paridade.',
      'RAID 1+0 usa metade para os espelhos.',
      'Capacidade considera o menor disco e metadados.',
      'Degradado permite leitura se houver redundancia.',
      'Reconstrua membros ausentes antes de gravar.',
      'Arquivos na raiz fisica do floppy nao sao importados.',
      'Unidade disponivel dentro do DiskDesk.',
      'Conjuntos antigos continuam no menu de arquivos.'},' Como usar a unidade RAID')
  end
end
local function archiveAction(extract)
  local item,chosen
  if extract then item=requireItem(); if item.dir then error('Selecione um pacote .ddz.',0) end
  else chosen=selectItems('Itens para compactar',false,64); if not chosen then return end end
  local target=newName(extract and 'Nome da NOVA pasta para extrair:' or 'Nome do pacote (ex: documentos.ddz):')
  if not target then return end
  if not extract and target:sub(-4):lower()~='.ddz' then target=target..'.ddz' end
  if not extract and not confirm('Criar pacote com '..#chosen..' item(ns) em /'..target..'?') then return end
  local targetGuard=pathGuard(target)
  local function guard()
    targetGuard()
    if extract then pathGuard(item.path)()
    else for _,selectedItem in ipairs(chosen) do pathGuard(selectedItem.path)() end end
  end
  if extract then
    services.extract(item.path,target,guard); status='Extraido em: '..fs.getName(target)
  else
    local paths={}; for _,selectedItem in ipairs(chosen) do paths[#paths+1]=selectedItem.path end
    local update=progress('Compactar'); update(0,2,'Destino: /'..target)
    local staging=target
    if current().drive or current().virtual then
      tempSerial=(tempSerial or 0)+1; physicalFs.makeDir('.diskdesk-temp')
      staging='.diskdesk-temp/pacote-'..os.epoch('utc')..'-'..tempSerial..'.ddz'
    end
    local original,packed=services.compressMany(paths,staging,guard); update(1,2,'Pacote temporario verificado')
    if staging~=target then
      local free=fs.getFreeSpace(fs.getDir(target))
      if type(free)=='number' and free<packed+1024 then
        physicalFs.delete(staging)
        show({'O pacote ficou com '..sizeLabel(packed)..'.','Destino: /'..target,'Livre no destino: '..sizeLabel(free),'O temporario do computador foi removido.'},' Sem espaco para o pacote')
        return
      end
      local fromGuard,toGuard=pathGuard(staging),pathGuard(target)
      services.moveItem(staging,target,function() fromGuard(); toGuard() end)
    end
    update(2,2,'Salvo em /'..target)
    status='Salvo em /'..target..' | '..#paths..' item(ns): '..sizeLabel(original)..' -> '..sizeLabel(packed)..(packed>=original and ' (inclui nomes/indice)' or (' (-'..math.floor((1-packed/original)*100)..'%)'))
  end
  filter=''
end
local helpTopics={
  {title='Unidades RAID em tempo real',text={'A > RAID e backup > Unidades RAID em tempo real. Crie uma unidade e selecione seus discos.',
    'Cada unidade aceita de 2 a 16 membros; RAID 1+0 exige quantidade par.',
    'Abra a nova unidade em D. C/M + V copia ou move para ela; os dados sao divididos ou espelhados automaticamente.',
    'RAID 0 soma a capacidade util dos discos iguais. RAID 1 espelha. RAID 5/6 reservam 1/2 membros para paridade; 1+0 usa metade para espelhos.',
    'Os percentuais e o espaco livre atualizam apos cada operacao. A capacidade e limitada pelo menor membro e reserva espaco para indices.',
    'N/T cria pastas/textos, R renomeia e Delete exclui. No editor, salve e saia para publicar nos discos. Se falhar, o rascunho fica no computador.',
    'Com membros ausentes, a unidade fica somente leitura se ainda houver redundancia. Reconstrua antes de gravar.',
    'Um arquivo alterado precisa de espaco para a versao nova antes de liberar a anterior. Falhas podem deixar blocos temporarios.',
    'Use Gerenciar para verificar ou reconstruir. Importar recupera o catalogo de uma unidade em outro computador.',
    'Arquivos copiados para a raiz fisica dos floppies continuam fora da unidade. Use Excluir unidade para apagar seus dados internos.'}},
  {title='Primeiros passos',text={'D escolhe computador ou disquete. Clique na unidade da barra lateral para trocar.',
    'Clique seleciona; duplo clique ou Enter abre. Backspace volta uma pasta.',
    'A abre o menu por categorias. Botao direito mostra acoes do item.',
    'F1 e o botao Voltar fecham menus sem sair da tela do PC. Esc pertence ao Minecraft.',
    'Q encerra o DiskDesk e volta ao terminal.'}},
  {title='Arquivos e mover',text={'N cria pasta. T abre um novo texto. E edita o arquivo selecionado.',
    'No editor: Ctrl > Save para salvar e Ctrl > Exit para sair. Nomes com espacos funcionam.',
    'C copia e M move: marque ate 64 arquivos/pastas, abra o destino e use V para colar.',
    'Mover verifica a copia antes de excluir a origem. Se falhar, confira a origem e os arquivos .partial.',
    'R renomeia; Delete exclui com confirmacao. F busca nomes; F1 limpa o filtro.'}},
  {title='Discos e armazenamento',text={'USO mostra a porcentagem do disco atual. D abre as barras de cada unidade; vermelho indica 90% ou mais.',
    'D abre o painel com barras de uso, espaco livre e capacidade de cada unidade. Capacidade indisponivel aparece como --.',
    'L muda o nome do floppy. J ejeta. Speaker conectado toca ao inserir e retirar; U silencia.',
    'Arquivos muito pequenos tambem ocupam espaco de armazenamento.'}},
  {title='Backup em varios discos',text={'B ou A > RAID e backup > Backup em varios discos.',
    'Selecione um arquivo ou pasta no computador, disquete ou unidade RAID. Em disquetes, pode escolher a unidade inteira.',
    'Marque de 1 a 8 disquetes de destino e confirme.',
    'Cada destino recebe uma copia completa, verificada e restauravel de forma independente.',
    'Versoes anteriores permanecem nos destinos. O restaura uma versao para outro disquete.',
    'O backup nao sincroniza exclusoes: isso permite recuperar versoes antigas.',
    'Mantenha a origem e todos os destinos conectados ate concluir.'}},
  {title='Compactacao DDZ',text={'A > Compactar e extrair. Selecione um arquivo ou pasta e escolha Compactar.',
    'O pacote .ddz preserva subpastas, arquivos binarios e pastas vazias. Pode enviar esse pacote pelo wireless.',
    'Para abrir, selecione o pacote, escolha Extrair e informe o nome de uma pasta nova.',
    'DDZ2 usa indice binario pequeno e comprime nomes e conteudo juntos. Continua lendo os pacotes DDZ1 antigos.',
    'Formato proprio, nao e ZIP. Arquivos minusculos podem crescer por causa dos nomes e do indice.',
    'Limites: 512 KiB descompactados e 1024 itens. Arquivos corrompidos ou caminhos invalidos sao rejeitados.'}},
  {title='Rede wireless',text={'Instale DiskDesk e modem wireless nos dois computadores.',
    'No destino: abra a pasta e use G (Receber). Veja o ID na barra inferior.',
    'Na origem: selecione o arquivo, use S e digite o ID. Aceite a oferta no destino.',
    'Ate 1 MiB por arquivo, com verificacao e repeticao de pacotes. F1 cancela a espera.',
    'A rede Rednet nao e criptografada. Use com jogadores confiaveis.'}},
  {title='Impressora',text={'Conecte Printer e abasteca com papel e corante. Selecione texto e use P.',
    'O texto e dividido automaticamente em paginas. Visualizacao e impressao: ate 128 KiB.',
    'Se faltar material ou a saida encher, resolva e tente de novo. P retoma um trabalho pausado.',
    'Nao reinicie o programa nem use outro programa na impressora enquanto houver trabalho pendente.'}}
}
local function helpScreen()
  local topic,offset=1,0
  while true do
    W,H=term.getSize()
    term.setBackgroundColor(theme.bg); term.clear()
    line(1,' DISKDESK / Central de ajuda',theme.accent,colors.black)
    line(2,' '..topic..'/'..#helpTopics..'  '..helpTopics[topic].title,theme.panel)
    local lines={}
    for _,paragraph in ipairs(helpTopics[topic].text) do
      for _,part in ipairs(wrap(paragraph,W-4)) do lines[#lines+1]=part end
      lines[#lines+1]=''
    end
    local rows=math.max(1,H-5)
    offset=math.max(0,math.min(offset,math.max(0,#lines-rows)))
    for row=1,rows do put(3,row+3,W-4,lines[offset+row] or '',theme.bg,theme.text) end
    line(H-1,' Setas: rolar | Esq/Dir: trocar assunto',theme.bg,theme.muted)
    line(H,'[Voltar] [Topicos] [<] [>]',theme.panel)
    local event,a,b,c=os.pullEvent()
    if event=='key' then
      if a==keys.f1 or a==keys.q or a==keys.enter or a==keys.escape then return end
      if a==keys.down then offset=offset+1 elseif a==keys.up then offset=offset-1
      elseif a==keys.left then topic=math.max(1,topic-1); offset=0
      elseif a==keys.right then topic=math.min(#helpTopics,topic+1); offset=0 end
    elseif event=='mouse_scroll' then offset=offset+a
    elseif event=='mouse_click' and a==1 and c==H then
      if b<=8 then return
      elseif b<=18 then
        local titles={}; for i,item in ipairs(helpTopics) do titles[i]=item.title end
        local selection=choose('Topicos da ajuda',titles,topic)
        if selection then topic,offset=selection,0 end
      elseif b<=22 then topic=math.max(1,topic-1); offset=0
      else topic=math.min(#helpTopics,topic+1); offset=0 end
    end
  end
end
local function boot()
  local steps={'Carregando explorador','Detectando perifericos','Verificando unidades','Preparando RAID e rede'}
  for i,text in ipairs(steps) do
    W,H=term.getSize()
    term.setBackgroundColor(theme.bg); term.clear()
    line(math.max(1,math.floor(H/2)-3),'             DISKDESK',theme.bg,theme.accent)
    local y=math.max(2,math.floor(H/2))
    put(3,y,W-4,text,theme.bg,theme.text)
    put(3,y+2,W-4,'',theme.panel)
    put(3,y+2,math.max(1,math.floor((W-4)*i/#steps)),'',theme.accent)
    put(3,y+3,W-4,math.floor(i/#steps*100)..'%',theme.bg,theme.muted)
    if i==2 then scan() elseif i==3 then refresh() end
    sleep(0.12)
  end
end
local menus = {
  file = {{'Abrir / visualizar', 'open'}, {'Novo texto', 't'}, {'Nova pasta', 'n'}, {'Editar texto', 'e'}, {'Backup do item selecionado', 'b'}, {'Imprimir', 'p'}},
  edit = {{'C  Copiar', 'c'}, {'M  Mover', 'm'}, {'V  Colar', 'v'}, {'R  Renomear', 'r'}, {'Delete  Excluir...', 'x'}, {'F  Buscar nesta pasta', 'f'}},
  disk = {{'Escolher unidade', 'd'}, {'Criar backup...', 'b'}, {'Restaurar backup...', 'o'}, {'Nome do disquete', 'l'}, {'Ejetar disquete', 'j'}},
  net = {{'Enviar arquivo...', 's'}, {'Receber arquivo...', 'g'}},
  protect = {{'Unidades RAID em tempo real','virtual'}, {'Backup em varios discos','b'}, {'Restaurar backup','o'}},
  archive = {{'Compactar varios itens (.ddz)','z'}, {'Extrair pacote .ddz','y'}},
  start = {{'[+] Arquivos e organizacao', 'menu:files'}, {'[%] Armazenamento dos discos', 'd'}, {'[=] RAID e backup', 'menu:protect'}, {'[Z] Compactar e extrair', 'menu:archive'}, {'[~] Rede wireless', 'menu:net'}, {'[?] Central de ajuda', 'h'}, {'[x] Sair do DiskDesk', 'q'}},
  files = {{'Criar / editar / imprimir','menu:file'}, {'Copiar / mover / renomear','menu:edit'}, {'Nomear / ejetar disquete','menu:disk'}},
  context = {{'Abrir', 'open'}, {'Editar', 'e'}, {'Copiar', 'c'}, {'Mover', 'm'}, {'Colar aqui', 'v'}, {'Backup...', 'b'}, {'Renomear', 'r'}, {'Imprimir', 'p'}, {'Enviar por wireless', 's'}, {'Excluir...', 'x'}}
}
local function action(command)
  if command:match('^menu:') then
    local items = menus[command:sub(6)]
    if not items then return end
    local labels = {}
    for i, item in ipairs(items) do labels[i] = item[1] end
    local titles={start='Menu principal',files='Arquivos e organizacao',file='Arquivos',edit='Organizar arquivos',disk='Discos',protect='RAID e backup',archive='Compactacao DDZ',net='Transferencia wireless',context='Acoes do item'}
    local choice = choose(titles[command:sub(6)] or 'Menu', labels)
    if choice then action(items[choice][2]) end
  elseif command == 'a' then action('menu:start')
  elseif command == 'z' then archiveAction(false)
  elseif command == 'y' then archiveAction(true)
  elseif command == 'i' then virtualMenu()
  elseif command == 'virtual' then virtualMenu()
  elseif command == 'b' then backupDisk()
  elseif command == 'o' then restoreDisk()
  elseif command == 's' then sendWireless()
  elseif command == 'g' then receiveWireless()
  elseif command == 'q' then
    if not job or confirm('Ha impressao pendente. Sair mesmo assim?') then running = false end
  elseif command == 'h' then helpScreen()
  elseif command == 'd' then chooseSource()
  elseif command:match('^source:%d+$') then switchSource(tonumber(command:match('%d+')))
  elseif command == 'f' then
    filter = prompt('Buscar nesta pasta (vazio limpa):')
    selected, scroll = 1, 0
  elseif command == 'clear' then filter, selected, scroll = '', 1, 0
  elseif command == 'u' then
    muted = not muted
    status = muted and 'Sons desativados.' or 'Sons ativados. Requer um Speaker.'
  elseif command == 'back' then
    folder = fs.getDir(folder); selected, scroll, filter = 1, 0, ''
  elseif command == 'open' then
    local item = requireItem()
    if item.dir then folder = fs.combine(folder, item.name); selected, scroll, filter = 1, 0, ''
    else show(textLines(readFile(item.path), W), item.name) end
  elseif command == 'n' then
    local full = newName('Nome da nova pasta:'); if full then fs.makeDir(full) end
  elseif command == 't' then
    local full = newName('Nome do texto (ex: notas.txt):'); if full then edit(full) end
  elseif command == 'e' then
    local item = requireItem(); protected(item)
    if item.dir then error('Selecione um arquivo.', 0) end
    edit(item.path)
  elseif command == 'c' or command == 'm' then
    local chosen=selectItems(command=='m' and 'Itens para mover' or 'Itens para copiar',false,64)
    if not chosen then return end
    local items={}
    for _,item in ipairs(chosen) do
      if command=='m' then protected(item) end
      if fs.isDriveRoot(item.path) then error('Abra a unidade e copie seus itens.',0) end
      local owner=current()
      for _,candidate in ipairs(sources) do
        if candidate.drive and (item.path==candidate.root or item.path:sub(1,#candidate.root+1)==candidate.root..'/') then owner=candidate end
      end
      items[#items+1]={path=item.path,name=item.name,owner=owner.key}
    end
    clipboard={items=items,move=command=='m'}
    status=(clipboard.move and 'Mover ' or 'Copiar ')..#items..' item(ns). Destino + V.'
  elseif command == 'v' then
    if not clipboard then error('Use C para copiar primeiro.', 0) end
    local targets,conflicts={},{}
    local function treeSize(target)
      if not fs.isDir(target) then return fs.getSize(target),1 end
      local bytes,count=0,1
      for _,name in ipairs(fs.list(target)) do local b,n=treeSize(fs.combine(target,name)); bytes,count=bytes+b,count+n end
      return bytes,count
    end
    local totalBytes,totalEntries=0,0
    for i,item in ipairs(clipboard.items) do
      local found=false
      for _,candidate in ipairs(sources) do if candidate.key==item.owner then found=true end end
      if not found or not fs.exists(item.path) then error('Origem indisponivel: '..item.name..'. Selecione novamente.',0) end
      local dest=fs.combine(path(),item.name)
      if fs.exists(dest) then conflicts[#conflicts+1]=item.name end
      if dest==item.path or dest:sub(1,#item.path+1)==item.path..'/' then error('Nao copie uma pasta para dentro dela mesma: '..item.name,0) end
      targets[i]=dest
      local bytes,count=treeSize(item.path); item.required=bytes+count*1024; item.target=dest
      totalBytes,totalEntries=totalBytes+bytes,totalEntries+count
    end
    if #conflicts>0 then
      if #clipboard.items==1 then targets[1]=newName('Ja existe. Novo nome para a copia:'); if not targets[1] then return end
      else error('Ja existem no destino: '..table.concat(conflicts,', ')..'. Renomeie ou remova antes.',0) end
    end
    for i,dest in ipairs(targets) do clipboard.items[i].target=dest; services.assertWritable(dest) end
    local free,capacity=fs.getFreeSpace(path()),fs.getCapacity(path())
    local required=totalBytes+totalEntries*1024
    local partial=false
    if type(free)=='number' and required>free then
      local used=type(capacity)=='number' and capacity>0 and math.floor((capacity-free)/capacity*100+0.5) or nil
      if clipboard.move and #clipboard.items>1 then
        partial=confirm('O lote inteiro nao cabe. Dados: '..sizeLabel(totalBytes)..', reserva estimada: '..sizeLabel(required)..', livre: '..sizeLabel(free)..(used and (', uso: '..used..'%') or '')..'. Mover agora somente os itens que couberem? Os demais continuarao selecionados.')
        if not partial then return end
      else
        show({'A operacao nao foi iniciada.','',
          'Dados selecionados: '..sizeLabel(totalBytes),'Reserva estimada: '..sizeLabel(required),
          'Espaco livre: '..sizeLabel(free),used and ('Unidade em '..used..'% de uso.') or '', '',
          current().virtual and 'RAID precisa de espaco para blocos, paridade e publicacao segura.' or 'Libere espaco ou escolha outra unidade.'},' Espaco insuficiente')
        return
      end
    end
    if not partial and current().virtual and type(free)=='number' and type(capacity)=='number' and capacity>0 then
      local projected=math.floor((capacity-free+required)/capacity*100+0.5)
      if projected>=90 and not confirm('Aviso: esta unidade RAID pode chegar a aproximadamente '..projected..'% de uso. Continuar?') then return end
    end
    local count=#clipboard.items
    local update=progress(clipboard.move and 'Mover' or 'Copiar')
    update(0,count,'Preparando '..count..' item(ns)...')
    if clipboard.move then
      local index,done=1,0
      while index<=#clipboard.items do
        local item=clipboard.items[index]
        local available=fs.getFreeSpace(path())
        if type(available)=='number' and item.required>available then index=index+1
        else
          local fromGuard,toGuard=pathGuard(item.path),pathGuard(item.target)
          services.moveItem(item.path,item.target,function() fromGuard(); toGuard() end)
          table.remove(clipboard.items,index); done=done+1; update(done,count,item.name)
        end
      end
      if #clipboard.items==0 then clipboard=nil; status=count..' item(ns) movidos e verificados.'
      else status=done..' movido(s); '..#clipboard.items..' ainda selecionado(s). Libere espaco e pressione V novamente.' end
    else
      for i,item in ipairs(clipboard.items) do fs.copy(item.path,targets[i]); update(i,count,item.name) end
      status=#clipboard.items..' item(ns) copiados.'
    end
  elseif command == 'r' then
    local item = requireItem(); protected(item)
    local dest = newName('Novo nome:'); if dest then fs.move(item.path, dest) end
  elseif command == 'x' then
    local item = requireItem(); protected(item)
    if confirm('Excluir ' .. item.name .. (item.dir and ' e seu conteudo?' or '?')) then
      fs.delete(item.path); status = 'Item excluido.'
    end
  elseif command == 'l' then
    if not current().drive then error('Escolha um disquete usando D.', 0) end
    local name = prompt('Nome do disquete (vazio cancela):')
    if name ~= '' then disk.setLabel(current().drive, name) end
  elseif command == 'j' then
    if not current().drive then error('Escolha um disquete usando D.', 0) end
    disk.eject(current().drive)
  elseif command == 'p' then printFile() end
end
local function main()
  boot()
  scan(); refresh()
  local raidTimer = os.startTimer(10)
  while running do
    draw()
    local event, a, b, c = os.pullEvent()
    local command
    if event == 'char' then command = a:lower()
    elseif event == 'key' then
      if a == keys.up then selected = math.max(1, selected - 1)
      elseif a == keys.down then selected = math.min(#entries, selected + 1)
      elseif a == keys.enter then command = 'open'
      elseif a == keys.backspace then command = 'back'
      elseif a == keys.escape or a == keys.f1 then command = 'clear'
      elseif a == keys.delete then command = 'x' end
    elseif event == 'mouse_scroll' then
      if b and b<=14 and W>=45 then unitScroll=math.max(0,math.min(math.max(0,#sources-math.max(1,H-10)),unitScroll+a))
      else selected = math.max(1, math.min(#entries, selected + a)) end
    elseif event == 'mouse_click' and (a == 1 or a == 2) then
      if a == 1 then
        for _, button in ipairs(buttons) do
          if c == button.y and b >= button.x and b <= button.last then command = button.action end
        end
      end
      if b >= listX and c >= listTop and c < listTop + listRows then
        local index = scroll + c - listTop + 1
        if entries[index] then
          local item = entries[index]
          selected = index
          if a == 2 then command = 'menu:context'
          elseif lastClick and lastClick.path == item.path and os.clock()-lastClick.time < 0.4 then
            command = 'open'; lastClick = nil
          else lastClick = {path=item.path,time=os.clock()} end
        end
      end
    end
    local ok, err = pcall(function()
      if command then action(command) end
      scan(); refresh()
      if running and (command or event=='disk' or event=='disk_eject' or event=='peripheral' or event=='peripheral_detach' or (event=='timer' and a==raidTimer)) then
        local note=virtual.notice(); if note then status=note end
        os.cancelTimer(raidTimer); raidTimer=os.startTimer(10)
      end
    end)
    if not ok then
      if tostring(err) == 'Terminated' then error(err, 0) end
      status = 'Erro: ' .. tostring(err)
    end
  end
end
-- Parallel keeps notifications alive while read(), help, or CraftOS edit waits.
-- No sleep here: sounds never consume or delay the user's input events.
local function watchDevices()
  while true do
    local event, drive, message, protocol = os.pullEvent()
    if event == 'rednet_message' then services.handleMessage(drive, message, protocol) end
    if event == 'disk' or event == 'disk_eject' then
      local inserted = event == 'disk'
      status = (inserted and 'Disco inserido: ' or 'Disco removido: ') .. tostring(drive)
      if not muted then
        pcall(function()
          for _, name in ipairs(peripheral.getNames()) do
            if peripheral.hasType(name, 'speaker') then
              local speaker = peripheral.wrap(name)
              speaker.playNote(inserted and 'pling' or 'bass', 0.5, inserted and 12 or 7)
              speaker.playNote(inserted and 'pling' or 'bass', 0.4, inserted and 19 or 0)
              break
            end
          end
        end)
      end
    end
  end
end
local ok, err = pcall(function() parallel.waitForAny(watchDevices, main) end)
services.closeWireless()
term.setBackgroundColor(colors.black); term.setTextColor(colors.white)
term.setCursorBlink(false); term.clear(); term.setCursorPos(1, 1)
if not ok then print(err) else print('DiskDesk encerrado.') end
