// =============================================================================
// 🌊 شاشة تَدَفُّق النَشاطات (Activity Feed)
// =============================================================================
// تَجمَع كُلّ النَشاطات الأَخيرة في التَطبيق في timeline واحِد:
//   - تَغييرات الإعدادات (settings_audit_log)
//   - تَغييرات حالة المُوَظَّفين (employee_status_changes)
//   - نُسَخ احتِياطيّة (database_backups)
//
// مَع filter بِالنَوع وَ بِالتاريخ.
// =============================================================================

import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/m7_log.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/m7_app_bar.dart';
import '../../shared/m7_empty_state.dart';

class ActivityFeedScreen extends StatefulWidget {
  const ActivityFeedScreen({super.key});

  @override
  State<ActivityFeedScreen> createState() => _ActivityFeedScreenState();
}

enum _ActivityKind { settings, employeeStatus, backup }

class _ActivityEntry {
  final _ActivityKind kind;
  final String title;
  final String? subtitle;
  final String? actor;
  final DateTime when;
  final Color color;
  final IconData icon;

  const _ActivityEntry({
    required this.kind,
    required this.title,
    this.subtitle,
    this.actor,
    required this.when,
    required this.color,
    required this.icon,
  });
}

class _ActivityFeedScreenState extends State<ActivityFeedScreen> {
  bool _loading = true;
  List<_ActivityEntry> _entries = const [];
  _ActivityKind? _filter;

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
    final entries = <_ActivityEntry>[];

    // 1) Settings changes
    try {
      final rows = await supa.client
          .from('settings_audit_log')
          .select()
          .order('created_at', ascending: false)
          .limit(50);
      for (final r in rows as List) {
        final m = r as Map<String, dynamic>;
        final op = (m['old_value'] == null)
            ? 'create'
            : (m['new_value'] == null ? 'delete' : 'update');
        entries.add(_ActivityEntry(
          kind: _ActivityKind.settings,
          title: '⚙ ${m['setting_key']}',
          subtitle: 'Settings $op',
          actor: m['changed_by_name'] as String?,
          when: DateTime.tryParse(m['created_at'] as String? ?? '') ??
              DateTime.now(),
          color: op == 'delete'
              ? AppColors.danger
              : (op == 'create' ? AppColors.success : AppColors.info),
          icon: Icons.settings,
        ));
      }
    } catch (e) {
      M7Log.error('Activity', 'settings', error: e);
    }

    // 2) Employee status changes
    try {
      final rows = await supa.client
          .from('employee_status_changes')
          .select('id,employee_id,old_status,new_status,reason,created_at,triggered_by')
          .order('created_at', ascending: false)
          .limit(50);
      for (final r in rows as List) {
        final m = r as Map<String, dynamic>;
        entries.add(_ActivityEntry(
          kind: _ActivityKind.employeeStatus,
          title: '👤 ${m['old_status'] ?? "—"} → ${m['new_status']}',
          subtitle: 'Reason: ${m['reason'] ?? "—"}',
          when: DateTime.tryParse(m['created_at'] as String? ?? '') ??
              DateTime.now(),
          color: _statusColor(m['new_status'] as String?),
          icon: Icons.person_outline,
        ));
      }
    } catch (e) {
      M7Log.error('Activity', 'employee_status', error: e);
    }

    // 3) Database backups
    try {
      final rows = await supa.client
          .from('database_backups')
          .select('id,backup_type,status,total_rows,created_at,duration_ms')
          .order('created_at', ascending: false)
          .limit(20);
      for (final r in rows as List) {
        final m = r as Map<String, dynamic>;
        entries.add(_ActivityEntry(
          kind: _ActivityKind.backup,
          title: '💾 Backup ${m['backup_type']} • ${m['total_rows']} rows',
          subtitle:
              '${m['status']} • ${m['duration_ms'] ?? "?"}ms',
          when: DateTime.tryParse(m['created_at'] as String? ?? '') ??
              DateTime.now(),
          color: m['status'] == 'completed'
              ? AppColors.success
              : (m['status'] == 'failed'
                  ? AppColors.danger
                  : AppColors.info),
          icon: Icons.backup_outlined,
        ));
      }
    } catch (e) {
      M7Log.error('Activity', 'backups', error: e);
    }

    // Sort all by date desc
    entries.sort((a, b) => b.when.compareTo(a.when));

    if (mounted) {
      setState(() {
        _entries = entries;
        _loading = false;
      });
    }
  }

  Color _statusColor(String? s) {
    switch (s) {
      case 'active':
        return AppColors.success;
      case 'vacation':
        return AppColors.info;
      case 'suspended':
        return AppColors.warning;
      case 'resigned':
      case 'terminated':
        return AppColors.danger;
      default:
        return Colors.grey;
    }
  }

  String _kindLabel(_ActivityKind k, bool isAr) {
    switch (k) {
      case _ActivityKind.settings:
        return isAr ? 'الإعدادات' : 'Settings';
      case _ActivityKind.employeeStatus:
        return isAr ? 'حالة المُوَظَّف' : 'Employee Status';
      case _ActivityKind.backup:
        return isAr ? 'النَسخ الاحتِياطيّ' : 'Backup';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    var filtered = _entries;
    if (_filter != null) {
      filtered = filtered.where((e) => e.kind == _filter).toList();
    }

    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? '🌊 تَدَفُّق النَشاطات' : '🌊 Activity Feed',
        subtitle: isAr
            ? '${filtered.length} نَشاط مُؤَخَّراً'
            : '${filtered.length} recent activities',
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
                // ===== فِلتَر النَوع =====
                Container(
                  padding: const EdgeInsets.all(8),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _chip(
                          isAr ? 'الكُلّ' : 'All',
                          _filter == null,
                          () => setState(() => _filter = null),
                        ),
                        for (final k in _ActivityKind.values) ...[
                          const SizedBox(width: 4),
                          _chip(
                            _kindLabel(k, isAr),
                            _filter == k,
                            () => setState(() =>
                                _filter = _filter == k ? null : k),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: filtered.isEmpty
                      ? M7EmptyState(
                          icon: Icons.timeline,
                          titleAr: 'لا تَوجَد نَشاطات بَعد',
                          titleEn: 'No activities yet',
                          actionLabel: isAr ? 'تَحديث' : 'Refresh',
                          onAction: _load,
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: filtered.length,
                          itemBuilder: (_, i) =>
                              _ActivityTile(entry: filtered[i], isAr: isAr),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.brand
              : Colors.grey.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: selected ? Colors.white : Colors.grey,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  final _ActivityEntry entry;
  final bool isAr;
  const _ActivityTile({required this.entry, required this.isAr});

  String _relTime(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return isAr ? 'الآن' : 'now';
    if (diff.inMinutes < 60) {
      return isAr ? 'مُنذ ${diff.inMinutes}د' : '${diff.inMinutes}m ago';
    }
    if (diff.inHours < 24) {
      return isAr ? 'مُنذ ${diff.inHours}س' : '${diff.inHours}h ago';
    }
    if (diff.inDays < 7) {
      return isAr ? 'مُنذ ${diff.inDays}ي' : '${diff.inDays}d ago';
    }
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: entry.color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: entry.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(entry.icon, color: entry.color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                if (entry.subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(entry.subtitle!,
                      style: const TextStyle(
                          fontSize: 11, color: Colors.grey),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
                if (entry.actor != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '👤 ${entry.actor}',
                    style: const TextStyle(
                        fontSize: 10, color: Colors.grey),
                  ),
                ],
              ],
            ),
          ),
          Text(
            _relTime(entry.when),
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
