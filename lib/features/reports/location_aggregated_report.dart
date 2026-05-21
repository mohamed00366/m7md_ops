// =============================================================================
// 📍 Location Aggregated Report — Full Point/Site 360° in ONE screen
// =============================================================================
// Pick one Point → see EVERYTHING about that location:
//   • Point header (name / code / city)
//   • Employees working there (with status colors)
//   • Attendance summary (last 30d) for the location
//   • Active leaves (people away right now)
//   • Recent rosters covering this point
//   • Disciplinary count
//   • Expiring documents across the location's workforce
// =============================================================================
import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/m7_log.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/m7_app_bar.dart';
import 'employee_aggregated_report.dart';

class LocationAggregatedReport extends StatefulWidget {
  final String? pointId;
  const LocationAggregatedReport({super.key, this.pointId});

  @override
  State<LocationAggregatedReport> createState() =>
      _LocationAggregatedReportState();
}

class _LocationAggregatedReportState extends State<LocationAggregatedReport> {
  String? _selectedId;
  Point? _point;
  bool _loading = false;

  // Aggregations
  List<Employee> _employees = [];
  int _clockIns30d = 0;
  int _clockOuts30d = 0;
  int _activeLeavesNow = 0;
  int _pendingLeaves = 0;
  int _activeDeductions = 0;
  int _expiringDocs60d = 0;
  List<Map<String, dynamic>> _rosters = [];
  List<Map<String, dynamic>> _latestLeaves = [];

  @override
  void initState() {
    super.initState();
    _selectedId = widget.pointId;
    if (_selectedId != null) _loadAll();
  }

  Future<void> _loadAll() async {
    if (_selectedId == null) return;
    setState(() => _loading = true);
    final supa = SupabaseService();
    final repo = MockRepository();
    final ptMatches =
        repo.points.where((p) => p.id == _selectedId).toList();
    _point = ptMatches.isEmpty ? null : ptMatches.first;
    _employees =
        repo.employees.where((e) => e.pointId == _selectedId).toList();

    if (!supa.isReady) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final pid = _selectedId!;
      final now = DateTime.now();
      final since30 = now.subtract(const Duration(days: 30));
      final empIds = _employees.map((e) => e.id).toList();

      // Attendance for this point
      try {
        final clk = await supa.client
            .from('point_terminal_clock_logs')
            .select('action, created_at')
            .eq('point_id', pid)
            .gte('created_at', since30.toIso8601String())
            .limit(5000);
        _clockIns30d = (clk as List)
            .where((r) => (r as Map)['action'] == 'clock_in')
            .length;
        _clockOuts30d = clk
            .where((r) => (r as Map)['action'] == 'clock_out')
            .length;
      } catch (_) {
        _clockIns30d = 0;
        _clockOuts30d = 0;
      }

      // Leaves for these employees (active + pending)
      if (empIds.isNotEmpty) {
        try {
          final lvs = await supa.client
              .from('employee_leave_requests')
              .select(
                  'id, employee_id, leave_type, start_date, end_date, days_count, status, late_status, employees(full_name, code)')
              .inFilter('employee_id', empIds)
              .order('start_date', ascending: false)
              .limit(500);
          final list = (lvs as List).cast<Map<String, dynamic>>();
          final todayIso = now.toIso8601String().substring(0, 10);
          _activeLeavesNow = list.where((l) {
            if (l['status'] != 'approved') return false;
            final s = l['start_date'] as String?;
            final e = l['end_date'] as String?;
            if (s == null || e == null) return false;
            return s.compareTo(todayIso) <= 0 && e.compareTo(todayIso) >= 0;
          }).length;
          _pendingLeaves =
              list.where((l) => l['status'] == 'pending').length;
          _latestLeaves = list.take(20).toList();
        } catch (e) {
          M7Log.error('LocAgg', 'leaves', error: e);
        }

        // Deductions
        try {
          final ded = await supa.client
              .from('employee_deductions')
              .select('id, status')
              .inFilter('employee_id', empIds);
          _activeDeductions = (ded as List)
              .where((d) => (d as Map)['status'] == 'active')
              .length;
        } catch (_) {
          _activeDeductions = 0;
        }

        // Expiring documents (within 60 days)
        try {
          final docs = await supa.client
              .from('employee_documents')
              .select('id, expiry_date')
              .inFilter('employee_id', empIds);
          _expiringDocs60d = (docs as List).where((d) {
            final s = (d as Map)['expiry_date'] as String?;
            if (s == null) return false;
            final dt = DateTime.tryParse(s);
            if (dt == null) return false;
            final daysLeft = dt.difference(now).inDays;
            return daysLeft >= 0 && daysLeft <= 60;
          }).length;
        } catch (_) {
          _expiringDocs60d = 0;
        }
      }

      // Rosters covering this point (via point linkage or site)
      try {
        final rost = await supa.client
            .from('weekly_rosters')
            .select(
                'id, week_start, status, supervisor_id, site_id, point_id, points(name), sites(name)')
            .eq('point_id', pid)
            .order('week_start', ascending: false)
            .limit(20);
        _rosters = (rost as List).cast<Map<String, dynamic>>();
      } catch (_) {
        _rosters = [];
      }
    } catch (e) {
      M7Log.error('LocAgg', 'loadAll', error: e);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? '📍 المُلَفّ الشامِل لِلمَوقِع' : '📍 Location 360°',
        actions: [
          if (_selectedId != null)
            M7AppBarAction(
              icon: Icons.refresh,
              tooltip: isAr ? 'تَحديث' : 'Refresh',
              onPressed: _loadAll,
            ),
          M7AppBarAction(
            icon: Icons.swap_horiz,
            tooltip: isAr ? 'تَغيير الموقع' : 'Change location',
            onPressed: _pickPoint,
          ),
        ],
      ),
      body: _selectedId == null
          ? _emptyPicker(isAr)
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _loadAll,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      _pointCard(isAr),
                      const SizedBox(height: 10),
                      _kpiGrid(isAr),
                      const SizedBox(height: 10),
                      _section(
                        isAr ? '👥 المُوَظَّفون' : '👥 Employees',
                        _employees.length,
                        _employeesList(isAr),
                      ),
                      _section(
                          isAr ? '🏖 الإجازات الأَخيرة' : '🏖 Recent leaves',
                          _latestLeaves.length,
                          _leavesList(isAr)),
                      _section(
                          isAr ? '📅 الجَداوِل الأُسبوعِيّة' : '📅 Rosters',
                          _rosters.length,
                          _rostersList(isAr)),
                    ],
                  ),
                ),
    );
  }

  Widget _emptyPicker(bool isAr) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.location_on, size: 80, color: AppColors.brand),
            const SizedBox(height: 16),
            Text(
              isAr ? 'اِختَر مَوقِعاً لعَرض مُلَفّه الشامِل' : 'Pick a location',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: _pickPoint,
              icon: const Icon(Icons.search),
              label: Text(isAr ? 'اِختِيار مَوقِع' : 'Choose location'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brand,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickPoint() async {
    final repo = MockRepository();
    final isAr = AppStrings.of(context).isAr;
    final search = TextEditingController();
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        var query = '';
        return StatefulBuilder(builder: (ctx, setSt) {
          final all = repo.points
              .where((p) =>
                  query.isEmpty ||
                  p.name.toLowerCase().contains(query.toLowerCase()) ||
                  p.code.toLowerCase().contains(query.toLowerCase()))
              .toList();
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.8,
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    width: 40,
                    height: 4,
                    color: Colors.grey.shade400,
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      controller: search,
                      autofocus: true,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: isAr ? 'بَحث…' : 'Search…',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      onChanged: (v) => setSt(() => query = v),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: all.length,
                      itemBuilder: (_, i) {
                        final p = all[i];
                        final empCount = repo.employees
                            .where((e) => e.pointId == p.id)
                            .length;
                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            backgroundColor: AppColors.brand.withOpacity(0.15),
                            child: const Icon(Icons.place,
                                color: AppColors.brand, size: 18),
                          ),
                          title: Text(p.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13)),
                          subtitle: Text(
                              '${p.code} · $empCount ${isAr ? "مُوَظَّف" : "emp."}',
                              style: const TextStyle(fontSize: 11)),
                          onTap: () => Navigator.pop(ctx, p.id),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
    if (picked != null) {
      setState(() => _selectedId = picked);
      _loadAll();
    }
  }

  Widget _pointCard(bool isAr) {
    final p = _point;
    if (p == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(isAr ? 'الموقِع غَير مَوجود' : 'Location not found'),
        ),
      );
    }
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: AppColors.brand.withOpacity(0.15),
                  child: const Icon(Icons.place,
                      color: AppColors.brand, size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 2),
                      Text(p.code,
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade700)),
                      if (p.fullAddress.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(p.fullAddress,
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade600)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _kpiGrid(bool isAr) {
    final activeEmps =
        _employees.where((e) => e.status == EntityStatus.active).length;
    final onVacation =
        _employees.where((e) => e.status == EntityStatus.vacation).length;
    final inactive =
        _employees.where((e) => e.status == EntityStatus.inactive).length;

    final kpis = <_LocKpi>[
      _LocKpi(isAr ? 'إجمالي' : 'Total', '${_employees.length}',
          Icons.people, AppColors.brand),
      _LocKpi(isAr ? 'نَشِطون' : 'Active', '$activeEmps',
          Icons.check_circle, AppColors.success),
      _LocKpi(isAr ? 'في إجازة' : 'On leave', '$onVacation',
          Icons.beach_access, AppColors.warning),
      _LocKpi(isAr ? 'مُعَطَّلون' : 'Inactive', '$inactive',
          Icons.do_disturb_alt, AppColors.danger),
      _LocKpi(isAr ? 'دُخول 30ي' : 'In 30d', '$_clockIns30d',
          Icons.login, Colors.indigo),
      _LocKpi(isAr ? 'خُروج 30ي' : 'Out 30d', '$_clockOuts30d',
          Icons.logout, Colors.indigo),
      _LocKpi(isAr ? 'إجازات اليَوم' : 'Out today',
          '$_activeLeavesNow', Icons.event_busy, AppColors.warning),
      _LocKpi(isAr ? 'إنذارات' : 'Warnings', '$_activeDeductions',
          Icons.warning, AppColors.danger),
      _LocKpi(isAr ? 'وَثائق ≤60ي' : 'Docs ≤60d',
          '$_expiringDocs60d', Icons.description, Colors.purple),
      _LocKpi(isAr ? 'إجازات مُعَلَّقة' : 'Leaves Pen.',
          '$_pendingLeaves', Icons.pending, Colors.teal),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: kpis.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 0.9,
      ),
      itemBuilder: (_, i) {
        final k = kpis[i];
        return Container(
          decoration: BoxDecoration(
            color: k.color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: k.color.withOpacity(0.3)),
          ),
          padding: const EdgeInsets.all(4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(k.icon, color: k.color, size: 16),
              const SizedBox(height: 2),
              Text(k.value,
                  style: TextStyle(
                      color: k.color,
                      fontSize: 12,
                      fontWeight: FontWeight.w900),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              Text(k.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 8,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        );
      },
    );
  }

  Widget _section(String title, int count, Widget body) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        initiallyExpanded: count > 0 && count <= 25,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        title: Row(
          children: [
            Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 13))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.brand.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('$count',
                  style: const TextStyle(
                      color: AppColors.brand,
                      fontWeight: FontWeight.w900,
                      fontSize: 11)),
            ),
          ],
        ),
        children: [
          if (count == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('—',
                  style:
                      TextStyle(color: Colors.grey.shade500, fontSize: 12)),
            )
          else
            body,
        ],
      ),
    );
  }

  Widget _employeesList(bool isAr) {
    return Column(
      children: _employees.map((e) {
        Color c = Colors.grey;
        String label = '';
        switch (e.status) {
          case EntityStatus.active:
            c = AppColors.success;
            label = isAr ? 'نَشِط' : 'Active';
            break;
          case EntityStatus.vacation:
            c = AppColors.warning;
            label = isAr ? 'في إجازة' : 'Vacation';
            break;
          case EntityStatus.inactive:
            c = AppColors.danger;
            label = isAr ? 'مُعَطَّل' : 'Inactive';
            break;
          case EntityStatus.maintenance:
            c = Colors.orange;
            label = '—';
            break;
        }
        return ListTile(
          dense: true,
          leading: CircleAvatar(
            radius: 14,
            backgroundColor: c.withOpacity(0.15),
            child: Text(e.fullName.isNotEmpty ? e.fullName[0] : '?',
                style: TextStyle(
                    color: c, fontWeight: FontWeight.w900, fontSize: 11)),
          ),
          title: Text(e.fullName,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          subtitle: Text('${e.code} · ${e.jobTitle}',
              style: const TextStyle(fontSize: 11)),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: c.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(label,
                style: TextStyle(
                    color: c, fontSize: 9, fontWeight: FontWeight.w900)),
          ),
          onTap: () {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => EmployeeAggregatedReport(employeeId: e.id),
            ));
          },
        );
      }).toList(),
    );
  }

  Widget _leavesList(bool isAr) {
    return Column(
      children: _latestLeaves.take(15).map((l) {
        final st = (l['status'] as String?) ?? '';
        Color c = Colors.grey;
        if (st == 'approved') c = AppColors.success;
        if (st == 'pending') c = AppColors.warning;
        if (st == 'rejected') c = AppColors.danger;
        final emp = l['employees'];
        final name = emp is Map ? (emp['full_name'] as String?) ?? '?' : '?';
        return ListTile(
          dense: true,
          leading: Icon(Icons.beach_access, color: c, size: 18),
          title: Text(name,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          subtitle: Text(
              '${l['leave_type']} · ${l['start_date']} → ${l['end_date']}',
              style: const TextStyle(fontSize: 11)),
          trailing: Text(st,
              style: TextStyle(
                  color: c, fontSize: 10, fontWeight: FontWeight.w800)),
        );
      }).toList(),
    );
  }

  Widget _rostersList(bool isAr) {
    return Column(
      children: _rosters.take(15).map((r) {
        final st = (r['status'] as String?) ?? '';
        Color c = Colors.grey;
        if (st == 'approved') c = AppColors.success;
        if (st == 'pending' || st == 'submitted') c = AppColors.warning;
        if (st == 'rejected') c = AppColors.danger;
        return ListTile(
          dense: true,
          leading: Icon(Icons.calendar_view_week, color: c, size: 18),
          title: Text('${isAr ? "أُسبوع" : "Week"} ${r['week_start']}',
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          subtitle: Text(st, style: const TextStyle(fontSize: 11)),
        );
      }).toList(),
    );
  }
}

class _LocKpi {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  _LocKpi(this.label, this.value, this.icon, this.color);
}
