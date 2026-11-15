-- update.lua : download the latest scripts from GitHub.
-- Runs on every boot (from startup.lua). Safe to run by hand: update
local BASE = "https://raw.githubusercontent.com/KyleATRYZE/turtles/main/"

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
