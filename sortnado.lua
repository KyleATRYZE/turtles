-- sortnado.lua : the storage room's computer. Whatever lands in the In
-- chest is put away; whatever is asked for (on the touch screen, by chat
-- through GroundControl, or by another turtle) is sent to the Out chest, or
-- straight into the owner's inventory through an Inventory Manager.
--
-- The store is one of two things, whichever is on the wired network:
--   a Sophisticated Storage controller: every barrel and chest joined to
--     it is one big inventory, and the controller decides which of them
--     an item goes into (the sections are then only how items are grouped
--     on the screen);
--   or, without a controller, every chest on the network, shared out
--     between the sections.
--
-- No turtle carries anything: CC moves items over the cable (pushItems).
-- This computer only keeps the books.
--
-- First run:  sortnado setup     (tells it which chests are In and Out)
local okSwarm, swarm = pcall(require, "swarm")
if not okSwarm then swarm = nil end
local okDash, dash = pcall(require, "dash")
if not okDash then dash = nil end

local CONFIG_FILE = ".storage"
local PROTOCOL    = "swarm_store"

-- sections, in the order they sit along the walls, with each one's share
-- of the chests (from the storage plan) and how items are matched to it:
-- "=name" exactly, "mod:" a whole mod, anything else a part of the name.
-- First match wins; nothing matching goes to Overflow.
local SECTIONS = {
  { "Magic", 6, { "mysticalagriculture:", "essence", "theurgy:", "prosperity", "forbidden_arcanus:rune", "stellarite" } },
  { "Ores", 8, { "raw_copper", "raw_iron", "raw_gold", "alltheores:raw", "modern_industrialization:raw", "uraninite", "oritech:raw", "_ore" } },
  { "Redstone", 6, { "redstone", "computercraft:", "advancedperipherals:", "torch", "candle" } },
  { "Fuel", 2, { "=minecraft:coal", "charcoal", "coal_block" } },
  { "Stone", 17, { "cobblestone", "cobbled_deepslate", "=minecraft:stone", "andesite", "granite", "diorite", "tuff", "basalt",
      "obsidian", "gravel", "sand", "dirt", "darkstone", "kivi", "marble", "volcanic_ash", "magma", "supplementaries:ash",
      "allthecompressed:", "flint", "ash_vent" } },
  { "Build", 3, { "polished", "brick", "tiles", "stairs", "slab", "glass", "pane", "cut_copper", "copper_block", "sign",
      "ladder", "lantern", "chain", "iron_bars" } },
  { "Ingots", 3, { "ingot", "nugget", "dust", "sulfur", "cinnabar", "saltpeter" } },
  { "Gems", 7, { "diamond", "emerald", "gem", "quartz", "crystal", "ruby", "sapphire", "peridot", "topaz", "garnet", "aquamarine",
      "alexandrite", "turquoise", "heliodor", "opal", "iolite", "bort", "fluorite", "lapis", "xychorium", "shard" } },
  { "Wood", 2, { "log", "planks", "sapling", "seeds", "stick", "leaves", "fireweed", "thistle", "currant", "fruit" } },
  { "Mobs", 2, { "rotten_flesh", "bone", "string", "gunpowder", "ender_pearl", "ender_eye", "leather", "slime", "spider_eye" } },
  { "Overflow", 4, {} },
}

local S = { items = {}, chests = {}, order = {}, feed = {}, query = "", pick = nil, frame = 0 }
local cfg = {}

---------------------------------------------------------------- sections

local sectionCache = {}
function S.sectionOf(name)
  local hit = sectionCache[name]
  if hit then return hit end
  hit = "Overflow"
  for _, sec in ipairs(SECTIONS) do
    for _, rule in ipairs(sec[3]) do
      local ok
      if rule:sub(1, 1) == "=" then ok = name == rule:sub(2)
      elseif rule:sub(-1) == ":" then ok = name:sub(1, #rule) == rule
      else ok = name:find(rule, 1, true) ~= nil end
      if ok then hit = sec[1] break end
    end
    if hit ~= "Overflow" then break end
  end
  sectionCache[name] = hit
  return hit
end

local function pretty(name)
  local s = name:gsub("^.*:", ""):gsub("_", " ")
  return s:sub(1, 1):upper() .. s:sub(2)
end

---------------------------------------------------------------- the books

local function num(name) return tonumber(name:match("_(%d+)$")) or 0 end

-- Which chests there are, and which section each belongs to: handed out in
-- the order the chests joined the network, by the plan's shares.
function S.discover()
  local names, controller = {}, nil
  S.manager = nil
  for _, n in ipairs(peripheral.getNames()) do
    if peripheral.hasType(n, "inventory_manager") or peripheral.hasType(n, "inventoryManager") then
      S.manager = n                     -- (holds the owner's memory card)
    elseif n ~= cfg.inbox and n ~= cfg.outbox and peripheral.hasType(n, "inventory")
      and not n:find("furnace") and not n:find("turtle") then
      names[#names + 1] = n
      if n == cfg.store or (not cfg.store and n:find("sophisticatedstorage:controller", 1, true)) then
        controller = controller or n
      end
    end
  end
  if controller then
    -- one inventory holds everything; other chests on the cable are not
    -- part of the store
    S.backend, S.order = "controller", { controller }
    S.chests = { [controller] = { section = "All", size = peripheral.call(controller, "size") or 0,
      used = 0, slots = {} } }
    return 1
  end
  S.backend = "chests"
  table.sort(names, function(a, b)
    if num(a) ~= num(b) then return num(a) < num(b) end
    return a < b
  end)
  local shares = 0
  for _, sec in ipairs(SECTIONS) do shares = shares + sec[2] end
  S.order, S.chests = names, {}
  local at = 0
  for i, sec in ipairs(SECTIONS) do
    local upto = i == #SECTIONS and #names or math.floor(#names * (at + sec[2]) / shares + 0.5)
    local from = math.floor(#names * at / shares + 0.5) + 1
    for k = from, upto do
      local n = names[k]
      if n then S.chests[n] = { section = sec[1], size = peripheral.call(n, "size") or 27, used = 0, slots = {} } end
    end
    at = at + sec[2]
  end
  return #names
end

-- Read one chest again and put its contents in the books.
function S.read(chest)
  local c = S.chests[chest]
  if not c then return end
  for _, st in pairs(c.slots) do
    local it = S.items[st.name]
    if it then
      it.total = it.total - st.count
      it.at[chest] = nil
      if it.total <= 0 then S.items[st.name] = nil end
    end
  end
  local ok, list = pcall(peripheral.call, chest, "list")
  c.slots, c.used = {}, 0
  if not ok or type(list) ~= "table" then return end
  for slot, st in pairs(list) do
    c.slots[slot] = { name = st.name, count = st.count }
    c.used = c.used + 1
    local it = S.items[st.name]
    if not it then
      it = { name = st.name, label = pretty(st.name), section = S.sectionOf(st.name), total = 0, at = {} }
      S.items[st.name] = it
    end
    it.total = it.total + st.count
    it.at[chest] = true
  end
end

function S.scan()
  S.items = {}
  for _, n in ipairs(S.order) do
    S.chests[n].slots = {}
    S.read(n)
  end
end

local function note(dir, count, name)
  table.insert(S.feed, 1, { dir, count, pretty(name), S.sectionOf(name) })
  while #S.feed > 6 do table.remove(S.feed) end
end

---------------------------------------------------------------- putting away

-- Where a stack should go: a chest of its section that already has some
-- and has room, then any chest of the section with a free slot, then
-- Overflow.
local function homeFor(name)
  if S.backend == "controller" then return S.order[1] end
  local sec = S.sectionOf(name)
  local it = S.items[name]
  local spare
  for _, n in ipairs(S.order) do
    local c = S.chests[n]
    if c.section == sec then
      if it and it.at[n] then
        if c.used < c.size then return n end
        for _, st in pairs(c.slots) do
          if st.name == name and st.count < 64 then return n end
        end
      end
      if not spare and c.used < c.size then spare = n end
    end
  end
  if spare then return spare end
  for _, n in ipairs(S.order) do
    local c = S.chests[n]
    if c.section == "Overflow" and c.used < c.size then return n end
  end
  for _, n in ipairs(S.order) do                 -- last resort: anywhere
    if S.chests[n].used < S.chests[n].size then return n end
  end
end

-- Empty the In chest into the store. Returns how many items moved.
function S.sortInbox()
  if not cfg.inbox then return 0 end
  local ok, list = pcall(peripheral.call, cfg.inbox, "list")
  if not ok or type(list) ~= "table" then return 0 end
  local moved, pending, touched = 0, 0, nil
  for slot, st in pairs(list) do
    local left = st.count
    for _ = 1, 4 do
      if left <= 0 then break end
      local dest = homeFor(st.name)
      if not dest then break end
      local n = peripheral.call(cfg.inbox, "pushItems", dest, slot, left) or 0
      if S.backend == "controller" then
        if n == 0 then break end             -- nowhere in the store takes it
        touched = dest                       -- (read the books once, at the end)
      else
        S.read(dest)
        if n == 0 then S.chests[dest].used = S.chests[dest].size end   -- full for this item
      end
      left = left - n
      moved = moved + n
    end
    if st.count - left > 0 then note("IN", st.count - left, st.name) end
    pending = pending + left
  end
  if touched then S.read(touched) end
  S.pending = pending
  return moved
end

---------------------------------------------------------------- handing out

function S.find(query)
  query = (query or ""):lower()
  local out = {}
  for _, it in pairs(S.items) do
    if query == "" or it.label:lower():find(query, 1, true) or it.name:find(query, 1, true) then
      out[#out + 1] = it
    end
  end
  table.sort(out, function(a, b)
    -- the very thing that was typed first, then names that start with it,
    -- then the biggest piles
    local ea, eb = a.label:lower() == query or a.name == query, b.label:lower() == query or b.name == query
    if ea ~= eb then return ea end
    local pa, pb = a.label:lower():sub(1, #query) == query, b.label:lower():sub(1, #query) == query
    if pa ~= pb then return pa end
    if a.total ~= b.total then return a.total > b.total end
    return a.name < b.name
  end)
  return out
end

-- Send count of an item to the Out chest (or another inventory on the
-- network). Returns how many went.
function S.take(name, count, to)
  to = to or cfg.outbox
  local it = S.items[name]
  if not (it and to) then return 0 end
  local left = math.min(count, it.total)
  local sent = 0
  local from = {}
  for chest in pairs(it.at) do from[#from + 1] = chest end
  table.sort(from)
  for _, chest in ipairs(from) do
    if left <= 0 then break end
    S.read(chest)                     -- (someone may have moved things by hand)
    for slot, st in pairs(S.chests[chest].slots) do
      if left <= 0 then break end
      if st.name == name then
        -- a slot can hold many stacks (stack upgrades); a push moves one
        local inSlot = st.count
        while left > 0 and inSlot > 0 do
          local n = peripheral.call(chest, "pushItems", to, slot, left) or 0
          if n == 0 then break end
          left, sent, inSlot = left - n, sent + n, inSlot - n
        end
      end
    end
    S.read(chest)
  end
  if sent > 0 then
    note("OUT", sent, name)
    if to == cfg.outbox then S.ready = sent .. " " .. pretty(name) .. " ready in the Out chest" end
  end
  return sent
end

-- Put count of an item straight into the owner's inventory, through the
-- Inventory Manager (it holds their memory card). The manager pulls from a
-- container it is told about: importItem(<where>, { name, count }), where
-- <where> is a side of the manager ("@west") or, if this version takes it,
-- a name on the wired network. Nobody tells Sortnado how the desk was put
-- together, so it finds out on the first go and remembers:
--   straight out of the store (the controller touching the manager, or a
--     chest by name) if that works;
--   otherwise by way of the Out chest standing against the manager.
-- Only ever the one item asked for is moved, and the owner's inventory is
-- never looked at. Returns how many arrived, and a note when some did not.
local SIDES = { "@west", "@east", "@north", "@south", "@up", "@down" }
local function import(from, name, count)
  local ok, n = pcall(peripheral.call, S.manager, "importItem", from, { name = name, count = count })
  if ok and type(n) == "number" then return n end
  return nil, tostring(n)
end

-- How many of an item lie in the Out chest.
local function inOut(name)
  if not cfg.outbox then return 0 end
  local ok, list = pcall(peripheral.call, cfg.outbox, "list")
  local n = 0
  if ok and type(list) == "table" then
    for _, st in pairs(list) do if st.name == name then n = n + st.count end end
  end
  return n
end

-- Put count of an item that is lying in the Out chest back in the store.
local function unstage(name, count)
  local ok, list = pcall(peripheral.call, cfg.outbox, "list")
  if not ok or type(list) ~= "table" then return end
  local touched = {}
  for slot, st in pairs(list) do
    local dest = count > 0 and st.name == name and homeFor(name)
    if dest then
      local okPush, n = pcall(peripheral.call, cfg.outbox, "pushItems", dest, slot, count)
      count = count - (okPush and tonumber(n) or 0)
      touched[dest] = true
    end
  end
  for dest in pairs(touched) do S.read(dest) end
end

function S.give(name, count)
  local it = S.items[name]
  if not it then return 0, "none in store" end
  if not S.manager then return 0, "no Inventory Manager on the storage network" end
  local want = math.min(count, it.total)
  local one = S.backend == "controller"       -- one inventory holds it all
  local waiting = inOut(name)                 -- (left in the Out chest from an earlier go)
  local got = 0
  if cfg.giveVia ~= "out" then
    -- straight from where it lies
    local sources = {}
    if one and cfg.giveFrom then
      sources = { cfg.giveFrom }
    else
      for chest in pairs(it.at) do sources[#sources + 1] = chest end
      table.sort(sources)
      if one and waiting == 0 then            -- (with none in the Out chest, only the store can answer)
        for _, side in ipairs(SIDES) do
          if side ~= cfg.outSide then sources[#sources + 1] = side end
        end
      end
    end
    local read = {}
    for _, src in ipairs(sources) do
      if got >= want then break end
      local n, err = import(src, name, want - got)
      if not n then
        S.giveError = err
      elseif n > 0 then
        got = got + n
        read[#read + 1] = one and S.order[1] or src
        if one then
          if cfg.giveFrom ~= src or cfg.giveVia ~= "direct" then
            cfg.giveFrom, cfg.giveVia = src, "direct"
            S.saveConfig()
          end
          break                               -- one store, one way in: no more would fit
        elseif cfg.giveVia ~= "direct" then
          cfg.giveVia = "direct"
          S.saveConfig()
        end
      elseif cfg.giveVia == "direct" then
        break                                 -- it works, so: inventory full, or the owner is away
      end
    end
    for _, chest in ipairs(read) do S.read(chest) end
    if got > 0 then note("OUT", got, name) end
    if got > 0 or cfg.giveVia == "direct" then
      return got, got < want and "your inventory took no more" or nil
    end
  end
  -- by way of the Out chest, which stands against the manager
  if not cfg.outbox then return 0, "no Out chest set up" end
  local staged = waiting >= want and 0 or S.take(name, want - waiting, cfg.outbox)
  local there = waiting + staged
  if there == 0 then return 0, "the Out chest is full" end
  local sides = cfg.outSide and { cfg.outSide } or SIDES
  for _, side in ipairs(sides) do
    if side ~= cfg.giveFrom then
      local n, err = import(side, name, math.min(there, want))
      if not n then
        S.giveError = err
      elseif n > 0 then
        got = n
        local now = inOut(name)
        if now < there then                   -- it came out of the Out chest: this is its side
          there = now
          if cfg.outSide ~= side or cfg.giveVia ~= "out" then
            cfg.outSide, cfg.giveVia = side, "out"
            S.saveConfig()
          end
        else                                  -- it came out of the store itself, which touches the manager
          cfg.giveFrom, cfg.giveVia = side, "direct"
          S.saveConfig()
          S.read(S.order[1])
          note("OUT", got, name)
          unstage(name, staged)               -- (what was staged is not needed)
          there = inOut(name)
        end
        break
      end
    end
  end
  if there > 0 and got < want then
    S.ready = there .. " " .. pretty(name) .. " left in the Out chest"
    return got, there .. " are in the Out chest (inventory full, or I cannot reach you)"
  end
  if got > 0 then S.ready = got .. " " .. pretty(name) .. " sent to the owner" end
  return got
end

function S.totals()
  local used, slots = 0, 0
  for _, c in pairs(S.chests) do used, slots = used + c.used, slots + c.size end
  return used, slots
end

---------------------------------------------------------------- the screen

function S.view()
  local used, slots = S.totals()
  local kinds = 0
  for _ in pairs(S.items) do kinds = kinds + 1 end
  local results = {}
  local found = S.browse and {} or S.find(S.query)
  if S.browse then
    for _, it in pairs(S.items) do if it.section == S.browse then found[#found + 1] = it end end
    table.sort(found, function(a, b) return a.total > b.total end)
  end
  -- the picked item goes first (it is the one the take buttons act on)
  if S.pick and S.items[S.pick] then results[1] = S.items[S.pick] end
  for _, it in ipairs(found) do
    if #results >= 8 then break end
    if it.name ~= S.pick then results[#results + 1] = it end
  end
  local rows = {}
  for i, it in ipairs(results) do rows[i] = { name = it.label, count = it.total, section = it.section, id = it.name } end
  local sections = {}
  local first = results[1]
  local walls = { west = {}, east = {} }
  local where, wallNames
  if S.backend == "controller" then
    -- one inventory: a section is the slots its kinds of item take up
    local bySec = {}
    for _, st in pairs(S.chests[S.order[1]].slots) do
      local sec = S.sectionOf(st.name)
      bySec[sec] = (bySec[sec] or 0) + 1
    end
    for i, sec in ipairs(SECTIONS) do
      sections[i] = { name = sec[1], used = bySec[sec[1]] or 0, slots = math.max(1, slots) }
    end
    -- the picture: the whole store as 60 tiles, a run of them per section
    local tiles, at = {}, 0
    for _, sec in ipairs(sections) do
      at = at + sec.used
      local upto = math.min(60, math.floor(60 * at / math.max(1, slots) + 0.5))
      if sec.used > 0 and upto == #tiles and #tiles < 60 then upto = upto + 1 end
      for k = #tiles + 1, upto do
        tiles[k] = { section = sec.name, share = 1, hit = first ~= nil and first.section == sec.name }
      end
    end
    for k = #tiles + 1, 60 do tiles[k] = { section = "Free", share = 0 } end
    for i, t in ipairs(tiles) do
      local col = math.floor((i - 1) / 3)
      local wall = col < 10 and walls.west or walls.east
      wall[col % 10 + 1] = wall[col % 10 + 1] or {}
      wall[col % 10 + 1][(i - 1) % 3 + 1] = t
    end
    where, wallNames = "the store", { "The store", "" }
  else
    for i, sec in ipairs(SECTIONS) do
      local u, s = 0, 0
      for _, c in pairs(S.chests) do
        if c.section == sec[1] then u, s = u + c.used, s + c.size end
      end
      sections[i] = { name = sec[1], used = u, slots = s }
    end
    -- the walls: chests in network order, three to a column, west then east
    for i, n in ipairs(S.order) do
      local c = S.chests[n]
      local col = math.floor((i - 1) / 3)
      local wall = col < 10 and walls.west or walls.east
      local k = col % 10 + 1
      wall[k] = wall[k] or {}
      wall[k][(i - 1) % 3 + 1] = { section = c.section, share = c.used / c.size,
        hit = first ~= nil and S.items[first.id] ~= nil and S.items[first.id].at[n] == true }
    end
    local n = 0
    if first and S.items[first.id] then for _ in pairs(S.items[first.id].at) do n = n + 1 end end
    where = n .. (n == 1 and " chest" or " chests")
  end
  return {
    used = used, slots = math.max(1, slots), kinds = kinds, query = S.query, results = rows,
    where = where, wallNames = wallNames,
    dest = S.manager and (S.dest == "out" and "the Out chest" or "your inventory") or nil,
    sections = sections, walls = walls, feed = S.feed,
    inbox = (S.pending or 0) > 0 and (S.pending .. " waiting: the store is full") or "empty: all sorted",
    outbox = S.outText or "empty", ready = S.ready or "Type to search, or tap a section",
  }
end

-- A tap on the screen (the id of the zone it landed in).
function S.touch(id)
  local kind, arg = id:match("^(%a+):(.*)$")
  if kind == "key" then
    S.browse = nil
    if arg == "del" then S.query = S.query:sub(1, -2)
    elseif arg == "clr" then S.query, S.pick = "", nil
    elseif #S.query < 20 then S.query = S.query .. arg:lower() end
    S.pick = nil
  elseif kind == "pick" then
    for _, it in pairs(S.items) do
      if it.label == arg then S.pick = it.name end
    end
  elseif kind == "section" then
    S.browse, S.query, S.pick = arg, "", nil
  elseif kind == "take" then
    local v = S.view()
    local first = v.results[1]
    if first then
      local n = arg == "all" and first.count or tonumber(arg) or 0
      if S.manager and S.dest ~= "out" then     -- straight into the owner's inventory
        local got, why = S.give(first.id, n)
        S.ready = got .. " " .. first.name .. " sent to you" .. (why and (": " .. why) or "")
      else
        S.take(first.id, n)
      end
    end
  elseif kind == "dest" then                    -- where the take buttons send things
    S.dest = S.dest == "out" and "player" or "out"
  end
end

---------------------------------------------------------------- setup

local function loadConfig()
  if fs.exists(CONFIG_FILE) then
    local h = fs.open(CONFIG_FILE, "r")
    cfg = textutils.unserialize(h.readAll()) or {}
    h.close()
  end
end

local function saveConfig()
  local h = fs.open(CONFIG_FILE, "w")
  h.write(textutils.serialize(cfg))
  h.close()
end
S.saveConfig = saveConfig

-- Find a chest by what changes in it: "put one item in, press Enter".
local function whichChanged(prompt)
  local function counts()
    local t = {}
    for _, n in ipairs(peripheral.getNames()) do
      if peripheral.hasType(n, "inventory") then
        local total = 0
        for _, st in pairs(peripheral.call(n, "list") or {}) do total = total + st.count end
        t[n] = total
      end
    end
    return t
  end
  local before = counts()
  print(prompt)
  read()
  local after = counts()
  for n, c in pairs(after) do
    if c ~= (before[n] or 0) then return n end
  end
end

local function setup()
  print("Storage setup. The controller (or every chest), the In and Out")
  print("chests and the Inventory Manager must be on the network (modems red).")
  cfg.inbox = whichChanged("Put one item in the IN chest, then press Enter.")
  print(cfg.inbox and ("In chest: " .. cfg.inbox) or "No chest changed.")
  cfg.outbox = whichChanged("Now put one item in the OUT chest, then press Enter.")
  print(cfg.outbox and ("Out chest: " .. cfg.outbox) or "No chest changed.")
  saveConfig()
end

---------------------------------------------------------------- running

-- A request from GroundControl or a turtle: { type = "get", item, count,
-- to }. to = "player" puts it in the owner's inventory; otherwise it goes
-- to the Out chest (or the inventory named).
function S.request(msg)
  -- by exact name, or by what it is called ("diamond")
  local it = S.items[msg.item] or S.find(msg.item)[1]
  local count = msg.count == "all" and (it and it.total or 0) or tonumber(msg.count) or 64
  local sent, why = 0, nil
  if it then
    if msg.to == "player" then sent, why = S.give(it.name, count)
    else sent = S.take(it.name, count, msg.to) end
  end
  return { type = "got", item = it and it.name, label = it and it.label, count = sent, asked = count,
    to = msg.to, why = why, left = it and S.items[it.name] and S.items[it.name].total or 0, n = msg.n }
end

if SORTNADO_TEST then
  S.cfg = function(c) cfg = c end
  S.saveConfig = function() S.saved = (S.saved or 0) + 1 end
  return S
end

local args = { ... }
loadConfig()
if args[1] == "setup" or not (cfg.inbox and cfg.outbox) then setup() end
local found = S.discover()
if S.backend == "controller" then
  print("Sortnado: one controller, " .. S.chests[S.order[1]].size .. " slots behind it.")
else
  print(("Sortnado: %d chests on the network."):format(found))
end
print(S.manager and "Inventory Manager found: items can go straight to you."
  or "No Inventory Manager on the network: items go to the Out chest.")
S.scan()
if swarm then swarm.open() end

local function report()
  if not swarm then return end
  local used, slots = S.totals()
  pcall(swarm.report, { role = "storage", state = (S.pending or 0) > 0 and "store full" or "sorting",
    storage = { used = used, slots = slots, free = slots - used } })
end

local mon = peripheral.find("monitor")
local zones = {}
local function draw()
  if not (mon and dash) then return end
  local out = pcall(peripheral.call, cfg.outbox, "list") and peripheral.call(cfg.outbox, "list") or {}
  local n, name = 0, nil
  for _, st in pairs(out) do n = n + st.count name = name or st.name end
  S.outText = n > 0 and (n .. " items, " .. pretty(name) .. (next(out, next(out)) and " and more" or "")) or "empty"
  S.frame = S.frame + 1
  local ok, z = pcall(dash.store, mon, S.view(), S.frame)
  if ok and z then zones = z end
end

parallel.waitForAny(
  function()                                    -- put things away, once a second
    local tick = 0
    while true do
      pcall(S.sortInbox)
      tick = tick + 1
      if tick % 30 == 0 then                    -- and look over a few chests again, in case
        for k = 1, math.min(3, #S.order) do     -- someone moved things by hand
          local n = S.order[(tick / 30 * 3 + k) % math.max(1, #S.order) + 1]
          if n then pcall(S.read, n) end
        end
        report()
      end
      if tick % 600 == 0 then
        S.discover()                            -- (new chests, a controller, a manager)
        S.scan()
      end
      sleep(1)
    end
  end,
  function()                                    -- the screen
    while true do
      draw()
      sleep(0.25)
    end
  end,
  function()                                    -- taps
    while true do
      local _, _, x, y = os.pullEvent("monitor_touch")
      for i = #zones, 1, -1 do
        local z = zones[i]
        if x >= z[1] and x <= z[3] and y >= z[2] and y <= z[4] then
          pcall(S.touch, z[5])
          break
        end
      end
    end
  end,
  function()                                    -- requests from GroundControl and the turtles
    while true do
      local id, msg = rednet.receive(PROTOCOL)
      if type(msg) == "table" and id then
        if msg.type == "get" and type(msg.item) == "string" then
          local ok, reply = pcall(S.request, msg)
          if not ok then reply = { type = "got", count = 0, why = tostring(reply), n = msg.n, to = msg.to } end
          rednet.send(id, reply, PROTOCOL)
        elseif msg.type == "stock" then
          local totals = {}
          for name, it in pairs(S.items) do totals[name] = it.total end
          rednet.send(id, { type = "stock", totals = totals, n = msg.n }, PROTOCOL)
        end
      end
    end
  end
)
