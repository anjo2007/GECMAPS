import 'package:latlong2/latlong.dart';
import '../models/gate.dart';

final List<Gate> customGates = [
  Gate(
    id: 'gate_main',
    name: 'Main Gate Entrance',
    position: const LatLng(10.5541214, 76.2264419),
    graphNodeId: 'gate_main',
    openHour: 0,
    closeHour: 24,
  ),
  Gate(
    id: 'gate_south',
    name: 'South Gate Entrance (Canteen)',
    position: const LatLng(10.5520947, 76.2241280),
    graphNodeId: 'gate_south',
    openHour: 6,
    closeHour: 22,
  ),
  Gate(
    id: 'gate_east',
    name: 'East Gate Entrance (Electrical)',
    position: const LatLng(10.5531511, 76.2264930),
    graphNodeId: 'gate_east',
    openHour: 7,
    closeHour: 20,
  ),
];
