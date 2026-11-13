"""Simulation core: clock, villagers, task board, and building functions."""
from __future__ import annotations

import json
import os
import random
import re
import shlex
import subprocess
import threading
import time
import uuid
from collections import deque
from concurrent.futures import Future, ThreadPoolExecutor
from pathlib import Path

from .brains import make_brain
from .world import World

ROOT = Path(__file__).resolve().parent.parent
WS = ROOT / "workspace"
TASKS = WS / "tasks.json"
STATE = WS / "state.json"
BOARD = WS / "noticeboard.md"

MIN_PER_TICK = 2          # sim minutes per tick
WORK_TICKS = 12           # minimum time spent inside a building on a task (~24 sim min)
DAY_START = 6 * 60        # sim starts at 06:00 on day 1
DIGEST_AT = 16 * 60 + 30  # Dee's daily digest is auto-requested at 16:30


def hhmm(minutes: int) -> str:
    m = minutes % (24 * 60)
    return f"{m // 60:02d}:{m % 60:02d}"


def to_min(s: str) -> int:
    h, m = s.split(":")
    return int(h) * 60 + int(m)


def slug(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")[:40] or "task"


class Villager:
    def __init__(self, cfg: dict, start: tuple[int, int]):
        self.cfg = cfg
        self.id = cfg["id"]
        self.name = cfg["name"]
        self.x, self.y = start
        self.path: list[tuple[int, int]] = []
        self.dest: str | None = None
        self.at: str | None = cfg["home"]
        self.task_id: str | None = None
        self.work_left = 0
        self.job: Future | None = None
        self.posting = False           # walking to noticeboard to log a finished task
        self.leisure_spot: str | None = None
        self.next_check = 0
        self.status = "Waking up"
        self.bubble: tuple[str, int] | None = None

    def schedule_activity(self, minute_of_day: int) -> str:
        for block in self.cfg["schedule"]:
            if to_min(block["from"]) <= minute_of_day < to_min(block["to"]):
                return block["activity"]
        return "sleep"

    def snapshot(self, tick: int) -> dict:
        return {
            "id": self.id, "name": self.name, "role": self.cfg["role"], "color": self.cfg["color"],
            "x": self.x, "y": self.y, "at": self.at, "dest": self.dest, "status": self.status,
            "task": self.task_id, "indoors": self.at is not None and not self.path and self.at != "park",
            "bubble": self.bubble[0] if self.bubble and self.bubble[1] > tick else None,
        }

    def to_state(self) -> dict:
        return {"x": self.x, "y": self.y, "at": self.at, "task_id": self.task_id}


class Village:
    def __init__(self):
        self.world = World(ROOT / "map" / "village.json")
        cfgs = json.loads((ROOT / "villagers" / "villagers.json").read_text())["villagers"]
        self.lock = threading.RLock()
        self.events: deque = deque(maxlen=200)
        self.pool = ThreadPoolExecutor(max_workers=4)
        self.brain = make_brain(self.log)
        self.tick_n = 0
        self.clock = DAY_START
        self.paused = False
        self.speed = 1.0
        self.villagers = {c["id"]: Villager(c, self.world.door(c["home"])) for c in cfgs}
        self.tasks: list[dict] = []
        self._tasks_mtime = 0.0
        self._load()
        self.log(f"Village opened. Brain: {self.brain.name}.")

    # ---------------------------------------------------------------- io
    def log(self, text: str) -> None:
        clock = getattr(self, "clock", DAY_START)
        self.events.appendleft({"t": f"Day {clock // 1440 + 1} {hhmm(clock)}", "text": text})

    def _load(self) -> None:
        self._reload_tasks(force=True)
        if STATE.exists():
            s = json.loads(STATE.read_text())
            self.clock = s.get("clock", DAY_START)
            for vid, vs in s.get("villagers", {}).items():
                v = self.villagers.get(vid)
                if v:
                    v.x, v.y, v.at, v.task_id = vs["x"], vs["y"], vs["at"], vs["task_id"]

    def _reload_tasks(self, force: bool = False) -> None:
        """Pick up edits made to tasks.json by hand or by another process (e.g. Claude Code)."""
        if not TASKS.exists():
            TASKS.write_text("[]\n")
        mtime = TASKS.stat().st_mtime
        if force or mtime != self._tasks_mtime:
            self.tasks = json.loads(TASKS.read_text() or "[]")
            self._tasks_mtime = mtime

    def _save_tasks(self) -> None:
        TASKS.write_text(json.dumps(self.tasks, indent=2) + "\n")
        self._tasks_mtime = TASKS.stat().st_mtime

    def save(self) -> None:
        with self.lock:
            STATE.write_text(json.dumps({
                "clock": self.clock,
                "villagers": {v.id: v.to_state() for v in self.villagers.values()},
            }, indent=2) + "\n")

    # ------------------------------------------------------------- tasks
    def add_task(self, title: str, kind: str = "general", detail: str = "", to: str = "",
                 after: str | None = None) -> dict:
        with self.lock:
            self._reload_tasks()
            task = {
                "id": "t" + uuid.uuid4().hex[:7],
                "title": title.strip()[:120], "kind": kind, "detail": detail.strip()[:2000],
                "status": "open", "assignee": None, "created": f"Day {self.clock // 1440 + 1} {hhmm(self.clock)}",
            }
            if to:
                task["to"] = to
            if after:
                task["after"] = after
            self.tasks.append(task)
            self._save_tasks()
            self.log(f"New request at Town Hall: “{task['title']}” ({kind}).")
            return task

    def task(self, tid: str | None) -> dict | None:
        return next((t for t in self.tasks if t["id"] == tid), None)

    def _ready(self, t: dict) -> bool:
        dep = self.task(t.get("after"))
        return dep is None or dep["status"] == "done"

    def _claim(self, v: Villager) -> dict | None:
        skills = v.cfg["skills"]
        open_ = [t for t in self.tasks if t["status"] == "open" and self._ready(t)]
        pick = None
        if "triage" in skills:
            pick = next((t for t in open_ if t["kind"] == "general"), None)
        if not pick:
            pick = next((t for t in open_ if t["kind"] in skills), None)
        if not pick:
            return None
        pick["status"] = "claimed"
        pick["assignee"] = v.name
        self._save_tasks()
        return pick

    # -------------------------------------------------------------- tick
    def tick(self) -> None:
        with self.lock:
            if self.tick_n % 10 == 0:
                self._reload_tasks()
            self.tick_n += 1
            self.clock += MIN_PER_TICK
            mod = self.clock % 1440
            if mod == DIGEST_AT:
                self.add_task(f"Daily digest — Day {self.clock // 1440 + 1}", kind="digest")
            for v in self.villagers.values():
                self._step(v, mod)
            if self.tick_n % 30 == 0:
                self.save()

    def _go(self, v: Villager, loc_id: str) -> None:
        if v.dest == loc_id and v.path:
            return
        goal = self.world.door(loc_id)
        v.dest = loc_id
        v.at = None
        v.path = self.world.find_path((v.x, v.y), goal)
        if not v.path:  # already there (or unreachable)
            v.at = loc_id
            v.dest = None

    def _say(self, v: Villager, text: str, ticks: int = 25) -> None:
        v.bubble = (text, self.tick_n + ticks)

    def _step(self, v: Villager, mod: int) -> None:
        # 1. Background job (brain call) in progress or finished
        if v.job is not None:
            if not v.job.done():
                v.status = f"Working at {self.world.locations[v.at]['name']}…"
                return
            self._finish_job(v)
            return

        # 2. Walking
        if v.path:
            v.x, v.y = v.path.pop(0)
            if not v.path:
                v.at, v.dest = v.dest, None
                self._arrived(v)
            return

        # 3. Decide what to do next
        activity = v.schedule_activity(mod)
        if v.posting:
            return self._go_or(v, "noticeboard", lambda: self._post(v))

        if activity == "sleep":
            v.leisure_spot = None
            if v.at == v.cfg["home"]:
                v.status = "Sleeping 💤"
            else:
                v.status = "Heading home"
                self._go(v, v.cfg["home"])
            return

        if activity == "lunch":
            return self._go_or(v, "cafe", lambda: self._socialise(v, "Lunch at the Cafe"))

        if activity == "leisure":
            v.leisure_spot = v.leisure_spot or random.choice(["cafe", "park", "park", v.cfg["home"]])
            return self._go_or(v, v.leisure_spot, lambda: self._socialise(v, "Off the clock"))

        # activity == "work"
        v.leisure_spot = None
        t = self.task(v.task_id)
        if t and t["status"] == "claimed":
            target = "town_hall" if t["kind"] == "general" else self.world.task_routes[t["kind"]]
            return self._go_or(v, target, lambda: self._start_work(v, t))
        v.task_id = None
        if self.tick_n < v.next_check:
            post = v.cfg.get("post", "park")
            return self._go_or(v, post, lambda: setattr(v, "status", v.cfg.get("idle", "Idle — no matching work")))
        self._go_or(v, "town_hall", lambda: self._check_inbox(v))

    def _go_or(self, v: Villager, loc: str, on_there) -> None:
        if v.at == loc:
            on_there()
        else:
            v.status = f"Walking to {self.world.locations[loc]['name']}"
            self._go(v, loc)

    def _arrived(self, v: Villager) -> None:
        pass  # actions happen on the next tick's decision step

    # ------------------------------------------------------- behaviours
    def _check_inbox(self, v: Villager) -> None:
        t = self._claim(v)
        if t is None:
            v.status = "Checked the inbox — nothing for me"
            v.next_check = self.tick_n + 40
            return
        v.task_id = t["id"]
        triage = t["kind"] == "general"
        self.log(f"{v.name} {'is triaging' if triage else 'claimed'} “{t['title']}”.")
        self._say(v, "I'll sort this one." if triage else f"On it: {t['title'][:28]}")

    def _socialise(self, v: Villager, label: str) -> None:
        v.status = label
        if random.random() < 0.03:
            others = [o for o in self.villagers.values() if o is not v and o.at == v.at and not o.path]
            if others:
                other = random.choice(others)
                line = self.brain.chat(v.cfg, other.cfg)
                self._say(v, line)
                self.log(f"{v.name} to {other.name}: “{line}”")

    def _start_work(self, v: Villager, t: dict) -> None:
        if v.work_left == 0:
            v.work_left = WORK_TICKS
            v.status = f"Working on “{t['title'][:30]}”"
            return
        v.work_left -= 1
        if v.work_left > 1:
            return
        v.work_left = 0
        kind = t["kind"]
        fn = {"general": self._job_triage, "research": self._job_research,
              "email": self._job_email, "digest": self._job_digest}[kind]
        v.job = self.pool.submit(fn, v.cfg, dict(t))
        v.status = f"Working at {self.world.locations[v.at]['name']}…"

    def _finish_job(self, v: Villager) -> None:
        job, v.job = v.job, None
        t = self.task(v.task_id)
        try:
            result = job.result()
        except Exception as e:  # never let one bad job kill the loop
            self.log(f"{v.name} hit an error: {e!r}. Task returned to the inbox.")
            if t:
                t["status"], t["assignee"] = "open", None
                self._save_tasks()
            v.task_id = None
            return
        if t is None:
            v.task_id = None
            return
        if result.get("triaged"):
            t["kind"], t["status"], t["assignee"] = result["kind"], "open", None
            t["note"] = result.get("note", "")
            self._save_tasks()
            self.log(f"{v.name} routed “{t['title']}” → {result['kind']}.")
            self._say(v, f"That's a {result['kind']} job.")
            v.task_id = None
            return
        t["result"] = result.get("file")
        self._save_tasks()
        if t["kind"] == "digest":
            self._complete(v, t, "posted the daily digest")
        else:
            v.posting = True
            self._say(v, "Done! Off to the noticeboard.")

    def _post(self, v: Villager) -> None:
        v.posting = False
        t = self.task(v.task_id)
        if t:
            self._complete(v, t, f"finished “{t['title']}”")

    def _complete(self, v: Villager, t: dict, verb: str) -> None:
        t["status"] = "done"
        t["done"] = f"Day {self.clock // 1440 + 1} {hhmm(self.clock)}"
        self._save_tasks()
        stamp = t["done"]
        line = f"- **{stamp}** — {v.name} {verb}" + (f" → `{t['result']}`" if t.get("result") else "")
        with BOARD.open("a") as f:
            f.write(line + "\n")
        self.log(f"📌 {v.name} {verb}.")
        v.task_id = None
        v.status = "Posted to the noticeboard"

    # ------------------------------------------------------------- jobs
    # Run on the thread pool; must not touch Village state without the lock.
    def _job_triage(self, persona: dict, t: dict) -> dict:
        r = self.brain.triage(persona, t)
        kind = r.get("kind") if r.get("kind") in ("research", "email", "digest") else "research"
        return {"triaged": True, "kind": kind, "note": r.get("note", "")}

    def _job_research(self, persona: dict, t: dict) -> dict:
        text = self.brain.research(persona, t)
        out = WS / "research" / f"{t['id']}-{slug(t['title'])}.md"
        out.write_text(text)
        return {"file": str(out.relative_to(ROOT))}

    def _job_email(self, persona: dict, t: dict) -> dict:
        context = ""
        dep = self.task(t.get("after"))
        if dep and dep.get("result") and (ROOT / dep["result"]).exists():
            context = (ROOT / dep["result"]).read_text()
        draft = self.brain.email(persona, t, context)
        out = WS / "outbox" / f"{t['id']}-{slug(t['title'])}.md"
        out.write_text(draft)
        self._maybe_claude_code("post_office", persona, f"An email draft is at {out}. {t['title']}")
        return {"file": str(out.relative_to(ROOT))}

    def _job_digest(self, persona: dict, t: dict) -> dict:
        with self.lock:
            done = [{"title": x["title"], "by": x.get("assignee")} for x in self.tasks if x["status"] == "done"]
            open_ = [{"title": x["title"]} for x in self.tasks if x["status"] != "done" and x["id"] != t["id"]]
        text = self.brain.digest(persona, done, open_)
        with BOARD.open("a") as f:
            f.write(f"\n### {t['title']}\n\n{text}\n\n")
        return {"file": str(BOARD.relative_to(ROOT))}

    def _maybe_claude_code(self, loc_id: str, persona: dict, instruction: str) -> None:
        """Optional hand-off to Claude Code (headless) for real MCP tools.

        Off unless VILLAGE_EXECUTOR=claude-code AND the building lists explicit
        `claude_code_tools` in map/village.json. Only those tools are allowed.
        """
        tools = self.world.locations[loc_id].get("claude_code_tools") or []
        if os.environ.get("VILLAGE_EXECUTOR") != "claude-code" or not tools:
            return
        prompt = (f"You are {persona['name']}, {persona['role']} of the AI village. {instruction}\n"
                  "Follow ai-village/CLAUDE.md. Create drafts only; never send anything.")
        cmd = ["claude", "-p", prompt, "--allowedTools", ",".join(tools)]
        self.log(f"{persona['name']} hands off to Claude Code: {shlex.join(cmd[:2])} …")
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=300, cwd=ROOT.parent)
            self.log(f"Claude Code finished (exit {r.returncode}): {r.stdout.strip()[:160]}")
        except (OSError, subprocess.TimeoutExpired) as e:
            self.log(f"Claude Code hand-off failed: {e!r}")

    # --------------------------------------------------------- snapshot
    def snapshot(self) -> dict:
        with self.lock:
            return {
                "day": self.clock // 1440 + 1, "time": hhmm(self.clock), "minute": self.clock % 1440,
                "paused": self.paused, "speed": self.speed, "brain": self.brain.name, "tick": self.tick_n,
                "villagers": [v.snapshot(self.tick_n) for v in self.villagers.values()],
                "tasks": self.tasks[-30:],
                "events": list(self.events)[:60],
            }

    # ------------------------------------------------------------- loop
    def run_forever(self, tick_seconds: float = 0.25) -> None:
        while True:
            if not self.paused:
                self.tick()
            time.sleep(tick_seconds / max(self.speed, 0.1))

    def run_minutes(self, sim_minutes: int) -> None:
        """Headless catch-up for cron: advance the clock, waiting on jobs synchronously."""
        for _ in range(sim_minutes // MIN_PER_TICK):
            self.tick()
            for v in self.villagers.values():
                if v.job is not None:
                    v.job.exception()  # blocks until the brain call finishes
        self.save()
