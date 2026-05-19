import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/roster_settings.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../shared/m7_app_bar.dart';
import '../../shared/widgets.dart';

/// 📅 إعدادات الروسترات (داخل Settings Hub)
///
/// المحاور:
///   1. قفل الأيام السابقة (toggle + grace days)
///   2. الأنماط الجاهزة (CRUD)
///   3. السماح بفتح المعتمد للتعديل
///   4. حدود التنبيه (ساعات أسبوعية + حد أدنى للنقطة)
class RosterSettingsScreen extends StatefulWidget {
  const RosterSettingsScreen({super.key});

  @override
  State<RosterSettingsScreen> createState() => _RosterSettingsScreenState();
}

class _RosterSettingsScreenState extends State<RosterSettingsScreen> {
  final RosterSettings _s = RosterSettings.instance;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
    _s.addListener(_onChange);
  }

  @override
  void dispose() {
    _s.removeListener(_onChange);
    super.dispose();
  }

  Future<void> _init() async {
    await _s.load();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l = AppStrings.of(context);
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: M7AppBar(
        title: l.isAr ? 'إعدادات الروسترات' : 'Roster Settings',
        actions: [
          M7AppBarAction(
            icon: Icons.restart_alt,
            tooltip: l.isAr ? 'إعادة الافتراضيّ' : 'Reset to defaults',
            onPressed: _confirmReset,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _SectionLockPastDays(s: _s, l: l),
          const SizedBox(height: 12),
          _SectionPatterns(s: _s, l: l),
          const SizedBox(height: 12),
          _SectionReopen(s: _s, l: l),
          const SizedBox(height: 12),
          _SectionAlerts(s: _s, l: l),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _confirmReset() async {
    final l = AppStrings.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l.confirm),
        content: Text(l.isAr
            ? 'إعادة كل إعدادات الروسترات للقيم الافتراضيّة؟'
            : 'Reset all roster settings to defaults?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.isAr ? 'إعادة' : 'Reset'),
          ),
        ],
      ),
    );
    if (ok == true) await _s.resetToDefaults();
  }
}

// ============================================================
// 1. قفل الأيام السابقة
// ============================================================
class _SectionLockPastDays extends StatelessWidget {
  final RosterSettings s;
  final AppStrings l;
  const _SectionLockPastDays({required this.s, required this.l});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: l.isAr ? '🔒 قفل الأيام السابقة' : '🔒 Lock Past Days',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            value: s.lockEnabled,
            onChanged: s.setLockEnabled,
            title: Text(
              l.isAr ? 'تفعيل القفل' : 'Lock enabled',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              l.isAr
                  ? 'لا تسمح بتعديل الأيام التي عدّت'
                  : 'Disallow editing days that have passed',
              style: const TextStyle(fontSize: 11),
            ),
            contentPadding: EdgeInsets.zero,
          ),
          if (s.lockEnabled) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.isAr ? 'فترة السماح (أيام)' : 'Grace period (days)',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w800),
                        ),
                        Text(
                          l.isAr
                              ? '0 = اقفل من أمس فما قبل، 1 = اقفل من قبل أمس...'
                              : '0 = lock from yesterday backward; 1 = from 2d ago...',
                          style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.textTertiaryLight),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.brand.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${s.lockGraceDays}',
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: AppColors.brand),
                    ),
                  ),
                ],
              ),
            ),
            Slider(
              value: s.lockGraceDays.toDouble(),
              min: 0,
              max: 7,
              divisions: 7,
              label: '${s.lockGraceDays}',
              onChanged: (v) => s.setLockGraceDays(v.round()),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================
// 2. الأنماط الجاهزة
// ============================================================
class _SectionPatterns extends StatelessWidget {
  final RosterSettings s;
  final AppStrings l;
  const _SectionPatterns({required this.s, required this.l});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: l.isAr ? '⚡ الأنماط الجاهزة' : '⚡ Quick Patterns',
      action: TextButton.icon(
        onPressed: () => _editPattern(context, null),
        icon: const Icon(Icons.add, size: 16),
        label: Text(l.isAr ? 'إضافة' : 'Add'),
      ),
      child: s.patterns.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                l.isAr
                    ? 'لا توجد أنماط — أضف نمطاً افتراضياً'
                    : 'No patterns — add one',
                style:
                    const TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
              ),
            )
          : Column(
              children: s.patterns.map((p) {
                final activeCount =
                    p.shifts.where((sp) => sp.dayIndex >= 0).length;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_view_week,
                      color: AppColors.brand),
                  title: Text(l.isAr ? p.nameAr : p.nameEn,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    '$activeCount ${l.isAr ? "يوم عمل" : "working days"}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, size: 18),
                        onPressed: () => _editPattern(context, p),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete,
                            size: 18, color: AppColors.danger),
                        onPressed: () => _deletePattern(context, p),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  Future<void> _editPattern(
      BuildContext context, RosterPatternConfig? existing) async {
    final result = await showModalBottomSheet<RosterPatternConfig>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardTheme.color,
      builder: (_) => _PatternEditorSheet(
        existing: existing,
        l: l,
      ),
    );
    if (result == null) return;
    final newList = List<RosterPatternConfig>.from(s.patterns);
    final idx = newList.indexWhere((p) => p.id == result.id);
    if (idx >= 0) {
      newList[idx] = result;
    } else {
      newList.add(result);
    }
    await s.setPatterns(newList);
  }

  Future<void> _deletePattern(
      BuildContext context, RosterPatternConfig p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l.confirm),
        content: Text(l.isAr
            ? 'حذف النمط "${p.nameAr}"؟'
            : 'Delete pattern "${p.nameEn}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l.cancel)),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l.delete)),
        ],
      ),
    );
    if (ok != true) return;
    final newList = s.patterns.where((x) => x.id != p.id).toList();
    await s.setPatterns(newList);
  }
}

// ============================================================
// محرر النمط (sheet)
// ============================================================
class _PatternEditorSheet extends StatefulWidget {
  final RosterPatternConfig? existing;
  final AppStrings l;
  const _PatternEditorSheet({required this.existing, required this.l});

  @override
  State<_PatternEditorSheet> createState() => _PatternEditorSheetState();
}

class _PatternEditorSheetState extends State<_PatternEditorSheet> {
  late TextEditingController _nameArCtrl;
  late TextEditingController _nameEnCtrl;
  late List<ShiftSpec?> _days; // 7 entries; null = off
  late ShiftType _defaultType;
  late TimeOfDay _defaultStart;
  late TimeOfDay _defaultEnd;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameArCtrl = TextEditingController(text: e?.nameAr ?? '');
    _nameEnCtrl = TextEditingController(text: e?.nameEn ?? '');
    _days = List.generate(7, (i) => e?.shiftFor(i));
    _defaultType = ShiftType.morning;
    _defaultStart = const TimeOfDay(hour: 8, minute: 0);
    _defaultEnd = const TimeOfDay(hour: 20, minute: 0);
  }

  @override
  void dispose() {
    _nameArCtrl.dispose();
    _nameEnCtrl.dispose();
    super.dispose();
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final l = widget.l;
    final dayNames = l.isAr
        ? ['الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد']
        : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                widget.existing == null
                    ? (l.isAr ? 'نمط جديد' : 'New Pattern')
                    : (l.isAr ? 'تعديل النمط' : 'Edit Pattern'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameArCtrl,
                decoration: InputDecoration(
                  labelText: l.isAr ? 'الاسم بالعربيّة' : 'Name (Arabic)',
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nameEnCtrl,
                decoration: InputDecoration(
                  labelText: l.isAr ? 'الاسم بالإنجليزيّة' : 'Name (English)',
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              // افتراضي للورديات الجديدة
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.brand.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: AppColors.brand.withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.isAr
                          ? 'الافتراضيّ للأيام التي ستفعّلها:'
                          : 'Default for days you enable:',
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final t = await showTimePicker(
                                context: context,
                                initialTime: _defaultStart,
                              );
                              if (t != null) {
                                setState(() => _defaultStart = t);
                              }
                            },
                            child: Text('IN ${_fmt(_defaultStart)}'),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final t = await showTimePicker(
                                context: context,
                                initialTime: _defaultEnd,
                              );
                              if (t != null) {
                                setState(() => _defaultEnd = t);
                              }
                            },
                            child: Text('OUT ${_fmt(_defaultEnd)}'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      children: ShiftType.values
                          .where((t) => t != ShiftType.off)
                          .map((t) => ChoiceChip(
                                label: Text(
                                    l.isAr ? t.arabicLabel() : t.englishLabel(),
                                    style: const TextStyle(fontSize: 11)),
                                selected: t == _defaultType,
                                onSelected: (_) =>
                                    setState(() => _defaultType = t),
                              ))
                          .toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                l.isAr ? 'أيام النمط:' : 'Pattern days:',
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              ...List.generate(7, (i) {
                final spec = _days[i];
                final on = spec != null;
                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: on
                        ? AppColors.success.withOpacity(0.06)
                        : AppColors.textTertiaryLight.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                          width: 60,
                          child: Text(dayNames[i],
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w700))),
                      Switch(
                        value: on,
                        onChanged: (v) {
                          setState(() {
                            _days[i] = v
                                ? ShiftSpec(
                                    dayIndex: i,
                                    start: _fmt(_defaultStart),
                                    end: _fmt(_defaultEnd),
                                    type: _defaultType,
                                  )
                                : null;
                          });
                        },
                      ),
                      Expanded(
                        child: on
                            ? Text(
                                '${spec.start} - ${spec.end} (${l.isAr ? spec.type.arabicLabel() : spec.type.englishLabel()})',
                                style: const TextStyle(fontSize: 11))
                            : Text(
                                l.isAr ? 'إجازة' : 'Off',
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textTertiaryLight),
                              ),
                      ),
                    ],
                  ),
                );
              }),
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
                        final ar = _nameArCtrl.text.trim();
                        final en = _nameEnCtrl.text.trim();
                        if (ar.isEmpty && en.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(l.isAr
                                ? 'أدخل اسماً واحداً على الأقل'
                                : 'Enter at least one name'),
                          ));
                          return;
                        }
                        final shifts = _days
                            .where((s) => s != null)
                            .cast<ShiftSpec>()
                            .toList();
                        final result = RosterPatternConfig(
                          id: widget.existing?.id ??
                              'p_${DateTime.now().millisecondsSinceEpoch}',
                          nameAr: ar.isEmpty ? en : ar,
                          nameEn: en.isEmpty ? ar : en,
                          shifts: shifts,
                        );
                        Navigator.of(context).pop(result);
                      },
                      child: Text(l.save),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// 3. السماح بفتح المعتمد للتعديل
// ============================================================
class _SectionReopen extends StatelessWidget {
  final RosterSettings s;
  final AppStrings l;
  const _SectionReopen({required this.s, required this.l});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: l.isAr ? '🔓 فتح الروستر المعتمد' : '🔓 Reopen Approved',
      child: SwitchListTile(
        value: s.allowReopen,
        onChanged: s.setAllowReopen,
        title: Text(
          l.isAr
              ? 'السماح بفتح الروستر المعتمد للتعديل'
              : 'Allow reopening approved rosters',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          l.isAr
              ? 'إذا فُعّل: من لديه صلاحية الاعتماد يستطيع إرجاع الروستر لمراجعة + توثيق السبب'
              : 'When on, approvers can return rosters to review (with logged reason)',
          style: const TextStyle(fontSize: 11),
        ),
        contentPadding: EdgeInsets.zero,
      ),
    );
  }
}

// ============================================================
// 4. حدود التنبيه
// ============================================================
class _SectionAlerts extends StatelessWidget {
  final RosterSettings s;
  final AppStrings l;
  const _SectionAlerts({required this.s, required this.l});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: l.isAr ? '⚠️ حدود التنبيه' : '⚠️ Alert Thresholds',
      child: Column(
        children: [
          // ساعات أسبوعية قصوى
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.access_time, color: AppColors.danger),
            title: Text(
                l.isAr ? 'ساعات أسبوعية قصوى' : 'Max weekly hours',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(
              l.isAr
                  ? 'تحذير عند تجاوز هذا الحد لأي موظف'
                  : 'Warn when any employee exceeds this',
              style: const TextStyle(fontSize: 11),
            ),
            trailing: _NumStepper(
              value: s.maxWeekly,
              min: 1,
              max: 168,
              step: 5,
              onChanged: s.setMaxWeekly,
              suffix: 'h',
            ),
          ),
          const Divider(),
          // حد أدنى لعدد الموظفين بالنقطة
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.group_outlined, color: AppColors.warning),
            title: Text(
                l.isAr
                    ? 'حد أدنى لموظفي النقطة'
                    : 'Min staff per point',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(
              l.isAr
                  ? 'تنبيه إذا كان عدد موظفي نقطة أقل من هذا'
                  : 'Alert when a point has fewer employees',
              style: const TextStyle(fontSize: 11),
            ),
            trailing: _NumStepper(
              value: s.minStaff,
              min: 0,
              max: 50,
              step: 1,
              onChanged: s.setMinStaff,
            ),
          ),
        ],
      ),
    );
  }
}

class _NumStepper extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final int step;
  final String? suffix;
  final ValueChanged<int> onChanged;
  const _NumStepper({
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
    this.suffix,
  });
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: value > min
              ? () => onChanged((value - step).clamp(min, max))
              : null,
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.brand.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$value${suffix ?? ''}',
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: AppColors.brand),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: value < max
              ? () => onChanged((value + step).clamp(min, max))
              : null,
        ),
      ],
    );
  }
}
