import json, os, glob

with open("assets/campus_buildings.json", "r", encoding="utf-8") as f:
    data = json.load(f)

print(f"Total places: {len(data)}")
for item in data:
    name = item.get("name", "")
    tags = item.get("tags", {})
    if "gate" in name.lower() or tags.get("barrier") == "gate" or tags.get("entrance") == "yes":
        print(f"ID: {item.get('id')} | Name: {name} | Tags: {tags}")
