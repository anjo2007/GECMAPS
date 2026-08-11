import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/building.dart';

class PlaceDetailBottomSheet extends StatelessWidget {
  final Building building;
  final VoidCallback onNavigatePressed;
  final VoidCallback? onClosePressed;

  const PlaceDetailBottomSheet({
    super.key,
    required this.building,
    required this.onNavigatePressed,
    this.onClosePressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = theme.colorScheme.onSurface;
    final subTextColor = textColor.withValues(alpha: 0.65);
    final photo = building.photoBase64;
    final displayUrl = building.photoUrl ?? building.vpsBoardPhotoUrl ?? building.tags['image'] as String? ?? building.tags['photoUrl'] as String?;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
            blurRadius: 24,
            spreadRadius: 0,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4.5,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: textColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  building.name,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: textColor,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.close_rounded, color: subTextColor),
                onPressed: onClosePressed ?? () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (building.tags.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: building.tags.entries.map((e) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.2)),
                  ),
                  child: Text(
                    '${e.key}: ${e.value}',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                );
              }).toList(),
            ),
          if (displayUrl != null && displayUrl.isNotEmpty) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                displayUrl,
                height: 170,
                width: double.infinity,
                fit: BoxFit.cover,
                cacheWidth: 800,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    height: 170,
                    width: double.infinity,
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  );
                },
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ] else if (photo != null && photo.isNotEmpty) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: (() {
                final raw = photo.trim();
                if (raw.startsWith('http://') || raw.startsWith('https://')) {
                  return Image.network(
                    raw,
                    height: 170,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    cacheWidth: 800,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  );
                }
                return Image.memory(
                  base64Decode(raw.contains(',') ? raw.split(',').last : raw),
                  height: 170,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  cacheWidth: 800,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                );
              })(),
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: Colors.white,
                elevation: 4,
                shadowColor: theme.colorScheme.primary.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: onNavigatePressed,
              icon: const Icon(Icons.directions_walk_rounded, size: 22),
              label: const Text(
                'Navigate Here',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.3),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
