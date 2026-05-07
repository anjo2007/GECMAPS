import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../models/building.dart';

class DataService {
  Future<List<Building>> loadBuildings() async {
    try {
      final String jsonString =
          await rootBundle.loadString('assets/campus_buildings.json');
      final List<dynamic> jsonList = json.decode(jsonString);
      final all = jsonList.map((json) => Building.fromJson(json)).toList();

      // Filter out unnamed / uninteresting locations to reduce marker clutter
      final filtered = all.where((b) {
        if (b.name == 'Unnamed Location') return false;
        return true;
      }).toList();

      debugPrint("Loaded ${filtered.length} named buildings (${all.length} total in data)");
      return filtered;
    } catch (e) {
      debugPrint("Error loading buildings: $e");
      return [];
    }
  }
}
