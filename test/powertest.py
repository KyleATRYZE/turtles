"""foundry.lua: laying power on in the foundry bay (foundrysim.lua).

    python3 test/powertest.py

Checks: job=power places the heat generator facing north at (42,1,18), the
cube facing north at (42,1,17) and cable from z 16 to the first machine,
sets each machine's back to take energy, feeds the generator and finds the
power reaching the machines. An ore job afterwards needs no redstone; one
without a cube lays cable in its place; a cube later takes the cable's place;
lava is used only once a bucket is seen to come back; the bank and a smelt
job run on the cable; the generator gets fuel as it runs low.
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


def world(extra=""):
    L = lupa.LuaRuntime(unpack_returned_tuples=True)
    L.execute(open(os.path.join(HERE, "foundrysim.lua")).read())
    L.execute(f'F = dofile("{ROOT}/foundry.lua") F.print = function(t) LOG[#LOG + 1] = tostring(t) end')
    L.execute('''
      addMachine("mekanism:enrichment_chamber", 41, 1, 12, 2)
      addMachine("mekanism:energized_smelter", 41, 1, 11, 2)
      addMachine("mekanism:metallurgic_infuser", 41, 1, 15, 2)
      STOCK = { ["minecraft:raw_iron"] = 177, ["minecraft:redstone"] = 400, ["minecraft:iron_ingot"] = 35,
        ["minecraft:charcoal"] = 40, ["minecraft:coal"] = 200,
        ["mekanismgenerators:heat_generator"] = 1, ["mekanism:basic_energy_cube"] = 1,
        ["mekanism:basic_universal_cable"] = 16, ["mekanism:energized_smelter"] = 3,
        ["minecraft:sand"] = 300, ["minecraft:lava_bucket"] = 6 }
      STOP_WHEN_IDLE = true
      function run() local ok, err = pcall(F.run, ENV) return ok, tostring(err) end
      function at(x, y, z) local m = machineAt(x, y, z) return m and m.item, m and m.f end
      function emode(x, y, z, side) return machineAt(x, y, z).emodes[side] end
    ''' + extra)
    return L, L.globals()


def d(t):
    return dict(t.items()) if t is not None else {}


GEN, CUBE, CABLE = "mekanismgenerators:heat_generator", "mekanism:basic_energy_cube", "mekanism:basic_universal_cable"

# ---------------------------------------------------------------- power with a cube
L, g = world()
L.execute('F.order({ job = "power" })')
ok, err = g.run()
check("power job runs to the idle wait", err == "IDLE", err)
item, f = g.at(42, 1, 18)
check("generator at (42,1,18) facing north", item == GEN and f == 3, f"{item} {f}")
item, f = g.at(42, 1, 17)
check("cube at (42,1,17) facing north", item == CUBE and f == 3, f"{item} {f}")
cables = [z for z in range(11, 17) if g.at(42, 1, z)[0] == CABLE]
check("cable from z 16 to z 11", cables == list(range(11, 17)), str(cables))
check("each machine's back set to take energy",
      all(g.emode(41, 1, z, "BACK") == "INPUT" for z in (11, 12, 15)),
      str([g.emode(41, 1, z, "BACK") for z in (11, 12, 15)]))
info = d(L.eval("F.info()"))
p = d(info.get("power"))
on = d(p.get("on"))
check("power is on and reaches all three machines", p.get("ok") is True and all(on.get(n) in ("yes", "full") for n in ("chamber", "smelter", "infuser")), str(p) + " " + str(on))
check("generator fed", L.eval("(machineAt(42,1,18).slots.fuel or {count=0}).count") > 30, str(p.get("fuel")))
check("lava left alone unless asked", L.eval("machineAt(42,1,18).lava") is None)
check("nothing on the floor", not d(g.FLOOR), str(d(g.FLOOR)))
check("the factory is told the power is on",
      any(m["type"] == "foundry_ready" and m["power"] and m["power"]["ok"] for m in g.SENT.values()))
check("spare parts handed back (no cable left on board)", L.eval('onBoard("mekanism:basic_universal_cable")') == 0)

# an ore job now: no redstone burned
L.execute('HANDED = {} F.order({ ore = "raw_iron", n = 48 })')
before = d(g.STOCK)["minecraft:redstone"]
ok, err = g.run()
used = before - d(g.STOCK)["minecraft:redstone"]
handed = d(g.HANDED)
check("on the cable: 48 raw iron still make 64 ingots", handed.get("minecraft:iron_ingot") == 64, str(handed))
dust_in = L.eval('(machineAt(41,1,12).slots.power or {count=0}).count + (machineAt(41,1,11).slots.power or {count=0}).count')
check("on the cable: no redstone put in the machines", dust_in == 0 and used <= 8, f"{used} taken, {dust_in} in machines")
check("on the cable: nothing left in the machines", g.inMachines() == 0, str(g.inMachines()))

# ---------------------------------------------------------------- no cube, then a cube
L, g = world('STOCK["mekanism:basic_energy_cube"] = nil')
L.execute('F.order({ job = "power" })')
ok, err = g.run()
check("no cube to be had: cable at z 17 instead", g.at(42, 1, 17)[0] == CABLE and g.at(42, 1, 18)[0] == GEN)
check("no cube: power still on", d(d(L.eval("F.info()")).get("power")).get("ok") is True)
L.execute('STOCK["mekanism:basic_energy_cube"] = 1 F.order({ job = "power" })')
ok, err = g.run()
item, f = g.at(42, 1, 17)
check("a cube later: it takes the cable's place, facing north", item == CUBE and f == 3, f"{item} {f}")
check("a cube later: the cable is laid again behind it", g.at(42, 1, 16)[0] == CABLE)
check("a cube later: nothing dug but our own cable", all(x == CABLE for x in g.DUG.values()), str(list(g.DUG.values())))
check("a cube later: power still on", d(d(L.eval("F.info()")).get("power")).get("ok") is True)

# ---------------------------------------------------------------- the chamber off the cable: back to redstone
L, g = world()
L.execute('F.order({ job = "power" })')
g.run()
L.execute('machineAt(41,1,12).emodes.BACK = "NONE"')   # (the chamber's back no longer takes power)
L.execute('machineAt(41,1,12).energy = 0 HANDED = {} F.order({ ore = "raw_iron", n = 24 })')
ok, err = g.run()
on = d(d(d(L.eval("F.info()")).get("power")).get("on"))
check("chamber off the cable: it goes back to redstone", on.get("chamber") == "no", str(on))
L.execute('HANDED = {} F.order({ ore = "raw_iron", n = 24 })')
ok, err = g.run()
check("and the next job runs it on redstone (and works off what the short one left)",
      d(g.HANDED).get("minecraft:iron_ingot", 0) >= 32 and g.inMachines() == 0, str(d(g.HANDED)))

# ---------------------------------------------------------------- lava
L, g = world()
L.execute('F.order({ job = "power", fuel = "lava" })')
g.run()
p = d(d(L.eval("F.info()")).get("power"))
check("lava tried when asked: the bucket comes back, lava works", p.get("lava") == "works" and L.eval("machineAt(42,1,18).lava") >= 1000, str(p))
check("lava: empty buckets handed back in", d(g.HANDED).get("minecraft:bucket", 0) >= 1, str(d(g.HANDED)))
L, g = world('LAVA_STUCK = true')
L.execute('F.order({ job = "power", fuel = "lava" })')
g.run()
p = d(d(L.eval("F.info()")).get("power"))
check("lava when the bucket stays in: noted, only one bucket used", p.get("lava") == "stuck" and 0 < L.eval("machineAt(42,1,18).lava") <= 1000, str(p))

# ---------------------------------------------------------------- bank and smelt
L, g = world()
L.execute('F.order({ job = "power" }) F.order({ job = "bank" })')
g.run()
bank = [g.at(41, 1, z) for z in (7, 8, 9)]
check("bank: three smelters at z 7-9 facing the lane", all(b[0] == "mekanism:energized_smelter" and b[1] == 2 for b in bank), str(bank))
cables = [z for z in range(7, 17) if g.at(42, 1, z)[0] == CABLE]
check("bank: cable carried on north to z 7", cables == list(range(7, 17)), str(cables))
L.execute('HANDED = {} F.order({ smelt = "sand", n = 200 })')
before = d(g.STOCK)["minecraft:redstone"]
ok, err = g.run()
handed = d(g.HANDED)
check("smelt 200 sand through four smelters: 200 glass", handed.get("minecraft:glass") == 200, str(handed))
check("smelt: no redstone in the bank", all(L.eval(f'(machineAt(41,1,{z}).slots.power or {{count=0}}).count') == 0 for z in (7, 8, 9)))
check("smelt: nothing left in the machines, nothing on the floor", g.inMachines() == 0 and not d(g.FLOOR), f"{g.inMachines()} {d(g.FLOOR)}")
L, g = world()
L.execute('F.order({ job = "bank" })')
g.run()
last = d(d(L.eval("F.info()")).get("last"))
check("bank before power: refused, nothing placed", last.get("ok") is False and g.at(41, 1, 9)[0] is None, str(last))

# ---------------------------------------------------------------- the infuser brought in after the power
L, g = world('MACHINES["41,1,15"] = nil BENCH = { x = -4453, y = 74, z = 1533, face = 0, item = "mekanism:metallurgic_infuser", there = true }')
L.execute('F.order({ job = "power" })')
g.run()
L.execute('F.order({ job = "move_infuser" })')
g.run()
on = d(d(d(L.eval("F.info()")).get("power")).get("on"))
check("infuser brought in after the power: its back takes power, it counts as on the cable",
      g.emode(41, 1, 15, "BACK") == "INPUT" and on.get("infuser") in ("full", "yes"), f"{g.emode(41, 1, 15, 'BACK')} {on}")

# ---------------------------------------------------------------- the generator kept fed
L, g = world()
L.execute('F.order({ job = "power" })')
g.run()
L.execute('machineAt(42,1,18).slots.fuel = { name = "minecraft:coal", count = 4 }')
L.execute('S = F.load() S.power.fuel = 4 F.save(S) HANDED = {} F.order({ ore = "raw_iron", n = 48 })')
g.run()
fuel = L.eval("(machineAt(42,1,18).slots.fuel or {count=0}).count")
check("low on fuel: the next job brings fuel and tops the generator up", fuel >= 48, str(fuel))
L.execute('machineAt(42,1,18).slots.fuel = nil S = F.load() S.power.fuel = 0 F.save(S)')
L.execute('INBOX = { { from = 3, msg = { type = "foundry_job", n = 77, job = { kind = "fuel" } } } }')
g.run()
fuel = L.eval("(machineAt(42,1,18).slots.fuel or {count=0}).count")
done = [m for m in g.SENT.values() if m["type"] == "foundry_done" and m["n"] == 77]
check("a fuel job from the factory fills the generator and is reported", fuel >= 60 and done and done[-1]["ok"] is True, f"{fuel} {done and dict(done[-1].items())}")

print()
print("FAILED: " + ", ".join(fails) if fails else "PASS")
sys.exit(1 if fails else 0)
