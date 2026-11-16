-- builder.lua : BrickJagger, the swarm's builder.
--
-- For now it surveys, without breaking anything. It carries a Geo Scanner
-- (Advanced Peripherals) and maps by scanning; without one it walks instead.
--   * the base room: one scan around the factory (or a walk through every
--     open space, recording every block it can see)
--   * the ground around the base: it climbs out through the hole above the
--     launch pad and scans from points on a grid (or walks the surface in
--     rows), recording the ground and everything standing on it
-- The maps go to GroundControl, which uploads them (maps/*.json on the
-- status branch) so they can be looked at outside the game.
-- Building from those maps comes next.

local okSwarm, swarm = pcall(require, "swarm")
if not okSwarm then swarm = nil end

local NAME         = "BrickJagger"
local STATE_FILE   = "builder.state"
local BASE_FILE    = ".base"
local MAP_PROTOCOL = "swarm_map"
local JOB_PROTOCOL = "swarm_job"
local ROOM_REACH   = 12     -- room map: blocks either side of the factory
local ROOM_BELOW   = 2      -- ... and below / above its level
local ROOM_ABOVE   = 5
local LAND_SIZE    = 40     -- ground map: this many blocks square, centred on the base
local MAX_DROP     = 12     -- never follow the ground down further than this in one step
local CORE         = "advancedperipherals:weak_automata_core"
local SCANNER      = "advancedperipherals:geo_scanner"
local SCAN_RADIUS  = 8      -- the scanner's free range
local SCAN_SPACING = 12     -- distance between scan points on the ground map

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

local function report(state)
  lastState = state or lastState
  lastReport = os.clock()
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

-- Out of fuel where we stand: burn what we carry, else call for help.
local function emptyTank()
  burnInventory(200)
  while fuel() == 0 do
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
      if waited >= 20 then return false end
      turtle["attack" .. SUFFIX[dir]]()  -- a mob
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

-- Walk to a cell of the base room by known open cells.
local function goToCell(goalK)
  local path = pathTo(goalK, roomSet())
  if not path then return false end
  for _, m in ipairs(path) do
    if not moveBy(m) then return false end
  end
  return true
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
    report("needs fuel")
    if swarm and swarm.open() then
      rednet.broadcast({ type = "fuel_request", id = os.getComputerID() }, JOB_PROTOCOL)
    end
    sleep(10)
  end
end

-- From the room up through the hole above the launch pad to the surface.
local function goOutside()
  if not goToCell(st.padKey) then return false, "cannot reach the launch pad" end
  -- up through the space above the pad (a miners' lane), then the hole,
  -- until we are above the room and open to the side
  local climbed = 0
  while true do
    if pos.y > base.f.y + ROOM_ABOVE then
      for h = 0, 3 do
        face(h)
        if not turtle.detect() then return true end   -- open to the side: we are out
      end
    end
    if not step("u") then
      return false, "the hole above the launch pad is blocked"
    end
    climbed = climbed + 1
    if climbed > 80 then return false, "no way up" end
  end
end

-- Back down the hole onto the launch pad, then to the parking spot.
local function comeHome()
  if not groundTo(base.exit2.x, base.exit2.z) then return false end
  while pos.y > base.exit2.y + 1 do
    if not step("d") then return false end
  end
  -- down through the miners' lane above the pad, onto the pad, but only
  -- when both are clear: never wait inside the lane
  for _ = 1, 200 do
    if not turtle.inspectDown() and step("d") then        -- into the lane
      if not turtle.inspectDown() and step("d") then      -- onto the pad
        return goToCell(st.park)
      end
      step("u")                                          -- pad busy: back out
    end
    report("waiting for a turtle")
    sleep(5)
  end
  return false
end

-- Ground map by scanning from points on a grid.
local function landScan(size)
  local f = base.f
  local x1, z1 = f.x - math.floor(size / 2), f.z - math.floor(size / 2)
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
      groundTo(p.x, p.z)
      local found, covered = scanHere()
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
  sendMap("ground", {
    kind = "ground", origin = { x = x1, z = z1 }, size = size, scanned = true,
    factory = f, heights = heights, names = names, palette = palette, above = above,
  })
  return true
end

local function landSurvey()
  local f = base.f
  local size = st.landSize or LAND_SIZE
  local scanning = scannerSide() ~= nil
  local need = scanning and (math.floor(size * size / 4) + 800) or (size * size * 3 + 600)
  goToCell(st.padKey)
  fuelUpOnPad(math.min(need, 19000))
  if fuel() < need then
    size = math.max(8, math.floor(math.sqrt(math.max(0, fuel() - 600) / 3)))
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
  if scanning and landScan(size) then
    print("Ground mapped. Coming home.")
    report("coming home")
    if not comeHome() then
      print("I could not get back in. Waiting outside.")
      report("stuck outside")
      return false
    end
    st.done.ground = true
    save()
    return true
  end

  local x1, z1 = f.x - math.floor(size / 2), f.z - math.floor(size / 2)
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

  groundTo(x1, z1)
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

  sendMap("ground", {
    kind = "ground", origin = { x = x1, z = z1 }, size = size,
    factory = f, heights = heights, names = names, palette = palette,
  })
  print("Ground mapped. Coming home.")
  report("coming home")
  if not comeHome() then
    print("I could not get back in. Waiting outside.")
    report("stuck outside")
    return false
  end
  st.done.ground = true
  save()
  return true
end

---------------------------------------------------------------- jobs

local function work()
  if os.getComputerLabel() ~= NAME then os.setComputerLabel(NAME) end
  if fitScanner() then print("Geo Scanner fitted.") end
  relocate()
  if pos.y > base.f.y + ROOM_ABOVE then
    -- restarted outside: walk back to the hole and come in
    print("Outside. Coming home.")
    if not comeHome() then report("stuck outside") return end
  end
  if not st.done.room then roomSurvey() end
  goToCell(st.park)
  if not st.done.ground then landSurvey() end
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
  elseif cmd.cmd == "survey" then
    -- map again: "survey" redoes both maps; a size sets the ground map size
    st.paused = nil
    st.done = {}
    if tonumber(cmd.size) then st.landSize = math.floor(tonumber(cmd.size)) end
    save()
    task = guarded(work)
  end
end
