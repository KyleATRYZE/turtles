#!/usr/bin/env python3
"""The storage room proposal page: docs/storage-plan.html.

Lays the storage room out with double chests along both walls, a network
of wired modems hidden behind them, a sorting computer and a touch-screen
terminal at the south end; splits the walls into sections by what the swarm
actually has in stock (from status.json via /tmp/stock.json).
"""
import json, math, os, html as H
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
stock = json.load(open("/tmp/stock.json"))

# ---------------------------------------------------------------- categories
CATS = [  # (name, colour, what goes there, match rules) - first match wins
    ("Magic & modded", "#8a5bb8", "Essences, shards, crystals from magic mods",
     ["mysticalagriculture:", "essence", "theurgy:", "prosperity", "forbidden_arcanus:rune", "stellarite"]),
    ("Ores & raw metal", "#c0763b", "Raw ores and raw ore blocks, waiting to be smelted",
     ["raw_copper", "raw_iron", "raw_gold", "alltheores:raw", "modern_industrialization:raw", "uraninite", "oritech:raw", "_ore"]),
    ("Redstone & tech", "#c24a4a", "Redstone, CC and Advanced Peripherals parts",
     ["redstone", "computercraft:", "advancedperipherals:", "torch", "candle"]),
    ("Fuel", "#454549", "Coal and charcoal: the swarm's fuel tank",
     ["=minecraft:coal", "charcoal", "coal_block"]),
    ("Stone & earth", "#8d8f94", "Cobble, deepslate, dirt, sand, the odd stones",
     ["cobblestone", "cobbled_deepslate", "=minecraft:stone", "andesite", "granite", "diorite", "tuff",
      "basalt", "obsidian", "gravel", "sand", "dirt", "darkstone", "kivi", "marble", "volcanic_ash",
      "magma", "supplementaries:ash", "allthecompressed:", "flint", "ash_vent"]),
    ("Building blocks", "#5b6270", "Bricks, tiles, stairs, glass: what mapper1 builds with",
     ["polished", "brick", "tiles", "stairs", "slab", "glass", "pane", "cut_copper", "copper_block", "sign"]),
    ("Ingots & dusts", "#d4a43a", "Smelted metals, nuggets, dusts",
     ["ingot", "nugget", "dust", "sulfur", "cinnabar", "saltpeter"]),
    ("Gems & crystals", "#4aa3b8", "Diamonds, lapis, modded gems",
     ["diamond", "emerald", "gem", "quartz", "crystal", "ruby", "sapphire", "peridot", "topaz", "garnet",
      "aquamarine", "alexandrite", "turquoise", "heliodor", "opal", "iolite", "bort", "fluorite", "lapis",
      "xychorium", "shard"]),
    ("Wood & plants", "#6f9e3a", "Logs, planks, saplings, seeds: the tree farm's output",
     ["log", "planks", "sapling", "seeds", "stick", "leaves", "fireweed", "thistle", "currant", "fruit"]),
    ("Mob drops", "#b07aa8", "Bones, string, pearls, the stuff mobs leave",
     ["rotten_flesh", "bone", "string", "gunpowder", "ender_pearl", "ender_eye", "leather", "slime", "spider_eye"]),
    ("Overflow", "#b9b2a6", "Anything new, and anything a full section can't take",
     []),
]

def category(name):
    for cname, _, _, rules in CATS:
        for r in rules:
            if r.startswith("="):
                if name == r[1:]:
                    return cname
            elif r.endswith(":"):
                if name.startswith(r):
                    return cname
            elif r in name:
                return cname
    return "Overflow"

stacks, examples = defaultdict(int), defaultdict(list)
for name, n in stock.items():
    c = category(name)
    stacks[c] += math.ceil(n / 64)
    examples[c].append((n, name))
total_stacks = sum(stacks.values())

# ---------------------------------------------------------------- the room
# room inside x 10..17, z 1..29 (from the blueprint). The drone lane takes
# z 1..2 with its screen at z 3. West wall: double chests at x 11, modems and
# cable at x 10. East wall: double chests at x 16, modems at x 17. Both
# partition walls have a doorway at z 14..16; the ladder up is at (17, 29);
# the front desk stands against the south wall at z 29.
Z0, Z1 = 4, 26
DOOR = range(14, 17)
west = [z for z in range(Z0, Z1 + 1) if z not in DOOR]
east = list(west)
def doubles(zs):
    out, i = [], 0
    while i + 1 < len(zs):
        if zs[i + 1] == zs[i] + 1:
            out.append((zs[i], zs[i + 1]))
            i += 2
        else:
            i += 1
    return out
W_D, E_D = doubles(west), doubles(east)
slots_total = (len(W_D) + len(E_D)) * 3 * 54
n_doubles = (len(W_D) + len(E_D)) * 3

# share the double chests out: a small Overflow, the rest by today's stock
# plus a baseline so small sections have room to grow (largest remainder)
order = [c[0] for c in CATS]
OVERFLOW = 4
named = order[:-1]
weights = {c: stacks[c] + 30 for c in named}
room = n_doubles - OVERFLOW
raw = {c: room * weights[c] / sum(weights.values()) for c in named}
alloc = {c: max(1, int(raw[c])) for c in named}
for c in sorted(named, key=lambda c: raw[c] - int(raw[c]), reverse=True):
    if sum(alloc.values()) >= room:
        break
    alloc[c] += 1
alloc["Overflow"] = n_doubles - sum(alloc.values())

# lay sections along the walls: west wall from the north, bottom to top,
# then the east wall
cells = []          # (wall, z1, z2, row) in fill order
for wall, ds in (("west", W_D), ("east", E_D)):
    for (za, zb) in ds:
        for row in (1, 2, 3):
            cells.append((wall, za, zb, row))
assign = {}
k = 0
for c in order:
    for _ in range(alloc[c]):
        if k < len(cells):
            assign[cells[k]] = c
            k += 1
colour = {c[0]: c[1] for c in CATS}

# ---------------------------------------------------------------- SVG: plan view
S = 22                                # px per block
def plan_svg():
    W, Hh = (19 - 8) * S + 330, (31) * S + 20
    ox, oz = 90, 10
    def X(x): return ox + (x - 9) * S
    def Zp(z): return oz + z * S
    p = [f'<svg viewBox="0 0 {W} {Hh}" role="img" aria-labelledby="planT" class="fig">',
         '<title id="planT">Storage room seen from above</title>']
    # walls
    p.append(f'<rect x="{X(9)}" y="{Zp(0)}" width="{10*S}" height="{31*S}" fill="var(--wall)" rx="3"/>')
    p.append(f'<rect x="{X(10)}" y="{Zp(1)}" width="{8*S}" height="{29*S}" fill="var(--floor)"/>')
    # the drone lane behind its screen at the north end
    for z in (1, 2):
        for x in range(10, 18):
            c = "#d87a3a" if (x + z) % 4 < 2 else "#1b1624"
            p.append(f'<rect x="{X(x)}" y="{Zp(z)}" width="{S}" height="{S}" fill="{c}" opacity=".85"/>')
    p.append(f'<rect x="{X(9)}" y="{Zp(1)}" width="{S}" height="{2*S}" fill="var(--floor)"/>')
    p.append(f'<rect x="{X(18)}" y="{Zp(1)}" width="{S}" height="{2*S}" fill="var(--floor)"/>')
    p.append(f'<rect x="{X(10)}" y="{Zp(3)+S*0.4}" width="{8*S}" height="{S*0.2}" fill="#8e959b"/>')
    for x in (10, 14, 17):
        p.append(f'<rect x="{X(x)+3}" y="{Zp(3)+3}" width="{S-6}" height="{S-6}" fill="#4c4c54"/>')
    # doorways in both partitions
    for x in (9, 18):
        p.append(f'<rect x="{X(x)}" y="{Zp(14)}" width="{S}" height="{3*S}" fill="var(--floor)"/>')
    p.append(f'<text x="{X(19)+6}" y="{Zp(15)+S*0.7}" class="lbl">⇄ launch bay</text>')
    p.append(f'<text x="{X(9)-4}" y="{Zp(15)+S*0.7}" class="lbl" text-anchor="end">smelting ⇄</text>')
    for k in range(4):
        p.append(f'<line x1="{X(17)+4}" y1="{Zp(29)+4+k*4.5}" x2="{X(18)-4}" y2="{Zp(29)+4+k*4.5}" stroke="#8a6a3a" stroke-width="2"/>')
    # modem/cable strips
    for x in (10, 17):
        for z in range(Z0, Z1 + 1):
            if z in DOOR:
                continue
            p.append(f'<rect x="{X(x)+3}" y="{Zp(z)+1}" width="{S-6}" height="{S-2}" fill="var(--modem)"/>')
    # chests (top row colour)
    for (wall, za, zb, row) in cells:
        if row != 3:
            continue
        x = 11 if wall == "west" else 16
        c = assign.get((wall, za, zb, 3), "Overflow")
        p.append(f'<rect x="{X(x)+1}" y="{Zp(za)+1}" width="{S-2}" height="{2*S-2}" rx="3" fill="{colour[c]}" stroke="var(--ink)" stroke-opacity=".25"/>')
    # station at the south end
    p.append(f'<rect x="{X(12)+1}" y="{Zp(29)+S-6}" width="{3*S-2}" height="5" rx="2" fill="#1b1d22"/>')
    p.append(f'<rect x="{X(12)+2}" y="{Zp(29)+2}" width="{S-4}" height="{S-8}" rx="3" fill="#a8742c"/>')
    p.append(f'<rect x="{X(14)+2}" y="{Zp(29)+2}" width="{S-4}" height="{S-8}" rx="3" fill="#a8742c"/>')
    p.append(f'<rect x="{X(13)+3}" y="{Zp(29)+2}" width="{S-6}" height="{S-8}" rx="2" fill="#e0c46a"/>')
    # labels on the right
    lx = X(19) + 20
    notes = [
        (Zp(1), "Drone lane, behind its screen"),
        (Zp(5), "Double chests, 3 high, both walls"),
        (Zp(5)+16, "Modems hidden behind (grey strip)"),
        (Zp(20), "Doorways stay clear"),
        (Zp(20)+16, "4-block aisle down the middle"),
        (Zp(27)+2, "Front desk: In · Sortnado · Out"),
        (Zp(27)+18, "5 × 3 touch screen above"),
        (Zp(29)+12, "Ladder up (south-east corner)"),
    ]
    for y, t in notes:
        p.append(f'<text x="{lx}" y="{y+12}" class="lbl">{H.escape(t)}</text>')
    # flow arrows
    p.append(f'<path d="M{X(12)+S/2},{Zp(29)} C{X(12)+S/2},{Zp(23)} {X(12)+S*0.4},{Zp(13)} {X(12)+S*0.1},{Zp(8)}" class="flow" marker-end="url(#ar)"/>')
    p.append(f'<path d="M{X(16)-2},{Zp(9)} C{X(15)},{Zp(18)} {X(15)},{Zp(24)} {X(14)+S/2},{Zp(29)}" class="flow out" marker-end="url(#ar2)"/>')
    p.append('<defs><marker id="ar" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto"><path d="M0,0L10,5L0,10z" fill="#2f8a74"/></marker>'
             '<marker id="ar2" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto"><path d="M0,0L10,5L0,10z" fill="#c26a2e"/></marker></defs>')
    p.append(f'<text x="{X(12)+S*0.9}" y="{Zp(26)}" class="lbl small" fill="#2f8a74" transform="rotate(-88 {X(12)+S*0.9} {Zp(26)})">sorted away</text>')
    p.append(f'<text x="{X(15)+4}" y="{Zp(19)}" class="lbl small" fill="#c26a2e" transform="rotate(80 {X(15)+4} {Zp(19)})">what you ask for</text>')
    p.append('<text x="{0}" y="{1}" class="lbl small">N ↑</text>'.format(X(9), Zp(0) - 2))
    p.append('</svg>')
    return "\n".join(p)

# ---------------------------------------------------------------- SVG: wall elevations
def wall_svg(wall, ds, title):
    cw = 30
    zs = list(range(Z0, Z1 + 1))
    W = len(zs) * cw + 60
    Hh = 3 * cw + 70
    p = [f'<svg viewBox="0 0 {W} {Hh}" role="img" aria-label="{H.escape(title)}" class="fig wall">']
    flip = wall == "west"                 # facing west, north is on your right
    def Xz(z): return 40 + ((Z1 - z) if flip else (z - Z0)) * cw
    def Xspan(za, zb): return min(Xz(za), Xz(zb))
    def Yr(r): return 34 + (3 - r) * cw
    # the cable run along the top
    p.append(f'<rect x="40" y="{Yr(3)-12}" width="{len(zs)*cw}" height="6" rx="3" fill="var(--modem)"/>')
    p.append(f'<text x="40" y="{Yr(3)-18}" class="lbl small">modem strip behind, joined under the floor to the desk and crafter1</text>')
    for (za, zb) in ds:
        for row in (1, 2, 3):
            c = assign.get((wall, za, zb, row), "Overflow")
            x0 = Xspan(za, zb)
            p.append(f'<rect x="{x0+2}" y="{Yr(row)+2}" width="{2*cw-4}" height="{cw-4}" rx="4" fill="{colour[c]}"><title>{H.escape(c)}</title></rect>')
            p.append(f'<line x1="{x0+cw}" y1="{Yr(row)+6}" x2="{x0+cw}" y2="{Yr(row)+cw-6}" stroke="#000" stroke-opacity=".25"/>')
    if True:
        p.append(f'<rect x="{min(Xz(14), Xz(16))+2}" y="{Yr(3)+2}" width="{3*cw-4}" height="{3*cw-4}" rx="4" fill="var(--floor)" stroke="var(--line)" stroke-dasharray="4 3"/>')
        p.append(f'<text x="{Xz(15)+cw/2}" y="{Yr(2)+cw*0.62}" class="lbl small" text-anchor="middle">doorway</text>')
    for z in (Z0, 10, 20, Z1):
        pass
    for z in (Z0, 10, 20, Z1):
        p.append(f'<text x="{Xz(z)+cw/2}" y="{Yr(1)+cw+16}" class="lbl small" text-anchor="middle">z{z}</text>')
    p.append('</svg>')
    return "\n".join(p)

# ---------------------------------------------------------------- terminal mock-up (CC style)
def terminal():
    used, tot = total_stacks, n_doubles * 54
    rows = [
        ("hdr", f" STORAGE      {used:,} / {tot:,} slots   {round(100*used/tot)}% ".ljust(45)),
        ("", ""),
        ("srch", " Search: dia_                            "),
        ("", ""),
        ("hit", " Diamond                 185   [16][64][All]"),
        ("row", " Diamond block             0                "),
        ("row", " Diamond pickaxe           1                "),
        ("", ""),
        ("tab", " Ores  Ingots  Gems  Stone  Build  Wood  Fuel "),
        ("", ""),
        ("key", " A  B  C  D  E  F  G  H  I  J  K  L  M  <    "),
        ("key", " N  O  P  Q  R  S  T  U  V  W  X  Y  Z  CLR  "),
        ("foot", " Out chest: 64 diamond ready.   Tap to search "),
    ]
    out = ['<div class="mon" role="img" aria-label="Mock-up of the storage touch screen"><div class="mon-in">']
    for cls, t in rows:
        out.append(f'<div class="ln {cls}">{H.escape(t) or "&nbsp;"}</div>')
    out.append('</div></div>')
    return "".join(out)

# ---------------------------------------------------------------- page
rows = []
for c in order:
    ex = ", ".join(n.split(":")[1].replace("_", " ") for _, n in sorted(examples[c], reverse=True)[:4]) or "-"
    desc = next(d for name, _, d, _ in CATS if name == c)
    rows.append(f'<tr><td><span class="sw" style="background:{colour[c]}"></span>{c}</td><td>{H.escape(desc)}<div class="ex">now: {H.escape(ex)}</div></td>'
                f'<td class="num">{stacks[c]}</td><td class="num">{alloc[c]}</td><td class="num">{alloc[c]*54:,}</td></tr>')
modems = n_doubles
strip = 2 * len(west)                    # bottom-row strip positions, both walls
cables = (strip - (len(W_D) + len(E_D))) + 40   # gaps in the strip + under-floor runs
legend = "\n".join(f'<li><span class="sw" style="background:{colour[c]}"></span>{c}</li>' for c in order)
TIERS = [("Vanilla chests (to start)", 27), ("Sophisticated: copper", 45), ("Sophisticated: iron", 54),
         ("Sophisticated: gold", 81), ("Sophisticated: diamond", 108), ("Sophisticated: netherite", 132)]
blocks = n_doubles * 2
grow = "\n".join(f'<tr><td>{n}</td><td class="num">{k}</td><td class="num">{blocks*k:,}</td>'
                 f'<td class="num">{blocks*k/total_stacks:.0f}×</td></tr>' for n, k in TIERS)
page = open(os.path.join(ROOT, "tools", "storageplan_template.html")).read()
page = page.replace("{{GROW}}", grow)
page = (page.replace("{{PLAN}}", plan_svg())
            .replace("{{WEST}}", wall_svg("west", W_D, "West wall"))
            .replace("{{EAST}}", wall_svg("east", E_D, "East wall"))
            .replace("{{TERMINAL}}", '<img class="screen" src="store-screen.gif" alt="The storage touch screen as dash.lua draws it: capacity bar, search box, matching items with 16 / 64 / All buttons, sections with fill bars, keyboard and an Out chest note.">')
            .replace("{{ROWS}}", "\n".join(rows))
            .replace("{{N_DOUBLE}}", str(n_doubles))
            .replace("{{SLOTS}}", f"{slots_total:,}")
            .replace("{{STACKS}}", f"{total_stacks:,}")
            .replace("{{KINDS}}", str(len(stock)))
            .replace("{{CHESTS}}", str(n_doubles * 2))
            .replace("{{PLANKS}}", f"{n_doubles*2*8:,}")
            .replace("{{LOGS}}", f"{n_doubles*2*2:,}")
            .replace("{{MODEMS}}", str(modems))
            .replace("{{CABLES}}", str(round(cables, -1)))
            .replace("{{LEGEND}}", legend)
            .replace("{{JUNK}}", str(sum(math.ceil(stock.get(k, 0) / 64) for k in (
                "forbidden_arcanus:darkstone", "xycraft_world:kivi", "astralsorcery:marble_raw", "regions_unexplored:volcanic_ash")))))
open(os.path.join(ROOT, "docs", "storage-plan.html"), "w").write(page)
print("doubles", n_doubles, "slots", slots_total, "stacks now", total_stacks)
print({c: (stacks[c], alloc[c]) for c in order})
