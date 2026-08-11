import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A modern compact gradient spinner to replace standard CircularProgressIndicator.
class GradientSpinner extends StatefulWidget {
  final double size;
  final double strokeWidth;

  const GradientSpinner({
    super.key,
    this.size = 24.0,
    this.strokeWidth = 3.0,
  });

  @override
  State<GradientSpinner> createState() => _GradientSpinnerState();
}

class _GradientSpinnerState extends State<GradientSpinner> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
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
        return Transform.rotate(
          angle: _controller.value * 2 * math.pi,
          child: CustomPaint(
            size: Size(widget.size, widget.size),
            painter: _GradientSpinnerPainter(strokeWidth: widget.strokeWidth),
          ),
        );
      },
    );
  }
}

class _GradientSpinnerPainter extends CustomPainter {
  final double strokeWidth;

  _GradientSpinnerPainter({required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final paint = Paint()
      ..shader = const SweepGradient(
        colors: [
          Color(0xFF2563EB), // Royal Blue
          Color(0xFF06B6D4), // Cyan
          Color(0xFF8B5CF6), // Purple
          Color(0xFFEC4899), // Pink
          Color(0xFF2563EB),
        ],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      0,
      math.pi * 1.6,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// Full-screen loading overlay with animated gradient ring, pulsing compass logo, and loading text.
class GradientLoadingOverlay extends StatefulWidget {
  final String message;

  const GradientLoadingOverlay({
    super.key,
    this.message = 'Loading GEC Compass...',
  });

  @override
  State<GradientLoadingOverlay> createState() => _GradientLoadingOverlayState();
}

class _GradientLoadingOverlayState extends State<GradientLoadingOverlay>
    with TickerProviderStateMixin {
  late AnimationController _rotationController;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = theme.colorScheme.onSurface;
    final subTextColor = textColor.withValues(alpha: 0.65);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated Gradient Ring & Icon Outer Halo
            AnimatedBuilder(
              animation: Listenable.merge([_rotationController, _pulseController]),
              builder: (context, child) {
                final double rotationAngle = _rotationController.value * 2 * math.pi;
                final double scale = 0.95 + (_pulseController.value * 0.10);
                final double shadowAlpha = 0.25 + (_pulseController.value * 0.20);

                return Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: SweepGradient(
                        transform: GradientRotation(rotationAngle),
                        colors: const [
                          Color(0xFF2563EB), // Royal Blue
                          Color(0xFF06B6D4), // Cyan
                          Color(0xFF8B5CF6), // Purple
                          Color(0xFFEC4899), // Pink
                          Color(0xFF3B82F6), // Bright Blue
                          Color(0xFF2563EB),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF2563EB).withValues(alpha: shadowAlpha),
                          blurRadius: 24,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [Color(0xFF2563EB), Color(0xFF06B6D4)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ).createShader(bounds),
                          child: const Icon(
                            Icons.explore_rounded,
                            size: 52,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 32),
            // Loading Message with Sleek Typography
            Text(
              widget.message,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: textColor,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Interactive Campus Map & Navigation',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: subTextColor,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 24),
            // Mini Gradient Indicator Line
            SizedBox(
              width: 140,
              height: 3.5,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: AnimatedBuilder(
                  animation: _rotationController,
                  builder: (context, child) {
                    return LinearProgressIndicator(
                      backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color.lerp(
                          const Color(0xFF2563EB),
                          const Color(0xFF06B6D4),
                          _rotationController.value,
                        )!,
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
