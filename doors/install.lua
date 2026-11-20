-- Installs a door program and makes it start on boot.
--   wget run https://raw.githubusercontent.com/KyleATRYZE/turtles/main/doors/install.lua entrance
--   wget run https://raw.githubusercontent.com/KyleATRYZE/turtles/main/doors/install.lua baydoor
local which = ...
if which ~= "entrance" and which ~= "baydoor" then error("Usage: install entrance|baydoor") end
local url = "https://raw.githubusercontent.com/KyleATRYZE/turtles/main/doors/" .. which .. ".lua"
local r = http.get(url)
if not r then error("Could not download " .. url) end
local h = fs.open(which .. ".lua", "w"); h.write(r.readAll()); h.close(); r.close()
h = fs.open("startup.lua", "w"); h.write('shell.run("' .. which .. '")\n'); h.close()
os.setComputerLabel(which == "entrance" and "EntranceDoor" or "BayDoor")
print("Installed " .. which .. ". Rebooting...")
sleep(1)
os.reboot()
