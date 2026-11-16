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

-- Broadcast a status table. Does nothing if there is no wireless modem.
function M.report(status)
  if not open() then return false end
  status.id = os.getComputerID()
  status.label = os.getComputerLabel()
  status.time = os.epoch("utc")
  status.version = M.version()
  rednet.broadcast(status, M.PROTOCOL)
  return true
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
function M.accept(cmd)
  if type(cmd) ~= "table" or type(cmd.id) ~= "number" then return false end
  if not M.forMe(cmd) or cmd.id <= lastCmd() then return false end
  setLastCmd(cmd.id)
  return true
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
      if not (inline and inline(c)) then
        cmd = c
        return
      end
    end
  end, task)
  return cmd
end

return M
