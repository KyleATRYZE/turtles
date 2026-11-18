#!/usr/bin/env python3
"""Run dash.lua against a simulated advanced monitor and render what it
draws with CC's own font, so the mock-ups are exactly what the wall shows.

  python3 dashrender.py <status.json> <maps dir> <out dir>
"""
import json, math, os, sys, time
from lupa import LuaRuntime
from PIL import Image, ImageDraw

REPO = "/home/claude/turtles"
FONT = Image.open("/tmp/ccfont/term_font.png").convert("RGBA")
status = json.load(open(sys.argv[1]))
MAPS = sys.argv[2]
OUT = sys.argv[3]
os.makedirs(OUT, exist_ok=True)

lua = LuaRuntime(encoding="latin-1", unpack_returned_tuples=True)
lua.execute(f'package.path = "{REPO}/?.lua;" .. package.path')
dash = lua.eval('(require("dash"))')
lua.execute('''
function makeMon(bw, bh)
  local m = { scale = 1, rows = {}, pal = {}, bw = bw, bh = bh }
  local function size()
    local w = math.floor((bw - 0.3125) / (m.scale * 6 / 64) + 0.5)
    local h = math.floor((bh - 0.3125) / (m.scale * 9 / 64) + 0.5)
    return math.max(w, 1), math.max(h, 1)
  end
  m.setTextScale = function(s) m.scale = s end
  m.getSize = function() return size() end
  m.setPaletteColour = function(c, hex) m.pal[#m.pal + 1] = { c, hex } end
  m.setCursorPos = function(x, y) m.cy = y end
  m.blit = function(t, f, b) m.rows[m.cy] = { t, f, b } end
  return m
end
''')

def tolua(o):
    if isinstance(o, dict):
        return lua.table_from({k: tolua(v) for k, v in o.items()})
    if isinstance(o, list):
        return lua.table_from([tolua(v) for v in o])
    return o

# ---------------------------------------------------------------- render
def glyph(code, fg, bg):
    g = Image.new("RGB", (6, 9), bg)
    if 128 <= code < 160:
        bits = code - 128
        d = ImageDraw.Draw(g)
        for i, (gx, gy) in enumerate([(0, 0), (3, 0), (0, 3), (3, 3), (0, 6)]):
            if bits & (1 << i):
                d.rectangle([gx, gy, gx + 2, gy + 2], fill=fg)
        return g
    sx, sy = 1 + (code % 16) * 8, 1 + (code // 16) * 11
    mask = FONT.crop((sx, sy, sx + 6, sy + 9)).getchannel("A")
    g.paste(Image.new("RGB", (6, 9), fg), (0, 0), mask)
    return g

def render(mon, path, zoom=2, bezel=True):
    pal = {}
    for v in mon.pal.values():
        c, hexv = v[1], v[2]
        pal[int(round(math.log2(c)))] = (int(hexv) >> 16 & 255, int(hexv) >> 8 & 255, int(hexv) & 255)
    rows = mon.rows
    h = max(rows.keys())
    w = len(rows[1][1])
    img = Image.new("RGB", (w * 6, h * 9))
    cache = {}
    for y in range(1, h + 1):
        t, f, b = rows[y][1], rows[y][2], rows[y][3]
        for x in range(w):
            key = (ord(t[x]), f[x], b[x])
            if key not in cache:
                cache[key] = glyph(ord(t[x]), pal[int(f[x], 16)], pal[int(b[x], 16)])
            img.paste(cache[key], (x * 6, y * 9 - 9))
    img = img.resize((img.width * zoom, img.height * zoom), Image.NEAREST)
    if bezel:
        # the monitor's own margin (in the edge colour) and its gold frame
        px_per_block = 6 * zoom / (mon.scale * 6 / 64)
        m = int(px_per_block * 0.5 / 16)
        b = int(px_per_block * 2 / 16)
        edge = pal[int(rows[1][3][0], 16)]
        framed = Image.new("RGB", (img.width + 2 * (m + b), img.height + 2 * (m + b)), (201, 162, 39))
        d = ImageDraw.Draw(framed)
        d.rectangle([0, 0, framed.width - 1, framed.height - 1], outline=(140, 108, 18), width=max(2, b // 5))
        d.rectangle([b, b, framed.width - b - 1, framed.height - b - 1], fill=edge)
        framed.paste(img, (b + m, b + m))
        img = framed
    img.save(path)
    return img.size

# ---------------------------------------------------------------- the data
units = {}
for k, u in status["units"].items():
    u = dict(u); u.pop("inv", None)
    units[k] = u
forge = next(u for u in units.values() if u.get("label") == "crafter1")
brick = next(u for u in units.values() if u.get("label") == "mapper1")
f = forge["base"]["f"]
PLOT, KEEP = 8, 24
def plot_origin(index):
    n = 0
    for r in range(0, 81):
        for gx in range(-r, r + 1):
            for gz in range(-r, r + 1):
                if max(abs(gx), abs(gz)) == r:
                    x0, z0 = f["x"] + gx * PLOT, f["z"] + gz * PLOT
                    if (f["x"] < x0 - KEEP or f["x"] > x0 + PLOT - 1 + KEEP or
                            f["z"] < z0 - KEEP or f["z"] > z0 + PLOT - 1 + KEEP):
                        n += 1
                        if n == index:
                            return x0, z0
fleet = forge["fleet"]
active_idx = set(fleet["byId"].values())
done = [list(plot_origin(i)) for i in range(1, fleet["nextPlot"]) if i not in active_idx]
active = [list(plot_origin(i)) for i in sorted(active_idx)]
maps = []
for name in ("factory_site", "meadow", "ground"):
    m = json.load(open(os.path.join(MAPS, name + ".json")))["data"]
    maps.append({"origin": m["origin"], "size": m["size"], "heights": m["heights"],
                 "names": m["names"], "palette": m["palette"]})
pr = brick.get("progress") or {}
COL = {"crafter1": 8, "mapper1": 6, "Coalition": 11, "Ghastly": 7}
events = []
for u in sorted(units.values(), key=lambda u: -u.get("seen", 0)):
    if u.get("log"):
        events.append([u["label"], u["log"][-1], COL.get(u["label"], 9)])
now = max(u.get("seen", 0) for u in units.values())
data = {
    "units": units, "maps": maps,
    "base": {"x": f["x"], "y": f["y"], "z": f["z"]},
    "site": {1: -4448, 2: 1518, 3: -4404, 4: 1548, "progress": pr.get("done", 0) / max(1, pr.get("total", 1)),
             "layer": pr.get("layer"), "layers": 37, "done": pr.get("done"), "total": pr.get("total")},
    "hut": {1: -4464, 2: 1518, 3: -4458, 4: 1532},
    "plots": {"size": 8, "done": done, "active": active},
    "factory": {"coal": 870, **forge.get("storage", {})},
    "clock": time.strftime("%H:%M", time.gmtime(now / 1000)),
    "now": now, "updated": "updated 2s ago", "events": events, "huntRange": 48,
}
def ltab(d):
    if isinstance(d, dict) and all(isinstance(k, int) for k in d):
        t = lua.table()
        for k, v in d.items():
            t[k] = tolua(v)
        return t
    if isinstance(d, dict):
        t = lua.table()
        for k, v in d.items():
            t[k] = ltab(v) if isinstance(v, dict) else tolua(v)
        return t
    return tolua(d)

import copy
flyer = next((u for u in units.values() if "flying" in u.get("state", "")), None)
start = dict(flyer["pos"]) if flyer else None
frames = []
N = 40
for i in range(N):
    d = copy.deepcopy(data)
    if flyer:   # demo only: walk it home along its line, leaving a trail
        k = min(1, i / (N - 6))
        u = next(v for v in d["units"].values() if v["label"] == flyer["label"])
        u["pos"]["x"] = round(start["x"] + (f["x"] - start["x"]) * k)
        u["pos"]["z"] = round(start["z"] + (f["z"] - start["z"]) * k)
        d["trails"] = {flyer["label"]: [[round(start["x"] + (f["x"] - start["x"]) * min(1, j / (N - 6))),
                                         round(start["z"] + (f["z"] - start["z"]) * min(1, j / (N - 6)))]
                                        for j in range(max(0, i - 6), i, 2)]}
    wall = lua.eval("makeMon")(9, 4)
    t0 = time.time()
    dash.wall(wall, ltab(d), i)
    dt = time.time() - t0
    render(wall, os.path.join(OUT, "f.png"), zoom=1)
    frames.append(Image.open(os.path.join(OUT, "f.png")).convert("P", palette=Image.ADAPTIVE, colors=32))
    if i == 7:
        print("wall frame drawn in", round(dt, 3), "s", render(wall, os.path.join(OUT, "wall.png")))
frames[0].save(os.path.join(OUT, "wall.gif"), save_all=True, append_images=frames[1:], duration=250, loop=0, optimize=True)
print("gif", os.path.getsize(os.path.join(OUT, "wall.gif")) // 1024, "KB")

for name, g in (("gate_idle", {"left": "OUT", "right": "IN"}),
                ("gate_out", {"left": "OUT", "right": "IN", "active": "OUT", "frame": 1}),
                ("gate_in", {"left": "OUT", "right": "IN", "active": "IN", "frame": 2})):
    m = lua.eval("makeMon")(2, 1)
    dash.gate(m, ltab(g))
    print(name, render(m, os.path.join(OUT, name + ".png"), zoom=3))

# the rack: everyone's slot, by name; who's home is lit
labels = sorted(u["label"] for u in units.values() if u.get("role") != "factory")
slots = []
for i in range(8):
    slot = {}
    for k, which in enumerate(("upper", "lower")):
        j = i * 2 + k
        if j < len(labels):
            u = dict(next(v for v in units.values() if v["label"] == labels[j]))
            u["home"] = u["label"] == "Ghastly"
            u["where"] = "plot" if u.get("state") == "mining" else ""
            slot[which] = u
    slots.append(slot)
m = lua.eval("makeMon")(8, 1)
dash.rack(m, ltab({i + 1: ltab(s) for i, s in enumerate(slots)}), now)
print("rack", render(m, os.path.join(OUT, "rack.png"), zoom=2))

SECS = [("Magic", 93, 6), ("Ores", 118, 8), ("Redstone", 89, 6), ("Fuel", 14, 2), ("Stone", 294, 17), ("Build", 32, 3),
        ("Ingots", 24, 3), ("Gems", 96, 7), ("Wood", 10, 2), ("Mobs", 4, 2), ("Overflow", 3, 4)]
tiles = []
for name, used, n in SECS:
    left = used
    for k in range(n):
        got = min(54, left); left -= got
        tiles.append({"section": name, "share": got / 54, "hit": name == "Gems" and k in (0, 1)})
def wallof(ts, flip):
    cols = [{r + 1: ts[c * 3 + r] for r in range(3)} for c in range(10)]
    if flip: cols.reverse()
    return {i + 1: c for i, c in enumerate(cols)}
num = lambda l: {i + 1: (num(v) if isinstance(v, list) else v) for i, v in enumerate(l)}
store = {
    "used": 777, "slots": 3240, "kinds": 117, "query": "dia", "where": "2 chests",
    "results": num([{"name": "Diamond", "count": 185, "section": "Gems"}, {"name": "Dimensional shard", "count": 149, "section": "Gems"},
                    {"name": "Diorite", "count": 41, "section": "Stone"}, {"name": "Diamond pickaxe", "count": 1, "section": "Overflow"}]),
    "sections": num([{"name": n, "used": u, "slots": c * 54} for n, u, c in SECS]),
    "walls": {"west": wallof(tiles[:30], True), "east": wallof(tiles[30:], False)},
    "feed": num([["OUT", 64, "Diamond", "Gems"], ["IN", 128, "Cobbled deepslate", "Stone"], ["IN", 37, "Raw osmium", "Ores"],
                 ["IN", 64, "Redstone", "Redstone"], ["OUT", 16, "Glass", "Build"], ["IN", 12, "Coal", "Fuel"]]),
    "inbox": "empty: all sorted", "outbox": "64 Diamond", "ready": "64 Diamond ready in the Out chest",
}
frames = []
for i in range(12):
    m = lua.eval("makeMon")(5, 3)
    dash.store(m, ltab(store), i)
    render(m, os.path.join(OUT, "f.png"), zoom=2)
    frames.append(Image.open(os.path.join(OUT, "f.png")).convert("P", palette=Image.ADAPTIVE, colors=32))
    if i == 0:
        print("store", lua.eval("function(m) return m.getSize() end")(m), render(m, os.path.join(OUT, "store.png"), zoom=2))
frames[0].save(os.path.join(OUT, "store.gif"), save_all=True, append_images=frames[1:], duration=250, loop=0, optimize=True)
