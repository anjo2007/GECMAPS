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
  double _smoothHeading = 0.0;
  bool _headingInitialized = false;

  // Step detection state
  bool _isStepHigh = false;
  final double _stepThreshold = 1.4; // m/s^2 for user accelerometer
  int _lastStepTime = 0;
  final int _minStepIntervalMs = 280;
  double _stepLengthMeters = 0.7; // Dynamic step length

  // Accelerometer window for Weinberg dynamic step estimation
  double _recentMaxAccel = 1.0;
  double _recentMinAccel = 1.0;

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
  int _consecutiveGpsRejections = 0;
  LatLng? _currentPosition;

  bool _hasAccelerometerData = false;
  bool _hasCompassData = false;
  double _lastGpsSpeed = 0.0;
  int _lastGpsUpdateTime = 0;
  double _lastAcceptedAccuracy = 999.0;
  LatLng? _lastGpsPosition;

  bool get isActive => _currentPosition != null && (_accelSub != null || kIsWeb);

  /// Circular Exponential Moving Average (EMA) heading filter
  void _updateHeading(double newHeading) {
    rawHeading = newHeading;
    if (!_headingInitialized) {
      _smoothHeading = newHeading;
      _headingInitialized = true;
    } else {
      double radSmooth = _smoothHeading * (pi / 180.0);
      double radNew = newHeading * (pi / 180.0);
      double alpha = 0.25; // Responsive yet smooth filter factor
      double sinAvg = (1 - alpha) * sin(radSmooth) + alpha * sin(radNew);
      double cosAvg = (1 - alpha) * cos(radSmooth) + alpha * cos(radNew);
      double smoothed = atan2(sinAvg, cosAvg) * (180.0 / pi);
      _smoothHeading = (smoothed + 360.0) % 360.0;
    }
    _currentHeading = _smoothHeading;
    if (onRawCompassUpdated != null) onRawCompassUpdated!(_currentHeading);
  }

  Future<void> startPDR(LatLng startPosition) async {
    stopPDR(); // Clean up any previous session
    _currentPosition = startPosition;
    _stepCount = 0;
    _hasAccelerometerData = false;
    _hasCompassData = false;
    _headingInitialized = false;
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

    // 4Hz Sensor Fusion Loop (4 times a second for smoother trajectory rendering)
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 250), (timer) {
      if (_currentPosition == null) return;

      // Reset speed if GPS is stale (no update for 3s) to prevent infinite drift
      final int nowMs = DateTime.now().millisecondsSinceEpoch;
      if (_lastGpsUpdateTime > 0 && (nowMs - _lastGpsUpdateTime) > 3000) {
        _lastGpsSpeed = 0.0;
      }

      // GPS-only dead reckoning projection fallback if no accelerometer data is active
      if (!_hasAccelerometerData && _lastGpsSpeed > 0.5) {
        double headingRad = _currentHeading * (pi / 180.0);
        double dist = _lastGpsSpeed * 0.25; // 250ms elapsed

        double dx = dist * sin(headingRad);
        double dy = dist * cos(headingRad);

        double dLat = (dy / _earthRadius) * (180.0 / pi);
        double dLng = (dx / (_earthRadius * cos(_currentPosition!.latitude * pi / 180.0))) * (180.0 / pi);

        _currentPosition = LatLng(_currentPosition!.latitude + dLat, _currentPosition!.longitude + dLng);

        if (onPositionUpdated != null) {
          onPositionUpdated!(_currentPosition!);
        }
      }
    });
  }

  void startTelemetryOnly() {
    if (isActive || _isTelemetryOnlyActive) return;
    _isTelemetryOnlyActive = true;
    _hasAccelerometerData = false;
    _hasCompassData = false;
    _headingInitialized = false;

    if (kIsWeb) {
      listenToWebCompass((heading) {
        _hasCompassData = true;
        _updateHeading(heading);
      });
      _listenToAccelerometerTelemetry();
    } else {
      _compassSub = FlutterCompass.events?.listen((CompassEvent event) {
        if (event.heading != null) {
          _hasCompassData = true;
          _updateHeading(event.heading!);
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
        _updateHeading(event.heading!);
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
    listenToWebCompass((heading) {
      _hasCompassData = true;
      _updateHeading(heading);
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

      // Dynamic peak/trough tracking for Weinberg estimation
      _recentMaxAccel = max(_recentMaxAccel, magnitude);
      _recentMinAccel = min(_recentMinAccel, magnitude);

      if (magnitude > _stepThreshold && !_isStepHigh) {
        int now = DateTime.now().millisecondsSinceEpoch;
        int interval = now - _lastStepTime;
        if (interval > _minStepIntervalMs) {
          _isStepHigh = true;
          _lastStepTime = now;
          _stepCount++;

          // Weinberg dynamic step length estimation based on peak-to-trough range
          double diff = (_recentMaxAccel - _recentMinAccel).clamp(0.1, 8.0);
          double dynamicLength = 0.45 * pow(diff, 0.25);
          if (interval > 0 && interval < 1200) {
            double freq = 1000.0 / interval;
            dynamicLength = (dynamicLength + (0.38 + 0.16 * freq)) / 2.0;
          }
          _stepLengthMeters = dynamicLength.clamp(0.48, 0.92);

          // Reset peak window
          _recentMaxAccel = magnitude;
          _recentMinAccel = magnitude;

          if (onStepDetected != null) onStepDetected!(_stepCount);

          _updatePositionWithPDR();
        }
      } else if (magnitude < _stepThreshold - 0.4) {
        _isStepHigh = false;
      }
    });
  }

  void forceSetPosition(LatLng position) {
    _currentPosition = position;
    _consecutiveGpsRejections = 0;
    if (onPositionUpdated != null) onPositionUpdated!(position);
  }

  void updateGPSPosition(LatLng gpsPos, double accuracy, double speed, double heading) {
    _lastGpsSpeed = speed.clamp(0.0, 100.0);
    _lastGpsUpdateTime = DateTime.now().millisecondsSinceEpoch;
    _lastGpsPosition = gpsPos;

    // Filter out extremely poor fixes (>100m) but allow moderate accuracy with lower weight
    if (accuracy > 100.0) {
      return;
    }

    // GPS heading is more accurate when user moves fast; compass is better when stationary
    if (heading > 0.0 && speed > 0.8) {
      if (!_hasCompassData) {
        _updateHeading(heading);
      } else {
        // Blend GPS bearing with compass: trust GPS heading proportionally to speed
        double gpsWeight = (speed / 3.0).clamp(0.0, 0.6);
        double radCompass = _currentHeading * (pi / 180.0);
        double radGps = heading * (pi / 180.0);
        double sinBlend = (1 - gpsWeight) * sin(radCompass) + gpsWeight * sin(radGps);
        double cosBlend = (1 - gpsWeight) * cos(radCompass) + gpsWeight * cos(radGps);
        double blended = atan2(sinBlend, cosBlend) * (180.0 / pi);
        _currentHeading = (blended + 360.0) % 360.0;
        _smoothHeading = _currentHeading;
        rawHeading = _currentHeading;
        if (onRawCompassUpdated != null) onRawCompassUpdated!(_currentHeading);
      }
    }

    if (_currentPosition == null) {
      _currentPosition = gpsPos;
      _consecutiveGpsRejections = 0;
      if (onPositionUpdated != null) onPositionUpdated!(gpsPos);
      return;
    }

    // Distance calculation from current fused position
    final Distance distCalculator = const Distance();
    double jumpMeters = distCalculator.as(LengthUnit.Meter, _currentPosition!, gpsPos);

    // Filter stationary GPS noise — but allow accuracy refinement
    if (jumpMeters < 0.3 && speed < 0.4 && accuracy >= _lastAcceptedAccuracy) {
      return;
    }

    // Reject GPS multipath: either poor accuracy with large jump, or impossible teleport speed
    if ((accuracy > 25.0 && jumpMeters > 35.0) || jumpMeters > 80.0) {
      _consecutiveGpsRejections++;
      debugPrint("GPS outlier rejected ($_consecutiveGpsRejections/5): jump ${jumpMeters.toStringAsFixed(1)}m with accuracy ${accuracy.toStringAsFixed(1)}m");
      if (_consecutiveGpsRejections >= 5) {
        debugPrint("Escape hatch triggered after 5 consecutive outlier rejections. Resetting filter to GPS position.");
        _currentPosition = gpsPos;
        _consecutiveGpsRejections = 0;
        if (onPositionUpdated != null) onPositionUpdated!(_currentPosition!);
      }
      return;
    }

    _consecutiveGpsRejections = 0;

    // Weighted sensor fusion
    // Trust GPS more if accuracy is high (<5m)
    // Trust PDR step dead reckoning more if GPS accuracy is low (>15m)
    _lastAcceptedAccuracy = accuracy;

    double alpha;
    if (accuracy < 4.0) {
      alpha = 0.85;
    } else if (accuracy < 10.0) {
      alpha = 0.60;
    } else if (accuracy < 20.0) {
      alpha = 0.35;
    } else if (accuracy < 50.0) {
      alpha = 0.12; // Rely heavily on step dead reckoning
    } else {
      alpha = 0.06; // Very low weight for poor GPS — keeps marker roughly correct
    }

    // Blend coordinates smoothly
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

    final newPos = LatLng(_currentPosition!.latitude + dLat, _currentPosition!.longitude + dLng);

    // PDR drift cap: limit maximum displacement from last GPS fix to 80m
    if (_lastGpsPosition != null) {
      final Distance distCalc = const Distance();
      double driftMeters = distCalc.as(LengthUnit.Meter, _lastGpsPosition!, newPos);
      if (driftMeters > 80.0) {
        // Freeze PDR position — drift exceeded safety limit
        return;
      }
    }

    _currentPosition = newPos;

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
    _headingInitialized = false;
  }
}
