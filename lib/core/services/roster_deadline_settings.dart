import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings_service.dart';

/// 📅 إعدادات مواعيد الروستر — مزامَنة مع Supabase.
///
/// **القاعدة الافتراضيّة:**
///   - الإنشاء: يجب أن يُنشأ الروستر يوم **السبت** (6) أو قبله.
///   - المراجعة: يوم **الأحد** (7) — يومٌ كامل لمراجعته.
///   - بدء التطبيق: يبدأ العمل بالروستر من يوم **الإثنين** (1).
///
/// **التخزين:**
///   - Supabase: جدول `app_settings`، key=`roster_deadline`.
///   - SharedPreferences: كاش محلّي للسرعة وللعمل بلا اتّصال.
///   - عبر `AppSettingsService` (انظر التعليقات هناك للسلوك الكامل).
class RosterDeadlineSettings {
  RosterDeadlineSettings._();
  static final instance = RosterDeadlineSettings._();

  /// مفتاح الإعداد في Supabase + SharedPreferences.
  static const _kSettingKey = 'roster_deadline';

  // ⚠️ قيم Dart's DateTime.weekday: 1=Mon..7=Sun
  int _deadlineDay = DateTime.saturday;
  int _reviewDay = DateTime.sunday;
  int _effectiveDay = DateTime.monday;
  bool _enableAlerts = true;
  int _alertHour = 16;

  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    // 1) جرّب القراءة من Supabase + الكاش (الخدمة تعالج fallback)
    try {
      final v = await AppSettingsService.instance.getJson(_kSettingKey);
      if (v != null) {
        _deadlineDay = (v['deadlineDay'] as num?)?.toInt() ?? DateTime.saturday;
        _reviewDay = (v['reviewDay'] as num?)?.toInt() ?? DateTime.sunday;
        _effectiveDay =
            (v['effectiveDay'] as num?)?.toInt() ?? DateTime.monday;
        _enableAlerts = v['enableAlerts'] as bool? ?? true;
        _alertHour = (v['alertHour'] as num?)?.toInt() ?? 16;
      } else {
        // ابحث في الـ legacy keys (قبل التحويل) — هجرة من النسخة القديمة
        await _migrateLegacyKeys();
      }
    } catch (_) {/* keep defaults */}
    _loaded = true;
  }

  /// هجرة قيم النسخة السابقة (المخزَّنة بمفاتيح متفرّقة) إلى المفتاح الموحَّد.
  Future<void> _migrateLegacyKeys() async {
    try {
      final p = await SharedPreferences.getInstance();
      final hasLegacy = p.containsKey('roster_deadline_day_v1') ||
          p.containsKey('roster_review_day_v1') ||
          p.containsKey('roster_effective_day_v1');
      if (!hasLegacy) return;
      _deadlineDay =
          p.getInt('roster_deadline_day_v1') ?? DateTime.saturday;
      _reviewDay = p.getInt('roster_review_day_v1') ?? DateTime.sunday;
      _effectiveDay =
          p.getInt('roster_effective_day_v1') ?? DateTime.monday;
      _enableAlerts = p.getBool('roster_alerts_enabled_v1') ?? true;
      _alertHour = p.getInt('roster_alert_hour_v1') ?? 16;
      // احفظ في الصيغة الجديدة
      await _persist();
      // امسح المفاتيح القديمة لتجنّب التكرار
      await p.remove('roster_deadline_day_v1');
      await p.remove('roster_review_day_v1');
      await p.remove('roster_effective_day_v1');
      await p.remove('roster_alerts_enabled_v1');
      await p.remove('roster_alert_hour_v1');
    } catch (_) {/* ignore */}
  }

  Future<void> _persist() async {
    await AppSettingsService.instance.setJson(_kSettingKey, {
      'deadlineDay': _deadlineDay,
      'reviewDay': _reviewDay,
      'effectiveDay': _effectiveDay,
      'enableAlerts': _enableAlerts,
      'alertHour': _alertHour,
    });
  }

  Future<void> load() async => _ensureLoaded();

  int get deadlineDay => _deadlineDay;
  int get reviewDay => _reviewDay;
  int get effectiveDay => _effectiveDay;
  bool get enableAlerts => _enableAlerts;
  int get alertHour => _alertHour;

  Future<void> setDeadlineDay(int d) async {
    await _ensureLoaded();
    _deadlineDay = d;
    await _persist();
  }

  Future<void> setReviewDay(int d) async {
    await _ensureLoaded();
    _reviewDay = d;
    await _persist();
  }

  Future<void> setEffectiveDay(int d) async {
    await _ensureLoaded();
    _effectiveDay = d;
    await _persist();
  }

  Future<void> setEnableAlerts(bool v) async {
    await _ensureLoaded();
    _enableAlerts = v;
    await _persist();
  }

  Future<void> setAlertHour(int h) async {
    await _ensureLoaded();
    _alertHour = h.clamp(0, 23);
    await _persist();
  }

  /// يُرجع تاريخ آخر يوم لإنشاء الروستر للأسبوع المُعطى (weekStart يوم الإثنين).
  DateTime deadlineDateFor(DateTime weekStart) {
    final diff = (_effectiveDay - _deadlineDay + 7) % 7;
    final adjusted = diff == 0 ? 7 : diff;
    return weekStart.subtract(Duration(days: adjusted));
  }

  /// يُرجع تاريخ يوم المراجعة (الأحد عادةً) للأسبوع المُعطى.
  DateTime reviewDateFor(DateTime weekStart) {
    final diff = (_effectiveDay - _reviewDay + 7) % 7;
    final adjusted = diff == 0 ? 7 : diff;
    return weekStart.subtract(Duration(days: adjusted));
  }

  /// حالة الموعد لروستر يبدأ في `weekStart` بناءً على `today`.
  RosterDeadlineStatus statusFor({
    required DateTime weekStart,
    DateTime? today,
  }) {
    final now = today ?? DateTime.now();
    final dayOnly = DateTime(now.year, now.month, now.day);
    final deadline = deadlineDateFor(weekStart);
    final effective = weekStart;

    if (dayOnly.isAfter(effective)) {
      return RosterDeadlineStatus.workStarted;
    }
    if (dayOnly.isAtSameMomentAs(effective)) {
      return RosterDeadlineStatus.workStarted;
    }
    if (dayOnly.isAfter(deadline) && dayOnly.isBefore(effective)) {
      return RosterDeadlineStatus.reviewWindow;
    }
    if (dayOnly.isAtSameMomentAs(deadline)) {
      return RosterDeadlineStatus.lastDay;
    }
    if (dayOnly.isBefore(deadline)) {
      return RosterDeadlineStatus.onTime;
    }
    return RosterDeadlineStatus.onTime;
  }

  /// كم يوماً متبقّياً للـ deadline (سالب لو فات).
  int daysToDeadline({
    required DateTime weekStart,
    DateTime? today,
  }) {
    final now = today ?? DateTime.now();
    final dayOnly = DateTime(now.year, now.month, now.day);
    final deadline = deadlineDateFor(weekStart);
    return deadline.difference(dayOnly).inDays;
  }

  static String dayLabelAr(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'الإثنين';
      case DateTime.tuesday:
        return 'الثلاثاء';
      case DateTime.wednesday:
        return 'الأربعاء';
      case DateTime.thursday:
        return 'الخميس';
      case DateTime.friday:
        return 'الجمعة';
      case DateTime.saturday:
        return 'السبت';
      case DateTime.sunday:
        return 'الأحد';
      default:
        return '?';
    }
  }

  static String dayLabelEn(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'Monday';
      case DateTime.tuesday:
        return 'Tuesday';
      case DateTime.wednesday:
        return 'Wednesday';
      case DateTime.thursday:
        return 'Thursday';
      case DateTime.friday:
        return 'Friday';
      case DateTime.saturday:
        return 'Saturday';
      case DateTime.sunday:
        return 'Sunday';
      default:
        return '?';
    }
  }
}

/// حالات موعد الروستر بالنسبة لتاريخ اليوم.
enum RosterDeadlineStatus {
  onTime,
  lastDay,
  reviewWindow,
  workStarted,
}
