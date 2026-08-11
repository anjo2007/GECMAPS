import os
import json
import requests

def fetch_gec_osm_data():
    overpass_url = "http://overpass-api.de/api/interpreter"
    
    # Query building names and nodes around GEC Thrissur (approx bounding box)
    # Using the coordinates from Google Maps: roughly 10.551 to 10.560 lat, 76.220 to 76.230 lon
    overpass_query = """
    [out:json][timeout:25];
    (
      node["amenity"](10.551,76.220,10.560,76.230);
      way["building"](10.551,76.220,10.560,76.230);
      node["building"](10.551,76.220,10.560,76.230);
    );
    out center;
    """
    
    print("Fetching data from OSM Overpass API for GEC Thrissur...")
    response = requests.post(overpass_url, data={'data': overpass_query})
    
    if response.status_code == 200:
        data = response.json()
        buildings = []
        for element in data.get('elements', []):
            lat = element.get('lat') or element.get('center', {}).get('lat')
            lon = element.get('lon') or element.get('center', {}).get('lon')
            tags = element.get('tags', {})
            name = tags.get('name', 'Unnamed Location')
            
            if lat and lon:
                buildings.append({
                    "id": str(element['id']),
                    "name": name,
                    "lat": lat,
                    "lng": lon,
                    "tags": tags
                })
        
        # Ensure the data directory exists
        os.makedirs("../data", exist_ok=True)
        out_path = "../data/campus_buildings.json"
        with open(out_path, "w") as f:
            json.dump(buildings, f, indent=4)
            
        print(f"Success! Bootstrapped {len(buildings)} locations from OSM.")
        print(f"Saved to: {os.path.abspath(out_path)}")
    else:
        print("Error fetching data:", response.text)

if __name__ == "__main__":
    fetch_gec_osm_data()
