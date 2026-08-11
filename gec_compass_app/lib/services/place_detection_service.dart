import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wifi_scan/wifi_scan.dart';

class FloorFingerprint {
  final String floorId;
  final String floorName;
  final Map<String, int> bssidRssiMap; // MAC address to RSSI strength

  FloorFingerprint({
    required this.floorId,
    required this.floorName,
    required this.bssidRssiMap,
  });

  Map<String, dynamic> toJson() => {
        'floorId': floorId,
        'floorName': floorName,
        'bssidRssiMap': bssidRssiMap,
      };

  factory FloorFingerprint.fromJson(Map<String, dynamic> json) {
    return FloorFingerprint(
      floorId: json['floorId'] as String,
      floorName: json['floorName'] as String,
      bssidRssiMap: Map<String, int>.from(json['bssidRssiMap'] as Map),
    );
  }
}

class PlaceDetectionService {
  static final PlaceDetectionService _instance = PlaceDetectionService._internal();
  factory PlaceDetectionService() => _instance;
  PlaceDetectionService._internal();

  List<FloorFingerprint> _savedFingerprints = [];
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('floor_fingerprints');
    if (data != null) {
      try {
        final List<dynamic> jsonList = jsonDecode(data);
        _savedFingerprints = jsonList.map((e) => FloorFingerprint.fromJson(e)).toList();
      } catch (e) {
        debugPrint("Error loading fingerprints: $e");
      }
    }
    _isInitialized = true;
  }

  Future<void> saveFingerprints() async {
    final prefs = await SharedPreferences.getInstance();
    final String data = jsonEncode(_savedFingerprints.map((e) => e.toJson()).toList());
    await prefs.setString('floor_fingerprints', data);
  }

  Future<Map<String, int>> scanCurrentWifiEnvironment() async {
    try {
      final canStart = await WiFiScan.instance.canStartScan();
      if (canStart == CanStartScan.yes) {
        final result = await WiFiScan.instance.startScan();
        if (result) {
          // Wait a moment for scan to complete, typically Android returns results asynchronously.
          // For simplicity in this demo, we immediately fetch. In a production app, we might listen to onGetScannedResultsEvent.
          await Future.delayed(const Duration(seconds: 2));
          final results = await WiFiScan.instance.getScannedResults();
          final Map<String, int> environment = {};
          for (var network in results) {
            environment[network.bssid] = network.level;
          }
          return environment;
        }
      }
    } catch (e) {
      debugPrint("Error scanning wifi: $e");
    }
    return {};
  }

  Future<void> mapFloor(String floorId, String floorName) async {
    final environment = await scanCurrentWifiEnvironment();
    if (environment.isNotEmpty) {
      // Remove existing fingerprint for this floor if it exists
      _savedFingerprints.removeWhere((f) => f.floorId == floorId);
      
      _savedFingerprints.add(FloorFingerprint(
        floorId: floorId,
        floorName: floorName,
        bssidRssiMap: environment,
      ));
      await saveFingerprints();
      debugPrint("Mapped floor $floorName with ${environment.length} BSSIDs");
    } else {
      debugPrint("Failed to map floor: No Wi-Fi networks found or permission denied.");
    }
  }

  Future<FloorFingerprint?> detectCurrentFloor() async {
    if (_savedFingerprints.isEmpty) return null;

    final environment = await scanCurrentWifiEnvironment();
    if (environment.isEmpty) return null;

    FloorFingerprint? bestMatch;
    double bestSimilarity = 0.0;

    for (var fingerprint in _savedFingerprints) {
      // Skip fingerprints with empty BSSID maps to avoid division by zero
      if (fingerprint.bssidRssiMap.isEmpty) continue;

      double dotProduct = 0.0;
      double normASq = 0.0;
      double normBSq = 0.0;
      int matchCount = 0;

      // Only iterate over BSSIDs common to both scans for clean cosine similarity
      // Include fingerprint BSSIDs that are present in environment
      for (var bssid in fingerprint.bssidRssiMap.keys) {
        if (environment.containsKey(bssid)) {
          final valA = (environment[bssid]! + 105).clamp(1, 100).toDouble();
          final valB = (fingerprint.bssidRssiMap[bssid]! + 105).clamp(1, 100).toDouble();

          matchCount++;
          dotProduct += valA * valB;
          normASq += valA * valA;
          normBSq += valB * valB;
        }
      }

      if (normASq > 0 && normBSq > 0 && matchCount >= 2) {
        double cosineSim = dotProduct / (sqrt(normASq) * sqrt(normBSq));
        // Penalize fingerprint if very few BSSIDs matched relative to total expected
        double coverageRatio = matchCount / fingerprint.bssidRssiMap.length;
        double weightedScore = cosineSim * (0.6 + 0.4 * coverageRatio);

        if (weightedScore > bestSimilarity) {
          bestSimilarity = weightedScore;
          bestMatch = fingerprint;
        }
      }
    }

    if (bestSimilarity > 0.45) {
      return bestMatch;
    }
    return null;
  }
  
  List<FloorFingerprint> get savedFloors => _savedFingerprints;
}
