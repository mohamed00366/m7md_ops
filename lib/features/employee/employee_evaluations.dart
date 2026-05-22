import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/widgets.dart';

class EmployeeEvaluationsView extends StatelessWidget {
  const EmployeeEvaluationsView({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final auth = context.read<AuthProvider>();
    final empId = auth.currentUser?.employeeId;

    final evals =
        repo.employeeEvaluations.where((e) => e.employeeId == empId).toList()
          ..sort((a, b) => b.date.compareTo(a.date));

    if (evals.isEmpty) {
      return EmptyState(
        icon: Icons.star_outline,
        message: s.isAr ? 'لا توجد تقييمات' : 'No evaluations',
      );
    }

    final avg =
        evals.fold<int>(0, (a, e) => a + e.rating) / evals.length;

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.warning,
                AppColors.warning.withValues(alpha: 0.7),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.isAr ? 'متوسط التقييم' : 'Average Rating',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(avg.toStringAsFixed(1),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(width: 12),
                  Row(
                    children: List.generate(
                      5,
                      (i) => Icon(
                        i < avg.round() ? Icons.star : Icons.star_border,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                '${evals.length} ${s.isAr ? "تقييم" : "evaluations"}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ...evals.map((e) {
          final by = repo.employeeById(e.evaluatedBy);
          final site = repo.siteById(e.siteId);
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Row(
                      children: List.generate(
                        5,
                        (i) => Icon(
                          i < e.rating ? Icons.star : Icons.star_border,
                          color: AppColors.warning,
                          size: 18,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text('${e.date.day}/${e.date.month}/${e.date.year}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
                if (e.notes != null && e.notes!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(e.notes!),
                ],
                const SizedBox(height: 8),
                Text(
                  s.isAr
                      ? 'بواسطة: ${by?.fullName ?? "-"}${site != null ? " • ${site.displayName}" : ""}'
                      : 'By: ${by?.fullName ?? "-"}${site != null ? " • ${site.displayName}" : ""}',
                  style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).disabledColor),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
