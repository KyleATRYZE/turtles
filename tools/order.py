#!/usr/bin/env python3
"""Issue a remote order to the swarm by rewriting commands.json.

    tools/order.py reboot all
    tools/order.py stop miner-1
    tools/order.py home miner-1
    tools/order.py resume miner-1
    tools/order.py ping all

Then commit and push; the controller picks it up within about 20 seconds.
Targets: "all", a label ("miner-1", "controller") or a computer id (5).
"""
import json, sys, time

cmd, target = sys.argv[1], sys.argv[2]
if target.isdigit():
    target = int(target)
now = int(time.time())
order = {"id": now, "issued": now * 1000, "cmd": cmd, "target": target}
with open("commands.json", "w") as f:
    json.dump({"commands": [order]}, f, indent=2)
    f.write("\n")
print(order)
