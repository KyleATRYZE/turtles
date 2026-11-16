import lupa
L=lupa.LuaRuntime(unpack_returned_tuples=True); L.execute("MODEM_ON=true"); L.execute(open('fharness.lua').read())
L.execute('''C="minecraft:chest_0"
put(C,"minecraft:iron_ingot",40) put(C,"minecraft:coal",64) put(C,"minecraft:coal",64) put(C,"minecraft:bucket",2)
FILES[".plots"]='{["next"]=7,["done"]=0,["hunter"]=true,["builderId"]=14,["byId"]={["9"]=1,["10"]=2,["12"]=4,["13"]=5,["5"]=6,["11"]=3}}'
MAX_IDLES=1''')
L.eval('{runFactory()}')
L.execute('''IDLES=0 MAX_IDLES=4 PAD_OCCUPIED=true NEXT_ID=13
INBOX={{id=6,msg={type="empties_request",id=6,n=8}}}''')
r=L.eval('{runFactory()}')[2]
g=L.globals()
print("result:", r, "| crafts:", g.CRAFTS)
print("handed over:", list(g.NEWBORN_FUEL.values()))
print("log:", list(g.LOG.values())[-6:])
