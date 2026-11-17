-- update.lua : download the latest scripts from GitHub.
-- Runs on every boot (from startup.lua). Safe to run by hand: update
local REPO = "KyleATRYZE/turtles"

-- Boot heartbeat (turtles): say where we are before the download, which can
-- be slow or fail. See swarm.hello.
if turtle then
  pcall(function()
    local role
    if fs.exists(".role") then
      local h = fs.open(".role", "r")
      role = h.readAll():gsub("%s", "")
      h.close()
    end
    local swarm = require("swarm")
    if swarm.hello then swarm.hello(role) end
  end)
end

-- Work out exactly which version to download. GitHub's file server can serve
-- a copy up to five minutes old for "main", so we ask for a precise commit.
local function latestRev()
  -- 1. pinned by a remote reboot order
  if fs.exists(".rev") then
    local h = fs.open(".rev", "r")
    local rev = h.readAll():gsub("%s", "")
    h.close()
    fs.delete(".rev")
    if #rev == 40 and rev:match("^%x+$") then return rev end
  end
  -- 2. ask GitHub which commit is newest
  if http then
    local r = http.get({
      url = "https://api.github.com/repos/" .. REPO .. "/commits/main",
      headers = {
        ["Accept"] = "application/vnd.github.sha",
        ["User-Agent"] = "cc-turtle-updater",
      },
    })
    if r then
      local rev = r.readAll():gsub("%s", "")
      r.close()
      if #rev == 40 and rev:match("^%x+$") then return rev end
    end
  end
  -- 3. fall back to whatever "main" gives us
  return "main"
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

local function readFile(name)
  if not fs.exists(name) then return nil end
  local h = fs.open(name, "r")
  local s = h.readAll()
  h.close()
  return s
end

-- Turtles have little disk: a helper or miner has no use for the factory's
-- or the controller's programs (a helper ran out of space on factory.lua).
local early = readFile(".role")
early = early and early:gsub("%s", "") or nil
local ONLY = {
  factory    = { ["controller.lua"] = true, ["dash.lua"] = true, ["sortnado.lua"] = true, ["screens.lua"] = true,
                 ["rack.lua"] = true, ["works.lua"] = true },
  helper     = { ["factory.lua"] = true, ["controller.lua"] = true, ["dash.lua"] = true, ["sortnado.lua"] = true,
                 ["screens.lua"] = true, ["builder.lua"] = true, ["rack.lua"] = true, ["works.lua"] = true },
  miner      = { ["factory.lua"] = true, ["controller.lua"] = true, ["dash.lua"] = true, ["sortnado.lua"] = true,
                 ["screens.lua"] = true, ["builder.lua"] = true, ["foundry.lua"] = true, ["rack.lua"] = true, ["works.lua"] = true },
  loader     = { ["factory.lua"] = true, ["controller.lua"] = true, ["dash.lua"] = true, ["sortnado.lua"] = true,
                 ["screens.lua"] = true, ["builder.lua"] = true, ["foundry.lua"] = true, ["rack.lua"] = true, ["works.lua"] = true },
  builder    = { ["factory.lua"] = true, ["controller.lua"] = true, ["dash.lua"] = true, ["sortnado.lua"] = true,
                 ["screens.lua"] = true, ["foundry.lua"] = true, ["rack.lua"] = true, ["works.lua"] = true },
}
local skipFor = early and ONLY[early] or {}
local manifest, err = get("manifest.txt")
if not manifest then
  print("Update skipped: " .. tostring(err))
  return
end

local notes = {}
for line in manifest:gmatch("[^\r\n]+") do
  local name = line:match("^%s*(.-)%s*$")
  if name ~= "" and skipFor[name] then
    -- not needed here: free its space
    if fs.exists(name) then fs.delete(name) end
  elseif name ~= "" then
    local s = get(name)
    if not s or #s == 0 then
      print("Could not download " .. name)
      notes[#notes + 1] = "no download: " .. name .. " (" .. tostring(s and #s or "nil") .. ")"
    elseif name:match("%.lua$") and not load(s, name) then
      -- never replace a working script with one that does not compile
      print("Skipped " .. name .. " (broken upload)")
      local _, why = load(s, name)
      notes[#notes + 1] = "no compile: " .. name .. " " .. #s .. " bytes: " .. tostring(why)
    elseif readFile(name) ~= s then
      local ok, why = pcall(function()
        local h = fs.open(name, "w")
        h.write(s)
        h.close()
      end)
      if ok and readFile(name) == s then
        print("Updated " .. name)
      else
        print("Could not write " .. name .. ": " .. tostring(why))
        notes[#notes + 1] = "no write: " .. name .. " " .. #s .. " bytes, free " .. tostring(fs.getFreeSpace("/")) .. ": " .. tostring(why)
      end
    end
  end
end

do
  local h = fs.open(".update_log", "w")
  h.write(table.concat(notes, "\n"))
  h.close()
end
-- Record which version this machine is running (shown in status reports).
do
  local h = fs.open(".version", "w")
  h.write(REV:sub(1, 7))
  h.close()
end
print("Version " .. REV:sub(1, 7))

-- Keep startup.lua correct for this machine's job, so a change of job never
-- needs the installer to be run again.
-- What this machine is: remembered in .role (so it can be renamed freely);
-- worked out from the label the first time.
local role = readFile(".role")
if role then role = role:gsub("%s", "") end
if role ~= "controller" and role ~= "factory" and role ~= "miner" and role ~= "builder"
  and role ~= "loader" and role ~= "helper" and role ~= "storage" and role ~= "screen" and role ~= "rack"
  and role ~= "works" then
  if not turtle and (os.getComputerLabel() or ""):lower():match("^sortnado") then
    role = "storage"
  elseif not turtle then
    role = "controller"
  elseif (os.getComputerLabel() or ""):match("^factory") or (os.getComputerLabel() or ""):lower():match("^counter") then
    role = "factory"
  elseif (os.getComputerLabel() or ""):lower():match("^loader") then
    role = "loader"
  else
    role = "miner"
  end
  local h = fs.open(".role", "w")
  h.write(role)
  h.close()
end
local job
if role == "controller" then
  job = 'shell.run("controller")'
elseif role == "factory" then
  job = 'shell.run("factory")'
elseif role == "builder" then
  job = 'shell.run("builder")'
elseif role == "loader" then
  job = 'shell.run("loader")'
elseif role == "helper" then
  job = 'shell.run("helper")'
elseif role == "storage" then
  job = 'shell.run("sortnado")'
elseif role == "screen" then
  job = 'shell.run("screens")'
elseif role == "rack" then
  job = 'shell.run("rack")'
elseif role == "works" then
  job = 'shell.run("works")'
else
  job = 'shell.run("miner", "resume")'
end
-- (mirror.lua keeps a copy of the screen for the status reports; if the
-- job ever stops, what is on the screen goes to the base, then a restart)
local wanted = 'pcall(dofile, "mirror.lua")\nshell.run("update")\n' .. job .. '\n'
  .. 'pcall(function()\n'
  .. '  local r = fs.open(".role", "r")\n'
  .. '  local role = r and r.readAll() or "?"\n'
  .. '  if r then r.close() end\n'
  .. '  require("swarm").report({ role = role, state = "stopped", screen = _G.SCREEN_MIRROR and _G.SCREEN_MIRROR(16) })\n'
  .. 'end)\n'
  .. 'print("Stopped. Restarting in 2 minutes (hold Ctrl+T to stay).")\n'
  .. 'sleep(120)\nos.reboot()\n'
local current = readFile("startup.lua")
-- never touch a GPS host
if current ~= wanted and not (current and current:find("gps", 1, true)) then
  local h = fs.open("startup.lua", "w")
  h.write(wanted)
  h.close()
  print("Startup set: " .. job)
end
