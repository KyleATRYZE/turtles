import lupa
def fresh(fuel=300, coal=24):
    L=lupa.LuaRuntime(unpack_returned_tuples=True)
    L.execute(f"START_D=1; START_FUEL={fuel}")
    L.execute(open('harness.lua').read()); L.execute(open('sharness.lua').read())
    L.execute(f'placeAt(PAD, 2); T.inv[1]={{name="minecraft:coal",count={coal}}}')
    return L
def run(L):
    return list(L.eval('{runMiner("resume")}').values())
def info(L, tag, plots):
    g=L.globals()
    rem=[L.eval('plotRemaining(%d,%d,%d,%d,%d)'%p) for p in plots]
    print(f"[{tag}] pos=({g.T.x},{g.T.y},{g.T.z}) fuel={g.T.fuel} moves={g.T.moves} plot_remaining={rem} done={list(g.DONE.values())} "
          f"dock_items={sum(dict(g.DOCKCHEST).values())} kinds={len(dict(g.DOCKCHEST))} needs={g.NEEDS} fuelreq={g.FUELREQ} wrongway={g.VISITED_DOCKCOL_UP} maxY={g.MAXY} floors={g.FLOORS} floor_in_shaft={g.FLOOR_IN_SHAFT} broke={g.BROKE_PROTECTED} lostgood={g.LOSTGOOD} states={list(g.STATES.values())[-6:]}")

P1=(-4441,1540,4,15,0); P2=(-4489,1472,4,15,0)
# 1) newborn on the pad: two plots in a row, then no more jobs
L=fresh()
L.execute('JOBQ={job(1,-4441,1540,4,15,0,45), job(2,-4489,1472,4,15,0,46)}')
print(run(L)); info(L,"two plots", [P1,P2])

# 2) restart at every 23rd move along the whole route, random facing each time
L=fresh()
L.execute('JOBQ={job(1,-4441,1540,4,15,0,45), job(2,-4489,1472,4,15,0,46)}')
import itertools
n=0
for k in range(23, 4000, 23):
    L.execute(f"KILL_AT={k}")
    r=run(L)
    if r[1]!='KILLED': break
    n+=1
    L.execute("T.d=(T.d+%d)%%4" % (k%4))
L.execute("KILL_AT=nil")
print("restarts:", n, r); info(L,"restart storm", [P1,P2])

# 3) drop-off chest full for a while; and arriving with almost no fuel/coal
L=fresh(fuel=300, coal=3)
L.execute('JOBQ={job(1,-4441,1540,4,15,0,45)} DOCK_FULL=4')
print(run(L)); info(L,"dock full + low fuel", [P1])

# 4) remote orders in swarm mode: home (park), then resume
L=fresh()
L.execute('JOBQ={job(1,-4441,1540,4,15,0,45)} CMDQ={{at=150,cmd={id=1,target="all",cmd="home"}}}')
print(run(L)); info(L,"home order", [P1])
L.execute('CMDQ={{at=0,cmd={id=2,target="all",cmd="resume"}}}')
print(run(L)); info(L,"resume order", [P1])

# 5) lava fuel: start with a bucket, lava pool two layers down; bucket and cobble stay on board at the base
L=fresh(fuel=300, coal=24)
L.execute('T.inv[2]={name="minecraft:bucket",count=1} addLava(-4441,1540,4,6) addLava(-4441,1540,4,5) JOBQ={job(1,-4441,1540,4,15,0,45)}')
print(run(L)); info(L,"lava fuel", [P1])
print("    lava buckets burned:", L.globals().LAVA_BURNED, "| on board at end:", L.eval('invNames()'), "| label:", L.globals().LABEL, "| role file:", L.eval('FS[".role"]'))

# 6) no bucket: asks the factory on its first visit
L=fresh()
L.execute('JOBQ={job(1,-4441,1540,4,15,0,45)}')
print(run(L)); info(L,"bucket request", [P1])
print("    bucket requests:", L.globals().BUCKETREQ, "| on board:", L.eval('invNames()'))

# 7) factory has no buckets: stops asking after a few tries, still finishes
L=fresh()
L.execute('NO_BUCKETS=true JOBQ={job(1,-4441,1540,4,15,0,45)}')
print(run(L)); info(L,"no buckets available", [P1])
print("    bucket requests:", L.globals().BUCKETREQ)

# 8) coal hunter: stuck at the base with little fuel, factory hands over the Geo Scanner instead of coal
L=fresh(fuel=120, coal=0); L.execute("KILL_AT=4000")
L.execute('''JOBQ={job(1,-4441,1540,4,15,0,45)}
local sb = rednet.broadcast
rednet.broadcast = function(m, p)
  if m.type == "fuel_request" then FUELREQ = FUELREQ + 1
    if not GAVE then GAVE = true for i=1,16 do if not T.inv[i] then T.inv[i] = {name="advancedperipherals:geo_scanner", count=1} break end end end
    return
  end
  return sb(m, p)
end''')
r=run(L); print(r); info(L,"coal hunter", [P1])
g=L.globals()
print("    label:", g.LABEL, "| scans:", g.SCANS, "| coal delivered:", dict(g.DOCKCHEST).get('minecraft:coal'), "| tool:", g.TOOL, "| dug without pickaxe:", g.DUG_WITHOUT_PICK, "| on board:", L.eval('invNames()'))

# 9) tank already full, five empty buckets: four come home full of lava for the others, one empty stays on board
L=fresh(fuel=12000, coal=24)
L.execute('T.inv[2]={name="minecraft:bucket",count=5} for i=0,7 do addLava(-4441+i,1540,4,6) end JOBQ={job(1,-4441,1540,4,15,0,45)}')
print(run(L)); info(L,"lava for the base", [P1])
g=L.globals()
print("    lava buckets in the drop-off chest:", dict(g.DOCKCHEST).get('minecraft:lava_bucket'), "| burned:", g.LAVA_BURNED, "| on board at end:", L.eval('invNames()'), "| empties asked for:", g.EMPTYREQ)
