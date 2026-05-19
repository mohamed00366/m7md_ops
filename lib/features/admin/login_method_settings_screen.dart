import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/face_attempt_tracker.dart';
import '../../core/services/login_method_settings.dart';
import '../../core/theme/app_colors.dart';
import '../../models/lookups.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/m7_app_bar.dart';

/// 🔐 شاشة إعدادات "طريقة الدخول" (كلمة مرور / بصمة الوجه)
class LoginMethodSettingsScreen extends StatefulWidget {
  const LoginMethodSettingsScreen({super.key});
  @override
  State<LoginMethodSettingsScreen> createState() =>
      _LoginMethodSettingsScreenState();
}

class _LoginMethodSettingsScreenState
    extends State<LoginMethodSettingsScreen> {
  final _wrongAr = TextEditingController();
  final _wrongEn = TextEditingController();
  final _failedAr = TextEditingController();
  final _failedEn = TextEditingController();
  final _coolAr = TextEditingController();
  final _coolEn = TextEditingController();
  final _lockAr = TextEditingController();
  final _lockEn = TextEditingController();
  final _notEnrAr = TextEditingController();
  final _notEnrEn = TextEditingController();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await LoginMethodSettings.instance.load();
    if (!mounted) return;
    final s = LoginMethodSettings.instance;
    setState(() {
      _wrongAr.text = s.msgWrongMethodAr;
      _wrongEn.text = s.msgWrongMethodEn;
      _failedAr.text = s.msgFaceFailedAr;
      _failedEn.text = s.msgFaceFailedEn;
      _coolAr.text = s.msgCooldownAr;
      _coolEn.text = s.msgCooldownEn;
      _lockAr.text = s.msgLockedAr;
      _lockEn.text = s.msgLockedEn;
      _notEnrAr.text = s.msgNotEnrolledAr;
      _notEnrEn.text = s.msgNotEnrolledEn;
      _ready = true;
    });
  }

  @override
  void dispose() {
    _wrongAr.dispose();
    _wrongEn.dispose();
    _failedAr.dispose();
    _failedEn.dispose();
    _coolAr.dispose();
    _coolEn.dispose();
    _lockAr.dispose();
    _lockEn.dispose();
    _notEnrAr.dispose();
    _notEnrEn.dispose();
    super.dispose();
  }

  Future<void> _pickAccounts() async {
    final settings = LoginMethodSettings.instance;
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
    final settings = LoginMethodSettings.instance;
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

  Future<void> _showLockedAccounts() async {
    final isAr = AppStrings.of(context).isAr;
    final ids = await FaceAttemptTracker.instance.lockedAccounts();
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => _LockedAccountsSheet(
        accountIds: ids,
        isAr: isAr,
        onUnlock: (id) async {
          await FaceAttemptTracker.instance.unlockAccount(id);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              backgroundColor: AppColors.success,
              content: Text(isAr ? '✓ تمّ فكّ القفل' : '✓ Unlocked'),
            ));
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    return AnimatedBuilder(
      animation: LoginMethodSettings.instance,
      builder: (context, _) {
        final settings = LoginMethodSettings.instance;
        final showLists = settings.scope != LoginMethodScope.allAccounts;
        return Scaffold(
          appBar: M7AppBar(
            title: isAr ? 'طريقة الدخول' : 'Login Method',
            subtitle: isAr
                ? 'كلمة المرور / بصمة الوجه'
                : 'Password / Face ID',
            actions: [
              M7AppBarAction(
                icon: Icons.lock_open,
                tooltip:
                    isAr ? 'الحسابات المقفلة' : 'Locked accounts',
                onPressed: _showLockedAccounts,
              ),
              M7AppBarAction(
                icon: Icons.restore,
                tooltip: isAr ? 'القيم الافتراضية' : 'Reset',
                onPressed: _ready
                    ? () async {
                        await settings.resetToDefaults();
                        await _load();
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

                    // ===== 1) المفتاح الرئيسي =====
                    _SectionTitle(
                      icon: Icons.policy_outlined,
                      title: isAr ? 'السياسة' : 'Policy',
                    ),
                    const SizedBox(height: 8),
                    _SwitchCard(
                      title: isAr
                          ? 'تفعيل سياسة طريقة الدخول'
                          : 'Enable login-method policy',
                      subtitle: settings.enabled
                          ? (isAr
                              ? 'مفعّلة: تستطيع تخصيص طريقة الدخول لحسابات/مسمّيات معيّنة'
                              : 'Enabled: customize login method per account/title')
                          : (isAr
                              ? 'معطّلة: الكلّ يستخدم الطريقة الافتراضيّة'
                              : 'Disabled: everyone uses the default method'),
                      value: settings.enabled,
                      onChanged: settings.setEnabled,
                    ),

                    // ===== 2) الطريقة الافتراضيّة =====
                    const SizedBox(height: 18),
                    _SectionTitle(
                      icon: Icons.tune_outlined,
                      title: isAr
                          ? 'الطريقة الافتراضيّة'
                          : 'Default method',
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 8),
                      child: Text(
                        isAr
                            ? 'الطريقة المستخدمة لمن لا تنطبق عليه قاعدة استثنائيّة'
                            : 'Method used for everyone unless overridden',
                        style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.color),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _MethodOption(
                            method: LoginMethod.password,
                            active: settings.defaultMethod ==
                                LoginMethod.password,
                            isAr: isAr,
                            onTap: () => settings.setDefaultMethod(
                                LoginMethod.password),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _MethodOption(
                            method: LoginMethod.face,
                            active: settings.defaultMethod ==
                                LoginMethod.face,
                            isAr: isAr,
                            onTap: () => settings.setDefaultMethod(
                                LoginMethod.face),
                          ),
                        ),
                      ],
                    ),

                    if (settings.enabled) ...[
                      // ===== 3) النطاق =====
                      const SizedBox(height: 18),
                      _SectionTitle(
                        icon: Icons.group_outlined,
                        title: isAr
                            ? 'مَن يستخدم الطريقة الأخرى؟'
                            : 'Who uses the OTHER method?',
                      ),
                      Padding(
                        padding: const EdgeInsets.only(
                            top: 4, bottom: 8),
                        child: Text(
                          isAr
                              ? 'الطريقة الأخرى: ${settings.defaultMethod == LoginMethod.password ? "بصمة الوجه" : "كلمة المرور"}'
                              : 'Other method: ${settings.defaultMethod == LoginMethod.password ? "Face ID" : "Password"}',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.brand),
                        ),
                      ),
                      _ScopeOption(
                        active: settings.scope ==
                            LoginMethodScope.allAccounts,
                        title: isAr
                            ? 'الكلّ يستخدم الافتراضيّة'
                            : 'All use default',
                        subtitle: isAr
                            ? 'لا حساب يستخدم طريقة مختلفة'
                            : 'No account uses the other method',
                        icon: Icons.people_alt_outlined,
                        color: AppColors.brand,
                        onTap: () => settings.setScope(
                            LoginMethodScope.allAccounts),
                      ),
                      const SizedBox(height: 8),
                      _ScopeOption(
                        active: settings.scope ==
                            LoginMethodScope.includedOnly,
                        title: isAr
                            ? 'مختارون يستخدمون الطريقة الأخرى'
                            : 'Selected use OTHER method',
                        subtitle: isAr
                            ? 'الباقي يستخدم الافتراضيّة'
                            : 'Rest use default',
                        icon: Icons.check_circle_outline,
                        color: AppColors.success,
                        onTap: () => settings.setScope(
                            LoginMethodScope.includedOnly),
                      ),
                      const SizedBox(height: 8),
                      _ScopeOption(
                        active: settings.scope ==
                            LoginMethodScope.excludedOnly,
                        title: isAr
                            ? 'الكلّ يستخدم الأخرى ما عدا مختارين'
                            : 'All use OTHER except selected',
                        subtitle: isAr
                            ? 'المستثنون يستخدمون الافتراضيّة'
                            : 'Exempted use default',
                        icon: Icons.do_not_disturb_on_outlined,
                        color: AppColors.warning,
                        onTap: () => settings.setScope(
                            LoginMethodScope.excludedOnly),
                      ),

                      if (showLists) ...[
                        const SizedBox(height: 14),
                        _AccountListCard(
                          isAr: isAr,
                          ids: settings.accountIds,
                          isExempt: settings.scope ==
                              LoginMethodScope.excludedOnly,
                          onTapPick: _pickAccounts,
                          onRemove: settings.removeAccount,
                        ),
                        const SizedBox(height: 12),
                        _JobTitleListCard(
                          isAr: isAr,
                          ids: settings.jobTitleIds,
                          isExempt: settings.scope ==
                              LoginMethodScope.excludedOnly,
                          onTapPick: _pickJobTitles,
                          onRemove: settings.removeJobTitle,
                        ),
                      ],
                    ],

                    // ===== 4) إعدادات المحاولات الفاشلة =====
                    const SizedBox(height: 18),
                    _SectionTitle(
                      icon: Icons.shield_outlined,
                      title: isAr
                          ? 'سياسة الفشل والقفل'
                          : 'Failure & lockout',
                    ),
                    const SizedBox(height: 8),
                    _NumberCard(
                      label: isAr
                          ? 'عدد المحاولات قبل التهدئة'
                          : 'Attempts before cooldown',
                      value: settings.maxAttempts,
                      min: 1,
                      max: 10,
                      onChanged: settings.setMaxAttempts,
                      icon: Icons.repeat,
                    ),
                    const SizedBox(height: 8),
                    _NumberCard(
                      label: isAr
                          ? 'مدّة التهدئة (دقائق)'
                          : 'Cooldown duration (minutes)',
                      value: settings.cooldownMinutes,
                      min: 1,
                      max: 60,
                      onChanged: settings.setCooldownMinutes,
                      icon: Icons.timer_outlined,
                    ),
                    const SizedBox(height: 8),
                    _SwitchCard(
                      title: isAr
                          ? 'كلمة المرور كنسخة احتياطيّة'
                          : 'Password as fallback',
                      subtitle: isAr
                          ? 'لو فشلت بصمة الوجه، اسمح بكلمة المرور (بدلاً من القفل)'
                          : 'If Face fails, allow password instead of lock',
                      value: settings.allowPwdFallback,
                      onChanged: settings.setAllowPwdFallback,
                    ),

                    // ===== 5) الرسائل =====
                    const SizedBox(height: 18),
                    _SectionTitle(
                      icon: Icons.message_outlined,
                      title: isAr ? 'الرسائل' : 'Messages',
                    ),
                    const SizedBox(height: 8),
                    _MessagePair(
                      title: isAr
                          ? 'تبويبة خاطئة'
                          : 'Wrong tab selected',
                      ar: _wrongAr,
                      en: _wrongEn,
                      onSaveAr: settings.setMsgWrongMethodAr,
                      onSaveEn: settings.setMsgWrongMethodEn,
                    ),
                    const SizedBox(height: 12),
                    _MessagePair(
                      title: isAr
                          ? 'فشل التعرّف على الوجه'
                          : 'Face not recognized',
                      ar: _failedAr,
                      en: _failedEn,
                      onSaveAr: settings.setMsgFaceFailedAr,
                      onSaveEn: settings.setMsgFaceFailedEn,
                    ),
                    const SizedBox(height: 12),
                    _MessagePair(
                      title: isAr
                          ? 'تهدئة بعد عدّة محاولات'
                          : 'Cooldown active',
                      ar: _coolAr,
                      en: _coolEn,
                      onSaveAr: settings.setMsgCooldownAr,
                      onSaveEn: settings.setMsgCooldownEn,
                    ),
                    const SizedBox(height: 12),
                    _MessagePair(
                      title: isAr
                          ? 'الحساب مقفل'
                          : 'Account locked',
                      ar: _lockAr,
                      en: _lockEn,
                      onSaveAr: settings.setMsgLockedAr,
                      onSaveEn: settings.setMsgLockedEn,
                    ),
                    const SizedBox(height: 12),
                    _MessagePair(
                      title: isAr
                          ? 'لم تُسجَّل البصمة بعد'
                          : 'Not enrolled yet',
                      ar: _notEnrAr,
                      en: _notEnrEn,
                      onSaveAr: settings.setMsgNotEnrolledAr,
                      onSaveEn: settings.setMsgNotEnrolledEn,
                    ),

                    // ===== 6) معاينة المتأثّرين =====
                    const SizedBox(height: 18),
                    _SectionTitle(
                      icon: Icons.preview_outlined,
                      title:
                          isAr ? 'معاينة الأثر' : 'Method per account',
                    ),
                    const SizedBox(height: 8),
                    const _AffectedPreview(),

                    const SizedBox(height: 30),
                  ],
                ),
        );
      },
    );
  }
}

// ============================================================
// Internal widgets
// ============================================================
class _Banner extends StatelessWidget {
  final bool isAr;
  const _Banner({required this.isAr});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.brand.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: AppColors.brand.withOpacity(0.25), width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.face, color: AppColors.brand, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isAr
                  ? 'حدّد لكلّ موظّف طريقة دخوله: كلمة مرور أو بصمة وجه. يمكنك تطبيق الاختيار حسب الحساب أو المسمّى الوظيفي.'
                  : 'Define each employee\'s login method: password or face. Apply per account or job title.',
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
                    fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, size: 20),
            onPressed:
                value > min ? () => onChanged(value - 1) : null,
          ),
          Container(
            width: 40,
            alignment: Alignment.center,
            child: Text(
              '$value',
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w900),
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

class _MethodOption extends StatelessWidget {
  final LoginMethod method;
  final bool active;
  final bool isAr;
  final VoidCallback onTap;
  const _MethodOption({
    required this.method,
    required this.active,
    required this.isAr,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final color = method == LoginMethod.password
        ? AppColors.brand
        : AppColors.success;
    final icon =
        method == LoginMethod.password ? Icons.password : Icons.face;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: active
              ? color.withOpacity(0.12)
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active
                ? color.withOpacity(0.6)
                : Theme.of(context).dividerColor,
            width: active ? 1.5 : 0.5,
          ),
        ),
        child: Column(
          children: [
            Icon(icon,
                size: 26,
                color: active
                    ? color
                    : Theme.of(context).iconTheme.color),
            const SizedBox(height: 6),
            Text(
              isAr ? method.labelAr() : method.labelEn(),
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: active ? color : null),
            ),
          ],
        ),
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
              ? color.withOpacity(0.08)
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active
                ? color.withOpacity(0.6)
                : Theme.of(context).dividerColor,
            width: active ? 1.2 : 0.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
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
            if (active) Icon(Icons.check_circle, color: color, size: 18),
          ],
        ),
      ),
    );
  }
}

class _MessagePair extends StatelessWidget {
  final String title;
  final TextEditingController ar;
  final TextEditingController en;
  final ValueChanged<String> onSaveAr;
  final ValueChanged<String> onSaveEn;
  const _MessagePair({
    required this.title,
    required this.ar,
    required this.en,
    required this.onSaveAr,
    required this.onSaveEn,
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
          Text(title,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          TextField(
            controller: ar,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'العربيّة',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: onSaveAr,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: en,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'English',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: onSaveEn,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Account / JobTitle list cards + pickers + locked sheet
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
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3), width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 6),
            child: Row(
              children: [
                Icon(
                    isExempt
                        ? Icons.do_not_disturb_on_outlined
                        : Icons.check_circle_outline,
                    color: color,
                    size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isExempt
                        ? (isAr
                            ? 'حسابات مستثناة'
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
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('${ids.length}',
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
          if (accounts.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
              child: Text(
                isAr ? 'لا توجد حسابات' : 'No accounts',
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
                children: accounts
                    .map((a) => _ChipDel(
                          label: a.fullName,
                          sub: '@${a.username}',
                          color: color,
                          onRemove: () => onRemove(a.id),
                        ))
                    .toList(),
              ),
            ),
        ],
      ),
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
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3), width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 6),
            child: Row(
              children: [
                Icon(Icons.badge_outlined, color: color, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isExempt
                        ? (isAr
                            ? 'مسمّيات وظيفيّة مستثناة'
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
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('${ids.length}',
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
          if (titles.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
              child: Text(
                isAr ? 'لا توجد مسمّيات' : 'No job titles',
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
                children: titles
                    .map((j) => _ChipDel(
                          label: isAr ? j.nameAr : j.nameEn,
                          sub: '',
                          color: color,
                          icon: Icons.badge_outlined,
                          onRemove: () => onRemove(j.id),
                        ))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChipDel extends StatelessWidget {
  final String label;
  final String sub;
  final Color color;
  final IconData? icon;
  final VoidCallback onRemove;
  const _ChipDel({
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
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4), width: 0.5),
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
                    color: color.withOpacity(0.7), fontSize: 10)),
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

// ====== Pickers ======
class _AccountPickerSheet extends StatefulWidget {
  final Set<String> initiallySelected;
  final bool isAr;
  const _AccountPickerSheet({
    required this.initiallySelected,
    required this.isAr,
  });
  @override
  State<_AccountPickerSheet> createState() => _AccountPickerSheetState();
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
    return _PickerScaffold(
      title: isAr ? 'اختيار الحسابات' : 'Select accounts',
      isAr: isAr,
      count: _selected.length,
      onSearch: (v) => setState(() => _query = v),
      onCancel: () => Navigator.pop(context),
      onSave: () => Navigator.pop(context, _selected),
      child: ListView.builder(
        itemCount: accounts.length,
        itemBuilder: (ctx, i) {
          final a = accounts[i];
          final sel = _selected.contains(a.id);
          return CheckboxListTile(
            value: sel,
            onChanged: (v) {
              setState(() {
                if (v == true) {
                  _selected.add(a.id);
                } else {
                  _selected.remove(a.id);
                }
              });
            },
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
    return _PickerScaffold(
      title: isAr ? 'اختيار مسمّيات' : 'Select titles',
      isAr: isAr,
      count: _selected.length,
      onSearch: (v) => setState(() => _query = v),
      onCancel: () => Navigator.pop(context),
      onSave: () => Navigator.pop(context, _selected),
      child: ListView.builder(
        itemCount: titles.length,
        itemBuilder: (ctx, i) {
          final j = titles[i];
          final sel = _selected.contains(j.id);
          return CheckboxListTile(
            value: sel,
            onChanged: (v) {
              setState(() {
                if (v == true) {
                  _selected.add(j.id);
                } else {
                  _selected.remove(j.id);
                }
              });
            },
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
                    Text(title,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w900)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.brand.withOpacity(0.12),
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
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: isAr ? 'بحث…' : 'Search…',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
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
                        child: Text(isAr ? 'إلغاء' : 'Cancel'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: onSave,
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
// 🔓 Locked accounts sheet
// ============================================================
class _LockedAccountsSheet extends StatefulWidget {
  final List<String> accountIds;
  final bool isAr;
  final Future<void> Function(String) onUnlock;
  const _LockedAccountsSheet({
    required this.accountIds,
    required this.isAr,
    required this.onUnlock,
  });
  @override
  State<_LockedAccountsSheet> createState() =>
      _LockedAccountsSheetState();
}

class _LockedAccountsSheetState extends State<_LockedAccountsSheet> {
  late List<String> _ids;

  @override
  void initState() {
    super.initState();
    _ids = List.from(widget.accountIds);
  }

  @override
  Widget build(BuildContext context) {
    final isAr = widget.isAr;
    final repo = MockRepository();
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(18)),
        ),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
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
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.lock,
                      color: AppColors.danger, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isAr
                          ? 'الحسابات المقفلة'
                          : 'Locked accounts',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900),
                    ),
                  ),
                  Text('${_ids.length}',
                      style: const TextStyle(
                          color: AppColors.danger,
                          fontSize: 14,
                          fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _ids.isEmpty
                  ? Center(
                      child: Text(
                        isAr
                            ? '✓ لا توجد حسابات مقفلة'
                            : '✓ No locked accounts',
                        style: TextStyle(
                            color: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.color),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _ids.length,
                      itemBuilder: (ctx, i) {
                        final id = _ids[i];
                        AppAccount? acc;
                        try {
                          acc = repo.accounts
                              .firstWhere((a) => a.id == id);
                        } catch (_) {}
                        return ListTile(
                          leading: const CircleAvatar(
                            backgroundColor:
                                Color(0x33FF3B30),
                            child: Icon(Icons.lock,
                                color: AppColors.danger),
                          ),
                          title: Text(acc?.fullName ?? id,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700)),
                          subtitle: Text(
                              acc != null
                                  ? '@${acc.username}'
                                  : id,
                              style: const TextStyle(
                                  fontSize: 11)),
                          trailing: TextButton.icon(
                            icon: const Icon(Icons.lock_open,
                                size: 16),
                            label: Text(
                                isAr ? 'فكّ القفل' : 'Unlock'),
                            onPressed: () async {
                              await widget.onUnlock(id);
                              setState(() => _ids.remove(id));
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 👁️ Affected preview
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
      animation: LoginMethodSettings.instance,
      builder: (context, _) {
        final settings = LoginMethodSettings.instance;
        final repo = MockRepository();
        final passwordUsers = <_PreviewRow>[];
        final faceUsers = <_PreviewRow>[];
        for (final a in repo.accounts) {
          final dec = settings.decisionFor(a.id);
          final row = _PreviewRow(account: a, decision: dec);
          if (dec.method == LoginMethod.password) {
            passwordUsers.add(row);
          } else {
            faceUsers.add(row);
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _CountTile(
                    label: isAr ? 'كلمة المرور' : 'Password',
                    count: passwordUsers.length,
                    color: AppColors.brand,
                    icon: Icons.password,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _CountTile(
                    label: isAr ? 'بصمة الوجه' : 'Face ID',
                    count: faceUsers.length,
                    color: AppColors.success,
                    icon: Icons.face,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _CountTile(
                    label: isAr ? 'الإجمالي' : 'Total',
                    count: repo.accounts.length,
                    color: AppColors.warning,
                    icon: Icons.group_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
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
                    Icon(_expanded
                        ? Icons.expand_less
                        : Icons.expand_more),
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
                  ],
                ),
              ),
            ),
            if (_expanded) ...[
              const SizedBox(height: 8),
              if (faceUsers.isNotEmpty) ...[
                _GroupHeader(
                  label: isAr ? '👤 بصمة الوجه' : '👤 Face ID',
                  color: AppColors.success,
                  count: faceUsers.length,
                ),
                const SizedBox(height: 6),
                ...faceUsers.map((r) => _PreviewTile(
                    row: r, isAr: isAr, isFace: true)),
              ],
              if (passwordUsers.isNotEmpty) ...[
                const SizedBox(height: 12),
                _GroupHeader(
                  label: isAr ? '🔑 كلمة المرور' : '🔑 Password',
                  color: AppColors.brand,
                  count: passwordUsers.length,
                ),
                const SizedBox(height: 6),
                ...passwordUsers.map((r) => _PreviewTile(
                    row: r, isAr: isAr, isFace: false)),
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
  final LoginMethodDecision decision;
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
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25), width: 0.5),
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
                        color: color.withOpacity(0.85),
                        fontSize: 10,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(count.toString(),
              style: TextStyle(
                  color: color,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  height: 1.0)),
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
              color: color.withOpacity(0.12),
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
  final bool isFace;
  const _PreviewTile({
    required this.row,
    required this.isAr,
    required this.isFace,
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
    final c = isFace ? AppColors.success : AppColors.brand;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withOpacity(0.25), width: 0.4),
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
              children: [
                Text(acc.fullName,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
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
                              color: Theme.of(context).disabledColor,
                              fontSize: 10)),
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
          const SizedBox(width: 6),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: c.withOpacity(0.12),
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
