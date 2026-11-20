-- Factory launch-bay lift door (20 Nov 2026).
-- An 11 x 9 industrial-iron leaf (x -4389, z 1538..1548, y 71..79), Super Glued in game, hangs on a Create
-- rope pulley at -4389 92 1543. A Sequenced Gearshift at -4390 92 1543 (fed from the headframe's motor)
-- turns the pulley an exact number of blocks. This computer sits on the gearshift with a Player Detector
-- on top, and opens the door when a player is on the apron outside or just inside the bay.
--
-- Commands:  baydoor            run (the startup does this)
--            baydoor setup      one-time: lower the rope onto the glued leaf (after gluing it)
--            baydoor open|close move it by hand
-- Settings:  baydoor.lift   blocks the leaf rises (default 11)
--            baydoor.up     1 or -1: which way the gearshift turns to lift (flip it if the door goes the wrong way)

local gear = peripheral.find("Create_SequencedGearshift")
local det = peripheral.find("playerDetector")
if not gear then error("No Sequenced Gearshift next to this computer") end

local LIFT = tonumber(settings.get("baydoor.lift")) or 11
local UP = tonumber(settings.get("baydoor.up")) or 1
local STATE = "baydoor.state"

-- the apron outside the door and the first few blocks inside (world coordinates)
local ZONE = { { x = -4393, y = 69, z = 1535 }, { x = -4383, y = 80, z = 1551 } }

local function readState()
  if not fs.exists(STATE) then return "closed" end
  local h = fs.open(STATE, "r"); local s = h.readLine(); h.close(); return s or "closed"
end
local function writeState(s) local h = fs.open(STATE, "w"); h.writeLine(s); h.close() end

local function waitGear() repeat sleep(0.2) until not gear.isRunning() end
local function move(blocks, dir) gear.move(blocks, dir); waitGear() end

local function someoneThere()
  if not det then return false end
  local ok, names = pcall(det.getPlayersInCoords, ZONE[1], ZONE[2])
  if ok and type(names) == "table" then return #names > 0 end
  local ok2, near = pcall(det.isPlayersInRange, 22)      -- older Advanced Peripherals: plain range
  return ok2 and near == true
end

local function open()
  if readState() == "open" then return end
  move(LIFT, UP); writeState("open"); print("open")
end
local function close()
  if readState() == "closed" then return end
  move(LIFT, -UP); writeState("closed"); print("closed")
end

local cmd = ...
if cmd == "setup" then
  print("Lowering the rope onto the leaf (" .. LIFT .. " blocks)...")
  move(LIFT, -UP); writeState("closed"); print("Done. The door is closed; run 'baydoor open' to test.")
  return
elseif cmd == "open" then open(); return
elseif cmd == "close" then close(); return
end

term.clear(); term.setCursorPos(1, 1)
print("Bay door. Lift " .. LIFT .. ", up " .. UP .. ". State: " .. readState())
local lastSeen = 0
while true do
  local there = someoneThere()
  if there then lastSeen = os.clock(); open()
  elseif os.clock() - lastSeen > 5 then close() end
  sleep(0.5)
end
