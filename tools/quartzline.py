#!/usr/bin/env python3
"""Nether quartz with no Nether, in the south-west corner of the foundry bay.

Sand turns to soul sand in front of an Actually Additions Atomic
Reconstructor (a laser recipe: 20,000 FE, the reconstructor fires every five
seconds at 1,000 FE a shot), fed by two AA coal generators (20 FE/t each,
sharing to every side). Soul sand dropped into a Create fan's wash water
comes out as 4 quartz one time in eight (and a gold nugget one in fifty): on
average half a quartz per sand. The fan is turned by a water wheel next to
it, with water running south over the wheel's top.

    python3 tools/quartzline.py map                  the layout, layer by layer
    python3 tools/quartzline.py casing [opts]        lab steps: make one andesite casing
    python3 tools/quartzline.py build [opts]         lab steps: put the line up
    python3 tools/quartzline.py run N [opts]         lab steps: N sand -> quartz
    opts: side=right (the pickaxe side)  pick=minecraft:diamond_pickaxe
          log=minecraft:oak_log (casing)

Each prints the ops string for:  tools/order.py lab <helper> clear=1 "ops=..."

Coordinates are the factory building's own (corner -4448 71 1518; x east,
z south, y 1 = the ground floor). Nothing here is on the drone lane
(x 39-40), the Mekanism line or its walkway (x 35-37, z 9-21), its pool
(x 29-32, z 12-15), the gas plants' ground (x 29-34, z 16-21) or the old
sapling spots of the fit-out (x 30/34/38, every fourth z); test/quartzline.py
checks that against the plans.

    y 1   x 27..36 across          y 2   x 27..36 across
          7890123456                     7890123456
    z 22  .....GRt#.               z 22  ......G...
    z 23  .......s..               z 23  ..........
    z 24  ..........               z 24  ..#.......
    z 25  ..#.##....               z 25  .#~#......
    z 26  ..WF~~#...               z 26  .#~#......
    z 27  ....##....               z 27  ..#.......

    R reconstructor, firing east at t (where the sand stands); # behind it
    G generators: west of it, and on top of it
    s where the turtle stands to feed t (facing north)
    W water wheel (axis x), F encased fan beside it blowing east
    ~ at y 1: the wash water (a source by the fan, flowing one east); the
      turtle drops soul sand from 32 2 26 and takes the quartz up the same way
    ~ at y 2: a source over 29 1 25, flowing south over the wheel's top
"""
import sys

OX, OY, OZ = -4448, 71, 1518
SITE = f"site|{OX}|{OY}|{OZ}|factory_asfit3|factory_storeroom"
RIVER = (-4462, 66, 1560)          # over the river south-west of the hut (water at y 62)

COBBLE = "minecraft:cobblestone"
WHEEL, FAN = "create:water_wheel", "create:encased_fan"
RECON, GEN = "actuallyadditions:atomic_reconstructor", "actuallyadditions:coal_generator"
BUCKET, WATER = "minecraft:bucket", "minecraft:water_bucket"
COAL, SAND, SOUL = "minecraft:coal", "minecraft:sand", "minecraft:soul_sand"
SHOVEL, AXE = "minecraft:diamond_shovel", "minecraft:diamond_axe"
CORE, ALLOY = "advancedperipherals:weak_automata_core", "create:andesite_alloy"

# ---------------------------------------------------------------- the layout
WHEEL_AT, FAN_AT = (29, 1, 26), (30, 1, 26)
WASH_SRC, WASH_AT = (31, 1, 26), (32, 1, 26)      # the fan's water, and where the sand lies
WHEEL_SRC, WHEEL_FLOW = (29, 2, 25), (29, 2, 26)
RECON_AT, TARGET, STAND = (33, 1, 22), (34, 1, 22), (34, 1, 23)
GEN_SIDE, GEN_TOP = (32, 1, 22), (33, 2, 22)
CASING_AT, CASING_STAND = (35, 1, 26), (35, 1, 27)
WASH_STAND = (32, 2, 26)

# cobblestone: (cell, why)
WALLS = [
    ((29, 1, 25), "under the wheel's water"),
    ((31, 1, 25), "wash water, north"), ((32, 1, 25), "wash water, north"),
    ((31, 1, 27), "wash water, south"), ((32, 1, 27), "wash water, south"),
    ((33, 1, 26), "end of the wash: stops the air and the water"),
    ((29, 2, 24), "wheel water, north"),
    ((28, 2, 25), "wheel water, west"), ((30, 2, 25), "wheel water, east"),
    ((28, 2, 26), "wheel water, west"), ((30, 2, 26), "wheel water, east (over the fan)"),
    ((29, 2, 27), "wheel water, south"),
    ((35, 1, 22), "behind the sand: the laser stops here when nothing stands at t"),
]

# where water is meant to be: source cells, and every cell it may run into
WATER_SOURCES = [WHEEL_SRC, WASH_SRC]
WATER_CELLS = {WHEEL_SRC, WHEEL_FLOW, WASH_SRC, WASH_AT}

DIRS = {0: (1, 0), 1: (0, 1), 2: (-1, 0), 3: (0, -1)}     # east south west north
FACE_NAME = {0: "east", 1: "south", 2: "west", 3: "north"}

# machines placed from beside them: (cell, item, turtle faces, state wanted)
#  wheel: placed looking west, its facing normalised to the axis' positive end
#  fan: faces away from the wheel it sits against (its shaft side), so east
#  reconstructor: faces whoever placed it (looking west: faces east, at t)
FRONT = [
    (WHEEL_AT, WHEEL, 2, ("facing", "east")),
    (FAN_AT, FAN, 2, ("facing", "east")),
    (RECON_AT, RECON, 2, ("facing", "east")),
]
DOWN = [(GEN_SIDE, GEN), (GEN_TOP, GEN)]


def short(item):
    return item.split(":")[1]


def opts(args):
    o = {"side": "right", "pick": "minecraft:diamond_pickaxe", "log": "minecraft:oak_log"}
    for a in args:
        if "=" in a:
            k, v = a.split("=", 1)
            o[k] = v
    return o


def walk(c):
    return f"walk|{c[0]}|{c[1]}|{c[2]}"


def place_down(cell, item, state=None):
    x, y, z = cell
    s = [walk((x, y + 1, z)), f"placeDown|{item}", f"expect|down|{short(item)}"]
    if state:
        s[-1] += f"|{state[0]}|{state[1]}"
    return s


def place_front(cell, item, d, state=None):
    dx, dz = DIRS[d]
    stand = (cell[0] - dx, cell[1], cell[2] - dz)
    s = [walk(stand), f"face|{d}", f"place|{item}", f"expect|front|{short(item)}"]
    if state:
        s[-1] += f"|{state[0]}|{state[1]}"
    return s


def fill_buckets(n):
    """n buckets of river water (the cell takes a moment to fill again)."""
    s = [f"goto|{RIVER[0]}|{RIVER[1]}|{RIVER[2]}", "seek|water|12"]
    for i in range(n):
        if i:
            s += ["wait|3"]
        s += [f"placeDown|{BUCKET}"]
    return s


def build_coal():
    return 8


def build_items():
    return {COBBLE: len(WALLS), WHEEL: 1, FAN: 1, RECON: 1, GEN: len(DOWN),
            BUCKET: len(WATER_SOURCES), COAL: 2 * build_coal()}


def fetch(items, dump=True):
    return "fetch|" + ",".join(f"{k}={v}" for k, v in items.items()) + ("|dump" if dump else "")


def build(o):
    s = [fetch(build_items())]
    s += fill_buckets(len(WATER_SOURCES)) + ["inv", SITE]
    for cell, _ in sorted(WALLS, key=lambda w: (w[0][1], w[0][2], w[0][0])):
        s += place_down(cell, COBBLE)
    for cell, item, d, state in FRONT:
        s += place_front(cell, item, d, state)
    for cell, item in DOWN:
        s += place_down(cell, item)
    # water last, once everything that holds it is in place
    s += [walk((WHEEL_SRC[0], 3, WHEEL_SRC[2])), f"placeDown|{WATER}", "expect|down|water|level|0",
          "wait|2", walk((WHEEL_FLOW[0], 3, WHEEL_FLOW[2])), "expect|down|water|level|1",
          walk((WASH_SRC[0], 2, WASH_SRC[2])), f"placeDown|{WATER}", "expect|down|water|level|0",
          "wait|2", walk(WASH_STAND), "expect|down|water|level|1"]
    # some coal into each generator, so the reconstructor is charging
    s += [walk((GEN_SIDE[0], 2, GEN_SIDE[2])), f"dropDown|{COAL}|{build_coal()}",
          walk((GEN_TOP[0], 3, GEN_TOP[2])), f"dropDown|{COAL}|{build_coal()}"]
    s += ["inv", "leave", "home", "handin|"]
    return s


def casing(o):
    """One andesite casing: a log in front, stripped with an axe and then
    andesite alloy put on it, both by a right-click (Weak Automata Core)."""
    log = o["log"]
    stripped = log.replace(":", ":stripped_", 1)
    s = [fetch({log: 1, AXE: 1, ALLOY: 1, CORE: 1}), SITE]
    s += place_front(CASING_AT, log, 3)
    s += [f"equip|{o['side']}|{CORE}", f"use|{AXE}", f"expect|front|{short(stripped)}",
          f"use|{ALLOY}", "expect|front|andesite_casing", f"equip|{o['side']}|{o['pick']}",
          "dig", "inv", "leave", "home", "handin|"]
    return s


def run_coal(n):
    # a sand takes about 21,000 FE (20,000 + a shot), and the shots fired
    # while it charges: some 28,000 FE with both generators; a coal is 32,000
    return n + 2


def run(n, o):
    coal = run_coal(n)
    half = coal // 2
    s = [fetch({SAND: n, COAL: coal + 8, SHOVEL: 1}), SITE,
         walk((GEN_SIDE[0], 2, GEN_SIDE[2])), "expect|down|coal_generator", f"dropDown|{COAL}|{half}",
         walk((GEN_TOP[0], 3, GEN_TOP[2])), "expect|down|coal_generator", f"dropDown|{COAL}|{coal - half}",
         walk(STAND), "face|3",
         f"equip|{o['side']}|{SHOVEL}",
         f"cycle|{SAND}|soul_sand|{n}|180",
         f"equip|{o['side']}|{o['pick']}",
         walk(WASH_STAND), "expect|down|water",
         f"tossDown|{SOUL}|{n}", "wait|30", "suckDown|64", "wait|15", "suckDown|64", "suckDown|64",
         "inv", "leave", "home", "handin|"]
    return s


def cells():
    """Everything the line puts in the building: cell -> what."""
    c = {cell: COBBLE for cell, _ in WALLS}
    for cell, item, _, _ in FRONT:
        c[cell] = item
    for cell, item in DOWN:
        c[cell] = item
    for w in WATER_SOURCES:
        c[w] = "minecraft:water"
    return c


def show_map():
    c = cells()
    sym = {COBBLE: "#", WHEEL: "W", FAN: "F", RECON: "R", GEN: "G", "minecraft:water": "~"}
    for y in (1, 2):
        print(f"y {y}   x 27..36 across")
        print("      " + "".join(str(x % 10) for x in range(27, 37)))
        for z in range(21, 29):
            row = ""
            for x in range(27, 37):
                p = (x, y, z)
                if p in c:
                    row += sym[c[p]]
                elif p in WATER_CELLS:
                    row += "~"
                elif p == TARGET:
                    row += "t"
                elif p == STAND:
                    row += "s"
                else:
                    row += "."
            print(f"z {z:2d}  {row}")
        print()


def main(argv):
    if not argv or argv[0] == "map":
        show_map()
        return
    o = opts(argv[1:])
    if argv[0] == "build":
        print(";".join(build(o)))
    elif argv[0] == "casing":
        print(";".join(casing(o)))
    elif argv[0] == "run":
        n = int(argv[1]) if len(argv) > 1 and argv[1].isdigit() else 8
        print(";".join(run(n, o)))
    else:
        print(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
