// =============================================================================
// 📄 Report Detail Screen — renders a single report with its table view
// =============================================================================
import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/m7_app_bar.dart';
import 'reports_service.dart';

class ReportDetailScreen extends StatefulWidget {
  final String reportKey;
  const ReportDetailScreen({super.key, required this.reportKey});

  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<ReportDetailScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final svc = ReportsService.instance;
    switch (widget.reportKey) {
      case 'attendance':
        _rows = await svc.attendanceReport();
        break;
      case 'leave_usage':
      case 'overdue':
        _rows = await svc.leaveUsageReport();
        if (widget.reportKey == 'overdue') {
          _rows = _rows
              .where((r) => r['late_status'] == 'late_pending' ||
                  r['late_status'] == 'returned_late')
              .toList();
        }
        break;
      case 'docs_expiry':
        _rows = await svc.documentExpiryReport();
        break;
      case 'deductions':
        _rows = await svc.deductionsReport();
        break;
      case 'fleet_km':
        _rows = await svc.fleetKmReport();
        break;
      default:
        _rows = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  String _title(bool isAr) {
    switch (widget.reportKey) {
      case 'attendance':
        return isAr ? '⏰ تَقرير الحُضور' : '⏰ Attendance';
      case 'leave_usage':
        return isAr ? '🏖 الإجازات' : '🏖 Leaves';
      case 'overdue':
        return isAr ? '🚨 المُتَأَخِّرون' : '🚨 Overdue';
      case 'docs_expiry':
        return isAr ? '📁 الوَثائِق' : '📁 Documents';
      case 'deductions':
        return isAr ? '💰 الخَصومات' : '💰 Deductions';
      case 'fleet_km':
        return isAr ? '🛞 الأُسطول' : '🛞 Fleet';
      default:
        return 'Report';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return Scaffold(
      appBar: M7AppBar(
        title: _title(isAr),
        actions: [
          M7AppBarAction(
              icon: Icons.refresh,
              tooltip: isAr ? 'تَحديث' : 'Refresh',
              onPressed: _load),
          M7AppBarAction(
              icon: Icons.download,
              tooltip: isAr ? 'تَصدير' : 'Export',
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(isAr
                      ? 'سَيُضاف لاحِقاً: PDF/Excel/WhatsApp'
                      : 'Coming soon: PDF/Excel/WhatsApp'),
                ));
              }),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rows.isEmpty
              ? Center(
                  child: Text(
                  isAr
                      ? 'لا تُوجَد بَيانات في هذه الفَترة'
                      : 'No data in this period',
                  style: const TextStyle(fontSize: 14),
                ))
              : Column(
                  children: [
                    _summaryBar(isAr),
                    Expanded(child: _table(isAr)),
                  ],
                ),
    );
  }

  Widget _summaryBar(bool isAr) {
    return Container(
      padding: const EdgeInsets.all(10),
      color: AppColors.brand.withValues(alpha: 0.08),
      child: Row(
        children: [
          const Icon(Icons.summarize, color: AppColors.brand, size: 18),
          const SizedBox(width: 8),
          Text(
              '${_rows.length} ${isAr ? "صَفّ" : "rows"}',
              style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _table(bool isAr) {
    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: _rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (_, i) => _row(_rows[i], isAr),
    );
  }

  Widget _row(Map<String, dynamic> r, bool isAr) {
    // Try to extract employee from nested join
    String empName = '';
    final emp = r['employees'];
    if (emp is Map) {
      empName = (emp['full_name'] as String?) ?? '';
    }

    final lines = <String>[];

    switch (widget.reportKey) {
      case 'attendance':
        final action = r['action'] as String? ?? '';
        final time = (r['created_at'] as String?)?.substring(11, 16) ?? '';
        lines.add(
            '${action == 'clock_in' ? '🟢 دُخول' : '🔴 خُروج'} · $time');
        lines.add((r['created_at'] as String?)?.substring(0, 10) ?? '');
        break;
      case 'leave_usage':
      case 'overdue':
        lines.add(
            '${r['leave_type']} · ${r['days_count']} يَوم · ${r['status']}');
        lines.add('${r['start_date']} → ${r['end_date']}');
        if (r['late_status'] != null && r['late_status'] != 'not_started') {
          lines.add('${r['late_status']}');
        }
        break;
      case 'docs_expiry':
        final dt = (r['doc_type_label'] as String?) ??
            (r['doc_type'] as String?) ??
            '?';
        lines.add('$dt · ${isAr ? "يَنتَهي" : "expires"} ${r['expiry_date']}');
        break;
      case 'deductions':
        lines.add(
            '${r['warning_number']} · ${r['amount']} ${r['currency'] ?? "AED"}');
        lines.add('${r['category']} · ${r['reason']}');
        lines.add((r['applied_at'] as String?)?.substring(0, 10) ?? '');
        break;
      case 'fleet_km':
        final bus = r['buses'];
        final plate =
            bus is Map ? (bus['plate_number'] as String?) ?? '?' : '?';
        lines.add('$plate · ${r['action']} · ${r['odometer_km'] ?? "—"} km');
        lines.add((r['created_at'] as String?)?.substring(0, 16) ?? '');
        break;
    }

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        title: Text(empName.isEmpty ? lines.first : empName,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: lines
              .map((l) => Text(l,
                  style: const TextStyle(fontSize: 11, color: Colors.black87)))
              .toList(),
        ),
        dense: true,
      ),
    );
  }
}
