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
local function writeGuard(c)
  local units=members(c,true)
  local function guard()
    for _,unit in ipairs(units) do
      S.guard(unit); S.assertWritable(unit.root)
      if P.isReadOnly(unit.root) then fail('Membro RAID somente leitura.') end
    end
  end
  guard(); return units,guard
end
local function backupCatalog(c,units,data)
  for _,unit in ipairs(units) do
    local path=P.combine(unit.root,'.diskdesk-vdata/volume-'..c.id..'/catalog')
    replace(path,data,function() S.guard(unit) end)
  end
end
local function commit(c,old)
  local units,guard=writeGuard(c)
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
    c,from=need(source); _,to=need(target)
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
  commit(next,c); return next
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
