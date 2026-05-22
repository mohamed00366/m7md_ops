import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/supabase_data_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/services/workflow_engine.dart';
import '../../core/theme/app_colors.dart';
import '../../core/workflows/workflow_templates.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/m7_app_bar.dart';
import '../../shared/widgets.dart';

/// 🎨 محرّر سير الموافقات البصري (Visual Workflow Editor)
///
/// يفتح على FormTemplate ويعرض خطوات الـ workflow كبطاقات قابلة للسحب.
/// المسؤول يستطيع:
///   - إعادة ترتيب الخطوات بـ drag-and-drop
///   - إضافة خطوة جديدة (auto_chain / role / specific)
///   - تعديل خطوة (نوعها، عتباتها، تسمياتها، توقيع، ملاحظات)
///   - حذف خطوة
///   - تطبيق قالب جاهز (WorkflowPreset) لاستبدال كل الخطوات
///   - مسح الكل
///
/// يحفظ عبر SupabaseDataService.upsertFormTemplate إن كان مرتبطاً، وإلا
/// يحفظ في MockRepository ويُخطر الـ listeners.
class WorkflowEditorScreen extends StatefulWidget {
  final String templateId;
  const WorkflowEditorScreen({super.key, required this.templateId});

  @override
  State<WorkflowEditorScreen> createState() => _WorkflowEditorScreenState();
}

class _WorkflowEditorScreenState extends State<WorkflowEditorScreen> {
  late List<Map<String, dynamic>> _steps;
  String? _sampleSubmitterJobTitleId;
  bool _dirty = false;
  bool _saving = false;

  FormTemplate? get _template {
    final repo = MockRepository();
    try {
      return repo.formTemplates.firstWhere((t) => t.id == widget.templateId);
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    final t = _template;
    _steps = t == null
        ? <Map<String, dynamic>>[]
        : t.workflow.map((s) => Map<String, dynamic>.from(s)).toList();
    final repo = MockRepository();
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

  void _markDirty() => setState(() => _dirty = true);

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = _steps.removeAt(oldIndex);
      _steps.insert(newIndex, item);
      _renumber();
      _dirty = true;
    });
  }

  void _renumber() {
    for (var i = 0; i < _steps.length; i++) {
      _steps[i]['step'] = i;
    }
  }

  void _addStep() async {
    final added = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardTheme.color,
      builder: (_) => const _StepEditorSheet(
        initial: <String, dynamic>{
          'actor_type': 'auto_chain',
          'min_approval_power': 2,
          'label_ar': '',
          'label_en': '',
          'require_signature': true,
        },
      ),
    );
    if (added != null) {
      setState(() {
        added['step'] = _steps.length;
        _steps.add(added);
        _dirty = true;
      });
    }
  }

  void _editStep(int idx) async {
    final edited = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardTheme.color,
      builder: (_) => _StepEditorSheet(
        initial: Map<String, dynamic>.from(_steps[idx]),
      ),
    );
    if (edited != null) {
      setState(() {
        edited['step'] = idx;
        _steps[idx] = edited;
        _dirty = true;
      });
    }
  }

  void _deleteStep(int idx) async {
    final l = AppStrings.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l.confirm),
        content: Text(l.isAr
            ? 'حذف الخطوة ${idx + 1}؟'
            : 'Delete step ${idx + 1}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l.cancel)),
          ElevatedButton(
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l.delete)),
        ],
      ),
    );
    if (ok == true) {
      setState(() {
        _steps.removeAt(idx);
        _renumber();
        _dirty = true;
      });
    }
  }

  Future<void> _save() async {
    final l = AppStrings.of(context);
    final t = _template;
    if (t == null) return;
    setState(() => _saving = true);
    t.workflow = List<Map<String, dynamic>>.from(_steps);
    t.updatedAt = DateTime.now();
    final supaReady = SupabaseService().isReady;
    if (supaReady) {
      final ok = await SupabaseDataService().upsertFormTemplate(t);
      if (ok == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(SupabaseDataService().lastError ?? 'Failed to save'),
        ));
        setState(() => _saving = false);
        return;
      }
    } else {
      MockRepository().notifyListeners();
    }
    if (!mounted) return;
    setState(() {
      _dirty = false;
      _saving = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(l.savedSuccess),
    ));
  }

  Future<void> _applyPreset() async {
    final l = AppStrings.of(context);
    final preset = await showModalBottomSheet<WorkflowPreset>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardTheme.color,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(12),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                l.isAr ? 'اختر قالباً جاهزاً' : 'Pick a preset',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w800),
              ),
            ),
            ...WorkflowTemplates.all.map((p) => Card(
                  child: ListTile(
                    leading: Text(p.icon,
                        style: const TextStyle(fontSize: 22)),
                    title: Text(l.isAr ? p.nameAr : p.nameEn,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w800)),
                    subtitle: Text(
                        l.isAr ? p.descriptionAr : p.descriptionEn,
                        style: const TextStyle(fontSize: 11)),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.brand.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('${p.stepCount} ${l.isAr ? "خطوة" : "steps"}',
                          style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.brand,
                              fontWeight: FontWeight.w800)),
                    ),
                    onTap: () => Navigator.of(context).pop(p),
                  ),
                )),
          ],
        ),
      ),
    );
    if (preset == null) return;
    if (_steps.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(l.confirm),
          content: Text(l.isAr
              ? 'سيستبدل النمط الحالي بـ ${preset.stepCount} خطوة من القالب. متابعة؟'
              : 'Replace current workflow with ${preset.stepCount} preset steps?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l.cancel)),
            ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(l.isAr ? 'استبدل' : 'Replace')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() {
      _steps = preset.stepsCopy();
      _renumber();
      _dirty = true;
    });
  }

  Future<void> _clearAll() async {
    final l = AppStrings.of(context);
    if (_steps.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l.confirm),
        content: Text(l.isAr
            ? 'حذف جميع الخطوات (${_steps.length})؟'
            : 'Delete all ${_steps.length} steps?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l.cancel)),
          ElevatedButton(
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l.delete)),
        ],
      ),
    );
    if (ok == true) {
      setState(() {
        _steps.clear();
        _dirty = true;
      });
    }
  }

  Future<bool> _confirmExitIfDirty() async {
    if (!_dirty) return true;
    final l = AppStrings.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l.isAr ? 'تغييرات غير محفوظة' : 'Unsaved changes'),
        content: Text(l.isAr
            ? 'لديك تغييرات لم تُحفظ. هل تريد الخروج بدون حفظ؟'
            : 'You have unsaved changes. Exit without saving?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l.cancel)),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l.isAr ? 'خروج' : 'Exit')),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppStrings.of(context);
    final isAr = l.isAr;
    final t = _template;

    if (t == null) {
      return Scaffold(
        appBar: M7AppBar(title: l.isAr ? 'محرّر السير' : 'Workflow Editor'),
        body: EmptyState(
          icon: Icons.error_outline,
          message: isAr ? 'القالب غير موجود' : 'Template not found',
        ),
      );
    }

    // معاينة الحلّ لكل خطوة (preview chain)
    final repo = MockRepository();
    final previewTpl = FormTemplate(
      id: t.id,
      code: t.code,
      nameAr: t.nameAr,
      nameEn: t.nameEn,
      workflow: List<Map<String, dynamic>>.from(_steps),
    );
    final chain = WorkflowEngine.previewChain(
      template: previewTpl,
      sampleSubmitterJobTitleId: _sampleSubmitterJobTitleId,
    );
    final unresolvedCount =
        chain.where((c) => c.match?.isResolved != true).length;

    return WillPopScope(
      onWillPop: _confirmExitIfDirty,
      child: Scaffold(
        appBar: M7AppBar(
          title: isAr ? 'محرّر السير' : 'Workflow Editor',
          subtitle: isAr ? t.nameAr : t.nameEn,
          actions: [
            M7AppBarAction(
              icon: Icons.layers_outlined,
              tooltip: isAr ? 'تطبيق قالب' : 'Apply preset',
              onPressed: _applyPreset,
            ),
            M7AppBarAction(
              icon: Icons.delete_sweep_outlined,
              tooltip: isAr ? 'مسح الكل' : 'Clear all',
              onPressed: _steps.isEmpty ? null : _clearAll,
            ),
          ],
        ),
        body: Column(
          children: [
            // ===== Header مع معلومات القالب =====
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color,
                border: Border(
                  bottom: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.brand.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(t.code,
                            style: const TextStyle(
                                fontSize: 11,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w800,
                                color: AppColors.brand)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isAr ? t.nameAr : t.nameEn,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w800),
                        ),
                      ),
                      _MiniPill(
                        label:
                            '${_steps.length} ${isAr ? "خطوة" : "steps"}',
                        color: AppColors.brand,
                        icon: Icons.timeline,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // محاكاة المُقدِّم — لرؤية حلّ الخطوات
                  DropdownButtonFormField<String>(
                    value: _sampleSubmitterJobTitleId,
                    isDense: true,
                    decoration: InputDecoration(
                      labelText:
                          isAr ? 'محاكاة مُقدِّم بمسمّى' : 'Simulate submitter',
                      isDense: true,
                      prefixIcon: const Icon(Icons.person_search, size: 18),
                    ),
                    items: repo.jobTitles
                        .map((jt) => DropdownMenuItem(
                              value: jt.id,
                              child: Text(
                                  '${jt.displayName(isAr)} ${jt.level > 0 ? "(L${jt.level})" : ""}',
                                  style: const TextStyle(fontSize: 11)),
                            ))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _sampleSubmitterJobTitleId = v),
                  ),
                  if (unresolvedCount > 0) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: AppColors.danger.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber,
                              color: AppColors.danger, size: 14),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              isAr
                                  ? '$unresolvedCount خطوة لا تُحلّ مع هذا المُقدِّم'
                                  : '$unresolvedCount step(s) unresolved for this submitter',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.danger,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // ===== قائمة الخطوات (drag-drop) =====
            Expanded(
              child: _steps.isEmpty
                  ? _EmptyEditorState(onAddStep: _addStep, isAr: isAr)
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _steps.length,
                      onReorder: _reorder,
                      itemBuilder: (_, i) => _StepCard(
                        key: ValueKey('step_$i'),
                        index: i,
                        step: _steps[i],
                        chainStep: i < chain.length ? chain[i] : null,
                        isAr: isAr,
                        onEdit: () => _editStep(i),
                        onDelete: () => _deleteStep(i),
                      ),
                    ),
            ),
            // ===== شريط الأزرار السفلي =====
            SafeArea(
              top: false,
              child: Container(
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
                      child: OutlinedButton.icon(
                        onPressed: _addStep,
                        icon: const Icon(Icons.add, size: 16),
                        label: Text(isAr ? 'خطوة جديدة' : 'Add Step'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: (_dirty && !_saving) ? _save : null,
                        icon: _saving
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.save, size: 16),
                        label: Text(_dirty
                            ? l.save
                            : (isAr ? 'محفوظ' : 'Saved')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// بطاقة خطوة (Drag handle + إعدادات + معاينة الحلّ)
// ============================================================
class _StepCard extends StatelessWidget {
  final int index;
  final Map<String, dynamic> step;
  final ChainStep? chainStep;
  final bool isAr;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _StepCard({
    required Key key,
    required this.index,
    required this.step,
    required this.chainStep,
    required this.isAr,
    required this.onEdit,
    required this.onDelete,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final actorType = (step['actor_type'] as String?) ?? 'role';
    final labelAr = (step['label_ar'] as String?) ?? '';
    final labelEn = (step['label_en'] as String?) ?? '';
    final label = isAr ? labelAr : labelEn;
    final iconType = _typeIcon(actorType);
    final summary = _summary(step, isAr);
    final resolved = chainStep?.match?.isResolved ?? false;
    final resolvedLabel = chainStep?.match?.displayName(isAr) ?? '—';
    final color = resolved ? AppColors.success : AppColors.warning;

    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            // مقبض السحب + رقم
            Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.brand.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Text('${index + 1}',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: AppColors.brand)),
                ),
                const SizedBox(height: 4),
                ReorderableDragStartListener(
                  index: index,
                  child: Icon(Icons.drag_handle,
                      size: 18, color: Theme.of(context).disabledColor),
                ),
              ],
            ),
            const SizedBox(width: 10),
            // المحتوى
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(iconType.$1, size: 14, color: iconType.$2),
                      const SizedBox(width: 4),
                      Text(_actorLabel(actorType, isAr),
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: iconType.$2)),
                      const SizedBox(width: 8),
                      if (step['require_signature'] == true)
                        const Icon(Icons.draw_outlined,
                            size: 12, color: AppColors.brand),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label.isEmpty
                        ? (isAr ? '— بلا تسمية' : '— No label')
                        : label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: label.isEmpty
                          ? Theme.of(context).disabledColor
                          : null,
                    ),
                  ),
                  if (summary.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(summary,
                        style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textTertiaryLight)),
                  ],
                  // معاينة الحلّ
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: color.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                            resolved ? Icons.check_circle : Icons.warning_amber,
                            size: 11,
                            color: color),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            resolvedLabel,
                            style: TextStyle(
                                fontSize: 10,
                                color: color,
                                fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // أزرار
            Column(
              children: [
                IconButton(
                    icon: const Icon(Icons.edit, size: 18),
                    visualDensity: VisualDensity.compact,
                    onPressed: onEdit),
                IconButton(
                    icon: const Icon(Icons.delete,
                        size: 18, color: AppColors.danger),
                    visualDensity: VisualDensity.compact,
                    onPressed: onDelete),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static (IconData, Color) _typeIcon(String t) {
    switch (t) {
      case 'auto_chain':
        return (Icons.escalator, AppColors.brand);
      case 'specific':
        return (Icons.person, AppColors.success);
      case 'role':
      default:
        return (Icons.shield_outlined, AppColors.warning);
    }
  }

  static String _actorLabel(String t, bool isAr) {
    switch (t) {
      case 'auto_chain':
        return isAr ? 'صعود الهرم' : 'Auto-chain';
      case 'specific':
        return isAr ? 'موظف محدّد' : 'Specific';
      case 'role':
      default:
        return isAr ? 'دور' : 'Role';
    }
  }

  static String _summary(Map<String, dynamic> step, bool isAr) {
    final actorType = (step['actor_type'] as String?) ?? 'role';
    switch (actorType) {
      case 'auto_chain':
        final p = step['min_approval_power'] ?? 1;
        return isAr ? 'قوّة موافقة ≥ $p' : 'Approval power ≥ $p';
      case 'role':
        final r = step['role'] ?? '?';
        return isAr ? 'دور: $r' : 'Role: $r';
      case 'specific':
        final id = step['employee_id'] as String?;
        if (id == null) return '';
        final emp = MockRepository().employeeById(id);
        return emp == null ? id : (isAr ? 'موظف: ${emp.fullName}' : 'Emp: ${emp.fullName}');
      default:
        return '';
    }
  }
}

class _MiniPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  const _MiniPill(
      {required this.label, required this.color, required this.icon});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _EmptyEditorState extends StatelessWidget {
  final VoidCallback onAddStep;
  final bool isAr;
  const _EmptyEditorState({required this.onAddStep, required this.isAr});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.timeline,
                size: 60, color: AppColors.textTertiaryLight),
            const SizedBox(height: 12),
            Text(
              isAr ? 'لا توجد خطوات بعد' : 'No steps yet',
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              isAr
                  ? 'أضف خطوة يدوياً، أو طبّق قالباً جاهزاً من الأعلى.'
                  : 'Add a step manually, or apply a preset from the top bar.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: onAddStep,
              icon: const Icon(Icons.add, size: 16),
              label: Text(isAr ? 'إضافة خطوة' : 'Add Step'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// محرّر الخطوة (Sheet)
// ============================================================
class _StepEditorSheet extends StatefulWidget {
  final Map<String, dynamic> initial;
  const _StepEditorSheet({required this.initial});

  @override
  State<_StepEditorSheet> createState() => _StepEditorSheetState();
}

class _StepEditorSheetState extends State<_StepEditorSheet> {
  late String _actorType;
  late int _minPower;
  late TextEditingController _labelArCtrl;
  late TextEditingController _labelEnCtrl;
  late TextEditingController _roleCtrl;
  late bool _requireSignature;
  String? _employeeId;

  @override
  void initState() {
    super.initState();
    _actorType = (widget.initial['actor_type'] as String?) ?? 'auto_chain';
    _minPower = (widget.initial['min_approval_power'] as int?) ?? 2;
    _labelArCtrl =
        TextEditingController(text: widget.initial['label_ar'] as String? ?? '');
    _labelEnCtrl =
        TextEditingController(text: widget.initial['label_en'] as String? ?? '');
    _roleCtrl =
        TextEditingController(text: widget.initial['role'] as String? ?? '');
    _requireSignature =
        (widget.initial['require_signature'] as bool?) ?? true;
    _employeeId = widget.initial['employee_id'] as String?;
  }

  @override
  void dispose() {
    _labelArCtrl.dispose();
    _labelEnCtrl.dispose();
    _roleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppStrings.of(context);
    final isAr = l.isAr;
    final repo = MockRepository();
    final roleKeys = repo.roleDefs.map((r) => r.key).toSet().toList();

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                isAr ? 'تعديل الخطوة' : 'Edit Step',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              // النوع
              Text(isAr ? 'نوع الخطوة' : 'Step Type',
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: [
                  ChoiceChip(
                    avatar: const Icon(Icons.escalator,
                        size: 14, color: AppColors.brand),
                    label: Text(isAr ? 'صعود الهرم' : 'Auto-chain'),
                    selected: _actorType == 'auto_chain',
                    onSelected: (_) =>
                        setState(() => _actorType = 'auto_chain'),
                  ),
                  ChoiceChip(
                    avatar: const Icon(Icons.shield_outlined,
                        size: 14, color: AppColors.warning),
                    label: Text(isAr ? 'دور' : 'Role'),
                    selected: _actorType == 'role',
                    onSelected: (_) => setState(() => _actorType = 'role'),
                  ),
                  ChoiceChip(
                    avatar: const Icon(Icons.person,
                        size: 14, color: AppColors.success),
                    label: Text(isAr ? 'موظف' : 'Specific'),
                    selected: _actorType == 'specific',
                    onSelected: (_) =>
                        setState(() => _actorType = 'specific'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // التسمية
              TextField(
                controller: _labelArCtrl,
                decoration: InputDecoration(
                  labelText: isAr ? 'الوصف بالعربيّة' : 'Label (Arabic)',
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _labelEnCtrl,
                decoration: InputDecoration(
                  labelText: isAr ? 'الوصف بالإنجليزيّة' : 'Label (English)',
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              // إعدادات النوع
              if (_actorType == 'auto_chain') ...[
                Text(
                  isAr
                      ? 'الحدّ الأدنى لقوّة الموافقة'
                      : 'Minimum approval power',
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w800),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: _minPower.toDouble(),
                        min: 1,
                        max: 5,
                        divisions: 4,
                        label: '$_minPower',
                        onChanged: (v) =>
                            setState(() => _minPower = v.round()),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.brand.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('$_minPower / 5',
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppColors.brand)),
                    ),
                  ],
                ),
              ] else if (_actorType == 'role') ...[
                if (roleKeys.isEmpty)
                  Text(
                    isAr
                        ? 'لا توجد أدوار مُعرّفة — أدخل المفتاح يدوياً'
                        : 'No roles defined — enter key manually',
                    style: const TextStyle(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: AppColors.textTertiaryLight),
                  )
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: roleKeys
                        .map((k) => ChoiceChip(
                              label: Text(k,
                                  style: const TextStyle(fontSize: 11)),
                              selected: _roleCtrl.text == k,
                              onSelected: (_) =>
                                  setState(() => _roleCtrl.text = k),
                            ))
                        .toList(),
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: _roleCtrl,
                  decoration: InputDecoration(
                    labelText: isAr ? 'مفتاح الدور (key)' : 'Role key',
                    hintText: 'hr / finance / it ...',
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ] else if (_actorType == 'specific') ...[
                DropdownButtonFormField<String>(
                  value: _employeeId,
                  isDense: true,
                  decoration: InputDecoration(
                    labelText: isAr ? 'اختر موظفاً' : 'Pick employee',
                    isDense: true,
                    prefixIcon: const Icon(Icons.person, size: 18),
                  ),
                  items: repo.employees
                      .map((e) => DropdownMenuItem(
                            value: e.id,
                            child: Text('${e.fullName} (${e.code})',
                                style: const TextStyle(fontSize: 11)),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _employeeId = v),
                ),
              ],
              const SizedBox(height: 12),
              SwitchListTile(
                value: _requireSignature,
                onChanged: (v) => setState(() => _requireSignature = v),
                title: Text(
                    isAr ? 'يتطلّب توقيعاً' : 'Require signature',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700)),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l.cancel),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () {
                        // تحقّق بسيط
                        if (_actorType == 'role' &&
                            _roleCtrl.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(isAr
                                ? 'أدخل مفتاح الدور'
                                : 'Enter the role key'),
                          ));
                          return;
                        }
                        if (_actorType == 'specific' && _employeeId == null) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(isAr
                                ? 'اختر موظفاً'
                                : 'Pick an employee'),
                          ));
                          return;
                        }
                        final result = <String, dynamic>{
                          'actor_type': _actorType,
                          'label_ar': _labelArCtrl.text.trim(),
                          'label_en': _labelEnCtrl.text.trim(),
                          'require_signature': _requireSignature,
                        };
                        if (_actorType == 'auto_chain') {
                          result['min_approval_power'] = _minPower;
                        } else if (_actorType == 'role') {
                          result['role'] = _roleCtrl.text.trim();
                        } else if (_actorType == 'specific') {
                          result['employee_id'] = _employeeId;
                        }
                        Navigator.of(context).pop(result);
                      },
                      child: Text(l.save),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
