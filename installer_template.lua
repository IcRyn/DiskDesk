-- Instalador offline DiskDesk 3. Os arquivos do programa estao embutidos abaixo.
local payload = {
-- DISKDESK_PAYLOAD
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
