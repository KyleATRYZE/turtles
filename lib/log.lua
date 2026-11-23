--- lib/log.lua: logging, crash reports and a stall watchdog.
--
--   local log = require("lib.log")
--   log.setup({ name = "miner" })
--   log.run(function(...)            -- crash-safe main
--     log.info("starting, %d blocks to go", 64)
--     ...
--   end, ...)
--
-- Writes /logs/<name>.log (rolled over at maxBytes to <name>.log.old) and, if the program
-- crashes, /logs/crash.txt with the error, the traceback and the last log lines.
-- Set onLine / onCrash to also send them somewhere (rednet, the controller, a chat box).

local M = {}

local cfg = {
  name = "program",
  dir = "/logs",
  maxBytes = 32000,
  echo = true,         -- also print to the terminal
  keep = 30,           -- recent lines kept in memory for crash reports
  onLine = nil,        -- function(level, line)
  onCrash = nil,       -- function(report)
}
local recent = {}
M.progressAt = 0

local function now()
  if os.epoch then return os.epoch("utc") end
  return math.floor(os.clock() * 1000)
end

local function stamp()
  local ok, s = pcall(os.date, "!%H:%M:%S")
  return ok and s or tostring(now())
end

local function path() return cfg.dir .. "/" .. cfg.name .. ".log" end

local function append(file, line)
  if not fs.exists(cfg.dir) then fs.makeDir(cfg.dir) end
  if fs.exists(file) and fs.getSize(file) > cfg.maxBytes then
    if fs.exists(file .. ".old") then fs.delete(file .. ".old") end
    fs.move(file, file .. ".old")
  end
  local h = fs.open(file, "a")
  if h then
    h.writeLine(line)
    h.close()
  end
end

--- Configure. Any field of cfg above can be set.
---@param opts table
function M.setup(opts)
  for k, v in pairs(opts or {}) do cfg[k] = v end
  M.progress()
end

local function write(level, fmt, ...)
  local msg = select("#", ...) > 0 and string.format(fmt, ...) or tostring(fmt)
  local line = stamp() .. " " .. level .. " " .. msg
  recent[#recent + 1] = line
  if #recent > cfg.keep then table.remove(recent, 1) end
  pcall(append, path(), line)
  if cfg.echo then print(line) end
  if cfg.onLine then pcall(cfg.onLine, level, line) end
  return line
end

function M.info(fmt, ...) return write("INFO", fmt, ...) end
function M.warn(fmt, ...) return write("WARN", fmt, ...) end
function M.error(fmt, ...) return write("ERROR", fmt, ...) end

--- The last n log lines (newest last).
---@param n? integer
---@return string[]
function M.recent(n)
  n = n or #recent
  local out = {}
  for i = math.max(1, #recent - n + 1), #recent do out[#out + 1] = recent[i] end
  return out
end

--- Mark that the program made progress (moved, crafted, delivered...). Used by watchdog().
function M.progress() M.progressAt = now() end

--- Run main(...) and turn any crash into a report instead of a dead turtle with no trace.
-- Returns true, results... on success, or false, err.
---@param main function
function M.run(main, ...)
  local args = table.pack and table.pack(...) or { n = select("#", ...), ... }
  local unpack = table.unpack or unpack
  local results
  local ok, err = xpcall(function()
    results = table.pack and table.pack(main(unpack(args, 1, args.n)))
      or { main(unpack(args, 1, args.n)) }
  end, function(e)
    local tb = debug and debug.traceback and debug.traceback(tostring(e), 2) or tostring(e)
    return tb
  end)
  if ok then return true, unpack(results, 1, results.n or #results) end

  -- "Terminated" is the user pressing Ctrl+T: log it, but it is not a crash
  if tostring(err):find("Terminated", 1, true) then
    write("WARN", "terminated by user")
    return false, "Terminated"
  end
  local report = {
    program = cfg.name,
    id = os.getComputerID and os.getComputerID() or nil,
    label = os.getComputerLabel and os.getComputerLabel() or nil,
    time = now(),
    error = tostring(err),
    recent = M.recent(),
  }
  write("ERROR", "CRASH: %s", (tostring(err):gsub("\n.*", "")))
  pcall(function()
    if not fs.exists(cfg.dir) then fs.makeDir(cfg.dir) end
    local h = fs.open(cfg.dir .. "/crash.txt", "w")
    h.write(textutils.serialize(report))
    h.close()
  end)
  if cfg.onCrash then pcall(cfg.onCrash, report) end
  return false, err
end

--- A loop to run next to your program with parallel.waitForAny. If log.progress() has not
-- been called for `limit` seconds, onStuck(secondsIdle, lastLine) is called (once per stall).
-- This catches "running but going nowhere", which a silence check on its own does not.
---@param limit number seconds
---@param onStuck fun(idle: number, last: string?)
---@param checkEvery? number seconds (default 10)
---@param maxChecks? integer stop after this many checks (for tests); nil = forever
function M.watchdog(limit, onStuck, checkEvery, maxChecks)
  return function()
    local warned, checks = false, 0
    while not maxChecks or checks < maxChecks do
      checks = checks + 1
      sleep(checkEvery or 10)
      local idle = (now() - M.progressAt) / 1000
      if idle >= limit then
        if not warned then
          warned = true
          local last = recent[#recent]
          write("WARN", "no progress for %d s", math.floor(idle))
          pcall(onStuck, idle, last)
        end
      else
        warned = false
      end
    end
  end
end

return M
