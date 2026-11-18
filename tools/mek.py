#!/usr/bin/env python3
"""Lab steps for the Metallurgic Infuser on the bench beside the factory.

    tools/mek.py steel 10            ten steel dust (iron + carbon, twice)
    tools/mek.py circuit 4           basic control circuits (osmium + redstone)
    tools/mek.py alloy 4             infused alloy (copper + redstone)
    tools/mek.py steel 10 circuit 2  several in one run

Prints the ops for a helper's lab bench:  tools/order.py lab foundry1 "ops=$(tools/mek.py steel 10)"

The infuser stands at -4452 74 1533 facing south. From the turtle's side:
the west face takes the infusion item, the top takes the item to work on,
the east face gives the result, the north face is the energy slot (redstone
dust is power: two dust run one job, with a little to spare).
"""
import sys

X, Y, Z = -4452, 74, 1533
M = "metallurgic_infuser"
RECIPES = {   # name: list of stages (input, infusion item, dust per job, output)
    "steel": [("minecraft:iron_ingot", "minecraft:charcoal", 1, "mekanism:enriched_iron"),
              ("mekanism:enriched_iron", "minecraft:charcoal", 1, "alltheores:steel_dust")],
    "circuit": [("alltheores:osmium_ingot", "minecraft:redstone", 2, "mekanism:basic_control_circuit")],
    "alloy": [("minecraft:copper_ingot", "minecraft:redstone", 1, "mekanism:alloy_infused")],
}
STATION = {"W": (0, f"goto|{X - 1}|{Y + 6}|{Z};ground;face|0;expect|front|{M}"),
           "E": (2, None), "N": (1, None)}
FACE = {"W": 0, "E": 2, "N": 1}            # which way the turtle faces at each station
OUT = {"W": 2, "E": 0, "N": 3}             # which way it leaves the top to get there


def go(at, to):
    """Steps from one station to another (over the top of the machine)."""
    if at == to:
        return []
    steps = []
    if at != "T":
        steps += [f"face|{FACE[at]}", "up|1", "fwd|1", f"expect|down|{M}"]
    if to != "T":
        steps += [f"face|{OUT[to]}", "fwd|1", "down|1", f"face|{FACE[to]}", f"expect|front|{M}"]
    return steps


def drop(item, n, down=False):
    steps = []
    while n > 0:
        k = min(64, n)
        steps.append(f"{'dropDown' if down else 'drop'}|{item}|{k}")
        n -= k
    return steps


args = sys.argv[1:]
jobs = [(args[i], int(args[i + 1])) for i in range(0, len(args), 2)]
need = {}
def want(item, n):
    need[item] = need.get(item, 0) + n
power = 0
for name, n in jobs:
    stages = RECIPES[name]
    want(stages[0][0], n)
    for inp, extra, per, out in stages:
        want(extra, n * per)
        power += 2 * n                   # (a job takes a little more than one dust of power)
want("minecraft:redstone", power + 2)
ops = ["fetch|" + ",".join(f"{k}={v}" for k, v in need.items()), STATION["W"][1]]
at = "W"
ops += go(at, "N") + drop("minecraft:redstone", power + 2); at = "N"
# whatever was left half done last time finishes now it has power: take it
# out, and empty the infusion tank, so this run starts clean
ops += ["wait|25"] + go(at, "E") + ["suck|64", "suck|64", "call|front|getInput", "call|front|dumpInfuseType"]; at = "E"
for name, n in jobs:
    for inp, extra, per, out in RECIPES[name]:
        ops += go(at, "W") + drop(extra, n * per) + ["call|front|getInfuseType"]; at = "W"
        ops += go(at, "T") + drop(inp, n, down=True) + [f"until|bottom|getOutput|{n}|{60 + 15 * n}"]; at = "T"
        ops += go(at, "E") + ["suck|64", "suck|64"]; at = "E"
        # anything of another kind left in the machine would block the next recipe
        ops += ["call|front|getInfuseType", "call|front|dumpInfuseType"]
ops += ["inv", "handin|"]
print(";".join(ops))
