"""foundry.lua against a small Mekanism-like world (foundrysim.lua).

    python3 test/foundrytest.py

Checks: the machines found standing are set up as they were by hand; ore goes
through the chamber and smelter and comes back as ingots (three raw make
four); the infuser is brought in from the bench and makes steel dust and
circuits; a job from the factory is acknowledged, done and reported; nothing
is ever dropped on the floor or left behind in a machine.
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


def world():
    L = lupa.LuaRuntime(unpack_returned_tuples=True)
    L.execute(open(os.path.join(HERE, "foundrysim.lua")).read())
    L.execute(f'F = dofile("{ROOT}/foundry.lua") F.print = function(t) LOG[#LOG + 1] = tostring(t) end')
    # the chamber and smelter as they stand in the world: both facing west
    L.execute('''
      addMachine("mekanism:enrichment_chamber", 41, 1, 12, 2)
      addMachine("mekanism:energized_smelter", 41, 1, 11, 2)
      STOCK = { ["minecraft:raw_iron"] = 177, ["minecraft:redstone"] = 400, ["minecraft:iron_ingot"] = 35,
        ["minecraft:charcoal"] = 40, ["minecraft:coal"] = 60, ["alltheores:osmium_ingot"] = 6 }
      STOP_WHEN_IDLE = true
      function run() local ok, err = pcall(F.run, ENV) return ok, tostring(err) end
      function modes(x, y, z) local m = machineAt(x, y, z) return m.modes end
    ''')
    return L, L.globals()


def d(t):
    return dict(t.items()) if t is not None else {}


# ---------------------------------------------------------------- ore
L, g = world()
L.execute('F.order({ ore = "raw_iron", n = 48 })')
ok, err = g.run()
check("ore job runs to the idle wait", err == "IDLE", err)
cm, sm = d(g.modes(41, 1, 12)), d(g.modes(41, 1, 11))
check("chamber set as by hand: FRONT energy, TOP input, LEFT output (north, into the smelter)",
      cm["FRONT"] == "ENERGY" and cm["TOP"] == "INPUT" and cm["LEFT"] == "OUTPUT", str(cm))
check("smelter set as by hand: FRONT energy, RIGHT input (south), LEFT output (north)",
      sm["FRONT"] == "ENERGY" and sm["RIGHT"] == "INPUT" and sm["LEFT"] == "OUTPUT", str(sm))
check("chamber pushes its dust on by itself", L.eval("machineAt(41, 1, 12).eject") is True)
handed = d(g.HANDED)
check("48 raw iron came back as 64 ingots", handed.get("minecraft:iron_ingot") == 64, str(handed))
check("no dust or ore handed in half done",
      not any(k.startswith("mekanism:dust") or k == "minecraft:raw_iron" for k in handed), str(handed))
used = 400 - d(g.STOCK)["minecraft:redstone"] - L.eval('(machineAt(41,1,12).slots.power or {count=0}).count + (machineAt(41,1,11).slots.power or {count=0}).count')
check("redstone burned is about one dust a job (80 jobs)", 78 <= used <= 96, f"{used} dust")
check("nothing on the floor", not d(g.FLOOR), str(d(g.FLOOR)))
check("nothing left in the machines", g.inMachines() == 0, str(g.inMachines()))
check("the turtle was not standing where the chamber pushes out", not g.EJECTED_TO_TURTLE, str(g.EJECTED_TO_TURTLE))
check("one trip for supplies, one to hand in", g.FETCHES == 1 and g.HANDINS == 1, f"{g.FETCHES} {g.HANDINS}")
info = d(L.eval("F.info()"))
last = d(info["last"])
check("the report says what was made", last.get("ok") is True and d(last["made"]).get("minecraft:iron_ingot") == 64, str(last))
print("   took", g.CLOCK, "seconds of game time;", used, "redstone dust")

# a second batch: nothing to set up again, an odd count is rounded down to threes
L.execute('SETMODES = 0 HANDED = {} F.order({ job = "ore", item = "minecraft:raw_iron", n = 10 })')
ok, err = g.run()
check("second batch: 10 asked, 9 worked, 12 ingots", d(g.HANDED).get("minecraft:iron_ingot") == 12, str(d(g.HANDED)))
check("second batch: sides not set again", g.SETMODES == 0, str(g.SETMODES))

# ---------------------------------------------------------------- left-overs and no power
L, g = world()
L.execute('''
  local c = machineAt(41, 1, 12)
  c.slots.input = { name = "minecraft:raw_gold", count = 6 }     -- left from a run that lost power
  STOCK["minecraft:redstone"] = 400
  F.order({ ore = "minecraft:raw_iron", n = 12 })
''')
ok, err = g.run()
handed = d(g.HANDED)
# (the redstone brought was for the iron alone: what it will not stretch to goes back as ore)
check("left-over gold in the chamber is worked off first, not mixed up; ore there is no power for goes back",
      handed.get("minecraft:gold_ingot") == 8 and handed.get("minecraft:iron_ingot", 0) >= 8
      and handed.get("minecraft:iron_ingot", 0) * 3 / 4 + handed.get("minecraft:raw_iron", 0) == 12, str(handed))
check("left-overs: nothing on the floor, nothing in the machines", not d(g.FLOOR) and g.inMachines() == 0)

L, g = world()
L.execute('STOCK["minecraft:redstone"] = 0 F.STALL = 30 F.order({ ore = "minecraft:raw_iron", n = 12 })')
ok, err = g.run()
last = d(d(L.eval("F.info()"))["last"])
check("no redstone: the job is reported as failed, not hung", err == "IDLE" and last.get("ok") is False, str(last))
check("no redstone: nothing on the floor", not d(g.FLOOR), str(d(g.FLOOR)))

L, g = world()
L.execute('STOCK["minecraft:raw_iron"] = 0 F.order({ ore = "minecraft:raw_iron", n = 12 })')
ok, err = g.run()
last = d(d(L.eval("F.info()"))["last"])
check("no ore to be had: said so, redstone handed back",
      last.get("ok") is False and "raw_iron" in str(last.get("why")) and d(g.STOCK)["minecraft:redstone"] == 400, str(last))

# ---------------------------------------------------------------- the infuser
L, g = world()
L.execute('''
  BENCH = { x = F.BENCH.x, y = F.BENCH.y, z = F.BENCH.z, face = F.BENCH.face, item = F.BENCH.item, there = true }
  -- it comes in with a little of the wrong infusion left in it
  KEPT = { ["mekanism:metallurgic_infuser"] = { slots = {}, tank = { name = "mekanism:redstone", amount = 20 }, energy = 0,
    modes = { FRONT = "INPUT", LEFT = "INPUT", RIGHT = "OUTPUT", BACK = "ENERGY", TOP = "INPUT", BOTTOM = "EXTRA" } } }
  F.order({ job = "setup" })
''')
ok, err = g.run()
check("setup: the chamber and smelter are found, the bench is left alone, nothing is fetched",
      d(L.eval("F.info()")).get("machines") == "chamber smelter" and L.eval("BENCH.there") is True and g.FETCHES == 0,
      str(d(L.eval("F.info()"))))
L.execute('''
  F.order({ job = "move_infuser" })
  F.order({ make = "steel", n = 8 })
  F.order({ make = "circuit", n = 4 })
''')
ok, err = g.run()
check("infuser jobs run to the idle wait", err == "IDLE", err)
check("the infuser was taken off the bench", L.eval("BENCH.there") is False and not g.DUG_SOMETHING_ELSE)
inf = L.eval("machineAt(41, 1, 15)")
check("and stands in the bay facing the lane", inf is not None and inf.f == 2, str(inf and inf.f))
im = d(inf.modes)
check("infuser sides: FRONT energy, TOP input, RIGHT (south) infusion, LEFT (north) output",
      im["FRONT"] == "ENERGY" and im["TOP"] == "INPUT" and im["RIGHT"] == "EXTRA" and im["LEFT"] == "OUTPUT", str(im))
handed = d(g.HANDED)
check("8 steel dust and 4 circuits made", handed.get("alltheores:steel_dust") == 8
      and handed.get("mekanism:basic_control_circuit") == 4, str(handed))
check("the wrong infusion was emptied out first", (g.DUMPS or 0) >= 1, str(g.DUMPS))
check("infuser: nothing on the floor, nothing left inside", not d(g.FLOOR) and g.inMachines() == 0,
      f"{d(g.FLOOR)} {g.inMachines()}")
info = d(L.eval("F.info()"))
check("all three machines reported ready", info.get("ready") is True and info.get("machines") == "chamber infuser smelter", str(info))
ready = [m for m in g.SENT.values() if m["type"] == "foundry_ready"]
check("the factory is told the line is ready", ready and ready[-1]["ready"] is True)

# a new infuser from the factory when there is none on the bench
L, g = world()
L.execute('''
  BENCH = { x = F.BENCH.x, y = F.BENCH.y, z = F.BENCH.z, face = F.BENCH.face, item = F.BENCH.item, there = false }
  STOCK["mekanism:metallurgic_infuser"] = 1
  F.order({ make = "alloy", n = 2 })     -- (no copper in stock: the job fails cleanly, the machine still goes in)
''')
ok, err = g.run()
check("no infuser on the bench: one is fetched from the factory and placed",
      L.eval("machineAt(41, 1, 15)") is not None and err == "IDLE", err)
last = d(d(L.eval("F.info()"))["last"])
check("no copper: said so", last.get("ok") is False and "copper" in str(last.get("why")), str(last))

# ---------------------------------------------------------------- jobs from the factory
L, g = world()
L.execute('''
  F.order({ on = 1 })
  INBOX = {
    { from = 3, msg = { type = "foundry_hello" } },
    { from = 3, msg = { type = "foundry_job", n = 501, forId = 7, job = { kind = "ore", item = "minecraft:raw_iron", n = 24 } } },
    { from = 3, msg = { type = "foundry_job", n = 77, forId = 9, job = { kind = "ore", item = "minecraft:raw_iron", n = 24 } } },
  }
''')
ok, err = g.run()
sent = [d(m) for m in g.SENT.values()]
kinds = [m["type"] for m in sent]
check("hello answered, job acknowledged, done reported", kinds.count("foundry_ack") == 1 and kinds.count("foundry_done") == 1
      and "foundry_ready" in kinds, str(kinds))
done = [m for m in sent if m["type"] == "foundry_done"][0]
check("done: the right job, and what it made", done["n"] == 501 and done["ok"] is True
      and d(done["made"]).get("minecraft:iron_ingot") == 32, str(done))
check("a job meant for another turtle is left alone", d(g.HANDED).get("minecraft:iron_ingot") == 32, str(d(g.HANDED)))
# the factory missed the answer and asks again: told again, not done again
L.execute('SENT = {} HANDED = {} INBOX = { { from = 3, msg = { type = "foundry_job", n = 501, forId = 7, job = { kind = "ore", item = "minecraft:raw_iron", n = 24 } } } }')
ok, err = g.run()
sent = [d(m) for m in g.SENT.values()]
check("asked again for a job already done: answered again, not worked again",
      [m["type"] for m in sent] == ["foundry_done"] and not d(g.HANDED), str(sent))

# a restart half way through a job carries on from where it was
L, g = world()
L.execute('''
  F.order({ ore = "minecraft:raw_iron", n = 24 })
  local n = 0
  local walk = ENV.walk
  ENV.walk = function(...) n = n + 1 if n == 6 then error("Terminated", 0) end return walk(...) end
''')
ok, err = g.run()
L.execute('ENV.walk = nil')
L.execute(open(os.path.join(HERE, "foundrysim.lua")).read().split("-- the helper's side of things")[0].split("CLOCK = 0")[0])
L.execute('''
  local walk
  ENV.walk = function(x, y, z) T.outside = false T.x, T.y, T.z = x, y, z sleep(2) return true end
''')
ok2, err2 = g.run()
total = d(g.HANDED).get("minecraft:iron_ingot", 0) + g.onBoard("minecraft:iron_ingot")
check("a restart in the middle: the job is finished, nothing lost", err == "Terminated" and err2 == "IDLE"
      and total == 32 and not d(g.FLOOR) and g.inMachines() == 0, f"{err} / {err2} / {total} ingots / {d(g.HANDED)}")

print()
print("FAILED: " + ", ".join(fails) if fails else "PASS")
sys.exit(1 if fails else 0)
