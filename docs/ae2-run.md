# The AE2 run: from certus crystals to a running ME network

Tonight's way from the 92 certus crystals in the store to an ME network in
the foundry hall's AE2 room (x 28-34, z 17-23), built by drones, with the ME
Bridge on our cable. Everything is printed by tools; nothing here sends an
order.

- `python3 tools/ae2run.py orders now renew=<dead slots>` prints the orders below.
- `python3 tools/ae2run.py bom now|full` prints the bill of materials, worked out from
  factory.lua's own recipes.
- `python3 tools/ae2run.py dead` lists the farm's slots from the last survey.
- The lab steps come from `tools/certusfarm.py`. The fit plans come from
  `tools/foundry2plans.py` (`ae2power`, `ae2`).

## Where things stand (survey of 18 Nov, 19:29)

- **The farm is mostly dead.** Seven of the nine budding blocks are plain
  `ae2:quartz_block`: slots 0, 1, 2, 4, 5, 7 and 8. Slots 3 and 6 are
  damaged. A flawed block lasts about 36 growth steps (4-5 hours). These
  were placed at about 03:40, so they have run their course. No more
  crystals will come until the blocks are renewed (step 2).
- **The bench has no power.** The floor under 28 1 18-23 is plain polished
  deepslate. No fit plan ever put cable there (the old `ae2` plan powered
  only an energy acceptor). Step 0 does it.
- **The power has no source joined to it.** The survey finds none of the
  `power` job's universal cable row at x 43 y 1 (z 6-23). It has the heat
  generators (42 1 18-21) and the cube (42 1 23), but no cable touching
  them; the old plinth cable at x 42 is gone too. The z 24 run under the
  east door's walkway ends at 43 0 23, under an empty 43 1 23.
  - Rerun the `power` fit first (step 0p). It puts in only what is
    missing.
  - Then check that the cube fills. Unverified: which sides Mekanism's heat
    generators give power from. They were put in facing the row.
  - Until this is fixed, nothing in the AE2 room has power.
- **The alloy cell's riser is missing.** The cell's power row (38 1 17-23)
  is not joined to the power run under the east door's walkway (38-43 -1
  24): 38 0 23 and 38 -1 23 are not cable. So the alloy cell's machines
  probably have no power. That is the alloy job's to finish. The AE2 room's
  trunk joins the z 24 run itself, at 37 -1 24.
- **Floor modems clicked before their machine stood on them stay off.**
  CC: Tweaked's `WiredModemFullBlockEntity` checks for a peripheral when
  it is clicked. With none beside it, it stays off, and it does not pick up
  a machine placed later. The alloy and ore-line clicks were made from where
  the machines now stand (`walk|39|1|17;clickDown`), so they most likely
  did nothing. The fix is the new `hole` verb: click from the click hole
  beside the modem, as `bridgeclick` does (the ops are at the end).

## What is new

- **The `ae2power` fit** (48 steps, 18 universal cable) puts all the power
  in, none of it on show:
  - in the floor under all six bench machines (from access holes at x 29,
    which are filled again);
  - under the controller's first cell (29 0 19);
  - a block under the floor along z 23, then onto the power run at
    37 -1 24.
- **The `ae2` fit** (24 steps) places the machines from above, in priority
  order. It leaves what is not made yet. It needs no ME cable: every AE2
  block in the room passes the network on to the blocks it touches
  (checked in AE2's code: drive, pattern provider, assembler, crafting
  blocks, inscriber and charger are all grid nodes that carry channels).
  The inscribers and charger connect on every side but their front, and
  their front faces up when a turtle places them from above. The room is
  one network by touching:

  ```
  z\x  28        29   30   31   32         33          34
  18   silicon   C    C    C    drive(2)
  19   logic     C1   C1   C1   drive(1)
  20   calc      C    C    C    provider   assembler
  21   eng                      provider   assembler   ME Bridge (on its floor modem 34 0 21)
  22   charger   CPU  CPU  CPU  provider*  assembler*
  23   mill                     provider*  assembler*
  C1 = tonight's 3 controllers (power under 29 19); C = the rest of the 3 x 3; * = later
  ```

  `tools/foundry2plans.py check` now refuses any AE2-room cable that
  would show: each one must be under the floor, or in the floor under a
  machine. The energy acceptor is gone: the controller takes FE itself.
- **New lab steps** (`tools/certusfarm.py`):

  | step | what it does |
  |---|---|
  | `fluix N` | any number of fluix, one trip per 64 |
  | `chips L C E` | every processor in one trip |
  | `grind ITEM N` | lots of 64 |
  | `cells N` | cells into the drive |
  | `bridgeclick` | switches on the bridge's modem from its click hole |

  The charger is now waited on for each crystal, not a fixed 4 s, so none
  is skipped.
- **New lab verbs** (helper.lua):
  - `suckDown|n|seconds` keeps trying for that long.
  - `drainDown|seconds` takes a machine's output as it comes, until the
    machine holds nothing but its presses. The next batch then goes into an
    empty mill.
  - `hole|x|z` lets `walk` go down into a dug click hole.
- **crafter1 queues `make` orders.** Before this, a second make sent before
  the first started replaced it. Step 8 now sends all of them in one order.
- **Sortnado doesn't take the ME Bridge for the store until told**
  (`me Sortnado on=1`). Before this it switched to the bridge as soon as it
  saw one, on its 10-minute rescan. With the ME system empty and crafter1
  reading the controllers directly, that would have hidden the whole store.

## How the inscriber behaves (AE2 1.21.1, `InscriberBlockEntity`, read for this run)

- **Slots.** It has top, bottom, middle and output. Each of the three
  inputs holds up to 64 (setting "input capacity", default 64). The output
  holds 64, and a craft waits while the output is full.
- **Not separated (the default).** Every side, front included, reaches top,
  bottom and middle together, in that order. An item goes into the first
  slot that its `BaseFilter` allows: that slot plus the other two must still
  fit some inscriber recipe. In practice:
  - a press goes to the top;
  - then a printed circuit goes to the top and printed silicon to the
    bottom (the mill, which has no press);
  - silicon, gold, certus, diamond and redstone go to the middle.
- **Extraction.** Automation can take only from the output, so presses and
  part-used inputs stay put. This is why the mill must be empty before the
  next kind goes in. A leftover printed logic in its top slot would turn
  away printed calculation circuits. `chips` drains the mill after each kind.
- **Press mode and inscribe mode.** Processors are "press" mode: they use
  up top and bottom. Prints are "inscribe" mode: they keep the press.
- **Ingredients.** The calculation print takes `ae2:certus_quartz_crystal`
  exactly, not charged. Silicon is `#c:silicon` (only `ae2:silicon` in
  AE2's data), smelted from certus dust. There is no nether quartz route to
  silicon in AE2.
- **Speed and power.** It takes 116 ticks (5.8 s) a craft with no speed
  cards. It takes FE on every side but its front.

`test/certusfarm.py` models the inscriber exactly so (filter, slots, the
time per craft) and runs `grind`, `chips`, `fluix 70`, `cells` and
`bridgeclick` through the real helper.lua.

## The orders, in sequence

B is the bench drone: any idle helper, one at a time on the bench (they
share the y 2 corridor over x 28). The examples use builder2; `helper=`
changes it.

| # | who | order | what | about |
|---|---|---|---|---|
| 0p | builder6 | `tools/order.py fit builder6 ox=-4448 oy=71 oz=1518 plan=factory_f2_power shell=factory_asfit3` | the power row at x 43 again (the source for everything below) | 10-15 min |
| 0 | builder1 | `tools/order.py fit builder1 ox=-4448 oy=71 oz=1518 plan=factory_f2_ae2power shell=factory_asfit3` | the bench's and controller's power (18 universal cable from crafter1) | 20-30 min |
| 1 | B, Sortnado, crafter1 | `tools/order.py reboot builder2 reboot Sortnado reboot crafter1` | onto this code: lab verbs, the ME gate, the make queue. Check each is between jobs | 1 min |
| 2a | here | `python3 tools/survey.py pull && python3 tools/ae2run.py dead` | which slots are dead (last scan: `renew=0,1,2,4,5,7,8`) | |
| 2b | B | `tools/order.py lab builder2 clear=1 "ops=$(python3 tools/certusfarm.py renew 0,1,2,4,5,7,8)"` | 7 dead blocks dug, 21 crystals charged, all thrown in the basin, 7 flawed blocks put back | 15-20 min |
| 3 | B | `tools/order.py lab builder2 clear=1 "ops=$(python3 tools/certusfarm.py fluix 19)"` | 19 charged + 19 redstone + 19 nether quartz: 38 fluix | 10 min |
| 4 | B | `tools/order.py lab builder2 clear=1 "ops=$(python3 tools/certusfarm.py grind certus 31)"` | 31 certus dust | 8 min |
| 5 | crafter1 | `tools/order.py make crafter1 item=ae2:silicon n=18` | silicon in its furnaces | 3 min |
| 6 | B | `tools/order.py lab builder2 clear=1 "ops=$(python3 tools/certusfarm.py chips 11 2 5)"` | 18 printed silicon, 11/2/5 printed circuits, then 11 logic, 2 calculation, 5 engineering processors | 10 min |
| 7 | B | `tools/order.py lab builder2 clear=1 "ops=$(python3 tools/certusfarm.py grind fluix 8)"` | 8 fluix dust (for the cores) | 5 min |
| 8 | crafter1 | `tools/order.py make crafter1 item=ae2:controller n=3 make crafter1 item=ae2:drive n=1 make crafter1 item=ae2:item_storage_cell_1k n=1 make crafter1 item=ae2:1k_crafting_storage n=1 make crafter1 item=ae2:pattern_provider n=2 make crafter1 item=ae2:molecular_assembler n=2 make crafter1 item=advancedperipherals:me_bridge n=1` | the parts, in turn. It makes the in-between parts itself: quartz glass, fibre, cable, cores, components, 4 interfaces, 4 fluix blocks, the casing, smooth sky stone | 20-40 min |
| 9 | builder1 | `tools/order.py fit builder1 ox=-4448 oy=71 oz=1518 plan=factory_f2_ae2 shell=factory_asfit3` | the machines, from above; anything not made yet is left | 10-15 min |
| 10 | B | `tools/order.py lab builder2 clear=1 "ops=$(python3 tools/certusfarm.py cells 1)"` | the 1k cell into the drive at 32 1 19 | 5 min |
| 11 | B | `tools/order.py lab builder2 clear=1 "ops=$(python3 tools/certusfarm.py bridgeclick)"` | the bridge's floor modem on, from its click hole 34 0 22: Sortnado now sees `me_bridge_N` (and leaves it alone) | 5 min |

The whole run takes about 2 hours, most of it crafter1 (step 8) and the
fits.

- Steps 0 and 2a-2b can overlap with the other drones' work. Step 2b needs
  step 0 (the charger needs power).
- Steps 3, 4, 6 and 7 can be one order if wanted (join the four ops strings
  with `;`).
- Step 5 needs step 4's dust handed in, step 6 needs step 5, and step 8
  needs steps 3, 6 and 7.
- If a step's `labOut` shows `refused` or `left in it`, run that step again
  before going on.

After step 9, `close` (phase 5) puts the floor back over 34 0 22. It is
already in the close plan.

**Later (the `full` room):** `python3 tools/ae2run.py orders full` gives
the same sequence for 9 controllers, 2 drives, 4 providers and assemblers,
and 3 CPU blocks. The `ae2` fit is simply run again: what stands is passed
over. It says "left" for any kind it has none of, even ones standing
already; that is harmless.

## Bill of materials

| part | now | full |
|---|---|---|
| ME controller | 3 | 9 |
| ME drive | 1 | 2 |
| 1k item cell | 1 | 2 |
| 1k crafting storage (the CPU) | 1 | 3 |
| pattern provider | 2 | 4 |
| molecular assembler | 2 | 4 |
| ME Bridge | 1 | 1 |
| energy acceptor | 0: not needed, the controller takes FE | 0 |
| universal cable (ae2power) | 18 | 18 |
| ME cable | 0 laid: the room joins by touching. The parts use 2 fluix glass cable (1 craft) | |

| the bench's and the basin's work | now (+ renew 7) | full |
|---|---|---|
| charged certus | 19 for fluix + 21 for renewal | 35 |
| fluix crystals | 38 (19 basin throws; 8 ground to dust) | 70 |
| certus dust | 31 | 57 |
| silicon / printed silicon | 18 | 39 |
| logic / calculation / engineering processors | 11 / 2 / 5 | 20 / 6 / 13 |
| fluix dust | 8 | 12 |

| from the store | now (+ renew 7) | full |
|---|---|---|
| certus crystals | **85** (64 + 21 renewal) of the 92 | 124 |
| redstone | 48 | 100 |
| iron ingots | 46 | 76 |
| nether quartz | 23 | 41 |
| glass | 22 | 26 |
| sky stone blocks | 12 | 36 |
| gold ingots | 11 | 20 |
| diamonds | 5 | 13 |
| crafting tables / iron bars / copper / redstone block | 6 / 4 / 1 / 1 | 12 / 4 / 2 / 1 |
| glowstone | 0 (no terminal, no patterns tonight) | 0 |

**Tight:** tonight's set and the renewal take 85 of the 92 crystals. The
`full` room needs the renewed farm's next harvest. That comes about 3 hours
after step 2b: `python3 tools/certusfarm.py harvest`, with the clusters
picked. Anything the store already holds (fluix, dust or processors from
earlier bench trials) comes off these counts; crafter1 uses stock first.

## Sortnado and the ME Bridge

**After step 11:**

- Sortnado sees the bridge. Its status says
  `me = "seen, not the store: me_bridge_N"`.
- It stays on the Sophisticated controllers.
- crafter1 is untouched: it ignores `me_bridge` and reads the controllers.

**Making the ME system the store** needs the ME network to see the
store's barrels. It also needs crafter1 to still find everything, which
means the items stay in the barrels. The way to do both is:

1. **A storage bus on each Sophisticated controller.** One is at 10 5 15 and
   one at 17 5 15, both high on the storage room's walls. Use no cells for
   the store, so everything goes into the barrels through the buses.
2. `tools/order.py me Sortnado on=1`. Sortnado restarts on the bridge. The
   In barrel goes in with `importItem`. Out, `$get` and the bays use
   `exportItem`. The screens read `getItems`. `on=0` goes back.

**What blocks step 1: the cable to the storage room can't be hidden as the
room stands.**

- From the AE2 room it can run under the floor of the cross aisle (z 15),
  through the doors at x 27 and x 18.
- But the controllers are at y 5, against the walls, with the doorway
  (z 14-16, y 1-3) right under the east one.
- Every way up runs through a wall cell that shows from the launch bay, the
  doorway or the room.

**Options for Kyle:**

- **(a) AE2 facades.** Run the cable inside the wall and put stone-brick
  facades on its open faces. A facade is 4 cable anchors around a stone
  brick (AE2 `FacadeRecipe`). Anchors are a certus knife plus an iron
  ingot (`quartz_cutting`).
  - Drones can build it, but it is new: knife, anchor and facade recipes
    for crafter1, a fit plan for the wall run, and a turtle applying a
    facade, which is unverified.
  - About 25 cable, 4 storage buses and 20 facades: about 25 crystals
    more.
- **(b) Move each controller to floor level.** Put it in the floor under a
  barrel column foot (it must keep touching a barrel), with the bus under
  it in the floor. Everything is hidden. But the controllers' 15-block
  reach changes, and Sortnado's modem has to move with them. This touches
  the working store.
- **(c) No buses.** The ME system's own cells become the store over time
  (4k cells, about 21 crystals each; about 5 for the store's ~300 kinds).
  This needs the renewed farm and accelerators first. Sortnado would then
  need both stores at once, which is a code change not made here.

Until one of these is chosen, the ME network is ready but holds only what
is put into it. That is enough for AE2-side crafting tests and the bench's
later automation.

## Kyle's part

- **Nothing for the network itself.** Drones build, power, fill and click
  everything above.
- **The store link:** choose (a), (b) or (c) above.
- **Later, by hand:** an ME terminal where he wants one (glowstone needed
  for the panels), and writing crafting patterns. Patterns are player-only.

## Not verified

- **Turtle placement.** That a turtle places inscribers, the charger and a
  drive facing up from above. This follows AE2's `FacingWithSpinStrategy`
  (a player looking down more than 65° gives front = up) and CC's fake
  player looking straight down. A wrong facing only matters for the
  charger and inscribers' power side (power comes from below) and the
  drive's network side.
- **The ME Bridge's network side.** That it joins the network on every
  side. The bridge's peripheral was read for this, not its block entity.
- **`drainDown`.** That `peripheral.call("bottom", "list")` shows the
  inscriber's slots. CC's generic inventory peripheral on AE2's item
  handler should, but it has only been tested in simulation.
- **Renewal in the basin.** That the plain block, damaged and chipped steps
  chain one after another in one throw (`renew` is untested in game, as
  before).
- **Power.** That the z 24 power run (38-43 -1 24) is live once the row at
  x 43 is back: it rises at 43 -1/0 23 (surveyed) to 43 1 23, which is
  empty now (above).
- **Mekanism into AE2.** That Mekanism's universal cable feeds AE2's FE
  capability. AE2 offers it; Mekanism's side is unchecked, as in
  ae2-bootstrap.md.

## Re-clicking the alloy cell's and ore line's modems (from their click holes)

These are not part of the AE2 run, but they are probably off for the
reason above. They follow `bridgeclick`'s pattern.

- **The alloy cell's machines** stand on modems at 39 0 z. Their holes are
  at 40 0 z, so the drone faces west (2).
- **The ore line's machines** stand on modems at 42 0 z. Their holes are at
  41 0 z, so the drone faces east (0).
- Only where the hole is still open (`close` hasn't run yet). For example,
  for the alloy cell's three machines:

```
fetch|minecraft:coal=4;site|-4448|71|1518|factory_asfit3|factory_foundryfloor;hole|40|17;hole|40|19;hole|40|23;walk|40|0|17;face|2;expect|front|wired_modem;click;walk|40|0|19;face|2;expect|front|wired_modem;click;walk|40|0|23;face|2;expect|front|wired_modem;click;walk|40|2|23;leave;home
```
