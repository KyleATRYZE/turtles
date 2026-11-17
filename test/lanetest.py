# The drone lane (helper.lua LN, inert until a rebase order with lane=1):
# helpers come in by the west gate (front track, eastbound) or the east gate
# (back track, westbound), stop at a pad from the side, and wait in their
# home in the rack. A mini world of the factory: the building solid but for
# the lane, the rack homes and the pads; the pit stops' machines in the way.
# Run from inside test/.
import os, lupa

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
HEL = open(os.path.join(ROOT, "helper.lua")).read()
SWA = open(os.path.join(ROOT, "swarm.lua")).read()
fails = []


def check(what, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + what + ("" if ok else "  " + str(detail)))
    if not ok:
        fails.append(what)


part1 = HEL[HEL.index("local function face(d)"):HEL.index("local function gpsHere()")]
part2 = HEL[HEL.index("-- The drone lane (filled in"):HEL.index("-- Station computers")]
lane = SWA[SWA.index("M.LANE = {"):]
lane = lane[:lane.index("}\n") + 2]

WORLD = r'''
local C = { x = -4448, y = 71, z = 1518 }
local function B(x, y, z) return C.x + x, C.y + y, C.z + z end
OPEN, SOLID, PATH = {}, {}, {}
local function k(x, y, z) return x .. "," .. y .. "," .. z end
local function open(x, y, z) OPEN[k(B(x, y, z))] = true end
local function shut(x, y, z) SOLID[k(B(x, y, z))] = true end
for x = 0, 44 do for y = 1, 3 do for z = 1, 2 do open(x, y, z) end end end     -- the lane
for i = 0, 7 do open(19 + i, 1, 3) open(19 + i, 3, 3) end                      -- rack 1
for _, c in ipairs({ { 2, 2, 1 }, { 5, 2, 1 }, { 6, 2, 1 },                     -- Counter, drop chest, Crafty
  { 2, 1, 1 }, { 3, 1, 1 }, { 5, 1, 1 }, { 6, 1, 1 }, { 7, 1, 1 } }) do         -- modems, drives, block
  shut(c[1], c[2], c[3])
end
function solid(x, y, z)
  local key = k(x, y, z)
  if SOLID[key] then return true end
  if OPEN[key] then return false end
  if y <= C.y then return true end                                            -- the ground
  local bx, by, bz = x - C.x, y - C.y, z - C.z
  return bx >= 0 and bx <= 44 and bz >= 0 and bz <= 33 and by <= 8             -- the building
end
T = { x = 0, y = 0, z = 0, d = 0 }
DX, DZ = { [0] = 1, 0, -1, 0 }, { [0] = 0, 1, 0, -1 }
local function moveTo(x, y, z, how)
  if solid(x, y, z) then return false, "blocked" end
  T.x, T.y, T.z = x, y, z
  PATH[#PATH + 1] = { x = x, y = y, z = z, how = how, d = T.d }
  return true
end
turtle = {
  forward = function() return moveTo(T.x + DX[T.d], T.y, T.z + DZ[T.d], "f") end,
  up = function() return moveTo(T.x, T.y + 1, T.z, "u") end,
  down = function() return moveTo(T.x, T.y - 1, T.z, "d") end,
  turnRight = function() T.d = (T.d + 1) % 4 return true end,
  turnLeft = function() T.d = (T.d + 3) % 4 return true end,
  inspect = function() return true, { name = "minecraft:stone" } end,
  inspectUp = function() return true, { name = "minecraft:stone" } end,
  inspectDown = function() return true, { name = "minecraft:stone" } end,
  detect = function() return true end, detectUp = function() return true end, detectDown = function() return true end,
  dig = function() return false end, digUp = function() return false end, digDown = function() return false end,
}
function sleep() end
function print() end
function fuel() return 10000 end
function refuel() end
function report() end
function tick() end
LABEL = "HopTo"
os = { getComputerLabel = function() return LABEL end, getComputerID = function() return 9 end, clock = function() return 0 end }
'''

L = lupa.LuaRuntime(unpack_returned_tuples=True)
L.execute(WORLD)
L.execute("M = {} " + lane)
L.execute('''
local DIRS = { [0] = { x = 1, z = 0 }, [1] = { x = 0, z = 1 }, [2] = { x = -1, z = 0 }, [3] = { x = 0, z = -1 } }
local pos, heading = { x = 0, y = 0, z = 0 }, 0
local st, base = {}, nil
local OVER_SITE = 36
''' + part1 + part2 + '''
function SET(b, x, y, z) base = b pos.x, pos.y, pos.z = x, y, z T.x, T.y, T.z = x, y, z heading = 0 T.d = 0 PATH = {} end
function POS() return pos.x, pos.y, pos.z end
API = { LN = LN, hover = hover, goHover = goHover, downToPad = downToPad, upFromPad = upFromPad,
  overPad = overPad, riseTo = riseTo, highway = highway, setPadAt = function(p) padAt = p end }
''')

BASE = '''{ f = { x = -4442, y = 73, z = 1519 }, pad = { x = -4441, y = 73, z = 1519 },
  exit1 = { x = -4441, z = 1519 }, exit2 = { x = -4441, z = 1519 }, hoverUp = 20, lane = LANE }'''
L.execute("LANE = {} for k, v in pairs(M.LANE) do LANE[k] = v end")
api = L.eval("API")
pos = lambda: tuple(L.eval("{POS()}").values())
CRAFTY_PAD, COUNTER_PAD = (-4441, 73, 1519), (-4445, 73, 1519)
HOME = (-4428, 72, 1521)          # HopTo: home 1, low row


def path():
    return [dict(p) for p in L.eval("PATH").values()]


def tracks_ok(steps):
    """inside the building, along the tracks: back track westbound only, front track eastbound only"""
    bad = []
    for p in steps:
        inside = -4448 <= p["x"] <= -4404
        if p["how"] != "f" or not inside:
            continue
        if p["z"] == 1519 and p["d"] == 0:
            bad.append(("east on the back track", p))
        if p["z"] == 1520 and p["d"] == 2:
            bad.append(("west on the front track", p))
    return bad


def run(start, fn, *args, lane=True):
    L.execute("SET(%s, %d, %d, %d)" % (BASE if lane else BASE.replace("lane = LANE", "lane = nil"), *start))
    r = fn(*args)
    return r, pos(), path()


# 1. idle: from up in the sky outside, home into the rack by the west gate
r, at, ps = run((-4420, 140, 1490), api.goHover)
check("idle: into its home in the rack (HopTo: low row, second home)", r and at == HOME, at)
check("  in by the west gate, at lane height", any(p["x"] == -4448 and p["z"] == 1520 and p["y"] == 73 for p in ps))
check("  along the tracks the right way", not tracks_ok(ps), tracks_ok(ps)[:3])
check("hover() is the home in the rack", tuple(L.eval("{API.hover()}").values()) == HOME)

# 2. a load: from home to Crafty's pad, from the side
r, at, ps = run(HOME, api.downToPad)
check("load ready: home to Crafty's pad", r and at == CRAFTY_PAD, at)
check("  onto the pad sideways (the last step level, westbound on the back track)",
      ps[-1]["how"] == "f" and ps[-1]["d"] == 2, ps[-3:])
check("  along the tracks the right way", not tracks_ok(ps), tracks_ok(ps)[:3])

# 3. off the pad and home again
r, at, ps = run(CRAFTY_PAD, api.upFromPad)
check("off the pad: a step south onto the front track", r and at == (-4441, 73, 1520), at)
r, at, ps = run(at, api.goHover)
check("then east along the front track to its home", r and at == HOME and not tracks_ok(ps), (at, tracks_ok(ps)[:3]))

# 4. the Counter's pad, beyond Crafty's stop: over it, a block higher
api.setPadAt(L.eval("{ pad = { x = -4445, y = 73, z = 1519 }, f = { x = -4446, y = 73, z = 1519 } }"))
r, at, ps = run(HOME, api.downToPad)
check("the Counter's pad: home to it, over Crafty's stop", r and at == COUNTER_PAD
      and all(p["y"] == 74 for p in ps if p["z"] == 1519 and -4443 <= p["x"] <= -4441 and p["how"] == "f"), at)
check("  along the tracks the right way", not tracks_ok(ps), tracks_ok(ps)[:3])
r, at, ps = run(COUNTER_PAD, api.upFromPad)
r2, at2, ps2 = run(at, api.goHover)
check("  and home from it along the front track", r and r2 and at2 == HOME and not tracks_ok(ps2), at2)
api.setPadAt(None)

# 5. from a job out east: in by the east gate on the back track
r, at, ps = run((-4380, 130, 1540), api.downToPad)
check("from the east: in by the east gate, on the back track", r and at == CRAFTY_PAD
      and any(p["x"] == -4404 and p["z"] == 1519 and p["y"] == 73 for p in ps), at)
check("  along the tracks the right way", not tracks_ok(ps), tracks_ok(ps)[:3])

# 6. from a job out west: in by the west gate on the front track, north onto the pad
r, at, ps = run((-4500, 130, 1500), api.downToPad)
check("from the west: in by the west gate on the front track, a step north onto the pad",
      r and at == CRAFTY_PAD and ps[-1]["d"] == 3 and any(p["x"] == -4448 and p["z"] == 1520 for p in ps), at)
check("  along the tracks the right way", not tracks_ok(ps), tracks_ok(ps)[:3])

# 7. off to a job from home: out by the east gate, then up
hw = api.highway()
r, at, ps = run(HOME, api.riseTo, hw)
check("off to a job: out of the east gate before climbing", r and at[1] == hw and at[0] == -4402
      and all(p["how"] != "u" or p["x"] > -4404 or p["y"] <= 74 for p in ps), at)
check("  along the tracks the right way", not tracks_ok(ps), tracks_ok(ps)[:3])

# 8. setting something on the pad: the row over it
r, at, ps = run(HOME, api.overPad)
check("over the pad (to set a computer down): just above it", r and at == (-4441, 74, 1519), at)

# 9. a second home row; homes by name
L.execute('LABEL = "NoteWorthy"')
check("home 14 (NoteWorthy): high row", tuple(L.eval("{API.hover()}").values()) == (-4423, 74, 1521))
r, at, ps = run((-4420, 140, 1490), api.goHover)
check("  and it gets in", r and at == (-4423, 74, 1521), at)
L.execute('LABEL = "HopTo"')

# 10. inert: no lane in .base, the old hover in the sky
L.execute("SET(%s, 0, 0, 0)" % BASE.replace("lane = LANE", "lane = nil"))
check("no lane (before the rebase): hover in the air as before",
      tuple(L.eval("{API.hover()}").values()) == (-4441 + 3 + 2, 73 + 20, 1519 - 4), tuple(L.eval("{API.hover()}").values()))
check("  and riseTo climbs straight up", L.eval("API.LN.inside()") is False)

print("PASS" if not fails else "FAILED: %d" % len(fails))
