import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/role_scaffold.dart';
import '../../models/rbac.dart';
import '../manager/manager_settings.dart';
import 'admin_users.dart';
import 'admin_roles.dart';
import 'admin_audit.dart';
import 'admin_countries.dart';
import 'admin_overview.dart';
import 'organization_chart_screen.dart';
import 'org_builder_screen.dart';
import 'workflow_builder_screen.dart';
import 'approval_matrix_screen.dart';
import 'bulk_permissions_matrix_screen.dart';
import 'bulk_employee_ops_screen.dart';
import 'impersonate_picker.dart';
import 'system_health_screen.dart';
import 'config_export_screen.dart';
import 'notification_sender_screen.dart';
import 'admin_help_center.dart';
import 'point_assignment_settings_screen.dart';
import '../forms/admin_forms_screen.dart';

/// شاشة لوحة التحكم الإدارية - متاحة لـ Super Admin / Admin فقط
class AdminHome extends StatefulWidget {
  const AdminHome({super.key});

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  int _index = 0;

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
    return RoleScaffold(
      title: s.isAr ? 'لوحة الإدارة' : 'Admin Console',
      currentIndex: _index,
      onTabSelected: (i) => setState(() => _index = i),
      color: AppColors.brand,
      tabs: [
        RoleTab(
          icon: Icons.dashboard_outlined,
          title: s.isAr ? 'نظرة عامة' : 'Overview',
          shortTitle: s.isAr ? 'عامة' : 'Overview',
          body: const AdminOverview(),
        ),
        // 🆕 مركز المساعدة (Session 20) — أبدأ من هنا!
        RoleTab(
          icon: Icons.help_outline,
          title: s.isAr ? 'مركز المساعدة' : 'Help Center',
          shortTitle: s.isAr ? 'المساعدة' : 'Help',
          body: const AdminHelpCenter(),
        ),
        // 🆕 صحّة النظام (Session 5)
        RoleTab(
          icon: Icons.health_and_safety_outlined,
          title: s.isAr ? 'صحّة النظام' : 'System Health',
          shortTitle: s.isAr ? 'الصحّة' : 'Health',
          body: const SystemHealthScreen(),
        ),
        RoleTab(
          icon: Icons.people_outline,
          title: s.isAr ? 'المستخدمون' : 'Users',
          body: const AdminUsers(),
        ),
        RoleTab(
          icon: Icons.shield_outlined,
          title: s.isAr ? 'الأدوار' : 'Roles',
          body: const AdminRoles(),
        ),
        RoleTab(
          icon: Icons.public,
          title: s.isAr ? 'الدول' : 'Countries',
          body: const AdminCountries(),
        ),
        RoleTab(
          icon: Icons.list_alt_outlined,
          title: s.isAr ? 'القوائم المرجعية' : 'Lookups',
          shortTitle: s.isAr ? 'قوائم' : 'Lookups',
          body: const ManagerSettings(),
          requiredPermission: P.settingsLookupsView,
        ),
        // 🆕 إعدادات إسناد النقاط (مَن يُمكن ربطه بنقطة + يُرقّى)
        RoleTab(
          icon: Icons.pin_drop_outlined,
          title: s.isAr ? 'إعدادات إسناد النقاط' : 'Point Assignment Settings',
          shortTitle: s.isAr ? 'إسناد' : 'Assign',
          body: const PointAssignmentSettingsScreen(),
        ),
        // 🆕 الهيكل التنظيمي
        RoleTab(
          icon: Icons.account_tree_outlined,
          title: s.isAr ? 'الهيكل التنظيمي' : 'Organization',
          shortTitle: s.isAr ? 'الهيكل' : 'Org',
          body: const OrganizationChartScreen(),
        ),
        // 🆕 محرّر السحب والإفلات (Phase 8)
        RoleTab(
          icon: Icons.drag_indicator,
          title: s.isAr ? 'محرّر الهيكل' : 'Org Builder',
          shortTitle: s.isAr ? 'البناء' : 'Builder',
          body: const OrgBuilderScreen(),
        ),
        // 🆕 النماذج (طلبات الموظفين + الموافقات)
        RoleTab(
          icon: Icons.assignment_outlined,
          title: s.isAr ? 'النماذج' : 'Forms',
          shortTitle: s.isAr ? 'نماذج' : 'Forms',
          body: const AdminFormsScreen(),
        ),
        // 🆕 محرّر سير الموافقات (Phase 6)
        RoleTab(
          icon: Icons.auto_graph,
          title: s.isAr ? 'محرّر الموافقات' : 'Workflow Builder',
          shortTitle: s.isAr ? 'الموافقات' : 'Workflow',
          body: const WorkflowBuilderScreen(),
        ),
        // 🆕 مصفوفة الموافقات (Phase 7)
        RoleTab(
          icon: Icons.grid_view_outlined,
          title: s.isAr ? 'مصفوفة الموافقات' : 'Approval Matrix',
          shortTitle: s.isAr ? 'المصفوفة' : 'Matrix',
          body: const ApprovalMatrixScreen(),
        ),
        // 🆕 مصفوفة الصلاحيّات الجماعيّة (Bulk Perms Matrix)
        RoleTab(
          icon: Icons.security_outlined,
          title: s.isAr ? 'مصفوفة الصلاحيّات' : 'Permissions Matrix',
          shortTitle: s.isAr ? 'الصلاحيّات' : 'Perms',
          body: const BulkPermissionsMatrixScreen(),
        ),
        // 🆕 Session 17: عمليّات جماعيّة على الموظفين
        RoleTab(
          icon: Icons.dynamic_form_outlined,
          title: s.isAr ? 'عمليّات جماعيّة' : 'Bulk Operations',
          shortTitle: s.isAr ? 'جماعيّة' : 'Bulk',
          body: const BulkEmployeeOpsScreen(),
        ),
        // 🆕 العرض كحساب (Impersonate)
        RoleTab(
          icon: Icons.theater_comedy_outlined,
          title: s.isAr ? 'العرض كحساب' : 'Impersonate',
          shortTitle: s.isAr ? 'تجربة' : 'Try As',
          body: const ImpersonatePicker(),
        ),
        // 🆕 تصدير/استيراد الإعدادات (Session 8)
        RoleTab(
          icon: Icons.cloud_sync_outlined,
          title: s.isAr ? 'تصدير/استيراد' : 'Export/Import',
          shortTitle: s.isAr ? 'النسخ' : 'Backup',
          body: const ConfigExportScreen(),
        ),
        // 🆕 إرسال إشعار (Session 19)
        RoleTab(
          icon: Icons.campaign_outlined,
          title: s.isAr ? 'إرسال إشعار' : 'Send Notification',
          shortTitle: s.isAr ? 'إشعار' : 'Notify',
          body: const NotificationSenderScreen(),
        ),
        RoleTab(
          icon: Icons.history,
          title: s.isAr ? 'سجل النشاط' : 'Audit Log',
          shortTitle: s.isAr ? 'السجل' : 'Audit',
          body: const AdminAudit(),
        ),
      ],
    );
  }
}
