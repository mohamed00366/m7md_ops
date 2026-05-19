import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/workflow_engine.dart';
import '../../core/theme/app_colors.dart';
import '../../models/lookups.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';
import 'workflow_editor_screen.dart';

/// 🔁 شاشة محرّر سير الموافقات (Workflow Builder)
///
/// تستعرض كل قوالب النماذج (FormTemplate) وتحلّ سلسلة الموافقات لكل واحد
/// بمحاكاة مُقدِّم معيّن (يُختار من قائمة المسمّيات الوظيفيّة).
///
/// الفائدة:
///   - إدارة تستطيع رؤية مَن سيُوقّع كل خطوة قبل النشر.
///   - كشف الفجوات (مثل: لا يوجد JobTitle بقوّة موافقة 5 → الطلب لن يُكمل).
///   - تكشف خطوات auto_chain التي تنتهي بسلسلة مفقودة.
class WorkflowBuilderScreen extends StatefulWidget {
  const WorkflowBuilderScreen({super.key});

  @override
  State<WorkflowBuilderScreen> createState() => _WorkflowBuilderScreenState();
}

class _WorkflowBuilderScreenState extends State<WorkflowBuilderScreen> {
  String? _selectedTemplateId;
  String? _sampleSubmitterJobTitleId;

  @override
  void initState() {
    super.initState();
    final repo = MockRepository();
    if (repo.formTemplates.isNotEmpty) {
      _selectedTemplateId = repo.formTemplates.first.id;
    }
    // اختيار أوّل JobTitle برتبة عامل/L5 كمُقدِّم افتراضي
    final workers = repo.jobTitles.where((jt) => jt.level == 5).toList();
    if (workers.isNotEmpty) {
      _sampleSubmitterJobTitleId = workers.first.id;
    } else if (repo.jobTitles.isNotEmpty) {
      _sampleSubmitterJobTitleId = repo.jobTitles.last.id;
    }
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
    final templates = repo.formTemplates;
    final isAr = s.isAr;

    final selectedTemplate = _selectedTemplateId == null
        ? null
        : templates.firstWhere(
            (t) => t.id == _selectedTemplateId,
            orElse: () => templates.isNotEmpty
                ? templates.first
                : FormTemplate(id: '', code: '', nameAr: '', nameEn: ''),
          );

    final chain = (selectedTemplate == null || selectedTemplate.id.isEmpty)
        ? <ChainStep>[]
        : WorkflowEngine.previewChain(
            template: selectedTemplate,
            sampleSubmitterJobTitleId: _sampleSubmitterJobTitleId,
          );

    final unresolvedCount = chain.where((c) => c.match?.isResolved != true).length;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // ===== Header =====
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.brand.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.brand.withOpacity(0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_graph, color: AppColors.brand),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isAr ? 'معاينة سير الموافقات' : 'Workflow Preview',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w900),
                    ),
                  ),
                  if (_selectedTemplateId != null)
                    ElevatedButton.icon(
                      icon: const Icon(Icons.edit, size: 14),
                      label: Text(
                        isAr ? 'محرّر' : 'Edit',
                        style: const TextStyle(fontSize: 11),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () {
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => WorkflowEditorScreen(
                            templateId: _selectedTemplateId!,
                          ),
                        ));
                      },
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                isAr
                    ? 'يحلّ كلّ خطوة موافقة إلى مسمّى وظيفيّ بناءً على هرم الإدارة وقوّة الموافقات.'
                    : 'Resolves each approval step to a job title using management hierarchy & approval power.',
                style: const TextStyle(fontSize: 11.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ===== Selectors =====
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAr ? 'اختر القالب والمُقدِّم' : 'Pick Template & Submitter',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _selectedTemplateId,
                  decoration: InputDecoration(
                    labelText: isAr ? 'القالب' : 'Template',
                    isDense: true,
                    prefixIcon: const Icon(Icons.assignment_outlined, size: 18),
                  ),
                  items: templates
                      .map((t) => DropdownMenuItem(
                            value: t.id,
                            child: Text('${t.code} • ${isAr ? t.nameAr : t.nameEn}'),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedTemplateId = v),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _sampleSubmitterJobTitleId,
                  decoration: InputDecoration(
                    labelText: isAr ? 'محاكاة مُقدِّم بمسمّى' : 'Simulate as Job Title',
                    isDense: true,
                    prefixIcon: const Icon(Icons.person_search, size: 18),
                  ),
                  items: repo.jobTitles
                      .map((jt) => DropdownMenuItem(
                            value: jt.id,
                            child: Text(
                                '${jt.displayName(isAr)} ${jt.level > 0 ? "(L${jt.level})" : ""}'),
                          ))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _sampleSubmitterJobTitleId = v),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // ===== Chain visualization =====
        if (selectedTemplate == null || selectedTemplate.workflow.isEmpty)
          _EmptyChainCard(isAr: isAr)
        else ...[
          Row(
            children: [
              const Icon(Icons.timeline, size: 18, color: AppColors.brand),
              const SizedBox(width: 6),
              Text(
                isAr
                    ? 'سلسلة الموافقات (${chain.length} خطوة)'
                    : 'Approval Chain (${chain.length} steps)',
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              if (unresolvedCount > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isAr
                        ? '$unresolvedCount غير محلول'
                        : '$unresolvedCount unresolved',
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < chain.length; i++) ...[
            _ChainStepCard(step: chain[i], isAr: isAr),
            if (i < chain.length - 1)
              Padding(
                padding: const EdgeInsets.only(left: 24, right: 24),
                child: Container(
                  height: 14,
                  width: 2,
                  color: AppColors.brand.withOpacity(0.3),
                ),
              ),
          ],
        ],
      ],
    );
  }
}

class _ChainStepCard extends StatelessWidget {
  final ChainStep step;
  final bool isAr;

  const _ChainStepCard({required this.step, required this.isAr});

  @override
  Widget build(BuildContext context) {
    final match = step.match;
    final resolved = match?.isResolved ?? false;
    final color = resolved ? AppColors.success : AppColors.danger;
    final actorTypeLabel = _actorTypeLabel(step.actorType, isAr);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${step.index + 1}',
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        step.label(isAr),
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w800),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.brand.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        actorTypeLabel,
                        style: const TextStyle(
                          color: AppColors.brand,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      resolved ? Icons.check_circle : Icons.error_outline,
                      size: 14,
                      color: color,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        match?.displayName(isAr) ??
                            (isAr ? 'لا توجد بيانات' : 'No data'),
                        style: TextStyle(
                          fontSize: 12,
                          color: color,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                if (match?.jobTitle != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (match!.jobTitle!.level > 0) ...[
                        _SmallChip(
                          icon: Icons.layers_outlined,
                          text: 'L${match.jobTitle!.level}',
                        ),
                        const SizedBox(width: 6),
                      ],
                      _SmallChip(
                        icon: Icons.verified_outlined,
                        text: isAr
                            ? 'موافقة ${match.jobTitle!.approvalPower}/5'
                            : 'Approval ${match.jobTitle!.approvalPower}/5',
                      ),
                    ],
                  ),
                ],
                if (step.actorType == 'auto_chain') ...[
                  const SizedBox(height: 4),
                  Text(
                    isAr
                        ? 'يصعد الهرم حتى يجد قوّة موافقة ≥ ${step.rawStep['min_approval_power'] ?? 1}'
                        : 'Walks chain until approval power ≥ ${step.rawStep['min_approval_power'] ?? 1}',
                    style: const TextStyle(fontSize: 10.5, color: Colors.grey),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _actorTypeLabel(String type, bool isAr) {
    switch (type) {
      case 'auto_chain':
        return isAr ? 'تلقائي (هرم)' : 'Auto-chain';
      case 'specific':
        return isAr ? 'موظف محدّد' : 'Specific';
      case 'role':
      default:
        return isAr ? 'حسب الدور' : 'By Role';
    }
  }
}

class _SmallChip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _SmallChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: Colors.grey[700]),
          const SizedBox(width: 3),
          Text(
            text,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyChainCard extends StatelessWidget {
  final bool isAr;
  const _EmptyChainCard({required this.isAr});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(Icons.outbox_outlined, size: 32, color: Colors.grey[600]),
          const SizedBox(height: 6),
          Text(
            isAr
                ? 'لا توجد خطوات موافقة في هذا القالب'
                : 'This template has no workflow steps',
            style: TextStyle(
                fontSize: 12,
                color: Colors.grey[700],
                fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
