"""The surveyor: the lab verb survey|radius|tag with the real helper.lua (a
mock Geo Scanner), and tools/survey.py merging the parts, mapping and
diffing against the as-fitted shell.

    cd test && python3 surveytest.py
"""
import json, os, sys, lupa
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "tools"))
fails = []
def check(what, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + what + (f"  [{detail}]" if detail else ""))
    if not ok: fails.append(what)
SRC = open(os.path.join(HERE, "screensfit.py")).read()
WORLD = SRC[SRC.index("    L.execute('''\n      package.path") + len("    L.execute('''"):SRC.index("    ''')\n    # the monitors")]

L = lupa.LuaRuntime(unpack_returned_tuples=True)
L.execute("START_D=3; START_FUEL=20000")
L.execute(open(os.path.join(HERE, "harness.lua")).read().replace("/home/claude/turtles", ROOT))
L.execute(open(os.path.join(HERE, "bworld.lua")).read())
L.globals().ROOT = ROOT
L.globals().INSTALL_OK = True
L.execute(WORLD)
L.execute('''
T.x, T.y, T.z = -4420, 90, 1530
T.inv[5] = { name = "advancedperipherals:geo_scanner", count = 1 }
SCANS = 0
peripheral.wrap = function(side)
  return { scan = function(r)
    SCANS = SCANS + 1
    if SCANS == 1 then return nil, "scan is on cooldown" end
    local out = {}
    for x = -r, r do for z = -r, r do
      out[#out + 1] = { name = "minecraft:stone", x = x, y = -3, z = z }
      out[#out + 1] = { name = "minecraft:air", x = x, y = 0, z = z }
    end end
    for i = 1, 900 do out[#out + 1] = { name = i % 2 == 0 and "computercraft:cable" or "minecraft:polished_deepslate",
      x = i % 17 - 8, y = -1, z = (i // 17) % 17 - 8 } end
    return out
  end }
end
FS["helper.state"] = textutils.serialize({ lab = { ops = "survey|8|test" } })
''')
helper = L.eval(f'loadfile("{ROOT}/helper.lua")')
r = list(L.eval('function(f) return {pcall(f)} end')(helper).values())
lab = list(L.eval('textutils.unserialize(FS["helper.state"]).labOut').values())
maps = [m for m in L.eval("SENT").values() if m.type == "map"]
check("survey: after the scanner's cool-down, the blocks kept (air and plain stone left out) and sent in parts",
      any("900 blocks kept" in l and "2 parts" in l for l in lab) and len(maps) == 2, lab[-2:])
check("  each part named survey_<tag>_<x>_<y>_<z>_<part>, with its palette and flat records",
      maps[0].name == "survey_test_-4420_90_1530_1" and maps[1].data.parts == 2 and len(list(maps[0].data.b.values())) == 700 * 4)
check("  the last scan kept on the turtle (survey.txt)", L.eval('FS["survey.txt"]') is not None and
      L.eval('FS["survey.txt"]').startswith("test -4420 90 1530 8"))
check("  the controller writes them as maps but says nothing in chat for each",
      'not m.name:find("^survey_")' in open(os.path.join(ROOT, "controller.lua")).read())

# ---------------------------------------------------------------- tools/survey.py
import survey as S
def tojson(lua):
    if lupa.lua_type(lua) == "table":
        keys = list(lua.keys())
        if keys and all(isinstance(k, int) for k in keys):
            return [tojson(lua[k]) for k in sorted(keys)]
        return {k: tojson(v) for k, v in lua.items()}
    return lua
parts = [{"name": m.name, "data": tojson(m.data)} for m in maps]
w = {"blocks": {"-4420,95,1530": "minecraft:glass"}, "scans": {}, "pending": {}}
check("one part: waiting for the rest", S.merge(w, parts[0]) is False and len(w["pending"]) == 1)
check("both parts: the scan is complete, its cube cleared and filled", S.merge(w, parts[1]) is True and not w["pending"]
      and "-4420,95,1530" not in w["blocks"] and len(w["blocks"]) == 17 * 17,       # (the mock's 900 records fill 289 cells)
      len(w["blocks"]))
# the diff against the shell: a factory scan where one shell block is missing and one extra stands
shell = __import__("retrofit")._shell("factory_asfit3.txt")
c0 = next(c for c, n in sorted(shell.items()) if c[1] == 1 and 5 < c[0] < 10)
w2 = {"blocks": {}, "scans": {"x": {"at": [S.OX + c0[0], S.OY + c0[1], S.OZ + c0[2]], "r": 2, "time": 1, "blocks": 1}}, "pending": {}}
for dx in range(-2, 3):
    for dy in range(-2, 3):
        for dz in range(-2, 3):
            c = (c0[0] + dx, c0[1] + dy, c0[2] + dz)
            if c in shell and c != c0:
                w2["blocks"]["%d,%d,%d" % (S.OX + c[0], S.OY + c[1], S.OZ + c[2])] = shell[c].split("[")[0]
extra = (c0[0], c0[1] + 6, c0[2]) if (c0[0], c0[1] + 6, c0[2]) not in shell else None
S.WORLD_FILE = "/tmp/surveytest_world.json"
S.save(w2)
import io, contextlib
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    S.diff()
out = buf.getvalue()
check("diff: a shell block that is not there is listed", ("%s" % (c0,)) in out.split("there, different")[0], out[:300])
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    S.show((S.OX + c0[0] - 2, S.OX + c0[0] + 2, S.OY + c0[1], S.OY + c0[1], S.OZ + c0[2] - 2, S.OZ + c0[2] + 2))
check("map: layers with a legend", "legend:" in buf.getvalue() and "y " in buf.getvalue(), buf.getvalue()[:200])
ops = S.ops("factory")
check("ops: the scanner fetched, the building walked by its plan, a survey at every point, out again",
      ops.startswith("fetch|advancedperipherals:geo_scanner=1;site|") and ops.count("survey|8|factory") == len(S.points("factory"))
      and "leave" in ops and ops.endswith("home"))
print("PASS" if not fails else "FAILED: %d" % len(fails))
