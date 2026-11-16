# The renaming of the swarm (swarm.RENAMES): every machine renames itself at
# start-up, and nothing breaks while some have the old names and some the
# new. Runs from anywhere:  python3 test/renametest.py
import os, re, lupa
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(HERE)
def harness(name): return open(os.path.join(HERE, name)).read().replace('/home/claude/turtles', ROOT)
fails = []
def check(what, ok):
    print(("ok   " if ok else "FAIL ") + what)
    if not ok: fails.append(what)

# ---------------------------------------------------------------- the table itself
src = open(os.path.join(ROOT, 'swarm.lua')).read()
table = dict(re.findall(r'(\w+) = "(\w+)"', src[src.index('M.RENAMES = {'):src.index('local OLD_NAMES')]))
WANT = dict(GroundControl="CommandBlock", ForgeClooney="Crafty", BrickJagger="BlockParty", MortarKombat="Pushy",
    WallStreet="HopTo", SteelyDan="DropIt", TimberLake="LeverAlone", ChunkNorris="Ghastly", LoadRunner="Phantastic",
    ChunkBerry="Ablaze", OreLando="Oresome", ElvisPitsley="Pickle", BoulderDash="Cobbler", NotoriousDIG="TuffLuck",
    QuarryStyles="CleanSlate", ObiWanKenOrebi="Granted", OreSonWelles="Bedrocker", CoalPorter="Coalition", NatKingCoal="Charcool")
check("the table has Kyle's map", all(table.get(k) == v for k, v in WANT.items()))
check("no new name is also an old name, and no two old names share a new one",
      not (set(table) & set(table.values())) and len(set(table.values())) == len(table))
old_rx = re.compile(r'(?<![A-Za-z0-9_])(' + '|'.join(table) + r')(?![A-Za-z0-9_])')
left = []
for dirpath, dirs, files in os.walk(ROOT):
    dirs[:] = [d for d in dirs if d not in ('.git', 'test', 'maps', '__pycache__')]
    for f in files:
        if f.endswith(('.lua', '.py', '.md', '.html', '.txt')) and not (f == 'swarm.lua' and dirpath == ROOT):
            if old_rx.search(open(os.path.join(dirpath, f), errors='ignore').read()): left.append(os.path.relpath(os.path.join(dirpath, f), ROOT))
check("old names are nowhere but the table in swarm.lua %s" % (left or ""), not left)

# ---------------------------------------------------------------- swarm.lua alone
ENV = r'''
CLOCK = 5
os.clock = function() return CLOCK end
os.epoch = function() return 1700000000000 end
os.getComputerID = function() return ID or 17 end
os.getComputerLabel = function() return LABEL end
os.setComputerLabel = function(l) LABEL = l end
FS = {}
fs = { exists = function(f) return FS[f] ~= nil end, delete = function(f) FS[f] = nil end,
  open = function(f, mode)
    if mode == "w" then local buf = {} return { write = function(s) buf[#buf + 1] = s end, close = function() FS[f] = table.concat(buf) end } end
    return { readAll = function() return FS[f] end, close = function() end } end }
local function ser(v)
  if type(v) == "table" then local parts = {}
    for k, val in pairs(v) do parts[#parts + 1] = "[" .. (type(k) == "string" and string.format("%q", k) or tostring(k)) .. "]=" .. ser(val) end
    return "{" .. table.concat(parts, ",") .. "}"
  elseif type(v) == "string" then return string.format("%q", v) else return tostring(v) end
end
textutils = { serialize = ser, unserialize = function(s) local f = load("return " .. s) return f and f() end }
peripheral = { find = function() return nil end, getName = function() return "left" end, getType = function() return nil end }
rednet = { open = function() end, broadcast = function() end }
print = function() end
'''
def swarm(setup):
    L = lupa.LuaRuntime(unpack_returned_tuples=True); L.execute(ENV); L.execute(setup)
    L.execute('swarm = dofile("%s/swarm.lua")' % ROOT)
    return L, L.globals()

L, g = swarm('''LABEL = "ChunkBerry"
FS["loader.state"] = textutils.serialize({ mode = "escort", who = "NatKingCoal", stay = true, x = -4700, z = 1600, gaveUp = "coalporter" })''')
st = L.eval('textutils.unserialize(FS["loader.state"])')
check("a loader: label and escort target renamed, the rest of its job untouched",
      g.LABEL == "Ablaze" and st.who == "Charcool" and st.gaveUp == "Coalition" and st.mode == "escort" and st.stay and st.x == -4700)
L, g = swarm('''LABEL = "NatKingCoal"
FS["miner.state"] = textutils.serialize({ swarm = true, hunt = true, huntName = "NatKingCoal", huntDone = { 1, 2 }, size = 4, home = { x = 1, y = 2, z = 3 } })''')
st = L.eval('textutils.unserialize(FS["miner.state"])')
check("a hunter: label and huntName renamed, job intact", g.LABEL == "Charcool" and st.huntName == "Charcool" and st.hunt and st.size == 4 and st.home.z == 3 and st.huntDone[2] == 2)
L, g = swarm('''LABEL = "Sortnado" FS["helper.state"] = "{job={plan=\\"factory_shell\\"}}" BEFORE = FS["helper.state"]''')
check("a machine with nothing to rename: nothing is touched", g.LABEL == "Sortnado" and g.FS["helper.state"] == g.BEFORE)
L, g = swarm('LABEL = "SteelyDan"')
L.execute('swarm.rename()')
check("renaming twice changes nothing more", g.LABEL == "DropIt")
check("names: old or new, any case, are one machine",
      L.eval('swarm.sameName("steelydan", "DropIt") and swarm.sameName("DROPIT", "dropit") and not swarm.sameName("DropIt", "Pushy")')
      and L.eval('swarm.nameKey("NatKingCoal") == swarm.nameKey("Charcool")') and L.eval('swarm.newName("Sortnado")') == "Sortnado")

# orders: to the old name, to the new name, to somebody else
def obeys(label, target):
    L, g = swarm('LABEL = "%s"' % label)
    return L.eval('swarm.accept({ id = 1700000001, target = "%s", cmd = "ping" })' % target)
check("an order to the old name reaches the renamed turtle", obeys("SteelyDan", "SteelyDan") and obeys("DropIt", "SteelyDan") and obeys("DropIt", "steelydan"))
check("an order to the new name reaches it too", obeys("DropIt", "DropIt") and obeys("SteelyDan", "dropit"))
check("but not somebody else's", not obeys("DropIt", "Pushy") and not obeys("DropIt", "MortarKombat"))

# ---------------------------------------------------------------- a miner that wakes weeks later (old label, old state)
L = lupa.LuaRuntime(unpack_returned_tuples=True)
L.execute("START_D=1; START_FUEL=2500"); L.execute(harness('harness.lua')); L.execute(harness('sharness.lua'))
L.execute('''T.x,T.y,T.z,T.d=-4480,25,1480,0
LABEL = "CoalPorter"
T.inv[2]={name="advancedperipherals:geo_scanner",count=1} T.inv[3]={name="minecraft:coal",count=40}
FS["miner.state"]=textutils.serialize({swarm=true,index=3,hunt=true,huntDone={},home={x=-4442,y=15,z=1540},homeD=0,size=4,bottom=0,layer=12,
  cruise=45,dock=DOCK,exit1=EXIT1,exit2=EXIT2})
KILL_AT=400''')
L.eval('{runMiner("resume")}')
g = L.globals()
states = list(g.STATES.values())
check("CoalPorter wakes: he is Coalition, says so at once, and is hunting again",
      g.LABEL == "Coalition" and states[0] == "woke up" and "hunting coal" in states and g.SCANS >= 1)

L = lupa.LuaRuntime(unpack_returned_tuples=True)
L.execute("START_D=1; START_FUEL=2500"); L.execute(harness('harness.lua')); L.execute(harness('sharness.lua'))
L.execute('''T.x,T.y,T.z,T.d=-4480,25,1480,0
LABEL = "NatKingCoal"
T.inv[2]={name="advancedperipherals:geo_scanner",count=1} T.inv[3]={name="minecraft:coal",count=40}
FS["miner.state"]=textutils.serialize({swarm=true,hunt=true,huntName="NatKingCoal",huntDone={},home={x=-4442,y=15,z=1540},homeD=0,size=4,bottom=0,layer=12,
  cruise=45,dock=DOCK,exit1=EXIT1,exit2=EXIT2})
KILL_AT=300''')
L.eval('{runMiner("resume")}')
g = L.globals()
check("the stand-in hunter keeps his own (new) name, not the first hunter's", g.LABEL == "Charcool" and "hunting coal" in list(g.STATES.values()))

# a plot miner with an old label: renamed, same plot, still mining
L = lupa.LuaRuntime(unpack_returned_tuples=True)
L.execute("START_D=1; START_FUEL=3000"); L.execute(harness('harness.lua')); L.execute(harness('sharness.lua'))
L.execute('''LABEL = "OreLando" placeAt(PAD,2) JOBQ={job(1,-4441,1540,4,15,0,45)} KILL_AT=300''')
L.eval('{runMiner("resume")}')
g = L.globals()
check("a plot miner: renamed and at work", g.LABEL == "Oresome" and "mining" in list(g.STATES.values()))

# a brand-new miner takes a name from the new list (the place its old name had)
L = lupa.LuaRuntime(unpack_returned_tuples=True)
L.execute("START_D=1; START_FUEL=3000"); L.execute(harness('harness.lua')); L.execute(harness('sharness.lua'))
L.execute('''LABEL = "miner-5" os.getComputerID = function() return 5 end placeAt(PAD,2) JOBQ={job(1,-4441,1540,4,15,0,45)} KILL_AT=100''')
L.eval('{runMiner("resume")}')
check("a new miner number 5 is Oresome (where OreLando stood in the list)", L.globals().LABEL == "Oresome")


# ---------------------------------------------------------------- the factory
FH = harness('fharness.lua')
def factory(setup, statuses="", inbox="", idles=6, first=1):
    L = lupa.LuaRuntime(unpack_returned_tuples=True); L.execute("MODEM_ON=true"); L.execute(FH)
    L.execute('''C="minecraft:chest_0"
local function st(id, label, role, state, x, z, extra)
  local m = { label = label, role = role, state = state, pos = { x = x, y = 80, z = z }, fuel = 900 }
  for k, v in pairs(extra or {}) do m[k] = v end
  return { id = id, msg = m }
end
ST = st
OLD = function(a, b) return a .. b end        -- (old names, written in two halves)
''' + setup + '''
MAX_IDLES=%d''' % first)
    L.eval('{runFactory()}')
    L.execute('IDLES=0 MAX_IDLES=%d STATUSQ = { %s } INBOX = { %s }' % (idles, statuses, inbox))
    L.eval('{runFactory()}')
    return L, L.globals()

BOOKS = '''FILES[".plots"]='{["next"]=7,["done"]=0,["hunter"]=true,["builderId"]=14,["helpers"]={21,22,23,24},["loaders"]={41,42},["byId"]={["9"]=1,["10"]=2,["12"]=4,["13"]=5,["5"]=6,["11"]=3,["6"]=7,["7"]=8}}'
'''
# a factory with the old label and its books: four helpers, two loaders, parts for one more loader
L, g = factory('''LABEL_F = OLD("Forge", "Clooney")
os.getComputerLabel = function() return LABEL_F end
os.setComputerLabel = function(l) LABEL_F = l end
put(C,"computercraft:turtle_normal",2) put(C,"computercraft:wireless_modem_advanced",2) put(C,"advancedperipherals:chunk_controller",1)
put(C,"minecraft:coal",64) put(C,"minecraft:coal",64) put(C,"minecraft:bucket",2)
NEXT_ID = 60                                   -- (the number the next turtle built will have, less one)
''' + BOOKS,
    statuses='ST(21, OLD("Mortar", "Kombat"), "helper", "idle", 104, 205), ST(21, "Pushy", "helper", "idle", 104, 205), '
        + 'ST(41, OLD("Load", "Runner"), "loader", "parked", 104, 199), ST(41, "Phantastic", "loader", "parked", 104, 199)',
    inbox='{ id = 41, msg = { type = "need_job", id = 41 } }, { id = 21, msg = { type = "need_job", id = 21 } }')
roles = [(m.to, m.msg.role, m.msg.name) for m in g.OUTBOX.values() if m.msg.type == "role"]
placed = list(g.PLACED.values())
check("the factory took its new name", g.LABEL_F == "Crafty")
check("its helpers and loaders are known by number: each is told its new name", (41, "loader", "Phantastic") in roles and (21, "helper", "Pushy") in roles)
check("no duplicate helper: four on the books, none built", not any(r[1] == "helper" and r[0] not in (21, 22, 23, 24) for r in roles))
new_loaders = [r for r in roles if r[1] == "loader" and r[0] not in (41, 42)]
check("the next loader built is the third, with the third name (not a second Phantastic) %s %s" % (placed, new_loaders),
      len(placed) == 1 and "chunky" in placed[0] and len(new_loaders) == 1 and new_loaders[0][2] == "Vexed")

# no ender modem to be had (only a pearl and stone for a plain one): no loader is built
L, g = factory('''put(C,"computercraft:turtle_normal",2) put(C,"minecraft:ender_pearl",2) put(C,"minecraft:stone",16) put(C,"advancedperipherals:chunk_controller",3)
put(C,"minecraft:coal",64) put(C,"minecraft:coal",64)
''' + BOOKS)
check("without an ender modem no loader is built", not any("chunky" in p for p in g.PLACED.values()))

# one machine, one entry: a far miner that reported under its old name and now reports under the new one
# (with its own controller) is not taken for a second, silent turtle
L, g = factory('put(C,"minecraft:coal",64)\n' + BOOKS,
    statuses='ST(9, OLD("Ore", "Lando"), "miner", "mining", 1100, 1200), '
        + '{ id = 9, at = 300, msg = { label = "Oresome", role = "miner", state = "mining", pos = { x = 1100, y = 30, z = 1200 }, chunky = "on" } }, '
        + '{ id = 51, at = 300, msg = { label = "Ghastly", role = "loader", state = "parked", pos = { x = 104, y = 80, z = 199 } } }',
    inbox='{ id = 52, at = 310, msg = { type = "escort_request", id = 52, label = "Phantastic" } }', idles=600)
out = [dict(m.msg) for m in g.OUTBOX.values() if m.msg.direct]
check("old name then new name from one turtle: no loader sent after a ghost", out == [])

# a loader (still on its old state) says it is with the hunter by his old name; the hunter reports by his new name
L, g = factory('put(C,"minecraft:coal",64)\n' + BOOKS,
    statuses='ST(51, "Ghastly", "loader", "parked", 104, 199), ST(11, "Charcool", "miner", "hunting coal", 1100, 1200), '
        + 'ST(53, OLD("Chunk", "Berry"), "loader", "escorting", 1100, 1200, { job = { mode = "escort", who = OLD("NatKing", "Coal") } })',
    inbox='{ id = 52, wait = true, msg = { type = "escort_request", id = 52, label = "Phantastic" } }')
out = [dict(m.msg) for m in g.OUTBOX.values() if m.msg.direct]
check("an escort under the old names still counts: no second loader for the same hunter", out == [])
# (and the same books without that escort: the hunter does get a loader, so the check above means something)
L, g = factory('put(C,"minecraft:coal",64)\n' + BOOKS,
    statuses='ST(51, "Ghastly", "loader", "parked", 104, 199), ST(11, "Charcool", "miner", "hunting coal", 1100, 1200)',
    inbox='{ id = 52, wait = true, msg = { type = "escort_request", id = 52, label = "Phantastic" } }')
out = [dict(m.msg) for m in g.OUTBOX.values() if m.msg.direct]
check("(without it the hunter is offered one)", len(out) == 1 and out[0]["who"] == "Charcool")

# ---------------------------------------------------------------- the controller's status file
import json, base64
L = lupa.LuaRuntime(unpack_returned_tuples=True)
g = L.globals()
def to_py(t):
    if lupa.lua_type(t) == 'table':
        d = {k: to_py(v) for k, v in t.items()}
        if d and all(isinstance(k, int) for k in d): return [d[k] for k in sorted(d)]
        return d
    return t
def from_py(o):
    if isinstance(o, dict): return L.table_from({k: from_py(v) for k, v in o.items()})
    if isinstance(o, list): return L.table_from([from_py(v) for v in o])
    return o
docs = []
def post(req):
    r = to_py(req)
    try: docs.append(json.loads(base64.b64decode(json.loads(r['body'])['content'])))
    except Exception: pass
    return json.dumps({"content": {"sha": "sha"}})
g.py_ser = lambda t: json.dumps(to_py(t)); g.py_unser = lambda s: from_py(json.loads(s)); g.py_post = post
L.execute('package.path = "%s/?.lua;" .. package.path' % ROOT)
L.execute(r"""
CLABEL = "Ground" .. "Control"
FS = { [".github_token"] = "github_pat_TEST\n" }
fs = { exists = function(p) return FS[p] ~= nil end, delete = function(p) FS[p] = nil end,
  open = function(p, m) if m == "w" then return { write = function(s) FS[p] = s end, close = function() end } end
    return { readAll = function() return FS[p] end, close = function() end } end }
textutils = { serialiseJSON = py_ser, unserialiseJSON = py_unser, serialize = py_ser, unserialize = function() return nil end }
os.epoch = function() return 1700000000000 end
os.getComputerID = function() return 3 end
os.getComputerLabel = function() return CLABEL end
os.setComputerLabel = function(l) CLABEL = l end
local clock = 0
os.clock = function() clock = clock + 50 return clock end
term = { clear = function() end, setCursorPos = function() end, getSize = function() return 51, 19 end, write = function() end,
  setTextColor = function() end, setBackgroundColor = function() end, isColor = function() return true end }
print = function() end
local modem = { isWireless = function() return true end }
peripheral = { find = function(t) if t == "modem" then return modem end end, getName = function() return "top" end,
  getType = function() return nil end, getNames = function() return {} end, wrap = function() return nil end }
local old, new = "Ore" .. "Lando", "Oresome"
local queue = {
  { 7, { role = "miner", state = "mining", label = old, pos = { x = -4461, y = 12, z = 1530 }, fuel = 4200, log = { "Layer 3" } } },
  { 7, { role = "miner", state = "going home", label = new, pos = { x = -4461, y = 12, z = 1531 }, fuel = 4100, log = { "Going home" } } },
}
rednet = { open = function() end, broadcast = function() end,
  receive = function(proto)
    if proto == "swarm" then local m = table.remove(queue, 1) if m then return m[1], m[2] end end
    error("STOP", 0)
  end }
http = { get = function() return { readAll = function() return '{"sha":"x"}' end, close = function() end } end,
  post = function(req) local out = py_post(req) return { readAll = function() return out end, close = function() end } end }
local ticks = 0
sleep = function() ticks = ticks + 1 if ticks >= 3 then error("STOP", 0) end end
parallel = { waitForAny = function(...) for _, f in ipairs({ ... }) do pcall(f) end end }
""")
try:
    L.execute(open(os.path.join(ROOT, 'controller.lua')).read())
    err = None
except Exception as e:
    err = str(e)[:300]
check("the controller took its new name%s" % (" (%s)" % err if err else ""), g.CLABEL == "CommandBlock")
units = docs[-1].get("units", {}) if docs else {}
labels = [u.get("label") for u in (units.values() if isinstance(units, dict) else units)]
check("its status file shows the renamed turtle once, under the new name %s" % labels, labels == ["Oresome"])

print("PASS" if not fails else "FAILED: %d" % len(fails))
