import 'package:flutter/material.dart';

class NavigationHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback? onSearchPressed;
  final VoidCallback? onFilterPressed;
  final bool isNavigating;
  final VoidCallback? onCancelNavigation;

  const NavigationHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.onSearchPressed,
    this.onFilterPressed,
    this.isNavigating = false,
    this.onCancelNavigation,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = theme.colorScheme.onSurface;
    final subTextColor = textColor.withValues(alpha: 0.65);
    final borderColor = isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.cardColor.withValues(alpha: isDark ? 0.88 : 0.95),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.08),
            blurRadius: 16,
            spreadRadius: -2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isNavigating
                  ? theme.colorScheme.primary.withValues(alpha: 0.15)
                  : theme.colorScheme.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isNavigating ? Icons.navigation_rounded : Icons.explore_rounded,
              color: theme.colorScheme.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: textColor,
                    letterSpacing: 0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: subTextColor,
                    fontSize: 12.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (isNavigating)
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.redAccent),
              onPressed: onCancelNavigation,
              tooltip: 'End Navigation',
            )
          else ...[
            if (onSearchPressed != null)
              IconButton(
                icon: Icon(Icons.search_rounded, color: subTextColor),
                onPressed: onSearchPressed,
                tooltip: 'Search Places',
              ),
            if (onFilterPressed != null)
              IconButton(
                icon: Icon(Icons.filter_list_rounded, color: subTextColor),
                onPressed: onFilterPressed,
                tooltip: 'Filter Categories',
              ),
          ],
        ],
      ),
    );
  }
}
