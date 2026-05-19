import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/notifications_service.dart';
import '../../core/theme/app_colors.dart';
import 'my_inbox_screen.dart';

/// 🔔 أيقونة جَرَس الإشعارات لِـAppBar
///
/// تُظهِر badge بِعَدد غَير المَقروء، وتَفتَح NotificationsScreen عند الضَغط.
class NotificationBell extends StatelessWidget {
  final Color? iconColor;
  const NotificationBell({super.key, this.iconColor});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: NotificationsService.instance,
      child: Consumer<NotificationsService>(
        builder: (ctx, svc, _) {
          final count = svc.unreadCount;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                tooltip: 'الإشعارات',
                icon: Icon(
                  count > 0
                      ? Icons.notifications_active
                      : Icons.notifications_outlined,
                  size: 20,
                  color: iconColor,
                ),
                onPressed: () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const MyInboxScreen(),
                  ));
                },
              ),
              if (count > 0)
                Positioned(
                  right: 4,
                  top: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.danger,
                      borderRadius: BorderRadius.circular(10),
                      border:
                          Border.all(color: Colors.white, width: 1.5),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 16,
                    ),
                    child: Text(
                      count > 99 ? '99+' : '$count',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
