class Building {
  final String id;
  final String name;
  final double lat;
  final double lng;
  final Map<String, dynamic> tags;
  final String? photoBase64;
  final String? vpsBoardPhotoBase64;
  final String? photoUrl;
  final String? vpsBoardPhotoUrl;
  final bool isDeleted;

  Building({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.tags,
    this.photoBase64,
    this.vpsBoardPhotoBase64,
    String? photoUrl,
    String? vpsBoardPhotoUrl,
    this.isDeleted = false,
  })  : photoUrl = (photoUrl != null && photoUrl.isNotEmpty) ? photoUrl : photoBase64,
        vpsBoardPhotoUrl = (vpsBoardPhotoUrl != null && vpsBoardPhotoUrl.isNotEmpty) ? vpsBoardPhotoUrl : vpsBoardPhotoBase64;

  factory Building.fromJson(Map<String, dynamic> json) {
    final rawPhoto = json['photoUrl'] as String? ??
        json['photo'] as String? ??
        json['photoBase64'] as String? ??
        json['tags']?['image'] as String? ??
        json['tags']?['photoUrl'] as String?;
    final rawVps = json['vpsBoardPhotoUrl'] as String? ??
        json['vpsBoardPhoto'] as String? ??
        json['vpsBoardPhotoBase64'] as String? ??
        json['tags']?['vpsBoardPhotoUrl'] as String?;
    final deleted = json['deleted'] == true ||
        json['deleted'] == 'true' ||
        json['tags']?['deleted'] == true ||
        json['tags']?['deleted'] == 'true';

    final cleanTags = json['tags'] != null ? Map<String, dynamic>.from(json['tags']) : <String, dynamic>{};
    // Strip redundant image copies from tags to save memory and storage
    cleanTags.remove('image');
    cleanTags.remove('photoUrl');
    cleanTags.remove('photoBase64');
    cleanTags.remove('vpsBoardPhotoUrl');
    cleanTags.remove('vpsBoardPhotoBase64');

    return Building(
      id: json['id']?.toString() ?? '',
      name: json['name'] as String? ?? '',
      lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0.0,
      tags: cleanTags,
      photoBase64: rawPhoto,
      vpsBoardPhotoBase64: rawVps,
      photoUrl: rawPhoto,
      vpsBoardPhotoUrl: rawVps,
      isDeleted: deleted,
    );
  }

  Map<String, dynamic> toJson() {
    final mainPhoto = (photoUrl != null && photoUrl!.isNotEmpty) ? photoUrl : photoBase64;
    final vpsPhoto = (vpsBoardPhotoUrl != null && vpsBoardPhotoUrl!.isNotEmpty) ? vpsBoardPhotoUrl : vpsBoardPhotoBase64;
    final cleanTags = Map<String, dynamic>.from(tags);
    cleanTags.remove('image');
    cleanTags.remove('photoUrl');
    cleanTags.remove('photoBase64');
    cleanTags.remove('vpsBoardPhotoUrl');
    cleanTags.remove('vpsBoardPhotoBase64');

    return {
      'id': id,
      'name': name,
      'lat': lat,
      'lng': lng,
      'tags': cleanTags,
      if (isDeleted) 'deleted': true,
      if (mainPhoto != null && mainPhoto.isNotEmpty) 'photoUrl': mainPhoto,
      if (vpsPhoto != null && vpsPhoto.isNotEmpty) 'vpsBoardPhotoUrl': vpsPhoto,
    };
  }
}
