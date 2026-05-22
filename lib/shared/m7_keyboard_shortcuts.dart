// =============================================================================
// ⌨ M7KeyboardShortcuts — اختِصارات لَوحة المَفاتيح العامّة
// =============================================================================
// اِستَخدِم `M7KeyboardShortcuts` لِلِفّ شاشة المُديرين/المُحاسِبين بِها:
//   Ctrl+K → فَتح Global Search
//   Ctrl+S → حِفظ (يَطلُب callback)
//   Ctrl+/ → إظهار قائِمة الاختِصارات
//   Esc    → عَودة لِلسابِق
//   F5     → تَحديث
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/l10n/app_strings.dart';
import '../core/theme/app_colors.dart';

/// يَلُفّ أَيّ widget بِـshortcuts عامّة
class M7KeyboardShortcuts extends StatelessWidget {
  final Widget child;
  final VoidCallback? onSearch;   // Ctrl+K
  final VoidCallback? onSave;     // Ctrl+S
  final VoidCallback? onRefresh;  // F5
  final VoidCallback? onEscape;   // Esc

  const M7KeyboardShortcuts({
    super.key,
    required this.child,
    this.onSearch,
    this.onSave,
    this.onRefresh,
    this.onEscape,
  });

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        // Ctrl+K → search
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () {
          if (onSearch != null) onSearch!();
        },
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () {
          if (onSearch != null) onSearch!();
        },
        // Ctrl+S → save
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          if (onSave != null) onSave!();
        },
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () {
          if (onSave != null) onSave!();
        },
        // Ctrl+/ → help
        const SingleActivator(LogicalKeyboardKey.slash, control: true): () {
          _showShortcutsHelp(context);
        },
        // F5 → refresh
        const SingleActivator(LogicalKeyboardKey.f5): () {
          if (onRefresh != null) onRefresh!();
        },
        // Esc → back
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (onEscape != null) {
            onEscape!();
          } else if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        },
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}

/// مُسَهِّل ثابِت لِعَرض قائِمة الاختِصارات
void _showShortcutsHelp(BuildContext context) {
  final isAr = AppStrings.of(context).isAr;
  showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: Row(children: [
        const Icon(Icons.keyboard_alt_outlined, color: AppColors.brand),
        const SizedBox(width: 8),
        Text(isAr ? '⌨ اختِصارات لَوحة المَفاتيح' : '⌨ Keyboard Shortcuts'),
      ]),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _row('Ctrl+K', isAr ? 'بَحث عامّ' : 'Global search'),
            _row('Ctrl+S', isAr ? 'حِفظ' : 'Save'),
            _row('Ctrl+/', isAr ? 'إظهار هذه القائِمة' : 'Show this help'),
            _row('F5', isAr ? 'تَحديث' : 'Refresh'),
            _row('Esc', isAr ? 'رُجوع' : 'Back'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(isAr ? 'حَسَناً' : 'OK'),
        ),
      ],
    ),
  );
}

Widget _row(String shortcut, String description) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
          ),
          child: Text(
            shortcut,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(description, style: const TextStyle(fontSize: 13)),
        ),
      ],
    ),
  );
}

/// زِرّ بَدِيل لِفَتح مَفاتيح المُساعَدة (في AppBar)
class M7ShortcutsHelpButton extends StatelessWidget {
  const M7ShortcutsHelpButton({super.key});

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return IconButton(
      icon: const Icon(Icons.keyboard_alt_outlined, size: 18),
      tooltip: isAr ? 'اختِصارات المَفاتيح (Ctrl+/)' : 'Keyboard shortcuts (Ctrl+/)',
      onPressed: () => _showShortcutsHelp(context),
    );
  }
}
