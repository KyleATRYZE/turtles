-- foundry.lua : the Mekanism line in the foundry bay, run by a helper.
--
-- helper.lua loads this and hands it its own tools (walking, fetching,
-- reporting) as `env`. The operator (foundry1) then works here whenever it
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
M.PROTOCOL = "swarm_job" -- (the factory's own channel)

-- the building the line stands in (its corner in the world, and the plans
-- the helper finds its way by)
M.SITE = { ox = -4448, oy = 71, oz = 1518, shell = "factory_asfit3", plan = "factory_foundryfloor" }

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
-- Foundry v2 (18 Nov evening): the store cannot push into a Mekanism machine
-- over the cable (probe: its own peripheral hides the inventory), so the
-- operator carries again, to the new places. The ore line on the east wall
-- faces WEST (lane x 41): the chamber pushes its dust south into the smelter,
-- results out of the smelter's south face. Everything is powered over
-- universal cable (no redstone dust). The alloy cell faces EAST (lane x 40):
-- the first infuser takes the infusion items by its north face, results out
-- of its front; the bank smelters in at the top, out at the front.
M.LAYOUT = "v2"
M.MACHINES = {
  chamber = { item = "mekanism:enrichment_chamber", x = 42, y = 1, z = 12, lane = "west",
    use = { input = "top", output = "south" }, eject = true, perOp = 0 },
  smelter = { item = "mekanism:energized_smelter", x = 42, y = 1, z = 13, lane = "west",
    use = { input = "top", output = "south" }, also = { north = "INPUT" }, perOp = 0 },
  infuser = { item = "mekanism:metallurgic_infuser", x = 39, y = 1, z = 17, lane = "east",
    use = { input = "top", extra = "north", output = "east" }, perOp = 0 },
  bank1 = { item = "mekanism:energized_smelter", x = 39, y = 1, z = 19, lane = "east", bank = true,
    use = { input = "top", output = "east" }, perOp = 0 },
  bank2 = { item = "mekanism:energized_smelter", x = 39, y = 1, z = 20, lane = "east", bank = true,
    use = { input = "top", output = "east" }, perOp = 0 },
  bank3 = { item = "mekanism:energized_smelter", x = 39, y = 1, z = 21, lane = "east", bank = true,
    use = { input = "top", output = "east" }, perOp = 0 },
}
M.BANK = { "bank1", "bank2", "bank3" }

-- Power (job=power): a Heat Generator burning coal (or lava, once a bucket
-- has been seen to come back out), an energy cube if one can be had, and a
-- line of universal cable on the plinth along the backs of the machines
-- (x 42). Laid out from the south: the generator at z 18 facing north (its
-- front, where the power comes out, against the cube), the cube at z 17
-- facing north (its front against the cable), cable from z 16 north to the
-- first machine. Without a cube there is cable at z 17 too.
M.GEN   = "mekanismgenerators:heat_generator"
M.CUBE  = "mekanism:basic_energy_cube"
M.CABLE = "mekanism:basic_universal_cable"
M.LAVA, M.BUCKET = "minecraft:lava_bucket", "minecraft:bucket"
M.POWER = { x = 42, y = 1, gen = 18, cube = 17, last = 16,
  fuel = { "minecraft:coal", "minecraft:charcoal" },
  low = 16,                -- fuel in the generator's slot below this: more taken over
  full = 64 }              -- (the slot holds a stack)

-- What the infuser makes: each pass is one trip through it.
M.INFUSE = {
  steel = { makes = "alltheores:steel_dust", passes = {
    { input = "minecraft:iron_ingot", gas = "carbon", mb = 10 },
    { input = "mekanism:enriched_iron", gas = "carbon", mb = 10 } } },
  circuit = { makes = "mekanism:basic_control_circuit", passes = {
    { input = "alltheores:osmium_ingot", gas = "redstone", mb = 20 } } },
  alloy = { makes = "mekanism:alloy_infused", passes = {
    { input = "minecraft:copper_ingot", gas = "redstone", mb = 10 } } },
  -- (Mekanism 1.21.x data; the diamond is enriched first: enrich=minecraft:diamond)
  reinforced = { makes = "mekanism:alloy_reinforced", passes = {
    { input = "mekanism:alloy_infused", gas = "diamond", mb = 20 } } },
  atomic = { makes = "mekanism:alloy_atomic", passes = {
    { input = "mekanism:alloy_reinforced", gas = "refined_obsidian", mb = 40 } } },
  refined = { makes = "mekanism:dust_refined_obsidian", passes = {   -- (obsidian dust: a Crusher's)
    { input = "mekanism:dust_obsidian", gas = "diamond", mb = 10 } } },
}
-- what fills the infusion tank, best first: { item, mB each }. ask = what
-- the factory is asked for (then the next one, if it has none).
M.GAS = {
  carbon = { name = "mekanism:carbon", ask = { "minecraft:charcoal", "minecraft:coal" },
    items = { { "mekanism:enriched_carbon", 80 }, { "minecraft:charcoal", 10 }, { "minecraft:coal", 10 } } },
  redstone = { name = "mekanism:redstone", ask = { "minecraft:redstone" },
    items = { { "mekanism:enriched_redstone", 80 }, { "minecraft:redstone", 10 } } },
  diamond = { name = "mekanism:diamond",
    items = { { "mekanism:enriched_diamond", 80 }, { "mekanism:dust_diamond", 10 } } },
  refined_obsidian = { name = "mekanism:refined_obsidian",
    items = { { "mekanism:enriched_refined_obsidian", 80 }, { "mekanism:dust_refined_obsidian", 10 } } },
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
  if s.layout ~= M.LAYOUT then          -- the machines have moved: found and set up again
    s.m, s.layout, s.bench, s.ready = {}, M.LAYOUT, true, nil
  end
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
--   foundry make=steel n=16               the infuser (steel, circuit, alloy,
--                                         reinforced, atomic, refined)
--   foundry job=setup | job=move_infuser  find or place the machines; bring
--                                         the infuser in from the bench
--   foundry job=power [cube=0] [fuel=lava]  lay power on: generator, cube,
--                                         cable; the machines then need no dust
--   foundry job=fuel [fuel=lava]          more fuel for the generator
--   foundry job=bank [n=3]                more smelters (on the cable)
--   foundry smelt=minecraft:sand n=128    anything a furnace cooks, through
--                                         every smelter there is
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
  if cmd.on ~= nil then
    s.on = not (cmd.on == 0 or cmd.on == "0" or cmd.on == false)
    -- off the foundry: the factory is told (its furnaces take the ore again)
    if not s.on then
      pcall(rednet.broadcast, { type = "foundry_ready", ready = false, machines = {} }, M.PROTOCOL)
    end
  end
  if cmd.clear then s.queue, s.cur = {}, nil end
  if cmd.reset then s.m, s.bench, s.ready, s.power = {}, nil, nil, nil end
  local kind, item = cmd.job, cmd.item
  if cmd.ore then kind, item = "ore", cmd.ore end
  if cmd.enrich then kind, item = "enrich", cmd.enrich end
  if cmd.make then kind = cmd.make end
  if cmd.smelt then kind, item = "smelt", cmd.smelt end
  if type(kind) == "string" then
    s.on = true
    s.queue[#s.queue + 1] = { kind = kind, n = tonumber(cmd.n), item = fullName(item),
      cube = cmd.cube, fuel = cmd.fuel }
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
    power = s.power and { ok = s.power.ok, fuel = s.power.fuel, cube = s.power.cube, on = s.power.on,
      lava = s.power.lava } or nil,
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

-- (The turtle's own kit is not cargo: its pickaxe, or the Chunk Controller it
-- wears in the pickaxe's place when it is not digging. One or the other is
-- always in the inventory of a turtle that carries a controller.)
local function isKit(name)
  return name == "advancedperipherals:chunk_controller" or name:find("pickaxe", 1, true) ~= nil
end

local function aboard()
  local inv, total = {}, 0
  for slot = 1, 16 do
    local d = turtle.getItemDetail(slot)
    if d and not isKit(d.name) then inv[d.name], total = (inv[d.name] or 0) + d.count, total + d.count end
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

-- Redstone dust a machine needs per item worked: none once the cable powers
-- it (unless it has been seen to go without power on the cable).
local function cost(s, name)
  local p = s.power
  if p and p.ok and type(p.on) == "table" and p.on[name] and p.on[name] ~= "no" then return 0 end
  return M.MACHINES[name].perOp
end
M.cost = cost

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
  if have == 0 or cost(s, name) == 0 then return 0 end
  local _, side = stand(env, s, name, "energy")
  local waiting = stack(call(side, "getEnergyItem"))
  local n = math.min(have, math.max(0, math.ceil(ops * cost(s, name)) + 2 - waiting))
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
    if low and cost(s, name) == 0 and os.clock() - changed > 20 then
      -- on the cable, and short of power: the generator has run dry, or the
      -- cable does not reach this one (dust, if there is any, from here on)
      s.starved = s.starved or {}
      if not s.starved[name] then
        s.starved[name] = true
        note(s, "the " .. name .. " is short of power on the cable")
      end
    end
    if low and count(M.REDSTONE) > 0 and boosts < 16 and os.clock() - boosted > 9
      and stack(call(side, "getEnergyItem")) == 0 and M.MACHINES[name].use.energy then
      -- the dust has run out (the slot holds one stack): more
      boosts, boosted = boosts + 1, os.clock()
      put(env, s, name, "energy", M.REDSTONE, math.min(16, math.ceil(left * math.max(cost(s, name), M.MACHINES[name].perOp)) + 1))
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
  -- power laid on already (the infuser brought in afterwards, say): its back
  -- takes power from the cable too
  local p = s.power
  if p and p.ok and m.x == M.POWER.x - 1 then
    local rel = relative("east", f)
    local mode = call(side, "getMode", "ENERGY", rel)
    if mode ~= nil and mode ~= "INPUT" then pcall(peripheral.call, side, "setMode", "ENERGY", rel, "INPUT") end
    p.on = p.on or {}
    if p.on[name] == nil then p.on[name] = "full" end
  end
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
  local p = s.power
  pcall(rednet.broadcast, { type = "foundry_ready", ready = s.ready or false, machines = machines,
    power = p and { ok = p.ok or false, fuel = p.fuel, lava = p.lava, cube = p.cube } or nil }, env.PROTOCOL)
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
    local want, byItem = {}, {}
    for _, name in ipairs(need) do
      local item = M.MACHINES[name].item
      -- the infuser already made stands on the bench outside
      if name == "infuser" and (opts.bench or not s.bench) then fromBench(env, s) end
      byItem[item] = (byItem[item] or 0) + 1           -- (three bank smelters: three of them)
    end
    for item, n in pairs(byItem) do
      if opts.fetch and count(item) < n then want[#want + 1] = { item, n } end
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

---------------------------------------------------------------- power

local function powerState(s)
  s.power = s.power or {}
  s.power.on = s.power.on or {}
  return s.power
end

-- the cable runs from the cube's place north to the first machine on the
-- plinth (the bank, once it stands)
local function lineStart(s)
  local P, z = M.POWER, M.POWER.last
  for name, def in pairs(M.MACHINES) do
    if def.x == P.x - 1 and (not def.bank or (s.m[name] and s.m[name].ok)) then z = math.min(z, def.z) end
  end
  return z
end

-- what stands on the power line at z (nil: nothing): looked at from above
local function lineAt(env, z)
  local P = M.POWER
  if not env.walk(P.x, P.y + 1, z) then error("cannot get over the power line at z " .. z, 0) end
  local seen, data = turtle.inspectDown()
  return seen and type(data) == "table" and data.name or nil
end

-- take up a piece of our own cable (it comes back on board)
local function liftCable(env, z)
  if lineAt(env, z) ~= M.CABLE then return false end
  turtle.select(1)
  local ok = turtle.digDown()
  if ok then env.unblock(M.POWER.x, M.POWER.y, z) end
  return ok
end

local function placeDownHere(item)
  local slot = findSlot(item)
  if not slot then return false end
  turtle.select(slot)
  local ok = turtle.placeDown()
  turtle.select(1)
  return ok
end

-- a block standing at z on the line, facing north (a placed block faces the
-- turtle): placed from the spot south of it, which must be clear
local function placeFacingNorth(env, item, z)
  local P = M.POWER
  if not env.walk(P.x, P.y, z - 1) then return false, "cannot get to the power line at z " .. (z - 1) end
  env.face(1)
  local seen = turtle.inspect()
  if seen then return false, "something stands at z " .. z end
  local slot = findSlot(item)
  if not slot then return false, "none on board" end
  turtle.select(slot)
  local ok, err = turtle.place()
  turtle.select(1)
  if not ok then return false, tostring(err) end
  local _, data = turtle.inspect()
  if not (type(data) == "table" and data.name == item) then return false, "it did not go down" end
  env.block(P.x, P.y, z)
  -- stand off the line again (the next block may go where the turtle is)
  env.walk(P.x, P.y + 1, z - 1)
  return true
end

-- every machine on the plinth takes power from the cable at its back
local function energySides(env, s)
  for name, def in pairs(M.MACHINES) do
    local m = s.m[name]
    if m and m.ok and def.x == M.POWER.x - 1 then
      local okStand = pcall(stand, env, s, name)
      if okStand then
        local rel = relative("east", m.f)
        local mode = call("front", "getMode", "ENERGY", rel)
        if mode ~= nil and mode ~= "INPUT" then
          local ok, err = pcall(peripheral.call, "front", "setMode", "ENERGY", rel, "INPUT")
          if not ok then note(s, ("%s: the back would not take power (%s)"):format(name, tostring(err))) end
        end
      end
    end
  end
end

local function fuelIn(side)
  local f = call(side, "getFuelItem")
  if type(f) == "table" then return stack(f) end
end

-- Over the generator: top up its fuel from what is on board (lava first
-- when lava is known to work, or when asked to try it). Notes how much fuel
-- it has and whether it makes power.
local function feed(env, s, tryLava)
  local P, p = M.POWER, powerState(s)
  if lineAt(env, P.gen) ~= M.GEN then
    p.ok = false
    note(s, "no generator on the power line")
    return 0
  end
  local fed = 0
  if (tryLava or p.lava == "works") and findSlot(M.LAVA) then
    local buckets = count(M.BUCKET)
    turtle.select(findSlot(M.LAVA))
    if turtle.dropDown(1) then
      sleep(1)
      turtle.select(1)
      turtle.suckDown()
      if count(M.BUCKET) > buckets then
        p.lava, fed = "works", fed + 1
        -- (a bucket at a time while they keep coming back: the tank holds more)
        while findSlot(M.LAVA) and fed < 8 do
          turtle.select(findSlot(M.LAVA))
          local before = count(M.BUCKET)
          if not turtle.dropDown(1) then break end
          sleep(1)
          turtle.select(1)
          turtle.suckDown()
          if count(M.BUCKET) == before then p.lava = "stuck" break end
          fed = fed + 1
        end
      else
        p.lava = "stuck"
        note(s, "an empty bucket stays in the generator: no more lava (take it out by hand)")
      end
    end
    turtle.select(1)
  end
  local have = fuelIn("bottom")
  for _, name in ipairs(P.fuel) do
    local room = P.full - (have or 0)
    if room <= 0 then break end
    local slot = findSlot(name)
    while slot and room > 0 do
      turtle.select(slot)
      local before = turtle.getItemCount(slot)
      turtle.dropDown(math.min(room, before))
      local went = before - turtle.getItemCount(slot)
      if went == 0 then break end
      fed, room = fed + went, room - went
      have = (have or 0) + went
      slot = findSlot(name)
    end
    turtle.select(1)
  end
  sleep(2)                                 -- (a moment to light up)
  p.fuel = fuelIn("bottom") or have
  local rate = call("bottom", "getProductionRate")
  local e = call("bottom", "getEnergy")
  p.making = (type(rate) == "number" and rate > 0) or (type(e) == "number" and e > 0)
  M.save(s)
  return fed
end

-- Is the power reaching the machines? Each one's energy is read before and
-- after a wait: rising (or full and the generator making power) is yes,
-- empty and staying empty is no (it keeps its redstone).
local function checkPower(env, s)
  local p = powerState(s)
  local seen = {}
  for name, def in pairs(M.MACHINES) do
    if s.m[name] and s.m[name].ok and def.x == M.POWER.x - 1 then
      local okStand, _, side = pcall(stand, env, s, name)
      if okStand then
        seen[name] = { e = call(side, "getEnergy"), max = call(side, "getMaxEnergy") }
      end
    end
  end
  for _ = 1, 10 do
    sleep(2)
    env.tick("foundry: is the power on?")
  end
  local any, rose = false, false
  for name, b in pairs(seen) do
    local okStand, _, side = pcall(stand, env, s, name)
    local e = okStand and call(side, "getEnergy")
    if type(e) == "number" and type(b.e) == "number" and e > b.e then
      p.on[name], rose = "yes", true
    elseif type(e) == "number" and type(b.max) == "number" and b.max > 0 and e >= b.max * 0.9 then
      p.on[name] = p.on[name] == "yes" and "yes" or "full"    -- (full already: seen when it works)
    elseif type(e) == "number" and e <= 0 then
      p.on[name] = "no"
    else
      p.on[name] = p.on[name] or "full"
    end
    if p.on[name] ~= "no" then any = true end
  end
  p.ok = rose or (any and p.making) or false
  local parts = {}
  for name, v in pairs(p.on) do parts[#parts + 1] = name .. " " .. v end
  table.sort(parts)
  note(s, ("power %s (fuel %s): %s"):format(p.ok and "on" or "NOT on", tostring(p.fuel), table.concat(parts, ", ")))
  M.save(s)
  return p.ok
end

-- Cable from the cube's place (when there is no cube) north to the first
-- machine, wherever there is none yet. Returns what could not be laid.
local function cableUp(env, s)
  local P, short = M.POWER, 0
  local top = (powerState(s).cube and P.last or P.cube)
  for z = top, lineStart(s), -1 do
    local there = lineAt(env, z)
    if there == nil then
      if placeDownHere(M.CABLE) then
        env.block(P.x, P.y, z)
      else
        short = short + 1
      end
    elseif there ~= M.CABLE and there ~= M.CUBE then
      note(s, ("something else on the power line at z %d: %s"):format(z, there))
    end
  end
  return short
end

local function fetchFuel(env, s, want, lava)
  local list = {}
  if lava then list[#list + 1] = { M.LAVA, count(M.LAVA) + 4 } end
  list[#list + 1] = { M.POWER.fuel[1], count(M.POWER.fuel[1]) + want }
  env.fetch(list)
  local have = count(M.POWER.fuel[1]) + count(M.POWER.fuel[2])
  if have < want then env.fetch({ { M.POWER.fuel[2], count(M.POWER.fuel[2]) + want - have } }) end
end

-- job=power: everything from the generator to the last cable, then the
-- machines' backs set to take power, the generator fed, the power checked.
local function layPower(env, s, job)
  local P, p = M.POWER, powerState(s)
  setup(env, s, M.ORDER)                   -- (where the machines are, which way they face)
  local wantCube = not (job.cube == 0 or job.cube == "0")
  local z1 = lineStart(s)
  local there = {}
  for z = z1, P.gen do there[z] = lineAt(env, z) end
  if there[P.gen] and there[P.gen] ~= M.GEN then
    return { ok = false, why = "something else stands where the generator goes: " .. there[P.gen] }
  end
  -- what to fetch
  local list, cables = {}, 0
  if there[P.gen] ~= M.GEN and not findSlot(M.GEN) then list[#list + 1] = { M.GEN, 1 } end
  if wantCube and there[P.cube] ~= M.CUBE and not findSlot(M.CUBE) then list[#list + 1] = { M.CUBE, 1 } end
  for z = z1, P.cube do if there[z] == nil then cables = cables + 1 end end
  if cables > count(M.CABLE) then list[#list + 1] = { M.CABLE, cables } end
  local fuelWant = math.max(0, P.full - (count(P.fuel[1]) + count(P.fuel[2])))
  if #list > 0 or fuelWant > 0 then
    if env.inside() then env.leave() end
    if #list > 0 then env.fetch(list) end
    if fuelWant > 0 then fetchFuel(env, s, fuelWant, job.fuel == "lava") end
  end
  if there[P.gen] ~= M.GEN and not findSlot(M.GEN) then
    return { ok = false, why = "no heat generator to be had" }
  end
  -- the generator, at z 18 facing north (from z 17: our own cable there is
  -- taken up first)
  if there[P.gen] ~= M.GEN then
    if there[P.cube] == M.CABLE and liftCable(env, P.cube) then there[P.cube] = nil end
    if there[P.cube] ~= nil then
      return { ok = false, why = "no way in to place the generator: " .. tostring(there[P.cube]) .. " in front" }
    end
    local ok, why = placeFacingNorth(env, M.GEN, P.gen)
    if not ok then return { ok = false, why = "the generator: " .. why } end
    there[P.gen] = M.GEN
    note(s, "heat generator placed")
  end
  -- the cube, at z 17 facing north (from z 16)
  if wantCube and there[P.cube] ~= M.CUBE and findSlot(M.CUBE) then
    if there[P.cube] == M.CABLE and liftCable(env, P.cube) then there[P.cube] = nil end
    if there[P.last] == M.CABLE and liftCable(env, P.last) then there[P.last] = nil end
    if there[P.cube] == nil and there[P.last] == nil then
      local ok, why = placeFacingNorth(env, M.CUBE, P.cube)
      if ok then
        there[P.cube] = M.CUBE
        note(s, "energy cube placed")
      else
        note(s, "the cube: " .. why)
      end
    end
  end
  p.cube = there[P.cube] == M.CUBE or nil
  local short = cableUp(env, s)
  energySides(env, s)
  feed(env, s, job.fuel == "lava")
  checkPower(env, s)
  announce(env, s)
  if env.inside() then env.leave() end
  local _, total = aboard()
  if total > 0 then env.handin() end
  local why
  if short > 0 then why = short .. " cable short" end
  if not p.ok then why = (why and why .. "; " or "") .. "no power reaching the machines" end
  return { ok = p.ok and short == 0, made = {}, why = why }
end

-- job=fuel: more fuel for the generator
local function fuelJob(env, s, job)
  local p = powerState(s)
  local want = math.max(8, M.POWER.full - (p.fuel or 0))
  if env.inside() then env.leave() end
  fetchFuel(env, s, want, job.fuel == "lava" or p.lava == "works")
  local fed = feed(env, s, job.fuel == "lava")
  announce(env, s)
  if env.inside() then env.leave() end
  local inv = aboard()
  inv["minecraft:coal"], inv["minecraft:charcoal"] = nil, nil
  if next(inv) then env.handin() end
  return { ok = fed > 0, made = {}, why = fed == 0 and "no fuel went in" or nil }
end

-- job=bank: more smelters north of the first, on the cable
local function layBank(env, s, job)
  local p = powerState(s)
  if not p.ok then return { ok = false, why = "lay power on first (job=power): the bank runs on the cable" } end
  local n = math.max(1, math.min(#M.BANK, math.floor(tonumber(job.n) or #M.BANK)))
  local names = {}
  for i = 1, n do names[i] = M.BANK[i] end
  local r = setup(env, s, names, { fetch = true })
  local short = cableUp(env, s)
  if short > 0 then
    if env.inside() then env.leave() end
    env.fetch({ { M.CABLE, short } })
    short = cableUp(env, s)
  end
  energySides(env, s)
  for _, name in ipairs(names) do
    if s.m[name] and s.m[name].ok then p.on[name] = p.on[name] or "full" end
  end
  checkPower(env, s)
  announce(env, s)
  if env.inside() then env.leave() end
  local _, total = aboard()
  if total > 0 then env.handin() end
  return { ok = r.ok and short == 0, made = {}, why = r.why or (short > 0 and short .. " cable short" or nil) }
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
    local oldLot, oldYield = oreYield(type(was) == "table" and type(was.name) == "string" and was.name or item)
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
    local dust = math.max(0, math.ceil(lots * cost(s, "chamber")) - inChamber)
    if smelt then dust = dust + math.max(0, math.ceil(lots * lot * yield * cost(s, "smelter")) - inSmelter) end
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

-- Anything a furnace cooks, through every smelter there is (the first one
-- and the bank), shared out evenly: in at the top, taken from each output.
local function smelters(s)
  local list = {}
  for _, name in ipairs({ "smelter", "bank1", "bank2", "bank3" }) do
    if s.m[name] and s.m[name].ok then list[#list + 1] = name end
  end
  return list
end

local function smeltAll(env, s, job)
  local names = smelters(s)
  if #names == 0 then job.fail = "no smelter set up" return end
  for _, name in ipairs(names) do drain(env, s, name) end       -- (whatever was left in them)
  local n = count(job.item)
  if n == 0 then job.fail = "no " .. job.item:gsub("^.*:", "") .. " on board" return end
  local each = math.ceil(n / #names)
  for _, name in ipairs(names) do
    local k = math.min(each, count(job.item), 64)
    if k > 0 then
      power(env, s, name, k)
      put(env, s, name, "input", job.item, k)
    end
  end
  for _, name in ipairs(names) do
    local _, left = drain(env, s, name)
    if left > 0 then job.fail = "the " .. name .. " stopped part way" end
  end
end

-- what a job needs from the factory: { { item, count }, ... }
local function wants(s, job)
  local n = job.n
  local list, dust = {}, 6
  local recipe = M.INFUSE[job.kind]
  if recipe then
    list[1] = { recipe.passes[1].input, n }
    local gasMb = {}
    for _, pass in ipairs(recipe.passes) do
      gasMb[pass.gas] = (gasMb[pass.gas] or 0) + n * pass.mb
      dust = dust + math.ceil(n * cost(s, "infuser"))
    end
    if gasMb.redstone then dust = dust + math.ceil(gasMb.redstone / 10) end
    if gasMb.carbon then job.carbon = math.ceil(gasMb.carbon / 10) end
    for gas, mb in pairs(gasMb) do         -- (any other infusion: fetched by its own items)
      if gas ~= "redstone" and gas ~= "carbon" then
        job.infuse = job.infuse or {}
        job.infuse[gas] = mb
      end
    end
  elseif job.kind == "smelt" then
    list[1] = { job.item, n }
    for _, name in ipairs(smelters(s)) do
      dust = dust + math.ceil(n / #smelters(s) * cost(s, name))
    end
  else
    local lot, yield = oreYield(job.item)
    list[1] = { job.item, n }
    dust = dust + math.ceil(n / lot * cost(s, "chamber"))
    if job.kind == "ore" then dust = dust + math.ceil(n * yield * cost(s, "smelter")) end
  end
  list[#list + 1] = { M.REDSTONE, dust }
  return list
end

local function fetchFor(env, s, job)
  local list = wants(s, job)
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
  -- any other infusion (diamond, refined obsidian): the best the factory has first
  for gas, mb in pairs(job.infuse or {}) do
    local items = M.GAS[gas] and M.GAS[gas].items or {}
    local function have()
      local h = 0
      for _, it in ipairs(items) do h = h + count(it[1]) * it[2] end
      return h
    end
    for _, it in ipairs(items) do
      if have() < mb then
        list[#list + 1] = { it[1], count(it[1]) + math.ceil((mb - have()) / it[2]) }
        env.fetch(list)
        list[#list] = nil
        asked = true
      end
    end
  end
  -- fuel for the generator rides along when it is running low
  local p = s.power
  if p and p.ok and (p.fuel or 0) < M.POWER.low then
    local want = M.POWER.full - (p.fuel or 0)
    local have = count(M.POWER.fuel[1]) + count(M.POWER.fuel[2]) - (job.carbon or 0)
    if have < want then
      list[#list + 1] = { M.POWER.fuel[1], count(M.POWER.fuel[1]) + want - have }
      env.fetch(list)
      list[#list] = nil
      asked = true
    end
  end
  if not asked and short() then env.fetch(list) end
end

local function needed(kind)
  if M.INFUSE[kind] then return { "infuser" } end
  if kind == "smelt" then return { "smelter" } end
  if kind == "ore" then return { "chamber", "smelter" } end
  if kind == "enrich" then return { "chamber" } end
end

local function doJob(env, s, job)
  -- setup: see what stands in the bay and set it up (nothing is fetched)
  if job.kind == "setup" then return setup(env, s, M.ORDER) end
  if job.kind == "move_infuser" then return setup(env, s, { "infuser" }, { bench = true, fetch = true }) end
  if job.kind == "power" then return layPower(env, s, job) end
  if job.kind == "fuel" then return fuelJob(env, s, job) end
  if job.kind == "bank" then return layBank(env, s, job) end
  local machines = needed(job.kind)
  if not machines then return { ok = false, why = "no such job: " .. tostring(job.kind) } end
  if not M.INFUSE[job.kind] and type(job.item) ~= "string" then
    return { ok = false, why = "which item? (item=...)" }
  end
  local most = job.kind == "smelt" and 64 * #smelters(s) or M.MAX_BATCH
  job.n = math.max(1, math.min(most, math.floor(tonumber(job.n) or 8)))
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
    s.starved = nil
    local onCable = {}
    for _, name in ipairs(machines) do onCable[name] = cost(s, name) == 0 end
    if M.INFUSE[job.kind] then infuse(env, s, job)
    elseif job.kind == "smelt" then smeltAll(env, s, job)
    else refine(env, s, job, job.kind == "ore") end
    -- on the cable and never short: the cable is seen to work. Short: the
    -- generator is fed now; short with fuel in it: that one is off the cable
    local p = s.power
    if p and p.ok then
      local hadFuel = (p.fuel or 0) >= M.POWER.low
      for name, was in pairs(onCable) do
        if was and not (s.starved or {})[name] and not job.fail then p.on[name] = "yes" end
        if was and (s.starved or {})[name] and hadFuel then
          p.on[name] = "no"
          note(s, "the " .. name .. " goes back to redstone: the cable does not keep it going")
        end
      end
      pcall(feed, env, s)
      announce(env, s)
    end
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
