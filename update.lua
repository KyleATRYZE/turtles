-- update.lua : download this machine's scripts from GitHub.
-- Runs on every boot (from startup.lua). Safe to run by hand: update
--
-- Each machine only gets the files its job needs. files.txt lists them:
--     path  role[,role...]        roles: all, controller, screen, miner, parked
-- A machine's job is in .role. The old jobs that no longer exist (helper, builder,
-- loader, factory, storage, rack, works) all become "parked".
local REPO = "KyleATRYZE/turtles"
local BRANCH = "clean-rebuild"     -- the branch this copy follows ("main" once merged)

local function readFile(name)
  if not fs.exists(name) then return nil end
  local h = fs.open(name, "r")
  local s = h.readAll()
  h.close()
  return s
end

local function writeFile(name, text)
  local dir = fs.getDir(name)
  if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
  local h = fs.open(name, "w")
  h.write(text)
  h.close()
end

-- What this machine is: remembered in .role; worked out the first time.
local role = (readFile(".role") or ""):gsub("%s", "")
if role == "" then
  role = turtle and "miner" or "controller"
  writeFile(".role", role)
end
local CLASS = { controller = "controller", screen = "screen", miner = "miner" }
local class = CLASS[role] or "parked"
local JOB = { controller = "controller", screen = "screens", miner = "miner", parked = "parked" }

-- Boot heartbeat: say we are awake before the download, which can be slow or fail.
pcall(function()
  if fs.exists("lib/net.lua") then
    require("lib.net").report({ role = role, state = "woke up", fuel = turtle and turtle.getFuelLevel() or nil })
  end
end)

-- Which version to download. GitHub's file server can serve a copy up to five minutes
-- old for a branch name, so ask for the exact commit.
local function latestRev()
  local pinned = readFile(".rev")                 -- 1. pinned by a remote reboot order
  if pinned then
    fs.delete(".rev")
    pinned = pinned:gsub("%s", "")
    if #pinned == 40 and pinned:match("^%x+$") then return pinned end
  end
  if http then                                    -- 2. ask GitHub which commit is newest
    local r = http.get({
      url = "https://api.github.com/repos/" .. REPO .. "/commits/" .. BRANCH,
      headers = { ["Accept"] = "application/vnd.github.sha", ["User-Agent"] = "cc-turtle-updater" },
    })
    if r then
      local rev = r.readAll():gsub("%s", "")
      r.close()
      if #rev == 40 and rev:match("^%x+$") then return rev end
    end
  end
  return BRANCH                                   -- 3. whatever the branch name gives
end

local REV = latestRev()
local BASE = "https://raw.githubusercontent.com/" .. REPO .. "/" .. REV .. "/"

local function get(name)
  if not http then return nil, "http is disabled" end
  local r, err = http.get(BASE .. name .. "?t=" .. os.epoch("utc"))
  if not r then return nil, err end
  local s = r.readAll()
  r.close()
  return s
end

local list, err = get("files.txt")
if not list then
  print("Update skipped: " .. tostring(err))
  return
end

-- Programs of the old plant: removed wherever they are still lying about.
local RETIRED = { "factory.lua", "helper.lua", "builder.lua", "loader.lua", "foundry.lua", "sortnado.lua",
  "rack.lua", "works.lua", "chatpc.lua" }

local notes, wanted = {}, {}
for line in list:gmatch("[^\r\n]+") do
  local name, roles = line:match("^%s*([^%s#]+)%s+([%w_,]+)%s*$")
  if name then
    local mine = false
    for r in roles:gmatch("[^,]+") do
      if r == "all" or r == class then mine = true end
    end
    if mine then
      wanted[name] = true
      local s = get(name)
      if not s or #s == 0 then
        print("Could not download " .. name)
        notes[#notes + 1] = "no download: " .. name
      elseif name:match("%.lua$") and not load(s, name) then
        -- never replace a working script with one that does not compile
        local _, why = load(s, name)
        print("Skipped " .. name .. " (broken upload)")
        notes[#notes + 1] = "no compile: " .. name .. ": " .. tostring(why)
      elseif readFile(name) ~= s then
        local ok, why = pcall(writeFile, name, s)
        if ok and readFile(name) == s then
          print("Updated " .. name)
        else
          print("Could not write " .. name .. ": " .. tostring(why))
          notes[#notes + 1] = "no write: " .. name .. " " .. #s .. " bytes, free " .. tostring(fs.getFreeSpace("/")) .. ": " .. tostring(why)
        end
      end
    elseif fs.exists(name) and name ~= "update.lua" then
      fs.delete(name)                             -- another job's file: free its space
    end
  end
end
for _, name in ipairs(RETIRED) do
  if not wanted[name] and fs.exists(name) then fs.delete(name) end
end
if class ~= "controller" and class ~= "screen" then
  for _, name in ipairs({ "swarm.lua", "dash.lua", "mirror.lua" }) do
    if not wanted[name] and fs.exists(name) then fs.delete(name) end
  end
end

writeFile(".update_log", table.concat(notes, "\n"))
writeFile(".version", REV:sub(1, 7))
print("Version " .. REV:sub(1, 7) .. " (" .. class .. ")")

-- Keep startup.lua right for this machine's job. If the job ever stops, wait two minutes
-- and restart (a crash has already been reported by then).
local job = JOB[class]
local startup
if class == "controller" or class == "screen" then
  startup = 'pcall(dofile, "mirror.lua")\nshell.run("update")\nshell.run("' .. job .. '")\n'
    .. 'pcall(function()\n'
    .. '  require("swarm").report({ role = "' .. role .. '", state = "stopped", screen = _G.SCREEN_MIRROR and _G.SCREEN_MIRROR(16) })\n'
    .. 'end)\n'
else
  startup = 'shell.run("update")\nshell.run("' .. job .. '")\n'
    .. 'pcall(function() require("lib.net").report({ role = "' .. role .. '", state = "stopped" }) end)\n'
end
startup = startup .. 'print("Stopped. Restarting in 2 minutes (hold Ctrl+T to stay).")\nsleep(120)\nos.reboot()\n'
local current = readFile("startup.lua")
if current ~= startup and not (current and current:find("gps", 1, true)) then   -- never touch a GPS host
  writeFile("startup.lua", startup)
  print("Startup set: " .. job)
end
