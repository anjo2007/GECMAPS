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
  double get currentHeading => _currentHeading;

  // Step detection state
  double _filteredMagnitude = 0.0;
  final double _filterAlpha = 0.18; // Smoothes noise but keeps step peaks
  final List<double> _magnitudeHistory = [];
  final int _historySize = 15; // ~300ms window at 50Hz sample rate
  int _lastStepTime = 0;
  
  // Weinberg dynamic step-length estimation state
  double userHeight = 1.70; // Default height in meters
  double _currentStepLength = 0.70; // Estimated step length in meters

  // Map Snapping configuration
  bool enableSnapping = true;
  double snappingThresholdMeters = 15.0; // Distance tolerance for snapping
  List<LatLng> activeRoute = []; // User's active navigation path
  List<List<LatLng>> roadEdges = []; // General campus road network edges

  // Earth radius in meters
  final double _earthRadius = 6371000.0;

  void Function(LatLng newPosition)? onPositionUpdated;
  void Function(int count)? onStepDetected;
  void Function(double heading)? onHeadingUpdated;

  int _stepCount = 0;
  LatLng? _currentPosition;

  bool get isActive => _currentPosition != null && (_accelSub != null || _simulationTimer != null || kIsWeb);

  Future<void> startPDR(LatLng startPosition) async {
    stopPDR(); // Clean up any previous session
    _currentPosition = startPosition;
    _stepCount = 0;
    _filteredMagnitude = 0.0;
    _magnitudeHistory.clear();
    _currentStepLength = userHeight * 0.413; // Empirical average step size starting point

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
        if (onHeadingUpdated != null) onHeadingUpdated!(_currentHeading);
      }
    });
    _listenToAccelerometer();
  }

  void _startWebPDR() {
    // Custom JS interop compass because flutter_compass doesn't support web
    listenToWebCompass((heading) {
      _currentHeading = heading;
      if (onHeadingUpdated != null) onHeadingUpdated!(_currentHeading);
    });
    _listenToAccelerometer();
  }

  void _listenToAccelerometer() {
    _accelSub = userAccelerometerEventStream().listen((UserAccelerometerEvent event) {
      double rawMagnitude = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      
      // 1. Exponential Moving Average Low-Pass Filter
      _filteredMagnitude = _filterAlpha * rawMagnitude + (1.0 - _filterAlpha) * _filteredMagnitude;
      
      _magnitudeHistory.add(_filteredMagnitude);
      if (_magnitudeHistory.length > _historySize) {
        _magnitudeHistory.removeAt(0);
      }

      // 2. Dynamic Peak Detection
      if (_magnitudeHistory.length == _historySize) {
        int midIndex = _historySize ~/ 2;
        double midValue = _magnitudeHistory[midIndex];

        bool isPeak = true;
        double maxVal = _magnitudeHistory[0];
        double minVal = _magnitudeHistory[0];

        for (int i = 0; i < _historySize; i++) {
          double val = _magnitudeHistory[i];
          if (val > maxVal) maxVal = val;
          if (val < minVal) minVal = val;
          
          if (i != midIndex && val > midValue) {
            isPeak = false;
          }
        }

        double peakDiff = maxVal - minVal;
        int now = DateTime.now().millisecondsSinceEpoch;

        // Peak conditions:
        // - Is the local maximum in the window
        // - Window amplitude variance (max - min) exceeds 1.2 m/s^2 (filters out noise/tremor)
        // - Peak magnitude exceeds 1.0 m/s^2
        // - Time since last step is at least 350ms
        if (isPeak && peakDiff > 1.2 && midValue > 1.0) {
          if (now - _lastStepTime > 350) {
            _lastStepTime = now;
            _stepCount++;

            // 3. Weinberg Dynamic Step-Length Estimation
            _updateWeinbergStepLength(maxVal, minVal);

            if (onStepDetected != null) onStepDetected!(_stepCount);
            _updatePositionWithPDR();
          }
        }
      }
    });
  }

  void _updateWeinbergStepLength(double maxAcc, double minAcc) {
    // Weinberg formula: step_length = K * (acc_max - acc_min)^(1/4)
    // Scale K parameter based on user height
    double k = userHeight * 0.25;
    double accDiff = (maxAcc - minAcc).abs();
    _currentStepLength = k * pow(accDiff, 0.25);
    
    // Clamp to reasonable human limits
    _currentStepLength = _currentStepLength.clamp(0.4, 1.2);
  }

  void _startWebSimulation() {
    final rng = Random();
    _currentHeading = rng.nextDouble() * 360;

    _simulationTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) {
      _stepCount++;
      _currentHeading += (rng.nextDouble() - 0.5) * 15;
      if (onHeadingUpdated != null) onHeadingUpdated!(_currentHeading);
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

  // Calculate distance in meters between two LatLng points
  double _distance(LatLng a, LatLng b) {
    const double R = 6371000;
    final dLat = (b.latitude - a.latitude) * (pi / 180);
    final dLng = (b.longitude - a.longitude) * (pi / 180);
    final aCalc = sin(dLat / 2) * sin(dLat / 2) +
        cos(a.latitude * pi / 180) *
            cos(b.latitude * pi / 180) *
            sin(dLng / 2) *
            sin(dLng / 2);
    final c = 2 * atan2(sqrt(aCalc), sqrt(1 - aCalc));
    return R * c;
  }

  // Project point onto line segment AB in flat coordinate plane
  LatLng _projectPointToSegment(LatLng p, LatLng a, LatLng b) {
    double ax = a.longitude;
    double ay = a.latitude;
    double bx = b.longitude;
    double by = b.latitude;
    double px = p.longitude;
    double py = p.latitude;

    double abx = bx - ax;
    double aby = by - ay;
    double apx = px - ax;
    double apy = py - ay;

    double abLen2 = abx * abx + aby * aby;
    if (abLen2 == 0) return a;

    double t = (apx * abx + apy * aby) / abLen2;
    t = t.clamp(0.0, 1.0);

    return LatLng(ay + t * aby, ax + t * abx);
  }

  void _updatePositionWithPDR() {
    if (_currentPosition == null) return;

    // Convert heading from degrees to radians
    double headingRad = _currentHeading * (pi / 180.0);

    // Calculate dx and dy in meters
    double dx = _currentStepLength * sin(headingRad);
    double dy = _currentStepLength * cos(headingRad);

    // Update latitude and longitude based on Earth curvature
    double dLat = (dy / _earthRadius) * (180.0 / pi);
    double dLng = (dx / (_earthRadius * cos(_currentPosition!.latitude * pi / 180.0))) * (180.0 / pi);

    LatLng rawNextPosition = LatLng(_currentPosition!.latitude + dLat, _currentPosition!.longitude + dLng);
    LatLng nextPosition = rawNextPosition;

    // 4. Map Matching / Snapping
    if (enableSnapping) {
      if (activeRoute.isNotEmpty) {
        // Snap to active route polyline segments
        LatLng? closestPoint;
        double minDist = double.infinity;
        for (int i = 0; i < activeRoute.length - 1; i++) {
          LatLng projected = _projectPointToSegment(rawNextPosition, activeRoute[i], activeRoute[i + 1]);
          double dist = _distance(rawNextPosition, projected);
          if (dist < minDist) {
            minDist = dist;
            closestPoint = projected;
          }
        }
        if (closestPoint != null && minDist <= snappingThresholdMeters) {
          nextPosition = closestPoint;
        }
      } else if (roadEdges.isNotEmpty) {
        // Snap to nearest road segment in the campus road network
        LatLng? closestPoint;
        double minDist = double.infinity;
        for (var edge in roadEdges) {
          if (edge.length == 2) {
            LatLng projected = _projectPointToSegment(rawNextPosition, edge[0], edge[1]);
            double dist = _distance(rawNextPosition, projected);
            if (dist < minDist) {
              minDist = dist;
              closestPoint = projected;
            }
          }
        }
        if (closestPoint != null && minDist <= snappingThresholdMeters) {
          nextPosition = closestPoint;
        }
      }
    }

    _currentPosition = nextPosition;

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
