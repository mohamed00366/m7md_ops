import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../models/enums.dart';
import '../../../models/models.dart';
import '../../../repositories/mock_repository.dart';
import '../../manager/reports/buses_detail_report_screen.dart';
import '../camp_palette.dart';
import 'bus_detail_screen.dart';
import 'buses_shared.dart';

/// 📊 شاشة تقارير الباصات
class BusReportsScreen extends StatefulWidget {
  const BusReportsScreen({super.key});

  @override
  State<BusReportsScreen> createState() => _BusReportsScreenState();
}

class _BusReportsScreenState extends State<BusReportsScreen> {
  String _busSearch = '';
  String _empSearch = '';

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
    final auth = context.watch<AuthProvider>();

    final allBuses =
        auth.filterByCountry(repo.buses, (b) => b.countryId);
    final activeBuses =
        allBuses.where((b) => b.status == EntityStatus.active).toList();

    // ==== KPIs ====
    final totalBuses = allBuses.length;
    final totalCapacity =
        activeBuses.fold<int>(0, (a, b) => a + b.capacity);
    final usedSeats = repo.busEmployees.where((be) {
      try {
        final b = allBuses.firstWhere((x) => x.id == be.busId);
        return b.status == EntityStatus.active;
      } catch (_) {
        return false;
      }
    }).length;
    final freeSeats = (totalCapacity - usedSeats).clamp(0, 1 << 30);

    // الموظفون الذين يستخدمون الباص ولم يُربطوا بأي باص
    final usedBusModeIds = repo.transportModes
        .where((m) => m.key == 'used_bus')
        .map((m) => m.id)
        .toSet();
    final inAnyBus = <String>{
      for (final be in repo.busEmployees) be.employeeId,
    };
    final unassignedBusUsers = repo.employees.where((e) {
      if (e.status != EntityStatus.active) return false;
      if (!auth.isInScope(e.countryId)) return false;
      // 🆕 فقط موظفو السكن "خارج الكمب" يدخلون في حساب احتياج الباصات
      if (e.housingType != HousingType.offCamp) return false;
      if (e.transportModeId == null ||
          !usedBusModeIds.contains(e.transportModeId)) {
        return false;
      }
      return !inAnyBus.contains(e.id);
    }).toList();

    // ==== توزيع حسب النقطة ====
    final byPoint = <String, int>{}; // pointId -> bus count
    final empByPoint = <String, int>{}; // pointId -> emp count
    for (final b in activeBuses) {
      final k = b.assignedPointId ?? '_unset';
      byPoint[k] = (byPoint[k] ?? 0) + 1;
      final n = repo.busEmployees.where((be) => be.busId == b.id).length;
      empByPoint[k] = (empByPoint[k] ?? 0) + n;
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 30),
        children: [
          // ====== 🆕 الدخول للتقارير التفصيلية (4 تبويبات) ======
          _DetailedReportsCta(isAr: s.isAr),
          const SizedBox(height: 16),
          // ====== KPIs ======
          Text(s.isAr ? 'نظرة عامة' : 'Overview',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Kpi(
                icon: Icons.directions_bus,
                color: BusesPalette.primary,
                label: s.isAr ? 'إجمالي الباصات' : 'Total Buses',
                value: '$totalBuses',
              ),
              _Kpi(
                icon: Icons.check_circle,
                color: BusesPalette.success,
                label: s.isAr ? 'النشطة' : 'Active',
                value: '${activeBuses.length}',
              ),
              _Kpi(
                icon: Icons.event_seat,
                color: BusesPalette.info,
                label: s.isAr ? 'المقاعد الكلية' : 'Total Seats',
                value: '$totalCapacity',
              ),
              _Kpi(
                icon: Icons.people,
                color: BusesPalette.success,
                label: s.isAr ? 'مستخدَمة' : 'Used',
                value: '$usedSeats',
                hint: totalCapacity == 0
                    ? null
                    : '${(usedSeats / totalCapacity * 100).toStringAsFixed(0)}%',
              ),
              _Kpi(
                icon: Icons.event_seat_outlined,
                color: BusesPalette.warning,
                label: s.isAr ? 'متاحة' : 'Free',
                value: '$freeSeats',
              ),
              if (unassignedBusUsers.isNotEmpty)
                _Kpi(
                  icon: Icons.warning_amber_rounded,
                  color: BusesPalette.danger,
                  label: s.isAr
                      ? 'بدون باص (يحتاج ربط)'
                      : 'No bus (need link)',
                  value: '${unassignedBusUsers.length}',
                ),
            ],
          ),
          const SizedBox(height: 18),

          // ====== الموظفون بدون باص ======
          if (unassignedBusUsers.isNotEmpty) ...[
            _SectionHeader(
              icon: Icons.warning_amber_rounded,
              label: s.isAr
                  ? 'موظفون يحتاجون ربط بباص'
                  : 'Employees needing a bus',
              color: BusesPalette.danger,
              count: unassignedBusUsers.length,
            ),
            Container(
              decoration: BoxDecoration(
                color: CampPalette.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: BusesPalette.danger.withValues(alpha: 0.30)),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: BusesSearchBar(
                      hint: s.isAr
                          ? 'بحث الموظف بالاسم/الكود...'
                          : 'Search employee by name/code...',
                      value: _empSearch,
                      onChanged: (v) => setState(() => _empSearch = v),
                    ),
                  ),
                  ..._filterAndShow(unassignedBusUsers, _empSearch).map(
                    (e) => _UnassignedEmpRow(employee: e),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
          ],

          // ====== توزيع حسب النقطة ======
          _SectionHeader(
            icon: Icons.location_on_outlined,
            label: s.isAr ? 'حسب النقطة' : 'By Point',
            color: BusesPalette.secondary,
          ),
          if (byPoint.isEmpty)
            _EmptyTile(text: s.isAr ? 'لا بيانات' : 'No data')
          else
            Container(
              decoration: BoxDecoration(
                color: CampPalette.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: CampPalette.border),
              ),
              child: Column(
                children: [
                  for (final entry in byPoint.entries)
                    _PointRow(
                      pointId: entry.key,
                      busCount: entry.value,
                      empCount: empByPoint[entry.key] ?? 0,
                      isAr: s.isAr,
                    ),
                ],
              ),
            ),
          const SizedBox(height: 18),

          // ====== جدول إشغال الباصات ======
          _SectionHeader(
            icon: Icons.bar_chart,
            label: s.isAr ? 'إشغال الباصات' : 'Bus Utilization',
            color: BusesPalette.primary,
          ),
          Container(
            decoration: BoxDecoration(
              color: CampPalette.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: CampPalette.border),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: BusesSearchBar(
                    hint: s.isAr
                        ? 'بحث الباص بالاسم/اللوحة...'
                        : 'Search bus by name/plate...',
                    value: _busSearch,
                    onChanged: (v) => setState(() => _busSearch = v),
                  ),
                ),
                ...allBuses.where((b) {
                  if (_busSearch.trim().isEmpty) return true;
                  return busesMatchesQuery(_busSearch,
                      [b.name, b.plateNumber, b.model]);
                }).map((b) => _UtilizationRow(bus: b)),
                if (allBuses.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(s.isAr ? 'لا باصات' : 'No buses',
                        style: const TextStyle(
                            color: CampPalette.textSecondary)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Employee> _filterAndShow(List<Employee> list, String q) {
    if (q.trim().isEmpty) return list.take(20).toList();
    return list.where((e) {
      return busesMatchesQuery(q, [e.fullName, e.code, e.mobile]);
    }).toList();
  }
}

// ============================================================
// 🆕 CTA: الدخول للتقارير التفصيلية (4 تبويبات)
// ============================================================
class _DetailedReportsCta extends StatelessWidget {
  final bool isAr;
  const _DetailedReportsCta({required this.isAr});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const BusesDetailReportScreen(),
          ));
        },
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              colors: [
                BusesPalette.primary,
                BusesPalette.primary.withValues(alpha: 0.78),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: BusesPalette.primary.withValues(alpha: 0.25),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.insights_rounded,
                    color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isAr
                          ? 'التقارير التفصيلية للرحلات'
                          : 'Detailed Trip Reports',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isAr
                          ? 'الجدول اليومي · الزمني · السعة · حسب النقطة'
                          : 'Daily · Hourly · Capacity · Per-Point',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.92),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: Colors.white, size: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// عناصر مساعدة
// ============================================================

class _Kpi extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String? hint;
  const _Kpi({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Container(
        decoration: BoxDecoration(
          color: CampPalette.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: CampPalette.border),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(height: 8),
            Text(value,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: CampPalette.text)),
            const SizedBox(height: 2),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: CampPalette.textSecondary, fontSize: 11)),
            if (hint != null)
              Text(hint!,
                  style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final int? count;
  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.color,
    this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w900)),
          if (count != null) ...[
            const SizedBox(width: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('$count',
                  style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w900)),
            ),
          ],
        ],
      ),
    );
  }
}

class _PointRow extends StatelessWidget {
  final String pointId;
  final int busCount;
  final int empCount;
  final bool isAr;
  const _PointRow({
    required this.pointId,
    required this.busCount,
    required this.empCount,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    final repo = MockRepository();
    String name = isAr ? 'بدون نقطة' : 'Unassigned';
    if (pointId != '_unset') {
      try {
        final p = repo.points.firstWhere((x) => x.id == pointId);
        name = p.name;
      } catch (_) {}
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: CampPalette.borderLight)),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_on,
              size: 16, color: BusesPalette.secondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(name,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w800)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: BusesPalette.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.directions_bus,
                    size: 10, color: BusesPalette.primary),
                const SizedBox(width: 3),
                Text('$busCount',
                    style: const TextStyle(
                        color: BusesPalette.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w900)),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: BusesPalette.success.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.people,
                    size: 10, color: BusesPalette.success),
                const SizedBox(width: 3),
                Text('$empCount',
                    style: const TextStyle(
                        color: BusesPalette.success,
                        fontSize: 11,
                        fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UtilizationRow extends StatelessWidget {
  final Bus bus;
  const _UtilizationRow({required this.bus});

  @override
  Widget build(BuildContext context) {
    final repo = MockRepository();
    final n = repo.busEmployees.where((e) => e.busId == bus.id).length;
    final pct = bus.capacity == 0 ? 0.0 : (n / bus.capacity).clamp(0.0, 1.0);
    final color = pct >= 0.9
        ? CampPalette.red
        : (pct >= 0.6 ? CampPalette.amberDark : CampPalette.green);
    return InkWell(
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => BusDetailScreen(busId: bus.id),
        ));
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: CampPalette.borderLight)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: BusesPalette.primary,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(bus.name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900)),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(bus.plateNumber,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 4,
                      backgroundColor: color.withValues(alpha: 0.10),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('$n/${bus.capacity}',
                  style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w900)),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right,
                color: CampPalette.textTertiary, size: 16),
          ],
        ),
      ),
    );
  }
}

class _UnassignedEmpRow extends StatelessWidget {
  final Employee employee;
  const _UnassignedEmpRow({required this.employee});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: CampPalette.borderLight)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: BusesPalette.danger.withValues(alpha: 0.15),
            child: Text(employee.initials,
                style: const TextStyle(
                    color: BusesPalette.danger,
                    fontSize: 10,
                    fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(employee.fullName,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w800)),
                Text(employee.code,
                    style: const TextStyle(
                        fontSize: 10,
                        color: CampPalette.textSecondary)),
              ],
            ),
          ),
          const Icon(Icons.warning_amber_rounded,
              color: BusesPalette.danger, size: 14),
        ],
      ),
    );
  }
}

class _EmptyTile extends StatelessWidget {
  final String text;
  const _EmptyTile({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: CampPalette.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CampPalette.border),
      ),
      child: Center(
        child: Text(text,
            style: const TextStyle(color: CampPalette.textSecondary)),
      ),
    );
  }
}
