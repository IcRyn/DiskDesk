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
