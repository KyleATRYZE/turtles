-- lib/log.lua

test("lines go to /logs/<name>.log", function()
  local log = require("lib.log")
  log.setup({ name = "miner", echo = false })
  log.info("dug %d blocks", 12)
  log.warn("low fuel")
  has(SIM.files["logs/miner.log"], "INFO dug 12 blocks")
  has(SIM.files["logs/miner.log"], "WARN low fuel")
end)

test("the log rolls over at maxBytes", function()
  local log = require("lib.log")
  log.setup({ name = "big", echo = false, maxBytes = 200 })
  for i = 1, 30 do log.info("line number %d with some padding", i) end
  ok(SIM.files["logs/big.log.old"], "old log kept")
  ok(#SIM.files["logs/big.log"] <= 260, "current log stays small")
end)

test("run() turns a crash into a report", function()
  local log = require("lib.log")
  local got
  log.setup({ name = "t", echo = false, onCrash = function(r) got = r end })
  log.info("about to fail")
  local done, err = log.run(function() local x = nil return x.field end)
  eq(done, false)
  has(tostring(err), "attempt to index")
  ok(got, "onCrash called")
  has(got.recent[1], "about to fail")
  has(SIM.files["logs/crash.txt"], "attempt to index")
end)

test("run() passes arguments and return values through", function()
  local log = require("lib.log")
  log.setup({ echo = false })
  local done, a, b = log.run(function(x, y) return x + y, "ok" end, 2, 3)
  eq(done, true) eq(a, 5) eq(b, "ok")
end)

test("Ctrl+T is not reported as a crash", function()
  local log = require("lib.log")
  local crashed = false
  log.setup({ echo = false, onCrash = function() crashed = true end })
  local done, err = log.run(function() error("Terminated", 0) end)
  eq(done, false) eq(err, "Terminated") eq(crashed, false)
end)

test("watchdog calls onStuck once when progress stops", function()
  local log = require("lib.log")
  log.setup({ echo = false })
  local calls = 0
  local dog = log.watchdog(60, function() calls = calls + 1 end, 10, 12)
  dog()                                  -- 12 checks x 10 s = 120 s, no progress
  eq(calls, 1, "one warning per stall")
end)

test("watchdog stays quiet while progress is made", function()
  local log = require("lib.log")
  log.setup({ echo = false })
  local calls = 0
  local realSleep = sleep
  sleep = function(s) realSleep(s) log.progress() end   -- progress every check
  local dog = log.watchdog(15, function() calls = calls + 1 end, 10, 10)
  dog()
  sleep = realSleep
  eq(calls, 0)
end)
