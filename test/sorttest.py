import json, math, sys, os
from lupa import LuaRuntime
sys.argv = ["x", "/tmp/status_now.json", "/tmp/maps", "/tmp/screens"]
lua = LuaRuntime(encoding="latin-1", unpack_returned_tuples=True)
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
lua.globals().ROOT = ROOT
lua.execute('''
package.path = ROOT .. "/?.lua;" .. package.path
INV = {}
local function mk(n, size) INV[n] = { size = size, slots = {} } end
for i = 0, 59 do mk("minecraft:chest_" .. i, 54) end
mk("minecraft:chest_100", 27) mk("minecraft:chest_101", 27) mk("minecraft:furnace_0", 3)
function addTo(n, name, count)
  local inv = INV[n]
  for s = 1, inv.size do
    if count <= 0 then break end
    local st = inv.slots[s]
    if st and st.name == name and st.count < 64 then local k = math.min(64 - st.count, count) st.count = st.count + k count = count - k end
  end
  for s = 1, inv.size do
    if count <= 0 then break end
    if not inv.slots[s] then local k = math.min(64, count) inv.slots[s] = { name = name, count = k } count = count - k end
  end
  return count
end
MOVES = 0
peripheral = {
  getNames = function() local t = {} for n in pairs(INV) do t[#t + 1] = n end return t end,
  hasType = function(n, t) return INV[n] ~= nil and t == "inventory" end,
  call = function(n, m, a, b, c)
    local inv = INV[n]
    if m == "size" then return inv.size end
    if m == "list" then local t = {} for s, st in pairs(inv.slots) do t[s] = { name = st.name, count = st.count } end return t end
    if m == "pushItems" then
      local st = inv.slots[b]
      if not st then return 0 end
      local want = math.min(c or st.count, st.count)
      local left = addTo(a, st.name, want)
      st.count = st.count - (want - left)
      if st.count == 0 then inv.slots[b] = nil end
      MOVES = MOVES + 1
      return want - left
    end
  end,
  find = function() end,
}
fs = { exists = function() return false end }
textutils = {}
SORTNADO_TEST = true
S = dofile(ROOT .. "/sortnado.lua")
S.cfg({ inbox = "minecraft:chest_100", outbox = "minecraft:chest_101" })
function total(n) local t = 0 for _, st in pairs(INV[n].slots) do t = t + st.count end return t end
''')
S = lua.globals().S
stock = json.load(open('/tmp/stock.json'))
print("chests:", S.discover()); S.scan()
moved = 0
for name, count in stock.items():
    left = count
    while left > 0:
        k = min(left, 27 * 64)
        lua.globals().addTo("minecraft:chest_100", name, k)
        moved += S.sortInbox()
        left -= k
print("items in:", sum(stock.values()), "| put away:", moved, "| left in the In chest:", lua.globals().total("minecraft:chest_100"), "| moves:", lua.globals().MOVES)
books = {str(k): v.total for k, v in S["items"].items()}
print("books match the stock:", books == stock)
# every item sits in a chest of its own section (unless that section was full)
stray = lua.eval('''(function() local n, per = 0, {}
  for chest, c in pairs(S.chests) do for _, st in pairs(c.slots) do
    if S.sectionOf(st.name) ~= c.section then n = n + 1 end end
    per[c.section] = (per[c.section] or 0) + c.used end
  return n end)()''')
used, slots = S.totals()
print("stacks out of their section:", stray, "| used", used, "of", slots)
# ask for things
got = S.take("minecraft:diamond", 32)
print("take 32 diamond:", got, "| in Out chest:", lua.globals().total("minecraft:chest_101"), "| diamonds left on the books:", S["items"]["minecraft:diamond"].total, "of", stock["minecraft:diamond"])
for ch in "DIA": S.touch("key:" + ch)
v = S.view()
print("search 'dia':", [(r.name, r.count) for r in list(v.results.values())[:4]])
S.touch("pick:Diorite"); S.touch("take:all")
print("after tapping Diorite, ALL: Out chest holds", lua.globals().total("minecraft:chest_101"), "| diorite left:", S["items"]["minecraft:diorite"] and S["items"]["minecraft:diorite"].total)
S.touch("key:clr"); S.touch("section:Fuel")
print("browse Fuel:", [(r.name, r.count) for r in S.view().results.values()])
# draw the real screen from the real books
exec(open('/home/claude/test/dashrender.py').read().split("# ---------------------------------------------------------------- the data")[0].replace('lua = LuaRuntime(encoding="latin-1", unpack_returned_tuples=True)', '').replace("status = json.load(open(sys.argv[1]))", ""))
for ch in "RAW": S.touch("key:" + ch)
m = lua.eval("makeMon")(5, 3)
dash.store(m, S.view(), 0)
print("screen:", render(m, "/tmp/screens/store_real.png", zoom=2))
