import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings_service.dart';

/// 🚌 إعدادات إسناد الباصات
///
/// تتحكّم في **أيّ مسمّيات وظيفيّة** تظهر كمرشّحين عند ربط موظف بباص:
///   - كسائق (Bus Driver) — افتراضيّاً مسمّى "Bus Driver"
///   - كمساعد (Assistant) — قابل للتخصيص
///   - كموظف يستقلّ الباص — قابل للتخصيص
///
/// المسؤول يستطيع تخصيص هذه القائمة من شاشة الإعدادات.
///
/// **التخزين:** عبر `AppSettingsService` (Supabase + كاش محلّي)
class BusAssignmentSettings {
  BusAssignmentSettings._();
  static final instance = BusAssignmentSettings._();

  /// مفتاح الإعداد في Supabase + الكاش المحلّي.
  static const _kSettingKey = 'bus_assignment';

  // مفاتيح legacy (للهجرة فقط)
  static const _kLegacyDrivers = 'bus_eligible_drivers_v1';
  static const _kLegacyPassengers = 'bus_eligible_passengers_v1';

  Set<String> _driverIds = {};
  Set<String> _passengerIds = {};
  bool _loaded = false;
  bool _hasDriverCustom = false;
  bool _hasPassengerCustom = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    try {
      final v = await AppSettingsService.instance.getJson(_kSettingKey);
      if (v != null) {
        _readFromJson(v);
      } else {
        await _migrateLegacyKeys();
      }
    } catch (_) {
      _driverIds = {};
      _passengerIds = {};
    }
    _loaded = true;
  }

  Future<void> load() async => _ensureLoaded();

  void _readFromJson(Map<String, dynamic> v) {
    _hasDriverCustom = v['hasDriverCustom'] as bool? ?? false;
    _hasPassengerCustom = v['hasPassengerCustom'] as bool? ?? false;
    final d = v['driverIds'] as List?;
    _driverIds = d?.map((e) => e.toString()).toSet() ?? <String>{};
    final pa = v['passengerIds'] as List?;
    _passengerIds = pa?.map((e) => e.toString()).toSet() ?? <String>{};
  }

  Future<void> _migrateLegacyKeys() async {
    try {
      final p = await SharedPreferences.getInstance();
      final hasLegacy = p.containsKey(_kLegacyDrivers) ||
          p.containsKey(_kLegacyPassengers);
      if (!hasLegacy) return;
      final d = p.getStringList(_kLegacyDrivers);
      if (d != null) {
        _driverIds = d.toSet();
        _hasDriverCustom = true;
      }
      final pa = p.getStringList(_kLegacyPassengers);
      if (pa != null) {
        _passengerIds = pa.toSet();
        _hasPassengerCustom = true;
      }
      await _persist();
      await p.remove(_kLegacyDrivers);
      await p.remove(_kLegacyPassengers);
    } catch (_) {/* ignore */}
  }

  Future<void> _persist() async {
    await AppSettingsService.instance.setJson(_kSettingKey, {
      'driverIds': _driverIds.toList(),
      'passengerIds': _passengerIds.toList(),
      'hasDriverCustom': _hasDriverCustom,
      'hasPassengerCustom': _hasPassengerCustom,
    });
  }

  Set<String> get currentDrivers => Set.unmodifiable(_driverIds);
  Set<String> get currentPassengers => Set.unmodifiable(_passengerIds);
  bool get hasDriverCustom => _hasDriverCustom;
  bool get hasPassengerCustom => _hasPassengerCustom;

  Future<void> setDrivers(Set<String> ids) async {
    _driverIds = Set<String>.from(ids);
    _hasDriverCustom = true;
    await _persist();
  }

  Future<void> setPassengers(Set<String> ids) async {
    _passengerIds = Set<String>.from(ids);
    _hasPassengerCustom = true;
    await _persist();
  }

  Future<void> resetDrivers() async {
    _driverIds = {};
    _hasDriverCustom = false;
    await _persist();
  }

  Future<void> resetPassengers() async {
    _passengerIds = {};
    _hasPassengerCustom = false;
    await _persist();
  }

  /// هل المسمّى مؤهّل ليكون سائقاً؟
  /// `defaultDriverIds`: قائمة افتراضيّة (Bus Driver عادةً) تُستخدم إن لم يضع
  /// المسؤول إعداداً مخصّصاً.
  bool isEligibleDriver(String jobTitleId, Set<String> defaultDriverIds) {
    if (!_hasDriverCustom) {
      return defaultDriverIds.contains(jobTitleId);
    }
    return _driverIds.contains(jobTitleId);
  }

  /// هل المسمّى مؤهّل ليكون راكباً؟ (يستقلّ الباص)
  /// إن لم يضع المسؤول إعداداً مخصّصاً → كل المسمّيات مؤهّلة (true).
  bool isEligiblePassenger(String jobTitleId) {
    if (!_hasPassengerCustom) return true; // الكل
    return _passengerIds.contains(jobTitleId);
  }
}
