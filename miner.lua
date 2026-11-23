--- miner.lua: dig the plot the controller hands out, bring everything home to its berth
-- in the hangar, refuel there, go back, and ask for the next plot when it is done.
--
-- Built only from lib/ (move, inv, state, log, net). What it knows about the base comes
-- with the job, as two lists of corners to fly through, one after the other:
--
--   inbound  : top of the IN shaft ... its berth       (the shaft's foot is on the in road)
--   outbound : its berth ... top of the OUT shaft      (the shaft's foot is on the out road)
--
-- Both are one-way, so two miners never meet head on. Under ground it travels on two
-- one-way roads, as before:
--
--   out road  (topY + 2):  base -> plot      down the OUT shaft, along, down the plot's shaft
--   in road   (topY + 6):  plot -> base      up the plot's shaft, along, up the IN shaft
--
-- At the berth there is a barrel below (everything it carries goes in; a conveyor takes it
-- to the store) and a barrel above (lava buckets, kept filled by the store).
--
-- Fuel is lava. At the berth it burns lava buckets from the barrel overhead and sends the
-- empties down with the cargo, all but one: with that one it scoops up any lava it finds
-- over or under its path in the plot. Coal it digs goes to the store; it only burns coal
-- when there is no lava to be had.
--
-- A plot is size x size columns from (x0, z0), dug in layers three blocks high from topY
-- down to bottom. Progress is saved after every cell, so a restart carries on where it was.
--
-- Rules it keeps:
--   * it never digs higher than 12 above the plot tops: up there everything is the factory
--   * it never digs a protected block (machines, cables, chests, other turtles). On the way
--     somewhere it waits for it to go; in its plot it leaves that one cell and carries on
--   * every wait is reported with its reason; a crash is reported, then startup restarts it
--
-- Orders (from the controller): stop, resume, newjob, reboot (rev = a commit to load), ping,
-- and layer n=<number>: carry on from that layer (a plot part-dug before this program took it over).

local log = require("lib.log")
local move = require("lib.move")
local inv = require("lib.inv")
local state = require("lib.state")
local net = require("lib.net")

local M = {}

M.cfg = {
  jobFile = "/.miner",
  fuelTarget = 3000,     -- fill up to this at the base
  scoopTo = 20000,       -- lava found while digging is scooped up until the tank holds this
  fuelLow = 600,         -- spare kept on top of the trip home; below it, go and refuel
  reportEvery = 20,      -- seconds between routine reports
  coalWait = 120,        -- seconds to wait at the berth for fuel, when it has too little to work on
  cellWaits = 3,         -- waits on a protected block in the plot before that cell is left
  clearZ = { 1522, 1568 }, -- no road runs east-west between these z: the reactor hall is under the building
  patience = math.huge,  -- waits on a blocked path before a leg gives up (tests lower it)
}

-- never dropped at the berth (of the empty buckets it keeps one: see spareBuckets)
local BUCKET, LAVA = "minecraft:bucket", "minecraft:lava_bucket"
local KEEP = { "*pickaxe*", "advancedperipherals:*", "computercraft:*", BUCKET }
-- held back while it refuels, in case there is no lava
local HOLD = { "*pickaxe*", "advancedperipherals:*", "computercraft:*", BUCKET, LAVA,
  "minecraft:coal", "minecraft:charcoal", "minecraft:coal_block" }
-- never dug, wherever it is met
local PROTECT = {
  "^computercraft:", "^advancedperipherals:", "chest", "barrel", "shulker_box", "hopper",
  "^ae2:", "^extendedae:", "^mekanism", "^create", "^pipez:", "^ad_astra", "^industrialforegoing:",
  "^immersiveengineering:", "^simplylight:", "^functionalstorage:", "^sophisticated",
  "concrete", "glass", "spawner", "_door", "ladder", "polished_", "smooth_stone", "_slab", "_stairs", "_wall",
}
-- ...except these, which the patterns above would catch: ores and the plain rock mods add
local NATURAL = {
  "_ore$", "^create:scoria$", "^create:scorchia$", "^create:limestone$", "^create:asurine$",
  "^create:crimsite$", "^create:ochrum$", "^create:veridium$",
}
local DIG_CEILING = 12       -- no digging higher than this above the plot tops (see go)

local J = {}                 -- the job in hand (saved in cfg.jobFile); J.index nil = none
local parked, abandon, rebootWanted = false, false, false
local jumpTo = nil           -- a layer to carry on from, by order
local lastReport, lastState = -1e9, nil
local scooped = 0            -- lava sources scooped up since it started

-- ---------------------------------------------------------------- geometry

local function outY() return J.topY + 2 end
local function inY() return J.topY + 6 end

--- Which way round the two roads go, as axis orders for the out road and the in road. The
-- east-west leg must stay clear of cfg.clearZ: plots beyond it run along their own row and
-- the column at the shafts; the others run along the lane at the shafts and their own column.
local function roadOrders()
  local c = M.cfg.clearZ
  if not c then return "xzy", "xzy" end
  if J.z0 > c[2] then return "zxy", "xzy" end
  return "xzy", "zxy"
end

--- The whole way in: foot of the in-shaft, then the job's corners, ending in the berth.
local function wayIn()
  local w = { { x = J.inbound[1].x, y = inY(), z = J.inbound[1].z } }
  for _, c in ipairs(J.inbound) do w[#w + 1] = c end
  return w
end

--- The whole way out: the berth, the job's corners, then the foot of the out-shaft.
local function wayOut()
  local w = {}
  for _, c in ipairs(J.outbound) do w[#w + 1] = c end
  w[#w + 1] = { x = w[#w].x, y = outY(), z = w[#w].z }
  return w
end

local function between(v, a, b) return v >= math.min(a, b) and v <= math.max(a, b) end

--- Standing on this way? Returns the number of the corner to make for next, or nil.
local function onWay(way)
  local p = move.pos
  for i = 1, #way - 1 do
    local a, b = way[i], way[i + 1]
    if between(p.x, a.x, b.x) and between(p.y, a.y, b.y) and between(p.z, a.z, b.z) then return i + 1 end
  end
  return nil
end

local function layerCount() return math.floor((J.topY - 2 - J.bottom) / 3) + 1 end
local function layerY(l) return J.topY - 2 - 3 * (l - 1) end

--- World x, z of cell i (1..size*size) of layer l. Rows snake; every other layer runs the
-- same path backwards, so a layer starts in the column the one above ended in.
local function cellPos(l, i)
  local n = J.size * J.size
  local k = (l % 2 == 1) and i or (n + 1 - i)
  local r, c = math.floor((k - 1) / J.size), (k - 1) % J.size
  if r % 2 == 1 then c = J.size - 1 - c end
  return J.x0 + c, J.z0 + r
end

local function inPlot()
  local p = move.pos
  return p.y <= J.topY and p.x >= J.x0 and p.x < J.x0 + J.size and p.z >= J.z0 and p.z < J.z0 + J.size
end

local function tripHome()
  local way, p = wayIn(), move.pos
  local n = math.abs(p.x - way[1].x) + math.abs(p.z - way[1].z) + math.abs(way[1].y - p.y) + 10
  for i = 1, #way - 1 do
    n = n + math.abs(way[i + 1].x - way[i].x) + math.abs(way[i + 1].y - way[i].y) + math.abs(way[i + 1].z - way[i].z)
  end
  return n
end

-- ---------------------------------------------------------------- reports, orders

local function save() state.save(M.cfg.jobFile, J) end

local function report(st, force)
  local now = os.clock()
  if not force and st == lastState and now - lastReport < M.cfg.reportEvery then return end
  lastState, lastReport = st, now
  local p = move.pos
  net.report({
    role = "miner", state = st, fuel = turtle.getFuelLevel(), freeSlots = inv.freeSlots(),
    pos = { x = p.x, y = p.y, z = p.z },
    job = J.index and { plot = J.index, layer = J.layer, layers = layerCount(), cell = J.cell, phase = J.phase } or nil,
    log = log.recent(6),
  })
end
M.report = report

--- Take an order. Nothing happens here but a note: the work loop acts on it between steps.
function M.order(cmd)
  local c = cmd.cmd
  if c == "stop" or c == "pause" or c == "home" then parked = true
  elseif c == "resume" or c == "go" then parked = false
  elseif c == "newjob" then abandon, parked = true, false
  elseif c == "reboot" then
    net.pinVersion(cmd)
    rebootWanted = true
  elseif c == "layer" then
    local n = tonumber(cmd.n)
    if n and n >= 1 then jumpTo = math.floor(n) end
  elseif c == "ping" then lastReport = -1e9 end
end
function M.flags() return { parked = parked, abandon = abandon, reboot = rebootWanted, jumpTo = jumpTo } end

--- Between steps: obey orders.
local function checkpoint()
  if rebootWanted then
    report("rebooting", true)
    sleep(1)
    os.reboot()
    error("rebooting", 0)
  end
  while parked do
    report("parked")
    sleep(5)
  end
end

-- ---------------------------------------------------------------- tools

--- A miner needs its pickaxe on. (The old coal hunters wore a scanner in its place and
-- carried the pickaxe.) Puts on a pickaxe found in the inventory, on the side the modem
-- is not. Returns false only if that could not be done.
local function ensureTool()
  if not turtle.equipRight then return true end
  local slot = inv.find("*pickaxe*")
  if not slot then return true end                  -- none carried: it is on already
  local modemLeft = false
  for _, t in ipairs({ peripheral.getType("left") }) do
    if t == "modem" then modemLeft = true end
  end
  turtle.select(slot)
  local ok
  if modemLeft then ok = turtle.equipRight() else ok = turtle.equipLeft() end
  turtle.select(1)
  if ok then log.info("put my pickaxe on") end
  return ok and true or false
end
M.ensureTool = ensureTool

-- ---------------------------------------------------------------- moving

--- Go to x, y, z (x, then z, then y unless `order` says otherwise). Waits out anything that
-- can clear by itself (another turtle, a sleeping chunk, no fuel) and says why it waits.
-- Returns false + reason only for a block it will never dig, or when patience runs out.
-- `giveUp`: stop waiting on a protected block after that many waits (cells of the plot).
local function go(x, y, z, order, giveUp)
  local waits = 0
  while true do
    checkpoint()
    -- no digging near the surface: up there only the shafts and the dock row are ours
    move.setup({ dig = math.max(move.pos.y, y) <= J.topY + DIG_CEILING })
    local ok, why = move.goTo(x, y, z, { order = order or "xzy" })
    if ok then
      log.progress()
      return true
    end
    why = tostring(why)
    local noTool = why:find("No tool", 1, true) and ensureTool()
    if why:find("^undiggable") and not noTool then return false, why end
    waits = waits + 1
    if waits > M.cfg.patience then return false, why end
    if giveUp and waits >= giveUp and (why:find("^protected") or why:find("^blocked")) then return false, why end
    if why == "no fuel" then inv.refuel(M.cfg.fuelLow) end
    if waits == 1 or waits % 12 == 0 then log.warn("on the way to %d,%d,%d: %s", x, y, z, why) end
    report("waiting: " .. why, waits == 1)
    sleep(why == "unloaded" and 30 or 5)
  end
end

local function must(ok, why)
  if not ok then error("cannot get there: " .. tostring(why), 0) end
end

local function follow(way, from)
  for i = from, #way do must(go(way[i].x, way[i].y, way[i].z)) end
end

--- From anywhere to the berth, always the right way along the one-way roads.
local function toBerth()
  local way = wayIn()
  local k = onWay(way)
  if not k then
    local out = wayOut()
    local ko = onWay(out)
    if ko then follow(out, ko) end                    -- on the way out: finish leaving, then come round
    if inPlot() then
      must(go(J.x0, move.pos.y, J.z0))                -- to the plot's own shaft, on this layer
    elseif move.pos.y == outY() then
      must(go(J.x0, outY(), J.z0, (roadOrders())))    -- along the out road to the plot's shaft
    end
    must(go(move.pos.x, inY(), move.pos.z))           -- to the in road
    must(go(way[1].x, inY(), way[1].z, select(2, roadOrders())))  -- along it to the foot of the in-shaft
    k = 2
  end
  follow(way, k)
end

--- Drop everything not in `keep` into the barrel under the berth. Waits while it is full.
local function unload(keep)
  local tries = 0
  while true do
    inv.dropAllExcept(keep, "down")
    local left = 0
    for s = 1, inv.SLOTS do
      local it = turtle.getItemDetail(s)
      if it and not inv.matches(it, keep) then left = left + it.count end
    end
    if left == 0 then return true end
    tries = tries + 1
    if tries > M.cfg.patience then return false end
    report("cargo barrel full", tries == 1)
    sleep(10)
  end
end

local function fuelShort()
  local f = turtle.getFuelLevel()
  return f ~= "unlimited" and f < M.cfg.fuelTarget
end

--- Fill the tank at the berth: lava buckets from the barrel overhead first. Whatever else
-- comes out of that barrel is held and goes down with the cargo. With no lava there, the
-- coal it carries is burnt; with too little to work on, it waits a while for the barrel.
local function takeFuel()
  while fuelShort() and inv.freeSlots() > 1 do
    if not (turtle.suckUp and turtle.suckUp()) then break end
    inv.refuel(M.cfg.fuelTarget, { LAVA })
  end
  if fuelShort() then inv.refuel(M.cfg.fuelTarget) end
  local function low(limit)
    local f = turtle.getFuelLevel()
    return f ~= "unlimited" and f < limit
  end
  local waited, stuck = 0, 0
  while low(M.cfg.fuelLow + 400) and waited < M.cfg.coalWait do
    report("refuelling: nothing in the fuel barrel yet", waited == 0)
    sleep(5)
    waited = waited + 5
    if turtle.suckUp and turtle.suckUp() then inv.refuel(M.cfg.fuelTarget) end
  end
  while low(300) do
    stuck = stuck + 1
    if stuck > M.cfg.patience then error("no fuel at the base", 0) end
    report("needs fuel", stuck == 1)
    sleep(10)
    if turtle.suckUp then turtle.suckUp() end
    inv.refuel(M.cfg.fuelTarget)
  end
end

--- Of the empty buckets it now carries, one stays (for scooping); the rest go down to be refilled.
local function spareBuckets()
  local kept = false
  for s = 1, inv.SLOTS do
    local it = turtle.getItemDetail(s)
    if it and it.name == BUCKET then
      turtle.select(s)
      if kept then
        turtle.dropDown()
      else
        kept = true
        if it.count > 1 then turtle.dropDown(it.count - 1) end
      end
    end
  end
  turtle.select(1)
end

--- At the berth: unload, fill up, send the empties and the rest down.
local function service()
  if not unload(HOLD) then error("the cargo barrel stays full", 0) end
  takeFuel()
  spareBuckets()
  if not unload(KEEP) then error("the cargo barrel stays full", 0) end
end

--- From the berth (or anywhere on the way out) to the foot of the out-shaft.
local function leaveBerth()
  local way = wayOut()
  local k = onWay(way)
  if k then follow(way, k) end
end

--- To the plot's layer at height y: down its own shaft if coming from outside.
local function toPlot(y)
  if inPlot() then
    must(go(move.pos.x, y, move.pos.z))
    return
  end
  if onWay(wayOut()) then
    leaveBerth()                                      -- at the berth, or part way out
  elseif move.pos.y ~= outY() then                    -- anywhere else: come round by the berth
    toBerth()
    service()
    leaveBerth()
  end
  must(go(J.x0, outY(), J.z0, (roadOrders())))
  must(go(J.x0, y, J.z0))
end

-- ---------------------------------------------------------------- mining

--- A lava source right over or under it: scoop it up and burn it, while the tank has room.
local function scoop(dir)
  local f = turtle.getFuelLevel()
  if f == "unlimited" or f + 1000 > math.min(turtle.getFuelLimit(), M.cfg.scoopTo) then return false end
  local sfx = dir == "up" and "Up" or "Down"
  local present, b = turtle["inspect" .. sfx]()
  if not (present and type(b) == "table" and b.name == "minecraft:lava") then return false end
  if type(b.state) == "table" and (b.state.level or 0) ~= 0 then return false end   -- flowing: nothing to take
  local slot = inv.find(BUCKET)
  if not slot then return false end
  turtle.select(slot)
  local ok = turtle["place" .. sfx]()
  if ok then
    inv.refuel(M.cfg.scoopTo, { LAVA })
    scooped = scooped + 1
    if scooped == 1 or scooped % 10 == 0 then log.info("lava scooped up %d times, fuel %d", scooped, turtle.getFuelLevel()) end
  end
  turtle.select(1)
  return ok and true or false
end

local function housekeeping()
  if inv.freeSlots() <= 1 then
    inv.compact()
    if inv.freeSlots() <= 1 then return "full" end
  end
  local f = turtle.getFuelLevel()
  if f ~= "unlimited" and f < M.cfg.fuelLow + tripHome() then
    inv.refuel(M.cfg.fuelTarget)                     -- what it has dug, first
    f = turtle.getFuelLevel()
    if f < M.cfg.fuelLow + tripHome() then return "fuel" end
  end
  return nil
end

--- Dig until the plot is done ("finished"), the turtle must go to the base ("full",
-- "fuel"), or it was told to give the plot up ("abandon").
local function mine()
  local n = J.size * J.size
  while J.layer <= layerCount() do
    local y = layerY(J.layer)
    toPlot(y)
    while J.cell < n do
      if abandon then return "abandon" end
      if jumpTo then break end
      local x, z = cellPos(J.layer, J.cell + 1)
      local ok, why = go(x, y, z, nil, M.cfg.cellWaits)
      if ok then
        scoop("up")
        scoop("down")
        local _, up = move.dig("up")
        local _, down = move.dig("down")
        if up or down then log.warn("left alone at %d,%d,%d: %s", x, y, z, tostring(up or down)) end
      else
        log.warn("cell %d,%d,%d skipped: %s", x, y, z, tostring(why))
      end
      J.cell = J.cell + 1
      save()
      log.progress()
      report("mining")
      local need = housekeeping()
      if need then return need end
    end
    if jumpTo then
      -- told the layers above are dug already: carry on from the one named
      J.layer, J.cell, jumpTo = math.min(jumpTo, layerCount()), 0, nil
      save()
      log.info("plot #%d: carrying on from layer %d by order", J.index, J.layer)
    else
      J.layer, J.cell = J.layer + 1, 0
      save()
      log.info("plot #%d: layer %d of %d done", J.index, J.layer - 1, layerCount())
    end
  end
  return "finished"
end

--- A job is only usable if it says how to get to a berth.
local function hasWays(job)
  return type(job.inbound) == "table" and type(job.outbound) == "table" and #job.inbound >= 2 and #job.outbound >= 2
end

local function takeJob(job)
  J = {
    index = job.index, x0 = job.x0, z0 = job.z0, size = job.size, topY = job.topY, bottom = job.bottom,
    inbound = job.inbound, outbound = job.outbound, layer = 1, cell = 0, phase = "mine",
  }
  save()
  log.info("plot #%d at %d, %d", J.index, J.x0, J.z0)
end

--- A plot taken before the berths existed has no way home in it: ask the controller.
local function learnWays()
  local tries = 0
  while not (J.inbound and J.outbound) do
    local job = net.requestJob()
    if job and hasWays(job) then
      J.inbound, J.outbound = job.inbound, job.outbound
      J.dock, J.exit1, J.exit2 = nil, nil, nil
      save()
      local b = J.inbound[#J.inbound]
      log.info("berth at %d, %d, %d", b.x, b.y, b.z)
      return
    end
    tries = tries + 1
    if tries > M.cfg.patience then error("the controller gives no berth", 0) end
    report("waiting: asking the controller for my berth", tries == 1)
    sleep(15)
  end
end

--- The work loop. Each turn of it is one leg; `maxLegs` stops it (tests).
function M.work(maxLegs)
  local legs = 0
  while not maxLegs or legs < maxLegs do
    legs = legs + 1
    checkpoint()
    if J.index and not (J.inbound and J.outbound) then learnWays() end
    if not J.index then
      local job = net.requestJob()
      if job and hasWays(job) then
        takeJob(job)
      else
        report(job and "waiting: the controller gives no berth" or "waiting for a plot")
        sleep(20)
      end
    elseif J.phase == "leave" then
      leaveBerth()
      J.phase = "mine"
      save()
    elseif J.phase == "mine" then
      local r = mine()
      if r == "abandon" then
        abandon = false
        log.info("plot #%d given up by order", J.index)
        net.jobDone(J.index)
        J = {}
        save()
      else
        J.phase = (r == "finished") and "finish" or "dock"
        save()
        log.info("plot #%d: %s, going home", J.index, r)
      end
    elseif J.phase == "dock" or J.phase == "finish" then
      report("flying home", true)
      toBerth()
      service()
      if J.phase == "finish" then
        net.jobDone(J.index)
        log.info("plot #%d finished", J.index)
        J = {}                                        -- it waits in its berth for the next plot
      else
        J.phase = "leave"
      end
      save()
    else
      error("job file has an unknown phase: " .. tostring(J.phase), 0)
    end
  end
end

-- ---------------------------------------------------------------- starting

--- Where am I, and which way do I face? GPS is the truth; the saved position is only
-- trusted when GPS agrees with it (the facing cannot be read any other way).
local function locateSelf()
  local saved = move.load()
  for try = 1, 30 do
    local x, y, z = gps.locate(2)
    if x then
      x, y, z = math.floor(x + 0.5), math.floor(y + 0.5), math.floor(z + 0.5)
      local p = move.pos
      if saved and p.x == x and p.y == y and p.z == z then return true end
      local ok, why = move.calibrate()
      if ok then return true end
      log.warn("finding my facing: %s", tostring(why))
      -- boxed in underground: open one block ahead (never up at the base)
      if tostring(why):find("boxed in", 1, true) and J.topY and y <= J.topY + DIG_CEILING then move.dig("forward") end
    elseif saved and try >= 3 then
      log.warn("no GPS fix: trusting the saved position")
      return true
    end
    net.report({ role = "miner", state = "no GPS fix", fuel = turtle.getFuelLevel() })
    sleep(10)
  end
  error("no GPS fix", 0)
end
M.locateSelf = locateSelf

local function listener()
  while true do
    local cmd = net.nextOrder(5)
    if cmd then
      log.info("order: %s", tostring(cmd.cmd))
      M.order(cmd)
    end
  end
end

--- Load the job and settings (also used by tests before calling M.work).
function M.setup()
  log.setup({
    name = "miner",
    onCrash = function(r)
      net.report({ role = "miner", state = "error", log = { tostring(r.error):sub(1, 300) } })
    end,
  })
  move.setup({
    protect = PROTECT,
    natural = NATURAL,
    refuel = function() return inv.refuel(M.cfg.fuelLow) > 0 end,
    -- keep reporting on long trips too (report() itself spaces them out)
    onMove = function() report(lastState or "moving") end,
  })
  net.open()
  J = state.load(M.cfg.jobFile, {})
  return J
end

local function main()
  M.setup()
  net.report({ role = "miner", state = "woke up", fuel = turtle.getFuelLevel() })
  ensureTool()
  locateSelf()
  M.work()
end

function M.start()
  return log.run(function()
    if parallel then
      parallel.waitForAny(main, listener, log.watchdog(900, function(idle)
        net.report({ role = "miner", state = "stalled", log = { ("no progress for %d s"):format(idle) } })
      end))
    else
      main()
    end
  end)
end

if ... == "module" then return M end
return M.start()
