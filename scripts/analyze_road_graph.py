import json
import math

with open(r"C:\Users\anjo2\Downloads\road_final.geojson", "r", encoding="utf-8") as f:
    data = json.load(f)

def dist_m(p1, p2):
    # p1, p2 are [lng, lat]
    R = 6371000
    dlat = math.radians(p2[1] - p1[1])
    dlng = math.radians(p2[0] - p1[0])
    a = math.sin(dlat/2)**2 + math.cos(math.radians(p1[1])) * math.cos(math.radians(p2[1])) * math.sin(dlng/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    return R * c

features = data.get("features", [])
all_lines = []
for f in features:
    coords = f.get("geometry", {}).get("coordinates", [])
    if coords:
        all_lines.append(coords)

print(f"Total lines: {len(all_lines)}")

# Let's inspect endpoints and closeness between line segments
endpoints = []
for i, line in enumerate(all_lines):
    endpoints.append((f"line_{i}_start", line[0]))
    endpoints.append((f"line_{i}_end", line[-1]))

print("\nLine lengths & endpoints:")
for i, line in enumerate(all_lines):
    total_len = sum(dist_m(line[k], line[k+1]) for k in range(len(line)-1))
    print(f"Line {i}: {len(line)} vertices, length={total_len:.1f}m, start={line[0]}, end={line[-1]}")

# Check intersections or near-intersections (snapping distance)
print("\nChecking vertex proximity across lines:")
for i in range(len(all_lines)):
    for j in range(i + 1, len(all_lines)):
        l1 = all_lines[i]
        l2 = all_lines[j]
        min_d = float('inf')
        min_pair = None
        for idx1, p1 in enumerate(l1):
            for idx2, p2 in enumerate(l2):
                d = dist_m(p1, p2)
                if d < min_d:
                    min_d = d
                    min_pair = (idx1, idx2, p1, p2)
        print(f"Min dist between Line {i} and Line {j}: {min_d:.2f}m at L{i}[{min_pair[0]}] & L{j}[{min_pair[1]}]")
