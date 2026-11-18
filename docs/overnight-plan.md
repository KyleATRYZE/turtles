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
- [~] Charcool (miner3) stranded at -4463 60 1521: Dispensable fetching fuel (01:20). The other TuffLuck sits above it in the same shaft and gets dug out first if it is in the way
- [ ] Sticky (builder3): out of fuel at -4423 77 1531 under the factory roof and silent since. Order `rescue Crafty who=Sticky problem=fuel` (the route in through the door hasn't been tested)
- [ ] TuffLuck (40) at -4463 61 1521 "path blocked" by Charcool: should clear once Charcool is fuelled
- [ ] DropIt (foundry1): it was "stuck under turtle"; check it is clear now the jam is fixed
- [ ] Fuel self-sufficiency: lava rounds keep running (Pushy/lava1); watch the fuel line on the board (coal / charcoal / lava)
- [~] Rename everything to task names (agent running): builder1-6, lava1, foundry1, survey1, rescue1, mapper1, crafter1/2, miner1-3. Applied with `reboot all`

## B. Crafting throughput
- [x] Counter back as Crafty's crafting assistant: splits each load's crafting, about half the crafting time (`assist Counter on=1`)
- [ ] Watch Crafty's `assist` log for failures; Counter's wired modem has to be on
- [ ] Longer term: AE2 autocrafting (see E)

## C. Survey (Geo Scanner mapping the base)
- [~] Comparable (survey1) has its lab queued: fetch the scanner, then 14 scans over the factory. It was stuck in the pad jam; it was next down at 01:19
- [~] BlockParty (mapper1) maps the old base (`survey ... name=oldbase`, 01:21)
- [ ] When the maps land: `python3 tools/survey.py pull`, `survey.py rack`, then fix rack rows 3-4 (M.LANE, LN.home, rack.lua)
- [ ] After each build phase: rescan the area just built

## D. Docks (rack 1, 8 × 4)
- [ ] One-drone docking test (needs an idle drone on the latest code):
      `tools/order.py lab <drone> clear=1 "ops=dock|in;peripherals;look;dock|out;home"`
      It reports what blocks home -4428 72 1521 (HopTo stopped one block short)
- [ ] Fix whatever blocks it. Then test 2 drones, then turn lane mode on fleet-wide
- [ ] Docked drones load over the cable (Sortnado pushes into `turtle_<id>`); no more pad trips
- [ ] Top FACTORY monitor says "not heard yet" while the one under it works (Kyle's screenshot, 01:19): find out why rack.lua has two factory boards
- [ ] Kyle: rack rows 3-4 modems/monitors, once the survey confirms the rows

## E. Foundry v2 (docs/foundry-v2.md)
- Phase 1
  - [~] link (cable): Dusty x26-34; Dusty's x≥35 done except "dig at 35 0 22 (cannot get to it)"; HopTo's x≤25 re-sent to Observant, who says it's done
  - [~] lava wall: OnRepeat x≤35, ButtonUp x≥36
  - [~] certus pillars + barrel: Pushy's lab
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
- [ ] Certus farm: drones place the 9 flawed budding certus from storage on Pushy's pillars (slots: `tools/certusfarm.py kyle`)
- [K] Kyle clicks the certus barrel: -4414 71 1531
- [ ] `make Crafty item=ae2:inscriber n=5`; certusfarm.py bench and fluix labs
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
- [ ] Fix the top "not heard yet" board (D)
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
4. Optional server config: `computercraft:turtle_can_use` tag for modems/cable; Advanced Peripherals `chunkyTurtleRadius=1`
