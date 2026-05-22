// =============================================================================
// 🎓 M7OnboardingTour — جَولة تَعريفيّة لِلمُستَخدِم الجَديد
// =============================================================================
// عَرض رِسائِل تَوجيهيّة خُطوة بِخُطوة لِشَرح شاشة جَديدة.
//
// الاستِخدام:
// ```dart
// M7OnboardingTour.show(context, [
//   M7TourStep(
//     titleAr: 'مَرحَباً بِك!',
//     titleEn: 'Welcome!',
//     messageAr: 'هذه شاشة المُوَظَّفين — أَدوارك تُحَدِّد ماذا تَرى',
//     messageEn: 'This is the Employees screen — your role decides what you see',
//     icon: Icons.waving_hand,
//   ),
//   M7TourStep(...),
//   M7TourStep(...),
// ]);
// ```
// =============================================================================

import 'package:flutter/material.dart';

import '../core/l10n/app_strings.dart';
import '../core/theme/app_colors.dart';

class M7TourStep {
  final String titleAr;
  final String titleEn;
  final String messageAr;
  final String messageEn;
  final IconData icon;
  final Color? color;

  const M7TourStep({
    required this.titleAr,
    required this.titleEn,
    required this.messageAr,
    required this.messageEn,
    this.icon = Icons.info_outline,
    this.color,
  });
}

class M7OnboardingTour {
  M7OnboardingTour._();

  /// عَرض جَولة تَعريفيّة في شَكل dialog مُتَتالي
  static Future<void> show(
    BuildContext context,
    List<M7TourStep> steps, {
    String? tourKey, // لِلتَذَكُّر — لا يُعرَض مَرَّتَين (TODO: SharedPreferences)
  }) async {
    if (steps.isEmpty) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TourDialog(steps: steps),
    );
  }
}

class _TourDialog extends StatefulWidget {
  final List<M7TourStep> steps;
  const _TourDialog({required this.steps});

  @override
  State<_TourDialog> createState() => _TourDialogState();
}

class _TourDialogState extends State<_TourDialog> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final step = widget.steps[_index];
    final color = step.color ?? AppColors.brand;
    final isLast = _index == widget.steps.length - 1;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        width: 380,
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // أَيقونة دائِريّة كَبيرة
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(step.icon, size: 40, color: color),
            ),
            const SizedBox(height: 20),
            // العُنوان
            Text(
              isAr ? step.titleAr : step.titleEn,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            // الرِسالة
            Text(
              isAr ? step.messageAr : step.messageEn,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 24),
            // مُؤَشِّر التَقَدُّم (dots)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(widget.steps.length, (i) {
                final active = i == _index;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 20 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: active
                        ? color
                        : Colors.grey.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
            const SizedBox(height: 20),
            // الأَزرار
            Row(
              children: [
                if (_index > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _index--),
                      child: Text(isAr ? 'السابِق' : 'Back'),
                    ),
                  ),
                if (_index > 0) const SizedBox(width: 10),
                if (!isLast)
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(isAr ? 'تَخَطّي' : 'Skip'),
                  ),
                if (!isLast) const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      if (isLast) {
                        Navigator.of(context).pop();
                      } else {
                        setState(() => _index++);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(isLast
                        ? (isAr ? 'تَمام، فَهِمت!' : 'Got it!')
                        : (isAr ? 'التالي' : 'Next')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
