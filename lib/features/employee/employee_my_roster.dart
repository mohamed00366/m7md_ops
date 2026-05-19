import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/widgets.dart';

/// 📅 روستري - شاشة الموظف الشخصية لعرض ورديات الأسبوع المعتمدة
/// تتضمن: تنقل بين الأسابيع، تمييز اليوم الحالي، نقطة الوردية،
/// إجمالي الساعات، تنبيه عند عدم اعتماد الروستر بعد.
class EmployeeMyRoster extends StatefulWidget {
  const EmployeeMyRoster({super.key});

  @override
  State<EmployeeMyRoster> createState() => _EmployeeMyRosterState();
}

class _EmployeeMyRosterState extends State<EmployeeMyRoster> {
  late DateTime _weekStart;

  @override
  void initState() {
    super.initState();
    _weekStart = MockRepository().currentWeekStart();
    MockRepository().addListener(_onChange);
  }

  @override
  void dispose() {
    MockRepository().removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  void _changeWeek(int weeks) =>
      setState(() => _weekStart = _weekStart.add(Duration(days: weeks * 7)));

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final auth = context.watch<AuthProvider>();
    final empId = auth.currentUser?.employeeId;

    if (empId == null) {
      return EmptyState(
        icon: Icons.person_off,
        message: s.isAr
            ? 'حسابك ليس مرتبطاً بسجل موظف'
            : 'Your account is not linked to an employee record',
      );
    }

    final emp = repo.employeeById(empId);
    if (emp == null) {
      return EmptyState(
        icon: Icons.error_outline,
        message: s.isAr ? 'لم يتم العثور على بيانات الموظف' : 'Employee not found',
      );
    }

    // اجمع ورديات الموظف لهذا الأسبوع من جميع الروسترات
    final wsKey = _weekStart.toIso8601String().substring(0, 10);
    final myShifts = <_MyShift>[];
    final weekRosters = <WeeklyRoster>[];
    for (final r in repo.rosters) {
      if (r.weekStart.toIso8601String().substring(0, 10) != wsKey) continue;
      var hasMine = false;
      for (final a in r.assignments) {
        if (a.employeeId == empId) {
          myShifts.add(_MyShift(assignment: a, roster: r));
          hasMine = true;
        }
      }
      if (hasMine) weekRosters.add(r);
    }

    // كلّ الروسترات معتمدة؟
    final approvedRosters =
        weekRosters.where((r) => r.status == RosterStatus.approved).toList();
    final pendingRosters = weekRosters
        .where((r) =>
            r.status == RosterStatus.submitted ||
            r.status == RosterStatus.underReview ||
            r.status == RosterStatus.draft)
        .toList();
    final rejectedRosters =
        weekRosters.where((r) => r.status == RosterStatus.rejected).toList();

    return Scaffold(
      body: Column(
        children: [
          _Header(
            employee: emp,
            weekStart: _weekStart,
            onPrev: () => _changeWeek(-1),
            onNext: () => _changeWeek(1),
            onToday: () =>
                setState(() => _weekStart = repo.currentWeekStart()),
          ),
          // Banner: حالة الاعتماد
          _StatusBanner(
            approved: approvedRosters.length,
            pending: pendingRosters.length,
            rejected: rejectedRosters.length,
            totalShifts: myShifts.length,
          ),
          Expanded(
            child: _WeekGrid(
              weekStart: _weekStart,
              shifts: myShifts,
            ),
          ),
        ],
      ),
    );
  }
}

class _MyShift {
  final RosterAssignment assignment;
  final WeeklyRoster roster;
  _MyShift({required this.assignment, required this.roster});
}

// ============================================================
// Header - معلومات الموظف + التنقل بين الأسابيع
// ============================================================
class _Header extends StatelessWidget {
  final Employee employee;
  final DateTime weekStart;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;

  const _Header({
    required this.employee,
    required this.weekStart,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isThisWeek = _isSameWeek(weekStart, DateTime.now());
    return Container(
      color: Theme.of(context).cardTheme.color,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // اسم الموظف + الكود
          Row(
            children: [
              AppAvatar(initials: employee.initials, color: AppColors.brand),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(employee.fullName,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800)),
                    Text(
                      '${employee.code} • ${employee.jobTitle}',
                      style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).disabledColor),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // تنقل الأسبوع
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: onPrev,
                tooltip: s.isAr ? 'الأسبوع السابق' : 'Previous',
              ),
              Expanded(
                child: Center(
                  child: Column(
                    children: [
                      Text(
                        '${_fmt(weekStart)} → ${_fmt(weekStart.add(const Duration(days: 6)))}',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w800),
                      ),
                      if (isThisWeek)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.success.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            s.isAr ? 'الأسبوع الحالي' : 'This Week',
                            style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.success,
                                fontWeight: FontWeight.w700),
                          ),
                        )
                      else
                        InkWell(
                          onTap: onToday,
                          child: Text(
                            s.isAr ? 'اذهب لهذا الأسبوع' : 'Jump to this week',
                            style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.brand,
                                fontWeight: FontWeight.w700,
                                decoration: TextDecoration.underline),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: onNext,
                tooltip: s.isAr ? 'الأسبوع التالي' : 'Next',
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.day}/${d.month.toString().padLeft(2, '0')}';

  bool _isSameWeek(DateTime a, DateTime b) {
    // b kept for API symmetry; comparison is against repo's currentWeekStart()
    // since both `a` and `currentWeekStart` are Monday-anchored.
    final start = MockRepository().currentWeekStart();
    return a.year == start.year &&
        a.month == start.month &&
        a.day == start.day;
  }
}

// ============================================================
// Status Banner - يوضّح هل الروستر معتمد أم في الانتظار
// ============================================================
class _StatusBanner extends StatelessWidget {
  final int approved;
  final int pending;
  final int rejected;
  final int totalShifts;
  const _StatusBanner({
    required this.approved,
    required this.pending,
    required this.rejected,
    required this.totalShifts,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    if (totalShifts == 0) {
      return Container(
        margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.textTertiaryLight.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.event_busy,
                color: AppColors.textTertiaryLight, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                s.isAr
                    ? 'لا يوجد ورديات لك في هذا الأسبوع'
                    : 'No shifts assigned this week',
                style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiaryLight,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
    }
    final List<_BannerLine> lines = [];
    if (approved > 0) {
      lines.add(_BannerLine(
        icon: Icons.check_circle,
        color: AppColors.success,
        text: s.isAr
            ? 'معتمدة ($approved روستر)'
            : 'Approved ($approved roster)',
      ));
    }
    if (pending > 0) {
      lines.add(_BannerLine(
        icon: Icons.hourglass_top,
        color: AppColors.warning,
        text: s.isAr
            ? 'بانتظار الاعتماد ($pending روستر) — قد تتغيّر الورديات'
            : 'Pending approval ($pending roster) — shifts may change',
      ));
    }
    if (rejected > 0) {
      lines.add(_BannerLine(
        icon: Icons.cancel,
        color: AppColors.danger,
        text: s.isAr
            ? 'مرفوضة ($rejected روستر) — راجع المشرف'
            : 'Rejected ($rejected roster) — see your supervisor',
      ));
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: lines
            .map((l) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Icon(l.icon, size: 14, color: l.color),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(l.text,
                            style: TextStyle(
                                fontSize: 11,
                                color: l.color,
                                fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class _BannerLine {
  final IconData icon;
  final Color color;
  final String text;
  _BannerLine({required this.icon, required this.color, required this.text});
}

// ============================================================
// Week Grid - 7 بطاقات لأيام الأسبوع
// ============================================================
class _WeekGrid extends StatelessWidget {
  final DateTime weekStart;
  final List<_MyShift> shifts;
  const _WeekGrid({required this.weekStart, required this.shifts});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final dayNames = s.isAr
        ? ['الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد']
        : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final today = DateTime.now();

    // إجمالي ساعات الأسبوع
    double totalHours = 0;
    for (final sh in shifts) {
      totalHours += sh.assignment.hours;
    }
    final activeDays =
        shifts.where((sh) => sh.assignment.shiftType != ShiftType.off).length;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // ===== ملخّص الأسبوع =====
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.warning.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.warning.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.access_time, color: AppColors.warning, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${totalHours.toStringAsFixed(0)}h',
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: AppColors.warning),
                    ),
                    Text(
                      s.isAr
                          ? 'إجمالي ساعات الأسبوع — $activeDays يوم عمل'
                          : 'Total weekly hours — $activeDays working day(s)',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.warning.withOpacity(0.85),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // ===== بطاقات الأيام =====
        ...List.generate(7, (dayIndex) {
          final dayDate = weekStart.add(Duration(days: dayIndex));
          final isToday = dayDate.year == today.year &&
              dayDate.month == today.month &&
              dayDate.day == today.day;
          final dayShifts =
              shifts.where((sh) => sh.assignment.dayIndex == dayIndex).toList();
          return _DayCard(
            dayName: dayNames[dayIndex],
            dayDate: dayDate,
            isToday: isToday,
            shifts: dayShifts,
            repo: repo,
          );
        }),
      ],
    );
  }
}

class _DayCard extends StatelessWidget {
  final String dayName;
  final DateTime dayDate;
  final bool isToday;
  final List<_MyShift> shifts;
  final MockRepository repo;

  const _DayCard({
    required this.dayName,
    required this.dayDate,
    required this.isToday,
    required this.shifts,
    required this.repo,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isOff = shifts.isEmpty ||
        shifts.every((sh) => sh.assignment.shiftType == ShiftType.off);
    final dayHours = shifts.fold<double>(
        0.0, (acc, sh) => acc + sh.assignment.hours);

    final accentColor = isToday
        ? AppColors.brand
        : (isOff ? AppColors.textTertiaryLight : AppColors.success);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isToday
              ? AppColors.brand
              : Theme.of(context).dividerColor,
          width: isToday ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ===== رأس البطاقة =====
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(isToday ? 0.15 : 0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    dayDate.day.toString(),
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 16),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            dayName,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: accentColor),
                          ),
                          if (isToday) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.brand,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                s.isAr ? 'اليوم' : 'Today',
                                style: const TextStyle(
                                    fontSize: 9,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        '${dayDate.day}/${dayDate.month.toString().padLeft(2, '0')}/${dayDate.year}',
                        style: TextStyle(
                            fontSize: 10,
                            color: Theme.of(context).disabledColor),
                      ),
                    ],
                  ),
                ),
                if (!isOff)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.warning,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${dayHours.toStringAsFixed(0)}h',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          // ===== جسم البطاقة: الورديات أو "إجازة" =====
          if (isOff)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.beach_access,
                        color: AppColors.textTertiaryLight, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      s.isAr ? 'إجازة' : 'Day off',
                      style: const TextStyle(
                          color: AppColors.textTertiaryLight,
                          fontSize: 13,
                          fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            )
          else
            ...shifts.where((sh) => sh.assignment.shiftType != ShiftType.off).map((sh) {
              final point = repo.pointById(sh.roster.siteId);
              final isApproved = sh.roster.status == RosterStatus.approved;
              final isNight = sh.assignment.shiftType == ShiftType.night;
              return Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isNight ? Icons.nightlight : Icons.wb_sunny,
                          size: 16,
                          color: isNight ? AppColors.info : AppColors.success,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${sh.assignment.startTime} - ${sh.assignment.endTime}',
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'monospace'),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: (isNight
                                    ? AppColors.info
                                    : AppColors.success)
                                .withOpacity(0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${sh.assignment.hours.toStringAsFixed(0)}h',
                            style: TextStyle(
                              fontSize: 10,
                              color: isNight
                                  ? AppColors.info
                                  : AppColors.success,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (!isApproved)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.warning.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              s.isAr
                                  ? sh.roster.status.arabicLabel()
                                  : sh.roster.status.englishLabel(),
                              style: const TextStyle(
                                  fontSize: 9,
                                  color: AppColors.warning,
                                  fontWeight: FontWeight.w800),
                            ),
                          ),
                      ],
                    ),
                    if (point != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.place,
                              size: 12, color: AppColors.warning),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              point.name,
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (point.code.isNotEmpty)
                            Text(
                              point.code,
                              style: const TextStyle(
                                fontSize: 10,
                                fontFamily: 'monospace',
                                color: AppColors.warning,
                              ),
                            ),
                        ],
                      ),
                    ],
                    if (sh.assignment.notes != null &&
                        sh.assignment.notes!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.info.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.note_outlined,
                                size: 12, color: AppColors.info),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                sh.assignment.notes!,
                                style: const TextStyle(
                                    fontSize: 11, color: AppColors.info),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
