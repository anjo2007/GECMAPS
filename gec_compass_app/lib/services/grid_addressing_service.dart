import 'dart:math';
import 'package:latlong2/latlong.dart';

class GridAddressingService {
  // GEC Thrissur SW Anchor Point (Origin for campus grid reference)
  static const double swLat = 10.5500;
  static const double swLng = 76.2150;
  static const double gridCellSizeMeters = 10.0;

  // GEC Thrissur Campus Geodesic Bounding Box (Lat/Lng)
  static const double campusMinLat = 10.5480;
  static const double campusMaxLat = 10.5620;
  static const double campusMinLng = 10.5500 > 0 ? 76.2150 : 76.2150;
  static const double campusMaxLng = 76.2360;

  /// Computes high-precision point-to-point distance in meters (Haversine/Geodesic)
  static double computeDistanceMeters(LatLng p1, LatLng p2) {
    const double r = 6371000.0; // Earth radius in meters
    final double dLat = _toRadians(p2.latitude - p1.latitude);
    final double dLng = _toRadians(p2.longitude - p1.longitude);

    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(p1.latitude)) *
            cos(_toRadians(p2.latitude)) *
            sin(dLng / 2) *
            sin(dLng / 2);

    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  /// Checks if a position is within the physical GEC Thrissur campus grid envelope
  static bool isInsideCampusGrid(LatLng point) {
    return point.latitude >= campusMinLat &&
        point.latitude <= campusMaxLat &&
        point.longitude >= swLng &&
        point.longitude <= campusMaxLng;
  }

  /// Generates a standard campus grid address string (e.g., GEC-E074-N052)
  static String getCampusGridAddress(LatLng point) {
    final double latDist = computeDistanceMeters(LatLng(swLat, point.longitude), point);
    final double lngDist = computeDistanceMeters(LatLng(point.latitude, swLng), point);

    final int eastingIndex = (lngDist / gridCellSizeMeters).floor();
    final int northingIndex = (latDist / gridCellSizeMeters).floor();

    return "GEC-E${eastingIndex.toString().padLeft(3, '0')}-N${northingIndex.toString().padLeft(3, '0')}";
  }

  /// Generates a sub-meter precision campus grid address string (e.g., GEC-E074.4-N052.8)
  static String getPrecisionGridAddress(LatLng point, {double resolutionMeters = 1.0}) {
    final double latDist = computeDistanceMeters(LatLng(swLat, point.longitude), point);
    final double lngDist = computeDistanceMeters(LatLng(point.latitude, swLng), point);

    final double eVal = lngDist / gridCellSizeMeters;
    final double nVal = latDist / gridCellSizeMeters;

    return "GEC-E${eVal.toStringAsFixed(1).padLeft(5, '0')}-N${nVal.toStringAsFixed(1).padLeft(5, '0')}";
  }

  /// Snaps a floating coordinate to the nearest geodesic grid quantization step
  /// to eliminate GPS/PDR micro-jitter while preserving true trajectory geometry.
  static LatLng snapToCampusGrid(LatLng point, {double resolutionMeters = 1.0}) {
    final double latDist = computeDistanceMeters(LatLng(swLat, point.longitude), point);
    final double lngDist = computeDistanceMeters(LatLng(point.latitude, swLng), point);

    final double snappedLatDist = (latDist / resolutionMeters).round() * resolutionMeters;
    final double snappedLngDist = (lngDist / resolutionMeters).round() * resolutionMeters;

    const double r = 6371000.0;
    final double dLat = snappedLatDist / r;
    final double targetLat = swLat + (dLat * 180.0 / pi);

    final double dLng = snappedLngDist / (r * cos(_toRadians(swLat)));
    final double targetLng = swLng + (dLng * 180.0 / pi);

    return LatLng(targetLat, targetLng);
  }

  /// Decodes a custom campus grid address string (e.g., GEC-E074-N052 or GEC-E074.4-N052.8) back into LatLng.
  static LatLng? getLatLngFromGridAddress(String address) {
    final regex = RegExp(r'^GEC-E(\d+(?:\.\d+)?)-N(\d+(?:\.\d+)?)$');
    final match = regex.firstMatch(address.toUpperCase().trim());
    if (match == null) return null;

    final double eVal = double.tryParse(match.group(1)!) ?? 0.0;
    final double nVal = double.tryParse(match.group(2)!) ?? 0.0;

    final double lngDist = eVal * gridCellSizeMeters;
    final double latDist = nVal * gridCellSizeMeters;

    const double r = 6371000.0;

    // Reverse Haversine approx for short distances
    final double dLat = latDist / r;
    final double targetLat = swLat + (dLat * 180.0 / pi);

    final double dLng = lngDist / (r * cos(_toRadians(swLat)));
    final double targetLng = swLng + (dLng * 180.0 / pi);

    return LatLng(targetLat, targetLng);
  }

  /// Calculates geodesic azimuth/bearing in degrees (0..360) from p1 to p2
  static double calculateGridBearing(LatLng p1, LatLng p2) {
    final double lat1 = _toRadians(p1.latitude);
    final double lat2 = _toRadians(p2.latitude);
    final double dLng = _toRadians(p2.longitude - p1.longitude);

    final double y = sin(dLng) * cos(lat2);
    final double x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng);
    return (atan2(y, x) * 180.0 / pi + 360.0) % 360.0;
  }

  static double _toRadians(double degree) => degree * pi / 180.0;
}
