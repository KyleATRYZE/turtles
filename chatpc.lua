-- chatpc.lua: a computer that sends server chat for someone who can't type in
-- Minecraft's chat. Works on a pocket computer with the Advanced Peripherals
-- Chat Box upgrade (craft the pocket computer with a Chat Box), or on a
-- placed computer with a Chat Box touching it (and a monitor for buttons).
--
-- Install on the computer:
--   wget https://raw.githubusercontent.com/KyleATRYZE/turtles/main/chatpc.lua startup.lua
--   reboot
-- First start asks for the name to show in chat. Then: type a message and
-- press Enter, or tap a quick button on the monitor.

local box = peripheral.find("chatBox") or peripheral.find("chat_box")
if not box then
  print("No Chat Box found.")
  print("Pocket: craft it with a Chat Box.")
  print("Placed: put a Chat Box next to it.")
  print("Then reboot.")
  return
end

local CONFIG = ".chatpc"
local cfg = {}
if fs.exists(CONFIG) then
  local f = fs.open(CONFIG, "r")
  cfg = textutils.unserialize(f.readAll()) or {}
  f.close()
end
if not cfg.name or cfg.name == "" then
  term.clear()
  term.setCursorPos(1, 1)
  write("Name to show in chat: ")
  cfg.name = read()
  cfg.quick = cfg.quick or { "Hi!", "On my way", "Yes", "No", "Thanks!", "Brb", "Help please", "gg" }
  local f = fs.open(CONFIG, "w")
  f.write(textutils.serialize(cfg))
  f.close()
end

local send
send = function(msg)
  msg = tostring(msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if msg == "" then return end
  -- (newer Advanced Peripherals take the options as a table; older ones as
  -- plain arguments: try the table first)
  local function try()
    local ok, res, why = pcall(box.sendMessage, msg, { prefix = cfg.name, brackets = "<>" })
    if not ok and tostring(res):find("bad argument", 1, true) then
      ok, res, why = pcall(box.sendMessage, msg, cfg.name, "<>")
    end
    return ok, res, why
  end
  local ok, res, why = try()
  if not ok or not res then
    sleep(1.2)                                 -- (the Chat Box has a short cool-down)
    ok, res, why = try()
  end
  local old = term.getTextColour()
  if not (ok and res) then
    term.setTextColour(colours.red) print("NOT sent: " .. tostring(ok and (why or res) or res))
  end
  term.setTextColour(old)
end

-- quick buttons on a monitor, if there is one
local mon = peripheral.find("monitor")
local buttons = {}
local function drawButtons()
  if not mon then return end
  mon.setTextScale(1)
  mon.setBackgroundColour(colours.black)
  mon.clear()
  local w, h = mon.getSize()
  buttons = {}
  local y = 1
  for _, q in ipairs(cfg.quick or {}) do
    if y > h then break end
    mon.setCursorPos(1, y)
    mon.setBackgroundColour(colours.grey)
    mon.setTextColour(colours.white)
    mon.write((" " .. q .. string.rep(" ", w)):sub(1, w))
    buttons[y] = q
    y = y + 2
  end
  mon.setBackgroundColour(colours.black)
end

-- the screen: the chat (scrolling) above, the line you type on at the bottom
local native = term.current()
local W, H = native.getSize()
local head = 3                                  -- name and the quick list
local log = window.create(native, 1, head + 1, W, H - head - 1)
local input = window.create(native, 1, H, W, 1)

local function header()
  native.setBackgroundColour(colours.black)
  native.clear()
  native.setCursorPos(1, 1)
  native.setTextColour(colours.yellow)
  native.write(("Chat as " .. cfg.name):sub(1, W))
  native.setTextColour(colours.lightGrey)
  local q = {}
  for i, t in ipairs(cfg.quick or {}) do q[#q + 1] = i .. " " .. t end
  local line, y = "", 2
  for _, t in ipairs(q) do
    if #line + #t + 2 > W and y <= head then
      native.setCursorPos(1, y) native.write(line) y = y + 1 line = ""
    end
    line = line == "" and t or (line .. "  " .. t)
  end
  if y <= head then native.setCursorPos(1, y) native.write(line) end
  log.setBackgroundColour(colours.black)
  log.clear()
  log.setCursorPos(1, 1)
end

-- one line into the chat log (wrapped, scrolling)
local function logLine(text, col)
  local old = term.redirect(log)
  term.setTextColour(col or colours.white)
  print(text)
  term.redirect(old)
  input.restoreCursor()
end
send = (function(inner)
  return function(msg)
    local old = term.redirect(log)
    inner(msg)
    term.redirect(old)
    input.restoreCursor()
  end
end)(send)

drawButtons()
header()
logLine("Type a message, Enter to send.", colours.lightGrey)
logLine("Or a number for a quick one.", colours.lightGrey)
parallel.waitForAny(
  function()                                   -- typed messages
    while true do
      term.redirect(input)
      input.setBackgroundColour(colours.grey)
      input.setTextColour(colours.white)
      input.clear()
      input.setCursorPos(1, 1)
      write("> ")
      local msg = read()
      term.redirect(native)
      local q = tonumber(msg) and (cfg.quick or {})[tonumber(msg)]
      if (q or msg) ~= "" then logLine("me: " .. (q or msg), colours.cyan) end
      send(q or msg)
    end
  end,
  function()                                   -- what everyone else says
    while true do
      -- (this Advanced Peripherals sends the player's id first: id, name,
      -- message; older ones send name, message, id)
      local e = { os.pullEvent("chat") }
      local user, message, hidden = e[2], e[3], e[5]
      if type(e[2]) == "string" and e[2]:match("^%x+%-%x+%-%x+%-%x+%-%x+$") then
        user, message = e[3], e[4]
      end
      if hidden ~= true then logLine("<" .. tostring(user) .. "> " .. tostring(message)) end
    end
  end,
  function()                                   -- monitor buttons
    while true do
      local _, _, _, y = os.pullEvent("monitor_touch")
      local q = buttons[y]
      if q then
        logLine("me: " .. q, colours.cyan)
        send(q)
        if mon then
          mon.setCursorPos(1, y)
          mon.setBackgroundColour(colours.green)
          mon.write(" " .. q)
          sleep(0.4)
          drawButtons()
        end
      end
    end
  end
)
