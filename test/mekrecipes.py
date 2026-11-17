"""The Mekanism power parts: the factory's grids against Mekanism's own
patterns (from Mekanism's generated 1.21 recipe data), written out
separately here (energy tablet, basic energy cube,
universal cable, wind generator). None has been crafted in the pack yet: this
only shows the factory can plan and craft them from the parts.

    python3 test/mekrecipes.py
"""
import os, sys
import lupa

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
L = lupa.LuaRuntime(unpack_returned_tuples=True)
L.execute("MODEM_ON=true")
L.execute(open(os.path.join(HERE, "fharness.lua")).read().replace("/home/claude/turtles", ROOT))
L.execute('''
local R, G, A, I, O = "minecraft:redstone", "minecraft:gold_ingot", "mekanism:alloy_infused", "minecraft:iron_ingot", "alltheores:osmium_ingot"
local S, K, T, C = "alltheores:steel_ingot", "mekanism:steel_casing", "mekanism:energy_tablet", "mekanism:basic_control_circuit"
local GL, EC = "minecraft:glass", "mekanism:electrolytic_core"
-- Mekanism's patterns, row by row ("" = empty)
local REAL = {
  { out = "mekanism:energy_tablet", n = 1, rows = { { R, G, R }, { A, G, A }, { R, G, R } } },
  { out = "mekanism:basic_energy_cube", n = 1, rows = { { R, T, R }, { I, K, I }, { R, T, R } } },
  { out = "mekanismgenerators:wind_generator", n = 1, rows = { { "", O, "" }, { O, A, O }, { T, C, T } } },
  { out = "mekanism:basic_universal_cable", n = 8, rows = { { S, R, S }, { "", "", "" }, { "", "", "" } } },
  { out = "mekanism:steel_casing", n = 1, rows = { { S, GL, S }, { GL, O, GL }, { S, GL, S } } },
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
C1, D1 = "minecraft:chest_0", "minecraft:chest_1"
put(C1, R, 64) put(C1, G, 16) put(C1, A, 16) put(C1, I, 16) put(C1, O, 16) put(C1, S, 16) put(C1, C, 4) put(C1, GL, 16) put(C1, EC, 1)
put(C1, "minecraft:coal", 64)
FILES[".plots"]='{["next"]=7,["done"]=0,["hunter"]=true,["builderId"]=14,["byId"]={["9"]=1,["10"]=2,["12"]=4,["13"]=5,["5"]=6,["11"]=3}}'
MAX_IDLES=1
''')
L.eval('{runFactory()}')
want = [("mekanism:basic_energy_cube", 1), ("mekanismgenerators:wind_generator", 1), ("mekanism:basic_universal_cable", 8)]
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
    and "mekanism:energy_tablet" in crafted and "mekanism:steel_casing" in crafted
print("problems:", bad)
print("PASS" if ok else "FAILED")
sys.exit(0 if ok else 1)
