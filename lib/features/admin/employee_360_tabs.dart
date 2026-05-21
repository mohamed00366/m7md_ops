// =============================================================================
// 👤 Employee 360° tabs — Stats / Leaves / Discipline / Attendance
// =============================================================================
// Drop-in widgets used by EmployeeProfileHub tabs. Each fetches its own data
// directly from Supabase and shows a focused view for ONE employee.
// =============================================================================
import 'package:flutter/material.dart';

import '../../core/services/m7_log.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/models.dart';

// =============================================================================
// 📊 STATS TAB — high-level KPIs in cards
// =============================================================================
class EmployeeStatsTab extends StatefulWidget {
  final Employee employee;
  const EmployeeStatsTab({super.key, required this.employee});

  @override
  State<EmployeeStatsTab> createState() => _EmployeeStatsTabState();
}

class _EmployeeStatsTabState extends State<EmployeeStatsTab> {
  bool _loading = true;
  int _leavesTotal = 0;
  int _leavesPending = 0;
  double _leavesDaysThisYear = 0;
  int _warningsCount = 0;
  double _deductionsTotal = 0;
  int _clockIns30d = 0;
  int _clockOuts30d = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final supa = SupabaseService();
    if (!supa.isReady) {
      setState(() => _loading = false);
      return;
    }
    try {
      final empId = widget.employee.id;
      final year = DateTime.now().year;

      // Leaves
      final leaves = await supa.client
          .from('employee_leave_requests')
          .select('id, status, days_count, start_date')
          .eq('employee_id', empId);
      _leavesTotal = (leaves as List).length;
      _leavesPending = leaves
          .where((l) => (l as Map)['status'] == 'pending')
          .length;
      _leavesDaysThisYear = leaves
          .where((l) {
            final r = l as Map;
            final s = (r['start_date'] as String?) ?? '';
            return r['status'] == 'approved' && s.startsWith('$year');
          })
          .fold<double>(0,
              (sum, r) => sum + ((r as Map)['days_count'] as num? ?? 0).toDouble());

      // Deductions
      final dedu = await supa.client
          .from('employee_deductions')
          .select('id, amount, status')
          .eq('employee_id', empId);
      _warningsCount = (dedu as List).length;
      _deductionsTotal = dedu
          .where((d) => (d as Map)['status'] == 'active')
          .fold<double>(0,
              (sum, d) => sum + ((d as Map)['amount'] as num? ?? 0).toDouble());

      // Attendance last 30 days
      final since = DateTime.now()
          .subtract(const Duration(days: 30))
          .toUtc()
          .toIso8601String();
      final att = await supa.client
          .from('point_terminal_clock_logs')
          .select('action')
          .eq('employee_id', empId)
          .gte('created_at', since);
      _clockIns30d = (att as List)
          .where((r) => (r as Map)['action'] == 'clock_in')
          .length;
      _clockOuts30d = att
          .where((r) => (r as Map)['action'] == 'clock_out')
          .length;
    } catch (e) {
      M7Log.error('EmployeeStatsTab', 'load', error: e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _kpiRow([
            _Kpi(
              icon: Icons.beach_access,
              label: 'الإجازات',
              value: '$_leavesTotal',
              hint: '${_leavesDaysThisYear.toStringAsFixed(1)} يَوم هذا العام',
              color: Colors.teal,
            ),
            _Kpi(
              icon: Icons.hourglass_empty,
              label: 'قَيد المُراجَعة',
              value: '$_leavesPending',
              hint: 'pending approval',
              color: AppColors.warning,
            ),
          ]),
          const SizedBox(height: 8),
          _kpiRow([
            _Kpi(
              icon: Icons.gavel,
              label: 'الإنذارات (W-)',
              value: '$_warningsCount',
              hint: 'مَجموع كُلّ الإنذارات',
              color: AppColors.danger,
            ),
            _Kpi(
              icon: Icons.payments_outlined,
              label: 'الخَصومات النَشِطة',
              value: '${_deductionsTotal.toStringAsFixed(0)} AED',
              hint: 'لا تَزال active',
              color: Colors.red.shade800,
            ),
          ]),
          const SizedBox(height: 8),
          _kpiRow([
            _Kpi(
              icon: Icons.login,
              label: 'check-ins (30 يَوم)',
              value: '$_clockIns30d',
              hint: '',
              color: AppColors.success,
            ),
            _Kpi(
              icon: Icons.logout,
              label: 'check-outs (30 يَوم)',
              value: '$_clockOuts30d',
              hint: _clockIns30d != _clockOuts30d
                  ? '⚠ غَير مُتوازِن'
                  : '✓',
              color: Colors.indigo,
            ),
          ]),
        ],
      ),
    );
  }

  Widget _kpiRow(List<Widget> children) => Row(
        children: children
            .map((w) => Expanded(
                child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: w)))
            .toList(),
      );
}

class _Kpi extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String hint;
  final Color color;
  const _Kpi({
    required this.icon,
    required this.label,
    required this.value,
    required this.hint,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 22,
                  fontWeight: FontWeight.w900)),
          if (hint.isNotEmpty)
            Text(hint,
                style: const TextStyle(fontSize: 9, color: Colors.grey)),
        ],
      ),
    );
  }
}

// =============================================================================
// 🏖 LEAVES TAB — list of leave requests for this employee
// =============================================================================
class EmployeeLeavesTab extends StatefulWidget {
  final Employee employee;
  const EmployeeLeavesTab({super.key, required this.employee});
  @override
  State<EmployeeLeavesTab> createState() => _EmployeeLeavesTabState();
}

class _EmployeeLeavesTabState extends State<EmployeeLeavesTab> {
  bool _loading = true;
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final supa = SupabaseService();
    if (!supa.isReady) {
      setState(() => _loading = false);
      return;
    }
    try {
      final rows = await supa.client
          .from('employee_leave_requests')
          .select()
          .eq('employee_id', widget.employee.id)
          .order('start_date', ascending: false);
      _rows = (rows as List).cast<Map<String, dynamic>>();
    } catch (e) {
      M7Log.error('EmployeeLeavesTab', 'load', error: e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'approved':
        return AppColors.success;
      case 'pending':
        return AppColors.warning;
      case 'rejected':
      case 'cancelled':
        return Colors.grey;
      default:
        return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_rows.isEmpty) {
      return const Center(
          child: Text('لا تُوجَد طَلَبات إجازة'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (_, i) {
          final r = _rows[i];
          final status = (r['status'] as String?) ?? 'pending';
          final lateStatus = r['late_status'] as String?;
          return Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _statusColor(status).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: _statusColor(status), width: 0.6),
                        ),
                        child: Text(
                          status,
                          style: TextStyle(
                              fontSize: 10,
                              color: _statusColor(status),
                              fontWeight: FontWeight.w900),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        (r['leave_type'] as String?) ?? '?',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 12),
                      ),
                      const Spacer(),
                      Text(
                        '${r['days_count']} يَوم',
                        style: TextStyle(
                            color: Colors.grey.shade700, fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.event,
                          size: 12, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(
                        '${r['start_date']} → ${r['end_date']}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                  if ((r['reason'] as String?)?.isNotEmpty ?? false) ...[
                    const SizedBox(height: 2),
                    Text(
                      r['reason'] as String,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11, color: Colors.black87),
                    ),
                  ],
                  if (lateStatus != null && lateStatus != 'not_started') ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        lateStatus,
                        style: const TextStyle(
                            fontSize: 9,
                            color: AppColors.warning,
                            fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// =============================================================================
// 📋 DISCIPLINE TAB — deductions / warnings (W-XX) with signature
// =============================================================================
class EmployeeDisciplineTab extends StatefulWidget {
  final Employee employee;
  const EmployeeDisciplineTab({super.key, required this.employee});
  @override
  State<EmployeeDisciplineTab> createState() => _EmployeeDisciplineTabState();
}

class _EmployeeDisciplineTabState extends State<EmployeeDisciplineTab> {
  bool _loading = true;
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final supa = SupabaseService();
    if (!supa.isReady) {
      setState(() => _loading = false);
      return;
    }
    try {
      final rows = await supa.client
          .from('employee_deductions')
          .select()
          .eq('employee_id', widget.employee.id)
          .order('applied_at', ascending: false);
      _rows = (rows as List).cast<Map<String, dynamic>>();
    } catch (e) {
      M7Log.error('EmployeeDisciplineTab', 'load', error: e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _catLabel(String c) {
    const m = {
      'late_return': '🏖 تَأَخُّر إجازة',
      'absence': '❌ غِياب',
      'theft': '🚨 سَرِقة',
      'fighting': '⚠ شِجار',
      'misconduct': '⚠ سُلوك',
      'manual_ticket': '🎫 تَذكَرة يَدَويّة',
      'damage': '🔧 إتلاف',
      'other': '📋 أُخرى',
    };
    return m[c] ?? c;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_rows.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text('✅ لا تُوجَد إنذارات — سِجِلّ نَظيف!',
              style: TextStyle(fontSize: 14)),
        ),
      );
    }
    final totalAmount = _rows.fold<double>(
        0,
        (sum, r) =>
            sum + ((r['amount'] as num?)?.toDouble() ?? 0));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: AppColors.danger.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.danger.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.summarize, color: AppColors.danger),
                const SizedBox(width: 8),
                Text(
                  '${_rows.length} إنذار · ${totalAmount.toStringAsFixed(0)} AED مَجموع',
                  style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: AppColors.danger,
                      fontSize: 13),
                ),
              ],
            ),
          ),
          for (final r in _rows) _deductionCard(r),
        ],
      ),
    );
  }

  Widget _deductionCard(Map<String, dynamic> r) {
    final signed = r['signed_at'] != null;
    final amount = (r['amount'] as num?)?.toDouble() ?? 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.danger,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    (r['warning_number'] as String?) ?? '—',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'monospace',
                        fontSize: 11),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _catLabel((r['category'] as String?) ?? 'other'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                ),
                Text(
                  '${amount.toStringAsFixed(0)} AED',
                  style: const TextStyle(
                      color: AppColors.danger,
                      fontWeight: FontWeight.w900,
                      fontSize: 14),
                ),
              ],
            ),
            if ((r['reason'] as String?)?.isNotEmpty ?? false) ...[
              const SizedBox(height: 4),
              Text(
                r['reason'] as String,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Colors.black87),
              ),
            ],
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.event, size: 11, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(
                  (r['applied_at'] as String?)?.substring(0, 10) ?? '?',
                  style:
                      TextStyle(fontSize: 10, color: Colors.grey.shade700),
                ),
                const Spacer(),
                if (signed)
                  const Row(
                    children: [
                      Icon(Icons.check_circle,
                          size: 12, color: AppColors.success),
                      SizedBox(width: 3),
                      Text('مُوَقَّع',
                          style: TextStyle(
                              color: AppColors.success,
                              fontSize: 10,
                              fontWeight: FontWeight.w800)),
                    ],
                  )
                else
                  const Row(
                    children: [
                      Icon(Icons.draw,
                          size: 12, color: AppColors.warning),
                      SizedBox(width: 3),
                      Text('بانتِظار التَوقيع',
                          style: TextStyle(
                              color: AppColors.warning,
                              fontSize: 10,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// ⏰ ATTENDANCE TAB — last 30 days of clock logs
// =============================================================================
class EmployeeAttendanceTab extends StatefulWidget {
  final Employee employee;
  const EmployeeAttendanceTab({super.key, required this.employee});
  @override
  State<EmployeeAttendanceTab> createState() => _EmployeeAttendanceTabState();
}

class _EmployeeAttendanceTabState extends State<EmployeeAttendanceTab> {
  bool _loading = true;
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final supa = SupabaseService();
    if (!supa.isReady) {
      setState(() => _loading = false);
      return;
    }
    try {
      final since = DateTime.now()
          .subtract(const Duration(days: 30))
          .toUtc()
          .toIso8601String();
      final rows = await supa.client
          .from('point_terminal_clock_logs')
          .select('action, created_at, point_id')
          .eq('employee_id', widget.employee.id)
          .gte('created_at', since)
          .order('created_at', ascending: false);
      _rows = (rows as List).cast<Map<String, dynamic>>();
    } catch (e) {
      M7Log.error('EmployeeAttendanceTab', 'load', error: e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_rows.isEmpty) {
      return const Center(
          child: Text('لا تُوجَد سَجَلّات حُضور في آخِر 30 يَوم'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 4),
        itemBuilder: (_, i) {
          final r = _rows[i];
          final action = (r['action'] as String?) ?? '?';
          final isIn = action == 'clock_in';
          final ts = DateTime.tryParse(
                  (r['created_at'] as String?) ?? '')
              ?.toLocal();
          return Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (isIn ? AppColors.success : AppColors.warning)
                  .withOpacity(0.08),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: (isIn ? AppColors.success : AppColors.warning)
                      .withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(
                  isIn ? Icons.login : Icons.logout,
                  size: 18,
                  color: isIn ? AppColors.success : AppColors.warning,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isIn ? 'دُخول' : 'خُروج',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      color: isIn ? AppColors.success : AppColors.warning,
                    ),
                  ),
                ),
                if (ts != null)
                  Text(
                    '${ts.year}-${ts.month.toString().padLeft(2, '0')}-${ts.day.toString().padLeft(2, '0')} ${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: Colors.black87),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
