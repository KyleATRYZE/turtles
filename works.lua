-- works.lua : the foundry on the cable (docs/foundry-build.html). Runs on
-- the works computer in the foundry floor, role "works".
--
-- Every machine of the hall (docs/foundry-v2.md: the ore line on the east
-- wall, the alloy cell) sits on a full-block wired modem in the floor (its
-- BOTTOM face), on the same cable as the store. Items go from the store
-- straight into a machine by its network name and the results come straight
-- back: no turtle carries anything. The infuser's infusion items go in by
-- the same face, switched to EXTRA for the moment.
--
-- It speaks the factory's foundry protocol (factory.lua "the foundry"), the
-- one foundry1's foundry.lua speaks: it says foundry_ready with its machines,
-- takes foundry_job (ore, the infuser's makes, enrich, smelt), answers
-- foundry_ack and foundry_done with what it made. Messages go over the
-- cable (crafter1 listens on its wired modem too); reboot orders come from
-- crafter1 on the rack channel.
--
-- If the store cannot push into a Mekanism machine by name (crafter1's
-- "probe" order says), this computer is not used: the fallback is the
-- piped line with its inbox and outbox barrels (docs/mekanism-plan.md).

local okSwarm, swarm = pcall(require, "swarm")
if not okSwarm then swarm = nil end

local W = {}
W.JOB = "swarm_job"
W.STATUS = "swarm"
W.CHANNEL = 4711                     -- factory.lua K.RACK_CHANNEL (reboot orders)
W.FACE = "BOTTOM"                    -- the face on the floor modem
W.ORE_OUT, W.ORE_IN = "RIGHT", "LEFT"  -- the ore line faces west: south is RIGHT, north LEFT
W.NO_PROGRESS = 120                  -- seconds without anything coming out: the job has stopped
W.MAX_BATCH = 48

-- (as foundry.lua M.INFUSE and M.GAS)
W.INFUSE = {
  steel = { makes = "alltheores:steel_dust", passes = {
    { input = "minecraft:iron_ingot", gas = "carbon", mb = 10, out = "mekanism:enriched_iron" },
    { input = "mekanism:enriched_iron", gas = "carbon", mb = 10 } } },
  circuit = { makes = "mekanism:basic_control_circuit", passes = {
    { input = "alltheores:osmium_ingot", gas = "redstone", mb = 20 } } },
  alloy = { makes = "mekanism:alloy_infused", passes = {
    { input = "minecraft:copper_ingot", gas = "redstone", mb = 10 } } },
  reinforced = { makes = "mekanism:alloy_reinforced", passes = {
    { input = "mekanism:alloy_infused", gas = "diamond", mb = 20 } } },
  atomic = { makes = "mekanism:alloy_atomic", passes = {
    { input = "mekanism:alloy_reinforced", gas = "refined_obsidian", mb = 40 } } },
  refined = { makes = "mekanism:dust_refined_obsidian", passes = {
    { input = "mekanism:dust_obsidian", gas = "diamond", mb = 10 } } },
}
W.GAS = {
  carbon = { name = "mekanism:carbon", items = { { "mekanism:enriched_carbon", 80 }, { "minecraft:charcoal", 10 }, { "minecraft:coal", 10 } } },
  redstone = { name = "mekanism:redstone", items = { { "mekanism:enriched_redstone", 80 }, { "minecraft:redstone", 10 } } },
  diamond = { name = "mekanism:diamond", items = { { "mekanism:enriched_diamond", 80 }, { "mekanism:dust_diamond", 10 } } },
  refined_obsidian = { name = "mekanism:refined_obsidian",
    items = { { "mekanism:enriched_refined_obsidian", 80 }, { "mekanism:dust_refined_obsidian", 10 } } },
}

W.m = {}          -- chamber, smelter, infuser, extra (the infuser's second name), crusher, bank = { names }
W.stores = {}
W.notes = {}
W.made = {}

local function note(s)
  W.notes[#W.notes + 1] = s
  while #W.notes > 8 do table.remove(W.notes, 1) end
  print(s)
end
local function call(name, method, ...)
  local r = table.pack(pcall(peripheral.call, name, method, ...))
  if r[1] then return table.unpack(r, 2, r.n) end
  return nil, r[2]
end

---------------------------------------------------------------- what is on the cable
function W.isStore(name)
  if name:find("^mekanism") or name:find("furnace", 1, true) or name:find("turtle", 1, true)
    or name:find("computer", 1, true) or name:find("barrel", 1, true) or name:find("monitor", 1, true)
    or name:find("drive", 1, true) or name:find("manager", 1, true) or name:find("bridge", 1, true) then
    return false
  end
  return peripheral.hasType(name, "inventory") and true or false
end

-- The hall (docs/foundry-v2.md): the ore line on the east wall faces WEST
-- (the chamber at z 12 pushes south into the smelter at z 13); the alloy
-- cell faces EAST (infusers, a smelter bank, a second chamber, a crusher),
-- every machine on its own floor modem. Which is which is read from the
-- machine itself (getDirection). A machine that cannot say counts as the
-- ore line's if there is none yet.
local function facing(name)
  local d = call(name, "getDirection")
  return type(d) == "string" and d:upper() or nil
end

-- Mekanism's own peripherals come on the cable as metallurgicInfuser_0,
-- energizedSmelter_1 and so on (not mekanism:metallurgic_infuser_0): both
-- spellings are read as the block's id
local CAMEL = { enrichmentChamber = "mekanism:enrichment_chamber", energizedSmelter = "mekanism:energized_smelter",
  metallurgicInfuser = "mekanism:metallurgic_infuser", crusher = "mekanism:crusher" }
function W.kind(name)
  local base, n = tostring(name):match("^(.-)_(%d+)$")
  if base and CAMEL[base] then return CAMEL[base] .. "_" .. n end
  return name
end

function W.scan(names)
  W.m = { bank = {}, infusers = {} }
  W.stores = {}
  for _, name in ipairs(names) do
    local id = W.kind(name)
    local east = id:find("^mekanism") and facing(name) == "EAST"
    if id:find("^mekanism:enrichment_chamber") then
      if east then W.m.enrich = W.m.enrich or name else W.m.chamber = W.m.chamber or name end
    elseif id:find("^mekanism:energized_smelter") then
      if east or W.m.smelter then W.m.bank[#W.m.bank + 1] = name else W.m.smelter = name end
    elseif id:find("^mekanism:metallurgic_infuser") then W.m.infusers[#W.m.infusers + 1] = name
    elseif id:find("^mekanism:crusher") then W.m.crusher = W.m.crusher or name
    elseif W.isStore(name) then W.stores[#W.stores + 1] = name end
  end
  table.sort(W.stores, function(a, b)
    local ca, cb = a:find("controller", 1, true) ~= nil, b:find("controller", 1, true) ~= nil
    if ca ~= cb then return ca end
    return a < b
  end)
  table.sort(W.m.infusers)
  table.sort(W.m.bank)
  W.m.infuser = W.m.infusers[1]
  if not W.m.chamber and W.m.enrich then W.m.chamber, W.m.enrich = W.m.enrich, nil end
  return W.m
end

-- The sides: every machine's floor face takes items in and gives results
-- out. On the ore line the chamber pushes its dust on south (RIGHT, facing
-- west) into the smelter (in by its LEFT); nothing else ejects.
function W.setup()
  local function io(name)
    if not name then return end
    local ok = pcall(peripheral.call, name, "setMode", "ITEM", W.FACE, "INPUT_OUTPUT")
    if not ok then
      call(name, "setMode", "ITEM", W.FACE, "INPUT")
      note(name .. ": no INPUT_OUTPUT; results by ejection only")
    end
    call(name, "setRedstoneMode", "IGNORED")
    call(name, "setEjecting", "ITEM", false)
  end
  for _, n in ipairs({ W.m.chamber, W.m.smelter, W.m.enrich, W.m.crusher }) do io(n) end
  for _, b in ipairs(W.m.bank) do io(b) end
  for _, f in ipairs(W.m.infusers) do io(f) end
  if W.m.chamber and W.m.smelter then
    call(W.m.chamber, "setMode", "ITEM", W.ORE_OUT, "OUTPUT")
    call(W.m.chamber, "setEjecting", "ITEM", true)
    call(W.m.smelter, "setMode", "ITEM", W.ORE_IN, "INPUT")
  end
end

---------------------------------------------------------------- moving items
function W.count(item)
  local n = 0
  for _, inv in ipairs(W.stores) do
    for _, it in pairs(call(inv, "list") or {}) do
      if it.name == item then n = n + it.count end
    end
  end
  return n
end

-- up to n of an item from the store into a machine (by its name)
function W.put(target, item, n)
  local left = n
  for _, inv in ipairs(W.stores) do
    if left <= 0 then break end
    for slot, it in pairs(call(inv, "list") or {}) do
      if left <= 0 then break end
      if it.name == item then
        local moved = call(inv, "pushItems", target, slot, left) or 0
        left = left - moved
      end
    end
  end
  return n - left
end

-- everything that can come out of a machine back into the store; { name = n }
function W.takeOut(source)
  local got = {}
  for slot = 1, 6 do
    local out = call(source, "getOutput")
    local name = type(out) == "table" and out.name or nil
    for _, inv in ipairs(W.stores) do
      local moved = call(inv, "pullItems", source, slot) or 0
      if moved > 0 then
        local key = name or "?"
        got[key] = (got[key] or 0) + moved
        W.made[key] = (W.made[key] or 0) + moved
      end
    end
  end
  return got
end

local function stack(t) return type(t) == "table" and (tonumber(t.count) or 0) or 0 end
local function busy(name) return name and (stack(call(name, "getInput")) > 0) end

-- wait for the machines to finish, taking out what they make
function W.runDown(machines, want)
  local total, last = 0, os.clock()
  while true do
    local moved = 0
    for _, m in ipairs(machines) do
      for _, c in pairs(W.takeOut(m)) do moved = moved + c end
    end
    total = total + moved
    if moved > 0 then last = os.clock() end
    local working = false
    for _, m in ipairs(machines) do if busy(m) then working = true end end
    if not working and (not want or total >= want or os.clock() - last > 10) then return total, nil end
    if os.clock() - last > W.NO_PROGRESS then return total, "nothing came out for " .. W.NO_PROGRESS .. " s" end
    sleep(3)
  end
end

---------------------------------------------------------------- jobs
local function oreLot(item)
  if item:find(":raw_", 1, true) and not item:find("_block", 1, true) then return 3, 4 / 3 end
  return 1, 2
end

function W.ore(job, smelt)
  local machine = (not smelt and W.m.enrich) or W.m.chamber
  if not machine then return false, "no enrichment chamber on the cable" end
  if smelt and not W.m.smelter then smelt = false end
  if machine == W.m.chamber then call(machine, "setEjecting", "ITEM", smelt and true or false) end
  local lot, yield = oreLot(job.item)
  local n = math.min(job.n or W.MAX_BATCH, W.count(job.item))
  n = n - n % lot
  if n <= 0 then return false, "no " .. job.item .. " in the store" end
  local put = W.put(machine, job.item, n)
  if put == 0 then return false, "the chamber would not take " .. job.item end
  local want = math.floor(put * yield)
  local _, why = W.runDown(smelt and { machine, W.m.smelter } or { machine }, want)
  return why == nil, why
end

function W.smelt(job)
  local list = {}
  for _, b in ipairs(W.m.bank) do list[#list + 1] = b end
  if #list == 0 then list[1] = W.m.smelter end
  if #list == 0 then return false, "no smelter on the cable" end
  local n = math.min(job.n or 64, W.count(job.item))
  local per = math.ceil(n / #list)
  local put = 0
  for _, m in ipairs(list) do put = put + W.put(m, job.item, math.min(per, n - put)) end
  if put == 0 then return false, "no " .. job.item .. " to smelt" end
  local _, why = W.runDown(list, put)
  return why == nil, why
end

function W.fill(gasKey, mb)
  local gas = W.GAS[gasKey]
  local tank = call(W.m.infuser, "getInfuseType")
  local have = type(tank) == "table" and tonumber(tank.amount) or 0
  if have > 0 and type(tank) == "table" and tank.name ~= gas.name then
    call(W.m.infuser, "dumpInfuseType")
    have = 0
  end
  for _, it in ipairs(gas.items) do
    if have >= mb then break end
    local n = math.min(W.count(it[1]), math.ceil((mb - have) / it[2]))
    if n > 0 then
      -- the infusion items go in by the same floor face, switched to EXTRA
      -- for the moment (the infuser has one modem)
      if not W.m.extra then call(W.m.infuser, "setMode", "ITEM", W.FACE, "EXTRA") end
      have = have + W.put(W.m.extra or W.m.infuser, it[1], n) * it[2]
      if not W.m.extra then call(W.m.infuser, "setMode", "ITEM", W.FACE, "INPUT_OUTPUT") end
    end
  end
  return have
end

function W.infuse(job)
  local recipe = W.INFUSE[job.kind]
  if not W.m.infuser then return false, "no infuser on the cable" end
  W.runDown({ W.m.infuser })                         -- (whatever was left in it)
  for _, pass in ipairs(recipe.passes) do
    local n = math.min(job.n or W.MAX_BATCH, W.MAX_BATCH, W.count(pass.input))
    if n <= 0 then return false, "no " .. pass.input end
    local mb = W.fill(pass.gas, n * pass.mb)
    n = math.min(n, math.floor(mb / pass.mb))
    if n == 0 then return false, "no " .. pass.gas .. " for the infuser" end
    if W.put(W.m.infuser, pass.input, n) == 0 then return false, "the infuser would not take " .. pass.input end
    local _, why = W.runDown({ W.m.infuser }, n)
    if why then return false, why end
  end
  return true
end

function W.run(job)
  W.made = {}
  local ok, why
  if job.kind == "ore" then ok, why = W.ore(job, true)
  elseif job.kind == "enrich" then ok, why = W.ore(job, false)
  elseif job.kind == "smelt" then ok, why = W.smelt(job)
  elseif W.INFUSE[job.kind] then ok, why = W.infuse(job)
  elseif job.kind == "fuel" then ok = true             -- (the generator is not on the cable: fed by hand)
  else ok, why = false, "no such job: " .. tostring(job.kind) end
  if W.m.chamber and W.m.smelter then call(W.m.chamber, "setEjecting", "ITEM", true) end
  return ok, why, W.made
end

function W.ready()
  return { chamber = W.m.chamber and true or nil, smelter = W.m.smelter and true or nil,
    infuser = W.m.infuser and true or nil, infusers = #W.m.infusers, crusher = W.m.crusher and true or nil,
    enrich = W.m.enrich and true or nil,
    bank = #W.m.bank > 0 and #W.m.bank or nil, cable = true }
end

if _G.WORKS_TEST then return W end

---------------------------------------------------------------- running
local wired
for _, name in ipairs(peripheral.getNames()) do
  if peripheral.getType(name) == "modem" then
    local m = peripheral.wrap(name)
    rednet.open(name)
    if not m.isWireless() then wired = wired or m end
  end
end
if not wired then error("No wired modem next to me: I work the machines over the cable.", 0) end
wired.open(W.CHANNEL)
local hasBridge = false
for _, name in ipairs(peripheral.getNames()) do
  if tostring(peripheral.getType(name) or ""):lower():find("bridge", 1, true) then hasBridge = true end
end
if not hasBridge then              -- (with ME in charge, the machines' sides are ME's: left alone)
  W.scan(wired.getNamesRemote())
  W.setup()
  note(("Machines: chamber %s, smelter %s, infuser %s, bank %d, stores %d."):format(
    tostring(W.m.chamber), tostring(W.m.smelter), tostring(W.m.infuser), #W.m.bank, #W.stores))
end

local state, last = "idle", nil
local function report()
  rednet.broadcast({ id = os.getComputerID(), label = os.getComputerLabel(), role = "works", state = state,
    machines = W.ready(), last = last, log = W.notes }, W.STATUS)
end
local function ready()
  rednet.broadcast({ type = "foundry_ready", machines = W.ready(), power = { ok = true, fuel = 64 }, works = true }, W.JOB)
end

local function jobs()
  ready()
  local lastReady = os.clock()
  while true do
    local id, msg = rednet.receive(W.JOB, 30)
    if type(msg) == "table" and msg.type == "foundry_hello" then ready() end
    if type(msg) == "table" and msg.type == "foundry_job" and msg.forId == os.getComputerID() and type(msg.job) == "table" then
      rednet.send(id, { type = "foundry_ack", n = msg.n }, W.JOB)
      state = "working: " .. tostring(msg.job.kind) .. " " .. tostring(msg.job.item or "")
      report()
      W.scan(wired.getNamesRemote())
      local ok, why, made = W.run({ kind = msg.job.kind, item = msg.job.item, n = tonumber(msg.job.n) })
      last = { kind = msg.job.kind, item = msg.job.item, ok = ok, why = why, made = made }
      note((ok and "Done: " or "Failed: ") .. tostring(msg.job.kind) .. " " .. tostring(msg.job.item or "")
        .. (why and (" (" .. why .. ")") or ""))
      rednet.send(id, { type = "foundry_done", n = msg.n, ok = ok, why = why, made = made }, W.JOB)
      state = "idle"
    end
    if os.clock() - lastReady > 300 then
      lastReady = os.clock()
      W.scan(wired.getNamesRemote())
      ready()
      report()
    end
  end
end

local function orders()
  while true do
    local _, _, ch, _, msg = os.pullEvent("modem_message")
    if ch == W.CHANNEL and type(msg) == "table" and msg.type == "cmd" and type(msg.cmd) == "table" and msg.cmd.cmd == "reboot" then
      local t = msg.cmd.target
      if t == "all" or t == os.getComputerLabel() or t == os.getComputerID()
        or (swarm and swarm.forMe and swarm.forMe(msg.cmd)) then
        sleep(1)
        os.reboot()
      end
    end
  end
end

-- The ME desk (docs/ae2-factory.html): with an ME Bridge beside this computer,
-- the foundry is ME's (pattern providers behind every machine), so this
-- computer no longer takes foundry jobs. It tells the factory what ME holds
-- and starts crafts ordered from outside (order: me crafter1 craft=<id> n=<n>,
-- or ask=<id> to add an item to the watch list).
local bridge
for _, name in ipairs(peripheral.getNames()) do
  local t = tostring(peripheral.getType(name) or ""):lower()
  if t:find("bridge", 1, true) then bridge = peripheral.wrap(name) end
end
local function meDesk()
  local watch = { "alltheores:steel_ingot", "minecraft:iron_ingot", "ae2:certus_quartz_crystal",
    "ae2:charged_certus_quartz_crystal", "ae2:fluix_crystal", "ae2:silicon", "ae2:logic_processor",
    "ae2:calculation_processor", "ae2:engineering_processor", "mekanism:basic_control_circuit",
    "mekanism:alloy_infused", "mekanism:alloy_reinforced", "mekanism:alloy_atomic",
    "mekanism:ingot_refined_obsidian", "minecraft:lava_bucket" }
  local lastOrder, log = nil, {}
  local craftEvents = {}        -- (filled by the listener below)
  local answer                  -- the last `call` order's result
  -- Stock rules: ME is asked for the difference when an item falls under its
  -- target (one order per item at a time, small batches, only with a CPU
  -- free). order: me crafter1 rule=<id> n=<target> (n=0 drops the rule)
  local RULES_FILE = ".me_rules"
  local rules = { ["minecraft:lava_bucket"] = 64, ["alltheores:steel_ingot"] = 128,
    ["ae2:logic_processor"] = 16, ["ae2:calculation_processor"] = 16, ["ae2:engineering_processor"] = 16,
    ["mekanism:basic_control_circuit"] = 32 }
  if fs.exists(RULES_FILE) then
    local h = fs.open(RULES_FILE, "r")
    local t = textutils.unserialize(h.readAll() or "")
    h.close()
    if type(t) == "table" then rules = t end
  end
  local asked = {}              -- id -> { at, had }
  local function call(m, ...)
    if type(bridge[m]) ~= "function" then return nil, "no " .. m end
    local r = table.pack(pcall(bridge[m], ...))
    if not r[1] then return nil, tostring(r[2]) end
    return r[2], r[3]
  end
  local function count(id)
    local it = call("getItem", { name = id })
    if type(it) ~= "table" then return nil end
    return tonumber(it.count or it.amount) or 0
  end
  local function tell()
    local stock = {}
    for _, id in ipairs(watch) do stock[id] = count(id) end
    local cpus = call("getCraftingCPUs")
    local busy = 0
    for _, c in ipairs(type(cpus) == "table" and cpus or {}) do if c.isBusy then busy = busy + 1 end end
    local methods = {}
    for k in pairs(bridge) do methods[#methods + 1] = k end
    table.sort(methods)
    -- what each CPU is doing, and the lava ME holds
    local tasks = {}
    local okT, list = pcall(function() return bridge.getCraftingTasks() end)
    for i, t in ipairs(okT and type(list) == "table" and list or {}) do
      if i <= 6 then tasks[#tasks + 1] = textutils.serialize(t, { compact = true }):sub(1, 260) end
    end
    local lava = call("getFluid", { name = "minecraft:lava" })
    rednet.broadcast({ type = "me_report", me = { stock = stock, last = lastOrder, log = log, tasks = tasks, rules = rules, events = craftEvents, answer = answer,
      lava = type(lava) == "table" and (lava.count or lava.amount) or nil,
      free = call("getAvailableItemStorage"), freeBarrels = call("getAvailableExternalItemStorage"),
      energy = call("getEnergyStorage") or call("getStoredEnergy"), usage = call("getEnergyUsage"),
      cpus = type(cpus) == "table" and #cpus or nil, busy = busy,
      methods = #log == 0 and table.concat(methods, " ") or nil } }, W.JOB)
  end
  local function freeCpu()
    local cpus = call("getCraftingCPUs")
    local free = 0
    for _, c in ipairs(type(cpus) == "table" and cpus or {}) do if not c.isBusy then free = free + 1 end end
    return free
  end
  local function keepStock()
    local free = freeCpu()
    for id, target in pairs(rules) do
      if free <= 1 then break end                  -- (one CPU is always left for orders by hand)
      local have = count(id)
      local a = asked[id]
      -- (an order is open until what it asked for has arrived, or 15 minutes)
      if a and (have == nil or have >= a.had + a.n or os.clock() - a.at > 900) then asked[id], a = nil, nil end
      if have and have < target and not a then
        local n = math.min(target - have, 16)
        local ok, err = call("craftItem", { name = id, count = n })
        asked[id] = { at = os.clock(), had = have, n = n }
        local line = ("stock: %s %d of %d, ordered %d: %s"):format(id, have, target, n, ok and "started" or ("refused " .. tostring(err)))
        log[#log + 1] = line
        while #log > 8 do table.remove(log, 1) end
        note(line)
        if ok then free = free - 1 end
      end
    end
  end
  note("ME desk: bridge found. Reporting to the factory.")
  tell()
  local lastTell = os.clock()
  -- (orders are taken by a listener of their own: a bridge call waits on an
  -- event, and an order arriving meanwhile would be thrown away)
  local inbox = {}
  local events = craftEvents    -- what the bridge said about its crafting jobs (the last 6)
  local function listen()
    while true do
      local ev = table.pack(os.pullEvent())
      if ev[1] == "rednet_message" and ev[4] == W.JOB then
        local msg = ev[3]
        if type(msg) == "table" and msg.type == "me_order" then inbox[#inbox + 1] = msg end
      elseif type(ev[1]) == "string" and ev[1]:lower():find("craft", 1, true) then
        local parts = {}
        for i = 1, math.min(ev.n, 5) do
          local v = ev[i]
          parts[#parts + 1] = type(v) == "table" and textutils.serialize(v, { compact = true }):sub(1, 120) or tostring(v)
        end
        events[#events + 1] = table.concat(parts, " | "):sub(1, 240)
        while #events > 14 do table.remove(events, 1) end
      end
    end
  end
  local function work()
  while true do
    if #inbox == 0 then sleep(2) end
    local msg = table.remove(inbox, 1)
    if type(msg) == "table" and msg.type == "me_order" then
      local line
      if type(msg.call) == "string" then
        -- me crafter1 call=<bridge method> [arg=<item id>] [find=<text>]: what the bridge answers
        -- (arg=<item id> is passed as { name = <id> }: cancelCraftingTasks, getItem, isCraftable)
        local res, err
        if type(msg.arg) == "string" then res, err = call(msg.call, { name = msg.arg }) else res, err = call(msg.call) end
        local out = {}
        if type(res) == "table" and msg.find == "*" then      -- the whole answer, as text
          out[1] = textutils.serialize(res, { compact = true }):gsub("prototype=%b{},?", ""):gsub("tags=%b{},?", ""):sub(1, 7000)
        elseif type(res) == "table" then
          for k, v in pairs(res) do
            local name = type(v) == "table" and tostring(v.name or v.id or k) or tostring(v)
            local text = type(v) == "table" and textutils.serialize(v, { compact = true }) or tostring(v)
            if not msg.find or text:lower():find(tostring(msg.find):lower(), 1, true) then
              out[#out + 1] = msg.find and text:gsub("prototype=%b{},?", ""):sub(1, 900) or name
            end
            if #out >= (msg.find and 4 or 12) then break end
          end
        else
          out[1] = tostring(res) .. " " .. tostring(err)
        end
        answer = { call = msg.call, find = msg.find, n = #out, out = out }
        line = "call " .. msg.call .. (msg.find and (" find " .. msg.find) or "") .. ": " .. #out
      elseif type(msg.rule) == "string" then
        local n = math.floor(tonumber(msg.n) or 0)
        rules[msg.rule] = n > 0 and n or nil
        local h = fs.open(RULES_FILE, "w")
        h.write(textutils.serialize(rules))
        h.close()
        line = "rule " .. msg.rule .. " = " .. tostring(rules[msg.rule])
      elseif type(msg.ask) == "string" then
        local seen = false
        for _, id in ipairs(watch) do if id == msg.ask then seen = true end end
        if not seen then watch[#watch + 1] = msg.ask end
        line = "watching " .. msg.ask
      elseif type(msg.craft) == "string" then
        local n = math.max(1, math.floor(tonumber(msg.n) or 1))
        local before = count(msg.craft)
        -- (by name alone the bridge picks a stored item of that name, and one
        -- with a label or an id on it is "not craftable": ask for the very
        -- item the patterns make: by its fingerprint, or as the plain item)
        local filter, can = { name = msg.craft, count = n }, false
        local list = call("getCraftableItems")
        for _, it in ipairs(type(list) == "table" and list or {}) do
          if type(it) == "table" and it.name == msg.craft then
            can = true
            if it.fingerprint then filter.fingerprint = it.fingerprint
            elseif type(it.components) ~= "table" or next(it.components) == nil then filter.components = "{}" end
            break
          end
        end
        local ok, err = call("craftItem", filter)
        line = ("craft %d %s: %s%s (craftable: %s, had %s)"):format(n, msg.craft, ok and "started" or "refused",
          err and (" " .. tostring(err)) or "", tostring(can), tostring(before))
        local seen = false
        for _, id in ipairs(watch) do if id == msg.craft then seen = true end end
        if not seen then watch[#watch + 1] = msg.craft end
      end
      if line then
        local okD, clock = pcall(os.date, "!%H:%M")
        lastOrder = (okD and clock .. " " or "") .. line
        log[#log + 1] = lastOrder
        while #log > 8 do table.remove(log, 1) end
        note(line)
        if #inbox == 0 then
          tell()
          lastTell = os.clock()
        end
      end
    end
    if os.clock() - lastTell > 60 then
      lastTell = os.clock()
      pcall(keepStock)
      tell()
    end
  end
  end
  parallel.waitForAny(listen, work)
end

if not os.getComputerLabel() then os.setComputerLabel("Works") end
if bridge then parallel.waitForAny(meDesk, orders) else parallel.waitForAny(jobs, orders) end
