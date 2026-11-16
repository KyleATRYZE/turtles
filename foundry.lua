-- foundry.lua : the Mekanism line in the foundry bay, run by a helper.
--
-- helper.lua loads this and hands it its own tools (walking, fetching,
-- reporting) as `env`. The operator (SteelyDan) then works here whenever it
-- has no other job: it takes jobs from the factory over rednet, or from a
-- remote order, fetches what a job needs with the ordinary materials
-- request, feeds the machines, powers them with redstone dust, waits, and
-- hands what they made back in on the launch pad.
--
-- What is known about the machines (learned on the lab bench):
--   * a machine a turtle places FACES THE TURTLE (getDirection says so);
--     nothing here assumes it: the facing is read from the machine
--   * its sides are named from the front: LEFT is the next face clockwise
--     seen from above (facing south: the west face), RIGHT the other way
--   * setMode("ITEM", side, mode) says what a side does: INPUT, OUTPUT,
--     ENERGY (the energy slot: redstone dust dropped there is power) or
--     EXTRA (the infusion item); setEjecting("ITEM", true) pushes results
--     into whatever stands against an OUTPUT side
--   * an input slot can only be emptied by running the machine, and a
--     result slot holding something else stalls it: every job starts by
--     letting the machine finish and taking out what is in it

local M = {}

M.STATE_FILE = ".foundry"
M.print = print           -- (the helper puts its own, logged, print here)
M.REDSTONE = "minecraft:redstone"

-- the building the line stands in (its corner in the world, and the plans
-- the helper finds its way by)
M.SITE = { ox = -4448, oy = 71, oz = 1518, shell = "factory_asfit2", plan = "factory_foundryfloor" }

-- the first infuser, on the bench outside: stand here, facing this way, to
-- take it down (it stands at -4452 74 1533)
M.BENCH = { x = -4453, y = 74, z = 1533, face = 0, item = "mekanism:metallurgic_infuser" }

-- The machines, in the building's own coordinates, along the east side of
-- the operator's lane (x = 40). lane = the side the operator places and
-- sets them up from. use = which face does what for the operator ("top", or
-- a compass side); also = sides set for the machines' own sake (the chamber
-- pushes its dust north into the smelter). perOp = redstone dust of power
-- per item worked: a job is 10 kJ and a dust is 10 kJ, and a little is lost.
--
-- The chamber and smelter stand as they were first run by hand (9 raw iron
-- gave 12 ingots): both facing west, redstone in by the front (the lane),
-- ore in by the chamber's top, ingots out by the smelter's north side.
M.ORDER = { "chamber", "smelter", "infuser" }
M.MACHINES = {
  chamber = { item = "mekanism:enrichment_chamber", x = 41, y = 1, z = 12, lane = "west",
    use = { energy = "west", input = "top", output = "south" },
    also = { north = "OUTPUT" }, eject = true, perOp = 1.1 },
  smelter = { item = "mekanism:energized_smelter", x = 41, y = 1, z = 11, lane = "west",
    use = { energy = "west", input = "top", output = "north" },
    also = { south = "INPUT" }, perOp = 1.1 },
  infuser = { item = "mekanism:metallurgic_infuser", x = 41, y = 1, z = 15, lane = "west",
    use = { energy = "west", input = "top", extra = "south", output = "north" }, perOp = 1.1 },
}

-- What the infuser makes: each pass is one trip through it.
M.INFUSE = {
  steel = { makes = "alltheores:steel_dust", passes = {
    { input = "minecraft:iron_ingot", gas = "carbon", mb = 10 },
    { input = "mekanism:enriched_iron", gas = "carbon", mb = 10 } } },
  circuit = { makes = "mekanism:basic_control_circuit", passes = {
    { input = "alltheores:osmium_ingot", gas = "redstone", mb = 20 } } },
  alloy = { makes = "mekanism:alloy_infused", passes = {
    { input = "minecraft:copper_ingot", gas = "redstone", mb = 10 } } },
}
-- what fills the infusion tank, best first: { item, mB each }. ask = what
-- the factory is asked for (then the next one, if it has none).
M.GAS = {
  carbon = { name = "mekanism:carbon", ask = { "minecraft:charcoal", "minecraft:coal" },
    items = { { "mekanism:enriched_carbon", 80 }, { "minecraft:charcoal", 10 }, { "minecraft:coal", 10 } } },
  redstone = { name = "mekanism:redstone", ask = { "minecraft:redstone" },
    items = { { "mekanism:enriched_redstone", 80 }, { "minecraft:redstone", 10 } } },
}
M.MAX_BATCH = 48          -- most items per job (the result slot holds one stack)

local DIRS = {
  [0] = { x = 1, z = 0 }, [1] = { x = 0, z = 1 },
  [2] = { x = -1, z = 0 }, [3] = { x = 0, z = -1 },
}
local CODE = { east = 0, south = 1, west = 2, north = 3 }
local FACE = { [0] = "east", [1] = "south", [2] = "west", [3] = "north" }
local ROLE_MODE = { energy = "ENERGY", input = "INPUT", extra = "EXTRA", output = "OUTPUT" }
local REACH = { "top", "west", "north", "south", "east" }

---------------------------------------------------------------- state

function M.load()
  local s
  if fs.exists(M.STATE_FILE) then
    local h = fs.open(M.STATE_FILE, "r")
    s = textutils.unserialize(h.readAll())
    h.close()
  end
  if type(s) ~= "table" then s = {} end
  s.queue, s.m, s.notes = s.queue or {}, s.m or {}, s.notes or {}
  return s
end

function M.save(s)
  local h = fs.open(M.STATE_FILE, "w")
  h.write(textutils.serialize(s))
  h.close()
end

local function note(s, text)
  local ok, clock = pcall(os.date, "!%H:%M")
  s.notes[#s.notes + 1] = (ok and clock .. " " or "") .. tostring(text):sub(1, 150)
  while #s.notes > 12 do table.remove(s.notes, 1) end
  M.save(s)
  M.print(text)
end

-- A remote order:
--   foundry ore=minecraft:raw_iron n=48   ore through the chamber and smelter
--   foundry enrich=minecraft:redstone n=16   the chamber only
--   foundry make=steel n=16               the infuser (steel, circuit, alloy)
--   foundry job=setup | job=move_infuser  find or place the machines; bring
--                                         the infuser in from the bench
--   foundry on=1 / on=0                   work the foundry / an ordinary helper
--   foundry clear=1                       drop the jobs in hand
--   foundry reset=1                       forget what is set up (look again)
-- (job=ore item=... and job=steel are the same things spelt out.)
local function fullName(item)
  if type(item) ~= "string" or item == "" then return nil end
  return item:find(":", 1, true) and item or ("minecraft:" .. item)
end

function M.order(cmd)
  local s = M.load()
  if cmd.on ~= nil then s.on = not (cmd.on == 0 or cmd.on == "0" or cmd.on == false) end
  if cmd.clear then s.queue, s.cur = {}, nil end
  if cmd.reset then s.m, s.bench, s.ready = {}, nil, nil end
  local kind, item = cmd.job, cmd.item
  if cmd.ore then kind, item = "ore", cmd.ore end
  if cmd.enrich then kind, item = "enrich", cmd.enrich end
  if cmd.make then kind = cmd.make end
  if type(kind) == "string" then
    s.on = true
    s.queue[#s.queue + 1] = { kind = kind, n = tonumber(cmd.n), item = fullName(item) }
  end
  M.save(s)
  return s
end

-- for the status report
function M.info()
  local s = M.load()
  if not s.on then return nil end
  local cur = s.cur
  local placed = {}
  for name, m in pairs(s.m) do if m.ok then placed[#placed + 1] = name end end
  table.sort(placed)
  return {
    ready = s.ready or false, machines = table.concat(placed, " "),
    job = cur and ("%s x%s (%s)"):format(tostring(cur.kind), tostring(cur.n or 1), tostring(cur.stage or "starting")) or nil,
    queued = #s.queue, last = s.last, notes = s.notes,
  }
end

---------------------------------------------------------------- small tools

local function count(name)
  local n = 0
  for slot = 1, 16 do
    local d = turtle.getItemDetail(slot)
    if d and d.name == name then n = n + d.count end
  end
  return n
end

local function findSlot(name)
  for slot = 1, 16 do
    local d = turtle.getItemDetail(slot)
    if d and d.name == name then return slot end
  end
end

local function aboard()
  local inv, total = {}, 0
  for slot = 1, 16 do
    local d = turtle.getItemDetail(slot)
    if d then inv[d.name], total = (inv[d.name] or 0) + d.count, total + d.count end
  end
  return inv, total
end

local function call(side, method, ...)
  local ok, v = pcall(peripheral.call, side, method, ...)
  if ok then return v end
end

local function stack(v) return type(v) == "table" and tonumber(v.count) or 0 end

-- the name of a face from the machine's own point of view
local function relative(face, f)
  if face == "top" then return "TOP" elseif face == "bottom" then return "BOTTOM" end
  local turn = (CODE[face] - f) % 4
  return turn == 0 and "FRONT" or turn == 1 and "LEFT" or turn == 2 and "BACK" or "RIGHT"
end
M.relative = relative

-- where to stand to work a face: x, y, z, the way to look (nil: down), the
-- suffix of the turtle's verbs there, and where the machine is as a peripheral
local function station(m, face)
  if face == "top" then return m.x, m.y + 1, m.z, nil, "Down", "bottom" end
  local d = CODE[face]
  return m.x + DIRS[d].x, m.y, m.z + DIRS[d].z, (d + 2) % 4, "", "front"
end
M.station = station

---------------------------------------------------------------- at the machines

local function stand(env, s, name, role)
  local m = M.MACHINES[name]
  local face = role and s.m[name].faces[role] or m.lane
  local x, y, z, d, sfx, side = station(m, face)
  if not env.walk(x, y, z) then
    error(("cannot get to the %s (%s side)"):format(name, face), 0)
  end
  if d then env.face(d) end
  local seen, data = turtle["inspect" .. sfx]()
  if not (seen and type(data) == "table" and data.name == m.item) then
    s.m[name] = nil                            -- (it is looked for again next time)
    M.save(s)
    error(("no %s where it should be"):format(name), 0)
  end
  return sfx, side
end

-- up to n of an item into a machine by the side that does `role`
local function put(env, s, name, role, item, n)
  local sfx = stand(env, s, name, role)
  local moved = 0
  for slot = 1, 16 do
    if moved >= n then break end
    local d = turtle.getItemDetail(slot)
    if d and d.name == item then
      turtle.select(slot)
      local before = turtle.getItemCount(slot)
      turtle["drop" .. sfx](math.min(n - moved, before))
      local went = before - turtle.getItemCount(slot)
      moved = moved + went
      if went == 0 then break end                -- it takes no more
    end
  end
  turtle.select(1)
  return moved
end

local function suckAll(sfx)
  local _, before = aboard()
  for _ = 1, 8 do
    if not turtle["suck" .. sfx]() then break end
  end
  local _, after = aboard()
  return after - before
end

local function take(env, s, name)
  return suckAll((stand(env, s, name, "output")))
end

-- redstone dust into the energy slot: enough for `ops` items, less what is
-- waiting there already
local function power(env, s, name, ops)
  local have = count(M.REDSTONE)
  if have == 0 then return 0 end
  local _, side = stand(env, s, name, "energy")
  local waiting = stack(call(side, "getEnergyItem"))
  local n = math.min(have, math.max(0, math.ceil(ops * M.MACHINES[name].perOp) + 2 - waiting))
  if n == 0 then return 0 end
  return put(env, s, name, "energy", M.REDSTONE, n)
end

-- Wait by the machine until it has worked through what is in it (results
-- taken as they pile up; or, when they are left for the next machine, wait
-- at the input side: a machine that pushes its results out would push them
-- into a turtle standing at a result side). The energy slot is kept topped
-- up while there is dust on board. Returns what was taken and what is still
-- in the input.
M.STALL = 60              -- seconds without a change before giving up on a machine
local function drain(env, s, name, leave)
  local where = leave and "input" or "output"
  local sfx, side = stand(env, s, name, where)
  local got, last, changed, boosts, started = 0, nil, os.clock(), 0, os.clock()
  local left, boosted = 0, -100
  while true do
    left = stack(call(side, "getInput"))
    local out = stack(call(side, "getOutput"))
    if not leave and out >= 32 then got = got + suckAll(sfx) end
    if left == 0 then break end
    if left ~= last then last, changed = left, os.clock() end
    local e, max = call(side, "getEnergy"), call(side, "getMaxEnergy")
    local low = type(e) ~= "number" or type(max) ~= "number" or e < max / 4
    local stalled = os.clock() - changed > M.STALL
    if low and count(M.REDSTONE) > 0 and boosts < 16 and os.clock() - boosted > 9
      and stack(call(side, "getEnergyItem")) == 0 then
      -- the dust has run out (the slot holds one stack): more
      boosts, boosted = boosts + 1, os.clock()
      put(env, s, name, "energy", M.REDSTONE, math.min(16, math.ceil(left * M.MACHINES[name].perOp) + 1))
      sfx, side = stand(env, s, name, where)
      changed = os.clock()
    elseif stalled then
      note(s, ("the %s has stopped with %d still in it"):format(name, left))
      break
    end
    if os.clock() - started > 1800 then break end
    sleep(3)
    env.tick("foundry: waiting for the " .. name)
  end
  if not leave then got = got + suckAll(sfx) end
  return got, left
end

---------------------------------------------------------------- setting up

-- Read which way the machine faces, set its sides, and note which face the
-- operator uses for what (checked against what the machine says afterwards:
-- a side that would not be set is looked for elsewhere).
local function configure(env, s, name)
  local m = M.MACHINES[name]
  local side = "front"
  local dir = call(side, "getDirection")
  local f = type(dir) == "string" and CODE[dir:lower()]
  if not f then
    f = CODE[m.lane]
    note(s, ("the %s does not say which way it faces: taking it to face me"):format(name))
  end
  local want = {}
  for role, face in pairs(m.use) do want[face] = ROLE_MODE[role] end
  for face, mode in pairs(m.also or {}) do want[face] = mode end
  for face, mode in pairs(want) do
    local rel = relative(face, f)
    if call(side, "getMode", "ITEM", rel) ~= mode then
      local ok, err = pcall(peripheral.call, side, "setMode", "ITEM", rel, mode)
      if not ok then note(s, ("%s: %s side would not be set to %s (%s)"):format(name, face, mode, tostring(err))) end
    end
  end
  if m.eject then
    local ok, err = pcall(peripheral.call, side, "setEjecting", "ITEM", true)
    if not ok then note(s, name .. ": auto-eject would not be set (" .. tostring(err) .. ")") end
  end
  local modes = {}
  for _, face in ipairs(REACH) do modes[face] = call(side, "getMode", "ITEM", relative(face, f)) end
  local faces = {}
  for role, face in pairs(m.use) do
    local mode = ROLE_MODE[role]
    if modes[face] == mode or modes[face] == nil then
      faces[role] = face
    else
      for _, other in ipairs(REACH) do
        if modes[other] == mode then faces[role] = other break end
      end
    end
    if not faces[role] then return false, ("the %s has no %s side I can use"):format(name, role) end
  end
  s.m[name] = { ok = true, f = f, faces = faces }
  note(s, ("%s ready (facing %s)"):format(name, FACE[f]))
  return true
end

-- The machine on its spot: found, or placed from what is on board, then set
-- up. "need" = there is none there and none on board.
local function ensure(env, s, name)
  local m = M.MACHINES[name]
  local x, y, z, d = station(m, m.lane)
  if not env.walk(x, y, z) then return false, "cannot get to the " .. name .. "'s place" end
  env.face(d)
  local seen, data = turtle.inspect()
  local there = seen and type(data) == "table" and data.name or nil
  if not there then
    local slot = findSlot(m.item)
    if not slot then return false, "need" end
    turtle.select(slot)
    local ok, err = turtle.place()
    turtle.select(1)
    if not ok then return false, ("the %s would not go down: %s"):format(name, tostring(err)) end
    there = m.item
    sleep(0.5)                               -- (a moment for it to answer as a peripheral)
  end
  if there ~= m.item then
    env.block(m.x, m.y, m.z)
    return false, ("something else stands in the %s's place: %s"):format(name, there)
  end
  env.block(m.x, m.y, m.z)
  return configure(env, s, name)
end

-- Take the infuser down from the bench outside (it keeps what is in it).
local function fromBench(env, s)
  local b = M.BENCH
  if findSlot(b.item) then return true end
  if env.inside() then env.leave() end
  if not env.flyTo(b.x, b.y, b.z) then
    note(s, "could not get down to the bench outside")
    env.rise()
    return false
  end
  env.face(b.face)
  local seen, data = turtle.inspect()
  if seen and type(data) == "table" and data.name == b.item then
    turtle.select(1)
    turtle.dig()
    s.bench = findSlot(b.item) and "moved" or "stuck"
  else
    s.bench = "gone"
  end
  note(s, "the infuser on the bench outside: " .. s.bench)
  env.rise()
  return s.bench == "moved"
end

local function announce(env, s)
  local machines = {}
  for name, m in pairs(s.m) do machines[name] = m.ok or nil end
  pcall(rednet.broadcast, { type = "foundry_ready", ready = s.ready or false, machines = machines }, env.PROTOCOL)
end

-- names: the machines wanted. opts.fetch: one that is not there is asked of
-- the factory (which makes one if it can). opts.bench: the infuser is taken
-- down from the bench outside first (always, the first time a job needs it).
local function setup(env, s, names, opts)
  opts = opts or {}
  local need, failed = {}, nil
  for _, name in ipairs(names) do
    local ok, why = ensure(env, s, name)
    if not ok then
      if why == "need" then need[#need + 1] = name else failed = why note(s, why) end
    end
  end
  if #need > 0 and (opts.fetch or opts.bench) then
    local want = {}
    for _, name in ipairs(need) do
      local item = M.MACHINES[name].item
      -- the infuser already made stands on the bench outside
      if name == "infuser" and (opts.bench or not s.bench) then fromBench(env, s) end
      if opts.fetch and not findSlot(item) then want[#want + 1] = { item, 1 } end
    end
    if #want > 0 then
      if env.inside() then env.leave() end
      env.fetch(want)
    end
    for _, name in ipairs(need) do
      local ok, why = ensure(env, s, name)
      if not ok then
        failed = why == "need" and ("no " .. name .. " to be had") or why
        note(s, failed)
      end
    end
  elseif #need > 0 then
    note(s, "not in the bay yet: " .. table.concat(need, ", "))
  end
  local all = true
  for _, name in ipairs(M.ORDER) do
    if not (s.m[name] and s.m[name].ok) then all = false end
  end
  s.ready = all or nil
  M.save(s)
  announce(env, s)
  return { ok = not failed, why = failed }
end

---------------------------------------------------------------- the jobs

-- Fill the infusion tank for `mb` of work. Returns how much there is.
local function fillTank(env, s, kind, mb)
  local gas = M.GAS[kind]
  local _, side = stand(env, s, "infuser", "extra")
  local tank, have = call(side, "getInfuseType"), 0
  if type(tank) == "table" then
    have = tonumber(tank.amount) or 0
    if have > 0 and tank.name ~= gas.name then       -- left from another recipe
      call(side, "dumpInfuseType")
      have = 0
    end
  end
  for _, it in ipairs(gas.items) do
    if have >= mb then break end
    local n = math.min(count(it[1]), math.ceil((mb - have) / it[2]))
    if n > 0 then have = have + put(env, s, "infuser", "extra", it[1], n) * it[2] end
  end
  return have
end

local function infuse(env, s, job)
  local recipe = M.INFUSE[job.kind]
  drain(env, s, "infuser")                 -- (finish and take whatever was left in it)
  for _, pass in ipairs(recipe.passes) do
    local n = count(pass.input)
    if n > 0 then
      local mb = fillTank(env, s, pass.gas, n * pass.mb)
      n = math.min(n, math.floor(mb / pass.mb))
      if n == 0 then
        job.fail = "no " .. pass.gas .. " for the infuser"
        return
      end
      power(env, s, "infuser", n)
      if put(env, s, "infuser", "input", pass.input, n) == 0 then
        job.fail = "the infuser would not take " .. pass.input:gsub("^.*:", "")
        return
      end
      local _, left = drain(env, s, "infuser")
      if left > 0 then job.fail = "the infuser stopped part way" end
    end
  end
end

-- how many results each item of ore gives (raw ore: three make four dust)
local function oreYield(item)
  if item:find(":raw_", 1, true) and not item:find("_block", 1, true) then return 3, 4 / 3 end
  return 1, 2
end

-- What is in the chamber, worked and (smelt) taken on through the smelter.
-- While the chamber works the operator waits at its input side: it pushes
-- its dust north into the smelter, and would push it into a turtle standing
-- at its other result side.
local function settle(env, s, job, smelt)
  local _, left = drain(env, s, "chamber", smelt)
  if left > 0 then job.fail = "the chamber stopped part way" end
  sleep(3)                                 -- (the last of it moving on to the smelter)
  if not smelt then
    take(env, s, "chamber")
    return
  end
  -- anything the chamber did not push on itself is carried over
  local before = aboard()
  take(env, s, "chamber")
  for name, c in pairs((aboard())) do
    local gained = c - (before[name] or 0)
    if gained > 0 then put(env, s, "smelter", "input", name, gained) end
  end
  _, left = drain(env, s, "smelter")
  if left > 0 then job.fail = "the smelter stopped part way" end
end

-- Ore through the Enrichment Chamber and on through the Energized Smelter
-- (smelt = false: the chamber only, for enriched redstone or carbon).
local function refine(env, s, job, smelt)
  local item = job.item
  -- whatever was left in the machines is worked off first, the same way (an
  -- input slot holding something else takes nothing new)
  local _, side = stand(env, s, "chamber", "input")
  local was = call(side, "getInput")
  local old, oldDust = stack(was), 0
  if smelt then
    _, side = stand(env, s, "smelter", "output")
    oldDust = stack(call(side, "getInput"))
  end
  if old > 0 or oldDust > 0 then
    local oldLot, oldYield = oreYield(type(was.name) == "string" and was.name or item)
    if old > 0 then power(env, s, "chamber", old / oldLot) end
    if smelt then power(env, s, "smelter", oldDust + math.ceil(old * oldYield)) end
    settle(env, s, job, smelt)
    job.fail = nil                         -- (if it is still stuck the new ore will not go in: said then)
  elseif smelt then
    drain(env, s, "smelter")               -- (results left waiting in it)
  end
  local n = count(item)
  local lot, yield = oreYield(item)
  n = n - n % lot
  if n == 0 then job.fail = "no " .. item:gsub("^.*:", "") .. " on board" return end
  -- no more ore goes in than there is redstone to see through both machines
  -- (ore left in a machine without power blocks the next job)
  local inChamber, inSmelter, free = 0, 0, count(M.REDSTONE)
  _, side = stand(env, s, "chamber", "input")
  inChamber = stack(call(side, "getEnergyItem"))
  if smelt then
    _, side = stand(env, s, "smelter", "output")
    inSmelter = stack(call(side, "getEnergyItem"))
  end
  local lots = math.floor(n / lot)
  while lots > 0 do
    local dust = math.max(0, math.ceil(lots * M.MACHINES.chamber.perOp) - inChamber)
    if smelt then dust = dust + math.max(0, math.ceil(lots * lot * yield * M.MACHINES.smelter.perOp) - inSmelter) end
    if dust <= free then break end
    lots = lots - 1
  end
  if lots == 0 then job.fail = "not enough redstone to power the machines" return end
  if lots * lot < n then
    note(s, ("redstone for %d of the %d %s only"):format(lots * lot, n, item:gsub("^.*:", "")))
    n = lots * lot
  end
  power(env, s, "chamber", n / lot)
  if smelt then power(env, s, "smelter", math.ceil(n * yield)) end
  if put(env, s, "chamber", "input", item, n) == 0 then
    job.fail = "the chamber would not take " .. item:gsub("^.*:", "")
    return
  end
  settle(env, s, job, smelt)
end

-- what a job needs from the factory: { { item, count }, ... }
local function wants(job)
  local n = job.n
  local list, dust = {}, 6
  local recipe = M.INFUSE[job.kind]
  if recipe then
    list[1] = { recipe.passes[1].input, n }
    local gasMb = {}
    for _, pass in ipairs(recipe.passes) do
      gasMb[pass.gas] = (gasMb[pass.gas] or 0) + n * pass.mb
      dust = dust + math.ceil(n * M.MACHINES.infuser.perOp)
    end
    if gasMb.redstone then dust = dust + math.ceil(gasMb.redstone / 10) end
    if gasMb.carbon then job.carbon = math.ceil(gasMb.carbon / 10) end
  else
    local lot, yield = oreYield(job.item)
    list[1] = { job.item, n }
    dust = dust + math.ceil(n / lot * M.MACHINES.chamber.perOp)
    if job.kind == "ore" then dust = dust + math.ceil(n * yield * M.MACHINES.smelter.perOp) end
  end
  list[#list + 1] = { M.REDSTONE, dust }
  return list
end

local function fetchFor(env, s, job)
  local list = wants(job)
  local function short()
    for _, w in ipairs(list) do
      if count(w[1]) < w[2] then return true end
    end
    return false
  end
  local function carbon()
    local have = 0
    for _, it in ipairs(M.GAS.carbon.items) do have = have + count(it[1]) * it[2] / 10 end
    return have
  end
  -- carbon: charcoal if the factory has it, coal if not
  local asked = false
  for _, name in ipairs(job.carbon and M.GAS.carbon.ask or {}) do
    if carbon() < job.carbon then
      list[#list + 1] = { name, count(name) + math.ceil(job.carbon - carbon()) }
      env.fetch(list)
      list[#list] = nil
      asked = true
    end
  end
  if not asked and short() then env.fetch(list) end
end

local function needed(kind)
  if M.INFUSE[kind] then return { "infuser" } end
  if kind == "ore" then return { "chamber", "smelter" } end
  if kind == "enrich" then return { "chamber" } end
end

local function doJob(env, s, job)
  -- setup: see what stands in the bay and set it up (nothing is fetched)
  if job.kind == "setup" then return setup(env, s, M.ORDER) end
  if job.kind == "move_infuser" then return setup(env, s, { "infuser" }, { bench = true, fetch = true }) end
  local machines = needed(job.kind)
  if not machines then return { ok = false, why = "no such job: " .. tostring(job.kind) } end
  if not M.INFUSE[job.kind] and type(job.item) ~= "string" then
    return { ok = false, why = "which item? (item=...)" }
  end
  job.n = math.max(1, math.min(M.MAX_BATCH, math.floor(tonumber(job.n) or 8)))
  if job.kind == "ore" then
    local lot, yield = oreYield(job.item)
    job.n = math.min(job.n, math.floor(64 / yield))
    job.n = math.max(lot, job.n - job.n % lot)
  end
  for _, name in ipairs(machines) do
    if not (s.m[name] and s.m[name].ok) then
      local r = setup(env, s, machines, { fetch = true })
      if not r.ok then return r end
      break
    end
  end
  local primary = M.INFUSE[job.kind] and M.INFUSE[job.kind].passes[1].input or job.item
  if not job.stage then job.stage = "fetch" M.save(s) end
  if job.stage == "fetch" then
    if env.inside() then env.leave() end
    fetchFor(env, s, job)
    if count(primary) == 0 then
      job.fail = "no " .. primary:gsub("^.*:", "") .. " to be had"
      job.stage = "handin"
    else
      job.stage = "work"
    end
    M.save(s)
  end
  if job.stage == "work" then
    env.report("foundry: " .. job.kind)
    if M.INFUSE[job.kind] then infuse(env, s, job) else refine(env, s, job, job.kind == "ore") end
    local made = aboard()
    made[M.REDSTONE], made["minecraft:coal"], made["minecraft:charcoal"] = nil, nil, nil
    made[primary] = nil
    for _, m in pairs(M.MACHINES) do made[m.item] = nil end
    job.made, job.stage = made, "handin"
    M.save(s)
  end
  if job.stage == "handin" then
    if env.inside() then env.leave() end
    local _, total = aboard()
    if total > 0 then env.handin() end
  end
  local made = job.made or {}
  return { ok = next(made) ~= nil and not job.fail, made = made, why = job.fail }
end

---------------------------------------------------------------- the loop

local function tell(env, s, job, res)
  if not job.id then return end
  pcall(rednet.broadcast, { type = "foundry_done", n = job.id, kind = job.kind, ok = res.ok or false,
    made = res.made, why = res.why }, env.PROTOCOL)
end

-- Work the foundry until told otherwise: the jobs in hand first, then wait
-- over the base for the factory to ask for something.
function M.run(env)
  local s = M.load()
  if not env.site(M.SITE) then return false end
  for name, m in pairs(s.m) do
    local def = M.MACHINES[name]
    if m.ok and def then env.block(def.x, def.y, def.z) end
  end
  local me = os.getComputerID()
  while s.on do
    local job = s.cur or table.remove(s.queue, 1)
    if job then
      s.cur = job
      M.save(s)
      M.print("Foundry job: " .. tostring(job.kind) .. (job.n and (" x" .. job.n) or ""))
      env.report("foundry: " .. tostring(job.kind))
      local ok, res = pcall(doJob, env, s, job)
      if not ok then
        if res == "Terminated" then error(res, 0) end
        note(s, "PROBLEM: " .. tostring(res))
        res = { ok = false, why = tostring(res) }
      end
      s.cur = nil
      s.last = { kind = job.kind, n = job.n, id = job.id, ok = res.ok or false, made = res.made, why = res.why }
      M.save(s)
      tell(env, s, job, res)
      if res.why then M.print("Foundry: " .. tostring(res.why)) end
    else
      if env.inside() then env.leave() end
      env.home()
      env.report("foundry: idle")
      local from, msg = rednet.receive(env.PROTOCOL, 30)
      if type(msg) == "table" and (msg.forId == nil or msg.forId == me) then
        if msg.type == "foundry_hello" then
          announce(env, s)
        elseif msg.type == "foundry_job" and type(msg.job) == "table" and msg.n then
          if s.last and s.last.id == msg.n then
            -- done already (the factory missed hearing so): say it again
            tell(env, s, s.last, s.last)
          else
            s.queue[#s.queue + 1] = { kind = msg.job.kind, n = tonumber(msg.job.n), item = msg.job.item, id = msg.n }
            M.save(s)
            pcall(rednet.send, from, { type = "foundry_ack", n = msg.n }, env.PROTOCOL)
          end
        end
      end
    end
  end
  return true
end

return M
