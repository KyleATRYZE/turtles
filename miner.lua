-- miner.lua : GPS quarry miner for CC:Tweaked turtles
-- Usage:  miner <size> [bottomY]
--   Place the turtle facing the area to mine, with a chest directly behind it.
--   It mines a <size> x <size> square in front of it and to its right,
--   from just below its own level down to bottomY (default -58).
--   It returns to the chest to unload, refuels from mined coal,
--   and resumes by itself after a server restart or chunk reload.

local STATE_FILE  = "miner.state"
local MIN_Y       = -58     -- lowest layer centre (digs one block below this)
local FUEL_LOW    = 1500    -- start burning mined coal below this
local FUEL_TARGET = 3000    -- burn coal until fuel reaches this; the rest of
                            -- the coal is carried back to the base
local JOB_PROTOCOL = "swarm_job"   -- talking to the factory about plots

-- Kept (one stack only) even though it is junk: the factory smelts it into
-- stone for new turtles, and miners use it to floor gaps in the roads.
local KEEP_ONE_STACK = "minecraft:cobblestone"

-- Lava is fuel: a miner carrying a bucket scoops up any lava it meets
-- (one bucket = 1000 fuel) until its tank reaches LAVA_TARGET.
local BUCKET      = "minecraft:bucket"
local LAVA_BUCKET = "minecraft:lava_bucket"
local LAVA_TARGET = 4000
local LAVA_SPARE  = 4      -- full buckets a miner brings home for the others, when its own tank is full

-- Coal hunting: a miner holding a Geo Scanner (Advanced Peripherals) stops
-- digging its plot and goes looking for coal ore instead.
local SCANNER     = "advancedperipherals:geo_scanner"
local PICKAXE     = "minecraft:diamond_pickaxe"
local HUNT_RADIUS = 8      -- scan range in blocks (the free range)
local HUNT_STEP   = 14     -- distance between scan points
local HUNT_REACH  = 40     -- how far from the factory to roam (further out the
                           -- chunks may not be loaded, and a turtle there freezes)
local HUNT_NEAR   = 28     -- but no closer than this
local HUNT_LOAD   = 128    -- coal to gather before taking it home
local HUNT_NORTH  = 20     -- no hunting further north than this: a friend's base is inside
                           -- the mountain there (until we know exactly where it is)
local LAVA_RUN    = 8      -- buckets of lava the hunter brings home per trip
local DEEP_REACH  = 23     -- under the base (inside the ring of plots) coal is taken at any depth
local HUNT_MAX    = 128     -- the hunting area grows each round, up to this (Ghastly escorts)
local RESCUE_PROTOCOL = "swarm_rescue"
local RESCUE_COAL = 16     -- coal handed to a stranded miner

-- Names for miners, picked by computer number. (Each stands where the name
-- it replaced stood, so a miner gets the same name whether it took the old
-- one before the renaming or starts fresh: see swarm.lua.)
local NAMES = {
  "Ironic", "InVein", "Coalition", "MotherLode", "Oresome",
  "NetherMind", "DigIt", "Dioright", "Cobbler", "CleanSlate",
  "Andesight", "TuffLuck", "Calcited", "Gravelly",
  "Bedrocker", "Granted", "Flinty", "CopperTop",
  "GoldRush", "Basalty", "RockSolid", "Quartzy", "Smelty",
  "LapisLazy", "Dripstoned", "GeodeToGo", "Nuggety", "Pickle",
}

-- Thrown away when the inventory fills up
local JUNK = {
  ["minecraft:cobblestone"] = true,
  ["minecraft:cobbled_deepslate"] = true,
  ["minecraft:dirt"] = true,
  ["minecraft:gravel"] = true,
  ["minecraft:tuff"] = true,
  ["minecraft:andesite"] = true,
  ["minecraft:diorite"] = true,
  ["minecraft:granite"] = true,
  ["minecraft:calcite"] = true,
  ["minecraft:netherrack"] = true,
  ["minecraft:smooth_basalt"] = true,
  ["minecraft:dripstone_block"] = true,
  ["minecraft:pointed_dripstone"] = true,
  ["minecraft:deepslate"] = true,
  ["minecraft:stone"] = true,
  -- other mods' stone, not needed and filling the chests
  ["forbidden_arcanus:darkstone"] = true,
  ["xycraft_world:kivi"] = true,
  ["astralsorcery:marble_raw"] = true,
  ["regions_unexplored:volcanic_ash"] = true,
}

-- Burned for fuel while mining
local FUEL_ITEMS = {
  ["minecraft:coal"] = true,
  ["minecraft:charcoal"] = true,
  ["minecraft:coal_block"] = true,
}

-- Never dug, so the turtle cannot wreck your base or other turtles
local PROTECT = {
  "computercraft:", "chest", "barrel", "shulker", "hopper",
  "furnace", "drawer", "sophisticatedstorage:",
}

-- heading: 0 = east (+x), 1 = south (+z), 2 = west (-x), 3 = north (-z)
local DIRS = {
  [0] = { x = 1, z = 0 }, [1] = { x = 0, z = 1 },
  [2] = { x = -1, z = 0 }, [3] = { x = 0, z = -1 },
}

local pos = { x = 0, y = 0, z = 0 }
local heading = 0
local st -- saved job state
local totalLayers = 0

-- Status reporting to the controller (optional: works without swarm.lua)
local okSwarm, swarm = pcall(require, "swarm")
if not okSwarm then swarm = nil end
if swarm and swarm.hello and turtle then pcall(swarm.hello, "miner") end   -- awake, and here
-- A Chunk Controller of its own (see swarm.lua) keeps a miner's chunk
-- loaded wherever it is: worn in place of the pickaxe while it flies or
-- waits; while it digs the pickaxe stays on and the controller goes on for
-- a moment in every new chunk and every few minutes. Every dig puts the
-- pickaxe back on first. Without one on board none of this does anything.
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
local lastState = "idle"
local reported = false
local function report(state)
  lastReport = os.clock()
  lastState = state
  reported = true
  if chunky then chunky.keep(pos.x, pos.z) end   -- (covers long waits in one place)
  if not swarm then return end
  local inv, free = {}, 0
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d then inv[d.name] = (inv[d.name] or 0) + d.count else free = free + 1 end
  end
  local f = turtle.getFuelLevel()
  pcall(swarm.report, {
    role = "miner",
    state = state,
    pos = { x = pos.x, y = pos.y, z = pos.z },
    fuel = f == "unlimited" and -1 or f,
    freeSlots = free,
    inv = inv,
    bucket = (inv[BUCKET] or inv[LAVA_BUCKET]) and true or false,
    job = st and {
      home = st.home, size = st.size, bottom = st.bottom,
      layer = st.layer, layers = totalLayers, rowsDone = st.rowsDone,
      plot = st.index,
    } or nil,
    log = logLines,
    chunky = chunky and chunky.have() and (chunky.isWorn() and "on" or "carried") or nil,
  })
end

-- Called after every move: a turtle with a Chunk Controller of its own
-- keeps its chunk loaded, and everyone says where they are now and then on
-- a long flight (a turtle that freezes in an unloaded chunk is then last
-- seen close to where it stopped).
local function keepAwake()
  if chunky then chunky.keep(pos.x, pos.z) end
  if reported and os.clock() - lastReport > 30 then report(lastState) end
end

---------------------------------------------------------------- basics

local function fuel()
  local f = turtle.getFuelLevel()
  if f == "unlimited" then return math.huge end
  return f
end

local function save()
  local h = fs.open(STATE_FILE .. ".tmp", "w")
  h.write(textutils.serialize(st))
  h.close()
  fs.delete(STATE_FILE)
  fs.move(STATE_FILE .. ".tmp", STATE_FILE)
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

local function isProtected(inspectFn)
  local ok, data = inspectFn()
  if not ok then return false end
  for _, p in ipairs(PROTECT) do
    if data.name:find(p, 1, true) then return true end
  end
  return false
end

local function safeDig()
  if isProtected(turtle.inspect) then return false end
  return turtle.dig()
end

local function safeDigUp()
  if isProtected(turtle.inspectUp) then return false end
  return turtle.digUp()
end

local function safeDigDown()
  if isProtected(turtle.inspectDown) then return false end
  return turtle.digDown()
end

---------------------------------------------------------------- fuel

-- Burn anything burnable until fuel >= min. Waits for the player if needed.
local function refuelAny(min)
  while fuel() < min do
    for s = 1, 16 do
      if turtle.getItemCount(s) > 0 then
        turtle.select(s)
        while fuel() < min and turtle.refuel(1) do end
      end
    end
    turtle.select(1)
    if fuel() < min then
      print(("Need fuel (%d/%d). Put coal in my inventory."):format(fuel(), min))
      report("needs fuel")
      if swarm and swarm.open() then
        -- on the launch pad the factory can hand some over
        rednet.broadcast({ type = "fuel_request", id = os.getComputerID() }, JOB_PROTOCOL)
        -- anywhere else, the coal hunter can come and bring some
        rednet.broadcast({ type = "rescue", id = os.getComputerID(),
          pos = { x = pos.x, y = pos.y, z = pos.z } }, RESCUE_PROTOCOL)
      end
      sleep(5)
    end
  end
end

-- Burn mined coal only, up to target.
local function refuelFromInventory(target)
  if fuel() >= target then return end
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and FUEL_ITEMS[d.name] then
      turtle.select(s)
      while fuel() < target and turtle.refuel(1) do end
    end
  end
  for s = 1, 16 do
    if fuel() >= target then break end
    local d = turtle.getItemDetail(s)
    if d and d.name == LAVA_BUCKET then
      turtle.select(s)
      turtle.refuel(1)
    end
  end
  turtle.select(1)
end

---------------------------------------------------------------- movement

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
  if diff == 1 then
    turnRight()
  elseif diff == 2 then
    turnRight()
    turnRight()
  elseif diff == 3 then
    turnLeft()
  end
end

-- patient = true: keep trying forever. false: give up if truly blocked.
-- Hand our coal to the turtle in the way (it may be out of fuel: a queue
-- passes coal down to whoever is stuck at the front).
local function passCoal(dropFn)
  local gave = 0
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and FUEL_ITEMS[d.name] then
      turtle.select(s)
      local before = turtle.getItemCount(s)
      dropFn()
      gave = gave + before - turtle.getItemCount(s)
    end
  end
  turtle.select(1)
  return gave
end

local function tryMove(moveFn, detectFn, digFn, attackFn, patient, inspectFn, dropFn)
  local stuck = 0
  local passed = false
  while not moveFn() do
    if fuel() == 0 then
      print("Out of fuel!")
      refuelAny(1)
    elseif detectFn() then
      if digFn() then
        stuck = 0
      else
        stuck = stuck + 1
        sleep(0.5)
      end
    elseif attackFn() then
      -- hit a mob that was in the way
    else
      stuck = stuck + 1
      sleep(0.5)
    end
    if stuck > 8 then
      if not patient then return false end
      if stuck % 15 == 9 then
        local what = "something"
        if inspectFn then
          local ok, data = inspectFn()
          if ok and type(data) == "table" and data.name then what = data.name end
        end
        print("Blocked by " .. what .. ". Waiting...")
        report("path blocked")
        -- keep checking: coal passed down from behind arrives later
        if not passed and dropFn and stuck >= 24 and what:find("turtle", 1, true) then
          local n = passCoal(dropFn)
          if n > 0 then
            passed = true
            print("Passed " .. n .. " coal to the turtle in the way.")
          end
        end
      end
      sleep(2)
    end
  end
  return true
end

local function forward(patient)
  if tryMove(turtle.forward, turtle.detect, safeDig, turtle.attack, patient, turtle.inspect,
    turtle.drop) then
    pos.x = pos.x + DIRS[heading].x
    pos.z = pos.z + DIRS[heading].z
    keepAwake()
    return true
  end
  return false
end

local function up(patient)
  if tryMove(turtle.up, turtle.detectUp, safeDigUp, turtle.attackUp, patient, turtle.inspectUp,
    turtle.dropUp) then
    pos.y = pos.y + 1
    keepAwake()
    return true
  end
  return false
end

local function down(patient)
  if tryMove(turtle.down, turtle.detectDown, safeDigDown, turtle.attackDown, patient, turtle.inspectDown,
    turtle.dropDown) then
    pos.y = pos.y - 1
    keepAwake()
    return true
  end
  return false
end

local function axisMove(axis, target, patient, onStep)
  while pos[axis] ~= target do
    local ok
    if axis == "y" then
      if target > pos.y then ok = up(patient) else ok = down(patient) end
    else
      local d
      if axis == "x" then
        d = target > pos.x and 0 or 2
      else
        d = target > pos.z and 1 or 3
      end
      face(d)
      ok = forward(patient)
    end
    if not ok then return false end
    if onStep then onStep() end
  end
  return true
end

-- Work out which way we face by moving one block and comparing GPS fixes.
-- Leaves the turtle where it started, facing the way it started.
local function detectHeading()
  local x, _, z = locate()
  for pass = 1, 2 do
    for turns = 0, 3 do
      local moved = turtle.forward()
      if not moved and pass == 2 then
        safeDig()
        moved = turtle.forward()
      end
      if moved then
        local x2, _, z2 = locate()
        for _ = 1, 10 do
          if turtle.back() then break end
          sleep(0.5)
        end
        local d
        if x2 > x then d = 0
        elseif x2 < x then d = 2
        elseif z2 > z then d = 1
        else d = 3 end
        for _ = 1, turns do turtle.turnLeft() end
        return (d - turns) % 4
      end
      turtle.turnRight()
    end
  end
  error("Cannot move in any direction to find my heading.", 0)
end

---------------------------------------------------------------- local frame
-- lf = blocks forward of home, lr = blocks to the right of home

local function fwdVec() return DIRS[st.homeD] end
local function rightVec() return DIRS[(st.homeD + 1) % 4] end

local function toLocal()
  local dx, dz = pos.x - st.home.x, pos.z - st.home.z
  local f, r = fwdVec(), rightVec()
  return dx * f.x + dz * f.z, dx * r.x + dz * r.z
end

local function toWorld(lf, lr)
  local f, r = fwdVec(), rightVec()
  return st.home.x + lf * f.x + lr * r.x, st.home.z + lf * f.z + lr * r.z
end

local function fAxis() return fwdVec().x ~= 0 and "x" or "z" end
local function rAxis() return fwdVec().x ~= 0 and "z" or "x" end

-- order is a string of "f", "r", "y" giving which axis to move along first
local function goLocal(lf, lr, y, order, patient, onStep)
  local wx, wz = toWorld(lf, lr)
  local t = { x = wx, y = y, z = wz }
  for c in order:gmatch(".") do
    local axis
    if c == "y" then axis = "y"
    elseif c == "f" then axis = fAxis()
    else axis = rAxis() end
    if not axisMove(axis, t[axis], patient, onStep) then return false end
  end
  return true
end

local function atHome()
  local lf, lr = toLocal()
  return lf == 0 and lr == 0 and pos.y == st.home.y
end

-- The "shaft head" is the cell in front of home at home height: the top of
-- the vertical shaft this turtle uses to get in and out of its plot.

-- Normal route: across to the shaft, then straight up it.
local function tryShaftRoute()
  return goLocal(1, 0, pos.y, "rf", false)
    and axisMove("y", st.home.y, false)
end

-- Backup route: straight up first, then across the top layer.
local function tryTopRoute()
  local top = st.home.y - 1
  local lf, lr = toLocal()
  if lf == 1 and lr == 0 and st.size > 1 then
    -- the shaft itself is blocked: step into a neighbouring column first
    if not goLocal(2, 0, pos.y, "f", false) then
      goLocal(1, 1, pos.y, "r", false)
    end
  end
  return axisMove("y", top, false)
    and goLocal(1, 0, top, "rf", false)
    and axisMove("y", st.home.y, false)
end

local function toShaftHead()
  while true do
    if tryShaftRoute() or tryTopRoute() then return end
    print("Path out is blocked, retrying...")
    report("path blocked")
    sleep(5)
  end
end

local function goHome()
  if atHome() then return end
  toShaftHead()
  goLocal(0, 0, st.home.y, "f", true)
end

local function travelTo(lf, lr, y)
  while true do
    local ok = true
    if toLocal() <= 0 then ok = goLocal(1, 0, pos.y, "f", false) end
    -- normal route: down the shaft, then across
    if ok and axisMove("y", y, false) and goLocal(lf, lr, y, "rf", false) then
      return
    end
    -- backup route: across the top layer, then straight down
    local top = st.home.y - 1
    if toLocal() >= 1 and axisMove("y", top, false)
      and goLocal(lf, lr, top, "rf", false) and axisMove("y", y, false) then
      return
    end
    print("Path to work is blocked, retrying...")
    report("path blocked")
    sleep(5)
  end
end

---------------------------------------------------------------- swarm travel
-- Swarm miners have no chest of their own. They travel between their plots
-- and the base UNDERGROUND, on two one-way "roads" just above the plots, so
-- nothing on the surface is touched and turtles never meet head-on:
--
--   out road (2 above the plot tops): base -> plots
--   in road  (6 above the plot tops): plots -> base
--
-- Roads are dug two blocks high, and gaps in the floor are filled with
-- cobblestone, so people can walk along them too.
--
-- At the base a miner comes UP the in-shaft (one step beyond the drop-off
-- chest), unloads, and goes DOWN the out-shaft (one step beyond the launch
-- pad).

local function outY() return st.home.y + 2 end
local function inY() return st.home.y + 6 end

local function inShaft()
  return { x = 2 * st.dock.x - st.exit1.x, z = 2 * st.dock.z - st.exit1.z }
end

local function outShaft()
  return { x = 2 * st.exit2.x - st.exit1.x, z = 2 * st.exit2.z - st.exit1.z }
end

local function shaftXZ() return toWorld(1, 0) end

local function at(p) return pos.x == p.x and pos.y == p.y and pos.z == p.z end
local function over(p) return pos.x == p.x and pos.z == p.z end

-- Travel level to a column: along x first, then z.
local function flyTo(x, z, onStep)
  axisMove("x", x, true, onStep)
  axisMove("z", z, true, onStep)
end

-- Columns that must stay open: every plot's shaft (plots sit on a grid
-- measured from the factory) and the two shafts at the base.
local function overAShaft()
  local a, b = inShaft(), outShaft()
  if (pos.x == a.x and pos.z == a.z) or (pos.x == b.x and pos.z == b.z) then
    return true
  end
  -- (the plot grid: laid out from the factory's first spot, st.origin, which
  -- stays put when the factory moves; before that, exit1 was the same spot)
  local o = st.origin or st.exit1
  return (pos.x - o.x) % st.size == 0 and (pos.z - o.z) % st.size == 0
end

-- Called on every step along a road: keep it walkable for people.
local function roadStep()
  if turtle.detectUp() then safeDigUp() end           -- headroom
  if not turtle.detectDown() and not overAShaft() then  -- a gap: lay a floor
    for s = 1, 16 do
      local d = turtle.getItemDetail(s)
      if d and d.name == KEEP_ONE_STACK then
        turtle.select(s)
        turtle.placeDown()
        turtle.select(1)
        break
      end
    end
  end
end

-- Moves from here to the drop-off chest.
local function dockDistance(y)
  local lf, lr = toLocal()
  local sx, sz = shaftXZ()
  local lane, shaft = inY(), inShaft()
  return math.abs(lf - 1) + math.abs(lr) + math.abs(lane - y)
    + math.abs(sx - shaft.x) + math.abs(sz - shaft.z)
    + (st.dock.y - lane) + 1
end

local function distHome()
  if st.swarm then return dockDistance(pos.y) end
  return math.abs(pos.x - st.home.x) + math.abs(pos.y - st.home.y)
    + math.abs(pos.z - st.home.z)
end

local function tripFuel(y)
  if st.swarm then return 2 * (dockDistance(y) + st.size * 2) + 300 end
  return 2 * (math.abs(st.home.y - y) + st.size * 2) + 300
end

-- Drop the haul into the drop-off chest below. The bucket and one stack of
-- cobblestone (for flooring the roads) stay on board.
local COAL_BUFFER = 32       -- coal kept on board as a spare tank
local collectEmpties     -- defined further down (empty buckets from the factory, for lava)

local function unloadDock()
  local keptCobble, keptCoal, empties = false, false, 0
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    local keep = false
    if d then
      if d.name == LAVA_BUCKET then
        keep = false                    -- lava brought home is for everyone
      elseif d.name == BUCKET then
        -- empties for the next lava: a few are plenty
        local room = LAVA_SPARE + 1 - empties
        if room > 0 then
          turtle.select(s)
          if turtle.getItemCount(s) > room then turtle.dropDown(turtle.getItemCount(s) - room) end
          empties = empties + turtle.getItemCount(s)
          keep = true
        end
      elseif d.name == SCANNER or d.name == PICKAXE or d.name == CHUNKY then
        keep = true
      elseif d.name == KEEP_ONE_STACK and not keptCobble then
        keptCobble = true
        keep = true
      elseif FUEL_ITEMS[d.name] and not keptCoal then
        -- keep one slot of coal (up to COAL_BUFFER), drop the rest
        keptCoal = true
        turtle.select(s)
        while turtle.getItemCount(s) > COAL_BUFFER do
          if not turtle.dropDown(turtle.getItemCount(s) - COAL_BUFFER) then
            print("The drop-off chest is full. Waiting...")
            report("drop-off full")
            sleep(5)
          end
        end
        keep = true
      end
    end
    while not keep and turtle.getItemCount(s) > 0 do
      turtle.select(s)
      if not turtle.dropDown() then
        print("The drop-off chest is full. Waiting...")
        report("drop-off full")
        sleep(5)
      end
    end
  end
  turtle.select(1)
end

local function hasBucket()
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and (d.name == BUCKET or d.name == LAVA_BUCKET) then return s end
  end
  return nil
end

-- By remote order ("openhole"): the next miner standing above the launch
-- pad breaks the block over it, opening the builder's way in and out.
local HOLE_FILE = ".openhole"
local OPENABLE = { ["minecraft:stone"] = true, ["minecraft:cobblestone"] = true,
  ["minecraft:dirt"] = true, ["minecraft:cobbled_deepslate"] = true }
local function openHole()
  if not fs.exists(HOLE_FILE) or not at(st.exit2) then return end
  local ok, data = turtle.inspectUp()
  if ok and OPENABLE[data.name] then
    turtle.digUp()
    print("Opened the hole above the launch pad.")
  end
  if not turtle.detectUp() then fs.delete(HOLE_FILE) end
end

-- Off the drop-off column, across to the exit column.
local function toExitColumn()
  if at(st.dock) then flyTo(st.exit1.x, st.exit1.z) end
  if at(st.exit1) then flyTo(st.exit2.x, st.exit2.z) end
  openHole()
end

-- Leave the base: across to the out-shaft and down it to the out road.
local function leaveDock()
  toExitColumn()
  local out = outShaft()
  if over(st.exit2) then
    -- from above the pad, or from the pad itself: straight across into the
    -- out-shaft (never up through the space above the pad, which may be
    -- taken by a miner on its way out)
    flyTo(out.x, out.z)
  end
  axisMove("y", outY(), true)
end

-- Service stop: wait directly above the factory turtle (it hands things up
-- to us) until we have enough fuel and a bucket. Never blocks the base for
-- long: after about 90 seconds, carry on if there is fuel for the round
-- trip; if not, move onto the launch pad (off the main path) and wait there.
local function serviceStop(needed)
  local function wantBucket()
    return not hasBucket() and (st.bucketTries or 0) < 3
  end
  if fuel() >= needed and not wantBucket() then return end
  if at(st.dock) then flyTo(st.exit1.x, st.exit1.z) end
  local onPad = over(st.exit2) and pos.y == st.exit2.y - 1
  if not (at(st.exit1) or onPad) then return end
  local tries = 0
  while fuel() < needed or wantBucket() do
    if fuel() < needed then
      print("Asking the factory for fuel.")
      report("needs fuel")
      rednet.broadcast({ type = "fuel_request", id = os.getComputerID() }, JOB_PROTOCOL)
    end
    if wantBucket() then
      print("Asking the factory for a bucket.")
      rednet.broadcast({ type = "bucket_request", id = os.getComputerID() }, JOB_PROTOCOL)
    end
    sleep(10)
    tries = tries + 1
    for s = 1, 16 do
      local d = turtle.getItemDetail(s)
      if d and d.name == SCANNER and not st.hunt and not st.huntFinished then
        -- the factory has no coal and handed over its Geo Scanner instead:
        -- go and find some
        st.hunt = true
        st.phase, st.back = nil, nil
        save()
        error("SWITCH_TO_HUNT", 0)
      end
      if d and fuel() < needed then
        turtle.select(s)
        while fuel() < needed and turtle.refuel(1) do end
      end
    end
    turtle.select(1)
    if tries == 4 and wantBucket() then
      st.bucketTries = (st.bucketTries or 0) + 1
      save()
    end
    if tries >= 9 and not onPad then
      local trip = st.back and (2 * dockDistance(st.back.y) + 60) or 200
      if fuel() >= trip then
        print("Nothing on offer. Carrying on with what I have.")
        return
      end
      -- not enough to go anywhere: wait on the launch pad, out of the way
      if fuel() >= 3 then
        flyTo(st.exit2.x, st.exit2.z)
        local ok, data = turtle.inspectDown()
        if not (ok and type(data) == "table" and tostring(data.name):find("turtle", 1, true)) then
          axisMove("y", st.exit2.y - 1, true)
          onPad = true
          print("Waiting for fuel on the launch pad.")
        end
      end
    end
  end
end

local function inPlot()
  local lf, lr = toLocal()
  return lf >= 1 and lf <= st.size and lr >= 0 and lr < st.size
    and pos.y <= st.home.y
end


-- On the way out of the base: beside the factory, on the launch pad, or
-- in the out-shaft.
local function onExitSide()
  local out = outShaft()
  return at(st.exit1) or (over(st.exit2) and pos.y >= st.exit2.y - 1)
    or (pos.x == out.x and pos.z == out.z and pos.y <= st.dock.y and pos.y >= outY())
end

-- In the shaft that comes up to the drop-off chest.
local function onWayIn()
  local shaft = inShaft()
  return pos.x == shaft.x and pos.z == shaft.z
    and pos.y <= st.dock.y and pos.y >= inY()
end

local function overOwnShaft()
  local sx, sz = shaftXZ()
  return pos.x == sx and pos.z == sz
end

-- Up the in-shaft and onto the drop-off chest.
local function upToDock()
  axisMove("y", st.dock.y, true)
  flyTo(st.dock.x, st.dock.z)
end

-- After a restart a swarm miner may be anywhere on its route. These two get
-- it from wherever it is to the drop-off chest, or to the top of its plot
-- shaft, always going the right way along the one-way roads and shafts.

local function toDockFromAnywhere()
  if at(st.dock) then return end
  if inPlot() then toShaftHead() end
  if onWayIn() then
    upToDock()
    return
  end
  if onExitSide() then leaveDock() end   -- must go round: out, then back in
  local sx, sz = shaftXZ()
  if pos.y == outY() and not overOwnShaft() then
    flyTo(sx, sz, roadStep)              -- on the out road: carry on to the plot
  end
  axisMove("y", inY(), true)             -- up onto the in road
  local shaft = inShaft()
  flyTo(shaft.x, shaft.z, roadStep)
  upToDock()
end

local function toShaftFromAnywhere()
  if inPlot() then return end
  if not overOwnShaft() then
    if onWayIn() or pos.y == inY() then
      -- heading in: finish coming in, then leave properly
      local shaft = inShaft()
      if not onWayIn() then flyTo(shaft.x, shaft.z, roadStep) end
      upToDock()
      leaveDock()
    elseif at(st.dock) or onExitSide() then
      leaveDock()
    else
      axisMove("y", outY(), true)
    end
    local sx, sz = shaftXZ()
    flyTo(sx, sz, roadStep)
  end
  axisMove("y", st.home.y, true)
end

---------------------------------------------------------------- inventory

local function emptySlots()
  local n = 0
  for s = 1, 16 do
    if turtle.getItemCount(s) == 0 then n = n + 1 end
  end
  return n
end

-- Building stone carried home for the factory building: this many stacks
-- of each are kept back from the rubble (one cobblestone stack always stays
-- on board for flooring the roads).
-- stacks of building stone to bring home each trip. The factory has all the
-- cobble and cobbled deepslate the building needs and its chests are
-- nearly full, so for now nothing extra comes home.
local HAUL = {}

local function dropJunk()
  local kept = {}
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and JUNK[d.name] then
      local keep = HAUL[d.name] or (d.name == KEEP_ONE_STACK and 1) or 0
      if (kept[d.name] or 0) < keep then
        kept[d.name] = (kept[d.name] or 0) + 1
      else
        turtle.select(s)
        turtle.dropDown()
      end
    end
  end
  turtle.select(1)
end

-- Merge split stacks. Mined items land in the first empty slot, so after
-- junk is dropped the same ore ends up spread over several slots.
local function compact()
  for s = 16, 2, -1 do
    if turtle.getItemCount(s) > 0 then
      turtle.select(s)
      for t = 1, s - 1 do
        if turtle.getItemCount(t) > 0 and turtle.getItemSpace(t) > 0
          and turtle.compareTo(t) then
          turtle.transferTo(t)
          if turtle.getItemCount(s) == 0 then break end
        end
      end
    end
  end
  turtle.select(1)
end

local function unload()
  face((st.homeD + 2) % 4)
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    local keep = d and (d.name == BUCKET or d.name == LAVA_BUCKET or d.name == CHUNKY
      or d.name == PICKAXE)
    while not keep and turtle.getItemCount(s) > 0 do
      turtle.select(s)
      if not turtle.drop() then
        print("Chest is full. Waiting...")
        report("chest full")
        sleep(5)
      end
    end
  end
  turtle.select(1)
end

-- Swarm trips are saved as they go (st.phase), so a restart half-way
-- carries on with the trip instead of starting again from the plot.
--   "unload" = heading to the base with cargo; st.back = where to return to
--   "return" = unloaded, heading back to st.back

local function finishUnload()
  toDockFromAnywhere()
  refuelFromInventory(FUEL_TARGET)
  unloadDock()
  serviceStop(tripFuel(st.back.y))
  collectEmpties()                     -- a few empty buckets, to bring lava home in
  st.phase = "return"
  save()
end

local function finishReturn()
  report("flying to plot")
  toShaftFromAnywhere()
  travelTo(st.back.lf, st.back.lr, st.back.y)
  st.phase, st.back = nil, nil
  save()
  report("mining")
end

-- Swarm version of a trip home: fly to the base, unload, fly back.
local function dockTrip(reason)
  local lf, lr = toLocal()
  dropJunk()   -- no point carrying rubble home
  compact()
  st.back = { lf = lf, lr = lr, y = pos.y }
  st.phase = "unload"
  save()
  print("Flying to base: " .. reason)
  report("flying to base")
  finishUnload()
  print("Back to work.")
  finishReturn()
end

local function homeTrip(reason)
  if st.swarm then return dockTrip(reason) end
  dropJunk()
  compact()
  local lf, lr = toLocal()
  local y = pos.y
  print("Going home: " .. reason)
  report("going home")
  goHome()
  refuelFromInventory(FUEL_TARGET)
  unload()
  refuelAny(tripFuel(y))
  print("Back to work.")
  report("mining")
  travelTo(lf, lr, y)
end

local function housekeeping()
  if fuel() < FUEL_LOW then refuelFromInventory(FUEL_TARGET) end
  if fuel() < distHome() + 50 then
    homeTrip("low fuel")
    return
  end
  if emptySlots() < 2 then
    dropJunk()
    compact()
    if emptySlots() < 3 then homeTrip("inventory full") end
  end
end

---------------------------------------------------------------- mining

local function digUpDown()
  if turtle.detectUp() then safeDigUp() end
  if turtle.detectDown() then safeDigDown() end
end

-- Scoop lava into the bucket and burn it. inspect sees fluids; level 0 is a
-- full source block, the only kind a bucket can pick up.
local function slotOf(name)
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and d.name == name then return s, d.count end
  end
end

-- Fill an empty bucket from a full block of lava. keep = leave it full (to
-- take home); otherwise it goes straight into the tank. True if one was filled.
local function scoop(inspectFn, placeFn, keep)
  local ok, data = inspectFn()
  if not (ok and data.name == "minecraft:lava" and data.state and data.state.level == 0) then
    return false
  end
  local slot = slotOf(BUCKET)
  if not slot then return false end
  turtle.select(slot)
  local filled = placeFn()
  if filled and not keep then
    local full = slotOf(LAVA_BUCKET)
    if full then
      turtle.select(full)
      turtle.refuel()
    end
  end
  turtle.select(1)
  return filled
end

local bucketChecked, emptyN, fullN = -1000, 0, 0

local function lavaFuel()
  -- looking through the inventory is slow, so only re-check now and then
  if os.clock() - bucketChecked > 60 then
    bucketChecked = os.clock()
    emptyN, fullN = 0, 0
    for s = 1, 16 do
      local d = turtle.getItemDetail(s)
      if d and d.name == BUCKET then emptyN = emptyN + d.count end
      if d and d.name == LAVA_BUCKET then fullN = fullN + d.count end
    end
  end
  local drink = fuel() < LAVA_TARGET
  if drink and emptyN == 0 and fullN > 0 then
    -- every bucket is full and the tank is not: drink one
    local full = slotOf(LAVA_BUCKET)
    if full then
      turtle.select(full)
      if turtle.refuel() then emptyN, fullN = emptyN + 1, fullN - 1 end
      turtle.select(1)
    end
    return
  end
  if emptyN == 0 then return end
  -- tank full: fill the spare buckets for the base (one empty stays for us)
  if not drink and not (emptyN >= 2 and fullN < LAVA_SPARE) then return end
  for _, side in ipairs({ { turtle.inspectDown, turtle.placeDown }, { turtle.inspectUp, turtle.placeUp },
    { turtle.inspect, turtle.place } }) do
    if scoop(side[1], side[2], not drink) and not drink then
      emptyN, fullN = emptyN - 1, fullN + 1
      if emptyN < 2 or fullN >= LAVA_SPARE then break end
    end
  end
end

local function mineStep()
  digUpDown()
  lavaFuel()
  housekeeping()
  if os.clock() - lastReport > 30 then report("mining") end
end

-- Mine one row (fixed lr) of the layer centred on y. False if blocked.
local function mineRow(lr, y)
  local cf = toLocal()
  local startF, endF = 1, st.size
  if math.abs(cf - st.size) < math.abs(cf - 1) then
    startF, endF = st.size, 1
  end
  if not goLocal(startF, lr, y, "yrf", false) then return false end
  mineStep()
  local wx, wz = toWorld(endF, lr)
  local axis = fAxis()
  local target = axis == "x" and wx or wz
  return axisMove(axis, target, false, mineStep)
end

---------------------------------------------------------------- coal hunting

local function findItem(name)
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and d.name == name then return s end
  end
  return nil
end

local function countItem(name)
  local n = 0
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and d.name == name then n = n + d.count end
  end
  return n
end

-- Hunting happens on its own level, above the roads and the plots.
local function huntY() return st.home.y + 10 end

-- The side holding the pickaxe (the other one holds the modem).
local function toolSide()
  if peripheral.getType("left") == "modem" then return "right" end
  return "left"
end

-- If a restart caught us with the scanner fitted, put the pickaxe back.
local function fixTool()
  local side = toolSide()
  local fitted = peripheral.getType(side)
  local slot = findItem(PICKAXE)
  if fitted and fitted ~= "modem" and slot then
    turtle.select(slot)
    if side == "left" then turtle.equipLeft() else turtle.equipRight() end
    turtle.select(1)
    if chunky then chunky.forget() end
  end
end

-- Swap the pickaxe for the scanner, look around, swap back.
-- Returns a list of coal ore positions, or nil and a reason.
local function scanForCoal(deep)
  local slot = findItem(SCANNER)
  if not slot then return nil, "I have no Geo Scanner" end
  if chunky then chunky.tool() end        -- (the pickaxe is what the scanner swaps with)
  local side = toolSide()
  local equip = side == "left" and turtle.equipLeft or turtle.equipRight
  turtle.select(slot)
  if not equip() then
    turtle.select(1)
    return nil, "could not fit the scanner"
  end
  local found, why
  for _ = 1, 12 do
    local scanner = peripheral.wrap(side)
    -- Advanced Peripherals 0.8 calls it scanBlocks; older versions scan
    local fn = scanner and (scanner.scanBlocks or scanner.scan)
    if fn then
      local ok, blocks, reason = pcall(fn, HUNT_RADIUS)
      if ok and type(blocks) == "table" then
        found = blocks
        break
      end
      why = tostring(ok and reason or blocks)
      sleep(2)          -- usually the scanner's cooldown
    else
      why = "no scanner on the " .. side .. " (found " .. tostring(peripheral.getType(side)) .. ")"
      sleep(1)
    end
  end
  turtle.select(slot)
  equip()          -- pickaxe back on
  turtle.select(1)
  if chunky then chunky.forget() end
  if not found then return nil, why or "scan failed" end
  local ores, lava = {}, {}
  for _, b in ipairs(found) do
    if deep and b.name == "minecraft:lava" and b.x and b.y and b.z then
      local x, y, z = pos.x + b.x, pos.y + b.y, pos.z + b.z
      -- (the bottom of the world, where the caves are flooded with it)
      if y <= (st.bottom or -58) + 18 and math.abs(x - st.exit1.x) <= DEEP_REACH
        and math.abs(z - st.exit1.z) <= DEEP_REACH then
        lava[#lava + 1] = { x = x, y = y, z = z }
      end
    end
    if type(b.name) == "string" and b.name:find("coal", 1, true)
      and not b.name:find("charcoal", 1, true) and b.x and b.y and b.z then
      local x, y, z = pos.x + b.x, pos.y + b.y, pos.z + b.z
      local nearBase = math.abs(x - st.exit1.x) <= 12 and math.abs(z - st.exit1.z) <= 12
      local wanted
      if deep then
        -- under the base: below the roads, inside the ring of plots
        wanted = y <= st.home.y - 4 and math.abs(x - st.exit1.x) <= DEEP_REACH
          and math.abs(z - st.exit1.z) <= DEEP_REACH
      else
        wanted = y > st.home.y and not nearBase and z >= st.exit1.z - HUNT_NORTH - 6
      end
      if wanted then
        ores[#ores + 1] = { x = x, y = y, z = z }
      end
    end
  end
  return ores, lava
end

-- Straight-line dig to a block. False if something will not break.
local function digTo(x, y, z)
  return axisMove("y", y, false) and axisMove("x", x, false) and axisMove("z", z, false)
end

-- Places to scan from: a grid around the factory, skipping the middle.
local function huntPoints(reach)
  local pts = {}
  local n = math.floor(reach / HUNT_STEP)
  for i = -n, n do
    for k = -n, n do
      local dx, dz = i * HUNT_STEP, k * HUNT_STEP
      if math.max(math.abs(dx), math.abs(dz)) >= HUNT_NEAR and dz >= -HUNT_NORTH then
        pts[#pts + 1] = { x = st.exit1.x + dx, z = st.exit1.z + dz }
      end
    end
  end
  return pts
end

-- Leave the base down the out-shaft, stopping at the hunting level.
local function leaveToHunt()
  toExitColumn()
  local out = outShaft()
  if over(st.exit2) then flyTo(out.x, out.z) end
  axisMove("y", huntY(), true)
end

-- A miner with no Chunk Controller asks the factory for one to carry, on
-- top of it (where it hands things over): a hunter each time it brings coal
-- home, the others between plots. At most every 20 minutes, and not for an
-- hour after being told there is none to spare.
local ctlAsked, ctlNone = -10000, -10000
local function askController()
  if not chunky or chunky.have(true) then return end
  if os.clock() - ctlAsked < 1200 or os.clock() - ctlNone < 3600 then return end
  if at(st.dock) then flyTo(st.exit1.x, st.exit1.z) end
  if not at(st.exit1) then return end
  ctlAsked = os.clock()
  local me = os.getComputerID()
  print("Asking the factory for a Chunk Controller to carry.")
  for _ = 1, 6 do
    rednet.broadcast({ type = "controller_request", id = me }, JOB_PROTOCOL)
    local _, m = rednet.receive(JOB_PROTOCOL, 4)
    if type(m) == "table" and m.type == "controller_none" and m.forId == me then
      ctlNone = os.clock()
      print("None to spare.")
      return
    end
    if chunky.have(true) then
      print("Got one.")
      return
    end
  end
end

-- Take the coal home, then come back out.
local function huntDeliver()
  print("Taking coal to the base.")
  report("flying to base")
  local shaft = inShaft()
  axisMove("y", huntY(), true)
  flyTo(shaft.x, shaft.z)
  upToDock()
  refuelFromInventory(FUEL_TARGET)
  unloadDock()
  -- never set off again on an empty tank: get fuel from the factory first
  -- (it once ran dry in the exit shaft and blocked every miner behind it)
  serviceStop(FUEL_LOW)
  collectEmpties()
  if not findItem(SCANNER) then
    -- a hunter made by remote order: the factory hands over a spare Geo Scanner
    if at(st.dock) then flyTo(st.exit1.x, st.exit1.z) end
    if at(st.exit1) then
      print("Asking the factory for a Geo Scanner.")
      report("needs a scanner")
      for _ = 1, 30 do
        rednet.broadcast({ type = "scanner_request", id = os.getComputerID() }, JOB_PROTOCOL)
        sleep(4)
        if findItem(SCANNER) then break end
      end
    end
  end
  askController()
  leaveToHunt()
  report("hunting coal")
end

-- Moves from a column on the hunting level back to the drop-off chest.
local function huntHomeDistance(x, z)
  local shaft = inShaft()
  return math.abs(x - shaft.x) + math.abs(z - shaft.z) + (st.dock.y - huntY()) + 2
end

-- Scan where we are and dig out every coal ore found. Returns how many.
local function harvestHere(deep)
  local ores, why = scanForCoal(deep)
  if not ores then
    print("Scanner problem: " .. tostring(why))
    report("scanner problem")
    return nil, why
  end
  print(#ores .. " coal ore nearby.")
  report("hunting coal")
  local n = #ores
  while #ores > 0 do
    local ni, nd
    for i, o in ipairs(ores) do
      local d = math.abs(o.x - pos.x) + math.abs(o.y - pos.y) + math.abs(o.z - pos.z)
      if not nd or d < nd then ni, nd = i, d end
    end
    local o = table.remove(ores, ni)
    digTo(o.x, o.y, o.z)
    if fuel() < FUEL_LOW then refuelFromInventory(FUEL_TARGET) end
    -- rubble out before the inventory fills (coal dug with no room for it
    -- falls on the ground; a controller on board takes a slot too)
    if emptySlots() < 2 then
      dropJunk()
      compact()
    end
  end
  axisMove("y", deep or huntY(), true)
  return n
end

-- Lava is the best fuel there is (a bucket is 1,000 moves), and deep under
-- the base the caves are full of it. With empty buckets on board: down one
-- of the four columns to the bottom, scan, and fill every bucket from the
-- nearest full lava blocks. The factory hands the buckets out as fuel.
local DEEP_PTS = { { 14, 14 }, { 14, -14 }, { -14, 14 }, { -14, -14 } }
local function lavaStep()
  if countItem(BUCKET) < 2 then return false end       -- (one is its own)
  if st.lavaTry ~= 2 then st.lavaDry, st.lavaTry = {}, 2 end   -- (the first go said nothing about why)
  st.lavaDry = st.lavaDry or {}
  for i, p in ipairs(DEEP_PTS) do
    if not st.lavaDry[i] then
      local x, z = st.exit1.x + p[1], st.exit1.z + p[2]
      local level = (st.bottom or -58) + 6
      print(("Fetching lava under the base (column %d)."):format(i))
      report("fetching lava")
      local there = (pos.x == x and pos.z == z)
        or (axisMove("y", huntY(), false) and axisMove("x", x, false) and axisMove("z", z, false))
      local filled = 0
      if there and axisMove("y", level, false) then
        local _, lava = scanForCoal(level)
        local seen, flowing, missed = type(lava) == "table" and #lava or -1, 0, 0
        if type(lava) == "table" then
          table.sort(lava, function(a, b)
            return math.abs(a.x - x) + math.abs(a.z - z) + math.abs(a.y - level)
              < math.abs(b.x - x) + math.abs(b.z - z) + math.abs(b.y - level)
          end)
          for _, o in ipairs(lava) do
            if countItem(BUCKET) < 2 or fuel() < 300 then break end
            -- over it, and scoop down: only a full block of lava comes up
            if digTo(o.x, o.y + 1, o.z) then
              local ok, data = turtle.inspectDown()
              if ok and data.name == "minecraft:lava" and data.state and data.state.level == 0 then
                turtle.select(findItem(BUCKET))
                if turtle.placeDown() then filled = filled + 1 else missed = missed + 1 end
                turtle.select(1)
              else
                flowing = flowing + 1
              end
            else
              missed = missed + 1
            end
          end
        end
        print(("Lava at y %d: %d blocks seen, %d not full, %d missed."):format(level, seen, flowing, missed))
        digTo(x, level, z)
        axisMove("y", huntY(), true)
      end
      if filled == 0 then st.lavaDry[i] = true end
      save()
      print(("Filled %d buckets with lava."):format(filled))
      report("hunting coal")
      if filled > 0 then return true end
    end
  end
  return false
end

-- Empty buckets for the next lava run, from the factory (at the service
-- stop above it, after unloading).
collectEmpties = function()
  local want
  if st.hunt then
    local dry = st.lavaDry or {}
    if dry[1] and dry[2] and dry[3] and dry[4] then return end
    want = LAVA_RUN + 1 - countItem(BUCKET)
  else
    want = LAVA_SPARE + 1 - countItem(BUCKET)
  end
  if want <= 0 then return end
  if at(st.dock) then flyTo(st.exit1.x, st.exit1.z) end
  if not at(st.exit1) then return end
  print("Asking the factory for empty buckets.")
  for _ = 1, (st.hunt and 20 or 5) do   -- (it may be in the middle of a load)
    rednet.broadcast({ type = "empties_request", id = os.getComputerID(), n = want }, JOB_PROTOCOL)
    sleep(4)
    if countItem(BUCKET) > LAVA_RUN + 1 - want then break end
  end
end

-- Under the base nobody mines: the plots start 24 blocks out. Four columns
-- down through it, scanning every 16 blocks, reach nearly all of it.
local function deepStep()
  st.deepDone = st.deepDone or {}
  local levels = {}
  for y = st.home.y - 6, (st.bottom or -58) + 6, -16 do levels[#levels + 1] = y end
  for i, p in ipairs(DEEP_PTS) do
    local k = (st.deepDone[i] or 0) + 1
    if k <= #levels then
      local x, z = st.exit1.x + p[1], st.exit1.z + p[2]
      print(("Under the base: column %d of 4, y %d"):format(i, levels[k]))
      local there = pos.x == x and pos.z == z
      if not there then
        there = axisMove("y", huntY(), false) and axisMove("x", x, false) and axisMove("z", z, false)
      end
      if there and axisMove("y", levels[k], false) then
        harvestHere(levels[k])
        st.deepDone[i] = k
      else
        st.deepDone[i] = #levels             -- cannot get there: leave this column
      end
      if st.deepDone[i] >= #levels then axisMove("y", huntY(), true) end
      save()
      return true
    end
  end
  return false
end

-- Fly to a stranded miner, drop coal on it, come back up.
local function rescue(id, p)
  if type(p) ~= "table" or not (p.x and p.y and p.z) then return end
  if p.y >= huntY() then return end                  -- the base looks after those
  if countItem("minecraft:coal") < RESCUE_COAL then return end
  local trip = 2 * (math.abs(p.x - pos.x) + math.abs(p.z - pos.z) + (huntY() - p.y)) + 60
  if fuel() < trip then return end
  print("Rescuing #" .. tostring(id) .. " at " .. p.x .. ", " .. p.y .. ", " .. p.z)
  report("rescuing")
  axisMove("y", huntY(), true)
  flyTo(p.x, p.z)
  axisMove("y", p.y + 1, false)                      -- dig down to just above it
  local ok, data = turtle.inspectDown()
  if pos.y == p.y + 1 and ok and tostring(data.name):find("computercraft:turtle", 1, true) then
    local slot = findItem("minecraft:coal")
    if slot then
      turtle.select(slot)
      turtle.dropDown(RESCUE_COAL)
      turtle.select(1)
      print("Gave it " .. RESCUE_COAL .. " coal.")
    end
  else
    print("It was not there.")
  end
  axisMove("y", huntY(), true)
  report("hunting coal")
end

-- Listen briefly for stranded miners calling for help.
local function listenForRescue(seconds)
  local deadline = os.clock() + seconds
  while os.clock() < deadline do
    local id, msg = rednet.receive(RESCUE_PROTOCOL, math.max(0.5, deadline - os.clock()))
    if type(msg) == "table" and msg.type == "rescue" and id ~= os.getComputerID() then
      rescue(id, msg.pos)
      return
    end
  end
end

-- The coal hunter: roams a growing area around the base, digging out every
-- coal ore the scanner finds, taking the coal home, and bringing coal to
-- any miner that has run dry. It never goes back to a plot.
local function hunt()
  -- (a second hunter, made by remote order while the first is missing, has its own name)
  local name = st.huntName or "Coalition"
  if swarm.newName then name = swarm.newName(name) end
  if os.getComputerLabel() ~= name then os.setComputerLabel(name) end
  print("Hunting coal.")
  report("hunting coal")
  fixTool()
  swarm.open()

  -- give the plot back so another miner can finish it
  if st.index then
    rednet.broadcast({ type = "release", id = os.getComputerID(), index = st.index }, JOB_PROTOCOL)
    st.index = nil
    save()
  end

  -- get onto the hunting level from wherever we are, the right way round
  local shaft, out = inShaft(), outShaft()
  if at(st.dock) or (pos.x == shaft.x and pos.z == shaft.z and pos.y <= st.dock.y
    and pos.y >= huntY()) then
    if not at(st.dock) then upToDock() end
    refuelFromInventory(FUEL_TARGET)
    unloadDock()
    leaveToHunt()
  elseif at(st.exit1) or (over(st.exit2) and pos.y >= st.exit2.y - 1)
    or (pos.x == out.x and pos.z == out.z and pos.y <= st.dock.y and pos.y >= huntY()) then
    leaveToHunt()
  else
    axisMove("y", huntY(), true)
  end

  st.huntDone = st.huntDone or {}
  st.huntReach = math.min(st.huntReach or HUNT_REACH, HUNT_MAX)
  local scannedHere = false
  while true do
    if fuel() < FUEL_LOW then refuelFromInventory(FUEL_TARGET) end
    if not findItem(SCANNER) then
      huntDeliver()                    -- (to the base for a scanner first)
      if not findItem(SCANNER) then
        print("No Geo Scanner to be had. Waiting.")
        report("needs a scanner")
        sleep(120)
      end
    end
    if countItem("minecraft:coal") >= HUNT_LOAD or emptySlots() < 3 then
      dropJunk()
      compact()
      if countItem("minecraft:coal") >= HUNT_LOAD or emptySlots() < 3 then
        huntDeliver()
        scannedHere = false
      end
    end
    listenForRescue(6)

    local gotLava = fuel() >= 600 and lavaStep()
    if gotLava then
      huntDeliver()
    elseif not (fuel() >= 600 and deepStep()) then
    -- nearest scan point not yet visited
    local pts = huntPoints(st.huntReach)
    local best, bestD
    for i, p in ipairs(pts) do
      if not st.huntDone[i] then
        local d = math.abs(p.x - pos.x) + math.abs(p.z - pos.z)
        if not bestD or d < bestD then best, bestD = i, d end
      end
    end

    if not best then
      -- the whole area is covered: widen it and go round again
      st.huntDone = {}
      st.huntReach = math.min(st.huntReach + 2 * HUNT_STEP, HUNT_MAX)
      save()
      print("Area covered. Now searching out to " .. st.huntReach .. " blocks.")
    else
      local p = pts[best]
      local need = bestD + huntHomeDistance(p.x, p.z) + 30
      if fuel() < need and not scannedHere then
        -- short of fuel: look where we are before going anywhere
        print("Low on fuel. Scanning here first.")
        harvestHere()
        scannedHere = true
      elseif fuel() < need then
        if fuel() >= huntHomeDistance(pos.x, pos.z) + 5 then
          print("Low on fuel. Heading home.")
          huntDeliver()
          serviceStop(1500)
          scannedHere = false
        else
          print("Stranded: not enough fuel to get home.")
          report("stranded")
          rednet.broadcast({ type = "fuel_request", id = os.getComputerID() }, JOB_PROTOCOL)
          sleep(60)
          refuelFromInventory(FUEL_TARGET)
        end
      else
        print(("Scan point %d of %d"):format(best, #pts))
        report("hunting coal")           -- (so it is heard from on the way, not only on arrival)
        local reached = axisMove("y", huntY(), false) and axisMove("x", p.x, false)
          and axisMove("z", p.z, false)
        if reached then
          local found, why = harvestHere()
          if not found then sleep(20) end
        end
        scannedHere = reached
        st.huntDone[best] = true
        save()
      end
    end
    end
  end
end

-- Ask the factory for a plot to mine. With no time limit it waits until one
-- is offered; with one (seconds) it gives up and returns nil.
local function requestJob(limit)
  swarm.open()
  local me = os.getComputerID()
  while true do
    rednet.broadcast({ type = "need_job", id = me }, JOB_PROTOCOL)
    local deadline = os.clock() + (limit or 5)
    while os.clock() < deadline do
      local _, msg = rednet.receive(JOB_PROTOCOL, 1)
      if type(msg) == "table" and msg.type == "role" and msg.forId == me
        and type(msg.role) == "string" then
        -- the factory built this turtle for another job (e.g. the builder)
        local h = fs.open(".role", "w")
        h.write(msg.role)
        h.close()
        if type(msg.base) == "table" then
          h = fs.open(".base", "w")
          h.write(textutils.serialize(msg.base))
          h.close()
        end
        if type(msg.name) == "string" then os.setComputerLabel(msg.name) end
        fs.delete(STATE_FILE)
        print("New job: " .. msg.role .. ". Restarting.")
        sleep(1)
        os.reboot()
      end
      if type(msg) == "table" and msg.type == "job" and msg.forId == me then
        return msg
      end
    end
    if limit then return nil end
    report("waiting for a plot")
    sleep(20)
  end
end

local function stateForJob(j)
  return {
    swarm = true, index = j.index,
    home = { x = j.x0 - 1, y = j.topY, z = j.z0 }, homeD = 0,
    size = j.size, bottom = j.bottom, layer = 1,
    cruise = j.cruise, dock = j.dock, exit1 = j.exit1, exit2 = j.exit2, origin = j.origin,
  }
end

local function buildLayers()
  local layers = {}
  local c = st.home.y - 2
  while c > st.bottom do
    layers[#layers + 1] = c
    c = c - 3
  end
  layers[#layers + 1] = st.bottom
  return layers
end

local function run()
  local layers = buildLayers()
  totalLayers = #layers
  report("starting")
  if atHome() and st.layer <= #layers then
    refuelAny(tripFuel(layers[st.layer]))
    travelTo(1, 0, layers[st.layer])
  end
  while st.layer <= #layers do
    local y = layers[st.layer]
    if not st.rowDir then
      local _, cr = toLocal()
      st.rowDir = (cr > (st.size - 1) / 2) and -1 or 1
      st.rowsDone = 0
      save()
    end
    while st.rowsDone < st.size do
      local lr = st.rowDir == 1 and st.rowsDone or (st.size - 1 - st.rowsDone)
      print(("Layer %d/%d  row %d/%d  fuel %s"):format(
        st.layer, #layers, st.rowsDone + 1, st.size, tostring(fuel())))
      report("mining")
      if not mineRow(lr, y) then print("Row blocked, skipping.") end
      st.rowsDone = st.rowsDone + 1
      save()
    end
    st.layer = st.layer + 1
    st.rowDir = nil
    save()
  end
  if st.swarm then
    if st.phase ~= "finished" then
      print("Plot finished. Flying to base.")
      report("flying to base")
      st.phase = "finish"
      save()
      toDockFromAnywhere()
      refuelFromInventory(FUEL_TARGET)
      unloadDock()
      rednet.broadcast({ type = "job_done", id = os.getComputerID(), index = st.index },
        JOB_PROTOCOL)
      st.phase = "finished"
      save()
    end
    if at(st.dock) or onExitSide() then
      serviceStop(600)
      askController()                 -- (a Chunk Controller of my own, if there is one to spare)
      -- ask for the next plot while still at the base, so we can go
      -- straight there along the out road
      local j = requestJob(6)
      if j then
        st = stateForJob(j)
        save()
        print(("Next plot: #%d at %d, %d"):format(j.index, j.x0, j.z0))
        return
      end
      -- none on offer: wait at the top of the old plot, clear of the roads
      toShaftFromAnywhere()
    end
    fs.delete(STATE_FILE)
    print("Plot done.")
    report("done")
    return
  end
  print("Finished. Going home.")
  report("going home")
  goHome()
  unload()
  face(st.homeD)
  fs.delete(STATE_FILE)
  print("Done.")
  report("done")
end

---------------------------------------------------------------- startup

-- A turtle labelled "loader..." is Ghastly (it carries a Chunk
-- Controller, not a pickaxe): switch it to its own program.
if turtle and (os.getComputerLabel() or ""):lower():match("^loader") then
  local h = fs.open(".role", "w")
  h.write("loader")
  h.close()
  print("This is the chunk loader. Switching job.")
  sleep(1)
  os.reboot()
end

local function loadState()
  if not fs.exists(STATE_FILE) then return false end
  local h = fs.open(STATE_FILE, "r")
  local t = textutils.unserialize(h.readAll())
  h.close()
  if type(t) ~= "table" then return false end
  st = t
  return true
end

-- Find out where we are and which way we face.
-- False if we are somewhere outside the job area.
local function relocate()
  refuelAny(10)
  heading = detectHeading()
  pos.x, pos.y, pos.z = locate()
  if st.swarm then
    refuelFromInventory(FUEL_TARGET)
    if st.hunt then return true end   -- hunt() finds its own way
    if st.phase == "finish" or st.phase == "finished" then
      return true   -- run() finishes the job from wherever we are
    end
    if st.phase == "unload" then finishUnload() end
    if st.phase == "return" then
      finishReturn()
    else
      toShaftFromAnywhere()
    end
    return true
  end
  local lf, lr = toLocal()
  local inPlot = lf >= 1 and lf <= st.size and lr >= 0 and lr < st.size
    and pos.y <= st.home.y
  if not (atHome() or inPlot) then
    print("I am outside my mining area.")
    print("Put me back at my home spot, or run:")
    print("  delete " .. STATE_FILE)
    report("lost")
    return false
  end
  return true
end

local located = false   -- true only straight after a fresh GPS fix
local idleState = "idle"

-- Run fn, reporting any crash. Ctrl+T is passed through to the shell.
local function guarded(fn)
  local ok, err = pcall(fn)
  if not ok then
    if err == "Terminated" then
      report("stopped by player")
      error(err, 0)
    end
    print("ERROR: " .. tostring(err))
    report("error")
  end
end

-- Do the saved job; when there is none (or it finishes), get a plot from
-- the factory and mine that, for ever.
local function jobTask()
  guarded(function()
    while true do
      if not st then
        if not swarm then return end
        print("Asking the base for a plot...")
        local j = requestJob()
        st = stateForJob(j)
        save()
        located = false
        print(("Plot #%d at %d, %d"):format(j.index, j.x0, j.z0))
      end
      -- any swarm miner that is holding a Geo Scanner hunts coal instead
      if st.swarm and not st.hunt and not st.huntFinished and findItem(SCANNER) then
        st.hunt = true
        st.phase, st.back = nil, nil
        save()
      end
      local job, wasHunting = st, st.hunt
      local ok, err = pcall(function()
        if not located and not relocate() then error("LOST", 0) end
        located = false
        if st.hunt then hunt() else run() end
      end)
      if not ok then
        if err == "LOST" then return end
        -- "SWITCH_TO_HUNT": handed a scanner mid-trip; go round again as a hunter
        if err ~= "SWITCH_TO_HUNT" then error(err, 0) end
        located = false
      elseif wasHunting then
        -- the hunt covered its whole area: go round again and resume the plot
      elseif st == job then
        st = nil   -- plot finished (unless run() lined up the next one)
      end
    end
  end)
end

-- Go home, unload and wait there. The job is kept for a later "resume".
local function homeTask()
  guarded(function()
    print("Ordered home.")
    if st.swarm then
      refuelAny(10)
      heading = detectHeading()
      pos.x, pos.y, pos.z = locate()
      report("flying to base")
      toDockFromAnywhere()
      refuelFromInventory(FUEL_TARGET)
      unloadDock()
      serviceStop(tripFuel(st.home.y))
      toShaftFromAnywhere()            -- wait at the top of our plot, off the roads
    else
      if not relocate() then return end
      report("going home")
      goHome()
      unload()
      face(st.homeD)
    end
    print("Parked.")
    report("parked")
  end)
end

local function idleTask()
  print("Waiting for orders. (Hold Ctrl+T for the prompt.)")
  while true do
    report(idleState)
    sleep(60)
  end
end

local function main(args)
  if not turtle then
    print("This program only runs on a turtle.")
    return
  end

  -- remember what this machine is, and give it a proper name
  do
    local h = fs.open(".role", "w")
    h.write("miner")
    h.close()
    local label = os.getComputerLabel()
    if not label or label:match("^miner%-%d+$") then
      os.setComputerLabel(NAMES[(os.getComputerID() - 1) % #NAMES + 1])
    end
  end

  local size = tonumber(args[1])
  local task

  if size then
    -- new job
    size = math.floor(size)
    if size < 1 then
      print("Size must be at least 1.")
      return
    end
    if not peripheral.hasType("back", "inventory") then
      print("Put a chest directly behind me first.")
      return
    end
    refuelAny(10)
    heading = detectHeading()
    pos.x, pos.y, pos.z = locate()
    local bottom = tonumber(args[2]) or MIN_Y
    if pos.y - 2 < bottom then
      print("I am too low to mine down to Y " .. bottom .. ".")
      return
    end
    st = {
      home = { x = pos.x, y = pos.y, z = pos.z },
      homeD = heading,
      size = size,
      bottom = bottom,
      layer = 1,
    }
    save()
    if not fs.exists("startup.lua") then
      local h = fs.open("startup.lua", "w")
      h.write('shell.run("' .. shell.getRunningProgram() .. '", "resume")\n')
      h.close()
    end
    print(("Mining %dx%d from Y %d down to Y %d."):format(
      size, size, pos.y - 1, bottom - 1))
    located = true
    task = jobTask
  elseif args[1] == nil or args[1] == "resume" or args[1] == "go" then
    -- "resume" is what startup runs. "go" also un-parks a parked turtle.
    if loadState() then
      if args[1] == "go" and st.paused then
        st.paused = nil
        save()
      end
      if st.paused then
        print("Parked by remote order. Run 'miner go' to carry on.")
        idleState = "parked"
        task = idleTask
      else
        print("Resuming saved job...")
        task = jobTask
      end
    elseif args[1] == "resume" and swarm then
      task = jobTask   -- no saved job: ask the base for a plot
    else
      if args[1] ~= "resume" then
        print("Usage: miner <size> [bottomY]")
        print("Chest behind me, mining area in front.")
      end
      return
    end
  else
    print("Usage: miner <size> [bottomY]")
    return
  end

  if not swarm then
    task()
    return
  end

  -- Do the task while listening for remote orders.
  while true do
    local cmd = swarm.runWithCommands(task, function(c)
      if c.cmd == "ping" then
        report(lastState)
        return true
      end
      if c.cmd == "openhole" then
        local h = fs.open(HOLE_FILE, "w")
        h.write("yes")
        h.close()
        return true
      end
    end)
    if not cmd then
      -- the task ended by itself (finished, crashed, or parked at home)
      if task == homeTask and st then
        st.paused = true
        save()
        idleState = "parked"
      else
        idleState = st and lastState or "idle"
      end
      task = idleTask
    elseif cmd.cmd == "reboot" then
      print("Rebooting by remote order.")
      swarm.pinVersion(cmd)
      report("rebooting")
      os.reboot()
    elseif cmd.cmd == "stop" then
      print("Stopped by remote order.")
      if st then
        st.paused = true
        save()
      end
      idleState = "stopped"
      task = idleTask
    elseif cmd.cmd == "home" then
      if st or loadState() then
        st.paused = true
        save()
        task = homeTask
      else
        task = idleTask
      end
    elseif cmd.cmd == "hunt" then
      -- become a coal (and lava) hunter: give up the plot, fetch a scanner
      if st or loadState() then
        st.hunt, st.paused = true, nil
        st.huntName = type(cmd.name) == "string" and cmd.name:match("^[%w_]+$") or st.huntName
        if st.huntName and swarm.newName then st.huntName = swarm.newName(st.huntName) end
        st.phase, st.back = nil, nil
        save()
        located = false
        print("Hunting by remote order.")
        task = jobTask
      end
    elseif cmd.cmd == "newjob" then
      -- drop the plot in hand and ask the factory what to do (it may have
      -- drafted this turtle for another job)
      st = nil
      fs.delete(STATE_FILE)
      located = false
      print("Asking the base for a new job.")
      task = jobTask
    elseif cmd.cmd == "resume" then
      if st or loadState() then
        st.paused = nil
        save()
        located = false
        print("Resuming by remote order.")
        task = jobTask
      else
        located = false
        task = jobTask
      end
    end
  end
end

main({ ... })
