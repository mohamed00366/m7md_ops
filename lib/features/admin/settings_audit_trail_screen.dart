// =============================================================================
// 📜 شاشة سِجِلّ تَدقيق الإعدادات
// =============================================================================
// تَعرِض كُلّ تَعديل عَلى `app_settings` (مِن جَدوَل settings_audit_log):
//   - مِفتاح الإعداد
//   - مَن غَيَّر + مَتى
//   - القِيمة القَديمة → الجَديدة (JSON diff)
//
// مُتَطَلَّبات:
//   - مِجرايشن: 2026_05_23_settings_audit_log.sql
//   - الصَلاحيّة: P.auditLogView
// =============================================================================

import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/m7_log.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/m7_app_bar.dart';

class SettingsAuditTrailScreen extends StatefulWidget {
  const SettingsAuditTrailScreen({super.key});

  @override
  State<SettingsAuditTrailScreen> createState() =>
      _SettingsAuditTrailScreenState();
}

class _SettingsAuditTrailScreenState
    extends State<SettingsAuditTrailScreen> {
  bool _loading = true;
  List<_AuditEntry> _entries = const [];
  String _filterKey = '';
  String _filterUser = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final supa = SupabaseService();
    if (!supa.isReady) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final rows = await supa.client
          .from('settings_audit_log')
          .select()
          .order('created_at', ascending: false)
          .limit(500);
      _entries = (rows as List)
          .map((r) => _AuditEntry.fromRow(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      M7Log.error('SettingsAudit', 'load', error: e);
      _entries = const [];
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    var filtered = _entries;
    if (_filterKey.isNotEmpty) {
      final q = _filterKey.toLowerCase();
      filtered =
          filtered.where((e) => e.settingKey.toLowerCase().contains(q)).toList();
    }
    if (_filterUser.isNotEmpty) {
      final q = _filterUser.toLowerCase();
      filtered = filtered
          .where((e) =>
              (e.changedByName ?? '').toLowerCase().contains(q))
          .toList();
    }

    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? '📜 سِجِلّ تَدقيق الإعدادات' : '📜 Settings Audit Trail',
        subtitle: isAr
            ? '${filtered.length} سَجِلّ مِن ${_entries.length}'
            : '${filtered.length} of ${_entries.length} entries',
        actions: [
          M7AppBarAction(
            icon: Icons.refresh,
            onPressed: _load,
            tooltip: isAr ? 'تَحديث' : 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ===== فَلاتِر =====
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          decoration: InputDecoration(
                            hintText: isAr
                                ? '🔍 بَحث بِالمِفتاح...'
                                : '🔍 Filter by key...',
                            isDense: true,
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: (v) => setState(() => _filterKey = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          decoration: InputDecoration(
                            hintText: isAr
                                ? '👤 بَحث بِاسم المُستَخدِم...'
                                : '👤 Filter by user...',
                            isDense: true,
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: (v) =>
                              setState(() => _filterUser = v),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.history,
                                  size: 64,
                                  color: Colors.grey.withValues(alpha: 0.4)),
                              const SizedBox(height: 12),
                              Text(
                                isAr
                                    ? 'لا تَوجَد سِجِلّات تُطابِق البَحث'
                                    : 'No matching entries',
                                style: const TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(10),
                          itemCount: filtered.length,
                          itemBuilder: (_, i) =>
                              _EntryTile(entry: filtered[i], isAr: isAr),
                        ),
                ),
              ],
            ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  final _AuditEntry entry;
  final bool isAr;
  const _EntryTile({required this.entry, required this.isAr});

  String _fmtDateTime(DateTime d) {
    final ld = d.toLocal();
    return '${ld.year}-${ld.month.toString().padLeft(2, '0')}-${ld.day.toString().padLeft(2, '0')} '
        '${ld.hour.toString().padLeft(2, '0')}:${ld.minute.toString().padLeft(2, '0')}';
  }

  Color get _opColor {
    if (entry.oldValue == null && entry.newValue != null) {
      return AppColors.success; // create
    } else if (entry.oldValue != null && entry.newValue == null) {
      return AppColors.danger; // delete
    } else {
      return AppColors.info; // update
    }
  }

  String _opLabel() {
    if (entry.oldValue == null && entry.newValue != null) {
      return isAr ? '➕ إنشاء' : '➕ Create';
    } else if (entry.oldValue != null && entry.newValue == null) {
      return isAr ? '🗑 حَذف' : '🗑 Delete';
    } else {
      return isAr ? '✏️ تَعديل' : '✏️ Update';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _opColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ===== Header =====
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _opColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(_opLabel(),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: _opColor)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry.settingKey,
                  style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w800,
                      fontSize: 13),
                ),
              ),
              Text(_fmtDateTime(entry.createdAt),
                  style:
                      const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 6),
          // ===== Who =====
          Row(
            children: [
              const Icon(Icons.person_outline,
                  size: 14, color: Colors.grey),
              const SizedBox(width: 6),
              Text(
                entry.changedByName ?? (isAr ? 'غَير مَعروف' : 'Unknown'),
                style: const TextStyle(
                    fontSize: 12, color: Colors.grey),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(entry.settingScope,
                    style: const TextStyle(
                        fontSize: 10, color: Colors.grey)),
              ),
            ],
          ),
          // ===== Diff =====
          if (entry.oldValue != null || entry.newValue != null) ...[
            const SizedBox(height: 8),
            _DiffRow(
              isAr: isAr,
              oldValue: entry.oldValue,
              newValue: entry.newValue,
            ),
          ],
          // ===== Notes =====
          if (entry.notes != null && entry.notes!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              entry.notes!,
              style: const TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey),
            ),
          ],
        ],
      ),
    );
  }
}

class _DiffRow extends StatelessWidget {
  final bool isAr;
  final dynamic oldValue;
  final dynamic newValue;
  const _DiffRow({
    required this.isAr,
    required this.oldValue,
    required this.newValue,
  });

  String _fmt(dynamic v) {
    if (v == null) return isAr ? '— (لا شَيء)' : '— (none)';
    return v.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (oldValue != null) ...[
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 1),
                  color: AppColors.danger.withValues(alpha: 0.15),
                  child: Text(
                    isAr ? 'قَديم' : 'Old',
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: AppColors.danger),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _fmt(oldValue),
                    style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: Colors.grey),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
          ],
          if (newValue != null)
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 1),
                  color: AppColors.success.withValues(alpha: 0.15),
                  child: Text(
                    isAr ? 'جَديد' : 'New',
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: AppColors.success),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _fmt(newValue),
                    style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace'),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _AuditEntry {
  final String id;
  final String settingKey;
  final String settingScope;
  final dynamic oldValue;
  final dynamic newValue;
  final String? changedBy;
  final String? changedByName;
  final String? notes;
  final DateTime createdAt;

  const _AuditEntry({
    required this.id,
    required this.settingKey,
    required this.settingScope,
    this.oldValue,
    this.newValue,
    this.changedBy,
    this.changedByName,
    this.notes,
    required this.createdAt,
  });

  factory _AuditEntry.fromRow(Map<String, dynamic> r) => _AuditEntry(
        id: r['id'] as String,
        settingKey: r['setting_key'] as String? ?? '',
        settingScope: r['setting_scope'] as String? ?? 'app_settings',
        oldValue: r['old_value'],
        newValue: r['new_value'],
        changedBy: r['changed_by'] as String?,
        changedByName: r['changed_by_name'] as String?,
        notes: r['notes'] as String?,
        createdAt:
            DateTime.tryParse(r['created_at'] as String? ?? '') ??
                DateTime.now(),
      );
}
