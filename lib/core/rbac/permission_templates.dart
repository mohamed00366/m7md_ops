import '../../models/lookups.dart';
import '../../models/rbac.dart';

/// 🆕 قوالب صلاحيات افتراضية للمسميات الوظيفية
/// تحدد ما يراه حامل المسمى الوظيفي بناءً على:
///   1) تصنيف القسم (worker / admin / operations)
///   2) كلمات في الاسم (مدير / مشرف / محاسب / Officer / Manager / ...)
class PermissionTemplates {
  PermissionTemplates._();

  /// قالب الموظف الميداني (عامل) - الحد الأدنى
  static const workerBaseline = <String>[
    P.employeeScheduleView,
    P.employeeUniformView,
    P.employeeDocumentsManage,
    P.employeeRequestsCreate,
    P.policiesView,
    // 🆕 النماذج للموظّف (تقديم نموذج + متابعة الموافقات)
    P.formsSubmit,
    P.formsEmployeeView,
    P.formsApprovalsView,
  ];

  /// قالب موظف العمليات
  static const operationsBaseline = <String>[
    P.dashboardOperationView,
    P.rostersView,
    P.rostersCreate,
    P.rostersSubmit,
    P.rostersSelectAnyPoint,
    P.rostersApprove,
    P.rostersReject,
    P.rostersEditApproved,
    // 🆕 الحضور — CRUD + تصدير + تقارير
    P.attendanceView, P.attendanceCreate, P.attendanceEdit,
    P.attendanceDelete, P.attendanceExport,
    P.attendanceReportsView, P.attendanceReportsExport,
    P.trackingLiveView,
    P.reportsView,
    // 🆕 Dedicated reports screens
    P.reportsSmartAlertsView, P.reportsAnalyticsView,
    P.reportsDataQualityView, P.reportsCompanyCalendarView,
    P.employeesView,
    P.sitesView,
    P.busesView,
    P.busesDriversView, P.busesReportsView,
    P.policiesView,
    // 🆕 HR — تهيئة الموظّفين + الوثائق + التقارير (read+create)
    P.hrOnboardingView, P.hrOnboardingCreate, P.hrOnboardingEdit,
    P.hrDocumentsView, P.hrDocumentsCreate, P.hrDocumentsEdit,
    P.hrReportsView, P.hrReportsExport,
    // 🆕 النماذج — مراجعة/اعتماد
    P.formsView, P.formsApprovalsView, P.formsApprovalsApprove,
    P.workflowsApprovalMatrixView,
    // 🆕 السائقون — متابعة المسار
    P.driverRouteMapView,
    // 🆕 الهيكل التنظيمي — قراءة فقط
    P.orgView, P.orgChartView, P.orgDepartmentProfileView,
    P.orgJobTitleProfileView,
  ];

  /// قالب الموظف الإداري
  static const adminBaseline = <String>[
    P.employeesView,
    P.employeesCreate,
    P.employeesEdit,
    P.sitesView,
    P.reportsView,
    // 🆕 Dedicated reports screens — admin baseline includes all 4
    P.reportsSmartAlertsView, P.reportsAnalyticsView,
    P.reportsDataQualityView, P.reportsCompanyCalendarView,
    P.settingsLookupsView,
    P.policiesView,
    // 🆕 صفحات Admin/Settings الأساسيّة
    P.adminHomeView, P.adminOverviewView, P.adminHelpCenterView,
    P.settingsHubView,
    // 🆕 الهيكل التنظيمي — قراءة
    P.orgView, P.orgChartView,
    P.orgDepartmentProfileView, P.orgJobTitleProfileView,
    // 🆕 HR — وثائق + تقارير قراءة
    P.hrDocumentsView, P.hrReportsView,
    // 🆕 النماذج
    P.formsView, P.formsAdminView,
  ];

  /// قالب المدير: قاعدة + إضافات (تعديل/حذف/اعتماد)
  static const managerExtras = <String>[
    P.employeesEdit,
    P.employeesActivate,
    P.employeesDelete,
    P.employeesBulkImportView, P.employeesBulkImportManage,
    P.sitesCreate,
    P.sitesEdit,
    P.sitesDelete,
    P.busesCreate,
    P.busesEdit,
    P.busesDelete,
    P.busesAssign,
    P.busesDriversView, P.busesDriversEdit,
    P.busesReportsView, P.busesReportsExport,
    P.rostersCreate,
    P.rostersSubmit,
    P.rostersApprove,
    P.rostersReject,
    P.rostersEditApproved,
    P.rostersSelectAnyPoint,
    // 🆕 الحضور — CRUD + تصدير + تقارير
    P.attendanceView, P.attendanceCreate, P.attendanceEdit,
    P.attendanceDelete, P.attendanceExport,
    P.attendanceReportsView, P.attendanceReportsExport,
    // السياسات (تعديل)
    P.policiesEdit,
    P.reportsExport,
    P.settingsLookupsEdit,
    P.settingsLookupsCreate,
    P.settingsLookupsDelete,
    P.settingsNumberingEdit,
    // 🆕 HR — تهيئة الموظّفين + وثائق + تقارير CRUD
    P.hrOnboardingView, P.hrOnboardingCreate, P.hrOnboardingEdit,
    P.hrOnboardingDelete,
    P.hrDocumentsView, P.hrDocumentsCreate, P.hrDocumentsEdit,
    P.hrDocumentsDelete,
    P.hrReportsView, P.hrReportsExport,
    // 🆕 الزيّ — قراءة + تقارير
    P.uniformCatalogView, P.uniformReportsView, P.uniformReportsExport,
    // 🆕 النماذج وسير الموافقات
    P.formsView, P.formsApprove, P.formsManage,
    P.formsAdminView, P.formsAdminManage,
    P.formsApprovalsView, P.formsApprovalsApprove,
    P.workflowsView, P.workflowsCreate, P.workflowsEdit,
    P.workflowsBuilderView, P.workflowsBuilderManage,
    P.workflowsApprovalMatrixView,
    // 🆕 الهيكل التنظيمي — كامل
    P.orgView, P.orgManage,
    P.orgChartView, P.orgBuilderManage, P.orgCoverageView,
    P.orgPointAssignmentView, P.orgPointAssignmentEdit,
    P.orgDepartmentProfileView, P.orgJobTitleProfileView,
    // 🆕 صلاحيّات Admin أساسيّة للمدير
    P.adminSystemHealthView, P.adminWhatsNewView, P.adminWhatsNewEdit,
    P.adminJobTitlePermissionsView, P.adminJobTitlePermissionsManage,
  ];

  /// قالب المشرف: عرض موظفيه + إنشاء روسترات + التتبع + الحضور
  static const supervisorExtras = <String>[
    P.rostersCreate,
    P.rostersSubmit,
    // 🆕 الحضور — view/create/edit (بدون حذف لمشرف عاديّ)
    P.attendanceView, P.attendanceCreate, P.attendanceEdit,
    P.attendanceReportsView,
    P.trackingLiveView,
    P.campChecklistView,
    P.campChecklistCreate,
    // 🆕 HR — وثائق قراءة فقط للمشرف
    P.hrDocumentsView,
    // 🆕 النماذج
    P.formsView, P.formsSubmit,
    P.formsEmployeeView, P.formsApprovalsView, P.formsApprovalsApprove,
    // 🆕 الهيكل التنظيمي — قراءة
    P.orgChartView,
  ];

  /// قالب المحاسب: تقارير مالية + قوائم
  static const accountantExtras = <String>[
    P.reportsView,
    P.reportsExport,
    // 🆕 Dedicated reports screens — accountant gets all 4
    P.reportsSmartAlertsView, P.reportsAnalyticsView,
    P.reportsDataQualityView, P.reportsCompanyCalendarView,
    P.settingsLookupsView,
  ];

  /// قالب Camp Boss: كل الكامب + إنشاء/تعديل
  static const campBossBaseline = <String>[
    P.dashboardCampView,
    P.campRoomsView,
    P.campRoomsRate,
    P.campRoomsCreate,
    P.campRoomsEdit,
    P.campRoomsDelete,
    P.campLaundryView,
    P.campLaundryProcess,
    P.campLaundryCreate,
    P.campLaundryEdit,
    P.campLaundryDelete,
    // 🆕 المغسلة — صفحات فرعيّة
    P.campLaundryBatchesView, P.campLaundryBatchesCreate,
    P.campLaundryReceiveCreate, P.campLaundryDeliverCreate,
    P.campLaundryReportsView, P.campLaundryReportsExport,
    P.campLaundrySuppliersView, P.campLaundrySuppliersEdit,
    P.campLaundryPickupView, P.campLaundryPickupEdit,
    P.campViolationsView,
    P.campViolationsCreate,
    P.campViolationsApprove,
    P.campChecklistView,
    P.campChecklistCreate,
    P.busesView,
    P.busesAssign,
    P.busesDriversView, P.busesReportsView,
    // 🆕 الزيّ الموحّد — كامل (Camp Boss يدير الزيّ)
    P.uniformCatalogView, P.uniformCatalogCreate, P.uniformCatalogEdit,
    P.uniformIssueView, P.uniformIssueCreate, P.uniformIssueEdit,
    P.uniformReceiveView, P.uniformReceiveCreate,
    P.uniformReportsView, P.uniformReportsExport,
    P.policiesView,
    // 🆕 النماذج
    P.formsView, P.formsSubmit, P.formsEmployeeView,
  ];

  /// قالب السائق: رحلاته فقط + علامة الحضور + خريطة المسار + النماذج
  static const driverBaseline = <String>[
    P.driverTripsView,
    P.driverAttendanceMark,
    P.driverRouteMapView,
    P.policiesView,
    P.formsSubmit, P.formsEmployeeView, P.formsApprovalsView,
  ];

  /// 🎯 الحساب الأذكى: قاعدة من القسم + إضافات من اسم الوظيفة
  static List<String> recommendFor({
    required JobTitleCategory category,
    required String nameAr,
    required String nameEn,
  }) {
    final base = _baselineForCategory(category);
    final extras = _extrasForName(nameAr: nameAr, nameEn: nameEn);
    final result = <String>{...base, ...extras};
    return result.toList();
  }

  static List<String> _baselineForCategory(JobTitleCategory cat) {
    switch (cat) {
      case JobTitleCategory.admin:      return adminBaseline;
      case JobTitleCategory.operations: return operationsBaseline;
      case JobTitleCategory.worker:     return workerBaseline;
    }
  }

  static List<String> _extrasForName({required String nameAr, required String nameEn}) {
    final lower = '${nameAr.toLowerCase()} ${nameEn.toLowerCase()}';
    final result = <String>[];

    // مدير / Manager → كل صلاحيات إضافية
    if (_contains(lower, ['مدير', 'manager', 'director', 'chief'])) {
      result.addAll(managerExtras);
    }
    // مشرف / Supervisor → روسترات + تتبع
    if (_contains(lower, ['مشرف', 'supervisor', 'foreman'])) {
      result.addAll(supervisorExtras);
    }
    // محاسب / Accountant → تقارير
    if (_contains(lower, ['محاسب', 'accountant', 'finance', 'مالية'])) {
      result.addAll(accountantExtras);
    }
    // مدير الكامب / Camp Boss
    if (_contains(lower, ['كامب', 'كمب', 'camp boss', 'camp manager'])) {
      result.addAll(campBossBaseline);
    }
    // سائق / Driver
    if (_contains(lower, ['سائق', 'driver'])) {
      result.addAll(driverBaseline);
    }
    // ضابط / Officer → قاعدة فقط (بدون إضافات)
    // مساعد / Assistant → قاعدة فقط (بدون إضافات)

    return result;
  }

  static bool _contains(String haystack, List<String> needles) {
    for (final n in needles) {
      if (haystack.contains(n.toLowerCase())) return true;
    }
    return false;
  }
}
