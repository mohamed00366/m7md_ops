import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../repositories/mock_repository.dart';
import 'app_settings_service.dart';

/// طرق الدخول المتاحة
enum LoginMethod { password, face }

extension LoginMethodX on LoginMethod {
  String labelAr() {
    switch (this) {
      case LoginMethod.password:
        return 'كلمة المرور';
      case LoginMethod.face:
        return 'بصمة الوجه';
    }
  }

  String labelEn() {
    switch (this) {
      case LoginMethod.password:
        return 'Password';
      case LoginMethod.face:
        return 'Face ID';
    }
  }

  String key() {
    switch (this) {
      case LoginMethod.password:
        return 'password';
      case LoginMethod.face:
        return 'face';
    }
  }

  static LoginMethod fromKey(String? k) {
    switch (k) {
      case 'face':
        return LoginMethod.face;
      case 'password':
      default:
        return LoginMethod.password;
    }
  }
}

/// نطاق التطبيق
enum LoginMethodScope {
  allAccounts,
  includedOnly,
  excludedOnly,
}

extension LoginMethodScopeX on LoginMethodScope {
  String labelAr() {
    switch (this) {
      case LoginMethodScope.allAccounts:
        return 'كلّ الحسابات';
      case LoginMethodScope.includedOnly:
        return 'حسابات/مسمّيات مختارة فقط';
      case LoginMethodScope.excludedOnly:
        return 'الكلّ ما عدا المختارين';
    }
  }

  String labelEn() {
    switch (this) {
      case LoginMethodScope.allAccounts:
        return 'All accounts';
      case LoginMethodScope.includedOnly:
        return 'Selected only';
      case LoginMethodScope.excludedOnly:
        return 'All except selected';
    }
  }

  String key() {
    switch (this) {
      case LoginMethodScope.allAccounts:
        return 'all';
      case LoginMethodScope.includedOnly:
        return 'include';
      case LoginMethodScope.excludedOnly:
        return 'exclude';
    }
  }

  static LoginMethodScope fromKey(String? k) {
    switch (k) {
      case 'include':
        return LoginMethodScope.includedOnly;
      case 'exclude':
        return LoginMethodScope.excludedOnly;
      case 'all':
      default:
        return LoginMethodScope.allAccounts;
    }
  }
}

/// قرار طريقة الدخول لحساب
enum LoginMethodReason {
  overrideForced,
  globallyDisabled,
  scopeAll,
  accountInList,
  jobTitleInList,
  notInIncludeList,
  accountInExcludeList,
  jobTitleInExcludeList,
  notInExcludeList,
}

class LoginMethodDecision {
  final LoginMethod method;
  final LoginMethodReason reason;
  final String? matchedJobTitleId;

  const LoginMethodDecision({
    required this.method,
    required this.reason,
    this.matchedJobTitleId,
  });

  String reasonLabel({required bool isAr}) {
    switch (reason) {
      case LoginMethodReason.overrideForced:
        return isAr ? 'تجاوز فردي' : 'Override';
      case LoginMethodReason.globallyDisabled:
        return isAr ? 'السياسة معطّلة' : 'Policy off';
      case LoginMethodReason.scopeAll:
        return isAr ? 'النطاق: الكلّ' : 'Scope: all';
      case LoginMethodReason.accountInList:
        return isAr ? 'الحساب ضمن القائمة' : 'Account in list';
      case LoginMethodReason.jobTitleInList:
        return isAr ? 'المسمّى ضمن القائمة' : 'Job title in list';
      case LoginMethodReason.notInIncludeList:
        return isAr ? 'خارج القائمة' : 'Not in list';
      case LoginMethodReason.accountInExcludeList:
        return isAr ? 'حساب مستثنى' : 'Account exempted';
      case LoginMethodReason.jobTitleInExcludeList:
        return isAr ? 'مسمّى مستثنى' : 'Job title exempted';
      case LoginMethodReason.notInExcludeList:
        return isAr ? 'غير مستثنى' : 'Not exempted';
    }
  }
}

/// 🔐 إعدادات طريقة الدخول
///
/// **التخزين:** عبر `AppSettingsService` (Supabase + كاش محلّي)
///   - Supabase: جدول `app_settings`، key=`login_method`
class LoginMethodSettings extends ChangeNotifier {
  LoginMethodSettings._();
  static final instance = LoginMethodSettings._();

  /// مفتاح الإعداد في Supabase + الكاش المحلّي.
  static const _kSettingKey = 'login_method';

  // مفاتيح legacy (للهجرة فقط)
  static const _kLegacyEnabled = 'login_method_enabled_v1';
  static const _kLegacyDefaultMethod = 'login_method_default_v1';
  static const _kLegacyScope = 'login_method_scope_v1';
  static const _kLegacyAccountIds = 'login_method_account_ids_v1';
  static const _kLegacyJobTitleIds = 'login_method_job_title_ids_v1';
  static const _kLegacyOverrides = 'login_method_overrides_v1';
  static const _kLegacyMaxAttempts = 'login_method_max_attempts_v1';
  static const _kLegacyCooldownMinutes = 'login_method_cooldown_min_v1';
  static const _kLegacyAllowPwdFallback =
      'login_method_allow_pwd_fallback_v1';
  static const _kLegacyMsgWrongMethodAr = 'login_method_msg_wrong_ar_v1';
  static const _kLegacyMsgWrongMethodEn = 'login_method_msg_wrong_en_v1';
  static const _kLegacyMsgFaceFailedAr = 'login_method_msg_failed_ar_v1';
  static const _kLegacyMsgFaceFailedEn = 'login_method_msg_failed_en_v1';
  static const _kLegacyMsgCooldownAr = 'login_method_msg_cooldown_ar_v1';
  static const _kLegacyMsgCooldownEn = 'login_method_msg_cooldown_en_v1';
  static const _kLegacyMsgLockedAr = 'login_method_msg_locked_ar_v1';
  static const _kLegacyMsgLockedEn = 'login_method_msg_locked_en_v1';
  static const _kLegacyMsgNotEnrolledAr =
      'login_method_msg_notenrolled_ar_v1';
  static const _kLegacyMsgNotEnrolledEn =
      'login_method_msg_notenrolled_en_v1';

  // ===== Defaults =====
  static const bool defaultEnabled = false;
  static const LoginMethod defaultDefault = LoginMethod.password;
  static const LoginMethodScope defaultScope = LoginMethodScope.allAccounts;
  static const int defaultMaxAttempts = 3;
  static const int defaultCooldownMinutes = 3;
  static const bool defaultAllowPwdFallback = false;

  static const String defaultMsgWrongMethodAr =
      'هذا الحساب يستخدم بصمة الوجه — اختر تبويبة الوجه';
  static const String defaultMsgWrongMethodEn =
      'This account uses Face ID — switch to Face tab';
  static const String defaultMsgFaceFailedAr =
      '📷 لم يتمّ التعرّف على الوجه — امسح كاميرا الهاتف وتأكّد من الإضاءة';
  static const String defaultMsgFaceFailedEn =
      '📷 Face not recognized — clean camera and check lighting';
  static const String defaultMsgCooldownAr =
      'فشلت عدّة محاولات — حاول بعد 3 دقائق';
  static const String defaultMsgCooldownEn =
      'Several failed attempts — try again in 3 minutes';
  static const String defaultMsgLockedAr =
      'تمّ قفل حسابك مؤقّتاً — يُرجى مراجعة الإدارة';
  static const String defaultMsgLockedEn =
      'Your account is temporarily locked — please contact administration';
  static const String defaultMsgNotEnrolledAr =
      'لم تُسجَّل بصمة وجهك بعد — راجع الإدارة لتسجيلها';
  static const String defaultMsgNotEnrolledEn =
      'Your face is not enrolled yet — contact administration';

  // ===== State =====
  bool _enabled = defaultEnabled;
  LoginMethod _defaultMethod = defaultDefault;
  LoginMethodScope _scope = defaultScope;
  Set<String> _accountIds = <String>{};
  Set<String> _jobTitleIds = <String>{};
  Map<String, LoginMethod> _overrides = <String, LoginMethod>{};
  int _maxAttempts = defaultMaxAttempts;
  int _cooldownMinutes = defaultCooldownMinutes;
  bool _allowPwdFallback = defaultAllowPwdFallback;
  String _msgWrongMethodAr = defaultMsgWrongMethodAr;
  String _msgWrongMethodEn = defaultMsgWrongMethodEn;
  String _msgFaceFailedAr = defaultMsgFaceFailedAr;
  String _msgFaceFailedEn = defaultMsgFaceFailedEn;
  String _msgCooldownAr = defaultMsgCooldownAr;
  String _msgCooldownEn = defaultMsgCooldownEn;
  String _msgLockedAr = defaultMsgLockedAr;
  String _msgLockedEn = defaultMsgLockedEn;
  String _msgNotEnrolledAr = defaultMsgNotEnrolledAr;
  String _msgNotEnrolledEn = defaultMsgNotEnrolledEn;
  bool _loaded = false;

  // ===== Getters =====
  bool get enabled => _enabled;
  LoginMethod get defaultMethod => _defaultMethod;
  LoginMethodScope get scope => _scope;
  Set<String> get accountIds => Set.unmodifiable(_accountIds);
  Set<String> get jobTitleIds => Set.unmodifiable(_jobTitleIds);
  Map<String, LoginMethod> get overrides => Map.unmodifiable(_overrides);
  int get maxAttempts => _maxAttempts;
  int get cooldownMinutes => _cooldownMinutes;
  bool get allowPwdFallback => _allowPwdFallback;
  String get msgWrongMethodAr => _msgWrongMethodAr;
  String get msgWrongMethodEn => _msgWrongMethodEn;
  String get msgFaceFailedAr => _msgFaceFailedAr;
  String get msgFaceFailedEn => _msgFaceFailedEn;
  String get msgCooldownAr => _msgCooldownAr;
  String get msgCooldownEn => _msgCooldownEn;
  String get msgLockedAr => _msgLockedAr;
  String get msgLockedEn => _msgLockedEn;
  String get msgNotEnrolledAr => _msgNotEnrolledAr;
  String get msgNotEnrolledEn => _msgNotEnrolledEn;
  bool get isLoaded => _loaded;

  String wrongMethodMessage({required bool isAr}) =>
      isAr ? _msgWrongMethodAr : _msgWrongMethodEn;
  String faceFailedMessage({required bool isAr}) =>
      isAr ? _msgFaceFailedAr : _msgFaceFailedEn;
  String cooldownMessage({required bool isAr}) =>
      isAr ? _msgCooldownAr : _msgCooldownEn;
  String lockedMessage({required bool isAr}) =>
      isAr ? _msgLockedAr : _msgLockedEn;
  String notEnrolledMessage({required bool isAr}) =>
      isAr ? _msgNotEnrolledAr : _msgNotEnrolledEn;

  /// الطريقة المعاكسة لـ defaultMethod
  LoginMethod get _otherMethod =>
      _defaultMethod == LoginMethod.password
          ? LoginMethod.face
          : LoginMethod.password;

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

  /// 🎯 المنطق المركزي: ماذا تستخدم هذه الـ account للدخول؟
  LoginMethod methodFor(String accountId) =>
      decisionFor(accountId).method;

  LoginMethodDecision decisionFor(String accountId) {
    final override = _overrides[accountId];
    if (override != null) {
      return LoginMethodDecision(
        method: override,
        reason: LoginMethodReason.overrideForced,
      );
    }
    if (!_enabled) {
      return LoginMethodDecision(
        method: _defaultMethod,
        reason: LoginMethodReason.globallyDisabled,
      );
    }
    switch (_scope) {
      case LoginMethodScope.allAccounts:
        return LoginMethodDecision(
          method: _defaultMethod,
          reason: LoginMethodReason.scopeAll,
        );

      case LoginMethodScope.includedOnly:
        if (_accountIds.contains(accountId)) {
          return LoginMethodDecision(
            method: _otherMethod,
            reason: LoginMethodReason.accountInList,
          );
        }
        final jt = _jobTitleIdOf(accountId);
        if (jt != null && _jobTitleIds.contains(jt)) {
          return LoginMethodDecision(
            method: _otherMethod,
            reason: LoginMethodReason.jobTitleInList,
            matchedJobTitleId: jt,
          );
        }
        return LoginMethodDecision(
          method: _defaultMethod,
          reason: LoginMethodReason.notInIncludeList,
        );

      case LoginMethodScope.excludedOnly:
        if (_accountIds.contains(accountId)) {
          return LoginMethodDecision(
            method: _defaultMethod,
            reason: LoginMethodReason.accountInExcludeList,
          );
        }
        final jt = _jobTitleIdOf(accountId);
        if (jt != null && _jobTitleIds.contains(jt)) {
          return LoginMethodDecision(
            method: _defaultMethod,
            reason: LoginMethodReason.jobTitleInExcludeList,
            matchedJobTitleId: jt,
          );
        }
        return LoginMethodDecision(
          method: _otherMethod,
          reason: LoginMethodReason.notInExcludeList,
        );
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
    _defaultMethod = LoginMethodX.fromKey(v['defaultMethod'] as String?);
    _scope = LoginMethodScopeX.fromKey(v['scope'] as String?);
    _accountIds = (v['accountIds'] as List?)
            ?.map((e) => e.toString())
            .toSet() ??
        <String>{};
    _jobTitleIds = (v['jobTitleIds'] as List?)
            ?.map((e) => e.toString())
            .toSet() ??
        <String>{};
    final ov = v['overrides'] as Map?;
    _overrides = <String, LoginMethod>{};
    if (ov != null) {
      ov.forEach((k, val) {
        _overrides[k.toString()] = LoginMethodX.fromKey(val?.toString());
      });
    }
    _maxAttempts = (v['maxAttempts'] as num?)?.toInt() ?? defaultMaxAttempts;
    _cooldownMinutes =
        (v['cooldownMinutes'] as num?)?.toInt() ?? defaultCooldownMinutes;
    _allowPwdFallback =
        v['allowPwdFallback'] as bool? ?? defaultAllowPwdFallback;
    _msgWrongMethodAr =
        v['msgWrongMethodAr'] as String? ?? defaultMsgWrongMethodAr;
    _msgWrongMethodEn =
        v['msgWrongMethodEn'] as String? ?? defaultMsgWrongMethodEn;
    _msgFaceFailedAr =
        v['msgFaceFailedAr'] as String? ?? defaultMsgFaceFailedAr;
    _msgFaceFailedEn =
        v['msgFaceFailedEn'] as String? ?? defaultMsgFaceFailedEn;
    _msgCooldownAr = v['msgCooldownAr'] as String? ?? defaultMsgCooldownAr;
    _msgCooldownEn = v['msgCooldownEn'] as String? ?? defaultMsgCooldownEn;
    _msgLockedAr = v['msgLockedAr'] as String? ?? defaultMsgLockedAr;
    _msgLockedEn = v['msgLockedEn'] as String? ?? defaultMsgLockedEn;
    _msgNotEnrolledAr =
        v['msgNotEnrolledAr'] as String? ?? defaultMsgNotEnrolledAr;
    _msgNotEnrolledEn =
        v['msgNotEnrolledEn'] as String? ?? defaultMsgNotEnrolledEn;
  }

  Future<void> _migrateLegacyKeys() async {
    try {
      final p = await SharedPreferences.getInstance();
      final hasLegacy = p.containsKey(_kLegacyEnabled) ||
          p.containsKey(_kLegacyDefaultMethod) ||
          p.containsKey(_kLegacyScope);
      if (!hasLegacy) return;
      _enabled = p.getBool(_kLegacyEnabled) ?? defaultEnabled;
      _defaultMethod =
          LoginMethodX.fromKey(p.getString(_kLegacyDefaultMethod));
      _scope = LoginMethodScopeX.fromKey(p.getString(_kLegacyScope));
      _accountIds =
          (p.getStringList(_kLegacyAccountIds) ?? const []).toSet();
      _jobTitleIds =
          (p.getStringList(_kLegacyJobTitleIds) ?? const []).toSet();
      _maxAttempts =
          p.getInt(_kLegacyMaxAttempts) ?? defaultMaxAttempts;
      _cooldownMinutes =
          p.getInt(_kLegacyCooldownMinutes) ?? defaultCooldownMinutes;
      _allowPwdFallback =
          p.getBool(_kLegacyAllowPwdFallback) ?? defaultAllowPwdFallback;

      _msgWrongMethodAr =
          p.getString(_kLegacyMsgWrongMethodAr) ?? defaultMsgWrongMethodAr;
      _msgWrongMethodEn =
          p.getString(_kLegacyMsgWrongMethodEn) ?? defaultMsgWrongMethodEn;
      _msgFaceFailedAr =
          p.getString(_kLegacyMsgFaceFailedAr) ?? defaultMsgFaceFailedAr;
      _msgFaceFailedEn =
          p.getString(_kLegacyMsgFaceFailedEn) ?? defaultMsgFaceFailedEn;
      _msgCooldownAr =
          p.getString(_kLegacyMsgCooldownAr) ?? defaultMsgCooldownAr;
      _msgCooldownEn =
          p.getString(_kLegacyMsgCooldownEn) ?? defaultMsgCooldownEn;
      _msgLockedAr = p.getString(_kLegacyMsgLockedAr) ?? defaultMsgLockedAr;
      _msgLockedEn = p.getString(_kLegacyMsgLockedEn) ?? defaultMsgLockedEn;
      _msgNotEnrolledAr =
          p.getString(_kLegacyMsgNotEnrolledAr) ?? defaultMsgNotEnrolledAr;
      _msgNotEnrolledEn =
          p.getString(_kLegacyMsgNotEnrolledEn) ?? defaultMsgNotEnrolledEn;

      // overrides: قائمة "id|password" أو "id|face"
      final rawOverrides = p.getStringList(_kLegacyOverrides) ?? const [];
      _overrides = {};
      for (final raw in rawOverrides) {
        final i = raw.indexOf('|');
        if (i <= 0) continue;
        final id = raw.substring(0, i);
        final m = LoginMethodX.fromKey(raw.substring(i + 1));
        _overrides[id] = m;
      }

      await _persist();
      for (final k in [
        _kLegacyEnabled, _kLegacyDefaultMethod, _kLegacyScope,
        _kLegacyAccountIds, _kLegacyJobTitleIds, _kLegacyOverrides,
        _kLegacyMaxAttempts, _kLegacyCooldownMinutes,
        _kLegacyAllowPwdFallback,
        _kLegacyMsgWrongMethodAr, _kLegacyMsgWrongMethodEn,
        _kLegacyMsgFaceFailedAr, _kLegacyMsgFaceFailedEn,
        _kLegacyMsgCooldownAr, _kLegacyMsgCooldownEn,
        _kLegacyMsgLockedAr, _kLegacyMsgLockedEn,
        _kLegacyMsgNotEnrolledAr, _kLegacyMsgNotEnrolledEn,
      ]) {
        await p.remove(k);
      }
    } catch (_) {/* ignore */}
  }

  Future<void> _persist() async {
    await AppSettingsService.instance.setJson(_kSettingKey, {
      'enabled': _enabled,
      'defaultMethod': _defaultMethod.key(),
      'scope': _scope.key(),
      'accountIds': _accountIds.toList(),
      'jobTitleIds': _jobTitleIds.toList(),
      'overrides':
          _overrides.map((k, v) => MapEntry(k, v.key())),
      'maxAttempts': _maxAttempts,
      'cooldownMinutes': _cooldownMinutes,
      'allowPwdFallback': _allowPwdFallback,
      'msgWrongMethodAr': _msgWrongMethodAr,
      'msgWrongMethodEn': _msgWrongMethodEn,
      'msgFaceFailedAr': _msgFaceFailedAr,
      'msgFaceFailedEn': _msgFaceFailedEn,
      'msgCooldownAr': _msgCooldownAr,
      'msgCooldownEn': _msgCooldownEn,
      'msgLockedAr': _msgLockedAr,
      'msgLockedEn': _msgLockedEn,
      'msgNotEnrolledAr': _msgNotEnrolledAr,
      'msgNotEnrolledEn': _msgNotEnrolledEn,
    });
  }

  // ===== Setters =====
  Future<void> setEnabled(bool v) async {
    _enabled = v;
    await _persist();
    notifyListeners();
  }

  Future<void> setDefaultMethod(LoginMethod m) async {
    _defaultMethod = m;
    await _persist();
    notifyListeners();
  }

  Future<void> setScope(LoginMethodScope s) async {
    _scope = s;
    await _persist();
    notifyListeners();
  }

  Future<void> setMaxAttempts(int v) async {
    _maxAttempts = v.clamp(1, 10);
    await _persist();
    notifyListeners();
  }

  Future<void> setCooldownMinutes(int v) async {
    _cooldownMinutes = v.clamp(1, 60);
    await _persist();
    notifyListeners();
  }

  Future<void> setAllowPwdFallback(bool v) async {
    _allowPwdFallback = v;
    await _persist();
    notifyListeners();
  }

  Future<void> _setMsg(
      String defaultMsg, String v, void Function(String) assign) async {
    assign(v.trim().isEmpty ? defaultMsg : v.trim());
    await _persist();
    notifyListeners();
  }

  Future<void> setMsgWrongMethodAr(String v) =>
      _setMsg(defaultMsgWrongMethodAr, v, (x) => _msgWrongMethodAr = x);
  Future<void> setMsgWrongMethodEn(String v) =>
      _setMsg(defaultMsgWrongMethodEn, v, (x) => _msgWrongMethodEn = x);
  Future<void> setMsgFaceFailedAr(String v) =>
      _setMsg(defaultMsgFaceFailedAr, v, (x) => _msgFaceFailedAr = x);
  Future<void> setMsgFaceFailedEn(String v) =>
      _setMsg(defaultMsgFaceFailedEn, v, (x) => _msgFaceFailedEn = x);
  Future<void> setMsgCooldownAr(String v) =>
      _setMsg(defaultMsgCooldownAr, v, (x) => _msgCooldownAr = x);
  Future<void> setMsgCooldownEn(String v) =>
      _setMsg(defaultMsgCooldownEn, v, (x) => _msgCooldownEn = x);
  Future<void> setMsgLockedAr(String v) =>
      _setMsg(defaultMsgLockedAr, v, (x) => _msgLockedAr = x);
  Future<void> setMsgLockedEn(String v) =>
      _setMsg(defaultMsgLockedEn, v, (x) => _msgLockedEn = x);
  Future<void> setMsgNotEnrolledAr(String v) =>
      _setMsg(defaultMsgNotEnrolledAr, v, (x) => _msgNotEnrolledAr = x);
  Future<void> setMsgNotEnrolledEn(String v) =>
      _setMsg(defaultMsgNotEnrolledEn, v, (x) => _msgNotEnrolledEn = x);

  // ===== Account / JobTitle lists =====
  Future<void> setAccountIds(Set<String> ids) async {
    _accountIds = Set<String>.from(ids);
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
    if (!_accountIds.contains(id)) return;
    _accountIds = _accountIds.where((x) => x != id).toSet();
    await _persist();
    notifyListeners();
  }

  Future<void> setJobTitleIds(Set<String> ids) async {
    _jobTitleIds = Set<String>.from(ids);
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
    if (!_jobTitleIds.contains(id)) return;
    _jobTitleIds = _jobTitleIds.where((x) => x != id).toSet();
    await _persist();
    notifyListeners();
  }

  /// تجاوز فردي لطريقة دخول حساب
  /// [method] = null → مسح التجاوز (الرجوع للـ scope)
  Future<void> setOverride(String accountId, LoginMethod? method) async {
    if (method == null) {
      _overrides.remove(accountId);
    } else {
      _overrides[accountId] = method;
    }
    await _persist();
    notifyListeners();
  }

  LoginMethod? overrideFor(String accountId) => _overrides[accountId];

  Future<void> resetToDefaults() async {
    _enabled = defaultEnabled;
    _defaultMethod = defaultDefault;
    _scope = defaultScope;
    _accountIds = <String>{};
    _jobTitleIds = <String>{};
    _overrides = <String, LoginMethod>{};
    _maxAttempts = defaultMaxAttempts;
    _cooldownMinutes = defaultCooldownMinutes;
    _allowPwdFallback = defaultAllowPwdFallback;
    _msgWrongMethodAr = defaultMsgWrongMethodAr;
    _msgWrongMethodEn = defaultMsgWrongMethodEn;
    _msgFaceFailedAr = defaultMsgFaceFailedAr;
    _msgFaceFailedEn = defaultMsgFaceFailedEn;
    _msgCooldownAr = defaultMsgCooldownAr;
    _msgCooldownEn = defaultMsgCooldownEn;
    _msgLockedAr = defaultMsgLockedAr;
    _msgLockedEn = defaultMsgLockedEn;
    _msgNotEnrolledAr = defaultMsgNotEnrolledAr;
    _msgNotEnrolledEn = defaultMsgNotEnrolledEn;
    await _persist();
    notifyListeners();
  }
}
