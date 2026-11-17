"""The loading bays and the watchdog (docs/factory-retrofit.md 6b).

1. Crafty hands a load to a helper docked in its bay over the cable: hand-ins
   pulled back first, the load and fuel pushed straight in, materials_ready
   sent; no load_ready, no pad. Not on the cable: it waits and tries again.
2. The watchdog: a helper waiting over 10 minutes has its load announced
   again, 5 minutes later it is told to reboot; it is listed as stalled.
3. The Counter fallback: a Counter's load left ready 3 minutes is taken
   over by Crafty (and the Counter told to drop it).
4. The helper: in its bay it says its name on the cable and what goes back;
   with the bay modem off, it says so.
5. rack.lua: panels per home, green docked / amber out / grey free; a tap
   shows that drone's screen.

    cd test && python3 baytest.py
"""
import os, lupa
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(HERE)
fails = []
def check(what, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + what + (" | " + str(detail) if detail != "" else ""))
    if not ok: fails.append(what)

FAC = open(os.path.join(ROOT, "factory.lua")).read()
HEL = open(os.path.join(ROOT, "helper.lua")).read()
HARNESS = open(os.path.join(HERE, "fharness.lua")).read().replace("/home/claude/turtles", ROOT)

# ---------------------------------------------------------------- 1. a load into a bay
def factory(inbox, setup=""):
    L = lupa.LuaRuntime(unpack_returned_tuples=True); L.execute("MODEM_ON=true"); L.execute(HARNESS)
    L.execute('''C="minecraft:chest_0"
put(C,"minecraft:cobblestone",64) put(C,"minecraft:coal",64) put("minecraft:chest_1","minecraft:lava_bucket",1)
INV.turtle_40 = { size = 16, items = { [1] = { name = "minecraft:bucket", count = 1 }, [2] = { name = "minecraft:torch", count = 5 } } }
local pc = peripheral.call
peripheral.isPresent = function(n) return INV[n] ~= nil end
FILES[".plots"]='{["next"]=7,["done"]=0,["hunter"]=true,["builderId"]=14,["helpers"]={40},["loaders"]={},["byId"]={}}'
MAX_IDLES=1''' + setup)
    L.eval('{runFactory()}')
    L.execute("IDLES=0 MAX_IDLES=3 INBOX = {%s}" % inbox)
    r = L.eval('{runFactory()}')
    return L, L.globals()
ORDER = '{id=40,msg={type="materials",id=40,n=7,fuel=20,items={{"minecraft:cobblestone",40}},bay="turtle_40",back={1}}}'
L, g = factory(ORDER)
t40 = {}
for s, it in g.INV.turtle_40["items"].items():
    t40[it.name] = t40.get(it.name, 0) + it.count
sent = [m for m in g.OUTBOX.values() if m.to == 40]
check("the load goes straight into the bay: 40 cobblestone", t40.get("minecraft:cobblestone") == 40, t40)
check("with its fuel (the lava bucket first, then coal)", t40.get("minecraft:lava_bucket") == 1
      and t40.get("minecraft:coal", 0) > 0, t40)
check("the empty bucket it handed back is in storage; the torches stay", t40.get("minecraft:bucket") is None
      and t40.get("minecraft:torch") == 5 and L.eval('total("minecraft:chest_0","minecraft:bucket") + total("minecraft:chest_1","minecraft:bucket")') == 1)
check("materials_ready says so (bay=true); no load_ready, no pad",
      any(m.msg.type == "materials_ready" and m.msg.bay for m in sent) and not any(m.msg.type == "load_ready" for m in sent),
      [m.msg.type for m in sent])
L, g = factory(ORDER.replace("turtle_40", "turtle_41"))
sent = [m for m in g.OUTBOX.values() if m.to == 40]
check("a bay not on Crafty's cable (Sortnado's, before the move): nothing handed over, nothing sent to the pad",
      not any(m.msg.type in ("materials_ready", "load_ready") for m in sent), [m.msg.type for m in sent])
check("  and Crafty makes nothing for it (the store serves it; the rest comes back as a pad order)",
      not any("Preparing a load" in l for l in g.LOG.values()), list(g.LOG.values())[-3:])
check("(on its cable but not docked when the load is made: tried again every 15 s)", "o.tried or 0) > 15" in FAC)
check("a name that is not turtle_<n> is not taken as a bay", 'b:match("^turtle_%d+$")' in FAC)

# ---------------------------------------------------------------- 2-3. watchdog and Counter fallback
wd = FAC[FAC.index("function K.waiting(state)"):FAC.index("-- what a drone said, passed on over the cable")]
def watch():
    L = lupa.LuaRuntime(unpack_returned_tuples=True)
    L.execute('''K = { COUNTER = false, foreign = {}, adopted = {}, stall = {}, stalledList = {},
  COUNTER_GIVE_UP = 180, STALL_AFTER = 600, STALL_REBOOT = 300, JOB_PROTOCOL = "swarm_job" }
fleet, orders, SENT, BCAST, DIRECT = {}, {}, {}, {}, {}
base = { pad = { x = 1, y = 2, z = 3 }, f = { x = 0, y = 2, z = 3 } }
swarm = {}
rednet = { send = function(id, m) SENT[#SENT + 1] = { id, m } end, broadcast = function(m) BCAST[#BCAST + 1] = m end }
function direct(id, o) DIRECT[#DIRECT + 1] = { id, o.cmd } end
function print() end
''')
    L.execute(wd)
    return L
L = watch()
L.execute('''fleet.hopto = { id = 21, label = "HopTo", role = "helper", state = "waiting for materials", since = 0, at = 650 }
fleet.pushy = { id = 20, label = "Pushy", role = "helper", state = "building", since = 0, at = 650 }
orders[21] = { ready = true, n = 4, items = {} }
K.watchdog(500)''')
check("waiting 8 minutes: left alone", L.eval("#SENT") == 0 and L.eval("#K.stalledList") == 0)
L.execute("K.watchdog(660)")
check("over 10 minutes: its load announced again, and it is listed as stalled",
      L.eval("#SENT") == 1 and L.eval("SENT[1][2].type") == "load_ready" and L.eval("K.stalledList[1]") == "HopTo"
      and L.eval("#K.stalledList") == 1)
L.execute("fleet.hopto.at = 900 K.watchdog(900)")
check("4 minutes on: nothing more yet", L.eval("#DIRECT") == 0 and L.eval("#SENT") == 1)
L.execute("fleet.hopto.at = 970 K.watchdog(970)")
check("5 minutes on and still waiting: told to reboot (a direct order)", L.eval("#DIRECT") == 1
      and L.eval("DIRECT[1][1]") == 21 and L.eval("DIRECT[1][2]") == "reboot")
L.execute("fleet.hopto.state = 'building' fleet.hopto.since = 980 K.watchdog(1000)")
check("working again: off the stalled list", L.eval("#K.stalledList") == 0 and L.eval("K.stall.hopto") is None)
L.execute('''fleet.dusty = { id = 25, label = "Dusty", role = "helper", state = "stuck under glass", since = 0, at = 2000 }
K.watchdog(2000)''')
check("'stuck under ...' counts as waiting", L.eval("K.stalledList[1]") == "Dusty")
L.execute('''fleet.dusty.at = 100 K.stall = {} K.watchdog(2000)''')
check("a drone not heard for 5 minutes is not the watchdog's (it is silent, not waiting)",
      L.eval("#K.stalledList") == 0)
# the Counter fallback
L = watch()
L.execute('''K.foreign[23] = { items = { { "minecraft:stone", 8 } }, fuel = 4, n = 9, at = 0, readyAt = 100 }
K.watchdog(250)''')
check("a Counter's load ready 2.5 minutes: still the Counter's", L.eval("orders[23]") is None)
L.execute("K.watchdog(290)")
check("ready over 3 minutes and not collected: Crafty takes it over", L.eval("orders[23] and orders[23].n") == 9
      and L.eval("K.adopted[23]") is True and L.eval("K.foreign[23]") is None)
check("  and tells the Counter to drop it", L.eval("BCAST[1].type") == "counter_drop" and L.eval("BCAST[1].forId") == 23)
L = watch()
L.execute('''K.foreign[23] = { items = {}, fuel = 4, n = 9, at = 0 }
fleet.dropit = { id = 23, label = "DropIt", role = "helper", state = "waiting for materials", since = 0, at = 700 }
K.watchdog(700)''')
check("the watchdog takes over a Counter's load even when no 'ready' was heard (an old Counter)",
      L.eval("K.adopted[23]") is True and L.eval("orders[23].n") == 9)
split = FAC[FAC.index("do\n  local digits"):FAC.index("return share == 0 or not K.alive(share)\nend") + len("return share == 0 or not K.alive(share)\nend")]
L = lupa.LuaRuntime(unpack_returned_tuples=True)
L.execute("CLOCK = 1000 os.clock = function() return CLOCK end K = {} LABEL = 'Crafty' os.getComputerLabel = function() return LABEL end")
L.execute(split)
L.execute("K.adopted = {} K.counters[1] = 990")
a = L.eval("K.mine(23)")
L.execute("K.adopted[23] = true")
check("an odd id is the Counter's, until Crafty adopts its load", a is False and L.eval("K.mine(23)") is True)
check("the Counter says when a load is ready and when it is handed over",
      'type = "counter_ready"' in FAC and 'type = "counter_handed"' in FAC and 'msg.type == "counter_drop" and K.COUNTER' in FAC)
check("Crafty's status lists the stalled drones", "stalled = (not K.COUNTER and #K.stalledList > 0)" in FAC)

# ---------------------------------------------------------------- 4. the helper in its bay
bayfn = HEL[HEL.index("function LN.bay()"):HEL.index("local function hover()")]
L = lupa.LuaRuntime(unpack_returned_tuples=True)
L.execute('''LN = {} TYPES = {} ON = true
peripheral = { getType = function(s) return TYPES[s] end,
  call = function(s, m) if m == "isWireless" then return s == "left" end if m == "getNameLocal" then return ON and "turtle_40" or nil end end }''')
L.execute(bayfn)
L.execute('TYPES.left = "modem" TYPES.bottom = "modem"')
check("docked in a high home: the shelf modem under it gives its name on the cable", L.eval("LN.bay()") == "turtle_40")
L.execute("ON = false")
check("the shelf modem switched off: no name (it says 'bay modem off' and uses the pad)", L.eval("LN.bay()") is None
      and 'report("bay modem off")' in HEL)
L.execute('ON = true TYPES = { left = "modem" }')
check("an ender modem is not a bay", L.eval("LN.bay()") is None)
hb = HEL[HEL.index("local function handsBack(it)"):HEL.index("-- Home for a load: wait in the air")]
L = lupa.LuaRuntime(unpack_returned_tuples=True)
L.execute("st = {} function isKit(n) return n == 'computercraft:wireless_modem_advanced' end")
L.execute(hb.replace("local function handsBack", "function handsBack"))
check("hand-ins: an emptied bucket goes back; the kit and anything else stays",
      L.eval('handsBack({ name = "minecraft:bucket" })') is True and L.eval('handsBack({ name = "minecraft:stone" })') is False)
L.execute('st.fdy = { keep = { ["mekanism:steel_ingot"] = true } }')
check("  on a foundry run, whatever it was not sent for goes back",
      L.eval('handsBack({ name = "minecraft:cobblestone" })') is True and L.eval('handsBack({ name = "mekanism:steel_ingot" })') is False)
check("the order carries the bay and the hand-in slots", "msg.bay, msg.back = bay, {}" in HEL
      and "local bay = LN.on() and not noBay and LN.bay() or nil" in HEL)

# ---------------------------------------------------------------- 5. rack.lua
L = lupa.LuaRuntime(unpack_returned_tuples=True)
L.execute('''RACK_TEST = true colours = { black = 32768, white = 1, yellow = 16, green = 8192, orange = 2, grey = 128, red = 16384 }
os.clock = function() return 100 end
peripheral = { getNames = function() return {} end }''')
R = L.execute("return dofile(%r)" % os.path.join(ROOT, "rack.lua"))
L.globals().R = R
L.execute('''R.hear({ label = "HopTo", role = "helper", id = 21, state = "idle", fuel = 1500, pos = { x = -4428, y = 72, z = 1521 },
  screen = { "Waiting for jobs.", "line two" } }, 100)
R.hear({ label = "Pushy", role = "helper", id = 20, state = "building", fuel = 900, pos = { x = 0, y = 90, z = 0 } }, 100)
R.hear({ label = "NoteWorthy", role = "helper", id = 33, state = "idle", fuel = 50, pos = { x = -4423, y = 74, z = 1521 } }, 100)
R.hear({ label = "Crafty", role = "factory", id = 12, state = "x" }, 100)''')
p = lambda i: L.eval("R.panel(%d, 110)" % i)
check("HopTo docked in home 1 (low row): green", p(1).colour == "green" and p(1).word == "docked" and p(1).name == "HopTo")
check("Pushy out on a job: amber, with its state", p(0).colour == "orange" and p(0).state == "building")
check("NoteWorthy docked in home 14 (high row): green", p(14).colour == "green")
check("a home nobody has: grey, free", p(5).colour == "grey" and p(5).word == "free")
check("the factory is not on the rack", L.eval("R.units.Crafty") is None)
check("not heard for 5 minutes: silent (red)", L.eval("R.panel(1, 500)").colour == "red")
L.execute('''MON = { size = { 164, 10 }, rows = {} }
local cx, cy = 1, 1
function MON.getSize() return MON.size[1], MON.size[2] end
function MON.setTextScale() end function MON.setBackgroundColour() end function MON.setTextColour() end
function MON.clear() MON.rows = {} end
function MON.setCursorPos(x, y) cx, cy = x, y end
function MON.write(t) local r = MON.rows[cy] or (" "):rep(MON.size[1]) MON.rows[cy] = (r:sub(1, cx - 1) .. t .. r:sub(cx + #t)):sub(1, MON.size[1]) cx = cx + #t end
R.draw(MON, 0, 110, "monitor_4")''')
row1 = L.eval("MON.rows[1]")
check("the low strip: eight panels, names along the top", "Pushy" in row1 and "HopTo" in row1, row1)
L.execute('R.tap(MON, 0, 25, 110, "monitor_4") R.draw(MON, 0, 111, "monitor_4")')
check("a tap on HopTo's panel shows its screen", "HopTo's screen" in L.eval("MON.rows[1]") and "Waiting for jobs." in L.eval("MON.rows[2]"))
L.execute('R.tap(MON, 0, 25, 112, "monitor_4") R.draw(MON, 0, 112, "monitor_4")')
check("a second tap closes it", "Pushy" in L.eval("MON.rows[1]"))
check("Crafty passes the drones' statuses (and reboot orders) on over the cable",
      "K.relay(msg)" in FAC and 'type = "cmd", cmd = cmd' in FAC)
UPD = open(os.path.join(ROOT, "update.lua")).read()
check("rack.lua is in the manifest, the rack role runs it, turtles skip it",
      "rack.lua" in open(os.path.join(ROOT, "manifest.txt")).read() and 'job = \'shell.run("rack")\'' in UPD
      and UPD.count('["rack.lua"] = true') == 5)

# ---------------------------------------------------------------- 6. before the move: Sortnado serves the bays
import re
SW = re.search(r"WORLD = \'\'\'(.*?)\'\'\'", open(os.path.join(HERE, "sortctl.py")).read(), re.S).group(1)
L = lupa.LuaRuntime(unpack_returned_tuples=True)
L.execute("ROOT = %r" % ROOT)
L.execute(SW)
L.execute('''
fresh({ slots = 600, sides = {} })
addTo(CTL, "minecraft:cobblestone", 300) addTo(CTL, "minecraft:coal", 64)
S.scan()
INV.turtle_40 = { size = 16, cap = 64, slots = { [1] = { name = "minecraft:bucket", count = 1 } } }
SENTJ = {}
rednet = { send = function(id, m, p) SENTJ[#SENTJ + 1] = { id = id, m = m, p = p } end }
peripheral.isPresent = function(n) return INV[n] ~= nil end
local call = peripheral.call
peripheral.call = function(n, m, a, b, c)
  if m == "pullItems" then local st = INV[a].slots[b] if not st then return 0 end
    local left = addTo(n, st.name, st.count) local k = st.count - left st.count = left if left == 0 then INV[a].slots[b] = nil end return k end
  return call(n, m, a, b, c)
end
MSG = { type = "materials", id = 40, n = 3, fuel = 8, bay = "turtle_40", back = { 1 },
  items = { { "minecraft:cobblestone", 100 }, { "mekanism:basic_control_circuit", 4 } } }
S.bayHeard(40, MSG, 0)
S.bayStep(5)
''')
check("before the move: a bay on the store's cable is not served at once (Crafty may take it)",
      L.eval("#SENTJ") == 0 and L.eval("S.bayQueue[40] ~= nil") is True)
L.execute("S.bayStep(11)")
t40 = {}
for st in L.eval("INV.turtle_40.slots").values():
    t40[st.name] = t40.get(st.name, 0) + st.count
r = L.eval("SENTJ[1] and SENTJ[1].m")
check("10 s on and nobody took it: the store puts in what it has (100 cobblestone) and fuel",
      t40.get("minecraft:cobblestone") == 100 and t40.get("minecraft:coal", 0) == 8, t40)
check("  the empty bucket goes into the In chest (sorted away as usual)", t40.get("minecraft:bucket") is None
      and L.eval('total(IN, "minecraft:bucket")') == 1)
check("  and the answer says what it lacks, from Sortnado (the helper fetches that from the pad)",
      r is not None and r.by == "Sortnado" and r.bay is True and r.missing["mekanism:basic_control_circuit"] == 4
      and r.given["minecraft:cobblestone"] == 100 and L.eval("SENTJ[1].p") == "swarm_job")
L.execute('''SENTJ = {} MSG.n = 4 S.bayHeard(40, MSG, 20) S.bayHeard(12, { type = "bay_taken", forId = 40, n = 4 }, 21) S.bayStep(40)''')
check("Crafty on the same cable says bay_taken: the store leaves it alone", L.eval("#SENTJ") == 0
      and L.eval("S.bayQueue[40]") is None)
L.execute('''MSG2 = { type = "materials", id = 41, n = 1, bay = "turtle_41", items = {} } S.bayHeard(41, MSG2, 50)''')
check("a bay that is not on the store's cable is not the store's", L.eval("S.bayQueue[41]") is None)
check("Crafty records a bay order only when the bay is on its own cable, and says bay_taken",
      "if bay and not (modem and peripheral.isPresent(bay)) then" in FAC and 'type = "bay_taken"' in FAC)
check("the helper: what the store lacked comes from the pad straight away; nobody serving the bay in 90 s: the pad",
      'reply.by == "Sortnado" and next(reply.missing or {})' in HEL and "os.clock() - started > 90" in HEL
      and "local bay = LN.on() and not noBay and LN.bay() or nil" in HEL)
check("before the move the pad is not on the lane: the helper reaches it the old way (out of the lane first)",
      "function LN.padOnLane(p)" in HEL and "LN.on() and LN.padOnLane(padAt and padAt.pad or base.pad)" in HEL)
SN = open(os.path.join(ROOT, "sortnado.lua")).read()
check("Sortnado passes the drones' statuses and reboots on to the rack's panels",
      "S.relay(msg)" in SN and 'pcall(S.relay, { type = "cmd", cmd = c })' in SN)
check("a new computer labelled RackBoard (or Works) installs as the rack's panels (the works)",
      'match("^rack") then\n    role = "rack"' in UPD and 'match("^works") then\n    role = "works"' in UPD)

print("PASS" if not fails else "FAILED: %d" % len(fails))
