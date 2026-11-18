#!/usr/bin/env python3
"""The foundry hall v2 (docs/foundry-v2.md), built by the drones: one fit plan
per job, blueprints/factory_f2_<job>.txt, in the fit walker's format
(helper.lua runFit). Several helpers share a job with xmin=/xmax= strips.

    python3 tools/foundry2plans.py write      write every plan, print the bills
    python3 tools/foundry2plans.py check      the jobs against the model and each other
    python3 tools/foundry2plans.py bill <job> what a job needs
    python3 tools/foundry2plans.py order <job> [helper] [xmin xmax]   the fit order (printed, not sent)

Coordinates are the building's (corner -4448 71 1518). Stands: 0 above,
1 below, 2 east, 3 south, 4 west, 5 north of the block.

Cable under the floor: the walker digs the floor block from above (it may
then stand in that hole: helper.lua lets it into a floor cell the plan has
dug), puts the cable a block down, climbs out and puts the floor block back.
"""
import os
import sys
from collections import Counter, OrderedDict

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import retrofit as R  # noqa: E402

START = (22, 2, 33)               # in by the big door, as every factory fit
SHELL = "factory_asfit3"
CC = "computercraft:cable"
WM = "computercraft:wired_modem_full"
PC = "computercraft:computer_normal"
UC = "mekanism:basic_universal_cable"
PD = "minecraft:polished_deepslate"
DB = "minecraft:deepslate_bricks"
SB = "minecraft:stone_bricks"
STRIPE = "chipped:striped_yellow_concrete"
BARREL = "minecraft:barrel"


class Plan:
    def __init__(self, name, who, phase, what):
        self.name, self.who, self.phase, self.what = name, who, phase, what
        self.ops = []                 # (k, (x, y, z), item or None, stand)

    def D(self, c, s=0):
        self.ops.append(("D", c, None, s))

    def P(self, c, item, s=0):
        # (a block down is earth or stone: dug out and replaced)
        self.ops.append(("R" if c[1] < 0 else "P", c, item, s))

    def R(self, c, item, s=0):
        self.ops.append(("R", c, item, s))

    def under(self, c, floor, item=CC):
        """a cable (or modem) a block under floor cell c: dig the floor, put it in, floor back"""
        x, y, z = c
        self.D((x, 0, z), 0)
        self.P((x, -1, z), item, 0)
        if floor:
            self.P((x, 0, z), floor, 0)

    def text(self):
        pal = []
        for _, _, it, _ in self.ops:
            if it and it not in pal:
                pal.append(it)
        ent = lambda it: it if " " in it else it + " -"
        out = ["S %d %d %d" % START, f"P {len(pal)}"] + [ent(it) for it in pal] + [f"O {len(self.ops)}"]
        for k, (x, y, z), it, s in self.ops:
            out.append(f"D {x} {y} {z} {s}" if k == "D" else f"{k} {x} {y} {z} {pal.index(it)} {s}")
        return "\n".join(out) + "\n"

    def bill(self):
        """what has to come from the factory: placed, less what the plan digs up and puts back"""
        got = Counter()
        need = Counter()
        B = R.model()
        for k, c, it, s in self.ops:
            if k == "D":
                was = B.get(c)
                if was:
                    got[was.split(" ")[0]] += 1
            else:
                need[it.split(" ")[0]] += 1
        return OrderedDict(sorted(((n, c - got.get(n, 0)) for n, c in need.items() if c - got.get(n, 0) > 0),
                                  key=lambda t: -t[1]))


def floor_at(c):
    B = R.model()
    f = B.get((c[0], 0, c[2])) or PD
    return f.split("[")[0]


# ================================================================= the jobs
def link():
    """The CC cable: from rack 1's link at the x 18 wall, under the lane floor to
    the hatch, into the hall under the north walkway and down the spine (x 35),
    with branches to the certus barrel, the works computer, the ME bridge and the
    alloy cell (whose floor modems it puts in), and on toward the ore line."""
    p = Plan("link", "builder1 xmax=25, survey1 xmin=26 xmax=34, builder4 xmin=35", 1,
             "the CC cable under the floor, the alloy cell's floor modems, the works computer")
    # down from the link at 18 2 3 (Kyle's) to under the lane floor
    p.D((18, 1, 3), 5)
    p.D((18, 0, 3), 0)
    p.P((18, -1, 3), CC, 0)
    p.P((18, 0, 3), CC, 0)
    p.P((18, 1, 3), WM, 5)
    for x in range(18, 33):                               # under the front track to the hatch
        p.under((x, 0, 2), STRIPE)
    for z in (3, 4, 5):                                   # under the hatch, into the hall
        p.under((32, 0, z), PD)
    for x in (33, 34, 35):
        p.under((x, 0, 5), PD)
    for z in range(6, 23):                                # the spine's trunk
        if z == 15:
            p.under((35, 0, 15), None, WM)                # the works computer's modem (never clicked)
            p.P((35, 0, 15), PC, 0)                       # the works computer, flush in the floor
        else:
            p.under((35, 0, z), PD)
    for z in (13, 21):                                    # the certus barrel's and the ME bridge's modems
        p.under((34, 0, z), None)
        p.P((34, 0, z), WM, 0)
    for x in (36, 37, 38):                                # the alloy cell's branch (z 22, clear of the old line)
        p.under((x, 0, 22), floor_at((x, 0, 22)))
    for z in range(17, 24):                               # under the alloy cell: cable, and a modem under each machine
        p.under((39, 0, z), None)
        p.P((39, 0, z), WM, 0)
    for z in (16,):                                       # on toward the ore line (finished by the ore job)
        for x in (39, 40, 41):
            p.under((x, 0, z), floor_at((x, 0, z)))
    return p


def lava():
    """Sixteen dripstone lava units along the south wall, cauldrons at z 29
    (x 28-43), harvested from the walkway at z 28; lava held at y 4 between
    the wall and a row of blocks over the walkway."""
    p = Plan("lava", "builder2 xmax=35, builder5 xmin=36", 1, "the lava wall: 16 units")
    xs = range(28, 44)
    for x in xs:
        p.P((x, 3, 29), PD, 0)                            # the block the dripstone hangs from
    for x in xs:
        p.P((x, 4, 28), PD, 0)                            # the lava's north wall (over the walkway)
    for x in xs:
        p.P((x, 2, 29), "minecraft:pointed_dripstone", 1)   # from below: it hangs, tip down
    for x in xs:
        p.P((x, 1, 29), "minecraft:cauldron", 5)          # from the walkway
    for x in xs:
        p.P((x, 4, 29), "minecraft:lava_bucket", 0)       # last
    return p


def certus():
    """The AE2 work's certus farm (tools/certusfarm.py), its shell by drone:
    the two pillars, and the barrel the harvest goes into (on the cable). Kyle
    places only the budding blocks; the basin's water is a lab step."""
    import certusfarm as C
    F = C.Farm()
    p = Plan("certus", "lava1", 1, "the certus farm's pillars and its barrel (Kyle: the budding blocks)")
    for c in sorted(F.pillars(), key=lambda c: (c[2], c[1])):
        p.P(c, SB, 0)                                     # bottom up, each from above
    p.P((34, 1, 13), BARREL + " north", 5)
    p.D((33, 0, 13), 0)                                   # the click hole beside the barrel's modem
    return p


def budding():
    """The certus farm's budding blocks, by drone (Kyle: placing does not
    degrade them): the 9 flawed budding certus against the pillars, bottom
    tier first, each placed from above. Never dug again: harvests use the
    pick verb, which takes only full-grown clusters."""
    import certusfarm as C
    F = C.Farm()
    p = Plan("budding", "builder4", 1, "the 9 flawed budding certus on the farm's pillars")
    for _, i, t, sd in F.filled():                       # (bottom tier first)
        p.P(F.slot_cell(i, t, sd), "ae2:flawed_budding_quartz", 0)
    return p


def storelink():
    """Rack 1's network onto the store's (they were two networks, so the
    store could not load drones in their rack homes). Rack 1's link has a
    modem in the storage room's east wall at 18 6 3; the store's network has
    a modem at 17 5 16. One run of cable along the top of the room's east
    wall, x 17 y 6 z 3..16, placed from below (found by survey1's scans)."""
    p = Plan("storelink", "builder1", 1, "rack 1's cable joined to the store's network")
    for z in range(3, 17):
        p.P((17, 6, z), CC, 1)
    return p


def clear():
    """builder3's piped line (the parts that do not move) and the bench's leftovers.
    A chest or barrel with things in it is left (and said): empty it first."""
    p = Plan("clear", "builder3 xmax=35, rescue1 xmin=36", 1, "the old piped line's chest, sorter, transporters and cable; the bench's leftovers")
    import mekline
    keep = {(36, 1, 17), (36, 1, 18), (36, 1, 21)}        # moved by the ore and power jobs
    cells = sorted((c for c in mekline.upto(5) if c not in keep), key=lambda c: (-c[1], c[2], c[0]))
    for c in cells:
        p.D(c, 0 if c[1] > 1 else 4)
    for c in [(32, 1, 22), (32, 2, 22), (33, 1, 22), (34, 1, 22), (34, 1, 23), (35, 1, 22)]:
        p.D(c, 0)
    return p


def power():
    """The power row along the east wall (universal cable, x 43, z 6-23), the
    piped line's heat generator moved into the power block, and room for more."""
    p = Plan("power", "builder6", 1, "the east wall's power row, the second heat generator")
    p.D((36, 1, 21), 0)                                   # the piped line's heat generator (carried)
    p.P((42, 1, 19), "mekanismgenerators:heat_generator east", 2)
    p.P((42, 1, 20), "mekanismgenerators:heat_generator east", 2)
    p.P((42, 1, 21), "mekanismgenerators:heat_generator east", 2)
    p.P((42, 1, 22), "mekanismgenerators:gas_burning_generator east", 2)
    p.P((42, 1, 23), "mekanism:basic_energy_cube east", 2)
    for z in range(6, 24):
        p.P((43, 1, z), UC, 0)
    return p


def alloy():
    """foundry1's plinth machines into the alloy cell (the foundry stops while
    they move: a few minutes), the cell's power row, its link to the east wall,
    and the old plinth cable up."""
    p = Plan("alloy", "foundry1", 2, "the plinth machines into the alloy cell; the old plinth cable up")
    for c in ((41, 1, 11), (41, 1, 12), (41, 1, 15)):
        p.D(c, 4)                                         # from the operator lane
    cell = [((39, 1, 17), "mekanism:metallurgic_infuser east"), ((39, 1, 19), "mekanism:energized_smelter east"),
            ((39, 1, 23), "mekanism:enrichment_chamber east"),
            ((39, 1, 18), "mekanism:metallurgic_infuser east"), ((39, 1, 20), "mekanism:energized_smelter east"),
            ((39, 1, 21), "mekanism:energized_smelter east"), ((39, 1, 22), "mekanism:crusher east")]
    for c, it in cell:
        p.P(c, it, 2)                                     # from the east: it faces the turtle
    for z in range(17, 24):
        p.P((38, 1, z), UC, 0)                            # the cell's power row, behind it
    # its link to the east wall's row, a block down under the east door's walkway
    p.D((38, 0, 23), 0)
    p.P((38, -1, 23), UC, 0)
    p.P((38, 0, 23), UC, 0)
    for x in range(38, 44):
        p.under((x, 0, 24), floor_at((x, 0, 24)), UC)
    p.D((43, 0, 23), 0)
    p.P((43, -1, 23), UC, 0)
    p.P((43, 0, 23), UC, 0)
    for z in range(7, 17):
        p.D((42, 1, z), 0)                                # the old plinth cable
    p.D((42, 1, 17), 0)                                   # the cube and the heat generator: turned to face the row
    p.D((42, 1, 18), 0)
    p.P((42, 1, 17), "mekanism:basic_energy_cube east", 0)
    p.P((42, 1, 18), "mekanismgenerators:heat_generator east", 0)
    for z in range(17, 24):                               # the click holes beside the cell's modems
        p.D((40, 0, z), 0)
    return p


def ore():
    """The ore line on the east wall: the cable under it with a modem under
    every machine, the piped line's chamber and smelter moved in, the rest as
    they are made."""
    p = Plan("ore", "builder3 (after alloy)", 3, "the ore line: floor modems, the chamber and smelter moved in")
    for z in (16, 15, 14):
        p.under((42, 0, z), DB)
    for z in range(13, 5, -1):
        p.under((42, 0, z), None)
        p.P((42, 0, z), WM, 0)
    p.D((36, 1, 17), 0)                                   # the piped line's chamber and smelter (carried)
    p.D((36, 1, 18), 0)
    line = [(12, "mekanism:enrichment_chamber"), (13, "mekanism:energized_smelter"),    # (moved: first)
            (11, "mekanism:crusher"), (10, "mekanism:purification_chamber"),
            (9, "mekanism:chemical_injection_chamber"), (8, "mekanism:chemical_crystallizer"),
            (7, "mekanism:chemical_washer"), (6, "mekanism:chemical_dissolution_chamber")]
    for z, it in line:
        p.P((42, 1, z), it + " west", 4)                  # from the walkway: it faces the turtle
    for z in range(6, 14):                                # the click holes beside the line's modems
        p.D((41, 0, z), 0)
    return p


def ae2():
    """The AE2 room (with the AE2 work's bench along the west wall, x 28 z 18-23,
    which it builds itself): controller, drives, crafting CPU, pattern providers
    and assemblers, the energy acceptor and the ME bridge. Fit when the parts
    exist; what is not to be had is left and done on a later run."""
    p = Plan("ae2", "builder1 (or the AE2 work's helper)", 4, "the AE2 room")
    for x in (29, 30, 31):
        for z in (18, 19, 20):
            p.P((x, 1, z), "ae2:controller", 0)
    for z in (18, 19):
        p.P((33, 1, z), "ae2:drive west", 2)
    for x in (29, 30, 31):
        p.P((x, 1, 22), "ae2:crafting_unit", 0)
        p.P((x, 1, 23), "ae2:1k_crafting_storage", 0)
    for z in (20, 21, 22, 23):
        p.P((32, 1, z), "ae2:pattern_provider", 0)
        p.P((33, 1, z), "ae2:molecular_assembler", 0)
    p.P((34, 1, 17), "ae2:energy_acceptor", 0)
    p.P((34, 1, 21), "advancedperipherals:me_bridge", 0)
    p.D((34, 0, 22), 0)                                   # the click hole beside the bridge's modem
    # power: one universal cable across the spine, flush in the floor
    for x in (34, 35, 36, 37):
        p.R((x, 0, 17), UC, 0)
    p.R((38, 0, 17), UC, 0)
    return p


def close():
    """After Kyle's clicks: the floor blocks back over the click holes."""
    p = Plan("close", "any helper", 5, "the click holes closed")
    p.P((33, 0, 13), PD, 0)
    p.P((34, 0, 22), PD, 0)
    for z in range(6, 14):
        p.P((41, 0, z), DB, 0)
    for z in range(17, 24):
        p.P((40, 0, z), DB, 0)
    return p


JOBS = OrderedDict((f.__name__, f) for f in (link, lava, certus, budding, storelink, clear, power, alloy, ore, ae2, close))


def check():
    plans = {n: f() for n, f in JOBS.items()}
    B = R.model()
    bad = []
    placed = {}
    dug = set()                                           # (the jobs run in phase order)
    for n, p in sorted(plans.items(), key=lambda t: t[1].phase):
        for k, c, it, s in p.ops:
            if k == "D":
                dug.add(c)
                continue
            floor = c in placed and placed[c][1] in (PD, DB, STRIPE) and k == "R"
            if c in placed and placed[c][0] != n and n != "close" and not floor:
                bad.append(f"{n}: {c} also placed by {placed[c][0]}")
            placed[c] = (n, it)
            if k == "P" and c[1] >= 0 and B.get(c) and c not in dug and n not in ("close",):
                was = B[c]
                if not any(w in was for w in ("(", "copper")) and not was.startswith("mekanism"):
                    bad.append(f"{n}: {c} {it} onto {was}")
            if s == 0 and c[1] == -1 and (c[0], 0, c[2]) not in dug:
                bad.append(f"{n}: {c} put a block down without the floor above dug")
    # the walkways stay clear at y 1-2
    for x in range(28, 43):
        for z in (14, 15, 16):
            for y in (1, 2):
                if (x, y, z) in placed:
                    bad.append(f"cross aisle {x} {y} {z} gets {placed[(x, y, z)]}")
    for z in range(5, 29):
        for x in (35, 36):
            for y in (1, 2):
                if (x, y, z) in placed:
                    bad.append(f"spine {x} {y} {z} gets {placed[(x, y, z)]}")
    n = sum(len(p.ops) for p in plans.values())
    print("\n".join(bad) if bad else f"ok: {len(plans)} jobs, {n} fit steps; nothing placed twice or in a walkway")
    return not bad


def write():
    for n, f in JOBS.items():
        p = f()
        path = os.path.join(ROOT, "blueprints", f"factory_f2_{n}.txt")
        with open(path, "w") as fh:
            fh.write(p.text())
        print(f"{path}: {len(p.ops)} steps; phase {p.phase}; {p.who}")
        for item, c in p.bill().items():
            print(f"    {c:4d}  {item}")


if __name__ == "__main__":
    a = sys.argv[1:] or ["check"]
    if a[0] == "write":
        if check():
            write()
    elif a[0] == "check":
        sys.exit(0 if check() else 1)
    elif a[0] == "bill":
        for item, c in JOBS[a[1]]().bill().items():
            print(f"{c:4d}  {item}")
    elif a[0] == "order":
        who = a[2] if len(a) > 2 else "builder1"
        strip = f" xmin={a[3]} xmax={a[4]}" if len(a) > 4 else ""
        print(f"tools/order.py fit {who} ox={R.OX} oy={R.OY} oz={R.OZ} plan=factory_f2_{a[1]} shell={SHELL}{strip}")
    else:
        print(__doc__)
