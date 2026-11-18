import json, sys
sys.path.insert(0, __import__('os').path.dirname(__file__))
import foundry2plans as F
w = json.load(open('data/world.json'))['blocks']
def at(c):
    x, y, z = c
    return w.get(f"{-4448+x},{71+y},{1518+z}")
for name, fn in F.JOBS.items():
    p = fn()
    final = {}
    for k, c, it, s in p.ops:
        final[c] = None if k == "D" else it.split(" ")[0]
    ok = bad = 0; issues = []
    for c, want in final.items():
        have = at(c)
        if want is None:
            good = have is None
        else:
            good = have == want
        if good: ok += 1
        else:
            bad += 1; issues.append((c, want, have))
    print(f"{name:10} ok {ok:3} off {bad:3}")
    for c, want, have in issues[:int(sys.argv[1]) if len(sys.argv)>1 else 6]:
        print("     ", c, "want", want, "have", have)
