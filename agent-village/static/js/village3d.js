// 3D village renderer (Three.js r170). Models: KayKit by Kay Lousberg, CC0 (static/models/CREDITS.md).
// Exposes window.Game with the same API the sidebar (ui.js) already uses.
import * as THREE from "three";
import { GLTFLoader } from "three/addons/loaders/GLTFLoader.js";
import { OrbitControls } from "three/addons/controls/OrbitControls.js";
import * as SkeletonUtils from "three/addons/utils/SkeletonUtils.js";

const HEX_W = 2, ROW_H = Math.sqrt(3);                 // KayKit hexes are 2 units flat-to-flat
const CHAR_SCALE = 0.36;
const BUILDING_SCALE = 1.65;
const ROADS = { A: [0, 3], B: [3, 5], C: [3, 4], D: [1, 3, 5], E: [0, 3, 5], F: [0, 1, 3], G: [2, 3, 4],
  H: [0, 2, 3, 4], I: [1, 2, 4, 5], J: [0, 1, 2, 3], K: [1, 2, 3, 4, 5], L: [0, 1, 2, 3, 4, 5], M: [3] };
const WORK_ANIM = { ada: "Interact", leo: "Use_Item", maya: "Spellcasting" };

const tilePos = (c, r) => new THREE.Vector3((c + 0.5 * (r & 1)) * HEX_W, 0, r * ROW_H);
const mapPos = (x, y) => new THREE.Vector3(x * HEX_W, 0, y * HEX_W);   // server cartesian (hex widths) -> world

let map, renderer, scene, camera, controls, sun, hemi, clock = new THREE.Clock();
let state = null, selected = null, hoverId = null, onSelect = () => {};
const loader = new GLTFLoader();
const cache = {};
const villagers = {};       // id -> {root, mixer, actions, current, pos, yaw}
const doorLights = [];
const clouds = [];
const pickables = [];
let overlay, tip, fireflies, follow = false;
const portraits = {};

// ---------------------------------------------------------------- loading
function model(name) {
  return (cache[name] ??= loader.loadAsync(`/static/models/hex/${name}.gltf`).then((g) => {
    g.scene.traverse((o) => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; } });
    return g.scene;
  }));
}
async function place(name, c, r, rotSteps = 0, y = 0) {
  const s = (await model(name)).clone();
  s.position.copy(tilePos(c, r)); s.position.y = y;
  s.rotation.y = -rotSteps * Math.PI / 3;
  scene.add(s);
  return s;
}
function roadFor(edges) {
  const want = [...edges].sort().join();
  for (const [k, base] of Object.entries(ROADS)) {
    for (let r = 0; r < 6; r++) if (base.map((e) => (e + r) % 6).sort().join() === want) return [`hex_road_${k}`, r];
  }
  return ["hex_road_L", 0];
}

// ------------------------------------------------------------------ setup
async function init(m, canvas) {
  map = m;
  renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
  renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.05;
  scene = new THREE.Scene();
  scene.background = new THREE.Color("#9fd4f2");
  scene.fog = new THREE.Fog("#9fd4f2", 45, 95);

  const cx = (map.cols - 0.5) * HEX_W / 2, cz = (map.rows - 1) * ROW_H / 2;
  cx0 = cx; cz0 = cz;
  camera = new THREE.PerspectiveCamera(32, 1, 0.1, 300);
  camera.position.set(cx, 21, cz + 23);
  controls = new OrbitControls(camera, canvas);
  controls.target.set(cx, 0, cz + 2.2);
  controls.enableDamping = true;
  controls.minDistance = 4; controls.maxDistance = 55;
  controls.minPolarAngle = 0.35; controls.maxPolarAngle = 1.2;
  controls.screenSpacePanning = false;
  controls.addEventListener("start", () => { if (follow) setFollow(false); });
  controls.update();
  window.__home = { pos: camera.position.clone(), target: controls.target.clone() };

  hemi = new THREE.HemisphereLight("#e8f4ff", "#5d7a3a", 1.4);
  scene.add(hemi);
  sun = new THREE.DirectionalLight("#fff1d6", 2.6);
  sun.position.set(cx - 18, 30, cz - 10);
  sun.target.position.set(cx, 0, cz);
  sun.castShadow = true;
  sun.shadow.mapSize.set(2048, 2048);
  Object.assign(sun.shadow.camera, { left: -30, right: 30, top: 30, bottom: -30, near: 1, far: 90 });
  sun.shadow.bias = -0.0004; sun.shadow.normalBias = 0.02;
  scene.add(sun, sun.target);

  await buildWorld();
  await loadVillagers();
  buildFireflies();

  overlay = document.createElement("div"); overlay.className = "overlay";
  canvas.parentElement.appendChild(overlay);
  tip = document.getElementById("tooltip");
  for (const [id, L] of Object.entries(map.locations)) {
    const el = document.createElement("div"); el.className = "plaque"; el.textContent = L.name;
    const p = tilePos(...L.tile); p.y = L.zone ? 1.0 : 2.3;
    labels.push({ el, p, id }); overlay.appendChild(el);
  }
  resize(); new ResizeObserver(resize).observe(canvas.parentElement);
  bindInput(canvas);
  renderer.setAnimationLoop(frame);
}
const labels = [];

async function buildWorld() {
  const roads = new Map(map.roads.map((r) => [r.tile.join(), r.edges]));
  const water = new Set(map.water.map((t) => t.join()));
  const jobs = [];
  for (let r = 0; r < map.rows; r++) for (let c = 0; c < map.cols; c++) {
    const k = `${c},${r}`;
    if (roads.has(k)) { const [name, rot] = roadFor(roads.get(k)); jobs.push(place(name, c, r, rot)); }
    else if (water.has(k)) jobs.push(place("hex_water", c, r));
    else jobs.push(place("hex_grass", c, r, (c * 7 + r * 3) % 6));
  }
  for (const b of map.buildings) {
    jobs.push(place(b.model, b.tile[0], b.tile[1], 0).then((o) => {
      // KayKit buildings face +z (south); turn to face their door
      o.rotation.y = Math.PI / 2 - b.face * Math.PI / 3;
      o.scale.setScalar(b.model.includes("well") ? 1.3 : b.model.includes("grain") || b.model.includes("stage") ? 1.2 : BUILDING_SCALE);
      if (b.id) { o.traverse((m) => { m.userData.loc = b.id; }); pickables.push(o); }
      if (b.model.includes("windmill")) windmill = o;
    }));
  }
  for (const s of map.scenery) {
    jobs.push(place(s.model, s.tile[0], s.tile[1], s.rot, s.water ? -0.12 : 0).then((o) => {
      if (s.small) o.scale.setScalar(0.8);
      if (s.water) bobbers.push(o);
    }));
  }
  // little yards: barrels, crates and sacks on free grass next to buildings
  const busy = new Set([...roads.keys(), ...water, ...map.buildings.map((b) => b.tile.join()), ...map.scenery.map((x) => x.tile.join())]);
  const PROPS = ["barrel", "crate_A_big", "crate_B_small", "sack", "wheelbarrow", "resource_lumber", "crate_open", "bucket_water", "flag_red", "tent", "pallet", "flag_blue"];
  const rnd = (i) => { const x = Math.sin(i * 12.9898) * 43758.5453; return x - Math.floor(x); };
  let n = 0;
  for (const b of map.buildings) {
    if (b.model.includes("well")) continue;
    const [c, r] = b.tile;
    const nbr = (r & 1 ? [[1, 0], [1, 1], [0, 1], [-1, 0], [0, -1], [1, -1]] : [[1, 0], [0, 1], [-1, 1], [-1, 0], [-1, -1], [0, -1]]).map(([dc, dr]) => [c + dc, r + dr]);
    for (const [nc, nr] of nbr) {
      if (busy.has(`${nc},${nr}`) || nc < 1 || nr < 1 || nc >= map.cols - 1 || nr >= map.rows - 1) continue;
      busy.add(`${nc},${nr}`);
      const count = 1 + Math.floor(rnd(++n) * 3);
      for (let i = 0; i < count; i++) {
        const name = PROPS[Math.floor(rnd(++n) * PROPS.length)];
        jobs.push(model(name).then((m) => {
          const o = m.clone(), base = tilePos(nc, nr), a = rnd(++n) * Math.PI * 2, d = 0.25 + rnd(++n) * 0.5;
          o.position.set(base.x + Math.cos(a) * d, 0, base.z + Math.sin(a) * d);
          o.rotation.y = rnd(++n) * Math.PI * 2;
          o.scale.setScalar(name === "tent" ? 1 : 1.25);
          scene.add(o);
        }));
      }
    }
  }
  // round cobbled plaza under the square
  {
    const sq = tilePos(...map.locations.town_square.tile);
    const ring = new THREE.Mesh(new THREE.CylinderGeometry(3.15, 3.25, 0.1, 48), new THREE.MeshStandardMaterial({ color: "#a39782", roughness: 0.95 }));
    const disc = new THREE.Mesh(new THREE.CylinderGeometry(2.95, 2.95, 0.12, 48), new THREE.MeshStandardMaterial({ color: "#d4c6aa", roughness: 0.9 }));
    const inner = new THREE.Mesh(new THREE.CylinderGeometry(1.25, 1.25, 0.13, 32), new THREE.MeshStandardMaterial({ color: "#bfae8d", roughness: 0.9 }));
    for (const [m, y] of [[ring, 0.02], [disc, 0.04], [inner, 0.05]]) { m.position.set(sq.x, y, sq.z); m.receiveShadow = true; scene.add(m); }
    // cobbles
    const cob = new THREE.InstancedMesh(new THREE.CylinderGeometry(0.11, 0.12, 0.05, 6), new THREE.MeshStandardMaterial({ color: "#c3b394", roughness: 1 }), 260);
    const mtx = new THREE.Matrix4(); let i = 0;
    for (let rr = 1.45; rr < 2.9 && i < 260; rr += 0.27) for (let a = 0; a < Math.PI * 2 && i < 260; a += 0.27 / rr) {
      mtx.makeTranslation(sq.x + Math.cos(a) * rr, 0.11, sq.z + Math.sin(a) * rr); cob.setMatrixAt(i++, mtx);
    }
    cob.count = i; cob.receiveShadow = true; scene.add(cob);
  }
  // lanterns: along the roads and around the plaza; they glow at night
  {
    const postMat = new THREE.MeshStandardMaterial({ color: "#4b3a2c", roughness: 0.8 });
    lampMat = new THREE.MeshStandardMaterial({ color: "#ffe2a0", emissive: "#ffb347", emissiveIntensity: 0.15 });
    const addLamp = (x, z) => {
      const g = new THREE.Group();
      const post = new THREE.Mesh(new THREE.CylinderGeometry(0.035, 0.05, 0.9, 8), postMat); post.position.y = 0.45;
      const arm = new THREE.Mesh(new THREE.BoxGeometry(0.22, 0.03, 0.03), postMat); arm.position.set(0.08, 0.9, 0);
      const cap = new THREE.Mesh(new THREE.ConeGeometry(0.1, 0.08, 4), postMat); cap.position.set(0.17, 0.92, 0); cap.rotation.y = Math.PI / 4;
      const glass = new THREE.Mesh(new THREE.BoxGeometry(0.11, 0.13, 0.11), lampMat); glass.position.set(0.17, 0.82, 0);
      for (const m of [post, arm, cap, glass]) { m.castShadow = true; g.add(m); }
      g.position.set(x, 0, z); g.rotation.y = Math.atan2(x - cx0, z - cz0);
      scene.add(g); lamps.push(glass);
    };
    const sq = tilePos(...map.locations.town_square.tile);
    for (let k = 0; k < 6; k++) { const a = k * Math.PI / 3 + Math.PI / 6; addLamp(sq.x + Math.cos(a) * 3.05, sq.z + Math.sin(a) * 3.05); }
    let i = 0;
    for (const r of map.roads) {
      if (++i % 4) continue;
      const p = tilePos(...r.tile), free = [0, 1, 2, 3, 4, 5].find((d) => !r.edges.includes(d));
      if (p.distanceTo(sq) < 3.6) continue;
      if (free === undefined) continue;
      const a = free * Math.PI / 3;
      addLamp(p.x + Math.cos(a) * 0.8, p.z + Math.sin(a) * 0.8);
    }
  }
  // drifting clouds
  for (let i = 0; i < 6; i++) {
    const o = (await model(i % 2 ? "cloud_small" : "cloud_big")).clone();
    o.position.set(i * 7 - 4 + Math.random() * 3, 11 + Math.random() * 3, -7 - Math.random() * 6);
    o.scale.setScalar(1.6);
    o.traverse((m) => { if (m.isMesh) { m.castShadow = true; m.receiveShadow = false; m.material = m.material.clone(); m.material.transparent = true; m.material.opacity = 0.92; } });
    o.userData.speed = 0.25 + Math.random() * 0.3;
    scene.add(o); clouds.push(o);
  }
  // warm lights at the three workplaces, switched on at night
  for (const id of ["library", "post_office", "town_hall", "town_square"]) {
    const L = map.locations[id], p = tilePos(...(id === "town_square" ? L.tile : L.door));
    const light = new THREE.PointLight("#ffb860", 0, 7, 1.6);
    light.position.set(p.x, 1.2, p.z);
    scene.add(light); doorLights.push(light);
  }
  await Promise.all(jobs);
}
let windmill = null, lampMat = null, cx0 = 0, cz0 = 0;
const lamps = [];
const bobbers = [];

async function loadVillagers() {
  const ids = (state?.villagers || [{ id: "ada" }, { id: "leo" }, { id: "maya" }]).map((v) => v.id);
  await Promise.all(ids.map(async (id) => {
    const g = await loader.loadAsync(`/static/models/chars/${id}.glb`);
    const root = SkeletonUtils.clone(g.scene);
    root.scale.setScalar(CHAR_SCALE);
    root.traverse((o) => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; o.userData.villager = id; } });
    const mixer = new THREE.AnimationMixer(root);
    const actions = Object.fromEntries(g.animations.map((a) => [a.name, mixer.clipAction(a)]));
    for (const n of ["Cheer", "PickUp"]) if (actions[n]) { actions[n].setLoop(THREE.LoopOnce); actions[n].clampWhenFinished = true; }
    scene.add(root); pickables.push(root);
    const v = { root, mixer, actions, current: null, pos: null, yaw: 0, el: null };
    villagers[id] = v;
    play(v, "Idle");
    portraits[id] = await renderPortrait(g);
    // per-villager overlay: name tag, bubble, work badge
    const el = document.createElement("div"); el.className = "vtag";
    el.innerHTML = `<div class="bubble" hidden></div><div class="badge" hidden><span></span><i><b></b></i></div><div class="name" hidden></div>`;
    v.el = el;
  }));
}

function play(v, name, fade = 0.3) {
  const next = v.actions[name] || v.actions.Idle;
  if (v.current === next) return;
  next.reset().fadeIn(fade).play();
  if (v.current) v.current.fadeOut(fade);
  v.current = next;
}

async function renderPortrait(gltf) {
  const r = new THREE.WebGLRenderer({ alpha: true, antialias: true, preserveDrawingBuffer: true });
  r.setSize(256, 256); r.toneMapping = THREE.ACESFilmicToneMapping; r.outputColorSpace = THREE.SRGBColorSpace;
  const s = new THREE.Scene();
  s.add(new THREE.HemisphereLight("#ffffff", "#8a7a5a", 2.2));
  const d = new THREE.DirectionalLight("#fff4e0", 2.2); d.position.set(2, 3, 4); s.add(d);
  const m = SkeletonUtils.clone(gltf.scene); s.add(m);
  const mixer = new THREE.AnimationMixer(m);
  const idle = gltf.animations.find((a) => a.name === "Idle"); if (idle) { mixer.clipAction(idle).play(); mixer.update(0.4); }
  const cam = new THREE.PerspectiveCamera(26, 1, 0.1, 50); cam.position.set(0.15, 1.75, 3.6); cam.lookAt(0, 1.55, 0);
  r.render(s, cam);
  const url = r.domElement.toDataURL(); r.dispose();
  return url;
}

function buildFireflies() {
  const n = 70, g = new THREE.BufferGeometry(), pos = new Float32Array(n * 3);
  for (let i = 0; i < n; i++) { pos[i * 3] = Math.random() * map.cols * HEX_W; pos[i * 3 + 1] = 0.3 + Math.random() * 1.2; pos[i * 3 + 2] = Math.random() * map.rows * ROW_H; }
  g.setAttribute("position", new THREE.BufferAttribute(pos, 3));
  fireflies = new THREE.Points(g, new THREE.PointsMaterial({ color: "#fff3a0", size: 0.12, transparent: true, opacity: 0, depthWrite: false, blending: THREE.AdditiveBlending }));
  scene.add(fireflies);
}

// ------------------------------------------------------------------ frame
const C = (h) => new THREE.Color(h);
const SKY = { day: C("#9fd4f2"), dusk: C("#f2a36b"), night: C("#16203f") };
function lighting(minute) {
  const h = minute / 60;
  // 0 = full day, 1 = full night
  const night = h >= 7 && h <= 18 ? 0 : h > 18 && h < 21 ? (h - 18) / 3 : h >= 21 || h < 5 ? 1 : (7 - h) / 2;
  const dusk = h > 17 && h < 20 ? Math.sin(((h - 17) / 3) * Math.PI) : h > 5 && h < 8 ? Math.sin(((h - 5) / 3) * Math.PI) * 0.7 : 0;
  const sky = SKY.day.clone().lerp(SKY.night, night).lerp(SKY.dusk, dusk * 0.6);
  scene.background.copy(sky); scene.fog.color.copy(sky);
  sun.intensity = 2.6 * (1 - night) + 0.25;
  sun.color.set("#fff1d6").lerp(C("#ffb070"), dusk).lerp(C("#9fb4ff"), night);
  hemi.intensity = 1.4 * (1 - night) + 0.35;
  hemi.color.set("#e8f4ff").lerp(C("#6d7fc4"), night);
  for (const l of doorLights) l.intensity = 9 * night;
  if (lampMat) lampMat.emissiveIntensity = 0.15 + night * 3.2;
  fireflies.material.opacity = Math.max(0, night - 0.4) * 1.4;
  renderer.toneMappingExposure = 1.05 - night * 0.15;
}

function frame() {
  const dt = Math.min(clock.getDelta(), 0.05), t = clock.elapsedTime;
  const speed = state && !state.paused ? state.speed : 0;
  if (state) lighting(state.minute);
  for (const c of clouds) { c.position.x += c.userData.speed * dt * (speed ? 1 : 0.2); if (c.position.x > map.cols * HEX_W + 8) c.position.x = -8; }
  for (const b of bobbers) b.position.y = -0.12 + Math.sin(t * 1.5 + b.position.x) * 0.02;
  if (windmill) windmill.traverse((o) => { if (/blade|wing|sail|propeller|rotor/i.test(o.name)) o.rotation.z += dt * 0.8 * Math.max(speed, 0.3); });
  if (fireflies.material.opacity > 0) { const p = fireflies.geometry.attributes.position; for (let i = 0; i < p.count; i++) p.setY(i, 0.5 + Math.sin(t * 1.3 + i) * 0.4 + (i % 5) * 0.15); p.needsUpdate = true; }

  if (state) for (const v of state.villagers) updateVillager(v, dt, t, speed);
  if (follow && selected && villagers[selected]) {
    const p = villagers[selected].root.position;
    controls.target.lerp(new THREE.Vector3(p.x, 0.4, p.z), Math.min(1, dt * 3));
    const want = new THREE.Vector3(p.x, 7, p.z + 8.5);
    camera.position.lerp(want, Math.min(1, dt * 2));
  }
  controls.update();
  renderer.render(scene, camera);
  drawOverlay();
}

function updateVillager(s, dt, t, speed) {
  const v = villagers[s.id]; if (!v) return;
  const target = mapPos(s.x, s.y);
  if (!v.pos) { v.pos = target.clone(); v.yaw = Math.PI / 2 - s.heading; }
  const k = Math.min(1, dt * 10);
  v.pos.lerp(target, k);
  // several villagers on one hex: spread them a little so they don't overlap
  const others = state.villagers.filter((o) => o.id !== s.id && Math.hypot(o.x - s.x, o.y - s.y) < 0.12);
  const off = others.length ? new THREE.Vector3(Math.cos(s.id.length * 2.1) * 0.35, 0, Math.sin(s.id.length * 2.1) * 0.35) : new THREE.Vector3();
  v.root.position.copy(v.pos).add(off);
  const yaw = Math.PI / 2 - s.heading;
  let d = yaw - v.yaw; d = Math.atan2(Math.sin(d), Math.cos(d)); v.yaw += d * Math.min(1, dt * 8);
  v.root.rotation.y = v.yaw;
  const sleeping = /Zzz/.test(s.thought || "");
  let anim = "Idle";
  if (s.state === "walking") anim = "Walking_A";
  else if (s.state === "working") anim = WORK_ANIM[s.id] || "Interact";
  else if (sleeping) anim = "Sit_Floor_Idle";
  if (s.bubble && /🎉|Goal complete/.test(s.bubble) && v.current !== v.actions.Cheer) anim = "Cheer";
  else if (v.current === v.actions.Cheer && v.actions.Cheer.isRunning()) anim = "Cheer";
  play(v, anim);
  v.mixer.timeScale = s.state === "walking" ? Math.min(2.2, 0.9 + speed * 0.12) : 1;
  v.mixer.update(dt * (speed ? 1 : s.state === "walking" ? 0 : 1));
}

// ---------------------------------------------------------------- overlay
const tmp = new THREE.Vector3();
function project(p) {
  tmp.copy(p).project(camera);
  const w = renderer.domElement.clientWidth, h = renderer.domElement.clientHeight;
  return { x: (tmp.x + 1) / 2 * w, y: (1 - tmp.y) / 2 * h, vis: tmp.z < 1 };
}
function drawOverlay() {
  const dist = camera.position.distanceTo(controls.target);
  const scale = Math.max(0.65, Math.min(1.15, 22 / dist));
  for (const L of labels) {
    const s = project(L.p);
    L.el.style.transform = `translate(${s.x}px, ${s.y}px) translate(-50%, -100%) scale(${scale})`;
    L.el.classList.toggle("hot", hoverLoc === L.id);
  }
  if (!state) return;
  for (const s of state.villagers) {
    const v = villagers[s.id]; if (!v) continue;
    if (!v.el.isConnected) overlay.appendChild(v.el);
    const p = project(v.root.position.clone().add(new THREE.Vector3(0, 0.75, 0)));
    v.el.style.transform = `translate(${p.x}px, ${p.y}px)`;
    v.el.style.display = p.vis ? "" : "none";
    const [bubble, badge, name] = v.el.children;
    bubble.hidden = !s.bubble || !!s.work;
    if (s.bubble && bubble.textContent !== s.bubble) bubble.textContent = s.bubble;
    badge.hidden = !s.work;
    if (s.work) { badge.firstChild.textContent = s.work.icon; badge.querySelector("b").style.width = `${Math.round((s.work.progress || 0) * 100)}%`; }
    const showName = selected === s.id || hoverId === s.id;
    name.hidden = !showName; name.textContent = s.title; name.style.setProperty("--c", s.color);
    v.el.classList.toggle("sel", selected === s.id);
  }
  overlay.classList.toggle("paused", !!state.paused);
}

// ------------------------------------------------------------------ input
const ray = new THREE.Raycaster(), ndc = new THREE.Vector2();
let hoverLoc = null, downAt = null;
function pick(e) {
  const r = renderer.domElement.getBoundingClientRect();
  ndc.set(((e.clientX - r.left) / r.width) * 2 - 1, -((e.clientY - r.top) / r.height) * 2 + 1);
  ray.setFromCamera(ndc, camera);
  for (const h of ray.intersectObjects(pickables, true)) {
    if (h.object.userData.villager) return { v: h.object.userData.villager, r, e };
    if (h.object.userData.loc) return { loc: h.object.userData.loc, r, e };
  }
  // generous hit area for small villagers: nearest on screen within 26px
  let best = null, bd = 26;
  for (const [id, v] of Object.entries(villagers)) {
    const p = project(v.root.position.clone().add(new THREE.Vector3(0, 0.3, 0)));
    const d = Math.hypot(p.x - (e.clientX - r.left), p.y - (e.clientY - r.top));
    if (d < bd) { bd = d; best = id; }
  }
  return best ? { v: best, r, e } : { r, e };
}
const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
function bindInput(canvas) {
  canvas.addEventListener("pointermove", (e) => {
    if (e.buttons) { tip.hidden = true; return; }
    const h = pick(e);
    hoverId = h.v || null; hoverLoc = h.loc || null;
    canvas.style.cursor = h.v ? "pointer" : h.loc ? "help" : "grab";
    let html = null;
    if (h.v && state) { const d = state.villagers.find((x) => x.id === h.v); html = `<b>${esc(d.title)}</b> · ${esc(d.state)}<br>${esc(d.work ? d.work.label + "…" : d.thought)}`; }
    else if (h.loc) { const L = map.locations[h.loc]; html = `<b>${esc(L.name)}</b><br>${esc(L.blurb)}`; }
    if (!html) { tip.hidden = true; return; }
    tip.innerHTML = html; tip.hidden = false;
    tip.style.left = Math.min(e.clientX - h.r.left + 14, h.r.width - 250) + "px"; tip.style.top = (e.clientY - h.r.top + 14) + "px";
  });
  canvas.addEventListener("pointerleave", () => { hoverId = hoverLoc = null; tip.hidden = true; });
  canvas.addEventListener("pointerdown", (e) => { downAt = [e.clientX, e.clientY]; });
  canvas.addEventListener("pointerup", (e) => {
    if (!downAt || Math.hypot(e.clientX - downAt[0], e.clientY - downAt[1]) > 5) return;
    const h = pick(e);
    if (h.v) { selected = h.v; onSelect(h.v); }
  });
  canvas.addEventListener("dblclick", () => fit());
}
function resize() {
  const el = renderer.domElement.parentElement, w = el.clientWidth, h = Math.round(w * 0.62);
  renderer.setSize(w, h, false);
  renderer.domElement.style.width = w + "px"; renderer.domElement.style.height = h + "px";
  camera.aspect = w / h; camera.updateProjectionMatrix();
}
function fit() {
  setFollow(false);
  camera.position.copy(window.__home.pos); controls.target.copy(window.__home.target);
}
function setFollow(on) {
  follow = on;
  document.getElementById("follow")?.classList.toggle("on", on);
}
function zoom(f) {
  const dir = camera.position.clone().sub(controls.target);
  const len = THREE.MathUtils.clamp(dir.length() / f, controls.minDistance, controls.maxDistance);
  camera.position.copy(controls.target).add(dir.setLength(len));
}
function portrait(cv, v) {
  const url = portraits[v.id]; if (!url) return;
  const img = new Image();
  img.onload = () => { const c = cv.getContext("2d"); c.clearRect(0, 0, cv.width, cv.height); c.drawImage(img, 0, 0, cv.width, cv.height); };
  img.src = url;
}

window.Game = {
  init, portrait, zoom, fit,
  setState: (s) => { state = s; },
  select: (id) => { selected = id; },
  follow: (on) => setFollow(on),
  get following() { return follow; },
  set onSelect(fn) { onSelect = fn; },
};
