import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../repositories/mock_repository.dart';

/// نظرة عامة على Admin Console
class AdminOverview extends StatelessWidget {
  const AdminOverview({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final activeUsers = repo.accounts.where((a) => a.isActive).length;
    final superAdmins = repo.accounts.where((a) => a.isSuperAdmin).length;
    final totalRoles = repo.roleDefs.length;
    final totalPerms = repo.permissionDefs.length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ===== Hero =====
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.brand, AppColors.brandAccent],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.shield_moon_outlined,
                        color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.isAr ? 'لوحة الإدارة' : 'Admin Console',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700),
                        ),
                        Text(
                          s.isAr
                              ? 'إدارة المستخدمين والصلاحيات'
                              : 'Manage users and permissions',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // ===== Stats grid =====
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.4,
          children: [
            _StatCard(
              icon: Icons.people,
              color: AppColors.brand,
              value: '${repo.accounts.length}',
              label: s.isAr ? 'إجمالي الحسابات' : 'Total Accounts',
              sub: '$activeUsers ${s.isAr ? "نشط" : "active"}',
              isDark: isDark,
            ),
            _StatCard(
              icon: Icons.workspace_premium,
              color: AppColors.success,
              value: '$superAdmins',
              label: s.isAr ? 'مديرون عامون' : 'Super Admins',
              isDark: isDark,
            ),
            _StatCard(
              icon: Icons.shield_outlined,
              color: AppColors.warning,
              value: '$totalRoles',
              label: s.isAr ? 'الأدوار' : 'Roles',
              isDark: isDark,
            ),
            _StatCard(
              icon: Icons.key_outlined,
              color: AppColors.purple,
              value: '$totalPerms',
              label: s.isAr ? 'الصلاحيات' : 'Permissions',
              isDark: isDark,
            ),
          ],
        ),
        const SizedBox(height: 16),
        // ===== Recent activity =====
        Text(
          s.isAr ? 'آخر الأنشطة' : 'Recent Activity',
          style: TextStyle(
              color: isDark ? AppColors.textDark : AppColors.textLight,
              fontSize: 14,
              fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (repo.auditLog.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: isDark
                      ? AppColors.borderDark
                      : AppColors.borderLight,
                  width: 0.5),
            ),
            child: Center(
              child: Text(s.noData,
                  style: TextStyle(
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight)),
            ),
          )
        else
          ...repo.auditLog.reversed.take(8).map((e) {
            final user = repo.accounts.firstWhere(
              (a) => a.id == e.userId,
              orElse: () => repo.accounts.first,
            );
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.surfaceDark
                    : AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: isDark
                        ? AppColors.borderDark
                        : AppColors.borderLight,
                    width: 0.5),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.brand.withValues(alpha: 0.2),
                    child: Text(
                      user.initials,
                      style: const TextStyle(
                          color: AppColors.brand,
                          fontSize: 11,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_actionLabel(e.action, s.isAr),
                            style: TextStyle(
                                color: isDark
                                    ? AppColors.textDark
                                    : AppColors.textLight,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                        Text(
                            '${user.fullName} • ${_relTime(e.at, s.isAr)}',
                            style: TextStyle(
                                color: isDark
                                    ? AppColors.textSecondaryDark
                                    : AppColors.textSecondaryLight,
                                fontSize: 10)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  String _actionLabel(String action, bool isAr) {
    switch (action) {
      case 'login':
        return isAr ? 'تسجيل دخول' : 'Login';
      case 'create_user':
        return isAr ? 'إنشاء مستخدم' : 'Created user';
      case 'update_user':
        return isAr ? 'تحديث مستخدم' : 'Updated user';
      case 'reset_password':
        return isAr ? 'إعادة تعيين كلمة مرور' : 'Reset password';
      case 'set_roles':
        return isAr ? 'تعيين أدوار' : 'Assigned roles';
      case 'set_role_permissions':
        return isAr ? 'تحديث صلاحيات دور' : 'Updated role permissions';
      default:
        return action;
    }
  }

  String _relTime(DateTime at, bool isAr) {
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return isAr ? 'الآن' : 'just now';
    if (diff.inMinutes < 60) {
      return isAr ? 'منذ ${diff.inMinutes} د' : '${diff.inMinutes}m ago';
    }
    if (diff.inHours < 24) {
      return isAr ? 'منذ ${diff.inHours} س' : '${diff.inHours}h ago';
    }
    return isAr ? 'منذ ${diff.inDays} يوم' : '${diff.inDays}d ago';
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final String? sub;
  final bool isDark;
  const _StatCard({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    this.sub,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const Spacer(),
          Text(value,
              style: TextStyle(
                  color: isDark ? AppColors.textDark : AppColors.textLight,
                  fontSize: 22,
                  fontWeight: FontWeight.w800)),
          Text(label,
              style: TextStyle(
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                  fontSize: 11)),
          if (sub != null)
            Text(sub!,
                style: TextStyle(
                    color: color, fontSize: 10, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
