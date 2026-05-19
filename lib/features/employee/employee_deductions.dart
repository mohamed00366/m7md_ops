import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/widgets.dart';

class EmployeeDeductions extends StatelessWidget {
  const EmployeeDeductions({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final auth = context.read<AuthProvider>();
    final empId = auth.currentUser?.employeeId;

    final myDeds = repo.deductions.where((d) => d.employeeId == empId).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    final total = myDeds.fold<double>(0, (a, d) => a + d.amount);

    if (myDeds.isEmpty) {
      return EmptyState(
        icon: Icons.money_off_outlined,
        message: s.isAr ? 'لا توجد خصومات' : 'No deductions',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.danger,
                AppColors.danger.withOpacity(0.7),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.isAr ? 'إجمالي الخصومات' : 'Total Deductions',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 6),
              Text(
                total.toStringAsFixed(2),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w800),
              ),
              Text(
                '${myDeds.length} ${s.isAr ? "عملية" : "items"}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ...myDeds.map((d) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.danger.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.money_off, color: AppColors.danger),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.reason,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700)),
                        Text('${d.date.day}/${d.date.month}/${d.date.year}',
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  Text(d.amount.toStringAsFixed(2),
                      style: const TextStyle(
                          color: AppColors.danger,
                          fontSize: 16,
                          fontWeight: FontWeight.w800)),
                ],
              ),
            )),
      ],
    );
  }
}
