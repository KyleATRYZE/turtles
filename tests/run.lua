-- tests/run.lua: run the tests with any plain Lua (5.1-5.4) or LuaJIT, from the kit folder:
--
--   lua tests/run.lua tests/*.test.lua
--
-- (No Lua installed? Use  python tests/run_tests.py  instead, it needs `pip install lupa`.)

package.path = "./?.lua;" .. package.path
dofile("sim/sim.lua")
dofile("tests/t.lua")

local files = { ... }
if #files == 0 then
  print("usage: lua tests/run.lua tests/*.test.lua")
  os.exit(2)
end

local total_fail = 0
for _, f in ipairs(files) do
  T.passed, T.failed, T.fails = 0, 0, {}
  dofile(f)
  io.write(string.format("%-28s %d passed, %d failed\n", f, T.passed, T.failed))
  for _, msg in ipairs(T.fails) do io.write("    FAIL " .. msg .. "\n") end
  total_fail = total_fail + T.failed
end
io.write(total_fail == 0 and "ALL PASSED\n" or ("FAILED: " .. total_fail .. "\n"))
os.exit(total_fail == 0 and 0 or 1)
