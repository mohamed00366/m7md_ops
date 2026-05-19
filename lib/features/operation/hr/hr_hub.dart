import 'package:flutter/material.dart';


import '../../../core/l10n/app_strings.dart';
import '../../manager/manager_employees.dart';
import 'hr_documents_screen.dart';
import 'hr_evaluations_screen.dart';
import 'hr_onboarding_screen.dart';
import 'hr_onpoint_training_screen.dart';
import 'hr_palette.dart';
import 'hr_reports_screen.dart';

/// 👥 قسم الموارد البشرية - 5 تبويبات
class HrHub extends StatefulWidget {
  const HrHub({super.key});

  @override
  State<HrHub> createState() => _HrHubState();
}

class _HrHubState extends State<HrHub> with TickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 6, vsync: this);
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
          indicatorColor: HrPalette.primary,
          labelColor: HrPalette.primary,
          unselectedLabelColor: Colors.black54,
          labelStyle:
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          tabs: [
            Tab(
                icon: const Icon(Icons.people_alt_outlined, size: 18),
                text: s.isAr ? 'الموظفون' : 'Employees'),
            Tab(
                icon: const Icon(Icons.assignment_outlined, size: 18),
                text: s.isAr ? 'الوثائق' : 'Documents'),
            Tab(
                icon: const Icon(Icons.person_add_alt_1, size: 18),
                text: s.isAr ? 'الالتحاق' : 'Onboarding'),
            Tab(
                icon: const Icon(Icons.school_outlined, size: 18),
                text: s.isAr ? '🎓 تدريب الجدد' : 'New Trainees'),
            Tab(
                icon: const Icon(Icons.bar_chart, size: 18),
                text: s.isAr ? 'تقارير HR' : 'HR Reports'),
            Tab(
                icon: const Icon(Icons.rate_review_outlined, size: 18),
                text: s.isAr ? 'التقييمات' : 'Evaluations'),
          ],
        ),
      ),
      Expanded(
        child: TabBarView(
          controller: _tab,
          children: const [
            ManagerEmployees(),
            HrDocumentsScreen(),
            HrOnboardingScreen(),
            HrOnPointTrainingScreen(),
            HrReportsScreen(),
            HrEvaluationsScreen(),
          ],
        ),
      ),
    ]);
  }
}
