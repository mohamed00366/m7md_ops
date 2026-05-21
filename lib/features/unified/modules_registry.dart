import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/auth_provider.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';
// Admin modules
import '../admin/admin_overview.dart';
import '../admin/admin_users.dart';
import '../hr/document_vault_screen.dart';
import '../hr/hr_dashboard_screen.dart';
import '../hr/pin_management_screen.dart';
import '../operation/hr/hr_onpoint_training_screen.dart';
// Camp Boss modules
import '../camp_boss/bus_shift_km_screen.dart';
// 🚫 camp_boss_bus_planning أُزيلَ — التابَة "الخُطّة الأُسبوعيّة" داخِل CampBossBuses تُغني عَنه
import '../camp_boss/camp_boss_buses.dart';
import '../camp_boss/camp_boss_dashboard.dart';
import '../laundry/camp_boss/camp_boss_dashboard.dart' as amana;
import '../laundry/employee/employee_laundry_home.dart' as amanaEmp;
import '../camp_boss/camp_boss_rooms.dart';
import '../camp_boss/camp_boss_uniform.dart';
import '../camp_boss/camp_boss_violations.dart';
// Driver modules
import '../driver/driver_trips.dart';
// Employee modules
import '../employee/employee_deductions.dart';
import '../employee/employee_evaluations.dart';
import '../employee/employee_schedule.dart';
import '../employee/employee_my_roster.dart';
import '../employee/employee_daily_memo.dart';
import '../employee/daily_memo_report.dart';
import '../leave/my_leaves_screen.dart';
import '../employee/employee_uniform.dart';
// Manager modules
import '../manager/customers_hub.dart';
import '../manager/manager_buses.dart';
import '../manager/manager_dashboard.dart';
import '../manager/manager_employees.dart';
import '../manager/manager_reports.dart';
// 🚫 manager_tracking أُزيلَ — "التَتَبُّع المُباشِر" مَحذوف بِالكامِل
// Operation/Admin modules
import '../admin/analytics_dashboard_screen.dart';
import '../admin/audit_log_screen.dart';
import '../admin/company_calendar_screen.dart';
import '../admin/company_calendar_tabs_screen.dart';
import '../admin/data_quality_screen.dart';
import '../admin/employee_documents_expiry_report_screen.dart';
import '../admin/forms_submissions_report_screen.dart';
import '../admin/help_center_screen.dart';
import '../admin/leave_balance_manager_screen.dart';
import '../leave/leave_approvals_screen.dart';
import '../reports/reports_hub_screen.dart';
import '../admin/my_preferences_screen.dart';
import '../admin/smart_alerts_screen.dart';
import '../notifications/my_inbox_screen.dart';
import '../manager/attendance/point_attendance_report_screen.dart';
import '../operation/attendance_management_screen.dart';
import '../operation/driver_route_map_screen.dart';
import '../operation/live_fleet_map_screen.dart';
import '../operation/operation_rosters.dart';
import '../operation/operation_supervisor_assignments.dart';
import '../operation/temporary_pin_screen.dart';
import '../operation/rosters_center.dart';
// Policies
import '../policies/policies_screen.dart';
// Forms 🆕
import '../forms/admin_forms_screen.dart';
import '../forms/employee_forms_screen.dart';
// Site Onboarding 🏗
import '../site_onboarding/sites_onboarding_dashboard.dart';
import '../site_onboarding/site_onboarding_reports.dart';
// Settings Hub
import '../admin/settings_hub_screen.dart';
// Supervisor modules
import '../supervisor/supervisor_approved_roster.dart';
import '../camp_boss/evaluations_center.dart';
import '../supervisor/supervisor_roster_creator.dart';
import 'app_module.dart';
import 'smart_home.dart';

/// السجل الموحّد لكل أقسام التطبيق
///
/// 📐 **هَيكَل التَطبيق المُنَظَّم (May 2026):**
///
/// 1. 🏠 **HOME** — الرَئيسيّة + الإشعارات + التَفضيلات + المُساعَدة
/// 2. 👥 **HR** — المُوَظَّفون + التَدريب + التَقييم + التَجهيز
/// 3. 🚚 **OPERATIONS** — لَوحة العَمَل + العُملاء + الإسناد
/// 4. 📅 **ROSTER** — الإنشاء + الاعتِماد + المُعتَمَد + الشيكلست
/// 5. 🛞 **TRANSPORT** — الباصات + التَتَبُّع + الخَرائِط + الحُضور
/// 6. 🏕 **CAMP** — الكامِب + الغُرَف + المَغسَلة + الزِيّ
/// 7. 🚗 **DRIVER** — رَحَلات السائِق
/// 8. 👤 **EMPLOYEE** — شاشاتي
/// 9. 📋 **FORMS** — كُلّ workflow وَمُوافَقاتي وَالنَماذِج
/// 10. 📊 **REPORTS** — كُلّ التَقارير في مَكان واحِد
/// 11. ⚙️ **ADMIN** — مُختَصَر: نَظرة عامّة + المُستَخدِمون + Settings Hub
class ModulesRegistry {
  /// كل الموديولات بالترتيب الذي ستظهر فيه في الـ Drawer
  static List<AppModule> all() => [
        // ═══════════════════════════════════════════════════
        // 1️⃣ HOME — ما يَحتاجه المُستَخدِم يَوميّاً
        // ═══════════════════════════════════════════════════
        AppModule(
          key: 'smart_home',
          titleAr: 'الرئيسية',
          titleEn: 'Home',
          icon: Icons.home_outlined,
          color: ModuleCategory.home.color(),
          category: ModuleCategory.home,
          builder: (_) => const SmartHome(),
        ),
        AppModule(
          key: 'my_inbox',
          titleAr: 'صَندوق الإشعارات',
          titleEn: 'My Inbox',
          icon: Icons.inbox_outlined,
          color: ModuleCategory.home.color(),
          category: ModuleCategory.home,
          builder: (_) => const MyInboxScreen(),
        ),
        AppModule(
          key: 'my_preferences',
          titleAr: 'تَفضيلاتي',
          titleEn: 'My Preferences',
          icon: Icons.tune,
          color: ModuleCategory.home.color(),
          category: ModuleCategory.home,
          builder: (_) => const MyPreferencesScreen(),
        ),
        AppModule(
          key: 'help_center',
          titleAr: 'مَركَز المُساعَدة',
          titleEn: 'Help Center',
          icon: Icons.menu_book,
          color: ModuleCategory.home.color(),
          category: ModuleCategory.home,
          requiredPermission: P.adminHelpCenterView,
          builder: (_) => const HelpCenterScreen(),
        ),
        AppModule(
          key: 'policies',
          titleAr: 'السياسات',
          titleEn: 'Policies',
          icon: Icons.gavel_outlined,
          color: ModuleCategory.home.color(),
          category: ModuleCategory.home,
          requiredPermission: P.policiesView,
          builder: (_) => const PoliciesScreen(),
        ),

        // ═══════════════════════════════════════════════════
        // 2️⃣ HR — كُلّ ما يَخُصّ المُوَظَّفين
        // ═══════════════════════════════════════════════════
        // 🆕 لَوحة HR المُوَحَّدة — KPIs + Alerts + Quick Actions
        AppModule(
          key: 'hr_dashboard',
          titleAr: '🏢 لَوحة HR',
          titleEn: '🏢 HR Dashboard',
          icon: Icons.dashboard_outlined,
          color: ModuleCategory.hr.color(),
          category: ModuleCategory.hr,
          requiredPermission: P.employeesView,
          builder: (_) => const HrDashboardScreen(),
        ),
        // 🆕 خِزانة الوَثائق المُوَحَّدة — كُلّ وَثائق كُلّ المُوَظَّفين في شاشة واحِدة
        AppModule(
          key: 'document_vault',
          titleAr: '📁 خِزانة الوَثائق',
          titleEn: '📁 Document Vault',
          icon: Icons.folder_special_outlined,
          color: ModuleCategory.hr.color(),
          category: ModuleCategory.hr,
          requiredPermission: P.documentsVaultView,
          builder: (_) => const DocumentVaultScreen(),
        ),
        // 🆕 إدارة PINs — تَعيين/تَجديد رَقم سِرّيّ لِبَديل التَعَرُّف عَلى الوَجه
        AppModule(
          key: 'pin_management',
          titleAr: '🔐 إدارة PINs',
          titleEn: '🔐 PIN Management',
          icon: Icons.pin_outlined,
          color: ModuleCategory.hr.color(),
          category: ModuleCategory.hr,
          requiredPermission: P.employeesView,
          builder: (_) => const PinManagementScreen(),
        ),
        AppModule(
          key: 'employees',
          titleAr: 'المُوَظَّفون',
          titleEn: 'Employees',
          icon: Icons.people_outline,
          color: ModuleCategory.hr.color(),
          category: ModuleCategory.hr,
          requiredPermission: P.employeesView,
          requiresCountry: true,
          builder: (_) => const ManagerEmployees(),
        ),
        AppModule(
          key: 'onpoint_training',
          titleAr: 'تَدريب الجُدُد',
          titleEn: 'New Trainees',
          icon: Icons.school_outlined,
          color: ModuleCategory.hr.color(),
          category: ModuleCategory.hr,
          requiredPermission: P.employeesView,
          builder: (_) => const HrOnPointTrainingScreen(),
        ),
        AppModule(
          key: 'evaluations_center',
          titleAr: 'مَركَز التَقييمات',
          titleEn: 'Evaluations Center',
          icon: Icons.star_rate,
          color: ModuleCategory.hr.color(),
          category: ModuleCategory.hr,
          requiredPermission: P.evaluationsView,
          builder: (_) => const EvaluationsCenter(),
        ),
        // 🆕 إدارة أَرصِدة الإجازات (HR/Admin فَقَط)
        AppModule(
          key: 'leave_balances',
          titleAr: '🏖 إدارة أَرصِدة الإجازات',
          titleEn: '🏖 Leave Balances',
          icon: Icons.beach_access_outlined,
          color: ModuleCategory.hr.color(),
          category: ModuleCategory.hr,
          requiredPermission: P.leaveBalanceManage,
          builder: (_) => const LeaveBalanceManagerScreen(),
        ),
        // 🆕 اعتِماد طَلَبات الإجازات (Manager/HR) — يَعرِض pending وَيُوافِق/يَرفُض
        AppModule(
          key: 'leave_approvals',
          titleAr: '🛂 اعتِماد طَلَبات الإجازات',
          titleEn: '🛂 Leave Approvals',
          icon: Icons.fact_check_outlined,
          color: ModuleCategory.hr.color(),
          category: ModuleCategory.hr,
          requiredPermission: P.leaveTeamApprove,
          builder: (_) => const LeaveApprovalsScreen(),
        ),
        // 🆕 نُقِلَ مِن النَقل → HR (إدارة الحُضور وَالانصِراف)
        AppModule(
          key: 'attendance_mgmt',
          titleAr: '⏰ إدارة الحُضور وَالانصِراف',
          titleEn: '⏰ Attendance Management',
          icon: Icons.access_time_outlined,
          color: ModuleCategory.hr.color(),
          category: ModuleCategory.hr,
          requiredPermission: P.attendanceView,
          builder: (_) => const AttendanceManagementScreen(),
        ),
        // 🆕 مَركَز التَقارير المُوَحَّد (Hybrid: KPIs + Quick Insights + Library)
        AppModule(
          key: 'reports_hub',
          titleAr: '📊 التَقارير وَالتَحليلات',
          titleEn: '📊 Reports & Analytics',
          icon: Icons.bar_chart,
          color: ModuleCategory.organization.color(),
          category: ModuleCategory.organization,
          requiredPermission: P.dashboardManagerView,
          builder: (_) => const ReportsHubScreen(),
        ),

        // ═══════════════════════════════════════════════════
        // 3️⃣ ORGANIZATION — عُملاء + دُوَل
        // ═══════════════════════════════════════════════════
        AppModule(
          key: 'ops_dashboard',
          titleAr: 'لَوحة العَمَليّات',
          titleEn: 'Operations Dashboard',
          icon: Icons.dashboard_outlined,
          color: ModuleCategory.organization.color(),
          category: ModuleCategory.organization,
          requiredPermission: P.dashboardManagerView,
          builder: (_) => const ManagerDashboard(),
        ),
        AppModule(
          key: 'customers',
          titleAr: 'العُملاء',
          titleEn: 'Customers',
          icon: Icons.business_outlined,
          color: ModuleCategory.organization.color(),
          category: ModuleCategory.organization,
          requiredPermission: P.sitesView,
          requiresCountry: true,
          builder: (_) => const CustomersHub(),
        ),
        // 🚫 admin_countries أُزيلَ من الدرور — مُتاح في مَركَز الإعدادات
        // 🚫 assign_supervisors نُقِلَ إلى قِسم الروستر (أَكثَر مَنطِقيّة)

        // ═══════════════════════════════════════════════════
        // 4️⃣ ROSTER — الرَوسترات
        // ═══════════════════════════════════════════════════
        // 🆕 إسناد المُشرِفين — نُقِلَ هُنا من قِسم المُؤَسَّسة لِأَنّه
        // خُطوة سابِقة لِإنشاء الروستر (المُشرِف يُسنَد لِنُقطة قَبل بِناء الروستر)
        AppModule(
          key: 'assign_supervisors',
          titleAr: 'إسناد المُشرِفين',
          titleEn: 'Assign Supervisors',
          icon: Icons.person_pin_circle_outlined,
          color: ModuleCategory.roster.color(),
          category: ModuleCategory.roster,
          requiredPermission: P.employeesView,
          requiresCountry: true,
          builder: (_) => const OperationSupervisorAssignments(),
        ),
        // 🆕 PIN مُؤَقَّت — مُدير العَمَلِيّات يُوَلِّد PIN صالِح لِثَوانٍ مَعدودة
        AppModule(
          key: 'temporary_pin',
          titleAr: '🔐 PIN مُؤَقَّت',
          titleEn: '🔐 Temporary PIN',
          icon: Icons.lock_clock_outlined,
          color: ModuleCategory.hr.color(),
          category: ModuleCategory.hr,
          requiredPermission: 'pin.generate_temporary',
          builder: (_) => const TemporaryPinScreen(),
        ),
        AppModule(
          key: 'roster_creator',
          titleAr: 'إنشاء روستر',
          titleEn: 'Create Roster',
          icon: Icons.edit_calendar_outlined,
          color: ModuleCategory.roster.color(),
          category: ModuleCategory.roster,
          requiredPermission: P.rosterCreatorView,
          requiresCountry: true,
          builder: (_) => const SupervisorRosterCreator(),
        ),
        AppModule(
          key: 'rosters_center',
          titleAr: 'مَركَز الرَوسترات',
          titleEn: 'Rosters Center',
          icon: Icons.dashboard_customize_outlined,
          color: ModuleCategory.roster.color(),
          category: ModuleCategory.roster,
          requiredPermission: P.rostersCenterView,
          builder: (_) => const RostersCenter(),
        ),
        AppModule(
          key: 'roster_approvals',
          titleAr: 'اعتِماد الرَوسترات',
          titleEn: 'Roster Approvals',
          icon: Icons.fact_check_outlined,
          color: ModuleCategory.roster.color(),
          category: ModuleCategory.roster,
          requiredPermission: P.rosterApprovalsView,
          builder: (_) => const OperationRosters(),
        ),
        AppModule(
          key: 'approved_roster',
          titleAr: 'الروستر المُعتَمَد',
          titleEn: 'Approved Roster',
          icon: Icons.verified_outlined,
          color: ModuleCategory.roster.color(),
          category: ModuleCategory.roster,
          requiredPermission: P.approvedRosterView,
          builder: (_) => const SupervisorApprovedRoster(),
        ),
        // 🚫 morning_checklist أُزيلَ — أَصبَحَ نَموذَج MORNING-CHECKLIST
        //    يَملَؤه المُشرِف مِن "نَماذِجي"

        // 🚫 قِسم النَقل (Transport) أُزيلَ بِالكامِل — مَحتَواه وُزِّعَ كالتالي:
        //   • الباصات        → العَمَلِيّات (هذا الـ AppModule)
        //   • التَتَبُّع المُباشِر → مَحذوف
        //   • خَريطة الأُسطول   → الكَمب
        //   • خَرائِط المَسار   → الكَمب
        //   • الحُضور          → الموارِد البَشَريّة
        AppModule(
          key: 'buses',
          titleAr: '🚌 إدارة الباصات وَالسائِقين',
          titleEn: '🚌 Buses & Drivers',
          icon: Icons.directions_bus_outlined,
          color: ModuleCategory.organization.color(),
          category: ModuleCategory.organization,
          requiredPermission: P.busesView,
          requiresCountry: true,
          builder: (_) => const ManagerBuses(),
        ),

        // ═══════════════════════════════════════════════════
        // 6️⃣ CAMP — الكامِب (بِدون مُخالَفات — انتَقَلَت لِـForms)
        // ═══════════════════════════════════════════════════
        AppModule(
          key: 'camp_dashboard',
          titleAr: 'لَوحة الكامِب',
          titleEn: 'Camp Dashboard',
          icon: Icons.dashboard_outlined,
          color: ModuleCategory.camp.color(),
          category: ModuleCategory.camp,
          requiredPermission: P.dashboardCampView,
          builder: (_) => const CampBossDashboard(),
        ),
        AppModule(
          key: 'rooms',
          titleAr: 'الغُرَف',
          titleEn: 'Rooms',
          icon: Icons.bed_outlined,
          color: ModuleCategory.camp.color(),
          category: ModuleCategory.camp,
          requiredPermission: P.campRoomsView,
          builder: (_) => const CampBossRooms(),
        ),
        AppModule(
          key: 'laundry',
          titleAr: 'المَغسَلة (أَمانة)',
          titleEn: 'Laundry (Amana)',
          icon: Icons.local_laundry_service_outlined,
          color: ModuleCategory.camp.color(),
          category: ModuleCategory.camp,
          requiredPermission: P.campLaundryView,
          // 🆕 نِظام "أَمانة" الجَديد
          builder: (ctx) {
            final auth = ctx.read<AuthProvider>();
            final empId = auth.account?.employeeId ?? auth.account?.id ?? '';
            // البَلَد: مِن سِجِلّ الكَمب بُوص أَوّلاً، ثُمَّ activeCountryId
            final emp = MockRepository().employeeById(empId);
            return amana.CampBossLaundryDashboard(
              campBossId: empId,
              countryId: emp?.countryId ?? auth.activeCountryId,
            );
          },
        ),
        AppModule(
          key: 'uniform',
          titleAr: 'تَجهيز المُوَظَّفين',
          titleEn: 'Employee Setup',
          icon: Icons.checkroom_outlined,
          color: ModuleCategory.camp.color(),
          category: ModuleCategory.camp,
          requiredPermission: P.uniformCatalogView,
          builder: (_) => const CampBossUniform(),
        ),
        // 🆕 Camp Boss Buses Hub — 4 تابات: قائِمة باصات، سائقين، خُطّة أُسبوعيّة، تَقارير
        AppModule(
          key: 'camp_buses_hub',
          titleAr: '🚐 مَركَز الباصات (كَمب)',
          titleEn: '🚐 Buses Hub (Camp)',
          icon: Icons.directions_bus_filled_outlined,
          color: ModuleCategory.camp.color(),
          category: ModuleCategory.camp,
          requiredPermission: P.busesView,
          builder: (_) => const CampBossBuses(),
        ),
        // 🚫 تَخطيط الباصات (CampBossBusPlanning) — حُذِفَ بِطَلَب المُستَخدِم
        //   التابَة "📅 الخُطّة الأُسبوعيّة" داخِل "🚐 مَركَز الباصات" تُغني عَنها.
        AppModule(
          key: 'bus_shift_km',
          titleAr: '🛞 كيلومترات الوَردِيّات',
          titleEn: '🛞 Shift KM',
          icon: Icons.speed,
          color: ModuleCategory.camp.color(),
          category: ModuleCategory.camp,
          requiredPermission: P.busesAssign,
          builder: (_) => const BusShiftKmScreen(),
        ),
        // 🆕 نُقِلَ مِن النَقل → الكَمب (الكَمب بُوص يَحتاج رُؤية الباصات)
        AppModule(
          key: 'live_fleet_map',
          titleAr: '🗺 خَريطة الأُسطول',
          titleEn: '🗺 Fleet Map',
          icon: Icons.map,
          color: ModuleCategory.camp.color(),
          category: ModuleCategory.camp,
          requiredPermission: P.trackingLiveView,
          builder: (_) => const LiveFleetMapScreen(),
        ),
        AppModule(
          key: 'route_map',
          titleAr: 'خَرائِط المَسار',
          titleEn: 'Route Map',
          icon: Icons.alt_route,
          color: ModuleCategory.camp.color(),
          category: ModuleCategory.camp,
          requiredPermission: P.trackingLiveView,
          builder: (_) => const DriverRouteMapScreen(),
        ),

        // ═══════════════════════════════════════════════════
        // 7️⃣ DRIVER — السائِق
        // ═══════════════════════════════════════════════════
        AppModule(
          key: 'today_trips',
          titleAr: 'رحلات اليوم',
          titleEn: "Today's Trips",
          icon: Icons.today_outlined,
          color: ModuleCategory.driver.color(),
          category: ModuleCategory.driver,
          requiredPermission: P.driverTripsView,
          builder: (_) => const DriverTrips(weekly: false),
        ),
        AppModule(
          key: 'weekly_trips',
          titleAr: 'الرحلات الأُسبوعيّة',
          titleEn: 'Weekly Trips',
          icon: Icons.calendar_view_week_outlined,
          color: ModuleCategory.driver.color(),
          category: ModuleCategory.driver,
          requiredPermission: P.driverTripsView,
          builder: (_) => const DriverTrips(weekly: true),
        ),

        // ═══════════════════════════════════════════════════
        // 8️⃣ EMPLOYEE (My Screens) — شاشاتي
        // ═══════════════════════════════════════════════════
        AppModule(
          key: 'my_roster',
          titleAr: 'روستري',
          titleEn: 'My Roster',
          icon: Icons.calendar_month_outlined,
          color: ModuleCategory.employee.color(),
          category: ModuleCategory.employee,
          requiredPermission: P.myRosterView,
          builder: (_) => const EmployeeMyRoster(),
        ),
        AppModule(
          key: 'my_schedule',
          titleAr: 'جَدوَلي',
          titleEn: 'My Schedule',
          icon: Icons.schedule,
          color: ModuleCategory.employee.color(),
          category: ModuleCategory.employee,
          requiredPermission: P.employeeScheduleView,
          builder: (_) => const EmployeeSchedule(),
        ),
        AppModule(
          key: 'my_daily_memo',
          titleAr: 'مُذَكِّرَتي اليَوميّة',
          titleEn: 'My Daily Memo',
          icon: Icons.note_alt_outlined,
          color: ModuleCategory.employee.color(),
          category: ModuleCategory.employee,
          requiredPermission: P.dailyMemoCreate,
          builder: (_) => const EmployeeDailyMemoScreen(),
        ),
        AppModule(
          key: 'my_leaves',
          titleAr: 'إجازاتي',
          titleEn: 'My Leaves',
          icon: Icons.beach_access_outlined,
          color: ModuleCategory.employee.color(),
          category: ModuleCategory.employee,
          requiredPermission: P.leaveRequestSubmit,
          builder: (_) => const MyLeavesScreen(),
        ),
        AppModule(
          key: 'my_uniform',
          titleAr: 'ملابسي',
          titleEn: 'My Uniform',
          icon: Icons.checkroom,
          color: ModuleCategory.employee.color(),
          category: ModuleCategory.employee,
          requiredPermission: P.employeeUniformView,
          builder: (_) => const EmployeeUniformView(),
        ),
        AppModule(
          key: 'my_laundry',
          titleAr: 'مَغسَلَتي (أَمانة)',
          titleEn: 'My Laundry (Amana)',
          icon: Icons.local_laundry_service,
          color: ModuleCategory.employee.color(),
          category: ModuleCategory.employee,
          // مَفتوح لِكُلّ مُوَظَّف بِدون صَلاحِيّة إضافيّة
          builder: (ctx) {
            final auth = ctx.read<AuthProvider>();
            final empId = auth.account?.employeeId ?? auth.account?.id ?? '';
            // 🆕 خُذ البَلَد مِن سِجِلّ المُوَظَّف نَفسه أَوّلاً
            // (لِأَنّ activeCountryId قَد يَكون فارِغاً لِغَير الـadmins)
            final emp = MockRepository().employeeById(empId);
            final empCountry = emp?.countryId;
            return amanaEmp.EmployeeLaundryHome(
              employeeId: empId,
              countryId: empCountry ?? auth.activeCountryId,
            );
          },
        ),
        AppModule(
          key: 'my_deductions',
          titleAr: 'خُصوماتي',
          titleEn: 'My Deductions',
          icon: Icons.money_off_outlined,
          color: ModuleCategory.employee.color(),
          category: ModuleCategory.employee,
          requiredPermission: P.deductionsView,
          builder: (_) => const EmployeeDeductions(),
        ),
        AppModule(
          key: 'my_evaluations',
          titleAr: 'تَقييماتي',
          titleEn: 'My Evaluations',
          icon: Icons.star_outline,
          color: ModuleCategory.employee.color(),
          category: ModuleCategory.employee,
          requiredPermission: P.evaluationsView,
          builder: (_) => const EmployeeEvaluationsView(),
        ),
        AppModule(
          key: 'employee_forms',
          titleAr: 'نَماذِجي',
          titleEn: 'My Forms',
          icon: Icons.assignment_outlined,
          color: ModuleCategory.employee.color(),
          category: ModuleCategory.employee,
          requiredPermission: P.formsSubmit,
          builder: (_) => const EmployeeFormsScreen(),
        ),

        // ═══════════════════════════════════════════════════
        // 9️⃣ FORMS — ⭐ صَندوق النَماذِج المُوَحَّد
        //   - "صَندوق النَماذِج" يَحُلّ مَحَلّ: موافقاتي + اعتماد الإجازات
        //   - "إدارة النَماذِج" لِبِناء/تَعديل القوالِب (admin)
        // ═══════════════════════════════════════════════════
        AppModule(
          key: 'forms_inbox',
          titleAr: '📥 صَندوق النَماذِج',
          titleEn: '📥 Forms Inbox',
          icon: Icons.inbox_outlined,
          color: ModuleCategory.forms.color(),
          category: ModuleCategory.forms,
          // 🆕 خَفّفنا المُتَطَلَّب من formsAdminView إلى formsApprovalsView
          // لِيَراه كُلّ مُوافِق (مُشرِف/عَمَليّات/كامِب-بوس/HR/إلخ)
          requiredPermission: P.formsApprovalsView,
          builder: (_) => const FormsSubmissionsReportScreen(),
        ),
        AppModule(
          key: 'admin_forms',
          titleAr: 'إدارة النَماذِج',
          titleEn: 'Manage Forms',
          icon: Icons.assignment_turned_in_outlined,
          color: ModuleCategory.forms.color(),
          category: ModuleCategory.forms,
          requiredPermission: P.formsManage,
          builder: (_) => const AdminFormsScreen(),
        ),

        // ═══════════════════════════════════════════════════
        // 🔟 REPORTS — ⭐ كُلّ التَقارير في مَكان واحِد
        // ═══════════════════════════════════════════════════
        AppModule(
          key: 'reports',
          titleAr: 'مَركَز التَقارير',
          titleEn: 'Reports Center',
          icon: Icons.bar_chart,
          color: ModuleCategory.reports.color(),
          category: ModuleCategory.reports,
          requiredPermission: P.reportsView,
          builder: (_) => const ManagerReports(),
        ),
        // 🚫 forms_submissions_report نُقِلَ إلى FORMS كَـ forms_inbox

        // 🆕 المَواقِع الجَديدة (تَتَبُّع — kanban بَعد المُوافَقة)
        AppModule(
          key: 'sites_onboarding',
          titleAr: 'تَتَبُّع المَواقِع الجَديدة',
          titleEn: 'New Sites Tracker',
          icon: Icons.add_business_outlined,
          color: ModuleCategory.reports.color(),
          category: ModuleCategory.reports,
          requiredPermission: P.siteOnboardingView,
          builder: (_) => const SitesOnboardingDashboard(),
        ),
        // 🆕 سِجِلّ المُخالَفات (legacy — بَيانات تاريخيّة)
        AppModule(
          key: 'violations',
          titleAr: 'سِجِلّ المُخالَفات',
          titleEn: 'Violations Log',
          icon: Icons.warning_amber_outlined,
          color: ModuleCategory.reports.color(),
          category: ModuleCategory.reports,
          requiredPermission: P.campViolationsView,
          builder: (_) => const CampBossViolations(),
        ),
        AppModule(
          key: 'smart_alerts',
          titleAr: 'مَركَز التَنبيهات',
          titleEn: 'Smart Alerts',
          icon: Icons.notifications_active,
          color: ModuleCategory.reports.color(),
          category: ModuleCategory.reports,
          requiredPermission: P.reportsSmartAlertsView,
          builder: (_) => const SmartAlertsScreen(),
        ),
        AppModule(
          key: 'analytics_dashboard',
          titleAr: 'لَوحة التَحليلات',
          titleEn: 'Analytics Dashboard',
          icon: Icons.insights,
          color: ModuleCategory.reports.color(),
          category: ModuleCategory.reports,
          requiredPermission: P.reportsAnalyticsView,
          builder: (_) => const AnalyticsDashboardScreen(),
        ),
        AppModule(
          key: 'audit_trail',
          titleAr: 'سِجِلّ التَدقيق',
          titleEn: 'Audit Trail',
          icon: Icons.history,
          color: ModuleCategory.reports.color(),
          category: ModuleCategory.reports,
          requiredPermission: P.adminAuditView,
          builder: (_) => const AuditLogScreen(),
        ),
        AppModule(
          key: 'data_quality',
          titleAr: 'جَودة البَيانات',
          titleEn: 'Data Quality',
          icon: Icons.fact_check,
          color: ModuleCategory.reports.color(),
          category: ModuleCategory.reports,
          requiredPermission: P.reportsDataQualityView,
          builder: (_) => const DataQualityScreen(),
        ),
        AppModule(
          key: 'company_calendar',
          titleAr: 'تَقويم الشَركة',
          titleEn: 'Company Calendar',
          icon: Icons.calendar_month,
          color: ModuleCategory.reports.color(),
          category: ModuleCategory.reports,
          requiredPermission: P.reportsCompanyCalendarView,
          builder: (_) => const CompanyCalendarTabsScreen(),
        ),
        AppModule(
          key: 'daily_memo_report',
          titleAr: 'تَقرير المُذَكِّرات اليَوميّة',
          titleEn: 'Daily Memo Report',
          icon: Icons.assignment_outlined,
          color: ModuleCategory.reports.color(),
          category: ModuleCategory.reports,
          requiredPermission: P.dailyMemoReportView,
          builder: (_) => const DailyMemoReportScreen(),
        ),
        AppModule(
          key: 'site_onboarding_reports',
          titleAr: 'تَقارير المَواقِع الجَديدة',
          titleEn: 'New Sites Reports',
          icon: Icons.add_business,
          color: ModuleCategory.reports.color(),
          category: ModuleCategory.reports,
          requiredPermission: P.siteOnboardingReportView,
          builder: (_) => const SiteOnboardingReports(),
        ),
        AppModule(
          key: 'employee_documents_expiry',
          titleAr: 'تَقرير وَثائِق المُوَظَّفين',
          titleEn: 'Documents Expiry Report',
          icon: Icons.event_busy,
          color: ModuleCategory.reports.color(),
          category: ModuleCategory.reports,
          requiredPermission: P.employeeDocumentsExpiryReport,
          builder: (_) => const EmployeeDocumentsExpiryReportScreen(),
        ),
        AppModule(
          key: 'point_attendance_report',
          titleAr: 'تَقرير دَوام النِقاط',
          titleEn: 'Point Attendance',
          icon: Icons.assignment_turned_in,
          color: ModuleCategory.reports.color(),
          category: ModuleCategory.reports,
          requiredPermission: P.pointAttendanceReportView,
          builder: (_) => const PointAttendanceReportScreen(),
        ),
        // 🚫 legacy audit_log screen (مُكَرَّر مَع audit_trail — تَركناه لِلتَوافُق)

        // ═══════════════════════════════════════════════════
        // 1️⃣1️⃣ ADMIN — مُختَصَر جِدّاً (كُلّ شَيء آخَر في Settings Hub)
        // ═══════════════════════════════════════════════════
        AppModule(
          key: 'admin_overview',
          titleAr: 'لَوحة الإدارة',
          titleEn: 'Admin Dashboard',
          icon: Icons.shield_moon_outlined,
          color: ModuleCategory.admin.color(),
          category: ModuleCategory.admin,
          requiredPermission: P.adminUsersView,
          builder: (_) => const AdminOverview(),
        ),
        AppModule(
          key: 'admin_users',
          titleAr: 'المُستَخدِمون',
          titleEn: 'Users',
          icon: Icons.people_outline,
          color: ModuleCategory.admin.color(),
          category: ModuleCategory.admin,
          requiredPermission: P.adminUsersView,
          builder: (_) => const AdminUsers(),
        ),
        AppModule(
          key: 'settings_hub',
          titleAr: '⚙️ مَركَز الإعدادات',
          titleEn: '⚙️ Settings Hub',
          icon: Icons.settings_outlined,
          color: ModuleCategory.admin.color(),
          category: ModuleCategory.admin,
          requiredPermission: P.settingsLookupsView,
          builder: (_) => const SettingsHubScreen(),
        ),
      ];

  /// مفلترة بصلاحيات المستخدم الحالي
  static List<AppModule> visibleFor(
    Set<String> permissions, {
    bool isSuperAdmin = false,
  }) {
    return all().where((m) {
      if (m.requiredPermission == null) return true;
      if (isSuperAdmin) return true;
      return permissions.contains(m.requiredPermission);
    }).toList();
  }

  /// تجميع حسب الفئة (Map<Category, List<Module>>)
  static Map<ModuleCategory, List<AppModule>> grouped(
    List<AppModule> modules,
  ) {
    final result = <ModuleCategory, List<AppModule>>{};
    for (final m in modules) {
      result.putIfAbsent(m.category, () => []).add(m);
    }
    return result;
  }
}
