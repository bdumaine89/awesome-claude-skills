// Sidebar, controls, WebSocket. Keeps DOM work light: the canvas animates at
// 60fps, panels re-render only when the server's `rev` counter changes.
"use strict";

(() => {
  const $ = (id) => document.getElementById(id);
  const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const api = async (path, body) => {
    const r = await fetch(path, body ? { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) } : {});
    const data = await r.json().catch(() => ({}));
    if (!r.ok) throw new Error(data.detail || r.statusText);
    return data;
  };
  const store = (k, v) => { try { if (v === undefined) return localStorage.getItem(k); localStorage.setItem(k, v); } catch { return null; } };

  let state = null, board = null, rev = -1, selected = store("av.sel") || "ada", tab = store("av.tab") || "inspect";
  let feedFilter = "all", seenFeed = 0, lastCards = 0;
  const names = {};

  // ---------------------------------------------------------------- boot
  async function boot() {
    const map = await api("/api/map");
    await Game.init(map, $("village"));
    Game.onSelect = (id) => { selectVillager(id); setTab("inspect"); };
    Game.select(selected);
    examples();
    bindControls();
    setTab(tab);
    connect();
    setInterval(() => { if (tab === "inspect") renderInspector(); }, 1500);
  }

  function connect() {
    const ws = new WebSocket(`${location.protocol === "https:" ? "wss" : "ws"}://${location.host}/ws`);
    ws.onopen = () => { $("conn").hidden = true; };
    ws.onmessage = (e) => onState(JSON.parse(e.data));
    ws.onclose = () => { $("conn").hidden = false; setTimeout(connect, 1500); };
  }

  function onState(s) {
    state = s;
    Game.setState(s);
    for (const v of s.villagers) names[v.id] = v;
    const now = performance.now();
    if (now - lastCards > 250) { lastCards = now; renderTop(); renderCards(); }
    if (s.rev !== rev) { rev = s.rev; refreshBoard(); if (tab === "inspect") renderInspector(); }
  }

  // ------------------------------------------------------------- top bar
  function renderTop() {
    const m = state.minute, hh = String(Math.floor(m / 60)).padStart(2, "0"), mm = String(m % 60).padStart(2, "0");
    $("clock").textContent = `Day ${state.day} · ${hh}:${mm}`;
    const h = m / 60;
    $("sky").style.background = h >= 21 || h < 5 ? "radial-gradient(circle at 35% 35%, #fffbe0 30%, #1d2a5c 32%)"
      : h >= 18 || h < 7 ? "linear-gradient(#ff9d5c, #6b5aa8)" : "radial-gradient(circle, #ffe27a 45%, #8fd0f5 47%)";
    $("playBtn").textContent = state.paused ? "▶" : "❚❚";
    for (const b of $("speedSeg").children) b.classList.toggle("on", Number(b.dataset.speed) === state.speed);
    for (const b of $("modeSeg").children) {
      b.classList.toggle("on", b.dataset.mode === state.mode);
      if (b.dataset.mode === "live") { b.disabled = !state.live_available; b.title = state.live_message; }
    }
    $("modeHint").innerHTML = state.mode === "live"
      ? `🔴 <b>Live mode</b>: ${esc(state.live_message)}. Each goal costs about 4–6 API calls, and chats cost 1 each (capped per hour).`
      : `🧪 <b>Mock mode</b>: no API calls, placeholder content. ${state.live_available ? "Switch to Live for real research." : esc(state.live_message)}`;
  }

  // --------------------------------------------------------------- cards
  function renderCards() {
    const el = $("cards");
    if (!el.children.length) {
      el.innerHTML = state.villagers.map((v) => `
        <button class="card" data-id="${v.id}">
          <canvas width="96" height="96"></canvas>
          <div class="nm">${esc(v.title)} <span class="pill"></span></div>
          <div class="th"></div>
          <div class="bar"><i></i></div>
        </button>`).join("");
      for (const c of el.children) {
        Game.portrait(c.querySelector("canvas"), names[c.dataset.id]);
        c.onclick = () => { selectVillager(c.dataset.id); setTab("inspect"); };
      }
    }
    for (const c of el.children) {
      const v = names[c.dataset.id];
      const p = c.querySelector(".pill"); p.className = `pill ${v.state}`; p.textContent = v.state;
      c.querySelector(".th").textContent = v.work ? `${v.work.label}…` : v.thought;
      c.querySelector(".bar i").style.width = v.work ? `${Math.round((v.work.progress || 0) * 100)}%` : "0%";
      c.querySelector(".bar").style.visibility = v.work ? "visible" : "hidden";
      c.classList.toggle("sel", v.id === selected);
    }
  }

  function selectVillager(id) { selected = id; store("av.sel", id); Game.select(id); renderCards(); renderInspector(); }

  // ----------------------------------------------------------- inspector
  async function renderInspector() {
    const el = $("tab-inspect");
    if (!selected) { el.innerHTML = `<div class="empty"><span class="big">👆</span>Click a villager on the map to inspect them.</div>`; return; }
    let d; try { d = await api(`/api/villagers/${selected}`); } catch { return; }
    if (tab !== "inspect") return;
    const scrolled = el.scrollTop;
    el.innerHTML = `
      <div class="insp-head"><canvas width="144" height="144"></canvas>
        <div><h3>${esc(d.title)} <span class="pill ${d.state}">${esc(d.state)}</span></h3><p>${esc(d.bio)}</p></div></div>
      <div class="box"><h4>💭 Current thought</h4><div class="thought">“${esc(d.work ? d.work.label + "…" : d.thought)}”</div>
        ${d.bubble ? `<div class="hint">Saying: “${esc(d.bubble)}”</div>` : ""}</div>
      <div class="box"><h4>📋 Current task</h4>${d.task
        ? `<b>${esc(d.task.title)}</b><div class="hint">${esc(d.task.kind)} · <span class="st ${d.task.status}">${esc(d.task.status)}</span></div>`
        : `<span class="hint">Nothing assigned. Free to wander.</span>`}</div>
      <div class="box"><h4>🎒 Inventory</h4><div class="inv">${d.inventory.map((i) => `<span>${esc(i)}</span>`).join("") || '<span class="hint">Empty</span>'}</div></div>
      <div class="box"><h4>🗓️ Schedule</h4><ul class="sched">${d.schedule.map((s) => `<li>${esc(s)}</li>`).join("")}</ul></div>
      <div class="box"><h4>🧠 Memory log</h4><ul class="log">${d.memories.map((m) => `<li><time>${esc(m.sim_time)}</time>${esc(m.text)}</li>`).join("") || '<li>No memories yet.</li>'}</ul></div>
      <div class="box"><h4>💬 Recent chats</h4><ul class="log">${d.chats.map((c) => `<li><time>${esc(c.sim_time)}</time><b>${esc(names[c.speaker]?.name || c.speaker)}:</b> ${esc(c.text)}</li>`).join("") || '<li>Hasn\'t chatted yet.</li>'}</ul></div>`;
    Game.portrait(el.querySelector("canvas"), d);
    el.scrollTop = scrolled;
  }

  // --------------------------------------------------------------- board
  async function refreshBoard() {
    try { board = await api("/api/board"); } catch { return; }
    renderBoard(); renderFeed(); renderFiles();
  }

  function renderBoard() {
    const el = $("tab-board");
    if (!board.goals.length) { el.innerHTML = `<div class="empty"><span class="big">📌</span>No goals yet. Pin one above and Mayor Ada will plan it.</div>`; return; }
    el.innerHTML = board.goals.map((g) => {
      const subs = g.subtasks, done = subs.filter((s) => s.status === "done").length;
      const pct = g.status === "done" ? 100 : subs.length ? Math.round((done / subs.length) * 100) : 5;
      return `<div class="goal"><div class="gh"><b>${esc(g.title)}</b><span class="st ${g.status}">${esc(g.status.replace("_", " "))}</span></div>
        <div class="prog"><i style="width:${pct}%"></i></div>
        <ul class="sub-t">${subs.map((s) => `<li><span title="${esc(s.assignee)}">${s.kind === "research" ? "🔎" : "✍️"}</span>
          <span>${esc(s.title)} <span class="st ${s.status}">${esc(s.status.replace("_", " "))}</span>
          <span class="hint">→ ${esc(names[s.assignee]?.name || s.assignee || "?")}</span>
          ${s.result_path ? `<br>${fileBtn(s.result_path)}` : ""}</span></li>`).join("") || `<li><span>⏳</span><span class="hint">Waiting for Mayor Ada to plan…</span></li>`}</ul></div>`;
    }).join("");
  }

  const fileBtn = (p) => `<button class="file" data-file="${esc(p)}">📄 ${esc(p.replace("workspace/", ""))}</button>`;

  function renderFeed() {
    const items = board.feed.filter((f) => feedFilter === "all" || (feedFilter === "chat" ? f.type === "chat" : f.type === "event"));
    const icon = { system: "⚙️", task: "📌", delegate: "📣", file: "📄", done: "🎉" };
    $("feed").innerHTML = items.map((f) => f.type === "chat"
      ? `<li><time>${esc(f.sim_time.slice(-5))}</time><span class="who" style="color:${names[f.who]?.color}">${esc(names[f.who]?.name || f.who)}</span>
         <span class="hint">to ${esc(names[f.listener]?.name || f.listener)}</span><br><span class="say">${esc(f.text)}</span></li>`
      : `<li class="ev-${f.kind}"><time>${esc(f.sim_time.slice(-5))}</time>${icon[f.kind] || "•"} ${esc(f.text)}${f.file ? `<br>${fileBtn(f.file)}` : ""}</li>`).join("")
      || `<li class="empty">Quiet so far…</li>`;
    const n = board.feed.length;
    if (tab === "feed") seenFeed = n;
    const unseen = Math.max(0, n - seenFeed);
    $("feedBadge").hidden = !unseen; $("feedBadge").textContent = unseen > 30 ? "30+" : unseen;
  }

  function renderFiles() {
    const el = $("tab-files");
    const group = (dir, title, blurb) => {
      const fs = board.files.filter((f) => f.includes(`/${dir}/`));
      return `<div class="box"><h4>${title}</h4><p class="hint">${blurb}</p>${fs.map((f) => `<div>${fileBtn(f)}</div>`).join("") || '<span class="hint">None yet.</span>'}</div>`;
    };
    el.innerHTML = group("outbox", "✉️ Outbox: Maya's summaries", "workspace/outbox/") + group("notes", "📝 Notes: Leo's research", "workspace/notes/");
  }

  // ------------------------------------------------------------ markdown
  function md(src) {
    const inline = (s) => esc(s).replace(/`([^`]+)`/g, "<code>$1</code>").replace(/\*\*([^*]+)\*\*/g, "<b>$1</b>")
      .replace(/\*([^*]+)\*/g, "<i>$1</i>").replace(/\[([^\]]+)\]\((https?:[^)\s]+)\)/g, '<a href="$2" target="_blank" rel="noopener">$1</a>');
    let out = "", list = false;
    for (const line of src.split("\n")) {
      const li = line.match(/^\s*[-*]\s+(.*)/) || line.match(/^\s*\d+\.\s+(.*)/);
      if (li) { if (!list) { out += "<ul>"; list = true; } out += `<li>${inline(li[1])}</li>`; continue; }
      if (list) { out += "</ul>"; list = false; }
      const h = line.match(/^(#{1,3})\s+(.*)/);
      if (h) out += `<h${h[1].length}>${inline(h[2])}</h${h[1].length}>`;
      else if (line.startsWith(">")) out += `<blockquote>${inline(line.replace(/^>\s?/, ""))}</blockquote>`;
      else if (line.trim()) out += `<p>${inline(line)}</p>`;
    }
    return out + (list ? "</ul>" : "");
  }

  async function openFile(path) {
    const r = await fetch(`/api/files/${path}`);
    $("fileName").textContent = path;
    $("fileBody").innerHTML = r.ok ? md(await r.text()) : "<p>Couldn't open that file.</p>";
    $("fileModal").showModal();
  }

  // ------------------------------------------------------------ controls
  function setTab(t) {
    tab = t; store("av.tab", t);
    for (const b of document.querySelectorAll(".tabs button")) b.classList.toggle("on", b.dataset.tab === t);
    for (const id of ["inspect", "board", "feed", "files"]) $(`tab-${id}`).hidden = id !== t;
    if (t === "inspect") renderInspector();
    if (t === "feed" && board) { seenFeed = board.feed.length; renderFeed(); }
  }

  function examples() {
    const ex = ["Compare 3 beginner golf drills for consistent ball striking",
      "Build a 4-week off-ice conditioning plan for rec hockey",
      "Research Claude Skills and summarize how to write a good one"];
    $("examples").innerHTML = ex.map((e) => `<button type="button">${esc(e)}</button>`).join("");
    for (const b of $("examples").children) b.onclick = () => { $("goalTitle").value = b.textContent; $("goalTitle").focus(); };
  }

  function bindControls() {
    document.querySelectorAll(".tabs button").forEach((b) => (b.onclick = () => setTab(b.dataset.tab)));
    $("feedFilters").onclick = (e) => {
      const b = e.target.closest("button"); if (!b) return;
      feedFilter = b.dataset.f;
      for (const x of $("feedFilters").children) x.classList.toggle("on", x === b);
      if (board) renderFeed();
    };
    $("playBtn").onclick = () => api("/api/control", { action: state?.paused ? "resume" : "pause" });
    $("speedSeg").onclick = (e) => { const b = e.target.closest("button"); if (b) api("/api/control", { action: "speed", value: Number(b.dataset.speed) }); };
    $("modeSeg").onclick = async (e) => {
      const b = e.target.closest("button"); if (!b || b.disabled) return;
      try { await api("/api/control", { action: "mode", value: b.dataset.mode }); } catch (err) { alert(err.message); }
    };
    $("zoomIn").onclick = () => Game.zoom(1.3);
    $("zoomOut").onclick = () => Game.zoom(1 / 1.3);
    $("zoomFit").onclick = () => { Game.fit(); $("follow").classList.remove("on"); };
    $("follow").onclick = () => { const on = !Game.following; Game.follow(on); $("follow").classList.toggle("on", on); };
    $("resetBtn").onclick = () => { if (confirm("Reset the village? This clears tasks, memories, chats and generated files.")) api("/api/control", { action: "reset" }); };
    $("goalForm").onsubmit = async (e) => {
      e.preventDefault();
      try {
        await api("/api/tasks", { title: $("goalTitle").value, detail: $("goalDetail").value });
        e.target.reset(); setTab("board");
      } catch (err) { alert(err.message); }
    };
    document.addEventListener("click", (e) => { const f = e.target.closest("[data-file]"); if (f) openFile(f.dataset.file); });
    $("fileClose").onclick = () => $("fileModal").close();
    document.addEventListener("keydown", (e) => {
      if (e.code === "Space" && !["INPUT", "TEXTAREA"].includes(document.activeElement.tagName)) {
        e.preventDefault(); $("playBtn").click();
      }
    });
  }

  boot();
})();
