with open("lib/screens/map_screen.dart", "r", encoding="utf-8") as f:
    lines = f.readlines()

for idx, line in enumerate(lines, 1):
    if "_routingPath" in line or "_roadRoutingPath" in line or "_originalRoutingPath" in line:
        print(f"{idx}: {line.strip()}")
