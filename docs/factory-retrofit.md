# Factory retrofit: moving the base into the factory

The staged plan for getting Crafty, Counter, the launch pads and the old
base's storage out of the hut and into the factory, laid out for the long
term around the **drone lane** the building was built with.

- **Revisions:** first written 17 Nov. The same night the plan moved twice:
  first to pads in the launch bay with sky shafts, then (Kyle) to the lane.
  The drones come and go by the lane, are served at pit stops on it, and
  dock in racks facing it. No roof shafts.
- **Visual plan:** `docs/factory-retrofit.html` is the top-down plan, with
  the drone routes. It is written by `python3 tools/retrofit.py page`.
- **Coordinates:** the building's own frame unless marked "world". The
  corner is -4448 71 1518, x runs east, z runs south, y 1 is the ground
  floor and y 0 the floor. Outside the building the same frame carries on:
  the west yard has x < 0. To convert:
  **world = (-4448 + x, 71 + y, 1518 + z)**.
- **Tool:** every cell comes from `tools/retrofit.py`. It checks them
  against:
  - the as-fitted shell;
  - the storeroom, foundry-floor, screens and touch-up fit plans;
  - the controller move;
  - `tools/mekline.py` to stage 5 and `tools/quartzline.py`;
  - the stage-0 machines, the dripstone lava row, the old hut and the yard
    bench.

  It also checks that both tracks, the way over the pit stops, both racks'
  homes and the gate approaches stay open, and that Crafty's survey will
  map the miners' shafts where they are planned. `python3 tools/retrofit.py check`:
  `ok: 268 retrofit cells, none on anything built or planned; the lane, both racks and the approaches open`.
- **The tool only prints** (and writes the page). It sends no orders. Its fit
  plans are printed, to be saved into `blueprints/` when their stage is due.

---

## 0. Where things stand

| what | where (building) | world | source |
|---|---|---|---|
| Crafty, on its modem | -13 1 3 | -4461 72 1521 | Crafty's `base` in status |
| Old launch pad (drive under it) | -14 1 3 | -4462 72 1521 | Crafty's `base` |
| Counter (counter mode, serving) | -13 2 5 | -4461 73 1523 | Kyle |
| Old base storage | 28 chests and 2 furnaces in and under the hut: 1,090 of 1,269 slots, 187 kinds | | Crafty's `network`, `inv` |
| The hut | x -20..-10, z 0..14; Kyle's lava cauldrons inside (rounds stay) | | BlockParty's scan |
| Store | west controller 10 5 15 (its modem 10 5 16), desk modems 10..15 1 29, In and Out barrels; east controller **TBD** (being scanned); 803 slots, 327 used | | `ctlmove.py`, storeroom plan, Sortnado |
| **Drone lane (built)** | x 0..44, z 1-2, y 1-3, behind a screen at z 3: the hazard floor, bars and posts, portholes at x 9, 18, 27, gates at x 0 and 44 with IN/OUT lights (0/44, 4, 1-2) | | as-fitted shell, touch-up |
| **Rack 1 (built)** | launch bay x 19-26: copper pads at y 0 and y 2 (z 3), bars at z 4, the name board at y 4 | | as-fitted shell; the board's monitors are in `factory_screens` |
| The plan's pit stop in the bay | drive 21 1 1, modem 22 1 1, furnace 23 1 1, chest 23 2 1, holes in the lane floor at 20 0 1 and 24 0 1 | | blueprint (as far as fitted: check in the world) |
| Lane access from inside | the foundry's hatch at 32 1-2 3 (no bars), how the touch-up fit got onto the lane | | blueprint |
| Smelting hall | 12 furnaces at x 2 (odd z 5..27), modems at x 1, cable at x 1 (even z 4..28; its north end is 1 1 4) | | as-fitted shell |
| Outside the west gate | the hill's shoulder: ground up to y 3 at x -1..-2 z 1, y 1 at x -1 z 2 (scan from before the building) | | meadow scan |
| Outside the east gate | the dirt bank, below the floor: open | | terraform plan |
| Chunks round the factory | force-loaded | | Kyle |

---

## 1. The layout

```
The site, top down, x -20..56 (building's own frame; 1 char = 1 block)
   x  -20       -10       0         10        20        30        40        50     
      09876543210987654321012345678901234567890123456789012345678901234567890123456
z  -1                                                                              
z   0 HHHHHHHHHHH         #############################################            
z   1 HHHHHHHHHHH     ,,,,<<KP<cCP<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<            
z   2 HHHHHHHHHHH=========>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>            
z   3 HHHHHHHHHHH=        #::::::::#::::::::#11111111#:::::::22222222:#            
z   4 HHHHHHHHHHH=        #ssssssss#SSSSSSSS#yy    yy#fffffffffffllfff#            
z   5 HHHHHHHHHHH         #ssssssss#SSSSSSSS#yy    yy#fGGGGGfffffllfff# EEEE       
z   6 HHHHHHHHHHH         #ssssssss#SSSSSSSS#yy    yy#fGGGGGfffffll00f# EEEE       
z   7 HHHHHHHHHHH         #ssssssss#SSSSSSSS#yy    yy#fGGGGGfffffll00f# EEEE       
z   8 HHHHHHHHHHH         #ssssssss#SSSSSSSS#yy    yy#fffffffffffll00f# EEEE       
z   9 HHHHHHHHHHH         #ssssssss#SSSSSSSS#yy    yy#fffffffMMMMll00f#            
z  10 HHHHHHHHHHH         #ssssssss#SSSSSSSS#yy    yy#fffffffMMMMll00f#            
z  11 HHHHHHHHHHH         #ssssssss#SSSSSSSS#yy    yy#fffffffMMMMll00f#            
z  12 HHHHHHHHHHH         #ssssssss#SSSSSSSS#yy    yy#fggggggMMMMll00f#            
z  13 HHHHHHHHHHH         #ssssssss#SSSSSSSS#yy    yy#fggggggMMMMll00f#            
z  14 HHHHHHHHHHH         #ssssssss SSSSSSSS yy    yy fggggggMMMMll00f#            
z  15                     #ssssssss SSSSSSSS yy    yy fggggggMMMMll00f#            
z  16                     #ssssssss SSSSSSSS yy    yy fggggggMMMMll00f#            
z  17                     #ssssssss#SSSSSSSS#yy    yy#fggggggMMMMll00f#            
z  18                     #ssssAAAA#SSSSSSSS#yy    yy#fggggggMMMMll00f#            
z  19          ~~~~~~~~   #ssssAAAA#SSSSSSSS#yy    yy#fggggggMMMMll00f#            
z  20          ~~~~~~~~   #ssssAAAA#SSSSSSSS#yy    yy#fggggggMMMMll00f#TTTTTTTTTTT 
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
< > the drone lane: back track westbound, front track eastbound  K Counter  C Crafty  P pads  c drop chest
1 rack 1 (helpers' homes)  2 rack 2 (loaders' homes)  : the lane's screen  , the west gate's apron
s smelting hall (12 furnaces, Crafty's)  A AE2 corner (later)  S storage room (+ a 4th barrel row)
y launch bay (corridor x 21-24 clear)  H old hut  = bridge for the drain (temporary)  ~ lava rows
f foundry floor  G power corner  M Mekanism line  g pool, gas plants  Q quartz line  w workshop bench
l operator lane  0 stage-0 plinth  E evaporation tower (outside)  T control tower (screens)  # walls
```

| zone | box | what it is for |
|---|---|---|
| **Drone lane** | x 0..44, z 1-2 | All drone traffic in and out, and the pit stops. Back track (z 1) westbound, front track (z 2) eastbound, at y 2. |
| **Pit stops** | x 2-8, z 1 (the hall's stretch of the lane) | Counter, and Crafty with its drop chest. |
| **Rack 1** | x 19-26, z 3 (launch bay) | the helpers' 16 homes |
| **Rack 2** | x 35-42, z 3 (foundry) | the chunk loaders' 16 homes (stage 6) |
| **Smelting hall** | x 1-8 | Crafty's 12 furnaces; the **AE2 corner** in its south-east, x 5-8 z 18-28 |
| **Storage room** | x 10-17 | Sortnado's store, plus a 4th barrel row (§4) |
| **Launch bay** | x 19-26 | Free floor now the pads are on the lane. The way in from the big door (corridor x 21-24); rack 1 at its north end. |
| **Foundry** | x 28-43 | the Mekanism line and its expansion (§5); rack 2 at its north end |
| **Power corner** | NW plinth x 29-33 z 5-7 | generators and a cube |
| **Workshop bench** | x 36-38 z 23-27 | machine trials |
| **Quartz line** | x 28-35 z 22-27 | stays as it is |
| **East yard** | x 46-49 z 5-8 | the evaporation tower (Mekanism stage 4) |
| **Control tower** | x 45-55 z 20-30 | screens and dashboard; CommandBlock moves in |
| **West gate's apron** | x -4..-1, z 1-2 | dug back to y 1 so drones can fly in |
| **Old hut** | x -20..-10 | Kyle's hut and lava cauldrons stay; the old storage is drained and dismantled |
| **Fuel** | x -11..-4, z 19..31 | dripstone lava rows |

---

## 2. The lane: pit stops, racks, routes

```
The drone lane, top down (x -5..47, z -1..5)
   x       0         10        20        30        40      
      54321012345678901234567890123456789012345678901234567
z  -1                                                      
z   0      #############################################   
z   1  ,,,,<<KP^cTPv<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< E 
z   2   W,,>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> X 
z   3      ##|||#||###|||#||##11111111##|#| |#22222222##   
z   4      ##       ##########||||||||#       |||||||| #   
z   5      ###      ##      ##        #                #   
< back track (z 1, westbound)  > front track (z 2, eastbound); drones fly at y 2, gates at x 0 and 44
K Counter  T Crafty  P their pads  c Crafty's drop chest  ^ v miners' in- and out-shaft (in the lane floor)
1 rack 1 (launch bay, built): 16 homes, low and high  2 rack 2 (foundry, stage 6): 16 more
W drones come down here, outside the west gate, and go in on the front track (east)
E ... outside the east gate, in on the back track (west)  X out by the east gate on the front track
, the west gate's apron, dug out (the hill's shoulder)  | # % the screen, walls, rack pads
```

### The pit stops

They sit in the smelting hall's stretch of the lane, just inside the west
gate, on the back track at drone height (y 2). Every stop block sits on a
block of its own at y 1, and the cable runs under the lane floor.

| | building | world | under it (y 1) |
|---|---|---|---|
| **Counter** | 2 2 1 | -4446 73 1519 | its modem 2 1 1 |
| Counter's pad | 3 2 1 | **-4445 73 1519** | its drive 3 1 1 |
| Crafty's in-shaft (miners) | 4 · 1 | -4444 · 1519 | (cut when mining resumes) |
| Crafty's drop chest | 5 2 1 | -4443 73 1519 | a block, 5 1 1 |
| **Crafty** | 6 2 1 | **-4442 73 1519** | its modem 6 1 1 |
| Crafty's pad | 7 2 1 | **-4441 73 1519** | its drive 7 1 1 |
| Crafty's out-shaft (miners) | 8 · 1 | -4440 · 1519 | (cut when mining resumes) |

**Why there.**
- **The cable is short.** The hall's cable ends at 1 1 4, right behind the
  screen. A cable through the screen post at 1 1 3 runs under the lane
  floor along the front track (1..6 0 2) and under each modem (2 0 1,
  6 0 1). That is 9 cells, all on the hall's cable and so the 12 furnaces.
  The desk link (stage 1) puts the hall on the store's network.
- **Upstream of both racks.** A drone served at a pad goes on east to its
  rack home or out of the east gate. It never has to turn back.
- **Crafty's survey works unchanged.** It turns until its chest is in front
  (west). North is the wall and south is the front track; east is the pad,
  where it finds the drive. It maps:
  - dock 5 3 1, exit1 6 3 1, exit2 7 3 1;
  - in-shaft x 4, out-shaft x 8.

  These are the cells planned for them (the check computes them). The
  miners' service row is y 3 over the stop.
- **Counter's survey is the same.** It looks for its pad in front too and
  needs no chest.

### The racks

| rack | where | homes | for |
|---|---|---|---|
| **1 (built)** | launch bay x 19-26, z 3 | 16: low (x, 1, 3) on the copper pad in the floor, high (x, 3, 3) on the copper pad at y 2 | the helpers (home i: x 19 + i % 8, the low row first) |
| **2 (stage 6)** | foundry x 35-42, z 3 | 16, the same | the chunk loaders |

Rack 2 is built where the foundry's screen is. The bars (or posts) at y 1
and y 3 come out, copper pads go in the floor and at y 2, and the bars go
back one row, to z 4. The bar at y 4 stays as the lintel.

### The routes

Drones fly the lane at y 2:

| route | path |
|---|---|
| **In from the west** | come down outside the west gate at -3 2 2 (world -4451 73 1520), in on the front track, east to the pad's x, one step north onto the pad |
| **In from the east** | come down outside the east gate at 46 2 1 (world -4402 73 1519), in on the back track, west through the three portholes to Crafty's pad, onto it from the east |
| **To Counter's pad from the east** | at x 8 up to y 3, over Crafty's stop, down onto 3 2 1 |
| **From a pad** | a step south onto the front track, then east: to the rack home (a step south into it, at y 1 or y 3), or out of the east gate at 46 2 2 and up |
| **From a rack home to a pad** | north twice (to the back track), then west |

**Why this is safe:**
- Each track runs one way.
- The only shared stretch is y 3 over Crafty's stop, which the miners also
  use; they are paused today.
- A drone meeting a turtle in its way waits for it, up to 90 s (`step()`).

**The gates.**
- **West gate:** its apron is dug back (lab `apron`: 7 columns of plain
  ground, down to y 1).
- **East gate:** opens onto the bank and is clear. There is a lantern in
  the east gate at 44 3 1 (y 3 of the back track), which is fine at drone
  height y 2.

**Old pit stop.** The plan's bay pit stop (whatever of it was fitted) comes
off the back track, and its two floor holes (20 0 1, 24 0 1) are filled with
hazard concrete.

---

## 3. One network

```
The cable network, top down
   x      -10       0         10        20        30        40   
      43210987654321012345678901234567890123456789012345678901234
z   0               #############################################
z   1                 Md  Md              mf                     
z   2      ================                                      
z   3      =        #R       #        #        #                #
z   4  ===R=        #-       #        #        #                #
z   5               #mf      #        #        #                #
z   6               #-       #        #        #                #
z   7               #mf      #        #        #                #
z   8               #-       #        #        #        M~      #
z   9               #mf      #        #        #         ~      #
z  10               #-       #        #        #         ~      #
z  11               #mf      #        #        #         ~      #
z  12               #-       #        #        #         ~      #
z  13               #mf      #        #        #         ~      #
z  14               #-                                   ~       
z  15               #mf       K                          ~       
z  16               #-        ~~~~~~~~R~~~~~~~~R~~~~~~~~~~       
z  17               #mf      #-       #        #         ~      #
z  18               #-       #-       #        #         ~      #
z  19               #mf      #-       #        #         M      #
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
= new cable low (y 0-6; under the lane floor along the front track)  ~ new cable at y 7  R wall cell replaced
M new full modem (Counter's, Crafty's, the line's)  d new disk drive  - m f K existing cable, modems, furnaces, controller
(the bridge from the hut, x -13..-1, comes out again once the old chests are empty)
```

| run | cells | joins | stage | by |
|---|---|---|---|---|
| **Pit stop link** | screen post **1 1 3** replaced by cable; under the lane floor 1 0 3, 1..6 0 2, 2 0 1, 6 0 1 | the hall's cable (1 1 4) to Counter's and Crafty's modems | 1 | swarm: fit `pitstop` |
| **Desk link** | 1..8 1 29 along the hall's south wall, **9 1 29** through the partition | the hall's cable to desk modem 10 1 29: the store | 1 | swarm: fit `desklink` |
| **Bridge** (for the drain) | hut: -13..-11 2 4 (on the old modem -13 1 4), **-10 2 4** (cobblestone); yard: -9 2..0 4, -9 0 3..2, -8..-1 0 2; under the west gate **0 0 2** | the old base to the pit stop link at 1 0 2 | 2, out again in 6 | swarm: lab `bridge`, fit `gatelink` |
| **North line** | 10 6..7 16 up from the west controller's modem, east along y 7 z 16 through **18 7 16** and **27 7 16**, to modems on the Mekanism line's inbox (36 1 8) and outbox (37 1 19) | the store to the line | 7 | swarm: fit `northline` |

**No hand-placed cable at all.**
- Every replaced cell inside the building is a fit job standing in a room
  or on the lane. The fit walker gets onto the lane by the foundry's hatch,
  as the touch-up did.
- The bridge comes in under the west gate. The swarm digs the hut's
  cobblestone itself.

**What sees what.**
- **Sortnado:** with a controller on the cable, it keeps only the
  controllers as the store and ignores every other chest, furnace, turtle
  and drive.
- **Crafty (code done):** skips barrels, Inventory Managers and anything
  named with `stores Crafty skip=…`. It puts away into the controllers
  first.
- **The line's inbox and outbox (stage 7):** before their modems are
  switched on, Crafty must be told
  `stores Crafty skip=minecraft:chest_<inbox>,minecraft:chest_<outbox>`.

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
desk link. Each modem at x 1 (world -4447 72, z 1523..1545 odd) must be
switched on once by a player to show its furnace. Crafty's `network` says
which already are.

**AE2 corner (later): the smelting hall's south-east, x 5-8, y 1-3, z
18-28.**
- **ME Bridge:** a full modem at 8 1 28 on the desk link's cable, with the
  ME Bridge beside it.
- **Storage bus:** on an ME cable through the partition at 9 5 15, facing
  the west controller (10 5 15). The east controller's bus waits on its
  cell.
- **Power:** a Vibration Chamber, or a heat generator and cube, on fuel.

**Launch bay.** It is free now that the pads are on the lane. It is the way
in from the big door, and rack 1 is at its north end. The east strip
(x 25-26) and the west strip (x 19-20) are spare floor.

**Foundry: the Mekanism line's expansion.**

```
The foundry bay and east yard, top down
   x     30        40        5
      789012345678901234567890
z   3 ##|#| |#|||#|||###      
z   4 #                #      
z   5 # GGGGG          # EEEE 
z   6 # GGGGGuu        # EEEE 
z   7 # GGGGGbubbbbbb=b#bEEEE 
z   8 #      buM~    = # EEEE 
z   9 #      buC~    = #      
z  10 #      buS~    = #      
z  11 #      b.Dg   M= #      
z  12 #  ##  b.Ww   E= #      
z  13 # #~~# b.Y~    = #      
z  14   #~~# b.Igg   = #      
z  15    ##  b.P~   I= #      
z  16 ~~%%%%%%.R~    = #      
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

- the gate lights (now in real use: drones come and go by the gates);
- the rack board over rack 1;
- the bay panel;
- the map wall and touch panel in the tower;
- the storage screen.

Rack 2 can get a board of its own later (8 monitors at y 4, z 4).
CommandBlock (the controller computer in the hut, with its Chat Box and
Player Detector) is carried into the tower by Kyle.

**Fuel.**
- **Row 1** (11 units): stays.
- **Kyle's hut cauldrons:** these stay, and their round goes down the old
  pad's roof hole, so that hole and the old pad cell stay open.
- **Row 2** (optional, `ops lava2`): world x -4458, z 1538..1548, once there
  are 11 lava buckets to seed it.

---

## 6. Code

**Done (pushed, `test/movetest.py`).** All of this is inert until the move:

- the `rebase` order (every drone asks Crafty for the new base and
  restarts);
- Crafty's store filter;
- Counter reporting role `counter`;
- the 3-way pad split (labels `Counter`, `Counter2`, …);
- the plot grid kept where it is (`plots.origin`);
- Sortnado's `drain`;
- the helpers' hover height and the loaders' hop height (`base.hoverUp`,
  `base.hopUp`);
- the builder's door (`base.door`).

**For the lane (done; inert until `rebase ... lane=1`; `test/lanetest.py`):**

| id | where | what |
|---|---|---|
| **N1** | `helper.lua` | **Fly the lane** (`LN`). From outside: down outside the gate on the near side, at lane height (world y 73). In by the west gate on the front track (eastbound), north onto the pad; in by the east gate on the back track (westbound), onto the pad from the east (over Crafty's stop, y 74, for the Counter's pad). Off a pad: a step south onto the front track, then east. Off to a job: east along the front track and out of the east gate before climbing. Setting something on a pad: the row just over it. |
| **N2** | `helper.lua` | **Rack homes.** An idle helper, or one waiting for a load, goes into its rack home instead of hovering: home i is world x -4429 + i % 8, y 72 (i < 8) or 74, z 1521, i by name in the factory's helper list (Pushy 0, HopTo 1, ... TargetLock 15), else id % 16. In from the front track, a step south. |
| **N3** | `swarm.lua` | `rebase ... lane=1` puts the lane (`M.LANE`: gates, tracks, approaches, rack) into `.base`; a later rebase without `lane=` keeps it; `lane=0` drops it. |
| **L1b** | `loader.lua` | With the lane, a loader no longer hops onto the (indoor) pad for fuel: it burns what it carries and asks for a feed. |
| **L2** | `loader.lua` | Loaders park in rack 2 (later; until then they park where Crafty's offsets put them, on the hill north of the lane: x 10-16, z 0..-4). |
| **C6** | `factory.lua` | The line duty over the cable (stage 7). |
| **B1** | `builder.lua` | BlockParty's base-room map assumes the hut. Keep it idle or on helper-style jobs after the move. |

---

## 6b. Rack loading bays (Kyle, by hand; docs/rack-build.html)

Loads go over the cable, not across a pad: Crafty pushes a drone's load and
fuel straight into it while it sits in its rack home (`turtle_<id>` on the
network) and pulls hand-ins back. `python3 tools/retrofit.py check` checks
the cells (stage 11 in the tool) and that every bay is wired to the store.

| what | building x y z | world | count |
|---|---|---|---|
| bay modems (full block), the middle shelf: each touches the low home under it and the high home on it | 19..26 2 3 | -4429..-4422 73 1521 | 8, **right-clicked** |
| low shelf's panel: advanced monitors facing the bay, in place of the y 2 bars (the permanent neighbour that keeps each bay modem switched on) | 19..26 2 4 | -4429..-4422 73 1522 | 8 |
| high shelf's panel: the existing name board | 19..26 4 4 | | (built) |
| the board's computer, moved into the wall touching the board's west end | 18 4 4 | -4430 75 1522 | 1 (was at 22 4 3; its ender modem at 22 5 3 comes off) |
| connector modems in the x 18 wall (not clicked) | 18 1 3, 18 2 3, 18 2 4, 18 3 4 | -4430 72/73 1521, -4430 73/74 1522 | 4 |
| cable in the closed floor cell under them | 18 0 3 | -4430 71 1521 | 1 |
| cable under the lane floor (front track), to the hall corner | 18 -1 3; 18..1 -1 2; 1 -1 3; 1 -1 4 | y 70 | 21 |
| floor plug under the hall cable's end (not clicked) | 1 0 4 | -4447 71 1522 | 1 |

Visible afterwards: the shelf (modem texture instead of copper on the
high shelf, edge-on from the lane), the strip, and the lane-side faces of
two connector bricks at the x 18 wall end. Nothing sticks out. Rack 2
(stage 6) gets the same: modems for its y 2 shelf, a strip at y 2, z 4,
connectors at 34 1-2 3 and a cable under the lane floor from x 34 to x 19.

**The bays and the watchdog (code; test/baytest.py):**

| what | where | when |
|---|---|---|
| A helper on the lane waits for a load docked in its rack home, says its name on the cable (`LN.bay()`: the shelf modem's `getNameLocal`) and which slots go back; with the bay modem off it says `bay modem off` and uses the pad | `helper.lua` | after `rebase ... lane=1` |
| Crafty takes the hand-ins back (`pullItems`) and pushes the load and fuel straight in (`pushItems` to `turtle_<id>`); not on the cable yet: it tries again every 15 s | `factory.lua` `K.deliverBay` | whenever an order names a bay |
| Watchdog: a helper in `waiting for materials`, `fetching materials` or `stuck under ...` over 10 min gets its load announced again (and a Counter's load taken over); 5 min later a direct `reboot`; listed as `stalled` in Crafty's status | `factory.lua` `K.watchdog` | now |
| Counter fallback: a load ready at a Counter's pad 3 min and not collected is made and served by Crafty | `factory.lua` | now |
| Rack panels: per home name, state, fuel; green docked, amber out, grey free, red silent; tap for the drone's screen. Crafty passes statuses and reboot orders on over the cable (channel 4711). The board's computer becomes `rack` by itself once it is in the wall on the cable | `rack.lua`, `screens.lua` | when moved |

## 7. The stages

**Storage stays usable at every step.** `$get` and the storage screen run
off the desk and never stop. Crafty keeps its old chests until they are
empty, and sees the store from stage 2 on.

### Stage 1: pit stops, their cable, the desk link, the west gate

**Drones (HopTo):**
1. Save `python3 tools/retrofit.py fit pitstop` and `fit desklink` as
   `blueprints/factory_<name>.txt` and commit them.
2. `tools/order.py fit HopTo ox=-4448 oy=71 oz=1518 plan=factory_pitstop shell=factory_asfit3`, then the same with `plan=factory_desklink`.
3. `pitstop` (24 jobs, every stand on the lane):
   - the old bay pit stop dug out from the front track;
   - its two floor holes filled;
   - the screen post 1 1 3 out, the floor under it cut, a cable in;
   - the floor cable;
   - the two modems and drives from above;
   - the chest's block and the chest.

   `desklink` is 9 jobs.

**Drones (OnRepeat), the apron:**
`tools/order.py lab OnRepeat clear=1 "ops=$(python3 tools/retrofit.py ops apron)"`.
For each column, `goto` above it, then `digdown` to world 72 (plain ground
only).

**Kyle:** switch on any hall modem whose ring is not red (x -4447 y 72, z
1523..1545 odd). Counter's and Crafty's modems are switched on in stage 5.

**Bill:**

| item | count |
|---|---|
| cable | 19 |
| full modem | 2 |
| disk drive | 2 |
| chest | 1 |
| polished deepslate | 1 |
| striped yellow concrete | 2 |

**Check:**
- Sortnado still has 803 slots.
- The hall furnaces show on the store's network.
- A drone can fly from -3 2 2 to 44 2 2 (lab: `goto` the west apron, then
  `fwd`).

### Stage 2: the bridge (old network joined)

**Needs** Crafty on the new code (done; `reboot Crafty`).

**Drones:**
- `ops bridge` (OnRepeat): the hut end through the roof hole, the hut's
  cobblestone, the yard run along z 2.
- `fit gatelink` (HopTo): the floor under the west gate, 0 0 2.
- Then `haul Crafty on=0`.

**Kyle:** nothing.

**Bill:** 18 cables.

**Check:** Crafty's `network` lists `sophisticatedstorage:controller_*` and
the hall furnaces.

### Stage 3: the store wall raise

**Drones (HopTo):** fit `walls`, 38 jobs.

**Bill:** 20 limited barrels I and 18 limited barrels IV, about 70 logs.

### Stage 4: drain the old chests

**Drones:** `tools/order.py drain Sortnado from=minecraft:chest_*`. Before
stage 7 the only chests on the cable are the old base's and Crafty's drop
chest; the drop chest touches no modem, so it is never on the cable.

**Check:** Sortnado's status `drain` reaches 0 left.

### Stage 5: the move

1. **Code:** stop the helpers (`stop all`, or wait for idle).
2. **Kyle, Counter first:**
   1. Break Counter (it keeps label, ID and files).
   2. Set it at world **-4446 73 1519**.
   3. Right-click its modem below (-4446 72 1519).
3. **Kyle, Crafty:**
   1. Move the floppy from the old drive (world -4462 71 1521) to Crafty's
      drive (world **-4441 72 1519**).
   2. Check Crafty's inventory is empty.
   3. Break Crafty and set it at world **-4442 73 1519**.
   4. Right-click its modem below (-4442 72 1519).
4. **Wait** until Crafty's status shows `base.f` -4442 73 1519.
5. **Orders:**
   `tools/order.py rebase all hover=20 hop=22 lane=1 door=-4426,72,1549`,
   then `resume all`.
6. **When mining resumes:** `ops minershafts` cuts the two shafts through
   the lane floor.

### Stage 6: old base out, rack 2

**Old base:**
- The empty chests, furnaces and the old network out: Kyle, or the swarm
  from the old shafts.
- `ops unbridge`: the bridge out, and the hut wall made good.

**Rack 2:** fit `rack2`, 56 jobs:
- 16 bars or posts out;
- 16 copper pads in, at y 0 and y 2;
- 24 bars at z 4, from the foundry side.

Rack 2 is used once the loaders learn the lane (L2).

**Bill:** 16 cut copper, 24 iron bars.

### Stages 7-10

7. **The north line:** fit `northline`, 51 cables and 2 modems. Then
   `stores Crafty skip=…` for the line's two chests, then Kyle switches on
   the two modems.
8. **Mekanism expansion:** the power corner, the evaporation tower and
   brine (§5).
9. **Screens:** `docs/screens.md`. Kyle carries CommandBlock.
10. **AE2:** after the meteorite trip.

---

## 8. Order of work at a glance

| # | stage | Kyle by hand | store usable | old base |
|---|---|---|---|---|
| 1 | pit stops, links, apron | hall modems | yes | running |
| 2 | bridge | none | yes, both | running, on the cable |
| 3 | wall raise | none | yes | running |
| 4 | drain | none | yes | emptying |
| 5 | move, rebase | carry Counter and Crafty, the floppy, 2 modem clicks | yes; minutes without a dispenser | pad unused |
| 6 | old base out, rack 2 | chests (or swarm) | yes | hut and lava only |
| 7-10 | north line, Mekanism, screens, AE2 | 2 modems, CommandBlock, meteorite | yes | |

---

## 9. Bill of materials

| item | st 1 | st 2 | st 3 | st 6 | st 7 | st 8 | total |
|---|---|---|---|---|---|---|---|
| CC cable | 19 | 18 | | | 51 | | 88 |
| wired modem (full) | 2 | | | | 2 | | 4 |
| disk drive | 2 | | | | | | 2 |
| chest | 1 | | | | | | 1 |
| polished deepslate | 1 | | | | | 16 | 17 |
| striped yellow concrete | 2 | | | | | | 2 |
| limited barrel I / IV | | | 20 / 18 | | | | 38 |
| cut copper | | | | 16 | | | 16 |
| iron bars | | | | 24 | | | 24 |
| universal cable / mechanical pipe | | | | | | 7 / 27 | |

Everything is in stock or in Crafty's recipes except about 70 logs for the
barrels (**Q1**). Cut copper takes copper ingots: 16 needs 4 copper blocks.

---

## 10. Not proven, and what to watch

- **What was fitted of the old bay pit stop.** The fit plan digs whatever is
  there; a dig on air does nothing.
- **The west gate's apron** comes from a scan from before the building.
  `digdown` stops at anything that is not plain ground, and the lab notes
  it.
- **Traffic.** A one-way lane copes with a handful of helpers. Many at once
  queue at the pads. A turtle waits up to 90 s for another in its way, then
  gives up and tries again later.
- **The lantern at 44 3 1** hangs in the east gate's top layer. It is fine at
  drone height, but move it if anything ever flies the lane at y 3 there.
- **The rack homes** are open to the lane only: a drone gets in and out
  sideways from the front track, low or high.

---

## 11. Open questions for Kyle

1. **Logs.** About 70 are needed for the barrels. Enough of one wood?
2. **The east storage controller's cell** (scan running): for AE2's second
   bus.
3. **The yard bench's Inventory Manager.** Move it onto the store's network,
   or leave it?
4. **Stage 5 timing:** about 10 minutes on site.
5. **Rack 2's name board.** Wanted (8 more monitors)?
