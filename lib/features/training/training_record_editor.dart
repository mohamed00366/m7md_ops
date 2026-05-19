import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';

/// محرّر سجلّ تدريب (إنشاء/تعديل)
class TrainingRecordEditor extends StatefulWidget {
  final TrainingRecord? existing;
  const TrainingRecordEditor({super.key, required this.existing});

  @override
  State<TrainingRecordEditor> createState() => _TrainingRecordEditorState();
}

class _TrainingRecordEditorState extends State<TrainingRecordEditor> {
  late TextEditingController _certCtrl;
  late TextEditingController _scoreCtrl;
  late TextEditingController _notesCtrl;
  String? _employeeId;
  String? _courseId;
  TrainingStatus _status = TrainingStatus.scheduled;
  DateTime _scheduledAt = DateTime.now();
  DateTime? _completedAt;
  bool? _passed;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _certCtrl = TextEditingController(text: e?.certificateUrl ?? '');
    _scoreCtrl = TextEditingController(
        text: e?.score == null ? '' : e!.score!.toStringAsFixed(0));
    _notesCtrl = TextEditingController(text: e?.notes ?? '');
    _employeeId = e?.employeeId;
    _courseId = e?.courseId;
    _status = e?.status ?? TrainingStatus.scheduled;
    _scheduledAt = e?.scheduledAt ?? DateTime.now();
    _completedAt = e?.completedAt;
    _passed = e?.passed;
  }

  @override
  void dispose() {
    _certCtrl.dispose();
    _scoreCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool completed) async {
    final initial = (completed ? _completedAt : _scheduledAt) ?? DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (d == null) return;
    setState(() {
      if (completed) {
        _completedAt = d;
      } else {
        _scheduledAt = d;
      }
    });
  }

  void _save() {
    final l = AppStrings.of(context);
    if (_employeeId == null || _courseId == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l.isAr
            ? 'اختر الموظف والدورة'
            : 'Pick employee and course'),
      ));
      return;
    }
    final repo = MockRepository();
    final auth = context.read<AuthProvider>();
    final r = widget.existing ??
        TrainingRecord(
          id: repo.generateId(),
          employeeId: _employeeId!,
          courseId: _courseId!,
        );
    r.status = _status;
    r.scheduledAt = _scheduledAt;
    r.completedAt = _completedAt;
    // احسب expiresAt من الدورة
    if (_completedAt != null && _status == TrainingStatus.completed) {
      final course = repo.trainingCourseById(_courseId!);
      if (course != null && course.validityMonths > 0) {
        r.expiresAt = DateTime(
          _completedAt!.year,
          _completedAt!.month + course.validityMonths,
          _completedAt!.day,
        );
      } else {
        r.expiresAt = null;
      }
    }
    r.certificateUrl =
        _certCtrl.text.trim().isEmpty ? null : _certCtrl.text.trim();
    final score = double.tryParse(_scoreCtrl.text.trim());
    r.score = score;
    r.passed = _passed;
    r.notes = _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();
    r.recordedBy =
        auth.currentUser?.employeeId ?? auth.currentUser?.id;
    r.updatedAt = DateTime.now();
    repo.upsertTrainingRecord(r);
    Navigator.of(context).pop();
  }

  void _delete() async {
    final l = AppStrings.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l.confirm),
        content: Text(l.isAr ? 'حذف هذا السجلّ؟' : 'Delete this record?'),
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
    if (ok == true && widget.existing != null) {
      MockRepository().deleteTrainingRecord(widget.existing!.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppStrings.of(context);
    final isAr = l.isAr;
    final repo = MockRepository();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null
            ? (isAr ? 'سجلّ تدريب جديد' : 'New Training Record')
            : (isAr ? 'تعديل السجلّ' : 'Edit Record')),
        actions: [
          if (widget.existing != null)
            IconButton(
              icon: const Icon(Icons.delete, color: AppColors.danger),
              onPressed: _delete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          // الموظف
          DropdownButtonFormField<String>(
            value: _employeeId,
            isDense: true,
            decoration: InputDecoration(
              labelText: isAr ? 'الموظف' : 'Employee',
              isDense: true,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.person, size: 18),
            ),
            items: repo.employees
                .where((e) => e.status == EntityStatus.active)
                .map((e) => DropdownMenuItem(
                      value: e.id,
                      child: Text('${e.fullName} (${e.code})',
                          style: const TextStyle(fontSize: 12)),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _employeeId = v),
          ),
          const SizedBox(height: 10),
          // الدورة
          DropdownButtonFormField<String>(
            value: _courseId,
            isDense: true,
            decoration: InputDecoration(
              labelText: isAr ? 'الدورة' : 'Course',
              isDense: true,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.menu_book, size: 18),
            ),
            items: repo.trainingCourses
                .where((c) => c.isActive)
                .map((c) => DropdownMenuItem(
                      value: c.id,
                      child: Text('${c.code} • ${c.displayName(isAr)}',
                          style: const TextStyle(fontSize: 12)),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _courseId = v),
          ),
          const SizedBox(height: 14),
          // الحالة
          Text(isAr ? 'الحالة' : 'Status',
              style:
                  const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: TrainingStatus.values
                .where((t) => t != TrainingStatus.expired)
                .map((t) => ChoiceChip(
                      label: Text(
                          isAr ? t.arabicLabel() : t.englishLabel(),
                          style: const TextStyle(fontSize: 11)),
                      selected: _status == t,
                      onSelected: (_) => setState(() => _status = t),
                    ))
                .toList(),
          ),
          const SizedBox(height: 14),
          // التواريخ
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickDate(false),
                  icon: const Icon(Icons.event, size: 16),
                  label: Text(
                    isAr
                        ? 'مجدولة: ${_fmt(_scheduledAt)}'
                        : 'Sched: ${_fmt(_scheduledAt)}',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickDate(true),
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: Text(
                    _completedAt == null
                        ? (isAr ? 'مكتملة: —' : 'Completed: —')
                        : (isAr
                            ? 'مكتملة: ${_fmt(_completedAt!)}'
                            : 'Done: ${_fmt(_completedAt!)}'),
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // الدرجة + النجاح
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _scoreCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: isAr ? 'الدرجة (0-100)' : 'Score (0-100)',
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    border:
                        Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Text(isAr ? 'ناجح' : 'Passed',
                          style: const TextStyle(fontSize: 11)),
                      const Spacer(),
                      Switch(
                        value: _passed ?? false,
                        onChanged: (v) => setState(() => _passed = v),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _certCtrl,
            decoration: InputDecoration(
              labelText: isAr ? 'رابط الشهادة' : 'Certificate URL',
              hintText: 'https://...',
              isDense: true,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.link, size: 18),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notesCtrl,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: isAr ? 'ملاحظات' : 'Notes',
              isDense: true,
              border: const OutlineInputBorder(),
            ),
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

  String _fmt(DateTime d) =>
      '${d.day}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
