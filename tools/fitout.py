#!/usr/bin/env python3
"""Work out the fit-out: everything that turns the bare shell into the
finished factory, in an order a turtle can actually do it.

Compares blueprints/factory.json (the finished building) with
blueprints/factory_shell.txt (what the builders put up) and writes
blueprints/factory_fitout.txt:

  P <n>            then n lines: <block name> <facing or ->
  O <m>            then m lines, one job each, in order:
     D x y z s           dig the block there (a doorway, a porthole)
     P x y z i s         put palette block i there
     R x y z i s         dig what is there and put block i (the lane's floor)
  s = where the turtle stands to do it: 0 above (works downwards), 1 below
  (works upwards), 2 east, 3 south, 4 west, 5 north of the block (works
  forwards, facing it).

The order comes from taking the finished building apart: a fitting can be
taken out when a turtle can get to a free spot beside it; whatever comes
out last has to go in first. Hanging things go in after what they hang
from. Then the whole list is replayed from the bare shell to make sure
every job can be reached when its turn comes.
"""
import json, os, re, sys
from collections import Counter
import numpy as np
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
# fitout.py [<final.json> <shell.txt> <out.txt> <start x,y,z> [glass] [swaps] [redo] [box=...] [skip=...]
#             [only=name,...] [refit=name,...] [notbox=...]]
ARGS = sys.argv[1:]
F_FINAL = ARGS[0] if ARGS else os.path.join(ROOT, "blueprints", "factory.json")
F_SHELL = ARGS[1] if ARGS else os.path.join(ROOT, "blueprints", "factory_shell.txt")
F_OUT = ARGS[2] if ARGS else os.path.join(ROOT, "blueprints", "factory_fitout.txt")
START = tuple(map(int, ARGS[3].split(","))) if ARGS else (22, 2, 33)   # outside the big door
GLASS_TOO = len(ARGS) > 4 and ARGS[4] == "glass"    # a touch-up pass: the windows the builders left out
bp = json.load(open(F_FINAL))

def split(full):
    m = re.match(r"([^\[]+)(?:\[(.*)\])?", full)
    props = dict(p.split("=") for p in (m.group(2) or "").split(",") if p)
    return m.group(1), props.get("facing", "-")

final = {(x, y, z): split(bp["palette"][i]) for x, y, z, i in bp["blocks"]}

shell, mode, spal = {}, None, []
for line in open(F_SHELL):
    t = line.split()
    if t[0] in "PB" and len(t) == 2 and t[1].isdigit():
        mode = t[0]
    elif mode == "P":
        spal.append((t[0], t[1]))
    else:
        x, y, z, i = map(int, t)
        shell[(x, y, z)] = spal[i]

def _opt(key):
    for arg in ARGS[4:]:
        if arg.startswith(key + "="):
            return arg[len(key) + 1:]
# refit=name,name : these fittings are checked and made good, each from the
# side the plan says (a monitor put in from above lies on its back): they
# are taken as not standing, so every one becomes a job; the turtle leaves
# alone the ones it finds right
REFIT = set((_opt("refit") or "").split(",")) - {""}
for c in [c for c, v in shell.items() if v[0] in REFIT and c in final and final[c][0] == v[0]]:
    del shell[c]
# open=x,y,z : a sealed room (the tower's upper floors have no way in for a
# turtle once fitted): that block is dug out first and put back last
OPEN = [tuple(map(int, c.split(","))) for c in (_opt("open") or "").split(";") if c]
OPENED = []
for c in OPEN:
    if c in shell and c in final:
        OPENED.append((c, shell.pop(c)))
# the side a fitting has to be worked from, where the plan says ("stands")
MUST = {tuple(map(int, k.split(","))): v for k, v in bp.get("stands", {}).items()}

# ---------------------------------------------------------------- what changes
SKIP = {"computercraft:turtle_advanced", "computercraft:turtle_normal",      # drones place themselves
        "computercraft:computer_advanced", "advancedperipherals:chat_box",   # carried over by hand
        "advancedperipherals:player_detector", "computercraft:disk_drive",
        "minecraft:glass_pane", "minecraft:glass"}                            # the builders' own second go
if GLASS_TOO:
    SKIP -= {"minecraft:glass_pane", "minecraft:glass"}
SKIP -= {v[0] for c, v in OPENED}                 # (the way in is put back, whatever it is made of)
digs, puts, swaps = [], [], []
BOX = None
for c, (name, facing) in shell.items():
    if c[1] < 0:
        continue                                   # foundation
    f = final.get(c)
    if f is None:
        digs.append(c)
    elif f[0] != name and f[0] not in SKIP:
        swaps.append(c)
for c, (name, facing) in final.items():
    if c not in shell and name not in SKIP:
        puts.append(c)
if "swaps" in ARGS[4:]:                             # a floor job: nothing but the swaps
    digs, puts = [], []
# one room only: box=x0,y0,z0,x1,y1,z1 keeps the jobs inside it; skip=name,name
# leaves those blocks to be put in by hand (or by a lab run)
for arg in ARGS[4:]:
    if arg.startswith("skip="):
        left_out = set(arg[5:].split(","))
        puts = [c for c in puts if final[c][0] not in left_out]
        swaps = [c for c in swaps if final[c][0] not in left_out]
        SKIP |= left_out
    if arg.startswith("box="):
        bx = list(map(int, arg[4:].split(",")))
        def inside(c):
            return all(bx[k] <= c[k] <= bx[k + 3] for k in range(3))
        digs, puts, swaps = [c for c in digs if inside(c)], [c for c in puts if inside(c)], [c for c in swaps if inside(c)]
        BOX = inside
# only=name,name : nothing but these fittings (and no digging out);
# notbox=x0,y0,z0,x1,y1,z1 : leave that room to another plan
if _opt("only"):
    keep = set(_opt("only").split(","))
    digs = []
    puts = [c for c in puts if final[c][0] in keep]
    swaps = [c for c in swaps if final[c][0] in keep]
    BOX = BOX or (lambda c: True)
    _in = BOX
    BOX = lambda c, _in=_in: _in(c) and final.get(c, ("",))[0] in keep
if _opt("notbox"):
    nb = list(map(int, _opt("notbox").split(",")))
    def outside(c):
        return not all(nb[k] <= c[k] <= nb[k + 3] for k in range(3))
    digs, puts, swaps = [c for c in digs if outside(c)], [c for c in puts if outside(c)], [c for c in swaps if outside(c)]
    _in2 = BOX or (lambda c: True)
    BOX = lambda c, _in2=_in2: _in2(c) and outside(c)
if "redo" in ARGS[4:]:                              # a room refitted: what changes comes out first, then
    digs, puts, swaps = digs + swaps, puts + swaps, []      # goes in like any other fitting
print(f"{len(digs)} to dig out, {len(swaps)} to swap, {len(puts)} to put in")

# ---------------------------------------------------------------- the space
_all = list(final) + list(shell)
X0, Y0, Z0 = min(c[0] for c in _all) - 4, -1, min(c[2] for c in _all) - 4
SX = max(c[0] for c in _all) + 5 - X0
SY = max(c[1] for c in _all) + 5 - Y0
SZ = max(c[2] for c in _all) + 5 - Z0
def idx(c):
    return (c[0] - X0, c[1] - Y0, c[2] - Z0)
footprint = {(x, z) for (x, y, z) in final if y == 0} | {(x, z) for (x, y, z) in shell if y == 0}

def space(blocks):
    """True where a turtle can be."""
    free = np.ones((SX, SY, SZ), dtype=bool)
    free[:, 0:2, :] = False                       # the ground outside (y <= 0)
    for c in blocks:
        i = idx(c)
        if 0 <= i[0] < SX and 0 <= i[1] < SY and 0 <= i[2] < SZ:
            free[i] = False
    return free

def reachable(free):
    lab, _ = ndimage.label(free)
    return lab == lab[idx(START)]

STAND = [(0, 1, 0), (0, -1, 0), (1, 0, 0), (0, 0, 1), (-1, 0, 0), (0, 0, -1)]   # codes 0..5
FACE_STAND = {"east": 2, "south": 3, "west": 4, "north": 5}
def prefs(name, facing):
    if name == "minecraft:lantern":
        return [1]
    if name == "minecraft:chain":
        return [1, 2, 3, 4, 5]
    if name == "minecraft:ladder":
        return [FACE_STAND[facing], 0, 1]         # in front of it, facing the wall it hangs on;
                                                  # or from above / below (in a hole in a floor)
    if name.endswith("sapling"):
        return [0]
    return [0, 2, 3, 4, 5, 1]
HANGS = {"minecraft:lantern": (0, 1, 0), "minecraft:chain": (0, 1, 0), "minecraft:birch_sapling": (0, -1, 0)}

def stand_for(c, name, facing, reach):
    for s in ([MUST[c]] if name and c in MUST else prefs(name, facing)):
        d = STAND[s]
        i = idx((c[0] + d[0], c[1] + d[1], c[2] + d[2]))
        if 0 <= i[0] < SX and 0 <= i[1] < SY and 0 <= i[2] < SZ and reach[i]:
            return s
    return None

# ---------------------------------------------------------------- digging first
# forwards: dig what can be reached, which opens the way to more
now = dict(shell)
ops = []
todo = set(digs)
while todo:
    reach = reachable(space(now))
    wave = []
    for c in sorted(todo):
        s = stand_for(c, "", "-", reach)
        if s is not None:
            wave.append((c, s))
    if not wave:
        print("cannot reach to dig:", sorted(todo)[:10])
        sys.exit(1)
    for c, s in wave:
        ops.append(("D", c, None, s))
        del now[c]
        todo.discard(c)
after_digs = dict(now)

# ---------------------------------------------------------------- putting in, worked out backwards
state = dict(after_digs)
for c in puts:
    state[c] = final[c]
left = set(puts)
waves = []
while left:
    reach = reachable(space(state))
    wave = []
    for c in sorted(left):
        name, facing = final[c]
        # something still hanging from it? then it stays for now
        held = False
        for other, d in HANGS.items():
            o = (c[0] - d[0], c[1] - d[1], c[2] - d[2])
            if o in left and final[o][0] == other:
                held = True
        if held:
            continue
        s = stand_for(c, name, facing, reach)
        if s is not None:
            wave.append((c, s))
    if not wave:
        print("cannot work out how to reach:", [(c, final[c][0]) for c in sorted(left)[:12]])
        sys.exit(1)
    for c, s in wave:
        del state[c]
        left.discard(c)
    waves.append(wave)
print(f"{len(waves)} rounds of fitting")

pal, pindex = [], {}
def pal_i(entry):
    if entry not in pindex:
        pindex[entry] = len(pal)
        pal.append(entry)
    return pindex[entry]

hidden = set()
# swaps (the lane floor) go right after the digging: from above
reach = reachable(space(after_digs))
for c in sorted(swaps, key=lambda c: (c[2], c[0])):
    s = stand_for(c, final[c][0] if c in MUST else "", "-", reach)
    if s is None:
        print("cannot reach to swap", c)
        if GLASS_TOO:                              # under a fitting by now: out of sight, leave it
            hidden.add(c)
            continue
        sys.exit(1)
    ops.append(("R", c, pal_i(final[c]), s))
# then the fittings, deepest round first; within a round sweep room by room
def sweep(item):
    (x, y, z), s = item
    room = min(max(x, 0) // 9, 5)
    return (room, y, z if (y + room) % 2 == 0 else -z, x)
for wave in reversed(waves):
    for c, s in sorted(wave, key=sweep):
        ops.append(("P", c, pal_i(final[c]), s))

# the way in: dug out before anything else, from outside
if OPENED:
    full = dict(shell)
    for c, v in OPENED:
        full[c] = v
    reach = reachable(space(full))
    first = []
    for c, v in OPENED:
        st_ = stand_for(c, "", "-", reach)
        if st_ is None:
            print("cannot reach the way in at", c)
            sys.exit(1)
        first.append(("D", c, None, st_))
    ops = first + ops

# ---------------------------------------------------------------- replay it
now = dict(shell)
for c, v in OPENED:
    now[c] = v
bad = 0
reach = reachable(space(now))
dirty = False
for kind, c, i, s in ops:
    d = STAND[s]
    stand = (c[0] + d[0], c[1] + d[1], c[2] + d[2])
    if dirty:
        reach = reachable(space(now))
        dirty = False
    if not reach[idx(stand)]:
        bad += 1
        if bad <= 5:
            print("  not reachable in replay:", kind, c, s)
    if kind == "D":
        del now[c]
        dirty = True                               # more space: look again
    elif kind == "P":
        now[c] = pal[i]
        # less space: only matters if this cell was part of the way; cheap to recheck
        dirty = True
    else:
        now[c] = pal[i]
want = {c: v for c, v in final.items() if v[0] not in SKIP}
have = {c: v for c, v in now.items() if c[1] >= 0}
if BOX:                                             # (the rest of the building is not this plan's business)
    want = {c: v for c, v in want.items() if BOX(c)}
    have = {c: v for c, v in have.items() if BOX(c)}
wrong = [c for c in want if have.get(c) != want[c] and c not in hidden]
extra = [c for c in have if c not in final]
print(f"replay: {len(ops)} jobs, {bad} out of reach, {len(wrong)} blocks wrong at the end, {len(extra)} left over")

out = F_OUT
with open(out, "w") as f:
    f.write(f"S {START[0]} {START[1]} {START[2]}\n")
    f.write(f"P {len(pal)}\n")
    for name, facing in pal:
        f.write(f"{name} {facing}\n")
    f.write(f"O {len(ops)}\n")
    for kind, c, i, s in ops:
        if kind == "D":
            f.write(f"D {c[0]} {c[1]} {c[2]} {s}\n")
        else:
            f.write(f"{kind} {c[0]} {c[1]} {c[2]} {i} {s}\n")
need = Counter(pal[i][0] for kind, c, i, s in ops if kind != "D")
print(out)
for name, n in need.most_common():
    print(f"{n:6d}  {name}")
sys.exit(1 if bad or wrong else 0)
