import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:universal_html/html.dart' as html;

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/notifications_service.dart';
import '../../core/services/replacement_notification_settings.dart';
import '../../core/services/roster_employee_filter_settings.dart';
import '../../core/services/supabase_data_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/employee_identity.dart';
import '../../shared/widgets.dart';

/// 🚌 رحلات السائق
///
/// شاشة موحَّدة بثلاث تبويبات:
///   1. **اليوم**: رحلات اليوم الحالي فقط
///   2. **هذا الأسبوع**: رحلات الأسبوع المعروض (مع متصفّح أسابيع <  >)
///   3. **القادمة**: كلّ الرحلات في الأسابيع الـ4 القادمة
///
/// + بطاقة إحصاءات (إجمالي الرحلات/الركّاب/الساعات)
/// + متصفّح الأسابيع مع زرّ "اليوم" للعودة السريعة
/// + تنبيهات استباقيّة (الرحلة القادمة خلال ساعة)
/// + اتصال سريع بمدير العمليّات
class DriverTrips extends StatefulWidget {
  /// إذا true → يَفتح بتبويب "هذا الأسبوع" افتراضياً
  /// إذا false → يَفتح بتبويب "اليوم" افتراضياً
  final bool weekly;
  const DriverTrips({super.key, required this.weekly});

  @override
  State<DriverTrips> createState() => _DriverTripsState();
}

class _DriverTripsState extends State<DriverTrips>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  /// الأسبوع المعروض حاليّاً (يَتغيّر بالأسهم)
  late DateTime _displayedWeek;
  /// اليوم المختار في تبويب "هذا الأسبوع"
  int _selectedDay = DateTime.now().weekday - 1;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.weekly ? 1 : 0,
    );
    _displayedWeek = MockRepository().currentWeekStart();
    MockRepository().addListener(_onRepoChange);
    // 🆕 اضمَن تَحميل البَيانات وَبِناء خُطّة الباص لِلسائِق
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureData());
  }

  void _onRepoChange() {
    if (mounted) setState(() {});
  }

  /// 🆕 يَجلِب البَيانات من Supabase ثُمَّ يُولِّد خُطّة الباص لِلأُسابيع المَعروضة
  Future<void> _ensureData() async {
    try {
      final repo = MockRepository();
      final svc = SupabaseDataService();

      if (SupabaseService().isReady) {
        // اِجلِب البَيانات الناقِصة بِالتَوازي
        final futures = <Future>[];
        if (repo.buses.isEmpty) futures.add(svc.syncBuses());
        if (repo.employees.isEmpty) futures.add(svc.syncEmployees());
        if (repo.employeeBusAssignments.isEmpty) {
          futures.add(svc.syncEmployeeBusAssignments());
        }
        if (repo.busDriverShifts.isEmpty) {
          futures.add(svc.syncBusDriverShifts());
        }
        if (repo.busEmployees.isEmpty) futures.add(svc.syncBusEmployees());
        if (repo.rosters.isEmpty) futures.add(svc.syncRosters());
        if (repo.points.isEmpty) futures.add(svc.syncPoints());
        if (repo.sites.isEmpty) futures.add(svc.syncSites());
        if (futures.isNotEmpty) await Future.wait(futures);
      }

      // أَنشِئ/حَدِّث خُطَط الباصات لِلأُسابيع المَعروضة
      final ws = repo.currentWeekStart();
      repo.syncBusPlanFromApprovedRosters(ws);
      repo.syncBusPlanFromApprovedRosters(
        ws.add(const Duration(days: 7)),
      );
      repo.syncBusPlanFromApprovedRosters(_displayedWeek);

      if (mounted) setState(() {});
    } catch (_) {
      // ignore — لا نُريد كَسر الشاشة
    }
  }

  @override
  void dispose() {
    MockRepository().removeListener(_onRepoChange);
    _tabs.dispose();
    super.dispose();
  }

  /// تنقّل بين الأسابيع
  void _changeWeek(int weeks) {
    setState(() => _displayedWeek =
        _displayedWeek.add(Duration(days: weeks * 7)));
  }

  /// عودة سريعة لأسبوع اليوم
  void _jumpToToday() {
    setState(() {
      _displayedWeek = MockRepository().currentWeekStart();
      _selectedDay = DateTime.now().weekday - 1;
    });
  }

  String _fmt(DateTime d) =>
      '${d.day}/${d.month.toString().padLeft(2, "0")}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final repo = MockRepository();
    final auth = context.watch<AuthProvider>();
    final empId = auth.currentUser?.employeeId;

    if (empId == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            isAr
                ? 'هذه الشاشة مخصّصة للسائقين فقط'
                : 'This screen is for drivers only',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (repo.buses.isEmpty) {
      return Center(
        child: Text(isAr ? 'لا توجد باصات في النظام' : 'No buses available'),
      );
    }
    // 🆕 ابحَث عَن الباص عَبر BusDriverShift أَوّلاً (النِظام الجَديد)
    // ثُمَّ legacy bus.driverId كَـfallback
    String? myBusId;
    try {
      final shift = repo.busDriverShifts.firstWhere(
        (s) => s.driverId == empId,
      );
      myBusId = shift.busId;
    } catch (_) {
      // لا shift → استَخدِم legacy
    }
    final myBus = repo.buses.firstWhere(
      (b) => (myBusId != null && b.id == myBusId) || b.driverId == empId,
      orElse: () => repo.buses.first,
    );

    return Scaffold(
      body: Column(
        children: [
          // ===== رأس مدمج: معلومات الباص + زرّ اتصال سريع =====
          _BusHeader(bus: myBus),
          // ===== بطاقة إحصاءات الأسبوع المعروض =====
          _WeekStatsCard(
            bus: myBus,
            weekStart: _displayedWeek,
            isAr: isAr,
          ),
          // ===== متصفّح الأسابيع =====
          _WeekNavigator(
            weekStart: _displayedWeek,
            isCurrentWeek: _isSameWeek(
                _displayedWeek, MockRepository().currentWeekStart()),
            onPrev: () => _changeWeek(-1),
            onNext: () => _changeWeek(1),
            onToday: _jumpToToday,
            isAr: isAr,
            fmt: _fmt,
          ),
          // ===== التبويبات =====
          Container(
            color: Theme.of(context).cardTheme.color,
            child: TabBar(
              controller: _tabs,
              labelColor: AppColors.roleDriver,
              unselectedLabelColor: Colors.grey,
              indicatorColor: AppColors.roleDriver,
              labelStyle: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w900),
              tabs: [
                Tab(text: isAr ? 'اليوم' : 'Today'),
                Tab(text: isAr ? 'هذا الأسبوع' : 'This Week'),
                Tab(text: isAr ? 'الأسابيع القادمة' : 'Upcoming'),
              ],
            ),
          ),
          // ===== المحتوى =====
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _TodayTrips(bus: myBus, isAr: isAr),
                _WeekTrips(
                  bus: myBus,
                  weekStart: _displayedWeek,
                  selectedDay: _selectedDay,
                  onSelectDay: (d) => setState(() => _selectedDay = d),
                  isAr: isAr,
                ),
                _UpcomingTrips(bus: myBus, isAr: isAr),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static bool _isSameWeek(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

// ============================================================
// ===== رأس الشاشة: معلومات الباص + اتصال سريع =====
// ============================================================
class _BusHeader extends StatelessWidget {
  final Bus bus;
  const _BusHeader({required this.bus});

  /// 🆕 اتصال سريع بمدير العمليّات (يَستعمل أوّل حساب له role=operation)
  void _callOperations(BuildContext context) {
    final repo = MockRepository();
    final isAr = AppStrings.of(context).isAr;
    // ابحث عن أوّل موظّف عنده اتصال operations
    Employee? opsEmp;
    try {
      opsEmp = repo.employees.firstWhere(
        (e) =>
            e.jobTitle.toLowerCase().contains('operation') ||
            e.jobTitle.contains('عمليّات') ||
            e.jobTitle.contains('عمليات'),
      );
    } catch (_) {}
    final phone = opsEmp?.mobile.trim() ?? '';
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.warning,
        content: Text(isAr
            ? '⚠️ لم يُعثَر على رقم مدير العمليّات'
            : '⚠️ Operations manager phone not found'),
      ));
      return;
    }
    final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    html.window.open('tel:$cleaned', '_self');
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Container(
      color: Theme.of(context).cardTheme.color,
      padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.roleDriver.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.directions_bus,
                color: AppColors.roleDriver, size: 20),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(bus.name,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w900)),
                Text(
                    '${bus.plateNumber} • ${s.capacity}: ${bus.capacity}',
                    style: const TextStyle(fontSize: 10)),
              ],
            ),
          ),
          // 🆕 اتصال سريع بمدير العمليّات
          IconButton(
            tooltip: s.isAr
                ? 'اتصال بمدير العمليّات'
                : 'Call Operations Manager',
            icon: const Icon(Icons.phone_in_talk_outlined,
                color: AppColors.roleDriver),
            onPressed: () => _callOperations(context),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// ===== بطاقة إحصاءات الأسبوع =====
// ============================================================
class _WeekStatsCard extends StatelessWidget {
  final Bus bus;
  final DateTime weekStart;
  final bool isAr;
  const _WeekStatsCard({
    required this.bus,
    required this.weekStart,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    final repo = MockRepository();
    final plan = repo.getOrCreateBusPlan(weekStart);
    var trips = 0;
    var passengers = 0;
    final daysWithTrips = <int>{};
    for (final d in plan.details) {
      // فلتر: الموظّفون الذين لهم هذا الباص في هذا اليوم
      var matched = 0;
      for (final eid in d.employeeIds) {
        final busId = repo.resolveEmployeeBusId(
          employeeId: eid,
          weekStart: weekStart,
          dayIndex: d.dayIndex,
        );
        if (busId == bus.id) matched++;
      }
      if (matched > 0) {
        trips++;
        passengers += matched;
        daysWithTrips.add(d.dayIndex);
      }
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.roleDriver.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: AppColors.roleDriver.withOpacity(0.20)),
      ),
      child: Row(
        children: [
          _StatChip(
            icon: Icons.event_note,
            label: isAr ? 'رحلات' : 'Trips',
            value: '$trips',
            color: AppColors.roleDriver,
          ),
          const SizedBox(width: 6),
          _StatChip(
            icon: Icons.people,
            label: isAr ? 'ركّاب' : 'Pax',
            value: '$passengers',
            color: AppColors.brand,
          ),
          const SizedBox(width: 6),
          _StatChip(
            icon: Icons.calendar_today,
            label: isAr ? 'أيّام عمل' : 'Days',
            value: '${daysWithTrips.length}/7',
            color: AppColors.success,
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.30)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 9, color: Colors.grey.shade600)),
                  Text(value,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: color)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// ===== متصفّح الأسابيع =====
// ============================================================
class _WeekNavigator extends StatelessWidget {
  final DateTime weekStart;
  final bool isCurrentWeek;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final bool isAr;
  final String Function(DateTime) fmt;
  const _WeekNavigator({
    required this.weekStart,
    required this.isCurrentWeek,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
    required this.isAr,
    required this.fmt,
  });
  @override
  Widget build(BuildContext context) {
    final weekEnd = weekStart.add(const Duration(days: 6));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      color: Theme.of(context).cardTheme.color,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          InkWell(
            onTap: onPrev,
            borderRadius: BorderRadius.circular(20),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.chevron_right, size: 18),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '${fmt(weekStart)} - ${fmt(weekEnd)}',
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: onNext,
            borderRadius: BorderRadius.circular(20),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.chevron_left, size: 18),
            ),
          ),
          if (!isCurrentWeek) ...[
            const SizedBox(width: 6),
            InkWell(
              onTap: onToday,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.roleDriver,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isAr ? 'اليوم' : 'Today',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================
// ===== التبويب 1: اليوم =====
// ============================================================
class _TodayTrips extends StatefulWidget {
  final Bus bus;
  final bool isAr;
  const _TodayTrips({required this.bus, required this.isAr});

  @override
  State<_TodayTrips> createState() => _TodayTripsState();
}

class _TodayTripsState extends State<_TodayTrips> {
  Future<void> _openOffPlanSheet() async {
    final created = await showModalBottomSheet<BusPlanDetail>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _OffPlanTripSheet(bus: widget.bus, isAr: widget.isAr),
    );
    if (created != null && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isAr = widget.isAr;
    final bus = widget.bus;
    final repo = MockRepository();
    final today = DateTime.now();
    final week = repo.currentWeekStart();
    final dayIndex = today.weekday - 1;
    final plan = repo.getOrCreateBusPlan(week);
    final driverEmpId =
        context.read<AuthProvider>().currentUser?.employeeId;
    final trips = _filterTripsForBusDay(
        plan.details, bus.id, dayIndex, week, repo,
        driverEmpId: driverEmpId);
    trips.sort((a, b) => a.time.compareTo(b.time));

    return Stack(
      children: [
        if (trips.isEmpty)
          EmptyState(
            icon: Icons.directions_bus_outlined,
            message: isAr
                ? '🎉 لا توجد رحلات اليوم — استرح'
                : '🎉 No trips today',
          )
        else
          ListView(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 80),
            children: [
              _UpcomingTripBanner(trips: trips, isAr: isAr),
              ...trips.map((t) => _TripCard(
                    trip: t,
                    dayIndex: dayIndex,
                    dayName: _dayName(dayIndex, isAr),
                    showDay: false,
                    isAr: isAr,
                  )),
            ],
          ),
        // 🆕 زِرّ إضافة رَحلة خارِج الخُطّة
        Positioned(
          bottom: 16,
          right: 16,
          left: 16,
          child: FloatingActionButton.extended(
            heroTag: 'today_off_plan',
            onPressed: _openOffPlanSheet,
            backgroundColor: AppColors.brand,
            foregroundColor: AppColors.gold,
            icon: const Icon(Icons.add_circle_outline),
            label: Text(
              isAr
                  ? '➕ إضافة رَحلة خارِج الخُطّة'
                  : '➕ Add off-plan trip',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// ===== التبويب 2: هذا الأسبوع =====
// ============================================================
class _WeekTrips extends StatelessWidget {
  final Bus bus;
  final DateTime weekStart;
  final int selectedDay;
  final void Function(int) onSelectDay;
  final bool isAr;
  const _WeekTrips({
    required this.bus,
    required this.weekStart,
    required this.selectedDay,
    required this.onSelectDay,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    final repo = MockRepository();
    final plan = repo.getOrCreateBusPlan(weekStart);
    final trips = _filterTripsForBusDay(
        plan.details, bus.id, selectedDay, weekStart, repo);
    trips.sort((a, b) => a.time.compareTo(b.time));
    final dayNames = isAr
        ? ['الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد']
        : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return Column(
      children: [
        // اختيار اليوم
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(8),
          child: Row(
            children: List.generate(7, (i) {
              final selected = i == selectedDay;
              final d = weekStart.add(Duration(days: i));
              return Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: GestureDetector(
                  onTap: () => onSelectDay(i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.roleDriver
                          : Theme.of(context).cardTheme.color,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: selected
                              ? AppColors.roleDriver
                              : Theme.of(context).dividerColor),
                    ),
                    child: Column(
                      children: [
                        Text(
                          dayNames[i],
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: selected ? Colors.white : null),
                        ),
                        Text(
                          '${d.day}',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: selected
                                  ? Colors.white
                                  : Colors.grey.shade700),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        Expanded(
          child: trips.isEmpty
              ? EmptyState(
                  icon: Icons.directions_bus_outlined,
                  message: isAr ? 'لا توجد رحلات' : 'No trips',
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: trips.length,
                  itemBuilder: (_, i) => _TripCard(
                    trip: trips[i],
                    dayIndex: selectedDay,
                    dayName: dayNames[selectedDay],
                    showDay: false,
                    isAr: isAr,
                  ),
                ),
        ),
      ],
    );
  }
}

// ============================================================
// ===== التبويب 3: الأسابيع القادمة (4 أسابيع) =====
// ============================================================
class _UpcomingTrips extends StatelessWidget {
  final Bus bus;
  final bool isAr;
  const _UpcomingTrips({required this.bus, required this.isAr});

  @override
  Widget build(BuildContext context) {
    final repo = MockRepository();
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final dayNames = isAr
        ? ['الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد']
        : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    // اجمع كلّ الرحلات في الأسابيع الـ4 القادمة
    final allUpcoming = <_DatedTrip>[];
    final currentWeek = repo.currentWeekStart();
    for (int wOffset = 0; wOffset < 4; wOffset++) {
      final weekStart = currentWeek.add(Duration(days: wOffset * 7));
      final plan = repo.getOrCreateBusPlan(weekStart);
      for (int day = 0; day < 7; day++) {
        final tripDate = weekStart.add(Duration(days: day));
        if (tripDate.isBefore(todayDate)) continue; // أهمل الماضي
        final trips = _filterTripsForBusDay(
            plan.details, bus.id, day, weekStart, repo);
        for (final t in trips) {
          allUpcoming.add(_DatedTrip(
            trip: t,
            date: tripDate,
            dayIndex: day,
            weekStart: weekStart,
          ));
        }
      }
    }
    if (allUpcoming.isEmpty) {
      return EmptyState(
        icon: Icons.event_busy,
        message:
            isAr ? 'لا توجد رحلات في الأسابيع الـ4 القادمة' : 'No upcoming trips',
      );
    }
    // فرز بالتاريخ ثم الوقت
    allUpcoming.sort((a, b) {
      final cmp = a.date.compareTo(b.date);
      if (cmp != 0) return cmp;
      return a.trip.time.compareTo(b.trip.time);
    });
    // مجمَّعة بالتاريخ
    final grouped = <String, List<_DatedTrip>>{};
    for (final t in allUpcoming) {
      final key =
          '${t.date.year}-${t.date.month.toString().padLeft(2, "0")}-${t.date.day.toString().padLeft(2, "0")}';
      grouped.putIfAbsent(key, () => []).add(t);
    }
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        for (final entry in grouped.entries) ...[
          _DayHeader(
            date: entry.value.first.date,
            dayName: dayNames[entry.value.first.dayIndex],
            tripCount: entry.value.length,
            isAr: isAr,
          ),
          ...entry.value.map((dt) => _TripCard(
                trip: dt.trip,
                dayIndex: dt.dayIndex,
                dayName: dayNames[dt.dayIndex],
                showDay: false,
                isAr: isAr,
              )),
        ],
      ],
    );
  }
}

class _DayHeader extends StatelessWidget {
  final DateTime date;
  final String dayName;
  final int tripCount;
  final bool isAr;
  const _DayHeader({
    required this.date,
    required this.dayName,
    required this.tripCount,
    required this.isAr,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.roleDriver.withOpacity(0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border(
            right: BorderSide(color: AppColors.roleDriver, width: 3)),
      ),
      child: Row(
        children: [
          Icon(Icons.calendar_today,
              size: 12, color: AppColors.roleDriver),
          const SizedBox(width: 6),
          Text(
            '$dayName ${date.day}/${date.month}/${date.year}',
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: AppColors.roleDriver),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.roleDriver,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              isAr ? '$tripCount رحلة' : '$tripCount trips',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _DatedTrip {
  final BusPlanDetail trip;
  final DateTime date;
  final int dayIndex;
  final DateTime weekStart;
  _DatedTrip({
    required this.trip,
    required this.date,
    required this.dayIndex,
    required this.weekStart,
  });
}

// ============================================================
// ===== تنبيه الرحلة القادمة =====
// ============================================================
class _UpcomingTripBanner extends StatelessWidget {
  final List<BusPlanDetail> trips;
  final bool isAr;
  const _UpcomingTripBanner(
      {required this.trips, required this.isAr});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    BusPlanDetail? next;
    int? minMinutesAway;
    for (final t in trips) {
      final p = t.time.split(':');
      if (p.length != 2) continue;
      final h = int.tryParse(p[0]) ?? 0;
      final m = int.tryParse(p[1]) ?? 0;
      final tripDt = DateTime(now.year, now.month, now.day, h, m);
      final diff = tripDt.difference(now).inMinutes;
      if (diff < 0) continue; // فات
      if (minMinutesAway == null || diff < minMinutesAway) {
        minMinutesAway = diff;
        next = t;
      }
    }
    if (next == null || minMinutesAway == null || minMinutesAway > 60) {
      return const SizedBox.shrink();
    }
    final isImminent = minMinutesAway <= 15;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: (isImminent ? AppColors.danger : AppColors.warning)
            .withOpacity(0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: isImminent ? AppColors.danger : AppColors.warning,
            width: 1.5),
      ),
      child: Row(
        children: [
          Icon(
            isImminent
                ? Icons.alarm
                : Icons.notifications_active_outlined,
            color: isImminent ? AppColors.danger : AppColors.warning,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isImminent
                      ? (isAr
                          ? '🚨 رحلة قادمة خلال $minMinutesAway دقيقة!'
                          : '🚨 Trip in $minMinutesAway min!')
                      : (isAr
                          ? '⏰ رحلة قادمة خلال $minMinutesAway دقيقة'
                          : '⏰ Trip in $minMinutesAway min'),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: isImminent
                          ? AppColors.danger
                          : AppColors.warning),
                ),
                const SizedBox(height: 2),
                Text(
                  '🕐 ${next.time} • ${MockRepository().siteById(next.siteId)?.displayName ?? "—"} • ${next.employeeIds.length} ${isAr ? "ركّاب" : "pax"}',
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// ===== بطاقة الرحلة (محسَّنة) =====
// ============================================================
class _TripCard extends StatelessWidget {
  final BusPlanDetail trip;
  final int dayIndex;
  final String dayName;
  final bool showDay;
  final bool isAr;
  const _TripCard({
    required this.trip,
    required this.dayIndex,
    required this.dayName,
    required this.showDay,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    // 🆕 ابحَث في sites أَوّلاً، ثُمَّ points كَـfallback
    final site = repo.siteById(trip.siteId);
    final point = site == null ? repo.pointById(trip.siteId) : null;
    final locationName = site?.displayName ?? point?.name ?? '—';
    int present = 0, missing = 0, changed = 0;
    for (final eid in trip.employeeIds) {
      final att = repo.busAttendance.firstWhere(
        (a) => a.busPlanDetailId == trip.id && a.employeeId == eid,
        orElse: () => BusTripAttendance(
            id: '', busPlanDetailId: '', employeeId: eid),
      );
      if (att.id.isEmpty) continue;
      switch (att.status) {
        case BusAttendanceStatus.present:
          present++;
          break;
        case BusAttendanceStatus.missing:
          missing++;
          break;
        case BusAttendanceStatus.changed:
          changed++;
          break;
      }
    }
    final attendanceStarted = present + missing + changed > 0;
    final allMarked =
        present + missing + changed == trip.employeeIds.length;
    // حالة الرحلة
    final TripStatus status = allMarked
        ? TripStatus.completed
        : attendanceStarted
            ? TripStatus.inProgress
            : TripStatus.scheduled;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: status.color.withOpacity(0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.roleDriver,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(trip.time,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 14)),
              ),
              const SizedBox(width: 8),
              // 🆕 شارة الاتِجاه IN/OUT
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: (trip.direction == TripDirection.tripIn
                          ? AppColors.success
                          : AppColors.warning)
                      .withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: trip.direction == TripDirection.tripIn
                        ? AppColors.success
                        : AppColors.warning,
                    width: 0.6,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      trip.direction == TripDirection.tripIn
                          ? Icons.south_east
                          : Icons.north_west,
                      size: 11,
                      color: trip.direction == TripDirection.tripIn
                          ? AppColors.success
                          : AppColors.warning,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      trip.direction == TripDirection.tripIn
                          ? 'IN'
                          : 'OUT',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: trip.direction == TripDirection.tripIn
                              ? AppColors.success
                              : AppColors.warning),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(locationName,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800)),
                    if (showDay)
                      Text(dayName,
                          style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade600)),
                  ],
                ),
              ),
              // 🆕 شارة حالة الرحلة
              _StatusBadge(status: status, isAr: isAr),
              const SizedBox(width: 6),
              // عداد الركّاب
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.brand.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.people,
                        size: 12, color: AppColors.brand),
                    const SizedBox(width: 3),
                    Text('${trip.employeeIds.length}',
                        style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.brand,
                            fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
            ],
          ),
          // 🆕 أَسماء المُوَظَّفين في هذه الرَحلة (مُلَخَّص)
          if (trip.employeeIds.isNotEmpty) ...[
            const SizedBox(height: 6),
            Builder(builder: (_) {
              final names = trip.employeeIds
                  .take(3)
                  .map((id) {
                    try {
                      return repo.employees
                          .firstWhere((e) => e.id == id)
                          .fullName;
                    } catch (_) {
                      return '?';
                    }
                  })
                  .toList();
              final more = trip.employeeIds.length - names.length;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Icon(Icons.person_outline,
                        size: 12, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        names.join(' · ') +
                            (more > 0
                                ? ' + $more ${isAr ? "آخَرون" : "more"}'
                                : ''),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
          if (attendanceStarted) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                _Badge(
                    label: s.markPresent,
                    count: present,
                    color: AppColors.success),
                const SizedBox(width: 4),
                _Badge(
                    label: s.markMissing,
                    count: missing,
                    color: AppColors.danger),
                const SizedBox(width: 4),
                _Badge(
                    label: s.markChanged,
                    count: changed,
                    color: AppColors.warning),
              ],
            ),
          ],
          const SizedBox(height: 8),
          // 🆕 زرّ التفاصيل + قائمة الركّاب + الحضور
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => DriverAttendance(trip: trip),
            )),
            icon: const Icon(Icons.fact_check, size: 14),
            label: Text(s.attendance,
                style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

/// 🆕 حالة الرحلة (مَحسوبة)
enum TripStatus { scheduled, inProgress, completed }

extension TripStatusX on TripStatus {
  Color get color {
    switch (this) {
      case TripStatus.scheduled:
        return Colors.grey;
      case TripStatus.inProgress:
        return AppColors.warning;
      case TripStatus.completed:
        return AppColors.success;
    }
  }

  IconData get icon {
    switch (this) {
      case TripStatus.scheduled:
        return Icons.schedule;
      case TripStatus.inProgress:
        return Icons.directions_run;
      case TripStatus.completed:
        return Icons.check_circle;
    }
  }
}

class _StatusBadge extends StatelessWidget {
  final TripStatus status;
  final bool isAr;
  const _StatusBadge({required this.status, required this.isAr});
  @override
  Widget build(BuildContext context) {
    String label;
    switch (status) {
      case TripStatus.scheduled:
        label = isAr ? 'مجدوَلة' : 'Scheduled';
        break;
      case TripStatus.inProgress:
        label = isAr ? 'جارية' : 'In progress';
        break;
      case TripStatus.completed:
        label = isAr ? 'مكتملة' : 'Done';
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: status.color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: status.color.withOpacity(0.40)),
      ),
      child: Row(
        children: [
          Icon(status.icon, size: 11, color: status.color),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: status.color)),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _Badge(
      {required this.label, required this.count, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text('$count $label',
          style: TextStyle(
              color: color, fontSize: 9, fontWeight: FontWeight.w800)),
    );
  }
}

// ============================================================
// ===== شاشة الحضور (مع اتصال للموظّف) =====
// ============================================================
class DriverAttendance extends StatefulWidget {
  final BusPlanDetail trip;
  const DriverAttendance({super.key, required this.trip});

  @override
  State<DriverAttendance> createState() => _DriverAttendanceState();
}

class _DriverAttendanceState extends State<DriverAttendance> {
  void _setStatus(String empId, BusAttendanceStatus status) {
    final repo = MockRepository();
    final existing = repo.busAttendance.firstWhere(
      (a) => a.busPlanDetailId == widget.trip.id && a.employeeId == empId,
      orElse: () => BusTripAttendance(
          id: '', busPlanDetailId: widget.trip.id, employeeId: empId),
    );
    if (existing.id.isEmpty) {
      repo.busAttendance.add(BusTripAttendance(
        id: repo.generateId(),
        busPlanDetailId: widget.trip.id,
        employeeId: empId,
        status: status,
        markedAt: DateTime.now(),
      ));
    } else {
      existing.status = status;
      existing.markedAt = DateTime.now();
    }
    repo.notifyListeners();
    setState(() {});
  }

  /// 🆕 عِندَ الضَغط على "مُتَغَيِّر" — يَفتَح قائِمة الموظَّفين لِاختيار البَديل
  /// تَستَخدِم نَفس قَواعِد فَلتَرة Roster Creator (إعدادات إسناد النِقاط)
  Future<void> _markChangedWithReplacement(String originalEmpId) async {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final repo = MockRepository();
    final original = repo.employeeById(originalEmpId);

    // 🆕 احسُب الموظَّفين المُؤَهَّلين بِنَفس قَواعِد Roster Creator:
    //   - نَشِط (active)
    //   - نَفس دَولة النُقطة
    //   - مُسَمَّى وَظيفيّ مَسموح في إعدادات الفِلتَرة
    //   - لَيس مَوجوداً أَصلاً في نَفس الرَحلة
    await RosterEmployeeFilterSettings.instance.load();
    final filter = RosterEmployeeFilterSettings.instance;
    final point = repo.pointById(widget.trip.siteId);
    final pointCountry = point?.countryId;
    final alreadyInTrip = widget.trip.employeeIds.toSet();

    final eligibleIds = repo.employees.where((e) {
      if (e.id == originalEmpId) return false;
      if (alreadyInTrip.contains(e.id)) return false;
      if (filter.onlyActive && e.status != EntityStatus.active) return false;
      if (pointCountry != null && e.countryId != pointCountry) return false;
      if (!filter.isJobTitleAllowed(e.jobTitleId)) return false;
      return true;
    }).map((e) => e.id).toSet();

    final replacement = await showModalBottomSheet<Employee>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _EmployeePickerSheet(
        title: isAr
            ? 'اختَر البَديل لِـ${original?.fullName ?? ""}'
            : 'Pick replacement for ${original?.fullName ?? ""}',
        includeOnlyIds: eligibleIds,
      ),
    );

    if (replacement == null) return;

    // سَجِّل الحالة "مُتَغَيِّر" مَع مُلاحَظات تَحوي اسم/كود البَديل
    final note =
        'replaced_by:${replacement.id}|${replacement.fullName} (${replacement.code})';
    final att = repo.busAttendance.firstWhere(
      (a) =>
          a.busPlanDetailId == widget.trip.id &&
          a.employeeId == originalEmpId,
      orElse: () => BusTripAttendance(
        id: '',
        busPlanDetailId: widget.trip.id,
        employeeId: originalEmpId,
      ),
    );
    setState(() {
      att.status = BusAttendanceStatus.changed;
      att.notes = note;
      att.markedAt = DateTime.now();
      if (att.id.isEmpty) {
        // أَنشِئ صَفّاً جَديداً
        repo.busAttendance.add(BusTripAttendance(
          id: repo.generateId(),
          busPlanDetailId: widget.trip.id,
          employeeId: originalEmpId,
          status: BusAttendanceStatus.changed,
          notes: note,
          markedAt: DateTime.now(),
        ));
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.warning,
        content: Text(isAr
            ? 'تَمَّ التَبديل بِـ${replacement.fullName}'
            : 'Replaced with ${replacement.fullName}'),
      ));
    }

    // 🆕 أَرسِل إشعارات لِلمُحَدَّدين في إعدادات إشعار التَبديل
    unawaited(_dispatchReplacementNotifications(
      original: original,
      replacement: replacement,
    ));
  }

  /// 🆕 إرسال إشعارات داخل التَطبيق + بَريد إلكتروني (إذا مُفَعَّل)
  /// عِندَ تَبديل مُوظَّف غائِب بِبَديل في رِحلة.
  Future<void> _dispatchReplacementNotifications({
    required Employee? original,
    required Employee replacement,
  }) async {
    try {
      await ReplacementNotificationSettings.instance.load();
      final cfg = ReplacementNotificationSettings.instance;
      final repo = MockRepository();
      final point = repo.pointById(widget.trip.siteId);
      final pointName = point?.name ?? '—';
      final tripTime = widget.trip.time;

      final title = 'تَبديل في رِحلة $pointName ($tripTime)';
      final body = original == null
          ? 'تَمَّ إضافة ${replacement.fullName} (${replacement.code}) كَبَديل.'
          : 'تَمَّ تَبديل ${original.fullName} (${original.code}) بِـ${replacement.fullName} (${replacement.code}).';

      // 1) إشعارات داخِل التَطبيق
      if (cfg.inAppEnabled && cfg.recipientUserIds.isNotEmpty) {
        await NotificationsService.instance.createBulk(
          userIds: cfg.recipientUserIds.toList(),
          title: title,
          body: body,
          type: 'bus_replacement',
          priority: 'high',
          entityType: 'bus_plan_detail',
          entityId: widget.trip.id,
          iconEmoji: '🔁',
        );
      }

      // 2) بَريد إلكترونيّ — عَبر Supabase Edge Function `send-email`
      //    (إن لم تَكُن مُنشَأة بَعد، يَفشَل بِهُدوء.)
      if (cfg.emailEnabled && cfg.recipientEmails.isNotEmpty) {
        final supa = SupabaseService();
        if (supa.isReady) {
          try {
            await supa.client.functions.invoke('send-email', body: {
              'to': cfg.recipientEmails.toList(),
              'subject': title,
              'text': body,
              'metadata': {
                'event': 'bus_replacement',
                'busPlanDetailId': widget.trip.id,
                'pointName': pointName,
                'tripTime': tripTime,
                'originalEmployeeId': original?.id,
                'originalEmployeeName': original?.fullName,
                'replacementEmployeeId': replacement.id,
                'replacementEmployeeName': replacement.fullName,
              },
            });
          } catch (_) {
            // Edge Function غَير مُعَدَّة بَعد — تَجاهُل صامِت.
          }
        }
      }
    } catch (_) {/* أَيّ خَطَأ في الإشعارات لا يَجِب أَن يَكسِر التَبديل */}
  }

  /// 🆕 اتصال أو واتساب لموظّف معيّن
  void _callEmployee(Employee emp) {
    final phone = emp.mobile.trim();
    if (phone.isEmpty) return;
    final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    html.window.open('tel:$cleaned', '_self');
  }

  void _whatsappEmployee(Employee emp) {
    final phone = emp.mobile.trim();
    if (phone.isEmpty) return;
    final cleaned = phone.replaceAll(RegExp(r'[^\d]'), '');
    html.window.open('https://wa.me/$cleaned', '_blank');
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    // 🆕 ابحَث في sites أَوّلاً، ثُمَّ points كَـfallback
    final site = repo.siteById(widget.trip.siteId);
    final point = site == null ? repo.pointById(widget.trip.siteId) : null;
    final locationName = site?.displayName ?? point?.name ?? '';

    final bus = repo.buses.firstWhere(
      (b) => b.id == widget.trip.busId,
      orElse: () => repo.buses.isNotEmpty
          ? repo.buses.first
          : Bus(id: '', name: '', plateNumber: '', capacity: 0),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(s.attendance),
        backgroundColor: AppColors.roleDriver,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // 🆕 بانِر النُقطة + الباص + الوَقت في الأَعلى
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.roleDriver, AppColors.brand],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.location_on,
                        color: Colors.white, size: 22),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        locationName.isEmpty
                            ? (s.isAr ? 'نُقطة غَير مُحَدَّدة' : 'Unknown point')
                            : locationName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.20),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        widget.trip.time,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 14),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.directions_bus,
                        color: Colors.white70, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      '${bus.name} · ${bus.plateNumber}',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(width: 12),
                    const Icon(Icons.people,
                        color: Colors.white70, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      '${widget.trip.employeeIds.length} ${s.isAr ? "مُوظَّف" : "employees"}',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: widget.trip.employeeIds.length,
              itemBuilder: (_, i) {
          final empId = widget.trip.employeeIds[i];
          final emp = repo.employeeById(empId);
          if (emp == null) return const SizedBox.shrink();
          final att = repo.busAttendance.firstWhere(
            (a) =>
                a.busPlanDetailId == widget.trip.id && a.employeeId == empId,
            orElse: () => BusTripAttendance(
                id: '', busPlanDetailId: widget.trip.id, employeeId: empId),
          );
          final current = att.id.isEmpty ? null : att.status;
          final hasPhone = emp.mobile.trim().isNotEmpty;
          // 🆕 إذا الموظَّف "مُتَغَيِّر"، اِستَخرِج اسم البَديل من الـnotes
          String? replacementLabel;
          if (current == BusAttendanceStatus.changed &&
              att.notes != null &&
              att.notes!.startsWith('replaced_by:')) {
            final parts = att.notes!.split('|');
            if (parts.length >= 2) {
              replacementLabel = parts[1]; // "fullName (code)"
            }
          }
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: EmployeeIdentity(
                        employee: emp,
                        size: EmployeeIdentitySize.normal,
                        showCode: true,
                        avatarColor: AppColors.roleDriver,
                      ),
                    ),
                    // 🆕 اتصال + واتساب للموظّف
                    if (hasPhone) ...[
                      IconButton(
                        iconSize: 18,
                        icon: const Icon(Icons.call,
                            color: AppColors.success),
                        tooltip: s.isAr ? 'اتصال' : 'Call',
                        onPressed: () => _callEmployee(emp),
                      ),
                      IconButton(
                        iconSize: 18,
                        icon: const Icon(Icons.chat_bubble,
                            color: Color(0xFF25D366)),
                        tooltip: 'WhatsApp',
                        onPressed: () => _whatsappEmployee(emp),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _ActionBtn(
                      label: s.markPresent,
                      color: AppColors.success,
                      selected: current == BusAttendanceStatus.present,
                      onTap: () =>
                          _setStatus(empId, BusAttendanceStatus.present),
                    ),
                    const SizedBox(width: 6),
                    _ActionBtn(
                      label: s.markMissing,
                      color: AppColors.danger,
                      selected: current == BusAttendanceStatus.missing,
                      onTap: () =>
                          _setStatus(empId, BusAttendanceStatus.missing),
                    ),
                    const SizedBox(width: 6),
                    _ActionBtn(
                      label: s.markChanged,
                      color: AppColors.warning,
                      selected: current == BusAttendanceStatus.changed,
                      onTap: () => _markChangedWithReplacement(empId),
                    ),
                  ],
                ),
                // 🆕 اِعرِض اسم البَديل
                if (replacementLabel != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: AppColors.warning.withOpacity(0.30)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.swap_horiz,
                            size: 14, color: AppColors.warning),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            s.isAr
                                ? 'البَديل: $replacementLabel'
                                : 'Replaced by: $replacementLabel',
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.warning,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                  ],
                ),
              );
            },
          ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 🆕 شاشة إضافة رَحلة خارِج الخُطّة (لِلسائِق)
// الباص = باص السائِق (تلقائيّاً). يَختار: النُقطة + الوَقت + المُوظَّفين
// ============================================================
class _OffPlanTripSheet extends StatefulWidget {
  final Bus bus;
  final bool isAr;
  const _OffPlanTripSheet({required this.bus, required this.isAr});

  @override
  State<_OffPlanTripSheet> createState() => _OffPlanTripSheetState();
}

class _OffPlanTripSheetState extends State<_OffPlanTripSheet> {
  String? _pointId;
  TimeOfDay _time = TimeOfDay.now();
  final Set<String> _selectedEmpIds = <String>{};
  bool _saving = false;

  Future<void> _pickTime() async {
    final result = await showTimePicker(
      context: context,
      initialTime: _time,
    );
    if (result != null) setState(() => _time = result);
  }

  Future<void> _addEmployees() async {
    final picked = await showModalBottomSheet<List<Employee>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _MultiEmployeePickerSheet(
        title: widget.isAr ? 'اختَر المُوظَّفين' : 'Select employees',
        excludeIds: _selectedEmpIds,
      ),
    );
    if (picked != null) {
      setState(() {
        for (final e in picked) {
          _selectedEmpIds.add(e.id);
        }
      });
    }
  }

  Future<void> _save() async {
    final isAr = widget.isAr;
    if (_pointId == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text(isAr ? 'اختَر النُقطة' : 'Pick a point'),
      ));
      return;
    }
    setState(() => _saving = true);
    try {
      final repo = MockRepository();
      final today = DateTime.now();
      final week = repo.currentWeekStart();
      final dayIndex = today.weekday - 1;
      final timeStr =
          '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';

      final plan = repo.getOrCreateBusPlan(week);
      final detail = BusPlanDetail(
        id: repo.generateId(),
        busId: widget.bus.id,
        siteId: _pointId!,
        dayIndex: dayIndex,
        time: timeStr,
        employeeIds: _selectedEmpIds.toList(),
      );
      plan.details.add(detail);
      repo.notifyListeners();

      if (!mounted) return;
      Navigator.pop(context, detail);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.danger,
          content: Text('$e'),
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = widget.isAr;
    final repo = MockRepository();
    final points = repo.points;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      expand: false,
      // 🆕 خَلفيّة صَلبة لِتَجاوُز الـ BrandedBackground (لُوغو الأَسَد) الذي
      //   يَظهَر مِن خَلف أَيّ widget بِخَلفيّة شَفّافة.
      builder: (_, scrollController) => Material(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1F2937)
            : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        clipBehavior: Clip.antiAlias,
        elevation: 16,
        child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.brand,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                const Icon(Icons.add_road,
                    color: AppColors.gold, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isAr
                        ? '➕ إضافة رَحلة خارِج الخُطّة'
                        : '➕ Add off-plan trip',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 14),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.gold),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(14),
              children: [
                // ===== الباص (تلقائيّ — لِلعَرض فَقَط) =====
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.info.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppColors.info.withOpacity(0.30)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.directions_bus,
                          color: AppColors.info),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isAr ? 'الباص' : 'Bus',
                              style: const TextStyle(
                                  fontSize: 10, color: Colors.grey),
                            ),
                            Text(
                              '${widget.bus.name} · ${widget.bus.plateNumber}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ===== النُقطة =====
                Text(
                  isAr ? '📍 النُقطة *' : '📍 Point *',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: _pointId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.location_on),
                  ),
                  items: points
                      .map((p) => DropdownMenuItem(
                            value: p.id,
                            child: Text(p.name),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _pointId = v),
                ),
                const SizedBox(height: 16),

                // ===== الوَقت =====
                Text(
                  isAr ? '🕐 الوَقت *' : '🕐 Time *',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                InkWell(
                  onTap: _pickTime,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: Theme.of(context).dividerColor),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.access_time),
                        const SizedBox(width: 8),
                        Text(
                          _time.format(context),
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ===== المُوظَّفون =====
                Row(
                  children: [
                    Text(
                      isAr
                          ? '👥 المُوظَّفون (${_selectedEmpIds.length})'
                          : '👥 Employees (${_selectedEmpIds.length})',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      icon: const Icon(Icons.add),
                      label: Text(isAr ? 'إضافة' : 'Add'),
                      onPressed: _addEmployees,
                    ),
                  ],
                ),
                if (_selectedEmpIds.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Text(
                      isAr
                          ? 'لا مُوظَّفين بَعد — اضغَط "إضافة"'
                          : 'No employees yet — tap "Add"',
                      style:
                          const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  )
                else
                  for (final id in _selectedEmpIds)
                    Builder(builder: (_) {
                      final e = repo.employeeById(id);
                      if (e == null) return const SizedBox.shrink();
                      return Card(
                        margin: const EdgeInsets.only(bottom: 4),
                        child: ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            backgroundColor:
                                AppColors.brand.withOpacity(0.12),
                            radius: 16,
                            child: Text(
                              e.fullName.isNotEmpty
                                  ? e.fullName.substring(0, 1).toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12),
                            ),
                          ),
                          title: Text(e.fullName,
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800)),
                          subtitle: Text(e.code,
                              style: const TextStyle(fontSize: 10)),
                          trailing: IconButton(
                            icon: const Icon(Icons.close,
                                color: AppColors.danger, size: 16),
                            onPressed: () =>
                                setState(() => _selectedEmpIds.remove(id)),
                          ),
                        ),
                      );
                    }),

                const SizedBox(height: 80),
              ],
            ),
          ),
          // Save button
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save),
                label: Text(isAr ? 'حِفظ الرَحلة' : 'Save Trip'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(50),
                ),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

// ============================================================
// 🆕 مُختار مُتَعَدِّد لِلمُوظَّفين
// ============================================================
class _MultiEmployeePickerSheet extends StatefulWidget {
  final String title;
  final Set<String> excludeIds;
  const _MultiEmployeePickerSheet({
    required this.title,
    this.excludeIds = const {},
  });

  @override
  State<_MultiEmployeePickerSheet> createState() =>
      _MultiEmployeePickerSheetState();
}

class _MultiEmployeePickerSheetState extends State<_MultiEmployeePickerSheet> {
  String _filter = '';
  final Set<String> _picked = <String>{};

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final repo = MockRepository();
    final query = _filter.trim().toLowerCase();
    final list = repo.employees.where((e) {
      if (widget.excludeIds.contains(e.id)) return false;
      if (e.status != EntityStatus.active) return false;
      if (query.isEmpty) return true;
      return e.fullName.toLowerCase().contains(query) ||
          e.code.toLowerCase().contains(query) ||
          e.mobile.contains(query);
    }).toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      expand: false,
      // 🆕 خَلفيّة صَلبة لِتَجاوُز الـ BrandedBackground (لُوغو الأَسَد) الذي
      //   يَظهَر مِن خَلف أَيّ widget بِخَلفيّة شَفّافة.
      builder: (_, scrollController) => Material(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1F2937)
            : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        clipBehavior: Clip.antiAlias,
        elevation: 16,
        child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.brand,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    final selected =
                        list.where((e) => _picked.contains(e.id)).toList();
                    Navigator.pop(context, selected);
                  },
                  child: Text(
                    '${isAr ? "تَمّ" : "Done"} (${_picked.length})',
                    style: const TextStyle(color: AppColors.gold),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: TextField(
              autofocus: true,
              decoration: InputDecoration(
                hintText: isAr
                    ? 'بَحث بِالاسم أَو الكود…'
                    : 'Search by name or code…',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text(
                      isAr ? 'لا نَتائِج' : 'No matches',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  )
                : ListView.builder(
                    controller: scrollController,
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final e = list[i];
                      final picked = _picked.contains(e.id);
                      return CheckboxListTile(
                        value: picked,
                        onChanged: (v) {
                          setState(() {
                            if (v == true) {
                              _picked.add(e.id);
                            } else {
                              _picked.remove(e.id);
                            }
                          });
                        },
                        title: Text(e.fullName,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13)),
                        subtitle: Text(
                          '${e.code}${e.mobile.isNotEmpty ? " · ${e.mobile}" : ""}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        secondary: CircleAvatar(
                          backgroundColor:
                              AppColors.brand.withOpacity(0.12),
                          child: Text(
                            e.fullName.isNotEmpty
                                ? e.fullName.substring(0, 1).toUpperCase()
                                : '?',
                            style: const TextStyle(
                                color: AppColors.brand,
                                fontWeight: FontWeight.w900),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      ),
    );
  }
}

// ============================================================
// 🆕 مُختار مُوظَّفين بِبَحث (اسم/كود)
// ============================================================
class _EmployeePickerSheet extends StatefulWidget {
  final String title;
  final Set<String> excludeIds;
  // 🆕 إذا تَمّ تَمريرها، يُعرَض فَقَط الموظَّفين الذين معرَّفاتهم ضِمنها
  // (تَستَخدِمها شاشة "متغيب" لِتَطبيق فَلاتِر RosterEmployeeFilterSettings)
  final Set<String>? includeOnlyIds;
  const _EmployeePickerSheet({
    required this.title,
    this.excludeIds = const {},
    this.includeOnlyIds,
  });

  @override
  State<_EmployeePickerSheet> createState() => _EmployeePickerSheetState();
}

class _EmployeePickerSheetState extends State<_EmployeePickerSheet> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final repo = MockRepository();
    final query = _filter.trim().toLowerCase();
    final list = repo.employees.where((e) {
      // عند تَمرير includeOnlyIds: نَعرِض فَقَط من ضِمن القائِمة
      if (widget.includeOnlyIds != null &&
          !widget.includeOnlyIds!.contains(e.id)) {
        return false;
      }
      if (widget.excludeIds.contains(e.id)) return false;
      // إذا includeOnlyIds مَوجودة فالتَصفِية حَدَثت مُسبَقاً، تَجاوز فَحص status
      if (widget.includeOnlyIds == null && e.status != EntityStatus.active) {
        return false;
      }
      if (query.isEmpty) return true;
      return e.fullName.toLowerCase().contains(query) ||
          e.code.toLowerCase().contains(query) ||
          (e.mobile).contains(query);
    }).toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      expand: false,
      // 🆕 خَلفيّة صَلبة لِتَجاوُز الـ BrandedBackground (لُوغو الأَسَد) الذي
      //   يَظهَر مِن خَلف أَيّ widget بِخَلفيّة شَفّافة.
      builder: (_, scrollController) => Material(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1F2937)
            : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        clipBehavior: Clip.antiAlias,
        elevation: 16,
        child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.roleDriver,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                const Icon(Icons.person_search,
                    color: Colors.white, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 14),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          // Search
          Padding(
            padding: const EdgeInsets.all(10),
            child: TextField(
              autofocus: true,
              decoration: InputDecoration(
                hintText: isAr
                    ? 'ابحَث بِالاسم أَو الكود أَو الهاتِف…'
                    : 'Search by name, code, or phone…',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
          // Count
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                isAr
                    ? '${list.length} مُوظَّف'
                    : '${list.length} employees',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
          ),
          // List
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text(
                      isAr ? 'لا نَتائِج' : 'No matches',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  )
                : ListView.builder(
                    controller: scrollController,
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final e = list[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              AppColors.roleDriver.withOpacity(0.15),
                          child: Text(
                            e.fullName.isNotEmpty
                                ? e.fullName.substring(0, 1).toUpperCase()
                                : '?',
                            style: const TextStyle(
                                color: AppColors.roleDriver,
                                fontWeight: FontWeight.w900),
                          ),
                        ),
                        title: Text(
                          e.fullName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 13),
                        ),
                        subtitle: Text(
                          '${e.code}${e.mobile.isNotEmpty ? " · ${e.mobile}" : ""}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing:
                            const Icon(Icons.chevron_right, color: Colors.grey),
         