import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

enum LocationMode { idle, navigation }

class LocationService with WidgetsBindingObserver {
  StreamSubscription<Position>? _subscription;
  final _positionController = StreamController<LatLng>.broadcast();
  Stream<LatLng> get positionStream => _positionController.stream;

  LocationMode _mode = LocationMode.idle;

  LocationService() {
    WidgetsBinding.instance.addObserver(this);
  }

  void setMode(LocationMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    _restartTracking();
  }

  Future<void> _restartTracking() async {
    await _subscription?.cancel();
    _startListening();
  }

  Future<void> _startListening() async {
    // Check permissions first (your own permission handler)
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationSettings settings;
    switch (_mode) {
      case LocationMode.navigation:
        settings = const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 2,       // 2 meters – still realtime
        );
        break;
      case LocationMode.idle:
        settings = const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        );
        break;
    }

    _subscription = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen(
      (Position pos) {
        _positionController.add(LatLng(pos.latitude, pos.longitude));
      },
      onError: (error) {
        debugPrint('Location error: $error');
      },
    );
  }

  void stopTracking() {
    _subscription?.cancel();
    _subscription = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      stopTracking();
    } else if (state == AppLifecycleState.resumed) {
      _startListening();
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionController.close();
    stopTracking();
  }
}
