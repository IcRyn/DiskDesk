-- Instalador offline DiskDesk 3. Os arquivos do programa estao embutidos abaixo.
local payload = {
  {name=[=[
diskdesk.lua]=], contents=[=[
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
    put(x + 1, y + 1, width, string.rep(' ', width), colors.gray)
    put(x, y, width, ' ' .. title, colors.blue, colors.white)
    for row = 1, rows do
      local i = offset + row
      put(x, y + row, width, (i == selectedOption and ' > ' or '   ') .. items[i],
        i == selectedOption and theme.select or theme.panel, theme.text)
      put(x + width, y + row, 1, ' ', colors.gray)
    end
    put(x, y + rows + 1, width, ' [Voltar] F1  |  Enter: escolher', theme.panel, theme.muted)
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
    line(H, (title == 'Backup' or title == 'Restaurar') and ' Mantenha os dois discos inseridos.' or ' F1: voltar | mantenha o modem conectado.', theme.panel)
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
local function raidMenu()
  while true do
    local state=services.raidStatus()
    local labels=state.enabled and {'Sincronizar agora','Ver estado do par','Desativar espelhamento'} or {'Configurar RAID 1','Como funciona'}
    local selectedAction=choose('RAID 1 / '..state.text,labels)
    if not selectedAction then return end
    if not state.enabled and selectedAction==1 then
      local selectedMode=choose('Modo de espelhamento',{'RAID 1: direto na raiz','RAID 1: pasta RAID1','RAID 1: varios espelhos (raiz)'})
      if not selectedMode then return end
      local primary=pickDisk('Escolha o disco PRINCIPAL')
      if not primary then return end
      local mirror=pickDisk('Escolha o disco ESPELHO',primary)
      if not mirror then return end
      local mirrors={mirror}; local used={[primary.id]=true,[mirror.id]=true}
      if selectedMode==3 then
        while #mirrors<8 do
          local available=false
          for _,unit in ipairs(sources) do if unit.drive and not used[disk.getID(unit.drive)] then available=true end end
          if not available or not confirm('Adicionar mais um disquete como espelho?') then break end
          local extra=pickDisk('Escolha outro ESPELHO',primary,used)
          if not extra then break end
          mirrors[#mirrors+1]=extra; used[extra.id]=true
        end
      end
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
    status='Pacote: '..sizeLabel(original)..' -> '..sizeLabel(packed)
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
    'Formato proprio do DiskDesk, nao e ZIP. Compressao LZW quando diminui o arquivo; senao conserva o bloco original.',
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
  file = {{'Abrir / visualizar', 'open'}, {'Novo texto', 't'}, {'Nova pasta', 'n'}, {'Editar texto', 'e'}, {'Imprimir', 'p'}},
  edit = {{'C  Copiar', 'c'}, {'M  Mover', 'm'}, {'V  Colar', 'v'}, {'R  Renomear', 'r'}, {'Delete  Excluir...', 'x'}, {'F  Buscar nesta pasta', 'f'}},
  disk = {{'Escolher unidade', 'd'}, {'Criar backup...', 'b'}, {'Restaurar backup...', 'o'}, {'Nome do disquete', 'l'}, {'Ejetar disquete', 'j'}},
  net = {{'Enviar arquivo...', 's'}, {'Receber arquivo...', 'g'}},
  protect = {{'Configurar / gerenciar RAID 1','i'}, {'Criar backup com versoes','b'}, {'Restaurar backup','o'}},
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
-- DDZ: bounded LZW or raw blocks, a readable manifest, and binary payloads.
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
function M.compress(source,target,guard)
  guard=guard or function() end
  guard(); M.assertWritable(target)
  if fs.isDriveRoot(source) then fail('Selecione um arquivo ou pasta dentro da unidade.') end
  if fs.exists(target) or fs.exists(target..'.partial') then fail('Destino ja existe.') end
  if target==source or target:sub(1,#source+1)==source..'/' then fail('Salve o pacote fora da pasta de origem.') end
  local name=fs.getName(source)
  if not M.safeName(name) then fail('Nome invalido para o pacote.') end
  local entries,total
  if fs.isDir(source) then
    entries,total=inventory(source,guard,true)
    for _,entry in ipairs(entries) do entry.path=name..'/'..entry.path end
    table.insert(entries,1,{path=name,dir=true})
  else entries={{path=name,dir=false}}; total=fs.getSize(source) end
  if total>archiveLimit or #entries>1024 then fail('Limite DDZ: 512 KiB originais e 1024 itens.') end
  local blocks,actualTotal={},0
  for _,entry in ipairs(entries) do
    guard()
    if not entry.dir then
      local path=fs.combine(fs.getDir(source),entry.path)
      local raw=readBounded(path,archiveLimit-actualTotal)
      actualTotal=actualTotal+#raw
      local compressed=lzwEncode(raw)
      entry.codec=#compressed<#raw and 'lzw' or 'raw'
      local data=entry.codec=='lzw' and compressed or raw
      entry.size,entry.hash,entry.packed=#raw,M.checksum(raw),#data
      blocks[#blocks+1]=data
    end
  end
  local header=textutils.serialize({version=1,entries=entries})
  if #header>128*1024 then fail('Indice DDZ muito grande.') end
  local payload='DDZ1\n'..#header..'\n'..header..table.concat(blocks)
  guard(); room(fs.getDir(target),#payload+1024)
  writeVerified(target..'.partial',payload,guard)
  guard(); fs.move(target..'.partial',target)
  return actualTotal,#payload
end
function M.extract(source,target,guard)
  guard=guard or function() end
  guard(); M.assertWritable(target)
  if fs.exists(target) or fs.exists(target..'.partial') then fail('Escolha uma pasta nova para extrair.') end
  local data=readBounded(source,archiveLimit+128*1024+32)
  local length,position=data:match('^DDZ1\n(%d+)\n()')
  length=tonumber(length)
  if not length or length>128*1024 or position+length-1>#data then fail('Cabecalho DDZ invalido.') end
  local manifest=textutils.unserialize(data:sub(position,position+length-1)); position=position+length
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
return M
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
