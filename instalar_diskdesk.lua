-- Instalador offline DiskDesk 3. Os arquivos do programa estao embutidos abaixo.
local payload = {
  {name=[=[
diskdesk.lua]=], contents=[=[
-- DiskDesk para CC: Tweaked. Salve no computador como diskdesk.lua.
local wrap = require('cc.strings').wrap
local services = dofile(fs.combine(fs.getDir(shell.getRunningProgram()), 'diskdesk_services.lua'))
local physicalFs=fs
local volumeFactory=dofile(fs.combine(fs.getDir(shell.getRunningProgram()),'diskdesk_volumes.lua'))
local virtual=volumeFactory(services,dofile(fs.combine(fs.getDir(shell.getRunningProgram()),'diskdesk_arrays.lua')))
local fs=virtual.fs
services.useFilesystem(fs)
local sources, source, folder = {}, 1, ''
local entries, selected, scroll = {}, 1, 0
local clipboard, job
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
local raidLabel = 'Desativado'
local raidShort = 'Desativado'
local arrayService, knownArrays = nil, {}
local function getArrays()
  if not arrayService then arrayService=dofile(fs.combine(fs.getDir(shell.getRunningProgram()),'diskdesk_arrays.lua'))(services) end
  return arrayService
end
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
local function choose(title, items, initial, bottom)
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
      put(x, y + row, width, (i == selectedOption and ' > ' or '   ') .. items[i],
        i == selectedOption and theme.select or theme.panel, theme.text)
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
  line(1, ' [D] DISKDESK / arquivos', theme.accent, colors.black)
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
    local first = math.max(1,source-capacity+1)
    for i=first,math.min(#sources,first+capacity-1) do
      local item,y=sources[i],4+i-first
      put(2,y,sidebar-2,(item.virtual and '= ' or (item.drive and 'o ' or '# '))..item.name,
        i==source and theme.select or theme.panel)
      buttons[#buttons+1]={x=1,last=sidebar,y=y,action='source:'..i}
    end
    if H>=13 then
      put(2,H-5,sidebar-2,'RAID: '..raidShort,theme.panel,theme.muted)
      put(2,H-4,sidebar-2,muted and 'SOM: mudo' or (deviceCount.speaker>0 and 'SOM: ligado' or 'Sem Speaker'),theme.panel,theme.muted)
    end
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
  line(H-3,' '..#entries..' itens | RAID: '..raidLabel,theme.panel,theme.muted)
  line(H-2,clipboard and ((clipboard.move and ' Mover: ' or ' Copiar: ')..clipboard.name..' | V: colar') or status,theme.bg,colors.yellow)
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
local function backupDisk()
  if not current().drive then error('Abra o disquete de origem antes de fazer backup.', 0) end
  local src = services.capture(current().drive)
  local dest = pickDisk('Disco para guardar o backup', src)
  if not dest then return end
  if not confirm('Backup de ' .. src.name .. ' (#' .. src.id .. ') para ' .. dest.name .. ' (#' .. dest.id .. ')? Versoes anteriores serao preservadas.') then return end
  local result = services.backup(src, dest, progress('Backup'))
  status = 'Backup verificado e salvo.'
  show({'Backup concluido e verificado.', '', result, '', 'O: Restaurar para recuperar arquivos.', 'Versoes antigas nao foram apagadas.'}, ' Backup concluido')
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
local function pathGuard(target)
  if virtual.isVirtual(target) then return function() virtual.guard(target) end end
  for _, item in ipairs(sources) do
    if item.drive and (target == item.root or target:sub(1, #item.root+1) == item.root .. '/') then
      local volume = services.capture(item.drive)
      return function() services.guard(volume) end
    end
  end
  return function() end
end
local function sendWireless()
  local item = requireItem()
  if item.dir then error('Selecione um arquivo para enviar.', 0) end
  services.openWireless()
  local peer = tonumber(prompt('ID do computador de destino (abra Receber nele):'))
  if not peer then return end
  services.sendFile(item.path, peer, pathGuard(item.path), progress('Enviar'))
  status = 'Arquivo entregue e verificado no ID ' .. peer .. '.'
end
local function receiveWireless()
  services.openWireless()
  local destination = path()
  local update = progress('Receber')
  update(0, 1, 'Seu ID: ' .. os.getComputerID() .. '. Aguardando envio por 60 segundos. Pasta: /' .. destination)
  local result = services.receiveFile(destination, pathGuard(destination), function(peer, name, size)
    return confirm('ID ' .. peer .. ' quer enviar ' .. name .. ' (' .. sizeLabel(size) .. '). Aceitar nesta pasta?')
  end, update)
  status = result and ('Recebido: ' .. fs.getName(result)) or 'Recebimento recusado.'
end
local function syncRaid()
  local ok,result=pcall(services.raidSync)
  if not ok and tostring(result)=='Terminated' then error(result,0) end
  raidLabel=ok and result or 'Pendente'
  raidShort=raidLabel
  if not ok then status='RAID pendente: '..tostring(result) end
  local checked,why=pcall(function()
    local arrays=getArrays()
    for _,m in ipairs(arrays.list()) do knownArrays[m.id]=m end
    local count,chosen,severity=0,nil,-1
    for _,m in pairs(knownArrays) do
      count=count+1
      local state=arrays.status(m)
      local rank=not state.readable and 2 or (#state.missing>0 and 1 or 0)
      if rank>severity or (rank==severity and m.id>chosen.id) then
        severity=rank; chosen={id=m.id,mode=m.mode,n=m.n,state=state}
      end
    end
    if chosen then
      local mode=chosen.mode=='10' and '1+0' or chosen.mode
      local label=severity==0 and 'Ativo' or (severity==1 and 'Degradado' or 'Indisponivel')
      raidShort=mode..' '..label
      local auto=raidLabel~='Desativado' and (' / R1 auto: '..raidLabel) or ''
      raidLabel=raidShort..' ('..(chosen.n-#chosen.state.missing)..'/'..chosen.n..')'..
        (count>1 and (' +'..(count-1)..' conj.') or '')..auto
    end
    local volumes=virtual.list()
    if #volumes>0 then
      local worst,priority=nil,-1
      for _,volume in ipairs(volumes) do
        local state=virtual.info(volume)
        local level=not state.readable and 2 or (state.writable and 0 or 1)
        if level>priority then worst={volume=volume,state=state}; priority=level end
      end
      local volume,state=worst.volume,worst.state
      raidShort=(volume.mode=='10' and '1+0' or volume.mode)..' '..state.text
      raidLabel=raidShort..' ('..(#volume.members-#state.missing)..'/'..#volume.members..') unidade'..
        (#volumes>1 and (' +'..(#volumes-1)) or '')
    end
    local note=virtual.notice(); if note then status=note end
  end)
  if not checked then
    if tostring(why)=='Terminated' then error(why,0) end
    raidShort='Verificar'; raidLabel='Falha ao verificar conjuntos'
    status='RAID: '..tostring(why)
  end
end
local function selectDisks(title,minimum,maximum,excluded,even)
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
local function raidMenu()
  while true do
    local state=services.raidStatus()
    local labels=state.enabled and {'Sincronizar agora','Ver estado dos discos','Desativar espelhamento'} or {'Configurar RAID 1','Como funciona'}
    local selectedAction=choose('RAID 1 / '..state.text,labels)
    if not selectedAction then return end
    if not state.enabled and selectedAction==1 then
      local selectedMode=choose('Modo de espelhamento',{'RAID 1: direto na raiz','RAID 1: pasta RAID1','RAID 1: varios espelhos (raiz)'})
      if not selectedMode then return end
      local occupied={}
      for _,volume in ipairs(virtual.list()) do for _,id in ipairs(volume.members) do occupied[id]=true end end
      local primary=pickDisk('Escolha o disco PRINCIPAL',nil,occupied)
      if not primary then return end
      occupied[primary.id]=true
      local mirrors=selectDisks('Marque os ESPELHOS',1,selectedMode==3 and 8 or 1,occupied)
      if not mirrors then return end
      local mode=selectedMode==2 and 'folder' or 'root'
      local ids={}; for _,unit in ipairs(mirrors) do ids[#ids+1]='#'..unit.id end
      local warning=mode=='root' and 'Copiar tudo para a RAIZ. Arquivos extras dos destinos serao removidos.' or 'Copiar para a pasta RAID1 dos destinos.'
      if confirm('Principal #'..primary.id..' -> '..table.concat(ids,', ')..'. '..warning..' Ativar?') then
        services.raidConfigure(primary,mirrors,mode)
        raidLabel=services.raidSync(progress('RAID 1'))
        status='RAID 1 ativado. Use o disco principal.'
      end
      return
    elseif state.enabled and selectedAction==1 then
      raidLabel=services.raidSync(progress('RAID 1')); status='RAID: '..raidLabel; return
    elseif state.enabled and selectedAction==3 then
      if confirm('Desativar RAID? Os arquivos do principal e da copia serao mantidos.') then
        services.raidDisable(); raidLabel='Desativado'; status='RAID desativado. Copia preservada.'
      end
      return
    else
      show({'RAID 1 por arquivos, em uma direcao.',
        state.enabled and ('Principal #'..state.primaryID..' / espelhos: '..table.concat(state.mirrorIDs,', ')) or 'Escolha os floppies pelo ID.',
        'Estado: '..state.text,'',
        'Modo: '..(state.mode=='root' and 'RAIZ (copia direta)' or 'pasta RAID1'),
        'Sincroniza apos acoes e a cada 10s no explorador.',
        'Sem um disco: estado Degradado.',
        'Ao reinserir o mesmo disco: sincroniza de novo.',
        'O espelho e protegido contra escrita pelo app.',
        'Exclusoes do principal tambem sao replicadas.',
        'Mantenha backups versionados para recuperacao.',
        'Espaco: copia anterior + nova durante a troca.',
        'Nao ha failover nem volume de blocos.',
        'Principal perdido? Recupere usando um espelho.'},' RAID 1 - informacoes')
    end
  end
end
local function arrayMenu()
  local arrays=getArrays()
  local operation=choose('RAID 0 / 1 / 5 / 6 / 1+0',{'Guardar item em novo conjunto','Abrir / recuperar conjunto','Como funcionam os modos'})
  if not operation then return end
  if operation==3 then
    show({'Conjuntos guardam uma versao do item selecionado.',
      'Os blocos ficam em .diskdesk-arrays nos discos.',
      'Nao monta uma unidade virtual do CraftOS.',
      'RAID 0: 2+ discos, divide dados, sem redundancia.',
      'RAID 1: 2+ discos, copia completa em cada um.',
      'RAID 5: 3+ discos, suporta perder 1 disco.',
      'RAID 6: 4+ discos, suporta perder 2 discos.',
      'RAID 1+0: 4/6/8 discos, espelhos em pares.',
      '1+0: deve restar um membro de cada par.',
      'Restaurar valida e extrai para uma pasta nova.',
      'Reconstruir grava membro perdido em outro floppy.',
      'Para atualizar dados, guarde uma nova versao.',
      'RAID 1 automatico continua no menu anterior.'},' Conjuntos RAID')
    return
  end
  if operation==1 then
    local item=requireItem()
    local modeIndex=choose('Tipo do novo conjunto',{'RAID 0 - divisao, SEM redundancia','RAID 1 - espelhos completos','RAID 5 - paridade simples','RAID 6 - paridade dupla','RAID 1+0 - pares de espelhos'})
    if not modeIndex then return end
    local mode=({'0','1','5','6','10'})[modeIndex]
    local minimum=({2,2,3,4,4})[modeIndex]
    local units=selectDisks('Marque discos do RAID '..mode,minimum,8,nil,mode=='10')
    if not units then return end
    local update=progress('Preparando conjunto RAID')
    update(0,1,'Compactando '..item.name)
    local payload=services.archivePack(item.path,pathGuard(item.path))
    local bytes=arrays.plan(#payload,mode,#units)
    local ids={}; for _,unit in ipairs(units) do ids[#ids+1]='#'..unit.id end
    local detail=mode=='10' and ' Pares na ordem: 1-2, 3-4, 5-6, 7-8.' or ''
    if not confirm('Guardar '..item.name..' em RAID '..mode..' nos discos '..table.concat(ids,', ')..'? '..sizeLabel(bytes)..' de blocos por disco + indice.'..detail..(mode=='0' and ' Perder qualquer disco impede recuperar os dados.' or '')) then return end
    local result=arrays.create(payload,item.name,mode,units,update)
    status='Conjunto RAID '..mode..' verificado.'
    show({'Conjunto: '..result.id,'RAID '..mode..' / '..#units..' discos','Conteudo: '..item.name,'Original preservado. Esta e uma versao fixa.','Para ler: RAID > Abrir / recuperar conjunto.'},' RAID salvo')
  else
    local sets=arrays.list(); if #sets==0 then error('Nenhum conjunto RAID encontrado nos discos conectados.',0) end
    local labels={}; for i,m in ipairs(sets) do labels[i]='RAID '..m.mode..' '..m.name..' / '..m.id end
    local index=choose('Conjuntos nos discos',labels); if not index then return end
    local m=sets[index]; local state=arrays.status(m)
    local task=choose('RAID '..m.mode..': '..state.text,{'Ver discos / integridade','Restaurar nesta pasta','Reconstruir disco perdido'})
    if task==1 then
      local lines={'Conjunto: '..m.id,'Estado: '..state.text,'Dados: '..sizeLabel(m.size),'Blocos por disco: '..sizeLabel(m.shardSize)}
      for i=1,m.n do lines[#lines+1]='Posicao '..i..': '..(state.volumes[i] and ('OK / disco #'..state.volumes[i].id) or 'ausente ou corrompido') end
      if m.mode=='10' then lines[#lines+1]='Pares: 1-2, 3-4, 5-6, 7-8 (se existirem).' end
      show(lines,' Integridade do conjunto')
    elseif task==2 then
      local target=newName('Nome de uma NOVA pasta para restaurar:'); if not target then return end
      arrays.restore(m,target,pathGuard(target),progress('Restaurar RAID'))
      status='RAID restaurado em '..fs.getName(target)
    elseif task==3 then
      if not state.readable then error('Reconecte mais membros originais para recuperar.',0) end
      if #state.missing==0 then status='Todos os membros estao integros.'; return end
      local missing={}; for i,slot in ipairs(state.missing) do missing[i]='Reconstruir posicao '..slot end
      local selectedSlot=choose('Membro perdido ou corrompido',missing); if not selectedSlot then return end
      local dest=pickDisk('Disco SUBSTITUTO',nil,state.occupied); if not dest then return end
      if not confirm('Reconstruir posicao '..state.missing[selectedSlot]..' no disco #'..dest.id..'? Outros arquivos serao preservados.') then return end
      arrays.rebuild(m,state.missing[selectedSlot],dest,progress('Reconstruindo RAID'))
      status='Membro RAID reconstruido e verificado.'
    end
  end
end
local function virtualMenu()
  local operation=choose('Unidades RAID em tempo real',{'Criar unidade RAID','Gerenciar unidade RAID','Importar unidade dos discos','Como usar'})
  if not operation then return end
  if operation==1 then
    local modeIndex=choose('Tipo da unidade RAID',{'RAID 0 - soma / sem redundancia','RAID 1 - espelho','RAID 5 - paridade simples','RAID 6 - paridade dupla','RAID 1+0 - pares de espelhos'})
    if not modeIndex then return end
    local mode=({'0','1','5','6','10'})[modeIndex]
    local excluded={}
    for _,volume in ipairs(virtual.list()) do for _,id in ipairs(volume.members) do excluded[id]=true end end
    local units=selectDisks('Marque os membros da unidade',({2,2,3,4,4})[modeIndex],8,excluded,mode=='10')
    if not units then return end
    local name=prompt('Nome da unidade RAID:'); if name=='' then return end
    local ids={}; for _,unit in ipairs(units) do ids[#ids+1]='#'..unit.id end
    if not confirm('Criar RAID '..mode..' em '..table.concat(ids,', ')..'? Copie os arquivos para a NOVA unidade em D.'..
      (mode=='10' and ' Pares seguem essa ordem.' or '')..(mode=='0' and ' Sem redundancia.' or '')) then return end
    local volume=virtual.create(name,mode,units)
    scan()
    for i,unit in ipairs(sources) do if unit.key=='virtual:'..volume.id then switchSource(i); break end end
    status='Unidade criada. Use C/M e V para copiar/mover para ela.'
  elseif operation==2 then
    local list=virtual.list(); if #list==0 then error('Crie ou importe uma unidade RAID primeiro.',0) end
    local labels={}; for i,volume in ipairs(list) do labels[i]='RAID '..volume.mode..' / '..volume.name end
    local index=choose('Unidade RAID',labels); if not index then return end
    local volume=list[index]; local state=virtual.info(volume)
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
  elseif operation==3 then
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
  local item=requireItem()
  if extract and item.dir then error('Selecione um pacote .ddz.',0) end
  local target=newName(extract and 'Nome da NOVA pasta para extrair:' or 'Nome do pacote (ex: documentos.ddz):')
  if not target then return end
  if not extract and target:sub(-4):lower()~='.ddz' then target=target..'.ddz' end
  local sourceGuard,targetGuard=pathGuard(item.path),pathGuard(target)
  local function guard() sourceGuard(); targetGuard() end
  if extract then
    services.extract(item.path,target,guard); status='Extraido em: '..fs.getName(target)
  else
    local original,packed=services.compress(item.path,target,guard)
    status='Pacote: '..sizeLabel(original)..' -> '..sizeLabel(packed)..(packed>=original and ' (inclui nomes/indice)' or (' (-'..math.floor((1-packed/original)*100)..'%)'))
  end
  filter=''
end
local helpTopics={
  {title='Unidades RAID em tempo real',text={'A > RAID e backup > Unidades RAID em tempo real. Crie uma unidade e selecione seus discos.',
    'Abra a nova unidade em D. C/M + V copia ou move para ela; os dados sao divididos ou espelhados automaticamente.',
    'RAID 0 soma a capacidade util dos discos iguais. RAID 1 espelha. RAID 5/6 reservam 1/2 membros para paridade; 1+0 usa metade para espelhos.',
    'Os percentuais e o espaco livre atualizam apos cada operacao. A capacidade e limitada pelo menor membro e reserva espaco para indices.',
    'N/T cria pastas/textos, R renomeia e Delete exclui. No editor, salve e saia para publicar nos discos. Se falhar, o rascunho fica no computador.',
    'Com membros ausentes, a unidade fica somente leitura se ainda houver redundancia. Reconstrua antes de gravar.',
    'Um arquivo alterado precisa de espaco para a versao nova antes de liberar a anterior. Falhas podem deixar blocos temporarios.',
    'Use Gerenciar para verificar ou reconstruir. Importar recupera o catalogo de uma unidade em outro computador.',
    'Arquivos copiados para a raiz fisica dos floppies continuam fora da unidade. Conjuntos antigos sao arquivos de versoes, em menu separado.'}},
  {title='Primeiros passos',text={'D escolhe computador ou disquete. Clique na unidade da barra lateral para trocar.',
    'Clique seleciona; duplo clique ou Enter abre. Backspace volta uma pasta.',
    'A abre o menu por categorias. Botao direito mostra acoes do item.',
    'F1 e o botao Voltar fecham menus sem sair da tela do PC. Esc pertence ao Minecraft.',
    'Q encerra o DiskDesk e volta ao terminal.'}},
  {title='Arquivos e mover',text={'N cria pasta. T abre um novo texto. E edita o arquivo selecionado.',
    'No editor: Ctrl > Save para salvar e Ctrl > Exit para sair. Nomes com espacos funcionam.',
    'C marca para copiar; M marca para mover. Abra a pasta de destino e use V para colar.',
    'Mover verifica a copia antes de excluir a origem. Se falhar, confira a origem e os arquivos .partial.',
    'R renomeia; Delete exclui com confirmacao. F busca nomes; F1 limpa o filtro.'}},
  {title='Discos e armazenamento',text={'USO mostra a porcentagem do disco atual. D abre as barras de cada unidade; vermelho indica 90% ou mais.',
    'D abre o painel com barras de uso, espaco livre e capacidade de cada unidade. Capacidade indisponivel aparece como --.',
    'L muda o nome do floppy. J ejeta. Speaker conectado toca ao inserir e retirar; U silencia.',
    'Arquivos muito pequenos tambem ocupam espaco de armazenamento.'}},
  {title='RAID 1 e backup',text={'A > RAID e backup reune configuracao, sincronizacao, backups e restauracao. I abre RAID diretamente.',
    'Modos: copia na RAIZ, pasta RAID1 e varios espelhos na raiz. Configuracao e salva pelo ID dos discos.',
    'RAIZ copia todos os arquivos e remove extras dos destinos. Confira os IDs antes de confirmar!',
    'Espelhamento automatico ao retornar de acoes e a cada 10s no explorador. Durante editor/dialogos ele aguarda voce voltar.',
    'Remocao de disco: Degradado. Recoloque o mesmo disco para reconstruir a copia. Nao ha failover automatico.',
    'Exclusoes sao espelhadas! B cria backups com versoes; O restaura versoes antigas.',
    'Para trocar a copia com seguranca, precisa caber a copia antiga e a nova no espelho.'}},
  {title='Compactacao DDZ',text={'A > Compactar e extrair. Selecione um arquivo ou pasta e escolha Compactar.',
    'O pacote .ddz preserva subpastas, arquivos binarios e pastas vazias. Pode enviar esse pacote pelo wireless.',
    'Para abrir, selecione o pacote, escolha Extrair e informe o nome de uma pasta nova.',
    'DDZ2 usa indice binario pequeno e comprime nomes e conteudo juntos. Continua lendo os pacotes DDZ1 antigos.',
    'Formato proprio, nao e ZIP. Arquivos minusculos podem crescer por causa dos nomes e do indice.',
    'Limites: 512 KiB descompactados e 1024 itens. Arquivos corrompidos ou caminhos invalidos sao rejeitados.'}},
  {title='RAID 0, 5, 6 e 1+0',text={'A > RAID e backup > Conjuntos RAID. Guarda uma versao fixa do arquivo ou pasta selecionado.',
    'Marque varios discos com clique ou Enter e selecione Confirmar. Maximo de 8 discos por conjunto.',
    'RAID 0: minimo 2 discos, divide dados sem redundancia. Todos precisam estar disponiveis para restaurar.',
    'RAID 5: minimo 3 discos, recupera 1 disco perdido. RAID 6: minimo 4, recupera 2 perdidos.',
    'RAID 1+0: 4, 6 ou 8 discos em pares. Pode perder um disco de cada par, nunca os dois do mesmo par.',
    'Abrir / recuperar conjunto verifica membros e restaura numa pasta nova. Reconstruir grava um membro em outro floppy.',
    'Conjuntos usam blocos em .diskdesk-arrays, nao sao unidades virtuais do CraftOS. Nao altere esses arquivos.',
    'Cada conjunto e uma versao independente. O espelhamento RAID 1 automatico permanece no menu anterior.'}},
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
  file = {{'Abrir / visualizar', 'open'}, {'Novo texto', 't'}, {'Nova pasta', 'n'}, {'Editar texto', 'e'}, {'Imprimir', 'p'}},
  edit = {{'C  Copiar', 'c'}, {'M  Mover', 'm'}, {'V  Colar', 'v'}, {'R  Renomear', 'r'}, {'Delete  Excluir...', 'x'}, {'F  Buscar nesta pasta', 'f'}},
  disk = {{'Escolher unidade', 'd'}, {'Criar backup...', 'b'}, {'Restaurar backup...', 'o'}, {'Nome do disquete', 'l'}, {'Ejetar disquete', 'j'}},
  net = {{'Enviar arquivo...', 's'}, {'Receber arquivo...', 'g'}},
  protect = {{'Unidades RAID em tempo real','virtual'}, {'Espelhamento automatico RAID 1','i'}, {'Conjuntos RAID (versoes arquivadas)','array'}, {'Criar backup com versoes','b'}, {'Restaurar backup','o'}},
  archive = {{'Compactar arquivo ou pasta (.ddz)','z'}, {'Extrair pacote .ddz','y'}},
  start = {{'[+] Arquivos e organizacao', 'menu:files'}, {'[%] Armazenamento dos discos', 'd'}, {'[=] RAID e backup', 'menu:protect'}, {'[Z] Compactar e extrair', 'menu:archive'}, {'[~] Rede wireless', 'menu:net'}, {'[?] Central de ajuda', 'h'}, {'[x] Sair do DiskDesk', 'q'}},
  files = {{'Criar / editar / imprimir','menu:file'}, {'Copiar / mover / renomear','menu:edit'}, {'Nomear / ejetar disquete','menu:disk'}},
  context = {{'Abrir', 'open'}, {'Editar', 'e'}, {'Copiar', 'c'}, {'Mover', 'm'}, {'Colar aqui', 'v'}, {'Renomear', 'r'}, {'Imprimir', 'p'}, {'Enviar por wireless', 's'}, {'Excluir...', 'x'}}
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
  elseif command == 'i' then raidMenu()
  elseif command == 'array' then arrayMenu()
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
    local item = requireItem()
    if command == 'm' then protected(item) end
    if fs.isDriveRoot(item.path) then error('Abra a unidade e copie seus itens.', 0) end
    -- Bind to the actual mount even when browsing /disk from Computador.
    local owner = current()
    for _, candidate in ipairs(sources) do
      if candidate.drive and (item.path == candidate.root or item.path:sub(1, #candidate.root + 1) == candidate.root .. '/') then owner = candidate end
    end
    clipboard = {path = item.path, name = item.name, owner = owner.key, move = command == 'm'}
    status = (clipboard.move and 'Mover: ' or 'Copiar: ') .. item.name .. '. Destino + V.'
  elseif command == 'v' then
    if not clipboard then error('Use C para copiar primeiro.', 0) end
    local found = false
    for _, candidate in ipairs(sources) do if candidate.key == clipboard.owner then found = true end end
    if not found or not fs.exists(clipboard.path) then error('Origem indisponivel. Copie novamente.', 0) end
    local dest = fs.combine(path(), clipboard.name)
    if fs.exists(dest) then dest = newName('Ja existe. Novo nome para a copia:') end
    if not dest then return end
    if dest == clipboard.path or dest:sub(1, #clipboard.path + 1) == clipboard.path .. '/' then
      error('Nao copie uma pasta para dentro dela mesma.', 0)
    end
    services.assertWritable(dest)
    if clipboard.move then
      local fromGuard,toGuard=pathGuard(clipboard.path),pathGuard(dest)
      services.moveItem(clipboard.path,dest,function() fromGuard(); toGuard() end)
      clipboard=nil; status='Movido e verificado.'
    else fs.copy(clipboard.path, dest); status = 'Copia concluida.' end
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
  scan(); refresh(); syncRaid()
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
    elseif event == 'mouse_scroll' then selected = math.max(1, math.min(#entries, selected + a))
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
        syncRaid()
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
]=]},
  {name=[=[
diskdesk_services.lua]=], contents=[=[
-- DiskDesk 3: verified, versioned backups and acknowledged wireless transfers.
local M = {protocol = 'diskdesk.transfer.v1', maxFile = 1024 * 1024, chunkSize = 8192}
local fs=fs
function M.useFilesystem(filesystem) fs=filesystem end
local serial, receipts, opened = 0, {}, {}
local function fail(message) error(message, 0) end
local function token()
  serial = serial + 1
  return tostring(os.getComputerID()) .. '-' .. tostring(os.epoch('utc')) .. '-' .. serial
end
local function unique(base)
  local path, n = base, 1
  while fs.exists(path) or fs.exists(path .. '.partial') do n = n + 1; path = base .. '-' .. n end
  return path
end
local function open(path, mode)
  local handle, err = fs.open(path, mode)
  if not handle then fail(err or ('Nao foi possivel abrir ' .. path)) end
  return handle
end
local function close(handle) if handle then pcall(handle.close) end end
local function update(a, b, data)
  for i = 1, #data do a = (a + data:byte(i)) % 65521; b = (b + a) % 65521 end
  return a, b
end
function M.checksum(data)
  local a, b = update(1, 0, data)
  return b * 65536 + a
end
function M.safeName(name)
  return type(name) == 'string' and #name > 0 and #name <= 128 and
    name ~= '.' and name ~= '..' and not name:find('[/\\:*?"<>|]') and not name:find('%c')
end
local function safeRelative(path)
  if type(path) ~= 'string' or path == '' or #path > 512 or path:sub(1, 1) == '/' then return false end
  if path:find('//', 1, true) or path:sub(-1) == '/' then return false end
  for part in path:gmatch('[^/]+') do if not M.safeName(part) then return false end end
  return true
end
function M.capture(drive)
  local root, id = disk.getMountPath(drive), disk.getID(drive)
  if not root or not id then fail('Insira um floppy disk no drive ' .. drive .. '.') end
  return {drive = drive, root = fs.combine(root, ''), id = id, name = disk.getLabel(drive) or ('Disco ' .. id)}
end
function M.guard(volume)
  if volume and (disk.getID(volume.drive) ~= volume.id or disk.getMountPath(volume.drive) ~= volume.root) then
    fail('Disquete removido ou trocado. Operacao interrompida.')
  end
end
local function hashFile(path, guard)
  guard()
  local handle = open(path, 'rb')
  local a, b, size = 1, 0, 0
  local ok, err = pcall(function()
    while true do
      guard()
      local data = handle.read(M.chunkSize)
      if not data then break end
      size = size + #data; a, b = update(a, b, data)
    end
  end)
  close(handle)
  if not ok then fail(err) end
  return size, b * 65536 + a
end
local function copyVerified(src, dest, guard)
  guard()
  local input, output = open(src, 'rb'), nil
  local a, b, size = 1, 0, 0
  local ok, err = pcall(function()
    output = open(dest, 'wb')
    while true do
      guard()
      local data = input.read(M.chunkSize)
      if not data then break end
      output.write(data); size = size + #data; a, b = update(a, b, data)
    end
  end)
  close(input); close(output)
  if not ok then fail(err) end
  local actualSize, actualHash = hashFile(dest, guard)
  if actualSize ~= size or actualHash ~= b * 65536 + a then fail('Falha na verificacao da copia.') end
  return size, actualHash
end
local function room(path, bytes)
  if fs.isReadOnly(path) then fail('Destino somente leitura.') end
  local free = fs.getFreeSpace(path)
  if type(free) == 'number' and free < bytes then fail('Espaco insuficiente no destino.') end
end
local function inventory(root, guard, includeHistory)
  local list, total = {}, 0
  local function walk(relative, depth)
    if depth > 32 then fail('Limite de 32 niveis de pastas.') end
    guard()
    local names = fs.list(fs.combine(root, relative)); table.sort(names)
    for _, name in ipairs(names) do
      -- Do not back up backup history, including a recovered partial snapshot.
      if includeHistory or not (relative == '' and name == '.diskdesk-backups') then
        local rel = fs.combine(relative, name)
        if not safeRelative(rel) then fail('Nome nao suportado: ' .. rel) end
        local full = fs.combine(root, rel)
        local dir = fs.isDir(full)
        if not fs.isDriveRoot(full) then
          list[#list + 1] = {path = rel, dir = dir}
          if #list > 1024 then fail('Limite de 1024 itens por backup.') end
          if dir then walk(rel, depth + 1) else total = total + fs.getSize(full) end
        elseif includeHistory then fail('Nao mova pastas que contenham unidades montadas.') end
      end
    end
  end
  walk('', 0)
  return list, total
end
function M.backup(src, dest, progress)
  M.assertWritable(dest.root)
  if src.id == dest.id or src.root == dest.root then fail('Escolha dois disquetes diferentes.') end
  local function guard() M.guard(src); M.guard(dest) end
  local list, total = inventory(src.root, guard)
  room(dest.root, total + (#list + 4) * 1024)
  local final = unique(fs.combine(dest.root, '.diskdesk-backups/' .. src.id .. '/' .. token()))
  local staging = final .. '.partial'
  guard(); fs.makeDir(fs.combine(staging, 'data'))
  -- On failure, leave .partial for inspection. Never touch an earlier snapshot.
  for i, item in ipairs(list) do
    guard()
    local out = fs.combine(staging .. '/data', item.path)
    if item.dir then fs.makeDir(out)
    else item.size, item.hash = copyVerified(fs.combine(src.root, item.path), out, guard) end
    if progress then progress(i, #list, item.path) end
  end
  guard()
  local manifest = {version = 1, source = src.id, label = src.name, created = os.epoch('utc'), entries = list}
  local encoded = textutils.serialize(manifest)
  if #encoded > 128 * 1024 then fail('Indice do backup excede 128 KiB.') end
  local handle = open(staging .. '/manifest', 'w')
  local ok, err = pcall(handle.write, encoded); close(handle)
  if not ok then fail(err) end
  guard(); fs.move(staging, final)
  return final, #list
end
function M.snapshots(volume)
  M.guard(volume)
  local root, results = fs.combine(volume.root, '.diskdesk-backups'), {}
  if not fs.exists(root) then return results end
  for _, id in ipairs(fs.list(root)) do
    local parent = fs.combine(root, id)
    if fs.isDir(parent) then
      for _, name in ipairs(fs.list(parent)) do
        local path = fs.combine(parent, name)
        if not name:match('%.partial$') and fs.exists(path .. '/manifest') then
          results[#results + 1] = {path = path, name = 'Disco ' .. id .. ' / ' .. name}
        end
      end
    end
  end
  table.sort(results, function(a,b) return a.path > b.path end)
  return results
end
function M.restore(snapshot, src, dest, progress)
  M.assertWritable(dest.root)
  local function guard() M.guard(src); M.guard(dest) end
  guard()
  local prefix = src.root .. '/.diskdesk-backups/'
  if snapshot:sub(1, #prefix) ~= prefix or snapshot:find('..', 1, true) then fail('Backup invalido.') end
  if fs.getSize(snapshot .. '/manifest') > 128 * 1024 then fail('Indice muito grande.') end
  local handle = open(snapshot .. '/manifest', 'r')
  local content = handle.readAll(); close(handle)
  local manifest = textutils.unserialize(content)
  if type(manifest) ~= 'table' or manifest.version ~= 1 or type(manifest.entries) ~= 'table' or #manifest.entries > 1024 then
    fail('Indice de backup invalido.')
  end
  local seen, total = {}, 0
  for _, item in ipairs(manifest.entries) do
    if type(item) ~= 'table' or not safeRelative(item.path) or seen[item.path] or type(item.dir) ~= 'boolean' then fail('Caminho invalido no backup.') end
    seen[item.path] = true
    if not item.dir then
      if type(item.size) ~= 'number' or item.size < 0 or item.size % 1 ~= 0 or type(item.hash) ~= 'number' then fail('Indice de arquivo invalido.') end
      total = total + item.size
      local size, hash = hashFile(fs.combine(snapshot .. '/data', item.path), guard)
      if size ~= item.size or hash ~= item.hash then fail('Backup corrompido: ' .. item.path) end
    end
  end
  room(dest.root, total + (#manifest.entries + 2) * 1024)
  local final = unique(fs.combine(dest.root, 'Restaurado-' .. token()))
  local staging = final .. '.partial'
  guard(); fs.makeDir(staging)
  for i, item in ipairs(manifest.entries) do
    guard()
    local target = fs.combine(staging, item.path)
    if item.dir then fs.makeDir(target)
    else
      fs.makeDir(fs.getDir(target))
      local size, hash = copyVerified(fs.combine(snapshot .. '/data', item.path), target, guard)
      if size ~= item.size or hash ~= item.hash then fail('Backup alterado durante a restauracao.') end
    end
    if progress then progress(i, #manifest.entries, item.path) end
  end
  guard(); fs.move(staging, final)
  return final
end
function M.openWireless()
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.hasType(name, 'modem') and peripheral.wrap(name).isWireless() then
      if not rednet.isOpen(name) then rednet.open(name); opened[name] = true end
      return name
    end
  end
  fail('Conecte um Wireless Modem ou Ender Modem.')
end
function M.closeWireless()
  for name in pairs(opened) do pcall(rednet.close, name) end
  opened = {}
end
local function send(peer, packet)
  if not rednet.send(peer, packet, M.protocol) then fail('Modem desconectado.') end
end
-- Only recent completed transfers can be acknowledged in the background.
function M.handleMessage(peer, msg, protocol)
  if protocol ~= M.protocol or type(msg) ~= 'table' or msg.kind ~= 'finish' then return end
  for _, receipt in ipairs(receipts) do
    if receipt.peer == peer and receipt.token == msg.token and os.clock() < receipt.untilTime then
      pcall(send, peer, {kind = 'done', token = msg.token}); return
    end
  end
end
local function waitPacket(peer, session, seconds)
  local timer = os.startTimer(seconds)
  while true do
    local event, a, b, c = os.pullEvent()
    if event == 'timer' and a == timer then return nil end
    if event == 'key' and (a == keys.escape or a == keys.f1) then os.cancelTimer(timer); fail('Transferencia cancelada.') end
    if event == 'rednet_message' and c == M.protocol and (peer == nil or a == peer) and type(b) == 'table' and
      (session == nil or b.token == session) then
      os.cancelTimer(timer); return b, a
    end
  end
end
local function exchange(peer, packet, expected, timeout)
  for _ = 1, (expected == 'accept' and 18 or 3) do
    send(peer, packet)
    local deadline = os.clock() + timeout
    repeat
      local response = waitPacket(peer, packet.token, math.max(0.01, deadline - os.clock()))
      if not response then break end
      if response.kind == 'reject' then fail('Destino recusou: ' .. tostring(response.reason):sub(1, 100)) end
      if response.kind == expected and (expected ~= 'ack' or response.seq == packet.seq) then return end
    until os.clock() >= deadline
  end
  fail(expected == 'done' and 'Sem confirmacao final. Confira o arquivo no destino.' or 'Sem resposta. Confira ID, alcance e modo Receber.')
end
function M.sendFile(path, peer, guard, progress)
  if type(peer) ~= 'number' or peer < 0 or peer % 1 ~= 0 or peer == os.getComputerID() then fail('ID de destino invalido.') end
  guard = guard or function() end
  M.openWireless(); guard()
  if fs.isDir(path) then fail('Selecione um arquivo, nao uma pasta.') end
  local size = fs.getSize(path)
  if size > M.maxFile then fail('Limite wireless: 1 MiB por arquivo.') end
  local hash
  size, hash = hashFile(path, guard)
  if size > M.maxFile then fail('Arquivo cresceu alem do limite.') end
  local session = token()
  local name = fs.getName(path)
  if not M.safeName(name) then fail('Nome de arquivo nao suportado.') end
  if progress then progress(0, size, 'Aguardando aceitacao no destino...') end
  exchange(peer, {kind = 'offer', token = session, name = name, size = size, hash = hash}, 'accept', 5)
  guard()
  local handle = open(path, 'rb')
  local ok, err = pcall(function()
    local count, seq = 0, 0
    while true do
      guard()
      local data = handle.read(M.chunkSize)
      if not data then break end
      seq = seq + 1; count = count + #data
      if count > size then fail('Arquivo alterado durante o envio.') end
      exchange(peer, {kind = 'chunk', token = session, seq = seq, data = data}, 'ack', 2)
      if progress then progress(count, size, name) end
    end
    exchange(peer, {kind = 'finish', token = session}, 'done', 2)
  end)
  close(handle)
  if not ok then fail(err) end
  return name
end
function M.receiveFile(folder, guard, accept, progress)
  M.assertWritable(folder)
  guard = guard or function() end
  M.openWireless(); guard()
  local offer, peer
  local deadline = os.clock() + 60
  repeat
    offer, peer = waitPacket(nil, nil, math.max(0.01, deadline - os.clock()))
    if not offer then fail('Nenhum envio em 60 segundos. Abra Receber novamente.') end
    if offer.kind ~= 'offer' then offer = nil end
  until offer or os.clock() >= deadline
  if not offer then fail('Tempo de espera encerrado.') end
  if not M.safeName(offer.name) or type(offer.token) ~= 'string' or #offer.token > 96 or
    type(offer.size) ~= 'number' or offer.size < 0 or offer.size > M.maxFile or offer.size % 1 ~= 0 or
    type(offer.hash) ~= 'number' or offer.hash < 0 or offer.hash >= 4294967296 or offer.hash % 1 ~= 0 then
    fail('Oferta de arquivo invalida.')
  end
  if not accept(peer, offer.name, offer.size) then
    send(peer, {kind = 'reject', token = offer.token, reason = 'usuario cancelou'}); return nil
  end
  local final, temp, output
  local ok, err = pcall(function()
    guard(); room(folder, offer.size + 1024)
    final = unique(fs.combine(folder, offer.name))
    temp = final .. '.partial'
    output = open(temp, 'wb')
    send(peer, {kind = 'accept', token = offer.token})
    local seq, count = 0, 0
    local deadline = os.clock() + 15
    while true do
      if os.clock() >= deadline then fail('Envio interrompido. Arquivo parcial nao publicado.') end
      local msg = waitPacket(peer, offer.token, deadline - os.clock())
      guard()
      if not msg then fail('Envio interrompido. Arquivo parcial nao publicado.') end
      if msg.kind == 'offer' then send(peer, {kind = 'accept', token = offer.token})
      elseif msg.kind == 'chunk' then
        if type(msg.seq) ~= 'number' or type(msg.data) ~= 'string' or #msg.data == 0 or #msg.data > M.chunkSize then fail('Pacote invalido.') end
        if msg.seq == seq + 1 then
          if count + #msg.data > offer.size then fail('Arquivo excede tamanho anunciado.') end
          output.write(msg.data); count = count + #msg.data; seq = msg.seq
          deadline = os.clock() + 15
          if progress then progress(count, offer.size, offer.name) end
        elseif msg.seq ~= seq then fail('Sequencia de pacotes invalida.') end
        send(peer, {kind = 'ack', token = offer.token, seq = seq})
      elseif msg.kind == 'finish' then
        close(output); output = nil
        local size, hash = hashFile(temp, guard)
        if size ~= offer.size or hash ~= offer.hash then fail('Arquivo incompleto ou corrompido.') end
        guard()
        if fs.exists(final) then fail('Destino passou a existir. Arquivo parcial preservado.') end
        fs.move(temp, final)
        receipts[#receipts + 1] = {peer = peer, token = offer.token, untilTime = os.clock() + 30}
        if #receipts > 8 then table.remove(receipts, 1) end
        -- Publication succeeded even if the acknowledgement cannot be sent.
        -- The background receipt cache answers a repeated finish packet.
        pcall(send, peer, {kind = 'done', token = offer.token})
        return
      end
    end
  end)
  close(output)
  if not ok then
    pcall(send, peer, {kind = 'reject', token = offer.token, reason = tostring(err):sub(1, 100)})
    -- Only clean up on the same mounted destination. Otherwise leave .partial.
    local safe = pcall(guard)
    if safe and temp and fs.exists(temp) then pcall(fs.delete, temp) end
    fail(err)
  end
  return final
end
local raidPath = '.diskdesk-raid.cfg'
local raid, raidLoaded, raidState = nil, false, 'Desativado'
function M.raidLoad()
  if raidLoaded then return raid end
  if fs.exists(raidPath) then
    if fs.getSize(raidPath) > 4096 then fail('Configuracao RAID invalida.') end
    local file = open(raidPath, 'r'); local contents = file.readAll(); file.close()
    local value = textutils.unserialize(contents)
    if type(value) ~= 'table' or value.version ~= 1 or type(value.primary) ~= 'number' or
      type(value.mirror) ~= 'number' or value.primary == value.mirror then fail('Configuracao RAID invalida.') end
    if value.mode~=nil and value.mode~='folder' and value.mode~='root' then fail('Modo RAID desconhecido.') end
    if value.mirrors~=nil then
      if type(value.mirrors)~='table' or #value.mirrors<1 or #value.mirrors>8 then fail('Lista de espelhos invalida.') end
      local seen={[value.primary]=true}
      for _,id in ipairs(value.mirrors) do
        if type(id)~='number' or seen[id] then fail('ID de espelho invalido.') end
        seen[id]=true
      end
    end
    raid = value; raidState = 'Pendente'
  end
  raidLoaded = true
  return raid
end
local function raidVolumes()
  local cfg=M.raidLoad()
  if not cfg then return end
  local connected={}
  for _,name in ipairs(peripheral.getNames()) do
    if peripheral.hasType(name,'drive') and disk.getID(name) then
      connected[disk.getID(name)]=M.capture(name)
    end
  end
  local ids=cfg.mirrors or {cfg.mirror}
  local mirrors={}
  for i,id in ipairs(ids) do mirrors[i]=connected[id] or false end
  return connected[cfg.primary],mirrors[1],mirrors
end
function M.raidStatus()
  local cfg=M.raidLoad()
  if not cfg then return {text='Desativado'} end
  local primary,mirror,mirrors=raidVolumes()
  local complete=primary~=nil
  for _,item in ipairs(mirrors) do if not item then complete=false end end
  return {text=complete and raidState or 'Degradado',primary=primary,mirror=mirror,mirrors=mirrors,
    primaryID=cfg.primary,mirrorID=cfg.mirror,mirrorIDs=cfg.mirrors or {cfg.mirror},mode=cfg.mode or 'folder',enabled=true}
end
function M.assertWritable(path)
  local _,_,mirrors=raidVolumes()
  for _,mirror in ipairs(mirrors or {}) do
    if mirror and (path==mirror.root or path:sub(1,#mirror.root+1)==mirror.root..'/') then
      fail('Disco espelho RAID protegido. Edite o disco principal.')
    end
  end
end
function M.raidConfigure(primary,mirror,mode)
  mode=mode or 'folder'
  if mode~='folder' and mode~='root' then fail('Modo RAID invalido.') end
  if M.raidLoad() then fail('Desative o par atual antes de configurar outro.') end
  local mirrors=mirror.drive and {mirror} or mirror
  if #mirrors<1 or #mirrors>8 then fail('Escolha de 1 a 8 espelhos.') end
  M.guard(primary)
  local ids,seen={}, {[primary.id]=true}
  for _,volume in ipairs(mirrors) do
    M.guard(volume)
    if seen[volume.id] then fail('RAID precisa de disquetes diferentes.') end
    seen[volume.id]=true; ids[#ids+1]=volume.id
    local reserved={'.diskdesk-raid-next','.diskdesk-raid-old','.diskdesk-raid-journal','.diskdesk-raid-ready','.diskdesk-raid-committed'}
    if mode=='folder' then reserved[#reserved+1]='RAID1' end
    for _,name in ipairs(reserved) do
      if fs.exists(fs.combine(volume.root,name)) then fail('Destino ja contem dados RAID. Renomeie ou use outro disco.') end
    end
    room(volume.root,1024)
  end
  local cfg={version=1,primary=primary.id,mirror=ids[1],mirrors=ids,mode=mode}
  local data=textutils.serialize(cfg)
  local file=open(raidPath..'.tmp','w')
  local ok,err=pcall(file.write,data); close(file)
  if not ok then fail(err) end
  file=open(raidPath..'.tmp','r'); local actual=file.readAll(); close(file)
  if actual~=data then fail('Falha ao gravar configuracao RAID.') end
  fs.move(raidPath..'.tmp',raidPath)
  raid,raidLoaded,raidState=cfg,true,'Pendente'
end
function M.raidDisable()
  if fs.exists(raidPath) then fs.delete(raidPath) end
  raid,raidLoaded,raidState=nil,true,'Desativado'
end
local function rootJournal(dest)
  return fs.combine(dest.root,'.diskdesk-raid-journal'),fs.combine(dest.root,'.diskdesk-raid-ready'),fs.combine(dest.root,'.diskdesk-raid-committed')
end
local function recoverRoot(dest,guard)
  local journal,ready,committed=rootJournal(dest)
  local stage,old=dest.root..'/.diskdesk-raid-next',dest.root..'/.diskdesk-raid-old'
  local function remove(p) guard(); if fs.exists(p) then fs.delete(p) end end
  guard()
  if fs.exists(committed) then
    remove(old); remove(stage); remove(ready); remove(journal); remove(committed); return
  end
  if not fs.exists(journal) then
    if fs.exists(old) then fail('RAID: copia antiga sem indice. Recuperacao manual necessaria.') end
    return
  end
  if fs.getSize(journal)>128*1024 then fail('Indice de recuperacao RAID invalido.') end
  local file=open(journal,'r'); local value=textutils.unserialize(file.readAll()); close(file)
  if type(value)~='table' or type(value.old)~='table' or type(value.new)~='table' then fail('Indice de recuperacao RAID invalido.') end
  for _,list in ipairs({value.old,value.new}) do
    if #list>1024 then fail('Indice de recuperacao RAID muito grande.') end
    for _,name in ipairs(list) do
      if not M.safeName(name) or name:match('^%.diskdesk%-raid%-') then fail('Nome invalido no indice RAID.') end
    end
  end
  if fs.exists(ready) then
    for _,name in ipairs(value.new) do remove(fs.combine(dest.root,name)) end
    remove(ready) -- After this point, a repeated recovery must not remove restored files.
  end
  for _,name in ipairs(value.old) do
    guard(); local from,to=fs.combine(old,name),fs.combine(dest.root,name)
    if fs.exists(from) then
      if fs.exists(to) then fail('Conflito na recuperacao RAID: '..name) end
      fs.move(from,to)
    end
  end
  remove(old); remove(stage); remove(journal)
end
local function publishRoot(dest,stage,guard)
  local journal,ready,committed=rootJournal(dest)
  local old=dest.root..'/.diskdesk-raid-old'
  local previous={}
  for _,name in ipairs(fs.list(dest.root)) do
    if not name:match('^%.diskdesk%-raid%-') then previous[#previous+1]=name end
  end
  local incoming=fs.list(stage)
  guard(); fs.makeDir(old)
  local encoded=textutils.serialize({old=previous,new=incoming})
  local f=open(journal,'w'); local ok,err=pcall(f.write,encoded); close(f)
  if not ok then fail(err) end
  f=open(journal,'r'); local actual=f.readAll(); close(f)
  if actual~=encoded then fail('Falha ao verificar indice de recuperacao RAID.') end
  for _,name in ipairs(previous) do guard(); fs.move(fs.combine(dest.root,name),fs.combine(old,name)) end
  guard(); f=open(ready,'w'); f.write('ready'); f.close()
  for _,name in ipairs(incoming) do guard(); fs.move(fs.combine(stage,name),fs.combine(dest.root,name)) end
  guard(); f=open(committed,'w'); f.write('done'); f.close()
  recoverRoot(dest,guard)
end
local function syncOne(src,dest,progress)
  local function guard() M.guard(src); M.guard(dest) end
  local rootMode=raid.mode=='root'
  local final=rootMode and dest.root or fs.combine(dest.root,'RAID1')
  local stage=fs.combine(dest.root,'.diskdesk-raid-next')
  local old=fs.combine(dest.root,'.diskdesk-raid-old')
  raidState='Pendente'
  local ok,result=pcall(function()
    guard()
    if rootMode then recoverRoot(dest,guard) end
    -- Recover a publication interrupted between moving the old and new copies.
    if not rootMode and fs.exists(old) then
      if not fs.exists(final) then fs.move(old,final) else fs.delete(old) end
    end
    if fs.exists(stage) then fs.delete(stage) end
    if rootMode then
      for _,name in ipairs(fs.list(src.root)) do
        if name:match('^%.diskdesk%-raid%-') then fail('Origem contem pastas reservadas de recuperacao RAID.') end
      end
    end
    local items,total=inventory(src.root,guard,rootMode)
    local equal=fs.exists(final) and fs.isDir(final)
    local existing=equal and inventory(final,guard,rootMode) or {}
    if #existing~=#items then equal=false end
    for _,item in ipairs(items) do
      guard()
      local source=fs.combine(src.root,item.path)
      local target=fs.combine(final,item.path)
      if not item.dir then item.size,item.hash=hashFile(source,guard) end
      if not fs.exists(target) or fs.isDir(target)~=item.dir then equal=false
      elseif not item.dir then
        local size,hash=hashFile(target,guard)
        if size~=item.size or hash~=item.hash then equal=false end
      end
    end
    if equal then return 'Sincronizado' end
    room(dest.root,total+(#items+2)*1024)
    fs.makeDir(stage)
    for i,item in ipairs(items) do
      guard()
      local target=fs.combine(stage,item.path)
      if item.dir then fs.makeDir(target)
      else
        local size,hash=copyVerified(fs.combine(src.root,item.path),target,guard)
        if size~=item.size or hash~=item.hash then fail('Origem mudou durante o espelhamento. Tente novamente.') end
      end
      if progress then progress(i,#items,item.path) end
    end
    guard()
    -- Verify that files were not added/deleted while staging.
    local latest=inventory(src.root,guard,rootMode)
    if #latest~=#items then fail('Origem mudou durante o espelhamento.') end
    for i,item in ipairs(latest) do
      local before=items[i]
      if item.path~=before.path or item.dir~=before.dir then fail('Origem mudou durante o espelhamento.') end
      if not item.dir then
        local size,hash=hashFile(fs.combine(src.root,item.path),guard)
        if size~=before.size or hash~=before.hash then fail('Origem mudou durante o espelhamento.') end
      end
    end
    guard()
    if rootMode then publishRoot(dest,stage,guard)
    else
      if fs.exists(final) then fs.move(final,old) end
      guard(); fs.move(stage,final)
      guard(); if fs.exists(old) then fs.delete(old) end
    end
    return 'Sincronizado'
  end)
  if not ok then raidState='Pendente'; fail(result) end
  raidState=result
  return result
end
function M.raidSync(progress)
  if not M.raidLoad() then return 'Desativado' end
  local primary,_,mirrors=raidVolumes()
  if not primary then raidState='Degradado'; return raidState end
  local degraded,errors=false,{}
  for _,mirror in ipairs(mirrors) do
    if not mirror then degraded=true else
      local ok,result=pcall(syncOne,primary,mirror,progress)
      if not ok then
        if tostring(result)=='Terminated' then fail(result) end
        errors[#errors+1]='#'..mirror.id..': '..tostring(result)
      end
    end
  end
  if #errors>0 then raidState='Pendente'; fail(table.concat(errors,' | ')) end
  raidState=degraded and 'Degradado' or 'Sincronizado'
  return raidState
end
function M.moveItem(source,target,guard)
  guard=guard or function() end
  guard(); M.assertWritable(source); M.assertWritable(target)
  if fs.isDriveRoot(source) then fail('Nao e possivel mover uma unidade.') end
  if target==source or target:sub(1,#source+1)==source..'/' then fail('Destino dentro da propria origem.') end
  if fs.exists(target) or fs.exists(target..'.partial') then fail('Destino ja existe.') end
  local staging=target..'.partial'
  local dir=fs.isDir(source)
  local items,total
  if dir then items,total=inventory(source,guard,true)
  else items={{path='',dir=false}}; total=fs.getSize(source) end
  room(fs.getDir(target),total+(#items+1)*1024)
  if dir then fs.makeDir(staging) end
  for _,item in ipairs(items) do
    guard()
    local from=dir and fs.combine(source,item.path) or source
    local to=dir and fs.combine(staging,item.path) or staging
    if item.dir then fs.makeDir(to) else item.size,item.hash=copyVerified(from,to,guard) end
  end
  local latest=dir and inventory(source,guard,true) or items
  if #latest~=#items then fail('Origem mudou durante a copia; nao foi removida.') end
  for i,item in ipairs(items) do
    if latest[i].path~=item.path or latest[i].dir~=item.dir then fail('Origem mudou durante a copia.') end
    if not item.dir then
      local size,hash=hashFile(dir and fs.combine(source,item.path) or source,guard)
      if size~=item.size or hash~=item.hash then fail('Origem mudou; nao foi removida.') end
    end
  end
  guard(); fs.move(staging,target)
  guard(); fs.delete(source)
  return target
end
-- DDZ2: compact binary tree and whole-body LZW; DDZ1 remains readable.
local archiveLimit=512*1024
local function lzwEncode(text)
  if #text==0 then return '' end
  local dict={}; for i=0,255 do dict[string.char(i)]=i end
  local nextCode,word,out=256,'',{}
  local function emit(code) out[#out+1]=string.char(math.floor(code/256),code%256) end
  for i=1,#text do
    local ch=text:sub(i,i); local both=word..ch
    if dict[both] then word=both else
      emit(dict[word])
      if nextCode<4096 then dict[both]=nextCode; nextCode=nextCode+1 end
      word=ch
    end
    if i%8192==0 and sleep then sleep(0) end
  end
  if word~='' then emit(dict[word]) end
  return table.concat(out)
end
local function lzwDecode(data,expected)
  if #data%2~=0 then fail('Bloco DDZ incompleto.') end
  local dict={}; for i=0,255 do dict[i]=string.char(i) end
  local nextCode,previous,out,size=256,nil,{},0
  for i=1,#data,2 do
    local code=data:byte(i)*256+data:byte(i+1)
    local entry=dict[code]
    if not entry and code==nextCode and previous then entry=previous..previous:sub(1,1) end
    if not entry then fail('Codigo LZW invalido.') end
    size=size+#entry; if size>expected then fail('Conteudo DDZ excede tamanho declarado.') end
    out[#out+1]=entry
    if previous and nextCode<4096 then dict[nextCode]=previous..entry:sub(1,1); nextCode=nextCode+1 end
    previous=entry
    if i%8192==1 and sleep then sleep(0) end
  end
  if size~=expected then fail('Tamanho DDZ incorreto.') end
  return table.concat(out)
end
local function readBounded(path,limit)
  if fs.getSize(path)>limit then fail('Arquivo excede limite de '..limit..' bytes.') end
  local f=open(path,'rb'); local data=f.readAll(); close(f)
  if #data>limit then fail('Arquivo cresceu durante a leitura.') end
  return data
end
local function writeVerified(path,data,guard)
  guard(); local f=open(path,'wb')
  local ok,err=pcall(f.write,data); close(f)
  if not ok then fail(err) end
  guard(); local size,hash=hashFile(path,guard)
  if size~=#data or hash~=M.checksum(data) then fail('Falha ao verificar arquivo gravado.') end
end
local function varint(n)
  local out={}
  repeat local b=n%128; n=math.floor(n/128); out[#out+1]=string.char(b+(n>0 and 128 or 0)) until n==0
  return table.concat(out)
end
local function numberReader(data)
  local pos=1
  local function take(n)
    if n<0 or pos+n-1>#data then fail('Pacote DDZ incompleto.') end
    local value=data:sub(pos,pos+n-1); pos=pos+n; return value
  end
  local function number()
    local result,mult=0,1
    for _=1,5 do
      local b=take(1):byte(); result=result+(b%128)*mult
      if b<128 then return result end
      mult=mult*128
    end
    fail('Numero DDZ invalido.')
  end
  return take,number,function() return pos end
end
function M.archivePack(source,guard)
  guard=guard or function() end
  guard()
  if fs.isDriveRoot(source) then fail('Selecione um arquivo ou pasta dentro da unidade.') end
  local name=fs.getName(source)
  if not M.safeName(name) then fail('Nome invalido para o pacote.') end
  local entries,total
  if fs.isDir(source) then
    entries,total=inventory(source,guard,true)
    for _,entry in ipairs(entries) do entry.path=name..'/'..entry.path end
    table.insert(entries,1,{path=name,dir=true})
  else entries={{path=name,dir=false}}; total=fs.getSize(source) end
  if total>archiveLimit or #entries>1024 then fail('Limite DDZ: 512 KiB originais e 1024 itens.') end
  local blocks,actualTotal,parents={varint(#entries)},0,{['']=0}
  for i,entry in ipairs(entries) do
    guard()
    if not safeRelative(entry.path) then fail('Caminho muito longo ou invalido para DDZ.') end
    local parent=parents[fs.getDir(entry.path)]
    if not parent then fail('Pasta pai ausente.') end
    local basename=fs.getName(entry.path)
    blocks[#blocks+1]=varint(parent)..varint(#basename)..basename..string.char(entry.dir and 0 or 1)
    if entry.dir then parents[entry.path]=i end
    if not entry.dir then
      local path=fs.combine(fs.getDir(source),entry.path)
      local raw=readBounded(path,archiveLimit-actualTotal)
      actualTotal=actualTotal+#raw
      blocks[#blocks+1]=varint(#raw)..raw
    end
  end
  local body=table.concat(blocks)
  if #body-actualTotal>128*1024 then fail('Indice DDZ muito grande.') end
  local packed=lzwEncode(body)
  local useLzw=#packed<#body
  local hash=M.checksum(body)
  local hashBytes={}; for _=1,4 do hashBytes[#hashBytes+1]=string.char(hash%256); hash=math.floor(hash/256) end
  return 'DDZ2'..string.char(useLzw and 1 or 0)..varint(#body)..table.concat(hashBytes)..(useLzw and packed or body),actualTotal
end
function M.compress(source,target,guard)
  guard=guard or function() end
  guard(); M.assertWritable(target)
  if fs.exists(target) or fs.exists(target..'.partial') then fail('Destino ja existe.') end
  if target==source or target:sub(1,#source+1)==source..'/' then fail('Salve o pacote fora da pasta de origem.') end
  local payload,actualTotal=M.archivePack(source,guard)
  guard(); room(fs.getDir(target),#payload+1024)
  writeVerified(target..'.partial',payload,guard)
  guard(); fs.move(target..'.partial',target)
  return actualTotal,#payload
end
function M.archiveExtract(data,target,guard)
  guard=guard or function() end
  guard(); M.assertWritable(target)
  if fs.exists(target) or fs.exists(target..'.partial') then fail('Escolha uma pasta nova para extrair.') end
  if #data>archiveLimit+128*1024+32 then fail('Pacote DDZ muito grande.') end
  local manifest,position
  if data:sub(1,4)=='DDZ2' then
    local take,num,pos=numberReader(data:sub(5))
    local codec=take(1):byte(); local length=num(); local hash=0
    for i=0,3 do hash=hash+take(1):byte()*256^i end
    if length>archiveLimit+128*1024 then fail('DDZ excede limite.') end
    local body=data:sub(4+pos())
    if codec==1 then body=lzwDecode(body,length)
    elseif codec~=0 then fail('Codec DDZ desconhecido.') end
    if #body~=length or M.checksum(body)~=hash then fail('Pacote DDZ corrompido.') end
    take,num,pos=numberReader(body)
    local count=num(); if count>1024 then fail('Muitos itens DDZ.') end
    manifest={version=1,entries={}}; local blocks={}; local total=0
    for i=1,count do
      local parent=num(); local nameLength=num()
      if parent>=i or nameLength>128 then fail('Indice DDZ invalido.') end
      local name=take(nameLength); if not M.safeName(name) then fail('Nome DDZ invalido.') end
      local base=parent==0 and '' or manifest.entries[parent]
      if parent~=0 and (not base or not base.dir) then fail('Pasta DDZ invalida.') end
      local flag=take(1):byte(); if flag>1 then fail('Tipo DDZ invalido.') end
      local entry={path=parent==0 and name or fs.combine(base.path,name),dir=flag==0}
      if not entry.dir then
        local size=num(); total=total+size; if total>archiveLimit then fail('DDZ excede limite.') end
        local block=take(size); blocks[#blocks+1]=block
        entry.size,entry.packed,entry.hash,entry.codec=size,size,M.checksum(block),'raw'
      end
      manifest.entries[i]=entry
    end
    if pos()~=#body+1 then fail('Dados extras no pacote DDZ.') end
    data=table.concat(blocks); position=1
  else
    local length; length,position=data:match('^DDZ1\n(%d+)\n()'); length=tonumber(length)
    if not length or length>128*1024 or position+length-1>#data then fail('Cabecalho DDZ invalido.') end
    manifest=textutils.unserialize(data:sub(position,position+length-1)); position=position+length
  end
  if type(manifest)~='table' or manifest.version~=1 or type(manifest.entries)~='table' or #manifest.entries>1024 then fail('Indice DDZ invalido.') end
  local files,seen,total={},{},0
  for _,entry in ipairs(manifest.entries) do
    if type(entry)~='table' or not safeRelative(entry.path) or seen[entry.path] or type(entry.dir)~='boolean' then fail('Caminho DDZ invalido.') end
    seen[entry.path]=entry.dir and 'dir' or 'file'
    if not entry.dir then
      if type(entry.size)~='number' or entry.size<0 or entry.size%1~=0 or entry.size>archiveLimit-total or
        type(entry.packed)~='number' or entry.packed<0 or entry.packed%1~=0 or position+entry.packed-1>#data or
        type(entry.hash)~='number' then fail('Tamanho DDZ invalido.') end
      total=total+entry.size
      local block=data:sub(position,position+entry.packed-1); position=position+entry.packed
      if entry.codec=='lzw' then block=lzwDecode(block,entry.size)
      elseif entry.codec~='raw' then fail('Compactacao DDZ desconhecida.') end
      if #block~=entry.size or M.checksum(block)~=entry.hash then fail('Pacote DDZ corrompido.') end
      files[entry.path]=block
    end
  end
  if position~=#data+1 then fail('Dados extras no pacote DDZ.') end
  for path in pairs(seen) do
    local parent=fs.getDir(path)
    while parent~='' do
      if seen[parent]=='file' then fail('Conflito de pastas no pacote DDZ.') end
      parent=fs.getDir(parent)
    end
  end
  guard(); room(fs.getDir(target),total+(#manifest.entries+1)*1024)
  local stage=target..'.partial'; fs.makeDir(stage)
  for _,entry in ipairs(manifest.entries) do
    guard(); local dest=fs.combine(stage,entry.path)
    if entry.dir then fs.makeDir(dest) else
      fs.makeDir(fs.getDir(dest)); writeVerified(dest,files[entry.path],guard)
    end
  end
  guard(); fs.move(stage,target)
  return target
end
function M.extract(source,target,guard)
  return M.archiveExtract(readBounded(source,archiveLimit+128*1024+32),target,guard)
end
return M
]=]},
  {name=[=[
diskdesk_arrays.lua]=], contents=[=[
-- Immutable archive sets with striped blocks, rotating P/Q parity and paired mirrors.
-- Format is DiskDesk-specific, not a CraftOS filesystem mount or Linux RAID format.
return function(S,storageBase)
local A={}; local base=storageBase or '.diskdesk-arrays'; local block=1024; local limit=storageBase and 8*1024*1024 or 640*1024+32
local serial=0
local function fail(s) error(s,0) end
local function yield() if sleep then sleep(0) end end
local function slowXor(a,b)
  local value,p=0,1
  for _=1,8 do
    if a%2~=b%2 then value=value+p end
    a=math.floor(a/2); b=math.floor(b/2); p=p*2
  end
  return value
end
local nibble={}
for a=0,15 do nibble[a]={}; for b=0,15 do nibble[a][b]=slowXor(a,b) end end
local function xor(a,b) return nibble[a%16][b%16]+16*nibble[math.floor(a/16)][math.floor(b/16)] end
-- Multiplication in GF(256), polynomial x^8+x^4+x^3+x^2+1 (0x11d).
local exp,log={},{}; local v=1
for i=0,254 do
  exp[i]=v; log[v]=i; v=v*2
  if v>=256 then v=xor(v-256,29) end
end
local function mul(a,b) if a==0 or b==0 then return 0 end; return exp[(log[a]+log[b])%255] end
local function div(a,b) if b==0 then fail('Divisor RAID invalido.') end; if a==0 then return 0 end; return exp[(log[a]-log[b])%255] end
local function integer(n,low,high) return type(n)=='number' and n%1==0 and n>=low and n<=high end
local function dataCount(mode,n)
  if not integer(n,2,8) then fail('Escolha de 2 a 8 discos.') end
  if mode=='0' then return n end
  if mode=='1' then return 1 end
  if mode=='5' and n>=3 then return n-1 end
  if mode=='6' and n>=4 then return n-2 end
  if mode=='10' and n>=4 and n%2==0 then return n/2 end
  fail('Numero de discos invalido para RAID '..tostring(mode)..'.')
end
function A.plan(size,mode,n)
  local k=dataCount(mode,n)
  if not integer(size,1,limit) then fail('Pacote RAID excede 640 KiB.') end
  return math.ceil(size/(k*block))*block,k
end
local function layout(mode,n,stripe)
  local slots,p,q={},nil,nil
  if mode=='1' then return {1} end
  if mode=='10' then for i=1,n,2 do slots[#slots+1]=i end; return slots end
  if mode=='5' or mode=='6' then
    p=n-(stripe%n)
    if mode=='6' then q=p%n+1 end
  end
  for i=1,n do if i~=p and i~=q then slots[#slots+1]=i end end
  return slots,p,q
end
local function parity(data)
  local p,q={},{}
  for b=1,block do
    local pv,qv=0,0
    for j,s in ipairs(data) do local x=s:byte(b); pv=xor(pv,x); qv=xor(qv,mul(x,exp[j-1])) end
    p[b]=string.char(pv); q[b]=string.char(qv)
  end
  return table.concat(p),table.concat(q)
end
local function encode(payload,mode,n,progress)
  local size,k=A.plan(#payload,mode,n); local parts={}
  for i=1,n do parts[i]={} end
  local pos=1
  for stripe=0,size/block-1 do
    local slots,p,q=layout(mode,n,stripe); local data={}
    for j,slot in ipairs(slots) do
      local s=payload:sub(pos,pos+block-1); pos=pos+block
      s=s..string.rep('\0',block-#s); data[j]=s; parts[slot][#parts[slot]+1]=s
      if mode=='10' then parts[slot+1][#parts[slot+1]+1]=s end
    end
    if mode=='1' then for i=2,n do parts[i][#parts[i]+1]=data[1] end end
    if p then
      local pv,qv=parity(data); parts[p][#parts[p]+1]=pv
      if q then parts[q][#parts[q]+1]=qv end
    end
    if progress then progress(stripe+1,size/block,'Calculando blocos RAID '..mode) end
    yield()
  end
  for i=1,n do parts[i]=table.concat(parts[i]) end
  return parts,size
end
local function read(path,max)
  if not fs.exists(path) or fs.isDir(path) or fs.getSize(path)>max then fail('Arquivo RAID ausente ou invalido.') end
  local f,err=fs.open(path,'rb'); if not f then fail(err) end
  local ok,data=pcall(f.readAll); f.close(); if not ok then fail(data) end
  if #data>max then fail('Arquivo RAID cresceu durante leitura.') end
  return data
end
local function write(path,data,guard)
  guard(); local f,err=fs.open(path,'wb'); if not f then fail(err) end
  local ok,why=pcall(f.write,data); f.close(); if not ok then fail(why) end
  guard(); if read(path,#data)~=data then fail('Falha de verificacao RAID.') end
end
local function room(volume,bytes)
  S.guard(volume); S.assertWritable(volume.root)
  if fs.isReadOnly(volume.root) then fail('Disco somente leitura.') end
  local free=fs.getFreeSpace(volume.root)
  if type(free)=='number' and free<bytes then fail('Espaco insuficiente no disco #'..volume.id..'.') end
end
local function valid(m)
  if type(m)~='table' or m.version~=1 or type(m.id)~='string' or not m.id:match('^[%w%-]+$') or #m.id>80 or
    not S.safeName(m.name) or not integer(m.n,2,8) or not integer(m.size,1,limit) or
    not integer(m.hash,0,4294967295) or type(m.hashes)~='table' or #m.hashes~=m.n or m.block~=block then fail('Indice RAID invalido.') end
  local expected=A.plan(m.size,m.mode,m.n)
  if m.shardSize~=expected then fail('Tamanho dos blocos RAID invalido.') end
  for i=1,m.n do if not integer(m.hashes[i],0,4294967295) then fail('Checksum RAID invalido.') end end
  return m
end
local function root(volume,id) return fs.combine(volume.root,base..'/'..id) end
local function devices()
  local result={}
  for _,name in ipairs(peripheral.getNames()) do
    if peripheral.hasType(name,'drive') and disk.getMountPath(name) then result[#result+1]=S.capture(name) end
  end
  table.sort(result,function(a,b) return a.id<b.id end)
  return result
end
function A.list()
  local found={}
  for _,volume in ipairs(devices()) do
    local dir=fs.combine(volume.root,base)
    if fs.exists(dir) and fs.isDir(dir) then
      for _,id in ipairs(fs.list(dir)) do
        local ok,m=pcall(function()
          S.guard(volume)
          local candidate=valid(textutils.unserialize(read(fs.combine(dir,id..'/manifest'),16384)))
          local slot,diskID=read(fs.combine(dir,id..'/member'),64):match('^(%d+):(%d+)$')
          if candidate.id~=id or not integer(tonumber(slot),1,candidate.n) or tonumber(diskID)~=volume.id then fail('Membro incorreto.') end
          return candidate
        end)
        if ok then found[id]=m elseif tostring(m)=='Terminated' then fail(m) end
      end
    end
  end
  local list={}; for _,m in pairs(found) do list[#list+1]=m end
  table.sort(list,function(a,b) return a.id<b.id end); return list
end
local function same(a,b)
  for _,k in ipairs({'version','id','name','mode','n','size','hash','block','shardSize'}) do if a[k]~=b[k] then return false end end
  for i=1,a.n do if a.hashes[i]~=b.hashes[i] then return false end end
  return true
end
local function gather(m)
  valid(m); local shards,volumes,occupied={},{},{}
  for _,volume in ipairs(devices()) do
    local dir=root(volume,m.id)
    if fs.exists(dir) then
      occupied[volume.id]=true
      local ok,slot,data=pcall(function()
        S.guard(volume)
        local info=valid(textutils.unserialize(read(dir..'/manifest',16384)))
        if not same(m,info) then fail('Indice de outro conjunto.') end
        local index,id=read(dir..'/member',64):match('^(%d+):(%d+)$'); index=tonumber(index)
        if not integer(index,1,m.n) or tonumber(id)~=volume.id then fail('Membro incorreto.') end
        local content=read(dir..'/shard',m.shardSize); S.guard(volume)
        if #content~=m.shardSize or S.checksum(content)~=m.hashes[index] then fail('Bloco RAID corrompido.') end
        return index,content
      end)
      if ok then
        if shards[slot] and shards[slot]~=data then fail('Membros conflitantes.') end
        shards[slot]=data; volumes[slot]=volume
      elseif tostring(slot)=='Terminated' then fail(slot) end
    end
  end
  return shards,volumes,occupied
end
local function recoverable(m,shards)
  local missing=0; for i=1,m.n do if not shards[i] then missing=missing+1 end end
  if m.mode=='0' then return missing==0 end
  if m.mode=='1' then return missing<m.n end
  if m.mode=='5' then return missing<=1 end
  if m.mode=='6' then return missing<=2 end
  for i=1,m.n,2 do if not shards[i] and not shards[i+1] then return false end end
  return true
end
function A.status(m)
  local shards,volumes,occupied=gather(m); local missing={}
  for i=1,m.n do if not shards[i] then missing[#missing+1]=i end end
  return {missing=missing,volumes=volumes,occupied=occupied,readable=recoverable(m,shards),
    text=#missing==0 and 'Integro' or (recoverable(m,shards) and 'Degradado / recuperavel' or 'Discos insuficientes')}
end
local function decode(m,shards,progress)
  if not recoverable(m,shards) then fail('Perdas excedem a redundancia. Reconecte os discos originais.') end
  local out={}
  for stripe=0,m.shardSize/block-1 do
    local slots,p,q=layout(m.mode,m.n,stripe); local data,missing={},{}
    local function slice(slot)
      return shards[slot] and shards[slot]:sub(stripe*block+1,(stripe+1)*block)
    end
    for j,slot in ipairs(slots) do
      data[j]=slice(slot)
      if m.mode=='10' then data[j]=data[j] or slice(slot+1) end
      if m.mode=='1' and not data[j] then for i=2,m.n do data[j]=data[j] or slice(i) end end
      if not data[j] then missing[#missing+1]=j end
    end
    if #missing>0 then
      local pb,qb=p and slice(p),q and slice(q); local recovered={}
      for _,j in ipairs(missing) do recovered[j]={} end
      for b=1,block do
        local pp,qq=pb and pb:byte(b) or 0,qb and qb:byte(b) or 0
        for j=1,#slots do
          if data[j] then local value=data[j]:byte(b); pp=xor(pp,value); qq=xor(qq,mul(value,exp[j-1])) end
        end
        local x=missing[1]
        if #missing==1 then recovered[x][b]=string.char(pb and pp or div(qq,exp[x-1]))
        else
          local y=missing[2]
          local xv=div(xor(qq,mul(exp[y-1],pp)),xor(exp[x-1],exp[y-1]))
          recovered[x][b]=string.char(xv); recovered[y][b]=string.char(xor(pp,xv))
        end
      end
      for _,j in ipairs(missing) do data[j]=table.concat(recovered[j]) end
    end
    for j=1,#slots do out[#out+1]=data[j] end
    if progress then progress(stripe+1,m.shardSize/block,'Lendo RAID '..m.mode) end
    yield()
  end
  local payload=table.concat(out):sub(1,m.size)
  if #payload~=m.size or S.checksum(payload)~=m.hash then fail('Conteudo RAID nao passou na verificacao.') end
  return payload
end
function A.create(payload,name,mode,volumes,progress)
  if not S.safeName(name) then fail('Nome de conjunto invalido.') end
  local shardSize=A.plan(#payload,mode,#volumes); local seen={}
  for _,volume in ipairs(volumes) do
    if seen[volume.id] then fail('Selecione discos diferentes.') end; seen[volume.id]=true
    room(volume,shardSize+8192)
  end
  serial=serial+1
  local id=tostring(os.getComputerID())..'-'..tostring(os.epoch('utc'))..'-'..serial
  for _,volume in ipairs(volumes) do
    if fs.exists(root(volume,id)) or fs.exists(root(volume,id)..'.partial') then fail('Identificador RAID ja existe. Tente novamente.') end
  end
  local shards=encode(payload,mode,#volumes,progress)
  local m={version=1,id=id,name=name,mode=mode,n=#volumes,size=#payload,hash=S.checksum(payload),block=block,shardSize=shardSize,hashes={}}
  for i,s in ipairs(shards) do m.hashes[i]=S.checksum(s) end
  local manifest=textutils.serialize(m)
  local function guard() for _,volume in ipairs(volumes) do S.guard(volume) end end
  -- Stage every member before making any discoverable. Each set is immutable.
  for i,volume in ipairs(volumes) do
    guard(); room(volume,shardSize+#manifest+4096)
    local stage=root(volume,id)..'.partial'; fs.makeDir(stage)
    write(stage..'/shard',shards[i],guard)
    write(stage..'/manifest',manifest,guard)
    write(stage..'/member',i..':'..volume.id,guard)
    if progress then progress(i,#volumes,'Verificado disco #'..volume.id) end
  end
  for _,volume in ipairs(volumes) do guard(); fs.move(root(volume,id)..'.partial',root(volume,id)) end
  return m
end
function A.restore(m,target,guard,progress)
  local shards,volumes=gather(m)
  local function check()
    if guard then guard() end
    for _,volume in pairs(volumes) do S.guard(volume) end
  end
  check(); local payload=decode(m,shards,progress); check()
  return S.archiveExtract(payload,target,check)
end
function A.rebuild(m,slot,dest,progress)
  if not integer(slot,1,m.n) then fail('Posicao RAID invalida.') end
  local shards,volumes,occupied=gather(m)
  if shards[slot] then fail('Membro ja esta integro.') end
  if occupied[dest.id] then fail('Escolha outro disquete sem este conjunto.') end
  room(dest,m.shardSize+8192)
  local function guard()
    S.guard(dest); for _,volume in pairs(volumes) do S.guard(volume) end
  end
  local path=root(dest,m.id)
  if fs.exists(path) or fs.exists(path..'.partial') then fail('Destino ja contem este conjunto ou uma tentativa parcial.') end
  guard(); local payload=decode(m,shards,progress)
  local rebuilt=encode(payload,m.mode,m.n,progress)
  if S.checksum(rebuilt[slot])~=m.hashes[slot] then fail('Reconstrucao nao confere.') end
  guard(); local stage=path..'.partial'; fs.makeDir(stage)
  write(stage..'/shard',rebuilt[slot],guard)
  write(stage..'/manifest',textutils.serialize(m),guard)
  write(stage..'/member',slot..':'..dest.id,guard)
  guard(); fs.move(stage,path)
  return dest
end
function A.readData(m,progress)
  local shards,volumes=gather(m)
  local payload=decode(m,shards,progress)
  for _,volume in pairs(volumes) do S.guard(volume) end
  return payload
end
function A.removeData(m,volumes)
  valid(m)
  for _,volume in ipairs(volumes) do
    S.guard(volume)
    local path=root(volume,m.id)
    if fs.exists(path) then fs.delete(path) end
    if fs.exists(path..'.partial') then fs.delete(path..'.partial') end
  end
end
return A
end
]=]},
  {name=[=[
diskdesk_volumes.lua]=], contents=[=[
-- DiskDesk-only virtual filesystem. Catalog commits precede reclamation of old blocks.
-- Every file is an immutable raw striped object; replacing it publishes a new object.
return function(S,arrayFactory)
local P=fs
local A=arrayFactory(S,'.diskdesk-vdata')
local V={}; local F={}; local registry={}
local configRoot='.diskdesk-volumes'; local prefix='__diskdesk_raid__'
local serial=0; local notice
local maxFile=8*1024*1024-1
for k,v in pairs(P) do F[k]=v end
local function fail(s) error(s,0) end
local function clone(t)
  if type(t)~='table' then return t end
  local result={}; for k,v in pairs(t) do result[k]=clone(v) end; return result
end
local function norm(path)
  local parts={}
  for part in tostring(path):gmatch('[^/]+') do
    if part=='..' then table.remove(parts) elseif part~='.' and part~='' then parts[#parts+1]=part end
  end
  return table.concat(parts,'/')
end
local function relative(path)
  if type(path)~='string' or #path>512 or norm(path)~=path then return false end
  if path=='' then return true end
  for part in path:gmatch('[^/]+') do if not S.safeName(part) then return false end end
  return true
end
local function location(path)
  path=norm(path)
  if path==prefix then return nil,'',true end
  local id,rest=path:match('^'..prefix..'/([^/]+)(.*)$')
  if not id then return nil,nil,false end
  return registry[id],rest:gsub('^/',''),true
end
function V.isVirtual(path) local _,_,v=location(path); return v end
function V.root(volume) return prefix..'/'..volume.id end
local function number(n,min,max) return type(n)=='number' and n%1==0 and n>=min and n<=max end
local function valid(c)
  if type(c)~='table' or c.version~=1 or type(c.id)~='string' or not c.id:match('^[%w%-]+$') or #c.id>80 or
    not S.safeName(c.name) or not number(c.seq,1,1e12) or type(c.members)~='table' or
    not number(c.capacity,1,1e12) or type(c.entries)~='table' then fail('Catalogo da unidade RAID invalido.') end
  A.plan(1,c.mode,#c.members)
  local ids={}
  for _,id in ipairs(c.members) do
    if not number(id,0,1e12) or ids[id] then fail('Discos do catalogo invalidos.') end
    ids[id]=true
  end
  local count=0
  for path,e in pairs(c.entries) do
    count=count+1
    if count>1024 or not relative(path) or type(e)~='table' or type(e.dir)~='boolean' then fail('Indice da unidade RAID invalido.') end
    if path~='' and (not c.entries[P.getDir(path)] or not c.entries[P.getDir(path)].dir) then fail('Pasta pai RAID ausente.') end
    if not e.dir then
      if not number(e.size,0,maxFile) or type(e.object)~='table' or e.object.mode~=c.mode or
        e.object.n~=#c.members or e.object.size~=e.size+1 then fail('Objeto da unidade RAID invalido.') end
      local m=e.object
      if type(m.id)~='string' or not m.id:match('^[%w%-]+$') or #m.id>80 then fail('Identificador de objeto invalido.') end
    end
  end
  if not c.entries[''] or not c.entries[''].dir then fail('Raiz RAID ausente.') end
  return c
end
local function read(path,limit)
  if P.getSize(path)>limit then fail('Indice ou arquivo muito grande.') end
  local f,err=P.open(path,'rb'); if not f then fail(err) end
  local ok,data=pcall(f.readAll); f.close(); if not ok then fail(data) end
  if #data>limit then fail('Arquivo cresceu durante leitura.') end
  return data
end
local function checked(path,data)
  local f,err=P.open(path,'wb'); if not f then fail(err) end
  local ok,why=pcall(f.write,data); f.close(); if not ok then fail(why) end
  if read(path,#data)~=data then fail('Gravacao do catalogo RAID nao confere.') end
end
local function encode(c)
  valid(c)
  local body=textutils.serialize(c)
  if #body>1024*1024 then fail('Catalogo RAID excede 1 MiB.') end
  return 'DDV1\n'..S.checksum(body)..'\n'..body
end
local function decode(data)
  local hash,pos=data:match('^DDV1\n(%d+)\n()')
  if not hash or S.checksum(data:sub(pos))~=tonumber(hash) then fail('Catalogo RAID corrompido.') end
  return valid(textutils.unserialize(data:sub(pos)))
end
local function catalogPath(id) return configRoot..'/'..id..'/catalog' end
local function replace(path,data,guard)
  guard=guard or function() end
  guard(); P.makeDir(P.getDir(path))
  -- A valid current catalog supersedes an old recovery copy.
  if P.exists(path..'.previous') then
    if not P.exists(path) then P.move(path..'.previous',path) else P.delete(path..'.previous') end
  end
  if P.exists(path..'.next') then P.delete(path..'.next') end
  checked(path..'.next',data); guard()
  if P.exists(path) then P.move(path,path..'.previous') end
  local ok,why=pcall(P.move,path..'.next',path)
  if not ok then
    if not P.exists(path) and P.exists(path..'.previous') then P.move(path..'.previous',path) end
    fail(why)
  end
  -- After this rename the current catalog is committed, even if cleanup fails.
  if P.exists(path..'.previous') then pcall(P.delete,path..'.previous') end
end
local function devices()
  local found={}
  for _,name in ipairs(peripheral.getNames()) do
    if peripheral.hasType(name,'drive') and disk.getMountPath(name) then
      local unit=S.capture(name); found[unit.id]=unit
    end
  end
  return found
end
local function members(c,requireAll)
  local found=devices(); local result={}; local missing={}
  for i,id in ipairs(c.members) do
    result[i]=found[id] or false
    if not result[i] then missing[#missing+1]=i end
  end
  if requireAll and #missing>0 then fail('Unidade RAID degradada: reconecte ou reconstrua os membros para gravar.') end
  return result,missing
end
local function readable(c,missing)
  if c.mode=='0' then return #missing==0 end
  if c.mode=='1' then return #missing<#c.members end
  if c.mode=='5' then return #missing<=1 end
  if c.mode=='6' then return #missing<=2 end
  local lost={}; for _,slot in ipairs(missing) do lost[slot]=true end
  for i=1,#c.members,2 do if lost[i] and lost[i+1] then return false end end
  return true
end
function V.info(volume)
  local c=registry[volume.id] or volume
  local units,missing=members(c,false); local used=0; local free
  local _,k=A.plan(1,c.mode,#c.members)
  for _,unit in ipairs(units) do
    if unit then local f=P.getFreeSpace(unit.root); if type(f)=='number' then free=math.min(free or f,f) end end
  end
  for _,e in pairs(c.entries) do if not e.dir then used=used+e.size end end
  local available=math.max(0,math.min(c.capacity-used,math.max(0,(free or 0)-8192)*k))
  local canRead=readable(c,missing)
  return {missing=missing,members=units,readable=canRead,writable=#missing==0,capacity=c.capacity,free=available,used=used,
    text=#missing==0 and 'Ativo' or (canRead and 'Degradado' or 'Indisponivel')}
end
function V.guard(path)
  local c,_,virtual=location(path)
  if virtual and (not c or not V.info(c).readable) then fail('Unidade RAID indisponivel.') end
end
local function writeGuard(c,allowDegraded)
  local units,missing=members(c,not allowDegraded)
  if allowDegraded and not readable(c,missing) then fail('Membros insuficientes para publicar a reconstrucao.') end
  local function guard()
    for _,unit in ipairs(units) do
      if unit then
        S.guard(unit); S.assertWritable(unit.root)
        if P.isReadOnly(unit.root) then fail('Membro RAID somente leitura.') end
      end
    end
  end
  guard(); return units,guard
end
local function backupCatalog(c,units,data)
  for _,unit in ipairs(units) do
    if unit then
      local path=P.combine(unit.root,'.diskdesk-vdata/volume-'..c.id..'/catalog')
      replace(path,data,function() S.guard(unit) end)
    end
  end
end
local function commit(c,old,allowDegraded)
  local units,guard=writeGuard(c,allowDegraded)
  local data=encode(c)
  guard(); replace(catalogPath(c.id),data,guard)
  registry[c.id]=c
  -- Local catalog is authoritative. A failed redundant catalog write must not roll it back.
  local ok,why=pcall(backupCatalog,c,units,data)
  if not ok then
    if tostring(why)=='Terminated' then fail(why) end
    notice='Dados salvos; copia do catalogo pendente. Use Verificar unidade.'
    return
  end
  if old then
    local live={}; for _,e in pairs(c.entries) do if e.object then live[e.object.id]=true end end
    for _,e in pairs(old.entries) do
      if e.object and not live[e.object.id] then
        local cleaned,err=pcall(A.removeData,e.object,units)
        if not cleaned then
          if tostring(err)=='Terminated' then fail(err) end
          notice='Dados salvos; sobraram blocos antigos nos discos.'
        end
      end
    end
  end
end
function V.list()
  local out={}; for _,c in pairs(registry) do out[#out+1]=c end
  table.sort(out,function(a,b) return a.id<b.id end); return out
end
function V.notice() local text=notice; notice=nil; return text end
function V.create(name,mode,units)
  if P.exists(prefix) then fail('Nome reservado ocupado no computador: '..prefix) end
  if not S.safeName(name) then fail('Nome da unidade invalido.') end
  local _,k=A.plan(1,mode,#units); local ids,seen,minCapacity={},{},nil
  for _,unit in ipairs(units) do
    S.guard(unit); S.assertWritable(unit.root)
    local auto=S.raidStatus()
    if auto.enabled then
      if auto.primaryID==unit.id then fail('Desative o espelhamento antigo antes de usar seu disco principal numa unidade virtual.') end
      for _,id in ipairs(auto.mirrorIDs or {}) do if id==unit.id then fail('Disco ja usado pelo espelhamento automatico.') end end
    end
    if seen[unit.id] then fail('Selecione discos diferentes.') end; seen[unit.id]=true
    for _,c in pairs(registry) do for _,id in ipairs(c.members) do if id==unit.id then fail('Disco #'..id..' ja pertence a outra unidade virtual.') end end end
    local capacity=P.getCapacity(unit.root)
    if type(capacity)~='number' or capacity<=8192 then fail('Capacidade do disco indisponivel ou muito pequena.') end
    minCapacity=math.min(minCapacity or capacity,capacity); ids[#ids+1]=unit.id
  end
  serial=serial+1
  local id=tostring(os.getComputerID())..'-'..tostring(os.epoch('utc'))..'-v'..serial
  if registry[id] or P.exists(configRoot..'/'..id) then fail('Identificador ocupado; tente novamente.') end
  local c={version=1,id=id,name=name,mode=mode,members=ids,capacity=k*(minCapacity-8192),seq=1,entries={['']={dir=true}}}
  commit(c); return c
end
local function need(path)
  local c,rel,virtual=location(path)
  if not virtual or not c then fail('Unidade virtual nao encontrada.') end
  if not relative(rel) then fail('Caminho RAID invalido ou muito longo.') end
  return c,rel
end
local function rawProtected(path)
  path='/'..norm(path)..'/'
  return path:find('/.diskdesk-vdata/',1,true) or path:find('/.diskdesk-volumes/',1,true)
end
local function rawWritable(path) if rawProtected(path) then fail('Arquivos internos da unidade RAID sao protegidos.') end end
function F.exists(path)
  local c,rel,v=location(path)
  if v then return norm(path)==prefix or (c~=nil and c.entries[rel]~=nil) end
  return P.exists(path)
end
function F.isDir(path)
  local c,rel,v=location(path)
  if v then return norm(path)==prefix or (c~=nil and c.entries[rel]~=nil and c.entries[rel].dir) end
  return P.isDir(path)
end
function F.isDriveRoot(path)
  local c,rel,v=location(path)
  if v then return c~=nil and rel=='' end
  return P.isDriveRoot(path)
end
function F.isReadOnly(path)
  local c,_,v=location(path)
  if v then return not c or not V.info(c).writable end
  return rawProtected(path) and true or P.isReadOnly(path)
end
function F.getCapacity(path)
  local c,_,v=location(path); if v then return c and c.capacity or 0 end
  return P.getCapacity(path)
end
function F.getFreeSpace(path)
  local c,_,v=location(path); if v then return c and V.info(c).free or 0 end
  return P.getFreeSpace(path)
end
function F.getSize(path)
  local c,rel,v=location(path)
  if v then if not c or not c.entries[rel] then fail('Arquivo nao encontrado.') end; return c.entries[rel].size or 0 end
  return P.getSize(path)
end
function F.list(path)
  if norm(path)==prefix then local ids={}; for id in pairs(registry) do ids[#ids+1]=id end; table.sort(ids); return ids end
  local c,rel,v=location(path)
  if not v then return P.list(path) end
  if not c or not c.entries[rel] or not c.entries[rel].dir then fail('Pasta RAID nao encontrada.') end
  local out={}
  for key in pairs(c.entries) do if key~=rel and P.getDir(key)==rel then out[#out+1]=P.getName(key) end end
  table.sort(out); return out
end
function F.makeDir(path)
  if not V.isVirtual(path) then rawWritable(path); return P.makeDir(path) end
  local c,rel=need(path); writeGuard(c)
  if c.entries[rel] then if not c.entries[rel].dir then fail('Ja existe um arquivo nesse caminho.') end; return end
  local next=clone(c); next.seq=c.seq+1
  local part=''
  for name in rel:gmatch('[^/]+') do
    part=P.combine(part,name)
    if next.entries[part] and not next.entries[part].dir then fail('Arquivo no caminho da pasta.') end
    next.entries[part]={dir=true}
  end
  commit(next,c)
end
local function contents(path)
  local c,rel=need(path); V.guard(path)
  local entry=c.entries[rel]; if not entry or entry.dir then fail('Arquivo RAID nao encontrado.') end
  local payload=A.readData(entry.object)
  if #payload~=entry.size+1 or payload:sub(1,1)~='\0' then fail('Conteudo RAID invalido.') end
  return payload:sub(2)
end
local function save(path,data,expectedSeq)
  local c,rel=need(path); local units,guard=writeGuard(c)
  if expectedSeq and c.seq~=expectedSeq then fail('Unidade mudou durante a edicao. Reabra o arquivo.') end
  if #data>maxFile then fail('Arquivo excede limite de 8 MiB.') end
  if rel=='' or (c.entries[rel] and c.entries[rel].dir) then fail('Destino e uma pasta.') end
  local parent=c.entries[P.getDir(rel)]
  if not parent or not parent.dir then fail('Pasta de destino nao existe.') end
  local next=clone(c); next.seq=c.seq+1
  -- No compression: a normal file is striped immediately, with the selected redundancy.
  local object=A.create('\0'..data,P.getName(rel),c.mode,units)
  guard(); next.entries[rel]={dir=false,size=#data,object=object}
  commit(next,c)
end
function F.open(path,mode)
  if not V.isVirtual(path) then
    if mode and mode:sub(1,1)~='r' then rawWritable(path) end
    return P.open(path,mode)
  end
  local writing=mode=='w' or mode=='wb' or mode=='a' or mode=='ab'
  if not writing and mode~='r' and mode~='rb' then return nil,'Modo nao suportado na unidade RAID.' end
  local ok,c,rel=pcall(need,path); if not ok then return nil,c end
  local entry=c.entries[rel]
  if entry and entry.dir then return nil,'Destino e uma pasta.' end
  if not writing and not entry then return nil,'Arquivo nao encontrado.' end
  local data=''
  if not writing or (mode:sub(1,1)=='a' and entry) then
    local loaded,value=pcall(contents,path); if not loaded then return nil,value end; data=value
  end
  if writing then local ready,err=pcall(writeGuard,c); if not ready then return nil,err end end
  local closed,pos,dirty=false,1,writing and mode:sub(1,1)=='w'
  local expected=c.seq
  local function check() if closed then fail('Arquivo fechado.') end end
  if writing then
    return {write=function(value)
      check(); if type(value)=='number' and mode:sub(-1)=='b' then value=string.char(value) else value=tostring(value) end
      if #data+#value>maxFile then fail('Arquivo excede 8 MiB.') end
      data=data..value; dirty=true
    end,writeLine=function(value) check(); data=data..tostring(value)..'\n'; dirty=true end,
    flush=function() check(); if dirty then save(path,data,expected); expected=select(1,need(path)).seq; dirty=false end end,
    close=function() if not closed then if dirty then save(path,data,expected) end; closed=true end end}
  end
  return {read=function(n)
    check(); if pos>#data then return nil end
    if n==nil then local ch=data:sub(pos,pos); pos=pos+1; return mode=='rb' and ch:byte() or ch end
    local value=data:sub(pos,pos+n-1); pos=pos+#value; return value
  end,readAll=function() check(); local value=data:sub(pos); pos=#data+1; return value end,
  readLine=function(trailing)
    check(); if pos>#data then return nil end
    local ending=data:find('\n',pos,true); local value=data:sub(pos,ending and (trailing and ending or ending-1) or #data)
    pos=ending and ending+1 or #data+1; return value
  end,close=function() closed=true end}
end
function F.delete(path)
  if not V.isVirtual(path) then rawWritable(path); return P.delete(path) end
  local c,rel=need(path); if rel=='' then fail('Nao exclua a raiz da unidade RAID.') end
  if not c.entries[rel] then return end
  local next=clone(c); next.seq=c.seq+1
  for key in pairs(next.entries) do if key==rel or key:sub(1,#rel+1)==rel..'/' then next.entries[key]=nil end end
  commit(next,c)
end
function F.copy(source,target)
  if not V.isVirtual(source) and not V.isVirtual(target) then rawWritable(target); return P.copy(source,target) end
  if F.exists(target) then fail('Destino ja existe.') end
  source,target=norm(source),norm(target)
  if source==target or target:sub(1,#source+1)==source..'/' then fail('Destino dentro da propria origem.') end
  if F.isDir(source) then
    F.makeDir(target)
    for _,name in ipairs(F.list(source)) do F.copy(P.combine(source,name),P.combine(target,name)) end
  else
    local input,err=F.open(source,'rb'); if not input then fail(err) end
    local data=input.readAll(); input.close()
    local output,why=F.open(target,'wb'); if not output then fail(why) end
    output.write(data); output.close()
    local check=assert(F.open(target,'rb')); local saved=check.readAll(); check.close()
    if saved~=data then fail('Copia nao confere.') end
  end
end
function F.move(source,target)
  local c,from,vs=location(source); local d,to,vd=location(target)
  if not vs and not vd then rawWritable(source); rawWritable(target); return P.move(source,target) end
  if F.exists(target) then fail('Destino ja existe.') end
  if vs and vd and c and d and c.id==d.id then
    c,from=need(source); local targetVolume; targetVolume,to=need(target)
    if from=='' or to:sub(1,#from+1)==from..'/' then fail('Movimento invalido.') end
    if not c.entries[from] or not c.entries[P.getDir(to)] or not c.entries[P.getDir(to)].dir then fail('Origem ou pasta de destino ausente.') end
    local next=clone(c); next.seq=c.seq+1
    for key,e in pairs(c.entries) do
      if key==from or key:sub(1,#from+1)==from..'/' then next.entries[key]=nil; next.entries[to..key:sub(#from+1)]=e end
    end
    commit(next,c)
  else F.copy(source,target); F.delete(source) end
end
function V.verify(volume)
  local c=registry[volume.id]; if not c then fail('Unidade nao encontrada.') end
  local result={}; local good=true
  for path,e in pairs(c.entries) do
    if e.object then
      local state=A.status(e.object); if #state.missing>0 then good=false end
      result[#result+1]=path..': '..state.text
    end
  end
  local state=V.info(c)
  if state.writable then
    local units=members(c,true); backupCatalog(c,units,encode(c))
  end
  return result,good and state.text or 'Verifique os arquivos listados'
end
function V.rebuild(volume,slot,dest,progress)
  local c=registry[volume.id]; if not c or not number(slot,1,#c.members) then fail('Posicao invalida.') end
  for _,other in pairs(registry) do for _,id in ipairs(other.members) do if id==dest.id then fail('Substituto ja pertence a uma unidade RAID.') end end end
  local state=V.info(c)
  if not state.readable then fail('Discos insuficientes para reconstruir.') end
  if state.members[slot] then fail('Retire o membro que sera substituido antes de reconstruir.') end
  local count,total=0,0
  for _,e in pairs(c.entries) do if e.object then total=total+1 end end
  for path,e in pairs(c.entries) do
    if e.object then
      local objectState=A.status(e.object)
      if not objectState.volumes[slot] or objectState.volumes[slot].id~=dest.id then A.rebuild(e.object,slot,dest) end
      count=count+1; if progress then progress(count,total,path) end
    end
  end
  local next=clone(c); next.seq=c.seq+1; next.members[slot]=dest.id
  commit(next,c,true); return next
end
function V.import()
  local candidates={}
  for _,unit in pairs(devices()) do
    local base=P.combine(unit.root,'.diskdesk-vdata')
    if P.exists(base) and P.isDir(base) then
      for _,name in ipairs(P.list(base)) do
        if name:match('^volume%-') then
          local path=P.combine(base,name..'/catalog')
          if not P.exists(path) and P.exists(path..'.previous') then path=path..'.previous' end
          local ok,c=pcall(function() return decode(read(path,1024*1024+64)) end)
          if ok and name=='volume-'..c.id and (not candidates[c.id] or c.seq>candidates[c.id].seq) then candidates[c.id]=c end
        end
      end
    end
  end
  local count=0
  for id,c in pairs(candidates) do
    if not registry[id] then
      -- Import only if every referenced file can be read with the available members.
      for _,e in pairs(c.entries) do if e.object then A.readData(e.object) end end
      replace(catalogPath(id),encode(c)); registry[id]=c; count=count+1
    end
  end
  return count
end
if P.exists(configRoot) then
  for _,id in ipairs(P.list(configRoot)) do
    local path=catalogPath(id)
    if not P.exists(path) and P.exists(path..'.previous') then P.move(path..'.previous',path) end
    if P.exists(path) then
      local ok,c=pcall(function() return decode(read(path,1024*1024+64)) end)
      if ok and c.id==id then registry[id]=c else notice='Catalogo RAID invalido: '..id..'. Preserve os discos e importe em outro computador.' end
    end
  end
end
V.fs=F
return V
end
]=]},
  {name=[=[
launcher]=], contents=[=[
-- DiskDesk launcher
shell.run("/diskdesk-app/diskdesk.lua", ...)
]=]},
}
local app, launcher = 'diskdesk-app', 'diskdesk.lua'
local function header(title)
  term.setBackgroundColor(colors.black); term.setTextColor(colors.white)
  term.clear(); term.setCursorPos(1, 1)
  term.setBackgroundColor(colors.blue); term.setTextColor(colors.white)
  print(' DiskDesk 3 - ' .. title)
  term.setBackgroundColor(colors.black); term.setTextColor(colors.white)
  print('')
end
local function ask(question)
  print(question .. ' [s/N]')
  write('> ')
  return read():lower() == 's'
end
local function checkedWrite(path, contents)
  local file, err = fs.open(path, 'w')
  if not file then error(err or ('Nao foi possivel criar ' .. path), 0) end
  local ok, why = pcall(file.write, contents)
  file.close()
  if not ok then error(why, 0) end
  local check = assert(fs.open(path, 'r'))
  local actual = check.readAll(); check.close()
  if actual ~= contents then error('Falha ao verificar ' .. path, 0) end
end
local function install()
  header('Instalacao')
  print('Explorador, backup, impressora e wireless.')
  print('Este instalador funciona sem internet.')
  print('')
  print('Programa: /' .. app .. '/')
  print('Atalho: /' .. launcher)
  print('Uma versao anterior sera guardada em backup.')
  print('Seus disquetes e startup nao serao alterados.')
  print('')
  if not ask('Instalar ou atualizar agora?') then print('Instalacao cancelada.'); return end
  if fs.exists('diskdesk') then
    error('Ja existe /diskdesk. Renomeie esse item antes de criar o atalho.', 0)
  end
  for _, target in ipairs({'', app, launcher}) do
    if fs.isReadOnly(target) then error('Local somente leitura: /' .. target, 0) end
    if target ~= '' and fs.exists(target) and fs.isDriveRoot(target) then
      error('O destino e uma unidade montada: /' .. target, 0)
    end
  end
  local bytes = 8192
  for _, item in ipairs(payload) do
    bytes = bytes + #item.contents
    local compiled, err = load(item.contents, '@' .. item.name, 't', {})
    if not compiled then error('Instalador danificado: ' .. tostring(err), 0) end
  end
  local free = fs.getFreeSpace('')
  if type(free) == 'number' and free < bytes then
    error('Espaco insuficiente. Necessario livre: ' .. bytes .. ' bytes.', 0)
  end
  local base = 'diskdesk-backup-' .. tostring(os.epoch('utc'))
  local staging, suffix = base, 1
  while fs.exists(staging) do suffix = suffix + 1; staging = base .. '-' .. suffix end
  fs.makeDir(staging .. '/new/app')
  fs.makeDir(staging .. '/previous')
  local oldApp, oldLauncher, newApp, newLauncher = false, false, false, false
  local ok, err = pcall(function()
    header('Copiando arquivos')
    for i, item in ipairs(payload) do
      local target = item.name == 'launcher' and (staging .. '/new/launcher') or (staging .. '/new/app/' .. item.name)
      checkedWrite(target, item.contents)
      print(' [' .. i .. '/' .. #payload .. '] ' .. item.name .. ' - OK')
    end
    if fs.exists(app) then fs.move(app, staging .. '/previous/app'); oldApp = true end
    if fs.exists(launcher) then fs.move(launcher, staging .. '/previous/diskdesk.lua'); oldLauncher = true end
    fs.move(staging .. '/new/app', app); newApp = true
    fs.move(staging .. '/new/launcher', launcher); newLauncher = true
  end)
  if not ok then
    -- Retain failed new files; move the old installation back when possible.
    local rollback, rollbackError = pcall(function()
      if newLauncher then fs.move(launcher, staging .. '/failed-launcher') end
      if newApp then fs.move(app, staging .. '/failed-app') end
      if oldApp then fs.move(staging .. '/previous/app', app) end
      if oldLauncher then fs.move(staging .. '/previous/diskdesk.lua', launcher) end
    end)
    print('Instalacao interrompida: ' .. tostring(err))
    if rollback then print('Arquivos anteriores preservados.')
    else print('Recuperacao manual necessaria: ' .. tostring(rollbackError)) end
    print('Arquivos de recuperacao: /' .. staging)
    return
  end
  header('Instalacao concluida')
  print('Para abrir de qualquer pasta, execute:')
  print('  /diskdesk')
  print('')
  if oldApp or oldLauncher then
    print('Versao anterior guardada em:')
    print('  /' .. staging .. '/previous')
  else
    -- Only empty staging directories remain after publication.
    pcall(fs.delete, staging)
  end
  print('')
  print('Backup: dois drives com disquetes.')
  print('Wireless: modem nos dois computadores.')
  print('Sons: conecte um Speaker.')
  print('')
  if ask('Abrir o DiskDesk agora?') then
    shell.run('/' .. app .. '/diskdesk.lua')
  end
end
local ok, err = pcall(install)
term.setBackgroundColor(colors.black); term.setTextColor(colors.white)
if not ok then print('Erro: ' .. tostring(err)) end
