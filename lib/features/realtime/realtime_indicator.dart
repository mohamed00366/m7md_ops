import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/realtime_sync_service.dart';
import '../../core/theme/app_colors.dart';

/// 🟢 مُؤَشِّر "مُتَزامِن حَيّ" في الـAppBar
///
/// يُظهِر النُقطة الخَضراء عند اتّصال Realtime، أَو رَماديّة عند الانقِطاع.
/// عند الضَغط يَفتَح bottom sheet بِتَفاصيل آخِر مُزامَنة.
class RealtimeIndicator extends StatelessWidget {
  const RealtimeIndicator({super.key});

  String _timeAgo(DateTime? dt, bool isAr) {
    if (dt == null) return isAr ? 'لم يَحدُث بَعد' : 'never';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 5) return isAr ? 'الآن' : 'now';
    if (diff.inMinutes < 1) {
      return isAr ? 'قَبل ${diff.inSeconds}ث' : '${diff.inSeconds}s ago';
    }
    if (diff.inHours < 1) {
      return isAr ? 'قَبل ${diff.inMinutes}د' : '${diff.inMinutes}m ago';
    }
    return isAr ? 'قَبل ${diff.inHours}س' : '${diff.inHours}h ago';
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: RealtimeSyncService.instance,
      child: Consumer<RealtimeSyncService>(
        builder: (ctx, svc, _) {
          final isConnected = svc.isConnected;
          final color = isConnected ? AppColors.success : Colors.grey;
          return Tooltip(
            message: isConnected ? 'مُتَزامِن حَيّ' : 'غَير مُتَّصِل',
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _showDetails(ctx, svc),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _BlinkingDot(color: color, blink: isConnected),
                    if (svc.eventCount > 0) ...[
                      const SizedBox(width: 4),
                      Text(
                        '${svc.eventCount}',
                        style: const TextStyle(
                          fontSize: 9,
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showDetails(BuildContext context, RealtimeSyncService svc) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardTheme.color,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final isAr = Localizations.localeOf(ctx).languageCode == 'ar';
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _BlinkingDot(
                      color: svc.isConnected
                          ? AppColors.success
                          : Colors.grey,
                      blink: svc.isConnected,
                      size: 12),
                  const SizedBox(width: 8),
                  Text(
                    svc.isConnected
                        ? (isAr ? '🟢 مُتَزامِن حَيّ' : '🟢 Live sync')
                        : (isAr ? '⚪ غَير مُتَّصِل' : '⚪ Offline'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _InfoRow(
                icon: Icons.schedule,
                label: isAr ? 'آخِر مُزامَنة' : 'Last sync',
                value: _timeAgo(svc.lastSync, isAr),
              ),
              const SizedBox(height: 8),
              _InfoRow(
                icon: Icons.bolt,
                label: isAr ? 'تَحديثات مُستَلَمة' : 'Updates received',
                value: '${svc.eventCount}',
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.info.withValues(alpha: 0.30)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        size: 16, color: AppColors.info),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isAr
                            ? 'البَيانات تُحَدَّث تلقائيّاً عند تَغييرها من أيّ جِهاز آخَر. لا تَحتاج إعادة فَتح التَطبيق.'
                            : 'Data refreshes automatically when changed from any device. No need to restart.',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 42,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.refresh),
                  label: Text(
                      isAr ? 'تَحديث الآن' : 'Refresh now'),
                  onPressed: () async {
                    await svc.refreshAll();
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BlinkingDot extends StatefulWidget {
  final Color color;
  final bool blink;
  final double size;
  const _BlinkingDot({
    required this.color,
    required this.blink,
    this.size = 8,
  });

  @override
  State<_BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<_BlinkingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    if (widget.blink) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_BlinkingDot old) {
    super.didUpdateWidget(old);
    if (widget.blink && !_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    } else if (!widget.blink && _ctrl.isAnimating) {
      _ctrl.stop();
      _ctrl.reset();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final opacity = widget.blink
            ? 0.4 + 0.6 * (1 - _ctrl.value)
            : 0.5;
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: opacity),
            shape: BoxShape.circle,
            boxShadow: widget.blink
                ? [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.5 * (1 - _ctrl.value)),
                      blurRadius: 4,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
        );
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label,
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}
