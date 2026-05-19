import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../models/models.dart';
import '../../../repositories/mock_repository.dart';
import 'hr_palette.dart';

/// 🆕 شاشة الالتحاق - الموظفون الجدد + خطوات الإعداد
/// تعرض الموظفين الذين انضموا في آخر 90 يوماً مع نسبة استكمال البيانات
class HrOnboardingScreen extends StatefulWidget {
  const HrOnboardingScreen({super.key});

  @override
  State<HrOnboardingScreen> createState() => _HrOnboardingScreenState();
}

class _HrOnboardingScreenState extends State<HrOnboardingScreen> {
  int _windowDays = 90;

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

  /// خطوات الالتحاق + هل هي مكتملة لكل موظف
  List<_Step> _stepsFor(Employee e) => [
        _Step('الجواز', 'Passport',
            e.passportNumber.isNotEmpty && e.passportExpiry != null),
        _Step('التأشيرة', 'Visa', e.visaTypeId != null),
        _Step('عقد العمل', 'Contract', e.workLetterFileId != null),
        _Step('الراتب', 'Salary', e.basicSalary > 0),
        _Step('IBAN', 'IBAN', e.iban.isNotEmpty),
        _Step('القسم', 'Dept', e.departmentId != null),
        _Step('الوظيفة', 'Job', e.jobTitleId != null),
        _Step('الجوال', 'Mobile', e.mobile.isNotEmpty),
      ];

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final cid = context.watch<AuthProvider>().selectedCountryId;

    final cutoff = DateTime.now().subtract(Duration(days: _windowDays));
    var newcomers = repo.employees
        .where((e) =>
            e.joiningDate != null && e.joiningDate!.isAfter(cutoff))
        .toList();
    if (cid != null) {
      newcomers = newcomers.where((e) => e.countryId == cid).toList();
    }
    newcomers.sort((a, b) => b.joiningDate!.compareTo(a.joiningDate!));

    int totalComplete = 0;
    int totalSteps = 0;
    for (final e in newcomers) {
      final steps = _stepsFor(e);
      totalSteps += steps.length;
      totalComplete += steps.where((x) => x.done).length;
    }
    final overallPct = totalSteps == 0 ? 0 : (totalComplete * 100 ~/ totalSteps);

    return Scaffold(
      backgroundColor: HrPalette.bg,
      body: Column(children: [
        // KPI bar
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: HrPalette.primary.withOpacity(0.25)),
            ),
            child: Row(children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                    color: HrPalette.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.person_add_alt_1,
                    color: HrPalette.primary, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        s.isAr
                            ? 'وصلوا في آخر $_windowDays يوماً'
                            : 'Joined in last $_windowDays d',
                        style: const TextStyle(
                            color: Colors.black54, fontSize: 11)),
                    const SizedBox(height: 2),
                    Text(newcomers.length.toString(),
                        style: const TextStyle(
                            color: HrPalette.primary,
                            fontSize: 22,
                            fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
              _ProgressRing(percent: overallPct),
            ]),
          ),
        ),
        // Window selector
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final d in [30, 60, 90, 180, 365])
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: ChoiceChip(
                    label: Text(s.isAr ? '$d يوم' : '${d}d'),
                    selected: _windowDays == d,
                    selectedColor: HrPalette.primary.withOpacity(0.18),
                    onSelected: (_) => setState(() => _windowDays = d),
                  ),
                ),
            ]),
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: newcomers.isEmpty
              ? Center(
                  child: Text(
                      s.isAr ? 'لا يوجد موظفون جدد' : 'No newcomers',
                      style: const TextStyle(color: Colors.black54)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                  itemCount: newcomers.length,
                  itemBuilder: (_, i) {
                    final e = newcomers[i];
                    final steps = _stepsFor(e);
                    final done = steps.where((x) => x.done).length;
                    final pct = (done * 100 ~/ steps.length);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: HrPalette.primary.withOpacity(0.18)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor:
                                  HrPalette.primary.withOpacity(0.15),
                              child: Text(e.initials,
                                  style: const TextStyle(
                                      color: HrPalette.primary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(e.fullName,
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800)),
                                  Text(
                                      '${e.code}  •  ${s.isAr ? "انضم" : "Joined"} ${_fmt(e.joiningDate!)}',
                                      style: const TextStyle(
                                          color: Colors.black54,
                                          fontSize: 11)),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: pct == 100
                                    ? HrPalette.valid.withOpacity(0.15)
                                    : HrPalette.expiring.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('$pct%',
                                  style: TextStyle(
                                      color: pct == 100
                                          ? HrPalette.valid
                                          : HrPalette.primaryDark,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900)),
                            ),
                          ]),
                          const SizedBox(height: 8),
                          // steps wrap
                          Wrap(spacing: 6, runSpacing: 6, children: [
                            for (final st in steps)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: st.done
                                      ? HrPalette.valid.withOpacity(0.12)
                                      : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                          st.done
                                              ? Icons.check_circle
                                              : Icons.radio_button_unchecked,
                                          size: 13,
                                          color: st.done
                                              ? HrPalette.valid
                                              : Colors.black38),
                                      const SizedBox(width: 4),
                                      Text(s.isAr ? st.ar : st.en,
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: st.done
                                                  ? HrPalette.valid
                                                  : Colors.black54,
                                              fontWeight: FontWeight.w700)),
                                    ]),
                              ),
                          ]),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class _Step {
  final String ar;
  final String en;
  final bool done;
  _Step(this.ar, this.en, this.done);
}

class _ProgressRing extends StatelessWidget {
  final int percent;
  const _ProgressRing({required this.percent});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 50,
            height: 50,
            child: CircularProgressIndicator(
              value: percent / 100,
              strokeWidth: 5,
              backgroundColor: HrPalette.primary.withOpacity(0.15),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(HrPalette.primary),
            ),
          ),
          Text('$percent%',
              style: const TextStyle(
                  color: HrPalette.primaryDark,
                  fontSize: 11,
                  fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}
