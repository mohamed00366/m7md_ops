import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/excel_exporter.dart';
import '../../core/theme/app_colors.dart';
import '../../models/models.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';

/// 📊 تَقرير المذكّرات اليوميّة
///
/// يَدعم:
/// - الموظّف لِنَفسه (يَرى مذكّراته فقط)
/// - المشرف/Operation (يَرون فريقهم) — حَسب الصلاحيّة
/// - فلاتر نطاق تواريخ + موظّف + نقطة
/// - KPIs + جدولان (تفصيليّ وتجميعيّ حسب النقطة)
/// - تَصدير Excel (3 صفحات)
class DailyMemoReportScreen extends StatefulWidget {
  const DailyMemoReportScreen({super.key});

  @override
  State<DailyMemoReportScreen> createState() => _DailyMemoReportScreenState();
}

class _DailyMemoReportScreenState extends State<DailyMemoReportScreen> {
  late DateTime _from;
  late DateTime _to;
  String? _filterEmployeeId; // إذا null والمستخدم له viewTeam → يَرى الكلّ
  String? _filterPointId;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = DateTime(now.year, now.month, now.day);
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

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 7)),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (picked != null) {
      setState(() {
        _from = DateTime(picked.start.year, picked.start.month, picked.start.day);
        _to = DateTime(picked.end.year, picked.end.month, picked.end.day);
      });
    }
  }

  String _fmt(DateTime d) =>
      '${d.day}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// السُطور الكاملة بَعد الفلترة (موظّف + نطاق تاريخ + نقطة).
  List<_FlatRow> _flatRows() {
    final repo = MockRepository();
    final result = <_FlatRow>[];
    for (final m in repo.employeeDailyMemos) {
      if (m.date.isBefore(_from)) continue;
      final endOfTo = DateTime(_to.year, _to.month, _to.day, 23, 59, 59);
      if (m.date.isAfter(endOfTo)) continue;
      if (_filterEmployeeId != null && m.employeeId != _filterEmployeeId) {
        continue;
      }
      for (final e in m.entries) {
        if (_filterPointId != null && e.pointId != _filterPointId) continue;
        result.add(_FlatRow(memo: m, entry: e));
      }
    }
    result.sort((a, b) {
      final byDate = b.memo.date.compareTo(a.memo.date);
      if (byDate != 0) return byDate;
      return a.entry.startTime.compareTo(b.entry.startTime);
    });
    return result;
  }

  Future<void> _exportExcel(List<_FlatRow> rows, bool isAr) async {
    final repo = MockRepository();

    // Sheet 1: التفاصيل
    final detailHeaders = isAr
        ? const [
            'التاريخ',
            'الموظّف',
            'الرمز',
            'النقطة',
            'بداية',
            'نهاية',
            'ساعات',
            'ملاحظة'
          ]
        : const [
            'Date',
            'Employee',
            'Code',
            'Point',
            'Start',
            'End',
            'Hours',
            'Notes'
          ];
    final detailRows = rows.map<List<dynamic>>((r) {
      final emp = repo.employeeById(r.memo.employeeId);
      final point = repo.pointById(r.entry.pointId);
      return [
        _fmt(r.memo.date),
        emp?.fullName ?? '',
        emp?.code ?? '',
        point?.name ?? '',
        r.entry.startTime,
        r.entry.endTime,
        r.entry.hours.toStringAsFixed(2),
        r.entry.notes ?? '',
      ];
    }).toList();

    // Sheet 2: تجميع حسب الموظّف
    final byEmp = <String, double>{};
    final byEmpEntries = <String, int>{};
    for (final r in rows) {
      byEmp[r.memo.employeeId] =
          (byEmp[r.memo.employeeId] ?? 0) + r.entry.hours;
      byEmpEntries[r.memo.employeeId] =
          (byEmpEntries[r.memo.employeeId] ?? 0) + 1;
    }
    final empHeaders = isAr
        ? const ['الموظّف', 'الرمز', 'سُطور', 'مَجموع الساعات']
        : const ['Employee', 'Code', 'Entries', 'Total Hours'];
    final empRows = byEmp.entries.map<List<dynamic>>((e) {
      final emp = repo.employeeById(e.key);
      return [
        emp?.fullName ?? '',
        emp?.code ?? '',
        byEmpEntries[e.key] ?? 0,
        e.value.toStringAsFixed(2),
      ];
    }).toList();

    // Sheet 3: تجميع حسب النقطة
    final byPoint = <String, double>{};
    final byPointEntries = <String, int>{};
    for (final r in rows) {
      byPoint[r.entry.pointId] =
          (byPoint[r.entry.pointId] ?? 0) + r.entry.hours;
      byPointEntries[r.entry.pointId] =
          (byPointEntries[r.entry.pointId] ?? 0) + 1;
    }
    final pointHeaders = isAr
        ? const ['النقطة', 'سُطور', 'مَجموع الساعات']
        : const ['Point', 'Entries', 'Total Hours'];
    final pointRows = byPoint.entries.map<List<dynamic>>((e) {
      final p = repo.pointById(e.key);
      return [
        p?.name ?? '',
        byPointEntries[e.key] ?? 0,
        e.value.toStringAsFixed(2),
      ];
    }).toList();

    final ok = await ExcelExporter.export(
      fileName:
          'daily_memo_report_${DateTime.now().millisecondsSinceEpoch}.xlsx',
      sheets: [
        ExcelSheet(
            name: isAr ? 'التفاصيل' : 'Details',
            headers: detailHeaders,
            rows: detailRows),
        ExcelSheet(
            name: isAr ? 'حسب الموظّف' : 'By Employee',
            headers: empHeaders,
            rows: empRows),
        ExcelSheet(
            name: isAr ? 'حسب النقطة' : 'By Point',
            headers: pointHeaders,
            rows: pointRows),
      ],
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: ok ? AppColors.success : AppColors.danger,
      content: Text(ok
          ? (isAr ? '✅ تَمّ التصدير' : '✅ Exported')
          : (isAr ? '❌ فَشِل التصدير' : '❌ Export failed')),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final auth = context.watch<AuthProvider>();
    final repo = MockRepository();

    final canViewReport = auth.isSuperAdmin ||
        auth.permissions.contains(P.dailyMemoReportView);
    if (!canViewReport) {
      return Scaffold(
        appBar: AppBar(
          title: Text(isAr ? 'تقرير المذكّرات' : 'Daily Memo Report'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              isAr
                  ? 'لا تَملك صلاحية الوصول إلى هذا التقرير.'
                  : 'You do not have permission to view this report.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final canSeeTeam = auth.isSuperAdmin ||
        auth.permissions.contains(P.dailyMemoViewTeam);
    final canExport = auth.isSuperAdmin ||
        auth.permissions.contains(P.dailyMemoReportExport);

    // إن لم يَكن له viewTeam، فقط يَرى مذكّراته فقط:
    if (!canSeeTeam) {
      _filterEmployeeId = auth.currentUser?.employeeId;
    }

    final rows = _flatRows();
    final totalHours = rows.fold<double>(0, (a, r) => a + r.entry.hours);
    final uniqueEmployees =
        rows.map((r) => r.memo.employeeId).toSet().length;
    final uniqueDays = rows.map((r) => r.memo.date.toIso8601String()).toSet().length;
    final uniquePoints = rows.map((r) => r.entry.pointId).toSet().length;

    final allEmployees = canSeeTeam
        ? (auth.filterByCountry(repo.employees, (e) => e.countryId)..sort(
            (a, b) => a.fullName.compareTo(b.fullName),
          ))
        : <Employee>[];
    final allPoints =
        auth.filterByCountry(repo.points, (p) => p.countryId)..sort(
            (a, b) => a.name.compareTo(b.name),
          );

    return Scaffold(
      appBar: AppBar(
        title: Text(isAr ? 'تقرير المذكّرات' : 'Daily Memo Report'),
        actions: [
          if (canExport)
            IconButton(
              tooltip: 'Excel',
              icon: const Icon(Icons.table_chart_outlined),
              onPressed: () => _exportExcel(rows, isAr),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // ===== فلاتر =====
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Column(
              children: [
                InkWell(
                  onTap: _pickRange,
                  child: Row(
                    children: [
                      const Icon(Icons.date_range, color: AppColors.brand),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${_fmt(_from)} → ${_fmt(_to)}',
                          style:
                              const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const Icon(Icons.edit, size: 16),
                    ],
                  ),
                ),
                const Divider(height: 14),
                if (canSeeTeam)
                  DropdownButtonFormField<String?>(
                    value: _filterEmployeeId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: isAr ? 'موظّف' : 'Employee',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.person),
                      isDense: true,
                    ),
                    items: [
                      DropdownMenuItem(
                        value: null,
                        child: Text(isAr ? 'كلّ الموظّفين' : 'All employees'),
                      ),
                      ...allEmployees.map((e) => DropdownMenuItem(
                            value: e.id,
                            child: Text('${e.fullName} (${e.code})'),
                          )),
                    ],
                    onChanged: (v) => setState(() => _filterEmployeeId = v),
                  ),
                if (canSeeTeam) const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  value: _filterPointId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: isAr ? 'نقطة' : 'Point',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.place),
                    isDense: true,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: null,
                      child: Text(isAr ? 'كلّ النقاط' : 'All points'),
                    ),
                    ...allPoints.map((p) => DropdownMenuItem(
                          value: p.id,
                          child: Text(p.name),
                        )),
                  ],
                  onChanged: (v) => setState(() => _filterPointId = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ===== KPIs =====
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Kpi(
                  color: AppColors.success,
                  icon: Icons.schedule,
                  label: isAr ? 'مَجموع الساعات' : 'Total Hours',
                  value: totalHours.toStringAsFixed(1)),
              _Kpi(
                  color: AppColors.brand,
                  icon: Icons.event,
                  label: isAr ? 'أيّام' : 'Days',
                  value: '$uniqueDays'),
              if (canSeeTeam)
                _Kpi(
                    color: AppColors.info,
                    icon: Icons.person,
                    label: isAr ? 'موظّفون' : 'Employees',
                    value: '$uniqueEmployees'),
              _Kpi(
                  color: AppColors.purple,
                  icon: Icons.place,
                  label: isAr ? 'نقاط' : 'Points',
                  value: '$uniquePoints'),
              _Kpi(
                  color: AppColors.warning,
                  icon: Icons.list,
                  label: isAr ? 'سُطور' : 'Entries',
                  value: '${rows.length}'),
            ],
          ),
          const SizedBox(height: 14),

          // ===== الجدول التفصيليّ =====
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isAr ? 'التفاصيل' : 'Details',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                if (rows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 30),
                    child: Center(
                      child: Text(
                        isAr ? 'لا بيانات لهذه الفترة' : 'No data',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                else
                  ...rows.take(50).map((r) {
                    final emp = repo.employeeById(r.memo.employeeId);
                    final point = repo.pointById(r.entry.pointId);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.bgLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.brand,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _fmt(r.memo.date).substring(0, 5),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                if (canSeeTeam)
                                  Text(emp?.fullName ?? '—',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800)),
                                Text(point?.name ?? "—",
                                    style: const TextStyle(fontSize: 11)),
                                Text(
                                  '${r.entry.startTime} → ${r.entry.endTime}',
                                  style: const TextStyle(
                                      fontSize: 10, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color:
                                  AppColors.success.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${r.entry.hours.toStringAsFixed(1)}h',
                              style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.success),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                if (rows.length > 50)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Center(
                      child: Text(
                        isAr
                            ? '… والباقي (${rows.length - 50} سطر) في ملفّ Excel'
                            : '... and ${rows.length - 50} more in Excel',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.grey),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ===== تجميع حسب النقطة =====
          if (rows.isNotEmpty)
            _PointSummary(rows: rows, isAr: isAr),
        ],
      ),
    );
  }
}

class _FlatRow {
  final EmployeeDailyMemo memo;
  final EmployeeDailyMemoEntry entry;
  _FlatRow({required this.memo, required this.entry});
}

class _PointSummary extends StatelessWidget {
  final List<_FlatRow> rows;
  final bool isAr;
  const _PointSummary({required this.rows, required this.isAr});

  @override
  Widget build(BuildContext context) {
    final repo = MockRepository();
    final byPoint = <String, double>{};
    for (final r in rows) {
      byPoint[r.entry.pointId] =
          (byPoint[r.entry.pointId] ?? 0) + r.entry.hours;
    }
    final entries = byPoint.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxHours =
        entries.isEmpty ? 1.0 : entries.first.value;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(isAr ? 'حسب النقطة' : 'By Point',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          ...entries.map((e) {
            final p = repo.pointById(e.key);
            final pct = (e.value / maxHours).clamp(0.0, 1.0);
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.bgLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(p?.name ?? '—',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800)),
                      ),
                      Text(
                        '${e.value.toStringAsFixed(1)} ${isAr ? "ساعة" : "h"}',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: AppColors.brand),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 6,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: const AlwaysStoppedAnimation(
                          AppColors.brand),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  const _Kpi({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(icon, color: color, size: 14),
            ),
            const SizedBox(height: 6),
            Text(value,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w900)),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
