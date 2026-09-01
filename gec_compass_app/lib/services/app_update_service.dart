import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class AppUpdateInfo {
  final String version;
  final int buildNumber;
  final String releaseNotes;
  final String downloadUrl;
  final int minRequiredBuildNumber;
  final bool forceUpdate;

  AppUpdateInfo({
    required this.version,
    required this.buildNumber,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.minRequiredBuildNumber,
    required this.forceUpdate,
  });

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    return AppUpdateInfo(
      version: json['version']?.toString() ?? '1.0.0',
      buildNumber: (json['buildNumber'] as num?)?.toInt() ?? 1,
      releaseNotes: json['releaseNotes']?.toString() ?? 'Bug fixes and performance improvements.',
      downloadUrl: json['downloadUrl']?.toString() ?? 'https://github.com/anjo2007/GECMAPS/releases/latest/download/app-release.apk',
      minRequiredBuildNumber: (json['minRequiredBuildNumber'] as num?)?.toInt() ?? 1,
      forceUpdate: json['forceUpdate'] == true,
    );
  }
}

class AppUpdateService {
  // Current installed app build version
  static const int currentBuildNumber = 17;
  static const String currentVersionName = "1.3.4";

  Future<AppUpdateInfo?> checkForUpdate() async {
    // Only check for APK updates when running as native mobile app (Android)
    if (kIsWeb) return null;

    try {
      final List<String> updateUrls = [
        if (kIsWeb)
          '${Uri.base.origin}/version.json'
        else
          'https://gecmaps.vercel.app/api/version',
        'https://gecmaps.vercel.app/version.json',
      ];

      for (final urlStr in updateUrls) {
        try {
          final uri = Uri.parse(urlStr);
          final response = await http.get(uri).timeout(const Duration(seconds: 4));
          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            if (data is Map<String, dynamic>) {
              final info = AppUpdateInfo.fromJson(data);
              if (info.buildNumber > currentBuildNumber) {
                return info;
              }
            }
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint("AppUpdateService check error: $e");
    }
    return null;
  }
}
