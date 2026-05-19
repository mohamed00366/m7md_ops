import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../models/evaluation_criterion.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/widgets.dart';

/// شاشة التقييم - تعرض التعليمات + قائمة الموظفين + التقييمات السابقة
/// زر "تقييم جديد" يفتح نموذج بـ 3 فئات × 3 معايير لكل موظف
class SupervisorEvaluations extends StatefulWidget {
  const SupervisorEvaluations({super.key});

  @override
  State<SupervisorEvaluations> createState() => _SupervisorEvaluationsState();
}

class _SupervisorEvaluationsState extends State<SupervisorEvaluations> {
  bool _instructionsExpanded = true;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final auth = context.watch<AuthProvider>();
    final empId = auth.currentUser?.employeeId;
    final pointId = auth.selectedSiteId;

    // 🆕 وضع Operation: يستطيع رؤية كل الموظفين تحت كل نقطة
    final canViewAll = auth.hasPermission('rosters.approve') ||
        auth.hasPermission('rosters.edit_approved') ||
        auth.isSuperAdmin;
    if (pointId == null && canViewAll) {
      return _OperationEvaluationsView(currentUserEmpId: empId);
    }

    if (pointId == null) {
      return EmptyState(
        icon: Icons.location_off,
        message: s.isAr
            ? 'لم يتم ربط حسابك بنقطة بعد. تواصل مع مدير العمليات.'
            : 'Your account is not assigned to a point yet. Contact Operations.',
      );
    }

    // 🆕 الموظفون من الروستر الفعلي لهذه النقطة (المعتمد أو الأحدث)
    // المنطق:
    //   1) ابحث عن أحدث روستر لهذه النقطة (أولوية للمعتمد ثم Submitted ثم Draft)
    //   2) خذ employee_ids من assignments
    //   3) اعرض هؤلاء الموظفين فقط
    final pointRosters = repo.rosters
        .where((r) => r.siteId == pointId)
        .toList()
      ..sort((a, b) {
        // الأولوية: approved > submitted > draft
        int p(WeeklyRoster x) {
          if (x.status == RosterStatus.approved) return 3;
          if (x.status == RosterStatus.submitted) return 2;
          if (x.status == RosterStatus.draft) return 1;
          return 0;
        }
        final cmp = p(b).compareTo(p(a));
        if (cmp != 0) return cmp;
        return b.weekStart.compareTo(a.weekStart);
      });

    final List<Employee> shownEmployees;
    if (pointRosters.isEmpty) {
      shownEmployees = []; // لا يوجد روستر بعد
    } else {
      final activeRoster = pointRosters.first;
      final empIds = activeRoster.assignments
          .map((a) => a.employeeId)
          .toSet();
      shownEmployees = repo.employees
          .where((e) => empIds.contains(e.id))
          .toList();
    }

    final myEvals = repo.employeeEvaluations
        .where((e) => e.evaluatedBy == empId)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // قسم التعليمات (قابل للطي)
          _InstructionsBanner(
            expanded: _instructionsExpanded,
            onToggle: () => setState(
                () => _instructionsExpanded = !_instructionsExpanded),
          ),
          const SizedBox(height: 14),

          // الموظفون
          Padding(
            padding:
                const EdgeInsets.only(bottom: 8, right: 4, left: 4),
            child: Row(
              children: [
                const Icon(Icons.people, size: 16, color: AppColors.brand),
                const SizedBox(width: 6),
                Text(
                  s.isAr
                      ? 'موظفو الروستر (${shownEmployees.length})'
                      : 'Roster Employees (${shownEmployees.length})',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          // 🆕 رسالة توضيحية إن لم يوجد روستر
          if (shownEmployees.isEmpty)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.warning.withOpacity(0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.info_outline,
                    color: AppColors.warning, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.isAr
                        ? 'لا يوجد روستر لهذه النقطة بعد. أنشئ روستراً وأضف موظفين أولاً ثم ارجع لتقييمهم.'
                        : 'No roster for this point yet. Create a roster and add employees first, then come back to evaluate.',
                    style: const TextStyle(
                        color: AppColors.warning,
                        fontSize: 12,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ]),
            ),
          ...shownEmployees.map((emp) {
            final evals =
                myEvals.where((e) => e.employeeId == emp.id).toList();
            final latest = evals.isEmpty ? null : evals.first;
            return _EmployeeEvalCard(
              employee: emp,
              latestEval: latest,
              evalCount: evals.length,
              onEvaluate: () => _openEvaluator(emp),
            );
          }),

          if (myEvals.isNotEmpty) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.only(bottom: 8, right: 4, left: 4),
              child: Row(
                children: [
                  const Icon(Icons.history,
                      size: 16, color: AppColors.brand),
                  const SizedBox(width: 6),
                  Text(s.pastEvaluations,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            ...myEvals.take(10).map((e) => _PastEvalCard(eval: e)),
          ],
        ],
      ),
    );
  }

  void _openEvaluator(Employee emp) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EvaluationFormSheet(employee: emp),
    );
  }
}

// ============================================================
// بانر التعليمات (قابل للطي)
// ============================================================
class _InstructionsBanner extends StatelessWidget {
  final bool expanded;
  final VoidCallback onToggle;
  const _InstructionsBanner({
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.info.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.info.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.menu_book,
                      color: AppColors.info, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.evaluationInstructions,
                            style: const TextStyle(
                                color: AppColors.info,
                                fontSize: 14,
                                fontWeight: FontWeight.w800)),
                        Text(s.scaleHint,
                            style: const TextStyle(
                                color: AppColors.info, fontSize: 11)),
                      ],
                    ),
                  ),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: AppColors.info,
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(s.evaluationInstructionsBody,
                      style: const TextStyle(fontSize: 12, height: 1.5)),
                  const SizedBox(height: 12),
                  ..._categoriesWithCriteria(s)
                      .map((cat) => _CategoryHelp(
                            title: cat.title,
                            color: cat.color,
                            icon: cat.icon,
                            items: cat.items,
                          )),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CategoryHelp extends StatelessWidget {
  final String title;
  final Color color;
  final IconData icon;
  final List<_Criterion> items;
  const _CategoryHelp({
    required this.title,
    required this.color,
    required this.icon,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 6),
              Text(title,
                  style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 4),
          ...items.map((c) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(' • ',
                        style: TextStyle(color: color, fontSize: 10)),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(
                              fontSize: 11,
                              height: 1.4,
                              color: Colors.black87),
                          children: [
                            TextSpan(
                                text: '${c.label}: ',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            TextSpan(text: c.description),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

// ============================================================
// كارد كل موظف
// ============================================================
class _EmployeeEvalCard extends StatelessWidget {
  final Employee employee;
  final EmployeeEvaluation? latestEval;
  final int evalCount;
  final VoidCallback onEvaluate;
  const _EmployeeEvalCard({
    required this.employee,
    required this.latestEval,
    required this.evalCount,
    required this.onEvaluate,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          AppAvatar(initials: employee.initials, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(employee.fullName,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800)),
                Text(
                  '${employee.code}${employee.jobTitle.isNotEmpty ? " • ${employee.jobTitle}" : ""}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (latestEval != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      ...List.generate(
                          5,
                          (i) => Icon(
                                i < latestEval!.rating
                                    ? Icons.star
                                    : Icons.star_border,
                                size: 14,
                                color: AppColors.warning,
                              )),
                      const SizedBox(width: 6),
                      Text('($evalCount)',
                          style:
                              const TextStyle(fontSize: 11)),
                    ],
                  ),
                ],
              ],
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warning,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onPressed: onEvaluate,
            icon: const Icon(Icons.star, size: 14),
            label: Text(
              s.rate,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _PastEvalCard extends StatelessWidget {
  final EmployeeEvaluation eval;
  const _PastEvalCard({required this.eval});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final emp = repo.employeeById(eval.employeeId);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text('${eval.rating}',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.warning)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(emp?.fullName ?? '-',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                Text(
                  '${eval.date.day}/${eval.date.month}/${eval.date.year}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (eval.subRatings.isNotEmpty)
                  Text(
                    '${eval.subRatings.length} ${s.isAr ? "معايير" : "criteria"}',
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.brand),
                  ),
              ],
            ),
          ),
          Row(
            children: List.generate(
                5,
                (i) => Icon(
                      i < eval.rating ? Icons.star : Icons.star_border,
                      size: 12,
                      color: AppColors.warning,
                    )),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// نموذج التقييم - 3 فئات × 3 معايير = 9 ratings
// ============================================================
class EvaluationFormSheet extends StatefulWidget {
  final Employee employee;
  const EvaluationFormSheet({super.key, required this.employee});

  @override
  State<EvaluationFormSheet> createState() => _EvaluationFormSheetState();
}

class _EvaluationFormSheetState extends State<EvaluationFormSheet> {
  final Map<String, int> _ratings = {};
  final _notes = TextEditingController();

  double get _average {
    if (_ratings.isEmpty) return 0;
    final sum = _ratings.values.fold<int>(0, (a, b) => a + b);
    return sum / _ratings.length;
  }

  bool get _allRated {
    final allKeys = _allCriteriaKeys();
    return allKeys.every((k) => _ratings.containsKey(k));
  }

  List<String> _allCriteriaKeys() {
    final s = AppStrings.of(context);
    return _categoriesWithCriteria(s)
        .expand((cat) => cat.items.map((c) => c.key))
        .toList();
  }

  void _save() {
    final s = AppStrings.of(context);
    if (!_allRated) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.rateAllCriteria)),
      );
      return;
    }
    final auth = context.read<AuthProvider>();
    final repo = MockRepository();
    final overallRating = _average.round();

    repo.addEmployeeEvaluation(EmployeeEvaluation(
      id: repo.generateId(),
      employeeId: widget.employee.id,
      evaluatedBy: auth.currentUser?.employeeId ?? '',
      siteId: auth.selectedSiteId,
      rating: overallRating,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      subRatings: Map.from(_ratings),
    ));

    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s.success)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final categories = _categoriesWithCriteria(s);

    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // مقبض السحب
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).dividerColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // العنوان مع الموظف
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                AppAvatar(
                    initials: widget.employee.initials,
                    color: AppColors.warning,
                    radius: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.newEvaluation,
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.warning)),
                      Text(widget.employee.fullName,
                          style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800)),
                      Text(widget.employee.code,
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.brand)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      Text(_average.toStringAsFixed(1),
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: AppColors.warning)),
                      Text(s.overallRating,
                          style: const TextStyle(
                              fontSize: 9,
                              color: AppColors.warning)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // الفئات والمعايير
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                ...categories.map((cat) => _CategorySection(
                      title: cat.title,
                      color: cat.color,
                      icon: cat.icon,
                      criteria: cat.items,
                      ratings: _ratings,
                      onRate: (key, rating) {
                        setState(() => _ratings[key] = rating);
                      },
                    )),
                const SizedBox(height: 8),
                TextField(
                  controller: _notes,
                  maxLines: 3,
                  decoration: InputDecoration(labelText: s.notes),
                ),
              ],
            ),
          ),
          // أزرار الحفظ
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              border: Border(
                top: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(s.cancel),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.warning),
                    onPressed: _save,
                    icon: const Icon(Icons.save, size: 16),
                    label: Text(_allRated
                        ? s.save
                        : '${s.save} (${_ratings.length}/${_allCriteriaKeys().length})'),
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

class _CategorySection extends StatelessWidget {
  final String title;
  final Color color;
  final IconData icon;
  final List<_Criterion> criteria;
  final Map<String, int> ratings;
  final void Function(String key, int rating) onRate;

  const _CategorySection({
    required this.title,
    required this.color,
    required this.icon,
    required this.criteria,
    required this.ratings,
    required this.onRate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title,
                      style: TextStyle(
                          color: color,
                          fontSize: 14,
                          fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
          ...criteria.map((c) => _CriterionRow(
                criterion: c,
                rating: ratings[c.key],
                color: color,
                onRate: (r) => onRate(c.key, r),
              )),
        ],
      ),
    );
  }
}

class _CriterionRow extends StatelessWidget {
  final _Criterion criterion;
  final int? rating;
  final Color color;
  final ValueChanged<int> onRate;

  const _CriterionRow({
    required this.criterion,
    required this.rating,
    required this.color,
    required this.onRate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(criterion.label,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(criterion.description,
              style: const TextStyle(
                  fontSize: 11, height: 1.4, color: Color(0xFF6B7280))),
          const SizedBox(height: 8),
          Row(
            children: List.generate(5, (i) {
              final value = i + 1;
              final selected = rating != null && value <= rating!;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onRate(value),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: selected
                          ? color.withOpacity(0.15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected ? color : Theme.of(context).dividerColor,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          selected ? Icons.star : Icons.star_border,
                          color: selected ? color : Theme.of(context).disabledColor,
                          size: 18,
                        ),
                        Text(
                          '$value',
                          style: TextStyle(
                            color: selected ? color : Theme.of(context).disabledColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// تعريفات الفئات والمعايير
// ============================================================
class _Criterion {
  final String key;
  final String label;
  final String description;
  const _Criterion({
    required this.key,
    required this.label,
    required this.description,
  });
}

class _Category {
  final String title;
  final Color color;
  final IconData icon;
  final List<_Criterion> items;
  const _Category({
    required this.title,
    required this.color,
    required this.icon,
    required this.items,
  });
}

/// 🆕 يقرأ معايير التقييم من MockRepository.evaluationCriteria.
/// لو لم توجد (في بيئات قديمة)، يعود للقائمة الـhardcoded أدناه.
List<_Category> _categoriesWithCriteria(AppStrings s) {
  final repo = MockRepository();
  final grouped = repo.evaluationCriteriaGrouped(
    EvaluationTargetType.employee,
  );
  if (grouped.isNotEmpty) {
    final categoryColors = <String, Color>{
      'hygiene': AppColors.success,
      'grooming': AppColors.brand,
      'work_area': AppColors.purple,
    };
    final categoryIcons = <String, IconData>{
      'hygiene': Icons.sanitizer,
      'grooming': Icons.checkroom,
      'work_area': Icons.cleaning_services,
    };
    return grouped.entries.map((entry) {
      final criteria = entry.value;
      return _Category(
        title: s.isAr
            ? criteria.first.categoryAr
            : criteria.first.categoryEn,
        color: categoryColors[entry.key] ?? AppColors.brand,
        icon: categoryIcons[entry.key] ?? Icons.checklist_rtl,
        items: criteria
            .map((c) => _Criterion(
                  key: '${c.categoryKey}_${c.id.substring(0, 4)}',
                  label: s.isAr ? c.labelAr : c.labelEn,
                  description: s.isAr ? c.descAr : c.descEn,
                ))
            .toList(),
      );
    }).toList();
  }

  // Fallback hardcoded (للتوافق فقط)
  return [
    _Category(
      title: s.evalCategoryHygiene,
      color: AppColors.success,
      icon: Icons.sanitizer,
      items: [
        _Criterion(
          key: 'hygiene_smell',
          label: s.evalHygieneSmell,
          description: s.evalHygieneSmellDesc,
        ),
        _Criterion(
          key: 'hygiene_oral',
          label: s.evalHygieneOral,
          description: s.evalHygieneOralDesc,
        ),
        _Criterion(
          key: 'hygiene_hands',
          label: s.evalHygieneHands,
          description: s.evalHygieneHandsDesc,
        ),
      ],
    ),
    _Category(
      title: s.evalCategoryGrooming,
      color: AppColors.brand,
      icon: Icons.checkroom,
      items: [
        _Criterion(
          key: 'grooming_uniform',
          label: s.evalGroomingUniform,
          description: s.evalGroomingUniformDesc,
        ),
        _Criterion(
          key: 'grooming_hair',
          label: s.evalGroomingHair,
          description: s.evalGroomingHairDesc,
        ),
        _Criterion(
          key: 'grooming_shoes',
          label: s.evalGroomingShoes,
          description: s.evalGroomingShoesDesc,
        ),
      ],
    ),
    _Category(
      title: s.evalCategoryWorkArea,
      color: AppColors.purple,
      icon: Icons.cleaning_services,
      items: [
        _Criterion(
          key: 'work_podium',
          label: s.evalWorkPodium,
          description: s.evalWorkPodiumDesc,
        ),
        _Criterion(
          key: 'work_tickets',
          label: s.evalWorkTickets,
          description: s.evalWorkTicketsDesc,
        ),
        _Criterion(
          key: 'work_car',
          label: s.evalWorkCar,
          description: s.evalWorkCarDesc,
        ),
      ],
    ),
  ];
}

// ============================================================
// 🆕 وضع Operation: عرض كل الموظفين تحت نقاطهم + إمكانية تقييمهم
// ============================================================
class _OperationEvaluationsView extends StatefulWidget {
  final String? currentUserEmpId;
  const _OperationEvaluationsView({required this.currentUserEmpId});

  @override
  State<_OperationEvaluationsView> createState() =>
      _OperationEvaluationsViewState();
}

class _OperationEvaluationsViewState extends State<_OperationEvaluationsView> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final auth = context.watch<AuthProvider>();
    final cid = auth.activeCountryId;

    var points = repo.points.toList();
    if (cid != null) {
      points = points.where((p) => p.countryId == cid).toList();
    }
    points.sort((a, b) => a.name.compareTo(b.name));

    // اعثر على روستر كل نقطة + موظفيه
    Map<String, List<Employee>> employeesByPoint = {};
    int totalEmps = 0;
    for (final p in points) {
      final pointRosters = repo.rosters
          .where((r) => r.siteId == p.id)
          .toList()
        ..sort((a, b) {
          int prio(WeeklyRoster x) {
            if (x.status == RosterStatus.approved) return 3;
            if (x.status == RosterStatus.submitted) return 2;
            if (x.status == RosterStatus.draft) return 1;
            return 0;
          }
          final cmp = prio(b).compareTo(prio(a));
          if (cmp != 0) return cmp;
          return b.weekStart.compareTo(a.weekStart);
        });
      if (pointRosters.isEmpty) {
        employeesByPoint[p.id] = [];
      } else {
        final empIds = pointRosters.first.assignments
            .map((a) => a.employeeId).toSet();
        // أضف المشرف المُسند للنقطة (لتقييمه أيضاً)
        try {
          final supervisor = repo.employees.firstWhere((e) => e.pointId == p.id);
          empIds.add(supervisor.id);
        } catch (_) {}
        var list = repo.employees.where((e) => empIds.contains(e.id)).toList();
        // فلتر بحث
        final q = _query.trim().toLowerCase();
        if (q.isNotEmpty) {
          list = list
              .where((e) =>
                  e.fullName.toLowerCase().contains(q) ||
                  e.code.toLowerCase().contains(q))
              .toList();
        }
        employeesByPoint[p.id] = list;
        totalEmps += list.length;
      }
    }

    final myEvals = repo.employeeEvaluations
        .where((e) => e.evaluatedBy == widget.currentUserEmpId)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    return Scaffold(
      body: Column(children: [
        // شريط Operation
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          color: AppColors.brand.withOpacity(0.08),
          child: Row(children: [
            const Icon(Icons.admin_panel_settings,
                color: AppColors.brand, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.isAr
                        ? 'وضع Operation: تقييم كل النقاط'
                        : 'Operation Mode: All points',
                    style: const TextStyle(
                        color: AppColors.brand,
                        fontWeight: FontWeight.w900,
                        fontSize: 13),
                  ),
                  Text(
                    s.isAr
                        ? '${points.length} نقطة • $totalEmps موظف'
                        : '${points.length} points • $totalEmps employees',
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ],
              ),
            ),
          ]),
        ),
        // بحث
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: s.isAr ? 'بحث (اسم/كود)' : 'Search (name/code)',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              filled: true,
              fillColor: Theme.of(context).cardTheme.color,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        Expanded(
          child: points.isEmpty
              ? Center(
                  child: Text(
                    s.isAr ? 'لا توجد نقاط' : 'No points',
                    style: const TextStyle(color: Colors.black45),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
                  itemCount: points.length,
                  itemBuilder: (_, i) {
                    final p = points[i];
                    final emps = employeesByPoint[p.id] ?? [];
                    return _PointEvalGroup(
                      point: p,
                      employees: emps,
                      myEvals: myEvals,
                      onEvaluate: (emp) => _openEvaluator(emp),
                    );
                  },
                ),
        ),
      ]),
    );
  }

  void _openEvaluator(Employee emp) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EvaluationFormSheet(employee: emp),
    );
  }
}

class _PointEvalGroup extends StatelessWidget {
  final Point point;
  final List<Employee> employees;
  final List<EmployeeEvaluation> myEvals;
  final void Function(Employee) onEvaluate;
  const _PointEvalGroup({
    required this.point,
    required this.employees,
    required this.myEvals,
    required this.onEvaluate,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: ExpansionTile(
        initiallyExpanded: employees.isNotEmpty,
        shape: const RoundedRectangleBorder(),
        collapsedShape: const RoundedRectangleBorder(),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.brand.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.location_on, color: AppColors.brand),
        ),
        title: Text(point.name,
            style: const TextStyle(
                fontWeight: FontWeight.w900, fontSize: 14)),
        subtitle: Row(children: [
          Text(point.code,
              style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  color: Colors.black54)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: employees.isEmpty
                  ? AppColors.warning.withOpacity(0.15)
                  : AppColors.brand.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              employees.isEmpty
                  ? (s.isAr ? 'لا يوجد روستر' : 'No roster')
                  : (s.isAr
                      ? '${employees.length} موظف'
                      : '${employees.length} emps'),
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: employees.isEmpty
                      ? AppColors.warning
                      : AppColors.brand),
            ),
          ),
        ]),
        children: employees.isEmpty
            ? [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    s.isAr
                        ? 'لا يوجد روستر فعّال لهذه النقطة بعد'
                        : 'No active roster for this point yet',
                    style: const TextStyle(color: Colors.black45, fontSize: 12),
                  ),
                ),
              ]
            : employees.map((emp) {
                final evals = myEvals.where((e) => e.employeeId == emp.id).toList();
                final latest = evals.isEmpty ? null : evals.first;
                return _EmployeeEvalCard(
                  employee: emp,
                  latestEval: latest,
                  evalCount: evals.length,
                  onEvaluate: () => onEvaluate(emp),
                );
              }).toList(),
      ),
    );
  }
}
