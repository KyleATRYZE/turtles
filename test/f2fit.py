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
print("PASS" if not fails else "FAILED: %d" % len(fails))
