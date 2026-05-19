import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/notifications_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/notification.dart';

/// 🔔 شاشة الإشعارات
///
/// تَعرض كلّ إشعارات المستخدم الحاليّ مَع:
/// - فلتر: الكلّ / غَير مَقروء
/// - تَعليم الكلّ كَمقروء
/// - النَقر على إشعار → تَعليمه + الانتِقال (لو فيه deep link)
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _showOnlyUnread = false;

  @override
  void initState() {
    super.initState();
    // refresh عند فَتح الشاشة
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationsService.instance.refresh();
    });
  }

  Color _colorForPriority(String p) {
    switch (p) {
      case 'urgent':
        return AppColors.danger;
      case 'high':
        return AppColors.warning;
      case 'low':
        return Colors.grey;
      default:
        return AppColors.brand;
    }
  }

  String _timeAgo(DateTime dt, bool isAr) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) {
      return isAr ? 'الآن' : 'just now';
    }
    if (diff.inMinutes < 60) {
      return isAr
          ? 'مُنذ ${diff.inMinutes} د'
          : '${diff.inMinutes}m ago';
    }
    if (diff.inHours < 24) {
      return isAr ? 'مُنذ ${diff.inHours} س' : '${diff.inHours}h ago';
    }
    if (diff.inDays < 7) {
      return isAr ? 'مُنذ ${diff.inDays} يوم' : '${diff.inDays}d ago';
    }
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    return ChangeNotifierProvider.value(
      value: NotificationsService.instance,
      child: Consumer<NotificationsService>(
        builder: (ctx, svc, _) {
          final list = _showOnlyUnread
              ? svc.notifications.where((n) => !n.isRead).toList()
              : svc.notifications;
          return Scaffold(
            appBar: AppBar(
              title: Text(isAr
                  ? '🔔 الإشعارات (${svc.unreadCount} جَديد)'
                  : '🔔 Notifications (${svc.unreadCount} new)'),
              backgroundColor: AppColors.brand,
              foregroundColor: Colors.white,
              actions: [
                IconButton(
                  tooltip: isAr ? 'تَحديث' : 'Refresh',
                  icon: const Icon(Icons.refresh),
                  onPressed: () => svc.refresh(),
                ),
                if (svc.unreadCount > 0)
                  IconButton(
                    tooltip: isAr ? 'تَعليم الكلّ كَمقروء' : 'Mark all read',
                    icon: const Icon(Icons.done_all),
                    onPressed: () async {
                      await svc.markAllRead();
                      if (!ctx.mounted) return;
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                        backgroundColor: AppColors.success,
                        duration: const Duration(seconds: 2),
                        content: Text(isAr
                            ? '✅ تَمّ تَعليم الكلّ كَمقروء'
                            : '✅ All marked as read'),
                      ));
                    },
                  ),
              ],
            ),
            body: Column(
              children: [
                // فِلتر
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: SegmentedButton<bool>(
                    segments: [
                      ButtonSegment<bool>(
                        value: false,
                        icon: const Icon(Icons.list, size: 14),
                        label: Text(isAr ? 'الكلّ' : 'All',
                            style: const TextStyle(fontSize: 12)),
                      ),
                      ButtonSegment<bool>(
                        value: true,
                        icon: const Icon(Icons.mark_email_unread, size: 14),
                        label: Text(
                          isAr
                              ? 'غَير مَقروء (${svc.unreadCount})'
                              : 'Unread (${svc.unreadCount})',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                    selected: {_showOnlyUnread},
                    onSelectionChanged: (v) =>
                        setState(() => _showOnlyUnread = v.first),
                  ),
                ),
                // القائمة
                Expanded(
                  child: list.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.notifications_off_outlined,
                                    size: 56,
                                    color: Colors.grey.shade400),
                                const SizedBox(height: 12),
                                Text(
                                  _showOnlyUnread
                                      ? (isAr
                                          ? 'لا إشعارات غَير مَقروءة'
                                          : 'No unread notifications')
                                      : (isAr
                                          ? 'لا توجد إشعارات بَعد'
                                          : 'No notifications yet'),
                                  style: TextStyle(
                                      color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
                          itemCount: list.length,
                          itemBuilder: (_, i) => _NotifTile(
                            notif: list[i],
                            isAr: isAr,
                            color: _colorForPriority(list[i].priority),
                            timeAgo: _timeAgo(list[i].createdAt, isAr),
                            onTap: () async {
                              if (!list[i].isRead) {
                                await svc.markRead(list[i].id);
                              }
                              // (لاحقاً) deep link
                            },
                            onDelete: () => svc.delete(list[i].id),
                          ),
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _NotifTile extends StatelessWidget {
  final AppNotification notif;
  final bool isAr;
  final Color color;
  final String timeAgo;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _NotifTile({
    required this.notif,
    required this.isAr,
    required this.color,
    required this.timeAgo,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(notif.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        color: AppColors.danger,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => onDelete(),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: notif.isRead
              ? Theme.of(context).cardTheme.color
              : color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: notif.isRead
                ? Theme.of(context).dividerColor
                : color.withOpacity(0.30),
            width: notif.isRead ? 0.5 : 1,
          ),
        ),
        child: ListTile(
          onTap: onTap,
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              notif.effectiveIcon,
              style: const TextStyle(fontSize: 18),
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  notif.title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        notif.isRead ? FontWeight.w600 : FontWeight.w900,
                  ),
                ),
              ),
              if (!notif.isRead)
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if ((notif.body ?? '').isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  notif.body!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                timeAgo,
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
