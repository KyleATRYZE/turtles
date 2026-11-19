# Factory v2: first build pass (19 Nov, afternoon)

Approved by Kyle 14:25 ("Go ahead"). Compiled from tools/factoryv2.py by tools/v2build.py and run over RCON.
Every placement was `fill/setblock ... keep`: only air was filled, nothing existing was replaced or dropped.

## Built
- Roads (south z 1555-1557, east x -4391..-4389, with a centre line), forecourt, dirt bed under them.
- Main block raised to four storeys: pilasters, floor bands, glass curtain on the upper floors (y 84-92), flat roof (y 92),
  red parapet, red roof frame and twin red stacks.
- Red lattice tower (x -4399..-4393, z 1527..1533, to y 109) with core, mesh faces and rings; skip bridge; high truss.
- Banded chimneys (x -4399/-4395, z 1539-1540, to y 116); podium arcade piers on the east and south.
- Lookout box on the west wall (tinted glass); trees, hedges and street lamps on dirt footings.
- Inside: engine floor slab (y 86) with boilers, burners, steam engines, cogs, shaft lines, presses, deployers, mixers,
  crafter wall, tank bank, steam main, lanterns; logistics deck packagers, frogports, chain posts, ticker, requesters,
  boards; hall catwalk bridges with railings, red columns, chutes, pipe mains, gantry shaft and carriage, hanging lights;
  four guard turtles at the patrol corners.

## Kept clear on purpose
- The drone lane (z 1518..1521, y 72..76) and the drones' way down at both gates (x -4453..-4450 and -4403..-4400, sky to floor).
- Every doorway, port and vent in the old walls (the skin skipped the old envelope below y 84).
- The hut / crafter1 / crafter2 / old pad shaft corner (x <= -4454, z 1512..1532).
- Phases 1-7 of the AE2 plan (gas plant covers etc.) and all ME devices.

## Pass 2: the old walls swapped (Kyle 14:51 "Swap em", tools/v2reskin.py)
- Facades x 0, z 0, z 30, x 45 (y 72..83): stone bricks, polished deepslate, deepslate tiles and glass panes replaced in
  place by the new skin (pilasters, bands, red band, glass). Machines, screens, cables, modems and openings untouched.
- The old pitched roof inside the new top floor: at y 86 it became engine floor, above it removed.
- After: controller online, ME sweep line passed, both lane gates and the drop columns still open.

## Not done yet (needs work in game or a later pass)
- The hall's roof (podium moss roof, skylights) and the inside walls (iwall) are not swapped yet.
- Launch bay fit-out: the furnaces must be emptied and moved first. Held commands: /tmp/v2_bay_held.txt (regenerate with v2build).
- Belts, chain-conveyor runs, the hangar door and blast gate are Create pieces that only work when made in game
  (belt connector, chains, contraptions).
- Patrol path ring: the land drops 1-4 blocks east and south; needs terraforming first.
- ME health sweep after the build: all four lines passed.

## Pass 3: Create links by command (19 Nov 15:10)
- Belts: a belt piece checks its chain on its first tick and breaks if the rest isn't there yet, so the whole belt is
  placed while the world is paused for a split second: `tick freeze`, start + `fill` middle + end, `tick unfreeze`.
  Built: engine floor z 1543 (x -4432..-4423), hall overhead belts y 78 at z 1526 (x -4419..-4405) and z 1540 (x -4419..-4409).
  (First tries broke and dropped a few belts/shafts: those items were removed.)
- Chain conveyors: links are the posts' `Connections` (relative offsets, both ends): deck loop (four posts at y 84),
  outside tower chain (y 90), hall pair (y 80).
- Still needed for motion: rotation. Plan: Create Crafts & Additions electric motors fed from the thermo generator row
  (x -4406, y 72, z 1535..1541 pushes FE), shafts/gearboxes up to the belt pulleys. Keep clear of the ME blocks at x -4409/-4410.
- The real hall is taller than the model (air to y 84, roof from y 85): the podium roof must go at y 85, not y 81.
  The hall roof block type could not be identified by tests: look in game before swapping it.
