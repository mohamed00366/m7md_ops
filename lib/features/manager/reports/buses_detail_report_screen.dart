import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/services/excel_exporter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../repositories/mock_repository.dart';

/// 🚌 تقارير الباصات التفصيليّة (4 تبويبات)
///
/// 1. **الجدول اليومي**: لكلّ باص، رحلاته اليومية مرتّبة بالساعة
/// 2. **الزمني الموحَّد**: كلّ الرحلات مع كلّ الباصات بترتيب زمني
/// 3. **استغلال السعة**: كم % من سعة كلّ باص مُستغلّة + تنبيهات
/// 4. **حسب النقطة**: لكلّ نقطة، الباصات التي تَخدمها وعدد الموظّفين
class BusesDetailReportScreen extends StatefulWidget {
  /// الأسبوع الافتراضي (اختياري — يبدأ بأسبوع اليوم)
  final DateTime? initialWeek;
  const BusesDetailReportScreen({super.key, this.initialWeek});

  @override
  State<BusesDetailReportScreen> createState() =>
      _BusesDetailReportScreenState();
}

class _BusesDetailReportScreenState extends State<BusesDetailReportScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  late DateTime _weekStart;
  int _dayIndex = DateTime.now().weekday - 1;
  String? _filterBusId;
  String? _filterPointId;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _weekStart =
        widget.initialWeek ?? MockRepository().currentWeekStart();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  /// كلّ التفاصيل (BusPlanDetail) للأسبوع الحالي + الفلاتر، مع
  /// قائمة موظّفين مَحلولة (resolveEmployeeBusId).
  List<_TripRow> _allTripsForWeek() {
    final repo = MockRepository();
    final plan = repo.getOrCreateBusPlan(_weekStart);
    final result = <_TripRow>[];
    for (final d in plan.details) {
      // ابنِ خريطة busId → empIds (موظّفون فعليّاً ينتقلون بهذا الباص)
      final byBus = <String, List<String>>{};
      for (final eid in d.employeeIds.toSet()) {
        final actualBus = repo.resolveEmployeeBusId(
          employeeId: eid,
          weekStart: _weekStart,
          dayIndex: d.dayIndex,
        );
        if (actualBus == null || actualBus.isEmpty) continue;
        byBus.putIfAbsent(actualBus, () => []).add(eid);
      }
      // كلّ باص في هذه الـdetail يُصبح rowاً منفصلاً
      for (final entry in byBus.entries) {
        final busId = entry.key;
        final empIds = entry.value;
        if (_filterBusId != null && busId != _filterBusId) continue;
        if (_filterPointId != null && d.siteId != _filterPointId) continue;
        result.add(_TripRow(
          busId: busId,
          pointId: d.siteId,
          dayIndex: d.dayIndex,
          time: d.time,
          employeeIds: empIds,
        ));
      }
    }
    return result;
  }

  /// رحلات يوم واحد فقط
  List<_TripRow> _tripsForDay(int dayIndex) =>
      _allTripsForWeek().where((t) => t.dayIndex == dayIndex).toList()
        ..sort((a, b) => a.time.compareTo(b.time));

  String _fmt(DateTime d) =>
      '${d.day}/${d.month.toString().padLeft(2, "0")}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final repo = MockRepository();
    final dayNames = isAr
        ? ['الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد']
        : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    final weekTrips = _allTripsForWeek();
    final dayTrips = _tripsForDay(_dayIndex);
    final totalEmpsDay =
        dayTrips.fold<int>(0, (a, t) => a + t.employeeIds.length);
    final usedBuses = dayTrips.map((t) => t.busId).toSet().length;

    return Scaffold(
      appBar: AppBar(
        title: Text(isAr ? 'تقارير الباصات' : 'Buses Reports'),
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
        actions: [
          // 🆕 تصدير Excel
          IconButton(
            tooltip: 'Export Excel',
            icon: const Icon(Icons.table_chart_outlined),
            onPressed: () => _exportExcel(weekTrips, isAr, dayNames),
          ),
        ],
      ),
      body: Column(
        children: [
          // ===== متصفّح الأسبوع =====
          Container(
            color: Theme.of(context).cardTheme.color,
            padding:
                const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  iconSize: 18,
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => setState(
                      () => _weekStart = _weekStart
                          .subtract(const Duration(days: 7))),
                ),
                Text(
                  '${_fmt(_weekStart)} - ${_fmt(_weekStart.add(const Duration(days: 6)))}',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800),
                ),
                IconButton(
                  iconSize: 18,
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => setState(
                      () => _weekStart = _weekStart
                          .add(const Duration(days: 7))),
                ),
                const SizedBox(width: 8),
                if (_weekStart != repo.currentWeekStart())
                  TextButton(
                    onPressed: () => setState(
                        () => _weekStart = repo.currentWeekStart()),
                    child: Text(isAr ? 'اليوم' : 'Today',
                        style: const TextStyle(fontSize: 11)),
                  ),
              ],
            ),
          ),
          // ===== مَنتقي اليوم =====
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: List.generate(7, (i) {
                final selected = i == _dayIndex;
                return Padding(
                  padding: const EdgeInsetsDirectional.only(end: 4),
                  child: ChoiceChip(
                    selected: selected,
                    label: Text(dayNames[i],
                        style: const TextStyle(fontSize: 11)),
                    onSelected: (_) => setState(() => _dayIndex = i),
                  ),
                );
              }),
            ),
          ),
          // ===== الفلاتر (باص / نقطة) =====
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    value: _filterBusId,
                    isDense: true,
                    decoration: InputDecoration(
                      labelText: isAr ? 'باص' : 'Bus',
                      labelStyle: const TextStyle(fontSize: 10),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(
                          value: null,
                          child: Text(isAr ? 'كلّ الباصات' : 'All',
                              style: const TextStyle(fontSize: 11))),
                      ...repo.buses.map((b) => DropdownMenuItem(
                            value: b.id,
                            child: Text(b.name,
                                style: const TextStyle(fontSize: 11)),
                          )),
                    ],
                    onChanged: (v) => setState(() => _filterBusId = v),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    value: _filterPointId,
                    isDense: true,
                    decoration: InputDecoration(
                      labelText: isAr ? 'نقطة' : 'Point',
                      labelStyle: const TextStyle(fontSize: 10),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(
                          value: null,
                          child: Text(isAr ? 'كلّ النقاط' : 'All',
                              style: const TextStyle(fontSize: 11))),
                      ...repo.points.map((p) => DropdownMenuItem(
                            value: p.id,
                            child: Text(p.name,
                                style: const TextStyle(fontSize: 11)),
                          )),
                    ],
                    onChanged: (v) => setState(() => _filterPointId = v),
                  ),
                ),
              ],
            ),
          ),
          // ===== KPIs =====
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                _Kpi(
                    label: isAr ? 'رحلات اليوم' : 'Trips today',
                    value: '${dayTrips.length}',
                    color: AppColors.brand),
                const SizedBox(width: 4),
                _Kpi(
                    label: isAr ? 'موظّفون' : 'Pax',
                    value: '$totalEmpsDay',
                    color: AppColors.success),
                const SizedBox(width: 4),
                _Kpi(
                    label: isAr ? 'باصات نشطة' : 'Active buses',
                    value: '$usedBuses',
                    color: AppColors.info),
              ],
            ),
          ),
          // ===== التبويبات =====
          Container(
            color: Theme.of(context).cardTheme.color,
            child: TabBar(
              controller: _tabs,
              labelColor: AppColors.brand,
              isScrollable: true,
              labelStyle: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w900),
              tabs: [
                Tab(text: isAr ? 'الجدول اليومي' : 'Daily'),
                Tab(text: isAr ? 'الزمني' : 'Timeline'),
                Tab(text: isAr ? 'استغلال السعة' : 'Capacity'),
                Tab(text: isAr ? 'حسب النقطة' : 'By Point'),
              ],
            ),
          ),
          // ===== المحتوى =====
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _DailySchedule(trips: dayTrips, isAr: isAr, repo: repo),
                _HourlyTimeline(trips: dayTrips, isAr: isAr, repo: repo),
                _CapacityReport(
                    trips: dayTrips, isAr: isAr, repo: repo),
                _PerPointReport(
                    trips: dayTrips, isAr: isAr, repo: repo),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 🆕 تصدير الأسبوع كاملاً إلى Excel — 4 sheets (واحد لكلّ تبويب)
  Future<void> _exportExcel(
      List<_TripRow> weekTrips, bool isAr, List<String> dayNames) async {
    final repo = MockRepository();

    // Sheet 1: التفاصيل (كلّ رحلة)
    final detailRows = weekTrips.map<List<dynamic>>((t) {
      final bus = repo.busById(t.busId);
      final point = repo.pointById(t.pointId);
      return [
        bus?.name ?? '',
        bus?.plateNumber ?? '',
        bus?.capacity ?? 0,
        dayNames[t.dayIndex],
        t.time,
        point?.name ?? '',
        t.employeeIds.length,
        bus == null || bus.capacity == 0
            ? ''
            : '${(t.employeeIds.length * 100 / bus.capacity).toStringAsFixed(0)}%',
      ];
    }).toList();

    // Sheet 2: ملخّص لكلّ باص
    final byBus = <String, List<_TripRow>>{};
    for (final t in weekTrips) {
      byBus.putIfAbsent(t.busId, () => []).add(t);
    }
    final busSummaryRows = byBus.entries.map<List<dynamic>>((e) {
      final bus = repo.busById(e.key);
      final totalEmps =
          e.value.fold<int>(0, (a, t) => a + t.employeeIds.length);
      final cap = bus?.capacity ?? 0;
      final totalCap = cap * e.value.length;
      final util = totalCap == 0
          ? '0%'
          : '${(totalEmps * 100 / totalCap).toStringAsFixed(0)}%';
      return [
        bus?.name ?? '',
        bus?.plateNumber ?? '',
        cap,
        e.value.length,
        totalEmps,
        util,
      ];
    }).toList();

    // Sheet 3: ملخّص لكلّ نقطة
    final byPoint = <String, List<_TripRow>>{};
    for (final t in weekTrips) {
      byPoint.putIfAbsent(t.pointId, () => []).add(t);
    }
    final pointSummaryRows = byPoint.entries.map<List<dynamic>>((e) {
      final point = repo.pointById(e.key);
      final totalEmps =
          e.value.fold<int>(0, (a, t) => a + t.employeeIds.length);
      final busesUsed = e.value.map((t) => t.busId).toSet().length;
      return [
        point?.name ?? '',
        e.value.length,
        totalEmps,
        busesUsed,
      ];
    }).toList();

    final ok = await ExcelExporter.export(
      fileName:
          'buses_report_${DateTime.now().millisecondsSinceEpoch}.xlsx',
      sheets: [
        ExcelSheet(
          name: isAr ? 'كلّ الرحلات' : 'All Trips',
          headers: isAr
              ? ['الباص', 'اللوحة', 'السعة', 'اليوم', 'الساعة',
                  'النقطة', 'عدد الموظّفين', 'الاستغلال %']
              : ['Bus', 'Plate', 'Capacity', 'Day', 'Time',
                  'Point', 'Employees', 'Utilization %'],
          rows: detailRows,
        ),
        ExcelSheet(
          name: isAr ? 'ملخّص الباصات' : 'Per Bus',
          headers: isAr
              ? ['الباص', 'اللوحة', 'السعة', 'الرحلات', 'إجمالي الموظّفين', 'الاستغلال %']
              : ['Bus', 'Plate', 'Capacity', 'Trips', 'Total Pax', 'Utilization %'],
          rows: busSummaryRows,
        ),
        ExcelSheet(
          name: isAr ? 'ملخّص النقاط' : 'Per Point',
          headers: isAr
              ? ['النقطة', 'الرحلات', 'إجمالي الموظّفين', 'عدد الباصات']
              : ['Point', 'Trips', 'Total Pax', 'Buses Used'],
          rows: pointSummaryRows,
        ),
      ],
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: ok ? AppColors.success : AppColors.danger,
      content: Text(ok
          ? (isAr ? '✅ تمّ تصدير ${weekTrips.length} رحلة' : '✅ Exported ${weekTrips.length} trips')
          : (isAr ? '❌ فشل التصدير' : '❌ Export failed')),
    ));
  }
}

// ============================================================
// تبويب 1: الجدول اليومي
// ============================================================
class _DailySchedule extends StatelessWidget {
  final List<_TripRow> trips;
  final bool isAr;
  final MockRepository repo;
  const _DailySchedule(
      {required this.trips, required this.isAr, required this.repo});

  @override
  Widget build(BuildContext context) {
    if (trips.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(isAr ? 'لا توجد رحلات في هذا اليوم' : 'No trips today'),
        ),
      );
    }
    // مجمَّع حسب الباص
    final byBus = <String, List<_TripRow>>{};
    for (final t in trips) {
      byBus.putIfAbsent(t.busId, () => []).add(t);
    }
    return ListView(
      padding: const EdgeInsets.all(8),
      children: byBus.entries.map((e) {
        final bus = repo.busById(e.key);
        final tripsList = e.value..sort((a, b) => a.time.compareTo(b.time));
        final totalEmps =
            tripsList.fold<int>(0, (a, t) => a + t.employeeIds.length);
        final cap = bus?.capacity ?? 0;
        final totalCap = cap * tripsList.length;
        final util = totalCap == 0
            ? 0
            : (totalEmps * 100 / totalCap).round();
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // رأس البطاقة: الباص + إجماليات
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.brand.withValues(alpha: 0.08),
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(10)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.directions_bus,
                        color: AppColors.brand, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(bus?.name ?? '—',
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900)),
                          Text(
                              '${bus?.plateNumber ?? ""} • ${isAr ? "السعة" : "Cap"}: ${bus?.capacity ?? 0}',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey.shade600)),
                        ],
                      ),
                    ),
                    _MiniBadge(
                        label: '${tripsList.length} ${isAr ? "رحلة" : "trips"}',
                        color: AppColors.info),
                    const SizedBox(width: 4),
                    _MiniBadge(
                        label: '$totalEmps ${isAr ? "موظّف" : "pax"}',
                        color: AppColors.success),
                    const SizedBox(width: 4),
                    _MiniBadge(
                        label: '$util%',
                        color: util >= 80
                            ? AppColors.success
                            : util >= 50
                                ? AppColors.warning
                                : AppColors.danger),
                  ],
                ),
              ),
              // قائمة الرحلات
              for (final t in tripsList)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border(
                        top: BorderSide(
                            color: Theme.of(context).dividerColor)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.brand,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(t.time,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w900)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          repo.pointById(t.pointId)?.name ?? '—',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w800),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.people,
                                size: 11, color: AppColors.success),
                            const SizedBox(width: 3),
                            Text('${t.employeeIds.length}',
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.success)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      if (cap > 0)
                        Text(
                            '${(t.employeeIds.length * 100 / cap).toStringAsFixed(0)}%',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: t.employeeIds.length > cap
                                    ? AppColors.danger
                                    : Colors.grey.shade600)),
                    ],
                  ),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ============================================================
// تبويب 2: الزمني الموحَّد
// ============================================================
class _HourlyTimeline extends StatelessWidget {
  final List<_TripRow> trips;
  final bool isAr;
  final MockRepository repo;
  const _HourlyTimeline(
      {required this.trips, required this.isAr, required this.repo});

  @override
  Widget build(BuildContext context) {
    if (trips.isEmpty) {
      return Center(
          child: Text(isAr ? 'لا توجد رحلات' : 'No trips'));
    }
    // مجمَّع حسب الساعة (HH:MM)
    final byTime = <String, List<_TripRow>>{};
    for (final t in trips) {
      byTime.putIfAbsent(t.time, () => []).add(t);
    }
    final sortedTimes = byTime.keys.toList()..sort();
    return ListView(
      padding: const EdgeInsets.all(8),
      children: sortedTimes.map((time) {
        final tripsList = byTime[time]!;
        final totalEmps =
            tripsList.fold<int>(0, (a, t) => a + t.employeeIds.length);
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.10),
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(10)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.warning,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('🕐 $time',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w900)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isAr
                            ? '${tripsList.length} باصات • $totalEmps موظّف'
                            : '${tripsList.length} buses • $totalEmps pax',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
              for (final t in tripsList)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border(
                        top: BorderSide(
                            color: Theme.of(context).dividerColor)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.directions_bus,
                          size: 14, color: AppColors.brand),
                      const SizedBox(width: 6),
                      Expanded(
                        flex: 2,
                        child: Text(
                          repo.busById(t.busId)?.name ?? '—',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800),
                        ),
                      ),
                      const Icon(Icons.arrow_forward,
                          size: 12, color: Colors.grey),
                      const SizedBox(width: 4),
                      Expanded(
                        flex: 2,
                        child: Text(
                          repo.pointById(t.pointId)?.name ?? '—',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('${t.employeeIds.length}',
                            style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: AppColors.success)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ============================================================
// تبويب 3: استغلال السعة
// ============================================================
class _CapacityReport extends StatelessWidget {
  final List<_TripRow> trips;
  final bool isAr;
  final MockRepository repo;
  const _CapacityReport(
      {required this.trips, required this.isAr, required this.repo});

  @override
  Widget build(BuildContext context) {
    if (trips.isEmpty) {
      return Center(child: Text(isAr ? 'لا توجد رحلات' : 'No trips'));
    }
    final byBus = <String, List<_TripRow>>{};
    for (final t in trips) {
      byBus.putIfAbsent(t.busId, () => []).add(t);
    }
    // فرز بحسب نسبة الاستغلال
    final entries = byBus.entries.toList()
      ..sort((a, b) {
        final busA = repo.busById(a.key);
        final busB = repo.busById(b.key);
        final utilA = _utilization(a.value, busA?.capacity ?? 0);
        final utilB = _utilization(b.value, busB?.capacity ?? 0);
        return utilB.compareTo(utilA);
      });

    // تنبيهات عامّة
    final wastedTrips = trips.where((t) {
      final cap = repo.busById(t.busId)?.capacity ?? 0;
      if (cap == 0) return false;
      return t.employeeIds.length / cap < 0.30 &&
          t.employeeIds.isNotEmpty;
    }).toList();
    final overTrips = trips.where((t) {
      final cap = repo.busById(t.busId)?.capacity ?? 0;
      if (cap == 0) return false;
      return t.employeeIds.length > cap;
    }).toList();
    final emptyTrips =
        trips.where((t) => t.employeeIds.isEmpty).toList();

    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        // تنبيهات
        if (overTrips.isNotEmpty || wastedTrips.isNotEmpty || emptyTrips.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: AppColors.warning.withValues(alpha: 0.40)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isAr ? '⚠️ تنبيهات' : '⚠️ Alerts',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                if (overTrips.isNotEmpty)
                  Text(
                      isAr
                          ? '🔴 ${overTrips.length} رحلات تتجاوز السعة'
                          : '🔴 ${overTrips.length} over-capacity trips',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.danger)),
                if (wastedTrips.isNotEmpty)
                  Text(
                      isAr
                          ? '🟠 ${wastedTrips.length} رحلات أقلّ من 30% سعة'
                          : '🟠 ${wastedTrips.length} trips < 30% capacity',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.warning)),
                if (emptyTrips.isNotEmpty)
                  Text(
                      isAr
                          ? '⚫ ${emptyTrips.length} رحلات فارغة'
                          : '⚫ ${emptyTrips.length} empty trips',
                      style: const TextStyle(
                          fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
        // قائمة الباصات
        ...entries.map((e) {
          final bus = repo.busById(e.key);
          final cap = bus?.capacity ?? 0;
          final totalEmps = e.value.fold<int>(0, (a, t) => a + t.employeeIds.length);
          final totalCap = cap * e.value.length;
          final util = _utilization(e.value, cap);
          final color = util >= 80
              ? AppColors.success
              : util >= 50
                  ? AppColors.warning
                  : AppColors.danger;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withValues(alpha: 0.30)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.directions_bus,
                        color: AppColors.brand, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(bus?.name ?? '—',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900)),
                    ),
                    Text('$util%',
                        style: TextStyle(
                            color: color,
                            fontSize: 18,
                            fontWeight: FontWeight.w900)),
                  ],
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: util / 100,
                  backgroundColor: Colors.grey.shade200,
                  color: color,
                  minHeight: 6,
                ),
                const SizedBox(height: 6),
                Text(
                  isAr
                      ? '$totalEmps من $totalCap مقعد ($cap × ${e.value.length} رحلة)'
                      : '$totalEmps of $totalCap seats ($cap × ${e.value.length} trips)',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  int _utilization(List<_TripRow> trips, int capacity) {
    if (capacity == 0) return 0;
    final totalCap = capacity * trips.length;
    final totalEmps = trips.fold<int>(0, (a, t) => a + t.employeeIds.length);
    return totalCap == 0 ? 0 : (totalEmps * 100 / totalCap).round();
  }
}

// ============================================================
// تبويب 4: حسب النقطة
// ============================================================
class _PerPointReport extends StatelessWidget {
  final List<_TripRow> trips;
  final bool isAr;
  final MockRepository repo;
  const _PerPointReport(
      {required this.trips, required this.isAr, required this.repo});

  @override
  Widget build(BuildContext context) {
    if (trips.isEmpty) {
      return Center(child: Text(isAr ? 'لا توجد رحلات' : 'No trips'));
    }
    final byPoint = <String, List<_TripRow>>{};
    for (final t in trips) {
      byPoint.putIfAbsent(t.pointId, () => []).add(t);
    }
    final entries = byPoint.entries.toList()
      ..sort((a, b) {
        final empA = a.value.fold<int>(0, (s, t) => s + t.employeeIds.length);
        final empB = b.value.fold<int>(0, (s, t) => s + t.employeeIds.length);
        return empB.compareTo(empA);
      });
    return ListView(
      padding: const EdgeInsets.all(8),
      children: entries.map((e) {
        final point = repo.pointById(e.key);
        final tripsList = e.value..sort((a, b) => a.time.compareTo(b.time));
        final totalEmps =
            tripsList.fold<int>(0, (a, t) => a + t.employeeIds.length);
        final busesUsed = tripsList.map((t) => t.busId).toSet();
        final hasMultipleBuses = busesUsed.length > 1;
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: hasMultipleBuses
                    ? AppColors.warning.withValues(alpha: 0.40)
                    : Theme.of(context).dividerColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.purple.withValues(alpha: 0.08),
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(10)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.place,
                        color: AppColors.purple, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(point?.name ?? '—',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900)),
                    ),
                    _MiniBadge(
                        label: '${tripsList.length} ${isAr ? "رحلة" : "trips"}',
                        color: AppColors.info),
                    const SizedBox(width: 4),
                    _MiniBadge(
                        label: '$totalEmps ${isAr ? "موظّف" : "pax"}',
                        color: AppColors.success),
                  ],
                ),
              ),
              if (hasMultipleBuses)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  color: AppColors.warning.withValues(alpha: 0.10),
                  child: Text(
                    isAr
                        ? '💡 ${busesUsed.length} باصات تَخدم نفس النقطة — فرصة دمج محتملة'
                        : '💡 ${busesUsed.length} buses serving same point — possible consolidation',
                    style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.warning,
                        fontWeight: FontWeight.w800),
                  ),
                ),
              for (final t in tripsList)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    border: Border(
                        top: BorderSide(
                            color: Theme.of(context).dividerColor)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.brand,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(t.time,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w900)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          repo.busById(t.busId)?.name ?? '—',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text('${t.employeeIds.length} ${isAr ? "موظف" : "pax"}',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Colors.grey.shade700)),
                    ],
                  ),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ============================================================
// Helpers
// ============================================================
class _TripRow {
  final String busId;
  final String pointId;
  final int dayIndex;
  final String time;
  final List<String> employeeIds;
  _TripRow({
    required this.busId,
    required this.pointId,
    required this.dayIndex,
    required this.time,
    required this.employeeIds,
  });
}

class _Kpi extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Kpi(
      {required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.30)),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: color)),
            Text(label, style: const TextStyle(fontSize: 9)),
          ],
        ),
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _MiniBadge({required this.label, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              color: color)),
    );
  }
}
