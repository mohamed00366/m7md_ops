import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../models/enums.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/role_scaffold.dart';
import 'hr/hr_hub.dart';
import 'operation_dashboard.dart';
import 'ops/ops_hub.dart';
import 'sales/sales_hub.dart';

/// 🏢 الواجهة الرئيسية لقائمة العمليات
/// 🆕 الهيكل الجديد: Dashboard + 3 أقسام (HR / Sales / Operations)
class OperationHome extends StatefulWidget {
  const OperationHome({super.key});

  @override
  State<OperationHome> createState() => _OperationHomeState();
}

class _OperationHomeState extends State<OperationHome> {
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
      title: s.operation,
      currentIndex: _index,
      onTabSelected: (i) => setState(() => _index = i),
      color: colorForRole(UserRole.operation),
      tabs: [
        RoleTab(
          icon: Icons.dashboard_outlined,
          title: s.dashboard,
          body: const OperationDashboard(),
          requiredPermission: P.dashboardOperationView,
        ),
        // 🆕 قسم الموارد البشرية
        RoleTab(
          icon: Icons.people_alt_outlined,
          title: s.isAr ? 'الموارد البشرية' : 'HR',
          shortTitle: 'HR',
          body: const HrHub(),
          requiredPermission: P.employeesView,
        ),
        // 🆕 قسم المبيعات
        RoleTab(
          icon: Icons.handshake_outlined,
          title: s.isAr ? 'المبيعات' : 'Sales',
          shortTitle: s.isAr ? 'مبيعات' : 'Sales',
          body: const SalesHub(),
          requiredPermission: P.sitesView,
        ),
        // 🆕 قسم العمليات الفرعي
        RoleTab(
          icon: Icons.settings_input_component_outlined,
          title: s.isAr ? 'العمليات' : 'Operations',
          shortTitle: 'Ops',
          body: const OpsHub(),
          requiredPermission: P.rostersView,
        ),
      ],
    );
  }
}
