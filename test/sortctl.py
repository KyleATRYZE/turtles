"""Sortnado on one Sophisticated Storage controller, and handing items to the
owner through an Inventory Manager, whichever way the desk was put together.

    python3 test/sortctl.py
"""
import os, sys
from lupa import LuaRuntime
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

WORLD = '''
INV, PLAYER, PLAYER_ROOM, CALLS = {}, {}, 1e9, {}
CTL, IN, OUT, MAN = "sophisticatedstorage:controller_0", "minecraft:barrel_0", "minecraft:barrel_1", "inventory_manager_0"
local function mk(n, size, cap) INV[n] = { size = size, cap = cap or 64, slots = {} } end
function world(layout)
  INV, PLAYER, PLAYER_ROOM, CALLS = {}, {}, 1e9, {}
  mk(CTL, layout.slots or 600, 512)      -- (stack upgrades: a slot holds 8 stacks)
  mk(IN, 27) mk(OUT, 27)
  mk("minecraft:chest_7", 27)            -- a stray chest on the cable: not part of the store
  LAYOUT = layout
end
function addTo(n, name, count)
  local inv = INV[n]
  for s = 1, inv.size do
    if count <= 0 then break end
    local st = inv.slots[s]
    if st and st.name == name and st.count < inv.cap then
      local k = math.min(inv.cap - st.count, count) st.count = st.count + k count = count - k
    end
  end
  for s = 1, inv.size do
    if count <= 0 then break end
    if not inv.slots[s] then local k = math.min(inv.cap, count) inv.slots[s] = { name = name, count = k } count = count - k end
  end
  return count
end
function total(n, name)
  local t = 0
  for _, st in pairs(INV[n].slots) do if not name or st.name == name then t = t + st.count end end
  return t
end
local function takeFrom(n, name, count)
  local got = 0
  for s, st in pairs(INV[n].slots) do
    if got >= count then break end
    if st.name == name then
      local k = math.min(st.count, count - got)
      st.count, got = st.count - k, got + k
      if st.count == 0 then INV[n].slots[s] = nil end
    end
  end
  return got
end
peripheral = {
  getNames = function()
    local t = { MAN }
    if LAYOUT.noManager then t = {} end
    for n in pairs(INV) do t[#t + 1] = n end
    return t
  end,
  hasType = function(n, t)
    if n == MAN then return t == "inventory_manager" end
    return INV[n] ~= nil and t == "inventory"
  end,
  call = function(n, m, a, b, c)
    if n == MAN then
      CALLS[#CALLS + 1] = m .. " " .. tostring(type(a) == "table" and b or a)
      assert(m == "importItem", "only importItem is ever called on the manager, not " .. m)
      if LAYOUT.whatFirst then                -- a version that wants the item first, then where
        if type(a) ~= "table" then error("bad argument #1 (table expected)", 0) end
        a, b = b, a
      elseif type(a) ~= "string" then error("bad argument #1 (string expected)", 0) end
      local from = LAYOUT.sides[a]
      if not from and LAYOUT.names and INV[a] then from = a end
      if not from then error("inventory not found: " .. tostring(a), 0) end
      local k = math.min(b.count, PLAYER_ROOM, total(from, b.name))
      k = takeFrom(from, b.name, k)
      PLAYER[b.name] = (PLAYER[b.name] or 0) + k
      PLAYER_ROOM = PLAYER_ROOM - k
      return k
    end
    local inv = INV[n]
    if m == "size" then return inv.size end
    if m == "list" then
      local t = {}
      for s, st in pairs(inv.slots) do t[s] = { name = st.name, count = st.count } end
      return t
    end
    if m == "pushItems" then
      local st = inv.slots[b]
      if not st then return 0 end
      local want = math.min(c or 64, st.count, 64)       -- one stack a push
      local left = addTo(a, st.name, want)
      st.count = st.count - (want - left)
      if st.count == 0 then inv.slots[b] = nil end
      return want - left
    end
    error("no such method " .. tostring(m))
  end,
  find = function() end,
}
fs = { exists = function() return false end }
textutils = {}
SORTNADO_TEST = true
function fresh(layout)
  world(layout)
  S = dofile(ROOT .. "/sortnado.lua")
  S.cfg({ inbox = IN, outbox = OUT })
  S.discover() S.scan()
  return S
end
function config() return S.config and S.config() end
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
    g = lua.globals()
    S = g.fresh(lua.table_from(layout) if not isinstance(layout, str) else lua.eval(layout))
    return lua, g, S

def give(S, name, count):
    r = S.give(name, count)
    return r if isinstance(r, tuple) else (r, None)

def books(S, name):
    it = S["items"][name]
    return it.total if it else 0

IRON, COAL, PICK = "minecraft:iron_ingot", "minecraft:coal", "minecraft:diamond_pickaxe"

# ---- 1. the store is the controller, and only the controller
lua, g, S = new('{ sides = { ["@west"] = CTL, ["@east"] = OUT } }')
check("one controller is the whole store", S.backend == "controller" and len(S.order) == 1 and S.order[1] == g.CTL, S.backend)
check("the manager was found", S.manager == g.MAN)
g.addTo(g.IN, IRON, 700); g.addTo(g.IN, COAL, 300); g.addTo(g.IN, PICK, 1)
moved = S.sortInbox()
check("the In barrel is put away in the controller", moved == 1001 and g.total(g.IN) == 0 and g.total(g.CTL) == 1001, moved)
check("the books match", books(S, IRON) == 700 and books(S, COAL) == 300 and books(S, PICK) == 1)
check("the stray chest got nothing", g.total("minecraft:chest_7") == 0)

# ---- 2. controller against the manager, names not understood: found by side, nothing staged
got, why = give(S, IRON, 200)
check("200 iron straight to the owner", got == 200 and g.PLAYER[IRON] == 200 and why is None, (got, why, list(g.CALLS.values())))
check("nothing went through the Out barrel", g.total(g.OUT) == 0)
check("the way is remembered", lua.eval("S.saved") >= 1)
before = len(g.CALLS)
got, why = give(S, IRON, 100)
check("second go: one call, the remembered side", got == 100 and len(g.CALLS) == before + 1 and g.CALLS[before + 1] == "importItem @west", list(g.CALLS.values())[before:])
check("books after: 400 iron", books(S, IRON) == 400 and g.total(g.CTL, IRON) == 400, books(S, IRON))

# ---- 3. the owner's inventory fills up
g.PLAYER_ROOM = 30
got, why = give(S, COAL, 64)
check("a full inventory takes what it can, and says so", got == 30 and why == "your inventory took no more" and books(S, COAL) == 270, (got, why))
check("the rest stayed in the store, not on the desk", g.total(g.OUT) == 0 and g.total(g.CTL, COAL) == 270)
g.PLAYER_ROOM = 1e9

# ---- 4. asked the way GroundControl asks
r = S.request(lua.table_from({"type": "get", "item": "iron ingot", "count": 64, "to": "player", "n": 7}))
check("request by what it is called", r.item == IRON and r.count == 64 and r.left == 336 and r.n == 7, (r.item, r.count, r.left))
r = S.request(lua.table_from({"type": "get", "item": "diamond pickaxe", "count": "all", "to": "player", "n": 8}))
check("'all' of a single thing", r.count == 1 and r.left == 0, (r.count, r.left))
r = S.request(lua.table_from({"type": "get", "item": "netherite", "count": 1, "to": "player", "n": 9}))
check("something the store has none of", r.item is None and r.count == 0)
r = S.request(lua.table_from({"type": "get", "item": IRON, "count": 16, "n": 10}))
check("a turtle's request still goes to the Out barrel", r.count == 16 and g.total(g.OUT, IRON) == 16 and g.PLAYER[IRON] == 364, (r.count, g.total(g.OUT, IRON)))

# ---- 5. a slot holding many stacks (stack upgrades) empties in one go
got = S.take(IRON, 300)
check("300 out of one fat slot", got == 300 and g.total(g.OUT, IRON) == 316 and books(S, IRON) == 20, (got, g.total(g.OUT, IRON), books(S, IRON)))

# ---- 6. the manager does not touch the controller: by way of the Out barrel
lua, g, S = new('{ sides = { ["@east"] = OUT } }')
g.addTo(g.CTL, IRON, 500); S.scan()
got, why = give(S, IRON, 100)
check("staged in the Out barrel and handed on", got == 100 and g.PLAYER[IRON] == 100 and g.total(g.OUT) == 0 and why is None, (got, why, list(g.CALLS.values())))
before = len(g.CALLS)
got, why = give(S, IRON, 50)
check("second go: straight to the Out barrel's side", got == 50 and len(g.CALLS) == before + 1 and g.CALLS[before + 1] == "importItem @east", list(g.CALLS.values())[before:])
g.PLAYER_ROOM = 10
got, why = give(S, IRON, 64)
check("inventory full: the rest waits in the Out barrel", got == 10 and g.total(g.OUT, IRON) == 54 and "Out chest" in (why or ""), (got, why))
g.PLAYER_ROOM = 1e9
got, why = give(S, IRON, 64)
check("next go takes what was waiting first", got == 64 and g.total(g.OUT, IRON) == 0 and books(S, IRON) == 500 - 150 - 54 - 10 - 10, (got, g.total(g.OUT, IRON), books(S, IRON)))
check("nothing lost or made", g.PLAYER[IRON] + g.total(g.CTL, IRON) + g.total(g.OUT, IRON) == 500, g.PLAYER[IRON])

# ---- 7. this version takes a name on the network
lua, g, S = new('{ sides = {}, names = true }')
g.addTo(g.CTL, COAL, 128); S.scan()
got, why = give(S, COAL, 64)
check("by name on the network", got == 64 and g.CALLS[1] == "importItem " + g.CTL and g.total(g.OUT) == 0, list(g.CALLS.values()))

# ---- 7b. a version that takes the item first and the place second
lua, g, S = new('{ sides = { ["@west"] = CTL }, whatFirst = true }')
g.addTo(g.CTL, COAL, 128); S.scan()
got, why = give(S, COAL, 64)
check("arguments the other way round: found out", got == 64 and g.PLAYER[COAL] == 64 and g.total(g.OUT) == 0, (got, why, list(g.CALLS.values())))
before = len(g.CALLS)
got, why = give(S, COAL, 32)
check("and kept: one call next time", got == 32 and len(g.CALLS) == before + 1, list(g.CALLS.values())[before:])

# ---- 8. some of it already lying in the Out barrel, layout not yet known:
#         must not mistake the store's side for the Out barrel's
lua, g, S = new('{ sides = { ["@west"] = CTL, ["@east"] = OUT } }')
g.addTo(g.CTL, IRON, 300); g.addTo(g.OUT, IRON, 20); S.scan()
got, why = give(S, IRON, 64)
tot = g.PLAYER[IRON] + g.total(g.CTL, IRON) + g.total(g.OUT, IRON)
check("leftovers in the Out barrel do not confuse it", got == 64 and tot == 320 and g.total(g.OUT, IRON) == 20 and books(S, IRON) == g.total(g.CTL, IRON), (got, why, g.total(g.OUT, IRON), books(S, IRON)))
got, why = give(S, IRON, 64)
check("and it knows the way afterwards", got == 64 and g.PLAYER[IRON] == 128 and books(S, IRON) == g.total(g.CTL, IRON), (got, why))

# ---- 9. no manager at all, and the manager out of reach
lua, g, S = new('{ sides = {}, noManager = true }')
g.addTo(g.CTL, IRON, 64); S.scan()
got, why = give(S, IRON, 8)
check("no manager: says so, moves nothing", got == 0 and "Inventory Manager" in why and g.total(g.CTL, IRON) == 64, why)
lua, g, S = new('{ sides = {} }')
g.addTo(g.CTL, IRON, 64); S.scan()
got, why = give(S, IRON, 8)
check("manager touching nothing: items wait in the Out barrel", got == 0 and g.total(g.OUT, IRON) == 8 and "Out chest" in why and books(S, IRON) == 56, (got, why))

# ---- 10. a full store keeps the rest in the In barrel
lua, g, S = new('{ sides = {}, slots = 2 }')
g.addTo(g.IN, IRON, 1024); g.addTo(g.IN, COAL, 64)
S.sortInbox()
check("full store: what does not fit stays in the In barrel", g.total(g.CTL) == 1024 and g.total(g.IN) == 64 and S.pending == 64, (g.total(g.CTL), g.total(g.IN), S.pending))

# ---- 11. the screen
lua, g, S = new('{ sides = { ["@west"] = CTL } }')
g.addTo(g.CTL, IRON, 500); g.addTo(g.CTL, "minecraft:cobblestone", 2000); S.scan()
v = S.view()
tiles = sum(1 for col in list(v.walls.west.values()) + list(v.walls.east.values()) for _ in col.values())
check("the picture is 60 tiles, with where the take buttons send", tiles == 60 and v.dest == "your inventory" and v.where == "the store", (tiles, v.dest, v.where))
S.touch("dest:toggle")
check("tap to change: the Out chest", S.view().dest == "the Out chest")
for ch in "IRON": S.touch("key:" + ch)
S.touch("take:16")
check("take 16 with the Out chest chosen", g.total(g.OUT, IRON) == 16 and not g.PLAYER[IRON])
S.touch("dest:toggle"); S.touch("take:16")
check("take 16 to the owner", g.PLAYER[IRON] == 16 and g.total(g.OUT, IRON) == 16, g.PLAYER[IRON])

# ---- 12. the real screen draws from these books (dash.lua, 5 x 3 monitor)
lua.execute('package.path = ROOT .. "/?.lua;" .. package.path')
lua.execute('''
function makeMon(bw, bh)
  local m = { scale = 1, rows = {}, pal = {} }
  m.setTextScale = function(s) m.scale = s end
  m.getSize = function()
    return math.max(math.floor((bw - 0.3125) / (m.scale * 6 / 64) + 0.5), 1), math.max(math.floor((bh - 0.3125) / (m.scale * 9 / 64) + 0.5), 1)
  end
  m.setPaletteColour = function(c, hex) m.pal[#m.pal + 1] = { c, hex } end
  m.setCursorPos = function(x, y) m.cy = y end
  m.blit = function(t, f, b) m.rows[m.cy] = { t, f, b } end
  return m
end
''')
dash = lua.eval('(require("dash"))')
m = lua.eval("makeMon")(5, 3)
zones = dash.store(m, S.view(), 0)
text = "\n".join(m.rows[y][1] for y in sorted(m.rows.keys()))
check("the store screen draws: the one store, and where items go", "The store" in text and "to your inventory" in text and "tap to change" in text and "West wall" not in text)

print("PASS" if not fails else "FAILED: " + "; ".join(fails))
sys.exit(1 if fails else 0)
