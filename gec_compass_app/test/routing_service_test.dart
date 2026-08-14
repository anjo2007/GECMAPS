import 'package:flutter_test/flutter_test.dart';
import 'package:gec_compass_app/services/routing_service.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('RoutingService Tests', () {
    late RoutingService routingService;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
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

      expect(closest.id, isNotEmpty);
      expect(closest.position.latitude, closeTo(10.5541, 0.001));
    });

    test('getRouteBetweenWaypoints returns Dijkstra path from start to end', () {
      final w1 = routingService.findClosestWaypoint(const LatLng(10.554094, 76.226412));
      final w2 = routingService.findClosestWaypoint(const LatLng(10.554418, 76.224668));
      final route = routingService.getRouteBetweenWaypoints(w1.id, w2.id);

      expect(route, isNotEmpty);
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
      if (routingService.waypoints.isNotEmpty) {
        final startId = routingService.waypoints.first.id;
        final visited = <String>{startId};
        final queue = <String>[startId];

        while (queue.isNotEmpty) {
          final curr = queue.removeAt(0);
          for (final nbr in routingService.graph[curr] ?? <String>[]) {
            if (!visited.contains(nbr)) {
              visited.add(nbr);
              queue.add(nbr);
            }
          }
        }

        expect(visited.length, equals(routingService.waypoints.length),
            reason: 'Road graph contains disconnected components');
      }
    });

    test('getFullRoute generates full snapped route from user location to target', () async {
      const userPos = LatLng(10.554094, 76.226412);
      const targetPos = LatLng(10.554418, 76.224668);

      final route = await routingService.getFullRoute(userPos, targetPos);
      expect(route, isNotEmpty);
      expect(route.first, userPos);
      expect(route.last, targetPos);
    });
  });
}
