import 'package:flutter/material.dart';

import '../core/l10n/ar_to_ur_dictionary.dart' as ar2ur;
import '../core/theme/app_colors.dart';

/// 🔧 شَريط أَدَوات مُوَحَّد لِشاشات القَوائِم
///
/// كُلّ زِرّ اختِياريّ — مَرِّر الأَزرار التي تَحتاجها فَقَط.
///
/// **الاستِخدام:**
/// ```dart
/// M7Toolbar(
///   busy: _busy,
///   actions: [
///     M7ToolAction(icon: Icons.file_download, label: 'القالَب', color: AppColors.info, onTap: ...),
///     M7ToolAction(icon: Icons.upload_file, label: 'استيراد', color: AppColors.brand, onTap: ...),
///     M7ToolAction(icon: Icons.file_open, label: 'تَصدير', color: AppColors.success, onTap: ...),
///   ],
/// )
/// ```
class M7Toolbar extends StatelessWidget {
  final List<M7ToolAction> actions;
  final bool busy;
  const M7Toolbar({super.key, required this.actions, this.busy = false});

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return const SizedBox(
          height: 32, child: Center(child: LinearProgressIndicator()));
    }
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: actions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) => _ToolButton(action: actions[i]),
      ),
    );
  }
}

class M7ToolAction {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const M7ToolAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
}

class _ToolButton extends StatelessWidget {
  final M7ToolAction action;
  const _ToolButton({required this.action});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: action.color.withOpacity(0.10),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: action.color.withOpacity(0.30)),
          ),
          child: Row(
            children: [
              Icon(action.icon, color: action.color, size: 14),
              const SizedBox(width: 6),
              Text(action.label,
                  style: TextStyle(
                      color: action.color,
                      fontWeight: FontWeight.w800,
                      fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 🎯 شارة فِلتَر قابِلة لِلضَغط — بِعَدّاد + لَون
class M7FilterPill extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const M7FilterPill({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? color : color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.50)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    color: selected ? Colors.white : color,
                    fontWeight: FontWeight.w800,
                    fontSize: 11)),
            const SizedBox(width: 4),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white.withOpacity(0.25)
                    : color.withOpacity(0.20),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('$count',
                  style: TextStyle(
                      color: selected ? Colors.white : color,
                      fontWeight: FontWeight.w900,
                      fontSize: 10,
                      fontFamily: 'monospace')),
            ),
          ],
        ),
      ),
    );
  }
}

/// 💡 مُساعِد لِبِناء قائِمة أَدَوات الـ Import/Export/Template القياسيّة
class M7StandardActions {
  static List<M7ToolAction> ioActions({
    required bool isAr,
    required VoidCallback onTemplate,
    required VoidCallback onImport,
    required VoidCallback onExport,
  }) =>
      [
        M7ToolAction(
          icon: Icons.file_download,
          label: isAr ? ar2ur.tr('تَنزيل القالَب') : 'Template',
          color: AppColors.info,
          onTap: onTemplate,
        ),
        M7ToolAction(
          icon: Icons.upload_file,
          label: isAr ? ar2ur.tr('استيراد') : 'Import',
          color: AppColors.brand,
          onTap: onImport,
        ),
        M7ToolAction(
          icon: Icons.file_open,
          label: isAr ? ar2ur.tr('تَصدير Excel') : 'Export Excel',
          color: AppColors.success,
          onTap: onExport,
        ),
      ];
}
