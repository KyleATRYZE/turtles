-- swarm.lua : shared helper. Lets a turtle or computer report its status
-- to the controller over its (ender) modem.
local M = {}

M.PROTOCOL = "swarm"

---------------------------------------------------------------- names
-- The swarm has been renamed twice: first to shorter names (Minecraft puns),
-- then to plain task names (builder1, lava1, crafter1, ...), so it is clear
-- who does what while many jobs run at once. This is the one place the old
-- names appear: old name -> new name (a name from the first renaming goes
-- straight to its newest name). Every turtle and computer renames itself
-- when this file is loaded (see M.rename, at the end of the file): its
-- label, and every name saved in its state files. A turtle that wakes weeks
-- later does it on its first start.
-- Until all are renamed, a name means the same machine under either name:
-- orders addressed to an old name are obeyed (M.forMe), and anything filed
-- by name is filed under M.nameKey, which is the same for both.
M.RENAMES = {
  -- the base
  GroundControl = "CommandBlock", ForgeClooney = "crafter1", Crafty = "crafter1",
  Counter = "crafter2", BrickJagger = "mapper1", BlockParty = "mapper1",
  -- builder's mates (helpers), by duty
  MortarKombat = "lava1", Pushy = "lava1", SteelyDan = "foundry1", DropIt = "foundry1",
  WallStreet = "builder1", HopTo = "builder1", OnRepeat = "builder2", Sticky = "builder3",
  Dusty = "builder4", ButtonUp = "builder5", Observant = "builder6",
  TimberLake = "builder7", LeverAlone = "builder7",
  Comparable = "survey1", Dispensable = "rescue1",
  -- chunk loaders (the last six were names waiting for loaders not yet built)
  ChunkNorris = "Ghastly", LoadRunner = "Phantastic", ChunkBerry = "Ablaze",
  ChunkyMonkey = "Vexed", LoadZeppelin = "Beehave", ChunkSinatra = "Batty",
  LoadOfTheRings = "Breezy", ChunkDaddy = "AllayOop", HeavyLoad = "WitherOrNot",
  -- coal hunters
  CoalPorter = "Coalition", NatKingCoal = "miner3", Charcool = "miner3",
  -- miners
  OreLando = "Oresome", ElvisPitsley = "Pickle", BoulderDash = "Cobbler",
  QuarryStyles = "CleanSlate", ObiWanKenOrebi = "Granted",
  OreSonWelles = "Bedrocker",
  -- names miners used to pick by computer number (none in use; a miner
  -- built before the change-over may carry one)
  ShaftPunk = "Ironic", PickJagger = "InVein", DrillMurray = "MotherLode",
  RockLobster = "NetherMind", DigDug = "DigIt", TunnelVision = "Dioright",
  MinerThreat = "Andesight", DiggyStardust = "Calcited", LeonardoDigCaprio = "Gravelly",
  IndianaStones = "Flinty", DwayneTheBlock = "CopperTop", GoldieHaul = "GoldRush",
  PitStop = "Basalty", VeinDiesel = "RockSolid", SlateWinslet = "Quartzy",
  GraniteDavis = "Smelty", CobbleWobble = "LapisLazy", MoleDiggins = "Dripstoned",
  DeepPurple = "GeodeToGo", StoneCold = "Nuggety",
}
-- Old names two machines shared (two miners took the same name from the
-- list by computer number): which new name by computer number. Only a
-- machine's own label (and an order addressed to it) can be told apart by
-- number; elsewhere such a name is left as it is.
M.RENAMES_BY_ID = {
  TuffLuck = { [40] = "miner1", [12] = "miner2" },
  NotoriousDIG = { [40] = "miner1", [12] = "miner2" },
}
local OLD_NAMES = {}                  -- old name, lower case -> new name
for old, new in pairs(M.RENAMES) do OLD_NAMES[old:lower()] = new end
local OLD_BY_ID = {}                  -- old name, lower case -> { [id] = new name }
for old, ids in pairs(M.RENAMES_BY_ID) do OLD_BY_ID[old:lower()] = ids end
-- (a word the programs also use as itself: "counter" is the assistant
-- crafter's role in its reports. In a state file only the name, spelt
-- as a name, is renamed.)
local WORDS = { counter = true }

-- The name a machine goes by now (given its old or its new name, any case
-- for an old one). With the machine's number, a name two machines shared
-- is told apart too. Anything that is not an old name comes back unchanged.
function M.newName(name, id)
  if type(name) ~= "string" then return name end
  local low = name:lower()
  local ids = OLD_BY_ID[low]
  if ids and id ~= nil and ids[tonumber(id)] then return ids[tonumber(id)] end
  return OLD_NAMES[low] or name
end

-- What a name is filed under: the same for a machine's old and new names,
-- whatever the case.
function M.nameKey(name, id)
  return tostring(M.newName(name, id)):lower()
end

-- Do two names mean the same machine? (id: the number of the machine the
-- second name is, to tell a shared old name apart)
function M.sameName(a, b, id)
  if type(a) ~= "string" or type(b) ~= "string" then return false end
  return M.nameKey(a) == M.nameKey(b) or (id ~= nil and M.nameKey(a, id) == M.nameKey(b, id))
end

-- Is this name in a list kept by name (a set: name -> true, as the haul and
-- lava farm skip lists are)? Names saved under an old name still count.
-- id: the machine's number (for a shared old name).
function M.listed(set, name, id)
  if type(set) ~= "table" or type(name) ~= "string" then return false end
  if set[name] then return true end
  for k, v in pairs(set) do
    if v and type(k) == "string" and M.sameName(k, name, id) then return true end
  end
  return false
end

-- Old names -> new names all through a table (a state file): values that
-- are exactly an old name, and keys that are. Returns true if anything changed.
local function renameDeep(t, seen)
  seen = seen or {}
  if seen[t] then return false end
  seen[t] = true
  local changed, rekey = false, nil
  for k, v in pairs(t) do
    if type(v) == "table" then
      if renameDeep(v, seen) then changed = true end
    elseif type(v) == "string" and OLD_NAMES[v:lower()] and not WORDS[v] then
      t[k] = OLD_NAMES[v:lower()]
      changed = true
    end
    if type(k) == "string" and OLD_NAMES[k:lower()] and not WORDS[k] then
      rekey = rekey or {}
      rekey[#rekey + 1] = k
    end
  end
  for _, k in ipairs(rekey or {}) do
    local new = OLD_NAMES[k:lower()]
    if t[new] == nil then t[new] = t[k] end
    t[k] = nil
    changed = true
  end
  return changed
end
M.renameIn = renameDeep

-- The files a machine keeps its work in (whichever of them it has).
M.STATE_FILES = { "miner.state", "helper.state", "loader.state", "builder.state", ".plots", ".foundry" }

-- Rename this machine: its label, and the names in its state files. Safe to
-- call any number of times (the second time there is nothing left to do).
-- Returns the old label if the label changed.
function M.rename()
  local was
  if os.getComputerLabel and os.setComputerLabel then
    local label = os.getComputerLabel()
    local new = M.newName(label, os.getComputerID and os.getComputerID())
    if label and new ~= label then
      os.setComputerLabel(new)
      was = label
    end
  end
  if fs and textutils and textutils.unserialize and textutils.serialize then
    for _, file in ipairs(M.STATE_FILES) do
      if fs.exists(file) then
        local h = fs.open(file, "r")
        local text = h and h.readAll()
        if h then h.close() end
        local t = type(text) == "string" and textutils.unserialize(text) or nil
        if type(t) == "table" and renameDeep(t) then
          h = fs.open(file, "w")
          h.write(textutils.serialize(t))
          h.close()
        end
      end
    end
  end
  return was
end

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
  if status.screen == nil and _G.SCREEN_MIRROR then
    local ok, lines = pcall(_G.SCREEN_MIRROR, 12)
    if ok then status.screen = lines end
  end
  if fs.exists(".update_log") then
    local h = fs.open(".update_log", "r")
    local u = h.readAll()
    h.close()
    if u ~= "" then status.update = u:sub(1, 600) end
  end
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

-- Is this order addressed to this machine? (By its number, or its name:
-- the old name or the new one, in any case.)
function M.forMe(cmd)
  local t = cmd.target
  if t == "all" or t == os.getComputerID() then return true end
  local label = os.getComputerLabel()
  return type(t) == "string" and label ~= nil and M.sameName(t, label, os.getComputerID())
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
---------------------------------------------------------------- rebase
-- The order "rebase": the factory (Crafty and its launch pad) has moved.
-- Every drone keeps where the base is in ".base", written once when it was
-- drafted, so on this order it asks the factory where it is now, keeps
-- that (with the heights the order gives: hover=<blocks above Crafty that
-- helpers wait at>, hop=<a loader's short hop>, door=x,y,z for the builder),
-- brings the base's cells in its saved state up to date, and restarts.
-- Machines without a ".base" (the factory, the storage and screen
-- computers) take no notice.
local BASE_CELLS = { "dock", "exit1", "exit2" }

-- The drone lane along the factory's back wall (docs/factory-retrofit.md),
-- in world coordinates: drones fly it at y; the back track (z back) runs
-- west, the front track (z front) east, between the gates at x west and x
-- east. A drone comes down outside a gate (westIn: in on the front track;
-- eastIn: in on the back track) and leaves by eastOut. Rack 1's homes:
-- x rackX + i % perRow, low (y low) then high (y high), at z rackZ.
-- A rebase order with lane=1 puts this in .base (base.lane); lane=0 takes
-- it out again.
M.LANE = { y = 73, back = 1519, front = 1520, west = -4448, east = -4404,
  westIn = { x = -4451, z = 1520 }, eastIn = { x = -4402, z = 1519 }, eastOut = { x = -4402, z = 1520 },
  rackX = -4429, rackZ = 1521, low = 72, high = 74, perRow = 8,
  rows = { 72, 74 } }   -- (rack 1 is 4 rows of 8 now: rows 3 and 4 go in once the surveyor has placed them)
local STATE_FILES = { "miner.state", "helper.state", "loader.state", "builder.state" }

local function readTable(file)
  if not fs.exists(file) then return nil end
  local h = fs.open(file, "r")
  local t = textutils.unserialize(h.readAll() or "")
  h.close()
  return type(t) == "table" and t or nil
end

local function writeTable(file, t)
  local h = fs.open(file, "w")
  h.write(textutils.serialize(t))
  h.close()
end

function M.rebase(c, tries)
  if not fs.exists(".base") then return false, "no .base here" end
  if not open() then return false, "no wireless modem" end
  local got
  for _ = 1, tries or 6 do
    rednet.broadcast({ type = "base_request" }, "swarm_job")
    local untilT = os.clock() + 5
    while not got and os.clock() < untilT do
      local _, msg = rednet.receive("swarm_job", 1)
      if type(msg) == "table" and msg.type == "base" and type(msg.base) == "table"
        and type(msg.base.f) == "table" and type(msg.base.pad) == "table" then
        got = msg.base
      end
    end
    if got then break end
  end
  if not got then return false, "the factory did not answer" end
  local old = readTable(".base") or {}
  local base = {}
  for k, v in pairs(got) do base[k] = v end
  base.hoverUp = tonumber(c.hover) or old.hoverUp
  base.hopUp = tonumber(c.hop) or old.hopUp
  if type(c.door) == "string" then
    local x, y, z = c.door:match("^(-?%d+),(-?%d+),(-?%d+)$")
    if x then base.door = { x = tonumber(x), y = tonumber(y), z = tonumber(z) } end
  end
  base.door = base.door or old.door
  if c.lane ~= nil then
    if tonumber(c.lane) == 1 or c.lane == true then
      base.lane = {}
      for k, v in pairs(M.LANE) do base.lane[k] = v end
    else
      base.lane = nil
    end
  else
    base.lane = old.lane
  end
  writeTable(".base", base)
  for _, file in ipairs(STATE_FILES) do
    local st = readTable(file)
    if st then
      -- a miner's plot grid stays where it was laid out: it was measured
      -- from the old exit1
      if file == "miner.state" and st.exit1 and not st.origin then st.origin = st.exit1 end
      for _, k in ipairs(BASE_CELLS) do
        if st[k] ~= nil and base[k] then st[k] = base[k] end
      end
      -- the builder's map of the old base room and its way in
      st.roomCells, st.padKey, st.door, st.doorX, st.doorZ = nil, nil, nil, nil, nil
      writeTable(file, st)
    end
  end
  return true, ("base now at %d %d %d"):format(base.f.x, base.f.y, base.f.z)
end

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
      elseif inline and inline(c) then
        -- (handled by the program itself)
      elseif c.cmd == "rebase" then
        local ok, why = M.rebase(c)
        print("Rebase: " .. tostring(why))
        if ok then
          sleep(1)
          os.reboot()
        end
      else
        cmd = c
        return
      end
    end
  end, task)
  return cmd
end

-- Every machine takes its new name as it starts (see "names" above).
do
  local ok, was = pcall(M.rename)
  if ok and was then print("I am " .. tostring(os.getComputerLabel()) .. " now (was " .. was .. ").") end
end

return M
