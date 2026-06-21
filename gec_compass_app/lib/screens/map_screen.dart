import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/building.dart';
import '../services/data_service.dart';
import '../services/pdr_service.dart';
import '../services/routing_service.dart';
import 'package:url_launcher/url_launcher.dart';

class TelemetryData {
  final double heading;
  final double accelX;
  final double accelY;
  final double accelZ;
  final double accelMag;
  final List<double> magHistory;

  TelemetryData({
    required this.heading,
    required this.accelX,
    required this.accelY,
    required this.accelZ,
    required this.accelMag,
    required this.magHistory,
  });
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  final DataService _dataService = DataService();
  final PDRService _pdrService = PDRService();
  final RoutingService _routingService = RoutingService();

  double _currentZoom = 16.8;
  late final ValueNotifier<TelemetryData> _telemetryNotifier;

  List<Building> _buildings = [];
  Building? _selectedBuilding;
  bool _isNavigating = false;
  bool _staircaseCompleted = false;
  int? _stepsAtStairsZoneEnter;
  int _stepCount = 0;
  List<LatLng> _pdrTrail = [];

  // Dijkstra route path coordinates and turn-by-turn instructions
  List<LatLng> _routingPath = [];
  List<String> _routeInstructions = [];
  int _currentInstructionIndex = 0;

  // Category filter state
  final List<String> _categories = ['All', 'Departments', 'Workshops', 'Hostels', 'Cafes/ATMs', 'Rooms/Labs'];
  String _selectedCategory = 'All';

  LatLng? _currentPosition;
  StreamSubscription<Position>? _gpsSubscription;
  bool _isLoading = true;
  String? _loadError;

  // Onboarding Carousel state
  bool _showOnboarding = false;
  final PageController _onboardingPageController = PageController();
  int _onboardingPageIndex = 0;

  // Pulsing animation for selected markers
  late AnimationController _pulseController;

  // Map Type ('dark', 'satellite', 'light', 'ambient')
  String _mapType = 'ambient';
  // App Theme Mode ('dark', 'light', 'ambient')
  String _appThemeMode = 'ambient';
  bool _showLayerSelector = false;

  // Telemetry dashboard states
  bool _showSensorDashboard = false;
  double _telemetryHeading = 0.0;
  double _compassOffset = 0.0;
  final List<double> _magHistory = List.filled(15, 0.0);

  // GEC Thrissur Center
  final LatLng _campusCenter = const LatLng(10.555761, 76.224317);

  // Dynamic color getters for Theme System
  Color get _bgOverlayColor {
    if (_appThemeMode == 'light') return Colors.white.withValues(alpha: 0.85);
    if (_appThemeMode == 'ambient') return const Color(0xFF0F1E36).withValues(alpha: 0.8); // Tinted blue-violet glass
    return const Color(0xFF0F172A).withValues(alpha: 0.8); // Dark slate glass
  }

  Color get _cardBgColor {
    if (_appThemeMode == 'light') return Colors.white;
    if (_appThemeMode == 'ambient') return const Color(0xFF1E294B); // Tinted navy card
    return const Color(0xFF1E293B); // Dark slate card
  }

  Color get _scaffoldBgColor {
    if (_appThemeMode == 'light') return const Color(0xFFF1F5F9);
    if (_appThemeMode == 'ambient') return const Color(0xFF0B0F19);
    return const Color(0xFF0F172A);
  }

  Color get _textColor {
    if (_appThemeMode == 'light') return const Color(0xFF0F172A);
    return Colors.white;
  }

  Color get _subTextColor {
    if (_appThemeMode == 'light') return const Color(0xFF475569);
    return Colors.white.withValues(alpha: 0.60);
  }

  Color get _borderColor {
    if (_appThemeMode == 'light') return Colors.black.withValues(alpha: 0.08);
    return Colors.white.withValues(alpha: 0.12);
  }

  @override
  void initState() {
    super.initState();
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _telemetryNotifier = ValueNotifier<TelemetryData>(
      TelemetryData(
        heading: 0.0,
        accelX: 0.0,
        accelY: 0.0,
        accelZ: 0.0,
        accelMag: 0.0,
        magHistory: List.filled(15, 0.0),
      ),
    );

    _initData();

    _pdrService.onPositionUpdated = (LatLng newPosition) {
      if (!mounted) return;
      setState(() {
        _currentPosition = newPosition;
        _pdrTrail.add(newPosition);
      });
      _mapController.move(newPosition, _mapController.camera.zoom);
    };

    _pdrService.onStepDetected = (int count) {
      if (!mounted) return;
      setState(() {
        _stepCount = count;
      });
    };

    _pdrService.onRawCompassUpdated = (double heading) {
      if (!mounted) return;
      final current = _telemetryNotifier.value;
      _telemetryHeading = (heading + _compassOffset + 360) % 360;
      _telemetryNotifier.value = TelemetryData(
        heading: _telemetryHeading,
        accelX: current.accelX,
        accelY: current.accelY,
        accelZ: current.accelZ,
        accelMag: current.accelMag,
        magHistory: current.magHistory,
      );
    };

    _pdrService.onRawAccelUpdated = (double x, double y, double z, double magnitude) {
      if (!mounted) return;
      
      _magHistory.removeAt(0);
      _magHistory.add(magnitude);

      _telemetryNotifier.value = TelemetryData(
        heading: _telemetryHeading,
        accelX: x,
        accelY: y,
        accelZ: z,
        accelMag: magnitude,
        magHistory: List<double>.from(_magHistory),
      );
    };
  }

  @override
  void dispose() {
    _gpsSubscription?.cancel();
    _pulseController.dispose();
    _pdrService.stopPDR();
    _onboardingPageController.dispose();
    _telemetryNotifier.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    try {
      final buildings = await _dataService.loadBuildings();
      await _checkOnboarding();

      // Try to get user location
      LatLng? userPos;
      try {
        bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (serviceEnabled) {
          LocationPermission permission = await Geolocator.checkPermission();
          if (permission == LocationPermission.denied) {
            permission = await Geolocator.requestPermission();
          }
          if (permission == LocationPermission.always ||
              permission == LocationPermission.whileInUse) {
            final pos = await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.high,
                timeLimit: Duration(seconds: 8),
              ),
            );
            userPos = LatLng(pos.latitude, pos.longitude);
          }
        }
      } catch (e) {
        debugPrint("Location error (non-fatal): $e");
        userPos = _campusCenter;
      }

      if (!mounted) return;
      setState(() {
        _buildings = buildings;
        _currentPosition = userPos;
        _isLoading = false;
      });
      if (userPos != null) {
        _pdrService.startPDR(userPos);
      }
      _startGPSListening();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _startGPSListening() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse) {
        _gpsSubscription?.cancel();
        _gpsSubscription = Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 0, // update as frequently as possible for 3Hz fusion
          ),
        ).listen((Position position) {
          if (!mounted) return;
          final newPos = LatLng(position.latitude, position.longitude);
          
          if (!_pdrService.isActive) {
            _pdrService.startPDR(newPos);
          }
          
          _pdrService.updateGPSPosition(
            newPos,
            position.accuracy,
            position.speed,
            position.heading,
          );
        }, onError: (e) {
          debugPrint("GPS stream error: $e");
        });
      }
    } catch (e) {
      debugPrint("Error starting GPS listening: $e");
    }
  }

  Future<void> _checkOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeen = prefs.getBool('seen_onboarding') ?? false;
    if (!hasSeen) {
      setState(() {
        _showOnboarding = true;
      });
    }
  }

  Future<void> _dismissOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('seen_onboarding', true);
    setState(() {
      _showOnboarding = false;
    });
  }

  /// Calculate distance in meters between two LatLng points (Haversine).
  double _distanceMeters(LatLng a, LatLng b) {
    return _routingService.distance(a, b);
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return "${meters.toStringAsFixed(0)} m";
    return "${(meters / 1000).toStringAsFixed(1)} km";
  }

  void _selectBuilding(Building building) {
    setState(() {
      _selectedBuilding = building;
      if (_isNavigating) {
        _isNavigating = false;
        _staircaseCompleted = false;
        _stepsAtStairsZoneEnter = null;
        _pdrTrail.clear();
        _routingPath.clear();
        _routeInstructions.clear();
      }
      FocusScope.of(context).unfocus();
    });

    _mapController.move(LatLng(building.lat, building.lng), 18.5);
    _showBuildingDetails(building);
  }

  Future<void> _startNavigation() async {
    if (_selectedBuilding == null) return;
    
    final startPos = _currentPosition ?? _campusCenter;
    final endPos = LatLng(_selectedBuilding!.lat, _selectedBuilding!.lng);

    // Show a loading SnackBar
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            SizedBox(width: 16),
            Text('Calculating route along campus paths...'),
          ],
        ),
        duration: Duration(days: 1), // keeps it open until manually hidden/replaced
        backgroundColor: Color(0xFF3B82F6),
      ),
    );

    try {
      // Get OSRM path asynchronously
      final path = await _routingService.getFullRoute(startPos, endPos);
      final instructions = _routingService.getRouteInstructions(path);

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      _pdrService.startPDR(startPos);
      setState(() {
        _isNavigating = true;
        _staircaseCompleted = false;
        _stepsAtStairsZoneEnter = null;
        _stepCount = 0;
        _pdrTrail = [startPos];
        _routingPath = path;
        _routeInstructions = instructions;
        _currentInstructionIndex = 0;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Navigation started along campus walkways!'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to calculate route: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _startTelemetryListening() {
    _pdrService.startTelemetryOnly();
  }

  void _stopTelemetryListening() {
    _pdrService.stopTelemetryOnly();
  }

  void _stopNavigation() {
    setState(() {
      _isNavigating = false;
      _staircaseCompleted = false;
      _stepsAtStairsZoneEnter = null;
      _pdrTrail.clear();
      _routingPath.clear();
      _routeInstructions.clear();
      _currentInstructionIndex = 0;
    });
  }

  Future<void> _downloadApk() async {
    try {
      final base = Uri.base;
      final downloadUrl = Uri(
        scheme: base.scheme,
        host: base.host,
        port: base.port,
        path: '/app-release.apk',
      );
      final success = await launchUrl(downloadUrl, mode: LaunchMode.externalApplication);
      if (!success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not trigger APK download. Please try opening the link directly.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error downloading APK: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _downloadIpa() async {
    try {
      final base = Uri.base;
      final downloadUrl = Uri(
        scheme: base.scheme,
        host: base.host,
        port: base.port,
        path: '/app-release.ipa',
      );
      final success = await launchUrl(downloadUrl, mode: LaunchMode.externalApplication);
      if (!success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not trigger IPA download. Please make sure the file is hosted on the server.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error downloading IPA: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showIosInstructionsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardBgColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: _borderColor)),
        title: Row(
          children: [
            Icon(Icons.apple, color: _textColor),
            const SizedBox(width: 10),
            Text("Install on iOS", style: TextStyle(color: _textColor, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "To run GECT Compass as a web app on iOS Safari:",
              style: TextStyle(color: _textColor, fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildIosStep("1", "Open this website in your Safari browser."),
            const SizedBox(height: 12),
            _buildIosStep("2", "Tap the Share button at the bottom of Safari."),
            const SizedBox(height: 12),
            _buildIosStep("3", "Scroll down and select 'Add to Home Screen'."),
            const SizedBox(height: 20),
            Text(
              "Alternative option:",
              style: TextStyle(color: _textColor, fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: () {
                Navigator.pop(context);
                _downloadIpa();
              },
              child: Row(
                children: [
                  const Icon(Icons.download, color: Color(0xFF3B82F6), size: 18),
                  const SizedBox(width: 8),
                  Text("Download iOS .ipa file directly", style: TextStyle(color: const Color(0xFF3B82F6), fontSize: 13, decoration: TextDecoration.underline)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              "Note: Sideloading raw .ipa files on iOS requires AltStore, Developer mode, or enterprise deployment. PWAs are recommended.",
              style: TextStyle(color: _textColor.withValues(alpha: 0.5), fontSize: 10, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Got It", style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildIosStep(String number, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 10,
          backgroundColor: const Color(0xFF10B981),
          child: Text(number, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: _textColor.withValues(alpha: 0.8), fontSize: 13),
          ),
        ),
      ],
    );
  }

  void _showDownloadOptionsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardBgColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: _borderColor)),
        title: Row(
          children: [
            Icon(Icons.download_for_offline, color: const Color(0xFF10B981)),
            const SizedBox(width: 10),
            Text("Download GECT Compass", style: TextStyle(color: _textColor, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Choose your platform to install the mobile application:",
              style: TextStyle(color: _textColor.withValues(alpha: 0.8), fontSize: 14),
            ),
            const SizedBox(height: 20),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.15), shape: BoxShape.circle),
                child: const Icon(Icons.android, color: Colors.green),
              ),
              title: Text("Android App (.apk)", style: TextStyle(color: _textColor, fontWeight: FontWeight.bold)),
              subtitle: Text("Direct download & install on Android devices", style: TextStyle(color: _textColor.withValues(alpha: 0.5), fontSize: 11)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(context);
                _downloadApk();
              },
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.15), shape: BoxShape.circle),
                child: const Icon(Icons.phone_iphone, color: Colors.blue),
              ),
              title: Text("iOS App (Safari PWA)", style: TextStyle(color: _textColor, fontWeight: FontWeight.bold)),
              subtitle: Text("Install directly without App Store using Safari", style: TextStyle(color: _textColor.withValues(alpha: 0.5), fontSize: 11)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(context);
                _showIosInstructionsDialog();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel", style: TextStyle(color: _textColor.withValues(alpha: 0.6))),
          ),
        ],
      ),
    );
  }





  // Filter buildings on the map based on the active category chip
  List<Building> _getFilteredBuildings() {
    final showRooms = _selectedCategory == 'Rooms/Labs' || (_selectedCategory == 'All' && _currentZoom >= 17.5);

    return _buildings.where((b) {
      final amenity = b.tags['amenity'] as String?;
      final buildingType = b.tags['building'] as String?;
      final tourism = b.tags['tourism'] as String?;
      final isRoom = b.tags['room'] == 'yes';

      if (isRoom && !showRooms) {
        return false;
      }

      if (_selectedCategory == 'All') {
        return true;
      }

      switch (_selectedCategory) {
        case 'Departments':
          return buildingType == 'college' && !isRoom;
        case 'Workshops':
          return b.name.toLowerCase().contains('workshop');
        case 'Hostels':
          return tourism == 'hostel' || b.name.toLowerCase().contains('hostel');
        case 'Cafes/ATMs':
          return ['restaurant', 'cafe', 'food_court', 'atm', 'bank'].contains(amenity);
        case 'Rooms/Labs':
          return isRoom;
        default:
          return true;
      }
    }).toList();
  }

  String _getTileUrl() {
    switch (_mapType) {
      case 'satellite':
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
      case 'light':
        return 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png';
      case 'ambient':
        return 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png';
      case 'dark':
      default:
        return 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';
    }
  }

  void _showBuildingDetails(Building building) {
    final double? dist = _currentPosition != null
        ? _distanceMeters(_currentPosition!, LatLng(building.lat, building.lng))
        : null;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              color: _cardBgColor.withValues(alpha: 0.85),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(color: _borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: _appThemeMode == 'light' ? 0.15 : 0.6),
                  blurRadius: 25,
                  spreadRadius: 8,
                )
              ],
            ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 46,
                height: 5,
                decoration: BoxDecoration(
                  color: _textColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (building.photoBase64 != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.memory(
                  base64Decode(building.photoBase64!),
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 18),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    building.name,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: _textColor,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                if (building.tags.containsKey('custom'))
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
                    ),
                    child: const Text(
                      "Community",
                      style: TextStyle(color: Colors.blueAccent, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.location_on, color: Color(0xFF3B82F6), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "${building.lat.toStringAsFixed(6)}, ${building.lng.toStringAsFixed(6)}",
                    style: TextStyle(color: _subTextColor, fontSize: 13),
                  ),
                ),
              ],
            ),
            if (dist != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.directions_walk, color: Color(0xFF10B981), size: 18),
                  const SizedBox(width: 8),
                  Text(
                    _formatDistance(dist),
                    style: const TextStyle(
                      color: Color(0xFF10B981),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(" away along paths", style: TextStyle(color: _subTextColor)),
                ],
              ),
            ],
            if (building.tags.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: building.tags.entries
                    .where((e) => ['amenity', 'building', 'tourism', 'cuisine', 'floor', 'ref'].contains(e.key))
                    .map((e) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: _scaffoldBgColor.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _borderColor),
                          ),
                          child: Text(
                            "${e.key}: ${e.value}",
                            style: TextStyle(fontSize: 11, color: _textColor.withValues(alpha: 0.8)),
                          ),
                        ))
                    .toList(),
              ),
            ],
            
            // Render Contact Options (Call / WhatsApp) if phone exists
            () {
              final String? rawPhone = (building.tags['phone'] ?? building.tags['contact:phone']) as String?;
              final List<String> phoneNumbers = rawPhone != null 
                  ? rawPhone.split(';').map((p) => p.trim()).where((p) => p.isNotEmpty).toList()
                  : [];

              if (phoneNumbers.isEmpty) return const SizedBox.shrink();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 18),
                  Text(
                    "CONTACT OPTIONS",
                    style: TextStyle(
                      color: _textColor.withValues(alpha: 0.55),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...phoneNumbers.map((phone) {
                    final cleanPhone = phone.replaceAll(RegExp(r'[^+\d]'), '');
                    final standardPhone = (cleanPhone.length == 10 && !cleanPhone.startsWith('+'))
                        ? '+91$cleanPhone'
                        : cleanPhone;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: _scaffoldBgColor.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _borderColor),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    phone,
                                    style: TextStyle(
                                      color: _textColor,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    "Tap icons to Call or Chat",
                                    style: TextStyle(
                                      color: _subTextColor,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () async {
                                final url = Uri.parse("tel:$standardPhone");
                                try {
                                  await launchUrl(url);
                                } catch (e) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text("Could not call $phone")),
                                  );
                                }
                              },
                              icon: const Icon(Icons.phone, size: 20),
                              style: IconButton.styleFrom(
                                foregroundColor: const Color(0xFF3B82F6),
                                backgroundColor: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed: () async {
                                final text = "Hello! I am using the GECT Compass app and wanted to query about ${building.name}.";
                                final url = Uri.parse("https://wa.me/${standardPhone.replaceAll('+', '').replaceAll(' ', '')}?text=${Uri.encodeComponent(text)}");
                                try {
                                  final success = await launchUrl(url, mode: LaunchMode.externalApplication);
                                  if (!success) throw Exception();
                                } catch (e) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text("Could not open WhatsApp for $phone")),
                                  );
                                }
                              },
                              icon: const Icon(Icons.chat, size: 20),
                              style: IconButton.styleFrom(
                                foregroundColor: const Color(0xFF10B981),
                                backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              );
            }(),
            
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _startNavigation();
                },
                icon: const Icon(Icons.directions_walk, color: Colors.white),
                label: const Text(
                  "Navigate Along Paths",
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 5,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _showEditPlaceModal(building);
                },
                icon: Icon(Icons.edit, color: _textColor),
                label: Text(
                  "Edit Place Info / Photo",
                  style: TextStyle(color: _textColor, fontSize: 15, fontWeight: FontWeight.bold),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  side: BorderSide(color: _borderColor),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    ),
  ),
);
  }

  @override
  Widget build(BuildContext context) {
    final filteredBuildings = _getFilteredBuildings();

    return Theme(
      data: ThemeData(
        brightness: _appThemeMode == 'light' ? Brightness.light : Brightness.dark,
        primaryColor: _scaffoldBgColor,
        scaffoldBackgroundColor: _scaffoldBgColor,
        cardColor: _cardBgColor,
        colorScheme: ColorScheme(
          brightness: _appThemeMode == 'light' ? Brightness.light : Brightness.dark,
          primary: const Color(0xFF3B82F6),
          onPrimary: Colors.white,
          secondary: const Color(0xFF10B981),
          onSecondary: Colors.white,
          error: Colors.redAccent,
          onError: Colors.white,
          surface: _cardBgColor,
          onSurface: _textColor,
        ),
        useMaterial3: true,
      ),
      child: Builder(
        builder: (context) {
          return Scaffold(
            backgroundColor: _scaffoldBgColor,
            body: Stack(
              children: [
                // Loading / Error / Map
                if (_isLoading)
                  const Center(child: CircularProgressIndicator())
                else if (_loadError != null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
                          const SizedBox(height: 16),
                          Text("Failed to load: $_loadError",
                              textAlign: TextAlign.center,
                              style: TextStyle(color: _textColor.withValues(alpha: 0.7))),
                          const SizedBox(height: 16),
                          ElevatedButton(onPressed: _initData, child: const Text("Retry")),
                        ],
                      ),
                    ),
                  )
                else
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _campusCenter,
                      initialZoom: 16.8,
                      maxZoom: 22.0,
                      onPositionChanged: (pos, hasGesture) {
                        if (hasGesture) FocusScope.of(context).unfocus();
                        final newZoom = pos.zoom;
                        final wasZoomedIn = _currentZoom >= 17.5;
                        final isZoomedIn = newZoom >= 17.5;
                        if (wasZoomedIn != isZoomedIn) {
                          setState(() {
                            _currentZoom = newZoom;
                          });
                        } else {
                          _currentZoom = newZoom;
                        }
                      },
                      onTap: (tapPosition, point) {},
                    ),
                    children: [
                      // Configurable Map Tile Layer
                      TileLayer(
                        urlTemplate: _getTileUrl(),
                        subdomains: const ['a', 'b', 'c', 'd'],
                        maxNativeZoom: _mapType == 'satellite' ? 19 : 18,
                        userAgentPackageName: 'com.example.gec_compass_app',
                      ),
                      if (_mapType == 'satellite') ...[
                        TileLayer(
                          urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Transportation/MapServer/tile/{z}/{y}/{x}',
                          subdomains: const ['a', 'b', 'c', 'd'],
                          maxNativeZoom: 19,
                        ),
                        TileLayer(
                          urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}',
                          subdomains: const ['a', 'b', 'c', 'd'],
                          maxNativeZoom: 19,
                        ),
                      ],
                      
                      // Polyline layer for Dijkstra road route (under custom markers)
                      if (_isNavigating && _routingPath.length >= 2)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: _routingPath,
                              color: const Color(0xFF3B82F6),
                              strokeWidth: 6.0,
                              strokeCap: StrokeCap.round,
                              strokeJoin: StrokeJoin.round,
                            ),
                          ],
                        ),
                      
                      // Polyline layer for actual walked/PDR trail
                      if (_isNavigating && _pdrTrail.length >= 2)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: _pdrTrail,
                              color: const Color(0xFF10B981),
                              strokeWidth: 3.5,
                              strokeCap: StrokeCap.round,
                              strokeJoin: StrokeJoin.round,
                            ),
                          ],
                        ),
          
                      // Building markers
                      MarkerLayer(
                        markers: filteredBuildings.map((b) => Marker(
                          point: LatLng(b.lat, b.lng),
                          width: 48,
                          height: 48,
                          child: GestureDetector(
                            onTap: () => _selectBuilding(b),
                            child: _buildMarkerIcon(b),
                          ),
                        )).toList(),
                      ),
          
                      // User position marker
                      if (_currentPosition != null)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _currentPosition!,
                              width: 55,
                              height: 55,
                              alignment: Alignment.bottomCenter,
                              child: _buildUserLocationMarker(),
                            )
                          ],
                        ),
                    ],
                  ),
          
                // Search Bar & Horizontal Category Filters (Top)
                if (!_isNavigating)
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 12,
                    left: 16,
                    right: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Glassmorphism Search Bar
                        ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                            child: Container(
                              decoration: BoxDecoration(
                                color: _bgOverlayColor,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: _borderColor),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: _appThemeMode == 'light' ? 0.05 : 0.25),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  )
                                ],
                              ),
                              child: Autocomplete<Building>(
                                optionsBuilder: (TextEditingValue textEditingValue) {
                                  if (textEditingValue.text.isEmpty) {
                                    return const Iterable<Building>.empty();
                                  }
                                  return _buildings.where((Building option) {
                                    return option.name
                                        .toLowerCase()
                                        .contains(textEditingValue.text.toLowerCase());
                                  });
                                },
                                displayStringForOption: (Building option) => option.name,
                                onSelected: (Building selection) {
                                  _selectBuilding(selection);
                                },
                                fieldViewBuilder: (BuildContext context,
                                    TextEditingController textEditingController,
                                    FocusNode focusNode,
                                    VoidCallback onFieldSubmitted) {
                                  return TextField(
                                    controller: textEditingController,
                                    focusNode: focusNode,
                                    style: TextStyle(color: _textColor, fontSize: 15),
                                    decoration: InputDecoration(
                                      hintText: 'Search departments, labs, cafes...',
                                      hintStyle: TextStyle(color: _textColor.withValues(alpha: 0.5)),
                                      prefixIcon: Icon(Icons.search, color: _textColor.withValues(alpha: 0.5)),
                                      suffixIcon: textEditingController.text.isNotEmpty 
                                          ? IconButton(
                                              icon: Icon(Icons.clear, color: _textColor.withValues(alpha: 0.5), size: 18),
                                              onPressed: () {
                                                textEditingController.clear();
                                                focusNode.unfocus();
                                              },
                                            )
                                          : null,
                                      border: InputBorder.none,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                    ),
                                  );
                                },
                                optionsViewBuilder: (BuildContext context,
                                    AutocompleteOnSelected<Building> onSelected,
                                    Iterable<Building> options) {
                                  return Align(
                                    alignment: Alignment.topLeft,
                                    child: Material(
                                      color: Colors.transparent,
                                      child: Container(
                                        width: MediaQuery.of(context).size.width - 32,
                                        margin: const EdgeInsets.only(top: 8),
                                        constraints: const BoxConstraints(maxHeight: 250),
                                        decoration: BoxDecoration(
                                          color: _cardBgColor,
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(color: _borderColor),
                                          boxShadow: [
                                            BoxShadow(
                                                color: Colors.black.withValues(alpha: 0.3),
                                                blurRadius: 15,
                                                offset: const Offset(0, 5))
                                          ],
                                        ),
                                        child: ListView.separated(
                                          padding: EdgeInsets.zero,
                                          shrinkWrap: true,
                                          itemCount: options.length,
                                          separatorBuilder: (c, i) => Divider(color: _borderColor, height: 1),
                                          itemBuilder: (BuildContext context, int index) {
                                            final Building option = options.elementAt(index);
                                            return ListTile(
                                              title: Text(option.name,
                                                  style: TextStyle(color: _textColor, fontSize: 14)),
                                              leading: Icon(_getMarkerIcon(option),
                                                  color: _getMarkerColor(option), size: 20),
                                              onTap: () {
                                                onSelected(option);
                                              },
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        
                        // Category filter chips
                        SizedBox(
                          height: 40,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _categories.length,
                            itemBuilder: (context, index) {
                              final cat = _categories[index];
                              final isSelected = _selectedCategory == cat;
                              return Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(20),
                                  child: BackdropFilter(
                                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                                    child: ChoiceChip(
                                      label: Text(cat),
                                      selected: isSelected,
                                      onSelected: (selected) {
                                        if (selected) {
                                          setState(() {
                                            _selectedCategory = cat;
                                          });
                                        }
                                      },
                                      labelStyle: TextStyle(
                                        color: isSelected ? Colors.white : _textColor.withValues(alpha: 0.8),
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                        fontSize: 13,
                                      ),
                                      selectedColor: const Color(0xFF3B82F6).withValues(alpha: 0.85),
                                      backgroundColor: _cardBgColor.withValues(alpha: 0.5),
                                      side: BorderSide(color: isSelected ? Colors.transparent : _borderColor),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
          
                // Floating Buttons on the right (responsive positioning)
                Positioned(
                  bottom: _isNavigating ? 140 : 32,
                  right: 16,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Telemetry Dashboard Toggle (Hidden on Web)
                      if (!kIsWeb) ...[
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                              child: FloatingActionButton(
                                heroTag: 'sensors_btn',
                                elevation: 0,
                                highlightElevation: 0,
                                backgroundColor: _showSensorDashboard 
                                    ? const Color(0xFF10B981).withValues(alpha: 0.85) 
                                    : _cardBgColor.withValues(alpha: 0.7),
                                foregroundColor: _showSensorDashboard ? Colors.white : const Color(0xFF3B82F6),
                                onPressed: () {
                                  setState(() {
                                    _showSensorDashboard = !_showSensorDashboard;
                                    _showLayerSelector = false;
                                    if (_showSensorDashboard) {
                                      _startTelemetryListening();
                                    } else {
                                      if (!_isNavigating) {
                                        _stopTelemetryListening();
                                      }
                                    }
                                  });
                                },
                                child: Icon(_showSensorDashboard ? Icons.sensors : Icons.sensors_off),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      // Theme/Layer Switcher Button (Visible during navigation!)
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                            child: FloatingActionButton(
                              heroTag: 'layer_btn',
                              elevation: 0,
                              highlightElevation: 0,
                              backgroundColor: _cardBgColor.withValues(alpha: 0.7),
                              foregroundColor: const Color(0xFF3B82F6),
                              onPressed: () {
                                setState(() {
                                  _showLayerSelector = !_showLayerSelector;
                                });
                              },
                              child: const Icon(Icons.layers),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (!_isNavigating) ...[
                        // Add Place Button
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                              child: FloatingActionButton(
                                heroTag: 'add_place_btn',
                                elevation: 0,
                                highlightElevation: 0,
                                backgroundColor: const Color(0xFF3B82F6).withValues(alpha: 0.85),
                                foregroundColor: Colors.white,
                                onPressed: _showAddPlaceModal,
                                child: const Icon(Icons.add_location_alt),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      if (kIsWeb && !_isNavigating) ...[
                        // Download App Button (Hidden during navigation!)
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                              child: FloatingActionButton(
                                heroTag: 'download_app_btn',
                                elevation: 0,
                                highlightElevation: 0,
                                backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.85),
                                foregroundColor: Colors.white,
                                tooltip: 'Download Mobile App',
                                onPressed: _showDownloadOptionsDialog,
                                child: const Icon(Icons.install_mobile),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      // Recenter Button
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                            child: FloatingActionButton(
                              heroTag: 'recenter_btn',
                              elevation: 0,
                              highlightElevation: 0,
                              backgroundColor: _cardBgColor.withValues(alpha: 0.7),
                              foregroundColor: const Color(0xFF3B82F6),
                              onPressed: () async {
                                if (kIsWeb) {
                                  await _pdrService.startPDR(_currentPosition ?? _campusCenter);
                                }
                                if (_currentPosition != null) {
                                  _mapController.move(_currentPosition!, 18.5);
                                } else {
                                  _mapController.move(_campusCenter, 16.5);
                                }
                              },
                              child: const Icon(Icons.my_location),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
          
                // Theme & Layer Selector Panel
                if (_showLayerSelector && !_isNavigating)
                  Positioned(
                    bottom: 32 + 190,
                    right: 16,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: _bgOverlayColor,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: _borderColor),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 15,
                              )
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Theme & Map Layer",
                                style: TextStyle(
                                  color: _textColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  _buildLayerOption('dark', Icons.dark_mode, 'Dark'),
                                  const SizedBox(width: 12),
                                  _buildLayerOption('light', Icons.light_mode, 'Light'),
                                  const SizedBox(width: 12),
                                  _buildLayerOption('ambient', Icons.palette, 'Ambient'),
                                  const SizedBox(width: 12),
                                  _buildLayerOption('satellite', Icons.satellite_alt, 'Satellite'),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                // Feedback Button
                if (!_isNavigating)
                  Positioned(
                    bottom: 32,
                    left: 16,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(30),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                          child: FloatingActionButton.extended(
                            heroTag: 'feedback_btn',
                            elevation: 0,
                            highlightElevation: 0,
                            backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.85),
                            foregroundColor: Colors.white,
                            icon: const Icon(Icons.rate_review),
                            label: const Text('Feedback',
                                style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                            onPressed: _showFeedbackModal,
                          ),
                        ),
                      ),
                    ),
                  ),
          

          
                // Telemetry Sensor Dashboard Overlay (Hidden on Web)
                if (_showSensorDashboard && !kIsWeb)
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 80,
                    left: 16,
                    child: ValueListenableBuilder<TelemetryData>(
                      valueListenable: _telemetryNotifier,
                      builder: (context, telemetry, child) {
                        return _buildSensorDashboardWidget(context, telemetry);
                      },
                    ),
                  ),

                // Navigation UI Overlay
                if (_isNavigating) _buildNavigationOverlay(),
          
                // Welcome Onboarding Overlay
                if (_showOnboarding) _buildOnboardingOverlay(),
              ],
            ),
          );
        }
      ),
    );
  }

  Widget _buildLayerOption(String type, IconData icon, String label) {
    final isSelected = _mapType == type;
    final color = isSelected ? const Color(0xFF3B82F6) : _cardBgColor.withValues(alpha: 0.6);
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _mapType = type;
          if (type != 'satellite') {
            _appThemeMode = type;
          }
          _showLayerSelector = false;
        });
      },
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? const Color(0xFF3B82F6) : _borderColor,
                width: 1.5,
              ),
            ),
            child: Icon(
              icon,
              color: isSelected ? Colors.white : _textColor.withValues(alpha: 0.8),
              size: 22,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: isSelected ? const Color(0xFF3B82F6) : _textColor.withValues(alpha: 0.8),
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  // Draw user position with smooth pulsing outer glow
  Widget _buildUserLocationMarker() {
    return ValueListenableBuilder<TelemetryData>(
      valueListenable: _telemetryNotifier,
      builder: (context, telemetry, child) {
        final headingRad = telemetry.heading * (pi / 180.0);
        return AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            return Stack(
              alignment: Alignment.center,
              children: [
                // Directional Beam (pointing forward)
                Transform.rotate(
                  angle: headingRad,
                  child: CustomPaint(
                    size: const Size(65, 65),
                    painter: DirectionBeamPainter(),
                  ),
                ),
                // Pulsing background circle
                Container(
                  width: 26 + _pulseController.value * 16,
                  height: 26 + _pulseController.value * 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF3B82F6).withValues(alpha: 0.2 * (1.0 - _pulseController.value)),
                  ),
                ),
                // Standard location tear drop (pin)
                const Icon(
                  Icons.location_on,
                  color: Color(0xFF3B82F6),
                  size: 45,
                ),
                // White background circle for the inner arrow
                Transform.translate(
                  offset: const Offset(0, -5), // Shift slightly up to align with the hole of location_on
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                  ),
                ),
                // Heading navigation arrow (person/arrow like in gmap)
                Transform.translate(
                  offset: const Offset(0, -5), // Shift slightly up to align with the hole of location_on
                  child: Transform.rotate(
                    angle: headingRad,
                    child: const Icon(
                      Icons.navigation,
                      color: Color(0xFF3B82F6),
                      size: 11,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Draw customized pins for buildings (reduced sizes)
  Widget _buildMarkerIcon(Building b) {
    final isSelected = _selectedBuilding?.id == b.id;
    final color = isSelected ? Colors.greenAccent : _getMarkerColor(b);
    final icon = _getMarkerIcon(b);

    if (!isSelected) {
      return Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: _scaffoldBgColor.withValues(alpha: 0.9),
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 3,
              spreadRadius: 0.5,
            )
          ],
        ),
        child: Center(
          child: Icon(
            icon,
            color: color,
            size: 12,
          ),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 24 + _pulseController.value * 18,
              height: 24 + _pulseController.value * 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.4 * (1.0 - _pulseController.value)),
              ),
            ),
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: _scaffoldBgColor.withValues(alpha: 0.9),
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.3),
                    blurRadius: 6,
                    spreadRadius: 1.5,
                  )
                ],
              ),
              child: Center(
                child: Icon(
                  icon,
                  color: color,
                  size: 15,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildNavigationOverlay() {
    if (_selectedBuilding == null || _currentPosition == null) return const SizedBox.shrink();

    final dist = _distanceMeters(_currentPosition!, LatLng(_selectedBuilding!.lat, _selectedBuilding!.lng));
    final floorTag = _selectedBuilding!.tags['floor'];
    
    String primaryInstruction = "Head towards ${_selectedBuilding!.name}";
    String secondaryInstruction = "Follow the highlighted path on the map.";
    IconData turnIcon = Icons.straight;
    Color topBarColor = const Color(0xFF0F9D58); // Green for active nav

    if (_routeInstructions.isNotEmpty) {
      primaryInstruction = _routeInstructions[_currentInstructionIndex];
      if (_currentInstructionIndex < _routeInstructions.length - 1) {
        secondaryInstruction = "Next: ${_routeInstructions[_currentInstructionIndex + 1]}";
      } else {
        secondaryInstruction = "Arriving at ${_selectedBuilding!.name}";
      }
    }

    final bool showStairs = dist < 15.0 && floorTag != null && floorTag.toString().isNotEmpty && !_staircaseCompleted;

    int stepsWalkedInZone = 0;
    int targetSteps = 18;

    if (showStairs) {
      final int floorsToClimb = int.tryParse(floorTag.toString()) ?? 1;
      targetSteps = floorsToClimb > 0 ? floorsToClimb * 18 : 18;

      _stepsAtStairsZoneEnter ??= _stepCount;
      stepsWalkedInZone = _stepCount - _stepsAtStairsZoneEnter!;
      if (stepsWalkedInZone < 0) {
        _stepsAtStairsZoneEnter = _stepCount;
        stepsWalkedInZone = 0;
      }

      if (stepsWalkedInZone >= targetSteps) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_staircaseCompleted) {
            HapticFeedback.mediumImpact();
            setState(() {
              _staircaseCompleted = true;
            });
          }
        });
      }
    }

    if (showStairs) {
      primaryInstruction = "Take stairs to Floor $floorTag";
      secondaryInstruction = "Then proceed to ${_selectedBuilding!.name}";
      turnIcon = Icons.stairs;
      topBarColor = const Color(0xFF3B82F6); // Blue for indoor instructions
    } else if (dist < 5.0 || (dist < 15.0 && _staircaseCompleted)) {
      primaryInstruction = "You have arrived";
      secondaryInstruction = _selectedBuilding!.name;
      turnIcon = Icons.place;
      topBarColor = const Color(0xFF10B981); // Emerald green for arrival
    }

    // Average walking speed ~1.3 m/s
    final double timeSeconds = dist / 1.3;
    int minutes = (timeSeconds / 60).ceil();
    if (minutes < 1) minutes = 1;

    return Stack(
      children: [
        // Top Navigation Instruction Card (Glassmorphic)
        Positioned(
          top: MediaQuery.of(context).padding.top + 16,
          left: 16,
          right: 16,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                decoration: BoxDecoration(
                  color: topBarColor.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                  boxShadow: [
                    BoxShadow(color: Colors.black45, blurRadius: 15, offset: const Offset(0, 5)),
                  ],
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  children: [
                    Icon(turnIcon, color: Colors.white, size: 36),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            primaryInstruction,
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            secondaryInstruction,
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13),
                          ),
                          if (showStairs) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                SizedBox(
                                  width: 80,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: (stepsWalkedInZone / targetSteps).clamp(0.0, 1.0),
                                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
                                      minHeight: 6,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  "Climbing: $stepsWalkedInZone / $targetSteps steps",
                                  style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (showStairs) ...[
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          setState(() {
                            _staircaseCompleted = true;
                          });
                        },
                        icon: const Icon(Icons.check_circle_outline, color: Colors.white, size: 16),
                        label: const Text(
                          "Done",
                          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.2),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
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
        
        // Bottom Navigation Status Bar
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            decoration: BoxDecoration(
              color: _scaffoldBgColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(color: _borderColor),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 25, offset: const Offset(0, -6)),
              ],
            ),
            padding: EdgeInsets.only(
              left: 24, 
              right: 24, 
              top: 24, 
              bottom: MediaQuery.of(context).padding.bottom + 24
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text("$minutes min", style: const TextStyle(color: Color(0xFF10B981), fontSize: 28, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 12),
                          Text(_formatDistance(dist), style: TextStyle(color: _textColor.withValues(alpha: 0.8), fontSize: 18)),
                        ],
                      ),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: _stopNavigation,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent.withValues(alpha: 0.85),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 28),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Render onboarding/instructional carousel
  Widget _buildOnboardingOverlay() {
    final slides = [
      if (kIsWeb)
        _buildOnboardingSlide(
          title: "Download Mobile App",
          desc: "For the absolute best experience on campus with native step-tracking, offline navigation, and real-time haptic feedback, download our Android App.",
          icon: Icons.install_mobile,
          iconColor: const Color(0xFF3DDC84),
          actionButton: ElevatedButton.icon(
            onPressed: _downloadApk,
            icon: const Icon(Icons.android, color: Colors.white),
            label: const Text("Download Android App", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3DDC84),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              elevation: 4,
            ),
          ),
        ),
      _buildOnboardingSlide(
        title: "Welcome to GECT Compass",
        desc: "Interactive navigation along campus walkways, department buildings, labs, workshops, and facilities at GEC Thrissur.",
        icon: Icons.explore,
        iconColor: const Color(0xFF3B82F6),
      ),
      _buildOnboardingSlide(
        title: "Dead Reckoning (PDR)",
        desc: "Using the accelerometer & compass of your phone, the app detects steps and heading to track your indoor walking paths without GPS.",
        icon: Icons.directions_walk,
        iconColor: const Color(0xFF10B981),
      ),
      _buildOnboardingSlide(
        title: "Global Updates",
        desc: "Add missing rooms, classes, or labs with photos and coordinates. Updates sync globally to a shared cloud database instantly.",
        icon: Icons.cloud_sync,
        iconColor: Colors.purpleAccent,
      )
    ];

    return Container(
      color: Colors.black87.withValues(alpha: 0.85),
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              width: MediaQuery.of(context).size.width * 0.88,
              height: 500,
              decoration: BoxDecoration(
                color: _cardBgColor,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: _borderColor),
              ),
              padding: const EdgeInsets.all(28),
              child: Column(
                children: [
                  Expanded(
                    child: PageView.builder(
                      controller: _onboardingPageController,
                      itemCount: slides.length,
                      onPageChanged: (index) {
                        setState(() {
                          _onboardingPageIndex = index;
                        });
                      },
                      itemBuilder: (context, index) => slides[index],
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Indicator Dots
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      slides.length,
                      (index) => Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: _onboardingPageIndex == index ? 20 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: _onboardingPageIndex == index ? const Color(0xFF3B82F6) : _textColor.withValues(alpha: 0.3),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  
                  // Bottom Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () {
                        if (_onboardingPageIndex < slides.length - 1) {
                          _onboardingPageController.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        } else {
                          _dismissOnboarding();
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B82F6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Text(
                        _onboardingPageIndex == slides.length - 1 ? "Get Started" : "Continue",
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOnboardingSlide({
    required String title,
    required String desc,
    required IconData icon,
    required Color iconColor,
    Widget? actionButton,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 80, color: iconColor),
        const SizedBox(height: 24),
        Text(
          title,
          style: TextStyle(color: _textColor, fontSize: 24, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          desc,
          style: TextStyle(color: _textColor.withValues(alpha: 0.7), fontSize: 14, height: 1.4),
          textAlign: TextAlign.center,
        ),
        if (actionButton != null) ...[
          const SizedBox(height: 18),
          actionButton,
        ],
      ],
    );
  }

  IconData _getMarkerIcon(Building b) {
    final amenity = b.tags['amenity'] as String?;
    final buildingType = b.tags['building'] as String?;
    final tourism = b.tags['tourism'] as String?;

    if (amenity == 'restaurant' || amenity == 'cafe' || amenity == 'food_court') {
      return Icons.restaurant;
    }
    if (amenity == 'atm' || amenity == 'bank') return Icons.account_balance;
    if (amenity == 'place_of_worship') return Icons.temple_hindu;
    if (amenity == 'pharmacy') return Icons.local_pharmacy;
    if (amenity == 'police') return Icons.local_police;
    if (amenity == 'post_office') return Icons.local_post_office;
    if (amenity == 'fire_station') return Icons.local_fire_department;
    if (amenity == 'events_venue' || amenity == 'community_centre') return Icons.event;
    if (tourism == 'hostel') return Icons.hotel;
    if (buildingType == 'college') return Icons.school;
    return Icons.location_on;
  }

  Color _getMarkerColor(Building b) {
    final amenity = b.tags['amenity'] as String?;
    final buildingType = b.tags['building'] as String?;
    final isRoom = b.tags['room'] == 'yes';

    if (amenity == 'restaurant' || amenity == 'cafe' || amenity == 'food_court') {
      return Colors.orangeAccent;
    }
    if (isRoom) return Colors.purpleAccent;
    if (buildingType == 'college') return const Color(0xFF3B82F6);
    if (amenity == 'atm' || amenity == 'bank') return Colors.amberAccent;
    return Colors.redAccent;
  }

  void _showFeedbackModal() {
    final feedbackController = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              decoration: BoxDecoration(
                color: _cardBgColor.withValues(alpha: 0.85),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(color: _borderColor),
              ),
              padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _textColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                "Feedback & Reports",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _textColor),
              ),
              const SizedBox(height: 8),
              Text(
                "Suggest a missing building, report an inaccurate path, or share feature requests.",
                style: TextStyle(color: _subTextColor),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: feedbackController,
                maxLines: 4,
                style: TextStyle(color: _textColor),
                decoration: InputDecoration(
                  hintText: "Enter your feedback or report here...",
                  hintStyle: TextStyle(color: _textColor.withValues(alpha: 0.38)),
                  filled: true,
                  fillColor: _scaffoldBgColor.withValues(alpha: 0.5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final text = feedbackController.text.trim();
                    if (text.isNotEmpty) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Redirecting to WhatsApp to send feedback...'),
                          backgroundColor: Color(0xFF3B82F6),
                        ),
                      );
                      
                      final url = Uri.parse("https://wa.me/918714743183?text=${Uri.encodeComponent("Compass Feedback: $text")}");
                      try {
                        final success = await launchUrl(url, mode: LaunchMode.externalApplication);
                        if (!success) throw Exception("Could not launch URL");
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Could not launch WhatsApp. Feedback copied to clipboard.'),
                            backgroundColor: Colors.amber,
                          ),
                        );
                        await Clipboard.setData(ClipboardData(text: text));
                      }
                    }
                  },
                  icon: const Icon(Icons.send, color: Colors.white),
                  label: const Text(
                    "Submit Feedback",
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    ),
  ),
);
  }

  void _showAddPlaceModal() {
    final nameController = TextEditingController();
    final floorController = TextEditingController();
    final roomController = TextEditingController();
    
    bool isClassroom = false;
    Building? selectedParent;
    LatLng? location;
    bool isFetchingLocation = false;
    String? photoBase64;
    final ImagePicker picker = ImagePicker();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  height: MediaQuery.of(context).size.height * 0.85,
                  decoration: BoxDecoration(
                    color: _cardBgColor.withValues(alpha: 0.85),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                    border: Border.all(color: _borderColor),
                  ),
                  padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: _textColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      "Add a Place",
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _textColor),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Contribute a missing classroom, laboratory, or office to the cloud database.",
                      style: TextStyle(color: _subTextColor, fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                    
                    // Choice of type
                    Row(
                      children: [
                        Text("Category:", style: TextStyle(color: _textColor, fontSize: 14)),
                        const SizedBox(width: 16),
                        ChoiceChip(
                          label: const Text("Building/Lab"),
                          selected: !isClassroom,
                          onSelected: (val) => setModalState(() { isClassroom = false; }),
                          selectedColor: const Color(0xFF3B82F6),
                          backgroundColor: _scaffoldBgColor.withValues(alpha: 0.5),
                          labelStyle: TextStyle(color: !isClassroom ? Colors.white : _textColor.withValues(alpha: 0.7), fontSize: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text("Room/Classroom"),
                          selected: isClassroom,
                          onSelected: (val) => setModalState(() { isClassroom = true; }),
                          selectedColor: const Color(0xFF3B82F6),
                          backgroundColor: _scaffoldBgColor.withValues(alpha: 0.5),
                          labelStyle: TextStyle(color: isClassroom ? Colors.white : _textColor.withValues(alpha: 0.7), fontSize: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Name Input
                    TextField(
                      controller: nameController,
                      style: TextStyle(color: _textColor),
                      decoration: InputDecoration(
                        labelText: "Place Name (e.g. Embedded Systems Lab)",
                        labelStyle: TextStyle(color: _textColor.withValues(alpha: 0.5), fontSize: 14),
                        filled: true,
                        fillColor: _scaffoldBgColor.withValues(alpha: 0.5),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Parent Building Dropdown (if room)
                    if (isClassroom) ...[
                      DropdownButtonFormField<Building>(
                        decoration: InputDecoration(
                          labelText: "Located In (Building)",
                          labelStyle: TextStyle(color: _textColor.withValues(alpha: 0.5), fontSize: 14),
                          filled: true,
                          fillColor: _scaffoldBgColor.withValues(alpha: 0.5),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                        ),
                        dropdownColor: _cardBgColor,
                        initialValue: selectedParent,
                        items: _buildings.where((b) => b.tags['building'] == 'college' || !b.tags.containsKey('room')).map((b) {
                          return DropdownMenuItem(value: b, child: Text(b.name, style: TextStyle(color: _textColor, fontSize: 14)));
                        }).toList(),
                        onChanged: (val) {
                          setModalState(() { selectedParent = val; });
                        },
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Floor & Room number inputs
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: floorController,
                            keyboardType: TextInputType.number,
                            style: TextStyle(color: _textColor),
                            decoration: InputDecoration(
                              labelText: "Floor (e.g., 0, 1, 2)",
                              labelStyle: TextStyle(color: _textColor.withValues(alpha: 0.5), fontSize: 13),
                              filled: true,
                              fillColor: _scaffoldBgColor.withValues(alpha: 0.5),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: roomController,
                            style: TextStyle(color: _textColor),
                            decoration: InputDecoration(
                              labelText: "Room ID / Number",
                              labelStyle: TextStyle(color: _textColor.withValues(alpha: 0.5), fontSize: 13),
                              filled: true,
                              fillColor: _scaffoldBgColor.withValues(alpha: 0.5),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Location Card
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: _scaffoldBgColor.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: _borderColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Geographical Coordinates", style: TextStyle(color: _textColor, fontWeight: FontWeight.bold, fontSize: 14)),
                          const SizedBox(height: 8),
                          if (location != null)
                            Row(
                              children: [
                                const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 16),
                                const SizedBox(width: 8),
                                Text(
                                  "Lat: ${location!.latitude.toStringAsFixed(6)}, Lng: ${location!.longitude.toStringAsFixed(6)}",
                                  style: const TextStyle(color: Color(0xFF10B981), fontSize: 13, fontWeight: FontWeight.bold),
                                ),
                              ],
                            )
                          else
                            Text("No coordinate assigned yet", style: TextStyle(color: _textColor.withValues(alpha: 0.4), fontSize: 13)),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: isFetchingLocation ? null : () async {
                                setModalState(() { isFetchingLocation = true; });
                                try {
                                  bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
                                  if (!serviceEnabled) throw Exception("Location services disabled.");
                                  
                                  LocationPermission permission = await Geolocator.checkPermission();
                                  if (permission == LocationPermission.denied) {
                                    permission = await Geolocator.requestPermission();
                                  }
                                  if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
                                    throw Exception("Location permission denied.");
                                  }
                                  
                                  final pos = await Geolocator.getCurrentPosition(
                                    locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 8)),
                                  );
                                  setModalState(() { location = LatLng(pos.latitude, pos.longitude); });
                                } catch (e) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent));
                                } finally {
                                  setModalState(() { isFetchingLocation = false; });
                                }
                              },
                              icon: isFetchingLocation 
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blueAccent)) 
                                : const Icon(Icons.gps_fixed, size: 18),
                              label: Text(isFetchingLocation ? "Acquiring satellites..." : "Use Current GPS Location"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _scaffoldBgColor,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Add Photo Buttons (Camera / Gallery)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Add Place Image / Capture:", style: TextStyle(color: _textColor.withValues(alpha: 0.8), fontSize: 13, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  try {
                                    final XFile? image = await picker.pickImage(
                                      source: ImageSource.camera,
                                      imageQuality: 40,
                                      maxWidth: 700,
                                    );
                                    if (image != null) {
                                      final bytes = await image.readAsBytes();
                                      setModalState(() {
                                        photoBase64 = base64Encode(bytes);
                                      });
                                    }
                                  } catch (e) {
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Camera error: $e'), backgroundColor: Colors.redAccent));
                                  }
                                },
                                icon: const Icon(Icons.camera_alt, size: 18),
                                label: Text(photoBase64 == null ? "Camera" : "Camera (OK)", style: const TextStyle(fontSize: 12)),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  side: BorderSide(color: _borderColor),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  try {
                                    final XFile? image = await picker.pickImage(
                                      source: ImageSource.gallery,
                                      imageQuality: 40,
                                      maxWidth: 700,
                                    );
                                    if (image != null) {
                                      final bytes = await image.readAsBytes();
                                      setModalState(() {
                                        photoBase64 = base64Encode(bytes);
                                      });
                                    }
                                  } catch (e) {
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gallery error: $e'), backgroundColor: Colors.redAccent));
                                  }
                                },
                                icon: const Icon(Icons.photo_library, size: 18),
                                label: Text(photoBase64 == null ? "Gallery" : "Gallery (OK)", style: const TextStyle(fontSize: 12)),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  side: BorderSide(color: _borderColor),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (photoBase64 != null) ...[
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(
                              base64Decode(photoBase64!),
                              height: 100,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ]
                      ],
                    ),
                    const SizedBox(height: 28),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          if (nameController.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a name.'), backgroundColor: Colors.redAccent));
                            return;
                          }
                          if (location == null) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please assign GPS location coordinates.'), backgroundColor: Colors.redAccent));
                            return;
                          }
                          
                          final newBuilding = Building(
                            id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
                            name: nameController.text.trim(),
                            lat: location!.latitude,
                            lng: location!.longitude,
                            photoBase64: photoBase64,
                            tags: {
                              'custom': true,
                              if (isClassroom) 'room': 'yes',
                              if (isClassroom && selectedParent != null) 'parent_id': selectedParent!.id,
                              if (floorController.text.isNotEmpty) 'floor': floorController.text.trim(),
                              if (roomController.text.isNotEmpty) 'ref': roomController.text.trim(),
                            },
                          );
                          
                          await _dataService.saveCustomBuilding(newBuilding);
                          setState(() {
                            _buildings.add(newBuilding);
                          });
                          
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Place saved globally to cloud database!'),
                                backgroundColor: Color(0xFF10B981),
                              )
                            );
                          }
                          _mapController.move(location!, 18.5);
                        },
                        icon: const Icon(Icons.check, color: Colors.white),
                        label: const Text("Save Place Globally", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3B82F6),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  ),
);
  }

  void _showEditPlaceModal(Building building) {
    final nameController = TextEditingController(text: building.name);
    final floorController = TextEditingController(text: building.tags['floor']?.toString() ?? '');
    final roomController = TextEditingController(text: building.tags['ref']?.toString() ?? '');
    
    bool isClassroom = building.tags['room'] == 'yes';
    Building? selectedParent;
    try {
      final parentId = building.tags['parent_id'];
      if (parentId != null) {
        selectedParent = _buildings.firstWhere((b) => b.id == parentId);
      }
    } catch (_) {}

    LatLng? location = LatLng(building.lat, building.lng);
    bool isFetchingLocation = false;
    String? photoBase64 = building.photoBase64;
    final ImagePicker picker = ImagePicker();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  height: MediaQuery.of(context).size.height * 0.85,
                  decoration: BoxDecoration(
                    color: _cardBgColor.withValues(alpha: 0.85),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                    border: Border.all(color: _borderColor),
                  ),
                  padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: _textColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      "Edit Place Details",
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _textColor),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Modify coordinates, details, or upload/change the photographic capture.",
                      style: TextStyle(color: _subTextColor, fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                    
                    // Choice of type
                    Row(
                      children: [
                        Text("Category:", style: TextStyle(color: _textColor, fontSize: 14)),
                        const SizedBox(width: 16),
                        ChoiceChip(
                          label: const Text("Building/Lab"),
                          selected: !isClassroom,
                          onSelected: (val) => setModalState(() { isClassroom = false; }),
                          selectedColor: const Color(0xFF3B82F6),
                          backgroundColor: _scaffoldBgColor.withValues(alpha: 0.5),
                          labelStyle: TextStyle(color: !isClassroom ? Colors.white : _textColor.withValues(alpha: 0.7), fontSize: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text("Room/Classroom"),
                          selected: isClassroom,
                          onSelected: (val) => setModalState(() { isClassroom = true; }),
                          selectedColor: const Color(0xFF3B82F6),
                          backgroundColor: _scaffoldBgColor.withValues(alpha: 0.5),
                          labelStyle: TextStyle(color: isClassroom ? Colors.white : _textColor.withValues(alpha: 0.7), fontSize: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Name Input
                    TextField(
                      controller: nameController,
                      style: TextStyle(color: _textColor),
                      decoration: InputDecoration(
                        labelText: "Place Name",
                        labelStyle: TextStyle(color: _textColor.withValues(alpha: 0.5), fontSize: 14),
                        filled: true,
                        fillColor: _scaffoldBgColor.withValues(alpha: 0.5),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Parent Building Dropdown (if room)
                    if (isClassroom) ...[
                      DropdownButtonFormField<Building>(
                        decoration: InputDecoration(
                          labelText: "Located In (Building)",
                          labelStyle: TextStyle(color: _textColor.withValues(alpha: 0.5), fontSize: 14),
                          filled: true,
                          fillColor: _scaffoldBgColor.withValues(alpha: 0.5),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                        ),
                        dropdownColor: _cardBgColor,
                        initialValue: selectedParent,
                        items: _buildings.where((b) => b.id != building.id && (b.tags['building'] == 'college' || !b.tags.containsKey('room'))).map((b) {
                          return DropdownMenuItem(value: b, child: Text(b.name, style: TextStyle(color: _textColor, fontSize: 14)));
                        }).toList(),
                        onChanged: (val) {
                          setModalState(() { selectedParent = val; });
                        },
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Floor & Room number inputs
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: floorController,
                            keyboardType: TextInputType.number,
                            style: TextStyle(color: _textColor),
                            decoration: InputDecoration(
                              labelText: "Floor",
                              labelStyle: TextStyle(color: _textColor.withValues(alpha: 0.5), fontSize: 13),
                              filled: true,
                              fillColor: _scaffoldBgColor.withValues(alpha: 0.5),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: roomController,
                            style: TextStyle(color: _textColor),
                            decoration: InputDecoration(
                              labelText: "Room ID / Number",
                              labelStyle: TextStyle(color: _textColor.withValues(alpha: 0.5), fontSize: 13),
                              filled: true,
                              fillColor: _scaffoldBgColor.withValues(alpha: 0.5),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Location Card
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: _scaffoldBgColor.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: _borderColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Geographical Coordinates", style: TextStyle(color: _textColor, fontWeight: FontWeight.bold, fontSize: 14)),
                          const SizedBox(height: 8),
                          if (location != null)
                            Row(
                              children: [
                                const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 16),
                                const SizedBox(width: 8),
                                Text(
                                  "Lat: ${location!.latitude.toStringAsFixed(6)}, Lng: ${location!.longitude.toStringAsFixed(6)}",
                                  style: const TextStyle(color: Color(0xFF10B981), fontSize: 13, fontWeight: FontWeight.bold),
                                ),
                              ],
                            )
                          else
                            Text("No coordinate assigned yet", style: TextStyle(color: _textColor.withValues(alpha: 0.4), fontSize: 13)),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: isFetchingLocation ? null : () async {
                                setModalState(() { isFetchingLocation = true; });
                                try {
                                  bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
                                  if (!serviceEnabled) throw Exception("Location services disabled.");
                                  
                                  LocationPermission permission = await Geolocator.checkPermission();
                                  if (permission == LocationPermission.denied) {
                                    permission = await Geolocator.requestPermission();
                                  }
                                  if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
                                    throw Exception("Location permission denied.");
                                  }
                                  
                                  final pos = await Geolocator.getCurrentPosition(
                                    locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 8)),
                                  );
                                  setModalState(() { location = LatLng(pos.latitude, pos.longitude); });
                                } catch (e) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent));
                                } finally {
                                  setModalState(() { isFetchingLocation = false; });
                                }
                              },
                              icon: isFetchingLocation 
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blueAccent)) 
                                : const Icon(Icons.gps_fixed, size: 18),
                              label: Text(isFetchingLocation ? "Acquiring satellites..." : "Update to Current GPS Location"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _scaffoldBgColor,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Add Photo Buttons (Camera / Gallery)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Add / Update Photo:", style: TextStyle(color: _textColor.withValues(alpha: 0.8), fontSize: 13, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  try {
                                    final XFile? image = await picker.pickImage(
                                      source: ImageSource.camera,
                                      imageQuality: 40,
                                      maxWidth: 700,
                                    );
                                    if (image != null) {
                                      final bytes = await image.readAsBytes();
                                      setModalState(() {
                                        photoBase64 = base64Encode(bytes);
                                      });
                                    }
                                  } catch (e) {
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Camera error: $e'), backgroundColor: Colors.redAccent));
                                  }
                                },
                                icon: const Icon(Icons.camera_alt, size: 18),
                                label: Text(photoBase64 == null ? "Camera" : "Camera (OK)", style: const TextStyle(fontSize: 12)),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  side: BorderSide(color: _borderColor),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  try {
                                    final XFile? image = await picker.pickImage(
                                      source: ImageSource.gallery,
                                      imageQuality: 40,
                                      maxWidth: 700,
                                    );
                                    if (image != null) {
                                      final bytes = await image.readAsBytes();
                                      setModalState(() {
                                        photoBase64 = base64Encode(bytes);
                                      });
                                    }
                                  } catch (e) {
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gallery error: $e'), backgroundColor: Colors.redAccent));
                                  }
                                },
                                icon: const Icon(Icons.photo_library, size: 18),
                                label: Text(photoBase64 == null ? "Gallery" : "Gallery (OK)", style: const TextStyle(fontSize: 12)),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  side: BorderSide(color: _borderColor),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (photoBase64 != null) ...[
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(
                              base64Decode(photoBase64!),
                              height: 100,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ]
                      ],
                    ),
                    const SizedBox(height: 28),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          if (nameController.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a name.'), backgroundColor: Colors.redAccent));
                            return;
                          }
                          if (location == null) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please assign GPS location coordinates.'), backgroundColor: Colors.redAccent));
                            return;
                          }
                          
                          final updatedBuilding = Building(
                            id: building.id,
                            name: nameController.text.trim(),
                            lat: location!.latitude,
                            lng: location!.longitude,
                            photoBase64: photoBase64,
                            tags: {
                              ...building.tags,
                              'custom': true,
                              if (isClassroom) 'room': 'yes',
                              if (!isClassroom) ...{'room': null},
                              'parent_id': isClassroom && selectedParent != null ? selectedParent!.id : null,
                              'floor': floorController.text.isNotEmpty ? floorController.text.trim() : null,
                              'ref': roomController.text.isNotEmpty ? roomController.text.trim() : null,
                            }..removeWhere((k, v) => v == null),
                          );
                          
                          await _dataService.saveCustomBuilding(updatedBuilding);
                          
                          setState(() {
                            final index = _buildings.indexWhere((b) => b.id == building.id);
                            if (index != -1) {
                              _buildings[index] = updatedBuilding;
                            } else {
                              _buildings.add(updatedBuilding);
                            }
                            _selectedBuilding = updatedBuilding;
                          });
                          
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Place updated globally in cloud database!'),
                                backgroundColor: Color(0xFF10B981),
                              )
                            );
                          }
                        },
                        icon: const Icon(Icons.check, color: Colors.white),
                        label: const Text("Save Changes Globally", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  ),
);
  }

  // --- Glassmorphic Telemetry Dashboard Widgets & Helpers ---
  Widget _buildSensorDashboardWidget(BuildContext context, TelemetryData telemetry) {
    final double panelWidth = min(MediaQuery.of(context).size.width - 32, 320);

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          width: panelWidth,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _appThemeMode == 'light'
                ? Colors.white.withValues(alpha: 0.82)
                : const Color(0xFF0F172A).withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: _appThemeMode == 'light'
                  ? Colors.black.withValues(alpha: 0.12)
                  : Colors.white.withValues(alpha: 0.18),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                spreadRadius: 1,
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      _buildTelemetryDot(),
                      const SizedBox(width: 8),
                      Text(
                        "TELEMETRY",
                        style: TextStyle(
                          color: _textColor,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2.0,
                        ),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _showSensorDashboard = false;
                        if (!_isNavigating) {
                          _stopTelemetryListening();
                        }
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: _textColor.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.close, color: _textColor.withValues(alpha: 0.7), size: 16),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Status Badges
              Row(
                children: [
                  _buildStatusBadge("ACCEL", telemetry.accelMag == 0.0 ? "STANDBY" : "LIVE", Colors.cyanAccent),
                  const SizedBox(width: 6),
                  _buildStatusBadge("COMPASS", telemetry.heading == 0.0 ? "SIM" : "LIVE", Colors.amberAccent),
                  const SizedBox(width: 6),
                  _buildStatusBadge("PDR", _isNavigating ? "ACTIVE" : "STANDBY", Colors.greenAccent),
                ],
              ),
              const SizedBox(height: 12),

              // Rotating Compass
              Center(
                child: Column(
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 110,
                          height: 110,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _textColor.withValues(alpha: 0.12),
                              width: 3.5,
                            ),
                          ),
                        ),
                        // Rotating dial
                        Transform.rotate(
                          angle: -telemetry.heading * pi / 180,
                          child: CustomPaint(
                            size: const Size(100, 100),
                            painter: CompassDialPainter(textColor: _textColor),
                          ),
                        ),
                        // Fixed pointer pointing north
                        const Positioned(
                          top: 2,
                          child: Icon(
                            Icons.arrow_drop_up,
                            color: Colors.redAccent,
                            size: 24,
                          ),
                        ),
                        // Center readout bubble
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _cardBgColor.withValues(alpha: 0.85),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                              width: 1.0,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              "${telemetry.heading.toStringAsFixed(0)}°",
                              style: TextStyle(
                                color: _textColor,
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _getHeadingDirectionText(telemetry.heading),
                      style: TextStyle(
                        color: _textColor.withValues(alpha: 0.85),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Accelerometer physical meters
              Text(
                "ACCELEROMETER SENSOR (m/s²)",
                style: TextStyle(
                  color: _textColor.withValues(alpha: 0.55),
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 6),
              _buildAccelAxisIndicator("X", telemetry.accelX, Colors.redAccent),
              const SizedBox(height: 4),
              _buildAccelAxisIndicator("Y", telemetry.accelY, Colors.greenAccent),
              const SizedBox(height: 4),
              _buildAccelAxisIndicator("Z", telemetry.accelZ, Colors.blueAccent),
              
              // Sparkline graph
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "VIBRATION TELEMETRY",
                    style: TextStyle(
                      color: _textColor.withValues(alpha: 0.55),
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                  Text(
                    "Mag: ${telemetry.accelMag.toStringAsFixed(2)}",
                    style: TextStyle(
                      color: _textColor.withValues(alpha: 0.8),
                      fontSize: 9,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                height: 32,
                padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
                decoration: BoxDecoration(
                  color: _textColor.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _borderColor),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: telemetry.magHistory.map((val) {
                    final heightFactor = (val / 10.0).clamp(0.08, 1.0);
                    return Container(
                      width: 8,
                      height: 24 * heightFactor,
                      decoration: BoxDecoration(
                        color: Color.lerp(Colors.cyan, Colors.redAccent, (val / 6.0).clamp(0.0, 1.0)),
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                    );
                  }).toList(),
                ),
              ),

              // PDR Step engine details
              const SizedBox(height: 12),
              Text(
                "PEDESTRIAN DEAD RECKONING (PDR)",
                style: TextStyle(
                  color: _textColor.withValues(alpha: 0.55),
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.directions_walk, color: const Color(0xFF10B981), size: 14),
                      const SizedBox(width: 4),
                      Text(
                        "$_stepCount steps",
                        style: TextStyle(color: _textColor, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Text(
                    "Dist: ${(_stepCount * 0.7).toStringAsFixed(1)} m",
                    style: TextStyle(color: _subTextColor, fontSize: 11),
                  ),
                ],
              ),

              // Compass Offset Calibration slider
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "CALIBRATE COMPASS BIAS",
                    style: TextStyle(
                      color: _textColor.withValues(alpha: 0.55),
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    "${_compassOffset >= 0 ? '+' : ''}${_compassOffset.toStringAsFixed(0)}°",
                    style: TextStyle(color: _textColor, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 1.5,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                ),
                child: Slider(
                  value: _compassOffset,
                  min: -180.0,
                  max: 180.0,
                  onChanged: (val) {
                    setState(() {
                      _compassOffset = val;
                      _telemetryHeading = (_pdrService.rawHeading + _compassOffset + 360) % 360;
                    });
                    _telemetryNotifier.value = TelemetryData(
                      heading: _telemetryHeading,
                      accelX: telemetry.accelX,
                      accelY: telemetry.accelY,
                      accelZ: telemetry.accelZ,
                      accelMag: telemetry.accelMag,
                      magHistory: telemetry.magHistory,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTelemetryDot() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.greenAccent,
            boxShadow: [
              BoxShadow(
                color: Colors.greenAccent.withValues(alpha: 0.6 * (1.0 - _pulseController.value)),
                blurRadius: 3 + _pulseController.value * 5,
                spreadRadius: _pulseController.value * 2.5,
              )
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusBadge(String name, String status, Color activeColor) {
    final isLive = status == "LIVE" || status == "ACTIVE";
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: (isLive ? activeColor : Colors.blueAccent).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: (isLive ? activeColor : Colors.blueAccent).withValues(alpha: 0.25),
          width: 0.8,
        ),
      ),
      child: Text(
        "$name: $status",
        style: TextStyle(
          color: isLive ? activeColor : Colors.blueAccent,
          fontSize: 8.5,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildAccelAxisIndicator(String axis, double val, Color color) {
    final double clamped = val.clamp(-8.0, 8.0);
    final double percentage = (clamped + 8.0) / 16.0;

    return Row(
      children: [
        SizedBox(
          width: 10,
          child: Text(
            axis,
            style: TextStyle(
              color: _textColor.withValues(alpha: 0.6),
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Container(
              height: 6,
              color: _textColor.withValues(alpha: 0.08),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: percentage,
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 38,
          child: Text(
            "${val >= 0 ? '+' : ''}${val.toStringAsFixed(2)}",
            textAlign: TextAlign.right,
            style: TextStyle(
              color: _textColor,
              fontFamily: 'monospace',
              fontSize: 9,
            ),
          ),
        ),
      ],
    );
  }

  String _getHeadingDirectionText(double heading) {
    final deg = (heading + 360) % 360;
    if (deg >= 337.5 || deg < 22.5) return "North (N)";
    if (deg >= 22.5 && deg < 67.5) return "North-East (NE)";
    if (deg >= 67.5 && deg < 112.5) return "East (E)";
    if (deg >= 112.5 && deg < 157.5) return "South-East (SE)";
    if (deg >= 157.5 && deg < 202.5) return "South (S)";
    if (deg >= 202.5 && deg < 247.5) return "South-West (SW)";
    if (deg >= 247.5 && deg < 292.5) return "West (W)";
    return "North-West (NW)";
  }
}

class CompassDialPainter extends CustomPainter {
  final Color textColor;
  CompassDialPainter({required this.textColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = textColor.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    canvas.drawCircle(center, radius, paint);

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    for (int i = 0; i < 360; i += 15) {
      final angle = i * pi / 180;
      final isCardinal = i % 90 == 0;
      final tickLength = isCardinal ? 8.0 : 4.0;

      final start = Offset(
        center.dx + (radius - tickLength) * sin(angle),
        center.dy - (radius - tickLength) * cos(angle),
      );
      final end = Offset(
        center.dx + radius * sin(angle),
        center.dy - radius * cos(angle),
      );

      canvas.drawLine(start, end, paint);

      if (isCardinal) {
        String label = "";
        switch (i) {
          case 0:
            label = "N";
            break;
          case 90:
            label = "E";
            break;
          case 180:
            label = "S";
            break;
          case 270:
            label = "W";
            break;
        }

        textPainter.text = TextSpan(
          text: label,
          style: TextStyle(
            color: label == "N" ? Colors.redAccent : textColor.withValues(alpha: 0.7),
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(
            center.dx + (radius - 16) * sin(angle) - textPainter.width / 2,
            center.dy - (radius - 16) * cos(angle) - textPainter.height / 2,
          ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CompassDialPainter oldDelegate) =>
      oldDelegate.textColor != textColor;
}

class DirectionBeamPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF3B82F6).withValues(alpha: 0.4),
          const Color(0xFF3B82F6).withValues(alpha: 0.0),
        ],
        stops: const [0.25, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(size.width / 2, size.height / 2), radius: size.width / 2))
      ..style = PaintingStyle.fill;

    final path = Path();
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // A 40-degree wide field-of-view cone pointing UP (-90 degrees / -pi/2)
    const double coneAngleRad = 40.0 * (pi / 180.0);
    const double startAngle = -pi / 2.0 - coneAngleRad / 2.0;

    path.moveTo(center.dx, center.dy);
    path.arcTo(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      coneAngleRad,
      false,
    );
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
