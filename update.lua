-- update.lua : download the latest scripts from GitHub.
-- Runs on every boot (from startup.lua). Safe to run by hand: update
local REPO = "KyleATRYZE/turtles"

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

local manifest, err = get("manifest.txt")
if not manifest then
  print("Update skipped: " .. tostring(err))
  return
end

for line in manifest:gmatch("[^\r\n]+") do
  local name = line:match("^%s*(.-)%s*$")
  if name ~= "" then
    local s = get(name)
    if not s or #s == 0 then
      print("Could not download " .. name)
    elseif name:match("%.lua$") and not load(s, name) then
      -- never replace a working script with one that does not compile
      print("Skipped " .. name .. " (broken upload)")
    elseif readFile(name) ~= s then
      local h = fs.open(name, "w")
      h.write(s)
      h.close()
      print("Updated " .. name)
    end
  end
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
  and role ~= "loader" then
  if not turtle then
    role = "controller"
  elseif (os.getComputerLabel() or ""):match("^factory") then
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
else
  job = 'shell.run("miner", "resume")'
end
local wanted = 'shell.run("update")\n' .. job .. '\n'
local current = readFile("startup.lua")
-- never touch a GPS host
if current ~= wanted and not (current and current:find("gps", 1, true)) then
  local h = fs.open("startup.lua", "w")
  h.write(wanted)
  h.close()
  print("Startup set: " .. job)
end
