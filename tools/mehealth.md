# ME network health sweep (RCON)

A grid node's NBT carries `e` (its share of the grid's energy buffer) only while
it sits in the powered main grid. No `e` = that block has dropped off the grid.
Each line below passes ("Test passed") only if every node in it is on the grid;
"no response" means one of them is not: bisect, then re-place the dead cable or
the (empty) provider (`setblock air`, then the same block again).

Run after any change to controllers, CPUs or wireless connectors.

```
execute if block -4417 71 1539 ae2:controller[state=online]

execute if data block -4410 72 1535 proxy.e if data block -4410 72 1536 proxy.e if data block -4410 72 1537 proxy.e if data block -4410 72 1538 proxy.e if data block -4410 72 1539 proxy.e if data block -4410 72 1540 proxy.e if data block -4410 72 1541 proxy.e if data block -4410 72 1542 proxy.e if data block -4410 72 1543 proxy.e if data block -4410 72 1544 proxy.e if data block -4410 72 1545 proxy.e if data block -4409 71 1535 up.gn.e if data block -4409 71 1536 up.gn.e if data block -4409 71 1542 up.gn.e if data block -4409 71 1543 up.gn.e if data block -4409 71 1544 up.gn.e if data block -4409 73 1539 proxy.e if data block -4409 73 1541 proxy.e

execute if data block -4405 72 1529 proxy.e if data block -4405 72 1530 proxy.e if data block -4405 72 1531 proxy.e if data block -4406 71 1530 proxy.e if data block -4406 71 1531 proxy.e if data block -4420 71 1536 proxy.e if data block -4420 71 1537 proxy.e if data block -4420 71 1538 proxy.e if data block -4420 71 1539 proxy.e if data block -4420 71 1541 proxy.e if data block -4406 71 1545 proxy.e if data block -4405 72 1545 proxy.e if data block -4416 72 1526 proxy.e if data block -4415 72 1525 proxy.e if data block -4415 71 1525 up.gn.e if data block -4419 72 1535 proxy.e if data block -4418 72 1535 proxy.e if data block -4417 72 1535 proxy.e if data block -4416 72 1535 proxy.e if data block -4415 69 1540 proxy.e if data block -4418 69 1540 proxy.e if data block -4416 69 1540 proxy.e

execute if data block -4406 73 1535 down.gn.e if data block -4406 73 1536 down.gn.e if data block -4406 73 1537 down.gn.e if data block -4406 73 1538 down.gn.e if data block -4406 73 1539 down.gn.e if data block -4406 73 1540 down.gn.e if data block -4406 73 1541 down.gn.e if data block -4419 74 1535 proxy.e if data block -4416 74 1535 proxy.e if data block -4417 75 1535 proxy.e if data block -4419 69 1538 proxy.e if data block -4415 69 1538 proxy.e if data block -4431 76 1532 south.gn.e if data block -4438 76 1532 south.gn.e if data block -4432 76 1532 proxy.e if data block -4415 71 1536 cable.gn.e if data block -4415 71 1538 cable.gn.e if data block -4416 72 1525 proxy.e if data block -4419 70 1523 proxy.e if data block -4417 72 1543 proxy.e if data block -4418 74 1544 proxy.e if data block -4416 74 1544 proxy.e
```

Line 2: alloy row (providers, feeds, the two providers on top). Line 3: ore
line, press, fuel, crystal lab, drives. Line 4: generator water buses, CPUs,
storeroom buses and the overflow interface, terminals, lab, garden, matrix.
The ME Bridge (34 0 15) has no node NBT: if crafter1's `me` shows cpus 0,
re-place the cable under it (34 -1 15).

## Lessons (19 Nov, 02:02)
- A wireless connector placed against a controller block put the controllers into `conflicted`: everything went offline, and afterwards adjacent cables and blocks in four places were no longer joined.
- Each vault column (drive, cell, CPU, connector) passes 8 channels. The wireless links end there: do not add devices to a linked subnet without counting.
- A drive's cells: `data get block <drive> inv` shows the live contents. If ME reports stock that the cells do not show, the stock is not being saved.
