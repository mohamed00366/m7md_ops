import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/roster_employee_filter_settings.dart';
import '../../core/services/roster_settings.dart';
import '../../core/services/supabase_data_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../models/models.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/widgets.dart';
import '../supervisor/supervisor_roster_creator.dart';

class OperationRosters extends StatefulWidget {
  const OperationRosters({super.key});

  @override
  State<OperationRosters> createState() => _OperationRostersState();
}

class _OperationRostersState extends State<OperationRosters>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    MockRepository().addListener(_onChange);
  }

  @override
  void dispose() {
    MockRepository().removeListener(_onChange);
    _tabs.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();

    return Scaffold(
      body: Column(
        children: [
          Container(
            color: Theme.of(context).cardTheme.color,
            child: TabBar(
              controller: _tabs,
              isScrollable: true,
              labelColor: AppColors.roleOperation,
              unselectedLabelColor: Theme.of(context).disabledColor,
              indicatorColor: AppColors.roleOperation,
              tabs: [
                Tab(text: s.submitted),
                Tab(text: s.underReview),
                Tab(text: s.approved),
                Tab(text: s.rejected),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: const [
                _RosterList(status: RosterStatus.submitted),
                _RosterList(status: RosterStatus.underReview),
                _RosterList(status: RosterStatus.approved),
                _RosterList(status: RosterStatus.rejected),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RosterList extends StatelessWidget {
  final RosterStatus status;
  const _RosterList({required this.status});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final auth = context.watch<AuthProvider>();
    // فلترة الروسترات بحسب دولة النقطة
    final list = repo.rostersByStatus(status).where((r) {
      final point = repo.pointById(r.siteId);
      return auth.isInScope(point?.countryId);
    }).toList();

    if (list.isEmpty) {
      return EmptyState(
        icon: Icons.fact_check_outlined,
        message: s.isAr ? 'لا توجد روسترات' : 'No rosters',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: list.length,
      itemBuilder: (_, i) => _RosterCard(roster: list[i]),
    );
  }
}

class _RosterCard extends StatelessWidget {
  final WeeklyRoster roster;
  const _RosterCard({required this.roster});

  Color _statusColor() {
    return switch (roster.status) {
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
    final site = repo.siteById(roster.siteId);
    final sup = repo.employeeById(roster.supervisorId);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  site?.displayName ?? '-',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
              StatusBadge(
                label: s.isAr
                    ? roster.status.arabicLabel()
                    : roster.status.englishLabel(),
                color: _statusColor(),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${s.supervisor}: ${sup?.fullName ?? '-'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.calendar_today,
                  size: 12, color: Theme.of(context).disabledColor),
              const SizedBox(width: 4),
              Text(
                '${s.from} ${_fmt(roster.weekStart)}',
                style: const TextStyle(fontSize: 11),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.brand.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${roster.assignments.length} ${s.isAr ? "وردية" : "shifts"}',
                  style: const TextStyle(
                      color: AppColors.brand,
                      fontSize: 11,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          if (roster.rejectionReason != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.danger.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 14, color: AppColors.danger),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${s.rejectionReason}: ${roster.rejectionReason}',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.danger),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => RosterReviewScreen(roster: roster),
            )),
            icon: const Icon(Icons.visibility, size: 16),
            label: Text(s.reviewRoster),
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.day}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class RosterReviewScreen extends StatefulWidget {
  final WeeklyRoster roster;
  const RosterReviewScreen({super.key, required this.roster});

  @override
  State<RosterReviewScreen> createState() => _RosterReviewScreenState();
}

class _RosterReviewScreenState extends State<RosterReviewScreen> {
  late TextEditingController _notesCtrl;
  bool _notesDirty = false;

  @override
  void initState() {
    super.initState();
    _notesCtrl = TextEditingController(text: widget.roster.notes ?? '');
    MockRepository().addListener(_onChange);
    RosterSettings.instance.addListener(_onChange);
    RosterSettings.instance.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    MockRepository().removeListener(_onChange);
    RosterSettings.instance.removeListener(_onChange);
    _notesCtrl.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<bool> _persistAssignments(WeeklyRoster r) async {
    final supaReady = SupabaseService().isReady;
    if (supaReady) {
      final ds = SupabaseDataService();
      final ok = await ds.replaceRosterAssignments(r.id, r.assignments);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(ds.lastError ?? 'Failed to save'),
        ));
      }
      return ok;
    } else {
      MockRepository().updateRoster(r);
      return true;
    }
  }

  Future<void> _saveNotes() async {
    final r = widget.roster;
    final newNotes = _notesCtrl.text.trim();
    final supaReady = SupabaseService().isReady;
    if (supaReady) {
      final ds = SupabaseDataService();
      final ok = await ds.updateRosterNotes(
          r.id, newNotes.isEmpty ? null : newNotes);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(ds.lastError ?? 'Failed'),
        ));
        return;
      }
    } else {
      r.notes = newNotes.isEmpty ? null : newNotes;
      MockRepository().updateRoster(r);
    }
    setState(() => _notesDirty = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).savedSuccess)),
      );
    }
  }

  void _showShiftEditor(Employee emp, int dayIndex, WeeklyRoster r) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RosterShiftEditorSheet(
        employee: emp,
        dayIndex: dayIndex,
        roster: r,
        onPersist: () => _persistAssignments(r),
        onChanged: () => setState(() {}),
      ),
    );
  }

  void _showAddEmployee(WeeklyRoster r) async {
    final repo = MockRepository();
    final used = r.assignments.map((a) => a.employeeId).toSet();
    final point = repo.pointById(r.siteId);
    final pointCountry = point?.countryId;
    // 🆕 طَبِّق نَفس فِلتَر إعدادات روستر الموظَّفين (مِثل شاشة الإنشاء)
    await RosterEmployeeFilterSettings.instance.load();
    final filterSettings = RosterEmployeeFilterSettings.instance;
    final available = repo.employees.where((e) {
      if (used.contains(e.id)) return false;
      // فِلتَر النَشاط (افتِراضيّاً يَستَثني غَير النَشطين)
      if (filterSettings.onlyActive && e.status != EntityStatus.active) {
        return false;
      }
      // فِلتَر الدَولة — مُوظَّفو دَولة النُقطة فَقَط
      if (pointCountry != null && e.countryId != pointCountry) return false;
      // 🆕 فِلتَر المُسَمَّيات الوَظيفيّة المَسموحة
      if (!filterSettings.isJobTitleAllowed(e.jobTitleId)) return false;
      return true;
    }).toList();

    if (!mounted) return;
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.of(context).isAr
              ? 'لا يوجد موظفون متاحون'
              : 'No employees available'),
        ),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RosterAddEmployeeSheet(
        available: available,
        weekStart: r.weekStart,
        excludeRosterId: r.id,
        onAdd: (emp) async {
          final repo = MockRepository();
          r.assignments.add(RosterAssignment(
            id: repo.generateId(),
            employeeId: emp.id,
            dayIndex: 0,
            startTime: '08:00',
            endTime: '20:00',
            shiftType: ShiftType.morning,
          ));
          await _persistAssignments(r);
          if (!mounted) return;
          setState(() {});
        },
      ),
    );
  }

  void _removeEmployee(String empId, WeeklyRoster r) {
    final s = AppStrings.of(context);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(s.confirm),
        content: Text(s.isAr
            ? 'حذف هذا الموظف من الروستر؟'
            : 'Remove this employee?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(s.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () async {
              r.assignments.removeWhere((a) => a.employeeId == empId);
              await _persistAssignments(r);
              if (!mounted) return;
              setState(() {});
              Navigator.of(context).pop();
            },
            child: Text(s.delete),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final r = widget.roster;
    final point = repo.pointById(r.siteId);

    // الموظفون = موظفو الـ assignments الحاليين
    final empIds = r.assignments.map((a) => a.employeeId).toSet();
    final allEmployees = empIds
        .map((id) => repo.employeeById(id))
        .whereType<Employee>()
        .toList();

    // المراجعة = الحالة submitted أو underReview (يمكن التعديل + الاعتماد)
    final canReview = r.status == RosterStatus.submitted ||
        r.status == RosterStatus.underReview;
    // submitted فقط: زرّ "ابدأ المراجعة" يوضّح بدء العمل قبل التعديل
    final canStartReview = r.status == RosterStatus.submitted;
    // approved + من لديه صلاحية الاعتماد + الإعداد مفعّل: يمكن "فتح للتعديل"
    final auth = context.read<AuthProvider>();
    final canReopen = r.status == RosterStatus.approved &&
        RosterSettings.instance.allowReopen &&
        (auth.isSuperAdmin || auth.permissions.contains(P.rostersApprove));

    return Scaffold(
      appBar: AppBar(
        title: Text(s.reviewRoster),
        actions: [
          if (r.events.isNotEmpty)
            IconButton(
              icon: Stack(children: [
                const Icon(Icons.history),
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.brand,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    constraints:
                        const BoxConstraints(minWidth: 14, minHeight: 14),
                    child: Text(
                      '${r.events.length}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ]),
              tooltip: s.isAr ? 'سجل التغييرات' : 'Audit log',
              onPressed: () => _showAuditLog(context, r),
            ),
        ],
      ),
      body: Column(
        children: [
          // ===== Header =====
          Container(
            color: Theme.of(context).cardTheme.color,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.place,
                        color: AppColors.warning, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        point?.name ?? '-',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800),
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
                const SizedBox(height: 4),
                Text(
                  '${_fmt(r.weekStart)} - ${_fmt(r.weekStart.add(const Duration(days: 6)))}',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _MiniStat(
                      label: s.totalHours,
                      value: r.totalHours.toStringAsFixed(0),
                      color: AppColors.brand,
                    ),
                    const SizedBox(width: 6),
                    _MiniStat(
                      label: s.isAr ? 'الورديات' : 'Shifts',
                      value: '${r.assignments.length}',
                      color: AppColors.success,
                    ),
                    const SizedBox(width: 6),
                    _MiniStat(
                      label: s.isAr ? 'الموظفون' : 'Employees',
                      value: '${allEmployees.length}',
                      color: AppColors.info,
                    ),
                  ],
                ),
                // 🆕 زِرّ "إضافة موظَّف" بارِز في الأَعلى — يَظهَر فَقَط إذا كان قابِلاً لِلتَعديل
                if (canReview) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _showAddEmployee(r),
                      icon: const Icon(Icons.person_add, size: 18),
                      label: Text(
                        s.isAr
                            ? '➕ إضافة موظَّف لِلروستر'
                            : '➕ Add Employee to Roster',
                        style: const TextStyle(
                            fontWeight: FontWeight.w900),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.info,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // مفتاح ألوان الورديات
          const RosterShiftLegend(),
          // ===== الجدول =====
          // 🆕 RosterGridTable الآن يدير تمريره بنفسه (الرأس ثابت + body يمرّر)
          // فيحتاج ارتفاع محدود — نضعه مباشرة في Expanded.
          // الإضافات السفليّة (الورديات المعلّمة + تقرير التعارضات + ملاحظات)
          // نقلت لقسم منفصل أسفل الجدول.
          Expanded(
            flex: 3,
            child: RosterGridTable(
              roster: r,
              employees: allEmployees,
              weekStart: r.weekStart,
              readOnly: !canReview,
              onCellTap: (emp, day) => _showShiftEditor(emp, day, r),
              onCellLongPress: !canReview
                  ? null
                  : (emp) => _showFlagReviewerComment(emp, r),
              onAddEmployee: () => _showAddEmployee(r),
              onRemoveEmployee: (emp) => _removeEmployee(emp.id, r),
            ),
          ),
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // ===== الورديات المُعلَّمة =====
                  if (r.flaggedCount > 0) _FlaggedShiftsPanel(roster: r),
                  // ===== تقرير التعارضات =====
                  _ConflictReport(roster: r),
                  // ===== ملاحظات الروستر =====
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardTheme.color,
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.notes,
                                size: 16, color: AppColors.info),
                            const SizedBox(width: 6),
                            Text(
                              s.isAr
                                  ? 'ملاحظات الروستر العامة'
                                  : 'Roster Notes',
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800),
                            ),
                            const Spacer(),
                            if (_notesDirty)
                              TextButton.icon(
                                onPressed: _saveNotes,
                                icon: const Icon(Icons.save, size: 14),
                                label: Text(s.save,
                                    style: const TextStyle(fontSize: 11)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _notesCtrl,
                          maxLines: 3,
                          enabled: canReview,
                          decoration: InputDecoration(
                            hintText: canReview
                                ? (s.isAr
                                    ? 'أضف ملاحظات على الروستر كاملاً (تظهر للمشرف عند الرفض)'
                                    : 'Notes on the entire roster (shown on rejection)')
                                : null,
                            border: const OutlineInputBorder(),
                          ),
                          style: const TextStyle(fontSize: 12),
                          onChanged: (v) {
                            final dirty = v.trim() != (r.notes ?? '').trim();
                            if (dirty != _notesDirty) {
                              setState(() => _notesDirty = dirty);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
              ),
            ),
          ),
          // ===== "فتح للتعديل" (للمعتمد فقط) =====
          if (canReopen)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color,
                border: Border(
                    top: BorderSide(color: Theme.of(context).dividerColor)),
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.warning),
                  onPressed: () => _reopenForEdit(context),
                  icon: const Icon(Icons.lock_open, size: 18),
                  label: Text(s.isAr
                      ? 'فتح للتعديل (يرجع تحت المراجعة)'
                      : 'Reopen for Editing'),
                ),
              ),
            ),
          // ===== أزرار الاعتماد/الرفض =====
          if (canReview)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color,
                border: Border(
                    top: BorderSide(color: Theme.of(context).dividerColor)),
              ),
              child: Column(
                children: [
                  if (canStartReview) ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.info),
                        onPressed: () => _startReview(context),
                        icon: const Icon(Icons.play_arrow, size: 18),
                        label: Text(s.isAr ? 'ابدأ المراجعة' : 'Start Review'),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.danger),
                          onPressed: () => _reject(context),
                          icon: const Icon(Icons.close, size: 16),
                          label: Text(s.reject),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.success),
                          onPressed: () => _approve(context),
                          icon: const Icon(Icons.check, size: 16),
                          label: Text(s.approve),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Color _statusColor(RosterStatus s) {
    return switch (s) {
      RosterStatus.draft => AppColors.textTertiaryLight,
      RosterStatus.submitted => AppColors.warning,
      RosterStatus.underReview => AppColors.info,
      RosterStatus.approved => AppColors.success,
      RosterStatus.rejected => AppColors.danger,
    };
  }

  String _fmt(DateTime d) =>
      '${d.day}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _approve(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final r = widget.roster;
    final supaReady = SupabaseService().isReady;
    // احفظ الملاحظات أولاً إذا تم تعديلها
    if (_notesDirty && supaReady) {
      await SupabaseDataService().updateRosterNotes(
          r.id, _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim());
    } else if (_notesDirty) {
      r.notes = _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();
    }
    if (supaReady) {
      final ds = SupabaseDataService();
      final ok = await ds.updateRosterStatus(
        rosterId: r.id,
        status: RosterStatus.approved,
        reviewedBy: auth.currentUser?.id,
      );
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(ds.lastError ?? 'Failed'),
        ));
        return;
      }
    } else {
      r.status = RosterStatus.approved;
      r.reviewedAt = DateTime.now();
      r.reviewedBy = auth.currentUser?.id;
      r.rejectionReason = null;
      MockRepository().updateRoster(r);
    }
    if (!context.mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _reject(BuildContext context) async {
    final s = AppStrings.of(context);
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(s.rejectionReason),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: InputDecoration(hintText: s.reason),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(s.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(context).pop(ctrl.text),
            child: Text(s.reject),
          ),
        ],
      ),
    );
    if (reason == null || reason.trim().isEmpty) return;
    if (!context.mounted) return;
    final auth = context.read<AuthProvider>();
    final r = widget.roster;
    final supaReady = SupabaseService().isReady;
    // احفظ ملاحظات الروستر العامة قبل تحديث الحالة (إذا تم تعديلها)
    if (_notesDirty && supaReady) {
      await SupabaseDataService().updateRosterNotes(
          r.id, _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim());
    } else if (_notesDirty) {
      r.notes = _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();
    }
    if (supaReady) {
      final ds = SupabaseDataService();
      final ok = await ds.updateRosterStatus(
        rosterId: r.id,
        status: RosterStatus.rejected,
        reviewedBy: auth.currentUser?.id,
        rejectionReason: reason.trim(),
      );
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(ds.lastError ?? 'Failed'),
        ));
        return;
      }
    } else {
      r.status = RosterStatus.rejected;
      r.reviewedAt = DateTime.now();
      r.reviewedBy = auth.currentUser?.id;
      r.rejectionReason = reason.trim();
      MockRepository().updateRoster(r);
    }
    if (!context.mounted) return;
    Navigator.of(context).pop();
  }

  // ============================================================
  // 🆕 فتح روستر معتمد للتعديل (يرجع underReview + audit)
  // ============================================================
  Future<void> _reopenForEdit(BuildContext context) async {
    final s = AppStrings.of(context);
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(s.isAr ? 'فتح للتعديل' : 'Reopen for Editing'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              s.isAr
                  ? 'سيتم إرجاع الروستر لحالة "تحت المراجعة" حتى يمكن تعديله. يجب إعادة الاعتماد بعد التعديل.'
                  : 'The roster will return to "under review" so it can be edited. You must re-approve afterwards.',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: s.isAr ? 'سبب الفتح (للسجل)' : 'Reason (for log)',
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(s.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning),
            onPressed: () => Navigator.of(context).pop(ctrl.text),
            child: Text(s.isAr ? 'فتح' : 'Reopen'),
          ),
        ],
      ),
    );
    if (reason == null) return; // لُغي
    if (!context.mounted) return;
    final auth = context.read<AuthProvider>();
    final r = widget.roster;
    final supaReady = SupabaseService().isReady;
    if (supaReady) {
      final ds = SupabaseDataService();
      final ok = await ds.updateRosterStatus(
        rosterId: r.id,
        status: RosterStatus.underReview,
        reviewedBy: auth.currentUser?.id,
      );
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(ds.lastError ?? 'Failed'),
        ));
        return;
      }
    } else {
      r.status = RosterStatus.underReview;
      MockRepository().updateRoster(r);
    }
    MockRepository().logRosterEvent(
      r,
      kind: RosterEventKind.reEdited,
      actorId: auth.currentUser?.employeeId ?? auth.currentUser?.id,
      fromValue: 'approved',
      toValue: 'underReview',
      note: reason.trim().isEmpty ? null : reason.trim(),
    );
    if (!context.mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        s.isAr
            ? 'فُتح للتعديل — لا تنسَ إعادة الاعتماد'
            : 'Reopened for editing — remember to re-approve',
      ),
    ));
  }

  // ============================================================
  // 🆕 Start Review: ينقل من submitted إلى underReview
  // ============================================================
  Future<void> _startReview(BuildContext context) async {
    final s = AppStrings.of(context);
    final auth = context.read<AuthProvider>();
    final r = widget.roster;
    final supaReady = SupabaseService().isReady;
    if (supaReady) {
      final ds = SupabaseDataService();
      final ok = await ds.updateRosterStatus(
        rosterId: r.id,
        status: RosterStatus.underReview,
        reviewedBy: auth.currentUser?.id,
      );
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(ds.lastError ?? 'Failed'),
        ));
        return;
      }
    } else {
      r.status = RosterStatus.underReview;
      r.reviewedBy = auth.currentUser?.id;
      MockRepository().updateRoster(r);
    }
    MockRepository().logRosterEvent(
      r,
      kind: RosterEventKind.startedReview,
      actorId: auth.currentUser?.employeeId ?? auth.currentUser?.id,
      fromValue: 'submitted',
      toValue: 'underReview',
    );
    if (!context.mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(s.isAr
          ? 'بدأت المراجعة — يمكنك التعديل الآن'
          : 'Review started — you can edit now'),
    ));
  }

  // ============================================================
  // 🆕 تعليم وردية للمراجع مع تعليق
  // ============================================================
  Future<void> _showFlagReviewerComment(
      Employee emp, WeeklyRoster r) async {
    final s = AppStrings.of(context);
    // اعرض ورديات هذا الموظف لاختيار اليوم
    final empAssignments =
        r.assignments.where((a) => a.employeeId == emp.id).toList()
          ..sort((a, b) => a.dayIndex.compareTo(b.dayIndex));
    if (empAssignments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(s.isAr ? 'لا توجد ورديات لهذا الموظف' : 'No shifts'),
      ));
      return;
    }
    final dayNames = s.isAr
        ? ['الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد']
        : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardTheme.color,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                s.isAr
                    ? 'تعليم ورديات للمراجعة — ${emp.fullName}'
                    : 'Flag shifts — ${emp.fullName}',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              ...empAssignments.map((a) {
                return _ReviewerFlagRow(
                  assignment: a,
                  dayLabel: dayNames[a.dayIndex],
                  onToggle: (flag, comment) async {
                    final auth = context.read<AuthProvider>();
                    final wasFlagged = a.reviewerFlag;
                    a.reviewerFlag = flag;
                    a.reviewerComment = comment;
                    a.reviewerId = auth.currentUser?.employeeId ??
                        auth.currentUser?.id;
                    a.reviewerFlaggedAt =
                        flag ? DateTime.now() : null;
                    final repo = MockRepository();
                    await _persistAssignments(r);
                    repo.logRosterEvent(
                      r,
                      kind: flag
                          ? RosterEventKind.shiftFlagged
                          : RosterEventKind.shiftUnflagged,
                      actorId: auth.currentUser?.employeeId ??
                          auth.currentUser?.id,
                      note: flag ? comment : null,
                      targetAssignmentId: a.id,
                      fromValue: wasFlagged ? 'flagged' : 'clean',
                      toValue: flag ? 'flagged' : 'clean',
                    );
                    if (mounted) setState(() {});
                  },
                );
              }),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(sheetCtx).pop(),
                  child: Text(s.isAr ? 'إغلاق' : 'Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // 🆕 عرض سجلّ التغييرات (Audit Timeline)
  // ============================================================
  void _showAuditLog(BuildContext context, WeeklyRoster r) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardTheme.color,
      builder: (_) => RosterAuditTimeline(roster: r),
    );
  }
}

// ============================================================
// 🆕 صفّ تعليم وردية واحدة (داخل sheet التعليم)
// ============================================================
class _ReviewerFlagRow extends StatefulWidget {
  final RosterAssignment assignment;
  final String dayLabel;
  final Future<void> Function(bool flag, String? comment) onToggle;
  const _ReviewerFlagRow({
    required this.assignment,
    required this.dayLabel,
    required this.onToggle,
  });

  @override
  State<_ReviewerFlagRow> createState() => _ReviewerFlagRowState();
}

class _ReviewerFlagRowState extends State<_ReviewerFlagRow> {
  late TextEditingController _ctrl;
  late bool _flag;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.assignment.reviewerComment ?? '');
    _flag = widget.assignment.reviewerFlag;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final a = widget.assignment;
    final color = _flag ? AppColors.warning : AppColors.textTertiaryLight;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.brand.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(widget.dayLabel,
                    style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.brand,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 6),
              Text(
                '${a.startTime} - ${a.endTime}',
                style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Switch(
                value: _flag,
                onChanged: (v) async {
                  setState(() => _flag = v);
                  await widget.onToggle(
                      v, _ctrl.text.trim().isEmpty ? null : _ctrl.text.trim());
                },
              ),
            ],
          ),
          if (_flag) ...[
            const SizedBox(height: 4),
            TextField(
              controller: _ctrl,
              maxLines: 2,
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                isDense: true,
                hintText: s.isAr
                    ? 'علّق سبب التعليم (اختياري)'
                    : 'Reason / comment (optional)',
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.all(8),
              ),
              onChanged: (v) async {
                await widget.onToggle(
                    true, v.trim().isEmpty ? null : v.trim());
              },
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================
// 🆕 لوحة الورديات المُعلَّمة (تظهر تحت الجدول)
// ============================================================
class _FlaggedShiftsPanel extends StatelessWidget {
  final WeeklyRoster roster;
  const _FlaggedShiftsPanel({required this.roster});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final flagged =
        roster.assignments.where((a) => a.reviewerFlag).toList();
    if (flagged.isEmpty) return const SizedBox.shrink();
    final dayNames = s.isAr
        ? ['الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد']
        : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(0.15),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Row(
              children: [
                const Icon(Icons.flag,
                    color: AppColors.warning, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    s.isAr
                        ? 'ورديات تحتاج تعديل (${flagged.length})'
                        : 'Shifts needing changes (${flagged.length})',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.warning),
                  ),
                ),
              ],
            ),
          ),
          ...flagged.map((a) {
            final emp = repo.employeeById(a.employeeId);
            return Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppAvatar(
                      initials: emp?.initials ?? '?',
                      color: AppColors.warning,
                      radius: 14),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text(emp?.fullName ?? '—',
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.brand.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${dayNames[a.dayIndex]} ${a.startTime}-${a.endTime}',
                              style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.brand,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                        ]),
                        if (a.reviewerComment != null &&
                            a.reviewerComment!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(a.reviewerComment!,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.warning.withOpacity(0.9))),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ============================================================
// 🆕 خط زمني لسجلّ تغييرات الروستر (Audit Timeline)
// ============================================================
class RosterAuditTimeline extends StatelessWidget {
  final WeeklyRoster roster;
  const RosterAuditTimeline({super.key, required this.roster});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final events = [...roster.events]..sort((a, b) => b.at.compareTo(a.at));
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (_, controller) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.history,
                        color: AppColors.brand, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      s.isAr ? 'سجلّ التغييرات' : 'Audit Log',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                    const Spacer(),
                    Text(
                      s.isAr ? '${events.length} حدث' : '${events.length} events',
                      style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).disabledColor),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              if (events.isEmpty)
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        s.isAr
                            ? 'لا توجد أحداث مسجّلة بعد'
                            : 'No events recorded yet',
                        style: TextStyle(
                            color: Theme.of(context).disabledColor),
                      ),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    controller: controller,
                    itemCount: events.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final e = events[i];
                      final actor = e.actorId == null
                          ? null
                          : repo.employeeById(e.actorId!);
                      final actorName = actor?.fullName ??
                          (e.actorId == null ? '—' : 'User');
                      return ListTile(
                        leading: _eventIcon(e.kind),
                        title: Text(
                          _eventLabel(s.isAr, e),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$actorName • ${_fmt(e.at)}',
                              style: const TextStyle(fontSize: 10),
                            ),
                            if (e.note != null && e.note!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: AppColors.info.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    e.note!,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
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
      },
    );
  }

  Widget _eventIcon(RosterEventKind k) {
    switch (k) {
      case RosterEventKind.created:
        return const Icon(Icons.fiber_new, color: AppColors.brand);
      case RosterEventKind.submitted:
        return const Icon(Icons.send, color: AppColors.warning);
      case RosterEventKind.startedReview:
        return const Icon(Icons.play_arrow, color: AppColors.info);
      case RosterEventKind.approved:
        return const Icon(Icons.check_circle, color: AppColors.success);
      case RosterEventKind.rejected:
        return const Icon(Icons.cancel, color: AppColors.danger);
      case RosterEventKind.reEdited:
        return const Icon(Icons.edit_note, color: AppColors.brand);
      case RosterEventKind.shiftEdited:
        return const Icon(Icons.edit_calendar, color: AppColors.info);
      case RosterEventKind.shiftFlagged:
        return const Icon(Icons.flag, color: AppColors.warning);
      case RosterEventKind.shiftUnflagged:
        return const Icon(Icons.outlined_flag, color: AppColors.success);
      case RosterEventKind.noteEdited:
        return const Icon(Icons.notes, color: AppColors.brand);
    }
  }

  String _eventLabel(bool isAr, RosterEvent e) {
    switch (e.kind) {
      case RosterEventKind.created:
        return isAr ? 'تم إنشاء الروستر' : 'Roster created';
      case RosterEventKind.submitted:
        return isAr ? 'أُرسل للمراجعة' : 'Submitted for review';
      case RosterEventKind.startedReview:
        return isAr ? 'بدأت المراجعة' : 'Review started';
      case RosterEventKind.approved:
        return isAr ? 'تم الاعتماد' : 'Approved';
      case RosterEventKind.rejected:
        return isAr ? 'تم الرفض' : 'Rejected';
      case RosterEventKind.reEdited:
        return isAr ? 'أُرجع لمسودة' : 'Returned to draft';
      case RosterEventKind.shiftEdited:
        return isAr ? 'تعديل وردية' : 'Shift edited';
      case RosterEventKind.shiftFlagged:
        return isAr ? 'تعليم وردية للمراجعة' : 'Shift flagged for changes';
      case RosterEventKind.shiftUnflagged:
        return isAr ? 'إزالة علامة وردية' : 'Shift flag removed';
      case RosterEventKind.noteEdited:
        return isAr ? 'تعديل ملاحظات الروستر' : 'Roster notes edited';
    }
  }

  String _fmt(DateTime d) =>
      '${d.day}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MiniStat(
      {required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(value,
                style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.w800)),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    color: color.withOpacity(0.85), fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Stat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: TextStyle(
                    color: color,
                    fontSize: 20,
                    fontWeight: FontWeight.w800)),
            Text(label, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// تقرير التعارضات: يعرض كل assignment فيه تعارض مع روستر آخر
// ============================================================
class _ConflictReport extends StatelessWidget {
  final WeeklyRoster roster;
  const _ConflictReport({required this.roster});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final dayNames = s.isAr
        ? ['الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد']
        : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    final conflicts = <_AssignmentConflict>[];
    for (final a in roster.assignments) {
      if (a.shiftType == ShiftType.off) continue;
      final list = repo.findEmployeeConflicts(
        employeeId: a.employeeId,
        weekStart: roster.weekStart,
        dayIndex: a.dayIndex,
        startTime: a.startTime,
        endTime: a.endTime,
        excludeRosterId: roster.id,
      );
      if (list.isNotEmpty) {
        conflicts.add(_AssignmentConflict(myAssignment: a, others: list));
      }
    }

    if (conflicts.isEmpty) {
      return Container(
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.success.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.success.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle,
                color: AppColors.success, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                s.isAr
                    ? 'لا توجد تعارضات مع روسترات أخرى'
                    : 'No conflicts with other rosters',
                style: const TextStyle(
                    color: AppColors.success,
                    fontSize: 12,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      decoration: BoxDecoration(
        color: AppColors.danger.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: AppColors.danger.withOpacity(0.4), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.danger.withOpacity(0.15),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber,
                    color: AppColors.danger, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    s.isAr
                        ? 'تعارضات الموظفين (${conflicts.length})'
                        : 'Employee Conflicts (${conflicts.length})',
                    style: const TextStyle(
                        color: AppColors.danger,
                        fontSize: 13,
                        fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              s.isAr
                  ? 'هؤلاء الموظفون لديهم ورديات في روسترات أخرى تتقاطع مع هذا الروستر:'
                  : 'These employees have overlapping shifts in other rosters:',
              style: const TextStyle(fontSize: 11, color: AppColors.danger),
            ),
          ),
          ...conflicts.map((c) {
            final emp = repo.employeeById(c.myAssignment.employeeId);
            return Container(
              margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color,
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: AppColors.danger.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AppAvatar(
                          initials: emp?.initials ?? '?',
                          color: AppColors.danger,
                          radius: 14),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          emp?.fullName ?? '—',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w800),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.brand.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          dayNames[c.myAssignment.dayIndex],
                          style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.brand),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(children: [
                    Container(width: 4, height: 24, color: AppColors.brand),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${s.isAr ? "هنا" : "Here"}: '
                        '${c.myAssignment.startTime} - ${c.myAssignment.endTime}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ]),
                  ...c.others.map((conf) {
                    final point = repo.pointById(conf.pointId);
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(children: [
                        Container(
                            width: 4, height: 24, color: AppColors.danger),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${point?.name ?? "?"}: '
                            '${conf.assignment.startTime} - ${conf.assignment.endTime}',
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.danger,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.danger.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            s.isAr
                                ? conf.roster.status.arabicLabel()
                                : conf.roster.status.englishLabel(),
                            style: const TextStyle(
                                fontSize: 9,
                                color: AppColors.danger,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                      ]),
                    );
                  }),
                ],
              ),
            );
          }),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _AssignmentConflict {
  final RosterAssignment myAssignment;
  final List<RosterConflict> others;
  _AssignmentConflict({required this.myAssignment, required this.others});
}
