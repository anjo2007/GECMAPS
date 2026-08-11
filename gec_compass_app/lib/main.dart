import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/map_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Pre-warm critical services in parallel for faster startup
  await Future.wait([
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
    SharedPreferences.getInstance(), // warm the SharedPreferences singleton
  ]);
  
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
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
