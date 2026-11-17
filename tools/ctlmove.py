"""Lab steps that move the storage room's Sophisticated Storage controller
from the desk (south end, building 10 2 29) to the middle of the west wall,
on top of the barrel at 10 4 15, so its 15-block reach covers the whole room.

It stays on the desk's wired network: cable from the desk modem (10 1 29) up
through the old controller's cell to the top of the wall (y 5), along the top
of the west wall to z 17, and a full wired modem at 10 5 16 touching the new
controller. The modem is switched on with a right-click through a Weak
Automata Core worn on the tool side.

    python3 tools/ctlmove.py [tool side: right] [pickaxe item]

prints the ops string for:  tools/order.py lab <helper> clear=1 "ops=..."
"""
import sys

OX, OY, OZ = -4448, 71, 1518
SIDE = sys.argv[1] if len(sys.argv) > 1 else "right"
PICK = sys.argv[2] if len(sys.argv) > 2 else "minecraft:diamond_pickaxe"
CABLE, MODEM = "computercraft:cable", "computercraft:wired_modem_full"
CTL, CORE = "sophisticatedstorage:controller", "advancedperipherals:weak_automata_core"
TOP = 5          # cable along the top of the west wall (barrels at y 1..4)
X, DESK_Z, NEW_Z = 10, 29, 15


def ops():
    cables = (DESK_Z - 2) - (NEW_Z + 2) + 1 + 4      # along the wall, and up from the desk
    s = [f"fetch|{CABLE}={cables + 1},{MODEM}=1,{CORE}=1",
         f"site|{OX}|{OY}|{OZ}|factory_asfit3|factory_storeroom",
         # down the old controller's column from above, taking what is there
         f"walk|{X}|{TOP + 1}|{DESK_Z}"]
    for y in range(TOP, 2, -1):                      # 5, 4, 3: clear the column (nothing, by the plan)
        s += ["digDown", "down|1"]
    s += ["inspect|down", "expect|down|controller", "digDown",      # the controller, from 10 3 29
          f"placeDown|{CABLE}"]
    for y in range(3, TOP + 1):                      # cable up to the top of the wall
        s += ["up|1", f"placeDown|{CABLE}"]
    s += ["up|1"]                                    # at 10 6 29
    for z in range(DESK_Z - 1, NEW_Z + 1, -1):       # 28 .. 17 along the top of the wall
        s += [f"walk|{X}|{TOP + 1}|{z}", f"placeDown|{CABLE}"]
    s += [f"walk|{X}|{TOP + 1}|{NEW_Z + 1}", f"placeDown|{MODEM}",
          f"walk|{X}|{TOP + 1}|{NEW_Z}", "inspect|down", f"placeDown|{CTL}",
          # switch the new modem on: from the room side, facing west
          f"walk|{X + 1}|{TOP}|{NEW_Z + 1}", "face|2", "expect|front|wired_modem",
          f"equip|{SIDE}|{CORE}", "use", f"equip|{SIDE}|{PICK}",
          "inv", "leave", "home", "handin|"]
    return ";".join(s)


if __name__ == "__main__":
    print(ops())
