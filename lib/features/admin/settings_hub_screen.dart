import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';
import '../forms/admin_forms_screen.dart';
import '../manager/manager_settings.dart';
import 'admin_countries.dart';
import 'amana_settings_screen.dart';
import 'camp_uniform_settings_screen.dart';
import 'notification_templates_screen.dart';
import 'admin_device_sessions_screen.dart';
import 'admin_system_settings.dart';
import 'data_reset_screen.dart';
import 'device_session_settings_screen.dart';
import 'driver_tracking_settings_screen.dart';
import 'active_duty_settings_screen.dart';
import 'face_enrollment_policy_settings_screen.dart';
import 'point_terminal_settings_screen.dart';
import 'replacement_notification_settings_screen.dart';
import 'terminal_sessions_screen.dart';
import 'evaluation_criteria_screen.dart';
import 'log_viewer_screen.dart';
import 'face_embeddings_recompute_screen.dart';
import 'geo_fence_settings_screen.dart';
import 'impersonate_picker.dart';
import 'login_method_settings_screen.dart';
import 'session_settings_screen.dart';
// admin_roles removed from Settings Hub — managed via Job Title Permissions matrix
// import 'admin_roles.dart';
import 'admin_users.dart';
import 'approval_matrix_screen.dart';
import 'bulk_employee_ops_screen.dart';
import 'bulk_permissions_matrix_screen.dart';
import 'config_export_screen.dart';
import 'jobtitle_coverage_screen.dart';
import 'org_builder_screen.dart';
import 'organization_chart_screen.dart';
import 'bus_assignment_settings_screen.dart';
import 'fleet_tracking_settings_screen.dart';
import 'gps_devices_screen.dart';
import 'generic_module_settings_screen.dart';
import 'on_point_training_settings_screen.dart';
import 'point_assignment_settings_screen.dart';
import 'roster_deadline_settings_screen.dart';
import 'roster_employee_filter_settings_screen.dart';
import 'roster_settings_screen.dart';
import '../../core/services/app_module_settings.dart';
import 'system_health_screen.dart';
import 'workflow_builder_screen.dart';

/// ⚙️ مركز الإعدادات الموحّد (Unified Settings Hub)
///
/// تجمع كلّ شاشات الإعدادات المتفرّقة في النظام تحت قسم واحد منظَّم،
/// مع البحث والتصنيف.
///
/// الفئات:
///   🏛️ الهيكل التنظيمي  (الأقسام، المسمّيات، الهيكل، الإسناد)
///   🛡️ الصلاحيّات والأدوار  (Roles، Permissions Matrix، Approval Matrix)
///   📋 النماذج  (قوالب النماذج، محرّر سير الموافقات)
///   🌐 النظام  (الدول، المستخدمون، القوائم المرجعيّة، Backup)
///   👥 الموظفون  (عمليّات جماعيّة)
class SettingsHubScreen extends StatefulWidget {
  const SettingsHubScreen({super.key});

  @override
  State<SettingsHubScreen> createState() => _SettingsHubScreenState();
}

class _SettingsHubScreenState extends State<SettingsHubScreen> {
  String _query = '';
  String? _activeCategory;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final auth = context.watch<AuthProvider>();
    final allRaw = _entries(isAr);

    // 🆕 إخفاء الإعدادات بناءً على صلاحيّات المستخدم.
    // Super Admin يرى كلّ شيء؛ غيره يرى فقط الإعدادات التي
    // لا تشترط صلاحيّة، أو التي يملك صلاحيّتها.
    final all = auth.isSuperAdmin
        ? allRaw
        : allRaw.where((e) {
            final req = e.requiredPermission;
            if (req == null) return true;
            return auth.permissions.contains(req);
          }).toList();

    var filtered = all;
    if (_activeCategory != null) {
      filtered = filtered.where((e) => e.category == _activeCategory).toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      filtered = filtered
          .where((e) =>
              e.titleAr.toLowerCase().contains(q) ||
              e.titleEn.toLowerCase().contains(q) ||
              e.descAr.toLowerCase().contains(q) ||
              e.descEn.toLowerCase().contains(q))
          .toList();
    }

    final grouped = <String, List<_SettingEntry>>{};
    for (final e in filtered) {
      grouped.putIfAbsent(e.category, () => []).add(e);
    }

    final categories = all.map((e) => e.category).toSet().toList();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mutedColor = theme.textTheme.bodySmall?.color ??
        (isDark ? Colors.white70 : Colors.grey[700]!);
    final fadedColor = theme.textTheme.bodySmall?.color?.withOpacity(0.6) ??
        (isDark ? Colors.white54 : Colors.grey[600]!);

    return Scaffold(
      body: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            color: theme.cardColor,
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.settings_outlined,
                        color: AppColors.brand, size: 22),
                    const SizedBox(width: 6),
                    Text(
                      isAr ? 'مركز الإعدادات' : 'Settings Hub',
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w900),
                    ),
                    const Spacer(),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.brand.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isAr ? '${all.length} إعداد' : '${all.length} settings',
                        style: TextStyle(
                          color: AppColors.brand,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  decoration: InputDecoration(
                    hintText:
                        isAr ? '🔍 بحث في الإعدادات...' : '🔍 Search...',
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
                const SizedBox(height: 8),
                // فئات
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _categoryChip(
                        label: isAr ? 'الكل' : 'All',
                        selected: _activeCategory == null,
                        onTap: () => setState(() => _activeCategory = null),
                      ),
                      for (final cat in categories) ...[
                        const SizedBox(width: 4),
                        _categoryChip(
                          label: cat,
                          selected: _activeCategory == cat,
                          onTap: () => setState(() => _activeCategory = cat),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 🆕 Setup Status banner
          const _SetupStatusBanner(),
          // Body
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search_off,
                              size: 40, color: fadedColor),
                          const SizedBox(height: 8),
                          Text(
                            isAr ? 'لا توجد نتائج' : 'No results',
                            style: TextStyle(color: mutedColor),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 30),
                    children: [
                      for (final entry in grouped.entries) ...[
                        _categoryHeader(entry.key, entry.value.length),
                        for (final setting in entry.value)
                          _SettingCard(setting: setting, isAr: isAr),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _categoryChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final mutedColor = theme.textTheme.bodySmall?.color ??
        (theme.brightness == Brightness.dark
            ? Colors.white70
            : Colors.grey[800]!);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.brand
              : theme.dividerColor.withOpacity(0.4),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.brand : theme.dividerColor,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : mutedColor,
          ),
        ),
      ),
    );
  }

  Widget _categoryHeader(String category, int count) {
    final theme = Theme.of(context);
    final mutedColor = theme.textTheme.bodySmall?.color ??
        (theme.brightness == Brightness.dark
            ? Colors.white70
            : Colors.grey[700]!);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
      child: Row(
        children: [
          Text(
            category,
            style: TextStyle(
              fontSize: 12,
              color: mutedColor,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: theme.dividerColor.withOpacity(0.5),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                  fontSize: 10,
                  color: mutedColor,
                  fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 1,
              color: theme.dividerColor,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // الإعدادات
  // ============================================================
  List<_SettingEntry> _entries(bool isAr) {
    // 🆕 الفئات مرتّبة بحسب ModuleCategory الجديد:
    //   1. organization   2. hr   3. roster   4. transport
    //   5. camp           6. forms   7. admin/system   8. policies
    final catOrg       = isAr ? '🏢 المؤسّسة'              : '🏢 Organization';
    final catHr        = isAr ? '👥 الموارد البشريّة'       : '👥 HR';
    final catRoster    = isAr ? '📅 الروسترات'             : '📅 Rosters';
    final catTransport = isAr ? '🚌 النقل'                  : '🚌 Transport';
    final catCamp      = isAr ? '🏕️ الكمب'                  : '🏕️ Camp';
    final catForms     = isAr ? '📋 النماذج'                : '📋 Forms';
    final catAdmin     = isAr ? '⚙️ الإدارة والأمن'         : '⚙️ Admin & Security';
    final catPolicies  = isAr ? '📖 السياسات'               : '📖 Policies';

    // ⚠️ Legacy aliases — للتوافق مع entries لم تُحدَّث بعد.
    // ستُحذف بعد تحديث جميع المراجع.
    final catEmployees = catHr;        // legacy
    final catBuses     = catTransport; // legacy
    final catRoles     = catAdmin;     // legacy
    final catSystem    = catAdmin;     // legacy
    final catTraining  = catHr;        // legacy

    return [
      // 🏛️ الهيكل التنظيمي
      _SettingEntry(
        category: catOrg,
        icon: Icons.account_tree_outlined,
        color: AppColors.info,
        titleAr: 'الهيكل التنظيمي',
        titleEn: 'Organization Chart',
        descAr: 'شجرة الأقسام والمسمّيات + تصدير PDF',
        descEn: 'Department & title tree + PDF export',
        builder: (_) => const OrganizationChartScreen(),
        requiredPermission: P.orgChartView,
      ),
      _SettingEntry(
        category: catOrg,
        icon: Icons.drag_indicator,
        color: AppColors.purple,
        titleAr: 'محرّر الهيكل (سحب وإفلات)',
        titleEn: 'Org Builder (drag-drop)',
        descAr: 'إعادة بناء الهيكل بصريّاً',
        descEn: 'Restructure org by dragging',
        builder: (_) => const OrgBuilderScreen(),
        requiredPermission: P.orgBuilderManage,
      ),
      _SettingEntry(
        category: catOrg,
        icon: Icons.pin_drop_outlined,
        color: AppColors.brand,
        titleAr: 'إعدادات إسناد النقاط',
        titleEn: 'Point Assignment Settings',
        descAr: 'تخصيص أيّ مسمّيات تظهر في شاشة الإسناد',
        descEn: 'Which titles appear in assign screen',
        builder: (_) => const PointAssignmentSettingsScreen(),
        requiredPermission: P.orgPointAssignmentView,
      ),
      _SettingEntry(
        category: catOrg,
        icon: Icons.list_alt_outlined,
        color: AppColors.teal,
        titleAr: 'القوائم المرجعيّة',
        titleEn: 'Lookups',
        descAr: 'الأقسام، المسمّيات، الجنسيّات، التأشيرات...',
        descEn: 'Departments, titles, nationalities, visas...',
        builder: (_) => const ManagerSettings(),
        requiredPermission: P.settingsLookupsView,
      ),
      // 🆕 تغطية المسمّيات
      _SettingEntry(
        category: catOrg,
        icon: Icons.bar_chart,
        color: AppColors.success,
        titleAr: 'تغطية المسمّيات',
        titleEn: 'Job Title Coverage',
        descAr: 'كم موظف على كلّ مسمّى — يكشف الفجوات',
        descEn: 'Employees per title — reveal gaps',
        builder: (_) => const JobTitleCoverageScreen(),
        requiredPermission: P.orgCoverageView,
      ),

      // 📅 إعدادات الروسترات
      _SettingEntry(
        category: catRoster,
        icon: Icons.calendar_month_outlined,
        color: AppColors.warning,
        titleAr: 'إعدادات الروسترات',
        titleEn: 'Roster Settings',
        descAr: 'قفل الأيام، الأنماط، فتح المعتمد، حدود التنبيه',
        descEn: 'Day lock, patterns, reopen, alert thresholds',
        builder: (_) => const RosterSettingsScreen(),
        requiredPermission: P.settingsRosterView,
      ),
      // 🆕 صَفحة تَصفير البَيانات الموحَّدة (تَجمَع حَذف الروسترات + باقي الأَقسام)
      _SettingEntry(
        category: catAdmin,
        icon: Icons.delete_forever_outlined,
        color: AppColors.danger,
        titleAr: '🗑 تَصفير البَيانات',
        titleEn: '🗑 Data Reset',
        descAr:
            'تَصفير كُلّ البَيانات (روسترات، مَواقِع، نَماذِج، إجازات، زِيّ، أَمانة، حُضور، إشعارات، Tokens) + إعادة التَرقيم. Super Admin فَقَط.',
        descEn:
            'Wipe rosters / sites / forms / leaves / uniform / amana / attendance / notifications / tokens, and reset numbering. Super Admin only.',
        builder: (_) => const DataResetScreen(),
        requiredPermission: P.settingsClearRostersManage,
      ),
      // 🆕 تصفية موظّفي الروستر — أيّ مسمّيات تظهر عند إضافة موظّف
      _SettingEntry(
        category: catRoster,
        icon: Icons.filter_alt_outlined,
        color: AppColors.brand,
        titleAr: 'تصفية موظّفي الروستر',
        titleEn: 'Roster Employee Filter',
        descAr:
            'حدّد المسمّيات الوظيفيّة الظاهرة عند "إضافة موظّف للروستر" + إظهار النشطين فقط',
        descEn:
            'Pick which job titles appear in "Add to roster" + show only active employees',
        builder: (_) => const RosterEmployeeFilterSettingsScreen(),
        requiredPermission: P.settingsRosterEmployeeFilterView,
      ),
      // 🆕 مواعيد الروستر — آخر يوم للإنشاء + المراجعة + بدء العمل
      _SettingEntry(
        category: catRoster,
        icon: Icons.event_available_outlined,
        color: AppColors.warning,
        titleAr: 'مواعيد الروستر',
        titleEn: 'Roster Deadlines',
        descAr:
            'الـ deadline (السبت) + يوم المراجعة (الأحد) + بدء العمل (الإثنين) + تنبيهات',
        descEn:
            'Deadline (Sat) + review day (Sun) + work start (Mon) + alerts',
        builder: (_) => const RosterDeadlineSettingsScreen(),
        requiredPermission: P.settingsRosterDeadlineView,
      ),
      // 🆕 LogViewer — أداة مطوّرين
      _SettingEntry(
        category: catSystem,
        icon: Icons.terminal_outlined,
        color: AppColors.info,
        titleAr: 'سجلّ التطبيق (Logs)',
        titleEn: 'Application Logs',
        descAr: 'عرض السجلّ المباشر للتطبيق — مفيد لتشخيص المشاكل',
        descEn: 'Live application logs — useful for diagnostics',
        builder: (_) => const LogViewerScreen(),
        requiredPermission: P.settingsLogViewerView,
      ),

      // 📜 إعدادات التدريب — أُزيلت (لم يعد فيه Training Hub منفصل)

      // 🎓 إعدادات تدريب الجدد (OnPoint Training)
      _SettingEntry(
        category: catTraining,
        icon: Icons.school_outlined,
        color: AppColors.info,
        titleAr: 'إعدادات تدريب الجدد',
        titleEn: 'OnPoint Training Settings',
        descAr: 'مدّة، معتمِدون، توقيعات إلزاميّة، حدّ المستوى',
        descEn: 'Duration, approvers, required signatures, level threshold',
        builder: (_) => const OnPointTrainingSettingsScreen(),
        requiredPermission: P.trainingOnPointManage,
      ),

      // ============================================================
      // 🚌 الباصات
      // ============================================================
      _SettingEntry(
        category: catBuses,
        icon: Icons.gps_fixed,
        color: AppColors.brand,
        titleAr: '🛰 تَتَبُّع الأُسطول',
        titleEn: '🛰 Fleet Tracking',
        descAr:
            'إعدادات شامِلة: طُرُق التَتَبُّع، فَرض GPS، تَنبيهات الانقِطاع',
        descEn: 'Fleet-wide: tracking methods, GPS enforcement, alerts',
        builder: (_) => const FleetTrackingSettingsScreen(),
        requiredPermission: P.settingsBusView,
      ),
      _SettingEntry(
        category: catBuses,
        icon: Icons.devices_other,
        color: AppColors.purple,
        titleAr: '📡 أَجهِزة GPS لِلباصات',
        titleEn: '📡 Bus GPS Devices',
        descAr: 'اربِط/أَزِل جِهاز GPS أَو هاتِف أَو تابلت لِكُلّ باص',
        descEn: 'Pair GPS device, phone, or tablet per bus',
        builder: (_) => const GpsDevicesScreen(),
        requiredPermission: P.settingsBusView,
      ),
      _SettingEntry(
        category: catBuses,
        icon: Icons.directions_bus_outlined,
        color: AppColors.success,
        titleAr: 'إسناد الباصات',
        titleEn: 'Bus Assignment',
        descAr: 'مَن يحقّ له قيادة الباص ومَن يحقّ له ركوبه',
        descEn: 'Who can drive vs who can ride',
        builder: (_) => const BusAssignmentSettingsScreen(),
        requiredPermission: P.settingsBusView,
      ),
      _SettingEntry(
        category: catBuses,
        icon: Icons.tune,
        color: AppColors.success,
        titleAr: 'قواعد الباصات',
        titleEn: 'Bus Rules',
        descAr: 'السعة، الذُّرى الزمنيّة، حدود الرحلات، تنبيهات GPS',
        descEn: 'Capacity, peak hours, trip limits, GPS alerts',
        builder: (_) => GenericModuleSettingsScreen(
          titleAr: 'قواعد الباصات',
          titleEn: 'Bus Rules',
          settings: AppModuleSettings.buses,
        ),
        requiredPermission: P.settingsBusView,
      ),

      // ============================================================
      // 🏕️ الكمب
      // ============================================================
      _SettingEntry(
        category: catCamp,
        icon: Icons.holiday_village_outlined,
        color: AppColors.purple,
        titleAr: 'قواعد الكمب',
        titleEn: 'Camp Rules',
        descAr: 'يونيفورم، غسيل، غرف، تفتيش',
        descEn: 'Uniform, laundry, rooms, inspection',
        builder: (_) => GenericModuleSettingsScreen(
          titleAr: 'قواعد الكمب',
          titleEn: 'Camp Rules',
          settings: AppModuleSettings.camp,
        ),
        requiredPermission: P.settingsCampView,
      ),
      // 🆕 إعدادات تَجهيز المُوَظَّفين (الكاتالوج + الصَرف + الفَواتير + التَوقيع)
      _SettingEntry(
        category: catCamp,
        icon: Icons.checkroom,
        color: AppColors.gold,
        titleAr: '👕 تَجهيز المُوَظَّفين',
        titleEn: '👕 Employee Setup',
        descAr:
            'حَدّ المَخزون الأَدنى + مُدّة الزِيّ + التَوقيع الإلزامِيّ + بادِئات الأَرقام + مَنع المُتَدَرِّبين',
        descEn:
            'Min stock + uniform life + required signature + number prefixes + block trainees',
        builder: (_) => const CampUniformSettingsScreen(),
        requiredPermission: P.campSettingsView,
      ),
      // 🧺 إعدادات نِظام أَمانة (المَغسلة الجَديد)
      _SettingEntry(
        category: catCamp,
        icon: Icons.local_laundry_service,
        color: Colors.teal,
        titleAr: '🧺 نِظام أَمانة (المَغسلة)',
        titleEn: '🧺 Amana (Laundry)',
        descAr:
            'أَنواع المَلابِس + تَفعيل/إيقاف + إعداد "م.د" لِلمَلابِس الحَسّاسة',
        descEn:
            'Clothing types + activation + "م.د" mask for sensitive items',
        builder: (_) => const AmanaSettingsScreen(),
        requiredPermission: P.campSettingsView,
      ),
      // 🔔 قَوالِب الإشعارات — نُصوص قابِلة لِلتَخصيص
      _SettingEntry(
        category: catAdmin,
        icon: Icons.notifications_active_outlined,
        color: Colors.indigo,
        titleAr: '🔔 قَوالِب الإشعارات',
        titleEn: '🔔 Notification Templates',
        descAr:
            'تَعديل نُصوص العَناوين وَالنُصوص لِكُلّ إشعار + تَفعيل Push/داخِليّ',
        descEn:
            'Customize titles & bodies for every notification + toggle Push/in-app',
        builder: (_) => const NotificationTemplatesScreen(),
        requiredPermission: P.adminRolesManage,
      ),

      // ============================================================
      // 💸 الخصومات (تحت Employees / HR)
      // ============================================================
      _SettingEntry(
        category: catEmployees,
        icon: Icons.money_off_outlined,
        color: AppColors.danger,
        titleAr: 'قواعد الخصومات',
        titleEn: 'Deduction Rules',
        descAr: 'خصم تلقائي للتأخير والغياب، حدود شهريّة',
        descEn: 'Auto-deduct for lateness/absence, monthly caps',
        builder: (_) => GenericModuleSettingsScreen(
          titleAr: 'قواعد الخصومات',
          titleEn: 'Deduction Rules',
          settings: AppModuleSettings.deductions,
        ),
        requiredPermission: P.settingsDeductionView,
      ),

      // ============================================================
      // ⭐ التقييمات (تحت Employees / HR)
      // ============================================================
      _SettingEntry(
        category: catEmployees,
        icon: Icons.star_outline,
        color: AppColors.warning,
        titleAr: 'إعدادات التقييم',
        titleEn: 'Evaluation Settings',
        descAr: 'الأوزان، حدّ النجاح، التكرار الإلزامي',
        descEn: 'Weights, passing score, mandatory frequency',
        builder: (_) => GenericModuleSettingsScreen(
          titleAr: 'إعدادات التقييم',
          titleEn: 'Evaluation Settings',
          settings: AppModuleSettings.evaluations,
        ),
        requiredPermission: P.settingsEvaluationView,
      ),
      // 🆕 معايير التقييم (تعليمات + معايير لكل نوع تقييم)
      _SettingEntry(
        category: catEmployees,
        icon: Icons.checklist_rtl,
        color: AppColors.purple,
        titleAr: 'معايير التقييم (التعليمات)',
        titleEn: 'Evaluation Criteria',
        descAr:
            'إضافة/تعديل/حذف معايير تقييم الموظّفين والسائقين والغرف',
        descEn: 'Add/edit/delete criteria for employees, drivers, and rooms',
        builder: (_) => const EvaluationCriteriaScreen(),
        requiredPermission: P.evaluationCriteriaView,
      ),

      // ============================================================
      // 📍 التتبع (تحت Buses)
      // ============================================================
      _SettingEntry(
        category: catBuses,
        icon: Icons.gps_fixed,
        color: AppColors.info,
        titleAr: 'إعدادات التتبّع',
        titleEn: 'Tracking Settings',
        descAr: 'Geofence، الخمول، السرعة، انقطاع GPS',
        descEn: 'Geofence, idle, speed, GPS dropouts',
        builder: (_) => GenericModuleSettingsScreen(
          titleAr: 'إعدادات التتبّع',
          titleEn: 'Tracking Settings',
          settings: AppModuleSettings.tracking,
        ),
        requiredPermission: P.settingsTrackingView,
      ),

      // ============================================================
      // 👨‍💼 HR
      // ============================================================
      _SettingEntry(
        category: catHr,
        icon: Icons.person_search_outlined,
        color: AppColors.purple,
        titleAr: 'إعدادات HR',
        titleEn: 'HR Settings',
        descAr: 'فترة الاختبار، الإجازات، تنبيهات الوثائق',
        descEn: 'Probation, leaves, doc expiry alerts',
        builder: (_) => GenericModuleSettingsScreen(
          titleAr: 'إعدادات HR',
          titleEn: 'HR Settings',
          settings: AppModuleSettings.hr,
        ),
        requiredPermission: P.settingsHrView,
      ),

      // ============================================================
      // 🏢 العملاء (تحت Sales / Operations)
      // ============================================================
      _SettingEntry(
        category: catOrg,
        icon: Icons.business_outlined,
        color: AppColors.teal,
        titleAr: 'إعدادات العملاء',
        titleEn: 'Customer Settings',
        descAr: 'تجديد العقود، تنبيهات الفواتير، شروط الدفع',
        descEn: 'Contract renewal, invoice alerts, payment terms',
        builder: (_) => GenericModuleSettingsScreen(
          titleAr: 'إعدادات العملاء',
          titleEn: 'Customer Settings',
          settings: AppModuleSettings.customers,
        ),
        requiredPermission: P.settingsCustomerView,
      ),

      // 🛡️ الصلاحيّات (مصدر وحيد — مصفوفة المسمّيات الوظيفيّة)
      _SettingEntry(
        category: catRoles,
        icon: Icons.security_outlined,
        color: AppColors.brand,
        titleAr: 'صلاحيّات المسمّيات الوظيفيّة',
        titleEn: 'Job Title Permissions',
        descAr: 'مصفوفة موحّدة: كل المسمّيات × كل الصلاحيّات',
        descEn: 'Unified matrix: all job titles × all permissions',
        builder: (_) => const BulkPermissionsMatrixScreen(),
        requiredPermission: P.adminJobTitlePermissionsView,
      ),
      _SettingEntry(
        category: catRoles,
        icon: Icons.grid_view_outlined,
        color: AppColors.warning,
        titleAr: 'مصفوفة الموافقات',
        titleEn: 'Approval Matrix',
        descAr: 'تغطية الـ workflows + كشف الفجوات',
        descEn: 'Workflow coverage + gap detection',
        builder: (_) => const ApprovalMatrixScreen(),
        requiredPermission: P.workflowsApprovalMatrixView,
      ),

      // 📋 النماذج
      _SettingEntry(
        category: catForms,
        icon: Icons.assignment_outlined,
        color: AppColors.purple,
        titleAr: 'إدارة النماذج',
        titleEn: 'Forms Management',
        descAr: 'قوالب النماذج، الطلبات، الموافقات',
        descEn: 'Templates, submissions, approvals',
        builder: (_) => const AdminFormsScreen(),
        requiredPermission: P.formsAdminView,
      ),
      _SettingEntry(
        category: catForms,
        icon: Icons.auto_graph,
        color: AppColors.warning,
        titleAr: 'محرّر سير الموافقات',
        titleEn: 'Workflow Builder',
        descAr: 'بناء وتحرير سلاسل الموافقة',
        descEn: 'Build & edit approval chains',
        builder: (_) => const WorkflowBuilderScreen(),
        requiredPermission: P.workflowsBuilderView,
      ),

      // 🌐 النظام
      _SettingEntry(
        category: catSystem,
        icon: Icons.people_outline,
        color: AppColors.info,
        titleAr: 'المستخدمون',
        titleEn: 'Users',
        descAr: 'إدارة حسابات الدخول وكلمات السرّ',
        descEn: 'Manage login accounts and passwords',
        builder: (_) => const AdminUsers(),
        requiredPermission: P.adminUsersView,
      ),
      _SettingEntry(
        category: catSystem,
        icon: Icons.public,
        color: AppColors.teal,
        titleAr: 'الدول',
        titleEn: 'Countries',
        descAr: 'الدول المتاحة في النظام',
        descEn: 'Countries available in the system',
        builder: (_) => const AdminCountries(),
        requiredPermission: P.adminCountriesManage,
      ),
      _SettingEntry(
        category: catSystem,
        icon: Icons.cloud_sync_outlined,
        color: AppColors.success,
        titleAr: 'تصدير/استيراد JSON',
        titleEn: 'Config Export/Import',
        descAr: 'نسخة احتياطيّة كاملة + استعادة',
        descEn: 'Full backup + restore',
        builder: (_) => const ConfigExportScreen(),
        requiredPermission: P.settingsConfigExportView,
      ),
      // 🆕 إعدادات النِظام العامّة (إيميل المُصادَقة، اسم الشَركة…)
      _SettingEntry(
        category: catSystem,
        icon: Icons.settings_applications_outlined,
        color: AppColors.brand,
        titleAr: 'إعدادات النِظام العامّة',
        titleEn: 'System Settings',
        descAr: 'مُتَغَيِّرات قابِلة لِلتَعديل (إيميل المُصادَقة، اسم الشَركة، إلخ)',
        descEn: 'Editable system variables (auth email, company name, etc.)',
        builder: (_) => const AdminSystemSettings(),
        requiredPermission: P.settingsSystemView,
      ),
      // 🆕 صِحّة النِظام (مَركَز التَشخيص)
      _SettingEntry(
        category: catSystem,
        icon: Icons.health_and_safety_outlined,
        color: AppColors.success,
        titleAr: 'صِحّة النِظام',
        titleEn: 'System Health',
        descAr: 'فُحوصات صِحّة الإعداد + الاكتِشاف الذاتيّ لِلمَشاكِل',
        descEn: 'Setup health checks + self-diagnostics',
        builder: (_) => const SystemHealthScreen(),
        requiredPermission: P.adminSystemHealthView,
      ),
      // 🆕 مُحاكاة الحِسابات (Impersonate) — لِاختِبار ما يَراه كُلّ مُسَمَّى
      _SettingEntry(
        category: catSystem,
        icon: Icons.theater_comedy_outlined,
        color: AppColors.purple,
        titleAr: '🎭 مُحاكاة الحِسابات',
        titleEn: '🎭 Account Impersonation',
        descAr:
            'اعرِض التَطبيق كَأَيّ حِساب آخَر لِاختِبار ما يَراه كُلّ مُسَمَّى وَظيفيّ — Super Admin فَقَط',
        descEn:
            'View the app as any account to test what each job title sees — Super Admin only',
        builder: (_) => const ImpersonatePicker(),
        // لا نَضَع requiredPermission — الشاشة نَفسها تَفرِض isSuperAdmin
      ),
      _SettingEntry(
        category: catSystem,
        icon: Icons.devices_other,
        color: AppColors.brand,
        titleAr: 'جلسات الأجهزة',
        titleEn: 'Device Sessions',
        descAr: 'جهاز واحد لكل موظف — حذف لإتاحة الدخول من جهاز آخر',
        descEn: 'One device per employee — delete to allow new login',
        builder: (_) => const AdminDeviceSessionsScreen(),
        requiredPermission: P.adminDeviceSessionsView,
      ),
      _SettingEntry(
        category: catSystem,
        icon: Icons.policy_outlined,
        color: AppColors.warning,
        titleAr: 'سياسة الأجهزة ورسالة الرفض',
        titleEn: 'Device Policy & Block Message',
        descAr: 'تفعيل سياسة جهاز واحد + تعديل نصّ الرسالة',
        descEn: 'Toggle strict policy + customize block message',
        builder: (_) => const DeviceSessionSettingsScreen(),
        requiredPermission: P.settingsDeviceSessionView,
      ),
      _SettingEntry(
        category: catSystem,
        icon: Icons.public,
        color: AppColors.brand,
        titleAr: 'سياسة الموقع الجغرافي',
        titleEn: 'Geo-fence Policy',
        descAr: 'تقييد الدخول بمناطق محدّدة (دبي، الرياض…) + خريطة',
        descEn: 'Restrict login to defined zones with interactive map',
        builder: (_) => const GeoFenceSettingsScreen(),
        requiredPermission: P.settingsGeoFenceView,
      ),
      _SettingEntry(
        category: catSystem,
        icon: Icons.face,
        color: AppColors.success,
        titleAr: 'طريقة الدخول (كلمة مرور / بصمة وجه)',
        titleEn: 'Login Method (Password / Face ID)',
        descAr: 'تخصيص طريقة الدخول لكل حساب أو بحسب المسمّى الوظيفي',
        descEn: 'Configure login method per account or job title',
        builder: (_) => const LoginMethodSettingsScreen(),
        requiredPermission: P.settingsLoginMethodView,
      ),
      _SettingEntry(
        category: catSystem,
        icon: Icons.refresh,
        color: AppColors.brand,
        titleAr: 'إعادة حساب بصمات الوجه (FaceNet)',
        titleEn: 'Recompute face embeddings (FaceNet)',
        descAr: 'يُمرّر كلّ صور الوجوه على نموذج FaceNet لتحديث البصمات',
        descEn: 'Reprocess all face photos through FaceNet model',
        builder: (_) => const FaceEmbeddingsRecomputeScreen(),
        requiredPermission: P.settingsFaceEmbeddingsView,
      ),
      // 🆕 سياسة "التَطبيق على رَأس العَمَل فَقَط"
      _SettingEntry(
        category: catSystem,
        icon: Icons.work_off,
        color: AppColors.warning,
        titleAr: '🚧 التَطبيق على رَأس العَمَل فَقَط',
        titleEn: '🚧 Active-Duty-Only Policy',
        descAr:
            'مَنع الدُخول أَثناء الإجازة المُعتَمَدة أَو التَعليق — قابِل لِلتَهيئة بِالمُسَمَّى الوَظيفيّ',
        descEn:
            'Block login during approved leave or suspension — per-job-title',
        builder: (_) => const ActiveDutySettingsScreen(),
        requiredPermission: P.settingsLoginMethodView,
      ),
      // 🆕 إشعارات التَبديل في الرَحَلات
      _SettingEntry(
        category: catSystem,
        icon: Icons.swap_horiz,
        color: AppColors.gold,
        titleAr: '🔔 إشعارات التَبديل (الرَحَلات)',
        titleEn: '🔔 Replacement Notifications (Trips)',
        descAr:
            'مَن يَستَلِم إشعار/بَريد عِندَ تَبديل مُوظَّف غائِب بِبَديل في رِحلة باص',
        descEn:
            'Who gets notified (in-app/email) when a bus trip rider is replaced',
        builder: (_) => const ReplacementNotificationSettingsScreen(),
        requiredPermission: P.settingsBusView,
      ),
      // 🆕 سياسة تَسجيل بَصمة الوَجه الإجباريّ
      _SettingEntry(
        category: catSystem,
        icon: Icons.face_retouching_natural,
        color: AppColors.success,
        titleAr: '🔐 سياسة تَسجيل بَصمة الوَجه',
        titleEn: '🔐 Face Enrollment Policy',
        descAr:
            'إجبار الموظَّفين الجُدُد على تَسجيل بَصمة وَجه بَعدَ تَغيير كلِمة المُرور — لِكُلّ المُسَمَّيات أَو قائِمة مُحَدَّدة',
        descEn:
            'Force new employees to enroll a face biometric after password change — all titles or selected list',
        builder: (_) => const FaceEnrollmentPolicySettingsScreen(),
        requiredPermission: P.settingsFaceEmbeddingsView,
      ),
      // 🆕 إعدادات Point Terminal (نُقطة الدَوام)
      _SettingEntry(
        category: catSystem,
        icon: Icons.storefront,
        color: AppColors.gold,
        titleAr: '🏪 إعدادات نُقطة الدَوام',
        titleEn: '🏪 Point Terminal Settings',
        descAr:
            'Geo-fence + مُهلة الخُمول + حَدّ التَأَخُّر + نِطاق مُطابَقة الوَجه + صورة التَدقيق',
        descEn:
            'Geo-fence + idle timeout + late threshold + face match scope + audit photo',
        builder: (_) => const PointTerminalSettingsScreen(),
        requiredPermission: P.settingsPointTerminalView,
      ),
      // 🆕 أَجهِزة نِقاط الدَوام (مَربوطة بِالنُقطة)
      _SettingEntry(
        category: catSystem,
        icon: Icons.computer,
        color: AppColors.info,
        titleAr: '🖥 أَجهِزة نِقاط الدَوام',
        titleEn: '🖥 Terminal Devices',
        descAr:
            'الأَجهِزة المَربوطة بِكُلّ نُقطة + الجَلسات النَشطة — إنهاء/فَكّ رَبط',
        descEn:
            'Devices linked per point + active sessions — revoke/unlink',
        builder: (_) => const TerminalSessionsScreen(),
        requiredPermission: P.pointTerminalView,
      ),
      _SettingEntry(
        category: catSystem,
        icon: Icons.gps_fixed,
        color: AppColors.success,
        titleAr: 'تتبّع السائقين',
        titleEn: 'Driver Tracking',
        descAr: 'سياسة إرسال الموقع التلقائي + سجلّ المسارات',
        descEn: 'Auto location tracking policy + route history',
        builder: (_) => const DriverTrackingSettingsScreen(),
        requiredPermission: P.settingsDriverTrackingView,
      ),
      _SettingEntry(
        category: catSystem,
        icon: Icons.bookmark_outline,
        color: AppColors.brand,
        titleAr: 'سياسة الجلسات (تذكّرني)',
        titleEn: 'Session Policy (Remember me)',
        descAr: 'مدّة بقاء التطبيق مفتوحاً + من يستطيع استخدامها',
        descEn: 'Session duration + who can use Remember me',
        builder: (_) => const SessionSettingsScreen(),
        requiredPermission: P.settingsSessionView,
      ),

      // 👥 الموظفون
      _SettingEntry(
        category: catEmployees,
        icon: Icons.dynamic_form_outlined,
        color: AppColors.brand,
        titleAr: 'عمليّات جماعيّة',
        titleEn: 'Bulk Operations',
        descAr: 'نقل/تغيير قسم/مسمّى/حالة لعدّة موظفين',
        descEn: 'Bulk: change dept/title/status for many',
        builder: (_) => const BulkEmployeeOpsScreen(),
        requiredPermission: P.settingsBulkOpsView,
      ),
    ];
  }
}

class _SettingEntry {
  final String category;
  final IconData icon;
  final Color color;
  final String titleAr;
  final String titleEn;
  final String descAr;
  final String descEn;
  final Widget Function(BuildContext) builder;

  /// 🆕 إن وُجِد، يُخفى الإعداد تلقائيّاً ممّن لا يملك هذه الصلاحية
  /// (Super Admin يرى كلّ شيء بصرف النظر عن هذا الحقل).
  final String? requiredPermission;

  _SettingEntry({
    required this.category,
    required this.icon,
    required this.color,
    required this.titleAr,
    required this.titleEn,
    required this.descAr,
    required this.descEn,
    required this.builder,
    this.requiredPermission,
  });
}

// ============================================================
// 🆕 شريط حالة الإعداد (Setup Status Banner)
// ============================================================
class _SetupStatusBanner extends StatefulWidget {
  const _SetupStatusBanner();

  @override
  State<_SetupStatusBanner> createState() => _SetupStatusBannerState();
}

class _SetupStatusBannerState extends State<_SetupStatusBanner> {
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

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final repo = MockRepository();

    final deptCount = repo.departments.length;
    final jobTitleCount = repo.jobTitles.length;
    final roleCount = repo.roleDefs.length;
    final empCount = repo.employees.length;

    // الأهداف الرسميّة
    const targetDepts = 7;
    const targetTitles = 21;

    // حالة كلّ مؤشّر
    final deptStatus = deptCount == targetDepts
        ? _Status.ok
        : (deptCount > targetDepts ? _Status.warning : _Status.gap);
    final titleStatus = jobTitleCount == targetTitles
        ? _Status.ok
        : (jobTitleCount > targetTitles ? _Status.warning : _Status.gap);

    // حساب health score بسيط
    var score = 100;
    if (deptStatus != _Status.ok) score -= 15;
    if (titleStatus != _Status.ok) score -= 15;
    if (empCount == 0) score -= 20;
    if (roleCount < 5) score -= 10;
    score = score.clamp(0, 100);

    final scoreColor = score >= 80
        ? AppColors.success
        : (score >= 60 ? AppColors.warning : AppColors.danger);

    final theme = Theme.of(context);
    final mutedColor = theme.textTheme.bodySmall?.color ??
        (theme.brightness == Brightness.dark
            ? Colors.white70
            : Colors.grey[800]!);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scoreColor.withOpacity(theme.brightness == Brightness.dark ? 0.18 : 0.10),
            scoreColor.withOpacity(theme.brightness == Brightness.dark ? 0.08 : 0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scoreColor.withOpacity(0.30)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      value: score / 100,
                      strokeWidth: 4,
                      backgroundColor: theme.dividerColor.withOpacity(0.5),
                      valueColor: AlwaysStoppedAnimation<Color>(scoreColor),
                    ),
                  ),
                  Text(
                    '$score',
                    style: TextStyle(
                      color: scoreColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isAr ? 'صحّة الإعداد' : 'Setup Health',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      score >= 80
                          ? (isAr
                              ? '✅ كلّ شيء جاهز للعمل'
                              : '✅ All set up')
                          : score >= 60
                              ? (isAr
                                  ? '⚠️ يحتاج بعض التعديلات'
                                  : '⚠️ Needs attention')
                              : (isAr
                                  ? '🚨 إعداد ناقص — راجع التفاصيل'
                                  : '🚨 Setup incomplete'),
                      style: TextStyle(
                          fontSize: 11, color: mutedColor),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () =>
                    Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: AppBar(
                      title: Text(isAr ? 'صحّة النظام' : 'System Health'),
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                    ),
                    body: const SystemHealthScreen(),
                  ),
                )),
                icon: const Icon(Icons.health_and_safety_outlined,
                    size: 14),
                label: Text(
                  isAr ? 'تفاصيل' : 'Details',
                  style: const TextStyle(fontSize: 11),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // KPIs
          Row(
            children: [
              Expanded(
                child: _StatusPill(
                  icon: Icons.apartment_outlined,
                  label: isAr ? 'الأقسام' : 'Departments',
                  value: '$deptCount/$targetDepts',
                  status: deptStatus,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _StatusPill(
                  icon: Icons.badge_outlined,
                  label: isAr ? 'المسمّيات' : 'Job Titles',
                  value: '$jobTitleCount/$targetTitles',
                  status: titleStatus,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _StatusPill(
                  icon: Icons.shield_outlined,
                  label: isAr ? 'الأدوار' : 'Roles',
                  value: '$roleCount',
                  status: roleCount >= 5 ? _Status.ok : _Status.warning,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _StatusPill(
                  icon: Icons.people_outline,
                  label: isAr ? 'الموظفون' : 'Employees',
                  value: '$empCount',
                  status: empCount > 0 ? _Status.ok : _Status.gap,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _Status { ok, warning, gap }

class _StatusPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final _Status status;
  const _StatusPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = status == _Status.ok
        ? AppColors.success
        : status == _Status.warning
            ? AppColors.warning
            : AppColors.danger;
    final bgColor = status == _Status.ok
        ? (isDark ? color.withOpacity(0.15) : Colors.white)
        : color.withOpacity(isDark ? 0.18 : 0.08);
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 11, color: color),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.5,
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingCard extends StatelessWidget {
  final _SettingEntry setting;
  final bool isAr;
  const _SettingCard({required this.setting, required this.isAr});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: setting.color.withOpacity(0.3)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        // 🔧 Push the child screen DIRECTLY — every settings entry is
        // a full screen that brings its own Scaffold + AppBar. Wrapping
        // here would produce a duplicate header + invisible buttons
        // (see notification_templates_screen / device_sessions_screen).
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: setting.builder,
        )),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: setting.color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(setting.icon, color: setting.color, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isAr ? setting.titleAr : setting.titleEn,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isAr ? setting.descAr : setting.descEn,
                      style: TextStyle(
                          fontSize: 11.5,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                          height: 1.3),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.arrow_forward_ios,
                  size: 12, color: setting.color.withOpacity(0.6)),
            ],
          ),
        ),
      ),
    );
  }
}