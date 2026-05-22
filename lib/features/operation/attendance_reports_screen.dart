import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/point_attendance_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/m7_app_bar.dart';

/// 📊 شاشة تقارير الحضور
///
/// تُعرض فيها إحصاءات الحضور لفترة زمنيّة:
///   • Summary KPIs (حضور / غياب / متغيّر / إجمالي رحلات)
///   • نسبة الحضور لكلّ موظّف (مرتّب)
///   • تقسيم حسب اليوم
///   • فلتر بفترة زمنيّة (هذا الأسبوع / الشهر / مخصّص)
class AttendanceReportsScreen extends StatefulWidget {
  const AttendanceReportsScreen({super.key});

  @override
  State<AttendanceReportsScreen> createState() =>
      _AttendanceReportsScreenState();
}

enum _DateRange { week, month, custom }

class _AttendanceReportsScreenState
    extends State<AttendanceReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  _DateRange _range = _DateRange.week;
  DateTime _from = DateTime.now().subtract(const Duration(days: 6));
  DateTime _to = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _applyRange(_range);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  void _applyRange(_DateRange r) {
    final now = DateTime.now();
    setState(() {
      _range = r;
      switch (r) {
        case _DateRange.week:
          _from = now.subtract(const Duration(days: 6));
          _to = now;
          break;
        case _DateRange.month:
          _from = DateTime(now.year, now.month, 1);
          _to = now;
          break;
        case _DateRange.custom:
          // يبقى ما اختاره المستخدم
          break;
      }
    });
  }

  Future<void> _pickCustom() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (picked != null && mounted) {
      setState(() {
        _range = _DateRange.custom;
        _from = picked.start;
        _to = picked.end;
      });
    }
  }

  /// كلّ سجلّات الحضور ضمن الفترة (نُحاكي بالـ markedAt)
  List<BusTripAttendance> _attendanceInRange() {
    final repo = MockRepository();
    final start =
        DateTime(_from.year, _from.month, _from.day);
    final end =
        DateTime(_to.year, _to.month, _to.day, 23, 59, 59);
    return repo.busAttendance.where((a) {
      if (a.markedAt == null) return false;
      return !a.markedAt!.isBefore(start) &&
          !a.markedAt!.isAfter(end);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? 'تقارير الحضور' : 'Attendance Reports',
        subtitle:
            '${DateFormat('d/M').format(_from)} → ${DateFormat('d/M').format(_to)}',
        bottom: TabBar(
          controller: _tab,
          labelStyle: const TextStyle(
              fontWeight: FontWeight.w900, fontSize: 13),
          tabs: [
            Tab(text: isAr ? '🚌 الباصات' : '🚌 Buses'),
            Tab(text: isAr ? '📍 النِقاط' : '📍 Points'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _buildBusReport(context, isAr),
          _PointReportTab(from: _from, to: _to),
        ],
      ),
    );
  }

  Widget _buildBusReport(BuildContext context, bool isAr) {
    final repo = MockRepository();
    final atts = _attendanceInRange();

    final present = atts
        .where((a) => a.status == BusAttendanceStatus.present)
        .length;
    final missing = atts
        .where((a) => a.status == BusAttendanceStatus.missing)
        .length;
    final changed = atts
        .where((a) => a.status == BusAttendanceStatus.changed)
        .length;
    final total = atts.length;

    // إحصاء لكلّ موظّف
    final perEmployee = <String, _EmpStats>{};
    for (final a in atts) {
      final stats =
          perEmployee.putIfAbsent(a.employeeId, () => _EmpStats());
      stats.total++;
      switch (a.status) {
        case BusAttendanceStatus.present:
          stats.present++;
          break;
        case BusAttendanceStatus.missing:
          stats.missing++;
          break;
        case BusAttendanceStatus.changed:
          stats.changed++;
          break;
      }
    }
    final sortedEmps = perEmployee.entries.toList()
      ..sort((a, b) => b.value.missing.compareTo(a.value.missing));

    // إحصاء لكلّ يوم
    final perDay = <DateTime, _EmpStats>{};
    for (final a in atts) {
      if (a.markedAt == null) continue;
      final day = DateTime(
          a.markedAt!.year, a.markedAt!.month, a.markedAt!.day);
      final stats = perDay.putIfAbsent(day, () => _EmpStats());
      stats.total++;
      switch (a.status) {
        case BusAttendanceStatus.present:
          stats.present++;
          break;
        case BusAttendanceStatus.missing:
          stats.missing++;
          break;
        case BusAttendanceStatus.changed:
          stats.changed++;
          break;
      }
    }
    final sortedDays = perDay.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));

    return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ===== فلتر الفترة =====
          Wrap(
            spacing: 8,
            children: [
              _RangeChip(
                label: isAr ? 'الأسبوع' : 'Week',
                selected: _range == _DateRange.week,
                onTap: () => _applyRange(_DateRange.week),
              ),
              _RangeChip(
                label: isAr ? 'الشهر' : 'Month',
                selected: _range == _DateRange.month,
                onTap: () => _applyRange(_DateRange.month),
              ),
              _RangeChip(
                label: isAr ? 'مخصّص' : 'Custom',
                selected: _range == _DateRange.custom,
                onTap: _pickCustom,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ===== KPI Summary =====
          _SectionTitle(
            icon: Icons.dashboard,
            title: isAr ? 'الملخّص' : 'Summary',
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                  child: _BigStat(
                      label: isAr ? 'حاضر' : 'Present',
                      count: present,
                      color: AppColors.success,
                      icon: Icons.check_circle)),
              const SizedBox(width: 8),
              Expanded(
                  child: _BigStat(
                      label: isAr ? 'غائب' : 'Absent',
                      count: missing,
                      color: AppColors.danger,
                      icon: Icons.cancel)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                  child: _BigStat(
                      label: isAr ? 'متغيّر' : 'Variable',
                      count: changed,
                      color: AppColors.warning,
                      icon: Icons.swap_horiz)),
              const SizedBox(width: 8),
              Expanded(
                  child: _BigStat(
                      label: isAr ? 'الإجمالي' : 'Total',
                      count: total,
                      color: AppColors.brand,
                      icon: Icons.groups)),
            ],
          ),

          // ===== نسبة الحضور =====
          if (total > 0) ...[
            const SizedBox(height: 16),
            _AttendanceRateBar(
              present: present,
              total: total,
              isAr: isAr,
            ),
          ],

          // ===== تقسيم حسب اليوم =====
          const SizedBox(height: 24),
          _SectionTitle(
            icon: Icons.calendar_month,
            title: isAr ? 'حسب اليوم' : 'By Day',
          ),
          const SizedBox(height: 8),
          if (sortedDays.isEmpty)
            _Empty(isAr: isAr)
          else
            ...sortedDays.map((e) => _DayRow(
                  date: e.key,
                  stats: e.value,
                  isAr: isAr,
                )),

          // ===== لكلّ موظّف =====
          const SizedBox(height: 24),
          _SectionTitle(
            icon: Icons.people,
            title: isAr
                ? 'حسب الموظّف (مرتّب بالغياب)'
                : 'By Employee (sorted by absences)',
          ),
          const SizedBox(height: 8),
          if (sortedEmps.isEmpty)
            _Empty(isAr: isAr)
          else
            ...sortedEmps.take(50).map((entry) {
              Employee? emp;
              try {
                emp = repo.employees
                    .firstWhere((x) => x.id == entry.key);
              } catch (_) {}
              if (emp == null) return const SizedBox.shrink();
              return _EmpRow(
                emp: emp,
                stats: entry.value,
                isAr: isAr,
              );
            }),

          const SizedBox(height: 24),
        ],
      );
  }
}

// =============================================================================
// 📍 _PointReportTab — تَقرير حُضور النِقاط
// =============================================================================
class _PointReportTab extends StatefulWidget {
  final DateTime from;
  final DateTime to;
  const _PointReportTab({required this.from, required this.to});

  @override
  State<_PointReportTab> createState() => _PointReportTabState();
}

class _PointReportTabState extends State<_PointReportTab> {
  bool _loading = true;
  Map<String, int> _daysPresent = {};   // employee_id → count of days present
  Map<String, int> _daysCompleted = {}; // employee_id → days with clock_out
  int _totalDays = 0;
  int _totalRecords = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _PointReportTab old) {
    super.didUpdateWidget(old);
    if (old.from != widget.from || old.to != widget.to) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _daysPresent.clear();
    _daysCompleted.clear();
    _totalDays = 0;
    _totalRecords = 0;

    var d = DateTime(widget.from.year, widget.from.month, widget.from.day);
    final end = DateTime(widget.to.year, widget.to.month, widget.to.day);
    while (!d.isAfter(end)) {
      _totalDays++;
      final rows = await PointAttendanceService.instance.forDate(d);
      for (final r in rows) {
        _totalRecords++;
        if (r.isPresent) {
          _daysPresent[r.employeeId] = (_daysPresent[r.employeeId] ?? 0) + 1;
        }
        if (r.isCompleted) {
          _daysCompleted[r.employeeId] =
              (_daysCompleted[r.employeeId] ?? 0) + 1;
        }
      }
      d = d.add(const Duration(days: 1));
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final repo = MockRepository();
    final empMap = {for (final e in repo.employees) e.id: e};
    final sorted = _daysPresent.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // KPIs
          Row(
            children: [
              Expanded(
                child: _BigStat(
                  label: isAr ? 'أَيّام النِطاق' : 'Days in range',
                  count: _totalDays,
                  color: AppColors.brand,
                  icon: Icons.calendar_today,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _BigStat(
                  label: isAr ? 'مُوَظَّفون حَضَروا' : 'Employees attended',
                  count: _daysPresent.length,
                  color: AppColors.success,
                  icon: Icons.people,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _BigStat(
                  label: isAr ? 'إجماليّ سِجِلّات' : 'Total records',
                  count: _totalRecords,
                  color: AppColors.warning,
                  icon: Icons.history,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            isAr ? 'حُضور النِقاط (مُرَتَّب)' : 'Point attendance (sorted)',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
          ),
          const SizedBox(height: 8),
          if (sorted.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('لا يُوجَد سِجِلّات')),
            )
          else
            ...sorted.map((e) {
              final emp = empMap[e.key];
              if (emp == null) return const SizedBox.shrink();
              final present = e.value;
              final completed = _daysCompleted[e.key] ?? 0;
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.brand.withOpacity(0.1),
                    child: Text(emp.initials,
                        style: const TextStyle(
                            color: AppColors.brand,
                            fontWeight: FontWeight.w900)),
                  ),
                  title: Text(emp.fullName,
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: Text(emp.code,
                      style: const TextStyle(fontSize: 11)),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('$present/$_totalDays',
                          style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: AppColors.success)),
                      Text(
                        isAr ? '$completed مُكتَمِل' : '$completed completed',
                        style: const TextStyle(
                            fontSize: 10, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _EmpStats {
  int total = 0;
  int present = 0;
  int missing = 0;
  int changed = 0;
  double get presenceRate => total == 0 ? 0 : present / total;
  double get absenceRate => total == 0 ? 0 : missing / total;
}

// ============================================================
// Widgets
// ============================================================
class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionTitle({required this.icon, required this.title});
  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 18, color: AppColors.brand),
          const SizedBox(width: 6),
          Text(title,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800)),
        ],
      );
}

class _RangeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _RangeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.brand
              : AppColors.brand.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected
                  ? AppColors.brand
                  : AppColors.brand.withOpacity(0.3),
              width: 0.5),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? Colors.white : AppColors.brand,
                fontSize: 12,
                fontWeight: FontWeight.w800)),
      ),
    );
  }
}

class _BigStat extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;
  const _BigStat({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: color.withOpacity(0.25), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        color: color.withOpacity(0.85),
                        fontSize: 11,
                        fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(count.toString(),
              style: TextStyle(
                  color: color,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  height: 1.0)),
        ],
      ),
    );
  }
}

class _AttendanceRateBar extends StatelessWidget {
  final int present;
  final int total;
  final bool isAr;
  const _AttendanceRateBar({
    required this.present,
    required this.total,
    required this.isAr,
  });
  @override
  Widget build(BuildContext context) {
    final rate = total == 0 ? 0.0 : present / total;
    final pct = (rate * 100).toStringAsFixed(1);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: Theme.of(context).dividerColor, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(isAr ? 'نسبة الحضور' : 'Attendance Rate',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800)),
              const Spacer(),
              Text('$pct%',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppColors.success)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: rate,
              minHeight: 10,
              backgroundColor:
                  AppColors.danger.withOpacity(0.15),
              valueColor: const AlwaysStoppedAnimation(
                  AppColors.success),
            ),
          ),
        ],
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  final DateTime date;
  final _EmpStats stats;
  final bool isAr;
  const _DayRow({
    required this.date,
    required this.stats,
    required this.isAr,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: Theme.of(context).dividerColor, width: 0.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_today,
              size: 14, color: AppColors.brand),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              DateFormat('EEEE  d/M', isAr ? 'ar' : 'en')
                  .format(date),
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          _MiniBadge(count: stats.present, color: AppColors.success),
          const SizedBox(width: 4),
          _MiniBadge(count: stats.missing, color: AppColors.danger),
          const SizedBox(width: 4),
          _MiniBadge(count: stats.changed, color: AppColors.warning),
        ],
      ),
    );
  }
}

class _EmpRow extends StatelessWidget {
  final Employee emp;
  final _EmpStats stats;
  final bool isAr;
  const _EmpRow({
    required this.emp,
    required this.stats,
    required this.isAr,
  });
  @override
  Widget build(BuildContext context) {
    final pct = (stats.presenceRate * 100).toStringAsFixed(0);
    final color = stats.presenceRate > 0.85
        ? AppColors.success
        : stats.presenceRate > 0.6
            ? AppColors.warning
            : AppColors.danger;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: Theme.of(context).dividerColor, width: 0.5),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: color.withOpacity(0.12),
                child: Text(
                  emp.fullName.isEmpty ? '?' : emp.fullName[0],
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w800,
                      fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(emp.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800)),
                    Text(emp.code,
                        style: const TextStyle(
                            fontSize: 10,
                            color:
                                AppColors.textSecondaryLight)),
                  ],
                ),
              ),
              Text('$pct%',
                  style: TextStyle(
                      color: color,
                      fontSize: 14,
                      fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _MiniBadge(
                  count: stats.present, color: AppColors.success),
              const SizedBox(width: 4),
              _MiniBadge(
                  count: stats.missing, color: AppColors.danger),
              const SizedBox(width: 4),
              _MiniBadge(
                  count: stats.changed, color: AppColors.warning),
              const Spacer(),
              Text(
                  isAr
                      ? 'إجمالي ${stats.total}'
                      : 'Total ${stats.total}',
                  style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondaryLight)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: stats.presenceRate,
              minHeight: 4,
              backgroundColor: color.withOpacity(0.15),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  final int count;
  final Color color;
  const _MiniBadge({required this.count, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('$count',
          style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800)),
    );
  }
}

class _Empty extends StatelessWidget {
  final bool isAr;
  const _Empty({required this.isAr});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: Text(
          isAr
              ? 'لا توجد بيانات في هذه الفترة'
              : 'No data in this period',
          style: TextStyle(
              color: Theme.of(context).disabledColor),
        ),
      ),
    );
  }
}
