import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:gec_compass_app/services/grid_addressing_service.dart';

void main() {
  group('GridAddressingService Unit Tests', () {
    test('computeDistanceMeters returns precise geodesic distance', () {
      const p1 = LatLng(10.555761, 76.224317);
      const p2 = LatLng(10.556000, 76.224500);

      final dist = GridAddressingService.computeDistanceMeters(p1, p2);
      expect(dist, greaterThan(0));
      expect(dist, lessThan(100.0));
    });

    test('getCampusGridAddress returns formatted GEC grid code', () {
      const p = LatLng(10.555761, 76.224317);
      final address = GridAddressingService.getCampusGridAddress(p);

      expect(address, startsWith('GEC-E'));
      expect(address, contains('-N'));
    });
  });
}
