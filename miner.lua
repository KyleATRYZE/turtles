-- miner.lua : GPS quarry miner for CC:Tweaked turtles
-- Usage:  miner <size> [bottomY]
--   Place the turtle facing the area to mine, with a chest directly behind it.
--   It mines a <size> x <size> square in front of it and to its right,
--   from just below its own level down to bottomY (default -58).
--   It returns to the chest to unload, refuels from mined coal,
--   and resumes by itself after a server restart or chunk reload.

local STATE_FILE  = "miner.state"
local MIN_Y       = -58     -- lowest layer centre (digs one block below this)
local FUEL_LOW    = 3000    -- start burning mined coal below this
local FUEL_TARGET = 8000    -- burn coal until fuel reaches this
local JOB_PROTOCOL = "swarm_job"   -- talking to the factory about plots

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
local function report(state)
  lastReport = os.clock()
  lastState = state
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
    job = st and {
      home = st.home, size = st.size, bottom = st.bottom,
      layer = st.layer, layers = totalLayers, rowsDone = st.rowsDone,
      plot = st.index,
    } or nil,
    log = logLines,
  })
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
      -- on the launch pad the factory can hand some over
      if swarm and swarm.open() then
        rednet.broadcast({ type = "fuel_request", id = os.getComputerID() }, JOB_PROTOCOL)
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
local function tryMove(moveFn, detectFn, digFn, attackFn, patient)
  local stuck = 0
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
      sleep(2)
    end
  end
  return true
end

local function forward(patient)
  if tryMove(turtle.forward, turtle.detect, safeDig, turtle.attack, patient) then
    pos.x = pos.x + DIRS[heading].x
    pos.z = pos.z + DIRS[heading].z
    return true
  end
  return false
end

local function up(patient)
  if tryMove(turtle.up, turtle.detectUp, safeDigUp, turtle.attackUp, patient) then
    pos.y = pos.y + 1
    return true
  end
  return false
end

local function down(patient)
  if tryMove(turtle.down, turtle.detectDown, safeDigDown, turtle.attackDown, patient) then
    pos.y = pos.y - 1
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
-- Swarm miners have no chest of their own. Each flies between its plot and
-- the base at its own cruising height, comes down one column onto the
-- drop-off chest and leaves by a different column, so turtles never meet
-- head-on.

local function shaftXZ() return toWorld(1, 0) end

local function at(p) return pos.x == p.x and pos.y == p.y and pos.z == p.z end
local function over(p) return pos.x == p.x and pos.z == p.z end

-- Fly level to a column.
local function flyTo(x, z)
  axisMove("x", x, true)
  axisMove("z", z, true)
end

-- Moves from here to the drop-off chest.
local function dockDistance(y)
  local lf, lr = toLocal()
  local sx, sz = shaftXZ()
  return math.abs(lf - 1) + math.abs(lr) + (st.cruise - y)
    + math.abs(sx - st.dock.x) + math.abs(sz - st.dock.z)
    + (st.cruise - st.dock.y)
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

-- Drop everything into the drop-off chest below.
local function unloadDock()
  for s = 1, 16 do
    while turtle.getItemCount(s) > 0 do
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

-- Off the drop-off column, across to the exit column.
local function toExitColumn()
  if at(st.dock) then flyTo(st.exit1.x, st.exit1.z) end
  if at(st.exit1) then flyTo(st.exit2.x, st.exit2.z) end
end

-- Leave the base by the exit column.
local function leaveDock()
  toExitColumn()
  axisMove("y", st.cruise, true)
end

-- Short of fuel with no coal on board: wait on the launch pad next to the
-- factory and ask it for some.
local function fuelStop(needed)
  if fuel() >= needed then return end
  toExitColumn()
  axisMove("y", st.exit2.y - 1, true)
  while fuel() < needed do
    print("Asking the factory for fuel.")
    report("needs fuel")
    rednet.broadcast({ type = "fuel_request", id = os.getComputerID() }, JOB_PROTOCOL)
    sleep(10)
    for s = 1, 16 do
      if turtle.getItemCount(s) > 0 then
        turtle.select(s)
        while fuel() < needed and turtle.refuel(1) do end
      end
    end
    turtle.select(1)
  end
end

local function inPlot()
  local lf, lr = toLocal()
  return lf >= 1 and lf <= st.size and lr >= 0 and lr < st.size
    and pos.y <= st.home.y
end

local function onExitSide()
  return at(st.exit1) or (over(st.exit2) and pos.y >= st.exit2.y - 1)
end

-- After a restart a swarm miner may be anywhere on its route. These two get
-- it from wherever it is to the drop-off chest, or to the top of its shaft,
-- always going the right way along the one-way columns.

local function toDockFromAnywhere()
  if inPlot() then toShaftHead() end
  if over(st.dock) and pos.y >= st.dock.y then
    axisMove("y", st.dock.y, true)
    return
  end
  if onExitSide() then
    leaveDock()   -- must go up and round again
  else
    axisMove("y", st.cruise, true)
  end
  flyTo(st.dock.x, st.dock.z)
  axisMove("y", st.dock.y, true)
end

local function toShaftFromAnywhere()
  if inPlot() then return end
  local sx, sz = shaftXZ()
  if not (pos.x == sx and pos.z == sz) then
    if over(st.dock) and pos.y >= st.dock.y then
      axisMove("y", st.dock.y, true)   -- finish coming down, leave properly
      leaveDock()
    elseif onExitSide() then
      leaveDock()
    else
      axisMove("y", st.cruise, true)
    end
    flyTo(sx, sz)
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

-- Kept (one stack only) even though it is junk: the factory smelts it into
-- stone for building new turtles.
local KEEP_ONE_STACK = "minecraft:cobblestone"

local function dropJunk()
  local kept = false
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and JUNK[d.name] then
      if d.name == KEEP_ONE_STACK and not kept then
        kept = true
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
    while turtle.getItemCount(s) > 0 do
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
  fuelStop(tripFuel(st.back.y))
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

local function mineStep()
  digUpDown()
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
      fuelStop(600)
      leaveDock()
      -- step off the exit column so others can pass; wait here for the next plot
      axisMove("x", pos.x + 3, true)
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

-- Ask the factory for a plot to mine. Waits until one is offered.
local function requestJob()
  swarm.open()
  local me = os.getComputerID()
  while true do
    rednet.broadcast({ type = "need_job", id = me }, JOB_PROTOCOL)
    local deadline = os.clock() + 5
    while os.clock() < deadline do
      local _, msg = rednet.receive(JOB_PROTOCOL, 1)
      if type(msg) == "table" and msg.type == "job" and msg.forId == me then
        return msg
      end
    end
    report("waiting for a plot")
    sleep(20)
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
        st = {
          swarm = true, index = j.index,
          home = { x = j.x0 - 1, y = j.topY, z = j.z0 }, homeD = 0,
          size = j.size, bottom = j.bottom, layer = 1,
          cruise = j.cruise, dock = j.dock, exit1 = j.exit1, exit2 = j.exit2,
        }
        save()
        located = false
        print(("Plot #%d at %d, %d"):format(j.index, j.x0, j.z0))
      end
      if not located and not relocate() then return end
      located = false
      run()
      st = nil
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
      fuelStop(tripFuel(st.home.y))
      leaveDock()
      axisMove("x", pos.x + 3, true)   -- park clear of the exit column
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
