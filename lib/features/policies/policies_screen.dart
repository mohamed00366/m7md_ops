import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/m7_log.dart';
import '../../core/theme/app_colors.dart';
import '../../models/policies.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';
import 'policy_editor_sheet.dart';

/// شاشة السياسات المشتركة - تُستخدم في كل تطبيقات الأدوار
class PoliciesScreen extends StatefulWidget {
  const PoliciesScreen({super.key});

  @override
  State<PoliciesScreen> createState() => _PoliciesScreenState();
}

class _PoliciesScreenState extends State<PoliciesScreen> {
  final _searchCtrl = TextEditingController();
  PolicyCategory? _selectedCategory; // null = الكل
  String _query = '';
  final _expandedIds = <String>{};

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// 🆕 يفتح Sheet الإضافة/التعديل. إذا [policy] = null → إنشاء جديد.
  Future<void> _openEditor(Policy? policy) async {
    final result = await showModalBottomSheet<Policy>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => PolicyEditorSheet(existing: policy),
    );
    if (result == null) return;
    final repo = MockRepository();
    if (policy == null) {
      repo.addPolicy(result);
      M7Log.info('Policies', 'created policy ${result.id}');
    } else {
      repo.updatePolicy(result);
      M7Log.info('Policies', 'updated policy ${result.id}');
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.success,
        content: Text(
          AppStrings.of(context).isAr
              ? (policy == null ? 'تمّت إضافة السياسة' : 'تمّ تحديث السياسة')
              : (policy == null ? 'Policy added' : 'Policy updated'),
        ),
      ));
    }
  }

  /// 🆕 تأكيد الحذف ثمّ تنفيذه
  Future<void> _confirmDelete(Policy policy) async {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: AppColors.danger),
            const SizedBox(width: 8),
            Text(isAr ? 'حذف السياسة؟' : 'Delete policy?'),
          ],
        ),
        content: Text(
          isAr
              ? 'سيُحذف "${policy.titleAr}" نهائياً ولن يمكن استرجاعه.'
              : '"${policy.titleEn}" will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(isAr ? 'إلغاء' : 'Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(isAr ? 'حذف' : 'Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      MockRepository().deletePolicy(policy.id);
      M7Log.info('Policies', 'deleted policy ${policy.id}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.warning,
          content: Text(isAr ? 'حُذفت السياسة' : 'Policy deleted'),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 🆕 صلاحيّة التعديل
    final canEdit = context.watch<AuthProvider>().hasPermission(P.policiesEdit);

    final filtered = repo.policies.where((p) {
      if (_selectedCategory != null && p.category != _selectedCategory) {
        return false;
      }
      return p.matches(_query);
    }).toList()
      ..sort((a, b) => a.category.index.compareTo(b.category.index));

    return Scaffold(
      backgroundColor: Colors.transparent,
      // 🆕 زرّ إضافة سياسة (يظهر فقط لمن عنده صلاحيّة التعديل)
      floatingActionButton: !canEdit
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openEditor(null),
              icon: const Icon(Icons.add),
              label: Text(s.isAr ? 'سياسة جديدة' : 'New policy'),
              backgroundColor: AppColors.brand,
              foregroundColor: Colors.white,
            ),
      body: SafeArea(
        child: Column(
          children: [
            // ============ شريط البحث ============
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surface2Dark : AppColors.surface2Light,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: isDark
                          ? AppColors.borderDark
                          : AppColors.borderLight,
                      width: 0.5),
                ),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _query = v),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: s.policiesHint,
                    hintStyle: TextStyle(
                      color: isDark
                          ? AppColors.textTertiaryDark
                          : AppColors.textTertiaryLight,
                      fontSize: 13,
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight,
                      size: 20,
                    ),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _query = '');
                            },
                          ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                  ),
                ),
              ),
            ),
            // ============ فلاتر التصنيف ============
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _CategoryChip(
                    label: s.all,
                    color: AppColors.brand,
                    icon: Icons.apps,
                    selected: _selectedCategory == null,
                    onTap: () => setState(() => _selectedCategory = null),
                  ),
                  ...PolicyCategory.values
                      .where((c) => c != PolicyCategory.other)
                      .map((c) => _CategoryChip(
                            label: s.isAr ? c.labelAr() : c.labelEn(),
                            color: c.color(),
                            icon: c.icon(),
                            selected: _selectedCategory == c,
                            onTap: () =>
                                setState(() => _selectedCategory = c),
                          )),
                ],
              ),
            ),
            // ============ قائمة السياسات ============
            Expanded(
              child: filtered.isEmpty
                  ? _EmptyState(isAr: s.isAr, isDark: isDark)
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final p = filtered[i];
                        return _PolicyCard(
                          policy: p,
                          isAr: s.isAr,
                          isDark: isDark,
                          expanded: _expandedIds.contains(p.id),
                          canEdit: canEdit,
                          onEdit: () => _openEditor(p),
                          onDelete: () => _confirmDelete(p),
                          onToggle: () {
                            setState(() {
                              if (_expandedIds.contains(p.id)) {
                                _expandedIds.remove(p.id);
                              } else {
                                _expandedIds.add(p.id);
                              }
                            });
                          },
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
// شريحة تصنيف
// ============================================================
class _CategoryChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _CategoryChip({
    required this.label,
    required this.color,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? color.withOpacity(0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? color
                  : (isDark
                      ? AppColors.borderDark
                      : AppColors.borderLight),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 14,
                  color: selected
                      ? color
                      : (isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight)),
              const SizedBox(width: 5),
              Text(label,
                  style: TextStyle(
                      color: selected
                          ? color
                          : (isDark
                              ? AppColors.textDark
                              : AppColors.textLight),
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// بطاقة سياسة قابلة للفتح
// ============================================================
class _PolicyCard extends StatelessWidget {
  final Policy policy;
  final bool isAr;
  final bool isDark;
  final bool expanded;
  final bool canEdit;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _PolicyCard({
    required this.policy,
    required this.isAr,
    required this.isDark,
    required this.expanded,
    required this.canEdit,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final color = policy.category.color();
    final cardColor =
        isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final borderColor =
        isDark ? AppColors.borderDark : AppColors.borderLight;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ===== رأس البطاقة =====
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child:
                        Icon(policy.category.icon(), color: color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isAr ? policy.titleAr : policy.titleEn,
                          style: TextStyle(
                              color: isDark
                                  ? AppColors.textDark
                                  : AppColors.textLight,
                              fontSize: 14,
                              fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isAr ? policy.summaryAr : policy.summaryEn,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondaryLight,
                              fontSize: 11),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.list_alt,
                                size: 11,
                                color: isDark
                                    ? AppColors.textTertiaryDark
                                    : AppColors.textTertiaryLight),
                            const SizedBox(width: 3),
                            Text(
                              isAr
                                  ? '${policy.totalSteps} نقطة'
                                  : '${policy.totalSteps} items',
                              style: TextStyle(
                                  color: isDark
                                      ? AppColors.textTertiaryDark
                                      : AppColors.textTertiaryLight,
                                  fontSize: 10),
                            ),
                            const SizedBox(width: 10),
                            Icon(Icons.update,
                                size: 11,
                                color: isDark
                                    ? AppColors.textTertiaryDark
                                    : AppColors.textTertiaryLight),
                            const SizedBox(width: 3),
                            Text(
                              _relativeDate(policy.updatedAt, isAr),
                              style: TextStyle(
                                  color: isDark
                                      ? AppColors.textTertiaryDark
                                      : AppColors.textTertiaryLight,
                                  fontSize: 10),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // 🆕 أزرار التعديل/الحذف (تظهر لمن عنده صلاحيّة)
                  if (canEdit) ...[
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      tooltip: isAr ? 'تعديل' : 'Edit',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                          minWidth: 32, minHeight: 32),
                      onPressed: onEdit,
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          size: 18, color: AppColors.danger),
                      tooltip: isAr ? 'حذف' : 'Delete',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                          minWidth: 32, minHeight: 32),
                      onPressed: onDelete,
                    ),
                  ],
                  AnimatedRotation(
                    duration: const Duration(milliseconds: 200),
                    turns: expanded ? 0.5 : 0,
                    child: Icon(Icons.keyboard_arrow_down,
                        color: color, size: 22),
                  ),
                ],
              ),
            ),
          ),
          // ===== المحتوى المفتوح =====
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: !expanded
                ? const SizedBox.shrink()
                : Container(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 1,
                          color: borderColor,
                          margin: const EdgeInsets.only(bottom: 12),
                        ),
                        ...policy.sections.map(
                          (sec) => _PolicySectionView(
                            section: sec,
                            isAr: isAr,
                            isDark: isDark,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  String _relativeDate(DateTime d, bool isAr) {
    final diff = DateTime.now().difference(d).inDays;
    if (diff == 0) return isAr ? 'اليوم' : 'today';
    if (diff < 7) return isAr ? 'منذ $diff يوم' : '${diff}d ago';
    if (diff < 30) {
      final w = (diff / 7).floor();
      return isAr ? 'منذ $w أسبوع' : '${w}w ago';
    }
    if (diff < 365) {
      final m = (diff / 30).floor();
      return isAr ? 'منذ $m شهر' : '${m}mo ago';
    }
    final y = (diff / 365).floor();
    return isAr ? 'منذ $y سنة' : '${y}y ago';
  }
}

// ============================================================
// عرض قسم داخل سياسة
// ============================================================
class _PolicySectionView extends StatelessWidget {
  final PolicySection section;
  final bool isAr;
  final bool isDark;
  final Color color;
  const _PolicySectionView({
    required this.section,
    required this.isAr,
    required this.isDark,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final body = isAr ? section.bodyAr : section.bodyEn;
    final steps = isAr ? section.stepsAr : section.stepsEn;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(section.icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  isAr ? section.titleAr : section.titleEn,
                  style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          if (body != null) ...[
            const SizedBox(height: 8),
            Text(
              body,
              style: TextStyle(
                  color: isDark ? AppColors.textDark : AppColors.textLight,
                  fontSize: 12,
                  height: 1.55),
            ),
          ],
          if (steps.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...steps.asMap().entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 18,
                          height: 18,
                          margin: const EdgeInsets.only(top: 1),
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${e.key + 1}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            e.value,
                            style: TextStyle(
                                color: isDark
                                    ? AppColors.textDark
                                    : AppColors.textLight,
                                fontSize: 12,
                                height: 1.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }
}

// ============================================================
// حالة فارغة
// ============================================================
class _EmptyState extends StatelessWidget {
  final bool isAr;
  final bool isDark;
  const _EmptyState({required this.isAr, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off,
              size: 56,
              color: isDark
                  ? AppColors.textTertiaryDark
                  : AppColors.textTertiaryLight),
          const SizedBox(height: 12),
          Text(
            isAr
                ? 'لا توجد سياسات تطابق البحث'
                : 'No policies match your search',
            style: TextStyle(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
                fontSize: 13),
          ),
        ],
      ),
    );
  }
}
