import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../models/lookups.dart';
import '../../models/models.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/m7_app_bar.dart';
import '../manager/role_permissions_matrix_screen.dart';
import 'employee_profile_screen.dart';

/// 👤 شاشة "ملفّ مسمّى وظيفي" (Job Title Profile)
///
/// عرض شامل لكلّ ما يخصّ مسمّى وظيفيّاً واحداً في صفحة واحدة:
///   - البطاقة الأساسيّة: الاسم، اللون، المستوى، dashboard، قوّة الموافقات
///   - الهرم: مَن يدير، مَن يُدير
///   - الصلاحيّات: عدد + توزيع حسب الموديول
///   - سير الموافقات: في أيّ workflows يظهر كمُوقّع
///   - الموظفون: مَن يحمل هذا المسمّى
///   - الفجوات: تنبيهات + اقتراحات إصلاح
///
/// استخدم هذه الشاشة من أيّ مكان (org chart, bulk matrix, lookups) كنقطة
/// التفتيش الموحّدة لكلّ ما يتعلّق بالمسمّى قبل اعتماد أيّ تغيير.
class JobTitleProfileScreen extends StatefulWidget {
  final JobTitle jobTitle;
  const JobTitleProfileScreen({super.key, required this.jobTitle});

  @override
  State<JobTitleProfileScreen> createState() => _JobTitleProfileScreenState();
}

class _JobTitleProfileScreenState extends State<JobTitleProfileScreen> {
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
    final jt = widget.jobTitle;
    final color = _hexToColor(jt.color) ?? AppColors.brand;

    // 🔢 إحصاءات
    final permissions = jt.roleId == null
        ? <String>{}
        : repo.permissionKeysForRole(jt.roleId!);
    final managers = repo.managersOf(jt.id);
    final subordinates = repo.subordinatesOf(jt.id);
    final employees = repo.employees
        .where((e) => e.jobTitleId == jt.id)
        .toList();

    // قوالب يظهر فيها كمُوقّع
    final workflowReferences = <_WorkflowReference>[];
    for (final tpl in repo.formTemplates) {
      // اختبر بكل عيّنات
      for (var i = 0; i < tpl.workflow.length; i++) {
        final step = tpl.workflow[i];
        final actorType = (step['actor_type'] as String?) ?? 'role';
        // role-based: قارن باسم المسمّى عبر الدور
        if (actorType == 'role' && jt.roleId != null) {
          final roleKey = step['role'] as String?;
          if (roleKey != null) {
            final role = repo.roleDefs.firstWhere(
                (r) => r.id == jt.roleId,
                orElse: () => RoleDef(
                    id: '', key: '', nameAr: '', nameEn: ''));
            if (role.key == roleKey) {
              workflowReferences.add(_WorkflowReference(
                template: tpl, stepIndex: i, kind: 'role'));
            }
          }
        } else if (actorType == 'auto_chain') {
          final minPower = (step['min_approval_power'] as int?) ?? 1;
          if (jt.approvalPower >= minPower) {
            workflowReferences.add(_WorkflowReference(
              template: tpl, stepIndex: i, kind: 'auto_chain'));
          }
        }
      }
    }

    // فجوات سريعة
    final gaps = <String>[];
    if (jt.approvalPower > 0 && jt.roleId == null) {
      gaps.add(isAr
          ? 'مُوافِق بدون دور (لن يستطيع الموافقة فعلياً)'
          : 'Approver without a role (cannot actually approve)');
    }
    if (jt.level > 1 && jt.reportsToIds.isEmpty) {
      gaps.add(isAr
          ? 'مستواه ${jt.level} لكنّه لا يتبع لأحد'
          : 'Level ${jt.level} but reports to no one');
    }
    if (jt.dashboardType == DashboardType.supervisor &&
        permissions.isNotEmpty &&
        !permissions.any((p) =>
            p == 'rosters.approve' ||
            p == 'camp.checklist.create' ||
            p.startsWith('evaluation'))) {
      gaps.add(isAr
          ? 'لوحة "مشرف" لكن لا توجد صلاحيّة إشراف'
          : 'Supervisor dashboard but no supervisor permission');
    }

    return Scaffold(
      appBar: M7AppBar(
        title: jt.displayName(isAr),
        subtitle: isAr
            ? '${jt.dashboardType.label(true)} • L${jt.level}'
            : '${jt.dashboardType.label(false)} • L${jt.level}',
        backgroundColor: color,
        actions: [
          M7AppBarAction(
            icon: Icons.security_outlined,
            tooltip: isAr ? 'تعديل الصلاحيّات' : 'Edit Permissions',
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    RolePermissionsMatrixScreen(jobTitle: jt),
              ));
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // ===== Hero card =====
          _HeroCard(jt: jt, color: color, isAr: isAr),
          const SizedBox(height: 12),

          // ===== Quick KPIs =====
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
                  icon: Icons.people_outline,
                  label: isAr ? 'موظفون' : 'Employees',
                  value: '${employees.length}',
                  color: AppColors.info,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _Kpi(
                  icon: Icons.assignment_outlined,
                  label: isAr ? 'سير موافقات' : 'Workflows',
                  value: '${workflowReferences.length}',
                  color: AppColors.brand,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _Kpi(
                  icon: Icons.warning_amber_outlined,
                  label: isAr ? 'فجوات' : 'Gaps',
                  value: '${gaps.length}',
                  color: gaps.isEmpty ? AppColors.success : AppColors.danger,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ===== Gaps =====
          if (gaps.isNotEmpty) ...[
            _Section(
              title: isAr ? '⚠️ فجوات يجب معالجتها' : '⚠️ Issues to address',
              child: Column(
                children: [
                  for (final g in gaps)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: AppColors.danger.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline,
                              color: AppColors.danger, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              g,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.danger,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ===== Hierarchy =====
          _Section(
            title: isAr ? '🏛️ الهرم' : '🏛️ Hierarchy',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _hierarchyBlock(
                  title: isAr ? 'يتبع لـ' : 'Reports to',
                  items: managers,
                  emptyText:
                      isAr ? '— لا أحد (في القمّة)' : '— None (top of hierarchy)',
                  isAr: isAr,
                  primaryId: jt.primaryReportsToId,
                ),
                const SizedBox(height: 10),
                _hierarchyBlock(
                  title: isAr ? 'يدير' : 'Manages',
                  items: subordinates,
                  emptyText: isAr ? '— لا يدير أحداً' : '— Manages no one',
                  isAr: isAr,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ===== Permissions summary =====
          _Section(
            title: isAr ? '🛡️ الصلاحيّات' : '🛡️ Permissions',
            child: permissions.isEmpty
                ? Text(
                    isAr ? 'لا توجد صلاحيّات' : 'No permissions',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  )
                : _permissionsByModule(permissions, isAr),
          ),
          const SizedBox(height: 12),

          // ===== Workflows =====
          _Section(
            title: isAr ? '📑 سير الموافقات' : '📑 Workflows',
            child: workflowReferences.isEmpty
                ? Text(
                    isAr
                        ? 'لا يظهر في أيّ سلسلة موافقات'
                        : 'Not referenced in any workflow',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  )
                : Column(
                    children: workflowReferences
                        .map((w) => _workflowRefRow(w, isAr))
                        .toList(),
                  ),
          ),
          const SizedBox(height: 12),

          // ===== Employees =====
          _Section(
            title: isAr ? '👥 الموظفون' : '👥 Employees',
            child: employees.isEmpty
                ? Text(
                    isAr ? 'لا يوجد موظف بهذا المسمّى' : 'No employees',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  )
                : Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: employees
                        .map((e) => _EmployeeChip(employee: e))
                        .toList(),
                  ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _hierarchyBlock({
    required String title,
    required List<JobTitle> items,
    required String emptyText,
    required bool isAr,
    String? primaryId,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        if (items.isEmpty)
          Text(emptyText,
              style: TextStyle(fontSize: 11, color: Colors.grey[600]))
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: items
                .map((it) => InkWell(
                      onTap: () =>
                          Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) =>
                                  JobTitleProfileScreen(jobTitle: it))),
                      borderRadius: BorderRadius.circular(6),
                      child: _JobTitleChip(
                          jobTitle: it,
                          isPrimary: it.id == primaryId,
                          isAr: isAr),
                    ))
                .toList(),
          ),
      ],
    );
  }

  Widget _permissionsByModule(Set<String> keys, bool isAr) {
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
                  color: AppColors.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: AppColors.success.withValues(alpha: 0.3)),
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

  Widget _workflowRefRow(_WorkflowReference w, bool isAr) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.brand.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.brand.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.assignment_outlined,
              size: 14, color: AppColors.brand),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAr ? w.template.nameAr : w.template.nameEn,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800),
                ),
                Text(
                  isAr
                      ? 'الخطوة ${w.stepIndex + 1}'
                      : 'Step ${w.stepIndex + 1}',
                  style: TextStyle(fontSize: 10, color: Colors.grey[700]),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: w.kind == 'auto_chain'
                  ? AppColors.purple.withValues(alpha: 0.15)
                  : AppColors.info.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              w.kind == 'auto_chain'
                  ? (isAr ? 'تلقائي' : 'Auto')
                  : (isAr ? 'دور' : 'Role'),
              style: TextStyle(
                fontSize: 9,
                color:
                    w.kind == 'auto_chain' ? AppColors.purple : AppColors.info,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
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

class _WorkflowReference {
  final FormTemplate template;
  final int stepIndex;
  final String kind; // 'role' / 'auto_chain'
  _WorkflowReference({
    required this.template,
    required this.stepIndex,
    required this.kind,
  });
}

class _HeroCard extends StatelessWidget {
  final JobTitle jt;
  final Color color;
  final bool isAr;
  const _HeroCard(
      {required this.jt, required this.color, required this.isAr});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withValues(alpha: 0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
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
              if (jt.level > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'L${jt.level}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  jt.dashboardType.label(isAr),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              if (jt.isSupervisor)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.supervisor_account_outlined,
                          color: Colors.white, size: 12),
                      SizedBox(width: 3),
                      Text(
                        'Supervisor',
                        style: TextStyle(
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
          const SizedBox(height: 10),
          Text(
            jt.displayName(isAr),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isAr ? jt.nameEn : jt.nameAr,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.verified_outlined,
                  color: Colors.white.withValues(alpha: 0.9), size: 14),
              const SizedBox(width: 4),
              Text(
                isAr
                    ? 'قوّة الموافقات: ${jt.approvalPower}/5'
                    : 'Approval power: ${jt.approvalPower}/5',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (jt.approvalPower > 0) ...[
                const SizedBox(width: 8),
                ...List.generate(
                    5,
                    (i) => Padding(
                          padding: const EdgeInsets.only(right: 1),
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: i < jt.approvalPower
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.3),
                              shape: BoxShape.circle,
                            ),
                          ),
                        )),
              ],
            ],
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
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 14),
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
        border: Border.all(color: Colors.grey.withValues(alpha: 0.25)),
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

class _JobTitleChip extends StatelessWidget {
  final JobTitle jobTitle;
  final bool isPrimary;
  final bool isAr;
  const _JobTitleChip({
    required this.jobTitle,
    required this.isPrimary,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isPrimary
            ? AppColors.brand.withValues(alpha: 0.12)
            : Colors.grey.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isPrimary
              ? AppColors.brand
              : Colors.grey.withValues(alpha: 0.3),
          width: isPrimary ? 1.5 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isPrimary)
            Container(
              margin: const EdgeInsetsDirectional.only(end: 4),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.brand,
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Text(
                '★',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          if (jobTitle.level > 0) ...[
            Text(
              'L${jobTitle.level}',
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w900,
                color: Colors.grey,
              ),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            jobTitle.displayName(isAr),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmployeeChip extends StatelessWidget {
  final Employee employee;
  const _EmployeeChip({required this.employee});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => EmployeeProfileScreen(employee: employee),
      )),
      borderRadius: BorderRadius.circular(6),
      child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.person_outline, size: 12, color: AppColors.info),
          const SizedBox(width: 4),
          Text(
            employee.fullName,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 4),
          Text(
            '• ${employee.code}',
            style: const TextStyle(fontSize: 9, color: Colors.grey),
          ),
        ],
      ),
      ),
    );
  }
}
