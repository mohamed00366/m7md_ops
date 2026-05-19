import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../models/enums.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/role_scaffold.dart';
import 'customers_hub.dart';
import 'manager_dashboard.dart';
import 'manager_employees.dart';
import 'manager_buses.dart';
import 'manager_tracking.dart';

class ManagerHome extends StatefulWidget {
  const ManagerHome({super.key});

  @override
  State<ManagerHome> createState() => _ManagerHomeState();
}

class _ManagerHomeState extends State<ManagerHome> {
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
    final auth = context.watch<AuthProvider>();
    // العنوان يأتي من الدور النشط (Admin أو Manager) وليس مكتوباً ثابتاً
    final title = auth.activeRole != null
        ? (s.isAr ? auth.activeRole!.nameAr : auth.activeRole!.nameEn)
        : s.manager;
    return RoleScaffold(
      title: title,
      currentIndex: _index,
      onTabSelected: (i) => setState(() => _index = i),
      color: colorForRole(UserRole.manager),
      tabs: [
        RoleTab(
          icon: Icons.dashboard_outlined,
          title: s.dashboard,
          body: const ManagerDashboard(),
          requiredPermission: P.dashboardManagerView,
        ),
        RoleTab(
          icon: Icons.business_outlined,
          title: s.sites,
          body: const CustomersHub(),
          requiredPermission: P.sitesView,
        ),
        RoleTab(
          icon: Icons.people_outlined,
          title: s.employees,
          body: const ManagerEmployees(),
          requiredPermission: P.employeesView,
        ),
        RoleTab(
          icon: Icons.directions_bus_outlined,
          title: s.buses,
          body: const ManagerBuses(),
          requiredPermission: P.busesView,
        ),
        RoleTab(
          icon: Icons.location_on_outlined,
          title: s.liveTracking,
          shortTitle: s.isAr ? 'تتبع' : 'Track',
          body: const ManagerTracking(),
          requiredPermission: P.trackingLiveView,
        ),
        // ملاحظة: تاب الإعدادات/القوائم المرجعية انتقل لـ Admin Console
      ],
    );
  }
}
