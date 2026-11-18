"""The certus farm and the AE2 bench (tools/certusfarm.py), on paper and in a
simulated world.

1. On paper: no two budding slots share a cell to grow into; the drone never
   stands or moves in a cell next to a budding block (so nothing grows where
   it is); every cell a budding block grows into has a stand beside it; the
   farm fits docs/foundry-v2.md's certus zone (x 28-34, z 6-13; approach from
   the north walkway, z 5) and is clear of the building and its fit-outs
   (the Mekanism line's planned pool and gas plants there are dropped in v2).
2. In a simulated world: the real helper runs the bench, harvest and fluix
   steps. Every face of every budding block holds a full-grown cluster except
   a few still-growing buds; the harvest must take every cluster (4 crystals
   each), leave every bud and never break a budding block. The charger
   charges what is dropped in; the basin turns charged certus + redstone +
   nether quartz into 2 fluix.

    cd test && python3 certusfarm.py
"""
import os, sys
from collections import Counter
import lupa

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "tools"))
import certusfarm as CF

fails = []
def check(what, ok):
    print(("ok   " if ok else "FAIL ") + what)
    if not ok: fails.append(what)

N6 = ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1))
def nb(p): return [(p[0] + d[0], p[1] + d[1], p[2] + d[2]) for d in N6]

F = CF.Farm()
slots = [F.slot_cell(i, t, s) for _, i, t, s in F.slots()]
grow = CF.grow_cells(F)
cells = CF.cells(F)

# ---------------------------------------------------------------- on paper
allgrow = []
for _, i, t, s in F.slots():
    allgrow += list(F.clusters(i, t, s).values())
check("no two budding slots share a growth cell", len(allgrow) == len(set(allgrow)))
check("every open face of every slot is a growth cell (the back is the pillar, the floor under tier 1)",
      all(all(n in grow or n in cells or n[1] == F.o[1] - 1 for n in nb(p)) for p in slots))
check("the pillar backs every slot", all(any(n in F.pillars() for n in nb(p)) for p in slots))

# the drone's path, followed op by op from the harvest's start
DIRV = {0: (1, 0), 1: (0, 1), 2: (-1, 0), 3: (0, -1)}
def follow(ops):
    pos, d, path, picks, bad = None, 0, [], [], []
    for op in ops:
        a = op.split("|")
        v = a[0]
        if v == "walk":
            pos = tuple(map(int, a[1:4])); path.append(pos)
        elif v == "face":
            d = int(a[1])
        elif v in ("fwd", "back", "up", "down"):
            n = int(a[1])
            for _ in range(n):
                if v == "fwd": pos = (pos[0] + DIRV[d][0], pos[1], pos[2] + DIRV[d][1])
                elif v == "back": pos = (pos[0] - DIRV[d][0], pos[1], pos[2] - DIRV[d][1])
                elif v == "up": pos = (pos[0], pos[1] + 1, pos[2])
                else: pos = (pos[0], pos[1] - 1, pos[2])
                path.append(pos)
        elif v.startswith("pick"):
            if v == "pick": tgt = (pos[0] + DIRV[d][0], pos[1], pos[2] + DIRV[d][1])
            elif v == "pickUp": tgt = (pos[0], pos[1] + 1, pos[2])
            else: tgt = (pos[0], pos[1] - 1, pos[2])
            picks.append(tgt)
    return path, picks

ops = CF.harvest(F, CF.opts([]))
path, picks = follow(ops)
inside = [p for p in path if p != path[0]]
check("the drone never enters a growth cell, a slot, a pillar or the basin",
      not [p for p in inside if p in grow or p in cells])
check("the drone never stands next to a budding slot (nothing grows where it is)",
      not [p for p in inside if any(n in slots for n in nb(p))])
check("every growth cell of every slot is picked from a stand beside it",
      set(grow) <= set(picks))
check("nothing else is picked (no slot, pillar or wall)", set(picks) <= set(grow))
x0, x1, y0, y1, z0, z1 = F.box()
check("the farm stays in the v2 certus zone (x 28-34, z 5-13: the walkway at z 5 is the way in)",
      28 <= x0 and x1 <= 34 and z0 >= 5 and z1 <= 13 and all(28 <= p[0] <= 34 and 5 <= p[2] <= 13 for p in path))

import retrofit as R
B = R.model()
MEKS = set()
import mekline
for c in mekline.upto(5):
    MEKS.add(c)
fpath, _ = follow(CF.fluix(F, CF.opts([]), 8))
bench = CF.bench_of(CF.opts([]))
used = set(cells) | set(grow) | set(path) | set(fpath[1:]) | set(bench.values()) | {CF.above(c) for c in bench.values()}
clash = {p: B[p] for p in used if p in B and p not in MEKS and not (p == F.basin()[0])}
dropped = sorted(p for p in used if p in MEKS)
print("    (planned Mekanism cells v2 drops, in the farm's way:", dropped, ")")
check("farm, basin stand and v2 bench clear of the building and its fit-outs: %s" % clash, not clash)
check("the basin is dug in the floor", "deepslate" in B.get(F.basin()[0], ""))

# ---------------------------------------------------------------- the world
OX, OY, OZ = CF.OX, CF.OY, CF.OZ
L = lupa.LuaRuntime(unpack_returned_tuples=True)
L.execute("START_D=3; START_FUEL=6000")
os.chdir(HERE)
L.execute(open("harness.lua").read())
L.execute(open("bworld.lua").read())
files = {n: open(os.path.join(ROOT, "blueprints", n + ".txt")).read() for n in ("factory_asfit3", "factory_foundryfloor")}
L.globals().PLANFILES = L.table_from(files)
L.execute('''
package.preload.swarm = function() return {
  open = function() return true end, report = function() end,
  runWithCommands = function(task) task() return nil end, pinVersion = function() end } end
http = { get = function(url)
  for name, text in pairs(PLANFILES) do
    if url:find(name, 1, true) then return { readAll = function() return text end, close = function() end } end
  end end }
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
    if not PENDING or PENDING.n ~= m.n then end
    PENDING = m
    return
  end
  if m.type == "map" then return end
  return hb(m, p)
end
HANDED = {}
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
setsp = L.eval("setSpecial")
for (x, y, z), name in B.items():
    if y < 0 or (x, y, z) in MEKS: continue
    setsp(OX + x, OY + y, OZ + z, name)
# the farm as Kyle builds it, the basin, and every face grown
for p, it in cells.items():
    if it.startswith("("): continue
    setsp(OX + p[0], OY + p[1], OZ + p[2], it)
filled = {F.slot_cell(i, t, s) for _, i, t, s in F.filled()}
growing = set()
for k, (p, (idx, face)) in enumerate(sorted(grow.items())):
    if idx >= F.fill:
        continue
    bud = k % 7 == 3
    setsp(OX + p[0], OY + p[1], OZ + p[2], "ae2:large_quartz_bud" if bud else "ae2:quartz_cluster")
    if bud: growing.add(p)
L.execute(r'''
local D = {[0]={1,0},[1]={0,1},[2]={-1,0},[3]={0,-1}}
local function k(x,y,z) return x..","..y..","..z end
local function front() return T.x + D[T.d][1], T.y, T.z + D[T.d][2] end
FLOAT = {} CHARGER = {} BROKE = {} PICKED = 0 MADE_FLUIX = 0
local function take(name, n)
  for s=1,16 do local i = T.inv[s] if not i then T.inv[s] = {name=name, count=n} return true end
    if i.name == name and i.count + n <= 64 then i.count = i.count + n return true end end
  LOSTITEMS = (LOSTITEMS or 0) + n
end
local function placeAt(x,y,z)
  local i = T.inv[T.sel]
  if not i then return false, "No items to place" end
  if getBlock(x,y,z) then return false, "Cannot place block here" end
  if i.name:find("pickaxe") or i.name:find("coal") then return false, "Cannot place item here" end
  setSpecial(x,y,z,i.name)
  i.count = i.count - 1 if i.count == 0 then T.inv[T.sel] = nil end
  return true
end
turtle.place = function() return placeAt(front()) end
turtle.placeDown = function() return placeAt(T.x, T.y - 1, T.z) end
local function look(x,y,z) local b = getBlock(x,y,z) if not b then return false, "No block" end return true, {name=b, state={}} end
turtle.inspect = function() return look(front()) end
turtle.inspectDown = function() return look(T.x, T.y-1, T.z) end
turtle.inspectUp = function() return look(T.x, T.y+1, T.z) end
local function digAt(x,y,z)
  local b = getBlock(x,y,z)
  if not b or b == "minecraft:water" then return false, "Nothing to dig here" end
  if b:find("budding") then BROKE[#BROKE+1] = k(x,y,z) end
  setSpecial(x,y,z,false)
  if b == "ae2:quartz_cluster" then take("ae2:certus_quartz_crystal", 4) PICKED = PICKED + 1
  elseif b:find("_bud") then take("ae2:certus_quartz_dust", 1)
  else take(b, 1) end
  return true
end
turtle.dig = function() return digAt(front()) end
turtle.digDown = function() return digAt(T.x, T.y-1, T.z) end
turtle.digUp = function() return digAt(T.x, T.y+1, T.z) end
-- into the charger (one at a time; charged when taken out), the inscribers, or the basin
turtle.dropDown = function(n)
  local i = T.inv[T.sel]
  if not i then return false, "No items to drop" end
  n = math.min(n or 64, i.count)
  local x, y, z = T.x, T.y - 1, T.z
  local b = getBlock(x, y, z)
  if b == "ae2:charger" then
    if CHARGER[k(x,y,z)] or i.name ~= "ae2:certus_quartz_crystal" then return false, "No space for items" end
    n = 1 CHARGER[k(x,y,z)] = "ae2:charged_certus_quartz_crystal"
  elseif b == "ae2:inscriber" then
    INSCRIBED = (INSCRIBED or 0) + n
  elseif b == nil or b == "minecraft:water" then
    FLOAT[k(x,y,z)] = FLOAT[k(x,y,z)] or {}
    table.insert(FLOAT[k(x,y,z)], {name=i.name, count=n})
    if b == "minecraft:water" then
      local have = {}
      for _, it in ipairs(FLOAT[k(x,y,z)]) do have[it.name] = (have[it.name] or 0) + it.count end
      local sets = math.min(have["ae2:charged_certus_quartz_crystal"] or 0, have["minecraft:redstone"] or 0, have["minecraft:quartz"] or 0)
      if sets > 0 then
        local left = {}
        for _, nm in ipairs({"ae2:charged_certus_quartz_crystal", "minecraft:redstone", "minecraft:quartz"}) do have[nm] = have[nm] - sets end
        for nm, c in pairs(have) do if c > 0 then left[#left+1] = {name=nm, count=c} end end
        left[#left+1] = {name="ae2:fluix_crystal", count=2 * sets}
        MADE_FLUIX = MADE_FLUIX + 2 * sets
        FLOAT[k(x,y,z)] = left
      end
    end
  else
    return false, "No space for items"
  end
  i.count = i.count - n if i.count == 0 then T.inv[T.sel] = nil end
  return true
end
turtle.suckDown = function(n)
  local x, y, z = T.x, T.y - 1, T.z
  if getBlock(x,y,z) == "ae2:charger" then
    local c = CHARGER[k(x,y,z)]
    if not c then return false, "No items to take" end
    CHARGER[k(x,y,z)] = nil take(c, 1) CHARGED = (CHARGED or 0) + 1 return true
  end
  local f = FLOAT[k(x, y, z)]
  local it = f and table.remove(f, 1)
  if not it then return false, "No items to take" end
  take(it.name, it.count)
  return true
end
turtle.detectDown = function() local b = getBlock(T.x, T.y-1, T.z) return b ~= nil and b ~= "minecraft:water" end
turtle.detect = function() local b = getBlock(front()) return b ~= nil and b ~= "minecraft:water" end
TOOL = "minecraft:diamond_pickaxe"
peripheral.getType = function(side) if side == "right" then return "modem" end return nil end
''')
g = L.globals()
fresh = True
def lab(ops):
    global fresh
    g.OPS = ";".join(ops)
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
    return list(r.values()), list(st.labOut.values())

def world(p):
    return L.eval("getBlock")(OX + p[0], OY + p[1], OZ + p[2])

def done(name, ops, out):
    ok = not any("stopped here" in l for l in out) and any(("%d handin|" % len(ops)) in l for l in out)
    if not ok:
        for line in out[-8:]: print("   ", line)
    check("%s: every step done (none stopped)" % name, ok)

o = CF.opts([])
ops = CF.bench_build(F, o)
r, out = lab(ops)
done("bench", ops, out)
B6 = CF.bench_of(o)
check("bench: the charger and five inscribers stand on their cells",
      world(B6["charger"]) == "ae2:charger" and all(world(B6[n]) == "ae2:inscriber" for n in ("silicon", "logic", "calc", "eng", "mill")))

ops = CF.first(F, o)
r, out = lab(ops)
done("first harvest and fluix", ops, out)
want = sum(1 for p, (idx, _) in grow.items() if idx < F.fill and p not in growing)
check("harvest: every full-grown cluster picked (%d of %d)" % (g.PICKED, want), g.PICKED == want)
check("harvest: every bud left to grow", all(world(p) == "ae2:large_quartz_bud" for p in growing))
check("harvest: no budding block broken", len(list(g.BROKE.values())) == 0 and all(world(p) == CF.BUD for p in filled))
check("fluix: 8 charged in the charger, 16 fluix out of the basin", g.CHARGED == 8 and g.MADE_FLUIX == 16)
check("nothing lost (the drone's slots were enough)", not g.LOSTITEMS)
print("PASS" if not fails else "FAILED: %d" % len(fails))
sys.exit(1 if fails else 0)
