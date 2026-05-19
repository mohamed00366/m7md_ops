import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/widgets.dart';
// ⚠️ تَمّ إزالة قِسم المَغسلة — يُستَخدَم الآن نِظام "أَمانة" المُستَقِلّ
// عَبر موديول my_laundry في الـ Home.

class EmployeeUniformView extends StatefulWidget {
  const EmployeeUniformView({super.key});

  @override
  State<EmployeeUniformView> createState() => _EmployeeUniformViewState();
}

class _EmployeeUniformViewState extends State<EmployeeUniformView> {
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
    final repo = MockRepository();
    final auth = context.read<AuthProvider>();
    final empId = auth.currentUser?.employeeId;
    if (empId == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            s.isAr
                ? 'هذه الشاشة مخصصة للموظفين'
                : 'This screen is for employees only',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final myUniforms =
        repo.employeeUniforms.where((u) => u.employeeId == empId).toList();

    if (myUniforms.isEmpty) {
      return EmptyState(
        icon: Icons.checkroom_outlined,
        message: s.isAr ? 'لم يُسلّم لك زي بعد' : 'No uniform issued yet',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // ===== الزي =====
        if (myUniforms.isNotEmpty)
          SectionCard(
            title: s.isAr ? 'الزي المُسلّم لي' : 'Issued Uniforms',
            child: Column(
              children: myUniforms.map((u) {
                final item = repo.uniformCatalog.firstWhere(
                  (x) => x.id == u.uniformItemId,
                  orElse: () => UniformItem(
                    id: '',
                    nameAr: '?',
                    nameEn: '?',
                  ),
                );
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: u.isReturned
                        ? AppColors.success.withOpacity(0.08)
                        : AppColors.purple.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        u.isReturned ? Icons.check_circle : Icons.checkroom,
                        color: u.isReturned
                            ? AppColors.success
                            : AppColors.purple,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.isAr ? item.nameAr : item.nameEn,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800)),
                            Text(
                              u.isReturned
                                  ? (s.isAr ? 'تم الإرجاع' : 'Returned')
                                  : (s.isAr ? 'في عهدتي' : 'In my custody'),
                              style: const TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}
