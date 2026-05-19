import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/supabase_data_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/services/workflow_engine.dart';
import '../../core/theme/app_colors.dart';
import '../../models/lookups.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';
import 'approval_matrix_screen.dart';
import 'bulk_permissions_matrix_screen.dart';
import 'org_builder_screen.dart';
import 'organization_chart_screen.dart';
import 'admin_users.dart';

/// 🩺 لوحة صحّة النظام (System Health Dashboard)
///
/// نظرة تنفيذيّة شاملة على صحّة الإعدادات والصلاحيّات والهرم:
///   - 📊 KPIs أساسيّة (مسمّيات، أقسام، حسابات، صلاحيّات)
///   - ⚠️ كاشف فجوات شامل (مسمّيات يتيمة، مُوافِقون بدون صلاحيّة، حسابات بدون موظف)
///   - ❤️ مؤشّر صحّة عامّ (0..100%)
///   - 🔗 روابط سريعة لشاشات الإصلاح
class SystemHealthScreen extends StatefulWidget {
  const SystemHealthScreen({super.key});

  @override
  State<SystemHealthScreen> createState() => _SystemHealthScreenState();
}

class _SystemHealthScreenState extends State<SystemHealthScreen> {
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
    final isAr = s.isAr;
    final h = _Health.compute();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // ===== 🆕 صيانة: رفع الصلاحيّات الجديدة إلى Supabase =====
        _SyncSeedPermissionsCard(isAr: isAr),
        const SizedBox(height: 14),

        // ===== Health score banner =====
        _HealthScoreBanner(score: h.healthScore, isAr: isAr),
        const SizedBox(height: 14),

        // ===== KPIs Grid =====
        Text(
          isAr ? '📊 إحصاءات أساسيّة' : '📊 Key Metrics',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          childAspectRatio: 2.4,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: [
            _HealthCard(
              icon: Icons.apartment_outlined,
              label: isAr ? 'الأقسام' : 'Departments',
              value: '${h.departments}',
              detail: isAr
                  ? '${h.rootDepartments} جذور / ${h.nestedDepartments} فرعيّة'
                  : '${h.rootDepartments} root / ${h.nestedDepartments} nested',
              color: AppColors.brand,
            ),
            _HealthCard(
              icon: Icons.badge_outlined,
              label: isAr ? 'المسمّيات' : 'Job Titles',
              value: '${h.jobTitles}',
              detail: isAr
                  ? '${h.jobTitlesWithRole} لها دور'
                  : '${h.jobTitlesWithRole} with role',
              color: AppColors.info,
            ),
            _HealthCard(
              icon: Icons.people_outline,
              label: isAr ? 'الموظفون' : 'Employees',
              value: '${h.employees}',
              detail: isAr
                  ? '${h.employeesActive} نشط'
                  : '${h.employeesActive} active',
              color: AppColors.success,
            ),
            _HealthCard(
              icon: Icons.account_circle_outlined,
              label: isAr ? 'الحسابات' : 'Accounts',
              value: '${h.accounts}',
              detail: isAr
                  ? '${h.linkedAccounts} مرتبط بموظف'
                  : '${h.linkedAccounts} linked',
              color: AppColors.purple,
            ),
            _HealthCard(
              icon: Icons.shield_outlined,
              label: isAr ? 'الأدوار' : 'Roles',
              value: '${h.roles}',
              detail: isAr
                  ? '${h.permissionsCount} صلاحيّة معرَّفة'
                  : '${h.permissionsCount} perms defined',
              color: AppColors.gold,
            ),
            _HealthCard(
              icon: Icons.verified_outlined,
              label: isAr ? 'مُوافِقون' : 'Approvers',
              value: '${h.approvers}',
              detail: isAr
                  ? '${h.workflowTemplates} قوالب موافقة'
                  : '${h.workflowTemplates} workflows',
              color: AppColors.teal,
            ),
          ],
        ),
        const SizedBox(height: 14),

        // ===== 🆕 Session 18: Activity Charts =====
        const _ActivityChartsCard(),
        const SizedBox(height: 14),

        // ===== 🆕 Session 12: Recent Activity =====
        const _RecentActivityCard(),
        const SizedBox(height: 14),

        // ===== Issue Categories =====
        Text(
          isAr ? '⚠️ مكشف الفجوات' : '⚠️ Issue Detector',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),

        _IssueCategory(
          title: isAr ? 'الهرم التنظيمي' : 'Org Hierarchy',
          icon: Icons.account_tree_outlined,
          color: AppColors.brand,
          issues: [
            if (h.orphanJobTitles > 0)
              _Issue(
                severity: _Severity.warning,
                titleAr: '${h.orphanJobTitles} مسمّيات أيتام',
                titleEn: '${h.orphanJobTitles} orphan job titles',
                detailAr: 'مستوى > 1 لكنّها لا تتبع لأحد',
                detailEn: 'Level > 1 but report to no one',
                onFix: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const OrgBuilderScreen(),
                )),
              ),
            if (h.orphanDepartments > 0)
              _Issue(
                severity: _Severity.info,
                titleAr: '${h.orphanDepartments} أقسام بدون أب',
                titleEn: '${h.orphanDepartments} root departments',
                detailAr: 'تأكّد أنّ هذا مقصود',
                detailEn: 'Make sure this is intended',
                onFix: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const OrganizationChartScreen(),
                )),
              ),
          ],
          isAr: isAr,
        ),

        _IssueCategory(
          title: isAr ? 'الصلاحيّات' : 'Permissions',
          icon: Icons.security_outlined,
          color: AppColors.danger,
          issues: [
            if (h.jobTitlesWithoutRole > 0)
              _Issue(
                severity: _Severity.warning,
                titleAr: '${h.jobTitlesWithoutRole} مسمّيات بدون دور',
                titleEn: '${h.jobTitlesWithoutRole} job titles without role',
                detailAr: 'حاملوها لن يملكوا أيّ صلاحيّة',
                detailEn: 'Holders will have no permissions',
                onFix: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const BulkPermissionsMatrixScreen(),
                )),
              ),
            if (h.approverWithoutPermission > 0)
              _Issue(
                severity: _Severity.critical,
                titleAr:
                    '${h.approverWithoutPermission} مُوافِقون بدون صلاحيّة موافقة',
                titleEn:
                    '${h.approverWithoutPermission} approvers missing approval permission',
                detailAr: 'لن يستطيعوا الموافقة فعليّاً',
                detailEn: 'Cannot actually approve in workflow',
                onFix: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const ApprovalMatrixScreen(),
                )),
              ),
            if (h.dashboardMismatches > 0)
              _Issue(
                severity: _Severity.info,
                titleAr: '${h.dashboardMismatches} تعارض dashboard',
                titleEn: '${h.dashboardMismatches} dashboard mismatches',
                detailAr: 'مسمّيات لوحة تحكمها لا تطابق صلاحيّاتها',
                detailEn: 'Dashboard type doesn\'t match permissions',
                onFix: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const ApprovalMatrixScreen(),
                )),
              ),
          ],
          isAr: isAr,
        ),

        _IssueCategory(
          title: isAr ? 'سير الموافقات' : 'Workflows',
          icon: Icons.assignment_outlined,
          color: AppColors.warning,
          issues: [
            if (h.brokenChains > 0)
              _Issue(
                severity: _Severity.critical,
                titleAr: '${h.brokenChains} سلسلة مكسورة',
                titleEn: '${h.brokenChains} broken workflow chains',
                detailAr: 'لن تكتمل لأيّ مُقدِّم',
                detailEn: 'Won\'t resolve for any submitter',
                onFix: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const ApprovalMatrixScreen(),
                )),
              ),
            if (h.partialChains > 0)
              _Issue(
                severity: _Severity.warning,
                titleAr: '${h.partialChains} سلسلة جزئيّة',
                titleEn: '${h.partialChains} partial chains',
                detailAr: 'تكتمل لبعض المُقدِّمين فقط',
                detailEn: 'Resolves only for some submitters',
                onFix: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const ApprovalMatrixScreen(),
                )),
              ),
          ],
          isAr: isAr,
        ),

        _IssueCategory(
          title: isAr ? 'الموظفون والحسابات' : 'Employees & Accounts',
          icon: Icons.people_alt_outlined,
          color: AppColors.purple,
          issues: [
            if (h.employeesWithoutJobTitle > 0)
              _Issue(
                severity: _Severity.warning,
                titleAr:
                    '${h.employeesWithoutJobTitle} موظفون بدون مسمّى وظيفي',
                titleEn:
                    '${h.employeesWithoutJobTitle} employees without job title',
                detailAr: 'لن يحصلوا على dashboard أو صلاحيّات',
                detailEn: 'No dashboard or permissions',
                // 🆕 افتَح شاشة المُوَظَّفين لِإصلاح كُلّ مُوَظَّف
                onFix: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const AdminUsers(),
                )),
              ),
            if (h.accountsWithoutEmployee > 0)
              _Issue(
                severity: _Severity.info,
                titleAr:
                    '${h.accountsWithoutEmployee} حسابات بدون موظف',
                titleEn:
                    '${h.accountsWithoutEmployee} accounts without employee',
                detailAr: 'حسابات نظام/إدارة بدون ربط',
                detailEn: 'System/admin accounts unlinked',
                onFix: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const AdminUsers(),
                )),
              ),
            if (h.employeesWithoutCountry > 0)
              _Issue(
                severity: _Severity.info,
                titleAr: '${h.employeesWithoutCountry} موظفون بدون دولة',
                titleEn:
                    '${h.employeesWithoutCountry} employees without country',
                detailAr: 'لن يظهروا بفلتر الدولة',
                detailEn: 'Won\'t show in country filters',
                onFix: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const AdminUsers(),
                )),
              ),
          ],
          isAr: isAr,
        ),
        const SizedBox(height: 30),
      ],
    );
  }
}

// ============================================================
// التحليل
// ============================================================

class _Health {
  final int departments;
  final int rootDepartments;
  final int nestedDepartments;
  final int jobTitles;
  final int jobTitlesWithRole;
  final int jobTitlesWithoutRole;
  final int orphanJobTitles;
  final int orphanDepartments;
  final int employees;
  final int employeesActive;
  final int employeesWithoutJobTitle;
  final int employeesWithoutCountry;
  final int accounts;
  final int linkedAccounts;
  final int accountsWithoutEmployee;
  final int roles;
  final int permissionsCount;
  final int approvers;
  final int approverWithoutPermission;
  final int dashboardMismatches;
  final int workflowTemplates;
  final int brokenChains;
  final int partialChains;

  /// المؤشّر العام (0..100)
  /// كل فجوة حرجة = -10، تحذير = -5، info = -1
  final double healthScore;

  _Health({
    required this.departments,
    required this.rootDepartments,
    required this.nestedDepartments,
    required this.jobTitles,
    required this.jobTitlesWithRole,
    required this.jobTitlesWithoutRole,
    required this.orphanJobTitles,
    required this.orphanDepartments,
    required this.employees,
    required this.employeesActive,
    required this.employeesWithoutJobTitle,
    required this.employeesWithoutCountry,
    required this.accounts,
    required this.linkedAccounts,
    required this.accountsWithoutEmployee,
    required this.roles,
    required this.permissionsCount,
    required this.approvers,
    required this.approverWithoutPermission,
    required this.dashboardMismatches,
    required this.workflowTemplates,
    required this.brokenChains,
    required this.partialChains,
    required this.healthScore,
  });

  static _Health compute() {
    final repo = MockRepository();
    final jts = repo.jobTitles;

    // Org hierarchy
    final rootDepts = repo.departments.where((d) => d.parentId == null).length;
    final nested = repo.departments.length - rootDepts;
    final orphanJobs = jts
        .where((j) => j.level > 1 && j.reportsToIds.isEmpty)
        .length;

    // Permissions
    final withRole = jts.where((j) => j.roleId != null).length;
    var approverWithoutPerm = 0;
    var dashMismatch = 0;
    const approvalPermissions = {
      'rosters.approve',
      'rosters.reject',
      'camp.violations.approve',
    };
    for (final jt in jts) {
      if (jt.approvalPower > 0 && jt.roleId != null) {
        final perms = repo.permissionKeysForRole(jt.roleId!);
        if (!perms.any(approvalPermissions.contains)) {
          approverWithoutPerm++;
        }
      }
      if (jt.dashboardType != DashboardType.employee && jt.roleId != null) {
        final perms = repo.permissionKeysForRole(jt.roleId!);
        bool ok = true;
        switch (jt.dashboardType) {
          case DashboardType.manager:
            ok = perms.any((p) =>
                p.startsWith('reports.') ||
                p == 'employees.view' ||
                p == 'rosters.view');
            break;
          case DashboardType.supervisor:
            ok = perms.any((p) =>
                p == 'rosters.approve' ||
                p == 'camp.checklist.create' ||
                p.startsWith('evaluation'));
            break;
          case DashboardType.hr:
            ok = perms.any(
                (p) => p == 'employees.view' || p == 'employees.create');
            break;
          case DashboardType.finance:
            ok = perms.contains('reports.view') ||
                perms.contains('reports.export');
            break;
          case DashboardType.driver:
            ok = perms.contains('driver.trips.view');
            break;
          case DashboardType.operations:
            ok = perms.any((p) => p.startsWith('rosters.'));
            break;
          case DashboardType.employee:
            break;
        }
        if (!ok) dashMismatch++;
      }
    }

    // Workflows
    var broken = 0;
    var partial = 0;
    final workers = jts.where((j) => j.level == 5).toList();
    final samples = workers.isEmpty ? jts : workers;
    for (final tpl in repo.formTemplates) {
      var fully = 0;
      var brokenS = 0;
      var partialS = 0;
      for (final sample in samples) {
        final chain = WorkflowEngine.previewChain(
          template: tpl,
          sampleSubmitterJobTitleId: sample.id,
        );
        final unresolved =
            chain.where((c) => c.match?.isResolved != true).length;
        if (unresolved == 0) {
          fully++;
        } else if (unresolved < chain.length) {
          partialS++;
        } else {
          brokenS++;
        }
      }
      if (samples.isNotEmpty && brokenS == samples.length) {
        broken++;
      } else if (partialS > 0) {
        partial++;
      }
    }

    // Employees / Accounts
    final empsActive =
        repo.employees.where((e) => e.status.toString().contains('active')).length;
    final empsNoJob = repo.employees.where((e) => e.jobTitleId == null).length;
    final empsNoCountry =
        repo.employees.where((e) => e.countryId == null).length;
    final accountsLinked =
        repo.accounts.where((a) => a.employeeId != null).length;
    final accountsUnlinked = repo.accounts.length - accountsLinked;

    // Approvers count
    final approvers = jts.where((j) => j.approvalPower > 0).length;

    // Health score
    var penalty = 0.0;
    penalty += broken * 10;
    penalty += approverWithoutPerm * 8;
    penalty += orphanJobs * 5;
    penalty += partial * 4;
    penalty += (jts.length - withRole) * 2;
    penalty += dashMismatch * 1;
    penalty += empsNoJob * 0.5;
    final score = (100 - penalty).clamp(0, 100).toDouble();

    return _Health(
      departments: repo.departments.length,
      rootDepartments: rootDepts,
      nestedDepartments: nested,
      jobTitles: jts.length,
      jobTitlesWithRole: withRole,
      jobTitlesWithoutRole: jts.length - withRole,
      orphanJobTitles: orphanJobs,
      orphanDepartments: rootDepts > 1 ? rootDepts - 1 : 0,
      employees: repo.employees.length,
      employeesActive: empsActive,
      employeesWithoutJobTitle: empsNoJob,
      employeesWithoutCountry: empsNoCountry,
      accounts: repo.accounts.length,
      linkedAccounts: accountsLinked,
      accountsWithoutEmployee: accountsUnlinked,
      roles: repo.roleDefs.length,
      permissionsCount: repo.permissionDefs.length,
      approvers: approvers,
      approverWithoutPermission: approverWithoutPerm,
      dashboardMismatches: dashMismatch,
      workflowTemplates: repo.formTemplates.length,
      brokenChains: broken,
      partialChains: partial,
      healthScore: score,
    );
  }
}

// ============================================================
// Widgets
// ============================================================

/// 🆕 بطاقة رفع الصلاحيّات الجديدة من الـ seed المحلّي إلى Supabase.
///
/// كلّما أضاف المطوّر مفاتيح جديدة في `rbac_seed.dart`، يضغط هذا الزرّ
/// لإدراجها في جدول `permissions` على السيرفر — تُتجاهل الموجودة مسبقاً.
class _SyncSeedPermissionsCard extends StatefulWidget {
  final bool isAr;
  const _SyncSeedPermissionsCard({required this.isAr});

  @override
  State<_SyncSeedPermissionsCard> createState() =>
      _SyncSeedPermissionsCardState();
}

class _SyncSeedPermissionsCardState extends State<_SyncSeedPermissionsCard> {
  bool _busy = false;
  String? _resultMsg;
  Color _resultColor = AppColors.success;

  Future<void> _push() async {
    if (!SupabaseService().isReady) {
      setState(() {
        _resultMsg = widget.isAr
            ? 'Supabase غير متّصل — لا يمكن الرفع'
            : 'Supabase not connected — cannot push';
        _resultColor = AppColors.danger;
      });
      return;
    }

    setState(() {
      _busy = true;
      _resultMsg = null;
    });

    final result = await SupabaseDataService().pushSeedPermissionsToSupabase();

    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result.error != null) {
        _resultMsg = widget.isAr
            ? 'فشل: ${result.error}'
            : 'Failed: ${result.error}';
        _resultColor = AppColors.danger;
      } else if (result.added == 0) {
        _resultMsg = widget.isAr
            ? '✅ كلّ الصلاحيّات موجودة (${result.skipped} مفتاحاً)'
            : '✅ All perms present (${result.skipped} keys)';
        _resultColor = AppColors.info;
      } else {
        _resultMsg = widget.isAr
            ? '🎉 تمّت إضافة ${result.added} صلاحيّة جديدة (${result.skipped} كانت موجودة)'
            : '🎉 Added ${result.added} new perms (${result.skipped} existed)';
        _resultColor = AppColors.success;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.brand.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.brand.withOpacity(0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cloud_upload_outlined,
                  color: AppColors.brand, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.isAr
                      ? '🔄 رفع الصلاحيّات الجديدة إلى Supabase'
                      : '🔄 Push new permissions to Supabase',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            widget.isAr
                ? 'يُقارن الصلاحيّات في الـ seed المحلّي مع جدول السيرفر، ويُدرج المفاتيح الناقصة فقط (لا يحذف ولا يُحدّث الموجود).'
                : 'Compares local seed against the server table and inserts only missing keys (no deletes, no updates).',
            style: const TextStyle(fontSize: 11),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: _busy ? null : _push,
                icon: _busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.upload_file, size: 16),
                label: Text(
                  _busy
                      ? (widget.isAr ? 'جارٍ الرفع...' : 'Pushing...')
                      : (widget.isAr ? 'ابدأ الرفع' : 'Push now'),
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 12),
              if (_resultMsg != null)
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _resultColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _resultMsg!,
                      style: TextStyle(
                        color: _resultColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HealthScoreBanner extends StatelessWidget {
  final double score;
  final bool isAr;
  const _HealthScoreBanner({required this.score, required this.isAr});

  @override
  Widget build(BuildContext context) {
    final color = score >= 80
        ? AppColors.success
        : (score >= 50 ? AppColors.warning : AppColors.danger);
    final emoji = score >= 80 ? '🟢' : (score >= 50 ? '🟡' : '🔴');
    final label = score >= 80
        ? (isAr ? 'صحّيّ' : 'Healthy')
        : (score >= 50 ? (isAr ? 'يحتاج اهتمام' : 'Needs attention') : (isAr ? 'حرج' : 'Critical'));

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
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 64,
                height: 64,
                child: CircularProgressIndicator(
                  value: score / 100,
                  strokeWidth: 6,
                  backgroundColor: Colors.white.withOpacity(0.25),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              Text(
                score.toStringAsFixed(0),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAr ? 'صحّة النظام' : 'System Health',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      emoji,
                      style: const TextStyle(fontSize: 18),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  isAr
                      ? 'النتيجة محسوبة من الفجوات والتعارضات'
                      : 'Score derived from gaps and mismatches',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HealthCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final Color color;
  const _HealthCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.18),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 9.5,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _Severity { info, warning, critical }

class _Issue {
  final _Severity severity;
  final String titleAr;
  final String titleEn;
  final String detailAr;
  final String detailEn;
  final VoidCallback? onFix;
  _Issue({
    required this.severity,
    required this.titleAr,
    required this.titleEn,
    required this.detailAr,
    required this.detailEn,
    this.onFix,
  });
}

class _IssueCategory extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<_Issue> issues;
  final bool isAr;

  const _IssueCategory({
    required this.title,
    required this.icon,
    required this.color,
    required this.issues,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    if (issues.isEmpty) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.success.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.success.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline,
                color: AppColors.success, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isAr ? '$title — لا توجد فجوات' : '$title — All clear',
                style: const TextStyle(
                  color: AppColors.success,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isAr ? '${issues.length} فجوة' : '${issues.length} issues',
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final i in issues) _IssueRow(issue: i, isAr: isAr),
        ],
      ),
    );
  }
}

class _IssueRow extends StatelessWidget {
  final _Issue issue;
  final bool isAr;
  const _IssueRow({required this.issue, required this.isAr});

  @override
  Widget build(BuildContext context) {
    final color = issue.severity == _Severity.critical
        ? AppColors.danger
        : issue.severity == _Severity.warning
            ? AppColors.warning
            : AppColors.info;
    return InkWell(
      onTap: issue.onFix,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Row(
          children: [
            Icon(
              issue.severity == _Severity.critical
                  ? Icons.error_outline
                  : issue.severity == _Severity.warning
                      ? Icons.warning_amber_outlined
                      : Icons.info_outline,
              color: color,
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isAr ? issue.titleAr : issue.titleEn,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    isAr ? issue.detailAr : issue.detailEn,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            if (issue.onFix != null)
              Icon(Icons.arrow_forward_ios,
                  color: color.withOpacity(0.6), size: 12),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 🆕 Session 12: Recent Activity Card
// ============================================================
class _RecentActivityCard extends StatelessWidget {
  const _RecentActivityCard();

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final repo = MockRepository();
    final entries = repo.auditLog.toList()
      ..sort((a, b) => b.at.compareTo(a.at));
    final recent = entries.take(8).toList();

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
          Row(
            children: [
              const Icon(Icons.history, color: AppColors.brand, size: 18),
              const SizedBox(width: 6),
              Text(
                isAr ? '🕒 آخر النشاطات' : '🕒 Recent Activity',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.brand.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isAr ? '${entries.length} سجل' : '${entries.length} entries',
                  style: const TextStyle(
                    color: AppColors.brand,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (recent.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                isAr
                    ? 'لا توجد نشاطات بعد. ستظهر هنا أيّ تعديلات على الإعدادات أو الموافقات.'
                    : 'No activity yet. Settings/approvals changes will appear here.',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            )
          else
            for (final e in recent) _ActivityRow(entry: e, isAr: isAr),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final dynamic entry; // AuditEntry
  final bool isAr;
  const _ActivityRow({required this.entry, required this.isAr});

  IconData _iconForAction(String action) {
    switch (action) {
      case 'create':
        return Icons.add_circle_outline;
      case 'update':
        return Icons.edit_outlined;
      case 'delete':
        return Icons.delete_outline;
      case 'submit':
        return Icons.send_outlined;
      case 'approve':
        return Icons.check_circle_outline;
      case 'reject':
        return Icons.cancel_outlined;
      case 'login':
        return Icons.login;
      case 'logout':
        return Icons.logout;
      case 'assign':
        return Icons.link;
      case 'unassign':
        return Icons.link_off;
      default:
        return Icons.bolt;
    }
  }

  Color _colorForAction(String action) {
    switch (action) {
      case 'create':
        return AppColors.success;
      case 'update':
        return AppColors.info;
      case 'delete':
      case 'reject':
        return AppColors.danger;
      case 'approve':
        return AppColors.success;
      case 'submit':
        return AppColors.warning;
      case 'login':
      case 'logout':
        return AppColors.purple;
      default:
        return Colors.grey;
    }
  }

  String _actionLabel(String action) {
    final map = isAr
        ? {
            'create': 'إنشاء',
            'update': 'تعديل',
            'delete': 'حذف',
            'submit': 'تقديم',
            'approve': 'موافقة',
            'reject': 'رفض',
            'login': 'دخول',
            'logout': 'خروج',
            'assign': 'إسناد',
            'unassign': 'إلغاء إسناد',
          }
        : {
            'create': 'Created',
            'update': 'Updated',
            'delete': 'Deleted',
            'submit': 'Submitted',
            'approve': 'Approved',
            'reject': 'Rejected',
            'login': 'Login',
            'logout': 'Logout',
            'assign': 'Assigned',
            'unassign': 'Unassigned',
          };
    return map[action] ?? action;
  }

  String _timeAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return isAr ? 'الآن' : 'now';
    if (diff.inMinutes < 60) {
      return isAr ? 'منذ ${diff.inMinutes} د' : '${diff.inMinutes}m ago';
    }
    if (diff.inHours < 24) {
      return isAr ? 'منذ ${diff.inHours} س' : '${diff.inHours}h ago';
    }
    if (diff.inDays < 7) {
      return isAr ? 'منذ ${diff.inDays} يوم' : '${diff.inDays}d ago';
    }
    return '${t.day}/${t.month}/${t.year}';
  }

  @override
  Widget build(BuildContext context) {
    final action = entry.action as String;
    final color = _colorForAction(action);
    final icon = _iconForAction(action);
    final repo = MockRepository();
    String actorName = '?';
    try {
      final acc = repo.accounts.firstWhere((a) => a.id == entry.userId);
      actorName = acc.fullName;
    } catch (_) {
      // user might be a legacy user
      try {
        final u = repo.users.firstWhere((u) => u.id == entry.userId);
        actorName = u.fullName;
      } catch (_) {}
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, color: color, size: 14),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        _actionLabel(action),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${entry.targetType ?? "?"}${entry.targetId != null ? "/${entry.targetId}" : ""}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'monospace',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (entry.details != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    entry.details as String,
                    style: const TextStyle(fontSize: 10.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.person_outline,
                        size: 9, color: Colors.grey[600]),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text(
                        actorName,
                        style:
                            TextStyle(fontSize: 9.5, color: Colors.grey[700]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _timeAgo(entry.at as DateTime),
                      style:
                          TextStyle(fontSize: 9.5, color: Colors.grey[600]),
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
}

// ============================================================
// 🆕 Session 18: Activity Charts Card
// ============================================================
class _ActivityChartsCard extends StatelessWidget {
  const _ActivityChartsCard();

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final repo = MockRepository();
    final logs = repo.auditLog;

    if (logs.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withOpacity(0.25)),
        ),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.bar_chart, color: Colors.grey[400], size: 32),
              const SizedBox(height: 6),
              Text(
                isAr
                    ? 'لا توجد بيانات نشاط بعد'
                    : 'No activity data yet',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    // 1) Activity by day (last 7 days)
    final byDay = <int, int>{}; // 0..6 (today=0)
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    for (var i = 0; i < 7; i++) {
      byDay[i] = 0;
    }
    for (final e in logs) {
      final logDate = DateTime(e.at.year, e.at.month, e.at.day);
      final daysAgo = today.difference(logDate).inDays;
      if (daysAgo >= 0 && daysAgo < 7) {
        byDay[daysAgo] = (byDay[daysAgo] ?? 0) + 1;
      }
    }

    // 2) Activity by action type
    final byAction = <String, int>{};
    for (final e in logs) {
      byAction[e.action] = (byAction[e.action] ?? 0) + 1;
    }
    final topActions = byAction.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // 3) Top users
    final byUser = <String, int>{};
    for (final e in logs) {
      byUser[e.userId] = (byUser[e.userId] ?? 0) + 1;
    }
    final topUsers = byUser.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value))
      ..take(5).toList();

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
          Row(
            children: [
              const Icon(Icons.bar_chart, color: AppColors.brand, size: 18),
              const SizedBox(width: 6),
              Text(
                isAr ? '📈 إحصاءات النشاط' : '📈 Activity Stats',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              Text(
                isAr ? 'إجمالي ${logs.length}' : '${logs.length} total',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ===== Bar chart: Activity by day =====
          Text(
            isAr ? 'النشاط في 7 أيام' : 'Last 7 days',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Colors.grey[700]),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 120,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: (byDay.values.fold<int>(0, (a, b) => a > b ? a : b) + 2)
                    .toDouble(),
                barTouchData: BarTouchData(enabled: true),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 1,
                  getDrawingHorizontalLine: (v) => FlLine(
                    color: Colors.grey.withOpacity(0.12),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      interval: 1,
                      getTitlesWidget: (v, _) => Text(
                        v.toInt().toString(),
                        style: const TextStyle(fontSize: 9),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, _) {
                        final idx = v.toInt();
                        final daysAgo = 6 - idx;
                        final label =
                            daysAgo == 0 ? (isAr ? 'الآن' : 'Today') : '-$daysAgo';
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(label,
                              style: const TextStyle(fontSize: 9)),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: [
                  for (var i = 6; i >= 0; i--)
                    BarChartGroupData(
                      x: 6 - i,
                      barRods: [
                        BarChartRodData(
                          toY: (byDay[i] ?? 0).toDouble(),
                          color: AppColors.brand,
                          width: 14,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ===== Pie chart: Action breakdown =====
          if (topActions.isNotEmpty) ...[
            Text(
              isAr ? 'حسب نوع الإجراء' : 'By action type',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey[700]),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                SizedBox(
                  width: 120,
                  height: 120,
                  child: PieChart(
                    PieChartData(
                      sections: topActions.take(5).map((entry) {
                        return PieChartSectionData(
                          color: _colorForAction(entry.key),
                          value: entry.value.toDouble(),
                          title: '${entry.value}',
                          titleStyle: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                          radius: 40,
                        );
                      }).toList(),
                      centerSpaceRadius: 18,
                      sectionsSpace: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: topActions.take(5).map((entry) {
                      final pct = (entry.value * 100 / logs.length)
                          .toStringAsFixed(0);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: _colorForAction(entry.key),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                entry.key,
                                style: const TextStyle(
                                    fontSize: 10, fontWeight: FontWeight.w700),
                              ),
                            ),
                            Text(
                              '$pct%',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey[700],
                                  fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],

          // ===== Top Users =====
          if (topUsers.isNotEmpty) ...[
            Text(
              isAr ? '🏆 الأكثر نشاطاً' : '🏆 Top contributors',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey[700]),
            ),
            const SizedBox(height: 6),
            for (final u in topUsers.take(5)) _topUserRow(repo, u, logs.length),
          ],
        ],
      ),
    );
  }

  Widget _topUserRow(MockRepository repo, MapEntry<String, int> entry,
      int total) {
    String name = '?';
    try {
      final acc = repo.accounts.firstWhere((a) => a.id == entry.key);
      name = acc.fullName;
    } catch (_) {
      try {
        final u = repo.users.firstWhere((u) => u.id == entry.key);
        name = u.fullName;
      } catch (_) {}
    }
    final pct = (entry.value * 100 / total).toStringAsFixed(0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          CircleAvatar(
            radius: 10,
            backgroundColor: AppColors.brand.withOpacity(0.15),
            child: Text(
              name.isEmpty ? '?' : name[0].toUpperCase(),
              style: const TextStyle(
                color: AppColors.brand,
                fontSize: 9,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              width: 50,
              height: 6,
              child: LinearProgressIndicator(
                value: entry.value / total,
                backgroundColor: Colors.grey.withOpacity(0.15),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppColors.brand),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 36,
            child: Text(
              '${entry.value} ($pct%)',
              style: TextStyle(fontSize: 9.5, color: Colors.grey[700]),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Color _colorForAction(String action) {
    switch (action) {
      case 'create':
        return AppColors.success;
      case 'update':
        return AppColors.info;
      case 'delete':
      case 'reject':
        return AppColors.danger;
      case 'approve':
        return Colors.green;
      case 'submit':
        return AppColors.warning;
      case 'login':
      case 'logout':
        return AppColors.purple;
      default:
        return Colors.grey;
    }
  }
}
