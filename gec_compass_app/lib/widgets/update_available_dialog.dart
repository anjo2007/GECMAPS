import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/app_update_service.dart';

class UpdateAvailableDialog extends StatelessWidget {
  final AppUpdateInfo updateInfo;

  const UpdateAvailableDialog({
    super.key,
    required this.updateInfo,
  });

  static Future<void> show(BuildContext context, AppUpdateInfo info) async {
    return showDialog(
      context: context,
      barrierDismissible: !info.forceUpdate,
      builder: (context) => UpdateAvailableDialog(updateInfo: info),
    );
  }

  Future<void> _downloadApk(BuildContext context) async {
    final Uri uri = Uri.parse(updateInfo.downloadUrl);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error opening download link: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bgColor = isDark ? const Color(0xFF0F172A) : Colors.white;
    final Color textColor = isDark ? Colors.white : const Color(0xFF0F172A);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: bgColor.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: const Color(0xFF6366F1).withValues(alpha: 0.4),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                  blurRadius: 24,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header Icon
                Center(
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6366F1).withValues(alpha: 0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.system_update_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Title
                Text(
                  "New Update Available! 🚀",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),

                // Version Badge
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      "Version ${updateInfo.version} (Build ${updateInfo.buildNumber})",
                      style: const TextStyle(
                        color: Color(0xFF6366F1),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Release Notes Card
                if (updateInfo.releaseNotes.isNotEmpty) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "What's New:",
                      style: TextStyle(
                        color: textColor.withValues(alpha: 0.8),
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 120),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        updateInfo.releaseNotes,
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.85),
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // Download Button
                ElevatedButton.icon(
                  onPressed: () {
                    _downloadApk(context);
                    if (!updateInfo.forceUpdate) {
                      Navigator.of(context).pop();
                    }
                  },
                  icon: const Icon(Icons.download_rounded, size: 20),
                  label: const Text(
                    "Download Update (.apk)",
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 4,
                  ),
                ),

                // Dismiss / Later Button
                if (!updateInfo.forceUpdate) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      "Later",
                      style: TextStyle(
                        color: textColor.withValues(alpha: 0.6),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
