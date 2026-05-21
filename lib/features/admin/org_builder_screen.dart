import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../models/lookups.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/m7_app_bar.dart';

/// 🏗️ شاشة بناء الهيكل التنظيمي بالسحب والإفلات
///
/// تتيح للمسؤول تعديل الهيكل بصريّاً:
///   - **سحب مسمّى وظيفي** فوق آخر → الأوّل سيتبع للثاني (reports_to)
///   - **سحب قسم** فوق قسم آخر → الأوّل يصبح فرعيّاً للثاني (parent_id)
///   - **سحب على المنطقة العلويّة "Top Level"** → جعل المسمّى/القسم بدون أب
///
/// التغييرات تُحفظ مباشرةً في MockRepository.
class OrgBuilderScreen extends StatefulWidget {
  const OrgBuilderScreen({super.key});

  @override
  State<OrgBuilderScreen> createState() => _OrgBuilderScreenState();
}

class _OrgBuilderScreenState extends State<OrgBuilderScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
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
    return Scaffold(
      appBar: M7AppBar(
        title: s.isAr ? '🏗 بِناء الهَيكَل' : '🏗 Org Builder',
      ),
      body: Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.brand.withOpacity(0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.brand.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              const Icon(Icons.drag_indicator, color: AppColors.brand, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  s.isAr
                      ? 'اضغط طويلاً واسحب لإعادة ترتيب الهيكل. أفلت فوق عنصر ليصبح "تحت" ذلك العنصر.'
                      : 'Long-press and drag to restructure. Drop on an item to nest under it.',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: s.isAr ? 'الأقسام' : 'Departments'),
            Tab(text: s.isAr ? 'المسمّيات' : 'Job Titles'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: const [
              _DepartmentBuilder(),
              _JobTitleBuilder(),
            ],
          ),
        ),
      ],
      ),
    );
  }
}

// ============================================================
// Department Builder
// ============================================================

class _DepartmentBuilder extends StatefulWidget {
  const _DepartmentBuilder();

  @override
  State<_DepartmentBuilder> createState() => _DepartmentBuilderState();
}

class _DepartmentBuilderState extends State<_DepartmentBuilder> {
  String? _hoveredTargetId; // 'TOP' or department id

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final isAr = s.isAr;

    final roots = repo.rootDepartments();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // منطقة "Top Level"
        _TopLevelDropZone(
          label: isAr ? 'المستوى الأعلى (بدون أب)' : 'Top Level (no parent)',
          isHovered: _hoveredTargetId == 'TOP',
          onWillAccept: (data) {
            setState(() => _hoveredTargetId = 'TOP');
            return true;
          },
          onLeave: (_) {
            if (mounted) setState(() => _hoveredTargetId = null);
          },
          onAccept: (String departmentId) {
            final dept = repo.departments.firstWhere(
              (d) => d.id == departmentId,
              orElse: () => Department(id: '', nameAr: '', nameEn: ''),
            );
            if (dept.id.isEmpty) return;
            dept.parentId = null;
            dept.level = 0;
            repo.updateDepartment(dept);
            setState(() => _hoveredTargetId = null);
          },
        ),
        const SizedBox(height: 12),
        for (final root in roots) ...[
          _DepartmentNode(
            dept: root,
            depth: 0,
            hoveredTargetId: _hoveredTargetId,
            onHoverEnter: (id) => setState(() => _hoveredTargetId = id),
            onHoverExit: () {
              if (mounted) setState(() => _hoveredTargetId = null);
            },
          ),
          const SizedBox(height: 6),
        ],
        if (roots.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                isAr ? 'لا توجد أقسام' : 'No departments',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
          ),
      ],
    );
  }
}

class _DepartmentNode extends StatelessWidget {
  final Department dept;
  final int depth;
  final String? hoveredTargetId;
  final ValueChanged<String> onHoverEnter;
  final VoidCallback onHoverExit;

  const _DepartmentNode({
    required this.dept,
    required this.depth,
    required this.hoveredTargetId,
    required this.onHoverEnter,
    required this.onHoverExit,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final children = repo.childDepartments(dept.id);
    final isHovered = hoveredTargetId == dept.id;

    return Padding(
      padding: EdgeInsetsDirectional.only(start: depth * 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DragTarget<String>(
            onWillAcceptWithDetails: (details) {
              if (details.data == dept.id) return false;
              // منع الدوائر — لا يمكن جعل الأب فرعاً لأحفاده
              if (_isDescendant(repo, dept.id, details.data)) return false;
              onHoverEnter(dept.id);
              return true;
            },
            onLeave: (_) => onHoverExit(),
            onAcceptWithDetails: (details) {
              final dragged = repo.departments.firstWhere(
                (d) => d.id == details.data,
                orElse: () => Department(id: '', nameAr: '', nameEn: ''),
              );
              if (dragged.id.isEmpty) return;
              dragged.parentId = dept.id;
              dragged.level = dept.level + 1;
              repo.updateDepartment(dragged);
              onHoverExit();
            },
            builder: (_, __, ___) => LongPressDraggable<String>(
              data: dept.id,
              feedback: _DraggingChip(
                label: dept.displayName(s.isAr),
                icon: Icons.apartment,
              ),
              childWhenDragging: Opacity(
                opacity: 0.4,
                child: _DeptCard(
                  dept: dept,
                  isAr: s.isAr,
                  isHovered: false,
                ),
              ),
              child: _DeptCard(
                dept: dept,
                isAr: s.isAr,
                isHovered: isHovered,
              ),
            ),
          ),
          for (final child in children) ...[
            const SizedBox(height: 4),
            _DepartmentNode(
              dept: child,
              depth: depth + 1,
              hoveredTargetId: hoveredTargetId,
              onHoverEnter: onHoverEnter,
              onHoverExit: onHoverExit,
            ),
          ],
        ],
      ),
    );
  }

  static bool _isDescendant(
      MockRepository repo, String parentId, String maybeChildId) {
    final descendants = repo.descendantDepartmentIds(maybeChildId);
    return descendants.contains(parentId);
  }
}

class _DeptCard extends StatelessWidget {
  final Department dept;
  final bool isAr;
  final bool isHovered;
  const _DeptCard({
    required this.dept,
    required this.isAr,
    required this.isHovered,
  });

  @override
  Widget build(BuildContext context) {
    final repo = MockRepository();
    final empCount = repo.employees.where((e) => e.departmentId == dept.id).length;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isHovered
            ? AppColors.brand.withOpacity(0.18)
            : Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isHovered
              ? AppColors.brand
              : Colors.grey.withOpacity(0.3),
          width: isHovered ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.drag_handle, size: 16, color: Colors.grey[500]),
          const SizedBox(width: 8),
          const Icon(Icons.apartment_outlined, size: 18, color: AppColors.brand),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dept.displayName(isAr),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800),
                ),
                if (empCount > 0)
                  Text(
                    isAr ? '$empCount موظف' : '$empCount employees',
                    style: TextStyle(
                        fontSize: 10, color: Colors.grey[600]),
                  ),
              ],
            ),
          ),
          if (dept.level > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.brand.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'L${dept.level}',
                style: const TextStyle(
                  color: AppColors.brand,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================
// Job Title Builder
// ============================================================

class _JobTitleBuilder extends StatefulWidget {
  const _JobTitleBuilder();

  @override
  State<_JobTitleBuilder> createState() => _JobTitleBuilderState();
}

class _JobTitleBuilderState extends State<_JobTitleBuilder> {
  String? _hoveredTargetId;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final isAr = s.isAr;
    final tops = repo.topLevelJobTitles();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _TopLevelDropZone(
          label: isAr ? 'بدون مدير (أعلى الهرم)' : 'No manager (top of hierarchy)',
          isHovered: _hoveredTargetId == 'TOP',
          onWillAccept: (data) {
            setState(() => _hoveredTargetId = 'TOP');
            return true;
          },
          onLeave: (_) {
            if (mounted) setState(() => _hoveredTargetId = null);
          },
          onAccept: (String jobId) {
            final jt = repo.jobTitleById(jobId);
            if (jt == null) return;
            jt.reportsToIds.clear();
            jt.primaryReportsToId = null;
            jt.level = 1;
            repo.updateJobTitle(jt);
            setState(() => _hoveredTargetId = null);
          },
        ),
        const SizedBox(height: 12),
        for (final t in tops) ...[
          _JobTitleNode(
            jobTitle: t,
            depth: 0,
            hoveredTargetId: _hoveredTargetId,
            onHoverEnter: (id) => setState(() => _hoveredTargetId = id),
            onHoverExit: () {
              if (mounted) setState(() => _hoveredTargetId = null);
            },
          ),
          const SizedBox(height: 6),
        ],
        if (tops.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                isAr ? 'لا توجد مسمّيات في الأعلى' : 'No top-level titles',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
          ),
      ],
    );
  }
}

class _JobTitleNode extends StatelessWidget {
  final JobTitle jobTitle;
  final int depth;
  final String? hoveredTargetId;
  final ValueChanged<String> onHoverEnter;
  final VoidCallback onHoverExit;

  const _JobTitleNode({
    required this.jobTitle,
    required this.depth,
    required this.hoveredTargetId,
    required this.onHoverEnter,
    required this.onHoverExit,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final children = repo.subordinatesOf(jobTitle.id);
    final isHovered = hoveredTargetId == jobTitle.id;

    return Padding(
      padding: EdgeInsetsDirectional.only(start: depth * 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DragTarget<String>(
            onWillAcceptWithDetails: (details) {
              if (details.data == jobTitle.id) return false;
              // منع الدوائر — تأكّد أن الجذب ليس أحد المرؤوسين الحاليّين
              if (_isSubordinateOf(repo, jobTitle.id, details.data)) {
                return false;
              }
              onHoverEnter(jobTitle.id);
              return true;
            },
            onLeave: (_) => onHoverExit(),
            onAcceptWithDetails: (details) {
              final dragged = repo.jobTitleById(details.data);
              if (dragged == null) return;
              dragged.reportsToIds
                ..clear()
                ..add(jobTitle.id);
              dragged.primaryReportsToId = jobTitle.id;
              dragged.level = jobTitle.level + 1;
              repo.updateJobTitle(dragged);
              onHoverExit();
            },
            builder: (_, __, ___) => LongPressDraggable<String>(
              data: jobTitle.id,
              feedback: _DraggingChip(
                label: jobTitle.displayName(s.isAr),
                icon: Icons.badge_outlined,
              ),
              childWhenDragging: Opacity(
                opacity: 0.4,
                child: _JobCard(
                  jt: jobTitle,
                  isAr: s.isAr,
                  isHovered: false,
                ),
              ),
              child: _JobCard(
                jt: jobTitle,
                isAr: s.isAr,
                isHovered: isHovered,
              ),
            ),
          ),
          for (final child in children) ...[
            const SizedBox(height: 4),
            _JobTitleNode(
              jobTitle: child,
              depth: depth + 1,
              hoveredTargetId: hoveredTargetId,
              onHoverEnter: onHoverEnter,
              onHoverExit: onHoverExit,
            ),
          ],
        ],
      ),
    );
  }

  /// يتحقّق إن كان [maybeAncestorId] أحد مرؤوسي [titleId] (لمنع الدوائر)
  static bool _isSubordinateOf(
      MockRepository repo, String titleId, String maybeAncestorId) {
    final visited = <String>{};
    final queue = <String>[titleId];
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      if (!visited.add(current)) continue;
      final subs = repo.subordinatesOf(current);
      for (final s in subs) {
        if (s.id == maybeAncestorId) return true;
        queue.add(s.id);
      }
    }
    return false;
  }
}

class _JobCard extends StatelessWidget {
  final JobTitle jt;
  final bool isAr;
  final bool isHovered;
  const _JobCard({
    required this.jt,
    required this.isAr,
    required this.isHovered,
  });

  @override
  Widget build(BuildContext context) {
    final color = _hexToColor(jt.color) ?? AppColors.brand;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isHovered
            ? color.withOpacity(0.20)
            : Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isHovered ? color : Colors.grey.withOpacity(0.3),
          width: isHovered ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.drag_handle, size: 16, color: Colors.grey[500]),
          const SizedBox(width: 8),
          Container(
            width: 8,
            height: 32,
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
                  jt.displayName(isAr),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800),
                ),
                if (jt.approvalPower > 0)
                  Text(
                    isAr
                        ? 'موافقة ${jt.approvalPower}/5'
                        : 'Approval ${jt.approvalPower}/5',
                    style: TextStyle(
                        fontSize: 10, color: Colors.grey[600]),
                  ),
              ],
            ),
          ),
          if (jt.level > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'L${jt.level}',
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          if (jt.reportsToIds.length > 1) ...[
            const SizedBox(width: 4),
            Tooltip(
              message: isAr
                  ? '${jt.reportsToIds.length} مدراء'
                  : '${jt.reportsToIds.length} managers',
              child: const Icon(Icons.people_outline,
                  size: 14, color: AppColors.purple),
            ),
          ],
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
// Shared widgets
// ============================================================

class _TopLevelDropZone extends StatelessWidget {
  final String label;
  final bool isHovered;
  final bool Function(String?) onWillAccept;
  final ValueChanged<String?> onLeave;
  final ValueChanged<String> onAccept;

  const _TopLevelDropZone({
    required this.label,
    required this.isHovered,
    required this.onWillAccept,
    required this.onLeave,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => onWillAccept(details.data),
      onLeave: onLeave,
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (_, __, ___) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isHovered
              ? AppColors.success.withOpacity(0.15)
              : Colors.grey.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isHovered
                ? AppColors.success
                : Colors.grey.withOpacity(0.4),
            style: BorderStyle.solid,
            width: isHovered ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.vertical_align_top,
              color: isHovered ? AppColors.success : Colors.grey[600],
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: isHovered ? AppColors.success : Colors.grey[700],
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DraggingChip extends StatelessWidget {
  final String label;
  final IconData icon;
  const _DraggingChip({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.brand,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: AppColors.brand.withOpacity(0.4),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 14),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
