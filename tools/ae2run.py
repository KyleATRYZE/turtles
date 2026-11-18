#!/usr/bin/env python3
"""The AE2 run (docs/ae2-run.md): from certus crystals to a running ME network
in the foundry hall's AE2 room. The bill of materials, worked out from
factory.lua's own recipes, and the orders in sequence.

    python3 tools/ae2run.py bom [now|full] [renew=N]    what it takes: parts, what crafter1 crafts,
                                                        the bench's work, and the raw stock
    python3 tools/ae2run.py orders [now|full] [renew=SLOTS] [helper=builder2]
                                                        the tools/order.py commands, in order (printed, never sent)
    python3 tools/ae2run.py dead                        the certus farm's slots as the last survey saw them
                                                        (data/world.json: python3 tools/survey.py pull first),
                                                        and the renew= list of the dead ones

now:  tonight's network (tools/foundry2plans.py AE2_ROOM, the first cells of
      each kind): 3 controllers (the z 19 row), a drive and a 1k cell, 2
      pattern providers and 2 assemblers (they also join the bridge to the
      rest), a 1k crafting storage (the CPU) and the ME Bridge.
full: every cell of the room: 9 controllers, 2 drives and 2 cells, 4
      providers and 4 assemblers, 3 crafting storages, the bridge.
renew: dead budding blocks to make flawed again (3 charged certus each).

Machine-made (never crafted: the AE2 bench and the farm's basin make them,
tools/certusfarm.py): charged certus (charger), certus and fluix dust (the
mill), printed circuits (the four press inscribers), processors (the mill),
fluix crystals (the basin). Everything else is crafted by crafter1 from its
recipes (it makes the in-between parts itself: quartz glass, fibre, cable,
cores, cell components, interfaces, fluix blocks, the casing, smooth sky
stone, silicon in its furnaces).
"""
import math
import os
import re
import sys
from collections import OrderedDict

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

CRYSTAL, CHARGED = "ae2:certus_quartz_crystal", "ae2:charged_certus_quartz_crystal"
DUST, FLUIX, FDUST, SILICON = "ae2:certus_quartz_dust", "ae2:fluix_crystal", "ae2:fluix_dust", "ae2:silicon"
REDSTONE, NQ, GOLD, DIAMOND = "minecraft:redstone", "minecraft:quartz", "minecraft:gold_ingot", "minecraft:diamond"
PRINTED = {"logic": "ae2:printed_logic_processor", "calc": "ae2:printed_calculation_processor",
           "eng": "ae2:printed_engineering_processor"}
PROC = {"logic": "ae2:logic_processor", "calc": "ae2:calculation_processor", "eng": "ae2:engineering_processor"}
PSIL = "ae2:printed_silicon"

# what the bench and the basin make: item -> (where, yield, inputs)
MACHINE = OrderedDict([
    (FLUIX, ("the basin", 2, {CHARGED: 1, REDSTONE: 1, NQ: 1})),
    (CHARGED, ("the charger", 1, {CRYSTAL: 1})),
    (DUST, ("the mill", 1, {CRYSTAL: 1})),
    (FDUST, ("the mill", 1, {FLUIX: 1})),
    (PSIL, ("the silicon press", 1, {SILICON: 1})),
    (PRINTED["logic"], ("the logic press", 1, {GOLD: 1})),
    (PRINTED["calc"], ("the calculation press", 1, {CRYSTAL: 1})),
    (PRINTED["eng"], ("the engineering press", 1, {DIAMOND: 1})),
    (PROC["logic"], ("the mill", 1, {PRINTED["logic"]: 1, PSIL: 1, REDSTONE: 1})),
    (PROC["calc"], ("the mill", 1, {PRINTED["calc"]: 1, PSIL: 1, REDSTONE: 1})),
    (PROC["eng"], ("the mill", 1, {PRINTED["eng"]: 1, PSIL: 1, REDSTONE: 1})),
])
# not broken down further: the store has these (or crafter1 makes them from
# wood, cobblestone and the like as it always has)
RAW = {"minecraft:iron_ingot", "minecraft:copper_ingot", GOLD, DIAMOND, REDSTONE, NQ, CRYSTAL,
       "minecraft:glass", "minecraft:glowstone_dust", "ae2:sky_stone_block", "minecraft:crafting_table",
       "minecraft:piston", "minecraft:iron_bars", "minecraft:redstone_block"}

import foundry2plans as FP  # noqa: E402

FULL = OrderedDict((item, len(cells)) for item, cells in FP.AE2_ROOM.items())
FULL["ae2:item_storage_cell_1k"] = 2
NOW = OrderedDict([("ae2:controller", 3), ("ae2:drive", 1), ("ae2:pattern_provider", 2),
                   ("ae2:molecular_assembler", 2), ("ae2:1k_crafting_storage", 1),
                   ("advancedperipherals:me_bridge", 1), ("ae2:item_storage_cell_1k", 1)])
# the order crafter1 is asked for them: the controller and the drive first
# (the fit's backbone), the bridge last (the most certus in one part)
MAKE_ORDER = ["ae2:controller", "ae2:drive", "ae2:item_storage_cell_1k", "ae2:1k_crafting_storage",
              "ae2:pattern_provider", "ae2:molecular_assembler", "advancedperipherals:me_bridge"]


def recipes():
    """factory.lua's RECIPES table, read by Lua itself."""
    import lupa
    src = open(os.path.join(ROOT, "factory.lua")).read()
    a = src.index("local RECIPES = {")
    b = src.index("\n}\n", a) + 3
    consts = "\n".join(l for l in src[:a].splitlines() if re.match(r'^K\.[A-Z_]+\s*=\s*"[^"]*"', l))
    L = lupa.LuaRuntime(unpack_returned_tuples=True)
    t = L.execute("local K = {}\n" + consts + "\n" + src[a:b] + "\nreturn RECIPES")
    out = {}
    for name, r in t.items():
        rec = {"yield": int(r["yield"] or 1)}
        if r["smelt"]:
            rec["in"] = {r["smelt"]: 1}
            rec["how"] = "smelt"
        else:
            key = dict(r["key"].items()) if r["key"] else {}
            need = {}
            for i in range(1, 10):
                c = r["grid"][i] if r["grid"] else None
                if c:
                    item = key[c]
                    need[item] = need.get(item, 0) + 1
            rec["in"] = need
            rec["how"] = "craft"
            if r["tool"]:
                rec["tool"] = r["tool"]
        out[name] = rec
    return out


def bom(top, renew=0):
    """Total demand of every item for these top-level parts (and renew dead
    budding blocks): {item: count}, and how many times each is made."""
    R = recipes()

    def how(item):
        if item in RAW:
            return None
        if item in MACHINE:
            where, y, ins = MACHINE[item]
            return {"yield": y, "in": ins, "how": where}
        return R.get(item)

    # every item, after all that use it (a depth-first post-order, reversed)
    order, seen = [], set()

    def visit(item):
        if item in seen:
            return
        seen.add(item)
        h = how(item)
        if h:
            for i in h["in"]:
                visit(i)
        order.append(item)
    roots = list(top) + ([CHARGED] if renew else [])
    for item in roots:
        visit(item)
    order.reverse()
    demand = OrderedDict((i, 0) for i in order)
    for item, n in top.items():
        demand[item] += n
    if renew:
        demand[CHARGED] += 3 * renew
    made = OrderedDict()
    for item in order:
        h = how(item)
        n = demand[item]
        if not h or n <= 0:
            continue
        times = math.ceil(n / h["yield"])
        made[item] = (times, h["how"], times * h["yield"])
        for i, k in h["in"].items():
            if i == h.get("tool"):
                demand[i] = max(demand[i], 1)
            else:
                demand[i] += times * k
    return demand, made


def bench_work(demand, made):
    """What the AE2 bench and the basin must do, in lab terms."""
    g = lambda i: made.get(i, (0, "", 0))[2]
    return OrderedDict([
        ("charge (for fluix and renewal)", g(CHARGED)),
        ("fluix crystals (basin)", g(FLUIX)),
        ("certus dust (mill)", g(DUST)),
        ("silicon (crafter1's furnaces)", g(SILICON)),
        ("printed silicon", g(PSIL)),
        ("logic processors", g(PROC["logic"])),
        ("calculation processors", g(PROC["calc"])),
        ("engineering processors", g(PROC["eng"])),
        ("fluix dust (mill)", g(FDUST)),
    ])


def certus_cost(demand):
    return demand.get(CRYSTAL, 0)


def show_bom(which, renew):
    top = NOW if which == "now" else FULL
    demand, made = bom(top, renew)
    print(f"AE2 room, {which}: the parts" + (f" (and {renew} dead budding blocks renewed)" if renew else ""))
    for item, n in top.items():
        print(f"  {n:4d}  {item}")
    print("crafted by crafter1 (times made: items)")
    for item, (t, h, n) in made.items():
        if item not in MACHINE and item not in top:
            print(f"  {t:4d}x {n:4d}  {item}  ({h})")
    print("the bench and the basin")
    for what, n in bench_work(demand, made).items():
        print(f"  {n:4d}  {what}")
    print("from the store (raw)")
    for item in sorted(demand, key=lambda i: -demand[i]):
        if item in RAW and demand[item] > 0:
            print(f"  {demand[item]:4d}  {item}")
    print(f"certus crystals in all: {certus_cost(demand)}")


def orders(which, slots, helper):
    top = NOW if which == "now" else FULL
    renew = len(slots)
    demand, made = bom(top, renew)
    g = lambda i: made.get(i, (0, "", 0))[2]
    cf = "python3 tools/certusfarm.py"
    lab = lambda what: f'tools/order.py lab {helper} clear=1 "ops=$({cf} {what})"'
    fluix_n = g(FLUIX) // 2
    out = [("0p", "builder6", FP_order("power").replace("builder1", "builder6"),
            "the power job again: the survey of 18 Nov 19:29 found none of its row at x 43 y 1, so the heat "
            "generators and the cube are joined to nothing; a rerun puts in what is missing"),
           ("0", "builder1", FP_order("ae2power"), "the AE2 room's power first: the bench has none until this is done "
                                                   "(18 universal cable: crafter1 makes them)"),
           ("1", f"{helper}, Sortnado, crafter1", f"tools/order.py reboot {helper} reboot Sortnado reboot crafter1",
            "onto this code: the lab verbs (suck with patience, drainDown, hole), Sortnado's ME gate (it must "
            "be on it before step 11, or it takes the bridge for the store within 10 minutes), crafter1's make "
            "queue (step 8). Check each is between jobs first")]
    if renew:
        out.append(("2a", "(here, no order)", "python3 tools/survey.py pull && python3 tools/ae2run.py dead",
                    "which slots read quartz_block (dead); or a geo-scan lab: certusfarm.py survey"))
        out.append(("2b", helper, lab(f"renew {','.join(str(s) for s in slots)}"),
                    f"{renew} dead blocks made flawed again: {3 * renew} charged certus"))
    out += [
        ("3", helper, lab(f"fluix {fluix_n}"), f"{fluix_n} charged + {fluix_n} redstone + {fluix_n} nether quartz: {2 * fluix_n} fluix"),
        ("4", helper, lab(f"grind certus {g(DUST)}"), f"{g(DUST)} certus dust (silicon, quartz glass, fibre)"),
        ("5", "crafter1", f"tools/order.py make crafter1 item=ae2:silicon n={g(SILICON)}", "silicon in its furnaces"),
        ("6", helper, lab(f"chips {g(PROC['logic'])} {g(PROC['calc'])} {g(PROC['eng'])}"),
         "printed circuits and processors (logic, calculation, engineering)"),
        ("7", helper, lab(f"grind fluix {g(FDUST)}"), f"{g(FDUST)} fluix dust (the cores)"),
    ]
    makes = " ".join(f"make crafter1 item={item} n={top[item]}" for item in MAKE_ORDER if item in top)
    out.append(("8", "crafter1", f"tools/order.py {makes}", "the parts, in turn (one order: crafter1 queues makes)"))
    out += [
        ("9", "builder1", FP_order("ae2"), "the AE2 room's machines, from above (what is not made yet is left)"),
        ("10", helper, lab(f"cells {top.get('ae2:item_storage_cell_1k', 0)}"), "the cell(s) into the drive"),
        ("11", helper, lab("bridgeclick"), "the bridge's floor modem on, from its click hole"),
    ]
    for step, who, cmd, why in out:
        print(f"# {step}. {who}{': ' + why if why else ''}")
        print(cmd)


def FP_order(job):
    import retrofit as R
    return f"tools/order.py fit builder1 ox={R.OX} oy={R.OY} oz={R.OZ} plan=factory_f2_{job} shell={FP.SHELL}"


def dead():
    """Each budding slot of the farm as the latest survey saw it."""
    import json
    import certusfarm as CF
    path = os.path.join(ROOT, "data", "world.json")
    if not os.path.exists(path):
        print("no survey here (python3 tools/survey.py pull)")
        return []
    blocks = json.load(open(path))["blocks"]
    F = CF.Farm()
    out = []
    for idx, i, t, sd in F.slots():
        c = F.slot_cell(i, t, sd)
        b = blocks.get(f"{CF.OX + c[0]},{CF.OY + c[1]},{CF.OZ + c[2]}", "(nothing seen)")
        print(f"  slot {idx}: building {c[0]} {c[1]} {c[2]}: {b}")
        if b == CF.QBLOCK:
            out.append(idx)
    print("renew=" + ",".join(str(k) for k in out) if out else "none dead")
    return out


def main(argv):
    if not argv:
        print(__doc__)
        return
    which = "full" if "full" in argv else "now"
    opt = dict(a.split("=", 1) for a in argv if "=" in a)
    if argv[0] == "bom":
        show_bom(which, int(opt.get("renew", 0)))
    elif argv[0] == "dead":
        dead()
    elif argv[0] == "orders":
        slots = [int(s) for s in opt.get("renew", "").split(",") if s != ""]
        orders(which, slots, opt.get("helper", "builder2"))
    else:
        print(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
