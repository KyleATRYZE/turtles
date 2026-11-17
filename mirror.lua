-- mirror.lua : keeps a copy of what is on this machine's screen, so the
-- status report can carry it (swarm.report sends the last lines). Loaded by
-- startup.lua before anything else; a crash message lands here too, and
-- startup.lua reports it before the machine restarts.
if _G.SCREEN_MIRROR then return end

local native = term.current()
local w, h = native.getSize()
local rows = {}
for y = 1, h do rows[y] = "" end
local cx, cy = 1, 1

local function put(text)
  text = tostring(text)
  if cy < 1 or cy > h then cx = cx + #text return end
  local row = rows[cy]
  if #row < cx - 1 then row = row .. (" "):rep(cx - 1 - #row) end
  rows[cy] = (row:sub(1, cx - 1) .. text .. row:sub(cx + #text)):sub(1, w)
  cx = cx + #text
end

local rec = setmetatable({}, { __index = native })
function rec.write(text) put(text) return native.write(text) end
function rec.blit(text, fg, bg) put(text) return native.blit(text, fg, bg) end
function rec.clear()
  for y = 1, h do rows[y] = "" end
  return native.clear()
end
function rec.clearLine()
  if rows[cy] then rows[cy] = "" end
  return native.clearLine()
end
function rec.scroll(n)
  if n > 0 then
    for _ = 1, n do table.remove(rows, 1) rows[h] = "" end
  elseif n < 0 then
    for _ = 1, -n do table.insert(rows, 1, "") rows[h + 1] = nil end
  end
  return native.scroll(n)
end
function rec.setCursorPos(x, y)
  cx, cy = math.floor(x), math.floor(y)
  return native.setCursorPos(x, y)
end
function rec.getCursorPos() return cx, cy end

term.redirect(rec)

-- the screen's last lines that have something on them (n of them)
_G.SCREEN_MIRROR = function(n)
  local out = {}
  for y = 1, h do
    local line = rows[y]:gsub("%s+$", "")
    if line ~= "" then out[#out + 1] = line end
  end
  while #out > (n or 12) do table.remove(out, 1) end
  return out
end
