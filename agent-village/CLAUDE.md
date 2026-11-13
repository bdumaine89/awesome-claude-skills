# Agent Village: guide for Claude (and humans)

A local 3D village where three AI agents coordinate real work. FastAPI + SQLite
on the back end, a single-page Three.js (WebGL canvas) front end. All assets are
vendored, so nothing loads from a CDN.

## Run

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python run.py                 # http://127.0.0.1:8000   (--reload for dev, --port N)
```

Live mode needs `ANTHROPIC_API_KEY` in the environment **before** starting the
server. Without it, the Live toggle is disabled and the app runs in Mock mode.

## Architecture

```
run.py               uvicorn launcher
app/main.py          FastAPI routes + /ws WebSocket (10 Hz state push)
app/sim.py           Simulation: movement loop, decision ticks, roles, chats
app/world.py         17×13 hex map (pointy-top, odd-r offset): roads, buildings, scenery, A* over hexes
app/brain.py         MockBrain (offline) / LiveBrain (Claude API), same interface
app/personas.py      Villager definitions (looks, workplace, schedule, starting inventory)
app/db.py            SQLite: villagers, tasks, memories, chats, events, settings
static/js/village3d.js  Three.js renderer: hex tiles + auto-picked road pieces, buildings, plaza,
                       lanterns, animated characters, orbit camera, day/night, HTML overlay for
                       bubbles/labels, raycast picking. Sets window.Game for ui.js
static/models/       KayKit glTF models (hex/) and trimmed character .glb files (chars/), CREDITS.md
static/vendor/three/ Three.js r170 + the three addons we import (MIT)
tools/build_models.mjs  Rebuilds static/models + static/vendor from the free sources (see "Art")
static/js/ui.js      Sidebar: controls, inspector, task board, activity feed, files
workspace/notes/     Leo's research notes (markdown)
workspace/outbox/    Maya's summaries (markdown)
data/village.db      SQLite database (gitignored; delete it or press Reset to start over)
```

**Two clocks, on purpose**
- *Movement* runs every 100 ms (`FRAME`) so walking looks smooth. The client
  smooths it further at 60 fps.
- *Decisions* run every 6 sim-seconds (`DECISION_EVERY`): check the board,
  pick up work, start chats, save state. Speed (1–16×) scales sim time, and
  with it both clocks.
- Sim clock: 1 sim-second is 1 village minute, starting Day 1 at 08:00.
- Positions: the server moves villagers in "cartesian" hex units
  (`world.center` / `world.nearest`). The client multiplies by 2 for
  Three.js world units.

**Task flow** (`tasks` table, `kind` + `status`)
```
goal (pending) ──Ada plans at Town Hall──▶ goal (in_progress)
   ├─ research × 1–3 → Leo: pending → in_progress → done   (Library → notes/*.md → reports to Town Hall)
   └─ write     × 1  → Maya: waiting → pending → in_progress → done
                       (unblocked by Ada when all research is done;
                        collects notes at Town Hall → Post Office → outbox/*.md → reports)
goal → done   (Ada closes it once the write task is done)
```

**Villager states:** `idle`, `walking`, `working`, `chatting`. Only `idle`
villagers, with no errand pending, can start a chat. Chats need two idle
villagers within `CHAT_RADIUS` tiles, and there is a cooldown.

**Brains.** The brain writes *content only* (plans, notes, summaries,
dialogue). It never controls movement. Any live failure (missing key, rate
limit, refusal, bad JSON, hourly cap) logs a system event and falls back to
the mock result, so the village never stalls.

## Agent rules

1. **Stay in your lane.** Ada plans and delegates; she never writes notes or
   summaries. Leo writes only to `workspace/notes/`. Maya writes only to
   `workspace/outbox/`, and only from Leo's notes.
2. **Honesty over polish.** Notes end with a Sources section. Without web
   search, Leo says "from model knowledge" and flags anything that may be
   out of date. Maya cites note paths and adds no new facts.
3. **Nothing leaves the village.** Agents only write local markdown files.
   They send no email, post nothing and call no external services apart from
   the Claude API in Live mode.
4. **Spend carefully.**
   - Live mode is opt-in from the UI.
   - Calls are capped by `VILLAGE_MAX_CALLS_PER_HOUR` (default 40).
   - A typical goal costs 4–6 calls (1 plan + 1–3 notes + 1 summary), and
     each chat costs 1.
   - Web search is off unless `VILLAGE_WEB_SEARCH=1`, because it bills per
     search.
   - Don't raise limits or switch on paid features without asking the user.
   - Before using any paid image, 3D or audio generation tool for art
     (e.g. Higgsfield), quote the cost and get an explicit yes.

| Env var | Default | Purpose |
|---|---|---|
| `VILLAGE_MODEL` | `claude-opus-5-5` | Model for live calls. `claude-haiku-5-5` is the cheapest |
| `VILLAGE_MAX_CALLS_PER_HOUR` | `40` | Hard cap on live calls. Over the cap, villagers fall back to mock |
| `VILLAGE_WEB_SEARCH` | `0` | `1` lets Leo use Claude's web search tool (max 3 searches per note) |

## Adding a villager

1. **Define them** in `app/personas.py`: `id`, `name`, `title`, `role`,
   `color` (UI accent), `workplace` (a key in `world.LOCATIONS`), `start`
   (a walkable tile), `bio`, `schedule` (display text) and `inventory`.
2. **Give them a body.**
   - Add `<id>: "<Character>"` to `VILLAGERS` in `tools/build_models.mjs`.
     The Adventurers pack has Knight, Mage, Rogue, Rogue_Hooded and
     Barbarian.
   - Rebuild the models.
   - Add the id's working animation to `WORK_ANIM` in `static/js/village3d.js`.
   - Make `start` in `personas.py` a walkable hex `(col, row)`.
3. **Give them a job** in `app/sim.py`:
   - Write a role method like `_researcher(self, v) -> bool`. Return `True`
     if they took on work this tick, and `False` to fall through to idling
     and chatting.
   - Register it in `decide()`'s role map.
   - The usual pattern is: claim a task → `self.go(v, "<location>", label, on_arrive)`
     → `self.start_work(v, label, icon, secs, self.brain("<method>", ...), on_done)`
     → write a file → walk back to report.
4. **New kind of work?**
   - Add the task `kind` where Ada plans (`_planned`).
   - Add a matching method to **both** `MockBrain` and `LiveBrain` in
     `app/brain.py`, with the same signature.
5. **New building?**
   - Add a `world.LOCATIONS` entry with `model` (a file in
     `static/models/hex/`), `tile` and `door` (a neighbouring hex). The door
     must join the road network, so stamp a road with `_road(a, b)` in
     `build()`.
   - Purely decorative buildings go in `DECOR_BUILDINGS`.
6. **Check it:** `rm -rf data && python run.py`, post a goal at 16× speed, and
   watch the Activity tab.

## Art (free, CC0)

- **Village and characters:** by Kay Lousberg, released as CC0 (public
  domain). They come from the
  [KayKit Medieval Hexagon Pack](https://github.com/KayKit-Game-Assets/KayKit-Medieval-Hexagon-Pack-1.0)
  and the
  [KayKit Adventurers Character Pack](https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0).
  Mayor Ada is the Knight, Scout Leo the Rogue and Scribe Maya the Mage.
- **Trimming:** the characters keep 9 of their 76 animations, and their
  weapons are removed.
- **Credit:** attribution isn't required, but `static/models/CREDITS.md`
  credits the artist anyway.
- **Custom pieces:** the plaza, cobbles and lanterns are simple Three.js
  geometry made in `village3d.js`.
- **Road tiles:** each road hex lists the neighbour directions it connects.
  The client picks the KayKit road piece and rotation that match (the
  `ROADS` table). Directions are 0=E, 1=SE, 2=SW, 3=W, 4=NW, 5=NE. Buildings
  face `face` (their door direction); KayKit models face +z by default.

To change models, edit `MODELS` / `VILLAGERS` / `ANIMS` in `tools/build_models.mjs` and rebuild:
```bash
git clone --depth 1 https://github.com/KayKit-Game-Assets/KayKit-Medieval-Hexagon-Pack-1.0 hex
git clone --depth 1 https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0 chars
cd tools && npm install && node build_models.mjs --hex ../hex --chars ../chars
```
Paid art generation (e.g. Higgsfield) is never part of this pipeline. The
user has said not to spend credits.

## Conventions

- No CDNs or runtime downloads. Everything the page needs is in `static/`.
- The client is read-mostly. All state changes go through `POST /api/tasks` or
  `POST /api/control`.
- `GET /api/files/<path>` serves only `.md` files inside `workspace/`.
  Keep it that way.
- Restarting mid-task is safe: in-progress subtasks go back to `pending`, and
  the villager picks them up again.
