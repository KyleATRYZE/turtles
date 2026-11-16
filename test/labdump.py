import lupa, sys, json
from collections import Counter
ABORT = len(sys.argv) > 1 and sys.argv[1] == "abort"
L=lupa.LuaRuntime(unpack_returned_tuples=True)
L.execute("START_D=3; START_FUEL=2000")
L.execute(open('harness.lua').read())
L.execute(open('bworld.lua').read())
L.execute(f'''
ABORT = {"true" if ABORT else "false"}
-- a fake swarm library: orders and reports go nowhere
package.preload.swarm = function() return {{
  open = function() return true end, report = function() end,
  runWithCommands = function(task) task() return nil end, pinVersion = function() end }} end
-- the mini plan: a 6 x 4 floor, 2 high walls, a row of stairs on top
PLAN = {{"P 5", "minecraft:polished_deepslate -", "minecraft:stone_bricks -",
  "minecraft:deepslate_tile_stairs west", "minecraft:deepslate_tile_stairs east", "minecraft:cobblestone -"}}
local blocks = {{"2 -2 3 4", "2 -1 3 4"}}      -- foundation under a dip in the ground
for z=0,3 do for x=0,5 do blocks[#blocks+1] = x.." 0 "..z.." 0" end end
for y=1,2 do for z=0,3 do for x=0,5 do if x==0 or x==5 or z==0 or z==3 then blocks[#blocks+1] = x.." "..y.." "..z.." 1" end end end end
for x=0,5 do blocks[#blocks+1] = x.." 3 0 "..(x < 3 and 2 or 3) end
PLAN[1] = "P 6" PLAN[7] = "minecraft:glass_pane -"
for x=1,4 do blocks[#blocks+1] = x.." 3 3 5" end            -- windows, no glass to be had
PLAN[#PLAN+1] = "B "..#blocks
for _, b in ipairs(blocks) do PLAN[#PLAN+1] = b end
TPLAN = {{"P 1", "minecraft:dirt -", "B 6", "-2 -1 3 0", "-3 -1 3 0", "-2 -2 4 0", "-2 -1 4 0", "8 -1 1 0", "-2 -1 2 0"}}
http = {{ get = function(url) URL = url local i = 0
  local text = table.concat(url:find("terraform") and TPLAN or PLAN, "\\n")
  return {{ readAll = function() return text end, close = function() end }} end }}
-- placing blocks: the facing ends up turned by PLACE_TURN from the turtle's
FACE_NAMES = {{[0]="east", [1]="south", [2]="west", [3]="north"}}
PLACE_TURN = 2
FACINGS = {{}} PLACED = 0
local function placeAt(x,y,z)
  local i = T.inv[T.sel]
  if not i or i.name:find("pickaxe") or i.name:find("scanner") or i.name:find("coal") then return false end
  local b = getBlock(x,y,z)
  if b and b ~= "minecraft:short_grass" then return false end
  setSpecial(x,y,z,i.name)
  if i.name:find("stairs") then FACINGS[x..","..y..","..z] = FACE_NAMES[(T.d + PLACE_TURN) % 4] end
  i.count = i.count - 1 if i.count == 0 then T.inv[T.sel] = nil end
  PLACED = PLACED + 1
  return true
end
turtle.placeDown = function() return placeAt(T.x, T.y-1, T.z) end
turtle.inspectDown = function() local b = getBlock(T.x,T.y-1,T.z)
  if not b then return false, "No block" end
  return true, {{name=b, state={{facing=FACINGS[T.x..","..(T.y-1)..","..T.z]}}}} end
turtle.dropUp = function() local i = T.inv[T.sel] if i then DROPPED = (DROPPED or 0) + i.count T.inv[T.sel] = nil end return true end
turtle.drop = function() local i = T.inv[T.sel] if i then DEPOSITED = (DEPOSITED or 0) + i.count DEPOSIT_AT = T.x..","..T.y..","..T.z..",d"..T.d T.inv[T.sel] = nil end return true end
turtle.dropDown = function() local i = T.inv[T.sel] if i then DEPOSITED = (DEPOSITED or 0) + i.count T.inv[T.sel] = nil end return true end
-- the factory: hands over whatever is asked for
REPLIES = {{}} ORDERS = {{}}
local function give(name, n)
  while n > 0 do
    local placed = false
    for s=1,16 do if not T.inv[s] then local c = math.min(64, n) T.inv[s] = {{name=name, count=c}} n = n - c placed = true break end end
    if not placed then return end
  end
end
local hb = rednet.broadcast
rednet.broadcast = function(m, p)
  if m.type == "materials" then
    if not PENDING or PENDING.n ~= m.n then ORDERS[#ORDERS+1] = m end
    PENDING = m
    return
  end
  if m.type == "map" then return end
  return hb(m, p)
end
rednet.receive = function(proto, t)
  if proto == "swarm_job" then
    local m = PENDING
    if not m then error("NO REPLY", 0) end
    if T.x == -4462 and T.y == 15 and T.z == 1521 then      -- on the launch pad
      PENDING = nil
      local given = {{}}
      local missing = {{}}
      for _, l in ipairs(m.items) do
        if l[1] == "minecraft:glass_pane" then missing[l[1]] = l[2] else give(l[1], l[2]) given[l[1]] = l[2] end
      end
      if m.fuel > 0 then give("minecraft:coal", m.fuel) end
      return 3, {{type="materials_ready", forId=os.getComputerID(), n=m.n, given=given, missing=missing}}
    end
    if T.x == PARK_X and T.y == PARK_Y and T.z == PARK_Z then WAITED_AT_PARK = true end
    return 3, {{type="load_ready", forId=os.getComputerID(), n=m.n}}
  end
  while true do coroutine.yield() end
end
-- the site: in the sunken meadow, with a tree and some flowers on it
OX, OY, OZ = -4458, 15, 1540
for y=15,19 do setSpecial(-4456, y, 1541, "regions_unexplored:magnolia_log") end
for dx=-1,1 do for dz=-1,1 do setSpecial(-4456+dx, 20, 1541+dz, "regions_unexplored:pink_magnolia_leaves") end end
setSpecial(-4458, 15, 1540, "regions_unexplored:hyssop") setSpecial(-4455, 15, 1542, "minecraft:poppy")
setSpecial(-4453, 15, 1543, "minecraft:short_grass")
setSpecial(-4456, 14, 1543, false) setSpecial(-4456, 13, 1543, false)   -- a dip, two deep
if ABORT then setSpecial(-4454, 15, 1539, "minecraft:oak_planks") end
''')


g=L.globals()
L.execute("""
for y=16,60 do setSpecial(-4462, y, 1521, false) end
T.x, T.y, T.z = -4462, 15, 1521
T.inv = {}
T.inv[1] = {name="minecraft:coal", count=3}
for s = 2, 16 do T.inv[s] = {name="minecraft:polished_deepslate", count=64} end   -- fit-out leftovers: every slot taken
TOOL = "minecraft:diamond_pickaxe"
OPS = [[fetch|sophisticatedstorage:controller=1|dump;inv]]
FS["helper.state"] = textutils.serialize({ done = true, job = { plan="factory_shell", ox=OX, oy=OY, oz=OZ, xmin=3, xmax=5, layer=0 }, lab = { ops = OPS } })
FS[".version"] = "abc123"
local D = {[0]={1,0},[1]={0,1},[2]={-1,0},[3]={0,-1}}
local function front() return T.x + D[T.d][1], T.y, T.z + D[T.d][2] end
MACHINE = {}
turtle.place = function() local i = T.inv[T.sel] if not i then return false, "No items to place" end
  local x,y,z = front() if getBlock(x,y,z) then return false, "Cannot place block here" end
  setSpecial(x,y,z,i.name) i.count = i.count - 1 if i.count == 0 then T.inv[T.sel] = nil end return true end
turtle.inspect = function() local b = getBlock(front()) if not b then return false, "No block" end return true, {name=b, state={facing="north"}} end
turtle.dig = function() local x,y,z = front() local b = getBlock(x,y,z) if not b then return false end
  setSpecial(x,y,z,false) for s=1,16 do if not T.inv[s] then T.inv[s] = {name=b, count=1} break end end return true end
turtle.drop = function(n) local i = T.inv[T.sel] local b = getBlock(front())
  if i and T.x == -4462 and T.y == 15 and T.z == 1521 then HANDED = (HANDED or 0) + i.count T.inv[T.sel] = nil return true end if not i or not b or not b:find("mekanism") then return false, "No space for items" end
  n = math.min(n or 64, i.count) MACHINE[#MACHINE+1] = {name=i.name, count=n} i.count = i.count - n if i.count == 0 then T.inv[T.sel] = nil end return true end
turtle.suck = function(n) local m = table.remove(MACHINE) if not m then return false, "No items to take" end
  for s=1,16 do if not T.inv[s] then T.inv[s] = m break end end return true end
turtle.detect = function() return getBlock(front()) ~= nil end
turtle.back = function() local x, z = T.x - D[T.d][1], T.z - D[T.d][2] if getBlock(x, T.y, z) then return false end T.x, T.z = x, z T.fuel = T.fuel - 1 return true end
local gt = peripheral.getType
peripheral.getType = function(side) if side == "front" and getBlock(front()) then return "metallurgicInfuser", "inventory" end return gt(side) end
peripheral.getMethods = function(side) if side == "front" and getBlock(front()) then return {"getEnergy", "setMode", "getDirection", "list"} end end
peripheral.call = function(side, m, a, b) if m == "getEnergy" then return 0, {max = 40000} end if m == "setMode" then return type(a) .. ":" .. tostring(a.n) .. ":" .. tostring(b) end error("no such method") end
local n = 0
local os_sleep = sleep
sleep = function(s) if s == 60 then n = n + 1 if n > 2 then error("IDLE", 0) end end return os_sleep(s) end
""")
f=L.eval('loadfile("/home/claude/turtles/helper.lua")')
r=L.eval('function(f) return {pcall(f)} end')(f)
print("lab run:", list(r.values()))
st=L.eval('textutils.unserialize(FS["helper.state"])')
for line in st.labOut.values(): print("  ", line)
orders=[[(l[1], l[2]) for l in o['items'].values()] + [o.fuel] for o in g.ORDERS.values()]
print("orders:", orders, "| handed back to the factory:", g.HANDED)
have=sum(i.count for i in g.T.inv.values() if i.name=="sophisticatedstorage:controller")
junk=sum(i.count for i in g.T.inv.values() if i.name=="minecraft:polished_deepslate")
print("controller on board:", have, "| leftovers on board:", junk)
ok = have==1 and junk==0 and g.HANDED==15*64 and len(orders)==2 and orders[0][:-1]==[] and orders[1][0]==("sophisticatedstorage:controller",1)
print("PASS" if ok else "FAILED")
