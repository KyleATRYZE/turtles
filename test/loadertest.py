# The chunk loader (loader.lua): escorts, pairing by itself, fuel.
# Runs from anywhere:  python3 test/loadertest.py
import os, lupa
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(HERE)
HARNESS = open(os.path.join(HERE, 'harness.lua')).read().replace('/home/claude/turtles', ROOT)
fails = []
def check(what, ok):
    print(("ok   " if ok else "FAIL ") + what)
    if not ok: fails.append(what)

BASE = '{ f = { x = -4461, y = 20, z = 1521 }, pad = { x = -4462, y = 20, z = 1521 } }'
ENV = r'''
-- time: a move is 0.4 s, a sleep is what it says; the run ends at LIMIT
CLOCK, LIMIT = 0, LIMIT or 4000
os.clock = function() return CLOCK end
local function pass(n) CLOCK = CLOCK + n if CLOCK > LIMIT then error("END", 0) end end
sleep = function(n) pass(n or 0) if coroutine.isyieldable() then coroutine.yield() end end
for _, n in ipairs({ "forward", "back", "up", "down" }) do
  local f = turtle[n]
  turtle[n] = function() local r = f() pass(0.4) return r end
end
-- (tasks inside tasks: every round, let the task outside have a turn too)
parallel = { waitForAny = function(...)
  local cos = {}
  for i, f in ipairs({ ... }) do cos[i] = coroutine.create(f) end
  while true do
    for i, co in ipairs(cos) do
      local ok, err = coroutine.resume(co)
      if not ok then error(err, 0) end
      if coroutine.status(co) == "dead" then return i end
    end
    if coroutine.isyieldable() then coroutine.yield() end
  end
end }
LABEL = "Phantastic"
os.getComputerID = function() return 52 end
FS[".base"] = textutils.serialize(BASE_T)
REPORTS, JOBMSGS, FUEL_ASKS = {}, {}, 0
STATUSQ, CMDQ2 = {}, {}          -- { at = clock, id =, msg = }
OTHERS = {}                      -- label -> function(clock) returning a status (or nil), said every 5 s
local lastSaid = {}
rednet.broadcast = function(m, p)
  if p == "swarm" then
    if REPORTS[#REPORTS] ~= m.state then REPORTS[#REPORTS + 1] = m.state end
    LAST = m
  elseif p == "swarm_job" then
    JOBMSGS[#JOBMSGS + 1] = { type = m.type, at = CLOCK, gaveUp = m.gaveUp, x = m.x, y = m.y, z = m.z }
    if m.type == "fuel_request" then
      FUEL_ASKS = FUEL_ASKS + 1
      -- the factory serves whoever stands on the pad
      if not NO_COAL and T.x == BASE_T.pad.x and T.y == BASE_T.pad.y and T.z == BASE_T.pad.z then
        for s = 1, 16 do if not T.inv[s] then T.inv[s] = { name = "minecraft:coal", count = 8 } break end end
      end
    end
  end
end
rednet.send = rednet.broadcast
rednet.receive = function(proto, timeout)
  local waited = 0
  while true do
    if proto == "swarm" then
      local m = STATUSQ[1]
      if m and CLOCK >= m.at then table.remove(STATUSQ, 1) return m.id, m.msg end
      for label, f in pairs(OTHERS) do
        if CLOCK - (lastSaid[label] or -100) >= 5 then
          lastSaid[label] = CLOCK
          local msg = f(CLOCK)
          if msg then msg.label = label return 99, msg end
        end
      end
    elseif proto == "swarm_cmd" then
      local c = CMDQ2[1]
      if c and CLOCK >= c.at then table.remove(CMDQ2, 1) return 3, c.cmd end
    end
    if timeout and waited >= timeout then return nil end
    waited = waited + 1
    coroutine.yield()
  end
end
'''

def run(setup, limit=4000):
    L = lupa.LuaRuntime(unpack_returned_tuples=True)
    L.execute("START_D=0; START_FUEL=0; LIMIT=%d" % limit)
    L.execute(HARNESS)
    L.execute("BASE_T = " + BASE)
    L.execute(ENV)
    L.execute(setup)
    f = L.eval('loadfile("%s/loader.lua")' % ROOT)
    r = L.eval('function(f) return {pcall(f)} end')(f)
    g = L.globals()
    return L, g, list(r.values())

def states(g):
    st = list(g.REPORTS.values())
    while st and st[-1] == "error": st.pop()      # (the run is ended by an error raised from sleep)
    return st
def asks(g, kind): return [m for m in g.JOBMSGS.values() if m.type == kind]

# A) an escort written by hand: out to the turtle, follow it home, park
L, g, r = run('''T.x, T.y, T.z, T.fuel = -4450, 20, 1530, 3000
FS["loader.state"] = textutils.serialize({ mode = "escort", who = "Coalition", x = -4559, z = 1605 })
local path = { {-4559,1605}, {-4540,1590}, {-4515,1570}, {-4490,1550}, {-4470,1530} }
STEP = 1
OTHERS.Coalition = function()
  local p = path[STEP]
  -- it wakes, and moves on, only while I am over its chunk
  if math.floor(T.x/16) ~= math.floor(p[1]/16) or math.floor(T.z/16) ~= math.floor(p[2]/16) or T.y < 150 then return nil end
  if STEP < #path then STEP = STEP + 1 end
  p = path[STEP]
  return { role = "miner", state = "flying to base", pos = { x = p[1], y = 60, z = p[2] } }
end''', limit=3000)
check("A: followed it home and parked", g.STEP >= 4 and states(g)[-1] == "parked" and (g.T.x, g.T.z) == (-4457, 1518) and g.T.y == 20)
check("A: state file says park", 'mode="park"' in L.eval('FS["loader.state"]').replace(" ", ""))
check("A: parked and free, it asks the factory who needs company", len(asks(g, "escort_request")) >= 1)

# B) parked with 78 fuel (Phantastic): a short hop to the pad, coal, back to the spot
L, g, r = run('''T.x, T.y, T.z, T.fuel = -4457, 20, 1520, 78
FS["loader.state"] = textutils.serialize({ mode = "park" })''', limit=1500)
check("B: fetched fuel by a low hop", g.FUEL_ASKS >= 1 and g.T.fuel >= 600 and "fetching fuel" in states(g))
check("B: never went up to flying height on 78 fuel", "needs fuel" not in states(g) and len(asks(g, "feed_request")) == 0)
check("B: back on the parking spot", (g.T.x, g.T.y, g.T.z) == (-4457, 20, 1518) and states(g)[-1] == "parked")

# C) parked with 12 fuel: cannot even hop: asks for a feed, says so, stays put; fed, it carries on
L, g, r = run('''T.x, T.y, T.z, T.fuel = -4457, 20, 1520, 12
FS["loader.state"] = textutils.serialize({ mode = "park" })
local fed
local oldSleep = sleep
sleep = function(n)
  if CLOCK > 700 and not fed then fed = true FED_AT = CLOCK T.inv[5] = { name = "minecraft:coal", count = 16 } end
  return oldSleep(n)
end''', limit=1500)
f = asks(g, "feed_request")
check("C: asked for a feed, with its place", len(f) >= 1 and (f[0].x, f[0].y, f[0].z) == (-4457, 20, 1520))
check("C: said it needs fuel, did not ask every minute", "needs fuel" in states(g) and len([m for m in f if m.at < 700]) <= 4)
check("C: fed, it is parked again with fuel", g.T.fuel >= 600 and states(g)[-1] == "parked")

# D) out in the wild and dry (stranded 500 blocks away with 30 fuel): asks for a feed there
L, g, r = run('''T.x, T.y, T.z, T.fuel = -4957, 20, 1520, 30
FS["loader.state"] = textutils.serialize({ mode = "park" })''', limit=700)
f = asks(g, "feed_request")
check("D: stranded far out: asks for a feed where it is", len(f) >= 1 and abs(f[0].x + 4957) <= 2 and g.FUEL_ASKS == 0)

# E) told to stay (park by hand): never asks for company
L, g, r = run('''T.x, T.y, T.z, T.fuel = -4457, 20, 1520, 3000
FS["loader.state"] = textutils.serialize({ mode = "park" })
CMDQ2 = { { at = 10, cmd = { id = 5, target = "Phantastic", cmd = "park" } } }''', limit=600)
check("E: park by hand holds it", len([m for m in asks(g, "escort_request") if m.at > 20]) == 0)
check("E: and says so in its report", g.LAST.job.hold == True)

# F) the factory sends it out (a direct order); the miner later stops work: home, parked, asking again
L, g, r = run('''T.x, T.y, T.z, T.fuel = -4457, 20, 1520, 5000
FS["loader.state"] = textutils.serialize({ mode = "park" })
CMDQ2 = { { at = 70, cmd = { direct = true, forId = 52, nonce = "n1", cmd = "escort", who = "Oresome", x = -4800, z = 1700, auto = true } },
          { at = 80, cmd = { direct = true, forId = 52, nonce = "n1", cmd = "escort", who = "Nobody", auto = true } },      -- a repeat: ignored
          { at = 90, cmd = { direct = true, forId = 99, nonce = "n2", cmd = "escort", who = "Nobody", auto = true } } }    -- for another loader
OTHERS.Oresome = function(c)
  if T.x == -4800 and T.z == 1700 then OVER = (OVER or 0) + 1 end
  return { role = "miner", state = c < 900 and "mining" or "done", pos = { x = -4800, y = 12, z = 1700 } }
end''', limit=2200)
st = states(g)
check("F: went out and stood over the miner", (g.OVER or 0) > 10 and "escorting" in st)
check("F: the miner finished: home and parked", st[-1] == "parked" and (g.T.x, g.T.z) == (-4457, 1518))
check("F: free again, it asks", any(m.at > 1000 for m in asks(g, "escort_request")))
check("F: repeats and other loaders' orders were ignored", "Nobody" not in L.eval('FS["loader.state"]'))

# G) sent to a turtle that never speaks: ten minutes over the spot, then home, and it says who it gave up on
L, g, r = run('''T.x, T.y, T.z, T.fuel = -4457, 20, 1520, 5000
FS["loader.state"] = textutils.serialize({ mode = "park" })
CMDQ2 = { { at = 70, cmd = { direct = true, forId = 52, nonce = "n1", cmd = "escort", who = "Coalition", x = -4700, z = 1600, auto = true } } }''', limit=2500)
st = states(g)
check("G: looked for it, then came home", "looking for Coalition" in st and st[-1] == "parked")
check("G: tells the factory who it gave up on", any(m.gaveUp == "Coalition" for m in asks(g, "escort_request")))

# H) a long way out on little fuel: it fetches enough for there and back before going, and does not shuttle
L, g, r = run('''T.x, T.y, T.z, T.fuel = -4457, 20, 1520, 700
FS["loader.state"] = textutils.serialize({ mode = "escort", who = "miner3", stay = true, x = -6000, z = 1521 })
OTHERS.miner3 = function(c)
  if T.x == -6000 and T.z == 1521 then OVER = (OVER or 0) + 1 end
  return { role = "miner", state = "hunting coal", pos = { x = -6000, y = 30, z = 1521 } }
end
local up = turtle.up
PAD_VISITS = 0
local wasOn = false
local oldSleep = sleep
sleep = function(n)
  local on = T.x == BASE_T.pad.x and T.y == BASE_T.pad.y and T.z == BASE_T.pad.z
  if on and not wasOn then PAD_VISITS = PAD_VISITS + 1 end
  wasOn = on
  return oldSleep(n)
end''', limit=3500)
check("H: fuelled for the round trip first (one visit to the pad)", g.PAD_VISITS == 1 and g.FUEL_ASKS >= 4)
check("H: got there and stayed", (g.OVER or 0) > 5 and g.T.fuel > 1500 + 130)

# I) the factory has no coal: it does not fly out on fuel that will not bring it home
L, g, r = run('''T.x, T.y, T.z, T.fuel = -4457, 20, 1520, 700
NO_COAL = true
FS["loader.state"] = textutils.serialize({ mode = "escort", who = "miner3", stay = true, x = -6000, z = 1521 })
OTHERS.miner3 = function(c) return { role = "miner", state = "hunting coal", pos = { x = -6000, y = 30, z = 1521 } } end''', limit=2500)
check("I: no coal to be had: stays near the base and says it needs fuel", abs(g.T.x + 4461) < 20 and "needs fuel" in states(g))
# J) nearly dry, and another turtle is sitting on the pad: wait a minute, then out of its way, and ask for a feed
L, g, r = run('''T.x, T.y, T.z, T.fuel = -4457, 20, 1520, 78
setSpecial(BASE_T.pad.x, BASE_T.pad.y, BASE_T.pad.z, "computercraft:turtle_normal")
FS["loader.state"] = textutils.serialize({ mode = "park" })
TRIES = 0
local oldPrint = print
print = function(...) if tostring((...)):find("launch pad is taken") then TRIES = TRIES + 1 end return oldPrint(...) end''', limit=280)
check("J: pad taken: one try, then a feed is asked for", g.TRIES == 1 and len(asks(g, "feed_request")) >= 1 and g.FUEL_ASKS == 0)
check("J: not left hanging in the air over the pad", (g.T.x, g.T.z) != (-4462, 1521) and g.T.fuel > 0)
# K) the renaming, mid-escort: a loader with its old label and old state (with the hunter, by his old name)
#    starts up; the hunter reports under his old name, then (rebooted) under his new one, and moves on
L, g, r = run('''T.x, T.y, T.z, T.fuel = -4700, 150, 1600, 5000
LABEL = "Chunk" .. "Berry"
FS["loader.state"] = textutils.serialize({ mode = "escort", who = "NatKing" .. "Coal", stay = true, x = -4700, z = 1600 })
OTHERS.hunter = function(c)
  local renamed = c > 300
  local x = renamed and -4900 or -4700
  if renamed and T.x == -4900 and T.z == 1600 then OVER_NEW = (OVER_NEW or 0) + 1 end
  return { role = "miner", state = "hunting coal", pos = { x = x, y = 30, z = 1600 }, name = renamed and "miner3" or ("NatKing" .. "Coal") }
end
-- (OTHERS reports under its key: give this one the name it carries)
local receive = rednet.receive
rednet.receive = function(proto, timeout)
  local id, msg = receive(proto, timeout)
  if type(msg) == "table" and msg.name then msg.label, msg.name = msg.name, nil end
  return id, msg
end''', limit=1500)
check("K: the loader took its new name, and its state names the hunter's new name",
      g.LABEL == "Ablaze" and 'who="miner3"' in L.eval('FS["loader.state"]').replace(" ", ""))
check("K: it followed the hunter after he was renamed", (g.OVER_NEW or 0) > 10 and "looking for miner3" not in states(g))

# L) orders by hand under the old names: to the loader's old name, naming the miner's old name
L, g, r = run('''T.x, T.y, T.z, T.fuel = -4457, 20, 1520, 5000
LABEL = "Ablaze"
FS["loader.state"] = textutils.serialize({ mode = "park", hold = true })
CMDQ2 = { { at = 20, cmd = { id = 9, target = "Chunk" .. "Berry", cmd = "escort", who = "Ore" .. "Lando", stay = 1 } } }
OTHERS.Oresome = function(c)
  if T.x == -4800 and T.z == 1700 then OVER = (OVER or 0) + 1 end
  return { role = "miner", state = "mining", pos = { x = -4800, y = 12, z = 1700 } }
end''', limit=1200)
check("L: an order to the loader's old name, for a miner by his old name, is carried out", (g.OVER or 0) > 10)
print("PASS" if not fails else "FAILED: %d" % len(fails))
