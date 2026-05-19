import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/workflow_engine.dart';
import '../../core/theme/app_colors.dart';
import '../../models/lookups.dart';
import '../../repositories/mock_repository.dart';
import '../manager/role_permissions_matrix_screen.dart';

/// 🧮 شاشة مصفوفة الموافقات (Approval Matrix)
///
/// لوحة شاملة لمسؤولي النظام تعرض:
///   - **Coverage** — لكل قالب نموذج، يحلّ سلسلة الموافقات لكل مسمّى وظيفي
///                   ويُظهر إن كانت تكتمل بنجاح أم تنقطع.
///   - **Gaps**     — قائمة بالفجوات المكتشَفة في الهرم:
///         * مسمّيات أيتام (level > 1 بدون مدير)
///         * قوالب تنقطع سلسلتها مع كل المُقدِّمين
///         * مسمّيات بقوّة موافقة = 0 لكنّها مُدرجة كمُوقّع
///   - **Approvers** — تجميع المسمّيات حسب قوّة الموافقات
///                    لمعرفة "من يستطيع الموافقة على ماذا".
class ApprovalMatrixScreen extends StatefulWidget {
  const ApprovalMatrixScreen({super.key});

  @override
  State<ApprovalMatrixScreen> createState() => _ApprovalMatrixScreenState();
}

class _ApprovalMatrixScreenState extends State<ApprovalMatrixScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    MockRepository().addListener(_onChange);
  }

  @override
  void dispose() {
    _tabs.dispose();
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
    final analysis = _MatrixAnalysis.compute();

    // 🆕 Scaffold لِيُوَفِّر Material ancestor الذي يَحتاجه TabBar.
    //   كان مَفقوداً بَعد إزالة الـ Scaffold الخارِجيّ مِن settings_hub.
    return Scaffold(
      body: Column(
      children: [
        // ===== KPI strip =====
        Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: _MatrixKpi(
                  icon: Icons.assignment_outlined,
                  label: isAr ? 'القوالب' : 'Templates',
                  value: '${analysis.templateCount}',
                  color: AppColors.brand,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _MatrixKpi(
                  icon: Icons.badge_outlined,
                  label: isAr ? 'المسمّيات' : 'Job Titles',
                  value: '${analysis.jobTitleCount}',
                  color: AppColors.info,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _MatrixKpi(
                  icon: Icons.verified_outlined,
                  label: isAr ? 'مُوافِقون' : 'Approvers',
                  value: '${analysis.approverCount}',
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _MatrixKpi(
                  icon: Icons.error_outline,
                  label: isAr ? 'فجوات' : 'Gaps',
                  value: '${analysis.gaps.length}',
                  color: analysis.gaps.isEmpty
                      ? AppColors.success
                      : AppColors.danger,
                ),
              ),
            ],
          ),
        ),
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: [
            Tab(text: isAr ? 'التغطية' : 'Coverage'),
            Tab(text: isAr ? 'الفجوات (${analysis.gaps.length})' : 'Gaps (${analysis.gaps.length})'),
            Tab(text: isAr ? 'المُوافِقون' : 'Approvers'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _CoverageTab(analysis: analysis),
              _GapsTab(analysis: analysis),
              _ApproversTab(analysis: analysis),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================
// التحليل
// ============================================================

class _MatrixAnalysis {
  final int templateCount;
  final int jobTitleCount;
  final int approverCount;
  final List<_Gap> gaps;
  final List<_TemplateCoverage> coverage;
  final Map<int, List<JobTitle>> approversByPower;

  _MatrixAnalysis({
    required this.templateCount,
    required this.jobTitleCount,
    required this.approverCount,
    required this.gaps,
    required this.coverage,
    required this.approversByPower,
  });

  static _MatrixAnalysis compute() {
    final repo = MockRepository();
    final gaps = <_Gap>[];

    // 1) أيتام: level > 1 و reportsToIds فارغ
    for (final jt in repo.jobTitles) {
      if (jt.level > 1 && jt.reportsToIds.isEmpty) {
        gaps.add(_Gap(
          severity: _GapSeverity.warning,
          kind: _GapKind.orphanJobTitle,
          titleAr: 'مسمّى يتيم: ${jt.nameAr} (L${jt.level})',
          titleEn: 'Orphan job title: ${jt.nameEn} (L${jt.level})',
          detailAr: 'مستواه ${jt.level} لكنّه لا يتبع لأيّ مسمّى',
          detailEn: 'Level ${jt.level} but reports to no one',
          jobTitleId: jt.id,
        ));
      }
    }

    // 2) تغطية القوالب
    final coverage = <_TemplateCoverage>[];
    for (final t in repo.formTemplates) {
      // محاكاة لكل JobTitle بمستوى 5 (worker level) أو إن لم يوجد فأعمق مسمّى
      final workers = repo.jobTitles.where((j) => j.level == 5).toList();
      final samples = workers.isEmpty
          ? (repo.jobTitles.isEmpty ? <JobTitle>[] : [repo.jobTitles.last])
          : workers;

      var fullyResolved = 0;
      var partial = 0;
      var broken = 0;
      final unresolvedSteps = <String>{};

      for (final sample in samples) {
        final chain = WorkflowEngine.previewChain(
          template: t,
          sampleSubmitterJobTitleId: sample.id,
        );
        final unresolved = chain
            .where((c) => c.match?.isResolved != true)
            .map((c) => 'step ${c.index + 1}')
            .toList();

        if (unresolved.isEmpty) {
          fullyResolved++;
        } else if (unresolved.length < chain.length) {
          partial++;
          unresolvedSteps.addAll(unresolved);
        } else {
          broken++;
          unresolvedSteps.addAll(unresolved);
        }
      }

      final totalSamples = samples.length;
      coverage.add(_TemplateCoverage(
        template: t,
        totalSamples: totalSamples,
        fullyResolved: fullyResolved,
        partial: partial,
        broken: broken,
        unresolvedSteps: unresolvedSteps.toList(),
      ));

      // إذا انكسرت السلسلة لكل العيّنات → فجوة حرجة
      if (totalSamples > 0 && broken == totalSamples) {
        gaps.add(_Gap(
          severity: _GapSeverity.critical,
          kind: _GapKind.brokenChain,
          titleAr: 'سلسلة مكسورة: ${t.nameAr}',
          titleEn: 'Broken chain: ${t.nameEn}',
          detailAr: 'سلسلة الموافقات لا تكتمل لأيّ مُقدِّم',
          detailEn: 'Workflow does not resolve for any submitter',
          templateId: t.id,
        ));
      } else if (totalSamples > 0 && partial > 0) {
        gaps.add(_Gap(
          severity: _GapSeverity.warning,
          kind: _GapKind.partialChain,
          titleAr: 'سلسلة جزئية: ${t.nameAr}',
          titleEn: 'Partial chain: ${t.nameEn}',
          detailAr:
              'الخطوات غير المحلولة: ${unresolvedSteps.join(", ")}',
          detailEn:
              'Unresolved steps: ${unresolvedSteps.join(", ")}',
          templateId: t.id,
        ));
      }
    }

    // 3) approvers grouped by power
    final byPower = <int, List<JobTitle>>{};
    for (final jt in repo.jobTitles) {
      byPower.putIfAbsent(jt.approvalPower, () => []).add(jt);
    }
    final approverCount =
        repo.jobTitles.where((j) => j.approvalPower > 0).length;

    // 4) 🆕 فجوات الصلاحيّات: JobTitle بـ approval_power > 0 لكنّه لا يملك
    //    أيّ صلاحية موافقات (rosters.approve / forms / camp.violations.approve)
    const approvalPermissions = {
      'rosters.approve',
      'rosters.reject',
      'camp.violations.approve',
    };
    for (final jt in repo.jobTitles) {
      if (jt.approvalPower == 0) continue;
      if (jt.roleId == null) {
        gaps.add(_Gap(
          severity: _GapSeverity.warning,
          kind: _GapKind.zeroPowerApprover,
          titleAr: 'مسمّى مُوافِق بدون دور: ${jt.nameAr}',
          titleEn: 'Approver without role: ${jt.nameEn}',
          detailAr: 'قوّة موافقاته ${jt.approvalPower} لكن ليس لديه role_id',
          detailEn: 'Power ${jt.approvalPower} but no role_id linked',
          jobTitleId: jt.id,
        ));
        continue;
      }
      final perms = repo.permissionKeysForRole(jt.roleId!);
      final hasApproval = perms.any(approvalPermissions.contains);
      if (!hasApproval) {
        gaps.add(_Gap(
          severity: _GapSeverity.warning,
          kind: _GapKind.zeroPowerApprover,
          titleAr: 'مُوافِق بدون صلاحيّة موافقة: ${jt.nameAr}',
          titleEn: 'Approver missing approval permission: ${jt.nameEn}',
          detailAr:
              'قوّته ${jt.approvalPower} لكن لا يملك أيّاً من: ${approvalPermissions.join(", ")}',
          detailEn:
              'Power ${jt.approvalPower} but lacks any of: ${approvalPermissions.join(", ")}',
          jobTitleId: jt.id,
        ));
      }
    }

    // 5) 🆕 Dashboard mismatch: dashboard_type=manager بدون أيّ صلاحيّات إدارة
    for (final jt in repo.jobTitles) {
      if (jt.dashboardType == DashboardType.employee) continue;
      if (jt.roleId == null) continue;
      final perms = repo.permissionKeysForRole(jt.roleId!);
      bool isAppropriate = true;
      String? expectedAr;
      String? expectedEn;
      switch (jt.dashboardType) {
        case DashboardType.manager:
          isAppropriate = perms.any((p) =>
              p.startsWith('reports.') ||
              p == 'employees.view' ||
              p == 'rosters.view');
          expectedAr = 'reports.* أو employees.view';
          expectedEn = 'reports.* or employees.view';
          break;
        case DashboardType.supervisor:
          isAppropriate = perms.any((p) =>
              p == 'rosters.approve' ||
              p == 'camp.checklist.create' ||
              p.startsWith('evaluation'));
          expectedAr = 'rosters.approve أو camp.checklist.create';
          expectedEn = 'rosters.approve or camp.checklist.create';
          break;
        case DashboardType.hr:
          isAppropriate = perms.any((p) =>
              p == 'employees.view' || p == 'employees.create');
          expectedAr = 'employees.view أو employees.create';
          expectedEn = 'employees.view or employees.create';
          break;
        case DashboardType.finance:
          isAppropriate = perms.contains('reports.view') ||
              perms.contains('reports.export');
          expectedAr = 'reports.view أو reports.export';
          expectedEn = 'reports.view or reports.export';
          break;
        case DashboardType.driver:
          isAppropriate = perms.contains('driver.trips.view');
          expectedAr = 'driver.trips.view';
          expectedEn = 'driver.trips.view';
          break;
        case DashboardType.operations:
          isAppropriate = perms.any((p) => p.startsWith('rosters.'));
          expectedAr = 'rosters.*';
          expectedEn = 'rosters.*';
          break;
        case DashboardType.employee:
          break;
      }
      if (!isAppropriate) {
        gaps.add(_Gap(
          severity: _GapSeverity.info,
          kind: _GapKind.zeroPowerApprover,
          titleAr:
              'تعارض dashboard: ${jt.nameAr} يحتاج ${jt.dashboardType.label(true)}',
          titleEn:
              'Dashboard mismatch: ${jt.nameEn} expected ${jt.dashboardType.label(false)}',
          detailAr:
              'لوحة تحكم ${jt.dashboardType.label(true)} تتطلّب: $expectedAr',
          detailEn:
              '${jt.dashboardType.label(false)} dashboard expects: $expectedEn',
          jobTitleId: jt.id,
        ));
      }
    }

    return _MatrixAnalysis(
      templateCount: repo.formTemplates.length,
      jobTitleCount: repo.jobTitles.length,
      approverCount: approverCount,
      gaps: gaps,
      coverage: coverage,
      approversByPower: byPower,
    );
  }
}

class _TemplateCoverage {
  final dynamic template; // FormTemplate (avoid hard import)
  final int totalSamples;
  final int fullyResolved;
  final int partial;
  final int broken;
  final List<String> unresolvedSteps;

  _TemplateCoverage({
    required this.template,
    required this.totalSamples,
    required this.fullyResolved,
    required this.partial,
    required this.broken,
    required this.unresolvedSteps,
  });

  double get healthScore {
    if (totalSamples == 0) return 0;
    return fullyResolved / totalSamples;
  }
}

enum _GapSeverity { critical, warning, info }
enum _GapKind { orphanJobTitle, brokenChain, partialChain, zeroPowerApprover }

class _Gap {
  final _GapSeverity severity;
  final _GapKind kind;
  final String titleAr;
  final String titleEn;
  final String detailAr;
  final String detailEn;
  final String? jobTitleId;
  final String? templateId;
  _Gap({
    required this.severity,
    required this.kind,
    required this.titleAr,
    required this.titleEn,
    required this.detailAr,
    required this.detailEn,
    this.jobTitleId,
    this.templateId,
  });
}

// ============================================================
// Tabs
// ============================================================

class _CoverageTab extends StatelessWidget {
  final _MatrixAnalysis analysis;
  const _CoverageTab({required this.analysis});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    if (analysis.coverage.isEmpty) {
      return _Empty(
        icon: Icons.assignment_outlined,
        text: isAr ? 'لا توجد قوالب نماذج' : 'No form templates',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: analysis.coverage.length,
      itemBuilder: (_, i) {
        final c = analysis.coverage[i];
        return _CoverageRow(coverage: c, isAr: isAr);
      },
    );
  }
}

class _CoverageRow extends StatelessWidget {
  final _TemplateCoverage coverage;
  final bool isAr;
  const _CoverageRow({required this.coverage, required this.isAr});

  @override
  Widget build(BuildContext context) {
    final h = coverage.healthScore;
    final color = h >= 0.99
        ? AppColors.success
        : (h >= 0.5 ? AppColors.warning : AppColors.danger);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${(h * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      coverage.template.code as String,
                      style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                          fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isAr
                          ? coverage.template.nameAr as String
                          : coverage.template.nameEn as String,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // شريط تقسيم النتائج
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 6,
              child: Row(
                children: [
                  if (coverage.fullyResolved > 0)
                    Expanded(
                      flex: coverage.fullyResolved,
                      child: Container(color: AppColors.success),
                    ),
                  if (coverage.partial > 0)
                    Expanded(
                      flex: coverage.partial,
                      child: Container(color: AppColors.warning),
                    ),
                  if (coverage.broken > 0)
                    Expanded(
                      flex: coverage.broken,
                      child: Container(color: AppColors.danger),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _MiniLegend(
                color: AppColors.success,
                text: isAr
                    ? 'مكتمل: ${coverage.fullyResolved}'
                    : 'Full: ${coverage.fullyResolved}',
              ),
              const SizedBox(width: 8),
              _MiniLegend(
                color: AppColors.warning,
                text: isAr
                    ? 'جزئي: ${coverage.partial}'
                    : 'Partial: ${coverage.partial}',
              ),
              const SizedBox(width: 8),
              _MiniLegend(
                color: AppColors.danger,
                text: isAr
                    ? 'مكسور: ${coverage.broken}'
                    : 'Broken: ${coverage.broken}',
              ),
              const Spacer(),
              Text(
                isAr
                    ? '/ ${coverage.totalSamples}'
                    : '/ ${coverage.totalSamples}',
                style: TextStyle(fontSize: 10, color: Colors.grey[600]),
              ),
            ],
          ),
          if (coverage.unresolvedSteps.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              isAr
                  ? '⚠️ ${coverage.unresolvedSteps.join(", ")}'
                  : '⚠️ ${coverage.unresolvedSteps.join(", ")}',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.danger,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniLegend extends StatelessWidget {
  final Color color;
  final String text;
  const _MiniLegend({required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _GapsTab extends StatelessWidget {
  final _MatrixAnalysis analysis;
  const _GapsTab({required this.analysis});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    if (analysis.gaps.isEmpty) {
      return _Empty(
        icon: Icons.check_circle_outline,
        text: isAr ? '✅ لا توجد فجوات في الهرم' : '✅ No gaps detected',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: analysis.gaps.length,
      itemBuilder: (_, i) {
        final g = analysis.gaps[i];
        final color = g.severity == _GapSeverity.critical
            ? AppColors.danger
            : g.severity == _GapSeverity.warning
                ? AppColors.warning
                : AppColors.info;
        final icon = g.severity == _GapSeverity.critical
            ? Icons.error_outline
            : g.severity == _GapSeverity.warning
                ? Icons.warning_amber_outlined
                : Icons.info_outline;
        final isFixable = g.jobTitleId != null;
        return InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: isFixable ? () => _fixGap(context, g) : null,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withOpacity(0.4)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isAr ? g.titleAr : g.titleEn,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isAr ? g.detailAr : g.detailEn,
                        style: TextStyle(
                            fontSize: 11.5, color: Colors.grey[800]),
                      ),
                    ],
                  ),
                ),
                if (isFixable)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.build_outlined,
                            color: Colors.white, size: 12),
                        const SizedBox(width: 3),
                        Text(
                          isAr ? 'إصلاح' : 'Fix',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 🆕 ينقل المسؤول إلى شاشة تحرير الصلاحيّات للمسمّى المرتبط بالفجوة
  void _fixGap(BuildContext context, _Gap g) {
    final repo = MockRepository();
    if (g.jobTitleId == null) return;
    final jt = repo.jobTitleById(g.jobTitleId);
    if (jt == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RolePermissionsMatrixScreen(jobTitle: jt),
    ));
  }
}

class _ApproversTab extends StatelessWidget {
  final _MatrixAnalysis analysis;
  const _ApproversTab({required this.analysis});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final levels = [5, 4, 3, 2, 1, 0];
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final p in levels) ...[
          _PowerSection(
            power: p,
            jobTitles: analysis.approversByPower[p] ?? [],
            isAr: isAr,
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _PowerSection extends StatelessWidget {
  final int power;
  final List<JobTitle> jobTitles;
  final bool isAr;
  const _PowerSection({
    required this.power,
    required this.jobTitles,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    if (jobTitles.isEmpty) return const SizedBox.shrink();
    final color = power == 0
        ? Colors.grey
        : power >= 4
            ? AppColors.success
            : (power >= 2 ? AppColors.info : AppColors.warning);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  power == 0
                      ? (isAr ? 'بدون موافقة' : 'No approval')
                      : (isAr ? 'قوّة $power' : 'Power $power'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '(${jobTitles.length})',
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: jobTitles
                .map((jt) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: color.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (jt.level > 0) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.grey.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'L${jt.level}',
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            jt.displayName(isAr),
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _MatrixKpi extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _MatrixKpi({
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
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
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
          const SizedBox(height: 4),
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

class _Empty extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Empty({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: Colors.grey[400]),
          const SizedBox(height: 8),
          Text(
            text,
            style: TextStyle(
                fontSize: 13,
                color: Colors.grey[700],
                fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
