import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/supabase_data_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../models/models.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/widgets.dart';
import 'daily_memo_report.dart';

/// 📋 شاشة "مذكّرتي اليوميّة" — الموظّف يَكتب نَشاطَه بنفسه.
///
/// - يَختار اليوم.
/// - يُضيف سطراً واحداً أو أكثر: نقطة + بداية + نهاية + ملاحظة.
/// - النظام يَحسب مَجموع الساعات تلقائيّاً.
/// - يُنبّه عند تَداخُل سُطور.
/// - يُقفَل تلقائيّاً بَعد منتصف الليل بـ24 ساعة.
/// - يُقارن مع الروستر المعتمد (لو موجود) ويُظهر الفَرق.
class EmployeeDailyMemoScreen extends StatefulWidget {
  const EmployeeDailyMemoScreen({super.key});

  @override
  State<EmployeeDailyMemoScreen> createState() =>
      _EmployeeDailyMemoScreenState();
}

class _EmployeeDailyMemoScreenState extends State<EmployeeDailyMemoScreen> {
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date = DateTime(now.year, now.month, now.day);
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

  String _fmtDate(DateTime d) =>
      '${d.day}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 60)),
      lastDate: DateTime.now().add(const Duration(days: 7)),
    );
    if (picked != null) {
      setState(() => _date = DateTime(picked.year, picked.month, picked.day));
    }
  }

  Future<void> _addEntry() async {
    final s = AppStrings.of(context);
    final result = await showModalBottomSheet<_EntryFormResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardTheme.color,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _EntryForm(isAr: s.isAr),
    );
    if (result == null) return;

    final auth = context.read<AuthProvider>();
    final empId = auth.currentUser?.employeeId;
    if (empId == null) return;
    final ds = SupabaseDataService();

    // 1) محلّيّاً
    MockRepository().addDailyMemoEntry(
      employeeId: empId,
      date: _date,
      pointId: result.pointId,
      startTime: result.startTime,
      endTime: result.endTime,
      notes: result.notes,
    );

    // 2) Supabase
    if (ds.isSynced) {
      final saved = await ds.addDailyMemoEntryRemote(
        employeeId: empId,
        date: _date,
        pointId: result.pointId,
        startTime: result.startTime,
        endTime: result.endTime,
        notes: result.notes,
      );
      if (saved == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.warning,
          content: Text(
            s.isAr
                ? 'حُفظ محلّيّاً فقط — تأكّد من تطبيق migration'
                : 'Saved locally only — apply migration',
          ),
        ));
      }
    }
  }

  Future<void> _editEntry(EmployeeDailyMemo memo, EmployeeDailyMemoEntry e) async {
    final s = AppStrings.of(context);
    final result = await showModalBottomSheet<_EntryFormResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardTheme.color,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _EntryForm(isAr: s.isAr, initial: e),
    );
    if (result == null) return;

    final ds = SupabaseDataService();
    MockRepository().updateDailyMemoEntry(
      memoId: memo.id,
      entryId: e.id,
      pointId: result.pointId,
      startTime: result.startTime,
      endTime: result.endTime,
      notes: result.notes,
    );
    if (ds.isSynced) {
      await ds.updateDailyMemoEntryRemote(
        memoId: memo.id,
        entryId: e.id,
        pointId: result.pointId,
        startTime: result.startTime,
        endTime: result.endTime,
        notes: result.notes,
      );
    }
  }

  Future<void> _deleteEntry(
      EmployeeDailyMemo memo, EmployeeDailyMemoEntry e) async {
    final s = AppStrings.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(s.isAr ? 'حذف السطر؟' : 'Delete entry?'),
        content: Text(s.isAr
            ? 'سَيُحذَف هذا السطر نهائيّاً.'
            : 'This entry will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(s.isAr ? 'إلغاء' : 'Cancel'),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(s.isAr ? 'حذف' : 'Delete',
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final ds = SupabaseDataService();
    MockRepository().deleteDailyMemoEntry(memoId: memo.id, entryId: e.id);
    if (ds.isSynced) {
      await ds.deleteDailyMemoEntryRemote(memoId: memo.id, entryId: e.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final auth = context.watch<AuthProvider>();
    final repo = MockRepository();

    final canCreate = auth.isSuperAdmin ||
        auth.permissions.contains(P.dailyMemoCreate);
    final canView = auth.isSuperAdmin ||
        auth.permissions.contains(P.dailyMemoView) ||
        canCreate;

    if (!canView) {
      return Scaffold(
        appBar: AppBar(
          title: Text(isAr ? 'مذكّرتي اليوميّة' : 'My Daily Memo'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              isAr
                  ? 'لا تَملك صلاحية الوصول إلى هذه الشاشة.'
                  : 'You do not have permission to access this screen.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final empId = auth.currentUser?.employeeId;
    if (empId == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(isAr ? 'مذكّرتي اليوميّة' : 'My Daily Memo'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              isAr
                  ? 'هذه الشاشة مخصصة للموظفين (المستخدم ليس مرتبطاً بسجل موظف)'
                  : 'This screen is for employees (no linked employee).',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final memo = repo.findDailyMemo(employeeId: empId, date: _date);
    final entries = memo?.entries ?? [];
    final totalHours = memo?.totalHours ?? 0;
    final hasOverlap = memo?.hasOverlap ?? false;
    final isLocked = memo == null ? false : repo.isDailyMemoLocked(memo);
    final rosterHours =
        repo.rosterHoursFor(employeeId: empId, date: _date);
    final diff = totalHours - rosterHours;

    return Scaffold(
      appBar: AppBar(
        title: Text(isAr ? 'مذكّرتي اليوميّة' : 'My Daily Memo'),
        actions: [
          if (auth.isSuperAdmin ||
              auth.permissions.contains(P.dailyMemoReportView))
            IconButton(
              tooltip: isAr ? 'التقرير' : 'Report',
              icon: const Icon(Icons.assessment_outlined),
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const DailyMemoReportScreen(),
                ));
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
        children: [
          // ===== مَنتقى التاريخ =====
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: ListTile(
              leading: const Icon(Icons.event, color: AppColors.brand),
              title: Text(_fmtDate(_date),
                  style: const TextStyle(fontWeight: FontWeight.w900)),
              subtitle: Text(isAr ? 'التاريخ' : 'Date',
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
              trailing: Wrap(
                spacing: 4,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => setState(
                        () => _date = _date.subtract(const Duration(days: 1))),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => setState(
                        () => _date = _date.add(const Duration(days: 1))),
                  ),
                  IconButton(
                    icon: const Icon(Icons.calendar_month),
                    onPressed: _pickDate,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ===== KPIs =====
          Row(
            children: [
              Expanded(
                child: _Kpi(
                  color: AppColors.brand,
                  icon: Icons.list_alt,
                  label: isAr ? 'سُطور' : 'Entries',
                  value: '${entries.length}',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Kpi(
                  color: AppColors.success,
                  icon: Icons.schedule,
                  label: isAr ? 'ساعات' : 'Hours',
                  value: totalHours.toStringAsFixed(1),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Kpi(
                  color: diff.abs() < 0.05
                      ? AppColors.success
                      : (diff > 0 ? AppColors.info : AppColors.warning),
                  icon: diff > 0
                      ? Icons.trending_up
                      : (diff < 0
                          ? Icons.trending_down
                          : Icons.horizontal_rule),
                  label: isAr ? 'مقابل الروستر' : 'vs Roster',
                  value: diff > 0
                      ? '+${diff.toStringAsFixed(1)}'
                      : diff.toStringAsFixed(1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // ===== تَنبيهات =====
          if (isLocked) _LockedBanner(isAr: isAr),
          if (hasOverlap) _OverlapBanner(isAr: isAr),
          if (totalHours > 16) _TooManyHoursBanner(isAr: isAr),

          const SizedBox(height: 12),

          // ===== السُطور =====
          SectionCard(
            title: isAr ? 'سُطور المذكّرة' : 'Memo Entries',
            child: entries.isEmpty
                ? EmptyState(
                    icon: Icons.note_add_outlined,
                    message: isAr
                        ? 'لا يوجد سُطور لهذا اليوم — أَضِف سطراً'
                        : 'No entries yet — add one',
                  )
                : Column(
                    children: entries.map((e) {
                      final point = repo.pointById(e.pointId);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.bgLight,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.brand.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.place,
                                  color: AppColors.brand, size: 18),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(point?.name ?? '—',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13)),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${e.startTime} → ${e.endTime}  •  ${e.hours.toStringAsFixed(1)} ${isAr ? "ساعة" : "h"}',
                                    style: const TextStyle(
                                        fontSize: 11, color: Colors.grey),
                                  ),
                                  if ((e.notes ?? '').isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(e.notes!,
                                          style: const TextStyle(
                                              fontSize: 11,
                                              fontStyle: FontStyle.italic)),
                                    ),
                                ],
                              ),
                            ),
                            if (!isLocked && canCreate) ...[
                              IconButton(
                                tooltip: isAr ? 'تَعديل' : 'Edit',
                                iconSize: 18,
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () =>
                                    _editEntry(memo!, e),
                              ),
                              IconButton(
                                tooltip: isAr ? 'حذف' : 'Delete',
                                iconSize: 18,
                                icon: const Icon(Icons.delete_outline,
                                    color: AppColors.danger),
                                onPressed: () =>
                                    _deleteEntry(memo!, e),
                              ),
                            ],
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
      floatingActionButton: (canCreate && !isLocked)
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.brand,
              onPressed: _addEntry,
              icon: const Icon(Icons.add, color: Colors.white),
              label: Text(isAr ? 'إضافة سطر' : 'Add Entry',
                  style: const TextStyle(color: Colors.white)),
            )
          : null,
    );
  }
}

// ============================================================
// 📝 فورم إضافة/تَعديل سطر
// ============================================================
class _EntryFormResult {
  final String pointId;
  final String startTime;
  final String endTime;
  final String? notes;
  _EntryFormResult({
    required this.pointId,
    required this.startTime,
    required this.endTime,
    this.notes,
  });
}

class _EntryForm extends StatefulWidget {
  final bool isAr;
  final EmployeeDailyMemoEntry? initial;
  const _EntryForm({required this.isAr, this.initial});

  @override
  State<_EntryForm> createState() => _EntryFormState();
}

class _EntryFormState extends State<_EntryForm> {
  String? _pointId;
  TimeOfDay? _start;
  TimeOfDay? _end;
  final _notesCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      _pointId = widget.initial!.pointId;
      _start = _parseHHmm(widget.initial!.startTime);
      _end = _parseHHmm(widget.initial!.endTime);
      _notesCtrl.text = widget.initial!.notes ?? '';
    }
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  TimeOfDay? _parseHHmm(String s) {
    final p = s.split(':');
    if (p.length < 2) return null;
    final h = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  String _fmtTOD(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickStart() async {
    final t = await showTimePicker(
      context: context,
      initialTime: _start ?? TimeOfDay.now(),
    );
    if (t != null) setState(() => _start = t);
  }

  Future<void> _pickEnd() async {
    final t = await showTimePicker(
      context: context,
      initialTime: _end ?? TimeOfDay.now(),
    );
    if (t != null) setState(() => _end = t);
  }

  @override
  Widget build(BuildContext context) {
    final isAr = widget.isAr;
    final repo = MockRepository();
    final auth = context.read<AuthProvider>();
    final activePoints = auth
        .filterByCountry(repo.points, (p) => p.countryId)
        .where((p) => p.status == EntityStatus.active)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final canSave = _pointId != null && _start != null && _end != null;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.note_add, color: AppColors.brand),
              const SizedBox(width: 8),
              Text(
                widget.initial == null
                    ? (isAr ? 'إضافة سطر' : 'Add Entry')
                    : (isAr ? 'تَعديل سطر' : 'Edit Entry'),
                style: const TextStyle(
                    fontWeight: FontWeight.w900, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _pointId,
            decoration: InputDecoration(
              labelText: isAr ? 'النقطة' : 'Point',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.place),
            ),
            items: activePoints
                .map((p) => DropdownMenuItem(
                      value: p.id,
                      child: Text(p.name),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _pointId = v),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.access_time),
                  label: Text(_start == null
                      ? (isAr ? 'وقت البدء' : 'Start')
                      : _fmtTOD(_start!)),
                  onPressed: _pickStart,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.access_time_filled),
                  label: Text(_end == null
                      ? (isAr ? 'وقت النهاية' : 'End')
                      : _fmtTOD(_end!)),
                  onPressed: _pickEnd,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _notesCtrl,
            decoration: InputDecoration(
              labelText: isAr ? 'ملاحظة (اختياريّ)' : 'Notes (optional)',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.notes),
            ),
            minLines: 1,
            maxLines: 3,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(isAr ? 'إلغاء' : 'Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: canSave
                      ? () => Navigator.of(context).pop(_EntryFormResult(
                            pointId: _pointId!,
                            startTime: _fmtTOD(_start!),
                            endTime: _fmtTOD(_end!),
                            notes: _notesCtrl.text.trim().isEmpty
                                ? null
                                : _notesCtrl.text.trim(),
                          ))
                      : null,
                  icon: const Icon(Icons.check),
                  label: Text(isAr ? 'حفظ' : 'Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 🔔 شارات / Banners
// ============================================================
class _LockedBanner extends StatelessWidget {
  final bool isAr;
  const _LockedBanner({required this.isAr});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade400),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock, color: Colors.grey, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isAr
                  ? 'هذه المذكّرة مُقفَلة (مَضى أكثر من 24 ساعة على نهاية اليوم).'
                  : 'This memo is locked (more than 24h after end of day).',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}

class _OverlapBanner extends StatelessWidget {
  final bool isAr;
  const _OverlapBanner({required this.isAr});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.40)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline,
              color: AppColors.danger, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isAr
                  ? 'يوجد تَداخُل زمنيّ بين السُطور — راجِع البيانات.'
                  : 'Time overlap detected between entries — please review.',
              style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.danger,
                  fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _TooManyHoursBanner extends StatelessWidget {
  final bool isAr;
  const _TooManyHoursBanner({required this.isAr});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.40)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: AppColors.warning, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isAr
                  ? 'مَجموع الساعات تَجاوز 16 ساعة — تَأكَّد من البيانات.'
                  : 'Total exceeds 16 hours — please double-check.',
              style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.warning,
                  fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  const _Kpi({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w900)),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }
}
