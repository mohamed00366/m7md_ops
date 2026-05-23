import '../models/rbac.dart';

/// نتيجة seed لنظام RBAC
class RbacSeedResult {
  final List<RoleDef> roles;
  final List<PermissionDef> permissions;
  final List<RolePermissionLink> rolePermissions;
  final List<AppAccount> accounts;
  final List<UserRoleAssignment> userRoles;
  final List<UserCountryAccess> userCountries;

  RbacSeedResult({
    required this.roles,
    required this.permissions,
    required this.rolePermissions,
    required this.accounts,
    required this.userRoles,
    required this.userCountries,
  });
}

/// بيانات افتراضية كاملة لـ RBAC
RbacSeedResult seedRbac(String Function() generateId,
    {required List<String> countryIds}) {
  // ========================================
  // 1) الأدوار (7)
  // ========================================
  final superAdminRole = RoleDef(
    id: generateId(),
    key: SystemRoles.superAdmin,
    nameAr: 'مدير عام',
    nameEn: 'Super Admin',
    descriptionAr: 'تحكم كامل في كل النظام',
    descriptionEn: 'Full system control',
    isSystem: true,
    priority: 100,
  );
  final adminRole = RoleDef(
    id: generateId(),
    key: SystemRoles.admin,
    nameAr: 'مسؤول إداري',
    nameEn: 'Admin',
    descriptionAr: 'إدارة المستخدمين والإعدادات',
    descriptionEn: 'User and settings management',
    isSystem: true,
    priority: 90,
  );
  final managerRole = RoleDef(
    id: generateId(),
    key: SystemRoles.manager,
    nameAr: 'مدير',
    nameEn: 'Manager',
    descriptionAr: 'مدير شركة/فرع',
    descriptionEn: 'Company/branch manager',
    isSystem: true,
    priority: 80,
  );
  final operationRole = RoleDef(
    id: generateId(),
    key: SystemRoles.operation,
    nameAr: 'مسؤول عمليات',
    nameEn: 'Operation',
    descriptionAr: 'مراجعة الورديات وتعيين المشرفين',
    descriptionEn: 'Reviews and supervisor assignments',
    isSystem: true,
    priority: 70,
  );
  final supervisorRole = RoleDef(
    id: generateId(),
    key: SystemRoles.supervisor,
    nameAr: 'مشرف',
    nameEn: 'Supervisor',
    descriptionAr: 'إنشاء وإرسال الروستر',
    descriptionEn: 'Create and submit roster',
    isSystem: true,
    priority: 60,
  );
  final campBossRole = RoleDef(
    id: generateId(),
    key: SystemRoles.campBoss,
    nameAr: 'مسؤول كمب',
    nameEn: 'Camp Boss',
    descriptionAr: 'إدارة الكمب والباصات',
    descriptionEn: 'Camp and bus management',
    isSystem: true,
    priority: 50,
  );
  final driverRole = RoleDef(
    id: generateId(),
    key: SystemRoles.driver,
    nameAr: 'سائق',
    nameEn: 'Driver',
    descriptionAr: 'سائق باص',
    descriptionEn: 'Bus driver',
    isSystem: true,
    priority: 40,
  );
  final employeeRole = RoleDef(
    id: generateId(),
    key: SystemRoles.employee,
    nameAr: 'موظف',
    nameEn: 'Employee',
    descriptionAr: 'موظف عادي',
    descriptionEn: 'Regular employee',
    isSystem: true,
    priority: 30,
  );

  final roles = [
    superAdminRole,
    adminRole,
    managerRole,
    operationRole,
    supervisorRole,
    campBossRole,
    driverRole,
    employeeRole,
  ];

  // ========================================
  // 2) الصلاحيات (~50)
  // ========================================
  PermissionDef perm(String key, String module, String ar, String en) =>
      PermissionDef(
          id: generateId(), key: key, module: module, nameAr: ar, nameEn: en);

  final permissions = [
    // Admin
    perm(P.adminUsersView, 'admin', 'عرض المستخدمين', 'View users'),
    perm(P.adminUsersManage, 'admin', 'إدارة المستخدمين', 'Manage users'),
    perm(P.adminRolesManage, 'admin', 'إدارة الأدوار', 'Manage roles'),
    perm(P.adminAuditView, 'admin', 'عرض سجل النشاط', 'View audit log'),
    perm(P.adminCountriesManage, 'admin', 'إدارة الدول للمستخدمين',
        'Manage user countries'),
    perm(P.adminPasswordReset, 'admin', 'إعادة تعيين كلمات المرور',
        'Reset passwords'),
    // Dashboard
    perm(P.dashboardManagerView, 'dashboard', 'لوحة المدير',
        'Manager dashboard'),
    perm(P.dashboardOperationView, 'dashboard', 'لوحة العمليات',
        'Operation dashboard'),
    perm(P.dashboardCampView, 'dashboard', 'لوحة الكمب',
        'Camp Boss dashboard'),
    // Sites/Customers
    perm(P.sitesView, 'sites', 'عرض المواقع/العملاء', 'View sites/customers'),
    perm(P.sitesCreate, 'sites', 'إنشاء عميل/نقطة', 'Create customer/point'),
    perm(P.sitesEdit, 'sites', 'تعديل عميل/نقطة', 'Edit customer/point'),
    perm(P.sitesDelete, 'sites', 'حذف عميل/نقطة', 'Delete customer/point'),
    // Employees
    perm(P.employeesView, 'employees', 'عرض الموظفين', 'View employees'),
    perm(P.employeesCreate, 'employees', 'إنشاء موظف', 'Create employee'),
    perm(P.employeesEdit, 'employees', 'تعديل موظف', 'Edit employee'),
    perm(P.employeesActivate, 'employees', 'تفعيل/تعطيل موظف',
        'Activate/Deactivate employee'),
    perm(P.employeesDelete, 'employees', 'حذف موظف', 'Delete employee'),
    // Buses
    perm(P.busesView, 'buses', 'عرض الباصات', 'View buses'),
    perm(P.busesCreate, 'buses', 'إضافة باص', 'Add bus'),
    perm(P.busesEdit, 'buses', 'تعديل باص', 'Edit bus'),
    perm(P.busesAssign, 'buses', 'تعيين باص لساعة', 'Assign bus to hour'),
    perm(P.busesDelete, 'buses', 'حذف باص', 'Delete bus'),
    // Rosters
    perm(P.rostersView, 'rosters', 'عرض الروستر', 'View roster'),
    perm(P.rostersCreate, 'rosters', 'إنشاء روستر', 'Create roster'),
    perm(P.rostersSubmit, 'rosters', 'إرسال روستر للاعتماد', 'Submit roster'),
    perm(P.rostersApprove, 'rosters', 'اعتماد الروستر', 'Approve roster'),
    perm(P.rostersReject, 'rosters', 'رفض الروستر', 'Reject roster'),
    perm(P.rostersEditApproved, 'rosters', 'تعديل روستر معتمد',
        'Edit approved roster'),
    // 🆕 يسمح للمدير باختيار نقطة عند إنشاء الروستر بدون أن
    // يكون مرتبطاً بنقطة معيّنة (يتجاوز اشتراط ربط Operation له بنقطة).
    perm(P.rostersSelectAnyPoint, 'rosters', 'اختيار النقطة عند إنشاء الروستر',
        'Select point when creating roster'),
    // ===== 🆕 Attendance (تحت HR) — CRUD كامل =====
    perm(P.attendanceView, 'attendance', 'عرض الحضور', 'View attendance'),
    perm(P.attendanceCreate, 'attendance', 'تسجيل حضور', 'Mark attendance'),
    perm(P.attendanceEdit, 'attendance', 'تعديل حضور', 'Edit attendance'),
    perm(P.attendanceDelete, 'attendance', 'حذف سجلّ حضور',
        'Delete attendance record'),
    perm(P.attendanceExport, 'attendance', 'تصدير تقارير الحضور',
        'Export attendance reports'),
    // ===== 🆕 Policies — CRUD كامل =====
    perm(P.policiesCreate, 'policies', 'إضافة سياسة', 'Create policy'),
    perm(P.policiesDelete, 'policies', 'حذف سياسة', 'Delete policy'),
    // ===== 🆕 Evaluations =====
    perm(P.evaluationsView, 'evaluations', 'عرض التقييمات', 'View evaluations'),
    perm(P.evaluationsCreate, 'evaluations', 'إضافة تقييم', 'Create evaluation'),
    perm(P.evaluationsEdit, 'evaluations', 'تعديل تقييم', 'Edit evaluation'),
    perm(P.evaluationsDelete, 'evaluations', 'حذف تقييم', 'Delete evaluation'),
    perm(P.evaluationCriteriaView, 'evaluations',
        'عرض معايير التقييم', 'View evaluation criteria'),
    perm(P.evaluationCriteriaCreate, 'evaluations',
        'إضافة معيار تقييم', 'Create evaluation criterion'),
    perm(P.evaluationCriteriaEdit, 'evaluations',
        'تعديل معيار تقييم', 'Edit evaluation criterion'),
    perm(P.evaluationCriteriaDelete, 'evaluations',
        'حذف معيار تقييم', 'Delete evaluation criterion'),
    // ===== 🆕 Deductions =====
    perm(P.deductionsView, 'deductions', 'عرض الخصومات', 'View deductions'),
    perm(P.deductionsCreate, 'deductions',
        'إضافة خصم', 'Create deduction'),
    perm(P.deductionsEdit, 'deductions', 'تعديل خصم', 'Edit deduction'),
    perm(P.deductionsDelete, 'deductions', 'حذف خصم', 'Delete deduction'),
    // ===== 🆕 Customers / Branches =====
    perm(P.customersView, 'customers', 'عرض العملاء', 'View customers'),
    perm(P.customersCreate, 'customers', 'إضافة عميل', 'Create customer'),
    perm(P.customersEdit, 'customers', 'تعديل عميل', 'Edit customer'),
    perm(P.customersDelete, 'customers', 'حذف عميل', 'Delete customer'),
    perm(P.branchesView, 'customers', 'عرض الفروع', 'View branches'),
    perm(P.branchesCreate, 'customers', 'إضافة فرع', 'Create branch'),
    perm(P.branchesEdit, 'customers', 'تعديل فرع', 'Edit branch'),
    perm(P.branchesDelete, 'customers', 'حذف فرع', 'Delete branch'),
    // ===== 🆕 Lookups =====
    perm(P.departmentsView, 'lookups', 'عرض الأقسام', 'View departments'),
    perm(P.departmentsCreate, 'lookups',
        'إضافة قسم', 'Create department'),
    perm(P.departmentsEdit, 'lookups', 'تعديل قسم', 'Edit department'),
    perm(P.departmentsDelete, 'lookups', 'حذف قسم', 'Delete department'),
    perm(P.jobTitlesView, 'lookups',
        'عرض المسمّيات', 'View job titles'),
    perm(P.jobTitlesCreate, 'lookups',
        'إضافة مسمّى', 'Create job title'),
    perm(P.jobTitlesEdit, 'lookups',
        'تعديل مسمّى', 'Edit job title'),
    perm(P.jobTitlesDelete, 'lookups', 'حذف مسمّى', 'Delete job title'),
    perm(P.countriesView, 'lookups', 'عرض الدول', 'View countries'),
    perm(P.countriesCreate, 'lookups', 'إضافة دولة', 'Create country'),
    perm(P.countriesEdit, 'lookups', 'تعديل دولة', 'Edit country'),
    perm(P.countriesDelete, 'lookups', 'حذف دولة', 'Delete country'),
    // ===== 🆕 Forms / Workflows =====
    perm(P.formsView, 'forms', 'عرض النماذج', 'View forms'),
    perm(P.formsCreate, 'forms', 'إضافة نموذج', 'Create form'),
    perm(P.formsEdit, 'forms', 'تعديل نموذج', 'Edit form'),
    perm(P.formsDelete, 'forms', 'حذف نموذج', 'Delete form'),
    perm(P.workflowsView, 'forms',
        'عرض سير الموافقات', 'View workflows'),
    perm(P.workflowsCreate, 'forms',
        'إضافة سير موافقة', 'Create workflow'),
    perm(P.workflowsEdit, 'forms',
        'تعديل سير موافقة', 'Edit workflow'),
    perm(P.workflowsDelete, 'forms',
        'حذف سير موافقة', 'Delete workflow'),
    // ===== 🆕 Users / Roles =====
    perm(P.usersView, 'admin', 'عرض المستخدمين', 'View users'),
    perm(P.usersCreate, 'admin', 'إضافة مستخدم', 'Create user'),
    perm(P.usersEdit, 'admin', 'تعديل مستخدم', 'Edit user'),
    perm(P.usersDelete, 'admin', 'حذف مستخدم', 'Delete user'),
    perm(P.rolesView, 'admin', 'عرض الأدوار', 'View roles'),
    perm(P.rolesCreate, 'admin', 'إضافة دور', 'Create role'),
    perm(P.rolesEdit, 'admin', 'تعديل دور', 'Edit role'),
    perm(P.rolesDelete, 'admin', 'حذف دور', 'Delete role'),
    // ===== 🆕 Settings sub-pages — صفحات الإعدادات التفصيليّة =====
    perm(P.settingsNumberingView, 'settings',
        'عرض نظام الترقيم', 'View numbering'),
    perm(P.settingsOrgView, 'settings', 'عرض إعدادات المؤسّسة',
        'View organization settings'),
    perm(P.settingsOrgEdit, 'settings', 'تعديل إعدادات المؤسّسة',
        'Edit organization settings'),
    perm(P.settingsRosterView, 'settings',
        'عرض إعدادات الروسترات', 'View roster settings'),
    perm(P.settingsRosterEdit, 'settings',
        'تعديل إعدادات الروسترات', 'Edit roster settings'),
    perm(P.settingsBusView, 'settings',
        'عرض قواعد الباصات', 'View bus settings'),
    perm(P.settingsBusEdit, 'settings',
        'تعديل قواعد الباصات', 'Edit bus settings'),
    perm(P.settingsTrackingView, 'settings',
        'عرض إعدادات التتبّع', 'View tracking settings'),
    perm(P.settingsTrackingEdit, 'settings',
        'تعديل إعدادات التتبّع', 'Edit tracking settings'),
    perm(P.settingsCampView, 'settings',
        'عرض قواعد الكمب', 'View camp settings'),
    perm(P.settingsCampEdit, 'settings',
        'تعديل قواعد الكمب', 'Edit camp settings'),
    perm(P.settingsHrView, 'settings',
        'عرض إعدادات HR', 'View HR settings'),
    perm(P.settingsHrEdit, 'settings',
        'تعديل إعدادات HR', 'Edit HR settings'),
    perm(P.settingsDeductionView, 'settings',
        'عرض قواعد الخصومات', 'View deduction settings'),
    perm(P.settingsDeductionEdit, 'settings',
        'تعديل قواعد الخصومات', 'Edit deduction settings'),
    perm(P.settingsEvaluationView, 'settings',
        'عرض إعدادات التقييم', 'View evaluation settings'),
    perm(P.settingsEvaluationEdit, 'settings',
        'تعديل إعدادات التقييم', 'Edit evaluation settings'),
    perm(P.settingsTrainingView, 'settings',
        'عرض إعدادات التدريب', 'View training settings'),
    perm(P.settingsTrainingEdit, 'settings',
        'تعديل إعدادات التدريب', 'Edit training settings'),
    perm(P.settingsCustomerView, 'settings',
        'عرض إعدادات العملاء', 'View customer settings'),
    perm(P.settingsCustomerEdit, 'settings',
        'تعديل إعدادات العملاء', 'Edit customer settings'),
    perm(P.settingsSessionView, 'settings',
        'عرض سياسة الجلسات', 'View session policy'),
    perm(P.settingsSessionEdit, 'settings',
        'تعديل سياسة الجلسات', 'Edit session policy'),
    perm(P.settingsDeviceSessionView, 'settings',
        'عرض سياسة الأجهزة', 'View device session policy'),
    perm(P.settingsDeviceSessionEdit, 'settings',
        'تعديل سياسة الأجهزة', 'Edit device session policy'),
    perm(P.settingsGeoFenceView, 'settings',
        'عرض سياسة الموقع الجغرافي', 'View geo-fence policy'),
    perm(P.settingsGeoFenceEdit, 'settings',
        'تعديل سياسة الموقع الجغرافي', 'Edit geo-fence policy'),
    perm(P.settingsLoginMethodView, 'settings',
        'عرض طريقة الدخول', 'View login method'),
    perm(P.settingsLoginMethodEdit, 'settings',
        'تعديل طريقة الدخول', 'Edit login method'),
    perm(P.settingsFaceEmbeddingsView, 'settings',
        'عرض بصمات الوجه', 'View face embeddings'),
    perm(P.settingsFaceEmbeddingsManage, 'settings',
        'إعادة حساب بصمات الوجه', 'Recompute face embeddings'),
    perm(P.settingsLogViewerView, 'settings',
        'عرض سجلّ التطبيق', 'View application logs'),
    perm(P.settingsConfigExportView, 'settings',
        'عرض تصدير/استيراد JSON', 'View config export'),
    perm(P.settingsConfigExportManage, 'settings',
        'تصدير/استيراد JSON', 'Manage config export'),
    perm(P.settingsClearRostersManage, 'settings',
        'حذف كلّ الروسترات', 'Clear all rosters'),
    perm(P.settingsBulkOpsView, 'settings',
        'عرض العمليّات الجماعيّة', 'View bulk operations'),
    perm(P.settingsBulkOpsManage, 'settings',
        'تنفيذ العمليّات الجماعيّة', 'Run bulk operations'),
    // Camp
    perm(P.campRoomsView, 'camp', 'عرض الغرف', 'View rooms'),
    perm(P.campRoomsRate, 'camp', 'تقييم غرفة', 'Rate room'),
    perm(P.campLaundryView, 'camp', 'عرض المغسلة', 'View laundry'),
    perm(P.campLaundryProcess, 'camp', 'معالجة طلبات المغسلة',
        'Process laundry'),
    perm(P.campViolationsView, 'camp', 'عرض المخالفات', 'View violations'),
    perm(P.campViolationsCreate, 'camp', 'إنشاء مخالفة', 'Create violation'),
    perm(P.campViolationsApprove, 'camp', 'اعتماد مخالفة',
        'Approve violation'),
    perm(P.campChecklistView, 'camp', 'عرض الشيكلست الصباحي',
        'View morning checklist'),
    perm(P.campChecklistCreate, 'camp', 'إنشاء شيكلست', 'Create checklist'),
    // ===== صلاحيات تفصيلية إضافية للكمب =====
    perm(P.campRoomsCreate, 'camp', 'إنشاء غرفة', 'Create room'),
    perm(P.campRoomsEdit, 'camp', 'تعديل غرفة', 'Edit room'),
    perm(P.campRoomsDelete, 'camp', 'حذف غرفة', 'Delete room'),
    perm(P.campLaundryCreate, 'camp', 'إنشاء تذكرة مغسلة',
        'Create laundry ticket'),
    perm(P.campLaundryEdit, 'camp', 'تعديل تذكرة مغسلة',
        'Edit laundry ticket'),
    perm(P.campLaundryDelete, 'camp', 'حذف تذكرة مغسلة',
        'Delete laundry ticket'),
    perm(P.campViolationsEdit, 'camp', 'تعديل مخالفة', 'Edit violation'),
    perm(P.campViolationsDelete, 'camp', 'حذف مخالفة', 'Delete violation'),

    perm(P.campChecklistEdit, 'camp', 'تعديل شيكلست', 'Edit checklist'),
    perm(P.campChecklistDelete, 'camp', 'حذف شيكلست', 'Delete checklist'),
    // Driver
    perm(P.driverTripsView, 'driver', 'عرض رحلات السائق', 'View driver trips'),
    perm(P.driverAttendanceMark, 'driver', 'تسجيل حضور الركاب',
        'Mark passenger attendance'),
    // Employee
    perm(P.employeeScheduleView, 'employee', 'عرض جدولي', 'View my schedule'),
    perm(P.employeeUniformView, 'employee', 'عرض ملابسي', 'View my uniform'),
    perm(P.employeeRequestsCreate, 'employee', 'تقديم طلب', 'Submit a request'),
    perm(P.employeeDocumentsManage, 'employee', 'إدارة وثائقي',
        'Manage my documents'),
    // Tracking
    perm(P.trackingLiveView, 'tracking', 'تتبع مباشر للباصات',
        'Live bus tracking'),
    // Reports
    perm(P.reportsView, 'reports', 'عرض التقارير', 'View reports'),
    perm(P.reportsExport, 'reports', 'تصدير التقارير', 'Export reports'),
    // 🆕 Reports — dedicated per-screen permissions
    perm(P.reportsSmartAlertsView, 'reports',
        'عرض مَركَز التَنبيهات الذَكيّة', 'View Smart Alerts dashboard'),
    perm(P.reportsAnalyticsView, 'reports',
        'عرض لوحة التَحليلات', 'View Analytics dashboard'),
    perm(P.reportsDataQualityView, 'reports',
        'عرض جَودة البَيانات', 'View Data Quality dashboard'),
    perm(P.reportsCompanyCalendarView, 'reports',
        'عرض تَقويم الشَركة', 'View Company Calendar'),
    // Training
    perm(P.trainingView, 'training', 'عرض الدورات', 'View training courses'),
    perm(P.trainingManage, 'training', 'إدارة الدورات', 'Manage courses'),
    perm(P.trainingRecord, 'training', 'تسجيل إكمال دورة',
        'Record course completion'),
    perm(P.trainingReport, 'training', 'تقارير التدريب', 'Training reports'),
    perm(P.trainingOnPointView, 'training', 'عرض تدريب الجدد',
        'View OnPoint training'),
    perm(P.trainingOnPointEvaluate, 'training', 'اعتماد المتدرّب',
        'Evaluate trainee'),
    perm(P.trainingOnPointManage, 'training', 'إعدادات تدريب الجدد',
        'Manage OnPoint training'),
    // Org
    perm(P.orgView, 'org', 'عرض الهيكل التنظيمي', 'View org chart'),
    perm(P.orgManage, 'org', 'تعديل الهيكل التنظيمي', 'Manage org structure'),
    // Forms / Workflows
    perm(P.formsSubmit, 'forms', 'تقديم نموذج', 'Submit form'),
    perm(P.formsApprove, 'forms', 'الموافقة على النماذج', 'Approve forms'),
    perm(P.formsManage, 'forms', 'إدارة قوالب النماذج', 'Manage form templates'),
    // Device sessions / Geo-fence / Login method / Face
    perm(P.adminDeviceSessionsView, 'admin', 'عرض جلسات الأجهزة',
        'View device sessions'),
    perm(P.adminDeviceSessionsManage, 'admin', 'إدارة جلسات الأجهزة',
        'Manage device sessions'),
    perm(P.adminGeoFenceView, 'admin', 'عرض سياسة الموقع',
        'View geo-fence policy'),
    perm(P.adminGeoFenceManage, 'admin', 'إدارة سياسة الموقع',
        'Manage geo-fence'),
    perm(P.adminLoginMethodView, 'admin', 'عرض طريقة الدخول',
        'View login method'),
    perm(P.adminLoginMethodManage, 'admin', 'إدارة طريقة الدخول',
        'Manage login method'),
    perm(P.employeesFaceEnroll, 'employees', 'تسجيل بصمة الوجه',
        'Enroll face'),
    perm(P.employeesFaceDelete, 'employees', 'حذف بصمة الوجه',
        'Delete face enrollment'),
    // ===== Attendance (تحت HR) =====
    // ===== Policies =====
    perm(P.policiesView, 'policies', 'عرض السياسات', 'View policies'),
    perm(P.policiesEdit, 'policies', 'تعديل سياسة', 'Edit policy'),
    // ===== Evaluations =====
    // ===== Deductions =====
    // ===== Customers / Branches =====
    // ===== Lookups (الأقسام/المسمّيات/الدول) =====
    // ===== Users / Roles =====
    perm(P.adminUsersCreate, 'admin', 'إنشاء حساب', 'Create account'),
    perm(P.adminUsersEdit, 'admin', 'تعديل حساب', 'Edit account'),
    perm(P.adminUsersDelete, 'admin', 'حذف حساب', 'Delete account'),
    // Settings
    perm(P.settingsLookupsView, 'settings', 'عرض القوائم المرجعية',
        'View lookups'),
    perm(P.settingsLookupsEdit, 'settings', 'تعديل القوائم المرجعية',
        'Edit lookups'),
    perm(P.settingsLookupsCreate, 'settings', 'إنشاء عنصر مرجعي',
        'Create lookup'),
    perm(P.settingsLookupsDelete, 'settings', 'حذف عنصر مرجعي',
        'Delete lookup'),
    perm(P.settingsNumberingEdit, 'settings', 'تعديل نظام الترقيم',
        'Edit numbering'),
    perm(P.settingsSystemView, 'settings', 'عرض إعدادات النظام',
        'View system settings'),
    perm(P.settingsSystemEdit, 'settings', 'تعديل إعدادات النظام',
        'Edit system settings'),

    // ============================================================
    // 🆕 صلاحيّات على مستوى الصفحة (page-level) لكل صفحات التطبيق
    // ============================================================

    // ===== Uniforms (الزيّ) =====
    perm(P.uniformCatalogView, 'uniform', 'عرض كتالوج الزيّ',
        'View uniform catalog'),
    perm(P.uniformCatalogCreate, 'uniform',
        'إضافة عنصر للكتالوج', 'Add catalog item'),
    perm(P.uniformCatalogEdit, 'uniform',
        'تعديل عنصر بالكتالوج', 'Edit catalog item'),
    perm(P.uniformCatalogDelete, 'uniform',
        'حذف عنصر من الكتالوج', 'Delete catalog item'),
    perm(P.uniformIssueView, 'uniform',
        'عرض عمليّات الصرف', 'View uniform issues'),
    perm(P.uniformIssueCreate, 'uniform', 'صرف زيّ لموظّف',
        'Issue uniform to employee'),
    perm(P.uniformIssueEdit, 'uniform',
        'تعديل عمليّة صرف', 'Edit issue record'),
    perm(P.uniformIssueDelete, 'uniform',
        'حذف عمليّة صرف', 'Delete issue record'),
    perm(P.uniformReceiveView, 'uniform',
        'عرض عمليّات الاستلام', 'View receive records'),
    perm(P.uniformReceiveCreate, 'uniform', 'استلام زيّ مرتجع',
        'Receive returned uniform'),
    perm(P.uniformReceiveEdit, 'uniform',
        'تعديل سجلّ استلام', 'Edit receive record'),
    perm(P.uniformReceiveDelete, 'uniform',
        'حذف سجلّ استلام', 'Delete receive record'),
    perm(P.uniformReportsView, 'uniform',
        'عرض تقارير الزيّ', 'View uniform reports'),
    perm(P.uniformReportsExport, 'uniform',
        'تصدير تقارير الزيّ', 'Export uniform reports'),

    // ===== HR pages — صفحات HR التفصيليّة =====
    perm(P.hrOnboardingView, 'hr', 'عرض ملفّات التهيئة',
        'View onboarding records'),
    perm(P.hrOnboardingCreate, 'hr',
        'إنشاء ملفّ تهيئة', 'Create onboarding record'),
    perm(P.hrOnboardingEdit, 'hr',
        'تعديل ملفّ تهيئة', 'Edit onboarding record'),
    perm(P.hrOnboardingDelete, 'hr',
        'حذف ملفّ تهيئة', 'Delete onboarding record'),
    perm(P.hrDocumentsView, 'hr',
        'عرض وثائق الموظّفين', 'View employee documents'),
    perm(P.hrDocumentsCreate, 'hr',
        'رفع وثيقة', 'Upload document'),
    perm(P.hrDocumentsEdit, 'hr',
        'تعديل وثيقة', 'Edit document'),
    perm(P.hrDocumentsDelete, 'hr',
        'حذف وثيقة', 'Delete document'),
    perm(P.hrReportsView, 'hr',
        'عرض تقارير HR', 'View HR reports'),
    perm(P.hrReportsExport, 'hr',
        'تصدير تقارير HR', 'Export HR reports'),

    // ===== Camp Laundry — صفحات فرعيّة =====
    perm(P.campLaundryBatchesView, 'camp',
        'عرض دفعات المغسلة', 'View laundry batches'),
    perm(P.campLaundryBatchesCreate, 'camp',
        'إنشاء دفعة مغسلة', 'Create laundry batch'),
    perm(P.campLaundryReceiveCreate, 'camp',
        'استلام مغسلة', 'Laundry receive'),
    perm(P.campLaundryDeliverCreate, 'camp',
        'تسليم مغسلة', 'Laundry deliver'),
    perm(P.campLaundryReportsView, 'camp',
        'عرض تقارير المغسلة', 'View laundry reports'),
    perm(P.campLaundryReportsExport, 'camp',
        'تصدير تقارير المغسلة', 'Export laundry reports'),
    perm(P.campLaundrySuppliersView, 'camp',
        'عرض موردي المغسلة', 'View laundry suppliers'),
    perm(P.campLaundrySuppliersEdit, 'camp',
        'تعديل موردي المغسلة', 'Edit laundry suppliers'),
    perm(P.campLaundryPickupView, 'camp',
        'عرض مواعيد الاستلام', 'View pickup window'),
    perm(P.campLaundryPickupEdit, 'camp',
        'تعديل مواعيد الاستلام', 'Edit pickup window'),

    // ===== Buses sub-pages =====
    perm(P.busesDriversView, 'buses',
        'عرض سائقي الباصات', 'View bus drivers'),
    perm(P.busesDriversEdit, 'buses',
        'تعيين/تعديل سائقي الباصات', 'Assign/edit bus drivers'),
    perm(P.busesReportsView, 'buses',
        'عرض تقارير الباصات', 'View bus reports'),
    perm(P.busesReportsExport, 'buses',
        'تصدير تقارير الباصات', 'Export bus reports'),

    // ===== Driver sub-pages =====
    perm(P.driverRouteMapView, 'driver',
        'عرض خريطة المسار', 'View route map'),

    // ===== Employees - bulk import =====
    perm(P.employeesBulkImportView, 'employees',
        'عرض شاشة الاستيراد الجماعي', 'View bulk import'),
    perm(P.employeesBulkImportManage, 'employees',
        'تنفيذ استيراد جماعي', 'Manage bulk import'),

    // ===== Admin tools =====
    perm(P.adminSystemHealthView, 'admin',
        'عرض حالة النظام', 'View system health'),
    perm(P.adminNotificationsSend, 'admin',
        'إرسال إشعارات', 'Send notifications'),
    perm(P.adminWhatsNewView, 'admin',
        'عرض ما الجديد', 'View What\'s New'),
    perm(P.adminWhatsNewEdit, 'admin',
        'تعديل ما الجديد', 'Edit What\'s New'),
    perm(P.adminL4PromotionView, 'admin',
        'عرض ترقية L4', 'View L4 promotion'),
    perm(P.adminL4PromotionManage, 'admin',
        'إدارة ترقية L4', 'Manage L4 promotion'),

    // ===== Org sub-pages =====
    perm(P.orgChartView, 'org',
        'عرض الهيكل التنظيمي', 'View org chart'),
    perm(P.orgBuilderManage, 'org',
        'منشئ الهيكل (سحب وإفلات)', 'Org builder (drag-drop)'),
    perm(P.orgCoverageView, 'org',
        'عرض تغطية المسمّيات', 'View job title coverage'),
    perm(P.orgPointAssignmentView, 'org',
        'عرض إعداد ربط النقاط', 'View point assignment'),
    perm(P.orgPointAssignmentEdit, 'org',
        'تعديل ربط النقاط', 'Edit point assignment'),
    perm(P.orgDepartmentProfileView, 'org',
        'عرض ملفّ القسم', 'View department profile'),
    perm(P.orgJobTitleProfileView, 'org',
        'عرض ملفّ المسمّى', 'View job title profile'),

    // ===== Forms sub-pages =====
    perm(P.formsAdminView, 'forms',
        'عرض إدارة النماذج', 'View forms admin'),
    perm(P.formsAdminManage, 'forms',
        'إدارة النماذج', 'Manage forms admin'),
    perm(P.formsEmployeeView, 'forms',
        'نماذج الموظّف', 'View employee forms'),
    perm(P.formsApprovalsView, 'forms',
        'عرض الموافقات الخاصّة بي', 'View my approvals'),
    perm(P.formsApprovalsApprove, 'forms',
        'الموافقة من قائمة الموافقات', 'Approve from approvals list'),

    // ===== Workflows sub-pages =====
    perm(P.workflowsBuilderView, 'forms',
        'عرض منشئ سير الموافقات', 'View workflow builder'),
    perm(P.workflowsBuilderManage, 'forms',
        'إدارة سير الموافقات', 'Manage workflows'),
    perm(P.workflowsApprovalMatrixView, 'forms',
        'عرض مصفوفة الموافقات', 'View approval matrix'),

    // ===== Attendance reports (page-level) =====
    perm(P.attendanceReportsView, 'attendance',
        'عرض تقارير الحضور', 'View attendance reports'),
    perm(P.attendanceReportsExport, 'attendance',
        'تصدير تقارير الحضور', 'Export attendance reports'),

    // ===== إغلاق فجوات Admin/Settings =====
    perm(P.adminOverviewView, 'admin',
        'عرض نظرة عامّة Admin', 'View Admin overview'),
    perm(P.adminHomeView, 'admin',
        'عرض الصفحة الرئيسيّة Admin', 'View Admin home'),
    perm(P.adminHelpCenterView, 'admin',
        'عرض مركز المساعدة', 'View help center'),
    perm(P.adminImpersonateView, 'admin',
        'عرض شاشة الانتحال', 'View impersonate screen'),
    perm(P.adminImpersonateUse, 'admin',
        'استخدام الانتحال', 'Use impersonate'),
    perm(P.settingsHubView, 'settings',
        'فتح Settings Hub', 'Open Settings Hub'),
    perm(P.settingsDriverTrackingView, 'settings',
        'عرض إعدادات تتبّع السائقين', 'View driver tracking settings'),
    perm(P.settingsDriverTrackingEdit, 'settings',
        'تعديل إعدادات تتبّع السائقين', 'Edit driver tracking settings'),
    perm(P.adminJobTitlePermissionsView, 'admin',
        'عرض مصفوفة صلاحيّات المسمّيات',
        'View job title permissions matrix'),
    perm(P.adminJobTitlePermissionsManage, 'admin',
        'إدارة صلاحيّات المسمّيات',
        'Manage job title permissions'),
    // ===== Roster employee filter =====
    perm(P.settingsRosterEmployeeFilterView, 'settings',
        'عرض تصفية موظّفي الروستر',
        'View roster employee filter'),
    perm(P.settingsRosterEmployeeFilterEdit, 'settings',
        'تعديل تصفية موظّفي الروستر',
        'Edit roster employee filter'),
    perm(P.settingsRosterDeadlineView, 'settings',
        'عرض مواعيد الروستر',
        'View roster deadlines'),
    perm(P.settingsRosterDeadlineEdit, 'settings',
        'تعديل مواعيد الروستر',
        'Edit roster deadlines'),
    perm(P.settingsDeleteSpecificRosterManage, 'settings',
        'حذف روستر محدّد',
        'Delete specific roster'),
    // ===== Reports — تقارير لكلّ موديول =====
    perm(P.reportsEmployeesView, 'reports',
        'عرض تقرير الموظفين', 'View employees report'),
    perm(P.reportsEmployeesExport, 'reports',
        'تصدير تقرير الموظفين', 'Export employees report'),
    perm(P.reportsSitesView, 'reports',
        'عرض تقرير المواقع', 'View sites report'),
    perm(P.reportsSitesExport, 'reports',
        'تصدير تقرير المواقع', 'Export sites report'),
    perm(P.reportsRostersView, 'reports',
        'عرض تقرير الروسترات', 'View rosters report'),
    perm(P.reportsRostersExport, 'reports',
        'تصدير تقرير الروسترات', 'Export rosters report'),
    perm(P.reportsBusesView, 'reports',
        'عرض تقرير الباصات', 'View buses report'),
    perm(P.reportsBusesExport, 'reports',
        'تصدير تقرير الباصات', 'Export buses report'),
    perm(P.reportsDeductionsView, 'reports',
        'عرض تقرير الخصومات', 'View deductions report'),
    perm(P.reportsDeductionsExport, 'reports',
        'تصدير تقرير الخصومات', 'Export deductions report'),
    perm(P.reportsLaundryView, 'reports',
        'عرض تقرير المغسلة', 'View laundry report'),
    perm(P.reportsLaundryExport, 'reports',
        'تصدير تقرير المغسلة', 'Export laundry report'),
    perm(P.reportsUniformsView, 'reports',
        'عرض تقرير الزيّ', 'View uniforms report'),
    perm(P.reportsUniformsExport, 'reports',
        'تصدير تقرير الزيّ', 'Export uniforms report'),
    // ===== 🆕 Roster — مَجموعات مُستَقلّة لِكلّ شاشة =====
    // 📅 إنشاء روستر
    perm(P.rosterCreatorView, 'roster_creator',
        'فَتح شاشة إنشاء روستر', 'Open Create Roster screen'),
    perm(P.rosterCreatorCreate, 'roster_creator',
        'حِفظ روستر جَديد', 'Save new roster'),
    perm(P.rosterCreatorSubmit, 'roster_creator',
        'إرسال روستر للاعتماد', 'Submit roster for approval'),
    perm(P.rosterCreatorSelectAnyPoint, 'roster_creator',
        'اختيار أيّ نَقطة (للمدير)', 'Select any point (manager)'),
    // 📊 مركز الروسترات
    perm(P.rostersCenterView, 'rosters_center',
        'عَرض مركز الروسترات', 'View Rosters Center'),
    perm(P.rostersCenterCreate, 'rosters_center',
        'إضافة من المركز', 'Create from Center'),
    perm(P.rostersCenterEdit, 'rosters_center',
        'تَعديل من المركز', 'Edit from Center'),
    perm(P.rostersCenterDelete, 'rosters_center',
        'حَذف من المركز', 'Delete from Center'),
    perm(P.rostersCenterExport, 'rosters_center',
        'تَصدير من المركز', 'Export from Center'),
    // ✅ اعتماد الروسترات
    perm(P.rosterApprovalsView, 'roster_approvals',
        'عَرض شاشة الاعتماد', 'View Approvals screen'),
    perm(P.rosterApprovalsApprove, 'roster_approvals',
        'اعتماد روستر', 'Approve roster'),
    perm(P.rosterApprovalsReject, 'roster_approvals',
        'رَفض روستر', 'Reject roster'),
    perm(P.rosterApprovalsEditApproved, 'roster_approvals',
        'تَعديل روستر مُعتَمَد', 'Edit approved roster'),
    // 📋 الروستر المعتمد
    perm(P.approvedRosterView, 'approved_roster',
        'عَرض الروستر المعتمد', 'View approved roster'),
    perm(P.approvedRosterExport, 'approved_roster',
        'تَصدير الروستر المعتمد', 'Export approved roster'),
    // 👤 روستري
    perm(P.myRosterView, 'my_roster',
        'عَرض روستري الشَخصيّ', 'View my roster'),
    // ===== 🆕 Leave Management =====
    perm(P.leaveRequestSubmit, 'leave',
        'تَقديم طَلَب إجازة', 'Submit leave request'),
    perm(P.leaveRequestView, 'leave',
        'عَرض طَلَباتي ورَصيدي', 'View my requests & balance'),
    perm(P.leaveRequestCancel, 'leave',
        'إلغاء طَلَبي', 'Cancel my request'),
    perm(P.leaveTeamView, 'leave',
        'عَرض طَلَبات الفَريق', 'View team requests'),
    perm(P.leaveTeamApprove, 'leave',
        'اعتماد/رَفض طَلَبات الفَريق', 'Approve/reject team requests'),
    perm(P.leaveBalanceManage, 'leave',
        'تَعديل رَصيد الإجازات', 'Manage leave balances'),
    perm(P.leaveReportView, 'leave',
        'عَرض تَقرير الإجازات', 'View leave report'),
    perm(P.leaveReportExport, 'leave',
        'تَصدير تَقرير الإجازات', 'Export leave report'),
    // ===== 🆕 Daily Memo =====
    perm(P.dailyMemoCreate, 'daily_memo',
        'إنشاء/تَعديل مذكّرتي اليوميّة',
        'Create/edit my daily memo'),
    perm(P.dailyMemoView, 'daily_memo',
        'عرض مذكّراتي الخاصّة', 'View my daily memos'),
    perm(P.dailyMemoViewTeam, 'daily_memo',
        'عرض مذكّرات الفريق', 'View team daily memos'),
    perm(P.dailyMemoEditTeam, 'daily_memo',
        'تَعديل مذكّرات الفريق', 'Edit team daily memos'),
    perm(P.dailyMemoDelete, 'daily_memo',
        'حذف مذكّراتي', 'Delete my daily memos'),
    perm(P.dailyMemoReportView, 'daily_memo',
        'عرض تقرير المذكّرات', 'View daily memo report'),
    perm(P.dailyMemoReportExport, 'daily_memo',
        'تَصدير تقرير المذكّرات', 'Export daily memo report'),
    // ===== 🆕 Site Onboarding =====
    perm(P.siteOnboardingView, 'site_onboarding',
        'عَرض المواقِع الجَديدة', 'View new sites'),
    perm(P.siteOnboardingUpdateSetup, 'site_onboarding',
        'تَعديل حالات التَجهيز', 'Update setup statuses'),
    perm(P.siteOnboardingGoLive, 'site_onboarding',
        'تَفعيل/إعادة تَفعيل الموقِع', 'Activate / re-activate site'),
    perm(P.siteOnboardingArchive, 'site_onboarding',
        'أَرشَفة الموقِع', 'Archive site'),
    perm(P.siteOnboardingReportView, 'site_onboarding',
        'عَرض تَقارير المواقِع', 'View sites reports'),
    perm(P.siteOnboardingReportExport, 'site_onboarding',
        'تَصدير تَقارير المواقِع', 'Export sites reports'),

    // 🆕 وَثائِق المُوَظَّفين (Document Version Trail)
    perm(P.employeeDocumentsView, 'documents',
        'عَرض وَثائِق المُوَظَّفين', 'View employee documents'),
    perm(P.employeeDocumentsUpload, 'documents',
        'رَفع/تَجديد وَثيقة', 'Upload/renew documents'),
    perm(P.employeeDocumentsRevoke, 'documents',
        'إلغاء وَثيقة (revoke)', 'Revoke a document'),
    perm(P.employeeDocumentsHardDelete, 'documents',
        'حَذف نِهائيّ لِوَثيقة', 'Hard-delete a document'),
    perm(P.employeeDocumentsExpiryReport, 'documents',
        'تَقرير الوَثائِق المُنتَهية', 'Documents expiry report'),

    // 🆕 جِهاز نُقطة الدَوام (Point Terminal)
    perm(P.pointTerminalView, 'point_terminal',
        'عَرض حِسابات أَجهِزة النِقاط', 'View terminal accounts'),
    perm(P.pointTerminalManage, 'point_terminal',
        'إنشاء/إعادة تَوليد كَلِمة مُرور Terminal',
        'Create/regenerate terminal password'),
    perm(P.pointTerminalDelete, 'point_terminal',
        'حَذف حِساب Terminal', 'Delete terminal account'),
    perm(P.pointAttendanceReportView, 'point_terminal',
        'عَرض تَقرير دَوام النِقاط', 'View point attendance report'),
    perm(P.pointAttendanceReportExport, 'point_terminal',
        'تَصدير تَقرير دَوام النِقاط', 'Export point attendance report'),
    perm(P.settingsPointTerminalView, 'settings',
        'عَرض إعدادات Point Terminal',
        'View Point Terminal settings'),
    perm(P.settingsPointTerminalEdit, 'settings',
        'تَعديل إعدادات Point Terminal',
        'Edit Point Terminal settings'),

    // ============================================================
    // 🆕 PHASE 1 — صَلاحيّات الميزات الجَديدة (2026-05-23)
    // ============================================================

    // 💰 Tips
    perm(P.tipsView, 'tips', 'عَرض البَقاشيش', 'View tips'),
    perm(P.tipsCreate, 'tips', 'تَسجيل بَقشيش', 'Record tip'),
    perm(P.tipsDelete, 'tips', 'حَذف بَقشيش', 'Delete tip'),
    perm(P.tipsLeaderboardView, 'tips',
        'عَرض لَوحة المُتَصَدِّرين', 'View leaderboard'),
    perm(P.tipsExport, 'tips', 'تَصدير تَقرير البَقاشيش', 'Export tips report'),

    // 💾 Backups
    perm(P.backupsView, 'backups',
        'عَرض النُسَخ الاحتِياطيّة', 'View backups'),
    perm(P.backupsRunStats, 'backups',
        'تَشغيل نَسخة إحصاءات', 'Run stats backup'),
    perm(P.backupsRunFull, 'backups',
        'تَشغيل نَسخة فِعليّة كامِلة', 'Run full data backup'),
    perm(P.backupsDownload, 'backups',
        'تَنزيل نَسخة احتِياطيّة', 'Download backup'),

    // 🔒 GDPR
    perm(P.gdprAnonymize, 'gdpr',
        '🔒 إخفاء هُوِيّة مُوَظَّف (لا رَجعة فيه)',
        '🔒 Anonymize employee (irreversible)'),
    perm(P.gdprCandidatesView, 'gdpr',
        'عَرض المُرَشَّحين لِلإخفاء', 'View anonymization candidates'),

    // 📜 Audit splits
    perm(P.auditSettingsView, 'audit',
        'عَرض سِجِلّ تَدقيق الإعدادات', 'View settings audit'),
    perm(P.auditActivityView, 'audit',
        'عَرض تَدَفُّق النَشاطات', 'View activity feed'),

    // 👤 Employee Status
    perm(P.employeeStatusHistoryView, 'employees',
        'عَرض سِجِلّ حالة المُوَظَّف', 'View employee status history'),
    perm(P.employeeStatusChange, 'employees',
        'تَغيير حالة المُوَظَّف يَدَويّاً', 'Change employee status manually'),

    // 🇦🇪 UAE Gov fields
    perm(P.employeesGovFieldsView, 'employees',
        'عَرض الحُقول الحُكومِيّة (EID/MOHRE/WASL)',
        'View government fields (EID/MOHRE/WASL)'),
    perm(P.employeesGovFieldsEdit, 'employees',
        'تَعديل الحُقول الحُكومِيّة',
        'Edit government fields'),

    // 📤 Generic exports
    perm(P.exportExcel, 'export',
        'تَصدير إلى Excel', 'Export to Excel'),
    perm(P.exportPdf, 'export',
        'تَصدير إلى PDF', 'Export to PDF'),
  ];

  // ========================================
  // 3) Helper: ربط دور بصلاحيات
  // ========================================
  final permsByKey = {for (final p in permissions) p.key: p};
  final rolePermissions = <RolePermissionLink>[];
  void grant(RoleDef role, List<String> keys) {
    for (final k in keys) {
      final perm = permsByKey[k];
      if (perm == null) continue;
      rolePermissions.add(RolePermissionLink(
        roleId: role.id,
        permissionId: perm.id,
      ));
    }
  }

  // Super Admin: كل شيء
  grant(superAdminRole, permsByKey.keys.toList());

  // Admin: كل شيء داخل دولته
  grant(adminRole, permsByKey.keys.toList());

  // Manager
  grant(managerRole, [
    P.dashboardManagerView,
    P.sitesView,
    P.employeesView,
    P.busesView,
    P.rostersView,
    P.rostersCreate, P.rostersSubmit,
    P.rostersApprove, P.rostersReject, P.rostersEditApproved,
    P.rostersSelectAnyPoint,
    P.attendanceView, P.attendanceCreate, P.attendanceEdit,
    P.attendanceDelete, P.attendanceExport,
    P.attendanceReportsView, P.attendanceReportsExport,
    P.trackingLiveView,
    P.reportsView, P.reportsExport,
    // 🆕 Dedicated reports screens — manager gets all 4
    P.reportsSmartAlertsView, P.reportsAnalyticsView,
    P.reportsDataQualityView, P.reportsCompanyCalendarView,
    P.policiesView, P.policiesEdit,
    P.evaluationsView, P.evaluationsCreate, P.evaluationsEdit,
    P.evaluationCriteriaView, P.evaluationCriteriaEdit,
    P.deductionsView, P.deductionsCreate,
    P.formsView, P.formsApprove,
    P.formsAdminView, P.formsApprovalsView, P.formsApprovalsApprove,
    P.workflowsApprovalMatrixView,
    P.orgView, P.orgChartView, P.orgCoverageView,
    P.orgDepartmentProfileView, P.orgJobTitleProfileView,
    // HR pages
    P.hrOnboardingView, P.hrOnboardingCreate, P.hrOnboardingEdit,
    P.hrDocumentsView,
    P.hrReportsView, P.hrReportsExport,
    // 🆕 وَثائِق المُوَظَّفين (إصدارات) + تَقرير الانتِهاء
    P.employeeDocumentsView,
    P.employeeDocumentsUpload,
    P.employeeDocumentsRevoke,
    P.employeeDocumentsExpiryReport,
    // 🆕 تَقرير دَوام النِقاط
    P.pointTerminalView,
    P.pointAttendanceReportView,
    // Buses sub-pages
    P.busesDriversView, P.busesReportsView, P.busesReportsExport,
    // Uniforms
    P.uniformCatalogView, P.uniformReportsView,
    // Bulk import
    P.employeesBulkImportView,
    // Admin tools — read-only for manager
    P.adminSystemHealthView, P.adminWhatsNewView,
    P.adminOverviewView, P.adminHomeView, P.adminHelpCenterView,
    P.settingsHubView,
    P.settingsDriverTrackingView,
    P.adminJobTitlePermissionsView, P.adminJobTitlePermissionsManage,
    // 🆕 تصفية موظّفي الروستر + مواعيد الروستر
    P.settingsRosterEmployeeFilterView, P.settingsRosterEmployeeFilterEdit,
    P.settingsRosterDeadlineView, P.settingsRosterDeadlineEdit,
    P.settingsDeleteSpecificRosterManage,
    // 🆕 التقارير الفرعيّة (Manager يرى ويصدّر كلّ التقارير)
    P.reportsEmployeesView, P.reportsEmployeesExport,
    P.reportsSitesView, P.reportsSitesExport,
    P.reportsRostersView, P.reportsRostersExport,
    P.reportsBusesView, P.reportsBusesExport,
    P.reportsDeductionsView, P.reportsDeductionsExport,
    P.reportsLaundryView, P.reportsLaundryExport,
    P.reportsUniformsView, P.reportsUniformsExport,
    // 🆕 Daily Memo — Manager يَرى تقرير الفريق ويُصدّره
    P.dailyMemoViewTeam, P.dailyMemoEditTeam,
    P.dailyMemoReportView, P.dailyMemoReportExport,
    // 🆕 Roster — مَجموعات مُستَقلّة (Manager يَملك الكلّ)
    P.rosterCreatorView, P.rosterCreatorCreate, P.rosterCreatorSubmit,
    P.rosterCreatorSelectAnyPoint,
    P.rostersCenterView, P.rostersCenterCreate, P.rostersCenterEdit,
    P.rostersCenterDelete, P.rostersCenterExport,
    P.rosterApprovalsView, P.rosterApprovalsApprove,
    P.rosterApprovalsReject, P.rosterApprovalsEditApproved,
    P.approvedRosterView, P.approvedRosterExport,
    // 🆕 Leave Management — Manager يَملك كلّ شَيء
    P.leaveRequestSubmit, P.leaveRequestView, P.leaveRequestCancel,
    P.leaveTeamView, P.leaveTeamApprove, P.leaveBalanceManage,
    P.leaveReportView, P.leaveReportExport,
    // 🆕 Site Onboarding — Manager يَملك الكلّ
    P.siteOnboardingView, P.siteOnboardingUpdateSetup,
    P.siteOnboardingGoLive, P.siteOnboardingArchive,
    P.siteOnboardingReportView, P.siteOnboardingReportExport,
  ]);

  // Operation
  grant(operationRole, [
    P.dashboardOperationView,
    P.sitesView, P.employeesView, P.busesView,
    P.rostersView, P.rostersCreate, P.rostersSubmit,
    P.rostersApprove, P.rostersReject, P.rostersEditApproved,
    P.rostersSelectAnyPoint,
    P.attendanceView, P.attendanceCreate, P.attendanceEdit,
    P.attendanceDelete, P.attendanceExport,
    P.attendanceReportsView, P.attendanceReportsExport,
    P.trackingLiveView,
    P.reportsView,
    // 🆕 Dedicated reports screens — operation gets all 4 read-only
    P.reportsSmartAlertsView, P.reportsAnalyticsView,
    P.reportsDataQualityView, P.reportsCompanyCalendarView,
    P.policiesView,
    P.evaluationsView,
    // HR pages — Operation sees onboarding & documents
    P.hrOnboardingView, P.hrOnboardingCreate, P.hrOnboardingEdit,
    P.hrDocumentsView, P.hrDocumentsCreate, P.hrDocumentsEdit,
    P.hrReportsView,
    // Org read-only
    P.orgView, P.orgChartView, P.orgDepartmentProfileView,
    P.orgJobTitleProfileView,
    // Forms approvals
    P.formsView, P.formsApprovalsView, P.formsApprovalsApprove,
    // Driver route map (oversight)
    P.driverRouteMapView,
    // 🆕 التقارير — Operation يرى الموظفين/الروسترات/الباصات
    P.reportsEmployeesView, P.reportsRostersView, P.reportsBusesView,
    P.reportsSitesView,
    // 🆕 Daily Memo — Operation يَرى تقارير الفريق
    P.dailyMemoViewTeam,
    P.dailyMemoReportView, P.dailyMemoReportExport,
    // 🆕 Roster — Operation يَملك الكلّ ما عدا منع الحَذف
    P.rosterCreatorView, P.rosterCreatorCreate, P.rosterCreatorSubmit,
    P.rosterCreatorSelectAnyPoint,
    P.rostersCenterView, P.rostersCenterCreate, P.rostersCenterEdit,
    P.rostersCenterExport,
    P.rosterApprovalsView, P.rosterApprovalsApprove,
    P.rosterApprovalsReject, P.rosterApprovalsEditApproved,
    P.approvedRosterView, P.approvedRosterExport,
    // 🆕 Site Onboarding — Operation يُحَدِّث التَجهيز ويُفَعِّل
    P.siteOnboardingView, P.siteOnboardingUpdateSetup,
    P.siteOnboardingGoLive,
    P.siteOnboardingReportView,
    // 🆕 مَركَز المُساعَدة
    P.adminHelpCenterView,
  ]);

  // Supervisor
  grant(supervisorRole, [
    P.rostersView, P.rostersCreate, P.rostersSubmit,
    P.employeesView, P.sitesView,
    P.attendanceView, P.attendanceCreate, P.attendanceEdit,
    P.attendanceReportsView,
    P.campChecklistView, P.campChecklistCreate,
    P.evaluationsView, P.evaluationsCreate,
    P.policiesView,
    P.formsView, P.formsSubmit,
    P.formsEmployeeView, P.formsApprovalsView,
    P.hrDocumentsView,
    P.orgChartView,
    // 🆕 Daily Memo — Supervisor يَرى مذكّرات فريقه + التقرير
    P.dailyMemoViewTeam, P.dailyMemoReportView,
    // 🆕 Roster — Supervisor يُنشِئ ويُرسِل، ويَرى المركز + المعتمد
    P.rosterCreatorView, P.rosterCreatorCreate, P.rosterCreatorSubmit,
    P.rostersCenterView,
    P.approvedRosterView,
    // 🆕 مَركَز المُساعَدة
    P.adminHelpCenterView,
  ]);

  // Camp Boss
  grant(campBossRole, [
    P.dashboardCampView,
    P.campRoomsView, P.campRoomsRate,
    P.campRoomsCreate, P.campRoomsEdit, P.campRoomsDelete,
    P.campLaundryView, P.campLaundryProcess,
    P.campLaundryCreate, P.campLaundryEdit, P.campLaundryDelete,
    // Camp laundry sub-pages
    P.campLaundryBatchesView, P.campLaundryBatchesCreate,
    P.campLaundryReceiveCreate, P.campLaundryDeliverCreate,
    P.campLaundryReportsView, P.campLaundryReportsExport,
    P.campLaundrySuppliersView, P.campLaundrySuppliersEdit,
    P.campLaundryPickupView, P.campLaundryPickupEdit,
    P.campViolationsView, P.campViolationsCreate,
    P.campViolationsEdit, P.campViolationsDelete,
    P.campChecklistView, P.campChecklistCreate,
    P.campChecklistEdit, P.campChecklistDelete,
    P.busesView, P.busesAssign,
    P.busesDriversView, P.busesReportsView,
    // Uniforms — Camp Boss owns uniform inventory & issuance
    P.uniformCatalogView, P.uniformCatalogCreate, P.uniformCatalogEdit,
    P.uniformIssueView, P.uniformIssueCreate, P.uniformIssueEdit,
    P.uniformReceiveView, P.uniformReceiveCreate,
    P.uniformReportsView, P.uniformReportsExport,
    P.policiesView,
    P.formsView, P.formsSubmit,
    // 🆕 Camp Boss يرى تقارير المغسلة والزيّ
    P.reportsLaundryView, P.reportsUniformsView,
    // 🆕 مَركَز المُساعَدة
    P.adminHelpCenterView,
  ]);

  // Driver
  grant(driverRole, [
    P.driverTripsView,
    P.driverAttendanceMark,
    P.driverRouteMapView,
    P.policiesView,
    P.formsSubmit,
    // 🆕 مَركَز المُساعَدة
    P.adminHelpCenterView,
  ]);

  // Employee
  grant(employeeRole, [
    P.employeeScheduleView,
    P.employeeUniformView,
    P.employeeRequestsCreate,
    P.employeeDocumentsManage,
    P.policiesView,
    P.formsSubmit,
    P.formsEmployeeView,
    P.formsApprovalsView,
    // 🆕 Daily Memo — كلّ موظّف يَستطيع كتابة مذكّرته الخاصّة
    P.dailyMemoCreate, P.dailyMemoView, P.dailyMemoDelete,
    // 🆕 Roster — Employee يَرى روستره الخاصّ فقط
    P.myRosterView,
    // 🆕 Leave — كلّ موظّف يَستطيع تَقديم طَلَبات إجازة شَخصيّة
    P.leaveRequestSubmit, P.leaveRequestView, P.leaveRequestCancel,
    // 🆕 مَركَز المُساعَدة
    P.adminHelpCenterView,
  ]);

  // ========================================
  // 4) الحسابات التجريبيّة + إسناد الأدوار + الدول
  // ========================================
  final accounts = <AppAccount>[];
  final userRoles = <UserRoleAssignment>[];
  final userCountries = <UserCountryAccess>[];

  return RbacSeedResult(
    roles: roles,
    permissions: permissions,
    rolePermissions: rolePermissions,
    accounts: accounts,
    userRoles: userRoles,
    userCountries: userCountries,
  );
}
