-- Factory main entrance (20 Nov 2026): Create framed-glass sliding doors that open for players.
-- Computer at -4429 71 1551 (beside the doors), Player Detector at -4430 71 1551.
-- The doors take a redstone signal from the computer's side; the computer simply powers every side.
--
-- Settings (type `set <name> <value>` in the shell):
--   entrance.range   blocks from the detector that count as "approaching" (default 6)
--   entrance.hold    seconds the doors stay open after the last player leaves (default 3)
--   entrance.only    comma-separated player names allowed in (default: everyone)

local det = peripheral.find("playerDetector")
if not det then error("No Player Detector next to this computer") end

local RANGE = tonumber(settings.get("entrance.range")) or 6
local HOLD = tonumber(settings.get("entrance.hold")) or 3
local ONLY = settings.get("entrance.only")

local allowed
if type(ONLY) == "string" and ONLY ~= "" then
  allowed = {}
  for name in ONLY:gmatch("[^,%s]+") do allowed[name:lower()] = true end
end

local function someoneNear(r)
  local ok, names = pcall(det.getPlayersInRange, r)
  if not ok or type(names) ~= "table" then return false end
  for _, n in ipairs(names) do
    if not allowed or allowed[tostring(n):lower()] then return true end
  end
  return false
end

local function setDoors(open)
  for _, side in ipairs(rs.getSides()) do rs.setOutput(side, open) end
end

local isOpen, lastSeen = false, 0
setDoors(false)
term.clear(); term.setCursorPos(1, 1)
print("Entrance doors. Range " .. RANGE .. ", hold " .. HOLD .. "s" .. (allowed and " (allow-list on)" or ""))

while true do
  local near = someoneNear(RANGE)
  if near then lastSeen = os.clock() end
  if near and not isOpen then
    setDoors(true); isOpen = true
    print(textutils.formatTime(os.time(), true) .. " open")
  elseif isOpen and not near and os.clock() - lastSeen >= HOLD and not someoneNear(2) then
    setDoors(false); isOpen = false
    print(textutils.formatTime(os.time(), true) .. " closed")
  end
  sleep(0.5)
end
