#!/usr/bin/env python3
"""A touch-up pass over a building that has been fitted out: writes the
building as it stands (blueprints/factory_asfit.txt, in the shell format)
from the plan it was built to, leaving out the glass up to a given height
(the windows the builders had no glass for). Then

    tools/fitout.py blueprints/factory.json blueprints/factory_asfit.txt \\
        blueprints/factory_touchup.txt 22,2,33 glass

works out the jobs: the missing windows, and anything the new plan changes
(the drone lane's floor, to striped yellow concrete).

    tools/touchup.py <the plan it was built to .json> [<glass missing up to y> [<name>]]
"""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
bp = json.load(open(sys.argv[1]))
top = int(sys.argv[2]) if len(sys.argv) > 2 else 6
pal, index, rows = [], {}, []
blocks = {(x, y, z): bp["palette"][i] for x, y, z, i in bp["blocks"]}
for (x, y, z), full in sorted(blocks.items(), key=lambda t: (t[0][1], t[0][2], t[0][0])):
    name = full.split("[")[0]
    if name in ("minecraft:glass_pane", "minecraft:glass") and y <= top:
        continue
    if name.endswith("sapling"):
        continue                                   # never planted
    m = re.search(r"facing=(\w+)", full)
    entry = (name, m.group(1) if m else "-")
    if entry not in index:
        index[entry] = len(pal)
        pal.append(entry)
    rows.append(f"{x} {y} {z} {index[entry]}")
out = os.path.join(ROOT, "blueprints", (sys.argv[3] if len(sys.argv) > 3 else "factory_asfit") + ".txt")
with open(out, "w") as f:
    f.write(f"P {len(pal)}\n" + "\n".join(f"{n} {fc}" for n, fc in pal) + f"\nB {len(rows)}\n" + "\n".join(rows) + "\n")
print(out, len(rows), "blocks")
