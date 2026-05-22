import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// شعار M7 Nexus - واجهة موحّدة للاستخدام عبر التطبيق
///
/// الاستخدامات:
/// - `AppLogo()` - حجم متوسط (40)
/// - `AppLogo.small()` - في AppBar (28)
/// - `AppLogo.large()` - في الـ Drawer أو شاشات الترحيب (80)
/// - `AppLogo.huge()` - شاشة بداية / صفحات فارغة (160)
///
/// خيار `withName` يضيف نص "M7 NEXUS" بجانب الشعار.
class AppLogo extends StatelessWidget {
  final double size;
  final bool withName;
  final Color? tint;
  final bool dark;

  const AppLogo({
    super.key,
    this.size = 40,
    this.withName = false,
    this.tint,
    this.dark = false,
  });

  const AppLogo.small({super.key, this.withName = false, this.tint, this.dark = false})
      : size = 28;

  const AppLogo.medium({super.key, this.withName = false, this.tint, this.dark = false})
      : size = 40;

  const AppLogo.large({super.key, this.withName = true, this.tint, this.dark = false})
      : size = 72;

  const AppLogo.huge({super.key, this.withName = true, this.tint, this.dark = false})
      : size = 140;

  @override
  Widget build(BuildContext context) {
    final logo = SvgPicture.asset(
      'assets/m7_nexus_logo.svg',
      width: size,
      height: size,
      fit: BoxFit.contain,
      colorFilter: tint != null
          ? ColorFilter.mode(tint!, BlendMode.srcIn)
          : null,
    );

    if (!withName) return logo;

    final textColor = tint ??
        (dark ? Colors.white : const Color(0xFF111827));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        logo,
        SizedBox(width: size * 0.18),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'M7',
              style: TextStyle(
                color: textColor,
                fontSize: size * 0.55,
                fontWeight: FontWeight.w900,
                height: 1,
                letterSpacing: 1.0,
              ),
            ),
            SizedBox(height: size * 0.04),
            Text(
              'NEXUS',
              style: TextStyle(
                color: textColor.withValues(alpha: 0.75),
                fontSize: size * 0.20,
                fontWeight: FontWeight.w700,
                letterSpacing: size * 0.10,
                height: 1,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// خلفية باهتة بالشعار (للصفحات الفارغة أو شاشات البداية)
class AppLogoBackground extends StatelessWidget {
  final Widget child;
  final double opacity;
  final double size;
  final Alignment alignment;

  const AppLogoBackground({
    super.key,
    required this.child,
    this.opacity = 0.04,
    this.size = 380,
    this.alignment = Alignment.center,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: Align(
              alignment: alignment,
              child: Opacity(
                opacity: opacity,
                child: SvgPicture.asset(
                  'assets/m7_nexus_logo.svg',
                  width: size,
                  height: size,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
