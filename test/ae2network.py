"""The ME network's parts (docs/ae2-bootstrap.md): the factory's grids
against AE2's own patterns (generated recipe data, branch 1.21.1) and
Advanced Peripherals' ME Bridge (dev/0.8-1.21.1), shaped ones trimmed as the
game trims them, shapeless ones matched in any order. None has been crafted
in the pack yet: this shows the factory plans and crafts the network from
what the AE2 bench and the certus farm hand in (crystals, dust, processors,
fluix), and that it reports those as missing rather than inventing them.

    python3 test/ae2network.py
"""
import os, sys
import lupa

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def lua():
    L = lupa.LuaRuntime(unpack_returned_tuples=True)
    L.execute("MODEM_ON=true")
    L.execute(open(os.path.join(HERE, "fharness.lua")).read().replace("/home/claude/turtles", ROOT))
    return L


MATCHER = r'''
local I, C, R, G = "minecraft:iron_ingot", "minecraft:copper_ingot", "minecraft:redstone", "minecraft:glass"
local GS, NQ, P, CT = "minecraft:glowstone_dust", "minecraft:quartz", "minecraft:piston", "minecraft:crafting_table"
local CQ, CD, F, FD = "ae2:certus_quartz_crystal", "ae2:certus_quartz_dust", "ae2:fluix_crystal", "ae2:fluix_dust"
local LP, CP, EP = "ae2:logic_processor", "ae2:calculation_processor", "ae2:engineering_processor"
local QG, FB, CAB, FIB = "ae2:quartz_glass", "ae2:fluix_block", "ae2:fluix_glass_cable", "ae2:quartz_fiber"
local AC, FC, K1, K4 = "ae2:annihilation_core", "ae2:formation_core", "ae2:cell_component_1k", "ae2:cell_component_4k"
local SKY, HOU, TERM, IFACE = "ae2:smooth_sky_stone_block", "ae2:item_cell_housing", "ae2:terminal", "ae2:interface"
local PAN, CU, CTERM = "ae2:semi_dark_monitor", "ae2:crafting_unit", "ae2:crafting_terminal"
local BARS, RB, CAS = "minecraft:iron_bars", "minecraft:redstone_block", "advancedperipherals:peripheral_casing"
local function plank(n) return n:sub(-7) == "_planks" end
-- shaped: rows as AE2 writes them; shapeless: a list of ingredients
REAL = {
  { out = "ae2:controller", n = 1, rows = { { SKY, F, SKY }, { F, EP, F }, { SKY, F, SKY } } },
  { out = "ae2:drive", n = 1, rows = { { I, EP, I }, { CAB, "", CAB }, { I, EP, I } } },
  { out = HOU, n = 1, rows = { { QG, R, QG }, { R, "", R }, { I, C, I } } },
  { out = K1, n = 1, rows = { { R, CQ, R }, { CQ, LP, CQ }, { R, CQ, R } } },
  { out = K4, n = 1, rows = { { R, CP, R }, { K1, QG, K1 }, { R, K1, R } } },
  { out = "ae2:item_storage_cell_1k", n = 1, any = { HOU, K1 } },
  { out = "ae2:item_storage_cell_4k", n = 1, any = { HOU, K4 } },
  { out = QG, n = 4, rows = { { CD, G, CD }, { G, CD, G }, { CD, G, CD } } },
  { out = FB, n = 1, rows = { { F, F }, { F, F } } },
  { out = FIB, n = 3, rows = { { G, G, G }, { CD, CD, CD }, { G, G, G } } },
  { out = CAB, n = 4, any = { FIB, F, F } },
  { out = AC, n = 2, rows = { { NQ, FD, LP } } },
  { out = FC, n = 2, rows = { { CQ, FD, LP } } },
  { out = PAN, n = 3, rows = { { "", GS, QG }, { I, R, QG }, { "", GS, QG } } },
  { out = TERM, n = 1, any = { FC, PAN, LP, AC } },
  { out = CTERM, n = 1, any = { TERM, CT, CP } },
  { out = "ae2:pattern_encoding_terminal", n = 1, any = { EP, CTERM } },
  { out = CU, n = 1, rows = { { I, CP, I }, { CAB, LP, CAB }, { I, CP, I } } },
  { out = "ae2:1k_crafting_storage", n = 1, any = { CU, K1 } },
  { out = "ae2:molecular_assembler", n = 1, rows = { { I, QG, I }, { AC, CT, FC }, { I, QG, I } } },
  { out = "ae2:pattern_provider", n = 1, rows = { { I, CT, I }, { AC, "", FC }, { I, CT, I } } },
  { out = IFACE, n = 1, rows = { { I, G, I }, { AC, "", FC }, { I, G, I } } },
  { out = "ae2:blank_pattern", n = 2, rows = { { QG, GS, QG }, { GS, CQ, GS }, { I, C, I } } },
  { out = "ae2:storage_bus", n = 1, any = { P, IFACE, P } },
  { out = "ae2:energy_cell", n = 1, rows = { { CQ, FD, CQ }, { FD, QG, FD }, { CQ, FD, CQ } } },
  { out = "ae2:growth_accelerator", n = 1, rows = { { I, CAB, I }, { QG, FB, QG }, { I, CAB, I } } },
  { out = "ae2:energy_acceptor", n = 1, rows = { { I, QG, I }, { QG, C, QG }, { I, QG, I } } },
  { out = CAS, n = 1, rows = { { I, BARS, I }, { BARS, RB, BARS }, { I, BARS, I } } },
  { out = "advancedperipherals:me_bridge", n = 1, rows = { { FB, IFACE, FB }, { IFACE, CAS, IFACE }, { FB, IFACE, FB } } },
  { out = CT, n = 1, rows = { { plank, plank }, { plank, plank } } },
  { out = RB, n = 1, rows = { { R, R, R }, { R, R, R }, { R, R, R } } },
  { out = BARS, n = 16, rows = { { I, I, I }, { I, I, I } } },
  { out = "minecraft:oak_planks", n = 4, rows = { { "minecraft:oak_log" } } },
  { out = P, n = 1, rows = { { plank, plank, plank }, { "minecraft:cobblestone", I, "minecraft:cobblestone" },
    { "minecraft:cobblestone", R, "minecraft:cobblestone" } } },
}
local SLOTS = { { 1, 2, 3 }, { 5, 6, 7 }, { 9, 10, 11 } }
local craft = turtle.craft
turtle.craft = function()
  local items = INV.turtle_3.items
  local r1, r2, c1, c2 = 4, 0, 4, 0
  local bag, k = {}, 64
  for r = 1, 3 do for c = 1, 3 do local it = items[SLOTS[r][c]] if it then
    r1 = math.min(r1, r) r2 = math.max(r2, r) c1 = math.min(c1, c) c2 = math.max(c2, c)
    bag[#bag + 1] = it.name k = math.min(k, it.count) end end end
  table.sort(bag)
  for _, real in ipairs(REAL) do
    local same
    if real.any then
      local want = {}
      for i, v in ipairs(real.any) do want[i] = v end
      table.sort(want)
      same = #want == #bag
      for i = 1, #want do if want[i] ~= bag[i] then same = false end end
    else
      same = (r2 - r1 + 1) == #real.rows and (c2 - c1 + 1) == #real.rows[1]
      if same then
        for r = r1, r2 do for c = c1, c2 do
          local it, want = items[SLOTS[r][c]], real.rows[r - r1 + 1][c - c1 + 1]
          local name = it and it.name or ""
          if type(want) == "function" then if name == "" or not want(name) then same = false end
          elseif name ~= want then same = false end
        end end
      end
    end
    if same then
      k = math.min(k, math.floor(64 / real.n))
      for r = 1, 3 do for c = 1, 3 do
        local s = SLOTS[r][c]
        if items[s] then items[s].count = items[s].count - k if items[s].count == 0 then items[s] = nil end end
      end end
      if items[SEL] then return false, "output slot taken" end
      items[SEL] = { name = real.out, count = real.n * k }
      CRAFTED[#CRAFTED + 1] = real.out
      return true
    end
  end
  return craft()
end
'''

STOCK = r'''
C1, C2 = "minecraft:chest_0", "minecraft:chest_1"
for _ = 1, 3 do put(C1, "minecraft:iron_ingot", 64) end
put(C1, "minecraft:copper_ingot", 32) put(C1, "minecraft:redstone", 64) put(C1, "minecraft:glass", 64)
put(C1, "minecraft:glowstone_dust", 16) put(C1, "minecraft:quartz", 32) put(C1, "minecraft:oak_log", 16)
put(C1, "minecraft:cobblestone", 32) put(C1, "minecraft:coal", 64)
-- what the AE2 bench and the farm hand in
put(C2, "ae2:certus_quartz_crystal", 64) put(C2, "ae2:certus_quartz_dust", 64) put(C2, "ae2:fluix_crystal", 64)
put(C2, "ae2:fluix_dust", 32) put(C2, "ae2:logic_processor", 32) put(C2, "ae2:calculation_processor", 16)
put(C2, "ae2:engineering_processor", 16) put(C2, "ae2:smooth_sky_stone_block", 8)
FILES[".plots"]='{["next"]=7,["done"]=0,["hunter"]=true,["builderId"]=14,["byId"]={["9"]=1,["10"]=2,["12"]=4,["13"]=5,["5"]=6,["11"]=3}}'
MAX_IDLES=1
'''

fails = []


def check(what, ok):
    print(("ok   " if ok else "FAIL ") + what)
    if not ok:
        fails.append(what)


def ask(want, stock=STOCK, extra=""):
    L = lua()
    L.execute(MATCHER)
    L.execute(stock + extra)
    L.eval('{runFactory()}')
    L.execute('IDLES=0 MAX_IDLES=4 PAD_OCCUPIED=true NEXT_ID=13')
    L.execute('INBOX={{id=14,msg={type="materials",id=14,n=1,fuel=0,items={%s}}}}'
              % ",".join('{"%s",%d}' % i for i in want))
    L.eval('{runFactory()}')
    g = L.globals()
    given = missing = None
    for m in g.OUTBOX.values():
        if m.msg.type == "materials_ready":
            given, missing = dict(m.msg.given), dict(m.msg.missing or {})
    crafted = list(g.CRAFTED.values())
    bad = [l for l in g.LOG.values() if "did not work" in l or "PROBLEM" in l or "Problem" in l]
    ask.log = list(g.LOG.values())
    return given or {}, missing or {}, crafted, bad


# (a) the network itself
want = [("ae2:controller", 1), ("ae2:drive", 1), ("ae2:item_storage_cell_1k", 2), ("ae2:crafting_terminal", 1),
        ("ae2:fluix_glass_cable", 8), ("ae2:storage_bus", 1)]
given, missing, crafted, bad = ask(want)
print("a: given", given, "missing", missing)
check("(a) controller, drive, two 1k cells, crafting terminal, cable, storage bus",
      all(given.get(n) == c for n, c in want) and not missing and not bad)
check("(a) quartz glass, fiber, cores and panels were made on the way",
      all(x in crafted for x in ("ae2:quartz_glass", "ae2:quartz_fiber", "ae2:formation_core",
                                  "ae2:annihilation_core", "ae2:semi_dark_monitor", "minecraft:crafting_table")))

# (b) autocrafting
want = [("ae2:1k_crafting_storage", 1), ("ae2:molecular_assembler", 2), ("ae2:pattern_provider", 1),
        ("ae2:pattern_encoding_terminal", 1), ("ae2:blank_pattern", 4)]
given, missing, crafted, bad = ask(want)
print("b: given", given, "missing", missing)
check("(b) crafting storage, assemblers, provider, encoding terminal, patterns",
      all(given.get(n) == c for n, c in want) and not missing and not bad)
check("(b) a crafting unit went into the crafting storage", "ae2:crafting_unit" in crafted)

# (c) the ME Bridge, and the growth accelerator and energy cell
want = [("advancedperipherals:me_bridge", 1), ("ae2:growth_accelerator", 1), ("ae2:energy_cell", 1),
        ("ae2:cell_component_4k", 1)]
given, missing, crafted, bad = ask(want)
print("c: given", given, "missing", missing)
check("(c) ME Bridge, growth accelerator, energy cell, 4k component",
      all(given.get(n) == c for n, c in want) and not missing and not bad)
check("(c) the casing from a redstone block and bars; four interfaces, fluix blocks",
      all(x in crafted for x in ("advancedperipherals:peripheral_casing", "minecraft:redstone_block",
                                  "minecraft:iron_bars", "ae2:interface", "ae2:fluix_block")))

# nothing made by a machine is invented: no processors, no fluix -> reported missing
bare = STOCK.replace('put(C2, "ae2:logic_processor", 32)', "").replace('put(C2, "ae2:fluix_crystal", 64)', "")
given, missing, crafted, bad = ask([("ae2:interface", 1)], stock=bare)
print("bare: given", given, "missing", missing)
check("with no processors or fluix the factory says what the bench must make",
      not given.get("ae2:interface") and any("short of" in l and "logic processor" in l for l in ask.log))

print("PASS" if not fails else "FAILED: %d" % len(fails))
sys.exit(1 if fails else 0)
