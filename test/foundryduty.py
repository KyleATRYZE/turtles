"""The factory's side of the foundry: raw ore goes to the operator a batch at
a time once the chamber and smelter are reported ready and there is redstone
to spare; the furnaces leave that ore alone meanwhile, and take it again if
the foundry is not there, fails, or the redstone runs low.

    python3 test/foundryduty.py
"""
import os, sys
import lupa

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
fails = []


def check(what, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + what + (f"  [{detail}]" if detail else ""))
    if not ok:
        fails.append(what)


def world(redstone=300, raw=177, ingots=35, known=False):
    foundry = ',["foundry"]={["op"]=23,["machines"]={["chamber"]=true,["smelter"]=true}}' if known else ""
    L = lupa.LuaRuntime(unpack_returned_tuples=True)
    L.execute("MODEM_ON=true")
    L.execute(open(os.path.join(HERE, "fharness.lua")).read().replace("/home/claude/turtles", ROOT))
    L.execute(f'''C="minecraft:chest_0" D="minecraft:chest_1"
    for _=1,8 do put(C,"minecraft:coal",64) end
    for _=1,3 do put(C,"minecraft:lava_bucket",1) end
    local function lots(inv, item, n) while n > 0 do local k = math.min(64, n) put(inv, item, k) n = n - k end end
    lots(D, "minecraft:raw_iron", {raw}) lots(D, "minecraft:redstone", {redstone}) lots(D, "minecraft:iron_ingot", {ingots})
    FILES[".plots"]='{{["next"]=7,["done"]=0,["hunter"]=true,["builderId"]=14,["helpers"]={{20,21,22,23}},["loaders"]={{30,31}},["byId"]={{["9"]=1,["10"]=2,["12"]=4,["13"]=5,["5"]=6,["11"]=3,["8"]=7}}{foundry}}}'
    NOW = 1000000000
    os.epoch = function() return NOW + os.clock() * 1000 end
    function go(idles) IDLES = 0 MAX_IDLES = idles or 3 OUTBOX = {{}} REPORTS = {{}} return {{runFactory()}} end
    function jobs() local t = {{}} for _, m in ipairs(OUTBOX) do if m.msg.type == "foundry_job" then t[#t + 1] = m end end return t end
    function hellos() local n = 0 for _, m in ipairs(REPORTS) do if m.type == "foundry_hello" then n = n + 1 end end return n end
    function cooking(item) local n = 0 for name, inv in pairs(INV) do if name:find("furnace") then
      local it = inv.items[1] if it and it.name == item then n = n + it.count end end end return n end
    function plots() return textutils.unserialize(FILES[".plots"]) end
    function said(text) for _, l in ipairs(LOG) do if l:find(text, 1, true) then return true end end return false end
    ''')
    return L, L.globals()


READY = 'INBOX[#INBOX+1] = { id = 23, msg = { type = "foundry_ready", ready = false, machines = { chamber = true, smelter = true } } }'


def first(t):
    return list(t.values())[0] if t is not None and len(list(t.values())) else None


# ---------------------------------------------------------------- nobody at the foundry yet
L, g = world()
L.eval("go(3)")
check("no operator known: the furnaces smelt raw iron as before", g.cooking("minecraft:raw_iron") > 0, str(g.cooking("minecraft:raw_iron")))
check("and the factory calls for one", g.hellos() >= 1 and len(list(g.jobs().values())) == 0, str(g.hellos()))

# ---------------------------------------------------------------- the line is ready
L, g = world()
L.execute(READY)
L.eval("go(3)")
job = first(g.jobs())
check("ready: a job is sent to the operator", job is not None and job.to == 23 and job.msg.forId == 23)
check("the job: 48 raw iron through the chamber and smelter",
      job is not None and job.msg.job.kind == "ore" and job.msg.job.item == "minecraft:raw_iron" and job.msg.job.n == 48)
L2, g2 = world(known=True)
L2.eval("go(3)")
check("the furnaces leave the raw iron to the foundry",
      g2.cooking("minecraft:raw_iron") == 0 and first(g2.jobs()) is not None, str(g2.cooking("minecraft:raw_iron")))
check("one job at a time", len(list(g.jobs().values())) == 1, str(len(list(g.jobs().values()))))
n = job.msg.n
p = g.plots()
check("the job is remembered across a restart", p.foundry.job.n == n and p.foundry.op == 23)

# not acknowledged: asked again after two minutes, not before
L.eval("go(3)")
check("no answer yet: not asked again straight away", len(list(g.jobs().values())) == 0)
L.execute("NOW = NOW + 130000")
L.eval("go(2)")
again = first(g.jobs())
check("no answer for two minutes: the same job is sent again", again is not None and again.msg.n == n)

# acknowledged, then done
L.execute(f'INBOX[#INBOX+1] = {{ id = 23, msg = {{ type = "foundry_ack", n = {n} }} }}')
L.eval("go(2)")
check("acknowledged", g.plots().foundry.job.acked is True)
L.execute(f'INBOX[#INBOX+1] = {{ id = 99, msg = {{ type = "foundry_done", n = {n}, ok = true }} }}')
L.eval("go(2)")
check("a 'done' from some other turtle is not believed", g.plots().foundry.job is not None)
L.execute(f'INBOX[#INBOX+1] = {{ id = 23, msg = {{ type = "foundry_done", n = {n}, kind = "ore", ok = true, made = {{ ["minecraft:iron_ingot"] = 64 }} }} }}')
L.eval("go(2)")
p = g.plots()
check("done: the job is closed and what was made is logged", p.foundry.job is None and g.said("The foundry made 64 iron"))
L.execute("NOW = NOW + 60000")
L.eval("go(3)")
nxt = first(g.jobs())
check("then the next batch goes out", nxt is not None and nxt.msg.n != n and nxt.msg.job.item == "minecraft:raw_iron")

# ---------------------------------------------------------------- limits
L, g = world(redstone=200)
L.execute(READY)
L.eval("go(3)")
check("redstone too low to spare: no job, the furnaces take the ore",
      first(g.jobs()) is None and g.cooking("minecraft:raw_iron") > 0, str(g.cooking("minecraft:raw_iron")))

L, g = world(raw=100)
L.execute(READY)
L.eval("go(3)")
check("not enough raw ore above what is kept back: no job", first(g.jobs()) is None)

L, g = world(ingots=640)
L.execute(READY)
L.eval("go(3)")
check("plenty of ingots already: no job", first(g.jobs()) is None)

# ---------------------------------------------------------------- when it goes wrong
L, g = world()
L.execute(READY)
for i in range(3):
    L.eval("go(3)")
    job = first(g.jobs())
    if job is None:
        break
    L.execute(f'INBOX[#INBOX+1] = {{ id = 23, msg = {{ type = "foundry_done", n = {job.msg.n}, ok = false, why = "the smelter stopped part way" }} }}')
    L.eval("go(2)")
    L.execute("NOW = NOW + 660000")
p = g.plots()
check("three failed jobs: the foundry is left alone", p.foundry.fails == 3, str(p.foundry.fails))
L.eval("go(4)")
check("and the furnaces take the raw ore again", first(g.jobs()) is None and g.cooking("minecraft:raw_iron") > 0)
L.execute("NOW = NOW + 4 * 3600000")
L.eval("go(3)")
check("a few hours on it is tried once more", first(g.jobs()) is not None)

L, g = world()
L.execute(READY)
L.eval("go(3)")
L.execute("NOW = NOW + 1300000")
L.eval("go(2)")
p = g.plots()
check("never acknowledged: dropped after twenty minutes", p.foundry.job is None and p.foundry.fails == 1 and g.said("Nobody at the foundry"))

L, g = world()
L.execute(READY)
L.eval("go(3)")
L.execute('INBOX[#INBOX+1] = { id = 23, msg = { type = "foundry_ready", ready = false, machines = {} } }')
L.execute("NOW = NOW + 1300000")
L.eval("go(3)")
L.execute("NOW = NOW + 700000")
L.eval("go(3)")
check("the operator is taken off the foundry: no more jobs, furnaces again",
      first(g.jobs()) is None and g.cooking("minecraft:raw_iron") > 0)

# ---------------------------------------------------------------- the operator's order for its supplies is an ordinary load
L, g = world()
L.execute(READY)
L.eval("go(3)")
L.execute('''PAD_OCCUPIED = true NEXT_ID = 22
  INBOX[#INBOX+1] = { id = 23, msg = { type = "materials", id = 23, n = 5, fuel = 0,
    items = { { "minecraft:raw_iron", 48 }, { "minecraft:redstone", 95 } } } }''')
L.eval("go(4)")
ready = [m.msg for m in g.OUTBOX.values() if m.msg.type == "materials_ready"]
check("the operator's supplies are handed over on the pad",
      len(ready) == 1 and ready[0].given["minecraft:raw_iron"] == 48 and ready[0].given["minecraft:redstone"] == 95,
      str([dict(r.given) for r in ready]))

# ---------------------------------------------------------------- power laid on
POWERED = 'INBOX[#INBOX+1] = { id = 23, msg = { type = "foundry_ready", ready = false, machines = { chamber = true, smelter = true }, power = { ok = true, fuel = %d } } }'
L, g = world(redstone=200)
L.execute(POWERED % 60)
L.eval("go(3)")
job = first(g.jobs())
check("on the cable: ore goes over with little redstone to spare",
      job is not None and job.msg.job.kind == "ore", str(job))
check("the status report shows the power", g.plots().foundry.power.ok is True)

L, g = world(raw=10)
L.execute(POWERED % 4)
L.eval("go(3)")
job = first(g.jobs())
check("no ore to send, the generator low: a fuel job", job is not None and job.msg.job.kind == "fuel", str(job and dict(job.msg.job.items())))
n = job.msg.n
L.execute(f'INBOX[#INBOX+1] = {{ id = 23, msg = {{ type = "foundry_done", n = {n}, kind = "fuel", ok = true, made = {{}} }} }}')
L.eval("go(2)")
L.execute("NOW = NOW + 60000")
L.eval("go(3)")
check("not another fuel job straight after", first(g.jobs()) is None)

L, g = world(raw=10)
L.execute(POWERED % 40)
L.eval("go(3)")
check("plenty of fuel in the generator: no fuel job", first(g.jobs()) is None)

L, g = world(raw=10)
L.execute('for k, inv in pairs(INV) do for i, it in pairs(inv.items) do if it.name == "minecraft:coal" then inv.items[i] = nil end end end')
L.execute(POWERED % 4)
L.eval("go(3)")
check("no coal to spare: the generator waits", first(g.jobs()) is None)

print()
print("FAILED: " + ", ".join(fails) if fails else "PASS")
sys.exit(1 if fails else 0)
