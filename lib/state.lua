--- lib/state.lua: save and load small tables safely.
--
-- A turtle can lose power or have its chunk unloaded at any moment, including halfway
-- through writing a file. save() writes to "<path>.tmp" first and only then swaps it in,
-- so you always get either the old file or the new one, never half of one.
--
--   local state = require("lib.state")
--   local s = state.load("/.miner", { done = 0 })
--   s.done = s.done + 1
--   state.save("/.miner", s)

local M = {}

local function readAll(path)
  local h = fs.open(path, "r")
  if not h then return nil end
  local text = h.readAll()
  h.close()
  return text
end

local function decode(text)
  if not text or text == "" then return nil end
  local ok, value = pcall(textutils.unserialize, text)
  if ok and type(value) == "table" then return value end
  return nil
end

--- Load a table. Returns `default` (or {}) if the file is missing or broken.
-- A broken file is kept as "<path>.bad" so you can look at it later.
---@param path string
---@param default? table
---@return table
function M.load(path, default)
  local value = decode(readAll(path))
  if value then return value end
  -- the swap in save() may have been interrupted after the delete
  local tmp = decode(readAll(path .. ".tmp"))
  if tmp then return tmp end
  if fs.exists(path) then
    if fs.exists(path .. ".bad") then fs.delete(path .. ".bad") end
    fs.move(path, path .. ".bad")
  end
  return default or {}
end

--- Save a table (numbers, strings, booleans and nested tables only).
---@param path string
---@param value table
---@return boolean ok
---@return string? err
function M.save(path, value)
  local ok, text = pcall(textutils.serialize, value)
  if not ok then return false, "cannot serialise: " .. tostring(text) end
  local tmp = path .. ".tmp"
  local h, err = fs.open(tmp, "w")
  if not h then return false, err or ("cannot open " .. tmp) end
  h.write(text)
  h.close()
  if fs.exists(path) then fs.delete(path) end
  fs.move(tmp, path)
  return true
end

--- Load, change with fn(t), save. fn may return a new table or change t in place.
---@param path string
---@param fn fun(t: table): table?
---@param default? table
---@return table
function M.update(path, fn, default)
  local t = M.load(path, default)
  local result = fn(t) or t
  M.save(path, result)
  return result
end

return M
