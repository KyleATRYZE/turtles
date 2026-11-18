"""The crafting assistant (factory.lua "the crafting assistant").

1. Crafty, with an assistant heard from (assist_alive), shares a load out:
   the chests (most of the work) are halved, and the lines shared out to
   even the work: the assistant's part goes to it as plan steps
   (assist_job), Crafty crafts its own part at once and does not hand the
   load over yet.
2. When the assistant says it is done (assist_done), Crafty plans the load
   again, finds the chests in stock (crafts none itself) and hands the whole
   load into the helper's bay.
3. The assistant itself (Counter with "assist Counter on=1"): takes the job,
   crafts the steps from the shared storage, puts what it made back, says
   assist_done; says assist_alive; never takes a helper's load; no pad.
4. With more loads waiting, the assistant takes every line it can of one load
   and Crafty goes straight on to the next.
5. The bookkeeping: stock held back while a job is out, an assistant that
   restarted (lost the job) or went quiet: Crafty makes the rest.
6. How much faster: the crafts on Crafty's own path for a typical load.

    cd test && python3 assisttest.py
"""
import os, lupa
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(HERE)
fails = []
def check(what, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + what + (" | " + str(detail) if detail != "" else ""))
    if not ok: fails.append(what)

FAC = open(os.path.join(ROOT, "factory.lua")).read()
HARNESS = open(os.path.join(HERE, "fharness.lua")).read().replace("/home/claude/turtles", ROOT)

STOCK = '''C="minecraft:chest_0"
put(C,"minecraft:oak_log",16) put(C,"minecraft:iron_ingot",40) put(C,"minecraft:coal",64)
put("minecraft:chest_1","minecraft:cobblestone",64)
INV.turtle_40 = { size = 16, items = {} }
INV.turtle_41 = { size = 16, items = {} }
peripheral.isPresent = function(n) return INV[n] ~= nil end
FILES[".plots"]='{["next"]=7,["done"]=0,["hunter"]=true,["builderId"]=14,["helpers"]={40,41},["loaders"]={},["byId"]={}}'
'''
def crafty(inbox, hook="", setup=""):
    L = lupa.LuaRuntime(unpack_returned_tuples=True); L.execute("MODEM_ON=true"); L.execute(HARNESS)
    L.execute(STOCK + "MAX_IDLES=1" + setup)
    L.eval('{runFactory()}')
    L.execute("IDLES=0 MAX_IDLES=4 CRAFTED={} INBOX = {%s}" % inbox)
    L.execute('''local s = rednet.send
rednet.send = function(id, m, p) s(id, m, p)
  if type(m) == "table" and m.type == "assist_job" then JOB = m JOBTEXT = textutils.serialize(m) %s end end''' % hook)
    L.eval('{runFactory()}')
    return L, L.globals()
def crafted(g, name): return sum(1 for c in g.CRAFTED.values() if c == name)
def bay(g, n):
    t = {}
    for it in g.INV[n]["items"].values(): t[it.name] = t.get(it.name, 0) + it.count
    return t
ALIVE = '{id=38,msg={type="assist_alive",label="Counter"}}'
LOAD = '{id=40,msg={type="materials",id=40,n=7,fuel=0,items={{"minecraft:chest",4},{"minecraft:iron_block",2},{"minecraft:bucket",3}},bay="turtle_40",back={}}}'

# ---------------------------------------------------------------- 1. shared out
L, g = crafty(ALIVE + "," + LOAD)
sent = [m for m in g.OUTBOX.values() if m.to == 38]
job = g.JOB
check("an assistant heard from: the load is shared out (assist_job to it)", job is not None and len(sent) == 1
      and job.forId == 38, [m.msg.type for m in sent])
names = [s.name for s in job.steps.values()] if job else []
check("  the chests (most of the work) are made half by each, the rest shared to even it out",
      names.count("minecraft:chest") == 1 and "minecraft:iron_block" in names and "minecraft:bucket" not in names
      and "chest 2" in job.what, (names, job and job.what))
check("  each step carries its recipe (the assistant need not know the woods)", job and all(s.recipe for s in job.steps.values()))
check("  Crafty crafts the rest itself at the same time", crafted(g, "minecraft:iron_block") == 0
      and crafted(g, "minecraft:bucket") >= 1 and crafted(g, "minecraft:chest") == 2, list(g.CRAFTED.values()))
check("  and does not hand the load over before the assistant is done", bay(g, "turtle_40") == {}
      and not any(m.msg.type in ("materials_ready", "load_ready") for m in g.OUTBOX.values() if m.to == 40))
check("  (the store list it must leave alone goes with the job)", job and job.skip is not None)

# ---------------------------------------------------------------- 2. done: the load handed over
DONE_HOOK = '''put("minecraft:chest_1", "minecraft:chest", 2) put("minecraft:chest_1", "minecraft:iron_block", 2)
  for s, it in pairs(INV["minecraft:chest_0"].items) do if it.name == "minecraft:oak_log" then it.count = it.count - 4 end
    if it.name == "minecraft:iron_ingot" then it.count = it.count - 18 end end
  INBOX[#INBOX + 1] = { id = 38, msg = { type = "assist_done", job = m.job, errors = {}, took = 40, label = "Counter" } }'''
L, g = crafty(ALIVE + "," + LOAD, DONE_HOOK)
t = bay(g, "turtle_40")
check("the assistant done: the whole load goes into the bay", t.get("minecraft:chest") == 4
      and t.get("minecraft:iron_block") == 2 and t.get("minecraft:bucket") == 3, t)
check("  Crafty made only its own part (the assistant's was in stock)", crafted(g, "minecraft:chest") == 2
      and crafted(g, "minecraft:iron_block") == 0, list(g.CRAFTED.values()))
check("  materials_ready sent", any(m.msg.type == "materials_ready" for m in g.OUTBOX.values() if m.to == 40))
FAIL_HOOK = '''INBOX[#INBOX + 1] = { id = 38, msg = { type = "assist_done", job = m.job, errors = { "Ran out of oak log" }, took = 5 } }'''
L, g = crafty(ALIVE + "," + LOAD, FAIL_HOOK)
t = bay(g, "turtle_40")
check("the assistant failed (nothing made): Crafty makes the chests itself and hands the load over",
      t.get("minecraft:chest") == 4 and crafted(g, "minecraft:chest") >= 1 and t.get("minecraft:iron_block") == 2, t)
L, g = crafty(LOAD)
check("no assistant: Crafty makes the load alone, as before", bay(g, "turtle_40").get("minecraft:chest") == 4
      and g.JOB is None)
L, g = crafty(ALIVE + "," + LOAD, setup='\nFILES[".plots"] = FILES[".plots"]:sub(1, -2) .. \',["assist"]=false}\'')
check("assist Crafty on=0: nothing handed out", g.JOB is None and bay(g, "turtle_40").get("minecraft:chest") == 4)

# ---------------------------------------------------------------- 4. more loads waiting
LOAD2 = '{id=41,msg={type="materials",id=41,n=3,fuel=0,items={{"minecraft:iron_block",1}},bay="turtle_41",back={}}}'
BIG = LOAD.replace('{"minecraft:chest",4},{"minecraft:iron_block",2},{"minecraft:bucket",3}', '{"minecraft:chest",4},{"minecraft:bucket",3}')
L, g = crafty(ALIVE + "," + BIG + "," + LOAD2)
names = [s.name for s in g.JOB.steps.values()] if g.JOB else []
check("two loads waiting: the assistant takes the whole of one (the smaller, first in the queue)",
      names == ["minecraft:iron_block"], names)
t = bay(g, "turtle_40")
check("  and Crafty makes and hands over the other meanwhile (none of its lines halved)",
      t.get("minecraft:chest") == 4 and t.get("minecraft:bucket") == 3 and bay(g, "turtle_41") == {}, t)

# ---------------------------------------------------------------- 3. the assistant itself
L, g = crafty(ALIVE + "," + LOAD)
jobtext = g.JOBTEXT
A = lupa.LuaRuntime(unpack_returned_tuples=True); A.execute("MODEM_ON=true"); A.execute(HARNESS)
A.execute(STOCK + '''LABEL = "Counter" FILES[".assist"] = "on" MAX_IDLES = 3
JOB = textutils.unserialize(%r)
INBOX = { { id = 5, msg = JOB }, { id = 41, msg = { type = "materials", id = 41, n = 2, fuel = 0, items = { { "minecraft:bucket", 1 } } } } }''' % jobtext.replace("[\"forId\"]=38", "[\"forId\"]=12"))
A.eval('{runFactory()}')
ga = A.globals()
done = [m for m in ga.OUTBOX.values() if m.msg.type == "assist_done"]
chests = A.eval('total("minecraft:chest_0","minecraft:chest") + total("minecraft:chest_1","minecraft:chest")')
check("the assistant crafts the job from the shared storage", crafted(ga, "minecraft:chest") == 2 and chests == 2
      and crafted(ga, "minecraft:iron_block") == 1,
      (list(ga.CRAFTED.values()), chests))
check("  puts it back in storage (nothing left on board)", not any(ga.INV.turtle_3["items"].values()))
check("  and says it is done, to Crafty", len(done) == 1 and done[0].to == 5 and done[0].msg.job == 1
      and len(done[0].msg.errors) == 0, [(m.to, m.msg.type) for m in ga.OUTBOX.values()])
check("  says it is alive (assist_alive), not counter_alive", any(r.type == "assist_alive" for r in ga.REPORTS.values() if r.type)
      and not any(r.type == "counter_alive" for r in ga.REPORTS.values() if r.type))
check("  takes no helper's load, and needs no pad", not any("Preparing a load" in l for l in ga.LOG.values())
      and A.eval('total("minecraft:chest_0","minecraft:bucket") + total("minecraft:chest_1","minecraft:bucket")') == 0
      and ga.TURNS == 0, ga.TURNS)
check("the orders: assist Counter on=1 / assist Crafty on=0", 'c.cmd == "assist"' in FAC and "K.ASSIST_FILE" in FAC)

# ---------------------------------------------------------------- 5. bookkeeping
sect = FAC[FAC.index("-- (stockTotals) less what is held back"):FAC.index("-- What the status says about the assistant(s).")]
sect = sect[:sect.index("-- How many turtle.craft calls")] + sect[sect.index("-- An assistant heard from lately"):]
B = lupa.LuaRuntime(unpack_returned_tuples=True)
B.execute('''K = { ASSIST_QUIET = 90, ASSIST_TIMEOUT = 900, assistants = {}, reserve = {} }
orders, plots, LOG = {}, {}, {}
function saveTable() end function print(s) LOG[#LOG + 1] = s end''')
B.execute(sect)
B.execute('''orders[40] = { n = 7, farm = { job = 3, aid = 38, at = 100, work = 5 } }
K.reserve[40] = { order = orders[40], items = { ["minecraft:oak_log"] = 8, ["minecraft:chest"] = 4 } }
T = { ["minecraft:oak_log"] = 16, ["minecraft:chest"] = 2, ["minecraft:stone"] = 5 }
K.reserved(T)''')
check("while a job is out, its stock is held back from Crafty's planning", B.eval('T["minecraft:oak_log"]') == 8
      and B.eval('T["minecraft:chest"]') == 0 and B.eval('T["minecraft:stone"]') == 5)
B.execute('''orders[40] = { n = 8 } T = { ["minecraft:oak_log"] = 16 } K.reserved(T)''')
check("  (the load gone or replaced: nothing held back)", B.eval('T["minecraft:oak_log"]') == 16 and B.eval("K.reserve[40]") is None)
B.execute('''orders[40] = { n = 7, farm = { job = 3, aid = 38, at = 100, work = 5 } }
K.assistHeard(38, { type = "assist_alive", label = "Counter" }, 100)
K.assistants[38].job, K.assistants[38].sentAt = 3, 100
K.assistHeard(38, { type = "assist_alive", busy = 3 }, 120)''')
check("an assistant at work is not sent another job", B.eval("K.assistFree(120)") is None and not B.eval("orders[40].farm.done"))
B.execute('''K.assistHeard(38, { type = "assist_alive" }, 160)''')
check("one that restarted (alive, not busy, a job of mine out): Crafty makes the rest", B.eval("orders[40].farm.done") is True
      and B.eval("K.assistFree(160)") == 38 and B.eval("plots.assistLog.fails") == 1)
B.execute('''orders[41] = { n = 2, farm = { job = 4, aid = 38, at = 200, work = 3 } } K.assistants[38].job = 4
K.assistWatch(300)''')
check("  heard lately and within 15 min: left to it", not B.eval("orders[41].farm.done"))
B.execute("K.assistWatch(160 + 181)")
check("  quiet for 3 minutes: Crafty makes the rest", B.eval("orders[41].farm.done") is True and B.eval("K.assistants[38].job") is None)
B.execute('''K.assistants[38].at = 2000 orders[42] = { n = 2, farm = { job = 5, aid = 38, at = 1000 } } K.assistWatch(1950)''')
check("  out over 15 minutes: Crafty makes the rest", B.eval("orders[42].farm.done") is True)

# ---------------------------------------------------------------- 6. how much faster
# Crafty's own critical path for the load in 1: alone it does every craft; shared, only its part.
L, g = crafty(LOAD)
alone = len(g.CRAFTED)
L, g = crafty(ALIVE + "," + LOAD)
mine = len(g.CRAFTED)
theirs = len([s for s in g.JOB.steps.values()]) and A.eval("#CRAFTED")
print("     crafts for the chest/iron block/bucket load: Crafty alone %d; shared: Crafty %d, the assistant %d at the same time"
      % (alone, mine, theirs))
check("a typical mixed load gets made in well under the time (the longer side is under 2/3 of alone)",
      max(mine, theirs) * 3 < alone * 2, (alone, mine, theirs))

print("PASS" if not fails else "FAILED: %d" % len(fails))
