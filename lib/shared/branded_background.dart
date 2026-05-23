import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// خلفية موحدة لكل الشاشات: تدرّج + شعار خافت في الوسط
/// تُطبق على كل شاشات التطبيق عبر MaterialApp.builder.
///
/// **2026-05-23 — مَنطِق الـwatermark:**
///   - شاشات Auth/Splash/Home → watermark + glow blobs (هُوِيّة)
///   - شاشات تَشغيليّة (rosters, employees, إلخ) → gradient فَقَط
///   - الـwrapper الـglobal يَستَخدِم `BrandedBackgroundScope.of(context)`
///     لِيُقَرِّر مِنَ الشاشة نَفسها مِن خِلال InheritedWidget.
class BrandedBackground extends StatelessWidget {
  final Widget child;
  /// إذا true (افتِراضيّ) ⇒ يَعرِض الـwatermark logo في الوَسَط
  final bool showWatermark;
  /// إذا true (افتِراضيّ) ⇒ يَعرِض glow blobs + waves (native only)
  final bool showDecorations;

  const BrandedBackground({
    super.key,
    required this.child,
    this.showWatermark = true,
    this.showDecorations = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppColors.bgDark : AppColors.bgLight;

    // قِراءة الـscope مِن الـsubtree (لَو شاشة طَلَبَت تَعطيل decorations)
    final scope = BrandedBackgroundScope.maybeOf(context);
    final effectiveShowWatermark = scope?.showWatermark ?? showWatermark;
    final effectiveShowDecorations = scope?.showDecorations ?? showDecorations;

    return Stack(
      children: [
        // طبقة 1: تدرّج لوني ناعم (Gradient) — دائِماً
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [
                        const Color(0xFF0A0A0A),
                        bgColor,
                        const Color(0xFF1A1A1A),
                      ]
                    : [
                        const Color(0xFFF0F1F4),
                        bgColor,
                        const Color(0xFFE8EAEF),
                      ],
              ),
            ),
          ),
        ),
        // طبقة 2: glow blobs + waves — مَشروط
        if (effectiveShowDecorations && !kIsWeb)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _WatermarkPainter(isDark: isDark),
              ),
            ),
          ),
        // طبقة 3: شعار باهت في الوسط — مَشروط
        if (effectiveShowWatermark)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Opacity(
                  opacity: isDark ? 0.05 : 0.04,
                  child: FractionallySizedBox(
                    widthFactor: 0.55,
                    heightFactor: 0.55,
                    child: BrandLogo(forceInvert: isDark),
                  ),
                ),
              ),
            ),
          ),
        // المحتوى
        child,
      ],
    );
  }
}

/// 🆕 2026-05-23: InheritedWidget يَسمَح لِلشاشات بِتَعطيل watermark/decorations
/// مِن داخِل الـsubtree بِدون تَعديل MaterialApp.builder.
///
/// **مِثال — شاشة تَشغيليّة كَثيفة:**
/// ```dart
/// BrandedBackgroundScope(
///   showWatermark: false,
///   showDecorations: false,
///   child: MyHeavyScreen(),
/// )
/// ```
class BrandedBackgroundScope extends InheritedWidget {
  final bool showWatermark;
  final bool showDecorations;

  const BrandedBackgroundScope({
    super.key,
    required super.child,
    this.showWatermark = false,
    this.showDecorations = false,
  });

  static BrandedBackgroundScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BrandedBackgroundScope>();

  @override
  bool updateShouldNotify(BrandedBackgroundScope oldWidget) =>
      oldWidget.showWatermark != showWatermark ||
      oldWidget.showDecorations != showDecorations;
}

/// رسّام النمط المائي - دوائر ضوئية + موجات منحنية باهتة
class _WatermarkPainter extends CustomPainter {
  final bool isDark;
  _WatermarkPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    // ====== دوائر ضوئية (Blobs) - رمادي/ذهبي على الثيم الجديد ======
    final blob1 = Paint()
      ..color = AppColors.brand.withValues(alpha: isDark ? 0.12 : 0.06)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 80);
    canvas.drawCircle(
      Offset(size.width * 0.15, size.height * 0.15),
      size.width * 0.35,
      blob1,
    );

    final blob2 = Paint()
      ..color = AppColors.gold.withValues(alpha: isDark ? 0.06 : 0.04)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 100);
    canvas.drawCircle(
      Offset(size.width * 0.85, size.height * 0.7),
      size.width * 0.4,
      blob2,
    );

    final blob3 = Paint()
      ..color = AppColors.brandAccent.withValues(alpha: isDark ? 0.06 : 0.04)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 90);
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.95),
      size.width * 0.3,
      blob3,
    );

    // ====== موجات منحنية باهتة ======
    final wavePaint = Paint()
      ..color = AppColors.brand.withValues(alpha: isDark ? 0.05 : 0.04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (int i = 0; i < 3; i++) {
      final path = Path();
      final yOffset = size.height * (0.3 + i * 0.2);
      path.moveTo(0, yOffset);
      for (double x = 0; x <= size.width; x += 10) {
        final y = yOffset +
            math.sin((x / size.width) * 4 * math.pi + i) * 24;
        path.lineTo(x, y);
      }
      canvas.drawPath(path, wavePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _WatermarkPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}

/// شعار الشركة — يعرض `assets/logo_m7.png`.
/// الملف الأصلي فيه خلفيّة بيضاء + رسم أسود. لذلك:
///   • النهاريّ: نعرضه كما هو (خلفيّته البيضاء تذوب مع خلفيّة بيضاء).
///   • الليلي: نقلب الألوان (Color Matrix Invert) — تصير الخلفيّة سوداء
///     فتذوب مع الثيم الداكن، والرسم الأسود يصير أبيض فيظهر بوضوح.
///
/// [forceInvert] — يفرض القلب يدوياً (مفيد للـ watermark).
class BrandLogo extends StatelessWidget {
  /// (deprecated) — لا تأثير. محفوظ للتوافق.
  final Color? color;
  final BoxFit fit;
  /// إن كانت true تُقلب الألوان دائماً بصرف النظر عن الثيم.
  final bool forceInvert;
  const BrandLogo({
    super.key,
    this.color,
    this.fit = BoxFit.contain,
    this.forceInvert = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shouldInvert = forceInvert || isDark;

    final logo = Image.asset(
      'assets/logo_m7.png',
      fit: fit,
      errorBuilder: (_, __, ___) => const _LogoFallback(),
    );

    if (!shouldInvert) return logo;

    // 🔄 Color Matrix لقلب الألوان (Negative)
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(<double>[
        -1, 0, 0, 0, 255,   // R
        0, -1, 0, 0, 255,   // G
        0, 0, -1, 0, 255,   // B
        0, 0, 0, 1, 0,      // A (دون تغيير)
      ]),
      child: logo,
    );
  }
}

/// نص بديل عند عدم تحميل الـ SVG - يعرض "M7" بشكل كبير
class _LogoFallback extends StatelessWidget {
  const _LogoFallback();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black;
    return Center(
      child: FittedBox(
        fit: BoxFit.contain,
        child: Text(
          'M7',
          style: TextStyle(
            fontSize: 600,
            fontWeight: FontWeight.w900,
            color: color,
            letterSpacing: -20,
            height: 1,
          ),
        ),
      ),
    );
  }
}
