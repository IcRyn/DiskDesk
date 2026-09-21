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
  if not integer(n,2,16) then fail('Escolha de 2 a 16 discos.') end
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
    not S.safeName(m.name) or not integer(m.n,2,16) or not integer(m.size,1,limit) or
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
