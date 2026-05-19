import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/l10n/app_strings.dart';
import '../core/providers/auth_provider.dart';
import '../core/services/leave_service.dart';
import '../core/theme/app_colors.dart';
import '../models/enums.dart';
import '../models/leave.dart';
import '../models/models.dart';
import '../repositories/mock_repository.dart';
import '../features/employee/employee_my_roster.dart';
import '../features/leave/my_leaves_screen.dart';
import '../features/employee/employee_schedule.dart';

/// 🌅 بَطاقة "يَومي" (My Day) — لَمحة شَخصيّة للمُستَخدِم على الصَفحة الرَئيسيّة.
///
/// تَعرِض في بَطاقة واحِدة مَعلومات اليَوم الشَخصيّة لِلمُستَخدِم:
///   • وَردِيّة اليَوم (من الروستر المُعتَمَد) — أَو "راحة"
///   • أَقرَب إجازة قادِمة (إن وُجِدَت)
///   • تَنبيهات الوَثائِق المُنتَهية قَريباً (≤30 يَوم)
///
/// تُكَمِّل (لا تُكَرِّر) ما تَعرِضه:
///   - TodaySnapshot   (إحصائيّات المُؤَسَّسة)
///   - MyTasksDigest   (الموافَقات والنَماذِج)
///   - TeamMomentsWidget (أعياد ميلاد وتَواريخ)
///
/// تَختَفي البَطاقة كَامِلَة إن لم يَكُن لِلمُستَخدِم بَيانات شَخصيّة (لا
/// مُوَظَّف مَربوط بِالحِساب).
class MyDayCard extends StatelessWidget {
  const MyDayCard({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final auth = context.watch<AuthProvider>();
    final repo = MockRepository();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final empId = auth.account?.employeeId;
    if (empId == null) return const SizedBox.shrink();
    final emp = repo.employeeById(empId);
    if (emp == null) return const SizedBox.shrink();

    // ============================================================
    // 1) وَردِيّة اليَوم — مِن الروستر المُعتَمَد لِلأُسبوع الحاليّ
    // ============================================================
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final todayDayIndex = today.weekday - 1; // 0..6 (Mon..Sun)

    RosterAssignment? todayShift;
    for (final r in repo.rosters) {
      if (r.status != RosterStatus.approved) continue;
      final rWeekStart = DateTime(
          r.weekStart.year, r.weekStart.month, r.weekStart.day);
      if (rWeekStart != monday) continue;
      for (final a in r.assignments) {
        if (a.employeeId != empId) continue;
        if (a.dayIndex == todayDayIndex) {
          todayShift = a;
          break;
        }
      }
      if (todayShift != null) break;
    }

    // ============================================================
    // 2) أَقرَب إجازة قادِمة (مُعتَمَدة أَو مُعَلَّقة)
    // ============================================================
    final allMyLeaves = LeaveService.instance.requestsFor(empId);
    final myLeaves = allMyLeaves
        .where((l) => !l.endDate.isBefore(today))
        .where((l) =>
            l.status == LeaveStatus.approved ||
            l.status == LeaveStatus.pending)
        .toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    final nextLeave = myLeaves.isEmpty ? null : myLeaves.first;

    // ============================================================
    // 3) وَثائِق تَنتَهي خِلال 30 يَوم
    // ============================================================
    final expSoon = _myDocsExpiringSoon(emp, today);

    // ============================================================
    // 4) في إجازة الآن؟
    // ============================================================
    final onLeaveNow = myLeaves.any((l) =>
        l.status == LeaveStatus.approved &&
        !l.startDate.isAfter(today) &&
        !l.endDate.isBefore(today));

    // ============================================================
    // الـUI
    // ============================================================
    final theme = Theme.of(context);
    final cardColor = isDark
        ? theme.cardColor
        : Colors.white;
    final mutedColor = theme.textTheme.bodySmall?.color ??
        (isDark ? Colors.white70 : Colors.grey[700]!);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.brand.withOpacity(0.20)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.18 : 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ===== Header =====
            Row(
              children: [
                Icon(
                  Icons.wb_sunny_outlined,
                  size: 18,
                  color: AppColors.gold,
                ),
                const SizedBox(width: 6),
                Text(
                  isAr ? 'يَومي' : 'My Day',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Spacer(),
                Text(
                  _formatDate(today, isAr),
                  style: TextStyle(
                    fontSize: 11,
                    color: mutedColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // ===== Tiles row =====
            Row(
              children: [
                Expanded(
                  child: _DayTile(
                    icon: onLeaveNow
                        ? Icons.beach_access
                        : (todayShift != null
                            ? Icons.work_outline
                            : Icons.bedtime_outlined),
                    color: onLeaveNow
                        ? AppColors.info
                        : (todayShift != null
                            ? AppColors.success
                            : AppColors.gold),
                    title: isAr ? 'وَردِيّتي' : 'My Shift',
                    value: onLeaveNow
                        ? (isAr ? 'في إجازة' : 'On Leave')
                        : todayShift == null
                            ? (isAr ? 'راحة' : 'Off')
                            : '${todayShift.startTime} – ${todayShift.endTime}',
                    subtitle: todayShift == null
                        ? null
                        : _shiftTypeLabel(todayShift.shiftType, isAr),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const EmployeeMyRoster()),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _DayTile(
                    icon: Icons.beach_access_outlined,
                    color: nextLeave == null
                        ? mutedColor
                        : AppColors.info,
                    title: isAr ? 'إجازَتي القادِمة' : 'Next Leave',
                    value: nextLeave == null
                        ? (isAr ? 'لا تُوجَد' : 'None')
                        : _formatDate(nextLeave.startDate, isAr),
                    subtitle: nextLeave == null
                        ? null
                        : _leaveStatusLabel(nextLeave.status, isAr),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const MyLeavesScreen()),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _DayTile(
                    icon: expSoon == 0
                        ? Icons.check_circle_outline
                        : Icons.warning_amber_outlined,
                    color: expSoon == 0
                        ? AppColors.success
                        : AppColors.warning,
                    title: isAr ? 'وَثائِقي' : 'My Docs',
                    value: expSoon == 0
                        ? (isAr ? 'سَليمة' : 'OK')
                        : '$expSoon',
                    subtitle: expSoon == 0
                        ? null
                        : (isAr ? 'قَريب الانتِهاء' : 'Expiring soon'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const EmployeeSchedule()),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // مُساعِدات
  // ============================================================

  /// نَحسُب كَم وَثيقة مِن وَثائِق المُوَظَّف تَنتَهي خِلال 30 يَوم.
  /// (نَستَخدِم حُقول Employee المُباشِرة لِتَجَنُّب async — لِلتَفاصيل
  ///  الكامِلة هُناك EmployeeDocumentsService مُنفَصِل)
  int _myDocsExpiringSoon(Employee emp, DateTime today) {
    var count = 0;
    final cutoff = today.add(const Duration(days: 30));

    void check(DateTime? d) {
      if (d == null) return;
      if (d.isBefore(today)) {
        count++; // مُنتَهية فِعلاً = "قَريبة" مِن أَجل التَنبيه
      } else if (d.isBefore(cutoff)) {
        count++;
      }
    }

    check(emp.passportExpiry);
    check(emp.licenseExpiry);
    return count;
  }

  String _formatDate(DateTime d, bool isAr) {
    if (isAr) {
      const months = [
        'يَناير',
        'فِبراير',
        'مارِس',
        'أَبريل',
        'مايو',
        'يونيو',
        'يوليو',
        'أَغسطُس',
        'سِبتَمبَر',
        'أُكتوبَر',
        'نوفَمبَر',
        'ديسَمبَر'
      ];
      return '${d.day} ${months[d.month - 1]}';
    }
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[d.month - 1]} ${d.day}';
  }

  String _shiftTypeLabel(ShiftType type, bool isAr) {
    switch (type) {
      case ShiftType.morning:
        return isAr ? 'صَباحيّ' : 'Morning';
      case ShiftType.evening:
        return isAr ? 'مَسائيّ' : 'Evening';
      case ShiftType.night:
        return isAr ? 'لَيليّ' : 'Night';
      case ShiftType.off:
        return isAr ? 'راحة' : 'Off';
      case ShiftType.custom:
        return isAr ? 'مُخَصَّص' : 'Custom';
    }
  }

  String _leaveStatusLabel(LeaveStatus st, bool isAr) {
    switch (st) {
      case LeaveStatus.approved:
        return isAr ? 'مُعتَمَدة' : 'Approved';
      case LeaveStatus.pending:
        return isAr ? 'مُعَلَّقة' : 'Pending';
      case LeaveStatus.rejected:
        return isAr ? 'مَرفوضة' : 'Rejected';
      case LeaveStatus.cancelled:
        return isAr ? 'مُلغاة' : 'Cancelled';
    }
  }
}

class _DayTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String value;
  final String? subtitle;
  final VoidCallback? onTap;

  const _DayTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(isDark ? 0.14 : 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.30)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 14, color: color),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: color,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.textTheme.bodySmall?.color,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
