# turtles

CC:Tweaked turtle scripts for All the Mods 10.

Install on a turtle (one time):

```
wget run https://raw.githubusercontent.com/KyleATRYZE/turtles/main/install.lua
```

After that, every turtle downloads the latest scripts each time it boots.

- `miner.lua` - GPS quarry miner. `miner <size> [bottomY]`, chest behind the turtle.
- `update.lua` - downloads everything listed in `manifest.txt`.
- `install.lua` - one-time setup.
- `swarm.lua` - shared helper that reports status to the controller.
- `controller.lua` - base computer: shows every turtle's status and uploads it to the `status` branch (`status.json`).

## Remote orders

`commands.json` on `main` holds the latest order. The controller checks it every 20 seconds and
relays it to the turtles. Write one with `tools/order.py <cmd> <target>`, then commit and push.

- `reboot` - restart (downloads the latest scripts, then carries on with the saved job)
- `stop` - stop where it is and wait
- `home` - go home, unload and wait
- `resume` - carry on with the saved job
- `ping` - report status now
