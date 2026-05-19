import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/widgets.dart';

/// شاشة الجدولة الأسبوعية الموحّدة + تقارير
/// تابات:
/// 1) الجدول: موظفون × أيام (تجميع كل النقاط المعتمدة)
/// 2) التقارير: ساعات + عدد الموظفين في كل ساعة + فلاتر
class WeeklyEmployeeSchedule extends StatefulWidget {
  const WeeklyEmployeeSchedule({super.key});

  @override
  State<WeeklyEmployeeSchedule> createState() =>
      _WeeklyEmployeeScheduleState();
}

class _WeeklyEmployeeScheduleState extends State<WeeklyEmployeeSchedule>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  late DateTime _weekStart;

  // فلاتر
  String? _filterEmpId; // null = الكل
  String? _filterPointId; // null = الكل
  bool _includeNonApproved = false; // افتراضياً المعتمدة فقط

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _weekStart = MockRepository().currentWeekStart();
    MockRepository().addListener(_onChange);
  }

  @override
  void dispose() {
    _tabs.dispose();
    MockRepository().removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  void _changeWeek(int weeks) {
    setState(() => _weekStart = _weekStart.add(Duration(days: weeks * 7)));
  }

  /// كل الـ assignments بعد تطبيق الفلاتر
  List<_AggregatedShift> _gatherShifts(
      MockRepository repo, String? activeCountry) {
    final wsKey = _weekStart.toIso8601String().substring(0, 10);
    final result = <_AggregatedShift>[];
    for (final r in repo.rosters) {
      if (!_includeNonApproved && r.status != RosterStatus.approved) continue;
      if (r.weekStart.toIso8601String().substring(0, 10) != wsKey) continue;
      // فلتر الدولة
      if (activeCountry != null) {
        final point = repo.pointById(r.siteId);
        if (point?.countryId != activeCountry) continue;
      }
      // فلتر النقطة
      if (_filterPointId != null && r.siteId != _filterPointId) continue;
      for (final a in r.assignments) {
        if (a.shiftType == ShiftType.off) continue;
        if (_filterEmpId != null && a.employeeId != _filterEmpId) continue;
        result.add(_AggregatedShift(
          employeeId: a.employeeId,
          dayIndex: a.dayIndex,
          startTime: a.startTime,
          endTime: a.endTime,
          shiftType: a.shiftType,
          pointId: r.siteId,
          rosterStatus: r.status,
          hours: a.hours,
          notes: a.notes,
        ));
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final auth = context.watch<AuthProvider>();
    final activeCountry = auth.activeCountryId;
    final allShifts = _gatherShifts(repo, activeCountry);

    return Scaffold(
      body: Column(
        children: [
          // Header مع تنقل الأسبوع
          Container(
            color: Theme.of(context).cardTheme.color,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _changeWeek(-1),
                ),
                Expanded(
                  child: Center(
                    child: Column(
                      children: [
                        Text(
                          s.isAr
                              ? 'الجدولة الأسبوعية الموحّدة'
                              : 'Weekly Schedule (All Points)',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w800),
                        ),
                        Text(
                          '${_fmt(_weekStart)} - ${_fmt(_weekStart.add(const Duration(days: 6)))}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _changeWeek(1),
                ),
              ],
            ),
          ),
          // فلاتر
          _FilterBar(
            shifts: allShifts,
            filterEmpId: _filterEmpId,
            filterPointId: _filterPointId,
            includeNonApproved: _includeNonApproved,
            onEmpChanged: (id) => setState(() => _filterEmpId = id),
            onPointChanged: (id) => setState(() => _filterPointId = id),
            onIncludeNonApprovedChanged: (v) =>
                setState(() => _includeNonApproved = v),
          ),
          // التابات
          Container(
            color: Theme.of(context).cardTheme.color,
            child: TabBar(
              controller: _tabs,
              labelColor: AppColors.brand,
              unselectedLabelColor: Theme.of(context).disabledColor,
              indicatorColor: AppColors.brand,
              tabs: [
                Tab(text: s.isAr ? 'الجدول' : 'Schedule'),
                Tab(text: s.isAr ? 'التقارير' : 'Reports'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _SchedulePane(
                  shifts: allShifts,
                  weekStart: _weekStart,
                ),
                _ReportsPane(
                  shifts: allShifts,
                  weekStart: _weekStart,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.day}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

// ============================================================
// بنية البيانات: وردية مُجمَّعة
// ============================================================
class _AggregatedShift {
  final String employeeId;
  final int dayIndex;
  final String startTime;
  final String endTime;
  final ShiftType shiftType;
  final String pointId;
  final RosterStatus rosterStatus;
  final double hours;
  final String? notes;
  _AggregatedShift({
    required this.employeeId,
    required this.dayIndex,
    required this.startTime,
    required this.endTime,
    required this.shiftType,
    required this.pointId,
    required this.rosterStatus,
    required this.hours,
    this.notes,
  });

  /// ساعات البداية والنهاية بصيغة عشرية مع التعامل مع الورديات الليلية
  (double, double) get hourSpan {
    final p1 = startTime.split(':');
    final p2 = endTime.split(':');
    final start = (int.tryParse(p1[0]) ?? 0) +
        ((int.tryParse(p1[1]) ?? 0) / 60.0);
    var end =
        (int.tryParse(p2[0]) ?? 0) + ((int.tryParse(p2[1]) ?? 0) / 60.0);
    if (end <= start) end += 24;
    return (start, end);
  }
}

// ============================================================
// شريط الفلاتر
// ============================================================
class _FilterBar extends StatelessWidget {
  final List<_AggregatedShift> shifts; // قبل الفلترة الكاملة (للقوائم)
  final String? filterEmpId;
  final String? filterPointId;
  final bool includeNonApproved;
  final void Function(String?) onEmpChanged;
  final void Function(String?) onPointChanged;
  final void Function(bool) onIncludeNonApprovedChanged;
  const _FilterBar({
    required this.shifts,
    required this.filterEmpId,
    required this.filterPointId,
    required this.includeNonApproved,
    required this.onEmpChanged,
    required this.onPointChanged,
    required this.onIncludeNonApprovedChanged,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    // قوائم فلترة (تُعرض كل الموظفين والنقاط النشطة)
    final empIds = shifts.map((s) => s.employeeId).toSet().toList()..sort();
    final pointIds = shifts.map((s) => s.pointId).toSet().toList();

    return Container(
      color: Theme.of(context).cardTheme.color,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String?>(
                  value: filterEmpId,
                  isDense: true,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: s.isAr ? 'الموظف' : 'Employee',
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                  ),
                  items: [
                    DropdownMenuItem(
                        value: null,
                        child: Text(s.isAr ? 'كل الموظفين' : 'All Employees',
                            style: const TextStyle(fontSize: 12))),
                    ...empIds.map((id) {
                      final e = repo.employeeById(id);
                      return DropdownMenuItem(
                        value: id,
                        child: Text(
                            e == null ? id : '${e.code} - ${e.fullName}',
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis),
                      );
                    }),
                  ],
                  onChanged: onEmpChanged,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: DropdownButtonFormField<String?>(
                  value: filterPointId,
                  isDense: true,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: s.isAr ? 'النقطة' : 'Point',
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                  ),
                  items: [
                    DropdownMenuItem(
                        value: null,
                        child: Text(s.isAr ? 'كل النقاط' : 'All Points',
                            style: const TextStyle(fontSize: 12))),
                    ...pointIds.map((id) {
                      final p = repo.pointById(id);
                      return DropdownMenuItem(
                        value: id,
                        child: Text(p?.name ?? id,
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis),
                      );
                    }),
                  ],
                  onChanged: onPointChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Checkbox(
                value: includeNonApproved,
                onChanged: (v) => onIncludeNonApprovedChanged(v ?? false),
              ),
              Text(
                s.isAr
                    ? 'تضمين الروسترات غير المعتمدة'
                    : 'Include non-approved rosters',
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================
// التاب الأول: الجدول
// ============================================================
class _SchedulePane extends StatelessWidget {
  final List<_AggregatedShift> shifts;
  final DateTime weekStart;
  const _SchedulePane({required this.shifts, required this.weekStart});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final byEmp = <String, List<_AggregatedShift>>{};
    for (final sh in shifts) {
      byEmp.putIfAbsent(sh.employeeId, () => []).add(sh);
    }
    final employees = byEmp.keys
        .map((id) => repo.employeeById(id))
        .whereType<Employee>()
        .toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));

    if (employees.isEmpty) {
      return EmptyState(
        icon: Icons.calendar_today,
        message: s.isAr
            ? 'لا توجد ورديات تطابق الفلاتر'
            : 'No shifts match the filters',
      );
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: _ScheduleGrid(
            employees: employees, byEmp: byEmp, weekStart: weekStart),
      ),
    );
  }
}

class _ScheduleGrid extends StatelessWidget {
  final List<Employee> employees;
  final Map<String, List<_AggregatedShift>> byEmp;
  final DateTime weekStart;
  const _ScheduleGrid({
    required this.employees,
    required this.byEmp,
    required this.weekStart,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final dayShortNames = s.isAr
        ? ['ثن', 'ثل', 'أر', 'خم', 'جم', 'سب', 'أح']
        : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    const empColWidth = 150.0;
    const dayColWidth = 110.0;
    const totalColWidth = 60.0;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              _GridCell(
                  label: s.isAr ? 'الموظفون' : 'Employees',
                  width: empColWidth,
                  isHeader: true),
              ...List.generate(7, (i) {
                final d = weekStart.add(Duration(days: i));
                return _GridCell(
                    width: dayColWidth,
                    isHeader: true,
                    label:
                        '${dayShortNames[i]}\n${d.day.toString().padLeft(2, "0")}/${d.month.toString().padLeft(2, "0")}');
              }),
              const _GridCell(
                  label: 'h',
                  width: totalColWidth,
                  isHeader: true,
                  isAccent: true),
            ]),
            ...employees.map((emp) {
              final shifts = byEmp[emp.id] ?? [];
              double total = 0;
              for (final sh in shifts) {
                total += sh.hours;
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _EmpNameCell(employee: emp, width: empColWidth),
                    ...List.generate(7, (dayIndex) {
                      final dayShifts = shifts
                          .where((sh) => sh.dayIndex == dayIndex)
                          .toList();
                      return _ShiftCell(
                          width: dayColWidth, shifts: dayShifts);
                    }),
                    _TotalCell(width: totalColWidth, hours: total),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _GridCell extends StatelessWidget {
  final String label;
  final double width;
  final bool isHeader;
  final bool isAccent;
  const _GridCell({
    required this.label,
    required this.width,
    this.isHeader = false,
    this.isAccent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isAccent
            ? AppColors.warning.withOpacity(0.15)
            : (isHeader
                ? Theme.of(context).dividerColor.withOpacity(0.15)
                : null),
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor),
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: isAccent ? AppColors.warning : null,
        ),
      ),
    );
  }
}

class _EmpNameCell extends StatelessWidget {
  final Employee employee;
  final double width;
  const _EmpNameCell({required this.employee, required this.width});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor),
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(employee.fullName,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(employee.code,
              style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.brand,
                  fontFamily: 'monospace')),
        ],
      ),
    );
  }
}

class _ShiftCell extends StatelessWidget {
  final double width;
  final List<_AggregatedShift> shifts;
  const _ShiftCell({required this.width, required this.shifts});

  Color _pointColor(String pointId) {
    final palette = [
      AppColors.brand,
      AppColors.success,
      AppColors.warning,
      AppColors.info,
      Colors.purple,
      Colors.teal,
      Colors.pink,
      Colors.indigo,
    ];
    return palette[pointId.hashCode.abs() % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final repo = MockRepository();
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor),
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: shifts.isEmpty
          ? Center(
              child: Text('—',
                  style: TextStyle(
                      color: Theme.of(context).disabledColor, fontSize: 12)))
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: shifts.map((sh) {
                final point = repo.pointById(sh.pointId);
                final color = _pointColor(sh.pointId);
                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 1),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    border: Border.all(color: color.withOpacity(0.5)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(point?.name ?? '?',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: color),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text('${sh.startTime}-${sh.endTime}',
                          style: const TextStyle(
                              fontSize: 9,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class _TotalCell extends StatelessWidget {
  final double width;
  final double hours;
  const _TotalCell({required this.width, required this.hours});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.08),
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor),
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Text(hours.toStringAsFixed(0),
          style: const TextStyle(
              color: AppColors.warning,
              fontWeight: FontWeight.w800,
              fontSize: 14)),
    );
  }
}

// ============================================================
// التاب الثاني: التقارير
// ============================================================
class _ReportsPane extends StatelessWidget {
  final List<_AggregatedShift> shifts;
  final DateTime weekStart;
  const _ReportsPane({required this.shifts, required this.weekStart});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();

    // KPIs
    final totalHours =
        shifts.fold(0.0, (sum, sh) => sum + sh.hours);
    final totalShifts = shifts.length;
    final empCount = shifts.map((s) => s.employeeId).toSet().length;
    final pointCount = shifts.map((s) => s.pointId).toSet().length;
    final avgPerEmp = empCount == 0 ? 0.0 : totalHours / empCount;

    // التوزيع الساعي 24×7 (عدد الموظفين في كل ساعة)
    // hourly[day][hour] = count
    final hourly = List.generate(7, (_) => List.filled(24, 0));
    for (final sh in shifts) {
      final (start, end) = sh.hourSpan;
      // اعتبر كل ساعة شاملة في الفترة
      for (var h = start.floor(); h < end.ceil(); h++) {
        final actualH = h % 24;
        final actualDay = (sh.dayIndex + (h ~/ 24)) % 7;
        if (h >= 0 && h < 168) {
          hourly[actualDay][actualH]++;
        }
      }
    }

    // ساعات لكل موظف
    final empHours = <String, double>{};
    for (final sh in shifts) {
      empHours[sh.employeeId] = (empHours[sh.employeeId] ?? 0) + sh.hours;
    }
    final empSorted = empHours.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // ساعات لكل نقطة
    final pointHours = <String, double>{};
    for (final sh in shifts) {
      pointHours[sh.pointId] = (pointHours[sh.pointId] ?? 0) + sh.hours;
    }
    final pointSorted = pointHours.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (shifts.isEmpty) {
      return EmptyState(
        icon: Icons.bar_chart,
        message: s.isAr
            ? 'لا توجد بيانات للتقرير'
            : 'No data for the report',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // ===== KPIs =====
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          childAspectRatio: 2.4,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          children: [
            _Kpi(
                label: s.totalHours,
                value: totalHours.toStringAsFixed(0),
                color: AppColors.brand,
                icon: Icons.access_time),
            _Kpi(
                label: s.isAr ? 'الورديات' : 'Shifts',
                value: '$totalShifts',
                color: AppColors.success,
                icon: Icons.event_note),
            _Kpi(
                label: s.isAr ? 'الموظفون' : 'Employees',
                value: '$empCount',
                color: AppColors.info,
                icon: Icons.people),
            _Kpi(
                label: s.isAr ? 'النقاط' : 'Points',
                value: '$pointCount',
                color: AppColors.warning,
                icon: Icons.place),
            _Kpi(
                label: s.isAr ? 'متوسط/موظف' : 'Avg/Employee',
                value: '${avgPerEmp.toStringAsFixed(1)}h',
                color: Colors.purple,
                icon: Icons.show_chart),
          ],
        ),
        const SizedBox(height: 14),

        // ===== التوزيع الساعي (24 ساعة) =====
        SectionCard(
          title: s.isAr
              ? 'توزيع الموظفين في كل ساعة (24 ساعة × 7 أيام)'
              : 'Employees per Hour (24h × 7 days)',
          child: _HourlyHeatmap(hourly: hourly),
        ),
        const SizedBox(height: 14),

        // ===== ساعات الموظفين (Top 10) =====
        SectionCard(
          title: s.isAr ? 'ساعات الموظفين' : 'Hours per Employee',
          child: Column(
            children: empSorted.take(15).map((e) {
              final emp = repo.employeeById(e.key);
              final maxH = empSorted.first.value;
              return _BarRow(
                label: emp?.fullName ?? '—',
                code: emp?.code ?? '',
                value: e.value,
                max: maxH,
                color: AppColors.brand,
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 14),

        // ===== ساعات النقاط =====
        SectionCard(
          title: s.isAr ? 'ساعات النقاط' : 'Hours per Point',
          child: Column(
            children: pointSorted.map((e) {
              final p = repo.pointById(e.key);
              final maxH = pointSorted.first.value;
              return _BarRow(
                label: p?.name ?? '—',
                code: p?.code ?? '',
                value: e.value,
                max: maxH,
                color: AppColors.warning,
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// خريطة حرارية للتوزيع الساعي
// ============================================================
class _HourlyHeatmap extends StatelessWidget {
  final List<List<int>> hourly; // [day][hour]
  const _HourlyHeatmap({required this.hourly});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final dayLabels = s.isAr
        ? ['ثن', 'ثل', 'أر', 'خم', 'جم', 'سب', 'أح']
        : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    // اعثر على أعلى قيمة لتحديد الأقصى للون
    var maxV = 0;
    for (var d = 0; d < 7; d++) {
      for (var h = 0; h < 24; h++) {
        if (hourly[d][h] > maxV) maxV = hourly[d][h];
      }
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // محور الساعات
          Row(
            children: [
              const SizedBox(width: 32),
              ...List.generate(24, (h) {
                return SizedBox(
                  width: 22,
                  child: Center(
                    child: Text(h.toString().padLeft(2, '0'),
                        style: const TextStyle(
                            fontSize: 8, fontFamily: 'monospace')),
                  ),
                );
              }),
            ],
          ),
          const SizedBox(height: 4),
          // الصفوف (الأيام)
          ...List.generate(7, (day) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 32,
                    child: Text(dayLabels[day],
                        style: const TextStyle(
                            fontSize: 10, fontWeight: FontWeight.w700)),
                  ),
                  ...List.generate(24, (hour) {
                    final v = hourly[day][hour];
                    final t =
                        maxV == 0 ? 0.0 : (v / maxV).clamp(0.0, 1.0);
                    return Tooltip(
                      message: '${dayLabels[day]} ${hour.toString().padLeft(2, '0')}:00 → $v',
                      child: Container(
                        width: 22,
                        height: 22,
                        margin: const EdgeInsets.symmetric(horizontal: 0.5),
                        decoration: BoxDecoration(
                          color: v == 0
                              ? Theme.of(context).dividerColor.withOpacity(0.2)
                              : Color.lerp(
                                  AppColors.brand.withOpacity(0.15),
                                  AppColors.brand,
                                  t,
                                ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        alignment: Alignment.center,
                        child: v == 0
                            ? null
                            : Text(
                                '$v',
                                style: TextStyle(
                                    color: t > 0.5
                                        ? Colors.white
                                        : AppColors.brand,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800),
                              ),
                      ),
                    );
                  }),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
          // مفتاح الألوان
          Row(children: [
            Text(s.isAr ? 'قليل' : 'Low',
                style: const TextStyle(fontSize: 10)),
            const SizedBox(width: 4),
            ...List.generate(5, (i) {
              final t = (i / 4).clamp(0.0, 1.0);
              return Container(
                width: 16,
                height: 12,
                margin: const EdgeInsets.symmetric(horizontal: 0.5),
                color: Color.lerp(AppColors.brand.withOpacity(0.15),
                    AppColors.brand, t),
              );
            }),
            const SizedBox(width: 4),
            Text(s.isAr ? 'كثير' : 'High',
                style: const TextStyle(fontSize: 10)),
          ]),
        ],
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  const _Kpi({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(value,
                    style: TextStyle(
                        color: color,
                        fontSize: 16,
                        fontWeight: FontWeight.w800)),
                Text(label,
                    style: TextStyle(
                        color: color.withOpacity(0.85), fontSize: 10),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BarRow extends StatelessWidget {
  final String label;
  final String code;
  final double value;
  final double max;
  final Color color;
  const _BarRow({
    required this.label,
    required this.code,
    required this.value,
    required this.max,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final t = max == 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700)),
              ),
              if (code.isNotEmpty)
                Text(code,
                    style: TextStyle(
                        fontSize: 10,
                        fontFamily: 'monospace',
                        color: color)),
              const SizedBox(width: 6),
              Text('${value.toStringAsFixed(0)}h',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: color)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: t,
              minHeight: 7,
              backgroundColor: color.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }
}
