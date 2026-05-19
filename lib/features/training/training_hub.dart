import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/training_settings.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/widgets.dart';
import 'training_course_editor.dart';
import 'training_record_editor.dart';

/// 📜 مركز التدريب الموحّد
///
/// 4 تابات:
///   1. الكتالوج (دورات + CRUD)
///   2. السجلّات (موظف × دورة)
///   3. صلاحيّة منتهية / تنتهي قريباً
///   4. الإحصائيات
class TrainingHub extends StatefulWidget {
  const TrainingHub({super.key});

  @override
  State<TrainingHub> createState() => _TrainingHubState();
}

class _TrainingHubState extends State<TrainingHub>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    MockRepository().addListener(_onChange);
    TrainingSettings.instance.addListener(_onChange);
    TrainingSettings.instance.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    MockRepository().removeListener(_onChange);
    TrainingSettings.instance.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final repo = MockRepository();

    return Scaffold(
      body: Column(
        children: [
          Container(
            color: Theme.of(context).cardTheme.color,
            child: TabBar(
              controller: _tabs,
              isScrollable: true,
              labelColor: AppColors.brand,
              unselectedLabelColor: Theme.of(context).disabledColor,
              indicatorColor: AppColors.brand,
              tabs: [
                Tab(
                  icon: const Icon(Icons.menu_book, size: 16),
                  text: '${isAr ? "الكتالوج" : "Catalog"} (${repo.trainingCourses.length})',
                ),
                Tab(
                  icon: const Icon(Icons.assignment_turned_in, size: 16),
                  text: '${isAr ? "السجلّات" : "Records"} (${repo.trainingRecords.length})',
                ),
                Tab(
                  icon: const Icon(Icons.warning_amber, size: 16),
                  text:
                      '${isAr ? "تنتهي/منتهية" : "Expiring"} (${_expiringCount(repo)})',
                ),
                Tab(
                  icon: const Icon(Icons.bar_chart, size: 16),
                  text: isAr ? 'الإحصائيات' : 'Stats',
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _CatalogTab(query: _query, onQuery: (v) => setState(() => _query = v)),
                _RecordsTab(query: _query, onQuery: (v) => setState(() => _query = v)),
                _ExpiringTab(),
                _StatsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _expiringCount(MockRepository repo) {
    final days = TrainingSettings.instance.daysWarning;
    return repo.trainingExpiringSoon(days).length + repo.trainingExpired().length;
  }
}

// ============================================================
// تاب ١: الكتالوج
// ============================================================
class _CatalogTab extends StatelessWidget {
  final String query;
  final ValueChanged<String> onQuery;
  const _CatalogTab({required this.query, required this.onQuery});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final repo = MockRepository();
    final auth = context.read<AuthProvider>();
    final canManage = auth.isSuperAdmin || auth.permissions.contains('training.manage');

    final filtered = repo.trainingCourses.where((c) {
      if (query.isEmpty) return true;
      final q = query.toLowerCase();
      return c.code.toLowerCase().contains(q) ||
          c.nameAr.toLowerCase().contains(q) ||
          c.nameEn.toLowerCase().contains(q);
    }).toList()
      ..sort((a, b) => a.nameAr.compareTo(b.nameAr));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: s.search,
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                  ),
                  onChanged: onQuery,
                ),
              ),
              const SizedBox(width: 8),
              if (canManage)
                ElevatedButton.icon(
                  onPressed: () => _editCourse(context, null),
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(isAr ? 'دورة جديدة' : 'New Course'),
                ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? EmptyState(
                  icon: Icons.menu_book,
                  message: isAr
                      ? 'لا توجد دورات بعد'
                      : 'No courses yet',
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final c = filtered[i];
                    return _CourseCard(
                      course: c,
                      canManage: canManage,
                      onEdit: () => _editCourse(context, c),
                      onDelete: () => _deleteCourse(context, c),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _editCourse(BuildContext context, TrainingCourse? existing) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TrainingCourseEditor(existing: existing),
    ));
  }

  Future<void> _deleteCourse(BuildContext context, TrainingCourse c) async {
    final s = AppStrings.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(s.confirm),
        content: Text(s.isAr
            ? 'حذف الدورة "${c.nameAr}" وكل سجلاتها؟'
            : 'Delete course "${c.nameEn}" and its records?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(s.cancel)),
          ElevatedButton(
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(s.delete)),
        ],
      ),
    );
    if (ok == true) {
      MockRepository().deleteTrainingCourse(c.id);
    }
  }
}

class _CourseCard extends StatelessWidget {
  final TrainingCourse course;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _CourseCard({
    required this.course,
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final repo = MockRepository();
    final completion = repo.trainingCompletionRate(course.id);
    final needs = repo.employeesNeedingCourse(course).length;
    final color = course.isMandatory ? AppColors.danger : AppColors.brand;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    course.code,
                    style: TextStyle(
                        fontSize: 11,
                        color: color,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    course.displayName(isAr),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                ),
                if (course.isMandatory)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.danger,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      isAr ? 'إلزاميّة' : 'Mandatory',
                      style: const TextStyle(
                          fontSize: 9,
                          color: Colors.white,
                          fontWeight: FontWeight.w800),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // فئة + مدّة + صلاحيّة
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _Chip(
                      icon: Icons.category,
                      label: isAr
                          ? course.category.arabicLabel()
                          : course.category.englishLabel(),
                      color: AppColors.info,
                    ),
                    _Chip(
                      icon: Icons.access_time,
                      label:
                          '${course.durationHours.toStringAsFixed(0)}h',
                      color: AppColors.warning,
                    ),
                    _Chip(
                      icon: Icons.event_available,
                      label: course.validityMonths == 0
                          ? (isAr ? 'بلا انتهاء' : 'Never')
                          : (isAr
                              ? '${course.validityMonths} شهر'
                              : '${course.validityMonths}mo'),
                      color: AppColors.success,
                    ),
                    if (course.requiredForJobTitleIds.isNotEmpty)
                      _Chip(
                        icon: Icons.badge,
                        label:
                            '${course.requiredForJobTitleIds.length} ${isAr ? "مسمّى" : "titles"}',
                        color: AppColors.brand,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                // نسبة الإنجاز
                Row(
                  children: [
                    Text(
                      isAr
                          ? 'الإنجاز: ${(completion * 100).toStringAsFixed(0)}%'
                          : 'Completion: ${(completion * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w800),
                    ),
                    const Spacer(),
                    if (needs > 0)
                      Text(
                        isAr
                            ? '$needs يحتاجها'
                            : '$needs need it',
                        style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.warning,
                            fontWeight: FontWeight.w700),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: completion,
                    minHeight: 6,
                    backgroundColor: AppColors.success.withOpacity(0.1),
                    valueColor:
                        const AlwaysStoppedAnimation(AppColors.success),
                  ),
                ),
                if (canManage) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onEdit,
                          icon: const Icon(Icons.edit, size: 14),
                          label: Text(s.edit,
                              style: const TextStyle(fontSize: 11)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.danger),
                          onPressed: onDelete,
                          icon: const Icon(Icons.delete, size: 14),
                          label: Text(s.delete,
                              style: const TextStyle(fontSize: 11)),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// تاب ٢: السجلّات (موظف × دورة)
// ============================================================
class _RecordsTab extends StatelessWidget {
  final String query;
  final ValueChanged<String> onQuery;
  const _RecordsTab({required this.query, required this.onQuery});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final repo = MockRepository();
    final auth = context.read<AuthProvider>();
    final canRecord =
        auth.isSuperAdmin || auth.permissions.contains('training.record');

    final records = [...repo.trainingRecords]
      ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));
    final filtered = records.where((r) {
      if (query.isEmpty) return true;
      final emp = repo.employeeById(r.employeeId);
      final course = repo.trainingCourseById(r.courseId);
      final q = query.toLowerCase();
      return (emp?.fullName.toLowerCase().contains(q) ?? false) ||
          (emp?.code.toLowerCase().contains(q) ?? false) ||
          (course?.code.toLowerCase().contains(q) ?? false) ||
          (course?.nameAr.toLowerCase().contains(q) ?? false);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: s.search,
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                  ),
                  onChanged: onQuery,
                ),
              ),
              const SizedBox(width: 8),
              if (canRecord)
                ElevatedButton.icon(
                  onPressed: () => _addRecord(context),
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(isAr ? 'تسجيل' : 'Record'),
                ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? EmptyState(
                  icon: Icons.assignment_outlined,
                  message: isAr ? 'لا توجد سجلّات' : 'No records',
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) =>
                      _RecordRow(record: filtered[i], canManage: canRecord),
                ),
        ),
      ],
    );
  }

  Future<void> _addRecord(BuildContext context) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const TrainingRecordEditor(existing: null),
    ));
  }
}

class _RecordRow extends StatelessWidget {
  final TrainingRecord record;
  final bool canManage;
  const _RecordRow({required this.record, required this.canManage});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final repo = MockRepository();
    final emp = repo.employeeById(record.employeeId);
    final course = repo.trainingCourseById(record.courseId);
    final eff = record.effectiveStatus;
    final color = _statusColor(eff);

    return InkWell(
      onTap: !canManage
          ? null
          : () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => TrainingRecordEditor(existing: record),
              )),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(
          children: [
            AppAvatar(
                initials: emp?.initials ?? '?',
                color: color,
                radius: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(emp?.fullName ?? '—',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w800)),
                  if (course != null)
                    Text(
                      '${course.code} • ${course.displayName(isAr)}',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.brand),
                    ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        record.completedAt != null
                            ? _fmt(record.completedAt!)
                            : (isAr
                                ? 'مجدولة: ${_fmt(record.scheduledAt)}'
                                : 'Sched: ${_fmt(record.scheduledAt)}'),
                        style: const TextStyle(fontSize: 10),
                      ),
                      const SizedBox(width: 6),
                      if (record.expiresAt != null)
                        Text(
                          isAr
                              ? '— تنتهي ${_fmt(record.expiresAt!)}'
                              : '— exp ${_fmt(record.expiresAt!)}',
                          style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.textTertiaryLight),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                isAr ? eff.arabicLabel() : eff.englishLabel(),
                style: TextStyle(
                    fontSize: 10,
                    color: color,
                    fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.day}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Color _statusColor(TrainingStatus s) {
    return switch (s) {
      TrainingStatus.scheduled => AppColors.info,
      TrainingStatus.inProgress => AppColors.warning,
      TrainingStatus.completed => AppColors.success,
      TrainingStatus.expired => AppColors.danger,
      TrainingStatus.cancelled => AppColors.textTertiaryLight,
    };
  }
}

// ============================================================
// تاب ٣: تنتهي / منتهية
// ============================================================
class _ExpiringTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final repo = MockRepository();
    final days = TrainingSettings.instance.daysWarning;
    final expired = repo.trainingExpired();
    final expiring = repo.trainingExpiringSoon(days);

    if (expired.isEmpty && expiring.isEmpty) {
      return EmptyState(
        icon: Icons.check_circle,
        message: isAr
            ? 'لا توجد دورات تحتاج انتباه'
            : 'No trainings need attention',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        if (expired.isNotEmpty) ...[
          _SectionHeader(
            title: isAr
                ? '⛔ منتهية الصلاحيّة (${expired.length})'
                : '⛔ Expired (${expired.length})',
            color: AppColors.danger,
          ),
          ...expired.map((r) => _ExpiringRow(record: r, expired: true)),
          const SizedBox(height: 10),
        ],
        if (expiring.isNotEmpty) ...[
          _SectionHeader(
            title: isAr
                ? '⚠️ تنتهي خلال $days يوم (${expiring.length})'
                : '⚠️ Expires in $days days (${expiring.length})',
            color: AppColors.warning,
          ),
          ...expiring.map((r) => _ExpiringRow(record: r, expired: false)),
        ],
      ],
    );
  }
}

class _ExpiringRow extends StatelessWidget {
  final TrainingRecord record;
  final bool expired;
  const _ExpiringRow({required this.record, required this.expired});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final repo = MockRepository();
    final emp = repo.employeeById(record.employeeId);
    final course = repo.trainingCourseById(record.courseId);
    final color = expired ? AppColors.danger : AppColors.warning;
    final days = record.daysUntilExpiry ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(
              expired ? Icons.cancel : Icons.warning_amber,
              color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(emp?.fullName ?? '—',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w800)),
                if (course != null)
                  Text(course.displayName(isAr),
                      style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              expired
                  ? (isAr ? 'منذ ${-days} يوم' : '${-days}d ago')
                  : (isAr ? 'خلال $days يوم' : 'in ${days}d'),
              style: const TextStyle(
                  fontSize: 10,
                  color: Colors.white,
                  fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// تاب ٤: الإحصائيات
// ============================================================
class _StatsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final repo = MockRepository();
    final totalCourses = repo.trainingCourses.length;
    final mandatoryCourses =
        repo.trainingCourses.where((c) => c.isMandatory).length;
    final totalRecords = repo.trainingRecords.length;
    final completed = repo.trainingRecords
        .where((r) => r.status == TrainingStatus.completed && !r.isExpired)
        .length;
    final overallRate =
        totalRecords == 0 ? 0.0 : completed / totalRecords;

    // مصفوفة Coverage
    final activeEmps =
        repo.employees.where((e) => e.status == EntityStatus.active).toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // KPIs
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          childAspectRatio: 2.4,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          children: [
            _Kpi(
                label: isAr ? 'الدورات' : 'Courses',
                value: '$totalCourses',
                color: AppColors.brand,
                icon: Icons.menu_book),
            _Kpi(
                label: isAr ? 'إلزاميّة' : 'Mandatory',
                value: '$mandatoryCourses',
                color: AppColors.danger,
                icon: Icons.priority_high),
            _Kpi(
                label: isAr ? 'السجلّات' : 'Records',
                value: '$totalRecords',
                color: AppColors.info,
                icon: Icons.assignment_turned_in),
            _Kpi(
                label: isAr ? 'الإنجاز' : 'Complete',
                value: '${(overallRate * 100).toStringAsFixed(0)}%',
                color: AppColors.success,
                icon: Icons.check_circle),
          ],
        ),
        const SizedBox(height: 14),
        // أزرار التصدير
        OutlinedButton.icon(
          onPressed: () => _exportCsv(context, repo),
          icon: const Icon(Icons.download, size: 16),
          label: Text(isAr ? 'تصدير CSV' : 'Export CSV'),
        ),
        const SizedBox(height: 14),
        // Coverage Matrix (دورات × موظفين)
        if (repo.trainingCourses.isNotEmpty &&
            activeEmps.isNotEmpty) ...[
          Text(
            isAr ? '📊 مصفوفة التغطية' : '📊 Coverage Matrix',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          ...repo.trainingCourses.map((c) {
            final completion = repo.trainingCompletionRate(c.id);
            final needs = repo.employeesNeedingCourse(c).length;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(c.displayName(isAr),
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800)),
                      ),
                      Text(
                        '${(completion * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: completion > 0.8
                              ? AppColors.success
                              : completion > 0.5
                                  ? AppColors.warning
                                  : AppColors.danger,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: completion,
                      minHeight: 6,
                      backgroundColor:
                          AppColors.brand.withOpacity(0.1),
                      valueColor: AlwaysStoppedAnimation(
                        completion > 0.8
                            ? AppColors.success
                            : completion > 0.5
                                ? AppColors.warning
                                : AppColors.danger,
                      ),
                    ),
                  ),
                  if (needs > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      isAr
                          ? '$needs موظف يحتاج هذه الدورة'
                          : '$needs employees need this',
                      style: const TextStyle(
                          fontSize: 10, color: AppColors.warning),
                    ),
                  ],
                ],
              ),
            );
          }),
        ],
      ],
    );
  }

  void _exportCsv(BuildContext context, MockRepository repo) {
    final s = AppStrings.of(context);
    final lines = <String>[
      'Employee,Code,Course,CourseCode,Status,Completed,Expires,Score,Passed',
    ];
    for (final r in repo.trainingRecords) {
      final emp = repo.employeeById(r.employeeId);
      final c = repo.trainingCourseById(r.courseId);
      lines.add([
        emp?.fullName ?? '',
        emp?.code ?? '',
        c?.nameEn ?? '',
        c?.code ?? '',
        r.effectiveStatus.englishLabel(),
        r.completedAt?.toIso8601String().substring(0, 10) ?? '',
        r.expiresAt?.toIso8601String().substring(0, 10) ?? '',
        r.score?.toStringAsFixed(0) ?? '',
        r.passed?.toString() ?? '',
      ].map((c) => '"$c"').join(','));
    }
    Clipboard.setData(ClipboardData(text: lines.join('\n')));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(s.isAr
          ? 'نُسخ ${repo.trainingRecords.length} صف للحافظة'
          : 'Copied ${repo.trainingRecords.length} rows to clipboard'),
    ));
  }
}

// ============================================================
// Helpers
// ============================================================
class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _Chip(
      {required this.icon, required this.label, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 10, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  const _Kpi(
      {required this.label,
      required this.value,
      required this.color,
      required this.icon});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(value,
                  style: TextStyle(
                      color: color,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
              Text(label,
                  style: TextStyle(
                      color: color.withOpacity(0.85), fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ]),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Color color;
  const _SectionHeader({required this.title, required this.color});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        title,
        style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w800, color: color),
      ),
    );
  }
}
