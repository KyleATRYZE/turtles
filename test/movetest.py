"""The base move (docs/factory-retrofit.md): the code that lets Crafty and its
pads move into the factory, each piece inert until the move.

1. The pad split: loads go to Crafty, Counter, Counter2 by id % (N + 1),
   Crafty takes the share of a counter gone quiet; one Counter = odd ids.
2. Crafty's stores: the store's In and Out barrels, a manager and named
   skips are not storage; the storage room's controllers are put away into
   first.
3. The factory answers "base_request"; the plot grid stays where it was
   first laid out (plots.origin), and jobs carry it.
4. The rebase order (swarm.lua): a drone asks, keeps the new base with the
   heights the order gives, brings a miner's and a builder's saved base
   cells up to date; a machine with no .base takes no notice.
5. Heights: helpers hover base.hoverUp above Crafty (12 without), loaders
   hop base.hopUp (14 without); miners keep the plot grid's origin.
6. Sortnado's drain: old chests on the cable emptied into the store, the
   fullest first; the store's own containers are never drained.

    cd test && python3 movetest.py
"""
import os, re, lupa
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(HERE)
fails = []
def check(what, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + what + (" | " + str(detail) if detail != "" else ""))
    if not ok: fails.append(what)

FAC = open(os.path.join(ROOT, "factory.lua")).read()

# ---------------------------------------------------------------- 1. the pad split
split = FAC[FAC.index("do\n  local digits"):FAC.index("return share == 0 or not K.alive(share)\nend") + len("return share == 0 or not K.alive(share)\nend")]
def dispenser(label):
    L = lupa.LuaRuntime(unpack_returned_tuples=True)
    L.execute("CLOCK = 1000 os.clock = function() return CLOCK end K = {} LABEL = %r os.getComputerLabel = function() return LABEL end" % label)
    L.execute(split)
    return L
def mine(L, heard, ids=range(20, 32)):
    L.execute("K.counters = {}")
    for slot, ago in heard.items():
        L.execute("K.counters[%d] = CLOCK - %d" % (slot, ago))
    return [i for i in ids if L.eval("K.mine(%d)" % i)]
crafty, c1, c2 = dispenser("Crafty"), dispenser("Counter"), dispenser("Counter2")
check("labels: Crafty is no counter, Counter is 1, Counter2 is 2",
      crafty.eval("K.COUNTER") is False and c1.eval("K.SLOT") == 1 and c2.eval("K.SLOT") == 2)
check("no counter heard: Crafty serves everybody", mine(crafty, {}) == list(range(20, 32)))
check("one Counter: Crafty the even ids, Counter the odd (as before)",
      mine(crafty, {1: 10}) == list(range(20, 32, 2)) and mine(c1, {}) == list(range(21, 32, 2)))
three = {k: [i for i in range(20, 32) if i % 3 == k] for k in range(3)}
check("Counter and Counter2: id % 3, each its own share",
      mine(crafty, {1: 10, 2: 10}) == three[0] and mine(c1, {2: 10}) == three[1] and mine(c2, {1: 10}) == three[2])
check("Counter2 quiet for 150 s: back to two shares", mine(crafty, {1: 10, 2: 200}) == list(range(20, 32, 2))
      and mine(c1, {2: 200}) == list(range(21, 32, 2)))
check("Counter quiet, Counter2 alive: Crafty takes Counter's share as well",
      mine(crafty, {1: 200, 2: 10}) == sorted(three[0] + three[1]) and mine(c2, {1: 200}) == three[2])
check("every load has exactly one dispenser",
      sorted(mine(crafty, {1: 10, 2: 10}) + mine(c1, {2: 10}) + mine(c2, {1: 10})) == list(range(20, 32)))
check("an old Counter says alive with no number: taken as Counter",
      'K.counters[math.floor(tonumber(msg.slot) or 1)]' in FAC)

# ---------------------------------------------------------------- 2. Crafty's stores
ns = FAC[FAC.index("function K.notStore(name)"):FAC.index("local function discover()")]
L = lupa.LuaRuntime(unpack_returned_tuples=True)
L.execute("K = {} plots = {} TYPES = {['inventoryManager_0'] = 'inventoryManager'} "
          "peripheral = { hasType = function(n, t) return TYPES[n] == t end }")
L.execute(ns)
ok = lambda n: L.eval("K.notStore(%r)" % n)
check("the store's barrels and a manager are not storage, chests and controllers are",
      ok("minecraft:barrel_3") and ok("inventoryManager_0") and not ok("minecraft:chest_4")
      and not ok("sophisticatedstorage:controller_0"))
L.execute("plots.stores = { skip = { 'minecraft:chest_40', 'mekanism:*' } }")
check("names and name* the order gives are skipped", ok("minecraft:chest_40") and ok("mekanism:enrichment_chamber_2")
      and not ok("minecraft:chest_41"))
sortfn = re.search(r"table\.sort\(stores, (function\(a, b\).*?end)\)\n", FAC, re.S).group(1)
order = L.eval("function(t) table.sort(t, %s) return t end" % sortfn)(L.table("minecraft:chest_1", "sophisticatedstorage:controller_2", "minecraft:chest_0", "sophisticatedstorage:controller_1"))
check("controllers first (put away there), then the rest by name",
      list(order.values()) == ["sophisticatedstorage:controller_1", "sophisticatedstorage:controller_2", "minecraft:chest_0", "minecraft:chest_1"])

# ---------------------------------------------------------------- 3. the factory: base_request, the plot grid
HARNESS = open(os.path.join(HERE, "fharness.lua")).read().replace("/home/claude/turtles", ROOT)
def factory(plots, inbox, base=None):
    L = lupa.LuaRuntime(unpack_returned_tuples=True); L.execute("MODEM_ON=true"); L.execute(HARNESS)
    L.execute('put("minecraft:chest_0","minecraft:coal",64) put("minecraft:chest_0","minecraft:coal",64)')
    L.execute("FILES['.plots'] = %r" % plots)
    if base:
        L.execute("FILES['.base'] = %r" % base)
    L.execute("MAX_IDLES=1"); L.eval("{runFactory()}")
    L.execute("IDLES=0 MAX_IDLES=3 INBOX = {%s}" % inbox)
    L.eval("{runFactory()}")
    return L, L.globals()
# the harness's factory stands at 100 64 200; its base as surveyed
L, g = factory('{["next"]=1,["done"]=0,["byId"]={["9"]=1},["helpers"]={},["loaders"]={}}',
               '{id=31,msg={type="base_request"}}')
replies = [m for m in g.OUTBOX.values() if m.msg.type == "base"]
check("the factory answers base_request with its base", len(replies) == 1 and replies[0].to == 31
      and replies[0].msg.base.f.x == 100 and replies[0].msg.base.pad is not None)
check("the plot grid's origin is written down at Crafty's spot", '["origin"]=' in g.FILES[".plots"]
      and L.eval('textutils.unserialize(FILES[".plots"]).origin.x') == 100)
# a factory that has moved (its base 33 east, 3 south), with the old origin kept
moved = '{f={x=133,y=64,z=203},pad={x=133,y=64,z=202},padTurns=3,dock={x=133,y=65,z=204},exit1={x=133,y=65,z=203},exit2={x=133,y=65,z=202}}'
def job_for(origin):
    plots = '{["next"]=1,["done"]=0,["byId"]={["9"]=1},["helpers"]={},["loaders"]={}%s}' % (
        (',["origin"]={x=100,y=64,z=200}') if origin else "")
    L, g = factory(plots, '{id=9,msg={type="need_job",id=9}}', base=moved)
    jobs = [m.msg for m in g.OUTBOX.values() if m.msg.type == "job"]
    return jobs[0] if jobs else None
j_old, j_new = job_for(True), job_for(False)
check("moved, with the origin kept: plot 1 is where it always was", j_old is not None and j_old.origin.x == 100
      and (j_old.x0 - 100) % 8 == 0 and (j_old.z0 - 200) % 8 == 0, j_old and (j_old.x0, j_old.z0))
check("(without it the grid would have moved with Crafty)", j_new is not None and (j_new.x0 - 133) % 8 == 0 and (j_new.x0 - 100) % 8 != 0)

# ---------------------------------------------------------------- 4. the rebase order
ENV = r'''
CLOCK = 5
os.clock = function() CLOCK = CLOCK + 1 return CLOCK end
os.epoch = function() return 1700000000000 end
os.getComputerID = function() return 17 end
os.getComputerLabel = function() return LABEL end
os.setComputerLabel = function(l) LABEL = l end
FS = {}
fs = { exists = function(f) return FS[f] ~= nil end, delete = function(f) FS[f] = nil end,
  open = function(f, mode)
    if mode == "w" then local buf = {} return { write = function(s) buf[#buf + 1] = s end, close = function() FS[f] = table.concat(buf) end } end
    return { readAll = function() return FS[f] end, close = function() end } end }
local function ser(v)
  if type(v) == "table" then local parts = {}
    for k, val in pairs(v) do parts[#parts + 1] = "[" .. (type(k) == "string" and string.format("%q", k) or tostring(k)) .. "]=" .. ser(val) end
    return "{" .. table.concat(parts, ",") .. "}"
  elseif type(v) == "string" then return string.format("%q", v) else return tostring(v) end
end
textutils = { serialize = ser, unserialize = function(s) local f = load("return " .. s) return f and f() end }
local ender = { isWireless = function() return true end }
peripheral = { find = function(t, f) if f("right", ender) then return ender end end, getName = function() return "right" end, getType = function() return nil end }
SENT = {}
rednet = { open = function() end, broadcast = function(m, p) SENT[#SENT + 1] = m end,
  receive = function(p, t) if ANSWER and #SENT > 0 then return 7, ANSWER end return nil end }
print = function() end
NEW = { f = { x = -4428, y = 72, z = 1525 }, pad = { x = -4428, y = 72, z = 1524 }, padTurns = 2,
  dock = { x = -4428, y = 73, z = 1526 }, exit1 = { x = -4428, y = 73, z = 1525 }, exit2 = { x = -4428, y = 73, z = 1524 } }
OLD = { f = { x = -4461, y = 72, z = 1521 }, pad = { x = -4462, y = 72, z = 1521 },
  dock = { x = -4460, y = 73, z = 1521 }, exit1 = { x = -4461, y = 73, z = 1521 }, exit2 = { x = -4462, y = 73, z = 1521 } }
'''
def swarm(setup):
    L = lupa.LuaRuntime(unpack_returned_tuples=True); L.execute(ENV); L.execute(setup)
    L.execute('swarm = dofile("%s/swarm.lua")' % ROOT)
    return L, L.globals()
L, g = swarm('''LABEL = "Pushy" FS[".base"] = textutils.serialize(OLD)
FS["miner.state"] = textutils.serialize({ dock = OLD.dock, exit1 = OLD.exit1, exit2 = OLD.exit2, size = 8, home = { x = 1, y = 50, z = 2 } })
FS["builder.state"] = textutils.serialize({ roomCells = { "a" }, padKey = "k", door = { x = 1, y = 2, z = 3 }, job = { plan = "p" } })
ANSWER = { type = "base", base = NEW }''')
r = L.eval('{swarm.rebase({ cmd = "rebase", hover = 20, hop = "22", door = "-4426,72,1549" }, 1)}')
b = L.eval('textutils.unserialize(FS[".base"])')
check("rebase: the new base kept, with the order's heights and door", r[1] is True and b.f.x == -4428 and b.pad.z == 1524
      and b.hoverUp == 20 and b.hopUp == 22 and b.door.z == 1549, r)
check("it asked the factory", any(m.type == "base_request" for m in g.SENT.values()))
check("no lane=1 in the order: no drone lane (the helpers hover as before)", b.lane is None)
L.eval('swarm.rebase({ cmd = "rebase", lane = "1" }, 1)')
b = L.eval('textutils.unserialize(FS[".base"])')
check("lane=1: the drone lane in .base (gates, tracks, the rack)", b.lane is not None and b.lane.y == 73
      and b.lane.back == 1519 and b.lane.front == 1520 and b.lane.rackX == -4429 and b.lane.eastIn.x == -4402)
L.eval('swarm.rebase({ cmd = "rebase" }, 1)')
check("  kept by a later rebase without lane=", L.eval('textutils.unserialize(FS[".base"]).lane') is not None)
L.eval('swarm.rebase({ cmd = "rebase", lane = "0" }, 1)')
check("  and dropped by lane=0", L.eval('textutils.unserialize(FS[".base"]).lane') is None)
L.eval('swarm.rebase({ cmd = "rebase", hover = 20, hop = "22", door = "-4426,72,1549" }, 1)')
m = L.eval('textutils.unserialize(FS["miner.state"])')
check("a miner's saved dock and exits follow; its grid keeps the old exit1 as origin; the plot stays",
      m.dock.z == 1526 and m.exit2.x == -4428 and m.origin.x == -4461 and m.home.y == 50 and m.size == 8)
bs = L.eval('textutils.unserialize(FS["builder.state"])')
check("the builder forgets the old room's map and way in, keeps its job", bs.roomCells is None and bs.padKey is None
      and bs.door is None and bs.job.plan == "p")
L, g = swarm('''LABEL = "Pushy" FS[".base"] = textutils.serialize(OLD) ANSWER = nil''')
r = L.eval('{swarm.rebase({ cmd = "rebase" }, 1)}')
check("no answer from the factory: .base untouched", r[1] is False and L.eval('textutils.unserialize(FS[".base"]).f.x') == -4461)
L, g = swarm('''LABEL = "Sortnado" ANSWER = { type = "base", base = NEW }''')
r = L.eval('{swarm.rebase({ cmd = "rebase" }, 1)}')
check("a machine with no .base takes no notice", r[1] is False and not g.FS[".base"] and not list(g.SENT.values()))
L, g = swarm('''LABEL = "Pushy" FS[".base"] = textutils.serialize(OLD) OLD.hoverUp = nil ANSWER = { type = "base", base = NEW }''')
L.eval('swarm.rebase({ cmd = "rebase" }, 1)')
check("without heights in the order there are none (the old ones stay as they were)",
      L.eval('textutils.unserialize(FS[".base"]).hoverUp') is None)
check("the factory and the counters ignore the order (they know where they are)",
      'elseif c.cmd == "rebase" then          -- (for the drones' in FAC)

# ---------------------------------------------------------------- 5. heights
HEL = open(os.path.join(ROOT, "helper.lua")).read()
LOA = open(os.path.join(ROOT, "loader.lua")).read()
MIN = open(os.path.join(ROOT, "miner.lua")).read()
hov = HEL[HEL.index("local function hoverAir()"):HEL.index("---------------------------------------------------------------- the drone lane")]
L = lupa.LuaRuntime(unpack_returned_tuples=True)
L.execute("function slot() return 3 end " + hov.replace("local function hoverAir", "function hover"))
L.execute("base = { f = { y = 72 }, exit2 = { x = -4428, z = 1524 } }")
before = L.eval("{hover()}")
L.execute("base.hoverUp = 20")
after = L.eval("{hover()}")
check("helpers hover 12 above Crafty as before, 20 after a rebase with hover=20",
      before[2] == 84 and after[2] == 92 and after[1] == -4419 and after[3] == 1520, (before, after))
hop = LOA[LOA.index("local function hopUp()"):LOA.index("local function hopHeight()")]
L = lupa.LuaRuntime(unpack_returned_tuples=True)
L.execute("HOP_UP = 14 " + hop.replace("local function hopUp", "function hopUp"))
L.execute("base = {}")
a = L.eval("hopUp()"); L.execute("base.hopUp = 22"); b2 = L.eval("hopUp()")
check("loaders hop 14 up as before, 22 after a rebase with hop=22", a == 14 and b2 == 22)
check("on the drone lane loaders do not hop onto the pad indoors for fuel: they ask for a feed",
      "base.pad.z >= L.back and base.pad.z <= L.front" in LOA[LOA.index("local function fuelUp"):LOA.index("local function fuelUp") + 600])
check("loaders use it for both short hops", LOA.count("hopUp()") >= 3 and "+ HOP_UP" not in LOA.replace("local HOP_UP", ""))
check("miners take the origin from the job and use it for the plot grid", "origin = j.origin" in MIN
      and "local o = st.origin or st.exit1" in MIN)

# ---------------------------------------------------------------- 6. the drain
src = open(os.path.join(HERE, "sortctl.py")).read()
WORLD = re.search(r"WORLD = '''(.*?)'''", src, re.S).group(1)
L = lupa.LuaRuntime(unpack_returned_tuples=True)
L.execute("ROOT = %r" % ROOT)
L.execute(WORLD)
L.execute('''
fresh({ slots = 600, sides = {} })
INV["minecraft:chest_8"] = { size = 27, cap = 64, slots = {} }
INV["minecraft:chest_9"] = { size = 27, cap = 64, slots = {} }
addTo("minecraft:chest_7", "minecraft:cobblestone", 100)
addTo("minecraft:chest_8", "minecraft:raw_iron", 600) addTo("minecraft:chest_8", "minecraft:diamond", 5)
addTo(IN, "minecraft:dirt", 3) addTo(OUT, "minecraft:stick", 2)
CFG = { inbox = IN, outbox = OUT }
S.cfg(CFG)
CFG.drain = S.drainList("minecraft:chest_*,minecraft:barrel_*,sophisticatedstorage:controller_0")
NAMES = {} for i, n in ipairs(CFG.drain) do NAMES[i] = n end
for i = 1, 40 do S.drainStep() end
''')
names = list(g2 for g2 in L.eval("NAMES").values())
check("the drain list: the old chests, fullest first; never the In/Out barrels or the store",
      names == ["minecraft:chest_8", "minecraft:chest_7", "minecraft:chest_9"], names)
t = lambda n, item=None: L.eval("total(%r%s)" % (n, ", %r" % item if item else ""))
check("drained: the chests are empty, it is all in the store",
      t("minecraft:chest_7") == 0 and t("minecraft:chest_8") == 0 and t("sophisticatedstorage:controller_0", "minecraft:raw_iron") == 600
      and t("sophisticatedstorage:controller_0", "minecraft:cobblestone") == 100 and t("sophisticatedstorage:controller_0", "minecraft:diamond") == 5)
check("the list is done and counted; the Out barrel left alone",
      L.eval("CFG.drain") is None and L.eval("CFG.drained") == 3 and t("minecraft:barrel_1", "minecraft:stick") == 2)
L.execute('''
fresh({ slots = 1, sides = {} })
addTo(CTL, "minecraft:stone", 512)
INV["minecraft:chest_8"] = { size = 27, cap = 64, slots = {} }
addTo("minecraft:chest_8", "minecraft:raw_gold", 64)
CFG = { inbox = IN, outbox = OUT } S.cfg(CFG)
CFG.drain = S.drainList("minecraft:chest_8")
S.drainStep() S.drainStep()
''')
check("the store full: the chest stays on the list, and it waits", L.eval("CFG.drain and CFG.drain[1]") == "minecraft:chest_8"
      and t("minecraft:chest_8") == 64 and "full" in str(L.eval("S.drainNote")), L.eval("S.drainNote"))

print("PASS" if not fails else "FAILED: %d" % len(fails))
