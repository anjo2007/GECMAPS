class Building {
  final String id;
  final String name;
  final double lat;
  final double lng;
  final Map<String, dynamic> tags;

  Building({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.tags,
  });

  factory Building.fromJson(Map<String, dynamic> json) {
    return Building(
      id: json['id'] as String,
      name: json['name'] as String,
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      tags: json['tags'] != null ? Map<String, dynamic>.from(json['tags']) : {},
    );
  }
}
