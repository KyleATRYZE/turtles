--- lib/net.lua: talking to the controller. Status reports out, orders in, plots on request.
--
--   local net = require("lib.net")
--   net.open()                                        -- false when there is no wireless modem
--   net.report({ role = "miner", state = "mining", fuel = 900, pos = { x = 1, y = 2, z = 3 } })
--   local order = net.nextOrder(1)                    -- an order for this machine, or nil
--   local job = net.requestJob()                      -- a plot from the controller, or nil
--
-- The message shapes are the ones the controller already speaks (protocols "swarm",
-- "swarm_cmd" and "swarm_job"), so this replaces the old swarm.lua on turtles without
-- the controller noticing.

local M = {}

M.PROTOCOL = "swarm"          -- status reports, broadcast
M.CMD_PROTOCOL = "swarm_cmd"  -- orders from the controller
M.JOB_PROTOCOL = "swarm_job"  -- plots: need_job / job / job_done

local LAST_CMD_FILE = ".lastcmd"
local opened = false
local BOOTED = os.epoch and os.epoch("utc") or 0

local function readFile(path)
  if not fs.exists(path) then return nil end
  local h = fs.open(path, "r")
  local s = h.readAll()
  h.close()
  return s
end

local function writeFile(path, text)
  local h = fs.open(path, "w")
  h.write(text)
  h.close()
end

--- Open rednet on the wireless modem. Returns false if this machine has none.
function M.open()
  if opened then return true end
  for _, name in ipairs(peripheral.getNames()) do
    local isModem = false
    for _, t in ipairs({ peripheral.getType(name) }) do
      if t == "modem" then isModem = true end
    end
    if isModem then
      local ok, wireless = pcall(peripheral.call, name, "isWireless")
      if ok and wireless then
        rednet.open(name)
        opened = true
        return true
      end
    end
  end
  return false
end

--- Which version of the scripts this machine downloaded at boot.
function M.version()
  return (readFile(".version") or "unknown"):gsub("%s", "")
end

--- Broadcast a status table to the controller. Returns false with no modem.
---@param status table at least { role = ..., state = ... }
function M.report(status)
  if not M.open() then return false end
  status.id = os.getComputerID()
  status.label = os.getComputerLabel()
  status.time = os.epoch and os.epoch("utc") or 0
  status.version = M.version()
  status.booted = BOOTED
  rednet.broadcast(status, M.PROTOCOL)
  return true
end

local function forMe(cmd)
  local t = cmd.target
  if t == "all" or t == os.getComputerID() then return true end
  local label = os.getComputerLabel()
  return type(t) == "string" and label ~= nil and t:lower() == label:lower()
end

--- True the first time an order for this machine is seen; false for repeats and for
-- orders meant for others. (Orders carry a rising number; the last one taken is kept
-- in .lastcmd, so a reboot never runs an old order again.)
function M.accept(cmd)
  if type(cmd) ~= "table" or type(cmd.id) ~= "number" or type(cmd.cmd) ~= "string" then return false end
  if not forMe(cmd) then return false end
  if cmd.id <= (tonumber(readFile(LAST_CMD_FILE) or "") or 0) then return false end
  writeFile(LAST_CMD_FILE, tostring(cmd.id))
  return true
end

--- Wait up to `timeout` seconds for an order addressed to this machine.
---@return table? order
function M.nextOrder(timeout)
  if not M.open() then
    sleep(timeout or 1)
    return nil
  end
  local _, msg = rednet.receive(M.CMD_PROTOCOL, timeout)
  if M.accept(msg) then return msg end
  return nil
end

--- A reboot order can name the exact version to download on the way back up.
function M.pinVersion(cmd)
  if type(cmd.rev) == "string" and #cmd.rev == 40 and cmd.rev:match("^%x+$") then
    writeFile(".rev", cmd.rev)
  end
end

--- Ask the controller for a plot. Returns the job message, or nil if none came in `wait` seconds.
---@return table? job { index, x0, z0, size, topY, bottom, dock, exit1, exit2 }
function M.requestJob(wait)
  if not M.open() then return nil end
  local me = os.getComputerID()
  rednet.broadcast({ type = "need_job", id = me }, M.JOB_PROTOCOL)
  local deadline = os.clock() + (wait or 5)
  while os.clock() < deadline do
    local _, msg = rednet.receive(M.JOB_PROTOCOL, 1)
    if type(msg) == "table" and msg.type == "job" and msg.forId == me then return msg end
  end
  return nil
end

--- Tell the controller a plot is finished, so the next request gets a new one.
function M.jobDone(index)
  if not M.open() then return false end
  rednet.broadcast({ type = "job_done", id = os.getComputerID(), index = index }, M.JOB_PROTOCOL)
  return true
end

return M
