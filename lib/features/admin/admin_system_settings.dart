import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/audit_logger.dart';
import '../../core/services/system_settings_service.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets.dart';

/// شاشة إعدادات النظام - لإدارة المتغيّرات القابلة للتعديل
/// مثل الإيميل المركزي للمصادقة، اسم الشركة، إلخ.
class AdminSystemSettings extends StatefulWidget {
  const AdminSystemSettings({super.key});

  @override
  State<AdminSystemSettings> createState() => _AdminSystemSettingsState();
}

class _AdminSystemSettingsState extends State<AdminSystemSettings> {
  bool _loading = true;
  List<Map<String, dynamic>> _settings = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await SystemSettings.instance.fetchWithMetadata();
    if (mounted) {
      setState(() {
        _settings = list;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_settings.isEmpty) {
      return Column(
        children: [
          Expanded(
            child: EmptyState(
              icon: Icons.settings,
              message: s.isAr
                  ? 'لا توجد إعدادات. شغّل system_settings_migration.sql'
                  : 'No settings found. Run system_settings_migration.sql',
            ),
          ),
        ],
      );
    }

    // تجميع بحسب الفئة
    final byCategory = <String, List<Map<String, dynamic>>>{};
    for (final s in _settings) {
      final cat = (s['category'] as String?) ?? 'general';
      byCategory.putIfAbsent(cat, () => []).add(s);
    }

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _InfoBanner(),
          const SizedBox(height: 12),
          ...byCategory.entries.map((entry) => _CategorySection(
                category: entry.key,
                settings: entry.value,
                onUpdated: _load,
              )),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: AppColors.info, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              s.isAr
                  ? 'هذه الإعدادات تؤثر على كل مستخدمي النظام. تغيير الإيميل المركزي يؤثر على المصادقة الجديدة.'
                  : 'These settings affect all users. Changing the central email affects new authentications.',
              style: const TextStyle(
                  color: AppColors.info,
                  fontSize: 11,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  final String category;
  final List<Map<String, dynamic>> settings;
  final VoidCallback onUpdated;
  const _CategorySection({
    required this.category,
    required this.settings,
    required this.onUpdated,
  });

  IconData _categoryIcon(String c) {
    switch (c) {
      case 'auth':
        return Icons.security;
      case 'general':
        return Icons.settings;
      case 'reports':
        return Icons.bar_chart;
      case 'rosters':
        return Icons.calendar_today;
      default:
        return Icons.tune;
    }
  }

  Color _categoryColor(String c) {
    switch (c) {
      case 'auth':
        return AppColors.danger;
      case 'general':
        return AppColors.brand;
      case 'reports':
        return AppColors.info;
      case 'rosters':
        return AppColors.warning;
      default:
        return AppColors.textTertiaryLight;
    }
  }

  String _categoryLabel(String c, AppStrings s) {
    switch (c) {
      case 'auth':
        return s.isAr ? 'المصادقة' : 'Authentication';
      case 'general':
        return s.isAr ? 'عام' : 'General';
      case 'reports':
        return s.isAr ? 'التقارير' : 'Reports';
      case 'rosters':
        return s.isAr ? 'الروسترات' : 'Rosters';
      default:
        return c;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final color = _categoryColor(category);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(11)),
              ),
              child: Row(
                children: [
                  Icon(_categoryIcon(category), color: color, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    _categoryLabel(category, s),
                    style: TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            ...settings.map((setting) =>
                _SettingRow(setting: setting, onUpdated: onUpdated)),
          ],
        ),
      ),
    );
  }
}

class _SettingRow extends StatefulWidget {
  final Map<String, dynamic> setting;
  final VoidCallback onUpdated;
  const _SettingRow({required this.setting, required this.onUpdated});

  @override
  State<_SettingRow> createState() => _SettingRowState();
}

class _SettingRowState extends State<_SettingRow> {
  late TextEditingController _ctrl;
  bool _editing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
        text: (widget.setting['value'] as String?) ?? '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = AppStrings.of(context);
    final key = widget.setting['key'] as String;
    final newValue = _ctrl.text.trim();
    final oldValue = (widget.setting['value'] as String?) ?? '';
    if (newValue == oldValue) {
      setState(() => _editing = false);
      return;
    }
    setState(() => _saving = true);
    final ok = await SystemSettings.instance.set(key, newValue);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (ok) _editing = false;
    });
    if (ok) {
      // Audit
      await AuditLogger.instance.log(
        entityType: 'system_setting',
        entityId: key,
        entityLabel: key,
        action: AuditAction.update,
        before: {'value': oldValue},
        after: {'value': newValue},
      );
      widget.onUpdated();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.savedSuccess)),
        );
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(s.isAr ? 'فشل الحفظ' : 'Save failed'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final key = widget.setting['key'] as String;
    final desc = (widget.setting['description_ar'] as String?) ??
        (widget.setting['description'] as String?) ??
        '';
    final valueType = widget.setting['value_type'] as String? ?? 'string';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  key,
                  style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w800,
                      fontSize: 12),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.brand.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(valueType,
                    style: const TextStyle(
                        fontSize: 9,
                        color: AppColors.brand,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(desc,
                style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).disabledColor)),
          ],
          const SizedBox(height: 8),
          if (_editing)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    autofocus: true,
                    keyboardType: valueType == 'int'
                        ? TextInputType.number
                        : TextInputType.text,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check, color: AppColors.success),
                  onPressed: _saving ? null : _save,
                  tooltip: s.save,
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.danger),
                  onPressed: _saving
                      ? null
                      : () {
                          setState(() {
                            _ctrl.text = (widget.setting['value'] as String?) ?? '';
                            _editing = false;
                          });
                        },
                  tooltip: s.cancel,
                ),
              ],
            )
          else
            InkWell(
              onTap: () => setState(() => _editing = true),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        ((widget.setting['value'] as String?) ?? '').isEmpty
                            ? '—'
                            : widget.setting['value'] as String,
                        style: const TextStyle(
                            fontSize: 13,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                    const Icon(Icons.edit_outlined,
                        size: 14, color: AppColors.brand),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
