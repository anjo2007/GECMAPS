import 'package:latlong2/latlong.dart';

class Gate {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final String graphNodeId;

  Gate({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.graphNodeId,
  });

  LatLng get latLng => LatLng(latitude, longitude);

  factory Gate.fromJson(Map<String, dynamic> json) {
    return Gate(
      id: json['id'] as String? ?? 'gate_${json['graphNodeId'] ?? DateTime.now().millisecondsSinceEpoch}',
      name: json['name'] as String? ?? 'Campus Gate',
      latitude: ((json['latitude'] ?? json['lat']) as num).toDouble(),
      longitude: ((json['longitude'] ?? json['lng']) as num).toDouble(),
      graphNodeId: json['graphNodeId'] as String? ?? json['graph_node_id'] as String? ?? 'gate_main',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'graphNodeId': graphNodeId,
    };
  }
}
