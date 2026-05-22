// =============================================================================
// 📭 M7EmptyState — حالة فارِغة مُوَحَّدة عَبر كُلّ الشاشات
// =============================================================================
// استَخدِم هذه بَدَل تَكرار `Icon + Text("لا تَوجَد بَيانات")` في كُلّ شاشة.
//
// مَثال:
// ```dart
// if (items.isEmpty) {
//   return M7EmptyState(
//     icon: Icons.inbox_outlined,
//     titleAr: 'لا تَوجَد إشعارات بَعد',
//     titleEn: 'No notifications yet',
//     actionLabel: 'تَحديث',
//     onAction: () => _load(),
//   );
// }
// ```
// =============================================================================

import 'package:flutter/material.dart';

import '../core/l10n/app_strings.dart';

class M7EmptyState extends StatelessWidget {
  final IconData icon;
  final String titleAr;
  final String titleEn;
  final String? subtitleAr;
  final String? subtitleEn;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;
  final double iconSize;
  final Color? iconColor;

  const M7EmptyState({
    super.key,
    required this.icon,
    required this.titleAr,
    required this.titleEn,
    this.subtitleAr,
    this.subtitleEn,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    this.iconSize = 64,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final theme = Theme.of(context);
    final color = iconColor ?? Colors.grey.withValues(alpha: 0.4);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: iconSize, color: color),
            const SizedBox(height: 14),
            Text(
              isAr ? titleAr : titleEn,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: theme.textTheme.bodyLarge?.color,
              ),
            ),
            if (subtitleAr != null || subtitleEn != null) ...[
              const SizedBox(height: 6),
              Text(
                isAr ? (subtitleAr ?? '') : (subtitleEn ?? ''),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: onAction,
                icon: Icon(actionIcon ?? Icons.refresh, size: 16),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
