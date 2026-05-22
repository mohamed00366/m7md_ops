import 'package:flutter/material.dart';

import '../core/l10n/app_strings.dart';
import '../core/services/audit_log_service.dart';
import '../core/theme/app_colors.dart';

/// 📜 جَدول زَمَنيّ مُختَصَر لِأَنشِطة كِيان مُحَدَّد
///
/// **الاستِخدام** (داخِل أَيّ Hub):
/// ```dart
/// EntityTimelineWidget(
///   entityType: 'master',
///   entityId: master.id,
///   limit: 5,
/// )
/// ```
///
/// يَختَفي تِلقائيّاً لَو لا تُوجَد إدخالات.
class EntityTimelineWidget extends StatefulWidget {
  final String entityType;
  final String entityId;
  final int limit;
  final bool showHeader;

  const EntityTimelineWidget({
    super.key,
    required this.entityType,
    required this.entityId,
    this.limit = 5,
    this.showHeader = true,
  });

  @override
  State<EntityTimelineWidget> createState() => _EntityTimelineWidgetState();
}

class _EntityTimelineWidgetState extends State<EntityTimelineWidget> {
  @override
  void initState() {
    super.initState();
    AuditLogService.instance.load();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AuditLogService.instance,
      builder: (context, _) {
        final isAr = AppStrings.of(context).isAr;
        final entries = AuditLogService.instance
            .forEntity(widget.entityType, widget.entityId)
            .take(widget.limit)
            .toList();
        if (entries.isEmpty) return const SizedBox.shrink();
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.showHeader)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.08),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(12)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.history,
                          color: AppColors.gold, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        isAr ? 'سِجِلّ النَشاط' : 'Activity Timeline',
                        style: const TextStyle(
                            color: AppColors.gold,
                            fontWeight: FontWeight.w900,
                            fontSize: 13),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.gold.withValues(alpha: 0.20),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${entries.length}',
                          style: const TextStyle(
                              color: AppColors.gold,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              fontFamily: 'monospace'),
                        ),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  children: [
                    for (var i = 0; i < entries.length; i++)
                      _TimelineRow(
                        entry: entries[i],
                        isFirst: i == 0,
                        isLast: i == entries.length - 1,
                        isAr: isAr,
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final AuditEntry entry;
  final bool isFirst;
  final bool isLast;
  final bool isAr;
  const _TimelineRow({
    required this.entry,
    required this.isFirst,
    required this.isLast,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    final color = _actionColor(entry.action);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // الخَطّ العَموديّ + النُقطة
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Container(
                  width: 2,
                  height: isFirst ? 6 : 14,
                  color: isFirst
                      ? Colors.transparent
                      : Colors.grey.withValues(alpha: 0.3),
                ),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: color.withValues(alpha: 0.30),
                          blurRadius: 4,
                          spreadRadius: 1),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    color: isLast
                        ? Colors.transparent
                        : Colors.grey.withValues(alpha: 0.3),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // المُحتَوى
          Expanded(
            child: Padding(
              padding:
                  const EdgeInsets.only(bottom: 10, top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _actionLabel(entry.action, isAr),
                          style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w900,
                              fontSize: 9),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          entry.actorName,
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w800),
                        ),
                      ),
                      Text(
                        _timeAgo(entry.at, isAr),
                        style: const TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                            fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                  if (entry.summary != null && entry.summary!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        entry.summary!,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.grey),
                      ),
                    ),
                  if (entry.diff != null && entry.diff!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 2,
                        children: entry.diff!.entries
                            .map((kv) => Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '${kv.key}: ${kv.value}',
                                    style: TextStyle(
                                        color: color,
                                        fontSize: 10,
                                        fontFamily: 'monospace'),
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _timeAgo(DateTime d, bool isAr) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return isAr ? 'الآن' : 'just now';
    if (diff.inHours < 1) {
      return isAr ? 'مُنذ ${diff.inMinutes}د' : '${diff.inMinutes}m ago';
    }
    if (diff.inDays < 1) {
      return isAr ? 'مُنذ ${diff.inHours}س' : '${diff.inHours}h ago';
    }
    if (diff.inDays < 7) {
      return isAr ? 'مُنذ ${diff.inDays}ي' : '${diff.inDays}d ago';
    }
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static Color _actionColor(AuditAction a) {
    switch (a) {
      case AuditAction.create:
      case AuditAction.activate:
        return AppColors.success;
      case AuditAction.update:
        return AppColors.info;
      case AuditAction.delete:
        return Colors.red;
      case AuditAction.deactivate:
        return Colors.orange;
      case AuditAction.login:
        return AppColors.brand;
      case AuditAction.logout:
        return Colors.grey;
      case AuditAction.custom:
        return AppColors.gold;
    }
  }

  static String _actionLabel(AuditAction a, bool isAr) {
    switch (a) {
      case AuditAction.create:
        return isAr ? 'إنشاء' : 'CREATE';
      case AuditAction.update:
        return isAr ? 'تَعديل' : 'UPDATE';
      case AuditAction.delete:
        return isAr ? 'حَذف' : 'DELETE';
      case AuditAction.activate:
        return isAr ? 'تَفعيل' : 'ACTIVATE';
      case AuditAction.deactivate:
        return isAr ? 'إيقاف' : 'DEACT';
      case AuditAction.login:
        return isAr ? 'دُخول' : 'LOGIN';
      case AuditAction.logout:
        return isAr ? 'خُروج' : 'LOGOUT';
      case AuditAction.custom:
        return isAr ? 'مُخَصَّص' : 'CUSTOM';
    }
  }
}
