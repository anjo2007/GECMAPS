import 'dart:math';
import 'package:latlong2/latlong.dart';

class GridAddressingService {
  // GEC Thrissur SW Anchor Point (Origin for campus 10m grid)
  static const double swLat = 10.5500;
  static const double swLng = 76.2150;
  static const double gridCellSizeMeters = 10.0;

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

  /// Generates a custom campus grid address string (e.g., GEC-E074-N052)
  static String getCampusGridAddress(LatLng point) {
    final double latDist = computeDistanceMeters(LatLng(swLat, point.longitude), point);
    final double lngDist = computeDistanceMeters(LatLng(point.latitude, swLng), point);

    final int eastingIndex = (lngDist / gridCellSizeMeters).floor();
    final int northingIndex = (latDist / gridCellSizeMeters).floor();

    return "GEC-E${eastingIndex.toString().padLeft(3, '0')}-N${northingIndex.toString().padLeft(3, '0')}";
  }

  static double _toRadians(double degree) => degree * pi / 180.0;

  /// Decodes a custom campus grid address string (e.g., GEC-E074-N052) back into LatLng.
  static LatLng? getLatLngFromGridAddress(String address) {
    final regex = RegExp(r'^GEC-E(\d{3})-N(\d{3})$');
    final match = regex.firstMatch(address.toUpperCase());
    if (match == null) return null;
    
    final int eIndex = int.parse(match.group(1)!);
    final int nIndex = int.parse(match.group(2)!);
    
    final double lngDist = eIndex * gridCellSizeMeters;
    final double latDist = nIndex * gridCellSizeMeters;
    
    const double r = 6371000.0;
    
    // Reverse Haversine approx for short distances
    final double dLat = latDist / r;
    final double targetLat = swLat + (dLat * 180.0 / pi);
    
    final double dLng = lngDist / (r * cos(_toRadians(swLat)));
    final double targetLng = swLng + (dLng * 180.0 / pi);
    
    return LatLng(targetLat, targetLng);
  }
}
