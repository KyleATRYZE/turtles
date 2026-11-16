-- Simulated wired network: chests, a furnace, a crafty turtle, an output chest.
package.path = "/home/claude/turtles/?.lua;" .. package.path
INV = { ["minecraft:chest_0"] = {size=54, items={}}, ["minecraft:chest_1"] = {size=54, items={}}, ["minecraft:furnace_0"] = {size=3, items={}}, ["minecraft:furnace_1"] = {size=3, items={}}, ["minecraft:furnace_2"] = {size=3, items={}}, turtle_3 = {size=16, items={}}, front = {size=27, items={}} }
local function inv(n) return INV[n] or error("no inventory "..tostring(n)) end
function put(name, item, count)
  local I = inv(name)
  while count > 0 do
    local placed = false
    for s=1,I.size do local it=I.items[s]
      if it and it.name==item and it.count<64 then local t=math.min(64-it.count,count) it.count=it.count+t count=count-t placed=true break end end
    if not placed then for s=1,I.size do if not I.items[s] then local t=math.min(64,count) I.items[s]={name=item,count=t} count=count-t placed=true break end end end
    if not placed then error("full") end
  end
end
local function move(from, fromSlot, to, limit, toSlot)
  local F, T = inv(from), inv(to)
  local it = F.items[fromSlot]; if not it then return 0 end
  limit = math.min(limit or 64, it.count)
  local moved = 0
  local function into(s)
    local d = T.items[s]
    if not d then local t=limit-moved; T.items[s]={name=it.name,count=t,tag=it.tag}; moved=moved+t
    elseif d.name==it.name and d.tag==it.tag and d.count<64 then local t=math.min(64-d.count, limit-moved); d.count=d.count+t; moved=moved+t end
  end
  if toSlot then into(toSlot) else for s=1,T.size do if moved>=limit then break end into(s) end end
  it.count = it.count - moved; if it.count==0 then F.items[fromSlot]=nil end
  return moved
end
CALLS=0
local wired = { isWireless=function() return false end, getNameLocal=function() return MODEM_ON and "turtle_3" or nil end,
  getNamesRemote=function() return {"minecraft:chest_0","minecraft:chest_1","minecraft:furnace_0","minecraft:furnace_1","minecraft:furnace_2","computercraft:computer_9"} end }
local ender = { isWireless=function() return true end }
peripheral = {
  find=function(t, f)
    if t=="drive" then if NO_DRIVE_PERIPHERAL then return nil end
      return {isDiskPresent=function() return not NO_DISK end, hasData=function() return not NO_DISK end, getMountPath=function() return "disk" end} end
    if f("back", wired) then return wired end if f("right", ender) then return ender end end,
  getName=function() return "right" end,
  hasType=function(n,t) if n=="front" then
      if FACING==OUT_DIR then return t=="inventory" end
      if FACING==PAD_O and PAD_OCCUPIED then return t=="inventory" or t=="turtle" end
      return false end
    return INV[n]~=nil and t=="inventory" end,
  call=function(n, method, a, b, c, d)
    CALLS=CALLS+1
    if n=="front" and method=="getID" and FACING==PAD_O and PAD_OCCUPIED then return NEXT_ID + 1 end
    if n=="front" and method=="turnOn" then
      -- the newborn boots, installs itself, asks for a plot and flies off
      TURNED_ON=TURNED_ON+1; NEXT_ID=NEXT_ID+1
      INBOX[#INBOX+1]={id=NEXT_ID, msg={type="need_job", id=NEXT_ID}}
      PAD_OCCUPIED=false
      return true
    end
    if n=="front" and FACING~=OUT_DIR then error("no peripheral in front") end
    if method=="list" then local out={} for s,it in pairs(inv(n).items) do out[s]={name=it.name,count=it.count} end return out
    elseif method=="size" then return FURNACE_SIZE and n:find("furnace") and FURNACE_SIZE or inv(n).size
    elseif method=="pushItems" then return move(n, b, a, c, d)
    elseif method=="pullItems" then return move(a, b, n, c, d)
    end error("bad method "..method) end,
}
-- true recipes, written independently of factory.lua, to validate its grids
local function g(slot) local it=INV.turtle_3.items[slot] return it and it.name or "" end
local function isPlank(n) return n:sub(-7)=="_planks" end
local function isLog(n) return n:sub(-4)=="_log" end
local function grid() return {g(1),g(2),g(3),g(5),g(6),g(7),g(9),g(10),g(11)} end
local function shape(G)  -- trimmed pattern as string rows
  local rows={{G[1],G[2],G[3]},{G[4],G[5],G[6]},{G[7],G[8],G[9]}}
  local r1,r2,c1,c2=4,0,4,0
  for r=1,3 do for c=1,3 do if rows[r][c]~="" then r1=math.min(r1,r) r2=math.max(r2,r) c1=math.min(c1,c) c2=math.max(c2,c) end end end
  local out={} for r=r1,r2 do local row={} for c=c1,c2 do row[#row+1]=rows[r][c] end out[#out+1]=row end
  return out
end
local function eq(S, pat, pred)
  if #S~=#pat then return false end
  for r=1,#pat do if #S[r]~=#pat[r] then return false end
    for c=1,#pat[r] do local want=pat[r][c]; local got=S[r][c]
      if type(want)=="function" then if got=="" or not want(got) then return false end elseif got~=want then return false end end end
  return true
end
local ST,RS,GP,II,CO,CH,DI,SK,GO,EY="minecraft:stone","minecraft:redstone","minecraft:glass_pane","minecraft:iron_ingot","computercraft:computer_normal","minecraft:chest","minecraft:diamond","minecraft:stick","minecraft:gold_ingot","minecraft:ender_eye"
local TU,PK,MO="computercraft:turtle_normal","minecraft:diamond_pickaxe","computercraft:wireless_modem_advanced"
local LV,RT,OP,OS,SS="minecraft:lever","minecraft:redstone_torch","minecraft:oak_planks","minecraft:oak_slab","sophisticatedstorage:"
CRAFTED={}
FACING=0 OUT_DIR=OUT_DIR or 2 TURNS=0
PAD_O = PAD_O or 3                 -- absolute orientation of the launch pad side
FPOS = {x=100,y=64,z=200}          -- factory position
STEP = nil                         -- orientation we stepped out in, if away from home
FUEL = START_FUEL or 0
PLACED, NEWBORN_FUEL, TURNED_ON, PAD_OCCUPIED, NEXT_ID = {}, {}, 0, false, 40
local D4 = {[0]={x=1,z=0},[1]={x=0,z=1},[2]={x=-1,z=0},[3]={x=0,z=-1}}
local function blockedSide(o) return o==OUT_DIR or (BLOCKED and BLOCKED[o]) or (o==PAD_O and PAD_OCCUPIED) end
turtle = {
  turnRight=function() FACING=(FACING+1)%4 TURNS=TURNS+1 return true end,
  detect=function() return blockedSide(FACING) end,
  forward=function() if STEP or blockedSide(FACING) or FUEL<1 then return false end FUEL=FUEL-1 STEP=FACING return true end,
  back=function() if not STEP or STEP~=FACING or FUEL<1 then return false end FUEL=FUEL-1 STEP=nil return true end,
  inspectDown=function() if STEP==PAD_O and not NO_DRIVE then return true,{name="computercraft:disk_drive"} end return false,"No block" end,
  getFuelLevel=function() return FUEL end,
  refuel=function(n) local it=INV.turtle_3.items[SEL] if not it or it.name~="minecraft:coal" then return false end
    n=math.min(n or it.count, it.count) FUEL=FUEL+80*n it.count=it.count-n if it.count==0 then INV.turtle_3.items[SEL]=nil end return true end,
  place=function() if FACING~=PAD_O or PAD_OCCUPIED then return false end
    local it=INV.turtle_3.items[SEL] if not it then return false end
    PLACED[#PLACED+1]=it.name.."["..tostring(it.tag).."]" INV.turtle_3.items[SEL]=nil PAD_OCCUPIED=true return true end,
  suck=function() if FACING~=OUT_DIR then return false end
    for s2,it in pairs(INV.front.items) do
      for t=1,16 do if not INV.turtle_3.items[t] then INV.turtle_3.items[t]=it INV.front.items[s2]=nil return true end end
    end return false end,
  getItemCount=function(s) local it=INV.turtle_3.items[s] return it and it.count or 0 end,
  select=function(s) SEL=s end,
  transferTo=function(s) return move("turtle_3", SEL, "turtle_3", 64, s)>0 end,
  drop=function()
    if FACING==PAD_O and PAD_OCCUPIED then local it=INV.turtle_3.items[SEL] if not it then return false end
      if PAD_FULL then return false end        -- the turtle on the pad has no free slot
      NEWBORN_FUEL[#NEWBORN_FUEL+1]=it.name.." x"..it.count INV.turtle_3.items[SEL]=nil return true end
    if FACING~=OUT_DIR then return false end
    return move("turtle_3", SEL, "front", 64)>0 end,
  craft=function()
    for _,s in ipairs({4,8,12,13,14,15,16}) do if INV.turtle_3.items[s] then return false,"Inventory not empty outside grid" end end
    local S=shape(grid()); local out,n,tag
    local first=INV.turtle_3.items
    if eq(S,{{ST,ST,ST},{ST,RS,ST},{ST,GP,ST}}) then out,n=CO,1
    elseif eq(S,{{II,II,II},{II,CO,II},{II,CH,II}}) then out,n=TU,1
    elseif eq(S,{{DI,DI,DI},{"",SK,""},{"",SK,""}}) then out,n=PK,1
    elseif eq(S,{{GO,GO,GO},{GO,EY,GO},{GO,GO,GO}}) then out,n=MO,1
    elseif eq(S,{{isPlank,isPlank,isPlank},{isPlank,"",isPlank},{isPlank,isPlank,isPlank}}) then out,n=CH,1
    elseif eq(S,{{isPlank},{isPlank}}) then out,n=SK,4
    elseif eq(S,{{isLog}}) then out,n="minecraft:oak_planks",4
    elseif eq(S,{{"minecraft:glass","minecraft:glass","minecraft:glass"},{"minecraft:glass","minecraft:glass","minecraft:glass"}}) then out,n=GP,16
    elseif eq(S,{{II,"",II},{"",II,""}}) then out,n="minecraft:bucket",1
    elseif eq(S,{{"minecraft:cobbled_deepslate","minecraft:cobbled_deepslate"},{"minecraft:cobbled_deepslate","minecraft:cobbled_deepslate"}}) then out,n="minecraft:polished_deepslate",4
    elseif eq(S,{{"minecraft:polished_deepslate","minecraft:polished_deepslate"},{"minecraft:polished_deepslate","minecraft:polished_deepslate"}}) then out,n="minecraft:deepslate_bricks",4
    elseif eq(S,{{"minecraft:deepslate_bricks","minecraft:deepslate_bricks"},{"minecraft:deepslate_bricks","minecraft:deepslate_bricks"}}) then out,n="minecraft:deepslate_tiles",4
    elseif eq(S,{{"minecraft:deepslate_tiles","",""},{"minecraft:deepslate_tiles","minecraft:deepslate_tiles",""},{"minecraft:deepslate_tiles","minecraft:deepslate_tiles","minecraft:deepslate_tiles"}}) then out,n="minecraft:deepslate_tile_stairs",4
    elseif eq(S,{{ST,ST},{ST,ST}}) then out,n="minecraft:stone_bricks",4
    elseif eq(S,{{"minecraft:copper_ingot","minecraft:copper_ingot","minecraft:copper_ingot"},{"minecraft:copper_ingot","minecraft:copper_ingot","minecraft:copper_ingot"},{"minecraft:copper_ingot","minecraft:copper_ingot","minecraft:copper_ingot"}}) then out,n="minecraft:copper_block",1
    elseif eq(S,{{"minecraft:copper_block","minecraft:copper_block"},{"minecraft:copper_block","minecraft:copper_block"}}) then out,n="minecraft:cut_copper",4
    elseif eq(S,{{"minecraft:cut_copper","minecraft:cut_copper","minecraft:cut_copper"}}) then out,n="minecraft:cut_copper_slab",6
    -- Sophisticated Storage, from the mod's recipe provider (one wood throughout)
    elseif eq(S,{{SK},{"minecraft:cobblestone"}}) then out,n=LV,1
    elseif eq(S,{{RS},{SK}}) then out,n=RT,1
    elseif eq(S,{{OP,OP,OP}}) then out,n=OS,6
    elseif eq(S,{{OP,OS,OP},{OP,"",OP},{OP,OS,OP}}) then out,n="minecraft:barrel",1
    elseif eq(S,{{OP,OP,OP},{OP,LV,OP},{OP,OP,OP}}) then out,n=SS.."chest",1
    elseif eq(S,{{OP,OS,OP},{OP,LV,OP},{OP,OS,OP}}) then out,n=SS.."barrel",1
    elseif eq(S,{{OP,OS,OP},{OP,LV,OP},{OP,OP,OP}}) then out,n=SS.."limited_barrel_1",1
    elseif eq(S,{{OP,OP,OP},{OS,LV,OS},{OP,OP,OP}}) then out,n=SS.."limited_barrel_2",1
    elseif eq(S,{{OP,OS,OP},{OP,LV,OP},{OS,OP,OS}}) then out,n=SS.."limited_barrel_3",1
    elseif eq(S,{{OS,OP,OS},{OP,LV,OP},{OS,OP,OS}}) then out,n=SS.."limited_barrel_4",1
    elseif eq(S,{{II,II,II},{II,SS.."chest",II},{II,II,II}}) then out,n=SS.."iron_chest",1
    elseif eq(S,{{GO,GO,GO},{GO,SS.."iron_chest",GO},{GO,GO,GO}}) then out,n=SS.."gold_chest",1
    elseif eq(S,{{DI,DI,DI},{DI,SS.."gold_chest",DI},{DI,DI,DI}}) then out,n=SS.."diamond_chest",1
    elseif eq(S,{{"",RT,""},{RT,"minecraft:quartz",RT},{ST,ST,ST}}) then out,n="minecraft:comparator",1
    elseif eq(S,{{RT,RS,RT},{ST,ST,ST}}) then out,n="minecraft:repeater",1
    elseif eq(S,{{ST,"minecraft:comparator",ST},{isPlank,SS.."barrel",isPlank},{ST,"minecraft:comparator",ST}}) then out,n=SS.."controller",1
    elseif eq(S,{{"minecraft:ender_pearl",isPlank},{"minecraft:repeater",ST}}) then out,n=SS.."storage_link",1
    elseif eq(S,{{"","minecraft:ender_pearl",II},{"",SK,RT},{SK,"",""}}) then out,n=SS.."storage_tool",1
    elseif eq(S,{{"",SK,""},{SK,LV,SK},{"",SK,""}}) then out,n=SS.."basic_tier_upgrade",1
    elseif eq(S,{{II,II,II},{II,LV,II},{II,II,II}}) then out,n=SS.."basic_to_iron_tier_upgrade",1
    elseif eq(S,{{GO,GO,GO},{GO,LV,GO},{GO,GO,GO}}) then out,n=SS.."iron_to_gold_tier_upgrade",1
    elseif eq(S,{{DI,DI,DI},{DI,LV,DI},{DI,DI,DI}}) then out,n=SS.."gold_to_diamond_tier_upgrade",1
    elseif eq(S,{{isPlank,II,isPlank},{II,isPlank,II},{isPlank,II,isPlank}}) then out,n=SS.."upgrade_base",1
    elseif eq(S,{{isLog,isLog,isLog},{isLog,SS.."upgrade_base",isLog},{isLog,isLog,isLog}}) then out,n=SS.."stack_upgrade_tier_1",1
    elseif eq(S,{{II,II,II},{II,II,II},{II,II,II}}) then out,n="minecraft:iron_block",1
    elseif eq(S,{{GO,GO,GO},{GO,GO,GO},{GO,GO,GO}}) then out,n="minecraft:gold_block",1
    elseif eq(S,{{II,II,II},{II,SS.."stack_upgrade_tier_1",II},{"minecraft:iron_block",II,"minecraft:iron_block"}}) then out,n=SS.."stack_upgrade_tier_2",1
    elseif eq(S,{{GO,GO,GO},{GO,SS.."stack_upgrade_tier_2",GO},{"minecraft:gold_block",GO,"minecraft:gold_block"}}) then out,n=SS.."stack_upgrade_tier_3",1
    elseif eq(S,{{"minecraft:blaze_rod"}}) then out,n="minecraft:blaze_powder",2
    elseif eq(S,{{"minecraft:ender_pearl","minecraft:blaze_powder"}}) then out,n=EY,1
    elseif eq(S,{{PK,TU}}) then
      local t; for s,it in pairs(first) do if it.name==TU then t=it end end
      if t.tag then return false,"turtle already has upgrade" end
      out,n,tag=TU,1,"mining"
    elseif eq(S,{{"advancedperipherals:chunk_controller",TU}}) then
      local t; for s,it in pairs(first) do if it.name==TU then t=it end end
      if t.tag then return false,"turtle already has upgrade" end
      out,n,tag=TU,1,"chunky"
    elseif eq(S,{{TU,MO}}) then
      local t; for s,it in pairs(first) do if it.name==TU then t=it end end
      out,n,tag=TU,1,(t.tag=="mining") and "mining+ender" or (t.tag=="chunky") and "chunky+ender" or "ender-only"
    else return false,"No matching recipes" end
    -- as many crafts as every slot allows, up to a stack of output
    local k=64
    for _,s in ipairs({1,2,3,5,6,7,9,10,11}) do local it=first[s] if it then k=math.min(k,it.count) end end
    k=math.min(k, math.floor(64/n))
    for _,s in ipairs({1,2,3,5,6,7,9,10,11}) do local it=first[s] if it then it.count=it.count-k if it.count==0 then first[s]=nil end end end
    for _,s in ipairs({1,2,3,5,6,7,9,10,11}) do if first[s] then return false,"leftover in grid" end end
    first[SEL]={name=out,count=n*k,tag=tag}
    CRAFTS=(CRAFTS or 0)+1
    CRAFTED[#CRAFTED+1]=out..(tag and ("["..tag.."]") or "")
    return true
  end,
}
-- furnace cooks one item per 5 clock units if fuelled
SMELT={["minecraft:cobblestone"]="minecraft:stone",["minecraft:raw_iron"]="minecraft:iron_ingot",["minecraft:sand"]="minecraft:glass",["minecraft:raw_gold"]="minecraft:gold_ingot",["minecraft:raw_copper"]="minecraft:copper_ingot",["minecraft:stone_bricks"]="minecraft:cracked_stone_bricks"}
local CLOCK=0
local burns={}
SMELTED=0
local function tick()
  CLOCK=CLOCK+2
  for name,inv in pairs(INV) do
    if name:find("furnace") and not FURNACE_DEAD then
      local F=inv.items
      local i=F[1]
      if i and SMELT[i.name] then
        local b=burns[name] or 0
        local ok=true
        if b==0 then local f=F[2]; if not f or f.name=="minecraft:bucket" then ok=false elseif f.name=="minecraft:lava_bucket" then F[2]={name="minecraft:bucket",count=1} b=100 LAVA_BURNED=(LAVA_BURNED or 0)+1 else f.count=f.count-1 if f.count==0 then F[2]=nil end b=8 end end
        if ok then
          b=b-1; burns[name]=b; i.count=i.count-1; if i.count==0 then F[1]=nil end
          local o=F[3]; if o then o.count=o.count+1 else F[3]={name=SMELT[i.name],count=1} end
          SMELTED=SMELTED+1
        end
      end
    end
  end
end
os.clock=function() return CLOCK end
gps={locate=function() if NO_GPS then return nil end local o=STEP if o then return FPOS.x+D4[o].x, FPOS.y, FPOS.z+D4[o].z end return FPOS.x, FPOS.y, FPOS.z end}
INBOX, OUTBOX = {}, {}
os.epoch=function() return 1 end
os.getComputerID=function() return 12 end
LABEL="factory"
os.getComputerLabel=function() return LABEL end
os.setComputerLabel=function(l) LABEL=l end
os.reboot=function() error("REBOOT",0) end
FILES={}
fs={combine=function(a,b) return a.."/"..b end, exists=function(p) return FILES[p]~=nil end, delete=function(p) FILES[p]=nil end,
    open=function(p,m) if m=="w" then return {write=function(s) FILES[p]=s end, close=function() end} end return {readAll=function() return FILES[p] end, close=function() end} end}
REPORTS={}
rednet={open=function() end, broadcast=function(m) REPORTS[#REPORTS+1]=m end,
  send=function(id, m, p) OUTBOX[#OUTBOX+1]={to=id, msg=m, p=p} end,
  receive=function(proto)
    while true do
      -- (STATUSQ: status reports the factory overhears, {id=, msg=, at=clock};
      --  an INBOX message with wait=true is held until they have all been heard,
      --  one with at=clock until then)
      if proto=="swarm_job" then local m=INBOX[1]
        if m and not (m.wait and STATUSQ and #STATUSQ>0) and CLOCK>=(m.at or 0) then table.remove(INBOX,1) return m.id, m.msg end
      elseif proto=="swarm" then local m=STATUSQ and STATUSQ[1]
        if m and CLOCK>=(m.at or 0) then table.remove(STATUSQ,1) return m.id, m.msg end
      else local c=CMDQ and CMDQ[1] if c and CLOCK>=c.at then table.remove(CMDQ,1) return 3,c.cmd end end
      coroutine.yield() end end}
local function ser(v) if type(v)=="table" then local parts={} for k,val in pairs(v) do parts[#parts+1]="["..(type(k)=="string" and string.format("%q",k) or tostring(k)).."]="..ser(val) end return "{"..table.concat(parts,",").."}" elseif type(v)=="string" then return string.format("%q",v) else return tostring(v) end end
textutils={serialize=ser, unserialize=function(str) local f=load("return "..str) return f and f() end}
parallel={waitForAny=function(...) local cos={} for i,f in ipairs({...}) do cos[i]=coroutine.create(f) end
  while true do for i,co in ipairs(cos) do local ok,err=coroutine.resume(co) if not ok then error(err,0) end if coroutine.status(co)=="dead" then return i end end end end}
LOG={}
print=function(...) local t=table.pack(...) for i=1,t.n do t[i]=tostring(t[i]) end LOG[#LOG+1]=table.concat(t," ") end
IDLES=0
sleep=function(n) tick() if n and n>=10 then IDLES=IDLES+1 if IDLES>(MAX_IDLES or 1) then error("IDLE",0) end end if coroutine.isyieldable() then coroutine.yield() end end
function runFactory() local f=assert(loadfile("/home/claude/turtles/factory.lua")) return pcall(f) end
function total(name, item) local n=0 for _,it in pairs(INV[name].items) do if it.name==item then n=n+it.count end end return n end
function outTags() local t={} for _,it in pairs(INV.front.items) do t[#t+1]=it.name.."["..tostring(it.tag).."] x"..it.count end return table.concat(t,"; ") end
