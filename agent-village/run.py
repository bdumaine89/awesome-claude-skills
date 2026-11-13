#!/usr/bin/env python3
"""Launch the AI Agent Village:  python run.py  ->  http://127.0.0.1:8000"""
import argparse

import uvicorn

ap = argparse.ArgumentParser()
ap.add_argument("--host", default="127.0.0.1")
ap.add_argument("--port", type=int, default=8000)
ap.add_argument("--reload", action="store_true", help="auto-reload on code changes (dev)")
a = ap.parse_args()
print(f"\n  🏡  AI Agent Village → http://{a.host}:{a.port}\n")
uvicorn.run("app.main:app", host=a.host, port=a.port, reload=a.reload, log_level="warning")
