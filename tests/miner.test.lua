-- miner.lua in the simulator: a small base and a small plot.
--
--   shafts at z 0:  OUT x 7 (open from the out road up), IN x 11 (open from the in road up)
--   way in :  up the in-shaft to y 70, south to z 3, west to x 9, down to y 69, south into the berth (9, 69, 5)
--   way out:  berth, north to z 3, up to y 71, west to x 7, north to z 0, down the out-shaft
--   cargo barrel under the berth, fuel barrel over it
--   plot: 2 x 2 columns from (20, 4), top 50, bottom 40  ->  3 layers at y 48, 45, 42
--   out road y 52, in road y 56

local function c(x, y, z) return { x = x, y = y, z = z } end
local IN = { c(11, 70, 0), c(11, 70, 3), c(9, 70, 3), c(9, 69, 3), c(9, 69, 5) }
local OUT = { c(9, 69, 5), c(9, 69, 3), c(9, 71, 3), c(7, 71, 3), c(7, 71, 0) }
local JOB = { type = "job", forId = 1, index = 7, x0 = 20, z0 = 4, size = 2, topY = 50, bottom = 40,
  inbound = IN, outbound = OUT }

local function saved(extra)
  local j = { index = 7, x0 = 20, z0 = 4, size = 2, topY = 50, bottom = 40, inbound = IN, outbound = OUT,
    layer = 1, cell = 0, phase = "mine" }
  for k, v in pairs(extra or {}) do j[k] = v end
  SIM.files[".miner"] = textutils.serialize(j)
end

local function world()
  SIM.fill(0, 36, -4, 30, 64, 12, "minecraft:stone")         -- rock to well above the roads
  for y = 52, 64 do SIM.block(7, y, 0, nil) end              -- the out-shaft is open, as at the base
  for y = 57, 64 do SIM.block(11, y, 0, nil) end             -- and the in-shaft above the in road
  SIM.block(9, 68, 5, "minecraft:barrel")                    -- cargo, under the berth
  SIM.block(9, 70, 5, "minecraft:barrel")                    -- fuel, over it
  SIM.peripherals.right = { types = { "modem" }, methods = { isWireless = function() return true end } }
end

local function miner(cfg)
  local m = assert(loadfile("miner.lua"))("module")
  m.setup()
  m.cfg.patience = 50                                        -- no test may wait for ever
  for k, v in pairs(cfg or {}) do m.cfg[k] = v end
  return m
end

local function start(x, y, z)
  local move = require("lib.move")
  move.set(x, y, z, "north")
end

local function sent(kind)
  local out = {}
  for _, s in ipairs(SIM.sent) do
    if type(s[2]) == "table" and (s[2].type == kind or (kind == "report" and s[3] == "swarm")) then out[#out + 1] = s[2] end
  end
  return out
end

local function plotClear()
  for x = 20, 21 do for z = 4, 5 do for y = 41, 49 do
    if SIM.getBlock(x, y, z) then return false, x .. "," .. y .. "," .. z end
  end end end
  return true
end

local function droppedDown()
  local n = 0
  for _, d in ipairs(SIM.dropped) do if d.where == "down" then n = n + d.count end end
  return n
end

local function at(x, y, z) return SIM.t.x == x and SIM.t.y == y and SIM.t.z == z end

test("takes a plot, digs all of it, unloads in its berth and says it is done", function()
  world()
  SIM.receive(99, JOB, "swarm_job")
  local m = miner({ fuelTarget = 100 })
  start(7, 52, 0)                                             -- foot of the out-shaft
  m.work(6)
  local clear, where = plotClear()
  ok(clear, "plot dug (left: " .. tostring(where) .. ")")
  ok(droppedDown() >= 36, "everything dug went into the cargo barrel: " .. droppedDown())
  eq(#sent("job_done"), 1, "job_done sent")
  eq(sent("job_done")[1].index, 7)
  eq(SIM.getBlock(9, 68, 5), "minecraft:barrel", "the cargo barrel is still there")
  eq(SIM.getBlock(9, 70, 5), "minecraft:barrel", "and the fuel barrel")
  ok(at(9, 69, 5), "waiting in its berth for the next plot")
end, { x = 7, y = 52, z = 0, f = 0, fuel = 5000 })

test("a full inventory sends it home, then it carries on where it was", function()
  world()
  SIM.receive(99, JOB, "swarm_job")
  for s = 1, 15 do SIM.give(s, "minecraft:thing" .. s, 64) end -- one free slot
  local m = miner({ fuelTarget = 100 })
  start(7, 52, 0)
  m.work(3)                                                    -- take job, mine (stops full), dock
  local job = textutils.unserialize(SIM.files[".miner"])
  eq(job.phase, "leave", "unloaded and about to leave")
  ok(job.cell >= 1 and job.layer == 1, "stopped part way: cell " .. tostring(job.cell))
  ok(droppedDown() >= 15 * 64, "unloaded")
  ok(at(9, 69, 5), "in the berth")
  m.work(8)
  ok(plotClear(), "plot finished after the trip")
end, { x = 7, y = 52, z = 0, f = 0, fuel = 5000 })

test("low on fuel: it takes coal from the barrel overhead, only what it needs", function()
  world()
  SIM.stockAt(9, 70, 5, "minecraft:coal", 64)
  saved({ phase = "dock" })
  local m = miner({ fuelTarget = 2000, fuelLow = 50 })
  start(9, 69, 5)                                              -- in the berth
  m.work(1)                                                    -- unload, refuel
  ok(SIM.t.fuel >= 2000, "refuelled: " .. SIM.t.fuel)
  eq(SIM.stock["9,70,5"][1].count, 64 - 20, "took 20 coal for 1600 fuel")
  eq(turtle.getItemCount(1), 0, "carries no coal away")
  m.work(1)                                                    -- leave
  ok(at(7, 52, 0), "at the foot of the out-shaft")
end, { x = 9, y = 69, z = 5, f = 0, fuel = 400 })

test("an empty fuel barrel only holds it up for a while", function()
  world()
  saved({ phase = "dock" })
  local m = miner({ fuelTarget = 2000, fuelLow = 50, coalWait = 20 })
  start(9, 69, 5)
  m.work(2)
  ok(at(7, 52, 0), "left with what it had")
  ok(#sent("report") >= 1, "and said it was waiting for coal")
end, { x = 9, y = 69, z = 5, f = 0, fuel = 400 })

test("a plot taken before the berths existed: it asks the controller the way home", function()
  world()
  SIM.files[".miner"] = textutils.serialize({ index = 7, x0 = 20, z0 = 4, size = 2, topY = 50, bottom = 40,
    dock = c(10, 73, 0), exit1 = c(9, 73, 0), exit2 = c(8, 73, 0), layer = 3, cell = 4, phase = "dock" })
  SIM.receive(99, JOB, "swarm_job")
  local m = miner({ fuelTarget = 100 })
  start(20, 42, 4)                                             -- down in its plot
  for x = 20, 21 do for z = 4, 5 do for y = 41, 49 do SIM.block(x, y, z, nil) end end end
  m.work(1)
  local job = textutils.unserialize(SIM.files[".miner"])
  eq(job.dock, nil, "the old dock is forgotten")
  eq(job.inbound[5].z, 5, "the way in is kept")
  eq(job.layer, 3, "its place in the plot is kept")
  ok(at(9, 69, 5), "and it came home to the berth")
end, { x = 20, y = 42, z = 4, f = 0, fuel = 5000 })

test("restarted on the way in, it goes on in; on the way out, on out", function()
  world()
  saved({ phase = "dock" })
  local m = miner({ fuelTarget = 100 })
  start(10, 70, 3)                                             -- in the aisle, inbound
  m.work(1)
  ok(at(9, 69, 5), "reached the berth")
  saved({ phase = "leave" })
  m = miner({ fuelTarget = 100 })
  SIM.t.x, SIM.t.y, SIM.t.z, SIM.t.f = 8, 71, 3, 0             -- in the aisle, outbound, facing north
  start(8, 71, 3)
  local before = SIM.t.moves
  m.work(1)
  ok(at(7, 52, 0), "reached the foot of the out-shaft")
  eq(SIM.t.moves - before, 1 + 3 + 19, "straight there")
end, { x = 10, y = 70, z = 3, f = 0, fuel = 5000 })

test("sent home while it is on the way out, it goes round: the ways are one-way", function()
  world()
  saved({ phase = "dock" })
  local m = miner({ fuelTarget = 100 })
  start(7, 71, 2)                                              -- outbound, nearly at the out-shaft
  m.work(1)
  ok(at(9, 69, 5), "home")
  ok(SIM.t.moves > 60, "by the out-shaft, the roads and the in-shaft: " .. SIM.t.moves .. " moves")
end, { x = 7, y = 71, z = 2, f = 0, fuel = 5000 })

test("after a restart in the middle of a layer it finishes the plot", function()
  world()
  for x = 20, 21 do for z = 4, 5 do for y = 47, 49 do SIM.block(x, y, z, nil) end end end   -- layer 1 already dug
  -- layer 2 runs layer 1's path backwards, so its first cell is the column layer 1 ended in
  SIM.block(20, 46, 5, nil) SIM.block(20, 45, 5, nil) SIM.block(20, 44, 5, nil)
  saved({ layer = 2, cell = 1 })
  local m = miner({ fuelTarget = 100 })
  ok(m.locateSelf(), "found itself by GPS")
  m.work(1)
  ok(plotClear(), "plot finished")
  eq(textutils.unserialize(SIM.files[".miner"]).phase, "finish")
end, { x = 20, y = 45, z = 5, f = 2, fuel = 5000 })

test("a machine in the plot is left alone, and the rest of the plot is still dug", function()
  world()
  SIM.block(21, 45, 4, "ae2:cable_bus")
  SIM.receive(99, JOB, "swarm_job")
  local m = miner({ fuelTarget = 100 })                        -- patience as in the field: it must not wait for ever
  m.cfg.patience = math.huge
  start(7, 52, 0)
  m.work(2)
  eq(SIM.getBlock(21, 45, 4), "ae2:cable_bus", "not dug")
  eq(textutils.unserialize(SIM.files[".miner"]).phase, "finish", "the rest of the plot was still done")
  eq(SIM.getBlock(20, 42, 4), nil, "down to the last layer")
end, { x = 7, y = 52, z = 0, f = 0, fuel = 5000 })

test("plain rock and ores that mods add are dug like any other", function()
  world()
  SIM.block(21, 45, 4, "create:scoria")
  SIM.block(20, 45, 4, "create:deepslate_zinc_ore")
  SIM.block(20, 45, 5, "mekanism:osmium_ore")
  SIM.receive(99, JOB, "swarm_job")
  local m = miner({ fuelTarget = 100 })
  start(7, 52, 0)
  m.work(2)
  ok(plotClear(), "all of it dug")
  local got = {}
  for _, b in ipairs(SIM.dug) do got[b] = true end
  ok(got["create:scoria"] and got["create:deepslate_zinc_ore"] and got["mekanism:osmium_ore"], "and kept")
end, { x = 7, y = 52, z = 0, f = 0, fuel = 5000 })

test("but what is built from that rock is not", function()
  world()
  SIM.block(21, 45, 4, "create:cut_scoria_bricks")
  SIM.receive(99, JOB, "swarm_job")
  local m = miner({ fuelTarget = 100 })
  start(7, 52, 0)
  m.work(2)
  eq(SIM.getBlock(21, 45, 4), "create:cut_scoria_bricks", "left alone")
end, { x = 7, y = 52, z = 0, f = 0, fuel = 5000 })

test("near the surface it never digs: a miner set down in the factory waits", function()
  world()
  SIM.fill(0, 69, -4, 30, 69, 12, "minecraft:gray_concrete")  -- a factory floor
  SIM.receive(99, JOB, "swarm_job")
  local m = miner({ fuelTarget = 100, patience = 1 })
  start(15, 70, 8)
  local okRun, err = pcall(m.work, 2)
  eq(okRun, false, "gave up (with patience 1)")
  has(tostring(err), "protected:minecraft:gray_concrete", "said why")
  eq(SIM.getBlock(15, 69, 8), "minecraft:gray_concrete", "floor untouched")
  eq(#SIM.dug, 0, "nothing dug at all")
end, { x = 15, y = 70, z = 8, f = 0, fuel = 5000 })

test("even plain stone is not dug up there", function()
  world()
  SIM.fill(0, 69, -4, 30, 69, 12, "minecraft:stone")
  SIM.receive(99, JOB, "swarm_job")
  local m = miner({ fuelTarget = 100, patience = 1 })
  start(15, 70, 8)
  local okRun, err = pcall(m.work, 2)
  eq(okRun, false)
  has(tostring(err), "blocked:minecraft:stone", "said why")
  eq(#SIM.dug, 0, "nothing dug at all")
end, { x = 15, y = 70, z = 8, f = 0, fuel = 5000 })

test("a shut gate on the way in: it waits and says why, and digs nothing", function()
  world()
  SIM.block(11, 70, 2, "create:metal_girder")                 -- the gate leaf, across the way in
  saved({ phase = "dock" })
  local m = miner({ fuelTarget = 100, patience = 2 })
  start(11, 70, 0)
  local okRun, err = pcall(m.work, 1)
  eq(okRun, false)
  has(tostring(err), "protected:create:metal_girder")
  eq(SIM.getBlock(11, 70, 2), "create:metal_girder", "gate untouched")
end, { x = 11, y = 70, z = 0, f = 0, fuel = 5000 })

test("a job without a way home is not taken", function()
  world()
  SIM.receive(99, { type = "job", forId = 1, index = 7, x0 = 20, z0 = 4, size = 2, topY = 50, bottom = 40,
    dock = c(10, 73, 0), exit1 = c(9, 73, 0), exit2 = c(8, 73, 0) }, "swarm_job")
  local m = miner({ fuelTarget = 100 })
  start(7, 52, 0)
  m.work(1)
  eq(SIM.files[".miner"], nil, "nothing saved")
  eq(SIM.t.moves, 0, "it stayed where it was")
end, { x = 7, y = 52, z = 0, f = 0, fuel = 5000 })

test("orders only set flags; the loop acts on them between steps", function()
  world()
  local m = miner()
  m.order({ cmd = "stop" })
  eq(m.flags().parked, true)
  m.order({ cmd = "resume" })
  eq(m.flags().parked, false)
  m.order({ cmd = "newjob" })
  eq(m.flags().abandon, true)
  m.order({ cmd = "reboot", rev = ("a"):rep(40) })
  eq(m.flags().reboot, true)
  eq(SIM.files[".rev"], ("a"):rep(40), "the version to load is pinned")
end)

test("told to give its plot up, it hands it back and asks again", function()
  world()
  SIM.receive(99, JOB, "swarm_job")
  local m = miner({ fuelTarget = 100 })
  start(7, 52, 0)
  m.work(1)                                                    -- take the job
  m.order({ cmd = "newjob" })
  m.work(1)
  eq(#sent("job_done"), 1, "plot handed back")
  eq(textutils.unserialize(SIM.files[".miner"]).index, nil, "no job in hand")
end, { x = 7, y = 52, z = 0, f = 0, fuel = 5000 })

test("it reports where it is and what it is doing", function()
  world()
  SIM.receive(99, JOB, "swarm_job")
  local m = miner({ fuelTarget = 100 })
  start(7, 52, 0)
  m.work(2)
  local reports = sent("report")
  ok(#reports >= 1, "at least one report")
  local last = reports[#reports]
  eq(last.role, "miner")
  ok(last.pos and last.pos.x, "has a position")
  ok(last.job and last.job.plot == 7, "names its plot")
end, { x = 7, y = 52, z = 0, f = 0, fuel = 5000 })

test("a miner left underground off the roads finds its way round by the base", function()
  world()
  SIM.receive(99, JOB, "swarm_job")
  local m = miner({ fuelTarget = 100 })
  start(26, 60, 9)                                             -- in rock, above the roads
  m.work(2)                                                    -- take the job; go round; dig the plot
  ok(plotClear(), "plot dug")
  ok(droppedDown() > 0, "it passed its berth on the way")
end, { x = 26, y = 60, z = 9, f = 0, fuel = 5000 })

test("a road pier on the way is never dug: it waits and says why", function()
  world()
  SIM.block(15, 56, 4, "minecraft:polished_deepslate")        -- on the in road, between plot and base
  SIM.receive(99, JOB, "swarm_job")
  local m = miner({ fuelTarget = 100, patience = 1 })
  start(7, 52, 0)
  m.work(2)                                                    -- take the job, dig the plot
  local okRun, err = pcall(m.work, 1)                          -- the trip to the base
  eq(okRun, false)
  has(tostring(err), "protected:minecraft:polished_deepslate")
  eq(SIM.getBlock(15, 56, 4), "minecraft:polished_deepslate", "pier untouched")
end, { x = 7, y = 52, z = 0, f = 0, fuel = 5000 })

test("told which layer to carry on from, it skips the ones above", function()
  world()
  for x = 20, 21 do for z = 4, 5 do for y = 44, 49 do SIM.block(x, y, z, nil) end end end   -- layers 1 and 2 dug before
  SIM.receive(99, JOB, "swarm_job")
  local m = miner({ fuelTarget = 100 })
  start(7, 52, 0)
  m.work(1)                                                    -- take the job
  m.order({ cmd = "layer", n = 3 })
  local movesBefore = SIM.t.moves
  m.work(1)
  ok(plotClear(), "plot finished")
  eq(textutils.unserialize(SIM.files[".miner"]).phase, "finish")
  ok(SIM.t.moves - movesBefore < 40, "did not walk the dug layers: " .. (SIM.t.moves - movesBefore) .. " moves")
end, { x = 7, y = 52, z = 0, f = 0, fuel = 5000 })

test("a hunter's pickaxe goes back on, on the side the modem is not", function()
  world()                                                      -- modem on the right
  SIM.give(4, "minecraft:diamond_pickaxe", 1)
  local side
  turtle.equipLeft = function() side = "left" SIM.t.inv[SIM.t.sel] = { name = "advancedperipherals:geo_scanner", count = 1 } return true end
  turtle.equipRight = function() side = "right" return true end
  local m = miner()
  eq(m.ensureTool(), true)
  eq(side, "left", "the modem is on the right")
  eq(turtle.getItemDetail(4).name, "advancedperipherals:geo_scanner", "the scanner came off into the pack")
  side = nil
  eq(m.ensureTool(), true, "no pickaxe carried: nothing to do")
  eq(side, nil)
end)
