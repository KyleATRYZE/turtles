# The factory hands a spare Chunk Controller to the turtle that asked for one
# (and to no other), keeping back those the chunk loaders still to be built
# will need. Runs from anywhere:  python3 test/ctltest.py
import os, lupa
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(HERE)
HARNESS = open(os.path.join(HERE, 'fharness.lua')).read().replace('/home/claude/turtles', ROOT)
CTL = "advancedperipherals:chunk_controller"
fails = []
def check(what, ok):
    print(("ok   " if ok else "FAIL ") + what)
    if not ok: fails.append(what)

def run(controllers, loaders, asker, on_pad=14, given="", modems=0):
    L = lupa.LuaRuntime(unpack_returned_tuples=True); L.execute("MODEM_ON=true MODEMS=%d" % modems); L.execute(HARNESS)
    L.execute('''C="minecraft:chest_0"
put(C,"minecraft:coal",64) put(C,"minecraft:coal",64) put(C,"%s",%d)
if MODEMS > 0 then put(C,"computercraft:wireless_modem_advanced",MODEMS) end
FILES[".plots"]='{["next"]=7,["done"]=0,["hunter"]=true,["builderId"]=14,["helpers"]={21,22,23,24},["loaders"]={%s},%s["byId"]={["9"]=1}}'
MAX_IDLES=1''' % (CTL, controllers, loaders, given))
    L.eval('{runFactory()}')
    L.execute('''IDLES=0 MAX_IDLES=4 PAD_OCCUPIED=true NEXT_ID=%d
INBOX={{id=%d,msg={type="controller_request",id=%d}}}''' % (on_pad - 1, asker, asker))
    r = L.eval('{runFactory()}')[2]
    g = L.globals()
    handed = [h for h in g.NEWBORN_FUEL.values() if "chunk_controller" in h]
    none = [m for m in g.OUTBOX.values() if m.msg.type == "controller_none"]
    return handed, none, list(g.LOG.values()), g.FILES[".plots"]

handed, none, log, plots = run(3, "41,42,43,44", 14)
check("a spare goes to the turtle that asked, standing on the pad", len(handed) == 1 and "x1" in handed[0] and not none)
check("and it is written down", '["ctlGiven"]' in plots and '["14"]=1' in plots)

handed, none, log, plots = run(2, "41,42", 14, modems=2)
check("none to spare while loaders are still to be built (two ender modems wait for them): told so", not handed and len(none) == 1)

handed, none, log, plots = run(2, "41,42", 14)
check("with no ender modem to be had no loader can be built: the controllers are spare", len(handed) == 1 and not none)

handed, none, log, plots = run(3, "41,42", 14, modems=1)
check("one modem keeps one controller back, the rest are spare", len(handed) == 1 and not none)

handed, none, log, plots = run(3, "41,42,43,44", 6)
check("not handed to another turtle that happens to be on the pad", not handed)

handed, none, log, plots = run(3, "41,42,43,44", 14, given='["ctlGiven"]={["14"]=2},')
check("a turtle that has had two gets no more", not handed and len(none) == 1)
print("PASS" if not fails else "FAILED: %d" % len(fails))
