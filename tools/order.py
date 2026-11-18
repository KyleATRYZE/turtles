#!/usr/bin/env python3
"""Issue remote orders to the swarm by rewriting commands.json.

    tools/order.py reboot all
    tools/order.py stop miner-1
    tools/order.py reboot all resume Coalition          (several orders, in order)
    tools/order.py survey mapper1 x=-4430 z=1530 size=64 name=factory_site

Then commit and push; the controller picks them up within about 20 seconds.
Targets: "all", a name ("Coalition", any case) or a computer id (5).
"""
import json, sys, time

args = sys.argv[1:]
orders, now = [], int(time.time())
i = 0
while i < len(args):
    cmd, target = args[i], args[i + 1]
    i += 2
    order = {"id": now + len(orders), "issued": now * 1000, "cmd": cmd,
             "target": int(target) if target.isdigit() else target}
    while i < len(args) and "=" in args[i]:
        k, v = args[i].split("=", 1)
        try:
            v = int(v)
        except ValueError:
            pass
        order[k] = v
        i += 1
    orders.append(order)
if not orders:
    sys.exit(__doc__)
with open("commands.json", "w") as f:
    json.dump({"commands": orders}, f, indent=2)
    f.write("\n")
for o in orders:
    print(o)
