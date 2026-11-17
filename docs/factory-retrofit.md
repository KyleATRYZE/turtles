# Factory retrofit: moving the base into the factory

The staged plan for getting Crafty, Counter, the launch pads and the old
base's storage out of the hut and into the factory, and for laying the
building out properly for the long term.

- **Written:** 17 Nov (evening), revised the same night with Kyle's
  answers. The pads now go **inside**, in the launch bay, the empty room
  inside the big door.
- **Coordinates:** the building's own frame unless marked "world". The
  corner is -4448 71 1518, x runs east, z runs south, y 1 is the ground
  floor and y 0 the floor. Outside the building the same frame carries on:
  the west yard has x < 0. To convert:
  **world = (-4448 + x, 71 + y, 1518 + z)**.
- **Tool:** every cell below comes from `tools/retrofit.py`. It checks them
  against:
  - the as-fitted shell;
  - the storeroom, foundry-floor, screens and touch-up fit plans;
  - the controller move;
  - `tools/mekline.py` up to stage 5 and `tools/quartzline.py`;
  - the stage-0 machines, the dripstone lava row, the old hut and the yard
    bench.

  It also checks that the pad columns are open to the sky, the big-door
  corridor and doorways stay clear, and the helpers' hover row is above the
  roof. `python3 tools/retrofit.py check` prints
  `ok: 249 retrofit cells, none on anything built or planned`, and the maps
  here are its output.
- **The tool only prints.** It sends no orders and writes no files. Its fit
  plans are printed, to be saved into `blueprints/` when their stage is due.

---

## 0. Where things stand

| what | where (building) | world | source |
|---|---|---|---|
| Crafty, on its modem | -13 1 3 (modem -13 0 3) | -4461 72 1521 | Crafty's `base` in status |
| Old launch pad (drive under it) | -14 1 3 (drive -14 0 3) | -4462 72 1521 | Crafty's `base` |
| Drop-off chest (on a furnace) | -12 1 3 | -4460 72 1521 | Crafty's `base`, hut scan |
| Counter, in counter mode, serving | -13 2 5, its drive sunk one block beside it | -4461 73 1523 | Kyle |
| Old base storage | 28 chests and 2 furnaces in and under the hut (x -15..-11, y -4..1, z 1..6) | | Crafty's `network` |
| Its contents | 1,090 of 1,269 slots: 187 kinds, 56,647 items | | Crafty's `storage` and `inv` |
| The hut | x -20..-10, z 0..14, roof at y 3, roof hole over x -14..-12 z 3 | | BlockParty's `hut_lava` scan |
| Kyle's lava cauldrons (rounds stay) | -19 -1 3..9, reached down the old pad's roof hole | -4467 70 1521..1527 | lava rounds |
| Dripstone lava row (11 units) | x -7..-4, y 5..10, z 19..31 | -4454, 1538..1548 | `tools/lavafarm.py` |
| Store: west controller | 10 5 15 (its modem 10 5 16); desk modems 10..15 1 29; In and Out barrels on the desk | | `tools/ctlmove.py`, storeroom plan |
| Store: east controller | **TBD**: a helper is scanning for it | | |
| Store size | 803 slots, 327 used. The plan has 71 limited barrels I (bulk), 65 limited barrels IV (260 medium slots) and 18 chests (486 small slots). | | Sortnado's report, storeroom plan |
| Inventory Managers | three, holding Kyle's memory card and two other players' (one on the desk, one on the yard bench) | | Kyle |
| Smelting hall | 12 furnaces at x 2 (odd z 5..27), modems at x 1, cable at x 1 (even z 4..28) | | as-fitted shell |
| Launch bay | x 19-26, z 5..29, y 1-7, empty but for the drone rack (z 3-4) and the bay panel (19, 2-3, 26-27). Upper floor (slab y 8) above, roof above that (y 14-18). | | as-fitted shell |
| Mekanism line | stage 2 built, stage 3 being built, x 35-37 z 9-21 | | `tools/mekline.py` |
| Chunks round the factory | force-loaded | | Kyle |

**What ties the drones to Crafty's spot.** All of this decides what works
inside a building. Everything is measured from Crafty (`base.f`) or from its
pad (`base.exit2`):

- **Helpers** come straight down onto the pad and go straight back up.
  - They wait in a row 12 above Crafty, 4 blocks north of the pad, at pad
    x + 3, + 5, + 7 and + 9 (`helper.lua hover()`).
  - Leaving the pad, they climb only to that height (`upFromPad()`), then
    fly sideways (`goHover()`).
- **Loaders** park on 12 spots at Crafty x + 4..10 and z - 1, - 3, - 5,
  landing on whatever is there (`loader.lua parkSpot()`). Short hops fly at
  Crafty's height + 14 (`HOP_UP`).
- **Miners** go up the in-shaft beyond the drop chest and down the out-shaft
  beyond the pad. Their plot grid is laid out around Crafty
  (`factory.lua plotOrigin()`).
- **Each drone keeps its own copy** of the base in `.base`, written once.
- **BlockParty's** base-room map (`builder.lua`, `ROOM_REACH` 12 round
  Crafty, `DOOR_OFFSET` to the hut's door) assumes the hut.

---

## 1. The layout

```
The site, top down, x -20..56 (building's own frame; 1 char = 1 block)
   x  -20       -10       0         10        20        30        40        50     
      09876543210987654321012345678901234567890123456789012345678901234567890123456
z  -1                                                                              
z   0 HHHHHHHHHHH         #############################################            
z   1 HHHHHHHHHHH         ---------------------------------------------            
z   2 HHHHHHHHHHH         ---------------------------------------------            
z   3 HHHHHHHHHHH         #::::::::#::::::::#::::::::#::::::::::::::::#            
z   4 HHHHHHHHHHH=        #ssssssss#SSSSSSSS#yy    yy#fffffffffffllfff#            
z   5 HHHHHHHHHHH=        #ssssssss#SSSSSSSS#pp    yy#fGGGGGfffffllfff# EEEE       
z   6 HHHHHHHHHHH=========#ssssssss#SSSSSSSS#pP    yy#fGGGGGfffffll00f# EEEE       
z   7 HHHHHHHHHHH        =#ssssssss#SSSSSSSS#pp    yy#fGGGGGfffffll00f# EEEE       
z   8 HHHHHHHHHHH        =#ssssssss#SSSSSSSS#pp    yy#fffffffffffll00f# EEEE       
z   9 HHHHHHHHHHH         #ssssssss#SSSSSSSS#pp    yy#fffffffMMMMll00f#            
z  10 HHHHHHHHHHH         #ssssssss#SSSSSSSS#pp    yy#fffffffMMMMll00f#            
z  11 HHHHHHHHHHH         #ssssssss#SSSSSSSS#pP    yy#fffffffMMMMll00f#            
z  12 HHHHHHHHHHH         #ssssssss#SSSSSSSS#pp    yy#fggggggMMMMll00f#            
z  13 HHHHHHHHHHH         #ssssssss#SSSSSSSS#pp    yy#fggggggMMMMll00f#            
z  14 HHHHHHHHHHH         #ssssssss SSSSSSSS yy    yy fggggggMMMMll00f#            
z  15                     #ssssssss SSSSSSSS yy    yy fggggggMMMMll00f#            
z  16                     #ssssssss SSSSSSSS yy    yy fggggggMMMMll00f#            
z  17                     #ssssssss#SSSSSSSS#pp    yy#fggggggMMMMll00f#            
z  18                     #ssssAAAA#SSSSSSSS#pP    yy#fggggggMMMMll00f#            
z  19          ~~~~~~~~   #ssssAAAA#SSSSSSSS#pp    yy#fggggggMMMMll00f#            
z  20          ~~~~~~~~   #ssssAAAA#SSSSSSSS#pp    yy#fggggggMMMMll00f#TTTTTTTTTTT 
z  21          ~~~~~~~~   #ssssAAAA#SSSSSSSS#yy    yy#QQQQQQQQQMMll00f#TTTTTTTTTTT 
z  22          ~~~~~~~~   #ssssAAAA#SSSSSSSS#yy    yy#QQQQQQQQQffll00f#TTTTTTTTTTT 
z  23          ~~~~~~~~   #ssssAAAA#SSSSSSSS#yy    yy#QQQQQQQQQwwll00f#TTTTTTTTTTT 
z  24          ~~~~~~~~   #ssssAAAA#SSSSSSSS#yy    yy#QQQQQQQQQwwll00f#TTTTTTTTTTT 
z  25          ~~~~~~~~   #ssssAAAA#SSSSSSSS#yy    yy#QQQQQQQQQwwll00f#TTTTTTTTTTT 
z  26          ~~~~~~~~   #ssssAAAA#SSSSSSSS#yy    yy#QQQQQQQQQwwll00f#TTTTTTTTTTT 
z  27          ~~~~~~~~   #ssssAAAA#SSSSSSSS#yy    yy#QQQQQQQQQwwll00f#TTTTTTTTTTT 
z  28          ~~~~~~~~   #ssssAAAA#SSSSSSSS#yy    yy#QQQQQQQQQffllfff#TTTTTTTTTTT 
z  29          ~~~~~~~~   #ssssssss#SSSSSSSS#yy    yy#fffffffffffllfff#TTTTTTTTTTT 
z  30          ~~~~~~~~   #############################################TTTTTTTTTTT 
z  31          ~~~~~~~~                                                            
z  32                                                                              
P pads (open to the sky)  p pad strip: dispensers, cables, Crafty's chest and shafts
s smelting hall (12 furnaces, on the network from stage 2)  A AE2 corner (later)
S storage room (+ a 4th barrel row, stage 3)  y launch bay: corridor x 21-24 kept clear
H old hut (Kyle's; its storage drained and retired)  = bridge for the drain (stage 2, temporary)
~ dripstone lava rows (fuel)  - drone lane  : lane screen / drone rack  # walls
f foundry floor  G power corner  M Mekanism line + walkway  g pool and gas plants
Q quartz line  w workshop bench  l operator lane  0 stage-0 plinth (factories, stage 6+)
E evaporation tower (outside, stage 4)  T control tower (screens, CommandBlock)
```

| zone | box | what it is for |
|---|---|---|
| **Launch bay** | x 19-26 | **The pads** on the west side: pad column x 20, cable down the wall at x 19, z 5..13 and 17..20. The corridor x 21-24 stays clear: it is the way from the big door to the doorways (x 18 and x 27, z 14-16). The rack (z 3-4) and the bay panel stay. The east strip x 25-26 is spare. |
| **Smelting hall** | x 1-8 | Crafty's 12 furnaces (from stage 2). The **AE2 corner** goes in its south-east, x 5-8 z 18-28. |
| **Storage room** | x 10-17 | Sortnado's store, plus a 4th barrel row (§4) |
| **Foundry** | x 28-43 | the Mekanism line and its expansion (§5) |
| **Power corner** | NW plinth x 29-33 z 5-7 | generators and a cube, cabled into the line |
| **Workshop bench** | x 36-38 z 23-27 | machine trials |
| **Quartz line** | x 28-35 z 22-27 | stays as it is |
| **East yard** | x 46-49 z 5-8 | the evaporation tower (Mekanism stage 4) |
| **Control tower** | x 45-55 z 20-30 | screens and dashboard; CommandBlock moves in |
| **Roof** over the bay and the foundry's west end | x 23-30, z 2-6 | helpers hover above it; loaders park on it |
| **Fuel** | x -11..-4, z 19..31 | dripstone row 1 (built), row 2 (planned) |
| **Old hut** | x -20..-10 | stays as Kyle's hut, with its lava cauldrons and the old pad's roof hole for the rounds. Its storage is drained and dismantled. |

---

## 2. The pads, in the launch bay

```
The launch bay and the store beside it, top down (ground floor)
   x   10        20       
      90123456789012345678
z   2                     
z   3 ##|||#||############
z   4 #bssssssB#||||||||# 
z   5 #b      B#/v/~~~~~R~
z   6 #b      B#~P::::  # 
z   7 #b      B#|T::::  # 
z   8 #b      B#~c::::  # 
z   9 #b      B#/^/:::  # 
z  10 #b      B#~ ::::  # 
z  11 #b      B#~P::::  # 
z  12 #b      B#|K::::  # 
z  13 #b      B#~ ::::  # 
z  14  b      B ~ ::::    
z  15  b      B ~ ::::    
z  16  ~~~~~~~~R~ ::::    
z  17 #b      B#~ ::::  # 
z  18 #b      B#~P::::  # 
z  19 #b      B#|3::::  # 
z  20 #b      B#  ::::  # 
z  21 #b      B#  ::::  # 
z  22 #b      B#  ::::  # 
z  23 #b      B#  ::::  # 
z  24 #b      B#  ::::  # 
z  25 #b      B#  ::::  ##
z  26 #b      B#M ::::  ##
z  27 #b       #M ::::  # 
z  28 #b       #  ::::  # 
z  29 |mmmmmm H#  ::::  # 
z  30 ############    ####
P pad (drive in the floor under it; sky shaft above)  T Crafty  K Counter  3 pad 3 (stage 6)
c Crafty's drop chest  v out-shaft  ^ in-shaft (miners)  / hazard stripe in the floor
| cable down the west wall (x 19, y 1-6) to each modem  ~ trunk under the upper floor (y 7)
R partition cell replaced by cable  : big-door corridor, kept clear  % drone rack  M bay panel
b B s storage room barrels and chests  m desk modems  H ladder
```

**The three lines.** Each runs north to south along x 20: the pad, then the
dispenser on its modem, then (Crafty only) the drop chest. The drive and
modem are set into the floor (y 0).

| line | pad (drive in the floor under it) | dispenser on its modem | drop chest | shafts | stage |
|---|---|---|---|---|---|
| **A: Crafty** | 20 1 6 = world **-4428 72 1524** (drive -4428 71 1524) | 20 1 7 = **-4428 72 1525** (modem -4428 71 1525) | 20 1 8 = -4428 72 1526 | out 20 · 5 (-4428 · 1523), in 20 · 9 (-4428 · 1527) | 1, filled in 5 |
| **B: Counter** | 20 1 11 = **-4428 72 1529** | 20 1 12 = **-4428 72 1530** | none (counter mode needs none) | none | 1, filled in 5 |
| **C: pad 3** | 20 1 18 = **-4428 72 1536** | 20 1 19 = -4428 72 1537 | none | none | 6 |

**Cabling.** Each modem has a cable beside it in the floor (19 0 z). From
there a cable runs up the bay's west wall (19 1..6 z) to a trunk under the
upper floor (19 7 7..19). The trunk crosses into the storage room through
the partition over the doorway (**18 7 16**), runs west along y 7 (17..11
7 16), and drops onto the west controller's modem (10 7 16, 10 6 16). The
pads therefore sit on the store's own network: Crafty and Counter see the
store directly. The storage room's ceiling is free along z 16; the lantern
at 10 7 4 and the doorway lanterns at y 3 are missed.

**Sky shafts.** The x 20 column is open from floor to roof except for two
blocks: the upper floor at y 8 and the roof tile at y 17 (the roof is 17
high at x 20). Each pad's shaft is those two cut out. A two-high glass ring
goes round each hole in the upper floor (y 9-10), so nobody walks into it in
the workshop. Nothing above the roof is in the way.

```
Section through the pads (x 20): z across, y up
   z          10        20 
      234567890123456789012
y  20     .    .      .    
y  19     .    .      .    
y  18     .    .      .    
y  17 ^^^^o^^^^o^^^^^^o^^^^
y  16     .    .      .    
y  15     .    .      .    
y  14     .    .      .    
y  13     .    .      .    
y  12     .    .      .    
y  11     .    .      .    
y  10    g.g  g.g    g.g   
y   9    g.g  g.g    g.g   
y   8 ####o####o######o####
y   7    =.    .      .    
y   6     .    .      .    
y   5     .    .      .    
y   4   # .    .      .    
y   3   | .    .      .    
y   2  %| .    .      .    
y   1   | PTc  PK     P3   
y   0 #%#.dm#.#dm#####dm###
y  -1    .   .             
y  -2    .   .             
Side view along x 20 (north on the left). P pad  T Crafty  K Counter  3 pad 3  d drive  m modem
c drop chest  o cut out of the upper floor (y 8) and the roof (y 17)  . open to the sky
g glass ring round each hole in the upper floor (y 9-10)  ^ roof  # floor, upper floor  | rack bars
```

**Crafty finding its bearings.** `survey()` turns until the drop chest is in
front (south). West is the cable, so that side is skipped. North is the pad:
it steps there and finds the drive. It maps:

| what | building | world |
|---|---|---|
| dock | 20 2 8 | -4428 73 1526 |
| exit1 | 20 2 7 | -4428 73 1525 |
| exit2 | 20 2 6 | -4428 73 1524 |
| in-shaft | 20 · 9 | |
| out-shaft | 20 · 5 | |

These are exactly the cells kept open (the check keeps x 20 y 2, z 5..9
clear). Counter also looks for its pad in front (commit e87e43f), so it
needs no chest. Each dispenser's east side (21 1-2 z) is left open for the
survey's step.

**The roof: where the drones wait.**

```
The roof over the launch bay, top down
   x        20        30 
      4567890123456789012
z  -1                    
z   0 6554887766554887766
z   1 6554887766554887766
z   2 655488776hLhLhLhL"6
z   3 6554887766554887766
z   4 6554887766L5L8L7L66
z   5 655488776655488"7"6
z   6 655488O766L5L8L7L66
z   7 6554887766554887766
z   8 655488776655488"7"6
z   9 6554887766554887766
z  10 6554887766554887766
z  11 655488O76655488"7"6
z  12 6554887766554887766
z  13 6554887766554887766
z  14 655488776655488"7"6
z  15 6554887766554887766
z  16 6554887766554887766
z  17 655488776655488"7"6
z  18 655488O766554887766
z  19 6554887766554887766
z  20 655488776655488"7"6
z  21 6554887766554887766
z  22 6554887766554887766
O roof hole over a pad (stage 1; the third in stage 6)  h helpers hover, y 21, with code change H1
L loaders park on the roof (as the code stands)  digits: top block's y, last digit (14-18)
" roof glass (glazed sawtooth faces at x 18 and 27, roof lights over the foundry)
```

- **Helpers, as the code stands, do not work here.** The hover row (pad
  x + 3..9 = x 23-29, z 2, y 13) is *inside* the building, under the roof,
  over the upper floor and the foundry. A helper leaving the pad climbs its
  shaft only to y 13 (`upFromPad()`). `goHover()` then flies sideways inside
  the upper floor, meets the foundry's wall and the roof, and ends in
  `escape`.
- **Code change H1 is needed:** hover 20 above Crafty, not 12. In
  `helper.lua hover()`, `base.f.y + 12` becomes `base.f.y + 20`, or the
  factory hands out a hover point (`base.hover`).
  - The row is then at y 21 (world 92, z 1520, x -4425..-4419).
  - That is 3 above the highest roof it crosses (y 18). The check confirms
    this.
  - A helper climbs straight up its shaft and out through the roof hole,
    and waits in the air above the roof.
  - `downToPad()` crosses at that height and drops down the shaft.
  - At the old base the change only means waiting 8 higher.
- **Loaders park on the roof** at x 24, 26, 28, 30 and z 6, 4, 2
  (world -4424..-4418, 1524..1520). That works as the code stands: they
  land on whatever is under their spot, here the roof. None of the spots is
  over a pad or a shaft.
- **Recommended change L1:** `loader.lua HOP_UP` from 14 to 22. A
  nearly-dry loader's short hop flies at Crafty + 14 = y 15, which is into
  the roof. Normal trips fly at cruise height and come down the pad shaft.
- **Miners** work as before: up the in-shaft through the bay floor at
  20 · 9, along y 2 over the chest, over Crafty and over the pad, then down
  the out-shaft at 20 · 5.
  - The two shaft holes are cut through the floor down to the miners' roads
    (world 56 and 52) only when mining resumes (`ops minershafts`).
  - Each gets hazard stripes either side.

**What else changes** (code, §6): the drones' `.base` (C1), the plot grid
(C8), and BlockParty's base-room map (B1).

---

## 3. One network

```
The cable network, top down
   x      -10       0         10        20        30        40   
      43210987654321012345678901234567890123456789012345678901234
z   2               #        #        #        #                #
z   3               #        #        #        #                #
z   4  ===R=        #-       #        #        #                #
z   5      =        #mf      #        #~~~~~~~~R~~~~~~~~~       #
z   6      =========#-       #        #~d      #        ~       #
z   7              =#mf      #        #~M      #        ~       #
z   8              =R-       #        #~       #        M~      #
z   9               #mf      #        #~       #         ~      #
z  10               #-       #        #~       #         ~      #
z  11               #mf      #        #~d      #         ~      #
z  12               #-       #        #~M      #         ~      #
z  13               #mf      #        #~       #         ~      #
z  14               #-                 ~                 ~       
z  15               #mf       K        ~                 ~       
z  16               #-        ~~~~~~~~R~                 ~       
z  17               #mf      #-       #~       #         ~      #
z  18               #-       #-       #~d      #         ~      #
z  19               #mf      #-       #~M      #         M      #
z  20               #-       #-       #        #                #
z  21               #mf      #-       #        #                #
z  22               #-       #-       #        #                #
z  23               #mf      #-       #        #                #
z  24               #-       #-       #        #                #
z  25               #mf      #-       #        #                #
z  26               #-       #-       #        #                #
z  27               #mf      #-       #        #                #
z  28               #-       #-       #        #                #
z  29               #========Rmmmmmm  #        #                #
z  30               #############################################
= new cable low (y 0-6)  ~ new cable under the upper floor (y 7)  R wall cell replaced
M new full modem  d new disk drive  - m f K existing cable, modems, furnaces, storage controller
(the yard part and the hut end of the bridge come out again in stage 6)
```

| run | cells | joins | stage | by |
|---|---|---|---|---|
| **Pad trunk** | floor cables 19 0 7 and 19 0 12, cables up the wall 19 1..6 7 and 19 1..6 12, trunk 19 7 7..19, **partition 18 7 16**, 17..10 7 16, 10 6 16 | modems A and B (and C at 19 0 19) to the west controller's modem 10 5 16 | 1 (C's drop in 6) | swarm: fit plan `pads` |
| **Desk link** | 1..8 1 29 along the hall's south wall, **9 1 29** through the partition | the hall's cable (end 1 1 28) to desk modem 10 1 29: the 12 furnaces join | 2 | swarm: fit plan `desklink` |
| **Bridge** | hut: -13 2 4 (on the old modem -13 1 4), -12 2 4, -11 2 4, **-10 2 4** (hut wall, cobblestone); yard: -9 2..0 4, -9 0 5..6, -8..-1 0 6, -1 0 7..8, riser -1 1 8; **wall 0 1 8** | the old base's network to the hall's cable at 1 1 8, for the drain | 2, out again in 6 | swarm (lab), wall cell by Kyle |
| **North line** | from the pad trunk at 19 7 5..6, east at y 7 along z 5 (20..26), **partition 27 7 5**, 28..36 7 5, down x 36 to a modem on the line's inbox (36 1 8); along x 37 at y 7 and down to a modem on the outbox (37 1 19) | the store to the Mekanism line's chests | 7 | swarm: fit plan `northline` |

**What sees what.**

- **Sortnado:** with a controller on the network, it keeps only the
  controllers as the store and ignores every other chest, furnace, turtle
  and drive (`sortnado.lua S.discover`). The pads, the hall and the old
  base joining change nothing for it.
- **Crafty, as written today:** it would take every inventory on the cable
  as storage, including the store's **In and Out barrels** and, later, the
  **line's inbox and outbox**. Code change C2 stops that. It is needed
  before the bridge (stage 2), and before Crafty is switched on in the bay
  (stage 5).

**Why the bridge goes to the hall and not to the bay.** It is a temporary
run to drain the old chests. The hall's west wall is the nearest point of
the network to the hut. The bridge's one wall cell (0 1 8) is a deepslate
tile that the lab may not dig and a fit job could only reach from outside,
so it is Kyle's.

---

## 4. Storage: retiring the old base

**Will it fit?** The old stock is 187 kinds. By Sortnado's own rule (256 and
up to a bulk slot of 2,048, 64 and up to a medium slot of 512, the rest to a
small slot) it wants:

| kind of slot | kinds | slots wanted |
|---|---|---|
| bulk | 48 | 53 |
| medium | 32 | 32 |
| small | 107 | 107 |

That is about 192 slots, and the store has 476 free. Bulk is the tight one:
71 bulk slots in all, and the store already holds 327 slots' worth. A pile
that finds no bulk slot falls back to medium and small, so nothing is
refused, but it sprawls. Kyle's rule: **keep everything that fits**. So the
barrels go up first.

**Stage 3, the wall raise.** One more row of barrels at y 4 the length of
both side walls. These cells are free: today the y 4 row only exists over
the doorway (z 13-17). The new barrels touch the barrels below them, so
they join the store by themselves.

| what | count | adds |
|---|---|---|
| limited barrels I at 10 4 4..12 and 10 4 18..28 | 20 | 20 bulk slots |
| limited barrels IV at 17 4 4..12 and 17 4 18..26 | 18 | 72 medium slots |

Nothing goes at 17 · 27..28: the ladder at 17 · 29 is climbed from there.

```
Storage room: the wall raise (stage 3), top down
   x   10       
      9012345678
z   3 ##########
z   4 #+ssssss*#
z   5 #+      *#
z   6 #+      *#
z   7 #+      *#
z   8 #+      *#
z   9 #+      *#
z  10 #+      *#
z  11 #+      *#
z  12 #+      *#
z  13 #b      B#
z  14 #b      B#
z  15 #b      B#
z  16 #b      B#
z  17 #b      B#
z  18 #+      *#
z  19 #+      *#
z  20 #+      *#
z  21 #+      *#
z  22 #+      *#
z  23 #+      *#
z  24 #+      *#
z  25 #+      *#
z  26 #+      *#
z  27 #+       #
z  28 #+       #
z  29 #mmmmmm H#
b limited barrels I (west wall)  B limited barrels IV (east wall)  s chests (north wall)
+ new limited barrel I at y 4   * new limited barrel IV at y 4   m desk modems  H ladder
```

**The haul order.** Nothing is carried by a turtle. Sortnado empties the old
chests straight into the store over the cable (code change C5, `drain`):

1. **Dead stock first,** biggest piles first, so they take the bulk slots:
   inferium essence, raw redstone blocks, prosperity shards, dark gems,
   fluorite, the exotic raw ores, flint, marble, tuff and so on. This is
   the same list the haul duty works from today, so some has already gone.
2. **Crafty's working stock last.** That is what `HAUL_NEVER` keeps back:
   coal, buckets, redstone, ingots, logs, planks, glass, sand, CC, AP,
   Mekanism and Sophisticated parts, and diamonds. It moves once C2 lets
   Crafty pull from the store. Until then Crafty keeps finding it where it
   always has.
3. **Watch Sortnado's screen.** "N waiting: the store is full" means stop,
   raise more barrels (or bring the upper floor into the store later), and
   carry on. Nothing is binned.

**The haul duty** (`haul Crafty on=1`) is turned off when the bridge goes
in. The drain replaces it, and with the store on Crafty's network it would
only carry the store into itself.

**The empty chests** come out in stage 6, with the two old furnaces and the
old network's modems and cables. The old pad's drive stays: it is the floor
the hut lava round stands on.

---

## 5. The other zones

**Smelting hall (x 1-8).** The 12 furnaces at x 2 join the network with the
desk link (stage 2). Each modem at x 1 (world -4447 72, z 1523..1545 odd)
must be switched on once by a player to show its furnace. Crafty's
`network` list says which already are (`minecraft:furnace_N`).

**AE2 corner (later, after the meteorite trip): the smelting hall's
south-east, x 5-8, y 1-3, z 18-28.** Open floor in every plan, and the
right place for it:

- **ME Bridge:** a full modem at 8 1 28 touches the desk link's cable at
  8 1 29, with the ME Bridge beside it. Sortnado's desk is the other side of
  the partition.
- **Storage bus:** on an ME cable through the partition at **9 5 15** (stone
  brick, over the doorway's lintel). The cable runs along 8 5 15..18 from
  the corner, and the bus faces the west controller at 10 5 15. The east
  controller's bus waits on its cell (TBD).
- **Power:** an AE2 Vibration Chamber, or a heat generator and cube in the
  corner, both on fuel. No Mekanism cable reaches the hall, and one is not
  worth a run across three rooms.

**Foundry: the Mekanism line's expansion.**

```
The foundry bay and east yard, top down
   x     30        40        5
      789012345678901234567890
z   3 ##|#| |#|||#|||###      
z   4 #                #      
z   5 #~GGGGG~~~       # EEEE 
z   6 # GGGGGuu~       # EEEE 
z   7 # GGGGGbu~bbbbb=b#bEEEE 
z   8 #      buM~    = # EEEE 
z   9 #      buC~    = #      
z  10 #      buS~    = #      
z  11 #      b.Dg   M= #      
z  12 #  ##  b.Ww   E= #      
z  13 # #~~# b.Y~    = #      
z  14   #~~# b.Igg   = #      
z  15    ##  b.P~   I= #      
z  16   %%%%%%.R~    = #      
z  17 # %%%%%%.E~    B #      
z  18 # %%%%%%.M~    H #      
z  19 # %%%%%%.CM      #      
z  20 # %%%%%%.=       #######
z  21 # %%%%%%.H       ###    
z  22 #    qqqq        ##     
z  23 #      q www     ##     
z  24 #        www      #     
z  25 # q qq   www      #     
z  26 # ~q~ q  www      #     
z  27 #   qq   www     ##     
z  28 #                ##     
z  29 #                ##     
Mekanism line (tools/mekline.py, as at stage 5) and stage 0 on the plinth, ground floor (y 1)
G power corner (generators, cube; y 1)  u its universal cable (y 2), joining the line's at 36 2 11
M CC modems on the line's inbox and outbox  ~ their CC cable (y 2-7)
b brine pipe from the evaporation tower (y 9)  E the tower (outside)  w workshop bench
% gas plants (stages 4-5)  q quartz line  . walkway  C chests  S sorter  t transporters
E R P I D W Y M H machines (see mekline.py)  = Mekanism cable  B cube  # basin
```

- **The line stays where `tools/mekline.py` has it**, x 35-37 z 9-21, with
  the pool (x 29-32 z 12-15) and the gas plants' ground (x 29-34 z 16-21).
  Stages 3-5 go in as that tool prints them.
- **Power corner** (NW plinth x 29-33 z 5-7, y 1):
  - generators: two more heat generators, a gas-burning generator on the
    separator's spare hydrogen, and wind generators on the roof later;
  - storage: an advanced energy cube;
  - feed: the corner's own cable runs over its machines at y 2. From
    (34, 2, 6) a universal cable runs along x 35 to (36, 2, 10), joining the
    line's cable at 36 2 11.

  That is 7 cables. It lands with or right after stage 3, because the
  separator is the big draw.
- **Line link** (stage 7). These are CC modems on the north line:
  - one at 36 1 8, on the inbox's north face;
  - one at 37 1 19, on the outbox's east face.

  With C6, Crafty fills the inbox with raw ore from the store and empties
  the outbox into it. No turtle and no Logistical Sorter are needed: it is
  the mekanism plan's stage 6 storage link, done with cable.
- **Evaporation tower** (stage 4), in the east yard:
  - footprint: 4 × 4 at x 46-49 z 5-8, on a deck at y 0;
  - height: 4 to start (about 48 blocks, a controller and 2 valves), and it
    can grow to 18 in the open;
  - brine route: out of a valve at 46 3 7, up the outside at x 45 to y 9,
    in through **44 9 7** (stone brick between the windows), west at y 9
    along z 7, and down x 34 to (34, 9, 16) over the gas plants;
  - why y 9: it is above everything in the bay (the line reaches y 4 and
    the north line y 7), and the chains at x 35 hang at z 6.

  The tower's water and the plants' layout are drawn with stage 4.
- **Stage 0 plinth** (x 41-42): runs until the line is proven. Then it takes
  a bank of factories. The infuser stays.

**Screens and dashboard.** The plan is `docs/screens.md` as written:

- the map wall and touch panel in the tower;
- the rack board and bay panel in the launch bay (both stay; the pads are
  clear of them);
- the gate lights;
- the storage screen.

The stations are bootstrapped on pad A after the move (stage 9).
CommandBlock (the controller computer in the hut at -13 0 9, with its Chat
Box and Player Detector) is carried into the tower top floor by Kyle:
computer 50 17 28, chat box 50 18 28, detector 49 17 28.

**Fuel.**

- **Row 1** (11 units): stays as it is.
- **Kyle's hut cauldrons:** these stay. Their round goes down the old pad's
  roof hole (world -4462, down to 72), so that hole and the old pad cell
  stay open.
- **Row 2** (optional): a second dripstone row 4 blocks west, world x -4458,
  z 1538..1548. Build it with `ops lava2` once there are 11 lava buckets to
  seed it.

---

## 6. Code for the move

**Status, 17 Nov:** written and pushed (commits ce6908e to 1cb5f0a, tested
in `test/movetest.py`). Each piece is inert until the move:

- **Done:** H1, L1, C1, C3, C5, C7 and C8.
- **B1:** only the door part is done (`base.door`).
- **C2:** done in a different form. Crafty puts away straight into the
  controllers, never into the In barrel, because it often puts something
  away and takes it straight back.
- **Left:** C6, and BlockParty's base-room map at the new base (untested;
  keep BlockParty idle or on helper-style jobs).

The orders as written:

- `rebase all hover=20 hop=22 door=-4426,72,1549`
- `drain Sortnado from=minecraft:chest_*` (or `stop=1`)
- `stores Crafty skip=name,name*`
- Labels `Counter`, `Counter2`, ... for the dispensers. Loads go to
  id % (N + 1), and Crafty serves any share whose counter has been quiet
  for 150 s.


| id | where | what | needed before |
|---|---|---|---|
| **H1** | `helper.lua hover()` | **Hover 20 above Crafty, not 12** (`base.f.y + 20`), or a hover point handed out by the factory (`base.hover`). With the pads inside, y 13 is inside the building: `upFromPad()` stops there and `goHover()` flies into the upper floor. At + 20 the climb clears the roof (18) and the row waits 3 above it. | stage 5 |
| **L1** | `loader.lua` | `HOP_UP` 14 → 22, so a nearly-dry loader's short hop clears the roof. Parking on the roof needs no change. | stage 5 (recommended) |
| **B1** | `builder.lua` | BlockParty's base-room map (`ROOM_REACH` 12 round Crafty, `DOOR_OFFSET` to the hut's door) assumes the hut. Either point the door at the big door (22, 2, 30) or have BlockParty fetch like a helper, straight down the pad shaft. | before BlockParty next fetches after stage 5 |
| **C1** | `swarm.lua` (+ each role) | **`rebase` order.** Every drone takes the factory's new `base` (the controller fills it in from Crafty's last status) and rewrites `.base`. Miners also drop `dock/exit1/exit2`, loaders drop their remembered base. Then reboot. | stage 5 |
| **C2** | `factory.lua discover()` | **Crafty's stores are an allow-list.** Never the store's In or Out barrel (an order `stores Crafty skip=…`, or Sortnado broadcasts its `cfg.inbox/outbox`), never the line's inbox or outbox. Put away into the **In barrel**, so Sortnado files it. Pull from the controllers and the old chests. `storageSpace()` counts the controllers. | stage 2 |
| **C3** | `factory.lua` | **Counter reports role `counter`**, not `factory`. Today the controller (`forge`) and the loaders may take Counter's base for Crafty's. Counter's facing is already fixed (e87e43f). | stage 5 |
| **C5** | `sortnado.lua` | **`drain from=<names>`.** Treat the named old chests as extra In chests until they are empty, biggest piles first. Report what is left. | stage 4 |
| **C6** | `factory.lua` | **Line duty over the cable:** raw ore from the store into the line's inbox, the outbox into the store (the mekanism plan's "line operator duty"). | stage 7 |
| **C7** | `factory.lua` | **Pad 3:** split loads three ways (or give each to the least busy pad) instead of odd and even. Counter mode never crafts, so a spare turtle can serve pad 3. | stage 6 |
| **C8** | `factory.lua plotOrigin()`, miners | **Keep the plot grid where it is.** Plots are laid out round `base.f`; moving Crafty 33 east and 4 south moves every plot. Save the old `base.f` as `plots.origin` and use it, in the miners' shaft-column check too. | before mining resumes |

The lab, fit, haul and foundry orders already exist and need no change.

---

## 7. The stages

**Storage stays usable at every step.** `$get` and the storage screen run
off the desk and never stop. Crafty keeps its old chests until they are
empty, and sees the store from stage 2 on.

### Stage 1: pads A and B, their trunk, and the sky shafts

**Goal:** the pad hardware in the bay, on the store's network, with the sky
shafts open. Nothing is switched on yet. The old base carries on as it is.

**Drones:**

- **Inside (HopTo), fit plan `pads`:**
  1. `python3 tools/retrofit.py fit pads > blueprints/factory_pads.txt`
     (commit it).
  2. `tools/order.py fit HopTo ox=-4448 oy=71 oz=1518 plan=factory_pads shell=factory_asfit3`
  3. HopTo comes in at the big door and works the 46 jobs, every stand
     inside:
     - each floor cell (drives, modems, floor cables, 4 hazard stripes)
       dug out and replaced from above;
     - the wall cables bottom up, then Crafty's drop chest;
     - the trunk from the east;
     - the partition cell from the storage room side;
     - the storage room run from below;
     - the last cell beside the controller's modem from the east.
- **Outside (OnRepeat), the sky shafts:**
  `tools/order.py lab OnRepeat clear=1 "ops=$(python3 tools/retrofit.py ops shafts)"`.
  For each pad, from above:
  1. `goto` world (-4428, 90, z).
  2. `expect` the roof tile, then `digdown` to world 81: through the roof,
     down inside the upper floor's room.
  3. Glass on all four sides at y 10 and y 9.
  4. `expect` the upper floor, then `digdown` to world 73: through it,
     down to the pad's column at y 2.
  5. `home` goes straight back up the shaft.

  `digdown` takes only plain ground. Deepslate tiles and polished deepslate
  both count, and nothing else is in the column.

**Kyle:** nothing. Modems A and B are switched on in stage 5.

**Bill:**

| item | count | from |
|---|---|---|
| CC cable | 37 | 28 stone, 7 redstone |
| wired modem (full) | 2 | |
| disk drive | 2 | recipe unverified |
| chest | 1 | |
| glass | 16 | |
| striped yellow concrete | 4 | Kyle's stock |

**Check:**
- Sortnado still says `sorting`, 803 slots.
- Both lab and fit outputs have no `stopped here`.
- Looking up from 20 1 6 and 20 1 11 shows sky.

**Storage:** unaffected.

### Stage 2: the hall and the old base join the network

**Needs C2 on Crafty first** (reboot Crafty onto it).

**Drones:**
- **Desk link (HopTo):**
  1. `python3 tools/retrofit.py fit desklink > blueprints/factory_desklink.txt`
     (commit it).
  2. `fit HopTo … plan=factory_desklink shell=factory_asfit3`
  3. HopTo takes out the stone brick at 9 1 29 from the hall side, then
     lays 8 cables from above.
- **Bridge (OnRepeat):**
  `tools/order.py lab OnRepeat clear=1 "ops=$(python3 tools/retrofit.py ops bridge)"`
  - **Inside the hut:** in through the old pad's roof hole to the row over
    Crafty (-13 2 3). Facing south, it puts a cable on top of the old modem
    at -13 2 4, then at -12 2 4 and -11 2 4. It runs `inspect` and `expect`
    each time, so it stops if anything stands there.
  - **Across the yard:** cables lying on the grass at y 0, snaking -9 0 4
    → -9 0 6 → -1 0 6 → -1 0 8, then the riser at -1 1 8.
  - **The hut's wall:** it `dig`s the cobblestone at -10 2 4 and puts a
    cable in its place, and one each at -9 1 4 and -9 2 4.
- **Then:** `tools/order.py haul Crafty on=0`.

**Kyle:**
- **Wall cell:** break the deepslate tile at world **-4448 72 1526** (from
  outside, beside the riser) and put a cable there.
- **Hall modems:** right-click each modem at x -4447 y 72, z 1523..1545
  (odd) whose ring is not red.

**Bill:** 30 cables.

**Check:**
- Crafty's `network` lists `sophisticatedstorage:controller_*` and the hall
  furnaces.
- A lab `fetch` of something only the store holds succeeds at the old pad.

**Storage:** both stores usable, and Crafty smelts on up to 14 furnaces.

### Stage 3: the store wall raise

**Drones (HopTo):**
1. `fit walls` → `blueprints/factory_walls.txt`.
2. `fit HopTo … plan=factory_walls …`
3. 38 barrels, each put in from in front so it faces into the room.

**Kyle:** nothing.

**Bill:**

| item | count | from |
|---|---|---|
| limited barrel I | 20 | about 150 planks, 20 levers |
| limited barrel IV | 18 | about 108 planks, 18 levers |
| in all | 38 | about 70 logs of one wood per craft, 38 cobblestone |

Crafty keeps 160 logs of each wood back. **Q1:** enough logs?

**Check:** Sortnado's survey shows 20 more bulk slots and 72 more medium.

**Storage:** usable throughout.

### Stage 4: drain the old chests

**Needs C5.**

`tools/order.py drain Sortnado from=minecraft:chest_*` (or the 28 names from
Crafty's `network`)

**Kyle:** nothing.

**Bill:** none.

**Check:**
- The drain report lists every old chest as empty.
- Sortnado has nothing `waiting`.

**Storage:** usable throughout. Both stores are on the cable.

### Stage 5: move Counter and Crafty into the bay; rebase

**Needs** H1, C1, C2 and C3, with L1 recommended and C8 before mining
resumes, and B1 before BlockParty next fetches.

**Before:** idle the helpers (`stop`, or wait for idle).

**Kyle, Counter first:**
1. Break Counter at world -4461 73 1523. A player-broken turtle keeps its
   label, ID and files.
2. Set it on modem B at world **-4428 72 1530**.
3. Right-click modem B (world **-4428 71 1530**).

Crafty takes back the odd loads within 150 s of not hearing Counter.

**Kyle, then Crafty:**
1. Check its inventory is empty (it stashes between jobs; a broken turtle
   drops what it holds).
2. Move the floppy from the old drive (world -4462 71 1521) to drive A
   (world **-4428 71 1524**).
3. Break Crafty and set it on modem A at world **-4428 72 1525**.
4. Right-click modem A (world **-4428 71 1525**).

Crafty sees its GPS spot no longer matches `.base`, so it re-surveys, finds
its chest south and its pad north, rewrites the floppy and reports the new
`base`.

**Drones:** `tools/order.py rebase all hover=20 hop=22 door=-4426,72,1549`,
then `resume`.

**Check:**
- Crafty's `base`: f -4428 72 1525, pad -4428 72 1524, dock
  -4428 73 1526.
- Helpers wait at world y 92, z 1520, x -4425..-4419.
- A lab `fetch` comes down through the roof at x -4428 z 1524.
- Counter serves at -4428 72 1529.
- Loaders land on the roof at x -4424..-4418.

**Storage:** about 5 minutes with no dispenser while Crafty is carried.
`$get` is unaffected.

### Stage 6: retire the old base; pad 3

**Old base:**
- **Empty chests out.** The 28 empty chests, the two old furnaces, and the
  old network's modems and cables are dug and handed in. There are two
  ways:
  - **Kyle** breaks them (about 2 minutes; the hut is cramped);
  - **the swarm**, from the old in-shaft (x -11) and out-shaft (x -15)
    beside the z 3 chest stacks, with `dig` and `handin`.

  The old pad's drive at -14 0 3 and the roof hole stay, for the lava
  rounds. Counter's old sunk drive can come out.
- **Bridge out.** `ops unbridge` takes the bridge out again:
  - the hut end;
  - a cobblestone back in the hut wall at -10 2 4;
  - the yard cables and the riser.

  Kyle can put a deepslate tile back at world -4448 72 1526 when passing.
  The cable there is a dead end after that.

**Pad 3:**
1. Run `fit pad3`: its drive, modem and wall cable. The trunk already
   reaches 19 7 19.
2. Then `ops shaftc` cuts its sky shaft at world (-4428, ·, 1536).
3. With C7, a spare turtle (one of the miners parked while storage was full)
   becomes the third dispenser, on modem C at world -4428 72 1537.
4. Kyle right-clicks modem C (world -4428 71 1537).

**Bill:**

| item | count |
|---|---|
| cable | 7 |
| disk drive | 1 |
| full modem | 1 |
| glass | 8 |
| cobblestone | 1 |

### Stage 7: the line link

**Needs C6** before the two line modems are switched on (until then Crafty
cannot see the line's chests).

**Drones (HopTo):** fit plan `northline`, 47 jobs:
- in the foundry, everything from above, starting at the two modems;
- the partition cell 27 7 5 from the west;
- the launch bay run from below, to the trunk at 19 7 6.

**Kyle:** right-click the two line modems: world -4412 72 1526 and
-4411 72 1537.

**Bill:**

| item | count |
|---|---|
| cable | 44 |
| full modem | 2 |

**Check:** 12 raw iron from the store comes back to the store as ingots.

### Stage 8: Mekanism expansion (alongside mekline stages 3-5)

**Drones** (Sticky, DropIt), lab runs in the style of `tools/mekline.py`:
- the power corner and its 7-cable link;
- for stage 4, the evaporation tower deck (16), the tower and the 27-pipe
  brine run.

Inside, the brine run is a fit plan for its one wall cell, 44 9 7.

**Kyle:** nothing expected. If a tower valve will not push brine into the
pipe by itself, it needs a Configurator click (unverified).

**Bill:**

| item | count |
|---|---|
| universal cable | 7 |
| mechanical pipe | 27 |
| polished deepslate | 16 |
| power corner machines | 2 heat generators, 1 advanced cube, 1 gas-burning generator |
| evaporation tower | about 48 blocks, a controller, 2 valves |

### Stage 9: screens and the control tower

**Drones:** as `docs/screens.md`, bootstrapping on pad A.

**Kyle:** carry CommandBlock, the Chat Box and the Player Detector into the
tower (§5).

### Stage 10: AE2 corner (after the meteorite)

As `docs/ae2-plan.md` stages C-E, in the smelting hall corner (§5).

**Kyle:** the meteorite trip and the terminals he uses.

---

## 8. Order of work at a glance

| # | stage | code first | Kyle by hand | store usable | old base |
|---|---|---|---|---|---|
| 1 | pads A, B, trunk, sky shafts | none | none | yes | running |
| 2 | desk link, bridge | C2 | 1 wall cell, hall modems | yes, both | running, on the cable |
| 3 | wall raise | none | none | yes | running |
| 4 | drain | C5 | none | yes | emptying |
| 5 | Counter and Crafty into the bay, rebase | H1, C1, C3 (L1, B1, C8) | carry 2 turtles, the floppy, 2 modem clicks | yes; 5 min without a dispenser | pad unused |
| 6 | old base out, pad 3 | C7 for pad 3 | chests (or swarm), modem C | yes | hut, lava cauldrons and roof hole only |
| 7 | line link | C6 | 2 modems | yes | |
| 8 | Mekanism expansion | none new | none | yes | |
| 9 | screens | none new | carry CommandBlock | yes | |
| 10 | AE2 | Sortnado's ME backend (branch `ae2`) | meteorite, terminals | yes | |

Stages 1 and 3 can run side by side (different helpers), and stage 8 can
run alongside anything.

---

## 9. Bill of materials

| item | st 1 | st 2 | st 3 | st 6 | st 7 | st 8 | total |
|---|---|---|---|---|---|---|---|
| CC cable | 37 | 30 | | 7 | 44 | | 118 |
| wired modem (full) | 2 | | | 1 | 2 | | 5 |
| disk drive | 2 | | | 1 | | | 3 |
| chest | 1 | | | | | | 1 |
| glass | 16 | | | 8 | | | 24 |
| striped yellow concrete | 4 | | | | | | 4 |
| limited barrel I / IV | | | 20 / 18 | | | | 38 |
| universal cable | | | | | | 7 | 7 |
| mechanical pipe | | | | | | 27 | 27 |
| polished deepslate | | | | | | 16 | 16 |

Raw, roughly:

| raw | amount | for |
|---|---|---|
| stone | 140 | cables, modems, drives |
| redstone | 30 | the same, and universal cable |
| logs | 75 | barrels, chest |
| cobblestone | 40 | levers |
| glass (smelted sand) | 24 | |
| steel ingots | 10 | |
| buckets | 4 | |

Everything but the logs is well covered by stock: stone 1,576, redstone
1,621 plus blocks, glass 128.

---

## 10. Not proven, and what to watch

- **The hover row with H1:** y 21 assumes nothing else stands on the roof
  there. The check reads the model's roof (top y 18 at x 27-28), not the
  world. Anything added on the roof later must keep x 23-29 z 2 clear above
  y 19.
- **Through the roof:** a helper climbing out of a 1 × 1 shaft through the
  roof is the same move as today's hole over the old pad. The shaft must
  never be capped.
- **Hall modems:** that the 12 were never switched on is a guess. Check
  Crafty's `network` after stage 2.
- **Modems switched on after their turtle is set down:** clicking after
  placing is the safe order, which stage 5 uses.
- **A broken turtle** keeps its label and files and drops its inventory.
- **The yard and the hut** come from scans 1-2 days old. Every lab place is
  followed by an `expect`, and a failed place stops the run.
- **Lab `dig`** (used only outside: the bridge and grass in the way) takes
  any `computercraft:` block, a parked turtle included. Loaders and helpers
  do not wait on the bridge's path today.
- **Rain and light** come in through the three 1 × 1 holes. The glass rings
  keep people out of the holes in the upper floor; the holes in the bay
  floor are only Crafty's two shaft holes, striped.

---

## 11. Open questions for Kyle

1. **Logs.** About 75 are needed for the 38 barrels and the drop chest. Are
   there enough of one wood, or will you bring some?
2. **The east storage controller's cell** (the scan is running). It decides
   where the AE2 corner's second storage bus goes, and whether the trunk at
   17..11 7 16 passes near it.
3. **The yard bench's Inventory Manager.** Should it move onto the store's
   network, so `$get` can use the card in it, or stay where it is? The
   retrofit leaves the bench alone.
4. **Stage 5 timing.** It needs you on site for about 10 minutes: Counter,
   the floppy, Crafty, two modem clicks. When suits?
5. **The launch bay's east strip** (x 25-26). Leave it spare, or give it a
   job (overflow barrels, a second Mekanism bench)?
