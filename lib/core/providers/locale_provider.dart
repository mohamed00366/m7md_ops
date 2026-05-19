import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/ar_to_ur_dictionary.dart' as ar2ur;
import '../services/user_preferences_service.dart';

/// 🌐 مُزَوِّد اللُغة
///
/// **نَمَط hybrid:**
///   - قَبل تَسجيل الدُخول: تَستَخدِم default device key (`app_locale`)
///   - بَعد تَسجيل الدُخول: تَستَخدِم `UserPreferencesService` (per-user-per-device)
///   - مَع تَفعيل sync: تُزامَن عَبر DB
class LocaleProvider extends ChangeNotifier {
  static const _kDeviceDefaultKey = 'app_locale'; // device-level default
  Locale _locale = const Locale('ar');

  /// اللُغات المَدعومة (مَتاحة لِلتَبديل)
  static const supportedCodes = ['ar', 'en', 'ur'];

  Locale get locale => _locale;

  /// RTL لِلعَرَبيّ وَالأردو
  bool get isRtl =>
      _locale.languageCode == 'ar' || _locale.languageCode == 'ur';

  bool get isAr => _locale.languageCode == 'ar';
  bool get isEn => _locale.languageCode == 'en';
  bool get isUr => _locale.languageCode == 'ur';

  /// تَحميل اللُغة الافتِراضيّة لِلجِهاز (قَبل تَسجيل الدُخول)
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_kDeviceDefaultKey);
    if (supportedCodes.contains(code)) {
      _locale = Locale(code!);
    }
    ar2ur.setGlobalLanguageCode(_locale.languageCode);
  }

  /// 🆕 تَطبيق لُغة المُستَخدِم بَعد تَسجيل الدُخول
  /// تُستَدعى مِن AuthProvider بَعد نَجاح login
  Future<void> applyUserPreference() async {
    final userPrefs = UserPreferencesService.instance;
    final userLocale = userPrefs.locale;
    if (userLocale != null && supportedCodes.contains(userLocale)) {
      _locale = Locale(userLocale);
      ar2ur.setGlobalLanguageCode(_locale.languageCode);
      notifyListeners();
    }
    // لَو المُستَخدِم لا لَدَيه لُغة مَحفوظة → احتَفِظ بِالـdevice default
  }

  Future<void> setLocale(Locale locale) async {
    if (locale == _locale) return;
    if (!supportedCodes.contains(locale.languageCode)) return;
    _locale = locale;
    ar2ur.setGlobalLanguageCode(locale.languageCode);

    // 1) اكتُب في الـdevice default (لِفائِدة الجَلَسة قَبل login المَرَّة التالية)
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDeviceDefaultKey, locale.languageCode);

    // 2) لَو مُستَخدِم مُسَجَّل، اكتُب أَيضاً في تَفضيلاته الشَخصيّة
    final userPrefs = UserPreferencesService.instance;
    if (userPrefs.accountId != null) {
      await userPrefs.setValue('locale', locale.languageCode);
    }

    notifyListeners();
  }

  /// تَبديل ضِمن دائِرة: ar → en → ur → ar
  Future<void> toggle() async {
    final idx = supportedCodes.indexOf(_locale.languageCode);
    final next = supportedCodes[(idx + 1) % supportedCodes.length];
    await setLocale(Locale(next));
  }

  /// تَبديل مُباشَر بِالكود
  Future<void> setByCode(String code) async {
    if (!supportedCodes.contains(code)) return;
    await setLocale(Locale(code));
  }
}
