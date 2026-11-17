-- screens.lua : runs on a station, the plain computer that sits beside a
-- screen in the factory (in the wall behind it, where there is a wall).
--
-- A station needs nothing typed into it. A helper sets it up on the launch
-- pad's disk drive (the factory's floppy installs it), carries it to its
-- post and switches it on. It then
--   * works out which screen is its own from where it stands (GPS), or
--     failing that from the size of the monitor it touches;
--   * listens to what every drone says about itself (they all broadcast
--     their status through ender modems, which are heard anywhere);
--   * draws its screen with dash.lua, four times a second;
--   * passes taps on a button to the controller, which gives the order.
--     A station gives no orders itself and holds no secrets: the GitHub
--     token stays on the controller.
-- With nothing heard for a while it says so on the screen, and falls back
-- on the status file the controller uploads (a few minutes old at worst).

local okSwarm, swarm = pcall(require, "swarm")
if not okSwarm then swarm = nil end
local dash = require("dash")

local REPO = "KyleATRYZE/turtles"
local ORIGIN = { x = -4448, y = 71, z = 1518 }      -- the factory building's corner (plan 0, 0, 0)
local PANEL_PROTOCOL = swarm and swarm.PANEL_PROTOCOL or "swarm_panel"
local POST_FILE = ".post"

-- The posts, in the plan's own coordinates (tools/blueprint.py: STATIONS;
-- test/screenstest.py checks the two agree).
local POSTS = {
  { name = "west gate",   kind = "gate",  at = { 0, 5, 1 },    label = "GateWest",   gateX = 0 },
  { name = "east gate",   kind = "gate",  at = { 44, 5, 1 },   label = "GateEast",   gateX = 44 },
  { name = "rack",        kind = "rack",  at = { 22, 4, 3 },   label = "RackBoard" },
  { name = "bay panel",   kind = "panel", at = { 19, 4, 26 },  label = "BayPanel",   title = "LAUNCH BAY" },
  { name = "wall",        kind = "wall",  at = { 46, 17, 20 }, label = "WallScreen" },
  { name = "tower panel", kind = "panel", at = { 45, 17, 23 }, label = "TowerPanel", title = "CONTROL" },
  -- a station put down at the storage desk becomes the storage computer
  { name = "storage desk", kind = "storage", at = { 13, 2, 29 }, label = "Sortnado" },
}
local SITE = { -4448, 1518, -4404, 1548, layers = 37 }   -- the building, for the map
local HUT = { -4464, 1518, -4458, 1532 }
local MAPS = { "factory_site", "meadow", "ground" }
local PLOT, KEEP_OUT, HUNT_RANGE = 8, 24, 128
local DOCKS = 16                                    -- homes in the rack: 8 across, 2 high
local QUIET = 90                                    -- seconds with nothing heard before saying so

local S = {
  units = {},            -- [id as text] = what that machine last said (+ seen)
  heard = nil,           -- os.clock() of the last live report
  heardAt = nil,         -- its time of day, for the screen
  fromFile = nil,        -- time of day of the uploaded status, when that is what is shown
  maps = {},
  armed = nil, armedAt = 0,
  note = nil, noteAt = 0, noteColour = nil,
  pick = nil, pickAt = 0,
  gateSeen = {},         -- word -> os.clock() a drone was last seen on that track
  frame = 0,
}

---------------------------------------------------------------- which post
local function byName(name)
  for _, p in ipairs(POSTS) do if p.name == name then return p end end
end

-- world position -> the post standing there (or nil)
local function postAt(x, y, z)
  local lx, ly, lz = x - ORIGIN.x, y - ORIGIN.y, z - ORIGIN.z
  for _, p in ipairs(POSTS) do
    if p.at[1] == lx and p.at[2] == ly and p.at[3] == lz then return p end
  end
end

-- no GPS fix: tell by the monitor (text scale 0.5). The two gates look the
-- same; the west one is assumed, and "post <name>" in the order file or a
-- file named .post puts it right.
local function postBySize(w, h)
  if w >= 150 and h >= 45 then return byName("wall") end
  if w >= 150 and h <= 12 then return byName("rack") end
  if h >= 20 and h <= 26 and w >= 50 and w <= 60 then return byName("tower panel") end
  if h >= 20 and h <= 26 and w >= 30 and w <= 40 then return byName("bay panel") end
  if h <= 12 and w >= 30 and w <= 40 then return byName("west gate") end
end

local function readFile(name)
  if not fs.exists(name) then return nil end
  local h = fs.open(name, "r")
  local s = h.readAll()
  h.close()
  return s
end

local function writeFile(name, text)
  local h = fs.open(name, "w")
  h.write(text)
  h.close()
end

-- Returns the post and how it was told ("file", "gps", "monitor"), or nil.
local function identify(mon)
  local saved = readFile(POST_FILE)
  saved = saved and byName((saved:gsub("^%s+", ""):gsub("%s+$", "")))
  if saved then return saved, "file" end
  if gps and gps.locate then
    local ok, x, y, z = pcall(gps.locate, 3)
    if ok and x then
      local p = postAt(math.floor(x + 0.5), math.floor(y + 0.5), math.floor(z + 0.5))
      if p then return p, "gps" end
    end
  end
  if mon then
    mon.setTextScale(0.5)
    local w, h = mon.getSize()
    local p = postBySize(w, h)
    if p then return p, "monitor" end
  end
end

---------------------------------------------------------------- what is heard
local function nowMs() return os.epoch and os.epoch("utc") or 0 end
local function clock() return os.date and os.date("%H:%M") or "" end

local function note(text, colour)
  S.note, S.noteAt, S.noteColour = text, os.clock(), colour
end

-- one machine's report, as it came over the air
local function hear(id, msg)
  if type(msg) ~= "table" then return end
  msg.seen = nowMs()
  S.units[tostring(id)] = msg
  S.heard, S.heardAt, S.fromFile = os.clock(), clock(), nil
end

-- the status file the controller uploads: used when nothing has been heard
local function loadStatusFile()
  if not http then return false end
  local ok, res = pcall(http.get, "https://raw.githubusercontent.com/" .. REPO .. "/status/status.json")
  if not ok or not res then return false end
  local okJson, doc = pcall(textutils.unserializeJSON, res.readAll())
  res.close()
  if not okJson or type(doc) ~= "table" or type(doc.units) ~= "table" then return false end
  local newest = 0
  for id, u in pairs(doc.units) do
    if type(u) == "table" then
      local mine = S.units[tostring(id)]
      if not mine or (mine.seen or 0) < (u.seen or 0) then S.units[tostring(id)] = u end
      newest = math.max(newest, u.seen or 0)
    end
  end
  S.fromFile = (newest > 0 and os.date) and os.date("%H:%M", math.floor(newest / 1000)) or "earlier"
  return true
end

local function fetchMaps()
  if not http then return end
  for _, name in ipairs(MAPS) do
    local ok, res = pcall(http.get, "https://raw.githubusercontent.com/" .. REPO .. "/status/maps/" .. name .. ".json")
    if ok and res then
      local okJson, doc = pcall(textutils.unserializeJSON, res.readAll())
      res.close()
      local d = okJson and type(doc) == "table" and doc.data
      if type(d) == "table" and d.kind == "ground" and d.heights and d.names and d.palette then
        S.maps[#S.maps + 1] = { name = name, origin = d.origin, size = d.size,
          heights = d.heights, names = d.names, palette = d.palette }
      end
    end
  end
end

-- Words for "how fresh is this": nil while reports are coming in.
local function staleWords()
  if S.heard and os.clock() - S.heard < QUIET then return nil end
  if S.heard then return "NO SIGNAL SINCE " .. (S.heardAt or "?") end
  if S.fromFile then return "NO RADIO: SHOWING THE " .. S.fromFile .. " STATUS FILE" end
  return "WAITING FOR THE SWARM"
end

---------------------------------------------------------------- the fleet, counted
local function fleetList()
  local list = {}
  for _, u in pairs(S.units) do
    if type(u) == "table" and u.role ~= "screen" and u.role ~= "storage" and u.role ~= "controller" then
      list[#list + 1] = u
    end
  end
  table.sort(list, function(a, b) return tostring(a.label) < tostring(b.label) end)
  return list
end

local RESTING = { parked = true, idle = true, stopped = true, ["fleet full"] = true }
local function counts()
  local working, resting, silent, low = 0, 0, 0, 0
  local now = nowMs()
  for _, u in ipairs(fleetList()) do
    if u.seen and now - u.seen > 600000 then silent = silent + 1
    elseif RESTING[u.state or ""] or (u.state or ""):find("^Parked") then resting = resting + 1
    else working = working + 1 end
    if type(u.fuel) == "number" and u.fuel >= 0 and u.fuel < 400 and u.role ~= "factory" then low = low + 1 end
  end
  return working, resting, silent, low
end

local function short(name) return (tostring(name):gsub("^.*:", ""):gsub("_", " ")) end

---------------------------------------------------------------- the wall
local function plotOrigin(f, index)
  local n = 0
  for r = 0, 80 do
    for gx = -r, r do
      for gz = -r, r do
        if math.max(math.abs(gx), math.abs(gz)) == r then
          local x0, z0 = f.x + gx * PLOT, f.z + gz * PLOT
          if f.x < x0 - KEEP_OUT or f.x > x0 + PLOT - 1 + KEEP_OUT
            or f.z < z0 - KEEP_OUT or f.z > z0 + PLOT - 1 + KEEP_OUT then
            n = n + 1
            if n == index then return x0, z0 end
          end
        end
      end
    end
  end
end

local plotCache = {}
local function wallData()
  local forge
  local list = {}
  for _, u in pairs(S.units) do
    if u.role == "factory" then forge = u end
    if type(u.log) == "table" and #u.log > 0 then list[#list + 1] = u end
  end
  if not (forge and type(forge.base) == "table" and forge.base.f) then return nil end
  local f = forge.base.f
  table.sort(list, function(a, b) return (a.seen or 0) > (b.seen or 0) end)
  local events = {}
  for i = 1, math.min(#list, 14) do events[i] = { list[i].label, list[i].log[#list[i].log] } end
  local plots = { size = PLOT, done = {}, active = {} }
  local fleet = type(forge.fleet) == "table" and forge.fleet or {}
  local live = {}
  for _, index in pairs(fleet.byId or {}) do live[index] = true end
  for index = 1, (fleet.nextPlot or 1) - 1 do
    local o = plotCache[index]
    if not o then
      local x, z = plotOrigin(f, index)
      o = { x, z }
      plotCache[index] = o
    end
    if live[index] then plots.active[#plots.active + 1] = o else plots.done[#plots.done + 1] = o end
  end
  local inv = type(forge.inv) == "table" and forge.inv or {}
  local store = type(forge.storage) == "table" and forge.storage or {}

  -- a line each for the stock, the foundry and the chunk loaders
  local lines = {}
  local function have(name) return inv[name] or 0 end
  lines[#lines + 1] = { "Stock", ("lava %d  iron %d  redstone %d  logs %d"):format(
    have("minecraft:lava_bucket"), have("minecraft:iron_ingot"), have("minecraft:redstone"),
    have("minecraft:oak_log")) }
  local fy = type(forge.foundry) == "table" and forge.foundry or nil
  if fy then
    local mach = {}
    for name, okM in pairs(type(fy.machines) == "table" and fy.machines or {}) do
      if okM then mach[#mach + 1] = name end
    end
    table.sort(mach)
    local last = type(fy.last) == "table" and (fy.last.ok and "last run fine" or "last run failed") or ""
    lines[#lines + 1] = { "Foundry", (#mach > 0 and table.concat(mach, " + ") or "no machines yet")
      .. (fy.job and ("  " .. string.char(183) .. " " .. short(fy.job)) or "") .. (last ~= "" and ("  " .. string.char(183) .. " " .. last) or ""),
      (type(fy.last) == "table" and fy.last.ok == false) and "amber" or nil }
  end
  local parked, out, who = 0, 0, {}
  for _, u in pairs(S.units) do
    if u.role == "loader" then
      local with = type(u.job) == "table" and u.job.who
      if u.state == "parked" or u.state == "needs fuel" or not with then parked = parked + 1
      else out = out + 1; who[#who + 1] = tostring(with) end
    end
  end
  if parked + out > 0 then
    table.sort(who)
    lines[#lines + 1] = { "Loaders", ("%d at base  %d out%s"):format(parked, out,
      #who > 0 and (" with " .. table.concat(who, ", ")) or ""), parked == 0 and "red" or nil }
  end

  local pick
  if S.pick and os.clock() - S.pickAt < 30 then
    for _, u in pairs(S.units) do
      if u.label == S.pick then
        local p = u.pos
        pick = { ("%s  %s"):format(tostring(u.label), tostring(u.state)),
          (p and ("at %d, %d, %d   " ):format(p.x, p.y, p.z) or "") .. "fuel " .. tostring(u.fuel or "?"),
          type(u.log) == "table" and u.log[#u.log] or "" }
      end
    end
  end
  return {
    units = S.units, maps = S.maps, base = { x = f.x, y = f.y, z = f.z },
    site = { SITE[1], SITE[2], SITE[3], SITE[4], progress = 1, layers = SITE.layers },
    hut = HUT, plots = plots,
    factory = { coal = have("minecraft:coal") + have("minecraft:charcoal"),
      used = store.used, slots = store.slots, free = store.free },
    lines = lines, pick = pick,
    clock = clock(), now = nowMs(), updated = S.fromFile and ("file of " .. S.fromFile) or "live",
    events = events, huntRange = HUNT_RANGE,
    armed = (S.armed and os.clock() - S.armedAt < 6) and S.armed or nil,
    note = (S.note and os.clock() - S.noteAt < 12) and S.note or nil,
    stale = staleWords(),
  }
end

---------------------------------------------------------------- the gates
-- Both gates read the same from outside: the left light is OUT, the right
-- IN. A drone reported on a track near the gate lights that side for a
-- few seconds (the back track, z 1, runs west; the front, z 2, runs east).
local function gateView(post)
  local now = os.clock()
  for _, u in pairs(S.units) do
    local p = type(u) == "table" and u.pos
    if p and u.seen and nowMs() - u.seen < 8000 then
      local lx, ly, lz = p.x - ORIGIN.x, p.y - ORIGIN.y, p.z - ORIGIN.z
      if math.abs(lx - post.gateX) <= 5 and ly >= 1 and ly <= 4 and (lz == 1 or lz == 2) then
        local west = post.gateX == 0
        -- z 1 leaves by the west gate and comes in by the east one; z 2 the other way
        local word = ((lz == 1) == west) and "OUT" or "IN"
        S.gateSeen[post.name .. word] = now
      end
    end
  end
  local active
  for _, word in ipairs({ "OUT", "IN" }) do
    local at = S.gateSeen[post.name .. word]
    if at and now - at < 6 then active = word end
  end
  return { left = "OUT", right = "IN", active = active, frame = S.frame }
end

---------------------------------------------------------------- the rack's name board
-- Sixteen homes, two to a column. Drones are given homes in name order;
-- one standing in its home is lit, one away shows what it is doing.
local function rackSlots()
  local list = {}
  for _, u in ipairs(fleetList()) do
    if u.role == "miner" or u.role == "loader" or u.role == "helper" then list[#list + 1] = u end
  end
  local slots = {}
  for col = 1, DOCKS / 2 do
    local x = ORIGIN.x + 18 + col                   -- docks stand at plan x 19..26, z 3
    local function at(u, y)
      if not u then return nil end
      local p = u.pos
      u.home = p ~= nil and p.x == x and p.z == ORIGIN.z + 3 and p.y == ORIGIN.y + y
      return u
    end
    slots[col] = { upper = at(list[col * 2 - 1], 3), lower = at(list[col * 2], 1) }
  end
  return slots
end

---------------------------------------------------------------- the panels
local BUTTONS = {
  { "miners_home", "MINERS HOME", "red" },
  { "miners_resume", "MINERS RESUME", "green" },
  { "refresh", "REFRESH ALL", "cyan" },
}
local function panelView(post)
  local working, resting, silent, low = counts()
  local c = { { working, "working", "amber" }, { resting, "resting", "dim" } }
  if silent > 0 then c[#c + 1] = { silent, "silent", "red" } end
  if low > 0 then c[#c + 1] = { low, "low fuel", "red" } end
  local fresh = S.note and os.clock() - S.noteAt < 12
  return {
    title = post.title or "SWARM", counts = c, buttons = BUTTONS,
    armed = (S.armed and os.clock() - S.armedAt < 6) and S.armed or nil,
    note = fresh and S.note or "Tap twice to send", noteColour = fresh and (S.noteColour or "text") or "dim",
    stale = staleWords(),
  }
end

---------------------------------------------------------------- taps
-- A button asks the controller; only the controller gives orders. Every
-- button has to be tapped twice within six seconds.
local askN = 0
local function ask(what, post)
  askN = askN + 1
  local n = (os.getComputerID and os.getComputerID() or 0) * 1000 + askN % 1000
  S.waiting = { n = n, at = os.clock() }
  if rednet and rednet.broadcast then
    rednet.broadcast({ type = "ask", ask = what, n = n, from = post and post.name or "a screen" }, PANEL_PROTOCOL)
  end
  note("Asked control...", "dim")
  return n
end

local WALL_ASK = { recall = "recall", resume = "resume", pause = "pause" }
local function tap(id, post)
  if not id then return nil end
  local label = id:match("^unit:(.+)$")
  if label then
    S.pick, S.pickAt = label, os.clock()
    return nil
  end
  local what = (post.kind == "wall") and WALL_ASK[id] or id
  if post.kind == "wall" and not WALL_ASK[id] then
    if id == "find" then note("Tap a drone on the map or in the list") end
    if id == "storage" then note("The storage screen is in the storage room") end
    return nil
  end
  if S.armed == id and os.clock() - S.armedAt < 6 then
    S.armed = nil
    return ask(what, post)
  end
  S.armed, S.armedAt = id, os.clock()
  return nil
end

local function answer(msg)
  if type(msg) ~= "table" or msg.type ~= "ack" then return end
  if S.waiting and msg.n == S.waiting.n then
    S.waiting = nil
    note(tostring(msg.text or (msg.ok and "Sent." or "Not sent.")), msg.ok and "green" or "amber")
  end
end

---------------------------------------------------------------- drawing
-- Draws this post's screen once; returns the touch zones.
local function draw(post, mon)
  S.frame = S.frame + 1
  if S.waiting and os.clock() - S.waiting.at > 6 then
    S.waiting = nil
    note("Control did not answer", "amber")
  end
  if post.kind == "wall" then
    local data = wallData()
    if not data then
      return dash.notice(mon, { "SWARM CONTROL", staleWords() or "Waiting for the factory to report.",
        "This screen draws itself as soon as the factory is heard." })
    end
    return dash.wall(mon, data, S.frame)
  elseif post.kind == "gate" then
    return dash.gate(mon, gateView(post))
  elseif post.kind == "rack" then
    return dash.rack(mon, rackSlots(), nowMs())
  elseif post.kind == "panel" then
    return dash.panel(mon, panelView(post), S.frame)
  end
  return {}
end

local function zoneAt(zones, x, y)
  for i = #(zones or {}), 1, -1 do
    local z = zones[i]
    if x >= z[1] and x <= z[3] and y >= z[2] and y <= z[4] then return z[5] end
  end
end

---------------------------------------------------------------- for the tests
if _G.SCREENS_TEST then
  return { S = S, POSTS = POSTS, ORIGIN = ORIGIN, postAt = postAt, postBySize = postBySize, identify = identify,
    hear = hear, loadStatusFile = loadStatusFile, staleWords = staleWords, draw = draw, tap = tap,
    zoneAt = zoneAt, answer = answer, wallData = wallData, gateView = gateView, rackSlots = rackSlots,
    panelView = panelView, counts = counts }
end

---------------------------------------------------------------- running
local function findMonitor()
  local best, bestArea
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "monitor" then
      local m = peripheral.wrap(name)
      m.setTextScale(0.5)
      local w, h = m.getSize()
      if not best or w * h > bestArea then best, bestArea = m, w * h end
    end
  end
  return best
end

local function openRadio()
  local opened = false
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "modem" then
      rednet.open(name)
      opened = true
    end
  end
  return opened
end

local post, how
local radio = false

local function report(state, line)
  if not (swarm and radio) then return end
  pcall(swarm.report, { role = "screen", state = state, post = post and post.name,
    log = { line or state } })
end

local function setUp()
  local mon
  while true do
    mon = findMonitor()
    post, how = identify(mon)
    if post then break end
    local where = "no GPS fix"
    if gps and gps.locate then
      local ok, x, y, z = pcall(gps.locate, 3)
      if ok and x then where = ("at %d %d %d"):format(x, y, z) end
    end
    print("I do not know which screen is mine (" .. where .. ").")
    if mon then
      pcall(dash.notice, mon, { "STATION " .. tostring(os.getComputerLabel() or os.getComputerID()),
        "I cannot tell which screen this is (" .. where .. ").",
        "Looking again every half minute." })
    end
    sleep(30)
  end
  if post.kind == "storage" then
    -- standing at the storage desk: this one is the storage computer
    writeFile(".role", "storage")
    os.setComputerLabel(post.label)
    print("This is the storage desk. Becoming the storage computer.")
    sleep(1)
    os.reboot()
  end
  if post.kind == "rack" then
    -- moved into the wall at the rack's end (docs/rack-build.html): on the
    -- cable now, it runs the rack's panels instead
    for _, name in ipairs(peripheral.getNames()) do
      if peripheral.getType(name) == "modem" and not peripheral.call(name, "isWireless") then
        writeFile(".role", "rack")
        print("On the cable at the rack: becoming the rack's panels.")
        sleep(1)
        os.reboot()
      end
    end
  end
  writeFile(POST_FILE, post.name)
  if os.getComputerLabel() ~= post.label then os.setComputerLabel(post.label) end
  print(("Post: %s (told by %s)."):format(post.name, how))
  return mon
end

local zones = {}
local function painter()
  local mon = setUp()
  local hadMonitor = mon ~= nil
  if post.kind == "wall" then pcall(fetchMaps) end
  if not radio then pcall(loadStatusFile) end
  report("on", "Screen on: " .. post.name)
  local lastFile, lastReport = os.clock(), os.clock()
  while true do
    if not mon or not pcall(mon.getSize) then mon = findMonitor() end
    if mon then
      local ok, z = pcall(draw, post, mon)
      if ok then zones = z or {} else print("draw: " .. tostring(z)) end
      if not hadMonitor then hadMonitor = true end
    end
    -- nothing on the air: look at the uploaded file now and then
    if (not S.heard or os.clock() - S.heard > QUIET) and os.clock() - lastFile > 300 then
      lastFile = os.clock()
      pcall(loadStatusFile)
    end
    if os.clock() - lastReport > 60 then
      lastReport = os.clock()
      report(mon and "on" or "no monitor", mon and ("Showing: " .. post.name) or "No monitor touching me.")
    end
    sleep(post.kind == "wall" and 0.25 or 0.5)
  end
end

local function listener()
  while true do
    local id, msg, protocol = rednet.receive()
    if protocol == (swarm and swarm.PROTOCOL or "swarm") then
      hear(id, msg)
    elseif protocol == PANEL_PROTOCOL then
      answer(msg)
    end
  end
end

local function toucher()
  while true do
    local _, _, x, y = os.pullEvent("monitor_touch")
    if post then pcall(tap, zoneAt(zones, x, y), post) end
  end
end

-- orders from the controller: reboot (to update), ping, and "post" to say
-- which screen this is when it cannot tell
local function orders()
  if not (swarm and radio) then while true do sleep(3600) end end
  while true do
    local cmd = swarm.waitCommand()
    if cmd.cmd == "reboot" then
      swarm.pinVersion(cmd)
      sleep(1)
      os.reboot()
    elseif cmd.cmd == "post" and type(cmd.name) == "string" and byName((cmd.name:gsub("_", " "))) then
      writeFile(POST_FILE, (cmd.name:gsub("_", " ")))
      sleep(1)
      os.reboot()
    elseif cmd.cmd == "ping" then
      report("on", "Here.")
    end
  end
end

writeFile(".role", "screen")
radio = openRadio()
if not radio then print("No modem on me: I will show the uploaded status file only.") end
parallel.waitForAny(painter, listener, toucher, orders)
