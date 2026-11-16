-- A small world for foundry.lua: a turtle, Mekanism-like machines with
-- sides, slots, power and auto-eject, a factory that hands things over, and
-- a clock that only moves when the turtle sleeps.
--
-- Positions are in the building's own coordinates. Machines behave as was
-- learned on the lab bench: sides are named from the front (LEFT is the next
-- face clockwise seen from above), a side takes or gives by its ITEM mode, a
-- job costs 10 kJ and 10 seconds, a redstone dust in the energy slot is
-- 10 kJ, and results are pushed out of OUTPUT sides when ejecting is on.

local DX = { [0] = 1, [1] = 0, [2] = -1, [3] = 0 }
local DZ = { [0] = 0, [1] = 1, [2] = 0, [3] = -1 }
local CODE = { EAST = 0, SOUTH = 1, WEST = 2, NORTH = 3 }
local NAME = { [0] = "EAST", [1] = "SOUTH", [2] = "WEST", [3] = "NORTH" }

-- EMBED = true: only the machines (for a test that brings its own turtle
-- and world: T with x, y, z, d, inv, sel, and machines in its coordinates).
CLOCK = 0
if not EMBED then T = { x = 40, y = 1, z = 20, d = 0, inv = {}, sel = 1, outside = true } end
MACHINES = {}             -- key -> machine
FLOOR = {}                -- anything dropped where there is nothing to take it
STOCK = {}                -- the factory's stock: name -> count
HANDED = {}               -- what was handed in: name -> count
LOG, SENT, INBOX = {}, {}, {}
FETCHES, HANDINS = 0, 0

local function key(x, y, z) return x .. "," .. y .. "," .. z end

local RECIPES = {
  ["mekanism:enrichment_chamber"] = {
    ["minecraft:raw_iron"] = { take = 3, give = 4, out = "mekanism:dust_iron" },
    ["minecraft:raw_gold"] = { take = 3, give = 4, out = "mekanism:dust_gold" },
    ["minecraft:redstone"] = { take = 1, give = 1, out = "mekanism:enriched_redstone" },
  },
  ["mekanism:energized_smelter"] = {
    ["mekanism:dust_iron"] = { take = 1, give = 1, out = "minecraft:iron_ingot" },
    ["mekanism:dust_gold"] = { take = 1, give = 1, out = "minecraft:gold_ingot" },
  },
  ["mekanism:metallurgic_infuser"] = {
    ["minecraft:iron_ingot"] = { take = 1, give = 1, out = "mekanism:enriched_iron", gas = "mekanism:carbon", mb = 10 },
    ["mekanism:enriched_iron"] = { take = 1, give = 1, out = "alltheores:steel_dust", gas = "mekanism:carbon", mb = 10 },
    ["alltheores:osmium_ingot"] = { take = 1, give = 1, out = "mekanism:basic_control_circuit", gas = "mekanism:redstone", mb = 20 },
  },
}
local GAS = {
  ["minecraft:coal"] = { "mekanism:carbon", 10 }, ["minecraft:charcoal"] = { "mekanism:carbon", 10 },
  ["minecraft:redstone"] = { "mekanism:redstone", 10 }, ["mekanism:enriched_redstone"] = { "mekanism:redstone", 80 },
}

function addMachine(item, x, y, z, facing)
  local m = { item = item, x = x, y = y, z = z, f = facing, energy = 0, max = 20000, work = 0,
    modes = { FRONT = "NONE", LEFT = "NONE", RIGHT = "NONE", BACK = "NONE", TOP = "NONE", BOTTOM = "NONE" },
    eject = false, slots = {} }
  -- (defaults as found on the infuser: front, left and top take the item)
  m.modes.FRONT, m.modes.LEFT, m.modes.TOP, m.modes.RIGHT, m.modes.BACK = "INPUT", "INPUT", "INPUT", "OUTPUT", "ENERGY"
  MACHINES[key(x, y, z)] = m
  return m
end
function machineAt(x, y, z) return MACHINES[key(x, y, z)] end

-- the name of a face (0..3, "top", "bottom") from the machine's own front
local function rel(m, face)
  if face == "top" then return "TOP" elseif face == "bottom" then return "BOTTOM" end
  local turn = (face - m.f) % 4
  return turn == 0 and "FRONT" or turn == 1 and "LEFT" or turn == 2 and "BACK" or "RIGHT"
end

-- an item offered at a face: how many go in
function mekOffer(m, face, name, n)
  local mode = m.modes[rel(m, face)]
  local slot
  if mode == "INPUT" then
    if not RECIPES[m.item][name] then return 0 end
    slot = "input"
  elseif mode == "ENERGY" then
    if name ~= "minecraft:redstone" then return 0 end
    slot = "power"
  elseif mode == "EXTRA" then
    if not GAS[name] or m.item ~= "mekanism:metallurgic_infuser" then return 0 end
    slot = "extra"
  else
    return 0
  end
  local s = m.slots[slot]
  if s and s.name ~= name then return 0 end
  local room = 64 - (s and s.count or 0)
  local went = math.min(room, n)
  if went > 0 then m.slots[slot] = { name = name, count = (s and s.count or 0) + went } end
  return went
end

function giveTurtle(name, n)
  for i = 1, 16 do
    local s = T.inv[i]
    if n > 0 and s and s.name == name and s.count < 64 then
      local k = math.min(n, 64 - s.count)
      s.count, n = s.count + k, n - k
    end
  end
  for i = 1, 16 do
    if n > 0 and not T.inv[i] then
      local k = math.min(n, 64)
      T.inv[i], n = { name = name, count = k }, n - k
    end
  end
  return n            -- what would not fit
end

local function tickMachine(m, dt)
  -- dust in the energy slot turns to power when there is room for it
  local p = m.slots.power
  while p and p.count > 0 and m.energy + 10000 <= m.max do
    m.energy, p.count = m.energy + 10000, p.count - 1
  end
  if p and p.count == 0 then m.slots.power = nil end
  -- the infusion item goes into the tank
  local x = m.slots.extra
  if x then
    local g = GAS[x.name]
    m.tank = m.tank or { name = g[1], amount = 0 }
    if m.tank.amount == 0 then m.tank.name = g[1] end
    while x.count > 0 and m.tank.name == g[1] and m.tank.amount + g[2] <= 1000 do
      m.tank.amount, x.count = m.tank.amount + g[2], x.count - 1
    end
    if x.count == 0 then m.slots.extra = nil end
  end
  -- work
  m.work = m.work + dt
  while m.work >= 10 do
    local i, o = m.slots.input, m.slots.output
    local r = i and RECIPES[m.item][i.name]
    local can = r and i.count >= r.take and m.energy >= 10000
      and (not o or (o.name == r.out and o.count + r.give <= 64))
      and (not r.gas or (m.tank and m.tank.name == r.gas and m.tank.amount >= r.mb))
    if not can then m.work = 0 break end
    m.work, m.energy = m.work - 10, m.energy - 10000
    i.count = i.count - r.take
    if i.count == 0 then m.slots.input = nil end
    m.slots.output = { name = r.out, count = (o and o.count or 0) + r.give }
    if r.gas then m.tank.amount = m.tank.amount - r.mb end
    p = m.slots.power
    while p and p.count > 0 and m.energy + 10000 <= m.max do
      m.energy, p.count = m.energy + 10000, p.count - 1
    end
    if p and p.count == 0 then m.slots.power = nil end
  end
  -- results pushed out of the sides set to give them
  local o = m.slots.output
  if m.eject and o then
    for face = 0, 3 do
      if o.count > 0 and m.modes[rel(m, face)] == "OUTPUT" then
        local nx, nz = m.x + DX[face], m.z + DZ[face]
        local other = machineAt(nx, m.y, nz)
        if other then
          o.count = o.count - mekOffer(other, (face + 2) % 4, o.name, o.count)
        elseif not T.outside and T.x == nx and T.y == m.y and T.z == nz then
          EJECTED_TO_TURTLE = (EJECTED_TO_TURTLE or 0) + o.count
          o.count = giveTurtle(o.name, o.count)
        end
      end
    end
    if o.count == 0 then m.slots.output = nil end
  end
end

function mekTime(n)                     -- the clock moves on, and the machines with it
  local left = n or 0
  while left > 0 do
    local dt = math.min(1, left)
    CLOCK, left = CLOCK + dt, left - dt
    for _, m in pairs(MACHINES) do tickMachine(m, dt) end
  end
end

-- what the turtle is looking at: the machine and the face it is seen by
function mekTarget(dir)
  if T.outside then return nil end
  if dir == "Down" then return machineAt(T.x, T.y - 1, T.z), "top" end
  if dir == "Up" then return machineAt(T.x, T.y + 1, T.z), "bottom" end
  return machineAt(T.x + DX[T.d], T.y, T.z + DZ[T.d]), (T.d + 2) % 4
end

-- taking from a machine by the face looked at
function mekSuck(dir, n)
  local m, face = mekTarget(dir)
  if not m then return false, "No items to take" end
  local o = m.slots.output
  if m.modes[rel(m, face)] ~= "OUTPUT" or not o then return false, "No items to take" end
  local k = math.min(n or 64, o.count)
  local left = giveTurtle(o.name, k)
  o.count = o.count - (k - left)
  if o.count == 0 then m.slots.output = nil end
  return k - left > 0
end

-- a machine's methods as a peripheral
function mekCall(m, method, ...)
  local a = { ... }
  if method == "getDirection" then return NAME[m.f] end
  if method == "getMode" then return m.modes[a[2]] end
  if method == "setMode" then
    if a[1] ~= "ITEM" or m.modes[a[2]] == nil then error("bad side", 0) end
    m.modes[a[2]] = a[3]
    SETMODES = (SETMODES or 0) + 1
    return
  end
  if method == "setEjecting" then m.eject = a[2] return end
  if method == "getInput" then local s = m.slots.input return s and { name = s.name, count = s.count } or { name = "minecraft:air", count = 0 } end
  if method == "getOutput" then local s = m.slots.output return s and { name = s.name, count = s.count } or { name = "minecraft:air", count = 0 } end
  if method == "getEnergyItem" then local s = m.slots.power return s and { name = s.name, count = s.count } or { name = "minecraft:air", count = 0 } end
  if method == "getEnergy" then return m.energy end
  if method == "getMaxEnergy" then return m.max end
  if method == "getInfuseType" then return m.tank and { name = m.tank.name, amount = m.tank.amount } or { name = "mekanism:empty", amount = 0 } end
  if method == "dumpInfuseType" then m.tank = nil DUMPS = (DUMPS or 0) + 1 return end
  error("no such method " .. tostring(method), 0)
end

function inMachines()
  local n = 0
  for _, m in pairs(MACHINES) do
    for slot, s in pairs(m.slots) do if slot ~= "power" then n = n + s.count end end
  end
  return n
end

if EMBED then return end

function sleep(n)
  n = n or 0
  mekTime(n)
  SLEPT = (SLEPT or 0) + n
  if SLEPT > 200000 then error("TOO MUCH SLEEPING (stuck)", 0) end
end

os.clock = function() return CLOCK end
os.date = function() return "00:00" end
os.getComputerID = function() return 7 end

FS = {}
fs = {
  exists = function(p) return FS[p] ~= nil end,
  open = function(p, mode)
    if mode == "w" then
      local buf = {}
      return { write = function(s) buf[#buf + 1] = s end, close = function() FS[p] = table.concat(buf) end }
    end
    return { readAll = function() return FS[p] end, close = function() end }
  end,
}
local function ser(v)
  if type(v) == "table" then
    local parts = {}
    for k, val in pairs(v) do
      parts[#parts + 1] = "[" .. (type(k) == "string" and string.format("%q", k) or tostring(k)) .. "]=" .. ser(val)
    end
    return "{" .. table.concat(parts, ",") .. "}"
  elseif type(v) == "string" then return string.format("%q", v) else return tostring(v) end
end
textutils = { serialize = ser, unserialize = function(s) local f = load("return " .. s) return f and f() end }

local target = mekTarget

turtle = {
  select = function(i) T.sel = i return true end,
  getItemDetail = function(i) local s = T.inv[i or T.sel] if s then return { name = s.name, count = s.count } end end,
  getItemCount = function(i) local s = T.inv[i or T.sel] return s and s.count or 0 end,
}
for _, dir in ipairs({ "", "Up", "Down" }) do
  turtle["inspect" .. dir] = function()
    local m = target(dir)
    if BENCH and T.outside and dir == "" and T.x == BENCH.x and T.y == BENCH.y and T.z == BENCH.z and T.d == BENCH.face
      and BENCH.there then
      return true, { name = BENCH.item }
    end
    if not m then return false, "No block" end
    return true, { name = m.item }
  end
  turtle["drop" .. dir] = function(n)
    local s = T.inv[T.sel]
    if not s then return false, "No items to drop" end
    n = math.min(n or s.count, s.count)
    local m, face = target(dir)
    if not m then
      FLOOR[s.name] = (FLOOR[s.name] or 0) + n
      s.count = s.count - n
      if s.count == 0 then T.inv[T.sel] = nil end
      return true
    end
    local went = mekOffer(m, face, s.name, n)
    if went == 0 then return false, "No space for items" end
    s.count = s.count - went
    if s.count == 0 then T.inv[T.sel] = nil end
    return true
  end
  turtle["suck" .. dir] = function(n) return mekSuck(dir, n) end
end
-- a machine a turtle places faces the turtle
turtle.place = function()
  local s = T.inv[T.sel]
  if not s or T.outside then return false, "No items to place" end
  local x, z = T.x + DX[T.d], T.z + DZ[T.d]
  if machineAt(x, T.y, z) then return false, "Cannot place block here" end
  local m = addMachine(s.name, x, T.y, z, (T.d + 2) % 4)
  local kept = KEPT and KEPT[s.name]
  if kept then m.slots, m.tank, m.energy, m.modes, KEPT[s.name] = kept.slots, kept.tank, kept.energy, kept.modes, nil end
  s.count = s.count - 1
  if s.count == 0 then T.inv[T.sel] = nil end
  return true
end
-- the infuser on the bench outside: digging it brings it on board
turtle.dig = function()
  if BENCH and T.outside and T.x == BENCH.x and T.y == BENCH.y and T.z == BENCH.z and T.d == BENCH.face and BENCH.there then
    BENCH.there = false
    giveTurtle(BENCH.item, 1)
    return true
  end
  DUG_SOMETHING_ELSE = true
  return false
end

peripheral = {
  call = function(side, method, ...)
    local m = target(side == "bottom" and "Down" or side == "top" and "Up" or "")
    if not m then error("No peripheral attached", 0) end
    return mekCall(m, method, ...)
  end,
}

rednet = {
  broadcast = function(msg, proto) SENT[#SENT + 1] = msg return true end,
  send = function(to, msg, proto) msg._to = to SENT[#SENT + 1] = msg return true end,
  receive = function(proto, timeout)
    local m = table.remove(INBOX, 1)
    if m then return m.from or 3, m.msg end
    if STOP_WHEN_IDLE then error("IDLE", 0) end
    sleep(timeout or 1)
  end,
}

-- the helper's side of things: getting about, fetching, handing in
BLOCKED = {}
ENV = {
  PROTOCOL = "swarm_job",
  face = function(d) T.d = d end,
  tick = function() end,
  report = function(state) STATE = state end,
  inside = function() return not T.outside end,
  site = function(site) SITE = site return true end,
  walk = function(x, y, z)
    if machineAt(x, y, z) or BLOCKED[key(x, y, z)] and not machineAt(x, y, z) and false then return false end
    if NO_WAY and NO_WAY[key(x, y, z)] then return false end
    T.outside = false
    T.x, T.y, T.z = x, y, z
    WALKS = (WALKS or 0) + 1
    sleep(2)
    return true
  end,
  block = function(x, y, z) BLOCKED[key(x, y, z)] = true end,
  leave = function() T.outside = true LEFT = (LEFT or 0) + 1 end,
  rise = function() end,
  flyTo = function(x, y, z) T.outside = true T.x, T.y, T.z = x, y, z return true end,
  home = function() T.outside = true end,
  fetch = function(list)
    if not T.outside then error("fetching from inside the building", 0) end
    FETCHES = FETCHES + 1
    for _, w in ipairs(list) do
      local have = 0
      for i = 1, 16 do if T.inv[i] and T.inv[i].name == w[1] then have = have + T.inv[i].count end end
      local n = math.min(math.max(0, w[2] - have), STOCK[w[1]] or 0)
      if n > 0 then
        local left = giveTurtle(w[1], n)
        STOCK[w[1]] = STOCK[w[1]] - (n - left)
      end
    end
  end,
  handin = function()
    if not T.outside then error("handing in from inside the building", 0) end
    HANDINS = HANDINS + 1
    for i = 1, 16 do
      local s = T.inv[i]
      if s and s.name ~= "minecraft:coal" and s.name ~= "minecraft:charcoal" then
        HANDED[s.name] = (HANDED[s.name] or 0) + s.count
        STOCK[s.name] = (STOCK[s.name] or 0) + s.count
        T.inv[i] = nil
      end
    end
  end,
}

function onBoard(name)
  local n = 0
  for i = 1, 16 do if T.inv[i] and T.inv[i].name == name then n = n + T.inv[i].count end end
  return n
end
