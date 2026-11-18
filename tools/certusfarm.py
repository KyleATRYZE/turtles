#!/usr/bin/env python3
"""The certus farm and the AE2 bench: certus quartz grown on budding blocks,
harvested by a drone, and the machines that turn it into the ME network's
parts (docs/ae2-bootstrap.md, build guide docs/certus-build.html).

    python3 tools/certusfarm.py map  [opts]          the farm, layer by layer
    python3 tools/certusfarm.py kyle [opts]          what Kyle places, in order (world coordinates)
    python3 tools/certusfarm.py harvest [opts]       lab steps: pick every full-grown cluster
    python3 tools/certusfarm.py survey [opts]        lab steps: geo-scan the budding blocks' tiers
    python3 tools/certusfarm.py bench [opts]         lab steps: place the charger and inscribers, presses in
    python3 tools/certusfarm.py charge N [opts]      lab steps: N certus crystals through the charger
    python3 tools/certusfarm.py fluix N [opts]       lab steps: charge N, then N charged + N redstone + N
                                                     nether quartz into the basin: 2N fluix
    python3 tools/certusfarm.py print KIND N [opts]  lab steps: N printed circuits (silicon logic calc eng)
    python3 tools/certusfarm.py proc KIND N [opts]   lab steps: N processors (logic calc eng) in the mill
    python3 tools/certusfarm.py grind ITEM N [opts]  lab steps: N crystals to dust in the mill (certus, fluix)
    python3 tools/certusfarm.py chips L C E [opts]   lab steps: L logic, C calculation, E engineering processors
                                                     in one trip: all four presses print at once, then the
                                                     mill presses the processors (silicon, gold, certus,
                                                     diamond, redstone from the store)
    python3 tools/certusfarm.py cells N [opts]       lab steps: N 1k item cells into the AE2 room's drive
    python3 tools/certusfarm.py bridgeclick [opts]   lab steps: switch the ME Bridge's floor modem on, from
                                                     its click hole (after the ae2 fit has put the bridge on it)
    python3 tools/certusfarm.py renew SLOTS [opts]   lab steps: dead blocks (plain quartz blocks) dug,
                                                     made flawed again in the basin, put back (SLOTS: 0,3,5)
    python3 tools/certusfarm.py first [opts]         lab steps: the first harvest and the first fluix batch
    python3 tools/certusfarm.py page                 writes docs/certus-build.html
    opts: farm=x,y,z,back  (the first budding block, and the side its column backs onto:
          east west north south)  sides=2  cols=2  tiers=3  fill=9
          bench=v2|now  (or bench=x,y,z,dir: six cells in a row)  side=right  pick=minecraft:diamond_pickaxe

Each lab command prints the ops string for:
    tools/order.py lab <helper> clear=1 "ops=..."

THE FARM (a module; where it stands is the farm= option). Budding blocks in
columns, three tiers high (y +0, +3, +6) and every third block along the
row, so no two share a cell to grow into. Each column backs onto a "back"
column: a stone pillar now (Kyle places the budding blocks against it),
growth accelerators and cable later (one accelerator ticks the budding
blocks on both its sides). With sides=2 a second column of budding blocks
stands on the pillar's other side, mirrored. Every budding block's other
faces are open and each has a drone's stand beside it:

    seen from the end (sides=2):   corridor | budding | pillar | budding | corridor
    y +7   stand (up cluster, front)      .   o   P   o   .
    y +6   tier 3                         c   B   P   B   c
    y +5   stand                          .   o   P   o   .
    y +4   stand                          .   o   P   o   .
    y +3   tier 2                         c   B   P   B   c
    y +2   stand                          .   o   P   o   .
    y +1   stand                          .   o   P   o   .
    y  0   tier 1 (on the floor)          c   B   P   B   c
    B budding, o a cluster cell (up/down), c a cluster cell (out face), P pillar

    along the row (one tier): end cells e on both sides of each budding block
         a: -1  0  1  2  3  4  5  6
            e   B  e  e  B  e  .  ~      ~ the basin (one floor block of water), under the pillar line

The drone never stands in a cell next to a budding block, so nothing ever
grows where it stands or moves. It only digs a cell holding exactly
ae2:quartz_cluster (the lab verb pick); budding blocks are never dug.

THE BENCH: four inscribers with a press each (silicon, logic, calc, eng), the
mill (an inscriber with no press: crystals to dust, and the processors), and
the charger, each powered from below (FE: Mekanism cable), worked by a drone
from above (dropDown / suckDown).
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

OX, OY, OZ = -4448, 71, 1518
SITE = f"site|{OX}|{OY}|{OZ}|factory_asfit3|factory_foundryfloor"

BUD = "ae2:flawed_budding_quartz"
CLUSTER = "ae2:quartz_cluster"
QBLOCK = "ae2:quartz_block"
BUDS = "ae2:small_quartz_bud,ae2:medium_quartz_bud,ae2:large_quartz_bud," + CLUSTER
CRYSTAL, CHARGED = "ae2:certus_quartz_crystal", "ae2:charged_certus_quartz_crystal"
DUST, FLUIX, FDUST = "ae2:certus_quartz_dust", "ae2:fluix_crystal", "ae2:fluix_dust"
REDSTONE, NQUARTZ, SILICON = "minecraft:redstone", "minecraft:quartz", "ae2:silicon"
PILLAR = "minecraft:stone_bricks"
WATER, BUCKET = "minecraft:water_bucket", "minecraft:bucket"
GEO = "advancedperipherals:geo_scanner"
CHARGER, INSCRIBER = "ae2:charger", "ae2:inscriber"
PRESS = {"silicon": "ae2:silicon_press", "logic": "ae2:logic_processor_press",
         "calc": "ae2:calculation_processor_press", "eng": "ae2:engineering_processor_press"}
PRINTS = {"silicon": (SILICON, "ae2:printed_silicon"), "logic": ("minecraft:gold_ingot", "ae2:printed_logic_processor"),
          "calc": (CRYSTAL, "ae2:printed_calculation_processor"), "eng": ("minecraft:diamond", "ae2:printed_engineering_processor")}
PROCS = {"logic": "ae2:logic_processor", "calc": "ae2:calculation_processor", "eng": "ae2:engineering_processor"}
GRIND = {"certus": (CRYSTAL, DUST), "fluix": (FLUIX, FDUST)}

VEC = {"east": (1, 0), "south": (0, 1), "west": (-1, 0), "north": (0, -1)}
FACE = {(1, 0): 0, (0, 1): 1, (-1, 0): 2, (0, -1): 3}          # lab face|n: east south west north
CW = {"east": "south", "south": "west", "west": "north", "north": "east"}

# where things stand, by default: docs/foundry-v2.md's certus farm zone (x 28-34,
# z 6-13: corridors x 28 and x 32, budding columns x 29 and x 31, the pillars x 30,
# rows z 7 and 10; the harvester comes in from the north walkway, z 5) and its
# AE2 room (inscribers and the charger on the west wall, x 28, z 18-23).
# "now": on today's plinth cable (x 42, y 1, z 11-16: docs/foundry.md), until
# the hall is rebuilt.
FARM = (29, 1, 7, "east")
BENCHES = {
    "v2": ((28, 1, 18), "south"),
    "now": ((42, 2, 11), "south"),
}
BENCH_ORDER = ["silicon", "logic", "calc", "eng", "charger", "mill"]
SECONDS_PER_PRINT = 6          # 116 ticks with no speed card (AE2 InscriberBlockEntity)
SECONDS_PER_CHARGE = 4         # 1,600 AE stored, then a 1-in-5 chance every 10 ticks
CHARGE_PATIENCE = 15           # keep trying the charger this long (seconds) for each crystal
                               # (0.8^28 after 15 s: none is ever left in it)
TRIP = 64                      # crystals (and redstone, nether quartz) a drone takes on one fluix trip
DRIVE = (32, 1, 19)            # the AE2 room's first drive (tools/foundry2plans.py AE2_ROOM)
BRIDGE_MODEM, BRIDGE_HOLE = (34, 0, 21), (34, 0, 22)
CELL1K = "ae2:item_storage_cell_1k"


# ================================================================= geometry
class Farm:
    def __init__(self, x=FARM[0], y=FARM[1], z=FARM[2], back=FARM[3], sides=2, cols=2, tiers=3, fill=9):
        self.o, self.back = (x, y, z), back
        self.A = VEC[CW[back]]                       # along the row
        bx, bz = VEC[back]
        self.O = (-bx, -bz)                          # outward (toward the primary corridor)
        self.sides, self.cols, self.tiers = sides, cols, tiers
        self.fill = fill

    # local (a along, h up, b outward) -> building cell
    def at(self, a, h, b):
        return (self.o[0] + a * self.A[0] + b * self.O[0], self.o[1] + h, self.o[2] + a * self.A[1] + b * self.O[1])

    def side_cols(self, s):
        """(budding column b, corridor b) of side s (+1 primary, -1 mirrored)."""
        bb = 0 if s == 1 else -2
        return bb, bb + s

    def sides_list(self):
        return [1, -1][:self.sides]

    def slots(self):
        """Every budding slot: (index, i, t, s) bottom tier first."""
        out = []
        for t in range(self.tiers):
            for s in self.sides_list():
                for i in range(self.cols):
                    out.append((len(out), i, t, s))
        return out

    def slot_cell(self, i, t, s):
        return self.at(3 * i, 3 * t, self.side_cols(s)[0])

    def filled(self):
        return [sl for sl in self.slots() if sl[0] < self.fill]

    def clusters(self, i, t, s):
        """The cells slot (i, t, s) grows into: name -> cell."""
        a, h = 3 * i, 3 * t
        bb, bc = self.side_cols(s)
        c = {"end-": self.at(a - 1, h, bb), "end+": self.at(a + 1, h, bb), "out": self.at(a, h, bc),
             "up": self.at(a, h + 1, bb)}
        if t > 0:
            c["down"] = self.at(a, h - 1, bb)
        return c

    def pillars(self):
        """The back column: a pillar at each budding row, floor to the top tier."""
        return [self.at(3 * i, h, -1) for i in range(self.cols) for h in range(0, 3 * (self.tiers - 1) + 1)]

    def accelerators(self):
        return [self.at(3 * i, 3 * t, -1) for i in range(self.cols) for t in range(self.tiers)]

    def basin(self):
        """(water cell in the floor, the stand over it)."""
        a = 3 * self.cols
        return self.at(a, -1, -1), self.at(a, 0, -1)

    def cross(self):
        return 3 * self.cols - 1                     # the row (a) the drone crosses between corridors

    def approach(self):
        """Where the harvest starts: the primary corridor, a row before the first ends."""
        return self.at(-2, 1, 1)

    def face(self, v):
        return FACE[v]

    def along(self, sign=1):
        return FACE[(self.A[0] * sign, self.A[1] * sign)]

    def wallward(self, s):
        """Facing from side s's corridor toward its budding column."""
        return FACE[(-self.O[0] * s, -self.O[1] * s)]

    def box(self):
        cells = [self.at(a, h, b) for a in range(-2, 3 * self.cols + 1) for h in range(-1, 3 * self.tiers)
                 for b in range(-3 if self.sides == 2 else -1, 2)]
        xs, ys, zs = zip(*cells)
        return min(xs), max(xs), min(ys), max(ys), min(zs), max(zs)


def opts(args):
    o = {"side": "right", "pick": "minecraft:diamond_pickaxe", "bench": "v2", "sides": "2", "cols": "2",
         "tiers": "3", "fill": "9"}
    for a in args:
        if "=" in a:
            k, v = a.split("=", 1)
            o[k] = v
    return o


def farm_of(o):
    if "farm" in o:
        x, y, z, back = o["farm"].split(",")
        x, y, z = int(x), int(y), int(z)
    else:
        x, y, z, back = FARM
    return Farm(x, y, z, back, int(o["sides"]), int(o["cols"]), int(o["tiers"]), int(o["fill"]))


def bench_of(o):
    """name -> cell (the machine), and the stand over it."""
    b = o.get("bench", "v2")
    if b in BENCHES:
        (x, y, z), d = BENCHES[b]
    else:
        x, y, z, d = b.split(",")
        x, y, z = int(x), int(y), int(z)
    dx, dz = VEC[d]
    return {n: (x + i * dx, y, z + i * dz) for i, n in enumerate(BENCH_ORDER)}


def walk(c):
    return f"walk|{c[0]}|{c[1]}|{c[2]}"


def fetch(items, dump=True):
    return "fetch|" + ",".join(f"{k}={v}" for k, v in items.items()) + ("|dump" if dump else "")


def above(c):
    return (c[0], c[1] + 1, c[2])


# ================================================================= the harvest
def harvest_side(F, s, s_ops):
    """The three passes along one side's corridor (the drone starts at a=-1,
    h=1 in it, ends at the far end, h=1)."""
    bb, bc = F.side_cols(s)
    last = 3 * (F.cols - 1) + 1
    wall, fwd, bwd = F.wallward(s), F.along(1), F.along(-1)
    P = f"|{CLUSTER}"
    ops = []
    tiers = F.tiers

    def is_b(a):
        return a % 3 == 0 and 0 <= a // 3 < F.cols

    # pass 1, h 1 (and h 2 from the same spot): tiers 1 and 2's lower cells
    ops.append(f"face|{fwd}")
    for a in range(-1, last + 1):
        if is_b(a):
            ops += ["pickDown" + P, f"face|{wall}", "pick" + P]                 # out(1), up(1)
            if tiers > 1:
                ops += ["up|1", "pickUp" + P, "pick" + P, "down|1"]             # out(2), down(2)
            ops.append(f"face|{fwd}")
        else:
            ops += [f"face|{wall}", "fwd|1", "pickDown" + P]                    # end(1)
            if tiers > 1:
                ops += ["up|1", "pickUp" + P, "down|1"]                         # end(2)
            ops += ["back|1", f"face|{fwd}"]
        if a < last:
            ops.append("fwd|1")
    for t in range(1, tiers):
        # pass at h 3t+1, back the other way: up(t); out, down and ends of tier t+1
        top = t + 1 == tiers
        way = bwd if t % 2 else fwd
        ops += ["up|3", f"face|{way}"]
        rng = list(range(last, -2, -1) if t % 2 else range(-1, last + 1))
        for k, a in enumerate(rng):
            if is_b(a):
                ops += [f"face|{wall}", "pick" + P]                              # up(t)
                if not top:
                    ops += ["up|1", "pickUp" + P, "pick" + P, "down|1"]         # out(t+1), down(t+1)
                ops.append(f"face|{way}")
            elif not top:
                ops += [f"face|{wall}", "fwd|1", "up|1", "pickUp" + P, "down|1", "back|1", f"face|{way}"]
            if k < len(rng) - 1:
                ops.append("fwd|1")
    # down to h 1 at whichever end the last pass finished, then to the far end
    ops += [f"down|{3 * (tiers - 1)}"]
    if (tiers - 1) % 2 == 1:
        ops += [f"face|{fwd}", f"fwd|{last + 1}"]
    s_ops += ops


def harvest(F, o):
    """The whole harvest: the primary side, across the end, the mirrored side."""
    last = 3 * (F.cols - 1) + 1
    s = [fetch({"minecraft:coal": 8}), SITE, walk(F.approach()), walk(F.at(-1, 1, 1))]
    harvest_side(F, 1, s)
    if F.sides == 2:
        # at a=last, h 1 in the primary corridor: on to the crossing row, over, back to a=-1
        cross = F.cross()
        s += [f"face|{F.along(1)}", f"fwd|{cross - last}", f"face|{F.wallward(1)}", "fwd|4",
              f"face|{F.along(-1)}", f"fwd|{cross + 1}"]
        harvest_side(F, -1, s)
    s += ["inv", "leave", "home", "handin|"]
    return s


def survey(F, o):
    mid = F.at(F.cross(), 3, -1)
    return [fetch({GEO: 1}), SITE, walk(mid), "scan|budding_quartz|8", f"scan|{QBLOCK}|8",
            f"scan|{CLUSTER}|8", "leave", "home", "handin|"]


# ================================================================= the bench
def bench_build(F, o):
    B = bench_of(o)
    items = {INSCRIBER: 5, CHARGER: 1}
    for k in ("silicon", "logic", "calc", "eng"):
        items[PRESS[k]] = 1
    s = [fetch(items), SITE]
    for name in BENCH_ORDER:
        c = B[name]
        item = CHARGER if name == "charger" else INSCRIBER
        s += [walk(above(c)), "inspect|down", f"placeDown|{item}", f"expect|down|{item.split(':')[1]}"]
        if name in PRESS:
            s += [f"dropDown|{PRESS[name]}|1"]
    s += ["inv", "leave", "home", "handin|"]
    return s


def charge_ops(B, n, item=CRYSTAL):
    """n crystals through the charger, one at a time. The charger lets a
    crystal out only once it is charged, so the drone keeps trying (suck with
    patience) instead of a fixed wait: a slow one is never left behind and
    the next one never refused."""
    s = [walk(above(B["charger"])), "expect|down|charger"]
    for _ in range(n):
        s += [f"dropDown|{item}|1", f"suckDown|1|{CHARGE_PATIENCE}"]
    s += ["suckDown|1|3"]
    return s


def charge(F, o, n):
    B = bench_of(o)
    return [fetch({CRYSTAL: n}), SITE] + charge_ops(B, n) + ["inv", "leave", "home", "handin|"]


def fluix(F, o, n):
    """n certus charged, then thrown into the basin with n redstone and n
    nether quartz: 2n fluix (AE2 transform recipe; one set a tick once the
    charged crystals have lain in the water 3 s). Any number: one trip per
    64 crystals, each handed in before the next is fetched."""
    B = bench_of(o)
    water, stand = F.basin()
    s = []
    left = n
    while left > 0:
        k = min(TRIP, left)
        left -= k
        sucks = (2 * k + 63) // 64 + 2                # 2k fluix, a stack a suck, and whatever is left over
        s += [fetch({CRYSTAL: k, REDSTONE: k, NQUARTZ: k}), SITE] + charge_ops(B, k)
        s += [walk(stand), "expect|down|water", f"tossDown|{CHARGED}|{k}", f"tossDown|{REDSTONE}|{k}",
              f"tossDown|{NQUARTZ}|{k}", f"wait|{10 + k // 20}"] + ["suckDown|64"] * sucks
        s += ["wait|3", "suckDown|64", "inv", "leave", "home", "handin|"]
    return s


def wait_for(n):
    return f"wait|{SECONDS_PER_PRINT * n + 10}"


def drain(n):
    """Take an inscriber's output as it comes until it holds nothing but its
    press (lab verb drainDown), allowing twice the time n need."""
    return f"drainDown|{2 * SECONDS_PER_PRINT * n + 30}"


def print_ops(F, o, kind, n):
    B = bench_of(o)
    mat, out = PRINTS[kind]
    c = B[kind]
    return [fetch({mat: n}), SITE, walk(above(c)), "expect|down|inscriber", f"dropDown|{mat}|{n}", drain(n),
            "inv", "leave", "home", "handin|"]


def proc_ops(F, o, kind, n):
    """Processors in the mill: printed circuit (top), printed silicon (bottom),
    redstone (middle), the same number of each, so nothing is left stuck in
    the press slots (an inscriber not set to separate sides lets no one take
    them out)."""
    B = bench_of(o)
    printed = PRINTS[kind][1]
    c = B["mill"]
    return [fetch({printed: n, "ae2:printed_silicon": n, REDSTONE: n}), SITE, walk(above(c)), "expect|down|inscriber",
            f"dropDown|{printed}|{n}", "dropDown|ae2:printed_silicon|" + str(n), f"dropDown|{REDSTONE}|{n}",
            drain(n), "inv", "leave", "home", "handin|"]


def grind_ops(F, o, what, n):
    B = bench_of(o)
    mat, out = GRIND[what]
    c = B["mill"]
    s = []
    while n > 0:
        trip = min(n, 256)                         # (4 stacks in, 4 out: room on board)
        n -= trip
        s += [fetch({mat: trip}), SITE, walk(above(c)), "expect|down|inscriber"]
        while trip > 0:
            k = min(trip, 64)                      # the mill's middle slot and its output hold 64
            trip -= k
            s += [f"dropDown|{mat}|{k}", drain(k)]
        s += ["inv", "leave", "home", "handin|"]
    return s


def chips(F, o, nl, nc, ne):
    """Processors in one trip: the four press inscribers print at the same
    time (silicon for every processor, gold, certus, diamond), then the mill
    presses each kind in turn: its printed circuit, as many printed silicon and
    as much redstone. AE2 1.21.1's inscriber (InscriberBlockEntity): with
    sides not separated, every side reaches top, bottom and middle together,
    and an item goes to the first of them whose recipe it fits (a printed
    circuit to the top, printed silicon then to the bottom, redstone, gold,
    silicon, certus and diamond to the middle); only the output can be taken
    out, so presses and part-used inputs stay put. 64 at most in each slot
    and in the output: a kind over 64 takes another trip."""
    B = bench_of(o)
    s = []
    while nl + nc + ne > 0:
        L, C, E = min(nl, 64), min(nc, 64), min(ne, 64)
        S = L + C + E
        while S > 64:                              # (64 printed silicon a trip)
            if E > 0 and E >= C and E >= L: E -= 1
            elif C > 0 and C >= L: C -= 1
            else: L -= 1
            S = L + C + E
        nl, nc, ne = nl - L, nc - C, ne - E
        want = OrderedDictish([(SILICON, S), ("minecraft:gold_ingot", L), (CRYSTAL, C), ("minecraft:diamond", E),
                               (REDSTONE, S)])
        s += [fetch({k: v for k, v in want.items() if v > 0}), SITE]
        for kind, n in (("silicon", S), ("logic", L), ("calc", C), ("eng", E)):
            if n > 0:
                s += [walk(above(B[kind])), "expect|down|inscriber", f"dropDown|{PRINTS[kind][0]}|{n}"]
        s += [f"wait|{SECONDS_PER_PRINT * max(S, L, C, E) - 20}"] if max(S, L, C, E) > 5 else []
        for kind, n in (("silicon", S), ("logic", L), ("calc", C), ("eng", E)):
            if n > 0:
                s += [walk(above(B[kind])), drain(n)]
        s += [walk(above(B["mill"])), "expect|down|inscriber"]
        for kind, n in (("logic", L), ("calc", C), ("eng", E)):
            if n > 0:
                s += [f"dropDown|{PRINTS[kind][1]}|{n}", f"dropDown|ae2:printed_silicon|{n}", f"dropDown|{REDSTONE}|{n}",
                      drain(n)]
        s += ["inv", "leave", "home", "handin|"]
    return s


def OrderedDictish(pairs):
    from collections import OrderedDict
    return OrderedDict(pairs)


def cells_ops(F, o, n, item=CELL1K, drive=DRIVE):
    """n storage cells into the drive (from above: a drive put in from above
    faces up; its cell slots take items from any side)."""
    return [fetch({item: n}), SITE, walk(above(drive)), "expect|down|drive", f"dropDown|{item}|{n}",
            "inv", "leave", "home", "handin|"]


def bridgeclick(F, o):
    """The ME Bridge's floor modem switched on: from the click hole beside it
    (the ae2 fit dug it), facing the modem. Only after the bridge stands on
    it: a full modem clicked with nothing beside it stays off and does not
    pick up what is put there later (CC: Tweaked WiredModemFullBlockEntity)."""
    hx, hy, hz = BRIDGE_HOLE
    return [fetch({"minecraft:coal": 4}), SITE, f"hole|{hx}|{hz}", walk((hx, 1, hz)), "expect|down|nothing",
            walk(BRIDGE_HOLE), f"face|{FACE[(BRIDGE_MODEM[0] - hx, BRIDGE_MODEM[2] - hz)]}",
            "expect|front|wired_modem", "click", walk((hx, 2, hz)), "leave", "home"]


# ================================================================= renewing dead blocks
def renew(F, o, which):
    """Slots whose budding block has decayed to a plain certus quartz block
    (survey says so): dig it from its out cell, make it flawed again in the
    basin (block + 3 charged crystals: damaged, chipped, flawed), put it back."""
    B = bench_of(o)
    n = len(which)
    water, stand = F.basin()
    slots = {sl[0]: sl for sl in F.slots()}
    s = [fetch({CRYSTAL: 3 * n, "minecraft:coal": 8}), SITE] + charge_ops(B, 3 * n)
    trips = []
    for k in which:
        _, i, t, side = slots[k]
        bb, bc = F.side_cols(side)
        a, h = 3 * i, 3 * t
        out = F.at(a, h, bc)
        st = F.at(a, h + 1, bc)                      # the corridor stand over the out cell
        trips.append((out, st, side))
    for out, st, side in trips:
        s += [walk(st), f"pickDown|{BUDS}", "down|1", f"face|{F.wallward(side)}", "inspect",
              f"pick|{QBLOCK}", "up|1"]
    s += [walk(stand), "expect|down|water", f"tossDown|{QBLOCK}|{n}", f"tossDown|{CHARGED}|{3 * n}", "wait|12",
          "suckDown|64", "wait|3", "suckDown|64"]
    for out, st, side in trips:
        s += [walk(st), "down|1", f"face|{F.wallward(side)}", f"place|{BUD}", "expect|front|flawed_budding",
              "up|1"]
    s += ["inv", "leave", "home", "handin|"]
    return s


def first(F, o):
    """The first harvest, then the first fluix batch from 8 of its crystals."""
    return harvest(F, o)[:-1] + fluix(F, o, 8)


# ================================================================= what is where
def cells(F=None, o=None):
    """Everything the farm puts in the building: cell -> what (for plan checks)."""
    F = F or Farm()
    c = {}
    for p in F.pillars():
        c[p] = PILLAR
    for idx, i, t, s in F.slots():
        c[F.slot_cell(i, t, s)] = BUD if idx < F.fill else "(budding slot, empty for now)"
    water, stand = F.basin()
    c[water] = "minecraft:water"
    return c


def grow_cells(F):
    g = {}
    for idx, i, t, s in F.slots():
        for k, v in F.clusters(i, t, s).items():
            g[v] = (idx, k)
    return g


def show_map(F):
    c, g = cells(F), grow_cells(F)
    x0, x1, y0, y1, z0, z1 = F.box()
    print(f"farm: first budding block {F.o}, backs onto the {F.back}; {len(F.filled())} of {len(F.slots())} slots filled")
    print("B budding  b empty slot  P pillar  o grows here  ~ basin water  s the drone's stand over the basin")
    for y in range(y1, y0 - 1, -1):
        print(f"y {y}   x {x0}..{x1}")
        for z in range(z0, z1 + 1):
            row = ""
            for x in range(x0, x1 + 1):
                p = (x, y, z)
                v = c.get(p)
                row += ("B" if v == BUD else "b" if v and v.startswith("(budding") else "P" if v == PILLAR
                        else "~" if v == "minecraft:water" else "o" if p in g else "s" if p == F.basin()[1] else ".")
            print(f"  z {z:3d}  {row}")


def kyle(F):
    W = lambda c: f"{OX + c[0]} {OY + c[1]} {OZ + c[2]}"
    print("1. The two stone pillars (any solid block; growth accelerators replace them later):")
    for p in F.pillars():
        print("   ", W(p), f"(building {p[0]} {p[1]} {p[2]})")
    print(f"2. The budding blocks ({len(F.filled())} flawed), against the pillars, bottom tier first:")
    for idx, i, t, s in F.filled():
        p = F.slot_cell(i, t, s)
        print(f"    slot {idx}: {W(p)} (building {p[0]} {p[1]} {p[2]}, tier {t + 1})")
    water, stand = F.basin()
    print(f"3. The basin: dig the floor block at {W(water)} (building {water[0]} {water[1]} {water[2]}) and pour a bucket in.")


# ================================================================= the build page
def page(F=None):
    import rackpage as RP
    import retrofit as R
    F = F or Farm()
    extra = [
        ("bud", "Flawed budding certus: place by hand", "#1098ad", "#3bc9db", "new"),
        ("slot", "Budding slot, empty for now (a spare or a renewed block later)", "#99e9f2", "#0c8599", "new"),
        ("pillar", "Pillar (stone bricks): later growth accelerators", "#868e96", "#adb5bd", "new"),
        ("water", "Basin: one floor block dug out, a water source in it", "#4dabf7", "#1c7ed6", "new"),
        ("grow", "Keep open: certus grows here", "#c5f6fa", "#164b55", "new"),
    ]
    for e in extra:
        if e[0] not in RP.CODE:
            RP.CAT.append(e)
            RP.CODE[e[0]] = len(RP.CAT) - 1
    c = cells(F)
    filled = [F.slot_cell(i, t, s) for _, i, t, s in F.filled()]
    empty = [F.slot_cell(i, t, s) for idx, i, t, s in F.slots() if idx >= F.fill]
    water, stand = F.basin()
    steps = [
        ("The pillars",
         "Two pillars of stone bricks, floor to the top tier, one per row of the farm. The budding blocks go against "
         "them. Later each tier's brick becomes a growth accelerator (it speeds up the blocks on both its sides) and "
         "the bricks between become Mekanism cable.",
         [("pillar", F.pillars())]),
        ("The budding blocks",
         "Place the flawed budding certus against the pillars, bottom tier first (stand on the floor or a scaffold; "
         "the drone's stands stay open). Never break one: without Silk Touch it drops one tier lower. Keep the "
         "chipped and damaged ones in store as spares; the empty slots take renewed blocks later.",
         [("bud", filled), ("slot", empty)]),
        ("The basin",
         "Dig out one floor block at the end of the pillar line and pour a water bucket in. Charged certus, redstone and "
         "nether quartz thrown in become fluix; a plain certus quartz block and charged certus become budding again. "
         "The drone stands over it.",
         [("water", [water])]),
        ("Keep these open",
         "Where the certus grows: the faces of every budding block. Nothing may stand there. The drone picks only "
         "full-grown clusters, from its stands beside these cells.",
         [("grow", sorted(grow_cells(F)))]),
    ]
    x0, x1, y0, y1, z0, z1 = F.box()
    G = {
        "out": "certus-build.html", "title": "Certus farm: build guide", "h1": "The certus farm",
        "lede": "Certus quartz for the ME network, grown on the budding blocks from the meteorite. Two pillars with "
                f"{len(F.slots())} budding slots on them, three tiers high, every block with its own open faces and a "
                f"drone's stand beside each. You place the pillars and the {len(filled)} flawed budding blocks by hand "
                "(a block breaks one tier lower without Silk Touch); the drone harvests: it picks only full-grown "
                "clusters (4 crystals each) and never touches a budding block.",
        "region": (x0 - 1, x1 + 1, y0, y1 + 1, z0 - 1, z1 + 1), "near": (x0 - 1, x1 + 1), "steps": steps,
        "isoh": "The farm in 3D",
        "chips": lambda n: [f"{n.get('bud', 0)} flawed budding blocks", f"{n.get('pillar', 0)} stone bricks",
                            f"{n.get('slot', 0)} spare slots", "1 water bucket",
                            f"first block at building {F.o[0]} {F.o[1]} {F.o[2]}"],
        "isocap": "The farm is a module: tools/certusfarm.py farm=x,y,z,back puts it elsewhere. Drawn where "
                  "docs/foundry-v2.md puts the certus farm (x 28-34, z 6-13 of the foundry hall).",
        "layercap": f"x {x0 - 1}-{x1 + 1}, z {z0 - 1}-{z1 + 1}, north up.",
        "clicktop": "<p>Nothing to right-click. The table lists the budding blocks, in the order to place them.</p>",
        "clickbottom": "<p class=\"cap\">Then the first harvest about three hours later (docs/ae2-bootstrap.md, "
                       "<code>python3 tools/certusfarm.py first</code>).</p>",
        "serveshead": "What", "clicks": [(p, f"flawed budding, slot {k}") for k, p in enumerate(filled)],
    }
    return RP.write(G)


def main(argv):
    if not argv:
        print(__doc__)
        return
    cmd, rest = argv[0], argv[1:]
    o = opts(rest)
    F = farm_of(o)
    num = [int(a) for a in rest if a.isdigit()]
    words = [a for a in rest if "=" not in a and not a.isdigit()]
    if cmd == "map":
        show_map(F)
    elif cmd == "kyle":
        kyle(F)
    elif cmd == "page":
        print(page(F))
    else:
        if cmd == "harvest":
            s = harvest(F, o)
        elif cmd == "survey":
            s = survey(F, o)
        elif cmd == "bench":
            s = bench_build(F, o)
        elif cmd == "charge":
            s = charge(F, o, num[0] if num else 8)
        elif cmd == "fluix":
            s = fluix(F, o, num[0] if num else 8)
        elif cmd == "print":
            s = print_ops(F, o, words[0], num[0] if num else 8)
        elif cmd == "proc":
            s = proc_ops(F, o, words[0], num[0] if num else 8)
        elif cmd == "grind":
            s = grind_ops(F, o, words[0], num[0] if num else 8)
        elif cmd == "renew":
            s = renew(F, o, [int(k) for k in rest[0].split(",")])
        elif cmd == "first":
            s = first(F, o)
        elif cmd == "chips":
            nn = (num + [0, 0, 0])[:3]
            s = chips(F, o, *nn)
        elif cmd == "cells":
            s = cells_ops(F, o, num[0] if num else 1, o.get("item", CELL1K))
        elif cmd == "bridgeclick":
            s = bridgeclick(F, o)
        else:
            print(__doc__)
            return
        print(";".join(s))


if __name__ == "__main__":
    main(sys.argv[1:])
