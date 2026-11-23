--- miner.lua: dig the plot the controller hands out, bring everything to the drop-off,
-- refuel, go back, and ask for the next plot when it is done.
--
-- Built only from lib/ (move, inv, state, log, net). What it knows about the base comes
-- with the job: the drop-off chest (dock), the two cells beside it (exit1, exit2), and
-- from those the two shafts. Travel is underground on two one-way roads, as before:
--
--   out road  (topY + 2):  base -> plot      down the OUT shaft, along, down the plot's shaft
--   in road   (topY + 6):  plot -> base      up the plot's shaft, along, up the IN shaft
--
--   IN shaft | dock | exit1 | exit2 (fuel pad one below) | OUT shaft        (one row, y = dock.y)
--
-- A plot is size x size columns from (x0, z0), dug in layers three blocks high from topY
-- down to bottom. Progress is saved after every cell, so a restart carries on where it was.
--
-- Rules it keeps:
--   * it never digs higher than 12 above the plot tops: up there the shafts and the dock
--     row are already open, and anything else is the factory or a road
--   * it never digs a protected block (machines, cables, chests, other turtles): it waits
--   * every wait is reported with its reason; a crash is reported, then startup restarts it
--
-- Orders (from the controller): stop, resume, newjob, reboot (rev = a commit to load), ping.

local log = require("lib.log")
local move = require("lib.move")
local inv = require("lib.inv")
local state = require("lib.state")
local net = require("lib.net")

local M = {}

M.cfg = {
  jobFile = "/.miner",
  fuelTarget = 3000,     -- fill up to this at the base
  fuelLow = 600,         -- spare kept on top of the trip home; below it, go and refuel
  reportEvery = 20,      -- seconds between routine reports
  coalWait = 120,        -- seconds to wait on the fuel pad for coal before carrying on
  patience = math.huge,  -- waits on a blocked path before a leg gives up (tests lower it)
}

-- never dropped at the dock
local KEEP = { "*pickaxe*", "advancedperipherals:*", "computercraft:*" }
-- never dug, wherever it is met
local PROTECT = {
  "^computercraft:", "^advancedperipherals:", "chest", "barrel", "shulker_box", "hopper",
  "^ae2:", "^extendedae:", "^mekanism", "^create", "^pipez:", "^ad_astra", "^industrialforegoing:",
  "^immersiveengineering:", "^simplylight:", "^functionalstorage:", "^sophisticated",
  "concrete", "glass", "spawner", "_door", "ladder", "polished_", "smooth_stone", "_slab", "_stairs", "_wall",
}
local DIG_CEILING = 12       -- no digging higher than this above the plot tops (see go)

local J = {}                 -- the job in hand (saved in cfg.jobFile); J.index nil = none
local parked, abandon, rebootWanted = false, false, false
local lastReport, lastState = -1e9, nil

-- ---------------------------------------------------------------- geometry

local function geo()
  local d, e1, e2 = J.dock, J.exit1, J.exit2
  return {
    inX = 2 * d.x - e1.x, inZ = 2 * d.z - e1.z,        -- the in-shaft: one step beyond the dock
    outX = 2 * e2.x - e1.x, outZ = 2 * e2.z - e1.z,    -- the out-shaft: one step beyond exit2
    outY = J.topY + 2, inY = J.topY + 6, padY = e2.y - 1,
  }
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

--- On the row at the base (dock, exits, pad, shaft heads)?
local function onRow()
  local g, p = geo(), move.pos
  local lo, hi = math.min(g.inX, g.outX), math.max(g.inX, g.outX)
  return p.z == J.dock.z and p.y >= g.padY and p.x >= lo and p.x <= hi
end

--- On the dock or the in-shaft side of it?
local function inSide()
  local g, p = geo(), move.pos
  if g.inX > J.dock.x then return p.x >= J.dock.x end
  return p.x <= J.dock.x
end

local function tripHome()
  local g, p = geo(), move.pos
  return math.abs(p.x - g.inX) + math.abs(p.z - g.inZ) + math.abs(g.inY - p.y) + (J.dock.y - g.inY) + 10
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
  elseif c == "ping" then lastReport = -1e9 end
end
function M.flags() return { parked = parked, abandon = abandon, reboot = rebootWanted } end

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

-- ---------------------------------------------------------------- moving

--- Go to x, y, z (x, then z, then y unless `order` says otherwise). Waits out anything that
-- can clear by itself (another turtle, a sleeping chunk, no fuel) and says why it waits.
-- Returns false + reason only for a block it will never dig, or when patience runs out.
local function go(x, y, z, order)
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
    if why:find("^undiggable") then return false, why end
    waits = waits + 1
    if waits > M.cfg.patience then return false, why end
    if why == "no fuel" then inv.refuel(M.cfg.fuelLow) end
    if waits == 1 or waits % 12 == 0 then log.warn("on the way to %d,%d,%d: %s", x, y, z, why) end
    report("waiting: " .. why, waits == 1)
    sleep(why == "unloaded" and 30 or 5)
  end
end

local function must(ok, why)
  if not ok then error("cannot get there: " .. tostring(why), 0) end
end

--- From anywhere to the dock, always the right way along the one-way roads.
local function toDock()
  local g, d = geo(), J.dock
  local p = move.pos
  local inShaftAbove = p.x == g.inX and p.z == g.inZ and p.y >= g.inY
  if not ((onRow() and inSide()) or inShaftAbove) then
    if onRow() or (p.x == g.outX and p.z == g.outZ and p.y > g.outY) then
      -- on the way out: finish leaving, then come round
      must(go(g.outX, p.y, g.outZ))
      must(go(g.outX, g.outY, g.outZ))
    end
    if inPlot() then
      must(go(J.x0, move.pos.y, J.z0))              -- to the plot's own shaft, on this layer
    elseif move.pos.y == g.outY then
      must(go(J.x0, g.outY, J.z0))                  -- along the out road to the plot's shaft
    end
    must(go(move.pos.x, g.inY, move.pos.z))         -- to the in road
    must(go(g.inX, g.inY, g.inZ))                   -- along it
  end
  must(go(move.pos.x, d.y, move.pos.z))             -- up the in-shaft (or already on the row)
  must(go(d.x, d.y, d.z))
end

--- Drop everything but tools into the chest under the dock. Waits while the chest is full.
local function unload()
  inv.refuel(M.cfg.fuelTarget)                      -- burn mined coal first: it is free
  local tries = 0
  while true do
    inv.dropAllExcept(KEEP, "down")
    local left = 0
    for s = 1, inv.SLOTS do
      local it = turtle.getItemDetail(s)
      if it and not inv.matches(it, KEEP) then left = left + it.count end
    end
    if left == 0 then return true end
    tries = tries + 1
    if tries > M.cfg.patience then return false end
    report("drop-off full", tries == 1)
    sleep(10)
  end
end

local function fuelShort()
  local f = turtle.getFuelLevel()
  return f ~= "unlimited" and f < M.cfg.fuelTarget
end

--- From the dock: past the exits, onto the fuel pad if fuel is wanted, down the out-shaft.
local function leaveDock()
  local g, e2 = geo(), J.exit2
  local toward = (g.outX < J.dock.x) and -1 or 1
  if (move.pos.x - e2.x) * toward < 0 then          -- still on the dock side of exit2
    must(go(e2.x, e2.y, e2.z, "yxz"))
  end
  if fuelShort() and move.pos.x == e2.x and move.pos.z == e2.z then
    local onPad = move.pos.y == g.padY               -- (a restart can find it sitting there)
    if not onPad then
      local present, below = turtle.inspectDown()
      local taken = present and type(below) == "table" and tostring(below.name):find("turtle", 1, true)
      onPad = not taken and go(e2.x, g.padY, e2.z)
    end
    if onPad then
      -- the ME export bus under the pad pushes coal into whoever sits here
      local waited = 0
      while fuelShort() and waited < M.cfg.coalWait do
        inv.refuel(M.cfg.fuelTarget)
        if not fuelShort() then break end
        report("refuelling", waited == 0)
        sleep(2)
        waited = waited + 2
      end
    end
  end
  local stuck = 0
  while turtle.getFuelLevel() ~= "unlimited" and turtle.getFuelLevel() < 300 do
    stuck = stuck + 1
    if stuck > M.cfg.patience then error("no fuel at the base", 0) end
    report("needs fuel", stuck == 1)
    sleep(10)
    inv.refuel(M.cfg.fuelTarget)
  end
  must(go(g.outX, move.pos.y, g.outZ))
  must(go(g.outX, g.outY, g.outZ))
end

--- To the plot's layer at height y: down its own shaft if coming from outside.
local function toPlot(y)
  local g = geo()
  if inPlot() then
    must(go(move.pos.x, y, move.pos.z))
    return
  end
  if move.pos.y ~= g.outY then                       -- not on the out road: come round by the base
    toDock()
    unload()
    leaveDock()
  end
  must(go(J.x0, g.outY, J.z0))
  must(go(J.x0, y, J.z0))
end

-- ---------------------------------------------------------------- mining

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
      local x, z = cellPos(J.layer, J.cell + 1)
      local ok, why = go(x, y, z)
      if ok then
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
    J.layer, J.cell = J.layer + 1, 0
    save()
    log.info("plot #%d: layer %d of %d done", J.index, J.layer - 1, layerCount())
  end
  return "finished"
end

local function takeJob(job)
  J = {
    index = job.index, x0 = job.x0, z0 = job.z0, size = job.size, topY = job.topY, bottom = job.bottom,
    dock = job.dock, exit1 = job.exit1, exit2 = job.exit2, layer = 1, cell = 0, phase = "mine",
  }
  save()
  log.info("plot #%d at %d, %d", J.index, J.x0, J.z0)
end

--- The work loop. Each turn of it is one leg; `maxLegs` stops it (tests).
function M.work(maxLegs)
  local legs = 0
  while not maxLegs or legs < maxLegs do
    legs = legs + 1
    checkpoint()
    if J.phase == "leave" then
      if onRow() then leaveDock() end
      if J.idle then
        -- nothing to dig: wait in a pocket off the out road, clear of the shaft
        local g = geo()
        if move.pos.y == g.outY then go(g.outX, g.outY, g.outZ + 2 + os.getComputerID() % 5) end
        J = {}
      else
        J.phase = "mine"
      end
      save()
    elseif not J.index then
      local job = net.requestJob()
      if job then
        takeJob(job)
      else
        report("waiting for a plot")
        sleep(20)
      end
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
        log.info("plot #%d: %s, going to the base", J.index, r)
      end
    elseif J.phase == "dock" or J.phase == "finish" then
      report("flying to base", true)
      toDock()
      if not unload() then error("the drop-off chest stays full", 0) end
      if J.phase == "finish" then
        net.jobDone(J.index)
        log.info("plot #%d finished", J.index)
        local nextJob = net.requestJob()
        if nextJob then
          takeJob(nextJob)
          J.phase = "leave"
        else
          J = { dock = J.dock, exit1 = J.exit1, exit2 = J.exit2, topY = J.topY, phase = "leave", idle = true }
        end
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
