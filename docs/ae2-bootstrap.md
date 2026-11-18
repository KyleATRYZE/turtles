# AE2 bootstrap: from the meteorite haul to a network the swarm can use

The step-by-step chain from what came back from the meteorite to:

- **(a)** a working ME network: controller, drive, cells, terminal;
- **(b)** autocrafting: a crafting CPU, molecular assemblers, a pattern provider;
- **(c)** the ME Bridge, so our computers can craft and fetch.

The swarm does as much of it as it can. It follows on from docs/ae2-plan.md
(stages A and B are done).

**Tools**

- `tools/certusfarm.py` prints the farm's map, Kyle's placing list and every
  lab-ops string below.
- `docs/certus-build.html` is the voxel build guide for the farm.
- The factory recipes are in `factory.lua`, checked by `test/ae2network.py`.
- The farm and the bench are checked by `test/certusfarm.py`. That test runs
  the real helper through the bench, harvest and fluix steps.

**Sources**

AE2 is checked against its own code and data, branch `1.21.1` at commit
6af35c6:

- `src/generated/resources/data/ae2/recipe`, `loot_table` and `tags`;
- `BuddingCertusQuartzBlock`, `CertusQuartzClusterBlock`,
  `InscriberBlockEntity`, `ChargerBlockEntity`,
  `GrowthAcceleratorBlockEntity`, `TransformLogic`, `ItemEntityMixin`,
  `InitCapabilityProviders` and `AEConfig`;
- its guidebook: certus-growth, budding_certus, growth_accelerator, charger,
  inscriber and energy.

Advanced Peripherals is checked on `dev/0.8-1.21.1` at 413b35c: `me_bridge`
and `peripheral_casing` in its generated recipes, and `MEBridgePeripheral`.
For how a turtle digs, CC:Tweaked `mc-1.21.x` `TurtleTool.java`.

Anything not read in those is marked **(unverified)**.

## 1. What we have

| item | count | notes |
|---|---|---|
| Inscriber presses (silicon, logic, calculation, engineering) | 2 of each | one set goes in the inscribers; the other is spare. An inscriber can copy a press with an iron block. |
| Sky stone block | 54 | smelt it for the controller's smooth sky stone (factory recipe) |
| Flawed budding certus | 9 | **the farm** |
| Chipped / damaged budding certus | 2 / 2 | spares; they also fill empty slots after a renewal |
| Certus quartz block | 5 | crafts back into 4 crystals each (AE2 `deconstruction_certus_quartz_block`). It is also renewal stock (§3) |
| Quartz cluster (item), a few buds | 1 | place the cluster on any block and break it with a pickaxe: 4 crystals. A bud gives 1 dust |
| Charger + crank | 1 | |
| Nether quartz | ~82 | fluix and annihilation cores need about 28 (§4) |
| Diamonds, gold, iron, copper, redstone | plenty | |
| **Glowstone dust** | **?** | **Needed:** 2 for every 3 terminal panels and 1 for each blank pattern. That is about 10 in all. None is known to be in stock. |

## 2. How the AE2 mechanics work (checked)

**Budding certus** (`BuddingCertusQuartzBlock`):

- On each random tick there is a 1 in 5 chance that it picks one of its six
  faces at random and grows there. Air (or a water source) becomes a small
  bud; then a medium bud, a large bud and a full cluster. The bud has to face
  the same way, so **4 growth steps make a cluster**.
- **Every growth step** on a flawed, chipped or damaged block has a **1 in 12**
  chance of dropping it one tier: flawed → chipped → damaged → plain
  `ae2:quartz_block`. A flawless block never decays.
- So a tier lasts **12 steps on average (3 clusters)**. A flawed block gives
  about 36 steps (9 clusters, 36 crystals) before it is a plain quartz block.
- A face that holds a full cluster stops growing, and a stopped face does not
  wear the block down. Clusters left unharvested waste nothing, but buds still
  growing when the block dies are lost.

**Breaking a block** (loot tables):

- A budding block broken without Silk Touch drops the next tier down. Flawed
  drops chipped; damaged drops a plain quartz block.
- A full **`ae2:quartz_cluster` drops 4 certus crystals** to any tool without
  Silk Touch, more with Fortune.
- A small, medium or large bud drops 1 certus dust.

**A turtle's pickaxe digs as a player holding that pickaxe.** CC's
`TurtleTool.dig` breaks the block through `gameMode.destroyBlock` with the
tool in hand, and a plain diamond pickaxe has no Silk Touch. So a turtle gets
4 crystals per cluster.

**Renewal** (transform recipes, in water):

| thrown into water together with 1 charged certus | becomes |
|---|---|
| plain quartz block | damaged budding |
| damaged | chipped |
| chipped | flawed |

A dead block plus 3 charged crystals makes a flawed block again. A flawless
block cannot be made.

**Growth rate.** At the default `randomTickSpeed` of 3, a block gets a random
tick about every 68 s. That is about 10.5 growth tries an hour, spread over
six faces, so **about 1.76 steps an hour per open face**.

**Growth accelerator:**

- Every 10 ticks it gives each of its six neighbours a random tick, if the
  neighbour is in `c:budding_blocks`. The guide puts that at "~90x" a
  block's natural rate.
- Power: 8 AE/t (16 FE/t), taken only through its two ends. The guide calls
  them the top and bottom, marked by pink greebles; in the code they are the
  front and back.
- One accelerator speeds up the budding blocks on both of its sides.

**Silicon.** Certus dust smelted in a furnace (or a blast furnace) gives
`ae2:silicon`, the only item in `c:silicon` in AE2's data. The pack may add
others **(unverified)**.

**Certus dust** comes from a certus crystal (or a charged one) in an
inscriber with no press. Fluix dust comes from a fluix crystal the same way.

**Fluix crystal** (transform recipe `fluix_crystals`): 1 charged certus, 1
redstone and 1 nether quartz in water make **2 fluix**. In `TransformLogic`
and `ItemEntityMixin`:

- once the charged crystal has been in a water block for 3 s, it makes one
  set per tick out of whatever lies within a block of it;
- a stack thrown in together turns over in a few seconds;
- flowing water counts too.

**Quartz glass:** 5 certus dust and 4 glass make 4 quartz glass. The pattern
is `DGD / GDG / DGD`.

**Charger** (`ChargerBlockEntity`):

- It holds **one item at a time**. Items go in and out from any side, and
  only the charged result can be taken out.
- Each crystal takes its full 1,600 AE buffer (3,200 FE) and then has a 1 in
  5 chance every 10 ticks of being done: about 2.5 s each once powered.
- **Power goes in on any side except its front.** The guide's "top or
  bottom" is the default way round.
- It takes FE directly: AE2 registers an FE energy capability for every
  powered block entity.

**Inscriber** (`InscriberBlockEntity`):

- Slots: top, bottom, middle input, output.
- Unless it is set to separate sides, **every side reaches the same combined
  inventory**:
  - a filter sends each item to the slot a recipe wants (a press to the top,
    the material to the middle);
  - automation may take **only from the output**, so the presses stay put;
  - so a turtle can `dropDown` into it from above and `suckDown` the result.
- 116 ticks (5.8 s) an item with no speed card, about 20 AE/t while working.
- It takes FE on every side except its front.
- With the separate-sides setting, each side reaches only its own slot
  (guide).

**ME Controller.** It takes FE directly (guide energy.md: "Energy can be
converted by energy acceptors and controllers"). The **energy acceptor is
optional**; it costs 5 crystals for its quartz glass.

**ME Bridge** (AP 0.8):

- Recipe `FIF / IAI / FIF`: 4 fluix blocks, 4 ME interfaces and a peripheral
  casing.
- The casing is `IBI / BRB / IBI`: iron, iron bars and a redstone block.
- Its peripheral type is `me_bridge`. It has `getItems`, `craftItem`,
  `getCraftingTask`, `getCraftingCPUs` and the rest (docs/ae2-plan.md §3).

## 3. The certus farm (a module; placed in foundry-v2's certus zone)

`python3 tools/certusfarm.py map | kyle`, build guide `docs/certus-build.html`.

**Where.** `docs/foundry-v2.md` puts the certus farm at **x 28-34, z 6-13** of
the foundry hall. The farm is a module: `farm=x,y,z,back` moves it, and the
default is that zone.

- Corridors: x 28 and x 32.
- Budding columns: x 29 and x 31.
- Pillars: x 30, at z 7 and 10.
- Basin: 30 0 13.
- The way in is from the north walkway (z 5), by the hatch, as v2 says.

`test/certusfarm.py` checks it against the building and its fit-outs. The
only cell in the way is the stand over the basin, which falls in the old
plan's pool; v2 drops the pool.

v2 drew the farm differently: 9 budding blocks on a flat 3 × 3 grid at
spacing 2, with accelerators beside them. That layout shares growth cells and
covers faces. This one gives every block its own cells and puts the
accelerators where the faces are already covered.

**Shape.** Two stone-brick **pillars**, each 7 high, at the two rows (z 7,
z 10). The budding blocks sit against the pillars on both sides, in three
tiers (y 1, 4, 7). That makes **12 slots**: Kyle's 9 flawed blocks fill
tiers 1 and 2 and one tier-3 slot, and 3 slots wait for renewed blocks.

- Each block keeps its open faces (its back is the pillar; tier 1's bottom is
  the floor). It has 4 or 5 open faces, **41 in all**.
- No two blocks share a growth cell.
- The drone works from the corridors. It steps into the cells between the
  rows and never stands next to a budding block, so nothing grows where it
  stands.

**What Kyle places** (by hand; a budding block broken without Silk Touch
drops a tier):

1. The 14 stone bricks of the two pillars: world -4418 72..78, at z 1525 and
   z 1528.
2. The 9 flawed budding blocks, bottom tier first. Their cells are:
   - tier 1: -4419 72 1525, -4419 72 1528, -4417 72 1525, -4417 72 1528;
   - tier 2: the same x and z at y 75;
   - tier 3: -4419 78 1525.
3. The basin: dig the floor block at -4418 71 1531 and pour in a water
   bucket.

**Harvest** (`harvest`, 248 steps):

- The drone fetches coal, comes in by the walkway and works along the
  primary corridor in three passes (y 2-3, 5-6, 8). It goes across the end
  row (z 12) and does the mirrored side the same way.
- Every growth cell is reached from a stand beside it, with
  `pick|ae2:quartz_cluster`, `pickUp` or `pickDown`. **`pick` is a new lab
  verb.** It digs only a block of exactly that name and never a block with
  "budding" in its name; anything else is left and the steps go on.
- Buds are left to grow.
- The crystals are handed in at the end.

**How long:**

| | rate (randomTickSpeed 3) |
|---|---|
| fresh farm | 41 faces × 1.76 = about 72 steps an hour, **about 18 clusters (72 crystals) an hour** |
| first harvest | **about 3 hours after placing**: 77% of faces hold a full cluster, about 120 crystals |
| a flawed block dies (to a plain quartz block) | after about 4-5 hours |
| the 9 blocks together, before renewal | about 320 crystals |

**Renewal** (`survey`, then `renew SLOTS`):

- `survey` geo-scans the farm. A slot that reads `quartz_block` instead of
  `..._budding_quartz` is dead.
- `renew` digs each dead block from its out cell, charges 3 crystals per
  block, throws block and crystals into the basin, and puts the flawed block
  back.
- It costs 3 crystals per block; the block then yields about 36 more.
- The chipped and damaged spares can go in the empty slots, by hand or by
  `renew`, after the same water treatment.

**Growth accelerators (later, worth it):**

- Swap the pillar brick at each tier (30 1/4/7 7 and 30 1/4/7 10: six
  accelerators, 33 crystals and 15 nether quartz) for an accelerator. Each
  one speeds up the blocks on both of its sides.
- The bricks between them become Mekanism universal cable, fed from under
  the floor.
- The accelerators must stand with their pink ends up and down.
- The farm then grows about 90 times faster. Harvest frequency and renewal
  (3 charged crystals per 36 steps) become the limit, so do it once the
  network makes the crystals' uses automatic.

## 4. The certus budget

The costs are in certus crystals. Charged crystals count as crystals, and so
does dust: one crystal makes one dust. Intermediate costs:

- dust or silicon: 1;
- a printed silicon: 1;
- processors: logic 1 (+ gold), calculation 2, engineering 1 (+ diamond);
- fluix crystal: ½ (+ ½ nether quartz, ½ redstone); fluix dust: ½;
- quartz glass: 1¼;
- glass cable: ½ (+ ¼ NQ);
- annihilation core: ¾ (+ ¾ NQ); formation core: 1¼ (+ ¼ NQ);
- ME interface or pattern provider: 2 (+ 1 NQ).

| step | parts | crystals | nether quartz | glowstone |
|---|---|---|---|---|
| **(a) network** | controller 3 · drive 3 · 2 × 1k item cell 15 · crafting terminal 6¼ · 16 glass cable 8 · 2 storage buses (the store's two controllers) 4 | **39** | 9½ | 1 (2 to make 3 panels) |
| **(b) autocrafting** | 1k crafting storage 9 · 2 molecular assemblers 9 · pattern provider 2 · pattern encoding terminal 7¼ · 8 blank patterns 14 · 8 more cable 4 | **45** | 6½ | 9 |
| **(c) ME Bridge** | 4 fluix blocks 8 · 4 interfaces 8 · casing (iron, bars, redstone block: none) | **16** | 12 | |
| **total** | | **100** | **28** | **10** |
| later | 6 growth accelerators 33 · energy cell 7¼ · 4k cells 20¾ each · energy acceptor 5 (not needed) | | | |
| renewal | 3 per dead block | 27 for all 9 | | |

**So:**

- the first harvest (about 120 crystals) pays for (a) and most of (b);
- the second, about 3 hours later, pays for (c), the renewal and the first
  accelerators.

**Starting crystals before any harvest:** the 5 quartz blocks (20) and the
cluster (4) make **24**. That is enough to prove the bench and make the first
16 fluix before the farm has grown anything.

## 5. The AE2 bench

There are six machines, each powered from below over Mekanism cable (FE)
and worked from above. A drone drops material in and sucks the result out.

| name | machine | does |
|---|---|---|
| silicon, logic, calc, eng | inscriber, with that press | prints: silicon, gold, a certus crystal, a diamond |
| mill | inscriber, no press | crystal to dust (certus, fluix); processors (printed circuit + printed silicon + redstone, equal numbers, so nothing sticks in the press slots) |
| charger | charger | one crystal at a time |

| preset | where | when |
|---|---|---|
| `bench=now` | x 42, y 2, z 11-16, on today's plinth cable (docs/foundry.md `job=power`), the drone over them at y 3 | **now** |
| `bench=v2` (default) | the v2 AE2 room's west wall: 28 1 18-23 (the four press inscribers 18-21, the charger at 22 as v2 has them, and the mill at 23, one more cell than v2 drew) | once v2's cable is under them. Later the controller beside them puts them on the ME network |

Lab steps (all `tools/certusfarm.py ... bench=now|v2`):

| command | what it does |
|---|---|
| `bench` | places the 5 inscribers and the charger, and drops a press into each printer |
| `charge N` | charges N crystals |
| `fluix N` | charges N crystals, then throws N charged + N redstone + N nether quartz into the basin: 2N fluix |
| `grind certus N`, `grind fluix N` | N crystals to dust in the mill |
| `print silicon/logic/calc/eng N` | N printed circuits |
| `proc logic/calc/eng N` | N processors in the mill |

Silicon is smelted by crafter1's furnaces (factory recipe `ae2:silicon`, from
certus dust).

## 6. The chain, in order

**Factory recipes** (`factory.lua`, test `test/ae2network.py`). Everything
crafted on a table is there:

- smooth sky stone (smelted), silicon (smelted);
- quartz glass, fluix block, quartz fiber, fluix glass cable;
- annihilation and formation cores;
- controller, drive, item cell housing, 1k and 4k components, 1k and 4k
  item cells;
- semi-dark monitor (the terminal's panel), terminal, crafting terminal,
  pattern encoding terminal;
- crafting unit, 1k crafting storage, molecular assembler, pattern provider,
  ME interface, blank pattern, storage bus, energy cell, growth accelerator;
- energy acceptor (already there), peripheral casing, ME Bridge;
- crafting table and redstone block.

Machine-made parts have no recipe, and the factory reports them as short
("Cannot make interface: short of 2 logic processor"). They are: crystals,
charged crystals, dust, printed circuits, processors, fluix crystal and
fluix dust. The bench steps make them and hand them in.

**What crafter1 can make right now** (no certus):

- ae2:inscriber (5 wanted), ae2:charger (one in stock already), ae2:crank;
- smooth sky stone (from the 54 sky stone);
- peripheral casing, iron bars, redstone block;
- crafting tables, pistons, glass.

**Steps:**

1. **Kyle:**
   - builds the farm (§3);
   - crafts the 5 quartz blocks into 20 crystals;
   - breaks the cluster for 4 more;
   - puts them in store;
   - gets about 10 glowstone dust.
2. **crafter1:** `make crafter1 item=ae2:inscriber n=5`,
   `make crafter1 item=ae2:smooth_sky_stone_block n=4`,
   `make crafter1 item=advancedperipherals:peripheral_casing n=1`.
3. **Bench:** `lab <helper> ... bench bench=now`.
4. **Prove the chain on the 24 crystals:** `fluix 8 bench=now` makes 16 fluix.
   `grind certus 8` makes 8 dust, which crafter1 smelts to silicon. Then
   `print silicon 4`, `print logic 2`, `print eng 2`, `proc logic 2`,
   `proc eng 2`.
5. **About 3 hours after the farm is placed:** `first bench=now`, the first
   harvest and the next 8 crystals' fluix. Then, from about 120 crystals:

   | job | count |
   |---|---|
   | fluix | 24 (48 fluix) |
   | grind certus | 30 (the cable's fiber, quartz glass, silicon) |
   | print silicon | 14 |
   | print logic | 10 |
   | print calc | 3 |
   | print eng | 4 |
   | proc logic | 10 |
   | proc calc | 3 |
   | proc eng | 4 |
   | grind fluix | 6 (for the cores) |

   The counts follow §4. The factory then crafts the controller, drive,
   cells, crafting terminal, cable and storage buses.
6. **(a) Kyle places the network.** The controller goes on Mekanism power
   (the power block, or the plinth cable for now). Then drive and cells, the
   terminal at his desk, glass cable, and storage buses facing the two
   Sophisticated controllers (docs/ae2-plan.md §4).
7. **(b) after the second harvest:**
   - the factory crafts the 1k crafting storage, assemblers, pattern
     provider, pattern encoding terminal and blank patterns;
   - Kyle sets up the CPU (one crafting storage block is a CPU) and the
     provider with assemblers against it;
   - Kyle writes the first patterns.
8. **(c) ME Bridge:**
   - `fluix 8` (16 fluix → 4 blocks), 4 interfaces, then
     `make crafter1 item=advancedperipherals:me_bridge`;
   - it goes on the network and on our wired modem network. Sortnado's ME
     backend takes over the store (docs/ae2-plan.md §3).
   - From then on the bench's printing and grinding can become ME patterns,
     with the inscribers on the network and a pattern provider pushing into
     them. That is a later stage.
9. **Renew** the farm when `survey` shows dead blocks (§3). Accelerators come
   after (b).

## 7. The first orders

```
tools/order.py make crafter1 item=ae2:inscriber n=5
tools/order.py lab lava1 clear=1 "ops=$(python3 tools/certusfarm.py bench bench=now)"
tools/order.py lab lava1 clear=1 "ops=$(python3 tools/certusfarm.py fluix 8 bench=now)"     # with Kyle's 24 crystals in store
# about 3 hours after the farm is placed:
tools/order.py lab lava1 clear=1 "ops=$(python3 tools/certusfarm.py first bench=now)"
```

lava1 is just an idle helper; any helper will do. `first` is the harvest
followed by `fluix 8`. Read `labOut` in the helper's status:

- each `pick` line says `picked (n so far)` or `left: <bud>`;
- the fluix run ends with the fluix on board before the hand-in.

## 8. Not verified

- **Server `randomTickSpeed`:** the timings assume 3, the default.
- **The pack's AE2 recipes:** checked against AE2's own data. ATM10 may
  change a recipe; craft each once (the factory reports a failed craft and
  leaves it).
- **`bench=now`:**
  - that today's plinth cable is laid at 42 1 11-16 and the cells over it are
    free (the plan says so; `bench` does an `inspect|down` before each
    place);
  - **which way a turtle-placed inscriber and charger face.** Power goes in
    on every side but the front. Placed from above, the front should face up
    toward the turtle, so the cable below feeds it; if not, turn them with a
    certus wrench.
  - that a Mekanism universal cable feeds them. AE2 offers FE on those
    sides; Mekanism's side is not checked here.
- **The charger's real speed on our power:** 4 s a crystal is assumed.
  Crystals not done in time stay in it, and later `suckDown`s collect them.
- **CC turtle `suck` from the inscriber's output:** this follows from AE2's
  automation filter (only the output may be taken out). Tested only in
  simulation.
- **Renewal** (`renew`) is untested in game. Fluix in the basin follows
  AE2's code; the first `fluix 8` will show it.
- **Glowstone:** where it comes from in this world.
- **v2:**
  - the bench=v2 cells and the farm's zone assume Kyle approves
    docs/foundry-v2.md;
  - the mill at 28 1 23 is one cell more than v2 drew;
  - accelerators need power up the pillars (cable at 30 0 7/10 under the
    floor).
