import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/l10n/app_strings.dart';
import '../core/providers/auth_provider.dart';
import '../core/providers/locale_provider.dart';
import '../core/providers/theme_provider.dart';
import '../core/theme/app_colors.dart';
import '../features/admin/admin_home.dart';
import '../features/auth/country_selector.dart';
import '../features/camp_boss/camp_boss_home.dart';
import '../features/driver/driver_home.dart';
import '../features/employee/employee_home.dart';
import '../features/manager/manager_home.dart';
import '../features/operation/operation_home.dart';
import '../features/policies/policies_screen.dart';
import '../features/supervisor/supervisor_home.dart';
import '../models/enums.dart';
import '../repositories/mock_repository.dart';

/// تخطيط موحد لكل تطبيق دور: AppBar + Drawer + Bottom Nav
/// يفلتر التابات تلقائياً حسب صلاحيات المستخدم
class RoleScaffold extends StatelessWidget {
  final String title;
  final List<RoleTab> tabs;
  final int currentIndex;
  final ValueChanged<int> onTabSelected;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final Color color;

  const RoleScaffold({
    super.key,
    required this.title,
    required this.tabs,
    required this.currentIndex,
    required this.onTabSelected,
    this.actions,
    this.floatingActionButton,
    this.color = AppColors.brand,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final auth = context.watch<AuthProvider>();

    // فلترة التابات حسب الصلاحيات
    final visibleTabs = tabs.where((t) {
      if (t.requiredPermission == null) return true;
      // إذا كان المستخدم غير مسجل دخول، نعرض كل شيء (وضع تجريبي)
      if (!auth.isLoggedIn) return true;
      return auth.hasPermission(t.requiredPermission!);
    }).toList();

    // إذا لا توجد تابات مرئية، عرض حالة فارغة
    if (visibleTabs.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        drawer: _AppDrawer(title: title, color: color),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_outline,
                    size: 56, color: AppColors.textTertiaryLight),
                const SizedBox(height: 12),
                Text(
                  s.isAr
                      ? 'ليس لديك صلاحية للوصول لأي قسم'
                      : 'You do not have permission to access any section',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppColors.textSecondaryLight, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ضبط الـ index ضمن نطاق التابات المرئية
    final safeIndex = currentIndex.clamp(0, visibleTabs.length - 1);
    final tab = visibleTabs[safeIndex];

    // الدولة النشطة (للعرض في الـ AppBar)
    final activeCountry = auth.activeCountryId == null
        ? null
        : MockRepository().countryById(auth.activeCountryId!);
    // يظهر زر تبديل الدولة لـ:
    //  - Super Admin (دائماً، مع زر "All" إذا لم يختر)
    //  - أي مستخدم له أكثر من دولة
    final showCountryChip =
        auth.isSuperAdmin || auth.countryIds.length > 1;

    return Scaffold(
      appBar: AppBar(
        title: Text(tab.title),
        actions: [
          ...?actions,
          // شارة الدولة الحالية + إمكانية التبديل
          if (showCountryChip)
            _CountryChip(country: activeCountry, isAr: s.isAr),
          IconButton(
            icon: const Icon(Icons.language, size: 20),
            tooltip: s.language,
            onPressed: () => context.read<LocaleProvider>().toggle(),
          ),
          Consumer<ThemeProvider>(
            builder: (_, t, __) => IconButton(
              icon: Icon(
                t.isDark ? Icons.light_mode : Icons.dark_mode,
                size: 20,
              ),
              tooltip: s.theme,
              onPressed: () => t.toggle(),
            ),
          ),
        ],
      ),
      drawer: _AppDrawer(title: title, color: color),
      body: IndexedStack(
        index: safeIndex,
        children: visibleTabs.map((t) => t.body).toList(),
      ),
      bottomNavigationBar: visibleTabs.length < 2
          ? null
          : NavigationBar(
              selectedIndex: safeIndex,
              onDestinationSelected: (i) {
                // نمرّر الـ index بناءً على الموضع في visibleTabs
                onTabSelected(i);
              },
              destinations: visibleTabs
                  .map((t) => NavigationDestination(
                        icon: Icon(t.icon),
                        selectedIcon: Icon(t.icon, color: color),
                        label: t.shortTitle ?? t.title,
                      ))
                  .toList(),
            ),
      floatingActionButton: floatingActionButton,
    );
  }
}

class RoleTab {
  final IconData icon;
  final String title;
  final String? shortTitle;
  final Widget body;
  final String? requiredPermission; // مفتاح صلاحية لإظهار التاب

  RoleTab({
    required this.icon,
    required this.title,
    this.shortTitle,
    required this.body,
    this.requiredPermission,
  });
}

class _AppDrawer extends StatelessWidget {
  final String title;
  final Color color;
  const _AppDrawer({required this.title, required this.color});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;

    // 🆕 احضر الموظّف المرتبط بالحساب لعرض صورته في رأس القائمة الجانبيّة
    // الترتيب:
    //   1) user.employeeId (الربط المباشر)
    //   2) fallback: مطابقة بالاسم الكامل من قائمة الموظّفين
    String? photoUrl;
    if (user != null) {
      final repo = MockRepository();
      String? empPhotoRaw;

      // (1) محاولة عبر employeeId
      if (user.employeeId != null) {
        try {
          empPhotoRaw =
              repo.employeeById(user.employeeId!)?.photoFileId;
        } catch (_) {}
      }

      // (2) fallback عبر مطابقة الاسم
      if (empPhotoRaw == null || empPhotoRaw.isEmpty) {
        final name = user.fullName.trim();
        if (name.isNotEmpty) {
          try {
            final match = repo.employees.firstWhere(
              (e) => e.fullName.trim().toLowerCase() == name.toLowerCase(),
            );
            empPhotoRaw = match.photoFileId;
          } catch (_) {}
        }
      }

      if (empPhotoRaw != null &&
          empPhotoRaw.isNotEmpty &&
          (empPhotoRaw.startsWith('http://') ||
              empPhotoRaw.startsWith('https://'))) {
        photoUrl = empPhotoRaw;
      }
    }

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [color, color.withOpacity(0.7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 🆕 صورة الموظّف إن وُجدت — وإلا الأحرف الأولى
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.white,
                    backgroundImage:
                        photoUrl != null ? NetworkImage(photoUrl) : null,
                    child: photoUrl != null
                        ? null
                        : Text(
                            user?.initials ?? '?',
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                            ),
                          ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    user?.fullName ?? '',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    s.isAr
                        ? user?.role.arabicName() ?? ''
                        : user?.role.englishName() ?? '',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: Text(s.notifications),
              onTap: () {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(s.isAr
                          ? 'لا توجد إشعارات حالياً'
                          : 'No notifications')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(s.profile),
              onTap: () => Navigator.of(context).pop(),
            ),
            // ===== مبدّل التطبيقات (Super Admin فقط) =====
            if (auth.isSuperAdmin) ...[
              const Divider(height: 1, indent: 16, endIndent: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  s.isAr ? 'الانتقال بين التطبيقات' : 'Switch App',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.warning,
                      letterSpacing: 0.5),
                ),
              ),
              _AppSwitcher(color: color),
              const Divider(height: 1, indent: 16, endIndent: 16),
            ],
            // تبديل الدولة (للمستخدمين متعددي الدول)
            if (auth.countryIds.length > 1 || auth.isSuperAdmin)
              ListTile(
                leading: const Icon(Icons.public),
                title: Text(s.isAr ? 'تبديل الدولة' : 'Switch Country'),
                subtitle: auth.activeCountryId != null
                    ? Text(
                        MockRepository()
                                .countryById(auth.activeCountryId!)
                                ?.code ??
                            '',
                        style: const TextStyle(fontSize: 11),
                      )
                    : null,
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        const CountrySelectorScreen(isSwitch: true),
                  ));
                },
              ),
            if (!auth.isLoggedIn || auth.hasPermission('policies.view'))
              ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: Text(s.policies),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: Text(s.policies)),
                      body: const PoliciesScreen(),
                    ),
                  ));
                },
              ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: Text(s.settings),
              onTap: () => Navigator.of(context).pop(),
            ),
            const Spacer(),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout, color: AppColors.danger),
              title: Text(
                s.logout,
                style: const TextStyle(color: AppColors.danger),
              ),
              onTap: () {
                context.read<AuthProvider>().logout();
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// مبدّل التطبيقات - يظهر في Drawer لـ Super Admin فقط
/// يسمح له بالوصول لأي home من 7 خيارات
class _AppSwitcher extends StatelessWidget {
  final Color color;
  const _AppSwitcher({required this.color});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final apps = [
      _AppEntry(
        icon: Icons.shield_moon_outlined,
        labelAr: 'لوحة الإدارة',
        labelEn: 'Admin Console',
        color: AppColors.brand,
        builder: (_) => const AdminHome(),
      ),
      _AppEntry(
        icon: Icons.admin_panel_settings,
        labelAr: 'العمليات',
        labelEn: 'Operations',
        color: AppColors.roleManager,
        builder: (_) => const ManagerHome(),
      ),
      _AppEntry(
        icon: Icons.dashboard_customize,
        labelAr: 'تطبيق العمليات',
        labelEn: 'Operation App',
        color: AppColors.roleOperation,
        builder: (_) => const OperationHome(),
      ),
      _AppEntry(
        icon: Icons.assignment_ind,
        labelAr: 'تطبيق المشرف',
        labelEn: 'Supervisor App',
        color: AppColors.roleSupervisor,
        builder: (_) => const SupervisorHome(),
      ),
      _AppEntry(
        icon: Icons.holiday_village,
        labelAr: 'تطبيق الكمب',
        labelEn: 'Camp Boss App',
        color: AppColors.roleCampBoss,
        builder: (_) => const CampBossHome(),
      ),
      _AppEntry(
        icon: Icons.directions_bus,
        labelAr: 'تطبيق السائق',
        labelEn: 'Driver App',
        color: AppColors.roleDriver,
        builder: (_) => const DriverHome(),
      ),
      _AppEntry(
        icon: Icons.person,
        labelAr: 'تطبيق الموظف',
        labelEn: 'Employee App',
        color: AppColors.roleEmployee,
        builder: (_) => const EmployeeHome(),
      ),
    ];

    return Column(
      children: apps.map((a) {
        return ListTile(
          leading: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: a.color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(a.icon, color: a.color, size: 18),
          ),
          title: Text(
            s.isAr ? a.labelAr : a.labelEn,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          dense: true,
          onTap: () {
            Navigator.of(context).pop();
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: a.builder),
            );
          },
        );
      }).toList(),
    );
  }
}

class _AppEntry {
  final IconData icon;
  final String labelAr;
  final String labelEn;
  final Color color;
  final WidgetBuilder builder;
  _AppEntry({
    required this.icon,
    required this.labelAr,
    required this.labelEn,
    required this.color,
    required this.builder,
  });
}

/// شارة الدولة الحالية - تظهر في AppBar
/// إذا لم تكن هناك دولة محددة، تعرض "All" (لـ Super Admin) أو "Select"
class _CountryChip extends StatelessWidget {
  final dynamic country; // Country object أو null
  final bool isAr;
  const _CountryChip({required this.country, required this.isAr});

  @override
  Widget build(BuildContext context) {
    final hasCountry = country != null;
    final label = hasCountry ? country.code : (isAr ? 'الكل' : 'All');
    final color = hasCountry ? AppColors.brand : AppColors.warning;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const CountrySelectorScreen(isSwitch: true),
          ));
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.4), width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(hasCountry ? Icons.public : Icons.public_off,
                  size: 12, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 2),
              Icon(Icons.keyboard_arrow_down, size: 14, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

Color colorForRole(UserRole role) {
  switch (role) {
    case UserRole.manager:
      return AppColors.roleManager;
    case UserRole.operation:
      return AppColors.roleOperation;
    case UserRole.supervisor:
      return AppColors.roleSupervisor;
    case UserRole.campBoss:
      return AppColors.roleCampBoss;
    case UserRole.driver:
      return AppColors.roleDriver;
    case UserRole.employee:
      return AppColors.roleEmployee;
  }
}
