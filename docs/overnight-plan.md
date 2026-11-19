# Overnight plan, 18 Nov: the master list

**Read this first at every check-in.** Tick items, add new ones and keep it current.
Kyle's goal for the morning, in his words: everything moved into the factory and set up
well; AE2 set up and the foundry plan under way; idle bots docked; crafting that doesn't
wait on Crafty; the Geo Scanner mapping the base as we build; the foundry, docks and
screens done and matching; drones self-sufficient for fuel and not crashing or getting
stuck; rescue drones that save broken ones and report what went wrong.

Status key: [x] done · [~] under way · [ ] not started · [K] waiting on Kyle

## NOW (19:45, Kyle back): the factory pass
Rescan done 19:30 (13 scans). Plan vs world (`python3 /tmp/plancheck.py`-style check of tools/foundry2plans.py against data/world.json):
- [x] lava wall: 16 cauldrons filling (lava_cauldron). Lava rounds now `how=wall` (crafter1), lava1
- [ ] hut cauldrons out and the hut down, once a wall round has worked
- [ ] link: cable missing at 35 -1 22 = the alloy cell is cut off from Works (builder1 fixing, lab dig|<name>). Certus barrel modem 34 0 13 + cable missing
- [ ] steel is the bottleneck: no steel dust. Infusers (2) are placed; Works sees none (the cut cable). Then steel -> smelter #3, crusher, energy cube
- [ ] budding: all 9 flawed budding quartz have decayed to quartz blocks/damaged. Needs new flawed budding (AE2: quartz block + charged certus in water) or a different certus source
- [ ] power: east-wall universal cable row (43 1 6-16) and the gas-burning generator not placed
- [ ] ore: modem 42 0 13 and cables 42 -1 13..16 not in; purification/injection/crystallizer/washer/dissolution not made (refined obsidian, alloys, ultimate circuits)
- [ ] ae2 phase: 0 of 33 (controllers etc.). AE2 agent working the chain; bench: builder5 (inscribers made 19:29)
- [ ] close: click holes still open (wanted until the cell's modems see their machines)
- [ ] old-base bridge cable (y73 z1521) to bury; racks 2-3 with screens after
- Known: order.py REPLACES commands.json: space orders >= 30 s apart

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
- [ ] AE2 bench: 3 of 5 inscribers placed (silicon, logic and calc presses in). Blocked: **crafter1 is out of raw iron** ("short of 3 raw iron"). The store probably has iron, but crafter1 is on a separate network in the old base and can't reach it. builder5 holds the charger and the engineering press. Fix: Kyle puts ~16 iron into crafter1's chests, or crafter1 moves into the factory (section G). Then re-run builder5 with /tmp-style ops: fetch inscriber=2 + charger + eng press, site, walk 28 2 21 …
- [x] First harvest 07:12: 80 certus crystals (builder2), being handed in
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
- Status was silent 04:28-07:00 (server restart?); it came back by itself at 07:00
- crafter1 is out of raw iron: drop ~16 iron ingots or raw iron into its chests in the old base (AE2 bench needs 2 more inscribers)
1. Works computer: `label set Works` + installer at -4413 71 1533
2. Right-click modems: alloy cell -4409 71 1535/1537/1541 · ore line -4406 71 1530/1531 · certus barrel -4414 71 1531 · later the ME bridge -4414 71 1539
3. Rack rows 3-4 parts (after the survey)
0. **Most important:** join rack 1's cable to the storage controllers' cable (one piece). This unlocks loading at the rack, so no more pad queue
0b. survey1 is out of fuel under the roof at -4441 75 1520: pick it up and place it in its rack home (or give it 2 lava buckets) if the rescue drone hasn't got it
4. Optional server config: `computercraft:turtle_can_use` tag for modems/cable; Advanced Peripherals `chunkyTurtleRadius=1`

## AE2 build log (18 Nov, by command; plan: docs/ae2-factory.html, tools/ae2plan.py)
Rule (Kyle): place by command only what we could feasibly make. Nothing needing nether stars (no Nitro tier).
- Power bay BUILT: 7 niotic thermo gens (42 1 17-23) on lava (42 0 17-23), 300 FE/t each measured (basic 40, nitro 1750). Tank NBT: `{tank:{amount:4000,id:"minecraft:water"}}` (lasts ~2 h at nitro rate; refill by command until the sink feed is in). Universal cable chase (43 1 17-23) capped with slabs; power to the controller along y -2, z 23.
- Core BUILT: controller line (31 0 19-23) + tower (31 1-4 21), online. Vault: 4 ex_drives (29-32 1 17) + 4 dense cells above; cells in drive 1 (`inv:{itemN:{id,count}}`). Terminals at desk 33 1 18-20 (cable_bus NBT: `{cable:{id:..},east:{id:"ae2:crafting_terminal"}}`).
- Trunks: N blue (31 -1 15-19, bridge branch 32-34 -1 15), W green (31..33 -1 20; 33 0 18-20), A orange (31-34 -1 21, dips to y -2 under the CC spine at x 35, 36-38 -1 21, then 38 0 17-22).
- Storage link BUILT: storage bus + ExtendedAE wireless connector at each storeroom controller (cable at 10 5 14 and 17 5 14, connectors at 10 5 13 / 17 5 13), paired by NBT `freq` (4242, 4243) with connectors on the vault (30 3 17, 31 3 17). Remote ends show powered.
- ME Bridge at 34 0 15 beside Works (Works is still switched off; its code must stop announcing foundry_ready before it is turned on).
- Induction card: provider placed behind infuser C (38 1 17); the card can't be set by NBT (no `upgrades` key). Spawning the card as an item was refused; Kyle to get one (give) and try it in the provider.
- To check in game (Kyle): crafting terminal shows the barrels; provider has an upgrade slot for the card.
- Removed and not yet replaced: Nether pump + entangloporter (-623 32/33 373 in the Nether, 96x96 lava sheet; chunk no longer force-loaded).
- 22:15 Storage link confirmed by Kyle (terminal shows the barrels). Terminals placed by NBT need `enabledKeyTypes:["ae2:i","ae2:f"]` or they show fluids only.
- 22:20 Induction card WORKS: provider NBT `upgrades:[{count:1,Slot:0,id:"appflux:induction_card"}]`; an infuser and a smelter set to 0 energy refilled in seconds with no cable touching them. A provider with the card also takes FE in from a cable beside it.
- Alloy row: providers + cards behind z 17-22 (38 1 17-22); flux accessor at 38 1 23 on the old riser (FE from the generators into ME; 64k FE cell in drive 2). Enrichment chamber (39 1 23) has the accessor behind it, no provider yet. Old wired modems still under the machines (39 0 17-23).
- Still to do on the row: infusion feeds (export bus under infusers), the 4 new machines, patterns, trunk O and the ore line providers; then retire the universal cable under the ore line.
- 22:35 Alloy row wired for crafting: enrichment chamber now has its provider (38 1 23); the flux accessor moved into the floor under it (39 0 23), ME cable at 39 0 22. Export-bus feeds with crafting cards under infuser C (enriched carbon) and R (enriched redstone). Machine sides by NBT: `component_config:{config3:[I;front,left,right,back,top,bottom],eject3:1b}`, 7 = in/out (back), 9 = extra (bottom).
- Patterns by NBT work: provider `patterns:[{Slot,id:"ae2:processing_pattern",count:1,components:{"ae2:encoded_processing_pattern":{sparseInputs:[{"#":1L,"#t":"ae2:i",id:..}],sparseOutputs:[..]}}}]`. Written: iron>enriched iron, enriched iron>steel dust (infuser C); osmium>basic circuit, copper>infused alloy (infuser R); steel dust>steel ingot (smelter 1); coal>enriched carbon, redstone>enriched redstone (chamber).
- Two crafting CPUs (single 16k crafting storage blocks) on the vault, 29 3 17 and 32 3 17.
- Not yet proven: a full craft from the terminal (Kyle to request steel).
- 22:45 FIRST ME CRAFT: Kyle ordered 4 steel ingots; iron > enriched iron > steel dust > ingot ran through the infuser and smelter and finished. Lesson: patterns merged into a running provider are not picked up; place the provider with `patterns` in the setblock NBT (set air first).
- 22:50 Alloy row finished (39 1 24-27): infuser D, infuser O, osmium compressor, combiner, each with provider + card and a feed under it (enriched diamond, enriched refined obsidian, osmium ingot; combiner's feed not set). New machines need `config0:[I;1,1,1,1,1,1]` (energy in). Patterns: reinforced and atomic alloy, refined obsidian dust and ingot, refined glowstone, enriched diamond / refined obsidian, obsidian > 4 obsidian dust.
- Next: trunk O + ore line providers, crystal garden (13 flawless budding in the store), crystal lab, bigger CPUs, matrix, requesters, fuel station, gas plant.
- 23:00 Ore line on ME (2x): providers + cards behind crusher/chamber/smelter (43 1 11-13) AND in the floor under the chamber and smelter (42 0 12-13), because RCON commands cap at 1446 bytes = 5 patterns per setblock. Machine sides back and bottom = in/out. 10 ores: raw > 4 dust per 3 (chamber), dust > ingot (smelter): iron gold copper tin osmium | lead silver nickel zinc aluminum. Not yet: uranium, platinum, iridium; crusher patterns. Joined to the core by wireless connectors (freq 4244: 43 2 13 and on the vault at 29 4 17); cable under the providers at 43 0 11-13.
- 23:45 Crystal garden BUILT (28-30, y 1-4, z 4-12): 3 flawless budding (29 2 6/8/10), 4 growth accelerators (must be `[facing=up]` to pass the network vertically), planes in the floor and the lintel on a subnet (fluix glass cable) powered by a quartz fiber at 29 0 6, storage bus (certus crystal only) at 29 0 5 into an ME interface at 29 -1 5 on trunk N (extended: 31 -1 5-14). Old farm area was already empty.
- 23:55 Processor press ON ME, using the bench that is there (the 4 presses are in their inscribers; the swap to extended inscribers is not needed yet): pattern providers in the floor under the inscribers (28 0 18-21, 23), inscribers `auto_export:"YES"`. Prints: silicon, logic (gold), calculation (certus), engineering (diamond); assembly inscriber (z 23, blocking mode) makes the three processors. Silicon: certus crystal > dust (ore-line crusher) > silicon (alloy smelter 2): UNTESTED (does Mekanism crush certus?). Charger (z 22) not automated. W trunk extended to 28 -1 20.

## KYLE'S BRIEF, 18 Nov 23:49 (the master list for the night and after)
His words, condensed: all the ME machines we discussed set up, plus anything else we need. Storage linked to the barrels, with more space. A system to fuel the drones. All drones parked in their bays, not AFK overhead ("they should go back to their wee home"). Maybe Create. Revisit the overall design: cooler, more sci-fi, animated screens, levers that do things, much more ComputerCraft + ME + peripherals synergy, a control room for the drones with the map as in real Minecraft. Clean up the old factory. Terraform around the factory. Pipes shipping items about, conveyors maybe, drones doing things. Redo the visuals to match. Only blocks we could reasonably have (no nether stars). "Everything sorted by tomorrow. Figure out any barriers."

### Working rules for the night
- I only work inside a turn: check-ins are scheduled; each one takes the next item, verifies it through the ME desk or RCON, logs here.
- Verify recipes myself: `tools/order.py me crafter1 craft=<id> n=<n>` then read `me` in crafter1's status (stock, log, busy CPUs).
- Patterns: provider placed with `patterns` in its setblock NBT, 5 per command (1446-byte RCON limit).
- Feasible blocks only. Kyle's own blocks are collected by drones, not deleted.

### A. ME (function)
- [x] Core, vault, terminals, storage link, bridge, alloy row (11 machines), ore line 2x (10 ores), garden, processor press, ME desk
- [ ] Recipe proving through the ME desk: logic/calc/eng processors, silicon (does the crusher take certus?), circuits, alloys, refined obsidian. Obsidian > dust moved to the CRUSHER (the chamber refused it and jammed a CPU)
- [ ] Export-bus crafting cards tie up CPUs: add CPUs (4+), or drop the cards and use a requester
- [ ] Crystal lab row (ex charger, crystal assembler, reaction chamber, circuit cutter); fluix + charged certus recipes
- [ ] Assembler matrix + crafting patterns (control circuits tiers, cables, turtles, modems...)
- [ ] Requesters / stock keeping; more cells (space); uranium/platinum/iridium ore patterns
- [ ] Gas plant + 3x-5x; thermo generator water by ME export bus (no wrench): storage bus on a sink, fluid export bus on each generator
### B. Fuel
- [ ] Nether lava (pump + entangloporter at -623 31 373): needs Kyle to set the frequency (2 clicks). Until then: coal blocks (1,004 in the store = ~800k moves) loaded at the docks
- [ ] lava1 is stranded at 0 fuel at -4451 107 1521: rescue
### C. Drones home
- [ ] Why "Could not get into my home in the rack (?)" and "No bay modem switched on": fix LN.toHome / switch the shelf modems on (clickUp), so idle drones sit docked
### D. Design v2 (for Kyle to review before building): sci-fi look, control room with the live map, animated screens, levers wired to CC, ME <-> CC synergy (ME desk screens, request buttons), Create conveyors where they earn their place, visuals restyled
### E. Old base cleanup, terraforming (tools/terraform.py), leftovers in the hall (builder1 sent 23:50)
### Barriers (need Kyle or access)
- Entangloporter frequency (GUI only). Wrench/bucket clicks by drones need the datapack tag widened (server datapacks folder). No CC-specific MCP found for NeoForge; the ME desk + RCON + /computercraft cover it.
- 00:05 (19 Nov) ME desk live (Works + ME Bridge): `me` in crafter1's status. PROVED: logic processor x2 (certus > dust in the crusher > silicon > print > processor). Obsidian > dust is a CRUSHER recipe (chamber refused it, CPU jammed; fixed). 3 CPUs now. Garden yields ~50 certus / few min. Sortnado says "store full": ME cells added (256k) but Sortnado still needs an overflow path into ME (ME interface on its wired network).
- Fuel station placed: entangloporters at 43 1 26 (foundry) and -623 33 373 (Nether, on the pump), frequency "lava" set by Kyle on both; ME interface at 43 1 27 on trunk A (under-floor branch along z 27). NOT pumping yet: the pump shows no power. Power is tight: the 7 niotic gens (2,100 FE/t) are fully drained every tick (ME FE cells charging + AE use 417 AE/t). Next: check again; if still dry, feed the foundry entangloporter directly / add generators.
- Thermo tanks were down to 527 mB after 2 h (not "2 h per tank" at niotic: ~29 mB/min): refilled to 4000 at 00:00. NEEDS the ME water feed tonight; until then refill every 90 min.
- Drones home: helper tries the rack three times and names the failing stage (pushed; drones pick it up at their next restart). Most idle helpers are docked. lava1 rescue ordered.
- Kyle: has lent an End Automata turtle (which one? asked) for wrench/bucket clicks. Barrier left: none of the GUI kind for now.
- 00:20 FUEL LINE WORKS: the Nether pump only takes power on its BACK (pump facing west, a 2-block universal cable from the entangloporter to its east side). Lava reaches ME (194,000 mB and climbing). ME Canner at 42 1 27 with a provider under it (bucket + 1000 mB lava > lava bucket): 4 buckets ordered through the desk, made. Stock keeping (requester) still to add.
- 00:15 GENERATOR WATER BY ME: covered cables over the generators (42 2 17-23) with fluid export buses facing down; a sink at 42 3 18 on a storage bus is the endless water; wireless connector 42 3 17 <> vault (freq 4245). Tanks hold at 4000. No more refills.
- PROVED through the desk: logic processor, engineering processor, lava bucket. Running: atomic alloy (needs the refined-obsidian infusion chain). The diamond feed's crafting card stocked 64 enriched diamond in infuser D (diamonds used: ~70). lava1 rescued.
- Kyle 00:01: the End Automata turtle is in the store (an item); wants the redo plan; add a Create door and robot guards to the list.
- 00:35 Kyle (00:01): add a Create door and robot guards to the list; wants the redo plan. DONE: docs/factory-v2.html (tools/factoryv2.py), published as "Factory v2 Concept": blast gate (Create gantry + createaddition electric motor, Player Detector), the Bridge (13x4 map wall in map colours, consoles, levers on redstone relays, Create split-flap departures board via display link), guards (melee turtles, patrol ring, never swing within 6 blocks of a player), ore belt, tinted glass floor over the trench, light strips, drone yard on the old base's site. All block ids checked on the server. Stages A gate, B Bridge, C dressing, D guards, E old base + grounds. NOT built: waits for Kyle's review (his calls are on the page).
- The End Automata turtle is an item in the store: have crafter1/a drone place it and label it (to do), then use it for wrench/bucket clicks.
### Night shift 2 (00:13-00:35, 19 Nov)
- Atomic alloy job: it had stalled holding 3 obsidian dust in a CPU (the chain wants enriched refined obsidian fed by an export bus with a crafting card, which itself needs a free CPU: with 3 CPUs it deadlocked). Cleared by re-placing the three CPU blocks. NOT re-run yet: retry now there are 6 CPUs.
- CPUs: 6 now. Three more single 16k blocks under the floor on trunk W (29/31/33 -2 20). Temporary: the plan's CPU wall replaces them.
- STORE FULL FIXED. ME Interface at 16 5 14 (west of the storeroom's AE cable) with a CC wired modem on top (16 6 14) joined to Sortnado's cable. A full-block wired modem placed as `[modem=true,peripheral=true]` attaches by itself: no click needed. sortnado.lua: an `ae2:interface` on the cable is the overflow; what no barrel takes goes into ME. Sortnado now says "sorting"; first pass sent 42 items.
- STOCK RULES on the ME desk (works.lua): lava buckets 64, steel 128, logic/calc/eng processors 16 each, basic circuits 32. Checked every minute, 16 at a time, one job per item, always one CPU left free. `tools/order.py me crafter1 rule=<id> n=<target>` (n=0 drops it); kept in `.me_rules` on Works. Seen working: buckets 59 > 64, basic circuits 0 > 32, engineering 2 > 11 and rising.
- ME desk bug fixed: several orders in one commit were lost (a bridge call swallowed the queued rednet messages). A listener now queues them; 6 in one go all arrived.
- CRYSTAL LAB started (33 1 7-8, providers at 32 1 7-8, cable 32 -1/0 7 off trunk N):
  - Extended Charger (33 1 7): certus > charged certus. It has no auto-export: an import bus under it (33 0 7, `enabledKeyTypes:["ae2:i"]`, the default is fluids only) takes the charged crystals.
  - Crystal Assembler (33 1 8, `auto_export:"YES"`): 4 charged + 4 redstone + 4 nether quartz + 100 mB water > 8 fluix (recipe read from ExtendedAE's source). Water comes from ME (the sink).
  - PROVED: 16 fluix through the desk.
  - Not yet: reaction chamber, circuit cutter (block of gold/diamond/silicon > 9 prints; quartz block > 4), the processor recipes in the assembler.
- ASSEMBLER MATRIX BUILT (29-33, y 1-5, z 25-27; frame edges, glass faces, wall floor; inside: 3 pattern cores y2, 3 crafter cores y3, 3 speed cores y4), fed from the controller's south end by a cable in the floor (31 0 24-25). Formed.
  - Pattern core NBT: `pattern:[{Slot:n,id:"ae2:crafting_pattern",count:1,components:{"ae2:encoded_crafting_pattern":{inputs:[9 stacks, {} for empty],result:{id,count},recipeId:"<recipe id>",canSubstitute:1b,canSubstituteFluids:0b}}}]`. 3 patterns fit in one 1446-byte command, so 9 patterns tonight (108 slots: Kyle can add the rest by hand from a pattern terminal). Generator: /tmp/mx/gen.py (to move into tools/).
  - Patterns: advanced / elite / ultimate control circuit; quartz fiber, fluix glass cable, blank pattern; computer, turtle, chest.
  - PROVED through the desk: 2 advanced control circuits, 1 elite control circuit (reinforced alloy chain works), 8 fluix glass cable (quartz fiber on the way), 1 chest.
  - NOT WORKING: the turtle pattern. The bridge answers NOT_CRAFTABLE (the desk now reports the bridge's `ae_crafting` events in `me.events`). The recipe matches CC's own file (7 iron, computer, chest; `computercraft:transform_shaped`), so either AE2 rejects the transform recipe or the result carries components the bridge does not match by name. Next: read `getCraftableItems` for turtle, and see whether the computer pattern runs.
  - Running at 00:45: ultimate control circuit (needs atomic alloy: the same chain that stalled before), computer, blank pattern (needs quartz glass: no pattern for it yet).
- STEEL STALLED, fixed: after the CPU blocks were re-placed, the enriched-carbon feed bus under infuser C (39 0 17) sat dead (no crafting link, no `e` in its node) with 16 enriched iron waiting. Re-placing the bus restarted it: steel 63 > 95 and rising. Lesson: after re-placing CPUs, check every feed bus (`data get block ... up.gn`).
- Stock rule bug fixed: a rule re-ordered while its first job was still running (calculation processors went to 31 of 16). An order now stays open until what it asked for has arrived, or 15 minutes.
- Infuser C holds 15 redstone in its energy slot: left over from the old drone-run foundry, harmless.
- NOT DONE: the End Automata turtle (the store has 1 `computercraft:turtle_advanced`, which should be it). crafter1's launch routine only knows plain turtles: needs a `put` order (pull the item, place it on the pad, fuel, turn on, label). Not urgent now that machines are set by command.

### Next shifts (function): results of the cable/turtle/elite crafts; atomic alloy re-run; `put` order for the End Automata turtle; lab row rest (reaction chamber, circuit cutter); more matrix patterns (smart/dense cable, ME parts, modems, CC cable, Mekanism casing/tiers); uranium/platinum/iridium; Mekanism speed upgrades in the alloy row (steel is slow: 10 s an infusion); gas plant; requesters. Tests to update: foundrytest/foundryhelper (old layout), sortctl "by name on the network" (failed before tonight's change too).
