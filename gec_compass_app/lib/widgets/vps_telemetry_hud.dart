import 'dart:math';
import 'package:flutter/material.dart';

class VPSTelemetryHUD extends StatelessWidget {
  final double pitch; // radians
  final double roll;  // radians
  final int slamFeatureCount;
  final double confidenceScore; // 0.0 to 1.0
  final String statusText;
  final int currentFloor;

  const VPSTelemetryHUD({
    super.key,
    required this.pitch,
    required this.roll,
    required this.slamFeatureCount,
    required this.confidenceScore,
    required this.statusText,
    required this.currentFloor,
  });

  @override
  Widget build(BuildContext context) {
    final confidencePct = (confidenceScore * 100).round();
    Color badgeColor = Colors.redAccent;
    if (confidenceScore >= 0.8) {
      badgeColor = Colors.greenAccent;
    } else if (confidenceScore >= 0.5) {
      badgeColor = Colors.orangeAccent;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // Artificial Horizon Pitch/Roll Gauge Indicator
              CustomPaint(
                size: const Size(36, 36),
                painter: _ArtificialHorizonPainter(pitch: pitch, roll: roll),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      statusText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Floor $currentFloor  •  Pitch ${(pitch * 180 / pi).toStringAsFixed(1)}°  •  Roll ${(roll * 180 / pi).toStringAsFixed(1)}°',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              // VPS Confidence Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: badgeColor),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.radar, size: 14, color: badgeColor),
                    const SizedBox(width: 4),
                    Text(
                      '$confidencePct%',
                      style: TextStyle(
                        color: badgeColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'SLAM Features: $slamFeatureCount points',
                style: const TextStyle(color: Colors.cyanAccent, fontSize: 11),
              ),
              const Text(
                'VPS Relocalizer v2.0',
                style: TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ArtificialHorizonPainter extends CustomPainter {
  final double pitch;
  final double roll;

  _ArtificialHorizonPainter({required this.pitch, required this.roll});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final borderPaint = Paint()
      ..color = Colors.cyanAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final linePaint = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 2;

    canvas.drawCircle(center, radius, borderPaint);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(roll);

    final pitchOffset = (pitch * 20).clamp(-radius + 4, radius - 4);
    canvas.drawLine(
      Offset(-radius + 6, pitchOffset),
      Offset(radius - 6, pitchOffset),
      linePaint,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ArtificialHorizonPainter oldDelegate) {
    return oldDelegate.pitch != pitch || oldDelegate.roll != roll;
  }
}
