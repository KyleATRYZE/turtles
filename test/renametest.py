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

print("PASS" if not fails else "FAILED: %d" % len(fails))
