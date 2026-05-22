import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/roster_employee_filter_settings.dart';
import '../../core/theme/app_colors.dart';
import '../../repositories/mock_repository.dart';

/// 📋 شاشة إعدادات تصفية الموظّفين عند إضافتهم لروستر
///
/// تتيح للمسؤول تحديد:
///   1. أيّ مسمّيات وظيفيّة يُسمح إضافتها كموظّفين في الروسترات.
///      عدم تحديد أيّ مسمّى = الجميع مسموح (السلوك الافتراضي).
///   2. هل نُظهر فقط الموظّفين النشطين (الافتراضي = نعم).
class RosterEmployeeFilterSettingsScreen extends StatefulWidget {
  const RosterEmployeeFilterSettingsScreen({super.key});

  @override
  State<RosterEmployeeFilterSettingsScreen> createState() =>
      _RosterEmployeeFilterSettingsScreenState();
}

class _RosterEmployeeFilterSettingsScreenState
    extends State<RosterEmployeeFilterSettingsScreen> {
  final _settings = RosterEmployeeFilterSettings.instance;
  Set<String> _selected = {};
  bool _onlyActive = true;
  bool _loaded = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _settings.load();
    if (!mounted) return;
    setState(() {
      _selected = Set.from(_settings.allowedJobTitleIds);
      _onlyActive = _settings.onlyActive;
      _loaded = true;
    });
  }

  /// 🆕 الحالة: هل آخر حفظ وصل لـ Supabase أم محلّي فقط؟
  /// null = لم يحفظ بعد، true = متزامن مع السحابة، false = محلّي فقط.
  bool? _lastSyncCloud;

  Future<void> _save() async {
    await _settings.setAllowed(_selected);
    await _settings.setOnlyActive(_onlyActive);
    if (!mounted) return;
    final isAr = AppStrings.of(context).isAr;
    final cloudOk = _settings.lastSyncedToCloud;
    setState(() => _lastSyncCloud = cloudOk);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: cloudOk ? AppColors.success : AppColors.warning,
      duration: const Duration(seconds: 4),
      content: Text(cloudOk
          ? (isAr
              ? '✅ حُفظ في Supabase + الذاكرة المحليّة'
              : '✅ Saved to Supabase + local cache')
          : (isAr
              ? '⚠️ حُفظ محلّياً فقط — Supabase غير متّصل أو الجدول غير موجود. شغّل ملف SQL: app_settings_table.sql'
              : '⚠️ Saved locally only — Supabase unreachable. Run SQL: app_settings_table.sql')),
    ));
  }

  Future<void> _resetToDefault() async {
    final isAr = AppStrings.of(context).isAr;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isAr ? 'استعادة الافتراضي' : 'Reset to default'),
        content: Text(isAr
            ? 'سيُحذف الإعداد المخصّص — تظهر كلّ المسمّيات.'
            : 'Custom config will be removed — all titles will show.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(isAr ? 'إلغاء' : 'Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white),
              child: Text(isAr ? 'استعد' : 'Reset')),
        ],
      ),
    );
    if (ok != true) return;
    await _settings.resetToDefault();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final repo = MockRepository();
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final jobTitles = repo.jobTitles.toList();
    var visible = jobTitles;
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      visible = jobTitles
          .where((j) =>
              j.nameAr.toLowerCase().contains(q) ||
              j.nameEn.toLowerCase().contains(q))
          .toList();
    }

    final empCounts = <String, int>{};
    for (final e in repo.employees) {
      final id = e.jobTitleId;
      if (id == null) continue;
      empCounts[id] = (empCounts[id] ?? 0) + 1;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(isAr
            ? 'تصفية الموظّفين في الروستر'
            : 'Roster Employee Filter'),
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // 🆕 شريط حالة المزامنة
          if (_lastSyncCloud != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              color: _lastSyncCloud!
                  ? AppColors.success.withValues(alpha: 0.15)
                  : AppColors.warning.withValues(alpha: 0.15),
              child: Row(
                children: [
                  Icon(
                    _lastSyncCloud!
                        ? Icons.cloud_done
                        : Icons.cloud_off,
                    size: 16,
                    color: _lastSyncCloud!
                        ? AppColors.success
                        : AppColors.warning,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _lastSyncCloud!
                          ? (isAr
                              ? 'متزامن مع Supabase ☁️ — الإعدادات محفوظة على السحابة'
                              : 'Synced with Supabase ☁️ — settings saved to cloud')
                          : (isAr
                              ? 'محلّي فقط — لتفعيل المزامنة شغّل ملف SQL: app_settings_table.sql في Supabase Dashboard'
                              : 'Local only — run SQL file app_settings_table.sql in Supabase Dashboard to enable cloud sync'),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: _lastSyncCloud!
                            ? AppColors.success
                            : AppColors.warning,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // ===== شريط معلومات + إعداد "النشطين فقط" =====
          Container(
            padding: const EdgeInsets.all(12),
            color: AppColors.brand.withValues(alpha: 0.06),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.info_outline,
                        color: AppColors.brand, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        isAr
                            ? 'حدّد أيّ مسمّيات وظيفيّة تظهر عند إضافة موظّف للروستر. لو لم تختر شيئاً → كلّ المسمّيات تظهر.'
                            : 'Pick which job titles can be added to a roster. If none selected → all titles show.',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _onlyActive,
                  onChanged: (v) => setState(() => _onlyActive = v),
                  title: Text(
                    isAr
                        ? 'إظهار الموظّفين النشطين فقط'
                        : 'Show only active employees',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    isAr
                        ? 'يستثني الموظّفين المعطَّلين/المنفصلين/الموقَّفين'
                        : 'Excludes inactive / terminated / suspended',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
          // ===== بحث =====
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: isAr
                    ? '🔍 بحث في المسمّيات...'
                    : '🔍 Search job titles...',
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          // ===== أزرار سريعة =====
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () => setState(() {
                    _selected = jobTitles.map((j) => j.id).toSet();
                  }),
                  icon: const Icon(Icons.select_all, size: 16),
                  label:
                      Text(isAr ? 'حدّد الكلّ' : 'Select all',
                          style: const TextStyle(fontSize: 12)),
                ),
                TextButton.icon(
                  onPressed: () => setState(() => _selected = {}),
                  icon: const Icon(Icons.deselect, size: 16),
                  label: Text(isAr ? 'إلغاء الكلّ' : 'Clear',
                      style: const TextStyle(fontSize: 12)),
                ),
                const Spacer(),
                Text(
                  isAr
                      ? '${_selected.length} / ${jobTitles.length} محدّد'
                      : '${_selected.length} / ${jobTitles.length} selected',
                  style: const TextStyle(
                      color: AppColors.brand,
                      fontSize: 11,
                      fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // ===== قائمة المسمّيات =====
          Expanded(
            child: ListView.builder(
              itemCount: visible.length,
              itemBuilder: (_, i) {
                final j = visible[i];
                final isSelected = _selected.contains(j.id);
                final count = empCounts[j.id] ?? 0;
                return CheckboxListTile(
                  dense: true,
                  value: isSelected,
                  onChanged: (_) => setState(() {
                    if (isSelected) {
                      _selected.remove(j.id);
                    } else {
                      _selected.add(j.id);
                    }
                  }),
                  title: Text(
                    isAr ? j.nameAr : j.nameEn,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    isAr ? '$count موظّف' : '$count employees',
                    style: const TextStyle(fontSize: 11),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _resetToDefault,
                  icon: const Icon(Icons.restart_alt, size: 16),
                  label: Text(isAr ? 'استعد الافتراضي' : 'Reset',
                      style: const TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _save,
                  icon: const Icon(Icons.save_outlined, size: 16),
                  label: Text(
                      isAr
                          ? 'حفظ الإعدادات'
                          : 'Save settings',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
