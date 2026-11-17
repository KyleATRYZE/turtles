"""The quartz line (tools/quartzline.py), twice over.

1. On paper: every cell it uses is open floor in the plans (the as-fitted
   shell, the storeroom and foundry floor fit-outs, the old fit-out's sapling
   spots, the Mekanism line and the ground kept for it, the drone lane); the
   water, let run, stays where it is meant to; the fan blows through water
   onto the soul sand and stops at a wall within its reach; the reconstructor
   fires at the sand with a wall behind it; the generators touch it.
2. In a simulated world with the building in it: a helper runs the casing,
   build and run steps one after the other (the factory hands over what is
   asked for). The world plays the machines by the rules the layout counts
   on (a wheel's facing goes to its axis' positive end, a fan faces away from
   the wheel it sits against, a reconstructor faces whoever placed it and
   turns sand to soul sand while its generators have coal, soul sand in the
   fan's wash water comes out as 4 quartz in 8), and water spreads into
   every open cell beside it and below it.

    cd test && python3 quartzline.py
"""
import os, sys
from collections import Counter
import lupa

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "tools"))
import quartzline as Q
import mekline

fails = []
def check(what, ok):
    print(("ok   " if ok else "FAIL ") + what)
    if not ok: fails.append(what)

# ---------------------------------------------------------------- the plans
def shell(fn):
    solid, mode = {}, None
    for line in open(os.path.join(ROOT, "blueprints", fn)):
        t = line.split()
        if len(t) == 2 and t[0] in ("P", "B") and t[1].isdigit():
            mode = t[0]
            continue
        if mode == "B" and len(t) >= 3:
            solid[tuple(map(int, t[:3]))] = True
    return solid

def plan(fn):
    cells, mode, pal = {}, None, []
    for line in open(os.path.join(ROOT, "blueprints", fn)):
        t = line.split()
        if not t or t[0] == "S": continue
        if len(t) == 2 and t[0] in ("P", "O") and t[1].isdigit():
            mode = t[0]
            continue
        if mode == "P": pal.append(t[0])
        elif mode == "O":
            p = tuple(map(int, t[1:4]))
            if t[0] == "D": cells.pop(p, None)
            else: cells[p] = pal[int(t[4])]
    return cells

SHELL = shell("factory_asfit3.txt")
FITTED = {}
for fn in ("factory_storeroom.txt", "factory_foundryfloor.txt", "factory_screens.txt",
           "factory_storescreen.txt", "factory_touchup.txt", "factory_fitout.txt"):
    FITTED.update(plan(fn))
MEK = {}
for b in mekline.BLOCKS:
    p = tuple(b[1:4])
    if b[4] == "dig": MEK.pop(p, None)
    else: MEK[p] = b[4]

def kept_clear(p):
    """Why a cell is not ours to use, or None."""
    x, y, z = p
    if p in SHELL: return "the building"
    if p in FITTED: return "fitted: " + FITTED[p]
    if p in MEK: return "the Mekanism line"
    if x in (39, 40): return "the drone lane"
    if 35 <= x <= 37 and 9 <= z <= 21: return "the Mekanism line's walkway"
    if 29 <= x <= 34 and 12 <= z <= 21: return "the pool and the gas plants' ground"
    if x >= 41: return "the foundry plinth"
    if not (28 <= x <= 43 and 4 <= z <= 29 and 1 <= y <= 5): return "outside the bay"
    return None

CELLS = Q.cells()
WALKS = set()
for ops in (Q.casing(Q.opts([])), Q.build(Q.opts([])), Q.run(8, Q.opts([]))):
    for s in ops:
        a = s.split("|")
        if a[0] == "walk": WALKS.add(tuple(map(int, a[1:4])))
used = set(CELLS) | Q.WATER_CELLS | {Q.TARGET, Q.STAND, Q.WASH_STAND, Q.CASING_AT, Q.CASING_STAND} | WALKS
bad = {p: kept_clear(p) for p in used if kept_clear(p)}
print("cells used:", len(used), "| in the way:", bad)
check("every cell the line uses or stands on is open floor kept for nothing else", not bad)

# water let run: into every open cell beside it, and down
def solid(p):
    return p[1] <= 0 or p in SHELL or (p in CELLS and CELLS[p] != "minecraft:water")
wet, todo = set(Q.WATER_SOURCES), list(Q.WATER_SOURCES)
while todo:
    x, y, z = todo.pop()
    for n in ((x, y - 1, z), (x + 1, y, z), (x - 1, y, z), (x, y, z + 1), (x, y, z - 1)):
        if n not in wet and not solid(n) and len(wet) < 200:
            wet.add(n); todo.append(n)
check("the water runs only where it is meant to: %s" % sorted(wet - Q.WATER_CELLS), wet == Q.WATER_CELLS)

wx, wy, wz = Q.WHEEL_AT
check("water runs south over the wheel's top from a source to its north",
      Q.WHEEL_FLOW == (wx, wy + 1, wz) and Q.WHEEL_SRC == (wx, wy + 1, wz - 1))
check("the fan is on the wheel's axis (east of it)", Q.FAN_AT == (wx + 1, wy, wz))
air, x = [], Q.FAN_AT[0] + 1
while not solid((x, wy, wz)) and x - Q.FAN_AT[0] <= 4:
    air.append((x, wy, wz)); x += 1
check("the fan blows through water onto the soul sand's cell and into a wall within 3",
      air and air[0] in Q.WATER_CELLS and Q.WASH_AT in air and len(air) <= 3 and (x, wy, wz) in CELLS)
rx, ry, rz = Q.RECON_AT
check("the reconstructor fires east at t, with a wall behind t",
      Q.TARGET == (rx + 1, ry, rz) and CELLS.get((rx + 2, ry, rz)) == Q.COBBLE)
check("the turtle stands south of t, facing north",
      Q.STAND == (Q.TARGET[0], Q.TARGET[1], Q.TARGET[2] + 1))
near = {(rx + dx, ry + dy, rz + dz) for dx, dy, dz in ((1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1))}
check("both generators touch the reconstructor", all(c in near for c, _ in Q.DOWN))
check("the wash stand is over the soul sand's cell", Q.WASH_STAND == (Q.WASH_AT[0], 2, Q.WASH_AT[2]))

# ---------------------------------------------------------------- the world
OX, OY, OZ = Q.OX, Q.OY, Q.OZ
L = lupa.LuaRuntime(unpack_returned_tuples=True)
L.execute("START_D=3; START_FUEL=4000")
os.chdir(HERE)
L.execute(open("harness.lua").read())
L.execute(open("bworld.lua").read())
files = {n: open(os.path.join(ROOT, "blueprints", n + ".txt")).read()
         for n in ("factory_asfit3", "factory_storeroom")}
L.globals().PLANFILES = L.table_from(files)
build_in = lupa.LuaRuntime  # (keep flake quiet)
L.execute('''
package.preload.swarm = function() return {
  open = function() return true end, report = function() end,
  runWithCommands = function(task) task() return nil end, pinVersion = function() end } end
http = { get = function(url)
  for name, text in pairs(PLANFILES) do
    if url:find(name, 1, true) then return { readAll = function() return text end, close = function() end } end
  end end }
-- time passes only when the turtle waits
CLOCK = 0
os.clock = function() return CLOCK end
local idles = 0
sleep = function(s)
  s = s or 0
  SLEEPS = SLEEPS + 1 if SLEEPS > 400000 then error("TOO MANY SLEEPS", 0) end
  CLOCK = CLOCK + s
  if s == 60 then idles = idles + 1 if idles > 2 then idles = 0 error("IDLE", 0) end end
  if coroutine.isyieldable() then coroutine.yield() end
end
-- the factory: hands over whatever is asked for, on the pad
ORDERS = {}
local function give(name, n)
  while n > 0 do
    local placed = false
    for s=1,16 do if not T.inv[s] then local c = math.min(64, n) T.inv[s] = {name=name, count=c} n = n - c placed = true break end end
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
    if T.x == -4462 and T.y == 15 and T.z == 1521 then
      PENDING = nil
      local given = {}
      for _, l in ipairs(m.items) do give(l[1], l[2]) given[l[1]] = l[2] end
      if m.fuel > 0 then give("minecraft:coal", m.fuel) end
      return 3, {type="materials_ready", forId=os.getComputerID(), n=m.n, given=given, missing={}}
    end
    return 3, {type="load_ready", forId=os.getComputerID(), n=m.n}
  end
  while true do coroutine.yield() end
end
''')
# the building, its fit-outs and the Mekanism line
setsp = L.eval("setSpecial")
for (x, y, z) in SHELL:
    if y >= 0: setsp(OX + x, OY + y, OZ + z, "minecraft:polished_deepslate")
for (x, y, z), name in list(FITTED.items()) + list(MEK.items()):
    if "sapling" in name: continue                 # (never planted: no soil on the bay floor)
    setsp(OX + x, OY + y, OZ + z, name)
L.execute('''
OX, OY, OZ = %d, %d, %d
-- the river
for y=60,62 do setSpecial(-4462, y, 1560, "minecraft:water") end
setSpecial(-4462, 59, 1560, "minecraft:stone")
for y=63,120 do setSpecial(-4462, y, 1560, false) end
''' % (OX, OY, OZ))
L.execute(r'''
local D = {[0]={1,0},[1]={0,1},[2]={-1,0},[3]={0,-1}}
local NAMES = {[0]="east", [1]="south", [2]="west", [3]="north"}
local function k(x,y,z) return x..","..y..","..z end
local function front() return T.x + D[T.d][1], T.y, T.z + D[T.d][2] end
STATE = {}          -- block states by cell
COAL_IN = 0 WASHED = 0 MADE = 0 TOSSED_DRY = 0
FLOAT = {}          -- items lying in a cell
WATER_AT = {}
local function isWater(b) return b == "minecraft:water" end
local function open(x,y,z) local b = getBlock(x,y,z) return b == nil end
local function letRun(x,y,z)
  local todo, n = {{x,y,z,0}}, 0
  while #todo > 0 and n < 300 do
    local c = table.remove(todo, 1)
    n = n + 1
    local cx, cy, cz, lv = c[1], c[2], c[3], c[4]
    local ns = {{cx,cy-1,cz,1}, {cx+1,cy,cz,lv+1}, {cx-1,cy,cz,lv+1}, {cx,cy,cz+1,lv+1}, {cx,cy,cz-1,lv+1}}
    for _, q in ipairs(ns) do
      if q[4] <= 7 and open(q[1],q[2],q[3]) and not (q[1]==T.x and q[2]==T.y and q[3]==T.z) then
        setSpecial(q[1],q[2],q[3],"minecraft:water") STATE[k(q[1],q[2],q[3])] = {level=q[4]}
        WATER_AT[k(q[1],q[2],q[3])] = q[4]
        todo[#todo+1] = q
      end
    end
  end
end
local function take(name, n)
  for s=1,16 do local i = T.inv[s] if not i then T.inv[s] = {name=name, count=n} return true end
    if i.name == name and i.count + n <= 64 then i.count = i.count + n return true end end
  LOSTITEMS = (LOSTITEMS or 0) + n
end
local function placeAt(x,y,z)
  local i = T.inv[T.sel]
  if not i then return false, "No items to place" end
  local b = getBlock(x,y,z)
  if i.name == "minecraft:bucket" then
    if isWater(b) and (STATE[k(x,y,z)] or {level=0}).level == 0 then
      i.count = i.count - 1 if i.count == 0 then T.inv[T.sel] = nil end
      take("minecraft:water_bucket", 1) FILLED = (FILLED or 0) + 1 return true
    end
    return false, "Nothing to pick up"
  end
  if b and not isWater(b) then return false, "Cannot place block here" end
  if i.name:find("pickaxe") or i.name:find("coal") and not i.name:find("generator") then return false, "Cannot place item here" end
  if i.name == "minecraft:water_bucket" then
    i.name = "minecraft:bucket"
    setSpecial(x,y,z,"minecraft:water") STATE[k(x,y,z)] = {level=0} WATER_AT[k(x,y,z)] = 0
    letRun(x,y,z)
    return true
  end
  local st = {}
  if i.name == "create:water_wheel" then
    st.facing = (T.d == 0 or T.d == 2) and "east" or "south"
  elseif i.name == "create:encased_fan" then
    -- away from a wheel against it (its shaft side), else as the turtle looks
    local face = NAMES[T.d] == "west" and "east" or NAMES[(T.d + 2) % 4]
    for d = 0, 3 do
      local nx, nz = x + D[d][1], z + D[d][2]
      local w = getBlock(nx, y, nz)
      local ws = STATE[k(nx, y, nz)]
      if w == "create:water_wheel" and ws and ((d % 2 == 0 and ws.facing == "east") or (d % 2 == 1 and ws.facing == "south")) then
        face = NAMES[(d + 2) % 4]
      end
    end
    st.facing = face
  elseif i.name == "actuallyadditions:atomic_reconstructor" then
    st.facing = NAMES[(T.d + 2) % 4]
  end
  setSpecial(x,y,z,i.name) STATE[k(x,y,z)] = st
  i.count = i.count - 1 if i.count == 0 then T.inv[T.sel] = nil end
  PLACED = (PLACED or 0) + 1
  return true
end
turtle.place = function() return placeAt(front()) end
turtle.placeDown = function() return placeAt(T.x, T.y - 1, T.z) end
turtle.placeUp = function() return placeAt(T.x, T.y + 1, T.z) end
-- the reconstructor: sand in front of it turns to soul sand the third time
-- the turtle looks, while a generator against it has had coal
local LOOKS = {}
local function look(x,y,z)
  local b = getBlock(x,y,z)
  if not b then return false, "No block" end
  if b == "minecraft:sand" and COAL_IN > 0 then
    for d = 0, 3 do
      local rx, rz = x - D[d][1], z - D[d][2]
      local rs = STATE[k(rx,y,rz)]
      if getBlock(rx,y,rz) == "actuallyadditions:atomic_reconstructor" and rs.facing == NAMES[d] then
        LOOKS[k(x,y,z)] = (LOOKS[k(x,y,z)] or 0) + 1
        if LOOKS[k(x,y,z)] >= 3 then LOOKS[k(x,y,z)] = nil setSpecial(x,y,z,"minecraft:soul_sand") b = "minecraft:soul_sand" CONVERTED = (CONVERTED or 0) + 1 end
      end
    end
  end
  return true, {name=b, state=STATE[k(x,y,z)] or {}}
end
turtle.inspect = function() return look(front()) end
turtle.inspectDown = function() return look(T.x, T.y-1, T.z) end
turtle.inspectUp = function() return look(T.x, T.y+1, T.z) end
local function digAt(x,y,z)
  local b = getBlock(x,y,z)
  if not b or isWater(b) then return false, "Nothing to dig here" end
  local shovel = b == "minecraft:soul_sand" or b == "minecraft:sand"
  if shovel and TOOL ~= "minecraft:diamond_shovel" then DUG_WRONG = (DUG_WRONG or 0) + 1 return false, "Cannot break block with this tool" end
  if not shovel and TOOL ~= "minecraft:diamond_pickaxe" then DUG_WRONG = (DUG_WRONG or 0) + 1 return false, "Cannot break block with this tool" end
  setSpecial(x,y,z,false) STATE[k(x,y,z)] = nil
  take(b, 1)
  return true
end
turtle.dig = function() return digAt(front()) end
turtle.digDown = function() return digAt(T.x, T.y-1, T.z) end
turtle.digUp = function() return digAt(T.x, T.y+1, T.z) end
-- moving through water leaves it there
for _, n in ipairs({"forward", "up", "down", "back"}) do
  local f = turtle[n]
  turtle[n] = function()
    local x, y, z
    if n == "forward" then x, y, z = front() elseif n == "back" then x, y, z = T.x - D[T.d][1], T.y, T.z - D[T.d][2]
    elseif n == "up" then x, y, z = T.x, T.y + 1, T.z else x, y, z = T.x, T.y - 1, T.z end
    local b = getBlock(x, y, z)
    local r = f()
    if r and isWater(b) then setSpecial(x, y, z, b) end
    return r
  end
end
-- dropping down: into a generator, or into the open (the wash water)
turtle.dropDown = function(n)
  local i = T.inv[T.sel]
  if not i then return false, "No items to drop" end
  n = math.min(n or 64, i.count)
  local x, y, z = T.x, T.y - 1, T.z
  local b = getBlock(x, y, z)
  if b == "actuallyadditions:coal_generator" then
    if i.name ~= "minecraft:coal" then return false, "No space for items" end
    COAL_IN = COAL_IN + n
  elseif b == nil or isWater(b) then
    -- in the wash: the fan must be within 3 west of it, facing east, open between
    local washed = false
    if isWater(b) then
      for d = 1, 3 do
        local f = getBlock(x - d, y, z)
        if f == "create:encased_fan" and STATE[k(x-d,y,z)].facing == "east" then washed = true break end
        if f and not isWater(f) then break end
      end
    end
    FLOAT[k(x,y,z)] = FLOAT[k(x,y,z)] or {}
    if washed and i.name == "minecraft:soul_sand" then
      WASHED = WASHED + n
      local q = 4 * math.floor(n / 8)
      MADE = MADE + q
      if q > 0 then table.insert(FLOAT[k(x,y,z)], {name="minecraft:quartz", count=q}) end
    else
      TOSSED_DRY = TOSSED_DRY + n
      table.insert(FLOAT[k(x,y,z)], {name=i.name, count=n})
    end
  else
    return false, "No space for items"
  end
  i.count = i.count - n if i.count == 0 then T.inv[T.sel] = nil end
  return true
end
turtle.suckDown = function(n)
  local f = FLOAT[k(T.x, T.y-1, T.z)]
  local it = f and table.remove(f, 1)
  if not it then return false, "No items to take" end
  take(it.name, it.count)
  return true
end
turtle.detectDown = function() local b = getBlock(T.x, T.y-1, T.z) return b ~= nil and not isWater(b) end
turtle.detect = function() local b = getBlock(front()) return b ~= nil and not isWater(b) end
-- tools: the pickaxe (or what is swapped in for it) on the left, the modem on the right
TOOL = "minecraft:diamond_pickaxe"
local CLICKS = 0
AUTO = { useOnBlock = function()
  local i = T.inv[T.sel]
  local x, y, z = front()
  local b = getBlock(x, y, z)
  if i and i.name == "minecraft:diamond_axe" and b and b:find("_log") and not b:find("stripped") then
    setSpecial(x, y, z, b:gsub(":", ":stripped_", 1)) return true end
  if i and i.name == "create:andesite_alloy" and b and b:find("stripped_") and b:find("_log") then
    setSpecial(x, y, z, "create:andesite_casing") i.count = i.count - 1 if i.count == 0 then T.inv[T.sel] = nil end return true end
  return nil, "nothing happened" end }
peripheral.getType = function(side)
  if side == "right" then return "modem" end
  if side == "left" and TOOL == "advancedperipherals:weak_automata_core" then return "weakAutomata" end
  return nil end
peripheral.wrap = function(side) if side == "left" and TOOL == "advancedperipherals:weak_automata_core" then return AUTO end end
''')

g = L.globals()
fresh = True
def lab(ops):
    global fresh
    L.globals().OPS = ";".join(ops)
    if fresh:
        L.execute('''
        T.x, T.y, T.z = -4462, 15, 1521
        T.inv = {} T.inv[1] = {name="minecraft:coal", count=16}
        FS["helper.state"] = textutils.serialize({ done = true, lab = { ops = OPS } })
        FS[".version"] = "abc123"
        ''')
        fresh = False
    else:
        L.execute('''
        local st = textutils.unserialize(FS["helper.state"])
        st.lab = { ops = OPS } st.labOut = {}
        FS["helper.state"] = textutils.serialize(st)
        ''')
    f = L.eval('loadfile("%s/helper.lua")' % ROOT)
    r = L.eval('function(f) return {pcall(f)} end')(f)
    st = L.eval('textutils.unserialize(FS["helper.state"])')
    out = list(st.labOut.values())
    return list(r.values()), out

def inv():
    c = Counter()
    for it in g.T.inv.values(): c[it.name] += it.count
    return c

def world(p):
    return L.eval("getBlock")(OX + p[0], OY + p[1], OZ + p[2])

def state(p, key):
    s = L.eval('function(x,y,z) local s = STATE[x..","..y..","..z] return s and s.%s end' % key)
    return s(OX + p[0], OY + p[1], OZ + p[2])

side = Q.opts(["side=left"])
for name, ops in (("casing", Q.casing(side)), ("build", Q.build(side)), ("run 8", Q.run(8, side))):
    r, out = lab(ops)
    print("== %s: %s | at %d %d %d | %d steps" % (name, r, g.T.x, g.T.y, g.T.z, len(ops)))
    for line in out[-6:]: print("   ", line)
    check("%s: every step done (none stopped)" % name, not any("stopped here" in l for l in out)
          and any(("%d handin|" % len(ops)) in l for l in out))
    if name == "casing":
        check("casing: an andesite casing came back to the factory, and the log was stripped first",
              any("expect|front|stripped_oak_log: minecraft:stripped_oak_log" in l for l in out)
              and any("dig: create:andesite_casing taken" in l for l in out))
    if name == "build":
        placed = {p: world(p) for p in Q.cells()}
        check("build: everything stands where the layout says",
              all(world(p) == item for p, item in Q.cells().items()))
        check("build: wheel, fan and reconstructor face as the steps expect",
              state(Q.WHEEL_AT, "facing") == "east" and state(Q.FAN_AT, "facing") == "east"
              and state(Q.RECON_AT, "facing") == "east")
        wet = set()
        for kk in L.eval("WATER_AT").keys():
            x, y, z = map(int, kk.split(","))
            wet.add((x - OX, y - OY, z - OZ))
        check("build: the water stayed in its four cells: %s" % sorted(wet), wet == Q.WATER_CELLS)
        check("build: two buckets filled at the river", g.FILLED == 2)
        check("build: coal went into the generators", g.COAL_IN == 2 * Q.build_coal())
    if name == "run 8":
        c = inv()
        check("run: 8 sand turned to soul sand in front of the reconstructor", g.CONVERTED == 8)
        check("run: dug with the shovel only (the pickaxe never tried soul sand)", not g.DUG_WRONG)
        check("run: all 8 went into the wash water, inside the fan's reach", g.WASHED == 8 and g.TOSSED_DRY == 0)
        check("run: the quartz was taken up and handed in (none left on board)",
              g.MADE == 4 and c["minecraft:quartz"] == 0 and c["minecraft:soul_sand"] == 0)
        check("run: the pickaxe is back on", g.TOOL == "minecraft:diamond_pickaxe")
        check("run: coal for both generators", g.COAL_IN == 2 * Q.build_coal() + Q.run_coal(8))

orders = [[(l[1], l[2]) for l in o["items"].values()] for o in g.ORDERS.values()]
print("asked the factory for:", orders)
check("nothing went missing from the turtle's slots", not g.LOSTITEMS)
print("PASS" if not fails else "FAILED: %d" % len(fails))
sys.exit(1 if fails else 0)
