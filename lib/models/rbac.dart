/// نماذج نظام الصلاحيات (Role-Based Access Control)
/// تستخدم في Mock أولاً ثم تُهاجَر إلى Supabase
library;

/// 🆕 نَوع الحِساب
///
/// - `employee`: حِساب مُوَظَّف شَخصيّ (الافتِراضيّ — كُلّ الحِسابات الحاليّة)
/// - `pointTerminal`: حِساب جِهاز نُقطة في Kiosk Mode لِتَسجيل دَوام الفَريق
///   بِبَصمة الوَجه. لا يَستَخدِم لِلعَمَل اليَوميّ، فَقَط شاشة مُحَدَّدة.
enum AccountType { employee, pointTerminal }

extension AccountTypeX on AccountType {
  String get key {
    switch (this) {
      case AccountType.employee:
        return 'employee';
      case AccountType.pointTerminal:
        return 'point_terminal';
    }
  }

  static AccountType fromKey(String? k) {
    switch (k) {
      case 'point_terminal':
        return AccountType.pointTerminal;
      case 'employee':
      default:
        return AccountType.employee;
    }
  }
}

class AppAccount {
  final String id;
  String username;
  String passwordHash; // في Mock نخزّن النص العادي مؤقتاً
  String fullName;
  String? email;
  String? phone;
  String? employeeId; // ربط بسجل الموظف إن وُجد
  bool isActive;
  bool isSuperAdmin; // علم خاص لمستخدم Super Admin
  /// 🆕 إذا true → يُجبَر المستخدم على تَغيير كلمة المرور عند أوَّل دُخول.
  /// يُستَعمَل عند الإنشاء التلقائيّ بِكلمة مرور مُؤَقَّتة.
  bool mustChangePassword;

  /// 🆕 إذا true → يَجِب على المُستَخدِم تَسجيل بَصمة وَجه قَبل اكتِمال أَوَّل دُخول.
  /// تُضبَط تِلقائيّاً بِناءً على `FaceEnrollmentPolicySettings`
  /// عَند إنشاء الحِساب لِمُوظَّفين ضِمن المُسَمَّيات المَشمولة بِالسياسة.
  bool mustEnrollFace;

  /// 🆕 وَقت أَوَّل دُخول ناجِح — لِحِساب مُهلة التَأجيل (grace period).
  DateTime? firstLoginAt;

  /// 🆕 وَقت اكتِمال تَسجيل بَصمة الوَجه (يُلغي mustEnrollFace).
  DateTime? faceEnrolledAt;

  /// 🆕 نَوع الحِساب: مُوَظَّف عاديّ أَم جِهاز نُقطة (Kiosk).
  AccountType accountType;

  /// 🆕 مَعرّف النُقطة المَربوطة بِالحِساب (لِنَوع pointTerminal فَقَط).
  String? pointId;

  /// 🆕 مَعرّف الجِهاز المَربوط بِالحِساب (Device Binding — legacy).
  /// مع دَعم تَعَدُّد الأَجهِزة، الجَلسات في point_terminal_sessions
  /// هي المَصدَر الرَسميّ. يُحفَظ هُنا أَوَّل جِهاز فَقَط لِلتَوافُق الخَلفيّ.
  String? linkedDeviceId;

  /// 🆕 الحَدّ الأَقصى لِعَدَد الأَجهِزة المَربوطة لِحِساب Terminal.
  /// `0` = بِدون حَدّ. عِندَ بُلوغ الحَدّ، يُرفَض دُخول جِهاز جَديد
  /// حَتّى يَتِم فَكّ رَبط أَحَد الأَجهِزة من قِبَل المَسؤول.
  int maxDevices;

  DateTime? lastLoginAt;
  final DateTime createdAt;

  AppAccount({
    required this.id,
    required this.username,
    required this.passwordHash,
    required this.fullName,
    this.email,
    this.phone,
    this.employeeId,
    this.isActive = true,
    this.isSuperAdmin = false,
    this.mustChangePassword = false,
    this.mustEnrollFace = false,
    this.firstLoginAt,
    this.faceEnrolledAt,
    this.accountType = AccountType.employee,
    this.pointId,
    this.linkedDeviceId,
    this.maxDevices = 0,
    this.lastLoginAt,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// 🆕 اختِصار: هَل هذا حِساب جِهاز نُقطة؟
  bool get isPointTerminal => accountType == AccountType.pointTerminal;

  String get initials {
    final p = fullName.trim().split(RegExp(r'\s+'));
    if (p.isEmpty || p[0].isEmpty) return '?';
    if (p.length == 1) return p[0].substring(0, 1).toUpperCase();
    return (p[0].substring(0, 1) + p[1].substring(0, 1)).toUpperCase();
  }
}

/// تعريف دور (Role)
class RoleDef {
  final String id;
  final String key; // مثل: 'manager', 'supervisor'
  String nameAr;
  String nameEn;
  String? descriptionAr;
  String? descriptionEn;
  final bool isSystem; // أدوار النظام لا تُحذف
  int priority; // 100 = أعلى. للترتيب الافتراضي

  RoleDef({
    required this.id,
    required this.key,
    required this.nameAr,
    required this.nameEn,
    this.descriptionAr,
    this.descriptionEn,
    this.isSystem = false,
    this.priority = 0,
  });
}

/// تعريف صلاحية محددة
class PermissionDef {
  final String id;
  final String key; // مثل: 'roster.approve'
  final String module; // مثل: 'roster', 'employee', 'admin'
  String nameAr;
  String nameEn;
  String? descriptionAr;
  String? descriptionEn;

  PermissionDef({
    required this.id,
    required this.key,
    required this.module,
    required this.nameAr,
    required this.nameEn,
    this.descriptionAr,
    this.descriptionEn,
  });
}

/// ربط بين دور وصلاحية (الصلاحيات الافتراضية للدور)
class RolePermissionLink {
  final String roleId;
  final String permissionId;
  RolePermissionLink({required this.roleId, required this.permissionId});
}

/// تعيين دور لمستخدم (مع نطاق اختياري)
class UserRoleAssignment {
  final String id;
  final String userId;
  final String roleId;
  final String? countryId; // إذا = null فالدور صالح لكل دول المستخدم
  final String? siteId; // إذا = null فالدور صالح لكل المواقع
  final DateTime assignedAt;

  UserRoleAssignment({
    required this.id,
    required this.userId,
    required this.roleId,
    this.countryId,
    this.siteId,
    DateTime? assignedAt,
  }) : assignedAt = assignedAt ?? DateTime.now();
}

/// override لصلاحية على مستوى المستخدم
/// granted = true يضيف صلاحية، false يسحب صلاحية يحملها افتراضياً
class UserPermissionOverride {
  final String id;
  final String userId;
  final String permissionId;
  bool granted;
  String? reason;
  final DateTime createdAt;

  UserPermissionOverride({
    required this.id,
    required this.userId,
    required this.permissionId,
    required this.granted,
    this.reason,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
}

/// ربط المستخدم بالدول التي يصلها
class UserCountryAccess {
  final String userId;
  final String countryId;
  UserCountryAccess({required this.userId, required this.countryId});
}

/// سجل الأنشطة (Audit Log)
class AuditEntry {
  final String id;
  final String userId;
  final String action; // مثل: 'login', 'create_user', 'change_role'
  final String? targetType; // مثل: 'user', 'roster'
  final String? targetId;
  String? details;
  String? ipAddress;
  final DateTime at;

  AuditEntry({
    required this.id,
    required this.userId,
    required this.action,
    this.targetType,
    this.targetId,
    this.details,
    this.ipAddress,
    DateTime? at,
  }) : at = at ?? DateTime.now();
}

/// أدوار النظام (مفاتيح ثابتة)
class SystemRoles {
  static const superAdmin = 'super_admin';
  static const admin = 'admin';
  static const manager = 'manager';
  static const operation = 'operation';
  static const supervisor = 'supervisor';
  static const campBoss = 'camp_boss';
  static const driver = 'driver';
  static const employee = 'employee';

  /// ترتيب الأولوية للدخول الافتراضي (الأعلى أولاً)
  static const priorities = {
    superAdmin: 100,
    admin: 90,
    manager: 80,
    operation: 70,
    supervisor: 60,
    campBoss: 50,
    driver: 40,
    employee: 30,
  };
}

/// مفاتيح الصلاحيات (تجميع لمنع الأخطاء الإملائية)
class P {
  // ===== Admin =====
  static const adminUsersView = 'admin.users.view';
  static const adminUsersManage = 'admin.users.manage'; // legacy bundle
  static const adminUsersCreate = 'admin.users.create'; // 🆕
  static const adminUsersEdit = 'admin.users.edit'; // 🆕
  static const adminUsersDelete = 'admin.users.delete'; // 🆕
  static const adminRolesManage = 'admin.roles.manage';
  static const adminAuditView = 'admin.audit.view';
  static const adminCountriesManage = 'admin.countries.manage';
  static const adminPasswordReset = 'admin.password.reset';

  // ===== Dashboard =====
  static const dashboardManagerView = 'dashboard.manager.view';
  static const dashboardOperationView = 'dashboard.operation.view';
  static const dashboardCampView = 'dashboard.camp.view';

  // ===== Sites/Customers =====
  static const sitesView = 'sites.view';
  static const sitesCreate = 'sites.create';
  static const sitesEdit = 'sites.edit';
  static const sitesDelete = 'sites.delete';

  // ===== Employees =====
  static const employeesView = 'employees.view';
  static const employeesCreate = 'employees.create';
  static const employeesEdit = 'employees.edit';
  static const employeesActivate = 'employees.activate';
  static const employeesDelete = 'employees.delete';

  // ===== Buses =====
  static const busesView = 'buses.view';
  static const busesCreate = 'buses.create';
  static const busesEdit = 'buses.edit';
  static const busesAssign = 'buses.assign';
  static const busesDelete = 'buses.delete';

  // ===== Rosters =====
  static const rostersView = 'rosters.view';
  static const rostersCreate = 'rosters.create';
  static const rostersSubmit = 'rosters.submit';
  static const rostersApprove = 'rosters.approve';
  static const rostersReject = 'rosters.reject';
  static const rostersEditApproved = 'rosters.edit_approved';
  /// 🆕 يسمح للمستخدم بإنشاء روستر لأيّ نقطة (بدون اشتراط
  /// أن يكون مرتبطاً بنقطة معيّنة من قِبل Operation). تُمنح عادةً للمدير.
  static const rostersSelectAnyPoint = 'rosters.select_any_point';

  // ===== Camp =====
  static const campRoomsView = 'camp.rooms.view';
  static const campRoomsRate = 'camp.rooms.rate';
  static const campRoomsCreate = 'camp.rooms.create'; // 🆕
  static const campRoomsEdit = 'camp.rooms.edit'; // 🆕
  static const campRoomsDelete = 'camp.rooms.delete'; // 🆕
  static const campLaundryView = 'camp.laundry.view';
  static const campLaundryProcess = 'camp.laundry.process';
  static const campLaundryCreate = 'camp.laundry.create'; // 🆕
  static const campLaundryEdit = 'camp.laundry.edit'; // 🆕
  static const campLaundryDelete = 'camp.laundry.delete'; // 🆕
  // 🆕 نِظام أَمانة — صَلاحِيّات تَفصيلِيّة
  static const amanaDirectReceive = 'amana.direct_receive';
  static const amanaConfirmRequest = 'amana.confirm_request';
  static const amanaCreateBatch = 'amana.create_batch';
  static const amanaReceiveBatch = 'amana.receive_batch';
  static const amanaResolveReport = 'amana.resolve_report';
  static const amanaScheduleEdit = 'amana.schedule.edit';
  static const amanaReportsView = 'amana.reports.view';
  static const campViolationsView = 'camp.violations.view';
  static const campViolationsCreate = 'camp.violations.create';
  static const campViolationsApprove = 'camp.violations.approve';
  static const campViolationsEdit = 'camp.violations.edit'; // 🆕
  static const campViolationsDelete = 'camp.violations.delete'; // 🆕
  static const campChecklistView = 'camp.checklist.view';
  static const campChecklistCreate = 'camp.checklist.create';
  static const campChecklistEdit = 'camp.checklist.edit'; // 🆕
  static const campChecklistDelete = 'camp.checklist.delete'; // 🆕

  // ===== 🆕 Attendance (تحت HR) — CRUD كامل =====
  /// عرض شاشة "إدارة الحضور" + تقارير الحضور
  static const attendanceView = 'attendance.view';
  /// تسجيل حالة حضور لموظّف (حاضر/غائب/متأخّر)
  static const attendanceCreate = 'attendance.create';
  /// تعديل حالة حضور سُجِّلت سابقاً
  static const attendanceEdit = 'attendance.edit';
  /// حذف سجلّ حضور
  static const attendanceDelete = 'attendance.delete';
  /// تصدير تقارير الحضور (PDF/Excel)
  static const attendanceExport = 'attendance.export';

  // ===== Driver =====
  static const driverTripsView = 'driver.trips.view';
  static const driverAttendanceMark = 'driver.attendance.mark';

  // ===== Employee =====
  static const employeeScheduleView = 'employee.schedule.view';
  static const employeeUniformView = 'employee.uniform.view';
  static const employeeRequestsCreate = 'employee.requests.create';
  static const employeeDocumentsManage = 'employee.documents.manage';

  // ===== Training (📜) =====
  static const trainingView = 'training.view';      // الكل يرى دوراته
  static const trainingManage = 'training.manage';  // CRUD الدورات
  static const trainingRecord = 'training.record';  // تسجيل إكمال دورة لموظف
  static const trainingReport = 'training.report';  // تقارير + تصدير

  // ===== OnPoint Training (🎓 تدريب الموظف الجديد على نقطة) =====
  /// رؤية صفحة "تدريب الجدد" في HR Hub
  static const trainingOnPointView = 'training.onpoint.view';
  /// اعتماد/رفض المتدرّب (Operation Manager وما فوق)
  static const trainingOnPointEvaluate = 'training.onpoint.evaluate';
  /// إعدادات صفحة التدريب (Admin فقط)
  static const trainingOnPointManage = 'training.onpoint.manage';

  // ===== Tracking =====
  static const trackingLiveView = 'tracking.live.view';

  // ===== Reports =====
  static const reportsView = 'reports.view';
  static const reportsExport = 'reports.export';

  // 📊 Custom Report Builder (2026-05-23)
  static const reportsCustomView   = 'reports.custom.view';
  static const reportsCustomCreate = 'reports.custom.create';
  static const reportsCustomDelete = 'reports.custom.delete';

  // ===== Reports (dedicated per-screen) =====
  /// 🚨 Smart Alerts — لَوحة التَنبيهات الذَكيّة (مَركَزة لِلتَنبيهات الحَرِجة وَالعاجِلة)
  static const reportsSmartAlertsView = 'reports.smart_alerts.view';

  /// 📊 Analytics Dashboard — رُسوم بَيانيّة وَKPIs
  static const reportsAnalyticsView = 'reports.analytics.view';

  /// 🔍 Data Quality — تَقييم جَودة البَيانات
  static const reportsDataQualityView = 'reports.data_quality.view';

  /// 📅 Company Calendar — تَقويم الأَحداث المُؤَسَّسيّة
  static const reportsCompanyCalendarView = 'reports.company_calendar.view';

  // ===== Settings =====
  static const settingsLookupsView = 'settings.lookups.view';
  static const settingsLookupsEdit = 'settings.lookups.edit';
  static const settingsLookupsCreate = 'settings.lookups.create';
  static const settingsLookupsDelete = 'settings.lookups.delete';
  static const settingsNumberingView = 'settings.numbering.view';
  static const settingsNumberingEdit = 'settings.numbering.edit';
  static const settingsSystemView = 'settings.system.view';
  static const settingsSystemEdit = 'settings.system.edit';

  // ===== 🆕 Settings — صفحات الإعدادات الفرعيّة (view/edit لكلّ منها) =====
  // المؤسّسة
  static const settingsOrgView = 'settings.org.view';
  static const settingsOrgEdit = 'settings.org.edit';
  // الروسترات
  static const settingsRosterView = 'settings.roster.view';
  static const settingsRosterEdit = 'settings.roster.edit';
  // النقل (الباصات + التتبّع)
  static const settingsBusView = 'settings.bus.view';
  static const settingsBusEdit = 'settings.bus.edit';
  static const settingsTrackingView = 'settings.tracking.view';
  static const settingsTrackingEdit = 'settings.tracking.edit';
  // الكمب
  static const settingsCampView = 'settings.camp.view';
  static const settingsCampEdit = 'settings.camp.edit';
  // الموارد البشرية
  static const settingsHrView = 'settings.hr.view';
  static const settingsHrEdit = 'settings.hr.edit';
  static const settingsDeductionView = 'settings.deduction.view';
  static const settingsDeductionEdit = 'settings.deduction.edit';
  static const settingsEvaluationView = 'settings.evaluation.view';
  static const settingsEvaluationEdit = 'settings.evaluation.edit';
  static const settingsTrainingView = 'settings.training.view';
  static const settingsTrainingEdit = 'settings.training.edit';

  // ===== Customer settings =====
  static const settingsCustomerView = 'settings.customer.view';
  static const settingsCustomerEdit = 'settings.customer.edit';
  // ===== Sessions / Security settings =====
  static const settingsSessionView = 'settings.session.view';
  static const settingsSessionEdit = 'settings.session.edit';
  static const settingsDeviceSessionView = 'settings.device_session.view';
  static const settingsDeviceSessionEdit = 'settings.device_session.edit';
  static const settingsGeoFenceView = 'settings.geofence.view';
  static const settingsGeoFenceEdit = 'settings.geofence.edit';
  static const settingsLoginMethodView = 'settings.login_method.view';
  static const settingsLoginMethodEdit = 'settings.login_method.edit';
  static const settingsFaceEmbeddingsView = 'settings.face_embeddings.view';
  static const settingsFaceEmbeddingsManage = 'settings.face_embeddings.manage';
  // ===== Admin tools =====
  static const settingsLogViewerView = 'settings.log_viewer.view';
  static const settingsConfigExportView = 'settings.config_export.view';
  static const settingsConfigExportManage = 'settings.config_export.manage';
  static const settingsClearRostersManage = 'settings.clear_rosters.manage';
  static const settingsBulkOpsView = 'settings.bulk_ops.view';
  static const settingsBulkOpsManage = 'settings.bulk_ops.manage';

  // ===== Policies =====
  static const policiesView = 'policies.view';
  static const policiesCreate = 'policies.create';
  static const policiesEdit = 'policies.edit';
  static const policiesDelete = 'policies.delete';

  // ===== Evaluations =====
  static const evaluationsView = 'evaluations.view';
  static const evaluationsCreate = 'evaluations.create';
  static const evaluationsEdit = 'evaluations.edit';
  static const evaluationsDelete = 'evaluations.delete';
  static const evaluationCriteriaView = 'evaluation_criteria.view';
  static const evaluationCriteriaCreate = 'evaluation_criteria.create';
  static const evaluationCriteriaEdit = 'evaluation_criteria.edit';
  static const evaluationCriteriaDelete = 'evaluation_criteria.delete';

  // ===== Deductions =====
  static const deductionsView = 'deductions.view';
  static const deductionsCreate = 'deductions.create';
  static const deductionsEdit = 'deductions.edit';
  static const deductionsDelete = 'deductions.delete';

  // ===== Customers / Branches =====
  static const customersView = 'customers.view';
  static const customersCreate = 'customers.create';
  static const customersEdit = 'customers.edit';
  static const customersDelete = 'customers.delete';
  static const branchesView = 'branches.view';
  static const branchesCreate = 'branches.create';
  static const branchesEdit = 'branches.edit';
  static const branchesDelete = 'branches.delete';

  // ===== Lookups =====
  static const departmentsView = 'departments.view';
  static const departmentsCreate = 'departments.create';
  static const departmentsEdit = 'departments.edit';
  static const departmentsDelete = 'departments.delete';
  static const jobTitlesView = 'job_titles.view';
  static const jobTitlesCreate = 'job_titles.create';
  static const jobTitlesEdit = 'job_titles.edit';
  static const jobTitlesDelete = 'job_titles.delete';
  static const countriesView = 'countries.view';
  static const countriesCreate = 'countries.create';
  static const countriesEdit = 'countries.edit';
  static const countriesDelete = 'countries.delete';

  // ===== Forms / Workflows =====
  static const formsView = 'forms.view';
  static const formsCreate = 'forms.create';
  static const formsEdit = 'forms.edit';
  static const formsDelete = 'forms.delete';
  static const formsSubmit = 'forms.submit';
  static const formsApprove = 'forms.approve';
  static const formsManage = 'forms.manage';
  static const workflowsView = 'workflows.view';
  static const workflowsCreate = 'workflows.create';
  static const workflowsEdit = 'workflows.edit';
  static const workflowsDelete = 'workflows.delete';

  // ===== Users / Roles =====
  static const usersView = 'users.view';
  static const usersCreate = 'users.create';
  static const usersEdit = 'users.edit';
  static const usersDelete = 'users.delete';
  static const rolesView = 'roles.view';
  static const rolesCreate = 'roles.create';
  static const rolesEdit = 'roles.edit';
  static const rolesDelete = 'roles.delete';

  // ===== Org =====
  static const orgView = 'org.view';
  static const orgManage = 'org.manage';

  // ===== Device Sessions / Geo-fence / Login method (admin tools) =====
  static const adminDeviceSessionsView = 'admin.device_sessions.view';
  static const adminDeviceSessionsManage = 'admin.device_sessions.manage';
  static const adminGeoFenceView = 'admin.geo_fence.view';
  static const adminGeoFenceManage = 'admin.geo_fence.manage';
  static const adminLoginMethodView = 'admin.login_method.view';
  static const adminLoginMethodManage = 'admin.login_method.manage';

  // ===== Face Enrollment (للموظّفين) =====
  static const employeesFaceEnroll = 'employees.face.enroll';
  static const employeesFaceDelete = 'employees.face.delete';

  // ============================================================
  // 🆕 صلاحيّات تفصيليّة على مستوى الصفحة (page-level CRUD)
  // ============================================================

  // ===== Uniforms (الزيّ) — موديول جديد كامل =====
  static const uniformCatalogView = 'uniform.catalog.view';
  static const uniformCatalogCreate = 'uniform.catalog.create';
  static const uniformCatalogEdit = 'uniform.catalog.edit';
  static const uniformCatalogDelete = 'uniform.catalog.delete';
  static const uniformIssueView = 'uniform.issue.view';
  static const uniformIssueCreate = 'uniform.issue.create';
  static const uniformIssueEdit = 'uniform.issue.edit';
  static const uniformIssueDelete = 'uniform.issue.delete';
  static const uniformReceiveView = 'uniform.receive.view';
  static const uniformReceiveCreate = 'uniform.receive.create';
  static const uniformReceiveEdit = 'uniform.receive.edit';
  static const uniformReceiveDelete = 'uniform.receive.delete';
  // 🆕 فَواتير الاستِلام الجَديدة (uniform_purchases)
  static const uniformPurchasesView = 'uniform.purchases.view';
  static const uniformPurchasesCreate = 'uniform.purchases.create';
  static const uniformPurchasesEdit = 'uniform.purchases.edit';
  static const uniformPurchasesDelete = 'uniform.purchases.delete';
  // 🆕 إرجاع زِيّ المُوَظَّف
  static const uniformIssueReturn = 'uniform.issue.return';
  // 🆕 تَوقيع المُوَظَّف عَلى السَند
  static const uniformIssueSign = 'uniform.issue.sign';
  // 🆕 شاشة طَلَبات الزِيّ + صَرف الطَلَب
  static const uniformRequestsView = 'uniform.requests.view';
  static const uniformRequestsFulfill = 'uniform.requests.fulfill';
  // 🆕 شاشة "يَنتَظِرون التَجهيز"
  static const campAwaitingSetupView = 'camp.awaiting_setup.view';
  // 🆕 إعدادات قِسم الكَمب
  static const campSettingsView = 'camp.settings.view';
  static const campSettingsEdit = 'camp.settings.edit';
  static const uniformReportsView = 'uniform.reports.view';
  static const uniformReportsExport = 'uniform.reports.export';

  // ===== HR — صفحات منفصلة =====
  static const hrOnboardingView = 'hr.onboarding.view';
  static const hrOnboardingCreate = 'hr.onboarding.create';
  static const hrOnboardingEdit = 'hr.onboarding.edit';
  static const hrOnboardingDelete = 'hr.onboarding.delete';
  static const hrDocumentsView = 'hr.documents.view';
  static const hrDocumentsCreate = 'hr.documents.create';
  static const hrDocumentsEdit = 'hr.documents.edit';
  static const hrDocumentsDelete = 'hr.documents.delete';
  static const hrReportsView = 'hr.reports.view';
  static const hrReportsExport = 'hr.reports.export';

  // ===== Camp — Laundry & Uniforms المتصلة بالكمب (sub-pages) =====
  static const campLaundryBatchesView = 'camp.laundry.batches.view';
  static const campLaundryBatchesCreate = 'camp.laundry.batches.create';
  static const campLaundryReceiveCreate = 'camp.laundry.receive.create';
  static const campLaundryDeliverCreate = 'camp.laundry.deliver.create';
  static const campLaundryReportsView = 'camp.laundry.reports.view';
  static const campLaundryReportsExport = 'camp.laundry.reports.export';
  static const campLaundrySuppliersView = 'camp.laundry.suppliers.view';
  static const campLaundrySuppliersEdit = 'camp.laundry.suppliers.edit';
  static const campLaundryPickupView = 'camp.laundry.pickup.view';
  static const campLaundryPickupEdit = 'camp.laundry.pickup.edit';

  // ===== Buses — صفحات فرعيّة =====
  static const busesDriversView = 'buses.drivers.view';
  static const busesDriversEdit = 'buses.drivers.edit';
  static const busesReportsView = 'buses.reports.view';
  static const busesReportsExport = 'buses.reports.export';

  // ===== Driver — صفحة الخريطة =====
  static const driverRouteMapView = 'driver.route_map.view';

  // ===== Employees — استيراد جماعي =====
  static const employeesBulkImportView = 'employees.bulk_import.view';
  static const employeesBulkImportManage = 'employees.bulk_import.manage';

  // ===== Admin — أدوات نظاميّة إضافيّة =====
  static const adminSystemHealthView = 'admin.system_health.view';
  static const adminNotificationsSend = 'admin.notifications.send';
  static const adminWhatsNewView = 'admin.whats_new.view';

  // ===== 🆕 Roster Tracked-Edit (post-approval changes) =====
  static const rostersEditApprovedMinor = 'rosters.edit_approved_minor';
  static const rostersEditApprovedMajor = 'rosters.edit_approved_major';
  static const rostersViewChangeLog = 'rosters.view_change_log';
  static const rostersBypassReason = 'rosters.bypass_reason';

  // ===== 🆕 Notification Receive — granular control over who gets what =====
  // Each maps to a notify_permission() call inside a trigger. Granting one of
  // these to a user (via role or direct override) starts delivering that
  // specific notification stream to them — country-filtered automatically.
  // Leave
  static const notificationsReceiveLeaveApprovalRequests =
      'notifications.receive.leave.approval_requests';
  static const notificationsReceiveLeaveLateReturns =
      'notifications.receive.leave.late_returns';
  static const notificationsReceiveLeaveEndedToday =
      'notifications.receive.leave.ended_today';
  // HR
  static const notificationsReceiveHrEmployeeCreated =
      'notifications.receive.hr.employee_created';
  static const notificationsReceiveHrEmployeeDeactivated =
      'notifications.receive.hr.employee_deactivated';
  static const notificationsReceiveHrDocumentExpiring =
      'notifications.receive.hr.document_expiring';
  static const notificationsReceiveHrDocumentExpired =
      'notifications.receive.hr.document_expired';
  // Forms
  static const notificationsReceiveFormsPendingApproval =
      'notifications.receive.forms.pending_approval';
  static const notificationsReceiveFormsIncidentReported =
      'notifications.receive.forms.incident_reported';
  static const notificationsReceiveFormsResignation =
      'notifications.receive.forms.resignation';
  // Attendance / Bus / Sites / Uniform / Roster
  static const notificationsReceiveAttendanceLateCheckin =
      'notifications.receive.attendance.late_checkin';
  static const notificationsReceiveBusTripEvents =
      'notifications.receive.bus.trip_events';
  static const notificationsReceiveSitesNewSubmission =
      'notifications.receive.sites.new_submission';
  static const notificationsReceiveUniformRequests =
      'notifications.receive.uniform.requests';
  static const notificationsReceiveRosterCreated =
      'notifications.receive.roster.created';

  static const adminWhatsNewEdit = 'admin.whats_new.edit';
  static const adminL4PromotionView = 'admin.l4_promotion.view';
  static const adminL4PromotionManage = 'admin.l4_promotion.manage';

  // ===== Org — صفحات فرعيّة =====
  static const orgChartView = 'org.chart.view';
  static const orgBuilderManage = 'org.builder.manage';
  static const orgCoverageView = 'org.coverage.view';
  static const orgPointAssignmentView = 'org.point_assignment.view';
  static const orgPointAssignmentEdit = 'org.point_assignment.edit';
  static const orgDepartmentProfileView = 'org.department_profile.view';
  static const orgJobTitleProfileView = 'org.job_title_profile.view';

  // ===== Forms — صفحات فرعيّة =====
  static const formsAdminView = 'forms.admin.view';
  static const formsAdminManage = 'forms.admin.manage';
  static const formsEmployeeView = 'forms.employee.view';
  static const formsApprovalsView = 'forms.approvals.view';
  static const formsApprovalsApprove = 'forms.approvals.approve';

  // ===== Workflows — صفحات فرعيّة =====
  static const workflowsBuilderView = 'workflows.builder.view';
  static const workflowsBuilderManage = 'workflows.builder.manage';
  static const workflowsApprovalMatrixView = 'workflows.approval_matrix.view';

  // ===== Attendance — تقارير منفصلة =====
  static const attendanceReportsView = 'attendance.reports.view';
  static const attendanceReportsExport = 'attendance.reports.export';

  // ===== Roster employee filter (إعداد جديد) =====
  /// عرض إعدادات تصفية الموظّفين عند إضافتهم للروستر
  static const settingsRosterEmployeeFilterView =
      'settings.roster_employee_filter.view';
  /// تعديل إعدادات تصفية الموظّفين
  static const settingsRosterEmployeeFilterEdit =
      'settings.roster_employee_filter.edit';
  /// إعدادات مواعيد الروستر (آخر يوم للإنشاء، يوم المراجعة، بدء العمل)
  static const settingsRosterDeadlineView =
      'settings.roster_deadline.view';
  static const settingsRosterDeadlineEdit =
      'settings.roster_deadline.edit';
  /// شاشة حذف روستر محدّد (نقطة + أسبوع)
  static const settingsDeleteSpecificRosterManage =
      'settings.delete_specific_roster.manage';

  // ===== صفحات Admin/Settings الباقية (إغلاق الفجوات) =====
  /// شاشة Admin Overview (نظرة سريعة على Admin)
  static const adminOverviewView = 'admin.overview.view';
  /// شاشة Admin Home (الواجهة الرئيسيّة للأدمن)
  static const adminHomeView = 'admin.home.view';
  /// مركز المساعدة في Admin
  static const adminHelpCenterView = 'admin.help_center.view';
  /// شاشة الانتحال (impersonate) — Super Admin فقط
  static const adminImpersonateView = 'admin.impersonate.view';
  static const adminImpersonateUse = 'admin.impersonate.use';
  /// شاشة Settings Hub الأمّ — عادةً تُترك مفتوحة لكلّ من له صلاحيّة فرعيّة،
  /// لكن نتيح مفتاحاً مستقلاً لمن يحتاج التحكّم بزيارة الـ Hub نفسه.
  static const settingsHubView = 'settings.hub.view';
  /// إعدادات تتبّع السائقين (مختلفة عن settings.tracking.* العامّ)
  static const settingsDriverTrackingView = 'settings.driver_tracking.view';
  static const settingsDriverTrackingEdit = 'settings.driver_tracking.edit';
  /// إدارة صلاحيّات المسمّيات (Job Title Permissions Matrix)
  static const adminJobTitlePermissionsView = 'admin.job_title_permissions.view';
  static const adminJobTitlePermissionsManage = 'admin.job_title_permissions.manage';

  // ===== 🆕 وَثائِق الموظَّفين (Document Versioning) =====
  /// عَرض وَثائِق الموظَّفين (كُلّ الإصدارات)
  static const employeeDocumentsView = 'employee_documents.view';
  /// رَفع/تَجديد وَثيقة (إنشاء إصدار جَديد)
  static const employeeDocumentsUpload = 'employee_documents.upload';
  /// إلغاء (revoke) وَثيقة — لا يَحذِف بَل يُغَيِّر الحالة
  static const employeeDocumentsRevoke = 'employee_documents.revoke';
  /// حَذف نِهائيّ لِوَثيقة (لِـSuper Admin أَو أَسباب قانونيّة)
  static const employeeDocumentsHardDelete = 'employee_documents.hard_delete';
  /// تَقرير الوَثائِق المُنتَهية/المُقتَرِبة من الانتِهاء (لِلـHR)
  static const employeeDocumentsExpiryReport =
      'employee_documents.expiry_report.view';

  // ===== 🆕 Point Terminal (جِهاز نُقطة الدَوام) =====
  /// عَرض حِسابات Point Terminal في شاشة Points
  static const pointTerminalView = 'point_terminal.view';
  /// إنشاء/إعادة تَوليد كَلِمة مُرور Terminal
  static const pointTerminalManage = 'point_terminal.manage';
  /// حَذف حِساب Terminal
  static const pointTerminalDelete = 'point_terminal.delete';
  /// عَرض تَقرير دَوام النِقاط
  static const pointAttendanceReportView = 'point_attendance_report.view';
  /// تَصدير تَقرير دَوام النِقاط
  static const pointAttendanceReportExport = 'point_attendance_report.export';
  /// تَعديل إعدادات Point Terminal (geo-fence, timeouts, ...)
  static const settingsPointTerminalView = 'settings.point_terminal.view';
  static const settingsPointTerminalEdit = 'settings.point_terminal.edit';

  // ===== Reports — صلاحيّة لكلّ تقرير (تحكّم دقيق بمن يرى ماذا) =====
  /// تقرير الموظفين (مع أرقام هواتفهم)
  static const reportsEmployeesView = 'reports.employees.view';
  static const reportsEmployeesExport = 'reports.employees.export';
  /// تقرير المواقع
  static const reportsSitesView = 'reports.sites.view';
  static const reportsSitesExport = 'reports.sites.export';
  /// تقرير الروسترات (المعتمدة + المعلّقة)
  static const reportsRostersView = 'reports.rosters.view';
  static const reportsRostersExport = 'reports.rosters.export';
  /// تقرير الباصات
  static const reportsBusesView = 'reports.buses.view';
  static const reportsBusesExport = 'reports.buses.export';
  /// تقرير الخصومات
  static const reportsDeductionsView = 'reports.deductions.view';
  static const reportsDeductionsExport = 'reports.deductions.export';
  /// تقرير المغسلة
  static const reportsLaundryView = 'reports.laundry.view';
  static const reportsLaundryExport = 'reports.laundry.export';
  /// تقرير الزيّ المسلَّم
  static const reportsUniformsView = 'reports.uniforms.view';
  static const reportsUniformsExport = 'reports.uniforms.export';

  // ===== 🆕 Roster — مَجموعات مُستَقلّة لِكلّ شاشة =====

  // 📅 إنشاء روستر (شاشة المُشرف)
  static const rosterCreatorView = 'roster_creator.view';
  static const rosterCreatorCreate = 'roster_creator.create';
  static const rosterCreatorSubmit = 'roster_creator.submit';
  /// السَماح باختيار أيّ نَقطة (للمدير بدون قَيد العمليّات)
  static const rosterCreatorSelectAnyPoint =
      'roster_creator.select_any_point';

  // 📊 مركز الروسترات (Dashboard عامّ)
  static const rostersCenterView = 'rosters_center.view';
  static const rostersCenterCreate = 'rosters_center.create';
  static const rostersCenterEdit = 'rosters_center.edit';
  static const rostersCenterDelete = 'rosters_center.delete';
  static const rostersCenterExport = 'rosters_center.export';

  // ✅ اعتماد الروسترات (شاشة المُعتَمِد)
  static const rosterApprovalsView = 'roster_approvals.view';
  static const rosterApprovalsApprove = 'roster_approvals.approve';
  static const rosterApprovalsReject = 'roster_approvals.reject';
  static const rosterApprovalsEditApproved =
      'roster_approvals.edit_approved';

  // 📋 الروستر المعتمد (شاشة العَرض)
  static const approvedRosterView = 'approved_roster.view';
  static const approvedRosterExport = 'approved_roster.export';

  // 👤 روستري (شاشة الموظّف)
  static const myRosterView = 'my_roster.view';

  // ===== 🆕 Sites Onboarding (إدارة المواقع الجَديدة) =====
  /// عَرض dashboard المواقِع المُعتَمَدة
  static const siteOnboardingView = 'site_onboarding.view';
  /// تَعديل حالات التَجهيز (HR/uniform/training/equipment)
  static const siteOnboardingUpdateSetup = 'site_onboarding.update_setup';
  /// إطلاق الموقِع (تَحويل إلى live)
  static const siteOnboardingGoLive = 'site_onboarding.go_live';
  /// أَرشَفة موقِع
  static const siteOnboardingArchive = 'site_onboarding.archive';
  /// تَقرير المواقِع
  static const siteOnboardingReportView =
      'site_onboarding.report.view';
  static const siteOnboardingReportExport =
      'site_onboarding.report.export';

  // ===== 🆕 Leave Management (إدارة الإجازات) =====
  /// تَقديم طَلَب إجازة شَخصيّ
  static const leaveRequestSubmit = 'leave.request.submit';
  /// عَرض طَلَباتي + رَصيدي
  static const leaveRequestView = 'leave.request.view';
  /// إلغاء طَلَبي قَبل الاعتماد
  static const leaveRequestCancel = 'leave.request.cancel';
  /// عَرض طَلَبات الفَريق (للمدير/HR)
  static const leaveTeamView = 'leave.team.view';
  /// اعتماد/رَفض طَلَبات الفَريق
  static const leaveTeamApprove = 'leave.team.approve';
  /// تَعديل رَصيد الإجازات (HR/Admin)
  static const leaveBalanceManage = 'leave.balance.manage';
  /// تَقرير الإجازات
  static const leaveReportView = 'leave.report.view';
  static const leaveReportExport = 'leave.report.export';

  // ===== 🆕 Daily Memo (مذكّرة الموظّف اليوميّة) =====
  /// إنشاء/تعديل مذكّرتي الخاصّة (الموظّف لنفسه)
  static const dailyMemoCreate = 'daily_memo.create';
  /// عرض مذكّراتي الخاصّة
  static const dailyMemoView = 'daily_memo.view';
  /// عرض مذكّرات فريقي (للمشرفين/Operation)
  static const dailyMemoViewTeam = 'daily_memo.view_team';
  /// تعديل مذكّرات الفريق (HR/Operation عند الحاجة)
  static const dailyMemoEditTeam = 'daily_memo.edit_team';
  /// حذف مذكّراتي الخاصّة
  static const dailyMemoDelete = 'daily_memo.delete';
  /// تقرير المذكّرات
  static const dailyMemoReportView = 'daily_memo.report.view';
  static const dailyMemoReportExport = 'daily_memo.report.export';

  // ===== 🆕 Document Vault (خِزانة الوَثائِق المُوَحَّدة — May 2026) =====
  /// عَرض خِزانة الوَثائِق (كُلّ وَثائِق كُلّ المُوَظَّفين في شاشة واحِدة)
  static const documentsVaultView = 'documents.vault.view';
  /// رَفع وَثيقة جَديدة إلى الخِزانة
  static const documentsVaultUpload = 'documents.vault.upload';
  /// حَذف/استِبدال وَثيقة في الخِزانة
  static const documentsVaultManage = 'documents.vault.manage';
  /// تَصدير قائِمة الوَثائِق (CSV/Excel)
  static const documentsVaultExport = 'documents.vault.export';

  // ===== 🆕 Company Events (تَقويم الشَرِكة — May 2026) =====
  /// عَرض أَحداث الشَرِكة (في التَقويم)
  static const companyEventsView = 'company_events.view';
  /// إنشاء حَدَث مُخَصَّص (اجتِماع، تَدريب، احتِفال…)
  static const companyEventsCreate = 'company_events.create';
  /// تَعديل حَدَث مَوجود
  static const companyEventsEdit = 'company_events.edit';
  /// حَذف حَدَث
  static const companyEventsDelete = 'company_events.delete';
  /// إدارة المُشارِكين (Responsible/Participant/Watcher)
  static const companyEventsManageParticipants = 'company_events.manage_participants';

  // ===== 🆕 Tasks (مَهام To-Do — May 2026) =====
  /// إسناد مَهَمّة لِمُوَظَّف آخَر
  static const tasksAssign = 'tasks.assign';
  /// عَرض كُلّ مَهام الفَريق
  static const tasksViewTeam = 'tasks.view_team';
  /// تَعديل أَيّ مَهَمّة (Admin/HR)
  static const tasksManageAll = 'tasks.manage_all';

  // ===== 🆕 Temporary PIN (PIN مُؤَقَّت — May 2026) =====
  /// تَوليد PIN مُؤَقَّت لِمُوَظَّف فَشِل في تَسجيل الوَجه
  static const pinGenerateTemporary = 'pin.generate_temporary';
  /// عَرض سِجِلّ الـ PINs المُولَّدة
  static const pinViewHistory = 'pin.view_history';
  /// تَعديل إعدادات PIN (TTL، الطول)
  static const pinManageSettings = 'pin.manage_settings';

  // ===== 🆕 Splash Video (فيديو الترحيب — May 2026) =====
  /// إدارة فيديو الترحيب (رَفع، تَعديل المُدَّة، تَفعيل/إيقاف)
  static const settingsSplashVideoManage = 'settings.splash_video.manage';

  // ===== 🆕 Entitlements (المُستَحَقّات — راتِب إجازة + نِهاية خِدمة — May 2026) =====
  /// عَرض مُستَحَقّات المُوَظَّف (لِنَفسِه أَو فَريقِه)
  static const entitlementsView = 'entitlements.view';
  /// عَرض مُستَحَقّات كُلّ المُوَظَّفين
  static const entitlementsViewAll = 'entitlements.view_all';
  /// صَرف راتِب إجازة
  static const entitlementsPayLeaveSalary = 'entitlements.pay_leave_salary';
  /// حِساب مُكافأة نِهاية الخِدمة
  static const entitlementsCalculateEos = 'entitlements.calculate_eos';
  /// صَرف مُكافأة نِهاية الخِدمة
  static const entitlementsPayEos = 'entitlements.pay_eos';
  /// تَفعيل/تَعطيل تَذكِرة سَفَر لِمُوَظَّف
  static const entitlementsManageTicket = 'entitlements.manage_ticket';

  // ===== 🆕 Labor Rules (قَواعِد قانون العَمَل لِكُلّ دَولة) =====
  /// عَرض قَواعِد قانون العَمَل
  static const settingsLaborRulesView = 'settings.labor_rules.view';
  /// تَعديل قَواعِد قانون العَمَل لِلدُوَل
  static const settingsLaborRulesManage = 'settings.labor_rules.manage';

  // ============================================================
  // 🆕 PHASE 1 — صَلاحيّات الميزات الجَديدة (2026-05-23)
  // ============================================================

  // ===== 💰 Tips (البَقاشيش) =====
  static const tipsView = 'tips.view';
  static const tipsCreate = 'tips.create';
  static const tipsDelete = 'tips.delete';
  static const tipsLeaderboardView = 'tips.leaderboard.view';
  static const tipsExport = 'tips.export';

  // ===== 💾 Backups (النُسَخ الاحتِياطيّة) =====
  static const backupsView = 'backups.view';
  static const backupsRunStats = 'backups.run.stats';
  static const backupsRunFull = 'backups.run.full';
  static const backupsDownload = 'backups.download';

  // ===== 🔒 GDPR / Anonymization =====
  /// إخفاء هُوِيّة مُوَظَّف نِهائيّاً (Super Admin فَقَط)
  static const gdprAnonymize = 'gdpr.anonymize';
  static const gdprCandidatesView = 'gdpr.candidates.view';

  // ===== 📜 Audit splits (تَفصيل سِجِلّ التَدقيق) =====
  /// عَرض سِجِلّ تَغييرات الإعدادات
  static const auditSettingsView = 'audit.settings.view';
  /// عَرض تَدَفُّق النَشاطات المُوَحَّد
  static const auditActivityView = 'audit.activity.view';

  // ===== 👤 Employee Status (سِجِلّ حالة المُوَظَّف) =====
  static const employeeStatusHistoryView = 'employees.status_history.view';
  /// تَغيير حالة المُوَظَّف يَدَويّاً (active/inactive)
  static const employeeStatusChange = 'employees.status.change';

  // ===== 🇦🇪 UAE Government Fields (حِماية البَيانات الحَسّاسة) =====
  /// عَرض EID, MOHRE, Labour Card, WASL, etc.
  static const employeesGovFieldsView = 'employees.gov_fields.view';
  /// تَعديل الحُقول الحُكومِيّة (يُغَلَّق غالِباً عَلى HR + Admin)
  static const employeesGovFieldsEdit = 'employees.gov_fields.edit';

  // ===== 📤 Exports (تَصدير عامّ) =====
  static const exportExcel = 'export.excel';
  static const exportPdf = 'export.pdf';
}
