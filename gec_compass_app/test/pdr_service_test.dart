import 'package:flutter_test/flutter_test.dart';
import 'package:gec_compass_app/services/pdr_service.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('PDRService Tests', () {
    late PDRService pdrService;

    setUp(() {
      pdrService = PDRService();
    });

    tearDown(() {
      pdrService.stopPDR();
    });

    test('updateGPSPosition initializes position when current position is null', () {
      const initialPos = LatLng(10.5540, 76.2264);
      LatLng? updatedPos;

      pdrService.onPositionUpdated = (pos) {
        updatedPos = pos;
      };

      pdrService.updateGPSPosition(initialPos, 3.0, 1.2, 90.0);

      expect(updatedPos, equals(initialPos));
    });

    test('updateGPSPosition blends GPS and PDR coordinates using sensor fusion weighting', () {
      const startPos = LatLng(10.5540, 76.2264);
      const newGpsPos = LatLng(10.5542, 76.2266);
      LatLng? resultPos;

      pdrService.updateGPSPosition(startPos, 3.0, 1.0, 0.0);
      pdrService.onPositionUpdated = (pos) {
        resultPos = pos;
      };

      // Medium accuracy (alpha = 0.45 for accuracy=4.0)
      pdrService.updateGPSPosition(newGpsPos, 4.0, 1.0, 0.0);

      expect(resultPos, isNotNull);
      expect(resultPos!.latitude, closeTo(10.55409, 0.00005));
      expect(resultPos!.longitude, closeTo(76.22649, 0.00005));
    });
  });
}
