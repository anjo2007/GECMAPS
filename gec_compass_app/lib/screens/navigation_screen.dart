import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../services/location_service.dart';
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

  double _remainingDistance = 0;
  List<LatLng>? _routePolyline;

  Timer? _animationTimer;
  LatLng? _previousPosition;
  LatLng? _currentPosition;
  bool _audioEnabled = true;

  @override
  void initState() {
    super.initState();
    _currentPosition = widget.startPosition;
    _previousPosition = widget.startPosition;

    _routePolyline = widget.initialRoute ?? [widget.startPosition, widget.destination];
    _updateRemaining(widget.startPosition);

    _locationService.setMode(LocationMode.navigation);

    _positionSubscription = _locationService.positionStream.listen((LatLng newPosition) {
      _updateUserMarker(newPosition);
      _updateRemaining(newPosition);
    });
  }

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
    return Geolocator.distanceBetween(
        a.latitude, a.longitude, b.latitude, b.longitude);
  }

  void _updateUserMarker(LatLng newPosition) {
    if (_previousPosition == null) {
      setState(() { _currentPosition = newPosition; });
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
      if (mounted) {
        setState(() { _currentPosition = LatLng(lat, lng); });
      }
      if (t >= 1.0) timer.cancel();
    });
    _previousPosition = end;
  }

  @override
  void dispose() {
    _animationTimer?.cancel();
    _positionSubscription?.cancel();
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
