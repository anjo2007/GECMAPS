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
      expect(dist, lessThan(8.0)); // centered within 10m cell (max diagonal offset is ~7.07m)
    });

    test('getLatLngFromGridAddress decodes precision grid address with sub-meter accuracy', () {
      const p = LatLng(10.554094, 76.226412);
      final precisionCode = GridAddressingService.getPrecisionGridAddress(p);
      final decoded = GridAddressingService.getLatLngFromGridAddress(precisionCode);

      expect(decoded, isNotNull);
      final dist = GridAddressingService.computeDistanceMeters(p, decoded!);
      expect(dist, lessThan(1.0)); // sub-meter accuracy
    });

    test('getLatLngFromGridAddress decodes flexible input formats', () {
      final formats = [
        'GEC-E074-N052',
        'gec-e074-n052',
        'E074-N052',
        'e74-n52',
        'E74 N52',
        'GEC E074 N052',
        'E074, N052',
        'GEC-E074.4-N052.8',
        'e74.4 n52.8',
      ];

      for (final fmt in formats) {
        final decoded = GridAddressingService.getLatLngFromGridAddress(fmt);
        expect(decoded, isNotNull, reason: 'Failed to decode format: $fmt');
        expect(decoded!.latitude, greaterThan(10.5480));
        expect(decoded.latitude, lessThan(10.5620));
        expect(decoded.longitude, greaterThan(76.2150));
        expect(decoded.longitude, lessThan(76.2360));
      }
    });
  });
}
