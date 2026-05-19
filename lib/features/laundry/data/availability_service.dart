// =============================================================================
// 🕐 خِدمة حِساب تَوَفُّر الكَمب بُوص
// =============================================================================
// تَدعَم نِطاقات أَوقات تَعبُر مُنتَصَف اللَيل (مَثَلاً 15:00 → 04:00 صَباحاً)
// تَتَعامَل مَع: إجازات + طوارِئ + أَيّام الأُسبوع + ساعات يَوميّة
// =============================================================================

import '../domain/models.dart';
import 'laundry_datasource.dart';

class AvailabilityService {
  AvailabilityService._();
  static final AvailabilityService instance = AvailabilityService._();

  /// يَحسِب الحالة الحاليّة لِلكَمب بُوص
  ///
  /// [mode]: 'receive' = ساعات الاستِلام مِن المُوَظَّفين
  ///         'deliver' = ساعات تَسليم النَظيف
  Future<AvailabilityStatus> checkAvailability({
    required String campBossId,
    String mode = 'receive',
  }) async {
    final ds = LaundryDataSource.instance;
    final schedule = await ds.getSchedule(campBossId);
    if (schedule == null) {
      // لا جَدوَل → مَفتوح افتِراضيّاً
      return const AvailabilityStatus(state: AvailabilityState.open);
    }

    final now = DateTime.now();

    // 1) وَضع الطوارِئ
    if (schedule.emergencyModeActive) {
      final until = schedule.emergencyUntil;
      if (until == null || now.isBefore(until)) {
        return AvailabilityStatus(
          state: AvailabilityState.emergency,
          reason: schedule.emergencyReason,
          nextOpenAt: until,
        );
      }
    }

    // 2) إجازة استِثنائيّة اليَوم؟
    final holidays = await ds.getHolidays(campBossId);
    final today = DateTime(now.year, now.month, now.day);
    final isHoliday = holidays.any((d) =>
        d.year == today.year &&
        d.month == today.month &&
        d.day == today.day);
    if (isHoliday) {
      // ابحَث عَن أَوَّل يَوم لَيس إجازة
      DateTime? next;
      for (var i = 1; i <= 14; i++) {
        final candidate = today.add(Duration(days: i));
        final isCandidateHoliday = holidays.any((d) =>
            d.year == candidate.year &&
            d.month == candidate.month &&
            d.day == candidate.day);
        if (!isCandidateHoliday) {
          next = candidate;
          break;
        }
      }
      return AvailabilityStatus(
        state: AvailabilityState.holiday,
        nextOpenAt: next,
        reason: 'إجازة استِثنائيّة',
      );
    }

    // 3) أَيّام الأُسبوع المَسموحة + ساعات اليَوم
    final dayIdx = _dayIndex(now); // 0=سَبت ... 6=جُمعة
    final days =
        mode == 'deliver' ? schedule.deliverDays : schedule.receiveDays;
    final start = mode == 'deliver'
        ? schedule.deliverStartTime
        : schedule.receiveStartTime;
    final end =
        mode == 'deliver' ? schedule.deliverEndTime : schedule.receiveEndTime;

    final isAllowedDay = days.contains(dayIdx);
    final inWindow = _isInTimeWindow(now, start, end);

    if (isAllowedDay && inWindow) {
      // مَفتوح — احسُب وَقت الإغلاق
      final closesAt = _resolveCloseTime(now, end);
      // closing soon = أَقَلّ مِن سَاعة
      final state = closesAt.difference(now).inMinutes < 60
          ? AvailabilityState.closingSoon
          : AvailabilityState.open;
      return AvailabilityStatus(state: state, closesAt: closesAt);
    }

    // مُغلَق — احسُب وَقت الفَتح القادِم
    final nextOpen = _calcNextOpenTime(now, days, start);
    return AvailabilityStatus(
      state: AvailabilityState.closed,
      nextOpenAt: nextOpen,
    );
  }

  /// تَحويل تاريخ إلى رَقَم اليَوم بِنَمط الجَدوَل (0=سَبت ... 6=جُمعة)
  /// Dart: 1=الإثنَين ... 7=الأَحَد
  int _dayIndex(DateTime d) {
    // weekday: Mon=1, Tue=2, Wed=3, Thu=4, Fri=5, Sat=6, Sun=7
    // المَطلوب: Sat=0, Sun=1, Mon=2, Tue=3, Wed=4, Thu=5, Fri=6
    switch (d.weekday) {
      case DateTime.saturday:  return 0;
      case DateTime.sunday:    return 1;
      case DateTime.monday:    return 2;
      case DateTime.tuesday:   return 3;
      case DateTime.wednesday: return 4;
      case DateTime.thursday:  return 5;
      case DateTime.friday:    return 6;
      default:                 return 0;
    }
  }

  /// هَل الوَقت الحاليّ ضِمن النِطاق؟ يَدعَم النِطاقات الَّتي تَعبُر مُنتَصَف اللَيل
  bool _isInTimeWindow(DateTime now, String startStr, String endStr) {
    final start = _parseTime(startStr);
    final end = _parseTime(endStr);
    final nowMin = now.hour * 60 + now.minute;

    if (start <= end) {
      // نِطاق عاديّ — 8:00 → 16:00
      return nowMin >= start && nowMin <= end;
    } else {
      // نِطاق يَعبُر مُنتَصَف اللَيل — 15:00 → 04:00
      return nowMin >= start || nowMin <= end;
    }
  }

  int _parseTime(String s) {
    final parts = s.split(':');
    final h = int.tryParse(parts[0]) ?? 0;
    final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    return h * 60 + m;
  }

  /// وَقت الإغلاق المُتَوَقَّع
  DateTime _resolveCloseTime(DateTime now, String endStr) {
    final end = _parseTime(endStr);
    final endHour = end ~/ 60;
    final endMin = end % 60;
    final start = _parseTime(endStr); // not used directly
    // لَو السّاعة الحاليّة بَعد ساعة الإغلاق → الإغلاق غَداً
    final candidate = DateTime(now.year, now.month, now.day, endHour, endMin);
    if (candidate.isBefore(now)) {
      return candidate.add(const Duration(days: 1));
    }
    return candidate;
  }

  /// وَقت الفَتح القادِم
  DateTime? _calcNextOpenTime(
      DateTime now, List<int> days, String startStr) {
    if (days.isEmpty) return null;
    final start = _parseTime(startStr);
    final startHour = start ~/ 60;
    final startMin = start % 60;

    // اِفحَص اليَوم + 14 يَوم تالٍ
    for (var i = 0; i < 14; i++) {
      final candidate = now.add(Duration(days: i));
      final dayIdx = _dayIndex(candidate);
      if (!days.contains(dayIdx)) continue;
      final openAt = DateTime(candidate.year, candidate.month,
          candidate.day, startHour, startMin);
      if (openAt.isAfter(now)) {
        return openAt;
      }
    }
    return null;
  }
}
