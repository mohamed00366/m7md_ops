import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/l10n/app_strings.dart';
import '../core/providers/auth_provider.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_palette.dart';
import '../features/admin/forms_submissions_report_screen.dart';
import '../features/forms/admin_forms_screen.dart';
import '../models/models.dart';
import '../repositories/mock_repository.dart';

/// 🔔 جرس الإشعارات — يظهر في الشريط العلوي
class NotificationsBell extends StatefulWidget {
  const NotificationsBell({super.key});

  @override
  State<NotificationsBell> createState() => _NotificationsBellState();
}

class _NotificationsBellState extends State<NotificationsBell> {
  @override
  void initState() {
    super.initState();
    MockRepository().addListener(_onChange);
  }

  @override
  void dispose() {
    MockRepository().removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final repo = MockRepository();
    final userId = auth.currentUser?.id;
    final empId = auth.currentUser?.employeeId;
    if (userId == null) return const SizedBox.shrink();

    final unread = repo.unreadNotificationsCount(
      userId: userId,
      employeeId: empId,
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          tooltip: AppStrings.of(context).isAr ? 'الإشعارات' : 'Notifications',
          icon: const Icon(Icons.notifications_outlined),
          onPressed: () => _openPanel(context),
        ),
        if (unread > 0)
          Positioned(
            top: 6,
            right: 6,
            child: IgnorePointer(
              child: Container(
                padding: unread > 9
                    ? const EdgeInsets.symmetric(horizontal: 4, vertical: 1)
                    : const EdgeInsets.all(2),
                constraints:
                    const BoxConstraints(minWidth: 16, minHeight: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFDC2626).withOpacity(0.40),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Text(
                  unread > 99 ? '99+' : '$unread',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _openPanel(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _NotificationsPanel(),
    );
  }
}

// ============================================================
// 📋 لوحة الإشعارات (BottomSheet)
// ============================================================
class _NotificationsPanel extends StatefulWidget {
  const _NotificationsPanel();

  @override
  State<_NotificationsPanel> createState() => _NotificationsPanelState();
}

class _NotificationsPanelState extends State<_NotificationsPanel> {
  // 🆕 Session 10: فلتر الإشعارات
  bool _showOnlyUnread = false;

  @override
  void initState() {
    super.initState();
    MockRepository().addListener(_onChange);
  }

  @override
  void dispose() {
    MockRepository().removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  /// تجميع الإشعارات حسب اليوم (اليوم / أمس / هذا الأسبوع / أقدم)
  Map<String, List<AppNotification>> _groupByDate(
      List<AppNotification> list, bool isAr) {
    final result = <String, List<AppNotification>>{};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekAgo = today.subtract(const Duration(days: 7));

    final keyToday = isAr ? 'اليوم' : 'Today';
    final keyYesterday = isAr ? 'أمس' : 'Yesterday';
    final keyThisWeek = isAr ? 'هذا الأسبوع' : 'This week';
    final keyEarlier = isAr ? 'أقدم' : 'Earlier';

    for (final n in list) {
      final d = DateTime(n.createdAt.year, n.createdAt.month, n.createdAt.day);
      String key;
      if (d == today) {
        key = keyToday;
      } else if (d == yesterday) {
        key = keyYesterday;
      } else if (d.isAfter(weekAgo)) {
        key = keyThisWeek;
      } else {
        key = keyEarlier;
      }
      result.putIfAbsent(key, () => []).add(n);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final auth = context.watch<AuthProvider>();
    final repo = MockRepository();
    final userId = auth.currentUser?.id;
    final empId = auth.currentUser?.employeeId;

    var list = (userId == null)
        ? <AppNotification>[]
        : repo.notificationsFor(userId: userId, employeeId: empId);

    // 🆕 فلتر "غير المقروءة فقط"
    if (_showOnlyUnread) {
      list = list.where((n) => !n.isRead).toList();
    }

    // 🆕 تجميع حسب التاريخ (Today / Yesterday / Earlier)
    final grouped = _groupByDate(list, s.isAr);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.80,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ===== Drag handle =====
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppPalette.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          // ===== رأس =====
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.notifications,
                    color: AppColors.brand, size: 22),
                const SizedBox(width: 8),
                Text(
                  s.isAr ? 'الإشعارات' : 'Notifications',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w900),
                ),
                const Spacer(),
                if (list.any((n) => !n.isRead) || _showOnlyUnread)
                  TextButton.icon(
                    onPressed: () {
                      repo.markAllNotificationsRead(
                          userId: userId, employeeId: empId);
                    },
                    icon: const Icon(Icons.done_all, size: 14),
                    label: Text(
                      s.isAr ? 'تعليم الكل' : 'Mark all read',
                      style: const TextStyle(fontSize: 11),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
              ],
            ),
          ),
          // 🆕 Session 10: شريط فلاتر
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                _FilterChip(
                  label: s.isAr ? 'الكل' : 'All',
                  selected: !_showOnlyUnread,
                  onTap: () => setState(() => _showOnlyUnread = false),
                ),
                const SizedBox(width: 6),
                _FilterChip(
                  label: s.isAr ? 'غير مقروء' : 'Unread',
                  selected: _showOnlyUnread,
                  onTap: () => setState(() => _showOnlyUnread = true),
                ),
              ],
            ),
          ),
          const Divider(height: 16),
          // ===== القائمة =====
          Flexible(
            child: list.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.notifications_off_outlined,
                            size: 56,
                            color: AppPalette.textTertiary
                                .withOpacity(0.50)),
                        const SizedBox(height: 12),
                        Text(
                          s.isAr ? 'لا توجد إشعارات' : 'No notifications',
                          style: TextStyle(
                              color: AppPalette.textSecondary,
                              fontWeight: FontWeight.w700,
                              fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          s.isAr
                              ? 'سترى هنا تنبيهاتك عند توفّرها'
                              : 'Your alerts will appear here',
                          style: const TextStyle(
                              color: AppPalette.textTertiary,
                              fontSize: 11),
                        ),
                      ],
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    children: [
                      for (final entry in grouped.entries) ...[
                        _DateHeader(label: entry.key),
                        for (final n in entry.value) ...[
                          _NotificationTile(notification: n),
                          const SizedBox(height: 6),
                        ],
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final AppNotification notification;
  const _NotificationTile({required this.notification});

  IconData get _icon {
    switch (notification.type) {
      case AppNotificationType.laundryReady:
        return Icons.assignment_returned_outlined;
      case AppNotificationType.laundryDelivered:
        return Icons.check_circle_outline;
      case AppNotificationType.laundryReceived:
        return Icons.local_shipping_outlined;
      case AppNotificationType.evaluationNew:
        return Icons.rate_review_outlined;
      case AppNotificationType.deductionNew:
        return Icons.money_off_outlined;
      case AppNotificationType.rosterPublished:
        return Icons.calendar_today_outlined;
      case AppNotificationType.generic:
        return Icons.notifications_outlined;
    }
  }

  Color get _color {
    switch (notification.type) {
      case AppNotificationType.laundryReady:
        return AppColors.success;
      case AppNotificationType.laundryDelivered:
        return AppColors.success;
      case AppNotificationType.laundryReceived:
        return AppColors.teal;
      case AppNotificationType.evaluationNew:
        return AppColors.purple;
      case AppNotificationType.deductionNew:
        return AppColors.danger;
      case AppNotificationType.rosterPublished:
        return AppColors.info;
      case AppNotificationType.generic:
        return AppColors.brand;
    }
  }

  /// 🆕 Session 10: ينقل المستخدم إلى الشاشة المناسبة بناءً على linkRef
  /// التنسيق: "kind:id" (مثل "submission:abc-123")
  void _navigate(BuildContext context) {
    final ref = notification.linkRef;
    if (ref == null || !ref.contains(':')) {
      // أغلق Bottom Sheet فقط
      Navigator.of(context).pop();
      return;
    }
    final parts = ref.split(':');
    final kind = parts[0];
    final id = parts.sublist(1).join(':');

    Navigator.of(context).pop(); // أغلق لوحة الإشعارات أوّلاً

    switch (kind) {
      case 'submission':
        _openSubmission(context, id);
        break;
      // ✋ مكان لإضافة أنواع أخرى لاحقاً (laundry, evaluation, ...)
      default:
        // غير مدعوم — لا تنقل
        break;
    }
  }

  void _openSubmission(BuildContext context, String submissionId) {
    final repo = MockRepository();
    final sub = repo.formSubmissions.firstWhere(
      (s) => s.id == submissionId,
      orElse: () => FormSubmission(id: '', templateId: ''),
    );
    if (sub.id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.red,
        content: Text(AppStrings.of(context).isAr
            ? 'الطلب غير موجود'
            : 'Submission not found'),
      ));
      return;
    }
    // إن كان الطلب بانتظار موافقة، انقل لشاشة "موافقاتي"
    if (sub.status == FormSubmissionStatus.submitted ||
        sub.status == FormSubmissionStatus.inReview) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const FormsSubmissionsReportScreen(),
      ));
    } else {
      // فتح شاشة الإدارة (إن كان لديه صلاحيّة سيراها كاملة)
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const AdminFormsScreen(),
      ));
    }
  }

  String _timeAgo(DateTime t, bool isAr) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return isAr ? 'الآن' : 'now';
    if (diff.inMinutes < 60) {
      return isAr ? 'منذ ${diff.inMinutes} د' : '${diff.inMinutes}m ago';
    }
    if (diff.inHours < 24) {
      return isAr ? 'منذ ${diff.inHours} س' : '${diff.inHours}h ago';
    }
    if (diff.inDays < 7) {
      return isAr ? 'منذ ${diff.inDays} يوم' : '${diff.inDays}d ago';
    }
    return '${t.day}/${t.month}';
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final unread = !notification.isRead;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          MockRepository().markNotificationAsRead(notification.id);
          _navigate(context);
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: unread
                ? _color.withOpacity(0.06)
                : AppPalette.input.withOpacity(0.50),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: unread
                    ? _color.withOpacity(0.30)
                    : AppPalette.border,
                width: unread ? 1.2 : 0.8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _color.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(_icon, color: _color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: TextStyle(
                                fontWeight: unread
                                    ? FontWeight.w900
                                    : FontWeight.w700,
                                fontSize: 13,
                                color: AppPalette.text),
                          ),
                        ),
                        if (unread)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFFDC2626),
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      notification.body,
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppPalette.textSecondary,
                          height: 1.4),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _timeAgo(notification.createdAt, s.isAr),
                      style: const TextStyle(
                          fontSize: 10,
                          color: AppPalette.textTertiary,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// 🆕 Session 10: مكوّنات مساعدة للفلتر والتجميع
// ============================================================

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AppColors.brand : Colors.grey.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.brand : Colors.grey.withOpacity(0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : Colors.grey[800],
          ),
        ),
      ),
    );
  }
}

class _DateHeader extends StatelessWidget {
  final String label;
  const _DateHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[700],
              fontWeight: FontWeight.w900,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 1,
              color: Colors.grey.withOpacity(0.2),
            ),
          ),
        ],
      ),
    );
  }
}
