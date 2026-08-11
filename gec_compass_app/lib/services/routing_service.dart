import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../models/gate.dart';
import 'path_finder.dart';

class Waypoint {
  final String id;
  final String name;
  final LatLng position;

  Waypoint({required this.id, required this.name, required this.position});
}

class _PQEntry implements Comparable<_PQEntry> {
  final String node;
  final double dist;
  _PQEntry(this.node, this.dist);

  @override
  int compareTo(_PQEntry other) => dist.compareTo(other.dist);
}

class RoadSnapResult {
  final LatLng snappedPoint;
  final String nodeA;
  final String nodeB;
  final double distanceToRoad;

  RoadSnapResult({
    required this.snappedPoint,
    required this.nodeA,
    required this.nodeB,
    required this.distanceToRoad,
  });
}

class RouteResult {
  final List<LatLng> fullPath;
  final List<LatLng> startAccessPath;
  final List<LatLng> roadPath;
  final List<LatLng> endAccessPath;
  final List<String> instructions;

  RouteResult({
    required this.fullPath,
    required this.startAccessPath,
    required this.roadPath,
    required this.endAccessPath,
    required this.instructions,
  });
}

class RoutingService {
  // Dense waypoint network for GEC Thrissur campus road & footpath network
  // Placed with high spatial resolution along all paved roads and pedestrian walkways
  final List<Waypoint> waypoints = [
    // === Campus Entrance Gates ===
    Waypoint(id: 'gate_main', name: 'Main Gate Entrance', position: const LatLng(10.5541214, 76.2264419)),
    Waypoint(id: 'gate_south', name: 'South Gate Entrance (Canteen)', position: const LatLng(10.5520947, 76.2241280)),
    Waypoint(id: 'gate_east', name: 'East Gate Entrance (Electrical)', position: const LatLng(10.5531511, 76.2264930)),

    // === Main Gate & Entry Avenue ===
    Waypoint(id: 'main_gate', name: 'Main Gate Entrance', position: const LatLng(10.554094, 76.226412)),
    Waypoint(id: 'main_gate_curve1', name: 'Main Gate Curve 1', position: const LatLng(10.554120, 76.226150)),
    Waypoint(id: 'main_gate_curve2', name: 'Main Gate Curve 2', position: const LatLng(10.554160, 76.225900)),
    Waypoint(id: 'main_junction', name: 'Main Junction (Amphitheatre)', position: const LatLng(10.554200, 76.225600)),
    Waypoint(id: 'bus_stop_road', name: 'Campus Bus Stop Path', position: const LatLng(10.554010, 76.226250)),

    // === Main Junction to Main Building (Central Avenue) ===
    Waypoint(id: 'main_road_w1', name: 'Central Avenue 1', position: const LatLng(10.554280, 76.225300)),
    Waypoint(id: 'main_road_w2', name: 'Central Avenue 2', position: const LatLng(10.554350, 76.225000)),
    Waypoint(id: 'main_building_front', name: 'Main Building Front Plaza', position: const LatLng(10.554418, 76.224668)),
    Waypoint(id: 'admin_block_path', name: 'Admin Office Walkway', position: const LatLng(10.554520, 76.224800)),

    // === Main Building to Auditorium & Library (South Avenue) ===
    Waypoint(id: 'main_aud_road1', name: 'South Road 1', position: const LatLng(10.554100, 76.224650)),
    Waypoint(id: 'library_junction', name: 'Central Library Junction', position: const LatLng(10.553850, 76.224610)),
    Waypoint(id: 'auditorium_junction', name: 'Auditorium Junction (Cafeteria)', position: const LatLng(10.553595, 76.224567)),

    // === Auditorium to Workshops & Canteen ===
    Waypoint(id: 'aud_workshop_road1', name: 'Aud-Workshop Road 1', position: const LatLng(10.553250, 76.224600)),
    Waypoint(id: 'workshops_junction', name: 'Workshops Road Junction', position: const LatLng(10.552883, 76.224626)),
    Waypoint(id: 'canteen_front', name: 'Central Canteen Entrance', position: const LatLng(10.552333, 76.224332)),
    Waypoint(id: 'coop_store_road', name: 'Cooperative Store Walkway', position: const LatLng(10.552550, 76.224450)),

    // === Workshops East to Electrical & Mechanical ===
    Waypoint(id: 'workshop_east_road1', name: 'Workshop East Road 1', position: const LatLng(10.552900, 76.225000)),
    Waypoint(id: 'workshop_east_road2', name: 'Workshop East Road 2', position: const LatLng(10.552950, 76.225450)),
    Waypoint(id: 'electrical_junction', name: 'Electrical Lab Junction', position: const LatLng(10.553002, 76.225915)),
    Waypoint(id: 'mech_workshop_path', name: 'Mechanical Workshop Path', position: const LatLng(10.552780, 76.225200)),

    // === Electrical Workshop to Civil Workshop & PG Block ===
    Waypoint(id: 'elec_civil_road1', name: 'Elec-Civil Road 1', position: const LatLng(10.553350, 76.225890)),
    Waypoint(id: 'civil_workshop_front', name: 'Civil Workshop Front', position: const LatLng(10.553708, 76.225861)),
    Waypoint(id: 'pg_block_path', name: 'PG Block & Research Lab Access', position: const LatLng(10.553550, 76.226100)),

    // === Civil Workshop to Main Junction (North-East road) ===
    Waypoint(id: 'civil_main_road1', name: 'Civil-Main Road 1', position: const LatLng(10.553900, 76.225750)),
    Waypoint(id: 'civil_dept_entrance', name: 'Civil Dept Building Entrance', position: const LatLng(10.553800, 76.225600)),

    // === Western Campus Road (Auditorium -> Chemical -> CSE -> ECE) ===
    Waypoint(id: 'west_road1', name: 'Western Campus Road 1', position: const LatLng(10.553500, 76.224200)),
    Waypoint(id: 'west_road2', name: 'Western Campus Road 2', position: const LatLng(10.553350, 76.223800)),
    Waypoint(id: 'chemical_junction', name: 'Chemical Eng. Junction', position: const LatLng(10.553100, 76.223400)),
    Waypoint(id: 'west_road3', name: 'Western Campus Road 3', position: const LatLng(10.552900, 76.223000)),
    Waypoint(id: 'west_road4', name: 'Western Campus Road 4', position: const LatLng(10.552800, 76.222600)),
    Waypoint(id: 'cse_ece_junction', name: 'CS & Production Dept Junction', position: const LatLng(10.552740, 76.222020)),
    Waypoint(id: 'ece_chem_junction', name: 'ECE Dept Entrance Junction', position: const LatLng(10.552710, 76.221619)),
    Waypoint(id: 'mca_block_road', name: 'MCA Department Walkway', position: const LatLng(10.552650, 76.221200)),

    // === Hostel Road Loop (Main Junction -> Men's Hostels -> Ladies Hostels) ===
    Waypoint(id: 'hostel_road_start', name: 'Hostel Road Start', position: const LatLng(10.554300, 76.225200)),
    Waypoint(id: 'hostel_road_mid', name: 'Hostel Road Midpoint', position: const LatLng(10.554400, 76.224500)),
    Waypoint(id: 'hostel_road_w1', name: 'Hostel Road West 1', position: const LatLng(10.554430, 76.223800)),
    Waypoint(id: 'hostel_road_w2', name: 'Hostel Road West 2', position: const LatLng(10.554440, 76.223100)),
    Waypoint(id: 'mens_hostel_junction', name: "Men's Hostel Main Junction", position: const LatLng(10.554442, 76.222121)),
    Waypoint(id: 'mh_block_a_road', name: "Men's Hostel Block A Access", position: const LatLng(10.554650, 76.222100)),
    Waypoint(id: 'lh_junction', name: "Ladies Hostel Junction", position: const LatLng(10.554800, 76.221500)),

    // === Hostel to CSE South Connectors ===
    Waypoint(id: 'hostel_cse_road1', name: 'Hostel-CSE Road 1', position: const LatLng(10.554100, 76.222100)),
    Waypoint(id: 'hostel_cse_road2', name: 'Hostel-CSE Road 2', position: const LatLng(10.553700, 76.222080)),
    Waypoint(id: 'hostel_cse_road3', name: 'Hostel-CSE Road 3', position: const LatLng(10.553200, 76.222050)),

    // === Chemical to Workshops Cross-Road ===
    Waypoint(id: 'chem_workshop_road1', name: 'Chemical-Workshop Road 1', position: const LatLng(10.552950, 76.223700)),
    Waypoint(id: 'chem_workshop_road2', name: 'Chemical-Workshop Road 2', position: const LatLng(10.552900, 76.224100)),

    // === Upper Campus Road (Northern Perimeter & Sports Ground) ===
    Waypoint(id: 'upper_road1', name: 'Upper Campus Road 1', position: const LatLng(10.554600, 76.224400)),
    Waypoint(id: 'upper_road2', name: 'Upper Campus Road 2', position: const LatLng(10.554700, 76.224000)),
    Waypoint(id: 'upper_road3', name: 'Upper Campus Road 3', position: const LatLng(10.554750, 76.223500)),
    Waypoint(id: 'sports_ground_road', name: 'Sports Ground Entrance Path', position: const LatLng(10.554900, 76.222800)),
    Waypoint(id: 'indoor_court_road', name: 'Indoor Court Road', position: const LatLng(10.555050, 76.222200)),

    // === East Inner Ring Roads ===
    Waypoint(id: 'inner_road1', name: 'East Inner Road 1', position: const LatLng(10.553500, 76.225500)),
    Waypoint(id: 'inner_road2', name: 'East Inner Road 2', position: const LatLng(10.553800, 76.225400)),
  ];

  late final Map<String, List<String>> _graph;
  late final Map<String, Waypoint> _waypointMap;

  List<String> _lastParsedInstructions = [];
  List<LatLng> _lastStepManeuverCoords = [];

  static final List<Gate> defaultGates = [
    Gate(id: 'gate_main', name: 'Main Gate Entrance', latitude: 10.5541214, longitude: 76.2264419, graphNodeId: 'gate_main'),
    Gate(id: 'gate_south', name: 'South Gate Entrance (Canteen)', latitude: 10.5520947, longitude: 76.2241280, graphNodeId: 'gate_south'),
    Gate(id: 'gate_east', name: 'East Gate Entrance (Electrical)', latitude: 10.5531511, longitude: 76.2264930, graphNodeId: 'gate_east'),
  ];

  RoutingService() {
    _waypointMap = {for (final w in waypoints) w.id: w};
    _buildSymmetricGraph();
  }

  Graph buildGraph() {
    final g = Graph();
    for (final wp in waypoints) {
      g.addNode(wp.id, wp.position);
    }
    _graph.forEach((fromId, neighbors) {
      final wpFrom = _waypointMap[fromId];
      if (wpFrom != null) {
        for (final toId in neighbors) {
          final wpTo = _waypointMap[toId];
          if (wpTo != null) {
            final dist = distance(wpFrom.position, wpTo.position);
            g.addEdge(fromId, toId, dist);
          }
        }
      }
    });
    return g;
  }

  List<LatLng> findPathWithGates(LatLng start, LatLng end, {List<Gate>? customGates}) {
    final allGates = [...defaultGates, ...?customGates];
    final pf = PathFinder(buildGraph(), allGates);
    return pf.findPath(start, end);
  }

  Map<String, List<String>> get graph => Map.unmodifiable(_graph);

  void _buildSymmetricGraph() {
    final rawGraph = <String, List<String>>{
      // Campus Entrance Gates & Outer Perimeter Links
      'gate_main': ['main_gate', 'main_gate_curve1', 'bus_stop_road', 'gate_east'],
      'gate_east': ['electrical_junction', 'pg_block_path', 'elec_civil_road1', 'gate_main', 'gate_south'],
      'gate_south': ['canteen_front', 'coop_store_road', 'workshops_junction', 'gate_east'],

      // Main Gate entry & bus stop
      'main_gate': ['gate_main', 'main_gate_curve1', 'bus_stop_road'],
      'bus_stop_road': ['main_gate', 'main_gate_curve1'],
      'main_gate_curve1': ['main_gate', 'main_gate_curve2', 'bus_stop_road'],
      'main_gate_curve2': ['main_gate_curve1', 'main_junction'],

      // Main Junction hub
      'main_junction': ['main_gate_curve2', 'main_road_w1', 'civil_main_road1', 'hostel_road_start'],

      // Central Avenue (Main Building)
      'main_road_w1': ['main_junction', 'main_road_w2'],
      'main_road_w2': ['main_road_w1', 'main_building_front', 'admin_block_path'],
      'admin_block_path': ['main_road_w2', 'main_building_front'],
      'main_building_front': ['main_road_w2', 'main_aud_road1', 'upper_road1', 'hostel_road_mid', 'admin_block_path'],

      // South Avenue (Library & Auditorium)
      'main_aud_road1': ['main_building_front', 'library_junction'],
      'library_junction': ['main_aud_road1', 'auditorium_junction'],
      'auditorium_junction': ['library_junction', 'aud_workshop_road1', 'west_road1'],

      // Auditorium to Workshops & Canteen
      'aud_workshop_road1': ['auditorium_junction', 'workshops_junction', 'coop_store_road'],
      'coop_store_road': ['aud_workshop_road1', 'workshops_junction'],
      'workshops_junction': ['aud_workshop_road1', 'canteen_front', 'workshop_east_road1', 'chem_workshop_road2', 'coop_store_road'],
      'canteen_front': ['workshops_junction'],

      // Workshop East loop
      'workshop_east_road1': ['workshops_junction', 'workshop_east_road2', 'mech_workshop_path'],
      'mech_workshop_path': ['workshop_east_road1', 'workshop_east_road2'],
      'workshop_east_road2': ['workshop_east_road1', 'electrical_junction', 'mech_workshop_path'],

      // Electrical & Civil East Ring
      'electrical_junction': ['workshop_east_road2', 'elec_civil_road1', 'inner_road1'],
      'elec_civil_road1': ['electrical_junction', 'civil_workshop_front', 'pg_block_path'],
      'pg_block_path': ['elec_civil_road1', 'civil_workshop_front'],
      'civil_workshop_front': ['elec_civil_road1', 'civil_main_road1', 'pg_block_path'],
      'civil_main_road1': ['civil_workshop_front', 'main_junction', 'inner_road2', 'civil_dept_entrance'],
      'civil_dept_entrance': ['civil_main_road1', 'main_junction'],

      // Western Campus (CSE / ECE / Chemical / MCA)
      'west_road1': ['auditorium_junction', 'west_road2'],
      'west_road2': ['west_road1', 'chemical_junction'],
      'chemical_junction': ['west_road2', 'west_road3', 'chem_workshop_road1'],
      'west_road3': ['chemical_junction', 'west_road4'],
      'west_road4': ['west_road3', 'cse_ece_junction'],
      'cse_ece_junction': ['west_road4', 'ece_chem_junction', 'hostel_cse_road3'],
      'ece_chem_junction': ['cse_ece_junction', 'mca_block_road'],
      'mca_block_road': ['ece_chem_junction'],

      // Hostel Road Loop
      'hostel_road_start': ['main_junction', 'hostel_road_mid'],
      'hostel_road_mid': ['hostel_road_start', 'hostel_road_w1', 'main_building_front'],
      'hostel_road_w1': ['hostel_road_mid', 'hostel_road_w2', 'upper_road3'],
      'hostel_road_w2': ['hostel_road_w1', 'mens_hostel_junction'],
      'mens_hostel_junction': ['hostel_road_w2', 'hostel_cse_road1', 'mh_block_a_road', 'lh_junction'],
      'mh_block_a_road': ['mens_hostel_junction', 'lh_junction'],
      'lh_junction': ['mens_hostel_junction', 'mh_block_a_road'],

      // Hostel to CSE South
      'hostel_cse_road1': ['mens_hostel_junction', 'hostel_cse_road2'],
      'hostel_cse_road2': ['hostel_cse_road1', 'hostel_cse_road3'],
      'hostel_cse_road3': ['hostel_cse_road2', 'cse_ece_junction'],

      // Chemical to Workshops Cross-road
      'chem_workshop_road1': ['chemical_junction', 'chem_workshop_road2'],
      'chem_workshop_road2': ['chem_workshop_road1', 'workshops_junction'],

      // Upper Campus & Sports Complex
      'upper_road1': ['main_building_front', 'upper_road2'],
      'upper_road2': ['upper_road1', 'upper_road3'],
      'upper_road3': ['upper_road2', 'hostel_road_w1', 'sports_ground_road'],
      'sports_ground_road': ['upper_road3', 'indoor_court_road'],
      'indoor_court_road': ['sports_ground_road', 'lh_junction'],

      // Inner East Road
      'inner_road1': ['electrical_junction', 'inner_road2'],
      'inner_road2': ['inner_road1', 'civil_main_road1'],
    };

    _graph = {};
    rawGraph.forEach((node, neighbors) {
      _graph.putIfAbsent(node, () => <String>[]);
      for (final nbr in neighbors) {
        if (!_graph[node]!.contains(nbr)) {
          _graph[node]!.add(nbr);
        }
        _graph.putIfAbsent(nbr, () => <String>[]);
        if (!_graph[nbr]!.contains(node)) {
          _graph[nbr]!.add(node);
        }
      }
    });
  }

  // Calculate Haversine distance in meters between two coordinates
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

  // Calculate bearing in degrees (0 to 360)
  double calculateBearing(LatLng a, LatLng b) {
    final lat1 = a.latitude * (pi / 180.0);
    final lat2 = b.latitude * (pi / 180.0);
    final dLon = (b.longitude - a.longitude) * (pi / 180.0);

    final y = sin(dLon) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    final brng = atan2(y, x) * (180.0 / pi);
    return (brng + 360.0) % 360.0;
  }

  /// Perpendicular projection of point P onto road edge segment A-B
  RoadSnapResult snapToNearestGraphEdge(LatLng point) {
    double minDistance = double.infinity;
    LatLng bestSnapped = point;
    String bestNodeA = waypoints.first.id;
    String bestNodeB = waypoints.first.id;

    final double latRad = point.latitude * (pi / 180.0);
    final double mPerLat = 111139.0;
    final double mPerLng = 111139.0 * cos(latRad);

    final visitedEdges = <String>{};

    for (final nodeA in _graph.keys) {
      final wpA = _waypointMap[nodeA];
      if (wpA == null) continue;

      for (final nodeB in _graph[nodeA]!) {
        final edgeKey = nodeA.compareTo(nodeB) < 0 ? '${nodeA}_$nodeB' : '${nodeB}_$nodeA';
        if (visitedEdges.contains(edgeKey)) continue;
        visitedEdges.add(edgeKey);

        final wpB = _waypointMap[nodeB];
        if (wpB == null) continue;

        final double px = (point.longitude - wpA.position.longitude) * mPerLng;
        final double py = (point.latitude - wpA.position.latitude) * mPerLat;

        final double bx = (wpB.position.longitude - wpA.position.longitude) * mPerLng;
        final double by = (wpB.position.latitude - wpA.position.latitude) * mPerLat;

        final double segmentLenSq = bx * bx + by * by;
        double t = 0.0;
        if (segmentLenSq > 0) {
          t = (px * bx + py * by) / segmentLenSq;
          t = t.clamp(0.0, 1.0);
        }

        final double projX = t * bx;
        final double projY = t * by;
        final double distSq = (px - projX) * (px - projX) + (py - projY) * (py - projY);
        final double dist = sqrt(distSq);

        if (dist < minDistance) {
          minDistance = dist;
          final double snappedLat = wpA.position.latitude + (projY / mPerLat);
          final double snappedLng = wpA.position.longitude + (projX / mPerLng);
          bestSnapped = LatLng(snappedLat, snappedLng);
          bestNodeA = nodeA;
          bestNodeB = nodeB;
        }
      }
    }

    return RoadSnapResult(
      snappedPoint: bestSnapped,
      nodeA: bestNodeA,
      nodeB: bestNodeB,
      distanceToRoad: minDistance,
    );
  }

  // Find closest waypoint to a point
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

  // Dijkstra algorithm to find shortest road path between two waypoint IDs
  List<LatLng> getRouteBetweenWaypoints(String startId, String endId) {
    if (startId == endId) {
      final wp = _waypointMap[startId];
      return wp != null ? [wp.position] : [];
    }

    final Map<String, double> distances = {startId: 0.0};
    final Map<String, String?> previous = {};
    final List<_PQEntry> pq = [_PQEntry(startId, 0.0)];

    while (pq.isNotEmpty) {
      final current = pq.removeAt(0);
      final currentId = current.node;
      final currentDist = current.dist;

      if (currentDist > (distances[currentId] ?? double.infinity)) continue;
      if (currentId == endId) break;

      final currentWp = _waypointMap[currentId];
      if (currentWp == null) continue;
      final neighbors = _graph[currentId] ?? [];

      for (final neighborId in neighbors) {
        final neighborWp = _waypointMap[neighborId];
        if (neighborWp == null) continue;

        final weight = distance(currentWp.position, neighborWp.position);
        final alt = currentDist + weight;

        if (alt < (distances[neighborId] ?? double.infinity)) {
          distances[neighborId] = alt;
          previous[neighborId] = currentId;
          
          final entry = _PQEntry(neighborId, alt);
          // O(log N) binary insertion instead of O(N) linear scan
          int lo = 0, hi = pq.length;
          while (lo < hi) {
            final mid = (lo + hi) >> 1;
            if (pq[mid].dist <= alt) {
              lo = mid + 1;
            } else {
              hi = mid;
            }
          }
          pq.insert(lo, entry);
        }
      }
    }

    if (previous[endId] == null && startId != endId) return [];

    final List<LatLng> path = [];
    String? current = endId;
    while (current != null) {
      final wp = _waypointMap[current];
      if (wp != null) {
        path.insert(0, wp.position);
      }
      current = previous[current];
    }

    if (path.isEmpty || path.first != _waypointMap[startId]?.position) {
      return [];
    }

    return path;
  }

  /// Online routing fetcher with primary + secondary server fallback
  Future<List<LatLng>?> _tryOnlineOSRM(LatLng start, LatLng end) async {
    final urls = [
      'https://router.project-osrm.org/route/v1/foot/'
          '${start.longitude},${start.latitude};'
          '${end.longitude},${end.latitude}'
          '?geometries=geojson&overview=full&steps=true',
      'https://routing.openstreetmap.de/routed-foot/route/v1/foot/'
          '${start.longitude},${start.latitude};'
          '${end.longitude},${end.latitude}'
          '?geometries=geojson&overview=full&steps=true',
    ];

    for (final urlStr in urls) {
      try {
        final url = Uri.parse(urlStr);
        final response = await http.get(url).timeout(const Duration(seconds: 3));
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['code'] == 'Ok' && data['routes'] != null && data['routes'].isNotEmpty) {
            final route = data['routes'][0];
            final geometry = route['geometry'];
            if (geometry != null && geometry['coordinates'] != null) {
              final List<dynamic> coords = geometry['coordinates'];
              final List<LatLng> path = coords.map((c) {
                final double lon = c[0] is int ? (c[0] as int).toDouble() : c[0] as double;
                final double lat = c[1] is int ? (c[1] as int).toDouble() : c[1] as double;
                return LatLng(lat, lon);
              }).toList();

              if (path.length >= 2) {
                final legs = route['legs'] as List<dynamic>?;
                if (legs != null && legs.isNotEmpty) {
                  final steps = legs[0]['steps'] as List<dynamic>?;
                  if (steps != null) {
                    _lastParsedInstructions = _parseOSRMSteps(steps);
                  }
                }
                return path;
              }
            }
          }
        }
      } catch (e) {
        debugPrint("Online OSRM endpoint ($urlStr) failed/skipped: $e");
      }
    }
    return null;
  }

  /// Get complete route decomposed into access walkways + paved road path
  Future<RouteResult> getDetailedRoute(LatLng start, LatLng end) async {
    _lastParsedInstructions.clear();
    _lastStepManeuverCoords.clear();

    final startSnap = snapToNearestGraphEdge(start);
    final endSnap = snapToNearestGraphEdge(end);

    final bool startIsOutside = startSnap.distanceToRoad > 30;
    final bool endIsOutside = endSnap.distanceToRoad > 30;

    // 1. Boundary crossing routing (forces passage through optimal gates)
    if (startIsOutside != endIsOutside) {
      final gateIds = ['gate_main', 'gate_south', 'gate_east'];
      String bestGateId = 'gate_main';
      double minTotalCost = double.infinity;

      // Optimal gate selection: pick the gate with shortest TOTAL path cost
      // (external→gate distance + gate→internal campus graph distance)
      final LatLng externalPoint = startIsOutside ? start : end;
      final LatLng internalPoint = startIsOutside ? end : start;
      final internalSnap = snapToNearestGraphEdge(internalPoint);

      for (final gateId in gateIds) {
        final gateWp = _waypointMap[gateId];
        if (gateWp != null) {
          // Cost leg 1: external point to gate (straight-line estimate)
          final externalDist = distance(externalPoint, gateWp.position);

          // Cost leg 2: gate to internal destination via campus graph (Dijkstra)
          double campusDist = double.infinity;
          for (final snapNode in [internalSnap.nodeA, internalSnap.nodeB]) {
            final path = getRouteBetweenWaypoints(gateId, snapNode);
            if (path.isNotEmpty) {
              final d = getRouteDistance(path) + distance(internalPoint, internalSnap.snappedPoint);
              if (d < campusDist) campusDist = d;
            }
          }
          if (campusDist == double.infinity) campusDist = distance(gateWp.position, internalPoint);

          final totalCost = externalDist + campusDist;
          if (totalCost < minTotalCost) {
            minTotalCost = totalCost;
            bestGateId = gateId;
          }
        }
      }

      final gatePos = _waypointMap[bestGateId]!.position;

      if (startIsOutside && !endIsOutside) {
        final onlinePath = await _tryOnlineOSRM(start, gatePos);
        if (onlinePath != null && onlinePath.isNotEmpty) {
          final campusRoute = await getDetailedRoute(gatePos, end);
          final fullPath = <LatLng>[...onlinePath, ...campusRoute.fullPath.skip(1)];
          final instructions = generateOfflineInstructions(fullPath);
          _lastParsedInstructions = instructions;
          return RouteResult(
            fullPath: fullPath,
            startAccessPath: [start, onlinePath.first],
            roadPath: fullPath,
            endAccessPath: campusRoute.endAccessPath,
            instructions: instructions,
          );
        }
      } else if (!startIsOutside && endIsOutside) {
        final campusRoute = await getDetailedRoute(start, gatePos);
        final onlinePath = await _tryOnlineOSRM(gatePos, end);
        if (onlinePath != null && onlinePath.isNotEmpty) {
          final fullPath = <LatLng>[...campusRoute.fullPath, ...onlinePath.skip(1)];
          final instructions = generateOfflineInstructions(fullPath);
          _lastParsedInstructions = instructions;
          return RouteResult(
            fullPath: fullPath,
            startAccessPath: campusRoute.startAccessPath,
            roadPath: fullPath,
            endAccessPath: [onlinePath.last, end],
            instructions: instructions,
          );
        }
      }
    }

    // 2. Try Standard OSRM (for purely internal or purely external routes)
    final onlinePath = await _tryOnlineOSRM(start, end);
    if (onlinePath != null && onlinePath.length >= 2) {
      final roadStart = onlinePath.first;
      final roadEnd = onlinePath.last;

      List<LatLng> startAccess = [];
      if (distance(start, roadStart) > 2.0) {
        startAccess = [start, roadStart];
      }

      List<LatLng> endAccess = [];
      if (distance(roadEnd, end) > 2.0) {
        endAccess = [roadEnd, end];
      }

      final List<LatLng> fullPath = [];
      if (startAccess.isNotEmpty) fullPath.add(start);
      fullPath.addAll(onlinePath);
      if (endAccess.isNotEmpty && distance(fullPath.last, end) > 1.0) fullPath.add(end);

      return RouteResult(
        fullPath: fullPath,
        startAccessPath: startAccess,
        roadPath: onlinePath,
        endAccessPath: endAccess,
        instructions: _lastParsedInstructions.isNotEmpty
            ? _lastParsedInstructions
            : generateOfflineInstructions(fullPath),
      );
    }

    // 3. Fallback to Offline Campus Graph (if OSRM fails or has no paths)
    final candidateStartNodes = [startSnap.nodeA, startSnap.nodeB];
    final candidateEndNodes = [endSnap.nodeA, endSnap.nodeB];

    List<LatLng> bestRoadPath = [];
    double minTotalDist = double.infinity;

    for (final sNode in candidateStartNodes) {
      for (final eNode in candidateEndNodes) {
        final subPath = getRouteBetweenWaypoints(sNode, eNode);
        if (subPath.isNotEmpty || sNode == eNode) {
          final List<LatLng> candidate = [startSnap.snappedPoint];
          if (subPath.isNotEmpty) candidate.addAll(subPath);
          candidate.add(endSnap.snappedPoint);

          final candidateDist = getRouteDistance(candidate);
          if (candidateDist < minTotalDist) {
            minTotalDist = candidateDist;
            bestRoadPath = candidate;
          }
        }
      }
    }

    if (bestRoadPath.isNotEmpty) {
      List<LatLng> startAccess = [];
      if (distance(start, bestRoadPath.first) > 1.5) {
        startAccess = [start, bestRoadPath.first];
      }

      List<LatLng> endAccess = [];
      if (distance(bestRoadPath.last, end) > 1.5) {
        endAccess = [bestRoadPath.last, end];
      }

      final List<LatLng> fullPath = [];
      if (startAccess.isNotEmpty) fullPath.add(start);
      fullPath.addAll(bestRoadPath);
      if (endAccess.isNotEmpty && distance(fullPath.last, end) > 0.5) fullPath.add(end);

      final instructions = generateOfflineInstructions(fullPath);
      _lastParsedInstructions = instructions;

      return RouteResult(
        fullPath: fullPath,
        startAccessPath: startAccess,
        roadPath: bestRoadPath,
        endAccessPath: endAccess,
        instructions: instructions,
      );
    }

    final fallbackPath = [start, end];
    return RouteResult(
      fullPath: fallbackPath,
      startAccessPath: [],
      roadPath: fallbackPath,
      endAccessPath: [],
      instructions: ['Walk directly to destination'],
    );
  }

  // Backward compatible getFullRoute
  Future<List<LatLng>> getFullRoute(LatLng start, LatLng end) async {
    final result = await getDetailedRoute(start, end);
    return result.fullPath;
  }

  List<String> generateOfflineInstructions(List<LatLng> path) {
    if (path.length < 2) return ['Arrive at destination'];

    final gateMainPos = const LatLng(10.5541214, 76.2264419);
    final gateSouthPos = const LatLng(10.5520947, 76.2241280);
    final gateEastPos = const LatLng(10.5531511, 76.2264930);

    final List<String> instructions = [];
    instructions.add('Start walking along campus route');

    for (int i = 0; i < path.length - 2; i++) {
      final midPoint = path[i + 1];

      // Check proximity to entrance gates
      if (distance(midPoint, gateMainPos) < 18) {
        instructions.add('Pass through Main Gate Entrance');
        continue;
      } else if (distance(midPoint, gateSouthPos) < 18) {
        instructions.add('Pass through South Gate Entrance (Canteen Side)');
        continue;
      } else if (distance(midPoint, gateEastPos) < 18) {
        instructions.add('Pass through East Gate Entrance (Electrical Side)');
        continue;
      }

      final b1 = calculateBearing(path[i], path[i + 1]);
      final b2 = calculateBearing(path[i + 1], path[i + 2]);
      final dist = distance(path[i + 1], path[i + 2]).round();

      if (dist < 3) continue; // skip micro-nodes

      double turnAngle = b2 - b1;
      while (turnAngle > 180) {
        turnAngle -= 360;
      }
      while (turnAngle < -180) {
        turnAngle += 360;
      }

      if (turnAngle > 45 && turnAngle <= 135) {
        instructions.add('In ${dist}m, turn right');
      } else if (turnAngle > 135) {
        instructions.add('In ${dist}m, make a sharp right turn');
      } else if (turnAngle < -45 && turnAngle >= -135) {
        instructions.add('In ${dist}m, turn left');
      } else if (turnAngle < -135) {
        instructions.add('In ${dist}m, make a sharp left turn');
      } else if (turnAngle.abs() > 22) {
        final dir = turnAngle > 0 ? 'right' : 'left';
        instructions.add('In ${dist}m, turn slight $dir');
      } else {
        instructions.add('In ${dist}m, continue straight');
      }
    }

    instructions.add('Arrive at destination');
    return instructions;
  }

  List<String> get lastInstructions => List.unmodifiable(_lastParsedInstructions);

  List<String> _parseOSRMSteps(List<dynamic> stepsJson) {
    List<String> instructions = [];
    _lastStepManeuverCoords = [];
    for (var step in stepsJson) {
      final distance = step['distance'] is int
          ? (step['distance'] as int).toDouble()
          : step['distance'] as double? ?? 0.0;
      final name = step['name'] as String? ?? '';
      final maneuver = step['maneuver'] as Map<dynamic, dynamic>?;

      if (maneuver == null) continue;

      final type = maneuver['type'] as String? ?? '';
      final modifier = maneuver['modifier'] as String? ?? '';

      String action = '';
      switch (type) {
        case 'depart':
          action = 'Start walking';
          break;
        case 'arrive':
          action = 'Arrive at destination';
          break;
        case 'turn':
          if (modifier.contains('left')) {
            action = 'Turn left';
          } else if (modifier.contains('right')) {
            action = 'Turn right';
          } else {
            action = 'Turn';
          }
          break;
        case 'new name':
          action = 'Continue onto';
          break;
        case 'continue':
          action = 'Continue';
          break;
        default:
          action = 'Walk';
          break;
      }

      String road = name.isNotEmpty ? ' on $name' : '';
      String distStr = distance > 0 ? ' (${distance.toStringAsFixed(0)} m)' : '';
      instructions.add("$action$road$distStr");
      // Capture the maneuver geographic coordinate for index mapping
      final loc = maneuver['location'] as List<dynamic>?;
      if (loc != null && loc.length >= 2) {
        final mLon = loc[0] is int ? (loc[0] as int).toDouble() : loc[0] as double;
        final mLat = loc[1] is int ? (loc[1] as int).toDouble() : loc[1] as double;
        _lastStepManeuverCoords.add(LatLng(mLat, mLon));
      } else {
        _lastStepManeuverCoords.add(const LatLng(0, 0));
      }
    }
    return instructions;
  }

  double getRouteDistance(List<LatLng> route) {
    double total = 0;
    for (int i = 0; i < route.length - 1; i++) {
      total += distance(route[i], route[i + 1]);
    }
    return total;
  }

  double getEstimatedWalkingTime(List<LatLng> route) {
    return getRouteDistance(route) / 83.3;
  }

  List<String> getRouteInstructions(List<LatLng> route) {
    if (_lastParsedInstructions.isNotEmpty) {
      return _lastParsedInstructions;
    }
    return generateOfflineInstructions(route);
  }

  List<Map<String, dynamic>> getRouteInstructionsWithIndices(List<LatLng> route) {
    if (route.length < 2) {
      return [
        {'text': "You have arrived.", 'index': 0}
      ];
    }
    List<Map<String, dynamic>> result = [];

    if (_lastParsedInstructions.isNotEmpty) {
      if (_lastStepManeuverCoords.isNotEmpty && _lastStepManeuverCoords.length == _lastParsedInstructions.length) {
        // Map each instruction to its actual geographic location on the route
        for (int k = 0; k < _lastParsedInstructions.length; k++) {
          final maneuverPos = _lastStepManeuverCoords[k];
          int bestIdx = 0;
          double bestDist = double.infinity;
          for (int j = 0; j < route.length; j++) {
            final d = distance(maneuverPos, route[j]);
            if (d < bestDist) {
              bestDist = d;
              bestIdx = j;
            }
          }
          result.add({
            'text': _lastParsedInstructions[k],
            'index': bestIdx.clamp(0, route.length - 1)
          });
        }
      } else {
        // Fallback: evenly spread if no maneuver coordinates available
        for (int k = 0; k < _lastParsedInstructions.length; k++) {
          int idx = (k * route.length / _lastParsedInstructions.length).round();
          result.add({
            'text': _lastParsedInstructions[k],
            'index': idx.clamp(0, route.length - 1)
          });
        }
      }
      return result;
    }

    final offline = generateOfflineInstructions(route);
    for (int k = 0; k < offline.length; k++) {
      int idx = (k * route.length / offline.length).round();
      result.add({
        'text': offline[k],
        'index': idx.clamp(0, route.length - 1),
      });
    }
    return result;
  }

  static LatLng snapToNearestSegment(LatLng point, List<LatLng> polyline, {double maxDistanceMeters = 12.0}) {
    if (polyline.length < 2) return point;

    double minDistance = double.infinity;
    LatLng closestPoint = point;

    for (int i = 0; i < polyline.length - 1; i++) {
      final a = polyline[i];
      final b = polyline[i + 1];

      final double latRad = point.latitude * (pi / 180.0);
      final double mPerLat = 111139.0;
      final double mPerLng = 111139.0 * cos(latRad);

      final double px = (point.longitude - a.longitude) * mPerLng;
      final double py = (point.latitude - a.latitude) * mPerLat;

      final double bx = (b.longitude - a.longitude) * mPerLng;
      final double by = (b.latitude - a.latitude) * mPerLat;

      final double segmentLenSq = bx * bx + by * by;
      double t = 0.0;
      if (segmentLenSq > 0) {
        t = (px * bx + py * by) / segmentLenSq;
        t = t.clamp(0.0, 1.0);
      }

      final double projX = t * bx;
      final double projY = t * by;

      final double distSq = (px - projX) * (px - projX) + (py - projY) * (py - projY);
      final double dist = sqrt(distSq);

      if (dist < minDistance) {
        minDistance = dist;
        final double snappedLat = a.latitude + (projY / mPerLat);
        final double snappedLng = a.longitude + (projX / mPerLng);
        closestPoint = LatLng(snappedLat, snappedLng);
      }
    }

    if (minDistance <= maxDistanceMeters) {
      return closestPoint;
    }
    return point;
  }
}


