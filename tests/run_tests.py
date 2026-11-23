"""Run every tests/*.test.lua inside Lua via lupa (same approach as the turtles repo's tests).

    pip install lupa
    python tests/run_tests.py               # all tests
    python tests/run_tests.py move inv      # only files whose name contains these words
    python tests/run_tests.py --lua 54      # another Lua version (default 52 = closest to CC's Cobalt)

Each file gets a fresh Lua state with the simulator (sim/sim.lua) and the test helpers.
Exit code 1 if anything fails (so it works in CI).
"""
import glob
import importlib
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


LUA = "52"


def runtime():
    # CC:Tweaked runs Cobalt, which is Lua 5.2 with a few 5.3 extras, so test on 5.2 by default
    try:
        return importlib.import_module("lupa.lua" + LUA).LuaRuntime(unpack_returned_tuples=True)
    except ImportError:
        import lupa
        return lupa.LuaRuntime(unpack_returned_tuples=True)


def run_file(path):
    L = runtime()
    root = ROOT.replace("\\", "/")
    L.execute(f'package.path = "{root}/?.lua;" .. package.path')
    L.execute(f'dofile("{root}/sim/sim.lua")')
    L.execute(f'dofile("{root}/tests/t.lua")')
    # programs read files relative to the kit root
    os.chdir(ROOT)
    L.execute(f'dofile("{path.replace(os.sep, "/")}")')
    T = L.globals().T
    return int(T.passed), int(T.failed), [T.fails[i] for i in range(1, int(len(T.fails)) + 1)]


def main():
    global LUA
    words = sys.argv[1:]
    if "--lua" in words:
        i = words.index("--lua")
        LUA = words[i + 1]
        del words[i:i + 2]
    files = sorted(glob.glob(os.path.join(ROOT, "tests", "*.test.lua")))
    if words:
        files = [f for f in files if any(w in os.path.basename(f) for w in words)]
    bad = 0
    for f in files:
        passed, failed, fails = run_file(f)
        print(f"{os.path.relpath(f, ROOT):28s} {passed} passed, {failed} failed")
        for msg in fails:
            print("    FAIL", msg)
        bad += failed
    print(("ALL PASSED" if bad == 0 else f"FAILED: {bad}") + f"  (Lua {LUA[0]}.{LUA[1]})")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
