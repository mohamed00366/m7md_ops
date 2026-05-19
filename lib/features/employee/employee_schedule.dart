import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/widgets.dart';

/// 📅 جدول الموظف — عَرض أسبوعي مع مَنتقى أسابيع
///
/// 1. رأس مَعلومات الموظّف
/// 2. مَنتقى الأسبوع (أسهم + اليوم)
/// 3. KPIs: عدد الورديات / الساعات / الرحلات في الأسبوع المختار
/// 4. رحلات الباص (للأسبوع المختار)
/// 5. الورديات (للأسبوع المختار)
/// 6. "كلّ أسابيعي" — كلّ الأسابيع الّتي لي فيها ورديات معتمدة
class EmployeeSchedule extends StatefulWidget {
  const EmployeeSchedule({super.key});

  @override
  State<EmployeeSchedule> createState() => _EmployeeScheduleState();
}

class _EmployeeScheduleState extends State<EmployeeSchedule> {
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

  bool _isSameWeek(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _fmt(DateTime d) =>
      '${d.day}/${d.month.toString().padLeft(2, '0')}';

  String _fmtFull(DateTime d) =>
      '${d.day}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// كلّ الأسابيع (weekStart فريدة) الّتي لها roster معتمد
  /// يَحوي ورديات لهذا الموظّف. مرتّبة من الأقدم للأحدث.
  List<DateTime> _weeksWithMyShifts(MockRepository repo, String empId) {
    final set = <String, DateTime>{};
    for (final r in repo.rosters) {
      if (r.status != RosterStatus.approved) continue;
      final hasMine = r.assignments.any((a) => a.employeeId == empId);
      if (!hasMine) continue;
      final ws = DateTime(r.weekStart.year, r.weekStart.month, r.weekStart.day);
      final key = ws.toIso8601String();
      set[key] = ws;
    }
    final list = set.values.toList()..sort((a, b) => a.compareTo(b));
    return list;
  }

  List<_DayShift> _myShiftsForWeek(
      MockRepository repo, String empId, DateTime weekStart) {
    final list = <_DayShift>[];
    for (final r in repo.rosters) {
      if (r.status != RosterStatus.approved) continue;
      if (!_isSameWeek(r.weekStart, weekStart)) continue;
      for (final a in r.assignments) {
        if (a.employeeId == empId) list.add(_DayShift(a, r.siteId));
      }
    }
    list.sort((a, b) =>
        a.assignment.dayIndex.compareTo(b.assignment.dayIndex));
    return list;
  }

  /// إجماليّ ساعات الورديات (من startTime/endTime، يَحتسب مرور منتصف اللّيل)
  double _hours(List<_DayShift> shifts) {
    double total = 0;
    for (final ds in shifts) {
      final a = ds.assignment;
      if (a.shiftType == ShiftType.off) continue;
      final start = _parseHHmm(a.startTime);
      final end = _parseHHmm(a.endTime);
      if (start == null || end == null) continue;
      var diff = end - start;
      if (diff <= 0) diff += 24 * 60; // مرور منتصف اللّيل
      total += diff / 60.0;
    }
    return total;
  }

  int? _parseHHmm(String? s) {
    if (s == null || s.isEmpty) return null;
    final parts = s.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final repo = MockRepository();
    final auth = context.read<AuthProvider>();
    final empId = auth.currentUser?.employeeId;
    if (empId == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            isAr
                ? 'هذه الشاشة مخصصة للموظفين (المستخدم ليس مرتبطاً بسجل موظف)'
                : 'This screen is for employees only (user not linked)',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final emp = repo.employeeById(empId);
    final today = DateTime.now();
    final todayWeek = repo.currentWeekStart();

    final dayNames = isAr
        ? ['الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد']
        : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final dayNamesShort = isAr
        ? ['إثن', 'ثلا', 'أرب', 'خمي', 'جمع', 'سبت', 'أحد']
        : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    // ===== بيانات الأسبوع المختار =====
    final myAssignments = _myShiftsForWeek(repo, empId, _weekStart);
    final plan = repo.getOrCreateBusPlan(_weekStart);
    final myTrips = plan.details
        .where((d) => d.employeeIds.contains(empId))
        .toList()
      ..sort((a, b) {
        final byDay = a.dayIndex.compareTo(b.dayIndex);
        if (byDay != 0) return byDay;
        return a.time.compareTo(b.time);
      });

    final activeShifts = myAssignments
        .where((d) => d.assignment.shiftType != ShiftType.off)
        .length;
    final totalHours = _hours(myAssignments);

    // ===== كلّ أسابيعي =====
    final myWeeks = _weeksWithMyShifts(repo, empId);

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
      children: [
        // ===== رأس الموظّف =====
        if (emp != null)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.roleEmployee,
                  AppColors.roleEmployee.withOpacity(0.7),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: Colors.white,
                  child: Text(
                    emp.initials,
                    style: const TextStyle(
                        color: AppColors.roleEmployee,
                        fontWeight: FontWeight.w800,
                        fontSize: 20),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(emp.fullName,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800)),
                      Text('${emp.code} • ${emp.jobTitle}',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 14),

        // ===== مَنتقى الأسبوع =====
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            children: [
              IconButton(
                tooltip: isAr ? 'الأسبوع السابق' : 'Previous week',
                icon: const Icon(Icons.chevron_right),
                onPressed: () => setState(() => _weekStart =
                    _weekStart.subtract(const Duration(days: 7))),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      isAr ? 'الأسبوع' : 'Week',
                      style: const TextStyle(
                          fontSize: 11, color: Colors.grey),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_fmt(_weekStart)} — ${_fmt(_weekStart.add(const Duration(days: 6)))}',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w900),
                    ),
                    if (_isSameWeek(_weekStart, todayWeek))
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.success.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isAr ? 'الأسبوع الحالي' : 'Current week',
                          style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.success,
                              fontWeight: FontWeight.w800),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: isAr ? 'الأسبوع التالي' : 'Next week',
                icon: const Icon(Icons.chevron_left),
                onPressed: () => setState(() => _weekStart =
                    _weekStart.add(const Duration(days: 7))),
              ),
              if (!_isSameWeek(_weekStart, todayWeek))
                TextButton.icon(
                  onPressed: () =>
                      setState(() => _weekStart = todayWeek),
                  icon: const Icon(Icons.today, size: 14),
                  label: Text(isAr ? 'اليوم' : 'Today',
                      style: const TextStyle(fontSize: 11)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ===== KPIs =====
        Row(
          children: [
            Expanded(
              child: _Kpi(
                color: AppColors.brand,
                icon: Icons.event_note_outlined,
                label: isAr ? 'ورديات' : 'Shifts',
                value: '$activeShifts',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Kpi(
                color: AppColors.success,
                icon: Icons.schedule,
                label: isAr ? 'ساعات' : 'Hours',
                value: totalHours.toStringAsFixed(1),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Kpi(
                color: AppColors.info,
                icon: Icons.directions_bus_outlined,
                label: isAr ? 'رحلات' : 'Trips',
                value: '${myTrips.length}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // ===== رحلات الباص =====
        if (myTrips.isNotEmpty) ...[
          SectionCard(
            title: isAr ? 'رحلات الباص' : 'Bus Trips',
            child: Column(
              children: myTrips.map((t) {
                final bus = repo.busById(t.busId);
                final point = repo.pointById(t.siteId);
                final dayName = dayNames[t.dayIndex];
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.brand.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.directions_bus,
                          color: AppColors.brand, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('$dayName • ${t.time}',
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700)),
                            Text(
                              '${bus?.name ?? "—"} → ${point?.name ?? "—"}',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // ===== ورديات الأسبوع =====
        SectionCard(
          title: s.weeklyRoster,
          child: myAssignments.isEmpty
              ? EmptyState(
                  icon: Icons.calendar_today_outlined,
                  message: isAr
                      ? 'لم تُعتمد ورديات لك هذا الأسبوع'
                      : 'No approved shifts this week',
                )
              : Column(
                  children: myAssignments.map((ds) {
                    final point = repo.pointById(ds.siteId);
                    final dayDate =
                        _weekStart.add(Duration(days: ds.assignment.dayIndex));
                    final isToday = dayDate.year == today.year &&
                        dayDate.month == today.month &&
                        dayDate.day == today.day;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isToday
                            ? AppColors.success.withOpacity(0.08)
                            : AppColors.bgLight,
                        borderRadius: BorderRadius.circular(8),
                        border: isToday
                            ? Border.all(
                                color:
                                    AppColors.success.withOpacity(0.40))
                            : null,
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isToday
                                  ? AppColors.success
                                  : AppColors.brand,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              dayNamesShort[ds.assignment.dayIndex],
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${ds.assignment.startTime} - ${ds.assignment.endTime}',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  '${point?.name ?? "—"} • ${isAr ? ds.assignment.shiftType.arabicLabel() : ds.assignment.shiftType.englishLabel()}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          Text(_fmt(dayDate),
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
        const SizedBox(height: 14),

        // ===== كلّ أسابيعي =====
        if (myWeeks.isNotEmpty)
          SectionCard(
            title: isAr ? 'كلّ أسابيعي' : 'All my weeks',
            child: Column(
              children: myWeeks.reversed.map((w) {
                final wShifts = _myShiftsForWeek(repo, empId, w);
                final wActive = wShifts
                    .where((d) => d.assignment.shiftType != ShiftType.off)
                    .length;
                final wHours = _hours(wShifts);
                final isCurrent = _isSameWeek(w, todayWeek);
                final isPast = w.isBefore(todayWeek);
                final isSelected = _isSameWeek(w, _weekStart);
                return InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(() => _weekStart = w),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.brand.withOpacity(0.10)
                          : AppColors.bgLight,
                      borderRadius: BorderRadius.circular(8),
                      border: isSelected
                          ? Border.all(
                              color: AppColors.brand.withOpacity(0.50))
                          : null,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isCurrent
                                ? AppColors.success
                                : (isPast
                                    ? Colors.grey.shade400
                                    : AppColors.info),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(Icons.calendar_view_week,
                              color: Colors.white, size: 18),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    '${_fmtFull(w)} — ${_fmtFull(w.add(const Duration(days: 6)))}',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(width: 6),
                                  if (isCurrent)
                                    _MiniBadge(
                                        text: isAr ? 'الحالي' : 'Now',
                                        color: AppColors.success)
                                  else if (isPast)
                                    _MiniBadge(
                                        text: isAr ? 'سابق' : 'Past',
                                        color: Colors.grey)
                                  else
                                    _MiniBadge(
                                        text: isAr ? 'قادم' : 'Upcoming',
                                        color: AppColors.info),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$wActive ${isAr ? "وردية" : "shifts"} · '
                                '${wHours.toStringAsFixed(1)} ${isAr ? "ساعة" : "h"}',
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_left,
                            size: 18, color: Colors.grey),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          )
        else
          SectionCard(
            title: isAr ? 'كلّ أسابيعي' : 'All my weeks',
            child: EmptyState(
              icon: Icons.event_busy,
              message: isAr
                  ? 'لا توجد ورديات معتمدة لك بعد'
                  : 'No approved shifts yet',
            ),
          ),
      ],
    );
  }
}

class _DayShift {
  final RosterAssignment assignment;
  final String siteId;
  _DayShift(this.assignment, this.siteId);
}

class _Kpi extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  const _Kpi({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w900)),
          Text(label,
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  final String text;
  final Color color;
  const _MiniBadge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 9,
              color: color,
              fontWeight: FontWeight.w900)),
    );
  }
}
