# CC lessons: what others do about our nine problems

Researched 2026-11-17. Sources are primary where possible: CC:Tweaked source (branch
`mc-1.21.x`, commit 4f6a555, version 1.121.x, NeoForge 1.21.1), Advanced Peripherals
source (`dev/1.21.1` = 0.7.62b, and `dev/0.8-1.21.1` at 413b35c = 0.8.2a+, 2026-11-15),
Mekanism's generated computer-method list for 10.7, official docs and issue threads.

Labels used below:
- **[source]** read in the mod's own code for MC 1.21.1. Not tested in our world.
- **[docs]** from official docs or a maintainer's reply.
- **[unverified]** a reasonable idea we could not confirm. Test before relying on it.

Our CC version is "1.11x" and our AP is the 0.8 line (controller.lua already handles the
0.8 chat box). Anything marked "CC >= x" must be checked against `_HOST` in game first.

---

## 1. Turtles jam handing items over at a launch pad

**What others do**
- Artist (SquidDev): the pickup/dropoff turtle sits *on the wired network*, and the
  storage computer moves items in and out of it by name. No drop/suck on the floor.
  https://github.com/SquidDev-CC/artist
- CCRemote: "CC's wired network can transport items over any distance", so no "bus"
  chest is needed. https://github.com/cyb0124/CCRemote
- SWARM: unload and refuel are two separate spots (chest below home for unload, above
  home for refuel), so a drone never waits on another drone's other job.
  https://github.com/ninnghazad/SWARM

**A trick that fits us [source]**
A full-block wired modem stays switched on as long as *at least one* of its faces has a
peripheral. While it is on, a neighbour that changes (a turtle arriving) is attached
automatically on the next tick, with no right-click
(`WiredModemFullBlockEntity.neighborChanged` -> `blockTick` -> `attachPeripherals`, only
`if (isPeripheralOn())`). When the turtle leaves, it is detached, and the modem stays on
because the other peripheral is still there.
https://github.com/cc-tweaked/CC-Tweaked/blob/mc-1.21.x/projects/common/src/main/java/dan200/computercraft/shared/peripheral/modem/wired/WiredModemFullBlockEntity.java

So: put a full-block wired modem under each pad, with a permanent chest (or barrel) on
one of its other faces, and cable to crafter1's network. A player clicks it once. Every
turtle that lands on the pad then shows up as `turtle_<n>` on the network. crafter1 can
`pushItems`/`pullItems` straight into and out of its slots, the same way factory.lua
already moves items to and from its own `selfName`.

**Recommendation**
- `factory.lua`: add `padTurtle()` that diffs `modem.getNamesRemote()` for
  `turtle_*` names and matches one to the caller by `peripheral.call(name, "getID")`
  (turtles are computers, so they have `getID` [docs: tweaked.cc/peripheral/computer]).
  Use it in the fuel, bucket and load hand-overs instead of drop/suck. Listen for
  `peripheral` / `peripheral_detach` events rather than polling (SquidDev confirms these
  fire for remote peripherals: https://github.com/cc-tweaked/CC-Tweaked/issues/264).
- `helper.lua` `downToPad`/`upFromPad` and `miner.lua` around line 740: once on the pad,
  just send `{type="on_pad", id=os.getComputerID()}` and wait for "done". The turtle
  moves nothing itself.
- Keep the 240 s "do not hog the pad" limit in helper.lua, but have crafter1 own the pad
  lease (who is on it, until when) so two turtles are never sent down at once.
- [unverified] that `pullItems` from a *remote* turtle works on our CC version. It works
  for crafter1's own name already, which uses the same lookup. Test once with `lua`.

---

## 2. Weak Automata Core: `useOnBlock` NPE "this.owner is null"

**Root cause [source]**
In AP 0.8 (`dev/0.8-1.21.1`, still true on 2026-11-15), the turtle's fake player is
always built with `owner = null`:
`TurtleFakePlayerProvider.getPlayer` -> `new APFakePlayer(level, null, profile)`.
But `APFakePlayer` reads `this.owner.get()` without a null check in three places:
- `awardStat` (line 93), reached only when the profile is *not* AP's own default profile,
- `getTeam` (line 146),
- `damageSources` (line 217, only when attacking).

https://github.com/IntelligenceModding/AdvancedPeripherals/blob/dev/0.8-1.21.1/src/main/java/de/srendi/advancedperipherals/common/util/fakeplayer/APFakePlayer.java
https://github.com/IntelligenceModding/AdvancedPeripherals/blob/dev/0.8-1.21.1/src/main/java/de/srendi/advancedperipherals/common/util/fakeplayer/TurtleFakePlayerProvider.java

The profile is the turtle's owning player. CC gives a turtle an owner whenever *any*
`Player` places it (`TurtleBlock.setPlacedBy`), and the turtle's own fake player counts
as a Player. So a turtle placed by crafter1 inherits crafter1's owner profile, or CC's
`[ComputerCraft]` profile if crafter1 has none. Either way it is not AP's default, so
any right-click that makes vanilla award a stat (for example using an item on a block)
crashes on line 93.

The 0.7 line (0.7.62b, `dev/1.21.1`) has no such dereference: its `awardStat` looks the
player up by UUID instead. So this is an 0.8 bug.

Why "sometimes works": [unverified] it depends on whether that click awards a stat or
asks for a team. An empty-hand click on a block that awards nothing can get through.
Who placed the turtle does not change the profile type, so re-placing it by hand is not
a reliable fix.

**Things that do not help**: no AP config option touches this. Picking the turtle up
and re-placing it only changes which owner profile it has. Issue #699 ("NullPointerException
when using useOnBlock", closed) and #764 are older 0.7 problems with other causes.
Issue #840 (0.8: the automata ray hits its own turtle) is related; the dev branch now
calls `setSourceBlock`, which looks like that fix.

**Ways round it**
1. **Use plain `turtle.place()` with a datapack tag (best, see problem 3).** It uses CC's
   own fake player, not AP's.
2. **AP `placeBlock` for placing (not clicking)**: it uses CC's `TurtlePlayer`, not
   `APFakePlayer`, so it does not hit the NPE [source]. It needs a Compass turtle upgrade
   (`minecraft:compass`) equipped on the other side.
3. Report it upstream: point at `APFakePlayer` lines 93/146/217 and the
   `null` owner in `TurtleFakePlayerProvider`. The fix is one null check.

**Also present in both 0.7.62b and 0.8 [source]**
- `useOnBlock({sneak=, yaw=, pitch=})`, `digBlock({...})` with the same options.
- `placeBlock({x,y,z, anchor, front, top, text, backText})`. x/y/z offsets up to
  `compassAccurePlaceRadius` (default 3, max 8). Free within `compassAccurePlaceFreeRadius`
  (default 1). Errors returned: `COMPASS_NOT_EQUIPPED`, `NOT_BLOCK`, `CANNOT_PLACE`,
  `OUT_OF_RANGE`, `EMPTY_SLOT`.
- `chargeTurtle([fuel])`: turns RF from an energy item in the selected slot into turtle
  fuel (rate `energyToFuelRate` in AP's metaphysics config). It is on the Weak Automata
  Core. A Mekanism energy tablet charged at the foundry could replace some lava runs.

**Recommendation**
- `helper.lua` `use` verb (around line 2007) and the cauldron `how == "use"` branch
  (around line 1993): first try `turtle.place()` with a stick selected (needs the tag
  from problem 3). Fall back to `auto.useOnBlock()` inside `pcall`. Report the error text.
- Never call `useOnBlock` holding an item that gets "used" (that is what awards a stat).
  Select an empty slot (the code already does this for the plain `use`).

---

## 3. Wired modems need a player's right-click

**What others say [docs]**
There is no Lua API to switch a modem's peripheral on. The request is still open:
https://github.com/cc-tweaked/CC-Tweaked/issues/264. In that thread, a datapack
("Turtles love Modems") is the workaround people use.

**How the datapack route works [source, CC 1.21.x]**
`turtle.place()` will *use* (right-click) the block in front, but only if the block is
in the tag `computercraft:turtle_can_use`. By default that tag holds only beehives,
cauldrons and the composter. The flow in `TurtlePlaceCommand.doDeployOnBlock`:
`useItemOn` returns pass, then if the block is tagged it calls `block.useWithoutItem`.
For a cable modem that is `CableBlockEntity.use`, which toggles the peripheral.
The turtle must hold *something*, because an empty slot returns "No items to place".
Hold an item that has no use of its own (a stick).

File for 1.21.1 (note the folder is `block`, singular, from 1.21):
`data/computercraft/tags/block/turtle_can_use.json`
```json
{ "replace": false, "values": ["computercraft:cable", "computercraft:wired_modem_full"] }
```
Put it in the world's `datapacks/` folder as a pack. Or, because ATM10 ships KubeJS, add a
server script:
```js
ServerEvents.tags('block', e => {
  e.add('computercraft:turtle_can_use', ['computercraft:cable', 'computercraft:wired_modem_full'])
})
```
This needs whoever runs the server. [unverified in game]

Notes [source]:
- It is a **toggle**. Click once, then check `getNamesRemote()` for the new name. Do not
  click again blindly.
- The cable modem's `use` fails unless the block has *both* cable and modem.
- A modem switches itself **off** when its peripheral goes away
  (`updateBlockState(... peripheral.hasPeripheral())`). Moving a machine
  (`job=move_infuser`) therefore needs a new click afterwards.
- A full-block modem that is already on attaches new neighbours by itself
  (problem 1). One player click on a "hub" full-block modem can serve up to 5 machines
  around it, as long as at least one stays.
- A peripheral directly touching a computer or turtle needs no modem at all.

**Recommendation**
- Ask the server owner to add the tag. Then add a `click` lab verb to `helper.lua` next to
  `use`: select a stick, call `turtle.place()`, then confirm on the network.
- For the foundry move onto cable: plan full-block modems as hubs, each with one
  permanent neighbour, so moving a machine never turns its modem off.

---

## 4. Turtles freezing in unloaded chunks

**Facts [source]**
- A turtle moving into an unloaded chunk gets `false, "Cannot leave loaded world"`
  (`TurtleMoveCommand`). It is not "obstructed". Retrying will not help.
- AP chunky turtle (1.21.1, 0.7.62b): while the Chunk Controller is equipped, every tick
  it force-loads its current chunk and "touches" a record. Records are saved (SavedData),
  so they survive a server restart. Every `chunkLoadValidTime` seconds (default 600,
  minimum 60) records not touched in that time are dropped.
  `ChunkManager.java`, `ChunkyPeripheral.java`, `TurtleChunkyUpgrade.update`.
- `chunkyTurtleRadius` (server config, default 0, max 16): 1 loads the 3x3 around the
  turtle. https://github.com/IntelligenceModding/AdvancedPeripherals/blob/dev/1.21.1/src/main/java/de/srendi/advancedperipherals/common/configuration/PeripheralsConfig.java
- AP 0.7.46a changelog: chunk timing now uses ticks, not wall-clock time, so lag no longer
  drops chunks early (#662).
- SWARM says plainly that chunk loading is left to the user.

**Recommendation**
- `helper.lua` `step()`, `miner.lua`'s move wrappers, `loader.lua`'s `flyTo`: treat
  `"Cannot leave loaded world"` as its own case. Stop, report `state="edge of loaded
  world"` with x/z, and wait for a loader (the factory already pairs loaders by
  `K.SILENT`). Do not count it as an obstruction.
- Ask the server owner for `chunkyTurtleRadius = 1`. Then a worn controller covers the next
  chunk too, so a turtle can cross a chunk border without the "put it on for a moment
  in each new chunk" dance in `swarm.lua` `C.touch`/`C.keep`.
- `swarm.lua` `C.HOLD = 180` is well inside the 600 s default. Keep it below
  `chunkLoadValidTime` if the server lowers that.

---

## 5. 1 MB disk, 200-local limit

**Facts**
- `computer_space_limit` default 1,000,000 bytes. `floppy_space_limit` default 125,000.
  Both are in the server config (`computercraft-server.toml`) and can be raised [source:
  `ConfigSpec.java`].
- Cobalt (CC's Lua VM): `LUAI_MAXVARS = 200` locals per function, `LUAI_MAXUPVALUES = 60`,
  `MAXSTACK = 250` [source: https://github.com/cc-tweaked/Cobalt `LuaC.java`].
- Our files: factory.lua 138 KB, helper.lua 101 KB, builder.lua 87 KB. Every turtle
  downloads every file in `manifest.txt`.

**What others do**: Howl (build and minify), Luz (compression):
https://github.com/SquidDev-CC/Howl, https://github.com/MCJack123/Luz (from
awesome-computercraft). [unverified] We have not checked they work on current CC.

**Recommendation**
- `update.lua`: download only what the machine's `.role` needs. A miner does not need
  factory.lua, builder.lua or screens.lua. Put a role column in `manifest.txt`
  (`miner.lua miner,helper`). This is the biggest saving and the least risky.
- Keep splitting large files into `require` modules, as `foundry.lua` already is
  (for example `lab.lua` out of helper.lua, `recipes.lua` out of factory.lua). Each
  module is its own top-level chunk, with its own 200-local budget.
- Keep the existing `K = {}` and `LN = {}` style: table fields do not count as locals.
- Report `fs.getFreeSpace("/")` in `swarm.report`, so the dashboard shows space before
  writes fail.

---

## 6. Placing directional blocks the right way round

**Facts**
- `turtle.place()` places as a fake player looking out of the turtle's front. Most
  blocks then face back at the turtle. Our helper.lua learns the offset per block
  (`st.turns`) and checks the result with `inspect().state`. That is the usual approach.
- AP `placeBlock` (problem 2) takes `anchor` (the face it hangs on), `front` (which way it
  faces) and `top`. It places the `BlockItem` directly through a `DirectionalPlaceContext`.
  So a machine can face any of the six directions without turning the turtle [source].
  It needs a compass upgrade. It cannot place fluids or use items.
- Mekanism: `getDirection()` reads which way a machine faces over the computer
  interface [docs: Mekanism 10.7 computer methods].

**Recommendation**
- `helper.lua` around line 1295 (`applyOp`): if a compass is equipped and the block has
  a facing, call `placeBlock({front=want.facing, anchor=...})` first. Fall back to the
  current learn-and-correct code.
- A builder needs the compass and the automata on its two sides. Swap the pickaxe out
  the same way the Chunk Controller swap works.

---

## 7. Silent stalls with no alert

**What we have**: controller.lua shows `SILENT n m` after 300 s (lines 390, 551). But
`alertFor` only fires on states a turtle *reports*, so a turtle that says nothing never
triggers a chat alert.

**What others do**: Telem (https://telem.cyberbit.dev) sends metrics to a cloud
dashboard. ntfy (https://docs.ntfy.sh) is a common free push service. You publish with a
plain HTTP POST, which CC's `http.post` can do. [unverified] that our server's http rules
allow ntfy.sh.

**Recommendation**
- `controller.lua`: in the loop that computes `age`, when `age > 300` and the last alert
  for that unit is more than 30 min old, call `say(name .. " has been silent for N min")`.
  Also POST to an ntfy topic, so the alert reaches a phone outside the game.
- `swarm.lua`: add `M.watchdog(limitSeconds)` to run inside `runWithCommands`'
  `parallel.waitForAny`. It reads a `M.lastProgress` clock that `tick()` and `report()`
  update. If nothing changed for `limit`, it reports `state="stuck"` with the last log
  line. That catches "running but going nowhere", which "silent" does not.
- Report the reason when a move fails (the string from `turtle.forward()`), not just
  "could not get there".

---

## 8. Turtles colliding on paths

**Facts**
- SWARM: shared map; a blocked drone "will try to go around, wait until it has moved or
  just kill whatever they encounter".
- **Turtles are mineable with a pickaxe** [source: CC `TagProvider`, `MINEABLE_WITH_PICKAXE`
  includes `turtle_normal` and `turtle_advanced`]. A miner that "digs through" whatever is
  in its way can break another turtle (and our cable, modems and disk drive).
- `turtle.inspect()` returns the block name, so a turtle in the way shows up as
  `computercraft:turtle_normal`/`_advanced`.

**Recommendation**
- Every dig-to-clear in miner.lua and helper.lua (the "only earth and stone in the
  hole" rule is a good start): never dig a block whose name starts with `computercraft:`.
  On seeing one, wait a random 1 to 4 s and retry, then side-step, then report.
- Pad and shaft cells: crafter1 already hands out loads. Let it hand out short leases
  for the shared cells too (pad, in-shaft, out-shaft), with a timeout. Turtles ask before
  entering. That is the jobserver idea from SWARM, applied to cells.

---

## 9. Slow orders through GitHub polling

**Facts**
- CC websockets: `http.websocket(url | {url, headers, timeout})`,
  `http.websocketAsync` with `websocket_success`/`websocket_message`/`websocket_closed`
  events. Enabled by default (`websocket_enabled = true`), 4 open sockets per computer by
  default (`max_websockets`) [source + docs: https://tweaked.cc/module/http.html]. The
  server's `[http] rules` can still block hosts. Private and local addresses are denied by
  default. [unverified] what our server's config says. Check with
  `http.checkURL("wss://ntfy.sh")`.
- ntfy websocket: `wss://ntfy.sh/<topic>/ws` delivers JSON `{event="message", message=...}`
  with keepalives. `?poll=1&since=10m` fetches what was missed [docs: https://docs.ntfy.sh/subscribe/api/].
- GitHub: an authenticated conditional request (`If-None-Match: <ETag>`) that returns 304
  does not count against the rate limit
  [docs: https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api].
  So `commands.json` can be checked every few seconds for free.

**Recommendation**
- `controller.lua` `fetchOrders`: keep the ETag from the last response and send
  `If-None-Match`. On 304, do nothing. Then drop `ORDER_POLL` from 20 to 5 s.
  Note: CC's `http.get` returns `nil, err, response` for non-2xx. Read the status from the
  third value.
- Add a websocket "nudge" channel: `tools/order.py` also POSTs the order id to a private
  ntfy topic (long random name). The controller keeps `http.websocket` open in a
  `parallel` branch and calls `fetchOrders()` right away on a message. If the socket drops,
  reconnect with backoff and keep the 5 s poll as the fallback. GitHub stays the record;
  the socket only cuts latency.

---

## Things we didn't know

| What | Where | 1.21.1? |
|---|---|---|
| `turtle.getEquippedLeft()/getEquippedRight()` give the upgrade's item details (pickaxe included), with no equip-swap needed. Could replace the peripheral-type guessing in `swarm.lua` `C.side` and `miner.lua` around line 1128. | CC `TurtleAPI.java`, `@cc.since 1.116.0` | Yes, if our CC is 1.116 or later. Check `_HOST`. |
| **Redstone Relay**: a block with all six redstone sides, driven over a wired modem. The foundry's "redstone from the lane" could become one relay on the cable. | https://tweaked.cc/peripheral/redstone_relay.html (1.114.0) | Yes [source: `ModRegistry`]. |
| On NeoForge, a block that offers its **own** peripheral (Mekanism machines do) is wrapped as *only* that peripheral. CC does not add the generic `list`/`pushItems` methods to it. | CC `PlatformHelperImpl.PeripheralAccess.get` | Yes [source]. |
| Mekanism machines over cable: `getEnergy`, `getMaxEnergy`, `getEnergyNeeded`, `getRedstoneMode`/`setRedstoneMode`, `getMode`/`setMode`/`incrementMode`/`setEjecting`/`isEjecting`/`getConfigurableTypes`/`getSupportedModes` (side config), `getRecipeProgress`/`getTicksRequired`, `getInstalledUpgrades`, `getDirection`, `getComparatorLevel`. Infuser: `getInput`, `getOutput`, `getInfuseType`, `getInfuseTypeNeeded`, `dumpInfuseType`. Injecting/purifying machines: `getChemical*`, `dumpChemical`. | https://mekanism.github.io/computer_data/10.7.0.html | 10.7 is the 1.21.1 line. |
| Using the item above: `setRedstoneMode("IGNORED")` means a machine runs without any redstone, and `setMode`/`setEjecting` let the machine push its own output into a neighbouring chest. foundry.lua already calls `setMode`/`setEjecting` from the side; over cable the same calls work by network name. | as above | [docs] |
| Putting items *into* a Mekanism machine from a chest by its network name (`chest.pushItems("mekanism:...._0", slot)`): CC finds the target's inventory through the block's item capability, not its methods, so it may work. Test once. Otherwise feed by side config from a chest, as now. | CC `ForgePeripheralTargets.getItemHandler` (1.122 API; older versions differ) | [unverified] |
| AP 0.8 breaking changes: peripheral types are snake_case (`chat_box`); `importItem("@north")` for directions; the chat box's `xToPlayer` functions are gone (pass `player=` in options); disabled peripherals expose only `peripheralDisabled`. | https://docs.advanced-peripherals.de/0.8/changelogs/0.8/ | Yes (0.8 is 1.21.1). |
| AP Player Detector `getPlayerPos`/`getPlayer` return `nil` (not `{}`) for a missing player since 0.7.59b. | AP `CHANGELOG.md` | Yes. |
| AP `chunkyTurtleRadius` and `chunkLoadValidTime` server configs (problem 4). | `PeripheralsConfig.java` | Yes [source]. |
| AP `placeBlock` with `anchor/front/top` and the compass upgrade; `chargeTurtle` from RF items (problem 2). | `AutomataBlockHandPlugin`, `AutomataChargingPlugin` | Yes, in 0.7.62b and 0.8 [source]. |
| `turtle_can_use` block tag lets plain `turtle.place()` right-click tagged blocks (problem 3). | CC `ComputerCraftTags.Blocks.TURTLE_CAN_USE` | Yes [source]. |
| Turtles, computers, cable, modems and disk drives are all pickaxe-mineable (problem 8). | CC `TagProvider` | Yes [source]. |
| `peripheral` / `peripheral_detach` events fire for remote peripherals on a wired network, so we can wait on events instead of polling `getNamesRemote`. | SquidDev in https://github.com/cc-tweaked/CC-Tweaked/issues/264 | [docs] |
| hopper.lua: one-line item pipelines between any inventories (`/ input *furnace* -to-slot 1 -to-limit 5 -per-chest`). Could run the foundry's feeding from the storage computer. | https://github.com/umnikos/hopper.lua | [unverified] version |
| Artist's trashcan: a second turtle on the network runs `extra/trashcan.lua` and voids items above a stock limit. This is the same idea as our darkstone/kivi dumping. | https://github.com/SquidDev-CC/artist | [unverified] version |
| Cloud Catcher: remote terminal access to a computer from a browser, over websocket. Useful for live debugging without GitHub round trips. | https://github.com/SquidDev-CC/cloud-catcher | [unverified] |
| `http.checkURL(url)` tells us whether the server's http rules allow a host before we depend on it. | https://tweaked.cc/module/http.html | Yes. |

Not checked (pages blocked or not reached): lewark/inv.lua, Storehaus/CC-MISC internals,
Fatboychummy-CC repos, the tweaked.cc guide pages (robots-blocked), and the AP docs pages for
ME Bridge, Inventory Manager, Block Reader, Colony Integrator and Geo Scanner beyond the
changelogs above. Ottomated's turtle-gambit README describes getting onto a server without
the admins knowing, so it was not used.
