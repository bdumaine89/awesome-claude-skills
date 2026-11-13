"""The village map: a 40x26 grid of 32px tiles, placed props, and A* pathfinding.

Ground codes (client draws them with LPC autotiles):
  g grass   p dirt path   c cobblestone square   w water
Anything a building or solid prop sits on is marked blocked separately.
"""
from __future__ import annotations

import heapq

W, H, TILE = 40, 26, 32
COST = {"p": 1.0, "c": 1.0, "g": 2.4}

# Buildings: sprite drawn at pixel (px, py); `block` = tile rect (x, y, w, h); `door` = tile to stand on.
LOCATIONS = {
    "library": {
        "name": "The Library", "sprite": "library", "px": 32, "py": 32,
        "block": (1, 1, 12, 6), "door": (4, 7),
        "glow": [(47, 72), (48, 140), (112, 140)],
        "blurb": "Scout Leo researches topics here and writes notes to workspace/notes/.",
    },
    "post_office": {
        "name": "Post Office", "sprite": "post_office", "px": 832, "py": 96,
        "block": (26, 3, 13, 4), "door": (31, 7),
        "glow": [(80, 80), (148, 82), (192, 82)],
        "blurb": "Scribe Maya turns notes into clean summaries in workspace/outbox/.",
    },
    "town_hall": {
        "name": "Town Hall", "sprite": "town_hall", "px": 494, "py": 367,
        "block": (15, 11, 11, 6), "door": (20, 17),
        "glow": [(22, 140), (52, 140), (86, 140), (130, 140), (195, 140), (240, 140), (272, 140), (305, 140)],
        "blurb": "Mayor Ada reads the task board, plans goals and delegates subtasks.",
    },
    "town_square": {
        "name": "Town Square", "zone": True, "rect": (13, 18, 15, 7), "door": (17, 21),
        "blurb": "Idle villagers wander, rest and chat here.",
    },
}

# Props: sprite anchored so its bottom-centre sits on the bottom-centre of `tile`.
# dx/dy nudge in pixels; `block` marks the tile solid; `flat` props never cover villagers.
PROPS: list[dict] = []


def prop(sprite, x, y, block=True, dx=0, dy=0, flat=False):
    PROPS.append({"sprite": sprite, "tile": [x, y], "block": block, "dx": dx, "dy": dy, "flat": flat})


def _rect(grid, x, y, w, h, code):
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            if 0 <= xx < W and 0 <= yy < H:
                grid[yy][xx] = code


def build() -> tuple[list[list[str]], list[list[bool]]]:
    g = [["g"] * W for _ in range(H)]
    # roads
    _rect(g, 1, 8, 38, 2, "p")              # main east-west road
    _rect(g, 4, 7, 1, 1, "p")               # library step
    _rect(g, 31, 7, 1, 1, "p")              # post office step
    _rect(g, 4, 10, 2, 12, "p")             # west lane
    _rect(g, 31, 10, 2, 12, "p")            # east lane
    _rect(g, 4, 20, 9, 2, "p")              # west lane into square
    _rect(g, 28, 20, 5, 2, "p")             # east lane into square
    _rect(g, 20, 17, 1, 1, "p")             # town hall step
    sq = LOCATIONS["town_square"]["rect"]
    _rect(g, *sq, "c")
    _rect(g, 34, 16, 5, 5, "w")             # pond
    _rect(g, 35, 21, 3, 1, "w")

    PROPS.clear()
    # square furniture
    prop("fountain", 20, 21)
    for (x, y) in [(13, 18), (27, 18), (13, 24), (27, 24)]:
        prop("lamp", x, y)
    prop("bench", 15, 22, dx=16)
    prop("bench", 24, 22, dx=16)
    prop("statue", 17, 18)
    prop("statue", 23, 18)
    # lamps along the main road
    for x in (8, 15, 26, 34):
        prop("lamp", x, 7)
    # garden west of town hall
    for x in range(7, 13):
        prop("fence_l" if x == 7 else "fence_r" if x == 12 else "fence_m", x, 16)
    for i, (x, y) in enumerate([(7, 12), (9, 13), (11, 12), (8, 14), (10, 15), (12, 14), (7, 15), (11, 11), (9, 11)]):
        prop(f"flower{i % 17}", x, y, block=False, flat=True)
    prop("bush", 9, 18, dx=16)
    # yards
    prop("barrels", 37, 7)
    prop("barrel", 27, 7)
    prop("plant_pot", 3, 7)
    prop("plant_pot", 5, 7)
    prop("urn", 19, 17)
    prop("urn", 21, 17)
    # north meadow between the library and post office
    prop("oak", 15, 4, dx=8)
    prop("autumn", 18, 2)
    prop("pine", 23, 3)
    prop("tree_small", 20, 6)
    prop("oak", 25, 6)
    prop("rocks", 17, 6, block=False)
    for i, (x, y) in enumerate([(14, 6), (21, 2), (16, 1), (24, 5), (19, 4), (22, 6)]):
        prop(f"flower{(i * 5) % 17}", x, y, block=False, flat=True)
    # border trees
    for x in range(0, W, 3):
        if 10 <= x <= 30:
            continue  # keep the view of the square clear; low hedges instead
        prop("pine" if x % 2 else "oak", x, 25, dx=(x % 5) - 2)
    for x in range(12, 30, 3):
        prop("bush", x, 25, dx=16)
    for y in range(3, 24, 3):
        prop("pine", 0, y)
        prop("pine" if y % 2 else "oak", 39, y)
    for (x, y, s) in [(2, 12, "oak"), (2, 17, "tree_small"), (8, 23, "autumn"), (31, 23, "oak"), (35, 13, "tree_small"),
                      (12, 10, "tree_small"), (28, 14, "pine"), (13, 14, "oak"), (36, 23, "pine"), (25, 11, "bush")]:
        if g[y][x] == "g":
            prop(s, x, y)
    prop("stump", 33, 12, block=False)
    for i, (x, y) in enumerate([(7, 22), (11, 23), (29, 23), (33, 14), (37, 12), (3, 22), (15, 10), (26, 10)]):
        if g[y][x] == "g":
            prop(f"flower{(i * 3) % 17}", x, y, block=False, flat=True)

    blocked = [[g[y][x] == "w" for x in range(W)] for y in range(H)]
    for loc in LOCATIONS.values():
        if "block" in loc:
            bx, by, bw, bh = loc["block"]
            for yy in range(by, by + bh):
                for xx in range(bx, bx + bw):
                    blocked[yy][xx] = True
    for p in PROPS:
        if p["block"]:
            x, y = p["tile"]
            blocked[y][x] = True
            if p["sprite"] in ("bench", "fountain", "barrels", "bush"):
                blocked[y][x - 1] = True
            if p["sprite"] == "fountain":
                blocked[y - 1][x] = blocked[y - 1][x - 1] = True
    for loc in LOCATIONS.values():
        dx, dy = loc["door"]
        blocked[dy][dx] = False
    return g, blocked


GRID, BLOCKED = build()
_sx, _sy, _sw, _sh = LOCATIONS["town_square"]["rect"]
SQUARE_TILES = [(x, y) for y in range(_sy, _sy + _sh) for x in range(_sx, _sx + _sw) if not BLOCKED[y][x]]


def walkable(x: int, y: int) -> bool:
    return 0 <= x < W and 0 <= y < H and not BLOCKED[y][x]


def door(loc_id: str) -> tuple[int, int]:
    return LOCATIONS[loc_id]["door"]


def astar(start: tuple[int, int], goal: tuple[int, int]) -> list[tuple[int, int]]:
    """A* that strongly prefers roads. Returns tiles after `start`, ending at `goal`."""
    if start == goal or not walkable(*goal):
        return []
    def h(p):
        return abs(p[0] - goal[0]) + abs(p[1] - goal[1])
    openq = [(h(start), 0.0, start)]
    came: dict = {}
    best = {start: 0.0}
    while openq:
        _, cost, cur = heapq.heappop(openq)
        if cur == goal:
            break
        if cost > best.get(cur, 1e9):
            continue
        cx, cy = cur
        for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
            if not walkable(nx, ny):
                continue
            nc = cost + COST.get(GRID[ny][nx], 2.4)
            if nc < best.get((nx, ny), 1e9):
                best[(nx, ny)] = nc
                came[(nx, ny)] = cur
                heapq.heappush(openq, (nc + h((nx, ny)), nc, (nx, ny)))
    if goal not in came:
        return []
    path = [goal]
    while came[path[-1]] != start:
        path.append(came[path[-1]])
    path.reverse()
    return path


def map_payload() -> dict:
    return {
        "w": W, "h": H, "tile": TILE,
        "grid": ["".join(row) for row in GRID],
        "blocked": ["".join("#" if b else "." for b in row) for row in BLOCKED],
        "locations": {k: {kk: (list(vv) if isinstance(vv, tuple) else vv) for kk, vv in v.items()}
                      for k, v in LOCATIONS.items()},
        "props": PROPS,
    }
