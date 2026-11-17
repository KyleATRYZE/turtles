#!/usr/bin/env python3
"""The factory retrofit (docs/factory-retrofit.md): every cell the retrofit
adds, checked against everything built or planned, plus the maps, the bills
and the lab steps for the swarm's share. Prints only; it sends nothing.

    python3 tools/retrofit.py check            every retrofit cell is free in the plans
    python3 tools/retrofit.py map site|pads|net|foundry|store
    python3 tools/retrofit.py items <stage>    bill of blocks for a stage (1 2 3 6 7 8)
    python3 tools/retrofit.py ops <job>        lab steps: deck bridge unbridge bench padc lava2
    python3 tools/retrofit.py fit <plan>       a fit plan's text: desklink walls northline
                                               (save as blueprints/factory_<plan>.txt to use)

Coordinates are the factory building's own (corner -4448 71 1518; x east,
z south, y 1 = the ground floor, y 0 = the floor). Outside the building the
same frame is used: the west yard is x < 0. World = (-4448 + x, 71 + y,
1518 + z). Lab steps outside the building use goto in world coordinates
(as tools/lavafarm.py does); inside, the fit plans and site/walk.
"""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

OX, OY, OZ = -4448, 71, 1518
SITE = f"site|{OX}|{OY}|{OZ}|factory_asfit3|factory_storeroom"


def W(x, y, z):
    return OX + x, OY + y, OZ + z


DECK = "minecraft:polished_deepslate"
STRIPE = "chipped:striped_yellow_concrete"
CABLE = "computercraft:cable"
MODEM = "computercraft:wired_modem_full"
DRIVE = "computercraft:disk_drive"
CHEST = "minecraft:chest"
LANTERN = "minecraft:lantern"
UCABLE = "mekanism:basic_universal_cable"
PIPE = "mekanism:basic_mechanical_pipe"
LB1 = "sophisticatedstorage:limited_barrel_1"
LB4 = "sophisticatedstorage:limited_barrel_4"

# ---------------------------------------------------------------- the pad court
# The West Apron: a deck at floor level (y 0) against the west wall, between
# the old hut (x -20..-10) and the building (x 0). Three pad lines run east
# to west, one per row. Each line, west to east:
#     out-shaft | pad (drive under it) | dispenser (on its modem) | drop chest | in-shaft
# Only Crafty's line (A) serves miners, so only it has shafts.
APRON_X = range(-9, 0)           # x -9 .. -1
APRON_N = range(4, 11)           # z 4 .. 10: stage 1 (clear ground today)
APRON_S = range(11, 18)          # z 11 .. 17: stage 6 (after the yard bench comes out)
PAD_X, DISP_X, CHEST_X = -8, -7, -6
LINES = {"A": 6, "B": 9, "C": 13}          # z of each line
WHO = {"A": "Crafty", "B": "Counter", "C": "pad 3"}
SHAFT_IN, SHAFT_OUT = (-5, 6), (-9, 6)     # Crafty's line only (x, z)


def line_cells(k):
    z = LINES[k]
    return {(PAD_X, 0, z): DRIVE, (DISP_X, 0, z): MODEM, (CHEST_X, 1, z): CHEST}


# the trunk: modem A - modem B - east along z 8 - up at the wall - through it
# (Kyle: one deepslate tile at 0 1 8) - into the smelting hall's cable (1 1 8)
TRUNK = [(-7, 0, 7), (-7, 0, 8)] + [(x, 0, 8) for x in range(-6, 0)] + [(-1, 1, 8)]
WALL_HOLE = (0, 1, 8)                       # Kyle: tile out, cable in
TRUNK_C = [(-7, 0, 10), (-7, 0, 11), (-7, 0, 12)]   # stage 6: modem B - modem C
# the bridge to the old base's network: its yard part goes in with the deck,
# the rest (through the hut's east wall to the modem at -13 1 4) in stage 2
BRIDGE_YARD = [(-7, 0, 5), (-7, 0, 4), (-8, 0, 4), (-9, 0, 4)]
BRIDGE_UP = [(-9, 1, 4), (-9, 2, 4)]
BRIDGE_WALL = (-10, 2, 4)                   # the hut's east wall (cobblestone)
BRIDGE_HUT = [(-11, 2, 4), (-12, 2, 4), (-13, 2, 4)]  # on top of the old modem at -13 1 4
STRIPES = [(-9, 0, 5), (-9, 0, 7), (-5, 0, 5), (-5, 0, 7)]   # either side of each shaft
POSTS = [(-2, 4), (-2, 10)]                 # a deck block with a lantern on it (x, z)
POSTS_S = [(-2, 16)]

# where the drones wait. Today (no code change) both follow Crafty:
#   helpers hover at (pad x + 3 + 2*slot, f.y + 12, pad z - 4)      helper.lua hover()
#   loaders park at (f.x + 4 + 2*(i%4), ground, f.z - 1 - 2*(i//4))  loader.lua parkSpot()
HOVER_NOW = [(PAD_X + 3 + 2 * s, 13, LINES["A"] - 4) for s in range(4)]
PARK_NOW = [(DISP_X + 4 + 2 * (i % 4), LINES["A"] - 1 - 2 * (i // 4)) for i in range(12)]
# with code change C4 (the factory hands out a hover row and a parking lot)
HOVER_C4 = [(-9 + 2 * s, 13, 2) for s in range(4)]
PARK_C4 = [(-18 + 2 * (i % 4), 15 + 2 * (i // 4)) for i in range(12)]

# ---------------------------------------------------------------- inside the building
# the desk link: the smelting hall's cable (x 1, z 4..28) along the hall's
# south wall to the storage desk's modem row (10..15, 1, 29)
DESK_LINK = [(x, 1, 29) for x in range(1, 9)]
DESK_HOLE = (9, 1, 29)                      # partition wall: R (fit, from the hall side)

# the store wall raise: one more row (y 4) the length of both side walls
WALL_W = [(10, 4, z) for z in list(range(4, 13)) + list(range(18, 29))]
WALL_E = [(17, 4, z) for z in list(range(4, 13)) + list(range(18, 27))]

# the north line: CC cable from the west controller's modem (10 5 16) up and
# along the top of the rooms (y 7, under the upper floor; z 5) into the
# foundry, to modems on the Mekanism line's inbox (36 1 9) and outbox (36 1 19)
NORTH = ([(10, 6, 16), (10, 7, 16)] + [(10, 7, z) for z in range(15, 4, -1)]
         + [(x, 7, 5) for x in range(11, 18)] + [(x, 7, 5) for x in range(19, 27)]
         + [(x, 7, 5) for x in range(28, 37)] + [(36, 7, z) for z in (6, 7, 8)]
         + [(36, y, 8) for y in range(6, 1, -1)]
         + [(37, 7, z) for z in range(8, 20)] + [(37, y, 19) for y in range(6, 1, -1)])
NORTH_HOLES = [(18, 7, 5), (27, 7, 5)]      # partitions: R (fit)
NORTH_MODEMS = [(36, 1, 8), (37, 1, 19)]    # touching the inbox (south of it) / outbox (east of it)

# ---------------------------------------------------------------- the foundry
POWER = [(x, 1, z) for x in range(29, 34) for z in (5, 6, 7)]       # the NW plinth: generators, cube
POWER_LINK = [(34, 2, 6), (35, 2, 6)] + [(35, 2, z) for z in range(7, 11)] + [(36, 2, 10)]
WORKSHOP = [(x, 1, z) for x in range(36, 39) for z in range(23, 28)]  # test bench floor
# the evaporation tower (stage 4), outside the east wall, and its brine pipe
# (4 x 4, 4 high to start: about 48 blocks, a controller and 2 valves; it can
# grow to 18 high in the open air). Brine leaves by a valve on its west wall
# (46 3 7), climbs the outside to y 9 and crosses the bay above everything.
TEP = [(x, y, z) for x in range(46, 50) for z in range(5, 9) for y in range(1, 5)
       if x in (46, 49) or z in (5, 8) or y == 1]
TEP_DECK = [(x, 0, z) for x in range(46, 50) for z in range(5, 9)]
BRINE = ([(45, y, 7) for y in range(3, 10)] + [(x, 9, 7) for x in range(43, 33, -1)]
         + [(34, 9, z) for z in range(8, 17)])
BRINE_HOLE = (44, 9, 7)
# the AE2 corner (later): the launch bay's west strip, north of the doorway
AE2 = [(x, y, z) for x in (19, 20) for y in (1, 2, 3) for z in range(6, 13)]

# ---------------------------------------------------------------- fuel
LAVA2_X0, LAVA_Z0, LAVA_N = -4458, 1538, 11      # a second dripstone row, 4 west of the first


# ================================================================= the plans
def _shell(f):
    B, mode, pal = {}, None, []
    for line in open(os.path.join(ROOT, "blueprints", f)):
        t = line.split()
        if not t:
            continue
        if t[0] in "PB" and len(t) == 2 and t[1].isdigit():
            mode = t[0]
            continue
        if mode == "P":
            pal.append(t[0])
        else:
            x, y, z, i = map(int, t)
            B[(x, y, z)] = pal[i]
    return B


def _plan(f, B):
    pal, mode = [], None
    for line in open(os.path.join(ROOT, "blueprints", f)):
        t = line.split()
        if not t or t[0] == "S":
            continue
        if t[0] in "PO" and len(t) == 2 and t[1].isdigit():
            mode = t[0]
            continue
        if mode == "P":
            pal.append(t[0])
        elif t[0] == "D":
            B.pop(tuple(map(int, t[1:4])), None)
        else:
            B[tuple(map(int, t[1:4]))] = pal[int(t[4])]


def model():
    """Everything standing or planned: cell -> what."""
    B = _shell("factory_asfit3.txt")
    for f in ("factory_storeroom.txt", "factory_foundryfloor.txt", "factory_screens.txt",
              "factory_storescreen.txt", "factory_touchup.txt"):
        _plan(f, B)
    # the controller move (tools/ctlmove.py): cable up the desk column and
    # along the top of the west wall, a modem, the controller
    for y in range(2, 6):
        B[(10, y, 29)] = CABLE
    for z in range(17, 29):
        B[(10, 5, z)] = CABLE
    B[(10, 5, 16)] = MODEM
    B[(10, 5, 15)] = "sophisticatedstorage:controller"
    import mekline, quartzline
    for c, it in mekline.upto(5).items():
        B[c] = it
    for c, it in quartzline.cells().items():
        B[c] = it
    for c in (quartzline.TARGET, quartzline.STAND, quartzline.WASH_STAND):
        B.setdefault(c, "(quartz line: kept clear)")
    # ground the Mekanism plan keeps: the walkway, the gas plants
    for z in range(9, 22):
        B.setdefault((35, 1, z), "(Mekanism walkway)")
    for x in range(29, 35):
        for z in range(16, 22):
            B.setdefault((x, 1, z), "(gas plants, stage 4-5)")
    # the stage 0 machines and their power (docs/foundry.md)
    for c, it in (((41, 1, 11), "mekanism:energized_smelter"), ((41, 1, 12), "mekanism:enrichment_chamber"),
                  ((41, 1, 15), "mekanism:metallurgic_infuser"), ((42, 1, 18), "mekanismgenerators:heat_generator"),
                  ((42, 1, 17), "mekanism:basic_energy_cube")):
        B[c] = it
    for z in range(7, 17):
        B.setdefault((42, 1, z), UCABLE)
    return B


def outside():
    """What stands outside the building that the retrofit must miss: the old
    hut (its walls and roof, x -20..-10, z 0..14), the yard bench, the lava
    row (tools/lavafarm.py) and the yard where the bench stands."""
    B = {}
    for x in range(-20, -9):
        for z in range(0, 15):
            for y in range(0, 4):
                if x in (-20, -10) or z in (0, 14) or y == 3:
                    B[(x, y, z)] = "(old hut wall/roof)"
    for x, z in ((-14, 3), (-13, 3), (-12, 3)):            # the roof hole over the old pad
        B.pop((x, 3, z), None)
    B[(-13, 1, 3)] = "Crafty (old)"
    B[(-13, 0, 3)] = MODEM
    B[(-14, 0, 3)] = DRIVE
    B[(-12, 1, 3)] = CHEST
    B[(-13, 1, 4)] = MODEM
    B[(-13, 1, 5)] = MODEM
    for x in range(-8, -2):                                 # the yard bench (cobblestone) and
        for z in range(11, 17):                             # the infuser and manager on it
            for y in (0, 1, 2, 3):
                B[(x, y, z)] = "(yard bench)"
    import lavafarm as L
    for i in range(LAVA_N):
        z = L.Z0 + i - OZ
        x0 = L.X0 - OX
        for c, it in (((x0, 9, z), "lava"), ((x0, 8, z), "cobblestone"), ((x0 - 1, 10, z), "cobblestone"),
                      ((x0 + 1, 10, z), "cobblestone"), ((x0, 7, z), "dripstone"), ((x0, 5, z), "cauldron"),
                      ((x0 + 1, 5, z), "(lava round stands here)"), ((x0 + 2, 6, z), "(lava round path)")):
            B[c] = it
    B[(L.X0 - OX, 10, L.Z0 - OZ - 1)] = "cobblestone"
    B[(L.X0 - OX, 10, L.Z0 - OZ + LAVA_N)] = "cobblestone"
    return B


# ================================================================= the retrofit's cells, by stage
def deck_cells(zs, extra_free=()):
    """The deck for rows zs: cell -> block (shaft holes left open)."""
    out = {}
    special = {}
    for k, z in LINES.items():
        if z in zs:
            special.update({c: it for c, it in line_cells(k).items() if c[1] == 0})
    for c in TRUNK + BRIDGE_YARD + TRUNK_C:
        if c[1] == 0 and c[2] in zs:
            special[c] = CABLE
    for c in STRIPES:
        if c[2] in zs:
            special[c] = STRIPE
    holes = {(SHAFT_IN[0], 0, SHAFT_IN[1]), (SHAFT_OUT[0], 0, SHAFT_OUT[1])}
    for z in zs:
        for x in APRON_X:
            c = (x, 0, z)
            if c in holes or c in extra_free:
                continue
            out[c] = special.get(c, DECK)
    return out


def stage_cells(stage):
    """Retrofit cells of a stage: cell -> (block, how). how: 'new' (free
    cell), 'R' (replaces what is there: a wall), 'kyle' (by hand)."""
    S = {}

    def put(c, it, how="new"):
        assert c not in S, ("twice", c)
        S[c] = (it, how)
    if stage == 1:
        for c, it in deck_cells(APRON_N).items():
            put(c, it)
        for k in ("A", "B"):
            put((CHEST_X, 1, LINES[k]), CHEST)
        put(TRUNK[-1], CABLE)
        put(WALL_HOLE, CABLE, "kyle")
        for x, z in POSTS:
            put((x, 1, z), DECK)
            put((x, 2, z), LANTERN)
        for c in DESK_LINK:
            put(c, CABLE)
        put(DESK_HOLE, CABLE, "R")
    elif stage == 2:
        for c in BRIDGE_UP + BRIDGE_HUT:
            put(c, CABLE)
        put(BRIDGE_WALL, CABLE, "R")
    elif stage == 3:
        for c in WALL_W:
            put(c, LB1)
        for c in WALL_E:
            put(c, LB4)
    elif stage == 6:
        for c, it in deck_cells(APRON_S).items():
            put(c, it)
        put((CHEST_X, 1, LINES["C"]), CHEST)
        for x, z in POSTS_S:
            put((x, 1, z), DECK)
            put((x, 2, z), LANTERN)
    elif stage == 7:
        for c in NORTH:
            put(c, CABLE)
        for c in NORTH_HOLES:
            put(c, CABLE, "R")
        for c in NORTH_MODEMS:
            put(c, MODEM)
    elif stage == 8:
        for c in POWER_LINK:
            put(c, UCABLE)
        for c in TEP_DECK:
            put(c, DECK)
        for c in BRINE:
            put(c, PIPE)
        put(BRINE_HOLE, PIPE, "R")
    return S


REPLACES = {DESK_HOLE: "stone_bricks", WALL_HOLE: "deepslate_tiles", BRIDGE_WALL: "(old hut wall/roof)",
            NORTH_HOLES[0]: "stone_bricks", NORTH_HOLES[1]: "stone_bricks", BRINE_HOLE: "stone_bricks"}


def check():
    B, O = model(), outside()
    bad, seen = [], {}
    for st in (1, 2, 3, 6, 7, 8):
        for c, (it, how) in stage_cells(st).items():
            if c in seen:
                bad.append(f"stage {st}: {c} also in stage {seen[c]}")
            seen[c] = st
            there = B.get(c) or O.get(c)
            if how in ("R", "kyle"):
                if not there:
                    bad.append(f"stage {st}: {c} meant to replace a wall, but nothing is there")
                continue
            if there and not (st == 6 and there == "(yard bench)"):
                bad.append(f"stage {st}: {c} {it} clashes with {there}")
    # zones that must stay clear of the retrofit's blocks
    keep = {}
    for c in [(x, 1, z) for x in range(0, 45) for z in (1, 2)]:
        keep[c] = "drone lane"
    for x, y, z in HOVER_NOW + HOVER_C4:
        keep[(x, y, z)] = "hover row"
    for k, z in LINES.items():
        for y in range(1, 40):
            keep[(PAD_X, y, z)] = f"pad {k} column"
    for x, z in (SHAFT_IN, SHAFT_OUT):
        for y in range(-20, 3):
            keep[(x, y, z)] = "shaft"
    for y in (2,):
        for x in range(-9, -4):
            keep[(x, y, LINES["A"])] = "miners' service row"
    for c in seen:
        if c in keep:
            bad.append(f"{c} is in the {keep[c]}")
    # the hover row and parking must miss the pads' columns and the shafts
    cols = {(PAD_X, z) for z in LINES.values()} | {SHAFT_IN, SHAFT_OUT}
    for x, y, z in HOVER_NOW + HOVER_C4:
        if (x, z) in cols:
            bad.append(f"hover {x},{z} over a pad or shaft")
    for x, z in PARK_NOW + PARK_C4:
        if (x, z) in cols:
            bad.append(f"parking {x},{z} on a pad or shaft")
    for x, z in PARK_C4:
        if (x, 0, z) in O or (x, 1, z) in O:
            bad.append(f"parking {x},{z} on {O.get((x, 0, z)) or O.get((x, 1, z))}")
    # zones inside the building
    for c in AE2 + WORKSHOP + POWER:
        if c in B:
            bad.append(f"zone cell {c} taken by {B[c]}")
    for c in TEP:
        if c in B:
            bad.append(f"TEP {c} clashes with {B[c]}")
    # the trunk joins: cable next to the hall's cable, the desk's modem
    assert B.get((1, 1, 8)) == CABLE, B.get((1, 1, 8))
    assert B.get((10, 1, 29)) == MODEM
    assert B.get((10, 5, 16)) == MODEM
    assert B.get((36, 1, 9)) == "minecraft:chest" and B.get((36, 1, 19)) == "minecraft:chest"
    for c, what in REPLACES.items():
        there = (B.get(c) or O.get(c) or "").split(":")[-1]
        if what not in there:
            bad.append(f"{c} is {there!r}, expected {what}")
    print("\n".join(bad) if bad else f"ok: {len(seen)} retrofit cells, none on anything built or planned")
    return not bad


# ================================================================= maps
def draw(x0, x1, z0, z1, cell, title, legend):
    """A top-down map: x across (east to the right), z down (south down)."""
    lab = [" "] * (x1 - x0 + 1)
    for x in range(x0, x1 + 1):
        if x % 10 == 0:
            for i, ch in enumerate(str(x)):
                if x - x0 + i <= x1 - x0:
                    lab[x - x0 + i] = ch
    out = [title, "   x  " + "".join(lab), "      " + "".join(str(abs(x) % 10) for x in range(x0, x1 + 1))]
    for z in range(z0, z1 + 1):
        out.append(f"z{z:4d} " + "".join(cell(x, z) for x in range(x0, x1 + 1)))
    out.append(legend)
    return "\n".join(out)


def map_pads():
    B, O = model(), outside()
    S1, S2, S6 = stage_cells(1), stage_cells(2), stage_cells(6)
    hov = {(x, z) for x, _, z in HOVER_NOW}
    park = set(PARK_NOW)

    def cell(x, z):
        for y in (1,):
            if (x, 1, z) == (DISP_X, 1, LINES["A"]):
                return "T"
            if (x, 1, z) == (DISP_X, 1, LINES["B"]):
                return "K"
            if (x, 1, z) == (DISP_X, 1, LINES["C"]):
                return "3"
        if (x, z) in {(PAD_X, z2) for z2 in LINES.values()}:
            return "P"
        if (x, z) in (SHAFT_IN, SHAFT_OUT):
            return "v" if (x, z) == SHAFT_OUT else "^"
        for S in (S1, S6):
            if (x, 1, z) in S and S[(x, 1, z)][0] == CHEST:
                return "c"
            if (x, 2, z) in S and S[(x, 2, z)][0] == LANTERN:
                return "*"
        if (x, 1, z) in S1 and x == -1:
            return "+"
        if (x, z) in park and x < 0:
            return "L"
        if (x, z) == (-14, 3):
            return "o"
        if (x, 1, z) == WALL_HOLE or (x, 1, z) == (0, 1, 8):
            return "X"
        for c in BRIDGE_HUT + BRIDGE_UP + [BRIDGE_WALL]:
            if (x, z) == (c[0], c[2]):
                return "b"
        for S in (S1, S6):
            it = S.get((x, 0, z), (None,))[0]
            if it == CABLE:
                return "="
            if it == STRIPE:
                return "/"
            if it == DECK:
                return "." if S is S1 else ","
        if (x, z) in hov:
            return "h"
        if (x, z) in park and x < 0:
            return "L"
        if (x, 9, z) in O and O[(x, 9, z)] == "lava":
            return "~"
        if (x, 10, z) in O:
            return "#"
        if (x, 0, z) in O and "bench" in O[(x, 0, z)]:
            return "%"
        if x == -13 and z == 3:
            return "T"
        if (x, 0, z) in O or (x, 3, z) in O:
            return "H"
        if x >= 0:
            b = B.get((x, 1, z))
            if not b:
                return " "
            return {"computercraft:cable": "=", "computercraft:wired_modem_full": "m",
                    "minecraft:furnace": "F"}.get(b, "#")
        return " "
    leg = ("P pad (drive under it)  T Crafty  K Counter  3 pad 3  c drop chest  ^ in-shaft  v out-shaft\n"
           "= cable in the deck (y 0) / at the wall (x 0-1, y 1)  + riser (y 1)  X wall cell (Kyle)\n"
           "b bridge to the old base (stage 2)  . deck stage 1  , deck stage 6  / hazard stripe  * lantern post\n"
           "h helpers hover (y 13)  L loaders park (both as the code stands)  % yard bench (stage 6 clears it)\n"
           "H old hut  ~ # dripstone lava row (y 5-10)  F m = smelting hall furnaces, modems, cable")
    return draw(-20, 8, -1, 32, cell, "Pad court, top down (y 0-1), x -20..8", leg)


def map_site():
    B, O = model(), outside()

    def zone(x, z):
        if -9 <= x <= -1 and 4 <= z <= 17:
            return "P"
        if -20 <= x <= -10 and 0 <= z <= 14:
            return "H"
        if (x, z) in set(PARK_C4):
            return "L"
        if -11 <= x <= -4 and 19 <= z <= 31:
            return "~"
        if 46 <= x <= 49 and 5 <= z <= 8:
            return "E"
        if 0 <= x <= 44 and z in (1, 2):
            return "-"
        if 0 <= x <= 44 and 0 <= z <= 30:
            if x in (0, 9, 18, 27, 44) or z in (0, 30):
                return "#" if not (z in (14, 15, 16) and x in (9, 18, 27)) else " "
            if z == 3:
                return ":"
            if 1 <= x <= 8:
                return "s"
            if 10 <= x <= 17:
                return "S"
            if 19 <= x <= 26:
                if x in (19, 20) and 6 <= z <= 12:
                    return "A"
                if 21 <= x <= 24:
                    return " "
                return "y"
            if 29 <= x <= 33 and 5 <= z <= 7:
                return "G"
            if 28 <= x <= 36 and 21 <= z <= 28:
                return "Q"
            if 36 <= x <= 38 and 23 <= z <= 27:
                return "w"
            if 29 <= x <= 34 and 12 <= z <= 21:
                return "g"
            if 35 <= x <= 38 and 9 <= z <= 21:
                return "M"
            if 39 <= x <= 40:
                return "l"
            if 41 <= x <= 42 and 6 <= z <= 27:
                return "0"
            return "f"
        if 45 <= x <= 55 and 20 <= z <= 30:
            return "T"
        return " "
    leg = ("P pad court (west apron)  H old hut (Kyle's; old storage retired)  L loader parking (with C4)\n"
           "~ dripstone lava rows (fuel)  - drone lane  : lane screen / drone rack  # walls\n"
           "s smelting hall: 12 furnaces on Crafty's network   S storage room (+ a 4th barrel row, stage 3)\n"
           "y systems bay (old launch bay; corridor x 21-24 kept clear)  A AE2 corner (later)\n"
           "f foundry floor  G power corner  M Mekanism line + walkway  g pool and gas plants\n"
           "Q quartz line  w workshop bench  l operator lane  0 stage-0 plinth (factories, stage 6+)\n"
           "E evaporation tower (outside, stage 4)  T control tower (screens, CommandBlock)")
    return draw(-20, 56, -1, 32, zone, "The site, top down, x -20..56 (building's own frame; 1 char = 1 block)", leg)


def map_net():
    S = {}
    for st in (1, 2, 7):
        S.update(stage_cells(st))
    B = model()

    def cell(x, z):
        best = None
        for y in range(0, 8):
            if S.get((x, y, z), (None,))[0] in (MODEM, DRIVE):
                return "M" if S[(x, y, z)][0] == MODEM else "d"
        for y in range(7, -1, -1):
            if (x, y, z) in S:
                it, how = S[(x, y, z)]
                if it == CABLE:
                    return "R" if how in ("R", "kyle") else ("~" if y == 7 else "=")
                if it == MODEM:
                    return "M"
                if it == DRIVE:
                    return "d"
            b = B.get((x, y, z))
            if b in (CABLE,) and best is None:
                best = "-"
            if b == MODEM and best is None:
                best = "m"
            if b and "controller" in b:
                best = "K"
            if b and "furnace" in b and best is None:
                best = "f"
            if b and "barrel" == b.split(":")[-1].split("_")[0] and z == 29:
                best = "o"
        if best:
            return best
        if x in (0, 9, 18, 27, 44) and 0 <= z <= 30 and not (z in (14, 15, 16) and x != 0):
            return "#"
        if 0 <= x <= 44 and z in (0, 30):
            return "#"
        return " "
    leg = ("= new cable, low (y 0-2)  ~ new cable along the top of the rooms (y 7)  R wall cell replaced\n"
           "M new full modem  d new disk drive  - m f existing cable, modems, furnaces  K storage controller\n"
           "(the bridge's hut end, x -13..-10 at y 2, comes out once the old chests are empty)")
    return draw(-14, 44, 2, 30, cell, "The cable network, top down", leg)


def map_foundry():
    B = model()
    S8 = stage_cells(8)
    S7 = stage_cells(7)
    SYM = (("chest", "C"), ("sorter", "S"), ("transporter", "t"), ("enrichment", "E"),
           ("smelter", "M"), ("heat_gen", "H"), ("crusher", "R"), ("purification", "P"),
           ("injection", "I"), ("dissolution", "D"), ("washer", "W"), ("crystallizer", "Y"),
           ("universal_cable", "="), ("mechanical_pipe", "w"), ("pressurized_tube", "g"),
           ("stone_bricks", "#"), ("water", "~"), ("pump", "U"), ("walkway", "."),
           ("gas plants", "%"), ("kept clear", "q"), ("reconstructor", "q"), ("coal_generator", "q"),
           ("water_wheel", "q"), ("encased_fan", "q"), ("cobblestone", "q"), ("energy_cube", "B"),
           ("infuser", "I"), ("iron_bars", "|"), ("polished_deepslate", "#"), ("deepslate", "#"),
           ("glass", '"'), ("ladder", "#"))

    def sym(b):
        n = b if b.startswith("(") else b.split(":")[-1]
        for k, v in SYM:
            if k in n:
                return v
        return "?"

    def cell(x, z):
        if (x, 1, z) in S7:
            return "M"
        b = B.get((x, 1, z))
        if b and not b.startswith("("):
            return sym(b)
        if (x, 2, z) in S8:
            return "u"
        if (x, 1, z) in set(POWER):
            return "G"
        if (x, 1, z) in set(WORKSHOP):
            return "w"
        if (x, 1, z) in set(TEP):
            return "E"
        if b:
            return sym(b)
        for y in range(7, 1, -1):
            if (x, y, z) in S7:
                return "~"
        if (x, 9, z) in S8 or (x, 9, z) == BRINE_HOLE:
            return "b"
        return " "
    leg = ("Mekanism line (tools/mekline.py, as at stage 5) and stage 0 on the plinth, ground floor (y 1)\n"
           "G power corner (generators, cube; y 1)  u its universal cable (y 2), joining the line's at 36 2 11\n"
           "M CC modems on the line's inbox and outbox  ~ their CC cable (y 2-7)\n"
           "b brine pipe from the evaporation tower (y 9)  E the tower (outside)  w workshop bench\n"
           "% gas plants (stages 4-5)  q quartz line  . walkway  C chests  S sorter  t transporters\n"
           "E R P I D W Y M H machines (see mekline.py)  = Mekanism cable  B cube  # basin")
    return draw(27, 50, 3, 29, cell, "The foundry bay and east yard, top down", leg)


def map_store():
    B = model()
    S3 = stage_cells(3)

    def cell(x, z):
        if (x, 4, z) in S3:
            return "+" if S3[(x, 4, z)][0] == LB1 else "*"
        b = B.get((x, 1, z)) or B.get((x, 4, z))
        if not b:
            return " "
        n = b.split(":")[-1]
        return {"limited_barrel_1": "b", "limited_barrel_4": "B", "chest": "s", "wired_modem_full": "m",
                "ladder": "H"}.get(n, "#")
    leg = ("b limited barrels I (west wall)  B limited barrels IV (east wall)  s chests (north wall)\n"
           "+ new limited barrel I at y 4   * new limited barrel IV at y 4   m desk modems  H ladder")
    return draw(9, 18, 3, 29, cell, "Storage room: the wall raise (stage 3), top down", leg)


# ================================================================= bills
def items(stage):
    need = {}
    for c, (it, how) in stage_cells(stage).items():
        need[it] = need.get(it, 0) + 1
    if stage == 1:
        need[DRIVE] = need.get(DRIVE, 0)
        need["minecraft:floppy_disk"] = "the one from the old drive"
    return need


# ================================================================= lab steps
def wgoto(x, y, z):
    wx, wy, wz = W(x, y, z)
    return f"goto|{wx}|{wy}|{wz}"


def fetch(need):
    return "fetch|" + ",".join(f"{k}={v}" for k, v in need.items() if isinstance(v, int) and v > 0) + "|dump"


def walk_rows(rows, y, act):
    """Visit cells row by row (rows: [(z, [x, ...]), ...]), standing at
    height y, snaking east and west. One goto to the first cell, then low
    moves only (dig clears grass in the way; shaft holes are stepped over,
    never into, as the turtle stays at y). act(x, z) gives the steps there."""
    s, at = [], None
    for i, (z, xs) in enumerate(rows):
        xs = sorted(xs, reverse=bool(i % 2))
        for x in xs:
            if at is None:
                s += [wgoto(x, y, z)]
            else:
                ax, az = at
                if az != z:
                    s += ["face|1"] + ["dig", "fwd|1"] * (z - az)
                if ax != x:
                    s += [f"face|{0 if x > ax else 2}"] + ["dig", "fwd|1"] * abs(x - ax)
            s += act(x, z)
            at = (x, z)
    return s


def ops_deck(zs, cells_extra):
    """Lay a deck stretch, standing at y 1 and putting each block in at y 0
    (grass and dirt there are dug out first)."""
    deck = deck_cells(zs)
    need = {}
    for it in deck.values():
        need[it] = need.get(it, 0) + 1
    for c, it in cells_extra:
        need[it] = need.get(it, 0) + 1
    rows = [(z, [x for x in APRON_X if (x, 0, z) in deck]) for z in sorted({c[2] for c in deck})]
    s = [fetch(need)]
    s += walk_rows(rows, 1, lambda x, z: ["digDown", f"placeDown|{deck[(x, 0, z)]}",
                                          f"expect|down|{deck[(x, 0, z)].split(':')[1]}"])
    s += ["up|2"]
    for c, it in cells_extra:
        x, y, z = c
        s += [wgoto(x, y + 1, z), f"placeDown|{it}", f"expect|down|{it.split(':')[1]}"]
    return s


def ops(job):
    if job == "deck":
        extra = [((CHEST_X, 1, LINES[k]), CHEST) for k in ("A", "B")]
        extra += [(TRUNK[-1], CABLE)]
        for x, z in POSTS:
            extra += [((x, 1, z), DECK), ((x, 2, z), LANTERN)]
        s = ops_deck(APRON_N, extra)
    elif job == "padc":
        extra = [((CHEST_X, 1, LINES["C"]), CHEST)]
        for x, z in POSTS_S:
            extra += [((x, 1, z), DECK), ((x, 2, z), LANTERN)]
        s = ops_deck(APRON_S, extra)
    elif job == "bridge":
        # inside the hut from the old pad's roof hole: along the row over
        # Crafty, the drop chest and the in-shaft (y 2, z 3), putting a cable
        # to the south of each (z 4); then outside, through the hut's east wall
        s = [f"fetch|{CABLE}=6|dump"]
        s += [wgoto(-13, 2, 3), "face|1", "inspect|front", f"place|{CABLE}", "expect|front|cable",
              "face|0", "fwd|1", "face|1", "inspect|front", f"place|{CABLE}", "expect|front|cable",
              "face|0", "fwd|1", "face|1", "inspect|front", f"place|{CABLE}", "expect|front|cable",
              "face|2", "fwd|1", "up|3"]
        s += [wgoto(-9, 2, 4), "inspect|down", f"placeDown|{CABLE}", "expect|down|cable",
              "face|2", "expect|front|cobblestone", "dig", f"place|{CABLE}", "expect|front|cable",
              "up|1", f"placeDown|{CABLE}", "expect|down|cable"]
    elif job == "unbridge":
        # stage 6, once the old chests are empty: the bridge's hut end out
        # again and the hut wall made good (the yard part stays in the deck)
        s = [f"fetch|minecraft:cobblestone=1|dump"]
        s += [wgoto(-13, 2, 3), "face|1", "expect|front|cable", "dig",
              "face|0", "fwd|1", "face|1", "expect|front|cable", "dig",
              "face|0", "fwd|1", "face|1", "expect|front|cable", "dig",
              "face|2", "fwd|1", "up|3"]
        s += [wgoto(-9, 3, 4), "expect|down|cable", "digDown", "down|1", "face|2",
              "expect|front|cable", "dig", "place|minecraft:cobblestone", "expect|front|cobblestone",
              "expect|down|cable", "digDown"]
    elif job == "bench":
        # the yard bench's cobblestone, a layer at a time from the top (the
        # infuser and the Inventory Manager must be off it first: see the plan)
        s = []
        rows = [(z, list(range(-8, -2))) for z in range(11, 17)]
        for y in (3, 2, 1, 0):
            s += walk_rows(rows, y + 1, lambda x, z: ["digDown"])
            s += ["up|2"]
    elif job == "lava2":
        import lavafarm as L
        old = L.X0
        L.X0 = LAVA2_X0
        s = L.build(LAVA_N)
        L.X0 = old
    else:
        sys.exit(__doc__)
    s += ["inv", "home", "handin|"]
    return ";".join(s)


# ================================================================= fit plans
def fit(name):
    """A fit plan (tools/fitout.py's format) for the jobs inside the building
    that need a wall cell taken out, which the lab bench may not dig."""
    if name == "desklink":
        jobs = [("R", DESK_HOLE, CABLE, 4)] + [("P", c, CABLE, 0) for c in sorted(DESK_LINK, reverse=True)]
    elif name == "walls":
        jobs = [("P", c, LB1 + " east", 2) for c in WALL_W] + [("P", c, LB4 + " west", 4) for c in WALL_E]
    elif name == "northline":
        jobs = [("P", NORTH_MODEMS[0], MODEM, 0)] + [("P", (36, y, 8), CABLE, 0) for y in range(2, 7)]
        jobs += [("P", NORTH_MODEMS[1], MODEM, 0)] + [("P", (37, y, 19), CABLE, 0) for y in range(2, 7)]
        jobs += [("P", (37, 7, z), CABLE, 0) for z in range(19, 7, -1)]
        jobs += [("P", (36, 7, z), CABLE, 0) for z in (8, 7, 6)]
        jobs += [("P", (x, 7, 5), CABLE, 0) for x in range(36, 27, -1)]
        jobs += [("R", NORTH_HOLES[1], CABLE, 4)]
        jobs += [("P", (x, 7, 5), CABLE, 1) for x in range(26, 18, -1)]
        jobs += [("R", NORTH_HOLES[0], CABLE, 4)]
        jobs += [("P", (x, 7, 5), CABLE, 1) for x in range(17, 10, -1)]
        jobs += [("P", (10, 7, z), CABLE, 1) for z in range(5, 16)]
        jobs += [("P", (10, 7, 16), CABLE, 2), ("P", (10, 6, 16), CABLE, 2)]
    else:
        sys.exit(__doc__)
    pal = []
    for _, _, it, _ in jobs:
        e = it if " " in it else it + " -"
        if e not in pal:
            pal.append(e)
    out = ["S 22 2 33", f"P {len(pal)}"] + pal + [f"O {len(jobs)}"]
    for k, (x, y, z), it, s in jobs:
        e = it if " " in it else it + " -"
        out.append(f"{k} {x} {y} {z} {pal.index(e)} {s}")
    return "\n".join(out)


if __name__ == "__main__":
    a = sys.argv[1:]
    cmd = a[0] if a else "check"
    if cmd == "check":
        sys.exit(0 if check() else 1)
    elif cmd == "map":
        print({"pads": map_pads, "site": map_site, "net": map_net, "foundry": map_foundry,
               "store": map_store}[a[1] if len(a) > 1 else "site"]())
    elif cmd == "items":
        for k, v in items(int(a[1])).items():
            print(f"{v:>5}  {k}")
    elif cmd == "ops":
        print(ops(a[1]))
    elif cmd == "fit":
        print(fit(a[1]))
    else:
        print(__doc__)
