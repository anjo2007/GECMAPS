import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:latlong2/latlong.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'web_sensors_stub.dart' if (dart.library.html) 'web_sensors_web.dart';

class PDRService {
  StreamSubscription? _accelSub;
  StreamSubscription? _compassSub;
  Timer? _simulationTimer;

  double _currentHeading = 0.0;

  // Step detection state
  bool _isStepHigh = false;
  final double _stepThreshold = 1.5; // m/s^2 for user accelerometer
  int _lastStepTime = 0;
  final int _minStepIntervalMs = 300;
  final double _stepLengthMeters = 0.7; // Average human step in meters

  // Earth radius in meters
  final double _earthRadius = 6371000.0;

  void Function(LatLng newPosition)? onPositionUpdated;
  void Function(int count)? onStepDetected;

  int _stepCount = 0;
  LatLng? _currentPosition;

  bool get isActive => _currentPosition != null && (_accelSub != null || _simulationTimer != null || kIsWeb);

  Future<void> startPDR(LatLng startPosition) async {
    stopPDR(); // Clean up any previous session
    _currentPosition = startPosition;
    _stepCount = 0;

    if (kIsWeb) {
      bool permissionGranted = await requestWebSensorPermissions();
      if (!permissionGranted) {
        // Fallback to simulation if user denied sensor permission
        _startWebSimulation();
        return;
      }
      _startWebPDR();
    } else {
      _startNativePDR();
    }
  }

  void _startNativePDR() {
    _compassSub = FlutterCompass.events?.listen((CompassEvent event) {
      if (event.heading != null) {
        _currentHeading = event.heading!;
      }
    });
    _listenToAccelerometer();
  }

  void _startWebPDR() {
    // Custom JS interop compass because flutter_compass doesn't support web
    listenToWebCompass((heading) {
      _currentHeading = heading;
    });
    _listenToAccelerometer();
  }

  void _listenToAccelerometer() {
    _accelSub = userAccelerometerEventStream().listen((UserAccelerometerEvent event) {
      double magnitude = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      int now = DateTime.now().millisecondsSinceEpoch;

      if (magnitude > _stepThreshold && !_isStepHigh) {
        if (now - _lastStepTime > _minStepIntervalMs) {
          _isStepHigh = true;
          _lastStepTime = now;
          _stepCount++;

          if (onStepDetected != null) onStepDetected!(_stepCount);

          _updatePositionWithPDR();
        }
      } else if (magnitude < _stepThreshold - 0.5) {
        _isStepHigh = false;
      }
    });
  }

  void _startWebSimulation() {
    final rng = Random();
    _currentHeading = rng.nextDouble() * 360;

    _simulationTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) {
      // In web simulation, we step slower to allow interactive overrides
      _stepCount++;
      _currentHeading += (rng.nextDouble() - 0.5) * 15;
      if (onStepDetected != null) onStepDetected!(_stepCount);
      _updatePositionWithPDR();
    });
  }

  void triggerManualStep(double heading) {
    _currentHeading = heading;
    _stepCount++;
    if (onStepDetected != null) onStepDetected!(_stepCount);
    _updatePositionWithPDR();
  }

  void forceSetPosition(LatLng position) {
    _currentPosition = position;
    if (onPositionUpdated != null) onPositionUpdated!(position);
  }

  void _updatePositionWithPDR() {
    if (_currentPosition == null) return;

    // Convert heading from degrees to radians
    double headingRad = _currentHeading * (pi / 180.0);

    // Calculate dx and dy in meters
    double dx = _stepLengthMeters * sin(headingRad);
    double dy = _stepLengthMeters * cos(headingRad);

    // Update latitude and longitude based on Earth curvature
    double dLat = (dy / _earthRadius) * (180.0 / pi);
    double dLng = (dx / (_earthRadius * cos(_currentPosition!.latitude * pi / 180.0))) * (180.0 / pi);

    _currentPosition = LatLng(_currentPosition!.latitude + dLat, _currentPosition!.longitude + dLng);

    if (onPositionUpdated != null) {
      onPositionUpdated!(_currentPosition!);
    }
  }

  void stopPDR() {
    _accelSub?.cancel();
    _accelSub = null;
    _compassSub?.cancel();
    _compassSub = null;
    _simulationTimer?.cancel();
    _simulationTimer = null;
    _currentPosition = null;
  }
}
