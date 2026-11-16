-- install.lua : one-time setup for a turtle or the controller computer.
-- Run:  wget run https://raw.githubusercontent.com/KyleATRYZE/turtles/main/install.lua
local BASE = "https://raw.githubusercontent.com/KyleATRYZE/turtles/main/"

-- Never touch a GPS host: replacing its startup would break GPS for everyone.
if not turtle and fs.exists("startup.lua") then
  local h = fs.open("startup.lua", "r")
  local existing = h.readAll()
  h.close()
  if existing:find("gps", 1, true) then
    print("This is a GPS computer. Leave it as it is.")
    print("Run the installer on turtles and on the controller only.")
    return
  end
end

local r, err = http.get(BASE .. "update.lua?t=" .. os.epoch("utc"))
if not r then
  print("Download failed: " .. tostring(err))
  return
end
local h = fs.open("update.lua", "w")
h.write(r.readAll())
h.close()
r.close()

-- update.lua downloads everything and writes the right startup.lua
-- for this machine (miner, factory or controller).
shell.run("update")

if not turtle and not os.getComputerLabel() then
  os.setComputerLabel("controller")
end
print("Installed. Rebooting...")
sleep(2)
os.reboot()
