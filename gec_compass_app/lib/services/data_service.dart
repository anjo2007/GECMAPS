import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../models/building.dart';

class DataService {
  static const String _customBuildingsKey = 'custom_buildings';

  // API URL for cloud syncing
  String get _apiUrl => kIsWeb ? '/api/places' : 'https://gec-compass.vercel.app/api/places';

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

      // Attempt to load from cloud (Vercel API), fallback to direct public cloud DB, fallback to local cache
      List<Building> customBuildings = [];
      bool loadedFromCloud = false;

      // 1. Try Vercel API
      try {
        final response = await http.get(Uri.parse(_apiUrl)).timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) {
          final List<dynamic> apiList = json.decode(response.body);
          customBuildings = apiList.map((j) => Building.fromJson(j)).toList();
          await _syncLocalCache(customBuildings);
          loadedFromCloud = true;
          debugPrint("Loaded places from Vercel API.");
        } else {
          throw Exception("Vercel API returned status ${response.statusCode}");
        }
      } catch (e) {
        debugPrint("Vercel API load failed, trying direct public DB fallback: $e");
      }

      // 2. Try direct public DB fallback if Vercel failed
      if (!loadedFromCloud) {
        try {
          final response = await http.get(Uri.parse('https://api.npoint.io/b3f62804fe66d1f0545f')).timeout(const Duration(seconds: 5));
          if (response.statusCode == 200) {
            final List<dynamic> apiList = json.decode(response.body);
            customBuildings = apiList.map((j) => Building.fromJson(j)).toList();
            await _syncLocalCache(customBuildings);
            loadedFromCloud = true;
            debugPrint("Loaded places from direct public DB fallback.");
          } else {
            throw Exception("Direct public DB returned status ${response.statusCode}");
          }
        } catch (e) {
          debugPrint("Direct public DB load failed, loading local cache: $e");
        }
      }

      // 3. Try local cache if both cloud methods failed
      if (!loadedFromCloud) {
        customBuildings = await _loadCustomBuildingsLocal();
      }

      filtered.addAll(customBuildings);

      debugPrint("Loaded ${filtered.length - customBuildings.length} standard buildings and ${customBuildings.length} custom buildings.");
      return filtered;
    } catch (e) {
      debugPrint("Error loading buildings: $e");
      return [];
    }
  }

  Future<void> _syncLocalCache(List<Building> buildings) async {
    final prefs = await SharedPreferences.getInstance();
    final String customJsonString = json.encode(buildings.map((b) => b.toJson()).toList());
    await prefs.setString(_customBuildingsKey, customJsonString);
  }

  Future<List<Building>> _loadCustomBuildingsLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? customJsonString = prefs.getString(_customBuildingsKey);
      if (customJsonString != null) {
        final List<dynamic> customJsonList = json.decode(customJsonString);
        return customJsonList.map((json) => Building.fromJson(json)).toList();
      }
    } catch (e) {
      debugPrint("Error loading custom buildings from SharedPreferences: $e");
    }
    return [];
  }

  Future<void> saveCustomBuilding(Building building) async {
    // 1. Save locally first for immediate availability
    try {
      final customBuildings = await _loadCustomBuildingsLocal();
      customBuildings.removeWhere((b) => b.id == building.id);
      customBuildings.add(building);
      await _syncLocalCache(customBuildings);
      debugPrint("Saved custom building locally: ${building.name}");
    } catch (e) {
      debugPrint("Error saving custom building locally: $e");
    }

    // 2. Sync to Vercel API
    bool syncedToVercel = false;
    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(building.toJson()),
      ).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        syncedToVercel = true;
        debugPrint("Synced custom building to Vercel cloud.");
      } else {
        debugPrint("Vercel sync returned status ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Error syncing to Vercel API: $e");
    }

    // 3. Fallback: Sync to direct public DB if Vercel sync failed
    if (!syncedToVercel) {
      try {
        final response = await http.get(Uri.parse('https://api.npoint.io/b3f62804fe66d1f0545f')).timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) {
          final List<dynamic> apiList = json.decode(response.body);
          final List<Building> current = apiList.map((j) => Building.fromJson(j)).toList();
          current.removeWhere((b) => b.id == building.id);
          current.add(building);

          await http.post(
            Uri.parse('https://api.npoint.io/b3f62804fe66d1f0545f'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(current.map((b) => b.toJson()).toList()),
          ).timeout(const Duration(seconds: 5));
          debugPrint("Synced custom building to direct public DB fallback.");
        }
      } catch (e) {
        debugPrint("Error syncing to direct public DB fallback: $e");
      }
    }
  }
}
