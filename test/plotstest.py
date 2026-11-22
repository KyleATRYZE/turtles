# The controller hands out the miners' plots (the factory computer that did it is gone).
# Runs from anywhere:  python3 test/plotstest.py
import os, re, lupa
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(HERE)
src = open(os.path.join(ROOT, "controller.lua"), encoding="utf-8").read()
code = re.search(r"-- PLOTS BEGIN(.*?)-- PLOTS END", src, re.S).group(1)
fails = []
def check(what, ok):
    print(("ok   " if ok else "FAIL ") + what)
    if not ok: fails.append(what)

def fresh(files=""):
    L = lupa.LuaRuntime(unpack_returned_tuples=True)
    L.execute("""FILES = {%s} SENT = {}
fs = { exists = function(p) return FILES[p] ~= nil end,
  open = function(p, m) if m == "w" then return { write = function(t) FILES[p] = t end, close = function() end } end
    return { readAll = function() return FILES[p] end, close = function() end } end }
textutils = { serialize = function(t) local function s(v) if type(v) == "table" then local o = {} for k, x in pairs(v) do o[#o + 1] = "[" .. (type(k) == "number" and k or ("%%q"):format(k)) .. "]=" .. s(x) end return "{" .. table.concat(o, ",") .. "}" end return tostring(v) end return s(t) end,
  unserialize = function(t) local f = load("return " .. t) return f and f() end }
rednet = { send = function(id, m) SENT[#SENT + 1] = { id = id, msg = m } end }
""" % files)
    L.execute(code + "\nP = { cells = plotCells, job = plotJob, done = plotDone, box = PLOTS.box }")
    return L

L = fresh()
cells = [(c.x0, c.z0) for c in L.eval("P.cells()").values()]
check("there are plots to give", len(cells) > 50)
check("every plot lies wholly inside the loaded box", all(-4480 <= x and x + 7 <= -4353 and 1512 <= z and z + 7 <= 1631 for x, z in cells))
check("none is north of z 1512 (the mountain base and beyond)", min(z for x, z in cells) >= 1512)
check("all sit on the old grid", all((x + 4437) % 8 == 0 and (z - 1521) % 8 == 0 for x, z in cells))
check("none is in the rings dug before (within 5 squares of the origin)", all(max(abs((x + 4437) // 8), abs((z - 1521) // 8)) >= 6 for x, z in cells))
check("ring 6 west of its third column is left out", all(not (max(abs((x + 4437) // 8), abs((z - 1521) // 8)) == 6 and (x + 4437) // 8 <= 1) for x, z in cells))
check("no plot twice", len(set(cells)) == len(cells))
a = L.eval("P.job(12)"); b = L.eval("P.job(13)"); a2 = L.eval("P.job(12)")
check("two miners get different plots", (a.x0, a.z0) != (b.x0, b.z0) and a.index == 1 and b.index == 2)
check("a miner that asks again gets the plot it has", a2.index == 1 and a2.x0 == a.x0)
check("the job carries the dock and shafts", a.dock.x == -4460 and a.exit1.x == -4461 and a.exit2.x == -4462 and a.topY == 50 and a.bottom == -58 and a.size == 8 and a.type == "job" and a.forId == 12)
check("job_done for another plot changes nothing", L.eval("P.done(12, 9)") is False and L.eval("P.job(12)").index == 1)
check("job_done frees the miner for the next plot", L.eval("P.done(12, 1)") is True and L.eval("P.job(12)").index == 3)
saved = L.eval('FILES[".plots"]')
L2 = fresh('[".plots"] = %r' % saved)
check("after a restart nothing is handed out twice", L2.eval("P.job(13)").index == 2 and L2.eval("P.job(40)").index == 4)
L3 = fresh('[".plots"] = "{[\\"next\\"]=100000,[\\"byId\\"]={}}"')
check("when the plots run out there is no answer", L3.eval("P.job(5)") is None)
print("PASS" if not fails else "FAILED: %d" % len(fails))
raise SystemExit(1 if fails else 0)
