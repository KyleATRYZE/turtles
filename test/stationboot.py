# A blank computer set on the launch pad boots from the factory's floppy
# (DISK_STARTUP in factory.lua) and must come up as a screen station and as
# nothing else: installed, named, switched off; or, when the download fails
# or an old updater answers, left blank for another try.
#   python3 test/stationboot.py
import os, re, lupa
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(HERE)
fails = []
def check(what, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + what + (f"  [{detail}]" if detail else ""))
    if not ok: fails.append(what)

DISK = re.search(r"local DISK_STARTUP = \[\[\n(.*?)\]\]", open(os.path.join(ROOT, "factory.lua")).read(), re.S).group(1)
UPDATE = open(os.path.join(ROOT, "update.lua")).read()
MANIFEST = open(os.path.join(ROOT, "manifest.txt")).read()

def boot(update_src, is_turtle=False, online=True, files=None):
    L = lupa.LuaRuntime(unpack_returned_tuples=True)
    g = L.globals()
    g.DISK, g.UPDATE_SRC, g.MANIFEST, g.ONLINE = DISK, update_src, MANIFEST, online
    L.execute('''
      FILES, LABEL, OFF, RAN = {}, nil, false, {}
      fs = { exists = function(n) n = n:gsub("^/", "") return FILES[n] ~= nil end,
        delete = function(n) FILES[n:gsub("^/", "")] = nil end,
        open = function(n, mode)
          n = n:gsub("^/", "")
          if mode == "r" then local s = FILES[n] if not s then return nil end
            return { readAll = function() return s end, close = function() end } end
          local buf = {}
          return { write = function(t) buf[#buf + 1] = t end, close = function() FILES[n] = table.concat(buf) end }
        end }
      os.epoch = function() return 1 end
      os.getComputerID = function() return 31 end
      os.getComputerLabel = function() return LABEL end
      os.setComputerLabel = function(l) LABEL = l end
      os.shutdown = function() OFF = true error("OFF", 0) end
      os.reboot = function() error("REBOOT", 0) end
      http = { get = function(url)
        if not ONLINE then return nil, "no route" end
        if type(url) == "table" then url = url.url end
        local body
        if url:find("api.github.com", 1, true) then body = string.rep("a", 40)
        elseif url:find("update.lua", 1, true) then body = UPDATE_SRC
        elseif url:find("manifest.txt", 1, true) then body = MANIFEST
        else body = "-- " .. url end
        return { readAll = function() return body end, close = function() end }
      end }
      shell = { run = function(prog, ...)
        RAN[#RAN + 1] = prog
        prog = prog:gsub("^/", "")
        if prog == "wget" then return end
        local src = FILES[prog] or FILES[prog .. ".lua"]
        if src then local f = assert(load(src, prog)) f() end
      end }
      print = function() end
      sleep = function() end
    ''')
    if is_turtle: L.execute("turtle = {} gps = { locate = function() end } require = function() error('no swarm') end")
    for k, v in (files or {}).items(): g.FILES[k] = v
    r = L.eval('function() return {pcall(load(DISK, "disk"))} end')()
    return g, list(r.values())

g, r = boot(UPDATE)
f = dict(g.FILES.items())
check("a blank computer installs itself as a screen station", f.get(".role") == "screen"
      and f.get("startup.lua") == 'shell.run("update")\nshell.run("screens")\n' and "screens.lua" in f, str(r))
check("it takes the name station-<number> and switches off", g.LABEL == "station-31" and g.OFF is True)
check("the token file is not something it ever has", ".github_token" not in f)

old = UPDATE.replace(' and role ~= "screen"', "").replace('elseif role == "screen" then\n  job = \'shell.run("screens")\'\n', "")
assert old != UPDATE
g, r = boot(old)
f = dict(g.FILES.items())
check("an old updater would have made it a controller: it is left blank and unnamed instead",
      g.LABEL is None and "startup.lua" not in f and ".role" not in f and g.OFF is True, str(sorted(f)))

g, r = boot(UPDATE, online=False)
f = dict(g.FILES.items())
check("no download: left blank, unnamed, switched off", g.LABEL is None and "startup.lua" not in f and g.OFF is True)

g, r = boot(UPDATE, files={"startup.lua": "RAN[#RAN + 1] = 'own startup'"})
check("a machine that is already set up just runs its own startup", "own startup" in list(g.RAN.values()) and g.LABEL is None)

g, r = boot(UPDATE, is_turtle=True)
check("a new turtle still becomes a miner the old way", g.LABEL == "miner-31" and "wget" in list(g.RAN.values())
      and dict(g.FILES.items()).get(".role") is None)
print("PASS" if not fails else "FAILED: %d" % len(fails))
