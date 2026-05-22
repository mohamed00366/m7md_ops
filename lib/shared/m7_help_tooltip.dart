// =============================================================================
// 💡 M7HelpTooltip — أَيقونة مُساعَدة مَع tooltip لِلحُقول المُعَقَّدة
// =============================================================================
// مَثَلاً بِجانِب حَقل "WASL VIP UID" يَشرَح ما هُوَ وَلِماذا يُطلَب.
//
// الاستِخدام:
// ```dart
// Row(children: [
//   Text('WASL VIP UID'),
//   M7HelpTooltip(
//     messageAr: 'رَقم تَسجيل السائِق في نِظام WASL VIP لِشَركات النَقل',
//     messageEn: 'Driver registration number in WASL VIP system',
//   ),
// ])
// ```
// =============================================================================

import 'package:flutter/material.dart';

import '../core/l10n/app_strings.dart';
import '../core/theme/app_colors.dart';

class M7HelpTooltip extends StatelessWidget {
  final String messageAr;
  final String messageEn;
  final double size;
  final Color? color;
  final IconData icon;

  const M7HelpTooltip({
    super.key,
    required this.messageAr,
    required this.messageEn,
    this.size = 16,
    this.color,
    this.icon = Icons.help_outline,
  });

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: isAr ? messageAr : messageEn,
        triggerMode: TooltipTriggerMode.tap,
        showDuration: const Duration(seconds: 8),
        textStyle: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          height: 1.4,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          icon,
          size: size,
          color: color ?? AppColors.info.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}

/// 📋 M7HelpInfoCard — بِطاقة شَرح أَكبَر (لِبِداية شاشة جَديدة)
///
/// تَعرِض رِسالة تَوجيهيّة في أَعلى الشاشة، تَختَفي بَعد قِراءَتها.
class M7HelpInfoCard extends StatefulWidget {
  final String messageAr;
  final String messageEn;
  final String? titleAr;
  final String? titleEn;
  final IconData icon;
  final Color color;
  final String? rememberKey; // إذا مُمَرَّر، يَتَذَكَّر الإخفاء (TODO)

  const M7HelpInfoCard({
    super.key,
    required this.messageAr,
    required this.messageEn,
    this.titleAr,
    this.titleEn,
    this.icon = Icons.lightbulb_outline,
    this.color = AppColors.info,
    this.rememberKey,
  });

  @override
  State<M7HelpInfoCard> createState() => _M7HelpInfoCardState();
}

class _M7HelpInfoCardState extends State<M7HelpInfoCard> {
  bool _hidden = false;

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();
    final isAr = AppStrings.of(context).isAr;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: widget.color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(widget.icon, color: widget.color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.titleAr != null || widget.titleEn != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      isAr ? (widget.titleAr ?? '') : (widget.titleEn ?? ''),
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        color: widget.color,
                      ),
                    ),
                  ),
                Text(
                  isAr ? widget.messageAr : widget.messageEn,
                  style: const TextStyle(fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            icon: const Icon(Icons.close, size: 16),
            tooltip: isAr ? 'إخفاء' : 'Dismiss',
            onPressed: () => setState(() => _hidden = true),
          ),
        ],
      ),
    );
  }
}
