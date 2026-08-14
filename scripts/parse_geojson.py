import json

geojson_path = r"C:\Users\anjo2\Downloads\road_final.geojson"
with open(geojson_path, "r", encoding="utf-8") as f:
    data = json.load(f)

print("Type:", data.get("type"))
features = data.get("features", [])
print("Features count:", len(features))

total_coords = 0
for i, feat in enumerate(features):
    geom = feat.get("geometry", {})
    gtype = geom.get("type")
    coords = geom.get("coordinates", [])
    props = feat.get("properties", {})
    total_coords += len(coords)
    if i < 15:
        print(f"Feature {i}: type={gtype}, num_points={len(coords)}, props={props}")

print("Total coordinate points across all features:", total_coords)
