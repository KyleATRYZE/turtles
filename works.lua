-- works.lua : the foundry on the cable (docs/foundry-build.html). Runs on
-- the works computer in the foundry floor, role "works".
--
-- Every machine on the plinth sits on a full-block wired modem in the floor
-- (its BOTTOM face), on the same cable as the store. Items go from the store
-- straight into a machine by its network name and the results come straight
-- back: no turtle carries anything. The infuser has a second modem on its
-- south (RIGHT) face for the infusion items.
--
-- It speaks the factory's foundry protocol (factory.lua "the foundry"), the
-- one DropIt's foundry.lua speaks: it says foundry_ready with its machines,
-- takes foundry_job (ore, the infuser's makes, enrich, smelt), answers
-- foundry_ack and foundry_done with what it made. Messages go over the
-- cable (Crafty listens on its wired modem too); reboot orders come from
-- Crafty on the rack channel.
--
-- If the store cannot push into a Mekanism machine by name (Crafty's
-- "probe" order says), this computer is not used: the fallback is the
-- piped line with its inbox and outbox barrels (docs/mekanism-plan.md).

local okSwarm, swarm = pcall(require, "swarm")
if not okSwarm then swarm = nil end

local W = {}
W.JOB = "swarm_job"
W.STATUS = "swarm"
W.CHANNEL = 4711                     -- factory.lua K.RACK_CHANNEL (reboot orders)
W.FACE = "BOTTOM"                    -- the face on the floor modem
W.EXTRA_FACE = "RIGHT"               -- the infuser's second modem (south, facing west)
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

function W.scan(names)
  W.m = { bank = {} }
  W.stores = {}
  local infusers = {}
  for _, name in ipairs(names) do
    if name:find("^mekanism:enrichment_chamber") then W.m.chamber = W.m.chamber or name
    elseif name:find("^mekanism:energized_smelter") then
      if not W.m.smelter then W.m.smelter = name else W.m.bank[#W.m.bank + 1] = name end
    elseif name:find("^mekanism:metallurgic_infuser") then infusers[#infusers + 1] = name
    elseif name:find("^mekanism:crusher") then W.m.crusher = W.m.crusher or name
    elseif W.isStore(name) then W.stores[#W.stores + 1] = name end
  end
  table.sort(W.stores, function(a, b)
    local ca, cb = a:find("controller", 1, true) ~= nil, b:find("controller", 1, true) ~= nil
    if ca ~= cb then return ca end
    return a < b
  end)
  table.sort(infusers)
  W.m.infuser, W.m.extra = infusers[1], infusers[2]
  return W.m
end

-- The sides: the floor modem's face takes items in and gives results out;
-- the chamber pushes its dust on north (LEFT) into the smelter; the
-- infuser's second modem is its infusion face.
function W.setup()
  local function io(name)
    if not name then return end
    local ok = pcall(peripheral.call, name, "setMode", "ITEM", W.FACE, "INPUT_OUTPUT")
    if not ok then
      call(name, "setMode", "ITEM", W.FACE, "INPUT")
      note(name .. ": no INPUT_OUTPUT; results by ejection only")
    end
    call(name, "setRedstoneMode", "IGNORED")
  end
  io(W.m.chamber)
  io(W.m.smelter)
  io(W.m.crusher)
  for _, b in ipairs(W.m.bank) do io(b) end
  io(W.m.infuser)
  if W.m.chamber and W.m.smelter then
    call(W.m.chamber, "setMode", "ITEM", "LEFT", "OUTPUT")
    call(W.m.smelter, "setMode", "ITEM", "RIGHT", "INPUT")
  end
  if W.m.infuser then call(W.m.infuser, "setMode", "ITEM", W.EXTRA_FACE, "EXTRA") end
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
  local machine = W.m.chamber
  if not machine then return false, "no enrichment chamber on the cable" end
  if smelt and not W.m.smelter then smelt = false end
  call(machine, "setEjecting", "ITEM", smelt and true or false)
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
  local list = { W.m.smelter }
  for _, b in ipairs(W.m.bank) do list[#list + 1] = b end
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
    if n > 0 then have = have + W.put(W.m.extra or W.m.infuser, it[1], n) * it[2] end
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
  if W.m.chamber then call(W.m.chamber, "setEjecting", "ITEM", true) end
  return ok, why, W.made
end

function W.ready()
  return { chamber = W.m.chamber and true or nil, smelter = W.m.smelter and true or nil,
    infuser = W.m.infuser and true or nil, crusher = W.m.crusher and true or nil,
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
W.scan(wired.getNamesRemote())
W.setup()
note(("Machines: chamber %s, smelter %s, infuser %s, bank %d, stores %d."):format(
  tostring(W.m.chamber), tostring(W.m.smelter), tostring(W.m.infuser), #W.m.bank, #W.stores))

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
      if t == "all" or t == os.getComputerLabel() or t == os.getComputerID() then
        sleep(1)
        os.reboot()
      end
    end
  end
end

if not os.getComputerLabel() then os.setComputerLabel("Works") end
parallel.waitForAny(jobs, orders)
