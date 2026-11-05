import 'package:flutter/material.dart';

import 'core/auth.dart';
import 'core/background.dart';
import 'core/demo.dart';
import 'core/foreground.dart';
import 'core/store.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/setup_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final p = await Prefs.get();
  if (FleetDemo.on) {
    FleetDemo.start(); // web preview with sample data
  } else {
    FleetForeground.initComms();
    try {
      await FleetBackground.start();
    } catch (_) {/* tests / no WorkManager */}
    try {
      await FleetForeground.startIfEnabled(p);
    } catch (_) {/* tests / old device */}
  }
  runApp(FleetApp(setUp: FleetAuth.isSetUp(p)));
}

class FleetColors {
  static const gold = Color(0xFF2B2E33); // monochrome accent (was gold) — white/black theme
  static const ink = Color(0xFF0B0B0C);
  static const ok = Color(0xFF16A34A);
  static const bad = Color(0xFFDC2626);
  static const warn = Color(0xFFD97706);
  static const muted = Color(0xFF6B7280);
  // the white/black gradient used on bars and headers
  static const barGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0B0B0C), Color(0xFF3A3D44)],
  );
}

/// A black→graphite gradient behind an AppBar.
const kBarFlex = DecoratedBox(decoration: BoxDecoration(gradient: FleetColors.barGradient));

class FleetApp extends StatelessWidget {
  const FleetApp({super.key, required this.setUp, this.home});
  final bool setUp;

  /// Tests open a page directly.
  final Widget? home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VIP Settings',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3A3D44), primary: FleetColors.ink, secondary: FleetColors.gold),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F6F8),
        appBarTheme: const AppBarTheme(backgroundColor: FleetColors.ink, foregroundColor: Colors.white, elevation: 0),
        filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48))),
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), isDense: true),
      ),
      home: home ?? (setUp ? const LoginScreen() : const SetupScreen()),
      routes: {'/home': (_) => const HomeScreen(), '/login': (_) => const LoginScreen()},
    );
  }
}
