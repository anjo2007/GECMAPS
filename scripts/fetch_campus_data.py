import os
import sys
import json
import requests

# Set this environment variable before running the script
API_KEY = os.environ.get("GOOGLE_MAPS_API_KEY")

if not API_KEY:
    print("Error: GOOGLE_MAPS_API_KEY environment variable is not set.")
    print("Please set your API key in the terminal and try again.")
    print("For Windows PowerShell:")
    print("    $env:GOOGLE_MAPS_API_KEY=\"your_actual_api_key\"")
    print("    python fetch_campus_data.py")
    sys.exit(1)

def fetch_gec_buildings():
    url = "https://places.googleapis.com/v1/places:searchText"
    
    headers = {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": API_KEY,
        "X-Goog-FieldMask": "places.id,places.displayName,places.location,places.formattedAddress,places.types"
    }
    
    # We bias the search within a 500-meter radius of the center of GEC Thrissur
    # 500m radius covers roughly ~78 acres (campus is 75 acres)
    data = {
        "textQuery": "GEC Thrissur department OR building OR lab OR facility",
        "locationBias": {
            "circle": {
                "center": {
                    "latitude": 10.555761,
                    "longitude": 76.224317
                },
                "radius": 500.0 
            }
        },
        "languageCode": "en"
    }
    
    print("Fetching geographical data for GEC Thrissur from Google Places API...")
    response = requests.post(url, headers=headers, json=data)
    
    if response.status_code == 200:
        places_data = response.json()
        
        output_data = []
        for place in places_data.get("places", []):
            name = place.get("displayName", {}).get("text", "Unknown")
            location = place.get("location", {})
            place_id = place.get("id", "")
            address = place.get("formattedAddress", "")
            types = place.get("types", [])
            
            output_data.append({
                "name": name,
                "place_id": place_id,
                "lat": location.get("latitude"),
                "lng": location.get("longitude"),
                "types": types,
                "address": address
            })
            
        # Ensure the data directory exists
        os.makedirs("../data", exist_ok=True)
        
        # Save output to our graph database source folder
        out_path = "../data/campus_buildings.json"
        with open(out_path, "w") as f:
            json.dump(output_data, f, indent=4)
            
        print(f"Success! Bootstrapped {len(output_data)} building locations.")
        print(f"Saved to: {os.path.abspath(out_path)}")
    else:
        print(f"API Error ({response.status_code}): {response.text}")

if __name__ == "__main__":
    fetch_gec_buildings()
