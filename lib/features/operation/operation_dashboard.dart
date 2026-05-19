import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/widgets.dart';

class OperationDashboard extends StatelessWidget {
  const OperationDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();

    final pending = repo.rostersByStatus(RosterStatus.submitted).length;
    final approved = repo.rostersByStatus(RosterStatus.approved).length;
    final rejected = repo.rostersByStatus(RosterStatus.rejected).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.roleOperation,
                  AppColors.roleOperation.withOpacity(0.7),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.white,
                  child: Icon(Icons.dashboard_customize,
                      color: AppColors.roleOperation),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.operation,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800)),
                      Text(
                        s.isAr
                            ? 'موافقات الروستر وتعيين المشرفين'
                            : 'Roster approvals & supervisor assignments',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          GridResponsive(
            columns: 3,
            aspectRatio: 1,
            children: [
              StatCard(
                  label: s.pendingRosters,
                  value: '$pending',
                  icon: Icons.pending,
                  color: AppColors.warning),
              StatCard(
                  label: s.approvedRosters,
                  value: '$approved',
                  icon: Icons.check_circle,
                  color: AppColors.success),
              StatCard(
                  label: s.rejectedRosters,
                  value: '$rejected',
                  icon: Icons.cancel,
                  color: AppColors.danger),
            ],
          ),
          const SizedBox(height: 14),
          // الروسترات المعلقة - وصول سريع
          SectionCard(
            title: s.isAr ? 'الروسترات بانتظار المراجعة' : 'Awaiting Review',
            child: pending == 0
                ? EmptyState(
                    icon: Icons.check_circle_outline,
                    message: s.isAr
                        ? 'لا توجد روسترات للمراجعة'
                        : 'No rosters to review')
                : Column(
                    children: repo
                        .rostersByStatus(RosterStatus.submitted)
                        .map((r) {
                      final site = repo.siteById(r.siteId);
                      final sup = repo.employeeById(r.supervisorId);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber,
                                color: AppColors.warning, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    site?.displayName ?? '-',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13),
                                  ),
                                  Text(
                                    '${sup?.fullName ?? '-'} • ${r.assignments.length} ${s.isAr ? "وردية" : "shifts"}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '${r.weekStart.day}/${r.weekStart.month}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }
}
