from fastapi import FastAPI
from pydantic import BaseModel
from typing import List, Dict
from fastapi.responses import JSONResponse
from heapq import heappop, heappush
import pandas as pd
import numpy as np
import json
import ast

app = FastAPI()

CSV_PATH = "booth_coordinates.csv"

@app.on_event("startup")

def load_booth_data(csv_path):
    import pandas as pd
    df = pd.read_csv(csv_path)
    booths = []
    for _, row in df.iterrows():
        booth = {
            "name": row["Name"],
            "description": row["Description"],
            "type": "booth",  # Adjust if needed
            "area": {
                "start": {"x": int(row["Start_X"]), "y": int(row["Start_Y"])},
                "end": {"x": int(row["End_X"]), "y": int(row["End_Y"])}
            }
        }
        booths.append(booth)
    return booths


booth_data = load_booth_data(CSV_PATH)
VENUE_GRID = generate_venue_grid(CSV_PATH)

BEACON_POSITIONS = {
    "17091": (0, 0),
    "15995":(1,0),
    "25450":(0,1)
}

# ====== Models ======
class BLEReading(BaseModel):
    uuid: str
    rssi: int

class BLEScan(BaseModel):
    ble_data: List[BLEReading]

class PathRequest(BaseModel):
    from_: List[int]
    to: str

# ====== API ======
@app.post("/locate")
def locate_user(data: BLEScan):
    weighted_sum_x = 0
    weighted_sum_y = 0
    total_weight = 0

    for reading in data.ble_data:
        pos = BEACON_POSITIONS.get(reading.uuid)
        if pos:
            weight = 1 / (abs(reading.rssi) + 1)
            weighted_sum_x += pos[0] * weight
            weighted_sum_y += pos[1] * weight
            total_weight += weight

    if total_weight == 0:
        return {"x": -1, "y": -1}

    x = round(weighted_sum_x / total_weight)
    y = round(weighted_sum_y / total_weight)
    return {"x": x, "y": y}

@app.post("/path")
def get_path(request: PathRequest):
    print("✅ /path endpoint hit:", request)
    booth_name = request.to.strip().lower()
    booth = next((b for b in booth_data if b["name"].strip().lower() == booth_name), None)

    if not booth:
        print("❌ Booth not found:", booth_name)
        return JSONResponse(content={"error": "Booth not found"}, status_code=404)

    cell_size = 50
    goal_grid = (
        int(booth["center"]["x"] // cell_size),
        int(booth["center"]["y"] // cell_size)
    )

    def find_nearest_free_cell(goal, grid):
        directions = [
            (0, 1), (1, 0), (-1, 0), (0, -1),
            (1, 1), (-1, -1), (1, -1), (-1, 1)
        ]
        for dx, dy in directions:
            nx, ny = goal[0] + dx, goal[1] + dy
            if 0 <= nx < len(grid[0]) and 0 <= ny < len(grid):
                if grid[ny][nx] == 1:
                    return (nx, ny)
        return None

    print(f"📍 Routing from {request.from_} to grid cell {goal_grid}")
    print("🧱 Sample grid slice at goal:")
    print(np.array(VENUE_GRID)[goal_grid[1]-1:goal_grid[1]+2, goal_grid[0]-1:goal_grid[0]+2])

    # 🔁 If goal is blocked, find a nearby free cell
    if VENUE_GRID[goal_grid[1]][goal_grid[0]] == 0:
        print("⚠️ Goal is blocked. Searching for nearby free cell...")
        new_goal = find_nearest_free_cell(goal_grid, VENUE_GRID)
        if not new_goal:
            print("❌ No valid nearby goal found.")
            return {"path": []}
        print(f"✅ Redirected goal to: {new_goal}")
        goal_grid = new_goal

    path = a_star(tuple(request.from_), goal_grid)
    print(f"🧭 Final path: {path}")
    if path:
        print(f"🏁 Last cell in path: {path[-1]}, Target goal: {goal_grid}")

    return {"path": path}


@app.get("/booths")
def get_booths():
    return JSONResponse(content=booth_data)

@app.get("/booths/{booth_id}")
def get_booth_by_id(booth_id: int):
    booth = next((b for b in booth_data if b["booth_id"] == booth_id), None)
    return booth or {"error": "Booth not found"}

@app.get("/map-data")
def get_map_data():
    return JSONResponse(content={"elements": booth_data})

# ====== A* Algorithm ======
def a_star(start, goal):
    def heuristic(a, b):
        return abs(a[0] - b[0]) + abs(a[1] - b[1])

    neighbors = [(0, 1), (1, 0), (-1, 0), (0, -1)]
    open_set = [(heuristic(start, goal), 0, start, [])]
    visited = set()

    while open_set:
            est_total_cost, path_cost, current, path = heappop(open_set)

            if current == goal:
                return path + [current]

            if current in visited:
                continue
            visited.add(current)

            for dx, dy in neighbors:
                nx, ny = current[0] + dx, current[1] + dy

                # Check bounds
                if 0 <= nx < len(VENUE_GRID[0]) and 0 <= ny < len(VENUE_GRID):
                    # Check if the cell is walkable (1 = free space)
                    if VENUE_GRID[ny][nx] == 1 and (nx, ny) not in visited:
                        next_cost = path_cost + 1
                        estimated_total = next_cost + heuristic((nx, ny), goal)
                        heappush(open_set, (
                            estimated_total,
                            next_cost,
                            (nx, ny),
                            path + [current]
                        ))

    return []

@app.get("/")
def root():
    return {"message": "InMaps backend is running!"}