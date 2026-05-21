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

    final textTheme = GoogleFonts.cairoTextTheme(base.textTheme).apply(
      bodyColor: text,
      displayColor: text,
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
        // 🆕 أَسوَد كامِل في الوَضع الفاتِح وَالداكِن — لِأَقصى تَبايُن.
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
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
        color: surface,
        elevation: 0,
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
        hintStyle: TextStyle(color: textSecondary.withOpacity(0.7)),
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
        indicatorColor: AppColors.brand.withOpacity(0.15),
        labelTextStyle: WidgetStatePropertyAll(textTheme.labelSmall),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStatePropertyAll(
            isDark ? Colors.white : AppColors.brand),
        trackColor: WidgetStatePropertyAll(
            AppColors.brand.withOpacity(isDark ? 0.5 : 0.3)),
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
