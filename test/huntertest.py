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

# A) stranded far west with 83 fuel at hunting height (the real CoalPorter's situation)
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
