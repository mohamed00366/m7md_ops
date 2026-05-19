import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/locale_provider.dart';
import '../../core/providers/theme_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../models/rbac.dart';
import '../../shared/branded_background.dart';

/// طابق دور RBAC مع UserRole القديم
bool _matchesUserRole(String roleKey, UserRole legacy) {
  switch (legacy) {
    case UserRole.manager:
      return roleKey == SystemRoles.manager ||
          roleKey == SystemRoles.admin ||
          roleKey == SystemRoles.superAdmin;
    case UserRole.operation:
      return roleKey == SystemRoles.operation;
    case UserRole.supervisor:
      return roleKey == SystemRoles.supervisor;
    case UserRole.campBoss:
      return roleKey == SystemRoles.campBoss;
    case UserRole.driver:
      return roleKey == SystemRoles.driver;
    case UserRole.employee:
      return roleKey == SystemRoles.employee;
  }
}

/// شاشة اختيار التطبيق - تعرض الستة أدوار الرئيسية
class AppSelectionScreen extends StatelessWidget {
  const AppSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final auth = context.watch<AuthProvider>();

    // كل الأدوار الممكنة
    final allRoles = [
      _RoleApp(UserRole.manager, Icons.admin_panel_settings, AppColors.roleManager),
      _RoleApp(UserRole.operation, Icons.dashboard_customize, AppColors.roleOperation),
      _RoleApp(UserRole.supervisor, Icons.assignment_ind, AppColors.roleSupervisor),
      _RoleApp(UserRole.campBoss, Icons.holiday_village, AppColors.roleCampBoss),
      _RoleApp(UserRole.driver, Icons.directions_bus, AppColors.roleDriver),
      _RoleApp(UserRole.employee, Icons.person, AppColors.roleEmployee),
    ];

    // إذا مسجل دخول، نعرض فقط الأدوار التي يملكها
    final roles = auth.isLoggedIn
        ? allRoles.where((r) {
            // Super Admin يرى كل شيء
            if (auth.isSuperAdmin) return true;
            return auth.roles.any((rd) => _matchesUserRole(rd.key, r.role));
          }).toList()
        : allRoles;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ================= الهيدر =================
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.brand,
                          AppColors.brand.withOpacity(0.7),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.brand.withOpacity(0.3),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: BrandLogo(color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.appName,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                          ),
                        ),
                        Text(
                          s.appTagline,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  _MiniIconButton(
                    icon: Icons.language,
                    onTap: () => context.read<LocaleProvider>().toggle(),
                    label: isAr ? 'EN' : 'AR',
                  ),
                  const SizedBox(width: 6),
                  Consumer<ThemeProvider>(
                    builder: (_, t, __) => _MiniIconButton(
                      icon: t.isDark ? Icons.light_mode : Icons.dark_mode,
                      onTap: () => t.toggle(),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 28),

              // ================= العنوان الرئيسي =================
              ShaderMask(
                shaderCallback: (rect) => LinearGradient(
                  colors: [
                    AppColors.brand,
                    AppColors.brand.withOpacity(0.7),
                  ],
                ).createShader(rect),
                child: Text(
                  s.selectApp,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                s.selectAppHint,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.color
                          ?.withOpacity(0.7),
                    ),
              ),

              const SizedBox(height: 20),

              // ================= بطاقات الأدوار =================
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // تحديد عدد الأعمدة حسب العرض
                    final width = constraints.maxWidth;
                    final cols = width >= 700
                        ? 4
                        : width >= 500
                            ? 3
                            : 3; // 3 أعمدة للموبايل (مربعات أصغر)
                    return GridView.builder(
                      itemCount: roles.length,
                      padding: EdgeInsets.zero,
                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 0.92,
                      ),
                      itemBuilder: (_, i) {
                        final r = roles[i];
                        return _AppCard(
                          role: r.role,
                          icon: r.icon,
                          color: r.color,
                          title: isAr
                              ? r.role.arabicName()
                              : r.role.englishName(),
                          subtitle: _subtitle(r.role, isAr),
                          onTap: () {
                            context.read<AuthProvider>().selectApp(r.role);
                          },
                        );
                      },
                    );
                  },
                ),
              ),

              const SizedBox(height: 8),
              Center(
                child: Text(
                  isAr
                      ? 'الإصدار 1.0.0 • إنتاج'
                      : 'Version 1.0.0 • Production',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).disabledColor,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitle(UserRole role, bool isAr) {
    switch (role) {
      case UserRole.manager:
        return isAr ? 'وصول كامل' : 'Full access';
      case UserRole.operation:
        return isAr ? 'مراجعة وموافقات' : 'Reviews';
      case UserRole.supervisor:
        return isAr ? 'إنشاء روستر' : 'Roster';
      case UserRole.campBoss:
        return isAr ? 'الكامب' : 'Camp';
      case UserRole.driver:
        return isAr ? 'الرحلات' : 'Trips';
      case UserRole.employee:
        return isAr ? 'جدولي' : 'My schedule';
    }
  }
}

class _RoleApp {
  final UserRole role;
  final IconData icon;
  final Color color;
  _RoleApp(this.role, this.icon, this.color);
}

/// بطاقة دور - تصميم مدمج وأنيق
class _AppCard extends StatefulWidget {
  final UserRole role;
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AppCard({
    required this.role,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  State<_AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<_AppCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = Theme.of(context).cardTheme.color ??
        (isDark ? const Color(0xFF1F2235) : Colors.white);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        transform: _hovered
            ? (Matrix4.identity()..translate(0.0, -3.0, 0.0))
            : Matrix4.identity(),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: widget.color.withOpacity(_hovered ? 0.22 : 0.10),
              blurRadius: _hovered ? 18 : 10,
              offset: Offset(0, _hovered ? 8 : 4),
            ),
          ],
        ),
        child: Material(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            child: Stack(
              children: [
                // زخرفة دائرية ركن علوي
                Positioned(
                  top: -20,
                  right: -20,
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.color.withOpacity(0.08),
                    ),
                  ),
                ),
                // الحدود الناعمة
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: widget.color.withOpacity(_hovered ? 0.45 : 0.18),
                        width: 1.2,
                      ),
                    ),
                  ),
                ),
                // المحتوى
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // أيقونة بتدرج
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              widget.color,
                              widget.color.withOpacity(0.65),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: widget.color.withOpacity(0.35),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Icon(widget.icon,
                            color: Colors.white, size: 20),
                      ),
                      const Spacer(),
                      // الاسم
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      // الوصف
                      Text(
                        widget.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.color
                              ?.withOpacity(0.65),
                        ),
                      ),
                      const SizedBox(height: 6),
                      // مؤشر الدخول
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: widget.color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.arrow_forward,
                                size: 11, color: widget.color),
                            const SizedBox(width: 3),
                            Text(
                              AppStrings.of(context).login,
                              style: TextStyle(
                                fontSize: 9.5,
                                color: widget.color,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? label;

  const _MiniIconButton({
    required this.icon,
    required this.onTap,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: label == null ? 8 : 10, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            if (label != null) ...[
              const SizedBox(width: 4),
              Text(label!,
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700)),
            ],
          ],
        ),
      ),
    );
  }
}
