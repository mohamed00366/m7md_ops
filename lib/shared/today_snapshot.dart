import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/l10n/app_strings.dart';
import '../core/providers/auth_provider.dart';
import '../core/theme/app_colors.dart';
import '../models/enums.dart';
import '../repositories/mock_repository.dart';
import 'm7_stats_banner.dart';

/// 📊 لَوحة إحصائيّات Today's Snapshot لِلصَفحة الرَئيسيّة
///
/// تَعرِض أَرقاماً سَريعة تُعَطي لَمحة عَن حالة النِظام الآن.
/// تَستَخدِم `M7StatsBanner` لِلاتِّساق مَع باقي الشاشات.
class TodaySnapshot extends StatelessWidget {
  const TodaySnapshot({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final auth = context.watch<AuthProvider>();
    final repo = MockRepository();

    // فِلتَر بِالدَولة لَو مَوجودة
    final cid = auth.activeCountryId;
    final employees = cid == null
        ? repo.employees
        : repo.employees.where((e) => e.countryId == cid).toList();
    final buses = cid == null
        ? repo.buses
        : repo.buses.where((b) => b.countryId == cid).toList();
    final sites = cid == null
        ? repo.sites
        : repo.sites.where((s) => s.countryId == cid).toList();
    final points = cid == null
        ? repo.points
        : repo.points.where((p) => p.countryId == cid).toList();
    final masters = cid == null
        ? repo.masters
        : repo.masters.where((m) => m.countryId == cid).toList();

    final activeEmployees =
        employees.where((e) => e.status == EntityStatus.active).length;
    final activeBuses =
        buses.where((b) => b.status == EntityStatus.active).length;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                Icon(Icons.insights,
                    color: AppColors.brand.withOpacity(0.85), size: 16),
                const SizedBox(width: 6),
                Text(
                  s.t('لَمحة اليَوم', "Today's Snapshot", 'آج کی جھلک'),
                  style: TextStyle(
                      color: AppColors.brand.withOpacity(0.85),
                      fontWeight: FontWeight.w900,
                      fontSize: 13),
                ),
              ],
            ),
          ),
          M7StatsBanner(stats: [
            M7Stat(
              icon: Icons.people,
              label: s.t('مُوظَّفون', 'Employees', 'ملازمین'),
              value: activeEmployees,
              color: AppColors.brand,
            ),
            M7Stat(
              icon: Icons.directions_bus,
              label: s.t('باصات', 'Buses', 'بسیں'),
              value: activeBuses,
              color: AppColors.info,
            ),
            M7Stat(
              icon: Icons.business,
              label: s.t('عُملاء', 'Masters', 'گاہک'),
              value: masters.length,
              color: AppColors.gold,
            ),
            M7Stat(
              icon: Icons.storefront,
              label: s.t('فُروع', 'Sites', 'برانچز'),
              value: sites.length,
              color: AppColors.success,
            ),
            M7Stat(
              icon: Icons.place,
              label: s.t('نُقاط', 'Points', 'پوائنٹس'),
              value: points.length,
              color: AppColors.warning,
            ),
          ]),
        ],
      ),
    );
  }
}
