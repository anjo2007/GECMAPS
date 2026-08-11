import 'package:flutter/material.dart';

class NavigationHUDBanner extends StatelessWidget {
  final String instruction;
  final double nextTurnDistanceMeters;
  final double totalDistanceMeters;
  final bool isVoiceEnabled;
  final VoidCallback onToggleVoice;
  final VoidCallback onEndNavigation;

  const NavigationHUDBanner({
    super.key,
    required this.instruction,
    required this.nextTurnDistanceMeters,
    required this.totalDistanceMeters,
    required this.isVoiceEnabled,
    required this.onToggleVoice,
    required this.onEndNavigation,
  });

  IconData _getManeuverIcon(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('left')) {
      return lower.contains('sharp') ? Icons.turn_sharp_left : Icons.turn_left;
    } else if (lower.contains('right')) {
      return lower.contains('sharp') ? Icons.turn_sharp_right : Icons.turn_right;
    } else if (lower.contains('arrive')) {
      return Icons.place;
    } else {
      return Icons.navigation;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = theme.colorScheme.onSurface;
    final subTextColor = textColor.withValues(alpha: 0.7);
    final etaMinutes = (totalDistanceMeters / 80).ceil(); // ~80m/min walking pace

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor.withValues(alpha: isDark ? 0.92 : 0.96),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: isDark ? 0.3 : 0.2), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.1),
            blurRadius: 20,
            spreadRadius: -2,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _getManeuverIcon(instruction),
                  color: theme.colorScheme.primary,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      instruction,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: textColor,
                        letterSpacing: 0.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${nextTurnDistanceMeters.round()} m ahead',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  isVoiceEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                  color: isVoiceEnabled ? const Color(0xFF10B981) : subTextColor.withValues(alpha: 0.5),
                ),
                onPressed: onToggleVoice,
                tooltip: isVoiceEnabled ? 'Mute Voice Guidance' : 'Enable Voice Guidance',
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.redAccent),
                onPressed: onEndNavigation,
                tooltip: 'End Navigation',
              ),
            ],
          ),
          Divider(color: textColor.withValues(alpha: 0.1), height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.directions_walk_rounded, size: 18, color: subTextColor),
                  const SizedBox(width: 6),
                  Text(
                    '${(totalDistanceMeters / 1000).toStringAsFixed(2)} km remaining',
                    style: TextStyle(fontSize: 13, color: textColor, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              Row(
                children: [
                  Icon(Icons.access_time_rounded, size: 18, color: subTextColor),
                  const SizedBox(width: 6),
                  Text(
                    '~$etaMinutes min walk',
                    style: TextStyle(fontSize: 13, color: textColor, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
