import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../models/models.dart';
import '../../../repositories/mock_repository.dart';
import 'hr_palette.dart';

/// ⭐ تقييمات الموظفين - قائمة كاملة بكل التقييمات + بحث/فلترة
class HrEvaluationsScreen extends StatefulWidget {
  const HrEvaluationsScreen({super.key});

  @override
  State<HrEvaluationsScreen> createState() => _HrEvaluationsScreenState();
}

class _HrEvaluationsScreenState extends State<HrEvaluationsScreen> {
  final TextEditingController _search = TextEditingController();
  int? _ratingFilter;

  @override
  void initState() {
    super.initState();
    MockRepository().addListener(_onChange);
  }

  @override
  void dispose() {
    MockRepository().removeListener(_onChange);
    _search.dispose();
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

    var evals = repo.employeeEvaluations.toList();
    if (cid != null) {
      evals = evals.where((e) {
        final emp = repo.employeeById(e.employeeId);
        return emp?.countryId == cid;
      }).toList();
    }

    final q = _search.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      evals = evals.where((e) {
        final emp = repo.employeeById(e.employeeId);
        return (emp?.fullName.toLowerCase().contains(q) ?? false) ||
            (emp?.code.toLowerCase().contains(q) ?? false);
      }).toList();
    }
    if (_ratingFilter != null) {
      evals = evals.where((e) => e.rating == _ratingFilter).toList();
    }
    evals.sort((a, b) => b.date.compareTo(a.date));

    final avg = evals.isEmpty
        ? 0.0
        : evals.fold<double>(0, (a, e) => a + e.rating) / evals.length;

    return Scaffold(
      backgroundColor: HrPalette.bg,
      body: Column(children: [
        // KPIs
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: Row(children: [
            _Kpi(
                label: s.isAr ? 'عدد التقييمات' : 'Evaluations',
                value: evals.length.toString(),
                icon: Icons.rate_review_outlined,
                color: HrPalette.primary),
            const SizedBox(width: 8),
            _Kpi(
                label: s.isAr ? 'المتوسط' : 'Avg',
                value: avg.toStringAsFixed(1),
                icon: Icons.star,
                color: HrPalette.expiring),
          ]),
        ),
        // Search
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: s.isAr ? 'بحث (اسم/كود)' : 'Search (name/code)',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            _Filter(s.isAr ? 'الكل' : 'All', _ratingFilter == null,
                () => setState(() => _ratingFilter = null)),
            for (int r = 5; r >= 1; r--) ...[
              const SizedBox(width: 6),
              _Filter('★ $r', _ratingFilter == r,
                  () => setState(() => _ratingFilter = r)),
            ],
          ]),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: evals.isEmpty
              ? Center(
                  child: Text(
                      s.isAr
                          ? 'لا توجد تقييمات'
                          : 'No evaluations',
                      style: const TextStyle(color: Colors.black54)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                  itemCount: evals.length,
                  itemBuilder: (_, i) => _EvalCard(eval: evals[i], isAr: s.isAr),
                ),
        ),
      ]),
    );
  }
}

class _Kpi extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _Kpi(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color});
  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.30)),
          ),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          color: Colors.black54, fontSize: 11)),
                  Text(value,
                      style: TextStyle(
                          color: color,
                          fontSize: 18,
                          fontWeight: FontWeight.w900)),
                ],
              ),
            ),
          ]),
        ),
      );
}

class _Filter extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Filter(this.label, this.selected, this.onTap);
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? HrPalette.primary : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border:
                Border.all(color: HrPalette.primary.withOpacity(0.5)),
          ),
          child: Text(label,
              style: TextStyle(
                  color: selected ? Colors.white : HrPalette.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w800)),
        ),
      );
}

class _EvalCard extends StatelessWidget {
  final EmployeeEvaluation eval;
  final bool isAr;
  const _EvalCard({required this.eval, required this.isAr});

  Color _ratingColor(int r) {
    if (r >= 4) return HrPalette.valid;
    if (r >= 3) return HrPalette.expiring;
    return HrPalette.expired;
  }

  @override
  Widget build(BuildContext context) {
    final repo = MockRepository();
    final emp = repo.employeeById(eval.employeeId);
    final ratingColor = _ratingColor(eval.rating);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HrPalette.primary.withOpacity(0.18)),
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: HrPalette.primary.withOpacity(0.15),
          child: Text(emp?.initials ?? '?',
              style: const TextStyle(
                  color: HrPalette.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w900)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(emp?.fullName ?? (isAr ? 'غير معروف' : 'Unknown'),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(
                  '${emp?.code ?? '—'}  •  ${eval.date.year}-${eval.date.month.toString().padLeft(2, '0')}-${eval.date.day.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                      color: Colors.black54, fontSize: 11)),
              if (eval.notes != null && eval.notes!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(eval.notes!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 11,
                        fontStyle: FontStyle.italic)),
              ],
            ],
          ),
        ),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: ratingColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.star, color: ratingColor, size: 14),
            const SizedBox(width: 3),
            Text(eval.rating.toString(),
                style: TextStyle(
                    color: ratingColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w900)),
          ]),
        ),
      ]),
    );
  }
}
