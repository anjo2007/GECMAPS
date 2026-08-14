import json
import math

with open(r"C:\Users\anjo2\Downloads\road_final.geojson", "r", encoding="utf-8") as f:
    geojson_data = json.load(f)

# Let's save a clean, formatted GeoJSON as assets/campus_roads.json
with open("assets/campus_roads.json", "w", encoding="utf-8") as f:
    json.dump(geojson_data, f, indent=2)

print("Saved assets/campus_roads.json successfully!")
