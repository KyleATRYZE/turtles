#!/usr/bin/env python3
"""Build the factory plan page: an interactive 3D model of blueprints/factory.json
plus the room-by-room plan, the materials and the build order.

Writes docs/factory-plan.html (one self-contained page).
"""
import json, math, os
from collections import Counter

ROOT = os.path.join(os.path.dirname(__file__), "..")
bp = json.load(open(os.path.join(ROOT, "blueprints", "factory.json")))

# ---------------------------------------------------------------- materials, back to what the miners dig
need = Counter(bp["materials"])
raw = Counter()
smelt = Counter()
for name, n in need.items():
    b = name.split(":")[1]
    if b in ("stone_bricks",):
        raw["stone"] += n
    elif b == "cracked_stone_bricks":
        raw["stone"] += n; smelt["Stone bricks → cracked"] += n
    elif b in ("polished_deepslate", "deepslate_bricks", "deepslate_tiles"):
        raw["cobbled_deepslate"] += n
    elif b == "deepslate_tile_stairs":
        raw["cobbled_deepslate"] += math.ceil(n / 4) * 6
    elif b == "glass_pane":
        raw["glass"] += math.ceil(n / 16) * 6
    elif b == "glass":
        raw["glass"] += n
    elif b == "dirt":
        raw["dirt"] += n
    elif b == "chest":
        raw["logs"] += n * 2
    elif b == "ladder":
        raw["logs"] += 6
    elif b == "monitor_advanced":
        raw["gold_ingot"] += math.ceil(n / 4) * 7
    elif b == "cut_copper":
        raw["copper_ingot"] += math.ceil(n / 4) * 36
    elif b == "cut_copper_slab":
        raw["copper_ingot"] += math.ceil(n / 6) * 27
    elif b == "lightning_rod":
        raw["copper_ingot"] += n * 3
    elif b == "furnace":
        raw["cobblestone"] += n * 8
    elif b == "lantern":
        raw["iron_ingot"] += n            # 8 nuggets each, plus a torch
    elif b == "chain":
        raw["iron_ingot"] += math.ceil(n * 11 / 9)
    elif b == "birch_sapling":
        raw["birch_sapling"] += n
raw["cobblestone"] += raw["stone"]; smelt["Cobblestone → stone"] += raw["stone"]
raw["sand"] += raw["glass"]; smelt["Sand → glass"] += raw["glass"]
smelt["Raw copper → ingots"] += raw["copper_ingot"]
total_smelts = sum(smelt.values())
raw["coal"] += math.ceil(total_smelts / 8)

NICE = {
    "cobbled_deepslate": ("Cobbled deepslate", "In stock: the miners brought home more than enough"),
    "cobblestone": ("Cobblestone", "In stock, plus the stone you added"),
    "sand": ("Glass", "About 270 in stock (glass and sand): roughly 200 more sand to find"),
    "dirt": ("Dirt", "Tree farm soil: in stock from clearing the site"),
    "logs": ("Logs", "Chests and ladders: from the tree farm, once it is growing"),
    "gold_ingot": ("Gold ingots", "Monitor wall: the factory has about 80 counting raw gold"),
    "copper_ingot": ("Copper ingots", "Chimney caps and pipes: the factory has 450 raw copper"),
    "iron_ingot": ("Iron ingots", "Lanterns and their chains: the factory has 88"),
    "coal": ("Coal", "Fuel for all the smelting"),
    "birch_sapling": ("Birch saplings", "To start the tree farm: from you"),
}
raw_rows = [(NICE[k][0], raw[k], NICE[k][1]) for k in NICE if raw[k]]

LABEL = lambda n: n.split(":")[1].replace("_", " ").capitalize()
block_rows = [(LABEL(k), v) for k, v in need.most_common()]

page_data = {
    "palette": bp["palette"], "blocks": bp["blocks"], "rooms": bp["rooms"],
    "size": bp["size"], "routes": bp.get("routes", []), "docks": bp.get("docks", []),
}

html = open(os.path.join(os.path.dirname(__file__), "viewer_template.html")).read()
html = html.replace("/*DATA*/null", json.dumps(page_data, separators=(",", ":")))
html = html.replace("{{TOTAL}}", f"{len(bp['blocks']):,}")
html = html.replace("{{SMELTS}}", f"{total_smelts:,}")
html = html.replace("{{SMELT_HOURS_1}}", f"{total_smelts * 10 / 3600:.0f}")
html = html.replace("{{SMELT_MIN_13}}", f"{total_smelts * 10 / 60 / 13:.0f}")
html = html.replace("{{RAW_ROWS}}", "\n".join(
    f'<tr><td>{a}</td><td class="num">{b:,}</td><td>{c}</td></tr>' for a, b, c in raw_rows))
html = html.replace("{{BLOCK_ROWS}}", "\n".join(
    f'<tr><td>{a}</td><td class="num">{b:,}</td></tr>' for a, b in block_rows))
os.makedirs(os.path.join(ROOT, "docs"), exist_ok=True)
out = os.path.join(ROOT, "docs", "factory-plan.html")
open(out, "w").write(html)
print("wrote", out, len(html) // 1024, "KB")
print("raw:", raw_rows)
print("smelting jobs:", total_smelts)
