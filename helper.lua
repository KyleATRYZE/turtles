-- helper.lua : a builder's mate. A mining turtle (pickaxe + ender modem, no
-- scanner) that places part of a building plan while BlockParty does the
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
-- the Mekanism line in the foundry bay (foundry.lua): worked by a helper
-- that has been told to (the order: foundry)
local okFoundry, foundry = pcall(require, "foundry")
if not okFoundry or type(foundry) ~= "table" then foundry = nil end

-- A Chunk Controller of my own (if I carry one) keeps my chunk loaded where
-- nobody is about: worn in place of the pickaxe whenever I am not digging
-- (see swarm.lua). Every dig puts the pickaxe back on first.
local CHUNKY = "advancedperipherals:chunk_controller"
local chunky = swarm and swarm.chunky or nil
if chunky and turtle and not turtle.chunkyDigs then
  turtle.chunkyDigs = true
  -- (and every swing at a mob in the way: that needs the pickaxe too)
  for _, n in ipairs({ "dig", "digUp", "digDown", "attack", "attackUp", "attackDown" }) do
    local raw = turtle[n]
    turtle[n] = function(...)
      chunky.tool()
      return raw(...)
    end
  end
end
-- (the pickaxe and the controller are my own kit: never handed in or dumped)
local function isKit(name)
  return name == CHUNKY or name:find("pickaxe", 1, true) ~= nil
end

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
  -- a lava bucket on board is 1,000 moves of fuel: drink it when there is room
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    local level = turtle.getFuelLevel()
    if d and d.name == "minecraft:lava_bucket" and type(level) == "number" and level < 2000
      and not (st and (st.feed or st.lab)) then
      turtle.select(s)
      turtle.refuel(1)
      turtle.select(1)
    end
  end
  -- not digging just now: the controller goes on (the lab bench swaps tools
  -- by hand, so not there)
  if chunky and not (st and st.lab) then chunky.keep(pos.x, pos.z) end
  if not swarm then return end
  local f = turtle.getFuelLevel()
  local inv = {}
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d then inv[d.name] = (inv[d.name] or 0) + d.count end
  end
  pcall(swarm.report, {
    role = "helper", state = lastState, inv = inv, lab = st and st.labOut,
    foundry = foundry and select(2, pcall(foundry.info)) or nil,
    pos = { x = pos.x, y = pos.y, z = pos.z },
    fuel = f == "unlimited" and -1 or f,
    progress = progress, log = logLines,
    chunky = chunky and chunky.have() and (chunky.isWorn() and "on" or "carried") or nil,
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

local function isCoal(name)
  return name == "minecraft:coal" or name == "minecraft:charcoal" or name == "minecraft:lava_bucket"
end

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
    local moved, whyNot = turtle[MOVE[dir]]()
    if moved then
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
      if waited == 4 then
        print("Cannot move " .. dir .. ": " .. tostring(whyNot))
        report("cannot move: " .. tostring(whyNot))
      end
      waited = waited + 1
      sleep(0.5)
    elseif name and name:find("leaves", 1, true) and waited < 40 then
      -- leaves are never worth being stuck behind (it once sat boxed in a
      -- treetop, unable to fly home): through them
      turtle["dig" .. SUFFIX[dir]]()
      waited = waited + 1
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

-- The drone lane (filled in further down): with the pads on the lane inside
-- the factory, a helper inside it leaves by the east gate before climbing.
local LN = {}

-- Straight up to a height. A block overhead: sidestep and try again.
local function riseTo(y)
  if y > pos.y and LN.inside and LN.inside() then LN.exit() end
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

-- Each helper has its own waiting spot and flying height (two with the same
-- id % 4 used to stack up on one spot).
local SLOTS = { Pushy = 0, HopTo = 1, LeverAlone = 2, DropIt = 3 }
local function slot() return SLOTS[os.getComputerLabel() or ""] or (os.getComputerID() % 4) end
local function highway() return (st.job and st.job.oy or base.f.y) + OVER_SITE + 2 * slot() end
-- where we wait: in the open air beside the hole over the launch pad (12
-- above the factory; a rebase order can raise that, base.hoverUp, so the
-- row clears the roof of a building the pad is in)
local function hoverAir()
  local e = base.exit2
  return e.x + 3 + 2 * slot(), base.f.y + (tonumber(base.hoverUp) or 12), e.z - 4
end

---------------------------------------------------------------- the drone lane
-- With base.lane (a rebase order with lane=1; swarm.lua M.LANE) the launch
-- pads are on the drone lane along the factory's back wall, and a helper
-- comes and goes by it, at the lane's height (L.y):
--   in from the west: down outside the west gate, in on the front track
--     (eastbound), along it to the pad's x, a step north onto the pad;
--   in from the east: down outside the east gate, in on the back track
--     (westbound), along it onto the pad (over Crafty's stop, a block
--     higher, for a pad beyond it);
--   off a pad: a step south onto the front track; then east to its home in
--     the rack (a step south into it, low or high) or out of the east gate.
-- It waits for a load, and between jobs, in its home rather than hovering.
-- Homes go by name (the factory's helper names, in order), else by id.
local HOMES = { "Pushy", "HopTo", "LeverAlone", "DropIt", "Sticky", "Dusty", "OnRepeat", "Comparable",
  "Observant", "Dispensable", "ButtonUp", "PlateUp", "Tripwired", "LampLit", "NoteWorthy", "TargetLock" }
function LN.on() return type(base) == "table" and type(base.lane) == "table" end
function LN.inside()
  if not LN.on() then return false end
  local L = base.lane
  return pos.y >= L.y - 1 and pos.y <= L.y + 1 and pos.z >= L.back and pos.z <= L.rackZ
    and pos.x >= L.west and pos.x <= L.east
end
-- on the lane, or on one of its tracks just outside a gate
function LN.onTrack()
  local L = base.lane
  return LN.inside() or (pos.y == L.y and (pos.z == L.front or pos.z == L.back)
    and pos.x >= L.west - 4 and pos.x <= L.east + 3)
end
-- is a pad on the lane? (before the move it is still at the old base: the
-- lane is only the way home to the rack, and the pad is reached as before)
function LN.padOnLane(p)
  local L = base.lane
  return type(p) == "table" and p.y >= L.y - 1 and p.y <= L.y + 1 and p.z >= L.back and p.z <= L.front
    and p.x >= L.west and p.x <= L.east
end
function LN.home()
  local L = base.lane
  local label, i = os.getComputerLabel() or "", nil
  for k, n in ipairs(HOMES) do if n == label then i = k - 1 end end
  i = i or (os.getComputerID() % (2 * L.perRow))
  return L.rackX + i % L.perRow, i < L.perRow and L.low or L.high, L.rackZ
end
function LN.go(dir, n)
  face(dir)
  for _ = 1, n do
    if not step("f") then return false end
    tick()
  end
  return true
end
function LN.toY(y)
  while pos.y < y do if not step("u") then return false end end
  while pos.y > y do if not step("d") then return false end end
  return true
end
function LN.east(x) return pos.x >= x or LN.go(0, x - pos.x) end
-- westbound on the back track to x: over Crafty's stop (a block higher)
-- when x is beyond it, then down to the lane's height
function LN.west(x)
  local L = base.lane
  while pos.x > x do
    if x < base.pad.x and pos.x <= base.pad.x + 1 and pos.y == L.y then
      if not step("u") then return false end
    end
    if not LN.go(2, 1) then return false end
  end
  return LN.toY(L.y)
end
-- onto the front track at the lane's height (from a home, a pad or the back
-- track: across first, as the front track is open all the way up)
function LN.toFront()
  local L = base.lane
  if pos.z == L.rackZ and not LN.go(3, 1) then return false end
  if pos.z == L.back and not LN.go(1, 1) then return false end
  return LN.toY(L.y) and pos.z == L.front
end
-- from outside: down to a gate's approach, on the line of its track
function LN.enter(east)
  local L = base.lane
  local a = east and L.eastIn or L.westIn
  riseTo(math.max(pos.y, highway()))
  if not across(a.x, a.z, math.max(highway() + 12, pos.y + 40)) then return false end
  return LN.toY(L.y)
end
function LN.toPad(p)
  local L = base.lane
  if not LN.onTrack() and not LN.enter(pos.x > (L.west + L.east) / 2) then return false end
  if pos.z == L.rackZ and not LN.toFront() then return false end
  if pos.z == L.back and pos.x < p.x and not LN.toFront() then return false end
  if pos.z == L.front then
    if pos.x <= p.x then
      if not LN.east(p.x) then return false end
      return LN.go(3, 1) and pos.x == p.x and pos.z == p.z
    end
    if not LN.go(3, 1) then return false end           -- (behind it: to the back track)
  end
  return LN.west(p.x) and pos.x == p.x and pos.z == p.z and pos.y == p.y
end
-- to the row just over a pad (to set something down on it), a pad taken or not
function LN.over(p)
  local L = base.lane
  if not LN.onTrack() and not LN.enter(pos.x > (L.west + L.east) / 2) then return false end
  if not LN.toFront() then return false end
  if pos.x <= p.x then
    return LN.east(p.x) and LN.toY(L.y + 1) and LN.go(3, 1) and pos.z == p.z
  end
  return LN.go(3, 1) and LN.toY(L.y + 1) and LN.go(2, pos.x - p.x) and pos.x == p.x
end
function LN.toHome()
  local hx, hy, hz = LN.home()
  if pos.x == hx and pos.y == hy and pos.z == hz then return true end
  if not LN.onTrack() and not LN.enter(false) then return false end   -- (homes are reached eastbound)
  if not LN.toFront() then return false end
  if pos.x > hx then                                   -- behind it: round by the back track
    if not (LN.go(3, 1) and LN.west(hx) and LN.go(1, 1)) then return false end
  end
  return LN.east(hx) and LN.toY(hy) and LN.go(1, 1) and pos.z == hz
end
-- out of the lane by the east gate (to climb outside)
function LN.exit()
  local L = base.lane
  return LN.toFront() and LN.east(L.eastOut.x)
end

-- The loading bay: docked in its home, the helper touches the shelf's
-- wired modem (above a low home, below a high one) and so is on the cable
-- as turtle_<id>. Crafty pushes its load straight in. Nil if the modem is
-- not there or not switched on.
function LN.bay()
  for _, side in ipairs({ "top", "bottom" }) do
    if peripheral.getType(side) == "modem" then
      local okW, wireless = pcall(peripheral.call, side, "isWireless")
      if okW and not wireless then
        local ok, name = pcall(peripheral.call, side, "getNameLocal")
        if ok and type(name) == "string" then return name end
      end
    end
  end
end

local function hover()
  if LN.on() then return LN.home() end
  return hoverAir()
end

local escape     -- defined further down (a way out of a place with no way straight up)

local function goHover()
  if LN.on() then
    if LN.toHome() then return true end
    print("Could not get into my home in the rack: waiting outside.")
    if LN.inside() then LN.exit() end
  end
  local x, y, z = hoverAir()
  if pos.y < y then riseTo(y) end
  -- (from up a mountain we may already be above the usual flying height)
  if not across(x, z, math.max(highway() + 12, pos.y + 40)) then
    -- shut in (a lumberjack inside a big tree, say): find the way out, then home
    if not escape(600) then return false end
    if not across(x, z, math.max(highway() + 12, pos.y + 40)) then return false end
  end
  while pos.y > y and step("d") do end
  return true
end

-- Down the hole onto the launch pad. Only earth and stone in the hole is
-- ever dug (it was open when this was written; it may have been patched).
local padAt                          -- the pad (and dispenser) of the load being fetched
local function downToPad()
  if LN.on() and LN.padOnLane(padAt and padAt.pad or base.pad) then return LN.toPad(padAt and padAt.pad or base.pad) end
  if LN.on() and LN.inside() then riseTo(highway()) end    -- (out of the lane first: the pad is elsewhere)
  local e, pad = base.exit2, base.pad
  if padAt then e, pad = { x = padAt.pad.x, z = padAt.pad.z }, padAt.pad end
  if not across(e.x, e.z, math.max(highway() + 12, pos.y + 40)) then return false end
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
  if LN.on() and LN.padOnLane(base.pad) and LN.inside() then return LN.toFront() end   -- (off the pad onto the front track)
  local _, y = hoverAir()
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

-- Down the hole to just above the launch pad (to set something on it).
local function overPad()
  if LN.on() and LN.padOnLane(base.pad) then return LN.over(base.pad) end   -- (the row over the pads)
  if LN.on() and LN.inside() then riseTo(highway()) end
  local e, pad = base.exit2, base.pad
  if not across(e.x, e.z, math.max(highway() + 12, pos.y + 40)) then return false end
  while pos.y > pad.y + 1 do
    if not step("d") then return false end
  end
  return true
end

-- Station computers (the screens'). A blank computer set on the launch pad
-- touches the disk drive under it: switched on, it boots from the factory's
-- floppy, installs itself, takes the name station-<number> and switches
-- off. Dug up again it keeps its name, number and files, so it can be
-- carried to its post and switched on there. Does up to n of the blank
-- computers on board; returns how many are ready and a note for each.
local function bootstrap(name, n)
  local ready, notes = 0, {}
  local function named(s)
    local d = turtle.getItemDetail(s, true)
    local label = d and d.name == name and d.displayName or ""
    return label:find("^station%-") and label or nil
  end
  local function blank()
    for s = 1, 16 do
      local d = turtle.getItemDetail(s)
      if d and d.name == name and not named(s) then return s end
    end
  end
  for s = 1, 16 do if named(s) then ready = ready + 1 end end
  if not blank() or n <= 0 then return ready, notes end
  if not overPad() then return ready, { "could not get down to the launch pad" } end
  local done = 0
  while done < n do
    local s = blank()
    if not s then break end
    done = done + 1
    local waited = 0
    while turtle.detectDown() and waited < 90 do      -- someone on the pad: give them time
      sleep(3)
      waited = waited + 3
    end
    if turtle.detectDown() then notes[#notes + 1] = "the pad is taken" break end
    turtle.select(s)
    if not turtle.placeDown() then notes[#notes + 1] = "it would not go down" break end
    sleep(0.5)
    pcall(peripheral.call, "bottom", "turnOn")
    local t0, seenOn = os.clock(), false
    while os.clock() - t0 < 150 do                    -- (the download takes a little while)
      sleep(1)
      local ok, on = pcall(peripheral.call, "bottom", "isOn")
      if ok and on then seenOn = true end
      if ok and not on and (seenOn or os.clock() - t0 > 15) then break end
      report("setting up a computer")
    end
    pcall(peripheral.call, "bottom", "shutdown")
    local okL, label = pcall(peripheral.call, "bottom", "getLabel")
    label = okL and type(label) == "string" and label or nil
    sleep(0.3)
    local seen, data = turtle.inspectDown()
    if seen and data.name == name then turtle.digDown() end
    if label and label:find("^station%-") then
      ready = ready + 1
      notes[#notes + 1] = label
    else
      notes[#notes + 1] = "one did not set itself up" .. (seenOn and "" or " (it never came on)")
      break                                           -- (no use trying the rest the same way)
    end
  end
  turtle.select(1)
  return ready, notes
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

-- With no Chunk Controller on board, ask the factory for one to carry: it
-- comes with the load, if there is one to spare (asked for at most every
-- 20 minutes; an hour after being told there is none).
local ctlAsked, ctlNone = -10000, -10000
local function askController()
  if not chunky or chunky.have(true) then return end
  if os.clock() - ctlAsked < 1200 or os.clock() - ctlNone < 3600 then return end
  ctlAsked = os.clock()
  rednet.broadcast({ type = "controller_request", id = os.getComputerID() }, JOB_PROTOCOL)
end

-- What goes back to the factory with a load: emptied lava buckets (not on a
-- lab run: buckets a lab run fetched stay on board, as they were handed
-- straight back and lava rounds went out with none), and, for the lab
-- bench, everything it was not sent for. Never the kit.
local function handsBack(it)
  local bench = st.lab or st.fdy
  local spare = bench and bench.keep and not bench.keep[it.name]
  local wanted = bench and bench.want and bench.want[it.name]
  return ((it.name == "minecraft:bucket" and not wanted and not st.lab) or spare) and not isKit(it.name) or false
end

-- Home for a load: wait in the air until the factory has it ready, drop
-- onto the pad, take it, and get straight back out of the way. (On the drone
-- lane: wait docked in the rack, where it comes in over the cable.)
local function supplyRun(indices, reason, once)
  print("Going for a load: " .. reason)
  report("fetching materials")
  local hx, hy, hz = hover()
  if not (pos.x == hx and pos.y == hy and pos.z == hz) then   -- (already waiting there: no detour)
    if not LN.inside() then riseTo(highway()) end
    goHover()
  end
  local me = os.getComputerID()
  local noBay = false                -- (the bay gave what it could: the rest from the pad)
  while true do
    local retryNow = false
    local items = nextLoad(indices)
    local coal = math.min(64, math.max(0, math.ceil((FULL_TANK - fuel()) / 80)))
    if st.feed then coal = 26 end       -- fuel to carry out to a stranded turtle
    local bench = st.lab or st.fdy      -- the lab bench, or the foundry: fetching parts, not building
    if bench and fuel() > 600 then coal = 0 end   -- (parts only: coal on board is not for burning)
    if bench and bench.handin then coal = math.max(coal, 1) end   -- (a reason to be called onto the pad)
    if #items == 0 and coal == 0 then return true end
    st.orderSeq = (st.orderSeq or (os.epoch("utc") % 1000000000)) + 1
    save()
    local msg = { type = "materials", id = me, n = st.orderSeq, items = items, fuel = coal }
    -- docked in a loading bay: the load comes in over the cable, and what
    -- goes back (emptied buckets, a bench's spare parts) is taken from us
    local bay = LN.on() and not noBay and LN.bay() or nil
    if bay then
      msg.bay, msg.back = bay, {}
      for s = 1, 16 do
        local it = turtle.getItemDetail(s)
        if it and handsBack(it) then msg.back[#msg.back + 1] = s end
      end
      print("Docked in my bay (" .. bay .. "): the load comes over the cable.")
    elseif LN.on() then
      print("No bay modem switched on in my home: fetching from the pad.")
      report("bay modem off")
    end
    rednet.broadcast(msg, JOB_PROTOCOL)
    askController()
    report("waiting for materials")
    local started, lastAsk, onPad, padSince, reply = os.clock(), os.clock(), false, 0, nil
    while os.clock() - started < 1800 do
      local _, m = rednet.receive(JOB_PROTOCOL, 20)
      if type(m) == "table" and m.forId == me and m.n == st.orderSeq then
        if m.type == "materials_ready" then
          reply = m
          if m.bay then turtle.select(1) end      -- (it came over the cable: nothing to drop)
          break
        end
        if m.type == "load_ready" and not onPad then
          padAt = type(m.pad) == "table" and type(m.at) == "table" and { pad = m.pad, f = m.at } or nil
          print("The load is ready. Down to the launch pad.")
          if downToPad() then
            onPad, padSince = true, os.clock()
          else
            upFromPad()
            goHover()
          end
        end
      elseif type(m) == "table" and m.type == "controller_none" and m.forId == me then
        ctlNone = os.clock()
      end
      if msg.bay and not onPad and os.clock() - started > 90 then
        -- nobody on the bay's cable can serve it (Crafty not moved in, no
        -- Sortnado): the same load from the pad
        print("Nobody served my bay: fetching from the pad.")
        noBay, retryNow = true, true
        break
      end
      if onPad and os.clock() - padSince > 240 then      -- do not hog the pad
        upFromPad()
        goHover()
        onPad = false
      end
      if os.clock() - lastAsk > 120 then               -- (the factory may have restarted)
        rednet.broadcast(msg, JOB_PROTOCOL)
        lastAsk = os.clock()
      end
      tick("waiting for materials")
    end
    if onPad then
      -- emptied lava buckets go back to the factory, right beside the pad
      for d = 0, 3 do
        local pf, pp = padAt and padAt.f or base.f, padAt and padAt.pad or base.pad
        if DIRS[d].x == pf.x - pp.x and DIRS[d].z == pf.z - pp.z then
          for s = 1, 16 do
            local it = turtle.getItemDetail(s)
            if it and handsBack(it) then
              face(d)
              turtle.select(s)
              turtle.drop()
            end
          end
          turtle.select(1)
        end
      end
      upFromPad()
    end
    if st.feed then
      goHover()
      for s = 1, 16 do
        local it = turtle.getItemDetail(s)
        if it and isCoal(it.name) then return true end
      end
      if once then return false end
    elseif st.lab or st.fdy then
      -- lava first: coal and charcoal on board may be what the lab was sent for
      for s = 1, 16 do
        local it = turtle.getItemDetail(s)
        if it and it.name == "minecraft:lava_bucket" and fuel() < FULL_TANK then
          turtle.select(s)
          turtle.refuel(1)
        end
      end
      turtle.select(1)
      if fuel() < 600 then refuel(FULL_TANK) end
      goHover()
    else
      refuel(FULL_TANK)
      goHover()
    end
    if reply and reply.by == "Sortnado" and next(reply.missing or {}) then
      -- the store gave what it had into the bay: the rest (things Crafty
      -- makes) from the pad, straight away
      print("The store gave what it had. The rest from the factory's pad.")
      noBay, retryNow, reply = true, true, nil
    end
    if reply then
      -- what the factory could not give at all is left for a second go
      local gotAny = false
      for _, n in pairs(reply.given or {}) do if n > 0 then gotAny = true end end
      local noRoom = {}
      for _, name in ipairs(reply.full or {}) do
        noRoom[name] = true
        print("No room on board for " .. name:gsub("^.*:", "") .. ": the factory has it.")
      end
      for name in pairs(reply.missing or {}) do
        if not findSlot(name) and not noRoom[name] then
          st.short = st.short or {}
          st.short[name] = true
          print("No " .. name:gsub("^.*:", "") .. " for now. Leaving those for later.")
        end
      end
      save()
      lastState = "building"
      if gotAny or fuel() > FUEL_SPARE * 2 then return true end
    end
    if not retryNow then
      if once then return false end
      print("Nothing to be had yet. Waiting for the miners.")
      report("waiting for materials")
      sleep(240)
    end
  end
end

---------------------------------------------------------------- building

-- Which way a block's front is. A barrel can face up or down as well as
-- round: a plain one says so in facing; a Sophisticated limited barrel in
-- vertical_facing ("up", "down", or "no" when it stands on its side), and
-- its horizontal_facing is then only which way it is turned. Put in from
-- above it lies face up, and its horizontal_facing still looks right.
local function facingOf(data)
  local s = type(data) == "table" and type(data.state) == "table" and data.state
  if not s then return nil end
  local v = s.vertical_facing
  if v ~= nil and v ~= "no" and v ~= "none" then return tostring(v) end
  return s.facing or s.horizontal_facing
end

-- Faces that way for certain: horizontal_facing alone does not say the
-- block is not lying on its back.
local function facesSurely(data, want)
  local s = type(data) == "table" and type(data.state) == "table" and data.state
  if not s or facingOf(data) ~= want then return false end
  return s.facing ~= nil or s.horizontal_facing == nil or s.vertical_facing ~= nil
end

-- Blocks whose front matters: put up from in front of them, and turned
-- round when found wrong even with none to spare (the one there is the one
-- to put back).
local function frontMatters(name)
  return name:find("monitor", 1, true) or name:find("barrel", 1, true)
    or name:find("sophisticatedstorage:", 1, true) == 1
end

-- Something with things in it is never dug: they would spill on the floor
-- and be lost. s = 0 below, 1 above, otherwise in front.
local function holdsThings(s)
  local side = s == 0 and "bottom" or s == 1 and "top" or "front"
  local ok, list = pcall(peripheral.call, side, "list")
  return ok and type(list) == "table" and next(list) ~= nil
end

-- A monitor put in from above lies on its back, screen to the ceiling
-- (orientation up), and will not join the ones standing beside it.
local function upright(data)
  local o = type(data) == "table" and type(data.state) == "table" and data.state.orientation
  return o == nil or o == "north"
end

-- A computer just put down is switched off. side = where it is from here.
local function wake(side)
  pcall(function()
    for _ = 1, 10 do
      if peripheral.getType(side) == "computer" then break end
      sleep(0.2)
    end
    if peripheral.getType(side) == "computer" and not peripheral.call(side, "isOn") then
      peripheral.call(side, "turnOn")
    end
  end)
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

---------------------------------------------------------------- fitting out
-- fit: the indoor work. The plan (tools/fitout.py) lists every job in an
-- order that can be done, each with the spot to stand on. The turtle knows
-- the whole building from the plans, so it finds its own way through the
-- rooms: in at the big door, round what is already fitted.
local STAND = { [0] = { 0, 1, 0 }, { 0, -1, 0 }, { 1, 0, 0 }, { 0, 0, 1 }, { -1, 0, 0 }, { 0, 0, -1 } }
local STAND_FACE = { [2] = 2, [3] = 3, [4] = 0, [5] = 1 }   -- standing east of it: face west...
local fitMap                                    -- what is where, in the plan's own coordinates

local function ck(x, y, z) return (x + 16) + (z + 16) * 128 + (y + 8) * 16384 end

local function fetchPlan(name)
  local file = name .. ".plan"
  if not fs.exists(file) then
    local rev = "main"
    if fs.exists(".version") then
      local f = fs.open(".version", "r")
      rev = f.readAll():gsub("%s", "")
      f.close()
    end
    local res = http and http.get(LIST_URL:format(rev ~= "" and rev or "main", name))
    -- (a plan newer than the code this turtle runs: take it from main)
    if not res and http then res = http.get(LIST_URL:format("main", name)) end
    if not res then error("Could not download " .. name .. ".", 0) end
    local f = fs.open(file, "w")
    f.write(res.readAll())
    f.close()
    res.close()
  end
  return fs.open(file, "r")
end

local function loadFit(job)
  local m = { solid = {}, ops = {}, pal = {} }
  local x1, y1, z1, x2, y2, z2 = 0, 0, 0, 0, 0, 0
  local f = fetchPlan(job.shell)
  local mode
  while true do
    local line = f.readLine()
    if not line then break end
    local tag = line:match("^([PB]) %d+$")
    if tag then
      mode = tag
    elseif mode == "B" then
      local x, y, z = line:match("^(-?%d+) (-?%d+) (-?%d+) ")
      x, y, z = tonumber(x), tonumber(y), tonumber(z)
      if x and y >= 0 then
        m.solid[ck(x, y, z)] = true
        x1, z1 = math.min(x1, x), math.min(z1, z)
        x2, y2, z2 = math.max(x2, x), math.max(y2, y), math.max(z2, z)
      end
    end
  end
  f.close()
  m.x1, m.z1, m.x2, m.y2, m.z2 = x1 - 4, z1 - 4, x2 + 4, y2 + 4, z2 + 4
  f = fetchPlan(job.plan)
  mode = nil
  while true do
    local line = f.readLine()
    if not line then break end
    local sx, sy, sz = line:match("^S (-?%d+) (-?%d+) (-?%d+)$")
    if sx then
      m.start = { tonumber(sx), tonumber(sy), tonumber(sz) }
    elseif line:match("^[PO] %d+$") then
      mode = line:sub(1, 1)
    elseif mode == "P" then
      local name, facing = line:match("^(%S+) (%S+)$")
      m.pal[#m.pal + 1] = { name = name, facing = facing ~= "-" and facing or nil }
    elseif mode == "O" then
      local t = {}
      for w in line:gmatch("%S+") do t[#t + 1] = w end
      if t[1] == "D" then
        m.ops[#m.ops + 1] = { k = "D", x = tonumber(t[2]), y = tonumber(t[3]), z = tonumber(t[4]), s = tonumber(t[5]) }
      else
        m.ops[#m.ops + 1] = { k = t[1], x = tonumber(t[2]), y = tonumber(t[3]), z = tonumber(t[4]),
          i = tonumber(t[5]) + 1, s = tonumber(t[6]) }
      end
    end
  end
  f.close()
  return m
end

-- the jobs already done change what is where
local function applyOp(op)
  local k = ck(op.x, op.y, op.z)
  if op.k == "D" then fitMap.solid[k] = nil else fitMap.solid[k] = true end
  -- a floor block the plan dug out is a hole the walker may stand in (to
  -- put a cable a block under the floor); filled again, it is floor
  if op.y == 0 then
    fitMap.dug = fitMap.dug or {}
    fitMap.dug[k] = op.k == "D" or nil
  end
end

local function lx() return pos.x - st.job.ox end
local function ly() return pos.y - st.job.oy end
local function lz() return pos.z - st.job.oz end

local function open(x, y, z)
  local m = fitMap
  if x < m.x1 or x > m.x2 or z < m.z1 or z > m.z2 or y < 0 or y > m.y2 then return false end
  if y == 0 and not (m.dug and m.dug[ck(x, y, z)]) then return false end
  return not m.solid[ck(x, y, z)]
end

-- Shortest way through open space from where we are to a cell (in the
-- plan's coordinates). Returns the list of moves, or nil.
local MOVES = { { 1, 0, 0, 0 }, { 0, 0, 1, 1 }, { -1, 0, 0, 2 }, { 0, 0, -1, 3 }, { 0, 1, 0, "u" }, { 0, -1, 0, "d" } }
local function route(tx, ty, tz)
  local sx, sy, sz = lx(), ly(), lz()
  if sx == tx and sy == ty and sz == tz then return {} end
  if not open(tx, ty, tz) then return nil end
  local goal = ck(tx, ty, tz)
  local from = { [ck(sx, sy, sz)] = false }
  local qx, qy, qz, head = { sx }, { sy }, { sz }, 1
  while head <= #qx do
    local x, y, z = qx[head], qy[head], qz[head]
    head = head + 1
    for _, mv in ipairs(MOVES) do
      local nx, ny, nz = x + mv[1], y + mv[2], z + mv[3]
      local nk = ck(nx, ny, nz)
      if from[nk] == nil and open(nx, ny, nz) then
        from[nk] = { ck(x, y, z), mv[4] }
        if nk == goal then
          local path, k = {}, goal
          while from[k] do
            table.insert(path, 1, from[k][2])
            k = from[k][1]
          end
          return path
        end
        qx[#qx + 1], qy[#qy + 1], qz[#qz + 1] = nx, ny, nz
      end
    end
    if head % 4000 == 0 then sleep(0) end          -- a long search: let others run
  end
  return nil
end

-- Go there. Something in the way that the plan does not know about: note
-- it and find another way.
local function goTo(tx, ty, tz)
  for _ = 1, 12 do
    local path = route(tx, ty, tz)
    if not path then return false end
    local ok = true
    for _, mv in ipairs(path) do
      local moved
      if mv == "u" or mv == "d" then
        moved = step(mv)
      else
        face(mv)
        moved = step("f")
      end
      if not moved then
        local x, y, z = lx(), ly(), lz()
        if mv == "u" then y = y + 1 elseif mv == "d" then y = y - 1
        else x, z = x + DIRS[mv].x, z + DIRS[mv].z end
        fitMap.solid[ck(x, y, z)] = true
        ok = false
        break
      end
      tick()
    end
    if ok then return true end
  end
  return false
end

-- between the hut and the building: high over everything, down in front
-- of the big door
local function intoBuilding()
  local m, job = fitMap, st.job
  local x, y, z = lx(), ly(), lz()
  if x >= m.x1 and x <= m.x2 and z >= m.z1 and z <= m.z2 and y >= 1 and y <= m.y2 and open(x, y, z) then
    return true
  end
  if fuel() < FUEL_SPARE then
    -- (it once set off on 73 after a restart and ran dry in mid-air)
    supplyRun(function() return {} end, "low on fuel")
  end
  riseTo(highway())
  across(job.ox + m.start[1], job.oz + m.start[3], highway() + 12)
  while ly() > m.start[2] do
    if not step("d") then break end
  end
  return true
end

local function outOfBuilding()
  local m = fitMap
  goTo(m.start[1], m.start[2], m.start[3])
  riseTo(highway())
end

-- The factory building: a helper that wakes up inside it (a restart, a
-- crash) walks out by the big door, the way the fit walker does, instead of
-- looking for open sky (which only took it up into the roof). Inside = under
-- the building's roof, by the as-fitted shell.
local FACTORY = { ox = -4448, oy = 71, oz = 1518, shell = "factory_asfit3", door = { 22, 2, 33 } }
local function loadShell(job)
  local m = { solid = {}, ops = {}, pal = {} }
  local x1, z1, x2, y2, z2 = 0, 0, 0, 0, 0
  local f = fetchPlan(job.shell)
  local mode
  while true do
    local line = f.readLine()
    if not line then break end
    local tag = line:match("^([PB]) %d+$")
    if tag then
      mode = tag
    elseif mode == "B" then
      local x, y, z = line:match("^(-?%d+) (-?%d+) (-?%d+) ")
      x, y, z = tonumber(x), tonumber(y), tonumber(z)
      if x and y >= 0 then
        m.solid[ck(x, y, z)] = true
        x1, z1 = math.min(x1, x), math.min(z1, z)
        x2, y2, z2 = math.max(x2, x), math.max(y2, y), math.max(z2, z)
      end
    end
  end
  f.close()
  m.x1, m.z1, m.x2, m.y2, m.z2 = x1 - 4, z1 - 4, x2 + 4, y2 + 4, z2 + 4
  return m
end

-- True (and the building's map) when we stand under the factory's roof.
local function inFactory()
  local x, y, z = pos.x - FACTORY.ox, pos.y - FACTORY.oy, pos.z - FACTORY.oz
  if x < 0 or x > 56 or z < 0 or z > 31 or y < 0 or y > 31 then return false end
  local ok, m = pcall(loadShell, FACTORY)
  if not ok then return false end
  for yy = y + 1, m.y2 do
    if m.solid[ck(x, yy, z)] then return true, m end
  end
  return false
end

-- Out by the big door, through the open space the shell knows of (anything
-- in the way that it does not know is gone round), then up to flying height.
local function leaveFactory(m)
  local saved, savedMap = st.job, fitMap
  st.job = { ox = FACTORY.ox, oy = FACTORY.oy, oz = FACTORY.oz }
  m.start = FACTORY.door
  fitMap = m
  print("Inside the factory: walking out by the big door.")
  report("leaving the factory")
  local ok = goTo(m.start[1], m.start[2], m.start[3])
  st.job, fitMap = saved, savedMap
  if ok then riseTo(math.max(pos.y, highway())) end
  return ok
end

local function runFit()
  local job = st.job
  fitMap = loadFit(job)
  local m = fitMap
  st.i = st.i or 1
  st.later = st.later or {}
  st.turns = st.turns or {}
  st.undone = st.undone or {}
  st.empty = st.empty or {}
  for i = 1, math.min(st.i - 1, #m.ops) do
    local o = m.ops[i]
    if not st.undone[i] and not (o.k == "D" and st.kept and st.kept[ck(o.x, o.y, o.z)]) then applyOp(o) end
  end
  -- two helpers can share the fit-out: each takes the jobs in its own strip
  -- (x from xmin to xmax) and takes the other's as done
  local function mine(op)
    return (not job.xmin or op.x >= job.xmin) and (not job.xmax or op.x <= job.xmax)
  end
  if job.xmin or job.xmax then
    local n = 0
    for _, op in ipairs(m.ops) do if mine(op) then n = n + 1 end end
    print(("Fitting out: %d of %d jobs are mine."):format(n, #m.ops))
  else
    print(("Fitting out: %d jobs."):format(#m.ops))
  end

  local function needs(from)
    return function()
      local counts, order, stacks = {}, {}, 0
      local list = type(from) == "table" and from or nil
      local n = list and #list or (#m.ops - from + 1)
      for k = 1, n do
        local op = m.ops[list and list[k] or (from + k - 1)]
        local name = op.k ~= "D" and m.pal[op.i].name
        -- (one of these already standing there is turned round, not
        -- replaced: none is fetched for it unless it was found missing)
        local standing = name and frontMatters(name) and m.solid[ck(op.x, op.y, op.z)]
          and not st.empty[ck(op.x, op.y, op.z)]
        if op.k ~= "D" and mine(op) and not standing then
          if not (st.short and st.short[name]) then
            if not counts[name] then counts[name] = 0 order[#order + 1] = name end
            if counts[name] % 64 == 0 then
              if stacks >= LOAD_STACKS then break end
              stacks = stacks + 1
            end
            counts[name] = counts[name] + 1
          end
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
  end

  -- what the plan leaves at each place it puts something
  local finalAt = {}
  for _, op in ipairs(m.ops) do
    if op.k ~= "D" then finalAt[ck(op.x, op.y, op.z)] = op end
  end

  local function act(verb, s)
    local sfx = s == 0 and "Down" or s == 1 and "Up" or ""
    return turtle[verb .. sfx]()
  end
  local function see(s)
    local ok, data = turtle["inspect" .. (s == 0 and "Down" or s == 1 and "Up" or "")]()
    return ok and data or nil
  end

  -- One job. True when finished with it (done, or given up on); false to
  -- try again (after fetching things).
  local function doOp(n, rest, lastGo)
    local op = m.ops[n]
    -- a take-out where a barrel, chest or monitor is to stand is done from
    -- that one's front (from the side it could be a wall or an old fitting)
    local forFront = false
    if op.k == "D" then
      local fop = finalAt[ck(op.x, op.y, op.z)]
      if fop and fop.s and fop.s >= 2 and frontMatters(m.pal[fop.i].name) then
        forFront = true
        if fop.s ~= op.s then op = { k = op.k, x = op.x, y = op.y, z = op.z, i = op.i, s = fop.s } end
      end
    end
    if not mine(op) then
      applyOp(op)
      return true
    end
    local want = op.k ~= "D" and m.pal[op.i] or nil
    local function putOff(why)
      if lastGo then
        st.left = (st.left or 0) + 1
        print(("Left: %s at %d %d %d (%s)."):format(want and want.name:gsub("^.*:", "") or "dig", op.x, op.y, op.z, why))
      else
        st.later[#st.later + 1] = n
      end
      st.undone[n] = true
      return true
    end
    -- None on board and none to be had: most things are then left. A screen's
    -- parts are looked at all the same: the one already there may be right,
    -- or only lying wrong (taken down, it is the one to put back).
    local lacking = want and not findSlot(want.name)
    local lookAnyway = lacking and (frontMatters(want.name) or want.name:find("computer", 1, true)
      or want.name:find("wireless_modem", 1, true))
    -- one standing there already (going by the shell): see to it before
    -- fetching any
    local lookFirst = lacking and frontMatters(want.name) and m.solid[ck(op.x, op.y, op.z)]
      and not st.empty[ck(op.x, op.y, op.z)]
    local short = lacking and st.short and st.short[want.name]
    local function fetch()
      outOfBuilding()
      supplyRun(needs(rest), "out of " .. want.name:gsub("^.*:", ""))
      intoBuilding()
      if not findSlot(want.name) then
        st.short = st.short or {}
        st.short[want.name] = true
      end
      return false
    end
    if short and not lookAnyway then
      return putOff("none to be had")
    elseif lacking and not short and not lookFirst then
      return fetch()
    elseif fuel() < FUEL_SPARE then
      outOfBuilding()
      supplyRun(needs(rest), "low on fuel")
      intoBuilding()
      return false
    end
    local d = STAND[op.s]
    if not goTo(op.x + d[1], op.y + d[2], op.z + d[3]) then
      if forFront and lastGo then
        -- (the job that puts the barrel here looks at this place from the
        -- same side: it finds out what is there and says so if it is wrong)
        st.undone[n] = nil
        return true
      end
      return putOff("cannot get to it")
    end
    if op.s >= 2 then face(STAND_FACE[op.s]) end
    local there = see(op.s)
    if op.k == "D" then
      -- the very thing the plan puts here (a barrel, chest or monitor) is
      -- already standing: leave it. Its own job turns it round if it faces
      -- wrong. (Not glass: a window taken out to get in is taken out again.)
      local fop = finalAt[ck(op.x, op.y, op.z)]
      local final = fop and m.pal[fop.i]
      if there and final and there.name == final.name and frontMatters(final.name) then
        st.kept = st.kept or {}
        st.kept[ck(op.x, op.y, op.z)] = true
        st.undone[n] = nil
        return true
      end
      if there and holdsThings(op.s) then
        -- (dug, a chest spills what is in it: someone empties it first)
        return putOff("a " .. there.name:gsub("^.*:", "") .. " with things in it")
      end
      if there then act("dig", op.s) end
      st.undone[n] = nil
      applyOp(op)
      return true
    end
    if lacking and not (there and there.name == want.name) then
      if short then return putOff("none to be had") end
      st.empty[ck(op.x, op.y, op.z)] = true          -- (not there after all: one is fetched for it)
      return fetch()
    end
    local right = there and there.name == want.name
      and (not want.facing or facesSurely(there, want.facing)) and upright(there)
    if not right then
      if there and (op.k == "R" or there.name == want.name or isClutter(there.name)) then
        if holdsThings(op.s) then
          return putOff("a " .. there.name:gsub("^.*:", "") .. " with things in it")
        end
        act("dig", op.s)
      elseif there then
        return putOff("a " .. there.name:gsub("^.*:", "") .. " is there")
      end
      local turn = st.turns[want.name] or 2
      if want.facing and op.s < 2 then face((FACING[want.facing] + turn) % 4) end
      turtle.select(findSlot(want.name))
      local placed = act("place", op.s)
      if placed and want.facing then
        local got = facingOf(see(op.s))
        if got and FACING[got] and got ~= want.facing and op.s < 2 then
          -- learn which way this kind of block ends up, and put it right
          st.turns[want.name] = (turn + FACING[want.facing] - FACING[got]) % 4
          turtle.select(1)
          act("dig", op.s)
          face((FACING[want.facing] + st.turns[want.name]) % 4)
          turtle.select(findSlot(want.name))
          act("place", op.s)
        end
      end
      turtle.select(1)
      if not placed and not see(op.s) then return putOff("it would not go in") end
      if placed and want.facing and op.s >= 2 and facingOf(see(op.s)) ~= want.facing then
        -- (put in from in front, it should face the turtle: say so if not)
        print(("%s at %d %d %d faces %s, not %s."):format(want.name:gsub("^.*:", ""), op.x, op.y, op.z,
          tostring(facingOf(see(op.s))), want.facing))
      end
    end
    -- a station computer (a screen's) is switched on where it stands
    if want.name:find("computer", 1, true) then
      wake(op.s == 0 and "bottom" or op.s == 1 and "top" or "front")
    end
    st.undone[n] = nil
    applyOp(op)
    return true
  end

  intoBuilding()
  while st.i <= #m.ops do
    progress = { kind = "fitting", done = st.i - 1, total = #m.ops, later = #st.later }
    if doOp(st.i, st.i, false) then
      st.i = st.i + 1
      if st.i % 8 == 0 then save() end
    end
    tick("fitting out")
  end
  if #st.later > 0 then
    print(("Going back for %d jobs I put off."):format(#st.later))
    st.short = nil
  end
  while #st.later > 0 do
    progress = { kind = "fitting", done = #m.ops, total = #m.ops, retry = #st.later }
    if doOp(st.later[1], st.later, true) then
      table.remove(st.later, 1)
      save()
    end
    tick("fitting out")
  end
  outOfBuilding()
  print(("Fit-out finished%s."):format((st.left or 0) > 0 and (", " .. st.left .. " jobs left undone") or ""))
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
local CHOP_BUDGET = 900    -- blocks taken (and spots looked at) per treetop
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
  left.seen = left.seen or {}
  local function try(dir, d)
    if left.n <= 0 then return end
    if d then face(d) end
    local name = look(dir)
    local log = isLog(name)
    local nx = pos.x + (dir == "f" and DIRS[heading].x or 0)
    local nz = pos.z + (dir == "f" and DIRS[heading].z or 0)
    local ny = pos.y + (dir == "u" and 1 or dir == "d" and -1 or 0)
    if math.abs(nx - x0) > CHOP_REACH or math.abs(nz - z0) > CHOP_REACH then return end
    if math.abs(nx - base.f.x) <= KEEP_OFF and math.abs(nz - base.f.z) <= KEEP_OFF then return end
    if name == nil and leafRun == 0 then
      -- open air beside a log: branches often run on corner to corner, so
      -- step out and look round for more logs (once per spot)
      local k = nx .. "," .. ny .. "," .. nz
      if left.seen[k] then return end
      left.seen[k] = true
      left.n = left.n - 1
      if not step(dir) then return end
      fell(x0, z0, 5, left)
      if dir == "u" then step("d") elseif dir == "d" then step("u")
      else
        face(d)
        if turtle.back() then pos.x, pos.z = pos.x - DIRS[heading].x, pos.z - DIRS[heading].z end
      end
      return
    end
    if not (log or (isLeaf(name) and leafRun < 5)) then return end
    if not turtle["dig" .. SUFFIX[dir]]() then return end
    left.n = left.n - 1
    if left.n % 25 == 0 then
      progress = { kind = "chopping", logs = countLogs(), left = left.n }
      report("felling a tree")
    end
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
    if across(e2.x, e2.z, math.max(highway() + 100, pos.y + 40)) then
      local ok = true
      while ok and pos.y > e2.y do ok = step("d") end
      if ok then
        face(e1.x > e2.x and 0 or e1.x < e2.x and 2 or (e1.z > e2.z and 1 or 3))
        local s1 = step("f")
        local s2 = s1 and step("f")
        if s2 and pos.x == dock.x and pos.z == dock.z then
          for s = 1, 16 do
            local d = turtle.getItemDetail(s)
            if d and not isCoal(d.name) and not d.name:find("bucket") and not isKit(d.name) then
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

-- Running low a long way from home: take what we have back and wait there
-- for a fuel-up, however long it takes (hovering costs nothing).
local function homeForFuel()
  if fuel() >= 250 then return false end
  burnLogs()
  print("Low on fuel. Going home for some.")
  if countLogs() > 0 then deliver() else riseTo(highway()) goHover() end
  supplyRun(function() return {} end, "fuel")
  return true
end

-- No walking about at ground level here: there is somebody's base inside the
-- mountain (a lumberjack once wandered into it). Rows fly over these boxes.
local NO_FORAGE = { { -4484, 1462, -4412, 1516 } }
local function noForage(x, z)
  for _, b in ipairs(NO_FORAGE) do
    if x >= b[1] and x <= b[3] and z >= b[2] and z <= b[4] then return b end
  end
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
    homeForFuel()
    report("looking for trees")
    riseTo(highway())
    across(from, z, top)
    if not noForage(pos.x, z) then toGroundLevel() end
    local n, logs0 = 0, countLogs()
    while pos.x ~= to do
      face(east and 0 or 2)
      local box = noForage(pos.x + (east and 1 or -1), z)
      if box then
        -- over the top of it, and down again on the far side
        local far = east and math.min(to, box[3] + 1) or math.max(to, box[1] - 1)
        riseTo(highway())
        across(far, z, top)
        if far == to then break end
        toGroundLevel()
      end
      local ahead = look("f")
      if isLog(ahead) then
        -- a trunk, or somebody's log wall? climb it: a tree has leaves
        local y0, leafy = pos.y, false
        while pos.y < y0 + 24 and isLog(look("f")) do
          if not step("u") then break end
        end
        leafy = isLeaf(look("f")) or isLeaf(look("u"))
        if not leafy then
          while pos.y > y0 and step("d") do end
          ahead = look("f")
        else
          ahead = "leaves"
        end
      end
      if isLeaf(ahead) then
        local before = countLogs()
        fell(pos.x, pos.z, 4, { n = CHOP_BUDGET })
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
          if countLogs() >= CHOP_LOAD or freeSlots() < 3 or fuel() < 250 then
            st.rowX = pos.x
            save()
            if not homeForFuel() then
              deliver()
              if fuel() < 1200 then supplyRun(function() return {} end, "fuel", true) end
            end
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

---------------------------------------------------------------- lost and found
-- escape: shut in somewhere with no way straight up (a cave, a hollow in a
-- hillside, somebody's cellar): search the open space, without breaking
-- anything, for a way out to open sky. Goes up wherever it can; comes back
-- to where it started if there is no way out. True when it is out, at
-- flying height.
escape = function(limit)
  limit = limit or 1500
  local seen, moves = {}, 0
  -- out = at flying height, and well clear above where we started (up a
  -- mountain, flying height can be inside the treetops)
  local goal = math.max(highway(), pos.y + 20)
  local function key(x, y, z) return x .. "," .. y .. "," .. z end
  local function visit(depth)
    seen[key(pos.x, pos.y, pos.z)] = true
    if pos.y >= goal then return true end
    if moves >= limit or depth > 600 then return false end
    if depth % 8 == 0 then tick("finding a way out") end
    -- up first
    if not seen[key(pos.x, pos.y + 1, pos.z)] and not turtle.detectUp() and step("u") then
      moves = moves + 1
      if visit(depth + 1) then return true end
      if step("d") then moves = moves + 1 else return false end
    end
    local first = heading
    for turn = 0, 3 do
      local d = (first + turn) % 4
      if not seen[key(pos.x + DIRS[d].x, pos.y, pos.z + DIRS[d].z)] then
        face(d)
        if not turtle.detect() and step("f") then
          moves = moves + 1
          if visit(depth + 1) then return true end
          face((d + 2) % 4)
          if step("f") then moves = moves + 1 else return false end
        else
          seen[key(pos.x + DIRS[d].x, pos.y, pos.z + DIRS[d].z)] = true
        end
      end
    end
    if not seen[key(pos.x, pos.y - 1, pos.z)] and not turtle.detectDown() and step("d") then
      moves = moves + 1
      if visit(depth + 1) then return true end
      if step("u") then moves = moves + 1 else return false end
    end
    return false
  end
  print("Looking for a way out to open sky.")
  report("finding a way out")
  local out = visit(0)
  print(out and ("Out, after " .. moves .. " moves.") or ("No way out found (" .. moves .. " moves)."))
  return out, moves
end

-- Blocks that are just ground: a rescue may dig straight down through these.
local GROUND = { "stone", "deepslate", "dirt", "grass_block", "gravel", "sand", "clay", "andesite",
  "diorite", "granite", "tuff", "cobblestone", "sandstone", "mud", "_ore", "calcite", "podzol" }
local function isGround(name)
  if not name then return false end
  for _, g in ipairs(GROUND) do if name:find(g, 1, true) then return true end end
  return false
end

---------------------------------------------------------------- lab bench
-- lab: try something out in the world, step by step, on remote orders, and
-- report what happened. For finding out how a machine from another mod
-- behaves before a whole routine is written around it. The order carries a
-- list of steps, "verb|arg|arg;verb|arg;...":
--   fetch|name=n,name=n     get these from the factory (fetch|...|dump also hands
--                           back everything else on board)
--   goto|x|y|z   ground   up|n   down|n   fwd|n   back|n   turn|left/right/around
--   place|item   placeUp|item   placeDown|item      dig   digUp   digDown
--   drop|item|n  dropUp|item|n  dropDown|item|n     suck|n  suckUp|n  suckDown|n
--   types|side   methods|side   call|side|method|arg|...   inspect|front/up/down
--   inv   fuel   wait|seconds   home   note|text
--   face|0..3 (east south west north)   escape|moves   digdown|y (plain ground only)
--   expect|front/up/down|text   (stop unless the block that way has text in its name)
--   until|side|method|n|seconds (wait for a machine's count to reach n)
--   equip|left/right|item       (swap the tool on that side for an item on board)
--   site|ox|oy|oz|shell|plan   walk|x|y|z   leave   (inside a building, by its plan)
--   handin|keep,keep            (everything else on board back to the factory)
--   pick|name,name  pickUp  pickDown  (dig only a block of these names; never a budding one)
-- Only machines, chests and computers are ever dug. Results are kept in
-- st.labOut and sent with every status report.
local LAB_DIG = { "mekanism", "computercraft:", "advancedperipherals:", "sophisticatedstorage:",
  "functionalstorage:", "ironfurnaces:", "minecraft:chest", "minecraft:furnace", "minecraft:barrel",
  -- the quartz line (tools/quartzline.py): its machines, and the soul sand made there
  "create:", "actuallyadditions:", "minecraft:soul_sand",
  -- (the lava farm's own cobblestone walls, when the row is extended)
  "minecraft:cobblestone", "minecraft:cauldron", "minecraft:pointed_dripstone" }

local function labValue(a)
  if a == "true" then return true elseif a == "false" then return false end
  if tonumber(a) then return tonumber(a) end
  if a:sub(1, 1) == "{" then
    local ok, t = pcall(textutils.unserialize, a)
    if ok and t ~= nil then return t end
  end
  return a
end

local function labShow(v)
  if type(v) ~= "table" then return tostring(v) end
  local ok, s = pcall(textutils.serialize, v, { compact = true })
  return ok and s or tostring(v)
end

local function runLab()
  local lab = st.lab
  st.labOut = st.labOut or {}
  local function out(text)
    text = tostring(text)
    while #text > 0 do
      st.labOut[#st.labOut + 1] = text:sub(1, 220)
      text = text:sub(221)
    end
    while #st.labOut > 70 do table.remove(st.labOut, 1) end
  end
  local steps = {}
  for s in lab.ops:gmatch("[^;]+") do steps[#steps + 1] = s end
  lab.i = lab.i or 1
  print(("Lab bench: %d steps."):format(#steps))
  local SFX = { [""] = "", Up = "Up", Down = "Down" }
  while lab.i <= #steps do
    local a = {}
    for w in (steps[lab.i] .. "|"):gmatch("(.-)|") do a[#a + 1] = w end
    local verb = a[1]
    local base, sfx = verb:match("^(%l+)(%u?%l*)$")
    local res, stop
    report("lab: " .. verb)
    local ok, err = pcall(function()
      if verb == "fetch" then
        local want = {}
        for name, n in a[2]:gmatch("([^,=]+)=(%d+)") do want[#want + 1] = { name, tonumber(n) } end
        if a[3] == "dump" then
          -- hand everything else back to the factory while on the pad
          lab.keep = { ["minecraft:coal"] = true, ["minecraft:charcoal"] = true }
          for _, w in ipairs(want) do lab.keep[w[1]] = true end
          -- ... on a trip of its own, before asking: the factory hands the
          -- new parts over first, and a turtle with 16 full slots takes none
          local spare = false
          for s = 1, 16 do
            local d = turtle.getItemDetail(s)
            if d and not lab.keep[d.name] then spare = true end
          end
          if spare then
            lab.handin = true
            save()
            supplyRun(function() return {} end, "handing in what the lab does not need", true)
            lab.handin = nil
          end
          save()
        end
        -- (empty buckets asked for stay on board: the pad takes the others back)
        lab.want = {}
        for _, w in ipairs(want) do lab.want[w[1]] = true end
        supplyRun(function()
          local items = {}
          for _, w in ipairs(want) do
            local have = 0
            for s = 1, 16 do
              local d = turtle.getItemDetail(s)
              if d and d.name == w[1] then have = have + d.count end
            end
            if have < w[2] then items[#items + 1] = { w[1], w[2] - have } end
          end
          return items
        end, "lab parts", true)
        local got = {}
        for _, w in ipairs(want) do
          local have = 0
          for s = 1, 16 do
            local d = turtle.getItemDetail(s)
            if d and d.name == w[1] then have = have + d.count end
          end
          got[#got + 1] = w[1]:gsub("^.*:", "") .. "=" .. have
        end
        res = table.concat(got, " ")
        lab.keep, lab.want = nil, nil
      elseif verb == "goto" then
        local x, y, z = tonumber(a[2]), tonumber(a[3]), tonumber(a[4])
        local top = math.max(highway(), y + 2, pos.y)
        riseTo(top)
        local there = across(x, z, top + 12)
        while there and pos.y > y and step("d") do end
        res = ("at %d %d %d"):format(pos.x, pos.y, pos.z)
        stop = not (pos.x == x and pos.z == z)
      elseif verb == "ground" then
        while step("d") do end
        res = ("at %d %d %d"):format(pos.x, pos.y, pos.z)
      elseif verb == "up" or verb == "down" or verb == "fwd" then
        local n, done = tonumber(a[2]) or 1, 0
        for _ = 1, n do
          if step(verb == "up" and "u" or verb == "down" and "d" or "f") then done = done + 1 else break end
        end
        res = done .. " of " .. n
        stop = done < n
      elseif verb == "back" then
        local n, done = tonumber(a[2]) or 1, 0
        for _ = 1, n do
          if turtle.back() then
            pos.x, pos.z = pos.x - DIRS[heading].x, pos.z - DIRS[heading].z
            done = done + 1
          else break end
        end
        res = done .. " of " .. n
        stop = done < n
      elseif verb == "face" then
        face(tonumber(a[2]) % 4)
        res = "facing " .. heading
      elseif verb == "escape" then
        local got, moves = escape(tonumber(a[2]))
        res = (got and "out" or "no way out") .. (" after %d moves, at %d %d %d"):format(moves, pos.x, pos.y, pos.z)
        stop = not got
      elseif verb == "digdown" then
        local y = tonumber(a[2])
        while pos.y > y do
          local seen, data = turtle.inspectDown()
          if seen and data.name ~= "minecraft:water" and data.name ~= "minecraft:lava" then
            if not (isGround(data.name) or isClutter(data.name)) then res = "stopped above " .. data.name break end
            turtle.digDown()
          end
          if not step("d") then res = "could not go down" break end
        end
        res = (res or "down") .. (" at %d %d %d"):format(pos.x, pos.y, pos.z)
        stop = pos.y ~= y
      elseif verb == "turn" then
        face((heading + (a[2] == "left" and 3 or a[2] == "around" and 2 or 1)) % 4)
        res = "facing " .. heading
      elseif base == "place" and SFX[sfx] then
        local slot = findSlot(a[2])
        if not slot then res, stop = "none on board", true else
          turtle.select(slot)
          local done, why = turtle["place" .. sfx]()
          turtle.select(1)
          res = done and "placed" or ("no: " .. tostring(why))
          -- (an empty bucket on an empty cauldron is not a reason to stop
          -- a lava round: the next one may be full)
          stop = not done and a[2] ~= "minecraft:bucket"
          if not done then
            -- the same block already standing there is as good as placed
            -- (a wall two farm units share, say)
            local seen, data = turtle["inspect" .. sfx]()
            if seen and data.name == a[2] then res, stop = "already there", false end
          end
        end
      elseif base == "pick" and SFX[sfx] then
        -- pick[Up/Down]|name,name : dig the block that way only if it is one
        -- of these (a full-grown certus cluster: tools/certusfarm.py), else
        -- leave it and go on. A budding block is never dug, whatever is asked.
        local seen, data = turtle["inspect" .. sfx]()
        local name, want = seen and data.name or "nothing", false
        for w in (a[2] or ""):gmatch("[^,]+") do if name == w then want = true end end
        if want and not name:find("budding", 1, true) then
          local got = turtle["dig" .. sfx]()
          if got then lab.picked = (lab.picked or 0) + 1 end
          res = name .. (got and (" picked (" .. lab.picked .. " so far)") or " would not come out")
        else
          res = "left: " .. name
        end
      elseif base == "dig" and SFX[sfx] then
        local seen, data = turtle["inspect" .. sfx]()
        local name, allowed = seen and data.name or "nothing", false
        for _, p in ipairs(LAB_DIG) do if name:find(p, 1, true) then allowed = true end end
        if seen and isClutter(name) then allowed = true end      -- grass and flowers in the way
        if allowed then
          res = name .. (turtle["dig" .. sfx]() and " taken" or " would not come out")
        else
          res = "left alone: " .. name
        end
      elseif verb == "bootstrap" then
        -- bootstrap|item|n : set blank computers up on the launch pad's
        -- disk drive, ready to be carried to their posts (see bootstrap)
        local got, notes = bootstrap(a[2] ~= "" and a[2] or "computercraft:computer_normal", tonumber(a[3]) or 16)
        upFromPad()
        goHover()
        res = got .. " ready" .. (#notes > 0 and (": " .. table.concat(notes, ", ")) or "")
        stop = got == 0
      elseif verb == "site" then
        -- site|ox|oy|oz|shell|plan : work inside a building; walk and leave
        -- find their way through it by its plan (as the fit-out does)
        st.job = { fit = true, ox = tonumber(a[2]), oy = tonumber(a[3]), oz = tonumber(a[4]),
          shell = a[5] or "factory_asfit2", plan = a[6] or "factory_foundryfloor" }
        st.done = true                       -- (a place to work in, not a job to do)
        save()
        fitMap = loadFit(st.job)
        res = ("plan loaded, door at %d %d %d"):format(fitMap.start[1], fitMap.start[2], fitMap.start[3])
      elseif verb == "walk" then
        -- walk|x|y|z in the building's own coordinates
        if not fitMap then res, stop = "no site set", true else
          intoBuilding()
          local there = goTo(tonumber(a[2]), tonumber(a[3]), tonumber(a[4]))
          res = ("at %d %d %d (%d %d %d)"):format(lx(), ly(), lz(), pos.x, pos.y, pos.z)
          stop = not there
        end
      elseif verb == "leave" then
        if fitMap then outOfBuilding() end
        res = ("at %d %d %d"):format(pos.x, pos.y, pos.z)
      elseif verb == "equip" then
        -- equip|left/right|item : swap what is on that side for the item (a
        -- Chunk Controller in place of the pickaxe, say)
        local slot = findSlot(a[3])
        if peripheral.getType(a[2]) == "modem" then
          res, stop = "that side holds the modem: left alone", true
        elseif not slot then res = "none on board" else
          turtle.select(slot)
          local done, why = turtle[a[2] == "right" and "equipRight" or "equipLeft"]()
          turtle.select(1)
          if chunky then chunky.forget() end
          local kinds = table.concat({ peripheral.getType(a[2]) }, ", ")
          res = (done and "on" or ("no: " .. tostring(why))) .. " (" .. (kinds ~= "" and kinds or "no peripheral") .. ")"
        end
      elseif verb == "collect" then
        -- collect|x|y|z|n|face|how : a row of n lava cauldrons. Stand at
        -- x y z, facing `face`, then one step south (+z) for each next one;
        -- at each, an empty bucket on the cauldron (how: "place" = turtle.place,
        -- "use" = the Weak Automata Core). Never stops on an empty cauldron.
        local x, y, z, n = tonumber(a[2]), tonumber(a[3]), tonumber(a[4]), tonumber(a[5]) or 1
        local fc, how = tonumber(a[6]) or 2, a[7] or "place"
        local auto
        if how == "use" then
          for _, side in ipairs({ "left", "right" }) do
            if tostring(peripheral.getType(side) or ""):lower():find("automata", 1, true) then auto = peripheral.wrap(side) end
          end
        end
        -- come down one block behind the stand (its own column may be walled
        -- above), then step in
        local bx = x - ({ [0] = 1, 0, -1, 0 })[fc]
        local bz = z - ({ [0] = 0, 1, 0, -1 })[fc]
        local top = math.max(highway(), y + 2, pos.y)
        riseTo(top)
        local there = across(bx, bz, top + 12)
        while there and pos.y > y and step("d") do end
        if pos.x == bx and pos.z == bz and pos.y == y then face(fc) step("f") end
        if not (pos.x == x and pos.z == z and pos.y == y) then
          res, stop = ("could not get there: at %d %d %d"):format(pos.x, pos.y, pos.z), true
        else
          local got, tried = 0, 0
          for i = 1, n do
            face(fc)
            local slot = findSlot("minecraft:bucket")
            if not slot then break end
            tried = tried + 1
            turtle.select(slot)
            local done = false
            if how == "use" and auto then done = auto.useOnBlock() and true or false
            else done = turtle.place() end
            turtle.select(1)
            if done then got = got + 1 end          -- (that bucket holds lava now)
            if i < n then
              face(1)
              if not step("f") then break end
            end
          end
          res = ("%d of %d cauldrons gave lava (%s)"):format(got, tried, how)
        end
      elseif verb == "use" then
        -- use[|item] : right-click the block in front, as a player would, with
        -- the Weak Automata Core (Advanced Peripherals) worn on the pickaxe
        -- side: an empty hand, or the item named held (a wired modem joined
        -- to its network, a lever thrown, a bucket filled at a cauldron)
        local auto
        for _, side in ipairs({ "left", "right" }) do
          if tostring(peripheral.getType(side) or ""):lower():find("automata", 1, true) then auto = peripheral.wrap(side) end
        end
        if not auto then
          res, stop = "no automata worn (equip|right|advancedperipherals:weak_automata_core first)", true
        else
          local slot
          if a[2] and a[2] ~= "" then
            slot = findSlot(a[2])
            if not slot then res, stop = "none on board: " .. a[2], true end
          else
            for s2 = 16, 1, -1 do if turtle.getItemCount(s2) == 0 then slot = s2 break end end
          end
          if slot then
            turtle.select(slot)
            local done, why = auto.useOnBlock()
            turtle.select(1)
            res = done and "used" or ("no: " .. tostring(why))
            stop = not done
          elseif not res then res, stop = "no empty slot for an empty hand", true end
        end
      elseif verb == "until" then
        -- wait for a machine: until|side|method|n|seconds (a count, or a number)
        local want, limit = tonumber(a[4]) or 1, tonumber(a[5]) or 180
        local t0, got = os.clock(), nil
        repeat
          local okCall, v = pcall(peripheral.call, a[2], a[3])
          got = okCall and (type(v) == "table" and tonumber(v.count) or tonumber(v)) or nil
          if got and got >= want then break end
          sleep(3)
          tick("lab: waiting for the machine")
        until os.clock() - t0 > limit
        res = ("%s after %d s"):format(tostring(got), math.floor(os.clock() - t0))
        stop = not (got and got >= want)
      elseif verb == "handin" then
        -- everything on board (but what is named, and fuel) back to the factory
        lab.keep = { ["minecraft:coal"] = true, ["minecraft:charcoal"] = true }
        for name in (a[2] or ""):gmatch("[^,]+") do lab.keep[name] = true end
        lab.handin = true
        save()
        supplyRun(function() return {} end, "handing in what the lab made", true)
        lab.keep, lab.handin = nil, nil
        res = "handed in"
      elseif verb == "expect" then
        -- stop here unless the block that way is what the steps assume
        local s = a[2] == "up" and "Up" or a[2] == "down" and "Down" or ""
        local seen, data = turtle["inspect" .. s]()
        local name = seen and data.name or "nothing"
        res = name
        stop = not name:find(a[3] or "", 1, true)
        -- expect|dir|name|key|value : and that block state too (a wheel's
        -- facing, say: a machine set the wrong way round is not built on)
        if not stop and a[4] and a[4] ~= "" then
          local got = seen and type(data.state) == "table" and data.state[a[4]]
          res = name .. " " .. a[4] .. "=" .. tostring(got)
          stop = tostring(got) ~= (a[5] or "")
        end
      elseif base == "drop" and SFX[sfx] then
        local slot = findSlot(a[2])
        if not turtle["detect" .. sfx]() then
          res = "nothing there to put it in"        -- (it would fall on the ground)
          stop = true
        elseif not slot then res = "none on board" else
          -- (from every stack of it on board until n have gone: coal handed
          -- over in two lots sits in two slots)
          local left, went, done, why = tonumber(a[3]) or 1, 0, false, nil
          for sl = slot, 16 do
            local d = turtle.getItemDetail(sl)
            if left > 0 and d and d.name == a[2] then
              turtle.select(sl)
              local before = turtle.getItemCount(sl)
              done, why = turtle["drop" .. sfx](left)
              local n = before - turtle.getItemCount(sl)
              went, left = went + n, left - n
              if not done then break end
            end
          end
          res = (went > 0 and "went in: " or "refused: ") .. went .. " " .. tostring(why or "")
          turtle.select(1)
        end
      elseif base == "suck" and SFX[sfx] then
        local before = {}
        for s = 1, 16 do before[s] = turtle.getItemCount(s) end
        local done, why = turtle["suck" .. sfx](tonumber(a[2]) or 64)
        local got = {}
        for s = 1, 16 do
          local d = turtle.getItemDetail(s)
          if d and d.count > before[s] then got[#got + 1] = d.name .. " x" .. (d.count - before[s]) end
        end
        res = done and table.concat(got, ", ") or ("nothing: " .. tostring(why))
      elseif verb == "types" then
        res = table.concat({ peripheral.getType(a[2]) }, ", ")
        if res == "" then res = "no peripheral" end
      elseif verb == "methods" then
        local m = peripheral.getMethods(a[2])
        if m then table.sort(m) end
        res = m and table.concat(m, " ") or "no peripheral"
      elseif verb == "call" then
        local args = {}
        for i = 4, #a do args[#args + 1] = labValue(a[i]) end
        local r = table.pack(pcall(peripheral.call, a[2], a[3], table.unpack(args)))
        local parts = {}
        for i = 2, r.n do parts[#parts + 1] = labShow(r[i]) end
        res = (r[1] and "" or "ERROR ") .. table.concat(parts, " | ")
      elseif base == "toss" and SFX[sfx] then
        -- toss[Up/Down]|item|n : drop items into the open on purpose (into a
        -- stream that works on them: a fan's wash water). "drop" refuses to.
        local left, tossed = tonumber(a[3]) or 64, 0
        for sl = 1, 16 do                      -- (every slot that holds some)
          local d = turtle.getItemDetail(sl)
          if d and d.name == a[2] and left > 0 then
            turtle.select(sl)
            local before = turtle.getItemCount(sl)
            turtle["drop" .. sfx](left)
            local went = before - turtle.getItemCount(sl)
            tossed, left = tossed + went, left - went
          end
        end
        turtle.select(1)
        res = "tossed " .. tossed
        stop = tossed == 0
      elseif verb == "scan" then
        -- scan|text|radius : the Geo Scanner (worn on the tool side for the
        -- moment, the pickaxe put back after) lists the blocks named like
        -- text within radius, in world coordinates
        local want, r = a[2] or "", math.min(16, tonumber(a[3]) or 8)
        local slot = findSlot("advancedperipherals:geo_scanner")
        if not slot then res, stop = "no geo scanner on board", true else
          turtle.select(slot)
          turtle.equipRight()
          local geo = peripheral.wrap("right")
          local ok, blocks = pcall(function() return geo.scan(r) end)
          turtle.select(slot)
          turtle.equipRight()
          turtle.select(1)
          if not ok or type(blocks) ~= "table" then res = "scan failed: " .. tostring(blocks) else
            local hits = {}
            for _, b in ipairs(blocks) do
              if b.name:find(want, 1, true) then
                hits[#hits + 1] = ("%s@%d,%d,%d"):format(b.name:gsub("^.*:", ""), pos.x + b.x, pos.y + b.y, pos.z + b.z)
              end
            end
            res = #hits .. " found: " .. table.concat(hits, " "):sub(1, 400)
          end
        end
      elseif verb == "seek" then
        -- seek|text|max : straight down until the block below is named like
        -- text (water, to fill a bucket from); stops on anything else
        local want, limit, moved = a[2] or "water", tonumber(a[3]) or 40, 0
        while true do
          local seen, data = turtle.inspectDown()
          if seen then
            res = ("over %s at %d %d %d"):format(data.name, pos.x, pos.y, pos.z)
            stop = not data.name:find(want, 1, true)
            break
          end
          if moved >= limit or not step("d") then
            res, stop = ("no %s within %d below"):format(want, moved), true
            break
          end
          moved = moved + 1
        end
      elseif verb == "cycle" then
        -- cycle|item|text|n|seconds : n times over, place the item in front,
        -- wait until the block there is named like text (sand turned to soul
        -- sand by an Atomic Reconstructor), and take it. Stops at the first
        -- that has not changed in time (it is left standing).
        local item, want = a[2], a[3] or ""
        local n, limit, made = tonumber(a[4]) or 1, tonumber(a[5]) or 120, 0
        for _ = 1, n do
          local seen, data = turtle.inspect()
          if not (seen and (data.name == item or data.name:find(want, 1, true))) then
            local slot = findSlot(item)
            if seen or not slot then res = (seen and "in the way: " .. data.name or "none on board") stop = true break end
            turtle.select(slot)
            local placed = turtle.place()
            turtle.select(1)
            if not placed then res, stop = "would not go down", true break end
          end
          local t0, changed = os.clock(), false
          repeat
            seen, data = turtle.inspect()
            changed = seen and data.name:find(want, 1, true) ~= nil
            if changed then break end
            sleep(2)
            tick("lab: waiting for the block to change")
          until os.clock() - t0 > limit
          if not changed then res, stop = "no change after " .. limit .. " s", true break end
          if not turtle.dig() then res, stop = "would not come out", true break end
          made = made + 1
        end
        res = made .. " of " .. n .. (res and (": " .. res) or "")
      elseif verb == "inspect" then
        local s = a[2] == "up" and "Up" or a[2] == "down" and "Down" or ""
        local seen, data = turtle["inspect" .. s]()
        res = seen and (data.name .. " " .. labShow(data.state)) or "nothing"
      elseif verb == "inv" then
        local parts = {}
        for s = 1, 16 do
          local d = turtle.getItemDetail(s)
          if d then parts[#parts + 1] = d.name:gsub("^.*:", "") .. " x" .. d.count end
        end
        res = table.concat(parts, ", ")
      elseif verb == "fuel" then
        res = tostring(fuel())
      elseif verb == "wait" then
        sleep(tonumber(a[2]) or 1)
        res = "waited"
      elseif verb == "home" then
        riseTo(math.max(pos.y, highway()))
        goHover()
        res = "home"
      elseif verb == "note" then
        res = a[2] or ""
      else
        res = "unknown step"
      end
    end)
    if not ok then
      if err == "Terminated" then error(err, 0) end
      res, stop = "ERROR " .. tostring(err), true
    end
    local okTime, clock = pcall(os.date, "!%H:%M:%S")
    out(("%s %d %s: %s"):format(okTime and clock or "", lab.i, steps[lab.i]:sub(1, 60), tostring(res)))
    lab.i = lab.i + 1
    save()
    if stop then
      out("stopped here")
      break
    end
  end
  st.lab = nil
  save()
  print("Lab bench done.")
  report("idle")
end

-- feed: a turtle has run dry in mid-air. Fetch fuel without burning it,
-- fly to just above the turtle and drop the fuel into it.
local function runFeed()
  local t = st.feed
  print(("Taking fuel to the turtle at %d %d %d."):format(t.x, t.y, t.z))
  local function carried()                 -- a lava bucket, or a fair bit of coal
    local coal = 0
    for s = 1, 16 do
      local it = turtle.getItemDetail(s)
      if it and it.name == "minecraft:lava_bucket" then return true end
      if it and isCoal(it.name) then coal = coal + it.count end
    end
    return coal >= 12
  end
  if not carried() then supplyRun(function() return {} end, "fuel for a stranded turtle") end
  report("taking fuel out")
  local top = math.max(highway(), t.y + 4)
  riseTo(top)
  local given, why = 0, "could not fly there"
  if across(t.x, t.z, top + 12) then
    while pos.y > t.y + 1 and step("d") do end
    local ok, data = turtle.inspectDown()
    if pos.y ~= t.y + 1 then
      why = "stopped at height " .. pos.y
    elseif not (ok and data.name:find("computercraft:turtle", 1, true)) then
      why = "below me is " .. tostring(ok and data.name or "nothing")
    else
      why = "it would not take the fuel"
      for pass = 1, 2 do
        for s = 1, 16 do
          local it = turtle.getItemDetail(s)
          if it and isCoal(it.name) then
            turtle.select(s)
            if turtle.dropDown() then given = given + it.count end
          end
        end
        if given > 0 then break end
        -- its inventory is full: take one stack off it to make room
        for s = 1, 16 do
          if turtle.getItemCount(s) == 0 then
            turtle.select(s)
            turtle.suckDown()
            break
          end
        end
      end
      turtle.select(1)
    end
  end
  print(given > 0 and ("Fuel handed over (" .. given .. ").") or ("Fuel not handed over: " .. why .. "."))
  st.feed = nil
  save()
  riseTo(top)
end

-- The foundry: this helper works the Mekanism machines (foundry.lua) for as
-- long as it is told to, between its other jobs. It is handed the helper's
-- own ways of getting about and of fetching and handing in.
local function runFoundry()
  local function inside()
    local m = fitMap
    if not (m and st.job and st.job.fit) then return false end
    local x, y, z = lx(), ly(), lz()
    return x >= m.x1 and x <= m.x2 and z >= m.z1 and z <= m.z2 and y >= 1 and y <= m.y2 and open(x, y, z)
  end
  local function onBoard(name)
    local n = 0
    for s = 1, 16 do
      local d = turtle.getItemDetail(s)
      if d and d.name == name then n = n + d.count end
    end
    return n
  end
  local env = {
    PROTOCOL = JOB_PROTOCOL,
    face = face, tick = tick, report = report, inside = inside,
    -- the building: its plans, and the door to go in and out by
    site = function(site)
      st.job = { fit = true, ox = site.ox, oy = site.oy, oz = site.oz, shell = site.shell, plan = site.plan }
      st.done = true                       -- (a place to work in, not a job to do)
      st.fdy = nil
      save()
      fitMap = loadFit(st.job)
      return true
    end,
    walk = function(x, y, z)               -- in the building's own coordinates
      intoBuilding()
      return goTo(x, y, z)
    end,
    block = function(x, y, z) fitMap.solid[ck(x, y, z)] = true end,   -- a machine stands here
    unblock = function(x, y, z) fitMap.solid[ck(x, y, z)] = nil end,  -- (our own cable, taken up)
    leave = function() outOfBuilding() end,
    rise = function() riseTo(math.max(pos.y, highway())) end,
    flyTo = function(x, y, z)              -- over everything, then straight down
      local top = math.max(highway(), y + 2, pos.y)
      riseTo(top)
      local there = across(x, z, top + 12)
      while there and pos.y > y and step("d") do end
      return pos.x == x and pos.y == y and pos.z == z
    end,
    home = function()
      local hx, hy, hz = hover()
      if pos.x == hx and pos.y == hy and pos.z == hz then return true end
      if not LN.inside() then riseTo(math.max(pos.y, highway())) end
      return goHover()
    end,
    -- up to these amounts on board: { { item, count }, ... } (one trip)
    fetch = function(list)
      st.fdy = {}
      save()
      supplyRun(function()
        local items = {}
        for _, w in ipairs(list) do
          local have = onBoard(w[1])
          if have < w[2] then items[#items + 1] = { w[1], w[2] - have } end
        end
        return items
      end, "foundry supplies", true)
      st.fdy = nil
      save()
    end,
    -- everything on board (but fuel) back to the factory
    handin = function()
      st.fdy = { handin = true, keep = { ["minecraft:coal"] = true, ["minecraft:charcoal"] = true } }
      save()
      supplyRun(function() return {} end, "handing in what the foundry made", true)
      st.fdy = nil
      save()
    end,
  }
  foundry.print = print
  print("Working the foundry.")
  foundry.run(env)
  print("Foundry work over.")
end

local function work()
  locate()
  -- born on the launch pad (or restarted in the hole): straight up and out
  -- woken dry with fuel on board (set out by another turtle, fed by hand):
  -- drink before anything tries to move
  if fuel() < 200 then
    for sl = 1, 16 do
      local d = turtle.getItemDetail(sl)
      if d and (d.name == "minecraft:lava_bucket" or isCoal(d.name)) then
        turtle.select(sl)
        turtle.refuel(d.name == "minecraft:lava_bucket" and 1 or math.min(d.count, 16))
      end
    end
    turtle.select(1)
  end
  -- (on the drone lane, in a home or on a track: in its place, not lost)
  local laneOk = LN.inside() and (pos.x ~= base.pad.x or pos.z ~= base.pad.z)
  -- inside the factory: a fit-out in hand carries on from where we stand (it
  -- knows the building); anything else walks out by the door. Never the sky.
  local inside, shellMap = false, nil
  if not laneOk then inside, shellMap = inFactory() end
  local fitting = st.job and st.job.fit and not st.done and not st.paused
  if inside and not fitting and not st.lab then
    findHeading()
    if not leaveFactory(shellMap) then
      report("stuck in the factory")
      error("I am inside the factory and cannot find the way to the door.", 0)
    end
    locate()
    inside = false
  end
  if pos.y <= base.f.y + 6 and (pos.x ~= base.pad.x or pos.z ~= base.pad.z) and st.lab and not laneOk then
    -- stopped inside a building: a lab run (site, leave, home) walks out by
    -- the door, so run it before giving up
    findHeading()
    runLab()
    locate()
  end
  if inside and not fitting then                       -- (a lab run that ended still inside)
    inside, shellMap = inFactory()
    if inside then
      findHeading()
      if not leaveFactory(shellMap) then
        report("stuck in the factory")
        error("I am inside the factory and cannot find the way to the door.", 0)
      end
      locate()
      inside = false
    end
  end
  if pos.y <= base.f.y + 6 and (pos.x ~= base.pad.x or pos.z ~= base.pad.z) and not laneOk and not inside then
    -- a miner drafted as a builder's mate wakes in its own shaft: find the
    -- way out through open space, digging nothing
    findHeading()
    pcall(escape, 800)
    locate()
  end
  if pos.y <= base.f.y + 6 and not laneOk and not inside then
    if pos.x ~= base.pad.x or pos.z ~= base.pad.z then
      report("lost")
      error("I am down in the base and not on the launch pad.", 0)
    end
    if LN.on() then findHeading() end                 -- (off the pad sideways, not up)
    upFromPad()
  end
  if not findHeading() then
    riseTo(pos.y + 3)
    if not findHeading() then error("I am boxed in.", 0) end
  end
  if st.feed then runFeed() end
  if st.lab then runLab() end
  if st.job and not st.done and not st.paused then
    if st.job.area then runForage() elseif st.job.trees then runChop()
    elseif st.job.fit then
      report("fitting out")
      runFit()
      lastState = "idle"
    else
      report("building")
      runBuild()
      lastState = "idle"
    end
  end
  if st.done and st.next and not st.paused then
    print("On to the next job.")
    st = { job = st.next, turn = st.turn, orderSeq = st.orderSeq }
    save()
    return work()
  end
  -- no building job in hand: the foundry, if this helper has been put on it
  if foundry and not st.paused and (not st.job or st.done) then
    local okLoad, fst = pcall(foundry.load)
    if okLoad and fst.on then
      riseTo(math.max(pos.y, base.f.y + 12))
      runFoundry()
    end
  end
  if not LN.on() then riseTo(math.max(pos.y, base.f.y + 12)) end
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

-- Without its modem a turtle hears no orders and reports nothing. If one has
-- been swapped off (a lab step once put a Chunk Controller in its place), put
-- it back on before anything else: onto the side that is not the pickaxe.
do
  local function hasModem()
    return peripheral.getType("left") == "modem" or peripheral.getType("right") == "modem"
  end
  if not hasModem() then
    for s = 1, 16 do
      local d = turtle.getItemDetail(s)
      if d and d.name:find("modem", 1, true) then
        turtle.select(s)
        local side = peripheral.getType("right") and "Right" or "Left"   -- a side holding some other gadget first
        turtle["equip" .. side]()
        local back = turtle.getItemDetail(s)
        if back and back.name:find("pickaxe", 1, true) then
          -- that was the pickaxe: put it back, and use the other side
          turtle["equip" .. side]()
          turtle["equip" .. (side == "Left" and "Right" or "Left")]()
        end
        turtle.select(1)
        break
      end
    end
  end
end

if swarm and swarm.hello then pcall(swarm.hello, "helper") end   -- awake, and here (the modem is on by now)

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
  elseif cmd.cmd == "lab" and type(cmd.ops) == "string" then
    st.lab = { ops = cmd.ops }
    if cmd.clear then st.labOut = nil end
    save()
    task = guarded(work)
  elseif cmd.cmd == "foundry" and foundry then
    -- foundry ore=minecraft:raw_iron n=48 | make=steel n=16 | job=setup |
    -- job=move_infuser | on=0 (see foundry.lua)
    foundry.order(cmd)
    task = guarded(work)
  elseif cmd.cmd == "feed" and tonumber(cmd.x) and tonumber(cmd.y) and tonumber(cmd.z) then
    st.feed = { x = math.floor(tonumber(cmd.x)), y = math.floor(tonumber(cmd.y)), z = math.floor(tonumber(cmd.z)) }
    save()
    task = guarded(work)
  elseif cmd.cmd == "fit" and tonumber(cmd.ox) and tonumber(cmd.oy) and tonumber(cmd.oz) then
    -- fit out a building: plan (the jobs) and shell (what is already built)
    local plan = type(cmd.plan) == "string" and cmd.plan:match("^[%w_%-]+$") or "factory_fitout"
    local shell = type(cmd.shell) == "string" and cmd.shell:match("^[%w_%-]+$") or "factory_shell"
    for _, f in ipairs({ plan .. ".plan", shell .. ".plan" }) do
      if fs.exists(f) then fs.delete(f) end
    end
    local job = { fit = true, plan = plan, shell = shell, ox = math.floor(tonumber(cmd.ox)),
      oy = math.floor(tonumber(cmd.oy)), oz = math.floor(tonumber(cmd.oz)),
      xmin = tonumber(cmd.xmin), xmax = tonumber(cmd.xmax) }
    if cmd.after and st.job and not st.done then
      st.next = job                     -- when the job in hand is finished
    else
      st = { job = job, turn = st.turn, orderSeq = st.orderSeq }
    end
    save()
    task = guarded(work)
  elseif cmd.cmd == "strip" and st.job and (tonumber(cmd.xmin) or tonumber(cmd.xmax)) then
    -- share the job in hand: keep to x from xmin to xmax from here on
    st.job.xmin, st.job.xmax = tonumber(cmd.xmin), tonumber(cmd.xmax)
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
