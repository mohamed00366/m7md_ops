import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings_service.dart';

/// 🎓 إعدادات صفحة تدريب الموظفين الجدد (OnPoint Training)
///
/// تتحكّم في:
///   • مدّة التدريب الافتراضيّة (أيام)
///   • مَن يحقّ له الاعتماد/التقييم (Job Title IDs)
///   • التوقيعات الإلزاميّة (employee/op_supervisor/camp_boss/hr)
///   • إنشاء سجلّ تلقائي عند تسجيل موظف كمتدرّب
///   • طلب صورة إجباريّ
///   • حدّ المستوى الأدنى للاعتماد
///
/// **التخزين:** عبر `AppSettingsService` (Supabase + كاش محلّي)
class OnPointTrainingSettings extends ChangeNotifier {
  OnPointTrainingSettings._();
  static final instance = OnPointTrainingSettings._();

  /// مفتاح الإعداد في Supabase + الكاش المحلّي.
  static const _kSettingKey = 'on_point_training';

  // مفاتيح legacy (للهجرة فقط)
  static const _kLegacyDefaultDays = 'onpoint_default_days_v1';
  static const _kLegacyApproverJobTitleIds = 'onpoint_approver_jt_ids_v1';
  static const _kLegacyRequireEmployeeSig =
      'onpoint_require_employee_sig_v1';
  static const _kLegacyRequireOpSupervisorSig =
      'onpoint_require_op_supervisor_sig_v1';
  static const _kLegacyRequireCampBossSig =
      'onpoint_require_camp_boss_sig_v1';
  static const _kLegacyRequireHrSig = 'onpoint_require_hr_sig_v1';
  static const _kLegacyAutoCreate = 'onpoint_auto_create_v1';
  static const _kLegacyRequirePhoto = 'onpoint_require_photo_v1';
  static const _kLegacyMinAcceptableLevel =
      'onpoint_min_acceptable_level_v1';

  // ===== القيم الافتراضيّة =====
  static const defaultDays = 7;
  static const defaultRequireEmployeeSig = true;
  static const defaultRequireOpSupervisorSig = true;
  static const defaultRequireCampBossSig = false;
  static const defaultRequireHrSig = true;
  static const defaultAutoCreate = true;
  static const defaultRequirePhoto = false;
  /// 'a' = ممتاز فقط، 'b' = جيد فأعلى، 'c' = مقبول فأعلى
  static const defaultMinAcceptableLevel = 'c';

  int _defaultDays = defaultDays;
  Set<String> _approverJobTitleIds = {};
  bool _requireEmployeeSig = defaultRequireEmployeeSig;
  bool _requireOpSupervisorSig = defaultRequireOpSupervisorSig;
  bool _requireCampBossSig = defaultRequireCampBossSig;
  bool _requireHrSig = defaultRequireHrSig;
  bool _autoCreate = defaultAutoCreate;
  bool _requirePhoto = defaultRequirePhoto;
  String _minAcceptableLevel = defaultMinAcceptableLevel;
  bool _loaded = false;

  bool get isLoaded => _loaded;
  int get defaultDaysValue => _defaultDays;
  Set<String> get approverJobTitleIds => Set.unmodifiable(_approverJobTitleIds);
  bool get requireEmployeeSig => _requireEmployeeSig;
  bool get requireOpSupervisorSig => _requireOpSupervisorSig;
  bool get requireCampBossSig => _requireCampBossSig;
  bool get requireHrSig => _requireHrSig;
  bool get autoCreate => _autoCreate;
  bool get requirePhoto => _requirePhoto;
  String get minAcceptableLevel => _minAcceptableLevel;

  /// كم توقيعاً إلزاميّاً
  int get requiredSignaturesCount {
    var n = 0;
    if (_requireEmployeeSig) n++;
    if (_requireOpSupervisorSig) n++;
    if (_requireCampBossSig) n++;
    if (_requireHrSig) n++;
    return n;
  }

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
    _defaultDays = (v['defaultDays'] as num?)?.toInt() ?? defaultDays;
    final rawApprovers = v['approverJobTitleIds'] as List?;
    _approverJobTitleIds =
        rawApprovers?.map((e) => e.toString()).toSet() ?? <String>{};
    _requireEmployeeSig =
        v['requireEmployeeSig'] as bool? ?? defaultRequireEmployeeSig;
    _requireOpSupervisorSig =
        v['requireOpSupervisorSig'] as bool? ?? defaultRequireOpSupervisorSig;
    _requireCampBossSig =
        v['requireCampBossSig'] as bool? ?? defaultRequireCampBossSig;
    _requireHrSig = v['requireHrSig'] as bool? ?? defaultRequireHrSig;
    _autoCreate = v['autoCreate'] as bool? ?? defaultAutoCreate;
    _requirePhoto = v['requirePhoto'] as bool? ?? defaultRequirePhoto;
    _minAcceptableLevel =
        v['minAcceptableLevel']?.toString() ?? defaultMinAcceptableLevel;
  }

  Future<void> _migrateLegacyKeys() async {
    try {
      final p = await SharedPreferences.getInstance();
      final hasLegacy = p.containsKey(_kLegacyDefaultDays) ||
          p.containsKey(_kLegacyApproverJobTitleIds) ||
          p.containsKey(_kLegacyRequireEmployeeSig) ||
          p.containsKey(_kLegacyRequireOpSupervisorSig) ||
          p.containsKey(_kLegacyRequireCampBossSig) ||
          p.containsKey(_kLegacyRequireHrSig) ||
          p.containsKey(_kLegacyAutoCreate) ||
          p.containsKey(_kLegacyRequirePhoto) ||
          p.containsKey(_kLegacyMinAcceptableLevel);
      if (!hasLegacy) return;
      _defaultDays = p.getInt(_kLegacyDefaultDays) ?? defaultDays;
      _approverJobTitleIds =
          (p.getStringList(_kLegacyApproverJobTitleIds) ?? <String>[])
              .toSet();
      _requireEmployeeSig = p.getBool(_kLegacyRequireEmployeeSig) ??
          defaultRequireEmployeeSig;
      _requireOpSupervisorSig =
          p.getBool(_kLegacyRequireOpSupervisorSig) ??
              defaultRequireOpSupervisorSig;
      _requireCampBossSig = p.getBool(_kLegacyRequireCampBossSig) ??
          defaultRequireCampBossSig;
      _requireHrSig = p.getBool(_kLegacyRequireHrSig) ?? defaultRequireHrSig;
      _autoCreate = p.getBool(_kLegacyAutoCreate) ?? defaultAutoCreate;
      _requirePhoto = p.getBool(_kLegacyRequirePhoto) ?? defaultRequirePhoto;
      _minAcceptableLevel = p.getString(_kLegacyMinAcceptableLevel) ??
          defaultMinAcceptableLevel;
      await _persist();
      await p.remove(_kLegacyDefaultDays);
      await p.remove(_kLegacyApproverJobTitleIds);
      await p.remove(_kLegacyRequireEmployeeSig);
      await p.remove(_kLegacyRequireOpSupervisorSig);
      await p.remove(_kLegacyRequireCampBossSig);
      await p.remove(_kLegacyRequireHrSig);
      await p.remove(_kLegacyAutoCreate);
      await p.remove(_kLegacyRequirePhoto);
      await p.remove(_kLegacyMinAcceptableLevel);
    } catch (_) {/* ignore */}
  }

  Future<void> _persist() async {
    await AppSettingsService.instance.setJson(_kSettingKey, {
      'defaultDays': _defaultDays,
      'approverJobTitleIds': _approverJobTitleIds.toList(),
      'requireEmployeeSig': _requireEmployeeSig,
      'requireOpSupervisorSig': _requireOpSupervisorSig,
      'requireCampBossSig': _requireCampBossSig,
      'requireHrSig': _requireHrSig,
      'autoCreate': _autoCreate,
      'requirePhoto': _requirePhoto,
      'minAcceptableLevel': _minAcceptableLevel,
    });
  }

  Future<void> setDefaultDays(int v) async {
    _defaultDays = v.clamp(1, 90);
    await _persist();
    notifyListeners();
  }

  Future<void> setApproverJobTitleIds(Set<String> ids) async {
    _approverJobTitleIds = Set<String>.from(ids);
    await _persist();
    notifyListeners();
  }

  Future<void> toggleApproverJobTitle(String id) async {
    if (_approverJobTitleIds.contains(id)) {
      _approverJobTitleIds.remove(id);
    } else {
      _approverJobTitleIds.add(id);
    }
    await _persist();
    notifyListeners();
  }

  Future<void> setRequireEmployeeSig(bool v) async {
    _requireEmployeeSig = v;
    await _persist();
    notifyListeners();
  }

  Future<void> setRequireOpSupervisorSig(bool v) async {
    _requireOpSupervisorSig = v;
    await _persist();
    notifyListeners();
  }

  Future<void> setRequireCampBossSig(bool v) async {
    _requireCampBossSig = v;
    await _persist();
    notifyListeners();
  }

  Future<void> setRequireHrSig(bool v) async {
    _requireHrSig = v;
    await _persist();
    notifyListeners();
  }

  Future<void> setAutoCreate(bool v) async {
    _autoCreate = v;
    await _persist();
    notifyListeners();
  }

  Future<void> setRequirePhoto(bool v) async {
    _requirePhoto = v;
    await _persist();
    notifyListeners();
  }

  Future<void> setMinAcceptableLevel(String level) async {
    if (!{'a', 'b', 'c'}.contains(level)) return;
    _minAcceptableLevel = level;
    await _persist();
    notifyListeners();
  }

  /// هل المستوى المُختار مقبول وفق الإعدادات؟
  /// 'a' أعلى من 'b' أعلى من 'c'.
  /// إن كانت العتبة 'b' فلا يُقبل 'c'.
  bool isLevelAcceptable(String? level) {
    if (level == null) return false;
    const order = {'a': 1, 'b': 2, 'c': 3};
    final picked = order[level] ?? 99;
    final threshold = order[_minAcceptableLevel] ?? 3;
    return picked <= threshold;
  }

  Future<void> resetToDefaults() async {
    _defaultDays = defaultDays;
    _approverJobTitleIds = {};
    _requireEmployeeSig = defaultRequireEmployeeSig;
    _requireOpSupervisorSig = defaultRequireOpSupervisorSig;
    _requireCampBossSig = defaultRequireCampBossSig;
    _requireHrSig = defaultRequireHrSig;
    _autoCreate = defaultAutoCreate;
    _requirePhoto = defaultRequirePhoto;
    _minAcceptableLevel = defaultMinAcceptableLevel;
    await _persist();
    notifyListeners();
  }
}
