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

    test('getPrecisionGridAddress generates sub-meter resolution address', () {
      const p = LatLng(10.555761, 76.224317);
      final address = GridAddressingService.getPrecisionGridAddress(p);

      expect(address, startsWith('GEC-E'));
      expect(address, contains('.'));
    });

    test('isInsideCampusGrid correctly classifies campus positions', () {
      const insidePos = LatLng(10.5540, 76.2250);
      const outsidePos = LatLng(11.0000, 77.0000);

      expect(GridAddressingService.isInsideCampusGrid(insidePos), true);
      expect(GridAddressingService.isInsideCampusGrid(outsidePos), false);
    });

    test('snapToCampusGrid reduces coordinate jitter while retaining proximity', () {
      const original = LatLng(10.554321, 76.225432);
      final snapped = GridAddressingService.snapToCampusGrid(original, resolutionMeters: 1.0);

      final diffMeters = GridAddressingService.computeDistanceMeters(original, snapped);
      expect(diffMeters, lessThanOrEqualTo(1.0));
    });

    test('getLatLngFromGridAddress decodes address back into LatLng accurately', () {
      const p = LatLng(10.5550, 76.2200);
      final code = GridAddressingService.getCampusGridAddress(p);
      final decoded = GridAddressingService.getLatLngFromGridAddress(code);

      expect(decoded, isNotNull);
      final dist = GridAddressingService.computeDistanceMeters(p, decoded!);
      expect(dist, lessThan(15.0)); // within 1 cell (10m)
    });
  });
}
