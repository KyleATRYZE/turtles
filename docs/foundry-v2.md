# Foundry hall v2 (approved 18 Nov, with a lava wall added)

The page is `docs/foundry-v2.html` (before/after, top-down, zone labels).
It is written by `python3 tools/foundry2.py`, and `python3 tools/foundry2.py check`
checks that the walkways and both doors stay clear. **The drones build it**
from the fit plans below (`tools/foundry2plans.py`); Kyle's own part is the
short list at the end.

Building coordinates: corner -4448 71 1518, x east, z south. The hall is
x 28-43, z 4-29.

## Why

The hall grew piece by piece:

- DropIt's plinth machines at x 41;
- Sticky's piped line at x 35-37, with a chest in the walkway;
- planned pools and gas plants in the middle;
- the quartz line and the bench's leftovers in the south-west.

The concept turns it into one floor with:

- every machine in a row against a wall, or on a bed;
- all services (CC cable, Mekanism cable, tubes) under the floor;
- walkways that nothing stands in.

## Zones

| zone | where | what |
|---|---|---|
| Racks 3 and 2 | lane wall, x 28-31 and x 35-42 | loading bays (stage 6, docs/racks23-build.html); the hatch at x 32 stays open |
| Walkways | spine x 35-36 (z 5-29), north walkway z 5, cross aisle z 14-16 from the west door, aisle z 24-26 to the east door, service walkways x 39-41 (z 6-13) and x 41 (z 17-23) | clear; the works computer is flush in the floor at 35 0 15, where they cross |
| Ore line (toward 5x) | east wall x 42, z 6-13, facing west; tanks behind at x 43 | dissolution, washer, crystallizer, injection, purification, crusher, enrichment, smelter, each pushing into the next. Ore goes in at the north end over the cable; ingots come out at the south end |
| Gas plant | x 38 z 6-13 facing east; tanks at x 37 | two separators (brine, water), oxidizer, three chemical infusers (SO3, sulfuric acid, HCl), rotary condensentrator, pump on a 2 x 2 floor pool. Gases cross under the service walkway |
| Power | east wall x 42-43, z 17-23 | cubes, four heat generators (both of today's), a gas-burning generator; room for an induction matrix behind |
| Alloy cell | x 39, z 17-23, on a bed | 2 metallurgic infusers, 3 energized smelters, crusher, enrichment chamber: the works computer's make, smelt and enrich jobs |
| **Certus farm** | x 28-34, z 5-13 | the AE2 work's farm (`tools/certusfarm.py`): two stone pillars at x 30 (z 7 and z 10, y 1-7), budding certus against both sides in three tiers (9 of 12 slots), corridors x 28 and x 32, the basin at 30 0 13. The harvester docks in rack 3 and comes in by the hatch (32, z 3-4). Crystals go into a barrel on the cable at 34 1 13 |
| **AE2 room** | x 28-34, z 17-23 | ME controller 3 × 3 (x 29-31 z 18-20), drives (33 18-19), crafting CPU (x 29-31 z 22-23), assemblers with pattern providers (33 20-23), inscribers ×4 on the west wall (28 18-21), charger (28 22), energy acceptor (34 17), ME bridge and terminal (34 21) |
| Quartz line | x 29-33, z 24-27 | the built machines, squared up into one bay |
| Workshop bench | x 38-42, z 27 | machine trials, by the east door |
| **Lava wall** | south wall, cauldrons x 28-43 at z 29; harvest walkway z 28 | 16 dripstone units: cauldron (y 1), pointed dripstone (y 2), a block (y 3), lava (y 4) held between the wall and a row of blocks over the walkway (y 4). A drone with empty buckets walks z 28 and fills them (turtle.place on the cauldron: proven). Fuel for the drones and the heat generators |
| Power rows | universal cable x 43 (z 6-23) behind the ore line and the power block; x 38 (z 17-23) behind the alloy cell; joined a block under the east door's walkway (z 24) | every machine on one Mekanism network |

## For the AE2 bootstrap work (the certus farm and the AE2 chain)

**Put the certus farm and the AE2 room where the table above says.** That is
the foundry hall's north-west and south-west blocks, not the smelting hall's
corner (x 5-8, z 18-28) that `docs/factory-retrofit.md` had. The AE2 corner
moves here, next to:

- the certus farm;
- the Mekanism power (energy acceptor at 34 1 17);
- the alloy cell (silicon, circuits).

Things to keep:

- **The harvester's way in.** It goes from rack 3 by the hatch (32, z 3)
  through the north walkway (z 4-5) into the farm's harvest rows. It needs
  nothing else.
- **The walkways.** Keep the spine (x 35-36) and the cross aisle
  (z 14-16) clear.
- **Cable.** It runs a block under the floor and joins the foundry link
  (docs/foundry-build.html). Any CC modem on an AE2 block must touch only
  that block (the lesson from the bays).
- **Exact cells are open.** If the AE2 chain needs more room, the AE2 room
  can take the floor up to x 34, z 17-23 inside its zone. Say so and I will
  move the other zones' edges, not the walkways.

## The build: fit plans for the drones

`python3 tools/foundry2plans.py write` writes `blueprints/factory_f2_<job>.txt`
and checks them: nothing is placed twice, and nothing goes in a walkway.
`test/f2fit.py` runs the cable and lava jobs with the real helper.lua in
the real building.

The helpers now go under the floor themselves. The walker digs a floor
block, stands in the hole, puts the cable in a block down (replacing the
earth), climbs out and puts the floor block back. helper.lua lets it into
a floor cell its plan has dug, and nowhere else at y 0.

Order for any job (printed by `python3 tools/foundry2plans.py order <job> <helper> [xmin xmax]`, never sent by the tool):
`tools/order.py fit <helper> ox=-4448 oy=71 oz=1518 plan=factory_f2_<job> shell=factory_asfit3 [xmin= xmax=]`.
Two helpers share a job with strips: each does its own x range and takes
the other's as done.

| phase | job | helper(s) | what | needs from Crafty |
|---|---|---|---|---|
| 1 | `link` | HopTo `xmax=25`, Comparable `xmin=26 xmax=34`, Dusty `xmin=35` | the CC cable from rack 1's link (18 1 3 down), under the front track to the hatch, under the north walkway, down the spine (x 35, to z 22); branches: the certus barrel's modem 34 0 13, the works computer (35 0 15, on its modem), the ME bridge's modem 34 0 21, the alloy cell's floor modems 39 0 17-23, and toward the ore line (39-41 0 16) | 54 cable, 11 wired modems, 1 computer |
| 1 | `lava` | OnRepeat `xmax=35`, ButtonUp `xmin=36` | the lava wall, 16 units | 32 polished deepslate, 16 pointed dripstone, 16 cauldrons, 16 lava buckets |
| 1 | `certus` | Pushy | the farm's two pillars (y 1-7) and its barrel; a click hole at 33 0 13 | 14 stone bricks, 1 barrel |
| 1 | `clear` | Sticky `xmax=35`, Dispensable `xmin=36` | the piped line's chest, sorter, transporters and cable, the plans' leftovers, the bench's leftovers (a chest with things in it is left and said: empty it into the store first) | none |
| 1 | `power` | Observant | the power row (x 43); the piped line's heat generator to 42 1 19, two more, a gas-burning generator and a second cube (left if not to be had) | 18 universal cable, 2 heat generators, 1 gas-burning generator, 1 cube |
| 2 | `alloy` | DropIt (the foundry stops for the few minutes this takes) | the plinth's infuser, smelter and chamber into the alloy cell (39 1 17, 19, 23, facing east), its power row (x 38) and link to the east wall; the old plinth cable up; the cube and heat generator turned to face the row; click holes at 40 0 17-23 | 7 universal cable (10 come back from the old cable), and the cell's other machines when made: 1 infuser, 2 smelters, 1 crusher |
| 3 | `ore` | Sticky, after `alloy` | the cable under the ore line with a modem under each machine; the piped line's chamber and smelter to 42 1 12 and 42 1 13 (facing west); the rest of the line as it is made; click holes at 41 0 6-13 | 11 cable, 8 wired modems; later the crusher, purification, injection, crystallizer, washer, dissolution chamber |
| 4 | `ae2` | HopTo, or the AE2 work's helper | the AE2 room (controller 3 × 3, drives, crafting CPU, pattern providers and assemblers, energy acceptor, ME bridge) and its power across the spine (one universal cable flush in the floor at z 17); a click hole at 34 0 22. Fit when the parts exist; what is missing is left for a later run | the AE2 work's parts |
| 5 | `close` | any helper, after Kyle's clicks | the floor blocks back over the click holes | 15 deepslate bricks, 2 polished deepslate |

**In parallel.** In phase 1, nine helpers work at once without meeting
(LeverAlone is lost and is not used; DropIt keeps the old foundry
running):
- HopTo, Comparable and Dusty on the cable (the west lane, the east lane
  with the hatch and the north walkway, the spine with its branches);
- OnRepeat and ButtonUp on the south wall;
- Pushy at the farm (x 30);
- Sticky and Dispensable clearing the old line;
- Observant on the east wall's power.

The old foundry keeps running through phase 1: the new power row joins
the old plinth cable, so the plinth machines keep their power. Phase 2
stops it for the move. Phase 3 rebuilds the line with the works computer
already on the cable.

**The move, step by step (keeping the old foundry running as long as it can):**
1. Phase 1 as above. Through it, DropIt's foundry.lua keeps working the
   plinth machines where they stand (the new power row joins their cable).
2. After `link` and the works computer's install: `probe Crafty` (one item
   into a machine by name and back; docs/factory-retrofit.md §5b). If it
   says no, stop and use the fallback there.
3. `foundry DropIt on=0`, then phase 2 (`alloy`, DropIt itself). The plinth
   machines go into the alloy cell; Kyle clicks their three floor modems.
4. Start the works computer: it says `foundry_ready` and the factory's
   jobs go to it from then on (ore through the chamber; make, smelt, enrich
   in the alloy cell). DropIt is an ordinary helper again.
5. Phase 3 (`ore`): the piped line's chamber and smelter onto the ore line;
   Kyle clicks their two modems. The works computer picks them up on its
   next look (every 5 minutes, or a reboot): the ore line's machines face
   west, the alloy cell's east, and it tells them apart that way
   (`getDirection`).
6. `close`.

(docs/foundry-build.html and the "foundry link" of docs/factory-retrofit.md
were for the plinth as it stood; this plan replaces them.)

## Kyle's part (the only things that need a player)

1. **The budding certus blocks.** 9, flawed. Place them against the pillars
   at the slots `python3 tools/certusfarm.py kyle` lists (world -4419/-4417,
   y 72/75/78, z 1525/1528; building 29 and 31, y 1/4/7, z 7 and 10). A
   budding block broken without Silk Touch loses a level, so no drone
   ever touches them. (The pillars and the basin are the drones'; the
   certus tool's own "kyle" list still has them, and the AE2 work may drop
   them from it.)
2. **Right-clicks on the floor modems,** each once, through the hole left
   beside it, once the machine stands on it:
   - the alloy cell: 39 0 17, 19, 23 now (world -4409 71 1535, 1537,
     1541), and 18, 20, 21, 22 as those machines come;
   - the ore line: 42 0 12 and 13 now (world -4406 71 1530 and 1531),
     and the rest as they come;
   - the certus barrel's: 34 0 13 (world -4414 71 1531);
   - the ME bridge's: 34 0 21 (world -4414 71 1539), when the bridge is in.

   Then `close` puts the floor back.
3. **The works computer** (35 0 15, world -4413 71 1533): open it, type
   `label set Works`, then
   `wget run https://raw.githubusercontent.com/KyleATRYZE/turtles/main/install.lua`.
4. **Nothing else.** The drones build, move and cable everything; lava
   and water are placed by them too (the farm's basin is a lab step:
   `tools/certusfarm.py first`).

## What moves (after approval)

The table on the page ("What moves where"). In short:

- **The plinth machines** go to the alloy cell.
- **The piped line:** its chamber and smelter go to the ore line. The
  chest, sorter, transporters and cable come up, and its heat generator
  goes to the power block.
- **Stays:** the cube and today's heat generator. They are the start of the
  power block.
- **Not built:** the planned pool, gas plants and power corner. The ore
  line, the gas plant and the certus farm take their place.
- **The quartz line** is squared up, and the bench leftovers are emptied
  into the store.

Drones can break and place Mekanism machines (they keep their contents and
settings); Kyle can too.

## Open for Kyle

1. **The concept as a whole.** The two-wall arrangement (machines on the
   east wall, farms and AE2 on the west).
2. **The plinth's deepslate bricks.** Keep them as beds, or floor them
   over to match.
3. **The ore line's direction.** North to south as drawn, so ingots come
   out by the power block.
