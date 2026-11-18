"""The storage room's fit plan run by the real helper.lua in the real
building, the way the west wall was left in the world: some limited barrels
dug out by hand (empty spaces), some lying face up (put in from above), a few
right. The rest of the room is as the first fit-out left it.

    python3 test/storewall.py

At the end every barrel, limited barrel and chest stands where the plan has
it with its front to the room (a limited barrel's vertical_facing "no"), the
face-up ones were taken down and put back from the front, and nothing went
on the floor.
"""
import os, re, sys
import lupa

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
fails = []


def check(what, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + what + (f"  [{detail}]" if detail else ""))
    if not ok:
        fails.append(what)


def read_plan(name):
    L = open(os.path.join(ROOT, "blueprints", name + ".txt")).read().split("\n")
    n = int(L[1].split()[1])
    pal = [l.split() for l in L[2:2 + n]]
    ops = [l.split() for l in L[3 + n:] if l]
    return pal, ops


pal, ops = read_plan("factory_storeroom")
want = {}          # (x, y, z) -> (name, facing)
for o in ops:
    if o[0] == "P":
        p = pal[int(o[4])]
        want[(int(o[1]), int(o[2]), int(o[3]))] = (p[0], p[1] if len(p) > 1 and p[1] != "-" else None)
need = {}
for n, f in want.values():
    need[n] = need.get(n, 0) + 1
west = sorted(c for c, (n, f) in want.items() if c[0] == 10 and "limited_barrel" in n)

# the building harness, as the screens test has it
src = open(os.path.join(HERE, "screensfit.py")).read()
harness = src[src.index("      package.path = ROOT"):src.index("    ''')\n    # the monitors")]

# barrels: from the side they face the turtle; from above a limited barrel
# lies face up with a horizontal_facing that still looks right
BARRELS = r'''
local NAMES = { [0] = "east", [1] = "south", [2] = "west", [3] = "north" }
for _, dir in ipairs({ "", "Up", "Down" }) do
  local place = turtle["place" .. dir]
  turtle["place" .. dir] = function()
    local i = T.inv[T.sel]
    local name = i and i.name
    local tx, ty, tz, td = T.x, T.y, T.z, T.d
    local ok, why = place()
    if ok and name and name:find("sophisticatedstorage:", 1, true) == 1 and not name:find("controller") then
      local x, y, z = tx, ty, tz
      if dir == "Up" then y = y + 1 elseif dir == "Down" then y = y - 1
      else x = x + ({ [0] = 1, 0, -1, 0 })[td] z = z + ({ [0] = 0, 1, 0, -1 })[td] end
      local toward = NAMES[(td + 2) % 4]
      local s
      if name:find("limited_barrel", 1, true) then
        s = { horizontal_facing = toward, vertical_facing = dir == "" and "no" or (dir == "Down" and "up" or "down") }
      elseif name:find("barrel", 1, true) then
        s = { facing = dir == "" and toward or (dir == "Down" and "up" or "down") }
      else
        s = { facing = toward }
      end
      STATE[KEY(x, y, z)] = s
    end
    return ok, why
  end
end
'''


def hopto_state():
    """The west wall as builder1 left it running the old plan with xmin=10
    xmax=10: its take-outs done (all but the one at 10 1 4 it could not get
    to), the barrels it put in from the front standing right, the ones it put
    in from above dug out again by hand."""
    L = open(os.path.join(HERE, "storeroom_old.txt")).read().split("\n")
    n = int(L[1].split()[1])
    opal = [l.split() for l in L[2:2 + n]]
    dug, good, empty = [], [], []
    for o in (l.split() for l in L[3 + n:] if l):
        if int(o[1]) != 10:
            continue
        c = (int(o[1]), int(o[2]), int(o[3]))
        if o[0] == "D":
            if c != (10, 1, 4):
                dug.append(c)
        elif "limited_barrel" in opal[int(o[4])][0]:
            (good if int(o[5]) >= 2 else empty).append(c)
    return dug, good, empty


def run(face_up, empty, right, stock_extra=None, cleared=None):
    L = lupa.LuaRuntime(unpack_returned_tuples=True)
    L.execute("START_D=3; START_FUEL=20000")
    L.execute(open(os.path.join(HERE, "harness.lua")).read().replace("/home/claude/turtles", ROOT))
    L.execute(open(os.path.join(HERE, "bworld.lua")).read())
    g = L.globals()
    g.ROOT = ROOT
    g.INSTALL_OK = True
    L.execute(harness)
    L.execute(BARRELS)
    # the west wall: builder1's take-outs there were done; then what is left
    for c in (cleared if cleared is not None else
              [(int(o[1]), int(o[2]), int(o[3])) for o in ops if o[0] == "D" and int(o[1]) == 10]):
        L.execute(f"setSpecial(OX+{c[0]}, OY+{c[1]}, OZ+{c[2]}, false)")
    for c in west:
        if c in empty:
            L.execute(f"setSpecial(OX+{c[0]}, OY+{c[1]}, OZ+{c[2]}, false)")
        else:
            up = c in face_up
            L.execute(f'setSpecial(OX+{c[0]}, OY+{c[1]}, OZ+{c[2]}, "sophisticatedstorage:limited_barrel_1")')
            L.execute(f'STATE[KEY(OX+{c[0]}, OY+{c[1]}, OZ+{c[2]})] = '
                      f'{{ horizontal_facing = "east", vertical_facing = "{"up" if up else "no"}" }}')
    for k, v in need.items():
        L.execute(f'STOCK["{k}"] = {v + 4}')
    for k, v in (stock_extra or {}).items():
        L.execute(f'STOCK["{k}"] = {v}')
    L.execute('STOCK["minecraft:coal"] = 400')
    helper = L.eval(f'loadfile("{ROOT}/helper.lua")')
    go = L.eval('function(f) return {pcall(f)} end')
    L.execute('''FS["helper.state"] = textutils.serialize({ job = { fit = true, plan = "factory_storeroom",
      shell = "factory_asfit3", ox = OX, oy = OY, oz = OZ } })''')
    r = list(go(helper).values())
    return L, g, r


def at(L, c):
    b = L.eval(f"getBlock(OX+{c[0]}, OY+{c[1]}, OZ+{c[2]})")
    s = L.eval(f"STATE[KEY(OX+{c[0]}, OY+{c[1]}, OZ+{c[2]})]")
    return b, (dict(s.items()) if s else {})


def front(s):
    v = s.get("vertical_facing")
    if v not in (None, "no"):
        return v
    return s.get("facing") or s.get("horizontal_facing")


def final_check(L, g, r, face_up, label):
    check(f"{label}: the run ends waiting for the next job", r == [False, "IDLE"], str(r))
    log = list(g.LOG.values())
    left = [l for l in log if l.startswith("Left:")]
    check(f"{label}: no job left undone", not left and "Fit-out finished." in log, str(left[:4]) + " " + str(log[-3:]))
    wrong = []
    for c, (n, f) in want.items():
        if not n.startswith("sophisticatedstorage:") or n.endswith("controller"):
            continue
        b, s = at(L, c)
        if b != n or (f and front(s) != f) or s.get("vertical_facing", "no") != "no":
            wrong.append((c, b, s))
    check(f"{label}: every barrel and chest stands with its front to the room", not wrong, str(wrong[:3]))
    check(f"{label}: nothing dropped on the floor", not g.FLOOR, str(g.FLOOR))
    return dict(g.DUG.items())


# ---------------------------------------------------------------- the room as it is in the world
dug, good, gone = hopto_state()
print(f"     west wall: {len(good)} barrels standing right, {len(gone)} dug out by hand")
L, g, r = run(set(), set(gone), set(good), cleared=dug)
d = final_check(L, g, r, set(), "from the world as it is")
check(f"the {len(good)} barrels already standing right were not dug",
      d.get("sophisticatedstorage:limited_barrel_1", 0) == 0, str(d.get("sophisticatedstorage:limited_barrel_1")))
L.execute('''FS["helper.state"] = textutils.serialize({ job = { fit = true, plan = "factory_storeroom",
  shell = "factory_asfit3", ox = OX, oy = OY, oz = OZ } })
DUG, PLACED = {}, {}''')
r2 = list(L.eval('function(f) return {pcall(f)} end')(L.eval(f'loadfile("{ROOT}/helper.lua")')).values())
d2 = {k: v for k, v in dict(g.DUG.items()).items() if "sophisticatedstorage" in k}
check("from the world as it is: run again, no barrel or chest is touched", r2 == [False, "IDLE"] and not d2, f"{r2} {d2}")

# ---------------------------------------------------------------- face-up barrels still standing
face_up = set(west[::2])                 # every other one lies face up
empty = set(west[1::4])                  # some dug out by hand
right = set(west) - face_up - empty
L, g, r = run(face_up, empty, right)
check("the run ends waiting for the next job", r == [False, "IDLE"], str(r))
log = list(g.LOG.values())
left = [l for l in log if l.startswith("Left:")]
check("no job left undone", not left and "Fit-out finished." in log, str(left[:4]) + " " + str(log[-3:]))
wrong = []
for c, (n, f) in want.items():
    if not n.startswith("sophisticatedstorage:") or n.endswith("controller"):
        continue
    b, s = at(L, c)
    if b != n or (f and front(s) != f) or s.get("vertical_facing", "no") != "no":
        wrong.append((c, b, s))
stores = sum(1 for n, f in want.values() if n.startswith("sophisticatedstorage:") and not n.endswith("controller"))
check(f"all {stores} barrels and chests stand with their front to the room", not wrong, str(wrong[:3]))
dug = dict(g.DUG.items())
check(f"the {len(face_up)} face-up barrels were taken down (and put back)",
      dug.get("sophisticatedstorage:limited_barrel_1", 0) >= len(face_up), str(dug.get("sophisticatedstorage:limited_barrel_1")))
check("nothing dropped on the floor", not g.FLOOR, str(g.FLOOR))

# a second run changes no barrel
L.execute('''FS["helper.state"] = textutils.serialize({ job = { fit = true, plan = "factory_storeroom",
  shell = "factory_asfit3", ox = OX, oy = OY, oz = OZ } })
DUG, PLACED = {}, {}''')
go = L.eval('function(f) return {pcall(f)} end')
r2 = list(go(L.eval(f'loadfile("{ROOT}/helper.lua")')).values())
dug2 = {k: v for k, v in dict(g.DUG.items()).items() if "sophisticatedstorage" in k}
check("run again, no barrel or chest is touched", r2 == [False, "IDLE"] and not dug2, f"{r2} {dug2}")

print()
print("FAILED: " + ", ".join(fails) if fails else "PASS")
sys.exit(1 if fails else 0)
