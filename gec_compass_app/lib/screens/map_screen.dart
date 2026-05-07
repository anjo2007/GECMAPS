import 'dart:math';
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../models/building.dart';
import '../services/data_service.dart';
import '../services/pdr_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  final DataService _dataService = DataService();
  final PDRService _pdrService = PDRService();

  List<Building> _buildings = [];
  Building? _selectedBuilding;
  bool _isNavigating = false;
  int _stepCount = 0;
  List<LatLng> _pdrTrail = [];

  LatLng? _currentPosition;
  bool _isLoading = true;
  String? _loadError;

  // GEC Thrissur Center
  final LatLng _campusCenter = const LatLng(10.555761, 76.224317);

  @override
  void initState() {
    super.initState();
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
    _pdrService.stopPDR();
    super.dispose();
  }

  Future<void> _initData() async {
    try {
      final buildings = await _dataService.loadBuildings();

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
                timeLimit: Duration(seconds: 10),
              ),
            );
            userPos = LatLng(pos.latitude, pos.longitude);
          }
        }
      } catch (e) {
        debugPrint("Location error (non-fatal): $e");
        // On web or when location fails, default to campus center
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

  /// Calculate distance in meters between two LatLng points (Haversine).
  double _distanceMeters(LatLng a, LatLng b) {
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
      }
      FocusScope.of(context).unfocus();
    });

    _mapController.move(LatLng(building.lat, building.lng), 18.0);
    _showBuildingDetails(building);
  }

  void _startNavigation() {
    final startPos = _currentPosition ?? _campusCenter;
    _pdrService.startPDR(startPos);
    setState(() {
      _isNavigating = true;
      _stepCount = 0;
      _pdrTrail = [startPos];
    });

    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Web Demo Mode: Simulating PDR steps. Use mobile for real sensors.'),
          duration: Duration(seconds: 3),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Navigation started! Walk toward your destination.')),
      );
    }
  }

  void _stopNavigation() {
    _pdrService.stopPDR();
    setState(() {
      _isNavigating = false;
      _pdrTrail.clear();
    });
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
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 20,
              spreadRadius: 5,
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
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              building.name,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.location_on, color: Colors.blueAccent, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "${building.lat.toStringAsFixed(5)}, ${building.lng.toStringAsFixed(5)}",
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              ],
            ),
            if (dist != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.straighten, color: Colors.orangeAccent, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    _formatDistance(dist),
                    style: const TextStyle(
                      color: Colors.orangeAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Text(" away", style: TextStyle(color: Colors.white54)),
                ],
              ),
            ],
            if (building.tags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: building.tags.entries
                    .where((e) => ['amenity', 'building', 'tourism', 'cuisine'].contains(e.key))
                    .take(3)
                    .map((e) => Chip(
                          label: Text(
                            "${e.key}: ${e.value}",
                            style: const TextStyle(fontSize: 11, color: Colors.white70),
                          ),
                          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
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
                  "Navigate Here",
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                initialZoom: 16.5,
                maxZoom: 22.0,
                onPositionChanged: (pos, hasGesture) {
                  if (hasGesture) FocusScope.of(context).unfocus();
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.gec_compass_app',
                ),
                // Building markers
                MarkerLayer(
                  markers: _buildings.map((b) => Marker(
                    point: LatLng(b.lat, b.lng),
                    width: 40,
                    height: 40,
                    child: GestureDetector(
                      onTap: () => _selectBuilding(b),
                      child: Icon(
                        _getMarkerIcon(b),
                        color: _selectedBuilding?.id == b.id
                            ? Colors.greenAccent
                            : _getMarkerColor(b),
                        size: _selectedBuilding?.id == b.id ? 40 : 30,
                      ),
                    ),
                  )).toList(),
                ),
                // User position marker
                if (_currentPosition != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _currentPosition!,
                        width: 50,
                        height: 50,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.blue.withOpacity(0.3),
                            border: Border.all(color: Colors.blueAccent, width: 2),
                          ),
                          child: const Center(
                            child: Icon(Icons.my_location, color: Colors.blueAccent, size: 22),
                          ),
                        ),
                      )
                    ],
                  ),
                // PDR trail
                if (_isNavigating && _pdrTrail.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _pdrTrail,
                        color: Colors.greenAccent,
                        strokeWidth: 3.0,
                      ),
                    ],
                  ),
                // Direct line to destination
                if (_isNavigating &&
                    _currentPosition != null &&
                    _selectedBuilding != null)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: [
                          _currentPosition!,
                          LatLng(_selectedBuilding!.lat, _selectedBuilding!.lng),
                        ],
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                        strokeWidth: 3.0,
                      ),
                    ],
                  ),
              ],
            ),

          // Glassmorphism Search Bar
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            right: 16,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white12),
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
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: 'Search buildings, labs, cafes...',
                          hintStyle: TextStyle(color: Colors.white54),
                          prefixIcon: Icon(Icons.search, color: Colors.white54),
                          border: InputBorder.none,
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                              color: Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black.withOpacity(0.3),
                                    blurRadius: 10)
                              ],
                            ),
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: options.length,
                              itemBuilder: (BuildContext context, int index) {
                                final Building option =
                                    options.elementAt(index);
                                return ListTile(
                                  title: Text(option.name,
                                      style:
                                          const TextStyle(color: Colors.white)),
                                  leading: Icon(_getMarkerIcon(option),
                                      color: Colors.white54),
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
          ),

          // Recenter Button
          Positioned(
            bottom: 32,
            right: 16,
            child: FloatingActionButton(
              heroTag: 'recenter_btn',
              backgroundColor: Theme.of(context).colorScheme.surface,
              child: const Icon(Icons.my_location, color: Colors.blueAccent),
              onPressed: () {
                if (_currentPosition != null) {
                  _mapController.move(_currentPosition!, 18.0);
                } else {
                  _mapController.move(_campusCenter, 16.0);
                }
              },
            ),
          ),

          // Feedback Button
          Positioned(
            bottom: 32,
            left: 16,
            child: FloatingActionButton.extended(
              heroTag: 'feedback_btn',
              backgroundColor: Theme.of(context).colorScheme.secondary,
              icon: const Icon(Icons.feedback_outlined, color: Colors.white),
              label: const Text('Feedback',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
              onPressed: _showFeedbackModal,
            ),
          ),

          // Navigation UI Overlay
          if (_isNavigating)
            Positioned(
              top: MediaQuery.of(context).padding.top + 80,
              left: 16,
              right: 16,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _selectedBuilding != null
                                        ? "→ ${_selectedBuilding!.name}"
                                        : "Navigating",
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Text(
                                        "$_stepCount",
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 28,
                                            fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(width: 4),
                                      const Text("steps",
                                          style: TextStyle(
                                              color: Colors.white70,
                                              fontSize: 14)),
                                      const SizedBox(width: 16),
                                      Text(
                                        _formatDistance(
                                            _stepCount * 0.7), // step * stride
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton.icon(
                              onPressed: _stopNavigation,
                              icon: const Icon(Icons.stop,
                                  color: Colors.redAccent, size: 20),
                              label: const Text("Stop",
                                  style: TextStyle(color: Colors.redAccent)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Theme.of(context).cardColor,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (kIsWeb) ...[
                          const SizedBox(height: 8),
                          const Text(
                            "🌐 Web demo mode — simulated steps",
                            style: TextStyle(color: Colors.white38, fontSize: 11),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Returns an appropriate icon based on the building's tags.
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

  /// Returns a color for the marker based on its type.
  Color _getMarkerColor(Building b) {
    final amenity = b.tags['amenity'] as String?;
    final buildingType = b.tags['building'] as String?;

    if (amenity == 'restaurant' || amenity == 'cafe' || amenity == 'food_court') {
      return Colors.orangeAccent;
    }
    if (buildingType == 'college') return Colors.cyanAccent;
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
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
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
                "Community Feedback",
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
              ),
              const SizedBox(height: 8),
              const Text(
                "Suggest a missing building, report an inaccurate path, or share your thoughts.",
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: feedbackController,
                maxLines: 4,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: "Enter your feedback here...",
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Theme.of(context).scaffoldBackgroundColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
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
                            content: Text(
                                'Feedback submitted! Thank you for contributing.')),
                      );
                    }
                  },
                  icon: const Icon(Icons.send, color: Colors.white),
                  label: const Text(
                    "Submit",
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
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
}
