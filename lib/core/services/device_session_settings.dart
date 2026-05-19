import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../repositories/mock_repository.dart';
import 'app_settings_service.dart';

/// سبب قرار تطبيق/عدم تطبيق السياسة على حساب
enum PolicyReason {
  /// تجاوز فردي = تفعيل (الأقوى)
  overrideEnforced,

  /// تجاوز فردي = إعفاء (الأقوى)
  overrideExempt,

  /// السياسة العامّة معطّلة كلّياً
  globallyDisabled,

  /// النطاق "كلّ الحسابات"
  scopeAll,

  /// (ضمن "مختارون فقط") الحساب موجود في قائمة الحسابات
  accountListed,

  /// (ضمن "مختارون فقط") مسمّى الحساب موجود في قائمة المسمّيات
  jobTitleListed,

  /// (ضمن "مختارون فقط") الحساب ليس في أيّ قائمة → لا تُطبَّق
  notInIncludeList,

  /// (ضمن "ما عدا...") الحساب موجود في قائمة الإعفاءات
  accountExcluded,

  /// (ضمن "ما عدا...") مسمّاه في قائمة الإعفاءات
  jobTitleExcluded,

  /// (ضمن "ما عدا...") الحساب ليس في الإعفاءات → تُطبَّق
  notInExcludeList,
}

class PolicyDecision {
  final bool applies;
  final PolicyReason reason;
  final String? matchedJobTitleId;

  const PolicyDecision({
    required this.applies,
    required this.reason,
    this.matchedJobTitleId,
  });

  String reasonLabel({required bool isAr}) {
    switch (reason) {
      case PolicyReason.overrideEnforced:
        return isAr ? 'تجاوز فردي: تفعيل' : 'Override: enforced';
      case PolicyReason.overrideExempt:
        return isAr ? 'تجاوز فردي: إعفاء' : 'Override: exempt';
      case PolicyReason.globallyDisabled:
        return isAr
            ? 'السياسة معطّلة عامّة'
            : 'Policy globally disabled';
      case PolicyReason.scopeAll:
        return isAr ? 'النطاق: كلّ الحسابات' : 'Scope: all accounts';
      case PolicyReason.accountListed:
        return isAr ? 'مضاف في قائمة الحسابات' : 'Account listed';
      case PolicyReason.jobTitleListed:
        return isAr ? 'مسمّاه ضمن المختارة' : 'Job title listed';
      case PolicyReason.notInIncludeList:
        return isAr
            ? 'ليس ضمن المختارين'
            : 'Not in include list';
      case PolicyReason.accountExcluded:
        return isAr ? 'مُعفى يدوياً' : 'Account exempted';
      case PolicyReason.jobTitleExcluded:
        return isAr
            ? 'مسمّاه ضمن المُعفاة'
            : 'Job title exempted';
      case PolicyReason.notInExcludeList:
        return isAr
            ? 'ليس ضمن المُعفاة'
            : 'Not in exempt list';
    }
  }
}

/// نطاق تطبيق السياسة المتشدّدة
enum DevicePolicyScope {
  /// السياسة تُطبَّق على كلّ الحسابات
  allAccounts,

  /// السياسة تُطبَّق فقط على الحسابات المختارة (whitelist)
  includedOnly,

  /// السياسة تُطبَّق على الكلّ ما عدا الحسابات المختارة (exemptions)
  excludedOnly,
}

extension DevicePolicyScopeX on DevicePolicyScope {
  String labelAr() {
    switch (this) {
      case DevicePolicyScope.allAccounts:
        return 'كلّ الحسابات';
      case DevicePolicyScope.includedOnly:
        return 'حسابات مختارة فقط';
      case DevicePolicyScope.excludedOnly:
        return 'الكلّ ما عدا حسابات مختارة';
    }
  }

  String labelEn() {
    switch (this) {
      case DevicePolicyScope.allAccounts:
        return 'All accounts';
      case DevicePolicyScope.includedOnly:
        return 'Selected accounts only';
      case DevicePolicyScope.excludedOnly:
        return 'All except selected';
    }
  }

  String key() {
    switch (this) {
      case DevicePolicyScope.allAccounts:
        return 'all';
      case DevicePolicyScope.includedOnly:
        return 'include';
      case DevicePolicyScope.excludedOnly:
        return 'exclude';
    }
  }

  static DevicePolicyScope fromKey(String? k) {
    switch (k) {
      case 'include':
        return DevicePolicyScope.includedOnly;
      case 'exclude':
        return DevicePolicyScope.excludedOnly;
      case 'all':
      default:
        return DevicePolicyScope.allAccounts;
    }
  }
}

/// 📱 إعدادات سياسة "جهاز واحد لكل موظف"
///
/// تتحكّم في:
///   • enforceOneDevice: هل نمنع الدخول من جهاز ثانٍ؟
///   • scope: على من تُطبَّق السياسة؟ (الكلّ / مختارون / الكلّ عدا مختارين)
///   • accountIds: قائمة الحسابات (الدلالة بحسب scope)
///   • blockedMessageAr / blockedMessageEn: نصّ الرسالة (قابل للتعديل)
///   • notifyAdminOnReplace: تسجيل حدث عند استبدال جهاز
///
/// **التخزين:** عبر `AppSettingsService` (Supabase + كاش محلّي)
///   - Supabase: جدول `app_settings`، key=`device_session`
class DeviceSessionSettings extends ChangeNotifier {
  DeviceSessionSettings._();
  static final instance = DeviceSessionSettings._();

  /// مفتاح الإعداد في Supabase + الكاش المحلّي.
  static const _kSettingKey = 'device_session';

  // مفاتيح legacy (للهجرة فقط)
  static const _kLegacyEnforce = 'device_session_enforce_v1';
  static const _kLegacyScope = 'device_session_scope_v1';
  static const _kLegacyAccountIds = 'device_session_account_ids_v1';
  static const _kLegacyJobTitleIds = 'device_session_job_title_ids_v1';
  static const _kLegacyOverrides = 'device_session_overrides_v1';
  static const _kLegacyMsgAr = 'device_session_blocked_msg_ar_v1';
  static const _kLegacyMsgEn = 'device_session_blocked_msg_en_v1';
  static const _kLegacyNotifyAdmin = 'device_session_notify_admin_v1';

  // ==== القيم الافتراضيّة ====
  static const bool defaultEnforce = false;
  static const DevicePolicyScope defaultScope =
      DevicePolicyScope.allAccounts;
  static const String defaultMsgAr =
      'حسابك مرتبط بجهاز آخر، يرجى مراجعة الإدارة';
  static const String defaultMsgEn =
      'Your account is bound to another device. Please contact administration';
  static const bool defaultNotifyAdmin = false;

  bool _enforce = defaultEnforce;
  DevicePolicyScope _scope = defaultScope;
  Set<String> _accountIds = <String>{};

  /// 🆕 مسميات وظيفيّة: السياسة تُطبَّق على كلّ موظّف يحمل أحد هذه المسمّيات
  Set<String> _jobTitleIds = <String>{};

  /// تجاوزات لكلّ حساب: 'on' أو 'off'. تتجاوز قواعد scope كلّياً.
  Map<String, bool> _overrides = <String, bool>{};
  String _msgAr = defaultMsgAr;
  String _msgEn = defaultMsgEn;
  bool _notifyAdmin = defaultNotifyAdmin;
  bool _loaded = false;

  bool get enforceOneDevice => _enforce;
  DevicePolicyScope get scope => _scope;
  Set<String> get accountIds => Set.unmodifiable(_accountIds);
  Set<String> get jobTitleIds => Set.unmodifiable(_jobTitleIds);
  Map<String, bool> get overrides => Map.unmodifiable(_overrides);
  String get blockedMessageAr => _msgAr;
  String get blockedMessageEn => _msgEn;
  bool get notifyAdminOnReplace => _notifyAdmin;
  bool get isLoaded => _loaded;

  /// رسالة بحسب اللغة
  String blockedMessage({required bool isAr}) =>
      isAr ? _msgAr : _msgEn;

  /// تجاوز لحساب محدّد: null = لا يوجد، true = مفعّل صراحة،
  /// false = معطَّل صراحة
  bool? overrideFor(String accountId) => _overrides[accountId];

  /// يستخرج jobTitleId المرتبط بحساب (عبر employee إن وُجد)
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

  /// هل الحساب مطابق للقائمة المختارة؟ (account-id OR job-title-id)
  bool _matchesSelection(String accountId) {
    if (_accountIds.contains(accountId)) return true;
    if (_jobTitleIds.isNotEmpty) {
      final jt = _jobTitleIdOf(accountId);
      if (jt != null && _jobTitleIds.contains(jt)) return true;
    }
    return false;
  }

  /// 🎯 المنطق المركزي: هل تُطبَّق السياسة المتشدّدة على هذا الحساب؟
  bool appliesTo(String accountId) {
    final override = _overrides[accountId];
    if (override != null) return override;
    if (!_enforce) return false;
    switch (_scope) {
      case DevicePolicyScope.allAccounts:
        return true;
      case DevicePolicyScope.includedOnly:
        return _matchesSelection(accountId);
      case DevicePolicyScope.excludedOnly:
        return !_matchesSelection(accountId);
    }
  }

  /// 🔎 يُرجع سبب القرار (للعرض في شاشة المعاينة)
  PolicyDecision decisionFor(String accountId) {
    final override = _overrides[accountId];
    if (override == true) {
      return PolicyDecision(
        applies: true,
        reason: PolicyReason.overrideEnforced,
      );
    }
    if (override == false) {
      return PolicyDecision(
        applies: false,
        reason: PolicyReason.overrideExempt,
      );
    }
    if (!_enforce) {
      return PolicyDecision(
        applies: false,
        reason: PolicyReason.globallyDisabled,
      );
    }
    switch (_scope) {
      case DevicePolicyScope.allAccounts:
        return PolicyDecision(
          applies: true,
          reason: PolicyReason.scopeAll,
        );
      case DevicePolicyScope.includedOnly:
        if (_accountIds.contains(accountId)) {
          return PolicyDecision(
            applies: true,
            reason: PolicyReason.accountListed,
          );
        }
        final jt = _jobTitleIdOf(accountId);
        if (jt != null && _jobTitleIds.contains(jt)) {
          return PolicyDecision(
            applies: true,
            reason: PolicyReason.jobTitleListed,
            matchedJobTitleId: jt,
          );
        }
        return PolicyDecision(
          applies: false,
          reason: PolicyReason.notInIncludeList,
        );
      case DevicePolicyScope.excludedOnly:
        if (_accountIds.contains(accountId)) {
          return PolicyDecision(
            applies: false,
            reason: PolicyReason.accountExcluded,
          );
        }
        final jt = _jobTitleIdOf(accountId);
        if (jt != null && _jobTitleIds.contains(jt)) {
          return PolicyDecision(
            applies: false,
            reason: PolicyReason.jobTitleExcluded,
            matchedJobTitleId: jt,
          );
        }
        return PolicyDecision(
          applies: true,
          reason: PolicyReason.notInExcludeList,
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
    _enforce = v['enforce'] as bool? ?? defaultEnforce;
    _scope = DevicePolicyScopeX.fromKey(v['scope'] as String?);
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
    _msgAr = v['msgAr'] as String? ?? defaultMsgAr;
    _msgEn = v['msgEn'] as String? ?? defaultMsgEn;
    _notifyAdmin = v['notifyAdmin'] as bool? ?? defaultNotifyAdmin;
  }

  Future<void> _migrateLegacyKeys() async {
    try {
      final p = await SharedPreferences.getInstance();
      final hasLegacy = p.containsKey(_kLegacyEnforce) ||
          p.containsKey(_kLegacyScope) ||
          p.containsKey(_kLegacyAccountIds) ||
          p.containsKey(_kLegacyOverrides);
      if (!hasLegacy) return;
      _enforce = p.getBool(_kLegacyEnforce) ?? defaultEnforce;
      _scope = DevicePolicyScopeX.fromKey(p.getString(_kLegacyScope));
      _accountIds = (p.getStringList(_kLegacyAccountIds) ?? const []).toSet();
      _jobTitleIds =
          (p.getStringList(_kLegacyJobTitleIds) ?? const []).toSet();
      // overrides: مخزَّنة كقائمة "id|on" أو "id|off"
      final rawOverrides = p.getStringList(_kLegacyOverrides) ?? const [];
      _overrides = {};
      for (final raw in rawOverrides) {
        final i = raw.indexOf('|');
        if (i <= 0) continue;
        final id = raw.substring(0, i);
        final flag = raw.substring(i + 1);
        if (flag == 'on') {
          _overrides[id] = true;
        } else if (flag == 'off') {
          _overrides[id] = false;
        }
      }
      _msgAr = p.getString(_kLegacyMsgAr) ?? defaultMsgAr;
      _msgEn = p.getString(_kLegacyMsgEn) ?? defaultMsgEn;
      _notifyAdmin = p.getBool(_kLegacyNotifyAdmin) ?? defaultNotifyAdmin;
      // احفظ في الصيغة الجديدة
      await _persist();
      // امسح المفاتيح القديمة
      await p.remove(_kLegacyEnforce);
      await p.remove(_kLegacyScope);
      await p.remove(_kLegacyAccountIds);
      await p.remove(_kLegacyJobTitleIds);
      await p.remove(_kLegacyOverrides);
      await p.remove(_kLegacyMsgAr);
      await p.remove(_kLegacyMsgEn);
      await p.remove(_kLegacyNotifyAdmin);
    } catch (_) {/* ignore */}
  }

  Future<void> _persist() async {
    await AppSettingsService.instance.setJson(_kSettingKey, {
      'enforce': _enforce,
      'scope': _scope.key(),
      'accountIds': _accountIds.toList(),
      'jobTitleIds': _jobTitleIds.toList(),
      'overrides': _overrides,
      'msgAr': _msgAr,
      'msgEn': _msgEn,
      'notifyAdmin': _notifyAdmin,
    });
  }

  Future<void> setEnforceOneDevice(bool v) async {
    _enforce = v;
    await _persist();
    notifyListeners();
  }

  Future<void> setScope(DevicePolicyScope s) async {
    _scope = s;
    await _persist();
    notifyListeners();
  }

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

  /// 🆕 ضبط/مسح تجاوز لحساب محدّد
  /// [enabled] = true → فرض السياسة على هذا الحساب
  ///           = false → إعفاء هذا الحساب
  ///           = null → مسح التجاوز (الرجوع للقاعدة العامّة)
  Future<void> setOverride(String accountId, bool? enabled) async {
    if (enabled == null) {
      _overrides.remove(accountId);
    } else {
      _overrides[accountId] = enabled;
    }
    await _persist();
    notifyListeners();
  }

  Future<void> setBlockedMessageAr(String v) async {
    _msgAr = v.trim().isEmpty ? defaultMsgAr : v.trim();
    await _persist();
    notifyListeners();
  }

  Future<void> setBlockedMessageEn(String v) async {
    _msgEn = v.trim().isEmpty ? defaultMsgEn : v.trim();
    await _persist();
    notifyListeners();
  }

  Future<void> setNotifyAdminOnReplace(bool v) async {
    _notifyAdmin = v;
    await _persist();
    notifyListeners();
  }

  Future<void> resetToDefaults() async {
    _enforce = defaultEnforce;
    _scope = defaultScope;
    _accountIds = <String>{};
    _jobTitleIds = <String>{};
    _overrides = <String, bool>{};
    _msgAr = defaultMsgAr;
    _msgEn = defaultMsgEn;
    _notifyAdmin = defaultNotifyAdmin;
    await _persist();
    notifyListeners();
  }
}
