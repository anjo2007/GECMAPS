# 🧭 GEC Compass

**Campus Navigation & Interactive Map for Government Engineering College, Thrissur**

GEC Compass is a high-performance, cross-platform campus navigation application built with Flutter that helps students, faculty, staff, and visitors navigate the GEC Thrissur campus with precision. It features real-time GPS tracking with Pedestrian Dead Reckoning (PDR), Dijkstra-based optimal routing along campus walkways and road networks, place type categorization, and cloud synchronization.

> [!TIP]
> 📲 **[Download the Optimized Android APK (ARM64-v8a)](./app-arm64-v8a-release.apk)** — For modern Android devices.

---

## ✨ Key Features

- 🗺️ **Interactive Campus Map** — Comprehensive satellite, ambient, and light-themed map of GEC Thrissur with building markers, high-accuracy geometry, and zoom-aware label rendering.
- 🚶 **Optimal Road & Path Navigation** — Dijkstra shortest-path network routing powered by `campus_roads.json` (247 nodes, 273 connected road/walkway edges) with turn-by-turn guidance and network-aware gate routing.
- 🎯 **Accurate Campus Boundaries** — Full coverage of both East and West wings of the campus (Main Blocks, Post Graduate Block, Dept. of Architecture, Hostels, Workshops).
- 📍 **Reliable Location Recenter** — Instant-response location recenter button with cold-start cache fallback (`getLastKnownPosition()`) and high-accuracy GPS lock.
- 🏢 **Place & Category Management** — Add, edit, and categorize custom places on the map with full Place Type editing (Departments, Workshops, Hostels, Cafes/ATMs, Rooms/Labs, Washrooms, Entrance Gate, Other), search keywords, operating hours, and floor mapping.
- ☁️ **Global Cloud Sync & Persistence** — Real-time cloud sync via Vercel serverless API with multi-backend failover (Vercel KV / GitHub Gist / GitHub Repository) and local offline-first caching.
- 🧭 **Sensor Fusion & PDR** — Pedestrian Dead Reckoning (PDR) with Weinberg step length estimation and circular Exponential Moving Average (EMA) compass smoothing.
- 🌙 **Ambient Dark & Adaptive Themes** — Premium dark UI with glassmorphism effects, fluid micro-interactions, and accessible typography.
- 📱 **Cross-Platform Support** — Runs seamlessly on Android, Web (Vercel), iOS, Windows, macOS, and Linux.

---

## 🏗️ Project Architecture

```
GEC Compass/
├── api/                               # Vercel serverless functions
│   ├── places.js                      # Cloud sync API (Vercel KV / GitHub Gist / GitHub Repo)
│   ├── share.js                       # Location sharing endpoints
│   ├── sitemap.js                     # Dynamic SEO sitemap generator
│   └── version.js                     # App release & version endpoint
├── config.json                        # Dynamic API URL configuration
├── gec_compass_app/                   # Flutter application
│   ├── lib/
│   │   ├── models/                    # Data models (Building, etc.)
│   │   ├── screens/                   # UI screens (MapScreen, etc.)
│   │   ├── services/                  # Core services
│   │   │   ├── data_service.dart      # Local & cloud building sync
│   │   │   ├── routing_service.dart   # Dijkstra road-graph navigation & gate selection
│   │   │   ├── pdr_service.dart       # Pedestrian Dead Reckoning & sensor fusion
│   │   │   └── grid_addressing_service.dart # Local spatial grid indexing
│   │   └── widgets/                   # Reusable UI components
│   ├── assets/
│   │   ├── campus_buildings.json      # Base campus building & department dataset
│   │   └── campus_roads.json          # 247-node connected road & walkway graph
│   └── web/                           # Web assets & splash configuration
├── vercel.json                        # Vercel deployment configuration & routing
├── vercel-build.sh                    # Flutter web automated build script
└── package.json                       # Node.js dependencies
```

---

## 🚀 Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable channel)
- [Node.js](https://nodejs.org/) (v18+ recommended)
- Android Studio or VS Code with Flutter extensions

### Run Locally

```bash
# Clone the repository
git clone https://github.com/anjo2007/Gec__compass.git
cd Gec__compass/gec_compass_app

# Get Flutter dependencies
flutter pub get

# Run on Chrome (Web)
flutter run -d chrome

# Run on Android device or emulator
flutter run
```

### Build Release Packages

```bash
# Build Android APK
cd gec_compass_app
flutter build apk --release

# Build Web Bundle
flutter build web --release
```

---

## ☁️ Cloud Sync & Storage Setup

The serverless API (`api/places.js`) supports multiple database backends and a **secondary backup option** to ensure reliability.

### Primary Storage Options
Configure one of the following as primary in your environment variables:

| Backend | Environment Variables | Description |
|---|---|---|
| **Vercel KV** (default) | `KV_REST_API_URL`, `KV_REST_API_TOKEN` | Redis-based, auto-configured when linking Vercel KV |
| **GitHub Gist** | `GITHUB_TOKEN`, `GIST_ID` | Stores places in a GitHub Gist |
| **GitHub Repo** | `GITHUB_TOKEN`, `GITHUB_REPO` | Stores `places.json` in a repository |

### Secondary Backup Options
You can configure a backup storage option that runs alongside the primary. When both primary and backup are configured, the API performs **dual-writes** on every `POST` and **read failover** on `GET`.

| Backup Backend | Environment Variables | Description |
|---|---|---|
| **GitHub Repo Backup** | `BACKUP_GITHUB_REPO` | Backup repository path (e.g., `username/repo`). Uses `GITHUB_TOKEN` |
| **Vercel KV Backup** | `BACKUP_KV_REST_API_URL`, `BACKUP_KV_REST_API_TOKEN` | Secondary Vercel KV store |
| **GitHub Gist Backup** | `BACKUP_GIST_ID` | Secondary GitHub Gist ID. Uses `GITHUB_TOKEN` |

---

## 🗺️ Campus Road Graph & Navigation System

The app utilizes a custom **Dijkstra shortest-path algorithm** executed over `campus_roads.json`, representing 247 nodes and 273 connected edges surveyed across GEC Thrissur.

### Routing Logic

1. **Snap to Road Network**: Snaps origin (user GPS/PDR position) and target building to nearest road network segment.
2. **Network Gate Selection**: For boundary crossings, evaluates Dijkstra shortest-path road distances through all campus gates (Electrical Gate, Main Gate, East Gate).
3. **Turn-by-Turn Waypoints**: Generates clear navigation cues along internal walkways and road segments.

---

## 📄 License

This project is open source and available under the [MIT License](LICENSE).

---

## 👨‍💻 Author

**Anjo** — [@anjo2007](https://github.com/anjo2007)

---

> Built with ❤️ for the Government Engineering College (GEC) Thrissur community.
