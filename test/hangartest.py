# The new hangar (helper.lua HG; swarm.lua M.HANGAR; docs/new-site.md): a
# helper comes in over the back of the building, down outside the gate,
# through it to the aisle, along to its column and row, and three steps
# south into its berth; it leaves by the gate's other side before climbing.
# A mini world of the rebuilt factory's back: the building solid but for the
# gate, the hangar's air (with the lights, catwalks and pulley that are in
# it) and the berths. Run from inside test/.
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
hangar = SWA[SWA.index("M.HANGAR = {"):]
hangar = hangar[:hangar.index("} }\n") + 4]

WORLD = r'''
OPEN, SOLID, PATH, BUMPS = {}, {}, {}, 0
local function k(x, y, z) return x .. "," .. y .. "," .. z end
-- the hangar's air: x -4440..-4413, y 78..89, z 1523..1526; the gate; the berths
for x = -4440, -4413 do for y = 78, 89 do for z = 1523, 1526 do OPEN[k(x, y, z)] = true end end end
for x = -4430, -4423 do for y = 78, 81 do OPEN[k(x, y, 1522)] = true end end
COLS, ROWS = { -4439, -4437, -4435, -4433, -4420, -4418, -4416, -4414 }, { 78, 83, 88 }
for _, x in ipairs(COLS) do for _, y in ipairs(ROWS) do OPEN[k(x, y, 1527)] = true end end
-- what stands in that air (surveyed): lights at y 80 and 85 (z 1525, 1526),
-- catwalks at y 82 and 87 (z 1526), the pulley at y 88 and 89 (z 1523)
for x = -4440, -4413 do
  for _, y in ipairs({ 80, 85 }) do OPEN[k(x, y, 1525)] = nil OPEN[k(x, y, 1526)] = nil end
  for _, y in ipairs({ 82, 87 }) do OPEN[k(x, y, 1526)] = nil end
  for _, y in ipairs({ 88, 89 }) do OPEN[k(x, y, 1523)] = nil end
end
function solid(x, y, z)
  local key = k(x, y, z)
  if SOLID[key] then return true end
  if OPEN[key] then return false end
  if y <= 70 then return true end                                              -- the ground
  return x >= -4474 and x <= -4378 and z >= 1522 and z <= 1556 and y <= 136    -- the building
end
T = { x = 0, y = 0, z = 0, d = 0 }
DX, DZ = { [0] = 1, 0, -1, 0 }, { [0] = 0, 1, 0, -1 }
local function moveTo(x, y, z, how)
  if solid(x, y, z) then BUMPS = BUMPS + 1 return false, "blocked" end
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
LABEL, ID = "builder1", 9
os = { getComputerLabel = function() return LABEL end, getComputerID = function() return ID end, clock = function() return 0 end }
'''

L = lupa.LuaRuntime(unpack_returned_tuples=True)
L.execute(WORLD)
L.execute("M = {} " + hangar)
L.execute('''
local DIRS = { [0] = { x = 1, z = 0 }, [1] = { x = 0, z = 1 }, [2] = { x = -1, z = 0 }, [3] = { x = 0, z = -1 } }
local pos, heading = { x = 0, y = 0, z = 0 }, 0
local st, base = {}, nil
local OVER_SITE = 36
''' + part1 + part2 + '''
function SET(b, x, y, z) base = b pos.x, pos.y, pos.z = x, y, z T.x, T.y, T.z = x, y, z heading = 0 T.d = 0 PATH = {} BUMPS = 0 end
function POS() return pos.x, pos.y, pos.z end
API = { LN = LN, HG = HG, riseTo = riseTo, highway = highway }
''')

BASE = '''{ f = { x = -4442, y = 73, z = 1519 }, pad = { x = -4441, y = 73, z = 1519 },
  exit1 = { x = -4441, z = 1519 }, exit2 = { x = -4441, z = 1519 }, hoverUp = 20, hangar = M.HANGAR }'''
api = L.eval("API")
pos = lambda: tuple(L.eval("{POS()}").values())
HOME = (-4437, 78, 1527)          # builder1: berth 1, bottom row, second column


def path():
    return [dict(p) for p in L.eval("PATH").values()]


def run(start, fn, *args, base=BASE):
    L.execute("SET(%s, %d, %d, %d)" % (base, *start))
    r = fn(*args)
    return r, pos(), path(), L.eval("BUMPS")


def in_gate(p):
    return p["z"] == 1522


# 1. from up in the sky outside, into its berth
r, at, ps, bumps = run((-4420, 170, 1490), api.HG.toHome)
check("in from the sky: into its berth (builder1: bottom row, second column)", r and at == HOME, (at, L.eval("API.LN.why")))
check("  through the gate on the inbound line (x -4429, y 79)",
      any(in_gate(p) for p in ps) and all(p["x"] == -4429 and p["y"] == 79 for p in ps if in_gate(p)),
      [p for p in ps if in_gate(p)][:3])
check("  down outside the gate, not through the roof", all(p["z"] <= 1520 for p in ps if p["y"] > 89), None)
check("  without bumping into anything", bumps == 0, bumps)
check("  the last three steps south into the berth", [p["z"] for p in ps[-3:]] == [1525, 1526, 1527]
      and all(p["how"] == "f" and p["d"] == 1 for p in ps[-3:]), ps[-3:])
check("HG.inside() in the berth", L.eval("API.HG.inside()") is True)

# 2. out again: by the gate's other side, top row
r, at, ps, bumps = run(HOME, api.HG.exit)
check("out: north of the gate on the outbound line", r and at == (-4424, 81, 1520), at)
check("  through the gate at x -4424, y 81", all(p["x"] == -4424 and p["y"] == 81 for p in ps if in_gate(p)),
      [p for p in ps if in_gate(p)][:3])
check("  without bumping into anything", bumps == 0, bumps)
check("HG.inside() is false outside the gate", L.eval("API.HG.inside()") is False)

# 3. off to a job from the berth: out of the gate before climbing
hw = api.highway()
r, at, ps, bumps = run(HOME, api.riseTo, hw)
check("off to a job: out of the gate, then straight up outside", r and at == (-4424, hw, 1520) and bumps == 0, (at, bumps))
check("  no climbing above the gate inside the hangar", all(p["z"] <= 1520 for p in ps if p["y"] > 81 and p["how"] == "u"),
      [p for p in ps if p["y"] > 81 and p["how"] == "u" and p["z"] > 1520][:3])

# 4. the upper rows, and both banks; berths by name
for label, home in (("builder11", (-4416, 83, 1527)), ("lava1", (-4439, 78, 1527)), ("survey1", (-4414, 78, 1527)),
                    ("builder6", (-4439, 83, 1527))):
    L.execute('LABEL = "%s"' % label)
    check("%s's berth is %s" % (label, home,), tuple(L.eval("{API.HG.home()}").values()) == home,
          tuple(L.eval("{API.HG.home()}").values()))
    r, at, ps, bumps = run((-4500, 170, 1500), api.HG.toHome)
    check("  and it gets in, bumping into nothing", r and at == home and bumps == 0, (at, bumps, L.eval("API.LN.why")))
    r, at, ps, bumps = run(home, api.HG.exit)
    check("  and out again", r and at == (-4424, 81, 1520) and bumps == 0, (at, bumps))
L.execute('LABEL = "builder1"')

# 5. a helper with no name on the list: a berth past the named ones (the top row), by id
L.execute('LABEL = "somebody" ID = 9')
check("an unnamed helper (id 9): top row, second column", tuple(L.eval("{API.HG.home()}").values()) == (-4437, 88, 1527),
      tuple(L.eval("{API.HG.home()}").values()))
r, at, ps, bumps = run((-4420, 170, 1490), api.HG.toHome)
check("  and it gets in, under the pulley's side of the aisle", r and at == (-4437, 88, 1527) and bumps == 0, (at, bumps))
L.execute('LABEL = "builder1" ID = 9')

# 6. every berth can be reached and left without touching anything
bad = []
for i in range(24):
    L.execute('LABEL = "nobody" ID = %d' % (i - 16 if i >= 16 else 0))
    names = ["lava1", "builder1", "builder7", "foundry1", "builder3", "builder4", "builder2", "survey1", "builder6", "rescue1",
             "builder5", "builder8", "builder9", "builder10", "builder11", "builder12"]
    if i < 16:
        L.execute('LABEL = "%s"' % names[i])
    home = tuple(L.eval("{API.HG.home()}").values())
    r, at, ps, bumps = run((-4420, 170, 1490), api.HG.toHome)
    r2, at2, ps2, bumps2 = run(home, api.HG.exit)
    if not (r and at == home and bumps == 0 and r2 and at2 == (-4424, 81, 1520) and bumps2 == 0):
        bad.append((i, home, at, bumps, at2, bumps2))
check("all 24 berths: in and out, bumping into nothing", not bad, bad[:3])
L.execute('LABEL = "builder1" ID = 9')
homes = set()
for i in range(8):
    L.execute('LABEL = "nobody" ID = %d' % i)
    homes.add(tuple(L.eval("{API.HG.home()}").values()))
check("eight unnamed ids: eight different berths, all on the top row", len(homes) == 8 and all(h[1] == 88 for h in homes), homes)
L.execute('LABEL = "builder1" ID = 9')

# 7. from one place in the hangar to its berth: back to the aisle first
r, at, ps, bumps = run((-4414, 88, 1527), api.HG.toHome)
check("from another berth: by the aisle to its own", r and at == HOME and bumps == 0, (at, bumps))

# 8. its berth taken: it says what is in the way and where, and it can still leave
L.execute("SOLID['-4437,78,1527'] = true")
L.execute("SET(%s, -4420, 170, 1490)" % BASE)
L.execute("API.LN.why = nil")
ok = L.eval("API.HG.toHome()")
check("a taken berth: not docked, and LN.why says what and where", ok is False
      and "-4437 78 1527" in str(L.eval("API.LN.why")), L.eval("API.LN.why"))
check("  it waits in front of the berth, in the hangar", pos() == (-4437, 78, 1526) and L.eval("API.HG.inside()") is True, pos())
ok = L.eval("API.HG.exit()")
check("  and gets out again by the gate", ok and pos() == (-4424, 81, 1520), pos())
L.execute("SOLID['-4437,78,1527'] = nil")

# 9. the gate shut (the door down): it stops outside and says so
for x in range(-4430, -4422):
    for y in range(78, 82):
        L.execute("SOLID['%d,%d,1522'] = true" % (x, y))
L.execute("SET(%s, -4420, 170, 1490)" % BASE)
L.execute("API.LN.why = nil")
ok = L.eval("API.HG.toHome()")
check("the gate shut: not docked, stopped outside it", ok is False and pos()[2] == 1521 and pos()[1] == 79, pos())
check("  and LN.why names the gate cell", "-4429 79 1522" in str(L.eval("API.LN.why")), L.eval("API.LN.why"))
for x in range(-4430, -4422):
    for y in range(78, 82):
        L.execute("SOLID['%d,%d,1522'] = nil" % (x, y))

# 10. inert: no hangar known, nothing changes
NOH = BASE.replace("hangar = M.HANGAR", "hangar = nil")
L.execute("SET(%s, -4437, 78, 1527)" % NOH)
check("no hangar known: HG.inside() is false", L.eval("API.HG.inside()") is False)
L.execute("API.LN.why = nil")
check("  and HG.toHome() says so", L.eval("API.HG.toHome()") is False and L.eval("API.LN.why") == "no hangar known",
      L.eval("API.LN.why"))

print("PASS" if not fails else "FAILED: %d" % len(fails))
