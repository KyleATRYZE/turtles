#!/usr/bin/env python3
"""The factory retrofit (docs/factory-retrofit.md): every cell the retrofit
adds, checked against everything built or planned, plus the maps, the bills
and the lab steps for the swarm's share. Prints only; it sends nothing.

    python3 tools/retrofit.py check            every retrofit cell is free in the plans
    python3 tools/retrofit.py map site|bay|section|roof|net|foundry|store
    python3 tools/retrofit.py items <stage>    bill of blocks for a stage (1 2 3 6 7 8)
    python3 tools/retrofit.py ops <job>        lab steps: shafts shaftc bridge unbridge minershafts lava2
    python3 tools/retrofit.py fit <plan>       a fit plan's text: pads pad3 desklink walls northline
                                               (save as blueprints/factory_<plan>.txt to use)

Coordinates are the factory building's own (corner -4448 71 1518; x east,
z south, y 1 = the ground floor, y 0 = the floor). Outside the building the
same frame is used: the west yard is x < 0. World = (-4448 + x, 71 + y,
1518 + z). Work inside the building is done by fit plans (they dig out any
block they replace, the lab may not); outside (the roof, the yard, the old
hut) by lab steps with goto in world coordinates.
"""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

OX, OY, OZ = -4448, 71, 1518


def W(x, y, z):
    return OX + x, OY + y, OZ + z


DECK = "minecraft:polished_deepslate"
STRIPE = "chipped:striped_yellow_concrete"
CABLE = "computercraft:cable"
MODEM = "computercraft:wired_modem_full"
DRIVE = "computercraft:disk_drive"
CHEST = "minecraft:chest"
GLASS = "minecraft:glass"
UCABLE = "mekanism:basic_universal_cable"
PIPE = "mekanism:basic_mechanical_pipe"
LB1 = "sophisticatedstorage:limited_barrel_1"
LB4 = "sophisticatedstorage:limited_barrel_4"

# ---------------------------------------------------------------- the pads, in the launch bay
# Along the bay's west side (x 20), north to south, so the big door's
# corridor (x 21-24) and the doorway from the store (x 18, z 14-16) stay
# clear. Each line runs along z: pad (drive in the floor under it), then the
# dispenser on its modem (in the floor), then (Crafty only) the drop chest.
# Crafty's miners come up an in-shaft beyond the chest and go down an
# out-shaft beyond the pad, as at the old base. Each pad's column is open to
# the sky: one cut in the upper floor (y 8) and one in the roof (y 17).
PAD_X = 20
LINES = {"A": (6, 7, 8), "B": (11, 12, None), "C": (18, 19, None)}   # pad z, dispenser z, chest z
WHO = {"A": "Crafty", "B": "Counter", "C": "pad 3"}
SHAFT_OUT, SHAFT_IN = (20, 5), (20, 9)       # Crafty's line only (x, z)
SLAB_Y, ROOF_Y = 8, 17                        # what each pad's sky shaft cuts (x 20: roof at y 17)
DROP_X = 19                                   # the cable down the west wall to each modem
CEIL_Y = 7                                    # the trunk under the upper floor
TRUNK_BAY = [(DROP_X, CEIL_Y, z) for z in range(7, 20)]
DROPS = {k: [(DROP_X, y, LINES[k][1]) for y in range(1, CEIL_Y)] for k in LINES}
FLOOR_CABLE = {k: (DROP_X, 0, LINES[k][1]) for k in LINES}    # under the drop, beside the modem
PARTITION = (18, 7, 16)                       # through the store's east partition, over the doorway
TRUNK_STORE = [(x, 7, 16) for x in range(17, 10, -1)] + [(10, 7, 16), (10, 6, 16)]   # to the west controller's modem 10 5 16
STRIPES = [(19, 0, 5), (21, 0, 5), (19, 0, 9), (21, 0, 9)]     # either side of the two shaft holes
GUARD = {k: [(x, y, z) for y in (9, 10) for x, z in ((PAD_X - 1, LINES[k][0]), (PAD_X + 1, LINES[k][0]),
                                                     (PAD_X, LINES[k][0] - 1), (PAD_X, LINES[k][0] + 1))]
         for k in LINES}                      # a glass ring round each hole in the upper floor

# where the drones wait, from Crafty (f = 20 1 7) and its pad (20 1 6):
#   helpers hover at (pad x + 3 + 2*slot, f.y + 12, pad z - 4)      helper.lua hover()
#   loaders park at (f.x + 4 + 2*(i%4), ground, f.z - 1 - 2*(i//4))  loader.lua parkSpot()
F = (PAD_X, 1, LINES["A"][1])
HOVER_NOW = [(PAD_X + 3 + 2 * s, 13, LINES["A"][0] - 4) for s in range(4)]      # inside the building!
HOVER_H1 = [(PAD_X + 3 + 2 * s, 21, LINES["A"][0] - 4) for s in range(4)]       # f.y + 20: over the roof
PARK_NOW = [(F[0] + 4 + 2 * (i % 4), F[2] - 1 - 2 * (i // 4)) for i in range(12)]

# ---------------------------------------------------------------- the other links
# the desk link: the smelting hall's cable (x 1, z 4..28) along the hall's
# south wall to the storage desk's modem row (10..15, 1, 29): the hall's 12
# furnaces join the store's network (and so Crafty's)
DESK_LINK = [(x, 1, 29) for x in range(1, 9)]
DESK_HOLE = (9, 1, 29)
# the bridge: the old base's network (modem -13 1 4 in the hut) across the
# yard to the hall's cable (1 1 8), for the drain; out again in stage 6
BRIDGE_HUT = [(-13, 2, 4), (-12, 2, 4), (-11, 2, 4)]
BRIDGE_WALL = (-10, 2, 4)                     # the hut's east wall (cobblestone)
BRIDGE_YARD = ([(-9, 2, 4), (-9, 1, 4), (-9, 0, 4), (-9, 0, 5), (-9, 0, 6)]
               + [(x, 0, 6) for x in range(-8, 0)] + [(-1, 0, 7), (-1, 0, 8), (-1, 1, 8)])
WALL_HOLE = (0, 1, 8)                         # Kyle: the deepslate tile out, a cable in

# the store wall raise: one more row (y 4) the length of both side walls
WALL_W = [(10, 4, z) for z in list(range(4, 13)) + list(range(18, 29))]
WALL_E = [(17, 4, z) for z in list(range(4, 13)) + list(range(18, 27))]

# the north line: from the bay's trunk east along z 5 at y 7 into the
# foundry, to modems on the Mekanism line's inbox (36 1 9) and outbox (36 1 19)
NORTH = ([(DROP_X, CEIL_Y, 6), (DROP_X, CEIL_Y, 5)] + [(x, 7, 5) for x in range(20, 27)]
         + [(x, 7, 5) for x in range(28, 37)] + [(36, 7, z) for z in (6, 7, 8)]
         + [(36, y, 8) for y in range(6, 1, -1)]
         + [(37, 7, z) for z in range(8, 20)] + [(37, y, 19) for y in range(6, 1, -1)])
NORTH_HOLES = [(27, 7, 5)]
NORTH_MODEMS = [(36, 1, 8), (37, 1, 19)]

# ---------------------------------------------------------------- the foundry
POWER = [(x, 1, z) for x in range(29, 34) for z in (5, 6, 7)]
POWER_LINK = [(34, 2, 6), (35, 2, 6)] + [(35, 2, z) for z in range(7, 11)] + [(36, 2, 10)]
WORKSHOP = [(x, 1, z) for x in range(36, 39) for z in range(23, 28)]
TEP = [(x, y, z) for x in range(46, 50) for z in range(5, 9) for y in range(1, 5)
       if x in (46, 49) or z in (5, 8) or y == 1]
TEP_DECK = [(x, 0, z) for x in range(46, 50) for z in range(5, 9)]
BRINE = ([(45, y, 7) for y in range(3, 10)] + [(x, 9, 7) for x in range(43, 33, -1)]
         + [(34, 9, z) for z in range(8, 17)])
BRINE_HOLE = (44, 9, 7)
# the AE2 corner (later): the smelting hall's south-east corner, beside the
# desk link (its CC modem at 8 1 28) and across the partition from the west
# storage controller (a storage bus on a cable through 9 5 15)
AE2 = [(x, y, z) for x in range(5, 9) for y in (1, 2, 3) for z in range(18, 29)]
AE2_BUS = (9, 5, 15)
AE2_RUN = [(8, 5, z) for z in range(15, 19)]

LAVA2_X0, LAVA_N = -4458, 11


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
    B[(-13, 2, 5)] = "Counter (old)"                         # world -4461 73 1523
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
def stage_cells(stage):
    """Retrofit cells of a stage: cell -> (block, how). how: 'new' (a free
    cell), 'R' (dug out and replaced: floor, wall, upper floor), 'cut'
    (dug out and left open), 'kyle' (by hand)."""
    S = {}

    def put(c, it, how="new"):
        assert c not in S, ("twice", c)
        S[c] = (it, how)
    if stage == 1:
        for k in ("A", "B"):
            pz, dz, cz = LINES[k]
            put((PAD_X, 0, pz), DRIVE, "R")
            put((PAD_X, 0, dz), MODEM, "R")
            put(FLOOR_CABLE[k], CABLE, "R")
            for c in DROPS[k]:
                put(c, CABLE)
            if cz:
                put((PAD_X, 1, cz), CHEST)
            put((PAD_X, SLAB_Y, pz), None, "cut")
            put((PAD_X, ROOF_Y, pz), None, "cut")
            for c in GUARD[k]:
                put(c, GLASS)
        for c in STRIPES:
            put(c, STRIPE, "R")
        for c in TRUNK_BAY + TRUNK_STORE:
            put(c, CABLE)
        put(PARTITION, CABLE, "R")
    elif stage == 2:
        for c in DESK_LINK:
            put(c, CABLE)
        put(DESK_HOLE, CABLE, "R")
        for c in BRIDGE_HUT + BRIDGE_YARD:
            put(c, CABLE)
        put(BRIDGE_WALL, CABLE, "R")
        put(WALL_HOLE, CABLE, "kyle")
    elif stage == 3:
        for c in WALL_W:
            put(c, LB1)
        for c in WALL_E:
            put(c, LB4)
    elif stage == 6:
        pz, dz, _ = LINES["C"]
        put((PAD_X, 0, pz), DRIVE, "R")
        put((PAD_X, 0, dz), MODEM, "R")
        put(FLOOR_CABLE["C"], CABLE, "R")
        for c in DROPS["C"]:
            put(c, CABLE)
        put((PAD_X, SLAB_Y, pz), None, "cut")
        put((PAD_X, ROOF_Y, pz), None, "cut")
        for c in GUARD["C"]:
            put(c, GLASS)
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
            PARTITION: "stone_bricks", NORTH_HOLES[0]: "stone_bricks", BRINE_HOLE: "stone_bricks"}
for _k, (_pz, _dz, _cz) in LINES.items():
    REPLACES[(PAD_X, 0, _pz)] = REPLACES[(PAD_X, 0, _dz)] = REPLACES[FLOOR_CABLE[_k]] = "polished_deepslate"
    REPLACES[(PAD_X, SLAB_Y, _pz)] = "polished_deepslate"
    REPLACES[(PAD_X, ROOF_Y, _pz)] = "deepslate_tiles"
for _c in STRIPES:
    REPLACES[_c] = "polished_deepslate"


def check():
    B, O = model(), outside()
    bad, seen = [], {}
    for st in (1, 2, 3, 6, 7, 8):
        for c, (it, how) in stage_cells(st).items():
            if c in seen:
                bad.append(f"stage {st}: {c} also in stage {seen[c]}")
            seen[c] = st
            there = B.get(c) or O.get(c)
            if how in ("R", "kyle", "cut"):
                want = REPLACES.get(c)
                if not there or not want or want not in there:
                    bad.append(f"stage {st}: {c} should replace {want}, finds {there}")
                continue
            if there:
                bad.append(f"stage {st}: {c} {it} clashes with {there}")
    # what must stay clear
    keep = {}
    for x in range(21, 25):                                     # the big door's corridor
        for z in range(5, 30):
            for y in range(1, 5):
                keep[(x, y, z)] = "big-door corridor"
    for x in (18, 19, 20, 26, 27):                              # the doorways and their approach
        for z in (14, 15, 16):
            for y in (1, 2, 3):
                keep[(x, y, z)] = "doorway"
    for k, (pz, dz, cz) in LINES.items():                       # pad columns: open to the sky
        for y in range(1, 40):
            if (PAD_X, y, pz) not in seen:
                keep[(PAD_X, y, pz)] = f"pad {k} column"
        for y in (1, 2):
            keep[(PAD_X + 1, y, dz)] = f"{WHO[k]}'s free east side (survey)"
    for x, z in (SHAFT_IN, SHAFT_OUT):
        for y in range(-20, 3):
            keep[(x, y, z)] = "miners' shaft"
    for z in range(5, 10):
        keep[(PAD_X, 2, z)] = "miners' service row (y 2)"
    for x, y, z in HOVER_H1:
        keep[(x, y, z)] = "hover row"
    for c in seen:
        if c in keep and seen[c] and stage_cells(seen[c])[c][1] != "cut":
            bad.append(f"{c} is in the {keep[c]}")
    for c, why in keep.items():
        if why.startswith("pad") and c in B and c[1] not in (SLAB_Y, ROOF_Y):
            bad.append(f"{c} ({why}) has {B[c]}")
        if why in ("big-door corridor", "miners' service row (y 2)") and c in B:
            bad.append(f"{c} ({why}) has {B[c]}")
    # the pad columns: nothing above the roof cut; the hover row above every roof it passes
    for k, (pz, _, _) in LINES.items():
        above = [y for (x, y, z) in B if x == PAD_X and z == pz and y > ROOF_Y]
        if above:
            bad.append(f"pad {k}: blocks above the roof at y {above}")
    for x, y, z in HOVER_H1:
        top = max([yy for (xx, yy, zz) in B if xx == x and zz == z] or [0])
        if top >= y:
            bad.append(f"hover {x},{z} at y {y} is not above the roof (top {top})")
    for x, y, z in HOVER_NOW:
        if not any(B.get((x, yy, z)) for yy in range(y + 1, 25)):
            bad.append(f"hover {x},{z} unexpectedly open to the sky")
    cols = {(PAD_X, LINES[k][0]) for k in LINES} | {SHAFT_IN, SHAFT_OUT}
    for x, z in [(h[0], h[2]) for h in HOVER_H1] + PARK_NOW:
        if (x, z) in cols:
            bad.append(f"waiting spot {x},{z} over a pad or shaft")
    for c in AE2 + AE2_RUN + WORKSHOP + POWER:
        if c in B:
            bad.append(f"zone cell {c} taken by {B[c]}")
    if B.get(AE2_BUS, "").split(":")[-1] != "stone_bricks" or B.get((10, 5, 15)) != "sophisticatedstorage:controller":
        bad.append("AE2 bus cell")
    for c in TEP:
        if c in B:
            bad.append(f"TEP {c} clashes with {B[c]}")
    assert B.get((1, 1, 8)) == CABLE and B.get((10, 1, 29)) == MODEM and B.get((10, 5, 16)) == MODEM
    assert B.get((36, 1, 9)) == "minecraft:chest" and B.get((36, 1, 19)) == "minecraft:chest"
    print("\n".join(bad) if bad else f"ok: {len(seen)} retrofit cells, none on anything built or planned")
    return not bad


def roof_top(x, z, B):
    return max([y for (xx, y, zz) in B if xx == x and zz == z] or [0])


# ================================================================= maps
def draw(x0, x1, z0, z1, cell, title, legend, row="z", col="x"):
    """A grid: col across, row down."""
    lab = [" "] * (x1 - x0 + 1)
    for x in range(x0, x1 + 1):
        if x % 10 == 0:
            for i, ch in enumerate(str(x)):
                if x - x0 + i <= x1 - x0:
                    lab[x - x0 + i] = ch
    out = [title, f"   {col}  " + "".join(lab), "      " + "".join(str(abs(x) % 10) for x in range(x0, x1 + 1))]
    rows = range(z0, z1 + 1) if z0 <= z1 else range(z0, z1 - 1, -1)
    for z in rows:
        out.append(f"{row}{z:4d} " + "".join(cell(x, z) for x in range(x0, x1 + 1)))
    out.append(legend)
    return "\n".join(out)


def _all():
    S = {}
    for st in (1, 2, 3, 6, 7, 8):
        S.update(stage_cells(st))
    return S


def map_bay():
    B = model()
    S = _all()
    pads = {(PAD_X, LINES[k][0]): k for k in LINES}
    disp = {(PAD_X, LINES[k][1]): k for k in LINES}

    def cell(x, z):
        if (x, z) in pads:
            return "P"
        if (x, z) in disp:
            return {"A": "T", "B": "K", "C": "3"}[disp[(x, z)]]
        if (x, z) in (SHAFT_IN, SHAFT_OUT):
            return "^" if (x, z) == SHAFT_IN else "v"
        if (x, 1, z) in S and S[(x, 1, z)][0] == CHEST:
            return "c"
        if (x, 1, z) in S and S[(x, 1, z)][0] == CABLE:
            return "|"
        if (x, 0, z) in S and S[(x, 0, z)][0] == STRIPE:
            return "/"
        if (x, 7, z) in S:
            return "R" if S[(x, 7, z)][1] == "R" else "~"
        if 21 <= x <= 24 and 5 <= z <= 29:
            return ":"
        b = B.get((x, 1, z)) or (B.get((x, 4, z)) if x in (10, 17) else None) or B.get((x, 2, z))
        if b:
            n = b.split(":")[-1]
            return {"limited_barrel_1": "b", "limited_barrel_4": "B", "chest": "s", "wired_modem_full": "m",
                    "ladder": "H", "iron_bars": "|", "monitor_advanced": "M"}.get(n, "#")
        if B.get((x, 0, z), "").endswith("cut_copper"):
            return "%"
        return " "
    leg = ("P pad (drive in the floor under it; sky shaft above)  T Crafty  K Counter  3 pad 3 (stage 6)\n"
           "c Crafty's drop chest  v out-shaft  ^ in-shaft (miners)  / hazard stripe in the floor\n"
           "| cable down the west wall (x 19, y 1-6) to each modem  ~ trunk under the upper floor (y 7)\n"
           "R partition cell replaced by cable  : big-door corridor, kept clear  % drone rack  M bay panel\n"
           "b B s storage room barrels and chests  m desk modems  H ladder")
    return draw(9, 28, 2, 30, cell, "The launch bay and the store beside it, top down (ground floor)", leg)


def map_section():
    B = model()
    S = _all()

    def cell(z, y):
        x = PAD_X
        c = (x, y, z)
        if c in S:
            it, how = S[c]
            if how == "cut":
                return "o"
            return {DRIVE: "d", MODEM: "m", CHEST: "c", CABLE: "=", STRIPE: "/", GLASS: "g"}.get(it, "?")
        if (z, y) in {(LINES[k][0], 1) for k in LINES}:
            return "P"
        if (z, y) in {(LINES[k][1], 1) for k in LINES}:
            return {LINES["A"][1]: "T", LINES["B"][1]: "K", LINES["C"][1]: "3"}[z]
        if any(LINES[k][0] == z for k in LINES) and 1 < y < 40 and (x, y, z) not in B:
            return "."
        if (x, z) in (SHAFT_IN, SHAFT_OUT) and y <= 0:
            return "."
        b = B.get(c)
        if not b:
            return " "
        n = b.split(":")[-1]
        return {"polished_deepslate": "#", "deepslate_tiles": "^", "deepslate_tile_stairs": "^",
                "iron_bars": "|", "cut_copper": "%", "stone_bricks": "#"}.get(n, "#")
    leg = ("Side view along x 20 (north on the left). P pad  T Crafty  K Counter  3 pad 3  d drive  m modem\n"
           "c drop chest  o cut out of the upper floor (y 8) and the roof (y 17)  . open to the sky\n"
           "g glass ring round each hole in the upper floor (y 9-10)  ^ roof  # floor, upper floor  | rack bars")
    return draw(2, 22, 20, -2, cell, "Section through the pads (x 20): z across, y up", leg, row="y", col="z")


def map_site():
    def zone(x, z):
        if -20 <= x <= -10 and 0 <= z <= 14:
            return "H"
        if (x, 0, z) in set(BRIDGE_YARD) or (x, 1, z) in set(BRIDGE_YARD):
            return "="
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
                return "A" if (5 <= x and 18 <= z <= 28) else "s"
            if 10 <= x <= 17:
                return "S"
            if 19 <= x <= 26:
                if x == PAD_X and z in {LINES[k][0] for k in LINES}:
                    return "P"
                if x in (19, 20) and 5 <= z <= 20 and z not in (14, 15, 16):
                    return "p"
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
    leg = ("P pads (open to the sky)  p pad strip: dispensers, cables, Crafty's chest and shafts\n"
           "s smelting hall (12 furnaces, on the network from stage 2)  A AE2 corner (later)\n"
           "S storage room (+ a 4th barrel row, stage 3)  y launch bay: corridor x 21-24 kept clear\n"
           "H old hut (Kyle's; its storage drained and retired)  = bridge for the drain (stage 2, temporary)\n"
           "~ dripstone lava rows (fuel)  - drone lane  : lane screen / drone rack  # walls\n"
           "f foundry floor  G power corner  M Mekanism line + walkway  g pool and gas plants\n"
           "Q quartz line  w workshop bench  l operator lane  0 stage-0 plinth (factories, stage 6+)\n"
           "E evaporation tower (outside, stage 4)  T control tower (screens, CommandBlock)")
    return draw(-20, 56, -1, 32, zone, "The site, top down, x -20..56 (building's own frame; 1 char = 1 block)", leg)


def map_roof():
    B = model()
    hov = {(x, z) for x, _, z in HOVER_H1}
    park = set(PARK_NOW)
    holes = {(PAD_X, LINES[k][0]) for k in LINES}

    def cell(x, z):
        if (x, z) in holes:
            return "O"
        if (x, z) in hov:
            return "h"
        if (x, z) in park:
            return "L"
        top = roof_top(x, z, B)
        if not top:
            return " "
        n = B[(x, top, z)].split(":")[-1]
        return '"' if "glass" in n else str(top % 10)
    leg = ("O roof hole over a pad (stage 1; the third in stage 6)  h helpers hover, y 21, with code change H1\n"
           "L loaders park on the roof (as the code stands)  digits: top block's y, last digit (14-18)\n"
           '" roof glass (glazed sawtooth faces at x 18 and 27, roof lights over the foundry)')
    return draw(14, 32, -1, 22, cell, "The roof over the launch bay, top down", leg)


def map_net():
    S = _all()
    B = model()

    def cell(x, z):
        for y in range(0, 8):
            if S.get((x, y, z), (None,))[0] in (MODEM, DRIVE):
                return "M" if S[(x, y, z)][0] == MODEM else "d"
        for y in range(7, -1, -1):
            if (x, y, z) in S:
                it, how = S[(x, y, z)]
                if it == CABLE:
                    return "R" if how in ("R", "kyle") and y > 0 else ("~" if y == 7 else "=")
        best = None
        for y in range(0, 8):
            b = B.get((x, y, z))
            if b == CABLE and best is None:
                best = "-"
            if b == MODEM and best is None:
                best = "m"
            if b and "controller" in b:
                best = "K"
            if b and "furnace" in b and best is None:
                best = "f"
        if best:
            return best
        if x in (0, 9, 18, 27, 44) and 0 <= z <= 30 and not (z in (14, 15, 16) and x != 0):
            return "#"
        if 0 <= x <= 44 and z in (0, 30):
            return "#"
        return " "
    leg = ("= new cable low (y 0-6)  ~ new cable under the upper floor (y 7)  R wall cell replaced\n"
           "M new full modem  d new disk drive  - m f K existing cable, modems, furnaces, storage controller\n"
           "(the yard part and the hut end of the bridge come out again in stage 6)")
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
        if it:
            need[it] = need.get(it, 0) + 1
    return need


# ================================================================= lab steps
def wgoto(x, y, z):
    wx, wy, wz = W(x, y, z)
    return f"goto|{wx}|{wy}|{wz}"


def ops_shafts(keys):
    """Each pad's sky shaft, from above: down through the roof tile, a glass
    ring round the hole in the upper floor (y 9-10), through the upper
    floor, down to the pad's column at y 2. digdown takes only plain ground
    (deepslate tiles and polished deepslate are)."""
    n = 8 * len(keys)
    s = [f"fetch|{GLASS}={n}|dump"]
    for k in keys:
        pz = LINES[k][0]
        s += [wgoto(PAD_X, ROOF_Y + 2, pz), "inspect|down", "expect|down|deepslate_tiles",
              f"digdown|{W(0, 10, 0)[1]}"]
        for y in (10, 9):
            if y == 9:
                s += ["down|1"]
            for f in (0, 1, 2, 3):
                s += [f"face|{f}", f"place|{GLASS}"]
        s += ["inspect|down", "expect|down|polished_deepslate", f"digdown|{W(0, 2, 0)[1]}",
              "inspect|down", "note|pad column open"]
    return s


def ops(job):
    if job == "shafts":
        s = ops_shafts(["A", "B"])
    elif job == "shaftc":
        s = ops_shafts(["C"])
    elif job == "bridge":
        # inside the hut from the old pad's roof hole, then across the yard
        # (lying on the grass at y 0) to the smelting hall's west wall
        n = len(BRIDGE_HUT) + len(BRIDGE_YARD) + 1
        s = [f"fetch|{CABLE}={n}|dump"]
        s += [wgoto(-13, 2, 3), "face|1", "inspect|front", f"place|{CABLE}", "expect|front|cable",
              "face|0", "fwd|1", "face|1", "inspect|front", f"place|{CABLE}", "expect|front|cable",
              "face|0", "fwd|1", "face|1", "inspect|front", f"place|{CABLE}", "expect|front|cable",
              "face|2", "fwd|1", "up|3"]
        low = [c for c in BRIDGE_YARD if c[1] == 0]
        s += [wgoto(low[0][0], 1, low[0][2])]
        at = None
        for x, _, z in low:
            if at:
                if z != at[1]:
                    s += [f"face|{1 if z > at[1] else 3}", "dig", "fwd|1"]
                if x != at[0]:
                    s += ["face|0", "dig", "fwd|1"]
            s += ["digDown", f"placeDown|{CABLE}", "expect|down|cable"]
            at = (x, z)
        s += ["up|1", f"placeDown|{CABLE}", "expect|down|cable"]          # the riser at -1 1 8
        s += [wgoto(-9, 2, 4), f"placeDown|{CABLE}", "expect|down|cable", "face|2",
              "expect|front|cobblestone", "dig", f"place|{CABLE}", "expect|front|cable",
              "up|1", f"placeDown|{CABLE}", "expect|down|cable"]
    elif job == "unbridge":
        # stage 6, once the old chests are empty: the hut end out again, the
        # hut wall made good, and the yard cable taken up
        s = ["fetch|minecraft:cobblestone=1|dump"]
        s += [wgoto(-13, 2, 3), "face|1", "expect|front|cable", "dig",
              "face|0", "fwd|1", "face|1", "expect|front|cable", "dig",
              "face|0", "fwd|1", "face|1", "expect|front|cable", "dig",
              "face|2", "fwd|1", "up|3"]
        s += [wgoto(-9, 3, 4), "expect|down|cable", "digDown", "down|1", "face|2",
              "expect|front|cable", "dig", "place|minecraft:cobblestone", "expect|front|cobblestone"]
        for y in (1, 0):
            s += ["expect|down|cable", "digDown", "down|1"]
        s += ["up|1"]
        low = [c for c in BRIDGE_YARD if c[1] == 0][1:]
        s += [wgoto(low[0][0], 1, low[0][2])]
        at = None
        for x, _, z in low:
            if at:
                if z != at[1]:
                    s += [f"face|{1 if z > at[1] else 3}", "fwd|1"]
                if x != at[0]:
                    s += ["face|0", "fwd|1"]
            s += ["expect|down|cable", "digDown"]
            at = (x, z)
        s += [wgoto(-1, 2, 8), "expect|down|cable", "digDown"]
    elif job == "minershafts":
        # Crafty's in- and out-shafts, through the bay floor down to the
        # miners' roads (out road world y 52, in road 56): only when mining resumes
        s = ["site|-4448|71|1518|factory_asfit3|factory_storeroom"]
        for (x, z), bottom in ((SHAFT_OUT, 52), (SHAFT_IN, 56)):
            s += [f"walk|{x}|1|{z}", f"digdown|{bottom}", f"up|{72 - bottom}"]
        s += ["leave"]
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
    """A fit plan (tools/fitout.py's format) for work inside the building:
    it digs out what each job replaces (the lab may not), every stand inside."""
    if name in ("pads", "pad3"):
        keys = ["A", "B"] if name == "pads" else ["C"]
        jobs = []
        for k in keys:
            pz, dz, cz = LINES[k]
            jobs += [("R", (PAD_X, 0, pz), DRIVE, 0), ("R", (PAD_X, 0, dz), MODEM, 0),
                     ("R", FLOOR_CABLE[k], CABLE, 0)]
            jobs += [("P", c, CABLE, 0) for c in DROPS[k]]
            if cz:
                jobs += [("P", (PAD_X, 1, cz), CHEST, 0)]
        if name == "pads":
            jobs += [("R", c, STRIPE, 0) for c in STRIPES]
            jobs += [("P", c, CABLE, 2) for c in TRUNK_BAY]
            jobs += [("R", PARTITION, CABLE, 4)]
            jobs += [("P", c, CABLE, 1) for c in TRUNK_STORE[:-1]]
            jobs += [("P", TRUNK_STORE[-1], CABLE, 2)]
    elif name == "desklink":
        jobs = [("R", DESK_HOLE, CABLE, 4)] + [("P", c, CABLE, 0) for c in sorted(DESK_LINK, reverse=True)]
    elif name == "walls":
        jobs = [("P", c, LB1 + " east", 2) for c in WALL_W] + [("P", c, LB4 + " west", 4) for c in WALL_E]
    elif name == "northline":
        jobs = [("P", NORTH_MODEMS[0], MODEM, 0)] + [("P", (36, y, 8), CABLE, 0) for y in range(2, 7)]
        jobs += [("P", NORTH_MODEMS[1], MODEM, 0)] + [("P", (37, y, 19), CABLE, 0) for y in range(2, 7)]
        jobs += [("P", (37, 7, z), CABLE, 0) for z in range(19, 7, -1)]
        jobs += [("P", (36, 7, z), CABLE, 0) for z in (8, 7, 6)]
        jobs += [("P", (x, 7, 5), CABLE, 0) for x in range(36, 27, -1)]
        jobs += [("R", NORTH_HOLES[0], CABLE, 4)]
        jobs += [("P", (x, 7, 5), CABLE, 1) for x in range(26, 19, -1)]
        jobs += [("P", (DROP_X, 7, 5), CABLE, 1), ("P", (DROP_X, 7, 6), CABLE, 1)]
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
        print({"site": map_site, "bay": map_bay, "section": map_section, "roof": map_roof, "net": map_net,
               "foundry": map_foundry, "store": map_store}[a[1] if len(a) > 1 else "site"]())
    elif cmd == "items":
        for k, v in items(int(a[1])).items():
            print(f"{v:>5}  {k}")
    elif cmd == "ops":
        print(ops(a[1]))
    elif cmd == "fit":
        print(fit(a[1]))
    else:
        print(__doc__)
