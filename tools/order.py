#!/usr/bin/env python3
"""Issue remote orders to the swarm by rewriting commands.json.

    tools/order.py reboot all
    tools/order.py stop miner-1
    tools/order.py reboot all resume CoalPorter      (several orders, in order)

Then commit and push; the controller picks them up within about 20 seconds.
Targets: "all", a name ("CoalPorter", any case) or a computer id (5).
"""
import json, sys, time

args = sys.argv[1:]
if not args or len(args) % 2:
    sys.exit(__doc__)
now = int(time.time())
orders = []
for i in range(0, len(args), 2):
    cmd, target = args[i], args[i + 1]
    if target.isdigit():
        target = int(target)
    orders.append({"id": now + i // 2, "issued": now * 1000, "cmd": cmd, "target": target})
with open("commands.json", "w") as f:
    json.dump({"commands": orders}, f, indent=2)
    f.write("\n")
for o in orders:
    print(o)
