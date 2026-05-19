import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/supabase_data_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../models/models.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/widgets.dart';

/// شاشة "روستراتي" - تعرض كل الروسترات بحسب الحالة
/// مع فلاتر للتنقل بين: مسودات / مرسلة / مرفوضة / معتمدة
/// المرفوضة تُعرض بشكل بارز مع سبب الرفض
class SupervisorMyRosters extends StatefulWidget {
  const SupervisorMyRosters({super.key});

  @override
  State<SupervisorMyRosters> createState() => _SupervisorMyRostersState();
}

class _SupervisorMyRostersState extends State<SupervisorMyRosters> {
  RosterStatus? _filter; // null = الكل

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
    final auth = context.watch<AuthProvider>();
    final empId = auth.currentUser?.employeeId;
    final activeCountry = auth.activeCountryId;

    // ===== تحديد نطاق الرؤية =====
    // 1) لو المستخدم موظف (مشرف) لديه نقطة مُسندة → يرى روسترات نقطته فقط
    // 2) لو المستخدم موظف بدون نقطة → "Operation يجب أن يربطك بنقطة"
    // 3) لو المستخدم Operation/Admin/SuperAdmin (بدون employeeId)
    //    → يرى كل الروسترات (مفلترة بدولته النشطة)
    String? supervisorPointId;
    bool isSupervisorMode = false;
    if (empId != null) {
      isSupervisorMode = true;
      try {
        final emp = repo.employees.firstWhere((e) => e.id == empId);
        supervisorPointId = emp.pointId ?? emp.siteId;
      } catch (_) {}
    }

    // 🆕 Manager/Operation/Admin (الذين لديهم rostersSelectAnyPoint)
    //    لا يحتاجون ربط بنقطة — يرون كل النقاط في الدولة.
    final canSeeAllPoints =
        auth.hasPermission(P.rostersSelectAnyPoint) ||
            auth.hasPermission(P.rostersApprove) ||
            auth.isSuperAdmin;

    if (isSupervisorMode &&
        supervisorPointId == null &&
        !canSeeAllPoints) {
      return EmptyState(
        icon: Icons.location_off,
        message: s.isAr
            ? 'لم يتم ربطك بنقطة بعد. تواصل مع Operation'
            : 'You\'re not assigned to a Point. Contact Operation',
      );
    }
    // إذا كان Manager/Operation بدون نقطة → نتعامل معه كـ Admin
    if (supervisorPointId == null && canSeeAllPoints) {
      isSupervisorMode = false;
    }

    // فلترة الروسترات
    var allRosters = repo.rosters.where((r) {
      // وضع المشرف: فقط روسترات نقطته
      if (supervisorPointId != null) {
        return r.siteId == supervisorPointId;
      }
      // وضع Operation/Admin/SuperAdmin: فلترة بالدولة
      if (activeCountry != null) {
        final point = repo.pointById(r.siteId);
        if (point?.countryId != activeCountry) return false;
      } else if (!auth.isSuperAdmin) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => b.weekStart.compareTo(a.weekStart));

    final filtered = _filter == null
        ? allRosters
        : allRosters.where((r) => r.status == _filter).toList();

    final counts = {
      RosterStatus.draft:
          allRosters.where((r) => r.status == RosterStatus.draft).length,
      RosterStatus.submitted: allRosters
          .where((r) =>
              r.status == RosterStatus.submitted ||
              r.status == RosterStatus.underReview)
          .length,
      RosterStatus.rejected:
          allRosters.where((r) => r.status == RosterStatus.rejected).length,
      RosterStatus.approved:
          allRosters.where((r) => r.status == RosterStatus.approved).length,
    };

    return Scaffold(
      body: Column(
        children: [
          // إحصائيات سريعة
          Container(
            color: Theme.of(context).cardTheme.color,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _CountBox(
                  label: s.draft,
                  count: counts[RosterStatus.draft] ?? 0,
                  color: AppColors.textTertiaryLight,
                  icon: Icons.edit_note,
                ),
                const SizedBox(width: 6),
                _CountBox(
                  label: s.submitted,
                  count: counts[RosterStatus.submitted] ?? 0,
                  color: AppColors.warning,
                  icon: Icons.hourglass_top,
                ),
                const SizedBox(width: 6),
                _CountBox(
                  label: s.rejected,
                  count: counts[RosterStatus.rejected] ?? 0,
                  color: AppColors.danger,
                  icon: Icons.cancel,
                ),
                const SizedBox(width: 6),
                _CountBox(
                  label: s.approved,
                  count: counts[RosterStatus.approved] ?? 0,
                  color: AppColors.success,
                  icon: Icons.check_circle,
                ),
              ],
            ),
          ),
          // فلاتر
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _FilterChip(
                    label: s.all,
                    selected: _filter == null,
                    color: AppColors.brand,
                    onTap: () => setState(() => _filter = null),
                  ),
                  _FilterChip(
                    label: s.draft,
                    selected: _filter == RosterStatus.draft,
                    color: AppColors.textTertiaryLight,
                    onTap: () =>
                        setState(() => _filter = RosterStatus.draft),
                  ),
                  _FilterChip(
                    label: s.submitted,
                    selected: _filter == RosterStatus.submitted,
                    color: AppColors.warning,
                    onTap: () =>
                        setState(() => _filter = RosterStatus.submitted),
                  ),
                  _FilterChip(
                    label: s.rejected,
                    selected: _filter == RosterStatus.rejected,
                    color: AppColors.danger,
                    onTap: () =>
                        setState(() => _filter = RosterStatus.rejected),
                  ),
                  _FilterChip(
                    label: s.approved,
                    selected: _filter == RosterStatus.approved,
                    color: AppColors.success,
                    onTap: () =>
                        setState(() => _filter = RosterStatus.approved),
                  ),
                ],
              ),
            ),
          ),
          // القائمة
          Expanded(
            child: filtered.isEmpty
                ? EmptyState(
                    icon: Icons.inbox_outlined,
                    message: s.noData,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) =>
                        _RosterListCard(roster: filtered[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _CountBox extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;
  const _CountBox({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 4),
            Text(
              '$count',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            Text(
              label,
              style: TextStyle(color: color, fontSize: 9),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? color : color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(selected ? 1 : 0.3)),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _RosterListCard extends StatelessWidget {
  final WeeklyRoster roster;
  const _RosterListCard({required this.roster});

  Color _statusColor() {
    return switch (roster.status) {
      RosterStatus.draft => AppColors.textTertiaryLight,
      RosterStatus.submitted => AppColors.warning,
      RosterStatus.underReview => AppColors.info,
      RosterStatus.approved => AppColors.success,
      RosterStatus.rejected => AppColors.danger,
    };
  }

  IconData _statusIcon() {
    return switch (roster.status) {
      RosterStatus.draft => Icons.edit_note,
      RosterStatus.submitted => Icons.hourglass_top,
      RosterStatus.underReview => Icons.visibility,
      RosterStatus.approved => Icons.check_circle,
      RosterStatus.rejected => Icons.cancel,
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final color = _statusColor();
    final isRejected = roster.status == RosterStatus.rejected;
    final isDraft = roster.status == RosterStatus.draft;

    final endDate = roster.weekStart.add(const Duration(days: 6));

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isRejected || isDraft
              ? color.withOpacity(0.5)
              : Theme.of(context).dividerColor,
          width: isRejected || isDraft ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(_statusIcon(), color: color, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_fmt(roster.weekStart)} - ${_fmt(endDate)}',
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(Icons.people,
                                  size: 11, color: Theme.of(context).disabledColor),
                              const SizedBox(width: 3),
                              Text(
                                '${roster.assignments.map((a) => a.employeeId).toSet().length}',
                                style: const TextStyle(fontSize: 11),
                              ),
                              const SizedBox(width: 8),
                              Icon(Icons.access_time,
                                  size: 11,
                                  color: Theme.of(context).disabledColor),
                              const SizedBox(width: 3),
                              Text(
                                '${roster.totalHours.toStringAsFixed(0)}h',
                                style: const TextStyle(fontSize: 11),
                              ),
                              const SizedBox(width: 8),
                              Icon(Icons.assignment,
                                  size: 11,
                                  color: Theme.of(context).disabledColor),
                              const SizedBox(width: 3),
                              Text(
                                '${roster.assignments.where((a) => a.shiftType != ShiftType.off).length}',
                                style: const TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    StatusBadge(
                      label: s.isAr
                          ? roster.status.arabicLabel()
                          : roster.status.englishLabel(),
                      color: color,
                    ),
                  ],
                ),
                if (roster.submittedAt != null && !isDraft) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.send,
                          size: 11, color: Theme.of(context).disabledColor),
                      const SizedBox(width: 4),
                      Text(
                        '${s.isAr ? "مُرسل" : "Submitted"}: ${_fmtDt(roster.submittedAt!)}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ],
                if (roster.reviewedAt != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                          isRejected
                              ? Icons.cancel
                              : Icons.check_circle,
                          size: 11,
                          color: color),
                      const SizedBox(width: 4),
                      Text(
                        '${isRejected ? (s.isAr ? "رُفض" : "Rejected") : s.approvedAt}: ${_fmtDt(roster.reviewedAt!)}',
                        style: TextStyle(fontSize: 11, color: color),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          // كارد سبب الرفض - يظهر بارز للمرفوضة
          if (isRejected &&
              roster.rejectionReason != null &&
              roster.rejectionReason!.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.danger.withOpacity(0.08),
                border: Border(
                  top: BorderSide(color: AppColors.danger.withOpacity(0.3)),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.comment,
                          size: 14, color: AppColors.danger),
                      const SizedBox(width: 6),
                      Text(
                        s.rejectionReason,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.danger,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    roster.rejectionReason!,
                    style: const TextStyle(fontSize: 12, height: 1.5),
                  ),
                ],
              ),
            ),
          // الإجراءات
          Container(
            decoration: const BoxDecoration(
              color: AppColors.bgLight,
              borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(12)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                if (isDraft)
                  TextButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(s.isAr
                            ? 'افتح تاب "روستر مسودة" للتعديل'
                            : 'Open "Draft Roster" tab to edit')),
                      );
                    },
                    icon: const Icon(Icons.edit, size: 14),
                    label: Text(s.edit,
                        style: const TextStyle(fontSize: 12)),
                  ),
                if (isRejected)
                  TextButton.icon(
                    onPressed: () async {
                      // إعادة الروستر لـ Draft
                      final supaReady = SupabaseService().isReady;
                      if (supaReady) {
                        final ds = SupabaseDataService();
                        final ok = await ds.updateRosterStatus(
                          rosterId: roster.id,
                          status: RosterStatus.draft,
                          rejectionReason: null,
                        );
                        if (!ok && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            backgroundColor: Colors.red,
                            content: Text(ds.lastError ?? 'Failed'),
                          ));
                          return;
                        }
                        roster.rejectionReason = null;
                      } else {
                        roster.status = RosterStatus.draft;
                        roster.rejectionReason = null;
                        MockRepository().updateRoster(roster);
                      }
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(s.isAr
                                ? 'تم تحويل الروستر لمسودة - افتح تاب الروستر للتعديل'
                                : 'Reverted to draft - open Roster tab to edit')),
                      );
                    },
                    icon:
                        const Icon(Icons.refresh, size: 14, color: AppColors.danger),
                    label: Text(s.reEditAndResubmit,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.danger)),
                  ),
                const Spacer(),
                Text('ID: ${roster.id.substring(0, 6)}',
                    style: TextStyle(
                        fontSize: 9,
                        color: Theme.of(context).disabledColor,
                        fontFamily: 'monospace')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.day}/${d.month.toString().padLeft(2, "0")}/${d.year}';
  String _fmtDt(DateTime d) =>
      '${_fmt(d)}  ${d.hour.toString().padLeft(2, "0")}:${d.minute.toString().padLeft(2, "0")}';
}
