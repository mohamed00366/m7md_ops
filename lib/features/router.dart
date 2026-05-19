import 'package:flutter/material.dart';

import '../models/enums.dart';
import 'manager/manager_home.dart';
import 'operation/operation_home.dart';
import 'supervisor/supervisor_home.dart';
import 'camp_boss/camp_boss_home.dart';
import 'driver/driver_home.dart';
import 'employee/employee_home.dart';

/// يوزّع المستخدم على الـ Home الصحيح بناءً على الدور
class RoleHomeRouter extends StatelessWidget {
  final UserRole role;
  const RoleHomeRouter({super.key, required this.role});

  @override
  Widget build(BuildContext context) {
    switch (role) {
      case UserRole.manager:
        return const ManagerHome();
      case UserRole.operation:
        return const OperationHome();
      case UserRole.supervisor:
        return const SupervisorHome();
      case UserRole.campBoss:
        return const CampBossHome();
      case UserRole.driver:
        return const DriverHome();
      case UserRole.employee:
        return const EmployeeHome();
    }
  }
}
