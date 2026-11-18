-- rack.lua : the rack's live ops board (docs/rack-build.html). Runs on the
-- computer in the wall at the west end of rack 1.
--
-- Rack 1 is one rack for every drone: 8 homes across, 4 rows (32 homes).
-- Each monitor strip on the cable (monitor_N) shows a row of homes, a panel
-- per home: the drone's name, what it is doing in words with its progress
-- ("Lava wall 12/40", "Fetching: cable x18"), a fuel bar and how long since
-- it was heard, on a colour that says how it is at a glance:
--   green  docked or idle          amber  working
--   blue   fetching a load         red    stuck, out of fuel, an error, or
--   grey   nobody lives here              waiting more than 10 minutes
-- The board touching the computer (the old name board, the top row) is the
-- factory's summary: crafter1, the store, fuel stock, jobs, stalled drones.
-- Tap a panel for that drone's own screen for 20 seconds.
--
-- It hears the drones through crafter1 (and Sortnado before the move) over
-- the cable, and on an ender modem if it has one. Which strip shows which
-- row: by default the strips in the order of their names, each taking as
-- many rows as it must so every row is shown; a file .rack can say
-- otherwise ({ strips = { monitor_3 = { 0 }, monitor_5 = { 1 } } }: row 0 is
-- the first eight homes).

local okSwarm, swarm = pcall(require, "swarm")
if not okSwarm then swarm = nil end
-- drawn by dash.lua, in the same palette and style as the other screens
-- (without it, plain text)
local okDash, dash = pcall(require, "dash")
if not okDash or type(dash) ~= "table" or not dash.homes then dash = nil end

local CHANNEL = 4711                                  -- factory.lua K.RACK_CHANNEL
-- homes by name: the helpers (0-15), the chunk loaders (16-26), then the
-- miners by id and mapper1 in the last home
local HELPERS = { "lava1", "builder1", "builder7", "foundry1", "builder3", "builder4", "builder2", "survey1",
  "builder6", "rescue1", "builder5", "builder8", "builder9", "builder10", "builder11", "builder12" }
local LOADERS = { "Phantastic", "Ablaze", "Vexed", "Beehave", "Batty", "Breezy", "AllayOop", "WitherOrNot",
  "Shulky", "Squawk", "Ghastly" }
local HOMES = {}
for _, n in ipairs(HELPERS) do HOMES[#HOMES + 1] = n end
for _, n in ipairs(LOADERS) do HOMES[#HOMES + 1] = n end
local BUILDER_HOME = 31
-- where the homes are: x along, a y per row
local RACK = { x = -4429, rows = { 72, 74, 76, 78 }, z = 1521, perRow = 8, nRows = 4 }   -- swarm.lua M.LANE (surveyed)
local QUIET = 300                                     -- seconds unheard before a drone counts as silent
local STALL = 600                                     -- seconds in a waiting state before it counts as stuck
local SHOW = 20                                       -- seconds a tapped drone's screen stays up
local FULL_FUEL = 20000

local R = { units = {}, pick = nil, pickAt = 0, pickMon = nil, factory = nil, store = nil, stalled = {}, frame = 0 }

---------------------------------------------------------------- homes
-- (a drone still reporting under its old name is the same drone: see the
-- names in swarm.lua)
local function same(name, u)
  if name == u.label then return true end
  return swarm and swarm.sameName and swarm.sameName(name, u.label, u.id) or false
end
function R.homeOf(u)
  for i, n in ipairs(HOMES) do if same(n, u) then return i - 1 end end
  if u.role == "builder" or same("mapper1", u) then return BUILDER_HOME end
  local id = tonumber(u.id)
  if not id then return nil end
  if u.role == "helper" then return id % #HELPERS end
  if u.role == "miner" then return #HOMES + id % (BUILDER_HOME - #HOMES) end
end
function R.homeAt(i)
  local y = RACK.rows[math.floor(i / RACK.perRow) + 1]
  if not y then return nil end
  return RACK.x + i % RACK.perRow, y, RACK.z
end
function R.docked(u, i)
  local p = u and u.pos
  local x, y, z = R.homeAt(i)
  if type(p) ~= "table" or not x then return false end
  return p.x == x and p.y == y and p.z == z
end
-- who lives in home i: a drone with that name, else one whose id puts it there
function R.resident(i)
  local best
  for _, u in pairs(R.units) do
    if R.homeOf(u) == i then
      local named = HOMES[i + 1] and same(HOMES[i + 1], u)
      if not best or named or (not (HOMES[i + 1] and same(HOMES[i + 1], best)) and (u.seen or 0) > (best.seen or 0)) then
        best = u
      end
    end
  end
  return best
end

local ROLES = { helper = true, miner = true, loader = true, builder = true }
function R.hear(msg, now)
  if type(msg) ~= "table" or type(msg.label) ~= "string" then return end
  now = now or os.clock()
  if msg.role == "factory" then
    R.factory, R.factoryAt = msg, now
    R.stalled = {}
    for _, n in ipairs(type(msg.stalled) == "table" and msg.stalled or {}) do R.stalled[n] = true end
    return
  end
  if msg.role == "storage" then R.store, R.storeAt = msg, now return end
  if not ROLES[msg.role] then return end
  local u = R.units[msg.label] or {}
  local state = tostring(msg.state or "?")
  if u.state ~= state then u.since = now end
  u.label, u.role, u.id, u.state = msg.label, msg.role, msg.id, state
  if type(msg.pos) == "table" and tonumber(msg.pos.x) then
    u.pos = { x = tonumber(msg.pos.x), y = tonumber(msg.pos.y), z = tonumber(msg.pos.z) }
  end
  u.fuel = tonumber(msg.fuel)
  u.progress = type(msg.progress) == "table" and msg.progress or nil
  u.job = type(msg.job) == "string" and msg.job or nil
  u.fetching = type(msg.fetching) == "string" and msg.fetching or nil
  u.foundry = type(msg.foundry) == "table" and msg.foundry or nil
  if type(msg.screen) == "table" then u.screen = msg.screen end
  u.seen = now
  R.units[msg.label] = u
end

---------------------------------------------------------------- in words
-- fit plans and what they are, for people
local PLANS = { factory_f2_lava = "Lava wall", factory_f2_link = "Cable", factory_f2_certus = "Certus farm",
  factory_f2_clear = "Clearing", factory_f2_power = "Power row", factory_f2_alloy = "Alloy cell",
  factory_f2_ore = "Ore line", factory_f2_ae2 = "AE2 room", factory_f2_close = "Floor back",
  factory_screens = "Screens", factory_pitstop = "crafter1's bench", factory_desklink = "Desk link",
  factory_walls = "Store walls" }
local function plainName(s) return (tostring(s):gsub("^.*:", ""):gsub("_", " ")) end

function R.doing(u)
  local p = u.progress
  if u.fetching then return "Fetching: " .. u.fetching end
  if type(u.foundry) == "table" and u.foundry.job then return "Foundry: " .. plainName(u.foundry.job) end
  local job = u.job and (PLANS[u.job] or plainName((u.job:gsub("^factory_", ""))))
  if p and tonumber(p.done) and tonumber(p.total) then
    local what = job or ({ building = "Building", fitting = "Fitting", lab = "Lab", foraging = "Foraging",
      chopping = "Chopping" })[p.kind] or plainName(p.kind or "Working")
    if p.kind == "lab" and p.step then what = "Lab " .. plainName(p.step) end
    return ("%s %d/%d"):format(what, p.done, p.total)
  end
  if job then return job end
  return u.state
end

local WAITING = { ["waiting for materials"] = true, ["fetching materials"] = true }
local IDLE = { idle = true, ["waiting for jobs"] = true, docked = true, parked = true, stopped = true, paused = true }
function R.colour(u, i, now)
  now = now or os.clock()
  local st = tostring(u.state):lower()
  local stuck = st:find("stuck") or st:find("error") or st:find("lost") or st:find("boxed") or st:find("no fuel")
    or st:find("out of fuel") or st:find("crash") or st:find("cannot") or st:find("problem")
  if stuck or R.stalled[u.label] or (u.fuel and u.fuel >= 0 and u.fuel < 100)
    or (WAITING[st] and now - (u.since or now) > STALL) then return "red" end
  if u.fetching or WAITING[st] then return "blue" end
  if (i and R.docked(u, i)) or IDLE[st] or st:find("waiting for jobs", 1, true) then return "green" end
  return "orange"
end

local function ago(s)
  if s < 60 then return math.floor(s) .. "s ago" end
  if s < 3600 then return math.floor(s / 60) .. "m ago" end
  return math.floor(s / 3600) .. "h ago"
end

-- what panel i shows: { name, word, state, fuel, colour, job, fill, ago }
function R.panel(i, now)
  now = now or os.clock()
  local u = R.resident(i)
  if not u then
    return { name = HOMES[i + 1] or (i == BUILDER_HOME and "mapper1") or "-", word = "free", state = "", fuel = "",
      colour = "grey", job = "", fill = 0, ago = "" }
  end
  local silent = now - (u.seen or 0) > QUIET
  local p = { name = u.label, word = silent and "silent" or (R.docked(u, i) and "docked" or "out"), state = u.state,
    fuel = u.fuel and (u.fuel < 0 and "fuel: inf" or ("fuel " .. math.floor(u.fuel))) or "",
    job = R.doing(u), fill = u.fuel and (u.fuel < 0 and 1 or math.min(1, u.fuel / FULL_FUEL)) or 0,
    ago = ago(now - (u.seen or now)) }
  p.colour = silent and "red" or R.colour(u, i, now)
  return p
end

-- the factory's summary, line by line (and whether anything is stalled)
function R.summary(now)
  now = now or os.clock()
  local f, lines = R.factory, {}
  if not f then return { "FACTORY: not heard yet", R.diag }, false end
  local inv = type(f.inv) == "table" and f.inv or {}
  local n = function(k) return tonumber(inv[k]) or 0 end
  local s = type(f.storage) == "table" and f.storage or {}
  local st = R.store and type(R.store.storage) == "table" and R.store.storage or nil
  local working, waiting, idle = 0, 0, 0
  for _, u in pairs(R.units) do
    local c = R.colour(u, R.homeOf(u), now)
    if c == "orange" then working = working + 1 elseif c == "blue" then waiting = waiting + 1 else idle = idle + 1 end
  end
  local stalled = {}
  for k in pairs(R.stalled) do stalled[#stalled + 1] = k end
  table.sort(stalled)
  local fy = type(f.foundry) == "table" and f.foundry or {}
  lines[1] = ("CRAFTER1: %s   (%s)"):format(tostring(f.state), ago(now - (R.factoryAt or now)))
  lines[2] = ("STORE: %s slots free%s   crafter1's chests: %s free"):format(st and tostring(st.free) or "?",
    st and (" of " .. tostring(st.slots)) or "", tostring(s.free or "?"))
  lines[3] = ("FUEL: coal %d  charcoal %d  lava %d"):format(n("minecraft:coal"), n("minecraft:charcoal"),
    n("minecraft:lava_bucket"))
  lines[4] = ("DRONES: %d working  %d fetching  %d idle%s"):format(working, waiting, idle,
    #stalled > 0 and ("   STALLED: " .. table.concat(stalled, ", ")) or "")
  lines[5] = ("FOUNDRY: %s"):format(fy.job and plainName(fy.job)
    or (type(fy.last) == "table" and fy.last.made and ("last made " .. tostring(fy.last.made))) or "idle")
  if type(f.probe) == "string" then lines[6] = f.probe end
  if R.diag then lines[#lines + 1] = R.diag end
  return lines, #stalled > 0
end

---------------------------------------------------------------- the monitors
-- the board touching the computer (a side name) is the summary; every strip
-- on the cable (monitor_N) shows rows of homes
-- (every monitor touching the computer is a summary board: with two, the
-- second was never drawn and kept an old "not heard yet" frame)
function R.monitors()
  local board, strips, boards = nil, {}, {}
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "monitor" then
      if name:find("_", 1, true) then strips[#strips + 1] = name
      else board = board or name boards[#boards + 1] = name end
    end
  end
  -- a monitor touching the computer can ALSO be on the cable (a modem
  -- touches it too): then it is one monitor under two names, drawn twice a
  -- frame (the board and a strip) and it flickers. Find those by marking the
  -- side one's palette and looking for the mark on the cable ones.
  local MARK, slot = 0x0b0c0d, colours and colours.lightBlue or 8
  for _, b in ipairs(boards) do
    local okB, old = pcall(function() return { peripheral.call(b, "getPaletteColour", slot) } end)
    pcall(peripheral.call, b, "setPaletteColour", slot, MARK)
    for i = #strips, 1, -1 do
      local okS, r, g, bl = pcall(peripheral.call, strips[i], "getPaletteColour", slot)
      if okS and r and math.floor(r * 255 + 0.5) == 0x0b and math.floor(g * 255 + 0.5) == 0x0c
        and math.floor(bl * 255 + 0.5) == 0x0d then
        R.dups = R.dups or {}
        R.dups[strips[i]] = b
        table.remove(strips, i)
      end
    end
    if okB and old and old[1] then pcall(peripheral.call, b, "setPaletteColour", slot, old[1], old[2], old[3]) end
  end
  -- (rack 1's strips are as wide as its board, 8 blocks: since
  -- the store's cable joined ours, its screens and others are on it too)
  -- (measured once per monitor: changing the text scale every second flickers)
  R.sizes = R.sizes or {}
  local function size(n)
    if not R.sizes[n] then
      local ok, w, h = pcall(function()
        local m = peripheral.wrap(n) local sc = m.getTextScale() m.setTextScale(0.5)
        local a, b = m.getSize() m.setTextScale(sc) return a, b end)
      R.sizes[n] = ok and { w, h } or { 0, 0 }
    end
    return R.sizes[n][1], R.sizes[n][2]
  end
  if boards[1] then
    local bw = size(boards[1])
    if bw > 0 then
      for i = #strips, 1, -1 do
        local sw = size(strips[i])                -- (same width: the rack is 8 blocks wide)
        if sw ~= bw then table.remove(strips, i) end
      end
    end
  end
  R.boards = boards
  table.sort(strips, function(a, b)
    return (tonumber(a:match("(%d+)$")) or 0) < (tonumber(b:match("(%d+)$")) or 0)
  end)
  return board, strips
end

-- strip name -> the home rows it shows (0 = the first eight homes)
function R.layout(strips, cfg)
  local out = {}
  if type(cfg) == "table" and type(cfg.strips) == "table" then
    for _, s in ipairs(strips) do
      if type(cfg.strips[s]) == "table" then out[s] = cfg.strips[s] end
    end
    if next(out) then return out end
  end
  if #strips == 0 then return out end
  local per = math.ceil(RACK.nRows / #strips)
  for k, s in ipairs(strips) do
    local rows = {}
    for r = (k - 1) * per, math.min(RACK.nRows, k * per) - 1 do rows[#rows + 1] = r end
    if #rows > 0 then out[s] = rows end
  end
  return out
end

local BG = { green = colours and colours.green or 8192, orange = colours and colours.orange or 2,
  grey = colours and colours.grey or 128, red = colours and colours.red or 16384,
  blue = colours and colours.blue or 2048 }

local function fit(text, w) text = tostring(text or "") if #text > w then return text:sub(1, w) end return text end

local function showScreen(mon, w, h)
  local u = R.units[R.pick]
  mon.setTextColour(colours.yellow)
  mon.setCursorPos(1, 1)
  mon.write(fit((u and u.label or R.pick) .. "'s screen (tap to close)", w))
  mon.setTextColour(colours.white)
  local lines = u and u.screen or {}
  local shown = 0
  for i = math.max(1, #lines - (h - 2)), #lines do
    shown = shown + 1
    mon.setCursorPos(1, 1 + shown)
    mon.write(fit(lines[i], w))
  end
  if shown == 0 then mon.setCursorPos(1, 2) mon.write("Nothing heard from its screen yet.") end
end

-- a strip: its rows of homes, one band each, a panel per home
function R.draw(mon, rows, now, name)
  if type(rows) == "number" then rows = { math.floor(rows / RACK.perRow) } end   -- (a first home, as before)
  R.frame = R.frame + 1
  if R.dash then
    local view = { rows = {} }
    if R.pick and R.pickMon == name and (now or os.clock()) - R.pickAt < SHOW then
      local u = R.units[R.pick]
      view.pick = { label = u and u.label or R.pick, lines = u and u.screen or {} }
    end
    for _, row in ipairs(rows) do
      local panels = {}
      for c = 0, RACK.perRow - 1 do panels[#panels + 1] = R.panel(row * RACK.perRow + c, now) end
      view.rows[#view.rows + 1] = panels
    end
    return R.dash.homes(mon, view, R.frame)
  end
  mon.setTextScale(0.5)
  local w, h = mon.getSize()
  mon.setBackgroundColour(colours.black)
  mon.clear()
  if R.pick and R.pickMon == name and (now or os.clock()) - R.pickAt < SHOW then return showScreen(mon, w, h) end
  local pw = math.floor(w / RACK.perRow)
  local band = math.floor(h / math.max(1, #rows))
  for b, row in ipairs(rows) do
    local y0 = (b - 1) * band
    local tall = band - (b < #rows and 1 or 0)
    for c = 0, RACK.perRow - 1 do
      local p = R.panel(row * RACK.perRow + c, now)
      local x0 = c * pw + 1
      mon.setBackgroundColour(BG[p.colour])
      mon.setTextColour(colours.white)
      for y = 1, tall do
        mon.setCursorPos(x0, y0 + y)
        mon.write((" "):rep(pw - 1))
      end
      local inner = pw - 2
      local n = math.floor((p.fill or 0) * (inner - 2) + 0.5)
      local bar = "[" .. ("="):rep(n) .. (" "):rep(inner - 2 - n) .. "]"
      local lines = { p.name, p.job ~= "" and p.job or p.word, p.colour ~= "grey" and bar or "", p.ago }
      if tall < 4 then lines = { p.name .. " " .. (p.job or ""), p.ago } end
      for r, t in ipairs(lines) do
        if r <= tall then
          mon.setCursorPos(x0 + 1, y0 + r)
          mon.write(fit(t, inner))
        end
      end
      mon.setBackgroundColour(colours.black)
    end
  end
end

-- the summary board
function R.drawSummary(mon, now)
  if R.dash then
    local lines, alarm = R.summary(now)
    return R.dash.opsBoard(mon, { lines = lines, alarm = alarm, title = "FACTORY" }, R.frame)
  end
  mon.setTextScale(0.5)
  local w, h = mon.getSize()
  local lines, alarm = R.summary(now)
  for i = 0, 15 do pcall(mon.setPaletteColour, 2 ^ i, term.nativePaletteColour(2 ^ i)) end
  mon.setBackgroundColour(colours.black)
  mon.clear()
  for i, t in ipairs(lines) do
    if i > h then break end
    mon.setCursorPos(2, i)
    mon.setTextColour(i == 4 and alarm and colours.red or (i == 1 and colours.yellow or colours.white))
    mon.write(fit(t, w - 2))
  end
end

-- a tap on a strip: which drone's screen to show
function R.tap(mon, rows, x, now, name, y)
  if type(rows) == "number" then rows = { math.floor(rows / RACK.perRow) } end
  local w, h = mon.getSize()
  if R.pick and R.pickMon == name and (now or os.clock()) - R.pickAt < SHOW then R.pick = nil return end
  local c = math.min(RACK.perRow - 1, math.floor((x - 1) / math.floor(w / RACK.perRow)))
  local band = math.floor(h / math.max(1, #rows))
  local row = rows[math.min(#rows, math.floor(((y or 1) - 1) / math.max(1, band)) + 1)]
  local u = R.resident(row * RACK.perRow + c)
  if u then R.pick, R.pickAt, R.pickMon = u.label, now or os.clock(), name end
end

R.dash = dash
if _G.RACK_TEST then return R end

---------------------------------------------------------------- running
local cfg
if fs.exists(".rack") then
  local hh = fs.open(".rack", "r")
  cfg = textutils.unserialize(hh.readAll())
  hh.close()
end
-- rack 1's two strips, by their names on the cable (seen on them 18 Nov):
-- the lower one (y 73) shows rows 1-2 (y 72, 74), the upper one (y 75)
-- rows 3-4 (y 76, 78). Guessing them stopped working once the store's
-- cable, with all its screens, joined ours.
if not (type(cfg) == "table" and type(cfg.strips) == "table") then
  cfg = type(cfg) == "table" and cfg or {}
  cfg.strips = { monitor_12 = { 0, 1 }, monitor_23 = { 2, 3 } }
end
local wired
for _, name in ipairs(peripheral.getNames()) do
  if peripheral.getType(name) == "modem" then
    local m = peripheral.wrap(name)
    if m.isWireless() then rednet.open(name) else wired = wired or m end
  end
end
if wired then wired.open(CHANNEL) end
print("Rack board. Over the cable: " .. (wired and "yes" or "no") .. ".")

local function painter()
  while true do
    R.dups = {}
    local board, strips = R.monitors()
    if type(cfg) == "table" and type(cfg.strips) == "table" then
      strips = {}
      for n in pairs(cfg.strips) do if peripheral.isPresent(n) then strips[#strips + 1] = n end end
      table.sort(strips)
    end
    local lay = R.layout(strips, cfg)
    -- (which monitor shows what, on the board: so a screenshot tells us)
    local parts = {}
    for _, st in ipairs(strips) do parts[#parts + 1] = st:gsub("monitor_", "m") .. "=" .. (lay[st] and table.concat(lay[st], ",") or "-") end
    for d in pairs(R.dups) do parts[#parts + 1] = d:gsub("monitor_", "m") .. "=board" end
    R.diag = "SCREENS: " .. table.concat(parts, " ")
    for _, b in ipairs(R.boards or { board }) do pcall(R.drawSummary, peripheral.wrap(b), os.clock()) end
    for _, s in ipairs(strips) do
      if lay[s] then pcall(R.draw, peripheral.wrap(s), lay[s], os.clock(), s)
      else
        local m = peripheral.wrap(s)            -- (a strip with no rows: blank, not a frozen old frame)
        if m then pcall(function()                 -- (the board's palette made black pink: back to plain)
          for i = 0, 15 do m.setPaletteColour(2 ^ i, term.nativePaletteColour(2 ^ i)) end
          m.setBackgroundColour(colours.black) m.clear()
          m.setTextScale(1) m.setTextColour(colours.grey) m.setCursorPos(2, 1)
          m.write(s .. ": no rows (" .. R.diag .. ")") end) end
      end
    end
    sleep(1)
  end
end

local function listener()
  while true do
    local ev, a, b, c, d = os.pullEvent()
    if ev == "modem_message" and b == CHANNEL and type(d) == "table" then
      if d.type == "cmd" and type(d.cmd) == "table" then
        local t = d.cmd.target
        if d.cmd.cmd == "reboot" and (t == "all" or t == os.getComputerLabel() or t == os.getComputerID()
          or (swarm and swarm.forMe and swarm.forMe(d.cmd))) then
          print("Rebooting (passed on over the cable).")
          sleep(1)
          os.reboot()
        end
      else
        R.hear(d)
      end
    elseif ev == "rednet_message" and c == (swarm and swarm.PROTOCOL or "swarm") then
      R.hear(b)
    elseif ev == "rednet_message" and swarm and c == swarm.CMD_PROTOCOL and swarm.accept(b) and b.cmd == "reboot" then
      swarm.pinVersion(b)
      sleep(1)
      os.reboot()
    elseif ev == "monitor_touch" then
      local board, strips = R.monitors()
      local lay = (type(cfg) == "table" and type(cfg.strips) == "table") and cfg.strips or R.layout(strips, cfg)
      if a ~= board and lay[a] then pcall(R.tap, peripheral.wrap(a), lay[a], b, os.clock(), a, c) end
    end
  end
end

parallel.waitForAny(painter, listener)
