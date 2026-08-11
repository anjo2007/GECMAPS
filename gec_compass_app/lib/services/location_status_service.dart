import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class LocationStatusService {
  StreamSubscription<ServiceStatus>? _serviceStatusSub;
  bool _isServiceEnabled = true;
  LocationPermission _permission = LocationPermission.whileInUse;

  void Function(bool isEnabled)? onStatusChanged;

  bool get isServiceEnabled => _isServiceEnabled;
  LocationPermission get permission => _permission;

  /// Start monitoring device location service status in real-time
  Future<bool> startMonitoring({void Function(bool isEnabled)? callback}) async {
    onStatusChanged = callback;

    try {
      _isServiceEnabled = await Geolocator.isLocationServiceEnabled();
      _permission = await Geolocator.checkPermission();
    } catch (e) {
      debugPrint("Error checking initial location status: $e");
    }

    _serviceStatusSub?.cancel();
    _serviceStatusSub = Geolocator.getServiceStatusStream().listen((ServiceStatus status) {
      bool enabled = status == ServiceStatus.enabled;
      _isServiceEnabled = enabled;
      debugPrint("Location Service Status Changed: $status");
      if (onStatusChanged != null) {
        onStatusChanged!(enabled);
      }
    });

    return _isServiceEnabled && (_permission == LocationPermission.always || _permission == LocationPermission.whileInUse);
  }

  /// Request location permissions if not yet granted
  Future<LocationPermission> requestPermissions() async {
    _permission = await Geolocator.requestPermission();
    return _permission;
  }

  /// Open native location settings page
  Future<void> openSettings() async {
    await Geolocator.openLocationSettings();
  }

  void stopMonitoring() {
    _serviceStatusSub?.cancel();
    _serviceStatusSub = null;
  }
}
