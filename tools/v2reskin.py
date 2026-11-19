#!/usr/bin/env python3
"""Factory v2, pass 2: the old walls swapped in place for the new skin (Kyle, 19 Nov 14:51: "Swap em").

Only plain building blocks are swapped: stone bricks (all kinds), polished deepslate, deepslate tiles and
bricks, glass panes. Machines, monitors, computers, cables, modems, chains, ladders and every opening (air)
are left alone, so doorways, drone ports and screens stay as they are. Facades only (x 0, z 0, z 30, x 45,
y 1..12); the hall's roof is not touched.

Then the old pitched roof inside the new top floor: its stairs and roof blocks at y 15 become the engine
floor (grey concrete), above it they are removed.

    python3 tools/v2reskin.py > /tmp/v2_reskin.txt
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ae2plan as A
import factoryv2 as F
import v2build as V

OLD = ["#minecraft:stone_bricks", "minecraft:polished_deepslate", "minecraft:deepslate_tiles",
       "minecraft:deepslate_bricks", "#c:glass_panes"]
ROOF_OLD = OLD + ["#minecraft:stairs", "#minecraft:slabs", "minecraft:cut_copper", "minecraft:glass"]


def main():
    F.page()
    T = A.T
    cells = {}
    for (x, y, z), (ty, f) in F.SKIN.items():
        if not (1 <= y <= 12 and 0 <= x <= 45 and 0 <= z <= 30): continue
        if not (x in (0, 45) or z in (0, 30)): continue
        if ty in V.SKIP_TYPES: continue
        cells[(x, y, z)] = T[ty]["id"] + V.state(T[ty]["id"], f, T[ty]["s"], ty)
    groups = {}
    for p, bs in cells.items(): groups.setdefault(bs, set()).add(p)
    out, placed = [], set()
    for bs in sorted(groups, key=lambda k: len(groups[k])):
        for (x0, y0, z0, x1, y1, z1) in V.cover(groups[bs], placed):
            a = (V.OX + x0, V.OY + y0, V.OZ + z0); b = (V.OX + x1, V.OY + y1, V.OZ + z1)
            for o in OLD:
                out.append("fill %d %d %d %d %d %d %s replace %s" % (*a, *b, bs, o))
        placed |= groups[bs]
    # the old roof inside the new top floor (x 1..26, z 1..29)
    a, b = (V.OX + 1, V.OZ + 1), (V.OX + 26, V.OZ + 29)
    for o in ROOF_OLD:
        out.append("fill %d %d %d %d %d %d minecraft:gray_concrete replace %s" % (a[0], V.OY + 15, a[1], b[0], V.OY + 15, b[1], o))
        out.append("fill %d %d %d %d %d %d minecraft:air replace %s" % (a[0], V.OY + 16, a[1], b[0], V.OY + 20, b[1], o))
    print("\n".join(out))


if __name__ == "__main__":
    main()
