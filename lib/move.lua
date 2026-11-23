--- lib/move.lua: turtle movement that knows where it is and says why it failed.
--
--   local move = require("lib.move")
--   move.setup({ protect = { "^computercraft:", "chest" } })
--   if not move.load() then              -- position saved from last run?
--     assert(move.locate())              -- GPS
--     assert(move.calibrate())           -- work out which way we face
--   end
--   local ok, why = move.goTo(100, 52, -40, { travelY = 52 })
--   if not ok then log.warn("could not get there: %s", why) end
--
-- Built from the swarm's lessons (docs in the turtles repo, cc-lessons.md):
--   * "Cannot leave loaded world" is its own failure ("unloaded"), not an obstruction
--   * never digs a protected block (turtles, computers, modems, chests...): waits, then gives up
--   * every failure returns a reason string, so the caller can report it
--   * position + facing are saved after every move, so a reboot resumes correctly
--
-- Facing: 0 = north (-z), 1 = east (+x), 2 = south (+z), 3 = west (-x). Same order as
-- turnRight, and the same names Minecraft uses.

local state = require("lib.state")

local M = {}

local DX = { [0] = 0, [1] = 1, [2] = 0, [3] = -1 }
local DZ = { [0] = -1, [1] = 0, [2] = 1, [3] = 0 }
M.NAMES = { [0] = "north", [1] = "east", [2] = "south", [3] = "west" }
local FACING = { north = 0, east = 1, south = 2, west = 3 }

local cfg = {
  stateFile = "/.move",   -- set to false to never save position
  dig = true,             -- dig through blocks in the way
  attack = true,          -- hit mobs in the way
  tries = 30,             -- attempts per single step (gravel, mobs...)
  protect = { "^computercraft:", "chest", "barrel", "shulker_box" }, -- Lua patterns, never dug
  natural = {},           -- Lua patterns that are never protected, whatever `protect` says (ores, plain rock)
  protectWaits = 4,       -- waits (1-4 s each) on a protected block before giving up
  refuel = nil,           -- function() -> boolean, called when fuel hits 0
  onMove = nil,           -- function(pos) after every successful step
}

M.pos = { x = 0, y = 0, z = 0, f = 0 }
M.known = false

local function save()
  if cfg.stateFile then
    state.save(cfg.stateFile, { x = M.pos.x, y = M.pos.y, z = M.pos.z, f = M.pos.f, known = M.known })
  end
end

--- Change settings (any key of cfg above).
---@param opts table
function M.setup(opts)
  for k, v in pairs(opts or {}) do cfg[k] = v end
end

--- Load the saved position. Returns true if a known position was restored.
---@return boolean
function M.load()
  if not cfg.stateFile then return false end
  local s = state.load(cfg.stateFile, {})
  if s.x and s.known then
    M.pos = { x = s.x, y = s.y, z = s.z, f = s.f or 0 }
    M.known = true
  end
  return M.known
end

--- Tell the turtle exactly where it is (e.g. it was placed at a known spot).
---@param f integer|string facing: 0-3 or "north"/"east"/"south"/"west"
function M.set(x, y, z, f)
  M.pos = { x = x, y = y, z = z, f = type(f) == "string" and FACING[f] or f or 0 }
  M.known = true
  save()
end

--- A copy of the current position, plus the facing as a word.
function M.where()
  local p = M.pos
  return { x = p.x, y = p.y, z = p.z, f = p.f, facing = M.NAMES[p.f], known = M.known }
end

local function round(v) return math.floor(v + 0.5) end

--- Read x, y, z from GPS (facing is not changed). Needs a modem and 4 GPS hosts.
---@param timeout? number
---@return boolean ok
---@return string? err
function M.locate(timeout)
  local x, y, z = gps.locate(timeout or 2)
  if not x then return false, "no gps fix" end
  M.pos.x, M.pos.y, M.pos.z = round(x), round(y), round(z)
  return true
end

--- Work out the facing with two GPS fixes: step, compare, step back.
-- Does not dig. Tries each of the four directions if the front is blocked.
---@return boolean ok
---@return string? err
function M.calibrate(timeout)
  local x1, _, z1 = gps.locate(timeout or 2)
  if not x1 then return false, "no gps fix" end
  local turns = 0
  while not turtle.forward() do
    if turns == 4 then return false, "boxed in: cannot step to calibrate" end
    turtle.turnRight()
    turns = turns + 1
  end
  local x2, y2, z2 = gps.locate(timeout or 2)
  local backOk = turtle.back()
  if not x2 then return false, "lost gps fix while calibrating" end
  local dx, dz = round(x2 - x1), round(z2 - z1)
  local f
  for i = 0, 3 do
    if DX[i] == dx and DZ[i] == dz then f = i end
  end
  if not f then return false, "gps moved oddly (" .. dx .. "," .. dz .. ")" end
  if backOk then
    M.pos = { x = round(x1), y = round(y2), z = round(z1), f = f }
  else -- something moved in behind us: we are still one block forward
    M.pos = { x = round(x2), y = round(y2), z = round(z2), f = f }
  end
  M.known = true
  save()
  return true
end

-- ---------------------------------------------------------------- turning

function M.turnRight()
  turtle.turnRight()
  M.pos.f = (M.pos.f + 1) % 4
  save()
end

function M.turnLeft()
  turtle.turnLeft()
  M.pos.f = (M.pos.f + 3) % 4
  save()
end

--- Turn to face a direction (0-3 or "north"/"east"/"south"/"west"), the short way.
function M.face(f)
  if type(f) == "string" then f = FACING[f] end
  local diff = (f - M.pos.f) % 4
  if diff == 1 then M.turnRight()
  elseif diff == 2 then M.turnRight() M.turnRight()
  elseif diff == 3 then M.turnLeft() end
end

-- ---------------------------------------------------------------- stepping

local SUFFIX = { forward = "", back = "", up = "Up", down = "Down" }

local function delta(dir)
  if dir == "up" then return 0, 1, 0 end
  if dir == "down" then return 0, -1, 0 end
  local s = dir == "back" and -1 or 1
  return DX[M.pos.f] * s, 0, DZ[M.pos.f] * s
end

local function hasFuel()
  local lvl = turtle.getFuelLevel()
  if lvl == "unlimited" or lvl > 0 then return true end
  if cfg.refuel and cfg.refuel() then
    lvl = turtle.getFuelLevel()
    return lvl == "unlimited" or lvl > 0
  end
  return false
end

local function isProtected(name)
  for _, p in ipairs(cfg.natural or {}) do
    if name:find(p) then return false end
  end
  for _, p in ipairs(cfg.protect) do
    if name:find(p) then return true end
  end
  return false
end
M.isProtected = isProtected

--- One step: "forward", "back", "up" or "down".
-- Returns true, or false + a reason:
--   "no fuel", "unloaded", "protected:<block>", "undiggable:<block>", "blocked:<block>"
--   (dig is off), "stuck: <last error>" (gave up after cfg.tries)
---@param dir "forward"|"back"|"up"|"down"
---@return boolean ok
---@return string? reason
function M.step(dir)
  if not hasFuel() then return false, "no fuel" end
  local sfx = SUFFIX[dir]
  local waits, lastErr = 0, nil
  for _ = 1, cfg.tries do
    local ok, err = turtle[dir]()
    if ok then
      local dx, dy, dz = delta(dir)
      M.pos.x, M.pos.y, M.pos.z = M.pos.x + dx, M.pos.y + dy, M.pos.z + dz
      save()
      if cfg.onMove then pcall(cfg.onMove, M.where()) end
      return true
    end
    lastErr = err
    if err == "Cannot leave loaded world" then return false, "unloaded" end
    if err == "Out of fuel" then
      if not hasFuel() then return false, "no fuel" end
    elseif dir == "back" then
      return false, "blocked behind: " .. tostring(err) -- turtles cannot dig backwards
    else
      local present, info = turtle["inspect" .. sfx]()
      if present then
        local name = info and info.name or "?"
        if isProtected(name) then
          waits = waits + 1
          if waits > cfg.protectWaits then return false, "protected:" .. name end
          sleep(1 + math.random() * 3) -- another turtle? give it a moment
        elseif cfg.dig then
          local dug, why = turtle["dig" .. sfx]()
          if not dug and turtle["detect" .. sfx]() then
            return false, "undiggable:" .. name .. (why and (" (" .. why .. ")") or "")
          end
        else
          return false, "blocked:" .. name
        end
      else
        -- nothing solid there, so a mob or player is in the way
        if cfg.attack then turtle["attack" .. sfx]() end
        sleep(0.3)
      end
    end
  end
  return false, "stuck: " .. tostring(lastErr)
end

--- Dig "forward", "up" or "down" without moving (e.g. head room for a 1x2 tunnel).
-- Keeps digging while falling gravel/sand refills the space. Never digs protected blocks.
-- Returns true (also when there was nothing to dig), or false + reason.
---@param dir? "forward"|"up"|"down"
---@return boolean ok
---@return string? reason
function M.dig(dir)
  local sfx = SUFFIX[dir or "forward"]
  for _ = 1, cfg.tries do
    if not turtle["detect" .. sfx]() then return true end
    local _, info = turtle["inspect" .. sfx]()
    local name = info and info.name or "?"
    if isProtected(name) then return false, "protected:" .. name end
    local dug, why = turtle["dig" .. sfx]()
    if not dug and turtle["detect" .. sfx]() then
      return false, "undiggable:" .. name .. (why and (" (" .. why .. ")") or "")
    end
  end
  return false, "stuck: still something there after " .. cfg.tries .. " digs"
end

local function repeatStep(dir, n)
  n = n or 1
  for i = 1, n do
    local ok, why = M.step(dir)
    if not ok then return false, why, i - 1 end
  end
  return true, nil, n
end

--- Move n blocks (default 1). Returns ok, reason, stepsDone.
function M.forward(n) return repeatStep("forward", n) end
function M.back(n) return repeatStep("back", n) end
function M.up(n) return repeatStep("up", n) end
function M.down(n) return repeatStep("down", n) end

local function axis(a, target)
  if a == "y" then
    local d = target - M.pos.y
    if d > 0 then return M.up(d) elseif d < 0 then return M.down(-d) end
    return true
  end
  local d = target - M.pos[a]
  if d == 0 then return true end
  if a == "x" then M.face(d > 0 and 1 or 3) else M.face(d > 0 and 2 or 0) end
  return M.forward(math.abs(d))
end

--- Go to x, y, z. Options:
--   order   = "xzy" (default) the axis order, e.g. "yxz" to change height first
--   travelY = number: go to this height first, then across, then to y
--             (the swarm's "travel underground on the roads" rule)
--   face    = facing to end with (0-3 or a word)
---@return boolean ok
---@return string? reason
---@return string? axis the axis it failed on
function M.goTo(x, y, z, opts)
  opts = opts or {}
  if not M.known then return false, "position unknown: use move.load(), move.locate()+calibrate() or move.set()" end
  local target = { x = x, y = y, z = z }
  if opts.travelY and M.pos.y ~= opts.travelY then
    local ok, why = axis("y", opts.travelY)
    if not ok then return false, why, "y" end
  end
  local order = opts.order or "xzy"
  if opts.travelY then order = order:gsub("y", "") .. "y" end
  for a in order:gmatch("[xyz]") do
    local ok, why = axis(a, target[a])
    if not ok then return false, why, a end
  end
  if opts.face ~= nil then M.face(opts.face) end
  return true
end

return M
