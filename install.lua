-- install.lua : one-time setup for a turtle.
-- Run:  wget run https://raw.githubusercontent.com/KyleATRYZE/turtles/main/install.lua
local BASE = "https://raw.githubusercontent.com/KyleATRYZE/turtles/main/"

local r, err = http.get(BASE .. "update.lua?t=" .. os.epoch("utc"))
if not r then
  print("Download failed: " .. tostring(err))
  return
end
local h = fs.open("update.lua", "w")
h.write(r.readAll())
h.close()
r.close()

-- On every boot: fetch the latest scripts, then carry on with any saved job.
h = fs.open("startup.lua", "w")
h.write('shell.run("update")\nshell.run("miner", "resume")\n')
h.close()

shell.run("update")

if fs.exists("miner.state") then
  print("Installed. Rebooting to resume the saved job...")
  sleep(2)
  os.reboot()
else
  print("Installed. Start a job with:  miner <size>")
end
