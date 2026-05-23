// =============================================================================
// ▶️ شاشة تَشغيل تَقرير مُخَصَّص
// =============================================================================
// تَأخُذ `CustomReport`، تُشَغِّل `ReportEngine` عَلى السَجِلّات المَحَلِّيّة،
// وَتَعرِض النَتائِج في جَدوَل قابِل لِلتَمرير، مَع زِرَّي تَصدير Excel وَPDF.
// =============================================================================

import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/report_engine.dart';
import '../../core/services/report_registry.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/custom_report.dart';
import '../../shared/m7_app_bar.dart';
import '../../shared/m7_print_view.dart';

class CustomReportRunnerScreen extends StatefulWidget {
  final CustomReport report;
  const CustomReportRunnerScreen({super.key, required this.report});

  @override
  State<CustomReportRunnerScreen> createState() =>
      _CustomReportRunnerScreenState();
}

class _CustomReportRunnerScreenState
    extends State<CustomReportRunnerScreen> {
  ReportResult? _result;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      ReportResult result;
      if (widget.report.source == ReportSource.driverTips) {
        // مَصدَر السَحابة — اقرَأ مِن Supabase
        final supa = SupabaseService();
        if (!supa.isReady) {
          throw Exception('Supabase not connected');
        }
        final rows = await supa.client.from('driver_tips').select();
        result = ReportEngine.instance.runWithRecords(
            widget.report, (rows as List).cast<Map<String, dynamic>>());
      } else {
        result = ReportEngine.instance.run(widget.report);
      }
      setState(() {
        _result = result;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  String _cell(dynamic value, ReportColumnDef col, bool isAr) {
    if (value == null) return '';
    if (col.type == ColumnType.lookup && col.lookupName != null) {
      return col.lookupName!(value.toString(), isAr);
    }
    if (value is DateTime) {
      return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
    }
    if (value is num) {
      // إذا integer → اعرِض بِدون أَرقام عَشريّة
      if (value % 1 == 0) return value.toInt().toString();
      return value.toStringAsFixed(2);
    }
    if (value is bool) return value ? '✓' : '✗';
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;

    return Scaffold(
      appBar: M7AppBar(
        title: widget.report.displayName(isAr),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _run,
            tooltip: isAr ? 'تَحديث' : 'Refresh',
          ),
          if (_result != null && _result!.rows.isNotEmpty)
            M7PrintButton(
              title: widget.report.displayName(isAr),
              subtitle: widget.report.description,
              columns: _result!.columnsForDisplay
                  .map((c) => c.label(isAr))
                  .toList(),
              rowsBuilder: () => _result!.rows.map((row) {
                return _result!.columnsForDisplay.map((c) {
                  return _cell(row.values[c.key], c, isAr);
                }).toList();
              }).toList(),
              footerNote:
                  isAr ? 'M7 Nexus — تَقرير مُخَصَّص' : 'M7 Nexus — Custom report',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 48, color: Colors.red),
                        const SizedBox(height: 12),
                        Text(_error!,
                            style: const TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                )
              : _buildBody(isAr),
    );
  }

  Widget _buildBody(bool isAr) {
    final r = _result!;
    if (r.rows.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              isAr
                  ? 'لا نَتائِج تُطابِق الفِلاتِر'
                  : 'No rows match the filters',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            Text(
              isAr
                  ? 'حاوِل تَخفيف الفِلاتِر أَو تَوسيع الفَترة'
                  : 'Try relaxing filters or expanding the period',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        // ===== Summary bar =====
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: Colors.grey[100],
          child: Row(
            children: [
              Icon(Icons.table_chart_outlined,
                  size: 16, color: AppColors.brand),
              const SizedBox(width: 6),
              Text(
                isAr
                    ? '${r.rows.length} صَفّ مَعروض / ${r.totalBeforeLimit} إجمالي'
                    : '${r.rows.length} rows shown / ${r.totalBeforeLimit} total',
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                isAr ? '🛢 ${widget.report.source.key}' : '🛢 ${widget.report.source.key}',
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // ===== Data table =====
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(Colors.grey[200]),
                columns: r.columnsForDisplay
                    .map((c) => DataColumn(
                          label: Text(
                            c.label(isAr),
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w800),
                          ),
                          numeric: c.type == ColumnType.number,
                        ))
                    .toList(),
                rows: r.rows
                    .map((row) => DataRow(
                          cells: r.columnsForDisplay
                              .map((c) => DataCell(Text(
                                    _cell(row.values[c.key], c, isAr),
                                    style: const TextStyle(fontSize: 11),
                                  )))
                              .toList(),
                        ))
                    .toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
