// Procedural pixel art. Everything is drawn in "world pixels" (16 per tile);
// the game canvas scales it up with smoothing off, so it stays crisp.
"use strict";

const T = 16;
const PAL = {
  grass: "#8cc56a", grassDark: "#77b05a", grassLight: "#a6d884", grassDeep: "#6a9f50",
  dirt: "#dcbb88", dirtDark: "#c7a26e", dirtLight: "#ebd2a5",
  cobble: "#c3b9a8", cobbleDark: "#a59b8b", cobbleLight: "#d9d0c0", mortar: "#9a907f",
  water: "#5aa7d6", waterDark: "#3f86b8", waterLight: "#9ad3f0", sand: "#e6d3a3",
  trunk: "#7a5232", trunkDark: "#5b3c24", leaf: "#4f9a46", leafDark: "#3c7d39", leafLight: "#6fbb5a",
  wood: "#9c6b43", woodDark: "#6e4729", woodLight: "#c08d5e", stone: "#a49d92", stoneDark: "#7f786e",
  ink: "#2b2622", paper: "#fff8ea",
};

function hash(x, y, s = 0) {
  let h = (x * 374761393 + y * 668265263 + s * 1442695041) | 0;
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
}
function shade(hex, amt) {
  const n = parseInt(hex.slice(1), 16);
  const c = (v) => Math.max(0, Math.min(255, v + amt));
  return `rgb(${c(n >> 16)},${c((n >> 8) & 255)},${c(n & 255)})`;
}
function px(ctx, x, y, w, h, c) { ctx.fillStyle = c; ctx.fillRect(x, y, w, h); }

// ------------------------------------------------------------------ terrain
function drawGrass(ctx, x, y) {
  const X = x * T, Y = y * T;
  px(ctx, X, Y, T, T, hash(x, y, 9) < 0.5 ? PAL.grass : shade(PAL.grass, -4));
  for (let i = 0; i < 5; i++) {
    const r = hash(x, y, i), r2 = hash(x, y, i + 20);
    const bx = X + Math.floor(r * 15), by = Y + Math.floor(r2 * 14);
    px(ctx, bx, by, 1, 2, i % 2 ? PAL.grassDark : PAL.grassLight);
  }
  if (hash(x, y, 77) < 0.06) { px(ctx, X + 6, Y + 7, 1, 1, "#fff"); px(ctx, X + 10, Y + 4, 1, 1, "#ffd84a"); }
}

function drawDirt(ctx, x, y, grid) {
  const X = x * T, Y = y * T;
  px(ctx, X, Y, T, T, PAL.dirt);
  for (let i = 0; i < 4; i++) {
    const bx = X + Math.floor(hash(x, y, i + 3) * 14), by = Y + Math.floor(hash(x, y, i + 8) * 14);
    px(ctx, bx, by, 2, 1, i % 2 ? PAL.dirtDark : PAL.dirtLight);
  }
  const g = (dx, dy) => { const c = (grid[y + dy] || "")[x + dx]; return c && !"pc".includes(c) && c !== "B"; };
  for (let i = 0; i < T; i += 2) {
    const j = hash(x, y, i) < 0.5 ? 1 : 2;
    if (g(0, -1)) px(ctx, X + i, Y, 2, j, PAL.grassDark);
    if (g(0, 1)) px(ctx, X + i, Y + T - j, 2, j, PAL.grassDark);
    if (g(-1, 0)) px(ctx, X, Y + i, j, 2, PAL.grassDark);
    if (g(1, 0)) px(ctx, X + T - j, Y + i, j, 2, PAL.grassDark);
  }
}

function drawCobble(ctx, x, y) {
  const X = x * T, Y = y * T;
  px(ctx, X, Y, T, T, PAL.mortar);
  for (let row = 0; row < 4; row++) {
    const off = (row + y) % 2 ? 0 : -3;
    for (let col = off; col < T; col += 6) {
      const sx = Math.max(X, X + col), ex = Math.min(X + T, X + col + 5);
      if (ex <= sx) continue;
      const r = hash(x * 4 + col, y * 4 + row, 2);
      px(ctx, sx, Y + row * 4, ex - sx, 3, r < 0.33 ? PAL.cobble : r < 0.66 ? PAL.cobbleLight : shade(PAL.cobble, -8));
      px(ctx, sx, Y + row * 4, ex - sx, 1, PAL.cobbleLight);
    }
  }
}

function drawWater(ctx, x, y, grid) {
  const X = x * T, Y = y * T;
  px(ctx, X, Y, T, T, PAL.water);
  const w = (dx, dy) => (grid[y + dy] || "")[x + dx] === "w";
  if (!w(0, -1)) { px(ctx, X, Y, T, 3, PAL.sand); px(ctx, X, Y + 3, T, 1, PAL.waterDark); }
  if (!w(0, 1)) px(ctx, X, Y + T - 2, T, 2, PAL.sand);
  if (!w(-1, 0)) { px(ctx, X, Y, 2, T, PAL.sand); px(ctx, X + 2, Y, 1, T, PAL.waterDark); }
  if (!w(1, 0)) px(ctx, X + T - 2, Y, 2, T, PAL.sand);
}

function drawFlowers(ctx, x, y) {
  drawGrass(ctx, x, y);
  const cols = ["#f28b82", "#fbd75b", "#ffffff", "#c58af9", "#f6a5c0"];
  for (let i = 0; i < 6; i++) {
    const fx = x * T + 2 + Math.floor(hash(x, y, i + 40) * 11), fy = y * T + 3 + Math.floor(hash(x, y, i + 50) * 10);
    px(ctx, fx, fy + 1, 1, 2, PAL.leafDark);
    px(ctx, fx - 1, fy, 3, 1, cols[(i + x) % cols.length]);
    px(ctx, fx, fy - 1, 1, 3, cols[(i + x) % cols.length]);
    px(ctx, fx, fy, 1, 1, "#fff3b0");
  }
}

function drawFence(ctx, x, y, grid) {
  const X = x * T, Y = y * T;
  const f = (dx, dy) => (grid[y + dy] || "")[x + dx] === "x";
  px(ctx, X + 6, Y + 3, 4, 11, PAL.woodDark); px(ctx, X + 6, Y + 3, 3, 10, PAL.woodLight);
  if (f(1, 0) || f(-1, 0)) {
    px(ctx, X, Y + 6, T, 2, PAL.wood); px(ctx, X, Y + 10, T, 2, PAL.wood);
    px(ctx, X, Y + 8, T, 1, PAL.woodDark); px(ctx, X, Y + 12, T, 1, PAL.woodDark);
  }
  if (f(0, 1) || f(0, -1)) px(ctx, X + 7, Y, 2, T, PAL.wood);
}

function drawBench(ctx, x, y) {
  const X = x * T, Y = y * T;
  px(ctx, X + 1, Y + 11, 14, 2, "rgba(0,0,0,.15)");
  px(ctx, X + 2, Y + 9, 2, 4, PAL.woodDark); px(ctx, X + 12, Y + 9, 2, 4, PAL.woodDark);
  px(ctx, X + 1, Y + 7, 14, 3, PAL.wood); px(ctx, X + 1, Y + 7, 14, 1, PAL.woodLight);
  px(ctx, X + 1, Y + 3, 14, 3, PAL.wood); px(ctx, X + 1, Y + 3, 14, 1, PAL.woodLight);
}

function drawLampBase(ctx, x, y) {
  const X = x * T, Y = y * T;
  px(ctx, X + 4, Y + 13, 8, 2, "rgba(0,0,0,.2)");
  px(ctx, X + 6, Y + 12, 4, 3, "#3b3f4a");
  px(ctx, X + 7, Y - 4, 2, 16, "#4a4f5c");
}
function drawLampHead(ctx, x, y) {
  const X = x * T, Y = y * T;
  px(ctx, X + 4, Y - 10, 8, 2, "#3b3f4a");
  px(ctx, X + 5, Y - 8, 6, 5, "#ffe9a8"); px(ctx, X + 5, Y - 8, 1, 5, "#3b3f4a"); px(ctx, X + 10, Y - 8, 1, 5, "#3b3f4a");
  px(ctx, X + 5, Y - 3, 6, 1, "#3b3f4a"); px(ctx, X + 7, Y - 12, 2, 2, "#3b3f4a");
}

function drawTreeTrunk(ctx, x, y) {
  const X = x * T, Y = y * T;
  ctx.fillStyle = "rgba(0,0,0,.18)";
  ctx.beginPath(); ctx.ellipse(X + 9, Y + 14, 8, 3, 0, 0, Math.PI * 2); ctx.fill();
  px(ctx, X + 6, Y + 6, 4, 9, PAL.trunk); px(ctx, X + 9, Y + 6, 1, 9, PAL.trunkDark);
  px(ctx, X + 5, Y + 14, 6, 1, PAL.trunkDark);
}
function blob(ctx, cx, cy, r, c) {
  ctx.fillStyle = c;
  for (let dy = -r; dy <= r; dy++) {
    const w = Math.round(Math.sqrt(r * r - dy * dy));
    ctx.fillRect(cx - w, cy + dy, w * 2, 1);
  }
}
function drawTreeCanopy(ctx, x, y) {
  const X = x * T + 8, Y = y * T + 2, v = hash(x, y, 5);
  const r = 7 + Math.round(v * 2);
  blob(ctx, X + 1, Y + 1, r, PAL.leafDark);
  blob(ctx, X, Y - 1, r - 1, PAL.leaf);
  blob(ctx, X - 2, Y - 3, Math.max(3, r - 4), PAL.leafLight);
  px(ctx, X - 3, Y - 5, 2, 1, "#9bd47c");
  if (v > 0.65) { px(ctx, X + 3, Y, 2, 2, "#e8504f"); px(ctx, X - 4, Y + 2, 2, 2, "#e8504f"); }
}

// --------------------------------------------------------------- fountain
function drawFountain(ctx, x, y) {
  const X = x * T, Y = y * T, W = 4 * T, H = 3 * T;
  ctx.fillStyle = "rgba(0,0,0,.15)";
  ctx.beginPath(); ctx.ellipse(X + W / 2 + 2, Y + H / 2 + 4, W / 2, H / 2 - 2, 0, 0, 7); ctx.fill();
  ctx.fillStyle = PAL.stoneDark; ctx.beginPath(); ctx.ellipse(X + W / 2, Y + H / 2 + 2, W / 2 - 1, H / 2 - 2, 0, 0, 7); ctx.fill();
  ctx.fillStyle = PAL.cobbleLight; ctx.beginPath(); ctx.ellipse(X + W / 2, Y + H / 2, W / 2 - 1, H / 2 - 3, 0, 0, 7); ctx.fill();
  ctx.fillStyle = PAL.waterDark; ctx.beginPath(); ctx.ellipse(X + W / 2, Y + H / 2 + 1, W / 2 - 6, H / 2 - 8, 0, 0, 7); ctx.fill();
  ctx.fillStyle = PAL.water; ctx.beginPath(); ctx.ellipse(X + W / 2, Y + H / 2 + 2, W / 2 - 7, H / 2 - 9, 0, 0, 7); ctx.fill();
  px(ctx, X + W / 2 - 3, Y + H / 2 - 10, 6, 14, PAL.stone);
  px(ctx, X + W / 2 - 3, Y + H / 2 - 10, 2, 14, PAL.cobbleLight);
  px(ctx, X + W / 2 - 8, Y + H / 2 - 13, 16, 4, PAL.stone);
  px(ctx, X + W / 2 - 8, Y + H / 2 - 13, 16, 1, PAL.cobbleLight);
  px(ctx, X + W / 2 - 6, Y + H / 2 - 12, 12, 1, PAL.waterLight);
}

// -------------------------------------------------------------- buildings
const ICONS = {
  book: ["..#####.", ".#ppppp#", "#pp#pp#.", "#pppppp#", "#pp#pp#.", ".#######", "........"],
  letter: ["########", "#w....w#", "#.w..w.#", "#..ww..#", "#......#", "########", "........"],
  flag: ["#rrrrr..", "#rrrrrr.", "#rrrrr..", "#.......", "#.......", "#.......", "##......"],
};
function drawIcon(ctx, x, y, name, colors) {
  const rows = ICONS[name]; if (!rows) return;
  rows.forEach((row, j) => [...row].forEach((ch, i) => { if (ch !== ".") px(ctx, x + i, y + j, 1, 1, colors[ch] || colors["#"]); }));
}

function drawBuilding(ctx, id, L, extras) {
  const X = L.x * T, Y = L.y * T, W = L.w * T, H = L.h * T;
  const roofH = Math.round(H * 0.5), wallTop = Y + roofH - 3, wallH = Y + H - wallTop;
  // shadow
  px(ctx, X + 5, Y + 8, W, H, "rgba(30,40,20,.22)");
  // walls
  px(ctx, X, wallTop, W, wallH, L.wall);
  const brick = id === "town_hall";
  for (let yy = wallTop + 3; yy < Y + H - 4; yy += 4) {
    px(ctx, X, yy, W, 1, shade(L.wall, -18));
    if (brick) for (let xx = X + ((yy / 4) % 2 ? 2 : 6); xx < X + W; xx += 8) px(ctx, xx, yy - 3, 1, 3, shade(L.wall, -14));
  }
  px(ctx, X, wallTop, 2, wallH, shade(L.wall, 18)); px(ctx, X + W - 2, wallTop, 2, wallH, shade(L.wall, -26));
  px(ctx, X, Y + H - 4, W, 4, PAL.stoneDark); px(ctx, X, Y + H - 4, W, 1, PAL.stone);
  // windows
  const doorX = L.door[0] * T;
  const winY = wallTop + Math.round((wallH - 4) / 2) - 5;
  for (let wx = X + 8; wx <= X + W - 18; wx += 22) {
    if (Math.abs(wx + 5 - (doorX + 8)) < 20) continue;
    px(ctx, wx - 1, winY - 1, 12, 12, L.trim);
    px(ctx, wx, winY, 10, 10, "#8fc9e3"); px(ctx, wx, winY, 10, 4, "#b6e0f1");
    px(ctx, wx + 4, winY, 2, 10, L.trim); px(ctx, wx, winY + 4, 10, 2, L.trim);
    px(ctx, wx - 2, winY + 10, 14, 2, shade(L.trim, -30));
    px(ctx, wx, winY + 12, 10, 2, "#e86a6a"); px(ctx, wx + 2, winY + 12, 2, 1, "#ffd84a"); px(ctx, wx + 6, winY + 12, 2, 1, "#ffffff");
    extras.windows.push([wx, winY, 10, 10]);
  }
  // door + sign
  px(ctx, doorX + 1, Y + H - 21, 14, 21, L.trim);
  px(ctx, doorX + 3, Y + H - 19, 10, 19, "#5b3a24"); px(ctx, doorX + 3, Y + H - 19, 10, 1, "#7a5232");
  px(ctx, doorX + 7, Y + H - 19, 1, 19, "#47301e"); px(ctx, doorX + 10, Y + H - 10, 1, 1, "#ffd84a");
  px(ctx, doorX - 4, Y + H - 33, 24, 11, PAL.woodDark); px(ctx, doorX - 3, Y + H - 32, 22, 9, PAL.woodLight);
  drawIcon(ctx, doorX + 4, Y + H - 31, L.icon, { "#": PAL.ink, p: PAL.paper, w: PAL.paper, r: "#d94b4b" });
  // roof
  const ov = 5;
  ctx.fillStyle = L.roof;
  ctx.beginPath();
  ctx.moveTo(X - ov, wallTop + 4); ctx.lineTo(X + 8, Y); ctx.lineTo(X + W - 8, Y); ctx.lineTo(X + W + ov, wallTop + 4);
  ctx.closePath(); ctx.fill();
  for (let yy = Y + 4, r = 0; yy < wallTop + 4; yy += 4, r++) {
    const t = (yy - Y) / (wallTop + 4 - Y);
    const lx = X + 8 - (8 + ov) * t, rx = X + W - 8 + (8 + ov) * t;
    px(ctx, Math.round(lx), yy, Math.round(rx - lx), 1, shade(L.roof, -22));
    for (let xx = Math.round(lx) + (r % 2 ? 3 : 7); xx < rx - 2; xx += 8) px(ctx, xx, yy - 3, 1, 3, shade(L.roof, -14));
  }
  px(ctx, X + 8, Y, W - 16, 2, shade(L.roof, 28));
  px(ctx, X - ov, wallTop + 4, W + ov * 2, 2, shade(L.roof, -40));
  px(ctx, X, wallTop + 6, W, 2, "rgba(0,0,0,.18)");
  // per-building flourishes
  if (id === "town_hall") {
    const cx = X + W / 2;
    px(ctx, cx - 10, Y - 16, 20, 20, L.trim); px(ctx, cx - 10, Y - 16, 2, 20, "#fff");
    px(ctx, cx - 9, Y - 16, 18, 1, shade(L.trim, -30));
    ctx.fillStyle = L.roof; ctx.beginPath(); ctx.moveTo(cx - 13, Y - 15); ctx.lineTo(cx, Y - 28); ctx.lineTo(cx + 13, Y - 15); ctx.fill();
    blob(ctx, cx, Y - 7, 6, "#fffdf5"); blob(ctx, cx, Y - 7, 5, "#f7efd9");
    px(ctx, cx, Y - 11, 1, 5, PAL.ink); px(ctx, cx, Y - 7, 4, 1, PAL.ink);
    px(ctx, cx - 1, Y - 40, 1, 13, "#4a4f5c");
    extras.flags.push([cx, Y - 40]);
    // columns by the door
    for (const dx of [-12, 22]) { px(ctx, doorX + dx, wallTop + 8, 4, Y + H - wallTop - 12, "#f3e3c8"); px(ctx, doorX + dx + 3, wallTop + 8, 1, Y + H - wallTop - 12, "#d4c3a3"); }
  }
  if (id === "library" || id === "post_office") {
    const chx = id === "library" ? X + 18 : X + W - 26;
    px(ctx, chx, Y - 8, 8, 14, "#8a5a44"); px(ctx, chx - 1, Y - 10, 10, 3, "#6b4434");
    px(ctx, chx + 1, Y - 6, 2, 10, "#a06b52");
    extras.chimneys.push([chx + 4, Y - 11]);
  }
  if (id === "post_office") {
    const mx = doorX + 22, my = Y + H + 1;
    px(ctx, mx + 2, my + 6, 2, 8, "#3b3f4a");
    px(ctx, mx, my, 7, 7, "#d64541"); px(ctx, mx, my, 7, 2, "#e8726e"); px(ctx, mx + 1, my + 3, 5, 1, PAL.ink);
  }
  if (id === "library") {
    for (const dx of [-14, 24]) { px(ctx, doorX + dx, wallTop + 6, 5, Y + H - wallTop - 10, "#e8dcc0"); px(ctx, doorX + dx + 4, wallTop + 6, 1, Y + H - wallTop - 10, "#c9bb98"); }
  }
}

// ------------------------------------------------------------- characters
// (px,py) = feet centre in world pixels. Returns nothing; draws ~12x20 sprite.
function drawVillager(ctx, v, X, Y, t, walking, selected) {
  const f = walking ? Math.floor(t * 8) % 4 : 0;
  const bob = walking ? (f % 2) : (Math.floor(t * 1.6) % 2 ? 0 : 0);
  const dir = v.facing || "down";
  const by = Y - bob;
  ctx.fillStyle = "rgba(0,0,0,.22)"; ctx.beginPath(); ctx.ellipse(X, Y, 5, 2, 0, 0, 7); ctx.fill();
  if (selected) {
    const p = 1 + Math.sin(t * 6) * 0.5;
    ctx.strokeStyle = "#fff6c2"; ctx.lineWidth = 1;
    ctx.beginPath(); ctx.ellipse(X, Y, 8 + p, 3.5 + p / 2, 0, 0, 7); ctx.stroke();
  }
  const pants = "#45405a", body = v.color, bodyDark = shade(v.color, -30), skin = v.skin, hair = v.hair;
  // legs
  const l1 = f === 1 ? -1 : 0, l2 = f === 3 ? -1 : 0;
  px(ctx, X - 3, by - 5 + l1, 2, 5 - (l1 ? 0 : 0), pants); px(ctx, X + 1, by - 5 + l2, 2, 5, pants);
  px(ctx, X - 3, by - 1 + l1, 2, 1, "#2b2622"); px(ctx, X + 1, by - 1 + l2, 2, 1, "#2b2622");
  // backpack behind (Leo)
  if (v.id === "leo" && dir !== "down") px(ctx, dir === "left" ? X + 1 : X - 5, by - 12, 5, 6, "#7a5230");
  // body
  px(ctx, X - 4, by - 11, 8, 7, body); px(ctx, X + 2, by - 11, 2, 7, bodyDark);
  px(ctx, X - 4, by - 6, 8, 1, v.accent);
  if (v.id === "ada") { px(ctx, X - 3, by - 11, 1, 1, v.accent); px(ctx, X - 2, by - 10, 1, 1, v.accent); px(ctx, X - 1, by - 9, 1, 1, v.accent); px(ctx, X, by - 8, 1, 1, v.accent); px(ctx, X + 1, by - 7, 1, 1, v.accent); }
  if (v.id === "maya") { px(ctx, X - 4, by - 11, 8, 2, "#e9d8a6"); }
  // arms
  const sw = walking ? (f === 1 ? 1 : f === 3 ? -1 : 0) : 0;
  if (dir !== "right") { px(ctx, X - 6, by - 10 + sw, 2, 5, body); px(ctx, X - 6, by - 6 + sw, 2, 1, skin); }
  if (dir !== "left") { px(ctx, X + 4, by - 10 - sw, 2, 5, bodyDark); px(ctx, X + 4, by - 6 - sw, 2, 1, skin); }
  // head
  const hx = X - 4, hy = by - 19;
  px(ctx, hx, hy, 8, 8, skin);
  if (dir === "up") px(ctx, hx, hy, 8, 7, hair);
  else {
    px(ctx, hx, hy, 8, 3, hair);
    if (dir === "left") px(ctx, hx + 5, hy, 3, 6, hair);
    else if (dir === "right") px(ctx, hx, hy, 3, 6, hair);
    else { px(ctx, hx, hy, 1, 5, hair); px(ctx, hx + 7, hy, 1, 5, hair); }
    if (v.id === "maya") { px(ctx, hx - 1, hy + 1, 1, 7, hair); px(ctx, hx + 8, hy + 1, 1, 7, hair); }
    const eyeY = hy + 4;
    const blink = Math.floor(t * 0.7 + v.id.length) % 6 === 0 && (t * 0.7 % 1) < 0.15;
    const eh = blink ? 1 : 2;
    if (dir === "down") { px(ctx, hx + 2, eyeY, 1, eh, PAL.ink); px(ctx, hx + 5, eyeY, 1, eh, PAL.ink); px(ctx, hx + 1, eyeY + 2, 1, 1, "#f08f8f"); px(ctx, hx + 6, eyeY + 2, 1, 1, "#f08f8f"); }
    if (dir === "left") px(ctx, hx + 1, eyeY, 1, eh, PAL.ink);
    if (dir === "right") px(ctx, hx + 6, eyeY, 1, eh, PAL.ink);
  }
  // hats
  if (v.hat === "tophat") {
    px(ctx, hx - 1, hy - 1, 10, 2, "#2b2a33"); px(ctx, hx + 1, hy - 7, 6, 6, "#2b2a33");
    px(ctx, hx + 1, hy - 3, 6, 1, v.accent); px(ctx, hx + 1, hy - 7, 1, 6, "#45444f");
  } else if (v.hat === "cap") {
    px(ctx, hx, hy - 2, 8, 3, "#7a5230"); px(ctx, hx + 1, hy - 3, 6, 1, "#7a5230"); px(ctx, hx + 2, hy - 2, 2, 1, "#9c6b43");
    if (dir === "left") px(ctx, hx - 3, hy, 4, 1, "#5b3c24");
    else if (dir === "right") px(ctx, hx + 7, hy, 4, 1, "#5b3c24");
    else if (dir === "down") px(ctx, hx - 1, hy, 10, 1, "#5b3c24");
  } else if (v.hat === "beret") {
    px(ctx, hx - 1, hy - 2, 9, 3, "#c0504d"); px(ctx, hx + 1, hy - 3, 6, 1, "#c0504d"); px(ctx, hx + 4, hy - 4, 1, 1, "#8f3a38");
    px(ctx, hx, hy - 2, 3, 1, "#d97370");
  }
}

// little icon bubbles over working villagers
function drawWorkBadge(ctx, X, Y, icon, progress, t) {
  const bx = X - 8, by = Y - 34 + Math.round(Math.sin(t * 4)), w = 16, h = 13;
  px(ctx, bx, by, w, h, PAL.ink); px(ctx, bx + 1, by + 1, w - 2, h - 2, PAL.paper);
  px(ctx, X - 1, by + h, 3, 1, PAL.ink); px(ctx, X, by + h + 1, 1, 1, PAL.ink);
  const name = icon === "📚" ? "book" : icon === "✉️" ? "letter" : "flag";
  drawIcon(ctx, bx + 4, by + 2, name, { "#": PAL.ink, p: "#fff", w: "#fff", r: "#d94b4b" });
  if (progress != null) {
    px(ctx, bx + 2, by + h - 3, w - 4, 2, "#d8cfbd");
    px(ctx, bx + 2, by + h - 3, Math.max(1, Math.round((w - 4) * progress)), 2, "#5aa45a");
  }
}

window.Art = { T, PAL, px, hash, shade, blob, drawGrass, drawDirt, drawCobble, drawWater, drawFlowers, drawFence,
  drawBench, drawLampBase, drawLampHead, drawTreeTrunk, drawTreeCanopy, drawFountain, drawBuilding, drawVillager,
  drawWorkBadge };
