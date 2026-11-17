"""'$get 64 iron ingot' in chat: what CommandBlock makes of the words, what
it asks Sortnado, and what it says back. Runs the piece of controller.lua
between its two markers on its own, and then the whole exchange against the
real sortnado.lua.

    python3 test/gettest.py
"""
import os, sys
from lupa import LuaRuntime
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src = open(os.path.join(ROOT, "controller.lua")).read()
a = src.index('local STORE_PROTOCOL = "swarm_store"')
b = src.index("-- Listens for \"swarm ...\" and \"get ...\" typed in chat.")
piece = src[a:b] + "\nreturn { parseGet = parseGet, askStore = askStore, storeLine = storeLine, storeReplies = storeReplies, pending = storePending }\n"

lua = LuaRuntime(encoding="latin-1", unpack_returned_tuples=True)
lua.execute('''
SAID, SENT, INBOX, NOW = {}, {}, {}, 0
function say(t) SAID[#SAID + 1] = t end
rednet = {
  broadcast = function(m, p) SENT[#SENT + 1] = { msg = m, proto = p } end,
  receive = function(p, t)
    NOW = NOW + (t or 0)
    local m = table.remove(INBOX, 1)
    if m == nil then coroutine.yield() return nil end
    return 5, m
  end,
}
local clock = os.clock
os = { clock = function() return NOW end, epoch = function() return 1700000000000 end }
''')
G = lua.globals()
C = lua.execute(piece)
fails = []
def check(what, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + what + (" | " + str(detail) if detail != "" else ""))
    if not ok:
        fails.append(what)

# ---- the words
def parse(t):
    r = C.parseGet(t)
    return r if isinstance(r, tuple) else (r, None)
check("get 64 iron ingot", parse("get 64 iron ingot") == (64, "iron ingot"), parse("get 64 iron ingot"))
check("get all cobblestone", parse("get all cobblestone") == ("all", "cobblestone"))
check("get diamond pickaxe is one", parse("get diamond pickaxe") == (1, "diamond pickaxe"))
check("get torch is one", parse("get torch") == (1, "torch"))
check("get 0 torch is still one", parse("get 0 torch") == (1, "torch"))
check("a bare get is nothing", parse("get")[0] is None and parse("get  ")[0] is None)
check("other chat is nothing", parse("swarm status")[0] is None and parse("forget it")[0] is None and parse("getting there")[0] is None)

# ---- the asking
C.askStore(64, "iron ingot")
m = G.SENT[1]
check("asks Sortnado on its own protocol, for the player", m.proto == "swarm_store" and m.msg.type == "get" and m.msg.item == "iron ingot"
      and m.msg.count == 64 and m.msg.to == "player" and m.msg.n is not None)
check("the request carries no player name", sorted(m.msg.keys()) == ["count", "item", "n", "to", "type"], sorted(m.msg.keys()))

# ---- the answers
line = lambda **k: C.storeLine(lua.table_from(k), "iron ingot")
check("all sent", line(item="minecraft:iron_ingot", label="Iron ingot", count=64, asked=64, left=300) == "Sent 64 Iron ingot to you. 300 left in storage.",
      line(item="minecraft:iron_ingot", label="Iron ingot", count=64, asked=64, left=300))
check("some sent", line(item="x", label="Iron ingot", count=30, asked=64, left=0, why="your inventory took no more")
      == "Sent 30 Iron ingot to you (you asked for 64: your inventory took no more). 0 left in storage.")
check("none sent", line(item="x", label="Iron ingot", count=0, asked=64, why="no Inventory Manager on the storage network")
      == "Could not send Iron ingot: no Inventory Manager on the storage network.")
check("none in store", line(count=0) == "Storage has no 'iron ingot'.")

# ---- the reply loop: an answer is passed on once; silence is reported
co = lua.eval("coroutine.wrap")(C.storeReplies)
n = m.msg.n
G.INBOX[1] = lua.table_from({"type": "got", "n": n, "item": "minecraft:iron_ingot", "label": "Iron ingot", "count": 64, "asked": 64, "left": 10})
G.INBOX[2] = lua.table_from({"type": "got", "n": n, "item": "minecraft:iron_ingot", "label": "Iron ingot", "count": 64, "asked": 64, "left": 10})
G.INBOX[3] = lua.table_from({"type": "got", "n": 424242, "item": "x", "label": "Someone else's", "count": 1})
co()
check("the answer is said once, and only ours", list(G.SAID.values()) == ["Sent 64 Iron ingot to you. 10 left in storage."], list(G.SAID.values()))
C.askStore(1, "elytra")
for _ in range(15):
    co()
check("no answer in 20 s: says so", G.SAID[2] == "Storage did not answer about 'elytra'. Is Sortnado running?" and len(G.SAID) == 2, list(G.SAID.values()))

# ---- end to end with the real Sortnado
sys.path.insert(0, os.path.join(ROOT, "test"))
import importlib.util
spec = importlib.util.spec_from_file_location("sortctl_world", os.path.join(ROOT, "test", "sortctl.py"))
world_src = open(os.path.join(ROOT, "test", "sortctl.py")).read()
WORLD = world_src[world_src.index("WORLD = '''") + len("WORLD = '''"):world_src.index("'''\n\nfails")]
l2 = LuaRuntime(encoding="latin-1", unpack_returned_tuples=True)
l2.globals().ROOT = ROOT
l2.execute(WORLD)
g2 = l2.globals()
S = g2.fresh(l2.eval('{ sides = { ["@west"] = CTL, ["@east"] = OUT } }'))
g2.addTo(g2.CTL, "minecraft:iron_ingot", 100); g2.addTo(g2.CTL, "minecraft:iron_block", 500); S.scan()
def chat(text):
    count, item = parse(text)
    before = len(G.SENT)
    C.askStore(count, item)
    q = G.SENT[before + 1].msg
    r = S.request(l2.table_from({k: q[k] for k in q.keys()}))
    return C.storeLine(lua.table_from({k: r[k] for k in r.keys()}), item)
said = chat("get 64 iron ingot")
check("$get 64 iron ingot: the ingots, not the blocks there are more of", said == "Sent 64 Iron ingot to you. 36 left in storage." and g2.PLAYER["minecraft:iron_ingot"] == 64, said)
said = chat("get all iron ingot")
check("$get all iron ingot", said == "Sent 36 Iron ingot to you. 0 left in storage.", said)
said = chat("get 5 netherite")
check("$get of something not stocked", said == "Storage has no 'netherite'.", said)
calls = [c for c in g2.CALLS.values()]
check("the manager was only ever asked to import", all(c.startswith("importItem ") or c.startswith("getOwner") for c in calls), calls)

print("PASS" if not fails else "FAILED: " + "; ".join(fails))
sys.exit(1 if fails else 0)
