# The renamings of the swarm (swarm.RENAMES: first to Minecraft puns, then to
# plain task names): every machine renames itself at start-up, and nothing
# breaks while some have the old names and some the new.
# Runs from anywhere:  python3 test/renametest.py
import os, re, lupa
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(HERE)
def harness(name): return open(os.path.join(HERE, name)).read().replace('/home/claude/turtles', ROOT)
fails = []
def check(what, ok):
    print(("ok   " if ok else "FAIL ") + what)
    if not ok: fails.append(what)

# ---------------------------------------------------------------- the table itself
src = open(os.path.join(ROOT, 'swarm.lua')).read()
table = dict(re.findall(r'(\w+) = "(\w+)"', src[src.index('M.RENAMES = {'):src.index('M.RENAMES_BY_ID = {')]))
by_id_src = src[src.index('M.RENAMES_BY_ID = {') + len('M.RENAMES_BY_ID = {'):src.index('local OLD_NAMES')]
by_id = {k: dict((int(i), n) for i, n in re.findall(r'\[(\d+)\] = "(\w+)"', v))
         for k, v in re.findall(r'(\w+) = \{([^}]*)\}', by_id_src)}
# the first renaming (pun names for the old names), each straight to its newest name
WANT = dict(GroundControl="CommandBlock", ForgeClooney="crafter1", BrickJagger="mapper1", MortarKombat="lava1",
    WallStreet="builder1", SteelyDan="foundry1", TimberLake="builder7", ChunkNorris="Ghastly", LoadRunner="Phantastic",
    ChunkBerry="Ablaze", OreLando="Oresome", ElvisPitsley="Pickle", BoulderDash="Cobbler",
    QuarryStyles="CleanSlate", ObiWanKenOrebi="Granted", OreSonWelles="Bedrocker", CoalPorter="Coalition", NatKingCoal="miner3")
# the second (Kyle's map: plain task names)
WANT2 = dict(HopTo="builder1", OnRepeat="builder2", Sticky="builder3", Dusty="builder4", ButtonUp="builder5",
    Observant="builder6", Pushy="lava1", DropIt="foundry1", Comparable="survey1", Dispensable="rescue1",
    BlockParty="mapper1", Crafty="crafter1", Counter="crafter2", Charcool="miner3", LeverAlone="builder7")
check("the table has Kyle's map (both renamings)", all(table.get(k) == v for k, v in list(WANT.items()) + list(WANT2.items())))
check("the two TuffLucks are told apart by number (40 miner1, 12 miner2), and NotoriousDIG with them",
      by_id.get("TuffLuck") == {40: "miner1", 12: "miner2"} and by_id.get("NotoriousDIG") == {40: "miner1", 12: "miner2"}
      and "TuffLuck" not in table and "NotoriousDIG" not in table)
check("the station computers keep their names", not {"Sortnado", "RackBoard"} & set(table))
new_names = set(table.values()) | {n for ids in by_id.values() for n in ids.values()}
check("no new name is also an old name", not (set(table) | set(by_id)) & new_names)
check("no two machines on Kyle's map share a new name",
      len(set(WANT2.values())) == len(WANT2) and not set(WANT2.values()) & {n for ids in by_id.values() for n in ids.values()})
old_rx = re.compile(r'(?<![A-Za-z0-9_])(' + '|'.join(list(table) + list(by_id)) + r')(?![A-Za-z0-9_])')
# (not names: the in-game item "Crafty Turtle", and Python's collections.Counter)
not_names = re.compile(r'Crafty [Tt]urtle|import Counter|Counter\(')
# (the main session's running notes: a log, left as written)
LOGS = {'docs/session-notes.md', 'docs/overnight-plan.md'}
left = []
for dirpath, dirs, files in os.walk(ROOT):
    dirs[:] = [d for d in dirs if d not in ('.git', 'test', 'maps', '__pycache__')]
    for f in files:
        rel = os.path.relpath(os.path.join(dirpath, f), ROOT)
        if f.endswith(('.lua', '.py', '.md', '.html', '.txt')) and rel != 'swarm.lua' and rel not in LOGS:
            text = not_names.sub('', open(os.path.join(dirpath, f), errors='ignore').read())
            if old_rx.search(text): left.append(rel)
check("old names are nowhere but the table in swarm.lua %s" % (left or ""), not left)

# the name lists in the programs
fac = open(os.path.join(ROOT, 'factory.lua')).read()
loaders = re.findall(r'"(\w+)"', fac[fac.index('local LOADER_NAMES'):fac.index('local LOADERS ')])
helpers = re.findall(r'"(\w+)"', fac[fac.index('local HELPER_NAMES'):fac.index('local launchingHelper')])
check("loader names, in Kyle's order", loaders == ["Phantastic", "Ablaze", "Vexed", "Beehave", "Batty", "Breezy", "AllayOop", "WitherOrNot", "Shulky", "Squawk"])
# (each new name where the old one stood: a mate's rack home and hover slot go by its place in the list)
OLD_HELPERS = ["Pushy", "HopTo", "LeverAlone", "DropIt", "Sticky", "Dusty", "OnRepeat", "Comparable", "Observant",
               "Dispensable", "ButtonUp"]
check("the helpers keep their places under their new names, with spare names after them",
      helpers[:len(OLD_HELPERS)] == [WANT2[n] for n in OLD_HELPERS] and len(helpers) >= 16 and len(set(helpers)) == len(helpers))
hel = open(os.path.join(ROOT, 'helper.lua')).read()
slots = dict(re.findall(r'(\w+) = (\d)', hel[hel.index('local SLOTS = {'):hel.index('local function myName()')]))
check("hover slots are filed under the new names, the same slots as before", slots == {"lava1": "0", "builder1": "1", "builder7": "2", "foundry1": "3"})
rk = open(os.path.join(ROOT, 'rack.lua')).read()
hl = re.findall(r'"(\w+)"', hel[hel.index('local HOMES = {'):hel.index('function LN.on()')])
check("rack homes: the same list in helper.lua, rack.lua and the factory",
      hl == helpers and re.findall(r'"(\w+)"', rk[rk.index('local HELPERS = {'):rk.index('local LOADERS = {')]) == helpers)
mi = open(os.path.join(ROOT, 'miner.lua')).read()
check("a new miner is named by its number (no list to give two the same name)",
      'local function newMinerName(id) return "miner" .. tostring(id) end' in mi and 'local NAMES' not in mi)
upd = open(os.path.join(ROOT, 'update.lua')).read()
check("update.lua: a crafter label (crafter2, once Counter) is the factory role", 'match("^crafter%d")' in upd)

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
      g.LABEL == "Ablaze" and st.who == "miner3" and st.gaveUp == "Coalition" and st.mode == "escort" and st.stay and st.x == -4700)
L, g = swarm('''LABEL = "NatKingCoal"
FS["miner.state"] = textutils.serialize({ swarm = true, hunt = true, huntName = "NatKingCoal", huntDone = { 1, 2 }, size = 4, home = { x = 1, y = 2, z = 3 } })''')
st = L.eval('textutils.unserialize(FS["miner.state"])')
check("a hunter: label and huntName renamed (straight to the newest name), job intact",
      g.LABEL == "miner3" and st.huntName == "miner3" and st.hunt and st.size == 4 and st.home.z == 3 and st.huntDone[2] == 2)
L, g = swarm('''LABEL = "Charcool" ID = 13
FS["miner.state"] = textutils.serialize({ swarm = true, hunt = true, huntName = "Charcool", size = 4 })''')
st = L.eval('textutils.unserialize(FS["miner.state"])')
check("Charcool (13): miner3, and his huntName too", g.LABEL == "miner3" and st.huntName == "miner3" and st.hunt)
L, g = swarm('''LABEL = "TimberLake"
FS["helper.state"] = textutils.serialize({ job = { plan = "factory_shell", ox = -4448, oy = 71, oz = 1518, xmin = 3, xmax = 5 }, turn = 2, orderSeq = 7, done = true })
FS[".foundry"] = textutils.serialize({ on = true, queue = {}, notes = { "ok" } })''')
st = L.eval('textutils.unserialize(FS["helper.state"])')
check("a helper (lost, waking weeks later): renamed, its job as it was", g.LABEL == "builder7" and st.job.plan == "factory_shell" and st.job.ox == -4448 and st.turn == 2 and st.done)
L, g = swarm('''LABEL = "Sortnado" FS["helper.state"] = "{job={plan=\\"factory_shell\\"}}" BEFORE = FS["helper.state"]''')
check("a machine with nothing to rename: nothing is touched", g.LABEL == "Sortnado" and g.FS["helper.state"] == g.BEFORE)
L, g = swarm('LABEL = "SteelyDan"')
L.execute('swarm.rename()')
check("renaming twice changes nothing more", g.LABEL == "foundry1")
check("names: old, older or new, any case, are one machine",
      L.eval('swarm.sameName("steelydan", "foundry1") and swarm.sameName("DropIt", "foundry1") and swarm.sameName("dropit", "FOUNDRY1")'
             ' and swarm.sameName("SteelyDan", "DropIt") and not swarm.sameName("DropIt", "Pushy") and not swarm.sameName("foundry1", "lava1")')
      and L.eval('swarm.nameKey("NatKingCoal") == swarm.nameKey("Charcool") and swarm.nameKey("Charcool") == "miner3"')
      and L.eval('swarm.newName("Sortnado")') == "Sortnado" and L.eval('swarm.newName("RackBoard")') == "RackBoard")

# Kyle's map, machine by machine: (computer number, label now, label after start-up)
MACHINES = [(19, "HopTo", "builder1"), (15, "OnRepeat", "builder2"), (9, "Sticky", "builder3"), (0, "Dusty", "builder4"),
    (5, "ButtonUp", "builder5"), (16, "Observant", "builder6"), (18, "Pushy", "lava1"), (23, "DropIt", "foundry1"),
    (39, "Comparable", "survey1"), (10, "Dispensable", "rescue1"), (14, "BlockParty", "mapper1"), (8, "Crafty", "crafter1"),
    (38, "Counter", "crafter2"), (40, "TuffLuck", "miner1"), (12, "TuffLuck", "miner2"), (13, "Charcool", "miner3"),
    (22, "LeverAlone", "builder7"), (11, "Sortnado", "Sortnado"), (30, "RackBoard", "RackBoard")]
wrong = []
for mid, label, want in MACHINES:
    L, g = swarm('LABEL = "%s" ID = %d' % (label, mid))
    if g.LABEL != want: wrong.append((mid, label, g.LABEL))
check("every machine on Kyle's map takes its new name at start-up %s" % (wrong or ""), not wrong)
L, g = swarm('LABEL = "NotoriousDIG" ID = 12')
check("NotoriousDIG (12, from before the first renaming) is miner2", g.LABEL == "miner2")
L, g = swarm('LABEL = "TuffLuck" ID = 77')
check("a TuffLuck that is neither of the two keeps its name", g.LABEL == "TuffLuck")

# a word that is also an old name: "counter" (the assistant's role in its reports) is left alone in a
# state file; the names in the factory's books are renamed (skip lists, the named rescuer)
L, g = swarm('''LABEL = "Crafty" ID = 8
FS[".plots"] = textutils.serialize({ assist = { role = "counter" }, rescue = { name = "Dispensable", on = true },
  haul = { on = true, skip = { HopTo = true, Sticky = true } }, lavafarm = { skip = { ["Pushy"] = true } } })''')
st = L.eval('textutils.unserialize(FS[".plots"])')
check("the factory's books: the role word kept; rescuer, haul and lava farm skip lists under the new names",
      g.LABEL == "crafter1" and st.assist.role == "counter" and st.rescue.name == "rescue1" and st.rescue.on
      and st.haul.skip.builder1 and st.haul.skip.builder3 and st.haul.skip.HopTo is None and st.lavafarm.skip.lava1)
# a skip list as it is read (saved under old names, or set later by an order naming old names)
L, g = swarm('LABEL = "crafter1" ID = 8')
check("skip lists: a drone listed under its old name still counts (swarm.listed)",
      L.eval('swarm.listed({ HopTo = true }, "builder1") and swarm.listed({ hopto = true }, "builder1")'
             ' and swarm.listed({ builder1 = true }, "HopTo") and not swarm.listed({ HopTo = true }, "builder2")'
             ' and swarm.listed({ TuffLuck = true }, "miner1", 40) and swarm.listed({ TuffLuck = true }, "miner2", 12)'
             ' and not swarm.listed({ TuffLuck = true }, "miner3", 13) and not swarm.listed({ HopTo = false }, "builder1")'))
L.execute('K = {} ' + fac[fac.index('function K.skipped('):fac.index('local function noteStatus(')])
check("the factory's skip lists go through it (haul, lava farm, rescuer)",
      L.eval('K.skipped({ Pushy = true }, { label = "lava1", id = 18 }) and not K.skipped({ Pushy = true }, { label = "builder1", id = 19 })'
             ' and not K.skipped(nil, { label = "lava1" })')
      and fac.count('K.skipped(') == 5 and 'skip[u.label]' not in fac)

# the assistant crafter: crafter2 (once Counter) is a counter, slot 1; crafter1 is the factory
COUNTER = fac[fac.index('do\n  local label = (os.getComputerLabel'):fac.index('K.counters = {}')]
def counter_slot(label):
    L = lupa.LuaRuntime(unpack_returned_tuples=True)
    L.execute('K = {} os.getComputerLabel = function() return %s end\n' % ('nil' if label is None else '"%s"' % label) + COUNTER)
    return (bool(L.eval('K.COUNTER')), L.eval('K.SLOT'))
check("crafter1, crafter2, crafter3 (and the old Counter, Counter2): a counter or not, and which slot",
      counter_slot("crafter1") == (False, 0) and counter_slot("crafter2") == (True, 1) and counter_slot("crafter3") == (True, 2)
      and counter_slot("Counter") == (True, 1) and counter_slot("Counter2") == (True, 2) and counter_slot(None) == (False, 0)
      and counter_slot("factory") == (False, 0))

# orders: to the old name, to the new name, to somebody else
def obeys(label, target, mid=17):
    L, g = swarm('LABEL = "%s" ID = %d' % (label, mid))
    return L.eval('swarm.accept({ id = 1700000001, target = "%s", cmd = "ping" })' % target)
check("an order to the old name reaches the renamed turtle", obeys("SteelyDan", "SteelyDan") and obeys("foundry1", "SteelyDan")
      and obeys("foundry1", "steelydan") and obeys("foundry1", "DropIt") and obeys("foundry1", "dropit") and obeys("DropIt", "DropIt"))
check("an order to the new name reaches it too", obeys("foundry1", "foundry1") and obeys("SteelyDan", "FOUNDRY1") and obeys("DropIt", "foundry1"))
check("but not somebody else's", not obeys("foundry1", "Pushy") and not obeys("foundry1", "MortarKombat") and not obeys("foundry1", "lava1"))
check("Counter and Crafty: the old names reach crafter2 and crafter1 (and not each other)",
      obeys("crafter2", "Counter", 38) and obeys("crafter2", "counter", 38) and obeys("crafter1", "Crafty", 8)
      and not obeys("crafter1", "Counter", 8) and not obeys("crafter2", "Crafty", 38))
check("an order to TuffLuck reaches both (as before), and no one else",
      obeys("miner1", "TuffLuck", 40) and obeys("miner2", "TuffLuck", 12) and not obeys("miner3", "TuffLuck", 13))
check("miner1 and miner2 are told apart, renamed or not",
      obeys("miner1", "miner1", 40) and not obeys("miner2", "miner1", 12)
      and obeys("TuffLuck", "miner1", 40) and not obeys("TuffLuck", "miner1", 12))

# ---------------------------------------------------------------- the rack: homes by name, old or new
L, g = swarm('LABEL = "RackBoard" ID = 30')
L.execute('package.path = "%s/?.lua;" .. package.path' % ROOT)
L.execute('package.loaded.swarm = swarm RACK_TEST = true colours = { black = 32768, white = 1 } '
          'peripheral.getNames = function() return {} end')
R = L.execute('return dofile("%s/rack.lua")' % ROOT)
home = lambda label, mid, role="helper": R.homeOf(L.table_from({"label": label, "id": mid, "role": role}))
check("rack homes: a drone still on its old name has the home of its new one",
      home("HopTo", 19) == home("builder1", 19) == 1 and home("Pushy", 18) == home("lava1", 18) == 0
      and home("Dispensable", 10) == home("rescue1", 10) == 9 and home("BlockParty", 14, "miner") == home("mapper1", 14, "miner") == 31)

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
check("the stand-in hunter keeps his own (new) name, not the first hunter's", g.LABEL == "miner3" and "hunting coal" in list(g.STATES.values()))

# a plot miner with an old label: renamed, same plot, still mining
L = lupa.LuaRuntime(unpack_returned_tuples=True)
L.execute("START_D=1; START_FUEL=3000"); L.execute(harness('harness.lua')); L.execute(harness('sharness.lua'))
L.execute('''LABEL = "OreLando" placeAt(PAD,2) JOBQ={job(1,-4441,1540,4,15,0,45)} KILL_AT=300''')
L.eval('{runMiner("resume")}')
g = L.globals()
check("a plot miner: renamed and at work", g.LABEL == "Oresome" and "mining" in list(g.STATES.values()))

# a brand-new miner is named by its computer number
L = lupa.LuaRuntime(unpack_returned_tuples=True)
L.execute("START_D=1; START_FUEL=3000"); L.execute(harness('harness.lua')); L.execute(harness('sharness.lua'))
L.execute('''LABEL = "miner-5" os.getComputerID = function() return 5 end placeAt(PAD,2) JOBQ={job(1,-4441,1540,4,15,0,45)} KILL_AT=100''')
L.eval('{runMiner("resume")}')
check("a new miner number 5 is miner5", L.globals().LABEL == "miner5")


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
    statuses='ST(21, OLD("Mortar", "Kombat"), "helper", "idle", 104, 205), ST(21, "lava1", "helper", "idle", 104, 205), '
        + 'ST(41, OLD("Load", "Runner"), "loader", "parked", 104, 199), ST(41, "Phantastic", "loader", "parked", 104, 199)',
    inbox='{ id = 41, msg = { type = "need_job", id = 41 } }, { id = 21, msg = { type = "need_job", id = 21 } }')
roles = [(m.to, m.msg.role, m.msg.name) for m in g.OUTBOX.values() if m.msg.type == "role"]
placed = list(g.PLACED.values())
check("the factory took its new name", g.LABEL_F == "crafter1")
check("its helpers and loaders are known by number: each is told its new name", (41, "loader", "Phantastic") in roles and (21, "helper", "lava1") in roles)
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
    statuses='ST(51, "Ghastly", "loader", "parked", 104, 199), ST(11, "miner3", "miner", "hunting coal", 1100, 1200), '
        + 'ST(53, OLD("Chunk", "Berry"), "loader", "escorting", 1100, 1200, { job = { mode = "escort", who = OLD("NatKing", "Coal") } })',
    inbox='{ id = 52, wait = true, msg = { type = "escort_request", id = 52, label = "Phantastic" } }')
out = [dict(m.msg) for m in g.OUTBOX.values() if m.msg.direct]
check("an escort under the old names still counts: no second loader for the same hunter", out == [])
# (and the same books without that escort: the hunter does get a loader, so the check above means something)
L, g = factory('put(C,"minecraft:coal",64)\n' + BOOKS,
    statuses='ST(51, "Ghastly", "loader", "parked", 104, 199), ST(11, "miner3", "miner", "hunting coal", 1100, 1200)',
    inbox='{ id = 52, wait = true, msg = { type = "escort_request", id = 52, label = "Phantastic" } }')
out = [dict(m.msg) for m in g.OUTBOX.values() if m.msg.direct]
check("(without it the hunter is offered one)", len(out) == 1 and out[0]["who"] == "miner3")

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
