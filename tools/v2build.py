#!/usr/bin/env python3
"""Compile the approved Factory v2 model (tools/factoryv2.py) into RCON commands.

    python3 tools/v2build.py stats                 how many blocks and commands per stage
    python3 tools/v2build.py cmds <stage> [out]    write the stage's commands (one per line)

Safety: every placement is `fill ... keep` (or setblock keep): only air is filled, so nothing
already there (machines, cables, drives, Kyle's blocks, stored items) is touched. Existing walls
the design reskins are left for a separate, per-block `execute if block ... run setblock ... destroy`
pass so Kyle's blocks drop rather than vanish. Natural ground (grass, dirt, stone) under the
grounds/road is replaced (terraform), never anything placed by a player.

No new ME cables, AE2/Mekanism machines or wireless connectors are placed here: the network is
changed only by hand with the tools/mehealth.md sweep after.
"""
import os, sys, json
from collections import defaultdict
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ae2plan as A
import factoryv2 as F

OX, OY, OZ = -4448, 71, 1518
SKIP_CATS = {"ae", "mek", "power", "lava", "pipe_me", "pipe_pw", "pipe_ch", "pipe_cc"}
SKIP_TYPES = {"wcon", "drone", "fuel", "barrel",    # drones are the real swarm; the fuel counter is an ME interface (by hand)
              "chain", "sk_chain", "belt",
              "gate", "gateglass", "hatch"}    # the blast gate and hangar door are Create contraptions: built working, not as walls # chain-conveyor runs and belts are made in game (chains / belt connector)
NATURAL = ["minecraft:grass_block", "minecraft:dirt", "minecraft:stone", "minecraft:coarse_dirt",
           "minecraft:andesite", "minecraft:diorite", "minecraft:granite", "minecraft:gravel",
           "minecraft:short_grass", "minecraft:tall_grass", "minecraft:deepslate", "minecraft:tuff"]
AXIS_IDS = {"minecraft:chain", "create:shaft", "create:gantry_shaft"}
FACING_IDS = {"minecraft:furnace", "computercraft:computer_normal", "computercraft:computer_advanced",
              "computercraft:turtle_normal", "computercraft:turtle_advanced", "computercraft:speaker",
              "computercraft:monitor_advanced", "create:stock_ticker", "create:display_board",
              "create:blaze_burner", "minecraft:lever"}
FACE6_IDS = {"create:deployer", "create:packager"}
DIR = ["east", "south", "west", "north", "up", "down"]


def state(rid, f, shape, ty=""):
    if rid in AXIS_IDS or shape in ("chain", "beam"):
        if rid in AXIS_IDS:
            ax = "y" if f == 2 else ("z" if f % 2 else "x")
            if rid == "create:gantry_shaft":
                return "[facing=%s]" % {"x": "east", "z": "south", "y": "up"}[ax]
            return "[axis=%s]" % ax
        return ""
    if rid in FACING_IDS:
        return "[facing=%s]" % DIR[f if f < 4 else 3]
    if rid in FACE6_IDS:
        return "[facing=%s]" % DIR[f]
    if rid.endswith("_leaves"):
        return "[persistent=true]"
    if rid == "minecraft:copper_bulb":
        return "[lit=true]"
    if rid == "minecraft:lantern" and ty == "hlamp":
        return "[hanging=true]"
    return ""


def lane_clear(x, y, z):
    """The drone lane (swarm.lua M.LANE: y 73 along z 1519/1520) and the drones' way down to
    its gates (westIn -4451,1520; eastIn/eastOut -4402,1519/1520) are kept open, sky to floor."""
    if -4 <= x <= 47 and 0 <= z <= 3 and 1 <= y <= 5: return True
    if (-5 <= x <= -2 or 45 <= x <= 48) and 0 <= z <= 3 and y >= 1: return True
    return False


def model():
    """Every new block of the design: {(x,y,z): (stage, blockstate)}."""
    F.page()
    T = A.T
    out = {}
    for (x, y, z), v in A.B.items():
        ty, f = v[0], v[1]
        ph = v[2] if len(v) > 2 and isinstance(v[2], int) else 0
        t = T[ty]
        if t["cat"] in SKIP_CATS or ty in SKIP_TYPES or ph == 0:
            continue
        if t["cat"] not in ("v2", "build") or ph != 8:
            continue    # phases 1-7 are the AE2/Mekanism plan's own steps (gas plant covers etc.): not part of this build
        out[(x, y, z)] = ("inside", t["id"] + state(t["id"], f, t["s"], ty))
    # the old building as surveyed: its doorways, drone ports and vents stay open (the skin only
    # goes where the old wall already is, or outside the old envelope)
    old = {p for p, v in A.B.items() if T[v[0]]["cat"] == "build" and not (len(v) > 2 and isinstance(v[2], int) and v[2] > 0)}
    for (x, y, z), (ty, f) in F.SKIN.items():
        t = T[ty]
        if ty in SKIP_TYPES:
            continue
        if 0 <= x <= 45 and 0 <= z <= 30 and 1 <= y <= 12:
            continue    # the old envelope: openings stay open; old wall faces are a separate reskin pass
        if x <= -6 and -6 <= z <= 14:
            continue    # the hut, crafter1, crafter2 and the old pad shaft (-4461..-4463, 1521..1523): left as they are
        stg = "ground" if y <= 0 else "outside"
        out[(x, y, z)] = (stg, t["id"] + state(t["id"], f, t["s"], ty))
    # the land falls away from the floor (1-4 blocks east and south): footings down to the ground,
    # only into air. Walls, piers and towers carry their own block down; trees, hedges and lamps sit on dirt.
    VEG = {"sk_hedge", "sk_leaf", "sk_log", "sk_lamp"}
    for (x, y, z), (ty, f) in F.SKIN.items():
        if y != 1 or (x, y, z) not in out or (x, 0, z) in out or ty in SKIP_TYPES:
            continue
        if 0 <= x <= 45 and 0 <= z <= 30:
            continue
        bs = "minecraft:dirt" if ty in VEG else out[(x, y, z)][1]
        for yy in range(-5, 1):
            out[(x, yy, z)] = ("outside", "minecraft:grass_block" if (ty in VEG and yy == 0) else bs)
    return {p: v for p, v in out.items() if not lane_clear(*p)}


def boxes(cells):
    """Greedy merge into cuboids; tries all six axis orders and keeps the fewest boxes."""
    best = None
    for order in ((0, 2, 1), (0, 1, 2), (2, 0, 1), (2, 1, 0), (1, 0, 2), (1, 2, 0)):
        sw = [{(c[order[0]], c[order[1]], c[order[2]]) for c in cells}]
        r = _boxes(sw[0])
        inv = [order.index(i) for i in range(3)]
        r = [tuple([b[inv[0]], b[inv[1]], b[inv[2]], b[3 + inv[0]], b[3 + inv[1]], b[3 + inv[2]]]) for b in r]
        if best is None or len(r) < len(best): best = r
    return best


def cover(targets, allowed):
    """Cuboids that cover every target cell, each made only of allowed cells (targets plus cells
    already placed: fill keep passes over those). Tries the six axis orders, keeps the fewest."""
    best = None
    for order in ((0, 2, 1), (0, 1, 2), (2, 0, 1), (2, 1, 0), (1, 0, 2), (1, 2, 0)):
        sw = lambda c: (c[order[0]], c[order[1]], c[order[2]])
        T_ = {sw(c) for c in targets}; A_ = {sw(c) for c in allowed} | T_
        left = set(T_); res = []
        for c in sorted(T_, key=lambda p: (p[1], p[2], p[0])):
            if c not in left: continue
            x0, y0, z0 = c; x1 = x0
            while (x1 + 1, y0, z0) in A_: x1 += 1
            z1 = z0
            while all((x, y0, z1 + 1) in A_ for x in range(x0, x1 + 1)): z1 += 1
            y1 = y0
            while all((x, y1 + 1, z) in A_ for x in range(x0, x1 + 1) for z in range(z0, z1 + 1)): y1 += 1
            for x in range(x0, x1 + 1):
                for y in range(y0, y1 + 1):
                    for z in range(z0, z1 + 1): left.discard((x, y, z))
            res.append((x0, y0, z0, x1, y1, z1))
        inv = [order.index(i) for i in range(3)]
        res = [(b[inv[0]], b[inv[1]], b[inv[2]], b[3 + inv[0]], b[3 + inv[1]], b[3 + inv[2]]) for b in res]
        if best is None or len(res) < len(best): best = res
    return best


def _boxes(cells):
    left = set(cells)
    res = []
    for c in sorted(cells, key=lambda p: (p[1], p[2], p[0])):
        if c not in left:
            continue
        x0, y0, z0 = c
        x1 = x0
        while (x1 + 1, y0, z0) in left: x1 += 1
        z1 = z0
        while all((x, y0, z1 + 1) in left for x in range(x0, x1 + 1)): z1 += 1
        y1 = y0
        while all((x, y1 + 1, z) in left for x in range(x0, x1 + 1) for z in range(z0, z1 + 1)): y1 += 1
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                for z in range(z0, z1 + 1):
                    left.discard((x, y, z))
        res.append((x0, y0, z0, x1, y1, z1))
    return res


def commands(stage):
    m = model()
    groups = defaultdict(set)
    for p, (stg, bs) in m.items():
        if stg == stage:
            groups[bs].add(p)
    cmds = []
    if stage == "ground":   # a dirt bed under the grounds wherever the land dips (only air is filled)
        foot = {(x, 0, z) for cells in groups.values() for (x, y, z) in cells}
        for (x0, _, z0, x1, _, z1) in boxes(foot):
            cmds.append("fill %d %d %d %d %d %d minecraft:dirt keep" % (OX + x0, OY - 5, OZ + z0, OX + x1, OY - 1, OZ + z1))
    placed = set()
    seq = []
    order = sorted(groups, key=lambda k: len(groups[k]))
    small, big = order[:-7], order[-7:]
    # rare states first; the five biggest in the order (found by DP over subsets) that needs fewest fills
    for bs in small:
        bx = cover(groups[bs], placed) if stage != "ground" else boxes(groups[bs])
        placed |= groups[bs]
        seq.append((bs, bx))
    if stage != "ground" and big:
        from functools import lru_cache
        @lru_cache(None)
        def cost(i, mask):
            prior = set(placed)
            for j in range(len(big)):
                if mask >> j & 1: prior |= groups[big[j]]
            return cover(groups[big[i]], prior)
        best = {0: (0, [])}
        for mask in range(1 << len(big)):
            if mask not in best: continue
            c, path = best[mask]
            for i in range(len(big)):
                if mask >> i & 1: continue
                bx = cost(i, mask); nm = mask | 1 << i
                if nm not in best or best[nm][0] > c + len(bx): best[nm] = (c + len(bx), path + [(big[i], bx)])
        seq += best[(1 << len(big)) - 1][1]
    else:
        for bs in big:
            seq.append((bs, boxes(groups[bs])))
    for bs, bx in seq:
        for (x0, y0, z0, x1, y1, z1) in bx:
            a = (OX + x0, OY + y0, OZ + z0); b = (OX + x1, OY + y1, OZ + z1)
            if stage == "ground":
                # natural ground (the dirt tag: grass, dirt, moss...) is replaced, then the air filled
                if bs != "minecraft:grass_block":
                    cmds.append("fill %d %d %d %d %d %d %s replace #minecraft:dirt" % (*a, *b, bs))
                cmds.append("fill %d %d %d %d %d %d %s keep" % (*a, *b, bs))
            elif a == b:
                cmds.append("setblock %d %d %d %s keep" % (*a, bs))
            else:
                cmds.append("fill %d %d %d %d %d %d %s keep" % (*a, *b, bs))
    # high and wide first is wrong for hanging things: put supports (lower y) first
    return cmds


if __name__ == "__main__":
    if sys.argv[1] == "stats":
        m = model()
        for s in ("ground", "inside", "outside"):
            n = sum(1 for v in m.values() if v[0] == s)
            print(s, n, "blocks", len(commands(s)), "commands")
    else:
        c = commands(sys.argv[2])
        out = sys.argv[3] if len(sys.argv) > 3 else "/tmp/v2_%s.txt" % sys.argv[2]
        open(out, "w").write("\n".join(c) + "\n")
        print(len(c), "->", out)
