import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings_service.dart';

/// 📋 إعدادات تصفية الموظّفين عند إضافتهم لروستر — مزامَنة مع Supabase.
///
/// **التخزين:** Supabase `app_settings` (key=`roster_employee_filter`)
/// + كاش محلّي. عبر `AppSettingsService`.
class RosterEmployeeFilterSettings {
  RosterEmployeeFilterSettings._();
  static final instance = RosterEmployeeFilterSettings._();

  static const _kSettingKey = 'roster_employee_filter';

  Set<String> _allowedJobTitleIds = {};
  bool _onlyActive = true;
  bool _loaded = false;
  bool _hasCustomSetting = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    try {
      final v = await AppSettingsService.instance.getJson(_kSettingKey);
      if (v != null) {
        final list = (v['allowedJobTitleIds'] as List?) ?? const [];
        _allowedJobTitleIds = list.map((e) => e.toString()).toSet();
        _onlyActive = v['onlyActive'] as bool? ?? true;
        _hasCustomSetting = v['hasCustom'] as bool? ?? false;
      } else {
        await _migrateLegacyKeys();
      }
    } catch (_) {/* defaults */}
    _loaded = true;
  }

  Future<void> _migrateLegacyKeys() async {
    try {
      final p = await SharedPreferences.getInstance();
      final list = p.getStringList('roster_employee_allowed_titles_v1');
      if (list != null) {
        _allowedJobTitleIds = list.toSet();
        _hasCustomSetting = true;
      }
      _onlyActive = p.getBool('roster_employee_only_active_v1') ?? true;
      if (list != null) {
        _lastSyncedToCloud = await _persist();
        await p.remove('roster_employee_allowed_titles_v1');
        await p.remove('roster_employee_only_active_v1');
      }
    } catch (_) {/* ignore */}
  }

  /// 🆕 يُرجع نتيجة الـ Supabase: true لو وصل للسحابة، false محلّي فقط.
  Future<bool> _persist() async {
    return AppSettingsService.instance.setJson(_kSettingKey, {
      'allowedJobTitleIds': _allowedJobTitleIds.toList(),
      'onlyActive': _onlyActive,
      'hasCustom': _hasCustomSetting,
    });
  }

  /// آخر حالة مزامنة معروفة بعد آخر setX(). للـ UI.
  bool _lastSyncedToCloud = false;
  bool get lastSyncedToCloud => _lastSyncedToCloud;

  Future<void> load() async => _ensureLoaded();

  Set<String> get allowedJobTitleIds =>
      Set.unmodifiable(_allowedJobTitleIds);

  bool get hasCustom => _hasCustomSetting;
  bool get onlyActive => _onlyActive;

  Future<bool> toggle(String jobTitleId) async {
    await _ensureLoaded();
    final added = !_allowedJobTitleIds.contains(jobTitleId);
    if (added) {
      _allowedJobTitleIds.add(jobTitleId);
    } else {
      _allowedJobTitleIds.remove(jobTitleId);
    }
    _hasCustomSetting = true;
    _lastSyncedToCloud = await _persist();
    return added;
  }

  Future<void> setAllowed(Set<String> ids) async {
    await _ensureLoaded();
    _allowedJobTitleIds = Set<String>.from(ids);
    _hasCustomSetting = true;
    _lastSyncedToCloud = await _persist();
  }

  Future<void> setOnlyActive(bool value) async {
    await _ensureLoaded();
    _onlyActive = value;
    _lastSyncedToCloud = await _persist();
  }

  Future<void> resetToDefault() async {
    _allowedJobTitleIds = {};
    _hasCustomSetting = false;
    _onlyActive = true;
    _loaded = true;
    await AppSettingsService.instance.delete(_kSettingKey);
  }

  bool isJobTitleAllowed(String? jobTitleId) {
    if (!_hasCustomSetting) return true;
    if (jobTitleId == null) return false;
    return _allowedJobTitleIds.contains(jobTitleId);
  }
}
