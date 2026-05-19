import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../repositories/mock_repository.dart';
import 'customers/masters_screen.dart';
import 'customers/points_screen.dart';

/// شاشة إدارة العملاء - الهيكل الهرمي:
///   Master (الاسم التجاري الأم)
///     └─ Clients (الفروع)
///   Points (نقاط البيع) ← يُربط بها العملاء
///
/// تابان فقط:
///   1) Customers (Masters expandable + Clients تحت كل Master)
///   2) Points (نقاط البيع المنفصلة + ربطها بالعملاء)
class CustomersHub extends StatefulWidget {
  const CustomersHub({super.key});

  @override
  State<CustomersHub> createState() => _CustomersHubState();
}

class _CustomersHubState extends State<CustomersHub>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    MockRepository().addListener(_onChange);
  }

  @override
  void dispose() {
    _tabs.dispose();
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        // ===== شريط التابات =====
        Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
            border: Border(
              bottom: BorderSide(
                  color: isDark
                      ? AppColors.borderDark
                      : AppColors.borderLight,
                  width: 0.5),
            ),
          ),
          child: TabBar(
            controller: _tabs,
            labelColor: AppColors.brand,
            unselectedLabelColor: isDark
                ? AppColors.textSecondaryDark
                : AppColors.textSecondaryLight,
            indicatorColor: AppColors.brand,
            indicatorWeight: 3,
            labelStyle: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800),
            unselectedLabelStyle: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w500),
            tabs: [
              Tab(
                icon: const Icon(Icons.business, size: 18),
                text: s.isAr
                    ? 'العملاء (${repo.masters.length})'
                    : 'Customers (${repo.masters.length})',
              ),
              Tab(
                icon: const Icon(Icons.place, size: 18),
                text: s.isAr
                    ? 'نقاط البيع (${repo.points.length})'
                    : 'POS Points (${repo.points.length})',
              ),
            ],
          ),
        ),
        // ===== المحتوى =====
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: const [
              MastersScreen(),
              PointsScreen(),
            ],
          ),
        ),
      ],
    );
  }
}
