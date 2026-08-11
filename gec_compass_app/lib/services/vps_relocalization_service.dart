import 'dart:convert';
import 'package:latlong2/latlong.dart';
import 'vps_sensor_fusion.dart';

class VPSRelocalizationResult {
  final LatLng position;
  final int floor;
  final double confidenceScore; // 0.0 to 1.0
  final String locationName;
  final bool isSuccess;
  final String message;
  final double? heading;

  VPSRelocalizationResult({
    required this.position,
    required this.floor,
    required this.confidenceScore,
    required this.locationName,
    required this.isSuccess,
    required this.message,
    this.heading,
  });
}

class VPSRelocalizationService {
  final VPSSensorFusionService sensorFusion = VPSSensorFusionService();

  /// Validate that parsed coordinates are finite and within valid geographic range
  bool _isValidCoordinate(double? lat, double? lng) {
    if (lat == null || lng == null) return false;
    if (lat.isNaN || lat.isInfinite || lng.isNaN || lng.isInfinite) return false;
    if (lat < -90.0 || lat > 90.0) return false;
    if (lng < -180.0 || lng > 180.0) return false;
    if (lat == 0.0 && lng == 0.0) return false;
    // Campus bounding box validation (GEC Thrissur region)
    if (lat < 10.5300 || lat > 10.5700 || lng < 76.2000 || lng > 76.2500) return false;
    return true;
  }

  /// Parse raw scanned QR string or OCR text into VPS positioning result
  VPSRelocalizationResult parsePayload(String rawCode, {double rawCompassHeading = 0.0}) {
    if (rawCode.isEmpty) {
      return VPSRelocalizationResult(
        position: const LatLng(0, 0),
        floor: 0,
        confidenceScore: 0.0,
        locationName: 'Unknown',
        isSuccess: false,
        message: 'Empty VPS code scanned',
      );
    }

    // Scheme 1: URI format "vps://room?name=CSE%20Lab%201&lat=10.55274&lng=76.22202&floor=1&heading=90"
    if (rawCode.startsWith('vps://')) {
      try {
        final uri = Uri.parse(rawCode);
        final name = uri.queryParameters['name'] ?? 'VPS Node';
        final lat = double.tryParse(uri.queryParameters['lat'] ?? '');
        final lng = double.tryParse(uri.queryParameters['lng'] ?? '');
        final floor = int.tryParse(uri.queryParameters['floor'] ?? '0') ?? 0;
        final heading = double.tryParse(uri.queryParameters['heading'] ?? '');

        if (_isValidCoordinate(lat, lng)) {
          final pos = LatLng(lat!, lng!);
          sensorFusion.processVisualAnchor(
            anchorPos: pos,
            floor: floor,
            confidence: 0.98,
            name: name,
            knownHeading: heading,
            rawCompassHeading: rawCompassHeading,
          );

          return VPSRelocalizationResult(
            position: pos,
            floor: floor,
            confidenceScore: 0.98,
            locationName: name,
            isSuccess: true,
            message: 'VPS QR Relocalized! Sensor Fused Accuracy ±0.2m',
            heading: heading,
          );
        }
      } catch (_) {}
    }

    // Scheme 2: JSON payload {"name": "Main Office", "lat": 10.5544, "lng": 76.2246, "floor": 0, "heading": 180}
    if (rawCode.trim().startsWith('{')) {
      try {
        final map = json.decode(rawCode) as Map<String, dynamic>;
        final name = map['name'] as String? ?? 'VPS Node';
        double? lat;
        double? lng;
        double? heading;
        if (map['lat'] is num) {
          lat = (map['lat'] as num).toDouble();
        } else if (map['lat'] is String) {
          lat = double.tryParse(map['lat'] as String);
        }
        if (map['lng'] is num) {
          lng = (map['lng'] as num).toDouble();
        } else if (map['lng'] is String) {
          lng = double.tryParse(map['lng'] as String);
        }
        if (map['heading'] is num) {
          heading = (map['heading'] as num).toDouble();
        } else if (map['heading'] is String) {
          heading = double.tryParse(map['heading'] as String);
        }
        final floor = (map['floor'] is num) ? (map['floor'] as num).toInt() : int.tryParse(map['floor']?.toString() ?? '0') ?? 0;

        if (_isValidCoordinate(lat, lng)) {
          final pos = LatLng(lat!, lng!);
          sensorFusion.processVisualAnchor(
            anchorPos: pos,
            floor: floor,
            confidence: 0.96,
            name: name,
            knownHeading: heading,
            rawCompassHeading: rawCompassHeading,
          );

          return VPSRelocalizationResult(
            position: pos,
            floor: floor,
            confidenceScore: 0.96,
            locationName: name,
            isSuccess: true,
            message: 'VPS JSON Relocalized! Sensor Fused Accuracy ±0.2m',
            heading: heading,
          );
        }
      } catch (_) {}
    }

    // Fallback: Text anchor identification
    return VPSRelocalizationResult(
      position: const LatLng(0, 0),
      floor: 0,
      confidenceScore: 0.40,
      locationName: rawCode,
      isSuccess: false,
      message: 'Scanned text detected: "$rawCode". Searching spatial map...',
    );
  }

  /// Calculate combined VPS confidence score based on sensor stability & visual features
  double calculateConfidenceScore({
    required bool qrMatched,
    required bool ocrMatched,
    required int slamPointsCount,
    required double sensorStability, // 0.0 (jittery) to 1.0 (stable)
  }) {
    double score = 0.0;
    if (qrMatched) score += 0.60;
    if (ocrMatched) score += 0.25;

    final slamBonus = (slamPointsCount / 50.0).clamp(0.0, 1.0) * 0.10;
    score += slamBonus;

    final stability = sensorStability.isFinite ? sensorStability.clamp(0.0, 1.0) : 0.0;
    score += (stability * 0.05);

    return score.clamp(0.0, 1.0);
  }
}
