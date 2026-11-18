-- sortnado.lua : the storage room's computer. Whatever lands in the In
-- chest is put away; whatever is asked for (on the touch screen, by chat
-- through CommandBlock, or by another turtle) is sent to the Out chest, or
-- straight into the owner's inventory through an Inventory Manager.
--
-- The store is one of three things, whichever is on the wired network:
--   an ME Bridge (Advanced Peripherals) on an AE2 network: the whole ME
--     system is the store; items go in and out over the cable by name
--     (importItem / exportItem with a container's network name);
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
  local names, controller, bridge = {}, nil, nil
  local controllers = {}
  S.manager, S.managers = nil, {}
  for _, n in ipairs(peripheral.getNames()) do
    if peripheral.hasType(n, "inventory_manager") or peripheral.hasType(n, "inventoryManager") then
      S.manager = S.manager or n        -- (holds the owner's memory card)
      -- (one per player: each holds that player's card)
      local ok, who = pcall(peripheral.call, n, "getOwner")
      if ok and type(who) == "string" then S.managers[who:lower()] = n end
    elseif peripheral.hasType(n, "me_bridge") or peripheral.hasType(n, "meBridge") then
      bridge = bridge or n
    elseif n ~= cfg.inbox and n ~= cfg.outbox and peripheral.hasType(n, "inventory")
      and not n:find("furnace") and not n:find("turtle") then
      names[#names + 1] = n
      if n == cfg.store or (not cfg.store and n:find("sophisticatedstorage:controller", 1, true)) then
        controller = controller or n
      end
      if n:find("sophisticatedstorage:controller", 1, true) then controllers[#controllers + 1] = n end
    end
  end
  if bridge then
    -- the ME system is the store: chests on the cable are only In and Out
    S.backend, S.order = "me", { bridge }
    S.chests = { [bridge] = { section = "All", size = 0, used = 0, slots = {} } }
    return 1
  end
  if controller then
    -- one inventory holds everything; other chests on the cable are not
    -- part of the store
    -- (a controller reaches 15 blocks: a long room has one per stretch of
    -- wall, and together they are the store)
    table.sort(controllers, function(a, b)
      if num(a) ~= num(b) then return num(a) < num(b) end
      return a < b
    end)
    -- (built aside and swapped in at once: the screen and the sorter run
    -- alongside, and peripheral calls let them in half way)
    local order, chests = { controller }, {}
    for _, n in ipairs(controllers) do
      if n ~= controller then order[#order + 1] = n end
    end
    for _, n in ipairs(order) do
      chests[n] = { section = "All", size = peripheral.call(n, "size") or 0, used = 0, slots = {} }
    end
    S.poolCache = nil
    S.backend, S.order, S.chests = "controller", order, chests
    return #S.order
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

-- The ME system's books: one "slot" per kind of item (the ME system does
-- not have slots). size is how many kinds it could still take, roughly.
local function readME(bridge)
  local c = S.chests[bridge]
  local ok, list = pcall(peripheral.call, bridge, "getItems", {})
  if not ok or type(list) ~= "table" then return end
  S.items, c.slots, c.used = {}, {}, 0
  for _, e in pairs(list) do
    local name, count = e.name, tonumber(e.count or e.amount) or 0
    if type(name) == "string" and count > 0 then
      c.used = c.used + 1
      c.slots[c.used] = { name = name, count = count }
      local it = S.items[name]
      if not it then
        local label = type(e.displayName) == "string" and e.displayName:gsub("^%[", ""):gsub("%]$", "") or pretty(name)
        it = { name = name, label = label, section = S.sectionOf(name), total = 0, at = {} }
        S.items[name] = it
      end
      it.total = it.total + count
      it.at[bridge] = true
    end
  end
  -- (the ME system counts bytes, not slots: the screen's "slots" are the
  -- kinds held, scaled by how full the drives are)
  local okT, total = pcall(peripheral.call, bridge, "getTotalItemStorage")
  local okU, usedB = pcall(peripheral.call, bridge, "getUsedItemStorage")
  total, usedB = okT and tonumber(total) or 0, okU and tonumber(usedB) or 0
  local frac = total > 0 and usedB / total or 0
  c.size = (frac > 0.01 and c.used > 0) and math.floor(c.used / frac) or math.max(63, c.used * 2)
end

-- Where things live behind the controllers. Slots come in three kinds, by
-- how much one holds (getItemLimit): bulk (2,048 and up: the single-item
-- barrels), medium (over 64: barrels with stack upgrades) and small (plain
-- barrels). An item goes by how much of it there is: 256 or more to a bulk
-- slot of its own, 64 or more to the medium slots, the rest to the small
-- ones. The medium and small slots are shared out between the sections (by
-- the plan's shares), so a section's items sit together.
function S.pools()
  if S.poolCache then return S.poolCache end
  local p = { bulk = {}, med = {}, small = {} }
  for _, n in ipairs(S.order) do
    for to = 1, S.chests[n].size or 0 do
      local ok, lim = pcall(peripheral.call, n, "getItemLimit", to)
      lim = ok and tonumber(lim) or 64
      local kind = lim >= 2048 and "bulk" or lim > 64 and "med" or "small"
      p[kind][#p[kind] + 1] = { n, to }
    end
  end
  S.poolCache = p
  return p
end

function S.classOf(total)
  if total >= 256 then return { "bulk", "med", "small" } end
  if total >= 64 then return { "med", "small" } end
  return { "small", "med" }
end

-- the part of a pool that is a section's (the whole of the bulk pool)
function S.stretch(pool, kind, want)
  if kind == "bulk" then return 1, #pool end
  local shares, done = 0, 0
  for _, sec in ipairs(SECTIONS) do shares = shares + sec[2] end
  for i, sec in ipairs(SECTIONS) do
    local from = math.floor(#pool * done / shares + 0.5) + 1
    local upto = i == #SECTIONS and #pool or math.floor(#pool * (done + sec[2]) / shares + 0.5)
    if sec[1] == want then return from, upto end
    done = done + sec[2]
  end
  return 1, 0
end

-- Push count of an item from a container's slot to where it lives. total:
-- how much of it the store will then hold. Returns how many went (0: none
-- of its places took it).
function S.place(container, slot, name, count, total)
  local okP, pools = pcall(S.pools)
  if not okP then return 0 end
  local moved = 0
  local function try(n, to)
    if n == container and to == slot then return 0 end
    local ok, k = pcall(peripheral.call, container, "pushItems", n, slot, count - moved, to)
    k = ok and tonumber(k) or 0
    moved = moved + k
    return k
  end
  local function fill(pool, from, upto)
    for i = from, upto do
      local n, to = pool[i][1], pool[i][2]
      local st = S.chests[n].slots[to]
      if st and st.name == name then
        try(n, to)
        if moved >= count then return end
      end
    end
    local misses = 0
    for i = from, upto do
      local n, to = pool[i][1], pool[i][2]
      if not S.chests[n].slots[to] and not (n == container and to == slot) then
        if try(n, to) > 0 then
          S.chests[n].slots[to] = { name = name, count = 0 }   -- (taken, until the books are read again)
        else
          misses = misses + 1
          if misses >= 6 then return end
        end
        if moved >= count then return end
      end
    end
  end
  local sec = S.sectionOf(name)
  for _, kind in ipairs(S.classOf(total)) do
    local pool = pools[kind]
    if #pool > 0 then
      fill(pool, S.stretch(pool, kind, sec))
      if moved < count and kind ~= "bulk" and sec ~= "Overflow" then fill(pool, S.stretch(pool, kind, "Overflow")) end
      if moved < count and kind ~= "bulk" then fill(pool, 1, #pool) end      -- its section is full: any slot of the kind
    end
    if moved >= count then break end
  end
  return moved
end

-- Is this slot a good enough place for the item: of the first kind of slot
-- for it, and in its section's part (or Overflow's), or anywhere of that
-- kind when those parts have no free slot left?
function S.atHome(n, to, name, total)
  local pools = S.pools()
  local kind = S.classOf(total)[1]
  local pool = pools[kind]
  local inPool, free = false, false
  local function look(from, upto)
    for i = from, upto do
      if pool[i][1] == n and pool[i][2] == to then return true end
      if not S.chests[pool[i][1]].slots[pool[i][2]] then free = true end
    end
  end
  if look(S.stretch(pool, kind, S.sectionOf(name))) then return true end
  if kind ~= "bulk" and look(S.stretch(pool, kind, "Overflow")) then return true end
  if free then return false end
  for i = 1, #pool do
    if pool[i][1] == n and pool[i][2] == to then inPool = true break end
  end
  return inPool
end

-- resort Sortnado: move everything in the store to where it lives, the
-- biggest piles first (they get the bulk slots). Nothing leaves the store.
function S.resortPass(round)
  S.scan()
  local names = {}
  for name, it in pairs(S.items) do names[#names + 1] = { name, it.total } end
  table.sort(names, function(a, b) return a[2] > b[2] end)
  local movedAll, kinds = 0, 0
  for k, e in ipairs(names) do
    local name, total = e[1], e[2]
    local any = false
    for _, n in ipairs(S.order) do
      local mine = {}
      for to, st in pairs((S.chests[n] or {}).slots or {}) do
        if st.name == name and not S.atHome(n, to, name, total) then mine[#mine + 1] = { to, st.count } end
      end
      for _, m in ipairs(mine) do
        local left = m[2]
        for _ = 1, 40 do
          if left <= 0 then break end
          local got = S.place(n, m[1], name, left, total)
          if got == 0 then break end
          left, movedAll, any = left - got, movedAll + got, true
        end
        if left <= 0 then S.chests[n].slots[m[1]] = nil end
      end
    end
    if any then
      kinds = kinds + 1
      for _, n in ipairs(S.order) do S.chests[n].slots = {} end
      S.scan()
    end
    S.resortNote = ("round %d: %d of %d kinds looked at, %d moved (%d items)"):format(round, k, #names, kinds, movedAll)
  end
  S.scan()
  return kinds, movedAll
end

-- (the first round clears odds and ends out of the bulk slots; the piles
-- that found them taken move in on the next)
function S.resort()
  S.busy = true
  local kinds, items, rounds = 0, 0, 0
  for round = 1, 4 do
    local k, m = S.resortPass(round)
    kinds, items, rounds = kinds + k, items + m, round
    if k == 0 then break end
  end
  S.busy = nil
  S.resortNote = ("done in %d rounds: %d moves of a kind (%d items)"):format(rounds, kinds, items)
end


-- Put count of an item lying in a container on the network into the store
-- (the ME system, or any inventory by pushItems from the container's slot).
local function store(container, slot, name, count, dest)
  if S.backend == "me" then
    local ok, n = pcall(peripheral.call, S.order[1], "importItem", { name = name, count = count }, container)
    return ok and tonumber(n) or 0
  end
  if S.backend == "controller" then
    local n = S.place(container, slot, name, count, (S.items[name] and S.items[name].total or 0) + count)
    if n > 0 then return n end
    for _, ctl in ipairs(S.order) do              -- anywhere a controller will take it
      local ok, k = pcall(peripheral.call, container, "pushItems", ctl, slot, count)
      if ok and (tonumber(k) or 0) > 0 then return tonumber(k) end
    end
    return 0
  end
  local ok, n = pcall(peripheral.call, container, "pushItems", dest, slot, count)
  return ok and tonumber(n) or 0
end

-- Read one chest again and put its contents in the books.
function S.read(chest)
  if S.backend == "me" then return readME(chest) end
  if S.backend == "controller" and chest == S.order[1] and not S.readingAll then
    S.readingAll = true                 -- (the first controller stands for them all)
    for i = 2, #S.order do S.read(S.order[i]) end
    S.readingAll = nil
  end
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
  for _, n in ipairs(S.order) do S.chests[n].slots = {} end
  if S.backend == "controller" then
    S.read(S.order[1])                  -- (reads every controller, once each)
    return
  end
  for _, n in ipairs(S.order) do S.read(n) end
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
  if S.backend == "controller" or S.backend == "me" then return S.order[1] end
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

-- Empty the In chest (or another container: a chest being drained) into
-- the store, the biggest stacks first. Returns how many items moved (and
-- leaves how many it could not place in S.left).
function S.sortInbox(from)
  local src = from or cfg.inbox
  S.left = 0
  if not src or S.busy then return 0 end
  local ok, list = pcall(peripheral.call, src, "list")
  if not ok or type(list) ~= "table" then return 0 end
  local stacks = {}
  for slot, st in pairs(list) do stacks[#stacks + 1] = { slot, st } end
  table.sort(stacks, function(a, b) return a[2].count > b[2].count end)
  local moved, pending, touched = 0, 0, nil
  for _, e in ipairs(stacks) do
    local slot, st = e[1], e[2]
    local left = st.count
    for _ = 1, 4 do
      if left <= 0 then break end
      local dest = homeFor(st.name)
      if not dest then break end
      local n = store(src, slot, st.name, left, dest)
      if S.backend == "controller" or S.backend == "me" then
        if n == 0 then break end             -- nowhere in the store takes it
        touched = dest                       -- (read the books once, at the end)
      else
        S.read(dest)
        if n == 0 then S.chests[dest].used = S.chests[dest].size end   -- full for this item
      end
      left = left - n
      moved = moved + n
    end
    if st.count - left > 0 then note(from and "OLD" or "IN", st.count - left, st.name) end
    pending = pending + left
  end
  if touched then S.read(touched) end
  if not from then S.pending = pending end
  S.left = pending
  return moved
end

-- Draining: the order "drain Sortnado from=a,b,c" (names, or name* for
-- every container on the cable whose name starts so) has the store take in
-- everything in those containers, the fullest first, as it does the In
-- chest. Used to empty the old base's chests over the cable. The list is
-- kept in the settings, so a restart carries on. A container that is
-- empty (or gone) leaves the list; with the store full it waits a minute.
function S.drainList(spec)
  local want, out, seen = {}, {}, {}
  for p in tostring(spec or ""):gmatch("[^,]+") do want[#want + 1] = p end
  local function wanted(n)
    for _, p in ipairs(want) do
      if n == p or (p:sub(-1) == "*" and n:sub(1, #p - 1) == p:sub(1, -2)) then return true end
    end
  end
  local mine = { [cfg.inbox or ""] = true, [cfg.outbox or ""] = true }
  for _, n in ipairs(S.order) do mine[n] = true end
  for _, n in ipairs(peripheral.getNames()) do
    if wanted(n) and not mine[n] and not seen[n] and peripheral.hasType(n, "inventory")
      and not n:find("furnace") and not n:find("turtle") and not n:find("controller") then
      local total = 0
      for _, st in pairs(peripheral.call(n, "list") or {}) do total = total + st.count end
      out[#out + 1] = { n, total }
      seen[n] = true
    end
  end
  table.sort(out, function(a, b) return a[2] > b[2] end)
  local names = {}
  for _, e in ipairs(out) do names[#names + 1] = e[1] end
  return names
end

function S.drainStep()
  local list = cfg.drain
  if not list or #list == 0 or S.busy then return end
  if S.drainWait and os.clock() < S.drainWait then return end
  local n = list[1]
  local ok, items = pcall(peripheral.call, n, "list")
  if not ok or type(items) ~= "table" or next(items) == nil then
    table.remove(list, 1)
    cfg.drained = (cfg.drained or 0) + 1
    if #list == 0 then cfg.drain = nil end
    S.saveConfig()
    S.drainNote = ok and ("emptied " .. n) or (n .. " is gone")
    return
  end
  local moved = S.sortInbox(n)
  local left = S.left or 0
  if moved == 0 and left > 0 then
    S.drainWait = os.clock() + 60
    S.drainNote = "the store is full: " .. left .. " left in " .. n
  else
    S.drainNote = "draining " .. n
  end
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
  if S.backend == "me" then
    while left > 0 do
      local ok, n = pcall(peripheral.call, S.order[1], "exportItem", { name = name, count = left }, to)
      n = ok and tonumber(n) or 0
      if n <= 0 then break end
      left, sent = left - n, sent + n
    end
    S.read(S.order[1])
    if sent > 0 then
      note("OUT", sent, name)
      if to == cfg.outbox then S.ready = sent .. " " .. pretty(name) .. " ready in the Out chest" end
    end
    return sent
  end
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
  -- (where first, then what: the order that worked in the world. If a
  -- version wants them the other way round, that is found out and kept.)
  local what = { name = name, count = count }
  local ok, n
  if cfg.giveSwap then ok, n = pcall(peripheral.call, S.manager, "importItem", what, from)
  else ok, n = pcall(peripheral.call, S.manager, "importItem", from, what) end
  if ok and type(n) == "number" then return n end
  if not cfg.giveSwap and not cfg.giveVia then
    local ok2, n2 = pcall(peripheral.call, S.manager, "importItem", what, from)
    if ok2 and type(n2) == "number" then
      if n2 > 0 then cfg.giveSwap = true S.saveConfig() end
      return n2
    end
  end
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
      count = count - store(cfg.outbox, slot, name, math.min(count, st.count), dest)
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
  -- (the ME system is not a container the manager can pull from: always by
  -- way of the Out chest)
  if cfg.giveVia ~= "out" and S.backend ~= "me" then
    -- straight from where it lies
    S.giveError = nil
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
    if got == 0 and cfg.giveVia == "direct" and S.giveError and #read == 0 then
      -- the way it used to work does not any more (the store was moved away
      -- from the manager): forget it, and go by the Out chest
      cfg.giveFrom, cfg.giveVia = nil, nil
      S.saveConfig()
    end
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
  if S.backend == "controller" or S.backend == "me" then
    -- one inventory: a section is the slots its kinds of item take up
    local bySec = {}
    for _, n in ipairs(S.order) do
      for _, st in pairs((S.chests[n] or {}).slots or {}) do
        local sec = S.sectionOf(st.name)
        bySec[sec] = (bySec[sec] or 0) + 1
      end
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

-- A request from CommandBlock or a turtle: { type = "get", item, count,
-- to }. to = "player" puts it in the owner's inventory; otherwise it goes
-- to the Out chest (or the inventory named).
function S.request(msg)
  -- by exact name, or by what it is called ("diamond")
  local it = S.items[msg.item] or S.find(msg.item)[1]
  local count = msg.count == "all" and (it and it.total or 0) or tonumber(msg.count) or 64
  local sent, why = 0, nil
  if it then
    if msg.to == "player" then
      -- the manager holding this player's card (the first one, for the owner)
      local mine = type(msg.player) == "string" and S.managers and S.managers[msg.player:lower()]
      local was = S.manager
      if type(msg.player) == "string" and next(S.managers or {}) and not mine then
        sent, why = 0, "no Inventory Manager holds a memory card for " .. msg.player
      else
        local other = mine and mine ~= was
        local keep = { cfg.giveFrom, cfg.giveVia, cfg.outSide }
        if other then
          -- (another player's manager: it learns its own way in, and the
          -- owner's is put back after)
          local per = (cfg.perManager or {})[mine] or {}
          S.manager, cfg.giveFrom, cfg.giveVia, cfg.outSide = mine, per[1], per[2], per[3]
        end
        sent, why = S.give(it.name, count)
        if other then
          cfg.perManager = cfg.perManager or {}
          cfg.perManager[mine] = { cfg.giveFrom, cfg.giveVia, cfg.outSide }
          cfg.giveFrom, cfg.giveVia, cfg.outSide = keep[1], keep[2], keep[3]
          S.saveConfig()
        end
        S.manager = was
      end
    else sent = S.take(it.name, count, msg.to) end
  end
  return { type = "got", item = it and it.name, label = it and it.label, count = sent, asked = count,
    to = msg.to, why = why, left = it and S.items[it.name] and S.items[it.name].total or 0, n = msg.n }
end

---------------------------------------------------------------- the loading bays
-- A helper docked in its rack home is on the store's cable (turtle_<id>):
-- before Crafty moves in, the store serves its load from what it has, and
-- the helper fetches the rest from Crafty's pad. Once Crafty is on the same
-- cable it takes the order (bay_taken) and the store leaves it alone.
S.BAY_WAIT = 10                      -- seconds for Crafty to say it takes a bay order
S.bayQueue = {}                      -- helper id -> { msg, at }
S.RACK_CHANNEL = 4711                -- the rack's panels hear the drones through us (factory.lua K.RACK_CHANNEL)

function S.bayHeard(id, msg, now)
  if type(msg) ~= "table" then return end
  if msg.type == "bay_taken" then
    local q = S.bayQueue[tonumber(msg.forId)]
    if q and q.msg.n == msg.n then S.bayQueue[tonumber(msg.forId)] = nil end
  elseif msg.type == "materials" and type(msg.items) == "table" and type(msg.bay) == "string"
      and msg.bay:match("^turtle_%d+$") and peripheral.isPresent(msg.bay) then
    local q = S.bayQueue[id]
    if not (q and q.msg.n == msg.n) and S.bayDone ~= tostring(id) .. ":" .. tostring(msg.n) then
      S.bayQueue[id] = { msg = msg, at = (now or os.clock()) + S.BAY_WAIT }
    end
  end
end

-- one bay order: hand-ins into the In chest (sorted away as usual), what
-- the store has into the bay, and the fuel; the answer says what is missing
function S.serveBay(id, msg)
  local bay = msg.bay
  for _, slot in ipairs(type(msg.back) == "table" and msg.back or {}) do
    if tonumber(slot) and cfg.inbox then pcall(peripheral.call, cfg.inbox, "pullItems", bay, math.floor(tonumber(slot))) end
  end
  local given, missing = {}, {}
  for _, l in ipairs(msg.items) do
    local name, want = l[1], math.floor(tonumber(l[2]) or 0)
    if type(name) == "string" and want > 0 then
      local got = (S.items[name] and S.take(name, want, bay)) or 0
      given[name] = got
      if got < want then missing[name] = want - got end
    end
  end
  local fuel = math.floor(tonumber(msg.fuel) or 0)
  if fuel > 0 then
    local buckets = math.min(4, math.floor(fuel * 80 / 1000 + 0.5))
    local lava = buckets > 0 and S.items["minecraft:lava_bucket"] and S.take("minecraft:lava_bucket", buckets, bay) or 0
    local coal = math.ceil(math.max(0, fuel * 80 - lava * 1000) / 80)
    for _, c in ipairs({ "minecraft:coal", "minecraft:charcoal" }) do
      if coal > 0 and S.items[c] then coal = coal - S.take(c, coal, bay) end
    end
  end
  S.bayDone = tostring(id) .. ":" .. tostring(msg.n)
  rednet.send(id, { type = "materials_ready", forId = id, n = msg.n, given = given, missing = missing, full = {},
    bay = true, by = "Sortnado" }, "swarm_job")
  S.bayNote = "loaded " .. bay
  return given, missing
end

function S.bayStep(now)
  now = now or os.clock()
  for id, q in pairs(S.bayQueue) do
    if now >= q.at then
      S.bayQueue[id] = nil
      if peripheral.isPresent(q.msg.bay) then pcall(S.serveBay, id, q.msg) end
    end
  end
end

-- the drones' statuses and reboot orders, on to the rack's panels over the cable
function S.relay(msg)
  if type(msg) ~= "table" then return end
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "modem" and not peripheral.call(name, "isWireless") then
      pcall(peripheral.call, name, "transmit", S.RACK_CHANNEL, S.RACK_CHANNEL, msg)
      return
    end
  end
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
if S.backend == "me" then
  print("Sortnado: the ME system (" .. S.order[1] .. ") is the store.")
elseif S.backend == "controller" then
  local all = 0
  for _, n in ipairs(S.order) do all = all + S.chests[n].size end
  print("Sortnado: " .. #S.order .. " controller(s), " .. all .. " slots behind them.")
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
  local t = { role = "storage", state = (S.pending or 0) > 0 and "store full" or "sorting",
    storage = { used = used, slots = slots, free = slots - used }, survey = S.survey, resort = S.resortNote,
    drain = (cfg.drain or S.drainNote) and { left = cfg.drain and #cfg.drain or 0, done = cfg.drained,
      next = cfg.drain and cfg.drain[1], note = S.drainNote } or nil }
  pcall(swarm.report, t)
  if S.relay then pcall(S.relay, { role = "storage", label = t.label, state = t.state, storage = t.storage }) end
end

-- survey Sortnado: what every slot of the store can hold and what is in it,
-- for planning where things should live. Per controller: the slots' limits
-- as runs ("64*27,2048*1,..." in slot order) and the items ("slot=name*n").
function S.makeSurvey()
  local out = {}
  for _, n in ipairs(S.order) do
    local c = S.chests[n]
    local runs, last, run = {}, nil, 0
    for slot = 1, c.size or 0 do
      local ok, lim = pcall(peripheral.call, n, "getItemLimit", slot)
      lim = ok and tonumber(lim) or -1
      if lim == last then run = run + 1 else
        if last then runs[#runs + 1] = last .. "*" .. run end
        last, run = lim, 1
      end
    end
    if last then runs[#runs + 1] = last .. "*" .. run end
    local items = {}
    local okL, list = pcall(peripheral.call, n, "list")
    if okL and type(list) == "table" then
      for slot, st in pairs(list) do items[#items + 1] = slot .. "=" .. st.name .. "*" .. st.count end
    end
    out[#out + 1] = { name = n, size = c.size, limits = table.concat(runs, ","), items = table.concat(items, ";") }
  end
  S.survey = out
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
      pcall(S.drainStep)
      tick = tick + 1
      if tick % 30 == 0 and S.busy then
        report()
      elseif tick % 30 == 0 then                -- and look over a few chests again, in case
        for k = 1, math.min(3, #S.order) do     -- someone moved things by hand
          local n = S.order[(tick / 30 * 3 + k) % math.max(1, #S.order) + 1]
          if n then pcall(S.read, n) end
        end
        report()
      end
      if tick % 600 == 0 and not S.busy then
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
  function()                                    -- orders from the repository
    if not swarm then while true do sleep(3600) end end
    while true do
      local c = swarm.waitCommand()
      if c.cmd == "reboot" or c.cmd == "update" then
        pcall(S.relay, { type = "cmd", cmd = c })
        os.reboot()
      elseif c.cmd == "survey" then
        pcall(S.makeSurvey)
        report()
      elseif c.cmd == "resort" then
        local okR, err = pcall(S.resort)
        S.busy = nil
        if not okR then S.resortNote = "stopped: " .. tostring(err) end
        report()
      elseif c.cmd == "drain" then
        -- drain Sortnado from=minecraft:chest_3,minecraft:chest_4 (or minecraft:chest_*);
        -- drain Sortnado stop=1
        if c.stop then
          cfg.drain = nil
          S.drainNote = "stopped"
        else
          local okL, names = pcall(S.drainList, c.from)
          cfg.drain = okL and #names > 0 and names or nil
          cfg.drained = 0
          S.drainNote = okL and (#names .. " to drain") or ("drain: " .. tostring(names))
        end
        S.saveConfig()
        report()
      elseif c.cmd == "ping" then
        report()
      end
    end
  end,
  function()                                    -- the loading bays, and the drones' news for the rack
    S.bayTimer = os.startTimer(2)
    while true do
      local ev, id, msg, proto = os.pullEvent()
      if ev == "rednet_message" and proto == "swarm_job" then
        pcall(S.bayHeard, id, msg)
      elseif ev == "rednet_message" and proto == "swarm" and type(msg) == "table"
          and (msg.role == "helper" or msg.role == "miner" or msg.role == "loader" or msg.role == "builder"
            or msg.role == "factory") then
        S.relay(msg)
      end
      pcall(S.bayStep)
      if ev == "timer" and id == S.bayTimer then S.bayTimer = os.startTimer(2) end
    end
  end,
  function()                                    -- requests from CommandBlock and the turtles
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
