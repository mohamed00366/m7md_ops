import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../repositories/mock_repository.dart';

/// نطاق سياسة "تذكّرني"
enum RememberMeScope {
  allAccounts,
  includedOnly,
  excludedOnly,
}

extension RememberMeScopeX on RememberMeScope {
  String key() {
    switch (this) {
      case RememberMeScope.allAccounts:
        return 'all';
      case RememberMeScope.includedOnly:
        return 'include';
      case RememberMeScope.excludedOnly:
        return 'exclude';
    }
  }

  static RememberMeScope fromKey(String? k) {
    switch (k) {
      case 'include':
        return RememberMeScope.includedOnly;
      case 'exclude':
        return RememberMeScope.excludedOnly;
      case 'all':
      default:
        return RememberMeScope.allAccounts;
    }
  }
}

/// خيارات مدّة الجلسة
enum SessionDuration {
  hours8, // دوام واحد
  hours24, // يوم كامل (افتراضي)
  days7, // أسبوع
  days30, // شهر
}

extension SessionDurationX on SessionDuration {
  Duration toDuration() {
    switch (this) {
      case SessionDuration.hours8:
        return const Duration(hours: 8);
      case SessionDuration.hours24:
        return const Duration(hours: 24);
      case SessionDuration.days7:
        return const Duration(days: 7);
      case SessionDuration.days30:
        return const Duration(days: 30);
    }
  }

  String labelAr() {
    switch (this) {
      case SessionDuration.hours8:
        return '8 ساعات (دوام)';
      case SessionDuration.hours24:
        return '24 ساعة (يوم)';
      case SessionDuration.days7:
        return '7 أيّام (أسبوع)';
      case SessionDuration.days30:
        return '30 يوم (شهر)';
    }
  }

  String labelEn() {
    switch (this) {
      case SessionDuration.hours8:
        return '8 hours (shift)';
      case SessionDuration.hours24:
        return '24 hours (day)';
      case SessionDuration.days7:
        return '7 days (week)';
      case SessionDuration.days30:
        return '30 days';
    }
  }

  String key() {
    switch (this) {
      case SessionDuration.hours8:
        return 'h8';
      case SessionDuration.hours24:
        return 'h24';
      case SessionDuration.days7:
        return 'd7';
      case SessionDuration.days30:
        return 'd30';
    }
  }

  static SessionDuration fromKey(String? k) {
    switch (k) {
      case 'h8':
        return SessionDuration.hours8;
      case 'd7':
        return SessionDuration.days7;
      case 'd30':
        return SessionDuration.days30;
      case 'h24':
      default:
        return SessionDuration.hours24;
    }
  }
}

/// 🕐 إعدادات سياسة "تذكّرني" + الجلسات الطويلة
class SessionSettings extends ChangeNotifier {
  SessionSettings._();
  static final instance = SessionSettings._();

  // ===== Storage keys =====
  static const _kEnabled = 'session_remember_enabled_v1';
  static const _kDuration = 'session_remember_duration_v1';
  static const _kScope = 'session_remember_scope_v1';
  static const _kAccountIds = 'session_remember_account_ids_v1';
  static const _kJobTitleIds = 'session_remember_job_title_ids_v1';
  static const _kOverrides = 'session_remember_overrides_v1';
  static const _kInvalidateOnPwdChange =
      'session_remember_invalidate_pwd_v1';
  static const _kRequireFaceForFaceAccounts =
      'session_remember_face_required_v1';

  // ===== Defaults =====
  static const defaultEnabled = true;
  static const defaultDuration = SessionDuration.hours24;
  static const defaultScope = RememberMeScope.allAccounts;
  static const defaultInvalidateOnPwd = true;
  static const defaultRequireFaceForFace = true;

  // ===== State =====
  bool _enabled = defaultEnabled;
  SessionDuration _duration = defaultDuration;
  RememberMeScope _scope = defaultScope;
  Set<String> _accountIds = <String>{};
  Set<String> _jobTitleIds = <String>{};
  Map<String, bool> _overrides = <String, bool>{};
  bool _invalidateOnPasswordChange = defaultInvalidateOnPwd;
  bool _requireFaceForFaceAccounts = defaultRequireFaceForFace;
  bool _loaded = false;

  // ===== Getters =====
  bool get enabled => _enabled;
  SessionDuration get duration => _duration;
  RememberMeScope get scope => _scope;
  Set<String> get accountIds => Set.unmodifiable(_accountIds);
  Set<String> get jobTitleIds => Set.unmodifiable(_jobTitleIds);
  Map<String, bool> get overrides => Map.unmodifiable(_overrides);
  bool get invalidateOnPasswordChange => _invalidateOnPasswordChange;
  bool get requireFaceForFaceAccounts => _requireFaceForFaceAccounts;
  bool get isLoaded => _loaded;

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

  /// هل يُسمح للحساب بميزة "تذكّرني"؟
  bool isAllowedFor(String accountId) {
    final override = _overrides[accountId];
    if (override != null) return override;
    if (!_enabled) return false;
    switch (_scope) {
      case RememberMeScope.allAccounts:
        return true;
      case RememberMeScope.includedOnly:
        return _matchesSelection(accountId);
      case RememberMeScope.excludedOnly:
        return !_matchesSelection(accountId);
    }
  }

  // ===== Load / Save =====
  Future<void> load() async {
    if (_loaded) return;
    try {
      final p = await SharedPreferences.getInstance();
      _enabled = p.getBool(_kEnabled) ?? defaultEnabled;
      _duration =
          SessionDurationX.fromKey(p.getString(_kDuration));
      _scope = RememberMeScopeX.fromKey(p.getString(_kScope));
      _accountIds =
          (p.getStringList(_kAccountIds) ?? const []).toSet();
      _jobTitleIds =
          (p.getStringList(_kJobTitleIds) ?? const []).toSet();
      _invalidateOnPasswordChange =
          p.getBool(_kInvalidateOnPwdChange) ??
              defaultInvalidateOnPwd;
      _requireFaceForFaceAccounts =
          p.getBool(_kRequireFaceForFaceAccounts) ??
              defaultRequireFaceForFace;

      final raw = p.getStringList(_kOverrides) ?? const [];
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
    } catch (_) {}
    _loaded = true;
  }

  Future<void> setEnabled(bool v) async {
    _enabled = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kEnabled, v);
    notifyListeners();
  }

  Future<void> setDuration(SessionDuration d) async {
    _duration = d;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kDuration, d.key());
    notifyListeners();
  }

  Future<void> setScope(RememberMeScope s) async {
    _scope = s;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kScope, s.key());
    notifyListeners();
  }

  Future<void> setAccountIds(Set<String> ids) async {
    _accountIds = Set.from(ids);
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kAccountIds, _accountIds.toList());
    notifyListeners();
  }

  Future<void> removeAccount(String id) async {
    _accountIds = _accountIds.where((x) => x != id).toSet();
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kAccountIds, _accountIds.toList());
    notifyListeners();
  }

  Future<void> setJobTitleIds(Set<String> ids) async {
    _jobTitleIds = Set.from(ids);
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kJobTitleIds, _jobTitleIds.toList());
    notifyListeners();
  }

  Future<void> removeJobTitle(String id) async {
    _jobTitleIds = _jobTitleIds.where((x) => x != id).toSet();
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kJobTitleIds, _jobTitleIds.toList());
    notifyListeners();
  }

  Future<void> setOverride(String accountId, bool? enabled) async {
    if (enabled == null) {
      _overrides.remove(accountId);
    } else {
      _overrides[accountId] = enabled;
    }
    final p = await SharedPreferences.getInstance();
    await p.setStringList(
      _kOverrides,
      _overrides.entries
          .map((e) => '${e.key}|${e.value ? 'on' : 'off'}')
          .toList(),
    );
    notifyListeners();
  }

  Future<void> setInvalidateOnPasswordChange(bool v) async {
    _invalidateOnPasswordChange = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kInvalidateOnPwdChange, v);
    notifyListeners();
  }

  Future<void> setRequireFaceForFaceAccounts(bool v) async {
    _requireFaceForFaceAccounts = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kRequireFaceForFaceAccounts, v);
    notifyListeners();
  }

  Future<void> resetToDefaults() async {
    final p = await SharedPreferences.getInstance();
    for (final k in [
      _kEnabled,
      _kDuration,
      _kScope,
      _kAccountIds,
      _kJobTitleIds,
      _kOverrides,
      _kInvalidateOnPwdChange,
      _kRequireFaceForFaceAccounts,
    ]) {
      await p.remove(k);
    }
    _enabled = defaultEnabled;
    _duration = defaultDuration;
    _scope = defaultScope;
    _accountIds = <String>{};
    _jobTitleIds = <String>{};
    _overrides = <String, bool>{};
    _invalidateOnPasswordChange = defaultInvalidateOnPwd;
    _requireFaceForFaceAccounts = defaultRequireFaceForFace;
    notifyListeners();
  }
}
