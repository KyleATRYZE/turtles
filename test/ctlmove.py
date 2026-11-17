"""The storage controller moved to the middle of the west wall by a helper's
lab run (tools/ctlmove.py), in the real building with the real helper.lua.

    python3 test/ctlmove.py
"""
import os, sys, subprocess
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(HERE)
os.chdir(HERE)
src = open("storewall.py").read()
# reuse the storage wall test's building harness (everything up to the checks)
exec(src[:src.index("# ---------------------------------------------------------------- the room as it is in the world")])

# the room fitted as planned, then the move
L, g, r = run(set(), set(), set(west))
check("room fitted first", r == [False, "IDLE"], str(r))
check("the controller stands at the desk", at(L, (10, 2, 29))[0] == "sophisticatedstorage:controller", str(at(L, (10, 2, 29))))
OPS = subprocess.check_output([sys.executable, os.path.join(ROOT, "tools", "ctlmove.py"), "left"]).decode().strip()
L.execute('''
CLICKS = {}
local D = {[0]={1,0},[1]={0,1},[2]={-1,0},[3]={0,-1}}
AUTO = { useOnBlock = function()
  if T.inv[T.sel] then return nil, "hand not empty" end
  local x, z = T.x + D[T.d][1], T.z + D[T.d][2]
  local b = getBlock(x, T.y, z)
  if not b then return nil, "nothing there" end
  CLICKS[#CLICKS + 1] = b .. " " .. (x - OX) .. " " .. (T.y - OY) .. " " .. (z - OZ)
  return true end }
local gt, wr = peripheral.getType, peripheral.wrap
peripheral.getType = function(side) if side == "left" and TOOL == "advancedperipherals:weak_automata_core" then return "weakAutomata" end return gt(side) end
peripheral.wrap = function(side) if side == "left" and TOOL == "advancedperipherals:weak_automata_core" then return AUTO end return wr(side) end
STOCK["computercraft:cable"] = 20 STOCK["computercraft:wired_modem_full"] = 2 STOCK["advancedperipherals:weak_automata_core"] = 1
STOCK["minecraft:coal"] = 400
DUG, PLACED = {}, {}
''')
L.execute('FS["helper.state"] = textutils.serialize({ done = true, lab = { ops = [[%s]] } })' % OPS)
r = list(L.eval('function(f) return {pcall(f)} end')(L.eval(f'loadfile("{ROOT}/helper.lua")')).values())
st = L.eval('textutils.unserialize(FS["helper.state"])')
out = list(st.labOut.values()) if st and st.labOut else []
stopped = [l for l in out if "stopped" in l]
check("the lab ran to the end", not stopped and any("handin|" in l for l in out), "\n".join(out[-6:]))
b = lambda c: at(L, c)[0]
check("new controller on the barrel at 10 4 15", b((10, 5, 15)) == "sophisticatedstorage:controller" and "limited_barrel" in (b((10, 4, 15)) or ""), str((b((10, 5, 15)), b((10, 4, 15)))))
check("a full wired modem touching it at 10 5 16", b((10, 5, 16)) == "computercraft:wired_modem_full")
cable = [(10, y, 29) for y in range(2, 6)] + [(10, 5, z) for z in range(17, 29)]
missing = [c for c in cable if b(c) != "computercraft:cable"]
check("cable from the desk modem up and along the top of the wall", not missing, str(missing[:4]))
check("the desk modem is still there", b((10, 1, 29)) == "computercraft:wired_modem_full")
check("the new modem was right-clicked once", list(g.CLICKS.values()) == ["computercraft:wired_modem_full 10 5 16"], str(list(g.CLICKS.values())))
check("no barrel was dug", not {k: v for k, v in dict(g.DUG.items()).items() if "barrel" in k or "chest" in k}, str(dict(g.DUG.items())))
check("nothing on the floor", not g.FLOOR, str(g.FLOOR))
print("PASS" if not fails else "FAILED: %d" % len(fails))
