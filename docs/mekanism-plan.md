# Mekanism: the build plan

How the swarm grows the foundry from today's hand-fed 2x line into piped
3x, 4x and 5x ore processing. Each stage gets one test craft, one lab run
and one check before the next starts.

The recipes and ratios here come from Mekanism's own generated recipe data
for 1.21 (the `1.21.x` branch on GitHub). ATM10 ships Mekanism 10.7.x, so
each stage test-crafts its new parts once before it is built. The layout
comes from `tools/mekline.py`, which also prints each stage's parts list and
its lab steps.

## What each tier gives (per raw ore, which is what our miners bring)

| tier | machines in order | per 3 raw ore | needs |
|---|---|---|---|
| 1x | furnace | 3 ingots | coal |
| 2x | Enrichment Chamber → Energized Smelter | 4 | power |
| 3x | Purification Chamber → Crusher → Enrichment → Smelter | 6 (2 clumps each) | + oxygen |
| 4x | Chemical Injection Chamber → Purification → Crusher → Enrichment → Smelter | 8 (3 raw → 8 shards) | + hydrogen chloride |
| 5x | Dissolution → Washer → Crystallizer → Injection → … → Smelter | 10 (3 raw → 2000 mB slurry → 10 crystals) | + sulfuric acid, water |

The multipliers per ore *block* (2x to 5x) are the ones usually quoted; per
raw ore they are 1.33x, 2x, 2.67x and 3.33x. Raw ore blocks count as 9 raw.

**The chemicals:**
- **Oxygen:** from an Electrolytic Separator splitting water into hydrogen
  and oxygen. Flint gives 10 mB each, too little to run on.
- **Hydrogen chloride:** hydrogen (separator) and chlorine go into a
  Chemical Infuser. Chlorine comes from a separator splitting brine, and
  brine from a Thermal Evaporation Plant (a multiblock) evaporating water.
  Salt dust gives only 2 mB each.
- **Sulfuric acid:** sulfur dust goes into a Chemical Oxidizer to make
  sulfur dioxide. That plus oxygen in a Chemical Infuser makes sulfur
  trioxide. That plus water vapour (water through a Rotary Condensentrator)
  in another infuser makes the acid. Sulfur dust alone gives 2 mB each.
- **Water:** an Electric Pump over an infinite 2 × 2 pool.

**Per-tick chemicals:** purifying, injecting and dissolving use their
chemical every tick they run, so the gas must arrive by tube, not by the
item.

## Logistics without a player

| transmitter | carries | recipe (×8) |
|---|---|---|
| Universal Cable | power | steel, redstone, steel |
| Mechanical Pipe | fluids (water) | steel, bucket, steel |
| Pressurized Tube | gases (O₂, H₂, HCl, acid, slurry) | steel, glass, steel |
| Logistical Transporter | items | steel, basic circuit, steel |

Higher tiers are 8 of the tier below around one alloy (infused, then
reinforced, then atomic).

**Rules the layout follows:**
- **Machines feed each other directly.** A machine with ejection on pushes
  its output into whatever touches its output side. Every machine on the
  line takes items in on its LEFT and ejects out of its RIGHT into the next
  one (`setMode`, `setEjecting`). The swarm already proved this on the
  chamber and smelter.
- **Pull from a chest with a Logistical Sorter.** Pull mode on a transporter
  needs a Configurator, and a Configurator needs a player. The sorter is set
  to auto through CC (`setAutoMode`, unverified).
- **One chemical per tube network.** Tubes, pipes and cables of the same kind
  join with any of their kind they touch, so two different gases must never
  run side by side. The layout keeps every gas run apart, or brings it in
  from a different side of the machine.
- **Power on top.** A cable runs over the machines (y 2), and each machine's
  TOP is set to take energy.

**What still needs a player, and how to avoid it:**
- **Transmitter connection modes (pull, push, none):** avoided entirely by
  using ejection and the sorter.
- **Separator dumping of unused hydrogen:** CC `setLeftOutputDumpingMode` or
  similar (unverified). Failing that, burn it in a Gas-Burning Generator or
  feed it to the HCl infuser.
- **Upgrades and factory tier installers:** both are fitted by right-clicking
  the machine with the item. A turtle's `place` with the item in hand is a
  right-click, so try that before asking Kyle.
- **Painting transmitters to keep networks apart:** not needed if the layout
  rules are kept.

## The bay layout (`tools/mekline.py map`)

**Placement:**
- **Line:** runs along x 36, z 9–21, on open floor (no block of the plan or
  the as-fitted shell is there).
- **Walkway:** the builder works from the walkway at x 35, facing east, so
  every machine faces west: LEFT is north, RIGHT is south, BACK is x 37.
- **Lane:** the operator lane (x 39–40) is never blocked.
- **Stage 0 stays:** the stage 0 machines on the east plinth (x 41–42) carry
  on as they are until the line is proven.

The map below is as it stands after stage 5, lowest layer first:

```
y 1   x 29..40 across, z 9..21 down   (lane = x 39-40)
      901234567890
z  9  .......C..||      C inbox (ore in)
z 10  .......S..||      S logistical sorter, pulls from the inbox
z 11  .......Dg.||      D dissolution   g acid tube in at its back
z 12  .##....Ww.||      W washer        w water pipe in at its back
z 13  #~~#...Y..||      Y crystalliser  ~ water pool, # basin
z 14  #~~#...Igg||      I injector      g HCl tube in at its back
z 15  .##....P..||      P purifier (oxygen from the separator on top of it)
z 16  .......R..||      R crusher
z 17  .......E..||      E enrichment chamber
z 18  .......M..||      M energized smelter (later a smelting factory)
z 19  .......C..||      C outbox (ingots out)
z 20  .......=..||      = cable
z 21  .......H..||      H heat generator, front north into the cable

y 2
z 11  .......=g...      cable over the line; acid tube rising
z 12  .......=w...
z 13  .U=....=w...      U electric pump over the pool, = its power
z 14  ..=....=w...
z 15  .......Xw...      X electrolytic separator: water in at its back,
z 16  .......=....        oxygen out of its bottom into the purifier
z 17..20  cable

y 3
z 13  .w......w...      water main rising (pump; down to the separator)
z 14  ..======....      cable bridge over the separator, branch west to the pump
z 15, 16  cable bridge

y 4
z 11  ........g...      acid stub (to the acid plant, stage 5)
z 13  .wwwwwwww...      water main over the walkway
z 14  .........g..      HCl stub (to the HCl plant, stage 4)
```

Until the stages ahead of it are built, transporters fill the line from the
sorter to the first machine. Each stage digs the transporters in its cells
and puts its machines there. The inbox stays where it is.

The gas plants for stages 4 and 5 go west of the line (x 29–34, z 16–21)
and outside on the roof or west yard (the evaporation tower). Their tube
routes are planned when the stage is due, following the rules above.

## Stages

Bills of materials are worked down to raw items (iron, copper and gold
ingots; osmium; coal is the carbon for steel). "Steel" means two infuser
passes with coal, then smelting. Stock is from the snapshot of 17 Nov,
00:00.

| stock | have |
|---|---|
| iron ingots | 50 |
| raw iron | 105 |
| iron blocks | 20 |
| copper ingots | 506 (+968 raw) |
| raw osmium | 1,368 |
| raw gold | 2 (+13 raw blocks) |
| redstone | 1,666 dust (+1,269 blocks) |
| diamonds | 414 |
| obsidian | 739 |
| fluorite | 1,549 |
| sulfur | 476 |
| coal / charcoal | 267 / 55 |
| glass / sand | 128 / 189 |
| lava buckets | 2 |

### Stage 0 (now)

The chamber and smelter on the east plinth are fed by foundry1
(`foundry ore=`). The infuser is coming in from the bench (lava1). The
heat generator, cube and cable are merged as `foundry job=power`, but not
yet laid.

### Stage 1: power and transmitter proof

- **Unlocks:** no redstone feeding, and proof that the four transmitter
  recipes are right in this pack.
- **Bill of materials:** a basic cube, 16 cable, 8 pipe, 8 tube and 8
  transporters. That is about iron 19, coal 28, redstone 20, gold 6,
  copper 4, glass 5 and osmium 2 (steel 14, circuit 1, alloy 4).
- **Jobs:** a test craft (lab fetch), then `foundry foundry1 job=power`.
- **Check:** `foundry.power.ok = true`; the next 48-ore batch burns about 6
  dust, not about 85.

### Stage 2: the piped 2x line

- **Unlocks:** ore goes into one chest and ingots come out of another with
  no turtle in between. This is the base every later tier builds on.
- **Bill of materials:** sorter, 6 transporters, enrichment chamber,
  energized smelter, heat generator, 11 cable and 2 chests. That is about
  iron 27, coal 28, redstone 23, osmium 9, glass 10 and copper 2 (steel 14,
  circuits 6).
- **Job:** one lab run, `tools/mekline.py ops 2`. Before it, the infuser
  makes steel and circuits: `foundry foundry1 make=steel n=32`, then
  `make=circuit n=12`.
- **Check:** the run's notes show every `setMode` and `setEjecting` call
  without ERROR. Drop 12 raw iron into the inbox and get 16 ingots in the
  outbox.
- **Watch:** if `setAutoMode` errors, the sorter needs another name for that
  method (read `methods|front`).

### Stage 3: 3x, oxygen

- **Unlocks:** 2 ingots per raw ore, up from 1.33.
- **Bill of materials:**
  - **Machines:** crusher, purification chamber, electrolytic separator,
    electric pump.
  - **Transmitters and fittings:** 13 pipe, 10 cable, 8 stone bricks and 4
    water buckets.
  - **Power:** a second heat generator and an advanced cube.
  - **Raw:** about iron 57, redstone 72, coal 48, copper 30, osmium 20,
    glass 16, gold 13 and lava 2 (the crusher's two buckets).
  - **Infuser work:** 26 alloys and 8 circuits.
  - **Dusts:** the electrolytic core needs osmium, iron and gold dust, made
    first with `foundry foundry1 enrich=…` (their item names in this pack are
    not yet seen: probably `alltheores:*_dust`).
- **Job:** `tools/mekline.py ops 3`.
- **Check:** the purifier's chemical tank fills with oxygen, and 12 raw iron
  gives 24 ingots.
- **Watch the separator:** its hydrogen has nowhere to go until stage 4.
  Dump it (CC dumping mode) or add a Gas-Burning Generator on it, which also
  pays back some power.
- **Power:** the separator is the big draw. Measure with `getEnergy` on the
  cube; add heat generators, or wind generators on the roof (5 osmium, an
  alloy, 2 tablets and a circuit each) if the cube drains.

### Stage 4: 4x, hydrogen chloride

- **Unlocks:** 2.67 ingots per raw ore.
- **Bill of materials:**
  - **Machines:** a chemical injection chamber (it consumes a purification
    chamber in its recipe), a chemical infuser and a second separator (for
    brine).
  - **Evaporation tower:** a Thermal Evaporation Plant (about 48 blocks, a
    controller and 2 valves), with 24 tube and 2 wind generators.
  - **Raw:** about coal 150, redstone 104, iron 85, copper 63, osmium 37,
    diamonds 16 and gold 15.
- **Jobs:** an evaporation-tower fit plan (new, outside the building), and
  the line job `tools/mekline.py ops 4`.
- **Check:** the tower forms by itself when complete (no player); brine →
  chlorine; HCl reaches the injector's back; 12 raw iron gives 32 ingots.

### Stage 5: 5x, sulfuric acid

- **Unlocks:** 3.33 ingots per raw ore.
- **Bill of materials:**
  - **Machines:** dissolution chamber, washer and crystalliser (each needs
    2 ultimate circuits and refined obsidian), an osmium compressor (for
    refined obsidian ingots), a chemical oxidizer (it needs a personal
    chest and a dynamic tank), 2 chemical infusers and a rotary
    condensentrator.
  - **Raw:** about redstone 134, coal 76, diamonds 65, copper 58, osmium
    58, iron 56, glass 32, obsidian 5 and fluorite 2.
- **Jobs:** `tools/mekline.py ops 5`, plus the acid-plant run (planned at
  stage 4).
- **Check:** slurry in the washer and crystals out; 12 raw iron gives 40
  ingots.

### Stage 6: throughput and the storage link

- **Factories:** swap the single machines for basic, then advanced factories
  (3 and 5 at once). The recipes are in the factory: smelting, enriching and
  crushing factories.
- **Storage link:** a Logistical Sorter on the storage controller, filtered
  to raw ores (CC filter methods, unverified), feeds the inbox by
  transporter. A transporter from the outbox goes into the controller.
  Ore then goes from the miners to the store, to the line and back with no
  turtle in between.
- **Retire the furnaces:** retire them and the stage 0 machines; their
  chamber and smelter become the first factory upgrades.

**Totals for stages 1–5:** about iron 244, coal 330, redstone 353, copper
157, osmium 125, diamonds 81, gold 37 and glass 74. Everything but coal and
gold is covered by stock. Iron is covered only if the 20 iron blocks are
turned back into ingots; the factory has no recipe for that.

## Code still to write

- **Line build:** `foundry job=line stage=N`, which runs
  `tools/mekline.py`'s steps as a foundry job so the factory can raise it,
  instead of a hand-sent lab run.
- **Line operator duty:** keep the inbox full from stock (raw ore, while
  power and gases hold) and empty the outbox into stock. The factory side
  of this is like `foundryDuty`.
- **Iron blocks to ingots:** the factory needs a recipe for it (RECIPES
  holds one recipe per item, so this needs a second-recipe mechanism).
- **The evaporation tower and acid plant fit plans:** stages 4 and 5.

## Sources

- Mekanism's generated recipe data, `src/datagen/generated/mekanism/data/mekanism/recipe` on the `1.21.x` branch of [mekanism/Mekanism](https://github.com/mekanism/Mekanism)
- [Ore Processing: 2x to 5x](https://www.minecraft-guides.com/mod/mekanism/wiki/ore-processing/)
- [Mekanism Recipe Type JSON Syntax](https://github.com/mekanism/Mekanism/wiki/Recipe-Type-JSON-Syntax)
