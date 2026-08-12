import 'package:latlong2/latlong.dart';

class ExternalRoute {
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;

  ExternalRoute({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
  });
}

abstract class ExternalRoutingService {
  Future<ExternalRoute?> getRoute(LatLng from, LatLng to);
}
