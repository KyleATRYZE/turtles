#!/usr/bin/env python3
"""Turn a build guide's new blocks (docs/*-build.html: CAT + CELLS) into a
Create schematic (.nbt, vanilla structure format) Kyle loads at a Schematic
Table. Only the blocks he places go in; the schematic's origin is printed so
the hologram can be put exactly in place.
    python3 tools/schematic.py docs/foundry-build.html schematics/foundry_cable.nbt
"""
import re, json, sys, nbtlib
from nbtlib.tag import Compound, List, Int, String

BLOCK = {   # build-guide category -> block state
    "bay": ("computercraft:wired_modem_full", {}),
    "conn": ("computercraft:wired_modem_full", {}),
    "cable": ("computercraft:cable", {"cable": "true", "modem": "none"}),
    "mon": ("computercraft:monitor_advanced", {"facing": "south", "orientation": "north", "state": "none"}),
    "pc": ("computercraft:computer_advanced", {"facing": "east", "state": "off"}),
    "bars2": ("minecraft:iron_bars", {}),
    "copper2": ("minecraft:cut_copper", {}),
}
DATA_VERSION = 3955   # 1.21.1

def build(page, out):
    s = open(page).read()
    cat = json.loads(re.search(r"const CAT = (\[.*?\]);", s, re.S).group(1))
    cells = json.loads(re.search(r"const CELLS = (\[.*?\]);", s, re.S).group(1))
    O = json.loads(re.search(r"const O = (\[.*?\]);", s).group(1))
    new = [c for c in cells if cat[c[3]][0] in BLOCK]
    xs, ys, zs = [c[0] for c in new], [c[1] for c in new], [c[2] for c in new]
    x0, y0, z0 = min(xs), min(ys), min(zs)
    size = [max(xs) - x0 + 1, max(ys) - y0 + 1, max(zs) - z0 + 1]
    palette, index, blocks = [], {}, []
    for c in new:
        name, props = BLOCK[cat[c[3]][0]]
        key = (name, tuple(sorted(props.items())))
        if key not in index:
            index[key] = len(palette)
            e = Compound({"Name": String(name)})
            if props:
                e["Properties"] = Compound({k: String(v) for k, v in props.items()})
            palette.append(e)
        blocks.append(Compound({"pos": List[Int]([Int(c[0] - x0), Int(c[1] - y0), Int(c[2] - z0)]),
                                "state": Int(index[key])}))
    root = Compound({"DataVersion": Int(DATA_VERSION), "size": List[Int]([Int(v) for v in size]),
                     "palette": List[Compound](palette), "blocks": List[Compound](blocks),
                     "entities": List[Compound]([])})
    nbtlib.File(root, root_name="").save(out, gzipped=True)
    corner = (O[0] + x0, O[1] + y0, O[2] + z0)
    from collections import Counter
    print(out, "size", size, "corner (lowest x, y, z) at world", *corner)
    for (n, _), k in Counter((BLOCK[cat[c[3]][0]][0], 0) for c in new).items():
        print(f"  {k:3d}  {n}")
    return corner

if __name__ == "__main__":
    build(sys.argv[1], sys.argv[2])
