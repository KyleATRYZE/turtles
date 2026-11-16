-- Extra world pieces for swarm tests: a base with a drop-off chest, launch pad and lanes.
-- Base (all in open air above the ground, ground top is y=19):
BASE = { f = {x=-4461,y=25,z=1500} }
setSpecial(BASE.f.x, BASE.f.y, BASE.f.z, "computercraft:turtle_normal")     -- the factory turtle
setSpecial(BASE.f.x+1, BASE.f.y, BASE.f.z, "minecraft:chest")               -- drop-off chest
DOCK  = {x=BASE.f.x+1, y=BASE.f.y+1, z=BASE.f.z}
EXIT1 = {x=BASE.f.x,   y=BASE.f.y+1, z=BASE.f.z}
PAD   = {x=BASE.f.x,   y=BASE.f.y,   z=BASE.f.z+1}
EXIT2 = {x=PAD.x, y=PAD.y+1, z=PAD.z}
local function key(x,y,z) return x..","..y..","..z end
DOCKCHEST = {}
local oldDropDown = turtle.dropDown
turtle.dropDown = function()
  local i = T.inv[T.sel]; if not i then return false end
  if getBlock(T.x, T.y-1, T.z) == "computercraft:turtle_normal" then
    RESCUED = RESCUED + i.count; T.inv[T.sel] = nil; return true
  end
  if getBlock(T.x, T.y-1, T.z) == "minecraft:chest" then
    if DOCK_FULL and DOCK_FULL > 0 then DOCK_FULL = DOCK_FULL - 1 return false end
    DOCKCHEST[i.name] = (DOCKCHEST[i.name] or 0) + i.count; T.inv[T.sel] = nil; return true
  end
  return oldDropDown()
end
-- job messages
JOBQ, NEEDS, DONE, FUELREQ = {}, 0, {}, 0
local clock = 0
os.clock = function() clock = clock + 0.4 return clock end
local statusBroadcast = rednet.broadcast
rednet.broadcast = function(m, p)
  if m.type == "need_job" then NEEDS = NEEDS + 1; NEEDJOB = true; if #JOBQ == 0 and NEEDS > 2 then error("NOJOB", 0) end
  elseif m.type == "job_done" then DONE[#DONE+1] = m.index
  elseif m.type == "release" then RELEASED[#RELEASED+1] = m.index
  elseif m.type == "rescue" then RESCUE_CALLS = (RESCUE_CALLS or 0) + 1
  elseif m.type == "bucket_request" then BUCKETREQ = (BUCKETREQ or 0) + 1
    if not NO_BUCKETS then for i=1,16 do if not T.inv[i] then T.inv[i] = {name="minecraft:bucket", count=1} break end end end
  elseif m.type == "empties_request" then EMPTYREQ = (EMPTYREQ or 0) + 1
  elseif m.type == "scanner_request" then SCANREQ = (SCANREQ or 0) + 1
    for i=1,16 do if not T.inv[i] then T.inv[i] = {name="advancedperipherals:geo_scanner", count=1} break end end
  elseif m.type == "controller_request" then CTLREQ = (CTLREQ or 0) + 1
    -- (GIVE_CTL: the factory hands a Chunk Controller over; otherwise it has none to spare)
    if GIVE_CTL then
      for i=1,16 do if not T.inv[i] then T.inv[i] = {name="advancedperipherals:chunk_controller", count=1} break end end
    end
  elseif m.type == "fuel_request" then FUELREQ = FUELREQ + 1
    -- the factory answers by dropping coal into the turtle
    for i=1,16 do if not T.inv[i] then T.inv[i] = {name="minecraft:coal", count=16} break end end
  else
    m.pos = m.pos or {}
    statusBroadcast(m, p)
  end
end
local cmdReceive = rednet.receive
RESCUEQ, RELEASED, RESCUED = {}, {}, 0
rednet.receive = function(proto, timeout)
  if proto == "swarm_rescue" then
    local r = RESCUEQ[1]
    if r and T.moves >= r.at then table.remove(RESCUEQ, 1) return r.id, r.msg end
    if coroutine.isyieldable() then coroutine.yield() end
    return nil
  end
  if proto == "swarm_job" then
    if NEEDJOB and JOBQ[1] then NEEDJOB = false; local j = table.remove(JOBQ, 1); j.forId = os.getComputerID(); return 99, j end
    if coroutine.isyieldable() then coroutine.yield() end
    return nil
  end
  return cmdReceive(proto, timeout)
end
function job(index, x0, z0, size, topY, bottom, cruise)
  return {type="job", index=index, x0=x0, z0=z0, size=size, topY=topY, bottom=bottom, cruise=cruise, dock=DOCK, exit1=EXIT1, exit2=EXIT2}
end
function plotRemaining(x0, z0, size, topY, bottom)
  local n = 0
  for x=x0,x0+size-1 do for z=z0,z0+size-1 do for y=bottom-1,topY-1 do local b=getBlock(x,y,z) if b and not isFluid(b) then n=n+1 end end end end
  return n
end
-- Lane discipline: never go DOWN the in-shaft or UP the out-shaft, and never rise above the base.
VISITED_DOCKCOL_UP = 0   -- (name kept) count of wrong-way moves
MAXY = -999
INSHAFT  = {x=2*DOCK.x-EXIT1.x, z=2*DOCK.z-EXIT1.z}
OUTSHAFT = {x=2*EXIT2.x-EXIT1.x, z=2*EXIT2.z-EXIT1.z}
do
  local up, down = turtle.up, turtle.down
  turtle.up = function()
    local bad = (T.x == OUTSHAFT.x and T.z == OUTSHAFT.z and T.y < DOCK.y)
    local r = up()
    if r and bad then VISITED_DOCKCOL_UP = VISITED_DOCKCOL_UP + 1 end
    if T.y > MAXY then MAXY = T.y end
    return r
  end
  turtle.down = function()
    local bad = (T.x == INSHAFT.x and T.z == INSHAFT.z and T.y <= DOCK.y)
    local r = down()
    if r and bad then VISITED_DOCKCOL_UP = VISITED_DOCKCOL_UP + 1 end
    return r
  end
end
FLOORS, FLOOR_IN_SHAFT, GRID = 0, 0, 4
local bucketPlaceDown = turtle.placeDown
turtle.placeDown = function()
  local i = T.inv[T.sel]
  if i and i.name == "minecraft:bucket" then return bucketPlaceDown() end
  if not i or i.name ~= "minecraft:cobblestone" then return false end
  if getBlock(T.x, T.y-1, T.z) then return false end
  setSpecial(T.x, T.y-1, T.z, "minecraft:cobblestone")
  i.count = i.count - 1; if i.count == 0 then T.inv[T.sel] = nil end
  FLOORS = FLOORS + 1
  local inShaftCol = (T.x==INSHAFT.x and T.z==INSHAFT.z) or (T.x==OUTSHAFT.x and T.z==OUTSHAFT.z)
    or ((T.x-EXIT1.x) % GRID == 0 and (T.z-EXIT1.z) % GRID == 0)
  if inShaftCol then FLOOR_IN_SHAFT = FLOOR_IN_SHAFT + 1 end
  return true
end
function placeAt(p, d) T.x, T.y, T.z = p.x, p.y, p.z; T.d = d or 0 end

function addLava(x0, z0, size, y)   -- a lava pool covering one layer of a plot
  for x=x0,x0+size-1 do for z=z0,z0+size-1 do setSpecial(x,y,z,"minecraft:lava") end end
end
function invNames() local t={} for i=1,16 do if T.inv[i] then t[#t+1]=T.inv[i].name.." x"..T.inv[i].count end end return table.concat(t,", ") end
