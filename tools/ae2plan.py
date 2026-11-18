#!/usr/bin/env python3
"""The AE2 factory plan for the foundry hall (docs/ae2-factory.md).

Builds the block model (building coordinates: world = -4448+x, 71+y, 1518+z)
from the last survey's shell plus the plan, checks it, and writes
docs/ae2-factory.html (the voxel viewer) from tools/ae2plan_page.html.

    python3 tools/ae2plan.py            check, write the page
    python3 tools/ae2plan.py bom        bill of materials by phase
"""
import json, os, sys
from collections import Counter, OrderedDict
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ------------------------------------------------------------------ types
# key: (display name, registry id, category, colour, accent, texture, shape, alpha)
T = OrderedDict()
def t(key, name, rid, cat, c, c2=None, tex="noise", shape="cube", a=1.0):
    T[key] = dict(n=name, id=rid, cat=cat, c=c, c2=c2 or c, t=tex, s=shape, a=a)

# the building
t("pd", "Polished deepslate", "minecraft:polished_deepslate", "build", "#4b4b52", "#3c3c42", "tiles")
t("dt", "Deepslate tiles", "minecraft:deepslate_tiles", "build", "#37373c", "#2a2a2e", "bricks")
t("db", "Deepslate bricks", "minecraft:deepslate_bricks", "build", "#45454a", "#303034", "bricks")
t("sb", "Stone bricks", "minecraft:stone_bricks", "build", "#7d7d7d", "#646464", "bricks")
t("cob", "Cobblestone", "minecraft:cobblestone", "build", "#7a7a7a", "#5c5c5c", "noise")
t("gl", "Glass", "minecraft:glass", "build", "#bfe3ee", "#ffffff", "glass", a=0.28)
t("stripe", "Striped concrete", "chipped:striped_yellow_concrete", "build", "#d4b23a", "#2b2b2b", "stripe")
t("grass", "Grass", "minecraft:grass_block", "build", "#6aa84f", "#5a9443", "noise")
t("cauld", "Lava cauldron", "minecraft:lava_cauldron", "lava", "#3a3a3e", "#e8731c", "cauldron")
t("drip", "Pointed dripstone", "minecraft:pointed_dripstone", "lava", "#8b6b56", "#73573f", "noise", "drip")
t("lava", "Lava", "minecraft:lava", "lava", "#e8731c", "#ffc233", "lava")
t("water", "Water", "minecraft:water", "pipe", "#3f76e4", "#6d9bf0", "lava", a=0.7)
t("cap", "Chase cap (deepslate tile slab)", "minecraft:deepslate_tile_slab", "build", "#37373c", "#2a2a2e", "bricks", "slab")
t("cc", "CC cable (existing)", "computercraft:cable", "pipe_cc", "#8a8a8a", "#c0392b", "flat", "pipe")
t("pc", "Works computer", "computercraft:computer_normal", "ae", "#b8b8b8", "#2e7d32", "machine")

# AE2 and add-ons
t("ctrl", "ME Controller", "ae2:controller", "ae", "#3b3550", "#b37bff", "controller")
t("exdrive", "Extended ME Drive (20 cells)", "extendedae:ex_drive", "ae", "#55565c", "#57e3c2", "drive")
t("dcell", "Dense Energy Cell", "ae2:dense_energy_cell", "ae", "#4a4b52", "#ffb84a", "cell")
t("prov", "Pattern Provider + Induction Card", "ae2:pattern_provider", "ae", "#6b6d77", "#8fd3ff", "provider")
t("exprov", "Extended Pattern Provider (36 patterns)", "extendedae:ex_pattern_provider", "ae", "#6b6d77", "#ffd76b", "provider")
t("facc", "Flux Accessor", "appflux:flux_accessor", "ae", "#5a5c66", "#ff5f5f", "provider")
t("insc", "Inscriber", "ae2:inscriber", "ae", "#7b7d86", "#4a4c55", "machine")
t("chg", "Charger", "ae2:charger", "ae", "#7b7d86", "#9be8ff", "machine")
t("exinsc", "Extended Inscriber (4 presses)", "extendedae:ex_inscriber", "ae", "#7b7d86", "#ffd76b", "machine")
t("exchg", "Extended Charger", "extendedae:ex_charger", "ae", "#7b7d86", "#9be8ff", "machine")
t("cryasm", "Crystal Assembler", "extendedae:crystal_assembler", "ae", "#70727c", "#c08bff", "machine")
t("react", "Reaction Chamber", "advanced_ae:reaction_chamber", "ae", "#5b5d68", "#59ffa8", "machine")
t("cutter", "Circuit Cutter", "extendedae:circuit_cutter", "ae", "#70727c", "#ff9c4a", "machine")
t("bud", "Flawed Budding Certus Quartz", "ae2:flawed_budding_quartz", "ae", "#a9d8ee", "#e6f7ff", "crystal")
t("clus", "Certus Quartz Cluster", "ae2:quartz_cluster", "ae", "#cfefff", "#ffffff", "flat", "cluster", 0.9)
t("accel", "Growth Accelerator", "ae2:growth_accelerator", "ae", "#5d5f69", "#c08bff", "machine")
t("fixer", "Crystal Fixer", "extendedae:crystal_fixer", "ae", "#666872", "#59ffa8", "machine")
t("plane", "Annihilation Plane (on cable)", "ae2:annihilation_plane", "ae", "#8d8f99", "#b37bff", "flat", "plane")
t("sky", "Sky stone block", "ae2:sky_stone_block", "build", "#2f3033", "#232427", "noise")
t("qglass", "Quartz glass", "ae2:quartz_glass", "build", "#dff3fb", "#ffffff", "glass", a=0.22)
t("cpu_s", "Crafting Storage (64k)", "ae2:64k_crafting_storage", "ae", "#4c4e58", "#57e3c2", "cpu")
t("cpu_a", "Crafting Co-Processing Unit", "ae2:crafting_accelerator", "ae", "#4c4e58", "#ff9c4a", "cpu")
t("cpu_m", "Crafting Monitor", "ae2:crafting_monitor", "ae", "#4c4e58", "#8fd3ff", "cpu")
t("mxf", "Assembler Matrix frame", "extendedae:assembler_matrix_frame", "ae", "#3f414b", "#57e3c2", "frame")
t("mxg", "Assembler Matrix glass", "extendedae:assembler_matrix_glass", "ae", "#bfe3ee", "#ffffff", "glass", a=0.25)
t("mxp", "Matrix Pattern Core (36 patterns)", "extendedae:assembler_matrix_pattern", "ae", "#57586a", "#ffd76b", "cell")
t("mxc", "Matrix Crafter Core", "extendedae:assembler_matrix_crafter", "ae", "#57586a", "#57e3c2", "cell")
t("mxs", "Matrix Speed Core", "extendedae:assembler_matrix_speed", "ae", "#57586a", "#ff5f5f", "cell")
t("term_c", "Crafting Terminal", "ae2:crafting_terminal", "ae", "#2f3033", "#8fd3ff", "terminal")
t("term_p", "Pattern Encoding Terminal", "ae2:pattern_encoding_terminal", "ae", "#2f3033", "#ffd76b", "terminal")
t("term_a", "Pattern Access Terminal", "ae2:pattern_access_terminal", "ae", "#2f3033", "#59ffa8", "terminal")
t("req", "ME Requester (keeps stock)", "merequester:requester", "ae", "#5b5d68", "#ff9c4a", "machine")
t("cond", "Matter Condenser (junk void)", "ae2:condenser", "ae", "#3f414b", "#b37bff", "machine")
t("wap", "Wireless Access Point", "ae2:wireless_access_point", "ae", "#8d8f99", "#b37bff", "flat", "post")
t("wcon", "ME Wireless Connector (to the storeroom)", "extendedae:wireless_connect", "ae", "#5b5d68", "#57e3c2", "machine")
t("bridge", "ME Bridge (the swarm's door into ME)", "advancedperipherals:me_bridge", "ae", "#6a6c76", "#c0392b", "machine")
t("iface", "ME Interface (lava in)", "ae2:interface", "ae", "#6b6d77", "#e8731c", "provider")
t("caner", "ME Canner (fills lava buckets)", "extendedae:caner", "ae", "#70727c", "#e8731c", "machine")
t("feed", "Export Bus feed (in the floor, faces up)", "ae2:export_bus", "ae", "#8d8f99", "#ffd76b", "flat", "plane")

# Mekanism
def mek(key, name, rid, acc): t(key, name, rid, "mek", "#9a9ca3", acc, "machine")
mek("inf", "Metallurgic Infuser", "mekanism:metallurgic_infuser", "#c0392b")
mek("smelt", "Energized Smelter", "mekanism:energized_smelter", "#ff9c4a")
mek("enrich", "Enrichment Chamber", "mekanism:enrichment_chamber", "#59c1ff")
mek("crush", "Crusher", "mekanism:crusher", "#b8b8b8")
mek("ocomp", "Osmium Compressor", "mekanism:osmium_compressor", "#7fd6e8")
mek("comb", "Combiner", "mekanism:combiner", "#c08bff")
mek("purif", "Purification Chamber (3x)", "mekanism:purification_chamber", "#8fe0ff")
mek("inject", "Chemical Injection Chamber (4x)", "mekanism:chemical_injection_chamber", "#d7e85a")
mek("cryst", "Chemical Crystallizer (5x)", "mekanism:chemical_crystallizer", "#f2f2f2")
mek("wash", "Chemical Washer (5x)", "mekanism:chemical_washer", "#3f76e4")
mek("dissol", "Chemical Dissolution Chamber (5x)", "mekanism:chemical_dissolution_chamber", "#f0c23a")
mek("rotary", "Rotary Condensentrator", "mekanism:rotary_condensentrator", "#6d9bf0")
mek("cinf", "Chemical Infuser", "mekanism:chemical_infuser", "#59ffa8")
mek("oxid", "Chemical Oxidizer", "mekanism:chemical_oxidizer", "#f0e05a")
mek("sep", "Electrolytic Separator", "mekanism:electrolytic_separator", "#59c1ff")
mek("prc", "Pressurized Reaction Chamber", "mekanism:pressurized_reaction_chamber", "#ff5f5f")
t("ctank", "Chemical Tank (oxygen buffer)", "mekanism:basic_chemical_tank", "mek", "#b9bbc2", "#8fe0ff", "tank")
t("sink", "Kitchen sink (endless water)", "cookingforblockheads:sink", "mek", "#d9d9d9", "#3f76e4", "machine")
t("evap", "Thermal Evaporation tower (brine)", "mekanism:thermal_evaporation_block", "mek", "#8a6a3a", "#c9a35a", "frame")
t("qe", "Quantum Entangloporter (lava from the Nether)", "mekanism:quantum_entangloporter", "mek", "#5b5d68", "#b37bff", "cell")
t("ghost", "Reserved: reactor pad", "bigreactors:basic_reactorcasing", "power", "#d9c24a", "#b39b2e", "frame", a=0.35)

# power
t("thermo", "Nitro Thermo Generator (1,750 FE/t measured)", "powah:thermo_generator_nitro", "power", "#2c2d33", "#ff5f5f", "machine")

# services under the floor
def pipe(key, name, rid, cat, c): t(key, name, rid, cat, c, c, "flat", "pipe")
pipe("me_n", "ME dense cable: trunk N (lab, garden, vault, bridge)", "ae2:blue_smart_dense_cable", "pipe_me", "#5aa0ff")
pipe("me_w", "ME dense cable: trunk W (press, CPUs, desk, matrix)", "ae2:green_smart_dense_cable", "pipe_me", "#5fd17a")
pipe("me_a", "ME dense cable: trunk A (alloy row)", "ae2:orange_smart_dense_cable", "pipe_me", "#ff9c4a")
pipe("me_o", "ME dense cable: trunk O (ore line, power)", "ae2:purple_smart_dense_cable", "pipe_me", "#b37bff")
pipe("pw", "Power: Pipez universal pipe (FE, and water in the chase)", "pipez:universal_pipe", "pipe_pw", "#ff5f5f")
pipe("uc", "Power: Mekanism universal cable", "mekanism:basic_universal_cable", "pipe_pw", "#e0453a")
pipe("p_water", "Water: mechanical pipe", "mekanism:basic_mechanical_pipe", "pipe_ch", "#3f76e4")
pipe("p_brine", "Brine: mechanical pipe", "mekanism:basic_mechanical_pipe", "pipe_ch", "#c9a35a")
pipe("p_o2", "Oxygen: pressurized tube (light blue)", "mekanism:basic_pressurized_tube", "pipe_ch", "#8fe0ff")
pipe("p_hcl", "Hydrogen chloride: pressurized tube (lime)", "mekanism:basic_pressurized_tube", "pipe_ch", "#b5e61d")
pipe("p_acid", "Sulfuric acid: pressurized tube (yellow)", "mekanism:basic_pressurized_tube", "pipe_ch", "#f0c23a")

SURVEY = {"minecraft:polished_deepslate": "pd", "minecraft:deepslate_tiles": "dt", "minecraft:deepslate_bricks": "db",
          "minecraft:stone_bricks": "sb", "minecraft:cracked_stone_bricks": "sb", "minecraft:cobblestone": "cob",
          "minecraft:glass": "gl", "minecraft:glass_pane": "gl", "chipped:clear_leaded_glass_pane": "gl",
          "chipped:striped_yellow_concrete": "stripe", "minecraft:lava_cauldron": "cauld",
          "amendments:liquid_cauldron": "cauld", "minecraft:cauldron": "cauld", "minecraft:pointed_dripstone": "drip",
          "minecraft:lava": "lava"}

E, S, W, N = 0, 1, 2, 3
B = {}          # (x,y,z) -> [type, facing, phase, note]
LINKS = set()   # (pipe cell, device cell): a pipe arm into a device
NOTES = []

def put(x, y, z, ty, f=0, ph=1, note=None):
    assert ty in T, ty
    ni = -1
    if note:
        if note not in NOTES: NOTES.append(note)
        ni = NOTES.index(note)
    B[(x, y, z)] = [ty, f, ph, ni]

def run(net, pts, ph, note=None):
    """a pipe along axis-aligned waypoints"""
    for (a, b) in zip(pts, pts[1:]):
        d = [(b[i] > a[i]) - (b[i] < a[i]) for i in range(3)]
        assert sum(map(abs, d)) == 1, (a, b)
        c = list(a)
        while True:
            k = tuple(c)
            if k in B and B[k][0] != net and T[B[k][0]]["s"] == "pipe":
                raise SystemExit(f"pipes cross at {k}: {B[k][0]} and {net}")
            put(*k, net, 0, ph, note)
            if k == tuple(b): break
            for i in range(3): c[i] += d[i]

def link(pipe_cell, dev_cell): LINKS.add((tuple(pipe_cell), tuple(dev_cell)))

# ------------------------------------------------------------------ the shell, from the survey
def shell():
    w = json.load(open(os.path.join(ROOT, "data", "world.json")))["blocks"]
    for k, name in w.items():
        X, Y, Z = map(int, k.split(","))
        x, y, z = X + 4448, Y - 71, Z - 1518
        if not (26 <= x <= 45 and 2 <= z <= 31 and 0 <= y <= 5): continue
        inside = 28 <= x <= 43 and 4 <= z <= 28
        if inside and y >= 1: continue            # the hall's contents are the plan's
        ty = SURVEY.get(name)
        if ty: put(x, y, z, ty, 0, 0)
    for x in range(28, 44):                       # the floor, where the survey has a hole (a click hole, a machine)
        for z in range(4, 29):
            if (x, 0, z) not in B or B[(x, 0, z)][0] not in ("pd", "dt", "db"):
                put(x, 0, z, "pd", 0, 0)
    for x in range(45, 53):                       # the east yard
        for z in range(6, 26):
            put(x, 0, z, "grass", 0, 0)

# ------------------------------------------------------------------ the plan
def plan():
    # ---- the Core (south-west): controller line in the floor, tower over its middle
    for z in range(19, 24):
        put(31, 0, z, "ctrl", 0, 1, "Controller line, flush in the floor: each block's underside is a 32-channel port for one dense trunk")
    for y in range(1, 5):
        put(31, y, 21, "ctrl", 0, 1, "Controller tower (4 high): the room's centrepiece; one valid controller with the floor line")
    put(31, 5, 21, "wap", 0, 5, "Wireless Access Point: the Wireless Universal Terminal works anywhere near the base")
    # the vault: drives and energy cells, north wall of the core
    for x in range(29, 33):
        put(x, 1, 17, "exdrive", S, 1, "Vault: 4 extended drives = 80 cell slots (item, fluid, chemical and FE cells)")
        put(x, 2, 17, "dcell", S, 1, "1.6M AE each: rides out power dips and crafting spikes")
        put(x, 0, 17, "me_n", 0, 1)
    put(30, 3, 17, "wcon", S, 1, "Paired with a connector at the storeroom's two storage controllers: a storage bus on each makes every barrel visible to ME, no cable through the walls")
    # the desk, facing the spine aisle; a gap at z 21 to walk in
    desk = {18: ("term_c", "Crafting Terminal: everything in the store, and one-click crafting"),
            19: ("term_p", "Pattern Encoding Terminal: write patterns straight from JEI"),
            20: ("term_a", "Pattern Access Terminal: every provider's patterns from one screen"),
            22: ("req", "ME Requester: keeps set amounts in stock (steel, circuits, cable, turtles)"),
            23: ("req", "ME Requester: keeps lava buckets and charcoal in the barrels, so the docks always have fuel"),
            24: ("cond", "Matter Condenser: the void for junk (darkstone, kivi), by an export bus")}
    for z, (ty, note) in desk.items():
        put(33, 1, z, ty, E, 5 if ty == "req" else 1, note)
        put(33, 0, z, "me_w", 0, 1)
    # crafting CPUs against the west wall (the old bench is taken out: the lab's extended inscribers do its work)
    for z in range(18, 21):
        for y in range(1, 4):
            ty = "cpu_m" if (z, y) == (19, 2) else ("cpu_s" if y == 1 else "cpu_a")
            put(28, y, z, ty, E, 5, "CPU A (3x3): the big jobs. 3 x 64k storage, 5 co-processors")
    for z in range(22, 24):
        for y in range(1, 4):
            ty = "cpu_m" if (z, y) == (22, 2) else ("cpu_s" if y == 1 else "cpu_a")
            put(28, y, z, ty, E, 5, "CPU B (2x3): small jobs run beside the big one")
    put(28, 0, 19, "me_w", 0, 5); put(28, 0, 22, "me_w", 0, 5)
    # the assembler matrix
    for x in range(29, 34):
        for y in range(1, 6):
            for z in range(25, 28):
                ex = (x in (29, 33)) + (y in (1, 5)) + (z in (25, 27))
                if ex >= 2: put(x, y, z, "mxf", 0, 5, "Assembler Matrix (5x5x3): every crafting-table recipe, in one block of the room")
                elif ex == 1: put(x, y, z, "mxg", 0, 5)
                else:
                    ty = "mxp" if y == 2 else ("mxc" if y == 3 else "mxs")
                    put(x, y, z, ty, 0, 5, {"mxp": "Pattern cores: 3 x 36 = 108 crafting patterns",
                                             "mxc": "Crafter cores: 3 x 8 crafts at once",
                                             "mxs": "Speed cores"}[ty])
    put(30, 0, 26, "me_w", 0, 5)

    # ---- the crystal garden (north-west): a vitrine on the west wall
    for z in range(5, 12):
        if z % 2 == 0:
            put(29, 2, z, "bud", 0, 4, "Budding certus: clusters grow above and below, 4 crystals each")
            put(29, 3, z, "clus", 0, 4); put(29, 1, z, "clus", 1, 4)
            put(29, 4, z, "plane", 5, 4, "Annihilation plane in the lintel, facing down: breaks only full clusters")
            put(29, 0, z, "plane", 4, 4, "Annihilation plane in the floor, facing up")
            put(28, 2, z, "fixer", E, 4, "Crystal Fixer: keeps the budding block from wearing out (no more dead farm)")
        else:
            put(29, 2, z, "accel", 0, 4, "Growth Accelerator: each one touching a budding block speeds it up")
            put(29, 1, z, "sky", 0, 4); put(29, 0, z, "me_n", 0, 4)
            put(29, 4, z, "me_n", 0, 4); put(28, 2, z, "me_n", 0, 4)
        for y in (1, 2, 3):
            put(30, y, z, "qglass", 0, 4)
        put(30, 4, z, "sky", 0, 4); put(28, 4, z, "sky", 0, 4)
        put(28, 1, z, "sky", 0, 4); put(28, 3, z, "sky", 0, 4)
    for y in (1, 2, 3, 4):
        for x in (28, 29, 30):
            put(x, y, 4, "qglass" if y < 4 and x == 29 else "sky", 0, 4)
            put(x, y, 12, "qglass" if y < 4 and x == 29 else "sky", 0, 4)
    put(28, 3, 5, "me_n", 0, 4); put(28, 4, 5, "me_n", 0, 4)   # the lintel's riser, behind the frame

    # ---- the crystal lab: machines face the spine, providers behind
    lab = {7: ("exchg", "Extended Charger: charged certus in bulk"),
           8: ("cryasm", "Crystal Assembler: fluix and pure crystals without water puddles"),
           9: ("react", "Reaction Chamber: bulk fluix, quantum alloy, flawless budding recipes"),
           10: ("cutter", "Circuit Cutter: a block of gold, diamond or silicon into 9 printed circuits"),
           11: ("exinsc", "Extended Inscriber: the four presses in one block (the old bench comes out)"),
           12: ("exinsc", "Extended Inscriber: 4 assembly lines for processors")}
    for z, (ty, note) in lab.items():
        put(33, 1, z, ty, E, 4, note)
        put(32, 1, z, "exprov", W, 4, "Extended pattern provider behind the machine: items in, results back, power by its induction card")
        put(32, 0, z, "me_n", 0, 4)

    # ---- the alloy row (x 39, faces east), providers behind at x 38
    alloy = {17: ("inf", 0, "Infuser C (carbon): steel, enriched iron", "enriched carbon"),
             18: ("inf", 0, "Infuser R (redstone): control circuits, infused alloy", "enriched redstone"),
             19: ("smelt", 0, "Smelter bank 1 of 3: anything a furnace cooks", None),
             20: ("smelt", 0, "Smelter bank 2 of 3", None), 21: ("smelt", 0, "Smelter bank 3 of 3 (placed tonight)", None),
             22: ("crush", 0, "Crusher: ingots to dust, cobble to gravel to sand (placed tonight)", None),
             23: ("enrich", 0, "Enrichment Chamber: enriched carbon, redstone, diamond; ore doubling for anything", None),
             24: ("inf", 3, "Infuser D (diamond): reinforced alloy, refined obsidian dust", "enriched diamond"),
             25: ("inf", 3, "Infuser O (refined obsidian): atomic alloy", "enriched refined obsidian"),
             26: ("ocomp", 3, "Osmium Compressor: refined obsidian and glowstone ingots", "osmium ingots"),
             27: ("comb", 3, "Combiner: ores and blocks back from dust", "cobblestone")}
    for z, (ty, ph, note, feed) in alloy.items():
        put(39, 1, z, ty, E, ph, note + (" (already placed)" if ph == 0 else ""))
        put(38, 1, z, "prov", W, 3, "Pattern provider + induction card: one block gives the machine its items and its power")
        put(38, 0, z, "me_a", 0, 3)
        if feed:
            put(39, 0, z, "feed", 4, 3, f"Export bus in the floor under the machine: keeps its second slot full of {feed}")

    # ---- the ore line (x 42, faces west), providers behind at x 43
    ore = {6: ("dissol", 7, "5x: ore + sulfuric acid to dirty slurry (pushes it south, into the washer)"),
           7: ("wash", 7, "5x: slurry + water to clean slurry (pushes it south)"),
           8: ("cryst", 7, "5x: clean slurry to crystals"),
           9: ("inject", 7, "4x: crystals (or raw ore) + hydrogen chloride to shards"),
           10: ("purif", 6, "3x: shards (or raw ore) + oxygen to clumps"),
           11: ("crush", 0, "Clumps to dirty dust"), 12: ("enrich", 0, "Dirty dust to dust (and 2x: raw ore to dust)"),
           13: ("smelt", 0, "Dust to ingots")}
    for z, (ty, ph, note) in ore.items():
        put(42, 1, z, ty, W, ph, note + (" (already placed)" if ph == 0 else ""))
        put(43, 1, z, "prov", E, 3 if ph == 0 else ph, "Pattern provider + induction card: each step is its own pattern, so ME chains 2x to 5x by itself")
        put(43, 0, z, "me_o", 0, 3 if ph == 0 else ph)

    # ---- the gas plant (x 39, faces east): chase behind at x 38, cover wall at x 37
    gas = {5: ("rotary", 7, "Rotary Condensentrator: water to water vapour, pushed south"),
           6: ("cinf", 7, "Chemical Infuser: sulfur trioxide + water vapour = sulfuric acid"),
           7: ("cinf", 7, "Chemical Infuser: sulfur dioxide + oxygen = sulfur trioxide, pushed north"),
           8: ("oxid", 7, "Chemical Oxidizer: sulfur dust to sulfur dioxide, pushed north"),
           9: ("ctank", 6, "Oxygen tank: filled by the separator beside it, feeds the oxygen main"),
           10: ("sep", 6, "Electrolytic Separator A: water to hydrogen (south) and oxygen (north)"),
           11: ("cinf", 7, "Chemical Infuser: hydrogen + chlorine = hydrogen chloride"),
           12: ("sep", 7, "Electrolytic Separator B: brine to chlorine (north); sodium is vented"),
           13: ("prc", 7, "Pressurized Reaction Chamber: HDPE, substrate, ethylene (fed by ME through its provider)")}
    chase = {5: "p_water", 6: "p_acid", 7: "p_o2", 8: "prov", 9: "p_o2", 10: "p_water", 11: "p_hcl", 12: "p_brine", 13: "prov"}
    for z, (ty, ph, note) in gas.items():
        put(39, 1, z, ty, E, ph, note)
        put(39, 0, z, "uc", 0, 6, "Universal cable in the floor under the gas plant: its power")
        cz = chase[z]
        if cz == "prov":
            put(38, 1, z, "prov", W, 7, "Pattern provider: sulfur in (oxidizer) / everything in (PRC)")
        else:
            put(38, 1, z, cz, 0, ph)
            link((38, 1, z), (39, 1, z))
        for y in (1, 2):
            put(37, y, z, "pd", 0, 6, "Cover wall: the pipe chase behind the gas plant is closed on every side")
        put(38, 2, z, "cap", 0, 6)
    put(39, 1, 4, "sink", E, 6, "Kitchen sink: endless water with no pump, drawn from below")

    # ---- the power bay (x 42, faces west): lava under, a closed chase behind
    for z in range(17, 24):
        put(42, 1, z, "thermo", W, 2, "Nitro Thermo Generator: 1,750 FE/t measured on your server from the lava block under it, which it does not use up. Built 18 Nov")
        put(42, 0, z, "lava", 0, 2, "A lava source block in the floor under each generator (hidden)")
        put(43, 2, z, "cap", 0, 2)
    put(43, 1, 17, "facc", N, 2, "Flux Accessor: the generators' FE goes into the ME network's FE cells; every induction card draws from there")
    for z in range(18, 23):
        put(43, 1, z, "pw", 0, 2, "Closed chase behind the generators: one Pipez universal pipe carries the water in and the power out")
        link((43, 1, z), (42, 1, z))
    link((43, 1, 18), (43, 1, 17))
    put(43, 1, 23, "sink", W, 2, "A second sink, in the chase's end: the generators' coolant")
    link((43, 1, 22), (43, 1, 23))

    # ---- the fuel station (south-east corner): Nether lava into buckets
    put(43, 1, 26, "qe", W, 2, "Quantum Entangloporter: twin of the one over the Nether lava sea (-623 33 373). Lava comes through, the pump's power goes back")
    put(43, 1, 27, "iface", W, 2, "ME Interface: the lava flows into the ME network's fluid cell")
    put(42, 1, 27, "caner", W, 2, "ME Canner: empty bucket + 1000 mB of lava = a lava bucket (1,000 moves of drone fuel). Empties come back through the store")
    put(43, 0, 26, "pw", 0, 2); put(43, 0, 27, "me_o", 0, 2)

    # ---- the swarm's door: the ME Bridge beside the Works computer, flush in the floor
    put(35, 0, 15, "pc", 0, 0, "Works computer (there now): becomes the ME desk for the swarm, asking ME to craft and reading stock")
    put(34, 0, 15, "bridge", 0, 1, "ME Bridge: crafter1 and Sortnado ask ME for anything, and see everything, through this")

    # ---- the east yard
    for x in range(46, 50):
        for y in range(1, 5):
            for z in range(9, 13):
                if x in (46, 49) or z in (9, 12) or y in (1,):
                    put(x, y, z, "evap", 0, 7, "Thermal Evaporation tower (4x4, grows to 18 high): water to brine for chlorine")
    for x in range(46, 51):
        for y in range(1, 5):
            for z in range(17, 22):
                if (x in (46, 50)) + (z in (17, 21)) + (y in (1, 4)) >= 2:
                    put(x, y, z, "ghost", 0, 8, "Reserved pad: the big generator (Extreme Reactors or a Powah reactor), once the thermo row has been measured")

def services():
    # ---- ME trunks (y -1 unless under a block)
    n = "Trunk N: 32 channels"
    run("me_n", [(31, -1, 19), (31, -1, 13), (32, -1, 13), (32, -1, 12)], 1, n); link((31, -1, 19), (31, 0, 19))
    link((32, -1, 12), (32, 0, 12)); link((31, -1, 17), (31, 0, 17))
    run("me_n", [(32, -1, 8), (38, -1, 8)], 7, n); link((32, -1, 8), (32, 0, 8)); link((38, -1, 8), (38, 1, 8))
    put(38, 0, 8, "me_n", 0, 7); put(38, 0, 13, "me_n", 0, 7)
    run("me_n", [(33, -1, 13), (38, -1, 13)], 7, n)
    run("me_n", [(31, -1, 7), (29, -1, 7)], 4, n); link((31, -1, 7), (32, -1, 7)); put(32, -1, 7, "me_n", 0, 4)
    link((29, -1, 7), (29, 0, 7))
    run("me_n", [(32, -1, 15), (34, -1, 15)], 1, n); link((34, -1, 15), (34, 0, 15))
    wn = "Trunk W: 32 channels"
    run("me_w", [(31, -1, 20), (28, -1, 20)], 1, wn); link((31, -1, 20), (31, 0, 20))
    run("me_w", [(28, -1, 18), (28, -1, 26), (30, -1, 26)], 4, wn); link((30, -1, 26), (30, 0, 26))
    run("me_w", [(32, -1, 20), (33, -1, 20)], 1, wn); link((33, -1, 20), (33, 0, 20))
    run("me_w", [(29, -1, 24), (33, -1, 24)], 1, wn); link((33, -1, 24), (33, 0, 24))
    a = "Trunk A: 32 channels (11 providers, 6 feeds)"
    run("me_a", [(31, -1, 21), (38, -1, 21)], 3, a); link((31, -1, 21), (31, 0, 21)); link((38, -1, 21), (38, 0, 21))
    o = "Trunk O: 32 channels (8 providers, the flux accessor)"
    run("me_o", [(31, -1, 22), (43, -1, 22), (43, -1, 13)], 2, o); link((31, -1, 22), (31, 0, 22))
    link((43, -1, 13), (43, 0, 13)); put(43, 0, 17, "me_o", 0, 2); link((43, 0, 17), (43, 1, 17))
    run("me_o", [(42, -1, 23), (42, -1, 27), (43, -1, 27)], 2, o); link((43, -1, 27), (43, 0, 27)); link((42, -1, 27), (42, 1, 27))
    link((43, 0, 27), (43, 1, 27)); link((43, 0, 26), (43, 1, 26))
    # ---- power (y -2)
    p = "Power main, two blocks under the floor"
    put(43, 0, 23, "pw", 0, 2, "Under the sink: draws the coolant water, and carries the power down")
    link((43, 0, 23), (43, 1, 23))
    run("pw", [(43, -1, 23), (43, -2, 23), (31, -2, 23), (31, -1, 23)], 2, p); link((31, -1, 23), (31, 0, 23))
    run("pw", [(43, -1, 24), (43, -1, 26)], 2, p)
    run("pw", [(40, -2, 22), (40, -2, 13), (40, -1, 13), (39, -1, 13)], 6, p); link((39, -1, 13), (39, 0, 13))
    # ---- water, brine, gases
    wtr = "Water main, two blocks under the floor"
    put(39, 0, 4, "p_water", 0, 6, wtr); link((39, 0, 4), (39, 1, 4))
    run("p_water", [(39, -1, 4), (39, -2, 4), (38, -2, 4), (38, -2, 10), (38, -1, 10), (38, 0, 10)], 6, wtr)
    run("p_water", [(38, -1, 5), (38, 0, 5)], 7, wtr)
    run("p_water", [(39, -2, 7), (42, -2, 7), (42, -1, 7), (42, 0, 7)], 7, wtr); link((42, 0, 7), (42, 1, 7))
    ac = "Sulfuric acid, to the dissolution chamber"
    run("p_acid", [(38, 0, 6), (38, -1, 6), (42, -1, 6), (42, 0, 6)], 7, ac); link((42, 0, 6), (42, 1, 6))
    ox = "Oxygen main"
    run("p_o2", [(38, 0, 9), (38, -1, 9), (41, -1, 9), (41, -1, 10), (42, -1, 10), (42, 0, 10)], 6, ox); link((42, 0, 10), (42, 1, 10))
    run("p_o2", [(38, 0, 7), (38, -1, 7), (41, -1, 7), (41, -1, 8)], 7, ox)
    hc = "Hydrogen chloride, to the injection chamber"
    run("p_hcl", [(38, 0, 11), (38, -1, 11), (38, -2, 11), (42, -2, 11), (42, -2, 9), (42, -1, 9), (42, 0, 9)], 7, hc)
    link((42, 0, 9), (42, 1, 9))
    br = "Brine from the evaporation tower, three blocks down"
    run("p_brine", [(38, 0, 12), (38, -1, 12), (38, -2, 12), (38, -3, 12), (46, -3, 12), (46, 0, 12)], 7, br)
    link((46, 0, 12), (46, 1, 12))

ZONES = [
 dict(id="core", name="The Core", box=[28, 17, 33, 27], ph="1, 4, 5", cam=[30.5, 2, 22],
      text="The controller is a line of five blocks set flush in the floor with a four-block tower over its middle. Each block of the line gives one dense trunk from its underside, so every cable leaves the room below your feet. North wall: the vault (4 extended drives, 80 cell slots, and 6.4M AE of energy cells). West wall: the two crafting CPUs, where the old inscriber bench stood. South: the assembler matrix. Along the aisle: the desk, with a gap to walk in."),
 dict(id="garden", name="Crystal garden", box=[28, 4, 30, 12], ph="4", cam=[29, 2, 8],
      text="Three budding blocks in a glass case on the west wall, four growth accelerators between them. Annihilation planes in the floor and in the lintel take only full clusters. A Crystal Fixer behind each budding block stops it wearing down to plain quartz, which is what killed the farm today."),
 dict(id="lab", name="Crystal lab", box=[32, 7, 33, 12], ph="4", cam=[33, 1, 9.5],
      text="Six machines facing the aisle, each with an extended pattern provider behind it: charger, crystal assembler, reaction chamber, circuit cutter and two extended inscribers. This row makes fluix, charged certus, printed circuits and all three processors on demand."),
 dict(id="alloy", name="Alloy row", box=[38, 17, 39, 27], ph="3", cam=[39, 1, 22],
      text="Seven machines are there now; four more finish the row. One pattern provider behind each machine gives it items and power (induction card) and takes the result back. Four infusers, one per infusion type, each kept loaded by an export bus hidden in the floor under it. Steel, circuits and all three alloys become one-click crafts, and foundry1 stops carrying."),
 dict(id="ore", name="Ore line", box=[42, 6, 43, 13], ph="3, 6, 7", cam=[42, 1, 9.5],
      text="Crusher, chamber and smelter are there now (2x). Purification makes it 3x, injection 4x, and the three slurry machines 5x. Every machine has its own provider, so ME chains the steps itself and falls back to the best tier it has the gas for."),
 dict(id="gas", name="Gas plant", box=[37, 4, 39, 13], ph="6, 7", cam=[39, 1, 9],
      text="Nine machines in a row, ordered so each hands its gas straight to the neighbour that needs it. What must travel goes down a closed chase behind the row and under the lane in colour-coded tubes: oxygen, hydrogen chloride, sulfuric acid, with water and brine in mechanical pipes. Nothing shows above the floor."),
 dict(id="power", name="Power bay", box=[42, 17, 43, 23], ph="2", cam=[42, 1, 20],
      text="Built tonight. Seven Nitro thermo generators, each on a lava block set in the floor: 1,750 FE/t each as measured, about 12,250 FE/t together, and the lava is never used up. A capped chase behind them carries the power down under the floor to the controller and the machines. Still to add: the sink and pipe that keep their water topped up (a full tank lasts about two hours), and the flux accessor that puts spare power into ME."),
 dict(id="fuel", name="Fuel station", box=[42, 26, 43, 27], ph="2", cam=[43, 1, 26.5],
      text="A pump sits on the Nether lava sea at -623 31 373, a 96 by 96 sheet of open lava, in a chunk that stays loaded. Its lava arrives here through a pair of quantum entangloporters, goes into the ME network, and the canner fills buckets with it. A requester keeps a stock of full buckets in the barrels for the docks. No drone walks the dripstone wall any more; the wall stays as the backup."),
 dict(id="yard", name="East yard", box=[46, 9, 50, 21], ph="7, 8", cam=[48, 2, 15],
      text="Outside the east wall: the brine tower for chlorine (4x ore and up), and a reserved pad for one big generator once the thermo row's real output is known."),
]

def model():
    B.clear(); LINKS.clear(); del NOTES[:]
    shell(); plan(); services()
    return B

def check(B):
    bad = []
    for (x, y, z), (ty, f, ph, ni) in B.items():
        s = T[ty]["s"]
        # nothing of a service may show: a pipe cell needs a block over it, unless it is inside the chase or frame
        if s == "pipe" and y >= 0 and ty not in ("cc",):
            above = B.get((x, y + 1, z))
            if not above or T[above[0]]["a"] < 1 and above[0] not in ("mxg",):
                if not (ty == "me_n" and (x, y) in ((29, 4), (28, 4), (28, 3))):
                    bad.append(f"{ty} shows at {x} {y} {z}")
    walk = [(x, z) for x in (34, 35, 36) for z in range(4, 29)] + [(x, z) for x in (40, 41) for z in range(5, 28)] \
        + [(x, z) for x in range(28, 44) for z in (14, 15, 16)]
    for (x, z) in walk:
        for y in (1, 2):
            if (x, y, z) in B: bad.append(f"walkway blocked at {x} {y} {z} by {B[(x, y, z)][0]}")
    return bad

def bom(B):
    out = OrderedDict()
    for (x, y, z), (ty, f, ph, ni) in sorted(B.items(), key=lambda kv: kv[1][2]):
        if ph == 0: continue
        out.setdefault(ph, Counter())[ty] += 1
    return out

PHASES = [
 (0, "Bench tests", "Five one-block tests before anything is built: induction card powers a Mekanism machine; a provider's items come back by auto-eject; Crystal Fixer holds a flawed budding block; one thermo generator's real FE/t on lava with water; wireless connector range to the storeroom."),
 (1, "Core online", "Controller, vault, desk, ME Bridge, and the storage link. From here ME sees every barrel and you can search and craft at the desk."),
 (2, "Power bay", "Thermo row, chase, flux accessor, the power main, and the fuel station (Nether lava into buckets). The four heat generators and the cable strip behind them come out."),
 (3, "Alloy row and ore line on ME", "Providers behind the machines that stand there now, the four new machines, the infusion feeds. Steel, circuits and alloys by one click. foundry1 retires from carrying."),
 (4, "Crystals and processors", "Garden rebuilt with fixers and planes, and the crystal lab; the old inscriber bench comes out. Certus never runs out again."),
 (5, "Autocrafting at scale", "Two CPUs, the assembler matrix, requesters, the wireless access point. Stock levels hold themselves."),
 (6, "3x ore", "Sink, separator, oxygen tank and main, purification chamber, the gas plant's power."),
 (7, "4x and 5x ore", "The rest of the gas plant, the brine tower, injection and the three slurry machines."),
 (8, "Headroom", "The big generator on the reserved pad, MEGA cells, the Advanced AE quantum computer in place of the two CPUs."),
]

def page(B):
    keys = list(T)
    blocks = []
    for (x, y, z), (ty, f, ph, ni) in B.items():
        m = 0
        if T[ty]["s"] == "pipe":
            for i, (dx, dy, dz) in enumerate(((1, 0, 0), (0, 0, 1), (-1, 0, 0), (0, 0, -1), (0, 1, 0), (0, -1, 0))):
                nb = (x + dx, y + dy, z + dz)
                if (nb in B and B[nb][0] == ty) or ((x, y, z), nb) in LINKS:
                    m |= 1 << i
        blocks.append([x, y, z, keys.index(ty), f, ph, ni, m])
    data = dict(types=[dict(k=k, **T[k]) for k in keys], blocks=blocks, notes=NOTES, zones=ZONES,
                phases=[dict(n=n, name=a, text=b) for n, a, b in PHASES],
                bom={str(ph): [[T[k]["n"], T[k]["id"], c] for k, c in cnt.most_common()] for ph, cnt in bom(B).items()})
    tpl = open(os.path.join(ROOT, "tools", "ae2plan_page.html")).read()
    html = tpl.replace("/*DATA*/null", json.dumps(data, separators=(",", ":")))
    open(os.path.join(ROOT, "docs", "ae2-factory.html"), "w").write(html)
    return len(html), len(blocks)

if __name__ == "__main__":
    B = model()
    bad = check(B)
    for b in bad: print("CHECK:", b)
    if sys.argv[1:] == ["bom"]:
        for ph, cnt in bom(B).items():
            print("phase", ph)
            for k, c in cnt.most_common(): print(f"   {c:4d}  {T[k]['n']}  ({T[k]['id']})")
    elif os.path.exists(os.path.join(ROOT, "tools", "ae2plan_page.html")):
        print(page(B))
    print("ok" if not bad else f"{len(bad)} problems", len(B), "blocks")
