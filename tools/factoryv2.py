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
t("lamp", "Light strip", "minecraft:pearlescent_froglight", "v2", "#f3d9ff", "#ffffff", "lava")
t("cyan", "Light strip (cyan)", "minecraft:sea_lantern", "v2", "#bff3ee", "#ffffff", "lava")
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
t("hatch", "Hangar door leaf (Create sliding door)", "create:industrial_iron_block", "v2", "#3d4147", "#57e3c2", "stripe")

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
    for x in range(-2, 47):
        for z in (-2, 32):
            if (x, 0, z) not in A.B or A.B[(x, 0, z)][0] == "grass": put(x, 0, z, "path", 0, 8, "Patrol path: the guards walk this ring at night")
    for z in range(-2, 33):
        for x in (-2, 46):
            if (x, 0, z) not in A.B or A.B[(x, 0, z)][0] == "grass": put(x, 0, z, "path", 0, 8, "Patrol path")
    for (x, z) in ((-2, -2), (46, -2), (46, 32), (-2, 32)):
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
    for z in (4, 26):
        for x in range(2, 8): put(x, 12, z, "cyan", 0, 8, "Ceiling light strip")
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
 dict(id="guards", name="Guards", cam=[46, 1, 32], h=3.5, ph="D",
      text="Four melee turtles walk a ring round the building at night and two hold the gate. They strike hostile mobs only, stand down near players, and raise the alarm and the gate lights."),
 dict(id="yard", name="Apron", cam=[-5, 1, 16], h=3.5, ph="E",
      text="Where the old base stands: taken apart by the drones into the store, levelled, and laid as a marked apron in front of the hangar door. The ground round the factory is terraformed to match."),
]

def page():
    A.B.clear(); A.LINKS.clear(); del A.NOTES[:]
    shell(); A.plan(); A.services(); v2()
    for k in [k for k, v in A.B.items() if v[0] in ("evap", "ghost")]: del A.B[k]
    keys = list(T)
    blocks = []
    for (x, y, z), (ty, f, ph, ni) in A.B.items():
        m = 0
        if T[ty]["s"] == "pipe":
            for i, (dx, dy, dz) in enumerate(((1, 0, 0), (0, 0, 1), (-1, 0, 0), (0, 0, -1), (0, 1, 0), (0, -1, 0))):
                nb = (x + dx, y + dy, z + dz)
                if (nb in A.B and A.B[nb][0] == ty) or ((x, y, z), nb) in A.LINKS: m |= 1 << i
        blocks.append([x, y, z, keys.index(ty), f, min(ph, 8), ni, m])
    data = dict(types=[dict(k=k, **T[k]) for k in keys], blocks=blocks, notes=A.NOTES, zones=ZONES, phases=[], bom={})
    tpl = open(os.path.join(ROOT, "tools", "ae2plan_page.html")).read()
    book = open(os.path.join(ROOT, "tools", "factoryv2_book.js")).read()
    a, b = tpl.index("const TABS="), tpl.index("function show(")
    tpl = tpl[:a] + book + "\n" + tpl[b:]
    rep = [("<title>Foundry AE2 Plan</title>", "<title>Factory v2 Concept</title>"),
           ("<h1>Foundry AE2 Plan</h1>", "<h1>Factory v2 Concept</h1>"),
           ("The foundry hall as it would stand: your real walls and floor from tonight's scan, with the whole AE2 and Mekanism factory in it. The two walls nearest you are cut away. Drag to move, scroll to zoom, hover any block.",
            "The whole factory from the survey, with the redesign drawn in. A proposal to react to: nothing on this page is built until you say. Drag to move, scroll to zoom, hover any block."),
           ('<div class="grp"><label for="ph">Build phase</label><input id="ph" type="range" min="0" max="8" value="8"><label id="phv">8 of 8</label></div>',
            '<div class="grp"><button id="t_up" aria-pressed="false">Upper deck</button><input id="ph" type="hidden" value="8"><label id="phv" hidden></label></div>'),
           ('press("t_floor","floor");', 'press("t_up","upper");press("t_floor","floor");'),
           ("    if(b[5]>O.phase)continue;", "    if(b[5]>O.phase)continue;if(!O.upper&&b[1]>=6)continue;"),
           ("const HOME={cx:36,cz:16.5,rot:0,zoom:1,px:0,py:0};", "const HOME={cx:20,cz:15,rot:0,zoom:1,px:0,py:0};"),
           ("Math.min(W/(30*HW*1.45),H/(30*HH*1.9))", "Math.min(W/(62*HW*1.1),H/(62*HH*1.5))"),
           ('zn.id=="core"?6.4:(zn.id=="garden"?5.4:(zn.id=="fuel"?2.4:3.3))', "(zn.h||3.3)"),
           ("const nr=d=>d==0?b[0]>=44:d==1?b[2]>=29:d==2?b[0]<=27:b[2]<=3,n=nr(XDIR[r])||nr(ZDIR[r]);",
            "const nr=d=>d==0?b[0]>=44:d==1?b[2]>=29:d==2?b[0]<=0:b[2]<=0,n=(nr(XDIR[r])||nr(ZDIR[r]))&&b[0]>=0&&b[0]<=44&&b[2]>=0&&b[2]<=30&&TY[b[3]].cat!=\"v2\";"),
           ("if(n&&b[0]>=45&&b[1]>=1)a*=.3}", "}"),
           ('if(!O.mach&&(cat=="ae"||cat=="mek"||cat=="power"||cat=="lava")&&!(cat=="lava"))continue;',
            'if(!O.mach&&(cat=="ae"||cat=="mek"||cat=="power"||cat=="v2"))continue;'),
           ('if(id=="bay")requestAnimationFrame(minis);', ""),
           ("V.px=0;V.py=40;V.zoom=Math.max(HOME.zoom*2.2,2);", "V.px=0;V.zoom=Math.max(HOME.zoom*2.2,2);V.py=40+(zn.cam[1]-1)*BH*V.zoom;"),
           ('<button id="home">Whole hall</button>', '<button id="home">Whole factory</button>'),
           ('function focusZone(id){const zn=D.zones.find(z=>z.id==id);O.sel=id;',
            'function focusZone(id){const zn=D.zones.find(z=>z.id==id);O.sel=id;if(id=="bridge"&&!O.upper){O.upper=true;document.getElementById("t_up").setAttribute("aria-pressed","true")}')]
    for x, y in rep:
        assert tpl.count(x) == 1, x[:60]
        tpl = tpl.replace(x, y)
    html = tpl.replace("/*DATA*/null", json.dumps(data, separators=(",", ":")))
    open(os.path.join(ROOT, "docs", "factory-v2.html"), "w").write(html)
    return len(html), len(blocks)

if __name__ == "__main__":
    print(page())
