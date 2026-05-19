import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:universal_html/html.dart' as html;

import '../../core/l10n/app_strings.dart';
import '../../core/l10n/ar_to_ur_dictionary.dart' as ar2ur;
import '../../core/providers/auth_provider.dart';
import '../../core/services/roster_deadline_settings.dart';
import '../../core/services/roster_employee_filter_settings.dart';
import '../../core/services/roster_settings.dart';
import '../../core/services/supabase_data_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../models/models.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/employee_identity.dart';
import '../../shared/widgets.dart';

/// منشئ الروستر الأسبوعي - تصميم جدولي:
/// - الصفوف: الموظفون (مع زر إضافة)
/// - الأعمدة: أيام الأسبوع (7 أيام) + عمود الإجمالي
/// - كل خلية: نوع الوردية (M/N/Off) + الوقت IN-OUT
/// - أسفل الجدول: صف Active/Day + Daily Hrs + إجمالي الأسبوع
/// - رسم بياني 24 ساعة لكل يوم
class SupervisorRosterCreator extends StatefulWidget {
  const SupervisorRosterCreator({super.key});

  @override
  State<SupervisorRosterCreator> createState() =>
      _SupervisorRosterCreatorState();
}

class _SupervisorRosterCreatorState extends State<SupervisorRosterCreator> {
  late DateTime _weekStart;
  WeeklyRoster? _roster;
  String? _loadedForSiteId; // لتعقب آخر نقطة طلب لها روستر
  bool _loading = false;
  /// 🆕 نقطة يختارها المدير يدوياً عندما لا يكون مرتبطاً بنقطة معيّنة.
  /// تتطلّب صلاحيّة [P.rostersSelectAnyPoint].
  String? _managerSelectedSiteId;

  /// 🆕 وضع تجاوز القفل — يسمح بتعديل/حذف الأيّام السابقة المقفلة.
  /// يتطلّب صلاحيّة [P.rostersEditApproved] (أي صلاحيّة "تعديل المعتمد")
  /// لأنّ التعديل بأثر رجعي على بيانات تاريخيّة.
  bool _overrideLock = false;

  @override
  void initState() {
    super.initState();
    _weekStart = MockRepository().currentWeekStart();
    MockRepository().addListener(_onChange);
    RosterSettings.instance.addListener(_onChange);
    // تحميل إعدادات الروسترات (lock/patterns/alerts) — إن لم تُحمَّل بعد
    RosterSettings.instance.load().then((_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRoster());
  }

  @override
  void dispose() {
    MockRepository().removeListener(_onChange);
    RosterSettings.instance.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _loadRoster() async {
    if (_loading) return;
    final auth = context.read<AuthProvider>();
    final repo = MockRepository();
    final empId = auth.currentUser?.employeeId;
    // 🆕 الأولوية للنقطة التي اختارها المدير، ثم نقطة Operation
    final siteId = _managerSelectedSiteId ??
        _supervisorAssignedSiteId(repo, empId);
    if (siteId == null) return;
    _loading = true;
    _loadedForSiteId = siteId;
    final supervisorId = empId ??
        (repo.employees.isNotEmpty ? repo.employees.first.id : '');
    final supaReady = SupabaseService().isReady;

    if (supaReady) {
      // Look for existing roster in synced cache
      final wsKey = _weekStart.toIso8601String().substring(0, 10);
      final found = repo.rosters.where((r) =>
          r.siteId == siteId &&
          r.weekStart.toIso8601String().substring(0, 10) == wsKey).toList();
      if (found.isNotEmpty) {
        setState(() => _roster = found.first);
        return;
      }
      // Create fresh draft roster in Supabase
      final draft = WeeklyRoster(
        id: '',
        siteId: siteId,
        supervisorId: supervisorId,
        weekStart: _weekStart,
        status: RosterStatus.draft,
        assignments: [],
      );
      final created = await SupabaseDataService().createRoster(draft);
      if (created != null && mounted) {
        setState(() => _roster = created);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(SupabaseDataService().lastError ?? 'Failed to create roster'),
        ));
      }
    } else {
      setState(() {
        _roster = repo.getOrCreateDraftRoster(
          siteId: siteId,
          supervisorId: supervisorId,
          weekStart: _weekStart,
        );
      });
    }
    _loading = false;
  }

  /// يحفظ التعديلات في الذاكرة + Supabase (إن كانت متاحة)
  Future<bool> _persistRoster(WeeklyRoster r) async {
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

  void _changeWeek(int weeks) {
    setState(() {
      _weekStart = _weekStart.add(Duration(days: weeks * 7));
      // 🆕 إجبار إعادة التحميل للأسبوع الجديد — لا تستخدم الـ roster المخزَّن
      // (كان السبب في "تكرار" الموظفين بين الأسابيع: نفس الـ object كان يُعرَض
      // لأسابيع مختلفة لأنّ check الـ build لا يقارن weekStart).
      _roster = null;
      _loading = false; // امسح أيّ حالة تحميل سابقة
    });
    _loadRoster();
  }

  /// النقطة المُسندة للمشرف من قِبل Operation (point_id)
  String? _supervisorAssignedSiteId(MockRepository repo, String? empId) {
    if (empId == null) return null;
    Employee? emp;
    try {
      emp = repo.employees.firstWhere((e) => e.id == empId);
    } catch (_) {
      return null;
    }
    // الأولوية لـ pointId الجديد، ثم siteId القديم (legacy)
    final id = emp.pointId ?? emp.siteId;
    if (id == null || id.isEmpty) return null;
    return id;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final auth = context.watch<AuthProvider>();

    final empId = auth.currentUser?.employeeId;
    final assignedSiteId = _supervisorAssignedSiteId(repo, empId);
    // 🆕 المدير صاحب الصلاحيّة rostersSelectAnyPoint يقدر يختار نقطة بنفسه
    final canSelectAnyPoint =
        auth.hasPermission(P.rostersSelectAnyPoint);

    // 🆕 النقطة الفعليّة = الـ override من المدير (إن وُجد) أو نقطة الـ Operation
    final effectiveSiteId =
        _managerSelectedSiteId ?? assignedSiteId;

    // الحالة 1: المستخدم ليس موظفاً + ليس له صلاحيّة اختيار نقطة
    if (empId == null && !canSelectAnyPoint) {
      return const _NoAssignmentState(reason: NoAssignmentReason.notEmployee);
    }
    // الحالة 2: لا توجد نقطة فعّالة (لا من Operation ولا اختار المدير واحدة)
    if (effectiveSiteId == null) {
      if (canSelectAnyPoint) {
        // 🆕 المدير: شاشة اختيار نقطة بدلاً من رسالة الرفض
        return _ManagerPointPicker(
          onSelected: (id) => setState(() {
            _managerSelectedSiteId = id;
            _loadedForSiteId = null; // أجبر إعادة التحميل للنقطة الجديدة
          }),
        );
      }
      return const _NoAssignmentState(reason: NoAssignmentReason.noPoint);
    }

    // لو الـ build يجري قبل اكتمال التحميل لأول مرة، حمّل الآن
    // 🆕 نتحقّق أيضاً إذا الـ roster المخزَّن لـ أسبوع مختلف عن المعروض
    final loadedWsKey =
        _roster?.weekStart.toIso8601String().substring(0, 10);
    final currentWsKey = _weekStart.toIso8601String().substring(0, 10);
    final weekMismatch =
        _roster != null && loadedWsKey != currentWsKey;
    if (_roster == null ||
        _loadedForSiteId != effectiveSiteId ||
        weekMismatch) {
      if (!_loading) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadRoster();
        });
      }
      return const Center(child: CircularProgressIndicator());
    }
    final r = _roster!;
    final point = repo.pointById(effectiveSiteId);
    final isReadOnly = r.status == RosterStatus.approved ||
        r.status == RosterStatus.submitted;

    // الموظفون المعروضون = أي موظف لديه assignment + الموظفون النشطون في الموقع
    final allEmployees = _employeesInRoster(r, repo);

    return Scaffold(
      body: Column(
        children: [
          // شريط أعلى الشاشة - معلومات النقطة والأسبوع
          _Header(
            point: point,
            weekStart: _weekStart,
            statusLabel: s.isAr
                ? r.status.arabicLabel()
                : r.status.englishLabel(),
            statusColor: _statusColor(r.status),
            onPrev: () => _changeWeek(-1),
            onNext: () => _changeWeek(1),
          ),
          // Status Banner (أهم عنصر - يظهر حالة الروستر بشكل بارز)
          _StatusBanner(
            roster: r,
            onReEdit: () async {
              // إعادة الروستر للتعديل بعد الرفض (يصير Draft)
              final supaReady = SupabaseService().isReady;
              if (supaReady) {
                final ds = SupabaseDataService();
                final ok = await ds.updateRosterStatus(
                  rosterId: r.id,
                  status: RosterStatus.draft,
                  rejectionReason: null,
                );
                if (!ok && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    backgroundColor: Colors.red,
                    content: Text(ds.lastError ?? 'Failed'),
                  ));
                  return;
                }
                r.rejectionReason = null;
              } else {
                r.status = RosterStatus.draft;
                r.rejectionReason = null;
                MockRepository().updateRoster(r);
              }
              if (!mounted) return;
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(s.isAr
                    ? 'تم تحويل الروستر لمسودة - عدّله ثم أعد الإرسال'
                    : 'Reverted to draft - edit then resubmit')),
              );
            },
          ),
          // 🆕 Deadline banner (تنبيه قبل/بعد موعد إنشاء الروستر)
          _DeadlineBanner(weekStart: _weekStart, status: r.status),
          // مفتاح اللون (M=Morning, N=Night, Off)
          const RosterShiftLegend(),
          // ===== شريط الإجراءات السريعة =====
          if (!isReadOnly)
            _QuickActionsBar(
              roster: r,
              weekStart: _weekStart,
              onCopyPreviousWeek: () => _copyFromPreviousWeek(r),
              onBulkAdd: () => _showBulkAddEmployees(r),
              onClearAll: () => _clearAllAssignments(r),
              // 🆕 إرسال للموظّفين عبر WhatsApp
              onSendToAll: () => _showSendToAllDialog(r),
              // 🆕 إنشاء 4 أسابيع قادمة فارغة دفعة واحدة
              onCreate4Weeks: () => _create4WeeksAhead(),
              // 🆕 وضع تجاوز القفل (للأيّام السابقة)
              overrideLock: _overrideLock,
              onToggleOverrideLock: () =>
                  _toggleOverrideLock(auth),
            ),
          // 🆕 الجدول الآن يدير تمريره بنفسه (أفقي + عمودي مع رأس ثابت)
          Expanded(
            child: RosterGridTable(
              roster: r,
              employees: allEmployees,
              weekStart: _weekStart,
              readOnly: isReadOnly,
              overrideLock: _overrideLock,
              onCellTap: (emp, dayIndex) {
                _showShiftEditor(emp, dayIndex, r);
              },
              onCellLongPress: isReadOnly
                  ? null
                  : (emp) => _showRowQuickActions(emp, r),
              onAddEmployee: () => _showAddEmployee(r),
              onRemoveEmployee: (emp) => _removeEmployee(emp.id, r),
            ),
          ),
          if (!isReadOnly)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color,
                border: Border(
                  top: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final ok = await _persistRoster(r);
                        if (ok && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(s.savedSuccess)),
                          );
                        }
                      },
                      icon: const Icon(Icons.save_outlined, size: 16),
                      label: Text(s.saveDraft),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _submitRoster(r),
                      icon: const Icon(Icons.send, size: 16),
                      label: Text(s.submit),
                    ),
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

  /// 🆕 يجمع الموظّفين الذين يَظهرون في صفوف الجدول:
  ///   1) من لديه ورديات سابقة (assignments)
  ///   2) كلّ الموظّفين النشطين المربوطين بنفس النقطة (pointId == siteId)
  ///      حتى لو لم تكن لديهم ورديات بعد — يَظهرون افتراضيّاً في الأعلى.
  /// الترتيب: المربوطون بنقطة هذا الروستر أوّلاً، ثمّ الباقي بالاسم.
  List<Employee> _employeesInRoster(WeeklyRoster r, MockRepository repo) {
    final empIds = r.assignments.map((a) => a.employeeId).toSet();

    // أضف موظّفي النقطة الأم تلقائيّاً
    for (final e in repo.employees) {
      if (e.status != EntityStatus.active) continue;
      if (e.pointId != null && e.pointId == r.siteId) {
        empIds.add(e.id);
      }
    }

    final result = empIds
        .map((id) => repo.employeeById(id))
        .whereType<Employee>()
        .toList();

    // فرز: المربوطون بهذه النقطة أوّلاً (يَظهرون في أعلى الجدول)
    result.sort((a, b) {
      final aLinked = a.pointId == r.siteId ? 0 : 1;
      final bLinked = b.pointId == r.siteId ? 0 : 1;
      if (aLinked != bLinked) return aLinked.compareTo(bLinked);
      return a.fullName.compareTo(b.fullName);
    });
    return result;
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
        onPersist: () => _persistRoster(r),
        onChanged: () => setState(() {}),
        overrideLock: _overrideLock,
      ),
    );
  }

  Future<void> _showAddEmployee(WeeklyRoster r) async {
    final repo = MockRepository();
    final used = r.assignments.map((a) => a.employeeId).toSet();
    // دولة الروستر = دولة النقطة المُسندة
    final point = repo.pointById(r.siteId);
    final pointCountry = point?.countryId;
    // 🆕 فلتر المسمّيات الوظيفيّة المسموحة (إعدادات Settings Hub)
    // ⚠ يَجِب تَحميل الإعدادات قَبل القِراءة، وَإلّا بَعد إعادة تَشغيل التَطبيق
    //   يَكون _loaded=false وَيُرجِع isJobTitleAllowed=true لِلكُلّ.
    await RosterEmployeeFilterSettings.instance.load();
    if (!mounted) return;
    final filterSettings = RosterEmployeeFilterSettings.instance;
    // فلترة الموظفين بدولة النقطة (لا يجوز إضافة موظف من دولة ثانية)
    final available = repo.employees.where((e) {
      if (used.contains(e.id)) return false;
      // 🆕 فلتر النشاط (افتراضيّاً يستثني غير النشطين)
      if (filterSettings.onlyActive && e.status != EntityStatus.active) {
        return false;
      }
      // فلتر الدولة - الموظفون من نفس دولة النقطة فقط
      if (pointCountry != null && e.countryId != pointCountry) return false;
      // 🆕 فلتر المسمّيات الوظيفيّة المسموحة (إن وُجد)
      if (!filterSettings.isJobTitleAllowed(e.jobTitleId)) return false;
      return true;
    }).toList();

    // 🆕 احسب الحالة لكلّ موظّف:
    //   - linked: مربوط بهذه النقطة (pointId == r.siteId) → عادي (لكن أصلاً مُستثنى لو ظهر في الجدول)
    //   - linkedElsewhere: مربوط بنقطة أخرى → برتقالي + اسم النقطة
    //   - inOtherRoster: مدرج في روستر آخر لنفس الأسبوع (مسوّدة/معتمدة) → أحمر + تفاصيل
    final wsKey = r.weekStart.toIso8601String().substring(0, 10);
    final statusMap = <String, RosterAddEmployeeStatus>{};
    for (final e in available) {
      String? linkedPointName;
      if (e.pointId != null && e.pointId != r.siteId) {
        final p = repo.pointById(e.pointId);
        linkedPointName = p?.name;
      }
      // ابحث عن روسترات أخرى لنفس الأسبوع، حالتها draft/approved/submitted
      String? otherRosterPoint;
      DateTime? otherRosterWeek;
      for (final other in repo.rosters) {
        if (other.id == r.id) continue;
        if (other.status == RosterStatus.rejected) continue;
        final otherWsKey =
            other.weekStart.toIso8601String().substring(0, 10);
        if (otherWsKey != wsKey) continue;
        // هل الموظّف لديه وردية فيه؟
        final hasShift = other.assignments.any((a) =>
            a.employeeId == e.id && a.shiftType != ShiftType.off);
        if (hasShift) {
          otherRosterPoint =
              repo.pointById(other.siteId)?.name ?? '?';
          otherRosterWeek = other.weekStart;
          break;
        }
      }
      statusMap[e.id] = RosterAddEmployeeStatus(
        linkedPointName: linkedPointName,
        otherRosterPointName: otherRosterPoint,
        otherRosterWeek: otherRosterWeek,
      );
    }

    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppStrings.of(context).isAr
                ? (pointCountry == null
                    ? 'كل الموظفين مضافون'
                    : 'لا يوجد موظفون متاحون في دولة النقطة')
                : (pointCountry == null
                    ? 'All employees added'
                    : 'No employees available in the point\'s country'))),
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
        statusMap: statusMap,
        onAdd: (emp) async {
          final repo = MockRepository();
          // أضف وردية افتراضية ليوم الإثنين فقط (يمكن تعديلها لاحقاً)
          r.assignments.add(RosterAssignment(
            id: repo.generateId(),
            employeeId: emp.id,
            dayIndex: 0,
            startTime: '08:00',
            endTime: '20:00',
            shiftType: ShiftType.morning,
          ));
          await _persistRoster(r);
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
            : 'Remove this employee from roster?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(s.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () async {
              r.assignments.removeWhere((a) => a.employeeId == empId);
              await _persistRoster(r);
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

  void _submitRoster(WeeklyRoster r) {
    final s = AppStrings.of(context);
    if (r.assignments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(s.isAr
                ? 'لا يمكن إرسال روستر فارغ'
                : 'Cannot submit empty roster')),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(s.confirm),
        content: Text(s.isAr
            ? 'سيتم إرسال الروستر للعمليات. هل تريد المتابعة؟'
            : 'Roster will be sent to Operation. Continue?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(s.cancel)),
          ElevatedButton(
            onPressed: () async {
              final supaReady = SupabaseService().isReady;
              if (supaReady) {
                final ds = SupabaseDataService();
                final ok = await ds.updateRosterStatus(
                  rosterId: r.id,
                  status: RosterStatus.submitted,
                );
                if (!ok && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    backgroundColor: Colors.red,
                    content: Text(ds.lastError ?? 'Failed'),
                  ));
                  return;
                }
              } else {
                r.status = RosterStatus.submitted;
                r.submittedAt = DateTime.now();
                MockRepository().updateRoster(r);
              }
              if (!mounted) return;
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(s.savedSuccess)),
              );
              setState(() {});
            },
            child: Text(s.submit),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ⚡ Quick Actions: Copy / Bulk-add / Per-row templates / Clear
  // ============================================================

  /// نسخ ورديات الأسبوع السابق لنفس النقطة (إن وُجدت)
  Future<void> _copyFromPreviousWeek(WeeklyRoster r) async {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final prevWeek = _weekStart.subtract(const Duration(days: 7));
    final prev = repo.findRoster(r.siteId, prevWeek);
    if (prev == null || prev.assignments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(s.isAr
            ? 'لا يوجد روستر للأسبوع السابق لنفس النقطة'
            : 'No previous-week roster found for this point'),
      ));
      return;
    }
    // تأكيد إذا الجدول الحالي يحتوي ورديات (سنُستبدل)
    if (r.assignments.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(s.confirm),
          content: Text(s.isAr
              ? 'سيتم استبدال ${r.assignments.length} وردية حالية بـ ${prev.assignments.length} وردية من الأسبوع السابق. متابعة؟'
              : 'This will replace ${r.assignments.length} existing shifts with ${prev.assignments.length} from the previous week. Continue?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(s.cancel)),
            ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(s.isAr ? ar2ur.tr('استبدل') : 'Replace')),
          ],
        ),
      );
      if (ok != true) return;
    }
    r.assignments.clear();
    for (final a in prev.assignments) {
      r.assignments.add(RosterAssignment(
        id: repo.generateId(),
        employeeId: a.employeeId,
        dayIndex: a.dayIndex,
        startTime: a.startTime,
        endTime: a.endTime,
        shiftType: a.shiftType,
        notes: a.notes,
      ));
    }
    await _persistRoster(r);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(s.isAr
          ? 'تم نسخ ${prev.assignments.length} وردية من الأسبوع السابق'
          : 'Copied ${prev.assignments.length} shifts from previous week'),
    ));
  }

  /// مسح جميع ورديات الأسبوع الحالي
  Future<void> _clearAllAssignments(WeeklyRoster r) async {
    final s = AppStrings.of(context);
    if (r.assignments.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(s.confirm),
        content: Text(s.isAr
            ? 'حذف جميع ورديات هذا الأسبوع (${r.assignments.length})؟'
            : 'Clear all shifts for this week (${r.assignments.length})?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(s.cancel)),
          ElevatedButton(
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(s.delete)),
        ],
      ),
    );
    if (ok != true) return;
    r.assignments.clear();
    await _persistRoster(r);
    if (!mounted) return;
    setState(() {});
  }

  /// 🆕 يبدّل وضع "تجاوز القفل" — يسمح بتعديل/حذف الأيّام السابقة المقفلة.
  /// يتطلّب صلاحيّة `P.rostersEditApproved` (تعديل بأثر رجعي).
  /// عند التفعيل: تأكيد + تنبيه. عند الإيقاف: مباشرة.
  Future<void> _toggleOverrideLock(AuthProvider auth) async {
    final isAr = AppStrings.of(context).isAr;

    // إذا مفعَّل بالفعل → أغلقه مباشرة
    if (_overrideLock) {
      setState(() => _overrideLock = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 2),
        content: Text(isAr
            ? '🔒 عاد القفل للأيّام السابقة'
            : '🔒 Lock re-enabled for past days'),
      ));
      return;
    }

    // التحقّق من الصلاحيّة قبل التفعيل
    final hasPerm = auth.isSuperAdmin ||
        auth.permissions.contains(P.rostersEditApproved);
    if (!hasPerm) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text(isAr
            ? '⛔ لا تملك صلاحيّة "تعديل المعتمد" — اطلبها من المسؤول'
            : '⛔ You lack the "Edit approved" permission'),
      ));
      return;
    }

    // تأكيد قبل التفعيل
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded,
            color: AppColors.warning, size: 36),
        title: Text(isAr ? ar2ur.tr('تجاوز قفل الأيّام السابقة') : 'Override lock?'),
        content: Text(
          isAr
              ? 'سيُسمح لك بتعديل/حذف الورديات في الأيّام السابقة. هذا تعديل '
                  'بأثر رجعي على بيانات تاريخيّة — استعمله بحذر شديد.\n\n'
                  'الأيّام المستقبليّة لا تتأثّر (دائماً قابلة للتعديل).'
              : 'You will be able to edit/delete shifts on past days. This '
                  'modifies historical data — use with care.\n\n'
                  'Future days are unaffected (always editable).',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(isAr ? ar2ur.tr('إلغاء') : 'Cancel')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.warning,
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(isAr ? ar2ur.tr('فعّل التجاوز') : 'Enable override')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _overrideLock = true);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.warning,
      duration: const Duration(seconds: 4),
      content: Text(isAr
          ? '🔓 تمّ تجاوز القفل — يمكنك الآن تعديل/حذف الأيّام السابقة'
          : '🔓 Lock overridden — past days editable now'),
    ));
  }

  /// 🆕 ينشئ روسترات فارغة (مسوّدة) للأسابيع الـ4 القادمة دفعة واحدة.
  ///
  /// لكلّ أسبوع: يتحقّق إذا في روستر موجود مسبقاً لنفس النقطة + الأسبوع
  /// — إن وُجد لا يُنشئ آخر (يحترم الـ unique constraint).
  /// إن لم يوجد، ينشئ مسوّدة فارغة.
  /// النتيجة: 4 روسترات منفصلة لـ 4 أسابيع، كلّ واحد فارغ مستقلّ.
  Future<void> _create4WeeksAhead() async {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final repo = MockRepository();
    final auth = context.read<AuthProvider>();
    final empId = auth.currentUser?.employeeId;
    final siteId = _managerSelectedSiteId ??
        _supervisorAssignedSiteId(repo, empId);
    if (siteId == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isAr ? ar2ur.tr('📅 إنشاء 4 أسابيع قادمة') : '📅 Create next 4 weeks'),
        content: Text(
          isAr
              ? 'سيتمّ إنشاء 4 روسترات منفصلة (مسوّدات فارغة) للأسابيع الـ4 القادمة لنفس النقطة. كلّ روستر مستقلّ — تستطيع تعبئته لاحقاً.'
              : 'Will create 4 separate empty draft rosters for the next 4 weeks at this point. Each is independent — fill them later.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(isAr ? ar2ur.tr('إلغاء') : 'Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(isAr ? ar2ur.tr('إنشاء') : 'Create')),
        ],
      ),
    );
    if (ok != true) return;

    final supervisorId = empId ??
        (repo.employees.isNotEmpty ? repo.employees.first.id : '');
    final supaReady = SupabaseService().isReady;
    int created = 0;
    int skipped = 0;
    for (int weekOffset = 1; weekOffset <= 4; weekOffset++) {
      final ws = _weekStart.add(Duration(days: weekOffset * 7));
      final wsKey = ws.toIso8601String().substring(0, 10);
      final exists = repo.rosters.any((r) =>
          r.siteId == siteId &&
          r.weekStart.toIso8601String().substring(0, 10) == wsKey);
      if (exists) {
        skipped++;
        continue;
      }
      if (supaReady) {
        final draft = WeeklyRoster(
          id: '',
          siteId: siteId,
          supervisorId: supervisorId,
          weekStart: ws,
          status: RosterStatus.draft,
          assignments: [],
        );
        final res = await SupabaseDataService().createRoster(draft);
        if (res != null) created++;
      } else {
        repo.getOrCreateDraftRoster(
          siteId: siteId,
          supervisorId: supervisorId,
          weekStart: ws,
        );
        created++;
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.success,
      content: Text(
        isAr
            ? '✅ أُنشئت $created روسترات جديدة'
                '${skipped > 0 ? " ($skipped موجودة مسبقاً)" : ""}'
            : '✅ Created $created new rosters'
                '${skipped > 0 ? " ($skipped already existed)" : ""}',
      ),
    ));
  }

  /// 🆕 يفتح حوار "إرسال الروستر لكلّ الموظفين" — كلّ ضغطة تفتح
  /// محادثة WhatsApp مخصّصة لذلك الموظّف برسالة جدوله الأسبوعي.
  Future<void> _showSendToAllDialog(WeeklyRoster r) async {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final repo = MockRepository();
    final point = repo.pointById(r.siteId);
    final pointName = point?.name ?? '';

    // كلّ موظّف له ورديات في الروستر، مع رقم جواله.
    final empIds = r.assignments.map((a) => a.employeeId).toSet();
    final employees = repo.employees
        .where((e) => empIds.contains(e.id))
        .toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));

    if (employees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(isAr
            ? 'لا يوجد موظفون في هذا الروستر بعد'
            : 'No employees in this roster yet'),
      ));
      return;
    }

    String buildMessageFor(Employee emp) {
      // اجمع كلّ ورديات الموظّف في رسالة منظّمة
      final assignments = r.assignments
          .where((a) =>
              a.employeeId == emp.id && a.shiftType != ShiftType.off)
          .toList()
        ..sort((a, b) => a.dayIndex.compareTo(b.dayIndex));
      final dayNamesAr = ['الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس',
          'الجمعة', 'السبت', 'الأحد'];
      final dayNamesEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      final wkStart = r.weekStart;
      final wkEnd = wkStart.add(const Duration(days: 6));
      final headerAr = 'مرحباً ${emp.fullName} 👋\n'
          'جدولك الأسبوعي'
          '${pointName.isNotEmpty ? " — $pointName" : ""}:\n'
          'من ${_fmtShort(wkStart)} إلى ${_fmtShort(wkEnd)}\n\n';
      final headerEn = 'Hi ${emp.fullName} 👋\n'
          'Your weekly schedule'
          '${pointName.isNotEmpty ? " — $pointName" : ""}:\n'
          'From ${_fmtShort(wkStart)} to ${_fmtShort(wkEnd)}\n\n';
      final lines = <String>[];
      if (assignments.isEmpty) {
        lines.add(isAr
            ? 'لا توجد ورديات (إجازة كامل الأسبوع)'
            : 'No shifts (off all week)');
      } else {
        for (final a in assignments) {
          final day = isAr
              ? dayNamesAr[a.dayIndex]
              : dayNamesEn[a.dayIndex];
          final shift = a.shiftType == ShiftType.morning
              ? (isAr ? ar2ur.tr('🌅 صباحي') : '🌅 Morning')
              : a.shiftType == ShiftType.night
                  ? (isAr ? ar2ur.tr('🌙 ليلي') : '🌙 Night')
                  : (isAr ? ar2ur.tr('☀️ مسائي') : '☀️ Evening');
          lines.add(
              '$day  •  $shift  •  ${a.startTime} → ${a.endTime}');
        }
      }
      final footerAr = '\n\nبالتوفيق 💪';
      final footerEn = '\n\nGood luck 💪';
      return (isAr ? headerAr : headerEn) +
          lines.join('\n') +
          (isAr ? footerAr : footerEn);
    }

    void openWhatsApp(Employee emp) {
      final phone = emp.mobile.replaceAll(RegExp(r'[^\d]'), '');
      if (phone.isEmpty) return;
      final msg = Uri.encodeComponent(buildMessageFor(emp));
      html.window.open('https://wa.me/$phone?text=$msg', '_blank');
    }

    void openCall(Employee emp) {
      final phone = emp.mobile.replaceAll(RegExp(r'[^\d+]'), '');
      if (phone.isEmpty) return;
      html.window.open('tel:$phone', '_self');
    }

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardTheme.color,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.75,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.send,
                        color: Color(0xFF25D366), size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isAr
                                ? 'إرسال الروستر للموظّفين'
                                : 'Send roster to employees',
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900),
                          ),
                          Text(
                            isAr
                                ? '${employees.length} موظّف — اضغط الزرّ بجانب اسمه'
                                : '${employees.length} employees — tap their action button',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: employees.length,
                  itemBuilder: (_, i) {
                    final emp = employees[i];
                    final hasPhone = emp.mobile.trim().isNotEmpty;
                    final shiftCount = r.assignments
                        .where((a) =>
                            a.employeeId == emp.id &&
                            a.shiftType != ShiftType.off)
                        .length;
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor:
                            AppColors.brand.withOpacity(0.15),
                        child: Text(
                          emp.initials,
                          style: const TextStyle(
                              color: AppColors.brand,
                              fontSize: 11,
                              fontWeight: FontWeight.w900),
                        ),
                      ),
                      title: Text(emp.fullName,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800)),
                      subtitle: Row(
                        children: [
                          if (hasPhone)
                            Text(emp.mobile,
                                style: const TextStyle(fontSize: 11))
                          else
                            Text(
                                isAr
                                    ? 'لا يوجد جوال'
                                    : 'No phone',
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.red)),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.brand.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                                isAr
                                    ? '$shiftCount وردية'
                                    : '$shiftCount shifts',
                                style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.brand)),
                          ),
                        ],
                      ),
                      trailing: hasPhone
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  iconSize: 18,
                                  icon: const Icon(Icons.call,
                                      color: AppColors.success),
                                  tooltip: isAr ? ar2ur.tr('اتصال') : 'Call',
                                  onPressed: () => openCall(emp),
                                ),
                                IconButton(
                                  iconSize: 18,
                                  icon: const Icon(Icons.chat_bubble,
                                      color: Color(0xFF25D366)),
                                  tooltip: 'WhatsApp',
                                  onPressed: () => openWhatsApp(emp),
                                ),
                              ],
                            )
                          : const Icon(Icons.phone_disabled,
                              size: 18, color: Colors.grey),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtShort(DateTime d) =>
      '${d.day}/${d.month}/${d.year}';

  /// إضافة جماعية لعدة موظفين بنمط افتراضي
  Future<void> _showBulkAddEmployees(WeeklyRoster r) async {
    final repo = MockRepository();
    final used = r.assignments.map((a) => a.employeeId).toSet();
    final point = repo.pointById(r.siteId);
    final pointCountry = point?.countryId;
    // 🆕 فلتر المسمّيات الوظيفيّة المسموحة (إعدادات Settings Hub)
    await RosterEmployeeFilterSettings.instance.load();
    if (!mounted) return;
    final filterSettings = RosterEmployeeFilterSettings.instance;
    final available = repo.employees.where((e) {
      if (used.contains(e.id)) return false;
      if (filterSettings.onlyActive && e.status != EntityStatus.active) {
        return false;
      }
      if (pointCountry != null && e.countryId != pointCountry) return false;
      if (!filterSettings.isJobTitleAllowed(e.jobTitleId)) return false;
      return true;
    }).toList();
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppStrings.of(context).isAr
            ? 'لا يوجد موظفون متاحون'
            : 'No employees available'),
      ));
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RosterBulkAddSheet(
        available: available,
        weekStart: r.weekStart,
        excludeRosterId: r.id,
        onAddBulk: (selected, pattern) async {
          final repo = MockRepository();
          for (final emp in selected) {
            for (var d = 0; d < 7; d++) {
              final shift = pattern.shiftFor(d);
              if (shift == null) continue; // off
              r.assignments.add(RosterAssignment(
                id: repo.generateId(),
                employeeId: emp.id,
                dayIndex: d,
                startTime: shift.start,
                endTime: shift.end,
                shiftType: shift.type,
              ));
            }
          }
          await _persistRoster(r);
          if (!mounted) return;
          setState(() {});
        },
      ),
    );
  }

  /// قائمة سريعة على صف موظف: تطبيق نمط جاهز / مسح أسبوعه
  void _showRowQuickActions(Employee emp, WeeklyRoster r) {
    final s = AppStrings.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardTheme.color,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: EmployeeIdentity(
                employee: emp,
                size: EmployeeIdentitySize.normal,
                showCode: true,
                trailing: Text(
                  s.isAr ? ar2ur.tr('تطبيق نمط') : 'Apply pattern',
                  style: const TextStyle(fontSize: 10),
                ),
              ),
            ),
            const Divider(height: 1),
            // أنماط جاهزة من إعدادات الروسترات (قابلة للتخصيص)
            ...RosterSettings.instance.patterns.map((p) {
              final iconType = _patternIconFor(p);
              return ListTile(
                leading: Icon(iconType.$1, color: iconType.$2, size: 20),
                title: Text(s.isAr ? p.nameAr : p.nameEn),
                subtitle: Text(
                  '${p.shifts.length} ${s.isAr ? ar2ur.tr("يوم عمل") : "working day(s)"}',
                  style: const TextStyle(fontSize: 10),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  _applyPatternToEmployee(emp.id, r, p);
                },
              );
            }),
            if (RosterSettings.instance.patterns.isEmpty)
              ListTile(
                leading: const Icon(Icons.info_outline, size: 18),
                title: Text(s.isAr
                    ? 'لا توجد أنماط — اضبطها من الإعدادات'
                    : 'No patterns — configure in Settings'),
                dense: true,
              ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.delete_outline,
                  color: AppColors.danger, size: 20),
              title: Text(s.isAr ? ar2ur.tr('مسح أسبوع الموظف') : 'Clear employee week'),
              onTap: () {
                Navigator.of(context).pop();
                _clearEmployeeWeek(emp.id, r);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// أيقونة + لون لكلّ نمط بناءً على نوع وردياته الغالب
  (IconData, Color) _patternIconFor(RosterPatternConfig p) {
    if (p.shifts.isEmpty) return (Icons.calendar_view_week, AppColors.brand);
    final allNight =
        p.shifts.every((sh) => sh.type == ShiftType.night);
    if (allNight) return (Icons.nightlight, AppColors.info);
    return (Icons.wb_sunny, AppColors.success);
  }

  Future<void> _applyPatternToEmployee(
      String empId, WeeklyRoster r, RosterPatternConfig pattern) async {
    final repo = MockRepository();
    // إزالة أي ورديات قديمة لهذا الموظف
    r.assignments.removeWhere((a) => a.employeeId == empId);
    for (var d = 0; d < 7; d++) {
      final shift = pattern.shiftFor(d);
      if (shift == null) continue;
      r.assignments.add(RosterAssignment(
        id: repo.generateId(),
        employeeId: empId,
        dayIndex: d,
        startTime: shift.start,
        endTime: shift.end,
        shiftType: shift.type,
      ));
    }
    await _persistRoster(r);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _clearEmployeeWeek(String empId, WeeklyRoster r) async {
    r.assignments.removeWhere((a) => a.employeeId == empId);
    await _persistRoster(r);
    if (!mounted) return;
    setState(() {});
  }
}

// ============================================================
// Quick Actions Bar (Copy / Bulk Add / Clear)
// ============================================================
class _QuickActionsBar extends StatelessWidget {
  final WeeklyRoster roster;
  final DateTime weekStart;
  final VoidCallback onCopyPreviousWeek;
  final VoidCallback onBulkAdd;
  final VoidCallback onClearAll;
  final VoidCallback? onSendToAll;
  final VoidCallback? onCreate4Weeks;
  final bool overrideLock;
  final VoidCallback? onToggleOverrideLock;
  const _QuickActionsBar({
    required this.roster,
    required this.weekStart,
    required this.onCopyPreviousWeek,
    required this.onBulkAdd,
    required this.onClearAll,
    this.onSendToAll,
    this.onCreate4Weeks,
    this.overrideLock = false,
    this.onToggleOverrideLock,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _QABtn(
              icon: Icons.content_copy,
              label: s.isAr ? ar2ur.tr('نسخ الأسبوع السابق') : 'Copy previous week',
              color: AppColors.brand,
              onTap: onCopyPreviousWeek,
            ),
            const SizedBox(width: 6),
            _QABtn(
              icon: Icons.group_add,
              label: s.isAr ? ar2ur.tr('إضافة جماعية') : 'Bulk add',
              color: AppColors.success,
              onTap: onBulkAdd,
            ),
            const SizedBox(width: 6),
            _QABtn(
              icon: Icons.layers_clear,
              label: s.isAr ? ar2ur.tr('مسح الكل') : 'Clear all',
              color: AppColors.danger,
              onTap: onClearAll,
            ),
            if (onSendToAll != null) ...[
              const SizedBox(width: 6),
              _QABtn(
                icon: Icons.send,
                label: s.isAr
                    ? 'إرسال للموظّفين (WA)'
                    : 'Send to employees (WA)',
                color: const Color(0xFF25D366),
                onTap: onSendToAll!,
              ),
            ],
            if (onCreate4Weeks != null) ...[
              const SizedBox(width: 6),
              _QABtn(
                icon: Icons.event_repeat,
                label: s.isAr
                    ? 'إنشاء 4 أسابيع قادمة'
                    : 'Create next 4 weeks',
                color: AppColors.info,
                onTap: onCreate4Weeks!,
              ),
            ],
            if (onToggleOverrideLock != null) ...[
              const SizedBox(width: 6),
              _QABtn(
                icon: overrideLock
                    ? Icons.lock_open
                    : Icons.lock_outline,
                label: overrideLock
                    ? (s.isAr ? ar2ur.tr('🔓 القفل موقوف') : '🔓 Lock OFF')
                    : (s.isAr ? ar2ur.tr('🔓 تجاوز القفل') : '🔓 Override lock'),
                color: overrideLock
                    ? AppColors.danger
                    : AppColors.warning,
                onTap: onToggleOverrideLock!,
              ),
            ],
            const SizedBox(width: 6),
            // معلومة بسيطة عن العدد
            Tooltip(
              message: s.isAr ? ar2ur.tr('مجموع الورديات') : 'Total shifts',
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: AppColors.warning.withOpacity(0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.event_note,
                        color: AppColors.warning, size: 14),
                    const SizedBox(width: 4),
                    Text('${roster.assignments.length}',
                        style: const TextStyle(
                            color: AppColors.warning,
                            fontWeight: FontWeight.w800,
                            fontSize: 12)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QABtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _QABtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

// (الأنماط الجاهزة الآن من RosterSettings.instance.patterns —
//  لا حاجة لـ _RosterPattern المحلية بعد ربط الإعدادات)

// ============================================================
// Status Banner - يعرض حالة الروستر بشكل بارز مع سبب الرفض إن وُجد
// ============================================================
class _StatusBanner extends StatelessWidget {
  final WeeklyRoster roster;
  final VoidCallback onReEdit;
  const _StatusBanner({required this.roster, required this.onReEdit});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    switch (roster.status) {
      case RosterStatus.draft:
        return _Banner(
          color: AppColors.textTertiaryLight,
          icon: Icons.edit_note,
          title: s.draftBanner,
          subtitle: null,
        );
      case RosterStatus.submitted:
      case RosterStatus.underReview:
        return _Banner(
          color: AppColors.warning,
          icon: Icons.hourglass_top,
          title: s.submittedBanner,
          subtitle: roster.submittedAt == null
              ? null
              : '${s.isAr ? ar2ur.tr("تاريخ الإرسال") : "Submitted"}: ${_fmtDt(roster.submittedAt!)}',
        );
      case RosterStatus.approved:
        return _Banner(
          color: AppColors.success,
          icon: Icons.check_circle,
          title: s.approvedBanner,
          subtitle: roster.reviewedAt == null
              ? null
              : '${s.approvedAt}: ${_fmtDt(roster.reviewedAt!)}',
        );
      case RosterStatus.rejected:
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.danger.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.danger.withOpacity(0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: AppColors.danger,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.cancel,
                      color: Colors.white, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(s.rejectedBanner,
                      style: const TextStyle(
                          color: AppColors.danger,
                          fontSize: 14,
                          fontWeight: FontWeight.w800)),
                ),
              ]),
              if (roster.rejectionReason != null &&
                  roster.rejectionReason!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: AppColors.danger.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.rejectionReason,
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.danger,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(roster.rejectionReason!,
                          style: const TextStyle(
                              fontSize: 13, height: 1.4)),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.danger),
                  onPressed: onReEdit,
                  icon: const Icon(Icons.edit, size: 16),
                  label: Text(s.reEditAndResubmit),
                ),
              ),
            ],
          ),
        );
    }
  }

  String _fmtDt(DateTime d) =>
      '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, "0")}:${d.minute.toString().padLeft(2, "0")}';
}

// ============================================================
// 🆕 Deadline Banner — تنبيه موعد إنشاء الروستر
// ============================================================
class _DeadlineBanner extends StatelessWidget {
  final DateTime weekStart;
  final RosterStatus status;
  const _DeadlineBanner({required this.weekStart, required this.status});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final settings = RosterDeadlineSettings.instance;
    if (!settings.enableAlerts) return const SizedBox.shrink();
    // إذا الروستر معتَمد فعلاً، لا داعي لتذكيره بالموعد.
    if (status == RosterStatus.approved) return const SizedBox.shrink();

    final st = settings.statusFor(weekStart: weekStart);
    final daysLeft = settings.daysToDeadline(weekStart: weekStart);
    final deadlineDay = settings.deadlineDay;
    final reviewDay = settings.reviewDay;
    final effectiveDay = settings.effectiveDay;
    final deadlineLabel =
        isAr ? RosterDeadlineSettings.dayLabelAr(deadlineDay)
             : RosterDeadlineSettings.dayLabelEn(deadlineDay);
    final reviewLabel =
        isAr ? RosterDeadlineSettings.dayLabelAr(reviewDay)
             : RosterDeadlineSettings.dayLabelEn(reviewDay);
    final effectiveLabel =
        isAr ? RosterDeadlineSettings.dayLabelAr(effectiveDay)
             : RosterDeadlineSettings.dayLabelEn(effectiveDay);

    Color bgColor;
    Color borderColor;
    IconData icon;
    String title;
    String subtitle;

    switch (st) {
      case RosterDeadlineStatus.onTime:
        bgColor = AppColors.success.withOpacity(0.10);
        borderColor = AppColors.success.withOpacity(0.40);
        icon = Icons.check_circle_outline;
        title = isAr
            ? '✅ الوقت كافٍ — يجب إرسال الروستر قبل $deadlineLabel'
            : '✅ On time — submit before $deadlineLabel';
        subtitle = isAr
            ? 'متبقّي $daysLeft يوم على الموعد النهائي. يوم $reviewLabel للمراجعة، ويبدأ التطبيق $effectiveLabel.'
            : '$daysLeft days until deadline. $reviewLabel for review, work starts $effectiveLabel.';
        break;
      case RosterDeadlineStatus.lastDay:
        bgColor = AppColors.warning.withOpacity(0.12);
        borderColor = AppColors.warning.withOpacity(0.50);
        icon = Icons.warning_amber_rounded;
        title = isAr
            ? '⚠️ اليوم آخر يوم لإرسال الروستر ($deadlineLabel)'
            : '⚠️ TODAY is the deadline ($deadlineLabel)';
        subtitle = isAr
            ? 'أرسِل الروستر قبل نهاية اليوم. غداً ($reviewLabel) للمراجعة، ويبدأ التطبيق $effectiveLabel.'
            : 'Submit by end of day. Tomorrow ($reviewLabel) is review day, work starts $effectiveLabel.';
        break;
      case RosterDeadlineStatus.reviewWindow:
        bgColor = AppColors.danger.withOpacity(0.12);
        borderColor = AppColors.danger.withOpacity(0.50);
        icon = Icons.error_outline;
        title = isAr
            ? '🚫 فات الموعد — أنت في نافذة المراجعة'
            : '🚫 Past deadline — review window';
        subtitle = isAr
            ? 'كان يجب إرسال الروستر قبل $deadlineLabel. اليوم ($reviewLabel) للمراجعة فقط — لا يجوز إنشاء روستر إلّا في حالات استثنائيّة.'
            : 'Roster was due before $deadlineLabel. Today is review-only — exceptions only.';
        break;
      case RosterDeadlineStatus.workStarted:
        bgColor = AppColors.danger.withOpacity(0.20);
        borderColor = AppColors.danger;
        icon = Icons.dangerous_outlined;
        title = isAr
            ? '⛔ بدأ العمل بهذا الأسبوع'
            : '⛔ Work week has already started';
        subtitle = isAr
            ? 'لا يمكن إنشاء/تعديل روستر لأسبوع بدأ تطبيقه. اختر أسبوعاً قادماً.'
            : 'Cannot create/edit a roster for a week already in progress. Pick a future week.';
        break;
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: borderColor, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: borderColor)),
                const SizedBox(height: 4),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final String? subtitle;
  const _Banner({
    required this.color,
    required this.icon,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w800)),
              if (subtitle != null)
                Text(subtitle!,
                    style: TextStyle(
                        fontSize: 11,
                        color: color.withOpacity(0.8))),
            ],
          ),
        ),
      ]),
    );
  }
}

// ============================================================
// Header - معلومات النقطة + العملاء + الأسبوع + الحالة
// ============================================================
class _Header extends StatelessWidget {
  final Point? point;
  final DateTime weekStart;
  final String statusLabel;
  final Color statusColor;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _Header({
    required this.point,
    required this.weekStart,
    required this.statusLabel,
    required this.statusColor,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final p = point;
    // العملاء التابعون لهذه النقطة
    final clients = p == null
        ? <Site>[]
        : p.linkedClients
            .map((link) => repo.sites.firstWhere(
                  (x) => x.id == link.clientId,
                  orElse: () =>
                      Site(id: '', companyName: '?', shortName: ''),
                ))
            .where((s) => s.id.isNotEmpty)
            .toList();

    // 🆕 شريط مدمج: الاسم + الكود + العملاء + التنقّل + الحالة في صفّ واحد.
    // (كان عمودياً ويأخذ مساحة كبيرة — صار أفقياً مضغوطاً.)
    return Container(
      color: Theme.of(context).cardTheme.color,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // اسم النقطة + الكود (صف واحد بدل عمود)
              const Icon(Icons.place,
                  size: 14, color: AppColors.warning),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  p?.name ?? '-',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w900),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (p?.code.isNotEmpty == true) ...[
                const SizedBox(width: 4),
                Text(
                  p!.code,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 9,
                    color: AppColors.warning,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              // العملاء كعدد فقط (لا قائمة كاملة لتوفير مساحة)
              if (clients.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.brand.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    s.isAr
                        ? '${clients.length} عميل'
                        : '${clients.length} clients',
                    style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: AppColors.brand),
                  ),
                ),
              ],
              const Spacer(),
              StatusBadge(label: statusLabel, color: statusColor),
            ],
          ),
          // navigation الأسبوع
          Row(
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
              const SizedBox(width: 4),
              Text(
                '${_fmt(weekStart)} - ${_fmt(weekStart.add(const Duration(days: 6)))}',
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 4),
              InkWell(
                onTap: onNext,
                borderRadius: BorderRadius.circular(20),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.chevron_left, size: 18),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.day}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

// ============================================================
// مفتاح ألوان أنواع الورديات
// ============================================================
class RosterShiftLegend extends StatelessWidget {
  const RosterShiftLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    // 🆕 مفتاح ألوان مدمج (كان يأخذ سطراً كاملاً، صار صغيراً)
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _LegendChip(
              color: AppColors.success,
              label: 'M=${s.isAr ? ar2ur.tr("صباحي") : "Morn"}'),
          const SizedBox(width: 4),
          _LegendChip(
              color: AppColors.info,
              label: 'N=${s.isAr ? ar2ur.tr("ليلي") : "Night"}'),
          const SizedBox(width: 4),
          _LegendChip(
              color: AppColors.textTertiaryLight,
              label: 'Off=${s.isAr ? ar2ur.tr("إجازة") : "Off"}'),
        ],
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendChip({required this.color, required this.label});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color, fontSize: 9, fontWeight: FontWeight.w800),
      ),
    );
  }
}

// ============================================================
// جدول الروستر (عام - يُستخدم في إنشاء وعرض/تعديل الروستر)
// ============================================================
class RosterGridTable extends StatefulWidget {
  final WeeklyRoster roster;
  final List<Employee> employees;
  final DateTime weekStart;
  final bool readOnly;
  /// 🆕 لو true → يتجاهل قفل الأيّام السابقة (admin override)
  final bool overrideLock;
  final void Function(Employee, int) onCellTap;
  /// long-press على صف موظف (لقائمة "تطبيق نمط")
  final void Function(Employee)? onCellLongPress;
  final VoidCallback onAddEmployee;
  final void Function(Employee) onRemoveEmployee;

  const RosterGridTable({
    super.key,
    required this.roster,
    required this.employees,
    required this.weekStart,
    required this.readOnly,
    this.overrideLock = false,
    required this.onCellTap,
    this.onCellLongPress,
    required this.onAddEmployee,
    required this.onRemoveEmployee,
  });

  @override
  State<RosterGridTable> createState() => _RosterGridTableState();
}

class _RosterGridTableState extends State<RosterGridTable> {
  // 🆕 Controllers مشتركان للتمرير الأفقي بين الـ header والـ body
  // عشان يبقى رأس الجدول ثابتاً عند التمرير العمودي للموظّفين.
  final ScrollController _hHeaderCtrl = ScrollController();
  final ScrollController _hBodyCtrl = ScrollController();
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _hHeaderCtrl.addListener(() {
      if (_syncing) return;
      _syncing = true;
      if (_hBodyCtrl.hasClients &&
          _hBodyCtrl.offset != _hHeaderCtrl.offset) {
        _hBodyCtrl.jumpTo(_hHeaderCtrl.offset);
      }
      _syncing = false;
    });
    _hBodyCtrl.addListener(() {
      if (_syncing) return;
      _syncing = true;
      if (_hHeaderCtrl.hasClients &&
          _hHeaderCtrl.offset != _hBodyCtrl.offset) {
        _hHeaderCtrl.jumpTo(_hBodyCtrl.offset);
      }
      _syncing = false;
    });
  }

  @override
  void dispose() {
    _hHeaderCtrl.dispose();
    _hBodyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final dayShortNames = s.isAr
        ? ['ثن', 'ثل', 'أر', 'خم', 'جم', 'سب', 'أح']
        : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    // 🆕 aliases للسهولة
    final roster = widget.roster;
    final employees = widget.employees;
    final weekStart = widget.weekStart;
    final readOnly = widget.readOnly;
    final overrideLock = widget.overrideLock;
    final onCellTap = widget.onCellTap;
    final onCellLongPress = widget.onCellLongPress;
    final onRemoveEmployee = widget.onRemoveEmployee;

    const empColWidth = 130.0;
    const dayColWidth = 70.0;
    const totalColWidth = 50.0;
    final tableWidth = empColWidth + (dayColWidth * 7) + totalColWidth;

    // 🆕 رأس الجدول كـ widget منفصل (سيُستعمل sticky فوق الـ body)
    final headerRow = Row(
      children: [
        _HeaderCell(
            label: s.isAr ? ar2ur.tr('الموظفون') : 'Employees',
            width: empColWidth),
        ...List.generate(7, (i) {
          final d = weekStart.add(Duration(days: i));
          return _HeaderCell(
            width: dayColWidth,
            label: '${dayShortNames[i]}\n${d.day.toString().padLeft(2, "0")}',
          );
        }),
        const _HeaderCell(
            label: 'h', width: totalColWidth, isAccent: true),
      ],
    );

    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ===== رأس الجدول الثابت (Sticky) =====
          Container(
            decoration: BoxDecoration(
              color: AppColors.brand.withOpacity(0.06),
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              controller: _hHeaderCtrl,
              child: SizedBox(width: tableWidth, child: headerRow),
            ),
          ),
          // ===== جسم الجدول (قابل للتمرير عموديّاً) =====
          // 🆕 Expanded بدلاً من Flexible: يفرض ارتفاعاً محدوداً
          // (Flexible loose fit كان يُسبّب "Cannot hit test render box
          // that has never been laid out").
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              controller: _hBodyCtrl,
              child: SizedBox(
                width: tableWidth,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ===== صفوف الموظفين =====
            ...employees.map((emp) {
              final empAssignments = roster.assignments
                  .where((a) => a.employeeId == emp.id)
                  .toList();
              double totalH = 0;
              for (final a in empAssignments) {
                totalH += a.hours;
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _EmpNameCell(
                      employee: emp,
                      width: empColWidth,
                      onRemove:
                          readOnly ? null : () => onRemoveEmployee(emp),
                      onLongPress: onCellLongPress == null
                          ? null
                          : () => onCellLongPress!(emp),
                    ),
                    ...List.generate(7, (dayIndex) {
                      final assignment = empAssignments
                          .where((a) => a.dayIndex == dayIndex)
                          .toList();
                      // 🆕 طبقة حماية ثالثة عند الـ render: يوم بعد اليوم
                      // الحالي = ليس مقفلاً، بصرف النظر عن أيّ delegate.
                      final today = DateTime.now();
                      final todayDate =
                          DateTime(today.year, today.month, today.day);
                      final cellDate = DateTime(weekStart.year,
                          weekStart.month, weekStart.day + dayIndex);
                      // 🆕 لو وضع التجاوز مفعَّل → كلّ الخلايا قابلة للتعديل
                      final dayLocked = overrideLock
                          ? false
                          : cellDate.isAfter(todayDate)
                              ? false
                              : roster.isDayLocked(dayIndex);
                      return Builder(builder: (cellCtx) {
                        return _ShiftCell(
                          width: dayColWidth,
                          assignment: assignment.isEmpty
                              ? null
                              : assignment.first,
                          locked: dayLocked,
                          onTap: readOnly
                              ? null
                              : () {
                                  if (dayLocked) {
                                    final isAr =
                                        AppStrings.of(cellCtx).isAr;
                                    ScaffoldMessenger.of(cellCtx)
                                        .showSnackBar(SnackBar(
                                      backgroundColor: AppColors.danger,
                                      content: Text(isAr
                                          ? '🔒 هذا اليوم انتهى ولا يمكن تعديله'
                                          : '🔒 This day has passed; editing is locked'),
                                    ));
                                    return;
                                  }
                                  onCellTap(emp, dayIndex);
                                },
                        );
                      });
                    }),
                    _TotalCell(
                        width: totalColWidth,
                        hours: totalH,
                        isAccent: true),
                  ],
                ),
              );
            }),
            // ===== صف Active/Day =====
            Row(
              children: [
                _SummaryLabelCell(
                    label: s.isAr ? ar2ur.tr('النشطون/يوم') : 'Active/Day',
                    width: empColWidth),
                ...List.generate(7, (dayIndex) {
                  final activeCount = roster.assignments
                      .where((a) =>
                          a.dayIndex == dayIndex &&
                          a.shiftType != ShiftType.off)
                      .length;
                  return _SummaryNumCell(
                      width: dayColWidth, value: activeCount.toString());
                }),
                _SummaryNumCell(
                    width: totalColWidth,
                    value: '${employees.length * 60}',
                    isAccent: true),
              ],
            ),
            // ===== صف Daily Hrs =====
            Row(
              children: [
                _SummaryLabelCell(
                    label: s.isAr ? ar2ur.tr('ساعات يومية') : 'Daily Hrs',
                    width: empColWidth,
                    color: AppColors.warning),
                ...List.generate(7, (dayIndex) {
                  double totalH = 0;
                  for (final a in roster.assignments) {
                    if (a.dayIndex == dayIndex) totalH += a.hours;
                  }
                  return _SummaryNumCell(
                    width: dayColWidth,
                    value: totalH.toStringAsFixed(0),
                    color: AppColors.warning,
                  );
                }),
                _SummaryNumCell(
                  width: totalColWidth,
                  value: '${roster.totalHours.toStringAsFixed(0)}h',
                  isAccent: true,
                  color: AppColors.warning,
                ),
              ],
            ),
                      // ===== زر إضافة موظف =====
                      if (!readOnly)
                        InkWell(
                          onTap: widget.onAddEmployee,
                          child: Container(
                            width: tableWidth,
                            padding: const EdgeInsets.symmetric(
                                vertical: 10),
                            decoration: BoxDecoration(
                              color:
                                  AppColors.brand.withOpacity(0.05),
                              border: Border(
                                top: BorderSide(
                                    color: Theme.of(context)
                                        .dividerColor),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.person_add,
                                    color: AppColors.brand,
                                    size: 16),
                                const SizedBox(width: 6),
                                Text(
                                  s.isAr
                                      ? 'إضافة موظف'
                                      : 'Add Employee',
                                  style: const TextStyle(
                                    color: AppColors.brand,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
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

// ===== خلية العنوان =====
class _HeaderCell extends StatelessWidget {
  final String label;
  final double width;
  final bool isAccent;
  const _HeaderCell({
    required this.label,
    required this.width,
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
            : Theme.of(context).dividerColor.withOpacity(0.15),
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

// ===== خلية اسم الموظف =====
class _EmpNameCell extends StatelessWidget {
  final Employee employee;
  final double width;
  final VoidCallback? onRemove;
  final VoidCallback? onLongPress;
  const _EmpNameCell({
    required this.employee,
    required this.width,
    this.onRemove,
    this.onLongPress,
  });

  /// 🆕 فتح تطبيق الاتصال (Phone Link).
  void _call() {
    final phone = employee.mobile.trim();
    if (phone.isEmpty) return;
    final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    html.window.open('tel:$cleaned', '_self');
  }

  /// 🆕 فتح WhatsApp Web.
  void _whatsapp() {
    final phone = employee.mobile.trim();
    if (phone.isEmpty) return;
    final cleaned = phone.replaceAll(RegExp(r'[^\d]'), '');
    html.window.open('https://wa.me/$cleaned', '_blank');
  }

  @override
  Widget build(BuildContext context) {
    final hasPhone = employee.mobile.trim().isNotEmpty;
    return InkWell(
      onLongPress: onLongPress,
      child: Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor),
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 🆕 هويّة الموظّف الموحّدة: صورة + اسم + كود
              Expanded(
                child: EmployeeIdentity(
                  employee: employee,
                  size: EmployeeIdentitySize.compact,
                  showCode: true,
                ),
              ),
              if (onRemove != null)
                InkWell(
                  onTap: onRemove,
                  child: const Icon(Icons.close,
                      size: 14, color: AppColors.danger),
                ),
            ],
          ),
          // 🆕 رقم الجوال + أزرار اتصال/واتساب
          if (hasPhone) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.phone, size: 10, color: Colors.grey.shade600),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    employee.mobile,
                    style: TextStyle(
                        fontSize: 9.5,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _MiniBtn(
                  icon: Icons.call,
                  color: AppColors.success,
                  tooltip: 'Call',
                  onTap: _call,
                ),
                const SizedBox(width: 3),
                _MiniBtn(
                  icon: Icons.chat_bubble,
                  color: const Color(0xFF25D366),
                  tooltip: 'WhatsApp',
                  onTap: _whatsapp,
                ),
              ],
            ),
          ],
        ],
      ),
      ),
    );
  }
}

/// زرّ صغير للاتصال/الواتساب داخل خليّة الروستر.
class _MiniBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;
  const _MiniBtn({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 11, color: color),
        ),
      ),
    );
  }
}

// ===== خلية وردية =====
class _ShiftCell extends StatelessWidget {
  final double width;
  final RosterAssignment? assignment;
  final VoidCallback? onTap;
  final bool locked; // 🔒 يوم سابق غير قابل للتعديل
  const _ShiftCell({
    required this.width,
    required this.assignment,
    required this.onTap,
    this.locked = false,
  });
  @override
  Widget build(BuildContext context) {
    final a = assignment;

    Color bg;
    Color textColor;
    String letter;
    String? timeLabel;

    if (a == null || a.shiftType == ShiftType.off) {
      bg = AppColors.textTertiaryLight.withOpacity(0.1);
      textColor = AppColors.textTertiaryLight;
      letter = 'Off';
      timeLabel = null;
    } else if (a.shiftType == ShiftType.night) {
      bg = AppColors.info.withOpacity(0.15);
      textColor = AppColors.info;
      letter = 'N';
      timeLabel = '${_short(a.startTime)}-${_short(a.endTime)}';
    } else {
      // morning / evening / custom
      bg = AppColors.success.withOpacity(0.15);
      textColor = AppColors.success;
      letter = 'M';
      timeLabel = '${_short(a.startTime)}-${_short(a.endTime)}';
    }

    final flagged = a?.reviewerFlag ?? false;

    return InkWell(
      onTap: onTap,
      child: Stack(
        children: [
          Container(
            width: width,
            height: 56,
            decoration: BoxDecoration(
              color: bg,
              border: Border(
                right: BorderSide(color: Theme.of(context).dividerColor),
                bottom: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  letter,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (timeLabel != null)
                  Text(
                    timeLabel,
                    style: TextStyle(
                        color: textColor,
                        fontSize: 10,
                        fontFamily: 'monospace'),
                  ),
              ],
            ),
          ),
          if (flagged)
            Positioned(
              top: 2,
              right: 2,
              child: Container(
                width: 14,
                height: 14,
                decoration: const BoxDecoration(
                  color: AppColors.warning,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.flag,
                    color: Colors.white, size: 9),
              ),
            ),
          if (locked)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.18),
                alignment: Alignment.topLeft,
                padding: const EdgeInsets.all(2),
                child: const Icon(Icons.lock,
                    size: 11, color: Colors.white70),
              ),
            ),
        ],
      ),
    );
  }

  String _short(String t) {
    // 08:00 → 08
    final p = t.split(':');
    return p.isEmpty ? t : p[0];
  }
}

// ===== خلية إجمالي ساعات الموظف =====
class _TotalCell extends StatelessWidget {
  final double width;
  final double hours;
  final bool isAccent;
  const _TotalCell({
    required this.width,
    required this.hours,
    this.isAccent = false,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.08),
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor),
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Text(
        hours.toStringAsFixed(0),
        style: const TextStyle(
            color: AppColors.warning,
            fontWeight: FontWeight.w800,
            fontSize: 14),
      ),
    );
  }
}

// ===== خلية ملخص (عنوان) =====
class _SummaryLabelCell extends StatelessWidget {
  final String label;
  final double width;
  final Color? color;
  const _SummaryLabelCell({
    required this.label,
    required this.width,
    this.color,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: (color ?? AppColors.brand).withOpacity(0.08),
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor),
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

// ===== خلية ملخص (رقم) =====
class _SummaryNumCell extends StatelessWidget {
  final double width;
  final String value;
  final bool isAccent;
  final Color? color;
  const _SummaryNumCell({
    required this.width,
    required this.value,
    this.isAccent = false,
    this.color,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isAccent
            ? AppColors.warning.withOpacity(0.15)
            : (color ?? AppColors.brand).withOpacity(0.05),
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor),
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Text(
        value,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: color ?? (isAccent ? AppColors.warning : AppColors.brand),
        ),
      ),
    );
  }
}

// ============================================================
// رسم بياني 24 ساعة لكل يوم
// يعرض timeline أفقي 0-24 لكل يوم مع شرائح ملونة لورديات الموظفين
// ============================================================
class _DailyHoursChart extends StatelessWidget {
  final WeeklyRoster roster;
  final DateTime weekStart;
  const _DailyHoursChart({required this.roster, required this.weekStart});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final dayNames = s.isAr
        ? ['الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد']
        : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Icon(Icons.bar_chart,
                size: 16, color: AppColors.brand),
            const SizedBox(width: 6),
            Text(
              s.isAr
                  ? 'الجدول الزمني (24 ساعة لكل يوم)'
                  : 'Daily Timeline (24h per day)',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800),
            ),
          ]),
          const SizedBox(height: 12),
          // محور ساعات (0, 6, 12, 18, 24)
          Padding(
            padding: const EdgeInsets.only(left: 70),
            child: Row(
              children: [0, 6, 12, 18, 24]
                  .map((h) => Expanded(
                        child: Text('${h.toString().padLeft(2, "0")}:00',
                            textAlign: TextAlign.start,
                            style: TextStyle(
                              fontSize: 9,
                              color: Theme.of(context).disabledColor,
                              fontFamily: 'monospace',
                            )),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 6),
          // 7 أيام
          ...List.generate(7, (dayIndex) {
            final dayAssignments = roster.assignments
                .where((a) =>
                    a.dayIndex == dayIndex && a.shiftType != ShiftType.off)
                .toList();
            return _DayTimelineRow(
                dayName: dayNames[dayIndex],
                assignments: dayAssignments);
          }),
        ],
      ),
    );
  }
}

class _DayTimelineRow extends StatelessWidget {
  final String dayName;
  final List<RosterAssignment> assignments;
  const _DayTimelineRow(
      {required this.dayName, required this.assignments});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(dayName,
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: Container(
              height: 18,
              decoration: BoxDecoration(
                color: Theme.of(context).dividerColor.withOpacity(0.3),
                borderRadius: BorderRadius.circular(4),
              ),
              child: LayoutBuilder(builder: (_, constraints) {
                final w = constraints.maxWidth;
                return Stack(
                  children: assignments.map((a) {
                    final start = _parseHour(a.startTime);
                    var end = _parseHour(a.endTime);
                    // وردية ليلية تعبر منتصف الليل
                    if (end <= start) end += 24;
                    final left = (start / 24) * w;
                    final width = ((end - start) / 24) * w;
                    final isNight = a.shiftType == ShiftType.night ||
                        start >= 18 || end > 24;
                    return Positioned(
                      left: left.clamp(0.0, w),
                      width: width.clamp(0.0, w - left.clamp(0.0, w)),
                      top: 0,
                      bottom: 0,
                      child: Container(
                        decoration: BoxDecoration(
                          color: (isNight ? AppColors.info : AppColors.success)
                              .withOpacity(0.7),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    );
                  }).toList(),
                );
              }),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 32,
            child: Text(
              '${_dayHours().toStringAsFixed(0)}h',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: AppColors.warning,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  double _dayHours() {
    double total = 0;
    for (final a in assignments) {
      total += a.hours;
    }
    return total;
  }

  double _parseHour(String t) {
    final p = t.split(':');
    if (p.length != 2) return 0;
    final h = int.tryParse(p[0]) ?? 0;
    final m = int.tryParse(p[1]) ?? 0;
    return h + (m / 60.0);
  }
}

// ============================================================
// نافذة تعديل الوردية (IN/OUT/Type)
// ============================================================
class RosterShiftEditorSheet extends StatefulWidget {
  final Employee employee;
  final int dayIndex;
  final WeeklyRoster roster;
  final Future<bool> Function() onPersist;
  final VoidCallback onChanged;
  /// 🆕 لو true → يتجاهل قفل الأيّام السابقة (admin override)
  final bool overrideLock;
  const RosterShiftEditorSheet({
    super.key,
    required this.employee,
    required this.dayIndex,
    required this.roster,
    required this.onPersist,
    required this.onChanged,
    this.overrideLock = false,
  });

  @override
  State<RosterShiftEditorSheet> createState() => _ShiftEditorSheetState();
}

class _ShiftEditorSheetState extends State<RosterShiftEditorSheet> {
  late TimeOfDay _start;
  late TimeOfDay _end;
  late ShiftType _type;
  late RosterAssignment? _existing;
  late TextEditingController _notesCtrl;

  @override
  void initState() {
    super.initState();
    _existing = widget.roster.assignments.firstWhere(
      (a) =>
          a.employeeId == widget.employee.id &&
          a.dayIndex == widget.dayIndex,
      orElse: () => RosterAssignment(
        id: '',
        employeeId: widget.employee.id,
        dayIndex: widget.dayIndex,
        startTime: '08:00',
        endTime: '20:00',
      ),
    );
    _start = _parseTime(_existing!.startTime);
    _end = _parseTime(_existing!.endTime);
    _type = _existing!.shiftType;
    _notesCtrl = TextEditingController(text: _existing!.notes ?? '');
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  TimeOfDay _parseTime(String t) {
    final p = t.split(':');
    if (p.length != 2) return const TimeOfDay(hour: 8, minute: 0);
    return TimeOfDay(
      hour: int.tryParse(p[0]) ?? 8,
      minute: int.tryParse(p[1]) ?? 0,
    );
  }

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickTime(bool isStart) async {
    final t = await showTimePicker(
      context: context,
      initialTime: isStart ? _start : _end,
    );
    if (t != null) {
      setState(() {
        if (isStart) {
          _start = t;
        } else {
          _end = t;
        }
      });
    }
  }

  Future<void> _save() async {
    final repo = MockRepository();
    final s = AppStrings.of(context);
    // 🔒 رفض التعديل على يوم انتهى — إلّا إذا كان وضع التجاوز مفعَّل
    if (!widget.overrideLock &&
        widget.roster.isDayLocked(widget.dayIndex)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text(s.isAr
            ? '🔒 هذا اليوم انتهى ولا يمكن تعديله — فعّل "تجاوز القفل" من شريط الإجراءات'
            : '🔒 This day has passed — enable "Override lock" first'),
      ));
      return;
    }
    if (_type != ShiftType.off) {
      // ===== فحص تعارض الموظف في موقع آخر =====
      final conflicts = repo.findEmployeeConflicts(
        employeeId: widget.employee.id,
        weekStart: widget.roster.weekStart,
        dayIndex: widget.dayIndex,
        startTime: _formatTime(_start),
        endTime: _formatTime(_end),
        excludeRosterId: widget.roster.id,
      );
      if (conflicts.isNotEmpty) {
        // 🆕 إذا التعارض مع نقطة مختلفة (cross-point) → رفض صارم
        // (الوردية يجب أن تكون بعد انتهاء الأخرى)
        final crossPointConflicts = conflicts
            .where((c) => c.pointId != widget.roster.siteId)
            .toList();
        if (crossPointConflicts.isNotEmpty) {
          if (!mounted) return;
          await _showHardBlockDialog(crossPointConflicts);
          return;
        }
        // تعارض داخل نفس النقطة (نادر) → السلوك القديم: تأكيد
        final shouldContinue = await _showConflictDialog(conflicts);
        if (shouldContinue != true) return;
      }
    }

    if (_type == ShiftType.off) {
      widget.roster.assignments.removeWhere((a) =>
          a.employeeId == widget.employee.id &&
          a.dayIndex == widget.dayIndex);
    } else {
      final notesText = _notesCtrl.text.trim();
      final newA = RosterAssignment(
        id: _existing!.id.isEmpty ? repo.generateId() : _existing!.id,
        employeeId: widget.employee.id,
        dayIndex: widget.dayIndex,
        startTime: _formatTime(_start),
        endTime: _formatTime(_end),
        shiftType: _type,
        notes: notesText.isEmpty ? null : notesText,
      );
      widget.roster.assignments.removeWhere((a) =>
          a.employeeId == widget.employee.id &&
          a.dayIndex == widget.dayIndex);
      widget.roster.assignments.add(newA);
    }
    final ok = await widget.onPersist();
    if (!ok) return;
    widget.onChanged();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  /// 🆕 dialog صارم — لا يسمح بالحفظ. تظهر للموظّف المُعار عند تعارض زمني
  /// مع روستر نقطة أخرى. الوردية الجديدة يجب أن تكون بعد انتهاء الأخرى.
  Future<void> _showHardBlockDialog(
      List<RosterConflict> conflicts) async {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final repo = MockRepository();
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.block,
            color: AppColors.danger, size: 36),
        title: Text(isAr
            ? '🚫 تعارض زمني مع نقطة أخرى'
            : '🚫 Time conflict with another point'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isAr
                ? 'هذا الموظّف لديه وردية مدرجة في نقطة أخرى تتعارض زمنيّاً مع الوردية التي تحاول إضافتها. لا يمكن الحفظ إلّا إذا كانت ورديتك بعد انتهاء الوردية الأصليّة.'
                : 'This employee already has a shift in another point that overlaps in time. You can only add a shift that starts AFTER the existing one ends.'),
            const SizedBox(height: 12),
            for (final c in conflicts) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.danger.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: AppColors.danger.withOpacity(0.30)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        isAr
                            ? '📍 النقطة: ${repo.pointById(c.pointId)?.name ?? "؟"}'
                            : '📍 Point: ${repo.pointById(c.pointId)?.name ?? "?"}',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                        '⏰ ${c.assignment.startTime} → ${c.assignment.endTime}',
                        style: const TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brand,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx),
            child: Text(isAr ? ar2ur.tr('فهمت') : 'Got it'),
          ),
        ],
      ),
    );
  }

  /// dialog يعرض تعارضات الموظف ويسأل: هل تريد المتابعة؟
  Future<bool?> _showConflictDialog(List<RosterConflict> conflicts) async {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber, color: AppColors.danger),
            const SizedBox(width: 8),
            Text(s.isAr ? ar2ur.tr('تعارض في الجدول') : 'Schedule Conflict'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.isAr
                  ? 'هذا الموظف موجود في موقع آخر بنفس الوقت:'
                  : 'This employee is scheduled at another point at the same time:',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            ...conflicts.map((c) {
              final point = repo.pointById(c.pointId);
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.danger.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.danger.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(point?.name ?? '?',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w800)),
                    Text(
                      '${c.assignment.startTime} - ${c.assignment.endTime}'
                      ' (${s.isAr ? c.roster.status.arabicLabel() : c.roster.status.englishLabel()})',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(s.cancel),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.warning, size: 14),
            label: Text(
                s.isAr ? ar2ur.tr('متابعة رغم التعارض') : 'Continue anyway'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final dayNames = s.isAr
        ? ['الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد']
        : ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return Container(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: Column(
                children: [
                  Text(widget.employee.fullName,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                  Text(dayNames[widget.dayIndex],
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(height: 18),
            // اختيار النوع
            Row(
              children: [
                _TypeButton(
                  label: 'M (${s.isAr ? ar2ur.tr("صباحي") : "Morning"})',
                  color: AppColors.success,
                  selected: _type == ShiftType.morning,
                  onTap: () => setState(() {
                    _type = ShiftType.morning;
                    _start = const TimeOfDay(hour: 8, minute: 0);
                    _end = const TimeOfDay(hour: 20, minute: 0);
                  }),
                ),
                const SizedBox(width: 6),
                _TypeButton(
                  label: 'N (${s.isAr ? ar2ur.tr("ليلي") : "Night"})',
                  color: AppColors.info,
                  selected: _type == ShiftType.night,
                  onTap: () => setState(() {
                    _type = ShiftType.night;
                    _start = const TimeOfDay(hour: 20, minute: 0);
                    _end = const TimeOfDay(hour: 8, minute: 0);
                  }),
                ),
                const SizedBox(width: 6),
                _TypeButton(
                  label: 'Off',
                  color: AppColors.textTertiaryLight,
                  selected: _type == ShiftType.off,
                  onTap: () => setState(() => _type = ShiftType.off),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (_type != ShiftType.off) ...[
              Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _pickTime(true),
                    child: AbsorbPointer(
                      child: TextField(
                        controller: TextEditingController(
                            text: _formatTime(_start)),
                        decoration: InputDecoration(
                          labelText: s.isAr ? ar2ur.tr('IN (الدخول)') : 'IN',
                          prefixIcon: const Icon(Icons.login, size: 18),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _pickTime(false),
                    child: AbsorbPointer(
                      child: TextField(
                        controller: TextEditingController(
                            text: _formatTime(_end)),
                        decoration: InputDecoration(
                          labelText: s.isAr ? ar2ur.tr('OUT (الخروج)') : 'OUT',
                          prefixIcon:
                              const Icon(Icons.logout, size: 18),
                        ),
                      ),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.access_time,
                        size: 14, color: AppColors.warning),
                    const SizedBox(width: 6),
                    Text(
                      '${s.isAr ? ar2ur.tr("الساعات") : "Hours"}: ${_calcHours().toStringAsFixed(1)}',
                      style: const TextStyle(
                          color: AppColors.warning,
                          fontWeight: FontWeight.w800,
                          fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            // ===== ملاحظات على هذه الوردية =====
            TextField(
              controller: _notesCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: s.isAr ? ar2ur.tr('ملاحظات (اختياري)') : 'Notes (optional)',
                prefixIcon: const Icon(Icons.note_outlined, size: 18),
                border: const OutlineInputBorder(),
              ),
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 14),
            ElevatedButton(onPressed: _save, child: Text(s.save)),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(s.cancel),
            ),
          ],
        ),
      ),
    );
  }

  double _calcHours() {
    final start = _start.hour + _start.minute / 60.0;
    var end = _end.hour + _end.minute / 60.0;
    if (end <= start) end += 24;
    return end - start;
  }
}

class _TypeButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _TypeButton({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? color : color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : color,
                fontWeight: FontWeight.w800,
                fontSize: 11,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// نافذة إضافة موظف للروستر
// ============================================================
/// 🆕 وصف حالة موظّف عند إضافته للروستر — لعرض الـ badges المناسبة.
class RosterAddEmployeeStatus {
  /// اسم النقطة الأمّ للموظّف إذا كانت مختلفة عن نقطة الروستر.
  final String? linkedPointName;

  /// اسم نقطة أخرى مدرج فيها الموظّف بنفس الأسبوع (مسوّدة/معتمدة).
  final String? otherRosterPointName;
  final DateTime? otherRosterWeek;

  const RosterAddEmployeeStatus({
    this.linkedPointName,
    this.otherRosterPointName,
    this.otherRosterWeek,
  });

  bool get isCrossPoint => linkedPointName != null;
  bool get isInOtherRoster => otherRosterPointName != null;
}

class RosterAddEmployeeSheet extends StatefulWidget {
  final List<Employee> available;
  final Future<void> Function(Employee) onAdd;
  // لإظهار شارة "مشغول في موقع آخر هذا الأسبوع"
  final DateTime? weekStart;
  final String? excludeRosterId;
  /// 🆕 حالة كلّ موظّف (مربوط بنقطة أخرى / مدرج في روستر آخر).
  /// خريطة: empId → الحالة.
  final Map<String, RosterAddEmployeeStatus>? statusMap;
  const RosterAddEmployeeSheet({
    super.key,
    required this.available,
    required this.onAdd,
    this.weekStart,
    this.excludeRosterId,
    this.statusMap,
  });

  @override
  State<RosterAddEmployeeSheet> createState() => _AddEmployeeSheetState();
}

class _AddEmployeeSheetState extends State<RosterAddEmployeeSheet> {
  String _query = '';

  /// عدد الورديات الفعّالة لهذا الموظف في روسترات أخرى لنفس الأسبوع
  int _otherWeekShifts(String empId) {
    if (widget.weekStart == null) return 0;
    final repo = MockRepository();
    final wsKey = widget.weekStart!.toIso8601String().substring(0, 10);
    var count = 0;
    for (final r in repo.rosters) {
      if (r.id == widget.excludeRosterId) continue;
      if (r.status == RosterStatus.rejected) continue;
      if (r.weekStart.toIso8601String().substring(0, 10) != wsKey) continue;
      for (final a in r.assignments) {
        if (a.employeeId == empId && a.shiftType != ShiftType.off) {
          count++;
        }
      }
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final filtered = widget.available.where((e) {
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return e.fullName.toLowerCase().contains(q) ||
          e.code.toLowerCase().contains(q);
    }).toList();
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Text(s.isAr ? ar2ur.tr('إضافة موظف للروستر') : 'Add to Roster',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                TextField(
                  decoration: InputDecoration(
                    hintText: s.search,
                    prefixIcon: const Icon(Icons.search),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (_, i) {
                final emp = filtered[i];
                final status = widget.statusMap?[emp.id];
                final isCrossPoint = status?.isCrossPoint ?? false;
                final isInOtherRoster =
                    status?.isInOtherRoster ?? false;

                // 🆕 لون البطاقة حسب الحالة
                final Color tileColor = isInOtherRoster
                    ? AppColors.danger.withOpacity(0.06)
                    : isCrossPoint
                        ? AppColors.warning.withOpacity(0.08)
                        : Colors.transparent;
                final Color borderColor = isInOtherRoster
                    ? AppColors.danger.withOpacity(0.40)
                    : isCrossPoint
                        ? AppColors.warning.withOpacity(0.40)
                        : Colors.transparent;
                final Color avatarColor = isInOtherRoster
                    ? AppColors.danger
                    : isCrossPoint
                        ? AppColors.warning
                        : AppColors.brand;

                return Container(
                  margin: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: tileColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: borderColor),
                  ),
                  child: ListTile(
                    leading:
                        AppAvatar(initials: emp.initials, color: avatarColor),
                    title: Text(emp.fullName,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w900)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${emp.code} • ${emp.jobTitle}',
                            style: const TextStyle(fontSize: 11)),
                        // 🆕 شارة "مدرج في روستر آخر" (الأولويّة الأعلى)
                        if (isInOtherRoster) ...[
                          const SizedBox(height: 4),
                          _StatusBadge(
                            color: AppColors.danger,
                            icon: Icons.warning_amber,
                            text: s.isAr
                                ? '⚠️ مُدرَج في روستر «${status!.otherRosterPointName}» نفس الأسبوع'
                                : '⚠️ Already in roster «${status!.otherRosterPointName}» same week',
                          ),
                        ],
                        // 🆕 شارة "مربوط بنقطة أخرى"
                        if (isCrossPoint && !isInOtherRoster) ...[
                          const SizedBox(height: 4),
                          _StatusBadge(
                            color: AppColors.warning,
                            icon: Icons.place_outlined,
                            text: s.isAr
                                ? '📍 مربوط بنقطة «${status!.linkedPointName}»'
                                : '📍 Linked to point «${status!.linkedPointName}»',
                          ),
                        ],
                      ],
                    ),
                    trailing: Icon(
                      Icons.add_circle_outline,
                      color: avatarColor,
                    ),
                    onTap: () async {
                      // 🆕 إذا مدرج في روستر آخر — نطلب تأكيد قبل الإضافة
                      if (isInOtherRoster) {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            icon: const Icon(Icons.warning_amber_rounded,
                                color: AppColors.warning, size: 36),
                            title: Text(s.isAr
                                ? 'الموظّف مُدرَج في روستر آخر'
                                : 'Already in another roster'),
                            content: Text(s.isAr
                                ? 'هذا الموظّف مدرج في روستر «${status!.otherRosterPointName}» لنفس الأسبوع. سيتمّ فحص تعارض الأوقات عند تعيين الورديات. متابعة الإضافة؟'
                                : 'This employee is already in roster «${status!.otherRosterPointName}» for the same week. Time conflicts will be validated when assigning shifts. Continue?'),
                            actions: [
                              TextButton(
                                  onPressed: () =>
                                      Navigator.pop(ctx, false),
                                  child: Text(
                                      s.isAr ? ar2ur.tr('إلغاء') : 'Cancel')),
                              ElevatedButton(
                                  onPressed: () =>
                                      Navigator.pop(ctx, true),
                                  child: Text(s.isAr
                                      ? 'أضف رغم ذلك'
                                      : 'Add anyway')),
                            ],
                          ),
                        );
                        if (confirm != true) return;
                      }
                      await widget.onAdd(emp);
                      if (!mounted) return;
                      Navigator.of(context).pop();
                    },
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

/// 🆕 شارة حالة في بطاقة الموظّف (مربوط بنقطة / مدرج في روستر آخر).
class _StatusBadge extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;
  const _StatusBadge({
    required this.color,
    required this.icon,
    required this.text,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 🔥 إضافة جماعية للموظفين (Multi-select + نمط جاهز)
// ============================================================
class RosterBulkAddSheet extends StatefulWidget {
  final List<Employee> available;
  final Future<void> Function(List<Employee>, RosterPatternConfig) onAddBulk;
  final DateTime weekStart;
  final String excludeRosterId;
  const RosterBulkAddSheet({
    super.key,
    required this.available,
    required this.onAddBulk,
    required this.weekStart,
    required this.excludeRosterId,
  });

  @override
  State<RosterBulkAddSheet> createState() => _RosterBulkAddSheetState();
}

class _RosterBulkAddSheetState extends State<RosterBulkAddSheet> {
  final Set<String> _selected = {};
  String _query = '';
  RosterPatternConfig? _pattern;

  @override
  void initState() {
    super.initState();
    final patterns = RosterSettings.instance.patterns;
    if (patterns.isNotEmpty) _pattern = patterns.first;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final patterns = RosterSettings.instance.patterns;
    _pattern ??= patterns.isNotEmpty ? patterns.first : null;
    final filtered = widget.available.where((e) {
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return e.fullName.toLowerCase().contains(q) ||
          e.code.toLowerCase().contains(q);
    }).toList();
    final patternLabel = _pattern == null
        ? (s.isAr ? ar2ur.tr('— لا يوجد نمط') : '— No pattern')
        : (s.isAr ? _pattern!.nameAr : _pattern!.nameEn);

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).dividerColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  s.isAr ? ar2ur.tr('إضافة جماعية للموظفين') : 'Bulk Add Employees',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                // ===== اختيار النمط =====
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.brand.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.brand.withOpacity(0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.auto_awesome,
                              size: 14, color: AppColors.brand),
                          const SizedBox(width: 6),
                          Text(
                            s.isAr
                                ? 'النمط الافتراضي: $patternLabel'
                                : 'Default pattern: $patternLabel',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.brand),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: patterns.map((p) {
                          final selected = _pattern?.id == p.id;
                          return ChoiceChip(
                            label: Text(s.isAr ? p.nameAr : p.nameEn,
                                style: const TextStyle(fontSize: 11)),
                            selected: selected,
                            onSelected: (_) => setState(() => _pattern = p),
                          );
                        }).toList(),
                      ),
                      if (patterns.isEmpty)
                        Text(
                          s.isAr
                              ? 'لا توجد أنماط — اضبطها من الإعدادات → الروسترات'
                              : 'No patterns — configure in Settings → Rosters',
                          style: const TextStyle(
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                              color: AppColors.textTertiaryLight),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  decoration: InputDecoration(
                    hintText: s.search,
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ],
            ),
          ),
          // عدّاد الاختيار
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Text(
                  s.isAr
                      ? 'المختار: ${_selected.length} / ${filtered.length}'
                      : 'Selected: ${_selected.length} / ${filtered.length}',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                TextButton(
                  onPressed: filtered.isEmpty
                      ? null
                      : () {
                          setState(() {
                            if (_selected.length == filtered.length) {
                              _selected.clear();
                            } else {
                              _selected
                                ..clear()
                                ..addAll(filtered.map((e) => e.id));
                            }
                          });
                        },
                  child: Text(
                    _selected.length == filtered.length && filtered.isNotEmpty
                        ? (s.isAr ? ar2ur.tr('إلغاء التحديد') : 'Deselect all')
                        : (s.isAr ? ar2ur.tr('تحديد الكل') : 'Select all'),
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (_, i) {
                final emp = filtered[i];
                final selected = _selected.contains(emp.id);
                return CheckboxListTile(
                  dense: true,
                  value: selected,
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _selected.add(emp.id);
                      } else {
                        _selected.remove(emp.id);
                      }
                    });
                  },
                  secondary: EmployeeAvatar(
                      employee: emp, radius: 16, color: AppColors.brand),
                  title: Text(emp.fullName,
                      style: const TextStyle(fontSize: 13)),
                  subtitle: Text('${emp.code} • ${emp.jobTitle}',
                      style: const TextStyle(fontSize: 11)),
                );
              },
            ),
          ),
          // زرار الإضافة
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color,
                border: Border(
                  top: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(s.cancel),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: (_selected.isEmpty || _pattern == null)
                          ? null
                          : () async {
                              final selectedEmps = widget.available
                                  .where((e) => _selected.contains(e.id))
                                  .toList();
                              await widget.onAddBulk(selectedEmps, _pattern!);
                              if (!mounted) return;
                              Navigator.of(context).pop();
                            },
                      icon: const Icon(Icons.group_add, size: 16),
                      label: Text(
                        s.isAr
                            ? 'أضف ${_selected.length} وطبّق النمط'
                            : 'Add ${_selected.length} & Apply',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 🆕 شاشة اختيار النقطة للمدير (إذا كان لديه صلاحيّة rostersSelectAnyPoint)
// ============================================================
class _ManagerPointPicker extends StatefulWidget {
  final ValueChanged<String> onSelected;
  const _ManagerPointPicker({required this.onSelected});

  @override
  State<_ManagerPointPicker> createState() => _ManagerPointPickerState();
}

class _ManagerPointPickerState extends State<_ManagerPointPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final repo = MockRepository();
    final theme = Theme.of(context);

    final all = repo.points
        .where((p) => p.status == EntityStatus.active)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? all
        : all
            .where((p) =>
                p.name.toLowerCase().contains(q) ||
                p.code.toLowerCase().contains(q))
            .toList();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.brand.withOpacity(0.10),
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: AppColors.brand.withOpacity(0.3)),
                ),
                child: const Icon(Icons.pin_drop_outlined,
                    color: AppColors.brand, size: 38),
              ),
              const SizedBox(height: 16),
              Text(
                isAr ? ar2ur.tr('اختر النقطة') : 'Select a point',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w900),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                isAr
                    ? 'بصلاحيّتك كـ مدير، يمكنك اختيار النقطة التي تريد إنشاء روستر لها.'
                    : 'As a Manager, you can pick the point you want to build the roster for.',
                style: TextStyle(
                    fontSize: 12,
                    color: theme.textTheme.bodySmall?.color),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextField(
                decoration: InputDecoration(
                  hintText:
                      isAr ? ar2ur.tr('بحث عن نقطة…') : 'Search points…',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: filtered.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          isAr
                              ? 'لا توجد نقاط'
                              : 'No points available',
                          style: TextStyle(
                              color: theme.textTheme.bodySmall?.color),
                        ),
                      )
                    : Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: theme.dividerColor),
                          borderRadius: BorderRadius.circular(10),
                          color: theme.cardColor,
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const Divider(
                              height: 1, indent: 12, endIndent: 12),
                          itemBuilder: (_, i) {
                            final p = filtered[i];
                            return ListTile(
                              leading: CircleAvatar(
                                radius: 16,
                                backgroundColor:
                                    AppColors.brand.withOpacity(0.12),
                                child: const Icon(Icons.location_on,
                                    color: AppColors.brand, size: 18),
                              ),
                              title: Text(p.name,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800)),
                              subtitle: p.code.isEmpty
                                  ? null
                                  : Text(p.code,
                                      style:
                                          const TextStyle(fontSize: 11)),
                              trailing: const Icon(Icons.arrow_forward,
                                  size: 16),
                              onTap: () => widget.onSelected(p.id),
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// رسائل غياب الإسناد
// ============================================================
enum NoAssignmentReason { notEmployee, noPoint }

class _NoAssignmentState extends StatelessWidget {
  final NoAssignmentReason reason;
  const _NoAssignmentState({required this.reason});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isNotEmployee = reason == NoAssignmentReason.notEmployee;
    final icon =
        isNotEmployee ? Icons.admin_panel_settings_outlined : Icons.location_off;
    final title = isNotEmployee
        ? (s.isAr
            ? 'هذه الشاشة مخصّصة للمشرفين'
            : 'This screen is for Supervisors only')
        : (s.isAr ? ar2ur.tr('لم يتم ربطك بنقطة بعد') : 'Not assigned to a Point yet');
    final body = isNotEmployee
        ? (s.isAr
            ? 'حسابك ليس مرتبطاً بسجل موظف (مشرف). للاختبار: أنشئ مشرفاً من قسم الموظفين، أنشئ له حساب مستخدم وربطه به، ثم سجّل الدخول بحسابه.'
            : 'Your account is not linked to a Supervisor employee record. To test: create a supervisor in Employees, create a user account linked to them, then login as that user.')
        : (s.isAr
            ? 'يجب أن يقوم Operation بربط حسابك بنقطة لتتمكن من إنشاء روستر. تواصل معهم.'
            : 'Operation must assign you to a Point before you can create rosters. Please contact them.');
    final color = isNotEmployee ? AppColors.info : AppColors.warning;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 40),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).disabledColor,
                  height: 1.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
