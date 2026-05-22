import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/enums.dart';
import '../../../models/models.dart';
import '../../../repositories/mock_repository.dart';
import '../../../shared/widgets.dart';
import 'trainee_onboarding_form_screen.dart';

/// 🎓 تدريب الموظفين الجدد على نقطة (OnPoint Training) — تابة في HR Hub
///
/// يعرض المتدرّبين فقط (employees with hireType==trainee + لم يُعتمدوا بعد).
/// كلّ موظف يدخل تلقائيّاً عند تسجيله كمتدرّب — مع زرّ مراجعة وتقييم.
class HrOnPointTrainingScreen extends StatefulWidget {
  const HrOnPointTrainingScreen({super.key});

  @override
  State<HrOnPointTrainingScreen> createState() =>
      _HrOnPointTrainingScreenState();
}

class _HrOnPointTrainingScreenState
    extends State<HrOnPointTrainingScreen> {
  String _query = '';
  OnPointStage? _filterStage;

  @override
  void initState() {
    super.initState();
    final repo = MockRepository();
    // 🆕 ترقية كلّ السجلّات القديمة العالقة في notStarted إلى inProgress
    repo.promoteAllNotStartedToInProgress();
    repo.addListener(_onChange);
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
    final isAr = s.isAr;
    final repo = MockRepository();
    final auth = context.watch<AuthProvider>();

    // كلّ المتدرّبين الذين لم يجتازوا
    final trainees = repo.currentTrainees().where((e) {
      // فلترة الدولة
      if (auth.activeCountryId != null && !auth.isSuperAdmin) {
        if (e.countryId != auth.activeCountryId) return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));

    // اربط لكلّ متدرّب آخر سجلّ تدريب على نقطة
    final entries = trainees.map((emp) {
      return _TraineeEntry(
        employee: emp,
        training: repo.latestOnPointForEmployee(emp.id),
      );
    }).toList();

    final filtered = entries.where((entry) {
      if (_query.isNotEmpty) {
        final q = _query.toLowerCase();
        if (!entry.employee.fullName.toLowerCase().contains(q) &&
            !entry.employee.code.toLowerCase().contains(q)) {
          return false;
        }
      }
      if (_filterStage != null) {
        final st = entry.training?.stage ?? OnPointStage.notStarted;
        if (st != _filterStage) return false;
      }
      return true;
    }).toList();

    // إحصاءات سريعة
    final inProgress = entries
        .where((e) =>
            (e.training?.stage ?? OnPointStage.notStarted) ==
            OnPointStage.inProgress)
        .length;
    final awaiting = entries
        .where((e) => e.training?.stage == OnPointStage.awaitingReview)
        .length;
    final notStarted = entries
        .where((e) =>
            e.training == null ||
            e.training!.stage == OnPointStage.notStarted)
        .length;

    return Column(
      children: [
        // ===== KPIs =====
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: _MiniKpi(
                  label: isAr ? 'لم يبدأ' : 'Not started',
                  value: '$notStarted',
                  color: AppColors.textTertiaryLight,
                  icon: Icons.hourglass_empty,
                  onTap: () => setState(() => _filterStage =
                      _filterStage == OnPointStage.notStarted
                          ? null
                          : OnPointStage.notStarted),
                  selected: _filterStage == OnPointStage.notStarted,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _MiniKpi(
                  label: isAr ? 'قيد التدريب' : 'In progress',
                  value: '$inProgress',
                  color: AppColors.info,
                  icon: Icons.school_outlined,
                  onTap: () => setState(() => _filterStage =
                      _filterStage == OnPointStage.inProgress
                          ? null
                          : OnPointStage.inProgress),
                  selected: _filterStage == OnPointStage.inProgress,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _MiniKpi(
                  label: isAr ? 'بانتظار المراجعة' : 'Awaiting',
                  value: '$awaiting',
                  color: AppColors.warning,
                  icon: Icons.pending_actions,
                  onTap: () => setState(() => _filterStage =
                      _filterStage == OnPointStage.awaitingReview
                          ? null
                          : OnPointStage.awaitingReview),
                  selected: _filterStage == OnPointStage.awaitingReview,
                ),
              ),
            ],
          ),
        ),
        // ===== شريط البحث =====
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: TextField(
            decoration: InputDecoration(
              hintText: isAr
                  ? 'بحث: اسم أو كود الموظف...'
                  : 'Search employee...',
              prefixIcon: const Icon(Icons.search, size: 18),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        // ===== القائمة =====
        Expanded(
          child: filtered.isEmpty
              ? EmptyState(
                  icon: Icons.school_outlined,
                  message: isAr
                      ? 'لا يوجد متدرّبون حاليّاً'
                      : 'No active trainees',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) =>
                      _TraineeCard(entry: filtered[i]),
                ),
        ),
      ],
    );
  }
}

class _TraineeEntry {
  final Employee employee;
  final OnPointTraining? training;
  _TraineeEntry({required this.employee, required this.training});
}

class _TraineeCard extends StatelessWidget {
  final _TraineeEntry entry;
  const _TraineeCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final repo = MockRepository();
    final emp = entry.employee;
    final t = entry.training;
    final stage = t?.stage ?? OnPointStage.notStarted;
    final color = _stageColor(stage);
    final point = t == null ? null : repo.pointById(t.pointId);

    return InkWell(
      onTap: () async {
        // 🆕 افتَح نَموذَج TRAINEE-ONBOARDING الخاصّ بِالمُوَظَّف
        // (يُنشَأ تِلقائيّاً إن لم يَكُن مَوجوداً، وَيُملَأ بِبَياناته)
        if (!context.mounted) return;
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TraineeOnboardingFormScreen(employee: emp),
        ));
        // 🔄 رَقّ سِجِلّ الـOnPoint القَديم لِـinProgress (لِلتَوافُق مَع
        //    الإحصائيّات وَالـworkflow القَديم) — لكِنّ الواجِهة الرَئيسيّة
        //    أَصبَحَت النَموذَج.
        OnPointTraining tr = t ??
            (() {
              final created = repo.autoCreateOnPointForNewTrainee(emp);
              return created!;
            })();
        if (tr.stage == OnPointStage.notStarted) {
          tr.stage = OnPointStage.inProgress;
          tr.startDate ??= DateTime.now();
          tr.updatedAt = DateTime.now();
          repo.upsertOnPointTraining(tr);
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                AppAvatar(initials: emp.initials, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(emp.fullName,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w800)),
                      Text(
                        '${emp.code} • ${emp.jobTitle}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isAr ? stage.arabicLabel() : stage.englishLabel(),
                    style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (point != null)
                  _Chip(
                    icon: Icons.place,
                    label: point.name,
                    color: AppColors.warning,
                  ),
                if (t?.startDate != null)
                  _Chip(
                    icon: Icons.event,
                    label: isAr
                        ? 'بدأ: ${_fmt(t!.startDate!)}'
                        : 'Started: ${_fmt(t!.startDate!)}',
                    color: AppColors.info,
                  ),
                if (t != null)
                  _Chip(
                    icon: Icons.timer,
                    label: '${t.plannedDays} ${isAr ? "يوم" : "d"}',
                    color: AppColors.brand,
                  ),
                if (t?.daysRemaining != null && t!.daysRemaining! < 0)
                  _Chip(
                    icon: Icons.warning_amber,
                    label: isAr
                        ? 'انتهت المدّة منذ ${-t.daysRemaining!} يوم'
                        : '${-t.daysRemaining!}d overdue',
                    color: AppColors.danger,
                  ),
                if (t?.level != null)
                  _Chip(
                    icon: Icons.workspace_premium,
                    label:
                        '${isAr ? "مستوى" : "Level"} ${t!.level!.label()}',
                    color: AppColors.success,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _fmt(DateTime d) =>
      '${d.day}/${d.month.toString().padLeft(2, '0')}';

  static Color _stageColor(OnPointStage stage) {
    switch (stage) {
      case OnPointStage.notStarted:
        return AppColors.textTertiaryLight;
      case OnPointStage.inProgress:
        return AppColors.info;
      case OnPointStage.awaitingReview:
        return AppColors.warning;
      case OnPointStage.passed:
        return AppColors.success;
      case OnPointStage.rejected:
        return AppColors.danger;
    }
  }
}

class _MiniKpi extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;
  final bool selected;
  const _MiniKpi({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    required this.onTap,
    this.selected = false,
  });
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: selected ? 0.2 : 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: color.withValues(alpha: selected ? 0.6 : 0.2),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 14),
                const SizedBox(width: 4),
                Text(value,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: color)),
              ],
            ),
            Text(
              label,
              style: TextStyle(
                  fontSize: 10,
                  color: color.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _Chip(
      {required this.icon, required this.label, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 10, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
