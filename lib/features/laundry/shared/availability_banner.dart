// =============================================================================
// 🟢 شَريط حالة الكَمب بُوص — يَظهَر في رَأس شاشات المُوَظَّف
// =============================================================================
import 'package:flutter/material.dart';

import '../data/availability_service.dart';
import '../domain/models.dart';
import 'laundry_colors.dart';

class AvailabilityBanner extends StatefulWidget {
  final String campBossId;
  final String mode; // 'receive' or 'deliver'
  final VoidCallback? onTap;

  const AvailabilityBanner({
    super.key,
    required this.campBossId,
    this.mode = 'receive',
    this.onTap,
  });

  @override
  State<AvailabilityBanner> createState() => _AvailabilityBannerState();
}

class _AvailabilityBannerState extends State<AvailabilityBanner> {
  AvailabilityStatus? _status;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final status = await AvailabilityService.instance.checkAvailability(
      campBossId: widget.campBossId,
      mode: widget.mode,
    );
    if (mounted) {
      setState(() {
        _status = status;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        height: 56,
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }

    final s = _status!;
    final (color, icon, mainText, subText) = _resolveDisplay(s);

    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.40), width: 1.2),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(mainText,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: color)),
                      if (subText.isNotEmpty)
                        Text(subText,
                            style: const TextStyle(
                                fontSize: 11.5,
                                color: Colors.black87)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  onPressed: _load,
                  tooltip: 'تَحديث',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  (Color, IconData, String, String) _resolveDisplay(AvailabilityStatus s) {
    switch (s.state) {
      case AvailabilityState.open:
        return (
          LaundryColors.availOpen,
          Icons.check_circle,
          '🟢 مَفتوح لِلاستِلام الآن',
          s.closesAt != null
              ? 'يُغلَق في ${_fmtTime(s.closesAt!)}'
              : 'تَستَطيع التَسليم',
        );
      case AvailabilityState.closingSoon:
        return (
          LaundryColors.availClosingSoon,
          Icons.access_time,
          '🟡 سَيُغلَق قَريباً',
          s.closesAt != null
              ? 'يُغلَق في ${_fmtTime(s.closesAt!)} — أَسرِع!'
              : '',
        );
      case AvailabilityState.closed:
        return (
          LaundryColors.availClosed,
          Icons.lock_clock,
          '🟡 مُغلَق حاليّاً',
          s.nextOpenAt != null
              ? 'يَفتَح في ${_fmtNextOpen(s.nextOpenAt!)}'
              : '',
        );
      case AvailabilityState.holiday:
        return (
          LaundryColors.availHoliday,
          Icons.event_busy,
          '🔴 إجازة استِثنائيّة',
          s.nextOpenAt != null
              ? 'يَعود في ${_fmtDate(s.nextOpenAt!)}'
              : '',
        );
      case AvailabilityState.emergency:
        return (
          LaundryColors.availEmergency,
          Icons.warning,
          '🚨 إغلاق طارِئ',
          s.reason ?? 'يُرجى المُراجَعة لاحِقاً',
        );
    }
  }

  String _fmtTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, "0")}:${d.minute.toString().padLeft(2, "0")}';

  String _fmtDate(DateTime d) =>
      '${d.day}/${d.month}/${d.year}';

  String _fmtNextOpen(DateTime d) {
    final now = DateTime.now();
    final diff = d.difference(now);
    if (diff.inDays >= 1) {
      return '${_fmtDate(d)} الساعة ${_fmtTime(d)}';
    } else if (diff.inHours >= 1) {
      return 'بَعد ${diff.inHours} ساعة (${_fmtTime(d)})';
    } else {
      return 'بَعد ${diff.inMinutes} دَقيقة';
    }
  }
}
