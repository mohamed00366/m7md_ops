import 'package:flutter/material.dart';

import '../core/l10n/app_strings.dart';
import '../core/services/network_status_service.dart';

/// 🌐 بانِر يَظهَر عِندَما تَكون الشَبَكة مَفصولة
///
/// عَلى الويب: يَظهَر تِلقائيّاً عِند فَقد الاتِّصال. يَختَفي عِند العَودة.
/// عَلى المِنَصّات الأُخرى: لا يَظهَر أَبَداً (الخِدمة تَبقى online).
class NetworkStatusBanner extends StatefulWidget {
  const NetworkStatusBanner({super.key});

  @override
  State<NetworkStatusBanner> createState() => _NetworkStatusBannerState();
}

class _NetworkStatusBannerState extends State<NetworkStatusBanner> {
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: NetworkStatusService.instance,
      builder: (context, _) {
        final online = NetworkStatusService.instance.isOnline;
        final isAr = AppStrings.of(context).isAr;
        if (online) return const SizedBox.shrink();
        return Material(
          color: Colors.red.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            margin: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red.withValues(alpha: 0.40)),
            ),
            child: Row(
              children: [
                const Icon(Icons.wifi_off, color: Colors.red, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isAr ? 'لا يُوجَد اتِّصال بِالإنتَرنِت' : 'No Internet',
                        style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.w900,
                            fontSize: 13),
                      ),
                      Text(
                        isAr
                            ? 'سَتُحفَظ التَغييرات عِند عَودة الاتِّصال'
                            : 'Changes will sync when reconnected',
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 🟢/🔴 شارة صَغيرة لِحالة الاتِّصال — مُناسِبة لِلـAppBar
class NetworkStatusChip extends StatelessWidget {
  /// لَو true يَظهَر دائِماً (حَتّى عِند online). الافتِراضيّ: يَظهَر عِند offline فَقَط.
  final bool alwaysVisible;
  const NetworkStatusChip({super.key, this.alwaysVisible = false});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: NetworkStatusService.instance,
      builder: (context, _) {
        final online = NetworkStatusService.instance.isOnline;
        if (online && !alwaysVisible) return const SizedBox.shrink();
        final isAr = AppStrings.of(context).isAr;
        final color = online ? Colors.green : Colors.red;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.20),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.50)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(online ? Icons.wifi : Icons.wifi_off,
                  size: 12, color: color),
              const SizedBox(width: 4),
              Text(
                online
                    ? (isAr ? 'مُتَّصِل' : 'Online')
                    : (isAr ? 'غَير مُتَّصِل' : 'Offline'),
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 9),
              ),
            ],
          ),
        );
      },
    );
  }
}
