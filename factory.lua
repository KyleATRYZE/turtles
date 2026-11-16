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

local MAX_MINERS   = 6     -- size of the fleet this base will run
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
local bucketQueue = {}   -- miners waiting on the launch pad for a bucket

local function activeCount()
  local n = 0
  for _ in pairs(plots.byId) do n = n + 1 end
  return n
end

local function report(state)
  lastState = state
  if not swarm then return end
  pcall(swarm.report, {
    role = "factory",
    state = state,
    built = built,
    inv = lastStock,
    missing = lastMissing,
    network = lastNetwork,
    base = base,
    fleet = { active = activeCount(), launching = pending, max = MAX_MINERS,
      plotsDone = plots.done, nextPlot = plots.next, byId = plots.byId },
    log = logLines,
  })
end

---------------------------------------------------------------- network

local modem      -- the wired modem behind the turtle
local selfName   -- this turtle's name on the wired network
local stores = {}    -- names of storage inventories
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

local function smelt(name, n)
  local f = furnaces[1]
  if not f then error("No furnace on the network.", 0) end
  local size = peripheral.call(f, "size")
  if size ~= 3 then
    error("The furnace shows " .. tostring(size) .. " slots, expected 3.", 0)
  end
  local input = RECIPES[name].smelt
  drainFurnace(f)

  -- fuel: one coal smelts 8 items
  local fuelNeeded = math.ceil(n / 8)
  local fuelSlot = furnaceList(f)[2]
  local fuelHave = fuelSlot and fuelSlot.count or 0
  if fuelHave < fuelNeeded then
    local want = fuelNeeded - fuelHave
    for _, s in ipairs(listStorage()) do
      if want <= 0 then break end
      if matches("#fuel", s.name) and (not fuelSlot or fuelSlot.name == s.name) then
        want = want - (peripheral.call(s.inv, "pushItems", f, s.slot, want, 2) or 0)
      end
    end
    if want > 0 then error("Not enough coal for the furnace.", 0) end
  end

  -- input
  local want = n
  for _, s in ipairs(listStorage()) do
    if want <= 0 then break end
    if s.name == input then
      want = want - (peripheral.call(s.inv, "pushItems", f, s.slot, want, 1) or 0)
    end
  end
  if want > 0 then
    error("Ran out of " .. shortName(input) .. " for the furnace.", 0)
  end

  -- wait for it to cook (10 seconds an item, plus slack)
  local deadline = os.clock() + n * 12 + 60
  while true do
    local out = furnaceList(f)[3]
    if out and out.count >= n then break end
    if os.clock() > deadline then
      error("The furnace did not finish smelting " .. shortName(input) .. ".", 0)
    end
    sleep(2)
  end
  drainFurnace(f)
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

-- Hand items to the turtle in front, without disturbing anything I hold.
-- sure = true when we know a turtle is there (we have just placed it; it
-- can take a moment to show up as a peripheral).
local function giveToFront(item, amount, sure)
  if not sure and not peripheral.hasType("front", "turtle") then return false end
  local slot
  for s = 16, 1, -1 do
    if turtle.getItemCount(s) == 0 then slot = s break end
  end
  if not slot then return false end
  pull(item, amount, slot)
  if turtle.getItemCount(slot) == 0 then return false end
  turtle.select(slot)
  turtle.drop()
  stashSlot(slot)
  turtle.select(1)
  return true
end

local function fuelTurtleInFront(amount, sure)
  return giveToFront("#fuel", amount, sure)
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
      for _ = 1, step.batches do craftOnce(step.name) end
    end
  end
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

-- Serve miners waiting on the launch pad: coal for the empty, buckets for
-- those without one. canCraft = false while I am holding a finished miner.
local function serveRequests(canCraft)
  if not next(fuelQueue) and not next(bucketQueue) then return end
  if canCraft and next(bucketQueue) then
    pcall(ensureStock, BUCKET, 1)
  end
  turnTo(base.padTurns)
  if not peripheral.hasType("front", "turtle") then
    fuelQueue, bucketQueue = {}, {}     -- whoever asked is not on the pad
  else
    if next(fuelQueue) then
      if fuelTurtleInFront(16) then
        fuelQueue = {}
        print("Gave fuel to a miner.")
      else
        print("A miner needs fuel but I have no coal.")
        report("out of coal")
      end
    end
    if next(bucketQueue) and giveToFront(BUCKET, 1) then
      bucketQueue = {}
      print("Gave a bucket to a miner.")
    end
  end
  turnTo(0)
end

-- Put the finished miner on the launch pad, fuel it and switch it on.
local function deploy()
  local slot = heldSlot()
  if not slot then error("Nothing to launch.", 0) end
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
  giveToFront(BUCKET, 1, true)      -- for scooping lava as fuel
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
  local index = plots.byId[key]
  if not index then
    if activeCount() >= MAX_MINERS then return nil end
    index = plots.next
    plots.next = index + 1
    plots.byId[key] = index
    saveTable(PLOTS_FILE, plots)
    if pending > 0 then pending = pending - 1 end
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
          plots.done = (plots.done or 0) + 1
          saveTable(PLOTS_FILE, plots)
        end
      elseif msg.type == "fuel_request" then
        fuelQueue[id] = true
      elseif msg.type == "bucket_request" then
        bucketQueue[id] = true
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
  for _, f in ipairs(furnaces) do drainFurnace(f) end

  local b
  b, why = survey()
  if not b then return notReady(why) end
  ok, why = prepareDisk()
  if not ok then return notReady(why) end

  if not held then collect() end
  serveRequests(not held)
  lastStock = stockTotals()

  if held then
    print("Finishing a miner from earlier...")
    assemble()
    deploy()
    built = built + 1
    report("launched one")
    return true
  end

  if activeCount() + pending >= MAX_MINERS then
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
  deploy()
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
