import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/geo_fence_settings.dart';
import '../../core/theme/app_colors.dart';
import '../../models/login_zone.dart';
import '../../models/lookups.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/m7_app_bar.dart';
import 'geo_fence_zone_editor.dart';

/// 🌍 إعدادات Geo-fence
///
/// تتيح:
///   • تفعيل السياسة + اختيار طبقات الفحص (GPS / Wi-Fi / IP)
///   • إدارة المناطق (دبي، الرياض…)
///   • تحديد النطاق (الكلّ / مختارون / الكلّ ما عدا)
///   • قائمة حسابات + قائمة مسمّيات وظيفيّة
///   • تعديل الرسائل
///   • معاينة المتأثّرين
class GeoFenceSettingsScreen extends StatefulWidget {
  const GeoFenceSettingsScreen({super.key});

  @override
  State<GeoFenceSettingsScreen> createState() =>
      _GeoFenceSettingsScreenState();
}

class _GeoFenceSettingsScreenState extends State<GeoFenceSettingsScreen> {
  final _msgRejAr = TextEditingController();
  final _msgRejEn = TextEditingController();
  final _msgMockAr = TextEditingController();
  final _msgMockEn = TextEditingController();
  final _msgPermAr = TextEditingController();
  final _msgPermEn = TextEditingController();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await GeoFenceSettings.instance.load();
    if (!mounted) return;
    final s = GeoFenceSettings.instance;
    setState(() {
      _msgRejAr.text = s.msgRejectedAr;
      _msgRejEn.text = s.msgRejectedEn;
      _msgMockAr.text = s.msgMockAr;
      _msgMockEn.text = s.msgMockEn;
      _msgPermAr.text = s.msgPermAr;
      _msgPermEn.text = s.msgPermEn;
      _ready = true;
    });
  }

  @override
  void dispose() {
    _msgRejAr.dispose();
    _msgRejEn.dispose();
    _msgMockAr.dispose();
    _msgMockEn.dispose();
    _msgPermAr.dispose();
    _msgPermEn.dispose();
    super.dispose();
  }

  Future<void> _editZone(LoginZone? zone) async {
    final r = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => GeoFenceZoneEditor(zone: zone),
      ),
    );
    if (r == true && mounted) setState(() {});
  }

  Future<void> _deleteZone(LoginZone zone) async {
    final isAr = AppStrings.of(context).isAr;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isAr ? 'حذف المنطقة؟' : 'Delete zone?'),
        content: Text(
            '${isAr ? "حذف" : "Delete"} "${isAr ? zone.nameAr : zone.nameEn}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isAr ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isAr ? 'حذف' : 'Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await GeoFenceSettings.instance.removeZone(zone.id);
    }
  }

  Future<void> _pickAccounts() async {
    final settings = GeoFenceSettings.instance;
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
    final settings = GeoFenceSettings.instance;
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
      animation: GeoFenceSettings.instance,
      builder: (context, _) {
        final settings = GeoFenceSettings.instance;
        return Scaffold(
          appBar: M7AppBar(
            title: isAr ? 'سياسة الموقع' : 'Geo-fence',
            subtitle: isAr
                ? 'تقييد الدخول بمناطق محدّدة'
                : 'Restrict login by location',
            actions: [
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
                          ? 'تقييد الدخول بالموقع الجغرافي'
                          : 'Restrict login by location',
                      subtitle: settings.enabled
                          ? (isAr
                              ? 'مُفعَّل: لا يُسمح بالدخول إلّا من المناطق المحدّدة'
                              : 'Enabled: login only from defined zones')
                          : (isAr
                              ? 'مُعطَّل: لا قيد جغرافي على الدخول'
                              : 'Disabled: no geographic restriction'),
                      value: settings.enabled,
                      onChanged: settings.setEnabled,
                    ),

                    if (settings.enabled) ...[
                      // ===== 2) طبقات الفحص =====
                      const SizedBox(height: 18),
                      _SectionTitle(
                        icon: Icons.layers_outlined,
                        title: isAr
                            ? 'طبقات التحقّق'
                            : 'Verification layers',
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 6),
                        child: Text(
                          isAr
                              ? 'كلّ طبقة مفعّلة تُستخدم. تكفي مطابقة طبقة واحدة لقبول الدخول.'
                              : 'Each enabled layer is checked. Matching ONE is enough.',
                          style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.color),
                        ),
                      ),
                      _SwitchCard(
                        title: isAr ? 'GPS' : 'GPS',
                        subtitle: isAr
                            ? 'الأكثر دقّة في الخارج. يحتاج إذن الموقع.'
                            : 'Most accurate outdoors. Requires location permission.',
                        value: settings.checkGps,
                        onChanged: settings.setCheckGps,
                        icon: Icons.gps_fixed,
                      ),
                      const SizedBox(height: 8),
                      _SwitchCard(
                        title: isAr ? 'Wi-Fi' : 'Wi-Fi',
                        subtitle: isAr
                            ? 'يعمل داخل المباني. يطابق أسماء الشبكات بكلّ منطقة.'
                            : 'Works indoors. Matches per-zone Wi-Fi SSIDs.',
                        value: settings.checkWifi,
                        onChanged: settings.setCheckWifi,
                        icon: Icons.wifi,
                      ),
                      const SizedBox(height: 8),
                      _SwitchCard(
                        title: isAr
                            ? 'IP / موقع الإنترنت'
                            : 'IP geolocation',
                        subtitle: isAr
                            ? 'احتياطي ضدّ تزييف GPS. دقّة بمستوى المدينة/الدولة.'
                            : 'Fallback against GPS spoofing. City/country accuracy.',
                        value: settings.checkIp,
                        onChanged: settings.setCheckIp,
                        icon: Icons.public,
                      ),

                      // ===== 3) Mock-location & VPN =====
                      const SizedBox(height: 14),
                      _SwitchCard(
                        title: isAr
                            ? 'رفض تطبيقات تزييف الموقع'
                            : 'Reject mock-location apps',
                        subtitle: isAr
                            ? 'إذا اكتشف الجهاز تطبيقاً يزيّف الموقع، يُرفض الدخول فوراً'
                            : 'Reject login if mock-location app detected',
                        value: settings.rejectMock,
                        onChanged: settings.setRejectMock,
                        icon: Icons.gpp_bad_outlined,
                        color: AppColors.danger,
                      ),
                      const SizedBox(height: 8),
                      _SwitchCard(
                        title: isAr
                            ? 'السماح بالـ VPN'
                            : 'Allow VPN usage',
                        subtitle: isAr
                            ? 'إذا GPS سليم لكن IP من دولة أخرى (احتمال VPN) — اسمح بالدخول مع تحذير'
                            : 'If GPS is OK but IP differs (likely VPN) — allow with warning',
                        value: settings.allowVpn,
                        onChanged: settings.setAllowVpn,
                        icon: Icons.vpn_lock_outlined,
                      ),

                      // ===== 4) المناطق =====
                      const SizedBox(height: 18),
                      _SectionTitle(
                        icon: Icons.map_outlined,
                        title: isAr
                            ? 'المناطق المسموحة'
                            : 'Allowed zones',
                        action: TextButton.icon(
                          onPressed: () => _editZone(null),
                          icon: const Icon(Icons.add, size: 16),
                          label: Text(isAr ? 'إضافة' : 'Add'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (settings.zones.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: AppColors.warning
                                    .withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded,
                                  color: AppColors.warning),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  isAr
                                      ? 'لا توجد مناطق محدّدة بعد. أضف منطقة على الأقلّ ليبدأ التطبيق الفعلي للسياسة.'
                                      : 'No zones defined yet. Add at least one to enforce.',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        ...settings.zones.map((z) => _ZoneCard(
                              zone: z,
                              isAr: isAr,
                              onTap: () => _editZone(z),
                              onDelete: () => _deleteZone(z),
                              onToggle: (v) => settings
                                  .setZoneActive(z.id, v),
                            )),

                      // ===== 5) النطاق =====
                      const SizedBox(height: 18),
                      _SectionTitle(
                        icon: Icons.group_outlined,
                        title: isAr
                            ? 'نطاق التطبيق'
                            : 'Apply scope',
                      ),
                      const SizedBox(height: 6),
                      _ScopeOption(
                        active: settings.scope ==
                            GeoFenceScope.allAccounts,
                        title: isAr
                            ? 'كلّ الحسابات'
                            : 'All accounts',
                        subtitle: isAr
                            ? 'تُطبَّق على كلّ موظّف عند تسجيل الدخول'
                            : 'Applies to every user on login',
                        icon: Icons.people_alt_outlined,
                        color: AppColors.brand,
                        onTap: () => settings
                            .setScope(GeoFenceScope.allAccounts),
                      ),
                      const SizedBox(height: 8),
                      _ScopeOption(
                        active: settings.scope ==
                            GeoFenceScope.includedOnly,
                        title: isAr
                            ? 'حسابات/مسمّيات مختارة فقط'
                            : 'Selected only',
                        subtitle: isAr
                            ? 'تُطبَّق على المختارين فقط'
                            : 'Applies only to listed below',
                        icon: Icons.check_circle_outline,
                        color: AppColors.success,
                        onTap: () => settings
                            .setScope(GeoFenceScope.includedOnly),
                      ),
                      const SizedBox(height: 8),
                      _ScopeOption(
                        active: settings.scope ==
                            GeoFenceScope.excludedOnly,
                        title: isAr
                            ? 'الكلّ ما عدا المختارين'
                            : 'All except selected',
                        subtitle: isAr
                            ? 'تُطبَّق على الكلّ، عدا المختارين (استثناءات)'
                            : 'Applies to all except listed (exemptions)',
                        icon: Icons.do_not_disturb_on_outlined,
                        color: AppColors.warning,
                        onTap: () => settings
                            .setScope(GeoFenceScope.excludedOnly),
                      ),

                      if (settings.scope !=
                          GeoFenceScope.allAccounts) ...[
                        const SizedBox(height: 14),
                        _AccountListCard(
                          isAr: isAr,
                          ids: settings.accountIds,
                          isExempt: settings.scope ==
                              GeoFenceScope.excludedOnly,
                          onTapPick: _pickAccounts,
                          onRemove: settings.removeAccount,
                        ),
                        const SizedBox(height: 12),
                        _JobTitleListCard(
                          isAr: isAr,
                          ids: settings.jobTitleIds,
                          isExempt: settings.scope ==
                              GeoFenceScope.excludedOnly,
                          onTapPick: _pickJobTitles,
                          onRemove: settings.removeJobTitle,
                        ),
                      ],
                    ],

                    // ===== 6) الرسائل =====
                    const SizedBox(height: 18),
                    _SectionTitle(
                      icon: Icons.message_outlined,
                      title: isAr ? 'الرسائل' : 'Messages',
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _MessagePair(
                        title: isAr
                            ? 'موقع غير مسموح'
                            : 'Outside allowed zone',
                        ar: _msgRejAr,
                        en: _msgRejEn,
                        onSaveAr: settings.setMsgRejectedAr,
                        onSaveEn: settings.setMsgRejectedEn,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _MessagePair(
                      title: isAr
                          ? 'كشف تزييف الموقع'
                          : 'Mock-location detected',
                      ar: _msgMockAr,
                      en: _msgMockEn,
                      onSaveAr: settings.setMsgMockAr,
                      onSaveEn: settings.setMsgMockEn,
                    ),
                    const SizedBox(height: 12),
                    _MessagePair(
                      title: isAr
                          ? 'إذن الموقع مرفوض'
                          : 'Location permission denied',
                      ar: _msgPermAr,
                      en: _msgPermEn,
                      onSaveAr: settings.setMsgPermAr,
                      onSaveEn: settings.setMsgPermEn,
                    ),

                    // ===== 7) معاينة المتأثّرين =====
                    if (settings.enabled) ...[
                      const SizedBox(height: 18),
                      _SectionTitle(
                        icon: Icons.preview_outlined,
                        title:
                            isAr ? 'معاينة الأثر' : 'Affected accounts',
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
          const Icon(Icons.public, color: AppColors.brand, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isAr
                  ? 'تتحكّم هذه الإعدادات في تقييد الدخول جغرافياً (مثل: السماح بالدخول من دبي فقط).'
                  : 'These settings restrict login by location (e.g., allow only from Dubai).',
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
  final Widget? action;
  const _SectionTitle({
    required this.icon,
    required this.title,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.brand),
        const SizedBox(width: 6),
        Text(title,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800)),
        const Spacer(),
        if (action != null) action!,
      ],
    );
  }
}

class _SwitchCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final IconData? icon;
  final Color? color;
  const _SwitchCard({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.icon,
    this.color,
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
        title: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: color ?? AppColors.brand),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(subtitle, style: const TextStyle(fontSize: 11)),
        ),
      ),
    );
  }
}

class _ZoneCard extends StatelessWidget {
  final LoginZone zone;
  final bool isAr;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggle;

  const _ZoneCard({
    required this.zone,
    required this.isAr,
    required this.onTap,
    required this.onDelete,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: zone.isActive
                ? AppColors.success.withOpacity(0.4)
                : Theme.of(context).dividerColor,
            width: zone.isActive ? 0.8 : 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.brand.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.place,
                    color: AppColors.brand, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(isAr ? zone.nameAr : zone.nameEn,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                      '${zone.radiusKm.toStringAsFixed(1)} km'
                      ' • ${zone.centerLat.toStringAsFixed(3)}, ${zone.centerLng.toStringAsFixed(3)}'
                      '${zone.ipCountryCode != null ? " • ${zone.ipCountryCode}" : ""}'
                      '${zone.wifiSsids.isNotEmpty ? " • ${zone.wifiSsids.length} Wi-Fi" : ""}',
                      style: const TextStyle(
                          fontSize: 10, fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Switch(
                value: zone.isActive,
                onChanged: onToggle,
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: isAr ? 'تعديل' : 'Edit',
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    padding: const EdgeInsets.all(4),
                    onPressed: onTap,
                  ),
                  IconButton(
                    tooltip: isAr ? 'حذف' : 'Delete',
                    icon: const Icon(Icons.delete_outline, size: 18),
                    padding: const EdgeInsets.all(4),
                    color: AppColors.danger,
                    onPressed: onDelete,
                  ),
                ],
              ),
            ],
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
            if (active)
              Icon(Icons.check_circle, color: color, size: 18),
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
// 🧑 Account / 🆔 JobTitle list cards + pickers
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
          id: id,
          username: '?',
          passwordHash: '',
          fullName: id,
        );
      }
    }).toList();
    final color = isExempt ? AppColors.warning : AppColors.success;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: color.withOpacity(0.3), width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                isAr
                    ? 'لا توجد حسابات. اضغط (+) لإضافة'
                    : 'No accounts. Tap (+)',
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
        border:
            Border.all(color: color.withOpacity(0.3), width: 0.6),
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
                isAr
                    ? 'لا توجد مسمّيات. اضغط (+)'
                    : 'No job titles. Tap (+)',
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

// ============================================================
// 🧰 Pickers (مكرّرة من شاشة DeviceSession لكن مستقلّة)
// ============================================================
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
      title: isAr ? 'اختيار مسمّيات' : 'Select job titles',
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
// معاينة المتأثّرين
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
      animation: GeoFenceSettings.instance,
      builder: (context, _) {
        final settings = GeoFenceSettings.instance;
        final repo = MockRepository();
        final affected = <_PreviewRow>[];
        final exempted = <_PreviewRow>[];
        for (final a in repo.accounts) {
          final dec = settings.decisionFor(a.id);
          final row = _PreviewRow(account: a, decision: dec);
          if (dec.applies) {
            affected.add(row);
          } else if (dec.reason ==
                  GeoFenceReason.overrideExempt ||
              dec.reason == GeoFenceReason.accountExcluded ||
              dec.reason == GeoFenceReason.jobTitleExcluded) {
            exempted.add(row);
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
                    row: r, isAr: isAr, applies: true)),
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
                    row: r, isAr: isAr, applies: false)),
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
  final GeoFenceDecision decision;
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
        border:
            Border.all(color: color.withOpacity(0.25), width: 0.5),
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
