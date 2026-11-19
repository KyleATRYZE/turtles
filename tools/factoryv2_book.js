const TABS=[["tour","Tour"],["works","How it works"],["look","The look"],["order","Build order"],["you","Your calls"]];
const book=document.getElementById("book"),tabs=document.getElementById("tabs");
const PAGES={
tour:()=>`<h2>The redo, piece by piece</h2><p>Same building, same footprint. The redesign changes what it feels like to walk through: a gate that opens for you, a launch bay where the drones live and leave from, a control room over it that runs the swarm, machines you can watch working, and guards on the wall at night. One look throughout: dark plating, striped lanes, cyan light, amber for status.</p>`+
  D.zones.map(z=>`<button class="zone" data-id="${z.id}" aria-pressed="false"><b>${z.name} <span class="tag">stage ${z.ph}</span></b><p>${z.text}</p></button>`).join("")+
  `<p>Running now and shown as built: the ME core, power bay, alloy row, ore line, crystal garden and lab, assembler matrix, processor press, fuel line from the Nether.</p>`,
works:()=>`<h2>Computers, ME and levers</h2>
  <h3>The map wall</h3><p>A 13 by 4 wall of advanced monitors. Each monitor sets its own 16-colour palette, so the land is drawn in the game's own map colours (grass, water, stone, sand, snow) from the survey scans, the way a held map looks. Drones are moving dots with a trail. Touch a drone for its job, fuel and a RECALL button.</p>
  <h3>The consoles</h3><ul><li><b>Fleet:</b> every drone's state, one touch to send or recall.</li><li><b>Requisition:</b> ME's stock with a CRAFT button beside anything craftable. It talks to ME through the ME Bridge, the same way I ordered processors tonight.</li><li><b>Stock rules:</b> keep 64 lava buckets, 128 steel, 32 of each processor. A computer watches ME and orders the difference, so the rules live in one file, not in blocks.</li><li><b>Power:</b> generation, ME's draw and stored FE as moving bars.</li><li><b>Gate and guards:</b> who is at the door, what the guards last saw.</li></ul>
  <h3>Levers that do things</h3><p>Each lever sits on a CC redstone relay. A computer reads them: RECALL ALL, LOCKDOWN (gate shut, lights red, guards out), MINERS OUT, LIGHTS, SIREN TEST. Flip one and the screens, the gate and the drones answer.</p>
  <h3>The launch bay</h3><p>The old furnace room (25 long, 8 wide, 7 high) becomes the drones' home. Bays run down both walls in two rows, 40 in all for 16 drones. Each bay has a copper bulb on a redstone relay: the bay computer turns it green when the drone is docked, amber while it is out, red when it needs help. A drone coming home flies in through the hangar door in the west wall, drops what it carries at the intake counter (straight into ME), takes lava buckets at the fuel port, and parks. Going out is the same in reverse: the door opens, the board flips, the light goes amber.</p>
  <h3>The departures board</h3><p>Create's split-flap display boards on the launch bay's south wall, written by a computer through a display link: which drone left, for what, and when it is due back. The flaps clatter as it updates.</p>
  <h3>Before the furnaces go</h3><p>The 12 vanilla furnaces are crafter1's smelter. Its smelting moves to the ME smelters first (orders through the desk), so nothing it makes stops working.</p>
  <h3>The gate</h3><p>Two leaves of industrial iron on a Create gantry, turned by an electric motor on the foundry's power. The Player Detector tells the gate computer who is there. Known players: gate opens, chime, name on the screen. Lockdown: shut.</p>
  <h3>The guards</h3><p>Turtles with swords. Four walk the patrol ring at night and two hold the gate. A turtle hits whatever is in front of it, so the rule is strict: no swing while any player is within 6 blocks, and they only patrol outside the walls. When one fights, the alarm sounds and the gate lights go red.</p>
  <h3>Things you can watch</h3><ul><li>An overhead belt in the hall carrying incoming ore into ME.</li><li>A tinted glass floor down the hall's spine with the cables and pipes under it.</li><li>The crystal garden growing behind glass.</li><li>The launch bay through the Bridge's glass floor: drones landing, docking, lights changing.</li></ul>`,
look:()=>`<h2>The look</h2><p>From stone-brick workshop to a deep-space refinery. Dark plating, lit seams, glass where there is something to see.</p>
  <table><tr><td><b>Plating</b></td><td>Create industrial iron for gates, desks and aprons; sky stone and polished deepslate for floors and plinths</td></tr>
  <tr><td><b>Light</b></td><td>Cyan sea-lantern strips in the hall and on the Bridge, pale froglight on the walls, copper bulbs at doors. Red takes over on lockdown</td></tr>
  <tr><td><b>Glass</b></td><td>Tinted glass floors over the trench, quartz glass for the garden and the gate window</td></tr>
  <tr><td><b>Metal accents</b></td><td>Copper grates and chiseled copper round doorways, brass casings on the belt</td></tr>
  <tr><td><b>Markings</b></td><td>Your striped yellow concrete on every drone path and pad edge</td></tr>
  <tr><td><b>Screens</b></td><td>One style across all of them: dark ground, cyan and amber, a boot sequence when a computer starts, moving bars in place of static numbers</td></tr></table>
  <p>Every block named here is in your pack; I checked each against the server. Nothing needs nether stars.</p>
  <h3>What stays</h3><p>The footprint, the rooms, the barrels, and everything built in the hall. What goes: the furnace room's furnaces (it becomes the launch bay), the old rack and the old base. Stone-brick outer walls can be re-skinned to match; it is the biggest single job, so it is your call.</p>`,
order:()=>`<h2>Build order</h2>
  <div class="ph"><h3>A. Gate</h3><p>The gate, its computer and detector, the apron. One evening. First, because you walk through it every time.</p></div>
  <div class="ph"><h3>B. Launch bay and the Bridge</h3><p>Smelting moved to ME, furnaces out, bays, lights, hangar door, intake and fuel counter, departures board; then the drones' code learns the bays. Upstairs: map wall and its renderer, consoles, levers, glass floor. The code is most of the work.</p></div>
  <div class="ph"><h3>C. Hall and lane dressing</h3><p>Glass floor, light strips, bay lights, the ore belt, restyled screens everywhere.</p></div>
  <div class="ph"><h3>D. Guards</h3><p>Patrol ring, guard program, alarm. Needs four more turtles with swords.</p></div>
  <div class="ph"><h3>F. The outside</h3><p>Re-clad the outer walls in bands (plating, light seam, tinted glass, parapet), steel ribs, the glass roof over the hall, vents, the mast, floodlights, path lights. Done a wall at a time from the outside, so nothing inside stops. The biggest single job: drones carry the stone brick to the store as it comes off.</p></div>
  <div class="ph"><h3>E. Old base, old rack and grounds</h3><p>Drones take the old base apart into the store and lay the apron outside the hangar door; the old rack comes out; the land round the building is tidied to match.</p></div>
  <p>Alongside all of it, the function work carries on: crystal lab, assembler matrix, stock rules, the gas plant and 3x to 5x ore.</p>`,
you:()=>`<h2>Your calls</h2><ul>
  <li><b>The launch bay.</b> Drawn with the hangar door in the west wall, onto the old base's ground. Bays on both walls, two rows. Fewer bays or one row is easy.</li>
  <li><b>Where is the Bridge?</b> Drawn upstairs over the launch bay, with a glass floor onto it. If you would rather have it in the tower, say so.</li>
  <li><b>Gate size and place.</b> Drawn at the south entrance, four wide and three high. It can be bigger.</li>
  <li><b>Guards near friends.</b> They patrol outside the walls only and never swing near a player. If you would rather not have armed turtles on a shared server at all, they can be lights-and-alarm only.</li>
  <li><b>The outside.</b> Drawn as dark plating, a light seam and a tinted glass ribbon with steel ribs, plus a glass roof over the hall. Press Outside to see it. Too much glass? The ribbon can be plating with slot windows instead.</li>
  <li><b>The tower.</b> Not drawn: the survey does not reach it. I would make it a control spire to match once it is scanned.</li>
  <li><b>Conveyors.</b> One showpiece belt is drawn. More belts look good but each is another thing to keep running; ME already moves everything.</li></ul>
  <h3>What I could not see</h3><p>The survey covers the building up to the upper floor and not the tower, so the tower is not drawn. A scan of it comes first if the Bridge moves there.</p>`
};
