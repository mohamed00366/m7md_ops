import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/l10n/app_strings.dart';
import '../core/providers/locale_provider.dart';
import '../core/theme/app_colors.dart';

/// 🌐 أَيقونة اختِيار لُغة (٣ خيارات: عَرَبيّ / English / اُردو)
///
/// تَفتَح PopupMenu عِندَ الضَغط. تُبَيِّن العَلَم وَاسم اللُغة الحاليّة.
class LanguagePicker extends StatelessWidget {
  final Color? iconColor;
  final double iconSize;
  const LanguagePicker({
    super.key,
    this.iconColor,
    this.iconSize = 22,
  });

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleProvider>();
    final current = locale.locale.languageCode;
    final flag = AppStrings.languageFlags[current] ?? '🌐';

    return PopupMenuButton<String>(
      tooltip: AppStrings.languageNames[current] ?? 'Language',
      icon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(flag, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 2),
          Icon(Icons.arrow_drop_down,
              color: iconColor ?? AppColors.gold, size: 18),
        ],
      ),
      onSelected: (code) => context.read<LocaleProvider>().setByCode(code),
      itemBuilder: (ctx) => LocaleProvider.supportedCodes.map((code) {
        final isSelected = code == current;
        return PopupMenuItem<String>(
          value: code,
          child: Row(
            children: [
              Text(
                AppStrings.languageFlags[code] ?? '🌐',
                style: const TextStyle(fontSize: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  AppStrings.languageNames[code] ?? code,
                  style: TextStyle(
                    fontWeight:
                        isSelected ? FontWeight.w900 : FontWeight.w600,
                    color: isSelected ? AppColors.brand : null,
                  ),
                ),
              ),
              if (isSelected)
                const Icon(Icons.check_circle,
                    color: AppColors.success, size: 18),
            ],
          ),
        );
      }).toList(),
    );
  }
}
