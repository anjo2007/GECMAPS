import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import '../services/place_detection_service.dart';

class FloorMappingScreen extends StatefulWidget {
  final String placeName;
  const FloorMappingScreen({super.key, required this.placeName});

  @override
  State<FloorMappingScreen> createState() => _FloorMappingScreenState();
}

class _FloorMappingScreenState extends State<FloorMappingScreen> {
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  
  // Simulation variables
  double _mappingProgress = 0.0;
  int _anchorCount = 0;
  String _currentAction = "Initializing spatial engine...";
  Timer? _simulationTimer;
  
  // SLAM feature points for visual effect
  final List<Point3D> _featurePoints = [];
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _startMappingSimulation();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      
      final backCamera = cameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();
      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
      }
    } catch (e) {
      debugPrint("Error initializing camera: $e");
    }
  }

  void _startMappingSimulation() async {
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 150), (timer) {
      if (!mounted) return;
      
      setState(() {
        if (_mappingProgress < 1.0) {
          _mappingProgress += 0.02;
          if (_mappingProgress > 1.0) _mappingProgress = 1.0;
          
          // Generate new simulated feature points as camera moves
          if (_random.nextDouble() > 0.3 && _featurePoints.length < 60) {
            _featurePoints.add(Point3D(
              _random.nextDouble() * 300 - 150,
              _random.nextDouble() * 500 - 250,
              _random.nextDouble() * 10 + 2, // Z depth
              Color.fromARGB(
                200, 
                _random.nextInt(100) + 155, 
                _random.nextInt(100) + 155, 
                0
              ),
            ));
          }
          
          // Update simulated status action text
          if (_mappingProgress < 0.25) {
            _currentAction = "Scanning floor boundaries & corners...";
          } else if (_mappingProgress < 0.50) {
            _currentAction = "Extracting visual anchor points...";
          } else if (_mappingProgress < 0.75) {
            _currentAction = "Sampling Wi-Fi fingerprint...";
          } else if (_mappingProgress < 0.95) {
            _currentAction = "Optimizing spatial mesh...";
          } else {
            _currentAction = "Floor map generated! Ready to save.";
          }
        }
      });
    });

    // Actually scan Wi-Fi in the background during the visual "mapping"
    final service = PlaceDetectionService();
    final env = await service.scanCurrentWifiEnvironment();
    if (mounted) {
      setState(() {
        _anchorCount = env.length; // use wifi count as "anchors"
      });
    }
  }

  void _saveFloorMap() async {
    HapticFeedback.mediumImpact();
    
    // Call the actual mapping service
    final floorId = widget.placeName.toLowerCase().replaceAll(' ', '_');
    await PlaceDetectionService().mapFloor(floorId, widget.placeName);
    
    // Return the mapping metadata to the calling screen
    final mapData = {
      'mapped': 'yes',
      'anchors': _anchorCount.toString(),
      'progress': '100%',
      'signature': 'vps_mesh_${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}'
    };
    if (mounted) {
      Navigator.pop(context, mapData);
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _simulationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraInitialized) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: const SizedBox.shrink(),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Camera Feed
          CameraPreview(_cameraController!),

          // 2. Custom Painter for 3D SLAM Mesh simulation
          Positioned.fill(
            child: CustomPaint(
              painter: SLAMPainter(
                points: _featurePoints,
                progress: _mappingProgress,
              ),
            ),
          ),

          // 3. HUD Stats top panel
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "VPS MAPPING: ${widget.placeName}",
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _mappingProgress >= 1.0 ? Colors.green.withValues(alpha: 0.3) : Colors.blue.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _mappingProgress >= 1.0 ? Colors.green : Colors.blue,
                            width: 1
                          ),
                        ),
                        child: Text(
                          _mappingProgress >= 1.0 ? "Mesh Locked" : "Mapping...",
                          style: TextStyle(
                            color: _mappingProgress >= 1.0 ? Colors.greenAccent : Colors.blueAccent, 
                            fontSize: 10, 
                            fontWeight: FontWeight.bold
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Spatial Anchors: $_anchorCount", style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      Text("Quality: ${(min(_anchorCount * 2, 100))}%", style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: _mappingProgress,
                    backgroundColor: Colors.white10,
                    valueColor: AlwaysStoppedAnimation<Color>(_mappingProgress >= 1.0 ? Colors.greenAccent : Colors.blueAccent),
                  ),
                ],
              ),
            ),
          ),

          // 4. Instructions in the center bottom
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 100,
            left: 24,
            right: 24,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white24),
              ),
              child: Text(
                _currentAction,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
          ),

          // 5. Cancel and Save Buttons
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 24,
            left: 24,
            right: 24,
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context, null);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey.withValues(alpha: 0.3),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    child: const Text("Cancel", style: TextStyle(color: Colors.white)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _mappingProgress >= 1.0 ? _saveFloorMap : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _mappingProgress >= 1.0 ? const Color(0xFF10B981) : Colors.grey.withValues(alpha: 0.2),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    child: const Text(
                      "Save Map",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class Point3D {
  final double x;
  final double y;
  final double z;
  final Color color;

  Point3D(this.x, this.y, this.z, this.color);
}

class SLAMPainter extends CustomPainter {
  final List<Point3D> points;
  final double progress;

  SLAMPainter({required this.points, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final double centerX = size.width / 2;
    final double centerY = size.height / 2;
    
    // Paint for features
    final Paint paint = Paint()..style = PaintingStyle.fill;
    
    // Draw SLAM grid mesh
    final Paint linePaint = Paint()
      ..color = Colors.cyan.withValues(alpha: 0.15 * progress)
      ..strokeWidth = 1.0;
      
    // Draw simulated mesh lines between nearby points
    for (int i = 0; i < points.length; i++) {
      final p1 = points[i];
      // Convert to 2D
      final double sx1 = centerX + (p1.x / p1.z) * 1.5;
      final double sy1 = centerY + (p1.y / p1.z) * 1.5;
      
      if (sx1 >= 0 && sx1 <= size.width && sy1 >= 0 && sy1 <= size.height) {
        paint.color = p1.color;
        canvas.drawCircle(Offset(sx1, sy1), (4 / p1.z).clamp(1.0, 4.0), paint);
        
        // Connect to neighbors to look like a mesh
        for (int j = i + 1; j < min(i + 5, points.length); j++) {
          final p2 = points[j];
          final double sx2 = centerX + (p2.x / p2.z) * 1.5;
          final double sy2 = centerY + (p2.y / p2.z) * 1.5;
          
          double dx = sx1 - sx2;
          double dy = sy1 - sy2;
          double db = sqrt(dx*dx + dy*dy);
          
          if (db < 80) {
            canvas.drawLine(Offset(sx1, sy1), Offset(sx2, sy2), linePaint);
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant SLAMPainter oldDelegate) {
    return oldDelegate.points.length != points.length || oldDelegate.progress != progress;
  }
}
