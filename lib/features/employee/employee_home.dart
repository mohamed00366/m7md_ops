import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../models/enums.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/role_scaffold.dart';
import '../laundry/employee/employee_laundry_home.dart' as amanaEmp;
import '../policies/policies_screen.dart';
import 'employee_schedule.dart';
import 'employee_uniform.dart';
import 'employee_deductions.dart';
import 'employee_evaluations.dart';
import '../forms/employee_forms_screen.dart';

class EmployeeHome extends StatefulWidget {
  const EmployeeHome({super.key});

  @override
  State<EmployeeHome> createState() => _EmployeeHomeState();
}

class _EmployeeHomeState extends State<EmployeeHome> {
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
    final empId = auth.currentUser?.employeeId;
    // البَلَد: مِن سِجِلّ المُوَظَّف أَوّلاً (لِأَنّ activeCountryId قَد يَكون
    // فارِغاً لِغَير الـadmins)
    final emp = empId == null ? null : MockRepository().employeeById(empId);
    final countryId = emp?.countryId ?? auth.activeCountryId;
    return RoleScaffold(
      title: s.employee,
      currentIndex: _index,
      onTabSelected: (i) => setState(() => _index = i),
      color: colorForRole(UserRole.employee),
      tabs: [
        RoleTab(
          icon: Icons.calendar_today_outlined,
          title: s.mySchedule,
          shortTitle: s.isAr ? 'جدولي' : 'Schedule',
          body: const EmployeeSchedule(),
          requiredPermission: P.employeeScheduleView,
        ),
        RoleTab(
          icon: Icons.checkroom_outlined,
          title: s.myUniform,
          body: const EmployeeUniformView(),
          requiredPermission: P.employeeUniformView,
        ),
        // 🆕 المَغسَلة — نِظام "أَمانة" الجَديد
        RoleTab(
          icon: Icons.local_laundry_service_outlined,
          title: s.myLaundry,
          shortTitle: s.isAr ? 'المَغسَلة' : 'Laundry',
          body: empId == null
              ? const Center(child: Text('—'))
              : amanaEmp.EmployeeLaundryHome(
                  employeeId: empId,
                  countryId: countryId,
                ),
        ),
        RoleTab(
          icon: Icons.money_off_outlined,
          title: s.myDeductions,
          shortTitle: s.deductions,
          body: const EmployeeDeductions(),
          requiredPermission: P.employeeScheduleView,
        ),
        RoleTab(
          icon: Icons.star_outline,
          title: s.myEvaluations,
          shortTitle: s.rating,
          body: const EmployeeEvaluationsView(),
          requiredPermission: P.employeeScheduleView,
        ),
        // 🆕 النماذج (طلب إجازة، سلفة، شهادات...)
        RoleTab(
          icon: Icons.assignment_outlined,
          title: s.isAr ? 'النماذج' : 'Forms',
          shortTitle: s.isAr ? 'نماذج' : 'Forms',
          body: const EmployeeFormsScreen(),
        ),
        RoleTab(
          icon: Icons.menu_book_outlined,
          title: s.policies,
          body: const PoliciesScreen(),
          requiredPermission: P.policiesView,
        ),
      ],
    );
  }
}
