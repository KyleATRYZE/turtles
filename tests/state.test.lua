-- lib/state.lua

test("save and load round trip", function()
  local state = require("lib.state")
  ok(state.save("/.job", { done = 3, name = "plot 4", list = { 1, 2 } }))
  local s = state.load("/.job")
  eq(s.done, 3) eq(s.name, "plot 4") eq(s.list[2], 2)
  eq(SIM.files[".job.tmp"], nil, "temp file cleaned up")
end)

test("missing file gives the default", function()
  local state = require("lib.state")
  eq(state.load("/.nothing", { n = 7 }).n, 7)
end)

test("a broken file gives the default and is kept as .bad", function()
  SIM.files[".job"] = "{ done = "
  local state = require("lib.state")
  eq(state.load("/.job", { done = 0 }).done, 0)
  eq(SIM.files[".job.bad"], "{ done = ")
end)

test("power cut mid-save: the .tmp copy is used", function()
  SIM.files[".job.tmp"] = "{ done = 9 }"    -- main file already deleted, swap not finished
  local state = require("lib.state")
  eq(state.load("/.job").done, 9)
end)

test("update changes and saves in one go", function()
  local state = require("lib.state")
  state.update("/.count", function(t) t.n = (t.n or 0) + 1 end)
  state.update("/.count", function(t) t.n = t.n + 1 end)
  eq(state.load("/.count").n, 2)
end)
