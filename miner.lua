-- miner.lua : GPS quarry miner for CC:Tweaked turtles
-- Usage:  miner <size> [bottomY]
--   Place the turtle facing the area to mine, with a chest directly behind it.
--   It mines a <size> x <size> square in front of it and to its right,
--   from just below its own level down to bottomY (default -58).
--   It returns to the chest to unload, refuels from mined coal,
--   and resumes by itself after a server restart or chunk reload.

local STATE_FILE  = "miner.state"
local MIN_Y       = -58     -- lowest layer centre (digs one block below this)
local FUEL_LOW    = 1000    -- start burning mined coal below this
local FUEL_TARGET = 5000    -- burn coal until fuel reaches this

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

-- Normal route: across to the shaft in front of home, then straight up.
local function tryHomeShaft()
  return goLocal(1, 0, pos.y, "rf", false)
    and axisMove("y", st.home.y, false)
    and goLocal(0, 0, st.home.y, "f", false)
end

-- Backup route: straight up first, then across the top layer.
local function tryHomeTop()
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
    and goLocal(0, 0, st.home.y, "f", false)
end

local function goHome()
  while not atHome() do
    if tryHomeShaft() or tryHomeTop() then return end
    print("Path home is blocked, retrying...")
    report("path blocked")
    sleep(5)
  end
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

local function distHome()
  return math.abs(pos.x - st.home.x) + math.abs(pos.y - st.home.y)
    + math.abs(pos.z - st.home.z)
end

local function tripFuel(y)
  return 2 * (math.abs(st.home.y - y) + st.size * 2) + 300
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

local function homeTrip(reason)
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

local function jobTask()
  guarded(function()
    if not located and not relocate() then return end
    located = false
    run()
    st = nil
  end)
end

-- Go home, unload and wait there. The job is kept for a later "resume".
local function homeTask()
  guarded(function()
    if not relocate() then return end
    print("Ordered home.")
    report("going home")
    goHome()
    unload()
    face(st.homeD)
    print("Parked at home.")
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
      task = idleTask
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
        idleState = "idle"
        task = idleTask
      end
    end
  end
end

main({ ... })
