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

-- Broadcast a status table. Does nothing if there is no wireless modem.
function M.report(status)
  if not open() then return false end
  status.id = os.getComputerID()
  status.label = os.getComputerLabel()
  status.time = os.epoch("utc")
  rednet.broadcast(status, M.PROTOCOL)
  return true
end

return M
