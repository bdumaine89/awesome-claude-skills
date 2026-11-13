#!/usr/bin/env python3
"""Build the village's art from free, openly licensed LPC sources.

Sources (clone them first; both are public, no account needed):
  git clone --depth 1 --filter=blob:none --sparse \
      https://github.com/liberatedpixelcup/Universal-LPC-Spritesheet-Character-Generator lpc
  git clone --depth 1 https://github.com/tales/sourceoftales sot

Then:  python tools/build_assets.py --lpc path/to/lpc --sot path/to/sot

Outputs (all committed, so the app needs nothing at runtime):
  static/assets/sprites.png + sprites.json   props, trees, buildings (packed atlas)
  static/assets/terrain/{grass,dirt,water}.png   LPC autotile sheets
  static/assets/villagers/<id>.png           576x256 walk sheets (9 frames x 4 dirs, 64px)
  static/assets/CREDITS.md                   per-file authors + licenses (required by CC-BY-SA)
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "static" / "assets"

# --------------------------------------------------------------- villagers
# (sheet_definition path, layer key, body type, color spec)
#   color spec: ("recolor", material, color) | ("variant", name) | None (use as-is)
VILLAGERS = {
    "ada": {"body": "female", "skin": "light", "layers": [
        ("torso/cape/cape_solid.json", ("recolor", "cloth", "maroon")),
        ("body/body.json", ("recolor", "body", "light")),
        ("head/heads/human/heads_human_female.json", ("recolor", "body", "light")),
        ("feet/shoes/feet_shoes_basic.json", ("recolor", "cloth", "black")),
        ("legs/skirts/legs_skirts_plain.json", ("recolor", "cloth", "navy")),
        ("torso/shirts/torso_clothes_blouse_longsleeve.json", ("variant", "white")),
        ("hair/short/hair_bob.json", ("recolor", "hair", "chestnut")),
        ("headwear/hats/formal/hat_formal_tophat.json", ("variant", "black")),
    ]},
    "leo": {"body": "male", "skin": "amber", "layers": [
        ("body/body.json", ("recolor", "body", "amber")),
        ("head/heads/human/heads_human_male.json", ("recolor", "body", "amber")),
        ("feet/shoes/feet_shoes_basic.json", ("recolor", "cloth", "brown")),
        ("legs/pants/legs_pants.json", ("recolor", "cloth", "tan")),
        ("torso/shirts/longsleeve/torso_clothes_longsleeve.json", ("recolor", "cloth", "sky")),
        ("torso/vest/torso_clothes_vest.json", ("variant", "forest")),
        ("hair/short/hair_messy2.json", ("recolor", "hair", "sandy")),
        ("torso/backpack/backpack.json", ("variant", "leather")),
        ("headwear/hats/caps/hat_cap_leather.json", ("variant", "base")),
    ]},
    "maya": {"body": "female", "skin": "bronze", "layers": [
        ("body/body.json", ("recolor", "body", "bronze")),
        ("head/heads/human/heads_human_female.json", ("recolor", "body", "bronze")),
        ("feet/shoes/feet_shoes_basic.json", ("recolor", "cloth", "brown")),
        ("legs/skirts/legs_skirts_plain.json", ("recolor", "cloth", "maroon")),
        ("torso/shirts/torso_clothes_blouse_longsleeve.json", ("variant", "teal")),
        ("torso/aprons/torso_aprons_apron.json", ("variant", "white")),
        ("hair/braids/hair_ponytail2.json", ("recolor", "hair", "raven")),
        ("headwear/accessories/glasses/facial_glasses_round.json", ("variant", "black")),
    ]},
}
PALETTE_BASE = {"cloth": "white", "hair": "orange", "body": "light"}


def find_def(lpc: Path, rel: str) -> Path:
    p = lpc / "sheet_definitions" / rel
    if p.exists():
        return p
    hits = list((lpc / "sheet_definitions").rglob(Path(rel).name))
    if not hits:
        raise FileNotFoundError(rel)
    return hits[0]


def palette(lpc: Path, material: str) -> dict:
    return json.loads((lpc / "palette_definitions" / material / f"{material}_ulpc.json").read_text())


def recolor(im: Image.Image, src: list[str], dst: list[str]) -> Image.Image:
    to_rgb = lambda h: tuple(int(h.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4))
    pairs = [(to_rgb(a), to_rgb(b)) for a, b in zip(src, dst)]
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if not a:
                continue
            for (sr, sg, sb), (dr, dg, db) in pairs:
                if abs(r - sr) <= 1 and abs(g - sg) <= 1 and abs(b - sb) <= 1:
                    px[x, y] = (dr, dg, db, a)
                    break
    return im


def build_villager(lpc: Path, vid: str, spec: dict, credits: list) -> None:
    pieces = []
    for rel, color in spec["layers"]:
        d = json.loads(find_def(lpc, rel).read_text())
        for key in ("layer_1", "layer_2"):
            layer = d.get(key)
            if not layer:
                continue
            path = layer.get(spec["body"])
            if not path:
                raise SystemExit(f"{rel} has no {spec['body']} layer")
            base = lpc / "spritesheets" / path
            if color[0] == "variant":
                f = base / "walk" / f"{color[1]}.png"
            else:
                f = base / "walk.png"
            if not f.exists():
                raise SystemExit(f"missing {f} (add it to the sparse checkout)")
            im = Image.open(f).convert("RGBA")
            if color[0] == "recolor":
                _, material, target = color
                pal = palette(lpc, material)
                im = recolor(im, pal[PALETTE_BASE[material]], pal[target])
            pieces.append((layer["zPos"], im))
        for c in d.get("credits", []):
            credits.append({"what": f"{vid}: {d.get('name', rel)}", **c})
    pieces.sort(key=lambda p: p[0])
    sheet = Image.new("RGBA", (576, 256))
    for _, im in pieces:
        sheet.alpha_composite(im.crop((0, 0, 576, 256)))
    (OUT / "villagers").mkdir(parents=True, exist_ok=True)
    sheet.save(OUT / "villagers" / f"{vid}.png")


# ----------------------------------------------------------------- sprites
# name: (source file in sot/tiles, x, y, w, h)
SPRITES = {
    "town_hall": ("building11.png", 0, 0, 325, 177),
    "library": ("housey.png", 0, 0, 384, 192),
    "post_office": ("town_buildings.png", 0, 0, 414, 128),
    "fountain": ("magecity.png", 192, 64, 64, 64),
    "bench": ("magecity.png", 0, 496, 64, 48),
    "statue": ("magecity.png", 64, 384, 32, 96),
    "lamp": ("magecity.png", 0, 384, 32, 96),
    "table": ("magecity.png", 160, 0, 64, 64),
    "plant_pot": ("magecity.png", 96, 64, 32, 64),
    "urn": ("magecity.png", 0, 64, 32, 64),
    "barrel": ("barrel.png", 0, 0, 32, 64),
    "barrels": ("barrel.png", 32, 0, 96, 64),
    "pine": ("outside.png", 448, 0, 84, 160),
    "oak": ("outside.png", 544, 192, 96, 128),
    "tree_small": ("outside.png", 484, 192, 62, 104),
    "autumn": ("outside.png", 544, 320, 96, 128),
    "stump": ("outside.png", 608, 512, 32, 32),
    "bush": ("flowers.png", 208, 40, 96, 48),
    "rocks": ("flowers.png", 288, 0, 32, 64),
    "fence_l": ("fence.png", 0, 0, 32, 32),
    "fence_m": ("fence.png", 32, 0, 32, 32),
    "fence_r": ("fence.png", 64, 0, 32, 32),
    "cobble": ("magecity.png", 0, 288, 96, 96),
}
for i, (cx, cy) in enumerate([(0, 0), (0, 1), (1, 1), (0, 2), (1, 2), (2, 2), (3, 2), (0, 3), (1, 3), (2, 3), (3, 3), (0, 4), (0, 5), (1, 5), (4, 0), (4, 1), (5, 1)]):
    SPRITES[f"flower{i}"] = ("flowers.png", cx * 32, cy * 32, 32, 32)

TERRAIN = {"grass": "grass.png", "dirt": "dirt.png", "water": "water.png"}

# Plaques painted over the source buildings' tavern/shop signs.
PLAQUES = {
    "library": [(99, 68, 26, 22, "book")],
    "post_office": [(291, 64, 26, 24, "letter"), (324, 64, 26, 24, "parcel"), (356, 64, 26, 24, "quill")],
}
ICONS = {
    "book": ["..######..", ".#pppp#pp#", "#ppp#ppp#.", "#pppp#ppp#", "#ppp#ppp#.", ".########."],
    "letter": ["##########", "#w......w#", "#.ww..ww.#", "#...ww...#", "#........#", "##########"],
    "parcel": ["...####...", "..#tttt#..", "##########", "#tttrrttt#", "#tttrrttt#", "##########"],
    "quill": [".......##.", "......#ww#", ".....#ww#.", "....#ww#..", "..##w#....", ".#........"],
}


def plaque(img: Image.Image, x, y, w, h, icon):
    d = ImageDraw.Draw(img)
    d.rectangle([x, y, x + w - 1, y + h - 1], fill=(74, 52, 35, 255))
    d.rectangle([x + 1, y + 1, x + w - 2, y + h - 2], fill=(236, 220, 186, 255))
    d.rectangle([x + 1, y + h - 2, x + w - 2, y + h - 2], fill=(196, 172, 130, 255))
    rows = ICONS[icon]
    ox, oy = x + (w - len(rows[0]) * 2) // 2, y + (h - len(rows) * 2) // 2
    col = {"#": (59, 44, 32), "p": (255, 250, 236), "w": (255, 250, 236), "t": (190, 140, 90), "r": (200, 70, 70)}
    for j, row in enumerate(rows):
        for i, ch in enumerate(row):
            if ch != ".":
                d.rectangle([ox + i * 2, oy + j * 2, ox + i * 2 + 1, oy + j * 2 + 1], fill=col[ch] + (255,))


def pack(images: dict[str, Image.Image]) -> tuple[Image.Image, dict]:
    """Simple shelf packer, tallest first."""
    order = sorted(images, key=lambda k: -images[k].height)
    W, x, y, shelf = 1024, 0, 0, 0
    pos = {}
    for k in order:
        im = images[k]
        if x + im.width > W:
            x, y, shelf = 0, y + shelf + 2, 0
        pos[k] = (x, y, im.width, im.height)
        x += im.width + 2
        shelf = max(shelf, im.height)
    atlas = Image.new("RGBA", (W, y + shelf))
    for k, (x, y, w, h) in pos.items():
        atlas.alpha_composite(images[k], (x, y))
    return atlas, {k: {"x": x, "y": y, "w": w, "h": h} for k, (x, y, w, h) in pos.items()}


def sot_authors(sot: Path) -> dict[str, str]:
    out = {}
    for line in (sot / "AUTHORS.txt").read_text(errors="ignore").splitlines():
        m = re.match(r"^(.{35})(.{28})(tiles/\S+)$", line)
        if m:
            out.setdefault(m.group(3)[6:], []).append((m.group(1).strip(), m.group(2).strip()))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lpc", type=Path, required=True)
    ap.add_argument("--sot", type=Path, required=True)
    a = ap.parse_args()
    tiles = a.sot / "tiles"
    OUT.mkdir(parents=True, exist_ok=True)

    lpc_credits: list = []
    for vid, spec in VILLAGERS.items():
        build_villager(a.lpc, vid, spec, lpc_credits)
        print("villager", vid)

    imgs = {}
    for name, (src, x, y, w, h) in SPRITES.items():
        im = Image.open(tiles / src).convert("RGBA").crop((x, y, x + w, y + h))
        for p in PLAQUES.get(name, []):
            plaque(im, *p)
        imgs[name] = im
    atlas, index = pack(imgs)
    atlas.save(OUT / "sprites.png")
    (OUT / "sprites.json").write_text(json.dumps(index, indent=1))
    (OUT / "terrain").mkdir(exist_ok=True)
    for k, src in TERRAIN.items():
        shutil.copy(tiles / src, OUT / "terrain" / f"{k}.png")
    print("atlas", atlas.size, len(index), "sprites")

    # credits
    authors = sot_authors(a.sot)
    used = sorted({s[0] for s in SPRITES.values()} | set(TERRAIN.values()))
    lines = ["# Art credits", "",
             "All art in this folder is free, openly licensed pixel art from the Liberated Pixel Cup (LPC) family,",
             "rebuilt by `tools/build_assets.py`. It is **not** covered by the app's code license.",
             "Redistributing it requires keeping this file. Modified files (recolours, crops, painted sign plaques)",
             "are shared under the same terms (CC-BY-SA 3.0 / GPL 3.0 where applicable).", "",
             "## Scenery, buildings and props",
             "Source: [Source of Tales](https://github.com/tales/sourceoftales) `tiles/` "
             "(art dual-licensed CC-BY-SA 3.0 and GPL 3.0; see its AUTHORS.txt).", "",
             "| File | Author(s) | License |", "|---|---|---|"]
    for f in used:
        for who, lic in authors.get(f, [("see Source of Tales AUTHORS.txt", "CC-BY-SA 3.0 / GPL 3.0")]):
            lines.append(f"| `{f}` | {who} | {lic} |")
    lines += ["", "## Villagers",
              "Source: [Universal LPC Spritesheet Character Generator]"
              "(https://github.com/liberatedpixelcup/Universal-LPC-Spritesheet-Character-Generator). "
              "Layers composited and recoloured with its palettes.", ""]
    seen = set()
    for c in lpc_credits:
        key = (c["what"], c["file"])
        if key in seen:
            continue
        seen.add(key)
        lines.append(f"- **{c['what']}** (`{c['file']}`): {', '.join(c.get('authors', []))}. "
                     f"Licenses: {', '.join(c.get('licenses', []))}."
                     + (f" {c['notes']}" if c.get("notes") else ""))
        for u in c.get("urls", [])[:3]:
            lines.append(f"  - {u}")
    (OUT / "CREDITS.md").write_text("\n".join(lines) + "\n")
    print("credits written")


if __name__ == "__main__":
    main()
