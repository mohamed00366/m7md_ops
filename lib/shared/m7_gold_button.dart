// =============================================================================
// 🥇 M7GoldButton — زِرّ CTA مُمَيَّز بِلَون البراند الذَهَبيّ
// =============================================================================
// **مَتى أَستَخدِمه؟**
//   • CTAs نادِرة لكِن مُهِمّة جِدّاً (ابدَأ، تَأكيد نِهائيّ، نَشر التَطبيق)
//   • لِفَصلها بَصَريّاً عَن الـ Primary buttons (التي هي أَسوَد)
//
// **متى لا أَستَخدِمه؟**
//   • أَزرار الـForms العاديّة (حِفظ، إرسال) → استَخدِم ElevatedButton عاديّ
//   • Destructive actions (حَذف) → استَخدِم لَون danger
//
// **القاعِدة:** زِرّ ذَهَبيّ واحِد فَقَط لِكُلّ شاشة. لَو في شاشة 3 ذَهَبيّ ⇒ لا
// يُوجَد تَمَيُّز فِعليّ.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/theme/app_colors.dart';

class M7GoldButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget? icon;
  final String label;
  final bool loading;
  final EdgeInsetsGeometry padding;
  final bool isFullWidth;

  const M7GoldButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.loading = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
    this.isFullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveOnPressed = loading ? null : onPressed;

    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: effectiveOnPressed,
        borderRadius: BorderRadius.circular(12),
        splashColor: Colors.white.withValues(alpha: 0.15),
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.gold, AppColors.goldLight],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            // ظِلّ ذَهَبيّ خَفيف لِلَفت الانتِباه (فَقَط في light)
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: AppColors.gold.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: Padding(
            padding: padding,
            child: Row(
              mainAxisSize:
                  isFullWidth ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (loading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF1A1A1A),
                    ),
                  )
                else if (icon != null) ...[
                  IconTheme(
                    data: const IconThemeData(
                        color: Color(0xFF1A1A1A), size: 18),
                    child: icon!,
                  ),
                  const SizedBox(width: 8),
                ],
                if (!loading)
                  Text(
                    label,
                    style: GoogleFonts.cairo(
                      color: const Color(0xFF1A1A1A), // brand black
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    return isFullWidth ? SizedBox(width: double.infinity, child: button) : button;
  }
}
