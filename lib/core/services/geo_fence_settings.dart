import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/login_zone.dart';
import '../../repositories/mock_repository.dart';
import 'app_settings_service.dart';

/// نطاق تطبيق سياسة المنطقة الجغرافيّة
enum GeoFenceScope {
  allAccounts,
  includedOnly,
  excludedOnly,
}

extension GeoFenceScopeX on GeoFenceScope {
  String labelAr() {
    switch (this) {
      case GeoFenceScope.allAccounts:
        return 'كلّ الحسابات';
      case GeoFenceScope.includedOnly:
        return 'حسابات/مسمّيات مختارة فقط';
      case GeoFenceScope.excludedOnly:
        return 'الكلّ ما عدا حسابات/مسمّيات';
    }
  }

  String labelEn() {
    switch (this) {
      case GeoFenceScope.allAccounts:
        return 'All accounts';
      case GeoFenceScope.includedOnly:
        return 'Selected only';
      case GeoFenceScope.excludedOnly:
        return 'All except selected';
    }
  }

  String key() {
    switch (this) {
      case GeoFenceScope.allAccounts:
        return 'all';
      case GeoFenceScope.includedOnly:
        return 'include';
      case GeoFenceScope.excludedOnly:
        return 'exclude';
    }
  }

  static GeoFenceScope fromKey(String? k) {
    switch (k) {
      case 'include':
        return GeoFenceScope.includedOnly;
      case 'exclude':
        return GeoFenceScope.excludedOnly;
      case 'all':
      default:
        return GeoFenceScope.allAccounts;
    }
  }
}

/// سبب قرار الـ geo-fence
enum GeoFenceReason {
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

class GeoFenceDecision {
  final bool applies;
  final GeoFenceReason reason;
  final String? matchedJobTitleId;

  const GeoFenceDecision({
    required this.applies,
    required this.reason,
    this.matchedJobTitleId,
  });

  String reasonLabel({required bool isAr}) {
    switch (reason) {
      case GeoFenceReason.overrideEnforced:
        return isAr ? 'تجاوز فردي: تفعيل' : 'Override: enforced';
      case GeoFenceReason.overrideExempt:
        return isAr ? 'تجاوز فردي: إعفاء' : 'Override: exempt';
      case GeoFenceReason.globallyDisabled:
        return isAr
            ? 'السياسة معطّلة عامّة'
            : 'Policy globally disabled';
      case GeoFenceReason.scopeAll:
        return isAr ? 'النطاق: كلّ الحسابات' : 'Scope: all';
      case GeoFenceReason.accountListed:
        return isAr ? 'مضاف في قائمة الحسابات' : 'Account listed';
      case GeoFenceReason.jobTitleListed:
        return isAr ? 'مسمّاه ضمن المختارة' : 'Job title listed';
      case GeoFenceReason.notInIncludeList:
        return isAr ? 'ليس ضمن المختارين' : 'Not in include list';
      case GeoFenceReason.accountExcluded:
        return isAr ? 'مُعفى يدوياً' : 'Account exempted';
      case GeoFenceReason.jobTitleExcluded:
        return isAr ? 'مسمّاه ضمن المُعفاة' : 'Job title exempted';
      case GeoFenceReason.notInExcludeList:
        return isAr ? 'ليس ضمن المُعفاة' : 'Not in exempt list';
    }
  }
}

/// 🌍 إعدادات Geo-fence
///
/// **التخزين:** عبر `AppSettingsService` (Supabase + كاش محلّي)
///   - Supabase: جدول `app_settings`، key=`geo_fence`
class GeoFenceSettings extends ChangeNotifier {
  GeoFenceSettings._();
  static final instance = GeoFenceSettings._();

  /// مفتاح الإعداد في Supabase + الكاش المحلّي.
  static const _kSettingKey = 'geo_fence';

  // مفاتيح legacy (للهجرة فقط)
  static const _kLegacyEnabled = 'geo_fence_enabled_v1';
  static const _kLegacyZones = 'geo_fence_zones_v1';
  static const _kLegacyScope = 'geo_fence_scope_v1';
  static const _kLegacyAccountIds = 'geo_fence_account_ids_v1';
  static const _kLegacyJobTitleIds = 'geo_fence_job_title_ids_v1';
  static const _kLegacyOverrides = 'geo_fence_overrides_v1';
  static const _kLegacyCheckGps = 'geo_fence_check_gps_v1';
  static const _kLegacyCheckWifi = 'geo_fence_check_wifi_v1';
  static const _kLegacyCheckIp = 'geo_fence_check_ip_v1';
  static const _kLegacyRejectMock = 'geo_fence_reject_mock_v1';
  static const _kLegacyAllowVpn = 'geo_fence_allow_vpn_v1';
  static const _kLegacyMsgRejectedAr = 'geo_fence_msg_rejected_ar_v1';
  static const _kLegacyMsgRejectedEn = 'geo_fence_msg_rejected_en_v1';
  static const _kLegacyMsgMockAr = 'geo_fence_msg_mock_ar_v1';
  static const _kLegacyMsgMockEn = 'geo_fence_msg_mock_en_v1';
  static const _kLegacyMsgPermAr = 'geo_fence_msg_perm_ar_v1';
  static const _kLegacyMsgPermEn = 'geo_fence_msg_perm_en_v1';

  // ===== Defaults =====
  static const bool defaultEnabled = false;
  static const GeoFenceScope defaultScope = GeoFenceScope.allAccounts;
  static const bool defaultCheckGps = true;
  static const bool defaultCheckWifi = false;
  static const bool defaultCheckIp = true;
  static const bool defaultRejectMock = true;
  static const bool defaultAllowVpn = false;
  static const String defaultMsgRejectedAr =
      'موقعك خارج المنطقة المسموحة، يُرجى الدخول من موقع العمل';
  static const String defaultMsgRejectedEn =
      'Your location is outside the allowed zone. Please log in from the work site';
  static const String defaultMsgMockAr =
      'تمّ كشف تطبيق تزييف الموقع، الدخول مرفوض. راجع الإدارة';
  static const String defaultMsgMockEn =
      'Mock-location app detected. Login denied. Contact administration';
  static const String defaultMsgPermAr =
      'يلزم السماح للتطبيق بالوصول للموقع لإكمال تسجيل الدخول';
  static const String defaultMsgPermEn =
      'Location permission is required to complete login';

  // ===== State =====
  bool _enabled = defaultEnabled;
  List<LoginZone> _zones = [];
  GeoFenceScope _scope = defaultScope;
  Set<String> _accountIds = <String>{};
  Set<String> _jobTitleIds = <String>{};
  Map<String, bool> _overrides = <String, bool>{};
  bool _checkGps = defaultCheckGps;
  bool _checkWifi = defaultCheckWifi;
  bool _checkIp = defaultCheckIp;
  bool _rejectMock = defaultRejectMock;
  bool _allowVpn = defaultAllowVpn;
  String _msgRejectedAr = defaultMsgRejectedAr;
  String _msgRejectedEn = defaultMsgRejectedEn;
  String _msgMockAr = defaultMsgMockAr;
  String _msgMockEn = defaultMsgMockEn;
  String _msgPermAr = defaultMsgPermAr;
  String _msgPermEn = defaultMsgPermEn;
  bool _loaded = false;

  // ===== Getters =====
  bool get enabled => _enabled;
  List<LoginZone> get zones => List.unmodifiable(_zones);
  GeoFenceScope get scope => _scope;
  Set<String> get accountIds => Set.unmodifiable(_accountIds);
  Set<String> get jobTitleIds => Set.unmodifiable(_jobTitleIds);
  Map<String, bool> get overrides => Map.unmodifiable(_overrides);
  bool get checkGps => _checkGps;
  bool get checkWifi => _checkWifi;
  bool get checkIp => _checkIp;
  bool get rejectMock => _rejectMock;
  bool get allowVpn => _allowVpn;
  String get msgRejectedAr => _msgRejectedAr;
  String get msgRejectedEn => _msgRejectedEn;
  String get msgMockAr => _msgMockAr;
  String get msgMockEn => _msgMockEn;
  String get msgPermAr => _msgPermAr;
  String get msgPermEn => _msgPermEn;
  bool get isLoaded => _loaded;

  String rejectedMessage({required bool isAr}) =>
      isAr ? _msgRejectedAr : _msgRejectedEn;
  String mockMessage({required bool isAr}) =>
      isAr ? _msgMockAr : _msgMockEn;
  String permissionMessage({required bool isAr}) =>
      isAr ? _msgPermAr : _msgPermEn;

  bool? overrideFor(String accountId) => _overrides[accountId];

  /// المسمّى الوظيفي للحساب (عبر employee إن وُجد)
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

  /// 🎯 هل تُطبَّق سياسة الـ geo-fence على هذا الحساب؟
  bool appliesTo(String accountId) {
    final override = _overrides[accountId];
    if (override != null) return override;
    if (!_enabled) return false;
    switch (_scope) {
      case GeoFenceScope.allAccounts:
        return true;
      case GeoFenceScope.includedOnly:
        return _matchesSelection(accountId);
      case GeoFenceScope.excludedOnly:
        return !_matchesSelection(accountId);
    }
  }

  GeoFenceDecision decisionFor(String accountId) {
    final override = _overrides[accountId];
    if (override == true) {
      return const GeoFenceDecision(
          applies: true, reason: GeoFenceReason.overrideEnforced);
    }
    if (override == false) {
      return const GeoFenceDecision(
          applies: false, reason: GeoFenceReason.overrideExempt);
    }
    if (!_enabled) {
      return const GeoFenceDecision(
          applies: false, reason: GeoFenceReason.globallyDisabled);
    }
    switch (_scope) {
      case GeoFenceScope.allAccounts:
        return const GeoFenceDecision(
            applies: true, reason: GeoFenceReason.scopeAll);
      case GeoFenceScope.includedOnly:
        if (_accountIds.contains(accountId)) {
          return const GeoFenceDecision(
              applies: true, reason: GeoFenceReason.accountListed);
        }
        final jt = _jobTitleIdOf(accountId);
        if (jt != null && _jobTitleIds.contains(jt)) {
          return GeoFenceDecision(
              applies: true,
              reason: GeoFenceReason.jobTitleListed,
              matchedJobTitleId: jt);
        }
        return const GeoFenceDecision(
            applies: false, reason: GeoFenceReason.notInIncludeList);
      case GeoFenceScope.excludedOnly:
        if (_accountIds.contains(accountId)) {
          return const GeoFenceDecision(
              applies: false, reason: GeoFenceReason.accountExcluded);
        }
        final jt = _jobTitleIdOf(accountId);
        if (jt != null && _jobTitleIds.contains(jt)) {
          return GeoFenceDecision(
              applies: false,
              reason: GeoFenceReason.jobTitleExcluded,
              matchedJobTitleId: jt);
        }
        return const GeoFenceDecision(
            applies: true, reason: GeoFenceReason.notInExcludeList);
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
    _scope = GeoFenceScopeX.fromKey(v['scope'] as String?);
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
    _checkGps = v['checkGps'] as bool? ?? defaultCheckGps;
    _checkWifi = v['checkWifi'] as bool? ?? defaultCheckWifi;
    _checkIp = v['checkIp'] as bool? ?? defaultCheckIp;
    _rejectMock = v['rejectMock'] as bool? ?? defaultRejectMock;
    _allowVpn = v['allowVpn'] as bool? ?? defaultAllowVpn;
    _msgRejectedAr = v['msgRejectedAr'] as String? ?? defaultMsgRejectedAr;
    _msgRejectedEn = v['msgRejectedEn'] as String? ?? defaultMsgRejectedEn;
    _msgMockAr = v['msgMockAr'] as String? ?? defaultMsgMockAr;
    _msgMockEn = v['msgMockEn'] as String? ?? defaultMsgMockEn;
    _msgPermAr = v['msgPermAr'] as String? ?? defaultMsgPermAr;
    _msgPermEn = v['msgPermEn'] as String? ?? defaultMsgPermEn;
    // zones (مخزّنة كقائمة من JSON objects)
    final rawZones = v['zones'] as List?;
    _zones = [];
    if (rawZones != null) {
      try {
        _zones = rawZones
            .map((e) =>
                LoginZone.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      } catch (_) {/* keep empty */}
    }
  }

  Future<void> _migrateLegacyKeys() async {
    try {
      final p = await SharedPreferences.getInstance();
      final hasLegacy = p.containsKey(_kLegacyEnabled) ||
          p.containsKey(_kLegacyZones) ||
          p.containsKey(_kLegacyScope);
      if (!hasLegacy) return;
      _enabled = p.getBool(_kLegacyEnabled) ?? defaultEnabled;
      _scope = GeoFenceScopeX.fromKey(p.getString(_kLegacyScope));
      _accountIds =
          (p.getStringList(_kLegacyAccountIds) ?? const []).toSet();
      _jobTitleIds =
          (p.getStringList(_kLegacyJobTitleIds) ?? const []).toSet();
      _checkGps = p.getBool(_kLegacyCheckGps) ?? defaultCheckGps;
      _checkWifi = p.getBool(_kLegacyCheckWifi) ?? defaultCheckWifi;
      _checkIp = p.getBool(_kLegacyCheckIp) ?? defaultCheckIp;
      _rejectMock = p.getBool(_kLegacyRejectMock) ?? defaultRejectMock;
      _allowVpn = p.getBool(_kLegacyAllowVpn) ?? defaultAllowVpn;
      _msgRejectedAr =
          p.getString(_kLegacyMsgRejectedAr) ?? defaultMsgRejectedAr;
      _msgRejectedEn =
          p.getString(_kLegacyMsgRejectedEn) ?? defaultMsgRejectedEn;
      _msgMockAr = p.getString(_kLegacyMsgMockAr) ?? defaultMsgMockAr;
      _msgMockEn = p.getString(_kLegacyMsgMockEn) ?? defaultMsgMockEn;
      _msgPermAr = p.getString(_kLegacyMsgPermAr) ?? defaultMsgPermAr;
      _msgPermEn = p.getString(_kLegacyMsgPermEn) ?? defaultMsgPermEn;

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

      final rawZones = p.getString(_kLegacyZones);
      _zones = [];
      if (rawZones != null && rawZones.isNotEmpty) {
        try {
          final list = json.decode(rawZones) as List;
          _zones = list
              .map((e) =>
                  LoginZone.fromJson(e as Map<String, dynamic>))
              .toList();
        } catch (_) {}
      }

      await _persist();
      for (final k in [
        _kLegacyEnabled, _kLegacyZones, _kLegacyScope,
        _kLegacyAccountIds, _kLegacyJobTitleIds, _kLegacyOverrides,
        _kLegacyCheckGps, _kLegacyCheckWifi, _kLegacyCheckIp,
        _kLegacyRejectMock, _kLegacyAllowVpn,
        _kLegacyMsgRejectedAr, _kLegacyMsgRejectedEn,
        _kLegacyMsgMockAr, _kLegacyMsgMockEn,
        _kLegacyMsgPermAr, _kLegacyMsgPermEn,
      ]) {
        await p.remove(k);
      }
    } catch (_) {/* ignore */}
  }

  Future<void> _persist() async {
    await AppSettingsService.instance.setJson(_kSettingKey, {
      'enabled': _enabled,
      'scope': _scope.key(),
      'accountIds': _accountIds.toList(),
      'jobTitleIds': _jobTitleIds.toList(),
      'overrides': _overrides,
      'checkGps': _checkGps,
      'checkWifi': _checkWifi,
      'checkIp': _checkIp,
      'rejectMock': _rejectMock,
      'allowVpn': _allowVpn,
      'msgRejectedAr': _msgRejectedAr,
      'msgRejectedEn': _msgRejectedEn,
      'msgMockAr': _msgMockAr,
      'msgMockEn': _msgMockEn,
      'msgPermAr': _msgPermAr,
      'msgPermEn': _msgPermEn,
      'zones': _zones.map((z) => z.toJson()).toList(),
    });
  }

  // ===== Setters =====
  Future<void> setEnabled(bool v) async {
    _enabled = v;
    await _persist();
    notifyListeners();
  }

  Future<void> setScope(GeoFenceScope s) async {
    _scope = s;
    await _persist();
    notifyListeners();
  }

  Future<void> setCheckGps(bool v) async {
    _checkGps = v;
    await _persist();
    notifyListeners();
  }

  Future<void> setCheckWifi(bool v) async {
    _checkWifi = v;
    await _persist();
    notifyListeners();
  }

  Future<void> setCheckIp(bool v) async {
    _checkIp = v;
    await _persist();
    notifyListeners();
  }

  Future<void> setRejectMock(bool v) async {
    _rejectMock = v;
    await _persist();
    notifyListeners();
  }

  Future<void> setAllowVpn(bool v) async {
    _allowVpn = v;
    await _persist();
    notifyListeners();
  }

  Future<void> setMsgRejectedAr(String v) async {
    _msgRejectedAr = v.trim().isEmpty ? defaultMsgRejectedAr : v.trim();
    await _persist();
    notifyListeners();
  }

  Future<void> setMsgRejectedEn(String v) async {
    _msgRejectedEn = v.trim().isEmpty ? defaultMsgRejectedEn : v.trim();
    await _persist();
    notifyListeners();
  }

  Future<void> setMsgMockAr(String v) async {
    _msgMockAr = v.trim().isEmpty ? defaultMsgMockAr : v.trim();
    await _persist();
    notifyListeners();
  }

  Future<void> setMsgMockEn(String v) async {
    _msgMockEn = v.trim().isEmpty ? defaultMsgMockEn : v.trim();
    await _persist();
    notifyListeners();
  }

  Future<void> setMsgPermAr(String v) async {
    _msgPermAr = v.trim().isEmpty ? defaultMsgPermAr : v.trim();
    await _persist();
    notifyListeners();
  }

  Future<void> setMsgPermEn(String v) async {
    _msgPermEn = v.trim().isEmpty ? defaultMsgPermEn : v.trim();
    await _persist();
    notifyListeners();
  }

  // ====== Account / JobTitle lists ======
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

  Future<void> setOverride(String accountId, bool? enabled) async {
    if (enabled == null) {
      _overrides.remove(accountId);
    } else {
      _overrides[accountId] = enabled;
    }
    await _persist();
    notifyListeners();
  }

  // ====== Zones CRUD ======
  Future<void> upsertZone(LoginZone zone) async {
    final i = _zones.indexWhere((z) => z.id == zone.id);
    if (i >= 0) {
      _zones[i] = zone;
    } else {
      _zones.add(zone);
    }
    await _persist();
    notifyListeners();
  }

  Future<void> removeZone(String id) async {
    _zones.removeWhere((z) => z.id == id);
    await _persist();
    notifyListeners();
  }

  Future<void> setZoneActive(String id, bool active) async {
    final i = _zones.indexWhere((z) => z.id == id);
    if (i < 0) return;
    _zones[i].isActive = active;
    await _persist();
    notifyListeners();
  }

  Future<void> resetToDefaults() async {
    _enabled = defaultEnabled;
    _zones = [];
    _scope = defaultScope;
    _accountIds = <String>{};
    _jobTitleIds = <String>{};
    _overrides = <String, bool>{};
    _checkGps = defaultCheckGps;
    _checkWifi = defaultCheckWifi;
    _checkIp = defaultCheckIp;
    _rejectMock = defaultRejectMock;
    _allowVpn = defaultAllowVpn;
    _msgRejectedAr = defaultMsgRejectedAr;
    _msgRejectedEn = defaultMsgRejectedEn;
    _msgMockAr = defaultMsgMockAr;
    _msgMockEn = defaultMsgMockEn;
    _msgPermAr = defaultMsgPermAr;
    _msgPermEn = defaultMsgPermEn;
    await _persist();
    notifyListeners();
  }
}
