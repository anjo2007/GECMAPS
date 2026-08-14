import 'package:flutter_test/flutter_test.dart';
import 'package:gec_compass_app/services/routing_service.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('RoutingService Bearing & Turn Instruction Tests', () {
    late RoutingService routingService;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      routingService = RoutingService();
    });

    test('calculateBearing returns 0 degrees due North', () {
      const p1 = LatLng(10.0, 76.0);
      const p2 = LatLng(10.1, 76.0);

      final bearing = routingService.calculateBearing(p1, p2);
      expect(bearing, closeTo(0.0, 0.1));
    });

    test('calculateBearing returns 90 degrees due East', () {
      const p1 = LatLng(10.0, 76.0);
      const p2 = LatLng(10.0, 76.1);

      final bearing = routingService.calculateBearing(p1, p2);
      expect(bearing, closeTo(90.0, 0.5));
    });

    test('generateOfflineInstructions creates turn instructions based on path angle deltas', () {
      final path = [
        const LatLng(10.554094, 76.226412), // Start at main gate
        const LatLng(10.554200, 76.225600), // Main junction
        const LatLng(10.553595, 76.224567), // Auditorium junction
        const LatLng(10.554418, 76.224668), // Target
      ];

      final instructions = routingService.generateOfflineInstructions(path);

      expect(instructions, isNotEmpty);
      expect(instructions.first, contains('Start walking'));
      expect(instructions.last, equals('Arrive at destination'));
    });

    test('getDetailedManeuverSteps identifies right and left turns accurately', () {
      // 90-degree right turn: Heading North (0 deg) then East (90 deg)
      final rightTurnPath = [
        const LatLng(10.550000, 76.220000),
        const LatLng(10.550100, 76.220000),
        const LatLng(10.550200, 76.220000),
        const LatLng(10.550300, 76.220000),
        const LatLng(10.550400, 76.220000),
        const LatLng(10.550500, 76.220000),
        const LatLng(10.550500, 76.220100),
        const LatLng(10.550500, 76.220200),
        const LatLng(10.550500, 76.220300),
        const LatLng(10.550500, 76.220400),
        const LatLng(10.550500, 76.220500),
      ];

      final steps = routingService.getDetailedManeuverSteps(rightTurnPath);
      expect(steps.any((s) => (s['text'] as String).toLowerCase().contains('turn right')), isTrue);

      // 90-degree left turn: Heading North (0 deg) then West (270 deg)
      final leftTurnPath = [
        const LatLng(10.550000, 76.220000),
        const LatLng(10.550100, 76.220000),
        const LatLng(10.550200, 76.220000),
        const LatLng(10.550300, 76.220000),
        const LatLng(10.550400, 76.220000),
        const LatLng(10.550500, 76.220000),
        const LatLng(10.550500, 76.219900),
        const LatLng(10.550500, 76.219800),
        const LatLng(10.550500, 76.219700),
        const LatLng(10.550500, 76.219600),
        const LatLng(10.550500, 76.219500),
      ];

      final leftSteps = routingService.getDetailedManeuverSteps(leftTurnPath);
      expect(leftSteps.any((s) => (s['text'] as String).toLowerCase().contains('turn left')), isTrue);
    });
  });
}
