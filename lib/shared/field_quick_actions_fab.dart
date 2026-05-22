import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/l10n/app_strings.dart';
import '../core/providers/auth_provider.dart';
import '../core/theme/app_colors.dart';
import '../features/admin/employee_documents_expiry_report_screen.dart';
import '../features/admin/help_center_screen.dart';
import '../features/admin/smart_alerts_screen.dart';
import 'global_entity_search.dart';

/// 🎯 زِرّ إجراءات سَريعة لِلاستِخدام المَيدانيّ
///
/// زِرّ floating يَفتَح ورقة بِالإجراءات الأَكثَر استِخداماً.
/// مُلائِم لِلعَمَل المَيدانيّ مِن الجَوّال.
class FieldQuickActionsFab extends StatelessWidget {
  const FieldQuickActionsFab({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final isUr = s.isUr;
    return FloatingActionButton.extended(
      backgroundColor: AppColors.brand,
      foregroundColor: Colors.white,
      onPressed: () => _showActionsSheet(context, isAr, isUr),
      icon: const Icon(Icons.bolt),
      label: Text(
        isUr ? 'فوری اقدامات' : (isAr ? 'إجراءات سَريعة' : 'Quick Actions'),
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }

  void _showActionsSheet(BuildContext context, bool isAr, bool isUr) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _QuickActionsSheet(isAr: isAr, isUr: isUr),
    );
  }
}

class _QuickActionsSheet extends StatelessWidget {
  final bool isAr;
  final bool isUr;
  const _QuickActionsSheet({required this.isAr, required this.isUr});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final perms = auth.permissions;
    final isSuper = auth.isSuperAdmin;
    bool can(String p) => isSuper || perms.contains(p);

    // الإجراءات المُتاحة حَسَب الدَور
    final actions = <_QuickAction>[
      _QuickAction(
        icon: Icons.search,
        labelAr: 'بَحث عام',
        labelEn: 'Global Search',
        labelUr: 'عمومی تلاش',
        color: AppColors.brand,
        descAr: 'ابحَث عَن مُوظَّف / باص / نُقطة / ...',
        descEn: 'Search across all entities',
        descUr: 'ملازم / بس / پوائنٹ تلاش کریں ...',
        onTap: () {
          Navigator.pop(context);
          showSearch<void>(
              context: context, delegate: GlobalEntitySearch(isAr: isAr));
        },
      ),
      _QuickAction(
        icon: Icons.notifications_active,
        labelAr: 'مَركَز التَنبيهات',
        labelEn: 'Smart Alerts',
        labelUr: 'سمارٹ الرٹس',
        color: Colors.orange,
        descAr: 'كُلّ التَنبيهات الحَرِجة وَالعاجِلة',
        descEn: 'All urgent alerts',
        descUr: 'تمام نازک اور فوری اطلاعات',
        onTap: () {
          Navigator.pop(context);
          Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const SmartAlertsScreen()));
        },
      ),
      _QuickAction(
        icon: Icons.assignment_late,
        labelAr: 'وَثائِق مُنتَهية',
        labelEn: 'Expiring Docs',
        labelUr: 'ختم ہونے والی دستاویزات',
        color: Colors.red,
        descAr: 'الوَثائِق التي تَنتَهي قَريباً',
        descEn: 'Documents expiring soon',
        descUr: 'جلد ختم ہونے والی دستاویزات',
        onTap: () {
          Navigator.pop(context);
          Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const EmployeeDocumentsExpiryReportScreen()));
        },
      ),
      _QuickAction(
        icon: Icons.menu_book,
        labelAr: 'دَليل المُيَزّات',
        labelEn: 'Help Center',
        labelUr: 'مدد مرکز',
        color: AppColors.purple,
        descAr: 'اكتَشِف كُلّ ميزات النِظام في مَكان واحِد',
        descEn: 'Discover all features in one place',
        descUr: 'تمام خصوصیات ایک جگہ دیکھیں',
        onTap: () {
          Navigator.pop(context);
          Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const HelpCenterScreen()));
        },
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.bolt, color: AppColors.gold, size: 22),
                const SizedBox(width: 8),
                Text(
                  isUr ? 'فوری اقدامات' : (isAr ? 'إجراءات سَريعة' : 'Quick Actions'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 16),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.all(8),
              itemCount: actions.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final a = actions[i];
                return Material(
                  color: a.color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: a.onTap,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: a.color.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: a.color.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child:
                                Icon(a.icon, color: a.color, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isUr
                                      ? (a.labelUr ?? a.labelAr)
                                      : (isAr ? a.labelAr : a.labelEn),
                                  style: TextStyle(
                                      color: a.color,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isUr
                                      ? (a.descUr ?? a.descAr)
                                      : (isAr ? a.descAr : a.descEn),
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right,
                              color: a.color.withValues(alpha: 0.50), size: 20),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _QuickAction {
  final IconData icon;
  final String labelAr;
  final String labelEn;
  final String? labelUr;
  final String descAr;
  final String descEn;
  final String? descUr;
  final Color color;
  final VoidCallback onTap;
  const _QuickAction({
    required this.icon,
    required this.labelAr,
    required this.labelEn,
    this.labelUr,
    required this.descAr,
    required this.descEn,
    this.descUr,
    required this.color,
    required this.onTap,
  });
}
