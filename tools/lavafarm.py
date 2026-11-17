"""Dripstone lava farm by the base: a row of units along z, built in the air
west of the factory building (clear of the hut, the launch pad, the loaders'
parking and the building itself).

One unit, at x0 and z:
    y 80   lava source, walled in (x0-1, x0+1, and the row's two ends)
    y 79   cobblestone under it
    y 78   pointed dripstone hanging from it, tip down
    y 77   air
    y 76   cauldron (lava drips into it, slowly, for ever)
A turtle collects standing at x0+1, 76, z facing west (face 2) with an empty
bucket.

    python3 tools/lavafarm.py build N [first unit]   lab steps to build units
    python3 tools/lavafarm.py test                   build ONE unit, then try
                                                     a bucket both ways
    python3 tools/lavafarm.py collect N [how]        lab steps to empty the row
"""
import sys

X0, Z0 = -4454, 1538          # first unit; the row runs south (+z)
LAVA_Y, BASE_Y, DRIP_Y, CAUL_Y = 80, 79, 78, 76
COBBLE, DRIP = "minecraft:cobblestone", "minecraft:pointed_dripstone"
CAUL, LAVA, BUCKET = "minecraft:cauldron", "minecraft:lava_bucket", "minecraft:bucket"


def build(n, first=0):
    zs = [Z0 + first + i for i in range(n)]
    cobble = n + 2 * n + 2          # bases, side walls, two end caps
    s = [f"fetch|{COBBLE}={cobble},{DRIP}={n},{CAUL}={n},{LAVA}={n}"]
    for z in zs:                     # the trough: base and both sides
        s += [f"goto|{X0}|{LAVA_Y}|{z}", f"placeDown|{COBBLE}",
              f"goto|{X0 - 1}|{LAVA_Y + 1}|{z}", f"placeDown|{COBBLE}",
              f"goto|{X0 + 1}|{LAVA_Y + 1}|{z}", f"placeDown|{COBBLE}"]
    s += [f"goto|{X0}|{LAVA_Y + 1}|{zs[0] - 1}", f"placeDown|{COBBLE}",      # the ends
          f"goto|{X0}|{LAVA_Y + 1}|{zs[-1] + 1}", f"placeDown|{COBBLE}"]
    for z in zs:                     # in under the base from the east (x0+1 is walled above),
        s += [f"goto|{X0 + 2}|{DRIP_Y - 1}|{z}", "face|2", "fwd|2",     # dripstone up, cauldron down
              f"placeUp|{DRIP}", f"placeDown|{CAUL}", "face|0", "fwd|2"]
    for z in zs:                     # lava last, into the walled cell
        s += [f"goto|{X0}|{LAVA_Y + 1}|{z}", f"placeDown|{LAVA}"]
    for z in zs:                     # look: the tip and the cauldron
        s += [f"goto|{X0 + 2}|{DRIP_Y}|{z}", "face|2", "fwd|1", "inspect|front", "expect|front|dripstone",
              "down|2", "inspect|front", "expect|front|cauldron", "face|0", "fwd|1"]
    return s


def finish(n, first=0):
    """Units whose trough is already built: make sure each base block is
    there (a dripstone hangs only from a solid block), then dripstone,
    cauldron, lava and the check, as in build."""
    zs = [Z0 + first + i for i in range(n)]
    s = [f"fetch|{COBBLE}={n + 2},{DRIP}={n},{CAUL}={n},{LAVA}={n}"]
    for z in zs:
        s += [f"goto|{X0}|{LAVA_Y}|{z}", f"placeDown|{COBBLE}"]
    for z in zs:
        s += [f"goto|{X0 + 2}|{DRIP_Y - 1}|{z}", "face|2", "fwd|2",
              f"placeUp|{DRIP}", f"placeDown|{CAUL}", "face|0", "fwd|2"]
    for z in zs:
        s += [f"goto|{X0}|{LAVA_Y + 1}|{z}", f"placeDown|{LAVA}"]
    for z in zs:
        s += [f"goto|{X0 + 2}|{DRIP_Y}|{z}", "face|2", "fwd|1", "inspect|front", "expect|front|dripstone",
              "down|2", "inspect|front", "expect|front|cauldron", "face|0", "fwd|1"]
    return s


def collect(n, how="place", first=0):
    return [f"fetch|{BUCKET}={n}", f"collect|{X0 + 1}|{CAUL_Y}|{Z0 + first}|{n}|2|{how}"]


def end():
    return ["inv", "home", "handin|"]


if __name__ == "__main__":
    what = sys.argv[1] if len(sys.argv) > 1 else "test"
    if what == "build":
        ops = build(int(sys.argv[2]), int(sys.argv[3]) if len(sys.argv) > 3 else 0) + end()
    elif what == "finish":
        ops = finish(int(sys.argv[2]), int(sys.argv[3]) if len(sys.argv) > 3 else 0) + end()
    elif what == "collect":
        ops = collect(int(sys.argv[2]), sys.argv[3] if len(sys.argv) > 3 else "place") + end()
    else:
        # one unit, then try a bucket with turtle.place and (if the turtle wears
        # the Weak Automata Core) with a right-click. A fresh cauldron is empty:
        # the first tries say "0 of 1"; run `collect 1` again later.
        ops = build(1) + [f"fetch|{BUCKET}=2", f"collect|{X0 + 1}|{CAUL_Y}|{Z0}|1|2|place"] + end()
    print(";".join(ops))
