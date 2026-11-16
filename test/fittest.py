import lupa, sys, json, subprocess, os
# ---- a mini building: a box with a door, and fittings inside
final, shell = {}, {}
def put(d, x, y, z, name): d[(x, y, z)] = name
for x in range(9):
    for z in range(9):
        put(final, x, 0, z, "minecraft:polished_deepslate"); put(final, x, 6, z, "minecraft:deepslate_tiles")
        if x in (0, 8) or z in (0, 8):
            for y in range(1, 6): put(final, x, y, z, "minecraft:stone_bricks")
for x in (3, 4, 5):
    for y in (1, 2, 3): final.pop((x, y, 8))
shell = dict(final)
for y in (1, 2): final.pop((0, y, 2))                                  # a porthole to cut
put(final, 1, 0, 2, "minecraft:obsidian"); put(final, 2, 0, 2, "minecraft:raw_copper_block")   # floor to swap
put(final, 1, 1, 1, "computercraft:wired_modem_full")
put(final, 2, 1, 1, "minecraft:chest[facing=east]"); put(final, 2, 2, 1, "minecraft:chest[facing=east]")
for y in (1, 2, 3): put(final, 7, y, 1, "minecraft:ladder[facing=south]")
put(final, 4, 5, 4, "minecraft:chain"); put(final, 4, 4, 4, "minecraft:lantern[hanging=true]")
put(final, 6, 1, 6, "minecraft:furnace[facing=west]")
for z in (3, 4, 5): put(final, 6, 1, z, "minecraft:iron_bars")
pal = sorted(set(final.values()))
json.dump({"palette": pal, "blocks": [[x, y, z, pal.index(n)] for (x, y, z), n in final.items()]}, open("/tmp/mini/final.json", "w"))
spal = sorted(set(shell.values()))
with open("/tmp/mini/shell.txt", "w") as f:
    f.write(f"P {len(spal)}\n" + "".join(f"{n} -\n" for n in spal) + f"B {len(shell)}\n")
    for (x, y, z), n in sorted(shell.items(), key=lambda kv: (kv[0][1], kv[0][2], kv[0][0])): f.write(f"{x} {y} {z} {spal.index(n)}\n")
r = subprocess.run([sys.executable, "/home/claude/turtles/tools/fitout.py", "/tmp/mini/final.json", "/tmp/mini/shell.txt", "/tmp/mini/fitout.txt", "4,2,11"], capture_output=True, text=True)
print(r.stdout.strip().splitlines()[2])

src = open('bbuild.py').read()
head = src[:src.index("# first run: the maps")]
exec(head)
g = L.globals()
g.SHELL_TXT = open("/tmp/mini/shell.txt").read(); g.FIT_TXT = open("/tmp/mini/fitout.txt").read()
L.execute("""
http = { get = function(url) local text = url:find("fitout") and FIT_TXT or SHELL_TXT
  return { readAll = function() return text end, close = function() end } end }
for y=15,24 do for dx=-2,2 do for dz=-2,2 do setSpecial(-4456+dx, y, 1541+dz, false) end end end
setSpecial(-4458, 15, 1540, false) setSpecial(-4455, 15, 1542, false) setSpecial(-4453, 15, 1543, false)
setSpecial(-4456, 14, 1543, "minecraft:stone") setSpecial(-4456, 13, 1543, "minecraft:stone")
for y=16,60 do setSpecial(-4462, y, 1521, false) end
-- room above the pit for the top of the box
for x=OX-4,OX+12 do for z=OZ-4,OZ+14 do for y=OY,OY+12 do if getBlock(x,y,z) then setSpecial(x,y,z,false) end end end end
-- put up the shell
for line in SHELL_TXT:gmatch("[^\\n]+") do
  local x,y,z,i = line:match("^(-?%d+) (-?%d+) (-?%d+) (%d+)$")
  if x then setSpecial(OX+x, OY+y, OZ+z, "minecraft:stone_bricks") end
end
-- placing, any direction; chests, furnaces and ladders end up facing the turtle
local DX, DZ = {[0]=1,[1]=0,[2]=-1,[3]=0}, {[0]=0,[1]=1,[2]=0,[3]=-1}
local function target(dir)
  if dir == "u" then return T.x, T.y+1, T.z elseif dir == "d" then return T.x, T.y-1, T.z end
  return T.x+DX[T.d], T.y, T.z+DZ[T.d]
end
local function placer(dir) return function()
  local i = T.inv[T.sel]
  if not i or i.name:find("pickaxe") or i.name:find("coal") then return false end
  local x,y,z = target(dir)
  if getBlock(x,y,z) then return false end
  if i.name == "minecraft:lantern" and not getBlock(x,y+1,z) then return false end
  if i.name == "minecraft:chain" and not getBlock(x,y+1,z) then return false end
  setSpecial(x,y,z,i.name)
  if i.name:find("chest") or i.name:find("furnace") or i.name:find("ladder") then FACINGS[x..","..y..","..z] = FACE_NAMES[(T.d+2)%4] end
  i.count = i.count - 1 if i.count == 0 then T.inv[T.sel] = nil end
  PLACED = PLACED + 1
  return true
end end
turtle.place, turtle.placeUp, turtle.placeDown = placer("f"), placer("u"), placer("d")
local function looker(dir) return function()
  local x,y,z = target(dir)
  local b = getBlock(x,y,z)
  if not b then return false, "No block" end
  return true, { name = b, state = { facing = FACINGS[x..","..y..","..z] } }
end end
turtle.inspect, turtle.inspectUp, turtle.inspectDown = looker("f"), looker("u"), looker("d")
T.x, T.y, T.z = -4462, 15, 1521
T.inv = {} T.inv[1] = {name="minecraft:coal", count=8}
TOOL = "minecraft:diamond_pickaxe"
FS["helper.state"] = textutils.serialize({ job = { fit=true, plan="mini_fitout", shell="mini_shell", ox=OX, oy=OY, oz=OZ } })
FS[".version"] = "abc123"
""")
f = L.eval('loadfile("/home/claude/turtles/helper.lua")')
r = L.eval('function(f) return {pcall(f)} end')(f)
print("fit run:", list(r.values()), "| pos:", g.T.x, g.T.y, g.T.z, "| fuel:", g.T.fuel)
print("log:", list(g.LOG.values())[-6:])
import re
ok = bad = 0; wrong = []
for (x, y, z), full in final.items():
    name = full.split("[")[0]; m = re.search(r"facing=(\w+)", full)
    got = L.eval(f'getBlock({g.OX+x},{g.OY+y},{g.OZ+z})'); gf = L.eval(f'FACINGS["{g.OX+x},{g.OY+y},{g.OZ+z}"]')
    if name in ("minecraft:stone_bricks", "minecraft:polished_deepslate", "minecraft:deepslate_tiles"): continue
    if got == name and (not m or gf == m.group(1)): ok += 1
    else: bad += 1; wrong.append((x, y, z, full, got, gf))
hole = [L.eval(f'getBlock({g.OX},{g.OY+y},{g.OZ+2})') for y in (1, 2)]
print(f"fittings right: {ok}, wrong: {bad} {wrong[:5]} | porthole: {hole} | state:", {k: v for k, v in dict(L.eval('textutils.unserialize(FS["helper.state"])')).items() if k in ('i', 'done', 'left')})
print("orders:", [[(l[1].split(':')[1], l[2]) for l in o['items'].values()] for o in g.ORDERS.values()])
