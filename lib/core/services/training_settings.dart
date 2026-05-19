import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings_service.dart';

/// 📜 إعدادات موديول التدريب
///
/// تتحكّم في:
///   - daysBeforeWarning: قبل كم يوم نُحذِّر من انتهاء صلاحيّة دورة (افتراضي 30)
///   - defaultValidityMonths: مدّة الصلاحيّة الافتراضيّة عند إنشاء دورة جديدة
///   - blockRosterOnExpired: هل نمنع إضافة موظف لروستر إن انتهت دورة إلزاميّة؟
///   - mandatoryCategories: تصنيفات إلزاميّة افتراضيّة لكل الموظفين
///
/// **التخزين:** عبر `AppSettingsService` (Supabase + كاش محلّي)
class TrainingSettings extends ChangeNotifier {
  TrainingSettings._();
  static final instance = TrainingSettings._();

  /// مفتاح الإعداد في Supabase + الكاش المحلّي.
  static const _kSettingKey = 'training';

  // مفاتيح legacy (للهجرة فقط)
  static const _kLegacyDaysWarning = 'training_days_before_warning_v1';
  static const _kLegacyDefaultValidity =
      'training_default_validity_months_v1';
  static const _kLegacyBlockRosterOnExpired =
      'training_block_roster_on_expired_v1';
  static const _kLegacyMandatoryCategories =
      'training_mandatory_categories_v1';

  static const defaultDaysWarning = 30;
  static const defaultValidityMonths = 12;
  static const defaultBlockRosterOnExpired = false;

  int _daysWarning = defaultDaysWarning;
  int _defaultValidityMonths = defaultValidityMonths;
  bool _blockRosterOnExpired = defaultBlockRosterOnExpired;
  Set<String> _mandatoryCategories = {};
  bool _loaded = false;

  int get daysWarning => _daysWarning;
  int get defaultValidityMonthsValue => _defaultValidityMonths;
  bool get blockRosterOnExpired => _blockRosterOnExpired;
  Set<String> get mandatoryCategories => Set.unmodifiable(_mandatoryCategories);
  bool get isLoaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final v = await AppSettingsService.instance.getJson(_kSettingKey);
      if (v != null) {
        _readFromJson(v);
      } else {
        await _migrateLegacyKeys();
      }
    } catch (_) {
      // keep defaults
    }
    _loaded = true;
  }

  void _readFromJson(Map<String, dynamic> v) {
    _daysWarning = (v['daysWarning'] as num?)?.toInt() ?? defaultDaysWarning;
    _defaultValidityMonths =
        (v['defaultValidityMonths'] as num?)?.toInt() ?? defaultValidityMonths;
    _blockRosterOnExpired =
        v['blockRosterOnExpired'] as bool? ?? defaultBlockRosterOnExpired;
    final rawCats = v['mandatoryCategories'] as List?;
    _mandatoryCategories =
        rawCats?.map((e) => e.toString()).toSet() ?? <String>{};
  }

  Future<void> _migrateLegacyKeys() async {
    try {
      final p = await SharedPreferences.getInstance();
      final hasLegacy = p.containsKey(_kLegacyDaysWarning) ||
          p.containsKey(_kLegacyDefaultValidity) ||
          p.containsKey(_kLegacyBlockRosterOnExpired) ||
          p.containsKey(_kLegacyMandatoryCategories);
      if (!hasLegacy) return;
      _daysWarning = p.getInt(_kLegacyDaysWarning) ?? defaultDaysWarning;
      _defaultValidityMonths =
          p.getInt(_kLegacyDefaultValidity) ?? defaultValidityMonths;
      _blockRosterOnExpired = p.getBool(_kLegacyBlockRosterOnExpired) ??
          defaultBlockRosterOnExpired;
      _mandatoryCategories =
          (p.getStringList(_kLegacyMandatoryCategories) ?? const [])
              .toSet();
      await _persist();
      await p.remove(_kLegacyDaysWarning);
      await p.remove(_kLegacyDefaultValidity);
      await p.remove(_kLegacyBlockRosterOnExpired);
      await p.remove(_kLegacyMandatoryCategories);
    } catch (_) {/* ignore */}
  }

  Future<void> _persist() async {
    await AppSettingsService.instance.setJson(_kSettingKey, {
      'daysWarning': _daysWarning,
      'defaultValidityMonths': _defaultValidityMonths,
      'blockRosterOnExpired': _blockRosterOnExpired,
      'mandatoryCategories': _mandatoryCategories.toList(),
    });
  }

  Future<void> setDaysWarning(int days) async {
    _daysWarning = days.clamp(1, 365);
    await _persist();
    notifyListeners();
  }

  Future<void> setDefaultValidityMonths(int months) async {
    _defaultValidityMonths = months.clamp(0, 120);
    await _persist();
    notifyListeners();
  }

  Future<void> setBlockRosterOnExpired(bool v) async {
    _blockRosterOnExpired = v;
    await _persist();
    notifyListeners();
  }

  Future<void> toggleMandatoryCategory(String key) async {
    if (_mandatoryCategories.contains(key)) {
      _mandatoryCategories.remove(key);
    } else {
      _mandatoryCategories.add(key);
    }
    await _persist();
    notifyListeners();
  }

  Future<void> resetToDefaults() async {
    _daysWarning = defaultDaysWarning;
    _defaultValidityMonths = defaultValidityMonths;
    _blockRosterOnExpired = defaultBlockRosterOnExpired;
    _mandatoryCategories = {};
    await _persist();
    notifyListeners();
  }
}
