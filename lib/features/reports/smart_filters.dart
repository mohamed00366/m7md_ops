// =============================================================================
// 📊 Smart Filters — shared filter state across the entire Reports Hub
// =============================================================================
// Set "Country: AE" + "Date range: last 30 days" once → every report card
// reflects it. Persisted in memory (per session). Future: persist to user_prefs.
// =============================================================================
import 'package:flutter/foundation.dart';

class DateRange {
  final DateTime start;
  final DateTime end;
  final String labelAr;
  final String labelEn;

  const DateRange({
    required this.start,
    required this.end,
    required this.labelAr,
    required this.labelEn,
  });

  static DateRange today() {
    final now = DateTime.now();
    final d = DateTime(now.year, now.month, now.day);
    return DateRange(
      start: d,
      end: d.add(const Duration(days: 1)),
      labelAr: 'اليَوم',
      labelEn: 'Today',
    );
  }

  static DateRange thisWeek() {
    final now = DateTime.now();
    final weekday = now.weekday;
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: weekday - 1));
    return DateRange(
      start: start,
      end: start.add(const Duration(days: 7)),
      labelAr: 'هذا الأُسبوع',
      labelEn: 'This week',
    );
  }

  static DateRange thisMonth() {
    final now = DateTime.now();
    return DateRange(
      start: DateTime(now.year, now.month, 1),
      end: DateTime(now.year, now.month + 1, 1),
      labelAr: 'هذا الشَهر',
      labelEn: 'This month',
    );
  }

  static DateRange last30Days() {
    final now = DateTime.now();
    return DateRange(
      start: now.subtract(const Duration(days: 30)),
      end: now,
      labelAr: 'آخِر 30 يَوم',
      labelEn: 'Last 30 days',
    );
  }

  static DateRange last90Days() {
    final now = DateTime.now();
    return DateRange(
      start: now.subtract(const Duration(days: 90)),
      end: now,
      labelAr: 'آخِر 90 يَوم',
      labelEn: 'Last 90 days',
    );
  }

  static DateRange thisYear() {
    final now = DateTime.now();
    return DateRange(
      start: DateTime(now.year, 1, 1),
      end: DateTime(now.year + 1, 1, 1),
      labelAr: 'هذا العام',
      labelEn: 'This year',
    );
  }

  static List<DateRange> presets() => [
        today(),
        thisWeek(),
        thisMonth(),
        last30Days(),
        last90Days(),
        thisYear(),
      ];

  String get startIso => start.toIso8601String().substring(0, 10);
  String get endIso => end.toIso8601String().substring(0, 10);
}

class SmartFilters extends ChangeNotifier {
  SmartFilters._();
  static final instance = SmartFilters._();

  // ===== Filters =====
  DateRange _dateRange = DateRange.last30Days();
  String? _countryId;
  String? _pointId;
  String? _departmentId;
  String? _employeeId;
  String? _jobTitleId;

  DateRange get dateRange => _dateRange;
  String? get countryId => _countryId;
  String? get pointId => _pointId;
  String? get departmentId => _departmentId;
  String? get employeeId => _employeeId;
  String? get jobTitleId => _jobTitleId;

  void setDateRange(DateRange r) {
    _dateRange = r;
    notifyListeners();
  }

  void setCountry(String? id) {
    _countryId = id;
    notifyListeners();
  }

  void setPoint(String? id) {
    _pointId = id;
    notifyListeners();
  }

  void setDepartment(String? id) {
    _departmentId = id;
    notifyListeners();
  }

  void setEmployee(String? id) {
    _employeeId = id;
    notifyListeners();
  }

  void setJobTitle(String? id) {
    _jobTitleId = id;
    notifyListeners();
  }

  void clearAll() {
    _dateRange = DateRange.last30Days();
    _countryId = null;
    _pointId = null;
    _departmentId = null;
    _employeeId = null;
    _jobTitleId = null;
    notifyListeners();
  }

  /// Returns a summary string for the filter bar
  String summary(bool isAr) {
    final parts = <String>[
      isAr ? _dateRange.labelAr : _dateRange.labelEn,
    ];
    if (_countryId != null) parts.add(isAr ? 'دَولة' : 'Country');
    if (_pointId != null) parts.add(isAr ? 'نُقطة' : 'Point');
    if (_departmentId != null) parts.add(isAr ? 'قِسم' : 'Dept');
    if (_jobTitleId != null) parts.add(isAr ? 'مُسَمَّى' : 'Title');
    return parts.join(' · ');
  }
}
