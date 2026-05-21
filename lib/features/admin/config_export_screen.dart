import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/config_export_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/rbac.dart';
import '../../shared/m7_app_bar.dart';

/// 📦 شاشة تصدير/استيراد الإعدادات (Session 8)
///
/// تتيح للمسؤول:
///   - معاينة كامل الإعدادات الحاليّة كـ JSON
///   - نسخ JSON إلى الحافظة (لحفظه في ملفّ خارجي)
///   - لصق JSON واستيراده
///   - معاينة قبل التطبيق (لكشف الفجوات)
class ConfigExportScreen extends StatefulWidget {
  const ConfigExportScreen({super.key});

  @override
  State<ConfigExportScreen> createState() => _ConfigExportScreenState();
}

class _ConfigExportScreenState extends State<ConfigExportScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  String _exportedJson = '';
  final _importController = TextEditingController();
  ImportPreview? _importPreview;

  // Import options
  bool _replaceDepartments = true;
  bool _replaceJobTitles = true;
  bool _replaceRoles = false;
  bool _replaceRolePermissions = true;
  bool _replaceFormTemplates = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _exportedJson = ConfigExportService.exportAsString(pretty: true);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _importController.dispose();
    super.dispose();
  }

  void _refreshExport() {
    setState(() {
      _exportedJson = ConfigExportService.exportAsString(pretty: true);
    });
  }

  Future<void> _copyToClipboard() async {
    await Clipboard.setData(ClipboardData(text: _exportedJson));
    if (!mounted) return;
    final s = AppStrings.of(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.success,
      content: Text(s.isAr ? '✅ نُسخ إلى الحافظة' : '✅ Copied to clipboard'),
    ));
  }

  void _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null) return;
    setState(() {
      _importController.text = data!.text!;
    });
    _previewImport();
  }

  void _previewImport() {
    final text = _importController.text.trim();
    if (text.isEmpty) {
      setState(() => _importPreview = null);
      return;
    }
    setState(() {
      _importPreview = ConfigExportService.previewImport(text);
    });
  }

  Future<void> _confirmAndApply() async {
    final s = AppStrings.of(context);
    if (_importPreview == null || !_importPreview!.success) return;
    // 🆕 الاستيراد عمليّة خطيرة جداً (يَستبدل كلّ البيانات).
    // يَتطلّب settingsConfigExportManage صراحة (وليس .view فقط).
    final auth = context.read<AuthProvider>();
    if (!(auth.isSuperAdmin ||
        auth.permissions.contains(P.settingsConfigExportManage))) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text(s.isAr
            ? '⛔ لا تَملك صلاحيّة "إدارة استيراد/تصدير JSON". '
                'هذه عمليّة تَستبدل كلّ البيانات — اتّصل بالمسؤول.'
            : '⛔ Missing permission: settings.config_export.manage. '
                'This replaces ALL data — contact admin.'),
      ));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          s.isAr ? '⚠️ تأكيد الاستيراد' : '⚠️ Confirm Import',
          style: const TextStyle(color: AppColors.danger),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.isAr
                  ? 'سيستبدل هذا البيانات الحاليّة. ستُلغى أيّ تغييرات لم تُحفظ.'
                  : 'This will replace current data. Any unsaved changes will be lost.',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                s.isAr
                    ? '🛡️ نصيحة: اعمل تصديراً للحاليّة قبل الاستيراد للنسخ الاحتياطي.'
                    : '🛡️ Tip: Export current first as backup before importing.',
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.isAr ? 'استيراد' : 'Import'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final result = ConfigExportService.applyImport(
      _importPreview!.rawData!,
      replaceDepartments: _replaceDepartments,
      replaceJobTitles: _replaceJobTitles,
      replaceRoles: _replaceRoles,
      replaceRolePermissions: _replaceRolePermissions,
      replaceFormTemplates: _replaceFormTemplates,
    );

    if (!mounted) return;
    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.success,
        content: Text(s.isAr
            ? '✅ تم استيراد ${result.imported} عنصر'
            : '✅ Imported ${result.imported} items'),
      ));
      _refreshExport();
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(s.isAr ? '⚠️ تحذيرات' : '⚠️ Warnings'),
          content: SingleChildScrollView(
            child: Text(result.errors.join('\n')),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(s.isAr ? 'موافق' : 'OK')),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;

    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? '📦 تَصدير/استيراد الإعدادات' : '📦 Config Export/Import',
      ),
      body: Column(
      children: [
        Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.brand.withOpacity(0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.brand.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              const Icon(Icons.cloud_download_outlined,
                  size: 18, color: AppColors.brand),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  isAr
                      ? 'تصدير/استيراد كامل الإعدادات: الأقسام، المسمّيات، الأدوار، الصلاحيّات.'
                      : 'Export/import full config: departments, job titles, roles, permissions.',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        TabBar(
          controller: _tabs,
          tabs: [
            Tab(
              icon: const Icon(Icons.cloud_upload_outlined, size: 18),
              text: isAr ? 'تصدير' : 'Export',
            ),
            Tab(
              icon: const Icon(Icons.cloud_download_outlined, size: 18),
              text: isAr ? 'استيراد' : 'Import',
            ),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _buildExportTab(isAr),
              _buildImportTab(isAr),
            ],
          ),
        ),
      ],
      ),
    );
  }

  // ============================================================
  // Export tab
  // ============================================================

  Widget _buildExportTab(bool isAr) {
    final lines = _exportedJson.split('\n').length;
    final bytes = _exportedJson.length;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _refreshExport,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text(isAr ? 'تحديث' : 'Refresh'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _copyToClipboard,
                  icon: const Icon(Icons.copy, size: 16),
                  label: Text(isAr ? 'نسخ JSON' : 'Copy JSON'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(Icons.description_outlined,
                    size: 14, color: Colors.grey[700]),
                const SizedBox(width: 6),
                Text(
                  isAr
                      ? '$lines سطر • ${(bytes / 1024).toStringAsFixed(1)} كيلوبايت'
                      : '$lines lines • ${(bytes / 1024).toStringAsFixed(1)} KB',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SelectableText(
                    _exportedJson,
                    style: const TextStyle(
                      color: Color(0xFFD4D4D4),
                      fontSize: 10,
                      fontFamily: 'monospace',
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // Import tab
  // ============================================================

  Widget _buildImportTab(bool isAr) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _pasteFromClipboard,
                  icon: const Icon(Icons.paste, size: 16),
                  label: Text(isAr ? 'لصق JSON' : 'Paste JSON'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _importController.clear();
                      _importPreview = null;
                    });
                  },
                  icon: const Icon(Icons.clear, size: 16),
                  label: Text(isAr ? 'مسح' : 'Clear'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _importController,
            maxLines: 6,
            onChanged: (_) => _previewImport(),
            decoration: InputDecoration(
              hintText: isAr ? 'الصق JSON هنا...' : 'Paste JSON here...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
          const SizedBox(height: 8),
          if (_importPreview != null) _buildPreview(_importPreview!, isAr),
        ],
      ),
    );
  }

  Widget _buildPreview(ImportPreview p, bool isAr) {
    if (!p.success) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.danger.withOpacity(0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.danger.withOpacity(0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: AppColors.danger, size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                p.error ?? 'Invalid JSON',
                style: const TextStyle(
                    color: AppColors.danger,
                    fontSize: 12,
                    fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      );
    }
    return Expanded(
      child: ListView(
        children: [
          // ===== Summary =====
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.success.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.check_circle_outline,
                        color: AppColors.success, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      isAr ? '✅ JSON صالح' : '✅ Valid JSON',
                      style: const TextStyle(
                          color: AppColors.success,
                          fontSize: 13,
                          fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (p.exportedAt != null)
                  Text(
                    isAr
                        ? 'تاريخ التصدير: ${p.exportedAt!.toLocal()}'
                        : 'Exported: ${p.exportedAt!.toLocal()}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _previewBadge(
                      label: isAr ? 'أقسام' : 'Departments',
                      count: p.departmentsCount,
                    ),
                    _previewBadge(
                      label: isAr ? 'مسمّيات' : 'Job Titles',
                      count: p.jobTitlesCount,
                    ),
                    _previewBadge(
                      label: isAr ? 'reports_to' : 'reports_to',
                      count: p.reportsToLinksCount,
                    ),
                    _previewBadge(
                      label: isAr ? 'أدوار' : 'Roles',
                      count: p.rolesCount,
                    ),
                    _previewBadge(
                      label: isAr ? 'صلاحيّات' : 'Role Perms',
                      count: p.rolePermissionsCount,
                    ),
                    _previewBadge(
                      label: isAr ? 'نماذج' : 'Forms',
                      count: p.formTemplatesCount,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ===== Options =====
          Text(
            isAr ? 'خيارات الاستيراد' : 'Import Options',
            style:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          _importToggle(
            label: isAr ? 'استبدال الأقسام' : 'Replace Departments',
            value: _replaceDepartments,
            onChanged: (v) =>
                setState(() => _replaceDepartments = v ?? false),
          ),
          _importToggle(
            label: isAr ? 'استبدال المسمّيات' : 'Replace Job Titles',
            value: _replaceJobTitles,
            onChanged: (v) => setState(() => _replaceJobTitles = v ?? false),
          ),
          _importToggle(
            label: isAr
                ? '⚠️ استبدال الأدوار (حسّاس)'
                : '⚠️ Replace Roles (sensitive)',
            value: _replaceRoles,
            onChanged: (v) => setState(() => _replaceRoles = v ?? false),
          ),
          _importToggle(
            label: isAr ? 'استبدال صلاحيّات الأدوار' : 'Replace Role Permissions',
            value: _replaceRolePermissions,
            onChanged: (v) =>
                setState(() => _replaceRolePermissions = v ?? false),
          ),
          _importToggle(
            label: isAr ? 'استبدال النماذج' : 'Replace Form Templates',
            value: _replaceFormTemplates,
            onChanged: (v) =>
                setState(() => _replaceFormTemplates = v ?? false),
          ),
          const SizedBox(height: 12),

          // ===== Apply button =====
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _confirmAndApply,
              icon: const Icon(Icons.cloud_download_outlined, size: 18),
              label: Text(
                isAr ? 'تطبيق الاستيراد' : 'Apply Import',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w900),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewBadge({required String label, required int count}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.success.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.success,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _importToggle({
    required String label,
    required bool value,
    required ValueChanged<bool?> onChanged,
  }) {
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      dense: true,
      title: Text(label, style: const TextStyle(fontSize: 12.5)),
      value: value,
      onChanged: onChanged,
    );
  }
}
