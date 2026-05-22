import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../models/lookups.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';
import 'employee_profile_screen.dart';
import 'job_title_profile_screen.dart';

/// 🏢 شاشة "ملفّ قسم" (Department Profile)
///
/// عرض شامل لكلّ ما يخصّ قسماً واحداً:
///   - بطاقة القسم: الاسم، التصنيف، المستوى الهرمي
///   - الهرم: القسم الأب، الأقسام الفرعيّة (المباشرة + كل النسل)
///   - الموظفون: مَن يعمل بالقسم (والتوزيع حسب المسمّى)
///   - المسمّيات الموجودة: قائمة JobTitles لها موظفون في هذا القسم
class DepartmentProfileScreen extends StatefulWidget {
  final Department department;
  const DepartmentProfileScreen({super.key, required this.department});

  @override
  State<DepartmentProfileScreen> createState() =>
      _DepartmentProfileScreenState();
}

class _DepartmentProfileScreenState extends State<DepartmentProfileScreen> {
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
    final dept = widget.department;

    final parent = dept.parentId == null
        ? null
        : repo.departments.firstWhere(
            (d) => d.id == dept.parentId,
            orElse: () => Department(id: '', nameAr: '', nameEn: ''),
          );
    final children = repo.childDepartments(dept.id);
    final descendantIds = repo.descendantDepartmentIds(dept.id);
    final allDescendants = descendantIds
        .map((id) => repo.departments
            .firstWhere((d) => d.id == id, orElse: () => Department(id: '', nameAr: '', nameEn: '')))
        .where((d) => d.id.isNotEmpty)
        .toList();

    // الموظفون داخل هذا القسم (مباشرة فقط)
    final directEmployees =
        repo.employees.where((e) => e.departmentId == dept.id).toList();

    // الموظفون في الأقسام الفرعيّة (كاملة)
    final allDeptIds = {dept.id, ...descendantIds};
    final allEmployees = repo.employees
        .where((e) => e.departmentId != null &&
            allDeptIds.contains(e.departmentId))
        .toList();

    // المسمّيات الموجودة (لها موظف بالقسم أو فروعه)
    final jobTitleCounts = <String, int>{};
    for (final e in allEmployees) {
      if (e.jobTitleId != null) {
        jobTitleCounts[e.jobTitleId!] =
            (jobTitleCounts[e.jobTitleId!] ?? 0) + 1;
      }
    }
    final jobTitlesPresent = jobTitleCounts.entries
        .map((entry) {
          final jt = repo.jobTitleById(entry.key);
          return jt == null ? null : MapEntry(jt, entry.value);
        })
        .whereType<MapEntry<JobTitle, int>>()
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              dept.displayName(isAr),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            Text(
              isAr ? 'قسم • L${dept.level}' : 'Department • L${dept.level}',
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // ===== Hero card =====
          _DeptHero(department: dept, isAr: isAr),
          const SizedBox(height: 12),

          // ===== KPIs =====
          Row(
            children: [
              Expanded(
                child: _Kpi(
                  icon: Icons.subdirectory_arrow_right,
                  label: isAr ? 'فرعيّة مباشرة' : 'Direct subs',
                  value: '${children.length}',
                  color: AppColors.brand,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _Kpi(
                  icon: Icons.account_tree_outlined,
                  label: isAr ? 'كل النسل' : 'All descendants',
                  value: '${allDescendants.length}',
                  color: AppColors.info,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _Kpi(
                  icon: Icons.person_outline,
                  label: isAr ? 'موظفون مباشرون' : 'Direct emps',
                  value: '${directEmployees.length}',
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _Kpi(
                  icon: Icons.groups_outlined,
                  label: isAr ? 'إجمالي' : 'Total',
                  value: '${allEmployees.length}',
                  color: AppColors.purple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ===== Hierarchy =====
          _Section(
            title: isAr ? '🏛️ الهرم' : '🏛️ Hierarchy',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (parent != null && parent.id.isNotEmpty) ...[
                  Text(
                    isAr ? 'القسم الأب' : 'Parent department',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                            builder: (_) => DepartmentProfileScreen(
                                department: parent))),
                    borderRadius: BorderRadius.circular(6),
                    child: _DeptChip(department: parent, isAr: isAr),
                  ),
                  const SizedBox(height: 10),
                ],
                Text(
                  isAr
                      ? 'الأقسام الفرعيّة المباشرة (${children.length})'
                      : 'Direct sub-departments (${children.length})',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                if (children.isEmpty)
                  Text(
                    isAr ? '— لا توجد' : '— None',
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey[600]),
                  )
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: children
                        .map((c) => InkWell(
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => DepartmentProfileScreen(
                                      department: c),
                                ),
                              ),
                              borderRadius: BorderRadius.circular(6),
                              child: _DeptChip(department: c, isAr: isAr),
                            ))
                        .toList(),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ===== Job Titles present =====
          _Section(
            title: isAr ? '👤 المسمّيات الوظيفيّة' : '👤 Job Titles Present',
            child: jobTitlesPresent.isEmpty
                ? Text(
                    isAr ? 'لا توجد' : 'None',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  )
                : Column(
                    children: jobTitlesPresent
                        .map((entry) => InkWell(
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => JobTitleProfileScreen(
                                      jobTitle: entry.key),
                                ),
                              ),
                              borderRadius: BorderRadius.circular(8),
                              child: _JobTitleCountRow(
                                jobTitle: entry.key,
                                count: entry.value,
                                isAr: isAr,
                              ),
                            ))
                        .toList(),
                  ),
          ),
          const SizedBox(height: 12),

          // ===== Direct Employees =====
          _Section(
            title: isAr
                ? '👥 الموظفون المباشرون (${directEmployees.length})'
                : '👥 Direct Employees (${directEmployees.length})',
            child: directEmployees.isEmpty
                ? Text(
                    isAr ? 'لا يوجد' : 'None',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  )
                : Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: directEmployees
                        .map((e) => _EmpChip(employee: e))
                        .toList(),
                  ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}

// ============================================================
// Helpers
// ============================================================

class _DeptHero extends StatelessWidget {
  final Department department;
  final bool isAr;
  const _DeptHero({required this.department, required this.isAr});

  @override
  Widget build(BuildContext context) {
    final categoryColor = _categoryColor(department.category);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.brand, AppColors.brand.withValues(alpha: 0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.brand.withValues(alpha: 0.3),
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
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.apartment_outlined,
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
                      department.displayName(isAr),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isAr ? department.nameEn : department.nameAr,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (department.level > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'L${department.level}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: categoryColor.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isAr
                      ? 'تصنيف: ${_categoryLabelAr(department.category)}'
                      : 'Category: ${_categoryLabelEn(department.category)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (department.isRoot)
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
                      Icon(Icons.star,
                          color: Colors.white, size: 11),
                      SizedBox(width: 3),
                      Text(
                        'Root',
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
        ],
      ),
    );
  }

  static Color _categoryColor(JobTitleCategory c) {
    switch (c) {
      case JobTitleCategory.admin:
        return Colors.blue;
      case JobTitleCategory.operations:
        return Colors.purple;
      case JobTitleCategory.worker:
        return Colors.green;
    }
  }

  static String _categoryLabelAr(JobTitleCategory c) {
    switch (c) {
      case JobTitleCategory.admin:
        return 'إداري';
      case JobTitleCategory.operations:
        return 'عمليات';
      case JobTitleCategory.worker:
        return 'عامل';
    }
  }

  static String _categoryLabelEn(JobTitleCategory c) {
    switch (c) {
      case JobTitleCategory.admin:
        return 'Admin';
      case JobTitleCategory.operations:
        return 'Operations';
      case JobTitleCategory.worker:
        return 'Worker';
    }
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

class _DeptChip extends StatelessWidget {
  final Department department;
  final bool isAr;
  const _DeptChip({required this.department, required this.isAr});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.brand.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.brand.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.apartment_outlined,
              size: 12, color: AppColors.brand),
          const SizedBox(width: 4),
          if (department.level > 0) ...[
            Text(
              'L${department.level}',
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w900,
                color: Colors.grey,
              ),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            department.displayName(isAr),
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

class _JobTitleCountRow extends StatelessWidget {
  final JobTitle jobTitle;
  final int count;
  final bool isAr;
  const _JobTitleCountRow({
    required this.jobTitle,
    required this.count,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    final color = _hexToColor(jobTitle.color) ?? AppColors.brand;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 28,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          if (jobTitle.level > 0) ...[
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
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
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              jobTitle.displayName(isAr),
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.arrow_forward_ios,
              size: 11, color: color.withValues(alpha: 0.6)),
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

class _EmpChip extends StatelessWidget {
  final Employee employee;
  const _EmpChip({required this.employee});

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
