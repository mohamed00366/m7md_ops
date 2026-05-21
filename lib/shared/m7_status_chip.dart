import 'package:flutter/material.dart';

import '../core/l10n/app_strings.dart';
import '../core/l10n/ar_to_ur_dictionary.dart' as ar2ur;
import '../core/theme/app_colors.dart';
import '../models/enums.dart';

/// Unified status chip for all entities.
/// Shows: Active / Inactive / Maintenance / Vacation.
class M7StatusChip extends StatelessWidget {
  final EntityStatus status;
  final bool dense;
  const M7StatusChip({super.key, required this.status, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final (color, icon, label) = _resolve(status, isAr);
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: dense ? 6 : 8, vertical: dense ? 2 : 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: dense ? 10 : 12),
          SizedBox(width: dense ? 3 : 4),
          Text(label,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: dense ? 9 : 10)),
        ],
      ),
    );
  }

  static (Color, IconData, String) _resolve(EntityStatus status, bool isAr) {
    switch (status) {
      case EntityStatus.active:
        return (AppColors.success, Icons.check_circle, isAr ? ar2ur.tr('Active') : 'Active');
      case EntityStatus.inactive:
        return (Colors.red, Icons.cancel, isAr ? ar2ur.tr('Inactive') : 'Inactive');
      case EntityStatus.maintenance:
        return (Colors.orange, Icons.build_circle, isAr ? ar2ur.tr('Maintenance') : 'Maintenance');
      case EntityStatus.vacation:
        return (Colors.teal, Icons.beach_access, isAr ? ar2ur.tr('On Vacation') : 'On Vacation');
    }
  }
}
