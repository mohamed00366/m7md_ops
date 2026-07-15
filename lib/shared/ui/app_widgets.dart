/// 🧩 مكتبة Widgets موحّدة للتطبيق - مصدر الحقيقة الوحيد للأشكال
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';

/// 🃏 بطاقة أساسية موحّدة
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final Color? borderColor;
  final double radius;
  final VoidCallback? onTap;
  final bool elevated;

  const AppCard({
    super.key,
    required this.child,
    this.padding = AppSpacing.paddingMd,
    this.color,
    this.borderColor,
    this.radius = AppRadii.lg,
    this.onTap,
    this.elevated = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = Container(
      decoration: BoxDecoration(
        color: color ?? (isDark ? AppPalette.cardDark : AppPalette.card),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: borderColor ??
              (isDark ? AppPalette.borderDark : AppPalette.border),
        ),
        boxShadow: elevated ? AppShadows.md : null,
      ),
      child: padding != null
          ? Padding(padding: padding!, child: child)
          : child,
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: card,
      ),
    );
  }
}

/// 💊 شارة Pill صغيرة
class AppPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  final double fontSize;
  final EdgeInsetsGeometry padding;

  const AppPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.fontSize = AppFontSizes.caption,
    this.padding =
        const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: AppRadii.rXs,
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: fontSize, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// 📊 بطاقة KPI موحّدة
class AppKpiCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String? hint;
  final double width;

  const AppKpiCard({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.hint,
    this.width = 150,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: width,
      child: AppCard(
        padding: AppSpacing.paddingMd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: AppRadii.rMd,
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              value,
              style: TextStyle(
                fontSize: AppFontSizes.headline,
                fontWeight: FontWeight.w900,
                color: isDark ? AppPalette.textDark : AppPalette.text,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isDark
                    ? AppPalette.textSecondaryDark
                    : AppPalette.textSecondary,
                fontSize: AppFontSizes.captionLg,
              ),
            ),
            if (hint != null) ...[
              const SizedBox(height: 2),
              Text(
                hint!,
                style: TextStyle(
                  color: color,
                  fontSize: AppFontSizes.caption,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 📭 حالة فارغة موحّدة
class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  final Color? color;

  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = color ??
        (isDark ? AppPalette.textTertiaryDark : AppPalette.textTertiary);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl + AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: isDark ? AppPalette.inputDark : AppPalette.input,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: c),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppFontSizes.title,
                fontWeight: FontWeight.w800,
                color: isDark
                    ? AppPalette.textSecondaryDark
                    : AppPalette.textSecondary,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark
                      ? AppPalette.textTertiaryDark
                      : AppPalette.textTertiary,
                  fontSize: AppFontSizes.body,
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.md),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// 🔍 شريط بحث موحّد
class AppSearchBar extends StatefulWidget {
  final String hint;
  final String value;
  final ValueChanged<String> onChanged;
  final IconData? icon;
  final EdgeInsetsGeometry margin;

  const AppSearchBar({
    super.key,
    required this.hint,
    required this.value,
    required this.onChanged,
    this.icon,
    this.margin = EdgeInsets.zero,
  });

  @override
  State<AppSearchBar> createState() => _AppSearchBarState();
}

class _AppSearchBarState extends State<AppSearchBar> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant AppSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _ctrl.text) {
      _ctrl.text = widget.value;
      _ctrl.selection = TextSelection.collapsed(offset: widget.value.length);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = isDark
        ? AppPalette.textSecondaryDark
        : AppPalette.textSecondary;
    return Container(
      margin: widget.margin,
      decoration: BoxDecoration(
        color: isDark ? AppPalette.inputDark : AppPalette.input,
        borderRadius: AppRadii.rLg,
        border: Border.all(
            color: isDark ? AppPalette.borderDark : AppPalette.border),
      ),
      child: TextField(
        controller: _ctrl,
        onChanged: widget.onChanged,
        style: const TextStyle(fontSize: AppFontSizes.bodyLg),
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: TextStyle(
            color: isDark
                ? AppPalette.textTertiaryDark
                : AppPalette.textTertiary,
            fontSize: AppFontSizes.bodyLg,
          ),
          prefixIcon: Icon(
            widget.icon ?? Icons.search,
            size: 18,
            color: secondary,
          ),
          suffixIcon: _ctrl.text.isEmpty
              ? null
              : IconButton(
                  icon: Icon(
                    Icons.clear,
                    size: 16,
                    color: secondary,
                  ),
                  onPressed: () {
                    _ctrl.clear();
                    widget.onChanged('');
                  },
                ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 10,
          ),
          isDense: true,
        ),
      ),
    );
  }
}

/// 🏷️ شريحة فلتر مع عدّاد
class AppFilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final Color color;
  final IconData? icon;
  final VoidCallback onTap;

  const AppFilterChip({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    required this.color,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadii.rPill,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color : color.withValues(alpha: 0.10),
          borderRadius: AppRadii.rPill,
          border: Border.all(color: color.withValues(alpha: selected ? 1 : 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: selected ? Colors.white : color),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : color,
                fontSize: AppFontSizes.body,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white.withValues(alpha: 0.25)
                    : color.withValues(alpha: 0.18),
                borderRadius: AppRadii.rPill,
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: selected ? Colors.white : color,
                  fontSize: AppFontSizes.caption,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 📌 ترويسة قسم
class AppSectionHeader extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final int? count;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const AppSectionHeader({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    this.count,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(4, 8, 4, 8),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: AppFontSizes.titleLg - 3,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: AppRadii.rPill,
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: color,
                  fontSize: AppFontSizes.caption,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
          if (trailing != null) ...[
            const Spacer(),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// 🔘 زر بحالة تحميل (Loading)
class AppLoadingButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool loading;
  final IconData icon;
  final String label;
  final Color color;
  final Color foreground;
  final EdgeInsetsGeometry padding;

  const AppLoadingButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.loading = false,
    this.color = AppPalette.brand,
    this.foreground = Colors.white,
    this.padding =
        const EdgeInsets.symmetric(vertical: AppSpacing.md + 2),
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: foreground,
        padding: padding,
      ),
      onPressed: loading ? null : onPressed,
      icon: loading
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: foreground,
              ),
            )
          : Icon(icon),
      label: Text(label),
    );
  }
}

/// 🧱 وعاء صفحة موحّد - يضمّ AppBar + body بنفس الـ background
class AppPageScaffold extends StatelessWidget {
  final Widget body;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final Color? backgroundColor;

  const AppPageScaffold({
    super.key,
    required this.body,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: backgroundColor ??
          (isDark ? AppPalette.surfaceDark : AppPalette.surface),
      body: body,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}

/// 📋 صف معلومات (Label / Value)
class AppInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  final Color? color;

  const AppInfoRow({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = isDark
        ? AppPalette.textSecondaryDark
        : AppPalette.textSecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color ?? secondary),
            const SizedBox(width: 8),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: AppFontSizes.captionLg,
              color: secondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontSize: AppFontSizes.body,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
