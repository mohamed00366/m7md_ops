import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/l10n/app_strings.dart';
import '../core/providers/auth_provider.dart';
import '../core/theme/app_colors.dart';
import '../features/auth/country_selector.dart';

/// 🛡️ حارس الدولة — مبدأ موحّد:
/// لا يُسمح بأي عملية إنشاء بدون تحديد دولة فعّالة (`auth.activeCountryId`).
///
/// الاستخدام:
/// ```dart
/// if (!await CountryGuard.require(context)) return;
/// // ... كود الإنشاء بعد التأكد من وجود الدولة
/// ```
///
/// السلوك:
/// 1) لو الدولة محدّدة → يُرجع `true` فوراً
/// 2) لو غير محدّدة → يعرض حوار تحذير، وعند الموافقة ينقل لـ Country Selector
///    ويُرجع `true` لو اختار، أو `false` لو ألغى
class CountryGuard {
  CountryGuard._();

  /// يتحقّق من وجود دولة محدّدة. لو لا، يعرض تحذير + ينقل للاختيار.
  ///
  /// [entityName] اختياري لتخصيص الرسالة (مثلاً: "غرفة" / "موظف" / "تقييم")
  static Future<bool> require(
    BuildContext context, {
    String? entityName,
  }) async {
    final auth = context.read<AuthProvider>();
    if (auth.activeCountryId != null) return true;

    final s = AppStrings.of(context);
    final action = entityName ?? (s.isAr ? 'هذه العملية' : 'this action');

    // عرض حوار تحذير
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        icon: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.warning.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.public_off,
              color: AppColors.warning, size: 28),
        ),
        title: Text(
          s.isAr ? 'يجب اختيار دولة' : 'Country Required',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              s.isAr
                  ? 'لا يمكن تنفيذ $action بدون اختيار دولة محدّدة.'
                  : 'Cannot perform $action without selecting a country.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.brand.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                s.isAr
                    ? '💡 سيتم نقلك لشاشة اختيار الدولة'
                    : '💡 You\'ll be taken to the country selector',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: AppColors.brand),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(s.cancel),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brand,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.public, size: 16),
            label: Text(s.isAr ? 'اختر دولة' : 'Select Country'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return false;

    // الانتقال لشاشة اختيار الدولة
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const CountrySelectorScreen(isSwitch: true),
      ),
    );

    if (!context.mounted) return false;

    // فحص نهائي: هل اختار المستخدم دولة فعلاً؟
    return auth.activeCountryId != null;
  }
}
