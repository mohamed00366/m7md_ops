// =============================================================================
// 💾 شاشة النُسَخ الاحتِياطيّة لِقاعِدة البَيانات
// =============================================================================
// تَعرِض:
//   - سِجِلّ كامِل لِكُلّ النُسَخ (يَوميّة تِلقائيّة + يَدَويّة)
//   - زِرّ "تَشغيل نَسخة جَديدة الآن"
//   - تَفاصيل كُلّ نَسخة: عَدَد صُفوف كُلّ جَدوَل + مُدّة التَنفيذ
//
// مَلحوظة: Supabase يَحتَفِظ بِنُسَخ كامِلة تِلقائيّة (Point-in-Time Recovery)
// عَلى مُستَوى السيرفر. هذا النِظام إضافيّ لِلتَدقيق + الإحصاءات.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/m7_log.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/m7_app_bar.dart';

class DatabaseBackupsScreen extends StatefulWidget {
  const DatabaseBackupsScreen({super.key});

  @override
  State<DatabaseBackupsScreen> createState() => _DatabaseBackupsScreenState();
}

class _DatabaseBackupsScreenState extends State<DatabaseBackupsScreen> {
  bool _loading = true;
  bool _running = false;
  List<_BackupEntry> _backups = const [];

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
          .from('database_backups')
          .select()
          .order('created_at', ascending: false)
          .limit(100);
      _backups = (rows as List)
          .map((r) => _BackupEntry.fromRow(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      M7Log.error('DbBackup', 'load', error: e);
      _backups = const [];
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _runManualBackup() async {
    final supa = SupabaseService();
    final isAr = AppStrings.of(context).isAr;
    if (!supa.isReady) return;
    setState(() => _running = true);
    try {
      final auth = context.read<AuthProvider>();
      await supa.client.rpc('execute_backup_snapshot', params: {
        'p_backup_type': 'manual',
        'p_triggered_by': auth.account?.id,
        'p_notes': isAr ? 'تَشغيل يَدَويّ مِن الواجِهة' : 'Manual run from UI',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.success,
          content: Text(isAr
              ? '✅ تَمّت النَسخة الاحتِياطيّة'
              : '✅ Backup completed'),
        ));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.danger,
          content: Text(isAr ? 'فَشِل: $e' : 'Failed: $e'),
        ));
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? '💾 النُسَخ الاحتِياطيّة' : '💾 Database Backups',
        subtitle: isAr
            ? '${_backups.length} نَسخة سابِقة'
            : '${_backups.length} backups',
        actions: [
          M7AppBarAction(
            icon: Icons.refresh,
            onPressed: _load,
            tooltip: isAr ? 'تَحديث' : 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // ===== بَطاقة الجَدوَلة =====
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.info.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.schedule, color: AppColors.info, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isAr
                            ? '🕑 يَوميّاً السّاعة 02:00 UTC (06:00 AM SA / 05:00 AM UAE)'
                            : '🕑 Daily at 02:00 UTC',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isAr
                            ? 'يَحتَفِظ بِآخِر 90 يَوم تِلقائيّاً. Supabase يَأخُذ نُسَخ كامِلة عَلى السيرفر بِشَكل مُنفَصِل.'
                            : 'Auto-keeps last 90 days. Full server backups are managed separately by Supabase.',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _running ? null : _runManualBackup,
                  icon: _running
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.play_arrow, size: 16),
                  label: Text(
                      isAr ? 'تَشغيل الآن' : 'Run Now',
                      style: const TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _backups.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.cloud_off,
                                size: 64,
                                color:
                                    Colors.grey.withValues(alpha: 0.4)),
                            const SizedBox(height: 12),
                            Text(
                              isAr
                                  ? 'لا تَوجَد نُسَخ بَعد'
                                  : 'No backups yet',
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _backups.length,
                        itemBuilder: (_, i) => _BackupTile(
                          backup: _backups[i],
                          isAr: isAr,
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _BackupTile extends StatelessWidget {
  final _BackupEntry backup;
  final bool isAr;
  const _BackupTile({required this.backup, required this.isAr});

  Color get _statusColor {
    switch (backup.status) {
      case 'completed':
        return AppColors.success;
      case 'running':
        return AppColors.info;
      case 'failed':
        return AppColors.danger;
      default:
        return Colors.grey;
    }
  }

  String _fmtDateTime(DateTime d) {
    final ld = d.toLocal();
    return '${ld.year}-${ld.month.toString().padLeft(2, '0')}-${ld.day.toString().padLeft(2, '0')} '
        '${ld.hour.toString().padLeft(2, '0')}:${ld.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _statusColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  backup.status.toUpperCase(),
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: _statusColor),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: backup.backupType == 'manual'
                      ? AppColors.gold.withValues(alpha: 0.15)
                      : AppColors.brand.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  backup.backupType,
                  style: TextStyle(
                    fontSize: 10,
                    color: backup.backupType == 'manual'
                        ? AppColors.gold
                        : AppColors.brand,
                  ),
                ),
              ),
              const Spacer(),
              Text(_fmtDateTime(backup.createdAt),
                  style:
                      const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 6),
          // Stats
          Row(
            children: [
              const Icon(Icons.dataset, size: 14, color: Colors.grey),
              const SizedBox(width: 6),
              Text(
                isAr
                    ? '${backup.totalRows} صَفّ إجماليّ'
                    : '${backup.totalRows} total rows',
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(width: 16),
              if (backup.durationMs != null) ...[
                const Icon(Icons.timer, size: 14, color: Colors.grey),
                const SizedBox(width: 6),
                Text(
                  '${backup.durationMs} ms',
                  style:
                      const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ],
          ),
          // Error
          if (backup.errorMessage != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(6),
              color: AppColors.danger.withValues(alpha: 0.08),
              child: Text(
                backup.errorMessage!,
                style: TextStyle(
                    fontSize: 11, color: AppColors.danger),
              ),
            ),
          ],
          // Table counts
          if (backup.tableCounts.isNotEmpty) ...[
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text(
                isAr ? 'تَفاصيل الجَداوِل' : 'Table details',
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700),
              ),
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: backup.tableCounts.entries.map((e) {
                    final isError = e.value == -1;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: isError
                            ? AppColors.danger.withValues(alpha: 0.1)
                            : Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${e.key}: ${isError ? "—" : e.value}',
                        style: const TextStyle(
                            fontSize: 10, fontFamily: 'monospace'),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _BackupEntry {
  final String id;
  final String backupType;
  final Map<String, int> tableCounts;
  final int totalRows;
  final String status;
  final String? errorMessage;
  final int? durationMs;
  final String? notes;
  final DateTime createdAt;

  const _BackupEntry({
    required this.id,
    required this.backupType,
    required this.tableCounts,
    required this.totalRows,
    required this.status,
    this.errorMessage,
    this.durationMs,
    this.notes,
    required this.createdAt,
  });

  factory _BackupEntry.fromRow(Map<String, dynamic> r) {
    final counts = <String, int>{};
    final raw = r['table_counts'];
    if (raw is Map) {
      raw.forEach((k, v) {
        if (v is num) counts[k.toString()] = v.toInt();
      });
    }
    return _BackupEntry(
      id: r['id'] as String,
      backupType: r['backup_type'] as String? ?? 'auto',
      tableCounts: counts,
      totalRows: (r['total_rows'] as num?)?.toInt() ?? 0,
      status: r['status'] as String? ?? 'unknown',
      errorMessage: r['error_message'] as String?,
      durationMs: (r['duration_ms'] as num?)?.toInt(),
      notes: r['notes'] as String?,
      createdAt:
          DateTime.tryParse(r['created_at'] as String? ?? '') ??
              DateTime.now(),
    );
  }
}
