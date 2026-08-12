import 'package:latlong2/latlong.dart';

class Gate {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final String graphNodeId;
  final int openHour;
  final int closeHour;

  Gate({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.graphNodeId,
    this.openHour = 8,
    this.closeHour = 17,
  });

  LatLng get latLng => LatLng(latitude, longitude);

  bool get isOpenNow {
    final now = DateTime.now();
    return now.hour >= openHour && now.hour < closeHour;
  }

  factory Gate.fromJson(Map<String, dynamic> json) {
    return Gate(
      id: json['id'] as String? ?? 'gate_${json['graphNodeId'] ?? DateTime.now().millisecondsSinceEpoch}',
      name: json['name'] as String? ?? 'Campus Gate',
      latitude: ((json['latitude'] ?? json['lat']) as num).toDouble(),
      longitude: ((json['longitude'] ?? json['lng']) as num).toDouble(),
      graphNodeId: json['graphNodeId'] as String? ?? json['graph_node_id'] as String? ?? 'gate_main',
      openHour: json['openHour'] as int? ?? 8,
      closeHour: json['closeHour'] as int? ?? 17,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'graphNodeId': graphNodeId,
      'openHour': openHour,
      'closeHour': closeHour,
    };
  }
}
