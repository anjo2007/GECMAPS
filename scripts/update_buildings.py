import shutil
import json
import os

src = r"C:\Users\anjo2\OneDrive\Desktop\data\campus_buildings.json"
dst = r"C:\Users\anjo2\OneDrive\Desktop\GEC Compass\gec_compass_app\assets\campus_buildings.json"

if os.path.exists(src):
    shutil.copyfile(src, dst)

    with open(dst, "r") as f:
        data = json.load(f)

    custom_poi = {
        "id": "custom_room_101",
        "name": "Prof. Smith's Secret Lab (Mock Navigation Target)",
        "lat": 10.556100,
        "lng": 76.224500,
        "tags": {}
    }

    # Only append if not already there
    if not any(d.get("id") == custom_poi["id"] for d in data):
        data.append(custom_poi)

    with open(dst, "w") as f:
        json.dump(data, f, indent=4)
    print("Injected custom POI!")
else:
    print("Source not found: " + src)
