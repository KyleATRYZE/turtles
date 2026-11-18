# AE2 (Applied Energistics 2): the plan

Where the swarm's storage goes once the Sophisticated Storage room runs out of
reach (one controller only sees 15 blocks). AE2's network has no such limit,
and Advanced Peripherals' **ME Bridge** lets our computers use it.

**Next: docs/ae2-bootstrap.md** (the meteorite haul is in: the certus farm, the AE2 bench,
the certus budget and the order of work to the network, autocrafting and the ME Bridge).

Pack: All the Mods 10 v8.5, MC 1.21.1 (AE2 19.x, Advanced Peripherals 0.7.x
for 1.21.1). Recipes below are from AE2's own generated recipe data and the
AE2 guide unless marked **(unverified)**: check those in JEI before the
factory crafts them.

## 1. What it is like to use (the player)

Nothing to learn: the **ME Terminal** is the chest.

- Right-click the terminal: every item in the system in one window, with a
  search box. Click a stack to take it, shift-click from your inventory to put
  it away. Nothing is in "a chest": the system decides where it lives.
- **Crafting Terminal**: the same, with a crafting grid that pulls straight
  from the system.
- **Wireless Terminal**: the same window anywhere in range of a Wireless
  Access Point (later stage).
- **Autocrafting** (later): ask the terminal for 64 pistons and it makes them
  from what is stored, using patterns we teach it.

The storage screen and `$get` keep working on top of this (section 3); the
terminal is the quick way, the computers are for the swarm and for chat.

## 2. Getting there: stages

### Stage A: find a meteorite (now; no certus needed)

The Meteorite Compass is not crafted: put a **compass** in a powered
**Charger** and it comes out as a Meteorite Compass. It points at the nearest
Mysterious Cube, which sits in the middle of every meteorite.

| Item | Recipe | Factory |
|---|---|---|
| Compass | vanilla: iron N/E/S/W, redstone in the middle | recipe added |
| Charger | `I C I / I . . / I C I` (I iron ingot, C copper ingot) | recipe added |
| Crank | `S S S / . . S / . . C` (S stick, C copper ingot) | recipe added |

All in stock (iron 93, copper ingots 634, redstone 480, sticks from logs).

Power: the charger takes power (AE or FE) on every side but its front (AE2
1.21.1 `ChargerBlockEntity`; the guide says top and bottom). Two ways:

1. **By hand (fastest):** Kyle puts the charger down anywhere, the crank on
   top, the compass in, and right-clicks the crank until it is charged.
2. **On the foundry's power:** the charger stands on top of the foundry's
   universal cable, at building (42, 2, 13) (world -4406, 73, 1531): the
   cable runs along x 42 from z 16 north to the machines (docs/foundry.md),
   so the charger's bottom touches it. A turtle drops a compass in from above
   (42, 3, 13) and sucks the Meteorite Compass out. **(unverified: that the
   space above the cable is free, and that a Mekanism cable feeds the
   charger's underside.)** Only worth doing once the power is laid; later it
   charges certus too.

### Stage B: the meteorite (Kyle, by hand)

Only a player can do this part. At the meteorite, bring back:

- **The Mysterious Cube**: break it, it drops all four **inscriber presses**
  (Calculation, Engineering, Logic, Silicon). One set is enough for ever: an
  Inscriber copies a press with an iron block.
- **Sky stone**: a stack or two (the ME Controller needs smooth sky stone;
  sky stone chests too).
- **Certus quartz**: the meteorite holds **Budding Certus Quartz**. Mine the
  clusters for crystals and the buds for dust. A budding block loses a level
  when broken (not with Silk Touch); a **Flawless** one can only be moved in a
  Mekanism Cardboard Box. Bring the budding blocks if you can (Silk Touch), as
  they are the swarm's certus farm.
- **Nether quartz**: a stack, for fluix (none in stock; there is 621 Actually
  Additions black quartz, which is not the same thing).

The factory has no certus and no AE2 items at all now; everything after
Stage A waits on this trip.

### Stage C: the inscriber line (swarm)

| Item | Recipe | Notes |
|---|---|---|
| Inscriber | `I P I / C . I / I P I` (P piston, C copper ingot) | recipe added; piston recipe exists |
| Charged certus | certus crystal in the Charger | the charger again |
| Fluix crystal | charged certus + redstone + nether quartz thrown in water | a turtle can drop them into a water block in front of it |
| Printed circuits | press + material in the Inscriber (silicon, gold, diamond, certus) | then processor = circuit + redstone + printed silicon |
| Quartz glass | certus dust + glass | **(unverified pattern)** |

The inscribers stand in the foundry bay on the Mekanism cable (they take FE).
**(unverified: that an inscriber takes FE straight from a Mekanism cable.)**

### Stage D: the ME network (swarm builds, Kyle places the terminals he uses)

| Part | Recipe | Count |
|---|---|---|
| ME Controller | `S F S / F E F / S F S` (S smooth sky stone, F fluix crystal, E engineering processor) | 1 |
| Energy Acceptor | `I Q I / Q C Q / I Q I` (Q quartz glass, C copper ingot) | 1 (recipe added) |
| ME Drive, item cells (1k/4k), cell housings | see JEI | 1 drive, 4+ cells |
| ME Terminal, Crafting Terminal | see JEI | 1 each, at the desk |
| ME Interface | `I G I / A . F / I G I` (G glass, A annihilation core, F formation core) | 4 for the bridge, more later |
| Fluix cable / smart cable | see JEI | runs |
| **ME Bridge** (Advanced Peripherals) | `F I F / I P I / F I F` (F fluix block, I ME Interface, P peripheral casing) | 1 |
| Storage Bus | see JEI | one per container to join (below) |

Power: the Energy Acceptor on the foundry's universal cable.

### Stage E: autocrafting (later)

Pattern Provider + Molecular Assembler + Crafting CPU (crafting storage
blocks). Patterns are written by a player at a Pattern Encoding Terminal.

## 3. What the computers do with it

The ME Bridge sits on the ME network **and** on our wired modem network
(peripheral type `me_bridge` on 1.21.1). Its 1.21.1 functions (from Advanced
Peripherals' source for 1.21.1):

- `getItems(filter)`, `getItem(filter)`: what is stored. Filter `{ name = "minecraft:iron_ingot" }`.
- `importItem(filter, target)`: from a container into ME; `exportItem(filter, target)`: out of ME.
  `target` is a side of the bridge or **the network name of a container on the cable**
  (e.g. our In and Out barrels). Returns how many moved.
- `craftItem(filter)`, `isCraftable(filter)`, `getCraftingTasks()`, `getCraftingCPUs()`.
- `getTotalItemStorage()`, `getUsedItemStorage()`, `isConnected()`, `isOnline()`,
  `getEnergyUsage()`, `getStoredEnergy()`.

**Done (branch `ae2`):** `sortnado.lua` has an ME backend. With an ME Bridge on
the cable, the ME system becomes the store (it wins over a Sophisticated
controller and loose chests):

- the In barrel is put away with `importItem(..., inbox)`;
- the screen's books come from `getItems`;
- to the Out barrel (turtles, the touch screen): `exportItem(..., outbox)`;
- to the owner (`$get` in chat): out to the Out barrel, then the Inventory
  Manager pulls it from there (it cannot pull from an ME system), as the
  controller backend already does when the store does not touch the manager.

So the desk stays as it is: In barrel, Out barrel, Inventory Manager, the
Sortnado computer and its screen, plus the ME Bridge on a wired modem.
Test: `test/sortme.py` (an ME system simulated alongside the controller test's world).

Still to write:

- `$craft 64 piston` in chat: `controller.lua` passes it to Sortnado, which
  calls `craftItem` and reports the job (Stage E).
- The factory's side (below).

## 4. The rooms we already have

- **The Sophisticated Storage room** joins the ME network through a
  **Storage Bus** facing its controller: the bus sees the controller as one
  inventory, so every barrel within its 15 blocks shows up in the terminal.
  A second controller further down the room gets its own bus. **(unverified:
  that a Storage Bus works on a Sophisticated controller; it works on any
  block that offers an item handler, and the controller does.)**
- **The factory's chests** (Crafty's ~918 slots): the quickest move is to put
  Storage Buses on them: the ME system sees the factory's stock at once with
  nothing carried. Then Crafty keeps working as now. Later Crafty itself
  works through the bridge (pull what a recipe needs into its own
  inventory with `exportItem`, put results back with `importItem`), and the
  old chests are emptied into ME cells by an Import Bus or by the turtle.

## 5. What only a player can do

- The meteorite trip (presses, sky stone, budding certus, nether quartz).
- Writing crafting patterns (Stage E).
- Anything set in an AE2 GUI by hand that has no peripheral call (partition
  and priority on cells and buses). The defaults are fine to start.

## 6. First orders

The factory must be rebooted onto the branch's code for the new recipes.

```
tools/order.py reboot Crafty
tools/order.py lab Pushy clear=1 "ops=fetch|ae2:charger=1,ae2:crank=1,minecraft:compass=2|dump;inv;handin|"
```

That proves the three recipes (they show in `inv`) and hands them back into
stock, where Kyle can take them or ask `$get 1 charger`, `$get 1 crank`,
`$get 1 compass` once the store holds them. For the foundry option, after
`job=power` has run:

```
tools/order.py lab DropIt clear=1 "ops=fetch|ae2:charger=1,minecraft:compass=1|dump;site|-4448|71|1518|factory_asfit3|factory_foundryfloor;walk|42|3|13;inspect|down;placeDown|ae2:charger;expect|down|charger;dropDown|minecraft:compass|1;wait|60;suckDown|1;inv;leave;home"
```

(unverified: walking to (42, 3, 13) depends on the bay's route at that height;
check `inspect|down` shows the space is empty before the place.)

## Sources

- AE2 recipes: AE2's generated recipe data on GitHub (charger, crank, inscriber, controller, energy acceptor, interface).
- AE2 guide (1.21.1): Meteorite Compass, Charger.
- ATM10 AE2 introduction (allthemods.github.io): meteorites, Mysterious Cube, budding certus.
- Advanced Peripherals: the 1.21.1 ME Bridge source (function list), and its generated `me_bridge` recipe.
