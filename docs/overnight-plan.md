# Overnight plan, 18 Nov: the master list

**Read this first at every check-in.** Tick items, add new ones and keep it current.
Kyle's goal for the morning, in his words: everything moved into the factory and set up
well; AE2 set up and the foundry plan under way; idle bots docked; crafting that doesn't
wait on Crafty; the Geo Scanner mapping the base as we build; the foundry, docks and
screens done and matching; drones self-sufficient for fuel and not crashing or getting
stuck; rescue drones that save broken ones and report what went wrong.

Status key: [x] done · [~] under way · [ ] not started · [K] waiting on Kyle

## Every check-in (about every 45 min until 08:00)
1. `python3 /tmp/st.py`, then go through every unit's state, its last log line and how long since it was heard.
2. Anything stuck, stranded, silent or idle: fix it, rescue it or give it work. Look for the cause, not only the symptom.
3. Move the next item below forward. Append a dated line to docs/session-notes.md.
4. Schedule the next check-in.

## Ground rules (never break)
- Send no orders through the old pad shaft at more than one drone at a time; the pad queue (41b3702) handles that.
- Leave lane mode OFF until one drone docks successfully.
- No chunk loaders out (Kyle took them all in).
- Destroy no stored items (only darkstone and kivi are allowed to go).
- No surface digging near friends' bases: nothing north of the base mountain.
- When committing orders, `git add commands.json` only; never add other agents' work-in-progress.
- Check a unit's state before rebooting it.

## A. Fleet health
- [x] Pad-shaft jam: Crafty now calls one drone down at a time (41b3702)
- [x] Rescue duty live on Crafty (1c885d0); named rescuer = Dispensable (rescue1)
- [x] miner3 (Charcool) rescued at 02:28; then it went coal-hunting, so sent home (03:12). Was: stranded at -4463 60 1521: Dispensable fetching fuel (01:20). The other TuffLuck sits above it in the same shaft and gets dug out first if it is in the way
- [ ] Sticky (builder3): out of fuel at -4423 77 1531 under the factory roof and silent since. Order `rescue Crafty who=Sticky problem=fuel` (the route in through the door hasn't been tested)
- [x] miner1 freed; it resumed its old plot (mining at y -12), so sent home 03:12. Was: TuffLuck (40) at -4463 61 1521 "path blocked" by Charcool: should clear once Charcool is fuelled
- [ ] DropIt (foundry1): it was "stuck under turtle"; check it is clear now the jam is fixed
- [ ] Fuel self-sufficiency: lava rounds keep running (Pushy/lava1); watch the fuel line on the board (coal / charcoal / lava)
- [x] Renamed to task names (3770163) and applied by reboot (01:36): builder1-7, lava1, foundry1, survey1, rescue1, mapper1, crafter1/2, miner1-3; new miners name themselves miner<id>. Old names still work as order targets
- [x] Watchdog no longer reboots drones that are only waiting their turn in the pad queue (ec45358). It was rebooting builders and costing them their place

## B. Crafting throughput
- [x] Counter back as Crafty's crafting assistant: splits each load's crafting, about half the crafting time (`assist Counter on=1`)
- [ ] Watch Crafty's `assist` log for failures; Counter's wired modem has to be on
- [ ] Longer term: AE2 autocrafting (see E)

## C. Survey (Geo Scanner mapping the base)
- [~] survey1's scans failed again: AE's method is scanBlocks, not scan (fixed d1ba0b6). Re-sent the survey at 04:05. Earlier: rescued at 02:30. Was: dry under the roof at -4441 75 1520. builder6 tried to walk in with lava (02:25) and its walk failed at 21 6 5. Left to rescue duty (the route through the door); else Kyle picks it up and puts it in its home. Also fixed: the scan had used the wrong tool side (geoOn). ORIGINAL NOTE: survey1 got the scanner and started, then ran out of fuel at -4441 75 1520 (01:53): it set out on 776 because labs didn't top up fuel. Fixed in 9b05162: a lab refuels first when under 1,500. survey1 is in the rescue queue after miner3; once refuelled, rerun its survey lab
- [x] mapper1 mapped the old base: maps/oldbase.json on the status branch
- [~] mapper1 maps the factory from outside (`factory_now`, 01:41)
- [ ] When the maps land: `python3 tools/survey.py pull`, `survey.py rack`, then fix rack rows 3-4 (M.LANE, LN.home, rack.lua)
- [ ] After each build phase: rescan the area just built

## D. Docks (rack 1, 8 × 4)
- [x] One-drone docking test: builder1 docks in its home -4428 72 1521 fine. The real fault was a lab bug: the verb's name shadowed `base`, fixed in ac40669. The network names a docked turtle turtle_<n>, where n is the network's counter, not the computer id; the fallback is in LN.bay
- [x] Found why cable loading fails (02:28, lab verb `net`): rack 1's cable is NOT on the storage controllers' network. From builder1's bay it reaches only RackBoard, 17 monitors, 3 Sophisticated chests and 3 limited barrels (the "router" area). Sortnado sees no turtles at all. **Kyle: join the rack link cable to the cable that reaches the storage controllers / Sortnado's computer** (one cable piece between the two). After that, bay loads work with no code change
- [ ] Then turn lane mode on for every helper (`rebase <h> lane=1`, a few at a time) so idle drones sit docked in rack 1. builder1 is already docked on lane mode
- [ ] Docked drones load over the cable (Sortnado pushes into `turtle_<id>`); no more pad trips
- [x] Top FACTORY monitor stuck on "not heard yet": only the first monitor touching the computer was ever drawn; now every one is (eabaaae, RackBoard rebooted)
- [ ] Kyle: rack rows 3-4 modems/monitors, once the survey confirms the rows

## E. Foundry v2 (docs/foundry-v2.md)
- Phase 1
  - [x] link (cable): builder4 + builder6 164/164 done. Was: Dusty x26-34; Dusty's x≥35 done except "dig at 35 0 22 (cannot get to it)"; HopTo's x≤25 re-sent to Observant, who says it's done
  - [x] lava wall: builder2 80/80, builder5 79/80 (one cell left)
  - [x] certus pillars + barrel: lava1's lab done (40/41 at 03:10)
  - [x] clear: both shares done (Dispensable)
  - [x] power: done, except the gas-burning generator (none in stock)
- [K] Works computer: Kyle runs `label set Works` and the installer at -4413 71 1533
- [ ] `probe Crafty` (after link + Works)
- [ ] `foundry DropIt on=0`, then phase 2 `alloy` (DropIt): the foundry is down a few minutes
- [K] Kyle clicks the alloy cell's modems: -4409 71 1535 / 1537 / 1541
- [ ] Phase 3 `ore` (Sticky, or whoever is free)
- [K] Kyle clicks the ore-line modems: -4406 71 1530 / 1531
- [ ] Phase 4 `ae2` when the parts exist
- [ ] Phase 5 `close` (after all of Kyle's clicks)
- [ ] Lava cauldrons from the hut into the foundry's lava wall (the hut is not kept)

## F. AE2 (docs/ae2-bootstrap.md)
- [x] Certus farm: builder4 placed 8 of 9 flawed budding certus (about 03:40). Only 8 were in reach; the 9th slot -4419 78 1525 is empty (Kyle can add one). **First harvest from about 06:45** (`python3 tools/certusfarm.py first bench=v2`)
- [K] Kyle clicks the certus barrel: -4414 71 1531
- [~] AE2 bench: 3 inscribers placed with the silicon, logic and calc presses (03:26). builder5 is finishing it: 2 more inscribers, the engineering press, the charger. Then the `fluix 8` lab
- [ ] Harvest with the `pick` verb (first crop about 3 h after placing)
- [ ] ME controller, drives and crafting CPU (phase 4 `ae2`); ME bridge at -4414 71 1539 (Kyle clicks it)

## G. Move the old base into the factory
- [~] Bridge cable from the old base to the factory network (HopTo's lab)
- [ ] `haul Crafty on=0`
- [ ] Move Crafty and Counter to the factory bench, with the floppy and drive
- [ ] `drain Sortnado from=minecraft:chest_*` (only once Crafty is moved: those chests are Crafty's store today)
- [ ] `rebase all ...` with lane on, after the docking test passes
- [ ] Hut torn down after the cauldrons have moved

## H. Storage
- [ ] Colour zones: marker test to map controller slots to barrels, then mark the zones on the existing redwood/oak barrels
- [ ] Re-sort after the old base drains

## I. Screens: cohesive look
- [x] Rack board restyled to match the store and map screens
- [x] Fixed the top "not heard yet" board (D)
- [ ] Rack homes show the new task names once the rename lands

## J. Older threads from today (checked against git log 17-18 Nov; none dropped)
- [ ] Mekanism stage 3 (crusher, purification, separator, pump) and the stage 4-5 machines: folded into foundry v2 phase 3 `ore`. Crafty makes them on demand; check which ones exist (`probe`, Crafty's missing list)
- [x] Quartz line: Kyle says it's not needed now; certus from the ME farm replaces it. Leave it idle
- [ ] Foundry generator ran dry twice (17 Nov 03:36 and 23:18): lava fuel for it goes on the fuel watch; the v2 power row replaces it
- [ ] Lava: hut farm (7) plus the 11-unit dripstone row, worked by Pushy/lava1. The hut cauldrons move to the v2 lava wall later; keep lava above 20 on the board
- [ ] Screens: the six screen computers HopTo fitted (17 Nov). Check all of them report and match the dash style (store, map, rack, factory)
- [x] Mining stays paused (Kyle, 01:30): send miners out ONLY if something runs out. They would need chunk loaders, which Kyle has
- [ ] Drafted ex-miners and the extra turtles Kyle picked up: account for every turtle id. Any that aren't reporting get placed in a rack home once docking works
- [ ] AE2 path beyond certus: meteorite compass, sky stone and presses (Kyle has the presses), then the ME bridge so Sortnado uses ME as the store (code is ready: Sortnado)
- [ ] Server tweaks to offer Kyle: the turtle_can_use tag and chunkyTurtleRadius

## Kyle's to-do for the morning (one list)
1. Works computer: `label set Works` + installer at -4413 71 1533
2. Right-click modems: alloy cell -4409 71 1535/1537/1541 · ore line -4406 71 1530/1531 · certus barrel -4414 71 1531 · later the ME bridge -4414 71 1539
3. Rack rows 3-4 parts (after the survey)
0. **Most important:** join rack 1's cable to the storage controllers' cable (one piece). This unlocks loading at the rack, so no more pad queue
0b. survey1 is out of fuel under the roof at -4441 75 1520: pick it up and place it in its rack home (or give it 2 lava buckets) if the rescue drone hasn't got it
4. Optional server config: `computercraft:turtle_can_use` tag for modems/cable; Advanced Peripherals `chunkyTurtleRadius=1`
