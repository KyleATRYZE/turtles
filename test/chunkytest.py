# swarm.chunky: a turtle's own Chunk Controller, worn on the tool side in
# place of the pickaxe. Runs from anywhere:  python3 test/chunkytest.py
import os, lupa
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CTL, PICK, SCAN = "advancedperipherals:chunk_controller", "minecraft:diamond_pickaxe", "advancedperipherals:geo_scanner"

ENV = r'''
CLOCK, SWAPS, SLEPT = 0, 0, 0
os.clock = function() return CLOCK end
sleep = function(n) CLOCK = CLOCK + (n or 0) SLEPT = SLEPT + (n or 0) end
FS = {}
fs = { exists = function(f) return FS[f] ~= nil end, delete = function(f) FS[f] = nil end,
  open = function(f, mode) return { write = function(s) FS[f] = s end, close = function() end,
    readAll = function() return FS[f] end } end }
SIDES = { left = "modem", right = "minecraft:diamond_pickaxe" }     -- what is fitted
INV = {}
SEL = 1
local function kind(item)        -- what a fitted thing shows as, as a peripheral
  if item == "modem" then return "modem" end
  if item == "advancedperipherals:chunk_controller" then return "chunky" end
  if item == "advancedperipherals:geo_scanner" then return "geo_scanner" end
  return nil                     -- a pickaxe is no peripheral
end
peripheral = { getType = function(side) return kind(SIDES[side]) end,
  find = function() return nil end, getName = function() return "left" end }
local function equip(side)
  return function()
    SWAPS = SWAPS + 1
    if SIDES[side] == "modem" then MODEM_SWAPPED = true end
    local inHand = INV[SEL]
    INV[SEL] = SIDES[side] and { name = SIDES[side], count = 1 } or nil
    SIDES[side] = inHand and inHand.name or nil
    return true
  end
end
turtle = { getItemDetail = function(s) return INV[s] end, select = function(s) SEL = s return true end,
  getSelectedSlot = function() return SEL end, equipLeft = equip("left"), equipRight = equip("right") }
rednet = { open = function() end, broadcast = function() end }
'''

def fresh(setup=""):
    L = lupa.LuaRuntime(unpack_returned_tuples=True)
    L.execute(ENV)
    L.execute(setup)
    L.globals().C = L.eval('dofile("%s/swarm.lua")' % ROOT).chunky
    return L, L.globals()

fails = []
def check(what, ok):
    print(("ok   " if ok else "FAIL ") + what)
    if not ok: fails.append(what)

# 1. a builder's mate: modem left, pickaxe right, controller in the inventory
L, g = fresh('INV[3] = { name = "%s", count = 1 }' % CTL)
check("has one, not worn yet", L.eval("C.have()") and not L.eval("C.isWorn()"))
check("wear puts it on the right", L.eval("C.wear()") and g.SIDES.right == CTL and g.SIDES.left == "modem")
check("the pickaxe is in the inventory", L.eval("INV[3].name") == PICK)
check("worn is known", L.eval("C.isWorn()"))
check("tool puts the pickaxe back", L.eval("C.tool()") and g.SIDES.right == PICK and L.eval("INV[3].name") == CTL)
check("the modem was never touched", not g.MODEM_SWAPPED)

# 2. keep: flying (no digs) wears it and leaves it on; a dig takes it off;
#    digging on, it only goes on for a moment per chunk and per HOLD
L, g = fresh('INV[3] = { name = "%s", count = 1 }' % CTL)
L.execute("CLOCK = 100 C.keep(0, 0)")
check("keep: idle -> worn", g.SIDES.right == CTL)
n = g.SWAPS
L.execute("for i = 1, 50 do CLOCK = CLOCK + 1 C.keep(i, 0) end")
check("keep: stays on in flight with no more swaps", g.SIDES.right == CTL and g.SWAPS == n)
L.execute("C.tool()")
check("a dig puts the pickaxe on", g.SIDES.right == PICK)
n = g.SWAPS
L.execute("CLOCK = CLOCK + 1 C.keep(51, 0)")          # same chunk (48..63), just dug
check("keep while digging, same chunk: nothing", g.SWAPS == n and g.SIDES.right == PICK)
L.execute("CLOCK = CLOCK + 1 C.tool() C.keep(64, 0)")  # a new chunk
check("keep while digging, new chunk: on for a moment, pickaxe back", g.SWAPS == n + 2 and g.SIDES.right == PICK)
n = g.SWAPS
L.execute("for i = 1, 60 do CLOCK = CLOCK + 2 C.tool() C.keep(65, 0) end")   # 120 s of digging in one chunk
check("no swaps inside HOLD", g.SWAPS == n)
L.execute("for i = 1, 40 do CLOCK = CLOCK + 2 C.tool() C.keep(65, 0) end")   # past HOLD
check("one touch after HOLD", g.SWAPS == n + 2 and g.SIDES.right == PICK)
L.execute("CLOCK = CLOCK + 10 C.keep(65, 0)")
check("digging over: back on to stay", g.SIDES.right == CTL)

# 3. no controller on board: nothing ever swaps
L, g = fresh()
L.execute("C.keep(0, 0) C.tool() C.wear() C.touch(99, 99)")
check("no controller: no swaps", g.SWAPS == 0 and not L.eval("C.have()"))

# 4. no modem to be seen (it was swapped off): hands off
L, g = fresh('SIDES.left = nil INV[3] = { name = "%s", count = 1 }' % CTL)
L.execute("C.keep(0, 0) C.wear()")
check("no modem: no swaps", g.SWAPS == 0)

# 5. a miner the other way round (modem right, pickaxe left)
L, g = fresh('SIDES = { right = "modem", left = "%s" } INV[1] = { name = "%s", count = 1 }' % (PICK, CTL))
L.execute("C.keep(0, 0)")
check("modem right: worn on the left", g.SIDES.left == CTL and g.SIDES.right == "modem" and not g.MODEM_SWAPPED)

# 6. started up already wearing it (the pickaxe in the inventory)
L, g = fresh('SIDES.right = "%s" INV[5] = { name = "%s", count = 1 }' % (CTL, PICK))
check("woke up wearing it: known, no swap", L.eval("C.isWorn()") and g.SWAPS == 0)
check("tool still works", L.eval("C.tool()") and g.SIDES.right == PICK)

# 7. the Geo Scanner is fitted (a scan in progress): leave it be
L, g = fresh('SIDES.right = "%s" INV[5] = { name = "%s", count = 1 } INV[6] = { name = "%s", count = 1 }' % (SCAN, PICK, CTL))
L.execute("C.keep(0, 0)")
check("scanner fitted: no swap", g.SWAPS == 0 and g.SIDES.right == SCAN)

# 8. the order "chunky on=false": carried, never worn; on again: worn
L, g = fresh('INV[3] = { name = "%s", count = 1 }' % CTL)
L.execute("C.setEnabled(false) C.keep(0, 0)")
check("switched off: not worn", g.SIDES.right == PICK and g.FS[".nochunky"] is not None)
L.execute("C.setEnabled(true) CLOCK = CLOCK + 30 C.keep(0, 0)")
check("switched on: worn", g.SIDES.right == CTL)

# 9. a spare pickaxe in the inventory and nothing to tell what is fitted:
#    one harmless swap of pickaxes, and no controller is imagined
L, g = fresh('INV[2] = { name = "%s", count = 1 }' % PICK)
check("spare pickaxe: has no controller", not L.eval("C.have()") and g.SIDES.right == PICK and g.SWAPS <= 1)

print("PASS" if not fails else "FAILED: %d" % len(fails))
