#!/usr/bin/env python3
"""The surveyor's scans: what is actually where.

A helper with the Geo Scanner runs the lab verb survey|radius|tag at a
scan point; every block but air and plain ground goes to the controller,
which writes it to the status branch as maps/survey_<tag>_<x>_<y>_<z>_<part>.json.

    python3 tools/survey.py pull                    fetch new scans, merge into data/world.json
    python3 tools/survey.py map X1 X2 Y1 Y2 Z1 Z2   layer maps of a box (world coordinates)
    python3 tools/survey.py map factory             the factory building's box
    python3 tools/survey.py diff [factory]          survey vs the as-fitted shell (and the plans)
    python3 tools/survey.py ops factory|oldbase [r=8] [tag=...]
                                                    lab ops: walk a grid of scan points and survey
    python3 tools/survey.py points factory|oldbase  the scan points
    python3 tools/survey.py rack                    rack 1 as surveyed: home rows, shelves, strips

The ops are printed for
    tools/order.py lab <helper> clear=1 "ops=..."
(this tool sends no orders).
"""
import json
import os
import subprocess
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
REPO = "KyleATRYZE/turtles"
WORLD_FILE = os.path.join(ROOT, "data", "world.json")
OX, OY, OZ = -4448, 71, 1518
SCANNER = "advancedperipherals:geo_scanner"
FACTORY_BOX = (OX - 1, OX + 57, OY - 1, OY + 32, OZ - 1, OZ + 34)       # world, inclusive


# ================================================================= the world file
def load():
    if os.path.exists(WORLD_FILE):
        return json.load(open(WORLD_FILE))
    return {"blocks": {}, "scans": {}, "pending": {}}


def save(w):
    os.makedirs(os.path.dirname(WORLD_FILE), exist_ok=True)
    with open(WORLD_FILE, "w") as f:
        json.dump(w, f, separators=(",", ":"), sort_keys=True)


def merge(w, part):
    """one part of one scan. When every part of a scan is in, the scan's cube
    is cleared (what is not listed there is air or plain ground) and filled."""
    d = part["data"] if "data" in part else part
    key = "%s@%d,%d,%d" % (d["tag"], *d["at"])
    p = w["pending"].setdefault(key, {"at": d["at"], "r": d["r"], "parts": d["parts"], "got": {}, "time": d.get("time", 0)})
    if d.get("time", 0) > p["time"]:                       # a newer scan of the same point: start again
        p.update({"got": {}, "time": d["time"], "parts": d["parts"], "r": d["r"]})
    flat, pal = d["b"], d["pal"]
    p["got"][str(d["part"])] = [[flat[i], flat[i + 1], flat[i + 2], pal[flat[i + 3] - 1]] for i in range(0, len(flat), 4)]
    if len(p["got"]) < p["parts"]:
        return False
    ax, ay, az = p["at"]
    r = p["r"]
    for k in [k for k in w["blocks"]]:
        x, y, z = map(int, k.split(","))
        if abs(x - ax) <= r and abs(y - ay) <= r and abs(z - az) <= r:
            del w["blocks"][k]
    for recs in p["got"].values():
        for dx, dy, dz, name in recs:
            w["blocks"]["%d,%d,%d" % (ax + dx, ay + dy, az + dz)] = name
    w["scans"][key] = {"at": p["at"], "r": r, "time": p["time"], "blocks": sum(len(v) for v in p["got"].values())}
    del w["pending"][key]
    return True


def gh(path):
    out = subprocess.run(["gh", "api", "-H", "Accept: application/vnd.github+json", path],
                         capture_output=True, text=True, check=True).stdout
    return json.loads(out)


def pull():
    w = load()
    seen = set(w.get("files", []))
    listing = gh(f"repos/{REPO}/contents/maps?ref=status")
    new = [e for e in listing if e["name"].startswith("survey_") and e["sha"] not in seen]
    done = 0
    for e in sorted(new, key=lambda e: e["name"]):
        raw = subprocess.run(["gh", "api", "-H", "Accept: application/vnd.github.raw",
                              f"repos/{REPO}/contents/maps/{e['name']}?ref=status"],
                             capture_output=True, text=True, check=True).stdout
        if merge(w, json.loads(raw)):
            done += 1
        seen.add(e["sha"])
    w["files"] = sorted(seen)
    save(w)
    print(f"{len(new)} new parts, {done} scans complete; {len(w['blocks'])} blocks known, "
          f"{len(w['pending'])} scans waiting for parts")


# ================================================================= reading it
def covered(w):
    """is a world cell inside any complete scan?"""
    cubes = [(s["at"], s["r"]) for s in w["scans"].values()]
    return lambda x, y, z: any(abs(x - a[0]) <= r and abs(y - a[1]) <= r and abs(z - a[2]) <= r for a, r in cubes)


CHARS = [("cable", "-"), ("wired_modem", "m"), ("modem", "m"), ("monitor", "#"), ("computer", "C"), ("turtle", "T"),
         ("glass", ":"), ("bars", "|"), ("copper", "c"), ("barrel", "b"), ("chest", "s"), ("furnace", "f"),
         ("mekanism", "M"), ("ae2:", "A"), ("budding", "Q"), ("cauldron", "u"), ("dripstone", "v"), ("lava", "L"),
         ("water", "~"), ("stripe", "="), ("brick", "B"), ("deepslate", "D"), ("lantern", "*"), ("log", "w"),
         ("plank", "w"), ("leaves", "%"), ("grass", ","), ("cobble", "o"), ("sand", "."), ("drive", "d")]


def char(name):
    for k, c in CHARS:
        if k in name:
            return c
    return "?"


def show(box):
    w = load()
    x1, x2, y1, y2, z1, z2 = box
    inside = covered(w)
    for y in range(y2, y1 - 1, -1):
        rows = []
        any_ = False
        for z in range(z1, z2 + 1):
            row = ""
            for x in range(x1, x2 + 1):
                n = w["blocks"].get("%d,%d,%d" % (x, y, z))
                if n:
                    any_ = True
                row += char(n) if n else (" " if inside(x, y, z) else "'")
            rows.append(f"  z {z:5d}  {row}")
        if any_:
            print(f"y {y} (building y {y - OY}), x {x1}..{x2}")
            print("\n".join(rows))
    print("legend: " + "  ".join(f"{c} {k.strip(':_')}" for k, c in CHARS) + "  ? other  (blank) air or ground  ' not scanned")


def diff(box=FACTORY_BOX):
    """the survey against the as-fitted shell, and the plans on top of it"""
    import retrofit as R
    w = load()
    inside = covered(w)
    shell = R._shell("factory_asfit3.txt")
    model = R.model()
    x1, x2, y1, y2, z1, z2 = box
    missing, extra, other, planned_built = [], [], [], []
    for x in range(x1, x2 + 1):
        for y in range(y1, y2 + 1):
            for z in range(z1, z2 + 1):
                if not inside(x, y, z):
                    continue
                c = (x - OX, y - OY, z - OZ)
                got = w["blocks"].get("%d,%d,%d" % (x, y, z))
                want = shell.get(c)
                plan = model.get(c)
                if want and not got:
                    missing.append((c, want))
                elif got and not want:
                    if plan and plan.split(" ")[0].split("[")[0] in got:
                        planned_built.append((c, got))
                    elif not any(g in got for g in ("grass", "water", "short_grass", "fern")) or c[1] > 0:
                        extra.append((c, got, plan))
                elif got and want and want.split("[")[0] not in got and got not in want:
                    other.append((c, want, got))
    def out(title, rows, fmt):
        print(f"{title}: {len(rows)}")
        for r in rows[:60]:
            print("   " + fmt(r))
        if len(rows) > 60:
            print(f"   ... and {len(rows) - 60} more")
    out("in the as-fitted shell, not there", missing, lambda r: f"{r[0]} {r[1]}")
    out("there, different from the shell", other, lambda r: f"{r[0]} shell {r[1]}, found {r[2]}")
    out("there, and a plan has it (built since the shell)", planned_built, lambda r: f"{r[0]} {r[1]}")
    out("there, in no plan", extra, lambda r: f"{r[0]} {r[1]}" + (f" (a plan has {r[2]})" if r[2] else ""))


# ================================================================= rack 1 from the survey
def rack(w=None, xs=range(19, 27), z=3):
    """Rack 1 as surveyed: the shelf rows (wired modems at z 3), the monitor
    strips behind (z 4), and the home rows (each a block above or below a
    shelf, open, in every column). Returns (homes y list, shelves, strips),
    building coordinates."""
    w = w or load()
    inside = covered(w)
    at = lambda x, y, zz: w["blocks"].get("%d,%d,%d" % (OX + x, OY + y, OZ + zz))
    shelves, strips, homes = [], [], []
    for y in range(0, 12):
        row = [at(x, y, z) or "" for x in xs]
        if sum("wired_modem" in n for n in row) >= len(row) - 1:
            shelves.append(y)
        back = [at(x, y, z + 1) or "" for x in xs]
        if sum("monitor" in n for n in back) >= len(back) - 1:
            strips.append(y)
    for y in sorted({y + d for y in shelves for d in (-1, 1)}):
        cells = [(x, y, z) for x in xs]
        if all(inside(OX + c[0], OY + c[1], OZ + c[2]) and not at(*c) for c in cells):
            homes.append(y)
    return homes, shelves, strips


# ================================================================= where to scan
def points(where, r=8):
    """scan points every 2r - 1 blocks: inside the factory at floor level by
    the building's plan (walk), outside by flying there (goto)"""
    step = 2 * r - 1
    if where == "factory":
        # (building coordinates, in walkways or open floor; one height
        # covers the building's ten blocks from y 2)
        pts = [("walk", (x, 2, z)) for z in (7, 21) for x in (7, 21, 37)]
        pts += [("walk", (x, 2, 2)) for x in (10, 25, 40)]          # the lane (by the hatch)
        pts += [("walk", (x, 2, 27)) for x in (7, 21, 36)]
        pts += [("goto", (-3, 4, 12)), ("goto", (50, 4, 8))]                 # the west and east yards
        return pts
    if where == "oldbase":
        return [("goto", (x, 6, z)) for x in (-17, -8) for z in (3, 3 + step, 3 + 2 * step)]
    raise SystemExit("where: factory or oldbase")


def ops(where, r=8, tag=None):
    tag = tag or where
    s = [f"fetch|{SCANNER}=1"]
    walked = False
    for how, (x, y, z) in points(where, r):
        if how == "walk":
            if not walked:
                s.append(f"site|{OX}|{OY}|{OZ}|factory_asfit3|factory_foundryfloor")
                walked = True
            s.append(f"walk|{x}|{y}|{z}")
        else:
            if walked:
                s.append("leave")
                walked = False
            s.append(f"goto|{OX + x}|{OY + y}|{OZ + z}")
        s.append(f"survey|{r}|{tag}")
    if walked:
        s.append("leave")
    s += ["home"]
    return ";".join(s)


if __name__ == "__main__":
    a = sys.argv[1:] or ["help"]
    kv = {k: v for k, _, v in (x.partition("=") for x in a if "=" in x)}
    a = [x for x in a if "=" not in x]
    if a[0] == "pull":
        pull()
    elif a[0] == "map":
        show(FACTORY_BOX if a[1:2] == ["factory"] else tuple(map(int, a[1:7])))
    elif a[0] == "diff":
        diff()
    elif a[0] == "ops":
        print(ops(a[1], int(kv.get("r", 8)), kv.get("tag")))
    elif a[0] == "rack":
        homes, shelves, strips = rack()
        print("rack 1 (building y): home rows", homes, "shelves (wired modems)", shelves, "monitor strips", strips)
        print("world y of the home rows:", [OY + y for y in homes])
    elif a[0] == "points":
        for how, c in points(a[1], int(kv.get("r", 8))):
            print(how, *c, "world", OX + c[0], OY + c[1], OZ + c[2])
    else:
        print(__doc__)
