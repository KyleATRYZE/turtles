"""tools/lint.py: catch CC:Tweaked-specific problems before code reaches a turtle.

    pip install lupa
    python tools/lint.py                      # this folder
    python tools/lint.py path/to/turtles      # another repo
    python tools/lint.py . --style            # also suggest lib/ helpers over raw turtle calls
    python tools/lint.py . --github           # GitHub Actions annotations

Checks (each one is a real way CC programs break):
  E syntax       compiled as Lua 5.2, which is what CC's Cobalt VM is based on
  E lua53        `//`, `&`, `|`, `~`, `<<`, `>>` compile on a PC (Lua 5.3+) but NOT in CC
  E upvalues     a function using more than 60 upvalues: Lua 5.2 allows 255, Cobalt only 60,
                 so it loads on your PC and fails in game ("too many upvalues")
                 (warns from 50, so you see it coming)
  E locals       more than 200 locals in one function (same limit in both, caught by compile)
  W require      require("x.y") with no x/y.lua in the repo (cc.* modules are skipped)
  W disk         files a role downloads add up to more than 80% of a computer's 1 MB disk
  I style        (--style) raw turtle.forward/up/down/dig outside lib/: use lib.move

Skips tests/, test/, sim/ by default (they run on a PC, not in game). Exit code 1 on errors.
"""
import argparse
import os
import re
import struct
import sys

try:
    import importlib
    lua52 = importlib.import_module("lupa.lua52")
    lua54 = importlib.import_module("lupa.lua54")
except ImportError:  # older lupa: one runtime only
    import lupa as lua52
    lua54 = None

SKIP_DIRS = {".git", "node_modules", "tests", "test", "sim", "__pycache__"}
COBALT_MAX_UPVALUES = 60
DISK_BYTES = 1_000_000

findings = []


def add(level, path, line, msg):
    findings.append((level, path, line, msg))


# ------------------------------------------------------------------ Lua 5.2 bytecode walk
class Reader:
    def __init__(self, b):
        self.b, self.i = b, 0
        # header: 4 sig, version, format, endian, int, size_t, instr, number, integral, 6 tail
        h = b[:18]
        if h[:4] != b"\x1bLua" or h[4] != 0x52:
            raise ValueError("not Lua 5.2 bytecode")
        self.little = h[6] == 1
        self.sint, self.ssize, self.sinstr, self.snum = h[7], h[8], h[9], h[10]
        self.i = 18

    def byte(self):
        v = self.b[self.i]
        self.i += 1
        return v

    def _int(self, size):
        v = int.from_bytes(self.b[self.i:self.i + size], "little" if self.little else "big")
        self.i += size
        return v

    def int(self):
        return self._int(self.sint)

    def size(self):
        return self._int(self.ssize)

    def string(self):
        n = self.size()
        s = self.b[self.i:self.i + n]
        self.i += n
        return s[:-1] if n else None


def walk_functions(r, out):
    """Collect (linedefined, upvalue count, max stack) for every function prototype."""
    line = r.int()
    r.int()  # lastlinedefined
    r.byte()  # numparams
    r.byte()  # is_vararg
    maxstack = r.byte()
    ncode = r.int()
    r.i += ncode * r.sinstr
    nconst = r.int()
    for _ in range(nconst):
        t = r.byte()
        if t == 1:
            r.byte()
        elif t == 3:
            r.i += r.snum
        elif t == 4:
            r.string()
    nproto = r.int()
    for _ in range(nproto):
        walk_functions(r, out)
    nup = r.int()
    r.i += nup * 2
    r.string()  # source
    nline = r.int()
    r.i += nline * r.sint
    nloc = r.int()
    for _ in range(nloc):
        r.string()
        r.int()
        r.int()
    nupn = r.int()
    for _ in range(nupn):
        r.string()
    out.append((line, nup, maxstack))


# ------------------------------------------------------------------ checks
L52 = lua52.LuaRuntime(encoding=None, unpack_returned_tuples=True)
compile52 = L52.eval(
    "function(src, name) local f, e = load(src, name) if not f then return nil, e end"
    " return string.dump(f), false end"
)
compile54 = None
if lua54:
    L54 = lua54.LuaRuntime(encoding=None, unpack_returned_tuples=True)
    compile54 = L54.eval("function(src, name) local f, e = load(src, name) return f ~= nil, e end")

ERR_LINE = re.compile(rb":(\d+):")


def check_file(path, rel, style):
    src = open(path, "rb").read()
    dumped, err = compile52(src, ("@" + rel).encode())
    if dumped is None:
        msg = err.decode(errors="replace") if isinstance(err, bytes) else str(err)
        m = ERR_LINE.search(err if isinstance(err, bytes) else err.encode())
        line = int(m.group(1)) if m else 1
        ok54 = compile54 and compile54(src, rel.encode())[0]
        if ok54:
            add("E", rel, line, "lua53: compiles in Lua 5.3+ but not in CC (Cobalt is Lua 5.2): "
                "no //, &, |, ~, <<, >> (use math.floor(a / b) and bit32)  [" + msg.split(":", 2)[-1].strip() + "]")
        elif "too many local variables" in msg:
            add("E", rel, line, "locals: more than 200 locals in one function: " + msg)
        else:
            add("E", rel, line, "syntax: " + msg)
        return
    funcs = []
    try:
        walk_functions(Reader(dumped) if not isinstance(dumped, str) else Reader(dumped.encode("latin-1")), funcs)
    except Exception as e:  # never let the walker hide other findings
        add("W", rel, 1, f"could not read bytecode ({e}); upvalue check skipped")
    for line, nup, _ in funcs:
        if nup > COBALT_MAX_UPVALUES:
            add("E", rel, max(line, 1), f"upvalues: function uses {nup} upvalues; CC allows {COBALT_MAX_UPVALUES}. "
                "Group them into a table (e.g. local K = {...}) so they count as one.")
        elif nup >= COBALT_MAX_UPVALUES - 10:
            add("W", rel, max(line, 1), f"upvalues: function uses {nup} of CC's {COBALT_MAX_UPVALUES} upvalues; "
                "a few more locals above it and it stops loading in game")

    text = src.decode("utf-8", errors="replace")
    for m in re.finditer(r"""require\s*\(?\s*["']([\w.]+)["']""", text):
        mod = m.group(1)
        if mod.startswith("cc.") or mod in ("cc",):
            continue
        root = find_root(path)
        cand = [os.path.join(root, *mod.split(".")) + ".lua", os.path.join(root, mod + ".lua"),
                os.path.join(os.path.dirname(path), mod.split(".")[-1] + ".lua")]
        if not any(os.path.exists(c) for c in cand):
            add("W", rel, text.count("\n", 0, m.start()) + 1, f"require: no file for module '{mod}' in the repo")

    if style and not rel.replace("\\", "/").startswith("lib/"):
        for m in re.finditer(r"\bturtle\.(forward|back|up|down|dig|digUp|digDown)\s*\(", text):
            add("I", rel, text.count("\n", 0, m.start()) + 1,
                f"style: raw turtle.{m.group(1)}(): lib.move tracks position and reports unloaded/protected blocks")


ROOT = "."


def find_root(_path):
    return ROOT


def check_disk(root):
    """manifest.txt lines: 'file.lua' or 'file.lua role1,role2'. Sum bytes per role."""
    man = os.path.join(root, "manifest.txt")
    if not os.path.exists(man):
        return
    roles = {}
    for n, line in enumerate(open(man, encoding="utf-8"), 1):
        parts = line.split()
        if not parts or parts[0].startswith("#"):
            continue
        f = os.path.join(root, parts[0])
        size = os.path.getsize(f) if os.path.exists(f) else 0
        if not os.path.exists(f):
            add("W", "manifest.txt", n, f"disk: {parts[0]} is listed but missing")
        for role in (parts[1].split(",") if len(parts) > 1 else ["every machine"]):
            roles[role] = roles.get(role, 0) + size
    for role, total in sorted(roles.items()):
        pct = 100 * total / DISK_BYTES
        if pct > 80:
            add("W", "manifest.txt", 1, f"disk: '{role}' downloads {total:,} bytes = {pct:.0f}% of the 1 MB disk "
                "(logs, state and updates need room too): split the manifest by role")


def main():
    global ROOT
    ap = argparse.ArgumentParser()
    ap.add_argument("root", nargs="?", default=".")
    ap.add_argument("--style", action="store_true")
    ap.add_argument("--github", action="store_true")
    a = ap.parse_args()
    ROOT = os.path.abspath(a.root)

    count = 0
    for dirpath, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for f in sorted(files):
            if f.endswith(".lua"):
                p = os.path.join(dirpath, f)
                check_file(p, os.path.relpath(p, ROOT), a.style)
                count += 1
    check_disk(ROOT)

    names = {"E": "error", "W": "warning", "I": "notice"}
    for level, path, line, msg in sorted(findings, key=lambda x: (x[1], x[2])):
        if a.github:
            print(f"::{names[level]} file={path},line={line}::{msg}")
        else:
            print(f"{path}:{line}: {names[level]}: {msg}")
    errors = sum(1 for f in findings if f[0] == "E")
    warns = sum(1 for f in findings if f[0] == "W")
    print(f"{count} files: {errors} errors, {warns} warnings")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
