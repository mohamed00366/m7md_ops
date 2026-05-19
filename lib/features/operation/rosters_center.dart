import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/excel_exporter.dart';
import '../../core/services/roster_settings.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../models/models.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/widgets.dart';
import 'operation_rosters.dart';

/// مركز الروسترات الموحّد - ٣ تابات (قائمة + جدولة + تقارير)
/// يخدم: Supervisor (نقطته فقط) + Operation/Admin/SuperAdmin (الكل)
class RostersCenter extends StatefulWidget {
  const RostersCenter({super.key});

  @override
  State<RostersCenter> createState() => _RostersCenterState();
}

class _RostersCenterState extends State<RostersCenter>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  late DateTime _weekStart;

  // Shared filters
  RosterStatus? _filterStatus;
  String? _filterPointId;
  String? _filterEmpId;
  bool _includeNonApproved = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _weekStart = MockRepository().currentWeekStart();
    MockRepository().addListener(_onChange);
    RosterSettings.instance.addListener(_onChange);
    RosterSettings.instance.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    MockRepository().removeListener(_onChange);
    RosterSettings.instance.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() => mounted ? setState(() {}) : null;

  void _changeWeek(int weeks) =>
      setState(() => _weekStart = _weekStart.add(Duration(days: weeks * 7)));

  // -----------------------------------------------------------
  // Visibility scope:
  //   - Operation/Admin/SuperAdmin (لديهم rosters.approve أو rosters.view بدون
  //     أن يكونوا مشرفي نقطة) → يرون كل روسترات الدولة ويعدّلون
  //   - Supervisor (موظف مرتبط بنقطة وليس عنده rosters.approve) → نقطته فقط
  // -----------------------------------------------------------
  ({String? supervisorPointId, bool isSupervisorMode}) _scope(
      MockRepository repo, AuthProvider auth) {
    // 1) Super Admin / من لديه صلاحية اعتماد الروسترات → عرض كامل
    if (auth.isSuperAdmin || auth.permissions.contains(P.rostersApprove)) {
      return (supervisorPointId: null, isSupervisorMode: false);
    }
    // 2) ليس مرتبطاً بسجلّ موظف → عرض كامل ضمن صلاحياته
    final empId = auth.currentUser?.employeeId;
    if (empId == null) {
      return (supervisorPointId: null, isSupervisorMode: false);
    }
    // 3) موظف مرتبط بسجلّ — هل هو مشرف نقطة فعلاً؟
    Employee? emp;
    try {
      emp = repo.employees.firstWhere((e) => e.id == empId);
    } catch (_) {
      // لا يوجد سجل موظف مطابق → عرض كامل
      return (supervisorPointId: null, isSupervisorMode: false);
    }
    final pointId = emp.pointId ?? emp.siteId;
    if (pointId == null || pointId.isEmpty) {
      // موظف بلا نقطة (إداري مكتبي) → عرض كامل ضمن صلاحياته
      return (supervisorPointId: null, isSupervisorMode: false);
    }
    // مشرف نقطة فعلي
    return (supervisorPointId: pointId, isSupervisorMode: true);
  }

  /// كل الروسترات بعد الفلاتر (المشرف vs Admin، الدولة، الفلاتر المعروضة)
  List<WeeklyRoster> _filteredRosters(MockRepository repo, AuthProvider auth) {
    final wsKey = _weekStart.toIso8601String().substring(0, 10);
    final scope = _scope(repo, auth);
    return repo.rosters.where((r) {
      // مشرف: نقطته فقط
      if (scope.isSupervisorMode) {
        if (scope.supervisorPointId == null) return false;
        if (r.siteId != scope.supervisorPointId) return false;
      } else {
        // Admin/Operation: فلتر الدولة
        if (auth.activeCountryId != null) {
          final p = repo.pointById(r.siteId);
          if (p?.countryId != auth.activeCountryId) return false;
        } else if (!auth.isSuperAdmin) {
          return false;
        }
      }
      // فلتر النقطة (إن وُجد)
      if (_filterPointId != null && r.siteId != _filterPointId) return false;
      // فلتر الأسبوع
      if (r.weekStart.toIso8601String().substring(0, 10) != wsKey) return false;
      // فلتر الحالة
      if (_filterStatus != null && r.status != _filterStatus) return false;
      return true;
    }).toList()
      ..sort((a, b) => b.weekStart.compareTo(a.weekStart));
  }

  /// الورديات المُجمَّعة (للجدولة + التقارير)
  List<_AggShift> _aggShifts(List<WeeklyRoster> rosters) {
    final result = <_AggShift>[];
    for (final r in rosters) {
      if (!_includeNonApproved && r.status != RosterStatus.approved) continue;
      for (final a in r.assignments) {
        if (a.shiftType == ShiftType.off) continue;
        if (_filterEmpId != null && a.employeeId != _filterEmpId) continue;
        result.add(_AggShift(
          employeeId: a.employeeId,
          dayIndex: a.dayIndex,
          startTime: a.startTime,
          endTime: a.endTime,
          shiftType: a.shiftType,
          pointId: r.siteId,
          rosterStatus: r.status,
          hours: a.hours,
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
    final scope = _scope(repo, auth);

    if (scope.isSupervisorMode && scope.supervisorPointId == null) {
      return EmptyState(
        icon: Icons.location_off,
        message: s.isAr
            ? 'لم يتم ربطك بنقطة بعد. تواصل مع Operation'
            : 'You\'re not assigned to a Point. Contact Operation',
      );
    }

    final rosters = _filteredRosters(repo, auth);
    final shifts = _aggShifts(rosters);

    return Scaffold(
      body: Column(
        children: [
          _WeekHeader(
            weekStart: _weekStart,
            onPrev: () => _changeWeek(-1),
            onNext: () => _changeWeek(1),
          ),
          _Filters(
            isSupervisorMode: scope.isSupervisorMode,
            filterStatus: _filterStatus,
            filterPointId: _filterPointId,
            filterEmpId: _filterEmpId,
            includeNonApproved: _includeNonApproved,
            allRosters: _allRostersForOptions(repo, auth, scope),
            onStatusChanged: (v) => setState(() => _filterStatus = v),
            onPointChanged: (v) => setState(() => _filterPointId = v),
            onEmpChanged: (v) => setState(() => _filterEmpId = v),
            onIncludeNonApprovedChanged: (v) =>
                setState(() => _includeNonApproved = v),
          ),
          Container(
            color: Theme.of(context).cardTheme.color,
            child: TabBar(
              controller: _tabs,
              labelColor: AppColors.brand,
              unselectedLabelColor: Theme.of(context).disabledColor,
              indicatorColor: AppColors.brand,
              tabs: [
                Tab(
                  icon: const Icon(Icons.list_alt, size: 18),
                  text: '${s.isAr ? "القائمة" : "List"} (${rosters.length})',
                ),
                Tab(
                  icon: const Icon(Icons.calendar_view_week, size: 18),
                  text: s.isAr ? 'الجدولة' : 'Schedule',
                ),
                Tab(
                  icon: const Icon(Icons.bar_chart, size: 18),
                  text: s.isAr ? 'التقارير' : 'Reports',
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _ListTab(rosters: rosters),
                _ScheduleTab(shifts: shifts, weekStart: _weekStart),
                _ReportsTab(shifts: shifts, weekStart: _weekStart),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// قائمة الروسترات قبل الـ filter (لخيارات dropdowns)
  List<WeeklyRoster> _allRostersForOptions(
    MockRepository repo,
    AuthProvider auth,
    ({String? supervisorPointId, bool isSupervisorMode}) scope,
  ) {
    final wsKey = _weekStart.toIso8601String().substring(0, 10);
    return repo.rosters.where((r) {
      if (scope.isSupervisorMode) {
        if (r.siteId != scope.supervisorPointId) return false;
      } else if (auth.activeCountryId != null) {
        final p = repo.pointById(r.siteId);
        if (p?.countryId != auth.activeCountryId) return false;
      } else if (!auth.isSuperAdmin) {
        return false;
      }
      if (r.weekStart.toIso8601String().substring(0, 10) != wsKey) return false;
      return true;
    }).toList();
  }
}

// ============================================================
// بنية البيانات
// ============================================================
class _AggShift {
  final String employeeId;
  final int dayIndex;
  final String startTime;
  final String endTime;
  final ShiftType shiftType;
  final String pointId;
  final RosterStatus rosterStatus;
  final double hours;
  _AggShift({
    required this.employeeId,
    required this.dayIndex,
    required this.startTime,
    required this.endTime,
    required this.shiftType,
    required this.pointId,
    required this.rosterStatus,
    required this.hours,
  });
}

// ============================================================
// Header
// ============================================================
class _WeekHeader extends StatelessWidget {
  final DateTime weekStart;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  const _WeekHeader(
      {required this.weekStart, required this.onPrev, required this.onNext});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    // 🆕 شريط مدمج: أسهم التنقّل + التاريخ في صفّ واحد بدون عنوان
    // (العنوان يَظهر بالفعل في الـ AppBar فوق هذه الشاشة).
    return Container(
      color: Theme.of(context).cardTheme.color,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          InkWell(
            onTap: onPrev,
            borderRadius: BorderRadius.circular(20),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.chevron_right, size: 18),
            ),
          ),
          Text(
            '${_fmt(weekStart)} - ${_fmt(weekStart.add(const Duration(days: 6)))}',
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700),
          ),
          InkWell(
            onTap: onNext,
            borderRadius: BorderRadius.circular(20),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.chevron_left, size: 18),
            ),
          ),
          // عنوان مختصر للتذكير
          const SizedBox(width: 8),
          Text(
            s.isAr ? 'مركز الروسترات' : 'Rosters',
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.day}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

// ============================================================
// Filters
// ============================================================
class _Filters extends StatelessWidget {
  final bool isSupervisorMode;
  final RosterStatus? filterStatus;
  final String? filterPointId;
  final String? filterEmpId;
  final bool includeNonApproved;
  final List<WeeklyRoster> allRosters;
  final void Function(RosterStatus?) onStatusChanged;
  final void Function(String?) onPointChanged;
  final void Function(String?) onEmpChanged;
  final void Function(bool) onIncludeNonApprovedChanged;
  const _Filters({
    required this.isSupervisorMode,
    required this.filterStatus,
    required this.filterPointId,
    required this.filterEmpId,
    required this.includeNonApproved,
    required this.allRosters,
    required this.onStatusChanged,
    required this.onPointChanged,
    required this.onEmpChanged,
    required this.onIncludeNonApprovedChanged,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final pointIds = allRosters.map((r) => r.siteId).toSet().toList();
    final empIds = <String>{};
    for (final r in allRosters) {
      for (final a in r.assignments) {
        empIds.add(a.employeeId);
      }
    }
    final empList = empIds.toList();

    // 🆕 صفّ واحد فيه 3 dropdowns + checkbox مدمج
    InputDecoration deco(String label) => InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 10),
          isDense: true,
          border: const OutlineInputBorder(),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        );
    return Container(
      color: Theme.of(context).cardTheme.color,
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 4),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<RosterStatus?>(
                  value: filterStatus,
                  isDense: true,
                  isExpanded: true,
                  style: const TextStyle(fontSize: 11),
                  decoration: deco('Status'),
                  items: [
                    DropdownMenuItem(
                        value: null,
                        child: Text(s.all,
                            style: const TextStyle(fontSize: 11))),
                    ...RosterStatus.values.map((v) => DropdownMenuItem(
                          value: v,
                          child: Text(
                            s.isAr
                                ? v.arabicLabel()
                                : v.englishLabel(),
                            style: const TextStyle(fontSize: 11),
                          ),
                        )),
                  ],
                  onChanged: onStatusChanged,
                ),
              ),
              if (!isSupervisorMode) ...[
                const SizedBox(width: 4),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    value: filterPointId,
                    isDense: true,
                    isExpanded: true,
                    style: const TextStyle(fontSize: 11),
                    decoration: deco(s.isAr ? 'النقطة' : 'Point'),
                    items: [
                      DropdownMenuItem(
                          value: null,
                          child: Text(s.isAr ? 'كل النقاط' : 'All',
                              style: const TextStyle(fontSize: 11))),
                      ...pointIds.map((id) {
                        final p = repo.pointById(id);
                        return DropdownMenuItem(
                          value: id,
                          child: Text(p?.name ?? id,
                              style: const TextStyle(fontSize: 11),
                              overflow: TextOverflow.ellipsis),
                        );
                      }),
                    ],
                    onChanged: onPointChanged,
                  ),
                ),
              ],
              const SizedBox(width: 4),
              Expanded(
                child: DropdownButtonFormField<String?>(
                  value: filterEmpId,
                  isDense: true,
                  isExpanded: true,
                  style: const TextStyle(fontSize: 11),
                  decoration: deco(s.isAr ? 'الموظف' : 'Emp'),
                  items: [
                    DropdownMenuItem(
                        value: null,
                        child: Text(s.isAr ? 'كل الموظفين' : 'All',
                            style: const TextStyle(fontSize: 11))),
                    ...empList.map((id) {
                      final e = repo.employeeById(id);
                      return DropdownMenuItem(
                        value: id,
                        child: Text(
                            e == null ? id : e.fullName,
                            style: const TextStyle(fontSize: 11),
                            overflow: TextOverflow.ellipsis),
                      );
                    }),
                  ],
                  onChanged: onEmpChanged,
                ),
              ),
            ],
          ),
          // checkbox المدمج
          SizedBox(
            height: 24,
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: Checkbox(
                    materialTapTargetSize:
                        MaterialTapTargetSize.shrinkWrap,
                    value: includeNonApproved,
                    onChanged: (v) =>
                        onIncludeNonApprovedChanged(v ?? false),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  s.isAr
                      ? 'تضمين غير المعتمد'
                      : 'Include non-approved',
                  style: const TextStyle(fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// تاب ١: القائمة
// ============================================================
class _ListTab extends StatelessWidget {
  final List<WeeklyRoster> rosters;
  const _ListTab({required this.rosters});

  Color _statusColor(RosterStatus s) {
    return switch (s) {
      RosterStatus.draft => AppColors.textTertiaryLight,
      RosterStatus.submitted => AppColors.warning,
      RosterStatus.underReview => AppColors.info,
      RosterStatus.approved => AppColors.success,
      RosterStatus.rejected => AppColors.danger,
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    if (rosters.isEmpty) {
      return EmptyState(
        icon: Icons.inbox_outlined,
        message: s.isAr ? 'لا توجد روسترات' : 'No rosters',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: rosters.length,
      itemBuilder: (_, i) {
        final r = rosters[i];
        final point = repo.pointById(r.siteId);
        final sup = repo.employeeById(r.supervisorId);
        final empCount =
            r.assignments.map((a) => a.employeeId).toSet().length;
        return InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => RosterReviewScreen(roster: r),
          )),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Column(
              children: [
                // Header مع اسم النقطة بارز
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.08),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(11)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.warning,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.place,
                            color: Colors.white, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              point?.name ?? '—',
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800),
                            ),
                            if (point?.code.isNotEmpty == true)
                              Text(
                                point!.code,
                                style: const TextStyle(
                                    fontSize: 10,
                                    fontFamily: 'monospace',
                                    color: AppColors.warning,
                                    fontWeight: FontWeight.w700),
                              ),
                          ],
                        ),
                      ),
                      StatusBadge(
                        label: s.isAr
                            ? r.status.arabicLabel()
                            : r.status.englishLabel(),
                        color: _statusColor(r.status),
                      ),
                    ],
                  ),
                ),
                // Body
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          if (sup != null) ...[
                            const Icon(Icons.person,
                                size: 12, color: AppColors.brand),
                            const SizedBox(width: 4),
                            Text(sup.fullName,
                                style: const TextStyle(fontSize: 11)),
                          ],
                          const Spacer(),
                          Text(
                            '${_fmt(r.weekStart)} - ${_fmt(r.weekStart.add(const Duration(days: 6)))}',
                            style: const TextStyle(fontSize: 10),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _Pill(
                              icon: Icons.people,
                              label: '$empCount',
                              color: AppColors.info,
                              tooltip:
                                  s.isAr ? 'الموظفون' : 'Employees'),
                          const SizedBox(width: 6),
                          _Pill(
                              icon: Icons.event_note,
                              label: '${r.assignments.length}',
                              color: AppColors.success,
                              tooltip: s.isAr ? 'الورديات' : 'Shifts'),
                          const SizedBox(width: 6),
                          _Pill(
                              icon: Icons.access_time,
                              label:
                                  '${r.totalHours.toStringAsFixed(0)}h',
                              color: AppColors.brand,
                              tooltip: s.totalHours),
                          const Spacer(),
                          const Icon(Icons.arrow_forward_ios,
                              size: 12, color: AppColors.textTertiaryLight),
                        ],
                      ),
                      // Approval info
                      if (r.status == RosterStatus.approved &&
                          r.reviewedAt != null) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppColors.success.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.verified,
                                  size: 12, color: AppColors.success),
                              const SizedBox(width: 4),
                              Text(
                                '${s.isAr ? "اعتُمد في" : "Approved on"}: ${_fmtDt(r.reviewedAt!)}',
                                style: const TextStyle(
                                    fontSize: 10,
                                    color: AppColors.success,
                                    fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (r.status == RosterStatus.rejected &&
                          r.rejectionReason != null) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppColors.danger.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.cancel,
                                  size: 12, color: AppColors.danger),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  '${s.rejectionReason}: ${r.rejectionReason}',
                                  style: const TextStyle(
                                      fontSize: 10,
                                      color: AppColors.danger),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _fmt(DateTime d) => '${d.day}/${d.month.toString().padLeft(2, '0')}';
  String _fmtDt(DateTime d) =>
      '${d.day}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final String tooltip;
  const _Pill(
      {required this.icon,
      required this.label,
      required this.color,
      required this.tooltip});
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// تاب ٢: الجدولة
// ============================================================
class _ScheduleTab extends StatelessWidget {
  final List<_AggShift> shifts;
  final DateTime weekStart;
  const _ScheduleTab({required this.shifts, required this.weekStart});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final byEmp = <String, List<_AggShift>>{};
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
        message: s.isAr ? 'لا توجد ورديات' : 'No shifts',
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
  final Map<String, List<_AggShift>> byEmp;
  final DateTime weekStart;
  const _ScheduleGrid(
      {required this.employees,
      required this.byEmp,
      required this.weekStart});

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
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final dayShortNames = s.isAr
        ? ['ثن', 'ثل', 'أر', 'خم', 'جم', 'سب', 'أح']
        : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const empColW = 150.0;
    const dayColW = 110.0;
    const totalColW = 60.0;

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
              _Cell(
                  label: s.isAr ? 'الموظفون' : 'Employees',
                  width: empColW,
                  isHeader: true),
              ...List.generate(7, (i) {
                final d = weekStart.add(Duration(days: i));
                return _Cell(
                    width: dayColW,
                    isHeader: true,
                    label:
                        '${dayShortNames[i]}\n${d.day.toString().padLeft(2, "0")}/${d.month.toString().padLeft(2, "0")}');
              }),
              const _Cell(
                  label: 'h',
                  width: totalColW,
                  isHeader: true,
                  isAccent: true),
            ]),
            ...employees.map((emp) {
              final list = byEmp[emp.id] ?? [];
              double total = 0;
              for (final sh in list) {
                total += sh.hours;
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: empColW,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border(
                          right: BorderSide(
                              color: Theme.of(context).dividerColor),
                          bottom: BorderSide(
                              color: Theme.of(context).dividerColor),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(emp.fullName,
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          Text(emp.code,
                              style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.brand,
                                  fontFamily: 'monospace')),
                        ],
                      ),
                    ),
                    ...List.generate(7, (dayIndex) {
                      final dayShifts =
                          list.where((sh) => sh.dayIndex == dayIndex).toList();
                      return Container(
                        width: dayColW,
                        padding: const EdgeInsets.symmetric(
                            vertical: 4, horizontal: 4),
                        decoration: BoxDecoration(
                          border: Border(
                            right: BorderSide(
                                color: Theme.of(context).dividerColor),
                            bottom: BorderSide(
                                color: Theme.of(context).dividerColor),
                          ),
                        ),
                        child: dayShifts.isEmpty
                            ? Center(
                                child: Text('—',
                                    style: TextStyle(
                                        color:
                                            Theme.of(context).disabledColor,
                                        fontSize: 12)))
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: dayShifts.map((sh) {
                                  final p = repo.pointById(sh.pointId);
                                  final c = _pointColor(sh.pointId);
                                  return Container(
                                    margin:
                                        const EdgeInsets.symmetric(vertical: 1),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: c.withOpacity(0.12),
                                      border: Border.all(
                                          color: c.withOpacity(0.5)),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(p?.name ?? '?',
                                            style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w800,
                                                color: c),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis),
                                        Text(
                                            '${sh.startTime}-${sh.endTime}',
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
                    }),
                    Container(
                      width: totalColW,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.warning.withOpacity(0.08),
                        border: Border(
                          right: BorderSide(
                              color: Theme.of(context).dividerColor),
                          bottom: BorderSide(
                              color: Theme.of(context).dividerColor),
                        ),
                      ),
                      child: Text(total.toStringAsFixed(0),
                          style: const TextStyle(
                              color: AppColors.warning,
                              fontWeight: FontWeight.w800,
                              fontSize: 14)),
                    ),
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

class _Cell extends StatelessWidget {
  final String label;
  final double width;
  final bool isHeader;
  final bool isAccent;
  const _Cell(
      {required this.label,
      required this.width,
      this.isHeader = false,
      this.isAccent = false});
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
      child: Text(label,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: isAccent ? AppColors.warning : null)),
    );
  }
}

// ============================================================
// تاب ٣: التقارير
// ============================================================
class _ReportsTab extends StatelessWidget {
  final List<_AggShift> shifts;
  final DateTime weekStart;
  const _ReportsTab({required this.shifts, required this.weekStart});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    if (shifts.isEmpty) {
      return EmptyState(
        icon: Icons.bar_chart,
        message: s.isAr ? 'لا توجد بيانات للتقرير' : 'No data',
      );
    }

    // KPIs
    final totalHours = shifts.fold(0.0, (a, sh) => a + sh.hours);
    final empCount = shifts.map((s) => s.employeeId).toSet().length;
    final pointCount = shifts.map((s) => s.pointId).toSet().length;
    final avg = empCount == 0 ? 0.0 : totalHours / empCount;

    // Hourly heatmap
    final hourly = List.generate(7, (_) => List.filled(24, 0));
    for (final sh in shifts) {
      final p1 = sh.startTime.split(':');
      final p2 = sh.endTime.split(':');
      final start = (int.tryParse(p1[0]) ?? 0).toDouble() +
          ((int.tryParse(p1[1]) ?? 0) / 60.0);
      var end = (int.tryParse(p2[0]) ?? 0).toDouble() +
          ((int.tryParse(p2[1]) ?? 0) / 60.0);
      if (end <= start) end += 24;
      for (var h = start.floor(); h < end.ceil(); h++) {
        final actualH = h % 24;
        final actualDay = (sh.dayIndex + (h ~/ 24)) % 7;
        hourly[actualDay][actualH]++;
      }
    }

    // Per employee
    final empHours = <String, double>{};
    final empPoints = <String, Set<String>>{};
    for (final sh in shifts) {
      empHours[sh.employeeId] = (empHours[sh.employeeId] ?? 0) + sh.hours;
      empPoints.putIfAbsent(sh.employeeId, () => {}).add(sh.pointId);
    }
    final empSorted = empHours.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Per point
    final pointHours = <String, double>{};
    final pointEmps = <String, Set<String>>{};
    for (final sh in shifts) {
      pointHours[sh.pointId] = (pointHours[sh.pointId] ?? 0) + sh.hours;
      pointEmps.putIfAbsent(sh.pointId, () => {}).add(sh.employeeId);
    }
    final pointSorted = pointHours.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // ===== Deviation Alerts (الحدود قابلة للتخصيص من إعدادات الروسترات) =====
    final maxWeekly = RosterSettings.instance.maxWeekly;
    final minStaff = RosterSettings.instance.minStaff;
    final overworkedEmps = empHours.entries
        .where((e) => e.value > maxWeekly)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final understaffedPoints = pointEmps.entries
        .where((e) => e.value.length < minStaff)
        .toList();

    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        // أزرار CSV / Excel / تصدير
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _exportCsv(context, shifts, repo),
                icon: const Icon(Icons.download, size: 16),
                label: Text(s.isAr ? 'CSV' : 'CSV',
                    style: const TextStyle(fontSize: 11)),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white),
                onPressed: () => _exportExcel(context, shifts, repo),
                icon: const Icon(Icons.table_chart, size: 16),
                label: Text(s.isAr ? 'Excel' : 'Excel',
                    style: const TextStyle(fontSize: 11)),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _copySummary(
                  context,
                  totalHours,
                  shifts.length,
                  empCount,
                  pointCount,
                  avg,
                ),
                icon: const Icon(Icons.copy, size: 16),
                label: Text(s.isAr ? 'نسخ الملخص' : 'Copy Summary'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // KPIs
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
                value: '${shifts.length}',
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
                value: '${avg.toStringAsFixed(1)}h',
                color: Colors.purple,
                icon: Icons.show_chart),
          ],
        ),
        const SizedBox(height: 14),

        // ===== تنبيهات الانحرافات =====
        if (overworkedEmps.isNotEmpty || understaffedPoints.isNotEmpty)
          SectionCard(
            title: s.isAr ? '⚠️ تنبيهات' : '⚠️ Alerts',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (overworkedEmps.isNotEmpty) ...[
                  Text(
                    s.isAr
                        ? 'موظفون يعملون أكثر من $maxWeekly ساعة في الأسبوع:'
                        : 'Employees working >${maxWeekly}h/week:',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.danger),
                  ),
                  const SizedBox(height: 4),
                  ...overworkedEmps.map((e) {
                    final emp = repo.employeeById(e.key);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(children: [
                        const Icon(Icons.warning,
                            size: 12, color: AppColors.danger),
                        const SizedBox(width: 4),
                        Expanded(
                            child: Text(emp?.fullName ?? '—',
                                style: const TextStyle(fontSize: 11))),
                        Text('${e.value.toStringAsFixed(0)}h',
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.danger,
                                fontWeight: FontWeight.w800)),
                      ]),
                    );
                  }),
                ],
                if (understaffedPoints.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    s.isAr
                        ? 'نقاط بأقل من $minStaff موظفين:'
                        : 'Points with fewer than $minStaff employees:',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.warning),
                  ),
                  const SizedBox(height: 4),
                  ...understaffedPoints.map((e) {
                    final p = repo.pointById(e.key);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(children: [
                        const Icon(Icons.info,
                            size: 12, color: AppColors.warning),
                        const SizedBox(width: 4),
                        Expanded(
                            child: Text(p?.name ?? '—',
                                style: const TextStyle(fontSize: 11))),
                        Text(
                            '${e.value.length} ${s.isAr ? "موظفون" : "emps"}',
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.warning,
                                fontWeight: FontWeight.w800)),
                      ]),
                    );
                  }),
                ],
              ],
            ),
          ),
        const SizedBox(height: 14),

        // Hourly heatmap
        SectionCard(
          title: s.isAr
              ? 'توزيع الموظفين في كل ساعة (24×7)'
              : 'Employees per Hour (24×7)',
          child: _Heatmap(hourly: hourly),
        ),
        const SizedBox(height: 14),

        // 🆕 تقرير الموظف × اليوم: الموقع + الساعات
        SectionCard(
          title: s.isAr
              ? '📋 تفصيل يومي: الموظف، الموقع، الساعات'
              : '📋 Daily Breakdown: Employee, Location, Hours',
          child: _DailyEmployeeReport(
            shifts: shifts,
            weekStart: weekStart,
          ),
        ),
        const SizedBox(height: 14),

        // Per employee
        SectionCard(
          title: s.isAr ? 'ساعات الموظفين' : 'Hours per Employee',
          child: Column(
            children: empSorted.take(15).map((e) {
              final emp = repo.employeeById(e.key);
              final maxH = empSorted.first.value;
              final pts = empPoints[e.key]?.length ?? 1;
              return _BarRow(
                label: emp?.fullName ?? '—',
                code: emp?.code ?? '',
                value: e.value,
                max: maxH,
                color: AppColors.brand,
                extra: pts > 1
                    ? '$pts ${s.isAr ? "نقاط" : "points"}'
                    : null,
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 14),

        // Per point
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
                extra:
                    '${pointEmps[e.key]?.length ?? 0} ${s.isAr ? "موظفون" : "emps"}',
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  void _exportCsv(BuildContext context, List<_AggShift> shifts,
      MockRepository repo) {
    final s = AppStrings.of(context);
    final lines = <String>[
      'Employee,Code,Day,Start,End,Hours,Point,PointCode,Status',
    ];
    final dayNames = [
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun'
    ];
    for (final sh in shifts) {
      final emp = repo.employeeById(sh.employeeId);
      final p = repo.pointById(sh.pointId);
      lines.add([
        emp?.fullName ?? '',
        emp?.code ?? '',
        dayNames[sh.dayIndex],
        sh.startTime,
        sh.endTime,
        sh.hours.toStringAsFixed(1),
        p?.name ?? '',
        p?.code ?? '',
        sh.rosterStatus.toString().split('.').last,
      ].map((c) => '"$c"').join(','));
    }
    final csv = lines.join('\n');
    Clipboard.setData(ClipboardData(text: csv));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(s.isAr
            ? 'تم نسخ ${shifts.length} صف CSV للحافظة'
            : 'Copied ${shifts.length} CSV rows to clipboard'),
      ),
    );
  }

  Future<void> _exportExcel(BuildContext context, List<_AggShift> shifts,
      MockRepository repo) async {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final dayNames = isAr
        ? ['الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد']
        : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    // ===== Sheet 1: التفاصيل (كلّ وردية في صفّ) =====
    final detailRows = <List<dynamic>>[];
    for (final sh in shifts) {
      final emp = repo.employeeById(sh.employeeId);
      final p = repo.pointById(sh.pointId);
      detailRows.add([
        emp?.fullName ?? '',
        emp?.code ?? '',
        emp?.mobile ?? '',
        dayNames[sh.dayIndex],
        sh.startTime,
        sh.endTime,
        sh.hours,
        p?.name ?? '',
        p?.code ?? '',
        sh.rosterStatus.toString().split('.').last,
      ]);
    }

    // ===== Sheet 2: ساعات الموظّفين =====
    final empHours = <String, double>{};
    final empPoints = <String, Set<String>>{};
    for (final sh in shifts) {
      empHours[sh.employeeId] = (empHours[sh.employeeId] ?? 0) + sh.hours;
      empPoints.putIfAbsent(sh.employeeId, () => {}).add(sh.pointId);
    }
    final empRows = empHours.entries.map((e) {
      final emp = repo.employeeById(e.key);
      return [
        emp?.fullName ?? '',
        emp?.code ?? '',
        emp?.mobile ?? '',
        emp?.jobTitle ?? '',
        e.value,
        empPoints[e.key]?.length ?? 0,
      ];
    }).toList()
      ..sort((a, b) => (b[4] as double).compareTo(a[4] as double));

    // ===== Sheet 3: ساعات النقاط =====
    final pointHours = <String, double>{};
    final pointEmps = <String, Set<String>>{};
    for (final sh in shifts) {
      pointHours[sh.pointId] = (pointHours[sh.pointId] ?? 0) + sh.hours;
      pointEmps.putIfAbsent(sh.pointId, () => {}).add(sh.employeeId);
    }
    final pointRows = pointHours.entries.map((e) {
      final p = repo.pointById(e.key);
      return [
        p?.name ?? '',
        p?.code ?? '',
        e.value,
        pointEmps[e.key]?.length ?? 0,
      ];
    }).toList()
      ..sort((a, b) => (b[2] as double).compareTo(a[2] as double));

    // ===== Sheet 4: الملخّص =====
    final totalHours = shifts.fold<double>(0, (a, sh) => a + sh.hours);
    final empCount = empHours.length;
    final pointCount = pointHours.length;
    final summaryRows = [
      [isAr ? 'إجمالي الساعات' : 'Total Hours', totalHours],
      [isAr ? 'إجمالي الورديات' : 'Total Shifts', shifts.length],
      [isAr ? 'الموظفون' : 'Employees', empCount],
      [isAr ? 'النقاط' : 'Points', pointCount],
      [
        isAr ? 'متوسط/موظف' : 'Avg/Employee',
        empCount == 0 ? 0 : totalHours / empCount
      ],
    ];

    final ok = await ExcelExporter.export(
      fileName:
          'rosters_report_${DateTime.now().millisecondsSinceEpoch}.xlsx',
      sheets: [
        ExcelSheet(
          name: isAr ? 'الملخّص' : 'Summary',
          headers: [isAr ? 'البيان' : 'Metric', isAr ? 'القيمة' : 'Value'],
          rows: summaryRows,
        ),
        ExcelSheet(
          name: isAr ? 'التفاصيل' : 'Details',
          headers: isAr
              ? ['الموظف', 'الكود', 'الجوال', 'اليوم', 'البداية',
                  'النهاية', 'الساعات', 'النقطة', 'كود النقطة', 'الحالة']
              : ['Employee', 'Code', 'Mobile', 'Day', 'Start',
                  'End', 'Hours', 'Point', 'Point Code', 'Status'],
          rows: detailRows,
        ),
        ExcelSheet(
          name: isAr ? 'ساعات الموظفين' : 'Per Employee',
          headers: isAr
              ? ['الموظف', 'الكود', 'الجوال', 'المسمى', 'الساعات', 'عدد النقاط']
              : ['Employee', 'Code', 'Mobile', 'Title', 'Hours', 'Points'],
          rows: empRows,
        ),
        ExcelSheet(
          name: isAr ? 'ساعات النقاط' : 'Per Point',
          headers: isAr
              ? ['النقطة', 'الكود', 'الساعات', 'عدد الموظفين']
              : ['Point', 'Code', 'Hours', 'Employees'],
          rows: pointRows,
        ),
      ],
    );

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: ok ? AppColors.success : AppColors.danger,
      content: Text(ok
          ? (isAr ? '✅ تمّ تصدير Excel' : '✅ Excel exported')
          : (isAr ? '❌ فشل التصدير' : '❌ Export failed')),
    ));
  }

  void _copySummary(BuildContext context, double totalHours, int totalShifts,
      int empCount, int pointCount, double avg) {
    final s = AppStrings.of(context);
    final summary = [
      '📊 ${s.isAr ? "ملخص الجدولة" : "Schedule Summary"}',
      '${s.totalHours}: ${totalHours.toStringAsFixed(0)}',
      '${s.isAr ? "الورديات" : "Shifts"}: $totalShifts',
      '${s.isAr ? "الموظفون" : "Employees"}: $empCount',
      '${s.isAr ? "النقاط" : "Points"}: $pointCount',
      '${s.isAr ? "متوسط/موظف" : "Avg/Employee"}: ${avg.toStringAsFixed(1)}h',
    ].join('\n');
    Clipboard.setData(ClipboardData(text: summary));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text(s.isAr ? 'تم نسخ الملخص' : 'Summary copied')),
    );
  }
}

// ============================================================
// Heatmap widget
// ============================================================
/// 🆕 تقرير تفصيلي: لكلّ موظّف، كم ساعة شَغل في كلّ يوم وفي أيّ نقطة
/// — مرتّب بحسب الموظّف، يُظهر الموقع المختلف بألوان واضحة.
class _DailyEmployeeReport extends StatelessWidget {
  final List<_AggShift> shifts;
  final DateTime weekStart;
  const _DailyEmployeeReport({
    required this.shifts,
    required this.weekStart,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final repo = MockRepository();

    final dayNamesAr = ['الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس',
        'الجمعة', 'السبت', 'الأحد'];
    final dayNamesEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    if (shifts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
            isAr ? 'لا توجد ورديات' : 'No shifts',
            style: TextStyle(color: Colors.grey.shade600)),
      );
    }

    // اجمع: empId → dayIndex → list of shifts (لو شغل بأكثر من نقطة في اليوم)
    final byEmpDay = <String, Map<int, List<_AggShift>>>{};
    for (final sh in shifts) {
      byEmpDay
          .putIfAbsent(sh.employeeId, () => {})
          .putIfAbsent(sh.dayIndex, () => [])
          .add(sh);
    }
    // فرز الموظّفين بالاسم
    final sortedEmpIds = byEmpDay.keys.toList()
      ..sort((a, b) {
        final ea = repo.employeeById(a);
        final eb = repo.employeeById(b);
        return (ea?.fullName ?? '').compareTo(eb?.fullName ?? '');
      });

    return Column(
      children: [
        // === الجدول ===
        for (final empId in sortedEmpIds) ...[
          _EmployeeWeekCard(
            employee: repo.employeeById(empId),
            weekData: byEmpDay[empId]!,
            weekStart: weekStart,
            dayNames: isAr ? dayNamesAr : dayNamesEn,
            isAr: isAr,
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// بطاقة موظّف واحد: تَعرض الأسبوع كاملاً مع الورديات لكلّ يوم
/// والموقع وساعاته.
class _EmployeeWeekCard extends StatelessWidget {
  final Employee? employee;
  final Map<int, List<_AggShift>> weekData;
  final DateTime weekStart;
  final List<String> dayNames;
  final bool isAr;
  const _EmployeeWeekCard({
    required this.employee,
    required this.weekData,
    required this.weekStart,
    required this.dayNames,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    final repo = MockRepository();
    final totalHours = weekData.values
        .expand((list) => list)
        .fold<double>(0, (sum, sh) => sum + sh.hours);
    final pointsCount = weekData.values
        .expand((list) => list)
        .map((sh) => sh.pointId)
        .toSet()
        .length;
    final isCrossPoint = pointsCount > 1;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isCrossPoint
              ? AppColors.warning.withOpacity(0.40)
              : Theme.of(context).dividerColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // === رأس البطاقة: اسم الموظّف + إجمالي الساعات + عدد النقاط ===
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.brand.withOpacity(0.06),
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        employee?.fullName ?? '—',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900),
                      ),
                      Text(
                        '${employee?.code ?? ""} • ${employee?.jobTitle ?? ""}',
                        style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                if (isCrossPoint) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                          color:
                              AppColors.warning.withOpacity(0.40)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.swap_horiz,
                            size: 11, color: AppColors.warning),
                        const SizedBox(width: 3),
                        Text(
                          isAr
                              ? '$pointsCount نقاط'
                              : '$pointsCount points',
                          style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: AppColors.warning),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.brand.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${totalHours.toStringAsFixed(1)}h',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: AppColors.brand),
                  ),
                ),
              ],
            ),
          ),
          // === صفوف الأيّام ===
          for (var d = 0; d < 7; d++)
            _DayRow(
              dayName: dayNames[d],
              dayDate: weekStart.add(Duration(days: d)),
              shifts: weekData[d] ?? const [],
              isAr: isAr,
            ),
        ],
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  final String dayName;
  final DateTime dayDate;
  final List<_AggShift> shifts;
  final bool isAr;
  const _DayRow({
    required this.dayName,
    required this.dayDate,
    required this.shifts,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    final repo = MockRepository();
    final isOff = shifts.isEmpty;
    final dayHours = shifts.fold<double>(0, (sum, sh) => sum + sh.hours);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          // اسم اليوم + التاريخ
          SizedBox(
            width: 80,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dayName,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800)),
                Text('${dayDate.day}/${dayDate.month}',
                    style: TextStyle(
                        fontSize: 9, color: Colors.grey.shade600)),
              ],
            ),
          ),
          // الورديات
          Expanded(
            child: isOff
                ? Text(
                    isAr ? '— إجازة' : '— Off',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                        fontStyle: FontStyle.italic),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final sh in shifts)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 1),
                          child: Row(
                            children: [
                              Icon(
                                sh.shiftType == ShiftType.night
                                    ? Icons.nightlight_round
                                    : Icons.wb_sunny_outlined,
                                size: 12,
                                color: sh.shiftType == ShiftType.night
                                    ? AppColors.info
                                    : AppColors.success,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${sh.startTime}→${sh.endTime}',
                                style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  '📍 ${repo.pointById(sh.pointId)?.name ?? "؟"}',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey.shade700,
                                      fontWeight: FontWeight.w700),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${sh.hours.toStringAsFixed(1)}h',
                                style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.brand),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
          // إجمالي اليوم
          if (!isOff)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.brand.withOpacity(0.10),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${dayHours.toStringAsFixed(1)}h',
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: AppColors.brand),
              ),
            ),
        ],
      ),
    );
  }
}

class _Heatmap extends StatelessWidget {
  final List<List<int>> hourly;
  const _Heatmap({required this.hourly});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final dayLabels = s.isAr
        ? ['ثن', 'ثل', 'أر', 'خم', 'جم', 'سب', 'أح']
        : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

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
          Row(children: [
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
          ]),
          const SizedBox(height: 4),
          ...List.generate(7, (day) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(children: [
                SizedBox(
                  width: 32,
                  child: Text(dayLabels[day],
                      style: const TextStyle(
                          fontSize: 10, fontWeight: FontWeight.w700)),
                ),
                ...List.generate(24, (hour) {
                  final v = hourly[day][hour];
                  final t = maxV == 0 ? 0.0 : (v / maxV).clamp(0.0, 1.0);
                  return Tooltip(
                    message:
                        '${dayLabels[day]} ${hour.toString().padLeft(2, '0')}:00 → $v',
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
                          : Text('$v',
                              style: TextStyle(
                                  color: t > 0.5
                                      ? Colors.white
                                      : AppColors.brand,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800)),
                    ),
                  );
                }),
              ]),
            );
          }),
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
  const _Kpi(
      {required this.label,
      required this.value,
      required this.color,
      required this.icon});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(children: [
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
      ]),
    );
  }
}

class _BarRow extends StatelessWidget {
  final String label;
  final String code;
  final double value;
  final double max;
  final Color color;
  final String? extra;
  const _BarRow(
      {required this.label,
      required this.code,
      required this.value,
      required this.max,
      required this.color,
      this.extra});

  @override
  Widget build(BuildContext context) {
    final t = max == 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
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
            if (extra != null) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(extra!,
                    style: TextStyle(
                        fontSize: 9,
                        color: color,
                        fontWeight: FontWeight.w700)),
              ),
            ],
            const SizedBox(width: 6),
            Text('${value.toStringAsFixed(0)}h',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: color)),
          ]),
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
