import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/l10n/app_strings.dart';
import '../core/providers/auth_provider.dart';
import '../core/theme/app_colors.dart';
import 'm7_app_bar.dart';
import 'm7_dirty_tracker.dart';

/// 🧩 Scaffold مُوَحَّد لِشاشات تَعديل أَقسام مَلَفّ كِيان (Hub & Spoke)
///
/// **المُمَيِّزات:**
/// - AppBar مُوَحَّد (M7AppBar) مَع زِرّ حِفظ في الأَعلى
/// - PopScope تَلقائيّ مَع تَأكيد قَبل الخُروج لَو هُناك تَعديلات
/// - فَحص الصَلاحيّة + شارة «وَضع القِراءة» تِلقائيّاً
/// - زِرّ حِفظ كَبير في الأَسفَل
/// - بانِر القِسم في الأَعلى بِلَون مُمَيَّز
///
/// **الاستِخدام:**
/// ```dart
/// M7SectionScaffold(
///   titleAr: 'البَيانات الشَخصيّة',
///   titleEn: 'Personal Info',
///   icon: Icons.person,
///   color: AppColors.brand,
///   editPermission: P.employeesEdit,
///   saving: _saving,
///   onSave: _save,
///   isDirty: () => isDirty,
///   children: [ TextField(...), ... ],
/// )
/// ```
class M7SectionScaffold extends StatelessWidget {
  final String titleAr;
  final String titleEn;
  final IconData icon;
  final Color color;
  final List<Widget> children;
  final VoidCallback onSave;
  final bool saving;
  /// عِند نَدائها تُعيد `true` لَو هُناك تَعديلات لَم تُحفَظ بَعد
  final bool Function()? isDirty;
  /// مِفتاح الصَلاحيّة المَطلوبة لِلتَعديل — لَو null يُسمَح بِالتَعديل دائماً
  final String? editPermission;

  const M7SectionScaffold({
    super.key,
    required this.titleAr,
    required this.titleEn,
    required this.icon,
    required this.color,
    required this.children,
    required this.onSave,
    required this.saving,
    this.isDirty,
    this.editPermission,
  });

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    // فَحص الصَلاحيّة
    final auth = context.read<AuthProvider>();
    final canEdit = editPermission == null ||
        auth.isSuperAdmin ||
        auth.permissions.contains(editPermission);

    return PopScope(
      canPop: !saving && !(isDirty?.call() ?? false),
      onPopInvoked: (didPop) async {
        if (didPop) return;
        if (saving) return;
        final hasChanges = isDirty?.call() ?? false;
        if (!hasChanges) {
          Navigator.of(context).pop();
          return;
        }
        final ok = await showM7DiscardDialog(context, isAr: isAr);
        if (ok == true && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: M7AppBar(
          title: isAr ? titleAr : titleEn,
          actions: canEdit
              ? [
                  M7AppBarAction(
                    icon: Icons.save,
                    tooltip: isAr ? 'حِفظ' : 'Save',
                    onPressed: saving ? null : onSave,
                  ),
                ]
              : null,
        ),
        body: AbsorbPointer(
          absorbing: saving,
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              // بانِر العُنوان
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    Icon(icon, color: color, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      isAr ? titleAr : titleEn,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              if (!canEdit) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppColors.warning.withValues(alpha: 0.40)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_outline,
                          color: AppColors.warning, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isAr
                              ? 'وَضع القِراءة فَقَط — لا تَملِك صَلاحيّة التَعديل.'
                              : 'Read-only mode — no edit permission.',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              ...children,
              const SizedBox(height: 24),
              if (canEdit)
                SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: saving ? null : onSave,
                    icon: saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save),
                    label: Text(
                      isAr
                          ? (saving ? 'يَجري الحِفظ...' : 'حِفظ التَعديلات')
                          : (saving ? 'Saving...' : 'Save changes'),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 🧱 بِطاقة قِسم في شاشات التَقارير (Account 360 / Master Report …)
class M7ReportSection extends StatelessWidget {
  final IconData icon;
  final String titleAr;
  final String titleEn;
  final Color color;
  final List<Widget> children;
  const M7ReportSection({
    super.key,
    required this.icon,
    required this.titleAr,
    required this.titleEn,
    required this.color,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 8),
                Text(isAr ? titleAr : titleEn,
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                        fontSize: 13)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

/// صَفّ مِفتاح/قيمة في شاشات التَقارير
class M7Row extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  final Color? color;
  const M7Row({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, color: color ?? Colors.grey, size: 16),
            const SizedBox(width: 6),
          ],
          SizedBox(
            width: 130,
            child: Text(label,
                style:
                    const TextStyle(fontSize: 11, color: Colors.grey)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color)),
          ),
        ],
      ),
    );
  }
}
