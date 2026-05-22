import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/widgets.dart';

class SupervisorDashboard extends StatelessWidget {
  const SupervisorDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final auth = context.watch<AuthProvider>();
    final empId = auth.currentUser?.employeeId;

    // الموقع المُعيّن لهذا المشرف هذا الأسبوع
    final week = repo.currentWeekStart();
    final mySiteAssignment = repo.supervisorAssignments
        .where((a) =>
            a.supervisorEmployeeId == empId &&
            !week.isBefore(a.weekStart) &&
            !week.isAfter(a.weekEnd))
        .toList();

    final site = mySiteAssignment.isEmpty
        ? null
        : repo.siteById(mySiteAssignment.first.siteId);

    final myRoster = site == null
        ? null
        : repo.findRoster(site.id, week);

    final empsAtSite = site == null
        ? <dynamic>[]
        : repo.employeesAtSite(site.id);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // معلومات المشرف
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.roleSupervisor,
                  AppColors.roleSupervisor.withValues(alpha: 0.7),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const CircleAvatar(
                      radius: 22,
                      backgroundColor: Colors.white,
                      child: Icon(Icons.assignment_ind,
                          color: AppColors.roleSupervisor),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(auth.currentUser?.fullName ?? '-',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800)),
                          Text(s.supervisor,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.business,
                          color: Colors.white70, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          site?.displayName ??
                              (s.isAr ? 'لم يتم التعيين' : 'Not assigned'),
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          if (myRoster != null) ...[
            // حالة الروستر
            SectionCard(
              title: s.isAr ? 'حالة روستر هذا الأسبوع' : "This Week's Roster",
              child: Column(
                children: [
                  Row(
                    children: [
                      _statusIcon(myRoster.status),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.isAr
                                  ? myRoster.status.arabicLabel()
                                  : myRoster.status.englishLabel(),
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800),
                            ),
                            Text(
                              '${myRoster.assignments.length} ${s.isAr ? "وردية" : "shifts"} • ${myRoster.totalHours.toStringAsFixed(0)} ${s.isAr ? "ساعة" : "hours"}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (myRoster.status == RosterStatus.rejected &&
                      myRoster.rejectionReason != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber,
                              color: AppColors.danger, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${s.rejectionReason}: ${myRoster.rejectionReason}',
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.danger),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          // إحصاءات
          GridResponsive(
            columns: 2,
            aspectRatio: 1.4,
            children: [
              StatCard(
                  label: s.isAr ? 'موظفو الموقع' : 'Site Employees',
                  value: '${empsAtSite.length}',
                  icon: Icons.people,
                  color: AppColors.brand),
              StatCard(
                  label: s.isAr ? 'الورديات' : 'Shifts',
                  value: '${myRoster?.assignments.length ?? 0}',
                  icon: Icons.schedule,
                  color: AppColors.warning),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusIcon(RosterStatus s) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: _statusColor(s).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(_statusIconData(s), color: _statusColor(s)),
    );
  }

  Color _statusColor(RosterStatus s) {
    return switch (s) {
      RosterStatus.draft => AppColors.textTertiaryLight,
      RosterStatus.submitted => AppColors.warning,
      RosterStatus.underReview => AppColors.info,
      RosterStatus.approved => AppColors.success,
      RosterStatus.rejected => AppColors.danger,
    };
  }

  IconData _statusIconData(RosterStatus s) {
    return switch (s) {
      RosterStatus.draft => Icons.edit_outlined,
      RosterStatus.submitted => Icons.send_outlined,
      RosterStatus.underReview => Icons.hourglass_top,
      RosterStatus.approved => Icons.check_circle,
      RosterStatus.rejected => Icons.cancel,
    };
  }
}
