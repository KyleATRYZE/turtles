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

    tools/order.py foundry DropIt job=setup                 find the machines in the bay and set their sides
    tools/order.py foundry DropIt ore=minecraft:raw_iron n=48   ore -> chamber -> smelter -> ingots (3 raw make 4)
    tools/order.py foundry DropIt enrich=minecraft:redstone n=16   chamber only
    tools/order.py foundry DropIt make=steel n=16           infuser: steel dust (also circuit, alloy)
    tools/order.py foundry DropIt job=move_infuser          bring the infuser in from the bench outside
    tools/order.py foundry DropIt on=0                      back to an ordinary helper
    tools/order.py foundry DropIt clear=1 / reset=1         drop the jobs in hand / forget what is set up

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

## Power, next (recipes in the factory, not yet tried in this pack)

Energy tablet, basic energy cube, universal cable, wind generator; a spare
Heat Generator is in stock. A generator gives its power out of its front, and
a placed machine faces the turtle, so: stand where the cable (or the machine)
is to go, place the generator beyond it, back off one and place the cable.
Cables join by themselves; the machines take power on any side. With power
laid on, `perOp` in `foundry.lua` goes to 0 and the redstone limit in the
factory can go.
