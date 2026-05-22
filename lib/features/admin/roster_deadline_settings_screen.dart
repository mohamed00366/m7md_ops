import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/roster_deadline_settings.dart';
import '../../core/theme/app_colors.dart';

/// 📅 شاشة إعدادات مواعيد الروستر
///
/// يضبط المسؤول:
///   - آخر يوم لإنشاء الروستر (افتراضي: السبت)
///   - يوم المراجعة (افتراضي: الأحد)
///   - يوم بدء العمل (افتراضي: الإثنين)
///   - تفعيل/إلغاء التنبيهات
///   - ساعة التنبيه اليومي (للتنبيه قبل الـ deadline)
class RosterDeadlineSettingsScreen extends StatefulWidget {
  const RosterDeadlineSettingsScreen({super.key});
  @override
  State<RosterDeadlineSettingsScreen> createState() =>
      _RosterDeadlineSettingsScreenState();
}

class _RosterDeadlineSettingsScreenState
    extends State<RosterDeadlineSettingsScreen> {
  final _settings = RosterDeadlineSettings.instance;
  bool _loaded = false;

  late int _deadlineDay;
  late int _reviewDay;
  late int _effectiveDay;
  late bool _enableAlerts;
  late int _alertHour;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _settings.load();
    setState(() {
      _deadlineDay = _settings.deadlineDay;
      _reviewDay = _settings.reviewDay;
      _effectiveDay = _settings.effectiveDay;
      _enableAlerts = _settings.enableAlerts;
      _alertHour = _settings.alertHour;
      _loaded = true;
    });
  }

  Future<void> _save() async {
    await _settings.setDeadlineDay(_deadlineDay);
    await _settings.setReviewDay(_reviewDay);
    await _settings.setEffectiveDay(_effectiveDay);
    await _settings.setEnableAlerts(_enableAlerts);
    await _settings.setAlertHour(_alertHour);
    if (!mounted) return;
    final isAr = AppStrings.of(context).isAr;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.success,
      content: Text(isAr ? 'تمّ الحفظ' : 'Saved'),
    ));
  }

  Widget _dayPicker({
    required String labelAr,
    required String labelEn,
    required String descAr,
    required String descEn,
    required int value,
    required ValueChanged<int> onChanged,
    required Color color,
    required bool isAr,
  }) {
    const days = [
      DateTime.monday,
      DateTime.tuesday,
      DateTime.wednesday,
      DateTime.thursday,
      DateTime.friday,
      DateTime.saturday,
      DateTime.sunday,
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(isAr ? labelAr : labelEn,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: color)),
          const SizedBox(height: 2),
          Text(isAr ? descAr : descEn,
              style: const TextStyle(fontSize: 11)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              for (final d in days)
                ChoiceChip(
                  selected: d == value,
                  label: Text(
                    isAr
                        ? RosterDeadlineSettings.dayLabelAr(d)
                        : RosterDeadlineSettings.dayLabelEn(d),
                    style: const TextStyle(fontSize: 11),
                  ),
                  onSelected: (_) => onChanged(d),
                  selectedColor: color.withValues(alpha: 0.20),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(isAr ? 'مواعيد الروستر' : 'Roster Deadlines'),
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // ===== شريط ملخّص =====
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.info.withValues(alpha: 0.30)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.info_outline,
                        color: AppColors.info, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        isAr
                            ? 'القاعدة الافتراضيّة: السبت آخر يوم للإنشاء، الأحد للمراجعة، الإثنين بدء العمل.'
                            : 'Default: Saturday is creation deadline, Sunday for review, Monday work starts.',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  isAr
                      ? 'هذه الإعدادات تتحكّم بظهور تنبيه «تم تجاوز الموعد» في شاشة إنشاء الروستر، ولا تمنع الإنشاء (تذكير فقط).'
                      : 'These control the deadline alert in the roster screen — they remind, they do not block.',
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          _dayPicker(
            labelAr: '🗓️ آخر يوم لإنشاء الروستر',
            labelEn: '🗓️ Roster creation deadline',
            descAr: 'يجب إنشاء الروستر وإرساله للمراجعة قبل نهاية هذا اليوم.',
            descEn: 'Roster must be created & submitted by end of this day.',
            value: _deadlineDay,
            onChanged: (v) => setState(() => _deadlineDay = v),
            color: AppColors.warning,
            isAr: isAr,
          ),

          _dayPicker(
            labelAr: '🔍 يوم المراجعة والاعتماد',
            labelEn: '🔍 Review & approval day',
            descAr: 'يخصَّص لمراجعة الروستر واعتماده أو طلب التعديل.',
            descEn: 'Reserved for reviewing & approving / requesting edits.',
            value: _reviewDay,
            onChanged: (v) => setState(() => _reviewDay = v),
            color: AppColors.info,
            isAr: isAr,
          ),

          _dayPicker(
            labelAr: '🚀 يوم بدء العمل',
            labelEn: '🚀 Work start day',
            descAr: 'اليوم الأوّل من الأسبوع الذي يطبَّق فيه الروستر.',
            descEn: 'First day of the week the roster applies to.',
            value: _effectiveDay,
            onChanged: (v) => setState(() => _effectiveDay = v),
            color: AppColors.success,
            isAr: isAr,
          ),

          const SizedBox(height: 6),
          // ===== التنبيهات =====
          Container(
            padding: const EdgeInsets.all(8),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    isAr
                        ? 'تفعيل تنبيهات المواعيد'
                        : 'Enable deadline alerts',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    isAr
                        ? 'يظهر شريط تنبيه فوق شاشة الروستر بحسب قرب الموعد.'
                        : 'Shows an alert banner above the roster screen.',
                    style: const TextStyle(fontSize: 11),
                  ),
                  value: _enableAlerts,
                  onChanged: (v) => setState(() => _enableAlerts = v),
                ),
                if (_enableAlerts) ...[
                  const Divider(height: 1),
                  ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 4),
                    title: Text(
                      isAr ? 'ساعة التذكير اليومي' : 'Daily reminder hour',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      isAr
                          ? 'تستخدم لاحقاً لإرسال إشعار محلّي بنفس هذه الساعة قرب الـ deadline.'
                          : 'For local push reminders close to deadline (future).',
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: DropdownButton<int>(
                      value: _alertHour,
                      items: [
                        for (var h = 6; h <= 22; h++)
                          DropdownMenuItem(
                              value: h,
                              child:
                                  Text('${h.toString().padLeft(2, "0")}:00')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _alertHour = v);
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brand,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: _save,
            icon: const Icon(Icons.save_outlined, size: 16),
            label: Text(
                isAr ? 'حفظ الإعدادات' : 'Save settings',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w900)),
          ),
        ),
      ),
    );
  }
}
