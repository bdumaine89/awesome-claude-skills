#!/usr/bin/env python3
"""Render map/village.json to map/village_layout.png — a flat, labelled top-down
blueprint with a tile grid. Use it as the reference image when generating art,
so generated buildings land on the same tiles the simulation uses. Needs Pillow."""
import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
m = json.loads((ROOT / "map" / "village.json").read_text())
T = m["tile"]
img = Image.new("RGB", (m["width"] * T, m["height"] * T), "#9cc47a")
d = ImageDraw.Draw(img)
for x in range(0, img.width, T):
    d.line([x, 0, x, img.height], fill="#8fb36f")
for y in range(0, img.height, T):
    d.line([0, y, img.width, y], fill="#8fb36f")
box = lambda r: [r["x"] * T, r["y"] * T, (r["x"] + r["w"]) * T - 1, (r["y"] + r["h"]) * T - 1]
for p in m["paths"]:
    d.rectangle(box(p), fill="#d8c49a")
for w in m.get("water", []):
    d.rectangle(box(w), fill="#6aa6c8")
for x, y in m["trees"]:
    d.ellipse([x * T + 3, y * T + 3, x * T + T - 3, y * T + T - 3], fill="#4e8a3e")
for l in m["locations"]:
    d.rectangle(box(l), fill=l["color"], outline="#2d2a26", width=2)
    dx, dy = l["door"]
    d.rectangle([dx * T + 4, dy * T + 4, dx * T + T - 4, dy * T + T - 4], fill="#3d2b1f")
    d.text((l["x"] * T + 6, l["y"] * T + 5), l["name"], fill="white")
    d.text((l["x"] * T + 6, l["y"] * T + 18), f"{l['function']} ({l['w']}x{l['h']})", fill="#f3ead8")
out = ROOT / "map" / "village_layout.png"
img.save(out)
print(f"wrote {out.relative_to(ROOT)} ({img.width}x{img.height})")
