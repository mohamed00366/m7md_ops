import 'package:flutter/material.dart';

import '../core/l10n/app_strings.dart';
import '../core/services/pwa_install_service.dart';
import '../core/theme/app_colors.dart';

/// 📲 بانِر دَعوة لِتَنزيل التَطبيق كـ PWA
///
/// يَظهَر فَقَط عَلى الويب وَعِندَما يَكون التَطبيق قابِلاً لِلتَنزيل
/// (المُتَصَفِّح يُطلِق حَدَث `beforeinstallprompt`).
class PwaInstallBanner extends StatefulWidget {
  const PwaInstallBanner({super.key});

  @override
  State<PwaInstallBanner> createState() => _PwaInstallBannerState();
}

class _PwaInstallBannerState extends State<PwaInstallBanner> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: PwaInstallService.instance,
      builder: (context, _) {
        final isAr = AppStrings.of(context).isAr;
        if (!PwaInstallService.instance.canInstall) {
          return const SizedBox.shrink();
        }
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.brand.withOpacity(0.18),
                AppColors.gold.withOpacity(0.10),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.gold.withOpacity(0.40)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.gold.withOpacity(0.20),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.install_mobile,
                    color: AppColors.brand, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isAr
                          ? '📲 ثَبِّت التَطبيق عَلى جِهازَك'
                          : '📲 Install the app',
                      style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          color: AppColors.brand),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isAr
                          ? 'وُصول أَسرَع بِدون مُتَصَفِّح + يَعمَل بِأَنماط الجَوّال'
                          : 'Faster access + mobile-style experience',
                      style: const TextStyle(
                          fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () async {
                  await PwaInstallService.instance.promptInstall();
                },
                icon: const Icon(Icons.download, size: 16),
                label: Text(isAr ? 'تَنزيل' : 'Install'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                ),
              ),
              IconButton(
                tooltip: isAr ? 'إخفاء' : 'Dismiss',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => setState(() => _dismissed = true),
              ),
            ],
          ),
        );
      },
    );
  }
}
