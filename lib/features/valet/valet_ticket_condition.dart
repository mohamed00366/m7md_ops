import 'package:flutter/material.dart';

import 'valet_admin.dart';
import 'valet_damage_diagram.dart';
import 'valet_ui.dart';

/// DB 329 – the car at check-in in the dashboard: the drawing with the marks (and types), each mark with its part,
/// type and photo, «no damage» confirmed, the notes (with who sees them) and the camera photos (front / back …).
class ValetTicketCondition extends StatelessWidget {
  const ValetTicketCondition({super.key, required this.t});
  final VJson t;

  @override
  Widget build(BuildContext context) {
    final marks = [for (final m in (t['damage_marks'] as List? ?? const [])) if (m is Map) Map<String, dynamic>.from(m)];
    final old = [for (final d in (t['selected_damages'] as List? ?? const [])) '$d'];
    final sel = {...old, for (final m in marks) '${m['p']}'};
    final types = {for (final m in marks) if (m['t'] != null) '${m['p']}': '${m['t']}'};
    final notes = [for (final n in (t['note_items'] as List? ?? const [])) if (n is Map) Map<String, dynamic>.from(n)];
    final photos = [for (final p in (t['photos'] as List? ?? const [])) if (p is Map) Map<String, dynamic>.from(p)];
    final noDamage = t['no_damage_confirmed'] == true;
    final edits = [for (final e in (t['edit_log'] as List? ?? const [])) if (e is Map) Map<String, dynamic>.from(e)];
    if (sel.isEmpty && notes.isEmpty && photos.isEmpty && !noDamage && edits.isEmpty) return const SizedBox.shrink();
    Widget chip(String text, Color c, {IconData? icon, VoidCallback? onTap}) => InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: c.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: c.withValues(alpha: 0.4))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[Icon(icon, size: 14, color: c), const SizedBox(width: 4)],
              Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c)),
            ]),
          ),
        );
    void open(String url) => showDialog(context: context, builder: (c) => Dialog(child: InteractiveViewer(child: Image.network(url))));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Divider(height: 22),
      Row(children: [
        Expanded(child: Text(tx(context, 'حالة العربية عند الاستلام', 'Condition at check-in'), style: const TextStyle(fontWeight: FontWeight.w800))),
        if (sel.isEmpty && noDamage) chip(tx(context, 'مفيش ضرر · متأكد', 'No damage · confirmed'), const Color(0xFF16A34A), icon: Icons.check_circle),
        if (sel.isNotEmpty) chip('${sel.length} ${tx(context, 'علامة', 'marks')}', const Color(0xFFE11D48), icon: Icons.car_crash_outlined),
      ]),
      if (sel.isNotEmpty) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: const Color(0xFFF6F7F9), borderRadius: BorderRadius.circular(12)),
          child: DamageBlueprint(selected: sel, types: types, onToggle: null),
        ),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final id in kDamagePoints.where(sel.contains))
            Builder(builder: (_) {
              final m = marks.where((x) => '${x['p']}' == id).firstOrNull;
              final ty = kDamageTypes[m?['t']];
              final ph = m?['photo'] as String?;
              return chip('$id · ${kDamagePointName[id] ?? ''}${ty == null ? '' : ' · $ty'}', const Color(0xFFE11D48),
                  icon: ph != null ? Icons.photo_camera : null, onTap: ph == null ? null : () => open(ph));
            }),
        ]),
      ],
      if (notes.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text(tx(context, 'الملاحظات', 'Notes'), style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final n in notes)
            chip('${n['text'] ?? ''}${n['visible'] == 'customer' ? '' : ' · ${tx(context, 'للموظفين', 'staff only')}'}',
                n['visible'] == 'customer' ? const Color(0xFF16A34A) : const Color(0xFF475569),
                icon: n['visible'] == 'customer' ? Icons.visibility : Icons.visibility_off),
        ]),
      ],
      if (photos.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text(tx(context, 'الصور', 'Photos'), style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final p in photos)
            InkWell(
              onTap: () => open('${p['url']}'),
              child: Stack(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network('${p['url']}', width: 120, height: 84, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox(width: 120, height: 84)),
                ),
                Positioned(
                  left: 4,
                  top: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                    child: Text('${p['side'] ?? ''}${p['auto'] == true ? ' · auto' : ''}', style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
            ),
        ]),
      ],
      if (edits.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text(tx(context, 'تعديلات بعد عمل التكت', 'Changes after the ticket was made'), style: const TextStyle(fontWeight: FontWeight.w700)),
        for (final e in edits)
          Text('${VF.dt(vTime(e['at']))} · ${e['by_name'] ?? '-'} · ${(e['fields'] as List? ?? const []).join(', ')}',
              style: const TextStyle(fontSize: 12, color: Color(0xFFB45309))),
      ],
      if (t['create_seconds'] != null || t['plate_source'] != null) ...[
        const SizedBox(height: 8),
        Text(
          [
            if (t['create_seconds'] != null) '${tx(context, 'وقت عمل التكت', 'Ticket made in')} ${t['create_seconds']} s',
            if (t['plate_source'] != null) '${tx(context, 'اللوحة', 'plate')}: ${t['plate_source']}',
            if (t['colour_source'] != null) '${tx(context, 'اللون', 'colour')}: ${t['colour_source']}',
          ].join(' · '),
          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
      ],
    ]);
  }
}
