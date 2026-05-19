import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/m7_app_bar.dart';
import '../../shared/m7_stats_banner.dart';

/// 📊 لَوحة التَحليلات (Analytics Dashboard)
///
/// تُحَوِّل بَيانات النِظام إلى رُسومات بَيانيّة + KPIs لِفَهم الوَضع
/// عَلى مُستَوى عالٍ بِنَظرة سَريعة.
class AnalyticsDashboardScreen extends StatelessWidget {
  const AnalyticsDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final auth = context.watch<AuthProvider>();
    final repo = MockRepository();
    final cid = auth.activeCountryId;

    // فِلتَر بِالدَولة
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

    // ===== مَقاييس KPI =====
    final activeEmps =
        employees.where((e) => e.status == EntityStatus.active).length;
    final activeBuses =
        buses.where((b) => b.status == EntityStatus.active).length;
    final activeSites =
        sites.where((s) => s.status == EntityStatus.active).length;
    final docCompliance = _calculateDocCompliance(employees);

    // ===== بَيانات الـCategory donut =====
    final byCategory = <String, int>{};
    for (final e in employees) {
      final cat = e.category.isEmpty ? 'worker' : e.category;
      byCategory[cat] = (byCategory[cat] ?? 0) + 1;
    }

    // ===== بَيانات الباصات pie =====
    final busStatuses = <EntityStatus, int>{};
    for (final b in buses) {
      busStatuses[b.status] = (busStatuses[b.status] ?? 0) + 1;
    }

    // ===== مُوظَّفون لِكُلّ نُقطة (Top 10) =====
    final pointCounts = <String, int>{};
    for (final e in employees) {
      if (e.pointId == null) continue;
      pointCounts[e.pointId!] = (pointCounts[e.pointId!] ?? 0) + 1;
    }
    final topPoints = pointCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top10Points = topPoints.take(10).toList();

    // ===== الجِنسيّات =====
    final byNationality = <String, int>{};
    for (final e in employees) {
      final n = e.nationality.isEmpty ? '—' : e.nationality;
      byNationality[n] = (byNationality[n] ?? 0) + 1;
    }
    final topNationalities = byNationality.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? 'لَوحة التَحليلات' : 'Analytics Dashboard',
        subtitle: isAr ? 'رُؤى مِن بَيانات النِظام' : 'Insights from data',
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // ===== KPIs الرَئيسيّة =====
          M7StatsBanner(stats: [
            M7Stat(
                icon: Icons.people,
                label: isAr ? 'مُوظَّفون' : 'Employees',
                value: activeEmps,
                color: AppColors.brand),
            M7Stat(
                icon: Icons.directions_bus,
                label: isAr ? 'باصات' : 'Buses',
                value: activeBuses,
                color: AppColors.info),
            M7Stat(
                icon: Icons.business,
                label: isAr ? 'فُروع' : 'Sites',
                value: activeSites,
                color: AppColors.purple),
            M7Stat(
                icon: Icons.place,
                label: isAr ? 'نُقاط' : 'Points',
                value: points.length,
                color: AppColors.warning),
          ]),
          const SizedBox(height: 12),
          // ===== مُؤَشِّر امتِثال الوَثائِق =====
          _ComplianceCard(score: docCompliance, isAr: isAr),
          const SizedBox(height: 12),
          // ===== تَوزيع المُوظَّفين حَسَب الفِئة =====
          _ChartCard(
            titleAr: 'تَوزيع المُوظَّفين حَسَب الفِئة',
            titleEn: 'Employees by Category',
            icon: Icons.pie_chart,
            color: AppColors.brand,
            child: SizedBox(
              height: 200,
              child: byCategory.isEmpty
                  ? _emptyChart(isAr)
                  : Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: PieChart(
                            PieChartData(
                              sectionsSpace: 2,
                              centerSpaceRadius: 40,
                              sections: _categorySections(byCategory),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: byCategory.entries
                                .map((e) => _legendRow(
                                    label: _catLabel(e.key, isAr),
                                    value: e.value,
                                    total: employees.length,
                                    color: _catColor(e.key)))
                                .toList(),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 12),
          // ===== حالة الباصات =====
          _ChartCard(
            titleAr: 'حالة الأُسطول',
            titleEn: 'Fleet Status',
            icon: Icons.directions_bus,
            color: AppColors.info,
            child: SizedBox(
              height: 200,
              child: busStatuses.isEmpty
                  ? _emptyChart(isAr)
                  : Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: PieChart(
                            PieChartData(
                              sectionsSpace: 2,
                              centerSpaceRadius: 40,
                              sections: _busSections(busStatuses),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: busStatuses.entries
                                .map((e) => _legendRow(
                                    label: _statusLabel(e.key, isAr),
                                    value: e.value,
                                    total: buses.length,
                                    color: _statusColor(e.key)))
                                .toList(),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 12),
          // ===== Top 10 Points =====
          _ChartCard(
            titleAr: 'أَكبَر ١٠ نُقاط (عَدَد المُوظَّفين)',
            titleEn: 'Top 10 Points by Employees',
            icon: Icons.bar_chart,
            color: AppColors.warning,
            child: SizedBox(
              height: 260,
              child: top10Points.isEmpty
                  ? _emptyChart(isAr)
                  : BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        maxY: (top10Points.first.value * 1.2).toDouble(),
                        barTouchData: BarTouchData(enabled: true),
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 30,
                              getTitlesWidget: (v, _) => Text(
                                v.toInt().toString(),
                                style: const TextStyle(fontSize: 9),
                              ),
                            ),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
                              getTitlesWidget: (v, _) {
                                final idx = v.toInt();
                                if (idx >= top10Points.length) {
                                  return const SizedBox.shrink();
                                }
                                final pid = top10Points[idx].key;
                                final p = repo.points
                                    .where((p) => p.id == pid)
                                    .firstOrNull;
                                return Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    p?.code ?? '—',
                                    style: const TextStyle(
                                        fontSize: 8,
                                        fontFamily: 'monospace'),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        gridData: const FlGridData(show: true),
                        borderData: FlBorderData(show: false),
                        barGroups: [
                          for (var i = 0; i < top10Points.length; i++)
                            BarChartGroupData(
                              x: i,
                              barRods: [
                                BarChartRodData(
                                  toY: top10Points[i].value.toDouble(),
                                  color: AppColors.warning,
                                  width: 14,
                                  borderRadius:
                                      const BorderRadius.vertical(
                                          top: Radius.circular(4)),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          // ===== Top Nationalities =====
          _ChartCard(
            titleAr: 'أَكبَر الجِنسيّات',
            titleEn: 'Top Nationalities',
            icon: Icons.flag,
            color: AppColors.success,
            child: topNationalities.isEmpty
                ? SizedBox(height: 100, child: _emptyChart(isAr))
                : Column(
                    children: topNationalities.take(8).map((e) {
                      final pct =
                          (e.value / employees.length * 100).toStringAsFixed(1);
                      return _barRow(
                        label: e.key,
                        value: e.value,
                        max: topNationalities.first.value,
                        pct: pct,
                      );
                    }).toList(),
                  ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  // ============================================================
  // مُساعِدات
  // ============================================================
  double _calculateDocCompliance(List<dynamic> employees) {
    if (employees.isEmpty) return 1.0;
    int compliant = 0;
    int total = 0;
    for (final e in employees) {
      if (e.status != EntityStatus.active) continue;
      total++;
      // مُمتَثِل = لَدَيه جَواز سارٍ + هَوِيّة
      final hasPassport = e.passportNumber.isNotEmpty &&
          (e.passportExpiry == null ||
              e.passportExpiry!.isAfter(DateTime.now()));
      final hasId = e.idNumber.isNotEmpty;
      if (hasPassport && hasId) compliant++;
    }
    if (total == 0) return 1.0;
    return compliant / total;
  }

  List<PieChartSectionData> _categorySections(Map<String, int> data) {
    final total = data.values.fold<int>(0, (a, b) => a + b);
    return data.entries.map((e) {
      final pct = e.value / total * 100;
      return PieChartSectionData(
        value: e.value.toDouble(),
        color: _catColor(e.key),
        title: '${pct.toStringAsFixed(0)}%',
        radius: 50,
        titleStyle: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w800),
      );
    }).toList();
  }

  List<PieChartSectionData> _busSections(Map<EntityStatus, int> data) {
    final total = data.values.fold<int>(0, (a, b) => a + b);
    return data.entries.map((e) {
      final pct = e.value / total * 100;
      return PieChartSectionData(
        value: e.value.toDouble(),
        color: _statusColor(e.key),
        title: '${pct.toStringAsFixed(0)}%',
        radius: 50,
        titleStyle: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w800),
      );
    }).toList();
  }

  Color _catColor(String cat) {
    switch (cat) {
      case 'worker':
        return AppColors.brand;
      case 'admin':
        return AppColors.purple;
      case 'operations':
        return AppColors.gold;
      default:
        return Colors.grey;
    }
  }

  String _catLabel(String cat, bool isAr) {
    switch (cat) {
      case 'worker':
        return isAr ? 'عُمّال' : 'Workers';
      case 'admin':
        return isAr ? 'إداريّون' : 'Admin';
      case 'operations':
        return isAr ? 'عَمَليّات' : 'Operations';
      default:
        return cat;
    }
  }

  Color _statusColor(EntityStatus s) {
    switch (s) {
      case EntityStatus.active:
        return AppColors.success;
      case EntityStatus.inactive:
        return Colors.red;
      case EntityStatus.maintenance:
        return Colors.orange;
    }
  }

  String _statusLabel(EntityStatus s, bool isAr) {
    switch (s) {
      case EntityStatus.active:
        return isAr ? 'نَشِط' : 'Active';
      case EntityStatus.inactive:
        return isAr ? 'مُعَطَّل' : 'Inactive';
      case EntityStatus.maintenance:
        return isAr ? 'صِيانة' : 'Maintenance';
    }
  }

  Widget _emptyChart(bool isAr) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bar_chart, size: 36, color: Colors.grey.withOpacity(0.4)),
          const SizedBox(height: 6),
          Text(isAr ? 'لا تُوجَد بَيانات' : 'No data',
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _legendRow({
    required String label,
    required int value,
    required int total,
    required Color color,
  }) {
    final pct = total == 0 ? '0' : (value / total * 100).toStringAsFixed(1);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          Text(
            '$value',
            style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 12,
                fontFamily: 'monospace'),
          ),
          const SizedBox(width: 6),
          Text(
            '($pct%)',
            style:
                const TextStyle(fontSize: 10, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _barRow({
    required String label,
    required int value,
    required int max,
    required String pct,
  }) {
    final ratio = max == 0 ? 0.0 : value / max;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700)),
              ),
              Text('$value',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'monospace')),
              const SizedBox(width: 4),
              Text('($pct%)',
                  style: const TextStyle(
                      fontSize: 10, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: AppColors.success.withOpacity(0.10),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.success),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// بِطاقة رَسم بَيانيّ
// ============================================================
class _ChartCard extends StatelessWidget {
  final String titleAr;
  final String titleEn;
  final IconData icon;
  final Color color;
  final Widget child;
  const _ChartCard({
    required this.titleAr,
    required this.titleEn,
    required this.icon,
    required this.color,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 8),
                Text(isAr ? titleAr : titleEn,
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                        fontSize: 13)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: child,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// مُؤَشِّر امتِثال الوَثائِق
// ============================================================
class _ComplianceCard extends StatelessWidget {
  final double score;
  final bool isAr;
  const _ComplianceCard({required this.score, required this.isAr});

  @override
  Widget build(BuildContext context) {
    final pct = (score * 100).round();
    final color = score >= 0.85
        ? AppColors.success
        : score >= 0.50
            ? AppColors.gold
            : Colors.red;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.30)),
      ),
      child: Row(
        children: [
          // Gauge بَسيط (دائِريّ)
          SizedBox(
            width: 70,
            height: 70,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: score,
                  strokeWidth: 7,
                  backgroundColor: color.withOpacity(0.15),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
                Text('$pct%',
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        fontFamily: 'monospace')),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAr ? 'مُؤَشِّر امتِثال الوَثائِق' : 'Document Compliance',
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w900,
                      fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  isAr
                      ? 'نِسبة المُوظَّفين النَشِطين الذين لَدَيهم جَواز وَهَوِيّة سارِيَة'
                      : 'Active employees with valid passport + ID',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

extension _IterableX<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
