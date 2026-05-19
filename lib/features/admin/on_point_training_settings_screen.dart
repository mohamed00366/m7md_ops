import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/on_point_training_settings.dart';
import '../../core/theme/app_colors.dart';
import '../../models/lookups.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/m7_app_bar.dart';
import '../../shared/widgets.dart';

/// 🎓 إعدادات صفحة "تدريب الجدد" (OnPoint Training)
///
/// يضبط المسؤول:
///   1. مدّة التدريب الافتراضيّة
///   2. مَن يحقّ له الاعتماد/التقييم (مسمّيات وظيفيّة)
///   3. التوقيعات الإلزاميّة (4 خانات اختياريّة)
///   4. إنشاء سجلّ تلقائي عند تسجيل موظف كمتدرّب
///   5. الحدّ الأدنى للمستوى المقبول (A/B/C)
class OnPointTrainingSettingsScreen extends StatefulWidget {
  const OnPointTrainingSettingsScreen({super.key});

  @override
  State<OnPointTrainingSettingsScreen> createState() =>
      _OnPointTrainingSettingsScreenState();
}

class _OnPointTrainingSettingsScreenState
    extends State<OnPointTrainingSettingsScreen> {
  final OnPointTrainingSettings _s = OnPointTrainingSettings.instance;
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

  Future<void> _confirmReset() async {
    final l = AppStrings.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l.confirm),
        content: Text(l.isAr
            ? 'إعادة كل إعدادات تدريب الجدد للقيم الافتراضيّة؟'
            : 'Reset all OnPoint training settings to defaults?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l.cancel)),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.isAr ? 'إعادة' : 'Reset'),
          ),
        ],
      ),
    );
    if (ok == true) await _s.resetToDefaults();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppStrings.of(context);
    final isAr = l.isAr;
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final repo = MockRepository();

    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? 'إعدادات تدريب الجدد' : 'OnPoint Training Settings',
        actions: [
          M7AppBarAction(
            icon: Icons.restart_alt,
            tooltip: isAr ? 'إعادة الافتراضيّ' : 'Reset',
            onPressed: _confirmReset,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // ===== 1) المدّة الافتراضيّة =====
          SectionCard(
            title: isAr ? '⏱️ مدّة التدريب الافتراضيّة' : '⏱️ Default Duration',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAr
                      ? 'كم يوماً يبقى الموظف الجديد في التدريب على النقطة؟'
                      : 'How many days a new employee trains on a point?',
                  style: const TextStyle(fontSize: 11),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: _s.defaultDaysValue.toDouble(),
                        min: 1,
                        max: 30,
                        divisions: 29,
                        label: '${_s.defaultDaysValue}',
                        onChanged: (v) =>
                            _s.setDefaultDays(v.round()),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.brand.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${_s.defaultDaysValue} ${isAr ? "يوم" : "days"}',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: AppColors.brand),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ===== 2) المعتمِدون =====
          SectionCard(
            title: isAr
                ? '✅ مَن يحقّ له الاعتماد/التقييم'
                : '✅ Who can approve/evaluate',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAr
                      ? 'حدّد المسمّيات الوظيفيّة التي يستطيع حاملوها الضغط على "اعتماد" أو "رفض" للمتدرّب.\nالافتراضيّ (لا اختيار): كل من لديه صلاحيّة التقييم.'
                      : 'Pick which job titles are allowed to approve/reject trainees.\nDefault (none selected): anyone with the evaluate permission.',
                  style: const TextStyle(fontSize: 11),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: _filteredApproverCandidates(repo).map((jt) {
                    final selected = _s.approverJobTitleIds.contains(jt.id);
                    return FilterChip(
                      label: Text(
                        '${jt.displayName(isAr)} ${jt.level > 0 ? "(L${jt.level})" : ""}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      selected: selected,
                      onSelected: (_) => _s.toggleApproverJobTitle(jt.id),
                    );
                  }).toList(),
                ),
                if (_s.approverJobTitleIds.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle,
                            color: AppColors.success, size: 14),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            isAr
                                ? '${_s.approverJobTitleIds.length} مسمّى مؤهّل للاعتماد'
                                : '${_s.approverJobTitleIds.length} eligible job titles',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.success,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ===== 3) الحد الأدنى للمستوى المقبول =====
          SectionCard(
            title: isAr ? '📊 الحدّ الأدنى للمستوى' : '📊 Min Acceptable Level',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAr
                      ? 'أقلّ مستوى يُقبل فيه اعتماد المتدرّب'
                      : 'Minimum level required for approval',
                  style: const TextStyle(fontSize: 11),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    _LevelChoice(
                      level: 'a',
                      label: isAr ? 'A — ممتاز فقط' : 'A — Excellent only',
                      selected: _s.minAcceptableLevel == 'a',
                      onTap: () => _s.setMinAcceptableLevel('a'),
                    ),
                    _LevelChoice(
                      level: 'b',
                      label:
                          isAr ? 'B — جيد فأعلى' : 'B — Good or better',
                      selected: _s.minAcceptableLevel == 'b',
                      onTap: () => _s.setMinAcceptableLevel('b'),
                    ),
                    _LevelChoice(
                      level: 'c',
                      label:
                          isAr ? 'C — مقبول فأعلى' : 'C — Acceptable+',
                      selected: _s.minAcceptableLevel == 'c',
                      onTap: () => _s.setMinAcceptableLevel('c'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ===== 4) التوقيعات الإلزاميّة =====
          SectionCard(
            title: isAr ? '✍️ التوقيعات الإلزاميّة' : '✍️ Required Signatures',
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _s.requireEmployeeSig,
                  onChanged: _s.setRequireEmployeeSig,
                  title: Text(
                    isAr ? 'توقيع الموظف' : 'Employee signature',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _s.requireOpSupervisorSig,
                  onChanged: _s.setRequireOpSupervisorSig,
                  title: Text(
                    isAr
                        ? 'توقيع مشرف العمليّات'
                        : 'Operation Supervisor signature',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _s.requireCampBossSig,
                  onChanged: _s.setRequireCampBossSig,
                  title: Text(
                    isAr ? 'توقيع Camp Boss' : 'Camp Boss signature',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _s.requireHrSig,
                  onChanged: _s.setRequireHrSig,
                  title: Text(
                    isAr ? 'توقيع HR' : 'HR signature',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.info.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          color: AppColors.info, size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          isAr
                              ? '${_s.requiredSignaturesCount} توقيعات إلزاميّة'
                              : '${_s.requiredSignaturesCount} required signatures',
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.info,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ===== 5) السلوك التلقائي =====
          SectionCard(
            title: isAr ? '⚙️ السلوك التلقائي' : '⚙️ Automation',
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _s.autoCreate,
                  onChanged: _s.setAutoCreate,
                  title: Text(
                    isAr
                        ? 'إنشاء سجلّ تلقائي عند تسجيل موظف متدرّب'
                        : 'Auto-create record on new trainee',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    isAr
                        ? 'متى يختار المسؤول "متدرّب" يُفتح سجلّ تدريب فوراً'
                        : 'When admin picks "Trainee", a record opens immediately',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _s.requirePhoto,
                  onChanged: _s.setRequirePhoto,
                  title: Text(
                    isAr
                        ? 'صورة الموظف إلزاميّة قبل التدريب'
                        : 'Employee photo required',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// مرشّحو المعتمِدين: نُظهر مسمّيات لها approval power أو level <= 4
  List<JobTitle> _filteredApproverCandidates(MockRepository repo) {
    final list = repo.jobTitles.toList()
      ..sort((a, b) {
        final lc = a.level.compareTo(b.level);
        if (lc != 0) return lc;
        return a.nameAr.compareTo(b.nameAr);
      });
    // فلتر: نُظهر فقط من له approvalPower > 0 أو level <= 4
    return list
        .where((jt) => jt.approvalPower > 0 || jt.level <= 4)
        .toList();
  }
}

class _LevelChoice extends StatelessWidget {
  final String level;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _LevelChoice({
    required this.level,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final color = level == 'a'
        ? AppColors.success
        : level == 'b'
            ? AppColors.brand
            : AppColors.warning;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? color : Theme.of(context).dividerColor,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                level.toUpperCase(),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight:
                        selected ? FontWeight.w800 : FontWeight.w500,
                    color: selected ? color : null)),
          ],
        ),
      ),
    );
  }
}
