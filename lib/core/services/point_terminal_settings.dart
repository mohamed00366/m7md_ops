import 'app_settings_service.dart';

/// 🏪 نِطاق مُطابَقة الوَجه عَلى جِهاز النُقطة
enum FaceMatchScope {
  /// مُوَظَّفو النُقطة فَقَط
  pointOnly,
  /// مُوَظَّفو الدَولة (الافتِراضيّ)
  country,
  /// كُلّ المُوَظَّفين النَشطين
  all,
}

extension FaceMatchScopeX on FaceMatchScope {
  String get key {
    switch (this) {
      case FaceMatchScope.pointOnly:
        return 'point_only';
      case FaceMatchScope.country:
        return 'country';
      case FaceMatchScope.all:
        return 'all';
    }
  }

  String labelAr() {
    switch (this) {
      case FaceMatchScope.pointOnly:
        return 'مُوَظَّفو النُقطة فَقَط';
      case FaceMatchScope.country:
        return 'مُوَظَّفو الدَولة';
      case FaceMatchScope.all:
        return 'كُلّ المُوَظَّفين';
    }
  }

  String labelEn() {
    switch (this) {
      case FaceMatchScope.pointOnly:
        return 'Point employees only';
      case FaceMatchScope.country:
        return 'Country employees';
      case FaceMatchScope.all:
        return 'All employees';
    }
  }

  static FaceMatchScope fromKey(String? k) {
    switch (k) {
      case 'point_only':
        return FaceMatchScope.pointOnly;
      case 'all':
        return FaceMatchScope.all;
      case 'country':
      default:
        return FaceMatchScope.country;
    }
  }
}

/// 🏪 إعدادات Point Terminal — قابِلة لِلتَهيئة من شاشة الإعدادات
///
/// **التَخزين:** Supabase `app_settings` (key=`point_terminal`)
class PointTerminalSettings {
  PointTerminalSettings._();
  static final instance = PointTerminalSettings._();

  static const _kKey = 'point_terminal';

  // الإفتِراضيّات
  static const int defaultGeoFenceRadiusM = 200;
  static const int defaultIdleTimeoutMinutes = 15;
  static const int defaultAutoLockCheckMinutes = 5;
  static const int defaultLateThresholdMinutes = 10;
  static const bool defaultRequireGps = false;
  static const bool defaultCaptureAuditPhoto = true;
  static const FaceMatchScope defaultFaceScope = FaceMatchScope.country;
  static const double defaultMatchConfidenceMin = 0.65;

  int _geoFenceRadiusM = defaultGeoFenceRadiusM;
  int _idleTimeoutMinutes = defaultIdleTimeoutMinutes;
  int _autoLockCheckMinutes = defaultAutoLockCheckMinutes;
  int _lateThresholdMinutes = defaultLateThresholdMinutes;
  bool _requireGps = defaultRequireGps;
  bool _captureAuditPhoto = defaultCaptureAuditPhoto;
  FaceMatchScope _faceScope = defaultFaceScope;
  double _matchConfidenceMin = defaultMatchConfidenceMin;
  // 🎭 استِثناء جَماعيّ مِن دُخول بَصمة الوَجه — حَسَب المُسَمَّى الوَظيفيّ
  Set<String> _faceLoginExcludedJobTitleIds = <String>{};
  bool _loaded = false;

  int get geoFenceRadiusM => _geoFenceRadiusM;
  int get idleTimeoutMinutes => _idleTimeoutMinutes;
  int get autoLockCheckMinutes => _autoLockCheckMinutes;
  int get lateThresholdMinutes => _lateThresholdMinutes;
  bool get requireGps => _requireGps;
  bool get captureAuditPhoto => _captureAuditPhoto;
  FaceMatchScope get faceScope => _faceScope;
  double get matchConfidenceMin => _matchConfidenceMin;
  Set<String> get faceLoginExcludedJobTitleIds =>
      Set<String>.unmodifiable(_faceLoginExcludedJobTitleIds);

  bool isJobTitleExcludedFromFaceLogin(String? jobTitleId) {
    if (jobTitleId == null || jobTitleId.isEmpty) return false;
    return _faceLoginExcludedJobTitleIds.contains(jobTitleId);
  }

  Future<void> load() async {
    if (_loaded) return;
    try {
      final v = await AppSettingsService.instance.getJson(_kKey);
      if (v != null) {
        _geoFenceRadiusM =
            (v['geoFenceRadiusM'] as num?)?.toInt() ?? defaultGeoFenceRadiusM;
        _idleTimeoutMinutes =
            (v['idleTimeoutMinutes'] as num?)?.toInt() ??
                defaultIdleTimeoutMinutes;
        _autoLockCheckMinutes =
            (v['autoLockCheckMinutes'] as num?)?.toInt() ??
                defaultAutoLockCheckMinutes;
        _lateThresholdMinutes =
            (v['lateThresholdMinutes'] as num?)?.toInt() ??
                defaultLateThresholdMinutes;
        _requireGps = v['requireGps'] as bool? ?? defaultRequireGps;
        _captureAuditPhoto =
            v['captureAuditPhoto'] as bool? ?? defaultCaptureAuditPhoto;
        _faceScope =
            FaceMatchScopeX.fromKey(v['faceScope'] as String?);
        _matchConfidenceMin =
            (v['matchConfidenceMin'] as num?)?.toDouble() ??
                defaultMatchConfidenceMin;
        final excluded = v['faceLoginExcludedJobTitleIds'];
        if (excluded is List) {
          _faceLoginExcludedJobTitleIds = excluded
              .whereType<String>()
              .where((s) => s.isNotEmpty)
              .toSet();
        } else {
          _faceLoginExcludedJobTitleIds = <String>{};
        }
      }
    } catch (_) {/* defaults */}
    _loaded = true;
  }

  Future<void> reload() async {
    _loaded = false;
    await load();
  }

  Future<bool> save({
    required int geoFenceRadiusM,
    required int idleTimeoutMinutes,
    required int autoLockCheckMinutes,
    required int lateThresholdMinutes,
    required bool requireGps,
    required bool captureAuditPhoto,
    required FaceMatchScope faceScope,
    required double matchConfidenceMin,
    Set<String>? faceLoginExcludedJobTitleIds,
  }) async {
    _geoFenceRadiusM = geoFenceRadiusM.clamp(20, 2000);
    _idleTimeoutMinutes = idleTimeoutMinutes.clamp(1, 240);
    _autoLockCheckMinutes = autoLockCheckMinutes.clamp(1, 60);
    _lateThresholdMinutes = lateThresholdMinutes.clamp(0, 120);
    _requireGps = requireGps;
    _captureAuditPhoto = captureAuditPhoto;
    _faceScope = faceScope;
    _matchConfidenceMin =
        matchConfidenceMin.clamp(0.50, 0.95);
    if (faceLoginExcludedJobTitleIds != null) {
      _faceLoginExcludedJobTitleIds = faceLoginExcludedJobTitleIds
          .where((s) => s.isNotEmpty)
          .toSet();
    }
    _loaded = true;
    return AppSettingsService.instance.setJson(_kKey, {
      'geoFenceRadiusM': _geoFenceRadiusM,
      'idleTimeoutMinutes': _idleTimeoutMinutes,
      'autoLockCheckMinutes': _autoLockCheckMinutes,
      'lateThresholdMinutes': _lateThresholdMinutes,
      'requireGps': _requireGps,
      'captureAuditPhoto': _captureAuditPhoto,
      'faceScope': _faceScope.key,
      'matchConfidenceMin': _matchConfidenceMin,
      'faceLoginExcludedJobTitleIds':
          _faceLoginExcludedJobTitleIds.toList(),
    });
  }
}
