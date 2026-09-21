-- Instalador offline DiskDesk 3. Os arquivos do programa estao embutidos abaixo.
local payload = {
-- DISKDESK_PAYLOAD
}
local function unpackItem(item)
  local alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
  local map={}; for i=1,#alphabet do map[alphabet:sub(i,i)]=i-1 end
  local bytes,acc,bits={},0,0
  for char in item.contents:gmatch('.') do
    if char~='=' then
      acc=acc*64+assert(map[char],'Base64 invalido'); bits=bits+6
      if bits>=8 then bits=bits-8; bytes[#bytes+1]=string.char(math.floor(acc/2^bits)%256); acc=acc%2^bits end
    end
  end
  local data=table.concat(bytes); if #data%2~=0 then error('Pacote incompleto.',0) end
  local dict={}; for i=0,255 do dict[i]=string.char(i) end
  local nextCode,previous,out,size=256,nil,{},0
  for i=1,#data,2 do
    local code=data:byte(i)*256+data:byte(i+1); local entry=dict[code]
    if not entry and code==nextCode and previous then entry=previous..previous:sub(1,1) end
    if not entry then error('Pacote compactado invalido.',0) end
    size=size+#entry; if size>item.size then error('Pacote excede tamanho.',0) end
    out[#out+1]=entry
    if previous and nextCode<4096 then dict[nextCode]=previous..entry:sub(1,1); nextCode=nextCode+1 end
    previous=entry
  end
  item.contents=table.concat(out)
  if #item.contents~=item.size then error('Tamanho do pacote invalido.',0) end
  return item.contents
end
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
    local contents=unpackItem(item); bytes = bytes + #contents
    local compiled, err = load(contents, '@' .. item.name, 't', {})
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
