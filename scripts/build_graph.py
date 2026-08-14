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

def point_segment_distance(p, a, b):
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

# Extract all raw coordinates and lines
features = data.get("features", [])
raw_lines = [f.get("geometry", {}).get("coordinates", []) for f in features if f.get("geometry", {}).get("coordinates")]

# We want to build clean nodes and edges
# Step 1: Collect all vertices from all lines
# Step 2: For each vertex, if it is close to a segment of another line (or itself) with 0.01 < t < 0.99 and dist < 2.0m, insert the snapped point into that segment
# Let's do a multi-pass splitting
lines = [[list(pt) for pt in line] for line in raw_lines]

# Collect all potential split points
for _ in range(3): # repeat to catch cascade splits
    new_lines = []
    for i, line in enumerate(lines):
        split_points = {} # index -> list of (t, snapped_pt)
        for pt_line in lines:
            for pt in pt_line:
                for k in range(len(line) - 1):
                    a = line[k]
                    b = line[k+1]
                    d, t, snapped = point_segment_distance(pt, a, b)
                    if d < 2.5 and 0.02 < t < 0.98:
                        if k not in split_points:
                            split_points[k] = []
                        split_points[k].append((t, snapped))
        
        # Now reconstruct line with splits inserted
        new_line = []
        for k in range(len(line)):
            new_line.append(line[k])
            if k in split_points:
                # Sort splits by t
                sp = sorted(split_points[k], key=lambda x: x[0])
                for t_val, sn_pt in sp:
                    # Avoid adding duplicate very close points
                    if dist_m(new_line[-1], sn_pt) > 0.5:
                        new_line.append(sn_pt)
        new_lines.append(new_line)
    lines = new_lines

# Cluster vertices within 1.5m to unify node IDs
nodes = [] # list of [lng, lat]
def get_or_create_node(pt):
    for idx, node in enumerate(nodes):
        if dist_m(node, pt) < 1.8:
            return idx
    nodes.append(pt)
    return len(nodes) - 1

adjacency = {}
edges_set = set()

for line in lines:
    for k in range(len(line) - 1):
        u = get_or_create_node(line[k])
        v = get_or_create_node(line[k+1])
        if u != v:
            edge = (min(u, v), max(u, v))
            if edge not in edges_set:
                edges_set.add(edge)
                adjacency.setdefault(u, set()).add(v)
                adjacency.setdefault(v, set()).add(u)

print(f"Total Unique Nodes: {len(nodes)}")
print(f"Total Edges: {len(edges_set)}")

# Connectivity check (BFS)
visited = set()
components = []
for node_id in range(len(nodes)):
    if node_id not in visited:
        comp = []
        q = [node_id]
        visited.add(node_id)
        while q:
            curr = q.pop()
            comp.append(curr)
            for nbr in adjacency.get(curr, []):
                if nbr not in visited:
                    visited.add(nbr)
                    q.append(nbr)
        components.append(comp)

print(f"Connected Components count: {len(components)}")
for idx, comp in enumerate(components):
    print(f"  Component {idx}: {len(comp)} nodes")
