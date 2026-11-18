# Where things stand (18 Nov, 00:20)

Working notes so the next session can pick up. Newest first.

## Decided with Kyle
- Drones use the drone lane and its gates, never roof shafts. Idle drones dock in the rack.
- Loads go over the cable: a wired modem hidden behind every rack home; storage pushes
  items straight into the docked turtle (as inv.lua / hopper.lua do). Kyle clicks the
  modems red once. A monitor strip per shelf shows each drone.
- Nothing may stick out of the walls or spoil the rack's look.
- Junk stone is kept. Chunks round the factory are force-loaded. Hut lava rounds stay.
- Three players' memory cards are in Inventory Managers; `$get` serves whoever asks.

## Built and working
- Store: two Sophisticated Storage controllers, 803 slots, Sortnado sorts by slot size
  (bulk / medium / small) and section; orders `survey`, `resort`, `drain`, `reboot`.
- Quartz line (reconstructor + fan wash); 82 quartz. Lava: hut cauldrons + 11-unit row.
- Mekanism stage 2. Stage 4-5 recipes in factory.lua and foundry.lua.
- Screen mirror: every machine's status carries its last screen lines (`screen`).
- Counter (second dispenser, turtle 38) works but is PAUSED: helpers could not collect
  from its pad and three hung for an hour.

## In progress
- Retrofit stage 1: HopTo fits the lane pit stops (`factory_pitstop`), Comparable the
  hall-to-desk cable (`factory_desklink`), OnRepeat digs the west gate's approach (a
  parked loader, Breezy, sits in one cell: -4451 72 1520).
- Mekanism stage 3: waiting on DropIt's foundry jobs (alloy, circuits, dusts), then
  `make Crafty item=mekanism:crusher` etc., then `lab Sticky ... mekline.py ops 3`.
- Background work: rack-as-loading-bay plan + code + watchdog; research into other CC
  projects (docs/cc-lessons.md).

## The move (not yet)
See docs/factory-retrofit.md. Order of orders: `reboot all`, `haul Crafty on=0`,
`drain Sortnado from=minecraft:chest_*`, `stop all`, move Crafty/Counter/floppy,
`rebase all hover=20 hop=22 lane=1 door=-4426,72,1549`, `resume all`.

## Known problems
- Weak Automata Core `useOnBlock` throws "this.owner is null" on factory-placed turtles.
- Hauling and lava rounds take any idle helper: keep builders in their `skip=` lists.
- update.lua writes .role from the label only on first run: `rm .role`, `update`, `reboot`.

## Update 18 Nov 00:20
- Rack 1 built by Kyle (8 shelf modems clicked, monitors, RackBoard computer running rack.lua).
  Helper docking does NOT work yet: HopTo stopped one block short of his home and found no bay.
  Lane mode switched OFF for all helpers (`rebase <h> lane=0`): before the move it sent them out
  by the east gate to hover. Next: test ONE helper docking while watching it.
- Kyle removed all 11 chunk loaders until docking works.
- The old pad shaft (-4462, 1521) jammed with a stack of helpers; Kyle asked to break the bottom one.
- Sticky and OnRepeat out of fuel (Kyle asked to `refuel all`).
- Foundry hall v2 concept APPROVED (docs/foundry-v2.html) + an indoor lava dripper farm. Kyle wants
  drones to build almost everything (fit plans); he only clicks modems and places budding certus.
- AE2: presses, sky stone, 9 flawed + 4 lesser budding certus in the old base. docs/ae2-bootstrap.md,
  tools/certusfarm.py, docs/certus-build.html. ~100 certus crystals needed in all.
- Create schematics: tools/schematic.py; the device bridge can write into Kyle's ATM10 schematics folder.
