import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../repositories/mock_repository.dart';
import 'app_settings_service.dart';

/// نطاق تطبيق سياسة تتبّع الموقع
enum DriverTrackingScope {
  allDrivers,
  includedOnly,
  excludedOnly,
}

extension DriverTrackingScopeX on DriverTrackingScope {
  String key() {
    switch (this) {
      case DriverTrackingScope.allDrivers:
        return 'all';
      case DriverTrackingScope.includedOnly:
        return 'include';
      case DriverTrackingScope.excludedOnly:
        return 'exclude';
    }
  }

  static DriverTrackingScope fromKey(String? k) {
    switch (k) {
      case 'include':
        return DriverTrackingScope.includedOnly;
      case 'exclude':
        return DriverTrackingScope.excludedOnly;
      case 'all':
      default:
        return DriverTrackingScope.allDrivers;
    }
  }
}

enum DriverTrackingReason {
  overrideEnforced,
  overrideExempt,
  globallyDisabled,
  scopeAll,
  accountListed,
  jobTitleListed,
  notInIncludeList,
  accountExcluded,
  jobTitleExcluded,
  notInExcludeList,
}

class DriverTrackingDecision {
  final bool tracks;
  final DriverTrackingReason reason;
  final String? matchedJobTitleId;
  const DriverTrackingDecision({
    required this.tracks,
    required this.reason,
    this.matchedJobTitleId,
  });

  String reasonLabel({required bool isAr}) {
    switch (reason) {
      case DriverTrackingReason.overrideEnforced:
        return isAr ? 'تجاوز فردي: تفعيل' : 'Override: enforced';
      case DriverTrackingReason.overrideExempt:
        return isAr ? 'تجاوز فردي: إعفاء' : 'Override: exempt';
      case DriverTrackingReason.globallyDisabled:
        return isAr ? 'السياسة معطّلة' : 'Policy off';
      case DriverTrackingReason.scopeAll:
        return isAr ? 'النطاق: الكلّ' : 'Scope: all';
      case DriverTrackingReason.accountListed:
        return isAr ? 'الحساب في القائمة' : 'Account listed';
      case DriverTrackingReason.jobTitleListed:
        return isAr ? 'مسمّاه في القائمة' : 'Job title listed';
      case DriverTrackingReason.notInIncludeList:
        return isAr ? 'ليس ضمن المختارين' : 'Not in include list';
      case DriverTrackingReason.accountExcluded:
        return isAr ? 'مُعفى يدوياً' : 'Account exempted';
      case DriverTrackingReason.jobTitleExcluded:
        return isAr
            ? 'مسمّاه ضمن المُعفاة'
            : 'Job title exempted';
      case DriverTrackingReason.notInExcludeList:
        return isAr ? 'ليس ضمن المُعفاة' : 'Not in exempt list';
    }
  }
}

/// 📍 إعدادات تتبّع موقع السائقين
///
/// تتحكّم في:
///   • enabled: تفعيل التتبّع عامّ
///   • intervalMinutes: فترة الإرسال (1/5/10/15)
///   • autoStartOnLogin: ابدأ تلقائيّاً
///   • workingHoursOnly: ضمن ساعات الدوام فقط
///   • نطاق + قوائم (مثل بقيّة السياسات)
///   • retentionDays: مدّة حفظ السجلّ (افتراضي 30 يوم)
///
/// **التخزين:** عبر `AppSettingsService` (Supabase + كاش محلّي)
///   - Supabase: جدول `app_settings`، key=`driver_tracking`
class DriverTrackingSettings extends ChangeNotifier {
  DriverTrackingSettings._();
  static final instance = DriverTrackingSettings._();

  /// مفتاح الإعداد في Supabase + الكاش المحلّي.
  static const _kSettingKey = 'driver_tracking';

  // مفاتيح legacy (للهجرة فقط)
  static const _kLegacyEnabled = 'driver_tracking_enabled_v1';
  static const _kLegacyInterval = 'driver_tracking_interval_min_v1';
  static const _kLegacyAutoStart = 'driver_tracking_auto_start_v1';
  static const _kLegacyWorkingOnly = 'driver_tracking_working_only_v1';
  static const _kLegacyWorkStart = 'driver_tracking_work_start_v1';
  static const _kLegacyWorkEnd = 'driver_tracking_work_end_v1';
  static const _kLegacyPauseIdle = 'driver_tracking_pause_idle_v1';
  static const _kLegacyIdleThreshold = 'driver_tracking_idle_threshold_v1';
  static const _kLegacyScope = 'driver_tracking_scope_v1';
  static const _kLegacyAccountIds = 'driver_tracking_account_ids_v1';
  static const _kLegacyJobTitleIds = 'driver_tracking_job_title_ids_v1';
  static const _kLegacyOverrides = 'driver_tracking_overrides_v1';
  static const _kLegacyRetentionDays = 'driver_tracking_retention_days_v1';
  static const _kLegacyHistoryEnabled = 'driver_tracking_history_enabled_v1';

  // ===== Defaults =====
  static const defaultEnabled = true;
  static const defaultInterval = 5;
  static const defaultAutoStart = true;
  static const defaultWorkingOnly = false;
  static const defaultWorkStart = 6;
  static const defaultWorkEnd = 22;
  static const defaultPauseIdle = false;
  static const defaultIdleThreshold = 30;
  static const defaultScope = DriverTrackingScope.allDrivers;
  static const defaultRetentionDays = 30;
  static const defaultHistoryEnabled = true;

  // ===== State =====
  bool _enabled = defaultEnabled;
  int _intervalMinutes = defaultInterval;
  bool _autoStart = defaultAutoStart;
  bool _workingOnly = defaultWorkingOnly;
  int _workStart = defaultWorkStart;
  int _workEnd = defaultWorkEnd;
  bool _pauseIdle = defaultPauseIdle;
  int _idleThreshold = defaultIdleThreshold;
  DriverTrackingScope _scope = defaultScope;
  Set<String> _accountIds = <String>{};
  Set<String> _jobTitleIds = <String>{};
  Map<String, bool> _overrides = <String, bool>{};
  int _retentionDays = defaultRetentionDays;
  bool _historyEnabled = defaultHistoryEnabled;
  bool _loaded = false;

  // ===== Getters =====
  bool get enabled => _enabled;
  int get intervalMinutes => _intervalMinutes;
  bool get autoStart => _autoStart;
  bool get workingHoursOnly => _workingOnly;
  int get workStartHour => _workStart;
  int get workEndHour => _workEnd;
  bool get pauseWhenIdle => _pauseIdle;
  int get idleThresholdMinutes => _idleThreshold;
  DriverTrackingScope get scope => _scope;
  Set<String> get accountIds => Set.unmodifiable(_accountIds);
  Set<String> get jobTitleIds => Set.unmodifiable(_jobTitleIds);
  Map<String, bool> get overrides => Map.unmodifiable(_overrides);
  int get retentionDays => _retentionDays;
  bool get historyEnabled => _historyEnabled;
  bool get isLoaded => _loaded;

  /// هل الوقت الحالي ضمن ساعات الدوام؟
  bool get isWithinWorkingHours {
    if (!_workingOnly) return true;
    final now = DateTime.now();
    final hour = now.hour;
    if (_workStart < _workEnd) {
      return hour >= _workStart && hour < _workEnd;
    }
    return hour >= _workStart || hour < _workEnd;
  }

  bool? overrideFor(String accountId) => _overrides[accountId];

  String? _jobTitleIdOf(String accountId) {
    final repo = MockRepository();
    try {
      final acc = repo.accounts.firstWhere((a) => a.id == accountId);
      final empId = acc.employeeId;
      if (empId == null) return null;
      final emp = repo.employees.firstWhere((e) => e.id == empId);
      return emp.jobTitleId;
    } catch (_) {
      return null;
    }
  }

  bool _matchesSelection(String accountId) {
    if (_accountIds.contains(accountId)) return true;
    if (_jobTitleIds.isNotEmpty) {
      final jt = _jobTitleIdOf(accountId);
      if (jt != null && _jobTitleIds.contains(jt)) return true;
    }
    return false;
  }

  /// هل يجب تتبّع هذا الحساب؟
  bool appliesTo(String accountId) {
    final override = _overrides[accountId];
    if (override != null) return override;
    if (!_enabled) return false;
    switch (_scope) {
      case DriverTrackingScope.allDrivers:
        return true;
      case DriverTrackingScope.includedOnly:
        return _matchesSelection(accountId);
      case DriverTrackingScope.excludedOnly:
        return !_matchesSelection(accountId);
    }
  }

  DriverTrackingDecision decisionFor(String accountId) {
    final override = _overrides[accountId];
    if (override == true) {
      return const DriverTrackingDecision(
          tracks: true, reason: DriverTrackingReason.overrideEnforced);
    }
    if (override == false) {
      return const DriverTrackingDecision(
          tracks: false, reason: DriverTrackingReason.overrideExempt);
    }
    if (!_enabled) {
      return const DriverTrackingDecision(
          tracks: false,
          reason: DriverTrackingReason.globallyDisabled);
    }
    switch (_scope) {
      case DriverTrackingScope.allDrivers:
        return const DriverTrackingDecision(
            tracks: true, reason: DriverTrackingReason.scopeAll);
      case DriverTrackingScope.includedOnly:
        if (_accountIds.contains(accountId)) {
          return const DriverTrackingDecision(
              tracks: true,
              reason: DriverTrackingReason.accountListed);
        }
        final jt = _jobTitleIdOf(accountId);
        if (jt != null && _jobTitleIds.contains(jt)) {
          return DriverTrackingDecision(
              tracks: true,
              reason: DriverTrackingReason.jobTitleListed,
              matchedJobTitleId: jt);
        }
        return const DriverTrackingDecision(
            tracks: false,
            reason: DriverTrackingReason.notInIncludeList);
      case DriverTrackingScope.excludedOnly:
        if (_accountIds.contains(accountId)) {
          return const DriverTrackingDecision(
              tracks: false,
              reason: DriverTrackingReason.accountExcluded);
        }
        final jt = _jobTitleIdOf(accountId);
        if (jt != null && _jobTitleIds.contains(jt)) {
          return DriverTrackingDecision(
              tracks: false,
              reason: DriverTrackingReason.jobTitleExcluded,
              matchedJobTitleId: jt);
        }
        return const DriverTrackingDecision(
            tracks: true,
            reason: DriverTrackingReason.notInExcludeList);
    }
  }

  // ============================================================
  // تحميل: 1) Supabase 2) كاش 3) Legacy migration
  // ============================================================
  Future<void> load() async {
    if (_loaded) return;
    try {
      final v = await AppSettingsService.instance.getJson(_kSettingKey);
      if (v != null) {
        _readFromJson(v);
      } else {
        await _migrateLegacyKeys();
      }
    } catch (_) {/* keep defaults */}
    _loaded = true;
  }

  void _readFromJson(Map<String, dynamic> v) {
    _enabled = v['enabled'] as bool? ?? defaultEnabled;
    _intervalMinutes =
        (v['intervalMinutes'] as num?)?.toInt() ?? defaultInterval;
    _autoStart = v['autoStart'] as bool? ?? defaultAutoStart;
    _workingOnly = v['workingOnly'] as bool? ?? defaultWorkingOnly;
    _workStart = (v['workStart'] as num?)?.toInt() ?? defaultWorkStart;
    _workEnd = (v['workEnd'] as num?)?.toInt() ?? defaultWorkEnd;
    _pauseIdle = v['pauseIdle'] as bool? ?? defaultPauseIdle;
    _idleThreshold =
        (v['idleThreshold'] as num?)?.toInt() ?? defaultIdleThreshold;
    _scope = DriverTrackingScopeX.fromKey(v['scope'] as String?);
    _accountIds = (v['accountIds'] as List?)
            ?.map((e) => e.toString())
            .toSet() ??
        <String>{};
    _jobTitleIds = (v['jobTitleIds'] as List?)
            ?.map((e) => e.toString())
            .toSet() ??
        <String>{};
    final ov = v['overrides'] as Map?;
    _overrides = <String, bool>{};
    if (ov != null) {
      ov.forEach((k, val) {
        if (val is bool) _overrides[k.toString()] = val;
      });
    }
    _retentionDays =
        (v['retentionDays'] as num?)?.toInt() ?? defaultRetentionDays;
    _historyEnabled =
        v['historyEnabled'] as bool? ?? defaultHistoryEnabled;
  }

  Future<void> _migrateLegacyKeys() async {
    try {
      final p = await SharedPreferences.getInstance();
      final hasLegacy = p.containsKey(_kLegacyEnabled) ||
          p.containsKey(_kLegacyInterval) ||
          p.containsKey(_kLegacyAccountIds);
      if (!hasLegacy) return;
      _enabled = p.getBool(_kLegacyEnabled) ?? defaultEnabled;
      _intervalMinutes = p.getInt(_kLegacyInterval) ?? defaultInterval;
      _autoStart = p.getBool(_kLegacyAutoStart) ?? defaultAutoStart;
      _workingOnly = p.getBool(_kLegacyWorkingOnly) ?? defaultWorkingOnly;
      _workStart = p.getInt(_kLegacyWorkStart) ?? defaultWorkStart;
      _workEnd = p.getInt(_kLegacyWorkEnd) ?? defaultWorkEnd;
      _pauseIdle = p.getBool(_kLegacyPauseIdle) ?? defaultPauseIdle;
      _idleThreshold =
          p.getInt(_kLegacyIdleThreshold) ?? defaultIdleThreshold;
      _scope = DriverTrackingScopeX.fromKey(p.getString(_kLegacyScope));
      _accountIds =
          (p.getStringList(_kLegacyAccountIds) ?? const []).toSet();
      _jobTitleIds =
          (p.getStringList(_kLegacyJobTitleIds) ?? const []).toSet();
      _retentionDays =
          p.getInt(_kLegacyRetentionDays) ?? defaultRetentionDays;
      _historyEnabled =
          p.getBool(_kLegacyHistoryEnabled) ?? defaultHistoryEnabled;
      final raw = p.getStringList(_kLegacyOverrides) ?? const [];
      _overrides = {};
      for (final r in raw) {
        final i = r.indexOf('|');
        if (i <= 0) continue;
        final id = r.substring(0, i);
        final flag = r.substring(i + 1);
        if (flag == 'on') {
          _overrides[id] = true;
        } else if (flag == 'off') {
          _overrides[id] = false;
        }
      }
      // احفظ في الصيغة الجديدة
      await _persist();
      // امسح المفاتيح القديمة
      for (final k in [
        _kLegacyEnabled, _kLegacyInterval, _kLegacyAutoStart,
        _kLegacyWorkingOnly, _kLegacyWorkStart, _kLegacyWorkEnd,
        _kLegacyPauseIdle, _kLegacyIdleThreshold, _kLegacyScope,
        _kLegacyAccountIds, _kLegacyJobTitleIds, _kLegacyOverrides,
        _kLegacyRetentionDays, _kLegacyHistoryEnabled,
      ]) {
        await p.remove(k);
      }
    } catch (_) {/* ignore */}
  }

  Future<void> _persist() async {
    await AppSettingsService.instance.setJson(_kSettingKey, {
      'enabled': _enabled,
      'intervalMinutes': _intervalMinutes,
      'autoStart': _autoStart,
      'workingOnly': _workingOnly,
      'workStart': _workStart,
      'workEnd': _workEnd,
      'pauseIdle': _pauseIdle,
      'idleThreshold': _idleThreshold,
      'scope': _scope.key(),
      'accountIds': _accountIds.toList(),
      'jobTitleIds': _jobTitleIds.toList(),
      'overrides': _overrides,
      'retentionDays': _retentionDays,
      'historyEnabled': _historyEnabled,
    });
  }

  // ===== Setters =====
  Future<void> setEnabled(bool v) async {
    _enabled = v;
    await _persist();
    notifyListeners();
  }

  Future<void> setIntervalMinutes(int v) async {
    _intervalMinutes = v.clamp(1, 60);
    await _persist();
    notifyListeners();
  }

  Future<void> setAutoStart(bool v) async {
    _autoStart = v;
    await _persist();
    notifyListeners();
  }

  Future<void> setWorkingOnly(bool v) async {
    _workingOnly = v;
    await _persist();
    notifyListeners();
  }

  Future<void> setWorkStartHour(int h) async {
    _workStart = h.clamp(0, 23);
    await _persist();
    notifyListeners();
  }

  Future<void> setWorkEndHour(int h) async {
    _workEnd = h.clamp(0, 23);
    await _persist();
    notifyListeners();
  }

  Future<void> setPauseWhenIdle(bool v) async {
    _pauseIdle = v;
    await _persist();
    notifyListeners();
  }

  Future<void> setIdleThresholdMinutes(int v) async {
    _idleThreshold = v.clamp(5, 240);
    await _persist();
    notifyListeners();
  }

  Future<void> setScope(DriverTrackingScope s) async {
    _scope = s;
    await _persist();
    notifyListeners();
  }

  Future<void> setAccountIds(Set<String> ids) async {
    _accountIds = Set.from(ids);
    await _persist();
    notifyListeners();
  }

  Future<void> addAccount(String id) async {
    if (_accountIds.contains(id)) return;
    _accountIds = {..._accountIds, id};
    await _persist();
    notifyListeners();
  }

  Future<void> removeAccount(String id) async {
    _accountIds = _accountIds.where((x) => x != id).toSet();
    await _persist();
    notifyListeners();
  }

  Future<void> setJobTitleIds(Set<String> ids) async {
    _jobTitleIds = Set.from(ids);
    await _persist();
    notifyListeners();
  }

  Future<void> addJobTitle(String id) async {
    if (_jobTitleIds.contains(id)) return;
    _jobTitleIds = {..._jobTitleIds, id};
    await _persist();
    notifyListeners();
  }

  Future<void> removeJobTitle(String id) async {
    _jobTitleIds = _jobTitleIds.where((x) => x != id).toSet();
    await _persist();
    notifyListeners();
  }

  Future<void> setOverride(String accountId, bool? enabled) async {
    if (enabled == null) {
      _overrides.remove(accountId);
    } else {
      _overrides[accountId] = enabled;
    }
    await _persist();
    notifyListeners();
  }

  Future<void> setRetentionDays(int v) async {
    _retentionDays = v.clamp(1, 365);
    await _persist();
    notifyListeners();
  }

  Future<void> setHistoryEnabled(bool v) async {
    _historyEnabled = v;
    await _persist();
    notifyListeners();
  }

  Future<void> resetToDefaults() async {
    _enabled = defaultEnabled;
    _intervalMinutes = defaultInterval;
    _autoStart = defaultAutoStart;
    _workingOnly = defaultWorkingOnly;
    _workStart = defaultWorkStart;
    _workEnd = defaultWorkEnd;
    _pauseIdle = defaultPauseIdle;
    _idleThreshold = defaultIdleThreshold;
    _scope = defaultScope;
    _accountIds = <String>{};
    _jobTitleIds = <String>{};
    _overrides = <String, bool>{};
    _retentionDays = defaultRetentionDays;
    _historyEnabled = defaultHistoryEnabled;
    await _persist();
    notifyListeners();
  }
}
