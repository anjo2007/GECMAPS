# 🧭 GEC Compass

**Campus Navigation App for Government Engineering College, Thrissur**

GEC Compass is a cross-platform campus navigation application built with Flutter that helps students, staff, and visitors navigate the GEC Thrissur campus with ease. It features real-time GPS tracking, turn-by-turn walking directions along campus roads, and a beautiful ambient dark-themed UI.

---

## ✨ Features

- 🗺️ **Interactive Campus Map** — Full satellite + labeled map of GEC Thrissur with building markers, categorized by type (Departments, Workshops, Hostels, Cafes/ATMs, Rooms/Labs).
- 🚶 **Walking Navigation** — Dijkstra-based shortest-path routing along actual campus roads with turn-by-turn instructions.
- 📍 **Real-Time GPS Tracking** — Live blue-dot user position with heading indicator and location accuracy ring.
- 🏢 **Place Management** — Add, edit, and manage custom places on the map with names, categories, and photos.
- ☁️ **Cloud Sync** — All custom places are synced globally via a Vercel serverless API so updates reflect on every device.
- 🌙 **Ambient Dark Theme** — A premium dark UI with smooth glassmorphism effects and micro-animations.
- 📱 **Cross-Platform** — Runs on Android (APK), Web (Vercel), iOS, Windows, macOS, and Linux.
- 💬 **WhatsApp Integration** — Quick contact via WhatsApp for feedback and support.

---

## 🏗️ Architecture

```
GEC Compass/
├── api/                        # Vercel serverless functions
│   └── places.js               # Cloud sync API (Vercel KV / GitHub Gist / GitHub Repo)
├── config.json                 # Dynamic API URL configuration
├── gec_compass_app/            # Flutter application
│   ├── lib/
│   │   ├── models/             # Data models (Building)
│   │   ├── screens/            # UI screens (MapScreen)
│   │   └── services/           # Business logic
│   │       ├── data_service.dart      # Cloud data sync service
│   │       ├── routing_service.dart   # Dijkstra road-graph navigation
│   │       └── pdr_service.dart       # Pedestrian Dead Reckoning
│   ├── assets/
│   │   └── campus_buildings.json      # OSM-sourced building data
│   └── android/                # Android platform files
├── vercel.json                 # Vercel deployment configuration
├── vercel-build.sh             # Flutter web build script for Vercel
└── package.json                # Node.js dependencies (@vercel/kv)
```

---

## 🚀 Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable channel)
- [Node.js](https://nodejs.org/) (for serverless API development)
- Android Studio or VS Code with Flutter extensions

### Run Locally

```bash
# Clone the repository
git clone https://github.com/anjo2007/GECMAPS.git
cd GECMAPS/gec_compass_app

# Get Flutter dependencies
flutter pub get

# Run on Chrome (Web)
flutter run -d chrome

# Run on Android (connected device or emulator)
flutter run
```

### Build Release APK

```bash
cd gec_compass_app
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

### Build Web

```bash
cd gec_compass_app
flutter build web --release
# Output: build/web/
```

---

## ☁️ Cloud Sync Setup

The serverless API (`api/places.js`) supports multiple database backends. Configure via Vercel environment variables:

| Backend | Environment Variables | Description |
|---------|----------------------|-------------|
| **Vercel KV** (default) | `KV_REST_API_URL`, `KV_REST_API_TOKEN` | Redis-based, auto-configured when linking Vercel KV |
| **GitHub Gist** | `GITHUB_TOKEN`, `GIST_ID` | Stores places in a GitHub Gist |
| **GitHub Repo** | `GITHUB_TOKEN`, `GITHUB_REPO` | Stores `places.json` in a repository |

If no backend is configured, the API uses an ephemeral in-memory cache (data resets on cold starts).

### Deploy to Vercel

1. Push this repository to GitHub
2. Import the project on [Vercel](https://vercel.com)
3. Vercel will automatically detect the configuration from `vercel.json`
4. (Optional) Link a Vercel KV store for persistent cloud sync

---

## 🗺️ Navigation System

The app uses a **Dijkstra shortest-path algorithm** over a hand-curated road graph of the GEC Thrissur campus. The graph contains ~40 waypoints placed along actual internal campus roads, ensuring navigation lines follow walkways instead of cutting through buildings.

### How It Works

1. User selects a destination building on the map
2. The app finds the closest road waypoint to the user's GPS position and the destination
3. Dijkstra's algorithm computes the shortest path through the campus road network
4. The route is rendered as a blue polyline on the map
5. Turn-by-turn instructions are generated from named waypoints along the route

---

## 📸 Screenshots

*Coming soon — deploy the app to see it in action!*

---

## 🛠️ Tech Stack

| Component | Technology |
|-----------|------------|
| **Frontend** | Flutter (Dart) |
| **Map** | flutter_map + OpenStreetMap tiles |
| **Backend** | Vercel Serverless Functions (Node.js) |
| **Database** | Vercel KV / GitHub API |
| **Hosting** | Vercel |
| **Navigation** | Custom Dijkstra graph routing |

---

## 📄 License

This project is open source and available under the [MIT License](LICENSE).

---

## 👨‍💻 Author

**Anjo** — [@anjo2007](https://github.com/anjo2007)

---

> Built with ❤️ for the GEC Thrissur community
