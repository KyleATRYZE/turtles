#!/usr/bin/env python3
"""Factory v2: the redesign concept (for Kyle to review; nothing here is built
by this tool). The whole building from the survey, the hall as built and
planned (tools/ae2plan.py), and the v2 additions. Writes docs/factory-v2.html.
"""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ae2plan as A
ROOT = A.ROOT
t, put, T = A.t, A.put, A.T

t("barrel", "Storage barrel (there now)", "sophisticatedstorage:limited_barrel_1", "build", "#8a5a2b", "#5e3d1c", "bricks")
t("monitor", "Advanced monitor", "computercraft:monitor_advanced", "ae", "#1b1c20", "#57e3c2", "terminal")
t("furn", "Furnace (there now)", "minecraft:furnace", "build", "#6e6e6e", "#3a3a3a", "machine")
t("gate", "Blast gate leaf (Create contraption)", "create:industrial_iron_block", "v2", "#3d4147", "#ffb84a", "frame")
t("gateglass", "Gate window", "create:framed_glass", "v2", "#bfe3ee", "#ffffff", "glass", a=0.3)
t("girder", "Gantry and girders", "create:metal_girder", "v2", "#5a5f66", "#2e3136", "bricks")
t("motor", "Electric motor (FE to rotation, no water wheel)", "createaddition:electric_motor", "v2", "#70727c", "#ffd76b", "machine")
t("guard", "Guard turtle (melee, patrols)", "computercraft:turtle_advanced", "v2", "#d9c24a", "#c0392b", "machine")
t("console", "Console (advanced computer in a desk)", "computercraft:computer_advanced", "v2", "#2f3033", "#ffd76b", "terminal")
t("lever", "Lever on a redstone relay", "minecraft:lever", "v2", "#8d8f99", "#c0392b", "flat", "post")
t("board", "Split-flap display board (driven by a computer)", "create:display_board", "v2", "#1b1c20", "#ffb84a", "terminal")
t("lamp", "Wall lantern", "minecraft:lantern", "v2", "#e8b04a", "#fff0c0", "lava")
t("cyan", "Copper bulb light", "minecraft:copper_bulb", "v2", "#f0a860", "#fff0c8", "lava")
t("gfloor", "Tinted glass floor over the service trench", "minecraft:tinted_glass", "v2", "#3a3040", "#6a5a7a", "glass", a=0.35)
t("belt", "Conveyor belt (Create)", "create:belt", "v2", "#2b2b2f", "#8d8f99", "stripe", "slab")
t("tunnel", "Brass tunnel", "create:brass_tunnel", "v2", "#c9a35a", "#8a6a3a", "frame")
t("path", "Patrol path", "minecraft:deepslate_tiles", "v2", "#37373c", "#57e3c2", "bricks")
t("iron", "Industrial iron plating", "create:industrial_iron_block", "v2", "#3d4147", "#2e3136", "tiles")
t("speaker", "Speaker (alarms, door chime)", "computercraft:speaker", "v2", "#5b5d68", "#c0392b", "machine")
t("drone", "Drone docked in its bay (turtle)", "computercraft:turtle_normal", "v2", "#c9b04a", "#57e3c2", "machine")
t("baylamp", "Bay light (copper bulb on a relay: green docked, amber out, red trouble)", "minecraft:copper_bulb", "v2", "#7bd88f", "#e6fff0", "lava")
t("shelf", "Bay shelf (industrial iron slab)", "create:industrial_iron_block", "v2", "#3d4147", "#57e3c2", "tiles", "slab")
t("fuel", "Fuel port (ME interface: lava buckets out, drone loads in)", "ae2:interface", "v2", "#2c2f38", "#ffb84a", "frame")
t("hatch", "Hangar door leaf (Create sliding door)", "create:industrial_iron_block", "v2", "#3d4147", "#e8b04a", "stripe")
# the new outside, Create industrial (cat "skin": shown with the Outside button, in place of the old wall face)
t("sk_brick", "Brick wall", "minecraft:bricks", "skin", "#8f4b3a", "#6e3529", "bricks")
t("sk_plinth", "Plinth (cut andesite bricks)", "create:cut_andesite_bricks", "skin", "#8c8c84", "#6e6e66", "bricks")
t("sk_pier", "Pier (andesite casing), stands out of the wall", "create:andesite_casing", "skin", "#a3a091", "#6c5a3e", "frame")
t("sk_win", "Factory window (Create framed glass)", "create:framed_glass", "skin", "#c7dde3", "#5d4a33", "glass", a=0.55)
t("sk_cornice", "Cornice (cut andesite bricks), overhangs the wall", "create:cut_andesite_bricks", "skin", "#7c7c74", "#5e5e58", "bricks")
t("sk_shingle", "Sawtooth roof (copper shingles)", "create:copper_shingles", "skin", "#b8673f", "#8e4b2c", "tiles")
t("sk_roofwin", "Sawtooth roof light (framed glass, faces north)", "create:framed_glass", "skin", "#c7dde3", "#5d4a33", "glass", a=0.5)
t("sk_stack", "Smokestack (brick), smoke from a campfire at the top", "minecraft:bricks", "skin", "#7a3f31", "#5a2c22", "bricks")
t("sk_band", "Stack band (copper casing)", "create:copper_casing", "skin", "#b8673f", "#5c3a26", "frame")
t("sk_smoke", "Campfire (the stack smokes)", "minecraft:campfire", "skin", "#5a4636", "#ff9a3c", "lava")
t("sk_tank", "Fluid tank (Create): water and lava buffers for the generators and the fuel line", "create:fluid_tank", "skin", "#6f6250", "#c9a35a", "frame")
t("sk_pipe", "Copper pipe (Create fluid pipe)", "create:fluid_pipe", "skin", "#c47a4a", "#8e4b2c", "pipe", "pipe")
t("sk_belt", "Roof conveyor (Create belt): ore from the launch bay to the hall", "create:belt", "skin", "#2b2b2f", "#8d8f99", "stripe", "slab")
t("sk_cog", "Large cogwheel (Create), turning on the gate motor", "create:large_cogwheel", "skin", "#9b7a4a", "#5c4428", "machine")
t("sk_whistle", "Steam whistle (blows at shift change and on the alarm)", "create:steam_whistle", "skin", "#c9a35a", "#8a6a3a", "flat", "post")
t("sk_fan", "Roof vent (Create encased fan)", "create:encased_fan", "skin", "#8c8c84", "#2b2b2f", "machine")
t("sk_post", "Path light (lantern on a post)", "minecraft:lantern", "skin", "#e8b04a", "#fff0c0", "flat", "post")

SURVEY = dict(A.SURVEY)
SURVEY.update({"sophisticatedstorage:limited_barrel_1": "barrel", "sophisticatedstorage:limited_barrel_4": "barrel",
               "sophisticatedstorage:chest": "barrel", "computercraft:monitor_advanced": "monitor",
               "minecraft:furnace": "furn", "minecraft:grass_block": "grass", "minecraft:deepslate_tile_slab": "cap"})
V2 = "v2"

def shell():
    w = json.load(open(os.path.join(ROOT, "data", "world.json")))["blocks"]
    for k, name in w.items():
        X, Y, Z = map(int, k.split(","))
        x, y, z = X + 4448, Y - 71, Z - 1518
        if not (-12 <= x <= 47 and -6 <= z <= 35 and 0 <= y <= 12): continue
        if 28 <= x <= 43 and 4 <= z <= 28 and 1 <= y <= 6: continue
        ty = SURVEY.get(name)
        if ty: put(x, y, z, ty, 0, 0)
    for x in range(28, 44):
        for z in range(4, 29):
            if (x, 0, z) not in A.B or A.B[(x, 0, z)][0] not in ("pd", "dt", "db"): put(x, 0, z, "pd", 0, 0)
    for x in range(-12, 53):                       # the ground round the building
        for z in range(-6, 37):
            if not (0 <= x <= 44 and 0 <= z <= 30) and (x, 0, z) not in A.B: put(x, 0, z, "grass", 0, 0)

def v2():
    N = lambda s: s
    # 1. the blast gate at the south entrance (x 21-24, z 30)
    for x in range(21, 25):
        for y in range(1, 4):
            put(x, y, 30, "gateglass" if (x in (22, 23) and y == 2) else "gate", 0, 8,
                "Blast gate: two leaves of industrial iron on a Create gantry, driven by an electric motor. A computer opens it when the Player Detector sees someone on the list, and shuts it at night or on the LOCKDOWN lever")
    for x in range(20, 26): put(x, 4, 30, "girder", 0, 8, "Gantry the gate leaves hang from")
    put(26, 4, 30, "motor", 0, 8, "Electric motor on the foundry's power: no water wheel needed")
    put(20, 3, 31, "speaker", 0, 8, "Speaker: door chime, and the alarm when the guards see something")
    for x in range(19, 27):
        for z in range(31, 36): put(x, 0, z, "stripe" if (x in (19, 26) or z == 35) else "iron", 0, 8, "Apron in front of the gate")
    for x in (19, 26):
        for y in (1, 2): put(x, y, 31, "iron", 0, 8)
        put(x, 3, 31, "cyan", 0, 8, "Gate pylon light: cyan when open, red on lockdown (a computer swaps the block)")
    for x in (20, 25): put(x, 1, 32, "guard", 1, 8, "Guard post: a melee turtle either side of the gate")
    # 2. the patrol ring and corner guards
    for x in range(-2, 52):
        for z in (-2, 32):
            if (x, 0, z) not in A.B or A.B[(x, 0, z)][0] == "grass": put(x, 0, z, "path", 0, 8, "Patrol path: the guards walk this ring at night")
    for z in range(-2, 33):
        for x in (-2, 51):
            if (x, 0, z) not in A.B or A.B[(x, 0, z)][0] == "grass": put(x, 0, z, "path", 0, 8, "Patrol path")
    for (x, z) in ((-2, -2), (51, -2), (51, 32), (-2, 32)):
        put(x, 1, z, "guard", 0, 8, "Guard turtle with a sword: attacks hostile mobs on its beat, never swings while a player is within 6 blocks")
        put(x, 2, z, "cyan", 0, 8)
    # 3. the bridge: the control room upstairs in the west room (y 9)
    for z in range(9, 22):
        for y in range(9, 13): put(1, y, z, "monitor", 0, 8, "Map wall, 13 x 4 monitors: the land drawn in real map colours from the surveys, every drone a moving dot, touch a drone to order it")
    for z in range(10, 21):
        put(5, 9, z, "console", 2, 8, "Console desk: fleet, ME stock and crafting, power, the gate. Each one a touch screen")
        if z % 2 == 0: put(5, 10, z, "lever", 0, 8, "Levers on redstone relays: RECALL ALL, LOCKDOWN, MINERS OUT, LIGHTS, SIREN TEST. A computer reads them and acts")
    for x in range(3, 7):
        for z in range(11, 20):
            put(x, 8, z, "gfloor", 0, 8, "Glass floor in the Bridge: look straight down onto the launch bay and the drones in their bays")
    # 4. the hall: glass over the trench, light strips, the ore conveyor
    for z in range(6, 23):
        if z != 15: put(35, 0, z, "gfloor", 0, 8, "Tinted glass floor down the spine: the cables and pipes show under your feet")
    for x in range(29, 43): put(x, 3, 4, "belt", 0, 8, "Ore conveyor along the north wall: what the drones bring in rides the belt into ME where you can see it")
    put(36, 3, 4, "tunnel", 0, 8, "Brass tunnel on the belt")
    put(43, 3, 4, "iface", 0, 8, "ME Interface at the belt's end: the intake")
    put(28, 3, 4, "barrel", 0, 8, "Drop chute: drones hand in here")
    for z in range(5, 29, 4):
        put(28, 5, z, "lamp", 0, 8, "Wall light strip"); put(43, 5, z, "lamp", 0, 8, "Wall light strip")
    # 5. the launch bay: the old furnace room (x 1-8, z 4-28, y 1-7) becomes the drones' home
    for k in [k for k in A.B if 1 <= k[0] <= 8 and 4 <= k[2] <= 28 and 1 <= k[1] <= 7]: del A.B[k]
    for x in range(1, 9):
        for z in range(4, 29):
            put(x, 0, z, "stripe" if x in (2, 7) else "iron", 0, 8, "Launch bay floor: dark plating, striped lanes either side of the aisle")
    BAY = "Drone bay: the drone parks here between jobs, its light shows its state. Idle drones come home; none wait overhead"
    bays = [(8, z) for z in range(5, 28, 2)] + [(1, z) for z in list(range(5, 12, 2)) + list(range(21, 28, 2))]
    for (x, z) in bays:
        for lv in (1, 4):
            if lv == 4: put(x, 3, z, "shelf", 0, 8, "Bay shelf: the upper row of bays")
            put(x, lv, z, "drone", 1 if x == 8 else 3, 8, BAY)
            put(x, lv + 1, z, "baylamp", 0, 8, "Bay light: green docked, amber out on a job, red when the drone needs help. A computer sets each one through a redstone relay")
    for x in range(3, 7):
        put(x, 1, 4, "fuel" if x in (3, 4) else "iface", 0, 8,
            "Fuel and intake counter at the north end: drones hand in what they carry (ME interface), then take lava buckets (fuel port) before they dock" if x in (3, 4) else
            "Intake: what a drone brings in goes straight into ME")
    for z in range(13, 20):
        for y in range(1, 7):
            put(0, y, z, "hatch", 0, 8, "Hangar door in the west wall: two leaves on a Create gantry, opened by the bay computer as a drone comes or goes")
        put(0, 7, z, "girder", 0, 8, "Gantry the hangar door slides on")
    put(0, 7, 12, "motor", 0, 8, "Electric motor for the hangar door")
    for x in range(-1, 2):
        for z in range(13, 20):
            if x == 1: put(x, 0, z, "stripe", 0, 8, "Threshold")
    for z in range(5, 28, 4):
        put(4, 7, z, "cyan", 0, 8, "Ceiling light strip over the aisle"); put(5, 7, z, "cyan", 0, 8, "Ceiling light strip over the aisle")
    for x in range(2, 8):
        for y in (5, 6): put(x, y, 28, "board", 2, 8, "Departures board on the south wall: which drone left, for what, when it is due back. Split-flap, written by a computer")
    put(4, 1, 27, "console", 2, 8, "Bay console: launch, recall and refuel a drone by touch")
    put(5, 2, 27, "lever", 0, 8, "RECALL ALL lever")
    # 6. the apron where the old base stood: cleared, levelled, marked
    for k in [k for k in A.B if k[0] < 0 and -6 <= k[2] <= 35 and k[1] >= 1 and A.B[k][0] in ("cob", "cauld", "drip", "lava", "sb", "pd", "gl", "grass")]: del A.B[k]
    for x in range(-9, 0):
        for z in range(10, 23):
            edge = x == -9 or z in (10, 22)
            put(x, 0, z, "stripe" if edge else "iron", 0, 8, "Apron outside the hangar door, on the old base's ground: the old hut and chests are gone, carried into the store by the drones")
    for (x, z) in ((-9, 10), (-9, 22)):
        put(x, 1, z, "cyan", 0, 8, "Apron beacon")

SKIN = {}
def skin():
    """The new outside in Create industrial: brick walls with andesite piers that stand
    out of the face, tall factory windows between them, a plinth and an overhanging
    cornice; a sawtooth roof on the hall; smokestacks, tanks and copper pipes on the
    east side; a conveyor over the roof; vents, a cogwheel, a whistle, path lights."""
    SKIN.clear()
    WALL = ("sb", "pd", "gl", "dt", "db", "cob", "cap")
    pts = [k for k, v in A.B.items() if v[0] in WALL and k[1] >= 1 and -1 <= k[0] <= 46 and 0 <= k[2] <= 30]
    face = set()
    rows, colz = {}, {}
    for (x, y, z) in pts:
        r = rows.setdefault((y, z), [x, x]); r[0] = min(r[0], x); r[1] = max(r[1], x)
        c = colz.setdefault((y, x), [z, z]); c[0] = min(c[0], z); c[1] = max(c[1], z)
    for (y, z), (a, b) in rows.items(): face.add((a, y, z)); face.add((b, y, z))
    for (y, x), (a, b) in colz.items(): face.add((x, y, a)); face.add((x, y, b))
    top = {}
    for (x, y, z) in face: top[(x, z)] = max(top.get((x, z), 0), y)
    def opening(x, y, z): return (z == 30 and 20 <= x <= 25 and y <= 4) or (x == 0 and 12 <= z <= 20 and y <= 8)
    def normal(x, z):
        if x == 0: return (-1, 0)
        if x >= 44: return (1, 0)
        if z == 0: return (0, -1)
        if z == 30: return (0, 1)
        return None
    def put_s(x, y, z, ty):
        if (x, y, z) in A.B and A.B[(x, y, z)][0] not in WALL + ("grass", "path", "iron", "stripe"): return
        SKIN[(x, y, z)] = ty
    for (x, y, z) in face:
        n = normal(x, z)
        if not n or opening(x, y, z): continue
        tp = top[(x, z)]
        along = z if n[0] else x
        pier = along % 5 == 0
        win = along % 5 in (2, 3) and 3 <= y <= tp - 2
        if pier: ty = "sk_pier"
        elif y == 1: ty = "sk_plinth"
        elif y == tp: ty = "sk_cornice"
        elif win: ty = "sk_win"
        else: ty = "sk_brick"
        SKIN[(x, y, z)] = ty
        ox, oz = x + n[0], z + n[1]
        if opening(ox, y, oz) or opening(x, y, z): continue
        if pier: put_s(ox, y, oz, "sk_pier")
        elif y == 1: put_s(ox, y, oz, "sk_plinth")
        elif y == tp: put_s(ox, y, oz, "sk_cornice")
    for (x, z), tp in top.items():                 # pier caps rise above the cornice
        n = normal(x, z)
        if n and ((z if n[0] else x) % 5 == 0): SKIN[(x, tp + 1, z)] = "sk_pier"
    for (x, y, z) in pts:                         # inner walls above the roofs: brick to match
        if y >= 9 and (x, y, z) not in SKIN and not opening(x, y, z): SKIN[(x, y, z)] = "sk_brick"
    # the hall's sawtooth roof: north-facing glass, copper shingle slopes
    prof = {}
    for zt in range(1, 30, 5):
        prof[zt] = ("w", 13)
        for k, h in enumerate((13, 12, 11, 10)):
            if zt + 1 + k <= 29: prof[zt + 1 + k] = ("s", h)
    for z, (kind, h) in prof.items():
        for x in range(29, 44):
            if kind == "w":
                for y in range(10, 14): SKIN[(x, y, z)] = "sk_roofwin"
            else:
                SKIN[(x, h, z)] = "sk_shingle"
        for x in (28, 44):
            for y in range(11, h + 1): SKIN[(x, y, z)] = "sk_brick"
    # smokestacks and tanks on the east side, by the power bay
    for (z0, hgt) in ((4, 22), (24, 20)):
        for x in range(47, 50):
            for z in range(z0, z0 + 3):
                for y in range(1, hgt + 1):
                    SKIN[(x, y, z)] = "sk_band" if y in (hgt - 1, 6) else "sk_stack"
        SKIN[(48, hgt + 1, z0 + 1)] = "sk_smoke"
    for z0 in (10, 17):
        for x in range(47, 50):
            for z in range(z0, z0 + 3):
                for y in range(1, 8): SKIN[(x, y, z)] = "sk_tank"
        SKIN[(46, 5, z0 + 1)] = "sk_pipe"
    for z in range(11, 19): SKIN[(46, 8, z)] = "sk_pipe"
    SKIN[(46, 6, 11)] = SKIN[(46, 7, 11)] = SKIN[(46, 6, 18)] = SKIN[(46, 7, 18)] = "sk_pipe"
    SKIN[(43, 14, 3)] = "sk_whistle"
    # conveyor over the storeroom roof, launch bay to hall gable
    for x in range(8, 29): SKIN[(x, 10, 15)] = "sk_belt"
    for x in range(10, 28, 5): SKIN[(x, 9, 15)] = "sk_pier"
    for x in range(12, 27, 5):                     # roof vents over the storerooms
        for z in (7, 23): SKIN[(x, 9, z)] = "sk_fan"
    SKIN[(26, 4, 31)] = "sk_cog"
    for x in range(-3, 53, 8):                     # path lights round the patrol ring
        SKIN[(x, 1, -3)] = "sk_post"; SKIN[(x, 1, 33)] = "sk_post"
    for z in range(5, 30, 8):
        SKIN[(-3, 1, z)] = "sk_post"; SKIN[(52, 1, z)] = "sk_post"

ZONES = [
 dict(id="gate", name="Blast gate", cam=[22.5, 2, 31], h=5.5, ph="A",
      text="A four-wide sliding gate at the south entrance, built as a Create contraption on a gantry with an electric motor. A computer with the Player Detector opens it for people on the list and says so on a screen; LOCKDOWN shuts it. Two guard turtles stand either side."),
 dict(id="launch", name="Launch bay", cam=[4.5, 2, 16], h=6.5, ph="B",
      text="The old furnace room becomes the drones' home. 40 bays in two rows down both walls, each with a light (green docked, amber out, red trouble). A hangar door in the west wall opens as a drone comes or goes. At the north end a counter takes in what they carry and hands out lava buckets; at the south end the departures board and a console. The 12 vanilla furnaces go: their smelting moves to the ME smelters first."),
 dict(id="bridge", name="The Bridge", cam=[4, 10, 15], h=13.5, ph="B",
      text="The control room, upstairs over the launch bay. One wall is the map: 13 by 4 monitors showing the land in real map colours with every drone as a moving dot. A row of consoles with levers that do things, and a glass floor to look straight down on the bays. Turn on the upper deck to see it."),
 dict(id="hall", name="Foundry hall", cam=[36, 1, 15], h=6.5, ph="C",
      text="The AE2 and Mekanism hall, running. v2 adds a tinted glass floor down the spine so the cables and pipes show, light strips, and an overhead belt that carries incoming ore into ME."),
 dict(id="store", name="Storerooms", cam=[14, 1, 15], h=6.5, ph="C",
      text="The barrel rooms stay, now read and filled by ME. v2 adds category lighting over each zone and a requisition screen at each end."),
 dict(id="lane", name="Old rack", cam=[22, 1, 2], h=4.5, ph="E",
      text="The old lane and rack retire once the launch bay is running. The lane stays as a corridor; the rack comes out."),
 dict(id="outside", name="The outside", cam=[24, 6, 15], h=4, ph="F",
      text="Create industrial. Brick walls with andesite piers that stand a block proud, tall factory windows between them, a plinth at the foot and an overhanging cornice. The hall gets a sawtooth roof: copper shingles with north-facing glass. On the east side by the power bay, two brick smokestacks that smoke and two Create fluid tanks piped into the wall. A conveyor runs over the storeroom roof from the launch bay into the hall. Vents, a steam whistle, a cogwheel turning by the gate, lanterns round the path."),
 dict(id="guards", name="Guards", cam=[46, 1, 32], h=3.5, ph="D",
      text="Four melee turtles walk a ring round the building at night and two hold the gate. They strike hostile mobs only, stand down near players, and raise the alarm and the gate lights."),
 dict(id="yard", name="Apron", cam=[-5, 1, 16], h=3.5, ph="E",
      text="Where the old base stands: taken apart by the drones into the store, levelled, and laid as a marked apron in front of the hangar door. The ground round the factory is terraformed to match."),
]

def page():
    A.B.clear(); A.LINKS.clear(); del A.NOTES[:]
    shell(); A.plan(); A.services(); v2()
    for k in [k for k, v in A.B.items() if v[0] in ("evap", "ghost")]: del A.B[k]
    skin()
    keys = list(T)
    blocks = []
    for (x, y, z), (ty, f, ph, ni) in A.B.items():
        m = 0
        if T[ty]["s"] == "pipe":
            for i, (dx, dy, dz) in enumerate(((1, 0, 0), (0, 0, 1), (-1, 0, 0), (0, 0, -1), (0, 1, 0), (0, -1, 0))):
                nb = (x + dx, y + dy, z + dz)
                if (nb in A.B and A.B[nb][0] == ty) or ((x, y, z), nb) in A.LINKS: m |= 1 << i
        blocks.append([x, y, z, keys.index(ty), f, min(ph, 8), ni, m])
    for (x, y, z), ty in SKIN.items():
        m = 0
        if ty == "sk_pipe":
            for i, (dx, dy, dz) in enumerate(((1, 0, 0), (0, 0, 1), (-1, 0, 0), (0, 0, -1), (0, 1, 0), (0, -1, 0))):
                nb = SKIN.get((x + dx, y + dy, z + dz))
                if nb in ("sk_pipe", "sk_tank") or (dx == -1 and (x + dx, y, z) not in SKIN): m |= 1 << i
        blocks.append([x, y, z, keys.index(ty), 0, 8, -1, m])
    data = dict(types=[dict(k=k, **T[k]) for k in keys], blocks=blocks, notes=A.NOTES, zones=ZONES, phases=[], bom={})
    tpl = open(os.path.join(ROOT, "tools", "ae2plan_page.html")).read()
    book = open(os.path.join(ROOT, "tools", "factoryv2_book.js")).read()
    a, b = tpl.index("const TABS="), tpl.index("function show(")
    tpl = tpl[:a] + book + "\n" + tpl[b:]
    rep = [("<title>Foundry AE2 Plan</title>", "<title>Factory v2 Concept</title>"),
           ("<h1>Foundry AE2 Plan</h1>", "<h1>Factory v2 Concept</h1>"),
           ("The foundry hall as it would stand: your real walls and floor from tonight's scan, with the whole AE2 and Mekanism factory in it. The two walls nearest you are cut away. Drag to move, scroll to zoom, hover any block.",
            "The whole factory as it would look after the redesign: the new outside first. Press Outside to take the walls off and see in; pick a zone on the right to fly to it. Drag to move, scroll to zoom, hover any block. Nothing here is built until you say."),
           ('<div class="grp"><label for="ph">Build phase</label><input id="ph" type="range" min="0" max="8" value="8"><label id="phv">8 of 8</label></div>',
            '<div class="grp"><button id="t_out" aria-pressed="true">Outside</button><button id="t_up" aria-pressed="false">Upper deck</button><input id="ph" type="hidden" value="8"><label id="phv" hidden></label></div>'),
           ('press("t_floor","floor");', 'press("t_up","upper");press("t_out","out");press("t_floor","floor");'),
           ("    const cat=t.cat;\n", "    const cat=t.cat;\n    if(cat==\"skin\"&&!O.out)continue;if(O.out&&cat!=\"skin\"&&SK.has(b[0]+\",\"+b[1]+\",\"+b[2]))continue;\n"),
           ("const V=Object.assign({},HOME),O={", "const SK=new Set(D.blocks.filter(b=>D.types[b[3]].cat==\"skin\").map(b=>b[0]+\",\"+b[1]+\",\"+b[2]));const V=Object.assign({},HOME),O={out:true,"),
           ("    if(b[5]>O.phase)continue;", "    if(b[5]>O.phase)continue;if(!O.upper&&!O.out&&b[1]>=6)continue;"),
           ("const HOME={cx:36,cz:16.5,rot:0,zoom:1,px:0,py:0};", "const HOME={cx:20,cz:15,rot:0,zoom:1,px:0,py:0};"),
           ("Math.min(W/(30*HW*1.45),H/(30*HH*1.9))", "Math.min(W/(62*HW*1.1),H/(62*HH*1.5))"),
           ('zn.id=="core"?6.4:(zn.id=="garden"?5.4:(zn.id=="fuel"?2.4:3.3))', "(zn.h||3.3)"),
           ("const nr=d=>d==0?b[0]>=44:d==1?b[2]>=29:d==2?b[0]<=27:b[2]<=3,n=nr(XDIR[r])||nr(ZDIR[r]);",
            "const nr=d=>d==0?b[0]>=44:d==1?b[2]>=29:d==2?b[0]<=0:b[2]<=0,n=(nr(XDIR[r])||nr(ZDIR[r]))&&b[0]>=0&&b[0]<=44&&b[2]>=0&&b[2]<=30&&TY[b[3]].cat!=\"v2\"&&!O.out;"),
           ("if(n&&b[0]>=45&&b[1]>=1)a*=.3}", "}"),
           ('if(!O.mach&&(cat=="ae"||cat=="mek"||cat=="power"||cat=="lava")&&!(cat=="lava"))continue;',
            'if(!O.mach&&(cat=="ae"||cat=="mek"||cat=="power"||cat=="v2"))continue;'),
           ('if(id=="bay")requestAnimationFrame(minis);', ""),
           ("V.px=0;V.py=40;V.zoom=Math.max(HOME.zoom*2.2,2);", "V.px=0;V.zoom=Math.max(HOME.zoom*2.2,2);V.py=40+(zn.cam[1]-1)*BH*V.zoom;"),
           ('<button id="home">Whole hall</button>', '<button id="home">Whole factory</button>'),
           ('function focusZone(id){const zn=D.zones.find(z=>z.id==id);O.sel=id;',
            'function focusZone(id){const zn=D.zones.find(z=>z.id==id);O.sel=id;if(id=="bridge"&&!O.upper){O.upper=true;document.getElementById("t_up").setAttribute("aria-pressed","true")}O.out=["outside","gate","guards","yard"].includes(id);document.getElementById("t_out").setAttribute("aria-pressed",O.out);')]
    for x, y in rep:
        assert tpl.count(x) == 1, x[:60]
        tpl = tpl.replace(x, y)
    html = tpl.replace("/*DATA*/null", json.dumps(data, separators=(",", ":")))
    open(os.path.join(ROOT, "docs", "factory-v2.html"), "w").write(html)
    return len(html), len(blocks)

if __name__ == "__main__":
    print(page())
