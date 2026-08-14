import 'package:flutter_test/flutter_test.dart';
import 'package:gec_compass_app/models/building.dart';

void main() {
  group('Building Model Tests', () {
    test('Building.fromJson parses valid json correctly', () {
      final jsonMap = {
        'id': 'b1',
        'name': 'Main Building',
        'lat': 10.554418,
        'lng': 76.224668,
        'tags': {'amenity': 'college', 'building': 'yes'},
        'photoBase64': 'data:image/png;base64,1234',
        'vpsBoardPhotoBase64': 'data:image/png;base64,5678',
      };

      final building = Building.fromJson(jsonMap);

      expect(building.id, 'b1');
      expect(building.name, 'Main Building');
      expect(building.lat, 10.554418);
      expect(building.lng, 76.224668);
      expect(building.tags['amenity'], 'college');
      expect(building.photoBase64, 'data:image/png;base64,1234');
      expect(building.vpsBoardPhotoBase64, 'data:image/png;base64,5678');
    });

    test('Building.fromJson parses Washroom place correctly', () {
      final jsonMap = {
        'id': 'w1',
        'name': 'Main Block Ground Floor Restroom',
        'lat': 10.554500,
        'lng': 76.224700,
        'tags': {'place_type': 'Washrooms', 'amenity': 'toilets', 'floor': '0'},
      };

      final washroom = Building.fromJson(jsonMap);

      expect(washroom.id, 'w1');
      expect(washroom.tags['place_type'], 'Washrooms');
      expect(washroom.tags['amenity'], 'toilets');
      expect(washroom.tags['floor'], '0');
    });

    test('Building.toJson outputs expected json map', () {
      final building = Building(
        id: 'b2',
        name: 'CSE Department',
        lat: 10.55274,
        lng: 76.22202,
        tags: {'department': 'computer_science'},
      );

      final jsonMap = building.toJson();

      expect(jsonMap['id'], 'b2');
      expect(jsonMap['name'], 'CSE Department');
      expect(jsonMap['lat'], 10.55274);
      expect(jsonMap['lng'], 76.22202);
      expect(jsonMap['tags']['department'], 'computer_science');
      expect(jsonMap.containsKey('photoBase64'), false);
    });
  });
}
