"""The surveyor's Geo Scanner: the factory's grid against Advanced
Peripherals' own pattern (AP 1.21.1 data: DMD / DCD / ROR), with the
peripheral casing, the observer and the redstone blocks made on the way.

    python3 test/georecipe.py
"""
import os, sys
import lupa

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
L = lupa.LuaRuntime(unpack_returned_tuples=True)
L.execute("MODEM_ON=true")
L.execute(open(os.path.join(HERE, "fharness.lua")).read().replace("/home/claude/turtles", ROOT))
L.execute('''
local I, C, R, S = "minecraft:iron_ingot", "minecraft:copper_ingot", "minecraft:redstone", "minecraft:stick"
local P, CB, PL = "minecraft:piston", "minecraft:cobblestone", "minecraft:oak_planks"
local D, M, CA, O, RB, Q = "minecraft:diamond", "computercraft:wired_modem_full", "advancedperipherals:peripheral_casing",
  "minecraft:observer", "minecraft:redstone_block", "minecraft:quartz"
local BARS = "minecraft:iron_bars"
local REAL = {
  { out = "advancedperipherals:geo_scanner", n = 1, rows = { { D, M, D }, { D, CA, D }, { RB, O, RB } } },
  { out = CA, n = 1, rows = { { I, BARS, I }, { BARS, RB, BARS }, { I, BARS, I } } },
  { out = O, n = 1, rows = { { CB, CB, CB }, { R, R, Q }, { CB, CB, CB } } },
  { out = RB, n = 1, rows = { { R, R, R }, { R, R, R }, { R, R, R } } },
  { out = BARS, n = 16, rows = { { I, I, I }, { I, I, I }, { "", "", "" } } },
}
local SLOTS = { { 1, 2, 3 }, { 5, 6, 7 }, { 9, 10, 11 } }
local craft = turtle.craft
turtle.craft = function()
  local items = INV.turtle_3.items
  for _, r in ipairs(REAL) do
    local same, k = true, 64
    for row = 1, 3 do for col = 1, 3 do
      local it = items[SLOTS[row][col]]
      if (it and it.name or "") ~= r.rows[row][col] then same = false end
      if it then k = math.min(k, it.count) end
    end end
    if same then
      k = math.min(k, math.floor(64 / r.n))
      for row = 1, 3 do for col = 1, 3 do
        local s = SLOTS[row][col]
        if items[s] then items[s].count = items[s].count - k if items[s].count == 0 then items[s] = nil end end
      end end
      items[SEL] = { name = r.out, count = r.n * k }
      CRAFTED[#CRAFTED + 1] = r.out
      return true
    end
  end
  return craft()
end
C1 = "minecraft:chest_0"
put(C1, I, 64) put(C1, C, 32) put(C1, R, 32) put(C1, S, 16) put(C1, CB, 32) put(C1, PL, 16)
put(C1, "minecraft:coal", 64) put(C1, "minecraft:diamond", 8) put(C1, "computercraft:wired_modem_full", 2) put(C1, "minecraft:quartz", 4) put(C1, R, 32)
FILES[".plots"]='{["next"]=7,["done"]=0,["hunter"]=true,["builderId"]=14,["byId"]={["9"]=1,["10"]=2,["12"]=4,["13"]=5,["5"]=6,["11"]=3}}'
MAX_IDLES=1
''')
L.eval('{runFactory()}')
want = [("advancedperipherals:geo_scanner", 1)]
L.execute('IDLES=0 MAX_IDLES=4 PAD_OCCUPIED=true NEXT_ID=13')
L.execute('INBOX={{id=14,msg={type="materials",id=14,n=1,fuel=0,items={%s}}}}' % ",".join('{"%s",%d}' % i for i in want))
L.eval('{runFactory()}')
g = L.globals()
given = missing = None
for m in g.OUTBOX.values():
    if m.msg.type == "materials_ready":
        given, missing = dict(m.msg.given), dict(m.msg.missing or {})
crafted = sorted(set(g.CRAFTED.values()))
print("given:", given, "| missing:", missing)
print("crafted:", crafted)
bad = [l for l in g.LOG.values() if "did not work" in l or "PROBLEM" in l]
ok = given is not None and all(given.get(n) == c for n, c in want) and not missing and not bad \
    and "minecraft:observer" in crafted and "advancedperipherals:peripheral_casing" in crafted
print("problems:", bad)
print("PASS" if ok else "FAILED")
sys.exit(0 if ok else 1)
