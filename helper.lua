-- helper.lua : a builder's mate. A mining turtle (pickaxe + ender modem, no
-- scanner) that places part of a building plan while BrickJagger does the
-- rest, so a big build goes two or three times as fast.
--
-- It never goes into the base room and never tunnels. It lives in the open
-- air above the hut, flies high over everything to the site, and fetches
-- its loads by dropping straight down the hole over the launch pad.
--
-- Orders:
--   build plan=.. ox=.. oy=.. oz=.. xmin=.. xmax=.. layer=..
--                    place the plan's blocks with xmin <= x <= xmax, from
--                    that layer up (x and layer are the plan's own numbers)
--   stop / resume / reboot / ping
local okSwarm, swarm = pcall(require, "swarm")
if not okSwarm then swarm = nil end

local STATE_FILE   = "helper.state"
local BASE_FILE    = ".base"
local JOB_PROTOCOL = "swarm_job"
local LIST_URL     = "https://raw.githubusercontent.com/KyleATRYZE/turtles/%s/blueprints/%s.txt"
local LOAD_STACKS  = 12     -- stacks of blocks per trip
local FULL_TANK    = 1800   -- fuel to leave the pad with (coal is short)
local FUEL_SPARE   = 500    -- go home for more when down to this
local OVER_SITE    = 36     -- flying height above the site's floor
local FACING       = { east = 0, south = 1, west = 2, north = 3 }
-- things the build can do without for now: left for a second go at the end
local CLUTTER = { "grass", "dirt", "leaves", "fern", "flower", "poppy", "dandelion", "hyssop",
  "snow", "sapling", "mushroom", "vine" }

local DIRS = {
  [0] = { x = 1, z = 0 }, [1] = { x = 0, z = 1 },
  [2] = { x = -1, z = 0 }, [3] = { x = 0, z = -1 },
}
local pos, heading = { x = 0, y = 0, z = 0 }, 0
local st, base, list
local lastState, progress = "starting", nil

local logLines = {}
local rawPrint = print
local function print(...)
  rawPrint(...)
  local parts = table.pack(...)
  for i = 1, parts.n do parts[i] = tostring(parts[i]) end
  logLines[#logLines + 1] = table.concat(parts, " ")
  while #logLines > 6 do table.remove(logLines, 1) end
end

local lastReport = 0
local function report(state)
  lastState = state or lastState
  lastReport = os.clock()
  if not swarm then return end
  local f = turtle.getFuelLevel()
  pcall(swarm.report, {
    role = "helper", state = lastState,
    pos = { x = pos.x, y = pos.y, z = pos.z },
    fuel = f == "unlimited" and -1 or f,
    progress = progress, log = logLines,
  })
end
local function tick(state)
  if os.clock() - lastReport > 30 then report(state) end
end

local function loadTable(file)
  if not fs.exists(file) then return nil end
  local h = fs.open(file, "r")
  local t = textutils.unserialize(h.readAll())
  h.close()
  return t
end
local function save()
  local h = fs.open(STATE_FILE, "w")
  h.write(textutils.serialize(st))
  h.close()
end

---------------------------------------------------------------- fuel and slots

local function fuel()
  local f = turtle.getFuelLevel()
  if f == "unlimited" then return math.huge end
  return f
end

local function isCoal(name) return name == "minecraft:coal" or name == "minecraft:charcoal" end

local function refuel(target)
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and isCoal(d.name) then
      turtle.select(s)
      while fuel() < target and turtle.refuel(1) do end
    end
  end
  turtle.select(1)
end

local function findSlot(name)
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and d.name == name then return s end
  end
end

---------------------------------------------------------------- moving (never tunnels)

local function face(d)
  if (heading - d) % 4 == 1 then
    turtle.turnLeft()
    heading = (heading - 1) % 4
  end
  while heading ~= d do
    turtle.turnRight()
    heading = (heading + 1) % 4
  end
end

local MOVE = { f = "forward", u = "up", d = "down" }
local SUFFIX = { f = "", u = "Up", d = "Down" }
-- One step. Waits for a turtle or a mob in the way; a block stops us.
local function step(dir)
  local waited = 0
  while true do
    if fuel() < 1 then refuel(200) end
    if turtle[MOVE[dir]]() then
      if dir == "f" then
        pos.x, pos.z = pos.x + DIRS[heading].x, pos.z + DIRS[heading].z
      elseif dir == "u" then pos.y = pos.y + 1 else pos.y = pos.y - 1 end
      return true
    end
    local ok, data = turtle["inspect" .. SUFFIX[dir]]()
    local name = ok and type(data) == "table" and data.name or nil
    if name and name:find("computercraft:turtle", 1, true) then
      if waited >= 90 then return false, "turtle" end
      waited = waited + 1
      sleep(1)
    elseif not name and not turtle["detect" .. SUFFIX[dir]]() then
      if waited >= 30 then return false, "mob" end
      waited = waited + 1
      sleep(0.5)
    else
      return false, name
    end
  end
end

local function gpsHere()
  for _ = 1, 20 do
    local x, y, z = gps.locate(2)
    if x then return math.floor(x + 0.5), math.floor(y + 0.5), math.floor(z + 0.5) end
    sleep(3)
  end
  error("No GPS signal.", 0)
end

local function locate()
  pos.x, pos.y, pos.z = gpsHere()
end

-- Which way are we facing? Move one step and see where GPS puts us.
local function findHeading()
  for _ = 1, 4 do
    local x0, _, z0 = gpsHere()
    if turtle.forward() then
      local x1, _, z1 = gpsHere()
      for d = 0, 3 do
        if DIRS[d].x == x1 - x0 and DIRS[d].z == z1 - z0 then heading = d end
      end
      turtle.back()
      locate()
      return true
    end
    turtle.turnRight()
  end
  return false
end

-- Straight up to a height. A block overhead: sidestep and try again.
local function riseTo(y)
  local dodged = 0
  while pos.y < y do
    if not step("u") then
      if dodged >= 8 then return false end
      dodged = dodged + 1
      face((heading + 1) % 4)
      if not step("f") then face((heading + 1) % 4) end
    end
  end
  return true
end

-- Level flight to a column; anything in the way: go over it.
local function across(x, z, ceiling)
  for _, axis in ipairs({ "x", "z" }) do
    local target = axis == "x" and x or z
    while pos[axis] ~= target do
      if axis == "x" then face(target > pos.x and 0 or 2) else face(target > pos.z and 1 or 3) end
      if not step("f") then
        if pos.y >= ceiling or not step("u") then return false end
      end
      tick()
    end
  end
  return true
end

-- To a spot on the site, staying low: over what is in the way, then down
-- onto it. False if the spot cannot be reached from above.
local function flyTo(x, y, z, ceiling)
  while pos.y < y do
    if not step("u") then return false end
  end
  if not across(x, z, ceiling) then return false end
  while pos.y > y do
    if not step("d") then return false end
  end
  return pos.x == x and pos.y == y and pos.z == z
end

---------------------------------------------------------------- the hut

local function slot() return os.getComputerID() % 4 end
local function highway() return (st.job and st.job.oy or base.f.y) + OVER_SITE + 2 * slot() end
-- where we wait: in the open air beside the hole over the launch pad
local function hover()
  local e = base.exit2
  return e.x + 3 + 2 * slot(), base.f.y + 12, e.z - 4
end

local function goHover()
  local x, y, z = hover()
  if pos.y < y then riseTo(y) end
  if not across(x, z, highway() + 12) then return false end
  while pos.y > y and step("d") do end
  return true
end

-- Down the hole onto the launch pad. Only earth and stone in the hole is
-- ever dug (it was open when this was written; it may have been patched).
local function downToPad()
  local e, pad = base.exit2, base.pad
  if not across(e.x, e.z, highway() + 12) then return false end
  while pos.y > pad.y do
    local ok, why = step("d")
    if not ok then
      local natural = why == "minecraft:stone" or why == "minecraft:cobblestone"
        or why == "minecraft:dirt" or why == "minecraft:grass_block"
      if natural and pos.y > pad.y + 2 then
        turtle.digDown()
      else
        return false                          -- someone on the pad: try later
      end
    end
  end
  return true
end

local function upFromPad()
  local _, y = hover()
  while pos.y < y do
    local ok, why = step("u")
    if not ok then
      if why == "minecraft:stone" or why == "minecraft:cobblestone" or why == "minecraft:dirt" then
        turtle.digUp()
      else
        report("stuck under " .. tostring(why):gsub("^.*:", ""))
        sleep(5)
      end
    end
  end
end

---------------------------------------------------------------- the plan

local function loadList(job)
  local file = job.plan .. ".list"
  if not fs.exists(file) then
    print("Downloading the building plan.")
    local rev = "main"
    if fs.exists(".version") then
      local h = fs.open(".version", "r")
      rev = h.readAll():gsub("%s", "")
      h.close()
    end
    local res = http and http.get(LIST_URL:format(rev ~= "" and rev or "main", job.plan))
    if not res then error("Could not download the building plan.", 0) end
    local h = fs.open(file, "w")
    h.write(res.readAll())
    h.close()
    res.close()
  end
  local h = fs.open(file, "r")
  local pal, blocks, mode = {}, {}, nil
  while true do
    local line = h.readLine()
    if not line then break end
    local tag = line:match("^([PB]) %d+$")
    if tag then
      mode = tag
    elseif mode == "P" then
      local name, facing = line:match("^(%S+) (%S+)$")
      pal[#pal + 1] = { name = name, facing = facing ~= "-" and facing or nil }
    elseif mode == "B" then
      local x, y, z, i = line:match("^(-?%d+) (-?%d+) (-?%d+) (%d+)$")
      x, y = tonumber(x), tonumber(y)
      -- only our share: our strip of the plan, from our layer up
      if x and x >= job.xmin and x <= job.xmax and y >= job.layer then
        blocks[#blocks + 1] = { x, y, tonumber(z), tonumber(i) + 1 }
      end
    end
  end
  h.close()
  list = { pal = pal, blocks = blocks }
  return list
end

---------------------------------------------------------------- materials

-- What the next part of our share needs, up to a load.
local function nextLoad(indices)
  if type(indices) == "function" then return indices() end
  local counts, order, stacks = {}, {}, 0
  local n = type(indices) == "number" and (#list.blocks - indices + 1) or #indices
  for k = 1, n do
    local i = type(indices) == "number" and (indices + k - 1) or indices[k]
    local name = list.pal[list.blocks[i][4]].name
    if not (st.short and st.short[name]) then
      if not counts[name] then counts[name] = 0 order[#order + 1] = name end
      if counts[name] % 64 == 0 then
        if stacks >= LOAD_STACKS then break end
        stacks = stacks + 1
      end
      counts[name] = counts[name] + 1
    end
  end
  local items = {}
  for _, name in ipairs(order) do
    local have = 0
    for s = 1, 16 do
      local d = turtle.getItemDetail(s)
      if d and d.name == name then have = have + d.count end
    end
    if counts[name] > have then items[#items + 1] = { name, counts[name] - have } end
  end
  return items
end

-- Home for a load: wait in the air until the factory has it ready, drop
-- onto the pad, take it, and get straight back out of the way.
local function supplyRun(indices, reason, once)
  print("Going for a load: " .. reason)
  report("fetching materials")
  riseTo(highway())
  goHover()
  local me = os.getComputerID()
  while true do
    local items = nextLoad(indices)
    local coal = math.min(64, math.max(0, math.ceil((FULL_TANK - fuel()) / 80)))
    if #items == 0 and coal == 0 then return true end
    st.orderSeq = (st.orderSeq or (os.epoch("utc") % 1000000000)) + 1
    save()
    local msg = { type = "materials", id = me, n = st.orderSeq, items = items, fuel = coal }
    rednet.broadcast(msg, JOB_PROTOCOL)
    report("waiting for materials")
    local started, lastAsk, onPad, padSince, reply = os.clock(), os.clock(), false, 0, nil
    while os.clock() - started < 1800 do
      local _, m = rednet.receive(JOB_PROTOCOL, 20)
      if type(m) == "table" and m.forId == me and m.n == st.orderSeq then
        if m.type == "materials_ready" then reply = m break end
        if m.type == "load_ready" and not onPad then
          print("The load is ready. Down to the launch pad.")
          if downToPad() then
            onPad, padSince = true, os.clock()
          else
            upFromPad()
            goHover()
          end
        end
      end
      if onPad and os.clock() - padSince > 240 then      -- do not hog the pad
        upFromPad()
        goHover()
        onPad = false
      end
      if not onPad and os.clock() - lastAsk > 120 then
        rednet.broadcast(msg, JOB_PROTOCOL)
        lastAsk = os.clock()
      end
      tick("waiting for materials")
    end
    if onPad then upFromPad() end
    refuel(FULL_TANK)
    goHover()
    if reply then
      -- what the factory could not give at all is left for a second go
      local gotAny = false
      for _, n in pairs(reply.given or {}) do if n > 0 then gotAny = true end end
      for name in pairs(reply.missing or {}) do
        if not findSlot(name) then
          st.short = st.short or {}
          st.short[name] = true
          print("No " .. name:gsub("^.*:", "") .. " for now. Leaving those for later.")
        end
      end
      save()
      lastState = "building"
      if gotAny or fuel() > FUEL_SPARE * 2 then return true end
    end
    if once then return false end
    print("Nothing to be had yet. Waiting for the miners.")
    report("waiting for materials")
    sleep(240)
  end
end

---------------------------------------------------------------- building

local function facingOf(data)
  return type(data) == "table" and type(data.state) == "table" and data.state.facing or nil
end

local function isClutter(name)
  for _, w in ipairs(CLUTTER) do
    if name:find(w, 1, true) then return true end
  end
  return false
end

local function runBuild()
  local job = st.job
  loadList(job)
  local blocks, pal = list.blocks, list.pal
  local ceiling = job.oy + OVER_SITE + 12
  st.i = st.i or 1
  st.later = st.later or {}
  print(("My share: %d blocks of %s."):format(#blocks, job.plan:gsub("_", " ")))

  -- One block. True when done with it (placed, already there, skipped or
  -- put off); false to try it again after a load.
  local function doBlock(idx, rest, lastGo)
    local e = blocks[idx]
    local want = pal[e[4]]
    local wx, wy, wz = job.ox + e[1], job.oy + e[2], job.oz + e[3]
    if st.short and st.short[want.name] and not findSlot(want.name) then
      if not lastGo then st.later[#st.later + 1] = idx else st.left = (st.left or 0) + 1 end
      return true
    end
    if not findSlot(want.name) then
      supplyRun(rest, "out of " .. want.name:gsub("^.*:", ""))
      return false
    elseif fuel() < FUEL_SPARE + math.abs(pos.x - base.f.x) + math.abs(pos.z - base.f.z) then
      supplyRun(rest, "low on fuel")
      return false
    end
    -- from the hut (or anywhere off the site) come in high
    if math.abs(pos.x - wx) + math.abs(pos.z - wz) > 24 then
      riseTo(highway())
      across(wx, wz, ceiling)
    end
    if not flyTo(wx, wy + 1, wz, ceiling) then
      st.skipped = (st.skipped or 0) + 1
      if not lastGo then st.later[#st.later + 1] = idx end
      return true
    end
    local ok, data = turtle.inspectDown()
    local there = ok and data.name == want.name
      and (not want.facing or facingOf(data) == want.facing)
    if not there then
      if ok and (isClutter(data.name) or data.name == want.name) then turtle.digDown() end
      if want.facing then face((FACING[want.facing] + (st.turn or 0)) % 4) end
      turtle.select(findSlot(want.name))
      if turtle.placeDown() and want.facing then
        local _, d2 = turtle.inspectDown()
        local got = facingOf(d2)
        if got and FACING[got] and got ~= want.facing then
          -- learn how placing turns a block, then put it right
          st.turn = ((st.turn or 0) + FACING[want.facing] - FACING[got]) % 4
          turtle.digDown()
          face((FACING[want.facing] + st.turn) % 4)
          turtle.select(findSlot(want.name))
          turtle.placeDown()
        end
      end
      turtle.select(1)
    end
    return true
  end

  while st.i <= #blocks do
    progress = { kind = "building", done = st.i - 1, total = #blocks, layer = blocks[st.i][2],
      later = #st.later }
    if doBlock(st.i, st.i, false) then
      st.i = st.i + 1
      if st.i % 8 == 0 then save() end
    end
    tick("building")
  end
  -- a second go at what was put off (windows, lights, spots that were blocked)
  if #st.later > 0 then
    print(("Going back for %d I put off."):format(#st.later))
    st.short = nil
  end
  while #st.later > 0 do
    progress = { kind = "building", done = #blocks, total = #blocks, retry = #st.later }
    if doBlock(st.later[1], st.later, true) then
      table.remove(st.later, 1)
      save()
    end
    tick("building")
  end
  print(("Finished my share%s."):format((st.left or 0) > 0 and (", " .. st.left .. " left for the fit-out") or ""))
  st.done = true
  save()
end

---------------------------------------------------------------- lumberjack
-- chop: fell wild trees for charcoal. Given spots where the ground map saw
-- treetops, come down on each from above and follow the tree through its
-- leaves and logs, taking the lot (saplings drop into the inventory as the
-- leaves go). Only leaves and logs are ever broken, a canopy has to be met
-- before any log is touched, and nothing within reach of the base.
local CHOP_REACH  = 7      -- how far from where we came down a tree is followed
local CHOP_BUDGET = 500    -- blocks taken per treetop
local CHOP_LOAD   = 128    -- logs to carry before taking them home
local KEEP_OFF    = 16     -- no chopping this close to the base

local function isLog(name) return name ~= nil and name:find("_log$") ~= nil and not name:find("stripped") end
local function isLeaf(name) return name ~= nil and name:find("leaves", 1, true) ~= nil end

local function countLogs()
  local n = 0
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and isLog(d.name) then n = n + d.count end
  end
  return n
end

local function freeSlots()
  local n = 0
  for s = 1, 16 do if turtle.getItemCount(s) == 0 then n = n + 1 end end
  return n
end

local function look(dir)
  local ok, data = turtle["inspect" .. SUFFIX[dir]]()
  return ok and data.name or nil
end

-- Follow the tree from where we are: into every leaf or log next to us,
-- and back. Leaves are only followed a few steps from the last log.
local function fell(x0, z0, leafRun, left)
  local function try(dir, d)
    if left.n <= 0 then return end
    if d then face(d) end
    local name = look(dir)
    local log = isLog(name)
    if not (log or (isLeaf(name) and leafRun < 5)) then return end
    local nx = pos.x + (dir == "f" and DIRS[heading].x or 0)
    local nz = pos.z + (dir == "f" and DIRS[heading].z or 0)
    if math.abs(nx - x0) > CHOP_REACH or math.abs(nz - z0) > CHOP_REACH then return end
    if math.abs(nx - base.f.x) <= KEEP_OFF and math.abs(nz - base.f.z) <= KEEP_OFF then return end
    if not turtle["dig" .. SUFFIX[dir]]() then return end
    left.n = left.n - 1
    if not step(dir) then return end
    fell(x0, z0, log and 0 or leafRun + 1, left)
    if dir == "u" then step("d")
    elseif dir == "d" then step("u")
    else
      face(d)
      if turtle.back() then
        pos.x, pos.z = pos.x - DIRS[heading].x, pos.z - DIRS[heading].z
      end
    end
  end
  try("d")
  for d = 0, 3 do try("f", d) end
  try("u")
end

-- Logs (and saplings and the rest) into the miners' drop-off chest: down
-- the hole to the level above the pad, two steps along, drop, and out.
local function deliver()
  local e2, e1, dock = base.exit2, base.exit1, base.dock
  report("bringing logs home")
  riseTo(highway())
  for _ = 1, 20 do
    local done = false
    if across(e2.x, e2.z, highway() + 100) then
      local ok = true
      while ok and pos.y > e2.y do ok = step("d") end
      if ok then
        face(e1.x > e2.x and 0 or e1.x < e2.x and 2 or (e1.z > e2.z and 1 or 3))
        local s1 = step("f")
        local s2 = s1 and step("f")
        if s2 and pos.x == dock.x and pos.z == dock.z then
          for s = 1, 16 do
            local d = turtle.getItemDetail(s)
            if d and not isCoal(d.name) and not d.name:find("bucket") then
              turtle.select(s)
              turtle.dropDown()
            end
          end
          turtle.select(1)
          done = true
        end
        face((heading + 2) % 4)
        if s2 then step("f") end
        if s1 then step("f") end
      end
      upFromPad()
    end
    goHover()
    if done then return true end
    sleep(30)
  end
  return false
end

local function burnLogs()
  if fuel() >= 600 then return end
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and isLog(d.name) and fuel() < 900 then
      turtle.select(s)
      turtle.refuel(math.min(d.count, 24))
    end
  end
  turtle.select(1)
end

-- forage: sweep an area for trees nobody has mapped. Rows five apart,
-- flown a few blocks above the ground, so the turtle runs into the
-- canopies; every one it meets is felled.
local ROW_GAP, ABOVE_GROUND = 5, 4

local function toGroundLevel()
  local n = 0
  while n < 40 do
    local below = look("d")
    if isLeaf(below) then
      fell(pos.x, pos.z, 0, { n = CHOP_BUDGET })
    elseif below then
      break
    elseif not step("d") then
      break
    end
    n = n + 1
  end
  for _ = 1, ABOVE_GROUND do if not step("u") then break end end
end

local function runForage()
  local a = st.job.area
  local x1, x2 = math.min(a[1], a[3]), math.max(a[1], a[3])
  local z1, z2 = math.min(a[2], a[4]), math.max(a[2], a[4])
  local rows = math.floor((z2 - z1) / ROW_GAP) + 1
  st.row = st.row or 0
  local top = highway() + 120
  while st.row < rows do
    local z = z1 + st.row * ROW_GAP
    local east = st.row % 2 == 0
    local from, to = east and x1 or x2, east and x2 or x1
    if st.rowX then from = st.rowX end
    report("looking for trees")
    riseTo(highway())
    across(from, z, top)
    toGroundLevel()
    local n, logs0 = 0, countLogs()
    while pos.x ~= to do
      face(east and 0 or 2)
      local ahead = look("f")
      if isLeaf(ahead) then
        local before = countLogs()
        fell(pos.x, pos.z, 0, { n = CHOP_BUDGET })
        if countLogs() > before then print(("A tree at %d, %d: %d logs."):format(pos.x, pos.z, countLogs() - before)) end
        face(east and 0 or 2)
      end
      if not step("f") then
        if pos.y >= top or not step("u") then break end
      else
        n = n + 1
        if n % 4 == 0 then
          toGroundLevel()
          burnLogs()
          progress = { kind = "foraging", done = st.row, total = rows, logs = countLogs() }
          tick("looking for trees")
          if countLogs() >= CHOP_LOAD or freeSlots() < 3 then
            st.rowX = pos.x
            save()
            deliver()
            if fuel() < 1200 then supplyRun(function() return {} end, "fuel", true) end
            riseTo(highway())
            across(st.rowX, z, top)
            toGroundLevel()
          end
        end
      end
    end
    st.row, st.rowX = st.row + 1, nil
    save()
  end
  if countLogs() > 0 then deliver() end
  print("Area searched.")
  st.done = true
  save()
end

local function runChop()
  local job = st.job
  st.ci = st.ci or 1
  local top = highway() + 100
  while st.ci <= #job.trees do
    progress = { kind = "chopping", done = st.ci - 1, total = #job.trees, logs = countLogs() }
    if fuel() < 600 then                       -- burn a few of our own logs
      for s = 1, 16 do
        local d = turtle.getItemDetail(s)
        if d and isLog(d.name) and fuel() < 900 then
          turtle.select(s)
          turtle.refuel(math.min(d.count, 24))
        end
      end
      turtle.select(1)
    end
    if countLogs() >= CHOP_LOAD or freeSlots() < 3 then
      deliver()
      if fuel() < 1200 then supplyRun(function() return {} end, "fuel", true) end
    end
    local t = job.trees[st.ci]
    report("chopping")
    riseTo(highway())
    if across(t[1], t[2], top) then
      -- come down onto the treetop: it has to be leaves we meet first
      local met
      while pos.y > base.f.y - 20 do
        met = look("d")
        if met then break end
        if not step("d") then break end
      end
      if isLeaf(met) and not (math.abs(pos.x - base.f.x) <= KEEP_OFF and math.abs(pos.z - base.f.z) <= KEEP_OFF) then
        local before = countLogs()
        fell(pos.x, pos.z, 0, { n = CHOP_BUDGET })
        print(("Tree %d of %d: %d logs."):format(st.ci, #job.trees, countLogs() - before))
      end
    end
    st.ci = st.ci + 1
    save()
    tick("chopping")
  end
  if countLogs() > 0 then deliver() end
  print("That is all the trees I was given.")
  st.done = true
  save()
end

---------------------------------------------------------------- jobs

local function work()
  locate()
  -- born on the launch pad (or restarted in the hole): straight up and out
  if pos.y <= base.f.y + 6 then
    if pos.x ~= base.pad.x or pos.z ~= base.pad.z then
      report("lost")
      error("I am down in the base and not on the launch pad.", 0)
    end
    upFromPad()
  end
  if not findHeading() then
    riseTo(pos.y + 3)
    if not findHeading() then error("I am boxed in.", 0) end
  end
  if st.job and not st.done and not st.paused then
    if st.job.area then runForage() elseif st.job.trees then runChop() else
      report("building")
      runBuild()
      lastState = "idle"
    end
  end
  riseTo(math.max(pos.y, base.f.y + 12))
  goHover()
  print(st.done and "Share done. Waiting for jobs." or "Waiting for jobs.")
  while true do
    report(st.paused and "stopped" or "idle")
    sleep(60)
  end
end

local function guarded(fn)
  return function()
    local ok, err = pcall(fn)
    if not ok then
      if err == "Terminated" then error(err, 0) end
      print("ERROR: " .. tostring(err))
      while true do report("error") sleep(60) end
    end
  end
end

st = loadTable(STATE_FILE) or {}
base = loadTable(BASE_FILE)
if not base then error("No base details (.base).", 0) end
if not swarm then
  work()
  return
end
swarm.open()
local task = guarded(work)
while true do
  local cmd = swarm.runWithCommands(task, function(c)
    if c.cmd == "ping" then
      report(lastState)
      return true
    end
  end)
  if not cmd then
    task = function() while true do report(lastState) sleep(60) end end
  elseif cmd.cmd == "reboot" then
    swarm.pinVersion(cmd)
    report("rebooting")
    os.reboot()
  elseif cmd.cmd == "stop" then
    st.paused = true
    save()
    task = guarded(work)
  elseif cmd.cmd == "resume" then
    st.paused = nil
    save()
    task = guarded(work)
  elseif cmd.cmd == "chop" and type(cmd.area) == "string" then
    -- search an area for trees and fell them: area = "x1:z1:x2:z2"
    local x1, z1, x2, z2 = cmd.area:match("^(-?%d+):(-?%d+):(-?%d+):(-?%d+)$")
    if x1 then
      st = { job = { area = { tonumber(x1), tonumber(z1), tonumber(x2), tonumber(z2) } },
        turn = st.turn, orderSeq = st.orderSeq }
      save()
      task = guarded(work)
    end
  elseif cmd.cmd == "chop" and type(cmd.trees) == "string" then
    -- fell wild trees: trees = "x:z;x:z;..." (treetops from the ground map)
    local trees = {}
    for x, z in cmd.trees:gmatch("(-?%d+):(-?%d+)") do trees[#trees + 1] = { tonumber(x), tonumber(z) } end
    if #trees > 0 then
      st = { job = { trees = trees }, turn = st.turn, orderSeq = st.orderSeq }
      save()
      task = guarded(work)
    end
  elseif cmd.cmd == "build" and type(cmd.plan) == "string" and cmd.plan:match("^[%w_%-]+$")
    and tonumber(cmd.ox) and tonumber(cmd.oy) and tonumber(cmd.oz) then
    local job = {
      plan = cmd.plan,
      ox = math.floor(tonumber(cmd.ox)), oy = math.floor(tonumber(cmd.oy)), oz = math.floor(tonumber(cmd.oz)),
      xmin = math.floor(tonumber(cmd.xmin) or -1000), xmax = math.floor(tonumber(cmd.xmax) or 1000),
      layer = math.floor(tonumber(cmd.layer) or -1000),
    }
    local file = job.plan .. ".list"
    if fs.exists(file) then fs.delete(file) end
    st = { job = job, turn = st.turn, orderSeq = st.orderSeq }
    save()
    task = guarded(work)
  end
end
