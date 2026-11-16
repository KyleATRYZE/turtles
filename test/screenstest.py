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
