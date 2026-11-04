import 'package:flutter/material.dart';

import 'core/auth.dart';
import 'core/background.dart';
import 'core/demo.dart';
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
    try {
      await FleetBackground.start();
    } catch (_) {/* tests / no WorkManager */}
  }
  runApp(FleetApp(setUp: FleetAuth.isSetUp(p)));
}

class FleetColors {
  static const gold = Color(0xFFC9A227);
  static const ink = Color(0xFF111827);
  static const ok = Color(0xFF16A34A);
  static const bad = Color(0xFFDC2626);
  static const warn = Color(0xFFD97706);
  static const muted = Color(0xFF6B7280);
}

class FleetApp extends StatelessWidget {
  const FleetApp({super.key, required this.setUp, this.home});
  final bool setUp;

  /// Tests open a page directly.
  final Widget? home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VIP Fleet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: FleetColors.gold, primary: FleetColors.ink, secondary: FleetColors.gold),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(backgroundColor: FleetColors.ink, foregroundColor: Colors.white),
        filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48))),
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), isDense: true),
      ),
      home: home ?? (setUp ? const LoginScreen() : const SetupScreen()),
      routes: {'/home': (_) => const HomeScreen(), '/login': (_) => const LoginScreen()},
    );
  }
}
