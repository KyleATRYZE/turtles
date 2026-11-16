#!/usr/bin/env python3
"""Pictures of what the stations (screens.lua) draw, from a status file:
the wall, both touch panels, the rack board and a gate light, rendered with
CC's own font.

  python3 test/screenshots.py <status.json> <maps dir or -> <out dir> [font.png]
"""
import json, math, os, sys
from lupa import LuaRuntime
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(HERE)
status = json.load(open(sys.argv[1]))
MAPS, OUT = sys.argv[2], sys.argv[3]
FONT = Image.open(sys.argv[4] if len(sys.argv) > 4 else "/tmp/ccfont/term_font.png").convert("RGBA")
os.makedirs(OUT, exist_ok=True)

L = LuaRuntime(encoding="latin-1", unpack_returned_tuples=True)
L.execute(r'''
package.path = "%s/?.lua;" .. package.path
NOW, CLOCK = %d, 1000
os.epoch = function() return NOW end
os.clock = function() return CLOCK end
os.date = function() return "23:41" end
os.getComputerID = function() return 31 end
os.getComputerLabel = function() return "station-31" end
fs = { exists = function() return false end }
rednet = { broadcast = function() end }
function makeMon(bw, bh)
  local m = { scale = 1, rows = {}, pal = {}, bw = bw, bh = bh }
  m.setTextScale = function(s) m.scale = s end
  m.getSize = function()
    return math.max(1, math.floor((bw - 0.3125) / (m.scale * 6 / 64) + 0.5)),
           math.max(1, math.floor((bh - 0.3125) / (m.scale * 9 / 64) + 0.5))
  end
  m.setPaletteColour = function(c, hex) m.pal[#m.pal + 1] = { c, hex } end
  m.setCursorPos = function(x, y) m.cy = y end
  m.blit = function(t, f, b) m.rows[m.cy] = { t, f, b } end
  return m
end
SCREENS_TEST = true
SCR = dofile("%s/screens.lua")
''' % (ROOT, max((u.get("seen") or 0) for u in status["units"].values()) + 1500, ROOT))

def tolua(o):
    if isinstance(o, dict): return L.table_from({k: tolua(v) for k, v in o.items()})
    if isinstance(o, list): return L.table_from([tolua(v) for v in o])
    return o

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

def render(mon, path, zoom=2):
    pal = {}
    for v in mon.pal.values():
        pal[int(round(math.log2(v[1])))] = (int(v[2]) >> 16 & 255, int(v[2]) >> 8 & 255, int(v[2]) & 255)
    rows = mon.rows
    h = max(rows.keys()); w = len(rows[1][1])
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
    img.save(path)
    return img.size

S = L.globals().SCR
units = {}
for k, u in status["units"].items():
    u = dict(u); u.pop("lab", None)
    units[k] = u
if MAPS != "-":
    for i, name in enumerate(("factory_site", "meadow", "ground")):
        p = os.path.join(MAPS, name + ".json")
        if os.path.exists(p):
            m = json.load(open(p)); m = m.get("data", m)
            S.S.maps[i + 1] = tolua({"name": name, "origin": m["origin"], "size": m["size"],
                                     "heights": m["heights"], "names": m["names"], "palette": m["palette"]})
def hear(seen=None):
    for k, u in units.items():
        S.hear(int(k) if k.isdigit() else 0, tolua(u))
        if seen is None: S.S.units[k].seen = u.get("seen")
hear()
shots = [("wall", 5, 9, 4, 1), ("panel_tower", 6, 3, 2, 3), ("panel_bay", 4, 2, 2, 3), ("rack", 3, 8, 1, 2), ("gate", 1, 2, 1, 4)]
for name, post, bw, bh, zoom in shots:
    mon = L.eval("makeMon(%d, %d)" % (bw, bh))
    for _ in range(3): S.draw(L.eval("SCR.POSTS[%d]" % post), mon)
    print(name, render(mon, os.path.join(OUT, name + ".png"), zoom))
# gone quiet: the same wall three minutes after the last report
L.execute("CLOCK = CLOCK + 200 NOW = NOW + 200000")
mon = L.eval("makeMon(9, 4)")
S.draw(L.eval("SCR.POSTS[5]"), mon)
print("wall_quiet", render(mon, os.path.join(OUT, "wall_quiet.png"), 1))
