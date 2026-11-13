#!/usr/bin/env python3
"""AI Village web server. Stdlib only — `python3 server.py` and open http://localhost:8765"""
from __future__ import annotations

import argparse
import json
import mimetypes
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

from village.engine import ROOT, Village

STATIC = {"/": ROOT / "static" / "index.html"}
SERVE_DIRS = {"/static/": ROOT / "static", "/assets/": ROOT / "assets"}
village: Village


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):  # quiet
        pass

    def _json(self, obj, code=200):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _file(self, path: Path):
        if not path.is_file():
            return self._json({"error": "not found"}, 404)
        data = path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", mimetypes.guess_type(path.name)[0] or "application/octet-stream")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        p = urlparse(self.path).path
        if p == "/api/state":
            return self._json(village.snapshot())
        if p == "/api/village":
            return self._json(village.world.data)
        if p in STATIC:
            return self._file(STATIC[p])
        for prefix, base in SERVE_DIRS.items():
            if p.startswith(prefix):
                target = (base / p[len(prefix):]).resolve()
                if base.resolve() in target.parents:
                    return self._file(target)
        self._json({"error": "not found"}, 404)

    def do_POST(self):
        p = urlparse(self.path).path
        try:
            n = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(n) or b"{}")
        except (ValueError, json.JSONDecodeError):
            return self._json({"error": "bad json"}, 400)
        if p == "/api/tasks":
            title = (body.get("title") or "").strip()
            kind = body.get("kind", "general")
            if not title or kind not in ("general", "research", "email", "digest"):
                return self._json({"error": "title required; kind must be general|research|email|digest"}, 400)
            return self._json(village.add_task(title, kind, body.get("detail", ""), body.get("to", "")))
        if p == "/api/control":
            with village.lock:
                a = body.get("action")
                if a == "pause":
                    village.paused = True
                elif a == "resume":
                    village.paused = False
                elif a == "speed":
                    village.speed = max(0.25, min(16.0, float(body.get("value", 1))))
                else:
                    return self._json({"error": "action must be pause|resume|speed"}, 400)
            return self._json({"ok": True, "paused": village.paused, "speed": village.speed})
        self._json({"error": "not found"}, 404)


def main():
    global village
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--tick", type=float, default=0.25, help="real seconds per tick at speed 1")
    args = ap.parse_args()
    village = Village()
    threading.Thread(target=village.run_forever, args=(args.tick,), daemon=True).start()
    srv = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"AI Village running at http://{args.host}:{args.port}  (brain: {village.brain.name})")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        village.save()


if __name__ == "__main__":
    main()
