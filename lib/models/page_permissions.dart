/// 🔐 نظام الصلاحيّات الموحَّد — لكلّ صفحة 4 صلاحيّات قياسيّة:
///
///   `<page>.view`    — قراءة فقط (عرض)
///   `<page>.create`  — إضافة سجلّ جديد
///   `<page>.edit`    — تعديل سجلّ موجود
///   `<page>.delete`  — حذف سجلّ
///
/// الاستخدام:
/// ```dart
/// final perms = PagePermissions.employees;
/// if (auth.hasPermission(perms.view)) { ... }
/// if (auth.hasPermission(perms.delete)) { ... }
/// ```
///
/// كذلك يمكن سؤال الـ class مباشرة:
/// ```dart
/// PagePermissions.employees.view  // → 'employees.view'
/// PagePermissions.attendance.create // → 'attendance.create'
/// ```
class PagePerm {
  /// الـ resource key (employees, attendance, …)
  final String key;
  const PagePerm(this.key);

  String get view   => '$key.view';
  String get create => '$key.create';
  String get edit   => '$key.edit';
  String get delete => '$key.delete';

  /// كلّ الصلاحيّات الـ4 — مفيد عند البذرة (seeding).
  List<String> get all => [view, create, edit, delete];

  /// (V/E/C/D) — مرتّبة بحسب الشيوع.
  String operator [](String op) {
    switch (op) {
      case 'view':   return view;
      case 'create': return create;
      case 'edit':   return edit;
      case 'delete': return delete;
      default:
        throw ArgumentError('Unknown operation: $op');
    }
  }
}

/// 📚 السجلّ المركزي للصفحات — يضمن أنّ كلّ صفحة في التطبيق لها 4
/// صلاحيّات قياسيّة (view/create/edit/delete) تحت مفتاح موحَّد.
///
/// عند إضافة شاشة جديدة في التطبيق:
///   1) أضف `PagePerm` هنا.
///   2) أضفها لـ `PagePermissions.allPages` في الأسفل.
///   3) ضع الـ4 صلاحيّات في `seedPermissions` ضمن `rbac_seed.dart`
///      (يحدث تلقائياً لو استخدمت `_seedPagePerms` المرفقة).
///   4) امنح الصلاحيّات للأدوار في `permission_templates.dart`.
class PagePermissions {
  PagePermissions._();

  // ============================================================
  // 1️⃣ الرئيسيّة
  // ============================================================
  static const home = PagePerm('home');
  static const dashboards = PagePerm('dashboards');

  // ============================================================
  // 2️⃣ المؤسّسة (Organization)
  // ============================================================
  static const countries = PagePerm('countries');
  static const departments = PagePerm('departments');
  static const jobTitles = PagePerm('job_titles');
  static const points = PagePerm('points'); // alias لـ sites
  static const customers = PagePerm('customers');
  static const branches = PagePerm('branches');
  static const orgChart = PagePerm('org_chart');
  static const numbering = PagePerm('numbering');

  // ============================================================
  // 3️⃣ الموارد البشريّة
  // ============================================================
  static const employees = PagePerm('employees');
  static const employeeDocuments = PagePerm('employee_documents');
  static const onPointTraining = PagePerm('on_point_training');
  static const trainingCourses = PagePerm('training_courses');
  static const training = PagePerm('training');

  /// 🆕 الحضور والانصراف (تحت HR)
  static const attendance = PagePerm('attendance');
  static const attendanceReports = PagePerm('attendance_reports');

  /// التقييمات
  static const evaluations = PagePerm('evaluations');
  static const evaluationCriteria = PagePerm('evaluation_criteria');

  /// الرواتب والخصومات
  static const deductions = PagePerm('deductions');
  static const payroll = PagePerm('payroll');

  // ============================================================
  // 4️⃣ الروسترات
  // ============================================================
  static const rosters = PagePerm('rosters');
  static const rosterApprovals = PagePerm('roster_approvals');
  static const rosterSettings = PagePerm('roster_settings');

  // ============================================================
  // 5️⃣ النقل
  // ============================================================
  static const buses = PagePerm('buses');
  static const drivers = PagePerm('drivers');
  static const busPlans = PagePerm('bus_plans');
  static const tracking = PagePerm('tracking');
  static const routeMaps = PagePerm('route_maps');
  static const employeeBusAssignment = PagePerm('employee_bus_assignment');

  // ============================================================
  // 6️⃣ الكمب
  // ============================================================
  static const rooms = PagePerm('rooms');
  static const laundry = PagePerm('laundry');
  static const uniforms = PagePerm('uniforms');
  static const violations = PagePerm('violations');
  static const checklists = PagePerm('checklists');
  static const campBuses = PagePerm('camp_buses');

  // ============================================================
  // 7️⃣ السائق
  // ============================================================
  static const driverTrips = PagePerm('driver_trips');

  // ============================================================
  // 8️⃣ الموظف (شاشاتي)
  // ============================================================
  static const myRoster = PagePerm('my_roster');
  static const mySchedule = PagePerm('my_schedule');
  static const myUniform = PagePerm('my_uniform');
  static const myDeductions = PagePerm('my_deductions');
  static const myEvaluations = PagePerm('my_evaluations');
  static const myForms = PagePerm('my_forms');

  // ============================================================
  // 9️⃣ النماذج
  // ============================================================
  static const forms = PagePerm('forms');
  static const formApprovals = PagePerm('form_approvals');
  static const workflows = PagePerm('workflows');

  // ============================================================
  // 🔟 التقارير
  // ============================================================
  static const reports = PagePerm('reports');

  // ============================================================
  // 1️⃣1️⃣ الإدارة والإعدادات
  // ============================================================
  static const policies = PagePerm('policies');
  static const settings = PagePerm('settings');
  static const users = PagePerm('users');
  static const roles = PagePerm('roles');
  static const permissionsMatrix = PagePerm('permissions_matrix');
  static const auditLog = PagePerm('audit_log');
  static const deviceSessions = PagePerm('device_sessions');
  static const geoFence = PagePerm('geo_fence');
  static const loginMethod = PagePerm('login_method');
  static const faceEnrollments = PagePerm('face_enrollments');

  // ============================================================
  // 📋 سجلّ كلّ الصفحات (للـ seeding التلقائي)
  // ============================================================
  static const List<PagePerm> allPages = [
    // 1) Home
    home, dashboards,
    // 2) Organization
    countries, departments, jobTitles, points, customers, branches,
    orgChart, numbering,
    // 3) HR
    employees, employeeDocuments, onPointTraining, trainingCourses, training,
    attendance, attendanceReports,
    evaluations, evaluationCriteria,
    deductions, payroll,
    // 4) Rosters
    rosters, rosterApprovals, rosterSettings,
    // 5) Transport
    buses, drivers, busPlans, tracking, routeMaps, employeeBusAssignment,
    // 6) Camp
    rooms, laundry, uniforms, violations, checklists, campBuses,
    // 7) Driver
    driverTrips,
    // 8) My screens
    myRoster, mySchedule, myUniform, myDeductions, myEvaluations, myForms,
    // 9) Forms
    forms, formApprovals, workflows,
    // 10) Reports
    reports,
    // 11) Admin
    policies, settings, users, roles, permissionsMatrix,
    auditLog, deviceSessions, geoFence, loginMethod, faceEnrollments,
  ];

  /// كلّ المفاتيح الـ4 لكلّ الصفحات — مفيد لـ seedPermissions.
  static List<String> get allKeys =>
      allPages.expand((p) => p.all).toList();
}
