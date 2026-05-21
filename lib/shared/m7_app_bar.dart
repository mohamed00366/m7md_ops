import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_colors.dart';

/// 🎨 AppBar موحّد لكلّ التطبيق
///
/// يضمن تصميماً متّسقاً عبر الشاشات:
///   - ارتفاع كافٍ للعنوان الفرعي (subtitle) دون قصّ الأزرار
///   - زرّ رجوع تلقائي واضح
///   - لون brand افتراضي (أو لون مخصّص للهويّة البصريّة)
///   - دعم العناوين الفرعيّة (subtitle) ومصادفة elevation
///
/// مثال:
/// ```dart
/// appBar: M7AppBar(
///   title: 'إعدادات الباصات',
///   subtitle: 'السائقون والركّاب',
///   actions: [IconButton(...)],
/// ),
/// ```
class M7AppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Widget? leading;
  final PreferredSizeWidget? bottom;
  final bool centerTitle;

  const M7AppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
    this.backgroundColor,
    this.foregroundColor,
    this.leading,
    this.bottom,
    this.centerTitle = false,
  });

  static const double _baseHeight = 56;
  static const double _withSubtitleHeight = 68;
  static const double _bottomDefault = 48;

  @override
  Size get preferredSize {
    final base = subtitle == null ? _baseHeight : _withSubtitleHeight;
    final extra = bottom?.preferredSize.height ?? 0;
    return Size.fromHeight(base + extra);
  }

  @override
  Widget build(BuildContext context) {
    final fg = foregroundColor ?? Colors.white;
    // 🆕 أَسوَد كامِل في الوَضع الفاتِح وَالداكِن — أَقصى تَبايُن لِلنَصّ الأَبيَض
    final bg = backgroundColor ?? Colors.black;
    // 🆕 لَون الأَيقونات: ذَهَبيّ لِلتَبايُن العالي مَع الأَسوَد (هُويّة M7 NEXUS)
    final iconColor = AppColors.gold;
    return AppBar(
      backgroundColor: bg,
      foregroundColor: fg,
      // 🆕 شَريط الحالة بِلَون الـ AppBar — أَيقوناته بَيضاء
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: bg,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: centerTitle,
      toolbarHeight:
          subtitle == null ? _baseHeight : _withSubtitleHeight,
      leading: leading,
      // 🆕 أَيقونات أَكبَر وَذَهَبيّة لِلوُضوح
      iconTheme: IconThemeData(color: iconColor, size: 26),
      actionsIconTheme: IconThemeData(color: iconColor, size: 26),
      title: subtitle == null
          ? Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 11,
                    color: fg.withOpacity(0.85),
                    fontWeight: FontWeight.w500,
                    height: 1.0,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
      actions: actions,
      bottom: bottom,
    );
  }
}

/// زرّ إجراء داخل M7AppBar — أيقونة بحجم موحّد + tooltip + onPressed
class M7AppBarAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;
  const M7AppBarAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });
  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      // 🆕 الأَيقونات ذَهَبيّة لِلوُضوح + حَجم أَكبَر
      icon: Icon(icon, color: color ?? AppColors.gold, size: 26),
      onPressed: onPressed,
    );
  }
}
