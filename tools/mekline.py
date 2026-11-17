#!/usr/bin/env python3
"""The piped ore line in the foundry bay (docs/mekanism-plan.md): where each
block goes, stage by stage, and the lab run that builds a stage.

    python3 tools/mekline.py map              the layers, as built up to stage 5
    python3 tools/mekline.py map 3            ... up to stage 3
    python3 tools/mekline.py ops 2            the lab steps for stage 2
    python3 tools/mekline.py items 2          what stage 2 fetches

Coordinates are the factory building's own (corner -4448 71 1518; x east,
z south, y 1 = the ground floor). The line runs north to south along x 36
and the builder works from x 35 (the walkway) facing east, so a machine it
places faces west. Facing west, a Mekanism machine's LEFT is north and its
RIGHT is south: every machine on the line takes items in on the LEFT and
pushes its output out of the RIGHT into the next one (eject on). Nothing
here touches the built structure: the cells are open floor in the bay.
"""
import sys

ORIGIN = (-4448, 71, 1518)
SHELL, PLAN = "factory_asfit3", "factory_foundryfloor"

# (stage, x, y, z, item, how, config)
#   how: "east"  = stand at x-1 facing east and place (block faces west)
#        "north" = stand at z+1 facing north and place (block faces south)
#        "south" = stand at z-1 facing south and place (block faces north)
#        "down"  = stand on the cell above and place down
#   item "dig" takes up what an earlier stage put there
#   config: lab "call" steps run on the block just placed
ITEM_IO = ["setMode|ITEM|LEFT|INPUT", "setMode|ITEM|RIGHT|OUTPUT", "setEjecting|ITEM|true",
           "setMode|ENERGY|TOP|INPUT"]
CHEM_IO = ITEM_IO + ["setMode|CHEMICAL|LEFT|INPUT", "setMode|CHEMICAL|RIGHT|OUTPUT",
                     "setEjecting|CHEMICAL|true"]
TP = "mekanism:basic_logistical_transporter"
CABLE = "mekanism:basic_universal_cable"
TUBE = "mekanism:basic_pressurized_tube"
PIPE = "mekanism:basic_mechanical_pipe"

BLOCKS = [
    # stage 2: the 2x line on pipes, its own power
    (2, 36, 1, 9, "minecraft:chest", "east", []),                          # inbox: ore goes in here
    (2, 36, 1, 10, "mekanism:logistical_sorter", "north", ["setAutoMode|true"]),  # pulls from the inbox
    (2, 36, 1, 11, TP, "east", []), (2, 36, 1, 12, TP, "east", []), (2, 36, 1, 13, TP, "east", []),
    (2, 36, 1, 14, TP, "east", []), (2, 36, 1, 15, TP, "east", []), (2, 36, 1, 16, TP, "east", []),
    (2, 36, 1, 17, "mekanism:enrichment_chamber", "east", ITEM_IO),
    (2, 36, 1, 18, "mekanism:energized_smelter", "east", ITEM_IO),
    (2, 36, 1, 19, "minecraft:chest", "east", []),                         # outbox: ingots
    (2, 36, 1, 21, "mekanismgenerators:heat_generator", "south", []),      # front north, into the cable
    (2, 36, 1, 20, CABLE, "east", []),
] + [(2, 36, 2, z, CABLE, "east", []) for z in range(11, 21)] + [
    # stage 3: purify (oxygen) and crush ahead of the enrichment chamber
    (3, 36, 1, 16, "dig", "east", []), (3, 36, 1, 16, "mekanism:crusher", "east", ITEM_IO),
    (3, 36, 1, 15, "dig", "east", []), (3, 36, 1, 15, "mekanism:purification_chamber", "east",
                                         ITEM_IO + ["setMode|CHEMICAL|TOP|INPUT"]),
    # the separator sits on the purifier and drops oxygen straight into it;
    # the cable steps over it at y 3
    (3, 36, 2, 15, "dig", "east", []),
    (3, 36, 2, 15, "mekanism:electrolytic_separator", "east",
     ["setMode|ENERGY|TOP|INPUT", "setMode|FLUID|BACK|INPUT", "setMode|CHEMICAL|BOTTOM|OUTPUT",
      "setEjecting|CHEMICAL|true"]),
    (3, 36, 3, 14, CABLE, "east", []), (3, 36, 3, 15, CABLE, "east", []), (3, 36, 3, 16, CABLE, "east", []),
    # water: the pump stands over a 2 x 2 pool in a basin west of the line,
    # the main runs at y 4 over the walkway and down x 37 to the separator
    *[(3, x, 1, z, "minecraft:stone_bricks", "down", []) for x, z in
      ((29, 13), (29, 14), (32, 13), (32, 14), (30, 12), (31, 12), (30, 15), (31, 15))],
    (3, 30, 1, 13, "water", "down", []), (3, 31, 1, 13, "water", "down", []),
    (3, 30, 1, 14, "water", "down", []), (3, 31, 1, 14, "water", "down", []),
    (3, 30, 2, 13, "mekanism:electric_pump", "east", ["setMode|FLUID|TOP|OUTPUT", "setEjecting|FLUID|true",
                                                       "setMode|ENERGY|BACK|INPUT"]),
    (3, 30, 3, 13, PIPE, "down", []), (3, 30, 4, 13, PIPE, "down", []),
    # the pump's power: off the cable bridge, west along y 3 and down beside it
    (3, 31, 2, 14, CABLE, "down", []), (3, 31, 2, 13, CABLE, "down", []),
    *[(3, x, 3, 14, CABLE, "down", []) for x in range(31, 36)],
    *[(3, x, 4, 13, PIPE, "east", []) for x in range(31, 38)],
    (3, 37, 3, 13, PIPE, "east", []), (3, 37, 2, 13, PIPE, "east", []),
    (3, 37, 2, 14, PIPE, "east", []), (3, 37, 2, 15, PIPE, "east", []),
    # stage 4: inject (hydrogen chloride) ahead of the purifier; HCl comes
    # down x 38 and in at the injector's back (x 37)
    (4, 36, 1, 14, "dig", "east", []), (4, 36, 1, 14, "mekanism:chemical_injection_chamber", "east",
                                         ITEM_IO + ["setMode|CHEMICAL|BACK|INPUT"]),
    (4, 37, 1, 14, TUBE, "east", []), *[(4, 38, y, 14, TUBE, "east", []) for y in (1, 2, 3, 4)],
    # stage 5: dissolve, wash, crystallise ahead of the injector
    (5, 36, 1, 13, "dig", "east", []), (5, 36, 1, 13, "mekanism:chemical_crystallizer", "east", CHEM_IO),
    (5, 36, 1, 12, "dig", "east", []), (5, 36, 1, 12, "mekanism:chemical_washer", "east",
                                         CHEM_IO + ["setMode|FLUID|BACK|INPUT"]),
    (5, 36, 1, 11, "dig", "east", []), (5, 36, 1, 11, "mekanism:chemical_dissolution_chamber", "east",
                                         CHEM_IO + ["setMode|CHEMICAL|BACK|INPUT"]),
    (5, 37, 1, 12, PIPE, "east", []), (5, 37, 2, 12, PIPE, "east", []),   # water to the washer
    (5, 37, 1, 11, TUBE, "east", []), *[(5, 37, y, 11, TUBE, "east", []) for y in (2, 3, 4)],  # acid
]


def upto(stage):
    """What stands at each cell once stages 2..stage are built."""
    cells = {}
    for st, x, y, z, item, how, cfg in BLOCKS:
        if st > stage:
            continue
        if item == "dig":
            cells.pop((x, y, z), None)
        else:
            cells[(x, y, z)] = item
    return cells


SHORT = {"minecraft:chest": "C", "mekanism:logistical_sorter": "S", TP: "t", CABLE: "=",
         "mekanism:enrichment_chamber": "E", "mekanism:energized_smelter": "M",
         "mekanismgenerators:heat_generator": "H", "mekanism:crusher": "R",
         "mekanism:purification_chamber": "P", "mekanism:electrolytic_separator": "X",
         "minecraft:stone_bricks": "#", "water": "~", "mekanism:electric_pump": "U", PIPE: "w",
         "mekanism:chemical_injection_chamber": "I", TUBE: "g", "mekanism:chemical_crystallizer": "Y",
         "mekanism:chemical_washer": "W", "mekanism:chemical_dissolution_chamber": "D"}


def draw(stage):
    cells = upto(stage)
    out = []
    for y in (1, 2, 3, 4):
        out.append(f"y {y}   x 29..40 across, z 9..21 down   (lane = x 39-40)")
        out.append("      " + "".join(str(x % 10) for x in range(29, 41)))
        for z in range(9, 22):
            row = ""
            for x in range(29, 41):
                it = cells.get((x, y, z))
                row += SHORT.get(it, "?") if it else ("|" if x in (39, 40) and y == 1 else ".")
            out.append(f"z {z:2d}  {row}")
        out.append("")
    out.append("C chest  S sorter  t transporter  = cable  E enrichment  M smelter  H heat gen")
    out.append("R crusher  P purifier  X separator  U pump  ~ water  # basin  w pipe  g tube")
    out.append("I injector  D dissolution  W washer  Y crystalliser")
    return "\n".join(out)


def items(stage):
    need = {}
    for st, x, y, z, item, how, cfg in BLOCKS:
        if st != stage or item == "dig":
            continue
        name = "minecraft:water_bucket" if item == "water" else item
        need[name] = need.get(name, 0) + 1
    return need


def ops(stage):
    need = items(stage)
    steps = ["fetch|" + ",".join(f"{k}={v}" for k, v in need.items()) + "|dump",
             "site|%d|%d|%d|%s|%s" % (*ORIGIN, SHELL, PLAN)]
    planned = {(x, y, z) for st, x, y, z, *_ in BLOCKS if st >= 1}
    for st, x, y, z, item, how, cfg in BLOCKS:
        if st != stage:
            continue
        out = []
        if how == "east":
            steps += [f"walk|{x - 1}|{y}|{z}", "face|0"]
        elif how in ("north", "south"):
            sz = z + 1 if how == "north" else z - 1
            if (x, y, sz) in planned:
                # the place to stand is itself a planned block (not laid yet),
                # so the walk will not end there: step in from the west
                steps += [f"walk|{x - 1}|{y}|{sz}", "face|0", "fwd|1"]
                out = ["face|2", "fwd|1"]
            else:
                steps.append(f"walk|{x}|{y}|{sz}")
            steps.append("face|3" if how == "north" else "face|1")
        elif how == "down":
            steps += [f"walk|{x}|{y + 1}|{z}"]
        d = "Down" if how == "down" else ""
        side = "down" if how == "down" else "front"
        if item == "dig":
            steps.append("dig" + d)
        elif item == "water":
            steps.append(f"place{d}|minecraft:water_bucket")
        else:
            steps += [f"place{d}|{item}", f"expect|{side}|{item.split(':')[1]}"]
            steps += [f"call|{side}|{c}" for c in cfg]
        steps += out
    if stage == 2:   # a stack of coal into the line's generator, from above
        steps += ["walk|36|2|21", "dropDown|minecraft:coal|16"]
    steps += ["leave", "handin|"]
    return ";".join(steps)


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "map"
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 5
    if cmd == "map":
        print(draw(n))
    elif cmd == "items":
        for k, v in items(n).items():
            print(f"{v:4d}  {k}")
    elif cmd == "ops":
        print(ops(n))
