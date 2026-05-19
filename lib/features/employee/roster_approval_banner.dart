import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';
import 'employee_my_roster.dart';

/// 🔔 شريط إشعار خفيف يظهر للموظف عند اعتماد روستر جديد له
/// (يقتصر على آخر ٧ أيام لتجنّب الضوضاء البصرية)
class RosterApprovalBanner extends StatefulWidget {
  const RosterApprovalBanner({super.key});

  @override
  State<RosterApprovalBanner> createState() => _RosterApprovalBannerState();
}

class _RosterApprovalBannerState extends State<RosterApprovalBanner> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
    final s = AppStrings.of(context);
    final auth = context.watch<AuthProvider>();
    final empId = auth.currentUser?.employeeId;
    if (empId == null) return const SizedBox.shrink();
    final repo = MockRepository();

    // ابحث عن أحدث روستر معتمد للموظف خلال آخر 14 يوماً
    final cutoff = DateTime.now().subtract(const Duration(days: 14));
    WeeklyRoster? latest;
    DateTime? latestApprovedAt;
    for (final r in repo.rosters) {
      if (r.status != RosterStatus.approved) continue;
      if (r.reviewedAt == null) continue;
      if (r.reviewedAt!.isBefore(cutoff)) continue;
      final hasMine = r.assignments.any((a) => a.employeeId == empId);
      if (!hasMine) continue;
      if (latestApprovedAt == null || r.reviewedAt!.isAfter(latestApprovedAt)) {
        latest = r;
        latestApprovedAt = r.reviewedAt;
      }
    }
    if (latest == null) return const SizedBox.shrink();

    final point = repo.pointById(latest.siteId);
    final myShifts =
        latest.assignments.where((a) => a.employeeId == empId).toList();
    final myHours = myShifts.fold<double>(0, (acc, a) => acc + a.hours);
    final daysSince = DateTime.now().difference(latestApprovedAt!).inDays;
    final whenLabel = daysSince == 0
        ? (s.isAr ? 'اليوم' : 'today')
        : daysSince == 1
            ? (s.isAr ? 'أمس' : 'yesterday')
            : (s.isAr ? 'منذ $daysSince أيام' : '$daysSince days ago');

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.success.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.success.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: AppColors.success,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.isAr ? '✅ تم اعتماد روسترك' : '✅ Your roster is approved',
                  style: const TextStyle(
                      color: AppColors.success,
                      fontSize: 13,
                      fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  s.isAr
                      ? '${myShifts.where((a) => a.shiftType != ShiftType.off).length} وردية • ${myHours.toStringAsFixed(0)}h • ${point?.name ?? "—"} ($whenLabel)'
                      : '${myShifts.where((a) => a.shiftType != ShiftType.off).length} shifts • ${myHours.toStringAsFixed(0)}h • ${point?.name ?? "—"} ($whenLabel)',
                  style: TextStyle(
                      fontSize: 11,
                      color: AppColors.success.withOpacity(0.85),
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: s.isAr ? 'افتح روستري' : 'Open my roster',
            iconSize: 18,
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                settings: const RouteSettings(name: '/my_roster'),
                builder: (_) => Scaffold(
                  appBar: AppBar(
                    title: Text(s.isAr ? 'روستري' : 'My Roster'),
                  ),
                  body: const EmployeeMyRoster(),
                ),
              ));
            },
            icon: const Icon(Icons.arrow_forward, color: AppColors.success),
          ),
          IconButton(
            tooltip: s.isAr ? 'إخفاء' : 'Dismiss',
            iconSize: 16,
            onPressed: () => setState(() => _dismissed = true),
            icon:
                const Icon(Icons.close, color: AppColors.textTertiaryLight),
          ),
        ],
      ),
    );
  }
}

