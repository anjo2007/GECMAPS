import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:gec_compass_app/services/vps_sensor_fusion.dart';

void main() {
  group('VPSSensorFusionService Tests', () {
    late VPSSensorFusionService fusion;
    const startPos = LatLng(10.55274, 76.22202);

    setUp(() {
      fusion = VPSSensorFusionService();
      fusion.initialize(startPos, initialHeading: 90.0, floor: 1);
    });

    test('initialize sets correct initial state', () {
      final res = fusion.getFusedResult();
      expect(res.position, startPos);
      expect(res.floor, 1);
      expect(res.heading, 90.0);
      expect(res.mode, PositioningMode.gpsOnly);
    });

    test('processVisualAnchor snaps position with high confidence', () {
      const anchorPos = LatLng(10.55280, 76.22210);
      final res = fusion.processVisualAnchor(
        anchorPos: anchorPos,
        floor: 1,
        confidence: 0.98,
        name: 'CSE Lab 1',
        knownHeading: 180.0,
        rawCompassHeading: 45.0,
      );

      expect(res.position, anchorPos);
      expect(res.accuracyMeters, closeTo(0.2, 0.1));
      expect(res.confidenceScore, 0.98);
      expect(res.mode, PositioningMode.vpsLocked);
      expect(res.heading, 180.0);
    });

    test('updateGPS fuses GPS coordinates and calculates hybrid mode', () {
      const gpsPos = LatLng(10.55276, 76.22205);
      final res = fusion.updateGPS(
        gpsPos: gpsPos,
        accuracy: 3.5,
        speed: 1.2,
        gpsHeading: 92.0,
      );

      expect(res.position.latitude, isNotNull);
      expect(res.position.longitude, isNotNull);
      expect(res.confidenceScore, greaterThan(0.80));
    });

    test('updateGPS rejects multipath outlier jumps', () {
      const farOutlier = LatLng(10.56000, 76.23000); // ~1km away jump
      final initialRes = fusion.getFusedResult();

      final res = fusion.updateGPS(
        gpsPos: farOutlier,
        accuracy: 30.0,
        speed: 0.0,
      );

      // Outlier rejected; fused position remains unchanged
      expect(res.position, initialRes.position);
    });

    test('updatePDRStep advances position according to step length and heading', () {
      final initialPos = fusion.fusedPosition!;
      final res = fusion.updatePDRStep(
        stepLengthMeters: 0.70,
        rawCompassHeading: 90.0, // Moving East
      );

      expect(res.position.longitude, greaterThan(initialPos.longitude));
    });
  });
}
