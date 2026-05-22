import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/face_enrollment_service.dart';
import '../../core/services/m7_log.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../models/models.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/m7_app_bar.dart';
import 'employee_profile_hub.dart';
import 'face_enrollment_screen.dart';
import 'terminal_sessions_screen.dart';

/// 📊 تَقرير شامِل (Account 360) عَن حِساب واحِد
///
/// يُجمَع في صَفحة واحِدة: مَعلومات الحِساب، الدَور وَالصَلاحيّات، الموظَّف
/// المَربوط، بَصمة الوَجه، الجَلسات/الأَجهِزة، وَالنَشاط الأَخير.
class AccountReportScreen extends StatefulWidget {
  final AppAccount account;
  const AccountReportScreen({super.key, required this.account});

  @override
  State<AccountReportScreen> createState() => _AccountReportScreenState();
}

class _AccountReportScreenState extends State<AccountReportScreen> {
  bool _loading = true;
  // قِيَم تُحَدَّث بَعد الجَلب
  int _activeSessions = 0;
  int _totalSessions = 0;
  int _notificationsTotal = 0;
  int _notificationsUnread = 0;
  bool _hasFace = false;
  int _faceCount = 0;
  DateTime? _faceLastEnrolledAt;
  List<_SessionRow> _sessions = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await Future.wait([
      _loadSessions(),
      _loadNotifications(),
      _loadFace(),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadSessions() async {
    final supa = SupabaseService();
    if (!supa.isReady) return;
    try {
      final rows = await supa.client
          .from('point_terminal_sessions')
          .select(
              'id,account_id,point_id,device_id,device_name,device_label,is_active,first_login_at,last_seen_at')
          .eq('account_id', widget.account.id)
          .order('last_seen_at', ascending: false)
          .limit(20);
      final list = rows
          .whereType<Map>()
          .map((r) => _SessionRow.fromMap(Map<String, dynamic>.from(r)))
          .toList();
      _sessions = list;
      _totalSessions = list.length;
      _activeSessions = list.where((s) => s.isActive).length;
        } catch (e) {
      M7Log.error('AccountReport', 'sessions', error: e);
    }
  }

  Future<void> _loadNotifications() async {
    final supa = SupabaseService();
    if (!supa.isReady) return;
    try {
      final rows = await supa.client
          .from('notifications')
          .select('id,is_read')
          .eq('user_id', widget.account.id);
      _notificationsTotal = rows.length;
      _notificationsUnread = rows
          .whereType<Map>()
          .where((r) => r['is_read'] == false || r['is_read'] == null)
          .length;
        } catch (e) {
      // الجَدول قد لا يَكون مَوجوداً في كُلّ البيئات — نَتَجاهَل بِصَمت
      M7Log.warn('AccountReport', 'notifications: $e');
    }
  }

  Future<void> _loadFace() async {
    final empId = widget.account.employeeId;
    if (empId == null) return;
    try {
      final list =
          await FaceEnrollmentService.instance.listForEmployee(empId);
      _faceCount = list.length;
      _hasFace = list.isNotEmpty;
      if (list.isNotEmpty) {
        list.sort((a, b) => b.enrolledAt.compareTo(a.enrolledAt));
        _faceLastEnrolledAt = list.first.enrolledAt;
      }
    } catch (e) {
      M7Log.error('AccountReport', 'face', error: e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final acc = widget.account;
    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? 'تَقرير الحِساب' : 'Account Report',
        subtitle: '@${acc.username}',
        actions: [
          M7AppBarAction(
            icon: Icons.refresh,
            tooltip: isAr ? 'تَحديث' : 'Refresh',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _AccountHeader(account: acc),
            const SizedBox(height: 12),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            const SizedBox(height: 6),
            _AccountInfoSection(account: acc),
            const SizedBox(height: 10),
            _RolePermsSection(account: acc),
            const SizedBox(height: 10),
            _EmployeeLinkSection(account: acc),
            const SizedBox(height: 10),
            _FaceSection(
              account: acc,
              hasFace: _hasFace,
              count: _faceCount,
              lastEnrolledAt: _faceLastEnrolledAt,
            ),
            const SizedBox(height: 10),
            _SessionsSection(
              account: acc,
              active: _activeSessions,
              total: _totalSessions,
              sessions: _sessions,
            ),
            const SizedBox(height: 10),
            _ActivitySection(
              account: acc,
              notificationsTotal: _notificationsTotal,
              notificationsUnread: _notificationsUnread,
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// عَناصِر التَخطيط المُشتَرَكة
// ============================================================
class _Section extends StatelessWidget {
  final IconData icon;
  final String titleAr;
  final String titleEn;
  final Color color;
  final List<Widget> children;
  const _Section({
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
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12)),
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

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  final Color? color;
  const _Row({required this.label, required this.value, this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: color ?? Colors.grey, size: 16),
            const SizedBox(width: 6),
          ],
          SizedBox(
            width: 130,
            child: Text(label,
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
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

String _fmtDate(DateTime? d, {bool withTime = false}) {
  if (d == null) return '—';
  two(int n) => n.toString().padLeft(2, '0');
  final base = '${d.year}-${two(d.month)}-${two(d.day)}';
  if (!withTime) return base;
  return '$base ${two(d.hour)}:${two(d.minute)}';
}

// ============================================================
// 🆔 رَأس الصَفحة — بِطاقة الحِساب
// ============================================================
class _AccountHeader extends StatelessWidget {
  final AppAccount account;
  const _AccountHeader({required this.account});

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final color = account.isActive ? AppColors.success : Colors.red;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.brand.withValues(alpha: 0.10),
            AppColors.gold.withValues(alpha: 0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: AppColors.gold.withValues(alpha: 0.30), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                AppColors.gold.withValues(alpha: 0.40),
                AppColors.gold.withValues(alpha: 0.15),
              ]),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(account.initials,
                style: const TextStyle(
                    color: AppColors.brand,
                    fontWeight: FontWeight.w900,
                    fontSize: 22)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(account.fullName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 16)),
                Text('@${account.username}',
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: Colors.grey)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _Badge(
                        label: account.isActive
                            ? (isAr ? 'نَشِط' : 'Active')
                            : (isAr ? 'مُعَطَّل' : 'Inactive'),
                        color: color,
                        icon: account.isActive
                            ? Icons.check_circle
                            : Icons.cancel),
                    if (account.isSuperAdmin)
                      _Badge(
                          label:
                              isAr ? 'مَسؤول عام' : 'Super Admin',
                          color: AppColors.warning,
                          icon: Icons.shield),
                    if (account.isPointTerminal)
                      _Badge(
                          label: isAr ? 'جِهاز نُقطة' : 'Terminal',
                          color: AppColors.info,
                          icon: Icons.point_of_sale),
                    if (account.mustEnrollFace)
                      _Badge(
                          label: isAr
                              ? 'يَجِب تَسجيل بَصمة'
                              : 'Face required',
                          color: Colors.orange,
                          icon: Icons.face_retouching_natural),
                    if (account.mustChangePassword)
                      _Badge(
                          label:
                              isAr ? 'تَغيير كلمة المرور' : 'Change password',
                          color: Colors.purple,
                          icon: Icons.key),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  const _Badge({required this.label, required this.color, required this.icon});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 10)),
        ],
      ),
    );
  }
}

// ============================================================
// قِسم: مَعلومات الحِساب
// ============================================================
class _AccountInfoSection extends StatelessWidget {
  final AppAccount account;
  const _AccountInfoSection({required this.account});

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return _Section(
      icon: Icons.info_outline,
      titleAr: 'مَعلومات الحِساب',
      titleEn: 'Account Info',
      color: AppColors.info,
      children: [
        _Row(
            label: isAr ? 'اسم المُستَخدِم' : 'Username',
            value: '@${account.username}',
            icon: Icons.alternate_email),
        _Row(
            label: isAr ? 'الاسم الكامِل' : 'Full name',
            value: account.fullName,
            icon: Icons.person_outline),
        _Row(
            label: isAr ? 'البَريد الإلِكتروني' : 'Email',
            value: account.email ?? '—',
            icon: Icons.email_outlined),
        _Row(
            label: isAr ? 'الجَوّال' : 'Phone',
            value: account.phone ?? '—',
            icon: Icons.phone),
        _Row(
            label: isAr ? 'الحالة' : 'Status',
            value: account.isActive
                ? (isAr ? 'نَشِط' : 'Active')
                : (isAr ? 'مُعَطَّل' : 'Inactive'),
            color: account.isActive ? AppColors.success : Colors.red,
            icon: account.isActive ? Icons.check_circle : Icons.cancel),
        _Row(
            label: isAr ? 'نَوع الحِساب' : 'Account type',
            value: account.isPointTerminal
                ? (isAr ? 'جِهاز نُقطة (Terminal)' : 'Point Terminal')
                : (isAr ? 'مُوَظَّف' : 'Employee'),
            icon: Icons.category_outlined),
        _Row(
            label: isAr ? 'تاريخ الإنشاء' : 'Created at',
            value: _fmtDate(account.createdAt, withTime: true),
            icon: Icons.event),
        _Row(
            label: isAr ? 'آخِر دُخول' : 'Last login',
            value: _fmtDate(account.lastLoginAt, withTime: true),
            icon: Icons.login),
        _Row(
            label: isAr ? 'أَوَّل دُخول' : 'First login',
            value: _fmtDate(account.firstLoginAt, withTime: true),
            icon: Icons.flag_outlined),
      ],
    );
  }
}

// ============================================================
// قِسم: الدَور وَالصَلاحيّات
// ============================================================
class _RolePermsSection extends StatelessWidget {
  final AppAccount account;
  const _RolePermsSection({required this.account});

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final repo = MockRepository();
    final roles = repo.rolesOfAccount(account.id);
    final permKeys = repo.effectivePermissionKeys(account.id);

    return _Section(
      icon: Icons.shield_outlined,
      titleAr: 'الدَور وَالصَلاحيّات',
      titleEn: 'Role & Permissions',
      color: Colors.deepPurple,
      children: [
        if (roles.isEmpty)
          Text(isAr ? 'لا يُوجَد دَور مُعَيَّن' : 'No role assigned',
              style: const TextStyle(color: Colors.grey, fontSize: 12))
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: roles
                .map((r) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: Colors.deepPurple.withValues(alpha: 0.30)),
                      ),
                      child: Text(
                        r.nameAr.isNotEmpty
                            ? (isAr ? r.nameAr : r.nameEn)
                            : r.key,
                        style: const TextStyle(
                            color: Colors.deepPurple,
                            fontWeight: FontWeight.w900,
                            fontSize: 11),
                      ),
                    ))
                .toList(),
          ),
        const SizedBox(height: 8),
        _Row(
            label: isAr ? 'عَدَد الصَلاحيّات' : 'Permission count',
            value: account.isSuperAdmin
                ? (isAr ? '∞ (مَسؤول عام)' : '∞ (super admin)')
                : '${permKeys.length}',
            icon: Icons.vpn_key),
      ],
    );
  }
}

// ============================================================
// قِسم: الموظَّف المَربوط
// ============================================================
class _EmployeeLinkSection extends StatelessWidget {
  final AppAccount account;
  const _EmployeeLinkSection({required this.account});

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final repo = MockRepository();
    Employee? emp;
    if (account.employeeId != null) {
      try {
        emp = repo.employees.firstWhere((e) => e.id == account.employeeId);
      } catch (_) {
        emp = null;
      }
    }
    return _Section(
      icon: Icons.badge_outlined,
      titleAr: 'المُوظَّف المَربوط',
      titleEn: 'Linked Employee',
      color: AppColors.brand,
      children: [
        if (emp == null)
          Text(
            isAr
                ? 'هَذا الحِساب غَير مَربوط بِسِجِلّ مُوظَّف.'
                : 'This account is not linked to an employee record.',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          )
        else ...[
          _Row(
              label: isAr ? 'الرَقم الوَظيفيّ' : 'Code',
              value: emp.code,
              icon: Icons.tag),
          _Row(
              label: isAr ? 'الاسم' : 'Name',
              value: emp.fullName,
              icon: Icons.person_outline),
          _Row(
              label: isAr ? 'المُسَمّى' : 'Job title',
              value:
                  emp.jobTitle.isEmpty ? '—' : emp.jobTitle,
              icon: Icons.work_outline),
          _Row(
              label: isAr ? 'الحالة' : 'Status',
              value: emp.status == EntityStatus.active
                  ? (isAr ? 'نَشِط' : 'Active')
                  : (isAr ? 'مُعَطَّل' : 'Inactive'),
              color: emp.status == EntityStatus.active
                  ? AppColors.success
                  : Colors.red,
              icon: emp.status == EntityStatus.active
                  ? Icons.check_circle
                  : Icons.cancel),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => EmployeeProfileHub(employee: emp!),
              ));
            },
            icon: const Icon(Icons.open_in_new),
            label: Text(isAr ? 'فَتح مَلَفّ المُوظَّف' : 'Open Employee Profile'),
          ),
        ],
      ],
    );
  }
}

// ============================================================
// قِسم: بَصمة الوَجه
// ============================================================
class _FaceSection extends StatelessWidget {
  final AppAccount account;
  final bool hasFace;
  final int count;
  final DateTime? lastEnrolledAt;
  const _FaceSection({
    required this.account,
    required this.hasFace,
    required this.count,
    this.lastEnrolledAt,
  });

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final repo = MockRepository();
    final empId = account.employeeId;
    Employee? emp;
    if (empId != null) {
      try {
        emp = repo.employees.firstWhere((e) => e.id == empId);
      } catch (_) {
        emp = null;
      }
    }
    return _Section(
      icon: Icons.face_retouching_natural,
      titleAr: 'بَصمة الوَجه',
      titleEn: 'Face Biometric',
      color: Colors.deepOrange,
      children: [
        _Row(
            label: isAr ? 'الحالة' : 'Status',
            value: hasFace
                ? (isAr ? 'مُسَجَّلة' : 'Enrolled')
                : (isAr ? 'غَير مُسَجَّلة' : 'Not enrolled'),
            color: hasFace ? AppColors.success : Colors.orange,
            icon: hasFace ? Icons.check_circle : Icons.warning_amber),
        _Row(
            label: isAr ? 'عَدَد الالتِقاطات' : 'Captures',
            value: '$count / 5',
            icon: Icons.collections),
        _Row(
            label: isAr ? 'آخِر تَسجيل' : 'Last enrolled',
            value: _fmtDate(lastEnrolledAt, withTime: true),
            icon: Icons.event),
        _Row(
            label: isAr ? 'إلزام التَسجيل' : 'Enrollment required',
            value: account.mustEnrollFace
                ? (isAr ? 'نَعَم' : 'Yes')
                : (isAr ? 'لا' : 'No'),
            color: account.mustEnrollFace ? Colors.orange : Colors.grey,
            icon: Icons.policy_outlined),
        if (account.faceEnrolledAt != null)
          _Row(
              label: isAr ? 'اكتَمَل في' : 'Completed at',
              value: _fmtDate(account.faceEnrolledAt, withTime: true),
              icon: Icons.verified),
        const SizedBox(height: 8),
        if (emp != null)
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => FaceEnrollmentScreen(employee: emp!),
              ));
            },
            icon: const Icon(Icons.face),
            label: Text(hasFace
                ? (isAr ? 'إعادة تَسجيل البَصمة' : 'Re-enroll Face')
                : (isAr ? 'تَسجيل بَصمة الوَجه' : 'Enroll Face')),
            style: FilledButton.styleFrom(
                backgroundColor: Colors.deepOrange,
                foregroundColor: Colors.white),
          )
        else
          Text(
            isAr
                ? 'هَذا الحِساب غَير مَربوط بِمُوظَّف — لا يُمكِن تَسجيل بَصمة.'
                : 'Account not linked to an employee — face enrollment unavailable.',
            style: const TextStyle(color: Colors.grey, fontSize: 11),
          ),
      ],
    );
  }
}

// ============================================================
// قِسم: الجَلسات وَالأَجهِزة
// ============================================================
class _SessionsSection extends StatelessWidget {
  final AppAccount account;
  final int active;
  final int total;
  final List<_SessionRow> sessions;
  const _SessionsSection({
    required this.account,
    required this.active,
    required this.total,
    required this.sessions,
  });

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final auth = context.read<AuthProvider>();
    final canManage = auth.isSuperAdmin ||
        auth.permissions.contains(P.pointTerminalManage);
    return _Section(
      icon: Icons.devices_other,
      titleAr: 'الجَلسات وَالأَجهِزة',
      titleEn: 'Sessions & Devices',
      color: AppColors.gold,
      children: [
        _Row(
            label: isAr ? 'جَلسات نَشِطة' : 'Active sessions',
            value: '$active',
            color: active > 0 ? AppColors.success : Colors.grey,
            icon: Icons.bolt),
        _Row(
            label: isAr ? 'إجمالي الجَلسات' : 'Total sessions',
            value: '$total',
            icon: Icons.history),
        if (account.isPointTerminal)
          _Row(
              label: isAr ? 'حَدّ الأَجهِزة' : 'Device limit',
              value: account.maxDevices == 0
                  ? (isAr ? 'بِدون حَدّ' : 'Unlimited')
                  : '${account.maxDevices}',
              icon: Icons.numbers),
        const SizedBox(height: 8),
        if (sessions.isEmpty)
          Text(isAr ? 'لا تُوجَد جَلسات.' : 'No sessions.',
              style: const TextStyle(color: Colors.grey, fontSize: 12))
        else
          ...sessions.take(5).map((s) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                        s.isActive
                            ? Icons.fiber_manual_record
                            : Icons.fiber_manual_record_outlined,
                        color: s.isActive ? AppColors.success : Colors.grey,
                        size: 12),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        s.deviceLabel ?? s.deviceName ?? s.deviceId,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      _fmtDate(s.lastSeenAt, withTime: true),
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 10),
                    ),
                  ],
                ),
              )),
        if (sessions.length > 5)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              isAr
                  ? '… وَ ${sessions.length - 5} جَلسة إضافيّة'
                  : '… and ${sessions.length - 5} more',
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ),
        if (sessions.isNotEmpty && canManage) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const TerminalSessionsScreen(),
              ));
            },
            icon: const Icon(Icons.open_in_new),
            label: Text(isAr
                ? 'فَتح إدارة الجَلسات'
                : 'Open Sessions Manager'),
          ),
        ],
      ],
    );
  }
}

// ============================================================
// قِسم: النَشاط
// ============================================================
class _ActivitySection extends StatelessWidget {
  final AppAccount account;
  final int notificationsTotal;
  final int notificationsUnread;
  const _ActivitySection({
    required this.account,
    required this.notificationsTotal,
    required this.notificationsUnread,
  });

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final ageDays = DateTime.now().difference(account.createdAt).inDays;
    final inactiveDays = account.lastLoginAt == null
        ? null
        : DateTime.now().difference(account.lastLoginAt!).inDays;
    return _Section(
      icon: Icons.insights,
      titleAr: 'النَشاط',
      titleEn: 'Activity',
      color: Colors.teal,
      children: [
        _Row(
            label: isAr ? 'عُمر الحِساب' : 'Account age',
            value: isAr ? '$ageDays يَوم' : '$ageDays days',
            icon: Icons.timelapse),
        _Row(
            label: isAr ? 'الخُمول مُنذ' : 'Idle since',
            value: inactiveDays == null
                ? (isAr ? 'لَم يَدخُل أَبَداً' : 'Never logged in')
                : (isAr ? '$inactiveDays يَوم' : '$inactiveDays days'),
            color: inactiveDays != null && inactiveDays > 30
                ? Colors.orange
                : null,
            icon: Icons.hourglass_empty),
        _Row(
            label: isAr ? 'الإشعارات' : 'Notifications',
            value: '$notificationsTotal'
                '${notificationsUnread > 0 ? ' ($notificationsUnread '
                    '${isAr ? "غَير مَقروء" : "unread"})' : ''}',
            color: notificationsUnread > 0 ? AppColors.info : null,
            icon: Icons.notifications_outlined),
      ],
    );
  }
}

// ============================================================
// نَموذج صَفّ جَلسة مُبَسَّط
// ============================================================
class _SessionRow {
  final String id;
  final String deviceId;
  final String? deviceName;
  final String? deviceLabel;
  final bool isActive;
  final DateTime? firstLoginAt;
  final DateTime? lastSeenAt;
  const _SessionRow({
    required this.id,
    required this.deviceId,
    this.deviceName,
    this.deviceLabel,
    required this.isActive,
    this.firstLoginAt,
    this.lastSeenAt,
  });

  factory _SessionRow.fromMap(Map<String, dynamic> m) {
    DateTime? parse(dynamic v) =>
        v == null ? null : DateTime.tryParse(v.toString());
    return _SessionRow(
      id: m['id']?.toString() ?? '',
      deviceId: m['device_id']?.toString() ?? '',
      deviceName: m['device_name']?.toString(),
      deviceLabel: m['device_label']?.toString(),
      isActive: m['is_active'] == true,
      firstLoginAt: parse(m['first_login_at']),
      lastSeenAt: parse(m['last_seen_at']),
    );
  }
}
