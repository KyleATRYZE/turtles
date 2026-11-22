# The rebuilt factory: what the code still assumes, and what is there now

Surveyed over RCON on the night of 21 to 22 Nov 2026, after the old building was cleared and
rebuilt from the `shop-full` blueprint. World coordinates throughout. Nothing in this file
changes how any program behaves: it is the record to work from.

## Short version

- The old building is gone. Every coordinate in the programs that points inside it is stale.
- The fleet (8 turtles) is still parked in the **old rack cells** on the back lane. Those
  cells and the lane are still open air, so the old homes still work as places to sit.
- The base computer that relays orders and uploads status is gone. The `status` branch
  stopped at 21:57 UTC on 21 Nov. Until a controller is set up again, an order in
  `commands.json` reaches nobody.
- The new rack is one floor up, behind a gate. Getting to it is a new route, not a new
  number in `M.LANE`. It needs code, a test world, and one berth tried in game.

## Old lane and rack (what `swarm.lua` `M.LANE` describes)

| Thing | Where | State now |
|---|---|---|
| Lane | x -4448..-4404, y 72..74, z 1519..1520 | open, except crafter1 and one disk drive |
| Old rack homes | x -4429..-4422, rows y 72/74/76/78, z 1521 | open air; 7 turtles sit in them |
| crafter1 (id 8) | -4442 73 1519 | still there, switched on |
| Disk drive (holds a disk) | -4441 72 1519 | still there |
| Shelf modems, rack cable, rack board computers and monitors | along z 1519..1521 | **removed** |
| Chests beside crafter1 and the buried chest stack | x -4462..-4443 | 18 empty ones removed; 2 with items left |

Parked turtles (label, id, position): builder1 19 at -4428 72 1521, foundry1 23 at
-4426 72 1521, builder2 15 at -4423 72 1521, survey1 39 at -4422 72 1521, builder6 16 at
-4429 74 1521, rescue1 10 at -4428 74 1521, builder5 5 at -4427 74 1521, crafter1 8 at
-4442 73 1519. All were switched on and fuelled when read.

The floor under the lane is now a solid slab at y 67..70 and the old structure around the
rack is gone, so the turtles hang in open air.

## New hangar (`swarm.lua` `M.HANGAR`, not used by any program yet)

| Thing | Where |
|---|---|
| Gate opening in the back wall | x -4430..-4423, y 78..81, z 1522 (sill of grates at y 77) |
| Door leaf, parked open | x -4430..-4423, y 82..84, z 1522, chassis at y 85, rope pulley at -4427 88 1522 |
| Outside the gate | open air from z 1518 to 1521 at y 78..81 |
| Flight aisle | z 1524, clear from y 78 to 89 for x -4440..-4413 |
| Berths | z 1527, facing north, 24 of them |
| Berth columns | x -4439, -4437, -4435, -4433 (west bank) and -4420, -4418, -4416, -4414 (east bank) |
| Berth rows | y 78, 83, 88 |
| Fuel barrel | one above every berth (y + 1) |
| Cargo barrel | one below every berth (y - 1) |
| Catwalks | grates at y 82 and 87, z 1526 |

In the aisle, z 1525 and 1526 are blocked at y 80 and 85 (lights) and z 1526 at y 82 and 87
(catwalks); z 1523 is blocked at y 88 and 89 (the pulley). z 1524 is clear the whole way, and
at the three berth rows z 1525 and 1526 are clear too, so the last move into a berth is three
steps south from the aisle.

The door does not work yet. It is a Create rope pulley on a sequenced gearshift whose motor
has no power, and the leaf is not glued. It is parked open, so the gate is passable now; do
not rely on that once the door is commissioned.

The barrels are empty and nothing feeds or empties them: the item pipes behind the rack are
not built.

## Why this is not a constants change

`helper.lua` `LN.home()` computes a home as `rackX + i % perRow`, on the lane's own z plus
one, and `LN.toHome()` reaches it with a single step south off the front track. The new
berths are not contiguous in x, are five blocks apart in y, and are reached through a gate
and along an aisle. So it needs:

1. a home function that takes the columns and rows from a table (`M.HANGAR`);
2. a route: in over the back lane at gate height, through the gate, along the aisle, to the
   row, three steps south; and the same back out;
3. a rule for two drones meeting in the gate or the aisle (the old lane had two tracks);
4. the fuel and cargo hand-over from the berth barrels instead of the shelf modems;
5. a new world in `test/lanetest.py` for all of the above.

`rack.lua` (the ops board) has the same contiguous-x assumption in `R.homeAt`, and there
are 27 named homes plus the builder's against 24 berths.

## The hangar route (on this branch, opt-in)

`helper.lua` now has `HG`: `HG.home()`, `HG.toHome()`, `HG.exit()`, `HG.inside()`. Nothing
calls the route by itself. Two lab verbs do, for one helper at a time:

- `dock|berth` : in through the gate to this helper's berth.
- `dock|leave` : out of the gate and up.

The route in: high over the back of the building, down outside the gate at x -4429, z 1520
to y 79, south through the gate to the aisle (z 1524), along to the berth's column, to its
row, three steps south. Out: north to the aisle, to y 81, along to x -4424, north out of the
gate to z 1520. In and out use different columns and heights of the gate.

Three hooks apply wherever a helper is, hangar mode or not, because they go by position:

- `riseTo` leaves by the gate first when the helper is inside the hangar;
- a helper that starts up inside the hangar counts as in its place, not lost in the factory;
- `intoBuilding` leaves by the gate first.

Berths go by the same name list as the old homes (16 names fill the two lower rows), and
unnamed helpers take the top row by id.

`test/hangartest.py` flies all 24 berths in and out in a model of the hangar with its
lights, catwalks and pulley in the way, plus a taken berth and a shut gate. The two columns
outside the gate (x -4429 and x -4424 at z 1520) were checked clear in the world up to y 230.

Still not done: a rule for two helpers in the aisle at once, fuel and cargo at the berth
barrels, `rack.lua`, and making the hangar the automatic home.

## Other stale coordinates in the programs

| File | What | Why it is stale |
|---|---|---|
| `controller.lua` 690, `screens.lua` 23 and 39 | `site` / `ORIGIN` -4448 71 1518, the map of the building | the building and its floors are different |
| `controller.lua` 691, `screens.lua` 40 | `hut` -4464..-4458, 1518..1532 | cleared |
| `factory.lua` 3334, 3420, `foundry.lua` 32, `helper.lua` 1275 | site with shell `factory_asfit3` and its plans | those blueprints describe the old building |
| `factory.lua` 3386 | `FARM` at -4453 76 1538 | inside the new works hall |
| `foundry.lua` 36 | `BENCH` at -4453 74 1533 | the foundry is now at x -4397..-4385, z 1547 and 1552 |
| `sortnado.lua` | the barrel room and its ME interface | both removed; ME is a new, empty network |

## New computer hardware (placed, not booted, no programs)

| What | Where |
|---|---|
| Advanced computers | -4462 73 1530, -4424 72 1537, -4424 72 1545, -4407 72 1532, -4384 72 1551, -4414 79 1532, -4425 100 1540, -4421 100 1540 |
| Screens | 5x1 at -4461..-4457 76 1531; 5x1 at -4431..-4427 81 1552; 5x1 at -4426..-4422 73 1545; 9x4 at -4425..-4417 100..103 1538; 3x1 at -4384 73 1548..1550 |
| Full wired modems (need a right-click) | -4417 79 1533, -4415 79 1533, -4413 79 1530 |
| Redstone relay | -4414 100 1539 |
| Player detector | -4425 73 1546 |
| ME interfaces (not cabled to ME) | -4454 73 1530, -4422 72 1545, -4408 72 1532 |

## Order of work that would make it live

1. A controller computer again (install, role controller), so orders and status work.
2. The hangar route and home table in `helper.lua`, with its test world. (Done on this branch.)
3. One helper sent to one berth in game, watched, and brought back out.
4. Fuel from the berth barrel, tried with a full and an empty barrel.
5. Only then `rebase` the rest of the fleet.
