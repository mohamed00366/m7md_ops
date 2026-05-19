import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../models/models.dart';

/// 🪪 ويدجت موحّد لعرض هويّة الموظّف عبر التطبيق:
///   • [EmployeeAvatar] — دائرة الصورة (مع fallback للأحرف الأولى)
///   • [EmployeeIdentity] — صفّ كامل: صورة + اسم + كود
///   • [EmployeeIdentityChip] — نسخة مدمجة (Pill) للقوائم الكثيفة
///
/// يُستخدم في:
///   • شاشات الباصات (تخطيط، حضور، ركّاب الباص)
///   • شاشات الروستر (الإنشاء، الموافقة، التوزيع)
///   • شاشات السائق (المشاوير، الحضور)
///   • أيّ شاشة تعرض قائمة موظّفين
///
/// المبدأ: مصدر هويّة واحد للموظّف عبر التطبيق — صورة، اسم، كود.

// ============================================================
// EmployeeAvatar — الدائرة فقط
// ============================================================
class EmployeeAvatar extends StatelessWidget {
  final Employee employee;
  final double radius;
  final Color color;
  const EmployeeAvatar({
    super.key,
    required this.employee,
    this.radius = 18,
    this.color = AppColors.brand,
  });

  Widget _initials() {
    return Text(
      employee.initials,
      style: TextStyle(
        color: color,
        fontSize: radius * 0.65,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final raw = employee.photoFileId;
    final hasPhoto = raw != null &&
        raw.isNotEmpty &&
        (raw.startsWith('http://') || raw.startsWith('https://'));

    final fallback = CircleAvatar(
      radius: radius,
      backgroundColor: color.withOpacity(0.15),
      child: _initials(),
    );

    if (!hasPhoto) return fallback;

    final url = raw;
    final keyHash = '${employee.id}_${url.hashCode}';

    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.15),
      ),
      child: ClipOval(
        child: Image.network(
          url,
          key: ValueKey(keyHash),
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          errorBuilder: (ctx, err, stack) => fallback,
          loadingBuilder: (ctx, child, progress) {
            if (progress == null) return child;
            return Center(child: _initials());
          },
        ),
      ),
    );
  }
}

// ============================================================
// EmployeeIdentity — صفّ كامل (صورة + اسم + كود)
// ============================================================

/// عرض موحّد لهويّة الموظّف: صورة دائريّة + الاسم في سطر علويّ +
/// الكود الوظيفي (والمسمّى اختيارياً) في سطر سفليّ خفيف.
///
/// مصمّم ليعمل داخل بطاقات وقوائم وحوارات. يدعم 3 أحجام:
///   • [EmployeeIdentitySize.compact] — للقوائم الكثيفة (h≈32)
///   • [EmployeeIdentitySize.normal] — الافتراضي (h≈44)
///   • [EmployeeIdentitySize.large] — للبطاقات (h≈64)
class EmployeeIdentity extends StatelessWidget {
  final Employee employee;
  final EmployeeIdentitySize size;
  final bool showCode;
  final bool showJobTitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color avatarColor;
  final EdgeInsetsGeometry? padding;
  final TextStyle? nameStyle;
  final TextStyle? subtitleStyle;

  const EmployeeIdentity({
    super.key,
    required this.employee,
    this.size = EmployeeIdentitySize.normal,
    this.showCode = true,
    this.showJobTitle = false,
    this.trailing,
    this.onTap,
    this.avatarColor = AppColors.brand,
    this.padding,
    this.nameStyle,
    this.subtitleStyle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = switch (size) {
      EmployeeIdentitySize.compact => 14.0,
      EmployeeIdentitySize.normal => 18.0,
      EmployeeIdentitySize.large => 26.0,
    };
    final nameSize = switch (size) {
      EmployeeIdentitySize.compact => 11.5,
      EmployeeIdentitySize.normal => 13.0,
      EmployeeIdentitySize.large => 14.5,
    };
    final subSize = switch (size) {
      EmployeeIdentitySize.compact => 9.5,
      EmployeeIdentitySize.normal => 10.5,
      EmployeeIdentitySize.large => 11.5,
    };
    final gap = switch (size) {
      EmployeeIdentitySize.compact => 6.0,
      EmployeeIdentitySize.normal => 8.0,
      EmployeeIdentitySize.large => 10.0,
    };

    final subtitleParts = <String>[];
    if (showCode && employee.code.isNotEmpty) {
      subtitleParts.add(employee.code);
    }
    if (showJobTitle && employee.jobTitle.isNotEmpty) {
      subtitleParts.add(employee.jobTitle);
    }
    final subtitle = subtitleParts.join(' • ');

    Widget content = Row(
      children: [
        EmployeeAvatar(
          employee: employee,
          radius: radius,
          color: avatarColor,
        ),
        SizedBox(width: gap),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                employee.fullName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: nameStyle ??
                    TextStyle(
                      fontSize: nameSize,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: subtitleStyle ??
                      TextStyle(
                        fontSize: subSize,
                        fontWeight: FontWeight.w600,
                        color: theme.textTheme.bodySmall?.color,
                      ),
                ),
            ],
          ),
        ),
        if (trailing != null) ...[
          SizedBox(width: gap),
          trailing!,
        ],
      ],
    );

    if (padding != null) {
      content = Padding(padding: padding!, child: content);
    }

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: content,
      );
    }
    return content;
  }
}

enum EmployeeIdentitySize { compact, normal, large }

// ============================================================
// EmployeeIdentityChip — نسخة Pill صغيرة (للـ Wrap الكثيفة)
// ============================================================

/// كبسولة مدمجة لعرض الموظّف داخل شريط بنود (مثل قائمة ركّاب الباص
/// أو الموظّفين في خلية روستر). تعرض الصورة دائريّاً صغيرة + الاسم
/// المختصر، مع الكود في tooltip.
class EmployeeIdentityChip extends StatelessWidget {
  final Employee employee;
  final Color color;
  final VoidCallback? onTap;
  final Widget? leading;
  final Widget? trailing;
  final bool showCode;

  const EmployeeIdentityChip({
    super.key,
    required this.employee,
    this.color = AppColors.brand,
    this.onTap,
    this.leading,
    this.trailing,
    this.showCode = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 4)],
          EmployeeAvatar(
            employee: employee,
            radius: 10,
            color: color,
          ),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 110),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  employee.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 10.5, fontWeight: FontWeight.w700),
                ),
                if (showCode && employee.code.isNotEmpty)
                  Text(
                    employee.code,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 9,
                        color: theme.textTheme.bodySmall?.color,
                        fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 4), trailing!],
        ],
      ),
    );

    final tooltip = employee.code.isNotEmpty
        ? '${employee.fullName} • ${employee.code}'
        : employee.fullName;
    content = Tooltip(message: tooltip, child: content);

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: content,
      );
    }
    return content;
  }
}
