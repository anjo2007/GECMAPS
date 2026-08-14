import json, math

with open(r"C:\Users\anjo2\Downloads\road_final.geojson", "r", encoding="utf-8") as f:
    r_data = json.load(f)

with open("assets/campus_buildings.json", "r", encoding="utf-8") as f:
    b_data = json.load(f)

def dist_m(p1, p2):
    R = 6371000
    dlat = math.radians(p2[1] - p1[1])
    dlng = math.radians(p2[0] - p1[0])
    a = math.sin(dlat/2)**2 + math.cos(math.radians(p1[1])) * math.cos(math.radians(p2[1])) * math.sin(dlng/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    return R * c

all_pts = []
for f in r_data.get("features", []):
    for pt in f.get("geometry", {}).get("coordinates", []):
        all_pts.append(pt)

for b in b_data:
    if "gate" in b["id"]:
        b_pt = [b["lng"], b["lat"]]
        closest_pt = min(all_pts, key=lambda p: dist_m(b_pt, p))
        print(f"Gate {b['id']} ({b['name']}): lat={b['lat']}, lng={b['lng']}")
        print(f"  Closest road node: lat={closest_pt[1]}, lng={closest_pt[0]} (dist={dist_m(b_pt, closest_pt):.2f}m)")
