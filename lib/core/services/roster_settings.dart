import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/enums.dart';
import '../../models/models.dart';
import 'app_settings_service.dart';

/// 📅 إعدادات الروسترات (قابلة للتخصيص من Settings Hub)
///
/// تتحكّم في:
///   1. قفل الأيام السابقة (toggle + grace days)
///   2. الأنماط الجاهزة للتعبئة السريعة (5×2 صباحي، 5×2 ليلي، 6×1، أو مخصّص)
///   3. السماح بفتح الروستر المعتمد للتعديل
///   4. حدود التنبيه: ساعات أسبوعية قصوى + حد أدنى لعدد الموظفين بالنقطة
///
/// **التخزين:** عبر `AppSettingsService` (Supabase + كاش محلّي)
///   - Supabase: جدول `app_settings`، key=`roster_settings`
///   - SharedPreferences: كاش محلّي + هجرة من المفاتيح القديمة _v1
class RosterSettings extends ChangeNotifier {
  RosterSettings._();
  static final instance = RosterSettings._();

  /// مفتاح الإعداد في Supabase + الكاش المحلّي.
  static const _kSettingKey = 'roster_settings';

  // مفاتيح legacy (للهجرة فقط)
  static const _kLegacyLockEnabled = 'roster_lock_past_enabled_v1';
  static const _kLegacyLockGraceDays = 'roster_lock_past_grace_days_v1';
  static const _kLegacyPatterns = 'roster_patterns_v1';
  static const _kLegacyAllowReopen = 'roster_allow_reopen_approved_v1';
  static const _kLegacyMaxWeekly = 'roster_max_weekly_hours_warning_v1';
  static const _kLegacyMinStaff = 'roster_min_staff_per_point_v1';

  // ===== القيم الافتراضيّة =====
  static const defaultLockEnabled = true;
  static const defaultLockGraceDays = 0;
  static const defaultAllowReopen = true;
  static const defaultMaxWeekly = 60;
  static const defaultMinStaff = 2;

  bool _lockEnabled = defaultLockEnabled;
  int _lockGraceDays = defaultLockGraceDays;
  bool _allowReopen = defaultAllowReopen;
  int _maxWeekly = defaultMaxWeekly;
  int _minStaff = defaultMinStaff;
  List<RosterPatternConfig> _patterns = _builtInPatterns();
  bool _loaded = false;

  bool get lockEnabled => _lockEnabled;
  int get lockGraceDays => _lockGraceDays;
  bool get allowReopen => _allowReopen;
  int get maxWeekly => _maxWeekly;
  int get minStaff => _minStaff;
  List<RosterPatternConfig> get patterns => List.unmodifiable(_patterns);
  bool get isLoaded => _loaded;

  // ============================================================
  // تحميل: 1) Supabase 2) كاش 3) Legacy migration
  // ============================================================
  Future<void> load() async {
    if (_loaded) return;
    try {
      // 1) جرّب القراءة من Supabase + الكاش (الخدمة تعالج fallback)
      final v = await AppSettingsService.instance.getJson(_kSettingKey);
      if (v != null) {
        _readFromJson(v);
      } else {
        // 2) ابحث في المفاتيح القديمة وهاجرها
        await _migrateLegacyKeys();
      }
    } catch (_) {/* keep defaults */}
    _loaded = true;
    _installDelegates();
  }

  void _readFromJson(Map<String, dynamic> v) {
    _lockEnabled = v['lockEnabled'] as bool? ?? defaultLockEnabled;
    _lockGraceDays =
        ((v['lockGraceDays'] as num?)?.toInt() ?? defaultLockGraceDays)
            .clamp(0, 30);
    _allowReopen = v['allowReopen'] as bool? ?? defaultAllowReopen;
    _maxWeekly = (v['maxWeekly'] as num?)?.toInt() ?? defaultMaxWeekly;
    _minStaff = (v['minStaff'] as num?)?.toInt() ?? defaultMinStaff;
    final rawPatterns = v['patterns'] as List?;
    if (rawPatterns != null) {
      try {
        _patterns = rawPatterns
            .map((e) => RosterPatternConfig.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList();
      } catch (_) {
        _patterns = _builtInPatterns();
      }
    }
  }

  /// هجرة قيم النسخة السابقة (مفاتيح _v1) إلى المفتاح الموحَّد.
  Future<void> _migrateLegacyKeys() async {
    try {
      final p = await SharedPreferences.getInstance();
      final hasLegacy = p.containsKey(_kLegacyLockEnabled) ||
          p.containsKey(_kLegacyLockGraceDays) ||
          p.containsKey(_kLegacyPatterns);
      if (!hasLegacy) return;
      _lockEnabled = p.getBool(_kLegacyLockEnabled) ?? defaultLockEnabled;
      _lockGraceDays =
          (p.getInt(_kLegacyLockGraceDays) ?? defaultLockGraceDays)
              .clamp(0, 30);
      _allowReopen = p.getBool(_kLegacyAllowReopen) ?? defaultAllowReopen;
      _maxWeekly = p.getInt(_kLegacyMaxWeekly) ?? defaultMaxWeekly;
      _minStaff = p.getInt(_kLegacyMinStaff) ?? defaultMinStaff;
      // احفظ في الصيغة الجديدة
      await _persist();
      // امسح المفاتيح القديمة
      await p.remove(_kLegacyLockEnabled);
      await p.remove(_kLegacyLockGraceDays);
      await p.remove(_kLegacyAllowReopen);
      await p.remove(_kLegacyMaxWeekly);
      await p.remove(_kLegacyMinStaff);
      await p.remove(_kLegacyPatterns);
    } catch (_) {/* ignore */}
  }

  /// كتابة الإعدادات الكاملة في Supabase + الكاش.
  Future<void> _persist() async {
    await AppSettingsService.instance.setJson(_kSettingKey, {
      'lockEnabled': _lockEnabled,
      'lockGraceDays': _lockGraceDays,
      'allowReopen': _allowReopen,
      'maxWeekly': _maxWeekly,
      'minStaff': _minStaff,
      'patterns': _patterns.map((e) => e.toJson()).toList(),
    });
  }

  /// يحقن المنطق المعتمد على الإعدادات في WeeklyRoster (لتفادي circular import)
  void _installDelegates() {
    WeeklyRoster.setDayLockDelegate((dayDate, todayDate) {
      if (!_lockEnabled) return false;
      final dDate = DateTime(dayDate.year, dayDate.month, dayDate.day);
      final tDate =
          DateTime(todayDate.year, todayDate.month, todayDate.day);
      if (dDate.isAfter(tDate)) return false;
      final grace = _lockGraceDays.clamp(0, 30);
      final cutoff = tDate.subtract(Duration(days: grace));
      return dDate.isBefore(cutoff);
    });
  }

  // ============================================================
  // Setters (يحفظ في DB + يخطر)
  // ============================================================
  Future<void> setLockEnabled(bool v) async {
    _lockEnabled = v;
    await _persist();
    _installDelegates();
    notifyListeners();
  }

  Future<void> setLockGraceDays(int days) async {
    _lockGraceDays = days.clamp(0, 30);
    await _persist();
    _installDelegates();
    notifyListeners();
  }

  Future<void> setAllowReopen(bool v) async {
    _allowReopen = v;
    await _persist();
    notifyListeners();
  }

  Future<void> setMaxWeekly(int h) async {
    _maxWeekly = h.clamp(1, 200);
    await _persist();
    notifyListeners();
  }

  Future<void> setMinStaff(int n) async {
    _minStaff = n.clamp(0, 100);
    await _persist();
    notifyListeners();
  }

  Future<void> setPatterns(List<RosterPatternConfig> list) async {
    _patterns = List<RosterPatternConfig>.from(list);
    await _persist();
    notifyListeners();
  }

  Future<void> resetToDefaults() async {
    _lockEnabled = defaultLockEnabled;
    _lockGraceDays = defaultLockGraceDays;
    _allowReopen = defaultAllowReopen;
    _maxWeekly = defaultMaxWeekly;
    _minStaff = defaultMinStaff;
    _patterns = _builtInPatterns();
    await _persist();
    _installDelegates();
    notifyListeners();
  }

  // ============================================================
  // منطق القفل: هل يجب قفل هذا اليوم؟
  // ============================================================
  bool shouldLockDay(DateTime dayDate, {DateTime? now}) {
    if (!_lockEnabled) return false;
    final today = now ?? DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final dDate = DateTime(dayDate.year, dayDate.month, dayDate.day);
    final cutoff = todayDate.subtract(Duration(days: _lockGraceDays));
    return dDate.isBefore(cutoff);
  }

  static List<RosterPatternConfig> _builtInPatterns() => [
        RosterPatternConfig(
          id: 'five_two_morning',
          nameAr: '٥×٢ صباحي',
          nameEn: '5×2 Morning',
          shifts: [
            for (var d = 0; d < 5; d++)
              ShiftSpec(
                  dayIndex: d,
                  start: '08:00',
                  end: '20:00',
                  type: ShiftType.morning),
          ],
        ),
        RosterPatternConfig(
          id: 'five_two_night',
          nameAr: '٥×٢ ليلي',
          nameEn: '5×2 Night',
          shifts: [
            for (var d = 0; d < 5; d++)
              ShiftSpec(
                  dayIndex: d,
                  start: '20:00',
                  end: '08:00',
                  type: ShiftType.night),
          ],
        ),
        RosterPatternConfig(
          id: 'six_one_morning',
          nameAr: '٦×١ صباحي',
          nameEn: '6×1 Morning',
          shifts: [
            for (var d = 0; d < 7; d++)
              if (d != 4) // الجمعة off
                ShiftSpec(
                    dayIndex: d,
                    start: '08:00',
                    end: '20:00',
                    type: ShiftType.morning),
          ],
        ),
      ];
}

// ============================================================
// نموذج النمط الجاهز
// ============================================================
class RosterPatternConfig {
  final String id;
  final String nameAr;
  final String nameEn;
  final List<ShiftSpec> shifts;

  RosterPatternConfig({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    required this.shifts,
  });

  /// shift لـ يوم معيّن (null = إجازة)
  ShiftSpec? shiftFor(int dayIndex) {
    for (final s in shifts) {
      if (s.dayIndex == dayIndex) return s;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'nameAr': nameAr,
        'nameEn': nameEn,
        'shifts': shifts.map((e) => e.toJson()).toList(),
      };

  factory RosterPatternConfig.fromJson(Map<String, dynamic> j) {
    return RosterPatternConfig(
      id: j['id']?.toString() ?? 'p_${DateTime.now().microsecondsSinceEpoch}',
      nameAr: j['nameAr']?.toString() ?? '?',
      nameEn: j['nameEn']?.toString() ?? '?',
      shifts: (j['shifts'] as List?)
              ?.map((e) => ShiftSpec.fromJson(
                  Map<String, dynamic>.from(e as Map)))
              .toList() ??
          [],
    );
  }
}

class ShiftSpec {
  final int dayIndex;
  final String start;
  final String end;
  final ShiftType type;

  const ShiftSpec({
    required this.dayIndex,
    required this.start,
    required this.end,
    required this.type,
  });

  Map<String, dynamic> toJson() => {
        'd': dayIndex,
        's': start,
        'e': end,
        't': type.name,
      };

  factory ShiftSpec.fromJson(Map<String, dynamic> j) {
    final typeName = j['t']?.toString() ?? 'morning';
    final type = ShiftType.values.firstWhere(
      (t) => t.name == typeName,
      orElse: () => ShiftType.morning,
    );
    return ShiftSpec(
      dayIndex: (j['d'] as num?)?.toInt() ?? 0,
      start: j['s']?.toString() ?? '08:00',
      end: j['e']?.toString() ?? '20:00',
      type: type,
    );
  }
}
