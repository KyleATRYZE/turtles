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
# first run: the maps
f=L.eval('loadfile("/home/claude/turtles/builder.lua")')
r=L.eval('function(f) return {pcall(f)} end')(f)
g=L.globals()
print("maps run:", list(r.values()), "| pos:", g.T.x, g.T.y, g.T.z, "log:", list(g.LOG.values())[-2:])

L.execute("""
-- a sand patch on the meadow, two deep, with one column three deep and a stone in the middle
for x=-4461,-4458 do for z=1550,1553 do setSpecial(x,14,z,"minecraft:sand") setSpecial(x,13,z,"minecraft:sand") end end
setSpecial(-4460,12,1551,"minecraft:sand")
setSpecial(-4459,14,1552,"minecraft:stone")
local st = textutils.unserialize(FS["builder.state"])
st.gather = { name="minecraft:sand", want=200, r=6, seeds={{-4460,1551}}, from={{-4460,1551}} }
FS["builder.state"] = textutils.serialize(st)
for s=1,16 do if not T.inv[s] then T.inv[s] = {name="minecraft:diamond_pickaxe", count=1} break end end
""")
f=L.eval('loadfile("/home/claude/turtles/builder.lua")')
r=L.eval('function(f) return {pcall(f)} end')(f)
print("gather run:", list(r.values()), "| pos:", g.T.x, g.T.y, g.T.z, "| fuel:", g.T.fuel)
print("log:", list(g.LOG.values())[-8:])
left=[(x,y,z) for x in range(-4463,-4455) for z in range(1548,1556) for y in range(10,16) if L.eval(f'getBlock({x},{y},{z})')=="minecraft:sand"]
print("sand left:", left, "| deposited:", g.DEPOSITED, "at", g.DEPOSIT_AT, "| stone still there:", L.eval('getBlock(-4459,14,1552)'), "| broke protected:", g.BROKE_PROTECTED, "| dug:", g.DUGCOUNT)
st=L.eval('textutils.unserialize(FS["builder.state"])')
print("gather cleared:", st.gather is None, "| carrying sand:", [ (i.name,i.count) for i in g.T.inv.values() if i and 'sand' in i.name])
