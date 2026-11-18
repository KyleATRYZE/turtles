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

local function send(msg)
  msg = tostring(msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if msg == "" then return end
  local ok, err = pcall(box.sendMessage, msg, cfg.name, "<>")
  if not ok or err == false then
    sleep(1)                                   -- (the Chat Box has a short cool-down)
    pcall(box.sendMessage, msg, cfg.name, "<>")
  end
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

local function screen()
  term.setBackgroundColour(colours.black)
  term.clear()
  term.setCursorPos(1, 1)
  term.setTextColour(colours.yellow)
  print("Chat as " .. cfg.name)
  term.setTextColour(colours.lightGrey)
  print("Type a message, Enter to send.")
  if mon then print("Or tap a button on the monitor.") end
  print("Or just a number for a quick one:")
  for i, q in ipairs(cfg.quick or {}) do
    write(i .. " " .. q .. (i % 2 == 0 and "\n" or string.rep(" ", math.max(1, 13 - #q - #tostring(i)))))
  end
  print("")
  term.setTextColour(colours.white)
end

drawButtons()
screen()
parallel.waitForAny(
  function()                                   -- typed messages
    while true do
      write("> ")
      local msg = read()
      local q = tonumber(msg) and (cfg.quick or {})[tonumber(msg)]
      send(q or msg)
      local _, y = term.getCursorPos()
      if y > select(2, term.getSize()) - 2 then screen() end
    end
  end,
  function()                                   -- monitor buttons
    while true do
      local _, _, _, y = os.pullEvent("monitor_touch")
      local q = buttons[y]
      if q then
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
