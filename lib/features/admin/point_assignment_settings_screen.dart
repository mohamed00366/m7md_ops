import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/point_assignment_settings.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/lookups.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/m7_app_bar.dart';

/// ⚙️ شاشة إعدادات إسناد النقاط
///
/// تتيح للمسؤول تحديد أيّ مسمّيات وظيفيّة تظهر كمرشّحين عند ربط موظف بنقطة.
///
/// الافتراضيّ: Site Supervisor + كل من يتبع له (Marshal/KC/Valet)
/// المسؤول يستطيع:
///   - إضافة مسمّيات إضافيّة (مثلاً: Bus Driver لمن يريد ذلك)
///   - استبعاد مسمّيات (لتقييد الترقية)
///   - استعادة الافتراضيّ بنقرة
class PointAssignmentSettingsScreen extends StatefulWidget {
  const PointAssignmentSettingsScreen({super.key});

  @override
  State<PointAssignmentSettingsScreen> createState() =>
      _PointAssignmentSettingsScreenState();
}

class _PointAssignmentSettingsScreenState
    extends State<PointAssignmentSettingsScreen> {
  Set<String> _selected = {};
  bool _hasCustom = false;
  bool _loaded = false;
  // 🆕 مُسمّى الترقية + علم الوَراثة
  String? _promotionTargetId;
  bool _inheritTargetPerms = true;

  @override
  void initState() {
    super.initState();
    _load();
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

  Future<void> _load() async {
    await PointAssignmentSettings.instance.load();
    if (!mounted) return;
    setState(() {
      _selected = Set.from(PointAssignmentSettings.instance.current);
      _hasCustom = PointAssignmentSettings.instance.hasCustom;
      _promotionTargetId =
          PointAssignmentSettings.instance.promotionTargetJobTitleId;
      _inheritTargetPerms =
          PointAssignmentSettings.instance.inheritTargetPerms;
      _loaded = true;
      // إن لم يكن هناك إعداد مخصّص، اعرض الافتراضيّ كقيم مفعّلة
      if (!_hasCustom) {
        _selected = _defaultEligible(MockRepository());
      }
    });
  }

  /// المُسمّى الافتراضيّ للترقية (Site Supervisor) لو وُجد.
  String? _defaultPromotionTargetId(MockRepository repo) {
    try {
      return repo.jobTitles.firstWhere((j) => j.nameEn == 'Site Supervisor').id;
    } catch (_) {
      return null;
    }
  }

  /// القاعدة الافتراضيّة: Site Supervisor + كلّ من يتبع له
  Set<String> _defaultEligible(MockRepository repo) {
    JobTitle? siteSup;
    try {
      siteSup =
          repo.jobTitles.firstWhere((j) => j.nameEn == 'Site Supervisor');
    } catch (_) {
      return {};
    }
    final result = <String>{siteSup.id};
    for (final j in repo.jobTitles) {
      if (j.reportsToIds.contains(siteSup.id)) {
        result.add(j.id);
      }
    }
    return result;
  }

  Future<void> _saveAndApply() async {
    await PointAssignmentSettings.instance.setAll(_selected);
    await PointAssignmentSettings.instance
        .setPromotionTarget(_promotionTargetId);
    await PointAssignmentSettings.instance
        .setInheritTargetPerms(_inheritTargetPerms);
    if (!mounted) return;
    setState(() => _hasCustom = true);
    final s = AppStrings.of(context);
    final cloudReady = SupabaseService().isReady;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: cloudReady ? AppColors.success : AppColors.warning,
      duration: Duration(seconds: cloudReady ? 2 : 5),
      content: Text(cloudReady
          ? (s.isAr
              ? '✅ تَمّ الحفظ في السَحابة — ${_selected.length} مسمّى مؤهّل'
              : '✅ Saved to cloud — ${_selected.length} eligible titles')
          : (s.isAr
              ? '⚠ حُفظ مَحلّيّاً فقط (Supabase غير مُتَّصل)'
              : '⚠ Saved locally only (Supabase offline)')),
    ));
  }

  /// 🆕 إعادة تَحميل من Supabase — يُلاقِي التَغييرات من أَجهزة أُخرى.
  Future<void> _reloadFromCloud() async {
    if (!SupabaseService().isReady) return;
    await PointAssignmentSettings.instance.reload();
    if (!mounted) return;
    setState(() {
      _selected = Set.from(PointAssignmentSettings.instance.current);
      _hasCustom = PointAssignmentSettings.instance.hasCustom;
      _promotionTargetId =
          PointAssignmentSettings.instance.promotionTargetJobTitleId;
      _inheritTargetPerms =
          PointAssignmentSettings.instance.inheritTargetPerms;
      if (!_hasCustom) {
        _selected = _defaultEligible(MockRepository());
      }
    });
    final s = AppStrings.of(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.info,
      duration: const Duration(seconds: 2),
      content: Text(s.isAr
          ? '🔄 تَمّ التَحديث من السَحابة'
          : '🔄 Refreshed from cloud'),
    ));
  }

  Future<void> _resetToDefault() async {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isAr ? '↩️ استعادة الافتراضي' : '↩️ Reset to default'),
        content: Text(isAr
            ? 'سيتمّ مسح إعدادك المخصّص وإرجاعه للقاعدة الافتراضيّة (Site Supervisor + من يتبع له).'
            : 'Your custom setting will be cleared. Default rule will apply (Site Supervisor + reports).'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isAr ? 'استعادة' : 'Reset'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await PointAssignmentSettings.instance.resetToDefault();
    setState(() {
      _hasCustom = false;
      _selected = _defaultEligible(MockRepository());
      _promotionTargetId = null;
      _inheritTargetPerms = true;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.info,
      content:
          Text(isAr ? '↩️ تمّت العودة للافتراضي' : '↩️ Reverted to default'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final repo = MockRepository();
    final allTitles = repo.jobTitles.toList()
      ..sort((a, b) {
        final lc = a.level.compareTo(b.level);
        if (lc != 0) return lc;
        return a.nameAr.compareTo(b.nameAr);
      });

    if (!_loaded) {
      return Scaffold(
        appBar: M7AppBar(
            title: s.isAr ? '⚙️ إسناد المُوَظَّفين لِلنُقَط' : '⚙️ Assign Employees to Points'),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final defaultIds = _defaultEligible(repo);
    final defaultTargetId = _defaultPromotionTargetId(repo);
    final settingsTargetId =
        PointAssignmentSettings.instance.promotionTargetJobTitleId;
    final settingsInherit =
        PointAssignmentSettings.instance.inheritTargetPerms;
    final eligibleDirty = !_setEquals(_selected,
        _hasCustom ? PointAssignmentSettings.instance.current : defaultIds);
    final targetDirty = (_promotionTargetId ?? defaultTargetId) !=
        (settingsTargetId ?? defaultTargetId);
    final inheritDirty = _inheritTargetPerms != settingsInherit;
    final dirty = eligibleDirty || targetDirty || inheritDirty;
    // المُسمّيات المتاحة كهَدَف للترقية (يُفضَّل L3+ لِيكون أعلى من L4)
    final targetCandidates = repo.jobTitles
        .where((j) => j.level <= 3 || j.level == 0)
        .toList()
      ..sort((a, b) {
        final lc = a.level.compareTo(b.level);
        if (lc != 0) return lc;
        return a.nameAr.compareTo(b.nameAr);
      });

    return Scaffold(
      appBar: M7AppBar(
        title: s.isAr ? '⚙️ إسناد المُوَظَّفين لِلنُقَط' : '⚙️ Assign Employees to Points',
      ),
      body: Column(
        children: [
          // ===== Info banner =====
          Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.brand.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.brand.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                const Icon(Icons.pin_drop_outlined,
                    color: AppColors.brand, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isAr
                            ? 'مَن يظهر في شاشة "إسناد الموظفين للنقاط"؟'
                            : 'Who appears in "Assign Employees to Points"?',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isAr
                            ? 'فعّل المسمّيات التي يحقّ لحامليها أن يُسندوا إلى نقطة (يُرقّون تلقائيّاً إلى المُسمّى الهَدَف)'
                            : 'Enable titles whose holders can be assigned to a point (auto-promoted to the target title)',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // ===== Status badge =====
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                if (_hasCustom)
                  _statusChip(
                    icon: Icons.tune,
                    label: isAr ? 'مخصّص' : 'Custom',
                    color: AppColors.warning,
                  )
                else
                  _statusChip(
                    icon: Icons.auto_awesome,
                    label: isAr ? 'الافتراضي' : 'Default',
                    color: AppColors.info,
                  ),
                const SizedBox(width: 6),
                // 🆕 شارة حالة الـSync
                _statusChip(
                  icon: SupabaseService().isReady
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_off,
                  label: SupabaseService().isReady
                      ? (isAr ? 'مَزامَنة سَحابيّة' : 'Cloud synced')
                      : (isAr ? 'محلّيّ فقط' : 'Local only'),
                  color: SupabaseService().isReady
                      ? AppColors.success
                      : AppColors.warning,
                ),
                const SizedBox(width: 4),
                // 🆕 زرّ تَحديث من السَحابة
                if (SupabaseService().isReady)
                  IconButton(
                    iconSize: 16,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
                    tooltip: isAr ? 'تَحديث من السَحابة' : 'Refresh from cloud',
                    icon: const Icon(Icons.refresh),
                    onPressed: _reloadFromCloud,
                  ),
                const SizedBox(width: 6),
                _statusChip(
                  icon: Icons.check_circle_outline,
                  label: isAr
                      ? 'مفعَّل: ${_selected.length}'
                      : 'Enabled: ${_selected.length}',
                  color: AppColors.success,
                ),
                const Spacer(),
                if (_hasCustom)
                  TextButton.icon(
                    onPressed: _resetToDefault,
                    icon: const Icon(Icons.restore, size: 14),
                    label: Text(
                      isAr ? 'استعادة الافتراضي' : 'Reset',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
          // ===== 🆕 إعدادات الترقية =====
          Container(
            margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.purple.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: AppColors.purple.withValues(alpha: 0.30)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.upgrade,
                        color: AppColors.purple, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        isAr
                            ? 'الدَور الذي يَترقّى إليه عند الرَبط بِنَقطة'
                            : 'Role to promote to upon point assignment',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  isAr
                      ? 'الموظّف L4 المُؤهّل (يَتبع للمُسمّى المختار) يُرَقّى تلقائيّاً عند رَبطه بِنَقطة.'
                      : 'Eligible L4 employees (reporting to the selected title) are auto-promoted when linked to a point.',
                  style:
                      const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  value: _promotionTargetId ?? defaultTargetId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText:
                        isAr ? 'المُسمّى الهَدَف' : 'Target job title',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.workspace_premium),
                    isDense: true,
                  ),
                  items: [
                    if (defaultTargetId != null)
                      DropdownMenuItem(
                        value: defaultTargetId,
                        child: Text(
                          isAr
                              ? '⭐ افتراضيّ (Site Supervisor)'
                              : '⭐ Default (Site Supervisor)',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800),
                        ),
                      ),
                    ...targetCandidates
                        .where((j) => j.id != defaultTargetId)
                        .map(
                          (j) => DropdownMenuItem(
                            value: j.id,
                            child: Text(
                              '${j.displayName(isAr)} (L${j.level})',
                            ),
                          ),
                        ),
                  ],
                  onChanged: (v) =>
                      setState(() => _promotionTargetId = v),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    isAr
                        ? 'وَراثة كلّ صلاحيّات المُسمّى الهَدَف'
                        : 'Inherit all target role permissions',
                    style: const TextStyle(fontSize: 12),
                  ),
                  subtitle: Text(
                    _inheritTargetPerms
                        ? (isAr
                            ? 'المُرَقّى يَحصل على كلّ صلاحيّات RBAC للمُسمّى الهَدَف.'
                            : 'Promoted user gains the target role\'s full RBAC perms.')
                        : (isAr
                            ? 'تَتغيّر فقط لَوحة الـDashboard والشاشات المسموحة.'
                            : 'Only dashboard/allowed-screens change.'),
                    style: const TextStyle(fontSize: 10),
                  ),
                  value: _inheritTargetPerms,
                  onChanged: (v) =>
                      setState(() => _inheritTargetPerms = v),
                ),
              ],
            ),
          ),
          // ===== List =====
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
              itemCount: allTitles.length,
              itemBuilder: (_, i) {
                final jt = allTitles[i];
                final isSelected = _selected.contains(jt.id);
                final isDefaultEligible = defaultIds.contains(jt.id);
                return _TitleRow(
                  jobTitle: jt,
                  isSelected: isSelected,
                  isDefaultEligible: isDefaultEligible,
                  isAr: isAr,
                  onToggle: () => setState(() {
                    if (isSelected) {
                      _selected.remove(jt.id);
                    } else {
                      _selected.add(jt.id);
                    }
                  }),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: dirty
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _saveAndApply,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(
                      isAr
                          ? '💾 حفظ (${_selected.length} مسمّى)'
                          : '💾 Save (${_selected.length} titles)',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w900),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _statusChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  static bool _setEquals(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    for (final v in a) {
      if (!b.contains(v)) return false;
    }
    return true;
  }
}

class _TitleRow extends StatelessWidget {
  final JobTitle jobTitle;
  final bool isSelected;
  final bool isDefaultEligible;
  final bool isAr;
  final VoidCallback onToggle;

  const _TitleRow({
    required this.jobTitle,
    required this.isSelected,
    required this.isDefaultEligible,
    required this.isAr,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final color = _hexToColor(jobTitle.color) ?? AppColors.brand;

    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.08)
              : Colors.grey.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color:
                isSelected ? color.withValues(alpha: 0.4) : Colors.grey.withValues(alpha: 0.2),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Checkbox(
              value: isSelected,
              activeColor: color,
              onChanged: (_) => onToggle(),
            ),
            Container(
              width: 4,
              height: 32,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          jobTitle.displayName(isAr),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (jobTitle.level > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'L${jobTitle.level}',
                            style: TextStyle(
                              color: color,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (isDefaultEligible)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.info.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.auto_awesome,
                                  size: 9, color: AppColors.info),
                              const SizedBox(width: 2),
                              Text(
                                isAr ? 'افتراضيّ' : 'Default',
                                style: const TextStyle(
                                  color: AppColors.info,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(width: 4),
                      Text(
                        jobTitle.dashboardType.label(isAr),
                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Color? _hexToColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    final s = hex.replaceAll('#', '');
    try {
      return Color(int.parse('FF$s', radix: 16));
    } catch (_) {
      return null;
    }
  }
}
