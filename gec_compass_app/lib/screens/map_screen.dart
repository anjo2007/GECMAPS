import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/building.dart';
import '../services/data_service.dart';
import '../services/pdr_service.dart';
import '../services/routing_service.dart';
import '../services/web_sensors_stub.dart' if (dart.library.html) '../services/web_sensors_web.dart';

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

  List<Building> _buildings = [];
  Building? _selectedBuilding;
  bool _isNavigating = false;
  int _stepCount = 0;
  List<LatLng> _pdrTrail = [];

  // Dijkstra route path coordinates and turn-by-turn instructions
  List<LatLng> _routingPath = [];
  List<String> _routeInstructions = [];
  int _currentInstructionIndex = 0;
  int _simulatedRouteIndex = 0;

  // Category filter state
  final List<String> _categories = ['All', 'Departments', 'Workshops', 'Hostels', 'Cafes/ATMs', 'Rooms/Labs'];
  String _selectedCategory = 'All';

  LatLng? _currentPosition;
  bool _isLoading = true;
  String? _loadError;

  // Onboarding Carousel state
  bool _showOnboarding = false;
  final PageController _onboardingPageController = PageController();
  int _onboardingPageIndex = 0;

  // Pulsing animation for selected markers
  late AnimationController _pulseController;

  // GEC Thrissur Center
  final LatLng _campusCenter = const LatLng(10.555761, 76.224317);

  // New state variables for upgraded algorithms and HUD UX
  List<List<LatLng>> _roadEdges = [];
  int _selectedFloor = 0;
  bool _audioNavigationEnabled = true;
  String _lastAnnouncedInstruction = "";
  double _deviceHeading = 0.0;
  bool _expandDirections = false;

  // Theme and Style settings
  bool _isDarkMode = false; // default to light glassy theme
  String _mapStyle = 'roadmap'; // 'roadmap' or 'satellite'

  Color get _panelBgColor => _isDarkMode 
      ? const Color(0xFF0F172A).withOpacity(0.85) 
      : Colors.white.withOpacity(0.70);

  Color get _borderColor => _isDarkMode 
      ? Colors.white.withOpacity(0.12) 
      : Colors.black.withOpacity(0.08);

  Color get _textColor => _isDarkMode 
      ? Colors.white 
      : const Color(0xFF0F172A);

  Color get _subTextColor => _isDarkMode 
      ? Colors.white70 
      : const Color(0xFF475569);

  Color get _cardBgColor => _isDarkMode 
      ? const Color(0xFF1E293B) 
      : Colors.white.withOpacity(0.85);

  Color get _scaffoldBgColor => _isDarkMode 
      ? const Color(0xFF0F172A) 
      : const Color(0xFFF8FAFC);

  String _getTileUrl() {
    if (_mapStyle == 'satellite') {
      return 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
    }
    return _isDarkMode
        ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
        : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png';
  }

  @override
  void initState() {
    super.initState();
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _initData();

    _pdrService.onPositionUpdated = (LatLng newPosition) {
      if (!mounted) return;
      setState(() {
        _currentPosition = newPosition;
        _pdrTrail.add(newPosition);
      });
      _mapController.move(newPosition, _mapController.camera.zoom);
      _checkAudioNavigation();
    };

    _pdrService.onStepDetected = (int count) {
      if (!mounted) return;
      setState(() {
        _stepCount = count;
      });
    };

    _pdrService.onHeadingUpdated = (double heading) {
      if (!mounted) return;
      setState(() {
        _deviceHeading = heading;
      });
    };
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _pdrService.stopPDR();
    _onboardingPageController.dispose();
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

      _roadEdges = _routingService.getRoadEdges();
      _pdrService.roadEdges = _roadEdges;

      if (!mounted) return;
      setState(() {
        _buildings = buildings;
        _currentPosition = userPos;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _isLoading = false;
      });
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
        _pdrService.stopPDR();
        _isNavigating = false;
        _pdrTrail.clear();
        _routingPath.clear();
        _routeInstructions.clear();
      }
      FocusScope.of(context).unfocus();
    });

    _mapController.move(LatLng(building.lat, building.lng), 18.5);
    _showBuildingDetails(building);
  }

  void _announceInstruction(String text) {
    if (!_audioNavigationEnabled) return;
    if (_lastAnnouncedInstruction == text) return;
    _lastAnnouncedInstruction = text;
    speakWeb(text);
  }

  void _checkAudioNavigation() {
    if (!_isNavigating || _routeInstructions.isEmpty) return;

    final dist = _currentPosition != null && _selectedBuilding != null
        ? _distanceMeters(_currentPosition!, LatLng(_selectedBuilding!.lat, _selectedBuilding!.lng))
        : null;

    final floorTag = _selectedBuilding?.tags['floor'];

    String primaryInstruction = "Head towards ${_selectedBuilding!.name}";
    if (_routeInstructions.isNotEmpty && _currentInstructionIndex < _routeInstructions.length) {
      primaryInstruction = _routeInstructions[_currentInstructionIndex];
    }

    if (dist != null) {
      if (dist < 5.0) {
        _announceInstruction("You have arrived at ${_selectedBuilding!.name}");
      } else if (dist < 15.0 && floorTag != null && floorTag.toString().isNotEmpty) {
        _announceInstruction("Take stairs to Floor $floorTag, then proceed to ${_selectedBuilding!.name}");
      } else {
        _announceInstruction(primaryInstruction);
      }
    }
  }

  void _startNavigation() {
    if (_selectedBuilding == null) return;
    
    final startPos = _currentPosition ?? _campusCenter;
    final endPos = LatLng(_selectedBuilding!.lat, _selectedBuilding!.lng);

    // Get Dijkstra shortest-path along campus roads
    final path = _routingService.getFullRoute(startPos, endPos);
    final instructions = _routingService.getRouteInstructions(path);

    _pdrService.activeRoute = path; // Feed snapping polyline to PDRService
    _pdrService.startPDR(startPos);
    setState(() {
      _isNavigating = true;
      _stepCount = 0;
      _pdrTrail = [startPos];
      _routingPath = path;
      _routeInstructions = instructions;
      _currentInstructionIndex = 0;
      _simulatedRouteIndex = 0;
      _lastAnnouncedInstruction = "";
      _expandDirections = false;
    });

    if (instructions.isNotEmpty) {
      _announceInstruction(instructions.first);
    }

    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Interactive Web Navigation: Use "Simulate Step" or tap on the map to walk.'),
          duration: Duration(seconds: 4),
          backgroundColor: Color(0xFF3B82F6),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Navigation started along campus walkways!'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
    }
  }

  void _stopNavigation() {
    _pdrService.stopPDR();
    _pdrService.activeRoute = [];
    setState(() {
      _isNavigating = false;
      _pdrTrail.clear();
      _routingPath.clear();
      _routeInstructions.clear();
      _currentInstructionIndex = 0;
      _simulatedRouteIndex = 0;
      _lastAnnouncedInstruction = "";
      _expandDirections = false;
    });
  }

  // Handle manual steps for testing in the browser
  void _simulateNextStep() {
    if (!_isNavigating || _routingPath.isEmpty) return;

    if (_simulatedRouteIndex < _routingPath.length - 1) {
      _simulatedRouteIndex++;
      final nextPos = _routingPath[_simulatedRouteIndex];
      final prevPos = _currentPosition ?? _campusCenter;
      
      // Calculate bearing direction
      final bearing = _calculateBearing(prevPos, nextPos);
      
      _pdrService.forceSetPosition(nextPos);
      _pdrService.triggerManualStep(bearing);

      setState(() {
        if (_currentInstructionIndex < _routeInstructions.length - 1) {
          _currentInstructionIndex = _simulatedRouteIndex - 1;
        }
      });
      _checkAudioNavigation();
    } else {
      _announceInstruction("You have arrived at your destination!");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You have arrived at your destination!'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
      _stopNavigation();
    }
  }

  double _calculateBearing(LatLng start, LatLng end) {
    final lat1 = start.latitude * pi / 180;
    final lon1 = start.longitude * pi / 180;
    final lat2 = end.latitude * pi / 180;
    final lon2 = end.longitude * pi / 180;

    final dLon = lon2 - lon1;
    final y = sin(dLon) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);

    final bearing = atan2(y, x) * 180 / pi;
    return (bearing + 360) % 360;
  }

  // Filter buildings on the map based on the active category chip and floor level
  List<Building> _getFilteredBuildings() {
    List<Building> list = _buildings;
    if (_selectedCategory != 'All') {
      list = list.where((b) {
        final amenity = b.tags['amenity'] as String?;
        final buildingType = b.tags['building'] as String?;
        final tourism = b.tags['tourism'] as String?;
        final isRoom = b.tags['room'] == 'yes';

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

    // Now apply floor level filter to rooms/classrooms
    list = list.where((b) {
      final isRoom = b.tags['room'] == 'yes';
      if (isRoom) {
        final floorStr = b.tags['floor']?.toString() ?? '0';
        final floorVal = int.tryParse(floorStr) ?? 0;
        return floorVal == _selectedFloor;
      }
      return true; // Main department buildings / general POIs stay visible on all floors
    }).toList();

    return list;
  }

  void _showBuildingDetails(Building building) {
    final double? dist = _currentPosition != null
        ? _distanceMeters(_currentPosition!, LatLng(building.lat, building.lng))
        : null;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: _panelBgColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: _borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
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
                  color: _textColor.withOpacity(0.2),
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
                      color: Colors.blueAccent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
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
                            color: _cardBgColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _borderColor),
                          ),
                          child: Text(
                            "${e.key}: ${e.value}",
                            style: TextStyle(fontSize: 11, color: _subTextColor),
                          ),
                        ))
                    .toList(),
              ),
            ],
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF3B82F6), Color(0xFFEC4899)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFEC4899).withOpacity(0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
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
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _editBuildingDetails(building);
                },
                icon: Icon(Icons.edit_note, color: _textColor),
                label: Text(
                  "Edit Details & Upload Photo",
                  style: TextStyle(color: _textColor, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredBuildings = _getFilteredBuildings();

    return Scaffold(
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
                        style: const TextStyle(color: Colors.white70)),
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
                },
                onTap: (tapPosition, point) {
                  // Interactive Web debug tapping
                  if (_isNavigating && kIsWeb) {
                    _pdrService.forceSetPosition(point);
                  }
                },
              ),
              children: [
                // Dynamically themed map tiles (Roadmap light/dark or Satellite)
                TileLayer(
                  urlTemplate: _getTileUrl(),
                  subdomains: _mapStyle == 'satellite' ? const [] : const ['a', 'b', 'c', 'd'],
                  userAgentPackageName: 'com.example.gec_compass_app',
                ),
                
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
                    width: 60,
                    height: 60,
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
                          color: _panelBgColor,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: _borderColor),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12,
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
                                hintStyle: TextStyle(color: _textColor.withOpacity(0.5)),
                                prefixIcon: Icon(Icons.search, color: _textColor.withOpacity(0.5)),
                                suffixIcon: textEditingController.text.isNotEmpty 
                                    ? IconButton(
                                        icon: Icon(Icons.clear, color: _textColor.withOpacity(0.6), size: 18),
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
                                          color: Colors.black26,
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
                              color: isSelected ? Colors.white : _subTextColor,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              fontSize: 13,
                            ),
                            selectedColor: const Color(0xFF3B82F6),
                            backgroundColor: _cardBgColor,
                            side: BorderSide(color: isSelected ? Colors.transparent : _borderColor),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

          // Floating Buttons on the right
          if (!_isNavigating)
            Positioned(
              bottom: 32,
              right: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton(
                    heroTag: 'add_place_btn',
                    backgroundColor: const Color(0xFF3B82F6),
                    foregroundColor: Colors.white,
                    onPressed: _showAddPlaceModal,
                    child: const Icon(Icons.add_location_alt),
                  ),
                  const SizedBox(height: 14),
                  FloatingActionButton(
                    heroTag: 'recenter_btn',
                    backgroundColor: _cardBgColor,
                    foregroundColor: const Color(0xFF3B82F6),
                    onPressed: () {
                      if (_currentPosition != null) {
                        _mapController.move(_currentPosition!, 18.5);
                      } else {
                        _mapController.move(_campusCenter, 16.5);
                      }
                    },
                    child: const Icon(Icons.my_location),
                  ),
                ],
              ),
            ),

          // Feedback Button
          if (!_isNavigating)
            Positioned(
              bottom: 32,
              left: 16,
              child: FloatingActionButton.extended(
                heroTag: 'feedback_btn',
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                icon: const Icon(Icons.rate_review),
                label: const Text('Feedback',
                    style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                onPressed: _showFeedbackModal,
              ),
            ),

          // Web simulated navigation walkthrough buttons
          if (_isNavigating && kIsWeb)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 120,
              left: 0,
              right: 0,
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      color: const Color(0xFF0F172A).withOpacity(0.85),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _simulateNextStep,
                            icon: const Icon(Icons.directions_walk, size: 18, color: Colors.white),
                            label: const Text("Simulate Step", style: TextStyle(color: Colors.white, fontSize: 13)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF3B82F6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text("or Tap map to jump", style: TextStyle(color: Colors.white60, fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Digital Compass HUD
          _buildCompassHUD(),

          // Theme & Satellite Toggle Controls
          _buildMapControls(),

          // GEC Compass Logo Badge (hidden when navigating to make space for turn instructions)
          if (!_isNavigating) _buildGECCompassLogoBadge(),

          // Floor level switcher
          if (_shouldShowFloorSelector)
            Positioned(
              bottom: _isNavigating ? 140 : 180,
              right: 16,
              child: _buildFloorSelector(),
            ),

          // Navigation UI Overlay
          if (_isNavigating) _buildNavigationOverlay(),

          // Welcome Onboarding Overlay
          if (_showOnboarding) _buildOnboardingOverlay(),
        ],
      ),
    );
  }

  // Draw user position with smooth pulsing outer glow
  Widget _buildUserLocationMarker() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 30 + _pulseController.value * 25,
              height: 30 + _pulseController.value * 25,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF3B82F6).withOpacity(0.4 * (1.0 - _pulseController.value)),
              ),
            ),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 4,
                    spreadRadius: 1,
                  )
                ],
              ),
              child: Center(
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF3B82F6),
                  ),
                ),
              ),
            )
          ],
        );
      },
    );
  }

  // Draw customized pins for buildings
  Widget _buildMarkerIcon(Building b) {
    final isSelected = _selectedBuilding?.id == b.id;
    final color = isSelected ? Colors.greenAccent : _getMarkerColor(b);
    final icon = _getMarkerIcon(b);

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            if (isSelected)
              Container(
                width: 32 + _pulseController.value * 24,
                height: 32 + _pulseController.value * 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withOpacity(0.5 * (1.0 - _pulseController.value)),
                ),
              ),
            Container(
              width: isSelected ? 40 : 32,
              height: isSelected ? 40 : 32,
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A).withOpacity(0.9),
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.4),
                    blurRadius: isSelected ? 8 : 4,
                    spreadRadius: isSelected ? 2 : 1,
                  )
                ],
              ),
              child: Center(
                child: Icon(
                  icon,
                  color: color,
                  size: isSelected ? 22 : 16,
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

    if (dist < 15.0 && floorTag != null && floorTag.toString().isNotEmpty) {
      primaryInstruction = "Take stairs to Floor $floorTag";
      secondaryInstruction = "Then proceed to ${_selectedBuilding!.name}";
      turnIcon = Icons.stairs;
      topBarColor = const Color(0xFF3B82F6); // Blue for indoor instructions
    } else if (dist < 5.0) {
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
                  color: topBarColor.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.15)),
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
                            style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        
        // Bottom Navigation Status Bar (Expandable directions drawer)
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            height: _expandDirections ? MediaQuery.of(context).size.height * 0.45 : 120 + MediaQuery.of(context).padding.bottom,
            decoration: BoxDecoration(
              color: _panelBgColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(color: _borderColor),
              boxShadow: [
                BoxShadow(color: Colors.black26, blurRadius: 25, offset: const Offset(0, -6)),
              ],
            ),
            padding: const EdgeInsets.only(left: 24, right: 24, top: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Pull bar drawer handle gesture indicator
                Center(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _expandDirections = !_expandDirections;
                      });
                    },
                    child: Container(
                      width: 50,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
                // Compact HUD line
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _expandDirections = !_expandDirections;
                          });
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text("$minutes min", style: const TextStyle(color: Color(0xFF10B981), fontSize: 24, fontWeight: FontWeight.bold)),
                                const SizedBox(width: 8),
                                Text(_formatDistance(dist), style: TextStyle(color: _textColor, fontSize: 16)),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Icon(Icons.directions_walk, color: _subTextColor, size: 14),
                                const SizedBox(width: 4),
                                Text("$_stepCount steps taken", style: TextStyle(color: _subTextColor, fontSize: 12)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: _stopNavigation,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent.withOpacity(0.85),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      child: const Icon(Icons.close, color: Colors.white, size: 22),
                    ),
                  ],
                ),
                
                // Detailed Turn-by-Turn directions list visible when drawer is expanded
                if (_expandDirections) ...[
                  const SizedBox(height: 16),
                  Divider(color: _borderColor, height: 1),
                  const SizedBox(height: 12),
                  Text(
                    "Directions List",
                    style: TextStyle(color: _textColor, fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: _routeInstructions.length,
                      separatorBuilder: (c, i) => Divider(color: _borderColor, height: 1),
                      itemBuilder: (context, index) {
                        final instr = _routeInstructions[index];
                        final isCompleted = index < _currentInstructionIndex;
                        final isCurrent = index == _currentInstructionIndex;
                        
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            radius: 14,
                            backgroundColor: isCurrent 
                              ? const Color(0xFF3B82F6) 
                              : (isCompleted ? Colors.white12 : _cardBgColor),
                            child: Icon(
                              index == _routeInstructions.length - 1 
                                ? Icons.flag 
                                : (isCurrent ? Icons.play_arrow : Icons.check),
                              color: isCurrent ? Colors.white : (isCompleted ? _subTextColor.withOpacity(0.5) : _textColor.withOpacity(0.5)),
                              size: 14,
                            ),
                          ),
                          title: Text(
                            instr,
                            style: TextStyle(
                              color: isCurrent 
                                ? const Color(0xFF3B82F6) 
                                : (isCompleted ? _subTextColor.withOpacity(0.5) : _textColor),
                              fontSize: 13,
                              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Render onboarding/instructional carousel with height calibration field
  Widget _buildOnboardingOverlay() {
    final slides = [
      _buildOnboardingSlide(
        title: "Welcome to GEC Compass",
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
      _buildHeightCalibrationSlide(),
      _buildOnboardingSlide(
        title: "Global Updates",
        desc: "Add missing rooms, classes, or labs with photos and coordinates. Updates sync globally to a shared cloud database instantly.",
        icon: Icons.cloud_sync,
        iconColor: Colors.purpleAccent,
      )
    ];

    return Container(
      color: Colors.black87.withOpacity(0.85),
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              width: MediaQuery.of(context).size.width * 0.88,
              height: 480,
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white.withOpacity(0.12)),
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
                          color: _onboardingPageIndex == index ? const Color(0xFF3B82F6) : Colors.white30,
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

  Widget _buildHeightCalibrationSlide() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.height, size: 80, color: Color(0xFF3B82F6)),
        const SizedBox(height: 20),
        const Text(
          "PDR Step Calibration",
          style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        const Text(
          "Enter your height to automatically calibrate your average step length for Pedestrian Dead Reckoning (PDR).",
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "${(_pdrService.userHeight * 100).toStringAsFixed(0)} cm",
              style: const TextStyle(color: Color(0xFF3B82F6), fontSize: 28, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        Slider(
          value: _pdrService.userHeight,
          min: 1.30,
          max: 2.10,
          divisions: 80,
          onChanged: (val) {
            setState(() {
              _pdrService.userHeight = val;
            });
          },
        ),
      ],
    );
  }

  // Dynamic floating floor selector widget (G, 1, 2)
  Widget _buildFloorSelector() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        final floorText = index == 0 ? 'G' : '$index';
        final isSelected = _selectedFloor == index;
        return Padding(
          padding: const EdgeInsets.only(bottom: 6.0),
          child: SizedBox(
            width: 44,
            height: 44,
            child: FloatingActionButton(
              heroTag: 'floor_btn_$index',
              mini: true,
              backgroundColor: isSelected ? const Color(0xFF3B82F6) : _cardBgColor,
              foregroundColor: isSelected ? Colors.white : _textColor,
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isSelected ? Colors.blueAccent : _borderColor,
                  width: 1.5,
                ),
              ),
              onPressed: () {
                setState(() {
                  _selectedFloor = index;
                });
              },
              child: Text(
                floorText,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
          ),
        );
      }).reversed.toList(),
    );
  }

  bool get _shouldShowFloorSelector {
    if (_selectedCategory == 'Rooms/Labs') return true;
    if (_selectedBuilding != null) {
      final isRoom = _selectedBuilding!.tags['room'] == 'yes';
      final parentId = _selectedBuilding!.id;
      final hasRooms = _buildings.any((b) => b.tags['parent_id'] == parentId);
      return isRoom || hasRooms;
    }
    return false;
  }

  // Glowing Digital HUD Compass overlay
  Widget _buildCompassHUD() {
    double? targetBearing;
    if (_isNavigating && _routingPath.isNotEmpty && _simulatedRouteIndex < _routingPath.length - 1) {
      final nextPos = _routingPath[_simulatedRouteIndex];
      final currentPos = _currentPosition ?? _campusCenter;
      targetBearing = _calculateBearing(currentPos, nextPos);
    }

    return Positioned(
      top: MediaQuery.of(context).padding.top + 130,
      right: 16,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _audioNavigationEnabled = !_audioNavigationEnabled;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_audioNavigationEnabled ? 'Voice Guidance Enabled' : 'Voice Guidance Muted'),
              duration: const Duration(seconds: 2),
              backgroundColor: _audioNavigationEnabled ? const Color(0xFF10B981) : Colors.amber,
            ),
          );
        },
        child: Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _panelBgColor,
            border: Border.all(color: _borderColor, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF3B82F6).withOpacity(_isNavigating ? 0.35 : 0.15),
                blurRadius: 10,
                spreadRadius: 2,
              )
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Rotating Compass Ring dial
              Transform.rotate(
                angle: -_deviceHeading * pi / 180,
                child: CustomPaint(
                  size: const Size(76, 76),
                  painter: CompassDialPainter(color: _textColor),
                ),
              ),
              // Target bearing needle pointing to next waypoint
              if (targetBearing != null)
                Transform.rotate(
                  angle: (targetBearing - _deviceHeading) * pi / 180,
                  child: const Icon(
                    Icons.navigation,
                    color: Color(0xFF10B981),
                    size: 24,
                  ),
                ),
              // Center digital reading & Audio status icon
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "${_deviceHeading.toStringAsFixed(0)}°",
                    style: TextStyle(
                      color: _textColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Courier',
                    ),
                  ),
                  Icon(
                    _audioNavigationEnabled ? Icons.volume_up : Icons.volume_off,
                    color: _audioNavigationEnabled ? const Color(0xFF3B82F6) : _textColor.withOpacity(0.35),
                    size: 11,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Floating controls to toggle Satellite View and Dark/Light Glassy theme
  Widget _buildMapControls() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 220,
      right: 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Layer Switcher (Roadmap vs Satellite)
          FloatingActionButton.small(
            heroTag: 'layer_switcher_btn',
            backgroundColor: _panelBgColor,
            foregroundColor: _textColor,
            elevation: 3,
            shape: CircleBorder(side: BorderSide(color: _borderColor)),
            onPressed: () {
              setState(() {
                _mapStyle = _mapStyle == 'roadmap' ? 'satellite' : 'roadmap';
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(_mapStyle == 'satellite' ? 'Satellite View Active' : 'Roadmap View Active'),
                  duration: const Duration(seconds: 2),
                  backgroundColor: const Color(0xFF3B82F6),
                ),
              );
            },
            child: Icon(_mapStyle == 'satellite' ? Icons.satellite_alt : Icons.map),
          ),
          const SizedBox(height: 10),
          // Theme Switcher (Light Glass vs Dark Glass)
          FloatingActionButton.small(
            heroTag: 'theme_switcher_btn',
            backgroundColor: _panelBgColor,
            foregroundColor: _textColor,
            elevation: 3,
            shape: CircleBorder(side: BorderSide(color: _borderColor)),
            onPressed: () {
              setState(() {
                _isDarkMode = !_isDarkMode;
              });
            },
            child: Icon(_isDarkMode ? Icons.light_mode : Icons.dark_mode),
          ),
        ],
      ),
    );
  }

  Widget _buildOnboardingSlide({required String title, required String desc, required IconData icon, required Color iconColor}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 80, color: iconColor),
        const SizedBox(height: 28),
        Text(
          title,
          style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Text(
          desc,
          style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
          textAlign: TextAlign.center,
        ),
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
        child: Container(
          decoration: BoxDecoration(
            color: _panelBgColor,
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
                    color: _textColor.withOpacity(0.2),
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
                  hintStyle: TextStyle(color: _subTextColor.withOpacity(0.6)),
                  filled: true,
                  fillColor: _cardBgColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF3B82F6), Color(0xFFEC4899)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFEC4899).withOpacity(0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final text = feedbackController.text.trim();
                    if (text.isNotEmpty) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Sending report globally...'),
                          backgroundColor: Colors.blueAccent,
                          duration: Duration(seconds: 1),
                        ),
                      );

                      // 1. Submit to database globally
                      await _dataService.submitFeedback(text);

                      // 2. Format a structured body for mail client
                      final String email = 'anjo28mj@gmail.com';
                      final String subject = 'GEC Compass Feedback Report';
                      final String timestamp = DateTime.now().toLocal().toString();
                      final String platform = kIsWeb ? 'Web Browser' : 'Android App';
                      
                      // Build a clean, readable text template representing the feedback
                      final String body = 'GEC COMPASS FEEDBACK REPORT\n'
                          '=================================\n\n'
                          'Feedback Message:\n'
                          '---------------------------------\n'
                          '$text\n'
                          '---------------------------------\n\n'
                          'Metadata:\n'
                          '- Timestamp: $timestamp\n'
                          '- Platform: $platform\n'
                          '- Database Status: Synced Successfully\n\n'
                          'Thank you for contributing to GEC Compass!';

                      final String subjectEncoded = Uri.encodeComponent(subject);
                      final String bodyEncoded = Uri.encodeComponent(body);
                      final Uri emailUri = Uri.parse('mailto:$email?subject=$subjectEncoded&body=$bodyEncoded');

                      try {
                        if (await canLaunchUrl(emailUri)) {
                          await launchUrl(emailUri, mode: LaunchMode.externalApplication);
                        } else {
                          debugPrint("Could not launch $emailUri, email client not found.");
                        }
                      } catch (e) {
                        debugPrint("Error launching email client: $e");
                      }

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Feedback submitted! Thank you for contributing.'),
                            backgroundColor: Color(0xFF10B981),
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.send, color: Colors.white),
                  label: const Text(
                    "Submit Feedback",
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
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
    );
  }

  Widget _buildGECCompassLogoBadge() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 12,
      right: 16,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            decoration: BoxDecoration(
              color: _panelBgColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF8B5CF6), Color(0xFFD946EF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF8B5CF6).withOpacity(0.4),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      )
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.navigation,
                      size: 11,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  "GEC Compass",
                  style: TextStyle(
                    color: _textColor,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _editBuildingDetails(Building building) {
    final nameController = TextEditingController(text: building.name);
    final floorController = TextEditingController(text: building.tags['floor'] ?? '');
    final roomController = TextEditingController(text: building.tags['ref'] ?? '');
    
    String? photoBase64 = building.photoBase64;
    final ImagePicker picker = ImagePicker();
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Container(
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: BoxDecoration(
                color: _panelBgColor,
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
                          color: _textColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      "Edit Location Info",
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _textColor),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Update details or upload a photo for ${building.name}. Changes sync globally.",
                      style: TextStyle(color: _subTextColor, fontSize: 13),
                    ),
                    const SizedBox(height: 20),

                    // Name Input
                    TextField(
                      controller: nameController,
                      style: TextStyle(color: _textColor),
                      decoration: InputDecoration(
                        labelText: "Place Name",
                        labelStyle: TextStyle(color: _subTextColor, fontSize: 14),
                        filled: true,
                        fillColor: _cardBgColor,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 16),

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
                              labelStyle: TextStyle(color: _subTextColor, fontSize: 13),
                              filled: true,
                              fillColor: _cardBgColor,
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
                              labelStyle: TextStyle(color: _subTextColor, fontSize: 13),
                              filled: true,
                              fillColor: _cardBgColor,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Current Photo Preview (if exists)
                    if (photoBase64 != null) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.memory(
                          base64Decode(photoBase64!),
                          height: 150,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Attach/Replace Photo Button
                    SizedBox(
                      width: double.infinity,
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
                        icon: Icon(Icons.camera_alt, color: _textColor),
                        label: Text(
                          photoBase64 == null ? "Attach Photographic Capture" : "Replace Photographic Capture",
                          style: TextStyle(color: _textColor),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          side: BorderSide(color: _borderColor),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Submit Button
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF3B82F6), Color(0xFFEC4899)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFEC4899).withOpacity(0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        onPressed: isSaving ? null : () async {
                          if (nameController.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a name.'), backgroundColor: Colors.redAccent));
                            return;
                          }
                          
                          setModalState(() {
                            isSaving = true;
                          });

                          try {
                            final Map<String, dynamic> updatedTags = Map<String, dynamic>.from(building.tags);
                            if (floorController.text.isNotEmpty) {
                              updatedTags['floor'] = floorController.text.trim();
                            } else {
                              updatedTags.remove('floor');
                            }
                            if (roomController.text.isNotEmpty) {
                              updatedTags['ref'] = roomController.text.trim();
                            } else {
                              updatedTags.remove('ref');
                            }
                            updatedTags['custom'] = true;

                            final updatedBuilding = Building(
                              id: building.id,
                              name: nameController.text.trim(),
                              lat: building.lat,
                              lng: building.lng,
                              photoBase64: photoBase64,
                              tags: updatedTags,
                            );

                            await _dataService.saveCustomBuilding(updatedBuilding);
                            
                            // Re-fetch all buildings
                            await _initData();

                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Place updated globally across all devices!'),
                                  backgroundColor: Color(0xFF10B981),
                                )
                              );
                              // Reselect the updated building to show changes
                              setState(() {
                                final found = _buildings.firstWhere(
                                  (b) => b.id == building.id,
                                  orElse: () => updatedBuilding,
                                );
                                _selectedBuilding = found;
                              });
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update error: $e'), backgroundColor: Colors.redAccent));
                            }
                          } finally {
                            setModalState(() {
                              isSaving = false;
                            });
                          }
                        },
                        icon: isSaving 
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check, color: Colors.white),
                        label: Text(
                          isSaving ? "Saving changes globally..." : "Save Place Changes",
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
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
            child: Container(
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: BoxDecoration(
                color: _panelBgColor,
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
                          color: _textColor.withOpacity(0.2),
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
                          backgroundColor: _cardBgColor,
                          labelStyle: TextStyle(color: !isClassroom ? Colors.white : _subTextColor, fontSize: 12),
                          side: BorderSide(color: !isClassroom ? Colors.transparent : _borderColor),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text("Room/Classroom"),
                          selected: isClassroom,
                          onSelected: (val) => setModalState(() { isClassroom = true; }),
                          selectedColor: const Color(0xFF3B82F6),
                          backgroundColor: _cardBgColor,
                          labelStyle: TextStyle(color: isClassroom ? Colors.white : _subTextColor, fontSize: 12),
                          side: BorderSide(color: isClassroom ? Colors.transparent : _borderColor),
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
                        labelStyle: TextStyle(color: _subTextColor, fontSize: 14),
                        filled: true,
                        fillColor: _cardBgColor,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Parent Building Dropdown (if room)
                    if (isClassroom) ...[
                      DropdownButtonFormField<Building>(
                        decoration: InputDecoration(
                          labelText: "Located In (Building)",
                          labelStyle: TextStyle(color: _subTextColor, fontSize: 14),
                          filled: true,
                          fillColor: _cardBgColor,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                        ),
                        dropdownColor: _panelBgColor,
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
                              labelStyle: TextStyle(color: _subTextColor, fontSize: 13),
                              filled: true,
                              fillColor: _cardBgColor,
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
                              labelStyle: TextStyle(color: _subTextColor, fontSize: 13),
                              filled: true,
                              fillColor: _cardBgColor,
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
                        color: _cardBgColor,
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
                            Text("No coordinate assigned yet", style: TextStyle(color: _subTextColor.withOpacity(0.6), fontSize: 13)),
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
                                : Icon(Icons.gps_fixed, size: 18, color: _textColor),
                              label: Text(isFetchingLocation ? "Acquiring satellites..." : "Use Current GPS Location", style: TextStyle(color: _textColor)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _panelBgColor,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                side: BorderSide(color: _borderColor),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Add Photo Button
                    SizedBox(
                      width: double.infinity,
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
                        icon: Icon(Icons.camera_alt, color: _textColor),
                        label: Text(photoBase64 == null ? "Attach Photographic Capture" : "Photo Attached successfully!", style: TextStyle(color: _textColor)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          side: BorderSide(color: _borderColor),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Submit Button
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF3B82F6), Color(0xFFEC4899)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFEC4899).withOpacity(0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
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
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class CompassDialPainter extends CustomPainter {
  final Color color;
  CompassDialPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Draw cardinal marks
    final cardinals = {'N': 0.0, 'E': 90.0, 'S': 180.0, 'W': 270.0};
    final textPaint = TextPainter(textDirection: TextDirection.ltr);

    for (int i = 0; i < 360; i += 30) {
      final angle = i * pi / 180;
      final isCardinal = i % 90 == 0;
      final tickLength = isCardinal ? 6.0 : 3.0;

      final start = Offset(
        center.dx + (radius - tickLength) * sin(angle),
        center.dy - (radius - tickLength) * cos(angle),
      );
      final end = Offset(
        center.dx + radius * sin(angle),
        center.dy - radius * cos(angle),
      );
      canvas.drawLine(start, end, paint);
    }

    cardinals.forEach((label, deg) {
      final angle = deg * pi / 180;
      final offset = Offset(
        center.dx + (radius - 12) * sin(angle),
        center.dy - (radius - 12) * cos(angle),
      );

      textPaint.text = TextSpan(
        text: label,
        style: TextStyle(
          color: label == 'N' ? Colors.redAccent : color.withOpacity(0.7),
          fontSize: 8,
          fontWeight: FontWeight.bold,
        ),
      );
      textPaint.layout();
      textPaint.paint(
        canvas,
        Offset(offset.dx - textPaint.width / 2, offset.dy - textPaint.height / 2),
      );
    });
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
