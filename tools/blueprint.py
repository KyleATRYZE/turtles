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
    {"name": "Tree farm", "box": [28, 1, 1, 43, 13, 29], "floor": "ground, double height"},
    {"name": "Builder workshop", "box": [1, 9, 1, 26, 13, 29], "floor": "upper"},
    {"name": "Control tower", "box": [46, 1, 21, 54, 22, 29], "floor": "three floors"},
]


def roof_h(x):
    """Height of the sawtooth roof above y 14 at this x (4 down to 0)."""
    b = max(b for b in BAYS if b <= x)
    return 4 - min(4, (x - b) // 2)


# ---------------------------------------------------------------- floor
fill(0, 0, 0, HX, 0, HZ, "minecraft:polished_deepslate")
fill(28, 0, 1, 43, 0, 29, "minecraft:dirt")                 # tree farm soil
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
# open stairwell (ladders) in the storage room
clear(16, UPPER, 2, 17, UPPER, 2)
fill(17, 1, 1, 17, UPPER + 1, 1, "minecraft:ladder[facing=south]")

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
for z in range(3, 28, 2):
    put(2, 1, z, "minecraft:furnace[facing=east]")
    put(1, 1, z, "computercraft:wired_modem_full")
fill(1, 1, 2, 1, 1, 28, "computercraft:cable")
for z in range(3, 28, 2):
    put(1, 1, z, "computercraft:wired_modem_full")
# storage room: chest walls, three high, both sides, cable behind the floor line
for z in range(2, 28):
    for y in (1, 2, 3):
        put(10, y, z, "minecraft:chest[facing=east]")
        put(16, y, z, "minecraft:chest[facing=west]")
put(13, 1, 28, "minecraft:chest[facing=north]")                # the drop-in / take-out chest
put(14, 1, 28, "computercraft:computer_advanced")
put(14, 2, 28, "computercraft:monitor_advanced")
# launch bay: the factory, pad, drop-off chest and both shafts
put(22, 1, 15, "computercraft:wired_modem_full")
put(22, 2, 15, "computercraft:turtle_advanced")                # ForgeClooney
put(21, 1, 15, "computercraft:disk_drive")                     # under the launch pad
put(23, 1, 15, "minecraft:furnace[facing=south]")
put(23, 2, 15, "minecraft:chest[facing=west]")                 # drop-off
for y in range(0, 3):
    B.pop((20, y, 15), None)                                   # out-shaft
    B.pop((24, y, 15), None)                                   # in-shaft
fill(19, 1, 15, 19, 1, 15, "computercraft:cable")
# tree farm: 4 rows of birch saplings, a lumberjack turtle's track between
for x in (30, 34, 38, 42):
    for z in range(4, 28, 4):
        put(x, 1, z, "minecraft:birch_sapling")
put(28, 1, 15, "computercraft:turtle_normal")                  # the lumberjack's home
# control tower: the monitor wall on the north wall of the top floor
for x in range(TX1 + 1, TX2):
    for y in range(17, 21):
        put(x, y, TZ1 + 1, "computercraft:monitor_advanced")
put(TX1 + 5, 17, TZ2 - 2, "computercraft:computer_advanced")   # GroundControl
put(TX1 + 5, 18, TZ2 - 2, "advancedperipherals:chat_box")
put(TX1 + 4, 17, TZ2 - 2, "advancedperipherals:player_detector")
# lanterns
for x in range(4, 44, 9):
    for z in (8, 22):
        y = 13 if x < 27 else 13
        put(x, 6 if x < 27 else 12, z, "minecraft:lantern[hanging=true]")
for (x, z) in ((48, 24), (52, 26)):
    put(x, 22, z, "minecraft:lantern[hanging=true]")
# copper pipes running along the front of the smelting hall
for x in range(1, 9):
    put(x, 7, HZ + 1, "minecraft:lightning_rod[facing=east]")

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
    "materials": dict(materials.most_common()),
}
os.makedirs(os.path.join(os.path.dirname(__file__), "..", "blueprints"), exist_ok=True)
path = os.path.join(os.path.dirname(__file__), "..", "blueprints", "factory.json")
with open(path, "w") as f:
    json.dump(out, f, separators=(",", ":"))
print(f"{len(blocks)} blocks, size {out['size']}")
for k, v in materials.most_common():
    print(f"{v:6d}  {k}")
