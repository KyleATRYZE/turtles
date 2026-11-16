#!/usr/bin/env python3
"""Pick where the factory goes on a ground map uploaded by the builder.

usage: pick_site.py <map.json> [near_x near_z]

Tries every corner position for the building (plus the cleared ring around
it) and scores how much ground would have to be dug away or bridged over.
Prints the best few: ox, oy, oz for the build order.
"""
import json, sys
from collections import Counter

SX, SZ, MARGIN = 57, 32, 2
HUT_EAST = -4456          # keep the building's west ring east of the hut

d = json.load(open(sys.argv[1]))["data"]
N, o = d["size"], d["origin"]
H = d["heights"]
near = (float(sys.argv[2]), float(sys.argv[3])) if len(sys.argv) > 3 else None
pal = d["palette"]
above = d.get("above") or []
odd = {(c[0], c[2]) for c in above if not any(w in pal[c[3]-1] for w in
       ("leaves", "log", "grass", "flower", "fern", "sapling", "moss", "bush", "shrub",
        "plant", "hyssop", "fireweed", "daisy", "tsubaki", "petals", "berr", "flax"))}

def h(x, z):
    i, j = x - o["x"], z - o["z"]
    if 0 <= i < N and 0 <= j < N:
        v = H[j * N + i]
        return v if v > -1000 else None
    return None

results = []
for ox in range(o["x"] + MARGIN, o["x"] + N - SX - MARGIN + 1):
    if ox - MARGIN < HUT_EAST:
        continue
    for oz in range(o["z"] + MARGIN, o["z"] + N - SZ - MARGIN + 1):
        hs, unknown, built = [], 0, 0
        for x in range(ox - MARGIN, ox + SX + MARGIN):
            for z in range(oz - MARGIN, oz + SZ + MARGIN):
                v = h(x, z)
                if v is None: unknown += 1
                else: hs.append(v)
                if (x, z) in odd: built += 1
        if unknown > 0.03 * (SX + 4) * (SZ + 4) or built:
            continue
        ground = Counter(hs).most_common(1)[0][0]
        dig = sum(max(0, v - ground) for v in hs)          # blocks above the floor line
        fill = sum(max(0, ground - v) for v in hs)         # air gaps under the floor
        score = dig * 1.0 + fill * 0.5
        if near:
            cx, cz = ox + SX / 2, oz + SZ / 2
            score += 0.5 * ((cx - near[0]) ** 2 + (cz - near[1]) ** 2) ** 0.5
        results.append((score, ox, ground + 1, oz, dig, fill, unknown))

results.sort()
print(f"map {o['x']}..{o['x']+N-1}, {o['z']}..{o['z']+N-1}; {len(results)} possible spots")
for r in results[:5]:
    score, ox, oy, oz, dig, fill, unknown = r
    print(f"ox={ox} oy={oy} oz={oz}   dig {dig}, gaps under the floor {fill}, unknown {unknown}, score {score:.0f}")
