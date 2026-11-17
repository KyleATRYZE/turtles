-- builder.lua : BlockParty, the swarm's builder.
--
-- For now it surveys, without breaking anything. It carries a Geo Scanner
-- (Advanced Peripherals) and maps by scanning; without one it walks instead.
--   * the base room: one scan around the factory (or a walk through every
--     open space, recording every block it can see)
--   * the ground around the base: it climbs out through the hole above the
--     launch pad and scans from points on a grid (or walks the surface in
--     rows), recording the ground and everything standing on it
-- The maps go to CommandBlock, which uploads them (maps/*.json on the
-- status branch) so they can be looked at outside the game.
-- Building from those maps comes next.

local okSwarm, swarm = pcall(require, "swarm")
if not okSwarm then swarm = nil end

local NAME         = "BlockParty"
local STATE_FILE   = "builder.state"
local BASE_FILE    = ".base"
local MAP_PROTOCOL = "swarm_map"
local JOB_PROTOCOL = "swarm_job"
local ROOM_REACH   = 12     -- room map: blocks either side of the factory
local ROOM_BELOW   = 2      -- ... and below / above its level
local ROOM_ABOVE   = 5
local LAND_SIZE    = 40     -- ground map: this many blocks square, centred on the base
local MAX_DROP     = 3      -- never follow the ground down further than this in one step
                            -- (deeper drops are pits: hover across them instead)
local CORE         = "advancedperipherals:weak_automata_core"
local SCANNER      = "advancedperipherals:geo_scanner"
local PICKAXE      = "minecraft:diamond_pickaxe"
local SCAN_RADIUS  = 8      -- the scanner's free range
local SCAN_SPACING = 10     -- distance between scan points on the ground map
local DOOR_OFFSET  = { x = -1, y = 0, z = 8 }   -- the hut's doorway, from the factory
local DOOR_OUT     = 1                          -- the way out of it: south

-- Blocks that count as the ground itself (anything above these is a tree,
-- a plant, or something somebody built).
local GROUND = {}
for _, n in ipairs({
  "stone", "dirt", "grass_block", "coarse_dirt", "podzol", "rooted_dirt", "mud",
  "mycelium", "gravel", "sand", "red_sand", "sandstone", "red_sandstone",
  "deepslate", "tuff", "andesite", "granite", "diorite", "calcite", "clay",
  "snow_block", "powder_snow", "ice", "packed_ice", "blue_ice", "bedrock",
  "water", "lava", "terracotta", "moss_block", "dripstone_block",
  "smooth_basalt", "basalt", "blackstone", "netherrack", "end_stone",
}) do GROUND["minecraft:" .. n] = true end

local function isGround(name)
  return GROUND[name] or name:find("_ore$") ~= nil or name:find("_terracotta$") ~= nil
end

local DIRS = {
  [0] = { x = 1, z = 0 }, [1] = { x = 0, z = 1 },
  [2] = { x = -1, z = 0 }, [3] = { x = 0, z = -1 },
}

local pos = { x = 0, y = 0, z = 0 }
local heading = 0
local base, st

---------------------------------------------------------------- reporting

local logLines = {}
local rawPrint = print
local function print(...)
  rawPrint(...)
  local parts = table.pack(...)
  for i = 1, parts.n do parts[i] = tostring(parts[i]) end
  logLines[#logLines + 1] = table.concat(parts, " ")
  while #logLines > 6 do table.remove(logLines, 1) end
end

local lastState, lastReport = "starting", 0
local progress

-- A lava bucket in the inventory is fuel (1,000 moves): drink it whenever
-- there is room in the tank. The empty bucket goes back with the leftovers.
local function drinkLava()
  local limit = turtle.getFuelLimit and turtle.getFuelLimit() or 20000
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    local level = turtle.getFuelLevel()
    if d and d.name == "minecraft:lava_bucket" and type(level) == "number"
      and (type(limit) ~= "number" or level + 1000 <= limit) then
      turtle.select(s)
      turtle.refuel(1)
      turtle.select(1)
    end
  end
end

local function report(state)
  lastState = state or lastState
  lastReport = os.clock()
  pcall(drinkLava)
  if not swarm then return end
  local inv, free = {}, 0
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d then inv[d.name] = (inv[d.name] or 0) + d.count else free = free + 1 end
  end
  local f = turtle.getFuelLevel()
  pcall(swarm.report, {
    role = "builder",
    state = lastState,
    pos = { x = pos.x, y = pos.y, z = pos.z },
    fuel = f == "unlimited" and -1 or f,
    freeSlots = free,
    inv = inv,
    progress = progress,
    maps = st and st.done or nil,
    log = logLines,
  })
end

local function tick(state)
  if os.clock() - lastReport > 30 then report(state) end
end

---------------------------------------------------------------- saved data

local function loadTable(file)
  if not fs.exists(file) then return nil end
  local h = fs.open(file, "r")
  local t = textutils.unserialize(h.readAll())
  h.close()
  if type(t) == "table" then return t end
  return nil
end

local function saveTable(file, t)
  local h = fs.open(file .. ".tmp", "w")
  h.write(textutils.serialize(t))
  h.close()
  fs.delete(file)
  fs.move(file .. ".tmp", file)
end

local function save() saveTable(STATE_FILE, st) end

local function key(x, y, z) return x .. "," .. y .. "," .. z end
local function unkey(k)
  local x, y, z = k:match("^(-?%d+),(-?%d+),(-?%d+)$")
  return tonumber(x), tonumber(y), tonumber(z)
end

---------------------------------------------------------------- fuel

local function fuel()
  local f = turtle.getFuelLevel()
  if f == "unlimited" then return math.huge end
  return f
end

local function burnInventory(target)
  for s = 1, 16 do
    if fuel() >= target then break end
    local d = turtle.getItemDetail(s)
    if d and d.name ~= CORE then
      turtle.select(s)
      while fuel() < target and turtle.refuel(1) do end
    end
  end
  turtle.select(1)
end

-- A full inventory cannot take coal. On the launch pad the factory is right
-- beside us: hand it a stack back (turning costs no fuel).
local function makeRoom()
  for s = 1, 16 do
    if turtle.getItemCount(s) == 0 then return true end
  end
  for _ = 1, 4 do
    local ok, d = turtle.inspect()
    if ok and tostring(d.name):find("computercraft:turtle", 1, true) then
      for s = 16, 1, -1 do
        local it = turtle.getItemDetail(s)
        if it and it.name ~= CORE and it.name ~= SCANNER and it.name ~= PICKAXE
          and not it.name:find("coal", 1, true) then
          turtle.select(s)
          if turtle.drop() then
            turtle.select(1)
            print("Handed a stack back to make room for coal.")
            return true
          end
        end
      end
    end
    turtle.turnRight()
  end
  turtle.select(1)
  return false
end

-- Out of fuel where we stand: burn what we carry, else call for help.
local function emptyTank()
  burnInventory(200)
  while fuel() == 0 do
    makeRoom()
    print("Out of fuel. Waiting for coal.")
    report("needs fuel")
    if swarm and swarm.open() then
      rednet.broadcast({ type = "fuel_request", id = os.getComputerID() }, JOB_PROTOCOL)
    end
    sleep(10)
    burnInventory(200)
  end
end

---------------------------------------------------------------- movement
-- The builder has no digging tool: it never breaks anything.

local function turnRight()
  turtle.turnRight()
  heading = (heading + 1) % 4
end

local function turnLeft()
  turtle.turnLeft()
  heading = (heading + 3) % 4
end

local function face(d)
  local diff = (d - heading) % 4
  if diff == 1 then turnRight()
  elseif diff == 2 then turnRight() turnRight()
  elseif diff == 3 then turnLeft() end
end

local MOVE = { f = "forward", u = "up", d = "down" }
local SUFFIX = { f = "", u = "Up", d = "Down" }

-- One step: "f", "u" or "d". Waits for other turtles and mobs to get out
-- of the way. False if a block is in the way.
local function step(dir)
  local waited = 0
  while true do
    if fuel() == 0 then emptyTank() end
    if turtle[MOVE[dir]]() then
      if dir == "f" then
        pos.x = pos.x + DIRS[heading].x
        pos.z = pos.z + DIRS[heading].z
      elseif dir == "u" then
        pos.y = pos.y + 1
      else
        pos.y = pos.y - 1
      end
      return true
    end
    local ok, data = turtle["inspect" .. SUFFIX[dir]]()
    local name = ok and type(data) == "table" and data.name or nil
    if name and name:find("computercraft:turtle", 1, true) then
      if waited >= 90 then return false end
      if waited % 15 == 5 then report("waiting for a turtle") end
      waited = waited + 1
      sleep(1)                           -- another turtle: let it pass
    elseif not turtle["detect" .. SUFFIX[dir]]() and not name then
      -- a mob or a player: wait a few seconds (a player walks off), then
      -- swing at it
      if waited >= 30 then return false end
      if waited >= 12 then turtle["attack" .. SUFFIX[dir]]() end
      waited = waited + 1
      sleep(0.5)
    else
      return false
    end
  end
end

local function locate()
  while true do
    local x, y, z = gps.locate(2)
    if x then
      return math.floor(x + 0.5), math.floor(y + 0.5), math.floor(z + 0.5)
    end
    print("No GPS signal, retrying...")
    sleep(3)
  end
end

-- Which way do we face? Step out in some direction, compare GPS, step back.
local function detectHeading()
  local x, _, z = locate()
  for turns = 0, 3 do
    if turtle.forward() then
      local x2, _, z2 = locate()
      for _ = 1, 30 do
        if turtle.back() then break end
        sleep(1)
      end
      local d
      if x2 > x then d = 0 elseif x2 < x then d = 2 elseif z2 > z then d = 1 else d = 3 end
      for _ = 1, turns do turtle.turnLeft() end
      return (d - turns) % 4
    end
    turtle.turnRight()
  end
  return nil
end

local function relocate()
  if fuel() < 10 then emptyTank() end
  local h = detectHeading()
  if not h then
    -- boxed in: try one level up or down
    for _, dir in ipairs({ "u", "d" }) do
      if turtle[MOVE[dir]]() then
        h = detectHeading()
        turtle[MOVE[dir == "u" and "d" or "u"]]()
        if h then break end
      end
    end
  end
  if not h then error("I am boxed in and cannot tell which way I face.", 0) end
  heading = h
  pos.x, pos.y, pos.z = locate()
end

---------------------------------------------------------------- the base

local function inShaft()
  return { x = 2 * base.dock.x - base.exit1.x, z = 2 * base.dock.z - base.exit1.z }
end

local function outShaft()
  return { x = 2 * base.exit2.x - base.exit1.x, z = 2 * base.exit2.z - base.exit1.z }
end

-- Cells the miners travel through. The builder passes through the space
-- above the launch pad only when it has to, and never stops in these.
local function laneCells()
  local t = {}
  local function add(p) t[key(p.x, p.y, p.z)] = true end
  add(base.dock)
  add(base.exit1)
  add(base.exit2)
  add(base.pad)
  local a, b = inShaft(), outShaft()
  for y = base.f.y - ROOM_BELOW - 1, base.dock.y + 1 do
    t[key(a.x, y, a.z)] = true
    t[key(b.x, y, b.z)] = true
  end
  -- the old holes above the pad and the drop-off chest (the way out)
  for y = base.exit2.y, base.f.y + ROOM_ABOVE + 1 do
    t[key(base.exit2.x, y, base.exit2.z)] = true
    t[key(base.dock.x, y, base.dock.z)] = true
  end
  return t
end

local function inBox(x, y, z)
  local f = base.f
  return math.abs(x - f.x) <= ROOM_REACH and math.abs(z - f.z) <= ROOM_REACH
    and y >= f.y - ROOM_BELOW and y <= f.y + ROOM_ABOVE
end

-- neighbour of a cell for a move: 0-3 = a heading, "u", "d"
local function neighbour(x, y, z, m)
  if m == "u" then return x, y + 1, z end
  if m == "d" then return x, y - 1, z end
  return x + DIRS[m].x, y, z + DIRS[m].z
end

local function moveBy(m)
  if m == "u" or m == "d" then return step(m) end
  face(m)
  return step("f")
end

local OPPOSITE = { [0] = 2, [1] = 3, [2] = 0, [3] = 1, u = "d", d = "u" }
local ALL_MOVES = { 0, 1, 2, 3, "u", "d" }

-- Shortest path through known open cells (allowed = set of keys).
local function pathTo(goalK, allowed)
  local startK = key(pos.x, pos.y, pos.z)
  if startK == goalK then return {} end
  local prev, queue, head = { [startK] = false }, { startK }, 1
  while head <= #queue do
    local k = queue[head]
    head = head + 1
    local x, y, z = unkey(k)
    for _, m in ipairs(ALL_MOVES) do
      local nk = key(neighbour(x, y, z, m))
      if prev[nk] == nil and (allowed[nk] or nk == goalK) then
        prev[nk] = { k, m }
        if nk == goalK then
          local moves, c = {}, nk
          while prev[c] do
            table.insert(moves, 1, prev[c][2])
            c = prev[c][1]
          end
          return moves
        end
        queue[#queue + 1] = nk
      end
    end
  end
  return nil
end

local function roomSet()
  local s = {}
  for _, k in ipairs(st.roomCells or {}) do s[k] = true end
  return s
end

local function doorKey()
  -- (base.door: a rebase order's door=x,y,z, the way into the room the pad is in now)
  local d = st.door or base.door or { x = base.f.x + DOOR_OFFSET.x, y = base.f.y + DOOR_OFFSET.y,
    z = base.f.z + DOOR_OFFSET.z }
  return key(d.x, d.y, d.z), d
end

-- Walk to a cell of the base room by known open cells. If a block now
-- stands where the map says it's open (someone put a furnace there, say),
-- the map is corrected and another way is tried. Turtles in the way are
-- waited for (by step), not mapped.
local function goToCell(goalK)
  for _ = 1, 6 do
    local allowed = roomSet()
    allowed[doorKey()] = true
    local path = pathTo(goalK, allowed)
    if not path then return false end
    local ok = true
    for _, m in ipairs(path) do
      if not moveBy(m) then
        local dir = (m == "u" or m == "d") and m or "f"
        local seen, data = turtle["inspect" .. SUFFIX[dir]]()
        if seen and type(data) == "table" and not tostring(data.name):find("turtle", 1, true) then
          local x, y, z = neighbour(pos.x, pos.y, pos.z, m)
          local bad = key(x, y, z)
          local cells = {}
          for _, k in ipairs(st.roomCells or {}) do
            if k ~= bad then cells[#cells + 1] = k end
          end
          st.roomCells = cells
          save()
          print("The room has changed: " .. tostring(data.name):gsub("^.*:", "")
            .. " in the way. Finding another way.")
        else
          return false                    -- a turtle that would not move
        end
        ok = false
        break
      end
    end
    if ok then return true end
  end
  return false
end

local function sendMap(name, data)
  if not swarm or not swarm.open() then return end
  rednet.broadcast({ type = "map", name = name, data = data }, MAP_PROTOCOL)
  print("Map '" .. name .. "' sent.")
end

---------------------------------------------------------------- scanner

local function findSlot(name)
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and d.name == name then return s end
  end
  return nil
end

local function scannerSide()
  for _, side in ipairs({ "left", "right" }) do
    local t = peripheral.getType(side)
    if t and tostring(t):find("geo") then return side end
  end
  return nil
end

-- Fit the scanner if we carry one and have a free tool side.
local function fitScanner()
  if scannerSide() then return true end
  local slot = findSlot(SCANNER)
  if not slot then return false end
  turtle.select(slot)
  local fitted = false
  if peripheral.getType("left") ~= "modem" then fitted = turtle.equipLeft() end
  if not fitted and peripheral.getType("right") ~= "modem" then fitted = turtle.equipRight() end
  turtle.select(1)
  -- whatever came off (normally nothing) stays in the inventory
  for _ = 1, 10 do
    if scannerSide() then return true end
    sleep(0.5)
  end
  return false
end


local function toolSide()
  if peripheral.getType("left") == "modem" then return "right" end
  return "left"
end

-- "pick" or "scan": put that on the tool side (the other one goes into
-- the inventory).
local function useTool(which)
  if which == "scan" then
    if scannerSide() then return true end
    local slot = findSlot(SCANNER)
    if not slot then return false end
    turtle.select(slot)
    local ok = toolSide() == "left" and turtle.equipLeft() or turtle.equipRight()
    turtle.select(1)
    for _ = 1, 10 do
      if scannerSide() then return true end
      sleep(0.5)
    end
    return false
  end
  local side = scannerSide()
  if not side then return true end            -- the pickaxe is already on
  local slot = findSlot(PICKAXE)
  if not slot then return false end
  turtle.select(slot)
  local ok = side == "left" and turtle.equipLeft() or turtle.equipRight()
  turtle.select(1)
  return ok
end

-- Scan around us. Returns { key = name } for every non-air block, plus a
-- function telling whether a cell was inside the scanned range.
local function scanHere()
  local side = scannerSide()
  if not side then return nil, "no scanner fitted" end
  local why
  for _ = 1, 12 do
    local sc = peripheral.wrap(side)
    local fn = sc and (sc.scanBlocks or sc.scan)
    if fn then
      local ok, blocks, reason = pcall(fn, SCAN_RADIUS)
      if ok and type(blocks) == "table" then
        local found = {}
        for _, b in ipairs(blocks) do
          if b.x and b.y and b.z and type(b.name) == "string" then
            found[key(pos.x + b.x, pos.y + b.y, pos.z + b.z)] = b.name
          end
        end
        local cx, cy, cz = pos.x, pos.y, pos.z
        local function covered(x, y, z)
          local dx, dy, dz = x - cx, y - cy, z - cz
          return dx * dx + dy * dy + dz * dz <= SCAN_RADIUS * SCAN_RADIUS
        end
        return found, covered
      end
      why = tostring(ok and reason or blocks)
    else
      why = "the scanner did not answer"
    end
    sleep(2)          -- usually the scanner's cooldown
  end
  return nil, why
end

---------------------------------------------------------------- room map

-- Map the room by scanning: no walking needed, except to get within reach
-- of the launch pad if we start far from it.
local function roomScan()
  print("Scanning the base room.")
  report("mapping the base")
  local f = base.f
  local lanes = laneCells()
  local padK = key(base.pad.x, base.pad.y, base.pad.z)
  local seen, order, reached = {}, nil, nil

  local function reachable()
    local here = key(pos.x, pos.y, pos.z)
    local list, set, head = { here }, { [here] = true }, 1
    while head <= #list do
      local x, y, z = unkey(list[head])
      head = head + 1
      for _, m in ipairs(ALL_MOVES) do
        local nx, ny, nz = neighbour(x, y, z, m)
        local nk = key(nx, ny, nz)
        if not set[nk] and seen[nk] == "air" and not lanes[nk] and inBox(nx, ny, nz) then
          set[nk] = true
          list[#list + 1] = nk
        end
      end
    end
    return list, set
  end

  local function padNextTo(set)
    for _, m in ipairs(ALL_MOVES) do
      if set[key(neighbour(base.pad.x, base.pad.y, base.pad.z, m))] then return true end
    end
    return false
  end

  for attempt = 1, 4 do
    local found, covered = scanHere()
    if not found then
      if attempt == 1 then return false, covered end
      break
    end
    for x = pos.x - SCAN_RADIUS, pos.x + SCAN_RADIUS do
      for y = pos.y - SCAN_RADIUS, pos.y + SCAN_RADIUS do
        for z = pos.z - SCAN_RADIUS, pos.z + SCAN_RADIUS do
          if covered(x, y, z) then seen[key(x, y, z)] = found[key(x, y, z)] or "air" end
        end
      end
    end
    order, reached = reachable()
    if padNextTo(reached) then break end
    -- too far from the pad to see it: move to the reachable spot nearest to
    -- it and scan again
    local best, bestD
    local here = key(pos.x, pos.y, pos.z)
    for _, k in ipairs(order) do
      local x, y, z = unkey(k)
      local d = math.abs(x - base.pad.x) + math.abs(y - base.pad.y) + math.abs(z - base.pad.z)
      if not bestD or d < bestD then best, bestD = k, d end
    end
    if not best or best == here then break end
    print("Moving closer to the launch pad.")
    st.roomCells = order
    if not goToCell(best) then break end
  end

  local palette, index, cells = {}, {}, {}
  for k, name in pairs(seen) do
    local x, y, z = unkey(k)
    if inBox(x, y, z) then
      if not index[name] then
        palette[#palette + 1] = name
        index[name] = #palette
      end
      cells[#cells + 1] = { x - f.x, y - f.y, z - f.z, index[name] }
    end
  end
  sendMap("base_room", {
    kind = "room", origin = f, palette = palette, cells = cells, scanned = true,
    lanes = { dock = base.dock, exit1 = base.exit1, exit2 = base.exit2, pad = base.pad },
  })

  st.roomCells = order
  local best, bestD
  for _, k in ipairs(order) do
    local x, y, z = unkey(k)
    local below = seen[key(x, y - 1, z)]
    if y == f.y and below and below ~= "air" and not lanes[k] then
      local d = math.abs(x - base.exit1.x) + math.abs(z - base.exit1.z)
      if not bestD or d > bestD then best, bestD = k, d end
    end
  end
  st.park = best or key(pos.x, pos.y, pos.z)
  st.padKey = padK
  st.done.room = true
  save()
  if not padNextTo(reached) then print("Warning: I cannot see a way to the launch pad.") end
  print(("Base room scanned: %d open spaces I can reach."):format(#order))
  return true
end

local function roomSurvey()
  if scannerSide() then
    local ok, why = roomScan()
    if ok then return end
    print("Scan failed (" .. tostring(why) .. "). Walking it instead.")
  end
  print("Mapping the base room.")
  report("mapping the base")
  local lanes = laneCells()
  local seen, visited, order = {}, {}, {}
  local here = key(pos.x, pos.y, pos.z)

  local function lookAround()
    local k = key(pos.x, pos.y, pos.z)
    seen[k] = "air"
    for _, h in ipairs({ heading, (heading + 1) % 4, (heading + 3) % 4, (heading + 2) % 4 }) do
      local nk = key(neighbour(pos.x, pos.y, pos.z, h))
      if seen[nk] == nil then
        face(h)
        local ok, data = turtle.inspect()
        seen[nk] = ok and data.name or "air"
      end
    end
    local uk, dk = key(pos.x, pos.y + 1, pos.z), key(pos.x, pos.y - 1, pos.z)
    if seen[uk] == nil then
      local ok, data = turtle.inspectUp()
      seen[uk] = ok and data.name or "air"
    end
    if seen[dk] == nil then
      local ok, data = turtle.inspectDown()
      seen[dk] = ok and data.name or "air"
    end
  end

  visited[here] = true
  order[#order + 1] = here
  lookAround()
  local path = {}
  while true do
    tick("mapping the base")
    progress = { kind = "room", cells = #order }
    local pick
    for _, m in ipairs(ALL_MOVES) do
      local x, y, z = neighbour(pos.x, pos.y, pos.z, m)
      local k = key(x, y, z)
      if seen[k] == "air" and not visited[k] and not lanes[k] and inBox(x, y, z) then
        pick = m
        break
      end
    end
    if pick then
      local k = key(neighbour(pos.x, pos.y, pos.z, pick))
      visited[k] = true
      if moveBy(pick) then
        path[#path + 1] = pick
        order[#order + 1] = k
        lookAround()
      end
    else
      if #path == 0 then break end
      local m = table.remove(path)
      if not moveBy(OPPOSITE[m]) then
        error("Something blocked my way back while mapping.", 0)
      end
    end
  end

  -- send it: offsets from the factory, block names as a palette
  local f = base.f
  local palette, index, cells = {}, {}, {}
  for k, name in pairs(seen) do
    if not index[name] then
      palette[#palette + 1] = name
      index[name] = #palette
    end
    local x, y, z = unkey(k)
    cells[#cells + 1] = { x - f.x, y - f.y, z - f.z, index[name] }
  end
  sendMap("base_room", {
    kind = "room", origin = f, palette = palette, cells = cells,
    lanes = { dock = base.dock, exit1 = base.exit1, exit2 = base.exit2, pad = base.pad },
  })

  -- remember the open cells, and pick a parking spot: a floor-level cell,
  -- on solid ground, as far from the miners' lanes as possible
  st.roomCells = order
  local best, bestD
  for _, k in ipairs(order) do
    local x, y, z = unkey(k)
    local below = seen[key(x, y - 1, z)]
    if y == f.y and below and below ~= "air" and not lanes[k] then
      local d = math.abs(x - base.exit1.x) + math.abs(z - base.exit1.z)
      if not bestD or d > bestD then best, bestD = k, d end
    end
  end
  st.park = best or here
  st.padKey = key(base.pad.x, base.pad.y, base.pad.z)
  st.done.room = true
  save()
  print(("Base room mapped: %d open spaces."):format(#order))
end

---------------------------------------------------------------- ground map

-- Move one block forward hugging the ground: climb over whatever is in the
-- way, then settle onto whatever is below. Returns false if stuck.
local function groundForward()
  local climbed = 0
  while not step("f") do
    if climbed >= 24 or not step("u") then return false end
    climbed = climbed + 1
  end
  local dropped = 0
  -- over the base: never drop into it through a hole
  local overBase = math.abs(pos.x - base.f.x) <= ROOM_REACH
    and math.abs(pos.z - base.f.z) <= ROOM_REACH
  while dropped < MAX_DROP do
    local ok = turtle.inspectDown()
    if ok then break end
    if overBase and pos.y <= base.f.y + ROOM_ABOVE + 1 then break end
    if not step("d") then break end
    dropped = dropped + 1
  end
  return true
end

-- Walk along the surface to a column (x first, then z).
local function groundTo(x, z)
  for _, axis in ipairs({ "x", "z" }) do
    local target = axis == "x" and x or z
    while pos[axis] ~= target do
      local d
      if axis == "x" then d = target > pos.x and 0 or 2 else d = target > pos.z and 1 or 3 end
      face(d)
      if not groundForward() then
        -- try to get round by rising a little more
        local rose = 0
        while rose < 10 and step("u") do rose = rose + 1 end
        if not groundForward() then return false end
      end
      tick("travelling")
    end
  end
  return true
end

-- Ask the factory for fuel while waiting on the launch pad.
local function fuelUpOnPad(target)
  if fuel() >= target then return end
  print("Fuelling up on the launch pad.")
  for _ = 1, 30 do
    burnInventory(target)
    if fuel() >= target then return end
    if key(pos.x, pos.y, pos.z) ~= st.padKey then
      goToCell(st.padKey)                  -- the pad may have been taken
    end
    report("needs fuel")
    if swarm and swarm.open() then
      rednet.broadcast({ type = "fuel_request", id = os.getComputerID() }, JOB_PROTOCOL)
    end
    sleep(10)
  end
end

-- Blocks a turtle can move through.
local PASSABLE = {
  ["minecraft:short_grass"] = true, ["minecraft:tall_grass"] = true,
  ["minecraft:fern"] = true, ["minecraft:large_fern"] = true,
  ["minecraft:snow"] = true, ["minecraft:water"] = true,
}

-- Caught in a cave: look around with the scanner and walk through the open
-- space to a spot with open sky above, then climb up. If the way out is
-- further than the scanner reaches, go to the highest open spot and look
-- again.
local sentStuckMap = false
local function escape()
  if not useTool("scan") then
    print("No scanner to look around with.")
    return false
  end
  for _ = 1, 6 do
    local found, covered = scanHere()
    if not found then
      print("The scanner did not work: " .. tostring(covered))
      return false
    end
    if not sentStuckMap then
      -- a picture of where we are stuck, for looking at from outside
      sentStuckMap = true
      local f = base.f
      local palette, index, cells = {}, {}, {}
      for k, name in pairs(found) do
        local x, y, z = unkey(k)
        if not index[name] then palette[#palette + 1] = name index[name] = #palette end
        cells[#cells + 1] = { x - f.x, y - f.y, z - f.z, index[name] }
      end
      sendMap("stuck_area", { kind = "room", origin = f, palette = palette, cells = cells,
        scanned = true, from = { x = pos.x - f.x, y = pos.y - f.y, z = pos.z - f.z } })
    end
    local function open(x, y, z)
      local k = key(x, y, z)
      return covered(x, y, z) and (not found[k] or PASSABLE[found[k]])
    end
    -- open straight up to the top of what the scan saw, and the scan saw
    -- at least 5 blocks of that (near its edge it sees too little to tell)
    local function sky(x, y, z)
      local n = 0
      for yy = y + 1, y + SCAN_RADIUS + 1 do
        if not covered(x, yy, z) then return n >= 5 end
        if not open(x, yy, z) then return false end
        n = n + 1
      end
      return true
    end
    -- breadth-first through open cells
    local startK = key(pos.x, pos.y, pos.z)
    local seen, queue, head = { [startK] = true }, { startK }, 1
    -- if no way up is in sight, go to the open spot furthest away (the
    -- next scan from there sees new ground), never into a dead end above
    local exitK, bestK, bestD = nil, startK, 0
    while head <= #queue and #queue < 6000 do
      local k = queue[head]
      head = head + 1
      local x, y, z = unkey(k)
      if sky(x, y, z) then exitK = k break end
      local dist = (x - pos.x) ^ 2 + (z - pos.z) ^ 2 + (y - pos.y) ^ 2
      if dist > bestD then bestK, bestD = k, dist end
      for _, m in ipairs(ALL_MOVES) do
        local nx, ny, nz = neighbour(x, y, z, m)
        local nk = key(nx, ny, nz)
        if not seen[nk] and open(nx, ny, nz) then
          seen[nk] = true
          queue[#queue + 1] = nk
        end
      end
    end
    local goal = exitK or bestK
    if goal == startK and not exitK then
      print(("Shut in: %d open spaces around me and no way up."):format(#queue))
      return false
    end
    local allowed = {}
    for k in pairs(seen) do allowed[k] = true end
    local moves = pathTo(goal, allowed)
    if not moves then return false end
    for _, m in ipairs(moves) do
      if not moveBy(m) then
        print("Something is in the way of my way out.")
        break
      end
    end
    if exitK and key(pos.x, pos.y, pos.z) == exitK then
      -- up the hole until we are above everything solid around it
      local top = pos.y
      for k, name in pairs(found) do
        local x, y, z = unkey(k)
        if math.abs(x - pos.x) <= 1 and math.abs(z - pos.z) <= 1 and y > top
          and not PASSABLE[name] then
          top = y
        end
      end
      while pos.y <= top do
        if not step("u") then break end
      end
      if pos.y <= top then
        print("Blocked above me on the way out.")
        return false
      end
      print("Found a way out to open sky.")
      return true
    end
  end
  return false
end

-- Stuck somewhere (a pit, a cave): climb as high as we can, sidestepping
-- anything overhead, so that groundTo can find a way.
local function climbOut()
  for _ = 1, 3 do
    local rose = 0
    while rose < 40 and step("u") do rose = rose + 1 end
    if rose > 0 and not turtle.detectUp() then return true end
    local moved = false
    for h = 0, 3 do
      face(h)
      if step("f") then moved = true break end
    end
    if not moved then return false end
  end
  return true
end

-- Walk to a column, climbing out of trouble if we get stuck.
local function groundToSafely(x, z)
  for _ = 1, 4 do
    if groundTo(x, z) then return true end
    print("Stuck. Looking for a way out.")
    if not escape() and not climbOut() then return false end
  end
  return false
end

-- Near the hut: scan, then walk through open space into the room. If there
-- is no way, send a map of what the scanner saw so it can be looked at.
local function wayIn()
  if not useTool("scan") then return false end
  local found, covered = scanHere()
  if not found then return false end
  local room = roomSet()
  local function open(x, y, z)
    local k = key(x, y, z)
    return room[k] or (covered(x, y, z) and (not found[k] or PASSABLE[found[k]]))
  end
  local startK = key(pos.x, pos.y, pos.z)
  local prev, queue, head, goal = { [startK] = false }, { startK }, 1, nil
  while head <= #queue and #queue < 8000 do
    local k = queue[head]
    head = head + 1
    if room[k] then goal = k break end
    local x, y, z = unkey(k)
    for _, m in ipairs(ALL_MOVES) do
      local nx, ny, nz = neighbour(x, y, z, m)
      local nk = key(nx, ny, nz)
      if prev[nk] == nil and open(nx, ny, nz) then
        prev[nk] = { k, m }
        queue[#queue + 1] = nk
      end
    end
  end
  if not goal then
    local f = base.f
    local palette, index, cells = {}, {}, {}
    for k, name in pairs(found) do
      local x, y, z = unkey(k)
      if not index[name] then palette[#palette + 1] = name index[name] = #palette end
      cells[#cells + 1] = { x - f.x, y - f.y, z - f.z, index[name] }
    end
    sendMap("entry_area", { kind = "room", origin = f, palette = palette, cells = cells,
      scanned = true, from = { x = pos.x - f.x, y = pos.y - f.y, z = pos.z - f.z } })
    return false
  end
  local moves, c = {}, goal
  while prev[c] do
    table.insert(moves, 1, prev[c][2])
    c = prev[c][1]
  end
  for _, m in ipairs(moves) do
    if not moveBy(m) then return false end
  end
  return true
end

-- Out of the hut: up the hole above the launch pad if it is open, else
-- out through the doorway; the scanner finds the way up to open sky.
local function goOutside()
  local e = base.exit2
  if goToCell(key(e.x, e.y, e.z)) then
    useTool("scan")
    if escape() then return true end
  end
  local dk = doorKey()
  if not goToCell(dk) then return false, "cannot reach the door" end
  useTool("scan")
  if not escape() then return false, "no way out from the door" end
  return true
end

-- Back in: to above the launch pad (or else just outside the doorway),
-- let the scanner find the way into the room, then on to a room cell (the
-- parking spot unless told otherwise).
local function comeHome(target)
  -- already in (or right by) the hut? the scanner may see a way straight in
  if math.abs(pos.x - base.f.x) <= ROOM_REACH and math.abs(pos.z - base.f.z) <= ROOM_REACH
    and pos.y <= base.f.y + ROOM_ABOVE + 2 and wayIn() then
    return goToCell(target or st.park)
  end
  local e = base.exit2
  local _, d = doorKey()
  local spots = {
    { e.x, e.z },
    { d.x + 3 * DIRS[DOOR_OUT].x, d.z + 3 * DIRS[DOOR_OUT].z },
  }
  for _, sp in ipairs(spots) do
    if groundToSafely(sp[1], sp[2]) and wayIn() then
      return goToCell(target or st.park)
    end
  end
  return false
end

-- Ground map by scanning from points on a grid.
local function landScan(size, cx, cz, name)
  local f = base.f
  local x1, z1 = cx - math.floor(size / 2), cz - math.floor(size / 2)
  local blocks, colRange = {}, {}
  local points = {}
  local half = math.floor(SCAN_SPACING / 2)
  for zz = z1 + half, z1 + size - 1 + half, SCAN_SPACING do
    local row = {}
    for xx = x1 + half, x1 + size - 1 + half, SCAN_SPACING do
      row[#row + 1] = { x = math.min(xx, x1 + size - 1), z = math.min(zz, z1 + size - 1) }
    end
    if #points % 2 == 1 then
      -- snake: every other row the other way round
      for i = 1, math.floor(#row / 2) do row[i], row[#row + 1 - i] = row[#row + 1 - i], row[i] end
    end
    for _, p in ipairs(row) do points[#points + 1] = p end
    points[#points + 1] = false   -- row marker
  end
  local done, total = 0, 0
  for _, p in ipairs(points) do if p then total = total + 1 end end

  for _, p in ipairs(points) do
    if p then
      groundToSafely(p.x, p.z)
      -- down to the ground to scan (the scanner only reaches 8 blocks),
      -- then back up to where we were, so a pit can never trap us
      local before = pos.y
      for _ = 1, 40 do
        if turtle.inspectDown() or not step("d") then break end
      end
      local found, covered = scanHere()
      while pos.y < before and step("u") do end
      done = done + 1
      progress = { kind = "ground", scans = done, of = total }
      tick("mapping the ground")
      if found then
        for k, name in pairs(found) do blocks[k] = name end
        for x = pos.x - SCAN_RADIUS, pos.x + SCAN_RADIUS do
          for z = pos.z - SCAN_RADIUS, pos.z + SCAN_RADIUS do
            if covered(x, pos.y, z) then
              local ck = x .. "," .. z
              local r = colRange[ck]
              local lo, hi = pos.y - SCAN_RADIUS, pos.y + SCAN_RADIUS
              if r then
                r[1], r[2] = math.min(r[1], lo), math.max(r[2], hi)
              else
                colRange[ck] = { lo, hi }
              end
            end
          end
        end
      else
        print("Scan failed: " .. tostring(covered))
      end
    end
  end

  -- per column: the ground height and block, plus everything on top of it
  local heights, names, palette, index, above = {}, {}, {}, {}, {}
  local function idx(name)
    if not index[name] then
      palette[#palette + 1] = name
      index[name] = #palette
    end
    return index[name]
  end
  for z = z1, z1 + size - 1 do
    for x = x1, x1 + size - 1 do
      local i = (z - z1) * size + (x - x1) + 1
      heights[i], names[i] = -1000, 0
      local r = colRange[x .. "," .. z]
      if r then
        for y = r[2], r[1], -1 do
          local name = blocks[key(x, y, z)]
          if name then
            if isGround(name) then
              heights[i], names[i] = y, idx(name)
              break
            end
            above[#above + 1] = { x - f.x, y, z - f.z, idx(name) }
          end
        end
      end
    end
  end
  sendMap(name, {
    kind = "ground", origin = { x = x1, z = z1 }, size = size, scanned = true,
    factory = f, heights = heights, names = names, palette = palette, above = above,
  })
  return true
end

local function landSurvey(site)
  local f = base.f
  local size = (site and site.size) or st.landSize or LAND_SIZE
  local cx, cz = (site and site.x) or f.x, (site and site.z) or f.z
  local mapName = (site and site.name) or "ground"
  local scanning = scannerSide() ~= nil
  local need = scanning and (math.floor(size * size / 4) + 800) or (size * size * 3 + 600)
  goToCell(st.padKey)
  fuelUpOnPad(math.min(need, 19000))
  if fuel() < need then
    local afford = scanning and math.floor(math.sqrt(math.max(0, fuel() - 800) * 4))
      or math.floor(math.sqrt(math.max(0, fuel() - 600) / 3))
    if afford < 24 then
      print("Not enough fuel to map. Waiting for fuel.")
      report("needs fuel")
      goToCell(st.park)
      return false
    end
    size = math.min(size, afford)
    print("Not enough fuel for the full map. Mapping " .. size .. " x " .. size .. ".")
  end
  local ok, why = goOutside()
  if not ok then
    print("Cannot get outside: " .. why)
    report("no way out")
    goToCell(st.park)
    return false
  end
  print("Mapping the ground, " .. size .. " x " .. size .. ".")
  report("mapping the ground")
  if scanning and landScan(size, cx, cz, mapName) then
    if site then st.site = nil else st.done.ground = true end
    save()
    print("Ground mapped. Coming home.")
    report("coming home")
    if not comeHome() then
      print("I could not get back in. Waiting outside.")
      report("stuck outside")
      return false
    end
    if site then st.site = nil else st.done.ground = true end
    save()
    return true
  end

  local x1, z1 = cx - math.floor(size / 2), cz - math.floor(size / 2)
  local heights, names, palette, index = {}, {}, {}, {}
  for i = 1, size * size do heights[i], names[i] = -1000, 0 end
  local function record()
    local i = (pos.z - z1) * size + (pos.x - x1) + 1
    if pos.x < x1 or pos.x >= x1 + size or pos.z < z1 or pos.z >= z1 + size then return end
    local okDown, data = turtle.inspectDown()
    local name = okDown and data.name or "minecraft:air"
    if not index[name] then
      palette[#palette + 1] = name
      index[name] = #palette
    end
    heights[i] = pos.y - 1
    names[i] = index[name]
  end

  groundToSafely(x1, z1)
  record()
  for row = 0, size - 1 do
    progress = { kind = "ground", row = row + 1, rows = size }
    tick("mapping the ground")
    local d = row % 2 == 0 and 0 or 2
    for _ = 1, size - 1 do
      face(d)
      if groundForward() then record() end
    end
    if row < size - 1 then
      face(1)
      if groundForward() then record() end
    end
  end

  sendMap(mapName, {
    kind = "ground", origin = { x = x1, z = z1 }, size = size,
    factory = f, heights = heights, names = names, palette = palette,
  })
  if site then st.site = nil else st.done.ground = true end
  save()
  print("Ground mapped. Coming home.")
  report("coming home")
  if not comeHome() then
    print("I could not get back in. Waiting outside.")
    report("stuck outside")
    return false
  end
  if site then st.site = nil else st.done.ground = true end
  save()
  return true
end


---------------------------------------------------------------- building
-- The builder builds from a list made by tools/buildlist.py: one line per
-- block, in the order to place them (floor first, then up layer by layer).
-- It hovers one block above each spot and places the block below itself.

local LIST_URL    = "https://raw.githubusercontent.com/KyleATRYZE/turtles/%s/blueprints/%s.txt"
local MARGIN      = 2      -- cleared ring around the building
local LOAD_STACKS = 10     -- stacks of blocks to fetch per trip (leaves room for coal)
local BUILD_FUEL  = 4000   -- fuel to leave the launch pad with
local FUEL_SPARE  = 600    -- head home for more when down to this (plus the trip)
local FACING      = { east = 0, south = 1, west = 2, north = 3 }
-- Blocks the building can go on without for now (put in later, when the
-- factory has them): windows and lights.
local OPTIONAL    = { ["minecraft:glass_pane"] = true, ["minecraft:glass"] = true,
  ["minecraft:lantern"] = true }

-- Things that grow or lie about naturally: fine to clear from the site.
local NATURAL_WORDS = {
  "leaves", "_log", "grass", "flower", "fern", "sapling", "mushroom", "vine",
  "moss", "bush", "shrub", "plant", "petals", "roots", "snow", "dripleaf",
  "berr", "lily", "tulip", "daisy", "hyssop", "fireweed", "tsubaki", "poppy",
  "dandelion", "orchid", "allium", "bluet", "cornflower", "lilac", "peony",
  "rose", "clover", "sprout", "cattail", "reed", "pumpkin", "melon",
  "sugar_cane", "bamboo", "pebble", "dead_bush", "propagule", "flax",
  "lavender", "pointed_dripstone", "cobweb", "garden", "sage", "thistle",
  "_bud", "fruit", "cactus", "azalea", "seagrass", "kelp", "coral",
}
local function isNatural(name)
  if isGround(name) then return true end
  if name:find("computercraft:") or name:find("planks") or name:find("stripped") then
    return false
  end
  for _, w in ipairs(NATURAL_WORDS) do
    if name:find(w, 1, true) then return true end
  end
  return false
end

-- Building blocks: never dropped. Ones the current plan doesn't use go back
-- to the factory.
local MATERIALS = {}
for _, n in ipairs({ "polished_deepslate", "deepslate_tiles", "stone_bricks",
  "cracked_stone_bricks", "deepslate_bricks", "deepslate_tile_stairs", "cut_copper",
  "cut_copper_slab", "cobblestone", "dirt", "glass", "glass_pane" }) do
  MATERIALS["minecraft:" .. n] = true
end

-- Worth taking home after clearing (the rest is dropped).
local function isKeeper(name)
  return name:find("_log", 1, true) or name:find("sapling", 1, true)
    or name == "minecraft:dirt" or name == "minecraft:cobblestone"
    or name == "minecraft:cobbled_deepslate"
end

local list                   -- { pal = {...}, blocks = {...} }

local function loadList(b)
  if list and list.file == b.listFile then return list end
  list = nil
  if not fs.exists(b.listFile) then
    print("Downloading the building plan.")
    local rev = (fs.exists(".version") and (function()
      local h = fs.open(".version", "r") local v = h.readAll() h.close() return v
    end)() or "main"):gsub("%s", "")
    local res = http and http.get(LIST_URL:format(rev ~= "" and rev or "main", b.plan))
    if not res then error("Could not download the building plan.", 0) end
    local text = res.readAll()
    res.close()
    local h = fs.open(b.listFile, "w")
    h.write(text)
    h.close()
  end
  local h = fs.open(b.listFile, "r")
  local pal, blocks = {}, {}
  local mode, n = nil, 0
  while true do
    local line = h.readLine()
    if not line then break end
    local tag, count = line:match("^([PB]) (%d+)$")
    if tag then
      mode, n = tag, tonumber(count)
    elseif mode == "P" then
      local name, facing = line:match("^(%S+) (%S+)$")
      pal[#pal + 1] = { name = name, facing = facing ~= "-" and facing or nil }
    elseif mode == "B" then
      local x, y, z, i = line:match("^(-?%d+) (-?%d+) (-?%d+) (%d+)$")
      if x then blocks[#blocks + 1] = { tonumber(x), tonumber(y), tonumber(z), tonumber(i) + 1 } end
    end
  end
  h.close()
  if #blocks == 0 then
    fs.delete(b.listFile)
    error("The building plan is empty.", 0)
  end
  list = { pal = pal, blocks = blocks }
  for _, p in ipairs(pal) do MATERIALS[p.name] = true end
  local sx, sy, sz, minx, miny, minz = 0, 0, 0, 0, 0, 0
  for _, e in ipairs(blocks) do
    sx, sy, sz = math.max(sx, e[1] + 1), math.max(sy, e[2] + 1), math.max(sz, e[3] + 1)
    minx, miny, minz = math.min(minx, e[1]), math.min(miny, e[2]), math.min(minz, e[3])
  end
  list.sx, list.sy, list.sz, list.minx, list.miny, list.minz = sx, sy, sz, minx, miny, minz
  list.file = b.listFile
  return list
end

-- the box we may dig in: the building plus a ring around it, from the
-- bottom of the foundation up
local function inSite(b, x, y, z)
  return x >= b.ox + list.minx - MARGIN and x <= b.ox + list.sx - 1 + MARGIN
    and z >= b.oz + list.minz - MARGIN and z <= b.oz + list.sz - 1 + MARGIN
    and y >= b.oy + list.miny and y <= b.oy + list.sy + 20
end

local function hasPickaxe()
  return findSlot(PICKAXE) ~= nil or (not scannerSide() and findSlot(SCANNER) ~= nil)
end

local function freeSlots()
  local n = 0
  for s = 1, 16 do if turtle.getItemCount(s) == 0 then n = n + 1 end end
  return n
end

-- Drop what is not worth keeping; with all = true drop the keepers too.
local function dropJunk(b, all)
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and not MATERIALS[d.name] and d.name ~= PICKAXE and d.name ~= SCANNER
      and d.name ~= CORE and d.name ~= "minecraft:coal" and d.name ~= "minecraft:charcoal"
      and (all or not isKeeper(d.name)) then
      turtle.select(s)
      turtle.dropUp()
    end
  end
  turtle.select(1)
end

---------------------------------------------------------------- moving on the site

-- One step that may dig a natural block out of the way, inside the site.
local lastBlocker            -- what stopped the last move on the site

-- Is the block there the one the plan wants? (Dirt grows grass.)
local function sameBlock(have, want)
  return have == want or (want == "minecraft:dirt" and have == "minecraft:grass_block")
end
local function digStep(b, dir)
  if step(dir) then return true end
  local x, y, z = pos.x, pos.y, pos.z
  if dir == "u" then y = y + 1 elseif dir == "d" then y = y - 1
  else x, z = x + DIRS[heading].x, z + DIRS[heading].z end
  local ok, data = turtle["inspect" .. SUFFIX[dir]]()
  lastBlocker = ok and data.name or "something moving"
  if not inSite(b, x, y, z) then
    lastBlocker = lastBlocker .. " (outside the site)"
    return false
  end
  if not ok or not isNatural(data.name) then return false end
  -- working round the building (the dirt bank, say): never tunnel under or
  -- into it; go over the top instead
  local k = b.keepOut
  if k and x >= k.x1 and x <= k.x2 and z >= k.z1 and z <= k.z2 and y <= k.y2 then
    lastBlocker = "the building"
    return false
  end
  -- never dig out a block the plan put there (dirt of the bank, say)
  if list and list.at and list.at[key(x, y, z)] and sameBlock(data.name, list.at[key(x, y, z)]) then
    lastBlocker = data.name .. " (part of the plan)"
    return false
  end
  useTool("pick")
  local dig = dir == "u" and turtle.digUp or dir == "d" and turtle.digDown or turtle.dig
  for _ = 1, 6 do              -- sand and gravel may fall in again
    dig()
    if step(dir) then return true end
    local again, d2 = turtle["inspect" .. SUFFIX[dir]]()
    if not again or not isNatural(d2.name) then break end
  end
  return step(dir)
end

-- Fly to a spot on the site: up first, across, then down. If something
-- built is in the way, try the other way round it, then go over the top of
-- the whole building. Arrives exactly at x, y, z or returns false.
local function flyTo(b, x, y, z)
  lastBlocker = nil
  local function across(order)
    for _, axis in ipairs(order) do
      while pos[axis] ~= (axis == "x" and x or z) do
        if axis == "x" then face(x > pos.x and 0 or 2) else face(z > pos.z and 1 or 3) end
        if not digStep(b, "f") then return false end
      end
    end
    return true
  end
  -- above everything this site will ever have on it (the factory is 32 tall)
  local safe = b.oy + math.max(list.sy, 32) + 2
  for _ = 1, 3 do
    while pos.y < y and digStep(b, "u") do end
    local ok = across({ "x", "z" }) or across({ "z", "x" })
    if not ok then
      while pos.y < safe and digStep(b, "u") do end
      ok = across({ "x", "z" }) or across({ "z", "x" })
    end
    if ok then
      while pos.y > y and digStep(b, "d") do end
      while pos.y < y and digStep(b, "u") do end
      if pos.x == x and pos.y == y and pos.z == z then return true end
    end
    if not digStep(b, "u") then return false end
  end
  return pos.x == x and pos.y == y and pos.z == z
end

-- The column on the west side of the site we go up and down in.
local function sideColumn(b, z)
  local x1 = b.ox + list.minx - MARGIN
  local z1, z2 = b.oz + list.minz - MARGIN, b.oz + list.sz - 1 + MARGIN
  return x1, math.max(z1, math.min(z2, z))
end

-- From the doorway to a spot on the site, walking then flying.
local function goToSite(b, x, y, z)
  local cx, cz = sideColumn(b, z)
  if not groundToSafely(cx, cz) then return false end
  while pos.y > b.oy and step("d") do end
  return flyTo(b, x, y, z)
end

-- From the site back to the parking spot or another room cell.
local function leaveSite(b, target)
  local cx, cz = sideColumn(b, pos.z)
  if inSite(b, pos.x, pos.y, pos.z) then
    flyTo(b, cx, math.max(pos.y, b.oy), cz)
    while step("d") do end
  end
  return comeHome(target)
end

---------------------------------------------------------------- materials

-- Order a load. We wait at the parking spot while the factory makes it,
-- go onto the launch pad when it says the load is ready, and get it there.
local function ask(b, items, fuelWanted, timeout)
  if not (swarm and swarm.open()) then return nil end
  -- order numbers are unique across all jobs (the factory ignores a number
  -- it has just served)
  st.orderSeq = (st.orderSeq or (os.epoch("utc") % 1000000000)) + 1
  b.orderN = st.orderSeq
  save()
  local me = os.getComputerID()
  local msg = { type = "materials", id = me, n = b.orderN, items = items, fuel = fuelWanted }
  rednet.broadcast(msg, JOB_PROTOCOL)
  goToCell(st.park)
  local started, lastAsk = os.clock(), os.clock()
  while os.clock() - started < (timeout or 3600) do
    local _, reply = rednet.receive(JOB_PROTOCOL, 30)
    if type(reply) == "table" and reply.forId == me and reply.n == b.orderN then
      if reply.type == "materials_ready" then return reply end
      if reply.type == "load_ready" and key(pos.x, pos.y, pos.z) ~= st.padKey then
        print("The load is ready. Onto the launch pad.")
        goToCell(st.padKey)
      end
    end
    if os.clock() - lastAsk > 120 then          -- the factory may have missed it
      rednet.broadcast(msg, JOB_PROTOCOL)
      lastAsk = os.clock()
    end
    tick("waiting for materials")
  end
  return nil
end

-- What the next part of the list needs, up to a load.
-- With helpers on the job, we only place our own strip of the plan.
local function mine(b, e)
  return (not b.xmin or e[1] >= b.xmin) and (not b.xmax or e[1] <= b.xmax)
end

local function nextLoad(b)
  local counts, order = {}, {}
  local short = b.short or {}
  -- the blocks still to place: the rest of the list, or (at the end) the
  -- ones being gone back for
  local indices = {}
  if b.i <= #list.blocks then
    for i = b.i, #list.blocks do indices[#indices + 1] = i end
  else
    for _, i in ipairs(b.skips or {}) do indices[#indices + 1] = i end
  end
  for _, i in ipairs(indices) do
    local name = list.pal[list.blocks[i][4]].name
    if not short[name] and mine(b, list.blocks[i]) then   -- (out of stock: left for later)
      if not counts[name] then
        counts[name] = 0
        order[#order + 1] = name
      end
      counts[name] = counts[name] + 1
      local stacks = 0
      for _, c in pairs(counts) do stacks = stacks + math.ceil(c / 64) end
      if stacks > LOAD_STACKS then
        counts[name] = counts[name] - 1
        break
      end
    end
  end
  -- ask only for what we are not already carrying
  local items = {}
  for _, name in ipairs(order) do
    local have = 0
    for s = 1, 16 do
      local d = turtle.getItemDetail(s)
      if d and d.name == name then have = have + d.count end
    end
    if counts[name] - have > 0 then items[#items + 1] = { name, counts[name] - have } end
  end
  return items, counts
end

-- Part-stacks of the same thing into as few slots as they fit in.
local function compact()
  for a = 1, 15 do
    local da = turtle.getItemDetail(a)
    if da and da.count < 64 then
      for s = 16, a + 1, -1 do
        local ds = turtle.getItemDetail(s)
        if ds and ds.name == da.name then
          turtle.select(s)
          turtle.transferTo(a)
          if turtle.getItemCount(a) >= 64 then break end
        end
      end
    end
  end
  turtle.select(1)
end

-- On the launch pad: hand in what we dug up, then load up with blocks,
-- fuel and (the first time) a pickaxe.
local function restock(b)
  -- the keepers go into the drop-off chest by the factory
  local dock = base.dock
  -- what we keep: while placing, only what the next stretch of the plan
  -- needs (a full inventory of blocks for later left no room for the ones
  -- needed now); otherwise anything the plan uses
  local using = {}
  if b.stage == "place" then
    local _, needed = nextLoad(b)
    for name, n in pairs(needed) do
      if n > 0 then using[name] = true end
    end
  else
    for _, p in ipairs(list.pal) do using[p.name] = true end
  end
  -- spare coal goes back too: one stack is plenty (it takes room from blocks)
  local coalSlots, spareCoal = 0, {}
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and (d.name == "minecraft:coal" or d.name == "minecraft:charcoal") then
      coalSlots = coalSlots + 1
      if coalSlots > 1 then spareCoal[s] = true end
    end
  end
  local function handBack(name, slot)
    if spareCoal[slot] then return true end
    if name == "minecraft:bucket" then return true end       -- an emptied lava bucket
    return (isKeeper(name) or MATERIALS[name]) and not using[name]
  end
  local carrying = false
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and handBack(d.name, s) then carrying = true end
  end
  -- stand beside the chest (never in the miners' lanes) and drop in
  local cx, cy, cz = dock.x, dock.y - 1, dock.z
  local room, lanes = roomSet(), laneCells()
  local spot, toward
  for h = 0, 3 do
    local x, z = cx - DIRS[h].x, cz - DIRS[h].z
    local k = key(x, cy, z)
    if room[k] and not lanes[k] then spot, toward = k, h break end
  end
  if carrying and spot and goToCell(spot) then
    face(toward)
    for s = 1, 16 do
      local d = turtle.getItemDetail(s)
      if d and handBack(d.name, s) then
        turtle.select(s)
        turtle.drop()
      end
    end
    turtle.select(1)
  end
  goToCell(st.park)
  dropJunk(b, false)
  local placing = b.stage == "place"
  while true do
    compact()
    local items = placing and nextLoad(b) or {}
    local first = items[1] and items[1][1]
    -- already loaded and only short of fuel: ask for fuel alone
    local fuelOnly = first and findSlot(first) and fuel() < FUEL_SPARE + 400
    if fuelOnly then items = {} end
    if not hasPickaxe() then table.insert(items, 1, { PICKAXE, 1 }) end
    local fuelWanted = math.max(0, math.ceil((BUILD_FUEL - fuel()) / 80))
    if #items == 0 and fuelWanted == 0 then break end
    print("Asking the factory for a load.")
    report("waiting for materials")
    local reply = ask(b, items, math.min(64, fuelWanted))
    if fuel() < FUEL_SPARE + 400 and freeSlots() == 0 and key(pos.x, pos.y, pos.z) == st.padKey then
      makeRoom()                         -- no room for the coal: give a stack back and ask again
      reply = ask(b, {}, math.min(64, fuelWanted))
    end
    burnInventory(BUILD_FUEL)
    if fuel() < FUEL_SPARE + 400 then
      -- never set off on a tank that will only bring us straight back
      print("No fuel to be had. Waiting here for coal.")
      report("waiting for fuel")
      goToCell(st.park)
      for _ = 1, 6 do
        sleep(30)
        report("waiting for fuel")       -- (a lava bucket put in by hand is drunk here)
        if fuel() >= FUEL_SPARE + 400 then break end
      end
    elseif fuelOnly then break
    elseif not placing or (first and findSlot(first)) then break
    elseif not first then break
    elseif OPTIONAL[first] then
      -- windows and lights can wait: note it and carry on with the rest
      b.short = b.short or {}
      b.short[first] = true
      print("No " .. first:gsub("^.*:", "") .. " for now. Leaving those for later.")
      break
    else
      print("No " .. first:gsub("^.*:", "") .. " to be had yet. Waiting for the miners.")
      report("waiting for materials")
      goToCell(st.park)
      sleep(300)
    end
  end
  if not hasPickaxe() then error("I still have no pickaxe.", 0) end
  save()
end

-- Home from the site, restock, and back out of the hut.
local function supplyRun(b, reason)
  print("Going home: " .. reason)
  report("fetching materials")
  if not leaveSite(b, st.padKey) then
    report("stuck outside")
    error("I could not get back to the launch pad.", 0)
  end
  restock(b)
  if not goOutside() then error("I could not get out of the hut.", 0) end
  return true
end

---------------------------------------------------------------- clearing

local function saveTargets(t)
  local h = fs.open("clear.list", "w")
  for _, c in ipairs(t) do h.writeLine(c[1] .. " " .. c[2] .. " " .. c[3]) end
  h.close()
end

local function loadTargets()
  local t = {}
  if not fs.exists("clear.list") then return t end
  local h = fs.open("clear.list", "r")
  while true do
    local line = h.readLine()
    if not line then break end
    local x, y, z = line:match("^(-?%d+) (-?%d+) (-?%d+)$")
    if x then t[#t + 1] = { tonumber(x), tonumber(y), tonumber(z) } end
  end
  h.close()
  return t
end

-- Scan the site from points on a grid, at two heights, then clear every
-- natural block above the ground there, top down. Stops (touching nothing)
-- if anything there looks built.
local function clearSite(b)
  local x1, x2 = b.ox + list.minx - MARGIN, b.ox + list.sx - 1 + MARGIN
  local z1, z2 = b.oz + list.minz - MARGIN, b.oz + list.sz - 1 + MARGIN
  if not b.scanned then
    print("Scanning the site.")
    report("scanning the site")
    local found, built = {}, {}
    local points = {}
    local zs, xs = {}, {}
    for z = z1 + 4, z2 + 3, 8 do zs[#zs + 1] = math.min(z, z2) end
    for x = x1 + 4, x2 + 3, 8 do xs[#xs + 1] = math.min(x, x2) end
    for r, z in ipairs(zs) do
      for c = 1, #xs do
        points[#points + 1] = { r % 2 == 1 and xs[c] or xs[#xs + 1 - c], z }
      end
    end
    for n, p in ipairs(points) do
      progress = { kind = "site scan", point = n, points = #points }
      for _, h in ipairs({ b.oy + 1, b.oy + 11 }) do
        useTool("pick")
        if flyTo(b, p[1], h, p[2]) and useTool("scan") then
          local f = scanHere()
          for k, name in pairs(f or {}) do
            local x, y, z = unkey(k)
            if y >= b.oy and inSite(b, x, y, z) and not name:find("computercraft:turtle", 1, true) then
              if isNatural(name) then
                if not name:find("water", 1, true) and not name:find("lava", 1, true) then
                  found[k] = true
                end
              else
                built[#built + 1] = ("%s at %d %d %d"):format(name:gsub("^.*:", ""), x, y, z)
              end
            end
          end
        end
        tick("scanning the site")
      end
    end
    useTool("pick")
    if #built > 0 then
      print("Something built is on the site: " .. built[1])
      b.blocked = built
      save()
      report("site not clear")
      return false
    end
    local t = {}
    for k in pairs(found) do
      local x, y, z = unkey(k)
      t[#t + 1] = { x, y, z }
    end
    table.sort(t, function(a, c)
      if a[2] ~= c[2] then return a[2] > c[2] end
      if a[3] ~= c[3] then return a[3] < c[3] end
      if a[1] == c[1] then return false end
      if a[3] % 2 == 0 then return a[1] < c[1] end
      return a[1] > c[1]
    end)
    saveTargets(t)
    b.scanned, b.ci = true, 1
    save()
    print(("Site scanned: %d blocks to clear."):format(#t))
  end
  local t = loadTargets()
  useTool("pick")
  for i = b.ci or 1, #t do
    local c = t[i]
    progress = { kind = "clearing", done = i, total = #t }
    if fuel() < FUEL_SPARE + 200 then supplyRun(b, "low on fuel") end
    if freeSlots() < 3 then
      dropJunk(b, false)
      if freeSlots() < 3 then supplyRun(b, "my inventory is full") end
    end
    if flyTo(b, c[1], c[2] + 1, c[3]) then
      local ok, data = turtle.inspectDown()
      if ok and isNatural(data.name) and not data.name:find("water", 1, true) then
        useTool("pick")
        turtle.digDown()
      end
    end
    b.ci = i + 1
    if i % 16 == 0 then save() end
    tick("clearing the site")
  end
  b.stage = "place"
  b.i = b.i or 1
  save()
  print("Site cleared.")
  return true
end

---------------------------------------------------------------- placing

local function facingOf(data)
  return type(data) == "table" and type(data.state) == "table" and data.state.facing or nil
end

local function placeShell(b)
  local blocks, pal = list.blocks, list.pal
  local placedNow = 0
  useTool("pick")
  b.skips = b.skips or {}

  -- Try one block of the list. True when we are done with it (placed,
  -- already there, or skipped); false to try the same one again (after a
  -- supply run).
  local function doBlock(idx, lastGo)
    local e = blocks[idx]
    local want = pal[e[4]]
    local wx, wy, wz = b.ox + e[1], b.oy + e[2], b.oz + e[3]
    local slot = findSlot(want.name)
    local trip = math.abs(pos.x - st.doorX) + math.abs(pos.z - st.doorZ) + math.abs(pos.y - b.oy) + 50
    if not slot and OPTIONAL[want.name] and b.short and b.short[want.name] then
      if lastGo then
        b.leftover = (b.leftover or 0) + 1      -- the fit-out puts these in
      else
        b.later = b.later or {}
        b.later[#b.later + 1] = idx              -- put it in later
      end
      return true
    end
    if not slot then
      supplyRun(b, "out of " .. want.name:gsub("^.*:", ""))
      return false
    elseif fuel() < FUEL_SPARE + trip then
      supplyRun(b, "low on fuel")
      return false
    end
    if not flyTo(b, wx, wy + 1, wz) then
      if not b.sentBlockedMap and useTool("scan") then
        -- once: a picture of the spot, for working out what is in the way
        b.sentBlockedMap = true
        local found = scanHere()
        if found then
          local f = base.f
          local palette, index, cells = {}, {}, {}
          for k, name in pairs(found) do
            local x, y, z = unkey(k)
            if not index[name] then palette[#palette + 1] = name index[name] = #palette end
            cells[#cells + 1] = { x - f.x, y - f.y, z - f.z, index[name] }
          end
          sendMap("blocked_spot", { kind = "room", origin = f, palette = palette, cells = cells,
            scanned = true, from = { x = pos.x - f.x, y = pos.y - f.y, z = pos.z - f.z },
            target = { x = wx - f.x, y = wy + 1 - f.y, z = wz - f.z } })
        end
        useTool("pick")
      end
      print(("Cannot reach %d %d %d (%s). %s"):format(wx, wy, wz,
        tostring(lastBlocker):gsub("^minecraft:", ""),
        lastGo and "Leaving it." or "I'll try again at the end."))
      if not lastGo then b.skips[#b.skips + 1] = idx end
      b.skipped = (b.skipped or 0) + 1
      return true
    end
    local ok, data = turtle.inspectDown()
    local done = ok and sameBlock(data.name, want.name)
      and (not want.facing or facingOf(data) == want.facing)
    if not done then
      if ok and (isNatural(data.name) or data.name == want.name) then
        useTool("pick")
        turtle.digDown()                         -- clutter, or our own block facing wrong
      end
      if want.facing then face((FACING[want.facing] + (b.turn or 0)) % 4) end
      turtle.select(slot)
      if turtle.placeDown() and want.facing then
        local _, d2 = turtle.inspectDown()
        local got = facingOf(d2)
        if got and FACING[got] and got ~= want.facing then
          -- learn how placing turns the block, then put it right
          b.turn = ((b.turn or 0) + FACING[want.facing] - FACING[got]) % 4
          useTool("pick")
          turtle.select(1)
          turtle.digDown()
          turtle.select(slot)
          face((FACING[want.facing] + b.turn) % 4)
          turtle.placeDown()
        end
      end
      turtle.select(1)
      placedNow = placedNow + 1
    end
    return true
  end

  while b.i <= #blocks do
    if b.limit and placedNow >= b.limit then
      print("Trial done: placed " .. placedNow .. " blocks.")
      b.limit = nil
      b.paused = true
      save()
      return false
    end
    progress = { kind = "building", done = b.i - 1, total = #blocks, layer = blocks[b.i][2],
      skipped = #b.skips, later = b.later and #b.later or 0 }
    b.layer = blocks[b.i][2]
    if not mine(b, blocks[b.i]) or doBlock(b.i, false) then
      b.i = b.i + 1
      if b.i % 8 == 0 then save() end
    end
    if freeSlots() < 2 then dropJunk(b, true) end
    tick("building")
  end
  -- the windows and lights left for later go on the end of the retry list,
  -- with a fresh look at whether the factory has them now
  if b.later and #b.later > 0 then
    print(("Coming back for %d windows and lights."):format(#b.later))
    for _, idx in ipairs(b.later) do b.skips[#b.skips + 1] = idx end
    b.later, b.short = nil, nil
  end
  -- one more go at the ones that could not be reached the first time
  if #b.skips > 0 then print(("Going back for %d I skipped."):format(#b.skips)) end
  while #b.skips > 0 do
    progress = { kind = "building", done = #blocks, total = #blocks, retry = #b.skips }
    if doBlock(b.skips[1], true) then
      table.remove(b.skips, 1)
      save()
    end
    if freeSlots() < 2 then dropJunk(b, true) end
    tick("building")
  end
  b.stage = "done"
  save()
  print("Finished: " .. tostring(b.plan):gsub("_", " ") .. "!")
  return true
end

-- Build what st.build describes, from wherever we are.
local FACTORY_SIZE = { x = 57, y = 33, z = 32 }   -- the shell's box
local function runBuild()
  local b = st.build
  if b.reload then
    -- a new version of the plan: carry on from the start of the layer we
    -- are on (what is already built there is just checked)
    local layer = b.layer
    if not layer then
      loadList(b)
      local e = list.blocks[math.min(b.i, #list.blocks)]
      layer = e and e[2] or 0
    end
    if fs.exists(b.listFile) then fs.delete(b.listFile) end
    list = nil
    loadList(b)
    local i = #list.blocks + 1
    for n, e in ipairs(list.blocks) do
      if e[2] >= layer then i = n break end
    end
    b.i, b.reload, b.skips = i, nil, {}
    print(("New plan loaded: carrying on from layer %d."):format(layer))
    save()
  end
  loadList(b)
  if b.plan ~= "factory_shell" then
    b.keepOut = { x1 = b.ox, z1 = b.oz, x2 = b.ox + FACTORY_SIZE.x - 1,
      z2 = b.oz + FACTORY_SIZE.z - 1, y2 = b.oy + FACTORY_SIZE.y }
  end
  if not list.at then
    list.at = {}
    for _, e in ipairs(list.blocks) do
      list.at[key(b.ox + e[1], b.oy + e[2], b.oz + e[3])] = list.pal[e[4]].name
    end
  end
  local _, d = doorKey()
  st.doorX, st.doorZ = d.x, d.z
  local here = key(pos.x, pos.y, pos.z)
  -- (the room map also has the open air over the roof: above the ceiling
  -- is outside)
  local inside = (roomSet()[here] or here == st.padKey) and pos.y <= base.f.y + 2
  if not hasPickaxe() or fuel() < BUILD_FUEL / 2 then
    if inside then goToCell(st.padKey) else leaveSite(b, st.padKey) end
    restock(b)
    inside = true
  end
  if inside and not goOutside() then error("I could not get out of the hut.", 0) end
  report(b.stage == "clear" and "clearing the site" or "building")
  if not inSite(b, pos.x, pos.y, pos.z) then
    local x1, z1 = sideColumn(b, b.oz)
    if not goToSite(b, x1, b.oy, z1) then error("I could not reach the site.", 0) end
  end
  if b.stage == "clear" and not clearSite(b) then
    leaveSite(b)
    return
  end
  if b.stage == "place" then placeShell(b) end
  leaveSite(b)
end

-- Scan around us and send the picture as a map (for looking at from
-- outside when something is in the way).
local function sendScan(name, extra)
  if not useTool("scan") then return false end
  local found = scanHere()
  if not found then return false end
  local f = base.f
  local palette, index, cells = {}, {}, {}
  for k, n in pairs(found) do
    local x, y, z = unkey(k)
    if not index[n] then palette[#palette + 1] = n index[n] = #palette end
    cells[#cells + 1] = { x - f.x, y - f.y, z - f.z, index[n] }
  end
  local data = { kind = "room", origin = f, palette = palette, cells = cells, scanned = true,
    from = { x = pos.x - f.x, y = pos.y - f.y, z = pos.z - f.z } }
  for k, v in pairs(extra or {}) do data[k] = v end
  sendMap(name, data)
  return true
end

---------------------------------------------------------------- feeding a stuck queue
-- If a turtle runs dry in the miners' exit shaft, everything behind it
-- waits. Fetch coal from the factory, go to the top of the shaft and drop it
-- on the turtle there; the miners pass coal down the queue to the front.

local function feedShaft()
  local e1, e2 = base.exit1, base.exit2
  local out = { x = 2 * e2.x - e1.x, z = 2 * e2.z - e1.z }
  local function coal()
    local n = 0
    for s = 1, 16 do
      local d = turtle.getItemDetail(s)
      if d and (d.name == "minecraft:coal" or d.name == "minecraft:charcoal") then n = n + d.count end
    end
    return n
  end
  st.feed = st.feed or {}
  if coal() == 0 then
    print("Fetching coal for the stuck queue.")
    report("fetching coal")
    ask(st.feed, { { "minecraft:coal", 64 } }, 0, 300)
  end
  if coal() == 0 then
    print("The factory gave me no coal.")
    return false
  end
  print("Taking " .. coal() .. " coal to the exit shaft.")
  report("feeding the queue")
  if not goToCell(key(e2.x, e2.y, e2.z)) then
    print("Something is in my way to the exit shaft.")
    sendScan("feed_blocked")
    return false
  end
  face(out.x < e2.x and 2 or out.x > e2.x and 0 or (out.z > e2.z and 1 or 3))
  if not step("f") then return false end
  local down = 0
  while not turtle.detectDown() and down < 30 and step("d") do down = down + 1 end
  local ok, data = turtle.inspectDown()
  local gave = 0
  if ok and tostring(data.name):find("turtle", 1, true) then
    for s = 1, 16 do
      local d = turtle.getItemDetail(s)
      if d and (d.name == "minecraft:coal" or d.name == "minecraft:charcoal") then
        turtle.select(s)
        local before = turtle.getItemCount(s)
        turtle.dropDown()
        gave = gave + before - turtle.getItemCount(s)
      end
    end
    turtle.select(1)
    print("Dropped " .. gave .. " coal on the queue.")
  else
    print("Nobody stuck in the shaft.")
  end
  while pos.y < e2.y and step("u") do end
  face(out.x < e2.x and 0 or out.x > e2.x and 2 or (out.z > e2.z and 3 or 1))
  step("f")
  goToCell(st.park)
  return gave > 0
end

-- Hand n coal to a turtle at x, y, z next to the hut (Ghastly on the
-- roof, say): go to an open cell beside it and drop the coal into it.
local function giveCoalTo(tx, ty, tz, n)
  local have = 0
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and (d.name == "minecraft:coal" or d.name == "minecraft:charcoal") then have = have + d.count end
  end
  if have < n then
    print("Fetching coal to hand over.")
    st.feed = st.feed or {}
    ask(st.feed, { { "minecraft:coal", n - have } }, 0, 600)
  end
  local room = roomSet()
  for _, m in ipairs(ALL_MOVES) do
    local nx, ny, nz = neighbour(tx, ty, tz, m)
    local k = key(nx, ny, nz)
    if room[k] and goToCell(k) then
      local toward = OPPOSITE[m]
      local drop = toward == "u" and turtle.dropUp or toward == "d" and turtle.dropDown or turtle.drop
      if toward ~= "u" and toward ~= "d" then face(toward) end
      local left = n
      for s = 1, 16 do
        local d = turtle.getItemDetail(s)
        if left > 0 and d and (d.name == "minecraft:coal" or d.name == "minecraft:charcoal") then
          turtle.select(s)
          local before = turtle.getItemCount(s)
          drop(math.min(left, before))
          left = left - (before - turtle.getItemCount(s))
        end
      end
      turtle.select(1)
      print(("Gave %d coal to the turtle at %d %d %d."):format(n - left, tx, ty, tz))
      goToCell(st.park)
      return n - left
    end
  end
  -- not next to the room: go round outside and come down on top of it
  local here = key(pos.x, pos.y, pos.z)
  if (roomSet()[here] or here == st.padKey) and pos.y <= base.f.y + 2 then
    if not goOutside() then
      print("I could not get out to that turtle.")
      return 0
    end
  end
  if groundToSafely(tx, tz) then
    while pos.y > ty + 1 and not turtle.detectDown() and step("d") do end
    local ok, data = turtle.inspectDown()
    if pos.y == ty + 1 and ok and tostring(data.name):find("turtle", 1, true) then
      local left = n
      for s = 1, 16 do
        local d = turtle.getItemDetail(s)
        if left > 0 and d and (d.name == "minecraft:coal" or d.name == "minecraft:charcoal") then
          turtle.select(s)
          local before = turtle.getItemCount(s)
          turtle.dropDown(math.min(left, before))
          left = left - (before - turtle.getItemCount(s))
        end
      end
      turtle.select(1)
      print(("Gave %d coal to the turtle at %d %d %d."):format(n - left, tx, ty, tz))
      return n - left
    end
  end
  print("I could not get next to that turtle.")
  return 0
end

---------------------------------------------------------------- gathering
-- Fetch something the miners never find underground (sand for glass): go
-- to where the ground map shows it, and take it column by column. Only the
-- named block is ever dug, so nothing else out there can be harmed. Each
-- column that gives some adds its four neighbours to the list, so a patch
-- is followed wherever it goes, under water too.
local GATHER_DEPTH = 4     -- blocks taken from one column
local GATHER_FUEL = 400    -- head home with this much left

local function countOf(name)
  local n = 0
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and d.name == name then n = n + d.count end
  end
  return n
end

-- Put everything pred picks into the drop-off chest by the factory.
local function handIn(pred)
  local dock = base.dock
  local cx, cy, cz = dock.x, dock.y - 1, dock.z
  local room, lanes = roomSet(), laneCells()
  for h = 0, 3 do
    local x, z = cx - DIRS[h].x, cz - DIRS[h].z
    local k = key(x, cy, z)
    if room[k] and not lanes[k] and goToCell(k) then
      face(h)
      for s = 1, 16 do
        local d = turtle.getItemDetail(s)
        if d and pred(d.name) then
          turtle.select(s)
          turtle.drop()
        end
      end
      turtle.select(1)
      return true
    end
  end
  return false
end

local function runGather()
  local g = st.gather
  local short = g.name:gsub("^.*:", "")
  local function near(x, z)
    if math.abs(x - base.f.x) <= ROOM_REACH + 4 and math.abs(z - base.f.z) <= ROOM_REACH + 4 then return false end
    for _, sd in ipairs(g.from) do
      if math.abs(x - sd[1]) <= g.r and math.abs(z - sd[2]) <= g.r then return true end
    end
    return false
  end
  for trip = 1, 6 do
    if g.want <= 0 or #g.seeds == 0 then break end
    if not hasPickaxe() then print("No pickaxe: I cannot gather.") break end
    print(("Off to gather %s (%d wanted)."):format(short, g.want))
    report("gathering " .. short)
    if not goOutside() then error("I could not get out of the hut.", 0) end
    local seen, queue, head = {}, {}, 1
    for _, sd in ipairs(g.seeds) do
      local k = sd[1] .. "," .. sd[2]
      if not seen[k] then seen[k] = true queue[#queue + 1] = sd end
    end
    local got, tried = 0, 0
    while head <= #queue and got < g.want and freeSlots() >= 2 and fuel() > GATHER_FUEL and tried < 500 do
      local x, z = queue[head][1], queue[head][2]
      head = head + 1
      tried = tried + 1
      if groundToSafely(x, z) then
        local top, took = pos.y, 0
        useTool("pick")
        local sunk = 0                       -- down through water to the bed
        while sunk < 8 do
          local ok, d = turtle.inspectDown()
          if ok and d.name ~= "minecraft:water" then break end
          if not step("d") then break end
          sunk = sunk + 1
        end
        for _ = 1, GATHER_DEPTH do
          local ok, d = turtle.inspectDown()
          if not (ok and d.name == g.name) then break end
          local before = countOf(g.name)
          if not turtle.digDown() then break end
          took = took + countOf(g.name) - before
          if not step("d") then break end
        end
        while pos.y < top and step("u") do end
        if took > 0 then
          got = got + took
          for _, m in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
            local nx, nz = x + m[1], z + m[2]
            local k = nx .. "," .. nz
            if not seen[k] and near(nx, nz) then seen[k] = true queue[#queue + 1] = { nx, nz } end
          end
        end
      end
      tick("gathering " .. short)
    end
    print(("Gathered %d %s. Taking it home."):format(got, short))
    g.want = g.want - got
    g.seeds = {}
    for i = head, math.min(#queue, head + 60) do g.seeds[#g.seeds + 1] = queue[i] end
    save()
    report("bringing " .. short .. " home")
    if not comeHome(st.park) then
      report("stuck outside")
      error("I could not get back in.", 0)
    end
    handIn(function(name) return name == g.name end)
    goToCell(st.park)
    burnInventory(BUILD_FUEL)
    if got == 0 then break end
  end
  print(g.want > 0 and ("That is all the %s I could find: %d short."):format(short, g.want)
    or ("Got all the %s that was wanted."):format(short))
  st.gather = nil
  save()
end

---------------------------------------------------------------- jobs

local function work()
  if os.getComputerLabel() ~= NAME then os.setComputerLabel(NAME) end
  if fitScanner() then print("Geo Scanner fitted.") end
  relocate()
  local here = key(pos.x, pos.y, pos.z)
  local inside = ((roomSet()[here] or here == st.padKey) and pos.y <= base.f.y + 2)
    or (not st.done.room and inBox(pos.x, pos.y, pos.z) and pos.y <= base.f.y + 1)
  if not inside then
    -- restarted outside: find the way back in (keep trying for a while:
    -- someone may open a way)
    print("Outside. Coming home.")
    local tries = 0
    while not comeHome() do
      tries = tries + 1
      print("I could not get back in.")
      report("stuck outside")
      if tries >= 12 or fuel() < 150 then return end
      sleep(120)
    end
  end
  if not st.done.room then roomSurvey() end
  goToCell(st.park)
  if not st.done.ground then landSurvey() end
  if st.site then landSurvey(st.site) end
  goToCell(st.park)
  if st.gather then runGather() end
  for _ = 1, 4 do
    if not st.build or st.build.paused then break end
    if st.build.stage == "done" then
      if not (st.queue and #st.queue > 0) then break end
      st.build = table.remove(st.queue, 1)     -- back to what was put aside
      save()
      print("Back to " .. tostring(st.build.plan):gsub("_", " ") .. ".")
    end
    if st.build.stage ~= "done" then runBuild() end
    if st.build.stage ~= "done" then break end
  end
  goToCell(st.park)
  if st.done.ground then
    print("Maps done. Waiting for jobs.")
  else
    print("The ground map is not finished. Waiting for orders.")
  end
  while true do
    report("idle")
    sleep(60)
  end
end

local function guarded(fn)
  return function()
    local ok, err = pcall(fn)
    if not ok then
      if err == "Terminated" then error(err, 0) end
      print("ERROR: " .. tostring(err))
      report("error")
      while true do sleep(60) report("error") end
    end
  end
end

local function idle()
  while true do
    report(lastState)
    sleep(60)
  end
end

---------------------------------------------------------------- start

if not turtle then
  print("This program only runs on a turtle.")
  return
end

base = loadTable(BASE_FILE)
if not base or not base.f then
  print("I do not know where the base is. The factory sends that when I start.")
  return
end
st = loadTable(STATE_FILE) or { done = {} }
st.done = st.done or {}
do
  local h = fs.open(".role", "w")
  h.write("builder")
  h.close()
end

local task = st.paused and idle or guarded(work)
if st.paused then lastState = "stopped" end
if not swarm then
  task()
  return
end
while true do
  local cmd = swarm.runWithCommands(task, function(c)
    if c.cmd == "ping" then
      report(lastState)
      return true
    end
  end)
  if not cmd then
    task = idle
  elseif cmd.cmd == "reboot" then
    print("Rebooting by remote order.")
    swarm.pinVersion(cmd)
    report("rebooting")
    os.reboot()
  elseif cmd.cmd == "stop" then
    st.paused = true
    save()
    lastState = "stopped"
    task = idle
  elseif cmd.cmd == "resume" then
    st.paused = nil
    save()
    task = guarded(work)
  elseif cmd.cmd == "scan" then
    task = guarded(function()
      relocate()
      sendScan(type(cmd.name) == "string" and cmd.name:match("^[%w_]+$") or "scan_here")
      work()
    end)
  elseif cmd.cmd == "reload" and type(cmd.plan) == "string" then
    -- a new version of a plan is on GitHub: pick it up where we are
    local hit = false
    for _, b in ipairs({ st.build, table.unpack(st.queue or {}) }) do
      if b and b.plan == cmd.plan then
        b.reload = true
        b.layer = b.layer
        hit = true
      end
    end
    save()
    print(hit and ("Will reload " .. cmd.plan .. ".") or ("No build of " .. cmd.plan .. "."))
  elseif cmd.cmd == "givecoal" and tonumber(cmd.x) and tonumber(cmd.y) and tonumber(cmd.z) then
    task = guarded(function()
      relocate()
      local here = key(pos.x, pos.y, pos.z)
      local inside = (roomSet()[here] or here == st.padKey) and pos.y <= base.f.y + 2
      if not inside and not comeHome(st.park) then error("I could not get back in.", 0) end
      giveCoalTo(math.floor(tonumber(cmd.x)), math.floor(tonumber(cmd.y)), math.floor(tonumber(cmd.z)),
        tonumber(cmd.n) and math.floor(tonumber(cmd.n)) or 16)
      work()
    end)
  elseif cmd.cmd == "feed" then
    task = guarded(function()
      relocate()
      local here = key(pos.x, pos.y, pos.z)
      local inside = (roomSet()[here] or here == st.padKey) and pos.y <= base.f.y + 2
      if not inside then
        print("Coming in to feed the stuck queue.")
        if not comeHome(st.park) then error("I could not get back in.", 0) end
      end
      feedShaft()
      work()
    end)
  elseif cmd.cmd == "build" then
    -- build a plan (default: the shell) with its corner (the plan's 0,0,0)
    -- at ox, oy, oz (default: where the current build is). A different plan
    -- puts the current build aside; it carries on when the new one is done.
    -- limit = only place this many blocks (a trial); clear = 0 skips
    -- clearing the site first; stage = clear or place.
    st.paused = nil
    local cur = st.build
    local plan = (type(cmd.plan) == "string" and cmd.plan:match("^[%w_%-]+$"))
      or (cur and cur.plan) or "factory_shell"
    local ox = tonumber(cmd.ox) and math.floor(tonumber(cmd.ox)) or (cur and cur.ox)
    local oy = tonumber(cmd.oy) and math.floor(tonumber(cmd.oy)) or (cur and cur.oy)
    local oz = tonumber(cmd.oz) and math.floor(tonumber(cmd.oz)) or (cur and cur.oz)
    if ox and oy and oz then
      local same = cur and cur.plan == plan and cur.ox == ox and cur.oy == oy and cur.oz == oz
      if not same then
        if cur and cur.plan ~= plan and cur.stage ~= "done" then
          st.queue = st.queue or {}
          table.insert(st.queue, 1, cur)
          print("Putting " .. tostring(cur.plan):gsub("_", " ") .. " aside for now.")
        end
        local file = plan == "factory_shell" and "build.list" or (plan .. ".list")
        if fs.exists(file) then fs.delete(file) end
        if plan == "factory_shell" and fs.exists("clear.list") then fs.delete("clear.list") end
        st.build = { ox = ox, oy = oy, oz = oz, plan = plan, listFile = file,
          stage = plan == "factory_shell" and "clear" or "place", i = 1 }
      end
    end
    if st.build then
      st.build.paused = nil
      if tostring(cmd.redo) == "1" then
        st.build.i, st.build.skips = 1, {}
        if st.build.stage == "done" then st.build.stage = "place" end
      end
      st.build.limit = tonumber(cmd.limit) and math.floor(tonumber(cmd.limit)) or nil
      -- our strip of the plan when helpers share the job (share=all: the lot)
      if tonumber(cmd.xmin) then st.build.xmin = math.floor(tonumber(cmd.xmin)) end
      if tonumber(cmd.xmax) then st.build.xmax = math.floor(tonumber(cmd.xmax)) end
      if cmd.share == "all" then st.build.xmin, st.build.xmax = nil, nil end
      if tostring(cmd.clear) == "0" and st.build.stage == "clear" then st.build.stage = "place" end
      if cmd.stage == "clear" or cmd.stage == "place" then
        st.build.stage = cmd.stage
        if cmd.stage == "clear" then st.build.scanned = nil end
      end
    end
    save()
    task = guarded(work)
  elseif cmd.cmd == "gather" then
    -- fetch a surface block: name (default sand), want, and seeds: the
    -- columns to start from, as "x:z;x:z;..." (from the ground map);
    -- r = how far from a seed a patch may be followed
    local seeds = {}
    for x, z in tostring(cmd.seeds or ""):gmatch("(-?%d+):(-?%d+)") do
      seeds[#seeds + 1] = { tonumber(x), tonumber(z) }
    end
    if #seeds > 0 then
      local from = {}
      for i, sd in ipairs(seeds) do from[i] = { sd[1], sd[2] } end
      st.paused = nil
      st.gather = {
        name = (type(cmd.name) == "string" and cmd.name:match("^[%w_]+:[%w_]+$")) or "minecraft:sand",
        want = math.max(1, math.min(960, math.floor(tonumber(cmd.want) or 256))),
        r = math.max(2, math.min(24, math.floor(tonumber(cmd.r) or 10))),
        seeds = seeds, from = from,
      }
      save()
      task = guarded(work)
    end
  elseif cmd.cmd == "survey" then
    -- map again: with x and z, map the ground around that spot (named
    -- cmd.name); without, redo both base maps. size sets the map size.
    st.paused = nil
    if tonumber(cmd.x) and tonumber(cmd.z) then
      st.site = {
        x = math.floor(tonumber(cmd.x)), z = math.floor(tonumber(cmd.z)),
        size = math.min(96, math.floor(tonumber(cmd.size) or 48)),
        name = (type(cmd.name) == "string" and cmd.name:match("^[%w_%-]+$")) and cmd.name or "site",
      }
    else
      st.done = {}
      if tonumber(cmd.size) then st.landSize = math.floor(tonumber(cmd.size)) end
    end
    save()
    task = guarded(work)
  end
end
