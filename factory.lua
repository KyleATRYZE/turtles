-- factory.lua : builds mining turtles from raw materials.
--
-- Runs on a Crafty Turtle (with an ender modem) that sits against a wired
-- modem. Chests and a furnace on the same wired network are its storage and
-- smelter. Finished miners are dropped into the chest in front of it.
--
-- It smelts and crafts every intermediate part itself:
--   cobblestone -> stone, raw iron -> ingots, sand -> glass -> panes,
--   logs -> planks -> chest / sticks, pickaxe, computer, turtle.

local okSwarm, swarm = pcall(require, "swarm")
if not okSwarm then swarm = nil end

local MAX_STOCK   = 8     -- stop when this many finished miners are waiting
local CHECK_EVERY = 30    -- seconds between checks when idle
local PAUSE_FILE  = ".factory_paused"

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

-- Put the pickaxe and the modem onto a plain turtle, then drop the finished
-- miner into the chest in front.
local function assemble()
  stashAll()
  -- [pickaxe][turtle] : the tool goes on the turtle's left side
  if not (pull(PICKAXE, 1, 1) and pull(TURTLE, 1, 2)) then
    error("Parts went missing before assembly.", 0)
  end
  turtle.select(16)
  local ok, err = turtle.craft()
  if not ok then error("Could not fit the pickaxe: " .. tostring(err), 0) end

  -- find the mining turtle and move it to slot 1 : [turtle][modem]
  local at
  for slot = 1, 16 do
    if turtle.getItemCount(slot) > 0 then at = slot break end
  end
  if not at then error("The mining turtle vanished after crafting.", 0) end
  if at ~= 1 then
    turtle.select(at)
    turtle.transferTo(1)
  end
  if not pull(MODEM, 1, 2) then error("The ender modem went missing.", 0) end
  turtle.select(16)
  ok, err = turtle.craft()
  if not ok then error("Could not fit the ender modem: " .. tostring(err), 0) end

  for slot = 1, 16 do
    if turtle.getItemCount(slot) > 0 then
      turtle.select(slot)
      if not turtle.drop() then
        error("The output chest is full.", 0)
      end
    end
  end
  turtle.select(1)
end

local function outputCount()
  local ok, list = pcall(peripheral.call, "front", "list")
  if not ok or not list then return 0 end
  local n = 0
  for _, item in pairs(list) do n = n + item.count end
  return n
end

---------------------------------------------------------------- main loop

local function describeMissing(missing)
  local parts = {}
  for name, n in pairs(missing) do
    parts[#parts + 1] = n .. " " .. shortName(name)
  end
  table.sort(parts)
  return table.concat(parts, ", ")
end

-- One pass: build a miner if we can. Returns true if one was built.
local function tryBuild()
  local ok, why = discover()
  if not ok then
    print("Not ready: " .. why)
    lastMissing = {}
    report("not ready")
    return false
  end
  if not turtle.craft then
    print("I need a crafting table upgrade (Crafty Turtle).")
    report("not ready")
    return false
  end
  if not peripheral.hasType("front", "inventory") then
    print("Put a chest in front of me for finished miners.")
    report("not ready")
    return false
  end

  stashAll()
  for _, f in ipairs(furnaces) do drainFurnace(f) end
  lastStock = stockTotals()

  if outputCount() >= MAX_STOCK then
    lastMissing = {}
    report("output full")
    return false
  end

  -- plan a whole miner against a pretend copy of the stock
  local pretend = {}
  for name, c in pairs(lastStock) do pretend[name] = c end
  local steps, missing = {}, {}
  for name, n in pairs(MINER_PARTS) do
    plan(pretend, name, n, steps, missing)
  end
  lastMissing = missing
  if next(missing) then
    print("Waiting for: " .. describeMissing(missing))
    report("waiting for parts")
    return false
  end

  print("Building a miner...")
  report("building")
  for _, step in ipairs(steps) do
    local recipe = RECIPES[step.name]
    if recipe.smelt then
      print("Smelting " .. step.batches .. " " .. shortName(recipe.smelt))
      report("building")
      smelt(step.name, step.batches)
    else
      print("Crafting " .. shortName(step.name))
      for _ = 1, step.batches do craftOnce(step.name) end
    end
  end
  print("Assembling")
  assemble()
  built = built + 1
  lastStock = stockTotals()
  print("Miner #" .. built .. " is in the output chest.")
  report("built one")
  return true
end

local function work()
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
