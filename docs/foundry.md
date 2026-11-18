# The foundry

The Mekanism line in the east bay of the factory building, worked by one
helper (the operator). Code: `foundry.lua` (loaded by `helper.lua`), the
factory's side in `factory.lua` ("the foundry").

## Layout (the building's own coordinates; corner -4448 71 1518)

The machines stand on the deepslate-brick plinth (x 41-42, z 6-27), one
block east of the operator's lane (x 40), all facing west (the lane).

| machine | place | redstone (power) | in | out |
|---|---|---|---|---|
| Energized Smelter | 41 1 11 | west face, from the lane | south face (from the chamber), or top | north face: taken at 41 1 10 |
| Enrichment Chamber | 41 1 12 | west face, from the lane | top, from 41 2 12 | north face pushes into the smelter; south face for what is left (41 1 13) |
| Metallurgic Infuser | 41 1 15 (to be moved in) | west face | top; infusion item by the south face (41 1 16) | north face: taken at 41 1 14 |

Sides are named from the machine's front: facing west, LEFT is north and
RIGHT is south. A machine a turtle places faces the turtle; the operator
reads `getDirection` rather than assume it.

## Orders

    tools/order.py foundry foundry1 job=setup                 find the machines in the bay and set their sides
    tools/order.py foundry foundry1 ore=minecraft:raw_iron n=48   ore -> chamber -> smelter -> ingots (3 raw make 4)
    tools/order.py foundry foundry1 enrich=minecraft:redstone n=16   chamber only
    tools/order.py foundry foundry1 make=steel n=16           infuser: steel dust (also circuit, alloy)
    tools/order.py foundry foundry1 enrich=minecraft:diamond n=8   enriched diamond (80 mB of diamond infusion each)
    tools/order.py foundry foundry1 make=reinforced n=16      infuser: infused alloy + 20 mB diamond
    tools/order.py foundry foundry1 make=refined n=16         infuser: obsidian dust (a Crusher's) + 10 mB diamond
    tools/order.py foundry foundry1 make=atomic n=8           infuser: reinforced alloy + 40 mB refined obsidian
    tools/order.py foundry foundry1 job=move_infuser          bring the infuser in from the bench outside
    tools/order.py foundry foundry1 on=0                      back to an ordinary helper
    tools/order.py foundry foundry1 clear=1 / reset=1         drop the jobs in hand / forget what is set up

Any job puts the helper "on the foundry": between jobs it waits over the base
and takes jobs from the factory. Building, fit-out and lab orders still come
first. The status report carries `foundry` (machines, job in hand, the last
job and what it made, notes).

## What a job does

1. Out to the launch pad for the ore and the redstone (one trip).
2. In by the big door, along the lane. Whatever a run that lost power left
   in the machines is worked off first.
3. No more ore goes in than there is redstone on board to finish (ore left in
   a machine without power blocks the next job); the rest goes back as ore.
4. Redstone into the energy slots (west faces), ore into the chamber's top.
   The operator waits above the chamber, not at its south face: the chamber
   pushes its dust out of both result sides and would push it into the turtle.
5. Ingots taken at the smelter's north face; everything handed in on the pad.

## Cost

A job (one item through one machine) is 10 kJ; a redstone dust in the energy
slot is 10 kJ. 48 raw ore is 16 chamber jobs and 64 smelts: about 85 dust and
11 minutes for 64 ingots, where the furnaces give 48 for 6 coal. That is
about 5 dust for each extra ingot, so the factory only sends ore over while it
has redstone to spare (`FOUNDRY_KEEP` 128 kept back, `FOUNDRY_DUST` 100 a
batch) and takes the ore back into the furnaces otherwise.

## The factory's side

- The operator says which machines are set up (`foundry_ready`); the factory
  calls for one (`foundry_hello`) while it knows of none.
- With the chamber and smelter ready: 48 raw ore a job (iron, gold, copper,
  osmium) while ingots are wanted, one job at a time (`foundry_job`,
  `foundry_ack`, `foundry_done`). The furnaces leave that ore alone.
- Not answered in 2 minutes: asked again. Never answered in 20, or never
  finished in 60: dropped. Three failures: the furnaces take over, and the
  foundry is tried again a few hours on.

## Moving the infuser in (not done yet)

It stands on the bench outside at -4452 74 1533 (taken down from -4453 74
1533, facing east; it keeps what is in it). `job=move_infuser` takes it down,
carries it in and places it at 41 1 15 from the lane, then sets FRONT =
energy, TOP = input, RIGHT (south) = infusion, LEFT (north) = output. The
first `make=` job does the same by itself if the infuser is not in the bay.
The Inventory Manager beside the bench (-4453 74 1532) is not touched.
`tools/mek.py` (lab steps for the bench) is only for as long as it stands
outside.

## Power (job=power)

    tools/order.py foundry foundry1 job=power            generator, cube (if one can be had), cable; fuel; check
    tools/order.py foundry foundry1 job=power cube=0     no cube: cable in its place
    tools/order.py foundry foundry1 job=fuel [fuel=lava] more fuel for the generator
    tools/order.py foundry foundry1 job=bank [n=3]       more Energized Smelters at z 9, 8, 7, on the cable
    tools/order.py foundry foundry1 smelt=minecraft:sand n=128   anything a furnace cooks, through every smelter

All on the plinth behind the machines (x 42), in the building's coordinates:

| what | place | facing | why |
|---|---|---|---|
| Heat Generator | 42 1 18 | north | its front (where the power comes out) against the cube |
| Basic Energy Cube | 42 1 17 | north | takes power at its back, gives it out of its front into the cable |
| Universal cable | 42 1 16 north to the first machine (11; 7 with the bank) | - | touches each machine's back (east face) |

Without a cube there is cable at 42 1 17; a later `job=power` with a cube to
hand takes that cable up and puts the cube in its place. The generator and
cube are placed from the spot south of them (a placed block faces the
turtle); the cable from above. Only our own cable is ever taken up.

The operator then sets each machine's back (east) to take energy
(`setMode("ENERGY", side, "INPUT")`, where the machine has such a setting),
drops coal into the generator from above (charcoal if there is no coal; a
stack at most), and reads each machine's energy before and after a short
wait. A machine whose energy rises is on the cable ("yes"); one already full
counts as on ("full") until a job shows it; one that stays empty keeps its
redstone ("no"). A machine on the cable costs no redstone: a job takes only
a few dust in case the power fails. If it runs short on the cable while the
generator has fuel, it goes back to redstone.

Fuel: a coal is about 32 jobs. Every job on the cable ends at the generator
and tops it up from the coal on board; when it is below 16, the next job
fetches fuel with its ore, and the factory sends a fuel job when no ore is
going over (only while it has 160 coal and charcoal to spare). Lava: only on
`fuel=lava`, and only while the empty bucket comes back out of the
generator's slot (the operator takes it); if it stays in, the operator says
so and uses no more lava (that bucket must then be taken out by hand).

The factory hears `power` in `foundry_ready` and then keeps only 16 dust
above its reserve for a batch instead of 100.

Recipes, NOT YET TRIED in this pack: universal cable (steel, redstone,
steel: 8), energy tablet (3 infused alloy down the middle, 2 gold, 4
redstone), basic energy cube (redstone, 2 tablets, 2 iron, steel casing),
wind generator (needs an electrolytic core, which the factory cannot make),
crusher (2 lava buckets, 2 circuits, 4 redstone, steel casing). The heat
generator was crafted in the world already.

Not done: tripling ore (Purification Chamber) needs oxygen gas, which means
an Electrolytic Separator, water and gas plumbing: left for later. The
factory does not yet send big smelting batches to the bank by itself
(`smelt=` is an order only).
