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
the factory for a plot (8x8, Y 50 down, at least 24 blocks from the factory).

Miners travel underground on two one-way roads just above the plots: the out road (Y 52) from the
base to the plots and the in road (Y 56) back. Roads are two blocks high with gaps floored in
cobblestone, so people can walk them. At the base, miners come up the in-shaft (beyond the
drop-off chest), unload into the chest beside the factory turtle, and go down the out-shaft
(beyond the launch pad). Nothing on the surface is touched.

Miners keep only enough coal to stay fuelled (about 3000 fuel) and bring the rest back.

## Fuel

Each miner carries a bucket and scoops up any lava source it meets while mining (1000 fuel per
bucket) until its tank holds 10000. The factory crafts the buckets and hands one to every new
miner, and to any older miner that asks on its next visit. Rubble is dumped before each trip home.

## Names

Machines remember their job in a `.role` file, so they can be renamed freely. Miners name
themselves from a list of puns; the factory is ForgeClooney and the controller GroundControl.

## Coal hunting

A swarm miner holding a Geo Scanner (Advanced Peripherals) stops digging its plot and hunts coal:
it roams a grid of scan points 28 to 70 blocks from the factory at Y 60, swaps the scanner in to
find coal ore within 8 blocks, digs each one out and carries the coal home. When the factory has
no coal for a miner that asks, it hands over its scanner so that miner becomes the hunter
(renamed CoalPorter). After covering the whole area it goes back to its plot.

The coal hunter is permanent: it gives its plot back (the next new miner finishes it), widens
its search area each round (up to 112 blocks), scans where it is first when low on fuel, and
answers rescue calls: a miner that runs dry away from the base broadcasts its position, and the
hunter digs down to it and drops 16 coal on it.
