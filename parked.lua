--- parked.lua: for a turtle or computer whose old job is gone (helpers, builders, loaders,
-- the old factory and storage machines). It stays where it is, says so once a minute, and
-- takes two orders: reboot (rev = a commit to load) and ping.

local net = require("lib.net")

local role = "parked"
if fs.exists(".role") then
  local h = fs.open(".role", "r")
  role = (h.readAll() or ""):gsub("%s", "")
  h.close()
end

local function report()
  local status = { role = role, state = "parked", log = { "Parked: no job in the rebuilt plant." } }
  if turtle then status.fuel = turtle.getFuelLevel() end
  local ok, x, y, z = pcall(gps.locate, 2)
  if ok and x then
    status.pos = { x = math.floor(x + 0.5), y = math.floor(y + 0.5), z = math.floor(z + 0.5) }
  end
  net.report(status)
end

print("Parked: no job in the rebuilt plant.")
print("(Orders taken: reboot, ping.)")
local nextReport = 0
while true do
  if os.clock() >= nextReport then
    report()
    nextReport = os.clock() + 60
  end
  local cmd = net.nextOrder(5)
  if cmd and cmd.cmd == "reboot" then
    net.pinVersion(cmd)
    net.report({ role = role, state = "rebooting" })
    sleep(1)
    os.reboot()
  elseif cmd and cmd.cmd == "ping" then
    nextReport = 0
  end
end
