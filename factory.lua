-- factory.lua : builds mining turtles from raw materials and runs the base.
--
-- Runs on a Crafty Turtle (with an ender modem) that sits on a wired modem.
-- Chests and a furnace on the same wired network are its storage and smelter.
--
-- It also runs the base for the swarm:
--   * places each new miner on the launch pad (the space above the disk
--     drive), fuels it and switches it on; the disk installs its software
--   * hands every miner its own plot to dig
--   * empties the drop-off chest beside it (where miners unload) into storage
--   * gives fuel to a miner that has run out
--
-- It smelts and crafts every intermediate part itself:
--   cobblestone -> stone, raw iron -> ingots, sand -> glass -> panes,
--   logs -> planks -> chest / sticks, pickaxe, computer, turtle.

local okSwarm, swarm = pcall(require, "swarm")
if not okSwarm then swarm = nil end

local MAX_MINERS   = 7     -- size of the fleet this base will run
local CHECK_EVERY  = 10    -- seconds between checks when idle
local NEWBORN_COAL = 24    -- coal given to each new miner
local PLOT_SIZE    = 8     -- each plot is this many blocks square
local KEEP_OUT     = 24    -- no plot comes closer to the factory than this
local TOP_Y_MAX    = 50    -- plots are dug from this height down
local BOTTOM_Y     = -58
local CRUISE_UP    = 45    -- (no longer used: miners now travel underground)

local PAUSE_FILE   = ".factory_paused"
local BASE_FILE    = ".base"
local PLOTS_FILE   = ".plots"
local STAGE_FILE   = ".assembling"
local JOB_PROTOCOL = "swarm_job"

local DIRS = {
  [0] = { x = 1, z = 0 }, [1] = { x = 0, z = 1 },
  [2] = { x = -1, z = 0 }, [3] = { x = 0, z = -1 },
}

-- Written onto the floppy disk. A brand-new turtle placed on the launch pad
-- boots from it and installs itself; anything already set up boots normally.
local DISK_STARTUP = [[
-- Written by the factory. Do not edit: it is rewritten automatically.
if fs.exists("/startup.lua") then
  shell.run("/startup.lua")
  return
end
if not turtle then return end
os.setComputerLabel("miner-" .. os.getComputerID())
shell.run("wget", "run", "https://raw.githubusercontent.com/KyleATRYZE/turtles/main/install.lua")
]]

local BUCKET   = "minecraft:bucket"
local SCANNER  = "advancedperipherals:geo_scanner"
local CORE     = "advancedperipherals:weak_automata_core"
local TURTLE   = "computercraft:turtle_normal"
local COMPUTER = "computercraft:computer_normal"
local MODEM    = "computercraft:wireless_modem_advanced"
local PICKAXE  = "minecraft:diamond_pickaxe"

-- Names starting with "#" are groups, matched by the end of the item name.
local GROUPS = {
  ["#planks"] = { "_planks" },
  ["#log"]    = { "_log", "_stem" },
  ["#fuel"]   = { "minecraft:coal", "minecraft:charcoal" },
}

-- How to make things. grid = 3x3 crafting layout, read left to right, top to
-- bottom ("" = empty). smelt = furnace input. yield = items per craft.
local RECIPES = {
  ["minecraft:stone"]      = { smelt = "minecraft:cobblestone" },
  ["minecraft:iron_ingot"] = { smelt = "minecraft:raw_iron" },
  ["minecraft:gold_ingot"] = { smelt = "minecraft:raw_gold" },
  ["minecraft:glass"]      = { smelt = "minecraft:sand" },
  ["minecraft:glass_pane"] = {
    yield = 16,
    grid = { "G", "G", "G", "G", "G", "G", "", "", "" },
    key = { G = "minecraft:glass" },
  },
  ["#planks"] = {
    yield = 4,
    grid = { "L", "", "", "", "", "", "", "", "" },
    key = { L = "#log" },
  },
  ["minecraft:stick"] = {
    yield = 4,
    grid = { "P", "", "", "P", "", "", "", "", "" },
    key = { P = "#planks" },
  },
  ["minecraft:chest"] = {
    grid = { "P", "P", "P", "P", "", "P", "P", "P", "P" },
    key = { P = "#planks" },
  },
  [PICKAXE] = {
    grid = { "D", "D", "D", "", "S", "", "", "S", "" },
    key = { D = "minecraft:diamond", S = "minecraft:stick" },
  },
  [MODEM] = {
    grid = { "G", "G", "G", "G", "E", "G", "G", "G", "G" },
    key = { G = "minecraft:gold_ingot", E = "minecraft:ender_eye" },
  },
  -- building blocks (2 x 2 recipes give 4)
  ["minecraft:polished_deepslate"] = {
    yield = 4, grid = { "D", "D", "", "D", "D", "", "", "", "" },
    key = { D = "minecraft:cobbled_deepslate" },
  },
  ["minecraft:deepslate_bricks"] = {
    yield = 4, grid = { "D", "D", "", "D", "D", "", "", "", "" },
    key = { D = "minecraft:polished_deepslate" },
  },
  ["minecraft:deepslate_tiles"] = {
    yield = 4, grid = { "D", "D", "", "D", "D", "", "", "", "" },
    key = { D = "minecraft:deepslate_bricks" },
  },
  ["minecraft:deepslate_tile_stairs"] = {
    yield = 4, grid = { "T", "", "", "T", "T", "", "T", "T", "T" },
    key = { T = "minecraft:deepslate_tiles" },
  },
  ["minecraft:stone_bricks"] = {
    yield = 4, grid = { "S", "S", "", "S", "S", "", "", "", "" },
    key = { S = "minecraft:stone" },
  },
  ["minecraft:cracked_stone_bricks"] = { smelt = "minecraft:stone_bricks" },
  ["minecraft:copper_ingot"] = { smelt = "minecraft:raw_copper" },
  ["minecraft:copper_block"] = {
    grid = { "C", "C", "C", "C", "C", "C", "C", "C", "C" },
    key = { C = "minecraft:copper_ingot" },
  },
  ["minecraft:cut_copper"] = {
    yield = 4, grid = { "C", "C", "", "C", "C", "", "", "", "" },
    key = { C = "minecraft:copper_block" },
  },
  ["minecraft:cut_copper_slab"] = {
    yield = 6, grid = { "C", "C", "C", "", "", "", "", "", "" },
    key = { C = "minecraft:cut_copper" },
  },
  -- unpacking storage blocks (packed by tidyStorage when the chests fill up)
  ["minecraft:redstone"] = { unpack = true, yield = 9, grid = { "B", "", "", "", "", "", "", "", "" },
    key = { B = "minecraft:redstone_block" } },
  ["minecraft:raw_copper"] = { unpack = true, yield = 9, grid = { "B", "", "", "", "", "", "", "", "" },
    key = { B = "minecraft:raw_copper_block" } },
  ["minecraft:raw_iron"] = { unpack = true, yield = 9, grid = { "B", "", "", "", "", "", "", "", "" },
    key = { B = "minecraft:raw_iron_block" } },
  ["minecraft:raw_gold"] = { unpack = true, yield = 9, grid = { "B", "", "", "", "", "", "", "", "" },
    key = { B = "minecraft:raw_gold_block" } },
  ["minecraft:cobblestone"] = { unpack = true, yield = 9, grid = { "B", "", "", "", "", "", "", "", "" },
    key = { B = "allthecompressed:cobblestone_1x" } },
  ["minecraft:cobbled_deepslate"] = { unpack = true, yield = 9, grid = { "B", "", "", "", "", "", "", "", "" },
    key = { B = "allthecompressed:cobbled_deepslate_1x" } },
  ["minecraft:dirt"] = { unpack = true, yield = 9, grid = { "B", "", "", "", "", "", "", "", "" },
    key = { B = "allthecompressed:dirt_1x" } },
  [BUCKET] = {
    grid = { "I", "", "I", "", "I", "", "", "", "" },
    key = { I = "minecraft:iron_ingot" },
  },
  ["minecraft:blaze_powder"] = {
    yield = 2,
    grid = { "R", "", "", "", "", "", "", "", "" },
    key = { R = "minecraft:blaze_rod" },
  },
  ["minecraft:ender_eye"] = {
    grid = { "P", "B", "", "", "", "", "", "", "" },
    key = { P = "minecraft:ender_pearl", B = "minecraft:blaze_powder" },
  },
  [COMPUTER] = {
    grid = { "S", "S", "S", "S", "R", "S", "S", "P", "S" },
    key = { S = "minecraft:stone", R = "minecraft:redstone", P = "minecraft:glass_pane" },
  },
  [TURTLE] = {
    grid = { "I", "I", "I", "I", "C", "I", "I", "K", "I" },
    key = { I = "minecraft:iron_ingot", C = COMPUTER, K = "minecraft:chest" },
  },
}

-- What one finished miner is assembled from.
local MINER_PARTS = { [TURTLE] = 1, [PICKAXE] = 1, [MODEM] = 1 }

-- crafting grid position (1-9) -> turtle inventory slot
local GRID_SLOT = { 1, 2, 3, 5, 6, 7, 9, 10, 11 }

---------------------------------------------------------------- reporting

local logLines = {}
local rawPrint = print
local function print(...)
  rawPrint(...)
  local parts = table.pack(...)
  for i = 1, parts.n do parts[i] = tostring(parts[i]) end
  logLines[#logLines + 1] = table.concat(parts, " ")
  while #logLines > 6 do table.remove(logLines, 1) end
end

local built = 0
local lastState = "starting"
local lastStock = {}
local lastMissing = {}
local lastNetwork = {}

-- saved tables
local function loadTable(file)
  if not fs.exists(file) then return nil end
  local h = fs.open(file, "r")
  local t = textutils.unserialize(h.readAll())
  h.close()
  if type(t) == "table" then return t end
  return nil
end

local function saveTable(file, t)
  local h = fs.open(file, "w")
  h.write(textutils.serialize(t))
  h.close()
end

local base = loadTable(BASE_FILE)                 -- where everything is
local plots = loadTable(PLOTS_FILE) or { next = 1, byId = {}, done = 0 }
local pending = 0        -- miners launched that have not asked for a plot yet
local fuelQueue = {}     -- miners waiting on the launch pad for fuel
local FUEL_RESERVE = 256 -- coal never handed out to miners
local HELPERS      = 3   -- builder's mates to make (mining turtles running helper.lua);
                         -- the third is the lumberjack
local HELPER_NAMES = { "MortarKombat", "WallStreet", "TimberLake", "HodStewart" }
local launchingHelper = false
local bucketQueue = {}   -- miners waiting on the launch pad for a bucket
local orders = {}        -- builder material orders, by computer id
local served = {}        -- the last order number served, by computer id

-- Miners with a plot, plus miners between plots (they finished one and
-- will be back for the next, so their place in the fleet is kept).
local function activeCount()
  local n = 0
  for _ in pairs(plots.byId) do n = n + 1 end
  for _ in pairs(plots.between or {}) do n = n + 1 end
  return n
end

local stores = {}    -- names of storage inventories

-- How full the storage chests are (checked at most every 30 seconds).
local space, spaceAt
local function storageSpace()
  if spaceAt and os.clock() - spaceAt < 30 then return space end
  local total, used = 0, 0
  for _, inv in ipairs(stores) do
    local okSize, size = pcall(peripheral.call, inv, "size")
    local okList, list = pcall(peripheral.call, inv, "list")
    if okSize and size then total = total + size end
    if okList and list then for _ in pairs(list) do used = used + 1 end end
  end
  space, spaceAt = { slots = total, used = used, free = total - used }, os.clock()
  return space
end

local function report(state)
  lastState = state
  if not swarm then return end
  pcall(swarm.report, {
    role = "factory",
    state = state,
    built = built,
    storage = storageSpace(),
    inv = lastStock,
    missing = lastMissing,
    network = lastNetwork,
    base = base,
    fleet = { active = activeCount(), launching = pending, max = MAX_MINERS,
      builder = plots.builderId,
      plotsDone = plots.done, nextPlot = plots.next, byId = plots.byId },
    log = logLines,
  })
end

---------------------------------------------------------------- network

local modem      -- the wired modem behind the turtle
local selfName   -- this turtle's name on the wired network
local furnaces = {}  -- names of furnaces

local function matches(wanted, name)
  if wanted:sub(1, 1) ~= "#" then return wanted == name end
  for _, suffix in ipairs(GROUPS[wanted] or {}) do
    if name == suffix or name:sub(-#suffix) == suffix then return true end
  end
  return false
end

local function shortName(name)
  return (name:gsub("^#", ""):gsub("^[%w_]+:", ""):gsub("_", " "))
end

-- Find the wired modem and everything attached to the network.
local function discover()
  modem = peripheral.find("modem", function(_, m) return not m.isWireless() end)
  if not modem then
    return false, "no wired modem next to me"
  end
  selfName = modem.getNameLocal()
  if not selfName then
    return false, "right-click the modem next to me to switch it on"
  end
  stores, furnaces = {}, {}
  lastNetwork = {}
  for _, name in ipairs(modem.getNamesRemote()) do
    lastNetwork[#lastNetwork + 1] = name
    if peripheral.hasType(name, "inventory") then
      if name:find("^minecraft:furnace_") then
        furnaces[#furnaces + 1] = name
      elseif name:find("furnace", 1, true) or name:find("smoker", 1, true)
        or name:find("turtle", 1, true) or name:find("computer", 1, true) then
        -- other machines and computers are not storage
      else
        stores[#stores + 1] = name
      end
    end
  end
  table.sort(stores)
  table.sort(furnaces)
  if #stores == 0 then
    return false, "no chest on the network (right-click its modem)"
  end
  return true
end

-- Every stack in storage: { inv, slot, name, count }
local function listStorage()
  local stacks = {}
  for _, inv in ipairs(stores) do
    local ok, list = pcall(peripheral.call, inv, "list")
    if ok and list then
      for slot, item in pairs(list) do
        stacks[#stacks + 1] = { inv = inv, slot = slot, name = item.name, count = item.count }
      end
    end
  end
  return stacks
end

-- Totals by item name.
local function stockTotals()
  local totals = {}
  for _, s in ipairs(listStorage()) do
    totals[s.name] = (totals[s.name] or 0) + s.count
  end
  return totals
end

-- Move `count` of an item (or group) from storage into a turtle slot.
local function pull(wanted, count, slot)
  local need = count
  for _, s in ipairs(listStorage()) do
    if need <= 0 then break end
    if matches(wanted, s.name) then
      local moved = peripheral.call(s.inv, "pushItems", selfName, s.slot, need, slot)
      need = need - (moved or 0)
    end
  end
  return need <= 0
end

-- Empty one turtle slot into storage.
local function stashSlot(slot)
  if turtle.getItemCount(slot) == 0 then return true end
  for _, inv in ipairs(stores) do
    peripheral.call(inv, "pullItems", selfName, slot)
    if turtle.getItemCount(slot) == 0 then return true end
  end
  return false
end

-- Empty the whole turtle into storage.
local function stashAll()
  for slot = 1, 16 do
    if not stashSlot(slot) then
      error("Storage is full: cannot put items away.", 0)
    end
  end
end

---------------------------------------------------------------- planning

local function countIn(stock, wanted)
  local n = 0
  for name, c in pairs(stock) do
    if matches(wanted, name) then n = n + c end
  end
  return n
end

local function takeFrom(stock, wanted, n)
  for name, c in pairs(stock) do
    if n <= 0 then break end
    if matches(wanted, name) then
      local t = math.min(c, n)
      stock[name] = c - t
      n = n - t
    end
  end
end

-- What a recipe consumes per craft: { name = count }
local function ingredients(recipe)
  local needs = {}
  if recipe.smelt then
    needs[recipe.smelt] = 1
  else
    for _, k in ipairs(recipe.grid) do
      if k ~= "" then
        local name = recipe.key[k]
        needs[name] = (needs[name] or 0) + 1
      end
    end
  end
  return needs
end

-- Work out how to end up with n of `wanted`, using a pretend copy of the
-- stock. Adds the jobs to `steps` in the order they must run, and anything
-- that cannot be made to `missing`.
local function plan(stock, wanted, n, steps, missing)
  local have = math.min(countIn(stock, wanted), n)
  takeFrom(stock, wanted, have)
  local short = n - have
  if short <= 0 then return end

  local recipe = RECIPES[wanted]
  -- an unpacking recipe only helps if there are packed blocks; otherwise
  -- report the item itself as missing (clearer than "cobblestone 1x")
  if recipe and recipe.unpack then
    local block = recipe.key.B
    if countIn(stock, block) < math.ceil(short / 9) then recipe = nil end
  end
  if not recipe then
    missing[wanted] = (missing[wanted] or 0) + short
    return
  end

  local yield = recipe.yield or 1
  local batches = math.ceil(short / yield)
  for name, per in pairs(ingredients(recipe)) do
    plan(stock, name, per * batches, steps, missing)
  end
  if recipe.smelt then
    plan(stock, "#fuel", math.ceil(batches / 8), steps, missing)
  end
  steps[#steps + 1] = { name = wanted, batches = batches }

  -- anything made beyond what was needed goes back on the pretend shelf
  local spare = batches * yield - short
  if spare > 0 then
    local key = wanted
    if wanted:sub(1, 1) == "#" then key = "spare" .. GROUPS[wanted][1] end
    stock[key] = (stock[key] or 0) + spare
  end
end

---------------------------------------------------------------- doing

local function craftOnce(name)
  local recipe = RECIPES[name]
  stashAll()
  for i, k in ipairs(recipe.grid) do
    if k ~= "" then
      if not pull(recipe.key[k], 1, GRID_SLOT[i]) then
        error("Ran out of " .. shortName(recipe.key[k]) .. " while making "
          .. shortName(name) .. ".", 0)
      end
    end
  end
  turtle.select(16)
  local ok, err = turtle.craft()
  if not ok then
    error("The recipe for " .. shortName(name) .. " did not work: "
      .. tostring(err), 0)
  end
  stashAll()
end

local function furnaceList(f)
  return peripheral.call(f, "list") or {}
end

-- Empty a furnace's input and output slots back into storage.
local function drainFurnace(f)
  for _, slot in ipairs({ 1, 3 }) do
    for _, inv in ipairs(stores) do
      if not furnaceList(f)[slot] then break end
      peripheral.call(f, "pushItems", inv, slot)
    end
  end
end

-- Take finished items out of a furnace, leaving what is still cooking.
local function emptyOutput(f)
  for _, inv in ipairs(stores) do
    if not furnaceList(f)[3] then break end
    peripheral.call(f, "pushItems", inv, 3)
  end
end

-- Load one furnace with fuel and up to `count` of the input. Returns how
-- many went in.
local function loadFurnace(f, input, count)
  drainFurnace(f)
  local fuelNeeded = math.ceil(count / 8)
  local fuelSlot = furnaceList(f)[2]
  local fuelHave = fuelSlot and fuelSlot.count or 0
  if fuelHave < fuelNeeded then
    local want = fuelNeeded - fuelHave
    for _, st in ipairs(listStorage()) do
      if want <= 0 then break end
      if matches("#fuel", st.name) and (not fuelSlot or fuelSlot.name == st.name) then
        want = want - (peripheral.call(st.inv, "pushItems", f, st.slot, want, 2) or 0)
      end
    end
    if want > 0 then error("Not enough coal for the furnaces.", 0) end
  end
  local loaded = 0
  for _, st in ipairs(listStorage()) do
    if loaded >= count then break end
    if st.name == input then
      loaded = loaded + (peripheral.call(st.inv, "pushItems", f, st.slot, count - loaded, 1) or 0)
    end
  end
  return loaded
end

-- Between jobs the furnaces keep cooking what the building will need, so a
-- load for the builder rarely has to wait for smelting.
local BACKGROUND = {
  -- logs to charcoal first: it is fuel (8 charcoal for 1 burned), so this
  -- runs even when coal is short
  { fuel = true, input = "regions_unexplored:magnolia_log", output = "minecraft:charcoal", keep = 4000 },
  { fuel = true, input = "regions_unexplored:mauve_log", output = "minecraft:charcoal", keep = 4000 },
  { fuel = true, leave = 64, input = "minecraft:oak_log", output = "minecraft:charcoal", keep = 4000 },
  { fuel = true, input = "minecraft:birch_log", output = "minecraft:charcoal", keep = 4000 },
  { fuel = true, input = "minecraft:spruce_log", output = "minecraft:charcoal", keep = 4000 },
  { input = "minecraft:cobblestone", output = "minecraft:stone", keep = 1600 },
  { input = "minecraft:raw_copper", output = "minecraft:copper_ingot", keep = 400 },
  { input = "minecraft:stone_bricks", output = "minecraft:cracked_stone_bricks", keep = 180 },
  -- for the fit-out: glass for the windows, iron for bars and lanterns,
  -- gold for the monitors
  { leave = 64, input = "minecraft:sand", output = "minecraft:glass", keep = 400 },
  { leave = 64, input = "minecraft:raw_iron", output = "minecraft:iron_ingot", keep = 200 },
  { leave = 64, input = "minecraft:raw_gold", output = "minecraft:gold_ingot", keep = 160 },
}

local function keepFurnacesBusy(stock)
  if next(orders) then return end          -- a builder load is being made
  -- cooking ahead is a luxury: not when coal is short
  local shortOfCoal = (stock["minecraft:coal"] or 0) + (stock["minecraft:charcoal"] or 0) < FUEL_RESERVE + 144
  for _, f in ipairs(furnaces) do
    local okList, items = pcall(furnaceList, f)
    if okList and not items[1] then
      for _, job in ipairs(BACKGROUND) do
        local have = stock[job.output] or 0
        local raw = stock[job.input] or 0
        local minRaw = job.input == "minecraft:stone_bricks" and 128 or 16
        -- leave = raw kept back for building turtles
        if (job.fuel or not shortOfCoal) and have < job.keep
          and raw >= minRaw + (job.leave and (job.leave + 48) or 0) then
          local okLoad, got = pcall(loadFurnace, f, job.input, 64)
          if okLoad and got and got > 0 then
            stock[job.input] = raw - got
            stock[job.output] = have + got
            break
          end
        end
      end
    end
  end
end

-- Smelt n items, split across every furnace on the network.
-- Something to do while waiting on the furnaces (set further down: look
-- after the miners).
local whileWaiting
local lastServe

local function smelt(name, n)
  local usable = {}
  for _, f in ipairs(furnaces) do
    if peripheral.call(f, "size") == 3 then usable[#usable + 1] = f end
  end
  if #usable == 0 then error("No furnace on the network.", 0) end
  local input = RECIPES[name].smelt
  local remaining = n
  while remaining > 0 do
    local per = math.min(64, math.ceil(remaining / #usable))
    local active = {}
    for _, f in ipairs(usable) do
      if remaining <= 0 then break end
      local got = loadFurnace(f, input, math.min(per, remaining))
      if got > 0 then
        active[#active + 1] = { f = f, n = got }
        remaining = remaining - got
      end
    end
    if #active == 0 then
      error("Ran out of " .. shortName(input) .. " for the furnace.", 0)
    end
    report("smelting")
    local deadline = os.clock() + per * 12 + 60
    while true do
      local done = true
      for _, a in ipairs(active) do
        local out = furnaceList(a.f)[3]
        if not out or out.count < a.n then done = false break end
      end
      if done then break end
      if os.clock() > deadline then
        error("The furnaces did not finish smelting " .. shortName(input) .. ".", 0)
      end
      if whileWaiting then pcall(whileWaiting) end
      sleep(2)
    end
    for _, a in ipairs(active) do drainFurnace(a.f) end
  end
end

local function setStage(stage)
  if stage then
    local h = fs.open(STAGE_FILE, "w")
    h.write(stage)
    h.close()
  else
    fs.delete(STAGE_FILE)
  end
end

local function getStage()
  if not fs.exists(STAGE_FILE) then return nil end
  local h = fs.open(STAGE_FILE, "r")
  local stage = h.readAll()
  h.close()
  return stage
end

-- The first slot holding anything, or nil.
local function heldSlot()
  for slot = 1, 16 do
    if turtle.getItemCount(slot) > 0 then return slot end
  end
  return nil
end

-- The builder: a plain turtle with just an ender modem (it needs no tool to
-- map things). Left in this turtle's inventory, staged as "builder".
local function assembleBuilder()
  stashAll()
  if not (pull(TURTLE, 1, 1) and pull(MODEM, 1, 2)) then
    error("Parts for the builder went missing.", 0)
  end
  turtle.select(16)
  local ok, err = turtle.craft()
  if not ok then error("Could not fit the modem on the builder: " .. tostring(err), 0) end
  setStage("builder")
end

-- Put the pickaxe and the modem onto a plain turtle. The finished miner is
-- left in this turtle's inventory. Progress is saved (STAGE_FILE) so that a
-- half-assembled miner is never put back into storage, where it would be
-- mistaken for a plain turtle.
local function assemble()
  local stage = getStage()
  if not heldSlot() then stage = nil end

  if not stage then
    stashAll()
    -- [pickaxe][turtle] : the tool goes on the turtle's left side
    if not (pull(PICKAXE, 1, 1) and pull(TURTLE, 1, 2)) then
      error("Parts went missing before assembly.", 0)
    end
    turtle.select(16)
    local ok, err = turtle.craft()
    if not ok then error("Could not fit the pickaxe: " .. tostring(err), 0) end
    stage = "pickaxe"
    setStage(stage)
  end

  if stage == "pickaxe" then
    -- move the mining turtle to slot 1 : [turtle][modem]
    local at = heldSlot()
    if not at then error("The mining turtle vanished after crafting.", 0) end
    if at ~= 1 then
      turtle.select(at)
      turtle.transferTo(1)
    end
    if not pull(MODEM, 1, 2) then error("The ender modem went missing.", 0) end
    turtle.select(16)
    local ok, err = turtle.craft()
    if not ok then error("Could not fit the ender modem: " .. tostring(err), 0) end
    setStage("ready")
  end
end

-- True if the chest in front is also one of the network storage chests
-- (same contents, slot for slot). Finished miners must not go back into
-- storage, where they would be mistaken for plain turtles.
local function outputIsStorage()
  local ok, front = pcall(peripheral.call, "front", "list")
  if not ok or not front or next(front) == nil then return false end
  for _, inv in ipairs(stores) do
    local ok2, list = pcall(peripheral.call, inv, "list")
    if ok2 and list then
      local same = true
      for slot, item in pairs(front) do
        local other = list[slot]
        if not other or other.name ~= item.name or other.count ~= item.count then
          same = false
          break
        end
      end
      for slot in pairs(list) do
        if not front[slot] then same = false break end
      end
      if same then return true end
    end
  end
  return false
end

---------------------------------------------------------------- the base

-- Which way the turtle faces, counted in right turns from the drop-off
-- chest (0 = facing the chest). nil = not known yet.
local facing

local function turnTo(n)
  while facing ~= n do
    turtle.turnRight()
    facing = (facing + 1) % 4
  end
end

local function frontIsChest()
  return peripheral.hasType("front", "inventory")
    and not peripheral.hasType("front", "turtle")
end

-- Turn until the drop-off chest is in front.
local function findDropChest()
  for _ = 1, 4 do
    if frontIsChest() then
      facing = 0
      return true
    end
    turtle.turnRight()
  end
  facing = nil
  return false
end

local function gpsFix()
  local x, y, z = gps.locate(3)
  if not x then return nil end
  return { x = math.floor(x + 0.5), y = math.floor(y + 0.5), z = math.floor(z + 0.5) }
end

local function ensureFuel(n)
  local f = turtle.getFuelLevel()
  if f == "unlimited" or f >= n then return true end
  stashAll()
  if pull("#fuel", 1, 1) then
    turtle.select(1)
    turtle.refuel(1)
  end
  stashAll()
  f = turtle.getFuelLevel()
  return f == "unlimited" or f >= n
end

-- Work out where everything is: my position, the launch pad (the space
-- above the disk drive) and the drop-off chest. Done once, then saved.
local function survey()
  local f = gpsFix()
  if not f then return nil, "no GPS signal" end
  if base and base.f.x == f.x and base.f.y == f.y and base.f.z == f.z then
    return base
  end
  if not ensureFuel(8) then
    return nil, "put some coal in the storage chest so I can look around"
  end
  -- step out on each free side and look down for the disk drive
  local found
  for t = 1, 3 do
    turnTo(t)
    if not found and not turtle.detect() and turtle.forward() then
      local ok, data = turtle.inspectDown()
      local p = gpsFix()
      local back = false
      for _ = 1, 20 do
        if turtle.back() then back = true break end
        sleep(0.5)
      end
      if not back then error("I stepped off my modem and cannot get back.", 0) end
      if ok and data.name:find("disk_drive", 1, true) and p then
        found = { t = t, p = p }
      end
    end
  end
  turnTo(0)
  if not found then
    return nil, "no disk drive found: put one on the floor touching the "
      .. "modem, and keep the space above it empty"
  end
  local p = found.p
  local dx, dz = p.x - f.x, p.z - f.z
  local hp = dx == 1 and 0 or dz == 1 and 1 or dx == -1 and 2 or 3
  local hd = (hp - found.t) % 4
  base = {
    f = f,
    pad = p,
    padTurns = found.t,
    dock = { x = f.x + DIRS[hd].x, y = f.y + 1, z = f.z + DIRS[hd].z },
    exit1 = { x = f.x, y = f.y + 1, z = f.z },
    exit2 = { x = p.x, y = p.y + 1, z = p.z },
  }
  saveTable(BASE_FILE, base)
  print(("Base mapped. I am at %d, %d, %d."):format(f.x, f.y, f.z))
  return base
end

-- Make sure the floppy disk will set up new turtles.
local function prepareDisk()
  local drive = peripheral.find("drive")
  if not drive then return false, "the disk drive is not on the network" end
  if not drive.isDiskPresent() or not drive.hasData() then
    return false, "put a floppy disk in the disk drive"
  end
  local path = drive.getMountPath()
  if not path then return false, "the floppy disk is not readable" end
  local file = fs.combine(path, "startup.lua")
  local current
  if fs.exists(file) then
    local h = fs.open(file, "r")
    current = h.readAll()
    h.close()
  end
  if current ~= DISK_STARTUP then
    local h = fs.open(file, "w")
    h.write(DISK_STARTUP)
    h.close()
  end
  return true
end

-- Empty the drop-off chest into storage.
local function collect()
  turnTo(0)
  stashAll()
  for _ = 1, 60 do
    turtle.select(1)
    if not turtle.suck() then break end
    stashAll()
  end
end

-- Hand items to a turtle in front of me or on top of me, without disturbing
-- anything I hold. sure = true when we know a turtle is there (we have just
-- placed it; it can take a moment to show up as a peripheral).
local function giveTo(dir, item, amount, sure)
  local side = dir == "up" and "top" or "front"
  if not sure and not peripheral.hasType(side, "turtle") then return false end
  local slot
  for s = 16, 1, -1 do
    if turtle.getItemCount(s) == 0 then slot = s break end
  end
  if not slot then return false end
  pull(item, amount, slot)
  local before = turtle.getItemCount(slot)
  if before == 0 then return false, 0 end
  turtle.select(slot)
  if dir == "up" then turtle.dropUp() else turtle.drop() end
  local moved = before - turtle.getItemCount(slot)
  stashSlot(slot)
  turtle.select(1)
  return moved > 0, moved
end

local function giveToFront(item, amount, sure)
  return giveTo("front", item, amount, sure)
end

local function fuelTurtleInFront(amount, sure)
  return giveToFront("#fuel", amount, sure)
end

-- Several crafts in one go: put k of each ingredient in its grid slot and
-- craft them all at once (up to a stack of output). Only for recipes whose
-- ingredients are exact items (a group like any planks could mix types).
local function canBulk(recipe)
  for _, item in pairs(recipe.key) do
    if item:sub(1, 1) == "#" then return false end
  end
  return true
end

local function craftBatch(name, k)
  local recipe = RECIPES[name]
  stashAll()
  for i, key in ipairs(recipe.grid) do
    if key ~= "" then
      if not pull(recipe.key[key], k, GRID_SLOT[i]) then
        stashAll()
        error("Ran out of " .. shortName(recipe.key[key]) .. " while making "
          .. shortName(name) .. ".", 0)
      end
    end
  end
  turtle.select(16)
  local ok, err = turtle.craft()
  if not ok then
    stashAll()
    error("The recipe for " .. shortName(name) .. " did not work: " .. tostring(err), 0)
  end
  stashAll()
end

---------------------------------------------------------------- tidying storage
-- When the chests fill up: first merge part-stacks of the same item, then
-- pack big piles into storage blocks (9 to 1). Nothing is ever thrown away,
-- and the planner unpacks blocks again when it needs the items.

local PACK = {
  { item = "minecraft:redstone", block = "minecraft:redstone_block", keep = 192 },
  { item = "minecraft:raw_copper", block = "minecraft:raw_copper_block", keep = 448 },
  { item = "minecraft:lapis_lazuli", block = "minecraft:lapis_block", keep = 64 },
  { item = "minecraft:raw_iron", block = "minecraft:raw_iron_block", keep = 192 },
  { item = "minecraft:raw_gold", block = "minecraft:raw_gold_block", keep = 128 },
  { item = "minecraft:cobbled_deepslate", block = "allthecompressed:cobbled_deepslate_1x", keep = 4000 },
  { item = "minecraft:cobblestone", block = "allthecompressed:cobblestone_1x", keep = 3000 },
  { item = "minecraft:dirt", block = "allthecompressed:dirt_1x", keep = 640 },
}
local packFails = {}      -- recipes that do not exist in this pack

-- Merge part-stacks of the same item. Returns how many slots were freed.
local function mergeStacks()
  local byName, freed = {}, 0
  for _, st in ipairs(listStorage()) do
    if st.count < 64 then
      byName[st.name] = byName[st.name] or {}
      table.insert(byName[st.name], st)
    end
  end
  for _, list in pairs(byName) do
    if #list > 1 then
      table.sort(list, function(a, b) return a.count > b.count end)
      local i, j = 1, #list
      while i < j do
        local to, from = list[i], list[j]
        local ok, moved = pcall(peripheral.call, from.inv, "pushItems", to.inv, from.slot,
          from.count, to.slot)
        moved = ok and tonumber(moved) or 0
        from.count = from.count - moved
        to.count = to.count + moved
        if from.count <= 0 then
          j = j - 1
          freed = freed + 1
        end
        if moved == 0 or to.count >= 64 then i = i + 1 end
      end
    end
  end
  return freed
end

-- Pack one pile into blocks, up to a stack of blocks per craft.
local function packOne(job, stock)
  local have = stock[job.item] or 0
  local packed = 0
  while have - job.keep >= 9 * 8 and not packFails[job.block] do
    local k = math.min(64, math.floor((have - job.keep) / 9))
    stashAll()
    for _, slot in ipairs(GRID_SLOT) do
      if not pull(job.item, k, slot) then
        stashAll()
        return packed
      end
    end
    turtle.select(16)
    local ok = turtle.craft()
    local made = turtle.getItemCount(16) > 0
    stashAll()
    if not ok or not made then
      packFails[job.block] = true      -- no such recipe in this modpack
      return packed
    end
    have = have - 9 * k
    packed = packed + k
  end
  return packed
end

local function tidyStorage(force)
  local sp = storageSpace()
  if not force and sp.free >= 24 then return end
  local freed = mergeStacks()
  if freed > 0 then print("Merged part-stacks: " .. freed .. " slots freed.") end
  if not pcall(stashAll) then return end
  local stock = stockTotals()
  for _, job in ipairs(PACK) do
    local ok, n = pcall(packOne, job, stock)
    if not ok then print("Could not pack " .. shortName(job.item) .. ": " .. tostring(n)) end
    if ok and n > 0 then print(("Packed %d %s."):format(n, shortName(job.block))) end
  end
  spaceAt = nil                          -- measure again next time
end

-- Run a list of planned smelting and crafting jobs.
local function runSteps(steps)
  for _, step in ipairs(steps) do
    local recipe = RECIPES[step.name]
    if recipe.smelt then
      print("Smelting " .. step.batches .. " " .. shortName(recipe.smelt))
      smelt(step.name, step.batches)
    else
      print("Crafting " .. shortName(step.name))
      local left = step.batches
      local bulk = canBulk(recipe)
      while left > 0 do
        local k = bulk and math.max(1, math.min(left, math.floor(64 / (recipe.yield or 1)))) or 1
        if bulk then craftBatch(step.name, k) else craftOnce(step.name) end
        left = left - k
      end
    end
  end
end

-- Make as many as possible of something, up to n. Returns how many are in
-- stock afterwards (capped at n).
local function makeUpTo(name, n)
  local have = countIn(stockTotals(), name)
  if have >= n then return n end
  local want = n
  while want > have do
    local stock = stockTotals()
    local steps, missing = {}, {}
    plan(stock, name, want, steps, missing)
    if not next(missing) then
      runSteps(steps)
      break
    end
    want = have + math.floor((want - have) / 2)   -- try for less
  end
  return math.min(n, countIn(stockTotals(), name))
end

-- Make sure storage holds at least n of something, making it if possible.
-- Must not be called while holding a finished miner.
local function ensureStock(name, n)
  local stock = stockTotals()
  if countIn(stock, name) >= n then return true end
  local steps, missing = {}, {}
  plan(stock, name, n, steps, missing)
  if next(missing) then return false end
  runSteps(steps)
  return true
end

-- Serve miners waiting for things: on top of me (the usual service stop) or
-- on the launch pad (where they wait if they cannot carry on). Coal for the
-- empty, buckets for those without one. With no coal at all, the Geo Scanner
-- goes to the first miner that asks, so it can hunt for coal.
-- canCraft = false while I am holding a finished miner.
local function serveRequests(canCraft)
  if not next(fuelQueue) and not next(bucketQueue) then return end
  if canCraft and next(bucketQueue) then
    pcall(ensureStock, BUCKET, 1)
  end
  for _, dir in ipairs({ "up", "front" }) do
    local side = "top"
    if dir == "front" then
      turnTo(base.padTurns)
      side = "front"
    end
    if peripheral.hasType(side, "turtle") then
      if next(fuelQueue) then
        -- a share of what there is, keeping a reserve for the builder, new
        -- turtles and the furnaces: 5% of the coal above the reserve, at
        -- least 8 (nobody is left stranded) and at most a stack
        local coal = countIn(stockTotals(), "#fuel")
        local share = math.max(8, math.min(64, math.floor((coal - FUEL_RESERVE) * 0.05)))
        if giveTo(dir, "#fuel", share) then
          print("Gave " .. share .. " coal to a miner.")
        else
          print("A miner needs fuel but I have no coal.")
          report("out of coal")
          if not plots.hunter and giveTo(dir, SCANNER, 1) then
            plots.hunter = true
            saveTable(PLOTS_FILE, plots)
            print("Gave it the Geo Scanner to hunt for coal.")
          end
        end
      end
      if next(bucketQueue) and giveTo(dir, BUCKET, 1) then
        print("Gave a bucket to a miner.")
      end
    end
  end
  fuelQueue, bucketQueue = {}, {}
  turnTo(0)
end

whileWaiting = function()
  if not lastServe or os.clock() - lastServe > 10 then
    lastServe = os.clock()
    collect()
    serveRequests(false)
  end
end

-- Plan a whole load at once against one copy of the stock, so that making
-- one line never eats what was set aside for another. Returns the steps,
-- or nil and what is missing.
local function planLoad(lines, stock)
  local pretend = {}
  for name, c in pairs(stock) do pretend[name] = c end
  local steps, missing = {}, {}
  for _, l in ipairs(lines) do
    if l[2] > 0 then plan(pretend, l[1], l[2], steps, missing) end
  end
  if next(missing) then return nil, missing end
  -- no more smelting than one load per furnace (about 11 minutes): the
  -- builder would rather have a smaller load sooner
  local smelting = 0
  for _, st in ipairs(steps) do
    if RECIPES[st.name] and RECIPES[st.name].smelt then smelting = smelting + st.batches end
  end
  if smelting > 64 * math.max(1, #furnaces) then return nil, { smelting = smelting } end
  return steps
end

-- The biggest load we can make, line by line: each line gets as many as
-- still fit after the lines before it.
local function fitLoad(items)
  local stock = stockTotals()
  local lines = {}
  for _, line in ipairs(items) do
    local name, want = line[1], math.floor(tonumber(line[2]) or 0)
    if want > 0 and RECIPES[name] or countIn(stock, name) > 0 then
      local lo, hi = 0, want
      while lo < hi do                       -- largest count that still plans
        local mid = math.floor((lo + hi + 1) / 2)
        lines[#lines + 1] = { name, mid }
        local ok = planLoad(lines, stock)
        lines[#lines] = nil
        if ok then lo = mid else hi = mid - 1 end
      end
      if lo > 0 then lines[#lines + 1] = { name, lo } end
    end
  end
  return lines, planLoad(lines, stock) or {}
end

-- Builder loads: make the load first while the builder waits out of the
-- way, tell it the load is ready, and hand it over once that builder (and
-- not a miner) is on the launch pad.
local function frontId()
  local ok, id = pcall(peripheral.call, "front", "getID")
  return ok and id or nil
end

local function serveOrders()
  -- a builder already on the pad with its load made goes first
  local waiting = false
  for _, o in pairs(orders) do if o.ready then waiting = true end end
  if waiting then
    turnTo(base.padTurns)
    local here = peripheral.hasType("front", "turtle") and frontId()
    if not (here and orders[here] and orders[here].ready) then waiting = false end
    turnTo(0)
  end
  for id, order in pairs(orders) do
    if not waiting and not order.ready then
      served[id] = order.n
      print("Preparing a load for the builder.")
      report("preparing materials")
      stashAll()
      local lines, steps = fitLoad(order.items)
      local okRun, err = pcall(runSteps, steps)
      if not okRun then print("Problem: " .. tostring(err)) end
      order.lines, order.ready, order.told = lines, true, os.clock()
      rednet.send(id, { type = "load_ready", forId = id, n = order.n }, JOB_PROTOCOL)
      print("Load ready. Waiting for the builder.")
      return true
    end
  end
  do
    -- every load is ready: hand over to whichever of them is on the pad
    turnTo(base.padTurns)
    local here = peripheral.hasType("front", "turtle") and frontId()
    local order = here and orders[here]
    if order and not order.ready then order = nil end
    if not order then
      turnTo(0)
      for id, o in pairs(orders) do
        if os.clock() - o.told > 60 then         -- remind it
          o.told = os.clock()
          rednet.send(id, { type = "load_ready", forId = id, n = o.n }, JOB_PROTOCOL)
        end
      end
      return false
    end
    local id = here
    orders[id] = nil
    local given, missing = {}, {}
    for _, l in ipairs(order.lines) do
      local name, want = l[1], l[2]
      local got = 0
      while got < want do
        local ok, moved = giveTo("front", name, math.min(64, want - got))
        if not ok then break end
        got = got + moved
      end
      given[name] = got
    end
    for _, line in ipairs(order.items) do
      local name, want = line[1], math.floor(tonumber(line[2]) or 0)
      if (given[name] or 0) < want then missing[name] = want - (given[name] or 0) end
    end
    if order.fuel > 0 then
      -- when fuel is short nobody gets more than a share of what there is
      local have = countIn(stockTotals(), "#fuel")
      giveTo("front", "#fuel", math.min(64, order.fuel, math.max(8, math.floor(have * 0.4))))
    end
    turnTo(0)
    rednet.send(id, { type = "materials_ready", forId = id, n = order.n,
      given = given, missing = missing }, JOB_PROTOCOL)
    print("Load handed over.")
    report("load handed over")
    return true
  end
  return false
end

-- Put the finished miner on the launch pad, fuel it and switch it on.
local function deploy()
  local slot = heldSlot()
  if not slot then error("Nothing to launch.", 0) end
  local isBuilder = getStage() == "builder"
  turnTo(base.padTurns)
  local waited = 0
  while true do
    local coal = countIn(stockTotals(), "#fuel")
    local busy = turtle.detect()
    -- a miner sitting on the pad waiting for fuel or a bucket: serve it
    -- so it can leave
    if busy and next(fuelQueue) and fuelTurtleInFront(16) then
      fuelQueue = {}
      print("Gave fuel to a miner.")
    end
    if busy and next(bucketQueue) and giveToFront(BUCKET, 1) then
      bucketQueue = {}
      print("Gave a bucket to a miner.")
    end
    if not busy and coal >= NEWBORN_COAL then break end
    if waited % 6 == 0 then
      if busy then
        print("Launch pad is busy, waiting...")
        report(coal > 0 and "launch pad busy" or "out of coal")
      else
        print("Waiting for " .. NEWBORN_COAL .. " coal to fuel the new miner...")
        report("out of coal")
      end
    end
    waited = waited + 1
    sleep(5)
  end
  turtle.select(slot)
  if not turtle.place() then error("Could not place the new miner.", 0) end
  setStage(nil)
  pending = pending + 1
  sleep(0.5)
  fuelTurtleInFront(NEWBORN_COAL, true)
  if isBuilder then
    giveToFront(SCANNER, 1, true)   -- for mapping
    giveToFront(CORE, 1, true)      -- for later: lets it right-click things
    for _ = 1, 10 do
      local okId, id = pcall(peripheral.call, "front", "getID")
      if okId and id then
        plots.builderId = id
        saveTable(PLOTS_FILE, plots)
        break
      end
      sleep(0.5)
    end
  else
    giveToFront(BUCKET, 1, true)    -- for scooping lava as fuel
    if launchingHelper then
      -- a builder's mate: note which turtle it is, so it gets that job
      for _ = 1, 10 do
        local okId, id = pcall(peripheral.call, "front", "getID")
        if okId and id then
          plots.helpers = plots.helpers or {}
          plots.helpers[#plots.helpers + 1] = id
          saveTable(PLOTS_FILE, plots)
          print("That one is a builder's mate.")
          break
        end
        sleep(0.5)
      end
    end
  end
  stashAll()
  for _ = 1, 10 do
    if pcall(peripheral.call, "front", "turnOn") then break end
    sleep(0.5)
  end
  turnTo(0)
end

---------------------------------------------------------------- plots

-- Plots are a grid of squares around the factory, handed out from the
-- inside outwards, skipping any that come within KEEP_OUT of the factory.
local function plotOrigin(index)
  local n = 0
  for r = 0, 80 do
    for gx = -r, r do
      for gz = -r, r do
        if math.max(math.abs(gx), math.abs(gz)) == r then
          local x0 = base.f.x + gx * PLOT_SIZE
          local z0 = base.f.z + gz * PLOT_SIZE
          local clear = base.f.x < x0 - KEEP_OUT
            or base.f.x > x0 + PLOT_SIZE - 1 + KEEP_OUT
            or base.f.z < z0 - KEEP_OUT
            or base.f.z > z0 + PLOT_SIZE - 1 + KEEP_OUT
          if clear then
            n = n + 1
            if n == index then return x0, z0 end
          end
        end
      end
    end
  end
end

-- The job for a miner: its current plot, or a new one if it has none.
local function jobFor(id)
  local key = tostring(id)
  if plots.builderId and tostring(plots.builderId) == key then
    if pending > 0 then pending = pending - 1 end
    return { type = "role", role = "builder", forId = id, base = base }
  end
  for n, hid in ipairs(plots.helpers or {}) do
    if tostring(hid) == key then
      if pending > 0 then pending = pending - 1 end
      return { type = "role", role = "helper", forId = id, base = base, name = HELPER_NAMES[n] }
    end
  end
  local index = plots.byId[key]
  if not index then
    local returning = plots.between and plots.between[key]
    if returning then
      plots.between[key] = nil
    elseif activeCount() >= MAX_MINERS and pending == 0 then
      return nil
    elseif pending > 0 then
      pending = pending - 1                   -- one we launched: it gets a plot
    end
    if plots.free and #plots.free > 0 then
      index = table.remove(plots.free, 1)     -- a plot someone gave back
    else
      index = plots.next
      plots.next = index + 1
    end
    plots.byId[key] = index
    saveTable(PLOTS_FILE, plots)
  end
  local x0, z0 = plotOrigin(index)
  return {
    type = "job", forId = id, index = index,
    x0 = x0, z0 = z0, size = PLOT_SIZE,
    topY = math.min(TOP_Y_MAX, base.f.y - 10), bottom = BOTTOM_Y,
    cruise = base.f.y + CRUISE_UP + ((index - 1) % 40),
    dock = base.dock, exit1 = base.exit1, exit2 = base.exit2,
  }
end

-- Answers miners. Runs alongside the building work; uses no turtle moves.
local function responder()
  if swarm then swarm.open() end
  while true do
    local id, msg = rednet.receive(JOB_PROTOCOL)
    if type(msg) == "table" and id then
      if msg.type == "need_job" then
        if base then
          local job = jobFor(id)
          if job then rednet.send(id, job, JOB_PROTOCOL) end
        end
      elseif msg.type == "job_done" then
        if plots.byId[tostring(id)] == msg.index then
          plots.byId[tostring(id)] = nil
          plots.between = plots.between or {}
          plots.between[tostring(id)] = true
          plots.done = (plots.done or 0) + 1
          saveTable(PLOTS_FILE, plots)
        end
      elseif msg.type == "fuel_request" then
        fuelQueue[id] = true
      elseif msg.type == "bucket_request" then
        bucketQueue[id] = true
      elseif msg.type == "materials" and type(msg.items) == "table"
        and (msg.n == nil or served[id] ~= msg.n) then
        orders[id] = { items = msg.items, fuel = tonumber(msg.fuel) or 0, n = msg.n }
      elseif msg.type == "release" then
        -- a miner turned coal hunter: its plot goes to the next new miner
        if plots.byId[tostring(id)] == msg.index then
          plots.byId[tostring(id)] = nil
          plots.free = plots.free or {}
          table.insert(plots.free, msg.index)
          plots.hunter = true
          saveTable(PLOTS_FILE, plots)
        end
      end
    end
  end
end

---------------------------------------------------------------- main loop

local function describeMissing(missing)
  local parts = {}
  for name, n in pairs(missing) do
    parts[#parts + 1] = n .. " " .. (name == "#fuel" and "coal" or shortName(name))
  end
  table.sort(parts)
  return table.concat(parts, ", ")
end

local function notReady(why)
  print("Not ready: " .. why)
  lastMissing = {}
  report("not ready")
  return false
end

-- One pass of base duties. Returns true if a miner was launched.
local function tryBuild()
  local ok, why = discover()
  if not ok then return notReady(why) end
  pcall(tidyStorage)
  if not turtle.craft then
    return notReady("I need a crafting table upgrade (Crafty Turtle)")
  end
  if not findDropChest() then
    return notReady("put a chest beside me, sitting on the furnace")
  end
  if outputIsStorage() then
    return notReady("the chest beside me is my storage chest; the drop-off "
      .. "chest must be a separate one that does not touch the modem")
  end

  -- a miner finished earlier but never launched (e.g. interrupted)
  local held = getStage() and heldSlot()
  if not held then
    setStage(nil)
    stashAll()
  end
  for _, f in ipairs(furnaces) do emptyOutput(f) end
  if not held then pcall(keepFurnacesBusy, stockTotals()) end

  local b
  b, why = survey()
  if not b then return notReady(why) end
  ok, why = prepareDisk()
  if not ok then return notReady(why) end

  if not held then collect() end
  serveRequests(not held)
  if not held and serveOrders() then
    lastStock = stockTotals()
    return true
  end
  lastStock = stockTotals()

  if held then
    print("Finishing a miner from earlier...")
    assemble()
    deploy()
    built = built + 1
    report("launched one")
    return true
  end

  -- one builder, before any more miners (it needs no diamonds)
  if not plots.builderId then
    local pretend = {}
    for name, c in pairs(lastStock) do pretend[name] = c end
    local steps, missing = {}, {}
    plan(pretend, TURTLE, 1, steps, missing)
    plan(pretend, MODEM, 1, steps, missing)
    plan(pretend, "#fuel", NEWBORN_COAL, steps, missing)
    if not next(missing) then
      print("Building the builder...")
      report("building")
      runSteps(steps)
      assembleBuilder()
      print("Launching the builder")
      deploy()
      built = built + 1
      report("launched builder")
      return true
    end
  end

  local forHelper = #(plots.helpers or {}) < HELPERS
  if not forHelper and activeCount() + pending >= MAX_MINERS then
    lastMissing = {}
    report("fleet full")
    return false
  end

  -- plan a whole miner against a pretend copy of the stock
  local pretend = {}
  for name, c in pairs(lastStock) do pretend[name] = c end
  local steps, missing = {}, {}
  for name, n in pairs(MINER_PARTS) do
    plan(pretend, name, n, steps, missing)
  end
  plan(pretend, "#fuel", NEWBORN_COAL, steps, missing)   -- fuel to send it off with
  plan(pretend, BUCKET, 1, steps, missing)               -- and a bucket for lava
  lastMissing = missing
  if next(missing) then
    print("Waiting for: " .. describeMissing(missing))
    report("waiting for parts")
    return false
  end

  print("Building a miner...")
  report("building")
  runSteps(steps)
  print("Assembling")
  assemble()
  print("Launching")
  launchingHelper = forHelper
  deploy()
  launchingHelper = false
  built = built + 1
  lastStock = stockTotals()
  print("Miner #" .. built .. " launched.")
  report("launched one")
  return true
end

local function buildLoop()
  while true do
    local ok, result = pcall(tryBuild)
    if not ok then
      if result == "Terminated" then error(result, 0) end
      print("PROBLEM: " .. tostring(result))
      report("problem")
      result = false
    end
    if not result then sleep(CHECK_EVERY) end
  end
end

local function work()
  parallel.waitForAny(buildLoop, responder)
end

local function paused()
  print("Paused by remote order.")
  while true do
    report("paused")
    sleep(60)
  end
end

if not turtle then
  print("This program only runs on a turtle.")
  return
end

-- remember what this machine is, and give it a proper name
do
  local h = fs.open(".role", "w")
  h.write("factory")
  h.close()
  local label = os.getComputerLabel()
  if not label or label == "factory" then os.setComputerLabel("ForgeClooney") end
end

local task = fs.exists(PAUSE_FILE) and paused or work

if not swarm then
  task()
  return
end

while true do
  local cmd = swarm.runWithCommands(task, function(c)
    if c.cmd == "ping" then
      report(lastState)
      return true
    end
  end)
  if not cmd then
    return
  elseif cmd.cmd == "reboot" then
    print("Rebooting by remote order.")
    swarm.pinVersion(cmd)
    report("rebooting")
    os.reboot()
  elseif cmd.cmd == "stop" or cmd.cmd == "home" then
    local h = fs.open(PAUSE_FILE, "w")
    h.write("paused")
    h.close()
    task = paused
  elseif cmd.cmd == "resume" then
    fs.delete(PAUSE_FILE)
    task = work
  end
end
