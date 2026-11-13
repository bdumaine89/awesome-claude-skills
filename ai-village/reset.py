#!/usr/bin/env python3
"""Reset the village to its seed state (tasks, noticeboard, clock). Deletes generated research and drafts."""
import shutil
from pathlib import Path

WS = Path(__file__).resolve().parent / "workspace"
shutil.copy(WS / "tasks.seed.json", WS / "tasks.json")
shutil.copy(WS / "noticeboard.seed.md", WS / "noticeboard.md")
(WS / "state.json").unlink(missing_ok=True)
for d in ("research", "outbox"):
    for f in (WS / d).glob("*.md"):
        f.unlink()
print("Village reset to seed state.")
