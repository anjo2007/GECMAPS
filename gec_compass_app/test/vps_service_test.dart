import 'package:flutter_test/flutter_test.dart';
import 'package:gec_compass_app/services/vps_relocalization_service.dart';

void main() {
  group('VPSRelocalizationService Unit Tests', () {
    late VPSRelocalizationService vpsService;

    setUp(() {
      vpsService = VPSRelocalizationService();
    });

    test('parsePayload parses vps:// URI payload accurately', () {
      const uriStr = 'vps://room?name=CSE%20Lab%201&lat=10.55274&lng=76.22202&floor=2';
      final result = vpsService.parsePayload(uriStr);

      expect(result.isSuccess, true);
      expect(result.locationName, 'CSE Lab 1');
      expect(result.position.latitude, 10.55274);
      expect(result.position.longitude, 76.22202);
      expect(result.floor, 2);
      expect(result.confidenceScore, 0.98);
    });

    test('parsePayload parses JSON VPS payload accurately', () {
      const jsonStr = '{"name": "Auditorium", "lat": 10.553595, "lng": 76.224567, "floor": 0}';
      final result = vpsService.parsePayload(jsonStr);

      expect(result.isSuccess, true);
      expect(result.locationName, 'Auditorium');
      expect(result.position.latitude, 10.553595);
      expect(result.position.longitude, 76.224567);
      expect(result.confidenceScore, 0.96);
    });

    test('calculateConfidenceScore returns expected blended confidence value', () {
      final score = vpsService.calculateConfidenceScore(
        qrMatched: true,
        ocrMatched: false,
        slamPointsCount: 40,
        sensorStability: 0.8,
      );

      expect(score, greaterThanOrEqualTo(0.60));
      expect(score, lessThanOrEqualTo(1.0));
    });
  });
}
