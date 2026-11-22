# The stations beside the factory's screens (screens.lua) and what they draw
# (dash.lua): which post a station takes, what it shows with live reports,
# with none, and from the uploaded file; the touch buttons; and the short
# list of orders the controller will pass on for a panel.
#   python3 test/screenstest.py
import json, os, lupa
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(HERE)
fails = []
def check(what, ok):
    print(("ok   " if ok else "FAIL ") + what)
    if not ok: fails.append(what)

PRELUDE = r'''
package.path = "%s/?.lua;" .. package.path
NOW, CLOCK = 1794870000000, 1000
FILES, SENT, LABEL = {}, {}, "station-31"
GPS = nil
os.epoch = function() return NOW end
os.clock = function() return CLOCK end
os.date = function(f, t) return "23:10" end
os.getComputerID = function() return 31 end
os.getComputerLabel = function() return LABEL end
os.setComputerLabel = function(l) LABEL = l end
fs = { exists = function(n) return FILES[n] ~= nil end,
  open = function(n, mode)
    if mode == "r" then local s = FILES[n] return { readAll = function() return s end, close = function() end } end
    local buf = {}
    return { write = function(t) buf[#buf + 1] = t end, close = function() FILES[n] = table.concat(buf) end }
  end }
gps = { locate = function() if GPS then return GPS[1], GPS[2], GPS[3] end end }
rednet = { broadcast = function(msg, proto) SENT[#SENT + 1] = { msg = msg, proto = proto } end }
peripheral = { find = function() end }
textutils = {}
http = nil
function makeMon(bw, bh)
  local m = { scale = 1, rows = {}, bw = bw, bh = bh }
  m.setTextScale = function(s) m.scale = s end
  m.getSize = function()
    return math.max(1, math.floor((bw - 0.3125) / (m.scale * 6 / 64) + 0.5)),
           math.max(1, math.floor((bh - 0.3125) / (m.scale * 9 / 64) + 0.5))
  end
  m.setPaletteColour = function() end
  m.setCursorPos = function(x, y) m.cy = y end
  m.blit = function(t, f, b) m.rows[m.cy] = t end
  m.text = function() local t = {} for y = 1, 80 do t[#t + 1] = m.rows[y] or "" end return table.concat(t, "\n") end
  return m
end
SCREENS_TEST = true
SCR = dofile("%s/screens.lua")
swarm = require("swarm")
''' % (ROOT, ROOT)

def fresh():
    L = lupa.LuaRuntime(unpack_returned_tuples=True, encoding="latin-1")
    L.execute(PRELUDE)
    return L

def tolua(L, o):
    if isinstance(o, dict): return L.table_from({k: tolua(L, v) for k, v in o.items()})
    if isinstance(o, list): return L.table_from([tolua(L, v) for v in o])
    return o

# ---------------------------------------------------------------- the posts agree with the plan
plan = json.load(open(os.path.join(ROOT, "blueprints", "factory.json")))
L = fresh()
posts = {p.name: list(p.at.values()) for p in L.eval("SCR.POSTS").values()}
check("every station in the plan is a post in screens.lua, at the same spot",
      all(posts.get(s["name"]) == s["computer"] for s in plan["stations"]) and len(plan["stations"]) == 6)
B = {(x, y, z): plan["palette"][i] for x, y, z, i in plan["blocks"]}
check("each station touches a monitor of its screen and carries an ender modem",
      all("monitor" in B[tuple(t)] for s in plan["stations"] for t in s["touches"])
      and all(B[tuple(s["radio"])].startswith("computercraft:wireless_modem_advanced") for s in plan["stations"])
      and all(B[tuple(s["computer"])] == "computercraft:computer_normal" for s in plan["stations"]))

# ---------------------------------------------------------------- which post
o = L.eval("SCR.ORIGIN")
def at(L, name):
    c = posts[name]
    L.execute("GPS = {%d, %d, %d}" % (o.x + c[0], o.y + c[1], o.z + c[2]))
for name in posts:
    at(L, name)
    p, how = L.eval("{SCR.identify(nil)}").values()
    if p.name != name or how != "gps": check("post by GPS: " + name, False)
check("a station knows its post from where it stands (all seven)", not fails)
L.execute("GPS = {1, 2, 3}")
check("standing somewhere else, with no monitor: no post", L.eval("SCR.identify(nil)") is None)
L.execute("GPS = nil")
sizes = {"wall": (9, 4), "rack": (8, 1), "tower panel": (3, 2), "bay panel": (2, 2), "west gate": (2, 1)}
ok = True
for name, (w, h) in sizes.items():
    p, how = L.eval("{SCR.identify(makeMon(%d, %d))}" % (w, h)).values()
    ok = ok and p.name == name and how == "monitor"
check("with no GPS fix it goes by the size of its monitor", ok)
L.execute('FILES[".post"] = "east gate\\n"')
p, how = L.eval("{SCR.identify(makeMon(2, 1))}").values()
check("a .post file settles it (the two gates look the same)", p.name == "east gate" and how == "file")

# ---------------------------------------------------------------- live reports
status = {
  "8": {"label": "Forge", "role": "factory", "state": "fleet full", "log": ["Load handed over."],
        "base": {"f": {"x": -4461, "y": 72, "z": 1521}, "pad": {"x": -4460, "y": 72, "z": 1521}},
        "fleet": {"nextPlot": 9, "byId": {"11": 7, "12": 8}},
        "inv": {"minecraft:coal": 109, "minecraft:lava_bucket": 9, "minecraft:iron_ingot": 35,
                "minecraft:redstone": 1058, "minecraft:oak_log": 112},
        "storage": {"used": 858, "slots": 918, "free": 60},
        "foundry": {"machines": {"chamber": True, "smelter": True}, "job": "minecraft:raw_iron", "last": {"ok": True}}},
  "11": {"label": "DigA", "role": "miner", "state": "mining", "fuel": 2774, "pos": {"x": -4414, "y": -21, "z": 1562},
         "log": ["Layer 24/37"]},
  "12": {"label": "DigB", "role": "miner", "state": "parked", "fuel": 310, "pos": {"x": -4421, "y": 50, "z": 1497},
         "log": ["Parked."]},
  "13": {"label": "LoadA", "role": "loader", "state": "parked", "fuel": 918, "pos": {"x": -4457, "y": 71, "z": 1520},
         "log": ["Parked."]},
  "14": {"label": "LoadB", "role": "loader", "state": "escorting", "fuel": 1500, "pos": {"x": -4500, "y": 150, "z": 1600},
         "job": {"mode": "escort", "who": "DigA"}, "log": ["Over DigA."]},
  "15": {"label": "HelpA", "role": "helper", "state": "idle", "fuel": 700, "pos": {"x": -4453, "y": 84, "z": 1517},
         "log": ["Waiting for jobs."]},
  "16": {"label": "Mason", "role": "builder", "state": "idle", "fuel": 3754, "pos": {"x": -4463, "y": 72, "z": 1528},
         "log": ["Maps done."], "progress": {"kind": "building", "done": 9842, "total": 9843}},
}
def hear_all(L, st=status):
    for k, u in st.items():
        L.globals().SCR.hear(int(k), tolua(L, u))

L = fresh()
hear_all(L)
wall = L.eval("makeMon(9, 4)")
zones = L.globals().SCR.draw(L.eval('SCR.POSTS[5]'), wall)
t = wall.text()
check("the wall is 185 x 52 and draws the map wall", tuple(wall.getSize()) == (185, 52) and "FLEET" in t and "DEPTH" in t)
check("every drone is listed with its state", all(n in t for n in ("DigA", "DigB", "LoadA", "LoadB", "HelpA", "Mason", "Forge")))
check("stock, foundry and loaders each get a line",
      "lava 9" in t and "redstone 1058" in t and "chamber + smelter" in t and "raw iron" in t
      and "1 at base  1 out with DigA" in t)
check("no stale banner while reports are coming in", "NO SIGNAL" not in t and "WAITING" not in t)
site = L.globals().SCR.wallData().site
check("the map shows the rebuilt building: four masses, the lane behind them, no hut",
      (site[1], site[2], site[3], site[4]) == (-4468, 1522, -4382, 1557) and len(list(site.parts.values())) == 4
      and site.lane[2] == 1519 and L.globals().SCR.wallData().hut is None and "HUT" not in t and "FACTORY" in t)
unit_zone = [z for z in zones.values() if z[5] == "unit:DigA"]
check("a drone in the list can be tapped", len(unit_zone) >= 1)
z = unit_zone[0]
L.globals().SCR.tap(L.globals().SCR.zoneAt(zones, z[1], z[2]), L.eval('SCR.POSTS[5]'))
L.globals().SCR.draw(L.eval('SCR.POSTS[5]'), wall)
t = wall.text()
check("tapped, it says where the drone is and what it last said", "at -4414, -21, 1562" in t and "Layer 24/37" in t)

# many drones: the list still fits above the buttons
L = fresh()
big = dict(status)
for i in range(30):
    big[str(100 + i)] = {"label": "Bot%02d" % i, "role": "miner", "state": "mining", "fuel": 1000 + i,
                         "pos": {"x": -4500 + i, "y": 10, "z": 1500}, "log": ["x"]}
hear_all(L, big)
wall = L.eval("makeMon(9, 4)")
L.globals().SCR.draw(L.eval('SCR.POSTS[5]'), wall)
t = wall.text()
check("thirty-seven drones still fit (two columns) and the buttons are still there",
      all(("Bot%02d" % i) in t for i in range(30)) and "RECALL ALL" in t and "LATEST" in t)

# ---------------------------------------------------------------- nothing heard
L = fresh()
wall = L.eval("makeMon(9, 4)")
L.globals().SCR.draw(L.eval('SCR.POSTS[5]'), wall)
check("nothing heard yet: the wall says it is waiting, in words", "WAITING FOR THE SWARM" in wall.text())
hear_all(L)
L.execute("CLOCK = CLOCK + 200 NOW = NOW + 200000")
L.globals().SCR.draw(L.eval('SCR.POSTS[5]'), wall)
check("gone quiet for three minutes: NO SIGNAL SINCE, over the map", "NO SIGNAL SINCE 23:10" in wall.text())
panel = L.eval("makeMon(2, 2)")
L.globals().SCR.draw(L.eval('SCR.POSTS[4]'), panel)
check("and on a panel too", "NO SIGNAL SINCE" in panel.text())

# the uploaded status file, when there is no radio at all
L = fresh()
L.execute('''http = { get = function(url) URL = url return { readAll = function() return DOC end, close = function() end } end }
textutils.unserializeJSON = function(s) return PARSED end''')
L.globals().PARSED = tolua(L, {"units": {k: dict(u, seen=1794869000000) for k, u in status.items()}})
L.globals().DOC = "{}"
check("with no radio the uploaded status file is read", L.globals().SCR.loadStatusFile() is True
      and "status/status.json" in L.globals().URL)
wall = L.eval("makeMon(9, 4)")
L.globals().SCR.draw(L.eval('SCR.POSTS[5]'), wall)
t = wall.text()
check("and shown, marked as the file it is", "DigA" in t and "SHOWING THE 23:10 STATUS FILE" in t)

# ---------------------------------------------------------------- the other screens
L = fresh()
hear_all(L)
gate = L.eval("makeMon(2, 1)")
L.globals().SCR.draw(L.eval('SCR.POSTS[1]'), gate)
check("a gate light draws on its 2 x 1 (36 x 10)", tuple(gate.getSize()) == (36, 10) and len(gate.rows) == 10)
check("no drone at the gate: neither side lit", L.eval('SCR.gateView(SCR.POSTS[1])').active is None)
L.globals().SCR.hear(11, tolua(L, dict(status["11"], pos={"x": o.x + 2, "y": o.y + 2, "z": o.z + 1})))
check("a drone on the back track at the west gate lights OUT", L.eval('SCR.gateView(SCR.POSTS[1])').active == "OUT")
check("the east gate stays dark", L.eval('SCR.gateView(SCR.POSTS[2])').active is None)
L.globals().SCR.hear(12, tolua(L, dict(status["12"], pos={"x": o.x + 42, "y": o.y + 2, "z": o.z + 1})))
check("the back track at the east gate is the way IN", L.eval('SCR.gateView(SCR.POSTS[2])').active == "IN")
rack = L.eval("makeMon(8, 1)")
L.globals().SCR.draw(L.eval('SCR.POSTS[3]'), rack)
t = rack.text()
check("the rack board names the drones (not the factory or the builder)",
      "DigA" in t and "LoadB" in t and "HelpA" in t and "Forge" not in t and "Mason" not in t)

# ---------------------------------------------------------------- the rebuilt factory's sign boards
L = fresh()
p, how = L.eval("{SCR.identify(makeMon(3, 1))}").values()
check("a 3 x 1 with no name is the foundry board", p.name == "foundry board" and how == "monitor")
p, how = L.eval("{SCR.identify(makeMon(5, 1))}").values()
check("a 5 x 1 with no name is a plain floor board", p.name == "floor board" and how == "monitor")
ok = True
for label, name in (("WorksBoard", "works board"), ("FrontBoard", "front board"), ("MEBoard", "me board"),
                    ("FoundryBoard", "foundry board")):
    L.execute('LABEL = "%s"' % label)
    p, how = L.eval("{SCR.identify(makeMon(5, 1))}").values()
    ok = ok and p.name == name and how == "label"
check("a board is told by the name its station was given (three look the same)", ok)
L.execute('LABEL = "WallScreen"')
p, how = L.eval("{SCR.identify(makeMon(2, 1))}").values()
check("no other post is taken on a label alone", p.name == "west gate" and how == "monitor")
L.execute('LABEL = "MEBoard"')
at(L, "wall")
p, how = L.eval("{SCR.identify(makeMon(5, 1))}").values()
check("a GPS fix on an old post still comes first", p.name == "wall" and how == "gps")
L.execute("GPS = nil")
for size, cells in (((5, 1), (100, 10)), ((3, 1), (57, 10))):
    L = fresh()
    board = L.eval("makeMon(%d, %d)" % size)
    post = L.globals().SCR.byName("foundry board" if size[0] == 3 else "me board")
    zones = L.globals().SCR.draw(post, board)
    t = board.text()
    check("a %d x %d board is %d x %d and fills every row" % (size + cells),
          tuple(board.getSize()) == cells and len(board.rows) == 10 and all(len(board.rows[y]) == cells[0] for y in range(1, 11)))
    check("  nothing heard: it says so in words, and has nothing to tap",
          "WAITING FOR THE SWARM" in t and "0 working" in t and len(list(zones.values())) == 0)
    hear_all(L)
    L.globals().SCR.draw(post, board)
    t = board.text()
    check("  with reports: the fleet counted, and one drone named with what it is doing",
          "working" in t and "resting" in t and "WAITING" not in t
          and any(n in t for n in ("DigA", "DigB", "LoadA", "LoadB", "HelpA", "Mason", "Forge")))
    L.execute("CLOCK = CLOCK + 200 NOW = NOW + 200000")
    L.globals().SCR.draw(post, board)
    check("  gone quiet: NO SIGNAL SINCE", "NO SIGNAL SINCE 23:10" in board.text())

# ---------------------------------------------------------------- the desk computers
L = fresh()
ok = True
for label, name in (("WorksDesk", "works desk"), ("MEDesk", "me desk"), ("HangarDesk", "hangar desk"),
                    ("LogisticsDesk", "logistics desk"), ("ControlWest", "control west"), ("ControlEast", "control east")):
    L.execute('LABEL = "%s"' % label)
    p, how = L.eval("{SCR.identify(nil)}").values()
    ok = ok and p.name == name and p.kind == "desk" and how == "label"
check("a desk computer is told by its name, with no monitor at all", ok)
OWN = 'function ownScreen() local m = makeMon(1, 1) m.getSize = function() return 51, 19 end return m end'
L.execute(OWN)
desk = L.eval("ownScreen()")
post = L.globals().SCR.byName("me desk")
L.globals().SCR.draw(post, desk)
check("nothing heard: the desk says so on its own 51 x 19",
      len(desk.rows) == 19 and all(len(desk.rows[y]) == 51 for y in range(1, 20))
      and "No drone heard yet." in desk.text() and "WAITING FOR THE SWARM" in desk.text())
hear_all(L)
zones = L.globals().SCR.draw(post, desk)
t = desk.text()
check("with reports: every drone on a line, its state and fuel, and no stale words",
      all(n in t for n in ("DigA", "DigB", "LoadA", "LoadB", "HelpA", "Mason", "Forge"))
      and "mining" in t and "fuel 2774" in t and "live" in t and "WAITING" not in t)
z = [z for z in zones.values() if z[5] == "unit:DigA"][0]
L.globals().SCR.tap(L.globals().SCR.zoneAt(zones, z[1] + 3, z[2]), post)
L.globals().SCR.draw(post, desk)
check("a click on a drone says where it is and what it last said",
      "at -4414, -21, 1562" in desk.text() and "Layer 24/37" in desk.text())
many = dict(status)
for i in range(30):
    many[str(100 + i)] = {"label": "Bot%02d" % i, "role": "miner", "state": "mining", "fuel": 1000 + i,
                          "pos": {"x": -4500 + i, "y": 10, "z": 1500}, "log": ["x"]}
L = fresh()
L.execute(OWN)
hear_all(L, many)
desk = L.eval("ownScreen()")
seen = set()
for k in range(6):
    L.execute("CLOCK = %d" % (1000 + 8 * k))
    L.globals().SCR.draw(L.globals().SCR.byName("works desk"), desk)
    seen |= {("Bot%02d" % i) for i in range(30) if ("Bot%02d" % i) in desk.text()}
check("thirty-seven drones: the list pages, and every drone gets its turn", len(seen) == 30 and "page" in desk.text())

# ---------------------------------------------------------------- the lobby doors
L = fresh()
ok = True
for label, name in (("LobbyDoorWest", "lobby door west"), ("LobbyDoorEast", "lobby door east"),
                    ("WorksDoorHall", "works door hall side"), ("WorksDoorWorks", "works door works side")):
    L.execute('LABEL = "%s"' % label)
    p, how = L.eval("{SCR.identify(nil)}").values()
    ok = ok and p.name == name and p.kind == "door" and how == "label"
check("a door computer is told by its name", ok)
L.execute(r'''
OUT, RELAY, NEAR, LOG, STEPS = {}, {}, {}, {}, 0
rs = { getSides = function() return { "top", "bottom", "left", "right", "front", "back" } end,
  setOutput = function(side, on) OUT[side] = on end }
settings = { get = function() end }
DET = { getPlayersInRange = function(r) RANGE = r return NEAR end }
peripheral = { getNames = function() return { "left", "right" } end,
  getType = function(n) return n == "right" and "redstone_relay" or "player_detector" end,
  call = function(n, m, side, on) RELAY[side] = on end,
  find = function(t) if t == "player_detector" then return DET end end }
-- the script: each sleep is a step; what happens at which step
SCRIPT = {}
sleep = function(t)
  CLOCK = CLOCK + t
  STEPS = STEPS + 1
  LOG[#LOG + 1] = { OUT.top == true, RELAY.top == true, CLOCK }
  local f = SCRIPT[STEPS]
  if f then f() end
  if STEPS >= 40 then error("done", 0) end
end
SCRIPT[3] = function() NEAR = { "someone" } end
SCRIPT[6] = function() NEAR = {} end
''')
L.execute("pcall(SCR.doorLoop, function() end)")
log = [tuple(v.values()) for v in L.eval("LOG").values()]
check("it opens once as it starts, on its own sides and on the relay, then shuts", log[0][0] and log[0][1] and not log[1][0] and not log[1][1])
check("someone near: open on the next look", log[3][0] and log[3][1] and L.eval("RANGE") == 3)
closed = next(i for i in range(6, 40) if not log[i][0])
check("it stays open a moment after they leave, then shuts on both", 1.4 <= log[closed][2] - log[5][2] <= 2.0 and not log[closed][1] and not any(l[0] for l in log[closed:]))
L.execute("STEPS, LOG, NEAR = 0, {}, { 'x' } DET = nil OUT, RELAY = {}, {} SCRIPT = {}")
L.execute("peripheral.find = function() end")
L.execute("pcall(SCR.doorLoop, function() end)")
log = [tuple(v.values()) for v in L.eval("LOG").values()]
check("no detector: the door stays shut after its opening look", not any(l[0] or l[1] for l in log[1:]))

# ---------------------------------------------------------------- orders for the ME store
L = fresh()
L.execute(r'''
ASKED, STORE = {}, { ["minecraft:iron_ingot"] = 12, ["ad_astra:steel_plate"] = 0 }
BRIDGE = { getItem = function(f) return STORE[f.name] and { name = f.name, count = STORE[f.name] } or nil end,
  craftItem = function(f) ASKED[#ASKED + 1] = f.name .. " x" .. f.count if f.name == "minecraft:bedrock" then return false, "no pattern" end return true end }
peripheral = { find = function(t) if t == "me_bridge" then return BRIDGE end end }
''')
line = L.eval('SCR.meOrder({ cmd = "craft", item = "ad_astra:steel_plate", n = 4 })')
check("a craft order asks the ME bridge and says it started", list(L.eval("ASKED").values()) == ["ad_astra:steel_plate x4"] and "started" in line and "before: 0" in line)
line = L.eval('SCR.meOrder({ cmd = "craft", item = "minecraft:bedrock", n = 1 })')
check("a craft the network refuses says why", "refused: no pattern" in line)
line = L.eval('SCR.meOrder({ cmd = "stock", items = "minecraft:iron_ingot,ad_astra:steel_plate,minecraft:dirt" })')
check("a stock order counts each thing asked about", line == "stock iron_ingot=12 steel_plate=0 dirt=?")
check("what came of them is kept for the report", L.eval("#SCR.S.me") == 3)
L.execute(r'''
sleep = function() end
BRIDGE.isCraftable = function(f) return f.name == "ad_astra:steel_plate" end
BRIDGE.craftItem = function(f)
  if f.name == "x:short" then return { isCalculationNotSuccessful = function() return true end,
    getDebugMessage = function() return "MISSING_ITEMS" end, getMissingItems = function() return { { name = "minecraft:coal", count = 3 } } end } end
  return { isCalculationNotSuccessful = function() return false end, isCraftingStarted = function() return true end }
end
''')
check("a job the network starts is reported as under way", "under way" in L.eval('SCR.meOrder({ cmd = "craft", item = "ad_astra:steel_plate", n = 1 })'))
line = L.eval('SCR.meOrder({ cmd = "craft", item = "x:short", n = 1 })')
check("a job it cannot plan says why and what is short", "not planned: MISSING_ITEMS" in line and "coal x3" in line)
L.execute('BRIDGE.cancelCraftingTasks = function(f) return 2 end BRIDGE.getCraftingTasks = function() return { { resource = { name = "x:rocket" }, crafted = 0, quantity = 1 } } end')
check("a cancel order says how many jobs it stopped", L.eval('SCR.meOrder({ cmd = "cancel", item = "x:rocket" })') == "cancel x:rocket: 2 job(s) cancelled")
check("a jobs order lists what is being made", L.eval('SCR.meOrder({ cmd = "jobs" })') == "jobs: rocket 0/1")
check("a recipes order says which things have a pattern", L.eval('SCR.meOrder({ cmd = "recipes", items = "ad_astra:steel_plate,minecraft:dirt" })') == "recipes steel_plate=yes dirt=no")
L.execute("peripheral.find = function() end")
check("no bridge: it says so", "no ME bridge" in L.eval('SCR.meOrder({ cmd = "craft", item = "x:y" })'))

# ---------------------------------------------------------------- the GPS hosts
L = fresh()
ok = True
for label, at in (("GpsA", (-4462, 68, 1528)), ("GpsB", (-4388, 68, 1551)), ("GpsC", (-4428, 68, 1553)), ("GpsD", (-4391, 129, 1533))):
    L.execute('LABEL = "%s"' % label)
    p, how = L.eval("{SCR.identify(nil)}").values()
    ok = ok and p.kind == "gps" and how == "label" and tuple(p.at.values()) == at
check("a GPS host is told by its name and knows where it stands", ok)
hosts = [tuple(p.at.values()) for p in L.eval("SCR.BOARDS").values() if p.kind == "gps"]
import itertools
def vol(a, b, c, d):
    u, v, w = [[q[i] - a[i] for i in range(3)] for q in (b, c, d)]
    return abs(u[0] * (v[1] * w[2] - v[2] * w[1]) - u[1] * (v[0] * w[2] - v[2] * w[0]) + u[2] * (v[0] * w[1] - v[1] * w[0]))
check("four hosts, far apart and not in one plane (or a fix has two answers)", len(hosts) == 4 and vol(*hosts) > 50000
      and all(sum((a[i] - b[i]) ** 2 for i in range(3)) > 30 ** 2 for a, b in itertools.combinations(hosts, 2)))
L.execute('RAN = {} shell = { run = function(...) RAN[#RAN + 1] = table.concat({ ... }, " ") end } sleep = function() error("done", 0) end')
L.execute('pcall(SCR.gpsHost, SCR.byName("gps host d"), function() end)')
check("it runs the stock host program with its own position", list(L.eval("RAN").values()) == ["gps host -4391 129 1533"])

# ---------------------------------------------------------------- the street gates
L = fresh()
ok = True
for label, name in (("FrontGate", "front gate"), ("WorksGate", "works gate")):
    L.execute('LABEL = "%s"' % label)
    p, how = L.eval("{SCR.identify(nil)}").values()
    ok = ok and p.name == name and p.kind == "hoist" and how == "label"
check("a gate computer is told by its name", ok)
L.execute(r'''
MOVES, NEAR, STEPS, RUN, BOX, SAID = {}, false, 0, 0, nil, {}
settings = { get = function() end }
GEAR = { move = function(d, m) MOVES[#MOVES + 1] = { d, m, CLOCK } RUN = 6 end, isRunning = function() return true end }
DET = { isPlayersInCoords = function(a, b) BOX = { a.x, a.y, a.z, b.x, b.y, b.z } return NEAR end }
peripheral = { find = function(t) if t == "Create_SequencedGearshift" then return GEAR elseif t == "player_detector" then return DET end end }
SCRIPT = {}
sleep = function(t)
  CLOCK = CLOCK + t
  STEPS = STEPS + 1
  if RUN > 0 then RUN = RUN - 1 end
  local f = SCRIPT[STEPS]
  if f then f() end
  if STEPS >= 120 then error("done", 0) end
end
SCRIPT[60] = function() NEAR = true end
SCRIPT[62] = function() NEAR = false end
SCRIPT[63] = function() NEAR = true end
SCRIPT[70] = function() NEAR = false end
''')
L.execute('pcall(SCR.hoistLoop, SCR.byName("front gate"), function(state) SAID[#SAID + 1] = state end)')
moves = [tuple(v.values()) for v in L.eval("MOVES").values()]
check("it goes up as it starts, and down again with nobody there, once the leaf has had time to get up",
      moves[0][:2] == (7, 1) and moves[1][:2] == (7, -1) and 6.5 <= moves[1][2] - moves[0][2] <= 7.5)
check("someone in its box: up; a moment out of it does not send it down", moves[2][:2] == (7, 1) and len(moves) == 4)
check("they leave soon after: it still finishes going up before it starts down (never an order while the leaf moves)",
      moves[3][:2] == (7, -1) and all(b[2] - a[2] >= 6.5 for a, b in zip(moves, moves[1:])))
check("it asks about its own box of ground", list(L.eval("BOX").values()) == [-4434, 70, 1545, -4424, 75, 1555])
check("it says what it did", list(L.eval("SAID").values())[:2] == ["up", "down"])
L.execute("MOVES, STEPS, SAID, SCRIPT = {}, 0, {}, {} peripheral.find = function() end")
L.execute('pcall(SCR.hoistLoop, SCR.byName("works gate"), function(state) SAID[#SAID + 1] = state end)')
check("no gearshift touching it: no orders, and it says so", L.eval("#MOVES") == 0 and list(L.eval("SAID").values())[0] == "no gearshift")

# ---------------------------------------------------------------- panels and their buttons
for idx, size, title in ((4, (2, 2), "LAUNCH BAY"), (6, (3, 2), "CONTROL")):
    L = fresh()
    hear_all(L)
    post = L.eval('SCR.POSTS[%d]' % idx)
    panel = L.eval("makeMon(%d, %d)" % size)
    zones = L.globals().SCR.draw(post, panel)
    t = panel.text()
    ids = [z[5] for z in zones.values()]
    check("%s panel: three buttons, counts in words" % title.lower(),
          ids == ["miners_home", "miners_resume", "refresh"] and "MINERS HOME" in t and "working" in t and "low fuel" in t)
    z = [z for z in zones.values() if z[5] == "miners_home"][0]
    hit = L.globals().SCR.zoneAt(zones, z[1] + 1, z[2] + 1)
    L.globals().SCR.tap(hit, post)
    check("  one tap sends nothing", len(L.globals().SENT) == 0)
    L.globals().SCR.draw(post, panel)
    check("  the button says TAP AGAIN", "TAP AGAIN" in panel.text())
    L.globals().SCR.tap(hit, post)
    sent = L.globals().SENT
    check("  the second tap asks the controller (and orders nothing itself)",
          len(sent) == 1 and sent[1].proto == "swarm_panel" and sent[1].msg.ask == "miners_home"
          and sent[1].msg.type == "ask")
    L.globals().SCR.answer(tolua(L, {"type": "ack", "n": sent[1].msg.n, "ok": True, "text": "Sent: miners home (2)"}))
    L.globals().SCR.draw(post, panel)
    check("  the controller's answer shows on the panel", "Sent: miners home (2)" in panel.text())
    L.execute("SENT = {}")
    L.globals().SCR.tap(hit, post); L.execute("CLOCK = CLOCK + 10"); L.globals().SCR.tap(hit, post)
    check("  two taps ten seconds apart send nothing", len(L.globals().SENT) == 0)
    L.globals().SCR.tap(hit, post)
    L.execute("CLOCK = CLOCK + 8")
    L.globals().SCR.draw(post, panel)
    check("  no answer in six seconds: it says so", "Control did not answer" in panel.text())

# the wall's own buttons go the same way
L = fresh()
hear_all(L)
post = L.eval('SCR.POSTS[5]')
L.globals().SCR.tap("recall", post); L.globals().SCR.tap("recall", post)
check("the wall's RECALL ALL asks the controller too", L.globals().SENT[1].msg.ask == "recall")

# ---------------------------------------------------------------- what the controller will pass on
units = tolua(L, status)
def orders(ask):
    lst, words = L.eval("function(a, u) return swarm.panelOrders(a, u) end")(ask, units)
    return ([(o.cmd, o.target) for o in lst.values()] if lst else None), words
check("miners home: one order per miner, by name", orders("miners_home")[0] == [("home", "DigA"), ("home", "DigB")])
check("miners resume likewise", orders("miners_resume")[0] == [("resume", "DigA"), ("resume", "DigB")])
check("refresh is a ping to all", orders("refresh")[0] == [("ping", "all")])
check("pause stops builders only", orders("pause")[0] == [("stop", "Mason")])
ok = True
for bad in ("reboot", "lab", "fit", "stop", "home", "feed", "", "build"):
    lst, why = orders(bad)
    ok = ok and lst is None
check("nothing else is passed on (reboot, lab, fit, stop, ...)", ok)
print("PASS" if not fails else "FAILED: %d" % len(fails))
