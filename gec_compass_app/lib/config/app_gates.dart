import '../models/gate.dart';

/// Custom gates that supplement the default routing graph gates.
/// These match real nodes in the RoutingService waypoint graph.
final List<Gate> customGates = [
  Gate(
    id: 'gate_main',
    name: 'Main Gate Entrance',
    latitude: 10.5541214,
    longitude: 76.2264419,
    graphNodeId: 'gate_main',
    openHour: 0,
    closeHour: 24,
  ),
  Gate(
    id: 'gate_south',
    name: 'South Gate Entrance (Canteen)',
    latitude: 10.5520947,
    longitude: 76.2241280,
    graphNodeId: 'gate_south',
    openHour: 6,
    closeHour: 22,
  ),
  Gate(
    id: 'gate_east',
    name: 'East Gate Entrance (Electrical)',
    latitude: 10.5531511,
    longitude: 76.2264930,
    graphNodeId: 'gate_east',
    openHour: 7,
    closeHour: 20,
  ),
];
