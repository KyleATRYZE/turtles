-- swarm.lua : shared helper. Lets a turtle or computer report its status
-- to the controller over its (ender) modem.
local M = {}

M.PROTOCOL = "swarm"

local opened = false

local function open()
  if opened then return true end
  local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
  if not modem then return false end
  rednet.open(peripheral.getName(modem))
  opened = true
  return true
end

M.open = open

-- Which version of the scripts this machine downloaded at boot.
function M.version()
  if not fs.exists(".version") then return "unknown" end
  local h = fs.open(".version", "r")
  local v = h.readAll()
  h.close()
  return v
end

-- A reboot order can name the exact version to download on the way back up.
function M.pinVersion(cmd)
  if type(cmd.rev) == "string" then
    local h = fs.open(".rev", "w")
    h.write(cmd.rev)
    h.close()
  end
end

-- When this program started (every report carries it: a start nobody
-- ordered is a turtle whose chunk went to sleep and came back).
local BOOTED = os.epoch and os.epoch("utc") or 0

-- Broadcast a status table. Does nothing if there is no wireless modem.
function M.report(status)
  if not open() then return false end
  status.id = os.getComputerID()
  status.label = os.getComputerLabel()
  status.time = os.epoch("utc")
  status.version = M.version()
  status.booted = BOOTED
  rednet.broadcast(status, M.PROTOCOL)
  return true
end

-- Boot heartbeat: "I am awake, and here", said the moment a program starts,
-- before the download and before anything else can go wrong. A turtle that
-- froze in a chunk nobody was keeping loaded restarts when the chunk comes
-- back: this is how it is found. (Said once per start: the updater and the
-- program it then runs both call this.)
function M.hello(role)
  if _G.SWARM_HELLO and os.clock() - _G.SWARM_HELLO < 60 then return false end
  if not open() then return false end
  _G.SWARM_HELLO = os.clock()
  local pos = { x = 0, y = 0, z = 0 }           -- (0, 0 = not known)
  local line = "Woke up (no GPS fix)."
  local ok, x, y, z = pcall(gps.locate, 2)
  if ok and x then
    pos = { x = math.floor(x + 0.5), y = math.floor(y + 0.5), z = math.floor(z + 0.5) }
    line = ("Woke up at %d %d %d."):format(pos.x, pos.y, pos.z)
  end
  local f = turtle and turtle.getFuelLevel() or nil
  return M.report({ role = role, state = "woke up", boot = true, pos = pos,
    fuel = f == "unlimited" and -1 or f, log = { line } })
end

---------------------------------------------------------------- own chunk loading
-- A turtle that carries a Chunk Controller (Advanced Peripherals) keeps its
-- own chunk loaded, so it cannot freeze when nobody is near. The controller
-- goes on the TOOL side, in place of the pickaxe, never on the modem side.
-- Worn, it loads the chunk the turtle is in; taken off, the chunk stays
-- loaded until it has gone unrefreshed for chunkLoadValidTime (600 seconds
-- as the mod ships). So: wear it whenever not digging (flying, waiting,
-- parked: C.keep does this), put the pickaxe back to dig (C.tool, before
-- every dig), and while digging put it on for a moment every HOLD seconds
-- and in every new chunk (C.touch). Only that last part leans on the chunk
-- staying loaded after the controller comes off: flying and waiting do not.
-- With no controller on board every function here does nothing.
M.chunky = {}
local C = M.chunky
C.ITEM = "advancedperipherals:chunk_controller"
C.HOLD = 180        -- seconds a chunk is trusted to stay loaded once the controller is off
C.IDLE = 6          -- seconds without a dig before the controller goes back on to stay

local function slotOf(match)
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and match(d.name) then return s end
  end
end
local function isCtl(n) return n == C.ITEM end
local function isPick(n) return n:find("pickaxe", 1, true) ~= nil end

-- The tool side: the one that does not hold the modem. Nil when that is not
-- clear (no modem, or two): then nothing is ever swapped.
function C.side()
  if not turtle then return nil end
  local l, r = peripheral.getType("left"), peripheral.getType("right")
  if l == "modem" and r ~= "modem" then return "right" end
  if r == "modem" and l ~= "modem" then return "left" end
  return nil
end

-- What we know, looked up at most every 20 seconds (and after every swap).
-- "Worn" = the pickaxe is in the inventory, the controller is not, and the
-- thing fitted is not a Geo Scanner. The controller shows as a peripheral a
-- moment after it goes on, so what this program did itself counts too (putOn).
local known = { at = -1000, has = false, worn = false }
local putOn               -- nil until the first look; then: did I put it on?
local swap
local function look(now)
  if not now and os.clock() - known.at < 20 then return known end
  known.at = os.clock()
  known.side = C.side()
  if not known.side then
    known.has, known.worn = false, false
    return known
  end
  local ctl, pick = slotOf(isCtl), slotOf(isPick)
  local fitted = peripheral.getType(known.side)
  local scanning = fitted ~= nil and tostring(fitted):lower():find("geo", 1, true) ~= nil
  local maybe = ctl == nil and pick ~= nil and not scanning
  if putOn == nil then
    if maybe and fitted == nil then
      -- just started, a pickaxe in the inventory and no telling what is
      -- fitted: put that pickaxe on and see what comes off
      swap(pick, known.side)
      ctl, pick = slotOf(isCtl), slotOf(isPick)
      maybe = false
    end
    putOn = maybe
  end
  known.worn = maybe and (putOn or fitted ~= nil)
  if not maybe then putOn = false end
  known.other = scanning
  known.has = known.worn or ctl ~= nil
  known.ctl, known.pick = ctl, pick
  return known
end

-- have(true) looks afresh (after being handed one, say)
function C.have(fresh) return turtle ~= nil and look(fresh).has end
function C.isWorn() return turtle ~= nil and look().worn end
-- Call after swapping a tool by other means (a scanner, a lab order).
function C.forget() known.at = -1000 end

local lastOn, lastChunk
local lastDig = -1000     -- when the pickaxe was last wanted (C.tool)

-- The order "chunky" with on = false stops a turtle wearing its controller
-- (kept in a file, so it holds across restarts); on = true starts it again.
local OFF_FILE = ".nochunky"
local off
function C.enabled()
  if off == nil then off = fs.exists(OFF_FILE) end
  return not off
end
function C.setEnabled(on)
  off = not on
  if on then
    if fs.exists(OFF_FILE) then fs.delete(OFF_FILE) end
  else
    local h = fs.open(OFF_FILE, "w")
    h.write("off")
    h.close()
  end
end

swap = function(slot, side)
  local sel = turtle.getSelectedSlot()
  turtle.select(slot)
  local ok
  if side == "left" then ok = turtle.equipLeft() else ok = turtle.equipRight() end
  turtle.select(sel)
  return ok
end

-- Put the controller on (the pickaxe goes into the inventory). True if it is on.
function C.wear()
  if not turtle then return false end
  local k = look(true)
  if k.worn then
    lastOn = os.clock()
    return true
  end
  if not C.enabled() then return false end
  if not k.ctl or k.other or not k.side then return false end
  if peripheral.getType(k.side) == "modem" then return false end     -- never the modem
  local ok = swap(k.ctl, k.side)
  if ok then putOn, lastOn = true, os.clock() end
  look(true)
  return ok and known.worn
end

-- Put the pickaxe back on (before digging). True if the pickaxe is on.
function C.tool()
  if not turtle then return true end
  lastDig = os.clock()
  if not look().worn then return true end           -- (cheap: called before every dig)
  local k = look(true)
  if not k.worn then return true end
  if not k.pick or peripheral.getType(k.side) == "modem" then return false end
  local ok = swap(k.pick, k.side)
  if ok then putOn = false end
  lastOn = os.clock()                     -- the chunk is good for a while from now
  look(true)
  return ok
end

-- For a turtle that works with the pickaxe on (the coal hunter, digging its
-- way along): when it enters a new chunk, or HOLD seconds have gone by, put
-- the controller on for a moment so that chunk is the loaded one. x, z =
-- where the turtle is. Cheap to call on every move.
function C.touch(x, z)
  if not turtle or not look().has then return false end
  local key = x and (math.floor(x / 16) .. "," .. math.floor(z / 16)) or lastChunk
  if lastOn and key == lastChunk and os.clock() - lastOn < C.HOLD then return false end
  if look(true).worn then
    lastOn, lastChunk = os.clock(), key
    return true
  end
  if not C.wear() then return false end
  -- the mod notes the chunk when the controller is attached to the computer
  -- and again as it ticks: give it a moment
  for _ = 1, 10 do
    if peripheral.getType(known.side) then break end
    sleep(0.1)
  end
  sleep(1)            -- (it looks at where it is every half second)
  C.tool()
  lastOn, lastChunk = os.clock(), key
  return true
end

-- The one call for a working turtle, after every move and in every report
-- (x, z = where it is). Not dug for a few seconds (flying, waiting, parked):
-- the controller goes on and stays on. Digging: the pickaxe stays on and
-- the controller is put on for a moment in each new chunk and every HOLD
-- seconds. Cheap when there is nothing to do.
function C.keep(x, z)
  if not turtle or not look().has then return false end
  local key = x and (math.floor(x / 16) .. "," .. math.floor(z / 16)) or lastChunk
  if look().worn then
    lastOn, lastChunk = os.clock(), key
    return true
  end
  if os.clock() - lastDig >= C.IDLE then
    if C.wear() then
      lastChunk = key
      return true
    end
    return false
  end
  return C.touch(x, z)
end

---------------------------------------------------------------- orders
-- Orders come from the controller (which reads them from GitHub).
-- Each has: id (number, always increasing), target, cmd.

M.CMD_PROTOCOL = "swarm_cmd"

local LAST_CMD_FILE = ".lastcmd"

local function lastCmd()
  if not fs.exists(LAST_CMD_FILE) then return 0 end
  local h = fs.open(LAST_CMD_FILE, "r")
  local n = tonumber(h.readAll())
  h.close()
  return n or 0
end

local function setLastCmd(id)
  local h = fs.open(LAST_CMD_FILE, "w")
  h.write(tostring(id))
  h.close()
end

-- Is this order addressed to this machine?
function M.forMe(cmd)
  local t = cmd.target
  if t == "all" or t == os.getComputerID() then return true end
  local label = os.getComputerLabel()
  return type(t) == "string" and label ~= nil and t:lower() == label:lower()
end

-- True the first time an order for this machine is seen; false for repeats.
local lastNonce
function M.accept(cmd)
  if type(cmd) ~= "table" then return false end
  -- A direct order: from the factory to this one machine (a chunk loader
  -- sent out with a miner, a builder's mate sent with fuel). It has no
  -- number in the controller's sequence; repeats are told by its nonce.
  if cmd.direct then
    if cmd.forId ~= os.getComputerID() or cmd.nonce == nil or cmd.nonce == lastNonce then return false end
    lastNonce = cmd.nonce
    return true
  end
  if type(cmd.id) ~= "number" then return false end
  if not M.forMe(cmd) or cmd.id <= lastCmd() then return false end
  setLastCmd(cmd.id)
  return true
end

---------------------------------------------------------------- the touch panels
-- The screens in the factory (screens.lua) give no orders: a tapped button
-- asks the controller, and the controller passes on only what is listed
-- here. Nothing in the list can lose anything: come home, carry on, say
-- how you are, and (as the map wall always could) builders stop building.
M.PANEL_PROTOCOL = "swarm_panel"
local function isBuilding(u)
  return u.role == "builder" or (u.role == "helper" and type(u.progress) == "table"
    and u.progress.kind == "building")
end
local PANEL_ASKS = {
  recall        = { cmd = "home",   all = true, words = "everyone home" },
  resume        = { cmd = "resume", all = true, words = "everyone carry on" },
  refresh       = { cmd = "ping",   all = true, words = "everyone report" },
  miners_home   = { cmd = "home",   who = function(u) return u.role == "miner" end, words = "miners home" },
  miners_resume = { cmd = "resume", who = function(u) return u.role == "miner" end, words = "miners carry on" },
  pause         = { cmd = "stop",   who = isBuilding, words = "builders stop" },
}

-- What a panel's request comes to: a list of { cmd =, target = } and a few
-- words for the chat and the panel; nil and the reason for anything else.
function M.panelOrders(ask, units)
  local a = type(ask) == "string" and PANEL_ASKS[ask]
  if not a then return nil, "not something a panel may ask" end
  if a.all then return { { cmd = a.cmd, target = "all" } }, a.words end
  local list, seen = {}, {}
  for _, u in pairs(units or {}) do
    if type(u) == "table" and type(u.label) == "string" and not seen[u.label] and a.who(u) then
      seen[u.label] = true
      list[#list + 1] = { cmd = a.cmd, target = u.label }
    end
  end
  table.sort(list, function(x, y) return x.target < y.target end)
  if #list == 0 then return nil, "nobody to tell" end
  return list, ("%s (%d)"):format(a.words, #list)
end

-- Block until a new order for this machine arrives.
function M.waitCommand()
  if not open() then
    while true do sleep(3600) end
  end
  while true do
    local _, msg = rednet.receive(M.CMD_PROTOCOL)
    if M.accept(msg) then return msg end
  end
end

-- Run task() while listening for orders.
-- inline(cmd) may handle an order without interrupting the task (return true).
-- Returns the order that interrupted the task, or nil if the task finished.
function M.runWithCommands(task, inline)
  local cmd
  parallel.waitForAny(function()
    while true do
      local c = M.waitCommand()
      if c.cmd == "chunky" then
        -- wear the Chunk Controller on board (or, with on=0, stop): no need
        -- to stop work. (Orders written by hand carry numbers and words.)
        local on = c.on
        C.setEnabled(not (on == false or on == 0 or on == "0" or on == "false" or on == "off"))
      elseif not (inline and inline(c)) then
        cmd = c
        return
      end
    end
  end, task)
  return cmd
end

return M
