import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../models/models.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/employee_identity.dart';
import '../../shared/widgets.dart';

/// شاشة الروستر المعتمد - عرض read-only للمشرف
/// يعرض آخر روستر تم اعتماده مع جدول الورديات والـ timeline
class SupervisorApprovedRoster extends StatefulWidget {
  const SupervisorApprovedRoster({super.key});

  @override
  State<SupervisorApprovedRoster> createState() =>
      _SupervisorApprovedRosterState();
}

class _SupervisorApprovedRosterState
    extends State<SupervisorApprovedRoster> {
  WeeklyRoster? _selected;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final auth = context.watch<AuthProvider>();
    final empId = auth.currentUser?.employeeId;
    final activeCountry = auth.activeCountryId;

    // ===== تحديد نطاق الرؤية (نفس منطق My Rosters) =====
    String? supervisorPointId;
    bool isSupervisorMode = false;
    if (empId != null) {
      isSupervisorMode = true;
      try {
        final emp = repo.employees.firstWhere((e) => e.id == empId);
        supervisorPointId = emp.pointId ?? emp.siteId;
      } catch (_) {}
    }

    // 🆕 من لديه rostersSelectAnyPoint (Manager/Operation/Admin) لا يحتاج
    // ربط بنقطة — يستطيع رؤية روسترات كل النقاط في الدولة النشطة.
    final canSeeAllPoints =
        auth.hasPermission(P.rostersSelectAnyPoint) ||
            auth.hasPermission(P.rostersApprove) ||
            auth.isSuperAdmin;

    if (isSupervisorMode && supervisorPointId == null && !canSeeAllPoints) {
      return EmptyState(
        icon: Icons.location_off,
        message: s.isAr
            ? 'لم يتم ربطك بنقطة بعد. تواصل مع Operation'
            : 'You\'re not assigned to a Point. Contact Operation',
      );
    }

    // إذا كان لديه صلاحية رؤية كل النقاط ولم يكن مرتبطاً بنقطة،
    // نتعامل معه كـ Admin/Operation: نعرض كل الروسترات في الدولة.
    if (supervisorPointId == null && canSeeAllPoints) {
      isSupervisorMode = false;
    }

    // اجلب الروسترات المعتمدة:
    //  - وضع المشرف: نقطته فقط
    //  - وضع Admin/Operation: كل النقاط ضمن الدولة النشطة
    var approvedList = repo.rosters.where((r) {
      if (r.status != RosterStatus.approved) return false;
      if (supervisorPointId != null) return r.siteId == supervisorPointId;
      if (activeCountry != null) {
        final point = repo.pointById(r.siteId);
        if (point?.countryId != activeCountry) return false;
      } else if (!auth.isSuperAdmin) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => b.weekStart.compareTo(a.weekStart));

    final selected = _selected ??
        (approvedList.isEmpty ? null : approvedList.first);

    if (selected == null) {
      return _NoApprovedView(
        message: s.noApprovedYet,
        hint: s.pendingApproval,
      );
    }

    return Scaffold(
      body: Column(
        children: [
          // Header مع اختيار الروستر المعتمد (إن كان هناك أكثر من واحد)
          _ApprovedHeader(
            roster: selected,
            allApproved: approvedList,
            onSelectChanged: (r) => setState(() => _selected = r),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Banner الموافقة
                  _ApprovedBanner(roster: selected),
                  // الجدول الـ read-only
                  _ApprovedRosterTable(roster: selected),
                  const SizedBox(height: 14),
                  // Timeline 24 ساعة
                  _ApprovedTimeline(roster: selected),
                  const SizedBox(height: 14),
                  // معلومات الاعتماد
                  _ApprovalInfo(roster: selected),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Header مع navigator للروسترات المعتمدة
// ============================================================
class _ApprovedHeader extends StatelessWidget {
  final WeeklyRoster roster;
  final List<WeeklyRoster> allApproved;
  final ValueChanged<WeeklyRoster> onSelectChanged;

  const _ApprovedHeader({
    required this.roster,
    required this.allApproved,
    required this.onSelectChanged,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final site = repo.siteById(roster.siteId);
    final point = repo.pointById(roster.siteId);
    final locationName = site?.companyName ?? point?.name ?? '-';

    return Container(
      color: Theme.of(context).cardTheme.color,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.location_on,
                  size: 16, color: AppColors.brand),
              const SizedBox(width: 6),
              Expanded(
                child: Text(locationName,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800)),
              ),
              StatusBadge(
                label: s.approved,
                color: AppColors.success,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (allApproved.length > 1)
            DropdownButtonFormField<String>(
              value: roster.id,
              isDense: true,
              decoration: InputDecoration(
                labelText: s.weeklyRoster,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                prefixIcon: const Icon(Icons.calendar_today, size: 16),
              ),
              items: allApproved
                  .map((r) => DropdownMenuItem(
                        value: r.id,
                        child: Text(
                          '${_fmt(r.weekStart)} - ${_fmt(r.weekStart.add(const Duration(days: 6)))}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                final r = allApproved.firstWhere((x) => x.id == v);
                onSelectChanged(r);
              },
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today,
                      size: 14, color: AppColors.success),
                  const SizedBox(width: 6),
                  Text(
                    '${_fmt(roster.weekStart)} - ${_fmt(roster.weekStart.add(const Duration(days: 6)))}',
                    style: const TextStyle(
                      color: AppColors.success,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.day}/${d.month.toString().padLeft(2, "0")}/${d.year}';
}

// ============================================================
// Banner اعتماد بارز
// ============================================================
class _ApprovedBanner extends StatelessWidget {
  final WeeklyRoster roster;
  const _ApprovedBanner({required this.roster});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.success.withValues(alpha: 0.15),
            AppColors.success.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: AppColors.success,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.approvedBanner,
                  style: const TextStyle(
                      color: AppColors.success,
                      fontSize: 14,
                      fontWeight: FontWeight.w800),
                ),
                if (roster.reviewedAt != null)
                  Text(
                    '${s.approvedAt}: ${_fmtDateTime(roster.reviewedAt!)}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.success,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmtDateTime(DateTime d) =>
      '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, "0")}:${d.minute.toString().padLeft(2, "0")}';
}

// ============================================================
// جدول الروستر للقراءة فقط
// ============================================================
class _ApprovedRosterTable extends StatelessWidget {
  final WeeklyRoster roster;
  const _ApprovedRosterTable({required this.roster});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final dayShortNames = s.isAr
        ? ['ثن', 'ثل', 'أر', 'خم', 'جم', 'سب', 'أح']
        : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    final empIds = roster.assignments.map((a) => a.employeeId).toSet();
    final employees = empIds
        .map((id) => repo.employeeById(id))
        .whereType<Employee>()
        .toList();

    const empColWidth = 130.0;
    const dayColWidth = 70.0;
    const totalColWidth = 50.0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Hdr(label: s.isAr ? 'الموظفون' : 'Employees', width: empColWidth),
                ...List.generate(7, (i) {
                  final d = roster.weekStart.add(Duration(days: i));
                  return _Hdr(
                    width: dayColWidth,
                    label:
                        '${dayShortNames[i]}\n${d.day.toString().padLeft(2, "0")}',
                  );
                }),
                const _Hdr(label: 'h', width: totalColWidth, accent: true),
              ],
            ),
            ...employees.map((emp) {
              final empAss = roster.assignments
                  .where((a) => a.employeeId == emp.id)
                  .toList();
              double total = 0;
              for (final a in empAss) {
                total += a.hours;
              }
              return Row(
                children: [
                  _NameCell(employee: emp, width: empColWidth),
                  ...List.generate(7, (di) {
                    final list = empAss.where((a) => a.dayIndex == di).toList();
                    return _CellRO(
                      width: dayColWidth,
                      assignment: list.isEmpty ? null : list.first,
                    );
                  }),
                  _Total(width: totalColWidth, hours: total),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _Hdr extends StatelessWidget {
  final String label;
  final double width;
  final bool accent;
  const _Hdr(
      {required this.label, required this.width, this.accent = false});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 50,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent
            ? AppColors.warning.withValues(alpha: 0.15)
            : AppColors.success.withValues(alpha: 0.08),
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor),
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: accent ? AppColors.warning : AppColors.success),
      ),
    );
  }
}

class _NameCell extends StatelessWidget {
  final Employee employee;
  final double width;
  const _NameCell({required this.employee, required this.width});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor),
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      // 🆕 هويّة الموظّف الموحّدة (صورة + اسم + كود)
      child: EmployeeIdentity(
        employee: employee,
        size: EmployeeIdentitySize.compact,
        showCode: true,
      ),
    );
  }
}

class _CellRO extends StatelessWidget {
  final double width;
  final RosterAssignment? assignment;
  const _CellRO({required this.width, required this.assignment});

  @override
  Widget build(BuildContext context) {
    final a = assignment;
    Color bg;
    Color textColor;
    String letter;
    String? timeLabel;
    if (a == null || a.shiftType == ShiftType.off) {
      bg = AppColors.textTertiaryLight.withValues(alpha: 0.1);
      textColor = AppColors.textTertiaryLight;
      letter = 'Off';
      timeLabel = null;
    } else if (a.shiftType == ShiftType.night) {
      bg = AppColors.info.withValues(alpha: 0.15);
      textColor = AppColors.info;
      letter = 'N';
      timeLabel = '${_short(a.startTime)}-${_short(a.endTime)}';
    } else {
      bg = AppColors.success.withValues(alpha: 0.15);
      textColor = AppColors.success;
      letter = 'M';
      timeLabel = '${_short(a.startTime)}-${_short(a.endTime)}';
    }
    return Container(
      width: width,
      height: 56,
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor),
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(letter,
              style: TextStyle(
                  color: textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w800)),
          if (timeLabel != null)
            Text(timeLabel,
                style: TextStyle(
                    color: textColor,
                    fontSize: 10,
                    fontFamily: 'monospace')),
        ],
      ),
    );
  }

  String _short(String t) {
    final p = t.split(':');
    return p.isEmpty ? t : p[0];
  }
}

class _Total extends StatelessWidget {
  final double width;
  final double hours;
  const _Total({required this.width, required this.hours});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor),
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Text(
        hours.toStringAsFixed(0),
        style: const TextStyle(
            color: AppColors.warning,
            fontWeight: FontWeight.w800,
            fontSize: 14),
      ),
    );
  }
}

// ============================================================
// Timeline أفقي 24 ساعة
// ============================================================
class _ApprovedTimeline extends StatelessWidget {
  final WeeklyRoster roster;
  const _ApprovedTimeline({required this.roster});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final dayNames = s.isAr
        ? ['الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد']
        : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Icon(Icons.bar_chart, size: 16, color: AppColors.success),
            const SizedBox(width: 6),
            Text(
              s.isAr
                  ? 'الجدول الزمني (24 ساعة لكل يوم)'
                  : 'Daily Timeline (24h per day)',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800),
            ),
          ]),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 70),
            child: Row(
              children: [0, 6, 12, 18, 24]
                  .map((h) => Expanded(
                        child: Text('${h.toString().padLeft(2, "0")}:00',
                            textAlign: TextAlign.start,
                            style: TextStyle(
                              fontSize: 9,
                              color: Theme.of(context).disabledColor,
                              fontFamily: 'monospace',
                            )),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 6),
          ...List.generate(7, (di) {
            final dayAss = roster.assignments
                .where((a) =>
                    a.dayIndex == di && a.shiftType != ShiftType.off)
                .toList();
            return _DayTimeline(name: dayNames[di], assignments: dayAss);
          }),
        ],
      ),
    );
  }
}

class _DayTimeline extends StatelessWidget {
  final String name;
  final List<RosterAssignment> assignments;
  const _DayTimeline({required this.name, required this.assignments});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(name,
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: Container(
              height: 18,
              decoration: BoxDecoration(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(4),
              ),
              child: LayoutBuilder(builder: (_, constraints) {
                final w = constraints.maxWidth;
                return Stack(
                  children: assignments.map((a) {
                    final start = _hr(a.startTime);
                    var end = _hr(a.endTime);
                    if (end <= start) end += 24;
                    final left = (start / 24) * w;
                    final width = ((end - start) / 24) * w;
                    final isNight = a.shiftType == ShiftType.night;
                    return Positioned(
                      left: left.clamp(0.0, w),
                      width:
                          width.clamp(0.0, w - left.clamp(0.0, w)),
                      top: 0,
                      bottom: 0,
                      child: Container(
                        decoration: BoxDecoration(
                          color: (isNight ? AppColors.info : AppColors.success)
                              .withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    );
                  }).toList(),
                );
              }),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 32,
            child: Text(
              '${_dayHours().toStringAsFixed(0)}h',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: AppColors.warning,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  double _dayHours() {
    double t = 0;
    for (final a in assignments) {
      t += a.hours;
    }
    return t;
  }

  double _hr(String t) {
    final p = t.split(':');
    if (p.length != 2) return 0;
    final h = int.tryParse(p[0]) ?? 0;
    final m = int.tryParse(p[1]) ?? 0;
    return h + m / 60.0;
  }
}

// ============================================================
// معلومات الاعتماد
// ============================================================
class _ApprovalInfo extends StatelessWidget {
  final WeeklyRoster roster;
  const _ApprovalInfo({required this.roster});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final reviewer = roster.reviewedBy == null
        ? null
        : repo.users.firstWhere(
            (u) => u.id == roster.reviewedBy,
            orElse: () => repo.users.first,
          );

    final endDate = roster.weekStart.add(const Duration(days: 6));

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s.isAr ? 'تفاصيل الاعتماد' : 'Approval Details',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          _InfoRow(
              label: s.effectiveFrom,
              value: _fmt(roster.weekStart),
              icon: Icons.event_available),
          _InfoRow(
              label: s.effectiveTo,
              value: _fmt(endDate),
              icon: Icons.event_busy),
          if (roster.submittedAt != null)
            _InfoRow(
              label: s.isAr ? 'تاريخ الإرسال' : 'Submitted At',
              value: _fmtDt(roster.submittedAt!),
              icon: Icons.send,
            ),
          if (roster.reviewedAt != null)
            _InfoRow(
              label: s.approvedAt,
              value: _fmtDt(roster.reviewedAt!),
              icon: Icons.check_circle,
              color: AppColors.success,
            ),
          if (reviewer != null)
            _InfoRow(
              label: s.reviewedBy,
              value: reviewer.fullName,
              icon: Icons.person,
            ),
          const Divider(height: 20),
          Row(
            children: [
              _MiniMetric(
                  label: s.totalHours,
                  value: roster.totalHours.toStringAsFixed(0),
                  color: AppColors.warning),
              _MiniMetric(
                  label: s.isAr ? 'الموظفون' : 'Employees',
                  value: '${roster.assignments.map((a) => a.employeeId).toSet().length}',
                  color: AppColors.brand),
              _MiniMetric(
                  label: s.isAr ? 'الورديات' : 'Shifts',
                  value: '${roster.assignments.where((a) => a.shiftType != ShiftType.off).length}',
                  color: AppColors.success),
            ],
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

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  const _InfoRow({
    required this.label,
    required this.value,
    required this.icon,
    this.color,
  });
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon,
              size: 14, color: color ?? Theme.of(context).disabledColor),
          const SizedBox(width: 6),
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      color:
                          color ?? Theme.of(context).disabledColor))),
          Text(value,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color)),
        ],
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MiniMetric({
    required this.label,
    required this.value,
    required this.color,
  });
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    color: color,
                    fontSize: 16,
                    fontWeight: FontWeight.w800)),
            Text(label,
                style: const TextStyle(fontSize: 10),
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// لا يوجد روستر معتمد
// ============================================================
class _NoApprovedView extends StatelessWidget {
  final String message;
  final String hint;
  const _NoApprovedView({required this.message, required this.hint});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.hourglass_empty,
                  size: 40, color: AppColors.warning),
            ),
            const SizedBox(height: 16),
            Text(message,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(hint,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
