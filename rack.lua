-- rack.lua : the rack's panels (docs/rack-build.html). Runs on the computer
-- in the wall at the west end of rack 1, which touches the name board (the
-- high shelf's panel) and reaches the low shelf's strip over the cable.
--
-- Each shelf's strip has a panel per home: the drone that lives there, its
-- state and fuel, green when it is docked, amber when it is out, grey when
-- the home is free. Tap a panel for that drone's own screen (the lines its
-- status reports carry), shown across the strip for 20 seconds.
--
-- It hears the drones through Crafty, which passes every drone's status on
-- over the cable (no ender modem needed in the wall); an ender modem, if
-- there is one, is listened to as well. Crafty passes on the controller's
-- reboot orders too, so the rack updates like everything else.

local okSwarm, swarm = pcall(require, "swarm")
if not okSwarm then swarm = nil end

local CHANNEL = 4711                                  -- factory.lua K.RACK_CHANNEL
local HOMES = { "Pushy", "HopTo", "LeverAlone", "DropIt", "Sticky", "Dusty", "OnRepeat", "Comparable",
  "Observant", "Dispensable", "ButtonUp", "PlateUp", "Tripwired", "LampLit", "NoteWorthy", "TargetLock" }
local RACK = { x = -4429, low = 72, high = 74, z = 1521, perRow = 8 }   -- swarm.lua M.LANE
local QUIET = 300                                     -- seconds unheard before a drone counts as silent
local SHOW = 20                                       -- seconds a tapped drone's screen stays up

local R = { units = {}, pick = nil, pickAt = 0, pickMon = nil, frame = 0 }

---------------------------------------------------------------- homes
-- home index (0..15) of a drone: by name, else by id (as helper.lua LN.home)
function R.homeOf(u)
  for i, n in ipairs(HOMES) do if n == u.label then return i - 1 end end
  if u.role == "helper" and tonumber(u.id) then return tonumber(u.id) % (2 * RACK.perRow) end
end
function R.homeAt(i)
  return RACK.x + i % RACK.perRow, i < RACK.perRow and RACK.low or RACK.high, RACK.z
end
function R.docked(u, i)
  local p = u and u.pos
  if type(p) ~= "table" then return false end
  local x, y, z = R.homeAt(i)
  return p.x == x and p.y == y and p.z == z
end
-- who lives in home i: a drone with that name, else one whose id puts it there
function R.resident(i)
  local best
  for _, u in pairs(R.units) do
    if R.homeOf(u) == i and (u.role == "helper" or u.label == HOMES[i + 1]) then
      if not best or (u.label == HOMES[i + 1]) or (u.seen or 0) > (best.seen or 0) then best = u end
    end
  end
  return best
end

function R.hear(msg, now)
  if type(msg) ~= "table" or type(msg.label) ~= "string" then return end
  if msg.role ~= "helper" and msg.role ~= "miner" and msg.role ~= "loader" then return end
  local u = R.units[msg.label] or {}
  u.label, u.role, u.id, u.state = msg.label, msg.role, msg.id, tostring(msg.state or "?")
  if type(msg.pos) == "table" and tonumber(msg.pos.x) then
    u.pos = { x = tonumber(msg.pos.x), y = tonumber(msg.pos.y), z = tonumber(msg.pos.z) }
  end
  u.fuel = tonumber(msg.fuel)
  if type(msg.screen) == "table" then u.screen = msg.screen end
  u.seen = now or os.clock()
  R.units[msg.label] = u
end

-- what panel i of a shelf shows: { name, word, state, fuel, colour }
function R.panel(i, now)
  now = now or os.clock()
  local u = R.resident(i)
  if not u then return { name = HOMES[i + 1] or "-", word = "free", state = "", fuel = "", colour = "grey" } end
  local silent = now - (u.seen or 0) > QUIET
  local docked = R.docked(u, i)
  local fuel = u.fuel and (u.fuel < 0 and "fuel: inf" or ("fuel " .. math.floor(u.fuel))) or ""
  return { name = u.label, word = silent and "silent" or (docked and "docked" or "out"),
    state = u.state, fuel = fuel, colour = docked and not silent and "green" or (silent and "red" or "orange") }
end

---------------------------------------------------------------- the monitors
-- the high shelf's board touches the computer; the low shelf's strip is on
-- the cable (several modems see it: any one name will do)
function R.monitors()
  local high, low
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "monitor" then
      if name:find("_", 1, true) then low = low or name else high = high or name end
    end
  end
  return high, low
end

local BG = { green = colours and colours.green or 8192, orange = colours and colours.orange or 2,
  grey = colours and colours.grey or 128, red = colours and colours.red or 16384 }

local function fit(text, w) text = tostring(text or "") if #text > w then return text:sub(1, w) end return text end

function R.draw(mon, first, now, name)
  mon.setTextScale(0.5)
  local w, h = mon.getSize()
  mon.setBackgroundColour(colours.black)
  mon.clear()
  if R.pick and R.pickMon == name and (now or os.clock()) - R.pickAt < SHOW then
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
    return
  end
  local pw = math.floor(w / RACK.perRow)
  for c = 0, RACK.perRow - 1 do
    local p = R.panel(first + c, now)
    local x0 = c * pw + 1
    mon.setBackgroundColour(BG[p.colour])
    mon.setTextColour(colours.white)
    for y = 1, h do
      mon.setCursorPos(x0, y)
      mon.write((" "):rep(pw - 1))
    end
    local rows = { p.name, p.word, p.state, p.fuel }
    for r, t in ipairs(rows) do
      if r <= h then
        mon.setCursorPos(x0 + 1, r)
        mon.write(fit(t, pw - 2))
      end
    end
    mon.setBackgroundColour(colours.black)
  end
end

-- a tap on a strip: which drone's screen to show
function R.tap(mon, first, x, now, name)
  local w = mon.getSize()
  if R.pick and R.pickMon == name and (now or os.clock()) - R.pickAt < SHOW then R.pick = nil return end
  local c = math.floor((x - 1) / math.floor(w / RACK.perRow))
  local u = R.resident(first + math.min(RACK.perRow - 1, c))
  if u then R.pick, R.pickAt, R.pickMon = u.label, now or os.clock(), name end
end

if _G.RACK_TEST then return R end

---------------------------------------------------------------- running
local wired
for _, name in ipairs(peripheral.getNames()) do
  if peripheral.getType(name) == "modem" then
    local m = peripheral.wrap(name)
    if m.isWireless() then rednet.open(name) else wired = wired or m end
  end
end
if wired then wired.open(CHANNEL) end
print("Rack panels. Over the cable: " .. (wired and "yes" or "no") .. ".")

local function painter()
  while true do
    local high, low = R.monitors()
    if high then pcall(R.draw, peripheral.wrap(high), RACK.perRow, os.clock(), high) end
    if low then pcall(R.draw, peripheral.wrap(low), 0, os.clock(), low) end
    sleep(1)
  end
end

local function listener()
  while true do
    local ev, a, b, c, d = os.pullEvent()
    if ev == "modem_message" and b == CHANNEL and type(d) == "table" then
      if d.type == "cmd" and type(d.cmd) == "table" then
        local t = d.cmd.target
        if d.cmd.cmd == "reboot" and (t == "all" or t == os.getComputerLabel() or t == os.getComputerID()) then
          print("Rebooting (passed on by Crafty).")
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
      local high, low = R.monitors()
      if a == high then pcall(R.tap, peripheral.wrap(high), RACK.perRow, c, os.clock(), high)
      elseif low and (a == low or (a and a:find("monitor_", 1, true))) then
        pcall(R.tap, peripheral.wrap(low), 0, c, os.clock(), low)
      end
    end
  end
end

parallel.waitForAny(painter, listener)
