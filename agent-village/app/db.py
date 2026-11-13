"""SQLite persistence: villagers, tasks, memories, chats, activity feed, settings."""
from __future__ import annotations

import json
import sqlite3
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DB_PATH = ROOT / "data" / "village.db"

SCHEMA = """
CREATE TABLE IF NOT EXISTS villagers (
    id TEXT PRIMARY KEY, name TEXT, role TEXT, title TEXT, color TEXT,
    x REAL, y REAL, state TEXT, thought TEXT, inventory TEXT, task_id INTEGER,
    updated_at REAL
);
CREATE TABLE IF NOT EXISTS tasks (
    id INTEGER PRIMARY KEY AUTOINCREMENT, parent_id INTEGER, kind TEXT,
    title TEXT, detail TEXT, assignee TEXT, status TEXT, result_path TEXT,
    created_at REAL, updated_at REAL
);
CREATE TABLE IF NOT EXISTS memories (
    id INTEGER PRIMARY KEY AUTOINCREMENT, villager_id TEXT, sim_time TEXT, text TEXT, created_at REAL
);
CREATE TABLE IF NOT EXISTS chats (
    id INTEGER PRIMARY KEY AUTOINCREMENT, speaker TEXT, listener TEXT, text TEXT,
    sim_time TEXT, created_at REAL
);
CREATE TABLE IF NOT EXISTS events (
    id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT, text TEXT, file TEXT, villager_id TEXT,
    sim_time TEXT, created_at REAL
);
CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT);
CREATE INDEX IF NOT EXISTS idx_mem_v ON memories(villager_id, id);
CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status, assignee);
"""


class DB:
    def __init__(self, path: Path = DB_PATH):
        path.parent.mkdir(parents=True, exist_ok=True)
        self.conn = sqlite3.connect(path, check_same_thread=False)
        self.conn.row_factory = sqlite3.Row
        self.lock = threading.Lock()
        with self.lock:
            self.conn.executescript(SCHEMA)
            self.conn.commit()

    def q(self, sql: str, args: tuple = ()) -> list[dict]:
        with self.lock:
            return [dict(r) for r in self.conn.execute(sql, args).fetchall()]

    def x(self, sql: str, args: tuple = ()) -> int:
        with self.lock:
            cur = self.conn.execute(sql, args)
            self.conn.commit()
            return cur.lastrowid

    # settings ---------------------------------------------------------------
    def get(self, key: str, default=None):
        rows = self.q("SELECT value FROM settings WHERE key=?", (key,))
        return json.loads(rows[0]["value"]) if rows else default

    def set(self, key: str, value) -> None:
        self.x("INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
               (key, json.dumps(value)))

    # tasks ------------------------------------------------------------------
    def add_task(self, kind, title, detail="", parent_id=None, assignee=None, status="pending") -> int:
        now = time.time()
        return self.x("INSERT INTO tasks(parent_id,kind,title,detail,assignee,status,created_at,updated_at) "
                      "VALUES(?,?,?,?,?,?,?,?)", (parent_id, kind, title, detail, assignee, status, now, now))

    def update_task(self, tid: int, **fields) -> None:
        fields["updated_at"] = time.time()
        cols = ", ".join(f"{k}=?" for k in fields)
        self.x(f"UPDATE tasks SET {cols} WHERE id=?", (*fields.values(), tid))

    def task(self, tid) -> dict | None:
        r = self.q("SELECT * FROM tasks WHERE id=?", (tid,))
        return r[0] if r else None

    # logs -------------------------------------------------------------------
    def remember(self, vid: str, sim_time: str, text: str) -> None:
        self.x("INSERT INTO memories(villager_id,sim_time,text,created_at) VALUES(?,?,?,?)",
               (vid, sim_time, text, time.time()))

    def event(self, kind: str, text: str, sim_time: str, file: str | None = None, vid: str | None = None) -> None:
        self.x("INSERT INTO events(kind,text,file,villager_id,sim_time,created_at) VALUES(?,?,?,?,?,?)",
               (kind, text, file, vid, sim_time, time.time()))

    def chat(self, speaker: str, listener: str, text: str, sim_time: str) -> None:
        self.x("INSERT INTO chats(speaker,listener,text,sim_time,created_at) VALUES(?,?,?,?,?)",
               (speaker, listener, text, sim_time, time.time()))

    def save_villager(self, v: dict) -> None:
        self.x("INSERT INTO villagers(id,name,role,title,color,x,y,state,thought,inventory,task_id,updated_at) "
               "VALUES(?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET x=excluded.x, y=excluded.y, "
               "state=excluded.state, thought=excluded.thought, inventory=excluded.inventory, "
               "task_id=excluded.task_id, updated_at=excluded.updated_at",
               (v["id"], v["name"], v["role"], v["title"], v["color"], v["x"], v["y"], v["state"],
                v["thought"], json.dumps(v["inventory"]), v["task_id"], time.time()))

    def reset(self) -> None:
        with self.lock:
            for t in ("villagers", "tasks", "memories", "chats", "events", "settings"):
                self.conn.execute(f"DELETE FROM {t}")
            self.conn.execute("DELETE FROM sqlite_sequence")
            self.conn.commit()
