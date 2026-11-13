"""The simulation: movement (10 Hz), decision ticks (every 6 sim-seconds), roles, chats."""
from __future__ import annotations

import asyncio
import json
import math
import random
import re
import time
from pathlib import Path

from . import world
from .brain import BrainUnavailable, LiveBrain, MockBrain, live_available
from .db import DB, ROOT
from .personas import PERSONAS

WORKSPACE = ROOT / "workspace"
FRAME = 0.1               # real seconds between movement updates
DECISION_EVERY = 6.0      # sim seconds between decision ticks
WALK_SPEED = 3.0          # tiles per sim second
MIN_PER_SIM_SECOND = 1.0  # sim clock: 1 sim second = 1 village minute
START_MINUTE = 8 * 60
CHAT_RADIUS = 2.6
CHAT_COOLDOWN = 75.0
LINE_SECONDS = 3.2


def slug(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")[:48] or "untitled"


class Villager:
    def __init__(self, p: dict):
        self.p = p
        self.id, self.name, self.title = p["id"], p["name"], p["title"]
        self.x, self.y = map(float, p["start"])
        self.path: list[tuple[int, int]] = []
        self.on_arrive = None          # callable run when the path ends
        self.state = "idle"            # idle | walking | working | chatting
        self.thought = "Waking up and stretching."
        self.inventory: list[str] = list(p["inventory"])
        self.task_id: int | None = None
        self.work: dict | None = None  # {label, icon, start, end, job, done}
        self.bubble: dict | None = None
        self.idle_until = 0.0
        self.last_chat = -999.0
        self.last_greet = -999.0
        self.facing = "down"

    @property
    def tile(self) -> tuple[int, int]:
        return round(self.x), round(self.y)

    def busy(self) -> bool:
        return self.work is not None or self.state == "chatting"

    def public(self, now: float) -> dict:
        prog = None
        if self.work:
            span = max(self.work["end"] - self.work["start"], 0.1)
            prog = min(1.0, (now - self.work["start"]) / span)
            if not self.work["job"].done():
                prog = min(prog, 0.92)
        return {
            "id": self.id, "name": self.name, "title": self.title, "color": self.p["color"],
            "hair": self.p["hair"], "skin": self.p["skin"], "accent": self.p["accent"], "hat": self.p["hat"],
            "x": round(self.x, 3), "y": round(self.y, 3), "state": self.state, "facing": self.facing,
            "thought": self.thought,
            "bubble": self.bubble["text"] if self.bubble and self.bubble["until"] > now else None,
            "work": {"label": self.work["label"], "icon": self.work["icon"], "progress": prog} if self.work else None,
        }


class Simulation:
    def __init__(self, db: DB):
        self.db = db
        self.mock = MockBrain()
        self.live = None
        self.now = 0.0
        self.next_decision = 0.0
        self.rev = 0                   # bumps whenever board/feed data changes
        self.villagers = {p["id"]: Villager(p) for p in PERSONAS}
        self.chats: list[dict] = []
        self.paused = db.get("paused", False)
        self.speed = db.get("speed", 1.0)
        self.mode = db.get("mode", "mock")
        self.now = db.get("sim_now", 0.0)
        self._restore()

    # ------------------------------------------------------------ helpers
    @property
    def minute(self) -> int:
        return int(START_MINUTE + self.now * MIN_PER_SIM_SECOND) % 1440

    @property
    def day(self) -> int:
        return int((START_MINUTE + self.now * MIN_PER_SIM_SECOND) // 1440) + 1

    def clock(self) -> str:
        return f"Day {self.day} {self.minute // 60:02d}:{self.minute % 60:02d}"

    def bump(self):
        self.rev += 1

    def event(self, kind, text, file=None, vid=None):
        self.db.event(kind, text, self.clock(), file, vid)
        self.bump()

    def remember(self, v: Villager, text: str):
        self.db.remember(v.id, self.clock(), text)
        self.bump()

    def say(self, v: Villager, text: str, secs: float = 4.0):
        v.bubble = {"text": text, "until": self.now + secs}

    def think(self, v: Villager, text: str):
        v.thought = text

    def _restore(self):
        for row in self.db.q("SELECT * FROM villagers"):
            v = self.villagers.get(row["id"])
            if v:
                v.x, v.y, v.thought = row["x"], row["y"], row["thought"]
                v.inventory = json.loads(row["inventory"])
        # work interrupted by a restart goes back on the board
        self.db.x("UPDATE tasks SET status='pending' WHERE status='in_progress' AND kind!='goal'")
        self.db.x("UPDATE tasks SET status='pending' WHERE status='planning'")
        if not self.db.q("SELECT 1 FROM events LIMIT 1"):
            self.event("system", "The village wakes up. Post a goal at Town Hall to get things moving.")

    def set_mode(self, mode: str) -> tuple[bool, str]:
        if mode == "live":
            ok, msg = live_available()
            if not ok:
                return False, msg
            if self.live is None:
                self.live = LiveBrain()
        self.mode = mode
        self.db.set("mode", mode)
        self.event("system", f"Switched to {'LIVE (Claude API)' if mode == 'live' else 'MOCK (offline)'} mode.")
        return True, mode

    async def brain(self, method: str, *args):
        """Call the active brain; on any live failure, log it and use the mock result."""
        if self.mode == "live" and self.live:
            try:
                return await getattr(self.live, method)(*args), "live"
            except BrainUnavailable as e:
                self.event("system", f"Live {method} failed ({e}); used mock content instead.")
            except Exception as e:  # malformed JSON etc.
                self.event("system", f"Live {method} error ({type(e).__name__}); used mock content instead.")
        return await getattr(self.mock, method)(*args), "mock"

    # ------------------------------------------------------------ movement
    def walk_to(self, v: Villager, tile: tuple[int, int], label: str, on_arrive=None):
        path = world.astar(v.tile, tile)
        v.on_arrive = on_arrive
        if not path:
            v.path = []
            if on_arrive:
                on_arrive()
            return
        v.path = path
        v.state = "walking"
        self.think(v, label)

    def go(self, v: Villager, loc: str, label: str, on_arrive=None):
        self.walk_to(v, world.door(loc), label, on_arrive)

    def _move(self, v: Villager, dt: float):
        if not v.path:
            return
        step = WALK_SPEED * dt
        while step > 0 and v.path:
            tx, ty = v.path[0]
            dx, dy = tx - v.x, ty - v.y
            dist = math.hypot(dx, dy)
            if abs(dx) > abs(dy):
                v.facing = "right" if dx > 0 else "left"
            elif dy:
                v.facing = "down" if dy > 0 else "up"
            if dist <= step:
                v.x, v.y = float(tx), float(ty)
                v.path.pop(0)
                step -= dist
            else:
                v.x += dx / dist * step
                v.y += dy / dist * step
                step = 0
        if not v.path:
            v.state = "idle"
            cb, v.on_arrive = v.on_arrive, None
            if cb:
                cb()

    # ------------------------------------------------------------- working
    def start_work(self, v: Villager, label: str, icon: str, secs: float, coro, on_done):
        v.state = "working"
        v.work = {"label": label, "icon": icon, "start": self.now, "end": self.now + secs,
                  "job": asyncio.ensure_future(coro), "on_done": on_done}
        self.think(v, label + "…")

    def _check_work(self, v: Villager):
        w = v.work
        if not w or self.now < w["end"] or not w["job"].done():
            return
        v.work = None
        v.state = "idle"
        try:
            result = w["job"].result()
        except Exception as e:
            self.event("system", f"{v.name}'s work failed: {e!r}", vid=v.id)
            if v.task_id:
                self.db.update_task(v.task_id, status="pending", assignee=v.id)
                v.task_id = None
            return
        w["on_done"](result)

    # ---------------------------------------------------------------- loop
    async def run(self):
        last = time.monotonic()
        while True:
            await asyncio.sleep(FRAME)
            t = time.monotonic()
            real_dt, last = t - last, t
            if self.paused:
                continue
            dt = min(real_dt, 0.5) * self.speed
            self.now += dt
            for v in self.villagers.values():
                self._move(v, dt)
                self._check_work(v)
            self._advance_chats()
            if self.now >= self.next_decision:
                self.next_decision = self.now + DECISION_EVERY
                self.decide()

    def decide(self):
        self._orchestrate()
        for v in self.villagers.values():
            if v.busy() or v.path and v.state == "walking" and v.on_arrive is not None:
                continue
            role = v.p["role"]
            acted = {"coordinator": self._mayor, "researcher": self._researcher, "writer": self._writer}[role](v)
            if not acted:
                self._idle(v)
        self._maybe_chat()
        self._greetings()
        for v in self.villagers.values():
            self.db.save_villager({"id": v.id, "name": v.name, "role": v.p["role"], "title": v.title,
                                   "color": v.p["color"], "x": v.x, "y": v.y, "state": v.state,
                                   "thought": v.thought, "inventory": v.inventory, "task_id": v.task_id})
        self.db.set("sim_now", self.now)

    # -------------------------------------------------------------- roles
    def _orchestrate(self):
        """Board bookkeeping Ada is responsible for: unblock writing, close goals."""
        ada = self.villagers["ada"]
        for goal in self.db.q("SELECT * FROM tasks WHERE kind='goal' AND status='in_progress'"):
            subs = self.db.q("SELECT * FROM tasks WHERE parent_id=?", (goal["id"],))
            research = [s for s in subs if s["kind"] == "research"]
            writes = [s for s in subs if s["kind"] == "write"]
            if research and all(s["status"] == "done" for s in research):
                for w in writes:
                    if w["status"] == "waiting":
                        self.db.update_task(w["id"], status="pending")
                        self.say(ada, "Maya! Notes are ready, over to you ✍️", 5)
                        self.event("delegate", f"Ada handed “{goal['title']}” to Maya for writing.", vid="ada")
                        self.remember(ada, f"Research for “{goal['title']}” done. Asked Maya to write it up.")
            if writes and all(w["status"] == "done" for w in writes):
                self.db.update_task(goal["id"], status="done", result_path=writes[-1]["result_path"])
                self.event("done", f"🎉 Goal complete: “{goal['title']}”", file=writes[-1]["result_path"])
                self.remember(ada, f"Closed the goal “{goal['title']}”. Good work, team.")
                self.say(ada, "Goal complete! 🎉", 5)

    def _mayor(self, v: Villager) -> bool:
        goal = self.db.q("SELECT * FROM tasks WHERE kind='goal' AND status='pending' ORDER BY id LIMIT 1")
        if not goal:
            return False
        goal = goal[0]
        self.db.update_task(goal["id"], status="planning", assignee="ada")
        v.task_id = goal["id"]
        self.remember(v, f"New goal on the board: “{goal['title']}”. Heading to Town Hall to plan.")

        def plan():
            self.say(v, "Let me think this through… 📋")
            self.start_work(v, "Planning at Town Hall", "📋", 10, self.brain("plan", goal),
                            lambda r: self._planned(v, goal, r))
        self.go(v, "town_hall", f"Walking to Town Hall to plan “{goal['title'][:40]}”", plan)
        return True

    def _planned(self, v: Villager, goal: dict, result):
        plan, source = result
        names = []
        for r in plan["research"]:
            self.db.add_task("research", r["title"][:100], r["question"], goal["id"], "leo")
            names.append(r["title"])
        self.db.add_task("write", f"Summary: {goal['title'][:80]}", plan["writing_brief"], goal["id"], "maya",
                         status="waiting")
        self.db.update_task(goal["id"], status="in_progress")
        v.task_id = None
        self.think(v, plan["thought"])
        self.say(v, f"Leo, please research {len(names)} topic{'s' * (len(names) > 1)}! 🔎", 5)
        self.event("delegate", f"Ada split “{goal['title']}” into {len(names)} research job(s) for Leo "
                               f"+ 1 writing job for Maya ({source}).", vid="ada")
        self.remember(v, f"Planned “{goal['title']}”: " + "; ".join(names))

    def _researcher(self, v: Villager) -> bool:
        t = self.db.q("SELECT * FROM tasks WHERE kind='research' AND assignee=? AND status='pending' "
                      "ORDER BY id LIMIT 1", (v.id,))
        if not t:
            return False
        t = t[0]
        goal = self.db.task(t["parent_id"]) or {"title": t["title"], "detail": ""}
        self.db.update_task(t["id"], status="in_progress")
        v.task_id = t["id"]
        self.say(v, "On it! 🏃")
        self.remember(v, f"Got a research job: “{t['title']}”.")

        def research():
            self.say(v, "Hmm, let me dig in… 📚")
            self.start_work(v, f"Researching “{t['title'][:36]}”", "📚", 14, self.brain("research", goal, t),
                            lambda r: self._researched(v, goal, t, r))
        self.go(v, "library", f"Heading to the Library to research “{t['title'][:40]}”", research)
        return True

    def _researched(self, v, goal, t, result):
        text, source = result
        rel = f"workspace/notes/{goal.get('id', 0):03d}-{t['id']:03d}-{slug(t['title'])}.md"
        (ROOT / rel).write_text(text)
        v.inventory.append(f"📝 {Path(rel).name}")
        self.db.update_task(t["id"], result_path=rel)
        self.event("file", f"Leo wrote notes: {t['title']} ({source})", file=rel, vid=v.id)
        self.remember(v, f"Finished notes on “{t['title']}” → {rel}")
        self.say(v, "Notes done! Taking them to Ada 📝")

        def report():
            self.db.update_task(t["id"], status="done")
            v.inventory = [i for i in v.inventory if Path(rel).name not in i]
            v.task_id = None
            self.say(v, "Here you go, Mayor!")
            self.remember(v, f"Handed my notes on “{t['title']}” to Ada at Town Hall.")
            self.think(v, "Job done. Time for a breather.")
            self.bump()
        self.go(v, "town_hall", "Bringing notes to Town Hall", report)

    def _writer(self, v: Villager) -> bool:
        t = self.db.q("SELECT * FROM tasks WHERE kind='write' AND assignee=? AND status='pending' "
                      "ORDER BY id LIMIT 1", (v.id,))
        if not t:
            return False
        t = t[0]
        goal = self.db.task(t["parent_id"])
        self.db.update_task(t["id"], status="in_progress")
        v.task_id = t["id"]
        self.say(v, "Ooh, a writing job! ✍️")
        self.remember(v, f"Asked to write “{t['title']}”. Collecting notes from Town Hall first.")
        notes_rows = self.db.q("SELECT result_path FROM tasks WHERE parent_id=? AND kind='research' "
                               "AND result_path IS NOT NULL", (goal["id"],))
        notes = [(r["result_path"], (ROOT / r["result_path"]).read_text()) for r in notes_rows
                 if (ROOT / r["result_path"]).exists()]

        def collected():
            for p, _ in notes:
                v.inventory.append(f"📝 {Path(p).name}")
            self.say(v, f"Got {len(notes)} note{'s' * (len(notes) != 1)}. To the Post Office!")
            self.go(v, "post_office", "Carrying notes to the Post Office", write)

        def write():
            self.say(v, "Quill time 🪶")
            self.start_work(v, f"Writing “{goal['title'][:36]}”", "✉️", 14, self.brain("write", goal, t, notes),
                            lambda r: self._written(v, goal, t, r))
        self.go(v, "town_hall", "Picking up Leo's notes at Town Hall", collected)
        return True

    def _written(self, v, goal, t, result):
        text, source = result
        rel = f"workspace/outbox/{goal['id']:03d}-{slug(goal['title'])}.md"
        (ROOT / rel).write_text(text)
        v.inventory = [i for i in v.inventory if not i.startswith("📝")] + [f"✉️ {Path(rel).name}"]
        self.db.update_task(t["id"], result_path=rel)
        self.event("file", f"Maya wrote the summary for “{goal['title']}” ({source})", file=rel, vid=v.id)
        self.remember(v, f"Wrote the summary → {rel}")

        def report():
            self.db.update_task(t["id"], status="done")
            v.inventory = [i for i in v.inventory if not i.startswith("✉️")]
            v.task_id = None
            self.say(v, "Summary's in the outbox, Mayor!")
            self.remember(v, f"Reported the finished summary for “{goal['title']}” to Ada.")
            self.think(v, "That reads nicely, if I say so myself.")
            self.bump()
        self.say(v, "Done! Letting Ada know.")
        self.go(v, "town_hall", "Walking to Town Hall to report", report)

    # ---------------------------------------------------------------- idle
    def _idle(self, v: Villager):
        m = self.minute
        if m >= 22 * 60 or m < 6 * 60:
            spot = world.door(v.p["workplace"])
            if v.tile != spot and not v.path:
                self.walk_to(v, spot, "Heading in for the night")
            elif not v.path:
                v.state = "idle"
                self.think(v, "Zzz… resting until morning.")
            return
        if v.path or self.now < v.idle_until:
            return
        if v.tile not in world.SQUARE_TILES or random.random() < 0.55:
            dest = random.choice(world.SQUARE_TILES)
            label = "Lunch break at the Town Square 🥪" if 12 * 60 <= m < 13 * 60 else "Strolling around the Town Square"
            self.walk_to(v, dest, label)
            v.idle_until = self.now + random.uniform(4, 12)
        else:
            v.idle_until = self.now + random.uniform(6, 14)
            self.think(v, random.choice([
                "Enjoying the sound of the fountain.", "Watching the clouds go by.",
                "Wondering what the next goal will be.", "People-watching. Very important work.",
            ]))

    # --------------------------------------------------------------- chats
    def _context(self) -> str:
        g = self.db.q("SELECT title FROM tasks WHERE kind='goal' ORDER BY id DESC LIMIT 1")
        return g[0]["title"] if g else ""

    def _maybe_chat(self):
        free = [v for v in self.villagers.values()
                if not v.busy() and v.on_arrive is None and self.now - v.last_chat > CHAT_COOLDOWN]
        random.shuffle(free)
        for i, a in enumerate(free):
            for b in free[i + 1:]:
                if b.state == "chatting" or a.state == "chatting":
                    continue
                if math.hypot(a.x - b.x, a.y - b.y) <= CHAT_RADIUS and random.random() < 0.7:
                    self._start_chat(a, b)

    def _start_chat(self, a: Villager, b: Villager):
        for v, o in ((a, b), (b, a)):
            v.path, v.state, v.last_chat = [], "chatting", self.now
            v.facing = ("right" if o.x > v.x else "left") if abs(o.x - v.x) > abs(o.y - v.y) else \
                ("down" if o.y > v.y else "up")
            self.think(v, f"Chatting with {o.name}.")
        job = asyncio.ensure_future(self.brain("chat", {"id": a.id, "name": a.name, "title": a.title},
                                               {"id": b.id, "name": b.name, "title": b.title}, self._context()))
        self.chats.append({"a": a, "b": b, "job": job, "lines": None, "i": 0, "next": self.now, "src": None})

    def _advance_chats(self):
        for c in list(self.chats):
            if c["lines"] is None:
                if not c["job"].done():
                    if self.now - c["a"].last_chat > 20:  # stuck call: give up
                        c["lines"] = []
                    continue
                try:
                    c["lines"], c["src"] = c["job"].result()
                except Exception:
                    c["lines"] = []
            if self.now < c["next"]:
                continue
            if c["i"] < len(c["lines"]):
                line = c["lines"][c["i"]]
                speaker = c["a"] if line["speaker"] == c["a"].id else c["b"]
                listener = c["b"] if speaker is c["a"] else c["a"]
                self.say(speaker, line["text"], LINE_SECONDS)
                self.db.chat(speaker.id, listener.id, line["text"], self.clock())
                self.bump()
                c["i"] += 1
                c["next"] = self.now + LINE_SECONDS
            else:
                for v, o in ((c["a"], c["b"]), (c["b"], c["a"])):
                    v.state = "idle"
                    v.last_chat = self.now
                    v.idle_until = self.now + 3
                    self.think(v, f"Nice chat with {o.name}.")
                if c["lines"]:
                    self.remember(c["a"], f"Chatted with {c['b'].name} at {self.clock()[-5:]}.")
                    self.remember(c["b"], f"Chatted with {c['a'].name} at {self.clock()[-5:]}.")
                self.chats.remove(c)

    def _greetings(self):
        vs = list(self.villagers.values())
        for a in vs:
            for b in vs:
                if a is b or a.state != "walking" or a.on_arrive is None:
                    continue
                if math.hypot(a.x - b.x, a.y - b.y) < 2.2 and self.now - a.last_greet > 30:
                    a.last_greet = self.now
                    self.say(a, random.choice([f"Hi {b.name}! 👋", f"Busy busy, {b.name}!", f"Morning, {b.name}!"
                                               if self.minute < 720 else f"Evening, {b.name}!"]), 2.5)

    # ---------------------------------------------------------- public api
    def add_goal(self, title: str, detail: str = "") -> int:
        tid = self.db.add_task("goal", title.strip()[:160], detail.strip()[:2000])
        self.event("task", f"📌 New goal posted at Town Hall: “{title.strip()[:160]}”")
        return tid

    def snapshot(self) -> dict:
        ok, msg = live_available()
        return {
            "clock": self.clock(), "minute": self.minute, "day": self.day,
            "paused": self.paused, "speed": self.speed, "mode": self.mode,
            "live_available": ok, "live_message": msg, "rev": self.rev,
            "villagers": [v.public(self.now) for v in self.villagers.values()],
        }

    def villager_detail(self, vid: str) -> dict | None:
        v = self.villagers.get(vid)
        if not v:
            return None
        task = self.db.task(v.task_id) if v.task_id else None
        return {
            **v.public(self.now), "bio": v.p["bio"], "role": v.p["role"], "schedule": v.p["schedule"],
            "inventory": v.inventory, "task": task,
            "memories": self.db.q("SELECT sim_time, text FROM memories WHERE villager_id=? ORDER BY id DESC LIMIT 40", (vid,)),
            "chats": self.db.q("SELECT speaker, listener, text, sim_time FROM chats WHERE speaker=? OR listener=? "
                               "ORDER BY id DESC LIMIT 12", (vid, vid)),
        }

    def board(self) -> dict:
        goals = self.db.q("SELECT * FROM tasks WHERE kind='goal' ORDER BY id DESC LIMIT 20")
        for g in goals:
            g["subtasks"] = self.db.q("SELECT * FROM tasks WHERE parent_id=? ORDER BY id", (g["id"],))
        feed = self.db.q(
            "SELECT * FROM (SELECT 'event' AS type, kind, text, file, villager_id AS who, NULL AS listener, sim_time, created_at "
            "FROM events UNION ALL SELECT 'chat', 'chat', text, NULL, speaker, listener, sim_time, created_at FROM chats) "
            "ORDER BY created_at DESC LIMIT 80")
        files = sorted([str(p.relative_to(ROOT)) for d in ("notes", "outbox") for p in (WORKSPACE / d).glob("*.md")],
                       reverse=True)
        return {"rev": self.rev, "goals": goals, "feed": feed, "files": files}

    def reset(self):
        self.db.reset()
        for d in ("notes", "outbox"):
            for f in (WORKSPACE / d).glob("*.md"):
                f.unlink()
        self.chats.clear()
        self.villagers = {p["id"]: Villager(p) for p in PERSONAS}
        self.now = self.next_decision = 0.0
        self.db.set("mode", self.mode)
        self.event("system", "The village was reset.")
