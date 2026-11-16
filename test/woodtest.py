"""Wood: the factory makes Sophisticated Storage blocks out of whatever wood
it has, one wood per craft, never a mix (the harness, like the mod, refuses a
chest of two woods).

    cd test && python3 woodtest.py
"""
import lupa
S = "sophisticatedstorage:"
MAG, OAK, BIRCH = "regions_unexplored:magnolia", "minecraft:oak", "minecraft:birch"

def world(stock, extra="", wood=None):
    L = lupa.LuaRuntime(unpack_returned_tuples=True)
    L.execute("MODEM_ON=true")
    L.execute(extra)
    L.execute(open('fharness.lua').read())
    L.execute('C="minecraft:chest_0" D="minecraft:chest_1"')
    for name, n in stock:
        L.execute('local n=%d while n>0 do put(C,"%s",math.min(64,n)) n=n-64 end' % (n, name))
    plots = '{%s["next"]=7,["done"]=0,["hunter"]=true,["builderId"]=14,["byId"]={["9"]=1,["10"]=2,["12"]=4,["13"]=5,["5"]=6,["11"]=3}}' % (
        '["wood"]="%s",' % wood if wood else "")
    L.globals().PLOTS_TEXT = plots
    L.execute('''put(D,"minecraft:coal",64)
    FILES[".plots"]=PLOTS_TEXT
    MAX_IDLES=1
    function have(name) local n=0 for inv,I in pairs(INV) do for _,it in pairs(I.items) do if it.name==name then n=n+it.count end end end return n end''')
    L.eval('{runFactory()}')
    return L

def order(L, items):
    L.execute('IDLES=0 MAX_IDLES=4 PAD_OCCUPIED=true NEXT_ID=13 PAD_FULL=false OUTBOX={} WOOD_MADE={}')
    L.execute('INBOX={{id=14,msg={type="materials",id=14,n=(ORDER_N or 0)+1,fuel=0,items={%s}}}} ORDER_N=(ORDER_N or 0)+1' % ",".join('{"%s",%d}' % i for i in items))
    L.eval('{runFactory()}')
    g = L.globals()
    made = [(m.item, m.wood, m.n) for m in g.WOOD_MADE.values()]
    for m in g.OUTBOX.values():
        if m.msg.type == "materials_ready":
            return dict(m.msg.given), dict(m.msg.missing or {}), made, list(g.LOG.values())
    return None, None, made, list(g.LOG.values())

fails = []
def check(what, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + what + (" | " + str(detail) if detail != "" else ""))
    if not ok:
        fails.append(what)
def woods(made, item):
    out = {}
    for i, w, n in made:
        if i == item:
            out[w] = out.get(w, 0) + n
    return out
def problems(log):
    return [l for l in log if "did not work" in l or "Problem" in l or "Ran out" in l]

LEVERS = [("minecraft:lever", 64)]

# 1. only magnolia in stock: a chest all the same
L = world([(MAG + "_log", 10), ("minecraft:cobblestone", 16)])
given, missing, made, log = order(L, [(S + "chest", 1)])
check("only magnolia: one chest, made of magnolia", (given or {}).get(S + "chest") == 1 and woods(made, S + "chest") == {MAG: 1} and not problems(log),
      (given, missing, made, problems(log)))

# 2. 3 oak logs and 40 magnolia: four chests need 32 planks, oak has 12 -> all four in magnolia, the oak untouched
L = world([(OAK + "_log", 3), (MAG + "_log", 40)] + LEVERS)
given, missing, made, log = order(L, [(S + "chest", 4)])
check("3 oak + 40 magnolia, four chests: all magnolia, no mixing", (given or {}).get(S + "chest") == 4 and woods(made, S + "chest") == {MAG: 4}
      and L.globals().have(OAK + "_log") == 3 and L.globals().have(OAK + "_planks") == 0 and not problems(log), (given, made, problems(log)))
#    ... and one chest, which the oak is enough for, is oak
given, missing, made, log = order(L, [(S + "chest", 1)])
check("the same stock, one more chest: oak is enough, so oak", woods(made, S + "chest") == {OAK: 1} and L.globals().have(OAK + "_log") == 1, (made, L.globals().have(OAK + "_log")))

# 3. more than any one wood's worth: spread, one wood per chest
stock = [(OAK + "_log", 4), (MAG + "_log", 6), (BIRCH + "_log", 2)] + LEVERS      # 2 + 3 + 1 chests
L = world(stock)
given, missing, made, log = order(L, [(S + "chest", 5)])
check("five chests from oak for 2, magnolia for 3, birch for 1: magnolia 3 + oak 2", (given or {}).get(S + "chest") == 5
      and woods(made, S + "chest") == {MAG: 3, OAK: 2} and L.globals().have(BIRCH + "_log") == 2 and not problems(log), (given, made, problems(log)))
L = world(stock)
given, missing, made, log = order(L, [(S + "chest", 6)])
check("six chests: all three woods, one wood each", (given or {}).get(S + "chest") == 6 and woods(made, S + "chest") == {MAG: 3, OAK: 2, BIRCH: 1}
      and not problems(log), (given, made, problems(log)))
L = world(stock)
given, missing, made, log = order(L, [(S + "chest", 7)])
check("seven chests: six made (the most there is wood for), none of mixed wood", (given or {}).get(S + "chest") == 6 and sum(woods(made, S + "chest").values()) == 6
      and not problems(log), (given, missing, made, problems(log)))

# 4. logs, planks and slabs of a wood count together (limited barrel I: 7 planks + 1 slab)
L = world([(MAG + "_log", 1), (MAG + "_planks", 4)] + LEVERS)
given, missing, made, log = order(L, [(S + "limited_barrel_1", 1)])
check("1 log + 4 planks is not a limited barrel (the slab takes 3 more): not attempted", (given or {}).get(S + "limited_barrel_1", 0) == 0 and not made
      and L.globals().have(MAG + "_log") == 1 and not problems(log), (given, missing, made))
L = world([(MAG + "_log", 1), (MAG + "_planks", 4), (MAG + "_slab", 1), (OAK + "_planks", 6)] + LEVERS)
given, missing, made, log = order(L, [(S + "limited_barrel_1", 1)])
check("1 log + 4 planks + 1 slab is: magnolia, the 6 oak planks left alone", (given or {}).get(S + "limited_barrel_1") == 1
      and woods(made, S + "limited_barrel_1") == {MAG: 1} and L.globals().have(OAK + "_planks") == 6 and not problems(log), (given, made, problems(log)))

# 5. a big order of barrels spreads too, and every barrel is one wood (slabs and planks alike)
L = world([(OAK + "_log", 20), (MAG + "_log", 30), ("minecraft:cobblestone", 64), ("minecraft:stick", 64)])
given, missing, made, log = order(L, [(S + "limited_barrel_4", 30)])       # 4 planks + 4 slabs each
w = woods(made, S + "limited_barrel_4")
check("30 limited barrels IV over two woods", (given or {}).get(S + "limited_barrel_4") == 30 and set(w) == {OAK, MAG} and sum(w.values()) == 30
      and not problems(log), (given, missing, w, problems(log)))

# 6. stripped logs are the same wood, and are not mixed into one grid slot
L = world([("minecraft:stripped_birch_log", 1), (BIRCH + "_log", 1)] + LEVERS)
given, missing, made, log = order(L, [(S + "chest", 1)])
check("a stripped log and a plain one make one birch chest", (given or {}).get(S + "chest") == 1 and woods(made, S + "chest") == {BIRCH: 1} and not problems(log),
      (given, missing, made, problems(log)))

# 7. a wood whose planks are called something else: found out, left alone, the next wood used
L = world([("oddmod:weird_log", 40), (MAG + "_log", 4)] + LEVERS, extra='NO_PLANKS={["oddmod:weird"]="oddmod:strange_planks"}')
given, missing, made, log = order(L, [(S + "chest", 1)])
first = (given or {}).get(S + "chest")
given, missing, made2, log2 = order(L, [(S + "chest", 1)])
check("planks not named after their log: that wood is dropped, magnolia makes the chest", (first == 1 or (given or {}).get(S + "chest") == 1)
      and woods(made + made2, S + "chest") == {MAG: 1}, (first, given, made, made2, [l for l in log + log2 if "Expected" in l]))

# 8. the two planks in a controller are one wood; the plain barrel too
L = world([(OAK + "_log", 1), (MAG + "_log", 8), ("minecraft:stone", 16), ("minecraft:comparator", 4)] + LEVERS)
given, missing, made, log = order(L, [(S + "controller", 1), ("minecraft:barrel", 1)])
check("a controller and a plain barrel out of mixed stock", (given or {}).get(S + "controller") == 1 and (given or {}).get("minecraft:barrel") == 1 and not problems(log),
      (given, missing, problems(log)))

# 9. levers to make as well (their sticks take planks of any wood): the chests still come out whole, first go
L = world([(OAK + "_log", 3), (MAG + "_log", 9), ("minecraft:cobblestone", 16)])
given, missing, made, log = order(L, [(S + "chest", 4)])
check("no levers in stock: sticks, levers and four chests in one go", (given or {}).get(S + "chest") == 4 and sum(woods(made, S + "chest").values()) == 4
      and not problems(log), (given, missing, made, problems(log)))

# 10. iron chests out of chests of two woods (which do not stack in a grid slot)
L = world([(OAK + "_log", 4), (MAG + "_log", 4), ("minecraft:iron_ingot", 64)] + LEVERS)
given, missing, made, log = order(L, [(S + "iron_chest", 3)])
check("three iron chests from chests of two woods", (given or {}).get(S + "iron_chest") == 3 and len(woods(made, S + "chest")) == 2 and not problems(log),
      (given, missing, made, problems(log)))

# 11. a "wood" order names another first choice: plenty of oak, but the chest is magnolia
L = world([(OAK + "_log", 64), (MAG + "_log", 4)] + LEVERS, wood=MAG)
given, missing, made, log = order(L, [(S + "chest", 1)])
check("first choice set to magnolia: a magnolia chest though there is more oak", woods(made, S + "chest") == {MAG: 1} and L.globals().have(OAK + "_log") == 64, made)
given, missing, made, log = order(L, [(S + "chest", 4)])
check("... and oak again once the magnolia is not enough", woods(made, S + "chest") == {OAK: 4}, made)

print("PASS" if not fails else "FAILED: " + "; ".join(fails))
