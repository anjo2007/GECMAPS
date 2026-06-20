import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../models/building.dart';

class DataService {
  static const String _customBuildingsKey = 'custom_buildings';
  static const String _apiUrlCacheKey = 'cached_api_url';

  // Default Vercel API URL — used as fallback if dynamic config fetch fails
  static const String _defaultApiUrl = 'https://gec-compass.vercel.app/api/places';

  // GitHub raw URL for the config.json file in the repository
  static const String _configUrl =
      'https://raw.githubusercontent.com/anjo2007/GECMAPS/master/config.json';

  // Cached resolved API URL (in-memory for the session)
  String? _resolvedApiUrl;

  /// Resolves the API URL dynamically from the GitHub-hosted config.json.
  /// Falls back to the locally cached URL, then to the hardcoded default.
  Future<String> _getApiUrl() async {
    // For web, always use relative path so it hits the same Vercel deployment
    if (kIsWeb) return '/api/places';

    // Return already-resolved URL if available this session
    if (_resolvedApiUrl != null) return _resolvedApiUrl!;

    // Try fetching from GitHub
    try {
      final response = await http
          .get(Uri.parse(_configUrl))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final config = json.decode(response.body);
        final url = config['vercel_api_url'] as String?;
        if (url != null && url.isNotEmpty) {
          _resolvedApiUrl = url;
          // Cache locally for offline use
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_apiUrlCacheKey, url);
          debugPrint('Resolved API URL from GitHub config: $url');
          return url;
        }
      }
    } catch (e) {
      debugPrint('Failed to fetch config from GitHub: $e');
    }

    // Try locally cached URL
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_apiUrlCacheKey);
      if (cached != null && cached.isNotEmpty) {
        _resolvedApiUrl = cached;
        debugPrint('Using locally cached API URL: $cached');
        return cached;
      }
    } catch (e) {
      debugPrint('Failed to read cached API URL: $e');
    }

    // Fall back to hardcoded default
    _resolvedApiUrl = _defaultApiUrl;
    debugPrint('Using default API URL: $_defaultApiUrl');
    return _defaultApiUrl;
  }

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

      // Load custom buildings from the cloud API
      List<Building> customBuildings = [];
      bool loadedFromCloud = false;

      try {
        final apiUrl = await _getApiUrl();
        final response = await http
            .get(Uri.parse(apiUrl))
            .timeout(const Duration(seconds: 8));
        if (response.statusCode == 200) {
          final decoded = json.decode(response.body);
          final List<dynamic> apiList =
              decoded is List ? decoded : [];
          customBuildings =
              apiList.map((j) => Building.fromJson(j)).toList();
          await _syncLocalCache(customBuildings);
          loadedFromCloud = true;
          debugPrint(
              'Loaded ${customBuildings.length} places from cloud API.');
        } else {
          throw Exception('Cloud API returned status ${response.statusCode}');
        }
      } catch (e) {
        debugPrint('Cloud API load failed, loading local cache: $e');
      }

      // Fall back to local cache if cloud fetch failed
      if (!loadedFromCloud) {
        customBuildings = await _loadCustomBuildingsLocal();
        debugPrint(
            'Loaded ${customBuildings.length} places from local cache.');
      }

      // Deduplicate: custom buildings override default ones if they have the same ID
      final customIds = customBuildings.map((b) => b.id).toSet();
      filtered.removeWhere((b) => customIds.contains(b.id));
      filtered.addAll(customBuildings);

      debugPrint(
          'Loaded ${filtered.length - customBuildings.length} standard buildings and ${customBuildings.length} custom buildings.');
      return filtered;
    } catch (e) {
      debugPrint('Error loading buildings: $e');
      return [];
    }
  }

  Future<void> _syncLocalCache(List<Building> buildings) async {
    final prefs = await SharedPreferences.getInstance();
    final String customJsonString =
        json.encode(buildings.map((b) => b.toJson()).toList());
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
      debugPrint(
          'Error loading custom buildings from SharedPreferences: $e');
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
      debugPrint('Saved custom building locally: ${building.name}');
    } catch (e) {
      debugPrint('Error saving custom building locally: $e');
    }

    // 2. Sync to cloud API
    try {
      final apiUrl = await _getApiUrl();
      final response = await http
          .post(
            Uri.parse(apiUrl),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(building.toJson()),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        debugPrint('Synced custom building to cloud: ${building.name}');
      } else {
        debugPrint(
            'Cloud sync returned status ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error syncing to cloud API: $e');
    }
  }
}
