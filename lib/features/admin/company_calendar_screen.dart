import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/company_calendar_service.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/m7_app_bar.dart';
import '../../shared/m7_stats_banner.dart';
import '../../shared/m7_toolbar.dart';

/// 📅 شاشة تَقويم الشَركة
///
/// Agenda view لِلأَحداث القادِمة (٩٠ يَوم).
class CompanyCalendarScreen extends StatefulWidget {
  const CompanyCalendarScreen({super.key});

  @override
  State<CompanyCalendarScreen> createState() => _CompanyCalendarScreenState();
}

class _CompanyCalendarScreenState extends State<CompanyCalendarScreen> {
  int _daysAhead = 90;
  CalendarEventType? _filterType;

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final auth = context.watch<AuthProvider>();
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day);
    final to = from.add(Duration(days: _daysAhead));
    final all = CompanyCalendarService.instance.events(
        from: from, to: to, countryId: auth.activeCountryId);

    // فَلتَر بِالنَوع
    var events = all;
    if (_filterType != null) {
      events = events.where((e) => e.type == _filterType).toList();
    }

    // إحصائيّات
    final cnt = <CalendarEventType, int>{};
    for (final e in all) {
      cnt[e.type] = (cnt[e.type] ?? 0) + 1;
    }
    final expiryCount = cnt[CalendarEventType.documentExpiry] ?? 0;
    final bdayCount = cnt[CalendarEventType.birthday] ?? 0;
    final anniCount = cnt[CalendarEventType.anniversary] ?? 0;

    // تَجميع حَسَب اليَوم
    final byDay = <String, List<CalendarEvent>>{};
    for (final e in events) {
      final key = _dayKey(e.date);
      byDay.putIfAbsent(key, () => []).add(e);
    }
    final dayKeys = byDay.keys.toList()..sort();

    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? 'تَقويم الشَركة' : 'Company Calendar',
        subtitle: isAr
            ? '${all.length} حَدَث خِلال $_daysAhead يَوم'
            : '${all.length} events in $_daysAhead days',
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          M7StatsBanner(stats: [
            M7Stat(
                icon: Icons.assignment_late,
                label: isAr ? 'انتِهاء' : 'Expiry',
                value: expiryCount,
                color: Colors.red),
            M7Stat(
                icon: Icons.cake,
                label: isAr ? 'مَواليد' : 'Birthdays',
                value: bdayCount,
                color: Colors.pink),
            M7Stat(
                icon: Icons.workspace_premium,
                label: isAr ? 'تَعيين' : 'Anniversaries',
                value: anniCount,
                color: AppColors.gold),
            M7Stat(
                icon: Icons.event,
                label: isAr ? 'الكُلّ' : 'Total',
                value: all.length,
                color: AppColors.brand),
          ]),
          const SizedBox(height: 12),
          // فِلتَر الفَترة
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.brand.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.date_range,
                    color: AppColors.brand, size: 18),
                const SizedBox(width: 8),
                Text(
                  isAr ? 'النَظر إلى:' : 'Look ahead:',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SegmentedButton<int>(
                    segments: [
                      ButtonSegment(
                          value: 30,
                          label: Text(isAr ? '٣٠ يَوم' : '30d')),
                      ButtonSegment(
                          value: 90,
                          label: Text(isAr ? '٩٠ يَوم' : '90d')),
                      ButtonSegment(
                          value: 180,
                          label: Text(isAr ? '١٨٠ يَوم' : '180d')),
                      ButtonSegment(
                          value: 365,
                          label: Text(isAr ? 'سَنة' : '1y')),
                    ],
                    selected: {_daysAhead},
                    onSelectionChanged: (s) =>
                        setState(() => _daysAhead = s.first),
                    showSelectedIcon: false,
                    style: ButtonStyle(
                      textStyle: WidgetStateProperty.all(
                          const TextStyle(fontSize: 10)),
                      padding: WidgetStateProperty.all(
                          const EdgeInsets.symmetric(horizontal: 8)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // فِلتَر نَوع الحَدَث
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                M7FilterPill(
                  label: isAr ? 'الكُلّ' : 'All',
                  count: all.length,
                  selected: _filterType == null,
                  color: AppColors.brand,
                  onTap: () => setState(() => _filterType = null),
                ),
                const SizedBox(width: 6),
                for (final type in CalendarEventType.values)
                  if ((cnt[type] ?? 0) > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: M7FilterPill(
                        label: isAr ? type.titleAr() : type.titleEn(),
                        count: cnt[type] ?? 0,
                        selected: _filterType == type,
                        color: _colorFor(type),
                        onTap: () => setState(() =>
                            _filterType = _filterType == type ? null : type),
                      ),
                    ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // قائِمة الأَحداث المُجَمَّعة بِاليَوم
          if (events.isEmpty)
            _emptyState(isAr)
          else
            for (final day in dayKeys)
              _DayGroup(
                day: day,
                events: byDay[day]!,
                isAr: isAr,
              ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _emptyState(bool isAr) {
    return Container(
      padding: const EdgeInsets.all(40),
      margin: const EdgeInsets.symmetric(vertical: 30),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Icon(Icons.check_circle,
              size: 64, color: AppColors.success.withValues(alpha: 0.85)),
          const SizedBox(height: 12),
          Text(
            isAr
                ? '✨ لا أَحداث في هَذه الفَترة'
                : '✨ No events in this period',
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }

  String _dayKey(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Color _colorFor(CalendarEventType t) {
    switch (t) {
      case CalendarEventType.documentExpiry:
        return Colors.red;
      case CalendarEventType.birthday:
        return Colors.pink;
      case CalendarEventType.anniversary:
        return AppColors.gold;
      case CalendarEventType.contractStart:
        return AppColors.success;
      case CalendarEventType.custom:
        return AppColors.brand;
    }
  }
}

// ============================================================
// مَجموعة أَحداث يَوم واحِد
// ============================================================
class _DayGroup extends StatelessWidget {
  final String day;
  final List<CalendarEvent> events;
  final bool isAr;
  const _DayGroup({
    required this.day,
    required this.events,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    final dt = DateTime.tryParse(day) ?? DateTime.now();
    final today = DateTime.now();
    final isToday = dt.year == today.year &&
        dt.month == today.month &&
        dt.day == today.day;
    final diff = dt.difference(DateTime(today.year, today.month, today.day)).inDays;
    final relative = diff == 0
        ? (isAr ? 'اليَوم' : 'Today')
        : diff == 1
            ? (isAr ? 'غَداً' : 'Tomorrow')
            : (isAr ? 'بَعد $diff يَوم' : 'In $diff days');
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isToday
                  ? AppColors.brand.withValues(alpha: 0.15)
                  : AppColors.brand.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: AppColors.brand.withValues(alpha: isToday ? 0.50 : 0.20)),
            ),
            child: Row(
              children: [
                const Icon(Icons.event,
                    color: AppColors.brand, size: 16),
                const SizedBox(width: 6),
                Text(
                  day,
                  style: const TextStyle(
                      color: AppColors.brand,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      fontFamily: 'monospace'),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.brand.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    relative,
                    style: const TextStyle(
                        color: AppColors.brand,
                        fontSize: 10,
                        fontWeight: FontWeight.w800),
                  ),
                ),
                const Spacer(),
                Text(
                  isAr
                      ? '${events.length} حَدَث'
                      : '${events.length} events',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ...events.map((e) => _EventTile(event: e, isAr: isAr)),
        ],
      ),
    );
  }
}

// ============================================================
// بِطاقة حَدَث
// ============================================================
class _EventTile extends StatelessWidget {
  final CalendarEvent event;
  final bool isAr;
  const _EventTile({required this.event, required this.isAr});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: event.color.withValues(alpha: 0.25)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: event.openBuilder == null
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute(builder: event.openBuilder!)),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: event.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(event.icon, color: event.color, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isAr ? event.titleAr : event.titleEn,
                        style: TextStyle(
                            color: event.color,
                            fontWeight: FontWeight.w900,
                            fontSize: 12),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        event.entityName,
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                if (event.openBuilder != null)
                  Icon(Icons.chevron_right,
                      color: event.color.withValues(alpha: 0.50), size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
