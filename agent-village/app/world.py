"""The village map: a tile grid built in code, plus A* pathfinding.

Tile codes (sent to the client, which draws them):
  g grass   p dirt path   c cobblestone   w water   B building   f fountain
  t tree    x fence       h hedge         l lamp post   n bench   o flowers
Blocking tiles: w B f t x h l n
"""
from __future__ import annotations

import heapq
import random

W, H = 48, 30
BLOCKING = set("wBftxhln")
COST = {"p": 1.0, "c": 1.0, "g": 2.6, "o": 2.6}

# Buildings / zones. `door` is the tile a villager stands on to "be at" the place.
LOCATIONS = {
    "library": {
        "name": "The Library", "x": 3, "y": 3, "w": 10, "h": 7, "door": (8, 10),
        "wall": "#6d8fb8", "roof": "#2f4a6e", "trim": "#e8dcc0", "icon": "book",
        "blurb": "Scout Leo researches topics here and writes notes to workspace/notes/.",
    },
    "post_office": {
        "name": "Post Office", "x": 35, "y": 3, "w": 10, "h": 7, "door": (39, 10),
        "wall": "#d9a441", "roof": "#8c4f2b", "trim": "#fff2d6", "icon": "letter",
        "blurb": "Scribe Maya turns notes into clean summaries in workspace/outbox/.",
    },
    "town_hall": {
        "name": "Town Hall", "x": 18, "y": 12, "w": 12, "h": 7, "door": (23, 19),
        "wall": "#c7765b", "roof": "#6b2f2a", "trim": "#f3e3c8", "icon": "flag",
        "blurb": "Mayor Ada reads the task board, plans goals and delegates subtasks.",
    },
    "town_square": {
        "name": "Town Square", "x": 15, "y": 21, "w": 18, "h": 8, "door": (23, 22),
        "zone": True, "icon": "fountain",
        "blurb": "Idle villagers wander, rest and chat here.",
    },
}


def _rect(grid, x, y, w, h, code):
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            if 0 <= xx < W and 0 <= yy < H:
                grid[yy][xx] = code


def build_grid() -> list[list[str]]:
    rng = random.Random(7)
    g = [["g"] * W for _ in range(H)]

    # roads
    _rect(g, 2, 10, 44, 2, "p")            # main east-west road
    _rect(g, 8, 12, 2, 13, "p")            # west lane down to the square
    _rect(g, 38, 12, 2, 13, "p")           # east lane down to the square
    _rect(g, 8, 24, 8, 2, "p")             # west lane into square
    _rect(g, 32, 24, 8, 2, "p")            # east lane into square
    _rect(g, 23, 19, 2, 2, "p")            # town hall steps
    # square (cobblestone) and fountain
    sq = LOCATIONS["town_square"]
    _rect(g, sq["x"], sq["y"], sq["w"], sq["h"], "c")
    _rect(g, 22, 24, 4, 3, "f")
    # buildings
    for loc in LOCATIONS.values():
        if not loc.get("zone"):
            _rect(g, loc["x"], loc["y"], loc["w"], loc["h"], "B")
    # pond (south-east) and garden hedges
    _rect(g, 41, 21, 5, 4, "w")
    _rect(g, 42, 25, 3, 1, "w")
    for x in range(2, 8):                  # little fenced garden by the library lane
        g[16][x] = "x"
    for y in range(13, 16):
        g[y][2] = "x"
    # flowers and benches
    for (x, y) in [(3, 13), (4, 14), (5, 13), (6, 14), (4, 15), (11, 13), (12, 14), (14, 18), (34, 18), (35, 17),
                   (36, 13), (44, 13), (43, 14), (28, 7), (19, 7), (20, 8)]:
        g[y][x] = "o"
    for (x, y) in [(17, 23), (30, 23), (17, 27), (30, 27)]:
        g[y][x] = "n"
    # lamp posts along the roads and square
    for (x, y) in [(13, 9), (16, 9), (31, 9), (34, 9), (15, 21), (32, 21), (15, 28), (32, 28), (10, 18), (37, 18)]:
        g[y][x] = "l"
    # trees: border ring plus clusters, never on roads/buildings/doors
    doors = {loc["door"] for loc in LOCATIONS.values()}
    candidates = [(x, 0) for x in range(W)] + [(x, H - 1) for x in range(W)] + \
                 [(0, y) for y in range(H)] + [(W - 1, y) for y in range(H)]
    candidates += [(1, 1), (14, 2), (16, 4), (32, 2), (30, 5), (2, 15), (3, 19), (5, 22), (12, 20),
                   (13, 27), (2, 26), (35, 21), (35, 27), (45, 18), (46, 9), (14, 13), (33, 14),
                   (27, 2), (21, 3), (24, 5), (11, 27), (45, 27), (36, 26)]
    for (x, y) in candidates:
        if g[y][x] in "go" and (x, y) not in doors and (rng.random() < 0.8 or y in (0, H - 1)):
            g[y][x] = "t"
    return g


GRID = build_grid()
SQUARE_TILES = [
    (x, y)
    for y in range(LOCATIONS["town_square"]["y"], LOCATIONS["town_square"]["y"] + LOCATIONS["town_square"]["h"])
    for x in range(LOCATIONS["town_square"]["x"], LOCATIONS["town_square"]["x"] + LOCATIONS["town_square"]["w"])
    if GRID[y][x] == "c"
]


def walkable(x: int, y: int) -> bool:
    return 0 <= x < W and 0 <= y < H and GRID[y][x] not in BLOCKING


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
            nc = cost + COST.get(GRID[ny][nx], 2.6)
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
        "w": W, "h": H, "tile": 16,
        "grid": ["".join(row) for row in GRID],
        "locations": {k: {**v, "door": list(v["door"])} for k, v in LOCATIONS.items()},
    }
