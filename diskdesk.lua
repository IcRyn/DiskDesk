-- DiskDesk para CC: Tweaked. Salve no computador como diskdesk.lua.
local wrap = require('cc.strings').wrap
local services = dofile(fs.combine(fs.getDir(shell.getRunningProgram()), 'diskdesk_services.lua'))
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
  line(2, ' '..current().name..' > /'..folder, theme.panel)
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
      put(2,y,sidebar-2,(item.drive and 'o ' or '# ')..item.name,
        i==source and theme.select or theme.panel)
      buttons[#buttons+1]={x=1,last=sidebar,y=y,action='source:'..i}
    end
    if H>=13 then
      put(2,H-5,sidebar-2,'RAID: '..raidLabel,theme.panel,theme.muted)
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
  line(H-1,(percent and (' USO '..percent..'%') or ' USO --')..' | Livre '..sizeLabel(free),theme.panel,theme.muted)
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
  -- execute preserves the path as one argument, including spaces in folders.
  if not shell.execute('/rom/programs/edit.lua', '/' .. file) then
    error('O editor falhou. Confira o disco e o espaco livre.', 0)
  end
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
        line(y,(i==choice and ' > ' or '   ')..unit.name..'  /'..unit.root,bg)
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
  if not ok then status='RAID pendente: '..tostring(result) end
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
      local primary=pickDisk('Escolha o disco PRINCIPAL')
      if not primary then return end
      local mirrors=selectDisks('Marque os ESPELHOS',1,selectedMode==3 and 8 or 1,{[primary.id]=true})
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
  local arrays=dofile(fs.combine(fs.getDir(shell.getRunningProgram()),'diskdesk_arrays.lua'))(services)
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
  protect = {{'Espelhamento automatico RAID 1','i'}, {'Conjuntos RAID 0 / 1 / 5 / 6 / 1+0','array'}, {'Criar backup com versoes','b'}, {'Restaurar backup','o'}},
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
