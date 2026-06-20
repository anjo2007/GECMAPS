import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
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

  // Telemetry callbacks & variables
  double rawAccelX = 0.0;
  double rawAccelY = 0.0;
  double rawAccelZ = 0.0;
  double rawAccelMagnitude = 0.0;
  double rawHeading = 0.0;

  void Function(double heading)? onRawCompassUpdated;
  void Function(double x, double y, double z, double magnitude)? onRawAccelUpdated;

  bool _isTelemetryOnlyActive = false;
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

  void startTelemetryOnly() {
    if (isActive || _isTelemetryOnlyActive) return;
    _isTelemetryOnlyActive = true;

    if (kIsWeb) {
      listenToWebCompass((heading) {
        _currentHeading = heading;
        rawHeading = heading;
        if (onRawCompassUpdated != null) onRawCompassUpdated!(heading);
      });
      _listenToAccelerometerTelemetry();
    } else {
      _compassSub = FlutterCompass.events?.listen((CompassEvent event) {
        if (event.heading != null) {
          _currentHeading = event.heading!;
          rawHeading = event.heading!;
          if (onRawCompassUpdated != null) onRawCompassUpdated!(rawHeading);
        }
      });
      _listenToAccelerometerTelemetry();
    }
  }

  void _listenToAccelerometerTelemetry() {
    try {
      _accelSub = userAccelerometerEventStream().listen((UserAccelerometerEvent event) {
        double magnitude = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
        rawAccelX = event.x;
        rawAccelY = event.y;
        rawAccelZ = event.z;
        rawAccelMagnitude = magnitude;
        if (onRawAccelUpdated != null) {
          onRawAccelUpdated!(event.x, event.y, event.z, magnitude);
        }
      }, onError: (e) {
        debugPrint("Sensors error, running fallback simulation: $e");
        _startTelemetryFallbackSimulation();
      });

      // If no events are received (common on desktop web), start fallback simulation after 1 second
      Timer(const Duration(seconds: 1), () {
        if (_isTelemetryOnlyActive && rawAccelMagnitude == 0.0) {
          _startTelemetryFallbackSimulation();
        }
      });
    } catch (e) {
      _startTelemetryFallbackSimulation();
    }
  }

  void _startTelemetryFallbackSimulation() {
    _simulationTimer?.cancel();
    final rng = Random();
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 150), (timer) {
      if (!_isTelemetryOnlyActive) {
        timer.cancel();
        return;
      }
      // Generate mild vibration/movement noise
      rawAccelX = (rng.nextDouble() - 0.5) * 0.4;
      rawAccelY = (rng.nextDouble() - 0.5) * 0.4;
      rawAccelZ = (rng.nextDouble() - 0.5) * 0.4;
      rawAccelMagnitude = sqrt(rawAccelX * rawAccelX + rawAccelY * rawAccelY + rawAccelZ * rawAccelZ);
      rawHeading = (rawHeading + (rng.nextDouble() - 0.5) * 4.0) % 360;

      if (onRawCompassUpdated != null) onRawCompassUpdated!(rawHeading);
      if (onRawAccelUpdated != null) onRawAccelUpdated!(rawAccelX, rawAccelY, rawAccelZ, rawAccelMagnitude);
    });
  }

  void stopTelemetryOnly() {
    _isTelemetryOnlyActive = false;
    stopPDR();
  }

  void _startNativePDR() {
    _compassSub = FlutterCompass.events?.listen((CompassEvent event) {
      if (event.heading != null) {
        _currentHeading = event.heading!;
        rawHeading = event.heading!;
        if (onRawCompassUpdated != null) onRawCompassUpdated!(rawHeading);
      }
    });
    _listenToAccelerometer();
  }

  void _startWebPDR() {
    // Custom JS interop compass because flutter_compass doesn't support web
    listenToWebCompass((heading) {
      _currentHeading = heading;
      rawHeading = heading;
      if (onRawCompassUpdated != null) onRawCompassUpdated!(heading);
    });
    _listenToAccelerometer();
  }

  void _listenToAccelerometer() {
    _accelSub = userAccelerometerEventStream().listen((UserAccelerometerEvent event) {
      double magnitude = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);

      rawAccelX = event.x;
      rawAccelY = event.y;
      rawAccelZ = event.z;
      rawAccelMagnitude = magnitude;
      if (onRawAccelUpdated != null) {
        onRawAccelUpdated!(event.x, event.y, event.z, magnitude);
      }

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
    rawHeading = _currentHeading;

    _simulationTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) {
      // In web simulation, we step slower to allow interactive overrides
      _stepCount++;
      _currentHeading += (rng.nextDouble() - 0.5) * 15;
      _currentHeading = (_currentHeading + 360) % 360;
      rawHeading = _currentHeading;

      // Simulate step accelerometer spikes
      rawAccelX = (rng.nextDouble() - 0.5) * 1.5;
      rawAccelY = 2.0 + rng.nextDouble() * 4.0;
      rawAccelZ = (rng.nextDouble() - 0.5) * 1.5;
      rawAccelMagnitude = sqrt(rawAccelX * rawAccelX + rawAccelY * rawAccelY + rawAccelZ * rawAccelZ);

      if (onRawCompassUpdated != null) onRawCompassUpdated!(rawHeading);
      if (onRawAccelUpdated != null) onRawAccelUpdated!(rawAccelX, rawAccelY, rawAccelZ, rawAccelMagnitude);

      if (onStepDetected != null) onStepDetected!(_stepCount);
      _updatePositionWithPDR();
    });
  }

  void triggerManualStep(double heading) {
    _currentHeading = heading;
    rawHeading = heading;
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
    _isTelemetryOnlyActive = false;
  }
}
