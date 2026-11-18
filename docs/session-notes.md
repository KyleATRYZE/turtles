# Where things stand (18 Nov, 00:20)

**Master to-do list: docs/overnight-plan.md (read it first).**

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

## 01:05 check-in (18 Nov)
- Found the pad-shaft jam: Crafty called every ready load at once, so 5 helpers dived the one-wide shaft together; Pushy sat on the pad "stuck under turtle", the rest hovered over it. Fix 41b3702: one helper called at a time (oldest ready load), skipped to the back after 2 min if it doesn't land. Crafty rebooted onto it.
- Dusty took Comparable's foundry-cable share (x 26-34); Dispensable took Sticky's clear-out share (x ≤35).
- Charcool still stranded at -4463 60 1521; miner TuffLuck is above it in the same shaft, so a feed from above can't reach it. Handed to the rescue work.
- 01:12: rescue duty and Counter-as-assistant landed (d23b7cc, 1c885d0); everyone restarted onto a4ba0b2. Counter now crafts half of Crafty's loads. Observant took HopTo's cable share (x ≤25). Dispensable kept idle as the standby rescuer. Phase 2 (alloy) waits for the cable + lava wall to finish; the probe needs Kyle's works-computer install first.
- Known stale test: test/baytest.py rack-board drawing checks (2) fail after the board restyle; the watchdog/pad-queue checks pass.
- 01:33 check-in: rename applied (all on 57194aa); watchdog fix (it rebooted pad-queued drones); rack top board fix; mapper1 mapped the old base and is mapping the factory. Throughput is limited by the single pad: 5 drones waiting for loads at once. The real fix is cable loading at docked homes, which needs the docking test (next free helper).
- 01:50: docking WORKS (the blocker was a lab-bench bug). builder1 is on lane mode alone; cable loading isn't served yet, so Sortnado now reports why. Next check-in 02:20.
- 01:55: survey1 ran dry mid-survey (labs never topped up fuel: fixed 9b05162). Rescue queue: miner3, then survey1. Pad queue is still the throughput limit until cable loading works.
- 02:30 check-in: phase 1 foundry fits all done except lava-wall leftovers (builder2 retrying) and the certus pillars (lava1). Cable loading diagnosed: the rack's network is separate from the store's, so Kyle has to join them. Alloy phase is held until ~06:00 so the foundry keeps working overnight.
- 03:15 check-in: rescues worked (miner3, survey1 fuelled; miner1 freed). Miners sent home (they resumed mining). Phase 1 foundry done. New: drones place the budding certus (factory_f2_budding, builder4); AE2 bench (builder5, inscribers being made); survey1 redoing the factory survey.
- 04:05 check-in: 8 budding certus placed by drones; AE2 bench 3/5 inscribers in; scanner method fix (scanBlocks); survey re-sent. miner1 parked; miner3 blocked by stone on its way home at -4448 56 1604.
- 04:50 check-in: STATUS STALE since 04:28 (all units at once; looks like a server restart or the controller stopped pushing). Found before that: survey1 got through 16 of 32 survey steps, then failed to re-equip the scanner and climbed into the roof; fixed (door escape + scanner retry). crafter1 out of raw iron, so the AE2 bench stalled at 3 of 5 inscribers.
