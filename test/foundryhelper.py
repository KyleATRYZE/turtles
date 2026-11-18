"""The whole helper (helper.lua + foundry.lua) on an ore job, in the real
building plan: from the launch pad, into the foundry bay by the big door,
the chamber and smelter found and set up, out for ore and redstone, back in,
the line run, the ingots handed in on the pad.

    python3 test/foundryhelper.py

Uses the miners' world (harness.lua, bworld.lua), the as-fitted factory
plans from blueprints/, and the machines from foundrysim.lua.
"""
import os, sys
import lupa

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
fails = []


def check(what, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + what + (f"  [{detail}]" if detail else ""))
    if not ok:
        fails.append(what)


def run(order, stock, label="foundry1", fuel=3000, extra=""):
    L = lupa.LuaRuntime(unpack_returned_tuples=True)
    L.execute(f"START_D=3; START_FUEL={fuel}")
    src = open(os.path.join(HERE, "harness.lua")).read().replace("/home/claude/turtles", ROOT)
    L.execute(src)
    L.execute(open(os.path.join(HERE, "bworld.lua")).read())
    L.execute("EMBED = true")
    L.execute(open(os.path.join(HERE, "foundrysim.lua")).read())
    g = L.globals()
    g.ROOT = ROOT
    L.execute("ORDER = " + order)
    L.execute('''
      package.path = ROOT .. "/?.lua;" .. package.path
      package.preload.swarm = function() return {
        open = function() return true end, report = function(r) LAST = r end,
        runWithCommands = function(task) task() return nil end, pinVersion = function() end } end
      LABEL = "''' + label + '''"
      -- the plans, as the turtles download them
      http = { get = function(url)
        local name = url:match("blueprints/([%w_]+)%.txt")
        local f = assert(io.open(ROOT .. "/blueprints/" .. name .. ".txt"))
        local text = f:read("a") f:close()
        PLANS = (PLANS or "") .. name .. " "
        return { readAll = function() return text end, close = function() end }
      end }
      -- the building's corner, and the machines standing in it (both facing west)
      local F = dofile(ROOT .. "/foundry.lua")
      OX, OY, OZ = F.SITE.ox, F.SITE.oy, F.SITE.oz
      local function machine(item, x, y, z)
        addMachine(item, OX + x, OY + y, OZ + z, 2)
        setSpecial(OX + x, OY + y, OZ + z, item)
      end
      machine("mekanism:enrichment_chamber", 41, 1, 12)
      machine("mekanism:energized_smelter", 41, 1, 11)
      -- the floor of the bay (so "the ground" is where it should be)
      for x = 20, 46 do for z = 2, 36 do setSpecial(OX + x, OY, OZ + z, "minecraft:polished_deepslate") end end

      for y = 16, 60 do setSpecial(-4462, y, 1521, false) end
      T.x, T.y, T.z = -4462, 15, 1521
      T.inv = {}
      TOOL = "minecraft:diamond_pickaxe"
      FS[".version"] = "abc123"
      FS["helper.state"] = textutils.serialize({})
      FS[".foundry"] = textutils.serialize({ on = true, queue = { ORDER }, m = {}, notes = {} })

      local DXX, DZZ = { [0] = 1, [1] = 0, [2] = -1, [3] = 0 }, { [0] = 0, [1] = 1, [2] = 0, [3] = -1 }
      local function front() return T.x + DXX[T.d], T.y, T.z + DZZ[T.d] end
      local function onPad() return T.x == -4462 and T.y == 15 and T.z == 1521 end
      for _, dir in ipairs({ "", "Up", "Down" }) do
        turtle["drop" .. dir] = function(n)
          local s = T.inv[T.sel]
          if not s then return false, "No items to drop" end
          n = math.min(n or s.count, s.count)
          local m, face = mekTarget(dir)
          local went
          if m then
            went = mekOffer(m, face, s.name, n)
            if went == 0 then return false, "No space for items" end
          elseif dir == "" and onPad() and getBlock(front()) == "computercraft:turtle_normal" then
            went = n                                   -- handed to the factory
            HANDED[s.name] = (HANDED[s.name] or 0) + n
            STOCK[s.name] = (STOCK[s.name] or 0) + n
          else
            went = n
            FLOOR[s.name] = (FLOOR[s.name] or 0) + n
          end
          s.count = s.count - went
          if s.count == 0 then T.inv[T.sel] = nil end
          return true
        end
        turtle["suck" .. dir] = function(n) return mekSuck(dir, n) end
      end
      local gt = peripheral.getType
      peripheral.call = function(side, method, ...)
        local m = mekTarget(side == "bottom" and "Down" or side == "top" and "Up" or "")
        if not m then error("No peripheral attached", 0) end
        return mekCall(m, method, ...)
      end
      os.clock = function() return CLOCK end
      os.date = function() return "00:00" end
      local hsleep = sleep
      sleep = function(n) mekTime(n or 0) return hsleep(n) end
      -- every move takes a moment too
      for _, name in ipairs({ "forward", "back", "up", "down" }) do
        local f = turtle[name]
        turtle[name] = function() mekTime(0.4) return f() end
      end

      -- the factory: calls the turtle down, then hands over what it has
      SENT, TRIPS = {}, 0
      rednet.broadcast = function(m, p)
        if m.type == "materials" then
          if not PENDING or PENDING.n ~= m.n then TRIPS = TRIPS + 1 end
          PENDING = m
          return
        end
        SENT[#SENT + 1] = m
      end
      rednet.send = function(to, m, p) SENT[#SENT + 1] = m end
      rednet.receive = function(proto, t)
        local m = PENDING
        if not m then error("IDLE", 0) end
        if onPad() then
          PENDING = nil
          local given, missing = {}, {}
          for _, l in ipairs(m.items) do
            local n = math.min(l[2], STOCK[l[1]] or 0)
            if n > 0 then giveTurtle(l[1], n) STOCK[l[1]] = STOCK[l[1]] - n given[l[1]] = n end
            if n < l[2] then missing[l[1]] = l[2] - n end
          end
          if m.fuel > 0 then giveTurtle("minecraft:coal", m.fuel) FUEL_GIVEN = (FUEL_GIVEN or 0) + m.fuel end
          return 3, { type = "materials_ready", forId = os.getComputerID(), n = m.n, given = given, missing = missing }
        end
        return 3, { type = "load_ready", forId = os.getComputerID(), n = m.n }
      end
    ''')
    for k, v in stock.items():
        L.execute(f'STOCK["{k}"] = {v}')
    if extra:
        L.execute(extra)
    f = L.eval(f'loadfile("{ROOT}/helper.lua")')
    r = L.eval('function(f) return {pcall(f)} end')(f)
    return L, g, list(r.values())


def d(t):
    return dict(t.items()) if t is not None else {}


# ---------------------------------------------------------------- an ore job, start to finish
ORE = '{ kind = "ore", item = "minecraft:raw_iron", n = 24 }'
L, g, r = run(ORE, {"minecraft:raw_iron": 177, "minecraft:redstone": 300, "minecraft:coal": 100})
check("the helper ends up waiting for the next job", r == [False, "IDLE"], str(r))
handed = d(g.HANDED)
check("24 raw iron came back to the factory as 32 ingots", handed.get("minecraft:iron_ingot") == 32, str(handed))
check("the redstone left over was handed back too", handed.get("minecraft:redstone", 0) > 0, str(handed))
check("nothing dropped on the floor", not d(g.FLOOR), str(d(g.FLOOR)))
check("nothing left in the machines", g.inMachines() == 0)
check("the real plans were used", "factory_asfit2" in g.PLANS and "factory_foundryfloor" in g.PLANS, g.PLANS)
cm = d(L.eval("machineAt(OX + 41, OY + 1, OZ + 12).modes"))
check("the chamber was set up from the lane", cm["FRONT"] == "ENERGY" and cm["LEFT"] == "OUTPUT" and cm["TOP"] == "INPUT", str(cm))
check("two trips to the pad: supplies, then the hand-in", g.TRIPS == 2, str(g.TRIPS))
check("coal on board was not burned as a matter of course", (g.FUEL_GIVEN or 0) <= 2, str(g.FUEL_GIVEN))
rep = d(g.LAST)
fd = d(rep.get("foundry"))
check("the status report carries the foundry's state", fd.get("machines") == "chamber smelter"
      and d(fd.get("last")).get("ok") is True, str(fd))
ready = [m for m in g.SENT.values() if m["type"] == "foundry_ready"]
check("the factory was told which machines are ready", len(ready) >= 1 and d(ready[-1]["machines"]).get("chamber") is True)
print("   fuel used:", 3000 - g.T.fuel, "| game time:", int(g.CLOCK), "s | ended at", g.T.x, g.T.y, g.T.z)

# ---------------------------------------------------------------- laying power on, start to finish
# (placing and taking up blocks goes through the machines' world too: a
# placed block faces the turtle, one placed down faces the way it looks)
PLACING = '''
  local DXX, DZZ = { [0] = 1, [1] = 0, [2] = -1, [3] = 0 }, { [0] = 0, [1] = 1, [2] = 0, [3] = -1 }
  local hplace, hplaceDown, hdigDown = turtle.place, turtle.placeDown, turtle.digDown
  local function newBlock(x, y, z, f)
    local s = T.inv[T.sel]
    if not s or getBlock(x, y, z) then return false, "Cannot place block here" end
    addMachine(s.name, x, y, z, f)
    setSpecial(x, y, z, s.name)
    s.count = s.count - 1
    if s.count == 0 then T.inv[T.sel] = nil end
    return true
  end
  turtle.place = function()
    local s = T.inv[T.sel]
    if s and s.name:find("mekanism") then return newBlock(T.x + DXX[T.d], T.y, T.z + DZZ[T.d], (T.d + 2) % 4) end
    return hplace()
  end
  turtle.placeDown = function()
    local s = T.inv[T.sel]
    if s and s.name:find("mekanism") then return newBlock(T.x, T.y - 1, T.z, T.d) end
    return hplaceDown()
  end
  turtle.digDown = function()
    local m = machineAt(T.x, T.y - 1, T.z)
    if m then
      MACHINES[m.x .. "," .. m.y .. "," .. m.z] = nil
      setSpecial(m.x, m.y, m.z, false)
      giveTurtle(m.item, 1)
      return true
    end
    return hdigDown()
  end
'''
L, g, r = run('{ kind = "power" }', {"minecraft:coal": 200, "minecraft:redstone": 300,
    "mekanismgenerators:heat_generator": 1, "mekanism:basic_energy_cube": 1, "mekanism:basic_universal_cable": 16},
    extra=PLACING)
check("power: the helper ends up waiting for the next job", r == [False, "IDLE"], str(r))
at = lambda x, y, z: L.eval(f"(function() local m = machineAt(OX + {x}, OY + {y}, OZ + {z}) return m and m.item .. ' ' .. m.f end)()")
check("power: generator at (42,1,18) facing north", at(42, 1, 18) == "mekanismgenerators:heat_generator 3", str(at(42, 1, 18)))
check("power: cube at (42,1,17) facing north", at(42, 1, 17) == "mekanism:basic_energy_cube 3", str(at(42, 1, 17)))
cab = [z for z in range(11, 17) if at(42, 1, z) == "mekanism:basic_universal_cable 1" or (at(42, 1, z) or "").startswith("mekanism:basic_universal_cable")]
check("power: cable along the backs from z 16 to z 11", cab == list(range(11, 17)), str(cab))
check("power: the chamber and smelter take power at the back",
      L.eval("machineAt(OX + 41, OY + 1, OZ + 12).emodes.BACK") == "INPUT" and L.eval("machineAt(OX + 41, OY + 1, OZ + 11).emodes.BACK") == "INPUT")
fd = d(d(g.LAST).get("foundry"))
pw = d(fd.get("power"))
check("power: reported on", pw.get("ok") is True, str(pw) + " " + str(d(fd).get("notes") and list(d(fd)["notes"].values())))
check("power: nothing on the floor", not d(g.FLOOR), str(d(g.FLOOR)))
print("   fuel used:", 3000 - g.T.fuel, "| game time:", int(g.CLOCK), "s")
# ---------------------------------------------------------------- an ordinary helper is not affected
L3 = lupa.LuaRuntime()
L3.execute('fs = { exists = function() return false end }')
st = L3.eval(f'dofile("{ROOT}/foundry.lua").load()')
check("a helper that was never put on the foundry stays an ordinary helper", not st["on"])

print()
print("FAILED: " + ", ".join(fails) if fails else "PASS")
sys.exit(1 if fails else 0)
