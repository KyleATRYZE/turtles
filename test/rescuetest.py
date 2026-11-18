"""Rescue drones (factory.lua "rescue drones", helper.lua runRescue).

Helper side, in the simulated world of feedtest.py:
1. fuel: the rescuer fetches fuel, flies down onto the drone, drops it in and
   reboots it; crafter1 is told (rescue_done).
2. reboot: a drone that is off is turned on (one that is on is rebooted).
3. trapped: the drone is dug (checked by its id first), carried into the open
   air beside the hover row, placed, given back what it carried, turned on.
4. a jammed shaft: another turtle on top of it is not touched; its id goes
   back to crafter1. A different turtle where it was is not dug either.
Factory side (the rescue section of factory.lua on its own):
5. what counts as stuck, the over-the-air reboot first for a crash, the
   nearest idle mate (or the named rescuer), the 3-an-hour limit, no
   rescue deep underground, the report in the status, the jammed shaft's
   top one first and the blocker next.

    cd test && python3 rescuetest.py
"""
import os, lupa
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(HERE)
fails = []
def check(what, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + what + (" | " + str(detail) if detail != "" else ""))
    if not ok: fails.append(what)

FEED = open(os.path.join(HERE, "feedtest.py")).read()
PRE = FEED[FEED.index("L=lupa.LuaRuntime"):FEED.index("g=L.globals()")]

def helper(victims, rescue, setup="", inv=None):
    ns = {"lupa": lupa, "ABORT": False}
    os.chdir(HERE)
    exec(PRE, ns)
    L = ns["L"]
    L.execute("""
for y=16,60 do setSpecial(-4462, y, 1521, false) end
T.x, T.y, T.z = -4462, 40, 1521
T.inv = {}
TOOL = "minecraft:diamond_pickaxe"
FS["helper.state"] = textutils.serialize({ done = true, rescue = %s })
FS[".version"] = "abc123"
LABEL = "builder1"
os.getComputerLabel = function() return LABEL end
V = {}           -- victims by "x,y,z": { id, label, on, inv = { name = n } }
local function vk(x, y, z) return x .. "," .. y .. "," .. z end
function addVictim(x, y, z, t) V[vk(x, y, z)] = t setSpecial(x, y, z, "computercraft:turtle_normal") end
local DX = {[0]=1,[1]=0,[2]=-1,[3]=0}; local DZ = {[0]=0,[1]=1,[2]=0,[3]=-1}
local function at(side)
  if side == "bottom" then return T.x, T.y - 1, T.z elseif side == "top" then return T.x, T.y + 1, T.z
  elseif side == "front" then return T.x + DX[T.d], T.y, T.z + DZ[T.d] end
end
local pg = peripheral.getType
peripheral.getType = function(side)
  local x, y, z = at(side)
  if x and V[vk(x, y, z)] then return "turtle" end
  return pg(side)
end
CALLS = {}
peripheral.call = function(side, m, ...)
  local x, y, z = at(side)
  local v = x and V[vk(x, y, z)]
  if not v then error("no peripheral " .. side, 0) end
  CALLS[#CALLS + 1] = m .. ":" .. v.id
  if m == "getID" then return v.id elseif m == "getLabel" then return v.label elseif m == "isOn" then return v.on
  elseif m == "turnOn" or m == "reboot" then v.on = not v.dead return nil end
  error("no method " .. m, 0)
end
DUG = {}
local function digV(x, y, z, raw)
  local v = V[vk(x, y, z)]
  if v then
    DUG[#DUG + 1] = v.id
    V[vk(x, y, z)] = nil
    setSpecial(x, y, z, false)
    for s = 1, 16 do if not T.inv[s] then T.inv[s] = { name = "computercraft:turtle_normal", count = 1, v = v } break end end
    for name, n in pairs(v.inv) do
      for s = 1, 16 do if not T.inv[s] then T.inv[s] = { name = name, count = n } break end end
    end
    v.inv = {}
    return true
  end
  return raw()
end
local rd, rdd = turtle.dig, turtle.digDown
turtle.dig = function() local x, y, z = at("front") return digV(x, y, z, rd) end
turtle.digDown = function() local x, y, z = at("bottom") return digV(x, y, z, rdd) end
local function putIn(side, n)
  local x, y, z = at(side)
  local v = V[vk(x, y, z)]
  local i = T.inv[T.sel]
  if not v or not i then return nil end
  n = math.min(n or i.count, i.count)
  v.inv[i.name] = (v.inv[i.name] or 0) + n
  i.count = i.count - n
  if i.count == 0 then T.inv[T.sel] = nil end
  return true
end
local dd, dr = turtle.dropDown, turtle.drop
turtle.dropDown = function(n) local r = putIn("bottom", n) if r ~= nil then return r end return dd(n) end
turtle.drop = function(n) local r = putIn("front", n) if r ~= nil then return r end return dr(n) end
local function place(side, raw)
  local i = T.inv[T.sel]
  local x, y, z = at(side)
  if i and i.v and not getBlock(x, y, z) then
    addVictim(x, y, z, i.v) PLACED = vk(x, y, z) T.inv[T.sel] = nil return true
  end
  return raw()
end
local pd, pf = turtle.placeDown, turtle.place
turtle.placeDown = function() return place("bottom", pd) end
turtle.place = function() return place("front", pf) end
DONE = {}
local hb2 = rednet.broadcast
rednet.broadcast = function(m, p) if type(m) == "table" and m.type == "rescue_done" then DONE[#DONE + 1] = m return end return hb2(m, p) end
local n = 0
local os_sleep = sleep
sleep = function(s) if s == 60 then n = n + 1 if n > 2 then error("IDLE", 0) end end return os_sleep(s) end
""" % rescue)
    L.execute(victims + setup)
    f = L.eval('loadfile(%r)' % os.path.join(ROOT, "helper.lua"))
    L.eval('function(f) return {pcall(f)} end')(f)
    return L, L.globals()

def done(g):
    d = list(g.DONE.values())
    return d[0] if d else None

# 1. fuel
L, g = helper('addVictim(-4430, 57, 1522, { id = 31, label = "builder4", on = true, inv = {} })',
              '{ who = "builder4", vid = 31, x = -4430, y = 57, z = 1522, how = "fuel", n = 4 }')
v = L.eval('V["-4430,57,1522"]')
d = done(g)
check("fuel: the rescuer fetches fuel and drops it into the drone", v is not None and v.inv["minecraft:coal"] and v.inv["minecraft:coal"] >= 12, v and dict(v.inv))
check("  checks its id, then reboots it", "getID:31" in g.CALLS.values() and "reboot:31" in g.CALLS.values(), list(g.CALLS.values()))
check("  and tells crafter1 (rescue_done, its number, what was done)", d is not None and d.n == 4 and d.vid == 31
      and "gave" in d.did and d.result == "fuelled and running", d and (d.did, d.result))
check("  nothing dug, and the rescue is off its hands", len(g.DUG) == 0
      and L.eval('textutils.unserialize(FS["helper.state"]).rescue') is None)

# 2. reboot: a drone that is off
L, g = helper('addVictim(-4440, 50, 1530, { id = 32, label = "builder3", on = false, inv = {} })',
              '{ who = "builder3", vid = 32, x = -4440, y = 50, z = 1530, how = "reboot", n = 5 }')
d = done(g)
check("reboot: a drone that is off is turned on", "turnOn:32" in g.CALLS.values() and d and d.did == "turned it on"
      and d.result == "running", d and (d.did, d.result))
L, g = helper('addVictim(-4440, 50, 1530, { id = 32, label = "builder3", on = true, dead = true, inv = {} })',
              '{ who = "builder3", vid = 32, x = -4440, y = 50, z = 1530, how = "reboot", n = 5 }')
d = done(g)
check("  one that is on is rebooted; one that does not come back is said so", "reboot:32" in g.CALLS.values()
      and d and d.did == "rebooted it" and d.result == "it did not start", d and (d.did, d.result))

# 3. trapped
L, g = helper('addVictim(-4462, 30, 1521, { id = 33, label = "builder2", on = true, inv = { ["minecraft:cobblestone"] = 20, ["minecraft:torch"] = 3 } })',
              '{ who = "builder2", vid = 33, x = -4462, y = 30, z = 1521, how = "trapped", n = 6 }')
d = done(g)
placed = g.PLACED
v = L.eval('PLACED and V[PLACED]')
check("trapped: dug out (only the drone itself)", list(g.DUG.values()) == [33], list(g.DUG.values()))
# hover spot: exit2 = pad + 1 = (-4462, 16, 1521); builder1 slot 1: x = -4462 + 3 + 2 = -4457, y = 15 + 12, z = 1517
check("  set down in the open air beside the hover row (between two spots)", placed == "-4456,27,1517", placed)
check("  what it carried given back, and turned on", v is not None and v.inv["minecraft:cobblestone"] == 20
      and v.inv["minecraft:torch"] == 3 and v.on is True, v and dict(v.inv))
check("  nothing of its left on the rescuer", not any(i and i.name in ("minecraft:cobblestone", "minecraft:torch",
      "computercraft:turtle_normal") for i in g.T.inv.values()), [(i.name, i.count) for i in g.T.inv.values() if i])
check("  crafter1 is told", d and d.result == "out and running" and "set it down at -4456 27 1517" in d.did, d and (d.did, d.result))

# 4. a jammed shaft: another turtle on top; a different turtle where it was
L, g = helper('''addVictim(-4462, 30, 1521, { id = 33, label = "builder2", on = true, inv = {} })
addVictim(-4462, 31, 1521, { id = 34, label = "survey1", on = true, inv = {} })''',
              '{ who = "builder2", vid = 33, x = -4462, y = 30, z = 1521, how = "trapped", n = 7 }')
d = done(g)
check("jammed shaft: the turtle on top is not dug", len(g.DUG) == 0, list(g.DUG.values()))
check("  its id goes back to crafter1 (it is dug out next)", d and d.blocker == 34 and "on top of it" in d.result, d and d.result)
L, g = helper('addVictim(-4462, 30, 1521, { id = 35, label = "Other", on = true, inv = {} })',
              '{ who = "builder2", vid = 33, x = -4462, y = 30, z = 1521, how = "trapped", n = 8 }')
d = done(g)
check("a different turtle where it was: not dug, not taken for a blocker", len(g.DUG) == 0 and d and d.blocker is None
      and "not there" in d.result, d and d.result)

# a miner's shaft under the hut (roofed over): down the pad's hole, across the base room, down the shaft
L, g = helper('addVictim(-4463, 8, 1521, { id = 36, label = "miner3", on = true, inv = {} })',
              '{ who = "miner3", vid = 36, x = -4463, y = 8, z = 1521, how = "fuel", n = 9 }')
d = done(g)
v = L.eval('V["-4463,8,1521"]')
check("a shaft roofed over at the base: in by the pad's hole and the base room, fuel handed over",
      d and d.result == "fuelled and running" and v.inv["minecraft:coal"] and v.inv["minecraft:coal"] >= 12, d and d.result)
check("  and back out the same way (up the pad's hole)", g.T.x != -4463 and g.T.y > 16, (g.T.x, g.T.y, g.T.z))
L, g = helper('addVictim(-4463, 8, 1521, { id = 36, label = "miner3", on = true, inv = {} }) addVictim(-4463, 9, 1521, { id = 37, label = "TuffLuck", on = true, inv = {} })',
              '{ who = "miner3", vid = 36, x = -4463, y = 8, z = 1521, how = "fuel", n = 10 }')
d = done(g)
check("  a miner on top of it in that shaft: not touched, its id back to crafter1 (moved first)",
      d and d.blocker == 37 and len(g.DUG) == 0 and not L.eval('V["-4463,8,1521"]').inv["minecraft:coal"], d and d.result)

# ---------------------------------------------------------------- 5. crafter1's side
FAC = open(os.path.join(ROOT, "factory.lua")).read()
sect = FAC[FAC.index("---------------------------------------------------------------- rescue drones"):FAC.index("local function statusListener()")]
sect = FAC[FAC.index("function K.skipped("):FAC.index("local function noteStatus(")] + sect     # (the skip lists)
def crafty():
    L = lupa.LuaRuntime(unpack_returned_tuples=True)
    L.execute('''K = { COUNTER = false, STALL_AFTER = 600, STALL_REBOOT = 300 }
function K.waiting(state) state = tostring(state)
  return state == "waiting for materials" or state == "fetching materials" or state:find("^stuck under") ~= nil end
RESTING = { idle = true, done = true, parked = true }
fleet, plots, DIRECT, SAVED, feedSent = {}, {}, {}, 0, {}
base = { f = { x = 0, y = 70, z = 0 }, pad = { x = -1, y = 70, z = 0 } }
swarm = {}
EPOCH = 1000000
os.epoch = function() return EPOCH end
os.date = function() return "18 Nov 01:00" end
function saveTable() SAVED = SAVED + 1 end
function nameKey(n) return tostring(n):lower() end
function isFar(u) return math.abs(u.x) > 64 or math.abs(u.z) > 64 end
function direct(id, o) DIRECT[#DIRECT + 1] = { id = id, o = o } end
LOG = {} function print(s) LOG[#LOG + 1] = s end
function u(label, id, role, state, x, y, z, at, since, fuel)
  fleet[label:lower()] = { label = label, id = id, role = role, state = state, x = x, y = y, z = z, at = at,
    since = since, fuel = fuel or 1000, screen = { "line 1", "ERROR: boom" } }
end''')
    L.execute(sect)
    return L
L = crafty()
L.execute('''u("lava1", 20, "helper", "idle", 10, 82, 10, 1000, 0)
u("builder1", 21, "helper", "idle", -30, 82, 0, 1000, 0)
u("builder4", 25, "helper", "needs fuel", 40, 90, 5, 1000, 500)
K.rescueDuty(1000)''')
check("out of fuel 8 minutes: the nearest idle mate is sent", L.eval("#DIRECT") == 1 and L.eval("DIRECT[1].id") == 20
      and L.eval("DIRECT[1].o.cmd") == "rescue" and L.eval("DIRECT[1].o.how") == "fuel" and L.eval("DIRECT[1].o.vid") == 25)
check("  the report goes into the status, with its last screen lines", L.eval("plots.rescues[1].who") == "builder4"
      and L.eval("plots.rescues[1].screen[2]") == "ERROR: boom" and L.eval("plots.rescues[1].result") == "under way")
L.execute("K.rescueDuty(1030)")
check("  one rescue at a time", L.eval("#DIRECT") == 1)
L.execute('''K.rescueHeard(20, { n = K.rescueNow.n, did = "gave 26 fuel, rebooted it", result = "fuelled and running" })''')
check("  the rescuer's word is kept (did, result)", L.eval("plots.rescues[1].did") == "gave 26 fuel, rebooted it"
      and L.eval("plots.rescues[1].result") == "fuelled and running" and L.eval("K.rescueNow") is None)
L.execute('''fleet.builder4.state = "building" fleet.builder4.since = 1100 fleet.builder4.at = 1200 K.rescueDuty(1200)''')
check("  and what it says three minutes on", L.eval("plots.rescues[1].after") == "building")

L = crafty()
L.execute('''u("lava1", 20, "helper", "idle", 10, 82, 10, 1000, 0)
u("builder3", 26, "helper", "error", 5, 85, 5, 1000, 700)
K.rescueDuty(1000)''')
check("crashed: first told to reboot over the air, nobody sent", L.eval("#DIRECT") == 1 and L.eval("DIRECT[1].id") == 26
      and L.eval("DIRECT[1].o.cmd") == "reboot")
L.execute('''fleet.builder3.since = 1100 fleet.builder3.at = 1400 fleet.lava1.at = 1400 K.rescueDuty(1400)''')
check("  crashed again within 30 min: a mate goes to reboot it by hand", L.eval("#DIRECT") == 2
      and L.eval("DIRECT[2].id") == 20 and L.eval("DIRECT[2].o.how") == "reboot")

L = crafty()
L.execute('''u("lava1", 20, "helper", "idle", 10, 82, 10, 1000, 0)
u("Shut", 45, "helper", "error", 5, 75, 5, 1000, 700)
fleet.shut.screen = { "ERROR: I am inside the factory and cannot find the way to the door." }
K.rebootTold.shut = 900
K.rescueDuty(1000)''')
check("a crash that says it is shut in (inside the factory): dug out, not just rebooted",
      L.eval("DIRECT[1].o.how") == "trapped" and L.eval("DIRECT[1].o.vid") == 45)
L = crafty()
L.execute('''u("lava1", 20, "helper", "idle", 10, 82, 10, 1000, 0)
u("builder4", 25, "helper", "needs fuel", 40, 90, 5, 1000, 500)
feedSent[25] = 800
K.rescueDuty(1000)''')
check("out of fuel, a mate already on its way with fuel (feed): nobody else sent", L.eval("#DIRECT") == 0)

L = crafty()
L.execute('''u("lava1", 20, "helper", "idle", 10, 82, 10, 1000, 0)
u("Ghast", 40, "loader", "parked", 20, 85, 5, 300, 0)
K.rescueDuty(1000)''')
check("silent 11 minutes (known place): sent to reboot it", L.eval("#DIRECT") == 1 and L.eval("DIRECT[1].o.how") == "reboot"
      and L.eval("plots.rescues[1].problem") == "silent")
L = crafty()
L.execute('''u("lava1", 20, "helper", "idle", 10, 82, 10, 20000, 0)
u("Old", 41, "helper", "idle", 20, 85, 5, 100, 0)
u("Far", 42, "miner", "mining", 500, 20, 5, 19000, 0)
K.rescueDuty(20000)''')
check("silent for hours (taken away): left alone; a far miner gone quiet is the loaders' (escort)", L.eval("#DIRECT") == 0)

L = crafty()
L.execute('''u("lava1", 20, "helper", "idle", 10, 82, 10, 1000, 0)
u("Deep", 43, "miner", "stuck in rock", 20, 12, 5, 1000, 0)
K.rescueDuty(1000)''')
check("deep underground (no shaft): reported, not rescued", L.eval("#DIRECT") == 0
      and "deep underground" in L.eval("plots.rescues[1].result") and L.eval("plots.rescues[1].did") == "nothing")
L.execute("K.rescueDuty(1030)")
check("  (reported once in 30 min)", L.eval("#plots.rescues") == 1)

L = crafty()
L.execute('''u("lava1", 20, "helper", "idle", 10, 82, 10, 1000, 0)
u("Lost", 44, "helper", "stuck in the factory", 20, 75, 5, 1000, 0)
plots.rescueTimes = { lost = { EPOCH / 1000 - 3000, EPOCH / 1000 - 2000, EPOCH / 1000 - 100 } }
K.rescueDuty(1000)''')
check("rescued 3 times this hour: reported instead", L.eval("#DIRECT") == 0 and "3 times this hour" in L.eval("plots.rescues[1].result"))
L.execute('''plots.rescueTimes.lost = { EPOCH / 1000 - 4000, EPOCH / 1000 - 2000, EPOCH / 1000 - 100 } K.rescueTold = {} K.rescueDuty(1000)''')
check("  (an hour old does not count): trapped, sent to dig it out", L.eval("#DIRECT") == 1 and L.eval("DIRECT[1].o.how") == "trapped")

L = crafty()
L.execute('''u("lava1", 20, "helper", "idle", 10, 82, 10, 1000, 0)
u("builder1", 21, "helper", "idle", 300, 82, 300, 1000, 0)
u("builder4", 25, "helper", "needs fuel", 40, 90, 5, 1000, 500)
plots.rescue = { name = "builder1" }
K.rescueDuty(1000)''')
check("the named rescuer goes when it is idle, however far", L.eval("DIRECT[1].id") == 21)
L = crafty()
L.execute('''u("lava1", 20, "helper", "idle", 10, 82, 10, 1000, 0)
u("builder1", 21, "helper", "building", 300, 82, 300, 1000, 0)
u("builder4", 25, "helper", "needs fuel", 40, 90, 5, 1000, 500)
plots.rescue = { name = "builder1", only = true }
K.rescueDuty(1000)''')
check("  only=1 and it is busy: nobody goes", L.eval("#DIRECT") == 0)
L = crafty()
L.execute('''u("lava1", 20, "helper", "idle", 10, 82, 10, 1000, 0)
u("builder4", 25, "helper", "needs fuel", 40, 90, 5, 1000, 500)
plots.rescue = { on = false }
K.rescueDuty(1000)''')
check("rescuer crafter1 on=0: none", L.eval("#DIRECT") == 0)

L = crafty()
L.execute('''u("lava1", 20, "helper", "idle", 10, 82, 10, 2000, 0)
u("Low", 27, "helper", "fetching materials", -1, 74, 0, 2000, 0)
u("Top", 28, "helper", "fetching materials", -1, 76, 0, 2000, 0)
K.rescueDuty(2000)''')
check("a jammed pad shaft: the top one first, dug out (trapped)", L.eval("DIRECT[1].o.vid") == 28
      and L.eval("DIRECT[1].o.how") == "trapped")
L = crafty()
L.execute('''u("lava1", 20, "helper", "idle", 10, 82, 10, 2000, 0)
u("Low", 27, "helper", "fetching materials", -1, 74, 0, 2000, 0)
u("Mid", 29, "helper", "idle", -1, 75, 0, 2000, 0)
K.rescueDuty(2000)
K.rescueHeard(20, { n = K.rescueNow.n, did = "nothing", result = "could not reach it", blocker = 29 })
fleet.lava1.state = "idle"
K.rescueDuty(2030)''')
check("  a turtle on top that is not stuck itself: dug out next (crafter1 asks for it)",
      L.eval("#DIRECT") == 2 and L.eval("DIRECT[2].o.vid") == 29 and L.eval("DIRECT[2].o.how") == "trapped")
check("the order: rescue crafter1 who=<drone>, rescuer crafter1 name=<helper>",
      'c.cmd == "rescue" and type(c.who) == "string"' in FAC and 'c.cmd == "rescuer"' in FAC)
check("the status carries the rescues", "rescues = (not K.COUNTER and plots.rescues" in FAC)

L = crafty()
L.execute('u("lava1", 20, "helper", "idle", 10, 82, 10, 1000, 0) u("builder3", 35, "helper", "cannot move: Out of fuel", 25, 77, 13, 1000, 600) K.rescueDuty(1000)')
check("'cannot move: Out of fuel' is a fuel rescue", L.eval("DIRECT[1].o.how") == "fuel")
L = crafty()
L.execute('u("lava1", 20, "helper", "idle", 10, 82, 10, 1000, 0) u("miner3", 36, "miner", "stranded", -2, 57, 0, 1000, 600) K.rescueDuty(1000)')
check("a miner deep in a shaft at the base (by the pad) is reachable: rescued, not reported",
      L.eval("DIRECT[1].o.vid") == 36 and L.eval("DIRECT[1].o.how") == "fuel")

print("PASS" if not fails else "FAILED: %d" % len(fails))
