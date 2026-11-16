#!/usr/bin/env python3
"""Turn blueprints/factory.json into the builder's list for one pass.

Pass 1 (the shell) is everything except glass, dirt and the fittings
(chests, furnaces, computers, ladders, lanterns...). Pass 2 adds the glass
from the inside later.

Writes blueprints/factory_shell.txt:
  P <n>                     then n lines: <item name> <facing or ->
  B <m>                     then m lines: <x> <y> <z> <palette index>
in the order the builder places them: layer by layer from the floor up,
each layer in rows that go back and forth.
"""
import json, os, re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SHELL = {
    "minecraft:polished_deepslate", "minecraft:deepslate_tiles", "minecraft:stone_bricks",
    "minecraft:cracked_stone_bricks", "minecraft:deepslate_bricks",
    "minecraft:deepslate_tile_stairs", "minecraft:cut_copper", "minecraft:cut_copper_slab",
}

bp = json.load(open(os.path.join(ROOT, "blueprints", "factory.json")))
pal, index, blocks = [], {}, []
for x, y, z, i in bp["blocks"]:
    full = bp["palette"][i]
    m = re.match(r"([^\[]+)(?:\[(.*)\])?", full)
    name, props = m.group(1), dict(p.split("=") for p in (m.group(2) or "").split(",") if p)
    if name not in SHELL:
        continue
    entry = (name, props.get("facing", "-"))
    if entry not in index:
        index[entry] = len(pal)
        pal.append(entry)
    blocks.append((x, y, z, index[entry]))

def order(b):
    x, y, z, _ = b
    row = z if y % 2 == 0 else -z               # alternate the row direction per layer
    col = x if (z + y) % 2 == 0 else -x         # back and forth along each row
    return (y, row, col)

blocks.sort(key=order)
out = os.path.join(ROOT, "blueprints", "factory_shell.txt")
with open(out, "w") as f:
    f.write(f"P {len(pal)}\n")
    for name, facing in pal:
        f.write(f"{name} {facing}\n")
    f.write(f"B {len(blocks)}\n")
    for x, y, z, i in blocks:
        f.write(f"{x} {y} {z} {i}\n")
print(f"{out}: {len(blocks)} blocks, {len(pal)} kinds, layers 0..{max(b[1] for b in blocks)}")
