START_X = nil
SCANNING = true
F = {x=-4461, y=15, z=1521}
-- the base room, carved out of the ground: x -4466..-4456, z 1518..1524, y 15..17
for x=-4466,-4456 do for z=1518,1524 do for y=15,17 do setSpecial(x,y,z,false) end end end
setSpecial(F.x, F.y, F.z, "computercraft:turtle_normal")             -- factory
setSpecial(F.x+1, F.y, F.z, "minecraft:chest")                       -- drop-off chest
setSpecial(F.x, F.y-1, F.z, "computercraft:wired_modem_full")
setSpecial(F.x-1, F.y-1, F.z, "computercraft:disk_drive")
setSpecial(-4458, 15, 1523, "minecraft:furnace")
for z=1518,1524 do setSpecial(-4456, 15, z, "minecraft:chest") end   -- a storage wall
-- the shafts, from the base level down
for y=5,16 do setSpecial(-4459, y, 1521, false) setSpecial(-4463, y, 1521, false) end
-- the hut's way out: a corridor south from the room to a doorway in a
-- hillside, with the hill above the doorway
for z=1525,1529 do setSpecial(-4462, 15, z, false) setSpecial(-4462, 16, z, false) end
for x=-4470,-4450 do for z=1530,1560 do for y=15,19 do setSpecial(x,y,z,false) end end end
-- some landscape: a tree, a hill, a pond, a little hut
for y=20,24 do setSpecial(-4450, y, 1530, "minecraft:oak_log") end
for dx=-2,2 do for dz=-2,2 do for y=23,24 do if not (dx==0 and dz==0) then setSpecial(-4450+dx, y, 1530+dz, "minecraft:oak_leaves") end end end end
for x=-4480,-4475 do for z=1505,1515 do for y=20,21 do setSpecial(x,y,z,"minecraft:stone") end end end
for x=-4445,-4442 do for z=1510,1512 do setSpecial(x,19,z,"minecraft:water") end end
for x=-4470,-4467 do for z=1530,1533 do setSpecial(x,20,z,"minecraft:oak_planks") setSpecial(x,22,z,"minecraft:oak_planks") end end
BASE = { f=F, pad={x=F.x-1,y=F.y,z=F.z}, padTurns=2,
  dock={x=F.x+1,y=F.y+1,z=F.z}, exit1={x=F.x,y=F.y+1,z=F.z}, exit2={x=F.x-1,y=F.y+1,z=F.z} }
FS[".base"] = textutils.serialize(BASE)
T.x, T.y, T.z = START_X or BASE.pad.x, BASE.pad.y, START_Z or BASE.pad.z
T.inv[1] = {name="minecraft:coal", count=24}
T.inv[2] = {name="advancedperipherals:weak_automata_core", count=1}
if SCANNING then T.inv[3] = {name="advancedperipherals:geo_scanner", count=1} end
TOOL = nil
LABEL = "miner-40"
MAPS = {}
local hb = rednet.broadcast
rednet.broadcast = function(m, p)
  if m.type == "map" then MAPS[#MAPS+1] = m return end
  if m.type == "fuel_request" then FUELREQ = (FUELREQ or 0) + 1
    for i=1,16 do if not T.inv[i] then T.inv[i] = {name="minecraft:coal", count=16} break end end return end
  return hb(m, p)
end
LANEHITS = 0
local lanes = {}
local function k(x,y,z) return x..","..y..","..z end
for _,p in ipairs({BASE.dock, BASE.exit1, BASE.exit2}) do lanes[k(p.x,p.y,p.z)] = true end
for y=5,16 do lanes[k(-4459,y,1521)] = true lanes[k(-4463,y,1521)] = true end
for _, n in ipairs({"forward","back","up","down"}) do
  local f = turtle[n]
  turtle[n] = function() local r = f() if r and lanes[k(T.x,T.y,T.z)] then LANEHITS = LANEHITS + 1 end return r end
end
