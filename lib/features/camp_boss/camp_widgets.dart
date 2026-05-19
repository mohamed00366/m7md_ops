import 'package:flutter/material.dart';
import 'camp_palette.dart';

/// كارد ستات (إحصائية) صغير - حسب التصميم: عدد كبير + label + sub-label ملوّن
class CampStatCard extends StatelessWidget {
  final String value;
  final String label;
  final String? subLabel;
  final Color? subLabelColor;
  final Color valueColor;
  final VoidCallback? onTap;
  const CampStatCard({
    super.key,
    required this.value,
    required this.label,
    this.subLabel,
    this.subLabelColor,
    this.valueColor = CampPalette.text,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: CampPalette.card,
      borderRadius: CampPalette.rCardSm,
      child: InkWell(
        onTap: onTap,
        borderRadius: CampPalette.rCardSm,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value,
                  style: TextStyle(
                      color: valueColor,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      height: 1.0)),
              const SizedBox(height: 4),
              Text(label,
                  style: const TextStyle(
                      color: CampPalette.textSecondary,
                      fontSize: 9,
                      fontWeight: FontWeight.w500)),
              if (subLabel != null) ...[
                const SizedBox(height: 2),
                Text(subLabel!,
                    style: TextStyle(
                        color: subLabelColor ?? CampPalette.textSecondary,
                        fontSize: 9,
                        fontWeight: FontWeight.w500)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// بطاقة Overview كبيرة - للصف العائم فوق الهيدر
class CampOverviewCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String value;
  final String label;
  final String? subLabel;
  final Color? subLabelColor;
  final VoidCallback? onTap;
  const CampOverviewCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.value,
    required this.label,
    this.subLabel,
    this.subLabelColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: CampPalette.card,
      borderRadius: CampPalette.rCard,
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: CampPalette.rCard,
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(value,
                        style: const TextStyle(
                            color: CampPalette.text,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            height: 1.0)),
                    const SizedBox(height: 3),
                    Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: CampPalette.textSecondary, fontSize: 10)),
                    if (subLabel != null) ...[
                      const SizedBox(height: 2),
                      Text(subLabel!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color:
                                  subLabelColor ?? CampPalette.textSecondary,
                              fontSize: 9,
                              fontWeight: FontWeight.w500)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// زر إجراء سريع - بطاقة بأيقونة + عنوان + وصف
class CampQuickActionButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color titleColor;
  final Color iconColor;
  final Color background;
  final bool primary;
  final VoidCallback onTap;
  const CampQuickActionButton({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.titleColor,
    required this.iconColor,
    required this.background,
    this.primary = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: CampPalette.rCard,
      child: InkWell(
        onTap: onTap,
        borderRadius: CampPalette.rCard,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: CampPalette.rCard,
            border: primary
                ? null
                : Border.all(color: CampPalette.border, width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(height: 6),
              Text(title,
                  style: TextStyle(
                      color: titleColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: TextStyle(
                      color: primary
                          ? Colors.white.withOpacity(0.65)
                          : CampPalette.textSecondary,
                      fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }
}

/// شارة حالة (دائرية)
class CampStatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final Color? bgColor;
  final bool dense;
  const CampStatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.bgColor,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6 : 8,
        vertical: dense ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: bgColor ?? color.withOpacity(0.15),
        borderRadius: CampPalette.rPill,
      ),
      child: Text(label,
          style: TextStyle(
              color: color,
              fontSize: dense ? 9 : 10,
              fontWeight: FontWeight.w500)),
    );
  }
}

/// كارد قسم - عنوان + محتوى + رابط جانبي اختياري
class CampSectionCard extends StatelessWidget {
  final String? title;
  final Widget child;
  final Widget? action;
  final EdgeInsets padding;
  final Color? borderRightColor;

  const CampSectionCard({
    super.key,
    this.title,
    required this.child,
    this.action,
    this.padding = const EdgeInsets.all(14),
    this.borderRightColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: CampPalette.card,
        borderRadius: CampPalette.rCardLg,
        border: borderRightColor == null
            ? null
            : Border(
                right: BorderSide(color: borderRightColor!, width: 3),
              ),
      ),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(title!,
                        style: const TextStyle(
                            color: CampPalette.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ),
                  if (action != null) action!,
                ],
              ),
              const SizedBox(height: 10),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

/// أفاتار صغير دائري لاسم الموظف
class CampEmpAvatar extends StatelessWidget {
  final String name;
  final double radius;
  final Color color;
  final Color bgColor;
  const CampEmpAvatar({
    super.key,
    required this.name,
    this.radius = 11,
    this.color = CampPalette.primary,
    this.bgColor = CampPalette.blueBg,
  });

  String get initials {
    final p = name.trim().split(RegExp(r'\s+'));
    if (p.isEmpty) return '?';
    if (p.length == 1) return p[0].substring(0, 1).toUpperCase();
    return (p[0].substring(0, 1) + p[1].substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(initials,
          style: TextStyle(
              color: color,
              fontSize: radius * 0.75,
              fontWeight: FontWeight.w600)),
    );
  }
}

/// شريحة حقل (label + value) - للملخصات
class CampFieldRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const CampFieldRow({
    super.key,
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    color: CampPalette.textSecondary, fontSize: 12)),
          ),
          Text(value,
              style: TextStyle(
                  color: color ?? CampPalette.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// هيدر الصفحات الفرعية - أزرق غامق مع زر رجوع
class CampPageHeader extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final VoidCallback? onBack;

  const CampPageHeader({
    super.key,
    required this.title,
    this.actions,
    this.onBack,
  });

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [CampPalette.headerStart, CampPalette.headerEnd],
        ),
      ),
      padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 6,
          left: 16,
          right: 16,
          bottom: 12),
      child: Row(
        children: [
          if (onBack != null)
            _CircleIconButton(
              icon: Icons.chevron_left,
              onTap: onBack!,
            ),
          if (onBack == null) const SizedBox(width: 34),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500)),
            ),
          ),
          if (actions != null) ...actions!,
          if (actions == null) const SizedBox(width: 34),
        ],
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}
