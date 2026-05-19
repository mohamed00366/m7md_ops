import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/training_settings.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';

/// محرّر دورة تدريبيّة (إنشاء/تعديل)
class TrainingCourseEditor extends StatefulWidget {
  final TrainingCourse? existing;
  const TrainingCourseEditor({super.key, this.existing});

  @override
  State<TrainingCourseEditor> createState() => _TrainingCourseEditorState();
}

class _TrainingCourseEditorState extends State<TrainingCourseEditor> {
  late TextEditingController _codeCtrl;
  late TextEditingController _nameArCtrl;
  late TextEditingController _nameEnCtrl;
  late TextEditingController _descArCtrl;
  late TextEditingController _descEnCtrl;
  late TextEditingController _durationCtrl;
  late TextEditingController _attachmentCtrl;
  late TrainingCategory _category;
  late int _validityMonths;
  late bool _isMandatory;
  late bool _isActive;
  late Set<String> _requiredJobTitleIds;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _codeCtrl = TextEditingController(text: e?.code ?? '');
    _nameArCtrl = TextEditingController(text: e?.nameAr ?? '');
    _nameEnCtrl = TextEditingController(text: e?.nameEn ?? '');
    _descArCtrl = TextEditingController(text: e?.descriptionAr ?? '');
    _descEnCtrl = TextEditingController(text: e?.descriptionEn ?? '');
    _durationCtrl = TextEditingController(
        text: e?.durationHours.toStringAsFixed(0) ?? '8');
    _attachmentCtrl = TextEditingController(text: e?.attachmentUrl ?? '');
    _category = e?.category ?? TrainingCategory.other;
    _validityMonths = e?.validityMonths ??
        TrainingSettings.instance.defaultValidityMonthsValue;
    _isMandatory = e?.isMandatory ?? false;
    _isActive = e?.isActive ?? true;
    _requiredJobTitleIds = (e?.requiredForJobTitleIds ?? []).toSet();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameArCtrl.dispose();
    _nameEnCtrl.dispose();
    _descArCtrl.dispose();
    _descEnCtrl.dispose();
    _durationCtrl.dispose();
    _attachmentCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final l = AppStrings.of(context);
    if (_codeCtrl.text.trim().isEmpty ||
        (_nameArCtrl.text.trim().isEmpty && _nameEnCtrl.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l.isAr ? 'الكود والاسم مطلوبان' : 'Code and name required'),
      ));
      return;
    }
    final repo = MockRepository();
    final c = widget.existing ??
        TrainingCourse(
          id: repo.generateId(),
          code: '',
          nameAr: '',
          nameEn: '',
        );
    c.code = _codeCtrl.text.trim();
    c.nameAr = _nameArCtrl.text.trim().isEmpty
        ? _nameEnCtrl.text.trim()
        : _nameArCtrl.text.trim();
    c.nameEn = _nameEnCtrl.text.trim().isEmpty
        ? _nameArCtrl.text.trim()
        : _nameEnCtrl.text.trim();
    c.descriptionAr = _descArCtrl.text.trim().isEmpty
        ? null
        : _descArCtrl.text.trim();
    c.descriptionEn = _descEnCtrl.text.trim().isEmpty
        ? null
        : _descEnCtrl.text.trim();
    c.category = _category;
    c.durationHours =
        double.tryParse(_durationCtrl.text.trim()) ?? 0;
    c.validityMonths = _validityMonths;
    c.isMandatory = _isMandatory;
    c.isActive = _isActive;
    c.attachmentUrl = _attachmentCtrl.text.trim().isEmpty
        ? null
        : _attachmentCtrl.text.trim();
    c.requiredForJobTitleIds = _requiredJobTitleIds.toList();
    c.updatedAt = DateTime.now();
    repo.upsertTrainingCourse(c);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppStrings.of(context);
    final isAr = l.isAr;
    final repo = MockRepository();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null
            ? (isAr ? 'دورة جديدة' : 'New Course')
            : (isAr ? 'تعديل دورة' : 'Edit Course')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          // الكود + الفئة
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _codeCtrl,
                  decoration: InputDecoration(
                    labelText: isAr ? 'الكود' : 'Code',
                    hintText: 'SAFE-101',
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<TrainingCategory>(
                  value: _category,
                  isDense: true,
                  decoration: InputDecoration(
                    labelText: isAr ? 'الفئة' : 'Category',
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  items: TrainingCategory.values
                      .map((c) => DropdownMenuItem(
                            value: c,
                            child: Text(
                                isAr ? c.arabicLabel() : c.englishLabel(),
                                style: const TextStyle(fontSize: 12)),
                          ))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _category = v ?? TrainingCategory.other),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _nameArCtrl,
            decoration: InputDecoration(
              labelText: isAr ? 'الاسم بالعربيّة' : 'Name (Arabic)',
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _nameEnCtrl,
            decoration: InputDecoration(
              labelText: isAr ? 'الاسم بالإنجليزيّة' : 'Name (English)',
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _descArCtrl,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: isAr ? 'الوصف بالعربيّة' : 'Description (Arabic)',
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _descEnCtrl,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: isAr ? 'الوصف بالإنجليزيّة' : 'Description (English)',
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _durationCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: isAr ? 'المدّة (ساعات)' : 'Duration (h)',
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isAr
                          ? 'الصلاحيّة (شهر) — 0 = بلا انتهاء'
                          : 'Validity (months) — 0 = never',
                      style: const TextStyle(fontSize: 10),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Slider(
                            value: _validityMonths.toDouble(),
                            min: 0,
                            max: 60,
                            divisions: 12,
                            label: '$_validityMonths',
                            onChanged: (v) =>
                                setState(() => _validityMonths = v.round()),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.brand.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '$_validityMonths',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: AppColors.brand),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _attachmentCtrl,
            decoration: InputDecoration(
              labelText: isAr ? 'رابط المرفق' : 'Attachment URL',
              hintText: 'https://...',
              isDense: true,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.link, size: 18),
            ),
          ),
          const SizedBox(height: 10),
          SwitchListTile(
            value: _isMandatory,
            onChanged: (v) => setState(() => _isMandatory = v),
            title: Text(isAr ? 'إلزاميّة' : 'Mandatory',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800)),
            subtitle: Text(
              isAr
                  ? 'كل الموظفين مطالَبين بإتمامها (أو حسب المسمّيات أدناه)'
                  : 'All employees required (or specific titles below)',
              style: const TextStyle(fontSize: 11),
            ),
            contentPadding: EdgeInsets.zero,
          ),
          SwitchListTile(
            value: _isActive,
            onChanged: (v) => setState(() => _isActive = v),
            title: Text(isAr ? 'نشطة' : 'Active',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800)),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 10),
          // المسمّيات الوظيفيّة المطلوبة
          Text(
            isAr
                ? 'المسمّيات الوظيفيّة المطلوبة (فارغ = للجميع)'
                : 'Required for job titles (empty = everyone)',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: repo.jobTitles.map((jt) {
              final selected = _requiredJobTitleIds.contains(jt.id);
              return FilterChip(
                label: Text(
                    '${jt.displayName(isAr)} (L${jt.level})',
                    style: const TextStyle(fontSize: 11)),
                selected: selected,
                onSelected: (v) {
                  setState(() {
                    if (v) {
                      _requiredJobTitleIds.add(jt.id);
                    } else {
                      _requiredJobTitleIds.remove(jt.id);
                    }
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
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
                child: ElevatedButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save, size: 16),
                  label: Text(l.save),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
