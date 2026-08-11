import 'package:flutter_test/flutter_test.dart';
import 'package:gec_compass_app/services/routing_service.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('RoutingService Tests', () {
    late RoutingService routingService;

    setUp(() {
      routingService = RoutingService();
    });

    test('distance calculates accurate distance between two points', () {
      const pointA = LatLng(10.554094, 76.226412);
      const pointB = LatLng(10.554418, 76.224668);

      final dist = routingService.distance(pointA, pointB);
      expect(dist, greaterThan(0));
      expect(dist, lessThan(1000)); // Within 1 km inside campus
    });

    test('findClosestWaypoint finds the nearest waypoint accurately', () {
      const nearMainGate = LatLng(10.554090, 76.226410);
      final closest = routingService.findClosestWaypoint(nearMainGate);

      expect(closest.id, 'main_gate');
    });

    test('getRouteBetweenWaypoints returns Dijkstra path from start to end', () {
      final route = routingService.getRouteBetweenWaypoints('main_gate', 'main_building_front');

      expect(route, isNotEmpty);
      expect(route.first, const LatLng(10.554094, 76.226412));
      expect(route.last, const LatLng(10.554418, 76.224668));
    });

    test('road graph is symmetric and fully connected', () {
      final ids = routingService.waypoints.map((w) => w.id).toSet();

      // Check symmetry for every directed edge
      routingService.graph.forEach((a, nbrs) {
        for (final b in nbrs) {
          expect(ids.contains(b), isTrue, reason: '$a -> unknown node $b');
          expect(routingService.graph[b], contains(a),
              reason: 'asymmetric edge: $a -> $b has no reverse');
        }
      });

      // BFS connectivity test from first waypoint
      final seen = <String>{ids.first};
      final queue = [ids.first];
      while (queue.isNotEmpty) {
        final current = queue.removeLast();
        for (final n in routingService.graph[current] ?? []) {
          if (seen.add(n)) queue.add(n);
        }
      }
      expect(seen.length, ids.length, reason: 'graph has disconnected components');
    });

    test('getFullRoute generates full snapped route from user location to target', () async {
      const userLoc = LatLng(10.554000, 76.226400);
      const targetLoc = LatLng(10.554418, 76.224668);

      final route = await routingService.getFullRoute(userLoc, targetLoc);

      expect(route, isNotEmpty);
      expect(route.length, greaterThanOrEqualTo(2));
    });
  });
}
