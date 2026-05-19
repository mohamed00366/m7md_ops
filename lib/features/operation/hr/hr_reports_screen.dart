import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/utils/currency.dart';
import '../../../models/enums.dart';
import '../../../repositories/mock_repository.dart';
import 'hr_palette.dart';

/// 📊 تقرير HR - إحصائيات شاملة عن الموظفين
class HrReportsScreen extends StatefulWidget {
  const HrReportsScreen({super.key});

  @override
  State<HrReportsScreen> createState() => _HrReportsScreenState();
}

class _HrReportsScreenState extends State<HrReportsScreen> {
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
    final cid = context.watch<AuthProvider>().selectedCountryId;

    var emps = repo.employees.toList();
    if (cid != null) emps = emps.where((e) => e.countryId == cid).toList();

    final active =
        emps.where((e) => e.status == EntityStatus.active).length;
    final inactive = emps.length - active;

    // by category
    final byCategory = <String, int>{};
    for (final e in emps) {
      byCategory[e.category] = (byCategory[e.category] ?? 0) + 1;
    }

    // by department
    final byDept = <String, int>{};
    for (final e in emps) {
      final d = repo.departmentById(e.departmentId);
      final key = d?.displayName(s.isAr) ?? (s.isAr ? 'بدون قسم' : 'No dept');
      byDept[key] = (byDept[key] ?? 0) + 1;
    }

    // by nationality
    final byNat = <String, int>{};
    for (final e in emps) {
      final n = repo.nationalityById(e.nationalityId);
      final key = n?.displayName(s.isAr) ??
          (e.nationality.isNotEmpty
              ? e.nationality
              : (s.isAr ? 'غير محدد' : 'Unknown'));
      byNat[key] = (byNat[key] ?? 0) + 1;
    }

    // payroll totals
    double basicSum = 0, overtimeSum = 0, othersSum = 0;
    for (final e in emps) {
      basicSum += e.basicSalary;
      overtimeSum += e.overtime;
      othersSum += e.others;
    }
    final grossSum = basicSum + overtimeSum + othersSum;

    return Scaffold(
      backgroundColor: HrPalette.bg,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        children: [
          // Top KPI grid
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1.0,
            children: [
              _Kpi(emps.length.toString(),
                  s.isAr ? 'الموظفون' : 'Employees', Icons.people_alt_outlined,
                  HrPalette.primary),
              _Kpi(active.toString(), s.isAr ? 'نشط' : 'Active',
                  Icons.check_circle_outline, HrPalette.valid),
              _Kpi(inactive.toString(), s.isAr ? 'غير نشط' : 'Inactive',
                  Icons.cancel_outlined, HrPalette.expired),
              _Kpi(byDept.length.toString(),
                  s.isAr ? 'الأقسام' : 'Depts', Icons.account_tree_outlined,
                  HrPalette.primaryDark),
            ],
          ),

          const SizedBox(height: 12),
          _Section(s.isAr ? 'حسب التصنيف' : 'By Category'),
          _BreakdownCard(byCategory.map(
              (k, v) => MapEntry(_categoryLabel(k, s.isAr), v))),

          const SizedBox(height: 12),
          _Section(s.isAr ? 'حسب القسم' : 'By Department'),
          _BreakdownCard(byDept),

          const SizedBox(height: 12),
          _Section(s.isAr ? 'حسب الجنسية' : 'By Nationality'),
          _BreakdownCard(byNat),

          const SizedBox(height: 12),
          _Section(s.isAr ? 'الرواتب الإجمالية' : 'Total Payroll'),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: HrPalette.primary.withOpacity(0.25)),
            ),
            child: Column(children: [
              _PayRow(s.isAr ? 'الراتب الأساسي' : 'Basic',
                  AppCurrency.format(context, basicSum)),
              _PayRow(s.isAr ? 'الإضافي' : 'Overtime',
                  AppCurrency.format(context, overtimeSum)),
              _PayRow(s.isAr ? 'بدلات أخرى' : 'Others',
                  AppCurrency.format(context, othersSum)),
              const Divider(height: 18),
              _PayRow(
                s.isAr ? 'الإجمالي الشهري' : 'Monthly Gross',
                AppCurrency.format(context, grossSum),
                bold: true,
              ),
            ]),
          ),
        ],
      ),
    );
  }

  String _categoryLabel(String cat, bool isAr) {
    switch (cat) {
      case 'admin': return isAr ? 'إداري' : 'Admin';
      case 'operations': return isAr ? 'عمليات' : 'Operations';
      default: return isAr ? 'عامل' : 'Worker';
    }
  }
}

class _Kpi extends StatelessWidget {
  final String count;
  final String label;
  final IconData icon;
  final Color color;
  const _Kpi(this.count, this.label, this.icon, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.30)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(count,
                style: TextStyle(
                    color: color,
                    fontSize: 18,
                    fontWeight: FontWeight.w900)),
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.black54, fontSize: 10)),
          ],
        ),
      );
}

class _Section extends StatelessWidget {
  final String label;
  const _Section(this.label);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 4, right: 4),
        child: Text(label,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: HrPalette.primaryDark)),
      );
}

class _BreakdownCard extends StatelessWidget {
  final Map<String, int> data;
  const _BreakdownCard(this.data);
  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text('—', style: TextStyle(color: Colors.black38)),
      );
    }
    final total = data.values.fold<int>(0, (a, b) => a + b);
    final sorted = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (final entry in sorted)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(entry.key,
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                    ),
                    Text(
                        '${entry.value}  (${(entry.value * 100 / total).toStringAsFixed(0)}%)',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            color: HrPalette.primary)),
                  ]),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: entry.value / total,
                      minHeight: 5,
                      backgroundColor: HrPalette.primary.withOpacity(0.12),
                      valueColor: const AlwaysStoppedAnimation(
                          HrPalette.primary),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PayRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  const _PayRow(this.label, this.value, {this.bold = false});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: bold ? 13 : 12,
                    fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
                    color: bold ? HrPalette.primaryDark : Colors.black87)),
          ),
          Text(value,
              style: TextStyle(
                  fontSize: bold ? 14 : 12,
                  fontWeight: FontWeight.w900,
                  color: bold ? HrPalette.primaryDark : Colors.black87)),
        ]),
      );
}
