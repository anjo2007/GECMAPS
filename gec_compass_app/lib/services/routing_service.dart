import 'dart:math';
import 'package:latlong2/latlong.dart';

class Waypoint {
  final String id;
  final String name;
  final LatLng position;

  Waypoint({required this.id, required this.name, required this.position});
}

class RoutingService {
  // Waypoints for GEC Thrissur road/path network (densified with key buildings)
  final List<Waypoint> waypoints = [
    Waypoint(id: 'main_gate', name: 'Main Gate Entrance', position: const LatLng(10.554094, 76.226412)),
    Waypoint(id: 'main_junction', name: 'Main Junction (Amphitheatre)', position: const LatLng(10.554200, 76.225600)),
    Waypoint(id: 'main_building_front', name: 'Main Building Front', position: const LatLng(10.554418, 76.224668)),
    Waypoint(id: 'auditorium_junction', name: 'Auditorium Junction (Cafeteria)', position: const LatLng(10.553595, 76.224567)),
    Waypoint(id: 'workshops_junction', name: 'Workshops Road Junction', position: const LatLng(10.552883, 76.224626)),
    Waypoint(id: 'electrical_junction', name: 'Electrical Workshop Junction', position: const LatLng(10.553002, 76.225915)),
    Waypoint(id: 'civil_workshop_front', name: 'Civil Workshop Front', position: const LatLng(10.553708, 76.225861)),
    Waypoint(id: 'cse_ece_junction', name: 'CS / Production Junction', position: const LatLng(10.552740, 76.222020)),
    Waypoint(id: 'ece_chem_junction', name: 'ECE / Chemical Junction', position: const LatLng(10.552710, 76.221619)),
    Waypoint(id: 'chemical_junction', name: 'Chemical Engineering Junction', position: const LatLng(10.552614, 76.223292)),
    Waypoint(id: 'mens_hostel_junction', name: 'Men\'s Hostel Junction', position: const LatLng(10.554442, 76.222121)),
    Waypoint(id: 'hostel_road_mid', name: 'Hostel Road Midpoint', position: const LatLng(10.554400, 76.223500)),
    Waypoint(id: 'canteen_front', name: 'Canteen Entrance', position: const LatLng(10.552333, 76.224332)),
    Waypoint(id: 'civil_dept', name: 'Civil Department', position: const LatLng(10.553940, 76.225157)),
    Waypoint(id: 'library', name: 'GECT Library', position: const LatLng(10.553986, 76.224701)),
    Waypoint(id: 'ladies_amenity', name: 'Ladies Amenity Centre', position: const LatLng(10.553853, 76.224918)),
    Waypoint(id: 'physical_ed', name: 'Physical Education Dept', position: const LatLng(10.553942, 76.224292)),
    Waypoint(id: 'arch_dept', name: 'Architecture Department', position: const LatLng(10.553398, 76.221138)),
  ];

  // Adjacency list: Map<NodeId, List<NeighborId>>
  late final Map<String, List<String>> _graph;

  RoutingService() {
    _graph = {
      'main_gate': ['main_junction'],
      'main_junction': ['main_gate', 'civil_workshop_front', 'hostel_road_mid', 'main_building_front', 'civil_dept'],
      'civil_workshop_front': ['main_junction', 'electrical_junction'],
      'electrical_junction': ['civil_workshop_front', 'workshops_junction'],
      'hostel_road_mid': ['main_junction', 'mens_hostel_junction'],
      'mens_hostel_junction': ['hostel_road_mid', 'cse_ece_junction', 'arch_dept'],
      'main_building_front': ['main_junction', 'auditorium_junction', 'library'],
      'auditorium_junction': ['main_building_front', 'workshops_junction', 'chemical_junction', 'ladies_amenity', 'physical_ed'],
      'workshops_junction': ['auditorium_junction', 'canteen_front', 'electrical_junction'],
      'canteen_front': ['workshops_junction'],
      'chemical_junction': ['auditorium_junction', 'cse_ece_junction'],
      'cse_ece_junction': ['chemical_junction', 'ece_chem_junction', 'mens_hostel_junction'],
      'ece_chem_junction': ['cse_ece_junction', 'arch_dept'],
      'civil_dept': ['main_junction', 'library', 'ladies_amenity'],
      'library': ['civil_dept', 'ladies_amenity', 'main_building_front', 'physical_ed'],
      'ladies_amenity': ['civil_dept', 'library', 'auditorium_junction'],
      'physical_ed': ['library', 'auditorium_junction'],
      'arch_dept': ['ece_chem_junction', 'mens_hostel_junction'],
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
    return _dijkstra(waypoints, _graph, startId, endId);
  }

  // Get complete routing path by constructing a temporary dynamic graph containing start/end connected to nearest segments
  List<LatLng> getFullRoute(LatLng start, LatLng end) {
    if (distance(start, end) < 15.0) {
      return [start, end];
    }

    // 1. Clone base waypoints and graph
    final tempWaypoints = List<Waypoint>.from(waypoints);
    final tempGraph = <String, List<String>>{};
    _graph.forEach((key, val) {
      tempGraph[key] = List<String>.from(val);
    });

    final startId = 'temp_start';
    final endId = 'temp_end';
    
    // 2. Add temporary start and end waypoints
    tempWaypoints.add(Waypoint(id: startId, name: 'Start Point', position: start));
    tempWaypoints.add(Waypoint(id: endId, name: 'Destination Point', position: end));

    // 3. Connect start to the nearest 2 base waypoints (within a threshold of 150m)
    final sortedByStart = List<Waypoint>.from(waypoints)
      ..sort((a, b) => distance(start, a.position).compareTo(distance(start, b.position)));
    
    tempGraph[startId] = [];
    for (int i = 0; i < min(2, sortedByStart.length); i++) {
      final wp = sortedByStart[i];
      if (distance(start, wp.position) < 150.0) {
        tempGraph[startId]!.add(wp.id);
        tempGraph[wp.id] ??= [];
        if (!tempGraph[wp.id]!.contains(startId)) {
          tempGraph[wp.id]!.add(startId);
        }
      }
    }
    if (tempGraph[startId]!.isEmpty) {
      final closest = sortedByStart.first;
      tempGraph[startId]!.add(closest.id);
      tempGraph[closest.id] ??= [];
      tempGraph[closest.id]!.add(startId);
    }

    // 4. Connect end to the nearest 2 base waypoints (within 150m)
    final sortedByEnd = List<Waypoint>.from(waypoints)
      ..sort((a, b) => distance(end, a.position).compareTo(distance(end, b.position)));

    tempGraph[endId] = [];
    for (int i = 0; i < min(2, sortedByEnd.length); i++) {
      final wp = sortedByEnd[i];
      if (distance(end, wp.position) < 150.0) {
        tempGraph[endId]!.add(wp.id);
        tempGraph[wp.id] ??= [];
        if (!tempGraph[wp.id]!.contains(endId)) {
          tempGraph[wp.id]!.add(endId);
        }
      }
    }
    if (tempGraph[endId]!.isEmpty) {
      final closest = sortedByEnd.first;
      tempGraph[endId]!.add(closest.id);
      tempGraph[closest.id] ??= [];
      tempGraph[closest.id]!.add(endId);
    }

    // 5. Run Dijkstra's algorithm on the expanded dynamic graph
    final path = _dijkstra(tempWaypoints, tempGraph, startId, endId);
    if (path.isEmpty) {
      return [start, end];
    }
    return path;
  }

  // Reusable Dijkstra implementation supporting dynamic/temporary graphs
  List<LatLng> _dijkstra(List<Waypoint> wps, Map<String, List<String>> graph, String startId, String endId) {
    if (startId == endId) {
      final wp = wps.firstWhere((w) => w.id == startId);
      return [wp.position];
    }

    final Map<String, double> distances = {};
    final Map<String, String?> previous = {};
    final Set<String> unvisited = {};

    for (var wp in wps) {
      distances[wp.id] = double.infinity;
      previous[wp.id] = null;
      unvisited.add(wp.id);
    }
    distances[startId] = 0.0;

    while (unvisited.isNotEmpty) {
      String? currentId;
      double minDistance = double.infinity;
      for (var id in unvisited) {
        if (distances[id]! < minDistance) {
          minDistance = distances[id]!;
          currentId = id;
        }
      }

      if (currentId == null || currentId == endId) break;

      unvisited.remove(currentId);

      final currentWp = wps.firstWhere((w) => w.id == currentId);
      final neighbors = graph[currentId] ?? [];

      for (var neighborId in neighbors) {
        if (!unvisited.contains(neighborId)) continue;

        final neighborWp = wps.firstWhere((w) => w.id == neighborId);
        final weight = distance(currentWp.position, neighborWp.position);
        final alt = distances[currentId]! + weight;

        if (alt < distances[neighborId]!) {
          distances[neighborId] = alt;
          previous[neighborId] = currentId;
        }
      }
    }

    final List<LatLng> path = [];
    String? current = endId;
    while (current != null) {
      final wp = wps.firstWhere((w) => w.id == current);
      path.insert(0, wp.position);
      current = previous[current];
    }

    if (path.isEmpty || path.first != wps.firstWhere((w) => w.id == startId).position) {
      return [];
    }

    return path;
  }

  // Generate visual instructions for steps
  List<String> getRouteInstructions(List<LatLng> route) {
    if (route.length < 2) return ["You have arrived."];
    List<String> instructions = [];

    for (int i = 0; i < route.length - 1; i++) {
      final p1 = route[i];
      final p2 = route[i + 1];
      final d = distance(p1, p2);

      // Find if we are matching a waypoint
      String fromName = "your location";
      String toName = "destination";

      for (var wp in waypoints) {
        if (distance(p1, wp.position) < 3.0) fromName = wp.name;
        if (distance(p2, wp.position) < 3.0) toName = wp.name;
      }

      if (i == 0) {
        instructions.add("Head towards $toName (${d.toStringAsFixed(0)} m)");
      } else if (i == route.length - 2) {
        instructions.add("Walk the final stretch to your destination (${d.toStringAsFixed(0)} m)");
      } else {
        instructions.add("Walk from $fromName to $toName (${d.toStringAsFixed(0)} m)");
      }
    }
    return instructions;
  }

  List<List<LatLng>> getRoadEdges() {
    final List<List<LatLng>> edges = [];
    _graph.forEach((startId, neighbors) {
      final startWp = waypoints.firstWhere((w) => w.id == startId);
      for (var neighborId in neighbors) {
        final neighborWp = waypoints.firstWhere((w) => w.id == neighborId);
        // Avoid duplicates in dual directions for simplification, or just add both
        edges.add([startWp.position, neighborWp.position]);
      }
    });
    return edges;
  }
}
