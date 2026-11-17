# Factory retrofit: moving the base into the factory

The staged plan for getting Crafty, Counter, the launch pads and the old
base's storage out of the hut and into the factory, and for laying the
building out properly for the long term. Written 17 Nov (evening), from the
plans in this repository and the swarm's status of that time.

- **Coordinates:** the building's own frame unless marked "world". The
  corner is -4448 71 1518, x runs east, z runs south, y 1 is the ground
  floor and y 0 the floor. The same frame carries on outside the building,
  so the west yard has x < 0. To convert:
  **world = (-4448 + x, 71 + y, 1518 + z)**.
- **Tool:** every cell below comes from `tools/retrofit.py`, which checks it
  against everything built or planned. That covers the as-fitted shell, the
  storeroom, foundry-floor, screens and touch-up fit plans, the controller
  move, `tools/mekline.py` up to stage 5, `tools/quartzline.py`, the
  stage-0 machines, the dripstone lava row, the old hut and the yard bench.
  `python3 tools/retrofit.py check` prints `ok: 304 retrofit cells, none on
  anything built or planned`. The maps here are the tool's own output.
- **The tool only prints.** It sends no orders and writes no files. Its fit
  plans are printed so they can be saved into `blueprints/` when their
  stage is due.

---

## 0. Where things stand

| what | where (building) | world | source |
|---|---|---|---|
| Crafty, on its modem | -13 1 3 (modem -13 0 3) | -4461 72 1521 | Crafty's `base` in status |
| Old launch pad (drive under it) | -14 1 3 (drive -14 0 3) | -4462 72 1521 | Crafty's `base` |
| Drop-off chest (on a furnace) | -12 1 3 | -4460 72 1521 | Crafty's `base`, hut scan |
| In-shaft / out-shaft | -11 · 3 / -15 · 3 | x -4459 / -4463 | `2*dock-exit1`, `2*exit2-exit1` |
| Old base storage | 28 chests and 2 furnaces, x -15..-11, y -4..1, z 1..6 | | Crafty's `network` |
| Its contents | 1,090 of 1,269 slots used: 187 kinds, 56,647 items | | Crafty's `storage` and `inv` |
| Counter | -13 2 5? (status: "woke up" at -4461 73 1523, role miner) | | **unclear: see Q1** |
| The hut | x -20..-10, z 0..14, roof at y 3, roof hole over x -14..-12 z 3 | | BlockParty's `hut_lava` scan |
| Kyle's lava cauldrons | -19 -1 3..9 | -4467 70 1521..1527 | lava rounds |
| Dripstone lava row (11 units) | x -7..-4, y 5..10, z 19..31 | -4454, 1538..1548 | `tools/lavafarm.py` |
| Yard bench (infuser + Inventory Manager) | cobblestone x -8..-3, y 0..2, z 11..16; manager -5 3 14 | -4453 74 1532 | `docs/foundry.md`, meadow scan |
| Helpers hover (today) | x -11..-5, y 13, z -1 | -4459..-4453 84 1517 | `hover()`, matches status |
| Loaders park (today) | x -9..-3, z 2 / 0 / -2 | -4457..-4451, 1520..1516 | `parkSpot()`, matches status |
| Store | west controller 10 5 15 (modem 10 5 16), desk modems 10..15 1 29, In and Out barrels on the desk | | `tools/ctlmove.py`, storeroom plan |
| Store size | 803 slots, 327 used. The plan has 71 limited barrels I (bulk), 65 limited barrels IV (260 medium slots) and 18 chests (486 small slots). | | Sortnado's report, storeroom plan |
| East controller | placed by hand; its cell is not recorded | | **Q2** |
| Smelting hall | 12 furnaces at x 2 (odd z 5..27), modems at x 1 (odd z), cable at x 1 (even z 4..28) | | as-fitted shell |
| Mekanism line | stage 2 built, stage 3 being built, x 35-37 z 9-21 | | `tools/mekline.py` |
| Quartz line | foundry SW corner, x 28-35 z 22-27 | | `tools/quartzline.py` |

**What ties the drones to Crafty's spot.** It matters for where the pads can
go. Everything is measured from Crafty (`base.f`) or from its pad
(`base.exit2`):

- **Helpers** fall straight down onto the pad. They wait in a row 12 above
  Crafty, 4 blocks north of the pad, at pad x + 3, + 5, + 7 and + 9
  (`helper.lua hover()`).
- **Loaders** park on 12 spots at Crafty x + 4..10 and z - 1, - 3, - 5
  (`loader.lua parkSpot()`).
- **Miners** go up the in-shaft beyond the drop chest and down the out-shaft
  beyond the pad. Their plot grid is laid out around Crafty
  (`factory.lua plotOrigin()`).
- **Each drone keeps its own copy** of the base in `.base`, written once when
  it was drafted. Nothing updates it today.

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
z   4 HHHHHHHHHHHPPPPPPPPP#ssssssss#SSSSSSSS#yy    yy#fffffffffffllfff#            
z   5 HHHHHHHHHHHPPPPPPPPP#ssssssss#SSSSSSSS#yy    yy#fGGGGGfffffllfff# EEEE       
z   6 HHHHHHHHHHHPPPPPPPPP#ssssssss#SSSSSSSS#AA    yy#fGGGGGfffffll00f# EEEE       
z   7 HHHHHHHHHHHPPPPPPPPP#ssssssss#SSSSSSSS#AA    yy#fGGGGGfffffll00f# EEEE       
z   8 HHHHHHHHHHHPPPPPPPPP#ssssssss#SSSSSSSS#AA    yy#fffffffffffll00f# EEEE       
z   9 HHHHHHHHHHHPPPPPPPPP#ssssssss#SSSSSSSS#AA    yy#fffffffMMMMll00f#            
z  10 HHHHHHHHHHHPPPPPPPPP#ssssssss#SSSSSSSS#AA    yy#fffffffMMMMll00f#            
z  11 HHHHHHHHHHHPPPPPPPPP#ssssssss#SSSSSSSS#AA    yy#fffffffMMMMll00f#            
z  12 HHHHHHHHHHHPPPPPPPPP#ssssssss#SSSSSSSS#AA    yy#fggggggMMMMll00f#            
z  13 HHHHHHHHHHHPPPPPPPPP#ssssssss#SSSSSSSS#yy    yy#fggggggMMMMll00f#            
z  14 HHHHHHHHHHHPPPPPPPPP#ssssssss SSSSSSSS yy    yy fggggggMMMMll00f#            
z  15   L L L L  PPPPPPPPP#ssssssss SSSSSSSS yy    yy fggggggMMMMll00f#            
z  16            PPPPPPPPP#ssssssss SSSSSSSS yy    yy fggggggMMMMll00f#            
z  17   L L L L  PPPPPPPPP#ssssssss#SSSSSSSS#yy    yy#fggggggMMMMll00f#            
z  18                     #ssssssss#SSSSSSSS#yy    yy#fggggggMMMMll00f#            
z  19   L L L L~~~~~~~~   #ssssssss#SSSSSSSS#yy    yy#fggggggMMMMll00f#            
z  20          ~~~~~~~~   #ssssssss#SSSSSSSS#yy    yy#fggggggMMMMll00f#TTTTTTTTTTT 
z  21          ~~~~~~~~   #ssssssss#SSSSSSSS#yy    yy#QQQQQQQQQMMll00f#TTTTTTTTTTT 
z  22          ~~~~~~~~   #ssssssss#SSSSSSSS#yy    yy#QQQQQQQQQffll00f#TTTTTTTTTTT 
z  23          ~~~~~~~~   #ssssssss#SSSSSSSS#yy    yy#QQQQQQQQQwwll00f#TTTTTTTTTTT 
z  24          ~~~~~~~~   #ssssssss#SSSSSSSS#yy    yy#QQQQQQQQQwwll00f#TTTTTTTTTTT 
z  25          ~~~~~~~~   #ssssssss#SSSSSSSS#yy    yy#QQQQQQQQQwwll00f#TTTTTTTTTTT 
z  26          ~~~~~~~~   #ssssssss#SSSSSSSS#yy    yy#QQQQQQQQQwwll00f#TTTTTTTTTTT 
z  27          ~~~~~~~~   #ssssssss#SSSSSSSS#yy    yy#QQQQQQQQQwwll00f#TTTTTTTTTTT 
z  28          ~~~~~~~~   #ssssssss#SSSSSSSS#yy    yy#QQQQQQQQQffllfff#TTTTTTTTTTT 
z  29          ~~~~~~~~   #ssssssss#SSSSSSSS#yy    yy#fffffffffffllfff#TTTTTTTTTTT 
z  30          ~~~~~~~~   #############################################TTTTTTTTTTT 
z  31          ~~~~~~~~                                                            
z  32                                                                              
P pad court (west apron)  H old hut (Kyle's; old storage retired)  L loader parking (with C4)
~ dripstone lava rows (fuel)  - drone lane  : lane screen / drone rack  # walls
s smelting hall: 12 furnaces on Crafty's network   S storage room (+ a 4th barrel row, stage 3)
y systems bay (old launch bay; corridor x 21-24 kept clear)  A AE2 corner (later)
f foundry floor  G power corner  M Mekanism line + walkway  g pool and gas plants
Q quartz line  w workshop bench  l operator lane  0 stage-0 plinth (factories, stage 6+)
E evaporation tower (outside, stage 4)  T control tower (screens, CommandBlock)
```

| zone | box | what it is for |
|---|---|---|
| **Pad court** | x -9..-1, z 4..17, deck at y 0 | Crafty, Counter, pad 3 (§2) |
| **Smelting hall** | x 1-8 | Crafty's 12 furnaces, and the trunk's way into the building |
| **Storage room** | x 10-17 | Sortnado's store, plus a 4th barrel row (§4) |
| **Systems bay** (the old launch bay) | x 19-26 | AE2 corner x 19-20 z 6-12. The corridor x 21-24 stays clear: it is the drones' and Kyle's way from the big door to the doorways (x 18 and x 27, z 14-16). The drone rack (z 3-4) and the bay panel (19, 2-3, 26-27) stay. |
| **Foundry** | x 28-43 | the Mekanism line and its expansion (§5) |
| **Power corner** | NW plinth x 29-33 z 5-7 | generators and a cube, cabled into the line |
| **Workshop bench** | x 36-38 z 23-27 | machine trials, so the yard bench can go |
| **Quartz line** | x 28-35 z 22-27 | stays as it is |
| **East yard** | x 46-49 z 5-8 | the evaporation tower (Mekanism stage 4) |
| **Control tower** | x 45-55 z 20-30 | screens and dashboard; CommandBlock moves in |
| **Fuel** | x -11..-4, z 19..31 | dripstone row 1 (built) and row 2 (planned) |
| **Loader parking** | x -18..-12, z 15..19 | only with code change C4; until then the loaders park where Crafty's offsets put them |
| **Old hut** | x -20..-10 | stays as Kyle's hut. Its storage and pad are retired. |

---

## 2. The pad court (west apron)

**Why here.** The apron is right against the smelting hall's west wall, so
the cable into the building is one wall block long. Every other site fails
on at least one count:

- **Inside the building:** no sky above a pad. Helpers come straight down
  onto it, and their hover row would sit inside the walls.
- **North:** behind the west half of the back wall, the hill rises 5-15
  blocks within 6 of it.
- **South:** the bank drops away, and the big door's approach (22, 2, 33) is
  every fit job's way in.
- **East:** the dirt bank there would do, but the store is 30 blocks of
  cable away, through the Mekanism bay. The east yard is kept for the
  evaporation tower.

The apron also has these properties:

- **Flat:** the yard is 1 below the floor (top block at y -1), so the deck
  sits at floor level.
- **Same chunk column:** chunk -279, 95, as the old base, which is already
  loaded.
- **Clear of everything else:** the hut, the dripstone row (from z 19) and
  the lane's west gate (x 0, z 1-2).

```
Pad court, top down (y 0-1), x -20..8
   x  -20       -10       0        
      09876543210987654321012345678
z  -1                              
z   0 HHHHHHHHHHH         #########
z   1 HHHHHHHHHHH      L L         
z   2 HHHHHHHHHHH    h h h h       
z   3 HHHHHHoT HH      L L#########
z   4 HHHHHHHbbbbb==....*.#=       
z   5 HHHHHHHHHHH/.=./.L.L#mF      
z   6 HHHHHHHHHHHvPTc^....#=       
z   7 HHHHHHHHHHH/.=./....#mF      
z   8 HHHHHHHHHHH..======+X=       
z   9 HHHHHHHHHHH.PKc.....#mF      
z  10 HHHHHHHHHHH..=....*.#=       
z  11 HHHHHHHHHHH,,=,,,,,,#mF      
z  12 HHHHHHHHHHH,,=,,,,,,#=       
z  13 HHHHHHHHHHH,P3c,,,,,#mF      
z  14 HHHHHHHHHHH,,,,,,,,,#=       
z  15            ,,,,,,,,,#mF      
z  16            ,,,,,,,*,#=       
z  17            ,,,,,,,,,#mF      
z  18                     #=       
z  19               #     #mF      
z  20              #~#    #=       
z  21              #~#    #mF      
z  22              #~#    #=       
z  23              #~#    #mF      
z  24              #~#    #=       
z  25              #~#    #mF      
z  26              #~#    #=       
z  27              #~#    #mF      
z  28              #~#    #=       
z  29              #~#    #        
z  30              #~#    #########
z  31               #              
z  32                              
P pad (drive under it)  T Crafty  K Counter  3 pad 3  c drop chest  ^ in-shaft  v out-shaft
= cable in the deck (y 0) / at the wall (x 0-1, y 1)  + riser (y 1)  X wall cell (Kyle)
b bridge to the old base (stage 2)  . deck stage 1  , deck stage 6  / hazard stripe  * lantern post
h helpers hover (y 13)  L loaders park (both as the code stands)  % yard bench (stage 6 clears it)
H old hut  ~ # dripstone lava row (y 5-10)  F m = smelting hall furnaces, modems, cable
```

**The three lines** (west to east: out-shaft, pad, dispenser, drop chest,
in-shaft; only Crafty's line has shafts):

| line | pad cell (drive under it) | dispenser on its modem | drop chest | shafts | stage |
|---|---|---|---|---|---|
| A: Crafty | -8 1 6 = world -4456 72 1524 | -7 1 6 = -4455 72 1524 (modem -4455 71 1524) | -6 1 6 | out -9 · 6, in -5 · 6 | 1, filled in 5 |
| B: Counter | -8 1 9 = -4456 72 1527 | -7 1 9 = -4455 72 1527 | -6 1 9 | none | 1, filled in 5 |
| C: pad 3 | -8 1 13 = -4456 72 1531 | -7 1 13 = -4455 72 1531 | -6 1 13 | none | 6 |

**How Crafty finds its bearings there.** `survey()` turns until the drop
chest is in front (east), then steps out to south, west and north. It finds
the drive under the west cell and maps:

| what | cell |
|---|---|
| dock | -6 2 6 |
| exit1 | -7 2 6 |
| exit2 | -8 2 6 |
| in-shaft | -5 · 6 |
| out-shaft | -9 · 6 |

These are exactly the cells kept open above. No code change is needed for
this. The drop chest touches neither modem, as `outputIsStorage()` requires.

**Approach lanes.**

- **Helpers** drop straight down x -8 onto whichever pad their load names
  (`padAt`). The pad columns are 3 to 4 blocks apart, and nothing is built
  above them.
- **Miners** (line A only) work at y 2 along z 6: up the in-shaft at x -5,
  over the chest, over Crafty for service, over the pad, down the
  out-shaft at x -9.
- **The rows between** (z 7-8, 10-12) carry only the trunk cable, flush in
  the deck.

**The waiting areas as the code stands (no change):**

- **Helpers** hover at x -5, -3, -1, +1, y 13, z 2 (world -4453..-4447 84
  1520). Slot 3 (DropIt) lands on the smelting hall's roof edge and waits
  there. `goHover` simply stops when it meets the roof, and the next fetch
  rises from there, so it still works.
- **Loaders** park at x -3, -1, +1, +3 and z 5, 3, 1. Four spots are on the
  deck's north edge or the slope, and the x +1 and +3 spots are on the
  hall's roof. That works but it is untidy.
- **With code change C4** they get their own places instead:
  - a hover row at x -9..-3, y 13, z 2 (world -4457..-4451 84 1520);
  - a parking lot at x -18..-12, z 15/17/19 (world -4466..-4460, 1533..1537),
    on flat yard south of the hut.

  `retrofit.py check` confirms neither is over a pad column or a shaft.

**Lights:** lanterns on deck-block posts at (-2, 1, 4), (-2, 1, 10) and
(-2, 1, 16), so nothing spawns on the deck at night (a mob on a pad column
stalls every fetch). **Hazard stripes:** the four deck cells either side of
the two shaft holes.

---

## 3. One network

```
The cable network, top down
   x      -10       0         10        20        30        40   
      43210987654321012345678901234567890123456789012345678901234
z   2               #        #        #        #                #
z   3               #        #        #        #                #
z   4  ===R===      #-       #        #        #                #
z   5        =      #mf      #~~~~~~~~R~~~~~~~~R~~~~~~~~~       #
z   6       dM      #-       #~       #        #        ~       #
z   7        =      #mf      #~       #        #        ~       #
z   8        =======R-       #~       #        #        M~      #
z   9       dM      #mf      #~       #        #         ~      #
z  10        =      #-       #~       #        #         ~      #
z  11               #mf      #~       #        #         ~      #
z  12               #-       #~       #        #         ~      #
z  13               #mf      #~       #        #         ~      #
z  14               #-        ~                          ~       
z  15               #mf       ~                          ~       
z  16               #-        ~                          ~       
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
z  29               #========R-mommo  #        #                #
z  30               #############################################
= new cable, low (y 0-2)  ~ new cable along the top of the rooms (y 7)  R wall cell replaced
M new full modem  d new disk drive  - m f existing cable, modems, furnaces  K storage controller
(the bridge's hut end, x -13..-10 at y 2, comes out once the old chests are empty)
```

Everything ends up on one wired network: the pads, the 12 hall furnaces,
the store and, for a while, the old base. The runs:

| run | cells | joins | stage | by |
|---|---|---|---|---|
| **Trunk** | -7 0 7, -7 0 8, x -6..-1 at 0 8 (in the deck), riser -1 1 8, **wall cell 0 1 8** (world -4448 72 1526) | modems A and B to the hall's cable at 1 1 8 | 1 | swarm; the wall cell is Kyle's |
| **Desk link** | 1..8 1 29 along the hall's south wall, **9 1 29** through the partition | the hall's cable (end at 1 1 28) to desk modem 10 1 29 | 1 | swarm, fit plan `desklink` |
| **Bridge** | yard: -7 0 5, -7 0 4, -8 0 4, -9 0 4 (with the deck); then -9 1 4, -9 2 4, **-10 2 4** (the hut's cobblestone east wall), -11 2 4, -12 2 4, -13 2 4 | old network (modem -13 1 4 under the last cable) to modem A | 2 | swarm (lab), all of it |
| **Pad C link** | -7 0 10 (stage 1), -7 0 11, -7 0 12 | modem B to modem C | 6 | swarm |
| **North line** | up from the west controller's modem (10 6..7 16), north along the top of the west wall (10 7 15..5), east at y 7 along z 5 through **18 7 5** and **27 7 5**, down x 36 to a modem on the line's inbox (36 1 8); along x 37 at y 7 and down to a modem on the outbox (37 1 19) | the store to the Mekanism line's chests | 7 | swarm, fit plan `northline` |

Why these exact cells:

- **Trunk:** the hall's cable cell at 1 1 8 is a cable (odd z are modems,
  either joins). No lab or fit job can reach the wall cell (0, 1, 8). Lab
  `dig` may not take deepslate tiles, and a fit job would have to stand
  outside the building. So it is one block for Kyle.
- **Desk link:** the hall's south-wall row and 9 1 29 are open floor and
  plain stone brick in every plan.
- **North line:** the lantern at 10 7 4 is why it turns east at z 5 and not
  z 4. y 7 is under the upper floor in the storage room and systems bay, and
  above every pipe and tube of the line in the foundry: the line goes no
  higher than y 4, and stubs may rise to y 5-6. The chains at x 35 and the
  station modem at 22 5 3 are missed.

**What sees what once joined:**

- **Sortnado:** with a controller on the network, it keeps only the
  controllers as the store and ignores every other chest, furnace and
  turtle (`sortnado.lua S.discover`). Joining changes nothing for it.
- **Crafty, as written today:** it would take every inventory on the cable
  as storage. That includes the store's **In and Out barrels**, and later
  the **line's inbox and outbox**. It must not, so code change C2 comes
  before the bridge.

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

That is about 192 slots, and the store has 476 free. The small and medium
slots are plenty. Bulk is the tight one: 71 bulk slots in all, and the store
already holds 327 slots' worth. A pile that finds no bulk slot falls back to
medium and small, so nothing is refused, but it sprawls. So, before the
drain:

**Stage 3, the wall raise.** One more row of barrels at y 4 the length of
both side walls. These cells are free: the y 4 row only exists over the
doorway (z 13-17) today. The new barrels touch the barrels below them, so
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

**The haul order.** Nothing is carried by a turtle once the bridge is in.
Sortnado empties the old chests straight into the store over the cable
(code change C5, `drain`). The order:

1. **Junk out first.** Darkstone and kivi (already decided). Marble 743,
   tuff 569, basalt 458, volcanic ash 234, gravel 291 and flint 1,146 are
   **Q4**. If they go, that is 6 fewer bulk slots.
2. **Dead stock.** Everything Crafty never uses, biggest piles first (they
   take the bulk slots): inferium essence, raw redstone blocks, prosperity
   shards, dark gems, fluorite, the exotic raw ores and so on. This is the
   same list the haul duty works from today, so some has already gone.
3. **Crafty's working stock last.** That is what `HAUL_NEVER` holds back:
   coal, buckets, redstone, ingots, logs, planks, glass, sand, CC, AP and
   Mekanism parts, Sophisticated parts and diamonds. It moves once C2 lets
   Crafty pull from the store. Until then Crafty keeps finding it where it
   always has.
4. **Watch Sortnado's screen line.** "N waiting: the store is full" means
   stop and raise more barrels.

**The haul duty** (`haul Crafty on=1`, helpers carrying 12 stacks) is turned
**off** when the bridge goes in. Its job is done by the drain, and with the
store on Crafty's network it would only carry the store into itself.

**The empty chests** come out in stage 6 (chests, the 2 furnaces, modems,
cables, the old drive) and go back into the store as items.

---

## 5. The other zones

**Smelting hall (x 1-8).** The 12 furnaces at x 2 become Crafty's on the
day of the bridge, because their cable is the trunk's way in. Each modem at
x 1 (world -4447 72, z 1523..1545 odd) must be switched on once by a player
to show its furnace. Crafty's `network` list in the status says which are
(`minecraft:furnace_N`). Later these can give way to Mekanism smelting
factories. Nothing else is planned in the hall: x 3-8 stays open floor.

**Systems bay and the AE2 corner (later, after the meteorite trip).**

- **Where:** x 19-20, y 1-3, z 6-12, against the partition with the
  storage room, clear of the rack (z 3-4) and the doorway (z 14-16). It
  holds the ME controller, drives, energy acceptor and ME Bridge.
- **Cabling:** the north line passes overhead at (19-20, 7, 5), so the
  bridge's CC modem drops from there. The AE energy comes from the power
  corner: a universal cable at y 6 along z 5, through (27, 6, 5). That run
  is not in `retrofit.py` yet; it is drawn when the AE2 stage is due.
- **Storage buses** must face the controllers. The west one is reached from
  (10, 6, 15), above it. The east one depends on **Q2**.
- **Desk and screen:** both stay as they are (`docs/ae2-plan.md` §3).

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
  Stages 3-5 go in as that tool prints them. Nothing here moves.
- **Power corner** (NW plinth x 29-33 z 5-7, y 1):
  - generators: two more heat generators, a gas-burning generator on the
    separator's spare hydrogen, and wind generators on the roof later;
  - storage: an advanced energy cube;
  - feed: the corner's own cable runs over its machines at y 2, as on the
    line. From its end at (34, 2, 6) a universal cable runs along x 35 to
    (36, 2, 10), joining the line's own cable at 36 2 11.

  That is 7 cables, besides the corner's own. The separator (stage 3) is the big draw, so this lands
  with or right after stage 3.
- **Line link** (stage 7). These are CC modems, not Mekanism logistics:
  - one at 36 1 8, touching the inbox's north face;
  - one at 37 1 19, touching the outbox's east face;
  - both on the north line.

  With code change C6, Crafty fills the inbox with raw ore from the store
  and empties the outbox into it, with no turtle and no Logistical Sorter
  pulling from the controller. This is the mekanism plan's stage 6 storage
  link, done with cable.
- **Evaporation tower** (stage 4), in the east yard:
  - footprint: 4 × 4 at x 46-49 z 5-8, on a deck at y 0;
  - height: 4 to start (about 48 blocks, a controller and 2 valves). It is
    in the open, so it can be raised to 18 later.
  - brine route: out of a valve at 46 3 7, up the outside at x 45 to y 9,
    in through **44 9 7** (stone brick between the windows), then west at
    y 9 along z 7 and down x 34 to (34, 9, 16) over the gas plants.
  - why y 9: it is above everything in the bay. The line reaches y 4 and
    the CC cable y 7, the roof starts at y 14, and the chains at x 35 hang
    at z 6, not z 7.

  The plants' own layout stays a stage-4 job, as the mekanism plan says.
- **Stage 0 plinth** (x 41-42): carries on until the line is proven
  (mekanism plan stage 6). Then the chamber and smelter there become the
  first factory upgrades, and the plinth takes a bank of factories. The
  infuser stays: it is the source of steel and circuits.
- **Workshop bench** (x 36-38 z 23-27): open floor in every plan, beside the
  quartz line's casing spot (35 1 26). Machine trials happen here instead
  of on the yard bench.

**Screens and dashboard.** The plan is `docs/screens.md` as written:

- the map wall and touch panel in the tower;
- the rack board and bay panel in the systems bay;
- the gate lights;
- the storage screen.

The retrofit only changes the order. The stations are bootstrapped on pad A
after the move (stage 9). CommandBlock (the controller computer at hut
-13 0 9, with its Chat Box and Player Detector) is carried into the tower by
Kyle: computer 50 17 28, chat box 50 18 28, detector 49 17 28. The tower
has no way in for a turtle.

**Fuel.**

- **Row 1** (11 units, built): stays as it is.
- **Row 2:** a second dripstone row 4 blocks west, at world x -4458, z
  1538..1548 (building x -11..-9). It is clear of the parking lot by one
  block, and its rounds stand at x -9. `python3 tools/retrofit.py ops lava2`
  prints the build. It needs 11 lava buckets to seed, so it waits until
  row 1 has filled the stock.
- **Kyle's hut cauldrons:** the hut lava round goes down the old pad's roof
  hole. **Q5:** keep that hole open for it, or drop the hut round once
  row 2 runs.

---

## 6. Code to write first (not part of this document's change)

| id | where | what | needed before |
|---|---|---|---|
| **C1** | `swarm.lua` (+ each role) | **`rebase` order.** Every drone takes the factory's new `base` (from the order, which the controller fills from Crafty's last status) and rewrites `.base`. Miners also drop `dock/exit1/exit2` from their state. Loaders drop their remembered base. Then reboot. Today `.base` is written once when a drone is drafted, so after the move every helper would fly to the old pad. | stage 5 |
| **C2** | `factory.lua discover()` | **Crafty's stores are an allow-list.** Two rules: (1) never the store's In or Out barrel (an order `stores Crafty skip=…`, or Sortnado broadcasts its `cfg.inbox/outbox`); (2) never a chest named as the line's inbox or outbox. Put away into the store's **In barrel**, so Sortnado files it in its section. Pull from the controllers and the old chests. `storageSpace()` counts the controllers' free slots. | stage 2 (the bridge) |
| **C3** | `factory.lua` counter mode | **Counter finds its chest** (`findDropChest()`) before `survey()`: `turnTo` with `facing` unset errors. **Counter reports role `counter`**, not `factory`. Today the controller (`forge`) and loaders may take Counter's base for Crafty's. | stage 5 |
| **C4** | `helper.lua hover()`, `loader.lua parkSpot()`, factory | **Hover row and parking lot handed out by the factory** (`base.hover`, `base.park`), falling back to today's offsets. | optional; stage 6 |
| **C5** | `sortnado.lua` | **`drain from=<names>` order.** Treat the named old chests as extra In chests until they are empty, biggest piles first, with junk (a list) sent to the trash rather than filed. Report what is left. | stage 4 |
| **C6** | `factory.lua` | **Line duty over the cable.** Push raw ore from the store into the line's inbox (while power holds) and pull the outbox into the store. This is the mekanism plan's "line operator duty". | stage 7 |
| **C7** | `factory.lua` | **Pad 3:** split helpers' loads three ways (or give each load to the least busy pad) instead of odd and even. | stage 6 |
| **C8** | `factory.lua plotOrigin()`, miners | **Keep the plot grid where it is.** Plots are laid out around Crafty (`base.f`), so moving Crafty 6 east and 3 south moves every plot. Save the old `base.f` as `plots.origin` and lay plots out from that. Miners' shaft-column check uses `exit1`, so it needs the same origin. | stage 5 (only matters once mining resumes) |

The lab, fit, haul and foundry orders already exist and need no change for
anything below.

---

## 7. The stages

Throughout: **storage stays usable at every step**. `$get` and the storage
screen run off the desk and never stop. Crafty keeps its old chests until
they are empty, and sees the store from stage 2 on.

### Stage 1: the pad court (north half) and the trunk

**Goal:** the apron deck z 4..10, pads A and B ready but empty, and the
hall and store on one network. The old base carries on untouched.

**Drones:**
- Deck and pad hardware (an idle helper, e.g. OnRepeat):
  `tools/order.py lab OnRepeat clear=1 "ops=$(python3 tools/retrofit.py ops deck)"`
  - One `fetch`, one `goto` to (-9, 1, 4).
  - Along each row, standing at y 1: `dig`, `fwd`, `digDown` (grass and
    dirt only), `placeDown`, and `expect|down|…` after every block.
  - Then the two drop chests, the riser cable and the lantern posts, each
    by `goto`, `placeDown`, `expect`.
  - Ends `inv;home;handin|`. It is 395 steps.
  - **Before it starts:** no drone may stand on the apron at y 1. The
    lab's `dig` takes any `computercraft:` block, a parked turtle
    included. Loaders park at z ≤ 2 and helpers hover at y 13 today, so the
    apron is normally clear.
- Desk link (HopTo, who knows the store room):
  1. `python3 tools/retrofit.py fit desklink > blueprints/factory_desklink.txt`
     (commit it).
  2. `tools/order.py fit HopTo ox=-4448 oy=71 oz=1518 plan=factory_desklink shell=factory_asfit3`
  3. HopTo takes out the stone brick at 9 1 29 from the hall side, then lays
     8 cables from above.

**Kyle:**
- **Wall cell:** break the deepslate tile at world **-4448 72 1526** (from
  outside, beside the riser cable) and put a cable in its place.
- **Hall modems:** right-click each modem at x -4447 y 72, z 1523..1545
  (odd) whose ring is not red. That is 12 at most, and Crafty's status shows
  which.
- Modems A and B are clicked in stage 5, once the turtles stand on them.

**Bill:**

| item | count | from |
|---|---|---|
| CC cable | 24 | 16 stone, 4 redstone |
| polished deepslate | 42 | 44 cobbled deepslate |
| wired modem (full) | 2 | 16 stone, 2 redstone |
| disk drive | 2 | 14 stone, 4 redstone; recipe unverified |
| chest | 2 | 16 planks |
| lantern | 2 | 16 iron nuggets, 2 torches |
| striped yellow concrete | 4 | Kyle's stock |

All but the concrete are in Crafty's recipes and stock.

**Check:**
- Sortnado's status still says `sorting` with 803 slots.
- From the desk, `peripheral.getNames()` lists the 12 furnaces once
  clicked.
- The lab output has no `stopped here`.

**Storage:** unaffected.

### Stage 2: the bridge (old network joined)

**Needs C2 on Crafty first** (reboot Crafty onto it).

**Drones:**
- `tools/order.py lab OnRepeat clear=1 "ops=$(python3 tools/retrofit.py ops bridge)"`
- Inside the hut: down the old pad's roof hole to the row over Crafty
  (-13 2 3). Facing south, it puts a cable at -13 2 4 on top of the old
  modem, then at -12 2 4 and -11 2 4. Each is checked with `inspect` and
  `expect`, so it stops if anything is there.
- Outside: back out the roof hole, then `goto` -9 2 4. It puts a cable down
  at -9 1 4, `dig`s the cobblestone at -10 2 4 and puts a cable in its
  place, then one more at -9 2 4.
- Then `tools/order.py haul Crafty on=0`.

**Kyle:** nothing. Optionally, the three cables inside the hut by hand, if
Counter or anything new stands there (**Q1**).

**Bill:** 6 cables.

**Check:**
- Crafty's `network` now lists `sophisticatedstorage:controller_*` and
  the hall furnaces. The new drives only show once modems A and B are on
  (stage 5).
- Its `storage` grows by the store's slots.
- A helper `fetch` of something only the store holds succeeds.

**Storage:** both stores usable. Crafty now smelts on 14 furnaces.

### Stage 3: the store wall raise

**Drones (HopTo):**
1. `python3 tools/retrofit.py fit walls > blueprints/factory_walls.txt`
   (commit it).
2. `tools/order.py fit HopTo ox=-4448 oy=71 oz=1518 plan=factory_walls shell=factory_asfit3`
3. HopTo places 38 barrels, each from in front (stand east for the west
   wall, west for the east wall), so each faces into the room.

**Kyle:** nothing.

**Bill:**

| item | count | from |
|---|---|---|
| limited barrel I | 20 | about 150 planks, 20 levers |
| limited barrel IV | 18 | about 108 planks, 18 levers |
| in all | 38 | **about 70 logs** of one wood per craft, and 38 cobblestone for the levers |

Crafty keeps 160 logs of each wood back. **Q6:** enough logs?

**Check:** Sortnado's survey shows 20 more bulk slots and 72 more medium
slots than before.

**Storage:** usable throughout. It grows as each barrel goes in.

### Stage 4: drain the old chests

**Needs C5.** One order, no turtle:

`tools/order.py drain Sortnado from=minecraft:chest_0,…` (the 28 names from
Crafty's `network`)

It runs in the order of §4. Junk goes per **Q4**.

**Kyle:** nothing.

**Bill:** none.

**Check:**
- Sortnado's drain report lists every old chest as empty.
- Sortnado has nothing `waiting`.

**Storage:** usable throughout. Items are in one place or the other, and
both are on the cable.

### Stage 5: move Crafty and Counter; rebase

**Needs C1 and C3 (and C8 before mining resumes).**

**Before:** pause anything that will fetch (`stop` the helpers, or wait
for idle).

**Kyle, Counter first:**
1. Break Counter. A player-broken turtle keeps its label, ID and files.
2. Set it down on modem B: world **-4455 72 1527**.
3. Right-click modem B (world -4455 71 1527) so the ring goes red.

Crafty takes back the odd loads within 150 s of hearing no
`counter_alive`, so nothing waits.

**Kyle, then Crafty:**
1. Make sure its inventory is empty: it stashes everything between jobs.
2. Take the floppy out of the old drive (world -4462 71 1521) and put it
   in drive A (world -4456 71 1524).
3. Break Crafty and set it on modem A: world **-4455 72 1524**.
4. Right-click modem A.

Crafty re-surveys by itself: its GPS spot no longer matches `.base`, so it
finds its chest east and the drive west. That rewrites the floppy and
reports the new `base`.

**Drones:** `tools/order.py rebase all`, then `resume`. Every helper,
loader, builder and miner takes the new base and reboots.

**Check:**
- Crafty's `base` is: f -4455 72 1524, pad -4456 72 1524, dock -4454 73 1524.
- Helpers hover at world z 1520.
- A lab `fetch` comes down x -4456.
- Counter answers odd loads at -4456 72 1527.

**Storage:** about 5 minutes with no dispenser, while Crafty is carried.
The store and `$get` are unaffected.

### Stage 6: retire the old base; the yard bench out; pad 3

**Old base:**
- The 28 empty chests, the 2 furnaces and the old drive are dug and handed
  in. There are two ways:
  - **Kyle** breaks them (about 2 minutes, recommended: the hut is
    cramped);
  - **the swarm**, from the old in-shaft (x -11) and out-shaft (x -15),
    which reach the chest stacks at z 3, with `dig` and `handin` (chests,
    modems, cable and drives are on the lab's dig list).
- Then the bridge's hut end comes out with `ops unbridge`. In through the
  roof hole, it `dig`s the three cables at -13..-11 2 4. Outside, it takes
  up the cables at -9 2 4 and -9 1 4, and puts a cobblestone back in the
  hut wall at -10 2 4 (from outside, facing west). The yard part stays: it
  is inside the deck.

**Yard bench:**
1. `foundry DropIt job=move_infuser` (it puts the infuser at 41 1 15), if
   not already done.
2. **Kyle** takes the Inventory Manager at world -4453 74 1532 (it holds a
   memory card: **Q3**).
3. `ops bench` digs the cobblestone layer by layer.

**Pad 3:**
- `ops padc` lays the south deck (z 11..17): pad C's drive, modem, chest,
  the cable from B to C and the last lantern.
- With C7: a third dispenser on modem C. Counter mode never crafts (the
  crafting check comes after the counter branch in `tryBuild()`), so any
  spare turtle will do, such as one of the miners parked while storage was
  full. It is given counter mode and a label C7 recognises; today any label
  starting "counter" serves the odd ids, so C7 decides the split.
- Kyle right-clicks modem C (world -4455 71 1531).

**Bill:**

| item | count |
|---|---|
| polished deepslate | 60 |
| cable | 2 |
| drive | 1 |
| modem | 1 |
| chest | 1 |
| lantern | 1 |
| dispenser | 1 spare turtle (when C7 is in) |

**Storage:** unaffected.

### Stage 7: the line link

**Needs C6** before the two modems are switched on. Until then they stay
off, so Crafty cannot take the inbox for storage.

**Drones (HopTo):**
1. `python3 tools/retrofit.py fit northline > blueprints/factory_northline.txt`
2. `fit HopTo … plan=factory_northline shell=factory_asfit3`
3. The order is worked out so every stand is free when its turn comes:
   - in the foundry, everything from above, starting at the two modems;
   - the two partition cells (27 7 5, 18 7 5) from the west;
   - the ceiling runs in the systems bay and storage room from below
     (y 6);
   - the last two cells beside the west controller's modem from the east.

   That is 66 jobs.

**Kyle:** right-click the two line modems: world -4412 72 1526 and
-4411 72 1537.

**Bill:**

| item | count | from |
|---|---|---|
| cable | 64 | 44 stone, 11 redstone |
| wired modem (full) | 2 | |

**Check:** Crafty's network lists the two line chests under the names C2
skips. 12 raw iron from the store arrive as ingots in the store.

### Stage 8: Mekanism expansion (alongside mekline stages 3-5)

**Drones** (Sticky, DropIt), lab runs in the same style as
`tools/mekline.py`:
- the power corner's generators and cube on the NW plinth;
- the 7-cable power link;
- for stage 4, the evaporation tower deck (16), the tower itself and the
  27-pipe brine run.

Inside, the brine run is a fit plan, for its one wall cell 44 9 7. Its
outside part (x 45) and the tower are `goto`/`placeDown` lab runs. Two
things are drawn when stage 4 is due, along with the plants: the tower's
water in (its own pump over a 2 × 2 pool on the east side, or a branch of
the line's water main), and that pump's power.

**Kyle:** nothing expected. The tower forms by itself (mekanism plan). If a
valve will not push brine into the pipe on its own, setting it needs a
Configurator in a player's hand (unverified).

**Bill:**

| item | count | from |
|---|---|---|
| universal cable | 7 | 2 steel, 1 redstone |
| mechanical pipe | 27 | 8 steel, 4 buckets |
| polished deepslate | 16 | |
| power corner machines | 2 heat generators, 1 advanced cube, 1 gas-burning generator | |
| evaporation tower | about 48 blocks, a controller, 2 valves | stage 4 bill in the mekanism plan |

### Stage 9: screens and the control tower

**Drones:** the bootstrap and fit steps of `docs/screens.md`, unchanged,
with pad A as the pad.

**Kyle:** carry CommandBlock, the Chat Box and the Player Detector from the
hut into the tower top floor (cells in §5).

**Bill:** as in screens.md: 6 computers, 6 ender modems (48 gold, 6 eyes).

### Stage 10: AE2 corner (after the meteorite)

As `docs/ae2-plan.md` stages C-E, in the systems bay corner (§5).

**Kyle:** the meteorite trip, and the terminals he uses.

---

## 8. Order of work at a glance

| # | stage | code first | Kyle | store usable | old base |
|---|---|---|---|---|---|
| 1 | pad court north, trunk, desk link | none | 1 wall cell, hall modems | yes | running |
| 2 | bridge | C2 | none | yes, both | running, on the cable |
| 3 | wall raise | none | none | yes | running |
| 4 | drain | C5 | none (Q4) | yes | emptying |
| 5 | move Crafty and Counter, rebase | C1, C3, C8 | carry 2 turtles, floppy, 2 modems | yes; 5 min without a dispenser | pad unused |
| 6 | retire old base, bench out, pad 3 | C7 for pad 3 | break chests (or swarm), the manager, modem C | yes | gone |
| 7 | line link | C6 | 2 modems | yes | |
| 8 | Mekanism expansion | none new | none | yes | |
| 9 | screens | none new | carry CommandBlock | yes | |
| 10 | AE2 | Sortnado's ME backend (branch `ae2`) | meteorite, terminals | yes | |

Stages 1 and 3 can run side by side (different helpers), and so can stage 8
with anything.

---

## 9. Bill of materials

| item | st 1 | st 2 | st 3 | st 6 | st 7 | st 8 | total |
|---|---|---|---|---|---|---|---|
| CC cable | 24 | 6 | | 2 | 64 | | 96 |
| wired modem (full) | 2 | | | 1 | 2 | | 5 |
| disk drive | 2 | | | 1 | | | 3 |
| polished deepslate | 42 | | | 60 | | 16 | 118 |
| chest | 2 | | | 1 | | | 3 |
| lantern | 2 | | | 1 | | | 3 |
| striped yellow concrete | 4 | | | | | | 4 |
| limited barrel I / IV | | | 20 / 18 | | | | 38 |
| universal cable | | | | | | 7 | 7 |
| mechanical pipe | | | | | | 27 | 27 |

Raw, roughly:

| raw | amount | for |
|---|---|---|
| stone | 130 | cables, modems, drives |
| redstone | 30 | cables, modems, drives, universal cable |
| cobbled deepslate | 120 | polished deepslate |
| logs | 80 | 38 barrels, 3 chests, torches |
| cobblestone | 40 | levers |
| iron nuggets | 24 | 3 lanterns |
| steel ingots | 10 | universal cable, pipes |
| buckets | 4 | pipes |

Everything but the logs is well covered by stock: stone 1,576, cobbled
deepslate 2,941, redstone 1,621 plus blocks. **Q6** covers the logs.

---

## 10. Not proven, and what to watch

- **Hall modems:** that the 12 hall modems were never switched on is a
  guess. Check Crafty's `network` after stage 2.
- **Modems switched on before their turtle arrives:** a full modem shares
  what is around it once on. That it picks up a turtle placed later is
  expected but not seen. Click again after placing if the turtle is not in
  `getNamesRemote()`.
- **Breaking turtles:** a turtle broken by a player keeps its label and
  files (CC behaviour). The plan does not rely on a turtle digging Crafty.
- **The yard and the hut:** the yard's height (top block at y -1) and the
  hut's interior come from scans 1-2 days old. Every lab step that places
  stops on failure (`stop` on a failed place, `expect` after it), so a
  surprise halts the run instead of building wrong.
- **Brine out of the evaporation tower:** it is unverified that a valve
  pushes brine into the pipe by itself. Mekanism pipes do not pull without a
  Configurator.
- **Wall block for Kyle:** `0 1 8` is the only wall block in the plan that
  the swarm cannot do. The fit plan's stands are all inside the building,
  and it cannot path outside it safely.
- **Chunk loading:** the factory spans chunks x -278..-275, z 94..96, the
  pad court and parking are in -280..-279, and the tower's east edge and
  the evaporation tower reach -275. All of them must be force-loaded
  (**Q7**).

---

## 11. Open questions for Kyle

1. **Counter.** Where exactly is it and its pad 2 at the old base? Is it
   actually serving? The last status shows id 38 as role `miner`,
   "woke up" at -4461 73 1523, and its pad needs open sky that the hut roof
   there does not have.
2. **The east storage controller.** Which cell did you put it in? The AE2
   storage buses and the "two halves" picture depend on it.
3. **The Inventory Manager on the yard bench** (-4453 74 1532). Whose
   memory card is in it, and should it move to the desk (on the cable, so
   Sortnado can use it for `$get`) or go?
4. **Junk.** Darkstone and kivi go. What about marble (743), tuff (569),
   basalt (458), volcanic ash (234), gravel (291) and flint (1,146)?
5. **The hut lava cauldrons.** Keep the old pad's roof hole open for those
   rounds, or retire them once dripstone row 2 runs?
6. **Logs.** About 80 are needed for the 38 barrels. Are there enough of one
   wood, or will you bring some?
7. **Chunks.** Are chunks x -280..-275, z 94..96 all force-loaded (FTB
   Chunks)?
8. **The pad court's look.** Is a plain polished deepslate apron with
   hazard stripes by the two shaft holes and three lanterns fine, or do you
   want low walls or railings round it? A roof is not possible: the pads
   need open sky.
9. **Stage 5 timing.** It needs you on site for about 10 minutes: Counter,
   the floppy, Crafty, two modem clicks. When suits?
