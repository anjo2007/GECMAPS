import 'package:latlong2/latlong.dart';
import 'external_router.dart';
import 'internal_router.dart';
import 'routing_service.dart';

class AppExternalRouter implements ExternalRoutingService {
  final RoutingService routingService;

  AppExternalRouter(this.routingService);

  @override
  Future<ExternalRoute?> getRoute(LatLng from, LatLng to) async {
    final path = await routingService.tryOnlineOSRM(from, to);
    if (path == null || path.isEmpty) return null;

    final distance = getPathDistance(path);
    final duration = distance / 1.4; // assume 1.4 m/s walking speed

    return ExternalRoute(
      points: path,
      distanceMeters: distance,
      durationSeconds: duration,
    );
  }

  double getPathDistance(List<LatLng> path) {
    double dist = 0;
    for (int i = 0; i < path.length - 1; i++) {
      dist += routingService.distance(path[i], path[i + 1]);
    }
    return dist;
  }
}

class AppInternalRouter implements InternalRouter {
  final RoutingService routingService;

  AppInternalRouter(this.routingService);

  @override
  LatLng findNearestInternalPoint(LatLng target) {
    final snap = routingService.snapToNearestGraphEdge(target);
    return snap.snappedPoint;
  }

  @override
  Future<InternalRoute?> getInternalRoute(LatLng start, LatLng end) async {
    final startSnap = routingService.snapToNearestGraphEdge(start);
    final endSnap = routingService.snapToNearestGraphEdge(end);

    final candidateStartNodes = [startSnap.nodeA, startSnap.nodeB];
    final candidateEndNodes = [endSnap.nodeA, endSnap.nodeB];

    List<LatLng> bestPath = [];
    double minDistance = double.infinity;

    for (final sNode in candidateStartNodes) {
      for (final eNode in candidateEndNodes) {
        final subPath = routingService.getRouteBetweenWaypoints(sNode, eNode);
        if (subPath.isNotEmpty || sNode == eNode) {
          final candidate = [startSnap.snappedPoint];
          if (subPath.isNotEmpty) candidate.addAll(subPath);
          candidate.add(endSnap.snappedPoint);

          final candidateDist = _getPathDistance(candidate);
          if (candidateDist < minDistance) {
            minDistance = candidateDist;
            bestPath = candidate;
          }
        }
      }
    }

    if (bestPath.isEmpty) return null;

    return InternalRoute(
      points: bestPath,
      distanceMeters: minDistance,
      durationSeconds: minDistance / 1.4,
    );
  }

  double _getPathDistance(List<LatLng> path) {
    double dist = 0;
    for (int i = 0; i < path.length - 1; i++) {
      dist += routingService.distance(path[i], path[i + 1]);
    }
    return dist;
  }
}
