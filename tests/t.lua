-- tests/t.lua: a tiny test framework. Every test gets a fresh simulated world and fresh
-- copies of the lib modules (so saved positions etc. don't leak between tests).

T = { passed = 0, failed = 0, fails = {} }

local function fresh()
  for name in pairs(package.loaded) do
    if name:match("^lib%.") or name:match("^examples%.") then package.loaded[name] = nil end
  end
end

function test(name, fn, simOpts)
  SIM.reset(simOpts)
  fresh()
  local ok, err = pcall(fn)
  if ok then
    T.passed = T.passed + 1
  else
    T.failed = T.failed + 1
    T.fails[#T.fails + 1] = name .. ": " .. tostring(err)
  end
end

function eq(got, want, what)
  if got ~= want then
    error((what or "value") .. ": expected " .. tostring(want) .. ", got " .. tostring(got), 2)
  end
end

function ok(v, what)
  if not v then error((what or "expected true") .. " (got " .. tostring(v) .. ")", 2) end
  return v
end

function has(s, part, what)
  if type(s) ~= "string" or not s:find(part, 1, true) then
    error((what or "text") .. ": expected to contain '" .. part .. "', got " .. tostring(s), 2)
  end
end
