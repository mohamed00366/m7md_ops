import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/driver_tracking_settings.dart';
import '../../core/theme/app_colors.dart';
import '../../models/lookups.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/m7_app_bar.dart';

/// 📍 شاشة إعدادات تتبّع السائقين
class DriverTrackingSettingsScreen extends StatefulWidget {
  const DriverTrackingSettingsScreen({super.key});
  @override
  State<DriverTrackingSettingsScreen> createState() =>
      _DriverTrackingSettingsScreenState();
}

class _DriverTrackingSettingsScreenState
    extends State<DriverTrackingSettingsScreen> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await DriverTrackingSettings.instance.load();
    if (!mounted) return;
    setState(() => _ready = true);
  }

  Future<void> _pickAccounts() async {
    final settings = DriverTrackingSettings.instance;
    final isAr = AppStrings.of(context).isAr;
    final selected = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => _AccountPickerSheet(
        initiallySelected: settings.accountIds,
        isAr: isAr,
      ),
    );
    if (selected != null) await settings.setAccountIds(selected);
  }

  Future<void> _pickJobTitles() async {
    final settings = DriverTrackingSettings.instance;
    final isAr = AppStrings.of(context).isAr;
    final selected = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => _JobTitlePickerSheet(
        initiallySelected: settings.jobTitleIds,
        isAr: isAr,
      ),
    );
    if (selected != null) await settings.setJobTitleIds(selected);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    return AnimatedBuilder(
      animation: DriverTrackingSettings.instance,
      builder: (context, _) {
        final settings = DriverTrackingSettings.instance;
        final showLists =
            settings.scope != DriverTrackingScope.allDrivers;
        return Scaffold(
          appBar: M7AppBar(
            title: isAr ? 'تتبّع السائقين' : 'Driver Tracking',
            subtitle: isAr
                ? 'سياسة إرسال الموقع التلقائي'
                : 'Auto location reporting policy',
            actions: [
              M7AppBarAction(
                icon: Icons.restore,
                tooltip:
                    isAr ? 'القيم الافتراضية' : 'Reset',
                onPressed: _ready
                    ? () async {
                        await settings.resetToDefaults();
                      }
                    : null,
              ),
            ],
          ),
          body: !_ready
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _Banner(isAr: isAr),
                    const SizedBox(height: 16),

                    // ===== 1) السياسة =====
                    _SectionTitle(
                      icon: Icons.policy_outlined,
                      title: isAr ? 'السياسة' : 'Policy',
                    ),
                    const SizedBox(height: 8),
                    _SwitchCard(
                      title: isAr
                          ? 'تفعيل تتبّع المواقع'
                          : 'Enable location tracking',
                      subtitle: settings.enabled
                          ? (isAr
                              ? 'مفعّل: التطبيق يرسل الموقع تلقائياً'
                              : 'Enabled: app reports location automatically')
                          : (isAr
                              ? 'معطّل: لا يُرسل أيّ موقع'
                              : 'Disabled: no location reporting'),
                      value: settings.enabled,
                      onChanged: settings.setEnabled,
                    ),

                    if (settings.enabled) ...[
                      // ===== 2) الإعدادات الأساسيّة =====
                      const SizedBox(height: 18),
                      _SectionTitle(
                        icon: Icons.tune_outlined,
                        title:
                            isAr ? 'إعدادات أساسيّة' : 'Basic',
                      ),
                      const SizedBox(height: 8),
                      _NumberCard(
                        label: isAr
                            ? 'فترة الإرسال (دقائق)'
                            : 'Reporting interval (min)',
                        value: settings.intervalMinutes,
                        min: 1,
                        max: 60,
                        onChanged: settings.setIntervalMinutes,
                        icon: Icons.schedule,
                      ),
                      const SizedBox(height: 8),
                      _SwitchCard(
                        title: isAr
                            ? 'بدء تلقائي عند الدخول'
                            : 'Auto-start on login',
                        subtitle: isAr
                            ? 'يبدأ التتبّع فور دخول السائق التطبيق'
                            : 'Starts tracking immediately on driver login',
                        value: settings.autoStart,
                        onChanged: settings.setAutoStart,
                      ),
                      const SizedBox(height: 8),
                      _SwitchCard(
                        title: isAr
                            ? 'ضمن ساعات الدوام فقط'
                            : 'Working hours only',
                        subtitle: isAr
                            ? 'لا تتبّع خارج الـ ${settings.workStartHour}:00 - ${settings.workEndHour}:00'
                            : 'No tracking outside ${settings.workStartHour}:00 - ${settings.workEndHour}:00',
                        value: settings.workingHoursOnly,
                        onChanged: settings.setWorkingOnly,
                      ),
                      if (settings.workingHoursOnly) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _NumberCard(
                                label: isAr ? 'بداية' : 'Start',
                                value: settings.workStartHour,
                                min: 0,
                                max: 23,
                                onChanged:
                                    settings.setWorkStartHour,
                                icon: Icons.wb_sunny_outlined,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _NumberCard(
                                label: isAr ? 'نهاية' : 'End',
                                value: settings.workEndHour,
                                min: 0,
                                max: 23,
                                onChanged: settings.setWorkEndHour,
                                icon: Icons.nightlight_outlined,
                              ),
                            ),
                          ],
                        ),
                      ],

                      // ===== 3) النطاق =====
                      const SizedBox(height: 18),
                      _SectionTitle(
                        icon: Icons.group_outlined,
                        title: isAr ? 'مَن يُتتبَّع؟' : 'Who is tracked?',
                      ),
                      const SizedBox(height: 6),
                      _ScopeOption(
                        active: settings.scope ==
                            DriverTrackingScope.allDrivers,
                        title: isAr
                            ? 'كلّ الحسابات'
                            : 'All accounts',
                        subtitle: isAr
                            ? 'يُتتبَّع كلّ من يفتح التطبيق'
                            : 'Track every user who opens the app',
                        icon: Icons.people_alt_outlined,
                        color: AppColors.brand,
                        onTap: () => settings
                            .setScope(DriverTrackingScope.allDrivers),
                      ),
                      const SizedBox(height: 8),
                      _ScopeOption(
                        active: settings.scope ==
                            DriverTrackingScope.includedOnly,
                        title: isAr
                            ? 'حسابات/مسمّيات مختارة'
                            : 'Selected only',
                        subtitle: isAr
                            ? 'مثل: السائقون فقط'
                            : 'e.g. drivers only',
                        icon: Icons.check_circle_outline,
                        color: AppColors.success,
                        onTap: () => settings.setScope(
                            DriverTrackingScope.includedOnly),
                      ),
                      const SizedBox(height: 8),
                      _ScopeOption(
                        active: settings.scope ==
                            DriverTrackingScope.excludedOnly,
                        title: isAr
                            ? 'الكلّ ما عدا'
                            : 'All except selected',
                        subtitle: isAr
                            ? 'مثل: استثناء بعض الحسابات الإداريّة'
                            : 'e.g. exempt some admin accounts',
                        icon: Icons.do_not_disturb_on_outlined,
                        color: AppColors.warning,
                        onTap: () => settings.setScope(
                            DriverTrackingScope.excludedOnly),
                      ),

                      if (showLists) ...[
                        const SizedBox(height: 14),
                        _AccountListCard(
                          isAr: isAr,
                          ids: settings.accountIds,
                          isExempt: settings.scope ==
                              DriverTrackingScope.excludedOnly,
                          onTapPick: _pickAccounts,
                          onRemove: settings.removeAccount,
                        ),
                        const SizedBox(height: 12),
                        _JobTitleListCard(
                          isAr: isAr,
                          ids: settings.jobTitleIds,
                          isExempt: settings.scope ==
                              DriverTrackingScope.excludedOnly,
                          onTapPick: _pickJobTitles,
                          onRemove: settings.removeJobTitle,
                        ),
                      ],

                      // ===== 4) السجلّ التاريخي =====
                      const SizedBox(height: 18),
                      _SectionTitle(
                        icon: Icons.history_outlined,
                        title: isAr
                            ? 'السجلّ التاريخي'
                            : 'History retention',
                      ),
                      const SizedBox(height: 8),
                      _SwitchCard(
                        title: isAr
                            ? 'حفظ سجلّ المسارات'
                            : 'Keep route history',
                        subtitle: isAr
                            ? 'يُمكِّن خرائط مسار السائق ومقارنة الأيّام'
                            : 'Enables route map + day comparisons',
                        value: settings.historyEnabled,
                        onChanged: settings.setHistoryEnabled,
                      ),
                      if (settings.historyEnabled) ...[
                        const SizedBox(height: 8),
                        _NumberCard(
                          label: isAr
                              ? 'مدّة الحفظ (يوم)'
                              : 'Retention (days)',
                          value: settings.retentionDays,
                          min: 1,
                          max: 365,
                          onChanged: settings.setRetentionDays,
                          icon: Icons.calendar_month_outlined,
                        ),
                      ],

                      // ===== 5) معاينة =====
                      const SizedBox(height: 18),
                      _SectionTitle(
                        icon: Icons.preview_outlined,
                        title: isAr
                            ? 'معاينة المتأثّرين'
                            : 'Affected accounts',
                      ),
                      const SizedBox(height: 8),
                      const _AffectedPreview(),
                    ],

                    const SizedBox(height: 30),
                  ],
                ),
        );
      },
    );
  }
}

// ============================================================
// shared widgets (Banner, SectionTitle, SwitchCard, NumberCard, ScopeOption)
// ============================================================
class _Banner extends StatelessWidget {
  final bool isAr;
  const _Banner({required this.isAr});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.brand.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: AppColors.brand.withValues(alpha: 0.25), width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.gps_fixed,
              color: AppColors.brand, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isAr
                  ? 'هذه الإعدادات تتحكّم في التتبّع التلقائي. السائق لا يرى زرّ "إرسال الموقع" — التطبيق يعمل بصمت في الخلفيّة.'
                  : 'These settings control automatic tracking. Driver sees NO send-location button — app works silently.',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionTitle({required this.icon, required this.title});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.brand),
        const SizedBox(width: 6),
        Text(title,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class _SwitchCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchCard({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: Theme.of(context).dividerColor, width: 0.5),
      ),
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        title: Text(title,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(subtitle, style: const TextStyle(fontSize: 11)),
        ),
      ),
    );
  }
}

class _NumberCard extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final IconData icon;
  const _NumberCard({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.icon,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: Theme.of(context).dividerColor, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.brand),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, size: 20),
            onPressed:
                value > min ? () => onChanged(value - 1) : null,
          ),
          SizedBox(
            width: 36,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w900),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 20),
            onPressed:
                value < max ? () => onChanged(value + 1) : null,
          ),
        ],
      ),
    );
  }
}

class _ScopeOption extends StatelessWidget {
  final bool active;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ScopeOption({
    required this.active,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: active
              ? color.withValues(alpha: 0.08)
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active
                ? color.withValues(alpha: 0.6)
                : Theme.of(context).dividerColor,
            width: active ? 1.2 : 0.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(fontSize: 11)),
                ],
              ),
            ),
            if (active)
              Icon(Icons.check_circle, color: color, size: 18),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Account / JobTitle list cards + pickers
// ============================================================
class _AccountListCard extends StatelessWidget {
  final bool isAr;
  final Set<String> ids;
  final bool isExempt;
  final VoidCallback onTapPick;
  final ValueChanged<String> onRemove;
  const _AccountListCard({
    required this.isAr,
    required this.ids,
    required this.isExempt,
    required this.onTapPick,
    required this.onRemove,
  });
  @override
  Widget build(BuildContext context) {
    final repo = MockRepository();
    final accounts = ids.map((id) {
      try {
        return repo.accounts.firstWhere((a) => a.id == id);
      } catch (_) {
        return AppAccount(
            id: id, username: '?', passwordHash: '', fullName: id);
      }
    }).toList();
    final color = isExempt ? AppColors.warning : AppColors.success;
    return _ListCardScaffold(
      isAr: isAr,
      title: isExempt
          ? (isAr ? 'حسابات مُستثناة' : 'Exempted accounts')
          : (isAr ? 'حسابات مشمولة' : 'Included accounts'),
      icon: isExempt
          ? Icons.do_not_disturb_on_outlined
          : Icons.check_circle_outline,
      color: color,
      count: ids.length,
      onTapPick: onTapPick,
      isEmpty: accounts.isEmpty,
      emptyText: isAr ? 'لا توجد حسابات' : 'No accounts',
      chips: accounts
          .map((a) => _Chip(
                label: a.fullName,
                sub: '@${a.username}',
                color: color,
                onRemove: () => onRemove(a.id),
              ))
          .toList(),
    );
  }
}

class _JobTitleListCard extends StatelessWidget {
  final bool isAr;
  final Set<String> ids;
  final bool isExempt;
  final VoidCallback onTapPick;
  final ValueChanged<String> onRemove;
  const _JobTitleListCard({
    required this.isAr,
    required this.ids,
    required this.isExempt,
    required this.onTapPick,
    required this.onRemove,
  });
  @override
  Widget build(BuildContext context) {
    final repo = MockRepository();
    final titles = ids
        .map((id) {
          try {
            return repo.jobTitles.firstWhere((j) => j.id == id);
          } catch (_) {
            return null;
          }
        })
        .whereType<JobTitle>()
        .toList();
    final color = isExempt ? AppColors.warning : AppColors.success;
    return _ListCardScaffold(
      isAr: isAr,
      title: isExempt
          ? (isAr
              ? 'مسمّيات وظيفيّة مستثناة'
              : 'Exempted job titles')
          : (isAr
              ? 'مسمّيات وظيفيّة مشمولة'
              : 'Included job titles'),
      icon: Icons.badge_outlined,
      color: color,
      count: ids.length,
      onTapPick: onTapPick,
      isEmpty: titles.isEmpty,
      emptyText: isAr ? 'لا توجد مسمّيات' : 'No titles',
      chips: titles
          .map((j) => _Chip(
                label: isAr ? j.nameAr : j.nameEn,
                sub: '',
                color: color,
                icon: Icons.badge_outlined,
                onRemove: () => onRemove(j.id),
              ))
          .toList(),
    );
  }
}

class _ListCardScaffold extends StatelessWidget {
  final bool isAr;
  final String title;
  final IconData icon;
  final Color color;
  final int count;
  final VoidCallback onTapPick;
  final bool isEmpty;
  final String emptyText;
  final List<Widget> chips;
  const _ListCardScaffold({
    required this.isAr,
    required this.title,
    required this.icon,
    required this.color,
    required this.count,
    required this.onTapPick,
    required this.isEmpty,
    required this.emptyText,
    required this.chips,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: color.withValues(alpha: 0.3), width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 6),
            child: Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('$count',
                      style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.w800)),
                ),
                IconButton(
                  tooltip: isAr ? 'إضافة' : 'Add',
                  onPressed: onTapPick,
                  icon: const Icon(Icons.add_circle_outline),
                  color: AppColors.brand,
                ),
              ],
            ),
          ),
          if (isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
              child: Text(emptyText,
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.color)),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: chips,
              ),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final String sub;
  final Color color;
  final IconData? icon;
  final VoidCallback onRemove;
  const _Chip({
    required this.label,
    required this.sub,
    required this.color,
    this.icon,
    required this.onRemove,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
          if (sub.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text(sub,
                style: TextStyle(
                    color: color.withValues(alpha: 0.7), fontSize: 10)),
          ],
          InkWell(
            customBorder: const CircleBorder(),
            onTap: onRemove,
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Icon(Icons.close, size: 14, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

// Pickers
class _AccountPickerSheet extends StatefulWidget {
  final Set<String> initiallySelected;
  final bool isAr;
  const _AccountPickerSheet({
    required this.initiallySelected,
    required this.isAr,
  });
  @override
  State<_AccountPickerSheet> createState() =>
      _AccountPickerSheetState();
}

class _AccountPickerSheetState extends State<_AccountPickerSheet> {
  late Set<String> _selected;
  String _q = '';
  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.initiallySelected);
  }

  @override
  Widget build(BuildContext context) {
    final isAr = widget.isAr;
    final repo = MockRepository();
    var accounts = List<AppAccount>.from(repo.accounts)
      ..sort((a, b) => a.fullName.compareTo(b.fullName));
    if (_q.isNotEmpty) {
      final q = _q.toLowerCase();
      accounts = accounts
          .where((a) =>
              a.fullName.toLowerCase().contains(q) ||
              a.username.toLowerCase().contains(q))
          .toList();
    }
    return _PickerScaffold(
      title: isAr ? 'اختيار حسابات' : 'Select accounts',
      isAr: isAr,
      count: _selected.length,
      onSearch: (v) => setState(() => _q = v),
      onCancel: () => Navigator.pop(context),
      onSave: () => Navigator.pop(context, _selected),
      child: ListView.builder(
        itemCount: accounts.length,
        itemBuilder: (ctx, i) {
          final a = accounts[i];
          return CheckboxListTile(
            value: _selected.contains(a.id),
            onChanged: (v) => setState(() {
              if (v == true) {
                _selected.add(a.id);
              } else {
                _selected.remove(a.id);
              }
            }),
            title: Text(a.fullName,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700)),
            subtitle: Text('@${a.username}',
                style: const TextStyle(fontSize: 11)),
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
          );
        },
      ),
    );
  }
}

class _JobTitlePickerSheet extends StatefulWidget {
  final Set<String> initiallySelected;
  final bool isAr;
  const _JobTitlePickerSheet({
    required this.initiallySelected,
    required this.isAr,
  });
  @override
  State<_JobTitlePickerSheet> createState() =>
      _JobTitlePickerSheetState();
}

class _JobTitlePickerSheetState extends State<_JobTitlePickerSheet> {
  late Set<String> _selected;
  String _q = '';
  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.initiallySelected);
  }

  @override
  Widget build(BuildContext context) {
    final isAr = widget.isAr;
    final repo = MockRepository();
    var titles = List<JobTitle>.from(repo.jobTitles)
      ..sort((a, b) => (isAr ? a.nameAr : a.nameEn)
          .compareTo(isAr ? b.nameAr : b.nameEn));
    if (_q.isNotEmpty) {
      final q = _q.toLowerCase();
      titles = titles
          .where((j) =>
              j.nameAr.toLowerCase().contains(q) ||
              j.nameEn.toLowerCase().contains(q))
          .toList();
    }
    return _PickerScaffold(
      title: isAr ? 'اختيار مسمّيات' : 'Select titles',
      isAr: isAr,
      count: _selected.length,
      onSearch: (v) => setState(() => _q = v),
      onCancel: () => Navigator.pop(context),
      onSave: () => Navigator.pop(context, _selected),
      child: ListView.builder(
        itemCount: titles.length,
        itemBuilder: (ctx, i) {
          final j = titles[i];
          return CheckboxListTile(
            value: _selected.contains(j.id),
            onChanged: (v) => setState(() {
              if (v == true) {
                _selected.add(j.id);
              } else {
                _selected.remove(j.id);
              }
            }),
            title: Text(isAr ? j.nameAr : j.nameEn,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700)),
            subtitle: Text(isAr ? j.nameEn : j.nameAr,
                style: const TextStyle(fontSize: 11)),
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
          );
        },
      ),
    );
  }
}

class _PickerScaffold extends StatelessWidget {
  final String title;
  final bool isAr;
  final int count;
  final ValueChanged<String> onSearch;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  final Widget child;
  const _PickerScaffold({
    required this.title,
    required this.isAr,
    required this.count,
    required this.onSearch,
    required this.onCancel,
    required this.onSave,
    required this.child,
  });
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(18)),
          ),
          constraints: BoxConstraints(
              maxHeight:
                  MediaQuery.of(context).size.height * 0.85),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Theme.of(context).dividerColor,
                      borderRadius: BorderRadius.circular(2))),
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.brand.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('$count',
                          style: const TextStyle(
                              color: AppColors.brand,
                              fontWeight: FontWeight.w800,
                              fontSize: 12)),
                    ),
                  ],
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: isAr ? 'بحث…' : 'Search…',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                  onChanged: onSearch,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(child: child),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                          onPressed: onCancel,
                          child:
                              Text(isAr ? 'إلغاء' : 'Cancel')),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                          onPressed: onSave,
                          child: Text(isAr ? 'حفظ' : 'Save')),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// 👁️ معاينة المتأثّرين
// ============================================================
class _AffectedPreview extends StatelessWidget {
  const _AffectedPreview();
  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return AnimatedBuilder(
      animation: DriverTrackingSettings.instance,
      builder: (context, _) {
        final settings = DriverTrackingSettings.instance;
        final repo = MockRepository();
        var tracked = 0;
        for (final a in repo.accounts) {
          if (settings.appliesTo(a.id)) tracked++;
        }
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: AppColors.success.withValues(alpha: 0.25), width: 0.5),
          ),
          child: Row(
            children: [
              const Icon(Icons.gps_fixed,
                  color: AppColors.success, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isAr
                      ? 'يُتتبَّع الآن $tracked حساباً من أصل ${repo.accounts.length}'
                      : '$tracked of ${repo.accounts.length} accounts are tracked now',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
