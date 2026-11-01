import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Menu layout (merge plan, Nov 2026): the new menu joins pages that showed the same thing; the old menu keeps every
/// entry as before. Saved on this device; switched from My Preferences.
class MenuLayout {
  MenuLayout._();
  static const _k = 'menu_style_new';
  static final notifier = ValueNotifier<bool>(true);
  static bool get isNew => notifier.value;

  static Future<void> load() async {
    try {
      notifier.value = (await SharedPreferences.getInstance()).getBool(_k) ?? true;
    } catch (_) {}
  }

  static Future<void> set(bool v) async {
    notifier.value = v;
    try {
      await (await SharedPreferences.getInstance()).setBool(_k, v);
    } catch (_) {}
  }

  /// Entries the new menu hides because they are tabs of another page now — only when that page (the map value) is visible.
  static const Map<String, String> hiddenUnder = {
    // phase 1: the Reports center holds them
    'reports_hub': 'reports',
    'smart_alerts': 'reports',
    'analytics_dashboard': 'reports',
    'data_quality': 'reports',
    'audit_trail': 'reports',
    'daily_memo_report': 'reports',
    'employee_documents_expiry': 'reports',
    'point_attendance_report': 'reports',
    'violations': 'reports',
    'site_onboarding_reports': 'reports',
  };
}

/// The drawer list for the chosen menu: in the new menu, entries that are tabs of a visible page are left out.
List<T> menuEntries<T>(List<T> visible, String Function(T) keyOf) {
  if (!MenuLayout.isNew) return visible;
  final keys = visible.map(keyOf).toSet();
  return visible.where((m) {
    final host = MenuLayout.hiddenUnder[keyOf(m)];
    return host == null || !keys.contains(host);
  }).toList();
}
