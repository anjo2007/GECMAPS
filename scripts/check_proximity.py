import json
import math

with open(r"C:\Users\anjo2\Downloads\road_final.geojson", "r", encoding="utf-8") as f:
    data = json.load(f)

with open("assets/campus_buildings.json", "r", encoding="utf-8") as f:
    b_data = json.load(f)

def dist_m(p1, p2):
    R = 6371000
    dlat = math.radians(p2[1] - p1[1])
    dlng = math.radians(p2[0] - p1[0])
    a = math.sin(dlat/2)**2 + math.cos(math.radians(p1[1])) * math.cos(math.radians(p2[1])) * math.sin(dlng/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    return R * c

# Extract all vertices
all_pts = []
for f in data.get("features", []):
    for pt in f.get("geometry", {}).get("coordinates", []):
        all_pts.append(pt)

print("Checking buildings and gates proximity to road network:")
for b in b_data:
    b_pt = [b["lng"], b["lat"]]
    name = b.get("name", "")
    is_gate = "gate" in name.lower() or b.get("tags", {}).get("barrier") == "gate"
    
    # find closest road pt
    min_d = min(dist_m(b_pt, pt) for pt in all_pts)
    if is_gate or min_d > 50:
        print(f"Building/Gate '{name}' ({b['id']}): distance to road = {min_d:.2f}m")
