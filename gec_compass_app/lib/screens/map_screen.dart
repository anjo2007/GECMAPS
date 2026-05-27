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
import '../models/building.dart';
import '../services/data_service.dart';
import '../services/pdr_service.dart';
import '../services/routing_service.dart';

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
    };

    _pdrService.onStepDetected = (int count) {
      if (!mounted) return;
      setState(() {
        _stepCount = count;
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

  void _startNavigation() {
    if (_selectedBuilding == null) return;
    
    final startPos = _currentPosition ?? _campusCenter;
    final endPos = LatLng(_selectedBuilding!.lat, _selectedBuilding!.lng);

    // Get Dijkstra shortest-path along campus roads
    final path = _routingService.getFullRoute(startPos, endPos);
    final instructions = _routingService.getRouteInstructions(path);

    _pdrService.startPDR(startPos);
    setState(() {
      _isNavigating = true;
      _stepCount = 0;
      _pdrTrail = [startPos];
      _routingPath = path;
      _routeInstructions = instructions;
      _currentInstructionIndex = 0;
      _simulatedRouteIndex = 0;
    });

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
    setState(() {
      _isNavigating = false;
      _pdrTrail.clear();
      _routingPath.clear();
      _routeInstructions.clear();
      _currentInstructionIndex = 0;
      _simulatedRouteIndex = 0;
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
    } else {
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

  // Filter buildings on the map based on the active category chip
  List<Building> _getFilteredBuildings() {
    if (_selectedCategory == 'All') {
      return _buildings;
    }
    return _buildings.where((b) {
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
          color: const Color(0xFF0F172A),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.6),
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
                  color: Colors.white24,
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
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
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
                    style: const TextStyle(color: Colors.white60, fontSize: 13),
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
                  const Text(" away along paths", style: TextStyle(color: Colors.white54)),
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
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withOpacity(0.05)),
                          ),
                          child: Text(
                            "${e.key}: ${e.value}",
                            style: const TextStyle(fontSize: 11, color: Colors.white70),
                          ),
                        ))
                    .toList(),
              ),
            ],
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
                // Dark-themed CartoDB Tiles
                TileLayer(
                  urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
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
                          color: const Color(0xFF0F172A).withOpacity(0.75),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.white.withOpacity(0.12)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black38,
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
                              style: const TextStyle(color: Colors.white, fontSize: 15),
                              decoration: InputDecoration(
                                hintText: 'Search departments, labs, cafes...',
                                hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                                prefixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.5)),
                                suffixIcon: textEditingController.text.isNotEmpty 
                                    ? IconButton(
                                        icon: const Icon(Icons.clear, color: Colors.white54, size: 18),
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
                                    color: const Color(0xFF0F172A),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                                    boxShadow: [
                                      BoxShadow(
                                          color: Colors.black54,
                                          blurRadius: 15,
                                          offset: const Offset(0, 5))
                                    ],
                                  ),
                                  child: ListView.separated(
                                    padding: EdgeInsets.zero,
                                    shrinkWrap: true,
                                    itemCount: options.length,
                                    separatorBuilder: (c, i) => Divider(color: Colors.white.withOpacity(0.06), height: 1),
                                    itemBuilder: (BuildContext context, int index) {
                                      final Building option = options.elementAt(index);
                                      return ListTile(
                                        title: Text(option.name,
                                            style: const TextStyle(color: Colors.white, fontSize: 14)),
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
                              color: isSelected ? Colors.white : Colors.white70,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              fontSize: 13,
                            ),
                            selectedColor: const Color(0xFF3B82F6),
                            backgroundColor: const Color(0xFF1E293B).withOpacity(0.8),
                            side: BorderSide(color: Colors.white.withOpacity(isSelected ? 0.0 : 0.08)),
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
                    backgroundColor: const Color(0xFF1E293B),
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
        
        // Bottom Navigation Status Bar
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.6), blurRadius: 25, offset: const Offset(0, -6)),
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
                          Text(_formatDistance(dist), style: const TextStyle(color: Colors.white70, fontSize: 18)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.directions_walk, color: Colors.white54, size: 16),
                          const SizedBox(width: 4),
                          Text("$_stepCount steps taken", style: const TextStyle(color: Colors.white54, fontSize: 14)),
                        ],
                      ),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: _stopNavigation,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent.withOpacity(0.85),
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
            color: const Color(0xFF0F172A),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
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
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                "Feedback & Reports",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              const Text(
                "Suggest a missing building, report an inaccurate path, or share feature requests.",
                style: TextStyle(color: Colors.white60),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: feedbackController,
                maxLines: 4,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: "Enter your feedback or report here...",
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
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
                  onPressed: () {
                    if (feedbackController.text.trim().isNotEmpty) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Feedback submitted! Thank you for contributing.'),
                          backgroundColor: Color(0xFF10B981),
                        ),
                      );
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
                color: const Color(0xFF0F172A),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
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
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      "Add a Place",
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      "Contribute a missing classroom, laboratory, or office to the cloud database.",
                      style: TextStyle(color: Colors.white60, fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                    
                    // Choice of type
                    Row(
                      children: [
                        const Text("Category:", style: TextStyle(color: Colors.white, fontSize: 14)),
                        const SizedBox(width: 16),
                        ChoiceChip(
                          label: const Text("Building/Lab"),
                          selected: !isClassroom,
                          onSelected: (val) => setModalState(() { isClassroom = false; }),
                          selectedColor: const Color(0xFF3B82F6),
                          backgroundColor: const Color(0xFF1E293B),
                          labelStyle: TextStyle(color: !isClassroom ? Colors.white : Colors.white70, fontSize: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text("Room/Classroom"),
                          selected: isClassroom,
                          onSelected: (val) => setModalState(() { isClassroom = true; }),
                          selectedColor: const Color(0xFF3B82F6),
                          backgroundColor: const Color(0xFF1E293B),
                          labelStyle: TextStyle(color: isClassroom ? Colors.white : Colors.white70, fontSize: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Name Input
                    TextField(
                      controller: nameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: "Place Name (e.g. Embedded Systems Lab)",
                        labelStyle: const TextStyle(color: Colors.white54, fontSize: 14),
                        filled: true,
                        fillColor: const Color(0xFF1E293B),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Parent Building Dropdown (if room)
                    if (isClassroom) ...[
                      DropdownButtonFormField<Building>(
                        decoration: InputDecoration(
                          labelText: "Located In (Building)",
                          labelStyle: const TextStyle(color: Colors.white54, fontSize: 14),
                          filled: true,
                          fillColor: const Color(0xFF1E293B),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                        ),
                        dropdownColor: const Color(0xFF0F172A),
                        initialValue: selectedParent,
                        items: _buildings.where((b) => b.tags['building'] == 'college' || !b.tags.containsKey('room')).map((b) {
                          return DropdownMenuItem(value: b, child: Text(b.name, style: const TextStyle(color: Colors.white, fontSize: 14)));
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
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: "Floor (e.g., 0, 1, 2)",
                              labelStyle: const TextStyle(color: Colors.white54, fontSize: 13),
                              filled: true,
                              fillColor: const Color(0xFF1E293B),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: roomController,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: "Room ID / Number",
                              labelStyle: const TextStyle(color: Colors.white54, fontSize: 13),
                              filled: true,
                              fillColor: const Color(0xFF1E293B),
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
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white.withOpacity(0.04)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Geographical Coordinates", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
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
                            const Text("No coordinate assigned yet", style: TextStyle(color: Colors.white38, fontSize: 13)),
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
                                backgroundColor: const Color(0xFF0F172A),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                        icon: const Icon(Icons.camera_alt),
                        label: Text(photoBase64 == null ? "Attach Photographic Capture" : "Photo Attached successfully!"),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          side: BorderSide(color: Colors.white.withOpacity(0.12)),
                        ),
                      ),
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
          );
        },
      ),
    );
  }
}
