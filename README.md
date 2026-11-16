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

## Factory

`factory.lua` runs on a Crafty Turtle labelled `factory` that sits against a wired modem, with a
chest and a furnace on the same wired network and an output chest in front of it. It smelts and
crafts every part and drops finished mining turtles (pickaxe + ender modem) into the output chest.

## Swarm

The factory also runs the base. It places each new miner on the launch pad (the space above the
disk drive), fuels it and switches it on; the floppy disk installs the software. Each miner asks
the factory for a plot (8x8, Y 50 down, at least 24 blocks from the factory), flies there at its
own cruising height, and flies back to drop its haul into the chest beside the factory turtle.
Miners come down one column and leave by another, so they never meet head-on.
