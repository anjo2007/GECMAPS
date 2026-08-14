import 'dart:math';
import 'package:latlong2/latlong.dart';

enum PositioningMode {
  vpsLocked,
  fusedHybrid,
  gpsOnly,
  pdrDeadReckoning,
}

class VPSSensorFusionResult {
  final LatLng position;
  final double accuracyMeters; // Estimated error bound in meters (e.g. ±0.2m)
  final double confidenceScore; // 0.0 to 1.0 (0% to 100%)
  final PositioningMode mode;
  final String modeLabel;
  final int floor;
  final double heading;
  final String locationName;
  final DateTime timestamp;

  VPSSensorFusionResult({
    required this.position,
    required this.accuracyMeters,
    required this.confidenceScore,
    required this.mode,
    required this.modeLabel,
    required this.floor,
    required this.heading,
    required this.locationName,
    required this.timestamp,
  });
}

/// Comprehensive report comparing visual ground truth from VPS with raw GPS sensor readings
class VPSGPSComparisonReport {
  final LatLng vpsAnchorPosition;
  final LatLng gpsRawPosition;
  final double displacementMeters; // Distance between visual anchor & raw GPS
  final double gpsReportedAccuracy;
  final double vpsConfidence;
  final bool isGpsMultipathOutlier; // True if GPS drifted significantly (> 3 * sigma + 10m)
  final double latitudeBiasCorrection; // Delta to correct subsequent GPS measurements
  final double longitudeBiasCorrection;
  final LatLng calibratedPosition;
  final double fusedAccuracyMeters;
  final int floor;
  final String locationName;
  final String diagnosticMessage;

  VPSGPSComparisonReport({
    required this.vpsAnchorPosition,
    required this.gpsRawPosition,
    required this.displacementMeters,
    required this.gpsReportedAccuracy,
    required this.vpsConfidence,
    required this.isGpsMultipathOutlier,
    required this.latitudeBiasCorrection,
    required this.longitudeBiasCorrection,
    required this.calibratedPosition,
    required this.fusedAccuracyMeters,
    required this.floor,
    required this.locationName,
    required this.diagnosticMessage,
  });
}

/// Advanced Sensor Fusion Engine combining Camera VPS Data (QR, OCR, SLAM features),
/// Real-time GPS stream, and PDR Step Dead Reckoning.
class VPSSensorFusionService {
  static const double _earthRadius = 6371000.0; // meters

  LatLng? _fusedPosition;
  double _fusedHeading = 0.0;
  double _headingOffset = 0.0;
  double _currentAccuracy = 12.0; // meters
  double _currentConfidence = 0.40;
  PositioningMode _currentMode = PositioningMode.gpsOnly;
  String _locationName = "GPS Estimator";
  int _currentFloor = 0;

  // VPS Camera Visual Anchor State
  LatLng? _lastVpsAnchorPos;
  DateTime? _lastVpsAnchorTime;
  double _vpsAnchorConfidence = 0.0;

  // GPS State
  LatLng? _lastGpsPos;
  double _lastGpsAccuracy = 20.0;
  DateTime? _lastGpsTime;

  // SLAM & Optical Feature Metrics
  int _slamFeatureCount = 0;
  // ignore: unused_field
  double _visualStability = 0.5; // 0.0 (unstable/moving) to 1.0 (locked)

  // Distance calculator
  final Distance _distCalc = const Distance();

  LatLng? get fusedPosition => _fusedPosition;
  double get fusedHeading => _fusedHeading;
  double get currentAccuracy => _currentAccuracy;
  double get currentConfidence => _currentConfidence;
  PositioningMode get currentMode => _currentMode;
  int get currentFloor => _currentFloor;
  LatLng? get lastVpsAnchorPos => _lastVpsAnchorPos;
  LatLng? get lastGpsPos => _lastGpsPos;
  double get lastGpsAccuracy => _lastGpsAccuracy;

  /// Reset or initialize fusion state with a starting coordinate
  void initialize(LatLng startPos, {double initialHeading = 0.0, int floor = 0}) {
    _fusedPosition = startPos;
    _fusedHeading = initialHeading;
    _currentFloor = floor;
    _currentAccuracy = 8.0;
    _currentConfidence = 0.50;
    _currentMode = PositioningMode.gpsOnly;
    _locationName = "Initial Position";
  }

  /// Process camera QR code or high-precision visual anchor lock
  VPSSensorFusionResult processVisualAnchor({
    required LatLng anchorPos,
    required int floor,
    required double confidence,
    required String name,
    double? knownHeading,
    double rawCompassHeading = 0.0,
  }) {
    _lastVpsAnchorPos = anchorPos;
    _lastVpsAnchorTime = DateTime.now();
    _vpsAnchorConfidence = confidence.clamp(0.0, 1.0);
    _currentFloor = floor;
    _locationName = name;

    // Calibrate compass heading offset if known visual heading is provided
    if (knownHeading != null) {
      _headingOffset = (knownHeading - rawCompassHeading + 360.0) % 360.0;
      _fusedHeading = knownHeading;
    }

    // High precision snap when visual confidence >= 0.80
    if (_vpsAnchorConfidence >= 0.80) {
      _fusedPosition = anchorPos;
      _currentAccuracy = (1.0 - _vpsAnchorConfidence) * 0.8 + 0.2; // e.g. ±0.2m
      _currentConfidence = _vpsAnchorConfidence;
      _currentMode = PositioningMode.vpsLocked;
    } else {
      // Blend visual position with existing estimate
      if (_fusedPosition != null) {
        double weight = _vpsAnchorConfidence * 0.70;
        double blendedLat = weight * anchorPos.latitude + (1 - weight) * _fusedPosition!.latitude;
        double blendedLng = weight * anchorPos.longitude + (1 - weight) * _fusedPosition!.longitude;
        _fusedPosition = LatLng(blendedLat, blendedLng);
      } else {
        _fusedPosition = anchorPos;
      }
      _currentAccuracy = 1.5;
      _currentConfidence = max(_currentConfidence, _vpsAnchorConfidence);
      _currentMode = PositioningMode.fusedHybrid;
    }

    return getFusedResult();
  }

  /// Special VPS vs GPS Comparison & Differential Calibration Algorithm:
  /// Performs vector comparison between camera visual ground truth and real-time GPS fix.
  /// Computes spatial bias, multipath error status, and optimal inverse-variance fused coordinate.
  VPSGPSComparisonReport compareAndFuseVPSWithGPS({
    required LatLng vpsAnchorPos,
    required int floor,
    required double vpsConfidence,
    required String locationName,
    LatLng? currentGpsPos,
    double gpsAccuracy = 15.0,
    double? knownHeading,
    double rawCompassHeading = 0.0,
  }) {
    final effectiveGps = currentGpsPos ?? _lastGpsPos ?? _fusedPosition ?? vpsAnchorPos;
    final double displacement = _distCalc.as(LengthUnit.Meter, vpsAnchorPos, effectiveGps);

    // Calculate GPS spatial bias: (Ground Truth - GPS)
    final double latBias = vpsAnchorPos.latitude - effectiveGps.latitude;
    final double lngBias = vpsAnchorPos.longitude - effectiveGps.longitude;

    // Detect GPS multipath / building signal occlusion
    final bool isMultipath = displacement > (3.0 * gpsAccuracy + 8.0) || displacement > 25.0;

    // Inverse-variance fusion weighting
    // VPS variance: sigma_vps = (1.0 - confidence) * 0.4 + 0.1 (e.g. 0.15m)
    // GPS variance: sigma_gps = max(gpsAccuracy, 1.0)
    final double sigmaVps = ((1.0 - vpsConfidence) * 0.4 + 0.1).clamp(0.1, 2.0);
    final double sigmaGps = isMultipath ? 500.0 : max(gpsAccuracy, 2.0);

    final double varVps = sigmaVps * sigmaVps;
    final double varGps = sigmaGps * sigmaGps;

    // Weight for VPS: w_vps = varGps / (varVps + varGps)
    final double vpsWeight = (varGps / (varVps + varGps)).clamp(0.85, 1.0);

    final double fusedLat = vpsWeight * vpsAnchorPos.latitude + (1.0 - vpsWeight) * effectiveGps.latitude;
    final double fusedLng = vpsWeight * vpsAnchorPos.longitude + (1.0 - vpsWeight) * effectiveGps.longitude;
    final LatLng calibratedPos = LatLng(fusedLat, fusedLng);

    final double fusedAccuracy = sqrt((varVps * varGps) / (varVps + varGps)).clamp(0.2, 2.0);

    // Apply calibration into fusion state
    _fusedPosition = calibratedPos;
    _currentFloor = floor;
    _locationName = locationName;
    _lastVpsAnchorPos = vpsAnchorPos;
    _lastVpsAnchorTime = DateTime.now();
    _vpsAnchorConfidence = vpsConfidence;
    _currentAccuracy = fusedAccuracy;
    _currentConfidence = max(vpsConfidence, 0.95);
    _currentMode = PositioningMode.vpsLocked;

    if (knownHeading != null) {
      _headingOffset = (knownHeading - rawCompassHeading + 360.0) % 360.0;
      _fusedHeading = knownHeading;
    }

    String diag;
    if (isMultipath) {
      diag = "GPS multipath drift of ${displacement.toStringAsFixed(1)}m corrected. Snapped to optical anchor.";
    } else {
      diag = "VPS & GPS cross-validated (offset: ${displacement.toStringAsFixed(1)}m, accuracy: ±${fusedAccuracy.toStringAsFixed(1)}m).";
    }

    return VPSGPSComparisonReport(
      vpsAnchorPosition: vpsAnchorPos,
      gpsRawPosition: effectiveGps,
      displacementMeters: displacement,
      gpsReportedAccuracy: gpsAccuracy,
      vpsConfidence: vpsConfidence,
      isGpsMultipathOutlier: isMultipath,
      latitudeBiasCorrection: latBias,
      longitudeBiasCorrection: lngBias,
      calibratedPosition: calibratedPos,
      fusedAccuracyMeters: fusedAccuracy,
      floor: floor,
      locationName: locationName,
      diagnosticMessage: diag,
    );
  }

  /// Process live GPS position update with accuracy, speed, and heading
  VPSSensorFusionResult updateGPS({
    required LatLng gpsPos,
    required double accuracy,
    required double speed,
    double gpsHeading = -1.0,
  }) {
    final now = DateTime.now();
    _lastGpsPos = gpsPos;
    _lastGpsAccuracy = accuracy.clamp(0.5, 200.0);
    _lastGpsTime = now;

    if (_fusedPosition == null) {
      _fusedPosition = gpsPos;
      _currentAccuracy = accuracy;
      _currentConfidence = _calculateConfidence(accuracy, false);
      _currentMode = PositioningMode.gpsOnly;
      return getFusedResult();
    }

    // Reject GPS teleports / multipath outliers
    double jumpMeters = _distCalc.as(LengthUnit.Meter, _fusedPosition!, gpsPos);
    if ((accuracy > 25.0 && jumpMeters > 35.0) || jumpMeters > 80.0) {
      // Outlier rejected; preserve fused position
      return getFusedResult();
    }

    // Evaluate VPS Anchor Age (visual anchor stays highly dominant for 15 seconds)
    bool isVpsRecent = _lastVpsAnchorTime != null &&
        now.difference(_lastVpsAnchorTime!).inSeconds < 15 &&
        _vpsAnchorConfidence >= 0.80;

    if (isVpsRecent) {
      // When VPS visual lock is active, GPS only gently corrects background drift
      double gpsAlpha = (4.0 / (accuracy + 10.0)).clamp(0.02, 0.12);
      double fusedLat = (1 - gpsAlpha) * _fusedPosition!.latitude + gpsAlpha * gpsPos.latitude;
      double fusedLng = (1 - gpsAlpha) * _fusedPosition!.longitude + gpsAlpha * gpsPos.longitude;
      _fusedPosition = LatLng(fusedLat, fusedLng);

      final elapsedSecs = now.difference(_lastVpsAnchorTime!).inSeconds;
      _currentAccuracy = ((1.0 - _vpsAnchorConfidence) * 0.8 + 0.5 + elapsedSecs * 0.08).clamp(0.5, 5.0);
      _currentConfidence = (_vpsAnchorConfidence - elapsedSecs * 0.02).clamp(0.50, 0.98);
      _currentMode = PositioningMode.vpsLocked;
    } else {
      // Standard Outdoor / Hybrid Fusion
      // Trust GPS heavily if accuracy < 5m; rely on PDR dead reckoning if GPS accuracy > 15m
      double alpha;
      if (accuracy < 4.0) {
        alpha = 0.85;
      } else if (accuracy < 10.0) {
        alpha = 0.60;
      } else if (accuracy < 20.0) {
        alpha = 0.35;
      } else {
        alpha = 0.10; // Rely on PDR
      }

      // Feature density boost if SLAM points are available
      if (_slamFeatureCount > 30) {
        alpha *= 0.85; // Give more weight to PDR/Camera visual tracking
      }

      double fusedLat = alpha * gpsPos.latitude + (1 - alpha) * _fusedPosition!.latitude;
      double fusedLng = alpha * gpsPos.longitude + (1 - alpha) * _fusedPosition!.longitude;
      _fusedPosition = LatLng(fusedLat, fusedLng);

      _currentAccuracy = (alpha * accuracy + (1 - alpha) * _currentAccuracy).clamp(0.5, 30.0);
      _currentConfidence = _calculateConfidence(_currentAccuracy, _slamFeatureCount > 20);

      if (_slamFeatureCount > 20 || (_lastVpsAnchorTime != null && now.difference(_lastVpsAnchorTime!).inSeconds < 60)) {
        _currentMode = PositioningMode.fusedHybrid;
      } else {
        _currentMode = PositioningMode.gpsOnly;
      }
    }

    // Blend GPS heading when speed > 0.8 m/s
    if (gpsHeading >= 0.0 && speed > 0.8) {
      double gpsWeight = (speed / 3.0).clamp(0.0, 0.5);
      double radFused = _fusedHeading * (pi / 180.0);
      double radGps = gpsHeading * (pi / 180.0);
      double sinB = (1 - gpsWeight) * sin(radFused) + gpsWeight * sin(radGps);
      double cosB = (1 - gpsWeight) * cos(radFused) + gpsWeight * cos(radGps);
      _fusedHeading = (atan2(sinB, cosB) * 180.0 / pi + 360.0) % 360.0;
    }

    return getFusedResult();
  }

  /// Process PDR step detection with dynamic step length and compass heading
  VPSSensorFusionResult updatePDRStep({
    required double stepLengthMeters,
    required double rawCompassHeading,
  }) {
    _fusedHeading = (rawCompassHeading + _headingOffset + 360.0) % 360.0;

    if (_fusedPosition == null) return getFusedResult();

    double headingRad = _fusedHeading * (pi / 180.0);
    double dx = stepLengthMeters * sin(headingRad);
    double dy = stepLengthMeters * cos(headingRad);

    double dLat = (dy / _earthRadius) * (180.0 / pi);
    double dLng = (dx / (_earthRadius * cos(_fusedPosition!.latitude * pi / 180.0))) * (180.0 / pi);

    _fusedPosition = LatLng(_fusedPosition!.latitude + dLat, _fusedPosition!.longitude + dLng);

    // Dynamic confidence decay if no recent GPS or VPS update
    final now = DateTime.now();
    bool isGpsFresh = _lastGpsTime != null && now.difference(_lastGpsTime!).inSeconds < 10;
    bool isVpsFresh = _lastVpsAnchorTime != null && now.difference(_lastVpsAnchorTime!).inSeconds < 20;

    if (isVpsFresh) {
      _currentMode = PositioningMode.vpsLocked;
      _currentAccuracy = 0.4;
    } else if (isGpsFresh) {
      _currentMode = PositioningMode.fusedHybrid;
    } else {
      _currentMode = PositioningMode.pdrDeadReckoning;
      _currentAccuracy = (_currentAccuracy + 0.15).clamp(0.5, 25.0);
    }

    return getFusedResult();
  }

  /// Update SLAM feature density and optical movement metrics
  void updateSLAMMetrics(int featureCount, double stability) {
    _slamFeatureCount = featureCount;
    _visualStability = stability.clamp(0.0, 1.0);
  }

  /// Calculate confidence score based on error radius and visual tracking
  double _calculateConfidence(double accuracyMeters, bool hasVisualFeatures) {
    double baseScore;
    if (accuracyMeters <= 1.0) {
      baseScore = 0.98;
    } else if (accuracyMeters <= 5.0) {
      baseScore = 0.85;
    } else if (accuracyMeters <= 10.0) {
      baseScore = 0.72;
    } else if (accuracyMeters <= 18.0) {
      baseScore = 0.50;
    } else {
      baseScore = 0.30;
    }

    if (hasVisualFeatures) {
      baseScore = (baseScore + 0.10).clamp(0.0, 1.0);
    }

    return baseScore;
  }

  String _getModeLabel(PositioningMode mode) {
    switch (mode) {
      case PositioningMode.vpsLocked:
        return "VPS LOCKED";
      case PositioningMode.fusedHybrid:
        return "FUSED HYBRID";
      case PositioningMode.gpsOnly:
        return "GPS ONLY";
      case PositioningMode.pdrDeadReckoning:
        return "PDR DEAD RECKONING";
    }
  }

  /// Get current fused positioning result object
  VPSSensorFusionResult getFusedResult() {
    return VPSSensorFusionResult(
      position: _fusedPosition ?? const LatLng(0, 0),
      accuracyMeters: _currentAccuracy,
      confidenceScore: _currentConfidence,
      mode: _currentMode,
      modeLabel: _getModeLabel(_currentMode),
      floor: _currentFloor,
      heading: _fusedHeading,
      locationName: _locationName,
      timestamp: DateTime.now(),
    );
  }
}
