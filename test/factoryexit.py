"""A helper that wakes up inside the factory (a restart, a crash) walks out
by the big door with the real helper.lua in the real building, and never
goes looking for open sky (which took builder6 up into the roof). With a
fit-out in hand it carries on from where it stands instead.

    cd test && python3 factoryexit.py
"""
import os, lupa
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(HERE)
fails = []
def check(what, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + what + (f"  [{detail}]" if detail else ""))
    if not ok: fails.append(what)
SRC = open(os.path.join(HERE, "screensfit.py")).read()
WORLD = SRC[SRC.index("    L.execute('''\n      package.path") + len("    L.execute('''"):SRC.index("    ''')\n    # the monitors")]

def wake(x, y, z, state="{}"):
    L = lupa.LuaRuntime(unpack_returned_tuples=True)
    L.execute("START_D=3; START_FUEL=20000")
    L.execute(open(os.path.join(HERE, "harness.lua")).read().replace("/home/claude/turtles", ROOT))
    L.execute(open(os.path.join(HERE, "bworld.lua")).read())
    L.globals().ROOT = ROOT
    L.globals().INSTALL_OK = True
    L.execute(WORLD)
    L.execute(f"T.x, T.y, T.z = OX + {x}, OY + {y}, OZ + {z}")
    L.execute(f'FS["helper.state"] = textutils.serialize({state})')
    L.execute("""PATH = {}
for _, m in ipairs({ "up", "forward", "down" }) do
  local f = turtle[m]
  turtle[m] = function() local ok = f() PATH[#PATH + 1] = { x = T.x - OX, y = T.y - OY, z = T.z - OZ, up = m == "up" } return ok end
end""")
    helper = L.eval(f'loadfile("{ROOT}/helper.lua")')
    r = list(L.eval('function(f) return {pcall(f)} end')(helper).values())
    return L, r

L, r = wake(38, 1, 12)
log = list(L.eval("LOG").values())
check("woken in the foundry hall with nothing to do: walks out by the big door",
      any("walking out by the big door" in l for l in log) and not any("open sky" in l for l in log), log[:6])
path = [dict(p) for p in L.eval("PATH").values()]
check("  through the big door (22 2 33), then up outside", any(p["x"] == 22 and p["z"] == 33 and p["y"] == 2 for p in path)
      and any(p["up"] and p["z"] >= 33 for p in path), [(p["x"], p["y"], p["z"]) for p in path[-5:]])
check("it never went up inside the building (the roof)", not any(p["y"] >= 7 and 0 <= p["x"] <= 44 and 0 <= p["z"] <= 30
      for p in path))
L, r = wake(38, 1, 12, '{ job = { fit = true, plan = "factory_f2_certus", shell = "factory_asfit3", ox = OX, oy = OY, oz = OZ }, i = 3 }')
log = list(L.eval("LOG").values())
check("with a fit-out in hand: no walking out, it carries on with the plan", not any("walking out" in l for l in log)
      and any("Fitting out" in l for l in log), log[:6])
print("PASS" if not fails else "FAILED: %d" % len(fails))
