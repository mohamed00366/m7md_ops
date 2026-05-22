import 'package:flutter/material.dart';

import '../core/l10n/app_strings.dart';
import '../core/theme/app_palette.dart';

/// 🛡️ حارس الحذف الموحَّد
///
/// المبدأ: قبل أي عملية حذف، نتحقّق من وجود ارتباطات. إن كان الكيان مرتبطاً،
/// نعرض حواراً واضحاً يبيّن للمستخدم بماذا هو مرتبط بدلاً من رسالة خطأ غامضة.
///
/// الاستخدام:
/// ```dart
/// final blockers = [
///   if (employeesCount > 0)
///     DeletionLink(label: 'موظف', count: employeesCount, icon: Icons.people),
/// ];
/// final ok = await DeletionGuard.requireSafe(
///   context,
///   entityName: 'مدير',
///   blockers: blockers,
/// );
/// if (!ok) return;
/// // ... قم بالحذف
/// ```
class DeletionGuard {
  DeletionGuard._();

  /// يتحقّق من القائمة [blockers]. إن لم تكن فارغة → يعرض حواراً ويرجع false.
  /// إن كانت فارغة → يعرض حوار التأكيد العادي ويرجع تأكيد المستخدم.
  static Future<bool> requireSafe(
    BuildContext context, {
    required String entityName,
    required List<DeletionLink> blockers,
    String? subjectName, // اسم الكيان نفسه (مثلاً: "مدير")
  }) async {
    if (blockers.isNotEmpty) {
      // كيان مرتبط → اعرض حوار التحذير
      await _showLinkedDialog(
        context,
        entityName: entityName,
        subjectName: subjectName,
        blockers: blockers,
      );
      return false;
    }
    // كيان غير مرتبط → اعرض حوار تأكيد عادي
    return _showConfirmDialog(
      context,
      entityName: entityName,
      subjectName: subjectName,
    );
  }

  // ===== حوار "غير قابل للحذف" =====
  static Future<void> _showLinkedDialog(
    BuildContext context, {
    required String entityName,
    String? subjectName,
    required List<DeletionLink> blockers,
  }) async {
    final s = AppStrings.of(context);
    final total = blockers.fold<int>(0, (a, b) => a + b.count);
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        icon: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppPalette.danger.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.link_off,
              color: AppPalette.danger, size: 32),
        ),
        title: Text(
          s.isAr ? 'لا يمكن الحذف' : 'Cannot Delete',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              subjectName == null
                  ? (s.isAr
                      ? 'هذا الـ$entityName مرتبط بعناصر أخرى ولا يمكن حذفه.'
                      : 'This $entityName is linked to other items and cannot be deleted.')
                  : (s.isAr
                      ? 'الـ$entityName "$subjectName" مرتبط بعناصر أخرى:'
                      : '$entityName "$subjectName" is linked to:'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppPalette.danger.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: AppPalette.danger.withValues(alpha: 0.30)),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < blockers.length; i++) ...[
                    if (i > 0) const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(blockers[i].icon ?? Icons.link,
                            size: 16, color: AppPalette.danger),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            blockers[i].label,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppPalette.danger,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${blockers[i].count}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w900),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppPalette.amber.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lightbulb_outline,
                      color: AppPalette.amberDark, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      s.isAr
                          ? 'احذف الارتباطات أولاً ($total عنصر) ثم حاول مرة أخرى.'
                          : 'Remove the $total linked item(s) first, then try again.',
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppPalette.amberDark,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppPalette.brand,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.check, size: 16),
            label: Text(s.isAr ? 'فهمت' : 'Got it'),
          ),
        ],
      ),
    );
  }

  // ===== حوار التأكيد العادي =====
  static Future<bool> _showConfirmDialog(
    BuildContext context, {
    required String entityName,
    String? subjectName,
  }) async {
    final s = AppStrings.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        icon: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppPalette.danger.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.delete_forever,
              color: AppPalette.danger, size: 28),
        ),
        title: Text(
          s.isAr ? 'تأكيد الحذف' : 'Confirm Delete',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        content: Text(
          subjectName == null
              ? (s.isAr
                  ? 'هل تريد حذف هذا الـ$entityName؟ لا يمكن التراجع.'
                  : 'Delete this $entityName? This cannot be undone.')
              : (s.isAr
                  ? 'هل تريد حذف "$subjectName"؟'
                  : 'Delete "$subjectName"?'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(s.cancel),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppPalette.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.delete, size: 16),
            label: Text(s.delete),
          ),
        ],
      ),
    );
    return result == true;
  }

  /// عرض رسالة خطأ FK من قاعدة البيانات (إن لم نتمكّن من الفحص المسبق)
  static Future<void> showServerLinkError(
    BuildContext context, {
    String? entityName,
    String? rawError,
  }) async {
    final s = AppStrings.of(context);
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        icon: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppPalette.danger.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.link_off,
              color: AppPalette.danger, size: 32),
        ),
        title: Text(
          s.isAr ? 'لا يمكن الحذف' : 'Cannot Delete',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              s.isAr
                  ? 'هذا العنصر${entityName == null ? "" : " (الـ$entityName)"} مرتبط بعناصر أخرى في قاعدة البيانات.'
                  : 'This item${entityName == null ? "" : " ($entityName)"} is linked to other records in the database.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppPalette.amber.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lightbulb_outline,
                      color: AppPalette.amberDark, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      s.isAr
                          ? 'لا بد من حذف العناصر المرتبطة أولاً ثم إعادة المحاولة.'
                          : 'Delete the linked items first, then try again.',
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppPalette.amberDark,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            if (rawError != null && rawError.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                rawError,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 9, color: AppPalette.textTertiary),
              ),
            ],
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppPalette.brand,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(s.isAr ? 'فهمت' : 'Got it'),
          ),
        ],
      ),
    );
  }

  /// يتحقّق من رسالة الخطأ إن كانت بسبب قيد FK
  static bool isFkError(String? error) {
    if (error == null) return false;
    final lower = error.toLowerCase();
    return lower.contains('foreign key') ||
        lower.contains('violates') ||
        lower.contains('constraint') ||
        lower.contains('23503'); // Postgres FK violation code
  }
}

/// نموذج ارتباط واحد (مثلاً: 5 موظفين)
class DeletionLink {
  final String label;
  final int count;
  final IconData? icon;

  const DeletionLink({
    required this.label,
    required this.count,
    this.icon,
  });
}
