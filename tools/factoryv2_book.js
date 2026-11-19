const TABS=[["tour","Tour"],["works","How it works"],["look","The look"],["order","Build order"],["you","Your calls"]];
const book=document.getElementById("book"),tabs=document.getElementById("tabs");
const PAGES={
tour:()=>`<h2>The redo, piece by piece</h2><p>Same building, same footprint. The redesign changes what it feels like to walk through: a gate that opens for you, a launch bay where the drones live and leave from, a control room over it that runs the swarm, machines you can watch working, and guards on the wall at night. One look throughout, inside and out: Create industrial. Brick, andesite and copper, working machines on show, warm light.</p>`+
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
look:()=>`<h2>The look: Create industrial</h2><p>A working brick factory that has grown up: heavy, warm, with its machinery showing on the outside.</p>
  <table><tr><td><b>Walls</b></td><td>Brick, with andesite-casing piers every five blocks standing a block proud of the wall, a cut-andesite plinth at the foot and an overhanging cornice at the top. That is the depth: no flat wall anywhere</td></tr>
  <tr><td><b>Windows</b></td><td>Tall factory windows in Create framed glass between the piers</td></tr>
  <tr><td><b>Roofs</b></td><td>The hall gets a sawtooth roof: copper shingle slopes with north-facing glass, the classic factory skyline. Flat roofs behind brick parapets elsewhere, with vents</td></tr>
  <tr><td><b>Machinery outside</b></td><td>Two brick smokestacks with copper bands that smoke, two Create fluid tanks piped into the wall, a conveyor over the roof from the launch bay to the hall, a large cogwheel turning by the gate, a steam whistle on the roof</td></tr>
  <tr><td><b>Light</b></td><td>Lanterns and copper bulbs, warm, not neon. Lanterns on posts round the path</td></tr>
  <tr><td><b>Markings</b></td><td>Your striped yellow concrete on drone paths, the apron and the gate</td></tr>
  <tr><td><b>Screens</b></td><td>Dark ground, amber and copper text, moving bars, so they sit with the brick</td></tr></table>
  <p>Every block named here is in your pack; I checked each against the server.</p>
  <h3>Shape changes</h3><p>The hall rises three blocks with the sawtooth roof, the stacks and tanks add a skyline on the east side, and the roof conveyor links the two halves. The footprint and everything inside stay where they are.</p>`,
order:()=>`<h2>Build order</h2>
  <div class="ph"><h3>A. Gate</h3><p>The gate, its computer and detector, the apron. One evening. First, because you walk through it every time.</p></div>
  <div class="ph"><h3>B. Launch bay and the Bridge</h3><p>Smelting moved to ME, furnaces out, bays, lights, hangar door, intake and fuel counter, departures board; then the drones' code learns the bays. Upstairs: map wall and its renderer, consoles, levers, glass floor. The code is most of the work.</p></div>
  <div class="ph"><h3>C. Hall and lane dressing</h3><p>Glass floor, light strips, bay lights, the ore belt, restyled screens everywhere.</p></div>
  <div class="ph"><h3>D. Guards</h3><p>Patrol ring, guard program, alarm. Needs four more turtles with swords.</p></div>
  <div class="ph"><h3>F. The outside</h3><p>Brick and andesite piers, factory windows, plinth and cornice, a wall at a time from the outside so nothing inside stops; the sawtooth roof on the hall; stacks, tanks and pipes; the roof conveyor. The biggest single job: drones carry the old stone brick to the store as it comes off.</p></div>
  <div class="ph"><h3>E. Old base, old rack and grounds</h3><p>Drones take the old base apart into the store and lay the apron outside the hangar door; the old rack comes out; the land round the building is tidied to match.</p></div>
  <p>Alongside all of it, the function work carries on: crystal lab, assembler matrix, stock rules, the gas plant and 3x to 5x ore.</p>`,
you:()=>`<h2>Your calls</h2><ul>
  <li><b>The launch bay.</b> Drawn with the hangar door in the west wall, onto the old base's ground. Bays on both walls, two rows. Fewer bays or one row is easy.</li>
  <li><b>Where is the Bridge?</b> Drawn upstairs over the launch bay, with a glass floor onto it. If you would rather have it in the tower, say so.</li>
  <li><b>Gate size and place.</b> Drawn at the south entrance, four wide and three high. It can be bigger.</li>
  <li><b>Guards near friends.</b> They patrol outside the walls only and never swing near a player. If you would rather not have armed turtles on a shared server at all, they can be lights-and-alarm only.</li>
  <li><b>The outside.</b> Create industrial: brick, andesite piers, factory windows, a sawtooth hall roof, smokestacks and tanks. Press Outside to see it. Red brick, or a darker brick (deepslate or nether brick) for a grimier look?</li>
  <li><b>The tower.</b> Not drawn: the survey does not reach it. I would make it a control spire to match once it is scanned.</li>
  <li><b>Conveyors.</b> One showpiece belt is drawn. More belts look good but each is another thing to keep running; ME already moves everything.</li></ul>
  <h3>What I could not see</h3><p>The survey covers the building up to the upper floor and not the tower, so the tower is not drawn. A scan of it comes first if the Bridge moves there.</p>`
};
