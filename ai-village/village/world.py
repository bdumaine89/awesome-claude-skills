"""Map loading and pathfinding. The JSON layout is the single source of truth."""
from __future__ import annotations

import heapq
import json
from pathlib import Path

PATH_COST = 1
GRASS_COST = 3


class World:
    def __init__(self, map_path: Path):
        self.data = json.loads(map_path.read_text())
        self.w = self.data["width"]
        self.h = self.data["height"]
        self.locations = {loc["id"]: loc for loc in self.data["locations"]}
        self.task_routes = self.data["task_routes"]
        self._build_grid()

    def _build_grid(self) -> None:
        self.blocked = [[False] * self.w for _ in range(self.h)]
        self.cost = [[GRASS_COST] * self.w for _ in range(self.h)]
        for p in self.data["paths"]:
            for y in range(p["y"], p["y"] + p["h"]):
                for x in range(p["x"], p["x"] + p["w"]):
                    if self.in_bounds(x, y):
                        self.cost[y][x] = PATH_COST
        for r in self.data.get("water", []):
            self._block(r)
        for loc in self.locations.values():
            if loc["kind"] != "zone":
                self._block(loc)
        for tx, ty in self.data.get("trees", []):
            if self.in_bounds(tx, ty):
                self.blocked[ty][tx] = True
        for loc in self.locations.values():  # doors are always reachable
            dx, dy = loc["door"]
            self.blocked[dy][dx] = False

    def _block(self, r: dict) -> None:
        for y in range(r["y"], r["y"] + r["h"]):
            for x in range(r["x"], r["x"] + r["w"]):
                if self.in_bounds(x, y):
                    self.blocked[y][x] = True

    def in_bounds(self, x: int, y: int) -> bool:
        return 0 <= x < self.w and 0 <= y < self.h

    def door(self, location_id: str) -> tuple[int, int]:
        d = self.locations[location_id]["door"]
        return d[0], d[1]

    def find_path(self, start: tuple[int, int], goal: tuple[int, int]) -> list[tuple[int, int]]:
        """Dijkstra over the tile grid, preferring paved paths. Returns steps excluding start."""
        if start == goal:
            return []
        dist = {start: 0}
        prev: dict[tuple[int, int], tuple[int, int]] = {}
        pq = [(0, start)]
        while pq:
            d, cur = heapq.heappop(pq)
            if cur == goal:
                break
            if d > dist[cur]:
                continue
            cx, cy = cur
            for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                if not self.in_bounds(nx, ny) or self.blocked[ny][nx]:
                    continue
                nd = d + self.cost[ny][nx]
                if nd < dist.get((nx, ny), 1 << 30):
                    dist[(nx, ny)] = nd
                    prev[(nx, ny)] = cur
                    heapq.heappush(pq, (nd, (nx, ny)))
        if goal not in prev:
            return []
        path = [goal]
        while path[-1] in prev and prev[path[-1]] != start:
            path.append(prev[path[-1]])
        path.reverse()
        return path
