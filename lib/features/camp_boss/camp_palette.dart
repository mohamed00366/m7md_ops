import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';

/// 🎨 Camp Boss Palette - الآن يشير إلى AppPalette الموحّد
/// (الأسماء محفوظة للتوافق مع الكود القديم)
class CampPalette {
  // ============= ألوان البراند الرئيسية =============
  static const headerStart = AppPalette.brand;
  static const headerEnd = AppPalette.brandLight;
  static const primary = AppPalette.brandLight;
  static const primaryDark = AppPalette.brand;

  // ============= ألوان دلالية =============
  static const accent = AppPalette.brandLight;

  static const green = AppPalette.success;
  static const greenBg = AppPalette.successSoft;
  static const greenText = Color(0xFF15803D);

  static const amber = AppPalette.amber;
  static const amberDark = AppPalette.amberDark;
  static const amberBg = AppPalette.amberSoft;
  static const amberSoftBg = Color(0xFFFEF6E0);
  static const amberText = Color(0xFF92400E);

  static const red = AppPalette.danger;
  static const redBg = AppPalette.dangerSoft;
  static const redSoftBg = Color(0xFFFCE7E7);
  static const redText = Color(0xFFA32D2D);

  static const purple = AppPalette.purple;
  static const purpleBg = Color(0xFFF3E8FF);

  static const blueBg = AppPalette.infoSoft;
  static const blueText = AppPalette.brandLight;

  // ============= الخلفية والبطاقات =============
  static const bg = AppPalette.surface;
  static const card = AppPalette.card;
  static const input = AppPalette.input;
  static const border = AppPalette.border;
  static const borderLight = AppPalette.borderLight;

  // ============= ألوان النصوص =============
  static const text = AppPalette.text;
  static const textSecondary = AppPalette.textSecondary;
  static const textTertiary = AppPalette.textTertiary;

  // ============= حدود وأنصاف أقطار =============
  static const rCardLg = BorderRadius.all(Radius.circular(AppRadii.xl));
  static const rCard = BorderRadius.all(Radius.circular(AppRadii.lg));
  static const rCardSm = BorderRadius.all(Radius.circular(AppRadii.md));
  static const rInput = BorderRadius.all(Radius.circular(AppRadii.md));
  static const rPill = BorderRadius.all(Radius.circular(AppRadii.pill));

  // ============= ألوان الرسوم البيانية =============
  static const stopColors = AppPalette.chartColors;
}

/// Wrapper widget - يضع الخلفية الموحّدة
class CampThemeWrapper extends StatelessWidget {
  final Widget child;
  const CampThemeWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    // 🌙 خلفية متوافقة مع الوضع الداكن (كانت ثابتة فاتحة تكسر الـ dark mode)
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark ? AppPalette.surfaceDark : AppPalette.surface,
      child: child,
    );
  }
}
