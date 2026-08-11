import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum TopMessageType {
  success,
  warning,
  error,
  info,
}

class TopMessageOverlay {
  static OverlayEntry? _currentEntry;
  static Timer? _dismissTimer;

  /// Display a high-priority system message overlay on top of ALL layers
  static void show(
    BuildContext context, {
    required String title,
    required String message,
    TopMessageType type = TopMessageType.info,
    Duration duration = const Duration(seconds: 4),
    String? actionLabel,
    VoidCallback? onAction,
    bool persistent = false,
  }) {
    dismiss();

    final overlayState = Overlay.of(context, rootOverlay: true);

    Color accentColor;
    IconData iconData;
    switch (type) {
      case TopMessageType.success:
        accentColor = const Color(0xFF10B981); // Emerald green
        iconData = Icons.check_circle_rounded;
        break;
      case TopMessageType.warning:
        accentColor = const Color(0xFFF59E0B); // Amber / Orange
        iconData = Icons.warning_amber_rounded;
        break;
      case TopMessageType.error:
        accentColor = const Color(0xFFEF4444); // Crimson red
        iconData = Icons.error_outline_rounded;
        break;
      case TopMessageType.info:
        accentColor = const Color(0xFF06B6D4); // Cyan
        iconData = Icons.info_outline_rounded;
        break;
    }

    HapticFeedback.lightImpact();

    _currentEntry = OverlayEntry(
      builder: (context) => _TopToastWidget(
        title: title,
        message: message,
        accentColor: accentColor,
        iconData: iconData,
        actionLabel: actionLabel,
        onAction: () {
          dismiss();
          if (onAction != null) onAction();
        },
        onDismiss: dismiss,
      ),
    );

    overlayState.insert(_currentEntry!);

    if (!persistent) {
      _dismissTimer = Timer(duration, () {
        dismiss();
      });
    }
  }

  /// Display a persistent Location Services Disabled modal on top of ALL layers
  static void showLocationAlert(
    BuildContext context, {
    required VoidCallback onOpenSettings,
    required VoidCallback onReload,
  }) {
    show(
      context,
      title: "📍 Location Services Disabled",
      message: "GPS location services are turned off on your device. Turn on Location to enable real-time 2D map navigation & VPS positioning.",
      type: TopMessageType.error,
      persistent: true,
      actionLabel: "ENABLE & RELOAD",
      onAction: () async {
        onOpenSettings();
        await Future.delayed(const Duration(milliseconds: 600));
        onReload();
      },
    );
  }

  /// Dismiss active top-layer message
  static void dismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _currentEntry?.remove();
    _currentEntry = null;
  }
}

class _TopToastWidget extends StatefulWidget {
  final String title;
  final String message;
  final Color accentColor;
  final IconData iconData;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onDismiss;

  const _TopToastWidget({
    required this.title,
    required this.message,
    required this.accentColor,
    required this.iconData,
    this.actionLabel,
    this.onAction,
    required this.onDismiss,
  });

  @override
  State<_TopToastWidget> createState() => _TopToastWidgetState();
}

class _TopToastWidgetState extends State<_TopToastWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );

    _slideAnimation = Tween<double>(begin: -100.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Positioned(
          top: topInset + 12 + _slideAnimation.value,
          left: 16,
          right: 16,
          child: Material(
            color: Colors.transparent,
            elevation: 20,
            type: MaterialType.transparency,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xEC0F172A), // Dark slate glassmorphism
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: widget.accentColor.withValues(alpha: 0.6),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: widget.accentColor.withValues(alpha: 0.25),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                        const BoxShadow(
                          color: Colors.black87,
                          blurRadius: 20,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: widget.accentColor.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            widget.iconData,
                            color: widget.accentColor,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.message,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontSize: 12,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (widget.actionLabel != null) ...[
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: widget.onAction,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: widget.accentColor,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Text(
                              widget.actionLabel!,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 18),
                          onPressed: widget.onDismiss,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
