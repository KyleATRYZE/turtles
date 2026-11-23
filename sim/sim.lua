--- sim/sim.lua: a small fake CC:Tweaked world for testing programs outside Minecraft.
--
-- It installs the globals a turtle program uses (turtle, gps, fs, os.*, textutils,
-- peripheral, rednet, sleep) into _G, backed by a table you control:
--
--   dofile("sim/sim.lua")
--   SIM.reset({ fuel = 500 })
--   SIM.block(0, 64, -1, "minecraft:stone")      -- put a block north of the turtle
--   local move = require("lib.move")
--   move.set(0, 64, 0, "north")
--   assert(move.forward())                        -- digs the stone, moves
--   assert(SIM.t.z == -1)
--
-- Coordinates are world coordinates. Facing: 0 north (-z), 1 east, 2 south, 3 west.
-- Behaviour copies CC where it matters for tests: error strings, fuel use, falling
-- gravel/sand, "Cannot leave loaded world", item stacking from the selected slot.
-- Runs on plain Lua 5.1-5.4 and LuaJIT (lupa). Not a full emulator: for real CC behaviour
-- use craftos-mcp or CraftOS-PC (see docs/04).

SIM = {}

local DX = { [0] = 0, [1] = 1, [2] = 0, [3] = -1 }
local DZ = { [0] = -1, [1] = 0, [2] = 1, [3] = 0 }
local function key(x, y, z) return x .. "," .. y .. "," .. z end

SIM.FUEL = {
  ["minecraft:coal"] = 80, ["minecraft:charcoal"] = 80, ["minecraft:coal_block"] = 800,
  ["minecraft:lava_bucket"] = 1000, ["minecraft:blaze_rod"] = 120,
}
SIM.FALLS = { ["minecraft:gravel"] = true, ["minecraft:sand"] = true, ["minecraft:red_sand"] = true }
SIM.FLUIDS = { ["minecraft:water"] = true, ["minecraft:lava"] = true }

--- Reset the whole world. opts: x, y, z, f, fuel, fuelLimit, id, label, gps (bool)
function SIM.reset(opts)
  opts = opts or {}
  SIM.blocks = {}                 -- key -> block name
  SIM.unbreakable = { ["minecraft:bedrock"] = true }
  SIM.entities = {}               -- key -> true (a mob standing there)
  SIM.loaded = nil                -- function(x, y, z) -> bool; nil = everything loaded
  SIM.t = {
    x = opts.x or 0, y = opts.y or 64, z = opts.z or 0, f = opts.f or 0,
    fuel = opts.fuel or 1000, fuelLimit = opts.fuelLimit or 20000,
    inv = {}, sel = 1, moves = 0,
  }
  SIM.id = opts.id or 1
  SIM.label = opts.label
  SIM.gps = opts.gps ~= false
  SIM.time = 0                    -- seconds since start
  SIM.files = {}                  -- path -> contents
  SIM.dirs = { [""] = true }
  SIM.events = {}                 -- queued events: { "name", args... }
  SIM.inbox = {}                  -- rednet: { from, msg, protocol }
  SIM.sent = {}                   -- rednet: { to, msg, protocol }
  SIM.stock = {}                  -- container contents: key -> { { name, count }, ... }
  SIM.dropped = {}                -- items dropped: { where, name, count }
  SIM.peripherals = {}            -- name -> { types = {...}, methods = { name = fn } }
  SIM.rebooted = false
  SIM.dug = {}                    -- list of dug block names
  SIM.printed = {}
end

function SIM.block(x, y, z, name) SIM.blocks[key(x, y, z)] = name end
function SIM.getBlock(x, y, z) return SIM.blocks[key(x, y, z)] end
function SIM.mob(x, y, z) SIM.entities[key(x, y, z)] = true end
--- Put items in a container block, for turtle.suck to take (first in, first out).
function SIM.stockAt(x, y, z, name, count)
  local k = key(x, y, z)
  SIM.stock[k] = SIM.stock[k] or {}
  table.insert(SIM.stock[k], { name = name, count = count or 1 })
end
function SIM.give(slot, name, count) SIM.t.inv[slot] = { name = name, count = count or 1 } end
function SIM.queue(...) SIM.events[#SIM.events + 1] = { ... } end
function SIM.receive(from, msg, protocol) SIM.inbox[#SIM.inbox + 1] = { from, msg, protocol } end
--- Fill a box with one block (handy for building test worlds).
function SIM.fill(x1, y1, z1, x2, y2, z2, name)
  for x = math.min(x1, x2), math.max(x1, x2) do
    for y = math.min(y1, y2), math.max(y1, y2) do
      for z = math.min(z1, z2), math.max(z1, z2) do SIM.block(x, y, z, name) end
    end
  end
end

-- ---------------------------------------------------------------- items

local function addItem(name, count)
  count = count or 1
  local inv = SIM.t.inv
  for k = 0, 15 do
    local i = ((SIM.t.sel - 1 + k) % 16) + 1
    local s = inv[i]
    if s and s.name == name and s.count < 64 then
      local take = math.min(64 - s.count, count)
      s.count, count = s.count + take, count - take
    elseif not s then
      inv[i] = { name = name, count = math.min(64, count) }
      count = count - math.min(64, count)
    end
    if count == 0 then return true end
  end
  SIM.lost = (SIM.lost or 0) + count
  return false
end
SIM.addItem = addItem

-- ---------------------------------------------------------------- turtle

local function target(dir)
  local t = SIM.t
  if dir == "up" then return t.x, t.y + 1, t.z end
  if dir == "down" then return t.x, t.y - 1, t.z end
  local s = dir == "back" and -1 or 1
  return t.x + DX[t.f] * s, t.y, t.z + DZ[t.f] * s
end

local function solid(x, y, z)
  local b = SIM.blocks[key(x, y, z)]
  return b ~= nil and not SIM.FLUIDS[b]
end

local function settle(x, y, z)
  -- gravel/sand above an emptied cell falls into it (the whole column)
  local above = SIM.blocks[key(x, y + 1, z)]
  while above and SIM.FALLS[above] do
    SIM.blocks[key(x, y, z)] = above
    SIM.blocks[key(x, y + 1, z)] = nil
    y = y + 1
    above = SIM.blocks[key(x, y + 1, z)]
  end
end

local function moveTo(dir)
  local t = SIM.t
  if t.fuel ~= "unlimited" and t.fuel < 1 then return false, "Out of fuel" end
  local x, y, z = target(dir)
  if SIM.loaded and not SIM.loaded(x, y, z) then return false, "Cannot leave loaded world" end
  if solid(x, y, z) or SIM.entities[key(x, y, z)] then return false, "Movement obstructed" end
  t.x, t.y, t.z = x, y, z
  if t.fuel ~= "unlimited" then t.fuel = t.fuel - 1 end
  t.moves = t.moves + 1
  SIM.time = SIM.time + 0.4
  return true
end

local function dig(dir)
  local x, y, z = target(dir)
  local b = SIM.blocks[key(x, y, z)]
  if not b or SIM.FLUIDS[b] then return false, "Nothing to dig here" end
  if SIM.unbreakable[b] then return false, "Cannot break unbreakable block" end
  SIM.blocks[key(x, y, z)] = nil
  SIM.dug[#SIM.dug + 1] = b
  addItem(b, 1)
  settle(x, y, z)
  SIM.time = SIM.time + 0.4
  return true
end

local function detect(dir) return solid(target(dir)) end

local function inspect(dir)
  local b = SIM.blocks[key(target(dir))]
  if not b then return false, "No block to inspect" end
  return true, { name = b, state = {}, tags = {} }
end

local function attack(dir)
  local x, y, z = target(dir)
  if SIM.entities[key(x, y, z)] then
    SIM.entities[key(x, y, z)] = nil
    return true
  end
  return false, "Nothing to attack here"
end

local function drop(where, count)
  local s = SIM.t.inv[SIM.t.sel]
  if not s then return false, "No items to drop" end
  local n = math.min(count or s.count, s.count)
  SIM.dropped[#SIM.dropped + 1] = { where = where, name = s.name, count = n }
  s.count = s.count - n
  if s.count == 0 then SIM.t.inv[SIM.t.sel] = nil end
  return true
end

local function suck(where, count)
  local box = SIM.stock[key(target(where))]
  local s = box and box[1]
  if not s then return false, "No items to take" end
  local n = math.min(count or 64, s.count)
  addItem(s.name, n)
  s.count = s.count - n
  if s.count == 0 then table.remove(box, 1) end
  return true
end

turtle = {
  forward = function() return moveTo("forward") end,
  back = function() return moveTo("back") end,
  up = function() return moveTo("up") end,
  down = function() return moveTo("down") end,
  turnLeft = function() SIM.t.f = (SIM.t.f + 3) % 4 return true end,
  turnRight = function() SIM.t.f = (SIM.t.f + 1) % 4 return true end,
  dig = function() return dig("forward") end,
  digUp = function() return dig("up") end,
  digDown = function() return dig("down") end,
  detect = function() return detect("forward") end,
  detectUp = function() return detect("up") end,
  detectDown = function() return detect("down") end,
  inspect = function() return inspect("forward") end,
  inspectUp = function() return inspect("up") end,
  inspectDown = function() return inspect("down") end,
  attack = function() return attack("forward") end,
  attackUp = function() return attack("up") end,
  attackDown = function() return attack("down") end,
  getFuelLevel = function() return SIM.t.fuel end,
  getFuelLimit = function() return SIM.t.fuelLimit end,
  refuel = function(count)
    local s = SIM.t.inv[SIM.t.sel]
    local per = s and SIM.FUEL[s.name]
    if not per then return false, "Items not combustible" end
    if count == 0 then return true end
    local n = math.min(count or s.count, s.count)
    SIM.t.fuel = math.min(SIM.t.fuelLimit, SIM.t.fuel + per * n)
    if s.name == "minecraft:lava_bucket" then
      SIM.t.inv[SIM.t.sel] = { name = "minecraft:bucket", count = 1 }
    else
      s.count = s.count - n
      if s.count == 0 then SIM.t.inv[SIM.t.sel] = nil end
    end
    return true
  end,
  select = function(slot) SIM.t.sel = slot return true end,
  getSelectedSlot = function() return SIM.t.sel end,
  getItemCount = function(slot) local s = SIM.t.inv[slot or SIM.t.sel] return s and s.count or 0 end,
  getItemSpace = function(slot) local s = SIM.t.inv[slot or SIM.t.sel] return s and (64 - s.count) or 64 end,
  getItemDetail = function(slot)
    local s = SIM.t.inv[slot or SIM.t.sel]
    return s and { name = s.name, count = s.count } or nil
  end,
  transferTo = function(slot, count)
    local from = SIM.t.inv[SIM.t.sel]
    if not from then return false end
    local to = SIM.t.inv[slot]
    if to and to.name ~= from.name then return false end
    local space = to and (64 - to.count) or 64
    local n = math.min(count or from.count, from.count, space)
    if n == 0 then return false end
    SIM.t.inv[slot] = { name = from.name, count = (to and to.count or 0) + n }
    from.count = from.count - n
    if from.count == 0 then SIM.t.inv[SIM.t.sel] = nil end
    return true
  end,
  drop = function(n) return drop("front", n) end,
  dropUp = function(n) return drop("up", n) end,
  dropDown = function(n) return drop("down", n) end,
  suck = function(n) return suck("forward", n) end,
  suckUp = function(n) return suck("up", n) end,
  suckDown = function(n) return suck("down", n) end,
}

-- ---------------------------------------------------------------- gps, os, sleep

gps = {
  locate = function()
    if not SIM.gps then return nil end
    return SIM.t.x, SIM.t.y, SIM.t.z
  end,
}

function sleep(s) SIM.time = SIM.time + (s or 0) end
os.sleep = sleep
os.getComputerID = function() return SIM.id end
os.getComputerLabel = function() return SIM.label end
os.setComputerLabel = function(l) SIM.label = l end
os.epoch = function() return math.floor(SIM.time * 1000) end
os.clock = function() return SIM.time end
os.reboot = function() SIM.rebooted = true end
os.queueEvent = function(...) SIM.queue(...) end
os.pullEvent = function(filter)
  for i, ev in ipairs(SIM.events) do
    if not filter or ev[1] == filter then
      table.remove(SIM.events, i)
      return (table.unpack or unpack)(ev)
    end
  end
  error("SIM: no more '" .. tostring(filter or "any") .. "' events queued", 2)
end
os.pullEventRaw = os.pullEvent
_HOST = "ComputerCraft (sim)"

-- ---------------------------------------------------------------- fs (in memory)

local function norm(p)
  p = ("/" .. tostring(p)):gsub("/+", "/"):gsub("/$", "")
  return p:sub(2)
end
local function dirOf(p) return (norm(p):match("^(.*)/[^/]*$")) or "" end

fs = {}
function fs.exists(p) p = norm(p) return SIM.files[p] ~= nil or SIM.dirs[p] ~= nil end
function fs.isDir(p) return SIM.dirs[norm(p)] ~= nil end
function fs.makeDir(p)
  p = norm(p)
  while p ~= "" do SIM.dirs[p] = true p = dirOf(p) end
end
function fs.delete(p) p = norm(p) SIM.files[p] = nil SIM.dirs[p] = nil end
function fs.move(a, b)
  a, b = norm(a), norm(b)
  if SIM.files[b] then error("File exists", 2) end
  if not SIM.files[a] then error("No such file", 2) end
  SIM.files[b], SIM.files[a] = SIM.files[a], nil
end
function fs.getSize(p) return #(SIM.files[norm(p)] or "") end
function fs.getFreeSpace() return 1000000 end
function fs.combine(a, b) return norm(a .. "/" .. b) end
function fs.getDir(p) return dirOf(p) end
function fs.list(p)
  p = norm(p)
  local out = {}
  for f in pairs(SIM.files) do if dirOf(f) == p then out[#out + 1] = f:match("[^/]*$") end end
  table.sort(out)
  return out
end
function fs.open(p, mode)
  p = norm(p)
  if mode == "r" then
    local data = SIM.files[p]
    if not data then return nil, "/" .. p .. ": No such file" end
    local pos = 1
    return {
      readAll = function() local s = data:sub(pos) pos = #data + 1 return s end,
      readLine = function()
        if pos > #data then return nil end
        local e = data:find("\n", pos, true)
        local line = data:sub(pos, (e or #data + 1) - 1)
        pos = (e or #data) + 1
        return line
      end,
      close = function() end,
    }
  end
  if dirOf(p) ~= "" and not SIM.dirs[dirOf(p)] then fs.makeDir(dirOf(p)) end -- CC creates parents
  local buf = (mode == "a" and SIM.files[p]) or ""
  SIM.files[p] = buf
  local h = {}
  function h.write(s) buf = buf .. tostring(s) SIM.files[p] = buf end
  function h.writeLine(s) h.write(tostring(s) .. "\n") end
  function h.flush() end
  function h.close() end
  return h
end

-- loadfile that reads from the in-memory disk first, then the real one
local realLoadfile = loadfile
function loadfile(path, mode, env)
  local data = SIM.files and SIM.files[norm(path)]
  -- (passing env = nil explicitly would give the chunk no globals at all, so leave it out)
  if data then
    if env then return load(data, "@" .. path, mode, env) end
    return load(data, "@" .. path, mode)
  end
  if env then return realLoadfile(path, mode, env) end
  return realLoadfile(path, mode)
end

-- ---------------------------------------------------------------- textutils

local function serialize(v, indent)
  local t = type(v)
  if t == "string" then return string.format("%q", v) end
  if t == "number" or t == "boolean" or t == "nil" then return tostring(v) end
  if t ~= "table" then error("Cannot serialize type " .. t, 0) end
  local parts = {}
  for k, val in pairs(v) do
    local ks = type(k) == "string" and k:match("^[%a_][%w_]*$") and k or ("[" .. serialize(k) .. "]")
    parts[#parts + 1] = ks .. " = " .. serialize(val)
  end
  table.sort(parts)
  return "{ " .. table.concat(parts, ", ") .. " }"
end

local function json(v)
  local t = type(v)
  if t == "string" then return '"' .. v:gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"' end
  if t == "number" or t == "boolean" then return tostring(v) end
  if t == "nil" then return "null" end
  local isArray = #v > 0
  local parts = {}
  if isArray then
    for _, x in ipairs(v) do parts[#parts + 1] = json(x) end
    return "[" .. table.concat(parts, ",") .. "]"
  end
  for k, x in pairs(v) do parts[#parts + 1] = json(tostring(k)) .. ":" .. json(x) end
  table.sort(parts)
  return "{" .. table.concat(parts, ",") .. "}"
end

textutils = {
  serialize = function(v) return serialize(v) end,
  unserialize = function(s)
    local fn = load("return " .. s, "unserialize", "t", {})
    if not fn then return nil end
    local ok, v = pcall(fn)
    return ok and v or nil
  end,
  serializeJSON = json,
}

-- ---------------------------------------------------------------- peripheral, rednet

peripheral = {
  getNames = function()
    local n = {}
    for name in pairs(SIM.peripherals) do n[#n + 1] = name end
    table.sort(n)
    return n
  end,
  getType = function(name)
    local p = SIM.peripherals[name]
    if p then return (table.unpack or unpack)(p.types) end
  end,
  getMethods = function(name)
    local p = SIM.peripherals[name]
    if not p then return nil end
    local m = {}
    for k in pairs(p.methods) do m[#m + 1] = k end
    table.sort(m)
    return m
  end,
  wrap = function(name) local p = SIM.peripherals[name] return p and p.methods end,
  call = function(name, method, ...) return SIM.peripherals[name].methods[method](...) end,
  find = function(ptype)
    for name, p in pairs(SIM.peripherals) do
      for _, t in ipairs(p.types) do if t == ptype then return p.methods, name end end
    end
  end,
}

rednet = {
  open = function() return true end,
  isOpen = function() return true end,
  send = function(to, msg, protocol) SIM.sent[#SIM.sent + 1] = { to, msg, protocol } return true end,
  broadcast = function(msg, protocol) SIM.sent[#SIM.sent + 1] = { "all", msg, protocol } end,
  receive = function(protocol, timeout)
    for i, m in ipairs(SIM.inbox) do
      if not protocol or m[3] == protocol then
        table.remove(SIM.inbox, i)
        return m[1], m[2], m[3]
      end
    end
    if timeout then SIM.time = SIM.time + timeout return nil end
    error("SIM: no rednet message queued for '" .. tostring(protocol) .. "'", 2)
  end,
}

-- print goes to the console and is also recorded
local realPrint = print
function print(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
  SIM.printed[#SIM.printed + 1] = table.concat(parts, "\t")
  if SIM.echo then realPrint(...) end
end

-- Snapshot the fake APIs so every reset() undoes anything a test patched
-- (e.g. turtle.digUp = function() error(...) end), even when test files share one Lua state.
local function copy(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end
local SNAP = {
  turtle = copy(turtle), gps = copy(gps), fs = copy(fs), textutils = copy(textutils),
  peripheral = copy(peripheral), rednet = copy(rednet), os = copy(os), sleep = sleep,
}
function SIM.restore()
  turtle, gps, fs, textutils = copy(SNAP.turtle), copy(SNAP.gps), copy(SNAP.fs), copy(SNAP.textutils)
  peripheral, rednet, sleep = copy(SNAP.peripheral), copy(SNAP.rednet), SNAP.sleep
  for k, v in pairs(SNAP.os) do os[k] = v end
end

local plainReset = SIM.reset
function SIM.reset(opts)
  plainReset(opts)
  SIM.restore()
end

SIM.reset()
return SIM
