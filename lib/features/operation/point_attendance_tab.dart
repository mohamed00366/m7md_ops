// =============================================================================
// 📍 PointAttendanceTab — حُضور المُوَظَّفين عَبر Point Terminals (تاب)
// =============================================================================
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/point_attendance_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/employee_identity.dart';

class PointAttendanceTab extends StatefulWidget {
  final DateTime date;
  const PointAttendanceTab({super.key, required this.date});

  @override
  State<PointAttendanceTab> createState() => _PointAttendanceTabState();
}

class _PointAttendanceTabState extends State<PointAttendanceTab> {
  bool _loading = true;
  List<PointAttendanceRow> _rows = [];
  String _query = '';
  String? _pointFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PointAttendanceTab old) {
    super.didUpdateWidget(old);
    if (old.date != widget.date) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows =
        await PointAttendanceService.instance.forDate(widget.date);
    if (mounted) {
      setState(() {
        _rows = rows;
        _loading = false;
      });
    }
  }

  List<_PointRowDisplay> _filtered() {
    final repo = MockRepository();
    final empMap = {for (final e in repo.employees) e.id: e};
    final pointMap = {for (final p in repo.points) p.id: p};

    var list = _rows.map((r) {
      final emp = empMap[r.employeeId];
      final point = r.pointId == null ? null : pointMap[r.pointId];
      return _PointRowDisplay(row: r, employee: emp, point: point);
    }).where((d) => d.employee != null).toList();

    if (_pointFilter != null) {
      list = list.where((d) => d.row.pointId == _pointFilter).toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list
          .where((d) =>
              d.employee!.fullName.toLowerCase().contains(q) ||
              d.employee!.code.toLowerCase().contains(q))
          .toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final list = _filtered();
    final present = _rows.where((r) => r.isPresent).length;
    final completed = _rows.where((r) => r.isCompleted).length;
    final inProgress = _rows.where((r) => r.isPresent && !r.isCompleted).length;

    return RefreshIndicator(
      onRefresh: _load,
      child: Column(
        children: [
          // KPI
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: _Kpi(
                    label: isAr ? 'حاضِر' : 'Present',
                    value: present,
                    color: AppColors.success,
                    icon: Icons.check_circle,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _Kpi(
                    label: isAr ? 'يَعمَل الآن' : 'In progress',
                    value: inProgress,
                    color: AppColors.warning,
                    icon: Icons.work,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _Kpi(
                    label: isAr ? 'اكتَمَل' : 'Completed',
                    value: completed,
                    color: AppColors.brand,
                    icon: Icons.task_alt,
                  ),
                ),
              ],
            ),
          ),
          // البَحث + فِلتَر النُقطة
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: isAr ? 'بَحث: اسم أَو رَقم...' : 'Search...',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _pickPoint,
                  icon: const Icon(Icons.place, size: 16),
                  label: Text(
                    _pointFilter == null
                        ? (isAr ? 'النِقاط' : 'Points')
                        : (MockRepository()
                                .points
                                .where((p) => p.id == _pointFilter)
                                .firstOrNull
                                ?.name ??
                            ''),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          // القائِمة
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : list.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.event_busy,
                                size: 48, color: Colors.grey),
                            const SizedBox(height: 8),
                            Text(
                              isAr
                                  ? 'لا يُوجَد سِجِلّات في هذا اليَوم'
                                  : 'No records for this day',
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(8),
                        itemCount: list.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 6),
                        itemBuilder: (_, i) => _PointEmployeeCard(
                          display: list[i],
                          isAr: isAr,
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickPoint() async {
    final isAr = AppStrings.of(context).isAr;
    final points = MockRepository().points;
    final picked = await showModalBottomSheet<String?>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.location_on),
              title: Text(isAr ? 'كُلّ النِقاط' : 'All points'),
              trailing: _pointFilter == null
                  ? const Icon(Icons.check, color: AppColors.success)
                  : null,
              onTap: () => Navigator.pop(ctx, ''),
            ),
            const Divider(),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: points.length,
                itemBuilder: (_, i) {
                  final p = points[i];
                  return ListTile(
                    leading: const Icon(Icons.place),
                    title: Text(p.name),
                    trailing: _pointFilter == p.id
                        ? const Icon(Icons.check, color: AppColors.success)
                        : null,
                    onTap: () => Navigator.pop(ctx, p.id),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    setState(() => _pointFilter = picked.isEmpty ? null : picked);
  }
}

class _PointRowDisplay {
  final PointAttendanceRow row;
  final Employee? employee;
  final Point? point;
  _PointRowDisplay(
      {required this.row, required this.employee, required this.point});
}

class _Kpi extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final IconData icon;
  const _Kpi({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 4),
          Text(value.toString(),
              style: TextStyle(
                  fontWeight: FontWeight.w900, color: color, fontSize: 18)),
          Text(label,
              style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }
}

class _PointEmployeeCard extends StatelessWidget {
  final _PointRowDisplay display;
  final bool isAr;
  const _PointEmployeeCard({required this.display, required this.isAr});

  String _fmtTime(DateTime t) => DateFormat('HH:mm').format(t.toLocal());

  @override
  Widget build(BuildContext context) {
    final emp = display.employee!;
    final row = display.row;
    final dur = row.duration;
    final statusColor = row.isCompleted
        ? AppColors.brand
        : (row.isPresent ? AppColors.warning : Colors.grey);
    final statusLabel = row.isCompleted
        ? (isAr ? 'اكتَمَل' : 'Completed')
        : (row.isPresent ? (isAr ? 'يَعمَل الآن' : 'In progress') : '—');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            EmployeeAvatar(employee: emp, radius: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(emp.fullName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 13)),
                  Text(emp.code,
                      style: const TextStyle(
                          fontSize: 10, color: Colors.grey)),
                  if (display.point != null)
                    Text('📍 ${display.point!.name}',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.brand)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (row.clockIn != null) ...[
                        const Icon(Icons.login,
                            size: 14, color: AppColors.success),
                        const SizedBox(width: 4),
                        Text(_fmtTime(row.clockIn!),
                            style: const TextStyle(fontSize: 11)),
                      ],
                      if (row.clockOut != null) ...[
                        const SizedBox(width: 12),
                        const Icon(Icons.logout,
                            size: 14, color: AppColors.danger),
                        const SizedBox(width: 4),
                        Text(_fmtTime(row.clockOut!),
                            style: const TextStyle(fontSize: 11)),
                      ],
                      if (dur != null) ...[
                        const SizedBox(width: 12),
                        const Icon(Icons.timer, size: 14, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                            '${dur.inHours}h ${dur.inMinutes.remainder(60)}m',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                statusLabel,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: statusColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
