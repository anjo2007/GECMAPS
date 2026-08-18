import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../models/building.dart';

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
  final String? gateClosureNotice;
  final String? bypassedClosedGateName;
  final String? activeGateName;

  RouteResult({
    required this.fullPath,
    required this.startAccessPath,
    required this.roadPath,
    required this.endAccessPath,
    required this.instructions,
    this.gateClosureNotice,
    this.bypassedClosedGateName,
    this.activeGateName,
  });

  double get distanceMeters {
    double dist = 0;
    for (int i = 0; i < fullPath.length - 1; i++) {
      dist += const Distance().as(LengthUnit.Meter, fullPath[i], fullPath[i + 1]);
    }
    return dist;
  }
}

class RoutingService {
  static final RoutingService _instance = RoutingService._internal();
  factory RoutingService() => _instance;

  List<Waypoint> _waypoints = [];
  Map<String, List<String>> _graph = {};
  Map<String, Waypoint> _waypointMap = {};
  bool _isGraphInitialized = false;

  List<String> _lastParsedInstructions = [];
  List<LatLng> _lastStepManeuverCoords = [];

  List<Waypoint> get waypoints => List.unmodifiable(_waypoints);
  Map<String, List<String>> get graph => Map.unmodifiable(_graph);
  List<Waypoint> get roadNodes => List.unmodifiable(_waypoints);
  Map<String, List<String>> get roadAdjacency => Map.unmodifiable(_graph);

  Future<void>? _initFuture;

  RoutingService._internal() {
    _initializeDefaultGraph();
    _initFuture = _loadCampusRoadsAsset();
  }

  /// Public loader from string (useful for testing, dynamic remote updates, and offline pre-caching)
  void loadCampusRoadsFromJsonString(String jsonString) {
    try {
      final data = json.decode(jsonString);
      Map<String, dynamic>? graphData;
      if (data is Map && data.containsKey('graph')) {
        graphData = data['graph'] as Map<String, dynamic>;
      } else if (data is Map && data.containsKey('nodes') && data.containsKey('edges')) {
        graphData = data as Map<String, dynamic>;
      }

      if (graphData != null) {
        final rawNodes = graphData['nodes'] as List<dynamic>;
        final rawEdges = graphData['edges'] as List<dynamic>;

        final List<Waypoint> loadedWaypoints = [];
        final Map<String, List<String>> loadedGraph = {};

        for (final n in rawNodes) {
          final id = n['id'].toString();
          final lat = (n['lat'] as num).toDouble();
          final lng = (n['lng'] as num).toDouble();
          final wp = Waypoint(
            id: id,
            name: _generateNodeName(id, lat, lng),
            position: LatLng(lat, lng),
          );
          loadedWaypoints.add(wp);
          loadedGraph[id] = [];
        }

        for (final e in rawEdges) {
          if (e is List && e.length >= 2) {
            final u = e[0].toString();
            final v = e[1].toString();
            if (loadedGraph.containsKey(u) && loadedGraph.containsKey(v)) {
              if (!loadedGraph[u]!.contains(v)) loadedGraph[u]!.add(v);
              if (!loadedGraph[v]!.contains(u)) loadedGraph[v]!.add(u);
            }
          }
        }

        _attachNamedGateWaypoints(loadedWaypoints, loadedGraph);

        _waypoints = loadedWaypoints;
        _graph = loadedGraph;
        _waypointMap = {for (final w in _waypoints) w.id: w};
        _isGraphInitialized = true;
      }
    } catch (e) {
      debugPrint("Error parsing campus roads string: $e");
    }
  }

  /// Public gate selector evaluating distance, target angle, and open/closed gate penalties
  Building selectOptimalGate(LatLng userPos, LatLng destination, {List<Building>? customGates, DateTime? now}) {
    final curTime = now ?? DateTime.now();
    final List<Map<String, dynamic>> candidateGates = [
      {
        'id': 'gate_main',
        'name': 'Main Gate Entrance',
        'pos': const LatLng(10.5541214, 76.2264419),
        'open': '06:00 AM',
        'close': '10:30 PM',
      },
      {
        'id': 'gate_south',
        'name': 'Electrical Gate Entrance',
        'pos': const LatLng(10.5520947, 76.2241280),
        'open': '08:00 AM',
        'close': '05:30 PM',
      },
      {
        'id': 'gate_east',
        'name': 'East Gate Entrance',
        'pos': const LatLng(10.5531511, 76.2264930),
        'open': '06:00 AM',
        'close': '09:00 PM',
      },
    ];

    if (customGates != null) {
      for (final b in customGates) {
        if (b.isDeleted) continue;
        final isGate = b.tags['barrier'] == 'gate' || b.tags['place_type'] == 'Entrance Gate';
        if (isGate) {
          candidateGates.add({
            'id': b.id,
            'name': b.name,
            'pos': LatLng(b.lat, b.lng),
            'open': b.tags['opening_time']?.toString() ?? '06:00 AM',
            'close': b.tags['closing_time']?.toString() ?? '10:00 PM',
          });
        }
      }
    }

    // Exclude closed gates completely as non-existent during closed hours
    final openGates = candidateGates.where((g) {
      final String? openStr = g['open'] as String?;
      final String? closeStr = g['close'] as String?;
      return isGateOpenNow(openStr, closeStr, now: curTime);
    }).toList();

    final validGates = openGates.isNotEmpty ? openGates : [candidateGates.first];

    Map<String, dynamic> bestGate = validGates.first;
    double minTotalCost = double.infinity;

    for (final gate in validGates) {
      final LatLng gatePos = gate['pos'] as LatLng;
      final double distExternalToGate = distance(userPos, gatePos);

      double distGateToInternal = distance(gatePos, destination);
      if (_isGraphInitialized && _graph.isNotEmpty) {
        final gateId = gate['id'] as String?;
        final destSnap = snapToNearestGraphEdge(destination);
        double minDijkstra = double.infinity;
        final startNodes = (gateId != null && _graph.containsKey(gateId))
            ? [gateId]
            : [snapToNearestGraphEdge(gatePos).nodeA, snapToNearestGraphEdge(gatePos).nodeB];
        final endNodes = [destSnap.nodeA, destSnap.nodeB];
        for (final s in startNodes) {
          for (final e in endNodes) {
            final p = getRouteBetweenWaypoints(s, e);
            if (p.isNotEmpty || s == e) {
              final d = getRouteDistance(p) + distance(destination, destSnap.snappedPoint);
              if (d < minDijkstra) minDijkstra = d;
            }
          }
        }
        if (minDijkstra < double.infinity) {
          distGateToInternal = minDijkstra;
        }
      }

      final double totalCost = distExternalToGate + distGateToInternal;

      if (totalCost < minTotalCost) {
        minTotalCost = totalCost;
        bestGate = gate;
      }
    }

    final pos = bestGate['pos'] as LatLng;
    return Building(
      id: bestGate['id'] as String,
      name: bestGate['name'] as String,
      lat: pos.latitude,
      lng: pos.longitude,
      tags: {
        'barrier': 'gate',
        'opening_time': bestGate['open'],
        'closing_time': bestGate['close'],
      },
    );
  }

  /// Gate schedule helper: checks if a gate is currently open
  static bool isGateOpenNow(String? openTime, String? closeTime, {DateTime? now}) {
    if (openTime == null || openTime.trim().isEmpty ||
        closeTime == null || closeTime.trim().isEmpty) {
      return true; // 24/7 or unconstrained
    }

    final current = now ?? DateTime.now();
    final currentMinutes = current.hour * 60 + current.minute;

    final openMinutes = _parseTimeToMinutes(openTime);
    final closeMinutes = _parseTimeToMinutes(closeTime);

    if (openMinutes == null || closeMinutes == null) return true;

    if (openMinutes <= closeMinutes) {
      return currentMinutes >= openMinutes && currentMinutes < closeMinutes;
    } else {
      // Crosses midnight (e.g. 18:00 to 06:00)
      return currentMinutes >= openMinutes || currentMinutes < closeMinutes;
    }
  }

  /// Gate schedule status label helper (e.g. "Open • Closes 10:00 PM")
  static String getGateStatusLabel(String? openTime, String? closeTime, {DateTime? now}) {
    if (openTime == null || openTime.trim().isEmpty ||
        closeTime == null || closeTime.trim().isEmpty) {
      return "Open 24 Hours";
    }

    final isOpen = isGateOpenNow(openTime, closeTime, now: now);
    if (isOpen) {
      return "Open • Closes ${_formatTimeDisplay(closeTime)}";
    } else {
      return "Closed • Opens ${_formatTimeDisplay(openTime)}";
    }
  }

  static int? _parseTimeToMinutes(String timeStr) {
    final clean = timeStr.trim().toLowerCase();
    if (clean == '24/7' || clean == 'always open' || clean == 'open') return null;

    final isPm = clean.contains('pm');
    final isAm = clean.contains('am');
    final numericOnly = clean.replaceAll(RegExp(r'[^0-9:]'), '');
    final parts = numericOnly.split(':');

    if (parts.isEmpty) return null;
    int hour = int.tryParse(parts[0]) ?? 0;
    int minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;

    if (isPm && hour < 12) hour += 12;
    if (isAm && hour == 12) hour = 0;

    return hour * 60 + minute;
  }

  static String _formatTimeDisplay(String timeStr) {
    final mins = _parseTimeToMinutes(timeStr);
    if (mins == null) return timeStr;

    final hour = mins ~/ 60;
    final minute = mins % 60;
    final isPm = hour >= 12;
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final minuteStr = minute < 10 ? '0$minute' : '$minute';
    final period = isPm ? 'PM' : 'AM';

    return '$displayHour:$minuteStr $period';
  }

  /// Asynchronously loads and parses assets/campus_roads.json to upgrade the graph
  Future<void> _loadCampusRoadsAsset() async {
    try {
      final jsonString = await rootBundle.loadString('assets/campus_roads.json');
      final data = json.decode(jsonString);

      if (data is Map && data.containsKey('nodes') && data.containsKey('edges')) {
        final rawNodes = data['nodes'] as List<dynamic>;
        final rawEdges = data['edges'] as List<dynamic>;

        final List<Waypoint> loadedWaypoints = [];
        final Map<String, List<String>> loadedGraph = {};

        for (final n in rawNodes) {
          final id = n['id'].toString();
          final lat = (n['lat'] as num).toDouble();
          final lng = (n['lng'] as num).toDouble();
          final wp = Waypoint(
            id: id,
            name: _generateNodeName(id, lat, lng),
            position: LatLng(lat, lng),
          );
          loadedWaypoints.add(wp);
          loadedGraph[id] = [];
        }

        for (final e in rawEdges) {
          if (e is List && e.length >= 2) {
            final u = e[0].toString();
            final v = e[1].toString();
            if (loadedGraph.containsKey(u) && loadedGraph.containsKey(v)) {
              if (!loadedGraph[u]!.contains(v)) loadedGraph[u]!.add(v);
              if (!loadedGraph[v]!.contains(u)) loadedGraph[v]!.add(u);
            }
          }
        }

        // Add explicit named gate connections to closest road nodes
        _attachNamedGateWaypoints(loadedWaypoints, loadedGraph);

        _waypoints = loadedWaypoints;
        _graph = loadedGraph;
        _waypointMap = {for (final w in _waypoints) w.id: w};
        _isGraphInitialized = true;
        debugPrint("Loaded campus_roads.json with ${_waypoints.length} nodes and ${_graph.length} graph keys.");
      }
    } catch (e) {
      debugPrint("Campus roads asset load note/fallback: $e");
    }
  }

  String _generateNodeName(String id, double lat, double lng) {
    if (distance(LatLng(lat, lng), const LatLng(10.5541214, 76.2264419)) < 15) {
      return "Main Gate Entrance";
    }
    if (distance(LatLng(lat, lng), const LatLng(10.5520947, 76.2241280)) < 15) {
      return "Electrical Gate Entrance";
    }
    if (distance(LatLng(lat, lng), const LatLng(10.5531511, 76.2264930)) < 15) {
      return "East Gate Entrance";
    }
    if (distance(LatLng(lat, lng), const LatLng(10.554418, 76.224668)) < 25) {
      return "Main Building Central Plaza";
    }
    if (distance(LatLng(lat, lng), const LatLng(10.553595, 76.224567)) < 25) {
      return "Auditorium / Library Junction";
    }
    if (distance(LatLng(lat, lng), const LatLng(10.552740, 76.222020)) < 25) {
      return "CSE / ECE Academic Way";
    }
    if (distance(LatLng(lat, lng), const LatLng(10.554442, 76.222121)) < 25) {
      return "Hostels & Sports Road";
    }
    return "Campus Walkway ($id)";
  }

  void _attachNamedGateWaypoints(List<Waypoint> wps, Map<String, List<String>> grp) {
    final gateDefs = [
      {'id': 'gate_main', 'name': 'Main Gate Entrance', 'pos': const LatLng(10.5541214, 76.2264419)},
      {'id': 'gate_south', 'name': 'Electrical Gate Entrance', 'pos': const LatLng(10.5520947, 76.2241280)},
      {'id': 'gate_east', 'name': 'East Gate Entrance', 'pos': const LatLng(10.5531511, 76.2264930)},
    ];

    for (final g in gateDefs) {
      final gId = g['id'] as String;
      final gPos = g['pos'] as LatLng;
      final gName = g['name'] as String;

      // Find 2 closest existing nodes in wps
      final sortedNodes = List<Waypoint>.from(wps)
        ..sort((a, b) => distance(gPos, a.position).compareTo(distance(gPos, b.position)));

      wps.removeWhere((w) => w.id == gId);
      wps.add(Waypoint(id: gId, name: gName, position: gPos));
      grp[gId] = [];

      for (int i = 0; i < min(2, sortedNodes.length); i++) {
        final target = sortedNodes[i];
        if (!grp[gId]!.contains(target.id)) grp[gId]!.add(target.id);
        grp.putIfAbsent(target.id, () => []);
        if (!grp[target.id]!.contains(gId)) grp[target.id]!.add(gId);
      }
    }
  }

  void _initializeDefaultGraph() {
    if (_isGraphInitialized) return;
    _waypoints = [
      Waypoint(id: 'gate_main', name: 'Main Gate Entrance', position: const LatLng(10.5541214, 76.2264419)),
      Waypoint(id: 'gate_south', name: 'Electrical Gate Entrance', position: const LatLng(10.5520947, 76.2241280)),
      Waypoint(id: 'gate_east', name: 'East Gate Entrance', position: const LatLng(10.5531511, 76.2264930)),
      Waypoint(id: 'main_gate', name: 'Main Gate Entrance', position: const LatLng(10.554094, 76.226412)),
      Waypoint(id: 'main_gate_curve1', name: 'Main Gate Curve 1', position: const LatLng(10.554120, 76.226150)),
      Waypoint(id: 'main_gate_curve2', name: 'Main Gate Curve 2', position: const LatLng(10.554160, 76.225900)),
      Waypoint(id: 'main_junction', name: 'Main Junction (Amphitheatre)', position: const LatLng(10.554200, 76.225600)),
      Waypoint(id: 'bus_stop_road', name: 'Campus Bus Stop Path', position: const LatLng(10.554010, 76.226250)),
      Waypoint(id: 'main_road_w1', name: 'Central Avenue 1', position: const LatLng(10.554280, 76.225300)),
      Waypoint(id: 'main_road_w2', name: 'Central Avenue 2', position: const LatLng(10.554350, 76.225000)),
      Waypoint(id: 'main_building_front', name: 'Main Building Front Plaza', position: const LatLng(10.554418, 76.224668)),
      Waypoint(id: 'admin_block_path', name: 'Admin Office Walkway', position: const LatLng(10.554520, 76.224800)),
      Waypoint(id: 'main_aud_road1', name: 'South Road 1', position: const LatLng(10.554100, 76.224650)),
      Waypoint(id: 'library_junction', name: 'Central Library Junction', position: const LatLng(10.553850, 76.224610)),
      Waypoint(id: 'auditorium_junction', name: 'Auditorium Junction (Cafeteria)', position: const LatLng(10.553595, 76.224567)),
      Waypoint(id: 'aud_workshop_road1', name: 'Aud-Workshop Road 1', position: const LatLng(10.553250, 76.224600)),
      Waypoint(id: 'workshops_junction', name: 'Workshops Road Junction', position: const LatLng(10.552883, 76.224626)),
      Waypoint(id: 'canteen_front', name: 'Central Canteen Entrance', position: const LatLng(10.552333, 76.224332)),
      Waypoint(id: 'coop_store_road', name: 'Cooperative Store Walkway', position: const LatLng(10.552550, 76.224450)),
      Waypoint(id: 'workshop_east_road1', name: 'Workshop East Road 1', position: const LatLng(10.552900, 76.225000)),
      Waypoint(id: 'workshop_east_road2', name: 'Workshop East Road 2', position: const LatLng(10.552950, 76.225450)),
      Waypoint(id: 'electrical_junction', name: 'Electrical Lab Junction', position: const LatLng(10.553002, 76.225915)),
      Waypoint(id: 'mech_workshop_path', name: 'Mechanical Workshop Path', position: const LatLng(10.552780, 76.225200)),
      Waypoint(id: 'elec_civil_road1', name: 'Elec-Civil Road 1', position: const LatLng(10.553350, 76.225890)),
      Waypoint(id: 'civil_workshop_front', name: 'Civil Workshop Front', position: const LatLng(10.553708, 76.225861)),
      Waypoint(id: 'pg_block_path', name: 'PG Block & Research Lab Access', position: const LatLng(10.553550, 76.226100)),
      Waypoint(id: 'civil_main_road1', name: 'Civil-Main Road 1', position: const LatLng(10.553900, 76.225750)),
      Waypoint(id: 'civil_dept_entrance', name: 'Civil Dept Building Entrance', position: const LatLng(10.553800, 76.225600)),
      Waypoint(id: 'west_road1', name: 'Western Campus Road 1', position: const LatLng(10.553500, 76.224200)),
      Waypoint(id: 'west_road2', name: 'Western Campus Road 2', position: const LatLng(10.553350, 76.223800)),
      Waypoint(id: 'chemical_junction', name: 'Chemical Eng. Junction', position: const LatLng(10.553100, 76.223400)),
      Waypoint(id: 'west_road3', name: 'Western Campus Road 3', position: const LatLng(10.552900, 76.223000)),
      Waypoint(id: 'west_road4', name: 'Western Campus Road 4', position: const LatLng(10.552800, 76.222600)),
      Waypoint(id: 'cse_ece_junction', name: 'CS & Production Dept Junction', position: const LatLng(10.552740, 76.222020)),
      Waypoint(id: 'ece_chem_junction', name: 'ECE Dept Entrance Junction', position: const LatLng(10.552710, 76.221619)),
      Waypoint(id: 'mca_block_road', name: 'MCA Department Walkway', position: const LatLng(10.552650, 76.221200)),
      Waypoint(id: 'hostel_road_start', name: 'Hostel Road Start', position: const LatLng(10.554300, 76.225200)),
      Waypoint(id: 'hostel_road_mid', name: 'Hostel Road Midpoint', position: const LatLng(10.554400, 76.224500)),
      Waypoint(id: 'hostel_road_w1', name: 'Hostel Road West 1', position: const LatLng(10.554430, 76.223800)),
      Waypoint(id: 'hostel_road_w2', name: 'Hostel Road West 2', position: const LatLng(10.554440, 76.223100)),
      Waypoint(id: 'mens_hostel_junction', name: "Men's Hostel Main Junction", position: const LatLng(10.554442, 76.222121)),
      Waypoint(id: 'mh_block_a_road', name: "Men's Hostel Block A Access", position: const LatLng(10.554650, 76.222100)),
      Waypoint(id: 'lh_junction', name: "Ladies Hostel Junction", position: const LatLng(10.554800, 76.221500)),
      Waypoint(id: 'hostel_cse_road1', name: 'Hostel-CSE Road 1', position: const LatLng(10.554100, 76.222100)),
      Waypoint(id: 'hostel_cse_road2', name: 'Hostel-CSE Road 2', position: const LatLng(10.553700, 76.222080)),
      Waypoint(id: 'hostel_cse_road3', name: 'Hostel-CSE Road 3', position: const LatLng(10.553200, 76.222050)),
      Waypoint(id: 'chem_workshop_road1', name: 'Chemical-Workshop Road 1', position: const LatLng(10.552950, 76.223700)),
      Waypoint(id: 'chem_workshop_road2', name: 'Chemical-Workshop Road 2', position: const LatLng(10.552900, 76.224100)),
      Waypoint(id: 'upper_road1', name: 'Upper Campus Road 1', position: const LatLng(10.554600, 76.224400)),
      Waypoint(id: 'upper_road2', name: 'Upper Campus Road 2', position: const LatLng(10.554700, 76.224000)),
      Waypoint(id: 'upper_road3', name: 'Upper Campus Road 3', position: const LatLng(10.554750, 76.223500)),
      Waypoint(id: 'sports_ground_road', name: 'Sports Ground Entrance Path', position: const LatLng(10.554900, 76.222800)),
      Waypoint(id: 'indoor_court_road', name: 'Indoor Court Road', position: const LatLng(10.555050, 76.222200)),
      Waypoint(id: 'inner_road1', name: 'East Inner Road 1', position: const LatLng(10.553500, 76.225500)),
      Waypoint(id: 'inner_road2', name: 'East Inner Road 2', position: const LatLng(10.553800, 76.225400)),
    ];

    _waypointMap = {for (final w in _waypoints) w.id: w};
    final rawGraph = <String, List<String>>{
      'gate_main': ['main_gate', 'main_gate_curve1', 'bus_stop_road', 'gate_east'],
      'gate_east': ['electrical_junction', 'pg_block_path', 'elec_civil_road1', 'gate_main', 'gate_south'],
      'gate_south': ['canteen_front', 'coop_store_road', 'workshops_junction', 'gate_east'],
      'main_gate': ['gate_main', 'main_gate_curve1', 'bus_stop_road'],
      'bus_stop_road': ['main_gate', 'main_gate_curve1'],
      'main_gate_curve1': ['main_gate', 'main_gate_curve2', 'bus_stop_road'],
      'main_gate_curve2': ['main_gate_curve1', 'main_junction'],
      'main_junction': ['main_gate_curve2', 'main_road_w1', 'civil_main_road1', 'hostel_road_start'],
      'main_road_w1': ['main_junction', 'main_road_w2'],
      'main_road_w2': ['main_road_w1', 'main_building_front', 'admin_block_path'],
      'admin_block_path': ['main_road_w2', 'main_building_front'],
      'main_building_front': ['main_road_w2', 'main_aud_road1', 'upper_road1', 'hostel_road_mid', 'admin_block_path'],
      'main_aud_road1': ['main_building_front', 'library_junction'],
      'library_junction': ['main_aud_road1', 'auditorium_junction'],
      'auditorium_junction': ['library_junction', 'aud_workshop_road1', 'west_road1'],
      'aud_workshop_road1': ['auditorium_junction', 'workshops_junction', 'coop_store_road'],
      'coop_store_road': ['aud_workshop_road1', 'workshops_junction'],
      'workshops_junction': ['aud_workshop_road1', 'canteen_front', 'workshop_east_road1', 'chem_workshop_road2', 'coop_store_road'],
      'canteen_front': ['workshops_junction'],
      'workshop_east_road1': ['workshops_junction', 'workshop_east_road2', 'mech_workshop_path'],
      'mech_workshop_path': ['workshop_east_road1', 'workshop_east_road2'],
      'workshop_east_road2': ['workshop_east_road1', 'electrical_junction', 'mech_workshop_path'],
      'electrical_junction': ['workshop_east_road2', 'elec_civil_road1', 'inner_road1'],
      'elec_civil_road1': ['electrical_junction', 'civil_workshop_front', 'pg_block_path'],
      'pg_block_path': ['elec_civil_road1', 'civil_workshop_front'],
      'civil_workshop_front': ['elec_civil_road1', 'civil_main_road1', 'pg_block_path'],
      'civil_main_road1': ['civil_workshop_front', 'main_junction', 'inner_road2', 'civil_dept_entrance'],
      'civil_dept_entrance': ['civil_main_road1', 'main_junction'],
      'west_road1': ['auditorium_junction', 'west_road2'],
      'west_road2': ['west_road1', 'chemical_junction'],
      'chemical_junction': ['west_road2', 'west_road3', 'chem_workshop_road1'],
      'west_road3': ['chemical_junction', 'west_road4'],
      'west_road4': ['west_road3', 'cse_ece_junction'],
      'cse_ece_junction': ['west_road4', 'ece_chem_junction', 'hostel_cse_road3'],
      'ece_chem_junction': ['cse_ece_junction', 'mca_block_road'],
      'mca_block_road': ['ece_chem_junction'],
      'hostel_road_start': ['main_junction', 'hostel_road_mid'],
      'hostel_road_mid': ['hostel_road_start', 'hostel_road_w1', 'main_building_front'],
      'hostel_road_w1': ['hostel_road_mid', 'hostel_road_w2', 'upper_road3'],
      'hostel_road_w2': ['hostel_road_w1', 'mens_hostel_junction'],
      'mens_hostel_junction': ['hostel_road_w2', 'hostel_cse_road1', 'mh_block_a_road', 'lh_junction'],
      'mh_block_a_road': ['mens_hostel_junction', 'lh_junction'],
      'lh_junction': ['mens_hostel_junction', 'mh_block_a_road'],
      'hostel_cse_road1': ['mens_hostel_junction', 'hostel_cse_road2'],
      'hostel_cse_road2': ['hostel_cse_road1', 'hostel_cse_road3'],
      'hostel_cse_road3': ['hostel_cse_road2', 'cse_ece_junction'],
      'chem_workshop_road1': ['chemical_junction', 'chem_workshop_road2'],
      'chem_workshop_road2': ['chem_workshop_road1', 'workshops_junction'],
      'upper_road1': ['main_building_front', 'upper_road2'],
      'upper_road2': ['upper_road1', 'upper_road3'],
      'upper_road3': ['upper_road2', 'hostel_road_w1', 'sports_ground_road'],
      'sports_ground_road': ['upper_road3', 'indoor_court_road'],
      'indoor_court_road': ['sports_ground_road', 'lh_junction'],
      'inner_road1': ['electrical_junction', 'inner_road2'],
      'inner_road2': ['inner_road1', 'civil_main_road1'],
    };

    _graph = {};
    rawGraph.forEach((node, neighbors) {
      _graph.putIfAbsent(node, () => <String>[]);
      for (final nbr in neighbors) {
        if (!_graph[node]!.contains(nbr)) _graph[node]!.add(nbr);
        _graph.putIfAbsent(nbr, () => <String>[]);
        if (!_graph[nbr]!.contains(node)) _graph[nbr]!.add(node);
      }
    });
  }

  // Calculate Haversine distance in meters
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
    String bestNodeA = _waypoints.isNotEmpty ? _waypoints.first.id : 'gate_main';
    String bestNodeB = bestNodeA;

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

  Waypoint findClosestWaypoint(LatLng point) {
    if (_waypoints.isEmpty) {
      return Waypoint(id: 'gate_main', name: 'Main Gate Entrance', position: const LatLng(10.5541214, 76.2264419));
    }
    Waypoint closest = _waypoints.first;
    double minDistance = distance(point, closest.position);

    for (var wp in _waypoints) {
      final dist = distance(point, wp.position);
      if (dist < minDistance) {
        minDistance = dist;
        closest = wp;
      }
    }
    return closest;
  }

  /// Returns node IDs belonging to gates currently closed based on operating schedule
  Set<String> getClosedGateNodeIds({DateTime? now, List<Building>? customGates}) {
    final curTime = now ?? DateTime.now();
    final Set<String> closedNodes = {};

    final List<Map<String, dynamic>> gates = [
      {
        'id': 'gate_main',
        'pos': const LatLng(10.5541214, 76.2264419),
        'open': '06:00 AM',
        'close': '10:30 PM',
      },
      {
        'id': 'gate_south',
        'pos': const LatLng(10.5520947, 76.2241280),
        'open': '08:00 AM',
        'close': '05:30 PM',
      },
      {
        'id': 'gate_east',
        'pos': const LatLng(10.5531511, 76.2264930),
        'open': '06:00 AM',
        'close': '09:00 PM',
      },
    ];

    if (customGates != null) {
      for (final b in customGates) {
        if (b.isDeleted) continue;
        final isGate = b.tags['barrier'] == 'gate' || b.tags['place_type'] == 'Entrance Gate';
        if (isGate) {
          gates.add({
            'id': b.id,
            'pos': LatLng(b.lat, b.lng),
            'open': b.tags['opening_time']?.toString() ?? '06:00 AM',
            'close': b.tags['closing_time']?.toString() ?? '10:00 PM',
          });
        }
      }
    }

    for (final gate in gates) {
      final isOpen = isGateOpenNow(gate['open'] as String?, gate['close'] as String?, now: curTime);
      if (!isOpen) {
        final gateId = gate['id'] as String;
        closedNodes.add(gateId);

        // Also block road nodes directly on/within 15m of this closed gate
        final gatePos = gate['pos'] as LatLng;
        for (final wp in _waypoints) {
          if (distance(wp.position, gatePos) < 15.0) {
            closedNodes.add(wp.id);
          }
        }
      }
    }

    return closedNodes;
  }

  /// Checks if a location is near a gate that is currently closed
  bool isNearClosedGate(LatLng pos, {DateTime? now, List<Building>? customGates}) {
    final curTime = now ?? DateTime.now();
    final List<Map<String, dynamic>> gates = [
      {
        'id': 'gate_main',
        'name': 'Main Gate Entrance',
        'pos': const LatLng(10.5541214, 76.2264419),
        'open': '06:00 AM',
        'close': '10:30 PM',
      },
      {
        'id': 'gate_south',
        'name': 'Electrical Gate Entrance',
        'pos': const LatLng(10.5520947, 76.2241280),
        'open': '08:00 AM',
        'close': '05:30 PM',
      },
      {
        'id': 'gate_east',
        'name': 'East Gate Entrance',
        'pos': const LatLng(10.5531511, 76.2264930),
        'open': '06:00 AM',
        'close': '09:00 PM',
      },
    ];

    if (customGates != null) {
      for (final b in customGates) {
        if (b.isDeleted) continue;
        final isGate = b.tags['barrier'] == 'gate' || b.tags['place_type'] == 'Entrance Gate';
        if (isGate) {
          gates.add({
            'id': b.id,
            'name': b.name,
            'pos': LatLng(b.lat, b.lng),
            'open': b.tags['opening_time']?.toString() ?? '06:00 AM',
            'close': b.tags['closing_time']?.toString() ?? '10:00 PM',
          });
        }
      }
    }

    for (final g in gates) {
      final isOpen = isGateOpenNow(g['open'] as String?, g['close'] as String?, now: curTime);
      if (!isOpen && distance(pos, g['pos'] as LatLng) < 25.0) {
        return true;
      }
    }
    return false;
  }

  /// Campus perimeter bounding box check
  static bool isPointOutsideCampus(LatLng point) {
    const double minLat = 10.5512;
    const double maxLat = 10.5568;
    const double minLng = 76.2168;
    const double maxLng = 76.2272;

    return point.latitude < minLat ||
        point.latitude > maxLat ||
        point.longitude < minLng ||
        point.longitude > maxLng;
  }

  /// Dijkstra algorithm to find shortest road path between two waypoint IDs
  List<LatLng> getRouteBetweenWaypoints(
    String startId,
    String endId, {
    Set<String>? closedNodeIds,
  }) {
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

        double weight = distance(currentWp.position, neighborWp.position);
        if (closedNodeIds != null &&
            closedNodeIds.contains(neighborId) &&
            neighborId != startId &&
            neighborId != endId) {
          weight += 5000.0; // Detour penalty for closed gates
        }

        final alt = currentDist + weight;

        if (alt < (distances[neighborId] ?? double.infinity)) {
          distances[neighborId] = alt;
          previous[neighborId] = currentId;

          final entry = _PQEntry(neighborId, alt);
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
        debugPrint("Online OSRM endpoint ($urlStr) skipped/failed: $e");
      }
    }
    return null;
  }

  /// Get single optimal route considering boundary crossing, operating gate schedules & paved walkways
  Future<RouteResult> getDetailedRoute(
    LatLng start,
    LatLng end, {
    List<Building>? customBuildings,
    DateTime? currentTime,
  }) async {
    _lastParsedInstructions.clear();
    _lastStepManeuverCoords.clear();

    final now = currentTime ?? DateTime.now();
    if (_initFuture != null) await _initFuture;

    final bool startIsOutside = isPointOutsideCampus(start);
    final bool endIsOutside = isPointOutsideCampus(end);

    // 1. Both points internal to campus -> Pure direct point-to-point walkway navigation!
    // Do NOT look for or route through any gates.
    if (!startIsOutside && !endIsOutside) {
      return _getInternalCampusRoute(start, end, currentTime: now, customBuildings: customBuildings);
    }

    // 2. Both points external to campus -> Pure online road navigation
    if (startIsOutside && endIsOutside) {
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

        final List<LatLng> rawFullPath = [];
        if (startAccess.isNotEmpty) rawFullPath.add(start);
        rawFullPath.addAll(onlinePath);
        if (endAccess.isNotEmpty && distance(rawFullPath.last, end) > 1.0) rawFullPath.add(end);

        final smoothedFullPath = smoothPolyline(rawFullPath, iterations: 2);
        final smoothedRoadPath = smoothPolyline(onlinePath, iterations: 2);

        return RouteResult(
          fullPath: smoothedFullPath,
          startAccessPath: startAccess,
          roadPath: smoothedRoadPath,
          endAccessPath: endAccess,
          instructions: _lastParsedInstructions.isNotEmpty
              ? _lastParsedInstructions
              : generateOfflineInstructions(rawFullPath),
        );
      }

      // Fallback direct connector
      return _getInternalCampusRoute(start, end, currentTime: now, customBuildings: customBuildings);
    }

    // 3. Boundary crossing routing (startIsOutside != endIsOutside)
    // One point is outside and the other is inside -> find optimal open gate to enter/exit campus.
    final List<Map<String, dynamic>> allGates = [
      {
        'id': 'gate_main',
        'name': 'Main Gate Entrance',
        'pos': const LatLng(10.5541214, 76.2264419),
        'open': '06:00 AM',
        'close': '10:30 PM',
      },
      {
        'id': 'gate_south',
        'name': 'Electrical Gate Entrance',
        'pos': const LatLng(10.5520947, 76.2241280),
        'open': '08:00 AM',
        'close': '05:30 PM',
      },
      {
        'id': 'gate_east',
        'name': 'East Gate Entrance',
        'pos': const LatLng(10.5531511, 76.2264930),
        'open': '06:00 AM',
        'close': '09:00 PM',
      },
    ];

    if (customBuildings != null) {
      for (final b in customBuildings) {
        if (b.isDeleted) continue;
        final isGate = b.tags['barrier'] == 'gate' || b.tags['place_type'] == 'Entrance Gate';
        if (isGate) {
          allGates.add({
            'id': b.id,
            'name': b.name,
            'pos': LatLng(b.lat, b.lng),
            'open': b.tags['opening_time']?.toString() ?? '06:00 AM',
            'close': b.tags['closing_time']?.toString() ?? '10:00 PM',
          });
        }
      }
    }

    final List<Map<String, dynamic>> openGates = allGates.where((g) {
      return isGateOpenNow(g['open'] as String?, g['close'] as String?, now: now);
    }).toList();

    final List<Map<String, dynamic>> validGates = openGates.isNotEmpty ? openGates : [allGates.first];
    final closedNodeIds = getClosedGateNodeIds(now: now, customGates: customBuildings);

    final LatLng externalPoint = startIsOutside ? start : end;
    final LatLng internalPoint = startIsOutside ? end : start;
    final internalSnap = snapToNearestGraphEdge(internalPoint);

    Map<String, dynamic> bestGate = validGates.first;
    double minTotalCost = double.infinity;

    for (final gate in validGates) {
      final LatLng gatePos = gate['pos'] as LatLng;
      final externalDist = distance(externalPoint, gatePos);

      final gateId = gate['id'] as String?;
      final gateSnap = snapToNearestGraphEdge(gatePos);
      final startNodes = (gateId != null && _graph.containsKey(gateId))
          ? [gateId, gateSnap.nodeA, gateSnap.nodeB]
          : [gateSnap.nodeA, gateSnap.nodeB];

      double campusDist = double.infinity;
      for (final gNode in startNodes) {
        for (final snapNode in [internalSnap.nodeA, internalSnap.nodeB]) {
          final path = getRouteBetweenWaypoints(
            gNode,
            snapNode,
            closedNodeIds: closedNodeIds,
          );
          if (path.isNotEmpty || gNode == snapNode) {
            final d = getRouteDistance(path) +
                distance(internalPoint, internalSnap.snappedPoint) +
                distance(gatePos, gateSnap.snappedPoint);
            if (d < campusDist) campusDist = d;
          }
        }
      }
      if (campusDist == double.infinity) campusDist = distance(gatePos, internalPoint);

      final totalCost = externalDist + campusDist;
      if (totalCost < minTotalCost) {
        minTotalCost = totalCost;
        bestGate = gate;
      }
    }

    // Check if geographically closest gate was closed
    Map<String, dynamic>? geographicallyClosestGate;
    double minGeoDist = double.infinity;
    for (final gate in allGates) {
      final d = distance(externalPoint, gate['pos'] as LatLng);
      if (d < minGeoDist) {
        minGeoDist = d;
        geographicallyClosestGate = gate;
      }
    }

    final gatePos = bestGate['pos'] as LatLng;
    final gateName = bestGate['name'] as String;
    final bool isClosestGateOpen = geographicallyClosestGate != null
        ? isGateOpenNow(geographicallyClosestGate['open'] as String?, geographicallyClosestGate['close'] as String?, now: now)
        : true;

    String? gateNotice;
    String? closedGateName;
    String? activeGateName = gateName;

    if (geographicallyClosestGate != null && !isClosestGateOpen && bestGate['id'] != geographicallyClosestGate['id']) {
      closedGateName = geographicallyClosestGate['name'] as String;
      gateNotice = "$closedGateName may be closed at this time. Rerouted via $activeGateName which is open.";
    }

    if (startIsOutside && !endIsOutside) {
      final onlinePath = await _tryOnlineOSRM(start, gatePos);
      final externalPath = (onlinePath != null && onlinePath.isNotEmpty)
          ? onlinePath
          : <LatLng>[start, gatePos];

      final campusRoute = await _getInternalCampusRoute(gatePos, end, currentTime: now, customBuildings: customBuildings);
      final rawFullPath = <LatLng>[...externalPath, ...campusRoute.fullPath.skip(1)];

      final instructions = generateOfflineInstructions(rawFullPath);
      if (gateNotice != null) {
        instructions.insert(0, gateNotice);
      }
      _lastParsedInstructions = instructions;

      final smoothedFullPath = smoothPolyline(rawFullPath, iterations: 2);
      final smoothedRoadPath = smoothPolyline(rawFullPath, iterations: 2);

      return RouteResult(
        fullPath: smoothedFullPath,
        startAccessPath: [start, externalPath.first],
        roadPath: smoothedRoadPath,
        endAccessPath: campusRoute.endAccessPath,
        instructions: instructions,
        gateClosureNotice: gateNotice,
        bypassedClosedGateName: closedGateName,
        activeGateName: activeGateName,
      );
    } else {
      final campusRoute = await _getInternalCampusRoute(start, gatePos, currentTime: now, customBuildings: customBuildings);
      final onlinePath = await _tryOnlineOSRM(gatePos, end);
      final externalPath = (onlinePath != null && onlinePath.isNotEmpty)
          ? onlinePath
          : <LatLng>[gatePos, end];

      final rawFullPath = <LatLng>[...campusRoute.fullPath, ...externalPath.skip(1)];

      final instructions = generateOfflineInstructions(rawFullPath);
      if (gateNotice != null) {
        instructions.insert(0, gateNotice);
      }
      _lastParsedInstructions = instructions;

      final smoothedFullPath = smoothPolyline(rawFullPath, iterations: 2);
      final smoothedRoadPath = smoothPolyline(rawFullPath, iterations: 2);

      return RouteResult(
        fullPath: smoothedFullPath,
        startAccessPath: campusRoute.startAccessPath,
        roadPath: smoothedRoadPath,
        endAccessPath: [externalPath.last, end],
        instructions: instructions,
        gateClosureNotice: gateNotice,
        bypassedClosedGateName: closedGateName,
        activeGateName: activeGateName,
      );
    }
  }

  /// Internal Dijkstra routing between two campus points on the paved road network
  Future<RouteResult> _getInternalCampusRoute(
    LatLng start,
    LatLng end, {
    DateTime? currentTime,
    List<Building>? customBuildings,
  }) async {
    final now = currentTime ?? DateTime.now();
    if (_initFuture != null) await _initFuture;
    final closedNodes = getClosedGateNodeIds(now: now, customGates: customBuildings);

    final startSnap = snapToNearestGraphEdge(start);
    final endSnap = snapToNearestGraphEdge(end);

    List<LatLng> bestRoadPath = [];
    double minTotalDist = double.infinity;

    // Direct segment check if both start and end snap to the exact same road edge
    final bool isSameEdge = (startSnap.nodeA == endSnap.nodeA && startSnap.nodeB == endSnap.nodeB) ||
        (startSnap.nodeA == endSnap.nodeB && startSnap.nodeB == endSnap.nodeA);
    if (isSameEdge) {
      final directDist = distance(startSnap.snappedPoint, endSnap.snappedPoint);
      if (directDist < minTotalDist) {
        minTotalDist = directDist;
        bestRoadPath = [startSnap.snappedPoint, endSnap.snappedPoint];
      }
    }

    final candidateStartNodes = [startSnap.nodeA, startSnap.nodeB];
    final candidateEndNodes = [endSnap.nodeA, endSnap.nodeB];

    for (final sNode in candidateStartNodes) {
      for (final eNode in candidateEndNodes) {
        final subPath = getRouteBetweenWaypoints(
          sNode,
          eNode,
          closedNodeIds: closedNodes,
        );
        if (subPath.isNotEmpty || sNode == eNode) {
          final List<LatLng> candidate = [startSnap.snappedPoint];
          if (subPath.isNotEmpty) {
            for (final pt in subPath) {
              if (candidate.isEmpty || distance(candidate.last, pt) > 0.5) {
                candidate.add(pt);
              }
            }
          }
          if (candidate.isEmpty || distance(candidate.last, endSnap.snappedPoint) > 0.5) {
            candidate.add(endSnap.snappedPoint);
          }

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

      final List<LatLng> rawFullPath = [];
      if (startAccess.isNotEmpty) rawFullPath.add(start);
      rawFullPath.addAll(bestRoadPath);
      if (endAccess.isNotEmpty && distance(rawFullPath.last, end) > 0.5) rawFullPath.add(end);

      final instructions = generateOfflineInstructions(rawFullPath);
      _lastParsedInstructions = instructions;

      final smoothedFullPath = smoothPolyline(rawFullPath, iterations: 2);
      final smoothedRoadPath = smoothPolyline(bestRoadPath, iterations: 2);

      return RouteResult(
        fullPath: smoothedFullPath,
        startAccessPath: startAccess,
        roadPath: smoothedRoadPath,
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

  String _getNearestRoadName(LatLng pos) {
    if (_waypoints.isEmpty) return '';
    Waypoint? best;
    double minD = double.infinity;
    for (final wp in _waypoints) {
      if (wp.name.startsWith('Campus Walkway (')) continue; // Skip raw node IDs
      final d = distance(pos, wp.position);
      if (d < minD && d < 30.0) {
        minD = d;
        best = wp;
      }
    }
    return best?.name ?? '';
  }

  List<Map<String, dynamic>> getDetailedManeuverSteps(List<LatLng> path) {
    if (path.length < 2) {
      return [
        {
          'text': 'Arrive at destination',
          'action': 'arrive',
          'road': 'Destination',
          'index': 0,
          'distance': 0.0,
        }
      ];
    }

    final List<Map<String, dynamic>> steps = [];

    const gateMainPos = LatLng(10.5541214, 76.2264419);
    const gateSouthPos = LatLng(10.5520947, 76.2241280);
    const gateEastPos = LatLng(10.5531511, 76.2264930);

    final initialRoad = _getNearestRoadName(path.first);
    steps.add({
      'text': initialRoad.isNotEmpty ? 'Start walking towards $initialRoad' : 'Start walking along campus route',
      'action': 'depart',
      'road': initialRoad,
      'index': 0,
      'distance': 0.0,
    });

    int lastManeuverIdx = 0;
    int i = 1;
    while (i < path.length - 1) {
      final midPoint = path[i];

      // Gate crossing detection
      if (distance(midPoint, gateMainPos) < 14 && (i - lastManeuverIdx) > 6) {
        steps.add({
          'text': 'Pass through Main Gate Entrance',
          'action': 'gate',
          'road': 'Main Gate Entrance',
          'index': i,
          'distance': distance(path[lastManeuverIdx], path[i]),
        });
        lastManeuverIdx = i;
        i += 4;
        continue;
      } else if (distance(midPoint, gateSouthPos) < 14 && (i - lastManeuverIdx) > 6) {
        steps.add({
          'text': 'Pass through Electrical Gate Entrance',
          'action': 'gate',
          'road': 'Electrical Gate Entrance',
          'index': i,
          'distance': distance(path[lastManeuverIdx], path[i]),
        });
        lastManeuverIdx = i;
        i += 4;
        continue;
      } else if (distance(midPoint, gateEastPos) < 14 && (i - lastManeuverIdx) > 6) {
        steps.add({
          'text': 'Pass through East Gate Entrance',
          'action': 'gate',
          'road': 'East Gate Entrance',
          'index': i,
          'distance': distance(path[lastManeuverIdx], path[i]),
        });
        lastManeuverIdx = i;
        i += 4;
        continue;
      }

      // Check angular change at vertex with 2-point lookback/lookahead
      int lookbackIdx = (i - 2).clamp(0, path.length - 1);
      int lookaheadIdx = (i + 2).clamp(0, path.length - 1);

      if (lookaheadIdx <= i || lookbackIdx >= i) {
        i++;
        continue;
      }

      final b1 = calculateBearing(path[lookbackIdx], path[i]);
      final b2 = calculateBearing(path[i], path[lookaheadIdx]);

      double turnAngle = b2 - b1;
      while (turnAngle > 180) {
        turnAngle -= 360;
      }
      while (turnAngle < -180) {
        turnAngle += 360;
      }

      final double segDistFromLast = distance(path[lastManeuverIdx], path[i]);

      if (turnAngle.abs() >= 25 && segDistFromLast >= 5.0) {
        final roadName = _getNearestRoadName(path[lookaheadIdx]);
        final roadSuffix = roadName.isNotEmpty ? ' onto $roadName' : '';

        String action;
        String text;

        if (turnAngle > 120) {
          action = 'turn_sharp_right';
          text = 'Make a sharp right turn$roadSuffix';
        } else if (turnAngle >= 35) {
          action = 'turn_right';
          text = 'Turn right$roadSuffix';
        } else if (turnAngle >= 18) {
          action = 'turn_slight_right';
          text = 'Turn slight right$roadSuffix';
        } else if (turnAngle < -120) {
          action = 'turn_sharp_left';
          text = 'Make a sharp left turn$roadSuffix';
        } else if (turnAngle <= -35) {
          action = 'turn_left';
          text = 'Turn left$roadSuffix';
        } else {
          action = 'turn_slight_left';
          text = 'Turn slight left$roadSuffix';
        }

        steps.add({
          'text': text,
          'action': action,
          'road': roadName,
          'index': i,
          'distance': segDistFromLast,
          'angle': turnAngle,
        });

        lastManeuverIdx = i;
        i += 3;
        continue;
      }

      i++;
    }

    steps.add({
      'text': 'Arrive at destination',
      'action': 'arrive',
      'road': 'Destination',
      'index': path.length - 1,
      'distance': distance(path[lastManeuverIdx], path.last),
    });

    return steps;
  }

  List<String> generateOfflineInstructions(List<LatLng> path) {
    if (path.length < 2) return ['Arrive at destination'];
    final steps = getDetailedManeuverSteps(path);
    return steps.map((s) => s['text'] as String).toList();
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
        {'text': "You have arrived.", 'index': 0, 'action': 'arrive'}
      ];
    }

    if (_lastParsedInstructions.isNotEmpty && _lastStepManeuverCoords.length == _lastParsedInstructions.length) {
      List<Map<String, dynamic>> result = [];
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
          'index': bestIdx.clamp(0, route.length - 1),
          'action': 'step',
        });
      }
      return result;
    }

    return getDetailedManeuverSteps(route);
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

  /// Smooths polyline curves using Chaikin's Corner-Cutting algorithm
  /// Gives a fluid, natural feel to campus roads while preserving exact endpoints and topology
  static List<LatLng> smoothPolyline(
    List<LatLng> points, {
    int iterations = 2,
    double tension = 0.22,
    double minSegmentLengthMeters = 2.0,
  }) {
    if (points.length < 3 || iterations <= 0) return List<LatLng>.from(points);

    List<LatLng> current = List<LatLng>.from(points);

    for (int iter = 0; iter < iterations; iter++) {
      final List<LatLng> smoothed = [current.first];

      for (int i = 0; i < current.length - 1; i++) {
        final p0 = current[i];
        final p1 = current[i + 1];

        final double dLat = p1.latitude - p0.latitude;
        final double dLng = p1.longitude - p0.longitude;

        final double latAvg = (p0.latitude + p1.latitude) * 0.5 * (pi / 180.0);
        final double dy = dLat * 111139.0;
        final double dx = dLng * 111139.0 * cos(latAvg);
        final double segDist = sqrt(dx * dx + dy * dy);

        if (segDist < minSegmentLengthMeters) {
          if (i > 0) smoothed.add(p0);
        } else {
          final q = LatLng(
            p0.latitude + dLat * tension,
            p0.longitude + dLng * tension,
          );
          final r = LatLng(
            p0.latitude + dLat * (1.0 - tension),
            p0.longitude + dLng * (1.0 - tension),
          );
          smoothed.add(q);
          smoothed.add(r);
        }
      }

      smoothed.add(current.last);
      current = smoothed;
    }

    return current;
  }
}

