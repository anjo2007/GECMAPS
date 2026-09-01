import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/map_screen.dart';

import 'services/data_service.dart';
import 'services/routing_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb) {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));
  }

  // Pre-warm caches and assets in parallel without blocking UI bootstrap
  SharedPreferences.getInstance();
  DataService().loadLocalBuildings();
  rootBundle.loadString('assets/campus_roads.json').then((jsonString) {
    RoutingService().loadCampusRoadsFromJsonString(jsonString);
  }).catchError((_) {});

  runApp(const GecCompassApp());
}

class GecCompassApp extends StatelessWidget {
  const GecCompassApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GECT Compass',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        primaryColor: const Color(0xFF2563EB),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        cardColor: Colors.white,
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF2563EB),
          secondary: Color(0xFF10B981),
          surface: Colors.white,
          onSurface: Color(0xFF0F172A),
        ),
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      home: const MapScreen(),
    );
  }
}
