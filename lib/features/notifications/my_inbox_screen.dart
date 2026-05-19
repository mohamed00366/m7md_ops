import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/notifications_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/notification.dart';
import '../../shared/m7_app_bar.dart';
import '../../shared/m7_stats_banner.dart';
import '../../shared/m7_toolbar.dart';

/// 📬 صَندوق الإشعارات المُوَحَّد
///
/// يَجمَع كُلّ الإشعارات الواصِلة لِلمُستَخدِم الحاليّ مَع:
/// - فَلتَر حَسَب النَوع (الكُلّ / مُوافَقات / قَرارات / انتِهاء / عامّ)
/// - فَلتَر غَير مَقروء
/// - تَعليم كَمَقروء بِالضَغط
/// - تَعليم كُلّ شَيء مَقروء
/// - حَذف
class MyInboxScreen extends StatefulWidget {
  const MyInboxScreen({super.key});

  @override
  State<MyInboxScreen> createState() => _MyInboxScreenState();
}

class _MyInboxScreenState extends State<MyInboxScreen> {
  String? _filterType; // 'pending_approval' / 'decision' / 'document_expiry' / 'general' / null
  bool _onlyUnread = false;

  @override
  void initState() {
    super.initState();
    NotificationsService.instance.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return AnimatedBuilder(
      animation: NotificationsService.instance,
      builder: (context, _) {
        final all = NotificationsService.instance.notifications;
        var filtered = [...all];
        if (_filterType != null) {
          filtered = filtered.where((n) => n.type == _filterType).toList();
        }
        if (_onlyUnread) {
          filtered = filtered.where((n) => !n.isRead).toList();
        }
        // إحصائيّات
        final unread = all.where((n) => !n.isRead).length;
        final pending =
            all.where((n) => n.type == 'pending_approval').length;
        final decisions = all.where((n) => n.type == 'decision').length;
        final expiry = all.where((n) => n.type == 'document_expiry').length;

        return Scaffold(
          appBar: M7AppBar(
            title: isAr ? 'صَندوق الإشعارات' : 'My Inbox',
            subtitle: isAr
                ? '$unread غَير مَقروء مِن ${all.length}'
                : '$unread unread of ${all.length}',
            actions: [
              if (unread > 0)
                M7AppBarAction(
                  icon: Icons.done_all,
                  tooltip:
                      isAr ? 'تَعليم الكُلّ كَمَقروء' : 'Mark all read',
                  onPressed: () async {
                    await NotificationsService.instance.markAllRead();
                  },
                ),
              M7AppBarAction(
                icon: Icons.refresh,
                tooltip: isAr ? 'تَحديث' : 'Refresh',
                onPressed: () => NotificationsService.instance.refresh(),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              // إحصائيّات سَريعة
              M7StatsBanner(stats: [
                M7Stat(
                    icon: Icons.mark_email_unread,
                    label: isAr ? 'غَير مَقروء' : 'Unread',
                    value: unread,
                    color: AppColors.brand),
                M7Stat(
                    icon: Icons.pan_tool,
                    label: isAr ? 'مُوافَقات' : 'Approval',
                    value: pending,
                    color: Colors.orange),
                M7Stat(
                    icon: Icons.mark_email_read,
                    label: isAr ? 'قَرارات' : 'Decisions',
                    value: decisions,
                    color: AppColors.success),
                M7Stat(
                    icon: Icons.access_time,
                    label: isAr ? 'انتِهاء' : 'Expiry',
                    value: expiry,
                    color: Colors.red),
              ]),
              const SizedBox(height: 12),
              // فِلتَر الأَنواع
              SizedBox(
                height: 32,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    M7FilterPill(
                      label: isAr ? 'الكُلّ' : 'All',
                      count: all.length,
                      selected: _filterType == null && !_onlyUnread,
                      color: AppColors.brand,
                      onTap: () => setState(() {
                        _filterType = null;
                        _onlyUnread = false;
                      }),
                    ),
                    const SizedBox(width: 6),
                    M7FilterPill(
                      label: isAr ? 'غَير مَقروء' : 'Unread',
                      count: unread,
                      selected: _onlyUnread,
                      color: AppColors.brand,
                      onTap: () => setState(() => _onlyUnread = !_onlyUnread),
                    ),
                    const SizedBox(width: 6),
                    if (pending > 0) ...[
                      M7FilterPill(
                        label: isAr ? 'مُوافَقات' : 'Approval',
                        count: pending,
                        selected: _filterType == 'pending_approval',
                        color: Colors.orange,
                        onTap: () => setState(() => _filterType =
                            _filterType == 'pending_approval'
                                ? null
                                : 'pending_approval'),
                      ),
                      const SizedBox(width: 6),
                    ],
                    if (decisions > 0) ...[
                      M7FilterPill(
                        label: isAr ? 'قَرارات' : 'Decisions',
                        count: decisions,
                        selected: _filterType == 'decision',
                        color: AppColors.success,
                        onTap: () => setState(() => _filterType =
                            _filterType == 'decision' ? null : 'decision'),
                      ),
                      const SizedBox(width: 6),
                    ],
                    if (expiry > 0) ...[
                      M7FilterPill(
                        label: isAr ? 'انتِهاء' : 'Expiry',
                        count: expiry,
                        selected: _filterType == 'document_expiry',
                        color: Colors.red,
                        onTap: () => setState(() => _filterType =
                            _filterType == 'document_expiry'
                                ? null
                                : 'document_expiry'),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // قائِمة الإشعارات
              if (filtered.isEmpty)
                _emptyState(isAr, _onlyUnread)
              else
                ...filtered.map((n) => _NotificationTile(notif: n, isAr: isAr)),
              const SizedBox(height: 30),
            ],
          ),
        );
      },
    );
  }

  Widget _emptyState(bool isAr, bool onlyUnread) {
    return Container(
      padding: const EdgeInsets.all(40),
      margin: const EdgeInsets.symmetric(vertical: 30),
      decoration: BoxDecoration(
        color: AppColors.success.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.success.withOpacity(0.25)),
      ),
      child: Column(
        children: [
          Icon(
            onlyUnread ? Icons.mark_email_read : Icons.inbox_outlined,
            size: 64,
            color: AppColors.success.withOpacity(0.85),
          ),
          const SizedBox(height: 12),
          Text(
            onlyUnread
                ? (isAr ? '✨ لا إشعارات غَير مَقروءة' : '✨ Inbox zero')
                : (isAr ? 'الصَندوق فارِغ' : 'Your inbox is empty'),
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            isAr
                ? 'سَتَظهَر الإشعارات هُنا عِندَ وُصولها'
                : "We'll show notifications here as they arrive",
            style: const TextStyle(fontSize: 11, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// بِطاقة إشعار
// ============================================================
class _NotificationTile extends StatelessWidget {
  final AppNotification notif;
  final bool isAr;
  const _NotificationTile({required this.notif, required this.isAr});

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(notif);
    return Dismissible(
      key: ValueKey(notif.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
      ),
      confirmDismiss: (_) async {
        await NotificationsService.instance.delete(notif.id);
        return false; // الـAnimatedBuilder سيُعيد البِناء بِدونها
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: notif.isRead
              ? Theme.of(context).cardTheme.color
              : color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: notif.isRead
                ? color.withOpacity(0.15)
                : color.withOpacity(0.40),
            width: notif.isRead ? 0.5 : 1.2,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () async {
              if (!notif.isRead) {
                await NotificationsService.instance.markRead(notif.id);
              }
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      notif.effectiveIcon,
                      style: const TextStyle(fontSize: 20),
                    ),
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
                                notif.title,
                                style: TextStyle(
                                    fontWeight: notif.isRead
                                        ? FontWeight.w700
                                        : FontWeight.w900,
                                    fontSize: 13),
                              ),
                            ),
                            if (notif.isUrgent)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text('⚡',
                                    style: TextStyle(fontSize: 11)),
                              ),
                            if (!notif.isRead) ...[
                              const SizedBox(width: 6),
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (notif.body != null && notif.body!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            notif.body!,
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _typeLabel(notif.type, isAr),
                                style: TextStyle(
                                    color: color,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              _timeAgo(notif.createdAt, isAr),
                              style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey,
                                  fontFamily: 'monospace'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Color _colorFor(AppNotification n) {
    switch (n.type) {
      case 'pending_approval':
        return Colors.orange;
      case 'decision':
        return AppColors.success;
      case 'document_expiry':
        return Colors.red;
      default:
        return AppColors.brand;
    }
  }

  static String _typeLabel(String type, bool isAr) {
    switch (type) {
      case 'pending_approval':
        return isAr ? 'مُوافَقة' : 'Approval';
      case 'decision':
        return isAr ? 'قَرار' : 'Decision';
      case 'document_expiry':
        return isAr ? 'انتِهاء' : 'Expiry';
      default:
        return isAr ? 'عامّ' : 'General';
    }
  }

  static String _timeAgo(DateTime d, bool isAr) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return isAr ? 'الآن' : 'just now';
    if (diff.inHours < 1) {
      return isAr ? 'مُنذ ${diff.inMinutes}د' : '${diff.inMinutes}m';
    }
    if (diff.inDays < 1) {
      return isAr ? 'مُنذ ${diff.inHours}س' : '${diff.inHours}h';
    }
    if (diff.inDays < 7) {
      return isAr ? 'مُنذ ${diff.inDays}ي' : '${diff.inDays}d';
    }
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}
