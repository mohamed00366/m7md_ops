import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/l10n/app_strings.dart';
import '../core/providers/auth_provider.dart';
import '../core/services/dynamic_role_engine.dart';
import '../core/theme/app_colors.dart';
import '../models/lookups.dart';

/// 🎨 لافتة ترحيب ديناميكيّة تستخدم حقول JobTitle الغنيّة:
///   - اللون يأتي من JobTitle.color
///   - شارة المستوى (L1..L5)
///   - نوع لوحة التحكم (Manager/Supervisor/Operations/Finance/HR/Driver/Employee)
///   - شارة قوّة الموافقات إن > 0
///   - شارة "مشرف" إن JobTitle.isSupervisor = true
///
/// أين تُستخدم:
///   - أعلى الصفحة الرئيسية (SmartHome)
///   - أعلى أيّ شاشة لوحة تحكّم تابعة لدور
///
/// كيف تتغيّر:
///   - عند تعديل أيّ حقل في JobTitle عبر شاشة الإعدادات (Phase 2 UI)
///     تنعكس التغييرات تلقائياً على هذه اللافتة بدون أيّ كود إضافيّ.
class DynamicRoleBanner extends StatelessWidget {
  /// إن كان true → يظهر بعرض كامل مع padding أفقي.
  /// إن كان false → يلتف فقط حول المحتوى.
  final bool fullWidth;

  /// نص ترحيبيّ مخصّص (اختياريّ)
  final String? customGreeting;

  const DynamicRoleBanner({
    super.key,
    this.fullWidth = true,
    this.customGreeting,
  });

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final s = AppStrings.of(context);
    final config = DynamicRoleEngine.resolve(auth);

    // إذا لم يكن للمستخدم JobTitle ولا Super Admin → لا تعرض شيء
    if (config.jobTitle == null && !config.isSuperAdmin) {
      return const SizedBox.shrink();
    }

    final accent = config.color ?? AppColors.brand;
    final isAr = s.isAr;
    final greeting = customGreeting ??
        (isAr ? 'أهلاً، ${auth.account?.fullName ?? ''}' : 'Welcome, ${auth.account?.fullName ?? ''}');
    final roleLabel = config.isSuperAdmin
        ? (isAr ? 'مدير عام (Super Admin)' : 'Super Admin')
        : config.jobTitle?.displayName(isAr) ?? '';
    final dashboardLabel = config.dashboardType.label(isAr);

    final card = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.95),
            accent.withValues(alpha: 0.78),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // أيقونة dashboard type
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _iconForDashboard(config.dashboardType),
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      greeting,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      roleLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (config.levelLabel != null)
                _BannerBadge(
                  text: config.levelLabel!,
                  bg: Colors.white,
                  fg: accent,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _BannerBadge(
                icon: Icons.dashboard_outlined,
                text: dashboardLabel,
                bg: Colors.white.withValues(alpha: 0.2),
                fg: Colors.white,
              ),
              if (config.canApprove)
                _BannerBadge(
                  icon: Icons.verified_outlined,
                  text: isAr
                      ? 'موافقات: ${config.approvalPower}/5'
                      : 'Approval: ${config.approvalPower}/5',
                  bg: Colors.white.withValues(alpha: 0.2),
                  fg: Colors.white,
                ),
              if (config.jobTitle?.isSupervisor == true)
                _BannerBadge(
                  icon: Icons.supervisor_account_outlined,
                  text: isAr ? 'مشرف' : 'Supervisor',
                  bg: Colors.white.withValues(alpha: 0.2),
                  fg: Colors.white,
                ),
              if (config.kpiTargets.isNotEmpty)
                _BannerBadge(
                  icon: Icons.flag_outlined,
                  text: isAr
                      ? 'KPIs: ${config.kpiTargets.length}'
                      : 'KPIs: ${config.kpiTargets.length}',
                  bg: Colors.white.withValues(alpha: 0.2),
                  fg: Colors.white,
                ),
            ],
          ),
        ],
      ),
    );

    if (!fullWidth) return card;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: card,
    );
  }

  static IconData _iconForDashboard(DashboardType t) {
    switch (t) {
      case DashboardType.manager:
        return Icons.business_center_outlined;
      case DashboardType.supervisor:
        return Icons.supervisor_account_outlined;
      case DashboardType.operations:
        return Icons.engineering_outlined;
      case DashboardType.finance:
        return Icons.account_balance_outlined;
      case DashboardType.hr:
        return Icons.groups_outlined;
      case DashboardType.driver:
        return Icons.directions_bus_outlined;
      case DashboardType.employee:
        return Icons.badge_outlined;
    }
  }
}

class _BannerBadge extends StatelessWidget {
  final IconData? icon;
  final String text;
  final Color bg;
  final Color fg;
  const _BannerBadge({
    this.icon,
    required this.text,
    required this.bg,
    required this.fg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              color: fg,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
