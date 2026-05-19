import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/supabase_data_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/employee_identity.dart';
import '../../shared/widgets.dart';

/// تخطيط الباصات: تجميع الموظفين من الروستر المعتمد حسب يوم/وقت/موقع
/// ثم تعيين الباصات لكل مجموعة
class CampBossBusPlanning extends StatefulWidget {
  const CampBossBusPlanning({super.key});

  @override
  State<CampBossBusPlanning> createState() => _CampBossBusPlanningState();
}

class _CampBossBusPlanningState extends State<CampBossBusPlanning> {
  late DateTime _weekStart;
  int _dayIndex = DateTime.now().weekday - 1;
  BusPlan? _plan;

  @override
  void initState() {
    super.initState();
    _weekStart = MockRepository().currentWeekStart();
    MockRepository().addListener(_onChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensurePlan());
  }

  @override
  void dispose() {
    MockRepository().removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  /// يجلب أو ينشئ خطة الأسبوع الحالي (يستخدم Supabase إن كانت متوفرة)
  Future<void> _ensurePlan() async {
    final repo = MockRepository();
    final supaReady = SupabaseService().isReady;
    if (supaReady) {
      // ابحث في الكاش أولاً
      final wsKey = _weekStart.toIso8601String().substring(0, 10);
      try {
        final found = repo.busPlans.firstWhere(
          (p) => p.weekStart.toIso8601String().substring(0, 10) == wsKey,
        );
        setState(() => _plan = found);
        return;
      } catch (_) {}
      // أنشئ في Supabase
      final created =
          await SupabaseDataService().createBusPlan(_weekStart);
      if (created != null && mounted) setState(() => _plan = created);
    } else {
      setState(() => _plan = repo.getOrCreateBusPlan(_weekStart));
    }
  }

  /// يجمع الورديات من كل الروسترات المعتمدة لهذا الأسبوع/اليوم حسب (الموقع، وقت البدء)
  Map<String, List<RosterAssignment>> _groupedAssignments() {
    final repo = MockRepository();
    final approved = repo.rosters.where((r) =>
        r.status == RosterStatus.approved &&
        r.weekStart.isAtSameMomentAs(_weekStart));

    final groups = <String, List<RosterAssignment>>{};
    for (final r in approved) {
      for (final a
          in r.assignments.where((a) => a.dayIndex == _dayIndex && a.shiftType != ShiftType.off)) {
        final key = '${r.siteId}|${a.startTime}';
        groups.putIfAbsent(key, () => []).add(a);
      }
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final groups = _groupedAssignments();
    final repo = MockRepository();
    // ملاحظة: لم نعد بحاجة إلى _plan لأنّ الإسناد الآن على مستوى الموظّف
    // (employees.default_bus_id + employee_bus_assignments). نُبقي _ensurePlan
    // لتوافق Supabase فقط، لكنّ شاشة العرض تعتمد كلّياً على resolveEmployeeBusId.

    final dayNames = s.isAr
        ? ['الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد']
        : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return Scaffold(
      body: Column(
        children: [
          Container(
            color: Theme.of(context).cardTheme.color,
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Text(s.busPlanning,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  '${_weekStart.day}/${_weekStart.month}/${_weekStart.year}',
                  style: const TextStyle(fontSize: 11),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: List.generate(7, (i) {
                      final d = _weekStart.add(Duration(days: i));
                      final selected = i == _dayIndex;
                      return Padding(
                        padding: const EdgeInsetsDirectional.only(end: 6),
                        child: GestureDetector(
                          onTap: () => setState(() => _dayIndex = i),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppColors.roleCampBoss
                                  : AppColors.surface2Light,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Column(
                              children: [
                                Text(dayNames[i],
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: selected
                                          ? Colors.white70
                                          : Theme.of(context).disabledColor,
                                    )),
                                Text('${d.day}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: selected ? Colors.white : null,
                                    )),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: groups.isEmpty
                ? EmptyState(
                    icon: Icons.directions_bus_filled,
                    message: s.isAr
                        ? 'لا توجد ورديات مُوافق عليها لهذا اليوم'
                        : 'No approved shifts for this day',
                  )
                : ListView(
                    padding: const EdgeInsets.all(12),
                    children: groups.entries.map((entry) {
                      final parts = entry.key.split('|');
                      final site = repo.siteById(parts[0]);
                      final time = parts[1];
                      // 🆕 dedupe — لو الموظّف عنده أكثر من assignment
                      // بنفس النقطة/الوقت، لا نكرّره.
                      final empIds = entry.value
                          .map((a) => a.employeeId)
                          .toSet()
                          .toList();

                      // 🆕 احسب الباصات المُسندة لكل موظف (override يومي → الافتراضي)
                      // ثم اعرض ملخّص: كم موظف لديه باص، كم بدون باص.
                      final assignments = <String, String?>{}; // empId → busId?
                      for (final id in empIds) {
                        assignments[id] = repo.resolveEmployeeBusId(
                          employeeId: id,
                          weekStart: _weekStart,
                          dayIndex: _dayIndex,
                        );
                      }
                      final assignedCount =
                          assignments.values.where((v) => v != null && v.isNotEmpty).length;
                      final unassignedCount = empIds.length - assignedCount;
                      // عدد الباصات المختلفة المستخدمة في هذه المجموعة
                      final usedBuses = assignments.values
                          .where((v) => v != null && v.isNotEmpty)
                          .toSet();

                      // 🆕 احصل على قائمة الموظّفين كأشخاص (للعرض المضغوط)
                      final empsForPreview = empIds
                          .map((id) => repo.employeeById(id))
                          .whereType<Employee>()
                          .toList();
                      return _PointGroupCard(
                        time: time,
                        siteName: site?.displayName ?? '-',
                        employees: empsForPreview,
                        assignedCount: assignedCount,
                        unassignedCount: unassignedCount,
                        usedBusesCount: usedBuses.length,
                        isAr: s.isAr,
                        onTap: () => _openPointEmployeesSheet(
                          time: time,
                          siteName: site?.displayName ?? '-',
                          employees: empsForPreview,
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  /// 🆕 يفتح Bottom Sheet يعرض كلّ موظّفي النقطة بصورهم + إسناد الباص لكلّ
  /// موظّف على حدة. هذا هو "اضغط على النقطة → اظهر الموظّفين بصورهم".
  void _openPointEmployeesSheet({
    required String time,
    required String siteName,
    required List<Employee> employees,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetCtx) => _PointEmployeesSheet(
        time: time,
        siteName: siteName,
        employees: employees,
        weekStart: _weekStart,
        dayIndex: _dayIndex,
        onAssignEmployee: _assignBusForEmployee,
        onClearEmployee: _clearBusForEmployee,
      ),
    );
  }

  /// 🆕 إسناد باص لموظّف واحد لهذا اليوم.
  /// يفتح حواراً يعرض كلّ الباصات النشطة + يُبيّن الباص الافتراضيّ للموظّف.
  /// النتيجة:
  ///   - إذا اختار الباص الافتراضيّ → احذف override (إن وُجد).
  ///   - إذا اختار باصاً مختلفاً → احفظ كـ override يومي.
  Future<void> _assignBusForEmployee(Employee employee) async {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final theme = Theme.of(context);
    final defaultId = employee.defaultBusId;

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
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
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
                    s.isAr
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
                  // خيار: استخدام الباص الافتراضي (أو "بلا باص" لو ما فيه)
                  ListTile(
                    leading: Icon(Icons.star_outline,
                        color: defaultId != null
                            ? AppColors.warning
                            : Theme.of(context).disabledColor),
                    title: Text(
                      s.isAr
                          ? 'استخدم الافتراضيّ'
                          : 'Use default',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      defaultId != null
                          ? (repo.busById(defaultId)?.name ?? '-')
                          : (s.isAr ? 'لا يوجد افتراضي' : 'No default set'),
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
                          '${b.plateNumber} • ${s.capacity}: ${b.capacity}'),
                      trailing: isDefault
                          ? Text(s.isAr ? 'افتراضي' : 'Default',
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

    // 🆕 Optimistic update + Supabase sync مع رسالة واضحة عند الفشل
    final supaReady = SupabaseService().isReady;
    final ds = SupabaseDataService();
    final isClear = (selected == null || selected == defaultId);

    // 1) تحديث محلّي فوريّ
    repo.setEmployeeBusOverride(
      employeeId: employee.id,
      weekStart: _weekStart,
      dayIndex: _dayIndex,
      busId: isClear ? '' : selected,
    );

    // 2) مزامنة Supabase
    if (supaReady) {
      String? error;
      if (isClear) {
        final ok = await ds.deleteEmployeeBusAssignment(
          employeeId: employee.id,
          weekStart: _weekStart,
          dayIndex: _dayIndex,
        );
        if (!ok) error = ds.lastError;
      } else {
        final saved = await ds.upsertEmployeeBusAssignment(
          employeeId: employee.id,
          weekStart: _weekStart,
          dayIndex: _dayIndex,
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
            s.isAr
                ? 'حُفظ محلّيّاً فقط — طبّق employee_bus_assignment_migration.sql'
                : 'Saved locally only — apply employee_bus_assignment_migration.sql',
          ),
        ));
      }
    }

    // 3) رسالة نجاح
    if (mounted) {
      final newBusId = repo.resolveEmployeeBusId(
        employeeId: employee.id,
        weekStart: _weekStart,
        dayIndex: _dayIndex,
      );
      final busName = (newBusId != null && newBusId.isNotEmpty)
          ? (repo.busById(newBusId)?.name ?? '-')
          : (s.isAr ? 'بلا باص' : 'No bus');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 2),
        content: Text('${employee.fullName} → $busName'),
      ));
      setState(() {});
    }
  }

  /// 🆕 إزالة الـ override فقط — يعود الموظّف لاستخدام الافتراضي.
  Future<void> _clearBusForEmployee(Employee employee) async {
    final repo = MockRepository();
    // optimistic local update
    repo.setEmployeeBusOverride(
      employeeId: employee.id,
      weekStart: _weekStart,
      dayIndex: _dayIndex,
      busId: '',
    );
    if (SupabaseService().isReady) {
      await SupabaseDataService().deleteEmployeeBusAssignment(
        employeeId: employee.id,
        weekStart: _weekStart,
        dayIndex: _dayIndex,
      );
    }
    if (mounted) setState(() {});
  }
}

// ============================================================
// Widgets
// ============================================================

/// 🆕 بطاقة مضغوطة لمجموعة (نقطة + وقت).
/// تعرض: الوقت + اسم النقطة + شارة عدد الموظّفين + شريط ملخّص الإسناد +
/// أوّل 5 صور للموظّفين (overlapping). الضغط يفتح Sheet للإسناد التفصيلي.
class _PointGroupCard extends StatelessWidget {
  final String time;
  final String siteName;
  final List<Employee> employees;
  final int assignedCount;
  final int unassignedCount;
  final int usedBusesCount;
  final bool isAr;
  final VoidCallback onTap;

  const _PointGroupCard({
    required this.time,
    required this.siteName,
    required this.employees,
    required this.assignedCount,
    required this.unassignedCount,
    required this.usedBusesCount,
    required this.isAr,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color:
                            AppColors.roleCampBoss.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(time,
                          style: const TextStyle(
                              color: AppColors.roleCampBoss,
                              fontWeight: FontWeight.w800,
                              fontSize: 13)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        siteName,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    StatusBadge(
                      label:
                          '${employees.length} ${isAr ? "موظف" : "emps"}',
                      color: AppColors.info,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // ملخّص الإسناد
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _SummaryChip(
                      icon: Icons.check_circle_outline,
                      label:
                          '${isAr ? "مُسند" : "Assigned"}: $assignedCount',
                      color: AppColors.success,
                    ),
                    if (unassignedCount > 0)
                      _SummaryChip(
                        icon: Icons.error_outline,
                        label:
                            '${isAr ? "غير مُسند" : "Unassigned"}: $unassignedCount',
                        color: AppColors.danger,
                      ),
                    _SummaryChip(
                      icon: Icons.directions_bus,
                      label:
                          '${isAr ? "باصات" : "Buses"}: $usedBusesCount',
                      color: AppColors.info,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // 🆕 شريط الصور المتداخلة (preview) + سهم الفتح
                Row(
                  children: [
                    Expanded(
                      child: _OverlappingAvatars(
                        employees: employees,
                        max: 6,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.brand.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: AppColors.brand.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            isAr ? 'إسناد الباص' : 'Assign bus',
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: AppColors.brand),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_forward,
                              size: 14, color: AppColors.brand),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 🆕 شريط صور متداخلة (overlapping circles) لإظهار preview للموظّفين
class _OverlappingAvatars extends StatelessWidget {
  final List<Employee> employees;
  final int max;
  const _OverlappingAvatars({required this.employees, this.max = 6});

  @override
  Widget build(BuildContext context) {
    final visible = employees.take(max).toList();
    final remaining = employees.length - visible.length;
    return SizedBox(
      height: 30,
      child: Stack(
        children: [
          for (var i = 0; i < visible.length; i++)
            Positioned(
              left: (i * 22).toDouble(),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Theme.of(context).cardColor, width: 2),
                ),
                child: EmployeeAvatar(
                  employee: visible[i],
                  radius: 13,
                  color: AppColors.brand,
                ),
              ),
            ),
          if (remaining > 0)
            Positioned(
              left: (visible.length * 22).toDouble(),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.brand.withOpacity(0.15),
                  border: Border.all(
                      color: Theme.of(context).cardColor, width: 2),
                ),
                child: Center(
                  child: Text(
                    '+$remaining',
                    style: const TextStyle(
                      color: AppColors.brand,
                      fontWeight: FontWeight.w800,
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 🆕 Bottom Sheet يعرض موظّفي النقطة + إسناد الباص لكلّ منهم.
/// يستمع لـ MockRepository ويُحدّث نفسه مباشرةً عند تغيير أيّ override
/// كي تظهر التغييرات بدون إغلاق الـ Sheet وفتحه ثانية.
class _PointEmployeesSheet extends StatefulWidget {
  final String time;
  final String siteName;
  final List<Employee> employees;
  final DateTime weekStart;
  final int dayIndex;
  final Future<void> Function(Employee) onAssignEmployee;
  final Future<void> Function(Employee) onClearEmployee;

  const _PointEmployeesSheet({
    required this.time,
    required this.siteName,
    required this.employees,
    required this.weekStart,
    required this.dayIndex,
    required this.onAssignEmployee,
    required this.onClearEmployee,
  });

  @override
  State<_PointEmployeesSheet> createState() =>
      _PointEmployeesSheetState();
}

class _PointEmployeesSheetState extends State<_PointEmployeesSheet> {
  String _query = '';

  @override
  void initState() {
    super.initState();
    MockRepository().addListener(_onRepoChange);
  }

  @override
  void dispose() {
    MockRepository().removeListener(_onRepoChange);
    super.dispose();
  }

  void _onRepoChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final repo = MockRepository();

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
        borderRadius: const BorderRadius.vertical(
            top: Radius.circular(18)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // مقبض السحب
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.dividerColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // الهيدر
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.roleCampBoss.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(widget.time,
                      style: const TextStyle(
                          color: AppColors.roleCampBoss,
                          fontWeight: FontWeight.w800,
                          fontSize: 13)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.siteName,
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
          // البحث
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              decoration: InputDecoration(
                hintText:
                    isAr ? 'بحث بالاسم أو الكود…' : 'Search name/code…',
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          const Divider(height: 1),
          // القائمة
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
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 12, endIndent: 12),
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
                            // 🆕 هويّة الموظّف الموحّدة (صورة + اسم + كود)
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
                            // الباص الحالي
                            Expanded(
                              flex: 3,
                              child: _BusBadge(
                                bus: bus,
                                isOverride: isOverride,
                                isAr: isAr,
                              ),
                            ),
                            const SizedBox(width: 4),
                            // إجراءات
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 18),
                                  visualDensity: VisualDensity.compact,
                                  tooltip:
                                      isAr ? 'تغيير الباص' : 'Change bus',
                                  onPressed: () =>
                                      widget.onAssignEmployee(e),
                                ),
                                if (bus != null && isOverride)
                                  IconButton(
                                    icon: const Icon(Icons.refresh,
                                        size: 18),
                                    visualDensity: VisualDensity.compact,
                                    tooltip: isAr
                                        ? 'العودة للافتراضي'
                                        : 'Reset to default',
                                    color: theme.textTheme.bodySmall?.color,
                                    onPressed: () =>
                                        widget.onClearEmployee(e),
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

/// شارة الباص الحالي للموظّف داخل الـ Sheet
class _BusBadge extends StatelessWidget {
  final Bus? bus;
  final bool isOverride;
  final bool isAr;
  const _BusBadge({
    required this.bus,
    required this.isOverride,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    final hasBus = bus != null;
    final accent = !hasBus
        ? AppColors.danger
        : (isOverride ? AppColors.warning : AppColors.success);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
              hasBus
                  ? Icons.directions_bus
                  : Icons.directions_bus_outlined,
              size: 14,
              color: accent),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              hasBus ? bus!.name : (isAr ? 'بلا باص' : 'No bus'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: accent),
            ),
          ),
          if (hasBus && isOverride) ...[
            const SizedBox(width: 4),
            const Icon(Icons.flash_on, size: 11, color: AppColors.warning),
          ],
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _SummaryChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
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
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

/// 🆕 صفّ يعرض موظّفاً مع الباص المُسند له (override أو الافتراضي)
/// + زرّ لتغيير الباص
class _EmployeeBusRow extends StatelessWidget {
  final Employee employee;
  final Bus? bus;
  final bool isOverride; // هل هو override يومي أم الافتراضي
  final bool isAr;
  final VoidCallback onAssign;
  final VoidCallback? onClear;

  const _EmployeeBusRow({
    required this.employee,
    required this.bus,
    required this.isOverride,
    required this.isAr,
    required this.onAssign,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasBus = bus != null;
    final accent = hasBus
        ? (isOverride ? AppColors.warning : AppColors.success)
        : AppColors.danger;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          // 🆕 هويّة الموظّف الموحّدة: صورة + اسم + كود
          Expanded(
            flex: 3,
            child: EmployeeIdentity(
              employee: employee,
              size: EmployeeIdentitySize.compact,
              showCode: true,
              avatarColor: accent,
            ),
          ),
          const SizedBox(width: 6),
          // الباص الحالي
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Icon(
                    hasBus
                        ? Icons.directions_bus
                        : Icons.directions_bus_outlined,
                    size: 14,
                    color: accent),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    hasBus
                        ? '${bus!.name}${isOverride ? ' •' : ''}'
                        : (isAr ? 'بلا باص' : 'No bus'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: accent),
                  ),
                ),
                if (hasBus && isOverride)
                  Tooltip(
                    message: isAr
                        ? 'تجاوز ليوم محدّد'
                        : 'Daily override',
                    child: const Icon(Icons.flash_on,
                        size: 12, color: AppColors.warning),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          // أزرار الإجراء
          IconButton(
            icon: const Icon(Icons.edit, size: 16),
            tooltip: isAr ? 'تغيير الباص' : 'Change bus',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
                minWidth: 28, minHeight: 28),
            onPressed: onAssign,
          ),
          if (onClear != null && isOverride)
            IconButton(
              icon: const Icon(Icons.refresh, size: 16),
              tooltip: isAr
                  ? 'العودة للافتراضي'
                  : 'Reset to default',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                  minWidth: 28, minHeight: 28),
              onPressed: onClear,
              color: theme.textTheme.bodySmall?.color,
            ),
        ],
      ),
    );
  }
}
