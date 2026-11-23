-- lib/agent.lua

local function agentWith(opts)
  local agent = require("lib.agent")
  local o = { secret = "s3cret" }
  for k, v in pairs(opts or {}) do o[k] = v end
  agent.setup(o)
  return agent
end

test("exec captures printed output and return values", function()
  local agent = agentWith()
  local r = agent.handle({ cmd = "exec", code = "print('fuel', turtle.getFuelLevel()) return 1 + 1, 'x'" })
  eq(r.ok, true)
  has(r.out, "fuel\t1000")
  has(r.ret, "2")
  has(r.ret, '"x"')
  eq(r.from, 1)
end)

test("exec reports syntax and runtime errors without crashing", function()
  local agent = agentWith()
  local r1 = agent.handle({ cmd = "exec", code = "print(" })
  eq(r1.ok, false) ok(r1.err, "syntax error text")
  local r2 = agent.handle({ cmd = "exec", code = "error('boom')" })
  eq(r2.ok, false) has(r2.err, "boom")
end)

test("output is cut at maxOutput", function()
  local agent = agentWith({ maxOutput = 50 })
  local r = agent.handle({ cmd = "exec", code = "for i = 1, 100 do print('line ' .. i) end" })
  has(r.out, "(output cut)")
  ok(#r.out < 100, "short output")
end)

test("run executes a program file with arguments", function()
  SIM.files["hello.lua"] = "local a, b = ... print('hi ' .. a .. b) return 'done'"
  local agent = agentWith()
  local r = agent.handle({ cmd = "run", path = "hello.lua", args = { "kyle", "!" } })
  eq(r.ok, true) has(r.out, "hi kyle!") has(r.ret, "done")
end)

test("ping, tail and dump", function()
  SIM.files["logs/miner.log"] = "one\ntwo\nthree\nfour\n"
  SIM.peripherals["left"] = { types = { "modem" }, methods = { open = function() end, isWireless = function() end } }
  local agent = agentWith({ status = function() return { job = "plot 4" } end })
  local p = agent.handle({ cmd = "ping" })
  has(p.ret, "freeDisk") has(p.ret, "plot 4")
  local t = agent.handle({ cmd = "tail", name = "miner", lines = 2 })
  eq(t.out, "three\nfour")
  local d = agent.handle({ cmd = "dump" })
  has(d.ret, "isWireless") has(d.ret, "modem")
end)

test("unknown and disallowed commands are refused", function()
  local agent = agentWith({ allow = { ping = true } })
  eq(agent.handle({ cmd = "exec", code = "return 1" }).ok, false)
  eq(agent.handle({ cmd = "format_disk" }).ok, false)
end)

test("queue arguments need the secret", function()
  local agent = agentWith()
  local o, err = agent.fromArgs({ "wrong", "ping" })
  eq(o, nil) eq(err, "bad secret")
  local o2 = agent.fromArgs({ "s3cret", "exec", "print(1)", "print(2)" })
  eq(o2.cmd, "exec") eq(o2.code, "print(1) print(2)")
  package.loaded["lib.agent"] = nil
  local open = require("lib.agent")
  local o3, err3 = open.fromArgs({ "x", "ping" })
  eq(o3, nil) has(err3, "no secret")
end)

test("serveCommands: a queued command runs and the result is delivered", function()
  local results = {}
  local agent = agentWith({ onResult = function(r) results[#results + 1] = r end })
  SIM.queue("computer_command", "s3cret", "exec", "return", "6*7")
  SIM.queue("computer_command", "guess", "ping")
  agent.serveCommands(2)
  eq(#results, 2)
  eq(results[1].ok, true) has(results[1].ret, "42")
  eq(results[2].ok, false) eq(results[2].err, "bad secret")
  has(SIM.files["logs/agent-last.txt"], "bad secret")
end)

test("serveCommands relay: passes the order on over rednet and waits for the answer", function()
  local results = {}
  local agent = agentWith({ onResult = function(r) results[#results + 1] = r end })
  -- the target turtle (id 12) answers whatever it is sent
  local realReceive = rednet.receive
  rednet.receive = function(protocol)
    local last = SIM.sent[#SIM.sent]
    local order = last[2].order
    return 12, { result = { id = order.id, ok = true, ret = "{ 1500 }", from = 12 } }, protocol
  end
  SIM.queue("computer_command", "s3cret", "relay", "12", "exec", "return", "turtle.getFuelLevel()")
  agent.serveCommands(1)
  rednet.receive = realReceive
  eq(SIM.sent[1][1], 12, "sent to turtle 12")
  eq(SIM.sent[1][2].order.code, "return turtle.getFuelLevel()")
  eq(SIM.sent[1][2].secret, "s3cret")
  eq(results[1].from, 12) eq(results[1].ret, "{ 1500 }")
end)

test("serveRednet: answers good orders, ignores ones without the secret, reboots last", function()
  local agent = agentWith()
  SIM.receive(7, { secret = "nope", order = { cmd = "exec", code = "return 1" } }, "dev_agent")
  SIM.receive(7, { secret = "s3cret", order = { id = "a1", cmd = "exec", code = "return 5" } }, "dev_agent")
  SIM.receive(7, { secret = "s3cret", order = { id = "a2", cmd = "reboot" } }, "dev_agent")
  agent.serveRednet(3)
  eq(#SIM.sent, 2, "two answers")
  eq(SIM.sent[1][2].result.id, "a1")
  has(SIM.sent[1][2].result.ret, "5")
  eq(SIM.rebooted, true)
end)

test("serving without a secret is refused", function()
  local agent = require("lib.agent")
  local done, err = pcall(agent.serveRednet, 1)
  eq(done, false) has(err, "secret")
end)
