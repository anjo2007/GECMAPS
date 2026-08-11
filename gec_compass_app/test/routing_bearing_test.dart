import 'package:flutter_test/flutter_test.dart';
import 'package:gec_compass_app/services/routing_service.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('RoutingService Bearing & Turn Instruction Tests', () {
    late RoutingService routingService;

    setUp(() {
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
  });
}
