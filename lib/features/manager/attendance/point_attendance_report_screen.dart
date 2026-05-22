import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/services/m7_log.dart';
import '../../../core/services/point_terminal_settings.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/enums.dart';
import '../../../models/models.dart';
import '../../../repositories/mock_repository.dart';
import '../../../shared/m7_app_bar.dart';

/// 📊 تَقرير دَوام النِقاط
///
/// لِكُلّ نُقطة:
///   - الرَوستر المُعتَمَد (المُتَوَقَّعون اليَوم) من `MockRepository.rosters`
///   - السِجِلّ الفِعليّ (دُخول/خُروج) من `point_terminal_clock_logs`
///   - مُقارَنة لِكَشف:
///     • ✅ حَضَر في الوَقت
///     • 🕐 مُتَأَخِّر
///     • ❌ غائِب (في الرَوستر ولم يَدخُل)
///     • 👻 خارِج الرَوستر (دَخَل ولَيس في الخُطّة)
class PointAttendanceReportScreen extends StatefulWidget {
  const PointAttendanceReportScreen({super.key});

  @override
  State<PointAttendanceReportScreen> createState() =>
      _PointAttendanceReportScreenState();
}

class _PointAttendanceReportScreenState
    extends State<PointAttendanceReportScreen> {
  DateTime _selectedDate = DateTime.now();
  bool _loadingLogs = false;
  /// خَريطة: pointId → List<ClockLog>
  Map<String, List<_ClockLog>> _logsByPoint = {};
  String _search = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  /// 🆕 تَهيِئة تَتَأَكَّد أَنّ الإعدادات مُحَمَّلة قَبل قِراءة قِيَمها
  Future<void> _init() async {
    await PointTerminalSettings.instance.load();
    await _loadLogs();
  }

  Future<void> _loadLogs() async {
    final supa = SupabaseService();
    if (!supa.isReady) {
      setState(() => _loadingLogs = false);
      return;
    }
    setState(() => _loadingLogs = true);
    try {
      final start = DateTime(
          _selectedDate.year, _selectedDate.month, _selectedDate.day);
      final end = start.add(const Duration(days: 1));
      final rows = await supa.client
          .from('point_terminal_clock_logs')
          .select(
              'id, point_id, employee_id, action, match_confidence, created_at')
          .gte('created_at', start.toUtc().toIso8601String())
          .lt('created_at', end.toUtc().toIso8601String())
          .order('created_at', ascending: true);
      final map = <String, List<_ClockLog>>{};
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        final pid = r['point_id'] as String?;
        if (pid == null) continue;
        map.putIfAbsent(pid, () => []).add(_ClockLog(
              id: r['id'] as String,
              employeeId: r['employee_id'] as String,
              action: r['action'] as String,
              confidence: (r['match_confidence'] as num?)?.toDouble(),
              at: DateTime.parse(r['created_at'] as String).toLocal(),
            ));
      }
      _logsByPoint = map;
    } catch (e) {
      M7Log.error('PointAttendanceReport', 'load logs', error: e);
    } finally {
      if (mounted) setState(() => _loadingLogs = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      await _loadLogs();
    }
  }

  /// 🆕 يُرجِع المُتَوَقَّعين في نُقطة لِيَوم مُحَدَّد بِناءً على الرَوستر المُعتَمَد
  Map<String, _Expected> _expectedAtPoint(String pointId, DateTime date) {
    final repo = MockRepository();
    final dayIndex = date.weekday - 1; // 0=Monday..6=Sunday
    // ابحَث في كُلّ الرَوسترات المُعتَمَدة التي تَشمَل هذا التاريخ
    final result = <String, _Expected>{};
    for (final r in repo.rosters) {
      if (r.status != RosterStatus.approved) continue;
      // التاريخ يَجِب أَن يَكون داخِل أُسبوع الرَوستر
      final weekStart = DateTime(
          r.weekStart.year, r.weekStart.month, r.weekStart.day);
      final weekEnd = weekStart.add(const Duration(days: 7));
      final d = DateTime(date.year, date.month, date.day);
      if (d.isBefore(weekStart) || !d.isBefore(weekEnd)) continue;
      for (final a in r.assignments) {
        if (a.dayIndex != dayIndex) continue;
        if (a.shiftType == ShiftType.off) continue;
        final emp = repo.employeeById(a.employeeId);
        if (emp == null) continue;
        final empPointId = emp.pointId ?? emp.siteId;
        if (empPointId != pointId) continue;
        result[a.employeeId] = _Expected(
          employeeId: a.employeeId,
          startTime: a.startTime,
          endTime: a.endTime,
          shiftType: a.shiftType,
        );
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final repo = MockRepository();
    // فَلتَر النِقاط النَشطة + البَحث
    final query = _search.trim().toLowerCase();
    final points = repo.points.where((p) {
      if (p.status != EntityStatus.active) return false;
      if (query.isEmpty) return true;
      return p.name.toLowerCase().contains(query) ||
          p.code.toLowerCase().contains(query);
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return Scaffold(
      appBar: M7AppBar(
        title:
            isAr ? 'تَقرير دَوام النِقاط' : 'Point Attendance Report',
        subtitle: _formatDate(_selectedDate, isAr: isAr),
        actions: [
          M7AppBarAction(
            icon: Icons.calendar_today,
            tooltip: isAr ? 'تَغيير التاريخ' : 'Change date',
            onPressed: _pickDate,
          ),
          M7AppBarAction(
            icon: Icons.refresh,
            tooltip: isAr ? 'تَحديث' : 'Refresh',
            onPressed: _loadLogs,
          ),
        ],
      ),
      body: Column(
        children: [
          // ===== شَريط البَحث =====
          Padding(
            padding: const EdgeInsets.all(10),
            child: TextField(
              decoration: InputDecoration(
                hintText: isAr
                    ? 'ابحَث عَن نُقطة…'
                    : 'Search points…',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          // ===== المُحتَوى =====
          Expanded(
            child: _loadingLogs
                ? const Center(child: CircularProgressIndicator())
                : points.isEmpty
                    ? Center(
                        child: Text(isAr
                            ? 'لا نِقاط مُطابِقة'
                            : 'No matching points'))
                    : RefreshIndicator(
                        onRefresh: _loadLogs,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: points.length,
                          itemBuilder: (_, i) {
                            final p = points[i];
                            final logs = _logsByPoint[p.id] ?? const [];
                            final expected =
                                _expectedAtPoint(p.id, _selectedDate);
                            return _PointReportCard(
                              point: p,
                              expected: expected,
                              logs: logs,
                              date: _selectedDate,
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d, {required bool isAr}) {
    const monthsAr = [
      'يَنايِر',
      'فِبرايِر',
      'مارِس',
      'إبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أَغُسطُس',
      'سِبتَمبَر',
      'أُكتوبَر',
      'نوفَمبَر',
      'ديسَمبَر',
    ];
    if (isAr) {
      return '${d.day} ${monthsAr[d.month - 1]} ${d.year}';
    }
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}

// ============================================================
// بِطاقة نُقطة (قابِلة لِلتَوسيع)
// ============================================================
class _PointReportCard extends StatefulWidget {
  final Point point;
  final Map<String, _Expected> expected;
  final List<_ClockLog> logs;
  final DateTime date;
  const _PointReportCard({
    required this.point,
    required this.expected,
    required this.logs,
    required this.date,
  });

  @override
  State<_PointReportCard> createState() => _PointReportCardState();
}

class _PointReportCardState extends State<_PointReportCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final repo = MockRepository();

    // ابني صَفاً لِكُلّ مُوَظَّف (مُتَوَقَّع أَو فَعليّ)
    final empIds = <String>{
      ...widget.expected.keys,
      ...widget.logs.map((l) => l.employeeId),
    };
    int present = 0;
    int absent = 0;
    int late_ = 0;
    int extra = 0;
    final rows = <_EmpRow>[];
    for (final empId in empIds) {
      final emp = repo.employeeById(empId);
      if (emp == null) continue;
      final exp = widget.expected[empId];
      final empLogs = widget.logs.where((l) => l.employeeId == empId).toList()
        ..sort((a, b) => a.at.compareTo(b.at));
      final firstIn =
          empLogs.where((l) => l.action == 'clock_in').firstOrNull;
      final lastOut =
          empLogs.where((l) => l.action == 'clock_out').lastOrNull;

      _Status status;
      if (exp == null && firstIn != null) {
        status = _Status.extra;
        extra++;
      } else if (exp != null && firstIn == null) {
        status = _Status.absent;
        absent++;
      } else if (exp != null && firstIn != null) {
        // فَحص التَأَخُّر: قارِن firstIn بِـ exp.startTime
        // الحَدّ قابِل لِلتَهيئة من PointTerminalSettings.lateThresholdMinutes
        final lateBy = _lateMinutes(firstIn.at, exp.startTime);
        final lateThreshold =
            PointTerminalSettings.instance.lateThresholdMinutes;
        if (lateBy > lateThreshold) {
          status = _Status.late;
          late_++;
        } else {
          status = _Status.present;
          present++;
        }
      } else {
        // غَير مُمكِن: لا مُتَوَقَّع ولا فِعليّ
        continue;
      }

      rows.add(_EmpRow(
        employee: emp,
        expected: exp,
        clockIn: firstIn,
        clockOut: lastOut,
        status: status,
      ));
    }
    rows.sort((a, b) {
      // رَتِّب: مُتَأَخِّر، ثُمَّ غائِب، ثُمَّ حاضِر، ثُمَّ خارِج الرَوستر
      const order = {
        _Status.late: 0,
        _Status.absent: 1,
        _Status.present: 2,
        _Status.extra: 3,
      };
      final ao = order[a.status] ?? 99;
      final bo = order[b.status] ?? 99;
      if (ao != bo) return ao.compareTo(bo);
      return a.employee.fullName.compareTo(b.employee.fullName);
    });

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Column(
        children: [
          // Header
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.place,
                        color: AppColors.warning, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.point.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 14)),
                        Text(widget.point.code,
                            style: const TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                                fontFamily: 'monospace')),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            _statChip('✅', '$present',
                                AppColors.success, isAr ? 'حاضِر' : 'Present'),
                            if (late_ > 0)
                              _statChip('🕐', '$late_',
                                  AppColors.warning, isAr ? 'مُتَأَخِّر' : 'Late'),
                            if (absent > 0)
                              _statChip('❌', '$absent',
                                  AppColors.danger, isAr ? 'غائِب' : 'Absent'),
                            if (extra > 0)
                              _statChip('👻', '$extra',
                                  AppColors.info, isAr ? 'خارِج الخُطّة' : 'Extra'),
                            _statChip('📋', '${widget.expected.length}',
                                Colors.grey, isAr ? 'في الخُطّة' : 'Planned'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.gold,
                  ),
                ],
              ),
            ),
          ),
          // التَفاصيل
          if (_expanded) ...[
            const Divider(height: 0),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  isAr
                      ? 'لا بَيانات لِهذِه النُقطة في هذا التاريخ'
                      : 'No data for this point on this date',
                  style: const TextStyle(color: Colors.grey),
                ),
              )
            else
              Column(
                children: rows
                    .map((r) => _EmpRowTile(row: r, isAr: isAr))
                    .toList(),
              ),
          ],
        ],
      ),
    );
  }

  Widget _statChip(String emoji, String value, Color color, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 11)),
          const SizedBox(width: 4),
          Text(
            '$value $label',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  int _lateMinutes(DateTime clockIn, String expectedHHMM) {
    final parts = expectedHHMM.split(':');
    if (parts.length != 2) return 0;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    final expectedDt = DateTime(
        clockIn.year, clockIn.month, clockIn.day, h, m);
    return clockIn.difference(expectedDt).inMinutes;
  }
}

// ============================================================
// صَفّ مُوَظَّف
// ============================================================
class _EmpRowTile extends StatelessWidget {
  final _EmpRow row;
  final bool isAr;
  const _EmpRowTile({required this.row, required this.isAr});

  @override
  Widget build(BuildContext context) {
    final emp = row.employee;
    final exp = row.expected;
    final inT = row.clockIn?.at;
    final outT = row.clockOut?.at;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(color: Colors.grey.shade200, width: 0.5)),
      ),
      child: Row(
        children: [
          _StatusIcon(status: row.status),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  emp.fullName,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 13),
                ),
                Text(
                  emp.code,
                  style: const TextStyle(
                      fontSize: 11,
                      color: Colors.grey,
                      fontFamily: 'monospace'),
                ),
                if (exp != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      isAr
                          ? '📋 الخُطّة: ${exp.startTime} → ${exp.endTime}'
                          : '📋 Plan: ${exp.startTime} → ${exp.endTime}',
                      style: const TextStyle(
                          fontSize: 10, color: Colors.grey),
                    ),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (inT != null)
                Text(
                  '⬇ ${_fmt(inT)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      color: AppColors.success),
                ),
              if (outT != null)
                Text(
                  '⬆ ${_fmt(outT)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      color: AppColors.warning),
                ),
              if (inT == null && outT == null)
                Text(
                  isAr ? '—' : '—',
                  style: const TextStyle(
                      fontSize: 12, color: Colors.grey),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _StatusIcon extends StatelessWidget {
  final _Status status;
  const _StatusIcon({required this.status});

  @override
  Widget build(BuildContext context) {
    late final Color color;
    late final IconData icon;
    switch (status) {
      case _Status.present:
        color = AppColors.success;
        icon = Icons.check_circle;
        break;
      case _Status.late:
        color = AppColors.warning;
        icon = Icons.access_time;
        break;
      case _Status.absent:
        color = AppColors.danger;
        icon = Icons.cancel;
        break;
      case _Status.extra:
        color = AppColors.info;
        icon = Icons.person_add;
        break;
    }
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: color, size: 18),
    );
  }
}

// ============================================================
// Models
// ============================================================
enum _Status { present, late, absent, extra }

class _Expected {
  final String employeeId;
  final String startTime;
  final String endTime;
  final ShiftType shiftType;
  const _Expected({
    required this.employeeId,
    required this.startTime,
    required this.endTime,
    required this.shiftType,
  });
}

class _ClockLog {
  final String id;
  final String employeeId;
  final String action; // clock_in | clock_out
  final double? confidence;
  final DateTime at;
  const _ClockLog({
    required this.id,
    required this.employeeId,
    required this.action,
    required this.confidence,
    required this.at,
  });
}

class _EmpRow {
  final Employee employee;
  final _Expected? expected;
  final _ClockLog? clockIn;
  final _ClockLog? clockOut;
  final _Status status;
  const _EmpRow({
    required this.employee,
    required this.expected,
    required this.clockIn,
    required this.clockOut,
    required this.status,
  });
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
  T? get lastOrNull => isEmpty ? null : last;
}
