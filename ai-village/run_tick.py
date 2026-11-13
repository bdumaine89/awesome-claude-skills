#!/usr/bin/env python3
"""Headless catch-up for cron / Claude Code scheduled tasks.

Advances the village clock without the web UI, so villagers wake, check
workspace/tasks.json, do the work, and post to the noticeboard. State is
saved to workspace/state.json, so the web UI picks up where this left off.

    python3 run_tick.py --minutes 120
    # crontab: */30 * * * * cd /path/to/ai-village && python3 run_tick.py --minutes 60
Don't run this while server.py is running — both would write the same state.
"""
import argparse

from village.engine import Village

ap = argparse.ArgumentParser()
ap.add_argument("--minutes", type=int, default=60, help="sim minutes to advance")
args = ap.parse_args()
v = Village()
v.run_minutes(args.minutes)
for e in reversed(list(v.events)[:40]):
    print(f"[{e['t']}] {e['text']}")
