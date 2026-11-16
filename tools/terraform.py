#!/usr/bin/env python3
"""Blend the ground around the factory into the landscape with dirt.

usage: terraform.py <map.json> <ox> <oy> <oz>

Builds a sloping bank of dirt around the building wherever the ground is
lower than the floor, so the foundation is hidden and the meadow runs up to
the walls. The bank drops about two blocks for every three out, with a bit
of unevenness so it doesn't look machine-made, and fades out where it meets
the natural ground. It keeps clear of anything built (the hut, the campfire)
and never fills water.

Writes blueprints/factory_terraform.txt in the builder's list format.
"""
import json, os, sys, hashlib
from collections import deque

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
REACH = 9            # how far out the bank may run

site = json.load(open(sys.argv[1]))["data"]
ox, oy, oz = map(int, sys.argv[2:5])
N, o, H, pal, names = site["size"], site["origin"], site["heights"], site["palette"], site["names"]
f = site["factory"]
NAT = ("leaves", "log", "grass", "flower", "fern", "sapling", "moss", "bush", "shrub", "plant",
       "hyssop", "fireweed", "daisy", "tsubaki", "petals", "berr", "flax", "pumpkin", "seagrass",
       "glowrose", "sage", "windygarden", "mossy_stone", "redstone_bud", "thistle", "turtle")
built = set()
for c in site.get("above") or []:
    n = pal[c[3] - 1]
    if not any(w in n for w in NAT):
        for dx in range(-3, 4):
            for dz in range(-3, 4):
                built.add((c[0] + f["x"] + dx, c[2] + f["z"] + dz))

def ground(x, z):
    i, j = x - o["x"], z - o["z"]
    if not (0 <= i < N and 0 <= j < N):
        return None, None
    v = H[j * N + i]
    if v <= -1000:
        return None, None
    return v, pal[names[j * N + i] - 1] if names[j * N + i] else None

def wobble(x, z):
    h = hashlib.md5(f"{x},{z}".encode()).digest()[0]
    return (h / 255.0 - 0.5) * 0.8          # -0.4 .. +0.4

bp = json.load(open(os.path.join(ROOT, "blueprints", "factory.json")))
foot = {(ox + b[0], oz + b[2]) for b in bp["blocks"]}
# distance from the building, spreading outwards
dist = {c: 0 for c in foot}
q = deque(foot)
while q:
    x, z = q.popleft()
    d = dist[(x, z)]
    if d >= REACH:
        continue
    for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)):
        c = (x + dx, z + dz)
        if c not in dist:
            dist[c] = d + 1
            q.append(c)

top = oy - 1                                   # the ground level the floor sits on
blocks = []
for (x, z), d in dist.items():
    if d == 0 or (x, z) in built:
        continue
    g, name = ground(x, z)
    if g is None or (name and "water" in name):
        continue
    g = min(g, top)                            # the cleared ring is at most floor level
    target = top - int((d - 1) * 0.67 + 0.5 + wobble(x, z))
    for y in range(g + 1, target + 1):
        blocks.append((x - ox, y - oy, z - oz))

blocks.sort(key=lambda b: (b[1], b[2], b[0] if (b[1] + b[2]) % 2 == 0 else -b[0]))
out = os.path.join(ROOT, "blueprints", "factory_terraform.txt")
with open(out, "w") as fh:
    fh.write("P 1\nminecraft:dirt -\n")
    fh.write(f"B {len(blocks)}\n")
    for x, y, z in blocks:
        fh.write(f"{x} {y} {z} 0\n")
cols = {(b[0], b[2]) for b in blocks}
print(f"{out}: {len(blocks)} dirt in {len(cols)} columns, layers {min(b[1] for b in blocks)}..{max(b[1] for b in blocks)}")
