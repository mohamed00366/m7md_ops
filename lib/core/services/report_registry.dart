// =============================================================================
// 📚 ReportRegistry — يُعَرِّف ما هي المَصادِر المُتاحة وَما هي أَعمِدتها
// =============================================================================
// لِكُلّ `ReportSource` نُعَرِّف:
//   • قائمة الأَعمِدة المُتاحة (بِالعَرَبيّة وَالإنجليزيّة)
//   • نَوع كُلّ عَمود (نَصّ / رَقم / تاريخ / boolean / lookup)
//   • مُستَخرِج (extractor) يَأخُذ السَجِلّ مِن MockRepository وَيُرجِع قيمة العَمود
//   • مَوضَع الـlookup إن وُجِد (لِتَحويل ID إلى اسم في عَرض/تَصدير)
// =============================================================================

import '../../models/custom_report.dart';
import '../../models/leave.dart';
import '../../models/lookups.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';
import 'leave_service.dart';

/// نَوع العَمود — يُحَدِّد الـUI لِلفِلتَر
enum ColumnType { text, number, date, boolean, lookup }

/// تَعريف عَمود في مَصدَر
class ReportColumnDef {
  final String key;
  final String labelAr;
  final String labelEn;
  final ColumnType type;
  final Object? Function(dynamic record) extract;
  /// لَو type == lookup — هذه دالّة تَحَوِّل ID إلى اسم لِلعَرض
  final String Function(String id, bool isAr)? lookupName;

  const ReportColumnDef({
    required this.key,
    required this.labelAr,
    required this.labelEn,
    required this.type,
    required this.extract,
    this.lookupName,
  });

  String label(bool isAr) => isAr ? labelAr : labelEn;
}

/// تَعريف مَصدَر — قائمة أَعمِدته + كَيف نَحصُل عَلى السَجِلّات
class ReportSourceDef {
  final ReportSource source;
  final String labelAr;
  final String labelEn;
  final List<ReportColumnDef> columns;
  final List<dynamic> Function() recordsLoader;

  const ReportSourceDef({
    required this.source,
    required this.labelAr,
    required this.labelEn,
    required this.columns,
    required this.recordsLoader,
  });

  String label(bool isAr) => isAr ? labelAr : labelEn;

  ReportColumnDef? column(String key) {
    for (final c in columns) {
      if (c.key == key) return c;
    }
    return null;
  }
}

/// السِجِلّ المَركَزيّ — يَعرِف ما يُمكِن بِناء تَقارير حَوله
class ReportRegistry {
  ReportRegistry._();
  static final ReportRegistry instance = ReportRegistry._();

  static MockRepository get _repo => MockRepository();

  // ==========================================================================
  // 🔍 lookups helpers
  // ==========================================================================
  static String _empName(String id, bool isAr) {
    final e = _repo.employeeById(id);
    if (e == null) return id;
    return e.fullName; // model has single-field fullName
  }

  static String _deptName(String id, bool isAr) {
    Department? d;
    for (final x in _repo.departments) {
      if (x.id == id) {
        d = x;
        break;
      }
    }
    if (d == null) return id;
    return isAr ? d.nameAr : d.nameEn;
  }

  static String _jobTitleName(String id, bool isAr) {
    final j = _repo.jobTitleById(id);
    if (j == null) return id;
    return isAr ? j.nameAr : j.nameEn;
  }

  static String _pointName(String id, bool isAr) {
    final p = _repo.pointById(id);
    if (p == null) return id;
    return p.name;
  }

  // ==========================================================================
  // كُلّ المَصادِر المُتاحة
  // ==========================================================================
  late final Map<ReportSource, ReportSourceDef> sources = {
    // ------------------------------------------------------------------------
    // 👥 EMPLOYEES
    // ------------------------------------------------------------------------
    ReportSource.employees: ReportSourceDef(
      source: ReportSource.employees,
      labelAr: '👥 المُوَظَّفون',
      labelEn: '👥 Employees',
      recordsLoader: () => _repo.employees,
      columns: [
        ReportColumnDef(
          key: 'full_name',
          labelAr: 'الاسم الكامِل',
          labelEn: 'Full name',
          type: ColumnType.text,
          extract: (e) => (e as Employee).fullName,
        ),
        ReportColumnDef(
          key: 'code',
          labelAr: 'الكود',
          labelEn: 'Code',
          type: ColumnType.text,
          extract: (e) => (e as Employee).code,
        ),
        ReportColumnDef(
          key: 'department_id',
          labelAr: 'القِسم',
          labelEn: 'Department',
          type: ColumnType.lookup,
          extract: (e) => (e as Employee).departmentId,
          lookupName: _deptName,
        ),
        ReportColumnDef(
          key: 'job_title_id',
          labelAr: 'المُسَمَّى الوَظيفيّ',
          labelEn: 'Job title',
          type: ColumnType.lookup,
          extract: (e) => (e as Employee).jobTitleId,
          lookupName: _jobTitleName,
        ),
        ReportColumnDef(
          key: 'status',
          labelAr: 'الحالة',
          labelEn: 'Status',
          type: ColumnType.text,
          extract: (e) => (e as Employee).status.name,
        ),
        ReportColumnDef(
          key: 'joining_date',
          labelAr: 'تاريخ التَعيين',
          labelEn: 'Joining date',
          type: ColumnType.date,
          extract: (e) => (e as Employee).joiningDate,
        ),
        ReportColumnDef(
          key: 'basic_salary',
          labelAr: 'الراتِب الأَساسيّ',
          labelEn: 'Basic salary',
          type: ColumnType.number,
          extract: (e) => (e as Employee).basicSalary,
        ),
        ReportColumnDef(
          key: 'nationality',
          labelAr: 'الجِنسيّة',
          labelEn: 'Nationality',
          type: ColumnType.text,
          extract: (e) => (e as Employee).nationality,
        ),
        ReportColumnDef(
          key: 'visa_type',
          labelAr: 'نَوع التَأشيرة',
          labelEn: 'Visa type',
          type: ColumnType.text,
          extract: (e) => (e as Employee).visaType,
        ),
        ReportColumnDef(
          key: 'point_id',
          labelAr: 'النُقطة',
          labelEn: 'Point',
          type: ColumnType.lookup,
          extract: (e) => (e as Employee).pointId,
          lookupName: _pointName,
        ),
      ],
    ),

    // ------------------------------------------------------------------------
    // 💸 DEDUCTIONS
    // ------------------------------------------------------------------------
    ReportSource.deductions: ReportSourceDef(
      source: ReportSource.deductions,
      labelAr: '💸 الخُصومات',
      labelEn: '💸 Deductions',
      recordsLoader: () => _repo.deductions,
      columns: [
        ReportColumnDef(
          key: 'employee_id',
          labelAr: 'المُوَظَّف',
          labelEn: 'Employee',
          type: ColumnType.lookup,
          extract: (d) => (d as Deduction).employeeId,
          lookupName: _empName,
        ),
        ReportColumnDef(
          key: 'amount',
          labelAr: 'المَبلَغ',
          labelEn: 'Amount',
          type: ColumnType.number,
          extract: (d) => (d as Deduction).amount,
        ),
        ReportColumnDef(
          key: 'reason',
          labelAr: 'السَبَب',
          labelEn: 'Reason',
          type: ColumnType.text,
          extract: (d) => (d as Deduction).reason,
        ),
        ReportColumnDef(
          key: 'date',
          labelAr: 'التاريخ',
          labelEn: 'Date',
          type: ColumnType.date,
          extract: (d) => (d as Deduction).date,
        ),
        ReportColumnDef(
          key: 'added_by',
          labelAr: 'أَضافَه',
          labelEn: 'Added by',
          type: ColumnType.text,
          extract: (d) => (d as Deduction).addedBy,
        ),
      ],
    ),

    // ------------------------------------------------------------------------
    // 🌴 LEAVES
    // ------------------------------------------------------------------------
    ReportSource.leaves: ReportSourceDef(
      source: ReportSource.leaves,
      labelAr: '🌴 الإجازات',
      labelEn: '🌴 Leaves',
      recordsLoader: () => LeaveService.instance.requests,
      columns: [
        ReportColumnDef(
          key: 'employee_id',
          labelAr: 'المُوَظَّف',
          labelEn: 'Employee',
          type: ColumnType.lookup,
          extract: (l) => (l as LeaveRequest).employeeId,
          lookupName: _empName,
        ),
        ReportColumnDef(
          key: 'leave_type',
          labelAr: 'النَوع',
          labelEn: 'Type',
          type: ColumnType.text,
          extract: (l) => (l as LeaveRequest).leaveType.name,
        ),
        ReportColumnDef(
          key: 'start_date',
          labelAr: 'مِن',
          labelEn: 'From',
          type: ColumnType.date,
          extract: (l) => (l as LeaveRequest).startDate,
        ),
        ReportColumnDef(
          key: 'end_date',
          labelAr: 'إلى',
          labelEn: 'To',
          type: ColumnType.date,
          extract: (l) => (l as LeaveRequest).endDate,
        ),
        ReportColumnDef(
          key: 'days_count',
          labelAr: 'الأَيّام',
          labelEn: 'Days',
          type: ColumnType.number,
          extract: (l) => (l as LeaveRequest).daysCount,
        ),
        ReportColumnDef(
          key: 'status',
          labelAr: 'الحالة',
          labelEn: 'Status',
          type: ColumnType.text,
          extract: (l) => (l as LeaveRequest).status.name,
        ),
      ],
    ),

    // ------------------------------------------------------------------------
    // 💰 DRIVER TIPS — يَتَحَمَّل بَيانات مِن Supabase (Runner يُمَرِّر السَجِلّات)
    // ------------------------------------------------------------------------
    ReportSource.driverTips: ReportSourceDef(
      source: ReportSource.driverTips,
      labelAr: '💰 البَقاشيش',
      labelEn: '💰 Tips',
      recordsLoader: () => const <dynamic>[],
      columns: [
        ReportColumnDef(
          key: 'employee_id',
          labelAr: 'السائِق',
          labelEn: 'Driver',
          type: ColumnType.lookup,
          extract: (r) => (r as Map)['employee_id'],
          lookupName: _empName,
        ),
        ReportColumnDef(
          key: 'point_id',
          labelAr: 'النُقطة',
          labelEn: 'Point',
          type: ColumnType.lookup,
          extract: (r) => (r as Map)['point_id'],
          lookupName: _pointName,
        ),
        ReportColumnDef(
          key: 'amount',
          labelAr: 'المَبلَغ',
          labelEn: 'Amount',
          type: ColumnType.number,
          extract: (r) => (r as Map)['amount'],
        ),
        ReportColumnDef(
          key: 'source',
          labelAr: 'المَصدَر',
          labelEn: 'Source',
          type: ColumnType.text,
          extract: (r) => (r as Map)['source'],
        ),
        ReportColumnDef(
          key: 'tip_date',
          labelAr: 'التاريخ',
          labelEn: 'Date',
          type: ColumnType.date,
          extract: (r) => (r as Map)['tip_date'],
        ),
      ],
    ),

    // ------------------------------------------------------------------------
    // 📅 ROSTERS — Roster assignments (لا تَحوي تاريخ مُباشَرة، فَقَط dayIndex)
    // ------------------------------------------------------------------------
    ReportSource.rosters: ReportSourceDef(
      source: ReportSource.rosters,
      labelAr: '📅 الروسترات',
      labelEn: '📅 Rosters',
      recordsLoader: () => [
        for (final r in _repo.rosters) ...r.assignments,
      ],
      columns: [
        ReportColumnDef(
          key: 'employee_id',
          labelAr: 'المُوَظَّف',
          labelEn: 'Employee',
          type: ColumnType.lookup,
          extract: (r) => (r as RosterAssignment).employeeId,
          lookupName: _empName,
        ),
        ReportColumnDef(
          key: 'day_index',
          labelAr: 'اليَوم (0=الإثنين..6=الأَحَد)',
          labelEn: 'Day index',
          type: ColumnType.number,
          extract: (r) => (r as RosterAssignment).dayIndex,
        ),
        ReportColumnDef(
          key: 'start_time',
          labelAr: 'البِداية',
          labelEn: 'Start',
          type: ColumnType.text,
          extract: (r) => (r as RosterAssignment).startTime,
        ),
        ReportColumnDef(
          key: 'end_time',
          labelAr: 'النِهاية',
          labelEn: 'End',
          type: ColumnType.text,
          extract: (r) => (r as RosterAssignment).endTime,
        ),
        ReportColumnDef(
          key: 'shift_type',
          labelAr: 'نَوع الوَردِيّة',
          labelEn: 'Shift type',
          type: ColumnType.text,
          extract: (r) => (r as RosterAssignment).shiftType.name,
        ),
        ReportColumnDef(
          key: 'reviewer_flag',
          labelAr: 'يَحتاج مُراجَعة',
          labelEn: 'Needs review',
          type: ColumnType.boolean,
          extract: (r) => (r as RosterAssignment).reviewerFlag,
        ),
      ],
    ),
  };

  ReportSourceDef? get(ReportSource s) => sources[s];

  List<ReportSourceDef> all() => sources.values.toList();
}
