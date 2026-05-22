// =============================================================================
// 📅 Schedule Preview — يَظهَر بَعد Clock-in لِيَرى المُوَظَّف وَردِيَّته + باصه
// =============================================================================
import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/m7_log.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';

class EmployeeSchedulePreview extends StatefulWidget {
  final Employee employee;
  final Point currentPoint;
  final String action; // 'clock_in' | 'clock_out'

  const EmployeeSchedulePreview({
    super.key,
    required this.employee,
    required this.currentPoint,
    required this.action,
  });

  static Future<void> show(
    BuildContext context, {
    required Employee employee,
    required Point currentPoint,
    required String action,
  }) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => EmployeeSchedulePreview(
        employee: employee,
        currentPoint: currentPoint,
        action: action,
      ),
    );
  }

  @override
  State<EmployeeSchedulePreview> createState() =>
      _EmployeeSchedulePreviewState();
}

class _EmployeeSchedulePreviewState extends State<EmployeeSchedulePreview> {
  bool _loading = true;
  Map<String, dynamic>? _todayShift; // assignment of today
  Bus? _defaultBus;
  int _activeNowAtPoint = 0;

  @override
  void initState() {
    super.initState();
    _load();
    // إغلاق تِلقائيّ بَعد 8 ثَوانٍ
    Future.delayed(const Duration(seconds: 8), () {
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _load() async {
    final supa = SupabaseService();
    final repo = MockRepository();
    if (!supa.isReady) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final now = DateTime.now();
      final today = now.toIso8601String().substring(0, 10);
      final dayIndex = now.weekday - 1; // 0..6

      // 1) وَردِيّة اليَوم من الروستر المُعتَمَد
      final weekStart = now.subtract(Duration(days: dayIndex));
      final wsKey = weekStart.toIso8601String().substring(0, 10);
      final rosters = await supa.client
          .from('weekly_rosters')
          .select('id, point_id, status')
          .eq('point_id', widget.currentPoint.id)
          .eq('week_start', wsKey)
          .inFilter('status', ['approved', 'submitted']);
      for (final r in (rosters as List)) {
        final rosterId = (r as Map)['id'] as String;
        final asg = await supa.client
            .from('roster_assignments')
            .select(
                'employee_id, day_index, start_time, end_time, shift_type, notes')
            .eq('roster_id', rosterId)
            .eq('employee_id', widget.employee.id)
            .eq('day_index', dayIndex)
            .maybeSingle();
        if (asg != null) {
          _todayShift = Map<String, dynamic>.from(asg);
          break;
        }
      }

      // 2) الباص الافتِراضيّ
      if (widget.employee.defaultBusId != null) {
        _defaultBus = repo.buses
            .where((b) => b.id == widget.employee.defaultBusId)
            .cast<Bus?>()
            .firstWhere((b) => true, orElse: () => null);
      }

      // 3) كَم مُوَظَّف نَشِط الآن في النُقطة
      try {
        final startOfDay = DateTime(now.year, now.month, now.day);
        final clk = await supa.client
            .from('point_terminal_clock_logs')
            .select('employee_id, action')
            .eq('point_id', widget.currentPoint.id)
            .gte('created_at', startOfDay.toIso8601String())
            .order('created_at', ascending: false);
        // مَنطِق: لِكُلّ مُوَظَّف، آخِر action هو clock_in → ما زالَ نَشِطاً
        final latestPerEmp = <String, String>{};
        for (final r in (clk as List)) {
          final emp = (r as Map)['employee_id'] as String?;
          final act = r['action'] as String?;
          if (emp == null || act == null) continue;
          latestPerEmp.putIfAbsent(emp, () => act);
        }
        _activeNowAtPoint =
            latestPerEmp.values.where((a) => a == 'clock_in').length;
      } catch (e) {
        M7Log.error('SchedulePreview', 'active count', error: e);
      }
    } catch (e) {
      M7Log.error('SchedulePreview', 'load', error: e);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final isClockIn = widget.action == 'clock_in';
    final headerColor =
        isClockIn ? AppColors.success : AppColors.warning;
    final headerIcon = isClockIn ? Icons.login : Icons.logout;
    final headerText = isClockIn
        ? (isAr ? '✅ تَمّ تَسجيل الدُخول' : '✅ Clocked In')
        : (isAr ? '🚪 تَمّ تَسجيل الخُروج' : '🚪 Clocked Out');

    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ===== Header =====
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      headerColor,
                      headerColor.withValues(alpha: 0.7),
                    ],
                  ),
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20)),
                ),
                child: Column(
                  children: [
                    Icon(headerIcon, color: Colors.white, size: 42),
                    const SizedBox(height: 8),
                    Text(
                      headerText,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$timeStr · ${now.toIso8601String().substring(0, 10)}',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
              // ===== Welcome message =====
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      isAr
                          ? '${isClockIn ? "أَهلاً" : "وَداعاً"} ${widget.employee.fullName}'
                          : '${isClockIn ? "Welcome" : "Goodbye"} ${widget.employee.fullName}',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w900),
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      '${widget.employee.code} · ${widget.employee.jobTitle}',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 14),
                    if (_loading)
                      const CircularProgressIndicator()
                    else ...[
                      // ===== Shift info =====
                      if (isClockIn && _todayShift != null)
                        _infoCard(
                          icon: Icons.schedule,
                          color: AppColors.brand,
                          title:
                              isAr ? '⏰ وَردِيّتك اليَوم' : '⏰ Today shift',
                          value:
                              '${_todayShift!['start_time']} → ${_todayShift!['end_time']}',
                          subtitle: _todayShift!['notes'] as String?,
                        ),
                      // ===== Bus info =====
                      if (isClockIn && _defaultBus != null) ...[
                        const SizedBox(height: 8),
                        _infoCard(
                          icon: Icons.directions_bus,
                          color: AppColors.warning,
                          title: isAr ? '🚌 باصُك' : '🚌 Your bus',
                          value:
                              '${_defaultBus!.name} · ${_defaultBus!.plateNumber}',
                          subtitle: _defaultBus!.morningTime != null
                              ? (isAr
                                  ? 'وَقت الصَباح: ${_defaultBus!.morningTime}'
                                  : 'Morning: ${_defaultBus!.morningTime}')
                              : null,
                        ),
                      ],
                      // ===== Active count =====
                      if (_activeNowAtPoint > 0) ...[
                        const SizedBox(height: 8),
                        _infoCard(
                          icon: Icons.groups,
                          color: AppColors.success,
                          title: isAr
                              ? '👥 الزُمَلاء في المَوقِع'
                              : '👥 Colleagues on-site',
                          value:
                              '$_activeNowAtPoint ${isAr ? "مُوَظَّف" : "employees"}',
                        ),
                      ],
                      if (isClockIn && _todayShift == null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline,
                                  size: 16,
                                  color: Colors.grey.shade700),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  isAr
                                      ? 'لا تُوجَد وَردِيّة مَجدوَلة لَك اليَوم'
                                      : 'No shift scheduled today',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade700),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              // ===== Footer =====
              Padding(
                padding: const EdgeInsets.all(12),
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: headerColor,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(44),
                  ),
                  child: Text(
                    isAr ? 'إغلاق (تِلقائيّاً بَعد 8ث)' : 'Close (auto 8s)',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoCard({
    required IconData icon,
    required Color color,
    required String title,
    required String value,
    String? subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w900)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 10, color: Colors.grey.shade600)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
