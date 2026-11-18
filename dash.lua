-- dash.lua: the control room's screens, drawn on advanced monitors.
--
-- A monitor is a grid of character cells. Each cell can also show a 2 x 3
-- block of "pixels" (CC's characters 128-159), so drawings get six times the
-- detail of text. Colours come from our own palette of 16, set on the
-- monitor itself, so nothing looks like stock CC.
--
--   local dash = require("dash")
--   dash.wall(mon, data)            -- the 9 x 4 map wall in the tower
--   dash.gate(mon, gate)            -- a gate's IN / OUT light
--   dash.rack(mon, slots)           -- the name board over the drone rack
--   dash.store(mon, view)           -- the storage room's touch screen
--   dash.panel(mon, view)           -- a touch panel: a few safe buttons
--   dash.notice(mon, lines)         -- plain words on any screen (no data yet)
--
-- Every screen returns the touch zones it drew ({x1, y1, x2, y2, id}), so
-- the caller can match monitor_touch events to buttons.

local D = {}

---------------------------------------------------------------- palette
D.PAL = {
  [0] = 0x090e1a, -- 0  night: background, unscanned land
  0x121a2c,       -- 1  panel
  0x1b2741,       -- 2  raised panel, chunk grid
  0x2e3f63,       -- 3  lines, dim bars
  0x6b7c9c,       -- 4  dim text
  0xd6dfef,       -- 5  text
  0x3ad4e8,       -- 6  cyan: building, highlights
  0xa77bf0,       -- 7  violet
  0x47c46f,       -- 8  green: IN, good
  0xf2ab3c,       -- 9  amber: mining, warnings
  0xe5484d,       -- 10 red: OUT, alerts
  0xdc7b3a,       -- 11 copper orange: hazard, the coal hunter
  0x15301f,       -- 12 land, low
  0x1f442b,       -- 13 land
  0x2c5c38,       -- 14 land, high
  0xf07ab8,       -- 15 pink
}
local HEX = "0123456789abcdef"
local C = { night = 0, panel = 1, raised = 2, line = 3, dim = 4, text = 5, cyan = 6, violet = 7, teal = 8,
            green = 8, amber = 9, red = 10, copper = 11, low = 12, land = 13, high = 14, pink = 15, stone = 4 }
D.C = C

local floor, max, min, abs = math.floor, math.max, math.min, math.abs

---------------------------------------------------------------- the cell grid
local function newScreen(w, h, bg)
  local s = { w = w, h = h, ch = {}, fg = {}, bg = {}, zones = {} }
  for y = 1, h do
    s.ch[y], s.fg[y], s.bg[y] = {}, {}, {}
    for x = 1, w do s.ch[y][x], s.fg[y][x], s.bg[y][x] = " ", C.text, bg or C.night end
  end
  return s
end

local function text(s, x, y, str, fg, bg)
  if y < 1 or y > s.h then return end
  for i = 1, #str do
    local cx = x + i - 1
    if cx >= 1 and cx <= s.w then
      s.ch[y][cx] = str:sub(i, i)
      s.fg[y][cx] = fg
      if bg then s.bg[y][cx] = bg end
    end
  end
end

local function fillCells(s, x1, y1, x2, y2, bg)
  for y = max(1, y1), min(s.h, y2) do
    for x = max(1, x1), min(s.w, x2) do
      s.ch[y][x], s.bg[y][x] = " ", bg
    end
  end
end

local function pad(str, n, right)
  str = tostring(str)
  if #str > n then return str:sub(1, n) end
  if right then return string.rep(" ", n - #str) .. str end
  return str .. string.rep(" ", n - #str)
end

local function show(mon, s, pal)
  pal = pal or D.PAL
  for i = 0, 15 do mon.setPaletteColour(2 ^ i, pal[i]) end
  for y = 1, s.h do
    local t, f, b = {}, {}, {}
    for x = 1, s.w do
      t[x] = s.ch[y][x]
      f[x] = HEX:sub(s.fg[y][x] + 1, s.fg[y][x] + 1)
      b[x] = HEX:sub(s.bg[y][x] + 1, s.bg[y][x] + 1)
    end
    mon.setCursorPos(1, y)
    mon.blit(table.concat(t), table.concat(f), table.concat(b))
  end
  return s.zones
end

---------------------------------------------------------------- pixels
-- A canvas is a pixel grid laid over a block of cells; 2 pixels across and
-- 3 down per cell. Drawn into the cells with put().
local function canvas(w, h, fill)
  local c = { w = w, h = h, px = {} }
  for i = 1, w * h do c.px[i] = fill or C.night end
  return c
end

local function set(c, x, y, col)
  x, y = floor(x), floor(y)
  if x >= 0 and y >= 0 and x < c.w and y < c.h then c.px[y * c.w + x + 1] = col end
end

local function get(c, x, y)
  return c.px[y * c.w + x + 1]
end

local function box(c, x1, y1, x2, y2, col)
  for y = floor(y1), floor(y2) do
    for x = floor(x1), floor(x2) do set(c, x, y, col) end
  end
end

local function outline(c, x1, y1, x2, y2, col, dash)
  local k = 0
  local function dot(x, y)
    k = k + 1
    if not dash or k % (dash * 2) < dash then set(c, x, y, col) end
  end
  for x = x1, x2 do dot(x, y1) end
  for y = y1 + 1, y2 do dot(x2, y) end
  for x = x2 - 1, x1, -1 do dot(x, y2) end
  for y = y2 - 1, y1 + 1, -1 do dot(x1, y) end
end

local function line(c, x1, y1, x2, y2, col, dash)
  x1, y1, x2, y2 = floor(x1), floor(y1), floor(x2), floor(y2)
  local dx, dy = abs(x2 - x1), -abs(y2 - y1)
  local sx, sy = x1 < x2 and 1 or -1, y1 < y2 and 1 or -1
  local err, k = dx + dy, 0
  while true do
    k = k + 1
    if not dash or k % (dash * 2) < dash then set(c, x1, y1, col) end
    if x1 == x2 and y1 == y2 then return end
    local e2 = 2 * err
    if e2 >= dy then err = err + dy; x1 = x1 + sx end
    if e2 <= dx then err = err + dx; y1 = y1 + sy end
  end
end

local function ring(c, cx, cy, r, col, dash)
  local steps = floor(r * 6.3)
  for k = 0, steps - 1 do
    if not dash or k % (dash * 2) < dash then
      local a = k / steps * 2 * math.pi
      set(c, cx + floor(math.cos(a) * r + 0.5), cy + floor(math.sin(a) * r + 0.5), col)
    end
  end
end

-- one cell from six pixels: CC can show two colours per cell, so the two
-- most common win and any third colour joins the commoner one
local function cell(p)
  local count, order = {}, {}
  for i = 1, 6 do
    local col = p[i]
    if not count[col] then count[col] = 0; order[#order + 1] = col end
    count[col] = count[col] + 1
  end
  if #order == 1 then return " ", order[1], order[1] end
  table.sort(order, function(a, b) return count[a] > count[b] end)
  local c1, c2 = order[1], order[2]
  local bg = p[6]
  if bg ~= c1 and bg ~= c2 then bg = c1 end
  local fg = (bg == c1) and c2 or c1
  local bits, w = 0, 1
  for i = 1, 5 do
    local col = p[i]
    if col ~= c1 and col ~= c2 then col = c1 end
    if col == fg then bits = bits + w end
    w = w * 2
  end
  if bits == 0 then return " ", bg, bg end
  return string.char(128 + bits), fg, bg
end

local function put(s, c, cx, cy)
  for y = 0, floor(c.h / 3) - 1 do
    for x = 0, floor(c.w / 2) - 1 do
      local px, py = x * 2, y * 3
      local ch, fg, bg = cell({ get(c, px, py), get(c, px + 1, py), get(c, px, py + 1),
                                get(c, px + 1, py + 1), get(c, px, py + 2), get(c, px + 1, py + 2) })
      local sx, sy = cx + x, cy + y
      if sx >= 1 and sx <= s.w and sy >= 1 and sy <= s.h then
        s.ch[sy][sx], s.fg[sy][sx], s.bg[sy][sx] = ch, fg, bg
      end
    end
  end
end

---------------------------------------------------------------- big letters
-- a 3 x 5 pixel font for headlines, drawn into a canvas
local GLYPH = {
  A = "010101111101101", B = "110101110101110", C = "011100100100011", D = "110101101101110",
  E = "111100110100111", F = "111100110100100", G = "011100101101011", H = "101101111101101",
  I = "111010010010111", J = "001001001101010", K = "101101110101101", L = "100100100100111",
  M = "1000111011101011000110001", N = "10011101101110011001", P = "110101110100100",
  Q = "010101101110011", O = "01101001100110010110", R = "110101110101101", S = "011100010001110", T = "111010010010010",
  U = "101101101101111", V = "101101101101010", W = "1000110001101011010101010", X = "101101010101101",
  Y = "101101010010010", Z = "111001010100111",
  ["0"] = "111101101101111", ["1"] = "010110010010111", ["2"] = "110001010100111",
  ["3"] = "110001010001110", ["4"] = "101101111001001", ["5"] = "111100110001110",
  ["6"] = "011100111101111", ["7"] = "111001010010010", ["8"] = "111101111101111",
  ["9"] = "111101111001110", ["-"] = "000000111000000", [":"] = "000010000010000",
  ["."] = "000000000000010", ["%"] = "101001010100101", ["/"] = "001001010100100",
  [">"] = "100010001010100", ["<"] = "001010100010001", [" "] = "000000000000000",
  ["^"] = "010101000000000",
}

local function bigWidth(str, scale)
  local w = 0
  str = str:upper()
  for i = 1, #str do
    local g = GLYPH[str:sub(i, i)] or GLYPH[" "]
    w = w + #g / 5 + 1
  end
  return (w - 1) * (scale or 1)
end

local function big(c, x, y, str, col, scale)
  scale = scale or 1
  str = str:upper()
  for i = 1, #str do
    local g = GLYPH[str:sub(i, i)] or GLYPH[" "]
    local gw = #g / 5
    for gy = 0, 4 do
      for gx = 0, gw - 1 do
        local k = gy * gw + gx + 1
        if g:sub(k, k) == "1" then
          box(c, x + gx * scale, y + gy * scale, x + gx * scale + scale - 1, y + gy * scale + scale - 1, col)
        end
      end
    end
    x = x + (gw + 1) * scale
  end
end

-- a bar of pixels across n cells: share of it filled in col, rest in back
local function bar(s, x, y, n, share, col, back)
  local c = canvas(n * 2, 3, back or C.line)
  share = max(0, min(1, share or 0))
  box(c, 0, 1, floor(n * 2 * share + 0.5) - 1, 2, col)
  box(c, 0, 0, n * 2 - 1, 0, s.bg[y] and s.bg[y][x] or C.night)
  put(s, c, x, y)
end

-- orange and black stripes, like the lane floor
local function hazard(s, x, y, n, shift, col)
  local c = canvas(n * 2, 3)
  for px = 0, n * 2 - 1 do
    for py = 0, 2 do
      set(c, px, py, ((px + py + (shift or 0)) % 6 < 3) and (col or C.copper) or C.night)
    end
  end
  put(s, c, x, y)
end

local function button(s, x, y, w, label, col, id, armed)
  if armed == id then label = "TAP AGAIN" end
  fillCells(s, x, y, x + w - 1, y + 2, armed == id and C.line or C.raised)
  for k = 0, 2 do text(s, x, y + k, " ", col, col) end
  text(s, x + 2 + floor((w - 2 - #label) / 2), y + 1, label, C.text, C.raised)
  s.zones[#s.zones + 1] = { x, y, x + w - 1, y + 2, id }
end

---------------------------------------------------------------- states
local STATE = {
  mining = C.amber, ["hunting coal"] = C.copper, building = C.cyan, parked = C.dim,
  ["flying to base"] = C.text, ["fleet full"] = C.green, idle = C.dim,
}
local function stateColour(u, now)
  if now and u.seen and now - u.seen > 120000 then return C.dim end
  for k, col in pairs(STATE) do
    if (u.state or ""):find(k, 1, true) then return col end
  end
  return C.text
end
D.stateColour = stateColour

---------------------------------------------------------------- identity
-- Every drone has its own chip: one cell, its own colour, one character.
-- Miners are numbered, the specials get a letter. The same chip marks the
-- drone on the map, in the fleet list and on the depth gauge, so names
-- never have to sit on the map.
local HUES = { C.amber, C.cyan, C.green, C.pink, C.violet, C.red, C.text, C.copper }
local SPECIAL = { builder = { "B", C.cyan }, loader = { "L", C.violet }, factory = { "F", C.green },
                  helper = { "H", C.pink }, screen = { "S", C.dim }, storage = { "S", C.dim } }
-- the coal hunters (by name too, when they are not hunting just now; a
-- report under a hunter's old name counts: see the names in swarm.lua)
local HUNTER_NAMES = { Coalition = true, miner3 = true }
local okNames, names = pcall(require, "swarm")
local HUNTERS = setmetatable({}, { __index = function(_, label)
  if okNames and type(names) == "table" and names.newName then label = names.newName(label) end
  return HUNTER_NAMES[label]
end })
function D.chips(units)
  local list = {}
  for _, u in pairs(units) do list[#list + 1] = u end
  local rank = { factory = 0, builder = 1, helper = 2, loader = 3, miner = 4, screen = 8, storage = 8 }
  table.sort(list, function(a, b)
    local ra, rb = rank[a.role] or 9, rank[b.role] or 9
    if ra ~= rb then return ra < rb end
    return (a.label or "") < (b.label or "")
  end)
  local n = 0
  for _, u in ipairs(list) do
    local sp = SPECIAL[u.role]
    if (u.state or ""):find("hunting") or HUNTERS[u.label or ""] then
      u.chip, u.hue = "C", C.copper
    elseif sp then
      u.chip, u.hue = sp[1], sp[2]
    else
      n = n + 1
      u.chip, u.hue = tostring(n % 10), HUES[(n - 1) % #HUES + 1]
    end
  end
  return list
end

local function chip(s, x, y, u)
  text(s, x, y, " " .. u.chip .. " ", C.night, u.hue)
end

---------------------------------------------------------------- the map wall
-- data = {
--   units  = { [id] = unit status, ... },   -- as CommandBlock keeps them
--   maps   = { map, ... },                  -- mapper1's ground scans
--   base   = { x, y, z },                   -- crafter1 (the pit stop)
--   site   = { x1, z1, x2, z2, progress, layer, layers, done, total },
--   hut    = { x1, z1, x2, z2 },
--   plots  = { size, done = { {x, z}, ... }, active = { {x, z}, ... } },
--   trails = { [label] = { {x, z}, ... } }, -- where each drone has just been
--   clock, now, updated, events, huntRange,
-- }
-- frame counts up four times a second and drives everything that moves:
-- the radar sweep, pings, marching lines, the scrolling hazard strip.
local landCache = {}

function D.wall(mon, data, frame)
  frame = frame or 0
  mon.setTextScale(0.5)
  local W, H = mon.getSize()
  local s = newScreen(W, H)
  local now = data.now
  local list = D.chips(data.units)

  -- header
  local head = canvas(W * 2, 12, C.night)
  big(head, 4, 1, "SWARM CONTROL", C.text, 2)
  local clock = data.clock or ""
  if frame % 4 >= 2 then clock = clock:gsub(":", " ") end
  big(head, W * 2 - bigWidth(data.clock or "", 2) - 4, 1, clock, C.cyan, 2)
  put(s, head, 1, 1)
  local counts, order, total = {}, {}, 0
  for _, u in ipairs(list) do
    local k = u.state or "?"
    if not counts[k] then counts[k] = 0; order[#order + 1] = k end
    counts[k] = counts[k] + 1
    total = total + 1
  end
  table.sort(order, function(a, b)
    if counts[a] ~= counts[b] then return counts[a] > counts[b] end
    return a < b
  end)
  local x0 = floor((4 + bigWidth("SWARM CONTROL", 2)) / 2) + 5
  local x = x0
  for _, k in ipairs(order) do
    local t = counts[k] .. " " .. k:upper()
    if x + #t + 2 > W - 24 then break end
    text(s, x, 2, t, C.text)
    x = x + #t + 3
  end
  text(s, x0, 3, total .. " drones " .. string.char(183) .. " " .. #(data.plots.done or {}) .. " plots dug "
       .. string.char(183) .. " " .. (data.updated or ""), C.dim)
  hazard(s, 1, 5, W, -frame)

  -- the map: one pixel per block, north up
  local MX, MY, MW, MH = 2, 7, 120, 41          -- in cells
  local ox = data.base.x - MW + 12              -- world x at pixel 0
  local oz = data.base.z - floor(MH * 3 / 2)    -- world z at pixel 0
  local function px(wx) return wx - ox end
  local function pz(wz) return wz - oz end
  local floorY = data.base.y or 72
  local f, hut = data.site, data.hut
  local P = data.plots.size or 8

  -- the land never moves, so it is drawn once and copied each frame
  local key = #data.maps .. ":" .. #(data.plots.done or {}) .. ":" .. floor((f.progress or 0) * 100)
  if landCache.key ~= key then
    local c = canvas(MW * 2, MH * 3, C.land)
    local function heightAt(wx, wz)
      for _, m in ipairs(data.maps) do
        local i, k = wx - m.origin.x, wz - m.origin.z
        if i >= 0 and k >= 0 and i < m.size and k < m.size then
          local h = m.heights[k * m.size + i + 1]
          if h and h > -999 then return h, m.palette[m.names[k * m.size + i + 1]] or "" end
        end
      end
    end
    for gy = 0, c.h - 1 do
      for gx = 0, c.w - 1 do
        local wx, wz = gx + ox, gy + oz
        local h, name = heightAt(wx, wz)
        if not h then
          set(c, gx, gy, ((gx * 7 + gy * 13) % 11 == 0) and C.low or C.land)
        else
          local col = (h < floorY - 2 and C.low) or (h > floorY + 3 and C.high) or C.land
          if name:find("leaves") then col = C.low end
          if name:find("water") then col = C.line end
          local he, hs = heightAt(wx + 1, wz), heightAt(wx, wz + 1)
          if (he and floor(he / 3) ~= floor(h / 3)) or (hs and floor(hs / 3) ~= floor(h / 3)) then
            col = (col == C.high) and C.land or C.high
          end
          set(c, gx, gy, col)
        end
      end
    end
    for _, p in ipairs(data.plots.done or {}) do          -- dug plots shade the land
      for yy = pz(p[2]), pz(p[2]) + P - 1 do
        for xx = px(p[1]), px(p[1]) + P - 1 do
          if (xx + yy) % 2 == 0 then set(c, xx, yy, C.low) end
        end
      end
    end
    box(c, px(hut[1]), pz(hut[2]), px(hut[3]), pz(hut[4]), C.line)
    outline(c, px(hut[1]), pz(hut[2]), px(hut[3]), pz(hut[4]), C.dim)
    box(c, px(f[1]), pz(f[2]), px(f[3]), pz(f[4]), C.raised)
    local built = floor((pz(f[4]) - pz(f[2])) * (f.progress or 0))
    box(c, px(f[1]), pz(f[4]) - built, px(f[3]), pz(f[4]), C.line)
    outline(c, px(f[1]), pz(f[2]), px(f[3]), pz(f[4]), C.dim)
    outline(c, px(f[3]) + 1, pz(f[4]) - 10, px(f[3]) + 11, pz(f[4]), C.dim)
    landCache.key, landCache.px = key, c.px
  end
  local c = canvas(MW * 2, MH * 3)
  for i = 1, #landCache.px do c.px[i] = landCache.px[i] end

  local bx, bz = px(data.base.x), pz(data.base.z)
  -- the drone lane's stripes run along the back of the factory
  for wx = f[1], f[3] do
    set(c, px(wx), pz(f[2]) + 1, (((wx + frame) % 4) < 2) and C.copper or C.night)
    set(c, px(wx), pz(f[2]) + 2, (((wx + frame + 1) % 4) < 2) and C.copper or C.night)
  end
  -- plots being dug: the outline marches round
  for _, p in ipairs(data.plots.active or {}) do
    local x1, y1 = px(p[1]), pz(p[2])
    local k = 0
    local function dot(xx, yy)
      k = k + 1
      set(c, xx, yy, ((k - frame) % 4 < 2) and C.cyan or C.panel)
    end
    for xx = x1, x1 + P - 1 do dot(xx, y1) end
    for yy = y1 + 1, y1 + P - 1 do dot(x1 + P - 1, yy) end
    for xx = x1 + P - 2, x1, -1 do dot(xx, y1 + P - 1) end
    for yy = y1 + P - 2, y1 + 1, -1 do dot(x1, yy) end
  end
  -- radar: rings every 32 blocks, the hunter's range, and the sweep
  for r = 32, 128, 32 do ring(c, bx, bz, r, C.line, 2) end
  if data.huntRange then ring(c, bx, bz, data.huntRange, C.copper, 1) end
  local sweep = (frame * 9) % 360
  for k = 0, 2 do
    local a = math.rad(sweep - k * 4)
    line(c, bx, bz, bx + math.cos(a) * 150, bz + math.sin(a) * 150, C.high, k > 0 and (k + 1) or nil)
  end
  outline(c, bx - 2, bz - 2, bx + 2, bz + 2, C.cyan)
  -- trails, lines home, and a ping from anyone the sweep has just passed
  local blips = {}
  for _, u in ipairs(list) do
    if u.pos and u.role ~= "factory" then
      local x, z = px(u.pos.x), pz(u.pos.z)
      for _, t in ipairs((data.trails or {})[u.label] or {}) do set(c, px(t[1]), pz(t[2]), C.text) end
      if (u.state or ""):find("flying") then
        local dx, dz = bx - x, bz - z
        local len = max(1, floor(math.sqrt(dx * dx + dz * dz)))
        for k = 0, len do
          if (k - frame) % 4 < 2 then set(c, x + dx * k / len, z + dz * k / len, C.text) end
        end
      end
      local ang = math.deg((math.atan2 or math.atan)(z - bz, x - bx)) % 360
      local since = (sweep - ang) % 360
      if since < 60 then
        local r = 2 + floor(since / 15)
        outline(c, x - r, z - r, x + r, z + r, since < 30 and C.text or C.dim)
      end
      blips[#blips + 1] = { x = x, z = z, u = u }
    end
  end
  line(c, 6, c.h - 5, 38, c.h - 5, C.text)
  set(c, 6, c.h - 6, C.text); set(c, 38, c.h - 6, C.text)
  put(s, c, MX, MY)
  text(s, MX + 21, MY + MH - 2, " 32 blocks ", C.dim, C.panel)
  text(s, MX + 1, MY + 1, " N " .. string.char(24) .. " ", C.dim, C.panel)
  text(s, MX + floor((px(hut[1]) + px(hut[3])) / 4) - 1, MY + floor(pz(hut[2]) / 3) - 1, "HUT", C.text, C.panel)
  text(s, MX + floor(px(f[1]) / 2) + 2, MY + floor(pz(f[2]) / 3) + 2, "FACTORY", C.text, C.raised)
  text(s, MX + floor(px(f[1]) / 2) + 2, MY + floor(pz(f[2]) / 3) + 3,
       floor((f.progress or 0) * 100) .. "% built", C.cyan, C.raised)
  -- the chips: one cell each; two drones in the same spot sit side by side
  local taken = {}
  for _, b in ipairs(blips) do
    local cxl, cyl = MX + floor(b.x / 2), MY + floor(b.z / 3)
    for _, o in ipairs({ { 0, 0 }, { 3, 0 }, { -3, 0 }, { 0, -1 }, { 0, 1 }, { 3, -1 }, { -3, 1 }, { 3, 1 }, { -3, -1 }, { 6, 0 } }) do
      local lx, ly = cxl + o[1] - 1, cyl + o[2]
      local ok = lx >= MX and lx + 2 < MX + MW and ly >= MY and ly < MY + MH
      for k = lx, lx + 2 do if taken[ly * 1000 + k] then ok = false end end
      if ok then
        for k = lx, lx + 2 do taken[ly * 1000 + k] = true end
        chip(s, lx, ly, b.u)
        b.u.cell = { lx + 1, ly }
        break
      end
    end
  end

  -- right panel: the fleet, each with its chip
  local RX = MX + MW + 3
  local RW = W - RX
  local function heading(y, label)
    text(s, RX, y, label, C.dim)
    for k = RX + #label + 1, W - 1 do text(s, k, y, string.char(140), C.line) end
  end
  heading(7, "FLEET")
  local y = 8
  -- the screens' own stations are not drones: they are left off the list
  local fleet = {}
  for _, u in ipairs(list) do
    if u.role ~= "screen" and u.role ~= "storage" then fleet[#fleet + 1] = u end
  end
  local roomy = #fleet <= H - 36                 -- one a line while there is room, else two
  local half = roomy and #fleet or math.ceil(#fleet / 2)
  for k, u in ipairs(fleet) do
    local col = stateColour(u, now)
    local low = type(u.fuel) == "number" and u.fuel >= 0 and u.fuel < 400
    if roomy then
      chip(s, RX, y, u)
      text(s, RX + 4, y, pad(u.label or "?", 15), C.text)
      local busy = (u.state or ""):find("mining") or (u.state or ""):find("building") or (u.state or ""):find("hunting")
      text(s, RX + 20, y, busy and string.sub("|/-\\", (frame + k) % 4 + 1, (frame + k) % 4 + 1) or string.char(7), col)
      text(s, RX + 22, y, pad(u.state or "", 14), col)
      if type(u.fuel) == "number" and u.fuel >= 0 then
        bar(s, RX + 37, y, 13, u.fuel / 2500, (low and C.red) or (u.fuel < 1000 and C.amber) or C.green)
        text(s, RX + 51, y, pad(u.fuel, 5, true), (low and frame % 2 == 0) and C.red or C.dim)
      end
      s.zones[#s.zones + 1] = { RX, y, W, y, "unit:" .. (u.label or "") }
      y = y + 1
    else
      local cx = RX + (k > half and 30 or 0)
      local cy = 8 + (k > half and k - half or k) - 1
      chip(s, cx, cy, u)
      text(s, cx + 4, cy, pad(u.label or "?", 11), C.text)
      text(s, cx + 16, cy, pad(u.state or "", 8), col)
      if type(u.fuel) == "number" and u.fuel >= 0 then
        text(s, cx + 25, cy, pad(u.fuel, 4, true), (low and frame % 2 == 0) and C.red or C.dim)
      end
      s.zones[#s.zones + 1] = { cx, cy, cx + 28, cy, "unit:" .. (u.label or "") }
    end
  end
  if not roomy then y = 8 + half end

  -- depth gauge: a slice through the ground, every drone at its own depth
  y = y + 1
  heading(y, "DEPTH")
  local GH = 8
  local g = canvas(RW * 2 - 2, GH * 3, C.night)
  local top, bottom = 96, -64
  local function gy(wy) return floor((top - wy) / (top - bottom) * (GH * 3 - 1)) end
  box(g, 0, gy(floorY), g.w - 1, gy(0), C.raised)          -- stone
  box(g, 0, gy(0) + 1, g.w - 1, g.h - 1, C.panel)           -- deepslate
  for xx = 0, g.w - 1 do
    set(g, xx, gy(floorY), C.high)
    if xx % 3 == 0 then set(g, xx, gy(50), C.line) end      -- the roads
  end
  local col0, step = 14, floor((g.w - 18) / max(1, #fleet - 1))
  local marks = {}
  for k, u in ipairs(fleet) do
    if u.pos and u.role ~= "factory" then
      local xx = col0 + (k - 1) * step
      local d = max(0, min(GH * 3 - 1, gy(u.pos.y)))   -- (a loader flies far above the gauge's top)
      for yy = min(d, gy(floorY)), max(d, gy(floorY)) do
        if (yy + frame) % 2 == 0 then set(g, xx, yy, C.dim) end
      end
      marks[#marks + 1] = { u, floor(xx / 2) - 1, floor(d / 3) }
    end
  end
  put(s, g, RX, y + 1)
  for _, m in ipairs(marks) do chip(s, RX + m[2], y + 1 + m[3], m[1]) end
  text(s, RX, y + 1 + floor(gy(floorY) / 3), "surface", C.dim)
  text(s, RX, y + 1 + floor(gy(0) / 3) + 1, "y 0", C.dim)
  text(s, RX, y + GH, "y-64", C.dim)
  y = y + GH + 2

  -- the factory and the build
  heading(y, "FACTORY")
  local fs = data.factory or {}
  y = y + 1
  text(s, RX, y, "Coal", C.dim); text(s, RX + 9, y, pad(fs.coal or "?", 5, true), C.text)
  bar(s, RX + 16, y, 28, (fs.coal or 0) / 2048, C.copper)
  text(s, RX + 46, y, "256 kept", C.dim)
  y = y + 1
  if fs.slots then
    local share = fs.used / fs.slots
    local warn = share > 0.9
    text(s, RX, y, "Storage", C.dim)
    text(s, RX + 9, y, pad(floor(share * 100) .. "%", 5, true), (warn and frame % 4 < 2) and C.amber or C.text)
    bar(s, RX + 16, y, 28, share, warn and C.amber or C.green)
    text(s, RX + 46, y, fs.free .. " free", C.dim)
  end
  y = y + 1
  if f.progress and f.progress > 0 and f.progress < 0.999 then
    local pct = floor((f.progress or 0) * 100)
    text(s, RX, y, "Shell", C.dim)
    text(s, RX + 9, y, pad(pct .. "%", 5, true), C.cyan)
    -- the build bar has a glint running along the built part
    local pb = canvas(56, 3, C.line)
    local fill = floor(56 * (f.progress or 0) + 0.5)
    box(pb, 0, 1, fill - 1, 2, C.cyan)
    box(pb, 0, 0, 55, 0, C.night)
    if fill > 2 then local gl = (frame * 2) % fill; box(pb, gl, 1, min(fill - 1, gl + 1), 2, C.text) end
    put(s, pb, RX + 16, y)
    text(s, RX + 46, y, "layer " .. (f.layer or "?") .. "/" .. (f.layers or "?"), C.dim)
    y = y + 1
  end
  -- what is in stock, the foundry, the chunk loaders: a line each, in words
  for _, row in ipairs(data.lines or {}) do
    text(s, RX, y, pad(row[1], 9), C.dim)
    text(s, RX + 9, y, pad(row[2], RW - 10), row[3] and C[row[3]] or C.text)
    y = y + 1
  end
  y = y - 1

  -- latest: the newest line slides in at the top
  y = y + 2
  heading(y, "LATEST")
  y = y + 1
  for _, e in ipairs(data.events or {}) do
    if y > H - 4 then break end
    local u
    for _, v in ipairs(list) do if v.label == e[1] then u = v end end
    if u then chip(s, RX, y, u) end
    text(s, RX + 4, y, pad(e[2], RW - 6), C.text)
    y = y + 1
  end

  -- buttons along the bottom
  local by = H - 2
  button(s, 2, by, 18, "RECALL ALL", C.red, "recall", data.armed)
  button(s, 21, by, 14, "RESUME", C.green, "resume", data.armed)
  button(s, 36, by, 18, "PAUSE BUILD", C.amber, "pause", data.armed)
  button(s, 55, by, 16, "FIND DRONE", C.cyan, "find")
  button(s, 72, by, 14, "STORAGE", C.violet, "storage")
  if data.pick then
    text(s, RX, by, pad(data.pick[1], RW - 1), C.text)
    text(s, RX, by + 1, pad(data.pick[2] or "", RW - 1), C.dim)
    text(s, RX, by + 2, pad(data.pick[3] or "", RW - 1), C.dim)
  else
    text(s, RX, by + 1, pad(data.note or "Tap a drone to see where it is and what it is doing", RW - 1),
         data.note and C.amber or C.dim)
  end
  if data.stale then                             -- nothing heard: say so, big, over the map
    local t = " " .. data.stale .. " "
    local bx0 = MX + floor((MW - #t) / 2)
    fillCells(s, bx0 - 1, MY + 3, bx0 + #t, MY + 5, C.red)
    text(s, bx0, MY + 4, t, C.text, C.red)
  end
  for _, b in ipairs(blips) do
    if b.u.cell then s.zones[#s.zones + 1] = { b.u.cell[1] - 1, b.u.cell[2] - 1, b.u.cell[1] + 1, b.u.cell[2] + 1, "unit:" .. (b.u.label or "") } end
  end
  return show(mon, s)
end

---------------------------------------------------------------- gate lights
-- gate = { left = "OUT", right = "IN", active = "OUT" or "IN" or nil, frame = n }
-- a 2 x 1 monitor over the two tracks; the track with a drone in it lights
-- up and its chevrons run
function D.gate(mon, gate)
  mon.setTextScale(0.5)
  local W, H = mon.getSize()
  local s = newScreen(W, H)
  local c = canvas(W * 2, H * 3, C.night)
  local half = W                                -- pixels per side
  for side = 0, 1 do
    local word = side == 0 and gate.left or gate.right
    local on = gate.active == word
    local col = word == "IN" and C.green or C.red
    local dimc = C.line
    local x0 = side * half
    box(c, x0 + 2, 3, x0 + half - 3, c.h - 4, on and C.panel or C.night)
    outline(c, x0 + 2, 3, x0 + half - 3, c.h - 4, on and col or dimc)
    local tw = bigWidth(word, 2)
    big(c, x0 + floor((half - tw) / 2), 6, word, on and col or dimc, 2)
    -- chevrons: IN points into the gate (down), OUT points out (up)
    for k = 0, 3 do
      local ax = x0 + floor(half / 2) - 13 + k * 7
      local lit = on and ((k + (gate.frame or 0)) % 4 == 0)
      local ac = on and (lit and C.text or col) or dimc
      local ay = 19
      for d = 0, 2 do
        if word == "OUT" then
          set(c, ax + 2 - d, ay + d, ac); set(c, ax + 3 + d, ay + d, ac)
        else
          set(c, ax + d, ay + d, ac); set(c, ax + 5 - d, ay + d, ac)
        end
      end
    end
  end
  put(s, c, 1, 1)
  return show(mon, s)
end

---------------------------------------------------------------- the rack's name board
-- slots = { { upper = unit or nil, lower = unit or nil }, ... }  (8 columns)
-- a drone at home is lit; one out at work shows where it is
function D.rack(mon, slots, now)
  mon.setTextScale(0.5)
  local W, H = mon.getSize()
  local s = newScreen(W, H, C.panel)
  hazard(s, 1, 1, W)
  local cw = floor(W / #slots)
  for i, slot in ipairs(slots) do
    local x = (i - 1) * cw + 1
    if i < #slots then fillCells(s, x + cw - 1, 2, x + cw - 1, H, C.night) end
    for k, which in ipairs({ "upper", "lower" }) do
      local u = slot[which]
      local y = 2 + (k - 1) * 4
      text(s, x + 1, y + 1, string.char(which == "upper" and 30 or 31), C.dim, C.panel)
      if u then
        local col = stateColour(u, now)
        local home = u.home
        text(s, x + 3, y + 1, pad(u.label, cw - 5), home and C.text or C.dim, C.panel)
        local word = home and "home" or (u.state or ""):match("^%S+") or ""
        text(s, x + 3, y + 2, pad(word, 8), col, C.panel)
        if type(u.fuel) == "number" then bar(s, x + cw - 8, y + 2, 6, u.fuel / 2500, (u.fuel < 400 and C.red) or C.green) end
        if not home and u.pos then text(s, x + 3, y + 3, pad("y" .. u.pos.y .. " " .. (u.where or ""), cw - 5), C.dim, C.panel) end
      else
        text(s, x + 3, y + 1, "free", C.line, C.panel)
      end
    end
  end
  return show(mon, s)
end

---------------------------------------------------------------- the rack's live board
-- One strip of the rack (rack.lua): rows of homes, a panel per home, in
-- the same palette and style as the store screen. view = {
--   rows = { { panel, ... (8) }, ... },        -- one band per row of homes
--   pick = { label, lines } or nil,            -- a tapped drone's own screen
-- } where panel = { name, job, fill (0-1 fuel), ago, colour = green |
-- orange | blue | red | grey, word }.
local TONE = { green = C.green, orange = C.amber, blue = C.cyan, red = C.red, grey = C.line }
function D.homes(mon, view, frame)
  frame = frame or 0
  mon.setTextScale(0.5)
  local W, H = mon.getSize()
  local s = newScreen(W, H, C.night)
  if view.pick then
    fillCells(s, 1, 1, W, 1, C.raised)
    text(s, 2, 1, view.pick.label .. "'s screen", C.text, C.raised)
    text(s, W - 12, 1, "tap to close", C.dim, C.raised)
    local lines = view.pick.lines or {}
    local first = math.max(1, #lines - (H - 2))
    for i = first, #lines do text(s, 2, 2 + i - first, pad(lines[i], W - 2), C.text) end
    if #lines == 0 then text(s, 2, 3, "Nothing heard from its screen yet.", C.dim) end
    return show(mon, s)
  end
  local rows = view.rows or {}
  -- (a cell of night all round: the monitor's own margin takes the colour
  -- of the cells at its edge)
  local band = floor((H - 1) / math.max(1, #rows))
  for r, row in ipairs(rows) do
    local y0 = (r - 1) * band + 2
    local tall = band - 1
    local pw = floor((W - 2) / math.max(1, #row))
    for c, p in ipairs(row) do
      local x0 = (c - 1) * pw + 2
      local tone = TONE[p.colour] or C.dim
      local free = p.colour == "grey"
      local back = free and C.panel or C.raised
      fillCells(s, x0, y0, x0 + pw - 2, y0 + tall - 1, back)
      fillCells(s, x0, y0, x0, y0 + tall - 1, tone)              -- the state stripe
      local iw = pw - 4
      -- four lines, spread out when the band is tall enough
      local gap = tall >= 8 and 2 or 1
      local top = y0 + (tall >= 8 and floor((tall - 7) / 2) or 0)
      local function at(k) return top + (k - 1) * gap end
      local function fits(k) return at(k) <= y0 + tall - 1 end
      if free then
        text(s, x0 + 2, at(1), pad(p.name or "", iw), C.dim, back)
        if fits(2) then text(s, x0 + 2, at(2), "free", C.line, back) end
      else
        -- red blinks, so trouble is seen from across the bay
        local nameCol = (p.colour == "red" and frame % 2 == 0) and C.red or C.text
        text(s, x0 + 2, at(1), pad(p.name or "", iw), nameCol, back)
        if fits(2) then text(s, x0 + 2, at(2), pad(p.job or p.word or "", iw), tone, back) end
        if fits(3) then
          local f = p.fill or 0
          bar(s, x0 + 2, at(3), iw, f, (f < 0.05 and C.red) or (f < 0.2 and C.amber) or C.green, C.line)
        end
        if fits(4) then text(s, x0 + 2, at(4), pad(p.ago or "", iw), C.dim, back) end
      end
      s.zones[#s.zones + 1] = { x0, y0, x0 + pw - 2, y0 + tall - 1, p.name }
    end
  end
  return show(mon, s)
end

-- The board over the rack: the factory at a glance. view = {
--   lines = { "CRAFTY: ...", ... }, alarm = bool, title = "FACTORY" }
function D.opsBoard(mon, view, frame)
  frame = frame or 0
  mon.setTextScale(0.5)
  local W, H = mon.getSize()
  local s = newScreen(W, H, C.night)
  local hc = canvas(W * 2, 12, C.night)
  local title = view.title or "FACTORY"
  big(hc, 4, 1, title, view.alarm and C.red or C.text, 2)
  put(s, hc, 1, 1)
  local hx = floor((4 + bigWidth(title, 2)) / 2) + 5
  local cols = { C.text, C.text, C.text, view.alarm and C.red or C.text, C.text, C.dim }
  local y = 1
  for i, l in ipairs(view.lines or {}) do
    if y > H - 1 then break end
    local label, rest = tostring(l):match("^(%u[%u ']*:)%s*(.*)$")
    if label then
      text(s, hx, y, label, C.dim)
      text(s, hx + #label + 1, y, pad(rest, W - hx - #label - 1), cols[i] or C.text)
    else
      text(s, hx, y, pad(l, W - hx), cols[i] or C.text)
    end
    y = y + 1
  end
  if H >= 6 then hazard(s, 1, H, W, -frame, view.alarm and C.red or C.copper) end
  return show(mon, s)
end

---------------------------------------------------------------- touch panel
-- A small touch screen with a few safe buttons (3 x 2 in the tower, 2 x 2
-- by the launch bay door). Whoever draws it sends what is tapped to the
-- controller, which gives the orders: the panel itself can order nothing.
-- view = {
--   title = "LAUNCH BAY", counts = { {n, "word", colour name}, ... },
--   buttons = { {id, "LABEL", colour name}, ... },   -- top to bottom
--   armed = id or nil,                               -- tapped once: tap again
--   note = "text", noteColour = colour name, stale = "text" or nil,
-- }
function D.panel(mon, view, frame)
  frame = frame or 0
  mon.setTextScale(0.5)
  local W, H = mon.getSize()
  local s = newScreen(W, H, C.night)
  local hc = canvas(W * 2, 9, C.night)
  big(hc, 2, 2, view.title or "SWARM", C.text, 1)
  put(s, hc, 1, 1)
  hazard(s, 1, 4, W, -frame)
  local x = 2
  for _, c in ipairs(view.counts or {}) do
    local t = tostring(c[1]) .. " " .. c[2]
    if x + #t > W then break end
    text(s, x, 5, t, C[c[3] or "text"] or C.text)
    x = x + #t + 2
  end
  if view.stale then
    text(s, 2, 6, pad(view.stale, W - 2), (frame % 4 < 2) and C.red or C.amber)
  end
  local n = #(view.buttons or {})
  local top, bottom = 8, H - 2
  local each = max(3, min(4, floor((bottom - top + 1) / max(1, n))))
  for i, b in ipairs(view.buttons or {}) do
    local by = top + (i - 1) * each
    if by + 2 <= bottom then
      button(s, 2, by, W - 2, b[2], C[b[3] or "cyan"] or C.cyan, b[1], view.armed)
    end
  end
  fillCells(s, 1, H, W, H, C.panel)
  text(s, 2, H, pad(view.note or "", W - 2), C[view.noteColour or "dim"] or C.dim, C.panel)
  return show(mon, s)
end

---------------------------------------------------------------- plain words
-- For a screen with nothing to show yet (no post found, no data): a few
-- lines of words, so a dark screen is never a mystery.
function D.notice(mon, lines)
  mon.setTextScale(0.5)
  local W, H = mon.getSize()
  local s = newScreen(W, H, C.night)
  hazard(s, 1, 1, W)
  for i, l in ipairs(lines) do
    text(s, 2, 2 + i, pad(l, W - 2), i == 1 and C.text or C.dim)
  end
  return show(mon, s)
end

---------------------------------------------------------------- storage terminal
-- the storage screen has its own palette: the sections' colours from the
-- storage plan, so the screen matches the chests
D.STORE_PAL = {
  [0] = 0x090e1a, 0x121a2c, 0x1b2741, 0x2e3f63, 0x6b7c9c, 0xd6dfef,
  0x8a5bb8, -- 6  magic
  0xc0763b, -- 7  ores
  0xc24a4a, -- 8  redstone
  0x5d5d66, -- 9  fuel
  0x8d8f94, -- 10 stone
  0x6d7790, -- 11 building blocks
  0xd4a43a, -- 12 ingots (and amber notes)
  0x4aa3b8, -- 13 gems (and buttons)
  0x6f9e3a, -- 14 wood
  0xb07aa8, -- 15 mob drops
}
D.SECTION = { Magic = 6, Ores = 7, Redstone = 8, Fuel = 9, Stone = 10, Build = 11, Ingots = 12,
              Gems = 13, Wood = 14, Mobs = 15, Overflow = 4 }

-- view = {
--   used, slots, kinds, query,
--   results  = { {name, count, section}, ... },      -- first one is selected
--   where    = "2 chests",                           -- where the selection is
--   sections = { {name, used, slots}, ... },
--   walls    = { west = { [col] = { [row] = {section, share, hit} } }, east = ... },
--   feed     = { {"IN" or "OUT", count, name, section}, ... },
--   inbox = "text", outbox = "text", ready = "text",
-- }
-- Laid out for a 5 x 3 monitor (100 x 38 characters).
local function commas(n)
  local t = tostring(n)
  while true do
    local k
    t, k = t:gsub("^(%d+)(%d%d%d)", "%1,%2")
    if k == 0 then return t end
  end
end

function D.store(mon, view, frame)
  frame = frame or 0
  mon.setTextScale(0.5)
  local W, H = mon.getSize()
  local s = newScreen(W, H, C.night)
  local SEC = D.SECTION
  local function heading(x, y, w, label)
    text(s, x, y, label, C.dim)
    for k = x + #label + 1, x + w - 1 do text(s, k, y, string.char(140), C.line) end
  end

  -- header: title, and the whole store as one bar, a slice per section
  local hc = canvas(W * 2, 12, C.night)
  big(hc, 4, 1, "STORAGE", C.text, 2)
  put(s, hc, 1, 1)
  local hx = floor((4 + bigWidth("STORAGE", 2)) / 2) + 5
  local share = view.used / view.slots
  text(s, hx, 2, commas(view.used) .. " of " .. commas(view.slots) .. " slots used", C.text)
  text(s, hx + 34, 2, floor(share * 100) .. "% full " .. string.char(183) .. " " .. (view.kinds or "?") .. " kinds of item", C.dim)
  local bw = (W - hx - 1) * 2
  local sb = canvas(bw, 3, C.raised)
  local at = 0
  for _, sec in ipairs(view.sections) do
    local w = max(1, floor(bw * sec.used / view.slots + 0.5))
    if sec.used > 0 then box(sb, at, 0, at + w - 1, 2, SEC[sec.name] or C.dim); at = at + w end
  end
  put(s, sb, hx, 3)
  hazard(s, 1, 5, W, -frame, 7)

  -- left: the two chest walls, a tile per double chest, filled as it fills;
  -- the chests holding the selected item blink
  local LX = 2
  heading(LX, 7, 32, "THE WALLS")
  local function wall(y, label, cols)
    text(s, LX, y, label, C.dim)
    local c = canvas(64, 18, C.night)
    for i = 0, 9 do
      for r = 0, 2 do
        local t = cols[i + 1] and cols[i + 1][3 - r]
        local x0, y0 = i * 6 + (i >= 5 and 4 or 0), r * 6
        if t then
          local col = SEC[t.section] or C.dim
          if t.hit and frame % 2 == 0 then
            box(c, x0, y0, x0 + 4, y0 + 4, C.text)
          else
            -- an outline in the section's colour, filled from the left
            outline(c, x0, y0, x0 + 4, y0 + 4, col)
            local w = floor(5 * (t.share or 0) + 0.5)
            if w > 0 then box(c, x0, y0, x0 + w - 1, y0 + 4, col) end
          end
        end
      end
    end
    put(s, c, LX, y + 1)
  end
  local wn = view.wallNames or { "West wall", "East wall" }   -- (a controller's store has no walls)
  wall(8, wn[1], view.walls.west)
  wall(15, wn[2], view.walls.east)
  local first = view.results[1]
  if first then
    text(s, LX, 22, " ", C.text, (frame % 2 == 0) and C.text or (SEC[first.section] or C.dim))
    text(s, LX + 2, 22, "holds " .. first.name, C.dim)
  end
  heading(LX, 24, 32, "FRONT DESK")
  local arrows = string.sub(">>>   >>>   ", frame % 6 + 1, frame % 6 + 3)
  text(s, LX, 25, "IN ", 14); text(s, LX + 4, 25, pad(view.inbox or "", 28), C.text)
  text(s, LX, 26, "OUT", 12); text(s, LX + 4, 26, arrows, 12); text(s, LX + 8, 26, pad(view.outbox or "", 24), C.text)

  -- middle: search and results
  local MX, MW = 36, 33
  heading(MX, 7, MW, "FIND")
  fillCells(s, MX, 8, MX + MW - 1, 10, C.raised)
  text(s, MX, 8, " ", 13, 13); text(s, MX, 9, " ", 13, 13); text(s, MX, 10, " ", 13, 13)
  text(s, MX + 2, 9, view.query:upper() .. ((frame % 4 < 2) and "_" or " "), C.text, C.raised)
  text(s, MX + MW - 12, 9, #view.results .. " matches", C.dim, C.raised)
  local top = 1
  for _, r in ipairs(view.results) do top = max(top, r.count) end
  local y = 12
  for i, r in ipairs(view.results) do
    if y > 19 then break end
    local sel = i == 1
    local bg = sel and C.panel or C.night
    local col = SEC[r.section] or C.dim
    fillCells(s, MX, y, MX + MW - 1, y, bg)
    text(s, MX, y, "  ", col, col)
    text(s, MX + 3, y, pad(r.name, 18), sel and C.text or C.dim, bg)
    text(s, MX + 21, y, pad(commas(r.count), 6, true), C.text, bg)
    local bc = canvas(8, 3, bg)
    box(bc, 0, 1, floor(8 * r.count / top + 0.5) - 1, 1, col)
    put(s, bc, MX + 28, y)
    s.zones[#s.zones + 1] = { MX, y, MX + MW - 1, y, "pick:" .. r.name }
    y = y + 1
  end
  if first then
    text(s, MX, 21, first.name, C.text)
    local more = string.char(183) .. " " .. first.section .. " " .. string.char(183) .. " in " .. (view.where or "")
    text(s, MX + #first.name + 1, 21, more:sub(1, math.max(0, MW - #first.name - 1)), C.dim)
    if view.dest then                           -- with an Inventory Manager: where they go
      text(s, MX, 22, "to " .. view.dest, C.text)
      text(s, MX + MW - 13, 22, "tap to change", C.dim)
      s.zones[#s.zones + 1] = { MX, 22, MX + MW - 1, 22, "dest:toggle" }
    end
    button(s, MX, 23, 10, "16", 13, "take:16")
    button(s, MX + 11, 23, 10, "64", 13, "take:64")
    button(s, MX + 22, 23, 11, "ALL", 12, "take:all")
  end

  -- right: the sections, then what has just moved
  local RX, RW = 71, W - 71
  heading(RX, 7, RW, "SECTIONS")
  for i, sec in ipairs(view.sections) do
    local col = SEC[sec.name] or C.dim
    local yy = 7 + i
    local f = sec.used / max(1, sec.slots)
    text(s, RX, yy, "  ", col, col)
    text(s, RX + 3, yy, pad(sec.name, 9), C.text)
    bar(s, RX + 13, yy, 10, f, col, C.raised)
    text(s, RX + 24, yy, pad(floor(f * 100) .. "%", 4, true), (f > 0.9 and frame % 4 < 2) and 8 or C.dim)
    s.zones[#s.zones + 1] = { RX, yy, W, yy, "section:" .. sec.name }
  end
  heading(RX, 20, RW, "JUST MOVED")
  for i, e in ipairs(view.feed or {}) do
    local yy = 20 + i
    if yy > 26 then break end
    local out = e[1] == "OUT"
    text(s, RX, yy, out and "OUT" or "IN", out and 12 or 14)
    text(s, RX + 4, yy, pad(e[2], 4, true), C.text)
    text(s, RX + 9, yy, pad(e[3], RW - 12), i == 1 and C.text or C.dim)
    text(s, W - 2, yy, " ", C.text, SEC[e[4]] or C.dim)
  end

  -- keyboard: proper keycaps
  local rows = { "QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM" }
  local function key(x, yy, w, label, id, col)
    fillCells(s, x, yy, x + w - 1, yy, col or C.raised)
    text(s, x + floor((w - #label) / 2), yy, label, C.text, col or C.raised)
    local kc = canvas(w * 2, 3, C.night)
    box(kc, 0, 0, w * 2 - 1, 1, col or C.raised)
    put(s, kc, x, yy + 1)
    s.zones[#s.zones + 1] = { x, yy, x + w - 1, yy + 1, id }
  end
  for r, keys in ipairs(rows) do
    local ky = 28 + (r - 1) * 3
    local kx = 6 + (r - 1) * 3
    for k = 1, #keys do
      local ch = keys:sub(k, k)
      key(kx, ky, 5, ch, "key:" .. ch, (view.query:upper():sub(-1) == ch) and C.line or nil)
      kx = kx + 6
    end
  end
  key(70, 28, 9, "DELETE", "key:del", C.line)
  key(80, 28, 8, "CLEAR", "key:clr", C.line)
  key(54, 34, 34, "SPACE", "key: ")
  fillCells(s, 1, H, W, H, C.panel)
  text(s, 2, H, view.ready or "", 12, C.panel)
  text(s, W - 28, H, "Tap a section to browse it", C.dim, C.panel)
  return show(mon, s, D.STORE_PAL)
end

return D
