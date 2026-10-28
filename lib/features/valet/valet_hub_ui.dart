import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'valet_admin.dart';
import 'valet_ui.dart';

/// Shared look of the "Valet app" section pages (black & white): page head, KPI row (first one dark),
/// quick filter chips, view settings (cards / table / compact, cards per row, card size, grouping,
/// visible data) saved per page on this device, and a responsive card grid.

const _ink = Color(0xFF0B0C0E);
const _line = Color(0xFFE2E8F0);
const _muted = Color(0xFF64748B);

/// Page head: title + subtitle on one side, actions on the other.
class HubHead extends StatelessWidget {
  const HubHead({super.key, required this.title, this.subtitle, this.actions = const []});
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.end,
          runSpacing: 10,
          spacing: 12,
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              if (subtitle != null) Text(subtitle!, style: const TextStyle(color: _muted, fontSize: 13)),
            ]),
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: actions),
          ],
        ),
      );
}

/// Search box of the head.
class HubSearch extends StatelessWidget {
  const HubSearch({super.key, required this.hint, required this.onChanged, this.width = 280});
  final String hint;
  final ValueChanged<String> onChanged;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        height: 40,
        child: TextField(
          onChanged: onChanged,
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            prefixIcon: const Icon(Icons.search, size: 20),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _line)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _line)),
          ),
        ),
      );
}

/// Black (main) or outlined button of the head.
class HubButton extends StatelessWidget {
  const HubButton({super.key, required this.label, required this.icon, required this.onPressed, this.primary = false, this.badge});
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final child = Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 18),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      if (badge != null) ...[
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
          decoration: BoxDecoration(color: primary ? Colors.white24 : const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(99)),
          child: Text(badge!, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
        ),
      ],
    ]);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    return SizedBox(
      height: 40,
      child: primary
          ? FilledButton(style: FilledButton.styleFrom(backgroundColor: _ink, foregroundColor: Colors.white, shape: shape), onPressed: onPressed, child: child)
          : OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: _ink, backgroundColor: Colors.white, side: const BorderSide(color: _line), shape: shape),
              onPressed: onPressed,
              child: child),
    );
  }
}

class HubKpi {
  const HubKpi(this.icon, this.value, this.label, {this.note});
  final IconData icon;
  final String value;
  final String label;
  final String? note;
}

/// Row of KPI tiles (the first one is black).
class HubKpis extends StatelessWidget {
  const HubKpis(this.items, {super.key});
  final List<HubKpi> items;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        child: LayoutBuilder(builder: (context, c) {
          final n = items.length;
          final per = c.maxWidth >= 1100 ? n : (c.maxWidth >= 700 ? 3 : 2);
          final w = (c.maxWidth - 12 * (per - 1)) / per;
          return Wrap(spacing: 12, runSpacing: 12, children: [
            for (var i = 0; i < n; i++) SizedBox(width: w, child: _tile(items[i], i == 0)),
          ]);
        }),
      );

  Widget _tile(HubKpi k, bool dark) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: dark ? _ink : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: dark ? _ink : _line),
        ),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: dark ? const Color(0xFF1F2329) : const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(12)),
            child: Icon(k.icon, size: 20, color: dark ? Colors.white : _ink),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(k.value, style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: dark ? Colors.white : _ink, height: 1.1)),
              ),
              Text(k.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: dark ? const Color(0xFF94A3B8) : _muted)),
            ]),
          ),
          if (k.note != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(99)),
              child: Text(k.note!, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF059669))),
            ),
        ]),
      );
}

/// Quick filters: (key, label, count).
class HubChips extends StatelessWidget {
  const HubChips({super.key, required this.items, required this.value, required this.onChanged, this.trailing = const []});
  final List<(String, String, int?)> items;
  final String value;
  final ValueChanged<String> onChanged;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        child: Row(children: [
          Expanded(
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (k, l, n) in items) hubChip(l, n, k == value, () => onChanged(k)),
            ]),
          ),
          ...trailing,
        ]),
      );
}

Widget hubChip(String label, int? count, bool on, VoidCallback onTap) => InkWell(
      borderRadius: BorderRadius.circular(99),
      onTap: onTap,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: on ? _ink : Colors.white,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: on ? _ink : _line),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: on ? Colors.white : const Color(0xFF334155))),
          if (count != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7),
              decoration: BoxDecoration(color: on ? const Color(0xFF2A2F37) : const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(99)),
              child: Text('$count', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: on ? const Color(0xFFE5E7EB) : const Color(0xFF475569))),
            ),
          ],
        ]),
      ),
    );

/// White card of the section.
class HubCard extends StatelessWidget {
  const HubCard({super.key, required this.child, this.onTap, this.strong = false, this.padding = const EdgeInsets.all(15)});
  final Widget child;
  final VoidCallback? onTap;
  final bool strong;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: strong ? _ink : _line, width: strong ? 1.5 : 1)),
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
      );
}

/// Small status pill: kinds dark / ok / bad / warn / mut / info.
Widget hubPill(String text, {String kind = 'mut', bool pulse = false}) {
  final (bg, fg) = switch (kind) {
    'dark' => (_ink, Colors.white),
    'ok' => (const Color(0xFFECFDF5), const Color(0xFF047857)),
    'bad' => (const Color(0xFFFEF2F2), const Color(0xFFB91C1C)),
    'warn' => (const Color(0xFFFFF7ED), const Color(0xFFC2410C)),
    'info' => (const Color(0xFFEFF6FF), const Color(0xFF1D4ED8)),
    _ => (const Color(0xFFF1F5F9), const Color(0xFF475569)),
  };
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (pulse) ...[
        Container(width: 7, height: 7, decoration: const BoxDecoration(color: Color(0xFF4ADE80), shape: BoxShape.circle)),
        const SizedBox(width: 5),
      ],
      Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: fg)),
    ]),
  );
}

/// Grey tag (or orange when [missing]).
Widget hubTag(String text, {IconData? icon, bool missing = false}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: missing ? const Color(0xFFFFF7ED) : const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 13, color: missing ? const Color(0xFFC2410C) : const Color(0xFF334155)), const SizedBox(width: 4)],
        Flexible(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: missing ? const Color(0xFFC2410C) : const Color(0xFF334155))),
        ),
      ]),
    );

/// Small outlined action of a card.
Widget hubAction(String label, VoidCallback? onTap, {Color? color}) => InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8), border: Border.all(color: _line)),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color ?? const Color(0xFF475569))),
      ),
    );

/// Number + label (card stats).
Widget hubStat(String value, String label, {Color? color}) => Column(mainAxisSize: MainAxisSize.min, children: [
      Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color ?? _ink)),
      Text(label, style: const TextStyle(fontSize: 11, color: _muted)),
    ]);

/// Thin progress bar.
Widget hubBar(double v) => ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LinearProgressIndicator(value: v.clamp(0, 1).toDouble(), minHeight: 5, backgroundColor: const Color(0xFFF1F5F9), color: _ink),
    );

// ---------------------------------------------------------------- view settings

/// View settings of one page, saved on this device.
class HubView {
  HubView(this.page, {this.mode = 'cards', this.cols = 0, this.size = 'm', this.group = '', Set<String>? fields, this.hideOff = false})
      : fields = fields ?? <String>{};
  final String page;
  String mode; // cards | table | compact
  int cols; // 0 = auto
  String size; // s | m | l
  String group;
  Set<String> fields;
  bool hideOff;

  bool show(String f) => fields.contains(f);

  static String _k(String page) => 'vv_hub_view_$page';

  /// Loads the saved settings, or [def] when none.
  static Future<HubView> load(HubView def) async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getStringList(_k(def.page));
      if (s == null || s.length < 6) return def;
      return HubView(def.page,
          mode: s[0], cols: int.tryParse(s[1]) ?? 0, size: s[2], group: s[3], fields: s[4].isEmpty ? <String>{} : s[4].split(',').toSet(), hideOff: s[5] == '1');
    } catch (_) {
      return def;
    }
  }

  Future<void> save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_k(page), [mode, '$cols', size, group, fields.join(','), hideOff ? '1' : '0']);
    } catch (_) {}
  }

  HubView copy() => HubView(page, mode: mode, cols: cols, size: size, group: group, fields: {...fields}, hideOff: hideOff);

  /// Card width for the grid (auto: by size).
  double minCard() => switch (size) { 's' => 230, 'l' => 380, _ => 290 };
}

/// "View" dialog. [fields] = (key, label) of data the cards can show; [groups] = (key, label) incl. '' = none.
Future<HubView?> showHubView(
  BuildContext context,
  HubView v,
  HubView defaults, {
  List<(String, String)> fields = const [],
  List<(String, String)> groups = const [],
  bool modes = true,
  String? hideOffLabel,
}) {
  var w = v.copy();
  return showDialog<HubView>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      Widget seg<T>(List<(T, String)> opts, T value, ValueChanged<T> on) => SegmentedButton<T>(
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor: _ink,
              selectedForegroundColor: Colors.white,
              visualDensity: VisualDensity.compact,
            ),
            segments: [for (final (k, l) in opts) ButtonSegment<T>(value: k, label: Text(l))],
            selected: {value},
            onSelectionChanged: (s) => set(() => on(s.first)),
          );
      Widget label(String t) => Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 6),
            child: Text(t, style: const TextStyle(color: _muted, fontWeight: FontWeight.w700, fontSize: 12.5)),
          );
      return AlertDialog(
        title: Row(children: [
          const Icon(Icons.tune_rounded),
          const SizedBox(width: 8),
          Text(tx(ctx, 'التَحَكُّم في العَرض', 'View')),
          const Spacer(),
          Text(tx(ctx, 'يِتحِفِظ عَلى الجِهاز دَه', 'Saved on this device'), style: const TextStyle(fontSize: 12, color: _muted)),
        ]),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              if (modes) ...[
                label(tx(ctx, 'شَكل العَرض', 'Layout')),
                seg<String>([('cards', tx(ctx, 'كُروت', 'Cards')), ('table', tx(ctx, 'جَدوَل', 'Table')), ('compact', tx(ctx, 'مَضغوط', 'Compact'))], w.mode,
                    (x) => w.mode = x),
              ],
              if (w.mode == 'cards') ...[
                label(tx(ctx, 'عَدَد الكُروت في الصَفّ', 'Cards per row')),
                seg<int>([(2, '2'), (3, '3'), (4, '4'), (5, '5'), (0, tx(ctx, 'تِلقائيّ', 'Auto'))], w.cols, (x) => w.cols = x),
                label(tx(ctx, 'حَجم الكارت', 'Card size')),
                seg<String>([('s', tx(ctx, 'صُغَيَّر', 'Small')), ('m', tx(ctx, 'مُتَوَسِّط', 'Medium')), ('l', tx(ctx, 'كَبير', 'Large'))], w.size, (x) => w.size = x),
              ],
              if (groups.isNotEmpty) ...[
                label(tx(ctx, 'تَجميع', 'Group by')),
                seg<String>(groups, w.group, (x) => w.group = x),
              ],
              if (fields.isNotEmpty) ...[
                label(tx(ctx, 'البَيانات الظاهِرة', 'Visible data')),
                for (final (k, l) in fields)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    activeColor: _ink,
                    title: Text(l),
                    value: w.fields.contains(k),
                    onChanged: (on) => set(() => on == true ? w.fields.add(k) : w.fields.remove(k)),
                  ),
              ],
              if (hideOffLabel != null)
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeTrackColor: _ink,
                  title: Text(hideOffLabel),
                  value: w.hideOff,
                  onChanged: (x) => set(() => w.hideOff = x),
                ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => set(() => w = defaults.copy()), child: Text(tx(ctx, 'رُجوع لِلافتِراضيّ', 'Reset'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _ink),
            onPressed: () async {
              await w.save();
              if (ctx.mounted) Navigator.pop(ctx, w);
            },
            child: Text(tx(ctx, 'تَطبيق', 'Apply')),
          ),
        ],
      );
    }),
  );
}

/// Responsive grid of cards following [v] (cards per row / size).
class HubGrid extends StatelessWidget {
  const HubGrid({super.key, required this.view, required this.children, this.padding = const EdgeInsets.fromLTRB(20, 14, 20, 0)});
  final HubView view;
  final List<Widget> children;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: LayoutBuilder(builder: (context, c) {
          var per = view.cols > 0 ? view.cols : (c.maxWidth / view.minCard()).floor();
          per = per.clamp(1, 6);
          if (c.maxWidth < 560) per = 1;
          final w = (c.maxWidth - 14 * (per - 1)) / per;
          return Wrap(spacing: 14, runSpacing: 14, children: [for (final ch in children) SizedBox(width: w, child: ch)]);
        }),
      );
}

/// Group title above a group of cards.
Widget hubGroupTitle(String title, String? note) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Row(children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
        if (note != null) ...[const SizedBox(width: 8), Text(note, style: const TextStyle(color: _muted, fontSize: 12.5))],
      ]),
    );

/// White panel with a table / list.
Widget hubPanel(Widget child) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: _line)),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );

/// Keeps [VJson] helpers visible to the pages importing this file.
typedef HubJson = VJson;
