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
local MAP_PROTOCOL = "swarm_map"
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
local owner              -- player who gets chat messages (set from chat)
local chatBox            -- defined in the chat section below
local chatDebug = { heard = 0, sent = 0, failed = 0 }   -- shown in the status file
local drawMonitor        -- defined in the monitor section below
local marks, ownerPos    -- defined in the player detector section below
local MARKS_FILE = ".marks"
local monitorError       -- last error from drawing the monitor, if any
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

local mapQueue, mapNote = {}, {}   -- maps from the builder, and how their uploads went

local function upload()
  local doc = {
    updated = os.epoch("utc"),
    updatedText = os.date("!%Y-%m-%d %H:%M:%S UTC"),
    controller = { id = os.getComputerID(), label = os.getComputerLabel() },
    lastOrder = orderNote,
    version = swarm.version(),
    chatBox = chatBox() ~= nil,
    chatOwner = owner,
    maps = mapNote,
    ownerPos = ownerPos(),
    marks = marks,
    detector = (peripheral.find("player_detector") or peripheral.find("playerDetector")) ~= nil,
    chatDebug = chatDebug,
    monitor = peripheral.find("monitor") ~= nil,
    monitorError = monitorError,
    peripherals = peripheral.getNames(),
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

---------------------------------------------------------------- chat
-- With an Advanced Peripherals Chat Box next to this computer, the swarm
-- speaks up in game chat when something needs a person, and takes simple
-- orders typed in chat:   $swarm status      $swarm stop miner-2
-- (a leading $ hides the message from other players).

local OWNER_FILE = ".owner"
if fs.exists(OWNER_FILE) then
  local h = fs.open(OWNER_FILE, "r")
  owner = h.readAll()
  h.close()
end

chatBox = function()
  return peripheral.find("chat_box") or peripheral.find("chatBox")
end

local chatQueue = {}

local function say(text, to)
  chatQueue[#chatQueue + 1] = to and { text, to } or text
  while #chatQueue > 20 do table.remove(chatQueue, 1) end
end

-- States worth interrupting a person for.
local ALERTS = {
  ["needs fuel"] = "has run out of fuel",
  ["drop-off full"] = "cannot unload: the drop-off chest is full",
  ["chest full"] = "cannot unload: its chest is full",
  ["path blocked"] = "is stuck: its path is blocked",
  ["lost"] = "is lost, outside its mining area",
  ["error"] = "has crashed",
  ["problem"] = "has a problem",
  ["not ready"] = "is not ready",
  ["waiting for parts"] = "is waiting for parts",
  ["launched one"] = "launched a new miner",
  ["out of coal"] = "has no coal: put coal in the storage chest",
  ["hunting coal"] = "is out hunting coal with the Geo Scanner",
  ["scanner problem"] = "cannot use the Geo Scanner",
  ["stranded"] = "is stranded with no fuel",
  ["rescuing"] = "is taking coal to a stranded miner",
  ["launched builder"] = "launched the builder",
  ["no way out"] = "cannot get out to the surface",
  ["stuck outside"] = "is stuck outside and cannot get back in",
  ["fleet full"] = "has built the whole fleet",
}

local lastAlert = {}   -- "id:state" -> time of the last chat message

local function alertFor(id, msg)
  local now = os.epoch("utc")
  local sp = type(msg.storage) == "table" and msg.storage
  if sp and tonumber(sp.slots) and tonumber(sp.free) and sp.slots > 0
    and sp.free < math.max(10, sp.slots * 0.05) then
    local k = tostring(id) .. ":storage"
    if not lastAlert[k] or now - lastAlert[k] > 30 * 60000 then
      lastAlert[k] = now
      say((msg.label or "The factory") .. "'s storage is nearly full (" .. sp.free
        .. " free slots): please add chests.")
    end
  end
  local text = ALERTS[msg.state]
  if not text then return end
  local key = tostring(id) .. ":" .. msg.state
  if lastAlert[key] and now - lastAlert[key] < 10 * 60000 then return end
  lastAlert[key] = now
  local name = msg.label or ("#" .. tostring(id))
  local detail = ""
  if type(msg.log) == "table" and #msg.log > 0
    and (msg.state == "problem" or msg.state == "not ready"
      or msg.state == "waiting for parts" or msg.state == "error") then
    detail = " (" .. tostring(msg.log[#msg.log]) .. ")"
  end
  say(name .. " " .. text .. detail)
end

-- Sends queued chat lines one at a time (the Chat Box has a cooldown).
local function chatter()
  while true do
    local box = chatBox()
    if box and #chatQueue > 0 then
      local text = table.remove(chatQueue, 1)
      local to = owner
      if type(text) == "table" then text, to = text[1], text[2] end
      local ok, res, why
      -- Advanced Peripherals 0.8: sendMessage(text, { options })
      local options = { prefix = "Swarm" }
      if to then options.player = to end
      ok, res, why = pcall(box.sendMessage, text, options)
      if ok and res ~= nil and res ~= false then
        chatDebug.sent = chatDebug.sent + 1
      else
        chatDebug.failed = chatDebug.failed + 1
        chatDebug.lastError = tostring(ok and why or res)
      end
    elseif not box then
      chatQueue = {}
    end
    sleep(1.5)
  end
end

local ORDER_WORDS = { stop = true, home = true, resume = true, reboot = true, ping = true }

-- "$get 64 iron ingot": ask the storage computer (Sortnado) to put items
-- straight into the owner's inventory. Also "$get all cobblestone", and
-- "$get diamond pickaxe" for one.
local STORE_PROTOCOL = "swarm_store"
local storePending, storeSeq = {}, 0

local function parseGet(text)
  local rest = text:match("^get%s+(.-)%s*$")
  if not rest or rest == "" then return nil end
  local count, item = rest:match("^(%S+)%s+(.+)$")
  if count == "all" then return "all", item end
  if count and tonumber(count) then return math.max(1, math.floor(tonumber(count))), item end
  return 1, rest
end

local function askStore(count, item, user)
  storeSeq = storeSeq + 1
  local n = math.floor(os.epoch("utc") / 1000) % 100000 * 100 + storeSeq % 100
  storePending[n] = { at = os.clock(), item = item, user = user }
  rednet.broadcast({ type = "get", item = item, count = count, to = "player", player = user, n = n }, STORE_PROTOCOL)
end

-- What to say in chat about the storage computer's answer.
local function storeLine(msg, asked)
  local label = tostring(msg.label or asked or "that")
  if not msg.item then
    return msg.why and ("Storage could not do that: " .. tostring(msg.why))
      or ("Storage has no '" .. tostring(asked) .. "'.")
  end
  local count, want = tonumber(msg.count) or 0, tonumber(msg.asked)
  if count == 0 then
    return ("Could not send %s: %s."):format(label, tostring(msg.why or "none left"))
  end
  local line = ("Sent %d %s to you"):format(count, label)
  if want and count < want then
    line = line .. (" (you asked for %d: %s)"):format(want, tostring(msg.why or "that is all there was"))
  end
  return line .. (". %d left in storage."):format(tonumber(msg.left) or 0)
end

-- Passes Sortnado's answers on, and says so when there is none.
local function storeReplies()
  while true do
    local _, msg = rednet.receive(STORE_PROTOCOL, 2)
    if type(msg) == "table" and msg.type == "got" and msg.n and storePending[msg.n] then
      local asked, user = storePending[msg.n].item, storePending[msg.n].user
      storePending[msg.n] = nil
      say(storeLine(msg, asked), user ~= owner and user or nil)
    end
    for n, p in pairs(storePending) do
      if os.clock() - p.at > 20 then
        storePending[n] = nil
        say("Storage did not answer about '" .. p.item .. "'. Is Sortnado running?", p.user ~= owner and p.user or nil)
      end
    end
  end
end

-- Listens for "swarm ..." and "get ..." typed in chat.
local function chatOrders()
  while true do
    -- Advanced Peripherals 0.8: event, uuid, player name, message, hidden
    local _, _, user, message = os.pullEvent("chat")
    chatDebug.heard = chatDebug.heard + 1
    chatDebug.lastHeard = tostring(user) .. ": " .. tostring(message)
    local text = type(message) == "string" and message:lower():gsub("^%$", "") or ""
    local word, arg = text:match("^swarm%s+(%S+)%s*(%S*)")
    local getCount, getItem = parseGet(text)
    -- (items go to whoever asks: Sortnado finds the Inventory Manager that
    -- holds their memory card)
    if getItem and type(user) == "string" then
      askStore(getCount, getItem, user)
    end
    if word and (not owner or owner == user) then
      if not owner then
        owner = user
        local h = fs.open(OWNER_FILE, "w")
        h.write(owner)
        h.close()
        say("Hello " .. user .. ". I will message only you from now on.")
      end
      if word == "mark" then
        -- remember where the owner is standing, under a name
        local p = ownerPos()
        local name = (arg ~= "" and arg:match("^[%w_%-]+$")) and arg or "here"
        if p then
          marks[name] = p
          local h = fs.open(MARKS_FILE, "w")
          h.write(textutils.serialize(marks))
          h.close()
          urgent = true
          say(("Marked '%s' at %d, %d, %d."):format(name, p.x, p.y, p.z))
        else
          say("I cannot see you. Is the Player Detector touching me?")
        end
      elseif word == "status" then
        local any = false
        for id, u in pairs(units) do
          any = true
          local p = u.pos
          say(("%s: %s%s"):format(tostring(u.label or ("#" .. id)), tostring(u.state),
            p and (" at %s, %s, %s"):format(p.x, p.y, p.z) or ""))
        end
        if not any then say("No turtles have reported yet.") end
      elseif ORDER_WORDS[word] then
        local target = arg ~= "" and arg or "all"
        if tonumber(target) then target = tonumber(target) end
        local cmd = {
          id = math.floor(os.epoch("utc") / 1000), issued = os.epoch("utc"),
          cmd = word, target = target,
        }
        rednet.broadcast(cmd, swarm.CMD_PROTOCOL)
        say("Order sent: " .. word .. " -> " .. tostring(target))
      else
        say("Try: swarm status | swarm mark <name> | swarm stop/home/resume/reboot <name or all> | get <count> <item>")
      end
    end
  end
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
  -- the monitor is a nicety: never let it take the controller down
  local okMon, errMon = pcall(drawMonitor)
  monitorError = not okMon and tostring(errMon) or nil
end

---------------------------------------------------------------- monitor
-- With a monitor attached, shows a top-down map of the base, the plots and
-- every turtle, plus a status line for each machine.

local function stateColour(state)
  state = tostring(state)
  if state == "mining" or state == "building" or state == "launched one" then
    return colors.lime
  elseif state:find("flying") or state == "going home" or state == "starting" then
    return colors.yellow
  elseif state == "parked" or state == "stopped" or state == "paused"
    or state == "idle" or state == "done" or state == "fleet full"
    or state == "waiting for a plot" or state == "waiting for parts" then
    return colors.lightBlue
  end
  return colors.red   -- anything else needs a look
end

local wallActive = false    -- the big map wall is drawing (dash.lua): leave the monitor to it

drawMonitor = function()
  local mon = peripheral.find("monitor")
  if not mon or wallActive then return end
  mon.setTextScale(0.5)
  local w, h = mon.getSize()
  local colour = mon.isColour()
  local function bg(c) if colour then mon.setBackgroundColour(c) end end
  local function fg(c) if colour then mon.setTextColour(c) end end
  local function put(x, y, text)
    if y < 1 or y > h or x > w then return end
    if x < 1 then text = text:sub(2 - x); x = 1 end
    mon.setCursorPos(x, y)
    mon.write(text:sub(1, w - x + 1))
  end
  bg(colors.black)
  fg(colors.white)
  mon.clear()

  -- sort machines: factory first, then by name
  local ids = {}
  for id in pairs(units) do ids[#ids + 1] = id end
  table.sort(ids, function(a, b)
    local ua, ub = units[a], units[b]
    if (ua.role == "factory") ~= (ub.role == "factory") then return ua.role == "factory" end
    return tostring(ua.label) < tostring(ub.label)
  end)

  -- layout: list on the right if the monitor is wide, else underneath
  local listW = 50
  local sideBySide = w >= listW + 30
  local mapX, mapY, mapW, mapH, listX, listY
  if sideBySide then
    mapX, mapY, mapW, mapH = 1, 2, w - listW - 1, h - 1
    listX, listY = w - listW + 1, 2
  else
    local listH = math.min(#ids + 1, math.floor(h / 2))
    mapX, mapY, mapW, mapH = 1, 2, w, h - 1 - listH
    listX, listY = 1, h - listH + 1
  end

  fg(colors.yellow)
  put(1, 1, "SWARM  " .. os.date("%H:%M") .. "  " .. uploadNote)
  fg(colors.white)

  -- everything that has a place on the map
  local base, plotsOf = nil, {}
  local minX, maxX, minZ, maxZ
  local function grow(x, z)
    minX = math.min(minX or x, x) maxX = math.max(maxX or x, x)
    minZ = math.min(minZ or z, z) maxZ = math.max(maxZ or z, z)
  end
  for _, id in ipairs(ids) do
    local u = units[id]
    if type(u.base) == "table" and type(u.base.f) == "table" then
      base = u.base
      grow(base.f.x, base.f.z)
    end
    local j = u.job
    if type(j) == "table" and type(j.home) == "table" and j.size then
      local x0, z0 = j.home.x + 1, j.home.z
      if not j.plot then x0 = nil end          -- old-style job: no fixed square
      if x0 then
        plotsOf[id] = { x0 = x0, z0 = z0, size = j.size, plot = j.plot,
          layer = j.layer or 0, layers = j.layers or 0 }
        grow(x0, z0)
        grow(x0 + j.size - 1, z0 + j.size - 1)
      end
    end
    if type(u.pos) == "table" and u.pos.x and not (u.pos.x == 0 and u.pos.z == 0) then
      grow(u.pos.x, u.pos.z)
    end
  end

  if minX and mapW > 4 and mapH > 2 then
    minX, maxX, minZ, maxZ = minX - 3, maxX + 3, minZ - 3, maxZ + 3
    -- a character cell is about 1.5 times as tall as it is wide
    local sx = math.max((maxX - minX + 1) / mapW, (maxZ - minZ + 1) / (mapH * 1.5))
    local sz = sx * 1.5
    local function col(x) return mapX + math.floor((x - minX) / sx) end
    local function row(z) return mapY + math.floor((z - minZ) / sz) end

    -- plots: grey squares, darker once more than half dug
    for _, pl in pairs(plotsOf) do
      local c1, c2 = col(pl.x0), col(pl.x0 + pl.size - 1)
      local r1, r2 = row(pl.z0), row(pl.z0 + pl.size - 1)
      local done = pl.layers > 0 and pl.layer / pl.layers or 0
      bg(done > 0.5 and colors.gray or colors.lightGray)
      fg(colors.black)
      for r = r1, r2 do
        if r >= mapY and r < mapY + mapH then
          put(c1, r, string.rep(" ", c2 - c1 + 1))
        end
      end
      put(c1, r1, tostring(pl.plot))
    end
    -- the factory
    if base then
      bg(colors.orange)
      fg(colors.black)
      put(col(base.f.x), row(base.f.z), "F")
    end
    -- the turtles: first letter of the name, coloured by what they are doing
    for _, id in ipairs(ids) do
      local u = units[id]
      if u.role ~= "factory" and type(u.pos) == "table" and u.pos.x
        and not (u.pos.x == 0 and u.pos.z == 0) then
        bg(stateColour(u.state))
        fg(colors.black)
        local r = row(u.pos.z)
        if r >= mapY and r < mapY + mapH then
          put(col(u.pos.x), r, tostring(u.label or "?"):sub(1, 1))
        end
      end
    end
    bg(colors.black)
    fg(colors.gray)
    put(mapX, mapY + mapH - 1, "N^  1 char = " .. string.format("%.1f", sx) .. " blocks")
  end

  -- the list
  bg(colors.black)
  local y = listY
  local now = os.epoch("utc")
  for _, id in ipairs(ids) do
    if y > h then break end
    local u = units[id]
    local age = math.floor((now - (u.seen or now)) / 1000)
    local state = tostring(u.state or "?")
    if age > 300 then state = "SILENT " .. math.floor(age / 60) .. "m" end
    bg(age > 300 and colors.red or stateColour(u.state))
    put(listX, y, " ")
    bg(colors.black)
    fg(colors.white)
    local detail = ""
    local j = u.job
    if u.role == "factory" and type(u.fleet) == "table" then
      detail = ("fleet %s/%s"):format(tostring(u.fleet.active), tostring(u.fleet.max))
    elseif type(j) == "table" and j.layers and j.layers > 0 then
      detail = ("#%s %d%% fuel %s"):format(tostring(j.plot or "-"),
        math.floor(100 * (j.layer or 0) / j.layers), tostring(u.fuel or "?"))
    elseif u.fuel then
      detail = "fuel " .. tostring(u.fuel)
    end
    put(listX + 2, y, ("%-14s %-15s %s"):format(
      tostring(u.label or ("#" .. id)):sub(1, 14), state:sub(1, 15), detail))
    y = y + 1
  end
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
      if not old or old.state ~= msg.state then
        urgent = true
        alertFor(id, msg)
      end
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

-- Write any file to the status branch (maps and the like).
local function putFile(path, text, message)
  local url = "https://api.github.com/repos/" .. REPO .. "/contents/" .. path
  local fileSha
  local r = http.get({ url = url .. "?ref=" .. BRANCH, headers = headers() })
  if r then
    local okJson, data = pcall(textutils.unserialiseJSON, r.readAll())
    r.close()
    if okJson and type(data) == "table" then fileSha = data.sha end
  end
  local body = textutils.serialiseJSON({
    message = message, branch = BRANCH, content = b64(text), sha = fileSha,
  })
  local r2, err, failed = http.post({ url = url, method = "PUT", headers = headers(), body = body })
  if r2 then
    r2.close()
    return true
  end
  if failed then failed.close() end
  return false, tostring(err)
end


-- Player Detector: where the owner is, and named spots they mark in chat.
marks = {}
if fs.exists(MARKS_FILE) then
  local h = fs.open(MARKS_FILE, "r")
  marks = textutils.unserialize(h.readAll()) or {}
  h.close()
end

ownerPos = function()
  local det = peripheral.find("player_detector") or peripheral.find("playerDetector")
  if not det or not owner then return nil end
  local ok, p = pcall(det.getPlayer, owner)
  if not ok or type(p) ~= "table" then
    ok, p = pcall(det.getPlayerPos, owner)        -- older versions
  end
  if ok and type(p) == "table" and p.x then
    return { x = math.floor(p.x), y = math.floor(p.y), z = math.floor(p.z),
      dimension = p.dimension }
  end
  return nil
end

-- Maps sent by the builder are uploaded as maps/<name>.json.
local function maps()
  while true do
    local m = table.remove(mapQueue, 1)
    if m then
      local okJson, json = pcall(textutils.serialiseJSON, {
        name = m.name, from = m.from, updated = os.epoch("utc"), data = m.data,
      })
      if okJson then
        local ok, why = putFile("maps/" .. m.name .. ".json", json, "map " .. m.name)
        mapNote[m.name] = ok and os.date("!%H:%M") or ("failed: " .. tostring(why))
        if ok and not m.name:find("^survey_") then say("New map uploaded: " .. m.name) end   -- (a survey sends many)
      else
        mapNote[m.name] = "could not convert: " .. tostring(json)
      end
      urgent = true
    end
    sleep(2)
  end
end

local function mapListener()
  while true do
    local id, msg = rednet.receive(MAP_PROTOCOL)
    if type(msg) == "table" and msg.type == "map" and type(msg.name) == "string"
      and msg.name:match("^[%w_%-]+$") and type(msg.data) == "table" then
      msg.from = id
      mapQueue[#mapQueue + 1] = msg
      pcall(keepMap, msg.name, msg.data)
    end
  end
end

---------------------------------------------------------------- the map wall
-- On a big wall of advanced monitors (the control tower's 9 x 4), dash.lua
-- draws the live map: land from the builder's scans, plots, every drone,
-- the fleet list, the factory, the build. Its buttons send orders; each
-- needs a second tap within a few seconds, so a stray click does nothing.
local okDash, dash = pcall(require, "dash")
if not okDash then dash = nil end
local WALL = {
  site = { -4448, 1518, -4404, 1548, layers = 37 },   -- the factory building
  hut = { -4464, 1518, -4458, 1532 },
  maps = { "factory_site", "meadow", "ground" },
  plot = 8, keepOut = 24, huntRange = 128,
}
local wallMaps, wallZones, armed, armedAt = {}, {}, nil, 0

local function keepMap(name, data)
  if type(data) == "table" and data.kind == "ground" and data.heights and data.names and data.palette then
    for i, m in ipairs(wallMaps) do
      if m.name == name then table.remove(wallMaps, i) break end
    end
    table.insert(wallMaps, 1, { name = name, origin = data.origin, size = data.size,
      heights = data.heights, names = data.names, palette = data.palette })
  end
end

-- the maps already uploaded, after a restart
local function fetchMaps()
  for _, name in ipairs(WALL.maps) do
    local okGet, res = pcall(http.get, "https://raw.githubusercontent.com/" .. REPO .. "/status/maps/" .. name .. ".json")
    if okGet and res then
      local okJson, doc = pcall(textutils.unserializeJSON, res.readAll())
      res.close()
      if okJson and type(doc) == "table" then keepMap(name, doc.data) end
    end
  end
end

local function plotOrigin(f, index)
  local n = 0
  for r = 0, 80 do
    for gx = -r, r do
      for gz = -r, r do
        if math.max(math.abs(gx), math.abs(gz)) == r then
          local x0, z0 = f.x + gx * WALL.plot, f.z + gz * WALL.plot
          if f.x < x0 - WALL.keepOut or f.x > x0 + WALL.plot - 1 + WALL.keepOut
            or f.z < z0 - WALL.keepOut or f.z > z0 + WALL.plot - 1 + WALL.keepOut then
            n = n + 1
            if n == index then return x0, z0 end
          end
        end
      end
    end
  end
end

local plotCache = {}
local function wallData()
  local forge, done, total, layer
  local list = {}
  for _, u in pairs(units) do
    if u.role == "factory" then forge = u end
    local p = type(u.progress) == "table" and u.progress
    if p and p.kind == "building" and tonumber(p.done) then
      done = (done or 0) + p.done
      if u.role == "builder" then total = p.total end
      if p.layer and (not layer or p.layer < layer) then layer = p.layer end
    end
    if type(u.log) == "table" and #u.log > 0 then list[#list + 1] = u end
  end
  if not (forge and type(forge.base) == "table" and forge.base.f) then return nil end
  local f = forge.base.f
  table.sort(list, function(a, b) return (a.seen or 0) > (b.seen or 0) end)
  local events = {}
  for i = 1, math.min(#list, 14) do events[i] = { list[i].label, list[i].log[#list[i].log] } end
  local plots = { size = WALL.plot, done = {}, active = {} }
  local fleet = type(forge.fleet) == "table" and forge.fleet or {}
  local live = {}
  for _, index in pairs(fleet.byId or {}) do live[index] = true end
  for index = 1, (fleet.nextPlot or 1) - 1 do
    local o = plotCache[index]
    if not o then
      local x, z = plotOrigin(f, index)
      o = { x, z }
      plotCache[index] = o
    end
    if live[index] then plots.active[#plots.active + 1] = o else plots.done[#plots.done + 1] = o end
  end
  local inv = type(forge.inv) == "table" and forge.inv or {}
  local store = type(forge.storage) == "table" and forge.storage or {}
  local s = WALL.site
  return {
    units = units, maps = wallMaps, base = { x = f.x, y = f.y, z = f.z },
    site = { s[1], s[2], s[3], s[4], progress = (done and total and total > 0) and math.min(1, done / total) or 0,
      layer = layer, layers = s.layers, done = done, total = total },
    hut = WALL.hut, plots = plots,
    factory = { coal = (inv["minecraft:coal"] or 0) + (inv["minecraft:charcoal"] or 0),
      used = store.used, slots = store.slots, free = store.free },
    clock = os.date("%H:%M"), now = os.epoch("utc"), updated = uploadNote,
    events = events, huntRange = WALL.huntRange,
    armed = (armed and os.clock() - armedAt < 6) and armed or nil,
  }
end

local function wall()
  if dash then pcall(fetchMaps) end
  local frame = 0
  while true do
    local mon = dash and peripheral.find("monitor")
    local big = false
    if mon then
      mon.setTextScale(0.5)
      local w, h = mon.getSize()
      big = w >= 150 and h >= 45
    end
    if big ~= wallActive then
      wallActive = big
      if mon and not big then for i = 0, 15 do mon.setPaletteColour(2 ^ i, term.nativePaletteColour(2 ^ i)) end end
    end
    if big then
      local data = wallData()
      if data then
        local okDraw, z = pcall(dash.wall, mon, data, frame)
        if okDraw then wallZones = z else monitorError = "wall: " .. tostring(z) end
      end
      frame = frame + 1
      sleep(0.25)
    else
      sleep(5)
    end
  end
end

-- A tap on the wall. Orders need the same button tapped twice.
local function wallTouch()
  local function order(word, target)
    rednet.broadcast({ id = math.floor(os.epoch("utc") / 1000), issued = os.epoch("utc"),
      cmd = word, target = target }, swarm.CMD_PROTOCOL)
    say("Order from the wall: " .. word .. " -> " .. tostring(target))
  end
  while true do
    local _, _, x, y = os.pullEvent("monitor_touch")
    local id
    for i = #wallZones, 1, -1 do
      local z = wallZones[i]
      if x >= z[1] and x <= z[3] and y >= z[2] and y <= z[4] then id = z[5] break end
    end
    if id and wallActive then
      local label = id:match("^unit:(.+)$")
      if label then
        for uid, u in pairs(units) do
          if u.label == label then
            local p = u.pos
            say(("%s: %s%s, fuel %s"):format(label, tostring(u.state),
              p and (" at %s, %s, %s"):format(p.x, p.y, p.z) or "", tostring(u.fuel)))
          end
        end
      elseif id == "recall" or id == "resume" or id == "pause" then
        if armed == id and os.clock() - armedAt < 6 then
          armed = nil
          if id == "recall" then order("home", "all")
          elseif id == "resume" then order("resume", "all")
          else
            for _, u in pairs(units) do
              if u.role == "builder" or (u.role == "helper" and type(u.progress) == "table"
                and u.progress.kind == "building") then order("stop", u.label) end
            end
          end
        else
          armed, armedAt = id, os.clock()
        end
      end
    end
  end
end

-- The touch panels and screens out in the factory (screens.lua) ask here;
-- only what swarm.panelOrders allows is passed on, and not twice in a row.
local function panelOrders()
  local lastAt = {}
  while true do
    local from, msg = rednet.receive(swarm.PANEL_PROTOCOL)
    if type(msg) == "table" and msg.type == "ask" then
      local reply = { type = "ack", n = msg.n, ok = false }
      local key = tostring(msg.ask)
      if lastAt[key] and os.clock() - lastAt[key] < 10 then
        reply.text = "Just sent: give it a moment"
      else
        local list, words = swarm.panelOrders(msg.ask, units)
        if list then
          lastAt[key] = os.clock()
          local id = math.floor(os.epoch("utc") / 1000)
          for _, o in ipairs(list) do      -- (one number will do: each goes to a different machine)
            rednet.broadcast({ id = id, issued = os.epoch("utc"), cmd = o.cmd, target = o.target },
              swarm.CMD_PROTOCOL)
          end
          reply.ok, reply.text = true, "Sent: " .. words
          say(("Order from the %s: %s"):format(tostring(msg.from or "panel"):sub(1, 24), words))
        else
          reply.text = "Not sent: " .. tostring(words)
        end
      end
      rednet.send(from, reply, swarm.PANEL_PROTOCOL)
    end
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

-- The newest commit on main, so rebooting machines download exactly that.
local function latestRev()
  local hdr = headers()
  hdr["Accept"] = "application/vnd.github.sha"
  local r = http.get({
    url = "https://api.github.com/repos/" .. REPO .. "/commits/main",
    headers = hdr,
  })
  if not r then return nil end
  local rev = r.readAll():gsub("%s", "")
  r.close()
  if #rev == 40 and rev:match("^%x+$") then return rev end
  return nil
end

local revForOrder = {}   -- order id -> version looked up for it

local function orders()
  while true do
    local list = fetchOrders()
    local now = os.epoch("utc")
    local mine
    for _, cmd in ipairs(list or {}) do
      if type(cmd) == "table" and type(cmd.issued) == "number"
        and now - cmd.issued < ORDER_LIFE then
        if cmd.cmd == "reboot" and cmd.id then
          if not revForOrder[cmd.id] then revForOrder[cmd.id] = latestRev() end
          cmd.rev = revForOrder[cmd.id]
        end
        rednet.broadcast(cmd, swarm.CMD_PROTOCOL)
        orderNote = ("#%d %s -> %s"):format(
          cmd.id or 0, tostring(cmd.cmd), tostring(cmd.target))
        if swarm.accept(cmd) then mine = cmd end
      end
    end
    if mine and mine.cmd == "reboot" then
      swarm.pinVersion(mine)
      print("Rebooting by remote order.")
      sleep(1)
      os.reboot()
    end
    sleep(ORDER_POLL)
  end
end

---------------------------------------------------------------- start

do
  -- (only when the machine has no job written down: update.lua may have just
  -- given it another one, and this run is the old startup's second line)
  if not fs.exists(".role") then
    local h = fs.open(".role", "w")
    h.write("controller")
    h.close()
  end
  local label = os.getComputerLabel()
  if not label or label == "controller" then os.setComputerLabel("CommandBlock") end
end

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
-- the wall is a nicety: whatever goes wrong in it must never stop the rest
local function safe(fn)
  return function()
    while true do
      local ok, err = pcall(fn)
      if not ok and err == "Terminated" then error(err, 0) end
      monitorError = "wall: " .. tostring(err)
      sleep(15)
    end
  end
end
parallel.waitForAny(receiver, uploader, orders, chatter, chatOrders, storeReplies, maps, mapListener, safe(wall), safe(wallTouch), safe(panelOrders))
