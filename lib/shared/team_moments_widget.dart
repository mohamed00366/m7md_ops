import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/l10n/app_strings.dart';
import '../core/providers/auth_provider.dart';
import '../core/theme/app_colors.dart';
import '../features/admin/employee_profile_screen.dart';
import '../models/models.dart';
import '../repositories/mock_repository.dart';

/// 🎉 ودجت "لحظات الفريق" (Team Moments) — Session 22
///
/// تظهر على SmartHome وتُسلّط الضوء على:
///   - 🎂 أعياد الميلاد هذا الأسبوع (تقويم سنوي)
///   - 🎉 الموظفون الجدد هذا الشهر
///   - 🏆 ذكريات الانضمام (1 سنة، 5، 10) هذا الشهر
///
/// تستخدم Employee.birthDate و Employee.joiningDate الموجودة بالنموذج.
/// تتفلتر بالدولة الحالية (يرى المستخدم فقط زملاء دولته).
class TeamMomentsWidget extends StatelessWidget {
  const TeamMomentsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final isUr = s.isUr;
    final auth = context.watch<AuthProvider>();
    final repo = MockRepository();

    // فلتر بالدولة
    final activeCountry = auth.activeCountryId;
    var employees = repo.employees.toList();
    if (activeCountry != null) {
      employees = employees.where((e) => e.countryId == activeCountry).toList();
    }

    final today = DateTime.now();
    final weekAhead = today.add(const Duration(days: 7));

    // 🎂 أعياد الميلاد هذا الأسبوع (تقويم سنوي)
    final birthdays = employees.where((e) {
      if (e.birthDate == null) return false;
      return _isAnniversaryWithinDays(e.birthDate!, today, 7);
    }).toList()
      ..sort((a, b) => _daysUntilAnniversary(a.birthDate!, today)
          .compareTo(_daysUntilAnniversary(b.birthDate!, today)));

    // 🎉 موظفون انضمّوا هذا الشهر
    final newHires = employees.where((e) {
      if (e.joiningDate == null) return false;
      final j = e.joiningDate!;
      return j.year == today.year && j.month == today.month;
    }).toList()
      ..sort((a, b) => b.joiningDate!.compareTo(a.joiningDate!));

    // 🏆 ذكريات انضمام (1, 5, 10 سنوات) هذا الشهر
    final anniversaries = employees.where((e) {
      if (e.joiningDate == null) return false;
      final j = e.joiningDate!;
      if (j.month != today.month) return false;
      final yearsAgo = today.year - j.year;
      return yearsAgo > 0 && (yearsAgo == 1 || yearsAgo == 5 || yearsAgo == 10);
    }).toList()
      ..sort((a, b) => b.joiningDate!.day.compareTo(a.joiningDate!.day));

    // إن لم يكن هناك شيء — لا تعرض
    if (birthdays.isEmpty && newHires.isEmpty && anniversaries.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.gold.withValues(alpha: 0.10),
            AppColors.brand.withValues(alpha: 0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.celebration_outlined,
                  color: AppColors.gold, size: 20),
              const SizedBox(width: 6),
              Text(
                isUr
                    ? '🎉 ٹیم لمحات'
                    : isAr
                        ? '🎉 لحظات الفريق'
                        : '🎉 Team Moments',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          if (birthdays.isNotEmpty) ...[
            const SizedBox(height: 12),
            _SectionTitle(
                emoji: '🎂',
                titleAr: 'أعياد ميلاد هذا الأسبوع',
                titleEn: 'Birthdays this week',
                titleUr: 'اس ہفتے کی سالگرہ',
                count: birthdays.length,
                isAr: isAr,
                isUr: isUr),
            const SizedBox(height: 6),
            for (final e in birthdays.take(5))
              _BirthdayRow(employee: e, today: today, isAr: isAr, isUr: isUr),
            if (birthdays.length > 5) _moreText(birthdays.length - 5, isAr, isUr),
          ],
          if (newHires.isNotEmpty) ...[
            const SizedBox(height: 12),
            _SectionTitle(
                emoji: '👋',
                titleAr: 'موظفون جدد هذا الشهر',
                titleEn: 'New hires this month',
                titleUr: 'اس ماہ کے نئے ملازمین',
                count: newHires.length,
                isAr: isAr,
                isUr: isUr),
            const SizedBox(height: 6),
            for (final e in newHires.take(5))
              _NewHireRow(employee: e, isAr: isAr, isUr: isUr),
            if (newHires.length > 5) _moreText(newHires.length - 5, isAr, isUr),
          ],
          if (anniversaries.isNotEmpty) ...[
            const SizedBox(height: 12),
            _SectionTitle(
                emoji: '🏆',
                titleAr: 'ذكريات الانضمام',
                titleEn: 'Work anniversaries',
                titleUr: 'کام کی سالگرہ',
                count: anniversaries.length,
                isAr: isAr,
                isUr: isUr),
            const SizedBox(height: 6),
            for (final e in anniversaries.take(5))
              _AnniversaryRow(employee: e, today: today, isAr: isAr, isUr: isUr),
            if (anniversaries.length > 5) _moreText(anniversaries.length - 5, isAr, isUr),
          ],
        ],
      ),
    );
  }

  Widget _moreText(int count, bool isAr, bool isUr) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 8, right: 8),
      child: Text(
        isUr
            ? '+$count اور'
            : isAr
                ? '+$count آخرين'
                : '+$count more',
        style: TextStyle(
            fontSize: 10,
            color: Colors.grey[700],
            fontWeight: FontWeight.w700),
      ),
    );
  }

  /// هل اليوم/الذكرى السنويّة ضمن [days] أيام قادمة؟
  static bool _isAnniversaryWithinDays(DateTime original, DateTime now, int days) {
    final daysUntil = _daysUntilAnniversary(original, now);
    return daysUntil >= 0 && daysUntil <= days;
  }

  /// عدد الأيام المتبقّية لذكرى التاريخ السنويّة
  static int _daysUntilAnniversary(DateTime original, DateTime now) {
    var nextOccurrence = DateTime(now.year, original.month, original.day);
    if (nextOccurrence.isBefore(DateTime(now.year, now.month, now.day))) {
      nextOccurrence = DateTime(now.year + 1, original.month, original.day);
    }
    return nextOccurrence.difference(DateTime(now.year, now.month, now.day)).inDays;
  }
}

// ============================================================
// Helpers
// ============================================================

class _SectionTitle extends StatelessWidget {
  final String emoji;
  final String titleAr;
  final String titleEn;
  final String titleUr;
  final int count;
  final bool isAr;
  final bool isUr;

  const _SectionTitle({
    required this.emoji,
    required this.titleAr,
    required this.titleEn,
    required this.titleUr,
    required this.count,
    required this.isAr,
    required this.isUr,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 4),
        Text(
          isUr ? titleUr : (isAr ? titleAr : titleEn),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: AppColors.gold.withValues(alpha: 0.20),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: AppColors.gold,
            ),
          ),
        ),
      ],
    );
  }
}

class _BirthdayRow extends StatelessWidget {
  final Employee employee;
  final DateTime today;
  final bool isAr;
  final bool isUr;

  const _BirthdayRow({
    required this.employee,
    required this.today,
    required this.isAr,
    required this.isUr,
  });

  @override
  Widget build(BuildContext context) {
    final bd = employee.birthDate!;
    final daysUntil = _TeamMoments._days(bd, today);
    final whenLabel = _whenLabel(daysUntil, isAr, isUr);
    final age = today.year - bd.year - (daysUntil > 0 ? 0 : 0);
    return _BaseRow(
      employee: employee,
      icon: Icons.cake_outlined,
      iconColor: AppColors.gold,
      primaryText: employee.fullName,
      secondaryText: isUr
          ? '${age + 1} سال کا ہو رہا ہے'
          : isAr
              ? 'سيُكمل ${age + 1} سنة'
              : 'Turning ${age + 1}',
      trailingText: whenLabel,
      isAr: isAr,
    );
  }

  String _whenLabel(int daysUntil, bool isAr, bool isUr) {
    if (daysUntil == 0) {
      return isUr ? 'آج 🎂' : (isAr ? 'اليوم 🎂' : 'Today 🎂');
    }
    if (daysUntil == 1) {
      return isUr ? 'کل' : (isAr ? 'غداً' : 'Tomorrow');
    }
    if (isUr) return '$daysUntil دن میں';
    if (isAr) return 'بعد $daysUntil أيام';
    return 'In $daysUntil days';
  }
}

class _NewHireRow extends StatelessWidget {
  final Employee employee;
  final bool isAr;
  final bool isUr;

  const _NewHireRow({required this.employee, required this.isAr, required this.isUr});

  @override
  Widget build(BuildContext context) {
    final j = employee.joiningDate!;
    final repo = MockRepository();
    final jt = employee.jobTitleId == null
        ? null
        : repo.jobTitleById(employee.jobTitleId);
    return _BaseRow(
      employee: employee,
      icon: Icons.waving_hand_outlined,
      iconColor: AppColors.success,
      primaryText: employee.fullName,
      secondaryText: jt == null
          ? '${j.day}/${j.month}'
          : '${jt.displayName(isAr)} • ${j.day}/${j.month}',
      trailingText: isUr ? 'شامل ہوا' : (isAr ? 'انضمّ' : 'Joined'),
      isAr: isAr,
    );
  }
}

class _AnniversaryRow extends StatelessWidget {
  final Employee employee;
  final DateTime today;
  final bool isAr;
  final bool isUr;

  const _AnniversaryRow({
    required this.employee,
    required this.today,
    required this.isAr,
    required this.isUr,
  });

  @override
  Widget build(BuildContext context) {
    final j = employee.joiningDate!;
    final years = today.year - j.year;
    return _BaseRow(
      employee: employee,
      icon: Icons.workspace_premium_outlined,
      iconColor: AppColors.purple,
      primaryText: employee.fullName,
      secondaryText: isUr
          ? '$years سال ٹیم کے ساتھ'
          : isAr
              ? '$years سنة في الفريق'
              : '$years year${years == 1 ? '' : 's'} with team',
      trailingText: '🏆 $years',
      isAr: isAr,
    );
  }
}

class _BaseRow extends StatelessWidget {
  final Employee employee;
  final IconData icon;
  final Color iconColor;
  final String primaryText;
  final String secondaryText;
  final String trailingText;
  final bool isAr;

  const _BaseRow({
    required this.employee,
    required this.icon,
    required this.iconColor,
    required this.primaryText,
    required this.secondaryText,
    required this.trailingText,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => EmployeeProfileScreen(employee: employee),
      )),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: iconColor.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    primaryText,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w800),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    secondaryText,
                    style: const TextStyle(
                        fontSize: 10, color: Colors.grey),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                trailingText,
                style: TextStyle(
                  color: iconColor,
                  fontSize: 10,
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

class _TeamMoments {
  static int _days(DateTime original, DateTime now) {
    var nextOccurrence = DateTime(now.year, original.month, original.day);
    if (nextOccurrence.isBefore(DateTime(now.year, now.month, now.day))) {
      nextOccurrence =
          DateTime(now.year + 1, original.month, original.day);
    }
    return nextOccurrence.difference(DateTime(now.year, now.month, now.day)).inDays;
  }
}
