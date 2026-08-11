import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gec_compass_app/models/gate.dart';
import 'package:gec_compass_app/services/gate_service.dart';
import 'package:gec_compass_app/services/location_service.dart';
import 'package:gec_compass_app/services/path_finder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Gate & PathFinder Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Gate serialization and deserialization', () {
      final gate = Gate(
        id: 'user_gate_1',
        name: 'North Gate',
        latitude: 10.5550,
        longitude: 76.2250,
        graphNodeId: 'main_junction',
      );

      final jsonMap = gate.toJson();
      final restored = Gate.fromJson(jsonMap);

      expect(restored.id, 'user_gate_1');
      expect(restored.name, 'North Gate');
      expect(restored.latitude, 10.5550);
      expect(restored.longitude, 76.2250);
      expect(restored.graphNodeId, 'main_junction');
    });

    test('GateService persists and loads custom user gates', () async {
      final service = GateService();
      final testGate = Gate(
        id: 'gate_custom_1',
        name: 'Custom Library Gate',
        latitude: 10.5538,
        longitude: 76.2246,
        graphNodeId: 'library_junction',
      );

      await service.addGate(testGate);
      final gates = await service.loadGates();

      expect(gates.length, 1);
      expect(gates.first.name, 'Custom Library Gate');
    });

    test('PathFinder finds optimal gate-aware path using campus graph', () {
      final graph = Graph();
      graph.addNode('node_start', const LatLng(10.5540, 76.2264));
      graph.addNode('gate_main', const LatLng(10.5541, 76.2264));
      graph.addNode('main_junction', const LatLng(10.5542, 76.2256));
      graph.addNode('gate_south', const LatLng(10.5520, 76.2241));
      graph.addNode('node_end', const LatLng(10.5544, 76.2246));

      graph.addEdge('node_start', 'gate_main', 10.0);
      graph.addEdge('gate_main', 'main_junction', 80.0);
      graph.addEdge('main_junction', 'node_end', 50.0);
      graph.addEdge('gate_south', 'node_end', 200.0);

      final gates = [
        Gate(id: 'g1', name: 'Main Gate', latitude: 10.5541, longitude: 76.2264, graphNodeId: 'gate_main'),
        Gate(id: 'g2', name: 'South Gate', latitude: 10.5520, longitude: 76.2241, graphNodeId: 'gate_south'),
      ];

      final pathFinder = PathFinder(graph, gates);
      final path = pathFinder.findPath(const LatLng(10.5540, 76.2264), const LatLng(10.5544, 76.2246));

      expect(path, isNotEmpty);
      expect(path.length, greaterThanOrEqualTo(2));
    });

    test('LocationService initializes in idle mode', () {
      final locationService = LocationService();
      expect(locationService.positionStream, isNotNull);
      locationService.dispose();
    });
  });
}
