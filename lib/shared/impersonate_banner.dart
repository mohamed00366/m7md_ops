import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/l10n/app_strings.dart';
import '../core/providers/auth_provider.dart';

/// 🚨 شريط أحمر يظهر أعلى التطبيق عند تشغيل وضع "العرض كحساب"
///
/// يُغلَّف هذا الـ widget حول كامل التطبيق في `main.dart` بحيث يظهر
/// الشريط على كلّ الشاشات تلقائياً عند تفعيل Impersonate.
class ImpersonateBanner extends StatelessWidget {
  final Widget child;
  const ImpersonateBanner({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (_, auth, __) {
        if (!auth.isImpersonating) return child;
        final s = AppStrings.of(context);
        return Column(
          children: [
            SafeArea(
              bottom: false,
              child: Material(
                color: const Color(0xFFDC2626), // red-600
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.theater_comedy_outlined,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.isAr
                                  ? 'تعرض كـ ${auth.impersonatedAs}'
                                  : 'Viewing as ${auth.impersonatedAs}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              s.isAr
                                  ? 'الحساب الأصليّ: ${auth.realIdentity}'
                                  : 'Original: ${auth.realIdentity}',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.85),
                                fontSize: 10,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      // 🆕 زِرّ مُستَقِلّ بِـInkWell مُباشِر — يَخرُج فَوراً بِدون نافِذة تَأكيد
                      Material(
                        color: Colors.white.withOpacity(0.20),
                        borderRadius: BorderRadius.circular(6),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () => _exitImmediately(context, auth),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.exit_to_app,
                                    color: Colors.white, size: 14),
                                const SizedBox(width: 4),
                                Text(
                                  s.isAr ? 'خروج' : 'Exit',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(child: child),
          ],
        );
      },
    );
  }

  /// 🆕 خُروج فَوريّ بِدون نافِذة تَأكيد — لِأَنّ المُحاكاة لِلتَجرِبة فَقَط
  /// (ليست لِتَنفيذ إجراءات مالِيّة) وَالمُستَخدِم سَيَعود لِنَفسه.
  void _exitImmediately(BuildContext context, AuthProvider auth) {
    final s = AppStrings.of(context);
    final originalName = auth.realIdentity;
    auth.stopImpersonate();
    // اخرُج من أَيّ صَفحة فَرعيّة وَارجِع لِلجَذر — لِأَنّ الصَفحة الحاليّة
    // قَد تَكون شاشة لا يَملِك المُستَخدِم الأَصليّ صَلاحيّة رؤيَتها
    Navigator.of(context).popUntil((r) => r.isFirst);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF16A34A), // green-600
        duration: const Duration(seconds: 2),
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Text(
              s.isAr
                  ? '✓ عُدتَ إلى $originalName'
                  : '✓ Returned to $originalName',
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
