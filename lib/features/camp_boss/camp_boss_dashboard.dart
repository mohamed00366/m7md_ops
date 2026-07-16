import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../models/enums.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/m7_stats_banner.dart';
import '../../core/theme/app_colors.dart';
import 'camp_palette.dart';
import 'camp_widgets.dart';
import 'camp_boss_rooms.dart';
import 'camp_boss_violations.dart';
import 'camp_boss_buses_weekly.dart';
import '../laundry/camp_boss/camp_boss_dashboard.dart' as amana;

/// تنقّل موحّد من الداشبورد لأي شاشة camp boss
void _pushScreen(BuildContext context, Widget screen) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
}

/// يفتح شاشة استلام الغسيل (تحتاج معرّف الكمب بوص + الدولة)
void _openLaundry(BuildContext context) {
  final auth = context.read<AuthProvider>();
  final empId = auth.account?.employeeId ?? auth.account?.id ?? '';
  final countryId =
      MockRepository().employeeById(empId)?.countryId ?? auth.activeCountryId;
  _pushScreen(
    context,
    amana.CampBossLaundryDashboard(campBossId: empId, countryId: countryId),
  );
}

/// Camp Boss Dashboard - تصميم احترافي بـ Header دارك بلو + بطاقات بيضاء
class CampBossDashboard extends StatelessWidget {
  const CampBossDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final auth = context.watch<AuthProvider>();

    // ===== فلترة كل الكيانات بحسب الدولة المختارة =====
    final scopedEmployees =
        auth.filterByCountry(repo.employees, (e) => e.countryId);
    final scopedBuses =
        auth.filterByCountry(repo.buses, (b) => b.countryId);
    final scopedRooms =
        auth.filterByCountry(repo.rooms, (r) => r.countryId);
    final scopedLaundry = repo.laundryTickets.where((t) {
      final emp = repo.employeeById(t.employeeId);
      return auth.isInScope(emp?.countryId);
    }).toList();
    final scopedViolations = repo.violations.where((v) {
      final emp = repo.employeeById(v.employeeId);
      return auth.isInScope(emp?.countryId);
    }).toList();

    final empCount = scopedEmployees
        .where((e) => e.status == EntityStatus.active)
        .length;
    final activeBuses =
        scopedBuses.where((b) => b.status == EntityStatus.active).length;
    final totalBeds = scopedRooms.fold<int>(0, (a, r) => a + r.capacity);
    final usedBeds = scopedRooms.fold<int>(0, (a, r) => a + r.used);
    final freeBeds = totalBeds - usedBeds;

    final laundryPending = scopedLaundry
        .where((t) => t.stage != LaundryStage.deliveredToEmployee)
        .length;
    final pendingViolations =
        scopedViolations.where((v) => v.status == ViolationStatus.pending).length;

    final hasUnassignedHour = _hasUnassignedHour(repo);

    return CampThemeWrapper(
      child: Stack(
        children: [
          ListView(
            padding: EdgeInsets.zero,
            children: [
              // ============ HEADER ============
              _DashHeader(user: auth.currentUser, isAr: s.isAr),
              // ============ لَمحة اليوم — نفس تصميم الصفحة الرئيسية (M7StatsBanner) ============
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                child: Row(
                  children: [
                    Icon(Icons.insights,
                        color: AppColors.gold.withValues(alpha: 0.9),
                        size: 16),
                    const SizedBox(width: 6),
                    Text(
                      s.isAr ? 'لَمحة اليَوم' : "Today's Snapshot",
                      style: TextStyle(
                          color: CampPalette.textColor(context),
                          fontWeight: FontWeight.w900,
                          fontSize: 13),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: M7StatsBanner(stats: [
                  M7Stat(
                    icon: Icons.people,
                    label: s.isAr ? 'موظفون' : 'Employees',
                    value: empCount,
                    color: AppColors.brand,
                  ),
                  M7Stat(
                    icon: Icons.directions_bus,
                    label: s.isAr ? 'باصات' : 'Buses',
                    value: activeBuses,
                    color: AppColors.info,
                  ),
                  M7Stat(
                    icon: Icons.hotel,
                    label: s.isAr ? 'أسِرّة' : 'Beds',
                    value: freeBeds,
                    color: AppColors.gold,
                  ),
                  M7Stat(
                    icon: Icons.local_laundry_service,
                    label: s.isAr ? 'مغسلة' : 'Laundry',
                    value: laundryPending,
                    color: AppColors.danger,
                  ),
                  M7Stat(
                    icon: Icons.error_outline,
                    label: s.isAr ? 'مخالفات' : 'Violations',
                    value: pendingViolations,
                    color: AppColors.warning,
                  ),
                ]),
              ),

              // ============ Alert banner ============
              if (hasUnassignedHour)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                  child: _AlertBanner(
                    title: s.isAr ? 'ساعة بدون باص' : 'Hour without a bus',
                    subtitle: s.isAr
                        ? 'توجد ساعة غير معيّنة لباص — راجع خطة الباصات'
                        : 'An hour has no bus assigned — review the bus plan',
                    actionText: s.isAr ? 'إصلاح ›' : 'Fix ›',
                    onAction: () =>
                        _pushScreen(context, const CampBossBusesWeekly()),
                  ),
                ),

              // ============ Today's roster ============
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: CampSectionCard(
                  title: s.isAr ? 'جدول اليوم' : "Today's roster",
                  action: GestureDetector(
                    onTap: () =>
                        _pushScreen(context, const CampBossBusesWeekly()),
                    child: Text(
                      s.isAr ? 'عرض الكل ›' : 'See all ›',
                      style: TextStyle(
                        color: CampPalette.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  child: const _TodayTimeline(),
                ),
              ),

              // ============ Laundry + Rooms 2-col ============
              const Padding(
                padding: EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: Row(
                  children: [
                    Expanded(child: _LaundrySummary()),
                    SizedBox(width: 8),
                    Expanded(child: _RoomsSummary()),
                  ],
                ),
              ),

              // ============ Quick actions ============
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                child: Text(
                  s.isAr ? 'إجراءات سريعة' : 'Quick actions',
                  style: TextStyle(
                      color: CampPalette.textColor(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.7,
                  children: [
                    CampQuickActionButton(
                      icon: Icons.directions_bus,
                      title: s.isAr ? 'تعيين باص' : 'Assign bus',
                      subtitle: s.isAr ? 'ساعة بحاجة باص' : '1 hour needs bus',
                      titleColor: Colors.white,
                      iconColor: Colors.white.withValues(alpha: 0.85),
                      background: CampPalette.headerStart,
                      primary: true,
                      onTap: () =>
                          _pushScreen(context, const CampBossBusesWeekly()),
                    ),
                    CampQuickActionButton(
                      icon: Icons.local_laundry_service_outlined,
                      title: s.isAr ? 'استلام ملابس' : 'Receive clothes',
                      subtitle: s.isAr ? 'إصدار إيصال' : 'Issue receipt',
                      titleColor: CampPalette.headerStart,
                      iconColor: CampPalette.headerStart,
                      background: CampPalette.bg,
                      onTap: () => _openLaundry(context),
                    ),
                    CampQuickActionButton(
                      icon: Icons.home_outlined,
                      title: s.isAr ? 'تقييم غرفة' : 'Rate room',
                      subtitle: s.isAr ? 'فحص النظافة' : 'Cleanliness',
                      titleColor: CampPalette.headerStart,
                      iconColor: CampPalette.headerStart,
                      background: CampPalette.bg,
                      onTap: () => _pushScreen(context, const CampBossRooms()),
                    ),
                    CampQuickActionButton(
                      icon: Icons.error_outline,
                      title: s.isAr ? 'مخالفة جديدة' : 'New violation',
                      subtitle: s.isAr ? 'تسجيل سوء سلوك' : 'Log misconduct',
                      titleColor: CampPalette.red,
                      iconColor: CampPalette.red,
                      background: CampPalette.bg,
                      onTap: () =>
                          _pushScreen(context, const CampBossViolations()),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ],
      ),
    );
  }

  bool _hasUnassignedHour(MockRepository repo) {
    final plan = repo.busPlans.isEmpty ? null : repo.busPlans.first;
    if (plan == null) return false;
    return plan.details.any((d) => d.busId.isEmpty);
  }
}

/// ============ هيدر الداشبورد (دارك بلو متدرج) ============
class _DashHeader extends StatelessWidget {
  final AppUser? user;
  final bool isAr;
  const _DashHeader({required this.user, required this.isAr});

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? (isAr ? 'صباح الخير،' : 'Good morning,')
        : (isAr ? 'مساء الخير،' : 'Good evening,');
    final shiftLabel = hour < 14
        ? (isAr ? 'وردية صباحية' : 'Morning shift')
        : hour < 22
            ? (isAr ? 'وردية مسائية' : 'Evening shift')
            : (isAr ? 'وردية ليلية' : 'Night shift');

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [CampPalette.headerStart, CampPalette.headerEnd],
        ),
      ),
      padding: EdgeInsets.fromLTRB(
          20, MediaQuery.of(context).padding.top + 12, 20, 36),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(greeting,
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.65))),
                const SizedBox(height: 2),
                Text(user?.fullName ?? (isAr ? 'كامب بوس' : 'Camp Boss'),
                    style: TextStyle(
                        fontSize: 20,
                        color: Colors.white,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 3),
                Text('${_today(isAr)} — $shiftLabel',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.55))),
              ],
            ),
          ),
          Stack(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.notifications_none,
                    color: Colors.white, size: 18),
              ),
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: CampPalette.amber,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: CampPalette.headerStart, width: 1.5),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _today(bool isAr) {
    final d = DateTime.now();
    if (isAr) {
      const days = [
        'الإثنين','الثلاثاء','الأربعاء','الخميس','الجمعة','السبت','الأحد'
      ];
      const months = [
        'يناير','فبراير','مارس','أبريل','مايو','يونيو',
        'يوليو','أغسطس','سبتمبر','أكتوبر','نوفمبر','ديسمبر'
      ];
      return '${days[d.weekday - 1]}، ${d.day} ${months[d.month - 1]} ${d.year}';
    }
    const days = [
      'Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'
    ];
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

/// ============ بانر تنبيه ============
class _AlertBanner extends StatelessWidget {
  final String title;
  final String subtitle;
  final String actionText;
  final VoidCallback onAction;
  const _AlertBanner({
    required this.title,
    required this.subtitle,
    required this.actionText,
    required this.onAction,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: CampPalette.amberBg,
        borderRadius: CampPalette.rCardSm,
        border: Border.all(color: const Color(0xFFFAC775), width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: CampPalette.amber,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: TextStyle(
                        color: CampPalette.amberText,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 1),
                Text(subtitle,
                    style: TextStyle(
                        color: CampPalette.amberText.withValues(alpha: 0.75),
                        fontSize: 10)),
              ],
            ),
          ),
          GestureDetector(
            onTap: onAction,
            child: Text(actionText,
                style: TextStyle(
                    color: CampPalette.amberText,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

/// ============ تايملاين اليوم ============
class _TodayTimeline extends StatelessWidget {
  const _TodayTimeline();

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final dayIndex = (DateTime.now().weekday - 1).clamp(0, 6);
    final plan = repo.busPlans.isEmpty ? null : repo.busPlans.first;
    final details = plan == null
        ? <BusPlanDetail>[]
        : (plan.details.where((d) => d.dayIndex == dayIndex).toList()
          ..sort((a, b) => a.time.compareTo(b.time)));

    if (details.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Text(
            s.isAr ? 'لا توجد رحلات اليوم' : 'No trips today',
            style: TextStyle(color: CampPalette.textSecondaryColor(context)),
          ),
        ),
      );
    }

    return Column(
      children: details.asMap().entries.map((entry) {
        final i = entry.key;
        final d = entry.value;
        final bus = repo.busById(d.busId);
        final site = repo.siteById(d.siteId);
        final point = repo.pointById(d.siteId);
        final stopName = site?.companyName ?? point?.name ?? '-';
        final hasBus = bus != null;
        final color = hasBus ? CampPalette.green : CampPalette.amber;
        final isLast = i == details.length - 1;

        final emps = d.employeeIds
            .map((id) => repo.employeeById(id))
            .whereType<Employee>()
            .toList();

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 42,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(d.time,
                          style: TextStyle(
                              color: CampPalette.textColor(context),
                              fontSize: 12,
                              fontWeight: FontWeight.w500)),
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 1.5,
                          margin: const EdgeInsets.only(top: 4),
                          color: CampPalette.borderColor(context),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                      vertical: 10, horizontal: 12),
                  decoration: BoxDecoration(
                    color: hasBus
                        ? const Color(0xFFF8F9FB)
                        : CampPalette.amberSoftBg.withValues(alpha: 0.4),
                    borderRadius: CampPalette.rInput,
                    border: Border(
                        right: BorderSide(color: color, width: 3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          hasBus
                              ? '${bus.name} — ${bus.capacity} ${s.isAr ? "مقعد" : "seats"}'
                              : (s.isAr
                                  ? 'لا يوجد باص معيّن'
                                  : 'No bus assigned'),
                          style: TextStyle(
                              color:
                                  hasBus ? CampPalette.textColor(context) : CampPalette.amberText,
                              fontSize: 12,
                              fontWeight: FontWeight.w500)),
                      const SizedBox(height: 2),
                      Text(stopName,
                          style: TextStyle(
                              color: CampPalette.textSecondaryColor(context), fontSize: 10)),
                      if (emps.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 3,
                          runSpacing: 3,
                          children: [
                            ...emps.take(4).map((e) => CampEmpAvatar(
                                  name: e.fullName,
                                  radius: 11,
                                  color: CampPalette.primary,
                                  bgColor: CampPalette.blueBg,
                                )),
                            if (emps.length > 4)
                              Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: CampPalette.borderColor(context),
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: Text('+${emps.length - 4}',
                                    style: TextStyle(
                                        color: CampPalette.textSecondaryColor(context),
                                        fontSize: 9)),
                              ),
                          ],
                        ),
                      ],
                      if (!hasBus) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 3),
                          decoration: const BoxDecoration(
                            color: CampPalette.amberSoftBg,
                            borderRadius: CampPalette.rPill,
                          ),
                          child: Text(
                              s.isAr
                                  ? '${d.employeeIds.length} موظفين بالانتظار'
                                  : '${d.employeeIds.length} employees waiting',
                              style: TextStyle(
                                  color: CampPalette.amberText,
                                  fontSize: 10)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

/// ============ ملخص المغسلة ============
class _LaundrySummary extends StatelessWidget {
  const _LaundrySummary();
  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final pending = repo.laundryTickets
        .where((t) => t.stage != LaundryStage.deliveredToEmployee)
        .length;
    final missing =
        repo.laundryTickets.where((t) => t.missingItems.isNotEmpty).length;
    return Material(
      color: CampPalette.cardColor(context),
      borderRadius: CampPalette.rCardSm,
      child: InkWell(
        onTap: () => _openLaundry(context),
        borderRadius: CampPalette.rCardSm,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(s.isAr ? 'المغسلة' : 'Laundry',
                        style: TextStyle(
                            color: CampPalette.textColor(context),
                            fontSize: 12,
                            fontWeight: FontWeight.w500)),
                  ),
                  Icon(Icons.chevron_right,
                      color: CampPalette.textTertiaryColor(context), size: 14),
                ],
              ),
              const SizedBox(height: 10),
              Text('$pending',
                  style: TextStyle(
                      color: CampPalette.primary,
                      fontSize: 22,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(s.isAr ? 'إيصالات معلّقة' : 'pending receipts',
                  style: TextStyle(
                      color: CampPalette.textSecondaryColor(context), fontSize: 10)),
              if (missing > 0) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: CampPalette.redSoftBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    s.isAr ? '$missing قطع ناقصة' : '$missing items missing',
                    style: TextStyle(
                        color: CampPalette.redText,
                        fontSize: 10,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// ============ ملخص الغرف ============
class _RoomsSummary extends StatelessWidget {
  const _RoomsSummary();
  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final count = repo.rooms.length;
    final avgRating = count == 0
        ? 0.0
        : repo.rooms.fold<double>(0, (a, r) => a + r.avgRating) / count;
    final totalBeds = repo.rooms.fold<int>(0, (a, r) => a + r.capacity);
    final used = repo.rooms.fold<int>(0, (a, r) => a + r.used);
    final occupancy = totalBeds == 0 ? 0.0 : used / totalBeds;

    return Material(
      color: CampPalette.cardColor(context),
      borderRadius: CampPalette.rCardSm,
      child: InkWell(
        onTap: () => _pushScreen(context, const CampBossRooms()),
        borderRadius: CampPalette.rCardSm,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(s.isAr ? 'الغرف' : 'Rooms',
                        style: TextStyle(
                            color: CampPalette.textColor(context),
                            fontSize: 12,
                            fontWeight: FontWeight.w500)),
                  ),
                  Icon(Icons.chevron_right,
                      color: CampPalette.textTertiaryColor(context), size: 14),
                ],
              ),
              const SizedBox(height: 10),
              Text('$count',
                  style: TextStyle(
                      color: CampPalette.primary,
                      fontSize: 22,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(s.isAr ? 'غرفة بالمجموع' : 'rooms total',
                  style: TextStyle(
                      color: CampPalette.textSecondaryColor(context), fontSize: 10)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: occupancy,
                  minHeight: 4,
                  backgroundColor: const Color(0xFFEEEEEE),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                      CampPalette.green),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                  '${s.isAr ? "متوسط" : "Avg"} ${avgRating.toStringAsFixed(1)} / 5',
                  style: TextStyle(
                      color: CampPalette.textSecondaryColor(context), fontSize: 9)),
            ],
          ),
        ),
      ),
    );
  }
}
