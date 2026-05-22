import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/supabase_data_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/employee_identity.dart';
import 'buses/buses_shared.dart';
import 'camp_palette.dart';

/// 📅 العرض الهرمي للباصات: الساعة → النقطة → الموظفون → الباص
/// تُولّد تلقائياً من الروسترات المعتمدة عبر `syncBusPlanFromApprovedRosters`
class CampBossBusesWeekly extends StatefulWidget {
  const CampBossBusesWeekly({super.key});

  @override
  State<CampBossBusesWeekly> createState() => _CampBossBusesWeeklyState();
}

class _CampBossBusesWeeklyState extends State<CampBossBusesWeekly> {
  late DateTime _weekStart;
  late int _dayIndex;

  @override
  void initState() {
    super.initState();
    _weekStart = MockRepository().currentWeekStart();
    _dayIndex = (DateTime.now().weekday - 1).clamp(0, 6);
    MockRepository().addListener(_onChange);
    // مزامنة من الروسترات المعتمدة عند الفتح
    WidgetsBinding.instance.addPostFrameCallback((_) {
      MockRepository().syncBusPlanFromApprovedRosters(_weekStart);
    });
  }

  @override
  void dispose() {
    MockRepository().removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  void _changeWeek(int delta) {
    setState(() {
      _weekStart = _weekStart.add(Duration(days: 7 * delta));
      MockRepository().syncBusPlanFromApprovedRosters(_weekStart);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final groups = repo.hourGroupsForDay(_weekStart, _dayIndex);

    return Scaffold(
      backgroundColor: CampPalette.bg,
      body: Column(
        children: [
          // ===== ترويسة الأسبوع =====
          _WeekHeader(
            weekStart: _weekStart,
            isAr: s.isAr,
            onPrev: () => _changeWeek(-1),
            onNext: () => _changeWeek(1),
          ),
          // ===== شريط الأيام =====
          _DayStrip(
            selected: _dayIndex,
            onSelect: (i) => setState(() => _dayIndex = i),
            isAr: s.isAr,
          ),
          // ===== العرض الهرمي =====
          Expanded(
            child: groups.isEmpty
                ? _EmptyState(
                    icon: Icons.calendar_today,
                    title: s.isAr
                        ? 'لا توجد ساعات لهذا اليوم'
                        : 'No hours for this day',
                    subtitle: s.isAr
                        ? 'تُولَّد الساعات تلقائياً من الروسترات المعتمدة'
                        : 'Hours are generated from approved rosters',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    itemCount: groups.length,
                    itemBuilder: (_, i) {
                      final time = groups.keys.elementAt(i);
                      final details = groups[time]!;
                      return _HourGroup(
                        hour: time,
                        details: details,
                        weekStart: _weekStart,
                        dayIndex: _dayIndex,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// ترويسة الأسبوع
// ============================================================
class _WeekHeader extends StatelessWidget {
  final DateTime weekStart;
  final bool isAr;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _WeekHeader({
    required this.weekStart,
    required this.isAr,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final end = weekStart.add(const Duration(days: 6));
    fmt(DateTime d) =>
        '${d.day}/${d.month}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: BusesPalette.primary.withValues(alpha: 0.06),
      child: Row(
        children: [
          IconButton(
            onPressed: onPrev,
            icon: const Icon(Icons.chevron_right, color: BusesPalette.primary),
            tooltip: isAr ? 'الأسبوع السابق' : 'Previous week',
          ),
          Expanded(
            child: Center(
              child: Column(
                children: [
                  Text(
                    isAr ? 'الأسبوع' : 'Week',
                    style: const TextStyle(
                        fontSize: 10,
                        color: CampPalette.textSecondary,
                        fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${fmt(weekStart)} - ${fmt(end)}',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: CampPalette.text),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_left, color: BusesPalette.primary),
            tooltip: isAr ? 'الأسبوع التالي' : 'Next week',
          ),
        ],
      ),
    );
  }
}

// ============================================================
// شريط الأيام
// ============================================================
class _DayStrip extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelect;
  final bool isAr;

  const _DayStrip({
    required this.selected,
    required this.onSelect,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    final names = dayNames(isAr);
    return SizedBox(
      height: 56,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        itemCount: 7,
        itemBuilder: (_, i) {
          final isSelected = i == selected;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: InkWell(
              onTap: () => onSelect(i),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 64,
                decoration: BoxDecoration(
                  color: isSelected
                      ? BusesPalette.primary
                      : CampPalette.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: isSelected
                          ? BusesPalette.primary
                          : CampPalette.border),
                ),
                child: Center(
                  child: Text(
                    names[i],
                    style: TextStyle(
                      color: isSelected ? Colors.white : CampPalette.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ============================================================
// 🕐 مجموعة ساعة (نقاط متعدّدة في نفس الساعة)
// ============================================================
class _HourGroup extends StatelessWidget {
  final String hour;
  final List<BusPlanDetail> details;
  final DateTime weekStart;
  final int dayIndex;

  const _HourGroup({
    required this.hour,
    required this.details,
    required this.weekStart,
    required this.dayIndex,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final totalEmps =
        details.fold<int>(0, (a, d) => a + d.employeeIds.length);

    // الباص المعيَّن لهذه الساعة (إن وُجد)
    final assignedBusId = details
        .map((d) => d.busId)
        .firstWhere((id) => id.isNotEmpty, orElse: () => '');
    Bus? assignedBus;
    if (assignedBusId.isNotEmpty) {
      try {
        assignedBus = repo.buses.firstWhere((b) => b.id == assignedBusId);
      } catch (_) {}
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: CampPalette.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BusesPalette.info.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ===== ترويسة الساعة =====
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: BusesPalette.info.withValues(alpha: 0.10),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: BusesPalette.info,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.access_time,
                      color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hour,
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: CampPalette.text),
                      ),
                      Text(
                        '${details.length} ${s.isAr ? "نقطة" : "points"} · $totalEmps ${s.isAr ? "موظف" : "employees"}',
                        style: const TextStyle(
                            fontSize: 11,
                            color: CampPalette.textSecondary,
                            fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                // 🆕 زرّ "تعيين باص" أُزيل بناءً على طلب المستخدم
                // (الإسناد يَتمّ على مستوى الموظّف الفردي بدلاً من الساعة)
                // لو في باص مُسنَد سابقاً بالساعة فقط، أعرضه كشارة قراءة:
                if (assignedBus != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: BusesPalette.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: BusesPalette.success.withValues(alpha: 0.40)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.directions_bus,
                            size: 12, color: BusesPalette.success),
                        const SizedBox(width: 4),
                        Text(
                          assignedBus.name,
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: BusesPalette.success),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          // ===== النقاط =====
          for (final d in details)
            _PointBlock(
              detail: d,
              weekStart: weekStart,
              dayIndex: dayIndex,
            ),
        ],
      ),
    );
  }

  Future<void> _showBusPicker(
    BuildContext context,
    DateTime weekStart,
    int dayIndex,
    String hour,
  ) async {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    // 🆕 الباصات الجاهزة فقط (لها سائق مرتبط على الأقل)
    final activeBuses = repo.buses
        .where((b) => b.status == EntityStatus.active)
        .where((b) =>
            repo.busDriverShifts.any((sh) => sh.busId == b.id))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final picked = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(s.isAr ? 'اختر باص للساعة $hour' : 'Pick bus for $hour'),
        content: SizedBox(
          width: 400,
          child: activeBuses.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(s.isAr
                      ? 'لا توجد باصات جاهزة. اربط سائقاً من تبويب «السائقون» أولاً.'
                      : 'No ready buses. Link a driver from "Drivers" tab first.'),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: activeBuses.length,
                  itemBuilder: (_, i) {
                    final b = activeBuses[i];
                    return ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: BusesPalette.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(Icons.directions_bus,
                            color: BusesPalette.primary),
                      ),
                      title: Text(b.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800)),
                      subtitle: Text(b.shownLabel),
                      trailing: Text('${b.capacity} ${s.isAr ? "مقعد" : "seats"}'),
                      onTap: () => Navigator.pop(context, b.id),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(s.cancel)),
        ],
      ),
    );
    if (picked != null) {
      repo.assignBusToHour(
        weekStart: weekStart,
        dayIndex: dayIndex,
        time: hour,
        busId: picked,
      );
    }
  }
}

// 🆕 _BusAssignmentChip class أُزيلت — لم تَعُد مُستعمَلة بعد حذف زرّ
// "تعيين باص" بناءً على طلب المستخدم. الإسناد الآن يَتمّ على مستوى
// الموظّف الفردي عبر شاشة "السائقون" أو الشاشة الأسبوعيّة بدلاً
// من الإسناد المركّز على الساعة.

// ============================================================
// 📍 نقطة (يحوي الموظفين)
// ============================================================
class _PointBlock extends StatelessWidget {
  final BusPlanDetail detail;
  final DateTime weekStart;
  final int dayIndex;
  const _PointBlock({
    required this.detail,
    required this.weekStart,
    required this.dayIndex,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    Point? point;
    try {
      point = repo.points.firstWhere((p) => p.id == detail.siteId);
    } catch (_) {}

    // 🆕 dedupe — قد تتكرّر نفس employeeId في detail.employeeIds
    // (لو كان الموظّف عنده أكثر من assignment بنفس الوقت/النقطة).
    final uniqueIds = detail.employeeIds.toSet().toList();
    final employees = uniqueIds
        .map((id) {
          try {
            return repo.employees.firstWhere((e) => e.id == id);
          } catch (_) {
            return null;
          }
        })
        .whereType<Employee>()
        .toList();

    // 🆕 احسب من له باص ومن لا (override يومي → الافتراضي)
    final assignedCount = employees.where((e) {
      final id = repo.resolveEmployeeBusId(
        employeeId: e.id,
        weekStart: weekStart,
        dayIndex: dayIndex,
      );
      return id != null && id.isNotEmpty;
    }).length;
    final unassignedCount = employees.length - assignedCount;

    // 🆕 اِجمَع الباصات المُسنَدة (قَد تَكون باصاً واحِداً أَو أَكثَر)
    final busCounts = <String, int>{};
    for (final e in employees) {
      final id = repo.resolveEmployeeBusId(
        employeeId: e.id,
        weekStart: weekStart,
        dayIndex: dayIndex,
      );
      if (id == null || id.isEmpty) continue;
      busCounts.update(id, (v) => v + 1, ifAbsent: () => 1);
    }
    final busHeader = busCounts.entries.map((e) {
      Bus? b;
      try {
        b = repo.buses.firstWhere((x) => x.id == e.key);
      } catch (_) {}
      final name = b?.name ?? '?';
      // إذا كُلّ المُوَظَّفين عَلى نَفس الباص لا نَكتُب العَدَد (يُشَوِّش).
      return busCounts.length == 1
          ? name
          : '$name × ${e.value}';
    }).join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          // 🆕 الضغط يفتح Sheet إسناد الباص لكلّ موظّف
          onTap: employees.isEmpty
              ? null
              : () => _openEmployeesSheet(
                    context,
                    pointName:
                        point?.name ?? (s.isAr ? 'بدون نقطة' : 'No point'),
                    employees: employees,
                  ),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            decoration: BoxDecoration(
              color: BusesPalette.secondary.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: BusesPalette.secondary.withValues(alpha: 0.20)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ===== 🆕 شَريط الباص (في المُقَدِّمة، بِخَطّ كَبير) =====
                // يُعرَض اسم الباص (أَو الباصات) المُسنَدة لِهذه الرَحلة.
                if (busHeader.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    decoration: BoxDecoration(
                      color: BusesPalette.primary.withValues(alpha: 0.12),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(10),
                        topRight: Radius.circular(10),
                      ),
                      border: Border(
                        bottom: BorderSide(
                          color: BusesPalette.primary.withValues(alpha: 0.20),
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: BusesPalette.primary,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(Icons.directions_bus,
                              color: Colors.white, size: 16),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            busHeader,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: BusesPalette.primary,
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (busCounts.length > 1)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: BusesPalette.primary.withValues(alpha: 0.20),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${busCounts.length} ${s.isAr ? "باصات" : "buses"}',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: BusesPalette.primary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                // ===== النقطة + شارة IN/OUT =====
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on,
                          size: 14, color: BusesPalette.secondary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          point?.name ??
                              (s.isAr ? 'بدون نقطة' : 'No point'),
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: BusesPalette.secondary),
                        ),
                      ),
                      // 🆕 شارة الاتِجاه (IN = أَخضَر → النُقطة، OUT = بُرتُقاليّ → الكَمب)
                      Container(
                        margin: const EdgeInsets.only(right: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: (detail.direction == TripDirection.tripIn
                                  ? AppColors.success
                                  : AppColors.warning)
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: detail.direction == TripDirection.tripIn
                                  ? AppColors.success
                                  : AppColors.warning,
                              width: 0.6),
                        ),
                        child: Text(
                          detail.direction == TripDirection.tripIn
                              ? (s.isAr ? '🟢 IN' : '🟢 IN')
                              : (s.isAr ? '🔴 OUT' : '🔴 OUT'),
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              color: detail.direction == TripDirection.tripIn
                                  ? AppColors.success
                                  : AppColors.warning),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color:
                              BusesPalette.secondary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                            '${employees.length} ${s.isAr ? "موظف" : "emp"}',
                            style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                color: BusesPalette.secondary)),
                      ),
                    ],
                  ),
                ),
                // ===== ملخّص الإسناد =====
                if (employees.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color:
                                    AppColors.success.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            '${s.isAr ? "مُسند" : "Assigned"}: $assignedCount',
                            style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: AppColors.success),
                          ),
                        ),
                        if (unassignedCount > 0) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.danger.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                  color:
                                      AppColors.danger.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              '${s.isAr ? "بلا باص" : "No bus"}: $unassignedCount',
                              style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.danger),
                            ),
                          ),
                        ],
                        const Spacer(),
                        Text(
                          s.isAr ? 'اضغط للإسناد →' : 'Tap to assign →',
                          style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: BusesPalette.secondary),
                        ),
                      ],
                    ),
                  ),
                // ===== الموظفون =====
                if (employees.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Center(
                      child: Text(
                        s.isAr ? 'لا يوجد موظفون' : 'No employees',
                        style: const TextStyle(
                            fontSize: 11,
                            color: CampPalette.textTertiary),
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final e in employees)
                          _EmployeeChip(
                            employee: e,
                            weekStart: weekStart,
                            dayIndex: dayIndex,
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openEmployeesSheet(
    BuildContext context, {
    required String pointName,
    required List<Employee> employees,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => _BusAssignSheet(
        pointName: pointName,
        employees: employees,
        weekStart: weekStart,
        dayIndex: dayIndex,
      ),
    );
  }
}

class _EmployeeChip extends StatelessWidget {
  final Employee employee;
  final DateTime weekStart;
  final int dayIndex;
  const _EmployeeChip({
    required this.employee,
    required this.weekStart,
    required this.dayIndex,
  });

  @override
  Widget build(BuildContext context) {
    final repo = MockRepository();
    // 🆕 الباص الحالي: override يومي → الافتراضي
    final busId = repo.resolveEmployeeBusId(
      employeeId: employee.id,
      weekStart: weekStart,
      dayIndex: dayIndex,
    );
    final hasBus = busId != null && busId.isNotEmpty;
    final isOverride = repo.findEmployeeBusOverride(
          employeeId: employee.id,
          weekStart: weekStart,
          dayIndex: dayIndex,
        ) !=
        null;
    final accent = !hasBus
        ? AppColors.danger
        : (isOverride ? AppColors.warning : AppColors.success);

    // 🆕 chip هويّة موحّدة (صورة + اسم) + علامة الباص
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          EmployeeAvatar(employee: employee, radius: 9, color: accent),
          const SizedBox(width: 5),
          Text(
            employee.fullName.split(' ').take(2).join(' '),
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: accent),
          ),
          const SizedBox(width: 3),
          Icon(
            hasBus
                ? (isOverride ? Icons.flash_on : Icons.check_circle)
                : Icons.warning_amber,
            size: 10,
            color: accent,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 🆕 Bottom Sheet لإسناد الباص لكلّ موظّف (تحت النقطة)
// ============================================================
class _BusAssignSheet extends StatefulWidget {
  final String pointName;
  final List<Employee> employees;
  final DateTime weekStart;
  final int dayIndex;
  const _BusAssignSheet({
    required this.pointName,
    required this.employees,
    required this.weekStart,
    required this.dayIndex,
  });

  @override
  State<_BusAssignSheet> createState() => _BusAssignSheetState();
}

class _BusAssignSheetState extends State<_BusAssignSheet> {
  String _query = '';

  @override
  void initState() {
    super.initState();
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

  Future<void> _pickBusFor(Employee employee) async {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final repo = MockRepository();
    final defaultId = employee.defaultBusId;
    final theme = Theme.of(context);

    final selected = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(18)),
        ),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.directions_bus,
                    color: AppColors.success, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isAr
                        ? 'اختر باصاً لـ ${employee.fullName}'
                        : 'Pick a bus for ${employee.fullName}',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  ListTile(
                    leading: Icon(Icons.star_outline,
                        color: defaultId != null
                            ? AppColors.warning
                            : Theme.of(context).disabledColor),
                    title: Text(
                      isAr ? 'استخدم الافتراضيّ' : 'Use default',
                      style:
                          const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      defaultId != null
                          ? (() {
                              try {
                                return repo.buses
                                    .firstWhere((b) => b.id == defaultId)
                                    .name;
                              } catch (_) {
                                return '-';
                              }
                            }())
                          : (isAr ? 'لا يوجد افتراضي' : 'No default set'),
                      style: const TextStyle(fontSize: 11),
                    ),
                    onTap: () => Navigator.of(context).pop(null),
                  ),
                  const Divider(height: 1),
                  ...repo.buses
                      .where((b) => b.status == EntityStatus.active)
                      .map((b) {
                    final isDefault = b.id == defaultId;
                    return ListTile(
                      leading: Icon(Icons.directions_bus,
                          color: isDefault
                              ? AppColors.warning
                              : AppColors.success),
                      title: Text(b.name),
                      subtitle: Text(
                          '${b.plateNumber} • ${isAr ? "السعة" : "Cap"}: ${b.capacity}'),
                      trailing: isDefault
                          ? Text(isAr ? 'افتراضي' : 'Default',
                              style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.warning,
                                  fontWeight: FontWeight.w800))
                          : null,
                      onTap: () => Navigator.of(context).pop(b.id),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;

    // 🆕 Optimistic update — حدّث المحلّي فوراً ليرى المستخدم النتيجة،
    // ثمّ حاول المزامنة مع Supabase. لو فشلت المزامنة (مثلاً
    // الجدول employee_bus_assignments لم يُنشأ بعد) نُبقي التغيير
    // محلّياً ونُعلم المستخدم برسالة.
    final supaReady = SupabaseService().isReady;
    final ds = SupabaseDataService();
    final isClear = (selected == null || selected == defaultId);

    // 1) تحديث المحلّي أوّلاً (فوريّ)
    repo.setEmployeeBusOverride(
      employeeId: employee.id,
      weekStart: widget.weekStart,
      dayIndex: widget.dayIndex,
      busId: isClear ? '' : selected,
    );

    // 2) مزامنة Supabase (خلفيّة)
    if (supaReady) {
      String? error;
      if (isClear) {
        final ok = await ds.deleteEmployeeBusAssignment(
          employeeId: employee.id,
          weekStart: widget.weekStart,
          dayIndex: widget.dayIndex,
        );
        if (!ok) error = ds.lastError;
      } else {
        final saved = await ds.upsertEmployeeBusAssignment(
          employeeId: employee.id,
          weekStart: widget.weekStart,
          dayIndex: widget.dayIndex,
          busId: selected,
        );
        if (saved == null) error = ds.lastError;
      }
      if (!mounted) return;
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.warning,
          duration: const Duration(seconds: 6),
          content: Text(
            isAr
                ? 'حُفظ محلّيّاً فقط — تأكّد من تطبيق migration:\nemployee_bus_assignment_migration.sql\n($error)'
                : 'Saved locally only — please apply migration:\nemployee_bus_assignment_migration.sql\n($error)',
          ),
        ));
        return;
      }
    }

    // 3) رسالة نجاح
    if (mounted) {
      final repoNow = MockRepository();
      final newBusId = repoNow.resolveEmployeeBusId(
        employeeId: employee.id,
        weekStart: widget.weekStart,
        dayIndex: widget.dayIndex,
      );
      final busName = (newBusId != null && newBusId.isNotEmpty)
          ? (repoNow.busById(newBusId)?.name ?? '-')
          : (isAr ? 'بلا باص' : 'No bus');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 2),
        content: Text(
          isAr
              ? '${employee.fullName} → $busName'
              : '${employee.fullName} → $busName',
        ),
      ));
    }
  }

  Future<void> _clearOverrideFor(Employee employee) async {
    // optimistic local update + Supabase sync
    MockRepository().setEmployeeBusOverride(
      employeeId: employee.id,
      weekStart: widget.weekStart,
      dayIndex: widget.dayIndex,
      busId: '',
    );
    if (SupabaseService().isReady) {
      await SupabaseDataService().deleteEmployeeBusAssignment(
        employeeId: employee.id,
        weekStart: widget.weekStart,
        dayIndex: widget.dayIndex,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final repo = MockRepository();
    final theme = Theme.of(context);

    final q = _query.toLowerCase();
    final filtered = q.isEmpty
        ? widget.employees
        : widget.employees
            .where((e) =>
                e.fullName.toLowerCase().contains(q) ||
                e.code.toLowerCase().contains(q))
            .toList();

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(18)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.dividerColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.location_on,
                    color: BusesPalette.secondary, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.pointName,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '${widget.employees.length} ${isAr ? "موظف" : "employees"}',
                        style: TextStyle(
                            fontSize: 11,
                            color: theme.textTheme.bodySmall?.color),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              decoration: InputDecoration(
                hintText:
                    isAr ? 'بحث بالاسم أو الكود…' : 'Search…',
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: filtered.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        isAr ? 'لا توجد نتائج' : 'No results',
                        style: TextStyle(
                            color: theme.textTheme.bodySmall?.color),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(
                        height: 1, indent: 12, endIndent: 12),
                    itemBuilder: (_, i) {
                      final e = filtered[i];
                      final busId = repo.resolveEmployeeBusId(
                        employeeId: e.id,
                        weekStart: widget.weekStart,
                        dayIndex: widget.dayIndex,
                      );
                      final bus = (busId != null && busId.isNotEmpty)
                          ? repo.busById(busId)
                          : null;
                      final isOverride =
                          repo.findEmployeeBusOverride(
                                employeeId: e.id,
                                weekStart: widget.weekStart,
                                dayIndex: widget.dayIndex,
                              ) !=
                              null;
                      final accent = bus == null
                          ? AppColors.danger
                          : (isOverride
                              ? AppColors.warning
                              : AppColors.success);
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: EmployeeIdentity(
                                employee: e,
                                size: EmployeeIdentitySize.normal,
                                showCode: true,
                                avatarColor: accent,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 3,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 6),
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: accent.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      bus != null
                                          ? Icons.directions_bus
                                          : Icons
                                              .directions_bus_outlined,
                                      size: 14,
                                      color: accent,
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        bus != null
                                            ? bus.name
                                            : (isAr ? 'بلا باص' : 'No bus'),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: accent),
                                      ),
                                    ),
                                    if (bus != null && isOverride) ...[
                                      const SizedBox(width: 4),
                                      const Icon(Icons.flash_on,
                                          size: 11,
                                          color: AppColors.warning),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon:
                                      const Icon(Icons.edit, size: 18),
                                  visualDensity: VisualDensity.compact,
                                  tooltip: isAr
                                      ? 'تغيير الباص'
                                      : 'Change bus',
                                  onPressed: () => _pickBusFor(e),
                                ),
                                if (bus != null && isOverride)
                                  IconButton(
                                    icon: const Icon(Icons.refresh,
                                        size: 18),
                                    visualDensity:
                                        VisualDensity.compact,
                                    tooltip: isAr
                                        ? 'العودة للافتراضي'
                                        : 'Reset to default',
                                    color: theme
                                        .textTheme.bodySmall?.color,
                                    onPressed: () =>
                                        _clearOverrideFor(e),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// حالة فارغة
// ============================================================
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;

  const _EmptyState({
    required this.icon,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: CampPalette.input,
                shape: BoxShape.circle,
              ),
              child: Icon(icon,
                  size: 36, color: CampPalette.textTertiary),
            ),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: CampPalette.textSecondary)),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: CampPalette.textTertiary, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}
