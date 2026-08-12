import 'package:latlong2/latlong.dart';
import '../models/gate.dart';
import 'routing_service.dart';

class GateRoutePlanner {
  final RoutingService routingService;
  final double walkSpeed = 1.4; // m/s

  GateRoutePlanner({required this.routingService});

  /// Computes a route from [origin] to [destination] that passes through [gate].
  /// Returns a [CombinedRoute] or null if any segment fails.
  Future<CombinedRoute?> computeRouteViaGate(
    LatLng origin,
    LatLng destination,
    Gate gate,
  ) async {
    final gatePos = gate.position;

    // 1. Route from origin to gate (OSRM snaps gate to nearest road point)
    final external = await routingService.getRoute(origin, gatePos);
    if (external == null || external.points.isEmpty) return null;

    // The snapped road point is the last point of the external polyline
    final snappedPoint = external.points.last;

    // Distance between snapped road point and actual gate location
    final distToGate = const Distance().as(LengthUnit.Meter, snappedPoint, gatePos);
    final walkTime = distToGate / walkSpeed;

    // 2. Route from the same snapped point to the destination (internal roads)
    //    This uses OSRM as well, so it follows campus roads.
    final internal = await routingService.getRoute(snappedPoint, destination);
    if (internal == null || internal.points.isEmpty) return null;

    // 3. Combine the three legs:
    //    external polyline, a spur to the gate, back to the snapped point, then internal polyline
    final combinedPoints = <LatLng>[
      ...external.points,      // road to snapped point
      gatePos,                 // walk to gate
      snappedPoint,            // walk back to road
      ...internal.points,      // internal road to destination
    ];

    final totalDistance = external.distanceMeters +
        2 * distToGate +           // there and back
        internal.distanceMeters;

    final totalDuration = external.durationSeconds +
        2 * walkTime +
        internal.durationSeconds;

    return CombinedRoute(
      points: combinedPoints,
      distanceMeters: totalDistance,
      durationSeconds: totalDuration,
      gateName: gate.name,
      segmentIsWalk: List.generate(combinedPoints.length - 1, (i) => false),
    );
  }
}

class CombinedRoute {
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;
  final String? gateName;
  final List<bool>? segmentIsWalk;

  CombinedRoute({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    this.gateName,
    this.segmentIsWalk,
  });
}
