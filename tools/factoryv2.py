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
# interior to match, and the Create layer
t("iwall", "Inside wall (light grey concrete), was stone brick", "minecraft:light_gray_concrete", "build", "#9d9d97", "#86867f", "flat")
t("iglass", "Inside glass (grey stained glass)", "minecraft:gray_stained_glass", "build", "#3a3f47", "#69707c", "glass", a=0.6)
t("basin", "Basin (Create)", "create:basin", "v2", "#8a8a84", "#5c5c56", "frame")
t("press", "Mechanical press (Create): plates and sheets", "create:mechanical_press", "v2", "#8a6a3a", "#c9a35a", "machine")
t("mixer", "Mechanical mixer (Create): brass, andesite alloy, dough", "create:mechanical_mixer", "v2", "#8a6a3a", "#c9a35a", "machine")
t("deployer", "Deployer (Create): fits parts onto what passes on the belt", "create:deployer", "v2", "#8a6a3a", "#5c4428", "machine")
t("catwalk", "Catwalk (Create metal girder deck) over the machines", "create:metal_girder", "v2", "#6a6f76", "#3e4248", "bricks", "slab")
t("rail", "Railing (iron bars)", "minecraft:iron_bars", "v2", "#8d8f99", "#5d5f66", "frame", "bars")
t("chute", "Chute (Create): drops what the belt carries into the machine below", "create:chute", "v2", "#8d8f99", "#c9a35a", "frame")
t("lavapipe", "Lava main (Create copper pipe): from the Nether pump to the generators and the fuel port", "create:fluid_pipe", "v2", "#d06a2a", "#8e4b2c", "pipe", "pipe")
t("waterpipe", "Water main (Create copper pipe, glass sections): to the generators and boilers", "create:fluid_pipe", "v2", "#3a7bd0", "#2a5a9a", "pipe", "pipe")
t("hlamp", "Hanging lantern on a chain", "minecraft:lantern", "v2", "#e8b04a", "#fff0c0", "flat", "post")
t("ore", "Ore on the belt", "minecraft:raw_iron_block", "v2", "#b89a7a", "#8a6a4a", "speck", "post")
t("deck", "Floor slab (grey concrete)", "minecraft:gray_concrete", "v2", "#5a5c60", "#4b4d51", "flat")
t("redcol", "Red steel column (red concrete)", "minecraft:red_concrete", "v2", "#9b2d24", "#7a2119", "flat")
t("packager", "Packager (Create): boxes what a drone brings in into a package addressed to where it goes", "create:packager", "v2", "#8a6a3a", "#c9a35a", "machine")
t("frogport", "Frogport (Create): catches packages off the chain and throws them on", "create:package_frogport", "v2", "#5f8a3a", "#c9a35a", "machine")
t("ticker", "Stock ticker (Create): ask for anything in stock, it is packed and sent here", "create:stock_ticker", "v2", "#3a3d44", "#ffb84a", "terminal")
t("requester", "Redstone requester (Create): a lever that orders a set load, e.g. 64 steel to the hall", "create:redstone_requester", "v2", "#5b5d68", "#c0392b", "machine")
t("chainpost", "Chain conveyor (Create): packages ride the chain overhead between posts", "create:chain_conveyor", "v2", "#9b7a4a", "#5c4428", "machine")
t("chain", "Chain conveyor run", "create:chain_conveyor", "v2", "#8d8f99", "#5d5f66", "frame", "chain")
t("pkg", "Package on its way", "create:cardboard_block", "v2", "#b88a55", "#8e6a3e", "tiles", "post")
t("gshaft", "Gantry shaft (Create): the crane rides it the length of the hall", "create:gantry_shaft", "v2", "#9b2d24", "#5a5f66", "frame", "beam")
t("gcar", "Gantry carriage with a hook (Create)", "create:gantry_carriage", "v2", "#9b2d24", "#c9a35a", "machine")
t("hook", "Crane hook chain", "minecraft:chain", "v2", "#5d5f66", "#3a3b40", "frame", "chain")
t("burner", "Blaze burner under the boiler (Create)", "create:blaze_burner", "v2", "#3a3b40", "#ff8a2a", "lava")
t("boiler", "Boiler (Create fluid tank, 3 x 3 x 3)", "create:fluid_tank", "v2", "#6f6250", "#c9a35a", "frame")
t("sengine", "Steam engine (Create): turns the shafts that run the gate, the lift, the crane and the belts", "create:steam_engine", "v2", "#8d8f99", "#c9a35a", "machine")
t("bigcog", "Large cogwheel (Create)", "create:large_cogwheel", "v2", "#9b7a4a", "#5c4428", "machine")
t("shaft", "Shaft (Create)", "create:shaft", "v2", "#8d8f99", "#5d5f66", "frame", "beam")
t("crafter", "Mechanical crafter wall (Create): big recipes laid out where you can watch them", "create:mechanical_crafter", "v2", "#b8673f", "#5c3a26", "machine")
t("flue", "Flue up to the roof stacks (copper pipe)", "create:fluid_pipe", "v2", "#c47a4a", "#8e4b2c", "pipe", "pipe")
# the new outside: concrete block, green-roofed podium, red steel (cat "skin", shown with Outside)
t("sk_conc", "Light grey concrete", "minecraft:light_gray_concrete", "skin", "#9d9d97", "#86867f", "flat")
t("sk_pil", "Pilaster (light grey concrete), stands a block out of the wall", "minecraft:light_gray_concrete", "skin", "#a9a9a3", "#8d8d86", "flat")
t("sk_band", "Floor band (smooth stone), stands out at every floor", "minecraft:smooth_stone", "skin", "#b9b9b4", "#9c9c96", "tiles")
t("sk_win", "Window (grey stained glass), dark by day, lit at night", "minecraft:gray_stained_glass", "skin", "#3a3f47", "#69707c", "glass", a=0.85)
t("sk_wlit", "Window, lit", "minecraft:gray_stained_glass", "skin", "#c9a25a", "#69707c", "glass", a=0.85)
t("sk_roof", "Roof deck (grey concrete)", "minecraft:gray_concrete", "skin", "#5a5c60", "#4b4d51", "flat")
t("sk_red", "Red steel (red concrete)", "minecraft:red_concrete", "skin", "#9b2d24", "#7a2119", "flat")
t("sk_bars", "Lattice bracing (iron bars)", "minecraft:iron_bars", "skin", "#8d8f99", "#5d5f66", "frame", "bars")
t("sk_core", "Furnace shaft (polished deepslate)", "minecraft:polished_deepslate", "skin", "#36373c", "#25262a", "tiles")
t("sk_moss", "Green roof (moss)", "minecraft:moss_block", "skin", "#5f8a3a", "#4a7030", "speck")
t("sk_sky", "Skylight (glass)", "minecraft:glass", "skin", "#cfe6ee", "#ffffff", "glass", a=0.45)
t("sk_white", "Chimney band (white concrete)", "minecraft:white_concrete", "skin", "#d8dadb", "#c3c5c6", "flat")
t("sk_grey", "Chimney (grey concrete)", "minecraft:gray_concrete", "skin", "#6b6d72", "#56585c", "flat")
t("sk_road", "Road (grey concrete)", "minecraft:gray_concrete", "skin", "#4a4b4f", "#3e3f42", "flat")
t("sk_line", "Road line (white concrete)", "minecraft:white_concrete", "skin", "#d8dadb", "#c3c5c6", "flat")
t("sk_pave", "Forecourt (smooth stone)", "minecraft:smooth_stone", "skin", "#b0b0ab", "#9a9a95", "tiles")
t("sk_hedge", "Hedge (azalea leaves)", "minecraft:azalea_leaves", "skin", "#4f7a32", "#3c6125", "speck")
t("sk_log", "Tree (oak log)", "minecraft:oak_log", "skin", "#6b5235", "#4e3b25", "bricks")
t("sk_leaf", "Tree (oak leaves)", "minecraft:oak_leaves", "skin", "#4c8a2e", "#3a6e22", "speck")
t("sk_lamp", "Street light (lantern on a post)", "minecraft:lantern", "skin", "#e8b04a", "#fff0c0", "flat", "post")
t("sk_chain", "Chain conveyor (Create) between the red tower and the main block: packages ride it in the open", "create:chain_conveyor", "skin", "#8d8f99", "#5d5f66", "frame", "chain")
t("sk_chainpost", "Chain conveyor post (Create)", "create:chain_conveyor", "skin", "#9b7a4a", "#5c4428", "machine")
t("sk_pkg", "Package on the chain", "create:cardboard_block", "skin", "#b88a55", "#8e6a3e", "tiles", "post")
t("sk_pod", "Lookout glass (tinted)", "minecraft:tinted_glass", "skin", "#2c2a33", "#69707c", "glass", a=0.7)

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

def v3():
    """Inside, to match the new outside, with Create doing the moving."""
    WALL = ("sb", "pd", "dt", "db", "cob", "cap")
    for k, v in list(A.B.items()):              # stone brick inside becomes concrete and grey glass
        x, y, z = k
        if 0 <= x <= 45 and 0 <= z <= 30 and y >= 1:
            if v[0] in WALL: A.B[k] = ("deck" if (y == 8 and v[0] == "pd") else "iwall",) + tuple(v[1:])
            elif v[0] == "gl": A.B[k] = ("iglass",) + tuple(v[1:])
    # floor 3 slab (the engine floor) over the main block
    for x in range(1, 27):
        for z in range(1, 30): put(x, 15, z, "deck", 0, 8, "Engine floor slab")
    # --- floor 2, the logistics deck beside the Bridge (x 10..26, y 9..14)
    for z in range(12, 19): put(10, 11, z, "board", 1, 8, "Stock boards (Create display boards): what is in ME and the barrels, what is on its way")
    put(13, 9, 15, "ticker", 2, 8, "Stock ticker: ask for anything in stock; it is packed and sent to this deck, the Bridge or the hall")
    for z in (13, 14, 16, 17): put(12, 9, z, "requester", 0, 8, "Redstone requesters: pull a lever, a set load is ordered (64 steel to the hall, a stack of lava buckets to the launch bay)")
    for x in range(15, 26, 3):
        put(x, 9, 4, "packager", 0, 8, "Packagers on the ME interfaces: ME stock leaves as addressed packages")
        put(x, 10, 4, "frogport", 0, 8, "Frogport: throws the package onto the chain")
    # chain conveyor loop overhead on the deck, and on into the hall
    loop = [(11, 4), (25, 4), (25, 26), (11, 26)]
    for (x, z) in loop: put(x, 13, z, "chainpost", 0, 8, "Chain conveyor post: a cogwheel the chain runs round")
    for x in range(12, 25):
        put(x, 13, 4, "chain", 0, 8, "Chain conveyor: packages ride it overhead"); put(x, 13, 26, "chain", 0, 8, "Chain conveyor")
    for z in range(5, 26):
        put(11, 13, z, "chain", 1, 8, "Chain conveyor"); put(25, 13, z, "chain", 1, 8, "Chain conveyor")
    for (x, z) in ((18, 4), (25, 14), (14, 26)): put(x, 12, z, "pkg", 0, 8, "A package on its way")
    # down into the hall: a post at the wall, the chain along z 20, a frogport over the ore line
    put(27, 9, 20, "chainpost", 0, 8, "Chain conveyor post at the hall wall")
    for x in range(28, 40): put(x, 9, 20, "chain", 0, 8, "Chain conveyor into the hall, under the skylights")
    put(40, 9, 20, "chainpost", 0, 8, "Chain conveyor post")
    for z in range(14, 20): put(40, 9, z, "chain", 1, 8, "Chain conveyor")
    put(40, 9, 13, "chainpost", 0, 8, "Chain conveyor post")
    put(41, 8, 13, "frogport", 0, 8, "Frogport over the ore line: drops packages of raw ore into its ME interface; takes finished ingots back")
    put(33, 8, 20, "pkg", 0, 8, "Raw ore on its way to the ore line")
    # from the launch bay intake up to the deck
    put(5, 2, 5, "packager", 0, 8, "Packager on the intake: what a drone hands in is boxed")
    put(5, 3, 5, "frogport", 0, 8, "Frogport: throws the box up to the chain on the deck")
    # --- floor 3, the engine floor (y 16..19): two boilers right under the roof stacks
    for (bx, bz) in ((12, 12), (17, 12)):
        for x in range(bx, bx + 3):
            for z in range(bz, bz + 3):
                put(x, 16, z, "burner", 0, 8, "Blaze burners: superheated, they boil the water")
                for y in (17, 18, 19): put(x, y, z, "boiler", 0, 8, "Boiler (Create fluid tank): water in from ME, steam to the engines")
        for x in range(bx, bx + 3): put(x, 18, bz - 1, "sengine", 3, 8, "Steam engine on the boiler side: turns the shaft line")
        put(bx + 1, 20, bz + 1, "flue", 0, 8, "Flue to the red stack on the roof")
    for x in range(4, 26): put(x, 18, 9, "shaft", 0, 8, "Shaft line along the engine floor")
    for x in (6, 15, 24): put(x, 18, 8, "bigcog", 0, 8, "Large cogwheel: the drive splits here")
    for y in range(1, 18): put(24, y, 9, "shaft", 2, 8, "Drive shaft down through the building: gate, belts, the crane" if y == 9 else "Drive shaft")
    for z in range(22, 26):
        for y in range(16, 19): put(1, y, z, "crafter", 1, 8, "Mechanical crafter wall: big Create recipes on show")
    # a Create processing line across the south of the engine floor: belt, presses, mixers on burners, deployers
    for x in range(5, 26): put(x, 16, 25, "belt", 0, 8, "Processing belt (Create): ingots in from the chain, plates, brass and parts out")
    for x in (8, 11):
        put(x, 18, 25, "press", 0, 8, "Mechanical press over the belt: iron, copper and gold sheets")
        put(x, 17, 25, "shaft", 2, 8, "Press head")
    for x in (15, 19):
        put(x, 16, 23, "burner", 0, 8, "Blaze burner under the basin: heated mixing")
        put(x, 17, 23, "basin", 0, 8, "Basin")
        put(x, 19, 23, "mixer", 0, 8, "Mechanical mixer: brass from copper and zinc, andesite alloy")
    for x in (22, 24): put(x, 17, 26, "deployer", 3, 8, "Deployer: fits parts onto what passes on the belt")
    put(25, 17, 25, "frogport", 0, 8, "Frogport: finished parts go back onto the chain to ME")
    for x in (7, 13, 19, 25):
        for z in (6, 20):
            for y in range(16, 20):
                if (x, y, z) not in A.B: put(x, y, z, "redcol", 0, 8, "Red steel column")
    for x in range(5, 26, 4):
        put(x, 19, 3, "cyan", 0, 8, "Light"); put(x, 19, 28, "cyan", 0, 8, "Light")
    put(3, 16, 27, "console", 2, 8, "Engine console: steam pressure, shaft speed, burner fuel")
    # --- the hall: red columns at the walls, the gantry crane under the skylights
    for x in (30, 36, 42):
        for z in (1, 29):
            for y in range(1, 10):
                if (x, y, z) not in A.B: put(x, y, z, "redcol", 0, 8, "Red steel column")
    for x in range(29, 44): put(x, 9, 15, "gshaft", 0, 8, "Gantry shaft: the hall crane runs on it")
    put(35, 8, 15, "gcar", 0, 8, "Gantry carriage: lifts a full crate from the drop point to any machine")
    for y in (6, 7): put(35, y, 15, "hook", 2, 8, "Crane hook")
    put(35, 5, 15, "pkg", 0, 8, "A crate on the hook")
    def free(x, y, z): return (x, y, z) not in A.B
    # the overhead layer in the hall: catwalk galleries, bridges, belts with ore on them, pipe mains, lanterns, drones
    for x in range(29, 43):
        for z in (2, 3, 27, 28):
            if free(x, 5, z): put(x, 5, z, "catwalk", 0, 8, "Gallery catwalk: walk the hall above the machines")
        for z in (4, 26):
            if free(x, 6, z): put(x, 6, z, "rail", 1, 8, "Railing")
    for x in (32, 41):
        for z in range(4, 27):
            if free(x, 5, z): put(x, 5, z, "catwalk", 1, 8, "Bridge across the hall over the machines")
            for xx in (x - 1, x + 1):
                if free(xx, 6, z) and z not in (8, 22): put(xx, 6, z, "rail", 0, 8, "Railing")
    for (zb, dest, cx) in ((8, "the ore line", 43), (22, "the alloy row", 39)):
        for x in range(29, 44):
            if free(x, 7, zb): put(x, 7, zb, "belt", 0, 8, "Overhead belt (Create) on red brackets: carries ore from the roof drop to " + dest)
            if x % 4 == 1 and free(x, 8, zb): put(x, 8, zb, "redcol", 0, 8, "Red bracket")
        for y in (5, 6):
            if free(cx, y, zb): put(cx, y, zb, "chute", 0, 8, "Chute down into " + dest)
    for x in range(29, 44):
        if free(x, 8, 11): put(x, 8, 11, "lavapipe", 0, 8, "Lava main")
        if free(x, 8, 19): put(x, 8, 19, "waterpipe", 0, 8, "Water main")
    for x in (31, 37, 43):
        for z in (5, 13, 24):
            if free(x, 8, z) and free(x, 7, z):
                put(x, 8, z, "hook", 2, 8, "Chain"); put(x, 7, z, "hlamp", 0, 8, "Hanging lantern")
    put(34, 6, 11, "drone", 0, 8, "A drone in flight, bringing a load in from the roof hatch")
    put(39, 7, 18, "drone", 2, 8, "A drone in flight to the alloy row")
    # the logistics deck: sorting belts with packages, more on the chain, lights, columns
    for zb in (8, 22):
        for x in range(14, 26):
            put(x, 9, zb, "belt", 0, 8, "Sorting belt: packages run to their frogport")
        put(26, 9, zb, "frogport", 0, 8, "Frogport at the belt end: up onto the chain")
    for x in (14, 20):
        for z in (11, 19):
            for y in range(9, 15): put(x, y, z, "redcol", 0, 8, "Red steel column")
    for x in range(13, 26, 4):
        for z in (6, 15, 24):
            if free(x, 14, z): put(x, 14, z, "hlamp", 0, 8, "Light")
    # engine floor: a second process line, a tank farm, overhead drive, lights
    for x in range(5, 26):
        if free(x, 16, 20): put(x, 16, 20, "belt", 0, 8, "Wash and press line (Create belt)")
    for x in (8, 12, 16, 20):
        if free(x, 18, 20): put(x, 18, 20, "press", 0, 8, "Mechanical press over the belt: plates from ingots")
        if free(x, 19, 20): put(x, 19, 20, "shaft", 0, 8, "Drive shaft")
    for x in (10, 14, 18, 22):
        if free(x, 18, 20): put(x, 18, 20, "deployer", 3, 8, "Deployer: puts the next part on")
    for x in range(5, 26):
        if free(x, 20, 20): put(x, 20, 20, "shaft", 0, 8, "Overhead drive shaft")
    for x in (2, 3):
        for z in range(11, 20, 2):
            for y in range(16, 20):
                if free(x, y, z): put(x, y, z, "boiler", 0, 8, "Fluid tank: lava and water stores for the boilers")
    for x in range(4, 26, 5):
        for z in (6, 16, 28):
            if free(x, 20, z) and free(x, 19, z):
                put(x, 20, z, "hook", 2, 8, "Chain"); put(x, 19, z, "hlamp", 0, 8, "Hanging lantern")
    for x in range(5, 26):
        if free(x, 19, 11): put(x, 19, 11, "flue", 0, 8, "Steam main from the boilers")
    # drones in the air outside: out of the hangar, over the apron, up past the roof
    for (x, y, z, n) in ((-7, 4, 16, "leaving the hangar"), (-13, 8, 13, "climbing out over the apron"), (-18, 13, 9, "outbound to the mine"),
                         (-6, 6, 19, "coming in to land"), (8, 26, 6, "over the roof"), (40, 24, 4, "on its way to the red tower")):
        put(x, y, z, "drone", 3, 8, "A drone " + n)

SKIN = {}
def skin():
    """The new outside, after Kyle's reference: a tall concrete block with a strong grid
    (pilasters and floor bands standing proud, dark windows set back), a low podium over
    the hall with an arcade and a green roof with skylights, red steel lattice towers
    joined by red bridges, twin banded chimneys, a forecourt, road, hedges and trees."""
    SKIN.clear()
    def S(x, y, z, ty, f=0): SKIN[(x, y, z)] = (ty, f)
    def opening(x, y, z): return (z == 30 and 20 <= x <= 25 and y <= 4) or (x == 0 and 12 <= z <= 20 and y <= 8)
    # ---- the main block: x 0..27, z 0..30, four floors to y 21
    TOP = 21
    def grid_face(cells, n, ylo, yhi, step=3, lit=()):
        """cells: list of (x, z, along) on one face; n: outward (dx, dz)."""
        for (x, z, al) in cells:
            for y in range(ylo, yhi + 1):
                if opening(x, y, z): continue
                pil = al % step == 0
                band = y % 5 == 0
                if y == yhi: ty = "sk_conc"
                elif pil or band: ty = "sk_conc"
                elif y <= 3 and z == 30: ty = "sk_wlit"
                else: ty = "sk_wlit" if (al * 7 + y * 3) % 11 in lit else "sk_win"
                S(x, y, z, ty)
                ox, oz = x + n[0], z + n[1]
                if opening(ox, y, oz) or opening(x, y, z): continue
                if pil: S(ox, y, oz, "sk_pil")
                elif band: S(ox, y, oz, "sk_band")
    LIT = (2, 5)
    grid_face([(x, 30, x) for x in range(0, 28)], (0, 1), 1, TOP, lit=LIT)
    grid_face([(x, 0, x) for x in range(0, 28)], (0, -1), 1, TOP, lit=LIT)
    grid_face([(0, z, z) for z in range(0, 31)], (-1, 0), 1, TOP, lit=LIT)
    grid_face([(27, z, z) for z in range(0, 31)], (1, 0), 11, TOP, lit=LIT)
    for x in range(1, 27):
        for z in range(1, 30): S(x, TOP, z, "sk_roof")
    for x in range(0, 28):
        S(x, TOP + 1, 0, "sk_red"); S(x, TOP + 1, 30, "sk_red")
    for z in range(0, 31):
        S(0, TOP + 1, z, "sk_red"); S(27, TOP + 1, z, "sk_red")
    # ---- the podium over the hall: x 28..45, arcade on the south and east, green roof
    PT = 10
    def arcade(cells, n):
        for (x, z, al) in cells:
            pier = al % 4 == 0
            for y in range(1, PT + 1):
                if opening(x, y, z): continue
                if y == PT: ty = "sk_conc"
                elif y == 4: ty = "sk_red"
                else: ty = "sk_win"
                S(x, y, z, ty)
                if pier:
                    for k in (1, 2): S(x + n[0] * k, y, z + n[1] * k, "sk_pil")
            for k in (1, 2): S(x + n[0] * k, PT, z + n[1] * k, "sk_band")
            S(x + n[0] * 2, PT + 1, z + n[1] * 2, "sk_conc")
    arcade([(x, 30, x) for x in range(28, 46)], (0, 1))
    arcade([(45, z, z) for z in range(0, 31)], (1, 0))
    arcade([(x, 0, x) for x in range(28, 46)], (0, -1))
    for x in range(28, 45):
        for z in range(1, 30):
            ty = "sk_sky" if (z % 6 in (2, 3) and 30 <= x <= 42) else ("sk_pave" if x in (28, 44) or z % 6 == 5 else "sk_moss")
            S(x, PT, z, ty)
    # ---- red steel: the lattice tower on the east (a headframe over the furnace shaft)
    X0, X1, Z0, Z1, H = 49, 55, 9, 15, 34
    for y in range(1, H + 1):
        for x in range(X0, X1 + 1):
            for z in range(Z0, Z1 + 1):
                edge_x, edge_z = x in (X0, X1), z in (Z0, Z1)
                if edge_x and edge_z: S(x, y, z, "sk_red")
                elif (edge_x or edge_z) and y % 6 == 0: S(x, y, z, "sk_red")
                elif edge_x or edge_z:
                    al = z if edge_x else x
                    if (al - (Z0 if edge_x else X0) + y) % 6 == 0: S(x, y, z, "sk_bars", 1 if edge_x else 0)
    for y in range(1, 27):
        for x in range(51, 54):
            for z in range(11, 14): S(x, y, z, "sk_core")
    for y in range(H + 1, H + 5):
        for x in range(X0 + 1, X1):
            for z in range(Z0 + 1, Z1): S(x, y, z, "sk_red" if y == H + 4 or x in (X0 + 1, X1 - 1) or z in (Z0 + 1, Z1 - 1) else "sk_core")
    for k in range(0, 15):                                  # inclined red skip-bridge down onto the podium roof
        S(48 - k, 25 - k, 12, "sk_red"); S(48 - k, 26 - k, 12, "sk_bars", 0)
    for x in range(28, 49):                                 # high red truss across to the main block
        S(x, 24, 18, "sk_red"); S(x, 27, 18, "sk_red")
        if x % 3 == 0: S(x, 25, 18, "sk_red"); S(x, 26, 18, "sk_red")
        else: S(x, 25, 18, "sk_bars", 0); S(x, 26, 18, "sk_bars", 0)
    for x in range(28, 49):                                 # chain conveyor from the tower to the main block
        S(x, 19, 12, "sk_chain", 0)
    S(48, 19, 11, "sk_chainpost"); S(27, 19, 11, "sk_chainpost")
    # red frame and twin red stacks on the main block's roof
    for x in range(12, 21):
        for z in range(10, 19):
            for y in range(TOP + 1, 30):
                ex, ez = x in (12, 20), z in (10, 18)
                if (ex and ez) or ((ex or ez) and y in (TOP + 1, 25, 29)): S(x, y, z, "sk_red")
                elif (ex or ez) and (x + z + y) % 4 == 0: S(x, y, z, "sk_bars", 1 if ex else 0)
    for (sx, sz) in ((13, 13), (18, 13)):
        for y in range(TOP + 1, 42):
            for dx in (0, 1):
                for dz in (0, 1): S(sx + dx, y, sz + dz, "sk_core" if y >= 40 else "sk_red")
    # twin banded chimneys, south-east
    for (cx, cz) in ((49, 21), (53, 21)):
        for x in range(cx - 1, cx + 3):
            for z in range(cz - 1, cz + 3):
                for y in (1, 2): S(x, y, z, "sk_conc")
        for y in range(3, 46):
            for dx in (0, 1):
                for dz in (0, 1): S(cx + dx, y, cz + dz, "sk_core" if y >= 44 else ("sk_white" if (y // 4) % 2 else "sk_grey"))
    # ---- ground: forecourt, road, hedges, trees, street lights
    for x in range(17, 29):
        for z in range(31, 36): S(x, 0, z, "sk_pave")
    for x in range(-12, 60):
        for z in (37, 38, 39): S(x, 0, z, "sk_line" if (z == 38 and x % 4 < 2) else "sk_road")
    for z in range(-6, 37):
        for x in (57, 58, 59): S(x, 0, z, "sk_line" if (x == 58 and z % 4 < 2) else "sk_road")
    for x in list(range(-1, 17)) + list(range(29, 47)):
        S(x, 1, 34, "sk_hedge")
    for z in range(-1, 31):
        if not (8 <= z <= 24): S(-8, 1, z, "sk_hedge")
    for (tx, tz) in ((-6, 41), (6, 41), (18, 41), (30, 41), (42, 41), (54, 41), (-10, 30), (-10, 2), (61, 30), (61, 5)):
        for y in range(1, 4): S(tx, y, tz, "sk_log")
        for dx in (-1, 0, 1):
            for dz in (-1, 0, 1):
                for y in (4, 5): S(tx + dx, y, tz + dz, "sk_leaf")
        S(tx, 6, tz, "sk_leaf")
    for x in range(-8, 58, 10): S(x, 1, 36, "sk_lamp")
    # ---- the lookout: a dark glass box out of the west face over the hangar door
    for x in range(-5, 0):
        for z in range(12, 21):
            for y in range(9, 13):
                edge = x == -5 or z in (12, 20)
                if y == 9 or y == 12: S(x, y, z, "sk_conc" if (edge or y == 12) else "sk_pod")
                elif edge: S(x, y, z, "sk_conc" if (x == -5 and z in (12, 20)) else "sk_pod")

ZONES = [
 dict(id="gate", name="Blast gate", cam=[22.5, 2, 31], h=5.5, ph="A",
      text="A four-wide sliding gate at the south entrance, built as a Create contraption on a gantry with an electric motor. A computer with the Player Detector opens it for people on the list and says so on a screen; LOCKDOWN shuts it. Two guard turtles stand either side."),
 dict(id="launch", name="Launch bay", cam=[4.5, 2, 16], h=6.5, ph="B",
      text="The old furnace room becomes the drones' home. 40 bays in two rows down both walls, each with a light (green docked, amber out, red trouble). A hangar door in the west wall opens as a drone comes or goes. At the north end a counter takes in what they carry and hands out lava buckets; at the south end the departures board and a console. The 12 vanilla furnaces go: their smelting moves to the ME smelters first."),
 dict(id="bridge", name="The Bridge", cam=[4, 10, 15], h=13.5, ph="B",
      text="The control room, upstairs over the launch bay. One wall is the map: 13 by 4 monitors showing the land in real map colours with every drone as a moving dot. A row of consoles with levers that do things, and a glass floor to look straight down on the bays. Turn on the upper deck to see it."),
 dict(id="deck", name="Logistics deck", cam=[18, 10, 15], h=13.5, ph="B",
      text="Create 6 logistics on floor 2, beside the Bridge. A stock ticker where you ask for anything; packagers on the ME interfaces box it; frogports throw the box onto a chain conveyor that runs overhead round the deck and on into the hall. Display boards show stock and what is moving. Redstone requesters are levers that order a set load. Drones hand in at the launch bay, their load is boxed and comes up the same way."),
 dict(id="engine", name="Engine floor", cam=[16, 16, 14], h=19.5, ph="F",
      text="Floor 3 is a Create steam plant. Two boilers on blaze burners sit right under the twin red stacks on the roof (the stacks are their flues). Steam engines turn a shaft line with large cogwheels; a drive shaft runs down through the building to the gate, the lift, the hall crane and the belts. A mechanical crafter wall at the west end."),
 dict(id="hall", name="Foundry hall", cam=[36, 1, 15], h=6.5, ph="C",
      text="The AE2 and Mekanism hall, running, under the green roof. Red steel columns at the walls, a Create gantry crane running the length of the hall under the skylights, and the chain conveyor coming in from the deck to a frogport over the ore line. A tinted glass floor down the spine shows the cables."),
 dict(id="store", name="Storerooms", cam=[14, 1, 15], h=6.5, ph="C",
      text="The barrel rooms stay, now read and filled by ME. v2 adds category lighting over each zone and a requisition screen at each end."),
 dict(id="lane", name="Old rack", cam=[22, 1, 2], h=4.5, ph="E",
      text="The old lane and rack retire once the launch bay is running. The lane stays as a corridor; the rack comes out."),
 dict(id="outside", name="The outside", cam=[14, 10, 15], h=4, ph="F",
      text="After your picture. The west half rises to a four-storey concrete block with a strong grid: pilasters every three blocks and a band at every floor, standing a block proud, with dark windows set back and a few lit. Red trim on the parapet. The hall becomes a low podium: an arcade of deep piers on the south and east, a red band, and a green roof with rows of skylights."),
 dict(id="steel", name="Red steel", cam=[45, 20, 15], h=12, ph="F",
      text="The industrial side. A red steel lattice tower on the east over a dark furnace shaft, a red skip-bridge dropping from it onto the podium roof, a high red truss across to the main block, a red frame with twin red stacks on the main block's roof, and two tall grey-and-white banded chimneys. All red concrete, iron bars and polished deepslate."),
 dict(id="pod", name="Lookout", cam=[-3, 10, 16], h=5, ph="B",
      text="The Bridge pushes out of the west face as a dark glass box over the hangar door: watch the drones go out under your feet."),
 dict(id="grounds", name="Grounds", cam=[22, 1, 36], h=4, ph="E",
      text="A paved forecourt at the gate, a road along the south and east with lines and street lights, hedges along the front, trees along the road."),
 dict(id="guards", name="Guards", cam=[46, 1, 32], h=3.5, ph="D",
      text="Four melee turtles walk a ring round the building at night and two hold the gate. They strike hostile mobs only, stand down near players, and raise the alarm and the gate lights."),
 dict(id="yard", name="Apron", cam=[-5, 1, 16], h=3.5, ph="E",
      text="Where the old base stands: taken apart by the drones into the store, levelled, and laid as a marked apron in front of the hangar door. The ground round the factory is terraformed to match."),
]

MOVERS = [
    # (type, path of block points, loop?, speed b/s, how many, outdoors?, size)
    ("pkg", [(11, 12, 4), (25, 12, 4), (25, 12, 26), (11, 12, 26)], True, 2.0, 12, False, .62),       # deck chain loop
    ("pkg", [(27, 8, 20), (40, 8, 20), (40, 8, 13), (41, 7, 13)], False, 1.6, 4, False, .62),         # chain into the hall
    ("ore", [(29, 7.5, 8), (43, 7.5, 8), (43, 5, 8)], False, 1.4, 7, False, .45),                      # overhead ore belt
    ("ore", [(29, 7.5, 22), (39, 7.5, 22), (39, 5, 22)], False, 1.4, 6, False, .45),                   # overhead ore belt 2
    ("pkg", [(14, 9.5, 8), (26, 9.5, 8), (26, 12, 8), (25, 12, 4)], False, 1.6, 5, False, .5),          # sorting belt up to the chain
    ("pkg", [(14, 9.5, 22), (26, 9.5, 22), (26, 12, 22), (25, 12, 26)], False, 1.6, 5, False, .5),
    ("ore", [(25, 16.5, 25), (5, 16.5, 25)], False, 1.2, 9, False, .45),
    ("ore", [(5, 16.5, 20), (25, 16.5, 20)], False, 1.0, 10, False, .45),                               # engine floor processing belt
    ("pkg", [(48, 18, 12), (28, 18, 12)], False, 1.8, 6, True, .62),                                   # outside chain, tower -> main block
    ("pkg", [(35, 5, 15), (43, 5, 15), (35, 5, 15), (29, 5, 15)], True, 1.0, 1, False, .9),            # the crane's crate
    ("drone", [(1, 3, 16), (-8, 5, 16), (-16, 12, 10), (-22, 20, 0), (8, 27, -6), (40, 27, 2), (52, 31, 12),
               (40, 26, 30), (10, 22, 38), (-10, 10, 26), (-6, 4, 18)], True, 4.0, 3, True, .9),         # drones on the round
    ("drone", [(30, 6, 5), (40, 7, 6), (42, 6, 24), (31, 7, 26), (34, 6, 15)], True, 2.2, 2, False, .9),  # drones in the hall
    ("drone", [(8, 4, 9), (5, 4, 10), (4, 3, 16), (0, 3, 16), (-7, 4, 16)], False, 1.5, 1, False, .9),   # one leaving its bay
]

def page():
    A.B.clear(); A.LINKS.clear(); del A.NOTES[:]
    shell(); A.plan(); A.services(); v2(); v3()
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
    for (x, y, z), (ty, f) in SKIN.items():
        blocks.append([x, y, z, keys.index(ty), f, 8, -1, 0])
    rt = {}
    try:
        import realtex
        rt, bad = realtex.build(set(keys))
    except Exception as e:
        print("no real textures:", e)
    types = []
    for k in keys:
        d = dict(k=k, **T[k])
        if k in rt:
            d["rt"] = 1
            if d["t"] == "glass": d["a"] = 0.92
        types.append(d)
    mv = [dict(t=keys.index(ty) if ty in keys else 0, p=pts, loop=lp, v=sp, n=n, out=o, s=sz) for (ty, pts, lp, sp, n, o, sz) in MOVERS]
    data = dict(types=types, movers=mv, blocks=blocks, notes=A.NOTES, zones=ZONES, phases=[], bom={}, rt=rt)
    tpl = open(os.path.join(ROOT, "tools", "ae2plan_page.html")).read()
    book = open(os.path.join(ROOT, "tools", "factoryv2_book.js")).read()
    a, b = tpl.index("const TABS="), tpl.index("function show(")
    tpl = tpl[:a] + book + "\n" + tpl[b:]
    rep = [("<title>Foundry AE2 Plan</title>", "<title>Factory v2 Concept</title>"),
           ("<h1>Foundry AE2 Plan</h1>", "<h1>Factory v2 Concept</h1>"),
           ("The foundry hall as it would stand: your real walls and floor from tonight's scan, with the whole AE2 and Mekanism factory in it. The two walls nearest you are cut away. Drag to move, scroll to zoom, hover any block.",
            "The whole factory as it would look after the redesign: the new outside first. Press Outside to take the walls off and see in; pick a zone on the right to fly to it. Drag to move, scroll to zoom, hover any block. Nothing here is built until you say."),
           ('<div class="grp"><label for="ph">Build phase</label><input id="ph" type="range" min="0" max="8" value="8"><label id="phv">8 of 8</label></div>',
            '<div class="grp"><button id="t_out" aria-pressed="true">Outside</button><button id="t_up" aria-pressed="false">Floor: ground</button><input id="ph" type="hidden" value="8"><label id="phv" hidden></label></div>'),
           ('press("t_floor","floor");', 'press("t_out","out");press("t_floor","floor");const LV=["Floor: ground","Floor: Bridge deck","Floor: engine floor"],setLv=v=>{O.lvl=v;const e=document.getElementById("t_up");e.textContent=LV[v];e.setAttribute("aria-pressed",v>0)};document.getElementById("t_up").onclick=()=>{setLv(((O.lvl|0)+1)%3);redraw()};'),
           ('  case"slab":return[[0,0,0,16,8,16]];', '  case"slab":return[[0,0,0,16,8,16]];\n  case"bars":return f%2?[[7,0,0,9,16,16]]:[[0,0,7,16,16,9]];\n  case"chain":return f==2?[[7,0,7,9,16,9]]:f%2?[[7,7,0,9,9,16]]:[[0,7,7,16,9,9]];\n  case"beam":return f==2?[[5,0,5,11,16,11]]:f%2?[[5,5,0,11,11,16]]:[[0,5,5,16,11,11]];'),
           ("    const cat=t.cat;\n", "    const cat=t.cat;\n    if(cat==\"skin\"&&!O.out)continue;if(O.out&&cat!=\"skin\"&&SK.has(b[0]+\",\"+b[1]+\",\"+b[2]))continue;\n"),
           ("const V=Object.assign({},HOME),O={", "const SK=new Set(D.blocks.filter(b=>D.types[b[3]].cat==\"skin\").map(b=>b[0]+\",\"+b[1]+\",\"+b[2]));const V=Object.assign({},HOME),O={out:true,"),
           ("    if(b[5]>O.phase)continue;", "    if(b[5]>O.phase)continue;if(!O.out&&b[1]>=[6,15,99][O.lvl|0])continue;"),
           ("const TX=TY.map(", "let TX=TY.map("),
           ("// ---------------------------------------------------------------- shapes", "(function(){const R=D.rt||{},RO={};let n=0,tot=0;TY.forEach((t,i)=>{const r=R[t.k];if(!r)return;const o={};RO[i]=o;for(const f of[\"top\",\"side\",\"front\"]){tot++;const im=new Image();im.onload=()=>{const base=mk(g=>{g.imageSmoothingEnabled=false;g.drawImage(im,0,0,16,16)});o[f]={top:base,l:shaded(base,SH.l),r:shaded(base,SH.r)};if(++n==tot){for(const j in RO)TX[j]=RO[j];window.RTREADY=1;if(typeof redraw==\"function\")redraw()}};im.src=r[f]}})})();\n// ---------------------------------------------------------------- shapes"),
           ('const fx=(t.t=="machine"||', 'const fx=(t.rt||t.t=="machine"||'),
           ('fz=(t.t=="machine"||', 'fz=(t.rt||t.t=="machine"||'),
           ("        poly([P(x0,y1,z1),P(x1,y1,z1),P(x1,y0,z1),P(x0,y0,z1)],shade(col,SH.l));",
            "        if(t.rt&&window.RTREADY){const T3=TX[b[3]],w=q[3]-q[0],h=q[4]-q[1],d=q[5]-q[2];if(w>0&&h>0)fq(T3.side.l,q[0],16-q[4],w,h,P(x0,y1,z1),P(x1,y1,z1),P(x0,y0,z1));if(d>0&&h>0)fq(T3.side.r,16-q[5],16-q[4],d,h,P(x1,y1,z1),P(x1,y1,z0),P(x1,y0,z1));if(w>0&&d>0)fq(T3.top.top,q[0],q[2],w,d,P(x0,y1,z0),P(x1,y1,z0),P(x0,y1,z1));continue}\n        poly([P(x0,y1,z1),P(x1,y1,z1),P(x1,y0,z1),P(x0,y0,z1)],shade(col,SH.l));"),
           ("  const wd=d=>DIRS[d];", "  const wd=d=>DIRS[d];\n  function fq(img,sx,sy,sw,sh,o,pu,pv){const u0=pu[0]-o[0],u1=pu[1]-o[1],v0=pv[0]-o[0],v1=pv[1]-o[1];g.setTransform(z*u0/sw,z*u1/sw,z*v0/sh,z*v1/sh,ox+z*o[0],oy+z*o[1]);g.drawImage(img,sx,sy,sw,sh,-.05,-.05,sw+.1,sh+.1)}"),
           ("function redraw(){if(raf)return;raf=requestAnimationFrame(()=>{raf=0;last=drawScene(cv,D.blocks,V,O)})}",
            "function redraw(){if(raf)return;raf=requestAnimationFrame(()=>{raf=0;last=drawScene(cv,D.blocks,V,O);snap();movers()})}\n" + open(os.path.join(ROOT, "tools", "factoryv2_anim.js")).read()),
           ("const HOME={cx:36,cz:16.5,rot:0,zoom:1,px:0,py:0};", "const HOME={cx:24,cz:17,rot:0,zoom:1,px:0,py:90};"),
           ("Math.min(W/(30*HW*1.45),H/(30*HH*1.9))", "Math.min(W/(80*HW*1.05),H/(80*HH*2.1))"),
           ('zn.id=="core"?6.4:(zn.id=="garden"?5.4:(zn.id=="fuel"?2.4:3.3))', "(zn.h||3.3)"),
           ("const nr=d=>d==0?b[0]>=44:d==1?b[2]>=29:d==2?b[0]<=27:b[2]<=3,n=nr(XDIR[r])||nr(ZDIR[r]);",
            "const nr=d=>d==0?b[0]>=44:d==1?b[2]>=29:d==2?b[0]<=0:b[2]<=0,n=(nr(XDIR[r])||nr(ZDIR[r]))&&b[0]>=0&&b[0]<=46&&b[2]>=0&&b[2]<=31&&TY[b[3]].cat!=\"v2\"&&!O.out;"),
           ("if(n&&b[0]>=45&&b[1]>=1)a*=.3}", "}"),
           ('if(!O.mach&&(cat=="ae"||cat=="mek"||cat=="power"||cat=="lava")&&!(cat=="lava"))continue;',
            'if(!O.mach&&(cat=="ae"||cat=="mek"||cat=="power"||cat=="v2"))continue;'),
           ('if(id=="bay")requestAnimationFrame(minis);', ""),
           ("V.px=0;V.py=40;V.zoom=Math.max(HOME.zoom*2.2,2);", "V.px=0;V.zoom=Math.max(HOME.zoom*2.2,2);V.py=40+(zn.cam[1]-1)*BH*V.zoom;"),
           ('<button id="home">Whole hall</button>', '<button id="home">Whole factory</button>'),
           ('function focusZone(id){const zn=D.zones.find(z=>z.id==id);O.sel=id;',
            'function focusZone(id){const zn=D.zones.find(z=>z.id==id);O.sel=id;if(["bridge","pod","deck","hall"].includes(id))setLv(1);else if(id=="engine")setLv(2);else setLv(0);O.out=["outside","gate","guards","yard"].includes(id);document.getElementById("t_out").setAttribute("aria-pressed",O.out);')]
    for x, y in rep:
        assert tpl.count(x) == 1, x[:60]
        tpl = tpl.replace(x, y)
    html = tpl.replace("/*DATA*/null", json.dumps(data, separators=(",", ":")))
    open(os.path.join(ROOT, "docs", "factory-v2.html"), "w").write(html)
    return len(html), len(blocks)

if __name__ == "__main__":
    print(page())
