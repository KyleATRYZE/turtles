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
  0x2a9d84,       -- 7  teal: plots, parked
  0x47c46f,       -- 8  green: IN, good
  0xf2ab3c,       -- 9  amber: mining, warnings
  0xe5484d,       -- 10 red: OUT, alerts
  0xdc7b3a,       -- 11 copper orange: hazard, the coal hunter
  0x15301f,       -- 12 land, low
  0x1f442b,       -- 13 land
  0x2c5c38,       -- 14 land, high
  0x8d95a6,       -- 15 stone, buildings
}
local HEX = "0123456789abcdef"
local C = { night = 0, panel = 1, raised = 2, line = 3, dim = 4, text = 5, cyan = 6, teal = 7,
            green = 8, amber = 9, red = 10, copper = 11, low = 12, land = 13, high = 14, stone = 15 }
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
local function hazard(s, x, y, n)
  local c = canvas(n * 2, 3)
  for px = 0, n * 2 - 1 do
    for py = 0, 2 do
      set(c, px, py, ((px + py) % 6 < 3) and C.copper or C.night)
    end
  end
  put(s, c, x, y)
end

local function button(s, x, y, w, label, col, id)
  fillCells(s, x, y, x + w - 1, y + 2, C.raised)
  for k = 0, 2 do text(s, x, y + k, " ", col, col) end
  text(s, x + 2 + floor((w - 2 - #label) / 2), y + 1, label, C.text, C.raised)
  s.zones[#s.zones + 1] = { x, y, x + w - 1, y + 2, id }
end

---------------------------------------------------------------- states
local STATE = {
  mining = C.amber, ["hunting coal"] = C.copper, building = C.cyan, parked = C.teal,
  ["flying to base"] = C.text, ["fleet full"] = C.green, idle = C.teal,
}
local function stateColour(u, now)
  if now and u.seen and now - u.seen > 120000 then return C.dim end
  for k, col in pairs(STATE) do
    if (u.state or ""):find(k, 1, true) then return col end
  end
  return C.text
end
D.stateColour = stateColour

---------------------------------------------------------------- the map wall
-- data = {
--   units  = { [id] = unit status, ... },   -- as GroundControl keeps them
--   maps   = { map, ... },                  -- BrickJagger's ground scans
--   base   = { x, z },                      -- ForgeClooney (the pad stop)
--   site   = { x1, z1, x2, z2, progress, layer, layers, done, total },
--   hut    = { x1, z1, x2, z2 },
--   plots  = { size, done = { {x, z}, ... }, active = { {x, z, id}, ... } },
--   clock  = "14:42", now = epoch ms, events = { "text", ... },
-- }
function D.wall(mon, data)
  mon.setTextScale(0.5)
  local W, H = mon.getSize()
  local s = newScreen(W, H)
  local now = data.now

  -- header: the title in big letters, the fleet in a line, the clock
  local head = canvas(W * 2, 12, C.night)
  big(head, 4, 1, "SWARM CONTROL", C.text, 2)
  local clockW = bigWidth(data.clock or "", 2)
  big(head, W * 2 - clockW - 4, 1, data.clock or "", C.cyan, 2)
  put(s, head, 1, 1)
  local counts, order, total = {}, {}, 0
  for _, u in pairs(data.units) do
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
    text(s, x, 2, string.char(7), stateColour({ state = k }))
    text(s, x + 2, 2, t, C.text)
    x = x + #t + 5
  end
  text(s, x0, 3, total .. " drones " .. string.char(183) .. " " .. #(data.plots.done or {}) .. " plots dug "
       .. string.char(183) .. " " .. (data.updated or ""), C.dim)
  hazard(s, 1, 5, W)

  -- the map: one pixel per block, north up
  local MX, MY, MW, MH = 2, 7, 120, 41          -- in cells
  local c = canvas(MW * 2, MH * 3, C.night)
  local ox = data.base.x - MW + 12              -- world x at pixel 0
  local oz = data.base.z - floor(MH * 3 / 2)    -- world z at pixel 0
  local function px(wx) return wx - ox end
  local function pz(wz) return wz - oz end
  -- land from the scans: three greens by height, contour lines every 3
  local function heightAt(wx, wz)
    for _, m in ipairs(data.maps) do
      local i, k = wx - m.origin.x, wz - m.origin.z
      if i >= 0 and k >= 0 and i < m.size and k < m.size then
        local h = m.heights[k * m.size + i + 1]
        if h and h > -999 then
          local name = m.palette[m.names[k * m.size + i + 1]] or ""
          return h, name
        end
      end
    end
  end
  local floorY = data.base.y or 72
  for gy = 0, c.h - 1 do
    for gx = 0, c.w - 1 do
      local wx, wz = gx + ox, gy + oz
      local h, name = heightAt(wx, wz)
      if not h then
        -- not charted yet: plain ground with a light texture, so the map
        -- reads as one piece; scans fill in the detail as they come
        set(c, gx, gy, ((gx * 7 + gy * 13) % 11 == 0) and C.low or C.land)
      else
        local col = (h < floorY - 2 and C.low) or (h > floorY + 3 and C.high) or C.land
        if name:find("leaves") then col = C.low end
        if name:find("water") then col = C.line end
        local he = heightAt(wx + 1, wz)
        local hs = heightAt(wx, wz + 1)
        if (he and floor(he / 3) ~= floor(h / 3)) or (hs and floor(hs / 3) ~= floor(h / 3)) then
          col = (col == C.high) and C.land or C.high
        end
        set(c, gx, gy, col)
      end
    end
  end
  -- plots: they're dug underground, so the dug ones only shade the land
  -- (every other pixel); the ones being dug now are outlined in teal
  local P = data.plots.size or 8
  for _, p in ipairs(data.plots.done or {}) do
    for yy = pz(p[2]), pz(p[2]) + P - 1 do
      for xx = px(p[1]), px(p[1]) + P - 1 do
        if (xx + yy) % 2 == 0 then set(c, xx, yy, C.low) end
      end
    end
  end
  for _, p in ipairs(data.plots.active or {}) do
    box(c, px(p[1]), pz(p[2]), px(p[1]) + P - 1, pz(p[2]) + P - 1, C.raised)
    outline(c, px(p[1]), pz(p[2]), px(p[1]) + P - 1, pz(p[2]) + P - 1, C.teal)
  end
  -- the hut and the factory, with the drone lane along its back wall
  local hut = data.hut
  box(c, px(hut[1]), pz(hut[2]), px(hut[3]), pz(hut[4]), C.line)
  outline(c, px(hut[1]), pz(hut[2]), px(hut[3]), pz(hut[4]), C.stone)
  local f = data.site
  box(c, px(f[1]), pz(f[2]), px(f[3]), pz(f[4]), C.raised)
  local built = floor((pz(f[4]) - pz(f[2])) * (f.progress or 0))
  box(c, px(f[1]), pz(f[4]) - built, px(f[3]), pz(f[4]), C.line)
  outline(c, px(f[1]), pz(f[2]), px(f[3]), pz(f[4]), C.stone)
  outline(c, px(f[3]) + 1, pz(f[4]) - 10, px(f[3]) + 11, pz(f[4]), C.stone)
  for wx = f[1], f[3] do
    set(c, px(wx), pz(f[2]) + 1, ((wx % 4) < 2) and C.copper or C.night)
    set(c, px(wx), pz(f[2]) + 2, (((wx + 1) % 4) < 2) and C.copper or C.night)
  end
  -- the base: radar rings every 32 blocks, the hunter's range in copper
  local bx, bz = px(data.base.x), pz(data.base.z)
  for r = 32, 128, 32 do ring(c, bx, bz, r, C.line, 2) end
  if data.huntRange then ring(c, bx, bz, data.huntRange, C.copper, 1) end
  outline(c, bx - 2, bz - 2, bx + 2, bz + 2, C.cyan)
  set(c, bx, bz, C.cyan)
  -- drones: a blip each, a line home for anyone flying back
  local blips = {}
  for id, u in pairs(data.units) do
    if u.pos and u.role ~= "factory" then
      local x, z = px(u.pos.x), pz(u.pos.z)
      local col = stateColour(u, now)
      if (u.state or ""):find("flying") then line(c, x, z, bx, bz, C.dim, 2) end
      box(c, x - 1, z - 1, x + 1, z + 1, C.night)
      box(c, x, z, x + 1, z + 1, col)
      blips[#blips + 1] = { x = x, z = z, u = u, col = col }
    end
  end
  -- scale bar and north
  line(c, 6, c.h - 5, 6 + 32, c.h - 5, C.dim)
  set(c, 6, c.h - 6, C.dim); set(c, 38, c.h - 6, C.dim)
  put(s, c, MX, MY)
  text(s, MX + 21, MY + MH - 2, " 32 blocks ", C.dim, C.panel)
  text(s, MX + 1, MY + 1, " N " .. string.char(24) .. " ", C.dim, C.panel)
  text(s, MX + MW - 19, MY + MH - 2, " 1 pixel = 1 block ", C.dim, C.panel)
  -- labels: try right, left, above, below; skip if they would overlap
  local taken = {}
  local function free(x1, y, x2)
    if y < MY or y > MY + MH - 1 or x1 < MX or x2 > MX + MW - 1 then return false end
    for x = x1 - 1, x2 + 1 do if taken[y * 1000 + x] then return false end end
    return true
  end
  table.sort(blips, function(a, b) return (a.u.label or "") < (b.u.label or "") end)
  for _, b in ipairs(blips) do
    local name = b.u.label or "?"
    local depth = b.u.pos.y and (" y" .. b.u.pos.y) or ""
    local t = name .. depth
    local cxl, cyl = MX + floor(b.x / 2), MY + floor(b.z / 3)
    for _, o in ipairs({ { 2, 0 }, { -#t - 1, 0 }, { -floor(#t / 2), -1 }, { -floor(#t / 2), 1 }, { 2, -1 }, { 2, 1 } }) do
      local lx, ly = cxl + o[1], cyl + o[2]
      if free(lx, ly, lx + #t - 1) then
        text(s, lx, ly, name, b.col, C.panel)
        text(s, lx + #name, ly, depth, C.dim, C.panel)
        for k = lx, lx + #t - 1 do taken[ly * 1000 + k] = true end
        break
      end
    end
  end
  text(s, MX + floor((px(hut[1]) + px(hut[3])) / 4) - 1, MY + floor(pz(hut[2]) / 3) - 1, "HUT", C.stone, C.night)
  text(s, MX + floor(px(f[1]) / 2) + 2, MY + floor(pz(f[2]) / 3) + 2, "FACTORY", C.text, C.raised)
  text(s, MX + floor(px(f[1]) / 2) + 2, MY + floor(pz(f[2]) / 3) + 3,
       floor((f.progress or 0) * 100) .. "% built", C.cyan, C.raised)

  -- right panel: the fleet
  local RX = MX + MW + 3
  local RW = W - RX
  local function heading(y, label)
    text(s, RX, y, label, C.dim)
    for k = RX + #label + 1, W - 1 do text(s, k, y, string.char(140), C.line) end
  end
  heading(7, "FLEET")
  local list = {}
  for _, u in pairs(data.units) do list[#list + 1] = u end
  local rank = { factory = 0, builder = 1, loader = 2, miner = 3 }
  table.sort(list, function(a, b)
    local ra, rb = rank[a.role] or 9, rank[b.role] or 9
    if ra ~= rb then return ra < rb end
    return (a.label or "") < (b.label or "")
  end)
  local y = 8
  for _, u in ipairs(list) do
    local col = stateColour(u, now)
    text(s, RX, y, string.char(7), col)
    text(s, RX + 2, y, pad(u.label or "?", 15), C.text)
    text(s, RX + 17, y, pad(u.state or "", 14), col)
    if type(u.fuel) == "number" then
      local share = u.fuel / 2500
      bar(s, RX + 32, y, 12, share, (u.fuel < 400 and C.red) or (u.fuel < 1000 and C.amber) or C.green)
      text(s, RX + 45, y, pad(u.fuel, 5, true), C.dim)
    end
    if u.pos and u.pos.y then text(s, RX + 52, y, pad("y" .. u.pos.y, 5, true), C.dim) end
    y = y + 1
  end

  -- the factory and the build
  y = y + 1
  heading(y, "FACTORY")
  local fs = data.factory or {}
  y = y + 1
  text(s, RX, y, "Coal", C.dim); text(s, RX + 10, y, pad(fs.coal or "?", 6, true), C.text)
  bar(s, RX + 18, y, 26, (fs.coal or 0) / 2048, C.copper)
  text(s, RX + 46, y, "256 kept", C.dim)
  y = y + 1
  if fs.slots then
    local share = fs.used / fs.slots
    text(s, RX, y, "Storage", C.dim)
    text(s, RX + 10, y, pad(floor(share * 100) .. "%", 6, true), share > 0.9 and C.amber or C.text)
    bar(s, RX + 18, y, 26, share, share > 0.9 and C.amber or C.teal)
    text(s, RX + 46, y, fs.free .. " free", C.dim)
  end
  y = y + 1
  text(s, RX, y, "Plots", C.dim)
  text(s, RX + 10, y, pad(#(data.plots.done or {}), 6, true), C.text)
  text(s, RX + 18, y, "dug, " .. #(data.plots.active or {}) .. " being dug now", C.dim)

  y = y + 2
  heading(y, "FACTORY SHELL")
  local pc = canvas(RW * 2, 12, C.night)
  local pct = floor((f.progress or 0) * 100) .. "%"
  big(pc, 0, 1, pct, C.cyan, 2)
  put(s, pc, RX, y + 1)
  text(s, RX + floor(bigWidth(pct, 2) / 2) + 3, y + 2, "layer " .. (f.layer or "?") .. " of " .. (f.layers or "?"), C.text)
  text(s, RX + floor(bigWidth(pct, 2) / 2) + 3, y + 3, (f.done or 0) .. " / " .. (f.total or 0) .. " blocks", C.dim)
  y = y + 5
  bar(s, RX, y, RW - 2, f.progress or 0, C.cyan)

  y = y + 2
  heading(y, "LATEST")
  y = y + 1
  for _, e in ipairs(data.events or {}) do
    if y > H - 5 then break end
    text(s, RX, y, pad(e[1], 14), e[3] or C.dim)
    text(s, RX + 15, y, pad(e[2], RW - 16), C.text)
    y = y + 1
  end

  -- buttons along the bottom
  local by = H - 2
  button(s, 2, by, 18, "RECALL ALL", C.red, "recall")
  button(s, 21, by, 14, "RESUME", C.green, "resume")
  button(s, 36, by, 18, "PAUSE BUILD", C.amber, "pause")
  button(s, 55, by, 16, "FIND DRONE", C.cyan, "find")
  button(s, 72, by, 14, "STORAGE", C.teal, "storage")
  text(s, RX, by + 1, "Tap a drone's name to recall it or send it to work", C.dim)
  for k, u in ipairs(list) do s.zones[#s.zones + 1] = { RX, 7 + k, W, 7 + k, "unit:" .. (u.label or "") } end
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

-- view = { used, slots, query, results = { {name, count, section}, ... },
--          sections = { {name, share}, ... }, ready = "text" }
function D.store(mon, view)
  mon.setTextScale(0.5)
  local W, H = mon.getSize()
  local s = newScreen(W, H, C.night)
  local hc = canvas(W * 2, 6, C.night)
  big(hc, 2, 0, "STORAGE", C.text, 1)
  put(s, hc, 1, 1)
  local share = view.used / view.slots
  text(s, 18, 1, view.used .. " / " .. view.slots .. " slots", C.dim)
  bar(s, 18, 2, W - 19, share, 13)
  fillCells(s, 2, 4, W - 1, 4, C.raised)
  text(s, 3, 4, "Search: ", C.dim, C.raised)
  text(s, 11, 4, view.query .. "_", C.text, C.raised)
  local y = 6
  for i, r in ipairs(view.results) do
    local sel = i == 1
    local bg = sel and C.panel or C.night
    local col = D.SECTION[r.section] or C.dim
    fillCells(s, 2, y, W - 1, y, bg)
    text(s, 2, y, " ", col, col)
    text(s, 4, y, pad(r.name, 24), C.text, bg)
    text(s, 28, y, pad(r.count, 6, true), C.dim, bg)
    if sel then
      for k, b in ipairs({ "16", "64", "All" }) do
        local bx = 36 + (k - 1) * 7
        text(s, bx, y, " " .. b .. " ", C.night, 13)
        s.zones[#s.zones + 1] = { bx, y, bx + #b + 1, y, "take:" .. b }
      end
    end
    y = y + 1
  end
  -- the sections, six to a row, each with how full it is
  for i, sec in ipairs(view.sections) do
    local col = D.SECTION[sec.name] or C.dim
    local sx = 2 + ((i - 1) % 6) * 9
    local sy = 12 + floor((i - 1) / 6) * 2
    text(s, sx, sy, pad(sec.name, 8), col)
    bar(s, sx, sy + 1, 8, sec.share, col, C.raised)
    s.zones[#s.zones + 1] = { sx, sy, sx + 7, sy + 1, "section:" .. sec.name }
  end
  local rows = { "QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM" }
  for r, keys in ipairs(rows) do
    local ky = 17 + (r - 1) * 2
    local kx = 3 + (r - 1) * 2
    for k = 1, #keys do
      local ch = keys:sub(k, k)
      text(s, kx, ky, " " .. ch .. " ", C.text, C.raised)
      s.zones[#s.zones + 1] = { kx, ky, kx + 2, ky, "key:" .. ch }
      kx = kx + 4
    end
  end
  text(s, 41, 21, " DEL ", C.text, C.line)
  text(s, 47, 21, " CLR ", C.text, C.line)
  fillCells(s, 1, H, W, H, C.panel)
  text(s, 2, H, view.ready or "", 12, C.panel)
  return show(mon, s, D.STORE_PAL)
end

return D
