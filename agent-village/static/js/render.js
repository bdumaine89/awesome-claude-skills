// Village renderer using LPC pixel art (see static/assets/CREDITS.md).
// Ground is pre-rendered once with autotiles; buildings, props and villagers
// are y-sorted every frame so villagers walk behind trees and in front of walls.
"use strict";

const Game = (() => {
  const T = 32;
  const A = {};                 // loaded images
  let SPR = {};                 // atlas index
  let map, WW, WH, canvas, ctx, ground, light, lctx;
  let state = null, selected = null, hover = null, onSelect = () => {};
  const shown = {};             // id -> smoothed position + anim
  const particles = [];
  const cam = { zoom: 1, x: 0, y: 0, follow: false };
  let scale = 1, dpr = 1, last = performance.now();

  const load = (src) => new Promise((ok, bad) => { const i = new Image(); i.onload = () => ok(i); i.onerror = bad; i.src = src; });

  async function init(m, cv) {
    map = m; canvas = cv; WW = m.w * T; WH = m.h * T;
    ctx = canvas.getContext("2d");
    SPR = await (await fetch("/static/assets/sprites.json")).json();
    const [atlas, grass, dirt, water, ...vs] = await Promise.all([
      load("/static/assets/sprites.png"), load("/static/assets/terrain/grass.png"),
      load("/static/assets/terrain/dirt.png"), load("/static/assets/terrain/water.png"),
      ...["ada", "leo", "maya"].map((id) => load(`/static/assets/villagers/${id}.png`)),
    ]);
    Object.assign(A, { atlas, grass, dirt, water });
    ["ada", "leo", "maya"].forEach((id, i) => (A[`v_${id}`] = vs[i]));
    ground = document.createElement("canvas"); ground.width = WW; ground.height = WH;
    light = document.createElement("canvas"); light.width = WW; light.height = WH; lctx = light.getContext("2d");
    paintGround(ground.getContext("2d"));
    resize(); new ResizeObserver(resize).observe(canvas.parentElement);
    bindInput();
    requestAnimationFrame(frame);
  }

  function resize() {
    const w = canvas.parentElement.clientWidth;
    dpr = Math.min(window.devicePixelRatio || 1, 2);
    canvas.style.width = w + "px"; canvas.style.height = (w * WH / WW) + "px";
    canvas.width = Math.round(w * dpr); canvas.height = Math.round(w * WH / WW * dpr);
    scale = w / WW;
    clampCam();
  }

  // ------------------------------------------------------------- drawing
  function spr(c, name, x, y, w, h) {
    const s = SPR[name]; if (!s) return;
    c.drawImage(A.atlas, s.x, s.y, s.w, s.h, Math.round(x), Math.round(y), w ?? s.w, h ?? s.h);
  }
  const hash = (x, y, s = 0) => { let h = (x * 374761393 + y * 668265263 + s * 1442695041) | 0; h = Math.imul(h ^ (h >>> 13), 1274126177); return ((h ^ (h >>> 16)) >>> 0) / 4294967296; };

  // LPC autotile (3x6 layout) drawn by 16px quadrants.
  function autotile(c, sheet, x, y, same) {
    const full = same(x - 1, y) && same(x + 1, y) && same(x, y - 1) && same(x, y + 1) &&
      same(x - 1, y - 1) && same(x + 1, y - 1) && same(x - 1, y + 1) && same(x + 1, y + 1);
    if (full) { const v = Math.floor(hash(x, y, 3) * 3); c.drawImage(sheet, v * T, 5 * T, T, T, x * T, y * T, T, T); return; }
    for (const qy of [0, 1]) for (const qx of [0, 1]) {
      const hx = x + (qx ? 1 : -1), vy = y + (qy ? 1 : -1);
      const H = same(hx, y), V = same(x, vy), D = same(hx, vy);
      let tc, tr;
      if (!H && !V) { tc = qx ? 2 : 0; tr = qy ? 4 : 2; }
      else if (!V) { tc = 1; tr = qy ? 4 : 2; }
      else if (!H) { tc = qx ? 2 : 0; tr = 3; }
      else if (!D) { [tc, tr] = qx ? (qy ? [1, 0] : [1, 1]) : (qy ? [2, 0] : [2, 1]); }
      else { tc = 1; tr = 3; }
      c.drawImage(sheet, tc * T + qx * 16, tr * T + qy * 16, 16, 16, x * T + qx * 16, y * T + qy * 16, 16, 16);
    }
  }

  function paintGround(c) {
    c.imageSmoothingEnabled = false;
    const g = map.grid, at = (x, y) => (g[y] || "")[x];
    for (let y = 0; y < map.h; y++) for (let x = 0; x < map.w; x++) {
      const v = Math.floor(hash(x, y) * 3);
      c.drawImage(A.grass, v * T, 5 * T, T, T, x * T, y * T, T, T);
    }
    // a few darker grass tufts for texture
    for (let y = 0; y < map.h; y++) for (let x = 0; x < map.w; x++)
      if (at(x, y) === "g" && hash(x, y, 9) < 0.07) c.drawImage(A.grass, 0, 0, T, T, x * T, y * T, T, T);
    for (let y = 0; y < map.h; y++) for (let x = 0; x < map.w; x++) {
      const k = at(x, y);
      if (k === "p" || k === "c") autotile(c, A.dirt, x, y, (a, b) => "pc".includes(at(a, b) || "x") && at(a, b) !== undefined);
      if (k === "w") autotile(c, A.water, x, y, (a, b) => at(a, b) === "w");
    }
    // cobblestone square (9-slice from the magecity plaza tile)
    const [sx, sy, sw, sh] = map.locations.town_square.rect, cb = SPR.cobble;
    for (let y = sy; y < sy + sh; y++) for (let x = sx; x < sx + sw; x++) {
      const col = x === sx ? 0 : x === sx + sw - 1 ? 2 : 1, row = y === sy ? 0 : y === sy + sh - 1 ? 2 : 1;
      c.drawImage(A.atlas, cb.x + col * T, cb.y + row * T, T, T, x * T, y * T, T, T);
    }
    for (const p of map.props) if (p.flat) drawProp(c, p);
  }

  function propBox(p) {
    const s = SPR[p.sprite]; if (!s) return null;
    const [tx, ty] = p.tile;
    return { x: tx * T + T / 2 - s.w / 2 + p.dx, y: (ty + 1) * T - s.h + p.dy + (p.sprite.startsWith("flower") ? 0 : 2), w: s.w, h: s.h };
  }
  function drawProp(c, p) { const b = propBox(p); if (b) spr(c, p.sprite, b.x, b.y); }

  function drawVillager(v, s, t) {
    const img = A[`v_${v.id}`]; if (!img) return;
    const row = { up: 0, left: 1, down: 2, right: 3 }[s.facing || v.facing || "down"];
    const frame = s.walking ? 1 + (Math.floor(t * 11) % 8) : 0;
    const px = Math.round(s.x * T + T / 2), py = Math.round(s.y * T + T - 4);
    ctx.fillStyle = "rgba(0,0,0,.28)";
    ctx.beginPath(); ctx.ellipse(px, py, 11, 4, 0, 0, 7); ctx.fill();
    if (selected === v.id || hover?.v === v.id) {
      const p = 1 + Math.sin(t * 6) * 1.2;
      ctx.strokeStyle = selected === v.id ? "#ffe680" : "rgba(255,255,255,.7)"; ctx.lineWidth = 2;
      ctx.beginPath(); ctx.ellipse(px, py, 15 + p, 6 + p / 2, 0, 0, 7); ctx.stroke();
    }
    const bob = !s.walking && v.state !== "working" ? Math.round(Math.sin(t * 2 + v.id.length) * 0.6) : 0;
    ctx.drawImage(img, frame * 64, row * 64, 64, 64, px - 32, py - 62 + bob, 64, 64);
    s.px = px; s.py = py;
  }

  // -------------------------------------------------------------- frame
  function frame(now) {
    const dt = Math.min(0.05, (now - last) / 1000); last = now;
    const t = now / 1000;
    const sp = state && !state.paused ? state.speed : 0;
    updateCam(dt);
    const z = scale * cam.zoom * dpr;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.fillStyle = "#3d6b2f"; ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.setTransform(z, 0, 0, z, -cam.x * z, -cam.y * z);
    ctx.imageSmoothingEnabled = z < 1.4;

    ctx.drawImage(ground, 0, 0);
    waterShimmer(t);
    cloudShadows(t);

    // y-sorted scene
    const items = [];
    for (const [id, L] of Object.entries(map.locations)) {
      if (L.zone) continue;
      const s = SPR[L.sprite];
      items.push({ y: L.py + s.h - 6, draw: () => spr(ctx, L.sprite, L.px, L.py) });
    }
    for (const p of map.props) if (!p.flat) { const b = propBox(p); if (b) items.push({ y: b.y + b.h - 4, draw: () => spr(ctx, p.sprite, b.x, b.y) }); }
    const vs = state ? state.villagers : [];
    for (const v of vs) {
      const s = (shown[v.id] ??= { x: v.x, y: v.y, facing: v.facing });
      const k = Math.min(1, dt * 12);
      const mx = v.x - s.x, my = v.y - s.y;
      s.x += mx * k; s.y += my * k;
      s.walking = v.state === "walking" && (Math.hypot(mx, my) > 0.01 || sp > 0);
      s.facing = v.facing;
      items.push({ y: s.y * T + T - 4, draw: () => drawVillager(v, s, t) });
    }
    items.sort((a, b) => a.y - b.y);
    for (const it of items) it.draw();

    // particles
    spawnAmbient(dt, sp, t);
    stepParticles(dt * (sp || 0), t);

    // lighting
    if (state) {
      const w = warmth(state.minute); if (w > 0) { ctx.fillStyle = `rgba(255,140,60,${w})`; ctx.fillRect(0, 0, WW, WH); }
      const dark = darkness(state.minute); if (dark > 0) night(dark, t);
    }
    // overlays
    labels();
    for (const v of vs) {
      const s = shown[v.id]; if (s.px == null) continue;
      if (v.work) badge(s.px, s.py - 66, v.work, t);
      else if (v.bubble) bubble(s.px, s.py - 62, v.bubble);
      if (selected === v.id || hover?.v === v.id) nameTag(s.px, s.py + 8, v.title, v.color);
    }
    if (state?.paused) banner("PAUSED");
    requestAnimationFrame(frame);
  }

  function waterShimmer(t) {
    const g = map.grid;
    for (let y = 0; y < map.h; y++) for (let x = 0; x < map.w; x++) {
      if (g[y][x] !== "w") continue;
      const p = (Math.sin(t * 1.3 + x * 1.7 + y * 2.9) + 1) / 2;
      if (p > 0.55) { ctx.fillStyle = `rgba(200,240,255,${(p - .55) * 1.4})`; ctx.fillRect(x * T + 6 + p * 10, y * T + 12 + (x % 3) * 4, 6, 1); }
    }
  }
  function cloudShadows(t) {
    ctx.fillStyle = "rgba(20,30,10,.06)";
    for (let i = 0; i < 3; i++) {
      const x = ((t * 6 + i * 520) % (WW + 600)) - 300, y = 140 + i * 250 + Math.sin(t * 0.1 + i) * 30;
      ctx.beginPath(); ctx.ellipse(x, y, 190, 70, 0, 0, 7); ctx.ellipse(x + 120, y + 20, 140, 60, 0, 0, 7); ctx.fill();
    }
  }

  // ----------------------------------------------------------- particles
  function spawnAmbient(dt, sp, t) {
    if (!sp || particles.length > 300) return;
    const f = map.props.find((p) => p.sprite === "fountain");
    if (f && Math.random() < dt * 40) {
      const x = f.tile[0] * T + T / 2 + f.dx, y = (f.tile[1] + 1) * T - 52;
      const a = Math.random() * Math.PI * 2;
      particles.push({ k: "drop", x, y, vx: Math.cos(a) * 10, vy: -26 - Math.random() * 10, life: 0, max: 1.0 });
    }
    const th = map.locations.town_hall;
    if (Math.random() < dt * 2) particles.push({ k: "smoke", x: th.px + 162, y: th.py + 30, vx: 3 + Math.random() * 2, vy: -10, life: 0, max: 4 });
    if (Math.random() < dt * 0.5) particles.push({ k: "leaf", x: -10, y: Math.random() * WH * 0.8, vx: 18 + Math.random() * 12, vy: 4, life: 0, max: 80, ph: Math.random() * 6 });
    const dark = state ? darkness(state.minute) : 0;
    if (dark > 0.3 && Math.random() < dt * 4) particles.push({ k: "fly", x: Math.random() * WW, y: WH * 0.25 + Math.random() * WH * 0.7, vx: (Math.random() - .5) * 8, vy: (Math.random() - .5) * 8, life: 0, max: 6 });
    if (dark < 0.1 && particles.filter((p) => p.k === "bfly").length < 5 && Math.random() < dt * 0.3)
      particles.push({ k: "bfly", x: Math.random() * WW, y: Math.random() * WH, vx: 0, vy: 0, life: 0, max: 30, ph: Math.random() * 6, c: ["#ffd84a", "#f6a5c0", "#9ad3f0", "#ffffff"][Math.floor(Math.random() * 4)] });
  }
  function stepParticles(dt, t) {
    for (let i = particles.length - 1; i >= 0; i--) {
      const p = particles[i];
      p.life += dt; p.x += p.vx * dt; p.y += p.vy * dt;
      if (p.k === "drop") p.vy += 80 * dt;
      if (p.k === "leaf") p.vy = Math.sin(p.life * 2 + p.ph) * 8;
      if (p.k === "bfly") { p.vx = Math.cos(t * 0.7 + p.ph) * 22; p.vy = Math.sin(t * 1.1 + p.ph * 2) * 14; }
      if (p.life > p.max || p.x > WW + 20) { particles.splice(i, 1); continue; }
      const a = 1 - p.life / p.max;
      if (p.k === "drop") { ctx.fillStyle = `rgba(210,240,255,${a})`; ctx.fillRect(p.x, p.y, 2, 2); }
      if (p.k === "smoke") { const r = 4 + p.life * 4; ctx.fillStyle = `rgba(230,230,230,${a * 0.45})`; ctx.beginPath(); ctx.arc(p.x, p.y, r, 0, 7); ctx.fill(); }
      if (p.k === "leaf") { ctx.fillStyle = "#7fbf4f"; ctx.fillRect(p.x, p.y, 4, 2); ctx.fillStyle = "#5f9a3a"; ctx.fillRect(p.x + 1, p.y + 2, 2, 1); }
      if (p.k === "fly") { const g = (Math.sin(t * 5 + p.x) + 1) / 2; ctx.fillStyle = `rgba(255,240,140,${g * a})`; ctx.fillRect(p.x, p.y, 2, 2); }
      if (p.k === "bfly") { const flap = Math.sin(t * 18 + p.ph) > 0 ? 3 : 1; ctx.fillStyle = p.c; ctx.fillRect(p.x - flap, p.y, flap, 2); ctx.fillRect(p.x + 1, p.y, flap, 2); ctx.fillStyle = "#3b2c20"; ctx.fillRect(p.x, p.y, 1, 3); }
    }
  }

  // ------------------------------------------------------------ lighting
  function darkness(min) {
    const h = min / 60;
    if (h >= 7 && h <= 18) return 0;
    if (h > 18 && h < 21) return ((h - 18) / 3) * 0.6;
    if (h >= 21 || h < 5) return 0.6;
    return ((7 - h) / 2) * 0.6;
  }
  function warmth(min) { const h = min / 60; return h > 17 && h < 19.5 ? Math.sin(((h - 17) / 2.5) * Math.PI) * 0.15 : h > 5.5 && h < 7.5 ? Math.sin(((h - 5.5) / 2) * Math.PI) * 0.1 : 0; }
  function night(dark, t) {
    lctx.globalCompositeOperation = "source-over";
    lctx.clearRect(0, 0, WW, WH);
    lctx.fillStyle = `rgba(14,20,56,${dark})`; lctx.fillRect(0, 0, WW, WH);
    lctx.globalCompositeOperation = "destination-out";
    const hole = (x, y, r, a) => { const g = lctx.createRadialGradient(x, y, 0, x, y, r); g.addColorStop(0, `rgba(0,0,0,${a})`); g.addColorStop(1, "rgba(0,0,0,0)"); lctx.fillStyle = g; lctx.beginPath(); lctx.arc(x, y, r, 0, 7); lctx.fill(); };
    const flick = 0.93 + Math.sin(t * 9) * 0.04;
    const lamps = map.props.filter((p) => p.sprite === "lamp").map((p) => { const b = propBox(p); return [b.x + 16, b.y + 14]; });
    const windows = [];
    for (const L of Object.values(map.locations)) for (const [gx, gy] of L.glow || []) windows.push([L.px + gx, L.py + gy]);
    for (const [x, y] of lamps) hole(x, y + 30, 90, 0.95 * flick);
    for (const [x, y] of windows) hole(x, y, 34, 0.7);
    for (const s of Object.values(shown)) if (s.px) hole(s.px, s.py - 20, 26, 0.3);
    ctx.drawImage(light, 0, 0);
    ctx.globalCompositeOperation = "lighter";
    ctx.globalCompositeOperation = "source-over";
    for (const [x, y] of lamps) { const g = ctx.createRadialGradient(x, y + 30, 0, x, y + 30, 85); g.addColorStop(0, `rgba(255,170,70,${0.22 * flick})`); g.addColorStop(1, "rgba(255,170,70,0)"); ctx.fillStyle = g; ctx.fillRect(x - 85, y - 55, 170, 170); }
    ctx.globalCompositeOperation = "lighter";
    for (const [x, y] of lamps) { const g = ctx.createRadialGradient(x, y, 0, x, y, 26); g.addColorStop(0, `rgba(255,210,120,${0.6 * flick})`); g.addColorStop(1, "rgba(255,190,100,0)"); ctx.fillStyle = g; ctx.fillRect(x - 26, y - 26, 52, 52); }
    for (const [x, y] of windows) { const g = ctx.createRadialGradient(x, y, 0, x, y, 18); g.addColorStop(0, "rgba(255,200,110,.55)"); g.addColorStop(1, "rgba(255,200,110,0)"); ctx.fillStyle = g; ctx.fillRect(x - 18, y - 18, 36, 36); }
    ctx.globalCompositeOperation = "source-over";
    if (dark > 0.4) for (let i = 0; i < 60; i++) {
      const sx = hash(i, 1) * WW, sy = hash(i, 2) * WH * 0.3, tw = (Math.sin(t * 2 + i) + 1) / 2;
      if (tw > 0.5) { ctx.fillStyle = `rgba(255,255,230,${(dark - 0.3) * tw})`; ctx.fillRect(sx, sy, 2, 2); }
    }
  }

  // ------------------------------------------------------------- overlays
  const FONT = "ui-rounded, 'SF Pro Rounded', system-ui, sans-serif";
  function labels() {
    for (const [id, L] of Object.entries(map.locations)) {
      let cx, y;
      if (L.zone) { const [x, yy] = L.rect; cx = (x + 3) * T; y = yy * T + 40; }
      else { const s = SPR[L.sprite]; cx = L.px + s.w / 2; y = L.py - 8; }
      plaque(cx, y, L.name, hover?.loc === id);
    }
  }
  function plaque(cx, y, text, hot) {
    ctx.font = `700 13px ${FONT}`;
    const w = Math.ceil(ctx.measureText(text).width) + 20, h = 22, x = Math.round(cx - w / 2);
    ctx.fillStyle = "rgba(0,0,0,.3)"; round(x + 2, y + 3, w, h, 6); ctx.fill();
    ctx.fillStyle = "#5b3c24"; round(x, y, w, h, 6); ctx.fill();
    ctx.fillStyle = hot ? "#fff3c4" : "#f3e5c4"; round(x + 2, y + 2, w - 4, h - 4, 4); ctx.fill();
    ctx.fillStyle = "#4a3523"; ctx.fillText(text, x + 10, y + 15.5);
  }
  function nameTag(x, y, text, color) {
    ctx.font = `700 11px ${FONT}`;
    const w = Math.ceil(ctx.measureText(text).width) + 12;
    ctx.fillStyle = "rgba(30,20,10,.85)"; round(x - w / 2, y, w, 16, 8); ctx.fill();
    ctx.fillStyle = color; ctx.fillRect(x - w / 2 + 6, y + 6, 4, 4);
    ctx.fillStyle = "#fff"; ctx.fillText(text, x - w / 2 + 13, y + 12);
  }
  function round(x, y, w, h, r) { ctx.beginPath(); ctx.roundRect(x, y, w, h, r); }
  function wrap(text, maxW) {
    const words = String(text).split(/\s+/), lines = []; let cur = "";
    for (const w of words) { const n = cur ? cur + " " + w : w; if (ctx.measureText(n).width > maxW && cur) { lines.push(cur); cur = w; } else cur = n; }
    if (cur) lines.push(cur);
    return lines.slice(0, 3);
  }
  function bubble(x, y, text) {
    ctx.font = `600 12px ${FONT}`;
    const lines = wrap(text, 170), lh = 15;
    const w = Math.ceil(Math.max(...lines.map((l) => ctx.measureText(l).width))) + 18, h = lines.length * lh + 10;
    let bx = Math.max(4, Math.min(WW - w - 4, Math.round(x - w / 2))), by = Math.max(4, Math.round(y - h));
    ctx.fillStyle = "rgba(0,0,0,.25)"; round(bx + 2, by + 3, w, h, 9); ctx.fill();
    ctx.fillStyle = "#fffdf6"; ctx.strokeStyle = "#3b2c20"; ctx.lineWidth = 2;
    round(bx, by, w, h, 9); ctx.fill(); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(x - 6, by + h - 1); ctx.lineTo(x, by + h + 7); ctx.lineTo(x + 6, by + h - 1); ctx.fill();
    ctx.beginPath(); ctx.moveTo(x - 6, by + h); ctx.lineTo(x, by + h + 7); ctx.lineTo(x + 6, by + h); ctx.stroke();
    ctx.fillStyle = "#fffdf6"; ctx.fillRect(x - 5, by + h - 3, 10, 3);
    ctx.fillStyle = "#2b2622"; lines.forEach((l, i) => ctx.fillText(l, bx + 9, by + 17 + i * lh));
  }
  function badge(x, y, work, t) {
    const by = y - 26 + Math.sin(t * 4) * 2, w = 46, h = 30, bx = x - w / 2;
    ctx.fillStyle = "rgba(0,0,0,.25)"; round(bx + 2, by + 3, w, h, 8); ctx.fill();
    ctx.fillStyle = "#fffdf6"; ctx.strokeStyle = "#3b2c20"; ctx.lineWidth = 2; round(bx, by, w, h, 8); ctx.fill(); ctx.stroke();
    ctx.font = `16px ${FONT}`; ctx.textAlign = "center"; ctx.fillText(work.icon, x, by + 19); ctx.textAlign = "left";
    const p = work.progress ?? 0;
    ctx.fillStyle = "#e3d6bd"; ctx.fillRect(bx + 6, by + h - 7, w - 12, 3);
    ctx.fillStyle = "#5aa45a"; ctx.fillRect(bx + 6, by + h - 7, (w - 12) * p, 3);
  }
  function banner(text) {
    ctx.font = `800 22px ${FONT}`;
    const vw = canvas.width / (scale * cam.zoom * dpr), w = ctx.measureText(text).width + 40;
    const x = cam.x + vw / 2 - w / 2, y = cam.y + 16;
    ctx.fillStyle = "rgba(40,30,20,.85)"; round(x, y, w, 40, 10); ctx.fill();
    ctx.fillStyle = "#fff3c4"; ctx.fillText(text, x + 20, y + 28);
  }

  // --------------------------------------------------------------- camera
  function viewW() { return WW / cam.zoom; }
  function viewH() { return WH / cam.zoom; }
  function clampCam() {
    cam.zoom = Math.max(1, Math.min(3, cam.zoom));
    cam.x = Math.max(0, Math.min(WW - viewW(), cam.x));
    cam.y = Math.max(0, Math.min(WH - viewH(), cam.y));
  }
  function updateCam(dt) {
    if (cam.follow && selected && shown[selected]) {
      const s = shown[selected];
      const tx = s.x * T + T / 2 - viewW() / 2, ty = s.y * T - viewH() / 2;
      const k = Math.min(1, dt * 4);
      cam.x += (tx - cam.x) * k; cam.y += (ty - cam.y) * k;
    }
    clampCam();
  }
  function zoomAt(f, sx, sy) {
    const wx = cam.x + sx / (scale * cam.zoom), wy = cam.y + sy / (scale * cam.zoom);
    cam.zoom *= f; clampCam();
    cam.x = wx - sx / (scale * cam.zoom); cam.y = wy - sy / (scale * cam.zoom);
    clampCam();
  }

  // ---------------------------------------------------------------- input
  const tip = document.getElementById("tooltip");
  const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
  function toWorld(e) {
    const r = canvas.getBoundingClientRect(), sx = e.clientX - r.left, sy = e.clientY - r.top;
    return { x: cam.x + sx / (scale * cam.zoom), y: cam.y + sy / (scale * cam.zoom), sx, sy, r };
  }
  function hitVillager(p) {
    let best = null, bd = 30;
    for (const [id, s] of Object.entries(shown)) {
      if (s.px == null) continue;
      const d = Math.hypot(p.x - s.px, p.y - (s.py - 26));
      if (d < bd) { bd = d; best = id; }
    }
    return best;
  }
  function hitLocation(p) {
    for (const [id, L] of Object.entries(map.locations)) {
      if (L.zone) { const [x, y, w, h] = L.rect; if (p.x >= x * T && p.x < (x + w) * T && p.y >= y * T && p.y < (y + h) * T) return id; continue; }
      const s = SPR[L.sprite];
      if (p.x >= L.px && p.x < L.px + s.w && p.y >= L.py - 30 && p.y < L.py + s.h) return id;
    }
    return null;
  }
  let drag = null;
  function bindInput() {
    canvas.addEventListener("pointermove", (e) => {
      const p = toWorld(e);
      if (drag) {
        const dx = e.clientX - drag.x, dy = e.clientY - drag.y;
        if (Math.abs(dx) + Math.abs(dy) > 3) drag.moved = true;
        cam.x = drag.cx - dx / (scale * cam.zoom); cam.y = drag.cy - dy / (scale * cam.zoom); cam.follow = false; clampCam();
        tip.hidden = true; return;
      }
      const v = hitVillager(p), loc = v ? null : hitLocation(p);
      hover = { v, loc };
      canvas.style.cursor = v ? "pointer" : cam.zoom > 1 ? "grab" : loc ? "help" : "default";
      if (v && state) { const d = state.villagers.find((x) => x.id === v); show(p, `<b>${esc(d.title)}</b> · ${esc(d.state)}<br>${esc(d.work ? d.work.label + "…" : d.thought)}`); }
      else if (loc) { const L = map.locations[loc]; show(p, `<b>${esc(L.name)}</b><br>${esc(L.blurb)}`); }
      else tip.hidden = true;
    });
    canvas.addEventListener("pointerleave", () => { hover = null; tip.hidden = true; });
    canvas.addEventListener("pointerdown", (e) => {
      canvas.setPointerCapture(e.pointerId);
      drag = { x: e.clientX, y: e.clientY, cx: cam.x, cy: cam.y, moved: false };
    });
    canvas.addEventListener("pointerup", (e) => {
      if (drag && !drag.moved) { const v = hitVillager(toWorld(e)); if (v) { selected = v; onSelect(v); } }
      drag = null;
    });
    canvas.addEventListener("pointercancel", () => { drag = null; });
    canvas.addEventListener("wheel", (e) => { e.preventDefault(); const p = toWorld(e); zoomAt(e.deltaY < 0 ? 1.15 : 1 / 1.15, p.sx, p.sy); }, { passive: false });
    canvas.addEventListener("dblclick", () => { cam.zoom = 1; cam.follow = false; clampCam(); });
  }
  function show(p, html) {
    tip.innerHTML = html; tip.hidden = false;
    tip.style.left = Math.min(p.sx + 14, p.r.width - 250) + "px"; tip.style.top = (p.sy + 14) + "px";
  }

  // portrait for sidebar cards: crop the standing, front-facing frame
  function portrait(cv, v) {
    const img = A[`v_${v.id}`]; if (!img) return;
    const c = cv.getContext("2d"); c.imageSmoothingEnabled = false;
    c.clearRect(0, 0, cv.width, cv.height);
    c.drawImage(img, 14, 128 + 6, 36, 36, 0, 0, cv.width, cv.height);
  }

  return {
    init, portrait,
    setState: (s) => (state = s),
    select: (id) => (selected = id),
    zoom: (f) => { const r = canvas.getBoundingClientRect(); zoomAt(f, r.width / 2, r.height / 2); },
    fit: () => { cam.zoom = 1; cam.follow = false; clampCam(); },
    follow: (on) => { cam.follow = on; if (on && cam.zoom < 1.8) cam.zoom = 2; },
    get following() { return cam.follow; },
    set onSelect(fn) { onSelect = fn; },
  };
})();
