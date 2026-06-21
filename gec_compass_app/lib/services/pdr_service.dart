import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'web_sensors_stub.dart' if (dart.library.html) 'web_sensors_web.dart';

class PDRService {
  static const EventChannel _stepDetectorChannel = EventChannel('com.gec.compass/step_detector');
  StreamSubscription? _nativeStepSub;

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

  bool _hasAccelerometerData = false;
  bool _hasCompassData = false;
  double _lastGpsSpeed = 0.0;

  bool get isActive => _currentPosition != null && (_accelSub != null || kIsWeb);

  Future<void> startPDR(LatLng startPosition) async {
    stopPDR(); // Clean up any previous session
    _currentPosition = startPosition;
    _stepCount = 0;
    _hasAccelerometerData = false;
    _hasCompassData = false;
    _lastGpsSpeed = 0.0;

    if (kIsWeb) {
      bool permissionGranted = await requestWebSensorPermissions();
      if (!permissionGranted) {
        debugPrint("Web sensor permissions denied. Running in GPS-only mode.");
      } else {
        _startWebPDR();
      }
    } else {
      _startNativePDR();
    }

    // 3Hz Sensor Fusion Loop (3 times a second)
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 333), (timer) {
      if (_currentPosition == null) return;

      // GPS-only dead reckoning projection fallback if no accelerometer data is active
      if (!_hasAccelerometerData && _lastGpsSpeed > 0.5) {
        double headingRad = _currentHeading * (pi / 180.0);
        double dist = _lastGpsSpeed * 0.333; // 333ms elapsed

        double dx = dist * sin(headingRad);
        double dy = dist * cos(headingRad);

        double dLat = (dy / _earthRadius) * (180.0 / pi);
        double dLng = (dx / (_earthRadius * cos(_currentPosition!.latitude * pi / 180.0))) * (180.0 / pi);

        _currentPosition = LatLng(_currentPosition!.latitude + dLat, _currentPosition!.longitude + dLng);
      }

      if (onPositionUpdated != null) {
        onPositionUpdated!(_currentPosition!);
      }
    });
  }

  void startTelemetryOnly() {
    if (isActive || _isTelemetryOnlyActive) return;
    _isTelemetryOnlyActive = true;
    _hasAccelerometerData = false;
    _hasCompassData = false;

    if (kIsWeb) {
      listenToWebCompass((heading) {
        _hasCompassData = true;
        _currentHeading = heading;
        rawHeading = heading;
        if (onRawCompassUpdated != null) onRawCompassUpdated!(heading);
      });
      _listenToAccelerometerTelemetry();
    } else {
      _compassSub = FlutterCompass.events?.listen((CompassEvent event) {
        if (event.heading != null) {
          _hasCompassData = true;
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
        _hasAccelerometerData = true;
        double magnitude = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
        rawAccelX = event.x;
        rawAccelY = event.y;
        rawAccelZ = event.z;
        rawAccelMagnitude = magnitude;
        if (onRawAccelUpdated != null) {
          onRawAccelUpdated!(event.x, event.y, event.z, magnitude);
        }
      }, onError: (e) {
        debugPrint("Sensors error: $e");
      });
    } catch (e) {
      debugPrint("Error listening to accelerometer: $e");
    }
  }

  void stopTelemetryOnly() {
    _isTelemetryOnlyActive = false;
    stopPDR();
  }

  Future<void> _startNativePDR() async {
    _compassSub = FlutterCompass.events?.listen((CompassEvent event) {
      if (event.heading != null) {
        _hasCompassData = true;
        _currentHeading = event.heading!;
        rawHeading = event.heading!;
        if (onRawCompassUpdated != null) onRawCompassUpdated!(rawHeading);
      }
    });

    // Request Android physical activity recognition permission
    try {
      final status = await Permission.activityRecognition.request();
      if (status.isGranted) {
        debugPrint("Android Activity Recognition permission granted. Starting hardware Step Detector...");
        _nativeStepSub = _stepDetectorChannel.receiveBroadcastStream().listen((dynamic event) {
          _hasAccelerometerData = true; // Mark motion sensor as active
          _stepCount++;
          if (onStepDetected != null) onStepDetected!(_stepCount);
          _updatePositionWithPDR();
        }, onError: (dynamic error) {
          debugPrint("Native step detector stream error: $error. Falling back to accelerometer peak detection.");
          _listenToAccelerometer();
        });
      } else {
        debugPrint("Android Activity Recognition permission denied. Falling back to accelerometer peak detection.");
        _listenToAccelerometer();
      }
    } catch (e) {
      debugPrint("Error requesting Activity Recognition permission: $e. Falling back to accelerometer peak detection.");
      _listenToAccelerometer();
    }
  }

  void _startWebPDR() {
    // Custom JS interop compass because flutter_compass doesn't support web
    listenToWebCompass((heading) {
      _hasCompassData = true;
      _currentHeading = heading;
      rawHeading = heading;
      if (onRawCompassUpdated != null) onRawCompassUpdated!(heading);
    });
    _listenToAccelerometer();
  }

  void _listenToAccelerometer() {
    _accelSub = userAccelerometerEventStream().listen((UserAccelerometerEvent event) {
      _hasAccelerometerData = true;
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

  void forceSetPosition(LatLng position) {
    _currentPosition = position;
    if (onPositionUpdated != null) onPositionUpdated!(position);
  }

  void updateGPSPosition(LatLng gpsPos, double accuracy, double speed, double heading) {
    _lastGpsSpeed = speed;
    if (heading >= 0.0) {
      if (!_hasCompassData) {
        _currentHeading = heading; // Fallback to GPS heading
        if (onRawCompassUpdated != null) onRawCompassUpdated!(heading);
      }
    }

    if (_currentPosition == null) {
      _currentPosition = gpsPos;
      if (onPositionUpdated != null) onPositionUpdated!(gpsPos);
      return;
    }

    // Weighted sensor fusion
    // Trust GPS more if it reports high accuracy (small radius)
    // Trust PDR step-counting/projection more if GPS has poor accuracy (large radius)
    double alpha;
    if (accuracy < 5.0) {
      alpha = 0.8;
    } else if (accuracy < 12.0) {
      alpha = 0.55;
    } else if (accuracy < 25.0) {
      alpha = 0.3;
    } else {
      alpha = 0.1; // rely heavily on PDR
    }

    // Blend coordinates
    double fusedLat = alpha * gpsPos.latitude + (1 - alpha) * _currentPosition!.latitude;
    double fusedLng = alpha * gpsPos.longitude + (1 - alpha) * _currentPosition!.longitude;
    _currentPosition = LatLng(fusedLat, fusedLng);

    if (onPositionUpdated != null) {
      onPositionUpdated!(_currentPosition!);
    }
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
    _nativeStepSub?.cancel();
    _nativeStepSub = null;
    _simulationTimer?.cancel();
    _simulationTimer = null;
    _currentPosition = null;
    _isTelemetryOnlyActive = false;
  }
}
