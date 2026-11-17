"""docs/rack-build.html: Kyle's build guide for rack 1's loading bays.

python3 tools/rackpage.py   writes the page (cells from tools/retrofit.py,
checked there: python3 tools/retrofit.py check).

Layer-by-layer top-down grids (y -1 .. 5) and a rotatable isometric view of
the rack wall, every block he places colour-coded, world coordinates on
hover, counts, and the steps ending with the modems to right-click.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import retrofit as R  # noqa: E402

X0, X1, Y0, Y1, Z0, Z1 = 0, 28, -1, 5, 1, 5

# (code, label, light colour, dark colour, kind) - kind: new / ctx / cut
CAT = [
    ("bay", "Wired modem (full block): bay shelf, right-click it", "#e8590c", "#ff8a3d", "new"),
    ("conn", "Wired modem (full block): connector, do NOT click", "#0b7285", "#3bc9db", "new"),
    ("cable", "Networking cable (hidden)", "#d6a400", "#ffd43b", "new"),
    ("mon", "Advanced monitor, facing south (the bay)", "#1c7ed6", "#74c0fc", "new"),
    ("pc", "Computer (the board's, moved here)", "#7048e8", "#b197fc", "new"),
    ("cut", "Take out (keep it)", "#e03131", "#ff6b6b", "cut"),
    ("floor", "Floor (polished deepslate)", "#8d8f96", "#7a7c86", "ctx"),
    ("stripe", "Lane floor (striped concrete): lift, put back", "#c9b458", "#9c8c4e", "ctx"),
    ("copper", "Cut copper pad", "#c07a4f", "#a8693f", "ctx"),
    ("wall", "Wall (bricks, tiles, pillars)", "#a9a59c", "#6e6e76", "ctx"),
    ("bars", "Iron bars", "#c8ccd2", "#868c95", "ctx"),
    ("board", "Name board (advanced monitors): now the high shelf's panel", "#4dabf7", "#4dabf7", "ctx"),
    ("store", "Storage (barrels, chests)", "#a07c4a", "#8c6c42", "ctx"),
    ("hall", "Hall cable (built)", "#e0c060", "#b39a40", "ctx"),
    ("other", "Other", "#b8b4ac", "#6a6a72", "ctx"),
]
CODE = {c[0]: i for i, c in enumerate(CAT)}


def ctx_code(it):
    n = it.split(":")[-1]
    if "monitor" in n:
        return "board"
    if "cable" in n:
        return "hall"
    if "striped" in n:
        return "stripe"
    if "copper" in n:
        return "copper"
    if "bars" in n:
        return "bars"
    if "barrel" in n or "chest" in n:
        return "store"
    if n.startswith("polished_deepslate"):
        return "floor"
    if "brick" in n or "deepslate" in n or "tile" in n:
        return "wall"
    return "other"


STEPS = [
    ("Take down the old board computer",
     "The computer behind the name board and the ender modem on top of it come out. Keep the computer: it is "
     "labelled RackBoard and keeps its files. It goes back into the wall in step 5. The ender modem goes back in "
     "stock.",
     [("cut", R.OLD_BOARD_PC)]),
    ("Lay the cable under the lane floor",
     "In the lane, lift the striped floor tiles along the front track from the hall end to the launch bay wall "
     "(x 1-18, z 2). Dig out the block under each tile and put a cable in its place. Do the same under the hall "
     "corner (lift the hall tile under the hall cable's end), then under the wall end at x 18. Put every striped "
     "tile back.",
     [("cable", R.TRENCH1)]),
    ("Floor plug under the hall cable",
     "Put a full-block wired modem where you lifted the hall tile (the hall cable's end sits on it). "
     "Do not right-click it: it only joins the cables.",
     [("conn", [R.HALL_PLUG])]),
    ("The wall end, lane side",
     "From the lane, take out the two bricks at the foot of the x 18 wall (y 1-2, z 3) and the floor block under "
     "them. Cable in the floor block, then two wired modems in the brick holes. Don't click them.",
     [("cable", [R.RACK_UNDER]), ("conn", [(18, 1, 3), (18, 2, 3)])]),
    ("The wall end, behind the board",
     "From the storage room side (the top of the barrel wall), take out the three bricks in the x 18 wall just "
     "west of the board's end (y 2-4, z 4). Wired modems in the lower two, then the RackBoard computer in the top "
     "one, touching the board. Don't click the modems.",
     [("conn", [(18, 2, 4), (18, 3, 4)]), ("pc", [R.RACK_PC])]),
    ("The bay shelf",
     "Swap the eight copper blocks of the middle shelf (y 2, the high homes' floor) for full-block wired modems. "
     "Each touches the home under it and the home on it. They join each other without cable.",
     [("bay", R.BAYS1)]),
    ("The low shelf's panel",
     "Swap the eight iron bars right behind the shelf (y 2, z 4) for advanced monitors, put up from the bay side so "
     "they face you. They make one 8 × 1 strip: the low homes' panels. The bars above and below stay, so the strip "
     "does not join the name board.",
     [("mon", R.STRIP1)]),
    ("Switch on",
     "Right-click each of the eight shelf modems once (from the lane, on its front edge). Each time chat should say "
     "a monitor was connected (and a turtle, if one is docked). They stay on from then on, with or without drones. "
     "Then right-click the computer to start it.",
     []),
]


def data():
    B = R.model()
    for c in R.OLD_BOARD_PC:
        pass
    new = {}
    for i, (_, _, parts) in enumerate(STEPS):
        for code, cells in parts:
            for c in cells:
                new[c] = (code, i + 1)
    out = []
    for x in range(X0, X1 + 1):
        for y in range(Y0, Y1 + 1):
            for z in range(Z0, Z1 + 1):
                c = (x, y, z)
                wx, wy, wz = R.W(*c)
                if c in new:
                    code, step = new[c]
                    was = B.get(c)
                    out.append([x, y, z, CODE[code], step, (was or "").split(":")[-1]])
                elif B.get(c):
                    out.append([x, y, z, CODE[ctx_code(B[c])], 0, B[c].split(":")[-1]])
    return out


def counts():
    n = {}
    for _, _, parts in STEPS:
        for code, cells in parts:
            n[code] = n.get(code, 0) + len(cells)
    return n


def clicks():
    return [list(R.W(*c)) for c in R.BAYS1]


PAGE = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Rack 1 loading bays: build guide</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Big+Shoulders+Display:wght@600;800&family=IBM+Plex+Sans:wght@400;500;600&family=IBM+Plex+Mono:wght@400;500&display=swap" rel="stylesheet">
<style>
%%CSS%%
.plan { position: relative; background: var(--panel); border: 1px solid var(--line); border-radius: 10px; overflow: auto; }
.plan canvas { display: block; touch-action: none; }
.tip { position: absolute; pointer-events: none; font: 12px/1.4 var(--mono); background: var(--panel); color: var(--ink);
  border: 1px solid var(--line); border-radius: 6px; padding: 6px 8px; max-width: 340px; display: none; box-shadow: 0 2px 8px rgba(0,0,0,.15); z-index: 2; }
.toggles { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; }
.key { list-style: none; display: grid; grid-template-columns: repeat(auto-fill, minmax(260px, 1fr)); gap: 6px 16px; padding: 0; margin: 0; font-size: 14px; }
.key li { display: flex; align-items: center; gap: 8px; }
.key i { width: 16px; height: 16px; border-radius: 3px; display: inline-block; border: 1px solid var(--line); flex: none; }
.key b { font: 500 13px var(--mono); margin-left: auto; }
.cap { color: var(--muted); font-size: 14px; }
code, .mono { font: 13px var(--mono); }
.layers { display: grid; gap: 14px; }
.layer h3 { margin: 0 0 4px; font: 600 14px var(--mono); }
.layer .plan { padding: 6px; }
ol.steps { display: grid; gap: 10px; padding-left: 0; list-style: none; counter-reset: s; }
ol.steps > li { background: var(--panel); border: 1px solid var(--line); border-radius: 10px; padding: 12px 16px; counter-increment: s; cursor: pointer; }
ol.steps > li[aria-current="true"] { border-color: var(--copper); box-shadow: inset 4px 0 0 var(--copper); }
ol.steps > li h3 { margin: 0; font-size: 16px; }
ol.steps > li h3::before { content: counter(s) ". "; color: var(--muted); font-family: var(--mono); }
ol.steps > li p { margin: 6px 0 0; }
ol.steps .cells { font: 12px/1.5 var(--mono); color: var(--muted); margin-top: 6px; }
table.clicks td, table.clicks th { padding: 6px 10px; }
</style>
</head>
<body>
<main>
<header>
  <h1>Rack 1: loading bays</h1>
  <p class="lede">What you build by hand so loads reach a docked drone over the cable instead of on a launch pad. Crafty pushes each load and its fuel straight into the drone in its home, and takes hand-ins back the same way. Nothing sticks out: every modem is a full block that is part of the shelf or the wall, and every cable is under the floor or inside the wall.</p>
  <div class="facts">%%CHIPS%%</div>
</header>

<section aria-labelledby="iso-h">
  <h2 id="iso-h">The rack wall in 3D</h2>
  <div class="toggles">
    <button id="rl" aria-label="Turn left">⟲ Turn</button>
    <button id="rr" aria-label="Turn right">Turn ⟳</button>
    <button id="ctx" aria-pressed="true">Existing blocks</button>
    <button id="far" aria-pressed="false">Whole cable run</button>
    <label class="cut">Cut away above y <input type="range" id="cuty" min="-1" max="5" value="5"><output id="cutv">5</output></label>
    <label class="cut">Show up to step <input type="range" id="upto" min="0" max="%%NSTEPS%%" value="%%NSTEPS%%"><output id="uptov">all</output></label>
  </div>
  <div class="plan" id="isoBox"><canvas id="iso" height="560"></canvas><div class="tip" id="isoTip"></div></div>
  <p class="cap">Drag sideways (or use the buttons) to turn it. Seen from the launch bay by default: the lane is behind the rack, the storage room to the left. New blocks are bright; existing ones are pale. Hover a block for its world coordinates.</p>
  <ul class="key" id="key"></ul>
</section>

<section aria-labelledby="layers-h">
  <h2 id="layers-h">Layer by layer</h2>
  <p class="cap">Each slice from above, north up (the lane at the top), x running east. One square is one block. y -1 is under the floor; y 0 is the floor you walk on. Only x 0-28, z 1-5 is shown: the hall's corner on the left, the launch bay on the right.</p>
  <div class="layers" id="layers"></div>
</section>

<section aria-labelledby="steps-h">
  <h2 id="steps-h">Steps</h2>
  <p class="cap">Click a step to light up its blocks above.</p>
  <ol class="steps" id="steps"></ol>
</section>

<section aria-labelledby="click-h">
  <h2 id="click-h">The right-clicks</h2>
  <p>Only the eight shelf modems are clicked, once each, after the strip is up (the strip is what keeps each of them switched on when no drone is docked). One modem serves two homes, the one below it and the one on it, so eight is all there is: it can't be fewer, as each home touches only its own shelf block. The connector modems and the floor plug are never clicked.</p>
  <div class="tablewrap"><table class="clicks"><thead><tr><th>#</th><th>World x y z</th><th>Serves homes</th></tr></thead><tbody id="clicks"></tbody></table></div>
  <p class="cap">If the server ever adds the <code>computercraft:turtle_can_use</code> tag for modems, a drone holding a stick can do these clicks too (docs/cc-lessons.md, 3). It is optional: by hand is the plan.</p>
  <p>Then right-click the computer in the wall (world %%PCW%%) to start it.</p>
</section>
</main>
<script>
const CAT = %%CAT%%;
const CELLS = %%DATA%%;
const STEPS = %%STEPS%%;
const CLICKS = %%CLICKS%%;
const O = [-4448, 71, 1518];
const X0 = %%X0%%, X1 = %%X1%%, Y0 = %%Y0%%, Y1 = %%Y1%%, Z0 = %%Z0%%, Z1 = %%Z1%%;
const dark = () => matchMedia('(prefers-color-scheme: dark)').matches;
const col = (c) => CAT[c][dark() ? 3 : 2];
const world = (x, y, z) => [O[0] + x, O[1] + y, O[2] + z];
const byKey = new Map(CELLS.map(c => [c[0] + ',' + c[1] + ',' + c[2], c]));
let showCtx = true, cutY = Y1, upto = STEPS.length, focus = 0, yaw = 0.62, far = false;
const visible = (c) => {
  const k = CAT[c[3]][4];
  if (k === 'ctx') return showCtx;
  return c[4] <= upto;
};
function describe(c) {
  const [x, y, z, code, step, was] = c;
  const w = world(x, y, z);
  let s = '<b>' + w.join(' ') + '</b> <span style="opacity:.7">(building ' + x + ' ' + y + ' ' + z + ')</span><br>' + CAT[code][1];
  if (step) s += '<br>Step ' + step + ': ' + STEPS[step - 1][0] + (was ? '<br>replaces ' + was : '');
  else s += '<br>' + was;
  return s;
}
// ---------------------------------------------------------------- key
const n = {};
for (const c of CELLS) if (c[4]) n[c[3]] = (n[c[3]] || 0) + 1;
document.getElementById('key').innerHTML = CAT.map((c, i) =>
  '<li><i style="background:' + c[2] + '"></i>' + c[1] + (n[i] ? '<b>' + n[i] + '</b>' : '') + '</li>').join('');
// ---------------------------------------------------------------- the isometric view
const iso = document.getElementById('iso'), isoTip = document.getElementById('isoTip'), isoBox = document.getElementById('isoBox');
let polys = [];
function shade(hex, f) {
  const v = parseInt(hex.slice(1), 16);
  const r = Math.round(((v >> 16) & 255) * f), g = Math.round(((v >> 8) & 255) * f), b = Math.round((v & 255) * f);
  return 'rgb(' + Math.min(255, r) + ',' + Math.min(255, g) + ',' + Math.min(255, b) + ')';
}
function drawIso() {
  const W = isoBox.clientWidth - 2; iso.width = W * devicePixelRatio; iso.style.width = W + 'px';
  const H = 560; iso.height = H * devicePixelRatio; iso.style.height = H + 'px';
  const g = iso.getContext('2d'); g.setTransform(devicePixelRatio, 0, 0, devicePixelRatio, 0, 0);
  g.clearRect(0, 0, W, H);
  const xa = far ? X0 : 14, xb = X1;
  const cs = Math.cos(yaw), sn = Math.sin(yaw), tilt = 0.5;
  const list = CELLS.filter(c => c[0] >= xa && c[0] <= xb && c[1] <= cutY && visible(c));
  const cx = (xa + xb + 1) / 2, cz = (Z0 + Z1 + 1) / 2;
  const span = (xb - xa + 1) * 1.15;
  const S = Math.min(W / span, 52);
  const P = (x, y, z) => { const dx = x - cx, dz = z - cz; const u = dx * cs - dz * sn, v = dx * sn + dz * cs;
    return [W / 2 + u * S, H * 0.62 + v * S * tilt - (y - 1) * S * 0.85]; };
  const depth = (c) => { const dx = c[0] + .5 - cx, dz = c[2] + .5 - cz; return (dx * sn + dz * cs) + c[1] * 0.001; };
  list.sort((a, b) => depth(a) - depth(b) || a[1] - b[1]);
  polys = [];
  const faces = [
    { n: [0, 0, -1], q: [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0]], f: 0.8 },
    { n: [0, 0, 1], q: [[0, 0, 1], [1, 0, 1], [1, 1, 1], [0, 1, 1]], f: 0.8 },
    { n: [-1, 0, 0], q: [[0, 0, 0], [0, 0, 1], [0, 1, 1], [0, 1, 0]], f: 0.65 },
    { n: [1, 0, 0], q: [[1, 0, 0], [1, 0, 1], [1, 1, 1], [1, 1, 0]], f: 0.65 },
    { n: [0, 1, 0], q: [[0, 1, 0], [1, 1, 0], [1, 1, 1], [0, 1, 1]], f: 1.0 },
  ];
  for (const c of list) {
    const [x, y, z, code, step] = c;
    const isNew = CAT[code][4] !== 'ctx';
    const lit = focus && step === focus;
    let base = col(code);
    for (const fc of faces) {
      const nx = fc.n[0], nz = fc.n[2];
      if (fc.n[1] === 0) {
        const v = nx * sn + nz * cs;            // facing the viewer: v > 0
        if (v <= 0) continue;
        const nb = byKey.get((x + nx) + ',' + y + ',' + (z + nz));
        if (nb && visible(nb) && nb[1] <= cutY && nb[0] >= xa && CAT[nb[3]][4] === CAT[code][4] && !isNew) continue;
      } else {
        const nb = byKey.get(x + ',' + (y + 1) + ',' + z);
        if (nb && visible(nb) && y + 1 <= cutY && nb[0] >= xa && !isNew) continue;
      }
      const pts = fc.q.map(p => P(x + p[0], y + p[1], z + p[2]));
      g.beginPath(); pts.forEach((p, i) => i ? g.lineTo(p[0], p[1]) : g.moveTo(p[0], p[1])); g.closePath();
      g.globalAlpha = isNew ? 1 : (focus ? 0.25 : 0.55);
      g.fillStyle = shade(base, fc.f * (lit ? 1.15 : 1)); g.fill();
      g.globalAlpha = 1;
      g.strokeStyle = lit ? (dark() ? '#fff' : '#000') : 'rgba(0,0,0,' + (isNew ? .35 : .12) + ')';
      g.lineWidth = lit ? 1.6 : 0.7; g.stroke();
      if (code === 0 && fc.n[1] === 1) {        // the bay modems: a ring to say "click"
        const m = P(x + .5, y + 1, z + .5); g.beginPath(); g.arc(m[0], m[1], S * 0.18, 0, 7);
        g.strokeStyle = dark() ? '#fff' : '#000'; g.lineWidth = 1.4; g.stroke();
      }
      if (code === 5 && fc.n[1] === 1) {        // take out: a cross
        const a = P(x + .2, y + 1, z + .2), b = P(x + .8, y + 1, z + .8), c2 = P(x + .8, y + 1, z + .2), d = P(x + .2, y + 1, z + .8);
        g.beginPath(); g.moveTo(a[0], a[1]); g.lineTo(b[0], b[1]); g.moveTo(c2[0], c2[1]); g.lineTo(d[0], d[1]);
        g.strokeStyle = '#fff'; g.lineWidth = 2; g.stroke();
      }
      polys.push([pts, c]);
    }
  }
  // the compass: which way is north
  const a = P(cx, Y0, cz), b = P(cx, Y0, cz - 3);
  const ang = Math.atan2(b[1] - a[1], b[0] - a[0]);
  g.save(); g.translate(W - 46, 46); g.rotate(ang + Math.PI / 2);
  g.fillStyle = dark() ? '#e9e8e4' : '#23242a'; g.beginPath(); g.moveTo(0, -18); g.lineTo(7, 8); g.lineTo(0, 3); g.lineTo(-7, 8); g.fill();
  g.restore(); g.font = '600 12px IBM Plex Mono, monospace'; g.fillStyle = dark() ? '#e9e8e4' : '#23242a';
  g.fillText('N', W - 50, 82);
}
function inPoly(pt, ps) {
  let inside = false;
  for (let i = 0, j = ps.length - 1; i < ps.length; j = i++) {
    const [xi, yi] = ps[i], [xj, yj] = ps[j];
    if ((yi > pt[1]) !== (yj > pt[1]) && pt[0] < (xj - xi) * (pt[1] - yi) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}
let drag = null;
iso.addEventListener('pointerdown', e => { drag = { x: e.clientX, yaw }; iso.setPointerCapture(e.pointerId); });
iso.addEventListener('pointerup', () => { drag = null; });
iso.addEventListener('pointermove', e => {
  const r = iso.getBoundingClientRect();
  if (drag) { yaw = drag.yaw + (e.clientX - drag.x) * 0.01; drawIso(); isoTip.style.display = 'none'; return; }
  const pt = [e.clientX - r.left, e.clientY - r.top];
  for (let i = polys.length - 1; i >= 0; i--) {
    if (inPoly(pt, polys[i][0])) {
      isoTip.innerHTML = describe(polys[i][1]); isoTip.style.display = 'block';
      isoTip.style.left = Math.min(pt[0] + 14, r.width - 300) + 'px'; isoTip.style.top = (pt[1] + 14) + 'px';
      return;
    }
  }
  isoTip.style.display = 'none';
});
iso.addEventListener('pointerleave', () => { isoTip.style.display = 'none'; });
const press = (id, v) => document.getElementById(id).setAttribute('aria-pressed', v ? 'true' : 'false');
document.getElementById('rl').onclick = () => { yaw -= Math.PI / 4; drawIso(); };
document.getElementById('rr').onclick = () => { yaw += Math.PI / 4; drawIso(); };
document.getElementById('ctx').onclick = () => { showCtx = !showCtx; press('ctx', showCtx); drawAll(); };
document.getElementById('far').onclick = () => { far = !far; press('far', far); drawIso(); };
document.getElementById('cuty').oninput = e => { cutY = +e.target.value; document.getElementById('cutv').textContent = cutY; drawIso(); };
document.getElementById('upto').oninput = e => { upto = +e.target.value; document.getElementById('uptov').textContent = upto === STEPS.length ? 'all' : upto; drawAll(); };
// ---------------------------------------------------------------- the layers
const layers = document.getElementById('layers');
const LCV = [];
for (let y = Y1; y >= Y0; y--) {
  const d = document.createElement('div'); d.className = 'layer';
  const wy = O[1] + y;
  d.innerHTML = '<h3>y ' + y + ' &nbsp;<span style="color:var(--muted);font-weight:400">world y ' + wy + (y === 0 ? ' · the floor' : y === -1 ? ' · under the floor' : '') + '</span></h3>' +
    '<div class="plan"><canvas></canvas><div class="tip"></div></div>';
  layers.appendChild(d);
  LCV.push([y, d.querySelector('canvas'), d.querySelector('.tip'), d.querySelector('.plan')]);
}
function drawLayer([y, cv, tip, box]) {
  const nx = X1 - X0 + 1, nz = Z1 - Z0 + 1;
  const S = Math.max(16, Math.min(30, Math.floor((box.clientWidth - 70) / nx)));
  const L = 34, T = 18;
  const W = L + nx * S + 8, H = T + nz * S + 6;
  cv.width = W * devicePixelRatio; cv.height = H * devicePixelRatio; cv.style.width = W + 'px'; cv.style.height = H + 'px';
  const g = cv.getContext('2d'); g.setTransform(devicePixelRatio, 0, 0, devicePixelRatio, 0, 0);
  g.font = '11px IBM Plex Mono, monospace'; g.fillStyle = dark() ? '#a2a3aa' : '#5e6068';
  for (let x = X0; x <= X1; x++) if (x % 2 === 0) g.fillText(String(x), L + (x - X0) * S + 2, 12);
  for (let z = Z0; z <= Z1; z++) g.fillText('z' + z, 2, T + (z - Z0) * S + S * 0.65);
  for (let x = X0; x <= X1; x++) for (let z = Z0; z <= Z1; z++) {
    const c = byKey.get(x + ',' + y + ',' + z);
    const px = L + (x - X0) * S, pz = T + (z - Z0) * S;
    g.strokeStyle = dark() ? '#2c2d33' : '#e4e2dc'; g.strokeRect(px + .5, pz + .5, S - 1, S - 1);
    if (!c || !visible(c)) continue;
    const isNew = CAT[c[3]][4] !== 'ctx';
    g.globalAlpha = isNew ? 1 : (focus ? 0.25 : 0.5);
    g.fillStyle = col(c[3]); g.fillRect(px + 1, pz + 1, S - 2, S - 2); g.globalAlpha = 1;
    if (focus && c[4] === focus) { g.strokeStyle = dark() ? '#fff' : '#000'; g.lineWidth = 2; g.strokeRect(px + 2, pz + 2, S - 4, S - 4); g.lineWidth = 1; }
    if (isNew) {
      g.fillStyle = '#fff'; g.font = '600 ' + Math.round(S * 0.42) + 'px IBM Plex Mono, monospace';
      const t = c[3] === 0 ? '◎' : c[3] === 5 ? '×' : String(c[4]);
      g.fillText(t, px + S * 0.28, pz + S * 0.68); g.font = '11px IBM Plex Mono, monospace';
    }
  }
  cv.onmousemove = e => {
    const r = cv.getBoundingClientRect();
    const x = X0 + Math.floor((e.clientX - r.left - L) / S), z = Z0 + Math.floor((e.clientY - r.top - T) / S);
    const c = byKey.get(x + ',' + y + ',' + z);
    if (!c || x < X0 || x > X1 || z < Z0 || z > Z1) { tip.style.display = 'none'; return; }
    tip.innerHTML = describe(c); tip.style.display = 'block';
    tip.style.left = Math.min(e.clientX - r.left + 14, box.clientWidth - 300) + 'px'; tip.style.top = (e.clientY - r.top + 14) + 'px';
  };
  cv.onmouseleave = () => { tip.style.display = 'none'; };
}
// ---------------------------------------------------------------- steps and clicks
const stepsEl = document.getElementById('steps');
stepsEl.innerHTML = STEPS.map((s, i) => '<li tabindex="0" data-i="' + (i + 1) + '"><h3>' + s[0] + '</h3><p>' + s[1] + '</p>' +
  (s[2].length ? '<div class="cells">' + s[2].join('<br>') + '</div>' : '') + '</li>').join('');
for (const li of stepsEl.children) {
  const pick = () => { const i = +li.dataset.i; focus = focus === i ? 0 : i;
    for (const o of stepsEl.children) o.setAttribute('aria-current', String(+o.dataset.i === focus)); drawAll(); };
  li.onclick = pick; li.onkeydown = e => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); pick(); } };
}
document.getElementById('clicks').innerHTML = CLICKS.map((c, i) =>
  '<tr><td class="num">' + (i + 1) + '</td><td class="mono">' + c.join(' ') + '</td><td class="mono">low ' + c[0] + ' ' + (c[1] - 1) + ' ' + c[2] + ' · high ' + c[0] + ' ' + (c[1] + 1) + ' ' + c[2] + '</td></tr>').join('');
function drawAll() { drawIso(); LCV.forEach(drawLayer); }
addEventListener('resize', drawAll);
matchMedia('(prefers-color-scheme: dark)').addEventListener('change', drawAll);
drawAll();
</script>
</body>
</html>
"""


def write():
    src = open(os.path.join(ROOT, "docs", "factory-plan.html"), encoding="utf-8").read()
    css = src[src.index("<style>") + 7:src.index("</style>")]
    css = css[:css.index("/* the model */")] + css[css.index("/* rooms */"):]
    n = counts()
    chips = [f"{n['bay']} bay modems serve 16 homes", f"{n['conn']} connector modems", f"{n['cable']} cables",
             f"{n['mon']} advanced monitors", "1 computer (moved)", f"{len(clicks())} right-clicks",
             "Corner -4448, 71, 1518 · north up"]
    steps = []
    for title, text, parts in STEPS:
        lines = []
        for code, cells in parts:
            ws = ", ".join(" ".join(map(str, R.W(*c))) for c in cells)
            lines.append(f"{CAT[CODE[code]][1].split(':')[0]} × {len(cells)}: {ws}")
        steps.append([title, text, lines])
    html = (PAGE.replace("%%CSS%%", css.strip())
            .replace("%%CHIPS%%", "".join(f'<span class="chip">{c}</span>' for c in chips))
            .replace("%%CAT%%", json.dumps(CAT)).replace("%%DATA%%", json.dumps(data(), separators=(",", ":")))
            .replace("%%STEPS%%", json.dumps(steps)).replace("%%CLICKS%%", json.dumps(clicks()))
            .replace("%%NSTEPS%%", str(len(STEPS))).replace("%%PCW%%", " ".join(map(str, R.W(*R.RACK_PC))))
            .replace("%%X0%%", str(X0)).replace("%%X1%%", str(X1)).replace("%%Y0%%", str(Y0))
            .replace("%%Y1%%", str(Y1)).replace("%%Z0%%", str(Z0)).replace("%%Z1%%", str(Z1)))
    out = os.path.join(ROOT, "docs", "rack-build.html")
    with open(out, "w", encoding="utf-8") as f:
        f.write(html)
    return out, len(html)


if __name__ == "__main__":
    print("wrote %s (%d bytes)" % write())
