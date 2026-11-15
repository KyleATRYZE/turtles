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
