# The factory pairs chunk loaders with far-off turtles and sends fuel to a
# stranded one. Runs from anywhere:  python3 test/pairtest.py
import os, lupa
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(HERE)
HARNESS = open(os.path.join(HERE, 'fharness.lua')).read().replace('/home/claude/turtles', ROOT)
fails = []
def check(what, ok):
    print(("ok   " if ok else "FAIL ") + what)
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
PARKED = 'ST(51, "ChunkNorris", "loader", "parked", 104, 199, { job = { mode = "park" } }), ST(52, "LoadRunner", "loader", "parked", 104, 199, { job = { mode = "park" } })'
ASK = '{ id = 52, wait = true, msg = { type = "escort_request", id = 52, label = "LoadRunner" } }'

# 1. two loaders parked, a miner working far away: the one that asks goes out with it
out, log, r = run(PARKED + ', ST(9, "OreLando", "miner", "mining", %s)' % FAR, ASK)
check("sent out with the far miner, as a direct order", len(out) == 1 and out[0][0] == 52 and out[0][1]["cmd"] == "escort"
      and out[0][1]["who"] == "OreLando" and out[0][1]["auto"] and out[0][1]["forId"] == 52 and out[0][1]["x"] == 1100)
check("on the order channel, with a nonce", out and out[0][1]["nonce"] is not None)

# 2. the only loader at the base stays, whoever is out there
out, log, r = run('ST(52, "LoadRunner", "loader", "parked", 104, 199, { job = { mode = "park" } }), ST(9, "OreLando", "miner", "mining", %s)' % FAR, ASK)
check("the last loader at the base is never sent", out == [])

# 3. both ask at once: one goes, one stays
out, log, r = run(PARKED + ', ST(9, "OreLando", "miner", "mining", %s), ST(10, "ElvisPitsley", "miner", "mining", %s)' % (FAR, FAR),
    ASK + ', { id = 51, wait = true, msg = { type = "escort_request", id = 51, label = "ChunkNorris" } }')
check("two ask, two far miners, two loaders: only one is sent", len(out) == 1)

# 4. nobody needs one: miners near the base, parked far away, already escorted, or carrying their own
out, log, r = run(PARKED + ', ST(9, "OreLando", "miner", "mining", %s), ST(10, "QuarryStyles", "miner", "parked", %s), ' % (NEARBY, FAR)
    + 'ST(11, "NatKingCoal", "miner", "hunting coal", %s), ST(53, "ChunkBerry", "loader", "escorting", %s, { job = { mode = "escort", who = "NatKingCoal" } }), ' % (FAR, FAR)
    + 'ST(12, "BoulderDash", "miner", "mining", %s, { chunky = "carried" })' % FAR, ASK)
check("near, resting, escorted and self-loading turtles need no loader", out == [])

# 5. three loaders, two far miners, one already taken: the other one is offered; the farther first
out, log, r = run(PARKED + ', ST(9, "OreLando", "miner", "mining", 400, 200), ST(10, "ElvisPitsley", "miner", "mining", 900, 200), '
    + 'ST(53, "ChunkBerry", "loader", "escorting", 900, 200, { job = { mode = "escort", who = "ElvisPitsley" } })', ASK)
check("the one without a loader is chosen", len(out) == 1 and out[0][1]["who"] == "OreLando")
out, log, r = run(PARKED + ', ST(9, "OreLando", "miner", "mining", 400, 200), ST(10, "ElvisPitsley", "miner", "mining", 900, 200)', ASK)
check("farthest first", len(out) == 1 and out[0][1]["who"] == "ElvisPitsley")

# 6. a loader that found nothing over a turtle is not sent to it again
out, log, r = run(PARKED + ', ST(9, "CoalPorter", "miner", "hunting coal", %s)' % FAR,
    '{ id = 52, wait = true, msg = { type = "escort_request", id = 52, label = "LoadRunner", gaveUp = "CoalPorter" } }')
check("gave up on it: not offered again", out == [])

# 7. a far turtle gone quiet (frozen in an unloaded chunk) comes first, even one with its own controller
out, log, r = run('ST(9, "CoalPorter", "miner", "hunting coal", 600, 200, { chunky = "carried" }), '
    + '{ id = 51, at = 300, msg = { label = "ChunkNorris", role = "loader", state = "parked", pos = { x = 104, y = 80, z = 199 } } }, '
    + '{ id = 10, at = 300, msg = { label = "OreLando", role = "miner", state = "mining", pos = { x = 1100, y = 30, z = 1200 } } }',
    '{ id = 52, at = 310, msg = { type = "escort_request", id = 52, label = "LoadRunner" } }', idles=600)
check("the silent one first", len(out) == 1 and out[0][1]["who"] == "CoalPorter")

# 8. fuel for a stranded loader: the idle mate with most fuel is sent, once
HELPERS = 'ST(21, "MortarKombat", "helper", "idle", 104, 205, { fuel = 484 }), ST(22, "WallStreet", "helper", "idle", 106, 205, { fuel = 237 }), ST(23, "SteelyDan", "helper", "building", 150, 205, { fuel = 5000 })'
FEED = '{ id = 52, wait = true, msg = { type = "feed_request", id = 52, label = "LoadRunner", x = 104, y = 70, z = 199, fuel = 78 } }'
out, log, r = run(HELPERS, FEED + ', ' + FEED)
check("an idle mate takes fuel there (once)", len(out) == 1 and out[0][0] == 21 and out[0][1]["cmd"] == "feed"
      and (out[0][1]["x"], out[0][1]["y"], out[0][1]["z"]) == (104, 70, 199))
out, log, r = run('ST(23, "SteelyDan", "helper", "building", 150, 205, { fuel = 5000 })', FEED)
check("no mate free: nobody is pulled off a job", out == [] and any("No builder's mate free" in l for l in log))
print("PASS" if not fails else "FAILED: %d" % len(fails))
