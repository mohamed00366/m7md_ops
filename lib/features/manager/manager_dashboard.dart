import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/widgets.dart';
import 'manager_reports.dart';

class ManagerDashboard extends StatelessWidget {
  const ManagerDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();

    final totalEmps = repo.employees.length;
    final activeEmps = repo.countActiveEmployees();
    final inactiveEmps = totalEmps - activeEmps;
    final totalSites = repo.sites.length;
    final activeSites = repo.countActiveSites();
    final totalBuses = repo.buses.length;
    final activeBuses = repo.countActiveBuses();
    final workingToday = repo.countWorkingToday();
    final offToday = activeEmps - workingToday;
    final todayTrips = repo.countTodayTrips();
    final pending = repo.rostersByStatus(RosterStatus.submitted).length;
    final approved = repo.rostersByStatus(RosterStatus.approved).length;
    final rejected = repo.rostersByStatus(RosterStatus.rejected).length;

    final perSite = repo.employeesPerSite();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ترحيب
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.roleManager, AppColors.brand],
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
                  child: Icon(Icons.dashboard, color: AppColors.roleManager),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.dashboard,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800),
                      ),
                      Text(
                        s.isAr
                            ? 'نظرة عامة على النظام'
                            : 'System overview',
                        style:
                            const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // البطاقات الإحصائية
          GridResponsive(
            columns: 2,
            aspectRatio: 1.4,
            children: [
              StatCard(
                label: s.totalEmployees,
                value: '$totalEmps',
                icon: Icons.people,
                color: AppColors.brand,
              ),
              StatCard(
                label: s.activeEmployees,
                value: '$activeEmps',
                icon: Icons.person,
                color: AppColors.success,
              ),
              StatCard(
                label: s.inactiveEmployees,
                value: '$inactiveEmps',
                icon: Icons.person_off,
                color: AppColors.danger,
              ),
              StatCard(
                label: s.activeSites,
                value: '$activeSites/$totalSites',
                icon: Icons.business,
                color: AppColors.purple,
              ),
              StatCard(
                label: s.activeBuses,
                value: '$activeBuses/$totalBuses',
                icon: Icons.directions_bus,
                color: AppColors.warning,
              ),
              StatCard(
                label: s.todayTrips,
                value: '$todayTrips',
                icon: Icons.route,
                color: AppColors.teal,
              ),
              StatCard(
                label: s.workingToday,
                value: '$workingToday',
                icon: Icons.work,
                color: AppColors.success,
              ),
              StatCard(
                label: s.offToday,
                value: '$offToday',
                icon: Icons.beach_access,
                color: AppColors.info,
              ),
            ],
          ),
          const SizedBox(height: 14),

          // الورديات
          SectionCard(
            title: s.rosters,
            child: Row(
              children: [
                Expanded(
                  child: _MiniMetric(
                    label: s.pendingRosters,
                    value: '$pending',
                    color: AppColors.warning,
                    icon: Icons.pending_outlined,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MiniMetric(
                    label: s.approvedRosters,
                    value: '$approved',
                    color: AppColors.success,
                    icon: Icons.check_circle_outline,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MiniMetric(
                    label: s.rejectedRosters,
                    value: '$rejected',
                    color: AppColors.danger,
                    icon: Icons.cancel_outlined,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // موظفون لكل موقع
          if (perSite.isNotEmpty)
            SectionCard(
              title: s.isAr ? 'الموظفون حسب الموقع' : 'Employees per Site',
              child: SizedBox(
                height: 180,
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: (perSite.values.fold<int>(0, (a, b) => a > b ? a : b))
                            .toDouble() +
                        2,
                    barTouchData: BarTouchData(enabled: false),
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      leftTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 30,
                          getTitlesWidget: (v, _) {
                            final keys = perSite.keys.toList();
                            if (v.toInt() >= keys.length) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                keys[v.toInt()],
                                style: const TextStyle(fontSize: 10),
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    barGroups: [
                      for (var i = 0; i < perSite.length; i++)
                        BarChartGroupData(
                          x: i,
                          barRods: [
                            BarChartRodData(
                              toY: perSite.values.elementAt(i).toDouble(),
                              color: AppColors.brand,
                              width: 28,
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(6),
                                topRight: Radius.circular(6),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),

          // وصول للتقارير
          SectionCard(
            title: s.reports,
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.info.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child:
                        const Icon(Icons.bar_chart, color: AppColors.info),
                  ),
                  title: Text(
                      s.isAr ? 'تقارير شاملة' : 'Comprehensive Reports'),
                  subtitle: Text(s.isAr
                      ? 'موظفون / مواقع / باصات / حضور'
                      : 'Employees / Sites / Buses / Attendance'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  onTap: () {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const ManagerReports()));
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _MiniMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
                color: color, fontSize: 18, fontWeight: FontWeight.w800),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 10),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
