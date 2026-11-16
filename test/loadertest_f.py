import lupa
L=lupa.LuaRuntime(unpack_returned_tuples=True); L.execute("MODEM_ON=true"); L.execute(open('fharness.lua').read())
L.execute('''C="minecraft:chest_0"
put(C,"computercraft:turtle_normal",2) put(C,"computercraft:wireless_modem_advanced",2) put(C,"advancedperipherals:chunk_controller",1)
put(C,"minecraft:coal",64) put(C,"minecraft:coal",64) put(C,"minecraft:bucket",2)
FILES[".plots"]='{["next"]=7,["done"]=0,["hunter"]=true,["builderId"]=14,["helpers"]={21,22,23},["byId"]={["9"]=1,["10"]=2,["12"]=4,["13"]=5,["5"]=6,["11"]=3,["6"]=7,["7"]=8}}'
MAX_IDLES=1''')
L.eval('{runFactory()}')
L.execute('IDLES=0 MAX_IDLES=6')
r=L.eval('{runFactory()}')[2]
g=L.globals()
print("result:", r, "| placed:", list(g.PLACED.values()), "| given:", list(g.NEWBORN_FUEL.values()))
print("replies:", [(m.to, m.msg.type, m.msg.role, m.msg.name) for m in g.OUTBOX.values() if m.msg.type=="role"])
print("plots:", g.FILES[".plots"][:400].replace("\n"," "))
print("log:", list(g.LOG.values())[-8:])
