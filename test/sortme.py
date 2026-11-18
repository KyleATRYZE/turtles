"""Sortnado on an ME system (an ME Bridge on the cable): the In barrel put
away, the books, things to the Out barrel and to the owner (always by way of
the Out barrel), and the controller backend still chosen when there is no
bridge. Uses the same world as test/sortctl.py with an ME Bridge added.

    python3 test/sortme.py
"""
import os, sys, re
from lupa import LuaRuntime
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

src = open(os.path.join(HERE, "sortctl.py")).read()
WORLD = re.search(r"WORLD = '''(.*?)'''", src, re.S).group(1)

ME = '''
BRIDGE, ME = "me_bridge_0", {}
ME_BYTES = 8192
local base = { getNames = peripheral.getNames, hasType = peripheral.hasType, call = peripheral.call }
peripheral.getNames = function()
  local t = base.getNames()
  if LAYOUT.bridge then t[#t + 1] = BRIDGE end
  return t
end
peripheral.hasType = function(n, t)
  if n == BRIDGE then return t == "me_bridge" end
  return base.hasType(n, t)
end
function meTotal(name) return ME[name] or 0 end
peripheral.call = function(n, m, a, b, c)
  if n ~= BRIDGE then return base.call(n, m, a, b, c) end
  if m == "getItems" then
    local t = {}
    for name, k in pairs(ME) do if k > 0 then t[#t + 1] = { name = name, count = k, displayName = "[" .. name .. "]" } end end
    return t
  elseif m == "getTotalItemStorage" then return ME_BYTES
  elseif m == "getUsedItemStorage" then
    local u = 0 for _, k in pairs(ME) do u = u + 8 + k / 8 end return u
  elseif m == "importItem" then           -- (filter, container): container -> ME
    assert(type(a) == "table" and type(b) == "string", "importItem(filter, container)")
    local inv = INV[b]
    if not inv then return 0, "INVENTORY_NOT_FOUND" end
    local want, got = a.count or 64, 0
    for s, st in pairs(inv.slots) do
      if got >= want then break end
      if st.name == a.name then
        local k = math.min(st.count, want - got)
        st.count, got = st.count - k, got + k
        if st.count == 0 then inv.slots[s] = nil end
      end
    end
    ME[a.name] = (ME[a.name] or 0) + got
    return got
  elseif m == "exportItem" then           -- (filter, container): ME -> container
    assert(type(a) == "table" and type(b) == "string", "exportItem(filter, container)")
    if not INV[b] then return 0, "INVENTORY_NOT_FOUND" end
    local k = math.min(a.count or 64, ME[a.name] or 0)
    local left = addTo(b, a.name, k)
    ME[a.name] = (ME[a.name] or 0) - (k - left)
    return k - left
  end
  error("no such ME Bridge method " .. tostring(m))
end
'''

fails = []
def check(what, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + what + (" | " + str(detail) if detail != "" else ""))
    if not ok:
        fails.append(what)

def new(layout):
    lua = LuaRuntime(encoding="latin-1", unpack_returned_tuples=True)
    lua.globals().ROOT = ROOT
    lua.execute(WORLD)
    lua.execute(ME)
    g = lua.globals()
    S = g.fresh(lua.eval(layout))
    return lua, g, S

def books(S, name):
    it = S["items"][name]
    return it.total if it else 0

IRON, COAL = "minecraft:iron_ingot", "minecraft:coal"

# ---- 0. a bridge on the cable is not the store until told ("me Sortnado on=1")
lua, g, S = new('{ bridge = true, sides = { ["@east"] = OUT } }')
check("a bridge alone does not take over: the controller stays the store", S.backend == "controller" and S.bridge == g.BRIDGE, S.backend)
g.addTo(g.IN, IRON, 10)
S.sortInbox()
check("  and nothing goes into the ME system", g.meTotal(IRON) == 0 and g.total(g.CTL) == 10, (g.meTotal(IRON), g.total(g.CTL)))

# ---- 1. told so, the bridge wins over the controller and the chests
lua, g, S = new('{ bridge = true, sides = { ["@east"] = OUT } }')
S.cfg(lua.eval('{ inbox = IN, outbox = OUT, me = true }'))
S.discover(); S.scan()
check("the ME system is the store", S.backend == "me" and S.order[1] == g.BRIDGE, S.backend)
g.addTo(g.IN, IRON, 700); g.addTo(g.IN, COAL, 300)
moved = S.sortInbox()
check("the In barrel is put away in the ME system", moved == 1000 and g.total(g.IN) == 0 and g.meTotal(IRON) == 700, (moved, g.meTotal(IRON)))
check("the books match", books(S, IRON) == 700 and books(S, COAL) == 300, (books(S, IRON), books(S, COAL)))
check("the controller and the stray chest got nothing", g.total(g.CTL) == 0 and g.total("minecraft:chest_7") == 0)
check("labels come from the display name", S["items"][IRON].label == IRON, S["items"][IRON].label)

# ---- 2. to the Out barrel (a turtle's request)
got = S.take(IRON, 100)
check("100 iron to the Out barrel", got == 100 and g.total(g.OUT, IRON) == 100 and books(S, IRON) == 600, (got, books(S, IRON)))

# ---- 3. to the owner: always by way of the Out barrel, which takes what was waiting first
r = S.give(IRON, 164)
got, why = (r if isinstance(r, tuple) else (r, None))
check("164 iron to the owner, 100 of them already waiting", got == 164 and g.PLAYER[IRON] == 164 and g.total(g.OUT) == 0 and why is None, (got, why, list(g.CALLS.values())))
check("the manager is only ever pointed at sides; the Out barrel's is found", list(g.CALLS.values())[-1] == "importItem @east", list(g.CALLS.values()))
before = len(g.CALLS)
S.give(IRON, 10)
check("second go: one call, straight to the Out barrel's side", len(g.CALLS) == before + 1 and g.CALLS[before + 1] == "importItem @east" and g.PLAYER[IRON] == 174, list(g.CALLS.values())[before:])
check("nothing lost or made", g.PLAYER[IRON] + g.meTotal(IRON) + g.total(g.OUT, IRON) == 700)

# ---- 4. inventory full: the rest goes back into the ME system, not left on the desk... or waits
g.PLAYER_ROOM = 10
r = S.give(COAL, 64)
got, why = (r if isinstance(r, tuple) else (r, None))
check("a full inventory takes what it can", got == 10, (got, why))
check("coal accounted for", g.PLAYER[COAL] + g.meTotal(COAL) + g.total(g.OUT, COAL) == 300, (g.PLAYER[COAL], g.meTotal(COAL), g.total(g.OUT, COAL)))
g.PLAYER_ROOM = 1e9

# ---- 5. asked the way CommandBlock asks
r = S.request(lua.table_from({"type": "get", "item": "iron", "count": 16, "n": 3}))
check("request by part of the name, to the Out barrel", r.count == 16 and g.total(g.OUT, IRON) == 16, (r.item, r.count))

# ---- 6. no bridge: the controller backend as before
lua, g, S = new('{ sides = { ["@west"] = CTL } }')
check("without a bridge the controller is the store", S.backend == "controller", S.backend)

print("PASS" if not fails else "FAILED: " + ", ".join(fails))
sys.exit(0 if not fails else 1)
