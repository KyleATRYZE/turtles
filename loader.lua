-- loader.lua : Ghastly, a turtle with a Chunk Controller (Advanced
-- Peripherals). The controller keeps the chunk the turtle is in loaded, so
-- wherever it hovers, turtles there keep running even with nobody nearby.
--
-- It flies high above everything (it has no pickaxe and never digs), and
-- does one of these jobs:
--   (by itself)          parked at the base it asks the factory, every
--                        minute, whether a turtle working far away needs
--                        company; the factory sends it out with one (never
--                        the last loader at the base), and it comes back
--                        when that turtle parks, comes home or goes quiet
--   park                 sit at the base and keep it loaded, and stay
--                        there (auto=1: stay only until wanted elsewhere)
--   auto                 back to pairing up by itself
--   escort who=<name>    fly to that turtle and stay above it until it is
--                        back near the base, then park again
--   escort who=.. stay=1 the same, but keep watching: go out with it again
--                        every time it leaves
--   goto x=.. z=..       hover over a spot until told otherwise
--   search who=<name> path=x:z;x:z;...
--                        a turtle has gone quiet, frozen in a chunk nobody is
--                        keeping loaded: fly along the path a chunk at a time,
--                        waiting at each, until it is heard from again; then
--                        stay with it (escort, stay)
local okSwarm, swarm = pcall(require, "swarm")
if not okSwarm then swarm = nil end

local NAME       = "Ghastly"
local STATE_FILE = "loader.state"
local BASE_FILE  = ".base"
local CRUISE     = 150    -- flying height: above every hill and tree
local NEAR_BASE  = 32     -- an escorted turtle closer than this is safe
local JOB_PROTOCOL = "swarm_job"
-- What a name is filed under: the same for a turtle's old name and its new
-- one (the swarm was renamed; see swarm.lua), in any case. A turtle I am
-- with keeps my company when it takes its new name.
local function nameKey(name)
  if swarm and swarm.nameKey then return swarm.nameKey(name) end
  return tostring(name):lower()
end
local function newName(name)
  if swarm and swarm.newName then return swarm.newName(name) end
  return name
end
local GIVE_UP    = 600    -- seconds over a silent turtle before going home (sent out by the factory)
-- states in which a turtle is not working: it needs no company
local RESTING = { done = true, parked = true, idle = true, stopped = true, paused = true,
  ["waiting for a plot"] = true, ["stopped by player"] = true }

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
    job = st and { mode = st.mode, who = st.who, x = st.x, z = st.z,
      auto = st.auto, hold = st.hold } or nil,
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

-- Up to flying height (or to h), sidestepping anything overhead.
local function climb(h)
  h = h or CRUISE
  while pos.y < h do
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

-- Fly to a column at flying height (or at height h: a short hop near the base).
local function flyTo(x, z, h)
  if not climb(h) then return false end
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
      -- (0, 0 = it does not know where it is: keep what we had)
      local old = seen[nameKey(msg.label)]
      local x, y, z = msg.pos.x, msg.pos.y, msg.pos.z
      if x == 0 and z == 0 and old then x, y, z = old.x, old.y, old.z end
      if not (x == 0 and z == 0) then
        seen[nameKey(msg.label)] = { x = x, z = z, y = y, at = os.clock(), state = tostring(msg.state) }
      end
    end
    -- the factory's reports say where the base is
    if type(msg) == "table" and msg.role == "factory" and type(msg.base) == "table"
      and type(msg.base.f) == "table" and not (base and base.pad) then
      base = msg.base
      local h = fs.open(BASE_FILE, "w")
      h.write(textutils.serialize(base))
      h.close()
    end
  end
end

local function chunkOf(x, z) return math.floor(x / 16), math.floor(z / 16) end

-- Fuel: down the hole onto the launch pad beside the factory, ask it for
-- coal as the miners do, burn it, and back up. (A loader used to sit and
-- wait for somebody to put coal in it.)
local LOW_FUEL, GOOD_FUEL = 600, 1500
local HOP_UP = 14          -- a short hop to the pad flies this far above the factory, not at flying height
local lastFeedAsk = -10000
local lastPadFail = -10000  -- when the pad was last found taken (not tried again for five minutes)

local function hasPad() return base and type(base.pad) == "table" end

-- Moves to the pad the usual way (up to flying height, across, down), and by
-- a short hop just over the base (for a loader parked there and nearly dry).
local function tripHigh()
  return math.abs(pos.x - base.pad.x) + math.abs(pos.z - base.pad.z)
    + math.max(0, CRUISE - pos.y) + (CRUISE - base.pad.y) + 12
end
-- (a rebase order can set base.hopUp: over the roof of a building the pad is in)
local function hopUp() return tonumber(base and base.hopUp) or HOP_UP end
local function hopHeight() return math.max(base.f.y, base.pad.y) + hopUp() end
local function tripLow()
  local h = hopHeight()
  return math.abs(pos.x - base.pad.x) + math.abs(pos.z - base.pad.z)
    + math.max(0, h - pos.y) + (math.max(h, pos.y) - base.pad.y) + 8
end

-- Too low to fly anywhere useful: say so, and ask for fuel to be brought
-- (the factory sends a builder's mate that is doing nothing; it drops the
-- coal in from above). Asked every five minutes until some arrives.
local function askFeed()
  refuel(GOOD_FUEL)                           -- (anything already put in me)
  if fuel() >= LOW_FUEL then return false end
  if os.clock() - lastFeedAsk < 300 then return true end
  lastFeedAsk = os.clock()
  print("Too little fuel to fetch my own (" .. tostring(fuel()) .. "). Asking for some to be brought.")
  report("needs fuel")
  rednet.broadcast({ type = "feed_request", id = os.getComputerID(), label = os.getComputerLabel(),
    x = pos.x, y = pos.y, z = pos.z, fuel = fuel() }, JOB_PROTOCOL)
  return true
end

-- Fuel to get from a column home to the pad, and whether there is enough
-- on board to fly out to a column and still get home from it.
local function homeFrom(x, z)
  return math.abs(x - base.pad.x) + math.abs(z - base.pad.z) + (CRUISE - base.pad.y) + 12
end
local function canReach(x, z)
  if not hasPad() then return true end
  return fuel() >= math.abs(x - pos.x) + math.abs(z - pos.z) + math.max(0, CRUISE - pos.y)
    + homeFrom(x, z) + 150
end

-- Fetch fuel from the pad when low (always, with force), up to want.
-- Returns true if it went. With too little even for that trip, asks for a
-- feed and returns false: stay put.
local function fuelUp(want, force)
  if not hasPad() then return false end
  -- the pads are on the drone lane inside the factory (base.lane): no way
  -- down to them from the sky; ask for a feed instead (rack 2 is for later)
  if base.lane then
    refuel(math.max(GOOD_FUEL, want or 0))
    if fuel() < LOW_FUEL then askFeed() end
    return false
  end
  want = math.max(GOOD_FUEL, want or 0)
  refuel(want)
  if force then
    if fuel() >= want then return false end
  elseif fuel() >= LOW_FUEL then
    return false
  end
  if os.clock() - lastPadFail < 300 then
    if fuel() < LOW_FUEL then askFeed() end
    return false
  end
  local low = false
  if fuel() < tripHigh() then
    -- (enough to get down onto the pad is enough: the coal is there)
    local near = math.abs(pos.x - base.pad.x) <= 40 and math.abs(pos.z - base.pad.z) <= 40
    if near and pos.y <= hopHeight() + 4 and fuel() >= tripLow() then
      low = true
    else
      askFeed()
      return false
    end
  end
  print("Low on fuel. Down to the launch pad for coal.")
  report("fetching fuel")
  if not flyTo(base.pad.x, base.pad.z, low and hopHeight() or nil) then return false end
  local blocked = 0
  while pos.y > base.pad.y do
    if not move("d") then
      -- somebody is on the pad: give them a minute
      blocked = blocked + 1
      if blocked > 6 then break end
      sleep(10)
    end
  end
  if pos.y ~= base.pad.y then
    print("The launch pad is taken.")
    lastPadFail = os.clock()
  else
    for try = 1, 72 do                 -- (the factory may be busy: wait longer while really low)
      if fuel() >= want or (try > 24 and fuel() >= LOW_FUEL) then break end
      rednet.broadcast({ type = "fuel_request", id = os.getComputerID() }, JOB_PROTOCOL)
      sleep(5)
      refuel(want)
    end
    if fuel() < LOW_FUEL then lastPadFail = os.clock() end   -- (nothing to be had: not straight back down)
  end
  print("Fuel: " .. tostring(fuel()) .. ".")
  -- (off the pad, and out of the air above it, whatever happened: others
  -- need it. Still nearly dry: a short way up, and ask for some to be brought)
  if fuel() >= LOW_FUEL then
    climb()
  else
    climb(hopHeight())
    askFeed()
  end
  return true
end

-- Where to park: just east of the hut, in the factory's chunk, clear of the
-- holes in the roof that the builder uses and of its paths to the building
-- site.
local function parkSpot()
  -- each loader its own spot (12 spots, two apart): all parking on one
  -- column stacked them up over the pad's approach and jammed the base
  if st.park or not base then return st.park end
  local i = (st.parkSlot or os.getComputerID()) % 12
  return { x = base.f.x + 4 + (i % 4) * 2, z = base.f.z - 1 - math.floor(i / 4) * 2 }
end

-- True once landed on the parking spot (or with nowhere known to park).
local function park()
  for _ = 1, 20 do
    if st.park or base then break end
    sleep(3)                                -- the factory reports every so often
  end
  local p = parkSpot()
  if not p then
    report("parked")
    return true
  end
  fuelUp()
  local dist = math.abs(pos.x - p.x) + math.abs(pos.z - p.z)
  local onTurtle = false
  do
    local ok, below = turtle.inspectDown()
    onTurtle = ok and below.name:find("computercraft:turtle", 1, true) ~= nil and not st.park
  end
  if dist == 0 and pos.y < CRUISE and not onTurtle then
    report("parked")                        -- (already there, landed: no need to go up and down again)
    return true
  end
  -- nearly dry: a short hop over the base, not a trip up to flying height
  -- and down again; with too little even for that, stay put
  local function cost(h) return math.max(0, h - pos.y) + dist + math.max(0, h - base.f.y) + 4 end
  local h
  if base and fuel() < cost(CRUISE) then
    h = math.max(pos.y, hasPad() and hopHeight() or (base.f.y + hopUp()))
    if fuel() < cost(h) then
      print("Too little fuel to fly to the parking spot.")
      report("needs fuel")
      return false
    end
  end
  print("Parking at the base.")
  report("flying home")
  if flyTo(p.x, p.z, h) then
    land()
    -- landed on another turtle (two loaders given one spot): take the next
    -- spot along, at most once round the twelve
    local ok, below = turtle.inspectDown()
    if ok and below.name:find("computercraft:turtle", 1, true) and not st.park
      and (st.parkTries or 0) < 12 then
      st.parkSlot = ((st.parkSlot or os.getComputerID()) + 1) % 12
      st.parkTries = (st.parkTries or 0) + 1
      save()
      print("Someone is parked here: the next spot along.")
      return park()
    end
    st.parkTries = 0
    save()
    print("Parked. Keeping the base loaded.")
  end
  report("parked")
  return true
end

-- Parked: keep an eye on the fuel, and (unless told to stay put) ask the
-- factory every minute whether a turtle working far away needs company. The
-- factory answers with an order (escort, auto), and never sends the last
-- loader away from the base.
local function parkedLoop(parked)
  while true do
    sleep(60)
    if fuel() < LOW_FUEL then
      if fuelUp() then parked = false end   -- (went to the pad: back to the parking spot)
    end
    if not parked then parked = park() end  -- (nearly dry, park makes it a short hop, or stays put)
    if fuel() < LOW_FUEL then
      report("needs fuel")
    else
      report("parked")
      if parked and not st.hold then
        rednet.broadcast({ type = "escort_request", id = os.getComputerID(),
          label = os.getComputerLabel(), gaveUp = st.gaveUp }, JOB_PROTOCOL)
      end
    end
  end
end

local function work()
  -- (the factory names the loaders it builds; the first one was made by hand)
  local label = os.getComputerLabel()
  if not label or label == "" or label:lower():match("^loader") or label:lower():match("^miner") then
    os.setComputerLabel(NAME)
  end
  refuel(1000)
  while fuel() < 20 do                 -- (a few moves are needed just to find which way I face)
    -- say where we are (GPS needs no fuel) so coal can be brought here, and
    -- ask for it: a builder's mate with nothing to do brings some
    local x, y, z = gps.locate(2)
    if x then pos.x, pos.y, pos.z = math.floor(x + 0.5), math.floor(y + 0.5), math.floor(z + 0.5) end
    print("I need fuel: put some coal in me.")
    report("needs fuel")
    if x and os.clock() - lastFeedAsk >= 300 then
      lastFeedAsk = os.clock()
      rednet.broadcast({ type = "feed_request", id = os.getComputerID(), label = os.getComputerLabel(),
        x = pos.x, y = pos.y, z = pos.z, fuel = fuel() }, JOB_PROTOCOL)
    end
    sleep(10)
    refuel(1000)
  end
  relocate()
  st = loadTable(STATE_FILE) or { mode = "park" }
  base = loadTable(BASE_FILE)
  if st.mode == "escort" and st.who then
    print("Escorting " .. st.who .. ".")
    local wait = 0
    local t0 = os.clock()
    local arrived               -- when I first got over the turtle (or its last known spot)
    local shortSaid
    -- Fly out to a column, if there is fuel to get there and home again;
    -- if not, fetch some first. False: not enough to be had just now.
    local function goOut(x, z)
      if not canReach(x, z) then
        fuelUp(2 * homeFrom(x, z) + 400, true)
        if not canReach(x, z) then
          if not shortSaid then
            print("Not enough fuel to go out to " .. st.who .. " and back.")
            shortSaid = true
          end
          report("needs fuel")
          return false
        end
      end
      shortSaid = nil
      return flyTo(x, z)
    end
    while true do
      local t = seen[nameKey(st.who)]
      -- sent out by the factory: home again when the turtle stops work, or
      -- has said nothing for ten minutes with me over the spot (it is off,
      -- or not where it was: the factory will not offer it again for a while)
      if st.auto then
        local done
        if t and t.at > t0 and RESTING[t.state] then
          done = st.who .. " has stopped work (" .. t.state .. ")."
        elseif arrived and os.clock() - math.max(arrived, t and t.at or 0) > GIVE_UP then
          done = "Nothing from " .. st.who .. " for ten minutes."
          st.gaveUp = st.who
        end
        if done then
          print(done)
          st.mode, st.who, st.auto, st.x, st.z = "park", nil, nil, nil, nil
          save()
          break
        end
      end
      if t then
        local cx, cz = chunkOf(t.x, t.z)
        local mx, mz = chunkOf(pos.x, pos.z)
        local nearBase = base and math.abs(t.x - base.f.x) <= NEAR_BASE and math.abs(t.z - base.f.z) <= NEAR_BASE
        if nearBase and not st.stay then
          print(st.who .. " is back near the base.")
          st.mode, st.who, st.auto, st.x, st.z = "park", nil, nil, nil, nil
          st.gaveUp = nil
          save()
          break
        end
        if cx ~= mx or cz ~= mz or pos.y < CRUISE then
          report("escorting")
          if goOut(t.x, t.z) then arrived = arrived or os.clock() end   -- stay in its chunk
        else
          arrived = arrived or os.clock()
        end
        if nearBase and st.stay then fuelUp() end
      elseif st.x and st.z then
        report("looking for " .. st.who)
        if goOut(st.x, st.z) then arrived = arrived or os.clock() end   -- its last known spot
      else
        wait = wait + 1
        if wait > 60 then
          print("I have not heard from " .. st.who .. ".")
          report("cannot find " .. st.who)
          arrived = arrived or os.clock()
        end
      end
      sleep(3)
    end
  end
  if st.mode == "search" and st.who and st.path then
    print("Searching for " .. st.who .. ".")
    local t0 = os.clock()
    local function heard()
      local t = seen[nameKey(st.who)]
      return t and t.at > t0
    end
    -- (a turtle that wakes has to start up, and maybe fetch new programs,
    -- before it says anything: dwell = seconds to wait over each chunk)
    local function listenHere()
      for _ = 1, math.ceil((tonumber(st.dwell) or 27) / 3) do
        if heard() then return true end
        sleep(3)
      end
      return heard()
    end
    local found = listenHere()
    for px, pz in st.path:gmatch("(-?%d+):(-?%d+)") do
      local x, z = tonumber(px), tonumber(pz)
      while not found and (pos.x ~= x or pos.z ~= z) do
        -- one chunk nearer, then wait for it to wake up and say something
        local hx = pos.x + math.max(-16, math.min(16, x - pos.x))
        local hz = pos.x ~= x and pos.z or (pos.z + math.max(-16, math.min(16, z - pos.z)))
        report("searching for " .. st.who)
        if not flyTo(hx, hz) then break end
        found = listenHere()
      end
      if found then break end
    end
    if found then
      print("Found " .. st.who .. ". Staying with it.")
    else
      print("No sign of " .. st.who .. " along the path.")
    end
    st.mode, st.stay, st.path = "escort", true, nil
    local t = seen[nameKey(st.who)]
    if t then st.x, st.z = t.x, t.z end
    save()
    return work()
  end
  if st.mode == "goto" and st.x and st.z then
    print(("Hovering over %d, %d."):format(st.x, st.z))
    report("flying")
    flyTo(st.x, st.z)
    report("hovering")
    while true do
      sleep(60)
      if fuel() < LOW_FUEL and fuelUp() then flyTo(st.x, st.z) end
      report(fuel() < LOW_FUEL and "needs fuel" or "hovering")
    end
  end
  parkedLoop(park())
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
if swarm and swarm.hello then pcall(swarm.hello, "loader") end   -- awake, and here

local function task() parallel.waitForAny(guarded, listen) end
-- (an order written by hand carries numbers and words: auto=0 is "no")
local function yes(v)
  return v ~= nil and v ~= false and v ~= 0 and v ~= "0" and v ~= "false" and v ~= "off"
end
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
      st.mode, st.who = "escort", newName(cmd.who)
      st.x, st.z = tonumber(cmd.x), tonumber(cmd.z)
      st.stay = cmd.stay and true or nil
      -- (auto: sent by the factory, to come home by itself. An order written
      -- by hand has no auto, and holds until the turtle is near the base.)
      st.auto = yes(cmd.auto) and not st.stay and true or nil
      st.hold = nil
    elseif cmd.cmd == "search" and type(cmd.who) == "string" and type(cmd.path) == "string" then
      st.mode, st.who, st.path = "search", newName(cmd.who), cmd.path
      st.dwell = tonumber(cmd.dwell)
    elseif cmd.cmd == "goto" and tonumber(cmd.x) and tonumber(cmd.z) then
      st.mode, st.x, st.z = "goto", math.floor(tonumber(cmd.x)), math.floor(tonumber(cmd.z))
    elseif cmd.cmd == "park" then
      -- stay at the base until told otherwise (auto=1: until wanted elsewhere)
      st.mode, st.who, st.stay, st.auto = "park", nil, nil, nil
      st.hold = not yes(cmd.auto) and true or nil
      if tonumber(cmd.x) and tonumber(cmd.z) then
        st.park = { x = math.floor(tonumber(cmd.x)), z = math.floor(tonumber(cmd.z)) }
      end
    elseif cmd.cmd == "auto" then
      -- pair up by itself again: park, and ask the factory who needs company
      st.mode, st.who, st.stay, st.auto, st.hold, st.gaveUp = "park", nil, nil, nil, nil, nil
    end
    save()
  end
end
