#!/usr/bin/env python3
"""The factory retrofit (docs/factory-retrofit.md): every cell the retrofit
adds or takes out, checked against everything built or planned, plus the
maps, the bills and the lab steps for the swarm's share. Prints only; it
sends nothing.

    python3 tools/retrofit.py check            every retrofit cell against the plans
    python3 tools/retrofit.py map site|lane|net|foundry|store
    python3 tools/retrofit.py items <stage>    bill of blocks for a stage (1 2 3 6 7 8)
    python3 tools/retrofit.py ops <job>        lab steps: apron bridge unbridge minershafts lava2
    python3 tools/retrofit.py fit <plan>       a fit plan's text: pitstop gatelink desklink walls rack2 (northline: superseded by the foundry link)
                                               (save as blueprints/factory_<plan>.txt to use)
    python3 tools/retrofit.py page             writes docs/factory-retrofit.html (the top-down plan page)

Coordinates are the factory building's own (corner -4448 71 1518; x east,
z south, y 1 = the ground floor, y 0 = the floor). Outside the building the
same frame is used: the west yard is x < 0. World = (-4448 + x, 71 + y,
1518 + z). Work inside the building (the drone lane included: the fit
walker gets onto it by the foundry's hatch, 32 1 3) is done by fit plans,
which dig out what they replace; outside by lab steps with goto in world
coordinates.
"""
import json, os, sys

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
COPPER = "minecraft:cut_copper"
BARS = "minecraft:iron_bars"
UCABLE = "mekanism:basic_universal_cable"
PIPE = "mekanism:basic_mechanical_pipe"
LB1 = "sophisticatedstorage:limited_barrel_1"
LB4 = "sophisticatedstorage:limited_barrel_4"

# ---------------------------------------------------------------- the drone lane (built)
# Two tracks along the back wall, x 0..44, behind a screen at z 3: the back
# track (z 1) runs west, the front track (z 2) east; 3 high (y 1-3); gates
# in both end walls (x 0 and x 44), portholes through the partitions (x 9,
# 18, 27). Drones fly it at y 2. Coming in: from the east by the east gate
# on the back track; from the west by the west gate on the front track.
# Going out: by the east gate on the front track.
LANE_X = range(0, 45)
BACK, FRONT, FLY = 1, 2, 2
WEST_IN = (-3, FLY, FRONT)        # where a drone comes down outside the west gate
EAST_IN = (46, FLY, BACK)         # ... and outside the east gate
EAST_OUT = (46, FLY, FRONT)       # where it leaves (then climbs)

# ---------------------------------------------------------------- crafter1's bench (smelting hall's stretch of the lane)
# Items reach the drones over the cable now (the loading bays in the racks),
# so there are no pit stops for them and no crafter2. crafter1 still needs a
# place on the hall's cable (its 12 furnaces) where new turtles can leave and
# the miners can be served until they have bays of their own: on the back
# track just inside the west gate, at drone height (y 2), on a block at y 1:
#   in-shaft (x 4), drop chest (5 2 1), crafter1 (6 2 1, modem 6 1 1),
#   its pad (7 2 1, drive 7 1 1: new turtles), out-shaft (x 8)
# Over it, y 3 is the miners' service row (dock 5 3 1, exit1 6 3 1, exit2
# 7 3 1).
PITS = {
    "A": {"who": "crafter1", "disp": (6, 2, 1), "pad": (7, 2, 1), "chest": (5, 2, 1)},
}
SHAFT_IN, SHAFT_OUT = (4, 1), (8, 1)            # (x, z): holes in the lane floor for the miners
CHEST_SEAT = (5, 1, 1)                          # a block under the drop chest

# the link to the store: the hall's cable ends at 1 1 4 (behind the screen);
# a cable through the screen post at 1 1 3, under the lane floor along the
# front track to under each modem
LINK_POST = (1, 1, 3)
LINK_FLOOR = [(1, 0, 3), (1, 0, 2), (2, 0, 2), (3, 0, 2), (4, 0, 2), (5, 0, 2), (6, 0, 2)]
LINK_UNDER = {"A": (6, 0, 1)}

# the old pit stop in the launch bay (in the plan; partly fitted): out of the
# way of the back track, and its two floor holes filled
OLD_PIT = [(21, 1, 1), (22, 1, 1), (23, 1, 1), (22, 2, 1), (23, 2, 1)]
OLD_HOLES = [(20, 0, 1), (24, 0, 1)]

# ---------------------------------------------------------------- the racks
# Rack 1 (built): the launch bay, 16 homes in two rows off the front track,
# x 19-26: a drone sits at (x, 1, 3) on the copper pad in the floor, or at
# (x, 3, 3) on the copper pad above it. Home i: x 19 + i % 8, low row first.
# Rack 2 (new, for the loaders): the same in the foundry's stretch, x 35-42,
# where the screen's bars at z 3 give way to the homes and move back to z 4.
RACK1_X, RACK2_X = range(19, 27), range(35, 43)


def homes(xs):
    return [(x, 1, 3) for x in xs] + [(x, 3, 3) for x in xs]


RACK2_CUT = [(x, y, 3) for x in RACK2_X for y in (1, 3)]          # bars or posts out
RACK2_PADS = [(x, 0, 3) for x in RACK2_X]                         # (the y 2 shelf is the bay modems)
RACK2_BARS = [(x, y, 4) for x in RACK2_X for y in (1, 3)]         # (y 2 is the strip)

# ---------------------------------------------------------------- the loading bays
# Items reach a docked drone over the cable: crafter1 (or Sortnado) pushes the
# load and fuel straight into it by its network name (turtle_<id>) and pulls
# hand-ins back. Each rack column's middle shelf, between the low home (y 1)
# and the high home (y 3), is a full-block wired modem: it touches both
# homes, so 8 modems serve 16 homes. Behind each shelf modem, in the bars'
# row (y 2, z 4), is one block of an 8-wide advanced-monitor strip: a
# peripheral that never leaves, so every modem stays switched on with or
# without a drone docked (a full-block modem switches itself off when its
# last peripheral goes; docs/cc-lessons.md, 1 and 3). The strip is the low
# shelf's panel; the old name board (y 4) becomes the high shelf's. One
# new computer in the wall at the west end drives both. The modems chain
# into each other; a connector modem in the x 18 wall (never clicked)
# touches the west end of the shelf, and Kyle runs cable from it through the
# wall to the storage room's network (Sortnado's store: it serves the bays
# until crafter1 moves onto the same cable). Everything is flush.
WIRED = "computercraft:wired_modem_full"
MONITOR = "computercraft:monitor_advanced"
PC = "computercraft:computer_normal"
BAYS1 = [(x, 2, 3) for x in RACK1_X]                      # replace the y 2 copper shelf; clicked
STRIP1 = [(x, 2, 4) for x in RACK1_X]                     # replace the y 2 bars; facing south
RACK_PC = (18, 4, 4)                                      # in the wall, touching the board's west end (a new computer)
RACK_LINK = (18, 2, 3)                                    # the wall modem touching the shelf's west end: the link
RACK_CONN = [RACK_LINK, (18, 2, 4), (18, 3, 4)]           # bricks -> modems (not clicked)
# (from RACK_LINK Kyle runs cable through the wall to the storage room's
# network; racks 2 and 3 and the foundry come in under the lane floor:)
RACK1_DOWN = [(18, 1, 3)]                                 # stage 6: a connector below the link
RACK_UNDER = (18, 0, 3)                                   # stage 6: floor cell, closed on all sides: cable
TRENCH1 = [(18, -1, 3), (18, -1, 2)]                      # stage 6: down to the lane-floor cable
# rack 2 (stage 6, loaders): the same, tied in at x 34
BAYS2 = [(x, 2, 3) for x in RACK2_X]
STRIP2 = [(x, 2, 4) for x in RACK2_X]
RACK2_CONN = [(34, 1, 3), (34, 2, 3)]
RACK2_UNDER = (34, 0, 3)
TRENCH2 = [(34, -1, 3)] + [(x, -1, 2) for x in range(34, 18, -1)]


# rack 3 (stage 6, miners and mapper1): the foundry's stretch x 28-31,
# 8 homes, the same design, tied in at x 27; the hatch at x 32 stays open
RACK3_X = range(28, 32)
RACK3_CUT = [(x, y, 3) for x in RACK3_X for y in (1, 3)]
RACK3_PADS = [(x, 0, 3) for x in RACK3_X]
RACK3_BARS = [(x, y, 4) for x in RACK3_X for y in (1, 3)]
BAYS3 = [(x, 2, 3) for x in RACK3_X]
STRIP3 = [(x, 2, 4) for x in RACK3_X]
RACK3_CONN = [(27, 1, 3), (27, 2, 3)]
RACK3_UNDER = (27, 0, 3)
TRENCH3 = [(27, -1, 3)]

# ---------------------------------------------------------------- the foundry on the cable (stage 7)
# Every plinth machine sits on a full-block wired modem in the plinth (its
# bottom face), switched on once and kept on by the machine itself; the
# infuser has a second one on its south face for the infusion items. A
# cable under the floor ties them to the rack trench (and so the store);
# the works computer sits in the floor beside the plinth. The piped line's
# inbox and outbox (build them as barrels, so crafter1 never takes them for
# storage) get a modem each under them, for the fallback.
F_MACHINES = {"smelter": (41, 0, 11), "chamber": (41, 0, 12), "infuser": (41, 0, 15)}
F_EXTRA = (41, 1, 16)                                 # the infuser's south face (RIGHT): infusion
F_EXTRA_UNDER = (41, 0, 16)
F_LINE = {"inbox": (36, 0, 9), "outbox": (36, 0, 19)}
F_PC = (43, 0, 12)                                    # the works computer, in the walkway floor
F_PC_MODEM = (43, -1, 12)                             # under it (not clicked)
F_TRUNK = ([(x, -1, 2) for x in range(35, 42)] + [(41, -1, z) for z in range(3, 20)]
           + [(x, -1, 9) for x in range(40, 35, -1)] + [(x, -1, 19) for x in range(40, 35, -1)] + [(42, -1, 12)])
F_BANK = [(41, 0, z) for z in (7, 8, 9)]              # later, with job=bank's smelters


def bay_world(c):
    return W(*c)

# the west gate's apron: the hill's shoulder comes up to y 3 outside it
APRON = [(-1, 1), (-2, 1), (-3, 1), (-4, 1), (-1, 2), (-2, 2), (-3, 2)]   # (x, z) columns dug down to y 1

# ---------------------------------------------------------------- the other links
DESK_LINK = [(x, 1, 29) for x in range(1, 9)]
DESK_HOLE = (9, 1, 29)
# the bridge for the drain: the old base's network (modem -13 1 4 in the
# hut) across the yard and in under the west gate to the lane's cable at 1 0 2
BRIDGE_HUT = [(-13, 2, 4), (-12, 2, 4), (-11, 2, 4)]
BRIDGE_WALL = (-10, 2, 4)
BRIDGE_YARD = ([(-9, 2, 4), (-9, 1, 4), (-9, 0, 4), (-9, 0, 3), (-9, 0, 2)]
               + [(x, 0, 2) for x in range(-8, 0)])
GATE_FLOOR = (0, 0, 2)                         # under the west gate: R (fit, from the gate)

WALL_W = [(10, 4, z) for z in list(range(4, 13)) + list(range(18, 29))]
WALL_E = [(17, 4, z) for z in list(range(4, 13)) + list(range(18, 27))]

# the north line: the store (west controller's modem 10 5 16) to modems on
# the Mekanism line's inbox (36 1 9) and outbox (36 1 19), along y 7
NORTH = ([(10, 6, 16), (10, 7, 16)] + [(x, 7, 16) for x in range(11, 18)] + [(x, 7, 16) for x in range(19, 27)]
         + [(x, 7, 16) for x in range(28, 38)] + [(37, 7, z) for z in (17, 18, 19)]
         + [(37, y, 19) for y in range(6, 1, -1)] + [(37, 7, z) for z in range(15, 7, -1)]
         + [(36, 7, 8)] + [(36, y, 8) for y in range(6, 1, -1)])
NORTH_HOLES = [(18, 7, 16), (27, 7, 16)]
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
AE2 = [(x, y, z) for x in range(5, 9) for y in (1, 2, 3) for z in range(18, 29)]
AE2_BUS = (9, 5, 15)
AE2_RUN = [(8, 5, z) for z in range(15, 19)]
LAVA2_X0, LAVA_N = -4458, 11


STAGES = (1, 2, 3, 6, 7, 8, 11)


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
    B[(-13, 1, 3)] = "crafter1 (old)"
    B[(-13, 0, 3)] = MODEM
    B[(-14, 0, 3)] = DRIVE
    B[(-12, 1, 3)] = CHEST
    B[(-13, 1, 4)] = MODEM
    B[(-13, 1, 5)] = MODEM
    B[(-13, 2, 5)] = "crafter2 (old)"                         # world -4461 73 1523
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
    cell), 'R' (dug out and replaced), 'cut' (dug out, left open)."""
    S = {}

    def put(c, it, how="new"):
        assert c not in S, ("twice", c)
        S[c] = (it, how)
    if stage == 1:
        for c in OLD_PIT:
            put(c, None, "cut")
        for c in OLD_HOLES:
            put(c, STRIPE, "R")
        put(LINK_POST, CABLE, "R")
        for c in LINK_FLOOR + list(LINK_UNDER.values()):
            put(c, CABLE, "R")
        for k, p in PITS.items():
            dx, dy, dz = p["disp"]
            px, py, pz = p["pad"]
            put((dx, dy - 1, dz), MODEM)
            put((px, py - 1, pz), DRIVE)
            if p["chest"]:
                put(p["chest"], CHEST)
        put(CHEST_SEAT, DECK)
        for c in DESK_LINK:
            put(c, CABLE)
        put(DESK_HOLE, CABLE, "R")
        for x, z in APRON:
            for y in (1, 2, 3):
                put((x, y, z), None, "dig")
    elif stage == 2:
        for c in BRIDGE_HUT + BRIDGE_YARD:
            put(c, CABLE)
        put(BRIDGE_WALL, CABLE, "R")
        put(GATE_FLOOR, CABLE, "R")
    elif stage == 3:
        for c in WALL_W:
            put(c, LB1)
        for c in WALL_E:
            put(c, LB4)
    elif stage == 6:                      # (racks 2 and 3 dropped: one rack, rack 1, for every drone)
        pass
    elif stage == 11:                     # rack 1's loading bays (Kyle, by hand, any time)
        for c in BAYS1:
            put(c, WIRED, "R")
        for c in STRIP1:
            put(c, MONITOR + " south", "R")
        put(RACK_PC, PC, "R")
        for c in RACK_CONN:
            put(c, WIRED, "R")
    elif stage == 7:                      # (the foundry on the cable: docs/foundry-v2.md, tools/foundry2plans.py)
        pass
    elif stage == 8:
        for c in POWER_LINK:
            put(c, UCABLE)
        for c in TEP_DECK:
            put(c, DECK)
        for c in BRINE:
            put(c, PIPE)
        put(BRINE_HOLE, PIPE, "R")
    return S


# what each replaced or cut cell holds today (checked against the model)
REPLACES = {DESK_HOLE: "stone_bricks", BRIDGE_WALL: "(old hut wall/roof)", GATE_FLOOR: "striped_yellow_concrete",
            LINK_POST: "polished_deepslate", NORTH_HOLES[0]: "stone_bricks", NORTH_HOLES[1]: "stone_bricks",
            BRINE_HOLE: "stone_bricks"}
for _c in LINK_FLOOR + list(LINK_UNDER.values()) + OLD_HOLES:
    REPLACES[_c] = "polished_deepslate" if _c[2] >= 3 else "striped_yellow_concrete"
for _c in OLD_HOLES:
    REPLACES[_c] = None                         # (holes: nothing there)
for _c in OLD_PIT:
    REPLACES[_c] = ""                           # (anything: the plan's pit stop, as far as it was fitted)
for _c in RACK2_CUT + BAYS2 + RACK3_CUT + BAYS3:
    REPLACES[_c] = ("iron_bars", "polished_deepslate")
for _c in RACK3_PADS + [RACK3_UNDER, F_LINE["inbox"], F_LINE["outbox"], F_PC]:
    REPLACES[_c] = "polished_deepslate"
for _c in RACK3_CONN:
    REPLACES[_c] = "stone_bricks"
for _c in list(F_MACHINES.values()) + [F_EXTRA_UNDER]:
    REPLACES[_c] = "deepslate_bricks"
for _c in BAYS1:
    REPLACES[_c] = "cut_copper"
for _c in STRIP1:
    REPLACES[_c] = "iron_bars"
for _c in [RACK_PC] + RACK_CONN + RACK1_DOWN:
    REPLACES[_c] = "stone_bricks"
for _c in [RACK_UNDER, RACK2_UNDER] + RACK2_CONN:
    REPLACES[_c] = "polished_deepslate"
for _c in [(x, 0, 3) for x in RACK2_X]:
    REPLACES[_c] = "polished_deepslate"


def lane_keep():
    """Cells of the lane that must stay open: both tracks at drone height,
    the front track full height, the back track's y 3 (the way over the pit
    stops), the gates, and the homes of both racks."""
    keep = {}
    pit = set()
    for p in PITS.values():
        for c in (p["disp"], p["pad"], p["chest"]):
            if c:
                pit |= {c, (c[0], c[1] - 1, c[2])}
    pit.add(CHEST_SEAT)
    for x in LANE_X:
        for y in (1, 2, 3):
            keep[(x, y, FRONT)] = "front track"
            if (x, y, BACK) not in pit and not (x == 44 and y == 3):
                keep[(x, y, BACK)] = "back track"
    for c in homes(RACK1_X):
        keep[c] = "rack home"
    for y in (1, 2):
        keep[(32, y, 3)] = "the foundry's hatch onto the lane"
    # (the miners' shafts are cut through the lane floor when mining resumes: ops minershafts)
    for x, y, z in (WEST_IN, EAST_IN, EAST_OUT):
        for yy in range(y, 40):
            keep[(x, yy, z)] = "approach column"
    return keep


def check():
    B, O = model(), outside()
    bad, seen = [], {}
    cut = set()
    for st in STAGES:
        for c, (it, how) in stage_cells(st).items():
            if c in seen:
                bad.append(f"stage {st}: {c} also in stage {seen[c]}")
            seen[c] = st
            there = B.get(c) or O.get(c)
            if how == "dig":
                if there:
                    bad.append(f"apron {c} has {there}")
                cut.add(c)
                continue
            if how in ("R", "cut"):
                want = REPLACES.get(c, "?")
                if want is None:
                    if there:
                        bad.append(f"stage {st}: {c} should be a hole, finds {there}")
                elif want == "":
                    pass
                elif not there or not any(w in there for w in ((want,) if isinstance(want, str) else want)):
                    bad.append(f"stage {st}: {c} should replace {want}, finds {there}")
                if how == "cut":
                    cut.add(c)
                continue
            if there:
                bad.append(f"stage {st}: {c} {it} clashes with {there}")
    keep = lane_keep()
    for c, why in keep.items():
        if c in seen and c not in cut:
            bad.append(f"{c} ({why}) gets {stage_cells(seen[c])[c][0]}")
        if c in B and c not in cut:
            bad.append(f"{c} ({why}) has {B[c]}")
        if c in O:
            bad.append(f"{c} ({why}) has {O[c]}")
    # the pit stops: crafter1's line as its survey will map it
    a = PITS["A"]
    dock, exit1, exit2 = [(c[0], c[1] + 1, c[2]) for c in (a["chest"], a["disp"], a["pad"])]
    ins = (2 * dock[0] - exit1[0], 2 * dock[2] - exit1[2])
    outs = (2 * exit2[0] - exit1[0], 2 * exit2[2] - exit1[2])
    if ins != SHAFT_IN or outs != SHAFT_OUT:
        bad.append(f"crafter1's shafts would be {ins} and {outs}")
    for c in (dock, exit1, exit2):
        if c in B or c in seen:
            bad.append(f"miners' service cell {c} not open")
    # the store link reaches the hall's cable, and each modem
    assert B.get((1, 1, 4)) == CABLE, B.get((1, 1, 4))
    for k, p in PITS.items():
        d = p["disp"]
        if LINK_UNDER[k] != (d[0], 0, d[2]):
            bad.append(f"no cable under {p['who']}'s modem")
    for c in AE2 + AE2_RUN + WORKSHOP + POWER:
        if c in B:
            bad.append(f"zone cell {c} taken by {B[c]}")
    for c in TEP:
        if c in B:
            bad.append(f"TEP {c} clashes with {B[c]}")
    bad += check_bays(B)
    assert B.get((10, 1, 29)) == MODEM and B.get((10, 5, 16)) == MODEM
    assert B.get((36, 1, 9)) == "minecraft:chest" and B.get((36, 1, 19)) == "minecraft:chest"
    print("\n".join(bad) if bad else f"ok: {len(seen)} retrofit cells, none on anything built or planned; the lane, the rack and the approaches open")
    return not bad


def check_bays(B):
    """The loading bays: every shelf modem touches its two homes and a block
    of the strip (its permanent peripheral) and nothing else that is a
    peripheral; the strips do not merge with the board; the computer touches
    the board; and the wire runs unbroken from every bay to the hall's cable
    (which the desk link ties to the store)."""
    bad = []
    A = _all()
    S = {c: it for c, (it, how) in A.items() if it}
    world = dict(B)
    for c, (it, how) in A.items():
        if how in ("cut", "dig"):
            world.pop(c, None)
    world.update(S)
    nb = lambda c: [(c[0] + d[0], c[1] + d[1], c[2] + d[2]) for d in
                    ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1))]
    PERI = ("monitor", "computer_", "chest", "barrel", "furnace", "disk_drive", "turtle", "controller", "mekanism")
    for bays, strip, xs in ((BAYS1, STRIP1, RACK1_X),):
        for c, m in zip(bays, strip):
            x = c[0]
            if world.get(c) != WIRED or not (world.get(m) or "").startswith(MONITOR):
                bad.append(f"bay {c}: no modem or no strip block behind it")
            for n in nb(c):
                it = world.get(n) or ""
                if n in ((x, 1, 3), (x, 3, 3)):
                    if it:
                        bad.append(f"bay {c}: its home {n} is not open ({it})")
                elif n != m and any(p in it for p in PERI):
                    bad.append(f"bay {c}: a clicked modem would also take in {it} at {n}")
            above = world.get((m[0], 3, 4)) or ""
            if "monitor" in above or "monitor" in (world.get((m[0], 1, 4)) or ""):
                bad.append(f"strip {m}: a monitor next to it would merge with it")
    if "monitor" not in (world.get((RACK_PC[0] + 1, RACK_PC[1], RACK_PC[2])) or ""):
        bad.append("the rack computer does not touch the board")
    # the wire: cables and full-block modems, from the hall cable's end
    wire = {c for c, it in world.items() if it and (it.startswith(CABLE) or it.startswith(WIRED)
                                                    or it.startswith(MODEM))}
    seen, todo = {RACK_LINK}, [RACK_LINK]
    while todo:
        c = todo.pop()
        for n in nb(c):
            if n in wire and n not in seen:
                seen.add(n)
                todo.append(n)
    for c in BAYS1 + [RACK_PC]:
        near = [n for n in nb(c) if n in seen] if c == RACK_PC else [c]
        if not any(n in seen for n in near):
            bad.append(f"{c} is not wired to rack 1's link into the storage room")
    # nothing of the wire shows but full blocks: a cable must be closed in on every side
    for c, it in S.items():
        if it.startswith(CABLE) and c[1] >= 0 and c in (set(TRENCH1) | set(TRENCH2) | {RACK_UNDER, RACK2_UNDER, RACK3_UNDER}):
            for n in nb(c):
                if not world.get(n) and n[1] >= 0:
                    bad.append(f"cable {c} shows through the open cell {n}")
    return bad


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
    for st in STAGES:
        S.update(stage_cells(st))
    return S


def map_lane():
    """The lane, its pit stops and racks: top down, x -5..46."""
    B = model()
    S = _all()
    marks = {}
    for k, p in PITS.items():
        marks[(p["disp"][0], p["disp"][2])] = "T" if k == "A" else "K"
        marks[(p["pad"][0], p["pad"][2])] = "P"
        if p["chest"]:
            marks[(p["chest"][0], p["chest"][2])] = "c"
    marks[SHAFT_IN] = "^"
    marks[SHAFT_OUT] = "v"
    for x in RACK1_X:
        marks[(x, 3)] = "1"
    for x in RACK2_X:
        marks[(x, 3)] = "2"
    marks[(WEST_IN[0], WEST_IN[2])] = "W"
    marks[(EAST_IN[0], EAST_IN[2])] = "E"
    marks[(EAST_OUT[0], EAST_OUT[2])] = "X"

    def cell(x, z):
        if (x, z) in marks:
            return marks[(x, z)]
        if 0 <= x <= 44 and z == BACK:
            return "<"
        if 0 <= x <= 44 and z == FRONT:
            return ">"
        if (x, z) in [(c[0], c[1]) for c in APRON]:
            return ","
        b = B.get((x, 2, z)) or B.get((x, 1, z))
        if (x, 1, z) in S and S[(x, 1, z)][0] == BARS:
            return "|"
        if b:
            n = b.split(":")[-1]
            return {"iron_bars": "|", "cut_copper": "%", "monitor_advanced": "M"}.get(n, "#")
        return " "
    leg = ("< back track (z 1, westbound)  > front track (z 2, eastbound); drones fly at y 2, gates at x 0 and 44\n"
           "T crafter1  P its pad  c crafter1's drop chest  ^ v miners' in- and out-shaft (in the lane floor)\n"
           "1 rack 1 (launch bay, built): 16 homes, low and high  2 rack 2 (foundry, stage 6): 16 more\n"
           "W drones come down here, outside the west gate, and go in on the front track (east)\n"
           "E ... outside the east gate, in on the back track (west)  X out by the east gate on the front track\n"
           ", the west gate's apron, dug out (the hill's shoulder)  | # % the screen, walls, rack pads")
    return draw(-5, 47, -1, 5, cell, "The drone lane, top down (x -5..47, z -1..5)", leg)


def map_site():
    def zone(x, z):
        if -20 <= x <= -10 and 0 <= z <= 14:
            return "H"
        if (x, 0, z) in set(BRIDGE_YARD):
            return "="
        if -11 <= x <= -4 and 19 <= z <= 31:
            return "~"
        if (x, z) in [(c[0], c[1]) for c in APRON]:
            return ","
        if 46 <= x <= 49 and 5 <= z <= 8:
            return "E"
        for k, p in PITS.items():
            for c in (p["disp"], p["pad"], p["chest"]):
                if c and (x, z) == (c[0], c[2]):
                    return {"A": "C", "B": "K"}[k] if c == p["disp"] else ("P" if c == p["pad"] else "c")
        if 0 <= x <= 44 and z in (1, 2):
            return "<" if z == 1 else ">"
        if z == 3 and x in RACK1_X:
            return "1"
        if z == 3 and x in RACK2_X:
            return "2"
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
                return " " if 21 <= x <= 24 else "y"
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
    leg = ("< > the drone lane: back track westbound, front track eastbound  C crafter1  P its pad  c drop chest\n"
           "1 rack 1 (helpers' homes)  2 rack 2 (loaders' homes)  : the lane's screen  , the west gate's apron\n"
           "s smelting hall (12 furnaces, crafter1's)  A AE2 corner (later)  S storage room (+ a 4th barrel row)\n"
           "y launch bay (corridor x 21-24 clear)  H old hut  = bridge for the drain (temporary)  ~ lava rows\n"
           "f foundry floor  G power corner  M Mekanism line  g pool, gas plants  Q quartz line  w workshop bench\n"
           "l operator lane  0 stage-0 plinth  E evaporation tower (outside)  T control tower (screens)  # walls")
    return draw(-20, 56, -1, 32, zone, "The site, top down, x -20..56 (building's own frame; 1 char = 1 block)", leg)


def map_net():
    S = _all()
    B = model()

    def cell(x, z):
        for y in range(0, 8):
            if S.get((x, y, z), (None,))[0] in (MODEM, DRIVE):
                return "M" if S[(x, y, z)][0] == MODEM else "d"
        for y in range(7, -1, -1):
            if (x, y, z) in S and S[(x, y, z)][0] == CABLE:
                return "R" if S[(x, y, z)][1] == "R" and y > 0 else ("~" if y == 7 else "=")
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
        if x in (0, 9, 18, 27, 44) and 0 <= z <= 30 and not (z in (14, 15, 16) and x != 0) and not z in (1, 2):
            return "#"
        if 0 <= x <= 44 and z in (0, 30):
            return "#"
        return " "
    leg = ("= new cable low (y 0-6; under the lane floor along the front track)  ~ new cable at y 7  R wall cell replaced\n"
           "M new full modem (crafter1's, the bays', the foundry's)  d new disk drive  - m f K existing cable, modems, furnaces, controller\n"
           "(the bridge from the hut, x -13..-1, comes out again once the old chests are empty)")
    return draw(-14, 44, 0, 30, cell, "The cable network, top down", leg)


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


def ops(job):
    if job == "apron":
        # the hill's shoulder outside the west gate, column by column from
        # above, down to y 1 (plain ground only; the lane's floor is y 0)
        s = []
        for x, z in APRON:
            s += [wgoto(x, 6, z), f"digdown|{W(0, 1, 0)[1]}", "inspect|down"]
        s += ["up|6"]
    elif job == "bridge":
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
        s += [wgoto(-9, 2, 4), f"placeDown|{CABLE}", "expect|down|cable", "face|2",
              "expect|front|cobblestone", "dig", f"place|{CABLE}", "expect|front|cable",
              "up|1", f"placeDown|{CABLE}", "expect|down|cable"]
    elif job == "unbridge":
        s = ["fetch|minecraft:cobblestone=1|dump"]
        s += [wgoto(-13, 2, 3), "face|1", "expect|front|cable", "dig",
              "face|0", "fwd|1", "face|1", "expect|front|cable", "dig",
              "face|0", "fwd|1", "face|1", "expect|front|cable", "dig",
              "face|2", "fwd|1", "up|3"]
        s += [wgoto(-9, 3, 4), "expect|down|cable", "digDown", "down|1", "face|2",
              "expect|front|cable", "dig", "place|minecraft:cobblestone", "expect|front|cobblestone"]
        for _ in (1, 0):
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
    elif job == "minershafts":
        # crafter1's in- and out-shaft, through the lane floor down to the
        # miners' roads (out road world y 52, in road 56): once mining resumes
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
    it digs out what each job replaces (the lab may not). Stands: 0 above,
    1 below, 2 east, 3 south, 4 west, 5 north of the block."""
    if name == "pitstop":
        jobs = [("D", c, None, 3) for c in OLD_PIT if c[1] == 2] + [("D", c, None, 3) for c in OLD_PIT if c[1] == 1]
        jobs += [("R", c, STRIPE, 0) for c in OLD_HOLES]
        jobs += [("D", LINK_POST, None, 5), ("R", (1, 0, 3), CABLE, 0), ("P", LINK_POST, CABLE, 5)]
        jobs += [("R", c, CABLE, 0) for c in LINK_FLOOR[1:]] + [("R", c, CABLE, 0) for c in LINK_UNDER.values()]
        for k, p in PITS.items():
            d, pd = p["disp"], p["pad"]
            jobs += [("P", (d[0], d[1] - 1, d[2]), MODEM, 0), ("P", (pd[0], pd[1] - 1, pd[2]), DRIVE, 0)]
        jobs += [("P", CHEST_SEAT, DECK, 0), ("P", PITS["A"]["chest"], CHEST, 0)]
    elif name == "gatelink":
        jobs = [("R", GATE_FLOOR, CABLE, 0)]
    elif name == "desklink":
        jobs = [("R", DESK_HOLE, CABLE, 4)] + [("P", c, CABLE, 0) for c in sorted(DESK_LINK, reverse=True)]
    elif name == "walls":
        jobs = [("P", c, LB1 + " east", 2) for c in WALL_W] + [("P", c, LB4 + " west", 4) for c in WALL_E]
    elif name == "rack2":
        jobs = [("D", c, None, 5) for c in RACK2_CUT if c[1] == 3] + [("D", c, None, 5) for c in RACK2_CUT if c[1] == 1]
        jobs += [("R", c, WIRED, 5) for c in BAYS2] + [("R", (x, 0, 3), COPPER, 0) for x in RACK2_X]
        jobs += [("P", c, BARS, 3) for c in RACK2_BARS] + [("P", c, MONITOR + " south", 3) for c in STRIP2]
    elif name == "northline":
        jobs = [("P", NORTH_MODEMS[0], MODEM, 0)] + [("P", (36, y, 8), CABLE, 0) for y in range(2, 7)]
        jobs += [("P", NORTH_MODEMS[1], MODEM, 0)] + [("P", (37, y, 19), CABLE, 0) for y in range(2, 7)]
        jobs += [("P", (37, 7, z), CABLE, 0) for z in (19, 18, 17)]
        jobs += [("P", (36, 7, 8), CABLE, 0)] + [("P", (37, 7, z), CABLE, 0) for z in range(8, 16)]
        jobs += [("P", (x, 7, 16), CABLE, 0) for x in range(37, 27, -1)]
        jobs += [("R", NORTH_HOLES[1], CABLE, 4)]
        jobs += [("P", (x, 7, 16), CABLE, 1) for x in range(26, 18, -1)]
        jobs += [("R", NORTH_HOLES[0], CABLE, 4)]
        jobs += [("P", (x, 7, 16), CABLE, 1) for x in range(17, 10, -1)]
        jobs += [("P", (10, 7, 16), CABLE, 1), ("P", (10, 6, 16), CABLE, 2)]
    else:
        sys.exit(__doc__)
    pal = []
    for _, _, it, _ in jobs:
        if it is None:
            continue
        e = it if " " in it else it + " -"
        if e not in pal:
            pal.append(e)
    out = ["S 22 2 33", f"P {len(pal)}"] + pal + [f"O {len(jobs)}"]
    for k, (x, y, z), it, s in jobs:
        if k == "D":
            out.append(f"D {x} {y} {z} {s}")
        else:
            e = it if " " in it else it + " -"
            out.append(f"{k} {x} {y} {z} {pal.index(e)} {s}")
    return "\n".join(out)


def layout_json():
    """The intended layout, for docs/factory-retrofit.html: building cells
    (the as-fitted shell and fit plans, top-down per floor), the retrofit's
    cells by stage, the zones, the pit stops, racks and the drone routes."""
    B = model()
    S = _all()
    cells = {}
    for (x, y, z), it in B.items():
        if it.startswith("("):
            continue
        cells.setdefault(f"{x},{y},{z}", it.split("[")[0])
    for (x, y, z), (it, how) in S.items():
        k = f"{x},{y},{z}"
        if how in ("cut", "dig"):
            cells.pop(k, None)
        else:
            cells[k] = it
    for (x, y, z), it in outside().items():
        if not it.startswith("(") and (x, y, z) not in S:
            cells.setdefault(f"{x},{y},{z}", "minecraft:" + it if ":" not in it else it)
    pits = {k: {"who": p["who"], "disp": p["disp"], "pad": p["pad"], "chest": p["chest"]} for k, p in PITS.items()}
    routes = {
        "west in, to a home": [WEST_IN, (0, FLY, FRONT), (22, FLY, FRONT), (22, 1, 3)],
        "east in, to a home": [EAST_IN, (44, FLY, BACK), (24, FLY, BACK), (24, FLY, FRONT), (24, 3, 3)],
        "out": [(30, FLY, FRONT), (44, FLY, FRONT), EAST_OUT],
    }
    return {"cells": cells, "pits": pits, "routes": routes,
            "rack1": homes(RACK1_X), "rack2": homes(RACK2_X),
            "shafts": [SHAFT_IN, SHAFT_OUT], "apron": APRON}


# ================================================================= the page
CAT = [  # (code, label, light colour, dark colour)
    ("g", "Outside ground", "#e3e6dc", "#23272a"),
    ("f", "Floor", "#d6d3cc", "#2b2c31"),
    ("w", "Walls and posts", "#5f6168", "#8a8c93"),
    ("L", "Drone lane (hazard floor)", "#e9c43f", "#b89a2c"),
    ("b", "Lane screen (iron bars)", "#9a9da4", "#6b6e75"),
    ("r", "Rack home (copper pad)", "#c47a4a", "#d08a5a"),
    ("S", "Storage barrels and chests", "#a3753f", "#9c7444"),
    ("d", "Storage desk (modems, In/Out, Sortnado)", "#3d6f8f", "#5a92b4"),
    ("F", "Furnaces (crafter1's bank)", "#7a4a3a", "#a0624e"),
    ("c", "Cable, existing", "#7d8794", "#8f99a6"),
    ("n", "New cable (retrofit; under the floor or overhead)", "#2f8a74", "#5cc0a6"),
    ("N", "New cable under the lane floor", "#2f8a74", "#5cc0a6"),
    ("T", "crafter1", "#16614f", "#7fe0c6"),
    ("K", "crafter2", "#2f5fae", "#7ea8ee"),
    ("P", "Launch pad (drive under it)", "#e5484d", "#ff7b7f"),
    ("h", "Drop chest", "#b98a3a", "#d6a650"),
    ("M", "Mekanism machines", "#4a7fa8", "#6aa2cc"),
    ("m", "Mekanism pipes, tubes, cable", "#9db7cc", "#4f6d84"),
    ("Q", "Quartz line", "#a98fd0", "#bba6e0"),
    ("p", "Plinth, operator lane", "#b8b0a3", "#46443f"),
    ("s", "Screens (monitors) and stations", "#2bb3c8", "#47cde0"),
    ("H", "Old hut", "#8b7d6b", "#9c8f7d"),
    ("v", "Lava rows (fuel)", "#e8682a", "#ff8a4c"),
    ("x", "Shaft holes (miners)", "#23242a", "#000000"),
]


def page_grid():
    B = model()
    S = _all()
    O = outside()
    new = {c: it for c, (it, how) in S.items() if how not in ("cut", "dig") and it}
    gone = {c for c, (it, how) in S.items() if how in ("cut", "dig")}
    X0, X1, Z0, Z1 = -20, 56, -2, 33
    pit_codes = {}
    for k, p in PITS.items():
        pit_codes[(p["disp"][0], p["disp"][2])] = "T" if k == "A" else "K"
        pit_codes[(p["pad"][0], p["pad"][2])] = "P"
        if p["chest"]:
            pit_codes[(p["chest"][0], p["chest"][2])] = "h"
    rows, tips = [], []

    def at(x, y, z):
        c = (x, y, z)
        if c in gone and c not in new:
            return None
        return new.get(c) or B.get(c) or O.get(c)

    def short(n):
        return n.split(":")[-1].replace("_", " ") if n else ""

    for z in range(Z0, Z1 + 1):
        row, trow = "", []
        for x in range(X0, X1 + 1):
            stack = [(y, at(x, y, z)) for y in range(0, 6 if x >= 0 else 11)]
            names = [n for _, n in stack if n]
            code = "g"
            if (x, z) in pit_codes:
                code = pit_codes[(x, z)]
            elif (x, z) in (SHAFT_IN, SHAFT_OUT):
                code = "x"
            else:
                floor = at(x, 0, z)
                low = [n for y, n in stack if 1 <= y <= 3 and n] + ([n for y, n in stack if y > 3 and n] if x < 0 else [])
                allnew = [new[(x, y, z)] for y in range(0, 8) if (x, y, z) in new]
                if code == "g":
                    for n in low + ([floor] if floor else []):
                        t = n
                        if t.startswith("(old hut") or t.startswith("crafter1 (old)") or t.startswith("crafter2 (old)"):
                            code = "H"
                        elif t in ("lava", "cauldron", "dripstone", "cobblestone") and 19 <= z <= 31:
                            code = "v"
                        elif "monitor" in t or "computer_" in t or "wireless_modem" in t or "chat_box" in t or "player_detector" in t:
                            code = "s"
                        elif "sophisticatedstorage" in t:
                            code = "S" if "controller" not in t else "d"
                        elif "minecraft:barrel" in t or ("wired_modem" in t and z == 29 and 10 <= x <= 15):
                            code = "d"
                        elif "furnace" in t:
                            code = "F"
                        elif t.startswith("mekanism") and ("cable" in t or "pipe" in t or "tube" in t or "transporter" in t):
                            code = "m"
                        elif t.startswith("mekanism") or t == "minecraft:chest" and 30 <= x <= 37:
                            code = "M"
                        elif t.startswith(("actuallyadditions", "create:")) or ("cobblestone" in t and 27 <= x <= 36 and 21 <= z <= 28) or t == "minecraft:water" and 27 <= x <= 36 and z >= 21:
                            code = "Q"
                        elif t == "minecraft:water" or t == "minecraft:stone_bricks" and 28 <= x <= 33 and 12 <= z <= 15:
                            code = "M"
                        elif "cable" in t or "wired_modem" in t or "disk_drive" in t:
                            code = "n" if (x, 1, z) in new or (x, 0, z) in new else "c"
                        elif "iron_bars" in t:
                            code = "b"
                        elif "cut_copper" in t and z == 3:
                            code = "r"
                        elif t.startswith("(") or "lantern" in t or "chain" in t:
                            continue
                        else:
                            code = "w" if t in [n2 for n2 in low] else code
                        if code != "g":
                            break
                if code == "g" and floor:
                    if "striped" in floor:
                        code = "L"
                    elif "cut_copper" in floor and z == 3:
                        code = "r"
                    elif "deepslate_bricks" in floor or "deepslate_tiles" in floor:
                        code = "p"
                    elif floor.startswith("("):
                        code = "g"
                    else:
                        code = "f"
                if code == "g" and z == 3 and x in list(RACK2_X):
                    code = "r"
                if code in ("f", "g", "L", "p") and allnew and CABLE in allnew:
                    code = "n" if code != "L" else "N"           # new cable, under the floor or overhead
            row += code
            trow.append(", ".join(f"y{y} {short(n)}" for y, n in stack if n and not n.startswith("(")))
        rows.append(row)
        tips.append(trow)
    return {"x0": X0, "z0": Z0, "rows": rows, "tips": tips}


ZONES = [  # (label, x0, z0, x1, z1, caption)
    ("Smelting hall", 1, 4, 8, 29, "crafter1's 12 furnaces on the hall's cable; the AE2 corner in its south-east."),
    ("AE2 corner (later)", 5, 18, 8, 28, "ME controller, drives, ME Bridge on the desk link; a storage bus through 9 5 15."),
    ("Storage room", 10, 4, 17, 29, "Sortnado's store: two controllers, 803 slots + a 4th barrel row (stage 3); the desk at the south end."),
    ("Launch bay", 19, 5, 26, 29, "The way in from the big door; rack 1's homes face the lane at its north end."),
    ("Foundry: Mekanism", 28, 4, 43, 29, "The piped line (x 35-37), pool and gas plants, stage-0 plinth, operator lane."),
    ("Power corner", 29, 5, 33, 7, "Generators and a cube on the NW plinth, cabled into the line."),
    ("Quartz line", 28, 21, 35, 27, "Sand to soul sand to quartz: reconstructor and fan wash."),
    ("Workshop bench", 36, 23, 38, 27, "Machine trials."),
    ("Control tower", 45, 20, 55, 30, "Map wall and touch panel on the top floor; CommandBlock moves in."),
    ("Old hut (Kyle's)", -20, 0, -10, 14, "Old base: storage drained over the cable, then dismantled; lava cauldrons stay."),
    ("Evaporation tower", 46, 5, 49, 8, "Mekanism stage 4: brine piped in at y 9."),
    ("Lava rows", -11, 19, -4, 31, "Dripstone lava for fuel: row 1 built, row 2 planned."),
]


def page_routes():
    R = [
        ("in from the west, front track, into a home", "#e8590c", False, [(WEST_IN[0], WEST_IN[2]), (0, FRONT), (22, FRONT), (22, 3)]),
        ("in from the east, back track, round into a home", "#1c7ed6", False,
         [(EAST_IN[0], EAST_IN[2]), (44, BACK), (24, BACK), (24, FRONT), (24, 3)]),
        ("out by the east gate", "#495057", False, [(26, FRONT), (44, FRONT), (EAST_OUT[0], EAST_OUT[2])]),
    ]
    return [{"name": n, "color": c, "dash": d, "pts": p} for n, c, d, p in R]


PAGE = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Factory retrofit: the base moves in</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Big+Shoulders+Display:wght@600;800&family=IBM+Plex+Sans:wght@400;500;600&family=IBM+Plex+Mono:wght@400;500&display=swap" rel="stylesheet">
<style>
%%CSS%%
.plan { position: relative; background: var(--panel); border: 1px solid var(--line); border-radius: 10px; overflow: auto; }
.plan canvas { display: block; }
.tip { position: absolute; pointer-events: none; font: 12px/1.4 var(--mono); background: var(--panel); color: var(--ink);
  border: 1px solid var(--line); border-radius: 6px; padding: 6px 8px; max-width: 340px; display: none; box-shadow: 0 2px 8px rgba(0,0,0,.15); }
.toggles { display: flex; flex-wrap: wrap; gap: 8px; }
.key { list-style: none; display: grid; grid-template-columns: repeat(auto-fill, minmax(230px, 1fr)); gap: 6px 16px; padding: 0; margin: 0; font-size: 14px; }
.key li { display: flex; align-items: center; gap: 8px; }
.key i { width: 16px; height: 16px; border-radius: 3px; display: inline-block; border: 1px solid var(--line); flex: none; }
.key .ln { width: 26px; height: 0; border-top: 3px solid; border-radius: 0; border-left: 0; border-right: 0; border-bottom: 0; }
.key .ln.dash { border-top-style: dashed; }
.cap { color: var(--muted); font-size: 14px; }
code { font: 13px var(--mono); }
</style>
</head>
<body>
<main>
<header>
  <h1>Factory retrofit</h1>
  <p class="lede">Where everything ends up once the base moves into the factory. The drones come and go by the drone lane along the back wall and dock in racks facing the lane, where their loads come in over the cable (loading bays): no drone carries anything inside the base. The foundry's machines are worked over the cable too. Hover over any block for what is there; switch the drone routes on and off.</p>
  <div class="facts">
    <span class="chip">Lane: 2 tracks × 45, gates at both ends</span>
    <span class="chip">Loads over the cable: loading bays in the racks</span>
    <span class="chip">Racks: 2 × 16 homes</span>
    <span class="chip">%%CELLS%% retrofit cells, checked against every plan</span>
    <span class="chip">Corner -4448, 71, 1518 · north up</span>
  </div>
</header>

<section aria-label="Top-down plan">
  <div class="toggles">
    <button id="t-routes" aria-pressed="true">Drone routes</button>
    <button id="t-zones" aria-pressed="true">Room labels</button>
    <button id="t-outside" aria-pressed="true">Outside (yard, hut, lava)</button>
  </div>
  <div class="plan" id="plan"><canvas id="cv"></canvas><div class="tip" id="tip"></div></div>
  <p class="cap">Ground floor, seen from above (y 0-5 flattened: the highest thing at walking height wins). One square = one block; x runs east (right), z south (down). The drone lane is the yellow strip along the top.</p>
  <ul class="key" id="key"></ul>
</section>

<section aria-labelledby="lane-h">
  <h2 id="lane-h">The drone lane</h2>
  <div class="plan" id="plan2"><canvas id="cv2"></canvas><div class="tip" id="tip2"></div></div>
  <p class="cap">The lane close up (x -5..47, z -1..5). Drones fly it at y 2; ↕ marks the miners' shaft holes in the lane floor. The routes are drawn side by side; dashed legs are at y 3 or one-off moves.</p>
  <div class="rooms">
    <div class="room"><h3>Lane and gates <span class="size">45 × 2, y 1-3</span></h3>
      <p>Built: the hazard-striped floor, the screen of bars, portholes through the three partitions, a gate in each end wall with its IN/OUT lights. Drones fly it at y 2. The <b>back track</b> (z 1) runs west, the <b>front track</b> (z 2) east, so nobody meets head on.</p>
      <p>In from the west by the west gate on the front track; in from the east by the east gate on the back track; out by the east gate on the front track. The hill's shoulder outside the west gate is dug back (stage 1).</p></div>
    <div class="room"><h3>crafter1's bench <span class="size">x 4-8, back track</span></h3>
      <p>crafter1 (6 2 1) on the hall's cable with its 12 furnaces, its drop chest 5 2 1 and its pad 7 2 1 (new turtles leave from it; the drive is under it). No crafter2, and no pit stop for the helpers: their loads come into their rack homes over the cable.</p>
      <p>The miners keep the service row over crafter1 (y 3) and their shafts at x 4 and x 8 until they have bays of their own in rack 3.</p></div>
    <div class="room"><h3>Racks <span class="size">2 × 16 homes</span></h3>
      <p><b>Rack 1</b> (built, launch bay x 19-26): the helpers' 16 homes, low (y 1) and high (y 3), off the front track. The middle shelf is 8 wired modems: each home is a loading bay (docs/rack-build.html).</p>
      <p>One rack for every drone: Kyle has made rack 1 eight homes across and four rows high (32 homes: the helpers, the chunk loaders, the miners and mapper1). No racks 2 and 3.</p></div>
  </div>
</section>

<section aria-labelledby="rooms-h">
  <h2 id="rooms-h">The rooms</h2>
  <div class="rooms" id="rooms"></div>
</section>

<section aria-labelledby="stages-h">
  <h2 id="stages-h">Order of work</h2>
  <ol class="phases">
    <li><div class="ph-head"><span class="ph-num">1</span><h3>crafter1's bench, the bays</h3></div><p>Fit plan <code>pitstop</code> (the old bay pit stop out, crafter1's bench in, cable under the floor to the hall's cable); lab <code>apron</code> digs the west gate clear. Fit <code>desklink</code> joins the hall to the store. Kyle builds rack 1's loading bays (docs/rack-build.html).</p></li>
    <li><div class="ph-head"><span class="ph-num">2</span><h3>The bridge</h3></div><p>The old base's network joined in under the west gate, so Sortnado can drain it.</p></li>
    <li><div class="ph-head"><span class="ph-num">3</span><h3>A 4th barrel row</h3></div><p>+20 bulk, +72 medium slots in the storage room.</p></li>
    <li><div class="ph-head"><span class="ph-num">4</span><h3>Drain</h3></div><p>The old chests emptied into the store over the cable.</p></li>
    <li><div class="ph-head"><span class="ph-num">5</span><h3>The move</h3></div><p>Kyle carries crafter1 to its bench; every drone is told the new base and its rack home.</p></li>
    <li><div class="ph-head"><span class="ph-num">6</span><h3>Old base out, rack 2</h3></div><p>Empty chests out, the bridge out.</p></li>
    <li><div class="ph-head"><span class="ph-num">7-10</span><h3>The rest</h3></div><p>The foundry hall rebuilt (docs/foundry-v2.md), the Mekanism expansion, the screens, AE2.</p></li>
  </ol>
</section>
</main>
<script>
const D = %%DATA%%;
const CAT = %%CAT%%;
const ZONES = %%ZONES%%;
const ROUTES = %%ROUTES%%;
const tip = document.getElementById("tip"), tip2 = document.getElementById("tip2");
const on = { routes: true, zones: true, outside: true };
const W = D.rows[0].length, H = D.rows.length;
const VIEWS = [
  { cv: document.getElementById("cv"), box: document.getElementById("plan"), tip, x0: D.x0, x1: D.x0 + W - 1, z0: D.z0, z1: D.z0 + H - 1, min: 9, max: 16, labels: true },
  { cv: document.getElementById("cv2"), box: document.getElementById("plan2"), tip: tip2, x0: -5, x1: 47, z0: -1, z1: 5, min: 14, max: 26, labels: false, close: true },
];
function dark() { return document.documentElement.dataset.theme === "dark" ||
  (document.documentElement.dataset.theme !== "light" && matchMedia("(prefers-color-scheme: dark)").matches); }
function colour(code) { const c = CAT.find(k => k[0] === code); return c ? (dark() ? c[3] : c[2]) : "transparent"; }
function css(v) { return getComputedStyle(document.documentElement).getPropertyValue(v).trim(); }
function codeAt(x, z) { const r = D.rows[z - D.z0]; return r ? r[x - D.x0] : undefined; }
function draw(v) {
  const w = v.x1 - v.x0 + 1, h = v.z1 - v.z0 + 1;
  const S = v.S = Math.max(v.min, Math.min(v.max, Math.floor((v.box.clientWidth - 2) / w)));
  const px = x => (x - v.x0) * S, pz = z => (z - v.z0) * S;
  const cv = v.cv, ctx = cv.getContext("2d"), r = devicePixelRatio || 1;
  cv.width = w * S * r; cv.height = h * S * r; cv.style.width = w * S + "px"; cv.style.height = h * S + "px";
  ctx.setTransform(r, 0, 0, r, 0, 0);
  ctx.fillStyle = css("--panel"); ctx.fillRect(0, 0, w * S, h * S);
  for (let z = v.z0; z <= v.z1; z++) for (let x = v.x0; x <= v.x1; x++) {
    const code = codeAt(x, z), i = x - v.x0, j = z - v.z0;
    if (!code || code === "g") continue;
    if (!on.outside && !v.close && (x < 0 || x > 44) && !(x >= 45 && x <= 55 && z >= 20)) continue;
    if ("cnN".includes(code)) {
      ctx.fillStyle = colour(code === "N" ? "L" : "f"); ctx.fillRect(i * S, j * S, S, S);
      ctx.fillStyle = colour(code); const k = Math.max(3, Math.round(S / 3));
      ctx.fillRect(i * S + (S - k) / 2, j * S + (S - k) / 2, k, k);
      for (const [di, dj] of [[1, 0], [0, 1]]) {
        const n = codeAt(x + di, z + dj);
        if (n && "cnNdTK".includes(n)) {
          if (di) ctx.fillRect(i * S + S / 2, j * S + (S - k) / 2, S, k); else ctx.fillRect(i * S + (S - k) / 2, j * S + S / 2, k, S);
        }
      }
      continue;
    }
    ctx.fillStyle = colour(code); ctx.fillRect(i * S, j * S, S, S);
    if (code === "L") {
      ctx.strokeStyle = dark() ? "#222" : "#2a2a2a"; ctx.lineWidth = 1.2; ctx.beginPath();
      ctx.moveTo(i * S, j * S + S); ctx.lineTo(i * S + S, j * S); ctx.stroke();
    }
    if ("TKPhx".includes(code) && S >= 12) {
      ctx.fillStyle = "#fff"; ctx.font = `600 ${Math.round(S * 0.62)}px IBM Plex Mono, monospace`; ctx.textAlign = "center"; ctx.textBaseline = "middle";
      ctx.fillText({ T: "C", K: "K", P: "P", h: "c", x: v.close ? "↕" : "" }[code], i * S + S / 2, j * S + S / 2 + 1);
    }
  }
  if (v.close) {                                  // the close-up: names on the stops and racks
    ctx.font = `500 12px IBM Plex Sans, sans-serif`; ctx.fillStyle = css("--ink"); ctx.textAlign = "left"; ctx.textBaseline = "top";
    const notes = [[3, 4, "crafter1's bench (y 2)"], [19, 4, "Rack 1: every drone (8 x 4)"],
      [-5, -1, "west gate"], [41, -1, "east gate"], [9, -1, "porthole"], [18, -1, "porthole"], [27, -1, "porthole"]];
    for (const [x, z, t] of notes) ctx.fillText(t, px(x) + 2, pz(z) + 2);
  }
  if (on.zones && v.labels) {
    ctx.font = `600 12px IBM Plex Sans, sans-serif`; ctx.textAlign = "left"; ctx.textBaseline = "top";
    for (const z of ZONES) {
      if (!on.outside && (z[1] < 0 || z[1] > 44) && z[0] !== "Control tower") continue;
      ctx.strokeStyle = css("--copper"); ctx.setLineDash([4, 3]); ctx.lineWidth = 1.5;
      ctx.strokeRect(px(z[1]) + 1, pz(z[2]) + 1, (z[3] - z[1] + 1) * S - 2, (z[4] - z[2] + 1) * S - 2);
      ctx.setLineDash([]);
      const t = z[0], tw = ctx.measureText(t).width + 8;
      ctx.fillStyle = css("--panel"); ctx.globalAlpha = 0.88; ctx.fillRect(px(z[1]) + 3, pz(z[2]) + 3, tw, 17); ctx.globalAlpha = 1;
      ctx.fillStyle = css("--ink"); ctx.fillText(t, px(z[1]) + 7, pz(z[2]) + 5);
    }
  }
  if (on.routes) ROUTES.forEach((rt, n) => {
    const off = v.close ? (n - (ROUTES.length - 1) / 2) * Math.max(2, S / 9) : 0;
    ctx.strokeStyle = rt.color; ctx.fillStyle = rt.color; ctx.lineWidth = v.close ? 3 : 2.5; ctx.setLineDash(rt.dash ? [6, 4] : []);
    const P = rt.pts.map(p => [px(p[0]) + S / 2 + off, pz(p[1]) + S / 2 + off]);
    ctx.beginPath(); P.forEach((p, k) => k ? ctx.lineTo(p[0], p[1]) : ctx.moveTo(p[0], p[1])); ctx.stroke(); ctx.setLineDash([]);
    for (let k = 1; k < P.length; k++) {
      const [ax, az] = P[k - 1], [bx, bz] = P[k];
      if (Math.hypot(bx - ax, bz - az) < 8) continue;
      const ang = Math.atan2(bz - az, bx - ax), mx = (ax + bx) / 2, mz = (az + bz) / 2, a = v.close ? 7 : 6;
      ctx.beginPath(); ctx.moveTo(mx + a * Math.cos(ang), mz + a * Math.sin(ang));
      ctx.lineTo(mx - a * Math.cos(ang) + a * 0.8 * Math.sin(ang), mz - a * Math.sin(ang) - a * 0.8 * Math.cos(ang));
      ctx.lineTo(mx - a * Math.cos(ang) - a * 0.8 * Math.sin(ang), mz - a * Math.sin(ang) + a * 0.8 * Math.cos(ang)); ctx.fill();
    }
  });
}
function drawAll() { VIEWS.forEach(draw); }
function key() {
  const used = new Set(D.rows.join(""));
  const ul = document.getElementById("key"); ul.innerHTML = "";
  for (const c of CAT) if (used.has(c[0])) {
    const li = document.createElement("li"); li.innerHTML = `<i style="background:${dark() ? c[3] : c[2]}"></i>${c[1]}`; ul.appendChild(li);
  }
  for (const r of ROUTES) {
    const li = document.createElement("li"); li.innerHTML = `<i class="ln${r.dash ? " dash" : ""}" style="border-top-color:${r.color}"></i>${r.name}`; ul.appendChild(li);
  }
}
function rooms() {
  document.getElementById("rooms").innerHTML = ZONES.map(z =>
    `<div class="room"><h3>${z[0]} <span class="size">x ${z[1]}..${z[3]}, z ${z[2]}..${z[4]}</span></h3><p>${z[5]}</p></div>`).join("");
}
for (const v of VIEWS) {
  v.cv.addEventListener("mousemove", e => {
    const b = v.cv.getBoundingClientRect(), x = v.x0 + Math.floor((e.clientX - b.left) / v.S), z = v.z0 + Math.floor((e.clientY - b.top) / v.S);
    const code = codeAt(x, z);
    if (code === undefined) { v.tip.style.display = "none"; return; }
    const t = D.tips[z - D.z0][x - D.x0], cat = CAT.find(k => k[0] === code);
    v.tip.innerHTML = `<b>${x} · ${z}</b> (world ${x - 4448}, ${z + 1518})<br>${cat && code !== "g" ? cat[1] : "open"}${t ? "<br>" + t : ""}`;
    v.tip.style.display = "block";
    const box = v.box.getBoundingClientRect();
    v.tip.style.left = Math.max(0, Math.min(e.clientX - box.left + 14, box.width - 350)) + "px"; v.tip.style.top = (e.clientY - box.top + 14) + "px";
  });
  v.cv.addEventListener("mouseleave", () => v.tip.style.display = "none");
}
for (const k of ["routes", "zones", "outside"]) {
  const b = document.getElementById("t-" + k);
  b.addEventListener("click", () => { on[k] = !on[k]; b.setAttribute("aria-pressed", on[k]); drawAll(); });
}
addEventListener("resize", drawAll);
matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => { drawAll(); key(); });
document.fonts && document.fonts.ready.then(drawAll);
drawAll(); key(); rooms();
</script>
</body>
</html>
"""


def write_page():
    src = open(os.path.join(ROOT, "docs", "factory-plan.html"), encoding="utf-8").read()
    css = src[src.index("<style>") + 7:src.index("</style>")]
    css = css[:css.index("/* the model */")] + css[css.index("/* rooms */"):]
    data = page_grid()
    n = len(_all())
    html = (PAGE.replace("%%CSS%%", css.strip()).replace("%%DATA%%", json.dumps(data, separators=(",", ":")))
            .replace("%%CAT%%", json.dumps(CAT)).replace("%%ZONES%%", json.dumps(ZONES))
            .replace("%%ROUTES%%", json.dumps(page_routes())).replace("%%CELLS%%", str(n)))
    out = os.path.join(ROOT, "docs", "factory-retrofit.html")
    with open(out, "w", encoding="utf-8") as f:
        f.write(html)
    return out, len(html)


if __name__ == "__main__":
    a = sys.argv[1:]
    cmd = a[0] if a else "check"
    if cmd == "check":
        sys.exit(0 if check() else 1)
    elif cmd == "map":
        print({"site": map_site, "lane": map_lane, "net": map_net, "foundry": map_foundry,
               "store": map_store}[a[1] if len(a) > 1 else "site"]())
    elif cmd == "items":
        for k, v in items(int(a[1])).items():
            print(f"{v:>5}  {k}")
    elif cmd == "ops":
        print(ops(a[1]))
    elif cmd == "fit":
        print(fit(a[1]))
    elif cmd == "page":
        print("wrote %s (%d bytes)" % write_page())
    elif cmd == "json":
        print(json.dumps(layout_json(), separators=(",", ":")))
    else:
        print(__doc__)
