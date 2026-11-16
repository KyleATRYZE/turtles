import lupa
L=lupa.LuaRuntime(unpack_returned_tuples=True); L.execute("MODEM_ON=true"); L.execute(open('fharness.lua').read())
L.execute('''C="minecraft:chest_0"
put(C,"minecraft:raw_iron",64) put(C,"minecraft:raw_iron",64) put(C,"minecraft:raw_iron",64) put(C,"minecraft:raw_iron",64)
for i=1,12 do put("minecraft:chest_1","minecraft:lava_bucket",1) end
put(C,"minecraft:coal",40)
FILES[".plots"]='{["next"]=7,["done"]=0,["hunter"]=true,["builderId"]=14,["helpers"]={21,22,23,24},["loaders"]={31,32},["byId"]={["9"]=1,["10"]=2,["12"]=4,["13"]=5,["5"]=6,["11"]=3,["6"]=7,["7"]=8}}'
MAX_IDLES=1''')
L.eval('{runFactory()}')
L.execute('''IDLES=0 MAX_IDLES=4 PAD_OCCUPIED=true NEXT_ID=13
INBOX={{id=14,msg={type="materials",id=14,n=1,fuel=0,items={{"minecraft:iron_ingot",200}}}}}''')
r=L.eval('{runFactory()}')[2]
g=L.globals()
tot=lambda n: sum(i.count for inv in g.INV.values() for i in inv['items'].values() if i and i.name==n)
print("result:", r, "| smelted:", g.SMELTED, "| lava burned:", g.LAVA_BURNED, "| coal left:", tot("minecraft:coal"), "| lava left:", tot("minecraft:lava_bucket"), "| empty buckets:", tot("minecraft:bucket"))
print("furnace fuel slots:", [ (n, (inv['items'][2].name, inv['items'][2].count) if inv['items'][2] else None) for n,inv in g.INV.items() if 'furnace' in n])
print("handed over:", list(g.NEWBORN_FUEL.values())[:6])
print("log:", list(g.LOG.values())[-5:])
