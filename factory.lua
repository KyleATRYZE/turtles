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

local K = {}   -- constants (a table: the CC compiler counts every top-level local)
K.MAX_MINERS   = 0     -- size of the fleet this base will run (0 while storage is full: no new miners)
K.CHECK_EVERY  = 10    -- seconds between checks when idle
K.NEWBORN_COAL = 24    -- coal given to each new miner
K.PLOT_SIZE    = 8     -- each plot is this many blocks square
K.KEEP_OUT     = 24    -- no plot comes closer to the factory than this
K.TOP_Y_MAX    = 50    -- plots are dug from this height down
K.BOTTOM_Y     = -58
K.CRUISE_UP    = 45    -- (no longer used: miners now travel underground)

K.PAUSE_FILE   = ".factory_paused"
K.BASE_FILE    = ".base"
K.PLOTS_FILE   = ".plots"
K.STAGE_FILE   = ".assembling"
K.JOB_PROTOCOL = "swarm_job"

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
if not turtle then
  -- A station computer (it will sit beside a screen): it sets itself up,
  -- takes a name and switches off. The helper standing on it is waiting to
  -- carry it to its post, where it works out which screen is its own.
  local base = "https://raw.githubusercontent.com/KyleATRYZE/turtles/main/"
  local h = fs.open("/.role", "w")
  h.write("screen")
  h.close()
  local r = http and http.get(base .. "update.lua?t=" .. os.epoch("utc"))
  if r then
    h = fs.open("/update.lua", "w")
    h.write(r.readAll())
    h.close()
    r.close()
    shell.run("/update.lua")
  end
  h = fs.exists("/startup.lua") and fs.open("/startup.lua", "r")
  local startup = h and h.readAll() or ""
  if h then h.close() end
  if fs.exists("/screens.lua") and startup:find("screens", 1, true) then
    os.setComputerLabel("station-" .. os.getComputerID())
  else
    -- an old copy of the updater, or no download: leave nothing behind, so
    -- the next try starts clean (and it never comes up as anything else)
    fs.delete("/startup.lua")
    fs.delete("/.role")
  end
  os.shutdown()
  return
end
os.setComputerLabel("miner-" .. os.getComputerID())
shell.run("wget", "run", "https://raw.githubusercontent.com/KyleATRYZE/turtles/main/install.lua")
]]

K.BUCKET   = "minecraft:bucket"
K.LAVA     = "minecraft:lava_bucket"   -- fuel for turtles (1,000 moves each) and, for big batches, the furnaces
K.LAVA_KEEP = 8                        -- lava buckets kept back for the turtles
K.SCANNER  = "advancedperipherals:geo_scanner"
K.CORE     = "advancedperipherals:weak_automata_core"
K.TURTLE   = "computercraft:turtle_normal"
K.COMPUTER = "computercraft:computer_normal"
K.MODEM    = "computercraft:wireless_modem_advanced"
K.PLAIN_MODEM = "computercraft:wireless_modem_normal"   -- (short range: for a chunk loader when ender modems run out)
K.PICKAXE  = "minecraft:diamond_pickaxe"
K.CHUNKY   = "advancedperipherals:chunk_controller"   -- on a turtle: keeps its chunk loaded

-- Names starting with "#" are groups, matched by the end of the item name.
local GROUPS = {
  -- (black quartz was tried in the comparator and refused: only the real thing)
  ["#quartz"] = { "minecraft:quartz" },
  ["#planks"] = { "_planks" },
  ["#log"]    = { "_log", "_stem" },
  ["#fuel"]   = { "minecraft:coal", "minecraft:charcoal",
                  -- with no coal or charcoal left, wood keeps the furnaces (and so the
                  -- charcoal) going: the woods kept least for storage first
                  "regions_unexplored:bamboo_log" },
}

-- How to make things. grid = 3x3 crafting layout, read left to right, top to
-- bottom ("" = empty). smelt = furnace input. yield = items per craft.
pendingMake = nil
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
  [K.PICKAXE] = {
    grid = { "D", "D", "D", "", "S", "", "", "S", "" },
    key = { D = "minecraft:diamond", S = "minecraft:stick" },
  },
  ["minecraft:diamond_shovel"] = {
    grid = { "D", "", "", "S", "", "", "S", "", "" },
    key = { D = "minecraft:diamond", S = "minecraft:stick" },
  },
  [K.MODEM] = {
    grid = { "G", "G", "G", "G", "E", "G", "G", "G", "G" },
    key = { G = "minecraft:gold_ingot", E = "minecraft:ender_eye" },
  },
  [K.PLAIN_MODEM] = {
    grid = { "S", "S", "S", "S", "E", "S", "S", "S", "S" },
    key = { S = "minecraft:stone", E = "minecraft:ender_pearl" },
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
  -- fittings for the factory building
  ["minecraft:redstone_torch"] = {
    grid = { "R", "", "", "S", "", "", "", "", "" },
    key = { R = "minecraft:redstone", S = "minecraft:stick" },
  },
  ["minecraft:lever"] = {
    grid = { "S", "", "", "C", "", "", "", "", "" },
    key = { S = "minecraft:stick", C = "minecraft:cobblestone" },
  },
  -- Sophisticated Storage (recipes from the mod's own recipe provider). A
  -- chest or barrel takes the wood it is made of, and all of it must be the
  -- same wood. "@planks" and "@slab" stand for the planks and slabs of ONE
  -- wood, chosen for each craft from what is in stock (see "wood" below);
  -- the planks and slabs themselves need no recipe here, they are worked
  -- out from the log's name (x_log -> x_planks -> x_slab).
  ["minecraft:barrel"] = {                           -- plain: the store's In and Out (not joined to it)
    grid = { "P", "S", "P", "P", "", "P", "P", "S", "P" },
    key = { P = "@planks", S = "@slab" },
  },
  ["sophisticatedstorage:chest"] = {                 -- 27 slots
    grid = { "P", "P", "P", "P", "L", "P", "P", "P", "P" },
    key = { P = "@planks", L = "minecraft:lever" },
  },
  ["sophisticatedstorage:barrel"] = {                -- 27 slots
    grid = { "P", "S", "P", "P", "L", "P", "P", "S", "P" },
    key = { P = "@planks", S = "@slab", L = "minecraft:lever" },
  },
  -- limited barrels show what is in them on the front: 1 to 4 kinds of
  -- item, 32 / 16 / 10 / 8 stacks of each
  ["sophisticatedstorage:limited_barrel_1"] = {
    grid = { "P", "S", "P", "P", "L", "P", "P", "P", "P" },
    key = { P = "@planks", S = "@slab", L = "minecraft:lever" },
  },
  ["sophisticatedstorage:limited_barrel_2"] = {
    grid = { "P", "P", "P", "S", "L", "S", "P", "P", "P" },
    key = { P = "@planks", S = "@slab", L = "minecraft:lever" },
  },
  ["sophisticatedstorage:limited_barrel_3"] = {
    grid = { "P", "S", "P", "P", "L", "P", "S", "P", "S" },
    key = { P = "@planks", S = "@slab", L = "minecraft:lever" },
  },
  ["sophisticatedstorage:limited_barrel_4"] = {
    grid = { "S", "P", "S", "P", "L", "P", "S", "P", "S" },
    key = { P = "@planks", S = "@slab", L = "minecraft:lever" },
  },
  -- bigger chests: metal around the chest one tier down (54 / 81 / 108 slots)
  ["sophisticatedstorage:iron_chest"] = {
    grid = { "I", "I", "I", "I", "C", "I", "I", "I", "I" },
    key = { I = "minecraft:iron_ingot", C = "sophisticatedstorage:chest" },
  },
  ["sophisticatedstorage:gold_chest"] = {
    grid = { "G", "G", "G", "G", "C", "G", "G", "G", "G" },
    key = { G = "minecraft:gold_ingot", C = "sophisticatedstorage:iron_chest" },
  },
  ["sophisticatedstorage:diamond_chest"] = {
    grid = { "D", "D", "D", "D", "C", "D", "D", "D", "D" },
    key = { D = "minecraft:diamond", C = "sophisticatedstorage:gold_chest" },
  },
  -- the controller makes everything touching it one inventory; a link joins
  -- a group that does not touch (set with the storage tool, by a player)
  ["minecraft:comparator"] = {
    grid = { "", "T", "", "T", "Q", "T", "S", "S", "S" },
    key = { T = "minecraft:redstone_torch", Q = "minecraft:quartz", S = "minecraft:stone" },
  },
  ["minecraft:repeater"] = {
    grid = { "T", "R", "T", "S", "S", "S", "", "", "" },
    key = { T = "minecraft:redstone_torch", R = "minecraft:redstone", S = "minecraft:stone" },
  },
  ["sophisticatedstorage:controller"] = {
    grid = { "S", "C", "S", "P", "B", "P", "S", "C", "S" },
    key = { S = "minecraft:stone", C = "minecraft:comparator", P = "@planks",
      B = "sophisticatedstorage:barrel" },
  },
  ["sophisticatedstorage:storage_link"] = {
    grid = { "E", "P", "", "R", "S", "", "", "", "" },
    key = { E = "minecraft:ender_pearl", P = "@planks", R = "minecraft:repeater",
      S = "minecraft:stone" },
  },
  ["sophisticatedstorage:storage_tool"] = {
    grid = { "", "E", "I", "", "S", "T", "S", "", "" },
    key = { E = "minecraft:ender_pearl", I = "minecraft:iron_ingot", S = "minecraft:stick",
      T = "minecraft:redstone_torch" },
  },
  -- upgrades. A tier upgrade is used on a storage block that is already
  -- standing (right click); a stack upgrade goes in its upgrade slot and
  -- multiplies how much each slot holds (tier 1 x2, tier 2 x4, tier 3 x8).
  ["sophisticatedstorage:basic_tier_upgrade"] = {    -- turns a vanilla chest or barrel
    grid = { "", "S", "", "S", "L", "S", "", "S", "" },
    key = { S = "minecraft:stick", L = "minecraft:lever" },
  },
  ["sophisticatedstorage:basic_to_iron_tier_upgrade"] = {
    grid = { "I", "I", "I", "I", "L", "I", "I", "I", "I" },
    key = { I = "minecraft:iron_ingot", L = "minecraft:lever" },
  },
  ["sophisticatedstorage:iron_to_gold_tier_upgrade"] = {
    grid = { "G", "G", "G", "G", "L", "G", "G", "G", "G" },
    key = { G = "minecraft:gold_ingot", L = "minecraft:lever" },
  },
  ["sophisticatedstorage:gold_to_diamond_tier_upgrade"] = {
    grid = { "D", "D", "D", "D", "L", "D", "D", "D", "D" },
    key = { D = "minecraft:diamond", L = "minecraft:lever" },
  },
  ["sophisticatedstorage:upgrade_base"] = {
    grid = { "P", "I", "P", "I", "P", "I", "P", "I", "P" },
    key = { P = "#planks", I = "minecraft:iron_ingot" },
  },
  ["sophisticatedstorage:stack_upgrade_tier_1"] = {
    grid = { "L", "L", "L", "L", "B", "L", "L", "L", "L" },
    key = { L = "#log", B = "sophisticatedstorage:upgrade_base" },
  },
  ["minecraft:iron_block"] = {
    grid = { "I", "I", "I", "I", "I", "I", "I", "I", "I" },
    key = { I = "minecraft:iron_ingot" },
  },
  ["minecraft:gold_block"] = {
    grid = { "G", "G", "G", "G", "G", "G", "G", "G", "G" },
    key = { G = "minecraft:gold_ingot" },
  },
  ["sophisticatedstorage:stack_upgrade_tier_2"] = {
    grid = { "I", "I", "I", "I", "U", "I", "B", "I", "B" },
    key = { I = "minecraft:iron_ingot", U = "sophisticatedstorage:stack_upgrade_tier_1",
      B = "minecraft:iron_block" },
  },
  ["sophisticatedstorage:stack_upgrade_tier_3"] = {
    grid = { "G", "G", "G", "G", "U", "G", "B", "G", "B" },
    key = { G = "minecraft:gold_ingot", U = "sophisticatedstorage:stack_upgrade_tier_2",
      B = "minecraft:gold_block" },
  },
  -- Mekanism parts. Steel dust, control circuits and infused alloy come out
  -- of the Metallurgic Infuser (a helper runs it and hands them in); the
  -- rest is crafted here.
  ["alltheores:steel_ingot"] = { smelt = "alltheores:steel_dust" },
  ["mekanism:steel_casing"] = {
    grid = { "S", "G", "S", "G", "O", "G", "S", "G", "S" },
    key = { S = "alltheores:steel_ingot", G = "minecraft:glass", O = "alltheores:osmium_ingot" },
  },
  ["mekanism:energized_smelter"] = {
    grid = { "R", "C", "R", "G", "K", "G", "R", "C", "R" },
    key = { R = "minecraft:redstone", C = "mekanism:basic_control_circuit", G = "minecraft:glass",
      K = "mekanism:steel_casing" },
  },
  ["mekanism:enrichment_chamber"] = {
    grid = { "R", "C", "R", "I", "K", "I", "R", "C", "R" },
    key = { R = "minecraft:redstone", C = "mekanism:basic_control_circuit", I = "minecraft:iron_ingot",
      K = "mekanism:steel_casing" },
  },
  -- Power, so the machines need no redstone dust fed to them: generators,
  -- cable to carry it, a cube to hold it. NOT YET TRIED in this pack (the
  -- grids are Mekanism's own; a craft that fails is reported and left).
  ["mekanism:basic_universal_cable"] = {                 -- unverified
    yield = 8, grid = { "S", "R", "S", "", "", "", "", "", "" },
    key = { S = "alltheores:steel_ingot", R = "minecraft:redstone" },
  },
  ["mekanism:energy_tablet"] = {                         -- Mekanism 1.21 data: RGR / AGA / RGR
    grid = { "R", "G", "R", "A", "G", "A", "R", "G", "R" },
    key = { R = "minecraft:redstone", G = "minecraft:gold_ingot", A = "mekanism:alloy_infused" },
  },
  ["mekanism:basic_energy_cube"] = {                     -- unverified
    grid = { "R", "T", "R", "I", "K", "I", "R", "T", "R" },
    key = { R = "minecraft:redstone", T = "mekanism:energy_tablet", I = "minecraft:iron_ingot",
      K = "mekanism:steel_casing" },
  },
  ["mekanismgenerators:wind_generator"] = {              -- Mekanism 1.21 data: _O_ / OAO / TCT
    grid = { "", "O", "", "O", "A", "O", "T", "C", "T" },
    key = { O = "alltheores:osmium_ingot", A = "mekanism:alloy_infused", T = "mekanism:energy_tablet",
      C = "mekanism:basic_control_circuit" },
  },
  -- the Crusher (ingots to dust; cobblestone to gravel, gravel to sand): two
  -- lava buckets go into it (the buckets stay in the grid, empty)
  ["mekanism:crusher"] = {                               -- unverified
    grid = { "R", "C", "R", "L", "K", "L", "R", "C", "R" },
    key = { R = "minecraft:redstone", C = "mekanism:basic_control_circuit", L = "minecraft:lava_bucket",
      K = "mekanism:steel_casing" },
  },
  -- Pipes, tubes and the next machines (docs/mekanism-plan.md). Grids are
  -- from Mekanism's own generated recipe data for 1.21 (the 1.21.x branch);
  -- the pack's copy may differ, so each is test-crafted once before a stage
  -- is built. Steel is All the Ores' (ATM unifies it), dusts likewise
  -- ("unverified id": the dust's item name in this pack not yet seen).
  ["mekanism:basic_mechanical_pipe"] = {                 -- fluids (water)
    yield = 8, grid = { "S", "B", "S", "", "", "", "", "", "" },
    key = { S = "alltheores:steel_ingot", B = "minecraft:bucket" },
  },
  ["mekanism:basic_pressurized_tube"] = {                -- gases (oxygen, hydrogen, acid)
    yield = 8, grid = { "S", "G", "S", "", "", "", "", "", "" },
    key = { S = "alltheores:steel_ingot", G = "minecraft:glass" },
  },
  ["mekanism:basic_logistical_transporter"] = {          -- items
    yield = 8, grid = { "S", "C", "S", "", "", "", "", "", "" },
    key = { S = "alltheores:steel_ingot", C = "mekanism:basic_control_circuit" },
  },
  ["mekanism:advanced_control_circuit"] = {              -- (or infuse a basic one with redstone)
    grid = { "A", "C", "A", "", "", "", "", "", "" },
    key = { A = "mekanism:alloy_infused", C = "mekanism:basic_control_circuit" },
  },
  ["mekanism:purification_chamber"] = {                  -- 3x: raw ore + oxygen -> clumps
    grid = { "A", "C", "A", "O", "E", "O", "A", "C", "A" },
    key = { A = "mekanism:alloy_infused", C = "mekanism:advanced_control_circuit",
      O = "alltheores:osmium_ingot", E = "mekanism:enrichment_chamber" },
  },
  ["mekanism:electrolytic_core"] = {                     -- unverified ids (the three dusts)
    grid = { "A", "O", "A", "I", "A", "G", "A", "O", "A" },
    key = { A = "mekanism:alloy_infused", O = "alltheores:osmium_dust", I = "alltheores:iron_dust",
      G = "alltheores:gold_dust" },
  },
  ["mekanism:electrolytic_separator"] = {                -- water -> hydrogen + oxygen
    grid = { "I", "R", "I", "A", "E", "A", "I", "R", "I" },
    key = { I = "minecraft:iron_ingot", R = "minecraft:redstone", A = "mekanism:alloy_infused",
      E = "mekanism:electrolytic_core" },
  },
  ["mekanism:electric_pump"] = {                         -- draws water from a pool below it
    grid = { "", "B", "", "A", "K", "A", "O", "O", "O" },
    key = { B = "minecraft:bucket", A = "mekanism:alloy_infused", K = "mekanism:steel_casing",
      O = "alltheores:osmium_ingot" },
  },
  ["mekanism:basic_fluid_tank"] = {
    grid = { "R", "I", "R", "I", "", "I", "R", "I", "R" },
    key = { R = "minecraft:redstone", I = "minecraft:iron_ingot" },
  },
  ["mekanism:basic_chemical_tank"] = {
    grid = { "R", "O", "R", "O", "", "O", "R", "O", "R" },
    key = { R = "minecraft:redstone", O = "alltheores:osmium_ingot" },
  },
  ["mekanism:dynamic_tank"] = {
    yield = 4, grid = { "", "S", "", "S", "B", "S", "", "S", "" },
    key = { S = "alltheores:steel_ingot", B = "minecraft:bucket" },
  },
  ["mekanism:advanced_energy_cube"] = {
    grid = { "A", "T", "A", "O", "C", "O", "A", "T", "A" },
    key = { A = "mekanism:alloy_infused", T = "mekanism:energy_tablet", O = "alltheores:osmium_ingot",
      C = "mekanism:basic_energy_cube" },
  },
  ["mekanismgenerators:solar_panel"] = {
    grid = { "P", "P", "P", "R", "A", "R", "O", "O", "O" },
    key = { P = "minecraft:glass_pane", R = "minecraft:redstone", A = "mekanism:alloy_infused",
      O = "alltheores:osmium_ingot" },
  },
  ["mekanismgenerators:solar_generator"] = {
    grid = { "P", "P", "P", "A", "I", "A", "O", "T", "O" },
    key = { P = "mekanismgenerators:solar_panel", A = "mekanism:alloy_infused", I = "minecraft:iron_ingot",
      O = "alltheores:osmium_ingot", T = "mekanism:energy_tablet" },
  },
  ["mekanismgenerators:gas_burning_generator"] = {       -- burns the separator's hydrogen
    grid = { "O", "A", "O", "K", "E", "K", "O", "A", "O" },
    key = { O = "alltheores:osmium_ingot", A = "mekanism:alloy_infused", K = "mekanism:steel_casing",
      E = "mekanism:electrolytic_core" },
  },
  ["mekanism:basic_smelting_factory"] = {                -- three smelts at once
    grid = { "R", "C", "R", "I", "M", "I", "R", "C", "R" },
    key = { R = "minecraft:redstone", C = "mekanism:basic_control_circuit", I = "minecraft:iron_ingot",
      M = "mekanism:energized_smelter" },
  },
  ["mekanism:basic_enriching_factory"] = {
    grid = { "R", "C", "R", "I", "M", "I", "R", "C", "R" },
    key = { R = "minecraft:redstone", C = "mekanism:basic_control_circuit", I = "minecraft:iron_ingot",
      M = "mekanism:enrichment_chamber" },
  },
  ["mekanism:basic_crushing_factory"] = {
    grid = { "R", "C", "R", "I", "M", "I", "R", "C", "R" },
    key = { R = "minecraft:redstone", C = "mekanism:basic_control_circuit", I = "minecraft:iron_ingot",
      M = "mekanism:crusher" },
  },
  ["minecraft:piston"] = {
    grid = { "P", "P", "P", "C", "I", "C", "C", "R", "C" },
    key = { P = "#planks", C = "minecraft:cobblestone", I = "minecraft:iron_ingot", R = "minecraft:redstone" },
  },
  ["mekanism:logistical_sorter"] = {                     -- pulls from the inventory behind it
    grid = { "I", "P", "I", "I", "C", "I", "I", "I", "I" },
    key = { I = "minecraft:iron_ingot", P = "minecraft:piston", C = "mekanism:basic_control_circuit" },
  },
  -- Stages 4 and 5 of the line (tools/mekline.py). Grids from Mekanism's
  -- generated 1.21.x recipe data. Made elsewhere and handed in:
  --   alloy_reinforced  infuser (foundry make=reinforced): infused alloy + 20 mB
  --                     diamond (enriched diamond: foundry enrich=minecraft:diamond)
  --   alloy_atomic      infuser (make=atomic): reinforced alloy + 40 mB refined
  --                     obsidian (its dust, or enriched: enrich=mekanism:dust_refined_obsidian)
  --   dust_refined_obsidian  infuser (make=refined): obsidian dust + 10 mB diamond;
  --                     the obsidian dust is a Crusher's (1 obsidian -> 4): NOT a foundry machine
  --   ingot_refined_obsidian  Osmium Compressor (the dust + osmium gas): NOT a foundry machine
  --   fluorite_gem      mined
  ["mekanism:elite_control_circuit"] = {
    grid = { "A", "C", "A", "", "", "", "", "", "" },
    key = { A = "mekanism:alloy_reinforced", C = "mekanism:advanced_control_circuit" },
  },
  ["mekanism:ultimate_control_circuit"] = {
    grid = { "A", "C", "A", "", "", "", "", "", "" },
    key = { A = "mekanism:alloy_atomic", C = "mekanism:elite_control_circuit" },
  },
  ["mekanism:chemical_injection_chamber"] = {            -- takes a purification chamber
    grid = { "A", "C", "A", "G", "P", "G", "A", "C", "A" },
    key = { A = "mekanism:alloy_reinforced", C = "mekanism:elite_control_circuit", G = "minecraft:gold_ingot",
      P = "mekanism:purification_chamber" },
  },
  ["mekanism:chemical_crystallizer"] = {
    grid = { "I", "F", "I", "C", "K", "C", "I", "F", "I" },
    key = { I = "mekanism:ingot_refined_obsidian", F = "mekanism:fluorite_gem",
      C = "mekanism:ultimate_control_circuit", K = "mekanism:steel_casing" },
  },
  ["mekanism:chemical_washer"] = {
    grid = { "I", "B", "I", "C", "K", "C", "I", "T", "I" },
    key = { I = "mekanism:ingot_refined_obsidian", B = "mekanism:basic_fluid_tank",
      C = "mekanism:ultimate_control_circuit", K = "mekanism:steel_casing", T = "mekanism:basic_chemical_tank" },
  },
  ["mekanism:chemical_dissolution_chamber"] = {
    grid = { "I", "T", "I", "C", "K", "C", "I", "T", "I" },
    key = { I = "mekanism:ingot_refined_obsidian", C = "mekanism:ultimate_control_circuit",
      K = "mekanism:steel_casing", T = "mekanism:basic_chemical_tank" },
  },
  ["mekanism:osmium_compressor"] = {                     -- for refined obsidian ingots (not yet in the foundry)
    grid = { "A", "C", "A", "B", "K", "B", "A", "C", "A" },
    key = { A = "mekanism:alloy_infused", C = "mekanism:advanced_control_circuit", B = "minecraft:bucket",
      K = "mekanism:steel_casing" },
  },
  -- Applied Energistics 2, to start with (patterns from AE2's own generated
  -- recipe data): the charger turns a compass into a Meteorite Compass, the
  -- crank powers it by hand, the inscriber prints processors once the presses
  -- are found. The Meteorite Compass itself is not crafted: a compass sits in
  -- a powered charger.
  ["minecraft:compass"] = {
    grid = { "", "I", "", "I", "R", "I", "", "I", "" },
    key = { I = "minecraft:iron_ingot", R = "minecraft:redstone" },
  },
  ["ae2:charger"] = {
    grid = { "I", "C", "I", "I", "", "", "I", "C", "I" },
    key = { I = "minecraft:iron_ingot", C = "minecraft:copper_ingot" },
  },
  ["ae2:crank"] = {
    grid = { "S", "S", "S", "", "", "S", "", "", "C" },
    key = { S = "minecraft:stick", C = "minecraft:copper_ingot" },
  },
  ["ae2:inscriber"] = {
    grid = { "I", "P", "I", "C", "", "I", "I", "P", "I" },
    key = { I = "minecraft:iron_ingot", P = "minecraft:piston", C = "minecraft:copper_ingot" },
  },
  ["ae2:energy_acceptor"] = {                            -- needs quartz glass (certus): later
    grid = { "I", "Q", "I", "Q", "C", "Q", "I", "Q", "I" },
    key = { I = "minecraft:iron_ingot", Q = "ae2:quartz_glass", C = "minecraft:copper_ingot" },
  },
  -- Mekanism, to start with: an infuser and something to power it
  ["alltheores:osmium_ingot"] = { smelt = "alltheores:raw_osmium" },
  ["mekanism:metallurgic_infuser"] = {
    grid = { "I", "F", "I", "R", "O", "R", "I", "F", "I" },
    key = { I = "minecraft:iron_ingot", F = "minecraft:furnace", R = "minecraft:redstone",
      O = "alltheores:osmium_ingot" },
  },
  ["mekanismgenerators:heat_generator"] = {
    grid = { "I", "I", "I", "P", "O", "P", "C", "F", "C" },
    key = { I = "minecraft:iron_ingot", P = "#planks", O = "alltheores:osmium_ingot",
      C = "minecraft:copper_ingot", F = "minecraft:furnace" },
  },
  -- Nether quartz with no Nether (tools/quartzline.py): sand
  -- becomes soul sand in front of an Atomic Reconstructor (Actually
  -- Additions; its casing takes the black quartz the miners bring up), and
  -- soul sand washed by a Create fan gives quartz one time in eight, four
  -- at a time. Grids from the mods' own recipe files for 1.21.1; not yet
  -- crafted in this pack. The andesite casing has no crafting recipe: a
  -- helper makes it in the world (andesite alloy used on a stripped log).
  ["actuallyadditions:iron_casing"] = {
    grid = { "I", "S", "I", "S", "Q", "S", "I", "S", "I" },
    key = { I = "minecraft:iron_ingot", S = "minecraft:stick", Q = "actuallyadditions:black_quartz" } },
  ["actuallyadditions:atomic_reconstructor"] = {
    grid = { "I", "R", "I", "R", "C", "R", "I", "R", "I" },
    key = { I = "minecraft:iron_ingot", R = "minecraft:redstone", C = "actuallyadditions:iron_casing" } },
  ["actuallyadditions:coal_generator"] = {
    grid = { "C", "I", "C", "C", "A", "C", "C", "I", "C" },
    key = { C = "minecraft:cobblestone", I = "actuallyadditions:iron_casing", A = "minecraft:coal" } },
  ["create:andesite_alloy"] = {
    grid = { "N", "A", "", "A", "N", "", "", "", "" },
    key = { N = "minecraft:iron_nugget", A = "minecraft:andesite" } },
  ["create:shaft"] = { yield = 8,
    grid = { "A", "", "", "A", "", "", "", "", "" },
    key = { A = "create:andesite_alloy" } },
  -- (the hammer is a tool: it comes back from the grid, a little worn)
  ["alltheores:iron_ore_hammer"] = {
    grid = { "", "B", "S", "", "S", "B", "S", "", "" },
    key = { B = "minecraft:iron_block", S = "minecraft:stick" } },
  ["alltheores:iron_plate"] = { tool = "alltheores:iron_ore_hammer",
    grid = { "H", "I", "", "I", "", "", "", "", "" },
    key = { H = "alltheores:iron_ore_hammer", I = "minecraft:iron_ingot" } },
  ["create:propeller"] = {
    grid = { "", "P", "", "P", "A", "P", "", "P", "" },
    key = { P = "alltheores:iron_plate", A = "create:andesite_alloy" } },
  ["create:encased_fan"] = {
    grid = { "S", "", "", "C", "", "", "P", "", "" },
    key = { S = "create:shaft", C = "create:andesite_casing", P = "create:propeller" } },
  ["create:water_wheel"] = {
    grid = { "P", "P", "P", "P", "S", "P", "P", "P", "P" },
    key = { P = "#planks", S = "create:shaft" } },
  -- a pickaxe turtle cannot break wooden blocks (barrels, controllers):
  -- helpers carry an axe for those
  ["minecraft:diamond_axe"] = { grid = { "D", "D", "", "D", "S", "", "", "S", "" },
    key = { D = "minecraft:diamond", S = "minecraft:stick" } },
  ["minecraft:cauldron"] = {
    grid = { "I", "", "I", "I", "", "I", "I", "I", "I" },
    key = { I = "minecraft:iron_ingot" } },
  ["minecraft:bucket"] = {
    grid = { "I", "", "I", "", "I", "", "", "", "" },
    key = { I = "minecraft:iron_ingot" } },
  ["minecraft:furnace"] = {
    grid = { "C", "C", "C", "C", "", "C", "C", "C", "C" },
    key = { C = "minecraft:cobblestone" },
  },
  ["minecraft:ladder"] = {
    yield = 3, grid = { "S", "", "S", "S", "S", "S", "S", "", "S" },
    key = { S = "minecraft:stick" },
  },
  ["minecraft:iron_bars"] = {
    yield = 16, grid = { "I", "I", "I", "I", "I", "I", "", "", "" },
    key = { I = "minecraft:iron_ingot" },
  },
  ["minecraft:iron_nugget"] = {
    yield = 9, grid = { "I", "", "", "", "", "", "", "", "" },
    key = { I = "minecraft:iron_ingot" },
  },
  ["minecraft:chain"] = {
    grid = { "N", "", "", "I", "", "", "N", "", "" },
    key = { N = "minecraft:iron_nugget", I = "minecraft:iron_ingot" },
  },
  ["minecraft:torch"] = {
    yield = 4, grid = { "C", "", "", "S", "", "", "", "", "" },
    key = { C = "#fuel", S = "minecraft:stick" },
  },
  ["minecraft:lantern"] = {
    grid = { "N", "N", "N", "N", "T", "N", "N", "N", "N" },
    key = { N = "minecraft:iron_nugget", T = "minecraft:torch" },
  },
  ["minecraft:lightning_rod"] = {
    grid = { "C", "", "", "C", "", "", "C", "", "" },
    key = { C = "minecraft:copper_ingot" },
  },
  ["computercraft:cable"] = {
    yield = 6, grid = { "", "S", "", "S", "R", "S", "", "S", "" },
    key = { S = "minecraft:stone", R = "minecraft:redstone" },
  },
  ["computercraft:wired_modem"] = {
    grid = { "S", "S", "S", "S", "R", "S", "S", "S", "S" },
    key = { S = "minecraft:stone", R = "minecraft:redstone" },
  },
  ["computercraft:wired_modem_full"] = {
    grid = { "M", "", "", "", "", "", "", "", "" },
    key = { M = "computercraft:wired_modem" },
  },
  ["computercraft:monitor_advanced"] = {
    yield = 4, grid = { "G", "G", "G", "G", "P", "G", "G", "G", "G" },
  -- the rest of the screens' kit. A station is a plain computer (COMPUTER,
  -- further down): it drives an advanced monitor in colour just the same.
  ["computercraft:computer_advanced"] = {            -- (unverified: as the plain one, in gold)
    grid = { "G", "G", "G", "G", "R", "G", "G", "P", "G" },
    key = { G = "minecraft:gold_ingot", R = "minecraft:redstone", P = "minecraft:glass_pane" },
  },
  ["computercraft:disk_drive"] = {                   -- (unverified)
    grid = { "S", "S", "S", "S", "R", "S", "S", "R", "S" },
    key = { S = "minecraft:stone", R = "minecraft:redstone" },
  },
  ["computercraft:disk"] = {                         -- a floppy (unverified; needs paper, which nobody mines)
    grid = { "R", "P", "", "", "", "", "", "", "" },
    key = { R = "minecraft:redstone", P = "minecraft:paper" },
  },
  ["minecraft:paper"] = {
    yield = 3,
    grid = { "C", "C", "C", "", "", "", "", "", "" },
    key = { C = "minecraft:sugar_cane" },
  },
    key = { G = "minecraft:gold_ingot", P = "minecraft:glass_pane" },
  },
  -- unpacking storage blocks (packed by tidyStorage when the chests fill up)
  ["minecraft:redstone"] = { unpack = true, yield = 9, grid = { "B", "", "", "", "", "", "", "", "" },
    key = { B = "minecraft:redstone_block" } },
  ["minecraft:raw_copper"] = { unpack = true, yield = 9, grid = { "B", "", "", "", "", "", "", "", "" },
    key = { B = "minecraft:raw_copper_block" } },
  ["minecraft:raw_iron"] = { unpack = true, yield = 9, grid = { "B", "", "", "", "", "", "", "", "" },
    key = { B = "minecraft:raw_iron_block" } },
  ["minecraft:coal"] = { unpack = true, yield = 9, grid = { "B", "", "", "", "", "", "", "", "" },
    key = { B = "minecraft:coal_block" } },
  ["minecraft:coal_block"] = { unpack = true, yield = 9, grid = { "B", "", "", "", "", "", "", "", "" },
    key = { B = "allthecompressed:coal_block_1x" } },
  ["minecraft:raw_gold"] = { unpack = true, yield = 9, grid = { "B", "", "", "", "", "", "", "", "" },
    key = { B = "minecraft:raw_gold_block" } },
  ["minecraft:cobblestone"] = { unpack = true, yield = 9, grid = { "B", "", "", "", "", "", "", "", "" },
    key = { B = "allthecompressed:cobblestone_1x" } },
  ["minecraft:cobbled_deepslate"] = { unpack = true, yield = 9, grid = { "B", "", "", "", "", "", "", "", "" },
    key = { B = "allthecompressed:cobbled_deepslate_1x" } },
  ["minecraft:dirt"] = { unpack = true, yield = 9, grid = { "B", "", "", "", "", "", "", "", "" },
    key = { B = "allthecompressed:dirt_1x" } },
  [K.BUCKET] = {
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
  [K.COMPUTER] = {
    grid = { "S", "S", "S", "S", "R", "S", "S", "P", "S" },
    key = { S = "minecraft:stone", R = "minecraft:redstone", P = "minecraft:glass_pane" },
  },
  [K.TURTLE] = {
    grid = { "I", "I", "I", "I", "C", "I", "I", "K", "I" },
    key = { I = "minecraft:iron_ingot", C = K.COMPUTER, K = "minecraft:chest" },
  },
}

-- What one finished miner is assembled from.
local MINER_PARTS = { [K.TURTLE] = 1, [K.PICKAXE] = 1, [K.MODEM] = 1 }

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
  while #logLines > 30 do table.remove(logLines, 1) end
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

local base = loadTable(K.BASE_FILE)                 -- where everything is
local plots = loadTable(K.PLOTS_FILE) or { next = 1, byId = {}, done = 0 }
-- The plot grid stays where it was first laid out (round Crafty's spot at
-- the time), so moving Crafty does not move anybody's plots.
if base and base.f and not plots.origin and not K.COUNTER then
  plots.origin = { x = base.f.x, y = base.f.y, z = base.f.z }
  saveTable(K.PLOTS_FILE, plots)
end
local pending = 0        -- miners launched that have not asked for a plot yet
local fuelQueue = {}     -- miners waiting on the launch pad for fuel
local emptiesQueue = {}  -- the lava runner asking for empty buckets: id -> how many
local scannerQueue = {}  -- a miner told to hunt, asking for a spare Geo Scanner
local ctlQueue = {}      -- turtles asking for a Chunk Controller of their own to carry: id -> when
K.CTL_PER_TURTLE = 2 -- (ever: one, and one more if it loses the first)
K.FUEL_RESERVE = 256 -- coal never handed out to miners
K.LOGS_KEPT = 160    -- logs of each wood the furnaces leave alone: chests, barrels and the
                         -- storage room are made of wood (whatever wood there is)
-- More dispensing turtles ("Counter", "Counter2", ... by label), each on a
-- launch pad of its own: they only serve helpers' loads, so several can be
-- served at once. Each says it is alive (counter_alive, with its number)
-- every 30 s; with the highest number heard in the last 150 s being N,
-- a load from turtle id goes to dispenser id % (N + 1): 0 is Crafty, k is
-- Counter k. Crafty serves any share whose counter has gone quiet. (With
-- one Counter that is the odd ids, as before.)
do
  local digits = (os.getComputerLabel() or ""):lower():match("^counter(%d*)")
  K.COUNTER = digits ~= nil
  K.SLOT = K.COUNTER and (tonumber(digits) or 1) or 0
end
K.counters = {}          -- counter number -> when last heard (os.clock)
K.adopted = {}           -- helper id -> true: a Counter's load Crafty took over
K.foreign = {}           -- helper id -> the order a Counter has (items, fuel, n, at, readyAt)
-- The Counter fallback: a load left ready at a Counter's pad this long without
-- being collected is made and served by Crafty instead.
K.COUNTER_GIVE_UP = 180
-- The watchdog: a helper in a waiting state this long gets its load
-- announced again; still waiting this much later, it is told to reboot.
K.STALL_AFTER = 600
K.STALL_REBOOT = 300
K.stall = {}             -- fleet key -> { step = 1|2, at = os.clock() }
K.stalledList = {}       -- labels, for the status report
-- the rack's screens hear the drones through Crafty, over the cable
K.RACK_CHANNEL = 4711
K.counterBeat = -1000
function K.alive(slot)
  return slot == K.SLOT or (K.counters[slot] and os.clock() - K.counters[slot] < 150) or false
end
function K.shareOf(id)
  local top = K.SLOT
  for slot in pairs(K.counters) do
    if slot > top and K.alive(slot) then top = slot end
  end
  return top == 0 and 0 or id % (top + 1)
end
-- Is turtle id's load mine to serve?
function K.mine(id)
  if K.adopted[id] then return not K.COUNTER end    -- (a Counter's load it never handed over)
  local share = K.shareOf(id)
  if K.COUNTER then return share == K.SLOT end
  return share == 0 or not K.alive(share)
end
K.HELPERS      = 4   -- builder's mates to make (mining turtles running helper.lua);
                         -- the third is the lumberjack
-- (the fourth runs the Mekanism machines; the rest are names for mates made later)
local HELPER_NAMES = { "Pushy", "HopTo", "LeverAlone", "DropIt",
  "Sticky", "Dusty", "OnRepeat", "Comparable", "Observant", "Dispensable",
  "ButtonUp", "PlateUp", "Tripwired", "LampLit", "NoteWorthy", "TargetLock" }
local launchingHelper = false
-- Chunk loaders (turtles with a Chunk Controller, running loader.lua): one
-- is built whenever there is a controller in stock and an ender modem to be
-- had for it (in stock, or made from gold and an ender eye), for as long as
-- there are names. One always stays parked at the base (see "pairing chunk
-- loaders"); the others go out with whoever is working far away.
-- (The first loader, Ghastly, was made by hand and is not in this list.)
local LOADER_NAMES = { "Phantastic", "Ablaze", "Vexed", "Beehave", "Batty", "Breezy",
  "AllayOop", "WitherOrNot", "Shulky", "Squawk" }
local LOADERS      = #LOADER_NAMES
K.PLAIN_LOADERS = false   -- true: with no ender modem to be had, a plain wireless modem will do
local lastLoaderWait
local bucketQueue = {}   -- miners waiting on the launch pad for a bucket
local orders = {}        -- builder material orders, by computer id
local bootstrapFuel      -- defined further down (fuel from nothing)
local dumpJunk           -- defined further down (unwanted stone)
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
K.MINE_ROOM = 0.10     -- share of storage slots that must be free before a miner is given a new plot
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
    role = K.COUNTER and "counter" or "factory",
    state = state,
    stalled = (not K.COUNTER and #K.stalledList > 0) and K.stalledList or nil,
    built = built,
    storage = storageSpace(),
    inv = lastStock,
    missing = lastMissing,
    network = lastNetwork,
    base = base,
    fleet = { active = activeCount(), launching = pending, max = K.MAX_MINERS,
      builder = plots.builderId,
      plotsDone = plots.done, nextPlot = plots.next, byId = plots.byId },
    foundry = plots.foundry and { op = plots.foundry.op, machines = plots.foundry.machines,
      job = plots.foundry.job and (plots.foundry.job.item or plots.foundry.job.kind), fails = plots.foundry.fails,
      last = plots.foundry.last, power = plots.foundry.power } or nil,
    log = logLines,
  })
end

---------------------------------------------------------------- network

local modem      -- the wired modem behind the turtle
local selfName   -- this turtle's name on the wired network
local furnaces = {}  -- names of furnaces

-- Which wood a log is: "minecraft:oak_log" and "minecraft:stripped_oak_log"
-- are "minecraft:oak", "biomesoplenty:hellbark_stem" is
-- "biomesoplenty:hellbark". Its planks and slabs are then <wood>_planks and
-- <wood>_slab, whatever mod it is from.
local function woodOfLog(name)
  local ns, rest = name:match("^([%w_%.%-]+):(.+)$")
  if not ns then return nil end
  local base = rest:match("^(.+)_log$") or rest:match("^(.+)_stem$")
  if not base or base == "mushroom" then return nil end
  return ns .. ":" .. (base:gsub("^stripped_", ""))
end

local function matches(wanted, name)
  if wanted:sub(1, 5) == "@log:" then return woodOfLog(name) == wanted:sub(6) end   -- the logs of one wood
  if wanted:sub(1, 1) ~= "#" then return wanted == name end
  for _, suffix in ipairs(GROUPS[wanted] or {}) do
    if name == suffix or name:sub(-#suffix) == suffix then return true end
  end
  return false
end

local function shortName(name)
  if name:sub(1, 5) == "@log:" then return shortName(name:sub(6)) .. " log" end
  return (name:gsub("^[#@]", ""):gsub("^[%w_]+:", ""):gsub("_", " "))
end

-- Find the wired modem and everything attached to the network.
-- Not storage, though it is an inventory on the cable: Sortnado's In and
-- Out barrels (the store's door: Sortnado empties one and the player takes
-- from the other), an Inventory Manager, and names (or name* prefixes) the
-- order "stores Crafty skip=a,b" gives (the Mekanism line's chests, say).
-- a helper's name on the cable, as it says it (turtle_<n> only)
function K.bayName(b)
  return type(b) == "string" and b:match("^turtle_%d+$") and b or nil
end

function K.notStore(name)
  if name:find("^minecraft:barrel") then return true end
  for _, t in ipairs({ "inventory_manager", "inventoryManager", "me_bridge", "meBridge" }) do
    if peripheral.hasType(name, t) then return true end
  end
  for _, p in ipairs((plots.stores and plots.stores.skip) or {}) do
    if name == p or (p:sub(-1) == "*" and name:sub(1, #p - 1) == p:sub(1, -2)) then return true end
  end
  return false
end

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
      elseif K.notStore(name) then
        -- the store's In and Out barrels (Sortnado's, and the player's), a
        -- manager, and whatever the order "stores Crafty skip=..." names
      else
        stores[#stores + 1] = name
      end
    end
  end
  -- with the storage room on the cable, things are put away in its
  -- controllers first (anything else is only taken from)
  table.sort(stores, function(a, b)
    local ca, cb = a:find("controller", 1, true) ~= nil, b:find("controller", 1, true) ~= nil
    if ca ~= cb then return ca end
    return a < b
  end)
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
  local storage = listStorage()
  if wanted == "#log" or wanted == "#planks" then
    -- any wood will do: the kind there is most of first, by name after
    -- that. The planner takes them in the same order (takeFrom), so a
    -- stick's planks do not come out of the wood a chest was counted on.
    local totals = {}
    for _, st in ipairs(storage) do
      if matches(wanted, st.name) then totals[st.name] = (totals[st.name] or 0) + st.count end
    end
    table.sort(storage, function(x, y)
      local tx, ty = totals[x.name] or 0, totals[y.name] or 0
      if tx ~= ty then return tx > ty end
      if x.name ~= y.name then return x.name < y.name end
      if x.inv ~= y.inv then return x.inv < y.inv end
      return x.slot < y.slot
    end)
  end
  for _, s in ipairs(storage) do
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
  -- (of a group, the kind there is most of first: the same order pull uses)
  local names = {}
  for name, c in pairs(stock) do
    if c > 0 and matches(wanted, name) then names[#names + 1] = name end
  end
  table.sort(names, function(x, y)
    if stock[x] ~= stock[y] then return stock[x] > stock[y] end
    return x < y
  end)
  for _, name in ipairs(names) do
    if n <= 0 then break end
    local t = math.min(stock[name], n)
    stock[name] = stock[name] - t
    n = n - t
  end
end

---------------------------------------------------------------- wood
-- A recipe with "@planks" or "@slab" in it is made of one wood, and never
-- a mix: for each craft the planner picks a wood from the stock, counting
-- that wood's logs, planks and slabs together. Oak when there is enough oak
-- for all that is wanted; otherwise the wood there is most of that can
-- make them all; otherwise the order is spread, one wood per item.

plots.badWood = plots.badWood or {}              -- woods whose planks are not called what the log suggests
local badWood = plots.badWood                    -- (remembered over restarts)
local function markBadWood(wood)
  badWood[wood] = true
  plots.badWood = badWood
  saveTable(K.PLOTS_FILE, plots)
end
local knownWood = { ["minecraft:oak"] = true }   -- woods seen in stock

-- The recipe for something not in the list: planks from the logs of their
-- wood, slabs from the planks.
local function recipeFor(name)
  local recipe = RECIPES[name]
  if recipe then return recipe end
  local wood = name:match("^([%w_%.%-]+:.+)_planks$")
  if wood then
    return { yield = 4, wood = wood, grid = { "L", "", "", "", "", "", "", "", "" }, key = { L = "@log:" .. wood } }
  end
  wood = name:match("^([%w_%.%-]+:.+)_slab$")
  if wood and knownWood[wood] then
    return { yield = 6, wood = wood, grid = { "P", "P", "P", "", "", "", "", "", "" }, key = { P = wood .. "_planks" } }
  end
  return nil
end

-- How many planks and slabs of its one wood a recipe takes per craft.
local function woodNeeds(recipe)
  local planks, slabs = 0, 0
  for _, k in ipairs(recipe.grid or {}) do
    local item = k ~= "" and recipe.key[k]
    if item == "@planks" then planks = planks + 1 elseif item == "@slab" then slabs = slabs + 1 end
  end
  return planks, slabs
end

-- The same recipe, in one wood.
local function ofWood(recipe, wood)
  local key = {}
  for k, item in pairs(recipe.key) do
    key[k] = item == "@planks" and wood .. "_planks" or item == "@slab" and wood .. "_slab" or item
  end
  return { yield = recipe.yield, grid = recipe.grid, key = key }
end

-- What there is of each wood: { wood = { logs, planks, slabs } }
local function woodStock(stock)
  local woods = {}
  local function at(wood)
    woods[wood] = woods[wood] or { logs = 0, planks = 0, slabs = 0 }
    return woods[wood]
  end
  for name, count in pairs(stock) do
    if count > 0 then
      local wood = woodOfLog(name)
      if wood then
        at(wood).logs = at(wood).logs + count
      else
        wood = name:match("^([%w_%.%-]+:.+)_planks$")
        if wood then at(wood).planks = at(wood).planks + count end
      end
    end
  end
  for wood, t in pairs(woods) do
    t.slabs = stock[wood .. "_slab"] or 0
    knownWood[wood] = true
  end
  return woods
end

-- How many crafts (up to most) of planks + slabs each a wood can finish.
local function woodCan(t, planks, slabs, most)
  local k = 0
  while k < most do
    local n = k + 1
    local slabCrafts = math.ceil(math.max(0, slabs * n - t.slabs) / 6)       -- 3 planks make 6 slabs
    local need = planks * n + 3 * slabCrafts
    if math.ceil(math.max(0, need - t.planks) / 4) > t.logs then break end    -- a log makes 4 planks
    k = n
  end
  return k
end

-- The wood for the next crafts, and how many of the n wanted it will make.
-- The first choice is oak, unless an order named another ("wood" order:
-- first=regions_unexplored:magnolia, kept in the plots file as plots.wood).
local function chooseWood(stock, planks, slabs, n)
  local woods = woodStock(stock)
  local first = plots.wood or "minecraft:oak"
  local t = woods[first]
  if t and not badWood[first] and woodCan(t, planks, slabs, n) >= n then
    return first, n
  end
  local best, bestK, bestSize
  for wood, t in pairs(woods) do
    local k = badWood[wood] and 0 or woodCan(t, planks, slabs, n)
    if k > 0 then
      local size = t.logs * 4 + t.planks + t.slabs / 2
      local all, bestAll = k >= n, best ~= nil and bestK >= n
      if not best or (all and not bestAll)
        or (all == bestAll and (size > bestSize or (size == bestSize and wood < best))) then
        best, bestK, bestSize = wood, k, size
      end
    end
  end
  return best, bestK
end

-- A "wood" order: which wood to reach for first. "oak" or nothing puts it
-- back to oak; a bare name ("magnolia") is looked up among the woods in stock.
local function setFirstWood(name)
  name = type(name) == "string" and name:lower() or "oak"
  if not name:find(":", 1, true) then
    local found
    for wood in pairs(woodStock(stockTotals())) do
      if wood:match(":(.+)$") == name and (not found or wood < found) then found = wood end
    end
    name = found or ("minecraft:" .. name)
  end
  plots.wood = name ~= "minecraft:oak" and name or nil
  saveTable(K.PLOTS_FILE, plots)
  print("First-choice wood: " .. shortName(name) .. ".")
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

  local recipe = recipeFor(wanted)
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
  local woodPlanks, woodSlabs = woodNeeds(recipe)
  if woodPlanks + woodSlabs > 0 then
    -- made of one wood. Everything else first (a lever's stick may take
    -- planks of any wood), then the wood for each craft from what is left.
    local needs = ingredients(recipe)
    for name, per in pairs(needs) do
      if name:sub(1, 1) ~= "@" then plan(stock, name, per * batches, steps, missing) end
    end
    local left = batches
    while left > 0 do
      local wood, k = chooseWood(stock, woodPlanks, woodSlabs, left)
      if not wood then
        -- (said in logs: that is what someone can go and fetch)
        local planks = woodPlanks * left + math.ceil(woodSlabs * left / 6) * 3
        missing["#log"] = (missing["#log"] or 0) + math.ceil(planks / 4)
        return
      end
      if woodPlanks > 0 then plan(stock, wood .. "_planks", woodPlanks * k, steps, missing) end
      if woodSlabs > 0 then plan(stock, wood .. "_slab", woodSlabs * k, steps, missing) end
      steps[#steps + 1] = { name = wanted, batches = k, wood = wood }
      left = left - k
    end
  else
    for name, per in pairs(ingredients(recipe)) do
      if recipe.tool == name then
        -- a tool: one does for every craft, and it comes back afterwards
        plan(stock, name, 1, steps, missing)
        stock[name] = (stock[name] or 0) + 1
      else
        plan(stock, name, per * batches, steps, missing)
      end
    end
    if recipe.smelt then
      plan(stock, "#fuel", math.ceil(batches / 8), steps, missing)
    end
    steps[#steps + 1] = { name = wanted, batches = batches, recipe = recipe.wood and recipe or nil }
  end

  -- anything made beyond what was needed goes back on the pretend shelf
  local spare = batches * yield - short
  if spare > 0 then
    local key = wanted
    if wanted:sub(1, 1) == "#" then key = "spare" .. GROUPS[wanted][1] end
    stock[key] = (stock[key] or 0) + spare
  end
end

---------------------------------------------------------------- doing

-- After a craft of planks or slabs worked out from a log's name: is it
-- what the name said it would be? If not, that wood is left alone from now on.
local function checkWood(name, recipe)
  if not recipe.wood or not turtle.getItemDetail then return end
  local made = turtle.getItemDetail(16)
  if made and made.name ~= name then
    markBadWood(recipe.wood)
    stashAll()
    error(("Expected %s but the craft made %s: not using %s wood."):format(shortName(name),
      shortName(made.name), shortName(recipe.wood)), 0)
  end
end

local function craftOnce(name, recipe)
  recipe = recipe or recipeFor(name)
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
    if recipe.wood and tostring(err):find("No matching") then markBadWood(recipe.wood) end
    error("The recipe for " .. shortName(name) .. " did not work: "
      .. tostring(err), 0)
  end
  checkWood(name, recipe)
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
  if fuelSlot and fuelSlot.name == K.BUCKET then
    -- a lava bucket has been burned: the empty one goes back to storage
    for _, inv in ipairs(stores) do
      if (peripheral.call(f, "pushItems", inv, 2) or 0) > 0 then break end
    end
    fuelSlot = furnaceList(f)[2]
  end
  local fuelHave = fuelSlot and fuelSlot.count or 0
  if fuelSlot and fuelSlot.name == K.LAVA then fuelHave = 13 end       -- a bucket cooks 100
  if fuelHave < fuelNeeded and not fuelSlot and count >= 32 then
    -- a big batch: lava, when there is more than the turtles need (it
    -- saves 8 coal a stack, and coal is what the miners run on)
    local storage, lava = listStorage(), 0
    for _, st in ipairs(storage) do
      if st.name == K.LAVA then lava = lava + st.count end
    end
    if lava > K.LAVA_KEEP then
      for _, st in ipairs(storage) do
        if st.name == K.LAVA and (peripheral.call(st.inv, "pushItems", f, st.slot, 1, 2) or 0) > 0 then
          fuelHave = 13
          break
        end
      end
    end
  end
  if fuelHave < fuelNeeded then
    local want = fuelNeeded - fuelHave
    local all = listStorage()
    local coalLeft = false                -- (wood only when there is no coal or charcoal)
    for _, st in ipairs(all) do
      if st.name == "minecraft:coal" or st.name == "minecraft:charcoal" then coalLeft = true end
    end
    for _, st in ipairs(all) do
      if want <= 0 then break end
      local wood = st.name:find("_log", 1, true) ~= nil
      if wood then
        local have = 0
        for _, o in ipairs(all) do if o.name == st.name then have = have + o.count end end
        if have <= K.LOGS_KEPT and st.name ~= "regions_unexplored:bamboo_log" then st = { name = "" } end
      end
      if matches("#fuel", st.name) and not (wood and coalLeft) and input ~= st.name
        and (not fuelSlot or fuelSlot.name == st.name) then
        local per = wood and 5 or 1         -- a log cooks 1.5 items, a coal 8
        local n = peripheral.call(st.inv, "pushItems", f, st.slot, math.min(64, want * per), 2) or 0
        want = want - math.floor(n / per)
        if wood and n > 0 then want = 0 end
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
  { fuel = true, leave = K.LOGS_KEPT, input = "regions_unexplored:magnolia_log", output = "minecraft:charcoal", keep = 4000 },
  { fuel = true, leave = K.LOGS_KEPT, input = "regions_unexplored:mauve_log", output = "minecraft:charcoal", keep = 4000 },
  { fuel = true, leave = K.LOGS_KEPT, input = "minecraft:oak_log", output = "minecraft:charcoal", keep = 4000 },
  { fuel = true, leave = K.LOGS_KEPT, input = "minecraft:birch_log", output = "minecraft:charcoal", keep = 4000 },
  { fuel = true, leave = K.LOGS_KEPT, input = "minecraft:spruce_log", output = "minecraft:charcoal", keep = 4000 },
  { fuel = true, leave = K.LOGS_KEPT, input = "minecraft:jungle_log", output = "minecraft:charcoal", keep = 4000 },
  { fuel = true, leave = K.LOGS_KEPT, input = "minecraft:dark_oak_log", output = "minecraft:charcoal", keep = 4000 },
  { fuel = true, leave = K.LOGS_KEPT, input = "minecraft:acacia_log", output = "minecraft:charcoal", keep = 4000 },
  { fuel = true, leave = K.LOGS_KEPT, input = "minecraft:cherry_log", output = "minecraft:charcoal", keep = 4000 },
  { fuel = true, leave = K.LOGS_KEPT, input = "regions_unexplored:redwood_log", output = "minecraft:charcoal", keep = 4000 },
  { fuel = true, leave = 0, input = "regions_unexplored:bamboo_log", output = "minecraft:charcoal", keep = 4000 },
  { input = "minecraft:cobblestone", output = "minecraft:stone", keep = 1600 },
  { input = "minecraft:raw_copper", output = "minecraft:copper_ingot", keep = 400 },
  { input = "minecraft:stone_bricks", output = "minecraft:cracked_stone_bricks", keep = 180 },
  -- for the fit-out: glass for the windows, iron for bars and lanterns,
  -- gold for the monitors
  { leave = 64, input = "minecraft:sand", output = "minecraft:glass", keep = 400 },
  { leave = 64, input = "minecraft:raw_iron", output = "minecraft:iron_ingot", keep = 200 },
  { leave = 64, input = "minecraft:raw_gold", output = "minecraft:gold_ingot", keep = 160 },
}

---------------------------------------------------------------- the foundry
-- The Mekanism line in the foundry bay is worked by a helper (foundry.lua).
-- Once it says its Enrichment Chamber and Energized Smelter are set up, raw
-- ore goes to it a batch at a time rather than into the furnaces: three raw
-- make four ingots there. Each job costs about one redstone dust of power,
-- so this only runs while there is redstone to spare; without it, or if the
-- foundry stops answering, the furnaces carry on as before.
K.REDSTONE = "minecraft:redstone"
local FOUNDRY_ORES = {      -- keep = ingots wanted; leave = raw ore kept back
  { raw = "minecraft:raw_iron", out = "minecraft:iron_ingot", keep = 600, leave = 64 },
  { raw = "minecraft:raw_gold", out = "minecraft:gold_ingot", keep = 320, leave = 64 },
  { raw = "minecraft:raw_copper", out = "minecraft:copper_ingot", keep = 600, leave = 0 },
  { raw = "alltheores:raw_osmium", out = "alltheores:osmium_ingot", keep = 200, leave = 0 },
}
K.FOUNDRY_BATCH = 48    -- raw ore a job (64 ingots: one stack out of the smelter)
K.FOUNDRY_DUST  = 100   -- redstone dust a batch takes with it (80 jobs, and a little)
K.FOUNDRY_KEEP  = 128   -- redstone dust never sent to the foundry (crafting needs it)
local foundryHello = nil    -- when the operator was last called for
-- With power laid on (a heat generator and cable: job=power) the machines
-- need no redstone. The operator says how much fuel the generator has left;
-- below FOUNDRY_FUEL_LOW it is sent a fuel job, while the factory has coal
-- to spare (FOUNDRY_FUEL_SPARE: coal and charcoal together).
K.FOUNDRY_FUEL_LOW   = 16
K.FOUNDRY_FUEL_SPARE = 160

local function foundryPowered()
  local p = plots.foundry and plots.foundry.power
  return type(p) == "table" and p.ok == true
end

local function foundryUp()
  local fy = plots.foundry
  return fy ~= nil and fy.op ~= nil and type(fy.machines) == "table"
    and fy.machines.chamber and fy.machines.smelter and (fy.fails or 0) < 3 or false
end

-- This raw ore is the foundry's just now (the furnaces leave it alone).
local function foundryOre(stock, raw)
  if not foundryUp() then return nil end
  -- (on the cable a batch takes a little dust in case the power fails)
  if (stock[K.REDSTONE] or 0) < K.FOUNDRY_KEEP + (foundryPowered() and 16 or K.FOUNDRY_DUST) then return nil end
  for _, o in ipairs(FOUNDRY_ORES) do
    if o.raw == raw then return o end
  end
end

local function foundrySend(fy)
  local job = fy.job
  rednet.send(fy.op, { type = "foundry_job", n = job.n, forId = fy.op,
    job = { kind = job.kind, item = job.item, n = job.count } }, K.JOB_PROTOCOL)
end

-- Raise a job when there is ore and redstone for one and none is out; ask
-- again if the operator has not answered; give up on one that never ends.
local function foundryDuty(stock)
  local fy = plots.foundry
  if not fy then
    fy = {}
    plots.foundry = fy
  end
  local now = os.epoch("utc")
  local job = fy.job
  if job then
    if now - job.since > (job.acked and 3600000 or 1200000) then
      print(job.acked and "The foundry never finished its job: dropped." or "Nobody at the foundry: job dropped.")
      fy.job, fy.fails, fy.failedAt = nil, (fy.fails or 0) + 1, now
      saveTable(K.PLOTS_FILE, plots)
    elseif now - job.asked > (job.acked and 900000 or 120000) then
      -- (not heard: asked again. One that is done already says so again.)
      job.asked = now
      foundrySend(fy)
    end
    return
  end
  if not fy.op then
    if not foundryHello or now - foundryHello > 300000 then
      foundryHello = now
      rednet.broadcast({ type = "foundry_hello" }, K.JOB_PROTOCOL)
    end
    return
  end
  if (fy.fails or 0) >= 3 and now - (fy.failedAt or 0) > 3 * 3600000 then
    fy.fails = 0                           -- (another go, a few hours on)
  end
  if now - (fy.failedAt or 0) < 600000 or now - (fy.doneAt or 0) < 30000 then return end
  if next(orders) ~= nil then return end   -- a load is being made up: not now
  for _, o in ipairs(FOUNDRY_ORES) do
    if foundryOre(stock, o.raw) and (stock[o.raw] or 0) >= o.leave + K.FOUNDRY_BATCH
      and (stock[o.out] or 0) < o.keep then
      fy.seq = (fy.seq or 0) % 1000 + 1
      fy.job = { n = now % 1000000 * 1000 + fy.seq, kind = "ore", item = o.raw, count = K.FOUNDRY_BATCH,
        since = now, asked = now }
      saveTable(K.PLOTS_FILE, plots)
      print(("To the foundry: %d %s."):format(K.FOUNDRY_BATCH, shortName(o.raw)))
      foundrySend(fy)
      return
    end
  end
  -- the generator running low, and no ore going over to bring fuel with it
  local p = fy.power
  if foundryPowered() and (tonumber(p.fuel) or K.FOUNDRY_FUEL_LOW) < K.FOUNDRY_FUEL_LOW
    and now - (fy.fuelAt or 0) > 600000
    and (stock["minecraft:coal"] or 0) + (stock["minecraft:charcoal"] or 0) >= K.FOUNDRY_FUEL_SPARE then
    fy.seq = (fy.seq or 0) % 1000 + 1
    fy.fuelAt = now
    fy.job = { n = now % 1000000 * 1000 + fy.seq, kind = "fuel", count = 64, since = now, asked = now }
    saveTable(K.PLOTS_FILE, plots)
    print("Fuel to the foundry's generator.")
    foundrySend(fy)
  end
end

-- word from the operator (from the responder)
local function foundryHeard(id, msg)
  local fy = plots.foundry
  if not fy then
    fy = {}
    plots.foundry = fy
  end
  if msg.type == "foundry_ready" then
    fy.op = id
    fy.machines = type(msg.machines) == "table" and msg.machines or {}
    fy.power = type(msg.power) == "table" and msg.power or nil
    saveTable(K.PLOTS_FILE, plots)
    return
  end
  local job = fy.job
  if not job or id ~= fy.op or msg.n ~= job.n then return end
  if msg.type == "foundry_ack" then
    job.acked = true
  elseif msg.type == "foundry_done" then
    local now = os.epoch("utc")
    fy.job, fy.doneAt = nil, now
    local made = {}
    for name, n in pairs(type(msg.made) == "table" and msg.made or {}) do
      made[#made + 1] = n .. " " .. shortName(name)
    end
    if msg.ok then
      fy.fails = 0
      print("The foundry made " .. (made[1] and table.concat(made, ", ") or "nothing") .. ".")
    else
      fy.fails, fy.failedAt = (fy.fails or 0) + 1, now
      print("The foundry: " .. tostring(msg.why or "job failed") .. ".")
    end
    fy.last = { item = job.item, ok = msg.ok and true or false, why = msg.why, made = table.concat(made, ", ") }
  end
  saveTable(K.PLOTS_FILE, plots)
end

local function keepFurnacesBusy(stock)
  local busy = next(orders) ~= nil         -- a builder load is being made: only fuel is cooked
  -- cooking ahead is a luxury: not when coal is short
  local shortOfCoal = (stock["minecraft:coal"] or 0) + (stock["minecraft:charcoal"] or 0) < K.FUEL_RESERVE + 144
  for _, f in ipairs(furnaces) do
    local okList, items = pcall(furnaceList, f)
    if okList and not items[1] then
      for _, job in ipairs(BACKGROUND) do
        local have = stock[job.output] or 0
        local raw = stock[job.input] or 0
        local minRaw = job.input == "minecraft:stone_bricks" and 128 or (job.fuel and 3 or 16)
        -- leave = raw kept back for building turtles
        -- (logs become charcoal only when coal is short: lava is the main
        -- fuel now, and wood is wanted for chests, ladders and new turtles)
        local wanted
        if job.fuel then wanted = shortOfCoal else wanted = not (shortOfCoal or busy) end
        if wanted and have < job.keep and not foundryOre(stock, job.input)
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
  local input = recipeFor(name).smelt
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
    local h = fs.open(K.STAGE_FILE, "w")
    h.write(stage)
    h.close()
  else
    fs.delete(K.STAGE_FILE)
  end
end

local function getStage()
  if not fs.exists(K.STAGE_FILE) then return nil end
  local h = fs.open(K.STAGE_FILE, "r")
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
  if not (pull(K.TURTLE, 1, 1) and pull(K.MODEM, 1, 2)) then
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
    -- [pickaxe][turtle] : the tool goes on the turtle's left side (a chunk
    -- loader gets a Chunk Controller there instead)
    local tool = plots.makingLoader and K.CHUNKY or K.PICKAXE
    if not (pull(tool, 1, 1) and pull(K.TURTLE, 1, 2)) then
      error("Parts went missing before assembly.", 0)
    end
    turtle.select(16)
    local ok, err = turtle.craft()
    if not ok then error("Could not fit the " .. shortName(tool) .. ": " .. tostring(err), 0) end
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
    -- (a chunk loader may be given a plain wireless modem: plots.loaderModem)
    local modem = plots.makingLoader and plots.loaderModem or K.MODEM
    if not pull(modem, 1, 2) then error("The " .. shortName(modem) .. " went missing.", 0) end
    turtle.select(16)
    local ok, err = turtle.craft()
    if not ok then error("Could not fit the " .. shortName(modem) .. ": " .. tostring(err), 0) end
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
  for t = K.COUNTER and 0 or 1, 3 do          -- (the counter has no chest in front: look there too)
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
  saveTable(K.BASE_FILE, base)
  print(("Base mapped. I am at %d, %d, %d."):format(f.x, f.y, f.z))
  return base
end

-- Make sure the floppy disk will set up new turtles.
local function prepareDisk()
  -- (the drive with a disk in it: the second pad's drive is empty)
  local drive = peripheral.find("drive", function(_, d) return d.isDiskPresent() end)
    or peripheral.find("drive")
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
  if before == 0 then return false, 0, "none" end
  turtle.select(slot)
  if dir == "up" then turtle.dropUp() else turtle.drop() end
  local moved = before - turtle.getItemCount(slot)
  stashSlot(slot)
  turtle.select(1)
  -- had it in hand and the other turtle took none: its inventory is full
  -- (not the same thing as having none, which is what it used to be told)
  return moved > 0, moved, moved == 0 and "full" or nil
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
  if recipe.tool then return false end      -- (one tool in the grid: one craft at a time)
  for _, item in pairs(recipe.key) do
    if item:sub(1, 1) == "#" or item:sub(1, 1) == "@" then return false end
    -- something made of wood (a chest going into an iron chest): two of
    -- different woods do not stack in one grid slot
    local made = RECIPES[item]
    if made and made.grid then
      local planks, slabs = woodNeeds(made)
      if planks + slabs > 0 then return false end
    end
  end
  return true
end

-- A recipe that takes "the logs of one wood": the same recipe with the one
-- kind of log there is most of (plain or stripped), and how many there are.
local function withLog(recipe)
  local group, letter
  for k, item in pairs(recipe.key) do
    if item:sub(1, 5) == "@log:" then group, letter = item, k end
  end
  if not group then return recipe, math.huge end
  local best, most = nil, 0
  for name, count in pairs(stockTotals()) do
    if matches(group, name) and (count > most or (count == most and best and name < best)) then
      best, most = name, count
    end
  end
  if not best then return nil, 0, group end
  local key = {}
  for k, item in pairs(recipe.key) do key[k] = item end
  key[letter] = best
  return { yield = recipe.yield, grid = recipe.grid, key = key, wood = recipe.wood }, most
end

local function craftBatch(name, k, recipe)
  recipe = recipe or recipeFor(name)
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
    if recipe.wood and tostring(err):find("No matching") then markBadWood(recipe.wood) end
    error("The recipe for " .. shortName(name) .. " did not work: " .. tostring(err), 0)
  end
  checkWood(name, recipe)
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
    local recipe = step.recipe or recipeFor(step.name)
    if recipe.smelt then
      print("Smelting " .. step.batches .. " " .. shortName(recipe.smelt))
      smelt(step.name, step.batches)
    else
      if step.wood then
        recipe = ofWood(recipe, step.wood)             -- all of one wood
        print("Crafting " .. shortName(step.name) .. " in " .. shortName(step.wood))
      else
        print("Crafting " .. shortName(step.name))
      end
      local left = step.batches
      while left > 0 do
        local now, most, short = withLog(recipe)
        if not now then
          error("Ran out of " .. shortName(short) .. " while making " .. shortName(step.name) .. ".", 0)
        end
        local bulk = canBulk(now)
        local k = bulk and math.max(1, math.min(left, most, math.floor(64 / (recipe.yield or 1)))) or 1
        if bulk then craftBatch(step.name, k, now) else craftOnce(step.name, now) end
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

-- Chunk Controllers in stock beyond those the chunk loaders still to be
-- built will need: these can go to turtles that carry their own. A loader
-- needs an ender modem, so no more are kept back than there are modems to
-- be had (in stock, or as an ender eye, or a pearl and blaze, with 8 gold).
local function spareControllers(stock)
  stock = stock or lastStock or {}
  local n = function(name) return stock[name] or 0 end
  local eyes = n("minecraft:ender_eye")
    + math.min(n("minecraft:ender_pearl"), n("minecraft:blaze_powder") + 2 * n("minecraft:blaze_rod"))
  local gold = n("minecraft:gold_ingot") + n("minecraft:raw_gold")
  local modems = n(K.MODEM) + math.min(eyes, math.floor(gold / 8))
  local forLoaders = plots.noLoaders and 0
    or math.max(0, math.min(LOADERS - #(plots.loaders or {}), modems))
  return math.max(0, n(K.CHUNKY) - forLoaders)
end

-- One controller to the turtle that asked for it (and to no other), standing
-- on top of me or on the pad.
local function giveController(dir, id)
  if not ctlQueue[id] or spareControllers(stockTotals()) < 1 then return false end
  if not giveTo(dir, K.CHUNKY, 1) then return false end
  local key = tostring(id)
  plots.ctlGiven = plots.ctlGiven or {}
  plots.ctlGiven[key] = (plots.ctlGiven[key] or 0) + 1
  saveTable(K.PLOTS_FILE, plots)
  ctlQueue[id] = nil
  print("Gave a Chunk Controller to turtle " .. key .. " to carry.")
  return true
end

-- Serve miners waiting for things: on top of me (the usual service stop) or
-- on the launch pad (where they wait if they cannot carry on). Coal for the
-- empty, buckets for those without one. With no coal at all, the Geo Scanner
-- goes to the first miner that asks, so it can hunt for coal.
-- canCraft = false while I am holding a finished miner.
local function serveRequests(canCraft)
  -- (a controller is handed to a builder's mate with its load; here only to
  -- a turtle that has just asked, waiting on top of me)
  local ctlNow = false
  for id, at in pairs(ctlQueue) do
    if os.clock() - at > 1800 then ctlQueue[id] = nil
    elseif os.clock() - at < 30 then ctlNow = true end
  end
  if not next(fuelQueue) and not next(bucketQueue) and not next(emptiesQueue)
    and not next(scannerQueue) and not ctlNow then return end
  local wantEmpties = 0
  for _, n in pairs(emptiesQueue) do wantEmpties = math.max(wantEmpties, n) end
  if canCraft and wantEmpties > 0 then pcall(ensureStock, K.BUCKET, wantEmpties) end
  if canCraft and next(bucketQueue) then
    pcall(ensureStock, K.BUCKET, 1)
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
        local stock = stockTotals()
        local coal = countIn(stock, "#fuel")
        local share = math.max(8, math.min(64, math.floor((coal - K.FUEL_RESERVE) * 0.05)))
        if (stock[K.LAVA] or 0) > K.LAVA_KEEP and giveTo(dir, K.LAVA, 1) then
          -- lava first, when there is some to spare: 1,000 moves a bucket,
          -- and the miners bring it home themselves
          print("Gave a lava bucket to a miner.")
        elseif giveTo(dir, "#fuel", share) then
          print("Gave " .. share .. " coal to a miner.")
        else
          print("A miner needs fuel but I have no coal.")
          report("out of coal")
          if not plots.hunter and giveTo(dir, K.SCANNER, 1) then
            plots.hunter = true
            saveTable(K.PLOTS_FILE, plots)
            print("Gave it the Geo Scanner to hunt for coal.")
          end
        end
      end
      if next(bucketQueue) and giveTo(dir, K.BUCKET, 1) then
        print("Gave a bucket to a miner.")
      end
      if next(scannerQueue) and giveTo(dir, K.SCANNER, 1) then
        print("Gave a Geo Scanner to a new hunter.")
        scannerQueue = {}
      end
      if ctlNow then
        local okId, here = pcall(peripheral.call, side, "getID")
        if okId and here then giveController(dir, here) end
      end
      if wantEmpties > 0 then
        local ok, moved = giveTo(dir, K.BUCKET, wantEmpties)
        if ok then
          print("Gave " .. tostring(moved) .. " empty buckets to the lava runner.")
          wantEmpties = 0
        end
      end
    end
  end
  fuelQueue, bucketQueue, emptiesQueue, scannerQueue = {}, {}, {}, {}
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
    if want > 0 and recipeFor(name) or countIn(stock, name) > 0 then
      local lo, hi = 0, want
      while lo < hi do                       -- largest count that still plans
        local mid = math.floor((lo + hi + 1) / 2)
        lines[#lines + 1] = { name, mid }
        local ok = planLoad(lines, stock)
        lines[#lines] = nil
        if ok then lo = mid else hi = mid - 1 end
      end
      if lo > 0 then lines[#lines + 1] = { name, lo } end
      if lo == 0 then
        lines[#lines + 1] = { name, 1 }
        local _, why = planLoad(lines, stock)
        lines[#lines] = nil
        local parts = {}
        for k, v in pairs(why or {}) do parts[#parts + 1] = tostring(v) .. " " .. shortName(k) end
        print("Cannot make " .. shortName(name) .. ": short of " .. table.concat(parts, ", "))
      end
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

-- The loading bays (docs/factory-retrofit.md 6b): a helper docked in its rack
-- home is an inventory on the cable (turtle_<id>), so its load and fuel go
-- straight from storage into it, and its hand-ins come straight back.
-- Up to count of an item (or group) from storage into target; returns how many.
function K.pushTo(target, wanted, count)
  local need = count
  for _, s in ipairs(listStorage()) do
    if need <= 0 then break end
    if matches(wanted, s.name) then
      local ok, moved = pcall(peripheral.call, s.inv, "pushItems", target, s.slot, need)
      need = need - (ok and tonumber(moved) or 0)
    end
  end
  return count - need
end

-- Everything in one slot of target back into storage.
function K.pullBack(target, slot)
  local got = 0
  for _, inv in ipairs(stores) do
    local ok, moved = pcall(peripheral.call, inv, "pullItems", target, slot)
    got = got + (ok and tonumber(moved) or 0)
  end
  return got
end

-- Hand a ready order to a helper docked in its bay. False (and a note) if
-- it is not on the cable (yet).
function K.deliverBay(id, order)
  local bay = order.bay
  if not (modem and type(bay) == "string" and peripheral.isPresent(bay)) then
    order.bayNote = "not on the cable"
    return false
  end
  local okId, who = pcall(peripheral.call, bay, "getID")
  if okId and tonumber(who) and tonumber(who) ~= id then
    order.bayNote = bay .. " is turtle " .. tostring(who)
    return false
  end
  orders[id] = nil
  K.adopted[id] = nil
  local back = 0
  for _, slot in ipairs(type(order.back) == "table" and order.back or {}) do
    if tonumber(slot) then back = back + K.pullBack(bay, math.floor(tonumber(slot))) end
  end
  local given, missing, full = {}, {}, {}
  local stock = stockTotals()
  for _, l in ipairs(order.lines or {}) do
    local name, want = l[1], l[2]
    local got = K.pushTo(bay, name, want)
    given[name] = (given[name] or 0) + got
    if got < want and countIn(stock, name) >= want then full[#full + 1] = name end
  end
  for _, line in ipairs(order.items) do
    local name, want = line[1], math.floor(tonumber(line[2]) or 0)
    if (given[name] or 0) < want then missing[name] = want - (given[name] or 0) end
  end
  if (order.fuel or 0) > 0 then
    stock = stockTotals()
    local want = order.fuel * 80
    local buckets = math.min(stock[K.LAVA] or 0, 4, math.floor(want / 1000 + 0.5))
    want = want - 1000 * K.pushTo(bay, K.LAVA, buckets)
    local coal = math.ceil(math.max(0, want) / 80)
    if coal > 0 then
      K.pushTo(bay, "#fuel", math.min(64, coal, math.max(8, math.floor(countIn(stock, "#fuel") * 0.4))))
    end
  end
  if ctlQueue[id] and spareControllers(stockTotals()) >= 1 and K.pushTo(bay, K.CHUNKY, 1) == 1 then
    local key = tostring(id)
    plots.ctlGiven = plots.ctlGiven or {}
    plots.ctlGiven[key] = (plots.ctlGiven[key] or 0) + 1
    saveTable(K.PLOTS_FILE, plots)
    ctlQueue[id] = nil
  end
  rednet.send(id, { type = "materials_ready", forId = id, n = order.n, given = given, missing = missing,
    full = full, bay = true }, K.JOB_PROTOCOL)
  local parts = {}
  for _, l in ipairs(order.lines or {}) do parts[#parts + 1] = shortName(l[1]) .. " " .. (given[l[1]] or 0) .. "/" .. l[2] end
  print("Load for " .. tostring(id) .. " into its bay (" .. bay .. "): " .. table.concat(parts, ", ")
    .. (back > 0 and ("; " .. back .. " taken back") or ""))
  report("load handed over")
  return true
end

local function serveOrders(onlyReady)
  -- onlyReady: just hand a finished load to the turtle on the pad (safe with
  -- a new turtle in hand: nothing is stashed or crafted)
  -- a builder already on the pad with its load made goes first
  local waiting = false
  for _, o in pairs(orders) do if o.ready then waiting = true end end
  if waiting then
    turnTo(base.padTurns)
    local here = peripheral.hasType("front", "turtle") and frontId()
    if not (here and orders[here] and orders[here].ready) then waiting = false end
    turnTo(0)
  end
  -- small loads first: a mate after one axe should not wait behind a
  -- whole machine line being crafted
  local queue = {}
  for id, order in pairs(orders) do queue[#queue + 1] = { id = id, order = order } end
  local function size(o)
    local n = 0
    for _, l in ipairs(o.items or {}) do n = n + (tonumber(l[2]) or 0) end
    return n
  end
  table.sort(queue, function(p, q) return size(p.order) < size(q.order) end)
  for _, entry in ipairs(queue) do
    local id, order = entry.id, entry.order
    if not waiting and not order.ready and not onlyReady then
      served[id] = order.n
      print("Preparing a load for the builder.")
      report("preparing materials")
      stashAll()
      local lines, steps = fitLoad(order.items)
      -- one step failing (no coal for a smelt, say) must not cost the rest
      -- of the load
      for _, step in ipairs(steps) do
        local okRun, err = pcall(runSteps, { step })
        if not okRun then print("Problem: " .. tostring(err)) end
      end
      order.lines, order.ready, order.told = lines, true, os.clock()
      order.readyAt = os.clock()
      if order.bay then
        if K.deliverBay(id, order) then return true end
        order.tried = os.clock()
        print("Load ready for " .. tostring(id) .. "; its bay: " .. tostring(order.bayNote))
        return true
      end
      rednet.send(id, { type = "load_ready", forId = id, n = order.n, pad = base.pad, at = base.f }, K.JOB_PROTOCOL)
      if K.COUNTER then          -- (Crafty takes it over if it is not collected)
        rednet.broadcast({ type = "counter_ready", forId = id, n = order.n }, K.JOB_PROTOCOL)
      end
      print("Load ready. Waiting for the builder.")
      return true
    end
  end
  -- a load for a bay whose helper was not docked yet: try again
  for id, o in pairs(orders) do
    if o.ready and o.bay and os.clock() - (o.tried or 0) > 15 then
      o.tried = os.clock()
      if K.deliverBay(id, o) then return true end
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
        if o.ready and not o.bay and os.clock() - (o.told or 0) > 60 then        -- remind it
          o.told = os.clock()
          rednet.send(id, { type = "load_ready", forId = id, n = o.n, pad = base.pad, at = base.f }, K.JOB_PROTOCOL)
        end
      end
      return false
    end
    local id = here
    orders[id] = nil
    K.adopted[id] = nil
    if K.COUNTER then rednet.broadcast({ type = "counter_handed", forId = id, n = order.n }, K.JOB_PROTOCOL) end
    local given, missing, full = {}, {}, {}
    for _, l in ipairs(order.lines) do
      local name, want = l[1], l[2]
      local got = 0
      while got < want do
        local ok, moved, why = giveTo("front", name, math.min(64, want - got))
        if not ok then
          if why == "full" then
            full[#full + 1] = name
            print("The builder has no room for " .. shortName(name) .. ".")
          end
          break
        end
        got = got + moved
      end
      given[name] = got
    end
    do
      local parts = {}
      for _, l in ipairs(order.lines) do parts[#parts + 1] = shortName(l[1]) .. " " .. (given[l[1]] or 0) .. "/" .. l[2] end
      local asked = {}
      for _, l in ipairs(order.items) do asked[#asked + 1] = shortName(tostring(l[1])) .. " " .. tostring(l[2]) end
      print("Load for " .. tostring(id) .. ": asked " .. table.concat(asked, ", ") .. "; gave " .. table.concat(parts, ", "))
    end
    for _, line in ipairs(order.items) do
      local name, want = line[1], math.floor(tonumber(line[2]) or 0)
      if (given[name] or 0) < want then missing[name] = want - (given[name] or 0) end
    end
    if order.fuel > 0 then
      -- lava first (a bucket is 1,000 moves, about 12 coal), coal for the rest
      local stock = stockTotals()
      local want = order.fuel * 80
      local buckets = math.min(stock[K.LAVA] or 0, 4, math.floor(want / 1000 + 0.5))
      for _ = 1, buckets do
        if giveTo("front", K.LAVA, 1) then want = want - 1000 end
      end
      local coal = math.ceil(math.max(0, want) / 80)
      if coal > 0 then
        -- when fuel is short nobody gets more than a share of what there is
        local have = countIn(stock, "#fuel")
        giveTo("front", "#fuel", math.min(64, coal, math.max(8, math.floor(have * 0.4))))
      end
    end
    giveController("front", id)       -- (if it asked for one to carry)
    turnTo(0)
    rednet.send(id, { type = "materials_ready", forId = id, n = order.n,
      given = given, missing = missing, full = full }, K.JOB_PROTOCOL)
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
    if busy and next(bucketQueue) and giveToFront(K.BUCKET, 1) then
      bucketQueue = {}
      print("Gave a bucket to a miner.")
    end
    -- a builder's mate that came down for its load while the new turtle was
    -- being made: give it the load, or both wait for ever
    if busy and next(orders) then
      serveOrders(true)
      turnTo(base.padTurns)
    end
    if not busy and coal >= K.NEWBORN_COAL then break end
    if waited % 6 == 0 then
      if busy then
        print("Launch pad is busy, waiting...")
        report(coal > 0 and "launch pad busy" or "out of coal")
      else
        print("Waiting for " .. K.NEWBORN_COAL .. " coal to fuel the new miner...")
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
  fuelTurtleInFront(K.NEWBORN_COAL, true)
  if isBuilder then
    giveToFront(K.SCANNER, 1, true)   -- for mapping
    giveToFront(K.CORE, 1, true)      -- for later: lets it right-click things
    for _ = 1, 10 do
      local okId, id = pcall(peripheral.call, "front", "getID")
      if okId and id then
        plots.builderId = id
        saveTable(K.PLOTS_FILE, plots)
        break
      end
      sleep(0.5)
    end
  elseif plots.makingLoader then
    -- a chunk loader: note which turtle it is, so it gets that job
    for _ = 1, 10 do
      local okId, id = pcall(peripheral.call, "front", "getID")
      if okId and id then
        plots.loaders = plots.loaders or {}
        plots.loaders[#plots.loaders + 1] = id
        print("That one is a chunk loader.")
        break
      end
      sleep(0.5)
    end
    plots.makingLoader, plots.loaderModem = nil, nil
    saveTable(K.PLOTS_FILE, plots)
  else
    giveToFront(K.BUCKET, 1, true)    -- for scooping lava as fuel
    if launchingHelper then
      -- a builder's mate: note which turtle it is, so it gets that job
      for _ = 1, 10 do
        local okId, id = pcall(peripheral.call, "front", "getID")
        if okId and id then
          plots.helpers = plots.helpers or {}
          plots.helpers[#plots.helpers + 1] = id
          saveTable(K.PLOTS_FILE, plots)
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
  local o = plots.origin or base.f            -- (where the grid was first laid out)
  for r = 0, 80 do
    for gx = -r, r do
      for gz = -r, r do
        if math.max(math.abs(gx), math.abs(gz)) == r then
          local x0 = o.x + gx * K.PLOT_SIZE
          local z0 = o.z + gz * K.PLOT_SIZE
          local clear = o.x < x0 - K.KEEP_OUT
            or o.x > x0 + K.PLOT_SIZE - 1 + K.KEEP_OUT
            or o.z < z0 - K.KEEP_OUT
            or o.z > z0 + K.PLOT_SIZE - 1 + K.KEEP_OUT
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
  for n, lid in ipairs(plots.loaders or {}) do
    if tostring(lid) == key then
      if pending > 0 then pending = pending - 1 end
      return { type = "role", role = "loader", forId = id, base = base, name = LOADER_NAMES[n] or ("Loader" .. n) }
    end
  end
  local index = plots.byId[key]
  if not index then
    -- no new plots while the storage is nearly full: what they dig has
    -- nowhere to go (they wait, and are given one when room comes back)
    local room = storageSpace()
    if room and room.slots > 0 and room.free < math.max(16, room.slots * K.MINE_ROOM) then
      if not plots.noRoomSaid then
        print("Storage nearly full: no new plots until there is room.")
        plots.noRoomSaid = true
      end
      return nil
    end
    plots.noRoomSaid = nil
    local returning = plots.between and plots.between[key]
    if returning then
      plots.between[key] = nil
    elseif activeCount() >= K.MAX_MINERS and pending == 0 then
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
    saveTable(K.PLOTS_FILE, plots)
  end
  local x0, z0 = plotOrigin(index)
  return {
    type = "job", forId = id, index = index,
    x0 = x0, z0 = z0, size = K.PLOT_SIZE,
    topY = math.min(K.TOP_Y_MAX, base.f.y - 10), bottom = K.BOTTOM_Y,
    cruise = base.f.y + K.CRUISE_UP + ((index - 1) % 40),
    dock = base.dock, exit1 = base.exit1, exit2 = base.exit2,
    origin = plots.origin,
  }
end

---------------------------------------------------------------- pairing chunk loaders
-- What every turtle last said in its status reports. From this the factory
-- pairs chunk loaders with the turtles that need one: a loader parked at
-- the base asks every minute (escort_request), and is sent out with the
-- turtle working far away that needs company most. Never the last loader
-- at the base. And a turtle too low on fuel to fetch its own (feed_request)
-- has a builder's mate with nothing to do sent to it with coal.
-- Both go out as direct orders (see swarm.accept).
local fleet = {}          -- name (see nameKey) -> what it last said
local escortGiven = {}    -- turtle (nameKey) -> { loader = id, at = clock }
local escortRest = {}     -- turtle -> not offered again before this (a loader found nothing there)
local feedSent = {}       -- who asked (id) -> when a mate was last sent
K.ESCORT_FAR = 64     -- blocks from the factory (either way) beyond which a turtle is "far"
K.ESCORTS_OUT = 3     -- at most this many loaders out with turtles at once (each trip burns fuel)
K.SILENT = 240        -- seconds without a word: far away, that is a turtle frozen in an unloaded chunk
local RESTING = { done = true, parked = true, idle = true, stopped = true, paused = true,
  ["waiting for a plot"] = true, ["stopped by player"] = true }

-- What a name is filed under: the same for a turtle's old name and its new
-- one (the swarm was renamed; see swarm.lua), in any case.
local function nameKey(name)
  if swarm and swarm.nameKey then return swarm.nameKey(name) end
  return tostring(name):lower()
end

local function noteStatus(id, msg)
  if type(msg) ~= "table" or type(msg.label) ~= "string" or msg.role == "factory" then return end
  local key = nameKey(msg.label)
  local old = fleet[key] or {}
  -- (one machine, one entry: whatever name it reported under before)
  for k, u in pairs(fleet) do
    if u.id == id and k ~= key then
      if not fleet[key] then old = u end
      fleet[k] = nil
    end
  end
  local p = type(msg.pos) == "table" and msg.pos or {}
  local x, y, z = tonumber(p.x), tonumber(p.y), tonumber(p.z)
  if not x or not z or (x == 0 and z == 0) then x, y, z = old.x, old.y, old.z end   -- (0, 0 = not known)
  local job = type(msg.job) == "table" and msg.job or {}
  local loader = msg.role == "loader"
  local state = tostring(msg.state)
  fleet[key] = { id = id, label = msg.label, role = msg.role, state = state,
    since = (old.state == state and old.since) or os.clock(),
    x = x, y = y, z = z, at = os.clock(), fuel = tonumber(msg.fuel), chunky = msg.chunky,
    mode = loader and job.mode or nil,
    who = loader and type(job.who) == "string" and nameKey(job.who) or nil }
end

local function isFar(u)
  return u.x ~= nil and base ~= nil and (math.abs(u.x - base.f.x) > K.ESCORT_FAR
    or math.abs(u.z - base.f.z) > K.ESCORT_FAR)
end

local directSeq = 0
local function direct(id, order)
  directSeq = directSeq + 1
  order.direct, order.forId = true, id
  order.nonce = tostring(os.epoch("utc")) .. "-" .. directSeq
  rednet.send(id, order, swarm.CMD_PROTOCOL)
end

-- A loader parked at the base asks whether anyone needs it.
local function escortFor(id, msg)
  if not base or not swarm then return end
  local now = os.clock()
  if type(msg.gaveUp) == "string" and not escortRest[nameKey(msg.gaveUp)] then
    escortRest[nameKey(msg.gaveUp)] = now + 3600
  end
  -- another loader must be staying: at the base, heard from in the last
  -- few minutes, and not itself just sent out
  local kept = false
  for _, u in pairs(fleet) do
    if u.role == "loader" and u.id ~= id and (u.state == "parked" or u.state == "needs fuel")
      and now - u.at < 300 and not isFar(u) then
      local sent = false
      for _, g in pairs(escortGiven) do
        if g.loader == u.id and now - g.at < 300 then sent = true end
      end
      if not sent then kept = true end
    end
  end
  if not kept then return end
  -- no more than ESCORTS_OUT out at once
  local out = 0
  for _, u in pairs(fleet) do
    if u.role == "loader" and u.id ~= id and now - u.at < 600
      and (u.mode == "escort" or u.state == "escorting" or isFar(u)) then out = out + 1 end
  end
  if out >= K.ESCORTS_OUT then return end
  local best, bestScore
  for key, u in pairs(fleet) do
    if u.role == "miner" and isFar(u) and not RESTING[u.state]
      and not (escortRest[key] and now < escortRest[key]) then
      local g = escortGiven[key]
      local taken = g ~= nil and now - g.at < 300 and g.loader ~= id
      for _, l in pairs(fleet) do
        if l.role == "loader" and l.id ~= id and l.who == key and now - l.at < 600 then taken = true end
      end
      local silent = now - u.at > K.SILENT
      -- a turtle that carries its own Chunk Controller looks after itself,
      -- unless it has gone quiet all the same
      if not taken and (silent or not u.chunky) then
        local score = (silent and 1000 or 0)
          + math.min(999, math.abs(u.x - base.f.x) + math.abs(u.z - base.f.z)) / 1000
        if not best or score > bestScore then best, bestScore = u, score end
      end
    end
  end
  if not best then return end
  escortGiven[nameKey(best.label)] = { loader = id, at = now }
  print("Chunk loader " .. tostring(msg.label or id) .. " goes out with " .. best.label .. ".")
  direct(id, { cmd = "escort", who = best.label, x = best.x, z = best.z, auto = true })
end

-- Hauling: when the factory's own chests fill up, a builder's mate with
-- nothing to do is given full stacks of what there is plenty of, and drops
-- them into the storage room's Sophisticated Storage controller, which puts
-- them away in its barrels. Switched on by the order "haul Crafty on=1" once
-- the controller stands where HAUL.at says (tools/ctlmove.py puts it there).
local HAUL = {
  at = { x = 11, y = 5, z = 15, face = 2 },   -- standing in the room, the controller to the west
  ox = -4448, oy = 71, oz = 1518, shell = "factory_asfit3", plan = "factory_storeroom",
  below = 0.20,       -- haul while less than this share of the slots is free
  keep = 256,         -- of anything, this much stays at the factory
  stacks = 12,        -- per trip
  every = 300,        -- seconds between trips
}
-- never hauled away: fuel, buckets, and what the turtles and recipes use all the time
local HAUL_NEVER = { "minecraft:coal", "minecraft:charcoal", "minecraft:coal_block", "allthecompressed:coal_block",
  "minecraft:lava_bucket", "minecraft:bucket", "minecraft:redstone", "_ingot", "_log", "_planks",
  "minecraft:glass", "minecraft:sand", "computercraft:", "advancedperipherals:", "mekanism",
  "sophisticatedstorage:", "minecraft:diamond", "minecraft:stick", "minecraft:ender", "minecraft:blaze" }
local haulAt = -1e9

local function haulList(stock)
  local lines, n = {}, 0
  local names = {}
  for name, count in pairs(stock) do
    if count > HAUL.keep + 64 then
      local skip = false
      for _, p in ipairs(HAUL_NEVER) do if name:find(p, 1, true) then skip = true end end
      if not skip then names[#names + 1] = name end
    end
  end
  table.sort(names, function(a, b) return stock[a] > stock[b] end)    -- the biggest piles first
  for _, name in ipairs(names) do
    local k = math.min(HAUL.stacks - n, math.floor((stock[name] - HAUL.keep) / 64))
    if k > 0 then
      lines[#lines + 1] = { name, k * 64 }
      n = n + k
    end
    if n >= HAUL.stacks then break end
  end
  return lines
end

local function haulOps(lines)
  local fetch, drops = {}, {}
  for _, l in ipairs(lines) do
    fetch[#fetch + 1] = l[1] .. "=" .. l[2]
    for _ = 1, l[2] / 64 do drops[#drops + 1] = "drop|" .. l[1] .. "|64" end
  end
  local a = HAUL.at
  return table.concat({ "fetch|" .. table.concat(fetch, ","),
    ("site|%d|%d|%d|%s|%s"):format(HAUL.ox, HAUL.oy, HAUL.oz, HAUL.shell, HAUL.plan),
    ("walk|%d|%d|%d"):format(a.x, a.y, a.z), "face|" .. a.face, "expect|front|controller",
    table.concat(drops, ";"), "leave", "home", "handin|" }, ";")
end

-- The dripstone lava farm (tools/lavafarm.py): a row of cauldrons that fill
-- with lava on their own. Once built, the order "lavafarm Crafty n=<units>
-- how=place|use" tells the factory about it, and while lava runs low it
-- sends a mate with nothing to do round with empty buckets.
local FARM = { x = -4453, y = 76, z = 1538, face = 2, every = 1200, low = 48 }
local farmAt = -1e9

local function lavaFarmDuty(stock)
  local farm = plots.lavafarm
  if not (farm and (farm.n or 0) > 0) or not swarm then return end
  local now = os.clock()
  if now - farmAt < FARM.every or (stock[K.LAVA] or 0) >= FARM.low then return end
  -- (a second farm, the dripstone row: every other round goes there)
  local row = farm.row and not farm.lastRow and farm.row
  local buckets = math.min(row and row.n or farm.n, stock["minecraft:bucket"] or 0, 12)
  if buckets == 0 then return end
  local best
  for _, u in pairs(fleet) do
    -- (a foundry operator between jobs will do; one given a job by hand
    -- in the last few minutes is left to it)
    if u.role == "helper" and (u.state == "idle" or u.state == "foundry: idle") and now - u.at < 200
      and not (farm.skip and farm.skip[u.label])
      and (not best or (u.fuel or 0) > (best.fuel or 0)) then best = u end
  end
  if not best then return end
  farmAt = now
  print(best.label .. " goes round the lava farm with " .. buckets .. " buckets.")
  farm.lastRow = row and true or nil
  local ops
  if row then
    ops = table.concat({ "fetch|minecraft:bucket=" .. buckets,
      ("collect|%d|%d|%d|%d|%d|place"):format(row.x, row.y, row.z, buckets, row.face or 2),
      "inv", "home", "handin|" }, ";")
  elseif farm.how == "hut" then
    -- Kyle's farm along the hut's west wall: cauldrons at x -4467, y 70,
    -- z 1521 on; reached down the pad shaft and along the aisle in front
    local t = { "fetch|minecraft:bucket=" .. buckets, "goto|-4462|80|1521", "down|8",
      "face|2", "fwd|4", "down|2" }
    for i = 1, buckets do
      if i > 1 then t[#t + 1] = "face|1" t[#t + 1] = "fwd|1" end
      t[#t + 1] = "face|2" t[#t + 1] = "place|minecraft:bucket"
    end
    for _, o in ipairs({ "inv", "up|2", "face|3", "fwd|" .. (buckets - 1), "face|0", "fwd|4", "up|8",
      "home", "handin|" }) do t[#t + 1] = o end
    ops = table.concat(t, ";")
  else
    ops = table.concat({
      "fetch|minecraft:bucket=" .. buckets,
      ("collect|%d|%d|%d|%d|%d|%s"):format(FARM.x, FARM.y, FARM.z, farm.n, FARM.face, farm.how or "place"),
      "inv", "home", "handin|" }, ";")
  end
  direct(best.id, { cmd = "lab", clear = true, ops = ops })
end

local function haulDuty(stock)
  if not (plots.haul and plots.haul.on) or not swarm then return end
  local now = os.clock()
  if now - haulAt < HAUL.every then return end
  local room = storageSpace()
  if not room or room.slots == 0 or room.free >= room.slots * HAUL.below then return end
  local best
  for _, u in pairs(fleet) do
    if u.role == "helper" and u.state == "idle" and now - u.at < 200
      and not (plots.haul.skip and plots.haul.skip[u.label])     -- (builders between steps)
      and (not best or (u.fuel or 0) > (best.fuel or 0)) then best = u end
  end
  if not best then return end
  local lines = haulList(stock)
  if #lines == 0 then return end
  haulAt = now
  local what = {}
  for _, l in ipairs(lines) do what[#what + 1] = l[2] .. " " .. l[1]:gsub("^.-:", "") end
  print(best.label .. " hauls to the store: " .. table.concat(what, ", ") .. ".")
  direct(best.id, { cmd = "lab", ops = haulOps(lines), clear = true })
end

-- A turtle too low on fuel to fetch its own: send a builder's mate that is
-- doing nothing (the one with most fuel) with coal, as the order "feed" does.
local function feedFor(id, msg)
  if not swarm then return end
  local now = os.clock()
  local x, y, z = tonumber(msg.x), tonumber(msg.y), tonumber(msg.z)
  if not (x and y and z) or (feedSent[id] and now - feedSent[id] < 600) then return end
  local best
  for _, u in pairs(fleet) do
    if u.role == "helper" and u.state == "idle" and now - u.at < 200 and u.id ~= id
      and (not best or (u.fuel or 0) > (best.fuel or 0)) then best = u end
  end
  if not best then
    print("No builder's mate free to take fuel to " .. tostring(msg.label or id) .. ".")
    return
  end
  feedSent[id] = now
  best.state = "sent with fuel"             -- (not sent twice before it says what it is doing)
  print(best.label .. " takes fuel to " .. tostring(msg.label or id) .. ".")
  direct(best.id, { cmd = "feed", x = math.floor(x), y = math.floor(y), z = math.floor(z) })
end

-- Listens to everyone's status reports (for the pairing above).
-- A helper waiting for a load that never comes (a Counter's load left on a
-- pad nobody landed on, a lost message): its load is announced again, a
-- Counter's is taken over, and if it still waits it is told to reboot.
function K.waiting(state)
  state = tostring(state)
  return state == "waiting for materials" or state == "fetching materials" or state:find("^stuck under") ~= nil
end
function K.adopt(id)
  local f = K.foreign[id]
  if not f then return false end
  K.foreign[id] = nil
  K.adopted[id] = true
  orders[id] = { items = f.items, fuel = f.fuel, n = f.n, bay = f.bay, back = f.back }
  rednet.broadcast({ type = "counter_drop", forId = id, n = f.n }, K.JOB_PROTOCOL)
  print("Taking over turtle " .. tostring(id) .. "'s load from the Counter.")
  return true
end
function K.watchdog(now)
  now = now or os.clock()
  if K.COUNTER then return end
  -- the Counter fallback: ready at a Counter's pad and not collected
  for id, f in pairs(K.foreign) do
    if f.readyAt and now - f.readyAt > K.COUNTER_GIVE_UP then K.adopt(id)
    elseif now - (f.at or now) > 3600 then K.foreign[id] = nil end
  end
  local list = {}
  for key, u in pairs(fleet) do
    if u.role == "helper" and K.waiting(u.state) and now - (u.since or now) > K.STALL_AFTER
        and now - (u.at or 0) < 300 then
      local w = K.stall[key]
      if w and w.since ~= u.since then w = nil end
      if not w then
        w = { step = 1, at = now, since = u.since }
        K.stall[key] = w
        local o = orders[u.id]
        if not o and K.foreign[u.id] then K.adopt(u.id) o = orders[u.id] end
        if o and o.ready and o.bay then o.tried = 0
        elseif o and o.ready then
          o.told = now
          rednet.send(u.id, { type = "load_ready", forId = u.id, n = o.n, pad = base and base.pad, at = base and base.f },
            K.JOB_PROTOCOL)
        end
        print(("%s has been %s for %d min: its load announced again."):format(u.label, u.state,
          math.floor((now - u.since) / 60)))
      elseif w.step == 1 and now - w.at > K.STALL_REBOOT then
        w.step, w.at = 2, now
        if swarm then direct(u.id, { cmd = "reboot" }) end
        print(u.label .. " still waiting: told to reboot.")
      end
      list[#list + 1] = u.label
    else
      K.stall[key] = nil
    end
  end
  table.sort(list)
  K.stalledList = list
end

-- what a drone said, passed on over the cable to the rack's screens
function K.relay(msg)
  if K.COUNTER or not modem or type(msg) ~= "table" then return end
  if msg.role ~= "helper" and msg.role ~= "miner" and msg.role ~= "loader" then return end
  pcall(modem.transmit, K.RACK_CHANNEL, K.RACK_CHANNEL, msg)
end

local function statusListener()
  if not swarm then while true do sleep(3600) end end
  swarm.open()
  local lastWatch = os.clock()
  while true do
    local id, msg = rednet.receive(swarm.PROTOCOL, 30)
    if id then
      noteStatus(id, msg)
      K.relay(msg)
    end
    if os.clock() - lastWatch >= 30 then
      lastWatch = os.clock()
      local ok, err = pcall(K.watchdog)
      if not ok then print("watchdog: " .. tostring(err)) end
    end
  end
end

-- Answers miners. Runs alongside the building work; uses no turtle moves.
local function responder()
  if swarm then swarm.open() end
  while true do
    local id, msg = rednet.receive(K.JOB_PROTOCOL)
    if type(msg) == "table" and id and msg.type == "counter_alive" then
      K.counters[math.floor(tonumber(msg.slot) or 1)] = os.clock()
    elseif type(msg) == "table" and id and (msg.type == "counter_ready" or msg.type == "counter_handed"
        or msg.type == "counter_drop") then
      local f = tonumber(msg.forId)
      if msg.type == "counter_ready" and not K.COUNTER and f and K.foreign[f] and K.foreign[f].n == msg.n then
        K.foreign[f].readyAt = K.foreign[f].readyAt or os.clock()
      elseif msg.type == "counter_handed" and f then
        K.foreign[f] = nil
      elseif msg.type == "counter_drop" and K.COUNTER and f and orders[f] and orders[f].n == msg.n then
        orders[f] = nil                       -- (Crafty took it over)
        served[f] = msg.n
      end
    elseif type(msg) == "table" and id and (K.COUNTER or (msg.type == "materials" and not K.mine(id))) then
      -- a counter's share, or not a counter's business at all
      if K.COUNTER and K.mine(id) and msg.type == "materials" and type(msg.items) == "table"
          and (msg.n == nil or served[id] ~= msg.n) then
        orders[id] = { items = msg.items, fuel = tonumber(msg.fuel) or 0, n = msg.n }
      elseif not K.COUNTER and msg.type == "materials" and type(msg.items) == "table" then
        -- a Counter's share: kept, in case it is never collected
        local f = K.foreign[id]
        if not f or f.n ~= msg.n then
          K.foreign[id] = { items = msg.items, fuel = tonumber(msg.fuel) or 0, n = msg.n, at = os.clock(),
            bay = K.bayName(msg.bay), back = msg.back }
        end
      end
    elseif type(msg) == "table" and id then
      if msg.type == "base_request" then
        -- a drone told to rebase (swarm.lua) asks where the base is now
        if base then rednet.send(id, { type = "base", base = base, forId = id }, K.JOB_PROTOCOL) end
      elseif msg.type == "need_job" then
        if base then
          local job = jobFor(id)
          if job then rednet.send(id, job, K.JOB_PROTOCOL) end
        end
      elseif msg.type == "job_done" then
        if plots.byId[tostring(id)] == msg.index then
          plots.byId[tostring(id)] = nil
          plots.between = plots.between or {}
          plots.between[tostring(id)] = true
          plots.done = (plots.done or 0) + 1
          saveTable(K.PLOTS_FILE, plots)
        end
      elseif msg.type == "fuel_request" then
        fuelQueue[id] = true
      elseif msg.type == "bucket_request" then
        bucketQueue[id] = true
      elseif msg.type == "scanner_request" then
        scannerQueue[id] = true
      elseif msg.type == "escort_request" then
        escortFor(id, msg)
      elseif msg.type == "feed_request" then
        feedFor(id, msg)
      elseif msg.type == "controller_request" then
        -- a turtle with room for a Chunk Controller of its own
        local given = (plots.ctlGiven or {})[tostring(id)] or 0
        if given < K.CTL_PER_TURTLE and spareControllers() > 0 then
          ctlQueue[id] = os.clock()
        else
          rednet.send(id, { type = "controller_none", forId = id }, K.JOB_PROTOCOL)
        end
      elseif msg.type == "empties_request" then
        emptiesQueue[id] = math.max(1, math.min(16, math.floor(tonumber(msg.n) or 8)))
      elseif msg.type == "materials" and type(msg.items) == "table"
        and (msg.n == nil or served[id] ~= msg.n) then
        local o = orders[id]
        if not (o and o.ready and o.n == msg.n) then    -- (a repeat of a load already made: keep it)
          orders[id] = { items = msg.items, fuel = tonumber(msg.fuel) or 0, n = msg.n,
            bay = K.bayName(msg.bay), back = type(msg.back) == "table" and msg.back or nil }
        end
      elseif msg.type == "foundry_ready" or msg.type == "foundry_ack" or msg.type == "foundry_done" then
        pcall(foundryHeard, id, msg)
      elseif msg.type == "release" then
        -- a miner turned coal hunter: its plot goes to the next new miner
        if plots.byId[tostring(id)] == msg.index then
          plots.byId[tostring(id)] = nil
          plots.free = plots.free or {}
          table.insert(plots.free, msg.index)
          plots.hunter = true
          saveTable(K.PLOTS_FILE, plots)
        end
      end
    end
  end
end

---------------------------------------------------------------- unwanted stone
-- Stone nobody has a use for (Kyle's call) is thrown out to make room: a
-- few stacks at a time onto the launch pad when it is empty, where they
-- lie until the game clears them away. Only what is named here, ever.
local DUMP = { "forbidden_arcanus:darkstone", "xycraft_world:kivi" }
dumpJunk = function(stock)
  if next(orders) then return end
  local any = false
  for _, name in ipairs(DUMP) do
    if (stock[name] or 0) > 0 then any = true end
  end
  if not any then return end
  stashAll()
  turnTo(base.padTurns)
  if turtle.detect() then                       -- someone is on the pad: not now
    turnTo(0)
    return
  end
  local thrown = 0
  for _, name in ipairs(DUMP) do
    for slot = 1, 8 do
      if (stock[name] or 0) - thrown <= 0 then break end
      pull(name, 64, slot)
    end
    for slot = 1, 16 do
      local d = turtle.getItemDetail(slot)
      if d and d.name == name and not turtle.detect() then
        turtle.select(slot)
        if turtle.drop() then thrown = thrown + d.count end
      end
    end
    if thrown > 0 then break end
  end
  turtle.select(1)
  turnTo(0)
  stashAll()
  if thrown > 0 then print("Threw out " .. thrown .. " unwanted stone.") end
end

---------------------------------------------------------------- fuel from nothing
-- No coal and no charcoal at all: nothing can smelt, so logs cannot become
-- charcoal either. Planks burn in a furnace too (a plank cooks 1.5 items,
-- and one log makes four): cook a first batch of logs on planks. After
-- that there is charcoal, and one charcoal cooks eight logs.
bootstrapFuel = function(stock)
  if next(orders) then return end
  if countIn(stock, "#fuel") > 0 then return end
  local logs = countIn(stock, "#log")
  if logs < 4 then return end
  local planks = countIn(stock, "#planks")
  if planks < 8 then
    local pretend = {}
    for name, c in pairs(stock) do pretend[name] = c end
    local steps, missing = {}, {}
    plan(pretend, "#planks", 8, steps, missing)
    if next(missing) then return end
    stashAll()
    runSteps(steps)
    stashAll()
  end
  for _, f in ipairs(furnaces) do
    local okList, items = pcall(furnaceList, f)
    if okList and not items[1] and not items[2] then
      local fed, loaded = 0, 0
      for _, st in ipairs(listStorage()) do
        if fed < 8 and matches("#planks", st.name) then
          fed = fed + (peripheral.call(st.inv, "pushItems", f, st.slot, 8 - fed, 2) or 0)
        end
      end
      if fed == 0 then return end
      local kind
      for _, st in ipairs(listStorage()) do
        if loaded < math.floor(fed * 1.5) and matches("#log", st.name) and (not kind or kind == st.name) then
          kind = st.name
          loaded = loaded + (peripheral.call(st.inv, "pushItems", f, st.slot, math.floor(fed * 1.5) - loaded, 1) or 0)
        end
      end
      print(("No fuel at all: cooking %d logs on planks for charcoal."):format(loaded))
      return
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
  if K.COUNTER then
    -- (no drop-off chest to face: turns count from wherever it faced at start,
    -- and it always turns back there)
    if facing == nil then facing = 0 end
    if os.clock() - K.counterBeat > 30 then
      K.counterBeat = os.clock()
      rednet.broadcast({ type = "counter_alive", slot = K.SLOT }, K.JOB_PROTOCOL)
    end
    local b
    b, why = survey()
    if not b then return notReady(why) end
    if serveOrders() then return true end
    report(next(orders) and "counter: serving" or "counter: open")
    return false
  end
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
  if not held then
    if pendingMake then
      local item, n = pendingMake[1], pendingMake[2]
      pendingMake = nil
      pcall(function()
        local stock = stockTotals()
        local steps, missing = {}, {}
        plan(stock, item, n + countIn(stockTotals(), item), steps, missing)
        local parts = {}
        for k, v in pairs(missing) do parts[#parts + 1] = tostring(v) .. " " .. shortName(k) end
        if #parts > 0 then print("Make " .. shortName(item) .. ": short of " .. table.concat(parts, ", ")) end
        local okRun, err = pcall(runSteps, steps)
        print("Make " .. shortName(item) .. ": " .. (okRun and "done" or tostring(err)) .. ", have "
          .. countIn(stockTotals(), item))
      end)
    end
    -- coal comes in blocks (and compressed blocks): keep some loose coal
    pcall(function()
      local stock = stockTotals()
      if (stock["minecraft:coal"] or 0) < 128 and ((stock["minecraft:coal_block"] or 0) > 0
          or (stock["allthecompressed:coal_block_1x"] or 0) > 0) then
        print("Unpacking coal blocks.")
        makeUpTo("minecraft:coal", 256)
      end
    end)
    pcall(bootstrapFuel, stockTotals())
    pcall(dumpJunk, stockTotals())
    pcall(keepFurnacesBusy, stockTotals())
    pcall(foundryDuty, stockTotals())
    pcall(haulDuty, stockTotals())
    -- empty buckets go out with the miners and the farm round, and leak
    -- away: keep a few in, made from iron when there is iron to spare
    pcall(function()
      local stock = stockTotals()
      if (stock["minecraft:bucket"] or 0) < 4 and (stock["minecraft:iron_ingot"] or 0) >= 64 then
        print("Making empty buckets.")
        makeUpTo("minecraft:bucket", 8)
      end
    end)
    pcall(lavaFarmDuty, stockTotals())
  end

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
  -- a load is made and its turtle is on the way down: do not start a build
  -- that ends with the launch pad taken (three minutes' grace)
  if not held then
    for _, o in pairs(orders) do
      if o.ready and os.clock() - (o.readyAt or 0) < 180 then
        report("waiting for the builder")
        sleep(2)
        lastStock = stockTotals()
        return true
      end
    end
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
    plan(pretend, K.TURTLE, 1, steps, missing)
    plan(pretend, K.MODEM, 1, steps, missing)
    plan(pretend, "#fuel", K.NEWBORN_COAL, steps, missing)
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

  -- a chunk loader, while there is a Chunk Controller to put on one
  if #(plots.loaders or {}) < LOADERS and (lastStock[K.CHUNKY] or 0) > 0 and not plots.noLoaders then
    -- with an ender modem. (PLAIN_LOADERS: failing that a plain wireless
    -- modem, stone and an ender pearl: a loader flies high, where even that
    -- reaches far, and the others' ender modems hear it anywhere.)
    local steps, missing, modem
    for _, m in ipairs(K.PLAIN_LOADERS and { K.MODEM, K.PLAIN_MODEM } or { K.MODEM }) do
      local pretend = {}
      for name, c in pairs(lastStock) do pretend[name] = c end
      local st2, miss2 = {}, {}
      plan(pretend, K.TURTLE, 1, st2, miss2)
      plan(pretend, m, 1, st2, miss2)
      plan(pretend, "#fuel", K.NEWBORN_COAL, st2, miss2)
      if not missing or not next(miss2) then steps, missing, modem = st2, miss2, m end
      if not next(miss2) then break end
    end
    if not next(missing) then
      print("Building a chunk loader" .. (modem == K.PLAIN_MODEM and " (plain wireless modem)..." or "..."))
      report("building")
      runSteps(steps)
      plots.makingLoader, plots.loaderModem = true, modem
      saveTable(K.PLOTS_FILE, plots)
      local okFit, why = pcall(assemble)
      if not okFit then
        if why == "Terminated" then error(why, 0) end
        if not getStage() then
          -- the controller would not go on: put the parts back and leave it
          -- (until .plots is edited), rather than trying for ever
          plots.makingLoader, plots.noLoaders, plots.loaderModem = nil, true, nil
          saveTable(K.PLOTS_FILE, plots)
          stashAll()
        end
        error("chunk loader: " .. tostring(why), 0)
      end
      print("Launching the chunk loader")
      deploy()
      built = built + 1
      lastStock = stockTotals()
      report("launched a loader")
      return true
    end
    local what = describeMissing(missing)
    if what ~= lastLoaderWait then
      print("A chunk loader is waiting for: " .. what)
      lastLoaderWait = what
    end
  end

  local forHelper = #(plots.helpers or {}) < K.HELPERS
  if not forHelper and activeCount() + pending >= K.MAX_MINERS then
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
  plan(pretend, "#fuel", K.NEWBORN_COAL, steps, missing)   -- fuel to send it off with
  plan(pretend, K.BUCKET, 1, steps, missing)               -- and a bucket for lava
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
    if not result then sleep(K.CHECK_EVERY) end
  end
end

local function work()
  parallel.waitForAny(buildLoop, responder, statusListener)
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
  if not label or label == "factory" then os.setComputerLabel("Crafty") end
end

local task = fs.exists(K.PAUSE_FILE) and paused or work

if not swarm then
  task()
  return
end

while true do
  local cmd = swarm.runWithCommands(task, function(c)
    if c.cmd == "ping" then
      report(lastState)
      return true
    elseif c.cmd == "lavafarm" then        -- lavafarm Crafty n=<units built> how=place|use
      plots.lavafarm = { n = tonumber(c.n) or 0,
        how = (c.how == "use" or c.how == "hut") and c.how or "place" }
      if type(c.row) == "string" then        -- row=x,y,z,n[,face]: the dripstone row's stand and length
        local x, y, z, n, f = c.row:match("^(-?%d+),(-?%d+),(-?%d+),(%d+),?(%d*)$")
        if x then plots.lavafarm.row = { x = tonumber(x), y = tonumber(y), z = tonumber(z), n = tonumber(n),
          face = tonumber(f) or 2 } end
      end
      if type(c.skip) == "string" then
        plots.lavafarm.skip = {}
        for name in c.skip:gmatch("[^,]+") do plots.lavafarm.skip[name] = true end
      end
      saveTable(K.PLOTS_FILE, plots)
      print("Lava farm: " .. plots.lavafarm.n .. " cauldrons (" .. plots.lavafarm.how .. ").")
      return true
    elseif c.cmd == "haul" then            -- haul Crafty on=1|0 [x= y= z= face=]: carry bulk stock to the store
      plots.haul = plots.haul or {}
      if c.on ~= nil then plots.haul.on = (c.on == "1" or c.on == 1 or c.on == true) end
      if type(c.skip) == "string" then
        plots.haul.skip = {}
        for name in c.skip:gmatch("[^,]+") do plots.haul.skip[name] = true end
      end
      saveTable(K.PLOTS_FILE, plots)
      print("Hauling to the store: " .. (plots.haul.on and "on" or "off") .. ".")
      return true
    elseif c.cmd == "make" and c.item then     -- make Crafty item=<id> n=<count>: craft into stock
      pendingMake = { c.item, math.max(1, math.floor(tonumber(c.n) or 1)) }
      return true
    elseif c.cmd == "rebase" then          -- (for the drones: the factory knows where it is)
      return true
    elseif c.cmd == "stores" then          -- stores Crafty skip=a,b*: inventories on the cable that are not storage
      plots.stores = { skip = {} }
      for name in tostring(c.skip or ""):gmatch("[^,]+") do table.insert(plots.stores.skip, name) end
      saveTable(K.PLOTS_FILE, plots)
      print("Not storage: " .. (#plots.stores.skip > 0 and table.concat(plots.stores.skip, ", ") or "nothing named"))
      return true
    elseif c.cmd == "wood" then            -- wood Crafty first=<wood>: no need to stop work
      setFirstWood(c.first)
      return true
    elseif c.cmd == "draft" and tonumber(c.turtle) then   -- (not id=: every order has its own id)
      -- draft Crafty id=<n>: an existing turtle (a parked miner) becomes a
      -- builder's mate; it is told so the next time it asks for a job
      local id = math.floor(tonumber(c.turtle))
      plots.helpers = plots.helpers or {}
      local have = false
      for _, h in ipairs(plots.helpers) do if tostring(h) == tostring(id) then have = true end end
      if not have then
        plots.helpers[#plots.helpers + 1] = id
        if plots.byId then plots.byId[tostring(id)] = nil end
        saveTable(K.PLOTS_FILE, plots)
        print("Turtle " .. id .. " is a builder's mate now: " .. tostring(HELPER_NAMES[#plots.helpers]))
      end
      return true
    end
  end)
  if not cmd then
    return
  elseif cmd.cmd == "reboot" then
    if modem and not K.COUNTER then pcall(modem.transmit, K.RACK_CHANNEL, K.RACK_CHANNEL, { type = "cmd", cmd = cmd }) end
    print("Rebooting by remote order.")
    swarm.pinVersion(cmd)
    report("rebooting")
    os.reboot()
  elseif cmd.cmd == "stop" or cmd.cmd == "home" then
    local h = fs.open(K.PAUSE_FILE, "w")
    h.write("paused")
    h.close()
    task = paused
  elseif cmd.cmd == "resume" then
    fs.delete(K.PAUSE_FILE)
    task = work
  end
end
