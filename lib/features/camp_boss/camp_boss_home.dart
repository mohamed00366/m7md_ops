import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../models/enums.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/role_scaffold.dart';
import 'camp_boss_dashboard.dart';
import 'camp_boss_rooms.dart';
import 'camp_boss_rooms_reports.dart';
import 'camp_boss_uniform.dart';
import 'camp_boss_laundry.dart';
import 'camp_boss_buses.dart';

class CampBossHome extends StatefulWidget {
  const CampBossHome({super.key});

  @override
  State<CampBossHome> createState() => _CampBossHomeState();
}

class _CampBossHomeState extends State<CampBossHome> {
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
      title: s.campBoss,
      currentIndex: _index,
      onTabSelected: (i) => setState(() => _index = i),
      color: colorForRole(UserRole.campBoss),
      tabs: [
        RoleTab(
          icon: Icons.dashboard_outlined,
          title: s.dashboard,
          body: const CampBossDashboard(),
          requiredPermission: P.dashboardCampView,
        ),
        RoleTab(
          icon: Icons.bed_outlined,
          title: s.rooms,
          body: const CampBossRooms(),
          requiredPermission: P.campRoomsView,
        ),
        RoleTab(
          icon: Icons.assessment_outlined,
          title: s.isAr ? 'تقارير الغرف' : 'Rooms Reports',
          shortTitle: s.isAr ? 'تقارير' : 'Reports',
          body: const CampBossRoomsReports(),
          requiredPermission: P.campRoomsView,
        ),
        RoleTab(
          icon: Icons.checkroom_outlined,
          title: s.uniform,
          body: const CampBossUniform(),
        ),
        RoleTab(
          icon: Icons.local_laundry_service_outlined,
          title: s.laundry,
          body: const CampBossLaundry(),
          requiredPermission: P.campLaundryView,
        ),
        RoleTab(
          icon: Icons.directions_bus_outlined,
          title: s.busPlanning,
          shortTitle: s.isAr ? 'باصات' : 'Buses',
          body: const CampBossBuses(),
          requiredPermission: P.busesView,
        ),
      ],
    );
  }
}
