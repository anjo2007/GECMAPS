import json
import math

with open(r"C:\Users\anjo2\Downloads\road_final.geojson", "r", encoding="utf-8") as f:
    data = json.load(f)

def dist_m(p1, p2):
    R = 6371000
    dlat = math.radians(p2[1] - p1[1])
    dlng = math.radians(p2[0] - p1[0])
    a = math.sin(dlat/2)**2 + math.cos(math.radians(p1[1])) * math.cos(math.radians(p2[1])) * math.sin(dlng/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    return R * c

# Project point P onto segment AB
def point_segment_distance(p, a, b):
    # p, a, b are [lng, lat]
    lat_rad = math.radians(p[1])
    m_lat = 111139.0
    m_lng = 111139.0 * math.cos(lat_rad)
    
    px = (p[0] - a[0]) * m_lng
    py = (p[1] - a[1]) * m_lat
    bx = (b[0] - a[0]) * m_lng
    by = (b[1] - a[1]) * m_lat
    
    seg_len_sq = bx*bx + by*by
    t = 0.0
    if seg_len_sq > 0:
        t = max(0.0, min(1.0, (px*bx + py*by) / seg_len_sq))
    
    proj_x = t * bx
    proj_y = t * by
    
    dist = math.sqrt((px - proj_x)**2 + (py - proj_y)**2)
    snapped = [a[0] + proj_x / m_lng, a[1] + proj_y / m_lat]
    return dist, t, snapped

features = data.get("features", [])
all_lines = [f.get("geometry", {}).get("coordinates", []) for f in features if f.get("geometry", {}).get("coordinates")]

print(f"Checking T-junctions and connections between all {len(all_lines)} lines:")
# For each vertex in each line, find closest segment in other lines
for i, line1 in enumerate(all_lines):
    for idx, v in enumerate(line1):
        for j, line2 in enumerate(all_lines):
            if i == j:
                continue
            for k in range(len(line2) - 1):
                a = line2[k]
                b = line2[k+1]
                d, t, snapped = point_segment_distance(v, a, b)
                if d < 5.0: # within 5 meters
                    # Check if endpoint or intermediate
                    print(f"Line {i} vertex {idx} ({v}) connects to Line {j} segment {k}->{k+1} at dist={d:.2f}m, t={t:.3f}")
