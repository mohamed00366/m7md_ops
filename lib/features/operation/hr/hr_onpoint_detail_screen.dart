import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/on_point_training_settings.dart';
import '../../../core/services/supabase_data_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/enums.dart';
import '../../../models/models.dart';
import '../../../models/rbac.dart';
import '../../../repositories/mock_repository.dart';
import '../../../shared/m7_app_bar.dart';
import '../../../shared/widgets.dart';

/// 🎓 شاشة تفاصيل تدريب موظف جديد على نقطة (مطابقة للنموذج الورقي)
///
/// أقسام:
///   1. معلومات الموظف (قراءة فقط من سجلّ الموظف)
///   2. الخبرة المهنيّة (3 صفوف اختياريّة)
///   3. اللغات (English / Urdu / Arabic / Other)
///   4. توقيع الموظف
///   5. تقرير Operation Manager: المستوى A/B/C، Approved/Rejected، Comments
///   6. توقيعات: Operation Supervisor + Camp Boss + HR
///   7. معلومات التدريب: المكان، تاريخ البدء، المدّة
class HrOnPointDetailScreen extends StatefulWidget {
  final String trainingId;
  const HrOnPointDetailScreen({super.key, required this.trainingId});

  @override
  State<HrOnPointDetailScreen> createState() =>
      _HrOnPointDetailScreenState();
}

class _HrOnPointDetailScreenState extends State<HrOnPointDetailScreen> {
  late TextEditingController _commentsCtrl;
  late TextEditingController _notesCtrl;
  late TextEditingController _otherLangCtrl;
  late List<TextEditingController> _expCompanyCtrls;
  late List<TextEditingController> _expDurationCtrls;
  late List<TextEditingController> _expPositionCtrls;
  bool _dirty = false;

  OnPointTraining? get _t =>
      MockRepository().onPointTrainingById(widget.trainingId);

  @override
  void initState() {
    super.initState();
    final t = _t;
    _commentsCtrl = TextEditingController(text: t?.operationComments ?? '');
    _notesCtrl = TextEditingController(text: t?.notes ?? '');
    _otherLangCtrl = TextEditingController(text: t?.langOther ?? '');
    // 3 صفوف خبرة (نفرد للنموذج)
    final exp = List<OnPointExperienceEntry>.from(
        (t?.experience ?? <OnPointExperienceEntry>[]));
    while (exp.length < 3) {
      exp.add(OnPointExperienceEntry());
    }
    _expCompanyCtrls = exp.map((e) => TextEditingController(text: e.company)).toList();
    _expDurationCtrls = exp.map((e) => TextEditingController(text: e.duration)).toList();
    _expPositionCtrls = exp.map((e) => TextEditingController(text: e.position)).toList();

    MockRepository().addListener(_onChange);
  }

  @override
  void dispose() {
    MockRepository().removeListener(_onChange);
    _commentsCtrl.dispose();
    _notesCtrl.dispose();
    _otherLangCtrl.dispose();
    for (final c in _expCompanyCtrls) {
      c.dispose();
    }
    for (final c in _expDurationCtrls) {
      c.dispose();
    }
    for (final c in _expPositionCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  /// يحفظ السجلّ (Supabase إن جاهز، وإلا Mock فقط)
  Future<void> _persist(OnPointTraining t) async {
    if (SupabaseService().isReady) {
      await SupabaseDataService().upsertOnPointTraining(t);
    } else {
      _persist(t);
    }
  }

  Future<void> _save() async {
    final t = _t;
    if (t == null) return;
    // اجمع التحديثات
    t.operationComments = _commentsCtrl.text.trim().isEmpty
        ? null
        : _commentsCtrl.text.trim();
    t.notes = _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();
    t.langOther = _otherLangCtrl.text.trim().isEmpty
        ? null
        : _otherLangCtrl.text.trim();
    final exp = <OnPointExperienceEntry>[];
    for (var i = 0; i < _expCompanyCtrls.length; i++) {
      final entry = OnPointExperienceEntry(
        company: _expCompanyCtrls[i].text.trim(),
        duration: _expDurationCtrls[i].text.trim(),
        position: _expPositionCtrls[i].text.trim(),
      );
      if (!entry.isEmpty) exp.add(entry);
    }
    t.experience = exp;
    t.updatedAt = DateTime.now();
    _persist(t);
    if (!mounted) return;
    setState(() => _dirty = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.success,
      content: Text(AppStrings.of(context).savedSuccess),
    ));
  }

  Future<void> _signAs(_SignerKind who) async {
    final t = _t;
    if (t == null) return;
    final auth = context.read<AuthProvider>();
    final actor = auth.currentUser?.employeeId ?? auth.currentUser?.id;
    final now = DateTime.now();
    setState(() {
      switch (who) {
        case _SignerKind.employee:
          t.employeeSignedBy = actor;
          t.employeeSignedAt = now;
          break;
        case _SignerKind.opSupervisor:
          t.opSupervisorSignedBy = actor;
          t.opSupervisorSignedAt = now;
          break;
        case _SignerKind.campBoss:
          t.campBossSignedBy = actor;
          t.campBossSignedAt = now;
          break;
        case _SignerKind.hr:
          t.hrSignedBy = actor;
          t.hrSignedAt = now;
          break;
      }
      t.updatedAt = now;
    });
    _persist(t);
  }

  Future<void> _setStage(OnPointStage stage) async {
    final t = _t;
    if (t == null) return;
    setState(() {
      t.stage = stage;
      if (stage == OnPointStage.inProgress && t.startDate == null) {
        t.startDate = DateTime.now();
      }
      if (stage == OnPointStage.awaitingReview &&
          t.actualEndDate == null) {
        t.actualEndDate = DateTime.now();
      }
      t.updatedAt = DateTime.now();
    });
    _persist(t);
  }

  Future<void> _setDecision({required bool approved}) async {
    final t = _t;
    if (t == null) return;
    if (approved && t.level == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.warning,
        content: Text(AppStrings.of(context).isAr
            ? 'حدّد المستوى (A/B/C) أوّلاً قبل الاعتماد'
            : 'Set level (A/B/C) before approval'),
      ));
      return;
    }
    final repo = MockRepository();
    setState(() {
      t.approved = approved;
      t.stage =
          approved ? OnPointStage.passed : OnPointStage.rejected;
      t.updatedAt = DateTime.now();
    });
    _persist(t);
    // 🆕 عند الاعتماد: ارفع الموظف لـ "محترف" (يخرج من قائمة المتدرّبين)
    if (approved) {
      final emp = repo.employeeById(t.employeeId);
      if (emp != null && emp.hireType != EmployeeHireType.professional) {
        emp.hireType = EmployeeHireType.professional;
        // احفظ في Supabase أيضاً إن جاهز
        if (SupabaseService().isReady) {
          await SupabaseDataService().updateEmployee(emp);
        } else {
          repo.updateEmployee(emp);
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.success,
          content: Text(AppStrings.of(context).isAr
              ? '✅ تمّ الاعتماد — الموظف الآن محترف وجاهز للعمل'
              : '✅ Approved — employee is now Professional & ready'),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final repo = MockRepository();
    final t = _t;
    if (t == null) {
      return Scaffold(
        appBar: M7AppBar(title: isAr ? 'تدريب' : 'Training'),
        body: EmptyState(
          icon: Icons.error_outline,
          message: isAr ? 'السجلّ غير موجود' : 'Record not found',
        ),
      );
    }
    final emp = repo.employeeById(t.employeeId);
    final point = repo.pointById(t.pointId);
    final stageColor = _stageColor(t.stage);

    // 🆕 صلاحيّة التقييم — أيضاً نتحقّق من قائمة المسمّيات في الإعدادات
    final auth = context.watch<AuthProvider>();
    final empOfActor = auth.currentUser?.employeeId == null
        ? null
        : repo.employeeById(auth.currentUser!.employeeId!);
    final actorJobTitleId = empOfActor?.jobTitleId;
    final settings = OnPointTrainingSettings.instance;
    final approverIds = settings.approverJobTitleIds;
    final canEvaluateByPermission = auth.isSuperAdmin ||
        auth.permissions.contains(P.trainingOnPointEvaluate);
    final canEvaluateByJobTitle = approverIds.isEmpty ||
        (actorJobTitleId != null && approverIds.contains(actorJobTitleId));
    final canEvaluate = canEvaluateByPermission && canEvaluateByJobTitle;

    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? 'تدريب موظف جديد' : 'OnPoint Training',
        subtitle: emp?.fullName ?? '—',
        backgroundColor: stageColor,
        actions: [
          if (_dirty)
            M7AppBarAction(
              icon: Icons.save,
              tooltip: s.save,
              onPressed: _save,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // ===== الحالة + التحكّم بالمراحل =====
          _StageControl(
            stage: t.stage,
            onChange: _setStage,
            isAr: isAr,
          ),
          const SizedBox(height: 12),

          // ===== معلومات الموظف =====
          SectionCard(
            title: isAr ? '👤 معلومات الموظف' : '👤 Employee Info',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Row(
                  label: isAr ? 'الاسم' : 'Name',
                  value: emp?.fullName ?? '—',
                ),
                _Row(label: isAr ? 'الكود' : 'Code', value: emp?.code ?? '—'),
                _Row(
                  label: isAr ? 'المسمّى' : 'Position',
                  value: emp?.jobTitle ?? '—',
                ),
                _Row(
                  label: isAr ? 'القسم' : 'Department',
                  value: emp?.department ?? '—',
                ),
                _Row(
                  label: isAr ? 'الجنسيّة' : 'Nationality',
                  value: emp?.nationality ?? '—',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ===== معلومات التدريب =====
          SectionCard(
            title: isAr ? '🎯 معلومات التدريب' : '🎯 Training Info',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Row(
                  label: isAr ? 'النقطة' : 'Point',
                  value: point?.name ?? '—',
                ),
                _Row(
                  label: isAr ? 'تاريخ البدء' : 'Start Date',
                  value: t.startDate == null ? '—' : _fmt(t.startDate!),
                  trailing: TextButton.icon(
                    icon: const Icon(Icons.edit_calendar, size: 14),
                    label: Text(isAr ? 'تعديل' : 'Edit',
                        style: const TextStyle(fontSize: 11)),
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: t.startDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now()
                            .add(const Duration(days: 365)),
                      );
                      if (d != null) {
                        setState(() => t.startDate = d);
                        _persist(t);
                      }
                    },
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: _Row(
                        label: isAr ? 'مدّة التدريب' : 'Days',
                        value: '${t.plannedDays}',
                      ),
                    ),
                    SizedBox(
                      width: 80,
                      child: TextField(
                        controller: TextEditingController(
                            text: '${t.plannedDays}'),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            isDense: true, hintText: '7'),
                        onSubmitted: (v) {
                          final n = int.tryParse(v) ?? 7;
                          setState(() => t.plannedDays = n);
                          _persist(t);
                        },
                      ),
                    ),
                  ],
                ),
                if (t.expectedEndDate != null)
                  _Row(
                    label: isAr ? 'تاريخ الانتهاء المتوقّع' : 'Expected End',
                    value: _fmt(t.expectedEndDate!),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ===== الخبرة المهنيّة (3 صفوف) =====
          SectionCard(
            title: isAr ? '💼 الخبرة المهنيّة' : '💼 Professional Experience',
            child: Column(
              children: List.generate(3, (i) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _expCompanyCtrls[i],
                          decoration: InputDecoration(
                            labelText:
                                isAr ? 'اسم الشركة' : "Company's name",
                            isDense: true,
                          ),
                          onChanged: (_) => _markDirty(),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _expDurationCtrls[i],
                          decoration: InputDecoration(
                            labelText:
                                isAr ? 'المدّة' : 'Work duration',
                            isDense: true,
                          ),
                          onChanged: (_) => _markDirty(),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _expPositionCtrls[i],
                          decoration: InputDecoration(
                            labelText: isAr ? 'المسمّى' : 'Position',
                            isDense: true,
                          ),
                          onChanged: (_) => _markDirty(),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 12),

          // ===== اللغات =====
          SectionCard(
            title: isAr ? '🌐 اللغات' : '🌐 Languages',
            child: Column(
              children: [
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: t.langEnglish,
                  onChanged: (v) {
                    setState(() => t.langEnglish = v ?? false);
                    _persist(t);
                  },
                  title: const Text('English'),
                ),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: t.langArabic,
                  onChanged: (v) {
                    setState(() => t.langArabic = v ?? false);
                    _persist(t);
                  },
                  title: const Text('Arabic'),
                ),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: t.langUrdu,
                  onChanged: (v) {
                    setState(() => t.langUrdu = v ?? false);
                    _persist(t);
                  },
                  title: const Text('Urdu'),
                ),
                TextField(
                  controller: _otherLangCtrl,
                  decoration: InputDecoration(
                    labelText: isAr ? 'لغات أخرى' : 'Other languages',
                    isDense: true,
                  ),
                  onChanged: (_) => _markDirty(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ===== تقرير Operation Manager =====
          SectionCard(
            title: isAr
                ? '📋 تقرير Operation Manager'
                : '📋 Operation Manager Report',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  isAr ? 'المستوى:' : 'Level:',
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: OnPointLevel.values.map((lv) {
                    final selected = t.level == lv;
                    return ChoiceChip(
                      label: Text(
                        '${lv.label()} — ${isAr ? lv.descriptionAr() : lv.descriptionEn()}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      selected: selected,
                      onSelected: (_) {
                        setState(() => t.level = lv);
                        _persist(t);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _commentsCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: isAr ? 'تعليقات' : 'Comments',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => _markDirty(),
                ),
                const SizedBox(height: 10),
                if (canEvaluate)
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.success),
                          onPressed: () => _setDecision(approved: true),
                          icon: const Icon(Icons.check, size: 16),
                          label: Text(isAr ? 'اعتماد' : 'Approve'),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.danger),
                          onPressed: () => _setDecision(approved: false),
                          icon: const Icon(Icons.close, size: 16),
                          label: Text(isAr ? 'رفض' : 'Reject'),
                        ),
                      ),
                    ],
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.textTertiaryLight.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.lock_outline,
                            size: 14,
                            color: AppColors.textTertiaryLight),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            isAr
                                ? 'لا تملك صلاحيّة الاعتماد/الرفض'
                                : 'You don\'t have evaluate permission',
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textTertiaryLight,
                                fontStyle: FontStyle.italic),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (t.approved != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (t.approved! ? AppColors.success : AppColors.danger)
                          .withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          t.approved! ? Icons.verified : Icons.cancel,
                          size: 14,
                          color: t.approved!
                              ? AppColors.success
                              : AppColors.danger,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          t.approved!
                              ? (isAr
                                  ? '✅ تمّ الاعتماد — جاهز للعمل'
                                  : '✅ Approved — Ready to work')
                              : (isAr
                                  ? '❌ تمّ الرفض'
                                  : '❌ Rejected'),
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                              color: t.approved!
                                  ? AppColors.success
                                  : AppColors.danger),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ===== التوقيعات =====
          SectionCard(
            title: isAr ? '✍️ التوقيعات' : '✍️ Signatures',
            child: Column(
              children: [
                _SignatureRow(
                  label: isAr ? 'الموظف' : 'Employee',
                  signedBy: t.employeeSignedBy,
                  signedAt: t.employeeSignedAt,
                  onSign: () => _signAs(_SignerKind.employee),
                  isAr: isAr,
                ),
                const Divider(height: 14),
                _SignatureRow(
                  label: isAr
                      ? 'مشرف العمليّات'
                      : 'Operation Supervisor',
                  signedBy: t.opSupervisorSignedBy,
                  signedAt: t.opSupervisorSignedAt,
                  onSign: () => _signAs(_SignerKind.opSupervisor),
                  isAr: isAr,
                ),
                const Divider(height: 14),
                _SignatureRow(
                  label: 'Camp Boss',
                  signedBy: t.campBossSignedBy,
                  signedAt: t.campBossSignedAt,
                  onSign: () => _signAs(_SignerKind.campBoss),
                  isAr: isAr,
                ),
                const Divider(height: 14),
                _SignatureRow(
                  label: 'HR',
                  signedBy: t.hrSignedBy,
                  signedAt: t.hrSignedAt,
                  onSign: () => _signAs(_SignerKind.hr),
                  isAr: isAr,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ===== ملاحظات إضافيّة =====
          SectionCard(
            title: isAr ? '📝 ملاحظات' : '📝 Notes',
            child: TextField(
              controller: _notesCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: isAr
                    ? 'ملاحظات إضافيّة (اختياري)'
                    : 'Additional notes (optional)',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => _markDirty(),
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
      bottomNavigationBar: _dirty
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success),
                    onPressed: _save,
                    icon: const Icon(Icons.save),
                    label: Text(s.save,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  String _fmt(DateTime d) =>
      '${d.day}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Color _stageColor(OnPointStage stage) {
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

enum _SignerKind { employee, opSupervisor, campBoss, hr }

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final Widget? trailing;
  const _Row({required this.label, required this.value, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiaryLight)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _StageControl extends StatelessWidget {
  final OnPointStage stage;
  final ValueChanged<OnPointStage> onChange;
  final bool isAr;
  const _StageControl({
    required this.stage,
    required this.onChange,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: isAr ? '🚦 الحالة' : '🚦 Stage',
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: OnPointStage.values.map((st) {
          final selected = stage == st;
          final color = _stageColor(st);
          return ChoiceChip(
            label: Text(
              isAr ? st.arabicLabel() : st.englishLabel(),
              style: const TextStyle(fontSize: 11),
            ),
            selected: selected,
            selectedColor: color.withOpacity(0.18),
            side: BorderSide(color: color.withOpacity(0.5)),
            onSelected: (_) => onChange(st),
          );
        }).toList(),
      ),
    );
  }

  Color _stageColor(OnPointStage stage) {
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

class _SignatureRow extends StatelessWidget {
  final String label;
  final String? signedBy;
  final DateTime? signedAt;
  final VoidCallback onSign;
  final bool isAr;
  const _SignatureRow({
    required this.label,
    required this.signedBy,
    required this.signedAt,
    required this.onSign,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    final signed = signedAt != null;
    final repo = MockRepository();
    final signerName = signedBy == null
        ? null
        : (repo.employeeById(signedBy!)?.fullName ?? signedBy);
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: (signed ? AppColors.success : AppColors.textTertiaryLight)
                .withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(
            signed ? Icons.check_circle : Icons.draw,
            color: signed ? AppColors.success : AppColors.textTertiaryLight,
            size: 18,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800)),
              if (signed)
                Text(
                  '${signerName ?? "—"} • ${_fmt(signedAt!)}',
                  style: const TextStyle(
                      fontSize: 10, color: AppColors.success),
                )
              else
                Text(
                  isAr ? 'لم يوقّع بعد' : 'Not signed',
                  style: const TextStyle(
                      fontSize: 10, color: AppColors.textTertiaryLight),
                ),
            ],
          ),
        ),
        if (!signed)
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brand,
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            onPressed: onSign,
            icon: const Icon(Icons.draw, size: 12),
            label: Text(isAr ? 'وقّع' : 'Sign',
                style: const TextStyle(fontSize: 11)),
          )
        else
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: isAr ? 'إعادة التوقيع' : 'Re-sign',
            onPressed: onSign,
          ),
      ],
    );
  }

  String _fmt(DateTime d) =>
      '${d.day}/${d.month.toString().padLeft(2, '0')}/${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
