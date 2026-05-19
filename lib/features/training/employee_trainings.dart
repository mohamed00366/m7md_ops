import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/training_settings.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/widgets.dart';

/// 📜 شاشة "تدريباتي" — عرض شخصي للموظف
///
/// يعرض:
///   - الدورات المكتملة (مع شهادات)
///   - الدورات المجدولة
///   - الدورات المنتهية أو المطلوبة
///   - إحصائيّة سريعة (إنجاز كلّي)
class EmployeeTrainings extends StatefulWidget {
  const EmployeeTrainings({super.key});

  @override
  State<EmployeeTrainings> createState() => _EmployeeTrainingsState();
}

class _EmployeeTrainingsState extends State<EmployeeTrainings> {
  @override
  void initState() {
    super.initState();
    MockRepository().addListener(_onChange);
    TrainingSettings.instance.addListener(_onChange);
    TrainingSettings.instance.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
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
    final auth = context.watch<AuthProvider>();
    final repo = MockRepository();
    final empId = auth.currentUser?.employeeId;

    if (empId == null) {
      return EmptyState(
        icon: Icons.person_off,
        message: isAr
            ? 'حسابك ليس مرتبطاً بسجل موظف'
            : 'Your account is not linked to an employee record',
      );
    }

    final emp = repo.employeeById(empId);
    if (emp == null) {
      return EmptyState(
        icon: Icons.error_outline,
        message: isAr ? 'لم يتم العثور على بيانات الموظف' : 'Employee not found',
      );
    }

    final myRecords = repo.trainingRecordsForEmployee(empId);
    final completed = myRecords
        .where((r) => r.status == TrainingStatus.completed && !r.isExpired)
        .toList()
      ..sort((a, b) =>
          (b.completedAt ?? b.scheduledAt).compareTo(a.completedAt ?? a.scheduledAt));
    final scheduled = myRecords
        .where((r) =>
            r.status == TrainingStatus.scheduled ||
            r.status == TrainingStatus.inProgress)
        .toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    final expired = myRecords.where((r) => r.isExpired && r.status == TrainingStatus.completed).toList();

    // الدورات الإلزاميّة المطلوبة لي ولم أكملها
    final myJtId = emp.jobTitleId;
    final missing = <TrainingCourse>[];
    for (final c in repo.trainingCourses) {
      if (!c.isActive) continue;
      if (!c.isMandatory) continue;
      if (c.requiredForJobTitleIds.isNotEmpty &&
          (myJtId == null || !c.requiredForJobTitleIds.contains(myJtId))) {
        continue;
      }
      final rec = repo.latestRecordFor(empId, c.id);
      if (rec == null ||
          rec.status != TrainingStatus.completed ||
          rec.isExpired) {
        missing.add(c);
      }
    }

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // KPI ملخّص
          _SummaryCard(
            employee: emp,
            completed: completed.length,
            scheduled: scheduled.length,
            expired: expired.length,
            missing: missing.length,
          ),
          const SizedBox(height: 14),
          if (missing.isNotEmpty) ...[
            _SectionTitle(
              isAr ? '⛔ دورات إلزاميّة مطلوبة' : '⛔ Required mandatory',
              AppColors.danger,
            ),
            ...missing.map((c) => _MissingCourseTile(course: c)),
            const SizedBox(height: 14),
          ],
          if (expired.isNotEmpty) ...[
            _SectionTitle(
              isAr ? '⚠️ منتهية الصلاحيّة' : '⚠️ Expired',
              AppColors.warning,
            ),
            ...expired.map((r) => _RecordTile(record: r, expired: true)),
            const SizedBox(height: 14),
          ],
          if (scheduled.isNotEmpty) ...[
            _SectionTitle(
              isAr ? '📅 مجدولة' : '📅 Scheduled',
              AppColors.info,
            ),
            ...scheduled.map((r) => _RecordTile(record: r)),
            const SizedBox(height: 14),
          ],
          if (completed.isNotEmpty) ...[
            _SectionTitle(
              isAr ? '✅ مكتملة' : '✅ Completed',
              AppColors.success,
            ),
            ...completed.map((r) => _RecordTile(record: r)),
          ],
          if (completed.isEmpty &&
              scheduled.isEmpty &&
              expired.isEmpty &&
              missing.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                isAr
                    ? 'لا توجد تدريبات مسجّلة لك بعد'
                    : 'No trainings recorded for you yet',
                textAlign: TextAlign.center,
                style:
                    TextStyle(color: Theme.of(context).disabledColor),
              ),
            ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final Employee employee;
  final int completed;
  final int scheduled;
  final int expired;
  final int missing;

  const _SummaryCard({
    required this.employee,
    required this.completed,
    required this.scheduled,
    required this.expired,
    required this.missing,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final total = completed + scheduled + expired + missing;
    final rate = total == 0 ? 0.0 : completed / total;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.brand, AppColors.brand.withOpacity(0.7)],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppAvatar(initials: employee.initials, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      employee.fullName,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.white),
                    ),
                    Text(
                      isAr ? 'تدريباتي' : 'My Trainings',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withOpacity(0.85)),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${(rate * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _MiniStat(label: isAr ? 'مكتملة' : 'Done', value: '$completed'),
              _MiniStat(label: isAr ? 'مجدولة' : 'Sched', value: '$scheduled'),
              _MiniStat(label: isAr ? 'منتهية' : 'Exp', value: '$expired'),
              _MiniStat(label: isAr ? 'مطلوبة' : 'Need', value: '$missing'),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  const _MiniStat({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Colors.white)),
          Text(label,
              style: TextStyle(
                  fontSize: 10, color: Colors.white.withOpacity(0.8))),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final Color color;
  const _SectionTitle(this.title, this.color);
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

class _MissingCourseTile extends StatelessWidget {
  final TrainingCourse course;
  const _MissingCourseTile({required this.course});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.danger.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.danger.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.priority_high,
              color: AppColors.danger, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(course.displayName(isAr),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800)),
                Text(
                  '${course.code} • ${isAr ? course.category.arabicLabel() : course.category.englishLabel()}',
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
          Text(
            isAr ? 'إلزاميّة' : 'Required',
            style: const TextStyle(
                fontSize: 10,
                color: AppColors.danger,
                fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  final TrainingRecord record;
  final bool expired;
  const _RecordTile({required this.record, this.expired = false});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final repo = MockRepository();
    final course = repo.trainingCourseById(record.courseId);
    final color = expired
        ? AppColors.warning
        : record.status == TrainingStatus.completed
            ? AppColors.success
            : AppColors.info;

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
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(_iconFor(record.effectiveStatus),
                color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    course?.displayName(isAr) ?? '—',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800)),
                Row(
                  children: [
                    if (record.completedAt != null)
                      Text(
                        '${isAr ? "مكتملة" : "Done"}: ${_fmt(record.completedAt!)}',
                        style: const TextStyle(fontSize: 10),
                      )
                    else
                      Text(
                        '${isAr ? "مجدولة" : "Sched"}: ${_fmt(record.scheduledAt)}',
                        style: const TextStyle(fontSize: 10),
                      ),
                    if (record.expiresAt != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        '${isAr ? "تنتهي" : "Exp"}: ${_fmt(record.expiresAt!)}',
                        style: TextStyle(
                            fontSize: 10,
                            color: expired
                                ? AppColors.danger
                                : Theme.of(context).disabledColor),
                      ),
                    ],
                  ],
                ),
                if (record.score != null)
                  Text(
                    '${isAr ? "الدرجة" : "Score"}: ${record.score!.toStringAsFixed(0)}',
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w800),
                  ),
              ],
            ),
          ),
          if (record.certificateUrl != null)
            const Icon(Icons.workspace_premium,
                size: 18, color: AppColors.brand),
        ],
      ),
    );
  }

  IconData _iconFor(TrainingStatus s) {
    switch (s) {
      case TrainingStatus.scheduled:
        return Icons.event;
      case TrainingStatus.inProgress:
        return Icons.hourglass_top;
      case TrainingStatus.completed:
        return Icons.check_circle;
      case TrainingStatus.expired:
        return Icons.warning_amber;
      case TrainingStatus.cancelled:
        return Icons.cancel;
    }
  }

  String _fmt(DateTime d) =>
      '${d.day}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
