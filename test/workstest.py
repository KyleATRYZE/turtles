"""The works computer (works.lua) and Crafty's probe: the foundry on the cable.

A mock cable: a store (a chest and a controller), an Enrichment Chamber
that turns 3 raw ore into 4 dust and pushes it on into the Energized
Smelter, which smelts it; a Metallurgic Infuser with its infusion face.
Items move only by pushItems/pullItems between names, as over CC's cable.

    cd test && python3 workstest.py
"""
import os, lupa
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(HERE)
fails = []
def check(what, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + what + (" | " + str(detail) if detail != "" else ""))
    if not ok: fails.append(what)

WORLD = r'''
WORKS_TEST = true
INV = {}
local function inv(n, size) INV[n] = INV[n] or { size = size or 27, items = {} } return INV[n] end
function add(n, item, c) local I = inv(n) for s = 1, I.size do local it = I.items[s]
  if not it then I.items[s] = { name = item, count = math.min(64, c) } c = c - math.min(64, c)
  elseif it.name == item and it.count < 64 then local t = math.min(64 - it.count, c) it.count = it.count + t c = c - t end
  if c <= 0 then return end end end
function total(item) local n = 0 for name, I in pairs(INV) do if not name:find("mekanism") then
  for _, it in pairs(I.items) do if it.name == item then n = n + it.count end end end end return n end
inv("minecraft:chest_0") inv("sophisticatedstorage:controller_0", 54)
-- machines: input slot 1, output slot 2 (as the floor face shows them)
M = {}
local function machine(name, accepts, make)
  M[name] = { input = nil, output = nil, accepts = accepts, make = make, modes = {}, eject = true, tank = { name = nil, amount = 0 } }
end
machine("mekanism:enrichment_chamber_0", function(i) return i:find("raw_") or i == "mekanism:dust_obsidian" end,
  function(i, n) if i:find("raw_") then return i:gsub("raw_", "") .. "_dust", math.floor(n * 4 / 3) end end)
machine("mekanism:energized_smelter_0", function(i) return i:find("_dust") end,
  function(i, n) return i:gsub("_dust", "_ingot"), n end)
machine("mekanism:metallurgic_infuser_0", function(i) return i == "minecraft:iron_ingot" or i == "mekanism:enriched_iron"
  or i == "minecraft:copper_ingot" end, nil)
machine("mekanism:metallurgic_infuser_1", function(i) return false end, nil)     -- the infusion face
M["mekanism:metallurgic_infuser_1"] = M["mekanism:metallurgic_infuser_0"]        -- (the same machine)
INFUSE_ITEMS = { ["minecraft:coal"] = { "mekanism:carbon", 10 }, ["minecraft:redstone"] = { "mekanism:redstone", 10 } }
INFUSER_EXTRA = "mekanism:metallurgic_infuser_1"
local function work()                                -- what a few seconds of running does
  local c, s, f = M["mekanism:enrichment_chamber_0"], M["mekanism:energized_smelter_0"], M["mekanism:metallurgic_infuser_0"]
  if c.input then
    local out, n = c.make(c.input.name, c.input.count)
    c.input = nil
    if c.eject and s.accepts(out) then s.input = { name = out, count = n } else c.output = { name = out, count = n } end
  end
  if s.input then local out, n = s.make(s.input.name, s.input.count) s.input = nil
    s.output = { name = out, count = (s.output and s.output.count or 0) + n } end
  if f.input then
    local n = math.min(f.input.count, math.floor(f.tank.amount / 10))
    local out = f.input.name == "minecraft:iron_ingot" and "mekanism:enriched_iron"
      or f.input.name == "mekanism:enriched_iron" and "alltheores:steel_dust" or "mekanism:alloy_infused"
    f.tank.amount = f.tank.amount - n * 10
    f.input.count = f.input.count - n
    if f.input.count == 0 then f.input = nil end
    if n > 0 then f.output = { name = out, count = (f.output and f.output.count or 0) + n } end
  end
end
SLEPT = 0
function sleep() SLEPT = SLEPT + 1 if SLEPT > 500 then error("stuck", 0) end work() end
CLOCK = 0
os = { clock = function() CLOCK = CLOCK + 1 return CLOCK end, getComputerID = function() return 77 end }
function print() end
peripheral = {
  hasType = function(n, t) return INV[n] ~= nil and t == "inventory" end,
  call = function(n, method, a, b, c, d)
    local m = M[n]
    if m then
      if method == "setMode" then m.modes[b] = c return
      elseif method == "setEjecting" then m.eject = b return
      elseif method == "setRedstoneMode" then return
      elseif method == "getInput" then return m.input and { name = m.input.name, count = m.input.count } or { name = "minecraft:air", count = 0 }
      elseif method == "getOutput" then return m.output and { name = m.output.name, count = m.output.count } or { name = "minecraft:air", count = 0 }
      elseif method == "getInfuseType" then return { name = m.tank.name or "mekanism:empty", amount = m.tank.amount }
      elseif method == "dumpInfuseType" then m.tank = { amount = 0 } return end
      error("no method " .. method)
    end
    local I = INV[n] or error("no peripheral " .. n)
    if method == "list" then local out = {} for s, it in pairs(I.items) do out[s] = { name = it.name, count = it.count } end return out end
    if method == "pushItems" then                      -- a = target, b = slot, c = limit
      local it = I.items[b] if not it then return 0 end
      local lim = math.min(c or 64, it.count)
      local T = M[a]
      if T then
        local moved = 0
        if a == INFUSER_EXTRA and INFUSE_ITEMS[it.name] then
          local g = INFUSE_ITEMS[it.name]
          T.tank.name, T.tank.amount, moved = g[1], T.tank.amount + g[2] * lim, lim
        elseif a ~= INFUSER_EXTRA and T.accepts(it.name) and (not T.input or T.input.name == it.name) then
          moved = lim
          T.input = { name = it.name, count = (T.input and T.input.count or 0) + lim }
        end
        it.count = it.count - moved if it.count == 0 then I.items[b] = nil end
        return moved
      end
      add(a, it.name, lim) it.count = it.count - lim if it.count == 0 then I.items[b] = nil end return lim
    end
    if method == "pullItems" then                      -- a = source, b = slot
      local S = M[a]
      if S then
        if b ~= 2 or not S.output then return 0 end
        local c = S.output.count
        add(n, S.output.name, c)
        S.output = nil
        return c
      end
      return 0
    end
    error("bad method " .. method)
  end }
'''
def works():
    L = lupa.LuaRuntime(unpack_returned_tuples=True)
    L.execute(WORLD)
    W = L.execute("return dofile(%r)" % os.path.join(ROOT, "works.lua"))
    L.globals().W = W
    L.execute('''W.scan({ "minecraft:chest_0", "sophisticatedstorage:controller_0", "mekanism:enrichment_chamber_0",
      "mekanism:energized_smelter_0", "mekanism:metallurgic_infuser_0", "mekanism:metallurgic_infuser_1",
      "minecraft:barrel_3", "computercraft:monitor_2", "turtle_40" })''')
    return L

L = works()
check("the machines found on the cable by name; the store is the chest and the controller (not the barrel, a turtle or a screen)",
      L.eval("W.m.chamber") == "mekanism:enrichment_chamber_0" and L.eval("W.m.smelter") == "mekanism:energized_smelter_0"
      and L.eval("W.m.infuser") == "mekanism:metallurgic_infuser_0" and L.eval("W.m.extra") == "mekanism:metallurgic_infuser_1"
      and L.eval("#W.stores") == 2 and L.eval("W.stores[1]") == "sophisticatedstorage:controller_0")
L.execute("W.setup()")
check("set up: the floor face takes items in and gives results out; the chamber pushes on into the smelter; the infusion face",
      L.eval('M["mekanism:enrichment_chamber_0"].modes.BOTTOM') == "INPUT_OUTPUT"
      and L.eval('M["mekanism:enrichment_chamber_0"].modes.LEFT') == "OUTPUT"
      and L.eval('M["mekanism:energized_smelter_0"].modes.RIGHT') == "INPUT"
      and L.eval('M["mekanism:metallurgic_infuser_0"].modes.RIGHT') == "EXTRA")
L.execute('add("minecraft:chest_0", "minecraft:raw_iron", 50)')
ok, why, made = L.execute('return W.run({ kind = "ore", item = "minecraft:raw_iron", n = 48 })')
check("an ore job: 48 raw iron from the store, through the chamber and the smelter, 64 ingots back in the store",
      ok is True and L.eval('total("minecraft:iron_ingot")') == 64 and L.eval('total("minecraft:raw_iron")') == 2, (ok, why))
check("  and it says what it made", made is not None and made["minecraft:iron_ingot"] == 64)
L.execute('add("minecraft:chest_0", "minecraft:copper_ingot", 16) add("minecraft:chest_0", "minecraft:redstone", 32)')
ok, why, made = L.execute('return W.run({ kind = "alloy", n = 16 })')
check("a make job: infused alloy from copper, the redstone in by the infusion face", ok is True
      and L.eval('total("mekanism:alloy_infused")') == 16 and L.eval('total("minecraft:redstone")') == 16, (ok, why))
L.execute('add("minecraft:chest_0", "minecraft:iron_ingot", 0) add("minecraft:chest_0", "minecraft:coal", 10)')
ok, why, made = L.execute('return W.run({ kind = "steel", n = 4 })')
check("steel: two passes (enriched iron, then steel dust), carbon from coal", ok is True
      and L.eval('total("alltheores:steel_dust")') == 4, (ok, why, L.eval('total("mekanism:enriched_iron")')))
ok, why, _ = L.execute('return W.run({ kind = "ore", item = "minecraft:raw_gold", n = 48 })')
check("no ore in the store: the job fails and says why", ok is False and "no minecraft:raw_gold" in why, why)
check("its readiness for the factory", L.eval("W.ready().chamber") is True and L.eval("W.ready().infuser") is True
      and L.eval("W.ready().cable") is True)

# ---------------------------------------------------------------- Crafty's probe
FAC = open(os.path.join(ROOT, "factory.lua")).read()
check("probe Crafty: an order that pushes an item into a machine by name and pulls it back",
      'c.cmd == "probe"' in FAC and "function K.probe(name)" in FAC and 'K.pushTo(name, item, 1)' in FAC)
probe = FAC[FAC.index("K.PROBE_ITEMS = {"):FAC.index("-- Everything in one slot of target back into storage.")]
for push_ok, want in ((True, "push raw iron in: yes; pull it back out: yes"), (False, "push in: no")):
    L = lupa.LuaRuntime(unpack_returned_tuples=True)
    L.execute('''K = {} modem = { getNamesRemote = function() return { "minecraft:chest_0", "mekanism:enrichment_chamber_3" } end }
peripheral = { getType = function() return "enrichmentChamber" end, hasType = function() return false end }
function stockTotals() return { ["minecraft:raw_iron"] = 5 } end
function shortName(n) return (n:gsub("^.*:", ""):gsub("_", " ")) end
PUSH = %s
function K.pushTo(t, item, n) return PUSH and 1 or 0 end
function K.pullBack(t, slot) return slot == 1 and 1 or 0 end''' % ("true" if push_ok else "false"))
    L.execute(probe)
    r = L.eval("K.probe()")
    check("probe: " + want, want in r and "mekanism:enrichment_chamber_3" in r and "inventory methods: no" in r, r)
check("Crafty opens rednet on its wired modem too (the works computer has no ender modem)",
      "pcall(rednet.open, side)" in FAC)
check("a load short of steel, circuits or alloy becomes a make job for the foundry",
      "K.wantMade[name] = math.max" in FAC and "kind = K.MAKES[item]" in FAC)
UPD = open(os.path.join(ROOT, "update.lua")).read()
check("works.lua: in the manifest, run by the works role, skipped by turtles",
      "works.lua" in open(os.path.join(ROOT, "manifest.txt")).read() and 'job = \'shell.run("works")\'' in UPD
      and UPD.count('["works.lua"] = true') == 5)

print("PASS" if not fails else "FAILED: %d" % len(fails))
