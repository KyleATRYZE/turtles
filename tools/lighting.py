#!/usr/bin/env python3
"""Where the lanterns go, so no mob can spawn inside the factory.

Mobs spawn where the block light is 0. plan_lanterns() floods light from
each lantern (15 at the lantern, one less per block, through air and glass)
over every spot inside the building a player can walk to from the
launch-bay door, and hangs lanterns under the ceilings until no spot is
dark. Under a high ceiling a lantern hangs on a chain, about five blocks
above the floor.

Run on its own it reports on blueprints/factory.json.
"""
import json, os, re
from collections import deque

N6 = ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1))


def plan_lanterns(blocks, door_z=None, log=print):
    """blocks: {(x, y, z): block name}. Returns [(lantern, [chain cells])]."""
    solid = {p: re.match(r"[^\[]+", n).group(0) for p, n in blocks.items()
             if "lantern" not in n and "chain" not in n}
    see_through = {p for p, n in solid.items() if "glass" in n}
    X = max(p[0] for p in solid) + 1
    Y = max(p[1] for p in solid) + 2
    Z = max(p[2] for p in solid) + 1
    # inside: every open cell under the roof (below the top block of its column)
    top = {}
    for (x, y, z) in solid:
        top[(x, z)] = max(top.get((x, z), -1), y)
    inside = {(x, y, z) for (x, z), t in top.items() for y in range(1, t)
              if (x, y, z) not in solid}
    ladder = {p for p, n in solid.items() if "ladder" in n}

    def stand(c):
        x, y, z = c
        return c in ladder or (c in inside and (x, y - 1, z) in solid and (x, y + 1, z) not in solid)

    def spawnable(c):
        x, y, z = c
        below = solid.get((x, y - 1, z), "")
        return (below and "glass" not in below and "slab" not in below and "stairs" not in below
                and "ladder" not in below and (x, y + 1, z) not in solid)

    # walk in from the door (front wall, middle) stepping up/down one, climbing ladders
    dz = Z - 2 if door_z is None else door_z
    door = min((c for c in inside if c[1] == 1 and c[2] == dz and stand(c)),
               key=lambda c: abs(c[0] - X // 2))
    reach, q = {door}, deque([door])
    while q:
        x, y, z = q.popleft()
        nxt = []
        for ddx, ddz in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nxt += [(x + ddx, y, z + ddz), (x + ddx, y - 1, z + ddz)]
            if (x, y + 2, z) not in solid:
                nxt.append((x + ddx, y + 1, z + ddz))
        if (x, y, z) in ladder or (x, y + 1, z) in ladder:
            nxt.append((x, y + 1, z))
        if (x, y - 1, z) in ladder:
            nxt.append((x, y - 1, z))
        for n in nxt:
            if n not in reach and stand(n):
                reach.add(n)
                q.append(n)
    spots = {c for c in reach if spawnable(c)}

    def light_from(sources):
        level, q = {}, deque()
        for s in sources:
            level[s] = 15
            q.append(s)
        while q:
            c = q.popleft()
            l = level[c] - 1
            if l <= 0:
                continue
            for d in N6:
                n = (c[0] + d[0], c[1] + d[1], c[2] + d[2])
                if (n in solid and n not in see_through) or not (-1 <= n[0] <= X and 0 <= n[1] <= Y and -1 <= n[2] <= Z):
                    continue
                if level.get(n, 0) < l:
                    level[n] = l
                    q.append(n)
        return level

    # hanging spots: under a ceiling (not a pane), on a chain if it's high
    chains = {}
    for (x, y, z) in inside:
        above = (x, y + 1, z)
        if above not in solid or "glass_pane" in solid[above]:
            continue
        f = y
        while (x, f - 1, z) in inside:
            f -= 1
        if y - f < 2:
            continue
        at = min(y, f + 5)
        chains[(x, at, z)] = [(x, yy, z) for yy in range(at + 1, y + 1)]

    placed = []
    lv_all = {}
    left = set(spots)
    log(f"inside: {len(inside)} cells, {len(spots)} walkable spots to keep lit")
    while left:
        s = next(iter(left))
        near = [c for c in chains if abs(c[0] - s[0]) + abs(c[1] - s[1]) + abs(c[2] - s[2]) <= 13]
        best, best_n, best_lv = None, 0, None
        for c in near:
            lv = light_from([c])
            n = sum(1 for p in left if lv.get(p, 0) > 0)
            # prefer short chains when it's a tie
            if n > best_n or (n == best_n and best and len(chains[c]) < len(chains[best])):
                best, best_n, best_lv = c, n, lv
        if not best:
            log(f"  nowhere to hang a lantern near {s}")
            left.discard(s)
            continue
        placed.append(best)
        left = {p for p in left if best_lv.get(p, 0) == 0}
    log(f"{len(placed)} lanterns, {sum(len(chains[c]) for c in placed)} chain links")
    return [(c, chains[c]) for c in placed]


if __name__ == "__main__":
    ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    bp = json.load(open(os.path.join(ROOT, "blueprints", "factory.json")))
    blocks = {(x, y, z): bp["palette"][i] for x, y, z, i in bp["blocks"]}
    for c, ch in sorted(plan_lanterns(blocks), key=lambda t: (t[0][1], t[0][2], t[0][0])):
        print("  lantern", c, "chain", len(ch))
