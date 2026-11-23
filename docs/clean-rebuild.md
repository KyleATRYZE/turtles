# The clean rebuild (merged into `main` on 23 Nov 2026)

The plant was rebuilt around an ME network, and most of the old programs served machines
that no longer exist. This branch starts the turtle side again on a small set of tested
helpers, and keeps the two programs that run the rebuilt plant.

## What is here

| Path | What it is |
|---|---|
| `lib/move.lua`, `inv.lua`, `state.lua`, `log.lua` | Shared helpers: movement that knows where it is and says why it failed, inventory, power-cut-safe saves, logs with crash reports and a stall watchdog |
| `lib/net.lua` | Reports to the controller, orders from it, plot requests. Speaks the message shapes the controller already uses |
| `lib/agent.lua` | Remote "run this and tell me" helper. Not deployed yet: it needs a shared secret set on each machine |
| `miner.lua` | The new miner, about 400 lines, built only from `lib/` |
| `parked.lua` | For machines whose old job is gone: stay put, report, take `reboot` and `ping` |
| `update.lua`, `files.txt` | Each machine downloads only its own job's files |
| `controller.lua`, `screens.lua`, `swarm.lua`, `dash.lua`, `mirror.lua` | Kept as they were: order relay, status upload, plots, doors, gates, boards, GPS hosts, ME orders |
| `sim/`, `tests/` | A small fake ComputerCraft world and the tests that run in it |
| `tools/lint.py` | Checks for code that runs on a PC but not in ComputerCraft, and each job's disk use |

Removed: `factory.lua`, `helper.lua`, `builder.lua`, `loader.lua`, `foundry.lua`,
`sortnado.lua`, `rack.lua`, `works.lua`, `chatpc.lua`, the old `miner.lua`, and their tests.

## Checking it

```
python tests/run_tests.py      # simulator tests, on Lua 5.2 like ComputerCraft
python tools/lint.py .         # syntax, 5.3 operators, upvalue limit, requires, disk per job
python test/screenstest.py     # the stations (unchanged)
python test/plotstest.py       # the controller's plot hand-out (unchanged)
```

All need `pip install lupa`.

## What each machine downloads

`files.txt` lists `path role[,role...]`. A machine's job is in its `.role` file; the old jobs
(helper, builder, loader, factory, storage, rack, works) all count as `parked`.

| Job | Files |
|---|---|
| miner | `update.lua`, `miner.lua`, `lib/move`, `inv`, `state`, `log`, `net` |
| parked | `update.lua`, `parked.lua`, `lib/net` |
| controller | `update.lua`, `controller.lua`, `swarm.lua`, `dash.lua`, `mirror.lua` |
| screen | `update.lua`, `screens.lua`, `swarm.lua`, `dash.lua`, `mirror.lua` |

## Moving a machine onto this branch

Machines on `main` run the old updater, which reads `manifest.txt` as a plain list. On this
branch `manifest.txt` lists only `update.lua`, so:

1. Order `reboot rev=<a commit on this branch>` to the machine. Its old updater downloads the
   new `update.lua` and nothing else, then runs its old program once more.
2. Order `reboot` again. The new updater now runs, follows this branch (`BRANCH` at the top of
   `update.lua`), downloads the files for the machine's job and removes the rest.

To move everything at once: merge into `main` with `BRANCH = "main"`. Every machine picks the
new updater up on its next boot and its job's files on the one after.

## The miner's rules

- Roads are one-way and underground: out at two above the plot tops, in at six above.
- Home is a berth in the hangar, one per miner, for good. The job carries two lists of corners:
  the way in (up the in-shaft, along the back of the building, in by the rear gate, along the
  aisle, into the berth) and the way out (one level higher, by the other side of the gate, to
  the out-shaft). Both are one-way. A miner with no plot waits in its berth.
- It never digs higher than twelve above the plot tops: everything up there is the factory.
- It never digs machines, cables, chests, other turtles, concrete, glass, or polished,
  slab, stair and wall blocks. On the way somewhere it waits, and its report says what is in
  the way; in its plot it leaves that one cell and carries on. Ores and the plain rock that
  mods add (Create's scoria, limestone and the like) are dug like any other.
- Progress is saved after every cell. GPS is the truth about position after a restart.
- Cargo: everything it carries goes into the barrel under the berth; a belt takes it to the store.
- Fuel is lava: at the berth it burns lava buckets from the barrel overhead, which
  the store keeps filled, and sends the empties down, all but one. With that one it scoops up
  lava it finds over or under its path. Coal it digs goes to the store; it burns coal only
  when there is no lava.
- Orders: `stop`, `resume`, `newjob`, `reboot` (with `rev`), `ping`.

Not tried in the game yet. The simulator has no `parallel`, no real peripherals and no lag.
