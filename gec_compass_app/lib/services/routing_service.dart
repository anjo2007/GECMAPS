import 'dart:math';
import 'package:latlong2/latlong.dart';

class Waypoint {
  final String id;
  final String name;
  final LatLng position;

  Waypoint({required this.id, required this.name, required this.position});
}

class RoutingService {
  // Dense waypoint network for GEC Thrissur campus road/path network
  // Waypoints are placed along actual internal campus roads for road-snapped routing
  final List<Waypoint> waypoints = [
    // === Main Gate & Entry Road ===
    Waypoint(id: 'main_gate', name: 'Main Gate Entrance', position: const LatLng(10.554094, 76.226412)),
    Waypoint(id: 'main_gate_curve1', name: 'Main Gate Road Curve 1', position: const LatLng(10.554120, 76.226150)),
    Waypoint(id: 'main_gate_curve2', name: 'Main Gate Road Curve 2', position: const LatLng(10.554160, 76.225900)),
    Waypoint(id: 'main_junction', name: 'Main Junction (Amphitheatre)', position: const LatLng(10.554200, 76.225600)),

    // === Main Junction to Main Building (West road) ===
    Waypoint(id: 'main_road_w1', name: 'Main Road West 1', position: const LatLng(10.554280, 76.225300)),
    Waypoint(id: 'main_road_w2', name: 'Main Road West 2', position: const LatLng(10.554350, 76.225000)),
    Waypoint(id: 'main_building_front', name: 'Main Building Front', position: const LatLng(10.554418, 76.224668)),

    // === Main Building to Auditorium (South road) ===
    Waypoint(id: 'main_aud_road1', name: 'Main-Auditorium Road 1', position: const LatLng(10.554100, 76.224650)),
    Waypoint(id: 'auditorium_junction', name: 'Auditorium Junction (Cafeteria)', position: const LatLng(10.553595, 76.224567)),

    // === Auditorium to Workshops (South road continues) ===
    Waypoint(id: 'aud_workshop_road1', name: 'Aud-Workshop Road 1', position: const LatLng(10.553250, 76.224600)),
    Waypoint(id: 'workshops_junction', name: 'Workshops Road Junction', position: const LatLng(10.552883, 76.224626)),
    Waypoint(id: 'canteen_front', name: 'Canteen Entrance', position: const LatLng(10.552333, 76.224332)),

    // === Workshops Junction East to Electrical Workshop ===
    Waypoint(id: 'workshop_east_road1', name: 'Workshop East Road 1', position: const LatLng(10.552900, 76.225000)),
    Waypoint(id: 'workshop_east_road2', name: 'Workshop East Road 2', position: const LatLng(10.552950, 76.225450)),
    Waypoint(id: 'electrical_junction', name: 'Electrical Workshop Junction', position: const LatLng(10.553002, 76.225915)),

    // === Electrical Workshop to Civil Workshop (North road) ===
    Waypoint(id: 'elec_civil_road1', name: 'Elec-Civil Road 1', position: const LatLng(10.553350, 76.225890)),
    Waypoint(id: 'civil_workshop_front', name: 'Civil Workshop Front', position: const LatLng(10.553708, 76.225861)),

    // === Civil Workshop to Main Junction (North-East road) ===
    Waypoint(id: 'civil_main_road1', name: 'Civil-Main Road 1', position: const LatLng(10.553900, 76.225750)),

    // === Auditorium West to Chemical/CSE (Western campus road) ===
    Waypoint(id: 'west_road1', name: 'Western Campus Road 1', position: const LatLng(10.553500, 76.224200)),
    Waypoint(id: 'west_road2', name: 'Western Campus Road 2', position: const LatLng(10.553350, 76.223800)),
    Waypoint(id: 'chemical_junction', name: 'Chemical Engineering Junction', position: const LatLng(10.553100, 76.223400)),
    Waypoint(id: 'west_road3', name: 'Western Campus Road 3', position: const LatLng(10.552900, 76.223000)),
    Waypoint(id: 'west_road4', name: 'Western Campus Road 4', position: const LatLng(10.552800, 76.222600)),
    Waypoint(id: 'cse_ece_junction', name: 'CS / Production Junction', position: const LatLng(10.552740, 76.222020)),
    Waypoint(id: 'ece_chem_junction', name: 'ECE / Chemical Junction', position: const LatLng(10.552710, 76.221619)),

    // === Main Junction South-West to Hostel Road ===
    Waypoint(id: 'hostel_road_start', name: 'Hostel Road Start', position: const LatLng(10.554300, 76.225200)),
    Waypoint(id: 'hostel_road_mid', name: 'Hostel Road Midpoint', position: const LatLng(10.554400, 76.224500)),
    Waypoint(id: 'hostel_road_w1', name: 'Hostel Road West 1', position: const LatLng(10.554430, 76.223800)),
    Waypoint(id: 'hostel_road_w2', name: 'Hostel Road West 2', position: const LatLng(10.554440, 76.223100)),
    Waypoint(id: 'mens_hostel_junction', name: "Men's Hostel Junction", position: const LatLng(10.554442, 76.222121)),

    // === Men's Hostel Junction to CSE/ECE (South road) ===
    Waypoint(id: 'hostel_cse_road1', name: 'Hostel-CSE Road 1', position: const LatLng(10.554100, 76.222100)),
    Waypoint(id: 'hostel_cse_road2', name: 'Hostel-CSE Road 2', position: const LatLng(10.553700, 76.222080)),
    Waypoint(id: 'hostel_cse_road3', name: 'Hostel-CSE Road 3', position: const LatLng(10.553200, 76.222050)),

    // === Chemical Junction to Workshops (Cross road) ===
    Waypoint(id: 'chem_workshop_road1', name: 'Chemical-Workshop Road 1', position: const LatLng(10.552950, 76.223700)),
    Waypoint(id: 'chem_workshop_road2', name: 'Chemical-Workshop Road 2', position: const LatLng(10.552900, 76.224100)),

    // === Main Building North (Upper campus road towards reservoir) ===
    Waypoint(id: 'upper_road1', name: 'Upper Campus Road 1', position: const LatLng(10.554600, 76.224400)),
    Waypoint(id: 'upper_road2', name: 'Upper Campus Road 2', position: const LatLng(10.554700, 76.224000)),
    Waypoint(id: 'upper_road3', name: 'Upper Campus Road 3', position: const LatLng(10.554750, 76.223500)),

    // === Electrical Junction to Main Junction (via inner road) ===
    Waypoint(id: 'inner_road1', name: 'Inner Road 1', position: const LatLng(10.553500, 76.225500)),
    Waypoint(id: 'inner_road2', name: 'Inner Road 2', position: const LatLng(10.553800, 76.225400)),
  ];

  // Adjacency list: Map<NodeId, List<NeighborId>>
  late final Map<String, List<String>> _graph;

  RoutingService() {
    _graph = {
      // Main Gate entry road
      'main_gate': ['main_gate_curve1'],
      'main_gate_curve1': ['main_gate', 'main_gate_curve2'],
      'main_gate_curve2': ['main_gate_curve1', 'main_junction'],

      // Main Junction - central hub
      'main_junction': ['main_gate_curve2', 'main_road_w1', 'civil_main_road1', 'hostel_road_start'],

      // Main road westward to Main Building
      'main_road_w1': ['main_junction', 'main_road_w2'],
      'main_road_w2': ['main_road_w1', 'main_building_front'],

      // Main Building
      'main_building_front': ['main_road_w2', 'main_aud_road1', 'upper_road1'],

      // Main Building to Auditorium
      'main_aud_road1': ['main_building_front', 'auditorium_junction'],

      // Auditorium junction
      'auditorium_junction': ['main_aud_road1', 'aud_workshop_road1', 'west_road1'],

      // Auditorium to Workshops
      'aud_workshop_road1': ['auditorium_junction', 'workshops_junction'],

      // Workshops junction
      'workshops_junction': ['aud_workshop_road1', 'canteen_front', 'workshop_east_road1', 'chem_workshop_road2'],

      // Canteen
      'canteen_front': ['workshops_junction'],

      // Workshops East to Electrical
      'workshop_east_road1': ['workshops_junction', 'workshop_east_road2'],
      'workshop_east_road2': ['workshop_east_road1', 'electrical_junction'],

      // Electrical junction
      'electrical_junction': ['workshop_east_road2', 'elec_civil_road1', 'inner_road1'],

      // Electrical to Civil Workshop
      'elec_civil_road1': ['electrical_junction', 'civil_workshop_front'],
      'civil_workshop_front': ['elec_civil_road1', 'civil_main_road1'],

      // Civil Workshop back to Main Junction
      'civil_main_road1': ['civil_workshop_front', 'main_junction', 'inner_road2'],

      // Western campus road (Auditorium to CSE/ECE)
      'west_road1': ['auditorium_junction', 'west_road2'],
      'west_road2': ['west_road1', 'chemical_junction'],
      'chemical_junction': ['west_road2', 'west_road3', 'chem_workshop_road1'],
      'west_road3': ['chemical_junction', 'west_road4'],
      'west_road4': ['west_road3', 'cse_ece_junction'],
      'cse_ece_junction': ['west_road4', 'ece_chem_junction', 'hostel_cse_road3'],
      'ece_chem_junction': ['cse_ece_junction'],

      // Hostel road (Main Junction west through campus)
      'hostel_road_start': ['main_junction', 'hostel_road_mid'],
      'hostel_road_mid': ['hostel_road_start', 'hostel_road_w1', 'main_building_front'],
      'hostel_road_w1': ['hostel_road_mid', 'hostel_road_w2'],
      'hostel_road_w2': ['hostel_road_w1', 'mens_hostel_junction'],

      // Men's Hostel junction
      'mens_hostel_junction': ['hostel_road_w2', 'hostel_cse_road1'],

      // Men's Hostel to CSE (south)
      'hostel_cse_road1': ['mens_hostel_junction', 'hostel_cse_road2'],
      'hostel_cse_road2': ['hostel_cse_road1', 'hostel_cse_road3'],
      'hostel_cse_road3': ['hostel_cse_road2', 'cse_ece_junction'],

      // Chemical to Workshops cross-road
      'chem_workshop_road1': ['chemical_junction', 'chem_workshop_road2'],
      'chem_workshop_road2': ['chem_workshop_road1', 'workshops_junction'],

      // Upper campus road (Main Building north)
      'upper_road1': ['main_building_front', 'upper_road2'],
      'upper_road2': ['upper_road1', 'upper_road3'],
      'upper_road3': ['upper_road2', 'hostel_road_w1'],

      // Inner roads connecting east campus
      'inner_road1': ['electrical_junction', 'inner_road2'],
      'inner_road2': ['inner_road1', 'civil_main_road1'],
    };
  }

  // Calculate distance in meters between two LatLng points (Haversine)
  double distance(LatLng a, LatLng b) {
    const double R = 6371000;
    final dLat = (b.latitude - a.latitude) * (pi / 180);
    final dLng = (b.longitude - a.longitude) * (pi / 180);
    final aCalc = sin(dLat / 2) * sin(dLat / 2) +
        cos(a.latitude * pi / 180) *
            cos(b.latitude * pi / 180) *
            sin(dLng / 2) *
            sin(dLng / 2);
    final c = 2 * atan2(sqrt(aCalc), sqrt(1 - aCalc));
    return R * c;
  }

  // Find the closest waypoint to a given point
  Waypoint findClosestWaypoint(LatLng point) {
    Waypoint closest = waypoints.first;
    double minDistance = distance(point, closest.position);

    for (var wp in waypoints) {
      final dist = distance(point, wp.position);
      if (dist < minDistance) {
        minDistance = dist;
        closest = wp;
      }
    }
    return closest;
  }

  // Dijkstra's algorithm to find the shortest path between two waypoints
  List<LatLng> getRouteBetweenWaypoints(String startId, String endId) {
    if (startId == endId) {
      final wp = waypoints.firstWhere((w) => w.id == startId);
      return [wp.position];
    }

    final Map<String, double> distances = {};
    final Map<String, String?> previous = {};
    final Set<String> unvisited = {};

    for (var wp in waypoints) {
      distances[wp.id] = double.infinity;
      previous[wp.id] = null;
      unvisited.add(wp.id);
    }
    distances[startId] = 0;

    while (unvisited.isNotEmpty) {
      // Find unvisited node with minimum distance
      String? currentId;
      double minDist = double.infinity;
      for (var id in unvisited) {
        if (distances[id]! < minDist) {
          minDist = distances[id]!;
          currentId = id;
        }
      }

      if (currentId == null || currentId == endId) break;

      unvisited.remove(currentId);

      final currentWp = waypoints.firstWhere((w) => w.id == currentId);
      final neighbors = _graph[currentId] ?? [];

      for (var neighborId in neighbors) {
        if (!unvisited.contains(neighborId)) continue;

        final neighborWp = waypoints.firstWhere((w) => w.id == neighborId);
        final weight = distance(currentWp.position, neighborWp.position);
        final alt = distances[currentId]! + weight;

        if (alt < distances[neighborId]!) {
          distances[neighborId] = alt;
          previous[neighborId] = currentId;
        }
      }
    }

    // Reconstruct path
    final List<LatLng> path = [];
    String? current = endId;
    while (current != null) {
      final wp = waypoints.firstWhere((w) => w.id == current);
      path.insert(0, wp.position);
      current = previous[current];
    }

    // If start node has no path to end node
    if (path.isEmpty || path.first != waypoints.firstWhere((w) => w.id == startId).position) {
      return [];
    }

    return path;
  }

  // Get complete routing path: Start -> Closest start waypoint -> shortest path waypoints -> Closest end waypoint -> End
  List<LatLng> getFullRoute(LatLng start, LatLng end) {
    // If start and end are extremely close, just return direct line
    if (distance(start, end) < 15.0) {
      return [start, end];
    }

    final startWp = findClosestWaypoint(start);
    final endWp = findClosestWaypoint(end);

    // If closest waypoints are the same, just route through that waypoint
    if (startWp.id == endWp.id) {
      return [start, startWp.position, end];
    }

    final waypointPath = getRouteBetweenWaypoints(startWp.id, endWp.id);
    if (waypointPath.isEmpty) {
      return [start, end]; // Fallback to straight line
    }

    return [
      start,
      ...waypointPath,
      end,
    ];
  }

  // Calculate total route distance in meters
  double getRouteDistance(List<LatLng> route) {
    double total = 0;
    for (int i = 0; i < route.length - 1; i++) {
      total += distance(route[i], route[i + 1]);
    }
    return total;
  }

  // Estimated walking time in minutes (average walking speed ~5 km/h = 83.3 m/min)
  double getEstimatedWalkingTime(List<LatLng> route) {
    return getRouteDistance(route) / 83.3;
  }

  // Generate visual instructions for steps
  List<String> getRouteInstructions(List<LatLng> route) {
    if (route.length < 2) return ["You have arrived."];
    List<String> instructions = [];

    for (int i = 0; i < route.length - 1; i++) {
      final p1 = route[i];
      final p2 = route[i + 1];
      final d = distance(p1, p2);

      // Skip very short segments for cleaner instructions (< 10m)
      // but always include first and last
      if (d < 10 && i > 0 && i < route.length - 2) continue;

      // Find if we are matching a waypoint
      String fromName = "your location";
      String toName = "destination";

      for (var wp in waypoints) {
        if (distance(p1, wp.position) < 5.0) fromName = wp.name;
        if (distance(p2, wp.position) < 5.0) toName = wp.name;
      }

      if (i == 0) {
        instructions.add("Head towards $toName (${d.toStringAsFixed(0)} m)");
      } else if (i == route.length - 2) {
        instructions.add("Walk the final stretch to your destination (${d.toStringAsFixed(0)} m)");
      } else {
        // Only add named waypoint instructions (skip unnamed intermediate points)
        if (!toName.contains('Road') && toName != 'destination') {
          instructions.add("Walk from $fromName to $toName (${d.toStringAsFixed(0)} m)");
        }
      }
    }
    return instructions;
  }
}
