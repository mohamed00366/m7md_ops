import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/lookups.dart';
import '../../repositories/mock_repository.dart';
import 'job_title_profile_screen.dart';

/// 📊 شاشة "تغطية المسمّيات الوظيفيّة" (JobTitle Coverage)
///
/// تعرض كلّ مسمّى مع عدد الموظفين الفعليّين عليه.
/// تساعد المسؤول على معرفة:
///   - أيّ المسمّيات لا يوجد عليها موظفون (فجوات)
///   - أيّ المسمّيات مزدحمة بالموظفين
///   - توزيع الموظفين على الهرم
class JobTitleCoverageScreen extends StatefulWidget {
  const JobTitleCoverageScreen({super.key});

  @override
  State<JobTitleCoverageScreen> createState() =>
      _JobTitleCoverageScreenState();
}

class _JobTitleCoverageScreenState extends State<JobTitleCoverageScreen> {
  String _query = '';
  bool _showOnlyEmpty = false;
  int? _filterLevel;

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
    final auth = context.watch<AuthProvider>();
    final repo = MockRepository();
    final activeCountry = auth.activeCountryId;

    // كل المسمّيات
    var titles = repo.jobTitles.where((j) => j.roleId != null).toList();

    // فلتر بالمستوى
    if (_filterLevel != null) {
      titles = titles.where((j) => j.level == _filterLevel).toList();
    }

    // فلتر بالبحث
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      titles = titles
          .where((j) =>
              j.nameAr.toLowerCase().contains(q) ||
              j.nameEn.toLowerCase().contains(q))
          .toList();
    }

    // عداد الموظفين لكلّ مسمّى (مفلتر بالدولة)
    final empCounts = <String, int>{};
    for (final t in titles) {
      empCounts[t.id] = repo.employees.where((e) {
        if (activeCountry != null && e.countryId != activeCountry) {
          return false;
        }
        return e.jobTitleId == t.id;
      }).length;
    }

    // فلتر «الفارغة فقط»
    if (_showOnlyEmpty) {
      titles = titles.where((j) => (empCounts[j.id] ?? 0) == 0).toList();
    }

    // ترتيب: حسب المستوى ثمّ الاسم
    titles.sort((a, b) {
      final lc = a.level.compareTo(b.level);
      if (lc != 0) return lc;
      return a.nameAr.compareTo(b.nameAr);
    });

    // إحصاءات
    final totalTitles = titles.length;
    final filled = titles.where((j) => (empCounts[j.id] ?? 0) > 0).length;
    final empty = totalTitles - filled;
    final coverage = totalTitles > 0
        ? (filled / totalTitles * 100).toStringAsFixed(0)
        : '0';

    final levels = repo.jobTitles
        .where((j) => j.roleId != null)
        .map((j) => j.level)
        .toSet()
        .toList()
      ..sort();

    return Scaffold(
      body: Column(
        children: [
          // ===== Stats banner =====
          Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: _StatCard(
                    icon: Icons.badge_outlined,
                    label: isAr ? 'إجمالي المسمّيات' : 'Total titles',
                    value: '$totalTitles',
                    color: AppColors.brand,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _StatCard(
                    icon: Icons.check_circle_outline,
                    label: isAr ? 'مع موظفين' : 'Filled',
                    value: '$filled',
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _StatCard(
                    icon: Icons.warning_amber_outlined,
                    label: isAr ? 'فارغة' : 'Empty',
                    value: '$empty',
                    color: empty > 0 ? AppColors.warning : AppColors.success,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _StatCard(
                    icon: Icons.percent,
                    label: isAr ? 'تغطية' : 'Coverage',
                    value: '$coverage%',
                    color: AppColors.info,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // ===== Filters =====
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.white,
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: isAr ? '🔍 بحث عن مسمّى...' : '🔍 Search title...',
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterChip(
                        label: isAr ? 'كل المستويات' : 'All levels',
                        selected: _filterLevel == null,
                        onTap: () => setState(() => _filterLevel = null),
                      ),
                      for (final l in levels) ...[
                        const SizedBox(width: 4),
                        _filterChip(
                          label: 'L$l',
                          selected: _filterLevel == l,
                          onTap: () => setState(() => _filterLevel = l),
                        ),
                      ],
                      const SizedBox(width: 12),
                      Container(
                        width: 1,
                        height: 22,
                        color: Colors.grey[300],
                      ),
                      const SizedBox(width: 12),
                      _toggleChip(
                        icon: Icons.warning_amber_outlined,
                        label: isAr ? 'الفارغة فقط' : 'Empty only',
                        selected: _showOnlyEmpty,
                        color: AppColors.warning,
                        onTap: () =>
                            setState(() => _showOnlyEmpty = !_showOnlyEmpty),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // ===== List =====
          Expanded(
            child: titles.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        isAr ? 'لا توجد نتائج' : 'No results',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 30),
                    itemCount: titles.length,
                    itemBuilder: (_, i) {
                      final t = titles[i];
                      final count = empCounts[t.id] ?? 0;
                      return _CoverageRow(
                        jobTitle: t,
                        empCount: count,
                        isAr: isAr,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? AppColors.brand : Colors.grey.withOpacity(0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.brand : Colors.grey.withOpacity(0.4),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : Colors.grey[800],
          ),
        ),
      ),
    );
  }

  Widget _toggleChip({
    required IconData icon,
    required String label,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? color : color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected ? color : color.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: selected ? Colors.white : color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: selected ? Colors.white : color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Helpers
// ============================================================

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _StatCard({
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
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: TextStyle(
                fontSize: 9,
                color: color,
                fontWeight: FontWeight.w700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _CoverageRow extends StatelessWidget {
  final JobTitle jobTitle;
  final int empCount;
  final bool isAr;
  const _CoverageRow({
    required this.jobTitle,
    required this.empCount,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    final color = _hexToColor(jobTitle.color) ?? AppColors.brand;
    final isEmpty = empCount == 0;
    final statusColor = isEmpty ? AppColors.warning : AppColors.success;

    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => JobTitleProfileScreen(jobTitle: jobTitle),
      )),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isEmpty
              ? AppColors.warning.withOpacity(0.05)
              : Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isEmpty
                ? AppColors.warning.withOpacity(0.4)
                : Colors.grey.withOpacity(0.25),
            width: isEmpty ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // شريط لون JobTitle
            Container(
              width: 4,
              height: 40,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            // معلومات
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          jobTitle.displayName(isAr),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w800),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (jobTitle.level > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.15),
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
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        isEmpty
                            ? Icons.warning_amber_outlined
                            : Icons.people_outline,
                        size: 12,
                        color: statusColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isEmpty
                            ? (isAr ? 'لا يوجد موظف' : 'No employees')
                            : (isAr
                                ? '$empCount موظف'
                                : '$empCount employee${empCount == 1 ? '' : 's'}'),
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // عداد دائريّ
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '$empCount',
                style: TextStyle(
                  color: statusColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_forward_ios,
                size: 11, color: Colors.grey[500]),
          ],
        ),
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
