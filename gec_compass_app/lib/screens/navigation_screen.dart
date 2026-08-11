import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../models/gate.dart';
import '../services/location_service.dart';
import '../services/path_finder.dart';
import '../widgets/navigation_hud_banner.dart';

class NavigationScreen extends StatefulWidget {
  final LatLng startPosition;
  final LatLng destination;
  final String destinationName;
  final List<LatLng>? initialRoute;

  const NavigationScreen({
    super.key,
    required this.startPosition,
    required this.destination,
    required this.destinationName,
    this.initialRoute,
  });

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  final MapController _mapController = MapController();
  final LocationService _locationService = LocationService();
  StreamSubscription<LatLng>? _positionSubscription;

  // Fix 1: Real-time remaining distance & ETA variables
  double _remainingDistance = 0;
  double _etaSeconds = 0;
  List<LatLng>? _routePolyline; // set this when route is generated

  // Fix 5: Smooth Marker Movement & Camera variables
  Timer? _animationTimer;
  LatLng? _previousPosition;
  LatLng? _currentPosition;
  Map<MarkerId, Marker> _markers = {};
  bool _audioEnabled = true;

  @override
  void initState() {
    super.initState();
    _currentPosition = widget.startPosition;
    _previousPosition = widget.startPosition;
    
    // Set route polyline from initial route or direct line
    _routePolyline = widget.initialRoute ?? [widget.startPosition, widget.destination];
    _updateRemaining(widget.startPosition);

    // Fix 3: Enable realtime high-frequency navigation mode
    _locationService.setMode(LocationMode.navigation);

    // Integration: In the location stream listener, after updating the marker, call _updateRemaining(currentLatLng)
    _positionSubscription = _locationService.positionStream.listen((LatLng newPosition) {
      _updateUserMarker(newPosition);
      _updateRemaining(newPosition);
    });

    _setMarkerPosition(widget.startPosition);
  }

  // Fix 1: Real-time remaining distance & ETA calculation
  void _updateRemaining(LatLng currentPosition) {
    if (_routePolyline == null || _routePolyline!.length < 2) return;

    double minDistance = double.infinity;
    int nearestIndex = 0;
    LatLng nearestPointOnSegment = _routePolyline![0];

    for (int i = 0; i < _routePolyline!.length - 1; i++) {
      LatLng p1 = _routePolyline![i];
      LatLng p2 = _routePolyline![i + 1];
      LatLng projection = _projectPointOnSegment(currentPosition, p1, p2);
      double dist = _distanceBetween(currentPosition, projection);
      if (dist < minDistance) {
        minDistance = dist;
        nearestIndex = i;
        nearestPointOnSegment = projection;
      }
    }

    double lengthFromStartOfSegment = _distanceBetween(
        _routePolyline![nearestIndex], nearestPointOnSegment);
    double lengthToEnd = 0;
    for (int i = nearestIndex + 1; i < _routePolyline!.length - 1; i++) {
      lengthToEnd += _distanceBetween(
          _routePolyline![i], _routePolyline![i + 1]);
    }
    lengthToEnd += _distanceBetween(
        nearestPointOnSegment, _routePolyline![nearestIndex + 1]);

    double remaining = lengthToEnd < 0 ? 0 : lengthToEnd;
    setState(() {
      _remainingDistance = remaining;
      _etaSeconds = remaining / 1.4; // walking speed (m/s)
    });
  }

  LatLng _projectPointOnSegment(LatLng p, LatLng a, LatLng b) {
    double ax = a.latitude, ay = a.longitude;
    double bx = b.latitude, by = b.longitude;
    double px = p.latitude, py = p.longitude;
    double abx = bx - ax, aby = by - ay;
    double apx = px - ax, apy = py - ay;
    double ab2 = abx * abx + aby * aby;
    if (ab2 == 0) return a;
    double t = (apx * abx + apy * aby) / ab2;
    t = t.clamp(0.0, 1.0);
    return LatLng(ax + abx * t, ay + aby * t);
  }

  double _distanceBetween(LatLng a, LatLng b) {
    // Use Geolocator or your own Haversine
    return Geolocator.distanceBetween(
        a.latitude, a.longitude, b.latitude, b.longitude);
  }

  // Fix 5: Smooth Marker Movement & Camera
  void _updateUserMarker(LatLng newPosition) {
    if (_previousPosition == null) {
      _setMarkerPosition(newPosition);
      _previousPosition = newPosition;
      return;
    }
    _animationTimer?.cancel();
    final start = _previousPosition!;
    final end = newPosition;
    const duration = Duration(milliseconds: 500);
    final startTime = DateTime.now();
    _animationTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      final elapsed = DateTime.now().difference(startTime);
      final t = (elapsed.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
      final lat = start.latitude + (end.latitude - start.latitude) * t;
      final lng = start.longitude + (end.longitude - start.longitude) * t;
      _setMarkerPosition(LatLng(lat, lng));
      if (t >= 1.0) timer.cancel();
    });
    _previousPosition = end;
  }

  void _setMarkerPosition(LatLng pos) {
    _currentPosition = pos;
    // Update marker and optionally animate camera
    setState(() {
      _markers[const MarkerId('user')] = Marker(
        markerId: const MarkerId('user'),
        position: pos,
      );
    });
    _mapController.move(pos, _mapController.camera.zoom);
  }

  @override
  void dispose() {
    _animationTimer?.cancel();
    _positionSubscription?.cancel();
    // Fix 3: Reset location service to idle mode when navigating disposed
    _locationService.setMode(LocationMode.idle);
    _locationService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: widget.startPosition,
              initialZoom: 17.5,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.gec.compass',
              ),
              if (_routePolyline != null && _routePolyline!.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePolyline!,
                      strokeWidth: 5.0,
                      color: const Color(0xFF2563EB),
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  if (_currentPosition != null)
                    Marker(
                      point: _currentPosition!,
                      width: 40,
                      height: 40,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 8),
                          ],
                        ),
                        child: const Icon(Icons.navigation, color: Colors.white, size: 20),
                      ),
                    ),
                  Marker(
                    point: widget.destination,
                    width: 40,
                    height: 40,
                    child: const Icon(Icons.location_on, color: Colors.redAccent, size: 36),
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 0,
            right: 0,
            child: NavigationHUDBanner(
              instruction: "Navigating to ${widget.destinationName}",
              nextTurnDistanceMeters: _remainingDistance > 20 ? 20 : _remainingDistance,
              totalDistanceMeters: _remainingDistance,
              isVoiceEnabled: _audioEnabled,
              onToggleVoice: () {
                setState(() {
                  _audioEnabled = !_audioEnabled;
                });
              },
              onEndNavigation: () {
                Navigator.of(context).pop();
              },
            ),
          ),
        ],
      ),
    );
  }
}

class MarkerId {
  final String value;
  const MarkerId(this.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarkerId && runtimeType == other.runtimeType && value == other.value;

  @override
  int get hashCode => value.hashCode;
}
