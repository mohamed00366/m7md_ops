import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/lookups.dart';
import '../../models/models.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';
import 'department_profile_screen.dart';
import 'job_title_profile_screen.dart';

/// 👤 شاشة "ملفّ موظف" (Employee Profile Inspector)
///
/// الـ third inspector بعد JobTitleProfile و DepartmentProfile.
/// تعرض كلّ ما يخصّ موظفاً واحداً:
///   - بطاقة Hero بمعلوماته الأساسيّة
///   - مسمّاه الوظيفي (مع رابط للملفّ)
///   - قسمه (مع رابط للملفّ)
///   - الحساب المرتبط (إن وُجد)
///   - dashboard الذي سيراه (محسوب من JobTitle)
///   - الصلاحيّات الفعليّة المحسوبة
///   - الطلبات (Forms) المُقدَّمة منه
///   - زرّ "العرض كحساب" مباشر
class EmployeeProfileScreen extends StatefulWidget {
  final Employee employee;
  const EmployeeProfileScreen({super.key, required this.employee});

  @override
  State<EmployeeProfileScreen> createState() => _EmployeeProfileScreenState();
}

class _EmployeeProfileScreenState extends State<EmployeeProfileScreen> {
  @override
  void initState() {
    super.initState();
    MockRepository().addListener(_onChange);
  }

  @override
  void dispose() {
    MockRepository().removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final isAr = s.isAr;
    final emp = widget.employee;

    final jt = emp.jobTitleId == null
        ? null
        : repo.jobTitleById(emp.jobTitleId);
    final dept = emp.departmentId == null
        ? null
        : repo.departments.firstWhere(
            (d) => d.id == emp.departmentId,
            orElse: () => Department(id: '', nameAr: '', nameEn: ''),
          );
    final account = repo.accountForEmployee(emp.id);
    final country = emp.countryId == null
        ? null
        : repo.countryById(emp.countryId!);

    // الصلاحيّات الفعليّة
    final permissions = jt?.roleId == null
        ? <String>{}
        : repo.permissionKeysForRole(jt!.roleId!);

    // الطلبات المُقدَّمة
    final submissions = repo.formSubmissions
        .where((sub) => sub.employeeId == emp.id)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final pendingCount = submissions
        .where((sub) =>
            sub.status == FormSubmissionStatus.submitted ||
            sub.status == FormSubmissionStatus.inReview)
        .length;
    final approvedCount = submissions
        .where((sub) => sub.status == FormSubmissionStatus.approved)
        .length;
    final rejectedCount = submissions
        .where((sub) => sub.status == FormSubmissionStatus.rejected)
        .length;

    final color = jt?.color == null
        ? AppColors.brand
        : (_hexToColor(jt!.color) ?? AppColors.brand);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: color,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              emp.fullName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              emp.code,
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
        actions: [
          // 🆕 زرّ العرض كحساب (مباشر من ملفّ الموظف)
          if (account != null)
            Builder(builder: (ctx) {
              final auth = ctx.watch<AuthProvider>();
              if (!auth.isSuperAdmin) return const SizedBox.shrink();
              return IconButton(
                tooltip: isAr ? 'العرض كهذا الموظف' : 'Impersonate',
                icon: const Icon(Icons.theater_comedy_outlined),
                onPressed: () => _confirmImpersonate(ctx, account),
              );
            }),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // ===== Hero =====
          _EmpHero(
              employee: emp,
              jobTitle: jt,
              color: color,
              account: account,
              country: country,
              isAr: isAr),
          const SizedBox(height: 12),

          // ===== KPIs =====
          Row(
            children: [
              Expanded(
                child: _Kpi(
                  icon: Icons.shield_outlined,
                  label: isAr ? 'صلاحيّات' : 'Permissions',
                  value: '${permissions.length}',
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _Kpi(
                  icon: Icons.pending_actions,
                  label: isAr ? 'بانتظار' : 'Pending',
                  value: '$pendingCount',
                  color: AppColors.warning,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _Kpi(
                  icon: Icons.check_circle_outline,
                  label: isAr ? 'معتمدة' : 'Approved',
                  value: '$approvedCount',
                  color: AppColors.brand,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _Kpi(
                  icon: Icons.cancel_outlined,
                  label: isAr ? 'مرفوضة' : 'Rejected',
                  value: '$rejectedCount',
                  color: AppColors.danger,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ===== Linked Job Title =====
          _Section(
            title: isAr ? '👤 المسمّى الوظيفي' : '👤 Job Title',
            child: jt == null
                ? Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppColors.danger.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_outlined,
                            color: AppColors.danger, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            isAr
                                ? 'لا يوجد مسمّى وظيفي — لن يحصل على dashboard أو صلاحيّات'
                                : 'No job title — no dashboard or permissions',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.danger,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : InkWell(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => JobTitleProfileScreen(jobTitle: jt),
                    )),
                    borderRadius: BorderRadius.circular(8),
                    child: _JobTitleRow(jobTitle: jt, isAr: isAr),
                  ),
          ),
          const SizedBox(height: 12),

          // ===== Linked Department =====
          if (dept != null && dept.id.isNotEmpty)
            Column(
              children: [
                _Section(
                  title: isAr ? '🏢 القسم' : '🏢 Department',
                  child: InkWell(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) =>
                          DepartmentProfileScreen(department: dept),
                    )),
                    borderRadius: BorderRadius.circular(8),
                    child: _DeptRow(department: dept, isAr: isAr),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),

          // ===== Account =====
          _Section(
            title: isAr ? '🔑 الحساب' : '🔑 Account',
            child: account == null
                ? Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.withOpacity(0.3)),
                    ),
                    child: Text(
                      isAr
                          ? 'لا يوجد حساب مرتبط (الموظف لا يستطيع تسجيل الدخول)'
                          : 'No linked account (cannot log in)',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                  )
                : Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppColors.success.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_outline,
                            color: AppColors.success, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '@${account.username}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.success,
                                  fontWeight: FontWeight.w800,
                                  fontFamily: 'monospace',
                                ),
                              ),
                              Text(
                                isAr
                                    ? account.isActive
                                        ? '✅ نشط'
                                        : '⏸️ معطّل'
                                    : account.isActive
                                        ? '✅ Active'
                                        : '⏸️ Disabled',
                                style: const TextStyle(fontSize: 10.5),
                              ),
                            ],
                          ),
                        ),
                        if (account.isSuperAdmin)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Super Admin',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 12),

          // ===== Permissions summary =====
          _Section(
            title: isAr ? '🛡️ الصلاحيّات الفعليّة' : '🛡️ Effective Permissions',
            child: permissions.isEmpty
                ? Text(
                    isAr ? 'لا توجد' : 'None',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  )
                : _permissionsByModule(permissions),
          ),
          const SizedBox(height: 12),

          // ===== Recent submissions =====
          if (submissions.isNotEmpty)
            _Section(
              title: isAr
                  ? '📑 آخر الطلبات (${submissions.length})'
                  : '📑 Recent Submissions (${submissions.length})',
              child: Column(
                children: submissions
                    .take(5)
                    .map((sub) => _SubmissionRow(submission: sub, isAr: isAr))
                    .toList(),
              ),
            ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _permissionsByModule(Set<String> keys) {
    final byModule = <String, int>{};
    for (final k in keys) {
      final mod = k.split('.').first;
      byModule[mod] = (byModule[mod] ?? 0) + 1;
    }
    final sortedModules = byModule.keys.toList()
      ..sort((a, b) => byModule[b]!.compareTo(byModule[a]!));
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: sortedModules
          .map((m) => Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: AppColors.success.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      m,
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.success,
                          fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.success,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${byModule[m]}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
              ))
          .toList(),
    );
  }

  Future<void> _confirmImpersonate(
      BuildContext context, AppAccount account) async {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isAr ? '🎭 العرض كحساب' : '🎭 Impersonate'),
        content: Text(
          isAr
              ? 'سترى التطبيق بصلاحيّات ${account.fullName}.'
              : 'You\'ll see the app as ${account.fullName}.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isAr ? 'متابعة' : 'Continue'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!context.mounted) return;
    final auth = context.read<AuthProvider>();
    auth.startImpersonate(account.id);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  static Color? _hexToColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    final s = hex.replaceAll('#', '');
    try {
      return Color(int.parse('FF$s', radix: 16));
    } catch (_) {
      return null;
    }
  }
}

// ============================================================
// Helpers
// ============================================================

class _EmpHero extends StatelessWidget {
  final Employee employee;
  final JobTitle? jobTitle;
  final Color color;
  final AppAccount? account;
  final dynamic country;
  final bool isAr;

  const _EmpHero({
    required this.employee,
    required this.jobTitle,
    required this.color,
    required this.account,
    required this.country,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withOpacity(0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: Colors.white.withOpacity(0.25),
            child: Text(
              employee.initials,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  employee.fullName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  employee.code,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    if (jobTitle != null)
                      _heroBadge(
                        icon: Icons.badge_outlined,
                        text: jobTitle!.displayName(isAr),
                      ),
                    if (jobTitle != null && jobTitle!.level > 0)
                      _heroBadge(text: 'L${jobTitle!.level}'),
                    if (jobTitle != null)
                      _heroBadge(
                        icon: Icons.dashboard_outlined,
                        text: jobTitle!.dashboardType.label(isAr),
                      ),
                    if (country != null)
                      _heroBadge(
                        icon: Icons.public,
                        text: isAr ? country.nameAr : country.nameEn,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroBadge({IconData? icon, required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.25),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: Colors.white),
            const SizedBox(width: 3),
          ],
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _Kpi({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 13),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _JobTitleRow extends StatelessWidget {
  final JobTitle jobTitle;
  final bool isAr;
  const _JobTitleRow({required this.jobTitle, required this.isAr});

  @override
  Widget build(BuildContext context) {
    final color = jobTitle.color == null
        ? AppColors.brand
        : (_hex(jobTitle.color!) ?? AppColors.brand);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 36,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  jobTitle.displayName(isAr),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800),
                ),
                Text(
                  isAr
                      ? '${jobTitle.dashboardType.label(true)} • قوّة ${jobTitle.approvalPower}/5'
                      : '${jobTitle.dashboardType.label(false)} • Power ${jobTitle.approvalPower}/5',
                  style: const TextStyle(fontSize: 10.5, color: Colors.grey),
                ),
              ],
            ),
          ),
          if (jobTitle.level > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'L${jobTitle.level}',
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          const SizedBox(width: 4),
          Icon(Icons.arrow_forward_ios,
              size: 11, color: color.withOpacity(0.5)),
        ],
      ),
    );
  }

  static Color? _hex(String hex) {
    final s = hex.replaceAll('#', '');
    try {
      return Color(int.parse('FF$s', radix: 16));
    } catch (_) {
      return null;
    }
  }
}

class _DeptRow extends StatelessWidget {
  final Department department;
  final bool isAr;
  const _DeptRow({required this.department, required this.isAr});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.brand.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.brand.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.apartment_outlined,
              color: AppColors.brand, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              department.displayName(isAr),
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800),
            ),
          ),
          if (department.level > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.brand.withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'L${department.level}',
                style: const TextStyle(
                  color: AppColors.brand,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          const SizedBox(width: 4),
          Icon(Icons.arrow_forward_ios,
              size: 11, color: AppColors.brand.withOpacity(0.5)),
        ],
      ),
    );
  }
}

class _SubmissionRow extends StatelessWidget {
  final FormSubmission submission;
  final bool isAr;
  const _SubmissionRow({required this.submission, required this.isAr});

  @override
  Widget build(BuildContext context) {
    final repo = MockRepository();
    final tpl = repo.formTemplateById(submission.templateId);
    final color = submission.status == FormSubmissionStatus.approved
        ? AppColors.success
        : submission.status == FormSubmissionStatus.rejected
            ? AppColors.danger
            : AppColors.warning;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              submission.formNo.isEmpty ? '—' : submission.formNo,
              style: TextStyle(
                fontSize: 9,
                color: color,
                fontWeight: FontWeight.w900,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tpl == null ? '?' : (isAr ? tpl.nameAr : tpl.nameEn),
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
          Text(
            submission.status.label(isAr),
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
