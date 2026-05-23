import 'package:flutter/material.dart';

/// 🎨 لوحة الألوان الموحّدة - هوية M7 NEXUS (أسود + ذهبي + ألوان دلالية)
///
/// مصدر الحقيقة الوحيد لكل التطبيق. كل الـ Palettes الأخرى
/// (CampPalette, UniformPalette, BusesPalette, AppColors) تشير لهذا.
class AppPalette {
  AppPalette._();

  // ============= الهوية الأساسية (M7 NEXUS) =============
  /// الأسود الرئيسي - لون شعار M7 NEXUS
  static const brand = Color(0xFF1A1A1A);
  static const brandDark = Color(0xFF000000);
  static const brandLight = Color(0xFF3D3D3D);

  /// الذهبي الفاخر - لمسة البراند
  static const gold = Color(0xFFC9A961);
  static const goldLight = Color(0xFFE8C97D);
  static const goldDark = Color(0xFFA88A45);

  // ============= ألوان الميزات (لكل قسم لون مميّز) =============
  /// تركواز للمغسلة
  static const teal = Color(0xFF0F766E);
  static const tealLight = Color(0xFF14B8A6);

  /// أرجواني لليونيفورم
  static const purple = Color(0xFF6B21A8);
  static const purpleLight = Color(0xFF8B5CF6);

  // ============= ألوان دلالية =============
  static const success = Color(0xFF10B981);
  static const successSoft = Color(0xFFD1FAE5);

  static const amber = Color(0xFFF59E0B);
  static const amberDark = Color(0xFFD97706);
  static const amberSoft = Color(0xFFFEF3C7);

  static const danger = Color(0xFFDC2626);
  static const dangerSoft = Color(0xFFFEE2E2);

  static const info = Color(0xFF0EA5E9);
  static const infoSoft = Color(0xFFE0F2FE);

  // ============= الخلفيات والأسطح (light) =============
  // 🆕 2026-05-23: bg أَغمَق قَليلاً ⇒ Cards البَيضاء تَنفَصِل بِوُضوح
  static const surface = Color(0xFFF5F5F7);
  static const card = Color(0xFFFFFFFF);
  static const input = Color(0xFFF3F4F6);
  static const border = Color(0xFFE5E7EB);
  static const borderLight = Color(0xFFF1F5F9);

  // ============= ألوان النصوص =============
  static const text = Color(0xFF111111);
  static const textSecondary = Color(0xFF4B5563);
  static const textTertiary = Color(0xFF9CA3AF);
  static const textOnDark = Color(0xFFF5F5F5);

  // ============= وضع داكن =============
  // 🆕 2026-05-23: تَدَرُّج elevation قياسيّ (Material 3) — كان OLED black
  // وَكانَت Cards تَختَفي. الآن bg #121212 ⇒ card #1E1E1E ⇒ input #2A2A2A.
  static const surfaceDark = Color(0xFF121212);
  static const cardDark = Color(0xFF1E1E1E);
  static const inputDark = Color(0xFF2A2A2A);
  // 🆕 borderDark #383838 (كان #2E2E2E غَير مَرئيّ عَلى bg)
  static const borderDark = Color(0xFF383838);
  static const textDark = Color(0xFFF5F5F5);
  static const textSecondaryDark = Color(0xFFB0B0B0);
  // 🆕 textTertiaryDark #888 (كان #707070 → WCAG AA fail)
  static const textTertiaryDark = Color(0xFF888888);
  // 🆕 surface تَأثير M3 elevation tint (لِـCards مُرتَفِعة في dark)
  static const surfaceTintDark = Color(0xFF252525);

  // ============= ألوان الأدوار =============
  static const roleAdmin = brand;
  static const roleManager = Color(0xFF374151);
  static const roleOperation = Color(0xFF1F2937);
  static const roleSupervisor = gold; // ذهبي للمشرف
  static const roleCampBoss = Color(0xFF4B5563);
  static const roleEmployee = Color(0xFF9CA3AF);
  static const roleDriver = Color(0xFF6B7280);

  // ============= تدرّجات شائعة =============
  static const brandGradient = [brand, brandLight];
  static const goldGradient = [gold, goldLight];
  static const tealGradient = [teal, tealLight];
  static const purpleGradient = [purple, purpleLight];

  /// ألوان الرسوم البيانية
  static const chartColors = [
    teal,
    purple,
    amber,
    info,
    danger,
  ];
}

/// 📏 مسافات قياسية
class AppSpacing {
  AppSpacing._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  static const EdgeInsets paddingSm = EdgeInsets.all(sm);
  static const EdgeInsets paddingMd = EdgeInsets.all(md);
  static const EdgeInsets paddingLg = EdgeInsets.all(lg);
  static const EdgeInsets paddingXl = EdgeInsets.all(xl);

  static const EdgeInsets pageHorizontal =
      EdgeInsets.symmetric(horizontal: md);
  static const EdgeInsets pageHorizontalLg =
      EdgeInsets.symmetric(horizontal: lg);

  static const Widget gapXs = SizedBox(height: xs);
  static const Widget gapSm = SizedBox(height: sm);
  static const Widget gapMd = SizedBox(height: md);
  static const Widget gapLg = SizedBox(height: lg);
  static const Widget gapXl = SizedBox(height: xl);
}

/// 🔵 أنصاف أقطار قياسية
class AppRadii {
  AppRadii._();

  static const double xs = 4;
  static const double sm = 6;
  static const double md = 8;
  static const double lg = 12;
  static const double xl = 16;
  static const double xxl = 20;
  static const double pill = 999;

  static const BorderRadius rXs = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius rSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius rMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius rLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius rXl = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius rXxl = BorderRadius.all(Radius.circular(xxl));
  static const BorderRadius rPill = BorderRadius.all(Radius.circular(pill));
}

/// ✍️ مقاييس النصوص
class AppFontSizes {
  AppFontSizes._();

  static const double caption = 10;
  static const double captionLg = 11;
  static const double body = 12;
  static const double bodyLg = 13;
  static const double title = 14;
  static const double titleLg = 16;
  static const double headline = 18;
  static const double headlineLg = 20;
  static const double display = 24;
  static const double displayLg = 32;
}

/// 🌫️ ظلال موحّدة
class AppShadows {
  AppShadows._();

  static const sm = [
    BoxShadow(
      color: Color(0x0A000000),
      blurRadius: 3,
      offset: Offset(0, 1),
    ),
  ];
  static const md = [
    BoxShadow(
      color: Color(0x0F000000),
      blurRadius: 6,
      offset: Offset(0, 2),
    ),
  ];
  static const lg = [
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 14,
      offset: Offset(0, 4),
    ),
  ];
}
