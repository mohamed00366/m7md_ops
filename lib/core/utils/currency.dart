import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../repositories/mock_repository.dart';

/// 💰 خدمة عرض العملات حسب الدولة الفعّالة
///
/// استخدم `AppCurrency.format(context, amount)` لعرض المبلغ مع الرمز الصحيح.
/// الرموز:
///   SAR → ر.س / SAR
///   AED → د.إ / AED
///   KWD → د.ك / KWD
///   QAR → ر.ق / QAR
///   BHD → د.ب / BHD
///   OMR → ر.ع / OMR
///   EGP → ج.م / EGP
class AppCurrency {
  AppCurrency._();

  /// رمز العملة بالعربي
  static String _arabicSymbol(String code) {
    switch (code.toUpperCase()) {
      case 'SAR':
        return 'ر.س';
      case 'AED':
        return 'د.إ';
      case 'KWD':
        return 'د.ك';
      case 'QAR':
        return 'ر.ق';
      case 'BHD':
        return 'د.ب';
      case 'OMR':
        return 'ر.ع';
      case 'EGP':
        return 'ج.م';
      case 'USD':
        return 'دولار';
      case 'EUR':
        return 'يورو';
      default:
        return code;
    }
  }

  /// رمز العملة بالإنجليزي = نفس الكود (SAR, AED, ...)
  static String _englishSymbol(String code) => code.toUpperCase();

  /// كود العملة للدولة الفعّالة (أو SAR كافتراضي)
  static String activeCode(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final repo = MockRepository();
    if (auth.activeCountryId == null) return 'SAR';
    try {
      final c =
          repo.countries.firstWhere((x) => x.id == auth.activeCountryId);
      return c.currency.isEmpty ? 'SAR' : c.currency;
    } catch (_) {
      return 'SAR';
    }
  }

  /// رمز العملة المعروض حسب اللغة
  static String activeSymbol(BuildContext context) {
    final s = AppStrings.of(context);
    final code = activeCode(context);
    return s.isAr ? _arabicSymbol(code) : _englishSymbol(code);
  }

  /// تنسيق مبلغ مع رمز العملة
  static String format(
    BuildContext context,
    num amount, {
    int decimals = 2,
  }) {
    return '${amount.toStringAsFixed(decimals)} ${activeSymbol(context)}';
  }

  /// تنسيق مبلغ بدون كسور (للأعداد الصحيحة)
  static String formatInt(BuildContext context, num amount) {
    return '${amount.toStringAsFixed(0)} ${activeSymbol(context)}';
  }

  /// تنسيق مبلغ لدولة معيّنة (تجاوز الدولة الفعّالة)
  static String formatForCountry(
    String countryId,
    num amount, {
    bool isAr = true,
    int decimals = 2,
  }) {
    final repo = MockRepository();
    String code = 'SAR';
    try {
      final c = repo.countries.firstWhere((x) => x.id == countryId);
      if (c.currency.isNotEmpty) code = c.currency;
    } catch (_) {}
    final sym = isAr ? _arabicSymbol(code) : _englishSymbol(code);
    return '${amount.toStringAsFixed(decimals)} $sym';
  }

  /// رمز فقط (بدون مبلغ) لاستخدامه كـ label
  static String symbolFor(String currencyCode, {required bool isAr}) {
    return isAr
        ? _arabicSymbol(currencyCode)
        : _englishSymbol(currencyCode);
  }
}
