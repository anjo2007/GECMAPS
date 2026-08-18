import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:gec_compass_app/services/routing_service.dart';
import 'package:gec_compass_app/models/building.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Campus Roads & Graph Connectivity Tests', () {
    test('campus_roads.json exists and contains complete road network', () async {
      final file = File('assets/campus_roads.json');
      expect(file.existsSync(), isTrue);
      final jsonStr = await file.readAsString();
      final data = json.decode(jsonStr) as Map<String, dynamic>;
      
      expect(data['type'], equals('FeatureCollection'));
      final features = data['features'] as List<dynamic>;
      expect(features, isNotEmpty);

      final nodes = data['nodes'] as List<dynamic>;
      final edges = data['edges'] as List<dynamic>;

      expect(nodes.length, equals(247));
      expect(edges.length, equals(273));
    });

    test('RoutingService initializes campus road graph properly', () async {
      final routingService = RoutingService();
      final file = File('assets/campus_roads.json');
      final jsonStr = await file.readAsString();
      routingService.loadCampusRoadsFromJsonString(jsonStr);

      expect(routingService.roadNodes.length, greaterThanOrEqualTo(247));
      expect(routingService.roadAdjacency.length, greaterThanOrEqualTo(247));
    });

    test('RoutingService finds single optimal path between campus locations', () async {
      final routingService = RoutingService();
      final file = File('assets/campus_roads.json');
      final jsonStr = await file.readAsString();
      routingService.loadCampusRoadsFromJsonString(jsonStr);

      // Main Gate to Mechanical Department
      final start = const LatLng(10.5541214, 76.2264419);
      final end = const LatLng(10.553250, 76.224850);

      final route = await routingService.getDetailedRoute(start, end);
      expect(route.fullPath.length, greaterThanOrEqualTo(2));
      expect(route.roadPath, isNotEmpty);
      expect(route.distanceMeters, greaterThan(0));
    });

    test('RoutingService selects optimal Electrical Gate for south entrance to West campus', () async {
      final routingService = RoutingService();
      final file = File('assets/campus_roads.json');
      final jsonStr = await file.readAsString();
      routingService.loadCampusRoadsFromJsonString(jsonStr);

      // White House Hostel (south) to Post Graduate Block (west campus)
      const southStart = LatLng(10.550500, 76.224100);
      const westDestination = LatLng(10.553440, 76.220577);

      // Daytime route when Electrical Gate is open (08:00 AM - 05:30 PM)
      final daytime = DateTime(2026, 8, 14, 10, 0);
      final route = await routingService.getDetailedRoute(southStart, westDestination, currentTime: daytime);
      expect(route.fullPath, isNotEmpty);
      expect(route.activeGateName, contains('Electrical Gate'));
      // Direct optimal route should be < 800m (not the 1.8km detour around the outside)
      expect(route.distanceMeters, lessThan(800.0));
    });
  });

  group('Gate Schedule & Dynamic Rerouting Notice Tests', () {
    test('isGateOpenNow correctly evaluates open/closed schedules', () {
      // 24/7 Gate
      expect(RoutingService.isGateOpenNow('24/7', '24/7'), isTrue);

      // Day schedule (06:00 AM to 10:30 PM)
      final morning = DateTime(2026, 8, 14, 10, 0); // 10:00 AM
      final night = DateTime(2026, 8, 14, 23, 30); // 11:30 PM (after 10:30 PM)
      final earlyMorning = DateTime(2026, 8, 14, 4, 30); // 4:30 AM (before 6:00 AM)

      expect(RoutingService.isGateOpenNow('06:00 AM', '10:30 PM', now: morning), isTrue);
      expect(RoutingService.isGateOpenNow('06:00 AM', '10:30 PM', now: night), isFalse);
      expect(RoutingService.isGateOpenNow('06:00 AM', '10:30 PM', now: earlyMorning), isFalse);

      // Midnight crossover schedule (08:00 PM to 06:00 AM)
      final lateNight = DateTime(2026, 8, 14, 23, 0); // 11:00 PM
      final noon = DateTime(2026, 8, 14, 12, 0); // 12:00 PM
      expect(RoutingService.isGateOpenNow('08:00 PM', '06:00 AM', now: lateNight), isTrue);
      expect(RoutingService.isGateOpenNow('08:00 PM', '06:00 AM', now: noon), isFalse);
    });

    test('getGateStatusLabel generates clear badges', () {
      final morning = DateTime(2026, 8, 14, 10, 0);
      final night = DateTime(2026, 8, 14, 23, 30);

      final openLabel = RoutingService.getGateStatusLabel('06:00 AM', '10:30 PM', now: morning);
      expect(openLabel, contains('Open'));
      expect(openLabel, contains('10:30 PM'));

      final closedLabel = RoutingService.getGateStatusLabel('06:00 AM', '10:30 PM', now: night);
      expect(closedLabel, contains('Closed'));
      expect(closedLabel, contains('6:00 AM'));
    });

    test('Routing evaluates gates considering open/closed status', () async {
      final routingService = RoutingService();
      final file = File('assets/campus_roads.json');
      final jsonStr = await file.readAsString();
      routingService.loadCampusRoadsFromJsonString(jsonStr);

      final customGates = [
        Building(
          id: 'gate_main',
          name: 'Main Gate',
          lat: 10.5541214,
          lng: 76.2264419,
          tags: {
            'barrier': 'gate',
            'opening_time': '06:00 AM',
            'closing_time': '10:30 PM',
          },
        ),
        Building(
          id: 'gate_south',
          name: 'Electrical Gate',
          lat: 10.5520947,
          lng: 76.2241280,
          tags: {
            'barrier': 'gate',
            'opening_time': '08:00 AM',
            'closing_time': '05:30 PM',
          },
        ),
      ];

      // External user point outside Electrical Gate
      final outsidePos = const LatLng(10.550500, 76.224000);
      final campusTarget = const LatLng(10.553250, 76.224850);

      // Route at 10:00 PM (Electrical gate closed at 5:30 PM, Main gate still open until 10:30 PM)
      final at10pm = DateTime(2026, 8, 14, 22, 0);
      final bestGate = routingService.selectOptimalGate(
        outsidePos,
        campusTarget,
        customGates: customGates,
        now: at10pm,
      );

      // Should choose Main Gate because Electrical Gate is closed
      expect(bestGate.id, equals('gate_main'));
    });

    test('getDetailedRoute provides gate closure notice when primary gate is closed', () async {
      final routingService = RoutingService();
      final file = File('assets/campus_roads.json');
      final jsonStr = await file.readAsString();
      routingService.loadCampusRoadsFromJsonString(jsonStr);

      // Point outside East Gate
      const outsideEastPos = LatLng(10.553150, 76.228000);
      const internalDestination = LatLng(10.554418, 76.224668);

      // East gate closes at 09:00 PM. Check route at 09:45 PM (Main gate is still open)
      final at945pm = DateTime(2026, 8, 14, 21, 45);
      final route = await routingService.getDetailedRoute(
        outsideEastPos,
        internalDestination,
        currentTime: at945pm,
      );

      expect(route.fullPath, isNotEmpty);
      expect(route.gateClosureNotice, isNotNull);
      expect(route.gateClosureNotice, contains('closed'));
      expect(route.bypassedClosedGateName, contains('East Gate'));
      expect(route.activeGateName, contains('Main Gate'));

      // Verify the generated polyline actually routes through Main Gate (10.55412, 76.22644)
      const mainGatePos = LatLng(10.5541214, 76.2264419);
      final passesMainGate = route.fullPath.any((p) => routingService.distance(p, mainGatePos) < 15.0);
      expect(passesMainGate, isTrue);
    });

    test('navigating between two points inside campus gives direct point-to-point route without gates', () async {
      final routingService = RoutingService();
      final file = File('assets/campus_roads.json');
      final jsonStr = await file.readAsString();
      routingService.loadCampusRoadsFromJsonString(jsonStr);

      // Starting from Mechanical Dept, destination is Central Library
      const internalStart = LatLng(10.554418, 76.224668);
      const internalDestination = LatLng(10.553595, 76.224567);

      // Even at 11:00 PM when all gates are closed, internal routing works directly
      final at11pm = DateTime(2026, 8, 14, 23, 0);
      final route = await routingService.getDetailedRoute(
        internalStart,
        internalDestination,
        currentTime: at11pm,
      );

      expect(route.fullPath, isNotEmpty);
      expect(route.gateClosureNotice, isNull);
      expect(route.bypassedClosedGateName, isNull);

      // Verify route ends at the internal destination, not any gate
      final endsNearDest = routingService.distance(route.fullPath.last, internalDestination) < 15.0;
      expect(endsNearDest, isTrue);
    });
  });

  group('Road Curve Smoothing Tests', () {
    test('smoothPolyline rounds sharp corners into fluid curves', () {
      // 90-degree corner at (10.5540, 76.2250)
      final original = [
        const LatLng(10.554000, 76.224000),
        const LatLng(10.554000, 76.225000),
        const LatLng(10.555000, 76.225000),
      ];

      final smoothed = RoutingService.smoothPolyline(original, iterations: 2);

      // Should have more points creating a smooth transition
      expect(smoothed.length, greaterThan(original.length));
      // Endpoints must match original start and destination precisely
      expect(smoothed.first, equals(original.first));
      expect(smoothed.last, equals(original.last));
    });

    test('smoothPolyline handles short or empty paths safely', () {
      final single = [const LatLng(10.554000, 76.224000)];
      expect(RoutingService.smoothPolyline(single), equals(single));

      final twoPoints = [
        const LatLng(10.554000, 76.224000),
        const LatLng(10.554000, 76.225000),
      ];
      expect(RoutingService.smoothPolyline(twoPoints), equals(twoPoints));
    });
  });
}
