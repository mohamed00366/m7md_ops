import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets.dart';

/// شاشة سجل التدقيق (Audit Log) - تقرأ مباشرة من Supabase
/// تعرض كل حركة في النظام: مَن، ماذا، متى، قبل، بعد
class AdminAudit extends StatefulWidget {
  const AdminAudit({super.key});

  @override
  State<AdminAudit> createState() => _AdminAuditState();
}

class _AdminAuditState extends State<AdminAudit> {
  String? _filterEntity;
  String? _filterAction;
  bool _loading = false;
  List<Map<String, dynamic>> _logs = [];
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
      if (!SupabaseService().isReady) {
        setState(() {
          _logs = [];
          _loading = false;
          _error = 'Supabase not ready';
        });
        return;
      }
      var query = SupabaseService().client.from('audit_logs').select();
      // ملاحظة: للفلترة نستخدم API الجديد
      final rows = await query
          .order('created_at', ascending: false)
          .limit(500);
      setState(() {
        _logs = (rows as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _logs = [];
        _loading = false;
        _error = e.toString();
      });
    }
  }

  List<Map<String, dynamic>> _filtered() {
    return _logs.where((l) {
      if (_filterEntity != null && l['entity_type'] != _filterEntity) {
        return false;
      }
      if (_filterAction != null && l['action'] != _filterAction) return false;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _logs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline,
                  color: AppColors.danger, size: 48),
              const SizedBox(height: 12),
              Text(s.isAr ? 'فشل تحميل السجل' : 'Failed to load',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(_error!,
                  style: const TextStyle(fontSize: 11),
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: Text(s.isAr ? 'إعادة المحاولة' : 'Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final entities = _logs
        .map((l) => l['entity_type'] as String? ?? '')
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final actions = _logs
        .map((l) => l['action'] as String? ?? '')
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final filtered = _filtered();

    return Scaffold(
      body: Column(
        children: [
          // فلاتر
          Container(
            color: Theme.of(context).cardTheme.color,
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _Chip(
                        label: s.isAr ? 'الكل' : 'All',
                        selected: _filterEntity == null,
                        onTap: () => setState(() => _filterEntity = null),
                      ),
                      ...entities.map((e) => _Chip(
                            label: e,
                            selected: _filterEntity == e,
                            onTap: () => setState(() => _filterEntity = e),
                          )),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _Chip(
                        label: s.isAr ? 'كل الأفعال' : 'All actions',
                        selected: _filterAction == null,
                        small: true,
                        onTap: () => setState(() => _filterAction = null),
                      ),
                      ...actions.map((a) => _Chip(
                            label: a,
                            selected: _filterAction == a,
                            small: true,
                            color: _actionColor(a),
                            onTap: () => setState(() => _filterAction = a),
                          )),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // قائمة السجلات
          Expanded(
            child: filtered.isEmpty
                ? EmptyState(
                    icon: Icons.history,
                    message: s.isAr ? 'لا توجد سجلات' : 'No logs',
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) => _AuditCard(log: filtered[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Color _actionColor(String a) {
    switch (a) {
      case 'create':
        return AppColors.success;
      case 'update':
        return AppColors.info;
      case 'delete':
        return AppColors.danger;
      case 'submit':
      case 'reEdit':
        return AppColors.warning;
      case 'approve':
        return AppColors.success;
      case 'reject':
        return AppColors.danger;
      case 'assign':
      case 'unassign':
        return AppColors.brand;
      default:
        return AppColors.textTertiaryLight;
    }
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;
  final bool small;
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
    this.small = false,
  });
  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.brand;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: small ? 10 : 12, vertical: small ? 4 : 6),
          decoration: BoxDecoration(
            color: selected ? c : c.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: c.withOpacity(selected ? 1 : 0.3)),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : c,
              fontSize: small ? 10 : 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _AuditCard extends StatelessWidget {
  final Map<String, dynamic> log;
  const _AuditCard({required this.log});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final action = (log['action'] as String?) ?? '?';
    final entity = (log['entity_type'] as String?) ?? '?';
    final label = (log['entity_label'] as String?) ?? '';
    final actor = (log['actor_name'] as String?) ?? '—';
    final role = (log['actor_role'] as String?) ?? '';
    final desc = (log['description'] as String?) ?? '';
    final at = log['created_at'] == null
        ? null
        : DateTime.tryParse(log['created_at'] as String);
    final changedFields =
        (log['changed_fields'] as List?)?.cast<String>() ?? const [];
    final actionColor = _color(action);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: actionColor,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(action.toUpperCase(),
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 10)),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.brand.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(entity,
                    style: const TextStyle(
                        color: AppColors.brand,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                        fontSize: 10)),
              ),
              const Spacer(),
              if (at != null)
                Text(_fmtDt(at),
                    style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).disabledColor)),
            ],
          ),
          const SizedBox(height: 6),
          if (label.isNotEmpty)
            Text(label,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(desc, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.person,
                  size: 11, color: Theme.of(context).disabledColor),
              const SizedBox(width: 3),
              Text(actor, style: const TextStyle(fontSize: 11)),
              if (role.isNotEmpty) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Theme.of(context).dividerColor.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(role,
                      style: const TextStyle(
                          fontSize: 9, fontWeight: FontWeight.w600)),
                ),
              ],
            ],
          ),
          if (changedFields.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: changedFields
                  .map((f) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(f,
                            style: const TextStyle(
                                fontSize: 10,
                                fontFamily: 'monospace',
                                color: AppColors.warning,
                                fontWeight: FontWeight.w700)),
                      ))
                  .toList(),
            ),
          ],
          if (log['before_data'] != null || log['after_data'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: TextButton.icon(
                onPressed: () => _showDetails(context),
                icon: const Icon(Icons.compare_arrows, size: 14),
                label: Text(
                    s.isAr ? 'عرض قبل/بعد' : 'View before/after',
                    style: const TextStyle(fontSize: 11)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showDetails(BuildContext context) {
    final s = AppStrings.of(context);
    final before = log['before_data'];
    final after = log['after_data'];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      s.isAr ? 'تفاصيل السجل' : 'Log Details',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  if (before != null) ...[
                    _SectionTitle(
                      title: s.isAr ? 'قبل (Before)' : 'Before',
                      color: AppColors.danger,
                    ),
                    _JsonViewer(data: before),
                    const SizedBox(height: 14),
                  ],
                  if (after != null) ...[
                    _SectionTitle(
                      title: s.isAr ? 'بعد (After)' : 'After',
                      color: AppColors.success,
                    ),
                    _JsonViewer(data: after),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _color(String a) {
    switch (a) {
      case 'create':
      case 'approve':
        return AppColors.success;
      case 'update':
        return AppColors.info;
      case 'delete':
      case 'reject':
        return AppColors.danger;
      case 'submit':
      case 'reEdit':
        return AppColors.warning;
      case 'assign':
      case 'unassign':
        return AppColors.brand;
      default:
        return AppColors.textTertiaryLight;
    }
  }

  String _fmtDt(DateTime d) {
    final l = d.toLocal();
    return '${l.day}/${l.month.toString().padLeft(2, '0')}/${l.year} '
        '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final Color color;
  const _SectionTitle({required this.title, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(title,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w800)),
    );
  }
}

class _JsonViewer extends StatelessWidget {
  final dynamic data;
  const _JsonViewer({required this.data});
  @override
  Widget build(BuildContext context) {
    String text;
    try {
      text = const JsonEncoder.withIndent('  ').convert(data);
    } catch (_) {
      text = data.toString();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).dividerColor.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        text,
        style: const TextStyle(
            fontFamily: 'monospace', fontSize: 11, height: 1.5),
      ),
    );
  }
}
