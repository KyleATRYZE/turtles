"""The foundry hall, redesigned (concept for Kyle): docs/foundry-v2.html.

    python3 tools/foundry2.py          writes the page
    python3 tools/foundry2.py check    the new layout against the walls, the lane and the doors

Building coordinates (corner -4448 71 1518; x east, z south). The hall is
x 28-43, z 4-29 inside its walls (x 27, x 44, z 30; the lane's screen at
z 3). Doors: west x 27 z 14-16 (from the launch bay), east x 44 z 24-26.
"Before" is the model (as fitted plus every plan on top); "after" is the
concept below, ground floor seen from above.
"""
import json
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import retrofit as R  # noqa: E402

X0, X1, Z0, Z1 = 26, 45, 1, 31

# ---------------------------------------------------------------- the look of things (texture-ish colours)
# key -> (label, base colour, speck colour)
LOOK = {
    "floor": ("Polished deepslate floor", "#4a4a50", "#56565d"),
    "bed": ("Machine bed (deepslate tiles)", "#3a3a40", "#2e2e33"),
    "aisle": ("Walkway (polished deepslate, copper inlay at the edges)", "#55555c", "#606068"),
    "inlay": ("Cut copper inlay", "#c0703e", "#a85f33"),
    "stripe": ("Lane floor (hazard stripes)", "#d6b83a", "#2b2b2b"),
    "wall": ("Stone brick wall", "#7c7c7c", "#6a6a6a"),
    "post": ("Polished deepslate post", "#48484d", "#3c3c41"),
    "glass": ("Window", "#bfe3ee", "#a8d4e2"),
    "bars": ("Iron bars", "#9fa4a9", "#7d8288"),
    "lamp": ("Lantern", "#f2b84b", "#c98f2a"),
    "copper": ("Rack home (copper pad)", "#c0703e", "#a85f33"),
    "bay": ("Rack shelf: bay modem", "#d8d8d8", "#9c9c9c"),
    "strip": ("Rack panel strip (monitors)", "#2b2f3a", "#4dabf7"),
    "door": ("Doorway", "#5f5f66", "#5f5f66"),
    # Mekanism (steel casing grey, each with its own trim colour)
    "m_dissolve": ("Chemical Dissolution Chamber", "#9aa3ad", "#e3c341"),
    "m_washer": ("Chemical Washer", "#9aa3ad", "#3fb6d6"),
    "m_crystal": ("Chemical Crystallizer", "#9aa3ad", "#2fa39a"),
    "m_inject": ("Chemical Injection Chamber", "#9aa3ad", "#6cbf4a"),
    "m_purify": ("Purification Chamber", "#9aa3ad", "#4f7fd6"),
    "m_crush": ("Crusher", "#9aa3ad", "#c94a3a"),
    "m_enrich": ("Enrichment Chamber", "#9aa3ad", "#3aa35a"),
    "m_smelt": ("Energized Smelter", "#9aa3ad", "#e07a2e"),
    "m_infuse": ("Metallurgic Infuser", "#9aa3ad", "#8b5fbf"),
    "m_separ": ("Electrolytic Separator", "#c9ced3", "#5aa0e0"),
    "m_oxid": ("Chemical Oxidizer", "#9aa3ad", "#d6a23a"),
    "m_cinf": ("Chemical Infuser", "#9aa3ad", "#c3d84a"),
    "m_rotary": ("Rotary Condensentrator", "#9aa3ad", "#7bc6e8"),
    "m_pump": ("Electric Pump (over a 2 x 2 pool in the floor)", "#9aa3ad", "#2f6fd0"),
    "m_tank": ("Chemical / fluid tank", "#b8bec4", "#6b7680"),
    "m_heat": ("Heat Generator", "#5b5f66", "#e0602e"),
    "m_gasgen": ("Gas-Burning Generator", "#5b5f66", "#e0e0e0"),
    "m_cube": ("Energy Cube", "#2f5fae", "#7ea8ee"),
    "m_line": ("Mekanism cable, transporter or tube (above the floor)", "#8a8f96", "#c0392b"),
    "m_sorter": ("Logistical Sorter", "#9aa3ad", "#555"),
    # AE2
    "a_ctrl": ("ME Controller", "#3c4a7a", "#7f9cff"),
    "a_drive": ("ME Drive", "#3a3d45", "#8fd0ff"),
    "a_cpu": ("Crafting CPU (storage and units)", "#d7dbe0", "#6fd3e8"),
    "a_asm": ("Molecular Assembler + Pattern Provider", "#cfd3d8", "#9b7fe0"),
    "a_insc": ("Inscriber", "#7a7f88", "#c9b3ff"),
    "a_charge": ("Charger", "#7a7f88", "#ffd75e"),
    "a_term": ("ME Terminal / Interface / Energy Acceptor", "#4b4f58", "#7ee0ff"),
    "a_bud": ("Flawed budding certus quartz", "#9ad1f0", "#d8f1ff"),
    "a_accel": ("Growth Accelerator", "#7f868f", "#9be36b"),
    "a_out": ("Barrel on the cable (certus out)", "#9a6b3e", "#7a5230"),
    # the rest
    "cc_pc": ("Works computer (flush in the floor)", "#c9c9c9", "#3fbf6a"),
    "lava": ("Lava unit: cauldron, pointed dripstone, block, lava (y 1-4)", "#3a3a40", "#ff7a1a"),
    "pillar": ("Certus pillar (stone bricks; growth accelerators later)", "#7c7c7c", "#9be36b"),
    "uc": ("Universal cable (power row)", "#5b5f66", "#c0392b"),
    "quartz": ("Quartz line (Create: wheel, fan wash, soul sand)", "#8b6b44", "#5aa9e6"),
    "water": ("Water", "#3f76e4", "#5a8cf0"),
    "bench": ("Workshop bench", "#9a6b3e", "#7a5230"),
    "chest": ("Chest", "#a8743a", "#7a5230"),
    "other": ("Other", "#8f8f8f", "#777"),
    "cable": ("Cable", "#c0392b", "#8a8f96"),
    "mek": ("Mekanism machine", "#9aa3ad", "#6b7680"),
}


def classify(it):
    """a block name from the model -> a LOOK key (for "before")"""
    n = it.split(":")[-1]
    if "budding" in n:
        return "a_bud"
    for k, w in (("dissolution", "m_dissolve"), ("washer", "m_washer"), ("crystallizer", "m_crystal"),
                 ("injection", "m_inject"), ("purification", "m_purify"), ("crusher", "m_crush"),
                 ("enrichment", "m_enrich"), ("energized_smelter", "m_smelt"), ("metallurgic", "m_infuse"),
                 ("electrolytic", "m_separ"), ("oxidizer", "m_oxid"), ("chemical_infuser", "m_cinf"),
                 ("rotary", "m_rotary"), ("electric_pump", "m_pump"), ("heat_generator", "m_heat"),
                 ("energy_cube", "m_cube"), ("logistical_sorter", "m_sorter"), ("tank", "m_tank")):
        if k in n:
            return w
    if it.startswith("mekanism") and any(t in n for t in ("cable", "transporter", "tube", "pipe")):
        return "m_line"
    if it.startswith("(Mekan") or it.startswith("mekanism"):
        return "mek"
    if it.startswith("(gas"):
        return "m_tank"
    if "striped" in n:
        return "stripe"
    if "glass" in n:
        return "glass"
    if "bars" in n:
        return "bars"
    if "lantern" in n:
        return "lamp"
    if "copper" in n:
        return "copper"
    if "chest" in n or "barrel" in n or "kept" in n:
        return "chest"
    if "water" in n and "wheel" not in n:
        return "water"
    if "wheel" in n or "fan" in n or "cobble" in n or "soul" in n:
        return "quartz"
    if "monitor" in n:
        return "strip"
    if "generator" in n:
        return "m_heat"
    if n.startswith("polished_deepslate"):
        return "post"
    if "brick" in n or "deepslate" in n:
        return "wall"
    if "cable" in n or "modem" in n:
        return "cable"
    return "other"


def before():
    """top-down: the highest thing at y 1-4, else the floor (y 0)"""
    B = R.model()
    out = {}
    for x in range(X0, X1 + 1):
        for z in range(Z0, Z1 + 1):
            top = None
            for y in (4, 3, 2, 1):
                if B.get((x, y, z)):
                    top = (y, B[(x, y, z)])
                    break
            if top:
                out[(x, z)] = (classify(top[1]), top[1].split(":")[-1], top[0])
            elif B.get((x, 0, z)):
                f = B[(x, 0, z)]
                k = "stripe" if "striped" in f else ("bed" if "bricks" in f else "floor")
                out[(x, z)] = (k, f.split(":")[-1], 0)
    return out


# ---------------------------------------------------------------- the concept
ZONES = [  # (key, label, x0, z0, x1, z1, colour, blurb)
    ("racks", "Racks 3 and 2 on the lane", 28, 3, 42, 4, "#c0703e",
     "Rack 3 (x 28-31: miners, BlockParty, the certus harvester), the hatch (x 32), rack 2 (x 35-42: loaders). Loading bays, panel strips behind."),
    ("ore", "Ore line (5x)", 42, 6, 43, 13, "#3aa35a",
     "Eight machines in one row on the east wall, each pushing into the next: dissolution, washer, crystallizer, injection, purification, crusher, enrichment, smelter. Ore goes in at the north end over the cable, ingots come out at the south end."),
    ("gas", "Gas plant", 37, 6, 38, 13, "#5aa0e0",
     "Facing the ore line across a 3-wide service walkway: two separators, oxidizer, three chemical infusers, condensentrator, pump on its pool; tanks behind. Gases cross under the walkway floor."),
    ("power", "Power", 42, 17, 43, 23, "#e0602e",
     "All the generators and cubes in one block on the east wall: four heat generators (both of today's; they burn lava too), a gas-burning one on spare hydrogen, two cubes. A power row of universal cable runs along the wall behind the ore line and the power block (x 43); the alloy cell has its own row behind it (x 38), joined under the east door's walkway."),
    ("lava", "Lava wall", 28, 28, 43, 29, "#ff7a1a",
     "Sixteen dripstone lava units along the south wall (cauldrons at z 29, the lava held at y 4 between the wall and a row of blocks over the walkway), harvested from the walkway at z 28 by a drone with empty buckets: fuel for the drones and the heat generators."),
    ("alloy", "Alloy cell", 38, 17, 40, 23, "#8b5fbf",
     "Two metallurgic infusers (steel, alloys, circuits), a bank of three smelters, a crusher, a second chamber: the works computer's make, smelt and enrich jobs."),
    ("certus", "Certus farm", 28, 5, 34, 13, "#9ad1f0",
     "The AE2 work's farm (tools/certusfarm.py): two stone pillars (x 30, z 7 and z 10, y 1-7) with budding certus against both sides in three tiers (9 of 12 slots), corridors at x 28 and x 32, the basin at 30 0 13. The harvester docks in rack 3 and comes in by the hatch; crystals go into a barrel on the cable at 34 1 13."),
    ("ae2", "AE2 room", 28, 17, 34, 23, "#7f9cff",
     "Controller, drives, crafting CPU, assemblers with pattern providers, four inscribers and the charger, next to the certus farm and the Mekanism power. Joins the store through the ME bridge."),
    ("quartz", "Quartz line", 28, 24, 34, 27, "#5aa9e6", "Today's sand to soul sand to quartz line, squared up in its own bay."),
    ("bench", "Workshop bench", 37, 27, 43, 27, "#9a6b3e", "Machine trials, by the east door."),
    ("aisles", "Walkways", 35, 5, 36, 29, "#9c9ca3",
     "A 2-wide spine from the racks to the south wall, a 3-wide cross aisle from the west door, and one to the east door. Nothing stands in them; the works computer sits flush in the floor where they cross."),
]


def after():
    """building (x, z) -> (LOOK key, label, y): the ground floor of the concept"""
    out = {}
    B = R.model()

    def put(x, z, key, label=None, y=1):
        out[(x, z)] = (key, label or LOOK[key][0], y)
    # the shell stays: walls, windows, posts, the lane and its screen
    for x in range(X0, X1 + 1):
        for z in range(Z0, Z1 + 1):
            inside = 28 <= x <= 43 and 4 <= z <= 29
            if inside:
                continue
            top = None
            for y in (4, 3, 2, 1):
                if B.get((x, y, z)):
                    top = (y, B[(x, y, z)])
                    break
            if top and not (z == 3 and 28 <= x <= 42):
                out[(x, z)] = (classify(top[1]), top[1].split(":")[-1], top[0])
            elif B.get((x, 0, z)):
                f = B[(x, 0, z)]
                out[(x, z)] = ("stripe" if "striped" in f else "floor", f.split(":")[-1], 0)
    # racks 3 and 2 (stage 6) and the hatch
    for x in list(range(28, 32)) + list(range(35, 43)):
        put(x, 3, "bay", "Rack home pair: copper pad, bay modem shelf, home above")
        put(x, 4, "strip", "Panel strip (y 2) between bars (y 1, y 3)")
    for x in (33, 34):
        put(x, 3, "post", "Screen post", 1)
    put(32, 3, "door", "The hatch onto the lane (stays open)", 0)
    for x in (32, 33, 34):
        put(x, 4, "aisle", "Walkway from the hatch", 0)
    # floor everywhere inside first
    for x in range(28, 44):
        for z in range(4, 30):
            if (x, z) not in out:
                put(x, z, "floor", None, 0)
    # walkways
    for x in range(28, 44):
        put(x, 5, "aisle", "North walkway (along the racks)", 0)
        put(x, 28, "aisle", "South walkway: the lava wall's harvest walkway (the lava's wall overhead at y 4)", 0)
        put(x, 29, "lava", "Lava unit (one of 16)")
        if x < 43:
            for z in (14, 15, 16):
                put(x, z, "aisle", "Cross aisle (from the west door)", 0)
    for z in range(5, 29):
        for x in (35, 36):
            put(x, z, "aisle", "The spine (racks to the south walkway)", 0)
    for x in range(37, 44):
        for z in (24, 25, 26):
            put(x, z, "aisle", "Aisle to the east door", 0)
    for z in range(6, 14):
        for x in (39, 40, 41):
            put(x, z, "aisle", "Service walkway (the ore line faces it)", 0)
    for z in range(17, 24):
        put(41, z, "aisle", "Service walkway", 0)
    for x in (35, 36):
        put(x, 4, "aisle", "Walkway", 0)
    put(35, 15, "cc_pc", "Works computer, flush in the floor where the walkways cross (cable under the floor)", 0)
    # the ore line (east wall, facing west), tanks behind it
    ore = ["m_dissolve", "m_washer", "m_crystal", "m_inject", "m_purify", "m_crush", "m_enrich", "m_smelt"]
    for i, k in enumerate(ore):
        put(42, 6 + i, k, LOOK[k][0] + (" (ore in here)" if i == 0 else " (ingots out here)" if i == 7 else ""))
        put(43, 6 + i, "uc", "Power row (universal cable) behind the ore line; gases come in from above, later")
    # the gas plant (facing east), tanks behind
    gas = [("m_separ", "Electrolytic Separator (brine: chlorine, hydrogen)"),
           ("m_separ", "Electrolytic Separator (water: oxygen, hydrogen)"), ("m_oxid", None),
           ("m_cinf", "Chemical Infuser (sulfur dioxide + oxygen)"), ("m_rotary", "Rotary Condensentrator (water vapour)"),
           ("m_cinf", "Chemical Infuser (sulfuric acid)"), ("m_cinf", "Chemical Infuser (hydrogen chloride)"),
           ("m_pump", None)]
    for i, (k, lab) in enumerate(gas):
        put(38, 6 + i, k, lab)
        put(37, 6 + i, "m_tank", ["Brine (from the evaporation tower)", "Hydrogen tank", "Sulfur in (barrel on the cable)",
                                  "Sulfur dioxide", "Sulfur trioxide", "Water vapour", "Chlorine", "Water"][i])
    put(37, 13, "water", "The pump's 2 x 2 pool (in the floor, under it and beside it)", 0)
    # power (east wall)
    put(42, 17, "m_cube", "Energy Cube (today's, turned to face the power row)")
    for z in (18, 19, 20, 21):
        put(42, z, "m_heat", "Heat Generator" + (" (today's, stays)" if z == 18 else " (from the piped line)" if z == 19 else ""))
    put(42, 22, "m_gasgen", None)
    put(42, 23, "m_cube", "Energy Cube (second)")
    for z in range(14, 24):
        put(43, z, "uc", "Power row (universal cable)")
    # the alloy cell: one row of machines on a bed, facing the service walkway (x 41)
    cell = [("m_infuse", "Metallurgic Infuser (today's, from the plinth): steel"),
            ("m_infuse", "Metallurgic Infuser: alloys, circuits"),
            ("m_smelt", "Energized Smelter (bank, today's from the plinth)"), ("m_smelt", "Energized Smelter (bank)"),
            ("m_smelt", "Energized Smelter (bank)"), ("m_crush", "Crusher (obsidian, dusts)"),
            ("m_enrich", "Enrichment Chamber (today's from the plinth): redstone, carbon, diamond")]
    for i, (k, lab) in enumerate(cell):
        put(39, 17 + i, k, lab)
        put(38, 17 + i, "uc", "The alloy cell's power row (universal cable)")
        put(40, 17 + i, "bed", "Machine bed", 0)
    # the certus farm (the AE2 work's: tools/certusfarm.py)
    import certusfarm as CF
    F = CF.Farm()
    for (x, y, z) in F.pillars():
        if y == 1:
            put(x, z, "pillar", None)
    for (_, i, t, sd) in F.filled():
        x, y, z = F.slot_cell(i, t, sd)
        if t == 0:
            put(x, z, "a_bud", "Flawed budding certus (Kyle places these: tiers at y 1, 4, 7)")
    for z in range(5, 14):
        for x in (28, 32):
            if (x, z) not in out or out[(x, z)][0] == "floor":
                put(x, z, "aisle", "Harvest corridor", 0)
    wcell, _ = F.basin()
    put(wcell[0], wcell[2], "water", "The farm's basin (one floor block of water)", 0)
    put(34, 13, "a_out", "Barrel on the cable: certus crystals and dust (Crafty and the ME bridge take them)")
    # the AE2 room
    for x in (29, 30, 31):
        for z in (18, 19, 20):
            put(x, z, "a_ctrl", "ME Controller (3 x 3)")
        for z in (22, 23):
            put(x, z, "a_cpu", None)
    for z in (18, 19):
        put(33, z, "a_drive", None)
    for z in (20, 21, 22, 23):
        put(33, z, "a_asm", None)
    for z in (18, 19, 20, 21):
        put(28, z, "a_insc", "Inscriber (" + ["silicon", "logic", "calculation", "engineering"][z - 18] + " press)")
    put(28, 22, "a_charge", None)
    put(34, 17, "a_term", "Energy Acceptor (on the Mekanism power)")
    put(34, 21, "a_term", "ME Bridge (CC sees AE2) and the terminal Kyle uses")
    # the quartz line (squared up) and the bench
    for x in range(29, 34):
        for z in range(24, 28):
            put(x, z, "quartz", "Quartz line (as built, squared up in this 5 x 4 bay)")
    for z in (25, 26):
        put(31, z, "water", "Quartz line: the wash", 1)
    for x in range(38, 43):
        put(x, 27, "bench", "Workshop bench (machine trials)")
    return out


def check():
    A = after()
    bad = []
    for z in (14, 15, 16):
        if A.get((28, z), ("",))[0] != "aisle":
            bad.append(f"the west door's way in is not open at z {z}")
    for z in (24, 25, 26):
        if A.get((43, z), ("",))[0] != "aisle":
            bad.append(f"the east door's way in is not open at z {z}")
    for z in range(5, 29):
        for x in (35, 36):
            if A[(x, z)][0] not in ("aisle", "cc_pc", "inlay"):
                bad.append(f"the spine is blocked at {x} {z}")
    # nothing of the concept on a wall cell
    B = R.model()
    for (x, z), (k, lab, y) in A.items():
        if 28 <= x <= 43 and 4 <= z <= 29 and y >= 1:
            for yy in (1, 2, 3):
                it = B.get((x, yy, z)) or ""
                if any(w in it for w in ("stone_bricks", "glass", "deepslate_tiles")) and x in (27, 44):
                    bad.append(f"{x} {z} is a wall")
    n = sum(1 for v in A.values() if v[2] >= 1 and v[0] not in ("wall", "post", "glass", "bars", "lamp", "stripe"))
    print("\n".join(bad) if bad else f"ok: {n} blocks placed in the concept; walkways and doors clear")
    return not bad


PAGE = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Foundry hall v2: a concept</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Big+Shoulders+Display:wght@600;800&family=IBM+Plex+Sans:wght@400;500;600&family=IBM+Plex+Mono:wght@400;500&display=swap" rel="stylesheet">
<style>
%%CSS%%
.plans { display: grid; grid-template-columns: repeat(auto-fit, minmax(420px, 1fr)); gap: 16px; }
.plan { position: relative; background: var(--panel); border: 1px solid var(--line); border-radius: 10px; overflow: auto; padding: 8px; }
.plan h3 { margin: 2px 4px 8px; font: 600 14px var(--mono); }
.plan canvas { display: block; }
.tip { position: absolute; pointer-events: none; font: 12px/1.4 var(--mono); background: var(--panel); color: var(--ink);
  border: 1px solid var(--line); border-radius: 6px; padding: 6px 8px; max-width: 320px; display: none; box-shadow: 0 2px 8px rgba(0,0,0,.15); z-index: 2; }
.toggles { display: flex; flex-wrap: wrap; gap: 8px; }
.key { list-style: none; display: grid; grid-template-columns: repeat(auto-fill, minmax(240px, 1fr)); gap: 6px 16px; padding: 0; margin: 0; font-size: 14px; }
.key li { display: flex; align-items: center; gap: 8px; }
.key i { width: 16px; height: 16px; border-radius: 3px; display: inline-block; border: 1px solid var(--line); flex: none; }
.cap { color: var(--muted); font-size: 14px; }
</style>
</head>
<body>
<main>
<header>
  <h1>Foundry hall v2</h1>
  <p class="lede">A concept for the foundry hall (x 28-43, z 4-29) as one tidy production floor: every machine in a row against a wall or in a bed, all services under the floor, a spine and two cross aisles that nothing stands in. For Kyle to approve before anything is drawn up in detail or built.</p>
  <div class="facts">
    <span class="chip">Ore line: 8 machines, toward 5x</span><span class="chip">Gas plant facing it</span>
    <span class="chip">Power in one block</span><span class="chip">Certus farm + AE2 room</span>
    <span class="chip">Quartz line and bench kept</span><span class="chip">Corner -4448, 71, 1518 · north up</span>
  </div>
</header>

<section aria-label="Plans">
  <div class="toggles">
    <button id="t-before" aria-pressed="true">Before</button>
    <button id="t-after" aria-pressed="true">After</button>
    <button id="t-zones" aria-pressed="true">Zone labels</button>
  </div>
  <div class="plans">
    <div class="plan" id="pb"><h3>Before: the hall as it is planned and fitted today</h3><canvas id="cb"></canvas><div class="tip"></div></div>
    <div class="plan" id="pa"><h3>After: the concept</h3><canvas id="ca"></canvas><div class="tip"></div></div>
  </div>
  <p class="cap">Ground floor seen from above, the highest block at walking height shown. North is up: the drone lane and the racks along the top, the west door from the launch bay on the left (z 14-16), the east door on the right (z 24-26). Hover a block for what it is and where.</p>
  <ul class="key" id="key"></ul>
</section>

<section aria-labelledby="why-h">
  <h2 id="why-h">Why this way</h2>
  <div class="rooms" id="zones"></div>
</section>

<section aria-labelledby="moves-h">
  <h2 id="moves-h">What moves where</h2>
  <div class="tablewrap"><table><thead><tr><th>today</th><th>where it is</th><th>goes to</th></tr></thead><tbody>%%MOVES%%</tbody></table></div>
  <p class="cap">Drones can break and place Mekanism machines (they keep their contents and settings); Kyle can too. Nothing is moved before Kyle approves the concept.</p>
</section>

<section aria-labelledby="rest-h">
  <h2 id="rest-h">The rest of the building</h2>
  %%REST%%
</section>
</main>
<script>
const LOOK = %%LOOK%%;
const BEFORE = %%BEFORE%%;
const AFTER = %%AFTER%%;
const ZONES = %%ZONES%%;
const X0 = %%X0%%, X1 = %%X1%%, Z0 = %%Z0%%, Z1 = %%Z1%%;
const O = [-4448, 71, 1518];
let on = { before: true, after: true, zones: true };
function rnd(seed) { let s = seed; return () => { s = (s * 16807) % 2147483647; return s / 2147483647; }; }
function draw(cv, data, zones) {
  const box = cv.parentElement;
  const nx = X1 - X0 + 1, nz = Z1 - Z0 + 1;
  const S = Math.max(12, Math.min(22, Math.floor((box.clientWidth - 40) / nx)));
  const L = 26, T = 16;
  const W = L + nx * S + 4, H = T + nz * S + 4;
  cv.width = W * devicePixelRatio; cv.height = H * devicePixelRatio; cv.style.width = W + 'px'; cv.style.height = H + 'px';
  const g = cv.getContext('2d'); g.setTransform(devicePixelRatio, 0, 0, devicePixelRatio, 0, 0);
  g.clearRect(0, 0, W, H);
  g.font = '10px IBM Plex Mono, monospace'; g.fillStyle = getComputedStyle(document.body).color;
  for (let x = X0; x <= X1; x++) if (x % 2 === 0) g.fillText(String(x), L + (x - X0) * S, 11);
  for (let z = Z0; z <= Z1; z++) if (z % 2 === 1) g.fillText(String(z), 2, T + (z - Z0) * S + S * 0.75);
  for (const [k, c] of Object.entries(data)) {
    const [x, z] = k.split(',').map(Number);
    const [key, label, y] = c;
    const look = LOOK[key] || LOOK.other;
    const px = L + (x - X0) * S, pz = T + (z - Z0) * S;
    g.fillStyle = look[1]; g.fillRect(px, pz, S, S);
    const r = rnd(x * 7919 + z * 104729 + 13);
    g.fillStyle = look[2];
    const isMachine = key.startsWith('m_') || key.startsWith('a_') || key === 'cc_pc';
    if (isMachine) {                    // a machine: a casing frame and a coloured face
      g.fillRect(px + S * 0.25, pz + S * 0.25, S * 0.5, S * 0.5);
      g.strokeStyle = 'rgba(0,0,0,.45)'; g.lineWidth = 1; g.strokeRect(px + 1.5, pz + 1.5, S - 3, S - 3);
    } else if (key === 'stripe') {
      for (let i = -S; i < S; i += 6) { g.beginPath(); g.moveTo(px + i, pz + S); g.lineTo(px + i + S, pz); g.lineWidth = 2; g.strokeStyle = look[2]; g.stroke(); }
    } else {                            // texture specks
      for (let i = 0; i < 5; i++) g.fillRect(px + Math.floor(r() * (S - 3)), pz + Math.floor(r() * (S - 3)), 3, 3);
    }
    if (y >= 1 && !isMachine) { g.strokeStyle = 'rgba(0,0,0,.25)'; g.strokeRect(px + .5, pz + .5, S - 1, S - 1); }
  }
  g.save(); g.beginPath(); g.rect(L, T, nx * S, nz * S); g.clip();
  g.restore();
  if (zones && on.zones) {
    g.font = '600 11px IBM Plex Sans, sans-serif';
    for (const zz of zones) {
      const [, label, x0, z0, x1, z1, colour] = zz;
      const px = L + (x0 - X0) * S, pz = T + (z0 - Z0) * S, w = (x1 - x0 + 1) * S, h = (z1 - z0 + 1) * S;
      g.strokeStyle = colour; g.lineWidth = 2; g.setLineDash([5, 3]); g.strokeRect(px + 1, pz + 1, w - 2, h - 2); g.setLineDash([]);
      const tw = g.measureText(label).width + 8;
      g.fillStyle = 'rgba(20,20,24,.78)'; g.fillRect(px + 3, pz + 3, Math.min(tw, w - 6), 16);
      g.fillStyle = '#fff'; g.fillText(label, px + 7, pz + 15, w - 12);
    }
  }
  const tip = box.querySelector('.tip');
  cv.onmousemove = e => {
    const rr = cv.getBoundingClientRect();
    const x = X0 + Math.floor((e.clientX - rr.left - L) / S), z = Z0 + Math.floor((e.clientY - rr.top - T) / S);
    const c = data[x + ',' + z];
    if (!c) { tip.style.display = 'none'; return; }
    tip.innerHTML = '<b>' + (O[0] + x) + ' ' + (O[1] + Math.max(1, c[2])) + ' ' + (O[2] + z) + '</b> <span style="opacity:.7">(building ' + x + ' ' + c[2] + ' ' + z + ')</span><br>' + c[1];
    tip.style.display = 'block';
    tip.style.left = Math.min(e.clientX - rr.left + 14, box.clientWidth - 260) + 'px'; tip.style.top = (e.clientY - rr.top + 30) + 'px';
  };
  cv.onmouseleave = () => { tip.style.display = 'none'; };
}
function drawAll() {
  document.getElementById('pb').style.display = on.before ? '' : 'none';
  document.getElementById('pa').style.display = on.after ? '' : 'none';
  if (on.before) draw(document.getElementById('cb'), BEFORE, null);
  if (on.after) draw(document.getElementById('ca'), AFTER, ZONES);
}
for (const k of ['before', 'after', 'zones']) {
  const b = document.getElementById('t-' + k);
  b.onclick = () => { on[k] = !on[k]; b.setAttribute('aria-pressed', String(on[k])); drawAll(); };
}
const used = new Set([...Object.values(AFTER), ...Object.values(BEFORE)].map(c => c[0]));
document.getElementById('key').innerHTML = Object.entries(LOOK).filter(([k]) => used.has(k))
  .map(([k, v]) => '<li><i style="background:linear-gradient(135deg,' + v[1] + ' 60%,' + v[2] + ' 60%)"></i>' + v[0] + '</li>').join('');
document.getElementById('zones').innerHTML = ZONES.map(z => '<div class="room" style="border-top-color:' + z[6] + '"><h3>' + z[1] +
  ' <span class="size">x ' + z[2] + '-' + z[4] + ', z ' + z[3] + '-' + z[5] + '</span></h3><p>' + z[7] + '</p></div>').join('');
addEventListener('resize', drawAll);
drawAll();
</script>
</body>
</html>
"""

MOVES = [
    ("Energized Smelter (DropIt's plinth)", "41 1 11", "the alloy cell's smelter bank, 39 1 19"),
    ("Energy Cube, Heat Generator (plinth)", "42 1 17, 42 1 18", "stay where they are, turned to face the power row (x 43)"),
    ("Enrichment Chamber (plinth)", "41 1 12", "the alloy cell, 39 1 23 (redstone, carbon, diamond)"),
    ("Metallurgic Infuser (plinth)", "41 1 15", "the alloy cell, 39 1 17 (steel)"),
    ("Universal cable along the plinth", "42 1 7..16", "taken up: power runs under the floor"),
    ("Sticky's piped line: inbox chest (in the walkway)", "36 1 9", "emptied into the store, taken up"),
    ("Logistical sorter and transporters", "36 1 10..16", "taken up (the works computer feeds by cable)"),
    ("Enrichment Chamber, Energized Smelter (piped line)", "36 1 17, 36 1 18", "the ore line, 42 1 12 and 42 1 13"),
    ("Outbox chest, cable, heat generator (piped line)", "36 1 19..21", "chest emptied and up; the generator to the power block, 42 1 19"),
    ("Planned stages 3-5 of the piped line (injection, purification, crusher, separator, pool, gas plants)", "x 29-37 z 11-21",
     "not built there: the ore line and gas plant instead"),
    ("Bench leftovers, coal generator, kept chests", "x 32-35 z 22-26", "emptied into the store; the bench goes to 38-42 27"),
    ("Quartz line", "x 28-35 z 22-27", "the same machines, squared up in x 29-33 z 24-27"),
    ("Power corner (planned)", "x 29-33 z 5-7", "not built: the certus farm is there; power on the east wall"),
    ("AE2 corner (planned, smelting hall)", "x 5-8 z 18-28", "moves here, next to the certus farm and the power: the hall's corner stays free"),
]

REST = """<div class="rooms">
<div class="room"><h3>Smelting hall <span class="size">x 1-8</span></h3><p>Crafty's bench and 12 furnaces stay. With AE2 moved into the foundry, the planned AE2 corner (x 5-8, z 18-28) is free: room for an induction smelter or more furnaces later.</p></div>
<div class="room"><h3>Launch bay <span class="size">x 19-26</span></h3><p>Now the pads are gone it is the way in from the big door and rack 1's room. Kept clear; the bay panel and the rack's panels are its screens.</p></div>
<div class="room"><h3>Storage room <span class="size">x 10-17</span></h3><p>Unchanged (the 4th barrel row of stage 3).</p></div>
<div class="room"><h3>East yard <span class="size">x 46-49</span></h3><p>The evaporation tower for brine, piped in through the east wall high (y 4) straight to the gas plant's brine tank.</p></div>
</div>"""


def write():
    src = open(os.path.join(ROOT, "docs", "factory-plan.html"), encoding="utf-8").read()
    css = src[src.index("<style>") + 7:src.index("</style>")]
    css = css[:css.index("/* the model */")] + css[css.index("/* rooms */"):]
    enc = lambda d: {f"{x},{z}": list(v) for (x, z), v in d.items()}
    moves = "".join(f"<tr><td>{a}</td><td class=\"num\">{b}</td><td>{c}</td></tr>" for a, b, c in MOVES)
    html = (PAGE.replace("%%CSS%%", css.strip()).replace("%%LOOK%%", json.dumps(LOOK))
            .replace("%%BEFORE%%", json.dumps(enc(before()), separators=(",", ":")))
            .replace("%%AFTER%%", json.dumps(enc(after()), separators=(",", ":")))
            .replace("%%ZONES%%", json.dumps(ZONES)).replace("%%MOVES%%", moves).replace("%%REST%%", REST)
            .replace("%%X0%%", str(X0)).replace("%%X1%%", str(X1)).replace("%%Z0%%", str(Z0)).replace("%%Z1%%", str(Z1)))
    out = os.path.join(ROOT, "docs", "foundry-v2.html")
    with open(out, "w", encoding="utf-8") as f:
        f.write(html)
    return out, len(html)


if __name__ == "__main__":
    if sys.argv[1:] == ["check"]:
        sys.exit(0 if check() else 1)
    print("wrote %s (%d bytes)" % write())
    check()
