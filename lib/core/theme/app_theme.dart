import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

class AppTheme {
  static ThemeData light() {
    return _build(
      brightness: Brightness.light,
      bg: AppColors.bgLight,
      surface: AppColors.surfaceLight,
      surface2: AppColors.surface2Light,
      border: AppColors.borderLight,
      text: AppColors.textLight,
      textSecondary: AppColors.textSecondaryLight,
    );
  }

  static ThemeData dark() {
    return _build(
      brightness: Brightness.dark,
      bg: AppColors.bgDark,
      surface: AppColors.surfaceDark,
      surface2: AppColors.surface2Dark,
      border: AppColors.borderDark,
      text: AppColors.textDark,
      textSecondary: AppColors.textSecondaryDark,
    );
  }

  static ThemeData _build({
    required Brightness brightness,
    required Color bg,
    required Color surface,
    required Color surface2,
    required Color border,
    required Color text,
    required Color textSecondary,
  }) {
    final isDark = brightness == Brightness.dark;
    final base =
        isDark ? ThemeData.dark(useMaterial3: true) : ThemeData.light(useMaterial3: true);

    final baseTextTheme = GoogleFonts.cairoTextTheme(base.textTheme).apply(
      bodyColor: text,
      displayColor: text,
    );

    // 🆕 2026-05-23: hierarchy واضِحة — Headers أَكبَر + أَوزان أَقوى
    // displayLarge/Medium لِـHeroes (welcome screens, splash)
    // headlineLarge/Medium لِعَناوين الشاشات
    // titleLarge لِعَناوين Cards وَSections
    final textTheme = baseTextTheme.copyWith(
      displayLarge: baseTextTheme.displayLarge?.copyWith(
        fontSize: 36,
        fontWeight: FontWeight.w900,
        letterSpacing: -0.5,
        color: text,
      ),
      displayMedium: baseTextTheme.displayMedium?.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w900,
        letterSpacing: -0.3,
        color: text,
      ),
      headlineLarge: baseTextTheme.headlineLarge?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        color: text,
      ),
      headlineMedium: baseTextTheme.headlineMedium?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: text,
      ),
      titleLarge: baseTextTheme.titleLarge?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: text,
      ),
      titleMedium: baseTextTheme.titleMedium?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: text,
      ),
      bodyLarge: baseTextTheme.bodyLarge?.copyWith(
        fontSize: 14,
        color: text,
      ),
      bodyMedium: baseTextTheme.bodyMedium?.copyWith(
        fontSize: 13,
        color: text,
      ),
      bodySmall: baseTextTheme.bodySmall?.copyWith(
        fontSize: 11,
        color: textSecondary,
      ),
      labelLarge: baseTextTheme.labelLarge?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: text,
      ),
      labelSmall: baseTextTheme.labelSmall?.copyWith(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: textSecondary,
      ),
    );

    return base.copyWith(
      brightness: brightness,
      // شفاف بحيث يظهر BrandedBackground خلف Scaffold
      scaffoldBackgroundColor: Colors.transparent,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: AppColors.brand,
        onPrimary: Colors.white,
        secondary: AppColors.brandAccent,
        onSecondary: Colors.white,
        surface: surface,
        onSurface: text,
        error: AppColors.danger,
        onError: Colors.white,
      ),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        // 🆕 2026-05-23: AppBar dynamic per mode
        //   • Light: brand (أَسوَد) مَع شَريط ذَهَبيّ سُفليّ لِلَمسة الهُوِيّة
        //   • Dark:  surface مُرتَفِع (#1E1E1E) بَدَلاً مِن أَسوَد كامِل — يَنفَصِل
        //     عَن الـbg بِتَدَرُّج elevation طَبيعيّ، لا تَبايُن قاسٍ
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.brand,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        // شَريط ذَهَبيّ سُفليّ — يُؤَكِّد هُوِيّة "أَسوَد + ذَهَبيّ" في كِلا الوَضعَين
        shape: const Border(
          bottom: BorderSide(color: AppColors.gold, width: 2),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        // 🔧 نَستَخدِم GoogleFonts.cairo مُباشَرَةً (لا نَمُرّ بِالـ textTheme
        //   المُعَدَّل لِأَنّ .apply(bodyColor/displayColor) يُعيد كِتابة الألوان
        //   وَيَجعَل النَصّ غامِقاً غَير مَرئيّ عَلى خَلفيّة dark brand).
        titleTextStyle: GoogleFonts.cairo(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w900,
        ),
        toolbarTextStyle: GoogleFonts.cairo(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        // 🆕 شريط الحالة شفّاف بأيقونات بيضاء — للـ AppBars الملوّنة (brand)
        // الشاشات ذات AppBar فاتح يمكنها تعديل systemOverlayStyle محلّياً
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
      ),
      cardTheme: CardTheme(
        // 🆕 2026-05-23: في light نُضيف elevation خَفيفة لِتَنفَصِل Cards
        // عَن الـbg. في dark نَعتَمِد عَلى surface tint (M3 standard).
        color: surface,
        elevation: isDark ? 0 : 1.5,
        shadowColor: Colors.black.withValues(alpha: 0.06),
        surfaceTintColor: isDark ? AppColors.brandAccent : Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: border, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface2,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.brand, width: 1.5),
        ),
        labelStyle: TextStyle(color: textSecondary),
        hintStyle: TextStyle(color: textSecondary.withValues(alpha: 0.7)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brand,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.cairo(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.brand,
          side: const BorderSide(color: AppColors.brand),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.cairo(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.brand,
          textStyle: GoogleFonts.cairo(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
      ),
      dividerColor: border,
      dividerTheme: DividerThemeData(color: border, thickness: 1),
      iconTheme: IconThemeData(color: text),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: AppColors.brand,
        unselectedItemColor: textSecondary,
        type: BottomNavigationBarType.fixed,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: AppColors.brand.withValues(alpha: 0.15),
        labelTextStyle: WidgetStatePropertyAll(textTheme.labelSmall),
      ),
      switchTheme: SwitchThemeData(
        // 🆕 2026-05-23: thumb أَبيَض دائِماً، track ذَهَبيّ عِندَ ON
        // (كانَ thumb أَسوَد في light ⇒ يَبدو OFF حَتّى لَو مُفَعَّل)
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return Colors.grey[400];
          return Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return Colors.grey.withValues(alpha: 0.3);
          }
          if (states.contains(WidgetState.selected)) {
            return AppColors.gold; // 🥇 ذَهَبيّ عِندَ التَفعيل
          }
          return isDark
              ? Colors.grey[700]
              : Colors.grey[400]; // OFF track
        }),
        trackOutlineColor: WidgetStatePropertyAll(Colors.transparent),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: surface,
        contentTextStyle: textTheme.bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}
