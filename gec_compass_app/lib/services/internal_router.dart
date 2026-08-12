import 'package:latlong2/latlong.dart';

class InternalRoute {
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;

  InternalRoute({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
  });
}

abstract class InternalRouter {
  LatLng findNearestInternalPoint(LatLng target);
  Future<InternalRoute?> getInternalRoute(LatLng start, LatLng end);
}
