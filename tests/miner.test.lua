-- miner.lua in the simulator: a small base and a small plot.
--
--   row at y 73, z 0:   OUT shaft x 7 | exit2 x 8 (fuel pad at y 72) | exit1 x 9 | dock x 10 | IN shaft x 11
--   plot: 2 x 2 columns from (20, 4), top 50, bottom 40  ->  3 layers at y 48, 45, 42
--   out road y 52, in road y 56

local DOCK, E1, E2 = { x = 10, y = 73, z = 0 }, { x = 9, y = 73, z = 0 }, { x = 8, y = 73, z = 0 }
local JOB = { type = "job", forId = 1, index = 7, x0 = 20, z0 = 4, size = 2, topY = 50, bottom = 40,
  dock = DOCK, exit1 = E1, exit2 = E2 }

local function world()
  SIM.fill(0, 36, -4, 30, 64, 12, "minecraft:stone")         -- rock to well above the roads
  for y = 52, 64 do SIM.block(7, y, 0, nil) end              -- the out-shaft is open, as at the base
  for y = 57, 64 do SIM.block(11, y, 0, nil) end             -- and the in-shaft above the in road
  SIM.block(10, 72, 0, "minecraft:chest")                    -- the drop-off under the dock
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

test("takes a plot, digs all of it, unloads at the dock and says it is done", function()
  world()
  SIM.receive(99, JOB, "swarm_job")
  local m = miner({ fuelTarget = 100 })
  start(7, 52, 0)                                             -- foot of the out-shaft
  m.work(6)
  local clear, where = plotClear()
  ok(clear, "plot dug (left: " .. tostring(where) .. ")")
  ok(droppedDown() >= 36, "everything dug went into the chest: " .. droppedDown())
  eq(#sent("job_done"), 1, "job_done sent")
  eq(sent("job_done")[1].index, 7)
  eq(SIM.getBlock(10, 72, 0), "minecraft:chest", "the chest is still there")
  eq(SIM.t.y, 52, "waiting on the out road")
  ok(SIM.t.x == 7 and SIM.t.z >= 2, "in its pocket, clear of the shaft")
end, { x = 7, y = 52, z = 0, f = 0, fuel = 5000 })

test("a full inventory sends it to the dock, then it carries on where it was", function()
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
  m.work(8)
  ok(plotClear(), "plot finished after the trip")
end, { x = 7, y = 52, z = 0, f = 0, fuel = 5000 })

test("low on fuel: it sits on the pad until the coal arrives, then goes back", function()
  world()
  SIM.receive(99, JOB, "swarm_job")
  local m = miner({ fuelTarget = 2000, fuelLow = 50 })
  start(10, 73, 0)                                             -- on the dock
  local realSleep, fed = sleep, 0
  sleep = function(s)                                          -- the export bus under the pad
    if SIM.t.x == 8 and SIM.t.y == 72 and SIM.t.z == 0 then
      SIM.addItem("minecraft:coal", 16)
      fed = fed + 1
    end
    return realSleep(s)
  end
  local job = { index = 7, x0 = 20, z0 = 4, size = 2, topY = 50, bottom = 40, dock = DOCK, exit1 = E1, exit2 = E2,
    layer = 1, cell = 0, phase = "leave" }
  SIM.files[".miner"] = textutils.serialize(job)
  m = miner({ fuelTarget = 2000, fuelLow = 50 })
  m.work(1)                                                    -- leave the dock
  ok(fed >= 1, "waited on the pad")
  ok(SIM.t.fuel >= 2000, "refuelled: " .. SIM.t.fuel)
  eq(SIM.t.x, 7) eq(SIM.t.y, 52)
end, { x = 10, y = 73, z = 0, f = 0, fuel = 400 })

test("after a restart in the middle of a layer it finishes the plot", function()
  world()
  for x = 20, 21 do for z = 4, 5 do for y = 47, 49 do SIM.block(x, y, z, nil) end end end   -- layer 1 already dug
  -- layer 2 runs layer 1's path backwards, so its first cell is the column layer 1 ended in
  SIM.block(20, 46, 5, nil) SIM.block(20, 45, 5, nil) SIM.block(20, 44, 5, nil)
  local job = { index = 7, x0 = 20, z0 = 4, size = 2, topY = 50, bottom = 40, dock = DOCK, exit1 = E1, exit2 = E2,
    layer = 2, cell = 1, phase = "mine" }
  SIM.files[".miner"] = textutils.serialize(job)
  local m = miner({ fuelTarget = 100 })
  ok(m.locateSelf(), "found itself by GPS")
  m.work(1)
  ok(plotClear(), "plot finished")
  eq(textutils.unserialize(SIM.files[".miner"]).phase, "finish")
end, { x = 20, y = 45, z = 5, f = 2, fuel = 5000 })

test("a machine in the plot is left alone", function()
  world()
  SIM.block(21, 45, 4, "ae2:cable_bus")
  SIM.receive(99, JOB, "swarm_job")
  local m = miner({ fuelTarget = 100, patience = 2 })
  start(7, 52, 0)
  m.work(2)
  eq(SIM.getBlock(21, 45, 4), "ae2:cable_bus", "not dug")
  eq(textutils.unserialize(SIM.files[".miner"]).phase, "finish", "the rest of the plot was still done")
end, { x = 7, y = 52, z = 0, f = 0, fuel = 5000 })

test("near the surface it never digs: a miner set down in the factory waits", function()
  world()
  SIM.fill(0, 69, -4, 30, 69, 12, "minecraft:gray_concrete")  -- a factory floor
  SIM.receive(99, JOB, "swarm_job")
  local m = miner({ fuelTarget = 100, patience = 1 })
  start(15, 70, 3)
  local okRun, err = pcall(m.work, 2)
  eq(okRun, false, "gave up (with patience 1)")
  has(tostring(err), "protected:minecraft:gray_concrete", "said why")
  eq(SIM.getBlock(15, 69, 3), "minecraft:gray_concrete", "floor untouched")
  eq(#SIM.dug, 0, "nothing dug at all")
end, { x = 15, y = 70, z = 3, f = 0, fuel = 5000 })

test("even plain stone is not dug up there", function()
  world()
  SIM.fill(0, 69, -4, 30, 69, 12, "minecraft:stone")
  SIM.receive(99, JOB, "swarm_job")
  local m = miner({ fuelTarget = 100, patience = 1 })
  start(15, 70, 3)
  local okRun, err = pcall(m.work, 2)
  eq(okRun, false)
  has(tostring(err), "blocked:minecraft:stone", "said why")
  eq(#SIM.dug, 0, "nothing dug at all")
end, { x = 15, y = 70, z = 3, f = 0, fuel = 5000 })

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
  ok(droppedDown() > 0, "it passed the dock on the way")
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
