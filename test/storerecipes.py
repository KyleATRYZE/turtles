"""Sophisticated Storage recipes: the factory's grids against the mod's real
patterns (written out separately in fharness.lua), and a hand-over to a
builder with no free slot."""
import lupa
def world():
    L=lupa.LuaRuntime(unpack_returned_tuples=True); L.execute("MODEM_ON=true"); L.execute(open('fharness.lua').read())
    L.execute('''C="minecraft:chest_0" D="minecraft:chest_1"
    for _=1,3 do put(C,"minecraft:oak_log",64) end
    put(C,"minecraft:jungle_log",2) put(C,"minecraft:cobblestone",64) put(C,"minecraft:coal",64)
    put(C,"minecraft:redstone",64) put(C,"minecraft:quartz",4) put(C,"minecraft:ender_pearl",3)
    put(D,"minecraft:raw_iron",64) put(D,"minecraft:raw_iron",64) put(D,"minecraft:raw_gold",64) put(D,"minecraft:raw_gold",64)
    put(D,"minecraft:diamond",64) put(D,"sophisticatedstorage:controller",1)
    FILES[".plots"]='{["next"]=7,["done"]=0,["hunter"]=true,["builderId"]=14,["byId"]={["9"]=1,["10"]=2,["12"]=4,["13"]=5,["5"]=6,["11"]=3}}'
    MAX_IDLES=1''')
    L.eval('{runFactory()}')
    return L
def order(L, items, full=False):
    L.execute('IDLES=0 MAX_IDLES=4 PAD_OCCUPIED=true NEXT_ID=13 PAD_FULL=%s' % ("true" if full else "false"))
    L.execute('INBOX={{id=14,msg={type="materials",id=14,n=1,fuel=0,items={%s}}}}' % ",".join('{"%s",%d}' % i for i in items))
    L.eval('{runFactory()}')
    g=L.globals()
    for m in g.OUTBOX.values():
        if m.msg.type=="materials_ready":
            return dict(m.msg.given), dict(m.msg.missing or {}), list((m.msg.full or {}).values()), list(g.LOG.values())
    return None, None, None, list(g.LOG.values())
S="sophisticatedstorage:"
want=[(S+"chest",2),(S+"barrel",1),(S+"limited_barrel_1",4),(S+"limited_barrel_2",1),(S+"limited_barrel_3",1),(S+"limited_barrel_4",1),
      (S+"diamond_chest",1),(S+"storage_link",1),(S+"storage_tool",1),(S+"basic_tier_upgrade",1),(S+"stack_upgrade_tier_2",1),
      (S+"controller",2),("minecraft:lever",2),("minecraft:barrel",2)]
fails=0
L=world()
given,missing,full,log=order(L,want)
print("given:",given); print("missing:",missing)
bad=[l for l in log if "did not work" in l or "Problem" in l]
print("recipe problems:",bad)
for name,n in want:
    if (given or {}).get(name)!=n: fails+=1; print("FAIL short of",name,(given or {}).get(name))
if bad or missing: fails+=1
crafted=list(L.globals().CRAFTED.values())
print("crafted kinds:",sorted(set(crafted)))
# the old test recipe (planks around a redstone torch) must be gone
if not any(c==S+"chest" for c in crafted): fails+=1; print("FAIL no chest crafted")

# a builder with no room: in stock, not handed over, and said so
L=world()
given,missing,full,log=order(L,[(S+"controller",1)],full=True)
print("full builder -> given:",given,"| missing:",missing,"| full:",full,"|",[l for l in log if "no room" in l])
if given.get(S+"controller")!=0 or full!=[S+"controller"] or not any("no room for controller" in l for l in log): fails+=1; print("FAIL full report")
tot=L.eval('(function() local n=0 for _,inv in pairs(INV) do for _,it in pairs(inv.items) do if it.name=="sophisticatedstorage:controller" then n=n+it.count end end end return n end)()')
print("controller still in the factory's stock:",tot)
if tot!=1: fails+=1; print("FAIL controller lost")
# and with room, the same order goes through
L=world()
given,missing,full,log=order(L,[(S+"controller",1)])
print("builder with room -> given:",given,"| full:",full)
if given.get(S+"controller")!=1 or full: fails+=1; print("FAIL plain hand-over")
print("PASS" if not fails else "FAILED %d" % fails)
