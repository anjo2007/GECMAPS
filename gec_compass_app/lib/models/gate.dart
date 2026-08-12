import 'package:latlong2/latlong.dart';

class Gate {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final String graphNodeId;
  final int openHour;   // 8
  final int closeHour;  // 17

  Gate({
    String? id,
    required this.name,
    LatLng? position,
    double? latitude,
    double? longitude,
    String? graphNodeId,
    this.openHour = 8,
    this.closeHour = 17,
  })  : latitude = latitude ?? position?.latitude ?? 0.0,
        longitude = longitude ?? position?.longitude ?? 0.0,
        id = id ?? 'gate_${graphNodeId ?? name.replaceAll(' ', '_')}',
        graphNodeId = graphNodeId ?? id ?? name.replaceAll(' ', '_');

  LatLng get position => LatLng(latitude, longitude);
  LatLng get latLng => LatLng(latitude, longitude);

  bool get isOpenNow {
    final now = DateTime.now();
    return now.hour >= openHour && now.hour < closeHour;
  }

  factory Gate.fromJson(Map<String, dynamic> json) {
    final lat = ((json['latitude'] ?? json['lat']) as num).toDouble();
    final lng = ((json['longitude'] ?? json['lng']) as num).toDouble();
    return Gate(
      id: json['id'] as String? ?? 'gate_${json['graphNodeId'] ?? DateTime.now().millisecondsSinceEpoch}',
      name: json['name'] as String? ?? 'Campus Gate',
      latitude: lat,
      longitude: lng,
      position: LatLng(lat, lng),
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
