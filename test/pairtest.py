# The factory pairs chunk loaders with far-off turtles and sends fuel to a
# stranded one. Runs from anywhere:  python3 test/pairtest.py
import os, lupa
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(HERE)
HARNESS = open(os.path.join(HERE, 'fharness.lua')).read().replace('/home/claude/turtles', ROOT)
fails = []
def check(what, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + what + ("" if ok or not detail else "  [%s]" % detail))
    if not ok: fails.append(what)

def run(statuses, inbox, idles=4):
    """statuses / inbox: Lua source for STATUSQ / INBOX entries. Returns the direct orders sent."""
    L = lupa.LuaRuntime(unpack_returned_tuples=True); L.execute("MODEM_ON=true"); L.execute(HARNESS)
    L.execute('''C="minecraft:chest_0" put(C,"minecraft:coal",64)
FILES[".plots"]='{["next"]=7,["done"]=0,["hunter"]=true,["builderId"]=14,["helpers"]={21,22,23,24},["loaders"]={41,42,43,44},["byId"]={}}'
MAX_IDLES=%d
local function st(id, label, role, state, x, z, extra)
  local m = { label = label, role = role, state = state, pos = { x = x, y = 80, z = z }, fuel = 900 }
  for k, v in pairs(extra or {}) do m[k] = v end
  return { id = id, msg = m }
end
ST = st
STATUSQ = { %s }
INBOX = { %s }''' % (idles, statuses, inbox))
    r = L.eval('{runFactory()}')[2]
    g = L.globals()
    out = [(m.to, dict(m.msg)) for m in g.OUTBOX.values() if m.msg.direct]
    return out, list(g.LOG.values()), r

FAR, NEARBY = "1100, 1200", "110, 205"       # the factory stands at 100, 200
PARKED = 'ST(51, "Ghastly", "loader", "parked", 104, 199, { job = { mode = "park" } }), ST(52, "Phantastic", "loader", "parked", 104, 199, { job = { mode = "park" } })'
ASK = '{ id = 52, wait = true, msg = { type = "escort_request", id = 52, label = "Phantastic" } }'

# 1. two loaders parked, a miner working far away: the one that asks goes out with it
out, log, r = run(PARKED + ', ST(9, "Oresome", "miner", "mining", %s)' % FAR, ASK)
check("sent out with the far miner, as a direct order", len(out) == 1 and out[0][0] == 52 and out[0][1]["cmd"] == "escort"
      and out[0][1]["who"] == "Oresome" and out[0][1]["auto"] and out[0][1]["forId"] == 52 and out[0][1]["x"] == 1100)
check("on the order channel, with a nonce", out and out[0][1]["nonce"] is not None)

# 2. the only loader at the base stays, whoever is out there
out, log, r = run('ST(52, "Phantastic", "loader", "parked", 104, 199, { job = { mode = "park" } }), ST(9, "Oresome", "miner", "mining", %s)' % FAR, ASK)
check("the last loader at the base is never sent", out == [])

# 3. both ask at once: one goes, one stays
out, log, r = run(PARKED + ', ST(9, "Oresome", "miner", "mining", %s), ST(10, "Pickle", "miner", "mining", %s)' % (FAR, FAR),
    ASK + ', { id = 51, wait = true, msg = { type = "escort_request", id = 51, label = "Ghastly" } }')
check("two ask, two far miners, two loaders: only one is sent", len(out) == 1)

# 4. nobody needs one: miners near the base, parked far away, already escorted, or carrying their own
out, log, r = run(PARKED + ', ST(9, "Oresome", "miner", "mining", %s), ST(10, "CleanSlate", "miner", "parked", %s), ' % (NEARBY, FAR)
    + 'ST(11, "miner3", "miner", "hunting coal", %s), ST(53, "Ablaze", "loader", "escorting", %s, { job = { mode = "escort", who = "miner3" } }), ' % (FAR, FAR)
    + 'ST(12, "Cobbler", "miner", "mining", %s, { chunky = "carried" })' % FAR, ASK)
check("near, resting, escorted and self-loading turtles need no loader", out == [])

# 5. three loaders, two far miners, one already taken: the other one is offered; the farther first
out, log, r = run(PARKED + ', ST(9, "Oresome", "miner", "mining", 400, 200), ST(10, "Pickle", "miner", "mining", 900, 200), '
    + 'ST(53, "Ablaze", "loader", "escorting", 900, 200, { job = { mode = "escort", who = "Pickle" } })', ASK)
check("the one without a loader is chosen", len(out) == 1 and out[0][1]["who"] == "Oresome")
out, log, r = run(PARKED + ', ST(9, "Oresome", "miner", "mining", 400, 200), ST(10, "Pickle", "miner", "mining", 900, 200)', ASK)
check("farthest first", len(out) == 1 and out[0][1]["who"] == "Pickle")

# 6. a loader that found nothing over a turtle is not sent to it again
out, log, r = run(PARKED + ', ST(9, "Coalition", "miner", "hunting coal", %s)' % FAR,
    '{ id = 52, wait = true, msg = { type = "escort_request", id = 52, label = "Phantastic", gaveUp = "Coalition" } }')
check("gave up on it: not offered again", out == [])

# 7. a far turtle gone quiet (frozen in an unloaded chunk) comes first, even one with its own controller
out, log, r = run('ST(9, "Coalition", "miner", "hunting coal", 600, 200, { chunky = "carried" }), '
    + '{ id = 51, at = 300, msg = { label = "Ghastly", role = "loader", state = "parked", pos = { x = 104, y = 80, z = 199 } } }, '
    + '{ id = 10, at = 300, msg = { label = "Oresome", role = "miner", state = "mining", pos = { x = 1100, y = 30, z = 1200 } } }',
    '{ id = 52, at = 310, msg = { type = "escort_request", id = 52, label = "Phantastic" } }', idles=600)
check("the silent one first", len(out) == 1 and out[0][1]["who"] == "Coalition")

# 8. fuel for a stranded loader: the idle mate with most fuel is sent, once
HELPERS = 'ST(21, "lava1", "helper", "idle", 104, 205, { fuel = 484 }), ST(22, "builder1", "helper", "idle", 106, 205, { fuel = 237 }), ST(23, "foundry1", "helper", "building", 150, 205, { fuel = 5000 })'
FEED = '{ id = 52, wait = true, msg = { type = "feed_request", id = 52, label = "Phantastic", x = 104, y = 70, z = 199, fuel = 78 } }'
out, log, r = run(HELPERS, FEED + ', ' + FEED)
check("an idle mate takes fuel there (once)", len(out) == 1 and out[0][0] == 21 and out[0][1]["cmd"] == "feed"
      and (out[0][1]["x"], out[0][1]["y"], out[0][1]["z"]) == (104, 70, 199))
out, log, r = run('ST(23, "foundry1", "helper", "building", 150, 205, { fuel = 5000 })', FEED)
check("no mate free: nobody is pulled off a job", out == [] and any("No builder's mate free" in l for l in log))

# 9. three loaders already out: no fourth
THREE_OUT = ', '.join('ST(%d, "L%d", "loader", "escorting", 900, %d, { job = { mode = "escort", who = "M%d" } })' % (60+i, i, 200+i*10, i) for i in range(3))
out, log, r = run(PARKED + ', ST(9, "Oresome", "miner", "mining", %s), ' % FAR + THREE_OUT, ASK)
check("never more than three loaders out at once", out == [])
# 10. a helper working far away gets no loader; a miner 60 blocks out is not far
out, log, r = run(PARKED + ', ST(21, "lava1", "helper", "flying", %s), ST(9, "Oresome", "miner", "mining", 160, 200)' % FAR, ASK)
check("helpers and turtles within 64 blocks get no loader", out == [])

# 11. storage nearly full: a miner asking for a plot is given none; with room again, it is
def plotRun(fill):
    L = lupa.LuaRuntime(unpack_returned_tuples=True); L.execute("MODEM_ON=true"); L.execute(HARNESS)
    L.execute("put(\"minecraft:chest_1\", \"minecraft:coal\", 64)")
    L.execute("for i = 1, %d do put(i <= 54 and \"minecraft:chest_0\" or \"minecraft:chest_1\", \"minecraft:cobblestone\", 64) end" % fill)
    L.execute('''FILES[".plots"]='{["next"]=7,["done"]=0,["hunter"]=true,["builderId"]=14,["helpers"]={21,22,23,24},["loaders"]={41,42,43,44},["byId"]={}}'
MAX_IDLES=4
STATUSQ = {}
INBOX = { { id = 77, msg = { type = "need_job", id = 77 } } }''')
    L.eval('{runFactory()}')
    g = L.globals()
    return [dict(m.msg) for m in g.OUTBOX.values() if m.msg.type == "job"]
check("no new plot while the storage is nearly full", plotRun(100) == [])
check("a plot again once there is room", len(plotRun(5)) == 1)

# 12. hauling: storage nearly full, hauling switched on, an idle mate: it is sent with the biggest piles
def haulRun(on, fill, helper_state="idle"):
    L = lupa.LuaRuntime(unpack_returned_tuples=True); L.execute("MODEM_ON=true"); L.execute(HARNESS)
    L.execute('put("minecraft:chest_1", "minecraft:coal", 64)')
    L.execute('for i = 1, %d do put(i <= 54 and "minecraft:chest_0" or "minecraft:chest_1", i %% 3 == 0 and "minecraft:cobbled_deepslate" or "minecraft:cobblestone", 64) end' % fill)
    L.execute('''FILES[".plots"]='{["next"]=7,["done"]=0,["hunter"]=true,["builderId"]=14,["helpers"]={21,22,23,24},["loaders"]={41,42,43,44},["byId"]={},["haul"]={["on"]=%s}}'
MAX_IDLES=4
local function st(id, label, role, state, x, z) return { id = id, msg = { label = label, role = role, state = state, pos = { x = x, y = 80, z = z }, fuel = 900 } } end
STATUSQ = { st(21, "lava1", "helper", "%s", 104, 199) }
INBOX = {}''' % ("true" if on else "false", helper_state))
    L.eval('{runFactory()}')
    g = L.globals()
    return [(m.to, dict(m.msg)) for m in g.OUTBOX.values() if m.msg.direct and m.msg.cmd == "lab"]
out = haulRun(True, 100)
ops = out[0][1]["ops"] if out else ""
check("full and hauling on: the idle mate is sent to the store", len(out) == 1 and out[0][0] == 21, str(out)[:200])
check("with the biggest pile, full stacks, keeping 256 back", "fetch|minecraft:cobblestone=" in ops and ops.count("drop|minecraft:cobblestone|64") >= 4
      and "expect|front|controller" in ops and ops.endswith("handin|") and "minecraft:coal=" not in ops, ops[:200])
check("at most 12 stacks a trip", ops.count("drop|") <= 12, ops.count("drop|"))
check("hauling off: nobody is sent", haulRun(False, 100) == [])
check("room to spare: nobody is sent", haulRun(True, 20) == [])
check("no idle mate: nobody is sent", haulRun(True, 100, "fitting") == [])

# 13. the lava farm: lava low, buckets in stock, an idle mate: sent round the cauldrons
def farmRun(lava, buckets, n=6, state="idle"):
    L = lupa.LuaRuntime(unpack_returned_tuples=True); L.execute("MODEM_ON=true"); L.execute(HARNESS)
    L.execute('put("minecraft:chest_1", "minecraft:coal", 64)')
    if lava: L.execute('put("minecraft:chest_1", "minecraft:lava_bucket", %d)' % lava)
    if buckets: L.execute('put("minecraft:chest_1", "minecraft:bucket", %d)' % buckets)
    L.execute('''FILES[".plots"]='{["next"]=7,["done"]=0,["hunter"]=true,["builderId"]=14,["helpers"]={21,22,23,24},["loaders"]={41,42,43,44},["byId"]={},["lavafarm"]={["n"]=%d,["how"]="place"}}'
MAX_IDLES=4
STATUSQ = { { id = 21, msg = { label = "lava1", role = "helper", state = "%s", pos = { x = 104, y = 80, z = 199 }, fuel = 900 } } }
INBOX = {}''' % (n, state))
    L.eval('{runFactory()}')
    g = L.globals()
    return [(m.to, dict(m.msg)) for m in g.OUTBOX.values() if m.msg.direct and m.msg.cmd == "lab"]
out = farmRun(2, 4)
check("lava low: a mate goes round the farm with the buckets there are", len(out) == 1 and "fetch|minecraft:bucket=4" in out[0][1]["ops"]
      and "collect|-4453|76|1538|6|2|place" in out[0][1]["ops"], str(out)[:200])
check("plenty of lava: nobody goes", farmRun(30, 4) == [])
check("no empty buckets: nobody goes", farmRun(2, 0) == [])
print("PASS" if not fails else "FAILED: %d" % len(fails))
