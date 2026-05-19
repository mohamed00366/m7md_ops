import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings_service.dart';

/// 📍 إعدادات إسناد الموظفين للنقاط
///
/// تتحكّم في:
///   1. **أيّ مسمّيات وظيفيّة** تظهر كمرشّحين عند ربط موظف بنقطة.
///   2. **المُسمّى الهَدَف للترقية** عند رَبط L4 بِنقطة.
///   3. **وَراثة صلاحيّات RBAC** للمُسمّى الهَدَف.
///
/// **التَخزين (dual-tier):**
///   - 🌐 **Supabase** هو المصدر الموثوق — كلّ المسؤولين يَرَون نَفس الإعداد.
///   - 💾 **SharedPreferences** كَكاش مَحلّيّ سَريع + يَعمل بدون اتّصال.
///
/// المفتاح في `app_settings`: `point_assignment_settings`.
class PointAssignmentSettings {
  PointAssignmentSettings._();
  static final instance = PointAssignmentSettings._();

  /// المفتاح في جَدول `app_settings` على Supabase.
  static const _settingsKey = 'point_assignment_settings';

  // ============================================================
  // مفاتيح الـSharedPreferences القديمة (للـmigration / fallback)
  // ============================================================
  static const _legacyPrefsEligible =
      'point_assignment_eligible_titles_v1';
  static const _legacyPrefsTarget =
      'point_assignment_promotion_target_v1';
  static const _legacyPrefsInherit =
      'point_assignment_inherit_supervisor_perms_v1';

  Set<String> _eligibleIds = {};
  bool _loaded = false;
  bool _hasCustomSetting = false;
  String? _promotionTargetJobTitleId;
  bool _inheritTargetPerms = true;

  /// المُسمّى الوظيفيّ الّذي يَتمّ الترقية إليه عند رَبط الموظّف بنقطة.
  /// إذا null → يَستعمل الافتراضيّ "Site Supervisor".
  String? get promotionTargetJobTitleId => _promotionTargetJobTitleId;

  /// إذا true: المُرَقّى يَرث كلّ صلاحيّات RBAC للمُسمّى الهَدَف.
  /// الافتراضيّ: true (وَراثة كاملة).
  bool get inheritTargetPerms => _inheritTargetPerms;

  /// المُختارة حالياً (sync — للـ UI)
  Set<String> get current => Set.unmodifiable(_eligibleIds);

  /// هل المسؤول وضع إعداداً مخصّصاً، أم نستخدم القاعدة الافتراضيّة؟
  bool get hasCustom => _hasCustomSetting;

  /// التحميل (يُستَدعى عند فَتح الشاشة + قَبل الترقية في الـauth)
  Future<Set<String>> load() async {
    await _ensureLoaded();
    return Set.unmodifiable(_eligibleIds);
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    // 1) جَرِّب Supabase أوّلاً (مع fallback تلقائيّ للكاش المحلّي)
    final json = await AppSettingsService.instance.getJson(_settingsKey);
    if (json != null) {
      _applyFromJson(json);
      _loaded = true;
      return;
    }
    // 2) إن لم يَكن في Supabase: حاول هجرة من الـSharedPreferences القديمة
    await _migrateFromLegacyPrefs();
    _loaded = true;
  }

  /// تَحويل الإعدادات إلى JSON map (لِلْتَخزين في Supabase).
  Map<String, dynamic> _toJson() => {
        'eligible_ids': _eligibleIds.toList(),
        'has_custom': _hasCustomSetting,
        'promotion_target_id': _promotionTargetJobTitleId,
        'inherit_target_perms': _inheritTargetPerms,
      };

  /// قراءة الإعدادات من JSON map.
  void _applyFromJson(Map<String, dynamic> j) {
    final list = j['eligible_ids'];
    if (list is List) {
      _eligibleIds = list.whereType<String>().toSet();
    }
    _hasCustomSetting = (j['has_custom'] as bool?) ?? _eligibleIds.isNotEmpty;
    _promotionTargetJobTitleId = j['promotion_target_id'] as String?;
    _inheritTargetPerms = (j['inherit_target_perms'] as bool?) ?? true;
  }

  /// هِجرة لِمَرّة واحدة من الـSharedPreferences القديمة (قَبل أن يَتَوفَّر Supabase).
  Future<void> _migrateFromLegacyPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_legacyPrefsEligible);
      if (list != null) {
        _eligibleIds = list.toSet();
        _hasCustomSetting = true;
      }
      _promotionTargetJobTitleId = prefs.getString(_legacyPrefsTarget);
      _inheritTargetPerms = prefs.getBool(_legacyPrefsInherit) ?? true;
      // إذا وَجدنا بيانات قديمة، ادفعها للسحابة الآن (ضمنيّاً)
      if (_hasCustomSetting ||
          _promotionTargetJobTitleId != null ||
          !_inheritTargetPerms) {
        await _save();
      }
    } catch (_) {
      _eligibleIds = {};
    }
  }

  /// حِفظ الإعدادات في Supabase + الكاش المحلّي.
  Future<bool> _save() async {
    return await AppSettingsService.instance.setJson(_settingsKey, _toJson());
  }

  /// تَعيين المُسمّى الهَدَف للترقية. null = العَودة للافتراضيّ.
  Future<void> setPromotionTarget(String? jobTitleId) async {
    await _ensureLoaded();
    _promotionTargetJobTitleId =
        (jobTitleId == null || jobTitleId.isEmpty) ? null : jobTitleId;
    await _save();
  }

  /// تَعيين علم وَراثة الصلاحيّات.
  Future<void> setInheritTargetPerms(bool value) async {
    await _ensureLoaded();
    _inheritTargetPerms = value;
    await _save();
  }

  /// إضافة/إزالة (toggle) لِمسمّى مُؤهَّل.
  Future<bool> toggle(String jobTitleId) async {
    await _ensureLoaded();
    final added = !_eligibleIds.contains(jobTitleId);
    if (added) {
      _eligibleIds.add(jobTitleId);
    } else {
      _eligibleIds.remove(jobTitleId);
    }
    _hasCustomSetting = true;
    await _save();
    return added;
  }

  /// تعيين القائمة كاملةً (للحفظ المجمّع)
  Future<void> setAll(Set<String> ids) async {
    await _ensureLoaded();
    _eligibleIds = Set<String>.from(ids);
    _hasCustomSetting = true;
    await _save();
  }

  /// إعادة تعيين إلى الافتراضيّ (يَحذف من Supabase + الكاش المحلّي).
  Future<void> resetToDefault() async {
    _eligibleIds = {};
    _hasCustomSetting = false;
    _promotionTargetJobTitleId = null;
    _inheritTargetPerms = true;
    _loaded = true;
    // احذف من Supabase + الكاش المحلّي
    await AppSettingsService.instance.delete(_settingsKey);
    // احذف الـlegacy keys أيضاً (تَنظيف)
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_legacyPrefsEligible);
      await prefs.remove(_legacyPrefsTarget);
      await prefs.remove(_legacyPrefsInherit);
    } catch (_) {}
  }

  /// هل المسمّى المعطى مؤهّل للظهور في شاشة الإسناد؟
  bool isEligible(String jobTitleId, Set<String> defaultEligibleIds) {
    if (!_hasCustomSetting) {
      return defaultEligibleIds.contains(jobTitleId);
    }
    return _eligibleIds.contains(jobTitleId);
  }

  /// 🆕 إعادة التَحميل من السحابة (للقاء التَغييرات الجَديدة من أَجهزة أخرى).
  Future<void> reload() async {
    _loaded = false;
    await _ensureLoaded();
  }
}
