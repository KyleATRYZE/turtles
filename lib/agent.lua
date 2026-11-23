--- lib/agent.lua: a small remote "dev agent" so code can be tried on a live computer
-- and the output comes back, without walking over to it.
--
-- Orders (tables) it understands:
--   { cmd = "exec",   code = "return turtle.getFuelLevel()" }   run a Lua snippet
--   { cmd = "run",    path = "miner.lua", args = { "8" } }      run a program file
--   { cmd = "ping" }                                             id, label, fuel, free disk...
--   { cmd = "tail",   lines = 20, name = "miner" }               last lines of /logs/<name>.log
--   { cmd = "dump" }                                             every peripheral + its methods
--   { cmd = "reboot" }                                           reply, then reboot
-- Each returns a result table: { id, cmd, ok, out (printed text), ret (returned values),
-- err, ms, from (computer id), label }.
--
-- Two ways in (both need the shared secret, because anyone can send them):
--   agent.serveRednet()     on any computer/turtle: orders arrive over rednet
--   agent.serveCommands()   on a COMMAND computer: orders arrive from
--                           /computercraft queue #<id> <secret> <cmd> ...
--                           (only command computers get this event; any player can send it)
-- A command computer can pass an order on:  ... <secret> relay <targetId> <cmd> ...
--
--   local agent = require("lib.agent")
--   agent.setup({ secret = "long-random-text", onResult = function(r) swarm.report({ dev = r }) end })
--   parallel.waitForAny(main, agent.serveRednet)

local M = {}

local cfg = {
  secret = nil,            -- REQUIRED for serveRednet/serveCommands (refuses to run without)
  protocol = "dev_agent",
  maxOutput = 4000,        -- characters of printed output kept per order
  timeout = 15,            -- seconds a relay waits for the target's answer
  allow = { exec = true, run = true, ping = true, tail = true, dump = true, reboot = true },
  logDir = "/logs",
  onResult = nil,          -- function(result): forward results somewhere you can read them
  status = nil,            -- function() -> table: extra fields for "ping"
}

function M.setup(opts)
  for k, v in pairs(opts or {}) do cfg[k] = v end
end

local pack = table.pack or function(...) return { n = select("#", ...), ... } end
local unpack = table.unpack or unpack

local function now()
  return os.epoch and os.epoch("utc") or math.floor(os.clock() * 1000)
end

local function ser(v)
  local ok, s = pcall(textutils.serialize, v)
  return ok and s or tostring(v)
end

-- An environment whose print/write go into a buffer instead of the screen.
local function capture()
  local buf, size, cut = {}, 0, false
  local function add(s)
    if size >= cfg.maxOutput then cut = true return end
    buf[#buf + 1] = s
    size = size + #s
  end
  local env = setmetatable({}, { __index = _ENV or _G })
  env.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    add(table.concat(parts, "\t") .. "\n")
  end
  env.write = function(s) add(tostring(s)) end
  return env, function()
    local s = table.concat(buf)
    if #s > cfg.maxOutput then s = s:sub(1, cfg.maxOutput) cut = true end
    return cut and (s .. "\n...(output cut)") or s
  end
end

local function runFn(res, fn, ...)
  local r = pack(pcall(fn, ...))
  res.ok = r[1]
  if r[1] then
    if r.n > 1 then res.ret = ser({ unpack(r, 2, r.n) }) end
  else
    res.err = tostring(r[2])
  end
end

local function readTail(path, n)
  if not fs.exists(path) then return nil end
  local h = fs.open(path, "r")
  local lines = {}
  while true do
    local l = h.readLine()
    if not l then break end
    lines[#lines + 1] = l
    if #lines > n then table.remove(lines, 1) end
  end
  h.close()
  return table.concat(lines, "\n")
end

local function dumpPeripherals()
  local out = {}
  for _, name in ipairs(peripheral.getNames()) do
    local types = { peripheral.getType(name) }
    local methods = peripheral.getMethods(name) or {}
    table.sort(methods)
    out[#out + 1] = { name = name, types = types, methods = methods }
  end
  return out
end

--- Run one order and return the result table. Never throws.
---@param order table
---@return table result
function M.handle(order)
  local t0 = now()
  local res = { id = order.id, cmd = order.cmd, from = os.getComputerID(), label = os.getComputerLabel() }
  if not cfg.allow[order.cmd] then
    res.ok, res.err = false, "unknown or not allowed: " .. tostring(order.cmd)
    return res
  end
  local env, output = capture()
  if order.cmd == "exec" then
    local fn, err = load(order.code or "", "=exec", "t", env)
    if fn then runFn(res, fn) else res.ok, res.err = false, err end
  elseif order.cmd == "run" then
    local path = order.path and (shell and shell.resolveProgram and shell.resolveProgram(order.path) or order.path)
    local fn, err = path and loadfile(path, "t", env)
    if fn then runFn(res, fn, unpack(order.args or {})) else res.ok, res.err = false, err or "no such program" end
  elseif order.cmd == "ping" then
    res.ok = true
    res.ret = ser({
      host = _HOST,
      fuel = turtle and turtle.getFuelLevel() or nil,
      freeDisk = fs.getFreeSpace("/"),
      uptime = os.clock(),
      extra = cfg.status and cfg.status() or nil,
    })
  elseif order.cmd == "tail" then
    local text = readTail(cfg.logDir .. "/" .. (order.name or "program") .. ".log", order.lines or 20)
    res.ok = text ~= nil
    if text then env.write(text) else res.err = "no log called " .. tostring(order.name) end
  elseif order.cmd == "dump" then
    res.ok = true
    res.ret = ser(dumpPeripherals())
  elseif order.cmd == "reboot" then
    res.ok, res.after = true, "reboot"
  end
  res.out = output()
  res.ms = now() - t0
  return res
end

--- Turn /computercraft queue arguments into an order (checks the secret).
---@param args string[]
---@return table? order
---@return string? err
function M.fromArgs(args, skipSecret)
  local i = 1
  if not skipSecret then
    if not cfg.secret then return nil, "no secret set: refusing" end
    if args[1] ~= cfg.secret then return nil, "bad secret" end
    i = 2
  end
  local cmd = args[i]
  local rest = { unpack(args, i + 1) }
  local order = { cmd = cmd, id = tostring(now()) }
  if cmd == "exec" then
    order.code = table.concat(rest, " ")
  elseif cmd == "run" then
    order.path, order.args = rest[1], { unpack(rest, 2) }
  elseif cmd == "tail" then
    order.lines, order.name = tonumber(rest[1]) or 20, rest[2]
  elseif cmd == "relay" then
    order.target = tonumber(rest[1]) or rest[1]
    order.order = M.fromArgs({ unpack(rest, 2) }, true)
    if order.order then order.order.id = order.id end
  end
  return order
end

local function deliver(res)
  pcall(function()
    if not fs.exists(cfg.logDir) then fs.makeDir(cfg.logDir) end
    local h = fs.open(cfg.logDir .. "/agent-last.txt", "w")
    h.write(ser(res))
    h.close()
  end)
  if cfg.onResult then pcall(cfg.onResult, res) end
end
M.deliver = deliver

--- Send an order to another computer's agent over rednet and wait for its result.
---@return table result
function M.send(target, order, timeout)
  order.id = order.id or tostring(now())
  rednet.send(target, { secret = cfg.secret, order = order }, cfg.protocol)
  local deadline = os.clock() + (timeout or cfg.timeout)
  while os.clock() < deadline do
    local from, msg = rednet.receive(cfg.protocol, deadline - os.clock())
    if from == target and type(msg) == "table" and msg.result and msg.result.id == order.id then
      return msg.result
    end
  end
  return { id = order.id, cmd = order.cmd, ok = false, err = "no answer from " .. tostring(target) }
end

--- Serve orders that arrive over rednet. Needs an open modem (rednet.open).
-- `limit` = stop after that many messages (for tests); nil = forever.
function M.serveRednet(limit)
  if not cfg.secret then error("lib.agent: set a secret before serving", 2) end
  local n = 0
  while not limit or n < limit do
    local from, msg = rednet.receive(cfg.protocol)
    n = n + 1
    if type(msg) == "table" and msg.order and msg.secret == cfg.secret then
      local res = M.handle(msg.order)
      rednet.send(from, { result = res }, cfg.protocol)
      deliver(res)
      if res.after == "reboot" then os.reboot() end
    end
  end
end

--- Serve /computercraft queue orders (COMMAND computers only).
-- Example from RCON:  computercraft queue #12 <secret> exec "print(1+1)"
function M.serveCommands(limit)
  if not cfg.secret then error("lib.agent: set a secret before serving", 2) end
  local n = 0
  while not limit or n < limit do
    local ev = pack(os.pullEvent("computer_command"))
    n = n + 1
    local order, err = M.fromArgs({ unpack(ev, 2, ev.n) })
    local res
    if not order then
      res = { ok = false, err = err }
    elseif order.cmd == "relay" then
      res = order.order and M.send(order.target, order.order) or { ok = false, err = "bad relay order" }
    else
      res = M.handle(order)
    end
    deliver(res)
    if res.after == "reboot" then os.reboot() end
  end
end

--- Optional result sink for a command computer: stores the last result as JSON in
-- command storage, readable over RCON with:  data get storage cc:agent last
-- [unverified on your server] Needs the `commands` API, which CC only enables when the
-- server allows command blocks (enable-command-block=true).
function M.storageSink(key)
  return function(res)
    if not commands then return end
    local json = textutils.serializeJSON(res)
    if #json > 30000 then json = json:sub(1, 30000) end
    local snbt = "'" .. json:gsub("\\", "\\\\"):gsub("'", "\\'") .. "'"
    commands.exec("data modify storage cc:agent " .. (key or "last") .. " set value " .. snbt)
  end
end

return M
