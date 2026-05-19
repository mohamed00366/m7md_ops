import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/training_settings.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../shared/m7_app_bar.dart';
import '../../shared/widgets.dart';

/// 📜 إعدادات موديول التدريب العامّ.
///
/// ⚠️ **ORPHAN** — هذه الشاشة لا يُستخدمها أيّ موديول حالياً، لأنّ
/// "Training Hub" المنفصل أُزيل من الـ Drawer (Task #17).
/// النظام يستخدم `OnPointTrainingSettingsScreen` لإعدادات تدريب الجدد فقط.
///
/// **القرار المعلَّق:** إمّا إعادة تفعيل Training Hub (أرشفة كورسات + سجلّات)
/// أو حذف هذه الشاشة نهائيّاً. تُرك كما هو لأنّ خدمة `TrainingSettings`
/// نفسها لا تزال تُستخدم في `MockRepository.trainingCourses/Records`.
class TrainingSettingsScreen extends StatefulWidget {
  const TrainingSettingsScreen({super.key});

  @override
  State<TrainingSettingsScreen> createState() => _TrainingSettingsScreenState();
}

class _TrainingSettingsScreenState extends State<TrainingSettingsScreen> {
  final TrainingSettings _s = TrainingSettings.instance;
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
    final isAr = l.isAr;
    if (_loading) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? 'إعدادات التدريب' : 'Training Settings',
        actions: [
          M7AppBarAction(
            icon: Icons.restart_alt,
            tooltip: isAr ? 'إعادة الافتراضيّ' : 'Reset',
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: Text(l.confirm),
                  content: Text(isAr
                      ? 'إعادة كل إعدادات التدريب للقيم الافتراضيّة؟'
                      : 'Reset all training settings to defaults?'),
                  actions: [
                    TextButton(
                        onPressed: () =>
                            Navigator.of(context).pop(false),
                        child: Text(l.cancel)),
                    ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.danger),
                        onPressed: () => Navigator.of(context).pop(true),
                        child: Text(isAr ? 'إعادة' : 'Reset')),
                  ],
                ),
              );
              if (ok == true) await _s.resetToDefaults();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // ===== فترة التحذير قبل الانتهاء =====
          SectionCard(
            title: isAr
                ? '⚠️ التحذير قبل انتهاء الصلاحيّة'
                : '⚠️ Pre-expiry warning',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAr
                      ? 'كم يوماً قبل انتهاء صلاحيّة الدورة نُظهر تحذيراً للموظف والمسؤول؟'
                      : 'How many days before expiry to warn employee and admin?',
                  style: const TextStyle(fontSize: 11),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: _s.daysWarning.toDouble(),
                        min: 1,
                        max: 90,
                        divisions: 89,
                        label: '${_s.daysWarning}',
                        onChanged: (v) => _s.setDaysWarning(v.round()),
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
                        '${_s.daysWarning} ${isAr ? "يوم" : "days"}',
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
          // ===== مدّة الصلاحيّة الافتراضيّة =====
          SectionCard(
            title: isAr
                ? '📆 مدّة الصلاحيّة الافتراضيّة'
                : '📆 Default validity',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAr
                      ? 'كم شهراً تكون الصلاحيّة الافتراضيّة عند إنشاء دورة جديدة؟ (0 = بلا انتهاء)'
                      : 'Default validity months when creating a new course (0 = never)',
                  style: const TextStyle(fontSize: 11),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: _s.defaultValidityMonthsValue.toDouble(),
                        min: 0,
                        max: 60,
                        divisions: 12,
                        label: '${_s.defaultValidityMonthsValue}',
                        onChanged: (v) =>
                            _s.setDefaultValidityMonths(v.round()),
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
                        '${_s.defaultValidityMonthsValue} ${isAr ? "شهر" : "mo"}',
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
          // ===== منع الروستر إن انتهت دورة إلزاميّة =====
          SectionCard(
            title: isAr ? '🚫 ربط بالروستر' : '🚫 Roster link',
            child: SwitchListTile(
              value: _s.blockRosterOnExpired,
              onChanged: _s.setBlockRosterOnExpired,
              title: Text(
                isAr
                    ? 'منع إضافة موظف لروستر إن انتهت دورة إلزاميّة'
                    : 'Block roster assignment if mandatory training expired',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                isAr
                    ? 'حماية لا توافقيّة (لو نقصت دورة سلامة لازمة، يُمنع جدولته)'
                    : 'Compliance guard — if a required course is missing, block them',
                style: const TextStyle(fontSize: 11),
              ),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(height: 12),
          // ===== التصنيفات الإلزاميّة =====
          SectionCard(
            title: isAr ? '🏷️ تصنيفات إلزاميّة' : '🏷️ Mandatory categories',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAr
                      ? 'أيّ تصنيفات نُعتبرها إلزاميّة افتراضيّاً (تظهر في تقارير التغطية)'
                      : 'Which categories are treated as mandatory by default',
                  style: const TextStyle(fontSize: 11),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: TrainingCategory.values
                      .where((c) => c != TrainingCategory.other)
                      .map((c) {
                    final selected = _s.mandatoryCategories.contains(c.key);
                    return FilterChip(
                      label: Text(
                          isAr ? c.arabicLabel() : c.englishLabel(),
                          style: const TextStyle(fontSize: 11)),
                      selected: selected,
                      onSelected: (_) =>
                          _s.toggleMandatoryCategory(c.key),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
