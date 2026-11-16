"""The screens job, start to finish, with the real helper.lua in the real
building: six blank computers set up on the launch pad's disk drive, then
the fit plan blueprints/factory_screens.txt run through the factory as the
first fit-out left it (monitors that were put in from above lying on their
backs, the west gate's facing the wrong way).

    python3 test/screensfit.py

At the end every screen's monitors stand upright and face the right way,
each station computer is in place, switched on, with its ender modem stuck
to it, and the window that was taken out to get into the tower is back.
"""
import json, os, sys
import lupa

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
fails = []


def check(what, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + what + (f"  [{detail}]" if detail else ""))
    if not ok:
        fails.append(what)


def read_plan(name):
    L = open(os.path.join(ROOT, "blueprints", name + ".txt")).read().split("\n")
    n = int(L[1].split()[1])
    pal = [l.split() for l in L[2:2 + n]]
    ops = [l.split() for l in L[3 + n:] if l]
    return pal, ops


# how the first fit-out left each monitor: from above = on its back
FACE = {2: "east", 3: "south", 4: "west", 5: "north"}
pal0, ops0 = read_plan("factory_fitout")
first = {}
for o in ops0:
    if o[0] != "D" and "monitor" in pal0[int(o[4])][0]:
        s = int(o[5])
        first[(int(o[1]), int(o[2]), int(o[3]))] = ("north", "up") if s < 2 else (FACE[s], "north")

plan = json.load(open(os.path.join(ROOT, "blueprints", "factory.json")))
final = {(x, y, z): plan["palette"][i] for x, y, z, i in plan["blocks"]}
STORE = lambda c: 10 <= c[0] <= 17 and c[2] <= 29 and c[1] <= 7
monitors = {c: n.split("facing=")[1].rstrip("]") for c, n in final.items()
            if n.startswith("computercraft:monitor") and not STORE(c)}


def run(stock, install_ok=True, missing_monitors=()):
    L = lupa.LuaRuntime(unpack_returned_tuples=True)
    L.execute("START_D=3; START_FUEL=6000")
    L.execute(open(os.path.join(HERE, "harness.lua")).read().replace("/home/claude/turtles", ROOT))
    L.execute(open(os.path.join(HERE, "bworld.lua")).read())
    g = L.globals()
    g.ROOT = ROOT
    g.INSTALL_OK = install_ok
    L.execute('''
      package.path = ROOT .. "/?.lua;" .. package.path
      package.preload.swarm = function() return {
        open = function() return true end, report = function(r) LAST = r end,
        runWithCommands = function(task) task() return nil end, pinVersion = function() end } end
      LABEL = "Helper"
      OX, OY, OZ = -4448, 71, 1518
      STATE, COMP, ATTACH, STOCK, PLANS = {}, {}, {}, {}, ""
      local function key(x, y, z) return x .. "," .. y .. "," .. z end
      KEY = key
      http = { get = function(url)
        local name = url:match("blueprints/([%w_]+)%.txt")
        local f = assert(io.open(ROOT .. "/blueprints/" .. name .. ".txt"))
        local text = f:read("a") f:close()
        PLANS = PLANS .. name .. " "
        return { readAll = function() return text end, close = function() end }
      end }
      -- the building as fitted, block for block
      do
        local pal, mode = {}, nil
        for line in io.lines(ROOT .. "/blueprints/factory_asfit3.txt") do
          local tag = line:match("^([PB]) %d+$")
          if tag then mode = tag
          elseif mode == "P" then pal[#pal + 1] = line:match("^(%S+)")
          else
            local x, y, z, i = line:match("^(-?%d+) (-?%d+) (-?%d+) (%d+)$")
            if x and tonumber(y) >= 0 then setSpecial(OX + x, OY + y, OZ + z, pal[i + 1]) end
          end
        end
      end
      for y = 16, 60 do setSpecial(-4462, y, 1521, false) end
      T.x, T.y, T.z = -4462, 15, 1521
      T.inv = {}
      TOOL = "minecraft:diamond_pickaxe"
      FS[".version"] = "abc123"

      local DXX, DZZ = { [0] = 1, [1] = 0, [2] = -1, [3] = 0 }, { [0] = 0, [1] = 1, [2] = 0, [3] = -1 }
      local NAMES = { [0] = "east", [1] = "south", [2] = "west", [3] = "north" }
      local function cell(dir)
        if dir == "Up" then return T.x, T.y + 1, T.z, 0, 1, 0 end
        if dir == "Down" then return T.x, T.y - 1, T.z, 0, -1, 0 end
        return T.x + DXX[T.d], T.y, T.z + DZZ[T.d], DXX[T.d], 0, DZZ[T.d]
      end
      local function onPad() return T.x == -4462 and T.y == 15 and T.z == 1521 end
      function giveTurtle(name, n)
        while n > 0 do
          local put = false
          for s = 1, 16 do
            local i = T.inv[s]
            if i and i.name == name and not i.label and i.count < 64 then
              local c = math.min(64 - i.count, n) i.count = i.count + c n = n - c put = true break
            end
          end
          if not put then
            for s = 1, 16 do
              if not T.inv[s] then local c = math.min(64, n) T.inv[s] = { name = name, count = c } n = n - c put = true break end
            end
          end
          if not put then return n end
        end
        return 0
      end
      turtle.getItemDetail = function(s, detailed)
        local i = T.inv[s or T.sel]
        if not i then return nil end
        return { name = i.name, count = i.count, displayName = i.label or "Thing" }
      end
      PLACED, DUG, HANDED = {}, {}, {}
      for _, dir in ipairs({ "", "Up", "Down" }) do
        turtle["place" .. dir] = function()
          local i = T.inv[T.sel]
          if not i or i.name:find("pickaxe") or i.name == "minecraft:coal" then return false, "nothing to place" end
          local x, y, z, dx, dy, dz = cell(dir)
          if getBlock(x, y, z) then return false, "in the way" end
          local k = key(x, y, z)
          if i.name:find("monitor") then
            -- upright and facing the turtle from the side; on its back from above
            STATE[k] = { facing = NAMES[(T.d + 2) % 4], orientation = dir == "" and "north" or (dir == "Down" and "up" or "down") }
          elseif i.name:find("wireless_modem") then
            -- sticks to the block straight beyond it; failing that the one under it
            local bx, by, bz = x + dx, y + dy, z + dz
            if getBlock(bx, by, bz) then ATTACH[k] = key(bx, by, bz)
            elseif dir == "" and getBlock(x, y - 1, z) then ATTACH[k] = key(x, y - 1, z)
            else ATTACH[k] = "the turtle" end
          elseif i.name:find("computer") then
            COMP[k] = { label = i.label, on = false, id = i.id }
          end
          setSpecial(x, y, z, i.name)
          PLACED[i.name] = (PLACED[i.name] or 0) + 1
          i.count = i.count - 1
          if i.count == 0 then T.inv[T.sel] = nil end
          return true
        end
        turtle["inspect" .. dir] = function()
          local x, y, z = cell(dir)
          local b = getBlock(x, y, z)
          if not b then return false, "No block" end
          return true, { name = b, state = STATE[key(x, y, z)] or {} }
        end
        local dig = turtle["dig" .. dir]
        turtle["dig" .. dir] = function()
          local x, y, z = cell(dir)
          local b, k = getBlock(x, y, z), key(x, y, z)
          if not b then return false end
          DUG[b] = (DUG[b] or 0) + 1
          if b:find("computer") and COMP[k] and COMP[k].label then
            -- a named computer comes up as itself: it does not stack
            setSpecial(x, y, z, false)
            for s = 1, 16 do
              if not T.inv[s] then T.inv[s] = { name = b, count = 1, label = COMP[k].label, id = COMP[k].id } break end
            end
            COMP[k] = nil
            return true
          end
          if b == "minecraft:glass_pane" then setSpecial(x, y, z, false) return true end   -- (glass breaks)
          STATE[k], ATTACH[k], COMP[k] = nil, nil, nil
          local ok = dig()
          BROKE_PROTECTED = nil
          return ok
        end
        turtle["drop" .. dir] = function()
          local s = T.inv[T.sel]
          if not s then return false end
          if dir == "" and onPad() then HANDED[s.name] = (HANDED[s.name] or 0) + s.count STOCK[s.name] = (STOCK[s.name] or 0) + s.count
          else FLOOR = (FLOOR or 0) + s.count end
          T.inv[T.sel] = nil
          return true
        end
      end
      -- computers as peripherals; one set on the pad (over the disk drive)
      -- installs itself when switched on, names itself and switches off
      local NEXT_ID = 30
      local function compAt(side)
        local x, y, z = cell(side == "bottom" and "Down" or side == "top" and "Up" or "")
        local k = key(x, y, z)
        local b = getBlock(x, y, z)
        if b and b:find("computer") then COMP[k] = COMP[k] or { on = false } return COMP[k], x, y, z end
      end
      local gt = peripheral.getType
      peripheral.getType = function(side)
        if side == "bottom" or side == "top" or side == "front" then return compAt(side) and "computer" or nil end
        return gt(side)
      end
      peripheral.call = function(side, method)
        local c, x, y, z = compAt(side)
        if not c then error("No peripheral attached", 0) end
        if method == "turnOn" then
          c.on = true
          if not c.label and getBlock(x, y - 1, z) == "computercraft:disk_drive" then c.booting = 4 end
        elseif method == "isOn" then
          if c.booting then
            c.booting = c.booting - 1
            if c.booting <= 0 then
              c.booting, c.on = nil, false
              if INSTALL_OK then NEXT_ID = NEXT_ID + 1 c.id = NEXT_ID c.label = "station-" .. NEXT_ID end
            end
          end
          return c.on
        elseif method == "shutdown" then c.on = false
        elseif method == "getLabel" then return c.label
        end
      end
      os.clock = function() CLOCK = (CLOCK or 0) + 0.05 return CLOCK end
      os.date = function() return "00:00" end

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
          if m.fuel > 0 then giveTurtle("minecraft:coal", m.fuel) end
          return 3, { type = "materials_ready", forId = os.getComputerID(), n = m.n, given = given, missing = missing }
        end
        return 3, { type = "load_ready", forId = os.getComputerID(), n = m.n }
      end
    ''')
    # the monitors, as the first fit-out left them
    for (x, y, z), (facing, orient) in first.items():
        if (x, y, z) in missing_monitors:
            L.execute(f"setSpecial(OX+{x}, OY+{y}, OZ+{z}, false)")
        else:
            L.execute(f'STATE[KEY(OX+{x}, OY+{y}, OZ+{z})] = {{ facing = "{facing}", orientation = "{orient}" }}')
    for k, v in stock.items():
        L.execute(f'STOCK["{k}"] = {v}')
    helper = L.eval(f'loadfile("{ROOT}/helper.lua")')
    go = L.eval('function(f) return {pcall(f)} end')
    # 1. the lab run: fetch six blank computers, set them up on the pad
    L.execute('''FS["helper.state"] = textutils.serialize({ lab = {
      ops = "fetch|computercraft:computer_normal=6|dump;bootstrap|computercraft:computer_normal|6" } })''')
    r1 = list(go(helper).values())
    lab = list(L.eval('textutils.unserialize(FS["helper.state"]).labOut').values())
    named = [i.label for i in g.T.inv.values() if i is not None and i.label]
    # 2. the fit plan
    L.execute('''FS["helper.state"] = textutils.serialize({ job = { fit = true, plan = "factory_screens",
      shell = "factory_asfit3", ox = OX, oy = OY, oz = OZ } })''')
    r2 = list(go(helper).values())
    return L, g, r1, lab, named, r2


def block(L, c):
    return L.eval(f"getBlock(OX+{c[0]}, OY+{c[1]}, OZ+{c[2]})")


def state(L, c):
    s = L.eval(f"STATE[KEY(OX+{c[0]}, OY+{c[1]}, OZ+{c[2]})]")
    return (s.facing, s.orientation) if s else (None, None)


STOCK = {"computercraft:computer_normal": 6, "computercraft:monitor_advanced": 39,
         "computercraft:wireless_modem_advanced": 6, "minecraft:glass_pane": 26, "minecraft:coal": 200}

# ---------------------------------------------------------------- the whole job
before = sum(1 for c in monitors if first.get(c) != (monitors[c], "north"))
L, g, r1, lab, named, r2 = run(STOCK)
check("the lab run ends waiting for the next job", r1 == [False, "IDLE"], str(r1))
check("six computers set themselves up on the pad and came back named", len(named) == 6
      and all(n.startswith("station-") for n in named), str(lab[-2:]))
check("the fit run ends waiting for the next job", r2 == [False, "IDLE"], str(r2))
log = list(g.LOG.values())
left = [l for l in log if l.startswith("Left:")]
check("no job left undone", not left and any("Fit-out finished." == l for l in log), str(left[:4]))
wrong = [(c, state(L, c)) for c in monitors
         if block(L, c) != "computercraft:monitor_advanced" or state(L, c) != (monitors[c], "north")]
check(f"all {len(monitors)} monitors upright and facing the right way ({before} were not)", not wrong, str(wrong[:4]))
dug = dict(g.DUG.items())
check("only the wrong ones were taken down and put back", dug.get("computercraft:monitor_advanced") == before,
      str(dug.get("computercraft:monitor_advanced")))
comps = L.eval("COMP")
ok, on, stuck = True, True, True
for s in plan["stations"]:
    c, rdo = tuple(s["computer"]), tuple(s["radio"])
    k = L.eval(f"KEY(OX+{c[0]}, OY+{c[1]}, OZ+{c[2]})")
    ok = ok and block(L, c) == "computercraft:computer_normal" and comps[k] is not None and str(comps[k].label).startswith("station-")
    on = on and comps[k] is not None and comps[k].on is True
    stuck = stuck and block(L, rdo) == "computercraft:wireless_modem_advanced" \
        and L.eval(f"ATTACH[KEY(OX+{rdo[0]}, OY+{rdo[1]}, OZ+{rdo[2]})]") == k
check("a set-up computer stands at each of the six posts", ok)
check("each was switched on where it was put", on)
check("each has its ender modem stuck to it (not to the wall or the floor)", stuck)
check("the tower window that was taken out is back", block(L, (55, 18, 25)) == "minecraft:glass_pane"
      and dug.get("minecraft:glass_pane") == 1, str(dug.get("minecraft:glass_pane")))
check("the four wall bricks that made way for computers are the only masonry dug",
      dug.get("minecraft:stone_bricks", 0) + dug.get("minecraft:cracked_stone_bricks", 0) == 4, str(dug))
check("nothing dropped on the floor", not g.FLOOR, str(g.FLOOR))
print("   trips to the pad:", g.TRIPS, "| fuel used:", 6000 - g.T.fuel + 80 * 0, "| monitors left over on board:",
      sum(i.count for i in g.T.inv.values() if i is not None and "monitor" in i.name))

# ---------------------------------------------------------------- run again: nothing to do
L.execute('''FS["helper.state"] = textutils.serialize({ job = { fit = true, plan = "factory_screens",
  shell = "factory_asfit3", ox = OX, oy = OY, oz = OZ } })
DUG, PLACED = {}, {}''')
go = L.eval('function(f) return {pcall(f)} end')
r3 = list(go(L.eval(f'loadfile("{ROOT}/helper.lua")')).values())
dug, placed = dict(g.DUG.items()), dict(g.PLACED.items())
check("run a second time it changes nothing but the window (out and back)",
      r3 == [False, "IDLE"] and set(dug) <= {"minecraft:glass_pane"} and set(placed) <= {"minecraft:glass_pane"},
      f"{dug} {placed}")

# ---------------------------------------------------------------- monitors missing, and none to spare
gone = [c for c in monitors if c[2] == 4][:3]            # three of the rack board's never went up
L, g, r1, lab, named, r2 = run(dict(STOCK, **{"computercraft:monitor_advanced": 2}), missing_monitors=gone)
log = list(g.LOG.values())
left = [l for l in log if l.startswith("Left:")]
wrong = [c for c in monitors if c not in gone and state(L, c) != (monitors[c], "north")]
check("short of monitors: the two it has go up, the third is named as left, and nothing else",
      len(left) == 1 and "monitor_advanced" in left[0] and "none to be had" in left[0], str(left[:3]))
check("... and the ones lying wrong were still turned round, with no spares to do it", not wrong, str(wrong[:3]))

# ---------------------------------------------------------------- the install fails
L, g, r1, lab, named, r2 = run(STOCK, install_ok=False)
check("a computer that does not set itself up is reported, and the rest are not tried",
      not named and "0 ready" in lab[-1] and "did not set itself up" in lab[-1], str(lab[-1:]))

print()
print("FAILED: " + ", ".join(fails) if fails else "PASS")
sys.exit(1 if fails else 0)
