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

      // High accuracy (alpha = 0.60 for accuracy 4.0)
      pdrService.updateGPSPosition(newGpsPos, 4.0, 1.0, 0.0);

      expect(resultPos, isNotNull);
      expect(resultPos!.latitude, closeTo(10.55412, 0.0001));
      expect(resultPos!.longitude, closeTo(76.22652, 0.0001));
    });

    test('calibrateGpsBias offsets incoming GPS coordinates towards ground truth', () {
      const rawGps = LatLng(10.5540, 76.2260);
      LatLng? resultPos;

      pdrService.forceSetPosition(const LatLng(10.5541, 76.2261));
      pdrService.onPositionUpdated = (pos) {
        resultPos = pos;
      };

      // Calibrate GPS with +0.0001 lat and +0.0001 lng bias correction
      pdrService.calibrateGpsBias(0.0001, 0.0001);
      pdrService.updateGPSPosition(rawGps, 2.0, 1.0, 0.0);

      expect(resultPos, isNotNull);
      expect(resultPos!.latitude, greaterThan(rawGps.latitude));
      expect(resultPos!.longitude, greaterThan(rawGps.longitude));
    });

    test('forceSetPosition overrides current position and notifies listener', () {
      const forcedPos = LatLng(10.5535, 76.2245);
      LatLng? resultPos;

      pdrService.onPositionUpdated = (pos) {
        resultPos = pos;
      };

      pdrService.forceSetPosition(forcedPos);
      expect(resultPos, equals(forcedPos));
    });
  });
}
