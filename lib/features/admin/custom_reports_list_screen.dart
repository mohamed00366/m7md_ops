// =============================================================================
// 📊 شاشة قائمة التَقارير المُخَصَّصة
// =============================================================================
// تَعرِض كُلّ التَقارير: الجاهِزة (نِظام) + المُشارَكة + الخاصّة بِالمُستَخدِم.
// مِن هُنا: فَتح تَقرير لِلتَشغيل، تَعديله، حَذفه، أَو إنشاء جَديد.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/custom_report.dart';
import '../../shared/m7_app_bar.dart';
import '../../shared/m7_empty_state.dart';
import 'custom_report_builder_screen.dart';
import 'custom_report_runner_screen.dart';

class CustomReportsListScreen extends StatefulWidget {
  const CustomReportsListScreen({super.key});

  @override
  State<CustomReportsListScreen> createState() =>
      _CustomReportsListScreenState();
}

class _CustomReportsListScreenState extends State<CustomReportsListScreen> {
  List<CustomReport> _reports = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final supa = SupabaseService();
      if (!supa.isReady) {
        // مَوضوعيّ: لَو Supabase غَير مُتَّصِل، لا قائمة
        setState(() {
          _reports = [];
          _loading = false;
          _error = 'Supabase not connected';
        });
        return;
      }
      final rows = await supa.client
          .from('custom_reports')
          .select()
          .order('is_system', ascending: false)
          .order('updated_at', ascending: false);
      _reports = (rows as List)
          .cast<Map<String, dynamic>>()
          .map(CustomReport.fromJson)
          .toList();
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _delete(CustomReport r) async {
    if (r.isSystem) return; // لا حَذف لِتَقارير النِظام
    final s = AppStrings.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.isAr ? 'حَذف التَقرير؟' : 'Delete report?'),
        content: Text(s.isAr ? r.nameAr : r.nameEn),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.isAr ? 'إلغاء' : 'Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.isAr ? 'حَذف' : 'Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await SupabaseService().client
          .from('custom_reports')
          .delete()
          .eq('id', r.id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.danger,
          content: Text('${s.isAr ? 'فَشِل الحَذف' : 'Delete failed'}: $e'),
        ));
      }
    }
  }

  Future<void> _openBuilder({CustomReport? existing}) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CustomReportBuilderScreen(initial: existing),
      ),
    );
    if (updated == true) _load();
  }

  void _openRunner(CustomReport r) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CustomReportRunnerScreen(report: r),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final auth = context.watch<AuthProvider>();
    final canCreate = auth.permissions.contains('reports.custom.create') ||
        auth.isSuperAdmin;

    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? '📊 التَقارير المُخَصَّصة' : '📊 Custom Reports',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: isAr ? 'تَحديث' : 'Refresh',
          ),
        ],
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () => _openBuilder(),
              icon: const Icon(Icons.add),
              label: Text(isAr ? 'تَقرير جَديد' : 'New report'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.cloud_off,
                          size: 48, color: Colors.grey),
                      const SizedBox(height: 12),
                      Text(
                        isAr
                            ? 'تَعَذَّر تَحميل التَقارير'
                            : 'Could not load reports',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(_error!,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey)),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: Text(isAr ? 'إعادة' : 'Retry'),
                      ),
                    ],
                  ),
                )
              : _reports.isEmpty
                  ? M7EmptyState(
                      icon: Icons.assessment_outlined,
                      titleAr: 'لا تَقارير بَعد',
                      titleEn: 'No reports yet',
                      subtitleAr: canCreate
                          ? 'اضغَط + لِبِناء تَقريرك الأَوّل'
                          : 'اسأَل المُدير لِإنشاء تَقارير جَديدة',
                      subtitleEn: canCreate
                          ? 'Tap + to build your first report'
                          : 'Ask an admin to create reports',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(8),
                      itemCount: _reports.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 6),
                      itemBuilder: (_, i) => _ReportTile(
                        report: _reports[i],
                        isAr: isAr,
                        canEdit: canCreate &&
                            !_reports[i].isSystem &&
                            (_reports[i].createdBy == auth.account?.id ||
                                auth.isSuperAdmin),
                        onRun: () => _openRunner(_reports[i]),
                        onEdit: () => _openBuilder(existing: _reports[i]),
                        onDelete: () => _delete(_reports[i]),
                      ),
                    ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  final CustomReport report;
  final bool isAr;
  final bool canEdit;
  final VoidCallback onRun;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ReportTile({
    required this.report,
    required this.isAr,
    required this.canEdit,
    required this.onRun,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onRun,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.brand.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.assessment,
                    color: AppColors.brand, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            report.displayName(isAr),
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (report.isSystem)
                          _badge(
                              isAr ? 'نِظام' : 'System', Colors.blue),
                        if (report.isShared && !report.isSystem) ...[
                          const SizedBox(width: 4),
                          _badge(isAr ? 'مُشارَك' : 'Shared', Colors.green),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      report.description ??
                          (isAr
                              ? 'مَصدَر: ${report.source.key}'
                              : 'Source: ${report.source.key}'),
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey[700]),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.play_arrow, color: AppColors.brand),
                onPressed: onRun,
                tooltip: isAr ? 'تَشغيل' : 'Run',
              ),
              if (canEdit)
                PopupMenuButton<String>(
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(children: [
                        const Icon(Icons.edit, size: 18),
                        const SizedBox(width: 8),
                        Text(isAr ? 'تَعديل' : 'Edit'),
                      ]),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(children: [
                        const Icon(Icons.delete,
                            size: 18, color: Colors.red),
                        const SizedBox(width: 8),
                        Text(isAr ? 'حَذف' : 'Delete',
                            style: const TextStyle(color: Colors.red)),
                      ]),
                    ),
                  ],
                  onSelected: (v) {
                    if (v == 'edit') onEdit();
                    if (v == 'delete') onDelete();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(String label, Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 9, fontWeight: FontWeight.w800, color: c)),
    );
  }
}

