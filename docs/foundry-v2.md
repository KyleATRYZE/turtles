# Foundry hall v2: the concept (awaiting Kyle's approval)

The page is `docs/foundry-v2.html` (before/after, top-down, zone labels).
It is written by `python3 tools/foundry2.py`, and `python3 tools/foundry2.py check`
checks that the walkways and both doors stay clear. Nothing is built, cabled or
moved, and no schematic is drawn, until Kyle approves.

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
| Walkways | spine x 35-36 (z 5-29), north walkway z 5, cross aisle z 14-16 from the west door, aisle z 24-26 to the east door, service walkways x 39-41 (z 6-13) and x 41 (z 17-23) | clear; the works computer is flush in the floor at 36 0 15, where they cross |
| Ore line (toward 5x) | east wall x 42, z 6-13, facing west; tanks behind at x 43 | dissolution, washer, crystallizer, injection, purification, crusher, enrichment, smelter, each pushing into the next. Ore goes in at the north end over the cable; ingots come out at the south end |
| Gas plant | x 38 z 6-13 facing east; tanks at x 37 | two separators (brine, water), oxidizer, three chemical infusers (SO3, sulfuric acid, HCl), rotary condensentrator, pump on a 2 x 2 floor pool. Gases cross under the service walkway |
| Power | east wall x 42-43, z 17-23 | cubes, four heat generators (both of today's), a gas-burning generator; room for an induction matrix behind |
| Alloy cell | x 39, z 17-23, on a bed | 2 metallurgic infusers, 3 energized smelters, crusher, enrichment chamber: the works computer's make, smelt and enrich jobs |
| **Certus farm** | x 28-34, z 6-13 | 9 flawed budding certus at x 29/31/33 × z 7/9/11, growth accelerators at x 30/32 beside them, harvest rows between them and all round. The harvester docks in rack 3 and comes in by the hatch (32, z 3-4). Crystals and dust go into a barrel on the cable at 34 1 13 |
| **AE2 room** | x 28-34, z 17-23 | ME controller 3 × 3 (x 29-31 z 18-20), drives (33 18-19), crafting CPU (x 29-31 z 22-23), assemblers with pattern providers (33 20-23), inscribers ×4 on the west wall (28 18-21), charger (28 22), energy acceptor (34 17), ME bridge and terminal (34 21) |
| Quartz line | x 29-33, z 25-28 | the built machines, squared up into one bay |
| Workshop bench | x 38-43, z 28 | machine trials, by the east door |

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
