import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/device_session_settings.dart';
import '../../core/services/face_attempt_tracker.dart';
import '../../core/services/login_method_settings.dart';
import '../../core/services/supabase_data_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../models/models.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/m7_app_bar.dart';
import '../../shared/permission_gate.dart';
import 'account_report_screen.dart';
import 'bulk_account_creator.dart';
import 'face_enrollment_screen.dart';
import '../../core/services/face_enrollment_service.dart';

/// شاشة إدارة المستخدمين
class AdminUsers extends StatefulWidget {
  const AdminUsers({super.key});

  @override
  State<AdminUsers> createState() => _AdminUsersState();
}

class _AdminUsersState extends State<AdminUsers> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  bool _showInactive = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // تطبيق التسلسل الهرمي: غير Super Admin لا يرى حسابات Super Admin
    final auth = context.watch<AuthProvider>();
    final canSeeSuperAdmins = auth.isSuperAdmin;
    // 🆕 صلاحيّة التعديل
    final canEdit = auth.isSuperAdmin ||
        auth.permissions.contains(P.adminUsersEdit);

    // 🆕 الـpriority الأَعلى لِكلّ حساب — لِلْفلتر الهَرَميّ
    int accountTopPriority(AppAccount a) {
      if (a.isSuperAdmin) return 1000;
      // أَعلى priority بَين كلّ أدوار الحساب
      var max = 0;
      for (final ur in repo.userRoleAssignments
          .where((u) => u.userId == a.id)) {
        try {
          final r = repo.roleDefs.firstWhere((x) => x.id == ur.roleId);
          if (r.priority > max) max = r.priority;
        } catch (_) {}
      }
      return max;
    }

    final myPriority = auth.topPriority;

    final list = repo.accounts.where((a) {
      if (!canSeeSuperAdmins && a.isSuperAdmin) return false;
      if (!_showInactive && !a.isActive) return false;
      // 🔐 فلتر هَرَميّ: غير Super Admin لا يَرى مَن هم في مُستواه أو أَعلى
      // (يَرى نَفسه + أَدنى مُستوى منه)
      if (!auth.isSuperAdmin && a.id != auth.account?.id) {
        final theirPriority = accountTopPriority(a);
        if (theirPriority >= myPriority) return false;
      }
      if (_query.trim().isEmpty) return true;
      final q = _query.toLowerCase();
      return a.username.toLowerCase().contains(q) ||
          a.fullName.toLowerCase().contains(q) ||
          (a.email ?? '').toLowerCase().contains(q);
    }).toList()
      ..sort((a, b) {
        if (a.isSuperAdmin != b.isSuperAdmin) {
          return a.isSuperAdmin ? -1 : 1;
        }
        return a.fullName.compareTo(b.fullName);
      });

    // 🆕 عَدد الحسابات المَخفيّة بِفَلتر الهَرَميّة (لِلإعلام)
    final totalVisible = repo.accounts.where((a) {
      if (!canSeeSuperAdmins && a.isSuperAdmin) return false;
      if (!_showInactive && !a.isActive) return false;
      return true;
    }).length;
    final hierarchyHidden = totalVisible - list.where((a) {
      if (_query.trim().isEmpty) return true;
      final q = _query.toLowerCase();
      return a.username.toLowerCase().contains(q) ||
          a.fullName.toLowerCase().contains(q) ||
          (a.email ?? '').toLowerCase().contains(q);
    }).length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: M7AppBar(
        title: s.isAr ? '👥 إدارة المُستَخدِمين' : '👥 Users',
      ),
      body: Column(
        children: [
          // ===== شريط البحث + فلتر =====
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.surface2Dark
                          : AppColors.surface2Light,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (v) => setState(() => _query = v),
                      decoration: InputDecoration(
                        hintText: s.isAr
                            ? 'بحث بالاسم أو اسم المستخدم...'
                            : 'Search name or username...',
                        prefixIcon: const Icon(Icons.search, size: 18),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        hintStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    _showInactive ? Icons.visibility : Icons.visibility_off,
                    color: _showInactive
                        ? AppColors.brand
                        : (isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight),
                  ),
                  tooltip: s.isAr ? 'عرض المعطلين' : 'Show inactive',
                  onPressed: () =>
                      setState(() => _showInactive = !_showInactive),
                ),
              ],
            ),
          ),
          // ===== Counter + Bulk Create =====
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      s.isAr
                          ? '${list.length} مستخدم'
                          : '${list.length} users',
                      style: TextStyle(
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondaryLight,
                          fontSize: 11),
                    ),
                    // 🔐 شارة إعلام بالـmasked
                    if (hierarchyHidden > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.shield_outlined,
                                size: 10, color: AppColors.warning),
                            const SizedBox(width: 3),
                            Text(
                              s.isAr
                                  ? '+$hierarchyHidden مَخفيّ'
                                  : '+$hierarchyHidden hidden',
                              style: const TextStyle(
                                fontSize: 9,
                                color: AppColors.warning,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                // 🆕 زرّ "إنشاء حسابات للموظّفين" — يَظهَر لو فيه موظّفون
                // بدون حساب + المُستخدِم لَه صلاحيّة الإنشاء.
                Builder(builder: (ctx) {
                  final auth = ctx.read<AuthProvider>();
                  final canCreate = auth.isSuperAdmin ||
                      auth.permissions.contains(P.adminUsersCreate) ||
                      auth.permissions.contains(P.adminUsersManage);
                  if (!canCreate) return const SizedBox.shrink();
                  final repo = MockRepository();
                  final linked = <String>{
                    for (final a in repo.accounts)
                      if (a.employeeId != null && a.employeeId!.isNotEmpty)
                        a.employeeId!,
                  };
                  // 🔐 طَبِّق فلتر الهَرَميّة لِلْعَدّاد أيضاً
                  final pending = repo.employees.where((e) {
                    if (e.status != EntityStatus.active) return false;
                    if (linked.contains(e.id)) return false;
                    if (auth.isSuperAdmin) return true;
                    if (e.jobTitleId == null) return true;
                    try {
                      final jt = repo.jobTitles
                          .firstWhere((j) => j.id == e.jobTitleId);
                      if (jt.roleId == null) return true;
                      final role = repo.roleDefs
                          .firstWhere((r) => r.id == jt.roleId);
                      if (role.key == SystemRoles.superAdmin) return false;
                      return role.priority < auth.topPriority;
                    } catch (_) {
                      return true;
                    }
                  }).length;
                  if (pending == 0) return const SizedBox.shrink();
                  return TextButton.icon(
                    icon: const Icon(Icons.group_add, size: 16),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.brand,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                    onPressed: () {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const BulkAccountCreatorScreen(),
                      ));
                    },
                    label: Text(
                      s.isAr
                          ? '🪪 إنشاء حسابات ($pending)'
                          : '🪪 Create accounts ($pending)',
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w800),
                    ),
                  );
                }),
              ],
            ),
          ),
          // ===== List =====
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text(
                      s.isAr ? 'لا يوجد مستخدمون' : 'No users',
                      style: TextStyle(
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondaryLight),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 96),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final acc = list[i];
                      return _UserCard(
                        account: acc,
                        isDark: isDark,
                        // 🆕 onTap = null لو لا يملك صلاحيّة التعديل
                        onTap:
                            canEdit ? () => _openEditUser(acc) : null,
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: PermissionGate(
        permission: P.adminUsersCreate,
        child: FloatingActionButton.extended(
          backgroundColor: AppColors.brand,
          onPressed: _openCreateUser,
          icon: const Icon(Icons.person_add, color: Colors.white),
          label: Text(
            s.isAr ? 'مستخدم جديد' : 'New User',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ),
    );
  }

  void _openCreateUser() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _UserFormSheet(),
    );
  }

  void _openEditUser(AppAccount acc) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _UserFormSheet(account: acc),
    );
  }
}

// ============================================================
// كارد مستخدم
// ============================================================
class _UserCard extends StatelessWidget {
  final AppAccount account;
  final bool isDark;
  /// 🆕 nullable — لو null يَعرض البطاقة بدون onTap (read-only)
  final VoidCallback? onTap;
  const _UserCard({
    required this.account,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final roles = repo.rolesOfAccount(account.id);
    final countries = repo.countryIdsOfAccount(account.id).length;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: account.isSuperAdmin
                ? AppColors.warning.withValues(alpha: 0.5)
                : (isDark
                    ? AppColors.borderDark
                    : AppColors.borderLight),
            width: account.isSuperAdmin ? 1 : 0.5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: account.isSuperAdmin
                        ? AppColors.warning.withValues(alpha: 0.2)
                        : AppColors.brand.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    account.initials,
                    style: TextStyle(
                        color: account.isSuperAdmin
                            ? AppColors.warning
                            : AppColors.brand,
                        fontWeight: FontWeight.w800,
                        fontSize: 14),
                  ),
                ),
                const SizedBox(width: 12),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              account.fullName,
                              style: TextStyle(
                                  color: isDark
                                      ? AppColors.textDark
                                      : AppColors.textLight,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (account.isSuperAdmin)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                s.isAr ? 'مدير عام' : 'Super',
                                style: const TextStyle(
                                    color: AppColors.warning,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800),
                              ),
                            ),
                          if (!account.isActive) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.danger.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                s.isAr ? 'معطل' : 'Inactive',
                                style: const TextStyle(
                                    color: AppColors.danger,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '@${account.username}',
                        style: TextStyle(
                            color: isDark
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondaryLight,
                            fontSize: 11),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          ...roles.take(3).map((r) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.brand.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  s.isAr ? r.nameAr : r.nameEn,
                                  style: const TextStyle(
                                      color: AppColors.brand,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700),
                                ),
                              )),
                          if (roles.length > 3)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.brand.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '+${roles.length - 3}',
                                style: const TextStyle(
                                    color: AppColors.brand,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.public,
                                    size: 9, color: AppColors.success),
                                const SizedBox(width: 3),
                                Text(
                                  '$countries',
                                  style: const TextStyle(
                                      color: AppColors.success,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // 🆕 2026-05-23: حُذِفَ زِرّ بَصمة الوَجه السَريع — مُكَرَّر مَع
                // _UserFaceEnrollmentCard في شاشة Edit User. وُحِّدَ المَدخَل
                // لِتَجَنُّب تَضارُب UX.
                // 🆕 زِرّ تَقرير الحِساب (Account 360)
                IconButton(
                  tooltip: s.isAr
                      ? 'تَقرير الحِساب'
                      : 'Account Report',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 36, minHeight: 36),
                  icon: const Icon(Icons.assessment_outlined,
                      color: AppColors.info, size: 20),
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) =>
                          AccountReportScreen(account: account),
                    ));
                  },
                ),
                Icon(Icons.chevron_right,
                    color: isDark
                        ? AppColors.textTertiaryDark
                        : AppColors.textTertiaryLight,
                    size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// شيت إنشاء/تعديل مستخدم
// ============================================================
class _UserFormSheet extends StatefulWidget {
  final AppAccount? account;
  const _UserFormSheet({this.account});

  @override
  State<_UserFormSheet> createState() => _UserFormSheetState();
}

class _UserFormSheetState extends State<_UserFormSheet> {
  final _username = TextEditingController();
  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _isActive = true;
  bool _isSuperAdmin = false;
  String? _linkedEmployeeId; // 🆕 ربط بسجل موظف
  // 🆕 تجاوز سياسة الجهاز لهذا الحساب: null=اتبع العام، true=فرض، false=إعفاء
  bool? _devicePolicyOverride;
  // 🆕 تجاوز طريقة الدخول: null=اتبع العام، password/face=فرض
  LoginMethod? _loginMethodOverride;
  final Set<String> _selectedRoles = {};
  final Set<String> _selectedCountries = {};
  // 🆕 حالة المزامنة الحيّة للأدوار/الدول من Supabase
  bool _refreshingRoles = false;
  bool _refreshingCountries = false;

  bool get isEdit => widget.account != null;

  @override
  void initState() {
    super.initState();
    if (widget.account != null) {
      final a = widget.account!;
      _username.text = a.username;
      _fullName.text = a.fullName;
      _email.text = a.email ?? '';
      _phone.text = a.phone ?? '';
      _isActive = a.isActive;
      _isSuperAdmin = a.isSuperAdmin;
      _linkedEmployeeId = a.employeeId;
      final repo = MockRepository();
      _selectedRoles
          .addAll(repo.rolesOfAccount(a.id).map((r) => r.id));
      _selectedCountries.addAll(repo.countryIdsOfAccount(a.id));
    } else {
      // افتراضياً المستخدم الجديد عنده وصول للدول كلها
      final repo = MockRepository();
      _selectedCountries.addAll(repo.countries.map((c) => c.id));
    }
    // 🆕 حمّل تجاوز سياسة الجهاز إن وُجد
    DeviceSessionSettings.instance.load().then((_) {
      if (!mounted) return;
      setState(() {
        if (widget.account != null) {
          _devicePolicyOverride = DeviceSessionSettings.instance
              .overrideFor(widget.account!.id);
        }
      });
    });
    // 🆕 حمّل تجاوز طريقة الدخول إن وُجد
    LoginMethodSettings.instance.load().then((_) {
      if (!mounted) return;
      setState(() {
        if (widget.account != null) {
          _loginMethodOverride = LoginMethodSettings.instance
              .overrideFor(widget.account!.id);
        }
      });
    });
    // 🆕 مَزامنة الأدوار + الدول مَرّة واحدة من Supabase حتّى تَكون
    // القائمة هنا تَعكس آخر حالة في النظام (إضافة/حذف).
    _refreshRolesFromSupabase();
    _refreshCountriesFromSupabase();
  }

  /// يَجلب أحدث الأدوار من Supabase ويُحدّث الواجهة.
  /// يُستدعى تلقائيّاً عند فَتح الشيت + يَدويّاً عَبر زرّ التحديث.
  Future<void> _refreshRolesFromSupabase({bool showSnack = false}) async {
    if (!SupabaseService().isReady) return;
    if (!mounted) return;
    setState(() => _refreshingRoles = true);
    try {
      final ds = SupabaseDataService();
      await ds.syncRoles();
      await ds.syncRolePermissions();
    } catch (_) {
      // تَجاهل — الواجهة ستَستعمل النسخة المحلّيّة كَ fallback
    }
    if (!mounted) return;
    setState(() => _refreshingRoles = false);
    if (showSnack && mounted) {
      final s = AppStrings.of(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 2),
        content: Text(s.isAr ? '✅ تَمّ تَحديث قائمة الأدوار' : '✅ Roles refreshed'),
      ));
    }
  }

  // 🆕 إظهار الأدوار اليتيمة (القديمة) — بشكل افتراضيّ مَخفيّة
  bool _showLegacyRoles = false;

  /// الأدوار "ذات الصِلَة" — تَستحقّ العَرض في القائمة:
  ///   ✅ النظاميّة (super_admin/admin/manager/operation/supervisor/…)
  ///   ✅ المَربوطة بِمسمّى وظيفيّ
  ///   ✅ مَربوطة فعلاً بِهذا الحساب الحاليّ (نَحتفظ بها كي نُظهر الإسناد القائم)
  bool _isRelevantRole(RoleDef r) {
    final repo = MockRepository();
    final systemKeys = {
      SystemRoles.superAdmin,
      SystemRoles.admin,
      SystemRoles.manager,
      SystemRoles.operation,
      SystemRoles.supervisor,
      SystemRoles.campBoss,
      SystemRoles.driver,
      SystemRoles.employee,
    };
    if (systemKeys.contains(r.key)) return true;
    final linked = repo.jobTitles.any((j) => j.roleId == r.id);
    if (linked) return true;
    if (_selectedRoles.contains(r.id)) return true;
    return false;
  }

  /// يَجلب أحدث الدول من Supabase ويُحدّث الواجهة.
  Future<void> _refreshCountriesFromSupabase({bool showSnack = false}) async {
    if (!SupabaseService().isReady) return;
    if (!mounted) return;
    setState(() => _refreshingCountries = true);
    try {
      await SupabaseDataService().syncCountries();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _refreshingCountries = false);
    if (showSnack && mounted) {
      final s = AppStrings.of(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 2),
        content: Text(s.isAr ? '✅ تَمّ تَحديث قائمة الدول' : '✅ Countries refreshed'),
      ));
    }
  }

  @override
  void dispose() {
    _username.dispose();
    _fullName.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final auth = context.read<AuthProvider>();
    final byUser = auth.currentUser?.id ?? '';

    if (_username.text.trim().isEmpty || _fullName.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(s.isAr ? 'الحقول الأساسية مطلوبة' : 'Required fields')),
      );
      return;
    }

    if (!isEdit && _password.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.isAr ? 'أدخل كلمة المرور' : 'Enter password')),
      );
      return;
    }

    // اسم المستخدم فريد
    final dup = repo.accounts.any((a) =>
        a.username.toLowerCase() == _username.text.trim().toLowerCase() &&
        a.id != (widget.account?.id ?? ''));
    if (dup) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(s.isAr
                ? 'اسم المستخدم موجود بالفعل'
                : 'Username already exists')),
      );
      return;
    }

    final supaReady = SupabaseService().isReady;
    final ds = SupabaseDataService();

    if (isEdit) {
      final a = widget.account!;
      a.username = _username.text.trim();
      a.fullName = _fullName.text.trim();
      a.email = _email.text.trim().isEmpty ? null : _email.text.trim();
      a.phone = _phone.text.trim().isEmpty ? null : _phone.text.trim();
      a.isActive = _isActive;
      a.isSuperAdmin = _isSuperAdmin;
      a.employeeId = _linkedEmployeeId; // 🆕 ربط بموظف
      if (_password.text.trim().isNotEmpty) {
        a.passwordHash = _password.text.trim();
      }
      if (supaReady) {
        final ok = await ds.updateAccount(
          a,
          roleIds: _selectedRoles.toList(),
          countryIds: _selectedCountries.toList(),
        );
        if (!ok && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: Colors.red,
            content: Text(ds.lastError ?? 'Failed'),
          ));
          return;
        }
      } else {
        repo.updateAccount(a, byUser);
        repo.setUserRoles(a.id, _selectedRoles.toList(), byUser);
        repo.setUserCountries(a.id, _selectedCountries.toList(), byUser);
      }
    } else {
      final acc = AppAccount(
        id: repo.generateId(),
        username: _username.text.trim(),
        passwordHash: _password.text.trim(),
        fullName: _fullName.text.trim(),
        email: _email.text.trim().isEmpty ? null : _email.text.trim(),
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        employeeId: _linkedEmployeeId, // 🆕
        isActive: _isActive,
        isSuperAdmin: _isSuperAdmin,
      );
      if (supaReady) {
        final created = await ds.createAccount(
          acc,
          roleIds: _selectedRoles.toList(),
          countryIds: _selectedCountries.toList(),
        );
        if (created == null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: Colors.red,
            content: Text(ds.lastError ?? 'Failed'),
          ));
          return;
        }
      } else {
        repo.createAccount(
            acc, _selectedRoles.toList(), _selectedCountries.toList(), byUser);
      }
      // 🆕 احفظ تجاوز سياسة الجهاز للحساب الجديد
      await DeviceSessionSettings.instance
          .setOverride(acc.id, _devicePolicyOverride);
      // 🆕 احفظ تجاوز طريقة الدخول للحساب الجديد
      await LoginMethodSettings.instance
          .setOverride(acc.id, _loginMethodOverride);
    }

    // 🆕 احفظ تجاوز سياسة الجهاز للحساب الموجود
    if (isEdit) {
      await DeviceSessionSettings.instance
          .setOverride(widget.account!.id, _devicePolicyOverride);
      await LoginMethodSettings.instance
          .setOverride(widget.account!.id, _loginMethodOverride);
    }

    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.success,
        content: Text(s.success),
      ),
    );
  }

  // ==========================================================
  // 🆕 تَعطيل/تَفعيل الحِساب — تَحديث is_active فَقَط
  // ==========================================================
  Future<void> _toggleActive() async {
    if (widget.account == null) return;
    final s = AppStrings.of(context);
    final a = widget.account!;
    final newState = !a.isActive;
    final supaReady = SupabaseService().isReady;
    final ds = SupabaseDataService();
    final repo = MockRepository();
    final auth = context.read<AuthProvider>();
    final byUser = auth.currentUser?.id ?? '';

    // 🔒 امنع تَعطيل النفس
    if (auth.currentUser?.id == a.id) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text(
            s.isAr ? 'لا يُمكنك تَعطيل حِسابك' : 'You cannot deactivate yourself'),
      ));
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(newState
            ? (s.isAr ? 'تَفعيل المُستَخدِم' : 'Activate user?')
            : (s.isAr ? 'تَعطيل المُستَخدِم' : 'Deactivate user?')),
        content: Text(newState
            ? (s.isAr
                ? 'سَيَستَطيع المُستَخدِم تَسجيل الدُخول مَرّة أُخرى.'
                : 'The user will be able to sign in again.')
            : (s.isAr
                ? 'لَن يَتَمَكَّن المُستَخدِم من تَسجيل الدُخول لكِن البَيانات تَبقى.'
                : 'The user will not be able to sign in, but their data is kept.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.isAr ? 'إلغاء' : 'Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  newState ? AppColors.success : AppColors.warning,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(newState
                ? (s.isAr ? 'تَفعيل' : 'Activate')
                : (s.isAr ? 'تَعطيل' : 'Deactivate')),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    a.isActive = newState;
    if (supaReady) {
      final ok = await ds.updateAccount(
        a,
        roleIds: _selectedRoles.toList(),
        countryIds: _selectedCountries.toList(),
      );
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.danger,
          content: Text(ds.lastError ?? 'Failed'),
        ));
        return;
      }
    } else {
      repo.updateAccount(a, byUser);
    }

    if (!mounted) return;
    setState(() => _isActive = newState);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.success,
      content: Text(newState
          ? (s.isAr ? '✅ تَمّ تَفعيل الحِساب' : '✅ User activated')
          : (s.isAr ? '⏸ تَمّ تَعطيل الحِساب' : '⏸ User deactivated')),
    ));
  }

  // ==========================================================
  // 🆕 حَذف نِهائيّ — مع تَأكيد مُضاعَف
  // ==========================================================
  Future<void> _confirmAndDelete() async {
    if (widget.account == null) return;
    final s = AppStrings.of(context);
    final a = widget.account!;
    final supaReady = SupabaseService().isReady;
    final ds = SupabaseDataService();
    final repo = MockRepository();
    final auth = context.read<AuthProvider>();

    // 🔒 امنع حَذف النفس
    if (auth.currentUser?.id == a.id) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text(
            s.isAr ? 'لا يُمكنك حَذف حِسابك' : 'You cannot delete yourself'),
      ));
      return;
    }

    // 🔒 امنع حَذف المُدير العام الوَحيد
    if (a.isSuperAdmin) {
      final remainingSupers =
          repo.accounts.where((x) => x.isSuperAdmin && x.id != a.id).length;
      if (remainingSupers == 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.danger,
          content: Text(s.isAr
              ? 'لا يُمكن حَذف آخِر مُدير عام في النِظام'
              : 'Cannot delete the last super-admin'),
        ));
        return;
      }
    }

    // تَأكيد أَوَّل
    final confirm1 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
            s.isAr ? '⚠️ حَذف نِهائيّ' : '⚠️ Delete permanently?'),
        content: Text(s.isAr
            ? 'سَيُحذَف "${a.fullName}" نِهائيّاً مَع كافّة أَدواره ودَوَله المَربوطة. '
                'هَل أَنتَ مُتَأَكِّد؟\n\n'
                'نَنصَح بِالتَعطيل بَدَلاً من الحَذف للحِفاظ على السِجِلّات.'
            : 'User "${a.fullName}" will be permanently deleted with all roles. '
                'Are you sure?\n\n'
                'Deactivate is usually safer — it preserves audit history.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.isAr ? 'إلغاء' : 'Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.isAr ? 'مُتابَعة' : 'Continue'),
          ),
        ],
      ),
    );
    if (confirm1 != true) return;

    // تَأكيد ثاني — اِكتُب اسم المُستَخدِم
    final typed = TextEditingController();
    final confirm2 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.isAr ? '🔒 تَأكيد نِهائيّ' : '🔒 Final confirmation'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.isAr
                ? 'اِكتُب اسم المُستَخدِم لِتَأكيد الحَذف:'
                : 'Type the username to confirm:'),
            const SizedBox(height: 6),
            Text(a.username,
                style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: AppColors.danger,
                    fontSize: 16)),
            const SizedBox(height: 10),
            TextField(
              controller: typed,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: s.isAr ? 'اسم المُستَخدِم' : 'Username',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.isAr ? 'إلغاء' : 'Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (typed.text.trim() == a.username) {
                Navigator.pop(ctx, true);
              } else {
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                  backgroundColor: AppColors.danger,
                  content: Text(s.isAr
                      ? 'الاسم غَير مُطابِق'
                      : 'Username does not match'),
                ));
              }
            },
            child: Text(s.isAr ? 'حَذف نِهائيّ' : 'Delete'),
          ),
        ],
      ),
    );
    if (confirm2 != true) return;

    if (supaReady) {
      final ok = await ds.deleteAccount(a.id);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.danger,
          content: Text(ds.lastError ?? 'Failed'),
        ));
        return;
      }
    } else {
      // Mock fallback — لا يُوجد deleteAccount مُتَخَصِّص، نَحذف مُباشَرَةً
      repo.accounts.removeWhere((x) => x.id == a.id);
      repo.notifyListeners();
    }

    // نَظِّف التَجاوُزات المَحلِّيّة
    await DeviceSessionSettings.instance.removeAccount(a.id);
    await LoginMethodSettings.instance.removeAccount(a.id);

    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.success,
      content: Text(
          s.isAr ? '🗑 تَمّ حَذف الحِساب' : '🗑 Account deleted'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor =
        isDark ? AppColors.surfaceDark : AppColors.surfaceLight;

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.borderDark
                    : AppColors.borderLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      isEdit
                          ? (s.isAr ? 'تعديل مستخدم' : 'Edit User')
                          : (s.isAr ? 'مستخدم جديد' : 'New User'),
                      style: TextStyle(
                          color: isDark
                              ? AppColors.textDark
                              : AppColors.textLight,
                          fontSize: 16,
                          fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 16),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: ListView(
                  controller: controller,
                  // 🆕 2026-05-23: padding سُفليّ يَحسِب شَريط النِظام
                  // (kept 20 sides; bottom = nav-bar height + 20 لِئَلّا يَختَفي زِرّ "Save")
                  padding: EdgeInsets.fromLTRB(
                      20, 0, 20,
                      MediaQuery.of(context).viewPadding.bottom + 20),
                  children: [
                  _Section(title: s.isAr ? 'البيانات الأساسية' : 'Basic Info'),
                  _Field(
                    label: s.isAr ? 'الاسم الكامل' : 'Full Name',
                    controller: _fullName,
                  ),
                  _Field(
                    label: s.isAr ? 'اسم المستخدم' : 'Username',
                    controller: _username,
                  ),
                  _Field(
                    label: isEdit
                        ? (s.isAr
                            ? 'كلمة مرور جديدة (اختياري)'
                            : 'New Password (optional)')
                        : (s.isAr ? 'كلمة المرور' : 'Password'),
                    controller: _password,
                    obscure: true,
                  ),
                  _Field(
                    label: s.isAr ? 'البريد الإلكتروني' : 'Email',
                    controller: _email,
                  ),
                  _Field(
                    label: s.isAr ? 'الهاتف' : 'Phone',
                    controller: _phone,
                  ),

                  // 🆕 ربط بموظف
                  const SizedBox(height: 12),
                  _EmployeePicker(
                    selectedEmployeeId: _linkedEmployeeId,
                    filterCountryIds: _selectedCountries.toSet(),
                    onChanged: (id) =>
                        setState(() => _linkedEmployeeId = id),
                  ),

                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: Text(s.isAr ? 'الحساب نشط' : 'Active'),
                    contentPadding: EdgeInsets.zero,
                    value: _isActive,
                    onChanged: (v) => setState(() => _isActive = v),
                  ),
                  // مفتاح Super Admin يظهر فقط لـ Super Admin (الهرمية)
                  if (context.read<AuthProvider>().isSuperAdmin)
                    SwitchListTile(
                      title: Text(
                        s.isAr ? 'مدير عام (Super Admin)' : 'Super Admin',
                        style: const TextStyle(color: AppColors.warning),
                      ),
                      subtitle: Text(
                        s.isAr
                            ? 'يملك كل الصلاحيات بدون استثناء'
                            : 'Has all permissions',
                        style: const TextStyle(fontSize: 11),
                      ),
                      contentPadding: EdgeInsets.zero,
                      value: _isSuperAdmin,
                      onChanged: (v) => setState(() => _isSuperAdmin = v),
                    ),

                  // 🆕 سياسة الجهاز لهذا الحساب
                  _DevicePolicyToggle(
                    isAr: s.isAr,
                    value: _devicePolicyOverride,
                    onChanged: (v) =>
                        setState(() => _devicePolicyOverride = v),
                  ),

                  // 🆕 طريقة الدخول لهذا الحساب
                  _LoginMethodToggle(
                    isAr: s.isAr,
                    value: _loginMethodOverride,
                    onChanged: (v) =>
                        setState(() => _loginMethodOverride = v),
                  ),

                  // 🆕 زرّ فكّ قفل بصمة الوجه (لو الحساب مقفل)
                  if (isEdit && widget.account != null)
                    _FaceUnlockButton(
                      accountId: widget.account!.id,
                      isAr: s.isAr,
                    ),

                  // ===== الأدوار (مفلتر بحسب الهرمية + الـrelevance) =====
                  Builder(builder: (ctx) {
                    final auth = ctx.read<AuthProvider>();
                    // كلّ الأدوار الّتي يَستطيع المستخدم الحاليّ إدارتها
                    final manageable = repo.roleDefs
                        .where((r) => auth.canManageRole(r))
                        .toList();
                    final relevant =
                        manageable.where(_isRelevantRole).toList();
                    final legacyCount = manageable.length - relevant.length;
                    final visible =
                        _showLegacyRoles ? manageable : relevant;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SectionWithAction(
                          title: s.isAr
                              ? 'الأدوار (${visible.length})'
                              : 'Roles (${visible.length})',
                          busy: _refreshingRoles,
                          tooltip: s.isAr
                              ? 'تَحديث من النظام'
                              : 'Refresh from server',
                          onRefresh: () =>
                              _refreshRolesFromSupabase(showSnack: true),
                        ),
                        // إعلام بالأدوار القديمة + زرّ إظهار/إخفاء
                        if (legacyCount > 0)
                          Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.warning.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.info_outline,
                                    size: 14,
                                    color: AppColors.warning),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    s.isAr
                                        ? '$legacyCount دَور قديم غير مَربوط بِمسمّى وظيفيّ مَخفيّ'
                                        : '$legacyCount legacy role(s) hidden',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.warning,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => setState(() =>
                                      _showLegacyRoles = !_showLegacyRoles),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: Text(
                                    _showLegacyRoles
                                        ? (s.isAr ? 'إخفاء' : 'Hide')
                                        : (s.isAr ? 'إظهار' : 'Show'),
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ...visible.map((r) {
                          final isLegacy = !_isRelevantRole(r);
                          return CheckboxListTile(
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(s.isAr ? r.nameAr : r.nameEn),
                                ),
                                if (isLegacy)
                                  Container(
                                    padding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 1),
                                    decoration: BoxDecoration(
                                      color: AppColors.warning
                                          .withValues(alpha: 0.15),
                                      borderRadius:
                                          BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      s.isAr ? 'قديم' : 'Legacy',
                                      style: const TextStyle(
                                          fontSize: 9,
                                          color: AppColors.warning,
                                          fontWeight:
                                              FontWeight.w900),
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Text(
                              s.isAr
                                  ? r.descriptionAr ?? ''
                                  : r.descriptionEn ?? '',
                              style: const TextStyle(fontSize: 11),
                            ),
                            contentPadding: EdgeInsets.zero,
                            controlAffinity:
                                ListTileControlAffinity.leading,
                            value: _selectedRoles.contains(r.id),
                            onChanged: (v) => setState(() {
                              if (v == true) {
                                _selectedRoles.add(r.id);
                              } else {
                                _selectedRoles.remove(r.id);
                              }
                            }),
                          );
                        }),
                      ],
                    );
                  }),

                  // ===== الدول =====
                  _SectionWithAction(
                    title: s.isAr
                        ? 'الدول المتاحة (${repo.countries.length})'
                        : 'Allowed Countries (${repo.countries.length})',
                    busy: _refreshingCountries,
                    tooltip: s.isAr
                        ? 'تَحديث من النظام'
                        : 'Refresh from server',
                    onRefresh: () =>
                        _refreshCountriesFromSupabase(showSnack: true),
                  ),
                  ...repo.countries.map((c) => CheckboxListTile(
                        title: Text(s.isAr ? c.nameAr : c.nameEn),
                        subtitle: Text(c.code),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _selectedCountries.contains(c.id),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selectedCountries.add(c.id);
                          } else {
                            _selectedCountries.remove(c.id);
                          }
                        }),
                      )),

                  // 🆕 بَصمة الوَجه — تَظهَر فَقَط لِلمُستَخدِم المَوجود وَالمَربوط بِمُوَظَّف
                  if (isEdit && widget.account!.employeeId != null) ...[
                    const SizedBox(height: 16),
                    _UserFaceEnrollmentCard(
                      account: widget.account!,
                      isAr: s.isAr,
                    ),
                  ],

                  const SizedBox(height: 20),
                  // ===== Save =====
                  ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brand,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      isEdit
                          ? (s.isAr ? 'حفظ التغييرات' : 'Save Changes')
                          : (s.isAr ? 'إنشاء المستخدم' : 'Create User'),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ),
                  // 🆕 زِرّ تَعطيل/حَذف (يَظهَر فَقَط عَنَدَ التَعديل)
                  if (isEdit) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _toggleActive,
                            icon: Icon(
                              widget.account?.isActive == true
                                  ? Icons.do_disturb_alt
                                  : Icons.check_circle,
                              size: 16,
                            ),
                            label: Text(
                              widget.account?.isActive == true
                                  ? (s.isAr ? 'تَعطيل' : 'Deactivate')
                                  : (s.isAr ? 'تَفعيل' : 'Activate'),
                              style: const TextStyle(fontSize: 12),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.warning,
                              side: const BorderSide(color: AppColors.warning),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _confirmAndDelete,
                            icon: const Icon(Icons.delete_forever, size: 16),
                            label: Text(
                              s.isAr ? 'حَذف نِهائيّ' : 'Delete',
                              style: const TextStyle(fontSize: 12),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.danger,
                              side: const BorderSide(color: AppColors.danger),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  ], // close ListView children
                ), // close ListView
              ), // close Padding (keyboard fix)
            ), // close Expanded
          ], // close Column children
        ), // close Column
      ), // close Container
    ); // close DraggableScrollableSheet
  }
}

class _Section extends StatelessWidget {
  final String title;
  const _Section({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
            color: AppColors.brand,
            fontSize: 12,
            fontWeight: FontWeight.w800),
      ),
    );
  }
}

/// 🆕 رَأس قسم مع زرّ تَحديث (sync من Supabase).
class _SectionWithAction extends StatelessWidget {
  final String title;
  final bool busy;
  final String tooltip;
  final VoidCallback onRefresh;
  const _SectionWithAction({
    required this.title,
    required this.busy,
    required this.tooltip,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: AppColors.brand,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          SizedBox(
            width: 28,
            height: 28,
            child: busy
                ? const Padding(
                    padding: EdgeInsets.all(6),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.brand,
                    ),
                  )
                : IconButton(
                    iconSize: 16,
                    padding: EdgeInsets.zero,
                    tooltip: tooltip,
                    icon: const Icon(Icons.refresh,
                        color: AppColors.brand),
                    onPressed: onRefresh,
                  ),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool obscure;
  const _Field({
    required this.label,
    required this.controller,
    this.obscure = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }
}

// ============================================================
// منتقي الموظف (لربط الحساب بسجل موظف)
// ============================================================
class _EmployeePicker extends StatelessWidget {
  final String? selectedEmployeeId;
  final Set<String> filterCountryIds; // 🆕 الدول التي يُسمح باختيار موظفيها
  final void Function(String?) onChanged;
  const _EmployeePicker({
    required this.selectedEmployeeId,
    required this.filterCountryIds,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    // فلترة الموظفين بالدول المختارة للحساب
    var employees = repo.employees.toList();
    if (filterCountryIds.isNotEmpty) {
      employees = employees
          .where((e) =>
              e.countryId != null && filterCountryIds.contains(e.countryId))
          .toList();
    }
    employees.sort((a, b) => a.fullName.compareTo(b.fullName));

    // 🛡️ إن كان selectedEmployeeId يشير لموظف غير موجود (مثلاً تم حذفه)،
    // نعتبره null لتفادي خطأ الـ Dropdown
    final validIds = employees.map((e) => e.id).toSet();
    final safeSelected = (selectedEmployeeId != null &&
            validIds.contains(selectedEmployeeId))
        ? selectedEmployeeId
        : null;
    // إن كان هناك ID قديم غير صالح، نخبر الأب لمسحه من state
    if (selectedEmployeeId != null && safeSelected == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onChanged(null);
      });
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.brand.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.brand.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.badge_outlined,
                  size: 16, color: AppColors.brand),
              const SizedBox(width: 6),
              Text(
                s.isAr
                    ? 'ربط الحساب بسجل موظف (اختياري)'
                    : 'Link to Employee Record (optional)',
                style: const TextStyle(
                  color: AppColors.brand,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            filterCountryIds.isEmpty
                ? (s.isAr
                    ? 'اختر الدول أولاً ثم سيظهر موظفوها هنا'
                    : 'Select countries first to see their employees')
                : (s.isAr
                    ? 'يعرض فقط موظفي الدول المختارة (${employees.length} موظف)'
                    : 'Shows employees of selected countries only (${employees.length})'),
            style: TextStyle(
              fontSize: 10,
              color: filterCountryIds.isEmpty
                  ? AppColors.warning
                  : AppColors.textSecondaryLight,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String?>(
            value: safeSelected,
            isExpanded: true,
            isDense: true,
            decoration: InputDecoration(
              labelText: s.isAr ? 'الموظف' : 'Employee',
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 8),
              filled: true,
              fillColor: Theme.of(context).cardTheme.color,
            ),
            items: [
              DropdownMenuItem(
                value: null,
                child: Text(
                  s.isAr ? 'بدون ربط (حساب إداري)' : 'No link (admin account)',
                  style: const TextStyle(
                      fontSize: 12, fontStyle: FontStyle.italic),
                ),
              ),
              ...employees.map((e) => DropdownMenuItem(
                    value: e.id,
                    child: Text(
                      '${e.code} • ${e.fullName}',
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  )),
            ],
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 🆕 مفتاح سياسة الجهاز لحساب محدّد
// ============================================================
//   • null  = اتبع الإعداد العامّ (الافتراضي)
//   • true  = افرض السياسة على هذا الحساب صراحةً
//   • false = أعفِ هذا الحساب صراحةً من السياسة
class _DevicePolicyToggle extends StatelessWidget {
  final bool isAr;
  final bool? value; // null = inherit
  final ValueChanged<bool?> onChanged;
  const _DevicePolicyToggle({
    required this.isAr,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    String subtitle;
    IconData icon;

    if (value == true) {
      color = AppColors.success;
      label = isAr
          ? 'سياسة الجهاز: مفعّلة لهذا الحساب'
          : 'Device policy: ENFORCED for this account';
      subtitle = isAr
          ? 'لا يستطيع الدخول إلّا من جهاز واحد. لتغيير الجهاز يجب حذف الجلسة من المسؤول.'
          : 'Can only log in from one device. Admin must delete session to allow new device.';
      icon = Icons.lock_outline;
    } else if (value == false) {
      color = AppColors.warning;
      label = isAr
          ? 'سياسة الجهاز: مُعفى هذا الحساب'
          : 'Device policy: EXEMPT for this account';
      subtitle = isAr
          ? 'يستطيع الدخول من أيّ جهاز دون قيود (تجاوز للسياسة العامّة).'
          : 'Can log in from any device without restriction (overrides global).';
      icon = Icons.lock_open_outlined;
    } else {
      color = AppColors.brand;
      label = isAr
          ? 'سياسة الجهاز: تتبع الإعداد العامّ'
          : 'Device policy: follow global setting';
      subtitle = isAr
          ? 'يطبَّق ما هو محدّد في «مركز الإعدادات → سياسة الأجهزة».'
          : 'Whatever is set in Settings Hub → Device Policy applies.';
      icon = Icons.settings_outlined;
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w800),
                ),
              ),
              if (value != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: isAr ? 'مسح التجاوز' : 'Clear override',
                  icon: const Icon(Icons.refresh, size: 18),
                  onPressed: () => onChanged(null),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 26, right: 4),
            child: Text(subtitle,
                style: const TextStyle(fontSize: 11)),
          ),
          const SizedBox(height: 8),
          // أزرار اختيار 3-حالات
          Row(
            children: [
              Expanded(
                child: _SegBtn(
                  label: isAr ? 'تفعيل' : 'Enforce',
                  icon: Icons.check_circle_outline,
                  selected: value == true,
                  color: AppColors.success,
                  onTap: () => onChanged(true),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _SegBtn(
                  label: isAr ? 'إعفاء' : 'Exempt',
                  icon: Icons.do_not_disturb_on_outlined,
                  selected: value == false,
                  color: AppColors.warning,
                  onTap: () => onChanged(false),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _SegBtn(
                  label: isAr ? 'افتراضي' : 'Default',
                  icon: Icons.settings_outlined,
                  selected: value == null,
                  color: AppColors.brand,
                  onTap: () => onChanged(null),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SegBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const _SegBtn({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color:
              selected ? color.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected
                  ? color
                  : Theme.of(context).dividerColor,
              width: selected ? 1 : 0.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14,
                color: selected
                    ? color
                    : Theme.of(context).iconTheme.color),
            const SizedBox(width: 4),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                      color: selected ? color : null,
                      fontSize: 11,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 🆕 مفتاح طريقة الدخول (3 حالات)
// ============================================================
class _LoginMethodToggle extends StatelessWidget {
  final bool isAr;
  final LoginMethod? value; // null = inherit
  final ValueChanged<LoginMethod?> onChanged;
  const _LoginMethodToggle({
    required this.isAr,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    String subtitle;
    IconData icon;

    if (value == LoginMethod.password) {
      color = AppColors.brand;
      label = isAr
          ? 'طريقة الدخول: كلمة المرور (مفروضة)'
          : 'Login: PASSWORD (forced)';
      subtitle = isAr
          ? 'هذا الحساب يدخل بكلمة المرور فقط — تجاوز للسياسة العامّة.'
          : 'Forced to use password regardless of global policy.';
      icon = Icons.password;
    } else if (value == LoginMethod.face) {
      color = AppColors.success;
      label = isAr
          ? 'طريقة الدخول: بصمة الوجه (مفروضة)'
          : 'Login: FACE (forced)';
      subtitle = isAr
          ? 'هذا الحساب يدخل ببصمة الوجه — تجاوز للسياسة العامّة.'
          : 'Forced to use face login regardless of global policy.';
      icon = Icons.face;
    } else {
      color = AppColors.warning;
      label = isAr
          ? 'طريقة الدخول: تتبع الإعداد العامّ'
          : 'Login: follow global setting';
      subtitle = isAr
          ? 'يطبَّق ما هو محدّد في «مركز الإعدادات → طريقة الدخول».'
          : 'Whatever is set in Settings Hub → Login Method applies.';
      icon = Icons.settings_outlined;
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w800),
                ),
              ),
              if (value != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: isAr ? 'مسح التجاوز' : 'Clear',
                  icon: const Icon(Icons.refresh, size: 18),
                  onPressed: () => onChanged(null),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 26, right: 4),
            child: Text(subtitle,
                style: const TextStyle(fontSize: 11)),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _MethodSegBtn(
                  label: isAr ? 'كلمة المرور' : 'Password',
                  icon: Icons.password,
                  selected: value == LoginMethod.password,
                  color: AppColors.brand,
                  onTap: () => onChanged(LoginMethod.password),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _MethodSegBtn(
                  label: isAr ? 'بصمة الوجه' : 'Face',
                  icon: Icons.face,
                  selected: value == LoginMethod.face,
                  color: AppColors.success,
                  onTap: () => onChanged(LoginMethod.face),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _MethodSegBtn(
                  label: isAr ? 'افتراضي' : 'Default',
                  icon: Icons.settings_outlined,
                  selected: value == null,
                  color: AppColors.warning,
                  onTap: () => onChanged(null),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MethodSegBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const _MethodSegBtn({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected
                  ? color
                  : Theme.of(context).dividerColor,
              width: selected ? 1 : 0.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14,
                color: selected
                    ? color
                    : Theme.of(context).iconTheme.color),
            const SizedBox(width: 4),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                      color: selected ? color : null,
                      fontSize: 11,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 🔓 زرّ فكّ قفل بصمة الوجه — يظهر فقط لو الحساب مقفل
// ============================================================
class _FaceUnlockButton extends StatefulWidget {
  final String accountId;
  final bool isAr;
  const _FaceUnlockButton({
    required this.accountId,
    required this.isAr,
  });
  @override
  State<_FaceUnlockButton> createState() => _FaceUnlockButtonState();
}

class _FaceUnlockButtonState extends State<_FaceUnlockButton> {
  FaceAttemptStatus? _status;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final s = await FaceAttemptTracker.instance
        .currentStatus(widget.accountId);
    if (mounted) setState(() => _status = s);
  }

  Future<void> _unlock() async {
    await FaceAttemptTracker.instance.unlockAccount(widget.accountId);
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.success,
      content: Text(widget.isAr
          ? '✓ تمّ فكّ قفل بصمة الوجه'
          : '✓ Face login unlocked'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    if (s == null) return const SizedBox.shrink();
    if (s.outcome != FaceAttemptOutcome.locked &&
        s.outcome != FaceAttemptOutcome.cooldown) {
      return const SizedBox.shrink();
    }
    final isLocked = s.outcome == FaceAttemptOutcome.locked;
    final color = isLocked ? AppColors.danger : AppColors.warning;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.5),
      ),
      child: Row(
        children: [
          Icon(isLocked ? Icons.lock : Icons.timer_outlined,
              color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isLocked
                      ? (widget.isAr
                          ? 'بصمة الوجه: مقفلة'
                          : 'Face login: LOCKED')
                      : (widget.isAr
                          ? 'بصمة الوجه: في تهدئة'
                          : 'Face login: COOLDOWN'),
                  style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w800),
                ),
                Text(
                  widget.isAr
                      ? 'فشل ${s.failedCount} محاولة'
                      : '${s.failedCount} failed attempts',
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: FilledButton.tonal(
              onPressed: _unlock,
              style: FilledButton.styleFrom(
                backgroundColor: color.withValues(alpha: 0.15),
                foregroundColor: color,
              ),
              child: Text(
                widget.isAr ? 'فكّ القفل' : 'Unlock',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 🆕 بِطاقة بَصمة الوَجه لِلمُستَخدِم (في شاشة المُستَخدِمين)
// ============================================================
class _UserFaceEnrollmentCard extends StatefulWidget {
  final AppAccount account;
  final bool isAr;
  const _UserFaceEnrollmentCard({
    required this.account,
    required this.isAr,
  });
  @override
  State<_UserFaceEnrollmentCard> createState() =>
      _UserFaceEnrollmentCardState();
}

class _UserFaceEnrollmentCardState extends State<_UserFaceEnrollmentCard> {
  bool _loading = true;
  int _enrolledCount = 0;
  static const _requiredPoses = 5;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final empId = widget.account.employeeId;
    if (empId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final list = await FaceEnrollmentService.instance
          .listForEmployee(empId);
      if (mounted) {
        setState(() {
          _enrolledCount = list.length;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openEnrollment() async {
    final empId = widget.account.employeeId;
    if (empId == null) return;
    final emp = MockRepository().employeeById(empId);
    if (emp == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text(widget.isAr
            ? 'الموظَّف المَربوط غَير مَوجود'
            : 'Linked employee not found'),
      ));
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => FaceEnrollmentScreen(employee: emp),
      ),
    );
    await _load();
  }

  /// 🆕 حَذف كُلّ صُوَر بَصمة الوَجه لِهذا المُستَخدِم
  Future<void> _deleteEnrollment() async {
    final empId = widget.account.employeeId;
    if (empId == null) return;
    final isAr = widget.isAr;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber, color: AppColors.danger),
            const SizedBox(width: 8),
            Text(isAr ? 'حَذف بَصمة الوَجه؟' : 'Delete Face Biometric?'),
          ],
        ),
        content: Text(
          isAr
              ? 'سَيَتِمّ حَذف جَميع صُوَر بَصمة الوَجه ($_enrolledCount صُوَر).\n'
                  'سَيَحتاج المُوَظَّف لِإعادة التَسجيل مِن جَديد.\n\n'
                  'هَل أَنتَ مُتَأَكِّد؟'
              : 'All face biometric photos ($_enrolledCount images) will be deleted.\n'
                  'The employee will need to re-enroll.\n\n'
                  'Are you sure?',
          style: const TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isAr ? 'إلغاء' : 'Cancel'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.delete_outline, size: 16),
            label: Text(isAr ? 'حَذف نِهائيّ' : 'Delete'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _loading = true);
    final ok = await FaceEnrollmentService.instance.deleteAll(empId);
    if (!mounted) return;
    setState(() => _loading = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: ok ? AppColors.success : AppColors.danger,
      content: Text(ok
          ? (isAr
              ? '✓ تَمّ حَذف بَصمة الوَجه بِنَجاح'
              : '✓ Face biometric deleted')
          : (isAr ? 'فَشَل الحَذف' : 'Failed to delete')),
    ));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final isAr = widget.isAr;
    final complete = _enrolledCount >= _requiredPoses;
    final partial = _enrolledCount > 0 && !complete;
    final color = complete
        ? AppColors.success
        : partial
            ? AppColors.warning
            : Colors.grey;
    final status = complete
        ? (isAr ? '✓ مُكتَمِلة' : '✓ Complete')
        : partial
            ? (isAr
                ? '⚠ ناقِصة ($_enrolledCount/$_requiredPoses)'
                : '⚠ Incomplete ($_enrolledCount/$_requiredPoses)')
            : (isAr ? '❌ لم تُسَجَّل بَعد' : '❌ Not enrolled');

    final hasAny = _enrolledCount > 0;

    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _loading ? null : _openEnrollment,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.face_retouching_natural,
                      color: color, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isAr
                            ? '😊 بَصمة الوَجه لِلدُخول'
                            : '😊 Face Biometric for Login',
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _loading
                            ? (isAr ? 'جارٍ التَحميل…' : 'Loading…')
                            : status,
                        style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w700,
                            fontSize: 11),
                      ),
                    ],
                  ),
                ),
                // 🆕 زِرّ حَذف يَظهَر فَقَط إذا وُجِدَت بَصمة
                if (hasAny && !_loading)
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: AppColors.danger, size: 20),
                    tooltip: isAr
                        ? 'حَذف بَصمة الوَجه'
                        : 'Delete face biometric',
                    onPressed: _deleteEnrollment,
                  ),
                Icon(Icons.chevron_right, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
