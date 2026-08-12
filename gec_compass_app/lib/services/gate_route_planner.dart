import 'package:latlong2/latlong.dart';
import '../models/gate.dart';
import 'internal_router.dart';
import 'external_router.dart';

class GateRoutePlanner {
  final ExternalRoutingService externalRouter;
  final InternalRouter internalRouter;

  GateRoutePlanner({
    required this.externalRouter,
    required this.internalRouter,
  });

  Future<CombinedRoute?> computeRouteViaGate(
    LatLng origin,
    LatLng destination,
    Gate gate,
  ) async {
    final gatePos = LatLng(gate.latitude, gate.longitude);

    final external = await externalRouter.getRoute(origin, gatePos);
    if (external == null) return null;

    final snappedRoadPoint = external.points.last;
    final distSnappedToGate = const Distance().as(
      LengthUnit.Meter, snappedRoadPoint, gatePos,
    );

    final walkDuration1 = distSnappedToGate / 1.4;

    final nearestInternal = internalRouter.findNearestInternalPoint(gatePos);
    final distGateToInternal = const Distance().as(
      LengthUnit.Meter, gatePos, nearestInternal,
    );
    final walkDuration2 = distGateToInternal / 1.4;

    final internal = await internalRouter.getInternalRoute(
      nearestInternal, destination,
    );
    if (internal == null) return null;

    final combinedPoints = <LatLng>[
      ...external.points,
      gatePos,
      nearestInternal,
      ...internal.points,
    ];

    final totalDistance = external.distanceMeters +
        distSnappedToGate +
        distGateToInternal +
        internal.distanceMeters;

    final totalDuration = external.durationSeconds +
        walkDuration1 +
        walkDuration2 +
        internal.durationSeconds;

    return CombinedRoute(
      points: combinedPoints,
      distanceMeters: totalDistance,
      durationSeconds: totalDuration,
      segmentIsWalk: List.generate(combinedPoints.length - 1, (i) => false), // Simplification
    );
  }
}

class CombinedRoute {
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;
  final List<bool>? segmentIsWalk;

  CombinedRoute({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    this.segmentIsWalk,
  });
}
