"""FastAPI app: REST for the sidebar, a WebSocket for 10 Hz villager positions."""
from __future__ import annotations

import asyncio
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse, PlainTextResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

from . import world
from .db import DB, ROOT
from .sim import Simulation

db = DB()
sim = Simulation(db)


@asynccontextmanager
async def lifespan(app: FastAPI):
    if sim.mode == "live":
        ok, _ = sim.set_mode("live")
        if not ok:
            sim.set_mode("mock")
    task = asyncio.create_task(sim.run())
    yield
    task.cancel()


app = FastAPI(title="AI Agent Village", lifespan=lifespan)
app.mount("/static", StaticFiles(directory=ROOT / "static"), name="static")


class GoalIn(BaseModel):
    title: str = Field(min_length=3, max_length=160)
    detail: str = Field(default="", max_length=2000)


class ControlIn(BaseModel):
    action: str
    value: float | str | None = None


@app.get("/")
def index():
    return FileResponse(ROOT / "static" / "index.html")


@app.get("/api/map")
def get_map():
    return world.map_payload()


@app.get("/api/state")
def get_state():
    return sim.snapshot()


@app.get("/api/board")
def get_board():
    return sim.board()


@app.get("/api/villagers/{vid}")
def get_villager(vid: str):
    d = sim.villager_detail(vid)
    if d is None:
        raise HTTPException(404, "no such villager")
    return d


@app.post("/api/tasks")
def post_task(goal: GoalIn):
    return {"id": sim.add_goal(goal.title, goal.detail)}


@app.post("/api/control")
def control(c: ControlIn):
    if c.action == "pause":
        sim.paused = True
    elif c.action == "resume":
        sim.paused = False
    elif c.action == "speed":
        sim.speed = max(0.5, min(16.0, float(c.value or 1)))
    elif c.action == "mode":
        ok, msg = sim.set_mode(str(c.value))
        if not ok:
            raise HTTPException(400, msg)
    elif c.action == "reset":
        sim.reset()
    else:
        raise HTTPException(400, "action must be pause|resume|speed|mode|reset")
    db.set("paused", sim.paused)
    db.set("speed", sim.speed)
    return sim.snapshot()


@app.get("/api/files/{path:path}", response_class=PlainTextResponse)
def read_file(path: str):
    target = (ROOT / path).resolve()
    ws = (ROOT / "workspace").resolve()
    if ws not in target.parents or target.suffix != ".md" or not target.is_file():
        raise HTTPException(404, "file not found")
    return target.read_text()


@app.websocket("/ws")
async def ws(socket: WebSocket):
    await socket.accept()
    try:
        while True:
            await socket.send_json(sim.snapshot())
            await asyncio.sleep(0.1)
    except (WebSocketDisconnect, RuntimeError):
        pass
