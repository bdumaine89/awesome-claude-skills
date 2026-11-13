// Canvas renderer: pre-renders the static village into two layers (ground and
// overlay), then each frame draws villagers, particles, lighting and bubbles.
"use strict";

const Game = (() => {
  const { T, px, drawVillager, drawWorkBadge } = Art;
  const S = 3;                         // screen pixels per world pixel
  const CS = 1.5;                      // villagers are drawn a bit chunkier than the scenery
  let map, W, H, canvas, ctx, base, over, light, lctx;
  const extras = { windows: [], chimneys: [], flags: [], lamps: [] };
  const shown = {};                    // id -> {x, y} smoothed tile coords
  const particles = [];
  let state = null, hover = null, selected = null, onSelect = () => {}, last = performance.now();

  function init(m, cv) {
    map = m; canvas = cv; W = m.w * T; H = m.h * T;
    canvas.width = W * S; canvas.height = H * S;
    ctx = canvas.getContext("2d");
    base = layer(); over = layer(); light = layer(); lctx = light.getContext("2d");
    paintStatic();
    canvas.addEventListener("mousemove", onMove);
    canvas.addEventListener("mouseleave", () => { hover = null; tip.hidden = true; });
    canvas.addEventListener("click", onClick);
    requestAnimationFrame(frame);
  }
  function layer() { const c = document.createElement("canvas"); c.width = W; c.height = H; return c; }

  // --------------------------------------------------------------- static
  function paintStatic() {
    const b = base.getContext("2d"), o = over.getContext("2d");
    const g = map.grid, cobbleNear = (x, y) => [[1,0],[-1,0],[0,1],[0,-1]].some(([dx, dy]) => (g[y + dy] || "")[x + dx] === "c");
    for (let y = 0; y < map.h; y++) for (let x = 0; x < map.w; x++) {
      const c = g[y][x];
      if (c === "p") Art.drawDirt(b, x, y, g);
      else if (c === "c" || c === "f" || ("ln".includes(c) && cobbleNear(x, y))) Art.drawCobble(b, x, y);
      else if (c === "w") Art.drawWater(b, x, y, g);
      else if (c === "o") Art.drawFlowers(b, x, y);
      else Art.drawGrass(b, x, y);
    }
    // multi-tile things
    let fdone = false;
    for (let y = 0; y < map.h; y++) for (let x = 0; x < map.w; x++) {
      const c = g[y][x];
      if (c === "f" && !fdone) { Art.drawFountain(b, x, y); fdone = true; extras.fountain = [x * T + 32, y * T + 10]; }
      if (c === "x") Art.drawFence(b, x, y, g);
      if (c === "n") Art.drawBench(b, x, y);
    }
    for (const [id, L] of Object.entries(map.locations)) if (!L.zone) Art.drawBuilding(b, id, L, extras);
    // trees and lamps: trunk/post on the ground layer, canopy/head on the overlay (drawn above villagers)
    for (let y = 0; y < map.h; y++) for (let x = 0; x < map.w; x++) {
      const c = g[y][x];
      if (c === "t") { Art.drawTreeTrunk(b, x, y); Art.drawTreeCanopy(o, x, y); }
      if (c === "l") { Art.drawLampBase(b, x, y); Art.drawLampHead(o, x, y); extras.lamps.push([x * T + 8, y * T - 6]); }
    }
    // bunting across the square
    const sq = map.locations.town_square, y0 = sq.y * T - 4;
    const cols = ["#e8504f", "#f2c14e", "#5aa7d6", "#6a9c4a", "#c58af9"];
    for (let i = 0, x = sq.x * T + 8; x < (sq.x + sq.w) * T - 8; x += 6, i++) {
      const sag = Math.round(Math.sin(((x - sq.x * T) / (sq.w * T)) * Math.PI) * 6);
      px(o, x, y0 + sag, 6, 1, "#5b3c24");
      o.fillStyle = cols[i % cols.length];
      o.beginPath(); o.moveTo(x, y0 + sag + 1); o.lineTo(x + 5, y0 + sag + 1); o.lineTo(x + 2.5, y0 + sag + 6); o.fill();
    }
  }

  // -------------------------------------------------------------- dynamic
  function setState(s) { state = s; }
  function select(id) { selected = id; }

  function spawn(kind, x, y) {
    if (particles.length > 260) return;
    if (kind === "smoke") particles.push({ kind, x, y, vx: 1.5 + Math.random(), vy: -5 - Math.random() * 2, life: 0, max: 3 + Math.random() * 2, r: 2 });
    if (kind === "drop") { const a = Math.random() * Math.PI * 2; particles.push({ kind, x, y, vx: Math.cos(a) * 6, vy: -16 - Math.random() * 6, life: 0, max: 0.9 }); }
    if (kind === "firefly") particles.push({ kind, x, y, vx: (Math.random() - .5) * 4, vy: (Math.random() - .5) * 4, life: 0, max: 4 + Math.random() * 3 });
    if (kind === "leaf") particles.push({ kind, x, y, vx: 6 + Math.random() * 4, vy: 3, life: 0, max: 6, ph: Math.random() * 6 });
  }

  function darkness(min) {
    // 0 at midday, ~0.55 deep night; smooth dusk/dawn
    const h = min / 60;
    if (h >= 7 && h <= 18) return 0;
    if (h > 18 && h < 21) return ((h - 18) / 3) * 0.55;
    if (h >= 21 || h < 5) return 0.55;
    return ((7 - h) / 2) * 0.55;
  }
  function warmth(min) { const h = min / 60; return h > 17 && h < 19.5 ? Math.sin(((h - 17) / 2.5) * Math.PI) * 0.16 : h > 5.5 && h < 7.5 ? Math.sin(((h - 5.5) / 2) * Math.PI) * 0.12 : 0; }

  function frame(now) {
    const dt = Math.min(0.05, (now - last) / 1000); last = now;
    const t = now / 1000;
    ctx.setTransform(S, 0, 0, S, 0, 0);
    ctx.imageSmoothingEnabled = false;
    ctx.drawImage(base, 0, 0);
    drawWaterShimmer(t);
    // particles below canopy
    const speed = state && !state.paused ? state.speed : 0;
    if (speed > 0) {
      for (const [x, y] of extras.chimneys) if (Math.random() < dt * 2.2) spawn("smoke", x, y);
      if (extras.fountain && Math.random() < dt * 30) spawn("drop", extras.fountain[0] + (Math.random() - .5) * 3, extras.fountain[1] + 12);
      if (Math.random() < dt * 0.4) spawn("leaf", -4, Math.random() * H * 0.8);
    }
    const dark = state ? darkness(state.minute) : 0;
    if (dark > 0.3 && Math.random() < dt * 3) spawn("firefly", Math.random() * W, H * 0.3 + Math.random() * H * 0.6);
    advanceParticles(dt * Math.max(speed, 0) || dt * 0);
    drawParticles(t, false);

    // villagers sorted by y for depth
    const vs = state ? [...state.villagers].sort((a, b) => a.y - b.y) : [];
    for (const v of vs) {
      const s = (shown[v.id] ??= { x: v.x, y: v.y });
      const k = Math.min(1, dt * 12);
      const mx = v.x - s.x, my = v.y - s.y;
      s.x += mx * k; s.y += my * k;
      s.moving = Math.hypot(mx, my) > 0.02 || v.state === "walking";
      const X = Math.round((s.x * T + 8) * S) / S, Y = Math.round((s.y * T + 13) * S) / S;
      s.X = X; s.Y = Y;
      ctx.save(); ctx.translate(X, Y); ctx.scale(CS, CS);
      drawVillager(ctx, v, 0, 0, t, s.moving && v.state === "walking", selected === v.id || hover?.v === v.id);
      ctx.restore();
    }
    ctx.drawImage(over, 0, 0);
    drawParticles(t, true);
    drawFlags(t);
    drawLabels();
    // lighting
    if (state) {
      const w = warmth(state.minute);
      if (w > 0) { ctx.fillStyle = `rgba(255,140,60,${w})`; ctx.fillRect(0, 0, W, H); }
      if (dark > 0) drawNight(dark, t);
    }
    // UI on top of lighting: bubbles + badges + names
    for (const v of vs) {
      const s = shown[v.id];
      if (v.work) drawWorkBadge(ctx, s.X, s.Y - 12, v.work.icon, v.work.progress, t);
      else if (v.bubble) bubble(s.X, s.Y - 36, v.bubble);
      nameTag(s.X, s.Y + 4, v.name, v.color, selected === v.id || hover?.v === v.id);
    }
    if (state?.paused) { ctx.fillStyle = "rgba(40,30,20,.25)"; ctx.fillRect(0, 0, W, H); banner("PAUSED"); }
    requestAnimationFrame(frame);
  }

  function drawWaterShimmer(t) {
    const g = map.grid;
    for (let y = 0; y < map.h; y++) for (let x = 0; x < map.w; x++) {
      if (g[y][x] !== "w") continue;
      const p = (Math.sin(t * 1.5 + x * 1.7 + y * 2.3) + 1) / 2;
      if (p > 0.6) px(ctx, x * T + 4 + Math.round(p * 4), y * T + 7, 4, 1, "rgba(255,255,255,.55)");
    }
    if (extras.fountain) {
      const [fx, fy] = extras.fountain, r = (t * 8) % 12;
      ctx.strokeStyle = `rgba(255,255,255,${0.5 - r / 26})`; ctx.lineWidth = 0.6;
      ctx.beginPath(); ctx.ellipse(fx, fy + 16, 4 + r, 2 + r / 3, 0, 0, 7); ctx.stroke();
    }
  }

  function advanceParticles(dt) {
    for (let i = particles.length - 1; i >= 0; i--) {
      const p = particles[i];
      p.life += dt; p.x += p.vx * dt; p.y += p.vy * dt;
      if (p.kind === "drop") p.vy += 40 * dt;
      if (p.kind === "smoke") p.vx += 0.5 * dt;
      if (p.kind === "leaf") p.vy = Math.sin(p.life * 2) * 4;
      if (p.life > p.max || p.x > W + 10) particles.splice(i, 1);
    }
  }
  function drawParticles(t, overlayPass) {
    for (const p of particles) {
      if ((p.kind === "smoke" || p.kind === "leaf") !== overlayPass) continue;
      const a = 1 - p.life / p.max;
      if (p.kind === "smoke") { ctx.fillStyle = `rgba(235,235,235,${a * 0.55})`; const r = 2 + p.life * 1.6; ctx.fillRect(p.x - r / 2, p.y - r / 2, r, r); }
      if (p.kind === "drop") px(ctx, p.x, p.y, 1, 1, `rgba(200,235,255,${a})`);
      if (p.kind === "leaf") px(ctx, p.x, p.y + Math.sin(t * 3 + p.ph) * 2, 2, 1, "#6fbb5a");
      if (p.kind === "firefly") { const g = (Math.sin(t * 5 + p.x) + 1) / 2; px(ctx, p.x, p.y, 1, 1, `rgba(255,240,140,${g * a})`); }
    }
  }

  function drawFlags(t) {
    for (const [x, y] of extras.flags) {
      for (let i = 0; i < 9; i++) {
        const wy = Math.round(Math.sin(t * 5 - i * 0.7) * 1.2);
        px(ctx, x + i, y + wy, 1, 6, i < 3 ? "#e8504f" : "#d94b4b");
        if (i % 3 === 0) px(ctx, x + i, y + 2 + wy, 1, 1, "#f2c14e");
      }
    }
  }

  function drawLabels() {
    for (const [id, L] of Object.entries(map.locations)) {
      const cx = (L.x + L.w / 2) * T;
      const y = L.zone ? L.y * T + 8 : (id === "town_hall" ? L.y * T - 50 : L.y * T - 12);
      label(cx, y, L.name.toUpperCase(), hover?.loc === id);
    }
  }
  function label(cx, y, text, hot) {
    ctx.font = "bold 7px ui-monospace, Menlo, Consolas, monospace";
    const w = Math.ceil(ctx.measureText(text).width) + 10, h = 12;
    const x = Math.round(cx - w / 2); y = Math.round(y - 3);
    px(ctx, x + 1, y + 2, w, h, "rgba(0,0,0,.25)");
    px(ctx, x, y, w, h, "#6e4729"); px(ctx, x + 1, y + 1, w - 2, h - 2, hot ? "#fff3c4" : "#f6ecd6");
    ctx.fillStyle = "#4a3523"; ctx.fillText(text, x + 5, y + 8.6);
  }
  function nameTag(x, y, name, color, hot) {
    if (!hot) return;
    ctx.font = "bold 6px ui-monospace, Menlo, Consolas, monospace";
    const w = Math.ceil(ctx.measureText(name).width) + 6;
    px(ctx, x - w / 2 - 1, y - 1, w + 2, 10, "#2b2622");
    px(ctx, x - w / 2, y, w, 8, color); ctx.fillStyle = "#fff"; ctx.fillText(name, x - w / 2 + 3, y + 6.2);
  }
  function wrap(text, maxW) {
    const words = String(text).split(/\s+/), lines = []; let cur = "";
    for (const w of words) { const n = cur ? cur + " " + w : w; if (ctx.measureText(n).width > maxW && cur) { lines.push(cur); cur = w; } else cur = n; }
    if (cur) lines.push(cur);
    return lines.slice(0, 3);
  }
  function bubble(x, y, text) {
    ctx.font = "6px ui-rounded, system-ui, sans-serif";
    const lines = wrap(text, 84), lh = 7.5;
    const w = Math.ceil(Math.max(...lines.map((l) => ctx.measureText(l).width))) + 8, h = lines.length * lh + 5;
    let bx = Math.round(x - w / 2), by = Math.round(y - h);
    bx = Math.max(2, Math.min(W - w - 2, bx)); by = Math.max(2, by);
    px(ctx, bx + 1, by, w - 2, h, "#2b2622"); px(ctx, bx, by + 1, w, h - 2, "#2b2622");
    px(ctx, bx + 1, by + 1, w - 2, h - 2, "#fffdf6"); px(ctx, bx + 1, by + h - 2, w - 2, 1, "#e9e0cc");
    px(ctx, x - 1, by + h, 3, 1, "#2b2622"); px(ctx, x, by + h + 1, 2, 1, "#2b2622"); px(ctx, x, by + h - 1, 1, 1, "#fffdf6");
    ctx.fillStyle = "#2b2622";
    lines.forEach((l, i) => ctx.fillText(l, bx + 4, by + 7 + i * lh));
  }
  function banner(text) {
    ctx.font = "bold 10px ui-monospace, Menlo, monospace";
    const w = ctx.measureText(text).width + 16;
    px(ctx, W / 2 - w / 2, 8, w, 16, "#2b2622"); px(ctx, W / 2 - w / 2 + 1, 9, w - 2, 14, "#f6ecd6");
    ctx.fillStyle = "#4a3523"; ctx.fillText(text, W / 2 - w / 2 + 8, 20);
  }

  function drawNight(dark, t) {
    lctx.globalCompositeOperation = "source-over";
    lctx.clearRect(0, 0, W, H);
    lctx.fillStyle = `rgba(16,22,58,${dark})`; lctx.fillRect(0, 0, W, H);
    lctx.globalCompositeOperation = "destination-out";
    const hole = (x, y, r, a) => {
      const g = lctx.createRadialGradient(x, y, 0, x, y, r);
      g.addColorStop(0, `rgba(0,0,0,${a})`); g.addColorStop(1, "rgba(0,0,0,0)");
      lctx.fillStyle = g; lctx.beginPath(); lctx.arc(x, y, r, 0, 7); lctx.fill();
    };
    const flick = 0.92 + Math.sin(t * 9) * 0.04;
    for (const [x, y] of extras.lamps) hole(x, y + 6, 30, 0.9 * flick);
    for (const [x, y, w, h] of extras.windows) hole(x + w / 2, y + h / 2, 14, 0.75);
    for (const s of Object.values(shown)) if (s.X) hole(s.X, s.Y - 8, 10, 0.35);
    ctx.drawImage(light, 0, 0);
    ctx.globalCompositeOperation = "lighter";
    for (const [x, y] of extras.lamps) { const g = ctx.createRadialGradient(x, y, 0, x, y, 22); g.addColorStop(0, `rgba(255,200,110,${0.28 * flick})`); g.addColorStop(1, "rgba(255,200,110,0)"); ctx.fillStyle = g; ctx.fillRect(x - 22, y - 22, 44, 44); }
    for (const [x, y, w, h] of extras.windows) { ctx.fillStyle = "rgba(255,190,90,.45)"; ctx.fillRect(x, y, w, h); }
    ctx.globalCompositeOperation = "source-over";
    // stars
    if (dark > 0.4) for (let i = 0; i < 40; i++) {
      const sx = Art.hash(i, 1) * W, sy = Art.hash(i, 2) * H * 0.25, tw = (Math.sin(t * 2 + i) + 1) / 2;
      if (tw > 0.5) px(ctx, sx, sy, 1, 1, `rgba(255,255,230,${(dark - 0.3) * tw})`);
    }
  }

  // --------------------------------------------------------------- input
  const tip = document.getElementById("tooltip");
  function worldPos(e) {
    const r = canvas.getBoundingClientRect();
    return { x: ((e.clientX - r.left) / r.width) * W, y: ((e.clientY - r.top) / r.height) * H, r, e };
  }
  function hitVillager(p) {
    let best = null, bd = 16;
    for (const [id, s] of Object.entries(shown)) {
      const d = Math.hypot(p.x - s.X, p.y - (s.Y - 14));
      if (d < bd) { bd = d; best = id; }
    }
    return best;
  }
  function hitLocation(p) {
    for (const [id, L] of Object.entries(map.locations)) {
      const top = L.zone ? L.y * T : L.y * T - 12;
      if (p.x >= L.x * T && p.x < (L.x + L.w) * T && p.y >= top && p.y < (L.y + L.h) * T) return id;
    }
    return null;
  }
  function onMove(e) {
    const p = worldPos(e), v = hitVillager(p), loc = v ? null : hitLocation(p);
    hover = { v, loc };
    canvas.style.cursor = v ? "pointer" : loc ? "help" : "default";
    if (v && state) {
      const d = state.villagers.find((x) => x.id === v);
      showTip(p, `<b>${esc(d.title)}</b> · ${esc(d.state)}<br>${esc(d.thought)}`);
    } else if (loc) {
      const L = map.locations[loc];
      showTip(p, `<b>${esc(L.name)}</b><br>${esc(L.blurb)}`);
    } else tip.hidden = true;
  }
  function showTip(p, html) {
    tip.innerHTML = html; tip.hidden = false;
    const x = p.e.clientX - p.r.left + 14, y = p.e.clientY - p.r.top + 14;
    tip.style.left = Math.min(x, p.r.width - 250) + "px"; tip.style.top = y + "px";
  }
  function onClick(e) {
    const p = worldPos(e), v = hitVillager(p);
    if (v) { selected = v; onSelect(v); }
  }
  const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));

  // mini portrait for the sidebar cards
  function portrait(cv, v) {
    const c = cv.getContext("2d"); const s = cv.width / 24;
    c.setTransform(s, 0, 0, s, 0, 0); c.imageSmoothingEnabled = false;
    c.clearRect(0, 0, 24, 24);
    drawVillager(c, { ...v, facing: "down" }, 12, 22, 0, false, false);
  }

  return { init, setState, select, portrait, set onSelect(fn) { onSelect = fn; } };
})();
