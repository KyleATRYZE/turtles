# Every program in the manifest compiles.  python3 test/syntax.py
import os, sys, lupa
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
L = lupa.LuaRuntime(unpack_returned_tuples=True)
bad = 0
names = [l.strip() for l in open(os.path.join(ROOT, "manifest.txt")) if l.strip()] + ["install.lua"]
for name in names:
    src = open(os.path.join(ROOT, name), encoding="latin-1").read()
    ok, err = L.eval("function(s, n) local f, e = load(s, n) return f ~= nil, e end")(src, name)
    if not ok:
        bad += 1
        print("FAIL", name, err)
print("PASS" if not bad else "FAILED: %d" % bad)
sys.exit(1 if bad else 0)
