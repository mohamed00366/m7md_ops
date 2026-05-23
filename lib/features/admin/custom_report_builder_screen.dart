// =============================================================================
// 🛠 شاشة بِناء/تَعديل تَقرير مُخَصَّص
// =============================================================================
// خَطَوات الـUI:
//   1. اِسم + وَصف + مَصدَر بَيانات
//   2. اختِيار الأَعمِدة (chips متَعَدِّدة)
//   3. اختِيار الفِلاتِر (قائمة قابلة لِلإضافة/الحَذف)
//   4. groupBy (اختِياريّ) + aggregates (لَو groupBy)
//   5. sort (اختِياريّ)
//   6. تَجريب — يَفتَح Runner لِلمُعايَنة
//   7. حِفظ — يَكتُب في Supabase
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/report_registry.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/custom_report.dart';
import '../../shared/m7_app_bar.dart';
import 'custom_report_runner_screen.dart';

class CustomReportBuilderScreen extends StatefulWidget {
  final CustomReport? initial;
  const CustomReportBuilderScreen({super.key, this.initial});

  @override
  State<CustomReportBuilderScreen> createState() =>
      _CustomReportBuilderScreenState();
}

class _CustomReportBuilderScreenState extends State<CustomReportBuilderScreen> {
  final _nameArController = TextEditingController();
  final _nameEnController = TextEditingController();
  final _descController = TextEditingController();

  ReportSource _source = ReportSource.employees;
  List<ReportColumn> _columns = [];
  List<ReportFilter> _filters = [];
  String? _groupBy;
  List<ReportAggregate> _aggregates = [];
  List<ReportSort> _sort = [];
  bool _isShared = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    if (init != null) {
      _nameArController.text = init.nameAr;
      _nameEnController.text = init.nameEn;
      _descController.text = init.description ?? '';
      _source = init.source;
      _columns = List.of(init.config.columns);
      _filters = List.of(init.config.filters);
      _groupBy = init.config.groupBy;
      _aggregates = List.of(init.config.aggregates);
      _sort = List.of(init.config.sort);
      _isShared = init.isShared;
    }
  }

  @override
  void dispose() {
    _nameArController.dispose();
    _nameEnController.dispose();
    _descController.dispose();
    super.dispose();
  }

  ReportSourceDef get _sourceDef => ReportRegistry.instance.get(_source)!;

  ReportConfig _buildConfig() => ReportConfig(
        columns: _columns,
        filters: _filters,
        groupBy: _groupBy,
        aggregates: _aggregates,
        sort: _sort,
      );

  CustomReport _buildReport() {
    final init = widget.initial;
    return CustomReport(
      id: init?.id ?? '',
      nameAr: _nameArController.text.trim(),
      nameEn: _nameEnController.text.trim(),
      description:
          _descController.text.trim().isEmpty ? null : _descController.text.trim(),
      source: _source,
      config: _buildConfig(),
      createdBy: init?.createdBy,
      isShared: _isShared,
      isSystem: init?.isSystem ?? false,
      countryId: init?.countryId,
      createdAt: init?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  void _preview() {
    if (_nameArController.text.trim().isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CustomReportRunnerScreen(report: _buildReport()),
    ));
  }

  Future<void> _save() async {
    final s = AppStrings.of(context);
    if (_nameArController.text.trim().isEmpty ||
        _nameEnController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text(s.isAr ? 'الاسم مَطلوب' : 'Name required'),
      ));
      return;
    }
    final supa = SupabaseService();
    if (!supa.isReady) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text(s.isAr
            ? 'Supabase غَير مُتَّصِل — لا يُمكِن الحِفظ'
            : 'Supabase not connected — cannot save'),
      ));
      return;
    }
    setState(() => _saving = true);
    try {
      final auth = context.read<AuthProvider>();
      final payload = {
        'name_ar': _nameArController.text.trim(),
        'name_en': _nameEnController.text.trim(),
        'description': _descController.text.trim().isEmpty
            ? null
            : _descController.text.trim(),
        'source_table': _source.key,
        'config_json': _buildConfig().toJson(),
        'is_shared': _isShared,
      };
      if (widget.initial == null) {
        // إنشاء
        payload['created_by'] = auth.account?.id;
        await supa.client.from('custom_reports').insert(payload);
      } else {
        // تَحديث
        await supa.client
            .from('custom_reports')
            .update(payload)
            .eq('id', widget.initial!.id);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.danger,
          content: Text('${s.isAr ? 'فَشِل الحِفظ' : 'Save failed'}: $e'),
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;

    return Scaffold(
      appBar: M7AppBar(
        title: widget.initial == null
            ? (isAr ? '🛠 تَقرير جَديد' : '🛠 New Report')
            : (isAr ? '✏️ تَعديل تَقرير' : '✏️ Edit Report'),
        actions: [
          IconButton(
            icon: const Icon(Icons.play_arrow),
            tooltip: isAr ? 'مُعايَنة' : 'Preview',
            onPressed: _preview,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ===== Name + desc =====
          _section(isAr ? '1️⃣ الاسم وَالوَصف' : '1️⃣ Name & Description'),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _nameArController,
                decoration: const InputDecoration(
                  labelText: 'الاسم (عَرَبيّ)',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _nameEnController,
                decoration: const InputDecoration(
                  labelText: 'Name (English)',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: _descController,
            decoration: InputDecoration(
              labelText: isAr ? 'الوَصف (اختِياريّ)' : 'Description (optional)',
              border: const OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          // ===== Source =====
          const SizedBox(height: 16),
          _section(isAr ? '2️⃣ مَصدَر البَيانات' : '2️⃣ Data Source'),
          DropdownButtonFormField<ReportSource>(
            value: _source,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: ReportRegistry.instance.all().map((sd) {
              return DropdownMenuItem(
                value: sd.source,
                child: Text(sd.label(isAr)),
              );
            }).toList(),
            onChanged: (v) {
              if (v == null) return;
              setState(() {
                _source = v;
                _columns.clear();
                _filters.clear();
                _groupBy = null;
                _aggregates.clear();
                _sort.clear();
              });
            },
          ),

          // ===== Columns =====
          const SizedBox(height: 16),
          _section(isAr ? '3️⃣ الأَعمِدة' : '3️⃣ Columns'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _sourceDef.columns.map((c) {
              final selected = _columns.any((sc) => sc.key == c.key);
              return FilterChip(
                label: Text(c.label(isAr)),
                selected: selected,
                onSelected: (yes) {
                  setState(() {
                    if (yes) {
                      _columns.add(ReportColumn(
                          key: c.key,
                          labelAr: c.labelAr,
                          labelEn: c.labelEn));
                    } else {
                      _columns.removeWhere((sc) => sc.key == c.key);
                    }
                  });
                },
              );
            }).toList(),
          ),

          // ===== Filters =====
          const SizedBox(height: 16),
          _section(isAr ? '4️⃣ الفِلاتِر' : '4️⃣ Filters'),
          ..._filters.asMap().entries.map((entry) => _FilterRow(
                key: ValueKey(entry.key),
                sourceDef: _sourceDef,
                filter: entry.value,
                isAr: isAr,
                onChanged: (newF) =>
                    setState(() => _filters[entry.key] = newF),
                onRemove: () => setState(() => _filters.removeAt(entry.key)),
              )),
          TextButton.icon(
            onPressed: () {
              if (_sourceDef.columns.isEmpty) return;
              setState(() {
                _filters.add(ReportFilter(
                    field: _sourceDef.columns.first.key,
                    op: FilterOp.eq,
                    value: ''));
              });
            },
            icon: const Icon(Icons.add),
            label: Text(isAr ? 'فِلتَر جَديد' : 'Add filter'),
          ),

          // ===== Group + Aggregates =====
          const SizedBox(height: 16),
          _section(isAr ? '5️⃣ التَجميع (اختِياريّ)' : '5️⃣ Group By (optional)'),
          DropdownButtonFormField<String?>(
            value: _groupBy,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: [
              DropdownMenuItem(
                value: null,
                child: Text(isAr ? '— بِدون تَجميع —' : '— No grouping —'),
              ),
              ..._sourceDef.columns.map((c) => DropdownMenuItem(
                  value: c.key, child: Text(c.label(isAr)))),
            ],
            onChanged: (v) => setState(() => _groupBy = v),
          ),
          if (_groupBy != null) ...[
            const SizedBox(height: 8),
            ..._aggregates.asMap().entries.map((entry) => _AggregateRow(
                  key: ValueKey('agg_${entry.key}'),
                  sourceDef: _sourceDef,
                  agg: entry.value,
                  isAr: isAr,
                  onChanged: (newA) =>
                      setState(() => _aggregates[entry.key] = newA),
                  onRemove: () =>
                      setState(() => _aggregates.removeAt(entry.key)),
                )),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _aggregates.add(ReportAggregate(
                    field: _sourceDef.columns.first.key,
                    fn: AggregateFn.count,
                    labelAr: 'العَدَد',
                    labelEn: 'Count',
                  ));
                });
              },
              icon: const Icon(Icons.add),
              label: Text(isAr ? 'تَجميع جَديد' : 'Add aggregate'),
            ),
          ],

          // ===== Sort =====
          const SizedBox(height: 16),
          _section(isAr ? '6️⃣ التَرتيب' : '6️⃣ Sort'),
          ..._sort.asMap().entries.map((entry) => _SortRow(
                key: ValueKey('sort_${entry.key}'),
                sourceDef: _sourceDef,
                sort: entry.value,
                isAr: isAr,
                onChanged: (newS) =>
                    setState(() => _sort[entry.key] = newS),
                onRemove: () => setState(() => _sort.removeAt(entry.key)),
              )),
          TextButton.icon(
            onPressed: () {
              setState(() {
                _sort.add(ReportSort(
                    field: _sourceDef.columns.first.key, descending: false));
              });
            },
            icon: const Icon(Icons.add),
            label: Text(isAr ? 'تَرتيب جَديد' : 'Add sort'),
          ),

          // ===== Sharing =====
          const SizedBox(height: 16),
          _section(isAr ? '7️⃣ المُشارَكة' : '7️⃣ Sharing'),
          SwitchListTile(
            value: _isShared,
            onChanged: (v) => setState(() => _isShared = v),
            title: Text(isAr
                ? 'مُشارَك مَع كُلّ المُستَخدِمين'
                : 'Shared with all users'),
            subtitle: Text(
              isAr
                  ? 'لَو مُغلَق → التَقرير خاصّ بِك فَقَط'
                  : 'If off → report is private to you',
              style: const TextStyle(fontSize: 11),
            ),
          ),

          // ===== Actions =====
          const SizedBox(height: 24),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _preview,
                icon: const Icon(Icons.play_arrow),
                label: Text(isAr ? 'مُعايَنة' : 'Preview'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save),
                label: Text(isAr ? 'حِفظ' : 'Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _section(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
    );
  }
}

// ============================================================
// Helper widgets
// ============================================================
class _FilterRow extends StatelessWidget {
  final ReportSourceDef sourceDef;
  final ReportFilter filter;
  final bool isAr;
  final ValueChanged<ReportFilter> onChanged;
  final VoidCallback onRemove;

  const _FilterRow({
    super.key,
    required this.sourceDef,
    required this.filter,
    required this.isAr,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          // Field
          Expanded(
            flex: 3,
            child: DropdownButton<String>(
              isExpanded: true,
              value: filter.field,
              items: sourceDef.columns
                  .map((c) => DropdownMenuItem(
                      value: c.key, child: Text(c.label(isAr))))
                  .toList(),
              onChanged: (v) {
                if (v != null) {
                  onChanged(ReportFilter(
                      field: v, op: filter.op, value: filter.value));
                }
              },
            ),
          ),
          const SizedBox(width: 6),
          // Op
          Expanded(
            flex: 2,
            child: DropdownButton<FilterOp>(
              isExpanded: true,
              value: filter.op,
              items: FilterOp.values
                  .map((op) =>
                      DropdownMenuItem(value: op, child: Text(op.key)))
                  .toList(),
              onChanged: (v) {
                if (v != null) {
                  onChanged(ReportFilter(
                      field: filter.field, op: v, value: filter.value));
                }
              },
            ),
          ),
          const SizedBox(width: 6),
          // Value
          Expanded(
            flex: 3,
            child: TextField(
              decoration: InputDecoration(
                hintText: isAr ? 'القِيمة' : 'value',
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                border: const OutlineInputBorder(),
              ),
              controller:
                  TextEditingController(text: filter.value?.toString() ?? ''),
              onSubmitted: (v) => onChanged(ReportFilter(
                  field: filter.field, op: filter.op, value: v)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.red, size: 18),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _AggregateRow extends StatelessWidget {
  final ReportSourceDef sourceDef;
  final ReportAggregate agg;
  final bool isAr;
  final ValueChanged<ReportAggregate> onChanged;
  final VoidCallback onRemove;

  const _AggregateRow({
    super.key,
    required this.sourceDef,
    required this.agg,
    required this.isAr,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: DropdownButton<AggregateFn>(
              isExpanded: true,
              value: agg.fn,
              items: AggregateFn.values
                  .map((f) =>
                      DropdownMenuItem(value: f, child: Text(f.key)))
                  .toList(),
              onChanged: (v) {
                if (v != null) {
                  onChanged(ReportAggregate(
                      field: agg.field,
                      fn: v,
                      labelAr: agg.labelAr,
                      labelEn: agg.labelEn));
                }
              },
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 3,
            child: DropdownButton<String>(
              isExpanded: true,
              value: agg.field,
              items: sourceDef.columns
                  .map((c) => DropdownMenuItem(
                      value: c.key, child: Text(c.label(isAr))))
                  .toList(),
              onChanged: (v) {
                if (v != null) {
                  onChanged(ReportAggregate(
                      field: v,
                      fn: agg.fn,
                      labelAr: agg.labelAr,
                      labelEn: agg.labelEn));
                }
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.red, size: 18),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _SortRow extends StatelessWidget {
  final ReportSourceDef sourceDef;
  final ReportSort sort;
  final bool isAr;
  final ValueChanged<ReportSort> onChanged;
  final VoidCallback onRemove;

  const _SortRow({
    super.key,
    required this.sourceDef,
    required this.sort,
    required this.isAr,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: DropdownButton<String>(
              isExpanded: true,
              value: sort.field,
              items: sourceDef.columns
                  .map((c) => DropdownMenuItem(
                      value: c.key, child: Text(c.label(isAr))))
                  .toList(),
              onChanged: (v) {
                if (v != null) {
                  onChanged(
                      ReportSort(field: v, descending: sort.descending));
                }
              },
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 2,
            child: DropdownButton<bool>(
              isExpanded: true,
              value: sort.descending,
              items: [
                DropdownMenuItem(
                    value: false,
                    child: Text(isAr ? 'تَصاعُديّ' : 'asc')),
                DropdownMenuItem(
                    value: true,
                    child: Text(isAr ? 'تَنازُليّ' : 'desc')),
              ],
              onChanged: (v) {
                if (v != null) {
                  onChanged(
                      ReportSort(field: sort.field, descending: v));
                }
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.red, size: 18),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
