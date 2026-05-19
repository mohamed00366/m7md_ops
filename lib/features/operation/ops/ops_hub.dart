import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../manager/manager_tracking.dart';
import '../hr/hr_palette.dart';
import '../operation_rosters.dart';
import '../operation_supervisor_assignments.dart';

/// ⚙️ قسم العمليات الفرعي
/// يحتوي: إسناد المشرفين للنقاط + الورديات + التتبع المباشر
class OpsHub extends StatefulWidget {
  const OpsHub({super.key});

  @override
  State<OpsHub> createState() => _OpsHubState();
}

class _OpsHubState extends State<OpsHub> with TickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Column(children: [
      Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            bottom: BorderSide(color: Colors.grey.shade200),
          ),
        ),
        child: TabBar(
          controller: _tab,
          isScrollable: true,
          indicatorColor: OpsPalette.primary,
          labelColor: OpsPalette.primary,
          unselectedLabelColor: Colors.black54,
          labelStyle:
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          tabs: [
            Tab(
                icon: const Icon(Icons.person_pin_circle_outlined, size: 18),
                text: s.isAr ? 'إسناد المشرفين' : 'Supervisors'),
            Tab(
                icon: const Icon(Icons.fact_check_outlined, size: 18),
                text: s.isAr ? 'الورديات' : 'Rosters'),
            Tab(
                icon: const Icon(Icons.location_on_outlined, size: 18),
                text: s.isAr ? 'التتبع' : 'Tracking'),
          ],
        ),
      ),
      Expanded(
        child: TabBarView(
          controller: _tab,
          children: const [
            OperationSupervisorAssignments(),
            OperationRosters(),
            ManagerTracking(),
          ],
        ),
      ),
    ]);
  }
}
