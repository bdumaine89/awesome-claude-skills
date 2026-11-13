// AI Village renderer. Procedural top-down art; any image listed in
// /assets/manifest.json replaces the procedural version for that thing.
const cv = document.getElementById("map");
const ctx = cv.getContext("2d");
let MAP, T, state = null;
const sprites = {};          // key -> HTMLImageElement
const shown = {};            // villager id -> {x,y} interpolated pixel position
const $ = (id) => document.getElementById(id);
const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));

async function boot() {
  MAP = await (await fetch("/api/village")).json();
  T = MAP.tile;
  cv.width = MAP.width * T;
  cv.height = MAP.height * T;
  $("title").textContent = `AI Village · ${MAP.name}`;
  document.title = MAP.name;
  await loadSprites();
  poll();
  setInterval(poll, 400);
  requestAnimationFrame(frame);
}

async function loadSprites() {
  try {
    const r = await fetch("/assets/manifest.json");
    if (!r.ok) return;
    const m = await r.json();
    const entries = [["ground", m.ground], ...Object.entries(m.locations || {}).map(([k, v]) => [`loc:${k}`, v]),
      ...Object.entries(m.villagers || {}).map(([k, v]) => [`vil:${k}`, v])];
    await Promise.all(entries.filter(([, src]) => src).map(([key, src]) => new Promise((res) => {
      const img = new Image();
      img.onload = () => { sprites[key] = img; res(); };
      img.onerror = res;
      img.src = `/assets/${src}`;
    })));
  } catch { /* procedural art only */ }
}

async function poll() {
  try {
    state = await (await fetch("/api/state")).json();
    renderPanel();
  } catch { /* server restarting */ }
}

// ---------------------------------------------------------------- drawing
function rect(x, y, w, h, c) { ctx.fillStyle = c; ctx.fillRect(x * T, y * T, w * T, h * T); }

function drawGround() {
  if (sprites.ground) return ctx.drawImage(sprites.ground, 0, 0, cv.width, cv.height);
  rect(0, 0, MAP.width, MAP.height, "#9cc47a");
  // deterministic grass speckle
  for (let y = 0; y < MAP.height; y++) for (let x = 0; x < MAP.width; x++) {
    const n = (x * 73856093 ^ y * 19349663) >>> 0;
    if (n % 7 === 0) { ctx.fillStyle = "#8db86b"; ctx.fillRect(x * T + (n % 17), y * T + (n % 13), 3, 3); }
  }
  for (const p of MAP.paths) rect(p.x, p.y, p.w, p.h, "#d8c49a");
  for (const p of MAP.paths) { ctx.strokeStyle = "#c4ae80"; ctx.lineWidth = 1; ctx.strokeRect(p.x * T + .5, p.y * T + .5, p.w * T - 1, p.h * T - 1); }
  for (const w of MAP.water || []) {
    ctx.fillStyle = "#6aa6c8"; roundRect(w.x * T, w.y * T, w.w * T, w.h * T, 10); ctx.fill();
    ctx.fillStyle = "rgba(255,255,255,.35)"; ctx.fillRect(w.x * T + 10, w.y * T + 14, 22, 3);
  }
}

function roundRect(x, y, w, h, r) {
  ctx.beginPath(); ctx.moveTo(x + r, y); ctx.arcTo(x + w, y, x + w, y + h, r); ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r); ctx.arcTo(x, y, x + w, y, r); ctx.closePath();
}

function drawTree(tx, ty) {
  const cx = tx * T + T / 2, cy = ty * T + T / 2;
  ctx.fillStyle = "rgba(0,0,0,.15)"; ctx.beginPath(); ctx.ellipse(cx + 3, cy + 8, 11, 5, 0, 0, 7); ctx.fill();
  ctx.fillStyle = "#6b4a2b"; ctx.fillRect(cx - 2, cy, 4, 9);
  ctx.fillStyle = "#4e8a3e"; ctx.beginPath(); ctx.arc(cx, cy - 2, 11, 0, 7); ctx.fill();
  ctx.fillStyle = "#62a24f"; ctx.beginPath(); ctx.arc(cx - 3, cy - 5, 6, 0, 7); ctx.fill();
}

function drawLocation(l) {
  const x = l.x * T, y = l.y * T, w = l.w * T, h = l.h * T;
  const s = sprites[`loc:${l.id}`];
  if (s) { ctx.drawImage(s, x, y, w, h); return label(l); }
  if (l.kind === "zone") {
    ctx.fillStyle = "#86bd6b"; roundRect(x, y, w, h, 14); ctx.fill();
    ctx.strokeStyle = "#6f9e57"; ctx.setLineDash([4, 4]); ctx.stroke(); ctx.setLineDash([]);
    ctx.fillStyle = "#8b6b47"; ctx.fillRect(x + w / 2 - 14, y + h / 2 + 6, 28, 6);   // bench
    return label(l);
  }
  if (l.kind === "landmark") {
    ctx.fillStyle = "#5a432b"; ctx.fillRect(x + 6, y + 10, 4, T); ctx.fillRect(x + w - 10, y + 10, 4, T);
    ctx.fillStyle = l.color; ctx.fillRect(x + 2, y - 6, w - 4, 20);
    ctx.fillStyle = "#f3ead8"; ctx.fillRect(x + 7, y - 2, 12, 9); ctx.fillRect(x + 24, y - 1, 14, 8);
    return label(l);
  }
  // building: shadow, walls, roof, door, windows
  ctx.fillStyle = "rgba(0,0,0,.18)"; ctx.fillRect(x + 5, y + 6, w, h);
  ctx.fillStyle = l.color; ctx.fillRect(x, y + h * 0.35, w, h * 0.65);
  ctx.fillStyle = l.roof; ctx.beginPath(); ctx.moveTo(x - 4, y + h * 0.4); ctx.lineTo(x + w / 2, y - 4);
  ctx.lineTo(x + w + 4, y + h * 0.4); ctx.closePath(); ctx.fill();
  const [dx] = l.door;
  ctx.fillStyle = "#3d2b1f"; ctx.fillRect(dx * T + 6, y + h - 18, T - 12, 18);
  ctx.fillStyle = "#f6e7b4";
  const wy = y + h * 0.5;
  for (let wx = x + 10; wx < x + w - 14; wx += 28) if (Math.abs(wx + 6 - (dx * T + T / 2)) > 14) ctx.fillRect(wx, wy, 12, 10);
  label(l);
}

function label(l) {
  ctx.font = "bold 11px system-ui, sans-serif";
  const text = l.name, tw = ctx.measureText(text).width;
  const cx = (l.x + l.w / 2) * T, y = l.kind === "zone" ? l.y * T + 14 : (l.y + l.h) * T + 13;
  ctx.fillStyle = "rgba(255,250,240,.85)"; ctx.fillRect(cx - tw / 2 - 4, y - 10, tw + 8, 14);
  ctx.fillStyle = "#2d2a26"; ctx.fillText(text, cx - tw / 2, y);
}

function drawVillager(v, px, py) {
  const s = sprites[`vil:${v.id}`];
  ctx.globalAlpha = v.indoors ? 0.45 : 1;
  ctx.fillStyle = "rgba(0,0,0,.2)"; ctx.beginPath(); ctx.ellipse(px, py + 9, 8, 3, 0, 0, 7); ctx.fill();
  if (s) ctx.drawImage(s, px - 12, py - 16, 24, 28);
  else {
    ctx.fillStyle = v.color; ctx.beginPath(); ctx.arc(px, py, 9, 0, 7); ctx.fill();
    ctx.strokeStyle = "#fff"; ctx.lineWidth = 2; ctx.stroke();
    ctx.fillStyle = "#fff"; ctx.font = "bold 10px system-ui"; ctx.fillText(v.name[0], px - 3.5, py + 3.5);
  }
  ctx.globalAlpha = 1;
  if (v.bubble) bubble(px, py - 14, v.bubble);
}

function bubble(x, y, text) {
  ctx.font = "11px system-ui, sans-serif";
  const t = text.length > 42 ? text.slice(0, 41) + "…" : text;
  const w = ctx.measureText(t).width + 12;
  const bx = Math.min(Math.max(x - w / 2, 2), cv.width - w - 2), by = y - 22;
  ctx.fillStyle = "#fff"; roundRect(bx, by, w, 18, 6); ctx.fill();
  ctx.strokeStyle = "#cbbfa8"; ctx.lineWidth = 1; ctx.stroke();
  ctx.beginPath(); ctx.moveTo(x - 4, by + 18); ctx.lineTo(x, by + 23); ctx.lineTo(x + 4, by + 18); ctx.fill();
  ctx.fillStyle = "#2d2a26"; ctx.fillText(t, bx + 6, by + 13);
}

function nightAlpha(min) {
  // 0 during the day, up to .45 at midnight, with dusk/dawn ramps
  if (min >= 7 * 60 && min <= 18 * 60) return 0;
  const d = min > 18 * 60 ? (min - 18 * 60) / 180 : (7 * 60 - min) / 120;
  return Math.min(0.45, Math.max(0, d * 0.45));
}

function frame() {
  if (MAP) {
    drawGround();
    for (const l of MAP.locations) drawLocation(l);
    for (const [tx, ty] of MAP.trees) drawTree(tx, ty);
    if (state) {
      // group villagers on the same tile so they don't stack
      const byTile = {};
      for (const v of state.villagers) (byTile[`${v.x},${v.y}`] ??= []).push(v.id);
      const ordered = [...state.villagers].sort((a, b) => a.y - b.y);
      for (const v of ordered) {
        const group = byTile[`${v.x},${v.y}`];
        const off = (group.indexOf(v.id) - (group.length - 1) / 2) * 14;
        const tx = v.x * T + T / 2 + off, ty = v.y * T + T / 2;
        const cur = (shown[v.id] ??= { x: tx, y: ty });
        cur.x += (tx - cur.x) * 0.18; cur.y += (ty - cur.y) * 0.18;
        drawVillager(v, cur.x, cur.y);
      }
      const a = nightAlpha(state.minute);
      if (a > 0) {
        ctx.fillStyle = `rgba(20,24,60,${a})`; ctx.fillRect(0, 0, cv.width, cv.height);
        ctx.fillStyle = `rgba(255,220,130,${a * 1.6})`;   // lit windows
        for (const l of MAP.locations) if (l.kind === "building" || l.kind === "home") ctx.fillRect(l.x * T + 10, (l.y + l.h * 0.5) * T, 12, 10);
      }
    }
  }
  requestAnimationFrame(frame);
}

// ---------------------------------------------------------------- panel
function renderPanel() {
  $("day").textContent = `Day ${state.day}`;
  $("time").textContent = state.time;
  $("brain").textContent = `brain: ${state.brain}`;
  $("pause").textContent = state.paused ? "Resume" : "Pause";
  if (document.activeElement !== $("speed")) $("speed").value = String(state.speed);
  $("villagers").innerHTML = state.villagers.map((v) =>
    `<li><span class="dot" style="background:${v.color}"></span><span><b>${esc(v.name)}</b> · ${esc(v.role)}</span>
     <span class="st">${esc(v.status)}</span></li>`).join("");
  $("tasks").innerHTML = [...state.tasks].reverse().map((t) =>
    `<li><span class="s ${t.status}">${t.status}</span>${esc(t.title)}
     <div class="meta">${esc(t.kind)}${t.assignee ? " · " + esc(t.assignee) : ""}${t.result ? " · " + esc(t.result) : ""}</div></li>`).join("");
  $("events").innerHTML = state.events.map((e) => `<li><span class="t">${esc(e.t)}</span> ${esc(e.text)}</li>`).join("");
}

$("pause").onclick = () => control({ action: state?.paused ? "resume" : "pause" });
$("speed").onchange = (e) => control({ action: "speed", value: Number(e.target.value) });
async function control(body) {
  await fetch("/api/control", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
  poll();
}
$("taskForm").onsubmit = async (e) => {
  e.preventDefault();
  const f = new FormData(e.target);
  await fetch("/api/tasks", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(Object.fromEntries(f)) });
  e.target.reset();
  poll();
};

// hover tooltip: what each building does
cv.addEventListener("mousemove", (e) => {
  if (!MAP) return;
  const r = cv.getBoundingClientRect();
  const tx = ((e.clientX - r.left) / r.width) * MAP.width, ty = ((e.clientY - r.top) / r.height) * MAP.height;
  const l = MAP.locations.find((l) => tx >= l.x && tx < l.x + l.w && ty >= l.y - 0.5 && ty < l.y + l.h + 0.5);
  const tip = $("tooltip");
  if (!l || !l.description) { tip.hidden = true; return; }
  tip.hidden = false;
  tip.innerHTML = `<b>${esc(l.name)}</b> · <i>${esc(l.function)}</i><br>${esc(l.description)}`;
  tip.style.left = `${e.clientX - r.left + 12}px`; tip.style.top = `${e.clientY - r.top + 12}px`;
});
cv.addEventListener("mouseleave", () => { $("tooltip").hidden = true; });

boot();
