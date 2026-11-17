"""The quartz line's parts: the factory's grids against the mods' own patterns
(Actually Additions 1.21, Create mc1.21.1, AllTheOres 1.21: their generated
recipe files), with the ore hammer coming back from the grid as a tool does.
None has been crafted in the pack yet: this shows the factory can plan and
craft them from what it has, and that a tool is not counted once per craft.

    python3 test/quartzrecipes.py
"""
import os, sys
import lupa

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
L = lupa.LuaRuntime(unpack_returned_tuples=True)
L.execute("MODEM_ON=true")
L.execute(open(os.path.join(HERE, "fharness.lua")).read().replace("/home/claude/turtles", ROOT))
L.execute('''
local I, R, S, CB = "minecraft:iron_ingot", "minecraft:redstone", "minecraft:stick", "minecraft:cobblestone"
local BQ, IC, COAL = "actuallyadditions:black_quartz", "actuallyadditions:iron_casing", "minecraft:coal"
local AN, NUG, AL, SH = "minecraft:andesite", "minecraft:iron_nugget", "create:andesite_alloy", "create:shaft"
local IB, HAM, PLATE = "minecraft:iron_block", "alltheores:iron_ore_hammer", "alltheores:iron_plate"
local CAS, PROP = "create:andesite_casing", "create:propeller"
local function plank(n) return n:sub(-7) == "_planks" end
-- the mods' patterns, trimmed as the game trims them ("" = empty)
local REAL = {
  { out = IC, n = 1, rows = { { I, S, I }, { S, BQ, S }, { I, S, I } } },
  { out = "actuallyadditions:atomic_reconstructor", n = 1, rows = { { I, R, I }, { R, IC, R }, { I, R, I } } },
  { out = "actuallyadditions:coal_generator", n = 1, rows = { { CB, IC, CB }, { CB, COAL, CB }, { CB, IC, CB } } },
  { out = AL, n = 1, rows = { { NUG, AN }, { AN, NUG } } },
  { out = SH, n = 8, rows = { { AL }, { AL } } },
  { out = HAM, n = 1, rows = { { "", IB, S }, { "", S, IB }, { S, "", "" } } },
  { out = PLATE, n = 1, rows = { { HAM, I }, { I, "" } }, tool = HAM },
  { out = PROP, n = 1, rows = { { "", PLATE, "" }, { PLATE, AL, PLATE }, { "", PLATE, "" } } },
  { out = "create:encased_fan", n = 1, rows = { { SH }, { CAS }, { PROP } } },
  { out = "create:water_wheel", n = 1, rows = { { plank, plank, plank }, { plank, SH, plank }, { plank, plank, plank } } },
  { out = NUG, n = 9, rows = { { I } } },
  { out = IB, n = 1, rows = { { I, I, I }, { I, I, I }, { I, I, I } } },
  { out = "minecraft:diamond_shovel", n = 1, rows = { { "minecraft:diamond" }, { S }, { S } } },
}
local SLOTS = { { 1, 2, 3 }, { 5, 6, 7 }, { 9, 10, 11 } }
local craft = turtle.craft
HAMMER_USES = 0
turtle.craft = function()
  local items = INV.turtle_3.items
  local r1, r2, c1, c2 = 4, 0, 4, 0
  for r = 1, 3 do for c = 1, 3 do if items[SLOTS[r][c]] then
    r1 = math.min(r1, r) r2 = math.max(r2, r) c1 = math.min(c1, c) c2 = math.max(c2, c) end end end
  for _, real in ipairs(REAL) do
    local same = (r2 - r1 + 1) == #real.rows and (c2 - c1 + 1) == #real.rows[1]
    local k = 64
    if same then
      for r = r1, r2 do for c = c1, c2 do
        local it, want = items[SLOTS[r][c]], real.rows[r - r1 + 1][c - c1 + 1]
        local name = it and it.name or ""
        if type(want) == "function" then if name == "" or not want(name) then same = false end
        elseif name ~= want then same = false end
        if it then k = math.min(k, it.count) end
      end end
    end
    if same then
      k = math.min(k, math.floor(64 / real.n))
      if real.tool then k = 1 HAMMER_USES = HAMMER_USES + 1 end
      for r = r1, r2 do for c = c1, c2 do
        local s = SLOTS[r][c]
        if items[s] and items[s].name ~= real.tool then
          items[s].count = items[s].count - k
          if items[s].count == 0 then items[s] = nil end
        end
      end end
      if items[SEL] then return false, "output slot taken" end
      items[SEL] = { name = real.out, count = real.n * k }
      CRAFTED[#CRAFTED + 1] = real.out
      return true
    end
  end
  return craft()
end
C1 = "minecraft:chest_0"
for _ = 1, 2 do put(C1, I, 64) end
put(C1, R, 32) put(C1, S, 32) put(C1, CB, 32) put(C1, BQ, 16) put(C1, COAL, 64)
put(C1, AN, 32) put(C1, "regions_unexplored:mauve_planks", 16) put(C1, CAS, 1) put(C1, "minecraft:diamond", 4)
FILES[".plots"]='{["next"]=7,["done"]=0,["hunter"]=true,["builderId"]=14,["byId"]={["9"]=1,["10"]=2,["12"]=4,["13"]=5,["5"]=6,["11"]=3}}'
MAX_IDLES=1
''')
L.eval('{runFactory()}')
want = [("actuallyadditions:atomic_reconstructor", 1), ("actuallyadditions:coal_generator", 2),
        ("create:andesite_alloy", 1), ("create:water_wheel", 1), ("create:encased_fan", 1),
        ("minecraft:diamond_shovel", 1)]
L.execute('IDLES=0 MAX_IDLES=4 PAD_OCCUPIED=true NEXT_ID=13')
L.execute('INBOX={{id=14,msg={type="materials",id=14,n=1,fuel=0,items={%s}}}}' % ",".join('{"%s",%d}' % i for i in want))
L.eval('{runFactory()}')
g = L.globals()
given, missing = {}, {}
for m in g.OUTBOX.values():
    if m.msg.type == "materials_ready":
        given, missing = dict(m.msg.given), dict(m.msg.missing or {})
log = list(g.LOG.values())
crafted = list(g.CRAFTED.values())
fails = []
def check(what, ok):
    print(("ok   " if ok else "FAIL ") + what)
    if not ok: fails.append(what)
print("given:", given, "missing:", missing)
bad = [l for l in log if "did not work" in l or "Problem" in l or "Ran out" in l]
print("problems:", bad)
check("every part asked for was handed over", all(given.get(n) == c for n, c in want) and not missing)
check("no recipe failed", not bad)
check("one hammer made, used four times (a tool is not used up)", crafted.count("alltheores:iron_ore_hammer") == 1 and g.HAMMER_USES == 4)
check("iron casings were made for the reconstructor and both generators", "actuallyadditions:iron_casing" in crafted)
hammers = L.eval('''(function() local n = 0
  for _, inv in pairs(INV) do for _, it in pairs(inv.items or {}) do
    if it.name == "alltheores:iron_ore_hammer" then n = n + it.count end end end
  return n end)()''')
check("the hammer is back in stock afterwards", hammers == 1)
check("the comparator asks for real quartz only", 'Q = "minecraft:quartz"' in open(os.path.join(ROOT, "factory.lua"), encoding="latin-1").read())
print("PASS" if not fails else "FAILED: %d" % len(fails))
sys.exit(1 if fails else 0)
