import 'package:flutter/material.dart';

class VPSScannerReticle extends StatefulWidget {
  final String label;

  const VPSScannerReticle({
    super.key,
    this.label = 'Align Room Sign or QR Code in Frame',
  });

  @override
  State<VPSScannerReticle> createState() => _VPSScannerReticleState();
}

class _VPSScannerReticleState extends State<VPSScannerReticle> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Outer Frame Bracket Box
            Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.cyanAccent.withValues(alpha: 0.4 + 0.4 * _controller.value),
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            // Laser Scanning Beam Line
            Positioned(
              top: 30 + 200 * _controller.value,
              child: Container(
                width: 240,
                height: 2,
                decoration: BoxDecoration(
                  color: Colors.cyanAccent,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.cyanAccent.withValues(alpha: 0.8),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
            // Subtitle Guidance Badge
            Positioned(
              bottom: -40,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.qr_code_scanner, color: Colors.cyanAccent, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      widget.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
