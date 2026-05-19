import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../models/policies.dart';
import '../../repositories/mock_repository.dart';

/// 📝 Bottom Sheet لإضافة/تعديل سياسة.
///
/// يعرض حقول:
///   • العنوان (عربي + إنجليزي)
///   • الملخّص (عربي + إنجليزي)
///   • التصنيف (PolicyCategory)
///   • أقسام السياسة (PolicySection): عنوان + خطوات
///
/// عند الحفظ: يعيد كائن `Policy` جاهز للإضافة/التحديث.
/// المتّصل (PoliciesScreen) يتولّى الحفظ في الـ repository.
class PolicyEditorSheet extends StatefulWidget {
  /// إن كانت `null` → إنشاء سياسة جديدة. غير ذلك → تعديل.
  final Policy? existing;
  const PolicyEditorSheet({super.key, this.existing});

  @override
  State<PolicyEditorSheet> createState() => _PolicyEditorSheetState();
}

class _PolicyEditorSheetState extends State<PolicyEditorSheet> {
  late final TextEditingController _titleAr;
  late final TextEditingController _titleEn;
  late final TextEditingController _summaryAr;
  late final TextEditingController _summaryEn;
  late PolicyCategory _category;
  late List<_EditableSection> _sections;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _titleAr = TextEditingController(text: p?.titleAr ?? '');
    _titleEn = TextEditingController(text: p?.titleEn ?? '');
    _summaryAr = TextEditingController(text: p?.summaryAr ?? '');
    _summaryEn = TextEditingController(text: p?.summaryEn ?? '');
    _category = p?.category ?? PolicyCategory.attendance;
    _sections = (p?.sections ?? [])
        .map((s) => _EditableSection.fromSection(s))
        .toList();
  }

  @override
  void dispose() {
    _titleAr.dispose();
    _titleEn.dispose();
    _summaryAr.dispose();
    _summaryEn.dispose();
    for (final s in _sections) {
      s.dispose();
    }
    super.dispose();
  }

  void _addSection() {
    setState(() => _sections.add(_EditableSection.empty()));
  }

  void _removeSection(int idx) {
    setState(() {
      _sections[idx].dispose();
      _sections.removeAt(idx);
    });
  }

  bool get _isValid {
    if (_titleAr.text.trim().isEmpty && _titleEn.text.trim().isEmpty) {
      return false;
    }
    return true;
  }

  void _save() {
    final s = AppStrings.of(context);
    if (!_isValid) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text(
          s.isAr
              ? 'العنوان مطلوب (عربي أو إنجليزي على الأقل)'
              : 'Title is required (Arabic or English)',
        ),
      ));
      return;
    }
    final repo = MockRepository();
    final policy = Policy(
      id: widget.existing?.id ?? repo.generateId(),
      titleAr: _titleAr.text.trim().isEmpty
          ? _titleEn.text.trim()
          : _titleAr.text.trim(),
      titleEn: _titleEn.text.trim().isEmpty
          ? _titleAr.text.trim()
          : _titleEn.text.trim(),
      summaryAr: _summaryAr.text.trim(),
      summaryEn: _summaryEn.text.trim().isEmpty
          ? _summaryAr.text.trim()
          : _summaryEn.text.trim(),
      category: _category,
      updatedAt: DateTime.now(),
      sections: _sections.map((e) => e.build()).toList(),
    );
    Navigator.of(context).pop(policy);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final theme = Theme.of(context);

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
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // مقبض السحب
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // الهيدر
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
                          ? (isAr ? 'سياسة جديدة' : 'New policy')
                          : (isAr ? 'تعديل السياسة' : 'Edit policy'),
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
            // الـ form
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // التصنيف
                    Text(
                      isAr ? 'التصنيف' : 'Category',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: PolicyCategory.values
                          .where((c) => c != PolicyCategory.other)
                          .map((c) => ChoiceChip(
                                label: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(c.icon(), size: 14, color: c.color()),
                                    const SizedBox(width: 4),
                                    Text(isAr ? c.labelAr() : c.labelEn(),
                                        style: const TextStyle(fontSize: 11)),
                                  ],
                                ),
                                selected: _category == c,
                                onSelected: (_) =>
                                    setState(() => _category = c),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 14),
                    // العنوان (AR + EN)
                    TextField(
                      controller: _titleAr,
                      decoration: InputDecoration(
                        labelText: isAr ? 'العنوان (عربي)' : 'Title (Arabic)',
                        prefixIcon: const Icon(Icons.title, size: 18),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _titleEn,
                      decoration: InputDecoration(
                        labelText:
                            isAr ? 'العنوان (إنجليزي)' : 'Title (English)',
                        prefixIcon: const Icon(Icons.title, size: 18),
                      ),
                    ),
                    const SizedBox(height: 14),
                    // الملخّص (AR + EN)
                    TextField(
                      controller: _summaryAr,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: isAr ? 'الملخّص (عربي)' : 'Summary (Arabic)',
                        prefixIcon: const Icon(Icons.short_text, size: 18),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _summaryEn,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText:
                            isAr ? 'الملخّص (إنجليزي)' : 'Summary (English)',
                        prefixIcon: const Icon(Icons.short_text, size: 18),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // الأقسام
                    Row(
                      children: [
                        Text(
                          isAr ? 'الأقسام والخطوات' : 'Sections & Steps',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 12),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: _addSection,
                          icon: const Icon(Icons.add, size: 16),
                          label: Text(
                            isAr ? 'إضافة قسم' : 'Add section',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                    if (_sections.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: theme.dividerColor.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: theme.dividerColor),
                        ),
                        child: Center(
                          child: Text(
                            isAr
                                ? 'لا أقسام بعد — اضغط "إضافة قسم"'
                                : 'No sections yet — tap "Add section"',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.textTheme.bodySmall?.color,
                            ),
                          ),
                        ),
                      ),
                    for (var i = 0; i < _sections.length; i++)
                      _SectionEditor(
                        index: i,
                        section: _sections[i],
                        isAr: isAr,
                        onRemove: () => _removeSection(i),
                      ),
                  ],
                ),
              ),
            ),
            // الـ footer (Save/Cancel)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border(
                    top: BorderSide(color: theme.dividerColor)),
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
                      label: Text(
                        widget.existing == null
                            ? (isAr ? 'إضافة السياسة' : 'Create policy')
                            : (isAr ? 'حفظ التعديلات' : 'Save changes'),
                      ),
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

// ============================================================
// قسم قابل للتعديل (مع controllers)
// ============================================================
class _EditableSection {
  final TextEditingController titleAr;
  final TextEditingController titleEn;
  final TextEditingController bodyAr;
  final List<TextEditingController> stepCtrls;

  _EditableSection({
    required this.titleAr,
    required this.titleEn,
    required this.bodyAr,
    required this.stepCtrls,
  });

  factory _EditableSection.empty() => _EditableSection(
        titleAr: TextEditingController(),
        titleEn: TextEditingController(),
        bodyAr: TextEditingController(),
        stepCtrls: [],
      );

  factory _EditableSection.fromSection(PolicySection s) => _EditableSection(
        titleAr: TextEditingController(text: s.titleAr),
        titleEn: TextEditingController(text: s.titleEn),
        bodyAr: TextEditingController(text: s.bodyAr ?? ''),
        stepCtrls:
            s.stepsAr.map((step) => TextEditingController(text: step)).toList(),
      );

  void dispose() {
    titleAr.dispose();
    titleEn.dispose();
    bodyAr.dispose();
    for (final c in stepCtrls) {
      c.dispose();
    }
  }

  PolicySection build() {
    final ar = titleAr.text.trim();
    final en = titleEn.text.trim();
    final body = bodyAr.text.trim();
    final steps = stepCtrls
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    return PolicySection(
      titleAr: ar.isEmpty ? en : ar,
      titleEn: en.isEmpty ? ar : en,
      icon: Icons.article_outlined,
      bodyAr: body.isEmpty ? null : body,
      bodyEn: body.isEmpty ? null : body,
      stepsAr: steps,
      stepsEn: steps,
    );
  }
}

// ============================================================
// محرّر قسم واحد
// ============================================================
class _SectionEditor extends StatefulWidget {
  final int index;
  final _EditableSection section;
  final bool isAr;
  final VoidCallback onRemove;
  const _SectionEditor({
    required this.index,
    required this.section,
    required this.isAr,
    required this.onRemove,
  });

  @override
  State<_SectionEditor> createState() => _SectionEditorState();
}

class _SectionEditorState extends State<_SectionEditor> {
  void _addStep() {
    setState(
        () => widget.section.stepCtrls.add(TextEditingController()));
  }

  void _removeStep(int i) {
    setState(() {
      widget.section.stepCtrls[i].dispose();
      widget.section.stepCtrls.removeAt(i);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isAr = widget.isAr;
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.brand.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${isAr ? "قسم" : "Section"} ${widget.index + 1}',
                  style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppColors.brand),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: AppColors.danger),
                visualDensity: VisualDensity.compact,
                onPressed: widget.onRemove,
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: widget.section.titleAr,
            decoration: InputDecoration(
              labelText: isAr ? 'عنوان القسم (عربي)' : 'Section title (Arabic)',
              isDense: true,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: widget.section.titleEn,
            decoration: InputDecoration(
              labelText:
                  isAr ? 'عنوان القسم (إنجليزي)' : 'Section title (English)',
              isDense: true,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: widget.section.bodyAr,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: isAr ? 'وصف القسم' : 'Section description',
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                isAr ? 'الخطوات' : 'Steps',
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 11),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _addStep,
                icon: const Icon(Icons.add, size: 14),
                label: Text(isAr ? 'إضافة' : 'Add',
                    style: const TextStyle(fontSize: 10)),
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                ),
              ),
            ],
          ),
          for (var i = 0; i < widget.section.stepCtrls.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Container(
                    width: 22,
                    alignment: Alignment.center,
                    child: Text('${i + 1}.',
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w800)),
                  ),
                  Expanded(
                    child: TextField(
                      controller: widget.section.stepCtrls[i],
                      decoration: InputDecoration(
                        hintText: isAr ? 'نصّ الخطوة' : 'Step text',
                        isDense: true,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close,
                        size: 14, color: AppColors.danger),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: 28, minHeight: 28),
                    onPressed: () => _removeStep(i),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
