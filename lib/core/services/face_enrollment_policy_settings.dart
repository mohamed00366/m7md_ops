import 'app_settings_service.dart';

/// 🔐 سياسة تَسجيل بَصمة الوَجه الإجباريّ
///
/// عِندَ إنشاء حِساب لِمُوظَّف، إذا كان ضِمن المُسَمَّيات المَشمولة بِالسياسة،
/// يُضبَط `mustEnrollFace=true` على حِسابه. عِندَ أَوَّل تَسجيل دُخول
/// (بَعدَ تَغيير كلِمة المُرور المُؤَقَّتة)، يَتِم تَحويله إلى شاشة
/// `FaceEnrollmentScreen` ولا يُسمَح لَه بِالدُخول قَبل اكتِمال التَسجيل.
///
/// **التَخزين:** Supabase `app_settings` (key=`face_enrollment_policy`)
///   + كاش محلّيّ. عَبر `AppSettingsService`.
///
/// **البَيانات المَحفوظة:**
///   - `enabled`: تَفعيل/تَعطيل السياسة كَكُلّ.
///   - `allJobTitles`: إذا true → كُلّ المُسَمَّيات. إذا false → فَقَط القائِمة أَدناه.
///   - `allowedJobTitleIds`: قائِمة المُسَمَّيات المَشمولة (إذا allJobTitles=false).
///   - `gracePeriodHours`: عَدَد الساعات المَسموح فيها بِتأجيل التَسجيل
///       (0 = إجباريّ من أَوَّل دُخول).
///   - `minPoses`: عَدَد زَوايا الوَجه الإجباريّ تَسجيلها (افتِراضيّاً 5).
///   - `forceFaceLoginAfter`: إذا true → بَعدَ التَسجيل تُحَوَّل
///       طَريقة دُخول الحِساب إلى "وَجه" تِلقائيّاً.
class FaceEnrollmentPolicySettings {
  FaceEnrollmentPolicySettings._();
  static final instance = FaceEnrollmentPolicySettings._();

  static const _kKey = 'face_enrollment_policy';

  bool _enabled = false;
  bool _allJobTitles = false;
  Set<String> _allowedJobTitleIds = {};
  int _gracePeriodHours = 24;
  int _minPoses = 5;
  bool _forceFaceLoginAfter = false;
  bool _loaded = false;

  bool get enabled => _enabled;
  bool get allJobTitles => _allJobTitles;
  Set<String> get allowedJobTitleIds => Set.unmodifiable(_allowedJobTitleIds);
  int get gracePeriodHours => _gracePeriodHours;
  int get minPoses => _minPoses;
  bool get forceFaceLoginAfter => _forceFaceLoginAfter;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final v = await AppSettingsService.instance.getJson(_kKey);
      if (v != null) {
        _enabled = v['enabled'] as bool? ?? false;
        _allJobTitles = v['allJobTitles'] as bool? ?? false;
        _allowedJobTitleIds = ((v['allowedJobTitleIds'] as List?) ?? const [])
            .map((e) => e.toString())
            .toSet();
        _gracePeriodHours = (v['gracePeriodHours'] as num?)?.toInt() ?? 24;
        _minPoses = (v['minPoses'] as num?)?.toInt() ?? 5;
        _forceFaceLoginAfter = v['forceFaceLoginAfter'] as bool? ?? false;
      }
    } catch (_) {/* defaults */}
    _loaded = true;
  }

  /// إعادة تَحميل قَسرِيّة (لِشاشة الإعدادات بَعد الحِفظ)
  Future<void> reload() async {
    _loaded = false;
    await load();
  }

  Future<bool> save({
    required bool enabled,
    required bool allJobTitles,
    required Set<String> allowedJobTitleIds,
    required int gracePeriodHours,
    required int minPoses,
    required bool forceFaceLoginAfter,
  }) async {
    _enabled = enabled;
    _allJobTitles = allJobTitles;
    _allowedJobTitleIds = allowedJobTitleIds.toSet();
    _gracePeriodHours = gracePeriodHours.clamp(0, 168);
    _minPoses = minPoses.clamp(1, 10);
    _forceFaceLoginAfter = forceFaceLoginAfter;
    _loaded = true;
    return AppSettingsService.instance.setJson(_kKey, {
      'enabled': _enabled,
      'allJobTitles': _allJobTitles,
      'allowedJobTitleIds': _allowedJobTitleIds.toList(),
      'gracePeriodHours': _gracePeriodHours,
      'minPoses': _minPoses,
      'forceFaceLoginAfter': _forceFaceLoginAfter,
    });
  }

  /// 🧠 هَل المُسَمَّى الوَظيفيّ مَشمول بِالسياسة؟
  ///
  /// يَرجِع false إذا السياسة مُعَطَّلة أَو المُسَمَّى لا ضِمن القائِمة.
  bool requiresEnrollment(String? jobTitleId) {
    if (!_enabled) return false;
    if (_allJobTitles) return true;
    if (jobTitleId == null || jobTitleId.isEmpty) return false;
    return _allowedJobTitleIds.contains(jobTitleId);
  }

  /// 🕐 هَل لا تَزال مُهلة التَأجيل سارِية؟
  ///
  /// تُستَدعى من بَوّابة الـRouter لِمَعرِفة هَل يَدخُل الموظَّف الآن
  /// أَم يُحَوَّل إلى التَسجيل.
  /// إذا `firstLoginAt == null` → لا مُهلة بَعد، يَجِب التَسجيل فَوراً
  /// (إلا إذا gracePeriodHours > 0 يُسَجَّل firstLoginAt و يُسمَح بِالدُخول).
  bool isWithinGracePeriod(DateTime? firstLoginAt) {
    if (_gracePeriodHours <= 0) return false;
    if (firstLoginAt == null) return true; // أَوَّل دُخول — بِداية المُهلة
    final elapsed = DateTime.now().difference(firstLoginAt);
    return elapsed.inHours < _gracePeriodHours;
  }
}
