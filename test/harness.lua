-- Simulated CC world for testing miner.lua
local W = {}  -- world blocks: key -> name ; nil = default by rule
local function key(x,y,z) return x..","..y..","..z end
local dug = {}
local HOME = {x=-4461,y=20,z=1525}
local seed = 12345
local function rnd(x,y,z) local v = (x*73856093 ~ y*19349663 ~ z*83492791 ~ seed) % 1000; return v end
local special = {}
function getBlock(x,y,z)
  local k = key(x,y,z)
  if special[k] ~= nil then return special[k] or nil end
  if dug[k] then return nil end
  if y <= -60 then return "minecraft:bedrock" end
  if y > HOME.y then return nil end
  if y == HOME.y then
    -- surface level: air
    return nil
  end
  local v = rnd(x,y,z)
  if v < 30 then return "minecraft:coal" end
  if v < 40 then return "minecraft:raw_iron" end
  if v < 45 then return "minecraft:diamond" end
  if v < 60 then return "minecraft:gravel" end
  if v < 65 then return "minecraft:redstone" end
  return "minecraft:cobblestone"
end
T = {x=HOME.x,y=HOME.y,z=HOME.z,d=START_D or 3,fuel=START_FUEL or 3000,inv={},sel=1,moves=0}
for i=1,16 do T.inv[i]=nil end
chest = {}
special[key(HOME.x - ({[0]=1,[1]=0,[2]=-1,[3]=0})[T.d], HOME.y, HOME.z - ({[0]=0,[1]=1,[2]=0,[3]=-1})[T.d])] = "minecraft:chest"
CHESTKEY = key(HOME.x - ({[0]=1,[1]=0,[2]=-1,[3]=0})[T.d], HOME.y, HOME.z - ({[0]=0,[1]=1,[2]=0,[3]=-1})[T.d])
UNBREAK = {}
function setSpecial(x,y,z,name) special[key(x,y,z)] = name end
local DX={[0]=1,[1]=0,[2]=-1,[3]=0}; local DZ={[0]=0,[1]=1,[2]=0,[3]=-1}
local function front() return T.x+DX[T.d], T.y, T.z+DZ[T.d] end
local function addItem(name)
  -- like CC: scan from the selected slot, wrapping; first empty OR matching slot wins
  for k=0,15 do local i=((T.sel-1+k)%16)+1
    if not T.inv[i] then T.inv[i]={name=name,count=1} return true end
    if T.inv[i].name==name and T.inv[i].count<64 then T.inv[i].count=T.inv[i].count+1 return true end
  end
  LOST = (LOST or 0)+1
  if name ~= "minecraft:cobblestone" and name ~= "minecraft:gravel" then LOSTGOOD=(LOSTGOOD or 0)+1 end
  return false
end
function isFluid(b) return b=="minecraft:lava" or b=="minecraft:water" end
function clearBlock(x,y,z) local k=key(x,y,z) if special[k] then special[k]=false end dug[k]=true end
local function solid(x,y,z) local b=getBlock(x,y,z) return b~=nil and not isFluid(b) end
local function digAt(x,y,z)
  local b = getBlock(x,y,z)
  if not b or isFluid(b) then return false end
  if b=="minecraft:bedrock" or b=="allthemodium:ore" then return false end
  if b=="minecraft:chest" or b:find("computercraft") then BROKE_PROTECTED=true end
  local k=key(x,y,z)
  if special[k] then special[k]=false end
  dug[k]=true
  addItem(b)
  DUGCOUNT=(DUGCOUNT or 0)+1
  return true
end
local function moveTo(x,y,z)
  if DEAD then error("KILLED",0) end
  if solid(x,y,z) then return false end
  if T.fuel<=0 then return false end
  if getBlock(x,y,z) then clearBlock(x,y,z) end   -- moving into a fluid destroys it
  T.fuel=T.fuel-1; T.x,T.y,T.z=x,y,z; T.moves=T.moves+1
  if KILL_AT and T.moves>=KILL_AT then KILL_AT=nil; DEAD=true end
  if DEAD then error("KILLED",0) end
  return true
end
turtle = {
  forward=function() return moveTo(front()) end,
  back=function() return moveTo(T.x-DX[T.d],T.y,T.z-DZ[T.d]) end,
  up=function() return moveTo(T.x,T.y+1,T.z) end,
  down=function() return moveTo(T.x,T.y-1,T.z) end,
  turnRight=function() T.d=(T.d+1)%4 return true end,
  turnLeft=function() T.d=(T.d+3)%4 return true end,
  detect=function() local x,y,z=front() return solid(x,y,z) end,
  detectUp=function() return solid(T.x,T.y+1,T.z) end,
  detectDown=function() return solid(T.x,T.y-1,T.z) end,
  inspect=function() local x,y,z=front() local b=getBlock(x,y,z) if b then return true,{name=b,state={level=0}} end return false,"No block" end,
  inspectUp=function() local b=getBlock(T.x,T.y+1,T.z) if b then return true,{name=b,state={level=0}} end return false,"No block" end,
  inspectDown=function() local b=getBlock(T.x,T.y-1,T.z) if b then return true,{name=b,state={level=0}} end return false,"No block" end,
  dig=function() return digAt(front()) end,
  digUp=function() return digAt(T.x,T.y+1,T.z) end,
  digDown=function() return digAt(T.x,T.y-1,T.z) end,
  attack=function() return false end, attackUp=function() return false end, attackDown=function() return false end,
  getFuelLevel=function() return T.fuel end,
  getFuelLimit=function() return 20000 end,
  getItemCount=function(s) s=s or T.sel return T.inv[s] and T.inv[s].count or 0 end,
  getItemDetail=function(s) s=s or T.sel local i=T.inv[s] if i then return {name=i.name,count=i.count} end end,
  select=function(s) T.sel=s return true end,
  refuel=function(n) local i=T.inv[T.sel] if not i then return false end
    if i.name=="minecraft:lava_bucket" then T.fuel=T.fuel+1000 i.name="minecraft:bucket" LAVA_BURNED=(LAVA_BURNED or 0)+1 return true end
    if i.name~="minecraft:coal" then return false end
    n=n or i.count; if n>i.count then n=i.count end
    T.fuel=T.fuel+80*n; i.count=i.count-n; if i.count==0 then T.inv[T.sel]=nil end return true end,
  drop=function() local i=T.inv[T.sel] if not i then return false end
    local x,y,z=front()
    if key(x,y,z)==CHESTKEY and getBlock(x,y,z)=="minecraft:chest" then chest[i.name]=(chest[i.name] or 0)+i.count else DROPPED_ON_FLOOR=(DROPPED_ON_FLOOR or 0)+i.count end
    T.inv[T.sel]=nil return true end,
  dropDown=function() local i=T.inv[T.sel] if not i then return false end JUNKED=(JUNKED or 0)+i.count T.inv[T.sel]=nil return true end,
}
gps = { locate=function() return T.x+0.0,T.y+0.0,T.z+0.0 end }
FS = FS or {}
fs = {
  exists=function(p) return FS[p]~=nil end,
  delete=function(p) FS[p]=nil end,
  move=function(a,b) FS[b]=FS[a] FS[a]=nil end,
  open=function(p,m) if m=="w" then local buf={} return {write=function(s) buf[#buf+1]=s end, writeLine=function(s) buf[#buf+1]=s.."\n" end, close=function() FS[p]=table.concat(buf) end}
    else local c=FS[p] local at=1 return {readAll=function() return c end, close=function() end,
      readLine=function() if not c or at > #c then return nil end local e=c:find("\n", at, true) local line
        if e then line=c:sub(at, e-1) at=e+1 else line=c:sub(at) at=#c+1 end return line end} end end,
}
local function ser(v,ind)
  if type(v)=="table" then local parts={} for k,val in pairs(v) do parts[#parts+1]=((type(k)=="string" and k:match("^[%a_][%w_]*$")) and k or "["..(type(k)=="string" and string.format("%q",k) or tostring(k)).."]").."="..ser(val) end return "{"..table.concat(parts,",").."}"
  elseif type(v)=="string" then return string.format("%q",v) else return tostring(v) end
end
textutils = { serialize=ser, unserialize=function(s) local f=load("return "..s) return f and f() end }
peripheral = { hasType=function(side,t) if side=="back" then local x,y,z=T.x-DX[T.d],T.y,T.z-DZ[T.d] return getBlock(x,y,z)=="minecraft:chest" end end }
shell = { getRunningProgram=function() return "miner.lua" end }
SLEEPS=0
function sleep(n) SLEEPS=SLEEPS+1 if SLEEPS>200000 then error("TOO MANY SLEEPS (stuck)",0) end end
local realprint=print
LOG={}
function print(...) local t={...} for i=1,#t do t[i]=tostring(t[i]) end LOG[#LOG+1]=table.concat(t," ") if VERBOSE then realprint(...) end end
function runMiner(...) local f=assert(loadfile("/home/claude/miner.lua")) return pcall(f,...) end
function remaining(size,bottom)
  -- count undug non-bedrock blocks in the plot volume, home.y-1 down to bottom-1
  local fx,fz=DX[HOMED],DZ[HOMED]; local rx,rz=DX[(HOMED+1)%4],DZ[(HOMED+1)%4]
  local n=0
  for lf=1,size do for lr=0,size-1 do for y=bottom-1,HOME.y-1 do
    local x=HOME.x+lf*fx+lr*rx; local z=HOME.z+lf*fz+lr*rz
    if getBlock(x,y,z) then n=n+1 end
  end end end
  return n
end
HOMED=T.d
HOMEPOS=HOME

package.path = "/home/claude/turtles/?.lua;" .. package.path
package.loaded.swarm = nil
os.epoch = function() return 1700000000000 end
os.getComputerID = function() return 7 end
os.getComputerLabel = function() return "miner-1" end
SENT = {}
rednet = { open=function() end, broadcast=function(m,p) SENT[#SENT+1]={state=m.state,x=m.pos.x,y=m.pos.y,z=m.pos.z,fuel=m.fuel,proto=p,layer=m.job and m.job.layer,layers=m.job and m.job.layers,nlog=#m.log,free=m.freeSlots} end }
local modem = { isWireless=function() return true end }
peripheral.find = function(t, f) if t=="modem" and f("right", modem) then return modem end end
peripheral.getName = function() return "right" end
function runMiner(...) DEAD=false local f=assert(loadfile("/home/claude/turtles/miner.lua")) return pcall(f,...) end

turtle.getItemSpace=function(s) return 64-(T.inv[s] and T.inv[s].count or 0) end
turtle.compareTo=function(s) local a,b=T.inv[T.sel],T.inv[s] return (a and b and a.name==b.name) or (not a and not b) end
turtle.transferTo=function(s) local a=T.inv[T.sel] if not a then return false end local b=T.inv[s]
  if not b then T.inv[s]=a T.inv[T.sel]=nil return true end
  if b.name~=a.name then return false end
  local n=math.min(a.count,64-b.count) b.count=b.count+n a.count=a.count-n if a.count==0 then T.inv[T.sel]=nil end return n>0 end
HOMETRIPS=0
local oldprint=print
print=function(...) local a=... if type(a)=="string" and a:find("Going home: inventory") then HOMETRIPS=HOMETRIPS+1 end return oldprint(...) end

-- ===== cooperative scheduling so remote orders can interrupt a job =====
CMDQ = {}     -- list of {at=moves, cmd={...}}
parallel = { waitForAny = function(...)
  local cos = {}
  for i, f in ipairs({...}) do cos[i] = coroutine.create(f) end
  while true do
    for i, co in ipairs(cos) do
      local ok, err = coroutine.resume(co)
      if not ok then error(err, 0) end
      if coroutine.status(co) == "dead" then return i end
    end
  end
end }
local function yieldIfCan() if coroutine.isyieldable() then coroutine.yield() end end
local baseSleep = sleep
sleep = function(n)
  if DEAD then error("KILLED", 0) end
  if n and n >= 60 and #CMDQ == 0 then error("IDLE", 0) end
  if n and n >= 20 and #CMDQ == 0 and (not JOBQ or #JOBQ == 0) then error("IDLE", 0) end
  baseSleep(n); yieldIfCan()
end
for _, name in ipairs({"forward","back","up","down"}) do
  local f = turtle[name]
  turtle[name] = function() local r = f(); yieldIfCan(); return r end
end
rednet.receive = function(proto)
  while true do
    local c = CMDQ[1]
    if c and T.moves >= c.at then table.remove(CMDQ, 1); return 3, c.cmd end
    coroutine.yield()
  end
end
os.reboot = function() error("REBOOT", 0) end
STATES = {}
local oldB = rednet.broadcast
rednet.broadcast = function(m, p) if STATES[#STATES] ~= m.state then STATES[#STATES+1] = m.state end; return oldB(m, p) end

-- buckets: placing an empty bucket against lava picks it up
local function scoopAt(x,y,z)
  local i=T.inv[T.sel]
  if i and i.name=="minecraft:bucket" and getBlock(x,y,z)=="minecraft:lava" then
    clearBlock(x,y,z)
    if i.count==1 then i.name="minecraft:lava_bucket" return true end
    i.count=i.count-1
    for s=1,16 do if not T.inv[s] then T.inv[s]={name="minecraft:lava_bucket",count=1} return true end end
    return true
  end
  return false
end
turtle.place=function() local x,y,z=T.x+({[0]=1,[1]=0,[2]=-1,[3]=0})[T.d],T.y,T.z+({[0]=0,[1]=1,[2]=0,[3]=-1})[T.d] return scoopAt(x,y,z) end
turtle.placeUp=function() return scoopAt(T.x,T.y+1,T.z) end
turtle.placeDown=function() return scoopAt(T.x,T.y-1,T.z) end
LABEL="miner-1"
os.getComputerLabel=function() return LABEL end
os.setComputerLabel=function(l) LABEL=l end

-- tool slots: the left side holds the pickaxe (or a Geo Scanner swapped in); the right holds the modem
TOOL = "minecraft:diamond_pickaxe"
SCANS = 0
local function equipTool()
  local i = T.inv[T.sel]
  local old = TOOL
  TOOL = i and i.name or nil
  T.inv[T.sel] = old and {name=old, count=1} or nil
  return true
end
turtle.equipLeft = equipTool
turtle.equipRight = function() return false end
peripheral.getType = function(side) if side == "right" then return "modem" end if side == "left" and TOOL == "advancedperipherals:geo_scanner" then return "geo_scanner" end return nil end
peripheral.wrap = function(side)
  if side ~= "left" or TOOL ~= "advancedperipherals:geo_scanner" then return nil end
  return { scanBlocks = function(r)
    SCANS = SCANS + 1
    local out = {}
    for dx=-r,r do for dy=-r,r do for dz=-r,r do
      local b = getBlock(T.x+dx, T.y+dy, T.z+dz)
      if b then out[#out+1] = {x=dx, y=dy, z=dz, name = (b=="minecraft:coal") and "minecraft:coal_ore" or b} end
    end end end
    return out
  end }
end
-- without a pickaxe fitted nothing can be dug
for _, n in ipairs({"dig","digUp","digDown"}) do
  local f = turtle[n]
  turtle[n] = function() if TOOL ~= "minecraft:diamond_pickaxe" then DUG_WITHOUT_PICK = (DUG_WITHOUT_PICK or 0) + 1 return false end return f() end
end
