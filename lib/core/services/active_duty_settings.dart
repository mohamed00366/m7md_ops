import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../repositories/mock_repository.dart';
import 'app_settings_service.dart';

/// 🚧 سياسة "التَطبيق يَعمَل فَقَط على رَأس العَمَل"
///
/// إذا فُعِّلَت → الموظَّفون المَشمولون لا يَستَطيعون الدُخول إذا:
///   - كانوا في إجازة مُعتَمَدة سارِية اليَوم
///   - حِسابهم/مَوظَّفهم مُعَلَّق (inactive/suspended)
///
/// قابِلة لِلتَهيئة:
///   - تَفعيل/إيقاف
///   - نِطاق: كُلّ الحِسابات / مُسَمَّيات وَظيفيّة مُحَدَّدة
///   - رِسالة مُخَصَّصة لِكُلّ حالة
///   - أَدوار يُسمَح لَها بِالتَجاوُز (Admin/Super Admin افتِراضيّاً)
enum ActiveDutyScope {
  allAccounts,
  includedOnly,
  excludedOnly,
}

extension ActiveDutyScopeX on ActiveDutyScope {
  String get key {
    switch (this) {
      case ActiveDutyScope.allAccounts:
        return 'all';
      case ActiveDutyScope.includedOnly:
        return 'included';
      case ActiveDutyScope.excludedOnly:
        return 'excluded';
    }
  }

  static ActiveDutyScope fromKey(String? k) {
    switch (k) {
      case 'included':
        return ActiveDutyScope.includedOnly;
      case 'excluded':
        return ActiveDutyScope.excludedOnly;
      default:
        return ActiveDutyScope.allAccounts;
    }
  }
}

class ActiveDutySettings extends ChangeNotifier {
  ActiveDutySettings._();
  static final instance = ActiveDutySettings._();

  /// مفتاح الإعداد في Supabase + الكاش المحلّي.
  static const _kSettingKey = 'active_duty';

  // مفاتيح legacy (للهجرة فقط)
  static const _kLegacyEnabled = 'active_duty.enabled';
  static const _kLegacyScope = 'active_duty.scope';
  static const _kLegacyJobTitles = 'active_duty.job_titles';
  static const _kLegacyAccounts = 'active_duty.accounts';
  static const _kLegacyBypassRoles = 'active_duty.bypass_roles';
  static const _kLegacyMsgLeaveAr = 'active_duty.msg.leave.ar';
  static const _kLegacyMsgLeaveEn = 'active_duty.msg.leave.en';
  static const _kLegacyMsgSuspendedAr = 'active_duty.msg.suspended.ar';
  static const _kLegacyMsgSuspendedEn = 'active_duty.msg.suspended.en';
  static const _kLegacyCheckSuspension = 'active_duty.check_suspension';
  static const _kLegacyCheckLeave = 'active_duty.check_leave';

  // ===== Defaults =====
  static const defaultEnabled = false;
  static const defaultScope = ActiveDutyScope.allAccounts;
  static const defaultBypassRoles = ['super_admin', 'admin'];
  static const defaultMsgLeaveAr =
      'التَطبيق يَعمَل فَقَط في حالة وُجودِك على رَأس العَمَل.\n'
      'أَنت حاليّاً في إجازة مُعتَمَدة. يُمكِنُك الدُخول بَعد عَودَتِك.';
  static const defaultMsgLeaveEn =
      'The app works only while you are on duty.\n'
      'You are currently on approved leave. Try again after you return.';
  static const defaultMsgSuspendedAr =
      'حِسابك مُعَلَّق حاليّاً.\nاِتَّصِل بِالموارِد البَشَريّة.';
  static const defaultMsgSuspendedEn =
      'Your account is currently suspended.\nContact HR.';

  // ===== State =====
  bool _enabled = defaultEnabled;
  ActiveDutyScope _scope = defaultScope;
  Set<String> _jobTitleIds = <String>{};
  Set<String> _accountIds = <String>{};
  Set<String> _bypassRoles = Set<String>.from(defaultBypassRoles);
  bool _checkSuspension = true;
  bool _checkLeave = true;
  String _msgLeaveAr = defaultMsgLeaveAr;
  String _msgLeaveEn = defaultMsgLeaveEn;
  String _msgSuspendedAr = defaultMsgSuspendedAr;
  String _msgSuspendedEn = defaultMsgSuspendedEn;
  bool _loaded = false;

  // ===== Getters =====
  bool get enabled => _enabled;
  ActiveDutyScope get scope => _scope;
  Set<String> get jobTitleIds => Set.unmodifiable(_jobTitleIds);
  Set<String> get accountIds => Set.unmodifiable(_accountIds);
  Set<String> get bypassRoles => Set.unmodifiable(_bypassRoles);
  bool get checkSuspension => _checkSuspension;
  bool get checkLeave => _checkLeave;
  String get messageLeaveAr => _msgLeaveAr;
  String get messageLeaveEn => _msgLeaveEn;
  String get messageSuspendedAr => _msgSuspendedAr;
  String get messageSuspendedEn => _msgSuspendedEn;
  bool get isLoaded => _loaded;

  // ===== Load/Save =====
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
    notifyListeners();
  }

  void _readFromJson(Map<String, dynamic> v) {
    _enabled = v['enabled'] as bool? ?? defaultEnabled;
    _scope = ActiveDutyScopeX.fromKey(v['scope']?.toString());
    final rawJt = v['jobTitleIds'] as List?;
    _jobTitleIds = rawJt?.map((e) => e.toString()).toSet() ?? <String>{};
    final rawAcc = v['accountIds'] as List?;
    _accountIds = rawAcc?.map((e) => e.toString()).toSet() ?? <String>{};
    final rawBypass = v['bypassRoles'] as List?;
    _bypassRoles = rawBypass?.map((e) => e.toString()).toSet() ??
        Set<String>.from(defaultBypassRoles);
    _checkSuspension = v['checkSuspension'] as bool? ?? true;
    _checkLeave = v['checkLeave'] as bool? ?? true;
    _msgLeaveAr = v['msgLeaveAr']?.toString() ?? defaultMsgLeaveAr;
    _msgLeaveEn = v['msgLeaveEn']?.toString() ?? defaultMsgLeaveEn;
    _msgSuspendedAr =
        v['msgSuspendedAr']?.toString() ?? defaultMsgSuspendedAr;
    _msgSuspendedEn =
        v['msgSuspendedEn']?.toString() ?? defaultMsgSuspendedEn;
  }

  Future<void> _migrateLegacyKeys() async {
    try {
      final p = await SharedPreferences.getInstance();
      final hasLegacy = p.containsKey(_kLegacyEnabled) ||
          p.containsKey(_kLegacyScope) ||
          p.containsKey(_kLegacyJobTitles) ||
          p.containsKey(_kLegacyAccounts) ||
          p.containsKey(_kLegacyBypassRoles) ||
          p.containsKey(_kLegacyCheckSuspension) ||
          p.containsKey(_kLegacyCheckLeave) ||
          p.containsKey(_kLegacyMsgLeaveAr) ||
          p.containsKey(_kLegacyMsgLeaveEn) ||
          p.containsKey(_kLegacyMsgSuspendedAr) ||
          p.containsKey(_kLegacyMsgSuspendedEn);
      if (!hasLegacy) return;
      _enabled = p.getBool(_kLegacyEnabled) ?? defaultEnabled;
      _scope = ActiveDutyScopeX.fromKey(p.getString(_kLegacyScope));
      _jobTitleIds =
          (p.getStringList(_kLegacyJobTitles) ?? const []).toSet();
      _accountIds =
          (p.getStringList(_kLegacyAccounts) ?? const []).toSet();
      _bypassRoles =
          (p.getStringList(_kLegacyBypassRoles) ?? defaultBypassRoles)
              .toSet();
      _checkSuspension = p.getBool(_kLegacyCheckSuspension) ?? true;
      _checkLeave = p.getBool(_kLegacyCheckLeave) ?? true;
      _msgLeaveAr = p.getString(_kLegacyMsgLeaveAr) ?? defaultMsgLeaveAr;
      _msgLeaveEn = p.getString(_kLegacyMsgLeaveEn) ?? defaultMsgLeaveEn;
      _msgSuspendedAr =
          p.getString(_kLegacyMsgSuspendedAr) ?? defaultMsgSuspendedAr;
      _msgSuspendedEn =
          p.getString(_kLegacyMsgSuspendedEn) ?? defaultMsgSuspendedEn;
      await _persist();
      await p.remove(_kLegacyEnabled);
      await p.remove(_kLegacyScope);
      await p.remove(_kLegacyJobTitles);
      await p.remove(_kLegacyAccounts);
      await p.remove(_kLegacyBypassRoles);
      await p.remove(_kLegacyMsgLeaveAr);
      await p.remove(_kLegacyMsgLeaveEn);
      await p.remove(_kLegacyMsgSuspendedAr);
      await p.remove(_kLegacyMsgSuspendedEn);
      await p.remove(_kLegacyCheckSuspension);
      await p.remove(_kLegacyCheckLeave);
    } catch (_) {/* ignore */}
  }

  Future<void> _persist() async {
    await AppSettingsService.instance.setJson(_kSettingKey, {
      'enabled': _enabled,
      'scope': _scope.key,
      'jobTitleIds': _jobTitleIds.toList(),
      'accountIds': _accountIds.toList(),
      'bypassRoles': _bypassRoles.toList(),
      'checkSuspension': _checkSuspension,
      'checkLeave': _checkLeave,
      'msgLeaveAr': _msgLeaveAr,
      'msgLeaveEn': _msgLeaveEn,
      'msgSuspendedAr': _msgSuspendedAr,
      'msgSuspendedEn': _msgSuspendedEn,
    });
  }

  Future<void> setEnabled(bool v) async {
    _enabled = v;
    await _persist();
    notifyListeners();
  }

  Future<void> setScope(ActiveDutyScope s) async {
    _scope = s;
    await _persist();
    notifyListeners();
  }

  Future<void> setJobTitleIds(Set<String> ids) async {
    _jobTitleIds = Set.from(ids);
    await _persist();
    notifyListeners();
  }

  Future<void> setAccountIds(Set<String> ids) async {
    _accountIds = Set.from(ids);
    await _persist();
    notifyListeners();
  }

  Future<void> setBypassRoles(Set<String> roles) async {
    _bypassRoles = Set.from(roles);
    await _persist();
    notifyListeners();
  }

  Future<void> setCheckSuspension(bool v) async {
    _checkSuspension = v;
    await _persist();
    notifyListeners();
  }

  Future<void> setCheckLeave(bool v) async {
    _checkLeave = v;
    await _persist();
    notifyListeners();
  }

  Future<void> setMessageLeave({String? ar, String? en}) async {
    if (ar != null) _msgLeaveAr = ar;
    if (en != null) _msgLeaveEn = en;
    await _persist();
    notifyListeners();
  }

  Future<void> setMessageSuspended({String? ar, String? en}) async {
    if (ar != null) _msgSuspendedAr = ar;
    if (en != null) _msgSuspendedEn = en;
    await _persist();
    notifyListeners();
  }

  Future<void> resetToDefaults() async {
    _enabled = defaultEnabled;
    _scope = defaultScope;
    _jobTitleIds = <String>{};
    _accountIds = <String>{};
    _bypassRoles = Set<String>.from(defaultBypassRoles);
    _checkSuspension = true;
    _checkLeave = true;
    _msgLeaveAr = defaultMsgLeaveAr;
    _msgLeaveEn = defaultMsgLeaveEn;
    _msgSuspendedAr = defaultMsgSuspendedAr;
    _msgSuspendedEn = defaultMsgSuspendedEn;
    await _persist();
    notifyListeners();
  }

  // ============================================================
  // مَنطِق التَطبيق
  // ============================================================

  /// هَل تَنطَبِق السياسة على هذا الحِساب؟
  bool appliesTo(String accountId, {List<String> userRoleKeys = const []}) {
    if (!_enabled) return false;
    // تَجاوُز لِأَدوار مُعَيَّنة
    for (final r in userRoleKeys) {
      if (_bypassRoles.contains(r)) return false;
    }
    // النِطاق
    switch (_scope) {
      case ActiveDutyScope.allAccounts:
        return true;
      case ActiveDutyScope.includedOnly:
        return _matchesSelection(accountId);
      case ActiveDutyScope.excludedOnly:
        return !_matchesSelection(accountId);
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
}
