"""The storage room in blueprints/factory.json: one controller, every
storage block joined to it, the desk wired the way Sortnado needs, and the
room's fit plan puts in exactly what the blueprint shows.

    python3 test/storeroom.py
"""
import json, os, re, sys
from collections import Counter
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
bp = json.load(open(os.path.join(ROOT, "blueprints", "factory.json")))
B = {(x, y, z): bp["palette"][i].split("[")[0] for x, y, z, i in bp["blocks"]}
N6 = [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)]
def near(c):
    return [(c[0] + d[0], c[1] + d[1], c[2] + d[2]) for d in N6]
fails = []
def check(what, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + what + (" | " + str(detail) if detail != "" else ""))
    if not ok:
        fails.append(what)

def is_store(n):
    return n.startswith("sophisticatedstorage:") and n != "sophisticatedstorage:controller"
ctl = [c for c, n in B.items() if n == "sophisticatedstorage:controller"]
store = {c for c, n in B.items() if is_store(n)}
check("one controller", len(ctl) == 1, ctl)
seen, todo = set(), [ctl[0]]
while todo:
    c = todo.pop()
    for o in near(c):
        if o in store and o not in seen:
            seen.add(o)
            todo.append(o)
check("every barrel and chest is joined to the controller", seen == store, f"{len(seen)} of {len(store)}")
listed = {tuple(c) for k in bp["store"].values() for c in k}
check("the plan's list of the store is the store", listed == store, (len(listed), len(store)))
kinds = Counter(B[c] for c in store)
print("     ", dict(kinds))

def one(name):
    hits = [c for c, n in B.items() if n == name and 10 <= c[0] <= 17 and c[2] >= 28]
    return hits[0] if len(hits) == 1 else None
man = one("advancedperipherals:inventory_manager")
pc = one("computercraft:computer_advanced")
ender = one("computercraft:wireless_modem_advanced")
barrels = sorted(c for c, n in B.items() if n == "minecraft:barrel" and 10 <= c[0] <= 17 and c[2] >= 28)
check("the desk: manager, Sortnado, its ender modem, In and Out barrels", bool(man and pc and ender) and len(barrels) == 2, (man, pc, ender, barrels))
check("the manager touches the controller (items straight from the store)", ctl[0] in near(man))
check("and an Out barrel (the other way)", any(b in near(man) for b in barrels))
check("the vanilla barrels do not touch the store", not any(o in store or o == ctl[0] for b in barrels for o in near(b)))
check("the ender modem is on Sortnado", pc in near(ender))
check("the touch screen stands on Sortnado", B.get((pc[0], pc[1] + 1, pc[2])) == "computercraft:monitor_advanced")
wired = lambda c: B.get((c[0], c[1] - 1, c[2])) == "computercraft:wired_modem_full"
check("a wired modem under everything Sortnado must reach", all(wired(c) for c in [ctl[0], man, pc] + barrels))
modems = {(c[0], c[1] - 1, c[2]) for c in [ctl[0], man, pc] + barrels}
seen, todo = set(), [next(iter(modems))]
while todo:
    c = todo.pop()
    if c in seen:
        continue
    seen.add(c)
    todo += [o for o in near(c) if B.get(o) in ("computercraft:wired_modem_full", "computercraft:cable")]
check("the desk's modems are one network", modems <= seen)
# the doorways are still open (z 14..16, the two bottom rows of both side walls)
check("the doorways are clear", not any((x, y, z) in B for x in (10, 17) for y in (1, 2, 3) for z in (14, 15, 16)))

# ---- the fit plan for the room
plan = os.path.join(ROOT, "blueprints", "factory_storeroom.txt")
pal, puts, mode = [], Counter(), None
for line in open(plan):
    t = line.split()
    if t[0] == "P" and len(t) == 2:
        mode = "P"
    elif t[0] == "O" and len(t) == 2:
        mode = "O"
    elif mode == "P":
        pal.append(t[0])
    elif mode == "O" and t[0] in "PR":
        c = tuple(map(int, t[1:4]))
        puts[pal[int(t[4])]] += 1
        if B.get(c) != pal[int(t[4])]:
            fails.append("plan puts %s at %s, blueprint has %s" % (pal[int(t[4])], c, B.get(c)))
check("the fit plan puts in the whole store and the controller",
      all(puts[k] == v for k, v in kinds.items()) and puts["sophisticatedstorage:controller"] == 1, dict(puts))
check("the manager and the ender modem are left for a lab run", "advancedperipherals:inventory_manager" not in puts
      and "computercraft:wireless_modem_advanced" not in puts)

print("PASS" if not fails else "FAILED: " + "; ".join(fails))
sys.exit(1 if fails else 0)
