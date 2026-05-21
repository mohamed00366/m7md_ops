import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/m7_log.dart';
import '../../core/theme/app_colors.dart';
import '../../models/evaluation_criterion.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/m7_app_bar.dart';

/// 📊 شاشة إدارة معايير التقييم — للموظّفين/السائقين/الغرف.
///
/// • تبويبات لكلّ نوع تقييم
/// • قائمة بالمعايير مُجمَّعة بحسب الفئة
/// • زرّ إضافة معيار جديد + أزرار تعديل/حذف على كل معيار
/// • تفعيل/تعطيل سريع عبر switch
class EvaluationCriteriaScreen extends StatefulWidget {
  const EvaluationCriteriaScreen({super.key});

  @override
  State<EvaluationCriteriaScreen> createState() =>
      _EvaluationCriteriaScreenState();
}

class _EvaluationCriteriaScreenState extends State<EvaluationCriteriaScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: EvaluationTargetType.values.length, vsync: this);
    MockRepository().addListener(_onChange);
  }

  @override
  void dispose() {
    _tab.dispose();
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
    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? '⭐ مَعايير التَقييم' : '⭐ Evaluation Criteria',
      ),
      body: Column(
        children: [
          Container(
            color: Theme.of(context).cardColor,
            child: TabBar(
              controller: _tab,
              isScrollable: true,
              tabs: [
                for (final t in EvaluationTargetType.values)
                  Tab(text: isAr ? t.labelAr() : t.labelEn()),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                for (final t in EvaluationTargetType.values)
                  _CriteriaList(targetType: t),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(
          targetType: EvaluationTargetType.values[_tab.index],
        ),
        icon: const Icon(Icons.add),
        label: Text(isAr ? 'معيار جديد' : 'New criterion'),
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
      ),
    );
  }

  Future<void> _openEditor({
    required EvaluationTargetType targetType,
    EvaluationCriterion? existing,
  }) async {
    final result = await showModalBottomSheet<EvaluationCriterion>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => _CriterionEditor(
        targetType: targetType,
        existing: existing,
      ),
    );
    if (result == null) return;
    final repo = MockRepository();
    if (existing == null) {
      repo.addEvaluationCriterion(result);
      M7Log.info('EvalCriteria', 'created ${result.id}');
    } else {
      repo.updateEvaluationCriterion(result);
      M7Log.info('EvalCriteria', 'updated ${result.id}');
    }
  }
}

// ============================================================
// قائمة المعايير لنوع تقييم محدّد
// ============================================================
class _CriteriaList extends StatelessWidget {
  final EvaluationTargetType targetType;
  const _CriteriaList({required this.targetType});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final repo = MockRepository();
    // نعرض كل المعايير (مفعّلة وغير مفعّلة) حتى يمكن تعديلها
    final all = repo.evaluationCriteria
        .where((c) => c.targetType == targetType)
        .toList()
      ..sort((a, b) {
        final cmp = a.categoryKey.compareTo(b.categoryKey);
        if (cmp != 0) return cmp;
        return a.displayOrder.compareTo(b.displayOrder);
      });

    if (all.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            isAr
                ? 'لا توجد معايير — اضغط "معيار جديد" لإضافتها'
                : 'No criteria — tap "New criterion" to add',
            style: TextStyle(
                color: Theme.of(context).textTheme.bodySmall?.color),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // تجميع
    final grouped = <String, List<EvaluationCriterion>>{};
    for (final c in all) {
      grouped.putIfAbsent(c.categoryKey, () => []).add(c);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
      children: [
        for (final entry in grouped.entries) ...[
          // رأس الفئة
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
            child: Row(
              children: [
                Icon(Icons.folder_outlined,
                    size: 16,
                    color:
                        Theme.of(context).textTheme.bodyMedium?.color),
                const SizedBox(width: 6),
                Text(
                  isAr
                      ? entry.value.first.categoryAr
                      : entry.value.first.categoryEn,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w900),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.brand.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('${entry.value.length}',
                      style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AppColors.brand)),
                ),
              ],
            ),
          ),
          for (final c in entry.value) _CriterionTile(criterion: c),
        ],
      ],
    );
  }
}

// ============================================================
// بطاقة معيار واحد
// ============================================================
class _CriterionTile extends StatelessWidget {
  final EvaluationCriterion criterion;
  const _CriterionTile({required this.criterion});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final theme = Theme.of(context);
    final repo = MockRepository();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: criterion.enabled
                ? theme.dividerColor
                : AppColors.danger.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  isAr ? criterion.labelAr : criterion.labelEn,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: criterion.enabled
                        ? null
                        : theme.disabledColor,
                  ),
                ),
              ),
              Switch(
                value: criterion.enabled,
                onChanged: (v) {
                  criterion.enabled = v;
                  repo.updateEvaluationCriterion(criterion);
                },
              ),
              IconButton(
                icon: const Icon(Icons.edit, size: 18),
                tooltip: isAr ? 'تعديل' : 'Edit',
                visualDensity: VisualDensity.compact,
                onPressed: () =>
                    (context.findAncestorStateOfType<_EvaluationCriteriaScreenState>()!)
                        ._openEditor(
                  targetType: criterion.targetType,
                  existing: criterion,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: AppColors.danger),
                tooltip: isAr ? 'حذف' : 'Delete',
                visualDensity: VisualDensity.compact,
                onPressed: () => _confirmDelete(context),
              ),
            ],
          ),
          if ((isAr ? criterion.descAr : criterion.descEn).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                isAr ? criterion.descAr : criterion.descEn,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.textTheme.bodySmall?.color,
                  height: 1.4,
                ),
              ),
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              if (criterion.weight != 1.0) ...[
                _MetaChip(
                  icon: Icons.line_weight,
                  label: '${criterion.weight}x',
                  color: AppColors.warning,
                ),
                const SizedBox(width: 4),
              ],
              _MetaChip(
                icon: Icons.format_list_numbered,
                label: '#${criterion.displayOrder}',
                color: AppColors.info,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isAr ? 'حذف المعيار؟' : 'Delete criterion?'),
        content: Text(
          isAr
              ? 'سيُحذف "${criterion.labelAr}" نهائياً.'
              : '"${criterion.labelEn}" will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(isAr ? 'إلغاء' : 'Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(isAr ? 'حذف' : 'Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      MockRepository().deleteEvaluationCriterion(criterion.id);
      M7Log.info('EvalCriteria', 'deleted ${criterion.id}');
    }
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _MetaChip(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: color)),
        ],
      ),
    );
  }
}

// ============================================================
// محرّر معيار (Bottom Sheet)
// ============================================================
class _CriterionEditor extends StatefulWidget {
  final EvaluationTargetType targetType;
  final EvaluationCriterion? existing;
  const _CriterionEditor({
    required this.targetType,
    this.existing,
  });

  @override
  State<_CriterionEditor> createState() => _CriterionEditorState();
}

class _CriterionEditorState extends State<_CriterionEditor> {
  late final TextEditingController _categoryAr;
  late final TextEditingController _categoryEn;
  late final TextEditingController _labelAr;
  late final TextEditingController _labelEn;
  late final TextEditingController _descAr;
  late final TextEditingController _descEn;
  late final TextEditingController _weight;
  late final TextEditingController _order;
  String? _categoryKey;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _categoryAr = TextEditingController(text: c?.categoryAr ?? '');
    _categoryEn = TextEditingController(text: c?.categoryEn ?? '');
    _labelAr = TextEditingController(text: c?.labelAr ?? '');
    _labelEn = TextEditingController(text: c?.labelEn ?? '');
    _descAr = TextEditingController(text: c?.descAr ?? '');
    _descEn = TextEditingController(text: c?.descEn ?? '');
    _weight = TextEditingController(text: (c?.weight ?? 1.0).toString());
    _order = TextEditingController(text: (c?.displayOrder ?? 0).toString());
    _categoryKey = c?.categoryKey;
  }

  @override
  void dispose() {
    _categoryAr.dispose();
    _categoryEn.dispose();
    _labelAr.dispose();
    _labelEn.dispose();
    _descAr.dispose();
    _descEn.dispose();
    _weight.dispose();
    _order.dispose();
    super.dispose();
  }

  void _save() {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    if (_labelAr.text.trim().isEmpty && _labelEn.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text(isAr ? 'الاسم مطلوب' : 'Label is required'),
      ));
      return;
    }
    if (_categoryAr.text.trim().isEmpty && _categoryEn.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text(isAr ? 'الفئة مطلوبة' : 'Category is required'),
      ));
      return;
    }
    final repo = MockRepository();
    final categoryAr = _categoryAr.text.trim().isEmpty
        ? _categoryEn.text.trim()
        : _categoryAr.text.trim();
    final categoryEn = _categoryEn.text.trim().isEmpty
        ? _categoryAr.text.trim()
        : _categoryEn.text.trim();
    // إن لم يُعطَ categoryKey، نشتقّه من الفئة الإنجليزيّة
    final key = _categoryKey ??
        categoryEn
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
            .replaceAll(RegExp(r'_+'), '_')
            .replaceAll(RegExp(r'^_|_$'), '');

    final criterion = EvaluationCriterion(
      id: widget.existing?.id ?? repo.generateId(),
      targetType: widget.targetType,
      categoryKey: key.isEmpty ? 'other' : key,
      categoryAr: categoryAr,
      categoryEn: categoryEn,
      labelAr: _labelAr.text.trim().isEmpty
          ? _labelEn.text.trim()
          : _labelAr.text.trim(),
      labelEn: _labelEn.text.trim().isEmpty
          ? _labelAr.text.trim()
          : _labelEn.text.trim(),
      descAr: _descAr.text.trim(),
      descEn: _descEn.text.trim(),
      weight: double.tryParse(_weight.text) ?? 1.0,
      displayOrder: int.tryParse(_order.text) ?? 0,
      enabled: widget.existing?.enabled ?? true,
    );
    Navigator.of(context).pop(criterion);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final theme = Theme.of(context);
    final repo = MockRepository();

    // suggested categories من الموجودة
    final suggested = repo.evaluationCriteria
        .where((c) => c.targetType == widget.targetType)
        .map((c) => MapEntry(c.categoryKey, isAr ? c.categoryAr : c.categoryEn))
        .toSet()
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(18)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      child: Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Icon(
                    widget.existing == null
                        ? Icons.add_circle_outline
                        : Icons.edit_outlined,
                    color: AppColors.brand,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.existing == null
                          ? (isAr ? 'معيار جديد' : 'New criterion')
                          : (isAr ? 'تعديل المعيار' : 'Edit criterion'),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w900),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // الفئة
                    Text(
                      isAr ? 'الفئة' : 'Category',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    if (suggested.isNotEmpty)
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: suggested.map((e) {
                          return ActionChip(
                            label: Text(e.value,
                                style: const TextStyle(fontSize: 10)),
                            onPressed: () {
                              setState(() {
                                _categoryKey = e.key;
                                final c = repo.evaluationCriteria.firstWhere(
                                    (x) => x.categoryKey == e.key &&
                                        x.targetType ==
                                            widget.targetType);
                                _categoryAr.text = c.categoryAr;
                                _categoryEn.text = c.categoryEn;
                              });
                            },
                          );
                        }).toList(),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _categoryAr,
                            decoration: InputDecoration(
                              labelText:
                                  isAr ? 'الفئة (عربي)' : 'Category (AR)',
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _categoryEn,
                            decoration: InputDecoration(
                              labelText: isAr
                                  ? 'الفئة (إنجليزي)'
                                  : 'Category (EN)',
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // الاسم
                    Text(
                      isAr ? 'اسم المعيار' : 'Criterion Label',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _labelAr,
                            decoration: InputDecoration(
                              labelText: isAr ? 'عربي' : 'Arabic',
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _labelEn,
                            decoration: InputDecoration(
                              labelText: isAr ? 'إنجليزي' : 'English',
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // الوصف
                    Text(
                      isAr ? 'الوصف (يظهر تحت الاسم)' : 'Description',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _descAr,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: isAr ? 'عربي' : 'Arabic',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _descEn,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: isAr ? 'إنجليزي' : 'English',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 14),
                    // الوزن + الترتيب
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _weight,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: isAr ? 'الوزن' : 'Weight',
                              hintText: '1.0',
                              isDense: true,
                              prefixIcon: const Icon(
                                  Icons.line_weight, size: 16),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _order,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: isAr ? 'ترتيب العرض' : 'Order',
                              hintText: '0',
                              isDense: true,
                              prefixIcon: const Icon(
                                  Icons.format_list_numbered, size: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border:
                    Border(top: BorderSide(color: theme.dividerColor)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(isAr ? 'إلغاء' : 'Cancel'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _save,
                      icon: Icon(
                        widget.existing == null
                            ? Icons.add
                            : Icons.check,
                        size: 16,
                      ),
                      label: Text(widget.existing == null
                          ? (isAr ? 'إضافة' : 'Add')
                          : (isAr ? 'حفظ' : 'Save')),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
