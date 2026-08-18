import json

with open("assets/campus_buildings.json", "r", encoding="utf-8") as f:
    data = json.load(f)

for b in data:
    if b.get("id") == "gate_main_entrance":
        b["tags"]["opening_time"] = "06:00 AM"
        b["tags"]["closing_time"] = "10:30 PM"
        b["tags"]["opening_hours"] = "06:00 AM - 10:30 PM"
    elif b.get("id") == "gate_south_canteen_entrance":
        b["tags"]["opening_time"] = "08:00 AM"
        b["tags"]["closing_time"] = "05:30 PM"
        b["tags"]["opening_hours"] = "08:00 AM - 05:30 PM"
    elif b.get("id") == "gate_east_electrical_entrance":
        b["tags"]["opening_time"] = "06:00 AM"
        b["tags"]["closing_time"] = "09:00 PM"
        b["tags"]["opening_hours"] = "06:00 AM - 09:00 PM"

with open("assets/campus_buildings.json", "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)

print("Updated campus_buildings.json with gate opening/closing hours!")
