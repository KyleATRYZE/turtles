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
-- clear the tree and flowers (the site was cleared by the builder), open the hole over the pad
for y=15,24 do for dx=-2,2 do for dz=-2,2 do setSpecial(-4456+dx, y, 1541+dz, false) end end end
setSpecial(-4458, 15, 1540, false) setSpecial(-4455, 15, 1542, false) setSpecial(-4453, 15, 1543, false)
setSpecial(-4456, 14, 1543, "minecraft:stone") setSpecial(-4456, 13, 1543, "minecraft:stone")
for y=16,60 do setSpecial(-4462, y, 1521, false) end
setSpecial(-4462, 19, 1521, "minecraft:stone")          -- the hole has been patched with a stone
T.x, T.y, T.z = -4462, 15, 1521
T.inv = {}
T.inv[1] = {name="minecraft:coal", count=8}
T.inv[2] = {name="minecraft:bucket", count=1}
TOOL = "minecraft:diamond_pickaxe"
FS["helper.state"] = textutils.serialize({ job = { plan="factory_shell", ox=OX, oy=OY, oz=OZ, xmin=3, xmax=5, layer=0 } })
FS[".version"] = "abc123"
""")
f=L.eval('loadfile("/home/claude/turtles/helper.lua")')
r=L.eval('function(f) return {pcall(f)} end')(f)
print("helper run:", list(r.values()), "| pos:", g.T.x, g.T.y, g.T.z, "| fuel:", g.T.fuel)
print("log:", list(g.LOG.values())[-10:])
print("orders:", [ (o.n, [ (l[1].split(':')[1], l[2]) for l in o['items'].values()], o.fuel) for o in g.ORDERS.values()])
plan=list(L.eval('PLAN').values())
pal=[]; mode=None; mine_ok=mine_bad=other_built=0; bad=[]
for line in plan:
    if line.startswith("P "): mode="P"; continue
    if line.startswith("B "): mode="B"; continue
    if mode=="P": pal.append(line.split())
    else:
        x,y,z,i=map(int,line.split()); name,fac=pal[i]
        wx,wy,wz=g.OX+x,g.OY+y,g.OZ+z
        got=L.eval(f'getBlock({wx},{wy},{wz})'); gf=L.eval(f'FACINGS["{wx},{wy},{wz}"]')
        right = got==name and (fac=="-" or gf==fac)
        if 3<=x<=5 and y>=0:
            if right: mine_ok+=1
            else: mine_bad+=1; bad.append((x,y,z,name.split(':')[1],got))
        elif right and y>=0: other_built+=1
print(f"my share right: {mine_ok}, wrong: {mine_bad} {bad[:6]} | others' blocks built by me: {other_built}")
print("state:", {k:v for k,v in dict(L.eval('textutils.unserialize(FS["helper.state"])')).items() if k in ('i','done','left','skipped','turn')}, "| broke protected:", g.BROKE_PROTECTED, "| stone in hole now:", L.eval('getBlock(-4462,19,1521)'))
