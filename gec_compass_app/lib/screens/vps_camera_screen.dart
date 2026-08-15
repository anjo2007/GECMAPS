import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:flutter_map/flutter_map.dart';
import '../services/pdr_service.dart';
import '../services/vps_sensor_fusion.dart';
import '../services/vps_relocalization_service.dart';
import '../services/location_status_service.dart';
import '../widgets/top_message_overlay.dart';

class VPSCameraScreen extends StatefulWidget {
  final LatLng startPosition;
  final List<LatLng> routingPath;
  final String destinationName;
  final int targetFloor;
  final String? vpsBoardPhotoBase64;
  final String? vpsText;

  const VPSCameraScreen({
    super.key,
    required this.startPosition,
    required this.routingPath,
    required this.destinationName,
    required this.targetFloor,
    this.vpsBoardPhotoBase64,
    this.vpsText,
  });

  @override
  State<VPSCameraScreen> createState() => _VPSCameraScreenState();
}

class SLAMPoint {
  final LatLng position;
  final double height;
  final Color color;
  final double scale;
  final double flickerPhase;
  bool isLocked;

  SLAMPoint({
    required this.position,
    required this.height,
    required this.color,
    required this.scale,
    required this.flickerPhase,
    this.isLocked = true,
  });
}

class OCRTextAnchor {
  final String text;
  final double bearing;
  final double elevation;
  Offset? screenPos;
  bool isTarget;

  OCRTextAnchor({
    required this.text,
    required this.bearing,
    required this.elevation,
    this.isTarget = false,
  });
}

class _VPSCameraScreenState extends State<VPSCameraScreen> with TickerProviderStateMixin {
  final MobileScannerController _scannerController = MobileScannerController();
  final bool _isCameraInitialized = true;
  final bool _cameraLoadFailed = false;

  // Services
  final PDRService _pdrService = PDRService();
  final VPSSensorFusionService _sensorFusion = VPSSensorFusionService();
  final VPSRelocalizationService _relocalizationService = VPSRelocalizationService();
  final LocationStatusService _locationStatusService = LocationStatusService();

  // Subscriptions
  StreamSubscription<CompassEvent>? _compassSubscription;
  StreamSubscription<UserAccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<Position>? _gpsSubscription;

  // Timers & Controllers
  Timer? _autoCalibrateTimer;
  late AnimationController _pulseController;
  late AnimationController _radarRippleController;

  // Sensor state & fused positioning
  double _heading = 0.0;
  double _pitch = 0.0;
  double _roll = 0.0;
  double _headingSin = 0.0;
  double _headingCos = 1.0;
  double _headingOffset = 0.0;
  double _rawCompassHeading = 0.0;

  // Fused Result & VPS-GPS Comparison State
  late VPSSensorFusionResult _fusionResult;
  VPSRelocalizationResult? _lastRelocResult;
  LatLng? _lastRawGpsPos;
  double _lastGpsAccuracy = 15.0;

  // Calibration state
  bool _isCalibrated = false;
  // ignore: unused_field
  String _calibrationStatus = "Uncalibrated - Point camera at room signboard for Auto-Calibration";

  // SLAM & OCR Simulation State
  final List<SLAMPoint> _slamPoints = [];
  final List<OCRTextAnchor> _ocrAnchors = [];
  double _targetSignboardBearing = 0.0;
  double _lockOnProgress = 0.0;

  // Developer Debug Console State
  bool _showDebugConsole = false;
  // ignore: prefer_final_fields
  bool _injectNoise = false;
  // ignore: unused_field
  int _stepCount = 0;
  final List<double> _accelHistory = [];

  // Enhanced 2D Mini-Map State
  final MapController _miniMapController = MapController();
  bool _isMiniMapExpanded = false;
  double _miniMapZoom = 18.5;
  String _mapTileStyle = "voyager"; // "voyager" or "dark"

  @override
  void initState() {
    super.initState();

    // Initialize sensor fusion engine
    _sensorFusion.initialize(widget.startPosition, floor: widget.targetFloor);
    _fusionResult = _sensorFusion.getFusedResult();

    _initSLAMPoints();
    _initOCRAnchors();

    // Tickers for AR scanline & radar ripple animations
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _pulseController.addListener(() => setState(() {}));

    _radarRippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _startLocationAndSensorStreams();
    _setupAutoCalibration();
  }

  @override
  void dispose() {
    _compassSubscription?.cancel();
    _accelerometerSubscription?.cancel();
    _gpsSubscription?.cancel();
    _autoCalibrateTimer?.cancel();
    _pulseController.dispose();
    _radarRippleController.dispose();
    _pdrService.stopPDR();
    _locationStatusService.stopMonitoring();
    _scannerController.dispose();
    super.dispose();
  }

  void _startLocationAndSensorStreams() async {
    // 1. Monitor Location Service Status & handle disabled state
    bool isLocationOk = await _locationStatusService.startMonitoring(callback: (enabled) {
      if (!enabled && mounted) {
        TopMessageOverlay.showLocationAlert(
          context,
          onOpenSettings: _locationStatusService.openSettings,
          onReload: _reloadLocationService,
        );
      }
    });

    if (!isLocationOk && mounted) {
      TopMessageOverlay.showLocationAlert(
        context,
        onOpenSettings: _locationStatusService.openSettings,
        onReload: _reloadLocationService,
      );
    }

    // 2. Start GPS Stream for Sensor Fusion
    try {
      _gpsSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 1,
        ),
      ).listen((Position position) {
        if (!mounted) return;
        final latLng = LatLng(position.latitude, position.longitude);
        _lastRawGpsPos = latLng;
        _lastGpsAccuracy = position.accuracy;
        setState(() {
          _fusionResult = _sensorFusion.updateGPS(
            gpsPos: latLng,
            accuracy: position.accuracy,
            speed: position.speed,
            gpsHeading: position.heading >= 0 ? position.heading : -1.0,
          );
          _pdrService.updateGPSPosition(latLng, position.accuracy, position.speed, position.heading);
          try {
            _miniMapController.move(_fusionResult.position, _miniMapZoom);
          } catch (_) {}
        });
      }, onError: (e) {
        debugPrint("VPS GPS Stream error: $e");
      });
    } catch (e) {
      debugPrint("Error listening to GPS in VPS: $e");
    }

    // 3. Start Compass stream with smoothing filter
    _compassSubscription = FlutterCompass.events?.listen((CompassEvent event) {
      if (!mounted) return;
      double raw = event.heading ?? 0.0;

      if (_injectNoise) {
        final double noise = 15.0 * sin(DateTime.now().millisecondsSinceEpoch / 150.0) +
            (Random().nextDouble() - 0.5) * 6.0;
        raw = (raw + noise) % 360;
      }

      setState(() {
        _rawCompassHeading = raw;
        final double currentRawHeading = (raw + _headingOffset + 360) % 360;
        final double headingRad = currentRawHeading * pi / 180.0;

        _headingSin = _headingSin * 0.82 + sin(headingRad) * 0.18;
        _headingCos = _headingCos * 0.82 + cos(headingRad) * 0.18;
        _heading = (atan2(_headingSin, _headingCos) * 180.0 / pi + 360) % 360;
      });
    });

    // 4. Start PDR step reckoning stream
    _pdrService.startPDR(widget.startPosition);
    _pdrService.onPositionUpdated = (LatLng newPosition) {
      if (!mounted) return;
      setState(() {
        _fusionResult = _sensorFusion.updatePDRStep(
          stepLengthMeters: 0.70,
          rawCompassHeading: _rawCompassHeading,
        );
        try {
          _miniMapController.move(_fusionResult.position, _miniMapZoom);
        } catch (_) {}
      });
    };

    _pdrService.onStepDetected = (int count) {
      if (!mounted) return;
      setState(() {
        _stepCount = count;
      });
    };

    // 5. Accelerometer tilt subscription
    _accelerometerSubscription = userAccelerometerEventStream().listen((event) {
      if (!mounted) return;

      final double pitchAngle = atan2(event.z, -event.y);
      final double rollAngle = atan2(event.x, -event.y);

      setState(() {
        _pitch = _pitch * 0.8 + pitchAngle * 0.2;
        _roll = _roll * 0.8 + rollAngle * 0.2;

        final double accelMag = _pdrService.rawAccelMagnitude;
        _accelHistory.add(accelMag);
        if (_accelHistory.length > 60) {
          _accelHistory.removeAt(0);
        }
      });
    });
  }

  void _reloadLocationService() async {
    _gpsSubscription?.cancel();
    _gpsSubscription = null;

    bool enabled = await Geolocator.isLocationServiceEnabled();
    if (enabled && mounted) {
      TopMessageOverlay.show(
        context,
        title: "📍 Location Restored",
        message: "GPS location active. Re-establishing VPS camera & map tracking...",
        type: TopMessageType.success,
      );
      _startLocationAndSensorStreams();
    } else if (mounted) {
      TopMessageOverlay.showLocationAlert(
        context,
        onOpenSettings: _locationStatusService.openSettings,
        onReload: _reloadLocationService,
      );
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isCalibrated) return;

    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      final String? rawValue = barcode.rawValue;
      if (rawValue != null) {
        final relocResult = _relocalizationService.parsePayload(
          rawValue,
          rawCompassHeading: _rawCompassHeading,
          currentGpsPos: _lastRawGpsPos,
          gpsAccuracy: _lastGpsAccuracy,
        );
        if (relocResult.isSuccess) {
          HapticFeedback.heavyImpact();
          _lastRelocResult = relocResult;

          setState(() {
            _fusionResult = _sensorFusion.getFusedResult();

            if (relocResult.heading != null) {
              _headingOffset = (relocResult.heading! - _rawCompassHeading + 360) % 360;
              _heading = (_rawCompassHeading + _headingOffset + 360) % 360;
            }

            _isCalibrated = true;
            _calibrationStatus = "VPS Calibrated via QR Anchor";
            _pdrService.forceSetPosition(_fusionResult.position);
          });

          TopMessageOverlay.show(
            context,
            title: "🎯 VPS Relocalized!",
            message: relocResult.message,
            type: TopMessageType.success,
            duration: const Duration(seconds: 5),
          );

          _scannerController.stop();
          return;
        }
      }
    }
  }

  void _initSLAMPoints() {
    final random = Random();
    final List<LatLng> bases = [widget.startPosition, ...widget.routingPath];

    for (var basePt in bases) {
      for (int k = 0; k < 6; k++) {
        final double dist = random.nextDouble() * 12.0 + 1.5;
        final double angle = random.nextDouble() * 2 * pi;

        final double dx = dist * sin(angle);
        final double dy = dist * cos(angle);

        const double rEarth = 6378137.0;
        final double dLat = (dy / rEarth) * (180.0 / pi);
        final double dLng = (dx / (rEarth * cos(basePt.latitude * pi / 180.0))) * (180.0 / pi);
        final double h = random.nextDouble() * 3.0 - 1.5;

        final colors = [
          const Color(0xFF67E8F9),
          const Color(0xFF38BDF8),
          const Color(0xFF4ADE80),
          const Color(0xFFFCD34D),
        ];

        _slamPoints.add(SLAMPoint(
          position: LatLng(basePt.latitude + dLat, basePt.longitude + dLng),
          height: h,
          color: colors[random.nextInt(colors.length)],
          scale: random.nextDouble() * 0.7 + 0.4,
          flickerPhase: random.nextDouble() * 2 * pi,
        ));
      }
    }

    _sensorFusion.updateSLAMMetrics(_slamPoints.length, 0.90);
  }

  void _initOCRAnchors() {
    if (widget.routingPath.length >= 2) {
      final p1 = widget.startPosition;
      final p2 = widget.routingPath[1];
      _targetSignboardBearing = _calculateBearing(p1, p2);
    } else {
      _targetSignboardBearing = 0.0;
    }

    _ocrAnchors.add(OCRTextAnchor(
      text: widget.vpsText ?? "ROOM SIGNBOARD",
      bearing: _targetSignboardBearing,
      elevation: 0.05,
      isTarget: true,
    ));

    _ocrAnchors.add(OCRTextAnchor(
      text: "EXIT",
      bearing: (_targetSignboardBearing + 50) % 360,
      elevation: 0.12,
    ));
    _ocrAnchors.add(OCRTextAnchor(
      text: "LAB 204",
      bearing: (_targetSignboardBearing - 45) % 360,
      elevation: -0.05,
    ));
  }

  double _calculateBearing(LatLng p1, LatLng p2) {
    final double lat1 = p1.latitude * pi / 180.0;
    final double lat2 = p2.latitude * pi / 180.0;
    final double dLng = (p2.longitude - p1.longitude) * pi / 180.0;

    final double y = sin(dLng) * cos(lat2);
    final double x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng);
    return (atan2(y, x) * 180.0 / pi + 360) % 360;
  }

  void _setupAutoCalibration() {
    _autoCalibrateTimer = Timer.periodic(const Duration(milliseconds: 250), (timer) {
      if (!mounted || _isCalibrated || (!_isCameraInitialized && !_cameraLoadFailed)) return;

      final double pitchDegree = _pitch * 180.0 / pi;
      final double accelMag = _pdrService.rawAccelMagnitude;

      final bool isUpright = pitchDegree.abs() < 25.0;
      final bool isSteady = accelMag < 0.85;

      double diff = (_heading - _targetSignboardBearing).abs();
      if (diff > 180) diff = 360 - diff;
      final bool isFacingSignboard = diff < 28.0;

      if (isUpright && isSteady && isFacingSignboard) {
        setState(() {
          _lockOnProgress = (_lockOnProgress + 0.12).clamp(0.0, 1.0);
        });

        if (_lockOnProgress >= 1.0) {
          HapticFeedback.heavyImpact();
          final report = _sensorFusion.compareAndFuseVPSWithGPS(
            vpsAnchorPos: widget.startPosition,
            floor: widget.targetFloor,
            vpsConfidence: 0.92,
            locationName: widget.destinationName,
            currentGpsPos: _lastRawGpsPos,
            gpsAccuracy: _lastGpsAccuracy,
            knownHeading: _targetSignboardBearing,
            rawCompassHeading: _rawCompassHeading,
          );

          _lastRelocResult = VPSRelocalizationResult(
            position: report.calibratedPosition,
            floor: widget.targetFloor,
            confidenceScore: 0.92,
            locationName: widget.destinationName,
            isSuccess: true,
            message: "Room Signboard Anchored! Position fused accuracy ±${report.fusedAccuracyMeters.toStringAsFixed(1)}m",
            heading: _targetSignboardBearing,
            comparisonReport: report,
          );

          setState(() {
            _headingOffset = (_targetSignboardBearing - _rawCompassHeading + 360) % 360;
            _heading = (_rawCompassHeading + _headingOffset + 360) % 360;
            _isCalibrated = true;
            _calibrationStatus = "VPS Auto-Calibrated via Signboard OCR";
            _fusionResult = _sensorFusion.getFusedResult();
          });

          TopMessageOverlay.show(
            context,
            title: "✨ VPS Signboard Calibrated!",
            message: "Room Signboard Anchored! Accuracy ±${report.fusedAccuracyMeters.toStringAsFixed(1)}m",
            type: TopMessageType.success,
          );
        }
      } else {
        if (_lockOnProgress > 0.0) {
          setState(() {
            _lockOnProgress = (_lockOnProgress - 0.08).clamp(0.0, 1.0);
          });
        }
      }
    });
  }

  Color get _modeColor {
    switch (_fusionResult.mode) {
      case PositioningMode.vpsLocked:
        return const Color(0xFF10B981); // Emerald
      case PositioningMode.fusedHybrid:
        return const Color(0xFF06B6D4); // Cyan
      case PositioningMode.gpsOnly:
        return const Color(0xFF3B82F6); // Blue
      case PositioningMode.pdrDeadReckoning:
        return const Color(0xFFF59E0B); // Amber
    }
  }

  Uint8List? _safeBase64Decode(String? input) {
    if (input == null || input.isEmpty) return null;
    try {
      String clean = input;
      if (clean.contains(',')) {
        clean = clean.split(',').last;
      }
      clean = clean.replaceAll(RegExp(r'\s+'), '');
      return base64Decode(clean);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Distance distCalc = const Distance();
    double distRemaining = 0.0;
    if (widget.routingPath.isNotEmpty) {
      distRemaining = distCalc.as(LengthUnit.Meter, _fusionResult.position, widget.routingPath.last);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Mobile Camera Viewfinder
          Positioned.fill(
            child: MobileScanner(
              controller: _scannerController,
              onDetect: _onDetect,
              fit: BoxFit.cover,
            ),
          ),

          // Dark vignette overlay
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 0.9,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.65),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 2. High-Visibility Real-Time 2D Map Overlay
          Positioned(
            left: 16,
            top: MediaQuery.of(context).padding.top + 85,
            child: RepaintBoundary(
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() {
                    _isMiniMapExpanded = !_isMiniMapExpanded;
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  width: _isMiniMapExpanded ? 230 : 115,
                  height: _isMiniMapExpanded ? 230 : 115,
                  decoration: BoxDecoration(
                    color: const Color(0xEC0F172A),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _modeColor, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: _modeColor.withValues(alpha: 0.35),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                      const BoxShadow(
                        color: Colors.black87,
                        blurRadius: 18,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      children: [
                        FlutterMap(
                          mapController: _miniMapController,
                          options: MapOptions(
                            initialCenter: _fusionResult.position,
                            initialZoom: _miniMapZoom,
                            interactionOptions: InteractionOptions(
                              flags: _isMiniMapExpanded ? InteractiveFlag.all : InteractiveFlag.none,
                            ),
                          ),
                          children: [
                            TileLayer(
                              urlTemplate: _mapTileStyle == "voyager"
                                  ? 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png'
                                  : 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                              subdomains: const ['a', 'b', 'c', 'd'],
                              userAgentPackageName: 'com.example.gec_compass_app',
                            ),
                            PolylineLayer(
                              polylines: [
                                if (widget.routingPath.isNotEmpty)
                                  Polyline(
                                    points: widget.routingPath,
                                    color: Colors.cyanAccent,
                                    strokeWidth: 4.5,
                                  ),
                              ],
                            ),
                            MarkerLayer(
                              markers: [
                                // Destination Target Pin
                                if (widget.routingPath.isNotEmpty)
                                  Marker(
                                    point: widget.routingPath.last,
                                    width: 32,
                                    height: 32,
                                    rotate: true,
                                    child: const Icon(
                                      Icons.location_on_rounded,
                                      color: Colors.redAccent,
                                      size: 26,
                                    ),
                                  ),

                                // Fused User Location Marker + Camera Vision FOV Cone
                                Marker(
                                  point: _fusionResult.position,
                                  width: 50,
                                  height: 50,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      // Camera FOV vision cone
                                      CustomPaint(
                                        size: const Size(50, 50),
                                        painter: CameraFOVPainter(
                                          color: _modeColor,
                                          headingRad: _heading * pi / 180.0,
                                        ),
                                      ),
                                      // Pulsing radar ripple circle
                                      ScaleTransition(
                                        scale: Tween<double>(begin: 0.7, end: 1.3).animate(_radarRippleController),
                                        child: Container(
                                          width: 24,
                                          height: 24,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: _modeColor.withValues(alpha: 0.25),
                                            border: Border.all(color: _modeColor, width: 1.5),
                                          ),
                                        ),
                                      ),
                                      // Rotated direction arrow
                                      Transform.rotate(
                                        angle: _heading * pi / 180.0,
                                        child: Icon(
                                          Icons.navigation_rounded,
                                          color: _modeColor,
                                          size: 20,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        // Mini-Map Top Status Pill
                        Positioned(
                          left: 6,
                          top: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.82),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: _modeColor.withValues(alpha: 0.6), width: 1),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _modeColor,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _isMiniMapExpanded
                                      ? "2D MAP • ${_fusionResult.modeLabel}"
                                      : "±${_fusionResult.accuracyMeters.toStringAsFixed(1)}m",
                                  style: TextStyle(
                                    color: _modeColor,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Expanded Map Interactive Controls
                        if (_isMiniMapExpanded) ...[
                          Positioned(
                            right: 6,
                            top: 6,
                            child: Column(
                              children: [
                                _miniMapButton(
                                  icon: Icons.add,
                                  onTap: () {
                                    setState(() {
                                      _miniMapZoom = (_miniMapZoom + 0.5).clamp(15.0, 20.0);
                                      _miniMapController.move(_fusionResult.position, _miniMapZoom);
                                    });
                                  },
                                ),
                                const SizedBox(height: 4),
                                _miniMapButton(
                                  icon: Icons.remove,
                                  onTap: () {
                                    setState(() {
                                      _miniMapZoom = (_miniMapZoom - 0.5).clamp(15.0, 20.0);
                                      _miniMapController.move(_fusionResult.position, _miniMapZoom);
                                    });
                                  },
                                ),
                                const SizedBox(height: 4),
                                _miniMapButton(
                                  icon: Icons.my_location,
                                  onTap: () {
                                    _miniMapController.move(_fusionResult.position, _miniMapZoom);
                                  },
                                ),
                                const SizedBox(height: 4),
                                _miniMapButton(
                                  icon: Icons.layers_rounded,
                                  onTap: () {
                                    setState(() {
                                      _mapTileStyle = _mapTileStyle == "voyager" ? "dark" : "voyager";
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                          Positioned(
                            left: 6,
                            bottom: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.black87,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                "${distRemaining.toStringAsFixed(0)}m to ${widget.destinationName}",
                                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 3. Top Action Bar & Back Button
          Positioned(
            left: 16,
            right: 16,
            top: MediaQuery.of(context).padding.top + 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CircleAvatar(
                  backgroundColor: Colors.black87,
                  radius: 22,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                    onPressed: () {
                      Navigator.pop(context, _lastRelocResult ?? _fusionResult.position);
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xEC0F172A),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _modeColor.withValues(alpha: 0.8), width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _modeColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _fusionResult.modeLabel,
                        style: TextStyle(
                          color: _modeColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                CircleAvatar(
                  backgroundColor: Colors.black87,
                  radius: 22,
                  child: IconButton(
                    icon: Icon(
                      _showDebugConsole ? Icons.bug_report : Icons.bug_report_outlined,
                      color: Colors.cyanAccent,
                    ),
                    onPressed: () {
                      setState(() {
                        _showDebugConsole = !_showDebugConsole;
                      });
                    },
                  ),
                ),
              ],
            ),
          ),

          // 4. Target Signboard / Reference Photo PIP
          if (widget.vpsBoardPhotoBase64 != null)
            Positioned(
              right: 16,
              top: MediaQuery.of(context).padding.top + 85,
              child: GestureDetector(
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: const Color(0xFF0F172A),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      title: const Text("Target Room Signboard", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      content: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          _safeBase64Decode(widget.vpsBoardPhotoBase64) ?? Uint8List(0),
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  );
                },
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white54, width: 1.5),
                    boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8)],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      _safeBase64Decode(widget.vpsBoardPhotoBase64) ?? Uint8List(0),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _miniMapButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.8),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white30),
        ),
        child: Icon(icon, color: Colors.white, size: 14),
      ),
    );
  }
}

/// Custom painter for camera direction FOV vision cone on 2D map
class CameraFOVPainter extends CustomPainter {
  final Color color;
  final double headingRad;

  CameraFOVPainter({required this.color, required this.headingRad});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.48;

    final paint = Paint()
      ..shader = RadialGradient(
        colors: [color.withValues(alpha: 0.45), color.withValues(alpha: 0.0)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    final path = Path();
    path.moveTo(center.dx, center.dy);
    final startAngle = headingRad - (pi / 6) - (pi / 2);
    const sweepAngle = pi / 3;
    path.arcTo(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
    );
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CameraFOVPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.headingRad != headingRad;
}
