import json

buildings_path = 'gec_compass_app/assets/campus_buildings.json'

with open(buildings_path, 'r', encoding='utf-8') as f:
    places = json.load(f)

# Deduplicate and filter out unnamed
unique_places = {}
for p in places:
    if p.get('id') and p.get('name') and p['name'] != 'Unnamed Location':
        unique_places[p['id']] = p

valid_places = list(unique_places.values())
print(f"Loaded {len(valid_places)} valid places.")

# Categorize places
categories = {
    "Engineering Departments & Academic Blocks": [],
    "Laboratories & Technical Centers": [],
    "Administrative, Library & Seminar Halls": [],
    "Campus Hostels & Residential Buildings": [],
    "Cafeterias, Canteens & Refreshments": [],
    "Campus Entrance Gates": [],
    "Banking & Utilities": [],
    "Other Campus Landmarks": []
}

for p in valid_places:
    name = p['name']
    tags = p.get('tags', {})
    name_lower = name.lower()
    place_type = tags.get('place_type', '').lower()
    building = tags.get('building', '').lower()
    amenity = tags.get('amenity', '').lower()
    tourism = tags.get('tourism', '').lower()
    barrier = tags.get('barrier', '').lower()

    if barrier == 'gate' or 'gate' in name_lower or 'entrance' in name_lower:
        categories["Campus Entrance Gates"].append(p)
    elif 'hostel' in name_lower or tourism == 'hostel':
        categories["Campus Hostels & Residential Buildings"].append(p)
    elif 'canteen' in name_lower or 'mess' in name_lower or 'cafe' in name_lower or 'ice' in name_lower or 'restaurant' in name_lower or amenity in ['restaurant', 'cafe', 'fast_food']:
        categories["Cafeterias, Canteens & Refreshments"].append(p)
    elif 'bank' in name_lower or 'atm' in name_lower or amenity in ['bank', 'atm']:
        categories["Banking & Utilities"].append(p)
    elif 'lab' in name_lower or 'workshop' in name_lower or 'centre' in name_lower or 'center' in name_lower:
        categories["Laboratories & Technical Centers"].append(p)
    elif 'department' in name_lower or 'dept' in name_lower or 'block' in name_lower or building == 'college' or place_type == 'departments':
        categories["Engineering Departments & Academic Blocks"].append(p)
    elif any(k in name_lower for k in ['office', 'library', 'auditorium', 'store', 'security', 'gym', 'ground', 'chapel']):
        categories["Administrative, Library & Seminar Halls"].append(p)
    else:
        categories["Other Campus Landmarks"].append(p)

# Generate ItemList for Schema.org JSON-LD
item_list_elements = []
for idx, p in enumerate(valid_places, 1):
    item_list_elements.append({
        "@type": "ListItem",
        "position": idx,
        "item": {
            "@type": "Place",
            "name": p['name'],
            "url": f"https://gecmaps.vercel.app/api/share?id={p['id']}",
            "hasMap": f"https://gecmaps.vercel.app/?placeId={p['id']}",
            "geo": {
                "@type": "GeoCoordinates",
                "latitude": p['lat'],
                "longitude": p['lng']
            },
            "containedInPlace": {
                "@type": "CollegeOrUniversity",
                "name": "Government Engineering College Thrissur"
            }
        }
    })

item_list_schema = {
    "@type": "ItemList",
    "@id": "https://gecmaps.vercel.app/#places-directory",
    "name": "GECT Compass & GEC Maps - Complete Campus Directory",
    "description": "Complete directory of all departments, laboratories, hostels, canteens, and amenities at Government Engineering College Thrissur on GEC Maps & GECT Compass.",
    "numberOfItems": len(item_list_elements),
    "itemListElement": item_list_elements
}

# Generate crawlable HTML directory
html_dir = "      <section>\n"
html_dir += "        <h2>Complete Campus Directory &amp; Interactive Navigation Locations (GEC Maps &amp; GECT Compass)</h2>\n"
html_dir += "        <p>Explore every single department block, laboratory, hostel, canteen, entrance gate, and campus amenity on GEC Maps and GECT Compass at Government Engineering College Thrissur:</p>\n"

for cat_name, cat_places in categories.items():
    if not cat_places:
        continue
    html_dir += f"        <article>\n          <h3>{cat_name}</h3>\n          <ul>\n"
    for p in cat_places:
        p_name = p['name'].replace('&', '&amp;')
        p_id = p['id']
        p_lat = p['lat']
        p_lng = p['lng']
        p_url = f"https://gecmaps.vercel.app/api/share?id={p_id}"
        html_dir += f'            <li><a href="{p_url}"><strong>{p_name}</strong></a> (Lat: {p_lat}, Lng: {p_lng}) — walking directions and compass navigation on GEC Maps / GECT Compass.</li>\n'
    html_dir += "          </ul>\n        </article>\n"
html_dir += "      </section>\n"

with open('scripts/generated_seo_items.json', 'w', encoding='utf-8') as f:
    json.dump(item_list_schema, f, indent=2)

with open('scripts/generated_seo_html.html', 'w', encoding='utf-8') as f:
    f.write(html_dir)

print("Saved output to scripts/generated_seo_items.json and scripts/generated_seo_html.html")
