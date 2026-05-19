import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/user_preferences_service.dart';

/// 🎨 مُزَوِّد الـTheme
///
/// **نَمَط hybrid:**
///   - قَبل login: device default key (`app_theme_mode`)
///   - بَعد login: `UserPreferencesService` (per-user-per-device)
///   - مَع تَفعيل sync: يُزامَن عَبر DB
class ThemeProvider extends ChangeNotifier {
  static const _kDeviceDefaultKey = 'app_theme_mode';
  ThemeMode _mode = ThemeMode.light;

  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_kDeviceDefaultKey);
    _mode = _modeFromString(v) ?? ThemeMode.light;
  }

  /// 🆕 تَطبيق theme المُستَخدِم بَعد login
  Future<void> applyUserPreference() async {
    final userPrefs = UserPreferencesService.instance;
    final userTheme = userPrefs.theme;
    if (userTheme != null) {
      final m = _modeFromString(userTheme);
      if (m != null) {
        _mode = m;
        notifyListeners();
      }
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;

    // 1) اكتُب في الـdevice default
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDeviceDefaultKey, mode.name);

    // 2) لَو مُستَخدِم مُسَجَّل، اكتُب في تَفضيلاته الشَخصيّة
    final userPrefs = UserPreferencesService.instance;
    if (userPrefs.accountId != null) {
      await userPrefs.setValue('theme', mode.name);
    }

    notifyListeners();
  }

  Future<void> toggle() async {
    await setMode(isDark ? ThemeMode.light : ThemeMode.dark);
  }

  static ThemeMode? _modeFromString(String? s) {
    switch (s) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      case 'system':
        return ThemeMode.system;
    }
    return null;
  }
}
