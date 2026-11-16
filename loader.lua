-- loader.lua : ChunkNorris, a turtle with a Chunk Controller (Advanced
-- Peripherals). The controller keeps the chunk the turtle is in loaded, so
-- wherever it hovers, turtles there keep running even with nobody nearby.
--
-- It flies high above everything (it has no pickaxe and never digs), and
-- does one of three jobs, set by remote order:
--   park                 sit at the base and keep it loaded (the default)
--   escort who=<name>    fly to that turtle and stay above it until it is
--                        back near the base, then park again
--   goto x=.. z=..       hover over a spot until told otherwise
local okSwarm, swarm = pcall(require, "swarm")
if not okSwarm then swarm = nil end

local NAME       = "ChunkNorris"
local STATE_FILE = "loader.state"
local BASE_FILE  = ".base"
local CRUISE     = 150    -- flying height: above every hill and tree
local NEAR_BASE  = 32     -- an escorted turtle closer than this is safe

local DIRS = {
  [0] = { x = 1, z = 0 }, [1] = { x = 0, z = 1 },
  [2] = { x = -1, z = 0 }, [3] = { x = 0, z = -1 },
}
local pos, heading = { x = 0, y = 0, z = 0 }, 0
local st, base
local lastState = "starting"

local logLines = {}
local rawPrint = print
local function print(...)
  rawPrint(...)
  local parts = table.pack(...)
  for i = 1, parts.n do parts[i] = tostring(parts[i]) end
  logLines[#logLines + 1] = table.concat(parts, " ")
  while #logLines > 6 do table.remove(logLines, 1) end
end

local function report(state)
  lastState = state or lastState
  if not swarm then return end
  local f = turtle.getFuelLevel()
  pcall(swarm.report, {
    role = "loader", state = lastState,
    pos = { x = pos.x, y = pos.y, z = pos.z },
    fuel = f == "unlimited" and -1 or f,
    job = st and { mode = st.mode, who = st.who, x = st.x, z = st.z } or nil,
    log = logLines,
  })
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

---------------------------------------------------------------- fuel

local function fuel()
  local f = turtle.getFuelLevel()
  if f == "unlimited" then return math.huge end
  return f
end

local function refuel(target)
  for s = 1, 16 do
    if fuel() >= target then break end
    if turtle.getItemCount(s) > 0 then
      turtle.select(s)
      while fuel() < target and turtle.refuel(1) do end
    end
  end
  turtle.select(1)
end

---------------------------------------------------------------- moving (never digs)

local function face(d)
  while heading ~= d do
    turtle.turnRight()
    heading = (heading + 1) % 4
  end
end

local function move(dir)
  if fuel() < 1 then refuel(500) end
  for _ = 1, 40 do
    local ok
    if dir == "u" then ok = turtle.up()
    elseif dir == "d" then ok = turtle.down()
    else ok = turtle.forward() end
    if ok then
      if dir == "u" then pos.y = pos.y + 1
      elseif dir == "d" then pos.y = pos.y - 1
      else
        pos.x, pos.z = pos.x + DIRS[heading].x, pos.z + DIRS[heading].z
      end
      return true
    end
    local detect = dir == "u" and turtle.detectUp or dir == "d" and turtle.detectDown
      or turtle.detect
    if detect() then return false end        -- a block: never dig it
    sleep(0.5)                               -- a mob, a bird, a player: wait
  end
  return false
end

local function locate()
  for _ = 1, 20 do
    local x, y, z = gps.locate(2)
    if x then return math.floor(x + 0.5), math.floor(y + 0.5), math.floor(z + 0.5) end
    sleep(3)
  end
  error("No GPS signal.", 0)
end

local function relocate()
  pos.x, pos.y, pos.z = locate()
  -- which way are we facing? step somewhere and back
  for turns = 0, 3 do
    if turtle.forward() then
      local x2, _, z2 = locate()
      turtle.back()
      local d
      if x2 > pos.x then d = 0 elseif x2 < pos.x then d = 2
      elseif z2 > pos.z then d = 1 else d = 3 end
      heading = d
      return
    end
    turtle.turnRight()
    heading = (heading + 1) % 4
  end
  if turtle.up() then
    pos.y = pos.y + 1
    return relocate()
  end
  error("Boxed in: I cannot move to find my way.", 0)
end

-- Up to flying height, sidestepping anything overhead.
local function climb()
  while pos.y < CRUISE do
    if not move("u") then
      local moved = false
      for h = 0, 3 do
        face(h)
        if move("f") then moved = true break end
      end
      if not moved then return false end
    end
  end
  return true
end

-- Fly to a column at flying height.
local function flyTo(x, z)
  if not climb() then return false end
  for _, axis in ipairs({ "x", "z" }) do
    local target = axis == "x" and x or z
    while pos[axis] ~= target do
      if axis == "x" then face(target > pos.x and 0 or 2) else face(target > pos.z and 1 or 3) end
      if not move("f") then
        if not move("u") then return false end   -- something up here: go higher
      end
    end
  end
  return true
end

-- Down onto whatever is below.
local function land()
  while move("d") do end
end

---------------------------------------------------------------- jobs

-- Where the other turtles are, from their status broadcasts.
local seen = {}
local function listen()
  if not swarm then while true do sleep(60) end end
  swarm.open()
  while true do
    local _, msg = rednet.receive(swarm.PROTOCOL)
    if type(msg) == "table" and type(msg.label) == "string" and type(msg.pos) == "table"
      and tonumber(msg.pos.x) and tonumber(msg.pos.z) then
      seen[msg.label:lower()] = { x = msg.pos.x, z = msg.pos.z, y = msg.pos.y, at = os.clock() }
    end
    -- the factory's reports say where the base is
    if type(msg) == "table" and msg.role == "factory" and type(msg.base) == "table"
      and type(msg.base.f) == "table" and not base then
      base = msg.base
      local h = fs.open(BASE_FILE, "w")
      h.write(textutils.serialize(base))
      h.close()
    end
  end
end

local function chunkOf(x, z) return math.floor(x / 16), math.floor(z / 16) end

local function park()
  for _ = 1, 20 do
    if st.park or base then break end
    sleep(3)                                -- the factory reports every so often
  end
  -- just east of the hut, in the factory's chunk, clear of the holes in
  -- the roof that the builder uses and of its paths to the building site
  local p = st.park or (base and { x = base.f.x + 4, z = base.f.z - 1 })
  if not p then
    report("parked")
    return
  end
  print("Parking at the base.")
  report("flying home")
  if flyTo(p.x, p.z) then
    land()
    print("Parked. Keeping the base loaded.")
  end
  report("parked")
end

local function work()
  if os.getComputerLabel() ~= NAME then os.setComputerLabel(NAME) end
  refuel(1000)
  while fuel() < 100 do
    print("I need fuel: put some coal in me.")
    report("needs fuel")
    sleep(10)
    refuel(1000)
  end
  relocate()
  st = loadTable(STATE_FILE) or { mode = "park" }
  base = loadTable(BASE_FILE)
  if st.mode == "escort" and st.who then
    print("Escorting " .. st.who .. ".")
    local wait = 0
    while true do
      local t = seen[st.who:lower()]
      if t then
        local cx, cz = chunkOf(t.x, t.z)
        local mx, mz = chunkOf(pos.x, pos.z)
        if cx ~= mx or cz ~= mz or pos.y < CRUISE then
          report("escorting")
          flyTo(t.x, t.z)                       -- stay in its chunk
        end
        if base and math.abs(t.x - base.f.x) <= NEAR_BASE and math.abs(t.z - base.f.z) <= NEAR_BASE then
          print(st.who .. " is back near the base.")
          st.mode, st.who = "park", nil
          save()
          break
        end
      elseif st.x and st.z then
        report("looking for " .. st.who)
        flyTo(st.x, st.z)                       -- its last known spot
      else
        wait = wait + 1
        if wait > 60 then
          print("I have not heard from " .. st.who .. ".")
          report("cannot find " .. st.who)
        end
      end
      sleep(3)
    end
  end
  if st.mode == "goto" and st.x and st.z then
    print(("Hovering over %d, %d."):format(st.x, st.z))
    report("flying")
    flyTo(st.x, st.z)
    report("hovering")
    while true do sleep(60) report() end
  end
  park()
  while true do sleep(60) report() end
end

local function guarded()
  local ok, err = pcall(work)
  if not ok then
    if err == "Terminated" then error(err, 0) end
    print("ERROR: " .. tostring(err))
    report("error")
    while true do sleep(60) report("error") end
  end
end

---------------------------------------------------------------- start

if not turtle then
  print("This program only runs on a turtle.")
  return
end
do
  local h = fs.open(".role", "w")
  h.write("loader")
  h.close()
end

local function task() parallel.waitForAny(guarded, listen) end
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
  if cmd then
    st = loadTable(STATE_FILE) or { mode = "park" }
    if cmd.cmd == "reboot" then
      swarm.pinVersion(cmd)
      report("rebooting")
      os.reboot()
    elseif cmd.cmd == "escort" and type(cmd.who) == "string" then
      st.mode, st.who = "escort", cmd.who
      st.x, st.z = tonumber(cmd.x), tonumber(cmd.z)
    elseif cmd.cmd == "goto" and tonumber(cmd.x) and tonumber(cmd.z) then
      st.mode, st.x, st.z = "goto", math.floor(tonumber(cmd.x)), math.floor(tonumber(cmd.z))
    elseif cmd.cmd == "park" then
      st.mode, st.who = "park", nil
      if tonumber(cmd.x) and tonumber(cmd.z) then
        st.park = { x = math.floor(tonumber(cmd.x)), z = math.floor(tonumber(cmd.z)) }
      end
    end
    save()
  end
end
