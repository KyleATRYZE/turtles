import lupa
def fresh(fuel, x, y, z, coal=0):
    L=lupa.LuaRuntime(unpack_returned_tuples=True)
    L.execute(f"START_D=1; START_FUEL={fuel}")
    L.execute(open('harness.lua').read()); L.execute(open('sharness.lua').read())
    L.execute(f'T.x,T.y,T.z,T.d={x},{y},{z},0')
    if coal: L.execute(f'T.inv[3]={{name="minecraft:coal",count={coal}}}')
    L.execute('''T.inv[2]={name="advancedperipherals:geo_scanner",count=1}
      FS["miner.state"]=textutils.serialize({swarm=true,index=3,hunt=true,huntDone={},home={x=-4442,y=15,z=1540},homeD=0,size=4,bottom=0,layer=12,
        cruise=45,dock=DOCK,exit1=EXIT1,exit2=EXIT2})''')
    return L
def show(L,tag):
    g=L.globals(); st=[]
    for v in g.STATES.values():
        if not st or st[-1]!=v: st.append(v)
    print(f"[{tag}] pos=({g.T.x},{g.T.y},{g.T.z}) fuel={g.T.fuel} moves={g.T.moves} scans={g.SCANS} coal_home={dict(g.DOCKCHEST).get('minecraft:coal')} released={list(g.RELEASED.values())} rescued={g.RESCUED} wrongway={g.VISITED_DOCKCOL_UP} label={g.LABEL} states={st[-6:]}")
    print("   log:", [l for l in g.LOG.values()][-4:])

# A) stranded far west with 83 fuel at hunting height (the real Coalition's situation)
L=fresh(83, -4531, 25, 1500)
L.execute('KILL_AT=3000')
print(list(L.eval('{runMiner("resume")}').values())); show(L,"low fuel far out")

# B) a stranded miner calls for help
L=fresh(2500, -4480, 25, 1480, coal=40)
L.execute('setSpecial(-4470,8,1470,"computercraft:turtle_normal") RESCUEQ={{at=0,id=77,msg={type="rescue",id=77,pos={x=-4470,y=8,z=1470}}}} KILL_AT=600')
print(list(L.eval('{runMiner("resume")}').values())); show(L,"rescue")

# C) a normal miner that runs dry calls for rescue
L=lupa.LuaRuntime(unpack_returned_tuples=True)
L.execute("START_D=1; START_FUEL=60"); L.execute(open('harness.lua').read()); L.execute(open('sharness.lua').read())
L.execute('placeAt(PAD,2) JOBQ={job(1,-4441,1540,4,15,0,45)} local s=0 local oldsleep=sleep sleep=function(n) s=s+1 if s>40 then error("ENOUGH",0) end return oldsleep(n) end')
print(list(L.eval('{runMiner("resume")}').values())); g=L.globals(); print("   rescue calls:", g.RESCUE_CALLS, "pos:", g.T.x, g.T.y, g.T.z, "fuel", g.T.fuel)

# D) coal under the base: the deep columns find it
L=fresh(2500, -4480, 25, 1480)
L.execute('''local e=EXIT1
DEEPORE={} for i=1,6 do local x,y,z=e.x+8+i,5,e.z+9 setSpecial(x,y,z,"minecraft:deepslate_coal_ore") DEEPORE[#DEEPORE+1]={x,y,z} end
setSpecial(e.x+40,5,e.z+9,"minecraft:coal_ore")   -- in a plot's ground: must be left
KILL_AT=2500''')
print(list(L.eval('{runMiner("resume")}').values())); show(L,"deep")
print("   deep ore left:", [1 for i in range(1,7) if L.eval(f'getBlock(DEEPORE[{i}][1],DEEPORE[{i}][2],DEEPORE[{i}][3])')], "| plot ore still there:", L.eval('getBlock(EXIT1.x+40,5,EXIT1.z+9)'), "| deepDone:", list(L.eval('textutils.unserialize(FS["miner.state"]).deepDone').values()))

# E) empty buckets on board: fetch lava from under the base, bring it home, ask for more empties
L=fresh(2500, -4480, 25, 1480)
L.execute('''local e=EXIT1
for i=0,5 do setSpecial(e.x+12+i, 3, e.z+13, "minecraft:lava") setSpecial(e.x+12+i, 2, e.z+13, "minecraft:lava") end
local st = textutils.unserialize(FS["miner.state"]) st.deepDone = {1,1,1,1} FS["miner.state"] = textutils.serialize(st)
T.inv[5] = {name="minecraft:bucket", count=9}
-- a stack of empties: one comes off the stack, a full one appears
local function scoop(x,y,z)
  local i=T.inv[T.sel]
  if not (i and i.name=="minecraft:bucket" and getBlock(x,y,z)=="minecraft:lava") then return false end
  clearBlock(x,y,z)
  i.count = i.count - 1 if i.count == 0 then T.inv[T.sel] = nil end
  for s=1,16 do if not T.inv[s] then T.inv[s] = {name="minecraft:lava_bucket", count=1} break end end
  return true
end
turtle.placeDown = function() return scoop(T.x, T.y-1, T.z) end
EMPTIES = 0
local ob = rednet.broadcast
rednet.broadcast = function(m, p)
  if type(m) == "table" and m.type == "empties_request" then
    EMPTIES = EMPTIES + 1
    for s=1,16 do local i = T.inv[s] if i and i.name == "minecraft:bucket" then i.count = i.count + m.n return end end
    for s=1,16 do if not T.inv[s] then T.inv[s] = {name="minecraft:bucket", count=m.n} return end end
  end
  return ob(m, p)
end
KILL_AT=900''')
print(list(L.eval('{runMiner("resume")}').values())); show(L,"lava")
g=L.globals()
print("   lava buckets home:", dict(g.DOCKCHEST).get('minecraft:lava_bucket'), "| empties asked for:", g.EMPTIES, "times | on board:", [(i.name.split(':')[1], i.count) for i in g.T.inv.values() if i and 'bucket' in i.name], "| lava left:", sum(1 for i in range(6) for y in (2,3) if L.eval(f'getBlock(EXIT1.x+12+{i},{y},EXIT1.z+13)')))


# F) a miner told to hunt by remote order: no scanner on board, own name; fetches a scanner from the factory, then hunts
L=fresh(2500, -4442, 26, 1540, coal=8)
L.execute('''T.inv[2]=nil
local st = textutils.unserialize(FS["miner.state"]) st.huntName = "miner3" FS["miner.state"] = textutils.serialize(st)
setSpecial(-4470, 20, 1560, "minecraft:coal") setSpecial(-4471, 20, 1560, "minecraft:coal")
KILL_AT=900''')
print(list(L.eval('{runMiner("resume")}').values())); show(L,"new hunter")
g=L.globals()
print("   scanner asked for:", g.SCANREQ, "times | label:", g.LABEL, "| scans:", g.SCANS, "| on board:", [i.name.split(':')[1] for i in g.T.inv.values() if i])

# G) a hunter carrying a Chunk Controller of its own: worn while it flies, the
# pickaxe back for every dig and every scan, and never a dig without it
L=fresh(2500, -4480, 25, 1480, coal=40)
L.execute('''T.inv[4]={name="advancedperipherals:chunk_controller",count=1}
WORN_MOVES, PICK_MOVES = 0, 0
for _, n in ipairs({"forward","up","down"}) do
  local f = turtle[n]
  turtle[n] = function() local r = f() if r then if TOOL == "advancedperipherals:chunk_controller" then WORN_MOVES = WORN_MOVES + 1 else PICK_MOVES = PICK_MOVES + 1 end end return r end
end
KILL_AT=2500''')
print(list(L.eval('{runMiner("resume")}').values())); show(L,"own controller")
g=L.globals()
print("   dug without the pickaxe:", g.DUG_WITHOUT_PICK, "| moves with the controller on:", g.WORN_MOVES, "| with the pickaxe on:", g.PICK_MOVES,
      "| fitted now:", g.TOOL, "| on board:", sorted(set(i.name.split(':')[1] for i in g.T.inv.values() if i)))
