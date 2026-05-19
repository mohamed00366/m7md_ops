import 'package:flutter/material.dart';

/// 🦁 لوغو M7 Nexus — يَختار النُسخة المُناسِبة حَسَب الـtheme
///
/// - Light mode → `m7_logo_light.png` (أَسوَد عَلى أَبيَض)
/// - Dark mode  → `m7_logo_dark.png` (أَبيَض عَلى أَسوَد)
class M7Logo extends StatelessWidget {
  final double size;
  final bool? forceLight; // اِجبار النُسخة (لِلـAppBars الدّاكِنة)

  const M7Logo({super.key, this.size = 48, this.forceLight});

  @override
  Widget build(BuildContext context) {
    final isDark =
        forceLight == true ? false : Theme.of(context).brightness == Brightness.dark;
    return Image.asset(
      isDark ? 'assets/m7_logo_dark.png' : 'assets/m7_logo_light.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Image.asset(
        'assets/logo_m7.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
      ),
    );
  }
}
