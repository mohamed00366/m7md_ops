import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../models/enums.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/role_scaffold.dart';
import 'supervisor_dashboard.dart';
import 'supervisor_roster_creator.dart';
import 'supervisor_evaluations.dart';
import 'supervisor_site_selector.dart';
import 'supervisor_approved_roster.dart';
import 'supervisor_my_rosters.dart';
import 'supervisor_morning_checklist.dart';

class SupervisorHome extends StatefulWidget {
  const SupervisorHome({super.key});

  @override
  State<SupervisorHome> createState() => _SupervisorHomeState();
}

class _SupervisorHomeState extends State<SupervisorHome> {
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
    // إذا لم يختر المشرف موقعاً بعد، اعرض شاشة الاختيار
    if (auth.selectedSiteId == null) {
      return const SupervisorSiteSelector();
    }
    return RoleScaffold(
      title: s.supervisor,
      currentIndex: _index,
      onTabSelected: (i) => setState(() => _index = i),
      color: colorForRole(UserRole.supervisor),
      tabs: [
        RoleTab(
          icon: Icons.dashboard_outlined,
          title: s.dashboard,
          body: const SupervisorDashboard(),
          requiredPermission: P.rostersView,
        ),
        RoleTab(
          icon: Icons.edit_calendar_outlined,
          title: s.draftRoster,
          shortTitle: s.isAr ? 'مسودة' : 'Draft',
          body: const SupervisorRosterCreator(),
          requiredPermission: P.rostersCreate,
        ),
        RoleTab(
          icon: Icons.list_alt,
          title: s.myRosters,
          shortTitle: s.isAr ? 'روستراتي' : 'Mine',
          body: const SupervisorMyRosters(),
          requiredPermission: P.rostersView,
        ),
        RoleTab(
          icon: Icons.verified_outlined,
          title: s.approvedRosterTab,
          shortTitle: s.isAr ? 'معتمد' : 'Approved',
          body: const SupervisorApprovedRoster(),
          requiredPermission: P.rostersView,
        ),
        RoleTab(
          icon: Icons.camera_alt_outlined,
          title: s.morningChecklist,
          shortTitle: s.morningChecklistShort,
          body: const SupervisorMorningChecklist(),
          requiredPermission: P.campChecklistView,
        ),
        RoleTab(
          icon: Icons.star_outline,
          title: s.employeeEvaluation,
          shortTitle: s.rating,
          body: const SupervisorEvaluations(),
          requiredPermission: P.rostersView,
        ),
      ],
    );
  }
}
