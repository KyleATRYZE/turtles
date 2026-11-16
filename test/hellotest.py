# The boot heartbeat (swarm.hello): said once per start, with the place.
# Runs from anywhere:  python3 test/hellotest.py
import os, lupa
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENV = r'''
CLOCK = 5
os.clock = function() return CLOCK end
os.epoch = function() return 1700000000000 + CLOCK * 1000 end
os.getComputerID = function() return 17 end
os.getComputerLabel = function() return "CoalPorter" end
FS = { [".version"] = "abc1234", [".role"] = "miner" }
fs = { exists = function(f) return FS[f] ~= nil end,
  open = function(f) return { readAll = function() return FS[f] end, close = function() end, write = function(s) FS[f] = s end } end }
local modem = { isWireless = function() return true end }
peripheral = { find = function(t, f) if HAS_MODEM and f("left", modem) then return modem end end,
  getName = function() return "left" end, getType = function() return nil end }
SENT = {}
rednet = { open = function() end, broadcast = function(m, p) SENT[#SENT + 1] = { m = m, p = p } end }
gps = { locate = function() if NO_GPS then return nil end return -4377.0, 60.0, 1577.0 end }
turtle = { getFuelLevel = function() return 83 end }
package.path = "%s/?.lua;" .. package.path
''' % ROOT
fails = []
def check(what, ok):
    print(("ok   " if ok else "FAIL ") + what)
    if not ok: fails.append(what)

L = lupa.LuaRuntime(unpack_returned_tuples=True); L.execute(ENV); L.execute("HAS_MODEM = true")
L.execute('swarm = dofile("%s/swarm.lua") swarm.hello("miner")' % ROOT)
g = L.globals(); m = g.SENT[1].m
check("one report on the status channel", len(list(g.SENT.values())) == 1 and g.SENT[1].p == "swarm")
check("says who, where and how much fuel", m.label == "CoalPorter" and m.state == "woke up" and (m.pos.x, m.pos.y, m.pos.z) == (-4377, 60, 1577) and m.fuel == 83 and m.role == "miner")
check("the log line names the place", m.log[1] == "Woke up at -4377 60 1577.")
L.execute('swarm.hello("miner")')
check("said once per start", len(list(g.SENT.values())) == 1)
L.execute('swarm.report({ state = "mining" })')
check("later reports carry the start time", g.SENT[2].m.booted == m.booted and m.booted > 0)

# the updater says it first (before any download), from the saved role
L = lupa.LuaRuntime(unpack_returned_tuples=True); L.execute(ENV); L.execute("HAS_MODEM = true http = nil")
L.execute('print = function() end local f = loadfile("%s/update.lua") pcall(f)' % ROOT)
g = L.globals()
check("update.lua says hello before downloading", len(list(g.SENT.values())) == 1 and g.SENT[1].m.state == "woke up" and g.SENT[1].m.role == "miner")

# no GPS: still speaks (place 0, 0 = not known); no modem: silent, no error
L = lupa.LuaRuntime(unpack_returned_tuples=True); L.execute(ENV); L.execute("HAS_MODEM = true NO_GPS = true")
L.execute('swarm = dofile("%s/swarm.lua") swarm.hello("helper")' % ROOT)
g = L.globals()
check("no GPS: speaks anyway", g.SENT[1].m.pos.x == 0 and g.SENT[1].m.log[1] == "Woke up (no GPS fix).")
L = lupa.LuaRuntime(unpack_returned_tuples=True); L.execute(ENV)
r = L.eval('(function() local s = dofile("%s/swarm.lua") return s.hello("helper") end)()' % ROOT)
check("no modem: nothing sent, no error", r is False and len(list(L.globals().SENT.values())) == 0)
print("PASS" if not fails else "FAILED: %d" % len(fails))
