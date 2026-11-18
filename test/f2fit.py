"""The foundry v2 fit plans (tools/foundry2plans.py, blueprints/factory_f2_*.txt)
run with the real helper.lua in the real building: the cable under the floor
(the walker digs a floor block, stands in the hole, puts the cable a block
down, climbs out and puts the floor back) and the lava wall.

    cd test && python3 f2fit.py
"""
import os, re, lupa
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
fails = []
def check(what, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + what + (f"  [{detail}]" if detail else ""))
    if not ok:
        fails.append(what)

SRC = open(os.path.join(HERE, "screensfit.py")).read()
WORLD = SRC[SRC.index("    L.execute('''\n      package.path") + len("    L.execute('''"):SRC.index("    ''')\n    # the monitors")]

def run(plan, stock, strip=""):
    L = lupa.LuaRuntime(unpack_returned_tuples=True)
    L.execute("START_D=3; START_FUEL=20000")
    L.execute(open(os.path.join(HERE, "harness.lua")).read().replace("/home/claude/turtles", ROOT))
    L.execute(open(os.path.join(HERE, "bworld.lua")).read())
    g = L.globals()
    g.ROOT = ROOT
    g.INSTALL_OK = True
    L.execute(WORLD)
    for k, v in stock.items():
        L.execute(f'STOCK["{k}"] = {v}')
    helper = L.eval(f'loadfile("{ROOT}/helper.lua")')
    go = L.eval('function(f) return {pcall(f)} end')
    L.execute('FS["helper.state"] = textutils.serialize({ job = { fit = true, plan = "%s", shell = "factory_asfit3", '
              'ox = OX, oy = OY, oz = OZ %s } })' % (plan, strip))
    r = list(go(helper).values())
    return L, g, r

def at(L, x, y, z):
    return L.eval(f"getBlock(OX+{x}, OY+{y}, OZ+{z})")

# ---------------------------------------------------------------- the cable (the hall's half)
L, g, r = run("factory_f2_link", {"computercraft:cable": 200, "computercraft:wired_modem_full": 30,
                                   "computercraft:computer_normal": 2, "minecraft:polished_deepslate": 64,
                                   "chipped:striped_yellow_concrete": 64, "minecraft:deepslate_bricks": 64}, ", xmin = 32")
st = L.eval('textutils.unserialize(FS["helper.state"])')
check("the hall's half of the cable job finishes", st.done is True and not st.left, (r[:2], st.left))
trunk = [(35, -1, z) for z in range(6, 23) if z != 15]
check("the cable lies a block under the floor down the spine", all(at(L, *c) == "computercraft:cable" for c in trunk),
      [at(L, *c) for c in trunk[:4]])
check("and the floor is back over it", all(at(L, c[0], 0, c[2]) == "minecraft:polished_deepslate" for c in trunk),
      [at(L, c[0], 0, c[2]) for c in trunk[:4]])
check("the works computer flush in the floor on its modem", at(L, 35, 0, 15) == "computercraft:computer_normal"
      and at(L, 35, -1, 15) == "computercraft:wired_modem_full")
check("a modem under each alloy machine's place", all(at(L, 39, 0, z) == "computercraft:wired_modem_full" for z in range(17, 24)))
check("the lane's half was left to the other helper", at(L, 20, -1, 2) != "computercraft:cable")
check("nothing left standing in the walkways", all(at(L, x, 1, z) is None for x in (35, 36) for z in range(5, 29)))

L, g, r = run("factory_f2_link", {"computercraft:cable": 200, "computercraft:wired_modem_full": 30,
                                   "chipped:striped_yellow_concrete": 64, "minecraft:polished_deepslate": 64}, ", xmax = 31")
st = L.eval('textutils.unserialize(FS["helper.state"])')
check("the lane's half (by the hatch): finishes", st.done is True and not st.left, (r[:2], st.left))
check("  down from rack 1's link through the wall foot, under the front track to the hatch",
      at(L, 18, 1, 3) == "computercraft:wired_modem_full" and at(L, 18, 0, 3) == "computercraft:cable"
      and all(at(L, x, -1, 2) == "computercraft:cable" and at(L, x, 0, 2) == "chipped:striped_yellow_concrete" for x in range(18, 32)))

# ---------------------------------------------------------------- the lava wall
L, g, r = run("factory_f2_lava", {"minecraft:polished_deepslate": 64, "minecraft:pointed_dripstone": 16,
                                   "minecraft:cauldron": 16, "minecraft:lava_bucket": 16})
st = L.eval('textutils.unserialize(FS["helper.state"])')
check("the lava job finishes", st.done is True and not st.left, (r[:2], st.left))
units = [(x, 29) for x in range(28, 44)]
check("16 units: cauldron, dripstone, block, lava", all(at(L, x, 1, z) == "minecraft:cauldron" and at(L, x, 2, z) == "minecraft:pointed_dripstone"
      and at(L, x, 3, z) == "minecraft:polished_deepslate" and at(L, x, 4, z) == "minecraft:lava_bucket" for x, z in units),
      [(at(L, 30, y, 29)) for y in (1, 2, 3, 4)])
check("the lava's wall over the walkway, the walkway clear", all(at(L, x, 4, 28) == "minecraft:polished_deepslate"
      and at(L, x, 1, 28) is None and at(L, x, 2, 28) is None for x in range(28, 44)))
# ---------------------------------------------------------------- the AE2 room (phase 4), with the parts for tonight only
import sys
sys.path.insert(0, os.path.join(ROOT, "tools"))
import foundry2plans as FP

def run_ae2(stock, plan="factory_f2_ae2power"):
    L = lupa.LuaRuntime(unpack_returned_tuples=True)
    L.execute("START_D=3; START_FUEL=20000")
    L.execute(open(os.path.join(HERE, "harness.lua")).read().replace("/home/claude/turtles", ROOT))
    L.execute(open(os.path.join(HERE, "bworld.lua")).read())
    g = L.globals()
    g.ROOT = ROOT
    g.INSTALL_OK = True
    L.execute(WORLD)
    # the bench as builder5 left it, the alloy cell's riser, and the old line's corner cleared (the clear job)
    for z, it in zip(range(18, 24), ["ae2:inscriber"] * 4 + ["ae2:charger", "ae2:inscriber"]):
        L.execute(f'setSpecial(OX + 28, OY + 1, OZ + {z}, "{it}")')
    for x in range(38, 44):                       # the alloy job's power run under the east door's walkway
        L.execute(f'setSpecial(OX + {x}, OY - 1, OZ + 24, "mekanism:basic_universal_cable")')
    for c in [(32, 1, 22), (32, 2, 22), (33, 1, 22), (34, 1, 22), (34, 1, 23), (35, 1, 22)]:
        L.execute(f'setSpecial(OX + {c[0]}, OY + {c[1]}, OZ + {c[2]}, false)')
    for k, v in stock.items():
        L.execute(f'STOCK["{k}"] = {v}')
    helper = L.eval(f'loadfile("{ROOT}/helper.lua")')
    go = L.eval('function(f) return {pcall(f)} end')
    L.execute('FS["helper.state"] = textutils.serialize({ job = { fit = true, plan = "%s", shell = "factory_asfit3", '
              'ox = OX, oy = OY, oz = OZ } })' % plan)
    r = list(go(helper).values())
    return L, g, r

def rerun_ae2(L, stock, plan="factory_f2_ae2"):
    for k, v in stock.items():
        L.execute(f'STOCK["{k}"] = {v}')
    helper = L.eval(f'loadfile("{ROOT}/helper.lua")')
    go = L.eval('function(f) return {pcall(f)} end')
    L.execute('local st = textutils.unserialize(FS["helper.state"]) '
              'st.job = { fit = true, plan = "%s", shell = "factory_asfit3", ox = OX, oy = OY, oz = OZ } ' % plan +
              'st.i, st.left, st.later, st.undone, st.short, st.done, st.kept, st.empty = nil, nil, nil, nil, nil, nil, nil, nil '
              'FS["helper.state"] = textutils.serialize(st)')
    return list(go(helper).values())

NOW = {"ae2:controller": 3, "ae2:drive": 1, "ae2:pattern_provider": 2, "ae2:molecular_assembler": 2,
       "ae2:1k_crafting_storage": 1, "advancedperipherals:me_bridge": 1}
# first the power (ae2power), then the machines (ae2) with tonight's parts, then ae2 again with nothing new
L, g, r = run_ae2({"mekanism:basic_universal_cable": 18, "minecraft:polished_deepslate": 64,
                   "minecraft:deepslate_bricks": 64})
st = L.eval('textutils.unserialize(FS["helper.state"])')
check("ae2power: finishes, nothing left", st.done is True and not st.left
      and at(L, 28, 0, 18) == "mekanism:basic_universal_cable" and at(L, 37, -1, 24) == "mekanism:basic_universal_cable",
      (r[:2], st.left))
r = rerun_ae2(L, NOW)
st = L.eval('textutils.unserialize(FS["helper.state"])')
have = sum(NOW.values())
want = sum(len(c) for c in FP.AE2_ROOM.values())
check("the ae2 job finishes; only the parts not yet made are left", st.done is True and st.left == want - have, (r[:2], st.left, want - have))
UCN = "mekanism:basic_universal_cable"
check("power in the floor under all six bench machines", all(at(L, 28, 0, z) == UCN for z in range(18, 24)),
      [at(L, 28, 0, z) for z in range(18, 24)])
check("  and under the controller's first block", at(L, 29, 0, 19) == UCN)
check("  the trunk a block under the floor along z 23, onto the power run at z 24",
      all(at(L, x, -1, 23) == UCN for x in range(28, 38)) and at(L, 37, -1, 24) == UCN and at(L, 38, -1, 24) == UCN,
      [at(L, x, -1, 23) for x in range(28, 38)] + [at(L, 37, -1, 24)])
check("  with the floor back over it, and over every access hole",
      all(at(L, x, 0, 23) in ("minecraft:polished_deepslate", "minecraft:deepslate_bricks") for x in range(29, 38))
      and at(L, 37, 0, 24) in ("minecraft:polished_deepslate", "minecraft:deepslate_bricks")
      and all(at(L, 29, 0, z) == "minecraft:polished_deepslate" for z in (18, 20, 21, 22)),
      [at(L, x, 0, 23) for x in range(29, 38)])
cov = {c for cells in FP.AE2_ROOM.values() for c in cells} | set(FP.AE2_BENCH)
shown = [(x, z) for x in range(27, 40) for z in range(16, 25)
         if at(L, x, 0, z) == UCN and at(L, x, 1, z) is None]
check("no cable on show: each one in the floor has a machine on it", not shown, shown)
firsts = {item: cells[:NOW[item]] for item, cells in FP.AE2_ROOM.items()}
check("tonight's machines in their first cells (controller row z 19, drive 32 19, providers, assemblers, CPU, bridge)",
      all(at(L, *c) == item for item, cells in firsts.items() for c in cells),
      {item: [at(L, *c) for c in cells] for item, cells in firsts.items()})
check("the bridge on its floor modem's cell, its click hole open", at(L, 34, 1, 21) == "advancedperipherals:me_bridge"
      and at(L, 34, 0, 22) is None)
# the network by touching: from the controller, through AE2 blocks only, every machine and the bench
ae = {c for c in cov if at(L, *c) and (at(L, *c).startswith("ae2:") or at(L, *c).startswith("advancedperipherals:"))}
seen, todo = {(29, 1, 19)}, [(29, 1, 19)]
while todo:
    x, y, z = todo.pop()
    for d in ((1, 0, 0), (-1, 0, 0), (0, 0, 1), (0, 0, -1)):
        n = (x + d[0], y, z + d[2])
        if n in ae and n not in seen:
            seen.add(n); todo.append(n)
check("one network by touching: the controller reaches the bench, drive, providers, assemblers, CPU and bridge",
      seen == ae, sorted(ae - seen))
r = rerun_ae2(L, {})
st = L.eval('textutils.unserialize(FS["helper.state"])')
# (the walker leaves a kind it has none of without going to look, so it says
# "left" for those standing already too: harmless)
check("ae2 again with nothing new made: finishes, takes nothing out", st.done is True
      and all(at(L, *c) == item for item, cells in firsts.items() for c in cells), (r[:2], st.left))
check("nothing in the spine or the cross aisle", all(at(L, x, y, z) is None for x in (35, 36) for y in (1, 2) for z in range(17, 24)))
print("PASS" if not fails else "FAILED: %d" % len(fails))
