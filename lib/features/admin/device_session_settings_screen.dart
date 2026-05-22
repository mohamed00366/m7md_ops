import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/device_session_settings.dart';
import '../../core/theme/app_colors.dart';
import '../../models/lookups.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/m7_app_bar.dart';

/// 📱 إعدادات سياسة "جهاز واحد لكل موظف"
///
/// تتيح:
///   • تفعيل/تعطيل السياسة
///   • تحديد نطاق التطبيق (الكلّ / مختارون فقط / الكلّ عدا مختارين)
///   • تعديل رسالة الرفض (عربيّة + إنجليزيّة)
///   • معاينة مباشرة
class DeviceSessionSettingsScreen extends StatefulWidget {
  const DeviceSessionSettingsScreen({super.key});

  @override
  State<DeviceSessionSettingsScreen> createState() =>
      _DeviceSessionSettingsScreenState();
}

class _DeviceSessionSettingsScreenState
    extends State<DeviceSessionSettingsScreen> {
  late TextEditingController _arCtrl;
  late TextEditingController _enCtrl;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _arCtrl = TextEditingController();
    _enCtrl = TextEditingController();
    _load();
  }

  Future<void> _load() async {
    await DeviceSessionSettings.instance.load();
    if (!mounted) return;
    setState(() {
      _arCtrl.text = DeviceSessionSettings.instance.blockedMessageAr;
      _enCtrl.text = DeviceSessionSettings.instance.blockedMessageEn;
      _ready = true;
    });
  }

  @override
  void dispose() {
    _arCtrl.dispose();
    _enCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAccounts() async {
    final settings = DeviceSessionSettings.instance;
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
    if (selected != null) {
      await settings.setAccountIds(selected);
    }
  }

  Future<void> _pickJobTitles() async {
    final settings = DeviceSessionSettings.instance;
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
    if (selected != null) {
      await settings.setJobTitleIds(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    return AnimatedBuilder(
      animation: DeviceSessionSettings.instance,
      builder: (context, _) {
        final settings = DeviceSessionSettings.instance;
        final showAccountPicker =
            settings.scope != DevicePolicyScope.allAccounts;
        return Scaffold(
          appBar: M7AppBar(
            title: isAr ? 'سياسة الأجهزة' : 'Device Policy',
            subtitle: isAr
                ? 'جهاز واحد لكل موظف'
                : 'One device per employee',
            actions: [
              M7AppBarAction(
                icon: Icons.restore,
                tooltip:
                    isAr ? 'القيم الافتراضية' : 'Reset to defaults',
                onPressed: _ready
                    ? () async {
                        await settings.resetToDefaults();
                        if (!mounted) return;
                        setState(() {
                          _arCtrl.text = settings.blockedMessageAr;
                          _enCtrl.text = settings.blockedMessageEn;
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(isAr
                                  ? 'تمّت إعادة الإعدادات للافتراضي'
                                  : 'Settings reset to defaults')),
                        );
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
                    _InfoBanner(isAr: isAr),
                    const SizedBox(height: 16),

                    // ===== 1) السياسة (تفعيل / تعطيل) =====
                    _SectionTitle(
                      icon: Icons.policy_outlined,
                      title: isAr ? 'السياسة' : 'Policy',
                    ),
                    const SizedBox(height: 8),
                    _PolicyCard(
                      title: isAr
                          ? 'جهاز واحد فقط لكل موظف'
                          : 'Strict one-device-per-employee',
                      subtitle: isAr
                          ? settings.enforceOneDevice
                              ? 'مُفعَّل: يُرفض الدخول من جهاز ثانٍ ويظهر للموظّف رسالة المراجعة'
                              : 'مُعطَّل: يُسمح بالدخول من جهاز جديد مع تعطيل الجهاز السابق تلقائياً'
                          : settings.enforceOneDevice
                              ? 'Enabled: Login from a second device is rejected; user sees the message below'
                              : 'Disabled: New device replaces the old one automatically',
                      value: settings.enforceOneDevice,
                      onChanged: (v) =>
                          settings.setEnforceOneDevice(v),
                    ),

                    // ===== 2) نطاق التطبيق =====
                    if (settings.enforceOneDevice) ...[
                      const SizedBox(height: 18),
                      _SectionTitle(
                        icon: Icons.group_outlined,
                        title: isAr ? 'نطاق التطبيق' : 'Scope',
                      ),
                      Padding(
                        padding: const EdgeInsets.only(
                            left: 4, right: 4, bottom: 8),
                        child: Text(
                          isAr
                              ? 'حدّد على من تُطبَّق السياسة المتشدّدة'
                              : 'Choose which accounts the strict policy applies to',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.color,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      _ScopeOption(
                        scope: DevicePolicyScope.allAccounts,
                        active: settings.scope ==
                            DevicePolicyScope.allAccounts,
                        title: isAr
                            ? 'كلّ الحسابات'
                            : 'All accounts',
                        subtitle: isAr
                            ? 'تُطبَّق السياسة على كلّ من يستخدم التطبيق'
                            : 'Policy applies to every user',
                        icon: Icons.people_alt_outlined,
                        color: AppColors.brand,
                        onTap: () => settings
                            .setScope(DevicePolicyScope.allAccounts),
                      ),
                      const SizedBox(height: 8),
                      _ScopeOption(
                        scope: DevicePolicyScope.includedOnly,
                        active: settings.scope ==
                            DevicePolicyScope.includedOnly,
                        title: isAr
                            ? 'حسابات مختارة فقط'
                            : 'Selected accounts only',
                        subtitle: isAr
                            ? 'السياسة تُطبَّق فقط على الحسابات المضافة لهذه القائمة'
                            : 'Policy applies only to accounts you add below',
                        icon: Icons.check_circle_outline,
                        color: AppColors.success,
                        onTap: () => settings
                            .setScope(DevicePolicyScope.includedOnly),
                      ),
                      const SizedBox(height: 8),
                      _ScopeOption(
                        scope: DevicePolicyScope.excludedOnly,
                        active: settings.scope ==
                            DevicePolicyScope.excludedOnly,
                        title: isAr
                            ? 'الكلّ ما عدا حسابات مختارة'
                            : 'Everyone except selected',
                        subtitle: isAr
                            ? 'السياسة تُطبَّق على الكلّ ما عدا الحسابات في هذه القائمة (استثناءات)'
                            : 'Policy applies to all except the listed accounts (exemptions)',
                        icon: Icons.do_not_disturb_on_outlined,
                        color: AppColors.warning,
                        onTap: () => settings
                            .setScope(DevicePolicyScope.excludedOnly),
                      ),

                      // ===== 3) قائمة الحسابات =====
                      if (showAccountPicker) ...[
                        const SizedBox(height: 14),
                        _AccountListCard(
                          isAr: isAr,
                          ids: settings.accountIds,
                          isExempt: settings.scope ==
                              DevicePolicyScope.excludedOnly,
                          onTapPick: _pickAccounts,
                          onRemove: (id) =>
                              settings.removeAccount(id),
                        ),

                        // ===== 3-b) قائمة المسمّيات الوظيفيّة =====
                        const SizedBox(height: 12),
                        _JobTitleListCard(
                          isAr: isAr,
                          ids: settings.jobTitleIds,
                          isExempt: settings.scope ==
                              DevicePolicyScope.excludedOnly,
                          onTapPick: _pickJobTitles,
                          onRemove: (id) =>
                              settings.removeJobTitle(id),
                        ),
                      ],
                    ],

                    // ===== 4) رسالة الرفض =====
                    const SizedBox(height: 18),
                    _SectionTitle(
                      icon: Icons.message_outlined,
                      title: isAr
                          ? 'رسالة رفض الدخول'
                          : 'Login-blocked message',
                    ),
                    Padding(
                      padding: const EdgeInsets.only(
                          left: 4, right: 4, bottom: 8),
                      child: Text(
                        isAr
                            ? 'النصّ الذي يراه الموظّف عند رفض الدخول.'
                            : 'Text shown to the employee when login is rejected.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.color,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    _MessageField(
                      label: isAr
                          ? 'الرسالة بالعربيّة'
                          : 'Arabic message',
                      controller: _arCtrl,
                      onSave: (v) =>
                          settings.setBlockedMessageAr(v),
                      hint: DeviceSessionSettings.defaultMsgAr,
                    ),
                    const SizedBox(height: 12),
                    _MessageField(
                      label: isAr
                          ? 'الرسالة بالإنجليزيّة'
                          : 'English message',
                      controller: _enCtrl,
                      onSave: (v) =>
                          settings.setBlockedMessageEn(v),
                      hint: DeviceSessionSettings.defaultMsgEn,
                    ),

                    // ===== 5) معاينة =====
                    const SizedBox(height: 18),
                    _SectionTitle(
                      icon: Icons.visibility_outlined,
                      title: isAr ? 'معاينة' : 'Preview',
                    ),
                    const SizedBox(height: 8),
                    _Preview(
                      arText: _arCtrl.text.trim().isEmpty
                          ? DeviceSessionSettings.defaultMsgAr
                          : _arCtrl.text,
                      enText: _enCtrl.text.trim().isEmpty
                          ? DeviceSessionSettings.defaultMsgEn
                          : _enCtrl.text,
                    ),

                    // ===== 6) خيارات إضافيّة =====
                    const SizedBox(height: 18),
                    _SectionTitle(
                      icon: Icons.notifications_outlined,
                      title: isAr ? 'خيارات إضافيّة' : 'Extra options',
                    ),
                    const SizedBox(height: 8),
                    _PolicyCard(
                      title: isAr
                          ? 'إبلاغ المسؤول عند استبدال جهاز'
                          : 'Notify admin on device replacement',
                      subtitle: isAr
                          ? 'يُسجَّل حدث في سجل النشاط عند استبدال جهاز موظف بجهاز جديد'
                          : 'Logs an audit event when an employee\'s device is replaced',
                      value: settings.notifyAdminOnReplace,
                      onChanged: (v) =>
                          settings.setNotifyAdminOnReplace(v),
                    ),

                    // ===== 7) معاينة المتأثّرين =====
                    const SizedBox(height: 18),
                    _SectionTitle(
                      icon: Icons.preview_outlined,
                      title: isAr
                          ? 'معاينة الأثر'
                          : 'Affected accounts',
                    ),
                    Padding(
                      padding: const EdgeInsets.only(
                          left: 4, right: 4, bottom: 8),
                      child: Text(
                        isAr
                            ? 'النتيجة الفعليّة لكلّ شروطك مجتمعةً (تجاوزات + نطاق + قوائم).'
                            : 'Live result of all your conditions combined (overrides + scope + lists).',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.color,
                        ),
                      ),
                    ),
                    const _AffectedPreview(),

                    const SizedBox(height: 24),
                  ],
                ),
        );
      },
    );
  }
}

// ============================================================
// ===== مكوّنات داخليّة =====
// ============================================================

class _InfoBanner extends StatelessWidget {
  final bool isAr;
  const _InfoBanner({required this.isAr});

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
          const Icon(Icons.devices_other,
              color: AppColors.brand, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isAr
                  ? 'تتحكّم هذه الإعدادات في سياسة "جهاز واحد لكل موظف". يمكنك تطبيقها على كلّ الحسابات أو على حسابات مختارة فقط.'
                  : 'These settings control the "one device per employee" policy. Apply it to all accounts or selected ones.',
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
        Text(
          title,
          style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _PolicyCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _PolicyCard({
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
          child: Text(subtitle, style: const TextStyle(fontSize: 12)),
        ),
      ),
    );
  }
}

class _ScopeOption extends StatelessWidget {
  final DevicePolicyScope scope;
  final bool active;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ScopeOption({
    required this.scope,
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
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
            Radio<DevicePolicyScope>(
              value: scope,
              groupValue:
                  active ? scope : DevicePolicyScope.allAccounts,
              onChanged: (_) => onTap(),
              activeColor: color,
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountListCard extends StatelessWidget {
  final bool isAr;
  final Set<String> ids;
  final bool isExempt; // true = excludedOnly (استثناءات)
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
          id: id,
          username: '?',
          passwordHash: '',
          fullName: id,
        );
      }
    }).toList();

    final color =
        isExempt ? AppColors.warning : AppColors.success;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: color.withValues(alpha: 0.3), width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // header
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Row(
              children: [
                Icon(
                  isExempt
                      ? Icons.do_not_disturb_on_outlined
                      : Icons.check_circle_outline,
                  color: color,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isExempt
                        ? (isAr
                            ? 'حسابات مُستثناة'
                            : 'Exempted accounts')
                        : (isAr
                            ? 'حسابات مشمولة'
                            : 'Included accounts'),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('${ids.length}',
                      style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: isAr ? 'إضافة' : 'Add',
                  onPressed: onTapPick,
                  icon: const Icon(Icons.add_circle_outline),
                  color: AppColors.brand,
                ),
              ],
            ),
          ),
          if (accounts.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
              child: Text(
                isAr
                    ? 'لا توجد حسابات في القائمة. اضغط (+) لإضافة'
                    : 'No accounts in the list. Tap (+) to add',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.color),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: accounts.map((a) {
                  return _AccountChip(
                    fullName: a.fullName,
                    username: a.username,
                    color: color,
                    onRemove: () => onRemove(a.id),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class _AccountChip extends StatelessWidget {
  final String fullName;
  final String username;
  final Color color;
  final VoidCallback onRemove;
  const _AccountChip({
    required this.fullName,
    required this.username,
    required this.color,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: color.withValues(alpha: 0.4), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: fullName,
                  style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w700),
                ),
                TextSpan(
                  text: '  @$username',
                  style: TextStyle(
                      color: color.withValues(alpha: 0.7),
                      fontSize: 10),
                ),
              ]),
            ),
          ),
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

class _MessageField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onSave;
  final String hint;
  const _MessageField({
    required this.label,
    required this.controller,
    required this.onSave,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: Theme.of(context).dividerColor, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            maxLines: 3,
            minLines: 2,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(fontSize: 12),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 10),
            ),
            onChanged: onSave,
          ),
        ],
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  final String arText;
  final String enText;
  const _Preview({required this.arText, required this.enText});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _previewBox(context, '🇦🇪', arText, TextDirection.rtl),
        const SizedBox(height: 8),
        _previewBox(context, '🇬🇧', enText, TextDirection.ltr),
      ],
    );
  }

  Widget _previewBox(BuildContext context, String flag, String text,
      TextDirection dir) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: AppColors.danger.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Directionality(
        textDirection: dir,
        child: Row(
          children: [
            Text(flag, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            const Icon(Icons.error_outline,
                color: AppColors.danger, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                    color: AppColors.danger,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 🧰 Bottom-sheet لاختيار حسابات متعدّدة
// ============================================================
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
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.initiallySelected);
  }

  @override
  Widget build(BuildContext context) {
    final isAr = widget.isAr;
    final repo = MockRepository();
    var accounts = List<AppAccount>.from(repo.accounts)
      ..sort((a, b) => a.fullName.compareTo(b.fullName));
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      accounts = accounts
          .where((a) =>
              a.fullName.toLowerCase().contains(q) ||
              a.username.toLowerCase().contains(q))
          .toList();
    }

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(18)),
          ),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Text(
                      isAr ? 'اختيار الحسابات' : 'Select accounts',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.brand.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_selected.length}',
                        style: const TextStyle(
                            color: AppColors.brand,
                            fontWeight: FontWeight.w800,
                            fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: isAr
                        ? 'بحث: اسم أو حساب…'
                        : 'Search name or username…',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: accounts.length,
                  itemBuilder: (ctx, i) {
                    final a = accounts[i];
                    final selected = _selected.contains(a.id);
                    return CheckboxListTile(
                      value: selected,
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            _selected.add(a.id);
                          } else {
                            _selected.remove(a.id);
                          }
                        });
                      },
                      title: Text(
                        a.fullName,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text('@${a.username}',
                          style: const TextStyle(fontSize: 11)),
                      controlAffinity:
                          ListTileControlAffinity.leading,
                      dense: true,
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(isAr ? 'إلغاء' : 'Cancel'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () =>
                            Navigator.pop(context, _selected),
                        child: Text(isAr ? 'حفظ' : 'Save'),
                      ),
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
// 🆕 بطاقة قائمة المسمّيات الوظيفيّة
// ============================================================
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
    final titles = ids.map((id) {
      try {
        return repo.jobTitles.firstWhere((j) => j.id == id);
      } catch (_) {
        return null;
      }
    }).whereType<JobTitle>().toList();

    final color = isExempt ? AppColors.warning : AppColors.success;

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
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Row(
              children: [
                Icon(Icons.badge_outlined, color: color, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isExempt
                        ? (isAr
                            ? 'مسمّيات وظيفيّة مُستثناة'
                            : 'Exempted job titles')
                        : (isAr
                            ? 'مسمّيات وظيفيّة مشمولة'
                            : 'Included job titles'),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('${ids.length}',
                      style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: isAr ? 'إضافة' : 'Add',
                  onPressed: onTapPick,
                  icon: const Icon(Icons.add_circle_outline),
                  color: AppColors.brand,
                ),
              ],
            ),
          ),
          if (titles.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
              child: Text(
                isAr
                    ? 'لا توجد مسمّيات وظيفيّة. اضغط (+) لإضافة'
                    : 'No job titles. Tap (+) to add',
                style: TextStyle(
                    fontSize: 12,
                    color:
                        Theme.of(context).textTheme.bodySmall?.color),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: titles.map((j) {
                  return _JobTitleChip(
                    nameAr: j.nameAr,
                    nameEn: j.nameEn,
                    isAr: isAr,
                    color: color,
                    onRemove: () => onRemove(j.id),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class _JobTitleChip extends StatelessWidget {
  final String nameAr;
  final String nameEn;
  final bool isAr;
  final Color color;
  final VoidCallback onRemove;
  const _JobTitleChip({
    required this.nameAr,
    required this.nameEn,
    required this.isAr,
    required this.color,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: color.withValues(alpha: 0.4), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.badge_outlined, size: 12, color: color),
                const SizedBox(width: 4),
                Text(
                  isAr ? nameAr : nameEn,
                  style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
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

// ============================================================
// 🧰 Bottom-sheet لاختيار مسمّيات وظيفيّة متعدّدة
// ============================================================
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
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.initiallySelected);
  }

  @override
  Widget build(BuildContext context) {
    final isAr = widget.isAr;
    final repo = MockRepository();
    var titles = List<JobTitle>.from(repo.jobTitles)
      ..sort((a, b) => (isAr ? a.nameAr : a.nameEn)
          .compareTo(isAr ? b.nameAr : b.nameEn));
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      titles = titles
          .where((j) =>
              j.nameAr.toLowerCase().contains(q) ||
              j.nameEn.toLowerCase().contains(q))
          .toList();
    }

    // اجمع بحسب الفئة
    final byCategory = <JobTitleCategory, List<JobTitle>>{};
    for (final j in titles) {
      byCategory.putIfAbsent(j.category, () => []).add(j);
    }

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(18)),
          ),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Text(
                      isAr
                          ? 'اختيار مسمّيات وظيفيّة'
                          : 'Select job titles',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.brand.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_selected.length}',
                        style: const TextStyle(
                            color: AppColors.brand,
                            fontWeight: FontWeight.w800,
                            fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: isAr
                        ? 'بحث: اسم المسمّى…'
                        : 'Search title name…',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  children: [
                    for (final entry in byCategory.entries) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                            16, 12, 16, 4),
                        child: Row(
                          children: [
                            Container(
                              width: 4,
                              height: 14,
                              decoration: BoxDecoration(
                                color: AppColors.brand,
                                borderRadius:
                                    BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isAr
                                  ? entry.key.labelAr()
                                  : entry.key.labelEn(),
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(width: 8),
                            Text('(${entry.value.length})',
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors
                                        .textSecondaryLight)),
                          ],
                        ),
                      ),
                      ...entry.value.map((j) {
                        final selected = _selected.contains(j.id);
                        return CheckboxListTile(
                          value: selected,
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                _selected.add(j.id);
                              } else {
                                _selected.remove(j.id);
                              }
                            });
                          },
                          title: Text(
                            isAr ? j.nameAr : j.nameEn,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            isAr ? j.nameEn : j.nameAr,
                            style: const TextStyle(fontSize: 11),
                          ),
                          controlAffinity:
                              ListTileControlAffinity.leading,
                          dense: true,
                        );
                      }),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(isAr ? 'إلغاء' : 'Cancel'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () =>
                            Navigator.pop(context, _selected),
                        child: Text(isAr ? 'حفظ' : 'Save'),
                      ),
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
// 🆕 معاينة المتأثّرين — تعرض كلّ حساب يخضع للسياسة الآن
// ============================================================
class _AffectedPreview extends StatefulWidget {
  const _AffectedPreview();

  @override
  State<_AffectedPreview> createState() => _AffectedPreviewState();
}

class _AffectedPreviewState extends State<_AffectedPreview> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return AnimatedBuilder(
      animation: DeviceSessionSettings.instance,
      builder: (context, _) {
        final settings = DeviceSessionSettings.instance;
        final repo = MockRepository();

        final affected = <_PreviewRow>[];
        final exempted = <_PreviewRow>[];
        for (final a in repo.accounts) {
          final dec = settings.decisionFor(a.id);
          final row = _PreviewRow(account: a, decision: dec);
          if (dec.applies) {
            affected.add(row);
          } else {
            if (dec.reason == PolicyReason.overrideExempt ||
                dec.reason == PolicyReason.accountExcluded ||
                dec.reason == PolicyReason.jobTitleExcluded) {
              exempted.add(row);
            }
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _CountTile(
                    label: isAr ? 'مشمولون' : 'Affected',
                    count: affected.length,
                    color: AppColors.success,
                    icon: Icons.lock_outline,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _CountTile(
                    label: isAr ? 'مُعفون' : 'Exempted',
                    count: exempted.length,
                    color: AppColors.warning,
                    icon: Icons.lock_open_outlined,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _CountTile(
                    label: isAr ? 'الإجمالي' : 'Total',
                    count: repo.accounts.length,
                    color: AppColors.brand,
                    icon: Icons.group_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (!settings.enforceOneDevice &&
                settings.overrides.values
                    .every((v) => v != true)) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: Theme.of(context).dividerColor,
                      width: 0.5),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 16,
                        color: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isAr
                            ? 'السياسة معطّلة عامّة — لا حساب يخضع للقيد حالياً'
                            : 'Policy is globally disabled — no account is currently restricted',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              InkWell(
                onTap: () =>
                    setState(() => _expanded = !_expanded),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding:
                      const EdgeInsets.fromLTRB(12, 10, 8, 10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Theme.of(context).dividerColor,
                        width: 0.5),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _expanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _expanded
                              ? (isAr
                                  ? 'إخفاء التفاصيل'
                                  : 'Hide details')
                              : (isAr
                                  ? 'عرض التفاصيل'
                                  : 'Show details'),
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(
                        '${affected.length + exempted.length}',
                        style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.color),
                      ),
                    ],
                  ),
                ),
              ),
              if (_expanded) ...[
                const SizedBox(height: 10),
                if (affected.isNotEmpty) ...[
                  _GroupHeader(
                    label: isAr
                        ? '🔒 خاضعون للسياسة'
                        : '🔒 Subject to policy',
                    color: AppColors.success,
                    count: affected.length,
                  ),
                  const SizedBox(height: 6),
                  ...affected.map((r) => _PreviewTile(
                        row: r,
                        isAr: isAr,
                        applies: true,
                      )),
                ],
                if (exempted.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _GroupHeader(
                    label: isAr
                        ? '🔓 إعفاءات صريحة'
                        : '🔓 Explicit exemptions',
                    color: AppColors.warning,
                    count: exempted.length,
                  ),
                  const SizedBox(height: 6),
                  ...exempted.map((r) => _PreviewTile(
                        row: r,
                        isAr: isAr,
                        applies: false,
                      )),
                ],
                if (affected.isEmpty && exempted.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      isAr
                          ? 'لا توجد حسابات للعرض'
                          : 'No accounts to display',
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.color),
                    ),
                  ),
              ],
            ],
          ],
        );
      },
    );
  }
}

class _PreviewRow {
  final AppAccount account;
  final PolicyDecision decision;
  _PreviewRow({required this.account, required this.decision});
}

class _CountTile extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;
  const _CountTile({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: color.withValues(alpha: 0.25), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        color: color.withValues(alpha: 0.85),
                        fontSize: 10,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            count.toString(),
            style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                height: 1.0),
          ),
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String label;
  final Color color;
  final int count;
  const _GroupHeader({
    required this.label,
    required this.color,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: color)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$count',
                style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

class _PreviewTile extends StatelessWidget {
  final _PreviewRow row;
  final bool isAr;
  final bool applies;
  const _PreviewTile({
    required this.row,
    required this.isAr,
    required this.applies,
  });

  @override
  Widget build(BuildContext context) {
    final repo = MockRepository();
    final acc = row.account;
    String? jobTitleLabel;
    if (acc.employeeId != null) {
      try {
        final emp = repo.employees
            .firstWhere((e) => e.id == acc.employeeId);
        if (emp.jobTitleId != null) {
          final jt = repo.jobTitles
              .firstWhere((j) => j.id == emp.jobTitleId);
          jobTitleLabel = isAr ? jt.nameAr : jt.nameEn;
        }
      } catch (_) {}
    }

    final c = applies ? AppColors.success : AppColors.warning;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withValues(alpha: 0.25), width: 0.4),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 32,
            decoration: BoxDecoration(
              color: c,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  acc.fullName,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text('@${acc.username}',
                          style: const TextStyle(fontSize: 10),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (jobTitleLabel != null) ...[
                      const SizedBox(width: 6),
                      Text('•',
                          style: TextStyle(
                              fontSize: 10,
                              color: Theme.of(context)
                                  .disabledColor)),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          jobTitleLabel,
                          style: const TextStyle(
                              fontSize: 10,
                              fontStyle: FontStyle.italic),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                row.decision.reasonLabel(isAr: isAr),
                style: TextStyle(
                    color: c,
                    fontSize: 9,
                    fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
