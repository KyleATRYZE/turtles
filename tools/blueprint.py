#!/usr/bin/env python3
"""Generate the factory building, block by block.

Coordinates are local to the building: x runs east, z runs south, y up.
y = 0 is the floor (it replaces the top ground block), so the ground floor
is y = 1 .. 7. World placement is decided when the site is chosen.

Writes blueprints/factory.json:
  palette   block names (with [properties] where facing matters)
  blocks    [x, y, z, palette index]
  rooms     named boxes, for the plan and the viewer
  materials how many of each block
"""
import json, os, random
from collections import Counter

random.seed(7)   # the cracked bricks land in the same places every time
B = {}           # (x, y, z) -> block name


def put(x, y, z, name):
    B[(x, y, z)] = name


def fill(x1, y1, z1, x2, y2, z2, name):
    for x in range(min(x1, x2), max(x1, x2) + 1):
        for y in range(min(y1, y2), max(y1, y2) + 1):
            for z in range(min(z1, z2), max(z1, z2) + 1):
                put(x, y, z, name)


def clear(x1, y1, z1, x2, y2, z2):
    for x in range(min(x1, x2), max(x1, x2) + 1):
        for y in range(min(y1, y2), max(y1, y2) + 1):
            for z in range(min(z1, z2), max(z1, z2) + 1):
                B.pop((x, y, z), None)


def brick():
    r = random.random()
    return "minecraft:cracked_stone_bricks" if r < 0.09 else "minecraft:stone_bricks"


# ---------------------------------------------------------------- sizes
HX, HZ = 44, 30          # main hall: x 0..44, z 0..30 (45 x 31)
GROUND_TOP, UPPER = 7, 8  # ground floor y 1..7, upper floor slab at y 8
WALL_TOP = 13            # upper floor y 9..13, roof from y 14
BAYS = [0, 9, 18, 27, 36]  # sawtooth roof bays, 9 wide
PILLARS_X = [0, 9, 18, 27, 36, 44]
PILLARS_Z = [0, 10, 20, 30]
TX1, TX2, TZ1, TZ2 = 45, 55, 20, 30   # control tower 11 x 11
TOWER_TOP = 23

ROOMS = [
    {"name": "Smelting hall", "box": [1, 1, 1, 8, 7, 29], "floor": "ground"},
    {"name": "Storage room", "box": [10, 1, 1, 17, 7, 29], "floor": "ground"},
    {"name": "Launch bay", "box": [19, 1, 1, 26, 7, 29], "floor": "ground"},
    {"name": "Mekanism foundry", "box": [28, 1, 1, 43, 13, 29], "floor": "ground, double height"},
    {"name": "Builder workshop", "box": [1, 9, 1, 26, 13, 29], "floor": "upper"},
    {"name": "Control tower", "box": [46, 1, 21, 54, 22, 29], "floor": "three floors"},
    {"name": "Drone lane", "box": [0, 1, 1, 44, 4, 4], "floor": "ground, along the back wall"},
]


def roof_h(x):
    """Height of the sawtooth roof above y 14 at this x (4 down to 0)."""
    b = max(b for b in BAYS if b <= x)
    return 4 - min(4, (x - b) // 2)


# ---------------------------------------------------------------- floor
fill(0, 0, 0, HX, 0, HZ, "minecraft:polished_deepslate")
# the foundry (it was going to be a tree farm): a plain floor, a brick plinth
# along the east wall for the machine line and one in the corner for power,
# and a tiled lane in front of the machines for the turtle that runs them
# (plinths in deepslate bricks: copper would mean smelting 500 ingots for a floor)
fill(41, 0, 6, 42, 0, 27, "minecraft:deepslate_bricks")
fill(39, 0, 6, 40, 0, 27, "minecraft:deepslate_tiles")
fill(29, 0, 5, 33, 0, 7, "minecraft:deepslate_bricks")
fill(TX1, 0, TZ1, TX2, 0, TZ2, "minecraft:polished_deepslate")

# ---------------------------------------------------------------- hall walls
def wall_column(x, z, top):
    for y in range(1, top + 1):
        if y <= 2:
            put(x, y, z, "minecraft:deepslate_tiles")
        elif y == UPPER:
            put(x, y, z, "minecraft:polished_deepslate")
        else:
            put(x, y, z, brick())

for x in range(0, HX + 1):
    for z in (0, HZ):
        wall_column(x, z, WALL_TOP)
for z in range(0, HZ + 1):
    for x in (0, HX):
        wall_column(x, z, WALL_TOP)

# gable infill under the sawtooth along the front and back walls
for x in range(0, HX + 1):
    for z in (0, HZ):
        for y in range(14, 14 + roof_h(x)):
            put(x, y, z, brick())
# the west end wall rises to the first bay's high side
for z in range(0, HZ + 1):
    for y in range(14, 18):
        put(0, y, z, brick())

# pillars
for x in PILLARS_X:
    for z in (0, HZ):
        fill(x, 1, z, x, WALL_TOP + roof_h(x), z, "minecraft:polished_deepslate")
for z in PILLARS_Z:
    for x in (0, HX):
        fill(x, 1, z, x, WALL_TOP + (4 if x == 0 else 0), z, "minecraft:polished_deepslate")

# windows: front and back walls, between the pillars
SEGMENTS = [(1, 8), (10, 17), (19, 26), (28, 35), (37, 43)]
for (s, e) in SEGMENTS:
    w1, w2 = s + 2, e - 2
    for z in (0, HZ):
        if s == 19 and z == HZ:
            continue                      # the launch bay door goes here
        if s >= 28:                       # tree farm: tall windows both floors
            fill(w1, 3, z, w2, 6, z, "minecraft:glass_pane")
            fill(w1, 9, z, w2, 12, z, "minecraft:glass_pane")
        else:
            fill(w1, 3, z, w2, 5, z, "minecraft:glass_pane")
            fill(w1, 10, z, w2, 12, z, "minecraft:glass_pane")
for (s, e) in [(2, 8), (12, 18), (22, 28)]:
    for x in (0, HX):
        if x == HX and s == 22:
            continue                      # the tower joins here
        fill(x, 3, s + 1, x, 5, e - 1, "minecraft:glass_pane")
        fill(x, 10, s + 1, x, 12, e - 1, "minecraft:glass_pane")

# the launch bay door: an arch 4 wide, 5 tall, in the front wall
clear(21, 1, HZ, 24, 4, HZ)
clear(22, 5, HZ, 23, 5, HZ)
put(21, 5, HZ, "minecraft:polished_deepslate")
put(24, 5, HZ, "minecraft:polished_deepslate")
fill(21, 6, HZ, 24, 6, HZ, "minecraft:polished_deepslate")

# a doorway into the tower
clear(HX, 1, 24, HX, 3, 26)

# ---------------------------------------------------------------- inside
# partition walls with doorways
for x in (9, 18, 27):
    top = WALL_TOP if x != 27 else WALL_TOP
    for z in range(1, HZ):
        for y in range(1, top + 1):
            if y == UPPER:
                put(x, y, z, "minecraft:polished_deepslate")
            else:
                put(x, y, z, "minecraft:stone_bricks")
    clear(x, 1, 14, x, 3, 16)            # ground floor doorway
    if x != 27:
        clear(x, 9, 14, x, 11, 16)       # upper floor doorway
    else:
        # the upper floor looks out over the tree farm through a glass wall
        fill(x, 9, 2, x, 12, 28, "minecraft:glass_pane")

# the upper floor over smelting, storage and the launch bay
fill(1, UPPER, 1, 26, UPPER, 29, "minecraft:polished_deepslate")
# ladder up to the workshop, in the storage room's south-east corner
fill(17, 1, HZ - 1, 17, UPPER + 1, HZ - 1, "minecraft:ladder[facing=north]")

# ---------------------------------------------------------------- the drone lane
# Drones never cross the rooms: a two-track lane runs the full length of the
# back wall behind a screen. The back track (z 1) runs west, the front track
# (z 2) runs east, so nobody meets head-on. Gates in both end walls, each with
# an IN and an OUT light; portholes through the partitions; hazard stripes on
# the floor. The miners' pit stop sits on the back track in the launch bay.
LANE = (1, 2)
HAZARD = "chipped:striped_yellow_concrete"          # yellow and black stripes (Kyle's pick)
for x in range(0, HX + 1):
    for z in LANE:
        put(x, 0, z, HAZARD)
for x in (0, HX):                                   # the gates, framed
    clear(x, 1, 1, x, 3, 2)
    fill(x, 1, 3, x, 4, 3, "minecraft:polished_deepslate")
for x in (9, 18, 27):                               # portholes, with a lintel
    clear(x, 1, 1, x, 3, 2)
    fill(x, 4, 1, x, 4, 2, "minecraft:polished_deepslate")
# the screen: iron bars between polished deepslate posts (the launch bay has
# the drone rack instead, below)
POSTS = {1, 5, 8, 10, 14, 17, 28, 30, 34, 38, 42, 43}
HATCH = 32                                          # the lumberjack's way into the farm
for x in range(1, HX):
    if x in (9, 18, 27) or 19 <= x <= 26:
        continue
    for y in range(1, 5):
        if x == HATCH and y <= 2:
            continue
        put(x, y, 3, "minecraft:polished_deepslate" if x in POSTS else "minecraft:iron_bars")
# gate lights: a monitor over each track, facing out. A track leaving the
# building shows OUT, one coming in shows IN; they flash while a drone passes.
LIGHTS = []
for x, face, lights in ((0, "west", {1: "OUT", 2: "IN"}), (HX, "east", {1: "IN", 2: "OUT"})):
    for z, word in lights.items():
        put(x, 4, z, f"computercraft:monitor_advanced[facing={face}]")
        LIGHTS.append({"pos": [x, 4, z], "face": face, "label": word,
                       "color": "#3fbf6a" if word == "IN" else "#e5484d"})

# ---------------------------------------------------------------- roof
for x in range(0, HX + 1):
    h = roof_h(x)
    y = 14 + h
    nxt = roof_h(x + 1) if x < HX else h
    step = nxt < h
    for z in range(0, HZ + 1):
        put(x, y, z, "minecraft:deepslate_tile_stairs[facing=west]" if step else "minecraft:deepslate_tiles")
# the glazed vertical faces of the sawtooth (north light from the west side)
for b in BAYS[1:]:
    for z in range(1, HZ):
        for y in range(14, 18):
            put(b, y, z, "minecraft:glass_pane")
# roof lights over the tree farm as well
for x in range(29, 44):
    for z in range(2, HZ - 1, 3):
        y = 14 + roof_h(x)
        if B.get((x, y, z), "").startswith("minecraft:deepslate_tiles"):
            put(x, y, z, "minecraft:glass")       # full glass: it is part of the roof

# ---------------------------------------------------------------- chimneys
for (cz1, cz2) in ((4, 6), (13, 15)):
    for y in range(UPPER + 1, 27):
        for x in range(3, 6):
            for z in range(cz1, cz2 + 1):
                if x in (3, 5) or z in (cz1, cz2):
                    put(x, y, z, "minecraft:deepslate_bricks")
                else:
                    B.pop((x, y, z), None)
    for x in range(2, 7):
        for z in range(cz1 - 1, cz2 + 2):
            if x in (2, 6) or z in (cz1 - 1, cz2 + 1):
                put(x, 26, z, "minecraft:cut_copper")
    for x in range(3, 6):
        for z in range(cz1, cz2 + 1):
            if x in (3, 5) or z in (cz1, cz2):
                put(x, 27, z, "minecraft:cut_copper_slab[type=bottom]")

# ---------------------------------------------------------------- control tower
for x in range(TX1, TX2 + 1):
    for z in range(TZ1, TZ2 + 1):
        edge = x in (TX1, TX2) or z in (TZ1, TZ2)
        if not edge:
            continue
        corner = x in (TX1, TX2) and z in (TZ1, TZ2)
        for y in range(1, TOWER_TOP + 2):
            if corner or y == TOWER_TOP + 1:
                put(x, y, z, "minecraft:polished_deepslate")
            elif y <= 2:
                put(x, y, z, "minecraft:deepslate_tiles")
            elif y in (UPPER, 16):
                put(x, y, z, "minecraft:polished_deepslate")
            else:
                put(x, y, z, brick())
for y in (UPPER, 16):
    fill(TX1 + 1, y, TZ1 + 1, TX2 - 1, y, TZ2 - 1, "minecraft:polished_deepslate")
    clear(TX1 + 1, y, TZ1 + 1, TX1 + 1, y, TZ1 + 1)           # ladder hole
fill(TX1 + 1, 1, TZ1 + 1, TX1 + 1, 17, TZ1 + 1, "minecraft:ladder[facing=south]")
# the big control-room window on the south face, and smaller ones
fill(TX1 + 3, 17, TZ2, TX2 - 3, 22, TZ2, "minecraft:glass_pane")
for (y1, y2) in ((3, 5), (10, 13)):
    fill(TX1 + 4, y1, TZ2, TX2 - 4, y2, TZ2, "minecraft:glass_pane")
    fill(TX2, y1, TZ1 + 4, TX2, y2, TZ2 - 4, "minecraft:glass_pane")
fill(TX2, 17, TZ1 + 3, TX2, 22, TZ2 - 3, "minecraft:glass_pane")
# front door
clear(TX1 + 5, 1, TZ2, TX1 + 5, 2, TZ2)
# pyramid roof
for i in range(0, 6):
    y = TOWER_TOP + 2 + i
    x1, x2, z1, z2 = TX1 - 1 + i, TX2 + 1 - i, TZ1 - 1 + i, TZ2 + 1 - i
    for x in range(x1, x2 + 1):
        for z in range(z1, z2 + 1):
            if x in (x1, x2) or z in (z1, z2):
                if x1 == x2:
                    put(x, y, z, "minecraft:deepslate_tiles")
                elif x == x1 and z not in (z1, z2):
                    put(x, y, z, "minecraft:deepslate_tile_stairs[facing=east]")
                elif x == x2 and z not in (z1, z2):
                    put(x, y, z, "minecraft:deepslate_tile_stairs[facing=west]")
                elif z == z1:
                    put(x, y, z, "minecraft:deepslate_tile_stairs[facing=south]")
                else:
                    put(x, y, z, "minecraft:deepslate_tile_stairs[facing=north]")
put(50, TOWER_TOP + 8, 25, "minecraft:lightning_rod")

# ---------------------------------------------------------------- fittings
# smelting hall: a bank of furnaces along the west wall, wired to the network
for z in range(5, 28, 2):
    put(2, 1, z, "minecraft:furnace[facing=east]")
fill(1, 1, 4, 1, 1, 28, "computercraft:cable")
for z in range(5, 28, 2):
    put(1, 1, z, "computercraft:wired_modem_full")
# storage room (docs/storage-plan.html): Sophisticated Storage, all of it
# touching, so one controller makes the whole room a single inventory.
#   west wall  limited barrels I   (one kind each, the bulk: shown on the front)
#   east wall  limited barrels IV  (four kinds each, the middling piles)
#   north wall chests              (the long tail: one-offs, tools, odd drops)
# Each side wall is three high with a row over its doorway to join the two
# halves. No modem behind every chest any more: the only cable is the
# counter the front desk stands on.
STORE_DOOR = range(14, 17)
STORE = {"bulk": [], "mixed": [], "chests": []}
def store(kind, x, y, z, name):
    put(x, y, z, name)
    STORE[kind].append([x, y, z])
for z in range(4, 29):                                         # west wall, down to the desk
    for y in ((4,) if z in STORE_DOOR else (1, 2, 3, 4) if z in (13, 17) else (1, 2, 3)):
        store("bulk", 10, y, z, "sophisticatedstorage:limited_barrel_1[facing=east]")
for z in range(4, 27):                                         # east wall (the ladder is at z 29)
    for y in ((4,) if z in STORE_DOOR else (1, 2, 3, 4) if z in (13, 17) else (1, 2, 3)):
        store("mixed", 17, y, z, "sophisticatedstorage:limited_barrel_4[facing=west]")
for x in range(11, 17):                                        # north wall, in front of the lane's screen
    for y in (1, 2, 3):
        store("chests", x, y, 4, "sophisticatedstorage:chest[facing=south]")
# the front desk, on a counter of wired modems (one under each thing that
# has to be on the network). From the west: the controller (touching the
# west wall), the Inventory Manager (it hands items to the player: the
# controller on one side of it, the Out barrel on the other), the Out
# barrel, Sortnado with an ender modem on its side (to hear CommandBlock),
# and the In barrel. Barrels, not chests: a chest will not open under the
# screen. The 5 x 3 touch screen stands on the desk.
DESK_Z = HZ - 1
for x in range(10, 16):
    put(x, 1, DESK_Z, "computercraft:wired_modem_full")
put(10, 2, DESK_Z, "sophisticatedstorage:controller")
put(11, 2, DESK_Z, "advancedperipherals:inventory_manager")
put(12, 2, DESK_Z, "minecraft:barrel[facing=north]")           # Out
put(13, 2, DESK_Z, "computercraft:computer_advanced[facing=north]")   # Sortnado
put(14, 2, DESK_Z, "computercraft:wireless_modem_advanced[facing=west]")
put(15, 2, DESK_Z, "minecraft:barrel[facing=north]")           # In
fill(11, 3, DESK_Z, 15, 5, DESK_Z, "computercraft:monitor_advanced[facing=north]")   # 5 x 3 touch screen
# launch bay: the pit stop on the back track, against the back wall. Miners
# come up the in-shaft (x 24), drop their load in the chest, get serviced
# over crafter1, pass the pad and drop down the out-shaft (x 20).
put(21, 1, 1, "computercraft:disk_drive")                      # under the launch pad
put(22, 1, 1, "computercraft:wired_modem_full")
put(22, 2, 1, "computercraft:turtle_advanced")                 # crafter1
put(23, 1, 1, "minecraft:furnace[facing=south]")
put(23, 2, 1, "minecraft:chest[facing=south]")                 # drop-off
B.pop((20, 0, 1), None)                                        # out-shaft
B.pop((24, 0, 1), None)                                        # in-shaft
# control tower: the monitor wall on the north wall of the top floor
for x in range(TX1 + 1, TX2):
    for y in range(17, 21):
        put(x, y, TZ1 + 1, "computercraft:monitor_advanced[facing=south]")   # (faces into the room)
put(TX1 + 5, 17, TZ2 - 2, "computercraft:computer_advanced")   # CommandBlock
put(TX1 + 5, 18, TZ2 - 2, "advancedperipherals:chat_box")
put(TX1 + 4, 17, TZ2 - 2, "advancedperipherals:player_detector")
# the drone rack: 16 homes in two rows off the front track in the launch bay.
# A drone with nothing to do slides in and sits on its copper pad. Bars at
# the back so you can see them from the bay, and a name board over each.
DOCKS = []
for x in range(19, 27):
    put(x, 0, 3, "minecraft:cut_copper")                       # lower pad, in the floor
    put(x, 2, 3, "minecraft:cut_copper")                       # upper pad (the upper drone sits on it)
    DOCKS += [(x, 0, 3), (x, 2, 3)]
    fill(x, 1, 4, x, 3, 4, "minecraft:iron_bars")
    put(x, 4, 4, "computercraft:monitor_advanced[facing=south]")
    LIGHTS.append({"pos": [x, 4, 4], "face": "south", "label": "", "color": "#2bb3c8"})
# touch panels (advanced monitors are touch screens): a 3 x 2 panel by
# CommandBlock in the tower, and a 2 x 2 one by the launch bay door
PANELS = {
    "tower": [(TX1 + 1, y, z) for y in (17, 18) for z in (23, 24, 25)],
    "launch bay": [(19, y, z) for y in (2, 3) for z in (26, 27)],
}
for cells in PANELS.values():
    for (x, y, z) in cells:
        put(x, y, z, "computercraft:monitor_advanced[facing=east]")   # (both hang on a west wall)

# ---------------------------------------------------------------- the stations
# Every screen has a station: a plain computer touching the monitor (a
# computer drives a monitor it touches with no cable and nobody to click a
# modem), with an ender modem stuck on it to hear the swarm. Where a wall is
# behind the screen the computer goes into the wall, out of sight. A helper
# sets the computers up on the launch pad's disk drive and carries them here
# (helper.lua, lab verb "bootstrap"); each then works out which screen it is
# from where it stands (screens.lua). "stand" is the side the turtle works
# from (as in fitout.py: 0 above, 2 east, 3 south, 4 west, 5 north): the
# modem only sticks to the computer when the computer is straight beyond it.
STATION = "computercraft:computer_normal"
RADIO = "computercraft:wireless_modem_advanced"
STATIONS = [
    # name          kind     computer        stand  radio           stand  screens it touches
    ("west gate",   "gate",  (0, 5, 1),       2,    (1, 5, 1),       2,   [(0, 4, 1)]),
    ("east gate",   "gate",  (HX, 5, 1),      4,    (HX - 1, 5, 1),  4,   [(HX, 4, 1)]),
    ("rack",        "rack",  (22, 4, 3),      0,    (22, 5, 3),      0,   [(22, 4, 4)]),
    ("bay panel",   "panel", (19, 4, 26),     0,    (19, 5, 26),     0,   [(19, 3, 26)]),
    ("wall",        "wall",  (TX1 + 1, 17, TZ1), 5, (TX1 + 1, 17, TZ1 - 1), 5, [(TX1 + 1, 17, TZ1 + 1)]),
    ("tower panel", "panel", (TX1, 17, 23),   4,    (TX1 - 1, 17, 23), 4, [(TX1 + 1, 17, 23)]),
]
STANDS = {}                                      # "x,y,z" -> the side to work from
for name, kind, comp, cs, radio, rs, touches in STATIONS:
    for t in touches:
        assert "monitor" in B[t] and sum(abs(a - b) for a, b in zip(comp, t)) == 1, name
    assert radio not in B and sum(abs(a - b) for a, b in zip(comp, radio)) == 1, name
    put(*comp, STATION)
    put(*radio, RADIO)
    STANDS["%d,%d,%d" % comp] = cs
    STANDS["%d,%d,%d" % radio] = rs
# a monitor is put up from in front, so it stands upright and faces the
# turtle (put in from above it lies on its back, screen to the ceiling)
FACE_STAND = {"east": 2, "south": 3, "west": 4, "north": 5}
for (x, y, z), name in B.items():
    if name.startswith("computercraft:monitor") and "facing=" in name:
        STANDS["%d,%d,%d" % (x, y, z)] = FACE_STAND[name.split("facing=")[1].rstrip("]")]
# so is anything of the store's whose front matters: a barrel put in from
# above lies face up (a limited barrel's label and count on top, plain wood
# to the room), and a chest opens towards whoever put it there
FRONT_MATTERS = ("sophisticatedstorage:", "minecraft:barrel")
for (x, y, z), name in B.items():
    if name.startswith(FRONT_MATTERS) and "facing=" in name:
        STANDS["%d,%d,%d" % (x, y, z)] = FACE_STAND[name.split("facing=")[1].rstrip("]")]
# copper pipes running along the front of the smelting hall
for x in range(1, 9):
    put(x, 7, HZ + 1, "minecraft:lightning_rod[facing=east]")

# ---------------------------------------------------------------- lanterns
# hung wherever the lighting plan says (tools/lighting.py): every walkable
# spot inside stays lit so nothing spawns; chains under the high ceilings
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lighting import plan_lanterns
LANTERNS = plan_lanterns(dict(B), door_z=HZ - 1)
for (lx, ly, lz), chain in LANTERNS:
    put(lx, ly, lz, "minecraft:lantern[hanging=true]")
    for (cx_, cy_, cz_) in chain:
        put(cx_, cy_, cz_, "minecraft:chain")

# ---------------------------------------------------------------- drone routes
# (for the plan page) everything rides the lane along the back wall
ROAD_IN, ROAD_OUT = 2 - 16, 2 - 20
ROUTES = [
    {"name": "Miners coming home: up the in-shaft to the pit stop", "color": "#e0a030",
     "points": [[62, ROAD_IN, 1.5], [24.5, ROAD_IN, 1.5], [24.5, 3.5, 1.5], [23.5, 3.5, 1.5], [22.5, 3.5, 1.5]]},
    {"name": "Miners going out: down the out-shaft", "color": "#d0603a",
     "points": [[22.5, 3.5, 1.5], [21.5, 3.5, 1.5], [20.5, 3.5, 1.5], [20.5, ROAD_OUT, 1.5], [-16, ROAD_OUT, 1.5]]},
    {"name": "Back track: westbound, in at the east gate, out at the west", "color": "#e5484d",
     "points": [[50, 2.5, 1.5], [44.5, 2.5, 1.5], [26.5, 2.5, 1.5], [25.5, 3.5, 1.5], [19.5, 3.5, 1.5],
                [18.5, 2.5, 1.5], [0.5, 2.5, 1.5], [-6, 2.5, 1.5]]},
    {"name": "Front track: eastbound, in at the west gate, out at the east", "color": "#3fbf6a",
     "points": [[-6, 1.6, 2.5], [0.5, 1.6, 2.5], [44.5, 1.6, 2.5], [50, 1.6, 2.5]]},
    {"name": "Lumberjack: rack to the farm through its hatch", "color": "#7cb342",
     "points": [[26.5, 1.5, 3.5], [26.5, 1.5, 2.5], [32.5, 1.5, 2.5], [32.5, 1.5, 3.5], [32.5, 1.5, 6.5]]},
]

# ---------------------------------------------------------------- write out
palette, index, blocks = [], {}, []
for (x, y, z), name in sorted(B.items(), key=lambda kv: (kv[0][1], kv[0][2], kv[0][0])):
    if name not in index:
        index[name] = len(palette)
        palette.append(name)
    blocks.append([x, y, z, index[name]])

materials = Counter(n.split("[")[0] for n in B.values())
xs = [k[0] for k in B]; ys = [k[1] for k in B]; zs = [k[2] for k in B]
out = {
    "name": "factory",
    "size": {"x": max(xs) - min(xs) + 1, "y": max(ys) + 1, "z": max(zs) - min(zs) + 1},
    "min": {"x": min(xs), "y": min(ys), "z": min(zs)},
    "palette": palette,
    "blocks": blocks,
    "rooms": ROOMS,
    "docks": DOCKS,
    "panels": PANELS,
    "routes": ROUTES,
    "lights": LIGHTS,
    "stations": [{"name": n, "kind": k, "computer": list(c), "radio": list(r), "touches": [list(t) for t in ts]}
                 for n, k, c, cs, r, rs, ts in STATIONS],
    "stands": STANDS,
    "store": STORE,
    "materials": dict(materials.most_common()),
}
os.makedirs(os.path.join(os.path.dirname(__file__), "..", "blueprints"), exist_ok=True)
path = os.path.join(os.path.dirname(__file__), "..", "blueprints", "factory.json")
with open(path, "w") as f:
    json.dump(out, f, separators=(",", ":"))
print(f"{len(blocks)} blocks, size {out['size']}")
for k, v in materials.most_common():
    print(f"{v:6d}  {k}")
