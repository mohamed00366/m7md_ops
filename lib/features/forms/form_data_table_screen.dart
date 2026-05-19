import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/models.dart';
import '../../shared/m7_app_bar.dart';
import 'form_permissions.dart';

/// 📊 عَرض جَدوَلي ديناميكيّ لِبَيانات نَموذج
///
/// يَقرَأ مِن جَدول form_data_<template_code> الذي يَنشَأ تلقائيّاً.
/// كُلّ حَقل في الـschema يَصير عَموداً، كُلّ submission يَصير صَفّاً.
///
/// لا يَعمَل مَع النَماذج القَديمة (LEAVE-REQ, ...) إلّا إذا تَمَّ تَفعيلها
/// يَدَويّاً عَبر: SELECT form_enable_data_table('CODE');
class FormDataTableScreen extends StatefulWidget {
  final FormTemplate template;
  const FormDataTableScreen({super.key, required this.template});

  @override
  State<FormDataTableScreen> createState() => _FormDataTableScreenState();
}

class _FormDataTableScreenState extends State<FormDataTableScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = false;
  String _filter = '';
  String? _error;

  String get _tableName {
    // نَفس الـnormalization في الـSQL function form_safe_table_name
    final normalized = widget.template.code
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_]'), '_');
    return 'form_data_$normalized';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final supa = SupabaseService();
      if (!supa.isReady) {
        setState(() {
          _loading = false;
          _error = 'Supabase not ready';
        });
        return;
      }
      final rows = await supa.client
          .from(_tableName)
          .select()
          .order('created_at', ascending: false)
          .limit(500);

      setState(() {
        _rows = (rows as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  /// الأَعمِدة المَعروضة: نُسَمّيها من schema الحاليّ + الأَعمِدة النِظاميّة
  List<_ColumnSpec> get _columns {
    final cols = <_ColumnSpec>[
      _ColumnSpec(key: 'form_no', labelAr: 'رَقَم', labelEn: 'No.'),
      _ColumnSpec(
          key: 'sub_status', labelAr: 'الحالة', labelEn: 'Status'),
      _ColumnSpec(
          key: 'created_at',
          labelAr: 'التاريخ',
          labelEn: 'Date',
          isDate: true),
    ];
    for (final field in widget.template.schema) {
      final type = (field['type'] ?? 'text').toString();
      if (type == 'section' || type == 'signature') continue;
      final key = _safeColumnName((field['key'] ?? '').toString());
      if (key.isEmpty) continue;
      cols.add(_ColumnSpec(
        key: key,
        labelAr: (field['label_ar'] ?? key).toString(),
        labelEn: (field['label_en'] ?? key).toString(),
        type: type,
      ));
    }
    return cols;
  }

  /// نَفس المَنطِق في form_safe_column_name
  static const _reserved = {
    'select', 'from', 'where', 'order', 'group', 'table', 'column', 'user',
    'role', 'grant', 'primary', 'foreign', 'key', 'index', 'create', 'drop',
    'alter', 'insert', 'update', 'delete', 'default', 'null', 'true', 'false',
    'check', 'constraint', 'references', 'unique', 'case', 'when', 'then',
    'else', 'end', 'as', 'and', 'or', 'not', 'in', 'is', 'like', 'between',
    'desc', 'asc', 'limit', 'offset', 'having', 'union', 'all', 'any', 'some',
    'distinct', 'exists', 'status',
  };

  String _safeColumnName(String key) {
    var clean = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '_');
    clean = clean.replaceAll(RegExp(r'^_+|_+$'), '');
    if (clean.isEmpty) return 'unnamed_field';
    if (RegExp(r'^[0-9]').hasMatch(clean)) clean = 'f_$clean';
    if (_reserved.contains(clean)) clean = 'f_$clean';
    return clean;
  }

  List<Map<String, dynamic>> get _filteredRows {
    if (_filter.isEmpty) return _rows;
    final q = _filter.toLowerCase();
    return _rows.where((r) {
      return r.values.any((v) => v.toString().toLowerCase().contains(q));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final auth = context.watch<AuthProvider>();

    // 🔐 فَحص الصَلاحيّة قَبل العَرض
    final perms = FormPermissions.fromTemplate(widget.template);
    if (!perms.canViewTable(auth)) {
      return Scaffold(
        appBar: M7AppBar(
          title: isAr ? '📊 عَرض جَدوَلي' : '📊 Table view',
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline,
                    size: 56, color: AppColors.danger),
                const SizedBox(height: 12),
                Text(
                  isAr
                      ? 'لا تَملك صَلاحيّة عَرض جَدول هذا النَموذج'
                      : 'No permission to view this form\'s table',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  isAr
                      ? 'اطلُب من الإدارة إضافَتك إلى view_table_roles'
                      : 'Ask admin to add you to view_table_roles',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final cols = _columns;
    final rows = _filteredRows;

    return Scaffold(
      appBar: M7AppBar(
        title: isAr
            ? '📊 ${widget.template.nameAr}'
            : '📊 ${widget.template.nameEn}',
        subtitle: isAr
            ? '${rows.length} صَفّ · ${cols.length} عَمود'
            : '${rows.length} rows · ${cols.length} columns',
        actions: [
          M7AppBarAction(
            icon: Icons.refresh,
            tooltip: isAr ? 'تَحديث' : 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          // === Search bar ===
          Padding(
            padding: const EdgeInsets.all(10),
            child: TextField(
              decoration: InputDecoration(
                hintText:
                    isAr ? 'بَحث في كُلّ الأَعمِدة…' : 'Search all columns…',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),

          // === Info bar with table name ===
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.info.withOpacity(0.08),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.info.withOpacity(0.30)),
            ),
            child: Row(
              children: [
                const Icon(Icons.table_chart_outlined,
                    size: 14, color: AppColors.info),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isAr
                        ? 'الجَدول: $_tableName'
                        : 'Table: $_tableName',
                    style: const TextStyle(
                        fontSize: 10,
                        fontFamily: 'monospace',
                        color: AppColors.info,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // === Table / Loading / Error ===
          if (_loading)
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline,
                          size: 48, color: AppColors.danger),
                      const SizedBox(height: 8),
                      Text(
                        isAr
                            ? 'الجَدول غَير مَوجود — هذا النَموذج قَديم'
                            : 'Table not found — this is a legacy form',
                        style: TextStyle(
                            color: AppColors.danger,
                            fontWeight: FontWeight.w800),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isAr
                            ? 'لِتَفعيله، شَغِّل في Supabase SQL:'
                            : 'To enable, run in Supabase SQL:',
                        style: const TextStyle(fontSize: 11),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        "SELECT form_enable_data_table('${widget.template.code}');",
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: AppColors.brand,
                          fontWeight: FontWeight.w800,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: const TextStyle(
                            fontSize: 9, color: Colors.grey),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (rows.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.inbox_outlined,
                        size: 64, color: Colors.grey.shade400),
                    const SizedBox(height: 8),
                    Text(
                      isAr
                          ? 'لا توجد بَيانات بَعد'
                          : 'No data yet',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isAr
                          ? 'البَيانات تَظهَر تلقائيّاً عِندَ تَقديم النَموذج'
                          : 'Data appears automatically when forms are submitted',
                      style: const TextStyle(
                          fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: _DataTableView(
                columns: cols,
                rows: rows,
                isAr: isAr,
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================================
// مُواصَفة عَمود
// ============================================================================
class _ColumnSpec {
  final String key;
  final String labelAr;
  final String labelEn;
  final String? type;
  final bool isDate;
  _ColumnSpec({
    required this.key,
    required this.labelAr,
    required this.labelEn,
    this.type,
    this.isDate = false,
  });
}

// ============================================================================
// عَرض الجَدول
// ============================================================================
class _DataTableView extends StatelessWidget {
  final List<_ColumnSpec> columns;
  final List<Map<String, dynamic>> rows;
  final bool isAr;

  const _DataTableView({
    required this.columns,
    required this.rows,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          headingRowColor: MaterialStatePropertyAll(
            AppColors.brand.withOpacity(0.08),
          ),
          headingTextStyle: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: AppColors.brand,
          ),
          dataTextStyle: const TextStyle(fontSize: 11),
          columnSpacing: 24,
          horizontalMargin: 12,
          dataRowMinHeight: 36,
          dataRowMaxHeight: 60,
          columns: [
            for (final c in columns)
              DataColumn(
                label: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 200),
                  child: Text(
                    isAr ? c.labelAr : c.labelEn,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
          ],
          rows: [
            for (final row in rows)
              DataRow(
                cells: [
                  for (final c in columns)
                    DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 220),
                        child: Text(
                          _formatValue(row[c.key], c),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _formatValue(dynamic v, _ColumnSpec col) {
    if (v == null) return '';
    if (col.isDate || col.type == 'date') {
      try {
        final d = DateTime.parse(v.toString());
        return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      } catch (_) {
        return v.toString();
      }
    }
    if (v is List) return v.join(', ');
    if (v is Map) return v.entries.map((e) => '${e.key}: ${e.value}').join(' · ');
    return v.toString();
  }
}
