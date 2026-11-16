-- controller.lua : runs on the base computer (needs an ender modem).
-- Collects status reports from every turtle, shows them on screen,
-- and uploads them to GitHub so they can be read from outside the game.

local swarm = require("swarm")

local REPO       = "KyleATRYZE/turtles"
local BRANCH     = "status"
local FILE       = "status.json"
local TOKEN_FILE = ".github_token"
local INTERVAL   = 120   -- seconds between routine uploads
local MIN_GAP    = 20    -- never upload more often than this

local API = "https://api.github.com/repos/" .. REPO .. "/contents/" .. FILE
local ORDERS_API = "https://api.github.com/repos/" .. REPO
  .. "/contents/commands.json?ref=main"
local ORDER_POLL = 20          -- seconds between checks for new orders
local ORDER_LIFE = 5 * 60000   -- orders older than this (ms) are ignored

---------------------------------------------------------------- token

local function loadToken()
  if fs.exists(TOKEN_FILE) then
    local h = fs.open(TOKEN_FILE, "r")
    local t = h.readAll():gsub("%s+", "")
    h.close()
    if #t > 0 then return t end
  end
  print("Paste your GitHub token (Ctrl+V), then press Enter:")
  local t = read("*"):gsub("%s+", "")
  local h = fs.open(TOKEN_FILE, "w")
  h.write(t)
  h.close()
  return t
end

---------------------------------------------------------------- base64

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function b64(s)
  local out = {}
  for i = 1, #s, 3 do
    local a, b, c = s:byte(i, i + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    local c1 = math.floor(n / 262144) % 64
    local c2 = math.floor(n / 4096) % 64
    local c3 = math.floor(n / 64) % 64
    local c4 = n % 64
    out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
      .. (b and B64:sub(c3 + 1, c3 + 1) or "=")
      .. (c and B64:sub(c4 + 1, c4 + 1) or "=")
  end
  return table.concat(out)
end

---------------------------------------------------------------- state

local token
local units = {}        -- computer id (as text) -> latest report
local urgent = false    -- something changed that is worth uploading soon
local lastUpload = 0
local uploadNote = "not uploaded yet"
local orderNote = "no orders yet"
local sha               -- GitHub's id for the current status file

local function headers()
  return {
    ["Authorization"] = "Bearer " .. token,
    ["Accept"] = "application/vnd.github+json",
    ["User-Agent"] = "cc-turtle-controller",
    ["Content-Type"] = "application/json",
  }
end

local function fetchSha()
  local r = http.get({ url = API .. "?ref=" .. BRANCH, headers = headers() })
  if not r then return nil end
  local data = textutils.unserialiseJSON(r.readAll())
  r.close()
  return data and data.sha
end

local function upload()
  local doc = {
    updated = os.epoch("utc"),
    updatedText = os.date("!%Y-%m-%d %H:%M:%S UTC"),
    controller = { id = os.getComputerID(), label = os.getComputerLabel() },
    lastOrder = orderNote,
    units = units,
  }
  local okJson, json = pcall(textutils.serialiseJSON, doc)
  if not okJson then
    uploadNote = "could not build report: " .. tostring(json)
    return false
  end
  if not sha then sha = fetchSha() end
  local body = textutils.serialiseJSON({
    message = "status",
    branch = BRANCH,
    content = b64(json),
    sha = sha,
  })
  local r, err, failed = http.post({
    url = API, method = "PUT", headers = headers(), body = body,
  })
  if r then
    local data = textutils.unserialiseJSON(r.readAll())
    r.close()
    sha = data and data.content and data.content.sha or nil
    uploadNote = "uploaded " .. os.date("%H:%M:%S")
    return true
  end
  local code = failed and failed.getResponseCode()
  local reason
  if failed then
    -- GitHub explains the refusal in the response body
    local okBody, data = pcall(textutils.unserialiseJSON, failed.readAll())
    if okBody and type(data) == "table" then reason = data.message end
    failed.close()
  end
  sha = nil -- fetch a fresh one next time
  uploadNote = "upload failed (" .. tostring(code or err) .. "): "
    .. tostring(reason or err or "no reason given")
  return false
end

---------------------------------------------------------------- screen

local function draw()
  term.clear()
  term.setCursorPos(1, 1)
  print("Turtle controller  |  " .. uploadNote)
  print("Orders: " .. orderNote)
  print(("%-10s %-16s %-17s %s"):format("NAME", "STATE", "POSITION", "FUEL"))
  local ids = {}
  for id in pairs(units) do ids[#ids + 1] = id end
  table.sort(ids, function(a, b) return tonumber(a) < tonumber(b) end)
  local now = os.epoch("utc")
  for _, id in ipairs(ids) do
    local u = units[id]
    local p = u.pos or {}
    local age = math.floor((now - (u.seen or now)) / 1000)
    local state = tostring(u.state or "?")
    if age > 300 then state = "SILENT " .. math.floor(age / 60) .. "m" end
    print(("%-10s %-16s %-17s %s"):format(
      tostring(u.label or ("#" .. id)):sub(1, 10),
      state:sub(1, 16),
      ("%s,%s,%s"):format(p.x or "?", p.y or "?", p.z or "?"),
      tostring(u.fuel or "?")))
  end
  if #ids == 0 then print("No turtles have reported yet.") end
end

---------------------------------------------------------------- loops

local function receiver()
  while true do
    local id, msg = rednet.receive(swarm.PROTOCOL)
    if type(msg) == "table" then
      local key = tostring(id)
      local old = units[key]
      msg.seen = os.epoch("utc")
      units[key] = msg
      if not old or old.state ~= msg.state then urgent = true end
      draw()
    end
  end
end

local function uploader()
  while true do
    local since = os.clock() - lastUpload
    if lastUpload == 0 or since >= INTERVAL or (urgent and since >= MIN_GAP) then
      urgent = false
      lastUpload = os.clock()
      upload()
      draw()
    end
    sleep(5)
  end
end

-- Fetch the orders file from GitHub and pass fresh orders on to the swarm.
-- Each order is re-broadcast until it expires, so a turtle that was busy or
-- out of range still gets it; turtles ignore orders they have already seen.
local function fetchOrders()
  local hdr = headers()
  hdr["Accept"] = "application/vnd.github.raw"
  local r = http.get({ url = ORDERS_API, headers = hdr })
  if not r then return nil end
  local okJson, data = pcall(textutils.unserialiseJSON, r.readAll())
  r.close()
  if okJson and type(data) == "table" and type(data.commands) == "table" then
    return data.commands
  end
  return nil
end

local function orders()
  while true do
    local list = fetchOrders()
    local now = os.epoch("utc")
    local mine
    for _, cmd in ipairs(list or {}) do
      if type(cmd) == "table" and type(cmd.issued) == "number"
        and now - cmd.issued < ORDER_LIFE then
        rednet.broadcast(cmd, swarm.CMD_PROTOCOL)
        orderNote = ("#%d %s -> %s"):format(
          cmd.id or 0, tostring(cmd.cmd), tostring(cmd.target))
        if swarm.accept(cmd) then mine = cmd end
      end
    end
    if mine and mine.cmd == "reboot" then
      print("Rebooting by remote order.")
      sleep(1)
      os.reboot()
    end
    sleep(ORDER_POLL)
  end
end

---------------------------------------------------------------- start

if not http then
  print("HTTP is disabled on this server, so I cannot upload.")
  return
end
if not swarm.open() then
  print("Attach an ender modem to this computer first.")
  return
end
token = loadToken()
draw()
parallel.waitForAny(receiver, uploader, orders)
