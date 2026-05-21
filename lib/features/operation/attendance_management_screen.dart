import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/employee_identity.dart';
import '../../shared/m7_app_bar.dart';
import 'attendance_reports_screen.dart';
import 'point_attendance_tab.dart';

/// 📋 شاشة إدارة الحضور (يوم بيوم لكلّ الموظفين)
///
/// المزايا:
///   • شريط تنقّل للأيّام (← أمس | اليوم | غداً →)
///   • عرض كلّ موظّف موجود في الباصات لذلك اليوم
///   • زرّ "حاضر / غائب / متغيّر" لكلّ موظّف بضغطة واحدة
///   • فلترة بالحالة + بالباص
///   • زرّ "التقارير" يفتح شاشة الإحصاءات
class AttendanceManagementScreen extends StatefulWidget {
  const AttendanceManagementScreen({super.key});

  @override
  State<AttendanceManagementScreen> createState() =>
      _AttendanceManagementScreenState();
}

class _AttendanceManagementScreenState
    extends State<AttendanceManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  DateTime _date = DateTime.now();
  String? _busFilter; // null = كلّ الباصات
  BusAttendanceStatus? _statusFilter;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    MockRepository().addListener(_onChange);
  }

  @override
  void dispose() {
    _tab.dispose();
    MockRepository().removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  /// الـ dayIndex: 0 الأحد، 6 السبت — حسب نمط النظام
  int get _dayIndex {
    // Dart: Sunday = 7, Monday = 1, ... Saturday = 6
    final dow = _date.weekday;
    if (dow == DateTime.sunday) return 0;
    return dow; // 1..6
  }

  void _shiftDay(int days) {
    setState(() => _date = _date.add(Duration(days: days)));
  }

  /// 🆕 trips النشطة لذلك اليوم (بدون فلتر بالباص — الفلتر صار على
  /// مستوى الموظّف).
  List<BusPlanDetail> _tripsForDay() {
    final repo = MockRepository();
    return repo.busPlans
        .expand((p) => p.details)
        .where((d) => d.dayIndex == _dayIndex)
        .toList()
      ..sort((a, b) => a.time.compareTo(b.time));
  }

  /// 🆕 كلّ الموظّفين في كلّ trips ذلك اليوم — الباص يُحلّ لكلّ موظّف
  /// على حدة عبر `resolveEmployeeBusId` (override يومي → الباص الافتراضي).
  /// لو لا يوجد باص للموظّف → يظهر بـ "بلا باص".
  List<_EmployeeAttendanceRow> _allRows() {
    final repo = MockRepository();
    final trips = _tripsForDay();
    final week = repo.currentWeekStart();
    final rows = <_EmployeeAttendanceRow>[];
    for (final trip in trips) {
      // dedupe employee ids (لو فيه تكرار من الـ sync القديم)
      for (final empId in trip.employeeIds.toSet()) {
        Employee? emp;
        try {
          emp = repo.employees.firstWhere((e) => e.id == empId);
        } catch (_) {}
        if (emp == null) continue;

        // 🆕 احسب الباص الفعليّ للموظّف لهذا اليوم
        final busId = repo.resolveEmployeeBusId(
          employeeId: empId,
          weekStart: week,
          dayIndex: trip.dayIndex,
        );
        Bus bus;
        if (busId != null && busId.isNotEmpty) {
          try {
            bus = repo.buses.firstWhere((b) => b.id == busId);
          } catch (_) {
            bus = Bus(
                id: busId,
                name: '?',
                plateNumber: '?',
                capacity: 0);
          }
        } else {
          bus = Bus(
              id: '',
              name: '— بلا باص —',
              plateNumber: '',
              capacity: 0);
        }

        // 🆕 فلتر الباص — يطبَّق على الموظّف لا على الـ trip
        if (_busFilter != null && bus.id != _busFilter) continue;

        BusTripAttendance? att;
        try {
          att = repo.busAttendance.firstWhere((a) =>
              a.busPlanDetailId == trip.id && a.employeeId == empId);
        } catch (_) {}

        rows.add(_EmployeeAttendanceRow(
          trip: trip,
          bus: bus,
          employee: emp,
          status: att?.status,
          markedAt: att?.markedAt,
        ));
      }
    }
    return rows;
  }

  List<_EmployeeAttendanceRow> _filtered() {
    var rows = _allRows();
    if (_statusFilter != null) {
      if (_statusFilter == _kUnmarked) {
        rows = rows.where((r) => r.status == null).toList();
      } else {
        rows = rows.where((r) => r.status == _statusFilter).toList();
      }
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      rows = rows
          .where((r) =>
              r.employee.fullName.toLowerCase().contains(q) ||
              r.employee.code.toLowerCase().contains(q))
          .toList();
    }
    return rows;
  }

  /// قيمة وهميّة لتمييز "غير محدّد"
  static const _kUnmarked = BusAttendanceStatus.changed; // placeholder
  // نُميّز بشكل مختلف داخل الفلتر — نستخدم null في الواقع

  void _setStatus(_EmployeeAttendanceRow row, BusAttendanceStatus s) {
    final repo = MockRepository();
    BusTripAttendance? existing;
    try {
      existing = repo.busAttendance.firstWhere((a) =>
          a.busPlanDetailId == row.trip.id &&
          a.employeeId == row.employee.id);
    } catch (_) {}
    if (existing == null) {
      repo.busAttendance.add(BusTripAttendance(
        id: repo.generateId(),
        busPlanDetailId: row.trip.id,
        employeeId: row.employee.id,
        status: s,
        markedAt: DateTime.now(),
      ));
    } else {
      existing.status = s;
      existing.markedAt = DateTime.now();
    }
    repo.notifyListeners();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _pickBus() async {
    final repo = MockRepository();
    final buses = repo.buses;
    final picked = await showModalBottomSheet<String?>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        final isAr = AppStrings.of(ctx).isAr;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(ctx).dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.directions_bus),
                title: Text(isAr ? 'كلّ الباصات' : 'All buses'),
                trailing: _busFilter == null
                    ? const Icon(Icons.check, color: AppColors.success)
                    : null,
                onTap: () => Navigator.pop(ctx, ''),
              ),
              const Divider(),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: buses.length,
                  itemBuilder: (_, i) {
                    final b = buses[i];
                    return ListTile(
                      leading: const Icon(Icons.directions_bus),
                      title: Text(b.name),
                      subtitle: Text(b.plateNumber),
                      trailing: _busFilter == b.id
                          ? const Icon(Icons.check,
                              color: AppColors.success)
                          : null,
                      onTap: () => Navigator.pop(ctx, b.id),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
    if (picked != null) {
      setState(() => _busFilter = picked.isEmpty ? null : picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final rows = _filtered();
    final all = _allRows();

    final present =
        all.where((r) => r.status == BusAttendanceStatus.present).length;
    final missing =
        all.where((r) => r.status == BusAttendanceStatus.missing).length;
    final changed =
        all.where((r) => r.status == BusAttendanceStatus.changed).length;
    final unmarked = all.where((r) => r.status == null).length;

    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? 'إدارة الحضور' : 'Attendance Management',
        subtitle: DateFormat(isAr ? 'EEEE، d MMMM yyyy' : 'EEEE, d MMMM yyyy',
                isAr ? 'ar' : 'en')
            .format(_date),
        actions: [
          M7AppBarAction(
            icon: Icons.bar_chart,
            tooltip: isAr ? 'التقارير' : 'Reports',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const AttendanceReportsScreen(),
            )),
          ),
        ],
      ),
      body: Column(
        children: [
          // ===== شريط التنقّل بين الأيّام =====
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border(
                bottom: BorderSide(
                    color: Theme.of(context).dividerColor, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(isAr
                      ? Icons.chevron_right
                      : Icons.chevron_left),
                  tooltip: isAr ? 'يوم سابق' : 'Previous',
                  onPressed: () => _shiftDay(-1),
                ),
                Expanded(
                  child: InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.brand.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.calendar_today,
                              size: 16, color: AppColors.brand),
                          const SizedBox(width: 8),
                          Text(
                            DateFormat('EEEE  d/M/yyyy',
                                    isAr ? 'ar' : 'en')
                                .format(_date),
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: AppColors.brand),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(isAr
                      ? Icons.chevron_left
                      : Icons.chevron_right),
                  tooltip: isAr ? 'يوم تالٍ' : 'Next',
                  onPressed: () => _shiftDay(1),
                ),
              ],
            ),
          ),

          // ===== 🆕 شَريط التابات: الباصات | النِقاط =====
          Container(
            color: AppColors.brand.withOpacity(0.06),
            child: TabBar(
              controller: _tab,
              labelColor: AppColors.brand,
              unselectedLabelColor: Colors.grey,
              indicatorColor: AppColors.brand,
              labelStyle: const TextStyle(
                  fontWeight: FontWeight.w900, fontSize: 13),
              tabs: [
                Tab(
                  icon: const Icon(Icons.directions_bus),
                  text: isAr ? '🚌 الباصات' : '🚌 Buses',
                ),
                Tab(
                  icon: const Icon(Icons.place),
                  text: isAr ? '📍 النِقاط' : '📍 Points',
                ),
              ],
            ),
          ),

          // ===== مُحتَوى التابات =====
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                // ─────────── تاب 1: الباصات (المُحتَوى الحاليّ) ───────────
                _buildBusTab(context, isAr, present, missing, changed,
                    unmarked, all, rows),
                // ─────────── تاب 2: النِقاط (Point Terminal) ───────────
                PointAttendanceTab(date: _date),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBusTab(
    BuildContext context,
    bool isAr,
    int present,
    int missing,
    int changed,
    int unmarked,
    List<_EmployeeAttendanceRow> all,
    List<_EmployeeAttendanceRow> rows,
  ) {
    return Column(
      children: [
          // ===== KPI ملخّص =====
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: _StatTile(
                    label: isAr ? 'حاضر' : 'Present',
                    count: present,
                    color: AppColors.success,
                    icon: Icons.check_circle,
                    selected: _statusFilter == BusAttendanceStatus.present,
                    onTap: () => setState(() {
                      _statusFilter = _statusFilter ==
                              BusAttendanceStatus.present
                          ? null
                          : BusAttendanceStatus.present;
                    }),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _StatTile(
                    label: isAr ? 'غائب' : 'Absent',
                    count: missing,
                    color: AppColors.danger,
                    icon: Icons.cancel,
                    selected: _statusFilter == BusAttendanceStatus.missing,
                    onTap: () => setState(() {
                      _statusFilter = _statusFilter ==
                              BusAttendanceStatus.missing
                          ? null
                          : BusAttendanceStatus.missing;
                    }),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _StatTile(
                    label: isAr ? 'متغيّر' : 'Variable',
                    count: changed,
                    color: AppColors.warning,
                    icon: Icons.swap_horiz,
                    selected: _statusFilter == BusAttendanceStatus.changed,
                    onTap: () => setState(() {
                      _statusFilter = _statusFilter ==
                              BusAttendanceStatus.changed
                          ? null
                          : BusAttendanceStatus.changed;
                    }),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _StatTile(
                    label: isAr ? 'لم يُحدَّد' : 'Pending',
                    count: unmarked,
                    color: AppColors.textSecondaryLight,
                    icon: Icons.help_outline,
                    selected: false,
                    onTap: () {},
                  ),
                ),
              ],
            ),
          ),

          // ===== شريط بحث + فلتر باص =====
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText:
                          isAr ? 'بحث: اسم أو رقم…' : 'Search name or code…',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  avatar: const Icon(Icons.directions_bus, size: 14),
                  label: Text(
                    _busFilter == null
                        ? (isAr ? 'الباصات' : 'All buses')
                        : _busLabel(_busFilter!),
                    style: const TextStyle(fontSize: 11),
                  ),
                  selected: _busFilter != null,
                  onSelected: (_) => _pickBus(),
                ),
              ],
            ),
          ),

          // ===== القائمة =====
          Expanded(
            child: rows.isEmpty
                ? _EmptyState(isAr: isAr, hasTrips: all.isNotEmpty)
                : ListView.separated(
                    padding:
                        const EdgeInsets.fromLTRB(12, 4, 12, 24),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final row = rows[i];
                      return _AttendanceCard(
                        row: row,
                        isAr: isAr,
                        onMark: (status) => _setStatus(row, status),
                      );
                    },
                  ),
          ),
        ],
      );
  }

  String _busLabel(String id) {
    final repo = MockRepository();
    try {
      return repo.buses.firstWhere((b) => b.id == id).name;
    } catch (_) {
      return id;
    }
  }
}

class _EmployeeAttendanceRow {
  final BusPlanDetail trip;
  final Bus bus;
  final Employee employee;
  final BusAttendanceStatus? status;
  final DateTime? markedAt;
  _EmployeeAttendanceRow({
    required this.trip,
    required this.bus,
    required this.employee,
    this.status,
    this.markedAt,
  });
}

// ============================================================
// 📊 KPI Tile
// ============================================================
class _StatTile extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _StatTile({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? color.withOpacity(0.18)
              : color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? color
                : color.withOpacity(0.25),
            width: selected ? 1.2 : 0.5,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 4),
            Text(count.toString(),
                style: TextStyle(
                    color: color,
                    fontSize: 16,
                    fontWeight: FontWeight.w900)),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: color.withOpacity(0.85),
                    fontSize: 10,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 👤 Attendance Card
// ============================================================
class _AttendanceCard extends StatelessWidget {
  final _EmployeeAttendanceRow row;
  final bool isAr;
  final ValueChanged<BusAttendanceStatus> onMark;
  const _AttendanceCard({
    required this.row,
    required this.isAr,
    required this.onMark,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: Theme.of(context).dividerColor, width: 0.5),
      ),
      child: Column(
        children: [
          // 🆕 هويّة الموظّف الموحّدة (صورة + اسم + كود) + شارة الباص/الوقت
          Row(
            children: [
              Expanded(
                child: EmployeeIdentity(
                  employee: row.employee,
                  size: EmployeeIdentitySize.normal,
                  showCode: true,
                ),
              ),
              const SizedBox(width: 6),
              // شارة الباص + الوقت
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.directions_bus,
                            size: 10,
                            color: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.color),
                        const SizedBox(width: 3),
                        Text(row.bus.name,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.color,
                            )),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.schedule,
                            size: 10,
                            color: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.color),
                        const SizedBox(width: 3),
                        Text(row.trip.time,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.color,
                            )),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _ActionBtn(
                  label: isAr ? 'حاضر' : 'Present',
                  icon: Icons.check_circle,
                  color: AppColors.success,
                  selected:
                      row.status == BusAttendanceStatus.present,
                  onTap: () => onMark(BusAttendanceStatus.present),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _ActionBtn(
                  label: isAr ? 'غائب' : 'Absent',
                  icon: Icons.cancel,
                  color: AppColors.danger,
                  selected:
                      row.status == BusAttendanceStatus.missing,
                  onTap: () => onMark(BusAttendanceStatus.missing),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _ActionBtn(
                  label: isAr ? 'متغيّر' : 'Variable',
                  icon: Icons.swap_horiz,
                  color: AppColors.warning,
                  selected:
                      row.status == BusAttendanceStatus.changed,
                  onTap: () => onMark(BusAttendanceStatus.changed),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color : color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected
                  ? color
                  : color.withOpacity(0.3),
              width: 0.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 14,
                color: selected ? Colors.white : color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: selected ? Colors.white : color,
                    fontSize: 11,
                    fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool isAr;
  final bool hasTrips;
  const _EmptyState({required this.isAr, required this.hasTrips});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              hasTrips
                  ? Icons.filter_alt_off
                  : Icons.event_busy,
              size: 56,
              color: Theme.of(context).disabledColor,
            ),
            const SizedBox(height: 12),
            Text(
              hasTrips
                  ? (isAr
                      ? 'لا توجد نتائج للفلتر الحالي'
                      : 'No results for current filter')
                  : (isAr
                      ? 'لا توجد رحلات في هذا اليوم'
                      : 'No trips for this day'),
              style: TextStyle(
                  color: Theme.of(context).disabledColor,
                  fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
