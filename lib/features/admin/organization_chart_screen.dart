import 'package:flutter/material.dart';

import 'package:printing/printing.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/org_chart_pdf_generator.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_palette.dart';
import '../../models/lookups.dart';
import '../../repositories/mock_repository.dart';
import 'department_profile_screen.dart';
import 'job_title_profile_screen.dart';

/// 🏢 شاشة الهيكل التنظيمي
/// عرض شجرة بصريّة:
///   - تبويب «الأقسام»: شجرة Departments بناءً على parent_id
///   - تبويب «الوظائف»: شجرة JobTitles بناءً على reports_to
class OrganizationChartScreen extends StatefulWidget {
  const OrganizationChartScreen({super.key});

  @override
  State<OrganizationChartScreen> createState() =>
      _OrganizationChartScreenState();
}

class _OrganizationChartScreenState extends State<OrganizationChartScreen>
    with TickerProviderStateMixin {
  late final TabController _tab;
  // ignore: unused_field
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    MockRepository().addListener(_onChange);
    // البيانات تأتي من MockRepository (مُحمَّلة في app boot)
  }

  @override
  void dispose() {
    _tab.dispose();
    MockRepository().removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  /// 🆕 Session 14: تصدير الهيكل كـ PDF
  Future<void> _exportPdf() async {
    final s = AppStrings.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      messenger.showSnackBar(SnackBar(
        backgroundColor: AppColors.brand,
        content: Text(s.isAr ? 'جاري التوليد...' : 'Generating...'),
        duration: const Duration(seconds: 1),
      ));
      final bytes = await OrgChartPdfGenerator.generate(isAr: s.isAr);
      if (!mounted) return;
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'org_chart_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        backgroundColor: Colors.red,
        content: Text(s.isAr ? 'فشل التوليد: $e' : 'Failed: $e'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Scaffold(
      backgroundColor: AppPalette.surface,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _exportPdf,
        backgroundColor: AppColors.danger,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
        label: Text(
          s.isAr ? 'تصدير PDF' : 'Export PDF',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        ),
      ),
      body: Column(children: [
        // ===== تبويبات =====
        Container(
          decoration: const BoxDecoration(
            color: AppPalette.card,
            border: Border(bottom: BorderSide(color: AppPalette.border)),
          ),
          child: TabBar(
            controller: _tab,
            indicatorColor: AppColors.brand,
            labelColor: AppColors.brand,
            unselectedLabelColor: AppPalette.textSecondary,
            labelStyle:
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            tabs: [
              Tab(
                  icon: const Icon(Icons.apartment, size: 18),
                  text: s.isAr ? 'حسب الأقسام' : 'By Departments'),
              Tab(
                  icon: const Icon(Icons.account_tree, size: 18),
                  text: s.isAr ? 'حسب الوظائف' : 'By Job Titles'),
            ],
          ),
        ),
        // ===== شريط البحث =====
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: TextField(
            decoration: InputDecoration(
              hintText:
                  s.isAr ? 'بحث في الهيكل...' : 'Search in chart...',
              prefixIcon: const Icon(Icons.search, size: 20),
              filled: true,
              fillColor: AppPalette.card,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _DepartmentsTree(query: _query),
              _JobTitlesTree(query: _query),
            ],
          ),
        ),
      ]),
    );
  }
}

// ============================================================
// 🏛️ شجرة الأقسام
// ============================================================
class _DepartmentsTree extends StatelessWidget {
  final String query;
  const _DepartmentsTree({required this.query});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final roots = repo.rootDepartments();
    if (roots.isEmpty) {
      return _emptyState(s.isAr ? 'لا توجد أقسام' : 'No departments');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
      children: [
        for (final root in roots) _DeptNode(department: root, depth: 0),
        const SizedBox(height: 16),
        _Legend(isAr: s.isAr),
      ],
    );
  }
}

class _DeptNode extends StatefulWidget {
  final Department department;
  final int depth;
  const _DeptNode({required this.department, required this.depth});

  @override
  State<_DeptNode> createState() => _DeptNodeState();
}

class _DeptNodeState extends State<_DeptNode> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final children = repo.childDepartments(widget.department.id);
    final empCount = repo.employees
        .where((e) => e.departmentId == widget.department.id)
        .length;
    final descCount = repo.descendantDepartmentIds(widget.department.id).length;
    final color = _depthColor(widget.depth);

    return Padding(
      padding: EdgeInsets.only(
          right: widget.depth * 16.0, top: widget.depth == 0 ? 0 : 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: children.isEmpty
                  ? () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => DepartmentProfileScreen(
                            department: widget.department),
                      ))
                  : () => setState(() => _expanded = !_expanded),
              onLongPress: () =>
                  Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    DepartmentProfileScreen(department: widget.department),
              )),
              child: Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color.withOpacity(0.30), width: 1.2),
                  boxShadow: widget.depth == 0
                      ? [
                          BoxShadow(
                            color: color.withOpacity(0.10),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Row(children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Icon(Icons.apartment, color: color, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.isAr
                              ? widget.department.nameAr
                              : widget.department.nameEn,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 2),
                        Wrap(
                          spacing: 6,
                          children: [
                            _Mini(
                              icon: Icons.person_outline,
                              label: '$empCount',
                              tip: s.isAr ? 'موظفون مباشرون' : 'Direct employees',
                              color: AppColors.brand,
                            ),
                            if (descCount > 0)
                              _Mini(
                                icon: Icons.account_tree,
                                label: '$descCount',
                                tip: s.isAr
                                    ? 'أقسام فرعيّة'
                                    : 'Sub-departments',
                                color: AppColors.teal,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (children.isNotEmpty)
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      color: AppPalette.textSecondary,
                    ),
                ]),
              ),
            ),
          ),
          // أبناء
          if (_expanded && children.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Column(
                children: [
                  for (final c in children)
                    _DeptNode(department: c, depth: widget.depth + 1),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================
// 🌳 شجرة الوظائف
// ============================================================
class _JobTitlesTree extends StatelessWidget {
  final String query;
  const _JobTitlesTree({required this.query});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final tops = repo.topLevelJobTitles().toList()
      ..sort((a, b) => a.level.compareTo(b.level));
    if (tops.isEmpty) {
      return _emptyState(s.isAr ? 'لا توجد وظائف' : 'No job titles');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
      children: [
        for (final t in tops) _JobNode(jobTitle: t, depth: 0),
        const SizedBox(height: 16),
        _Legend(isAr: s.isAr),
      ],
    );
  }
}

class _JobNode extends StatefulWidget {
  final JobTitle jobTitle;
  final int depth;
  const _JobNode({required this.jobTitle, required this.depth});

  @override
  State<_JobNode> createState() => _JobNodeState();
}

class _JobNodeState extends State<_JobNode> {
  void _openProfile(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => JobTitleProfileScreen(jobTitle: widget.jobTitle),
    ));
  }

  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final subs = repo.subordinatesOf(widget.jobTitle.id);
    final empCount = repo.employees
        .where((e) => e.jobTitleId == widget.jobTitle.id)
        .length;
    final color = _levelColor(widget.jobTitle.level);
    final managers = repo.managersOf(widget.jobTitle.id);

    return Padding(
      padding: EdgeInsets.only(
          right: widget.depth * 16.0, top: widget.depth == 0 ? 0 : 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: subs.isEmpty
                  ? () => _openProfile(context)
                  : () => setState(() => _expanded = !_expanded),
              onLongPress: () => _openProfile(context),
              child: Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color.withOpacity(0.40), width: 1.2),
                  boxShadow: widget.depth == 0
                      ? [
                          BoxShadow(
                            color: color.withOpacity(0.12),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Row(children: [
                  // شارة المستوى
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'L${widget.jobTitle.level}',
                      style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text(
                              s.isAr
                                  ? widget.jobTitle.nameAr
                                  : widget.jobTitle.nameEn,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900),
                            ),
                          ),
                          if (widget.jobTitle.isSupervisor)
                            const Padding(
                              padding: EdgeInsets.only(right: 4),
                              child: Icon(Icons.shield,
                                  size: 12, color: AppColors.gold),
                            ),
                        ]),
                        const SizedBox(height: 3),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            _Mini(
                              icon: Icons.person_outline,
                              label: '$empCount',
                              tip: s.isAr
                                  ? 'موظفون يحملون هذا المسمّى'
                                  : 'Employees',
                              color: AppColors.brand,
                            ),
                            if (subs.isNotEmpty)
                              _Mini(
                                icon: Icons.subdirectory_arrow_right,
                                label: '${subs.length}',
                                tip: s.isAr
                                    ? 'وظائف تتبع له'
                                    : 'Subordinate titles',
                                color: AppColors.teal,
                              ),
                            if (managers.length > 1)
                              _Mini(
                                icon: Icons.group_outlined,
                                label: '${managers.length}',
                                tip: s.isAr
                                    ? 'يتبع لعدّة مدراء'
                                    : 'Multiple managers',
                                color: AppColors.purple,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (subs.isNotEmpty)
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      color: AppPalette.textSecondary,
                    ),
                ]),
              ),
            ),
          ),
          // الوظائف التابعة
          if (_expanded && subs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Column(
                children: [
                  for (final sub in subs)
                    _JobNode(jobTitle: sub, depth: widget.depth + 1),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================
// مساعدات بصريّة
// ============================================================
Color _depthColor(int depth) {
  switch (depth) {
    case 0:
      return AppColors.brand;
    case 1:
      return AppColors.teal;
    case 2:
      return AppColors.purple;
    case 3:
      return AppColors.warning;
    default:
      return AppColors.gold;
  }
}

Color _levelColor(int level) {
  switch (level) {
    case 1:
      return AppColors.brand; // أعلى مستوى
    case 2:
      return AppColors.teal;
    case 3:
      return AppColors.purple;
    case 4:
      return AppColors.warning;
    case 5:
      return AppColors.success;
    default:
      return AppColors.gold;
  }
}

class _Mini extends StatelessWidget {
  final IconData icon;
  final String label;
  final String tip;
  final Color color;
  const _Mini({
    required this.icon,
    required this.label,
    required this.tip,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 2),
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: color)),
        ]),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final bool isAr;
  const _Legend({required this.isAr});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppPalette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isAr ? 'دليل الألوان' : 'Color Guide',
            style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 11,
                color: AppPalette.textSecondary),
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 4, children: [
            _Sw(label: isAr ? 'L1 (إدارة عليا)' : 'L1 (Top)', color: AppColors.brand),
            const _Sw(label: 'L2', color: AppColors.teal),
            const _Sw(label: 'L3', color: AppColors.purple),
            const _Sw(label: 'L4', color: AppColors.warning),
            _Sw(label: isAr ? 'L5 (ميدان)' : 'L5 (Field)', color: AppColors.success),
          ]),
        ],
      ),
    );
  }
}

class _Sw extends StatelessWidget {
  final String label;
  final Color color;
  const _Sw({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      ),
      const SizedBox(width: 4),
      Text(label,
          style: const TextStyle(
              fontSize: 10,
              color: AppPalette.textSecondary,
              fontWeight: FontWeight.w700)),
    ]);
  }
}

Widget _emptyState(String msg) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.account_tree_outlined,
              size: 48, color: AppPalette.textTertiary),
          const SizedBox(height: 8),
          Text(
            msg,
            style: const TextStyle(
                color: AppPalette.textSecondary,
                fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );
}
