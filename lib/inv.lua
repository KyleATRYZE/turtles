--- lib/inv.lua: turtle inventory helpers.
--
--   local inv = require("lib.inv")
--   inv.select("minecraft:torch")
--   inv.count("*coal*")                       -- wildcards with *
--   inv.dropMatching(inv.junk, "down")         -- dump rubble
--   inv.refuel(1000)                           -- burn fuel items until >= 1000
--
-- A "match" is one of:
--   "minecraft:coal"            exact item name
--   "*coal*"                    wildcard (* = anything)
--   { "a", "*b*" }              any of a list
--   function(detail) ... end    your own test on getItemDetail's table

local M = {}

M.SLOTS = 16

--- Common rubble that miners throw away.
M.junk = {
  "minecraft:cobblestone", "minecraft:cobbled_deepslate", "minecraft:dirt", "minecraft:gravel",
  "minecraft:netherrack", "minecraft:tuff", "minecraft:diorite", "minecraft:granite",
  "minecraft:andesite", "minecraft:calcite",
}

--- Fuel values per item (CC turtle fuel units).
M.FUEL = {
  ["minecraft:coal"] = 80, ["minecraft:charcoal"] = 80, ["minecraft:coal_block"] = 800,
  ["minecraft:lava_bucket"] = 1000, ["minecraft:blaze_rod"] = 120,
}

local function wildcard(p)
  return "^" .. p:gsub("[%^%$%(%)%%%.%[%]%+%-%?]", "%%%0"):gsub("%*", ".*") .. "$"
end

--- Does an item detail match? (see the header for what a match can be)
function M.matches(detail, match)
  if not detail then return false end
  local t = type(match)
  if t == "function" then return match(detail) and true or false end
  if t == "table" then
    for _, m in ipairs(match) do
      if M.matches(detail, m) then return true end
    end
    return false
  end
  if match:find("*", 1, true) then return detail.name:find(wildcard(match)) ~= nil end
  return detail.name == match
end

--- First slot holding a matching item, and its detail.
---@return integer? slot
---@return table? detail
function M.find(match)
  for slot = 1, M.SLOTS do
    local d = turtle.getItemDetail(slot)
    if d and M.matches(d, match) then return slot, d end
  end
  return nil
end

--- Total count of matching items.
---@return integer
function M.count(match)
  local n = 0
  for slot = 1, M.SLOTS do
    local d = turtle.getItemDetail(slot)
    if d and M.matches(d, match) then n = n + d.count end
  end
  return n
end

--- Select the first matching slot. Returns the slot or nil.
function M.select(match)
  local slot = M.find(match)
  if slot then turtle.select(slot) end
  return slot
end

--- Number of empty slots.
---@return integer
function M.freeSlots()
  local n = 0
  for slot = 1, M.SLOTS do
    if turtle.getItemCount(slot) == 0 then n = n + 1 end
  end
  return n
end

function M.isFull() return M.freeSlots() == 0 end

local DROP = { front = "drop", up = "dropUp", down = "dropDown" }

--- Drop every matching stack ("front", "up" or "down"). Returns how many items left.
---@return integer dropped
function M.dropMatching(match, where)
  local fn = turtle[DROP[where or "front"]]
  local before = turtle.getSelectedSlot()
  local n = 0
  for slot = 1, M.SLOTS do
    local d = turtle.getItemDetail(slot)
    if d and M.matches(d, match) then
      turtle.select(slot)
      if fn() then n = n + d.count - turtle.getItemCount(slot) end
    end
  end
  turtle.select(before)
  return n
end

--- Drop everything that does NOT match `keep` (e.g. unload all but fuel and tools).
---@return integer dropped
function M.dropAllExcept(keep, where)
  return M.dropMatching(function(d) return not M.matches(d, keep) end, where)
end

--- Merge part-stacks of the same item so more slots are free. Returns slots freed.
---@return integer
function M.compact()
  local freed = 0
  local before = turtle.getSelectedSlot()
  for i = M.SLOTS, 2, -1 do
    local di = turtle.getItemDetail(i)
    if di then
      for j = 1, i - 1 do
        local dj = turtle.getItemDetail(j)
        if dj and dj.name == di.name and turtle.getItemSpace(j) > 0 then
          turtle.select(i)
          turtle.transferTo(j)
          if turtle.getItemCount(i) == 0 then
            freed = freed + 1
            break
          end
        end
      end
    end
  end
  turtle.select(before)
  return freed
end

--- Burn fuel items until the level reaches `target` (or the fuel runs out).
-- Only burns items listed in `allow` (default: the keys of M.FUEL).
-- Lava buckets leave an empty bucket behind, as in the game.
---@param target integer
---@param allow? any match
---@return integer level
function M.refuel(target, allow)
  local level = turtle.getFuelLevel()
  if level == "unlimited" then return math.huge end
  local before = turtle.getSelectedSlot()
  for slot = 1, M.SLOTS do
    if level >= target then break end
    local d = turtle.getItemDetail(slot)
    local ok = d and (allow and M.matches(d, allow) or (not allow and M.FUEL[d.name]))
    if ok then
      turtle.select(slot)
      local per = M.FUEL[d.name] or 1
      local need = math.max(1, math.ceil((target - level) / per))
      turtle.refuel(math.min(need, d.count))
      level = turtle.getFuelLevel()
    end
  end
  turtle.select(before)
  return level
end

return M
