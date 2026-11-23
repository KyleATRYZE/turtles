-- lib/net.lua: reports, orders and plot requests in the controller's message shapes.

local function modem()
  SIM.peripherals.right = { types = { "modem" }, methods = { isWireless = function() return true end } }
end

test("no wireless modem: nothing is sent and nothing breaks", function()
  local net = require("lib.net")
  eq(net.open(), false)
  eq(net.report({ role = "miner", state = "x" }), false)
  eq(#SIM.sent, 0)
end)

test("a wired modem does not count", function()
  SIM.peripherals.back = { types = { "modem" }, methods = { isWireless = function() return false end } }
  eq(require("lib.net").open(), false)
end)

test("a report carries who sent it and which version it runs", function()
  modem()
  SIM.files[".version"] = "abc1234\n"
  local net = require("lib.net")
  ok(net.report({ role = "miner", state = "mining" }))
  local to, msg, protocol = SIM.sent[1][1], SIM.sent[1][2], SIM.sent[1][3]
  eq(to, "all") eq(protocol, "swarm")
  eq(msg.id, 5) eq(msg.label, "miner5") eq(msg.version, "abc1234") eq(msg.state, "mining")
end, { id = 5, label = "miner5" })

test("an order is taken once, and only when it is for this machine", function()
  modem()
  local net = require("lib.net")
  eq(net.accept({ id = 10, cmd = "stop", target = "miner9" }), false, "someone else's")
  eq(net.accept({ id = 10, cmd = "stop", target = "MINER5" }), true, "by name, any case")
  eq(net.accept({ id = 10, cmd = "stop", target = "miner5" }), false, "a repeat")
  eq(net.accept({ id = 11, cmd = "stop", target = 5 }), true, "by number")
  eq(net.accept({ id = 12, cmd = "stop", target = "all" }), true, "to everyone")
  eq(net.accept({ id = 9, cmd = "stop", target = "all" }), false, "an older one")
  eq(net.accept("stop"), false, "not a table")
  eq(SIM.files[".lastcmd"], "12", "remembered across restarts")
end, { id = 5, label = "miner5" })

test("nextOrder returns the order, or nil when none came", function()
  modem()
  local net = require("lib.net")
  SIM.receive(7, { id = 20, cmd = "resume", target = "all" }, "swarm_cmd")
  local cmd = net.nextOrder(1)
  eq(cmd and cmd.cmd, "resume")
  eq(net.nextOrder(1), nil)
end, { id = 5, label = "miner5" })

test("asking for a plot: takes the answer meant for it, ignores others", function()
  modem()
  local net = require("lib.net")
  SIM.receive(7, { type = "job", forId = 6, index = 1 }, "swarm_job")
  SIM.receive(7, { type = "job", forId = 5, index = 2, x0 = 1, z0 = 2 }, "swarm_job")
  local job = net.requestJob(3)
  eq(job and job.index, 2)
  eq(SIM.sent[1][2].type, "need_job") eq(SIM.sent[1][2].id, 5) eq(SIM.sent[1][3], "swarm_job")
  eq(net.requestJob(2), nil, "nothing on offer")
  net.jobDone(2)
  local last = SIM.sent[#SIM.sent][2]
  eq(last.type, "job_done") eq(last.index, 2)
end, { id = 5, label = "miner5" })

test("only a full commit id is pinned by a reboot order", function()
  local net = require("lib.net")
  net.pinVersion({ rev = "main" })
  eq(SIM.files[".rev"], nil)
  net.pinVersion({ rev = ("0123456789abcdef"):rep(2) .. "01234567" })
  eq(#SIM.files[".rev"], 40)
end)
