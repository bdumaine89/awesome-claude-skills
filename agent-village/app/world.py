"""The village map: a hex grid (pointy-top, odd-r offset coordinates), A* pathfinding,
and the layout of buildings, roads and scenery the 3D client renders.

Coordinates
  tile (col, row)   -> one hex. Odd rows are shifted half a hex to the right.
  "cartesian" (x, y) -> centre of a hex in units of hex width: x = col + 0.5*(row & 1),
                        y = row * sqrt(3)/2. The simulation moves villagers in this space.
"""
from __future__ import annotations

import heapq
import math
import random

COLS, ROWS = 17, 13
SQ3_2 = math.sqrt(3) / 2

# Neighbour directions, indexed like the client's road tiles: 0=E, 1=SE, 2=SW, 3=W, 4=NW, 5=NE
_DIRS = {
    0: [(1, 0), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1)],   # even rows
    1: [(1, 0), (1, 1), (0, 1), (-1, 0), (0, -1), (1, -1)],     # odd rows
}


def neighbour(t: tuple[int, int], d: int) -> tuple[int, int]:
    dc, dr = _DIRS[t[1] & 1][d]
    return t[0] + dc, t[1] + dr


def neighbours(t):
    return [neighbour(t, d) for d in range(6)]


def center(t: tuple[int, int]) -> tuple[float, float]:
    return t[0] + 0.5 * (t[1] & 1), t[1] * SQ3_2


def nearest(x: float, y: float) -> tuple[int, int]:
    r = round(y / SQ3_2)
    best = None
    for rr in (r - 1, r, r + 1):
        for cc in range(math.floor(x) - 1, math.floor(x) + 2):
            cx, cy = center((cc, rr))
            d = (cx - x) ** 2 + (cy - y) ** 2
            if best is None or d < best[0]:
                best = (d, (cc, rr))
    return best[1]


def inside(t) -> bool:
    return 0 <= t[0] < COLS and 0 <= t[1] < ROWS


def _cube(t):
    q = t[0] - (t[1] - (t[1] & 1)) // 2
    return q, t[1], -q - t[1]


def _from_cube(q, r):
    return q + (r - (r & 1)) // 2, r


def hex_line(a, b) -> list[tuple[int, int]]:
    (aq, ar, as_), (bq, br, bs) = _cube(a), _cube(b)
    n = max(abs(aq - bq), abs(ar - br), abs(as_ - bs))
    out = []
    for i in range(n + 1):
        t = i / max(n, 1)
        q, r, s = aq + (bq - aq) * t + 1e-6, ar + (br - ar) * t + 1e-6, as_ + (bs - as_) * t - 2e-6
        rq, rr, rs = round(q), round(r), round(s)
        dq, dr, ds = abs(rq - q), abs(rr - r), abs(rs - s)
        if dq > dr and dq > ds:
            rq = -rr - rs
        elif dr > ds:
            rr = -rq - rs
        out.append(_from_cube(rq, rr))
    return out


def facing(frm, to) -> int:
    """Direction index from hex `frm` to adjacent hex `to`."""
    for d in range(6):
        if neighbour(frm, d) == to:
            return d
    raise ValueError(f"{to} is not next to {frm}")


# ------------------------------------------------------------------- layout
# Functional places. `tile` is the building's hex, `door` the road hex in front of it.
LOCATIONS = {
    "library": {"name": "The Library", "model": "building_tower_A_blue", "tile": (3, 2), "door": (3, 3),
                 "blurb": "Scout Leo researches topics here and writes notes to workspace/notes/."},
    "post_office": {"name": "Post Office", "model": "building_market_red", "tile": (13, 2), "door": (12, 3),
                    "blurb": "Scribe Maya turns notes into clean summaries in workspace/outbox/."},
    "town_hall": {"name": "Town Hall", "model": "building_church_blue", "tile": (8, 5), "door": (8, 6),
                  "blurb": "Mayor Ada reads the task board, plans goals and delegates subtasks."},
    "town_square": {"name": "Town Square", "model": "building_well_blue", "tile": (8, 9), "door": (7, 9),
                    "zone": True, "blurb": "Idle villagers wander, rest and chat here."},
}

# Decorative buildings: (model, tile, door-or-None). Each faces its door (or the nearest road).
DECOR_BUILDINGS = [
    ("building_home_A_red", (5, 6), (5, 5)),
    ("building_home_B_yellow", (11, 6), (10, 5)),
    ("building_tavern_red", (11, 10), (10, 10)),
    ("building_blacksmith_yellow", (4, 9), (5, 9)),
    ("building_home_A_green", (6, 11), (7, 11)),
    ("building_home_B_blue", (10, 12), (9, 11)),
    ("building_windmill_yellow", (15, 6), None),
    ("building_watermill_green", (13, 8), None),
    ("building_lumbermill_blue", (1, 7), None),
    ("building_grain", (15, 7), None),
    ("building_grain", (14, 5), None),
    ("building_stage_A", (6, 3), None),
]
WATER = [(13, 10), (14, 10), (14, 11), (13, 11), (15, 10), (14, 9), (15, 11), (12, 11)]

ROADS: set[tuple[int, int]] = set()
BUILDINGS: list[dict] = []
SCENERY: list[dict] = []
BLOCKED: set[tuple[int, int]] = set()


def _road(a, b):
    for t in hex_line(a, b):
        ROADS.add(t)


def build():
    ROADS.clear(); BUILDINGS.clear(); SCENERY.clear(); BLOCKED.clear()
    sq = LOCATIONS["town_square"]["tile"]
    ring = neighbours(sq)
    ROADS.update(ring)
    # the main network: every door joins the square, and the library joins the post office
    _road(LOCATIONS["library"]["door"], LOCATIONS["post_office"]["door"])
    _road(LOCATIONS["library"]["door"], (6, 8))
    _road(LOCATIONS["post_office"]["door"], (10, 8))
    _road(LOCATIONS["town_hall"]["door"], neighbour(sq, 4))
    for _, _, door in DECOR_BUILDINGS:
        if door:
            ROADS.add(door)
    _road((5, 5), (4, 4))
    _road((10, 5), (10, 8))
    _road((5, 9), (6, 8))
    _road((7, 11), neighbour(sq, 2))
    _road((9, 11), neighbour(sq, 1))
    _road((10, 10), neighbour(sq, 0))

    for lid, loc in LOCATIONS.items():
        BUILDINGS.append({"id": lid, "model": loc["model"], "tile": list(loc["tile"]),
                          "face": facing(loc["tile"], loc["door"]) if not loc.get("zone") else 1})
        BLOCKED.add(loc["tile"])
    for model, tile, door in DECOR_BUILDINGS:
        face = facing(tile, door) if door else next((d for d in range(6) if neighbour(tile, d) in ROADS), 1)
        BUILDINGS.append({"id": None, "model": model, "tile": list(tile), "face": face})
        BLOCKED.add(tile)
    for t in WATER:
        BLOCKED.add(t)

    # scenery: forests and hills around the edge, trees and rocks sprinkled in the meadows
    rng = random.Random(11)
    taken = set(ROADS) | BLOCKED
    big = ["mountain_A_grass_trees", "mountain_B_grass", "mountain_C_grass_trees", "hills_A_trees", "hills_B_trees"]
    for c in range(COLS):
        for r in range(ROWS):
            t = (c, r)
            if t in taken:
                continue
            edge = c in (0, COLS - 1) or r in (0, ROWS - 1)
            corner = (c < 2 or c > COLS - 3) and (r < 2 or r > ROWS - 3)
            roll = rng.random()
            if corner:
                SCENERY.append({"model": rng.choice(big), "tile": [c, r], "rot": rng.randrange(6)})
                BLOCKED.add(t)
            elif edge:
                SCENERY.append({"model": rng.choice(["trees_A_large", "trees_B_large", "trees_A_medium", "hills_C"]),
                                "tile": [c, r], "rot": rng.randrange(6)})
                BLOCKED.add(t)
            elif roll < 0.3:
                SCENERY.append({"model": rng.choice(["trees_A_small", "trees_B_small", "tree_single_A", "tree_single_B", "trees_A_medium"]),
                                "tile": [c, r], "rot": rng.randrange(6)})
                BLOCKED.add(t)
            elif roll < 0.38:
                SCENERY.append({"model": rng.choice(["rock_single_A", "rock_single_B", "rock_single_C", "rock_single_D"]),
                                "tile": [c, r], "rot": rng.randrange(6), "small": True})
    for t in WATER:
        if rng.random() < 0.6:
            SCENERY.append({"model": rng.choice(["waterlily_A", "waterlily_B", "waterplant_A", "waterplant_B"]),
                            "tile": list(t), "rot": rng.randrange(6), "water": True})


build()
SQUARE_TILES = [t for t in neighbours(LOCATIONS["town_square"]["tile"]) if t not in BLOCKED]


def walkable(t) -> bool:
    return inside(t) and t not in BLOCKED


def door(loc_id: str) -> tuple[int, int]:
    return LOCATIONS[loc_id]["door"]


def astar(start, goal) -> list[tuple[int, int]]:
    """A* over hexes; roads cost 1, grass 2.5. Returns tiles after `start`, ending at `goal`."""
    start, goal = tuple(start), tuple(goal)
    if start == goal or not walkable(goal):
        return []
    gx, gy = center(goal)
    def h(t):
        x, y = center(t)
        return math.hypot(x - gx, y - gy)
    openq = [(h(start), 0.0, start)]
    came: dict = {}
    best = {start: 0.0}
    while openq:
        _, cost, cur = heapq.heappop(openq)
        if cur == goal:
            break
        if cost > best.get(cur, 1e9):
            continue
        for n in neighbours(cur):
            if not walkable(n):
                continue
            nc = cost + (1.0 if n in ROADS else 2.5)
            if nc < best.get(n, 1e9):
                best[n] = nc
                came[n] = cur
                heapq.heappush(openq, (nc + h(n), nc, n))
    if goal not in came:
        return []
    path = [goal]
    while came[path[-1]] != start:
        path.append(came[path[-1]])
    path.reverse()
    return path


def map_payload() -> dict:
    roads = []
    for t in sorted(ROADS):
        edges = [d for d in range(6) if neighbour(t, d) in ROADS]
        # roads run up to the doors of the buildings they serve
        for b in BUILDINGS:
            if tuple(b["tile"]) != LOCATIONS["town_square"]["tile"] and neighbour(tuple(b["tile"]), b["face"]) == t:
                edges.append(facing(t, tuple(b["tile"])))
        if t in neighbours(LOCATIONS["town_square"]["tile"]):
            edges.append(facing(t, LOCATIONS["town_square"]["tile"]))
        roads.append({"tile": list(t), "edges": sorted(set(edges))})
    return {
        "cols": COLS, "rows": ROWS,
        "roads": roads, "water": [list(t) for t in WATER],
        "buildings": BUILDINGS, "scenery": SCENERY,
        "locations": {k: {**v, "tile": list(v["tile"]), "door": list(v["door"])} for k, v in LOCATIONS.items()},
    }
