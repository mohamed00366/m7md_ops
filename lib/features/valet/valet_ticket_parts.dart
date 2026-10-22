import 'package:flutter/material.dart';

import 'valet_ui.dart';

/// Printed ticket parts of a point (valet_point_settings.ticket_parts). Same keys and defaults
/// as the valet app (vip_valet lib/core/ticket_parts.dart).
const Map<String, (String, String)> kTicketItems = {
  'number': ('رَقم التَذكَرة (كَبير)', 'Ticket number (big)'),
  'code': ('كود التَذكَرة', 'Ticket code'),
  'plate': ('اللَوحة', 'Plate'),
  'plate_big': ('اللَوحة (كَبيرة في الوَسط)', 'Plate (big, centred)'),
  'color': ('اللَون', 'Colour'),
  'vehicle': ('نَوع السَيّارة', 'Vehicle type'),
  'customer': ('العَميل', 'Customer'),
  'type': ('نَوع التَذكَرة', 'Ticket type'),
  'mode': ('الطَريقة', 'Mode'),
  'card': ('الكَرت', 'Card'),
  'time_in': ('وَقت الدُخول', 'Time in'),
  'time_big': ('وَقت الدُخول (في الوَسط)', 'Time in (centred)'),
  'price': ('السِعر وَالضَريبة وَالإجماليّ', 'Price, VAT and total'),
  'qr': ('QR لِطَلَب السَيّارة', 'QR – request the car'),
  'received_by': ('استَلَمَها ____', 'Received by ____'),
  'delivered_by': ('سَلَّمَها ____', 'Delivered by ____'),
  'parking': ('المَوقِف ____', 'Parking ____'),
  'signature': ('تَوقيع العَميل ____', 'Customer signature ____'),
  'notes': ('مُلاحَظات التَذكَرة', 'Ticket notes'),
};

List<Map<String, dynamic>> defaultTicketParts() => [
      {
        'id': 'customer', 'title': 'CUSTOMER COPY', 'enabled': true, 'footer': '',
        'items': ['number', 'code', 'plate', 'color', 'vehicle', 'customer', 'type', 'mode', 'card', 'time_in', 'price', 'qr'],
      },
      {
        'id': 'office', 'title': 'OFFICE COPY', 'enabled': true, 'footer': '',
        'items': ['number', 'code', 'plate', 'color', 'vehicle', 'customer', 'type', 'mode', 'card', 'time_in', 'price'],
      },
      {'id': 'car', 'title': 'CAR TAG', 'enabled': true, 'footer': '', 'items': ['number', 'plate_big', 'time_big']},
      {'id': 'key', 'title': 'KEY TAG', 'enabled': true, 'footer': '', 'items': ['number', 'plate', 'received_by', 'delivered_by', 'parking']},
    ];

List<Map<String, dynamic>> ticketPartsOf(dynamic v) {
  if (v is! List || v.isEmpty) return defaultTicketParts();
  return [
    for (final e in v)
      if (e is Map)
        {
          'id': '${e['id'] ?? ''}',
          'title': '${e['title'] ?? ''}',
          'enabled': e['enabled'] != false,
          'footer': '${e['footer'] ?? ''}',
          'items': [for (final i in (e['items'] is List ? e['items'] as List : const [])) '$i'],
        },
  ];
}

/// Panel in the point's Features tab: switch parts on / off, edit, reorder, add up to 6 parts.
class TicketPartsPanel extends StatelessWidget {
  const TicketPartsPanel({super.key, required this.value, required this.edit, required this.onSave});

  final dynamic value;
  final bool edit;
  final Future<void> Function(List<Map<String, dynamic>>? parts) onSave;

  static const maxParts = 6;

  @override
  Widget build(BuildContext context) {
    final custom = value is List && (value as List).isNotEmpty;
    final parts = ticketPartsOf(value);
    Future<void> save(List<Map<String, dynamic>> p) => onSave(p);
    return VPanel(
      title: tx(context, 'أَجزاء التَذكَرة المَطبوعة', 'Printed ticket parts'),
      actions: [
        if (edit && custom)
          TextButton(
            onPressed: () => onSave(null),
            child: Text(tx(context, 'الافتِراضيّ', 'Reset to default')),
          ),
        if (edit && parts.length < maxParts)
          FilledButton.icon(
            icon: const Icon(Icons.add),
            label: Text(tx(context, 'جُزء جَديد', 'New part')),
            onPressed: () async {
              final p = await _editPart(context, {
                'id': 'part${DateTime.now().millisecondsSinceEpoch}',
                'title': 'PART ${parts.length + 1}',
                'enabled': true,
                'footer': '',
                'items': ['number', 'plate'],
              });
              if (p != null) await save([...parts, p]);
            },
          ),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          tx(context,
              'تُطبَع الأَجزاء المُفعَّلة بِالتَرتيب عِند إضافة كُلّ تَذكَرة في هذه النُقطة (تَطبيق 2.0.21 وَما بَعده). '
                  '${custom ? '' : 'الآن: الأَجزاء الأَربَعة الافتِراضيّة — وَكُلّ جِهاز يَختار مِنها.'}',
              'The parts switched on are printed in this order for every new ticket at this point (app 2.0.21 and later). '
                  '${custom ? '' : 'Now: the 4 default parts — each device picks among them.'}'),
          style: const TextStyle(color: VC.muted, fontSize: 12.5),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < parts.length; i++)
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
            decoration: BoxDecoration(
              border: Border.all(color: VC.muted.withValues(alpha: 0.25)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: (parts[i]['enabled'] == true ? VC.gold : VC.muted).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${parts[i]['title']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(
                    [for (final k in parts[i]['items'] as List) tx(context, kTicketItems[k]?.$1 ?? '$k', kTicketItems[k]?.$2 ?? '$k')]
                        .join(' · '),
                    style: const TextStyle(color: VC.muted, fontSize: 12),
                  ),
                ]),
              ),
              Switch(
                value: parts[i]['enabled'] == true,
                onChanged: !edit
                    ? null
                    : (v) {
                        if (!v && parts.where((p) => p['enabled'] == true).length <= 1) return;
                        final n = [...parts];
                        n[i] = {...n[i], 'enabled': v};
                        save(n);
                      },
              ),
              if (edit) ...[
                IconButton(
                  tooltip: tx(context, 'تَعديل', 'Edit'),
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: () async {
                    final p = await _editPart(context, parts[i]);
                    if (p == null) return;
                    final n = [...parts];
                    n[i] = p;
                    await save(n);
                  },
                ),
                IconButton(
                  tooltip: tx(context, 'أَعلى', 'Up'),
                  icon: const Icon(Icons.arrow_upward, size: 18),
                  onPressed: i == 0
                      ? null
                      : () {
                          final n = [...parts];
                          final t = n[i];
                          n[i] = n[i - 1];
                          n[i - 1] = t;
                          save(n);
                        },
                ),
                IconButton(
                  tooltip: tx(context, 'حَذف', 'Delete'),
                  icon: const Icon(Icons.delete_outline, size: 20, color: VC.bad),
                  onPressed: parts.length <= 1
                      ? null
                      : () {
                          final n = [...parts]..removeAt(i);
                          save(n);
                        },
                ),
              ],
            ]),
          ),
      ]),
    );
  }

  /// Edits one part: title, footer and the printed lines (ticked = printed, in the shown order).
  static Future<Map<String, dynamic>?> _editPart(BuildContext context, Map<String, dynamic> part) {
    final title = TextEditingController(text: '${part['title']}');
    final footer = TextEditingController(text: '${part['footer'] ?? ''}');
    final items = [for (final k in part['items'] as List) '$k'];
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final others = kTicketItems.keys.where((k) => !items.contains(k)).toList();
        return AlertDialog(
          title: Text(tx(ctx, 'جُزء التَذكَرة', 'Ticket part')),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(
                  controller: title,
                  decoration: InputDecoration(labelText: tx(ctx, 'العُنوان المَطبوع', 'Printed title'), hintText: 'CUSTOMER COPY'),
                ),
                const SizedBox(height: 14),
                Text(tx(ctx, 'السُطور المَطبوعة (بِالتَرتيب)', 'Printed lines (in order)'), style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                for (var i = 0; i < items.length; i++)
                  Row(children: [
                    const Icon(Icons.check_box, size: 20, color: VC.ok),
                    const SizedBox(width: 8),
                    Expanded(child: Text(tx(ctx, kTicketItems[items[i]]?.$1 ?? items[i], kTicketItems[items[i]]?.$2 ?? items[i]))),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.arrow_upward, size: 18),
                      onPressed: i == 0
                          ? null
                          : () => set(() {
                                final t = items[i];
                                items[i] = items[i - 1];
                                items[i - 1] = t;
                              }),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close, size: 18, color: VC.bad),
                      onPressed: items.length <= 1 ? null : () => set(() => items.removeAt(i)),
                    ),
                  ]),
                if (others.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(tx(ctx, 'إضافة سَطر', 'Add a line'), style: const TextStyle(color: VC.muted, fontSize: 12.5)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final k in others)
                      ActionChip(
                        avatar: const Icon(Icons.add, size: 16),
                        label: Text(tx(ctx, kTicketItems[k]!.$1, kTicketItems[k]!.$2)),
                        onPressed: () => set(() => items.add(k)),
                      ),
                  ]),
                ],
                const SizedBox(height: 14),
                TextField(
                  controller: footer,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: tx(ctx, 'نَصّ في آخِر الجُزء (اختياريّ)', 'Text at the end of the part (optional)'),
                    hintText: tx(ctx, 'مِثال: الشَرِكة غَير مَسؤولة عَن المُقتَنَيات', 'e.g. We are not responsible for valuables'),
                  ),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tx(ctx, 'إلغاء', 'Cancel'))),
            FilledButton(
              onPressed: () {
                final t = title.text.trim();
                if (t.isEmpty) return;
                Navigator.pop(ctx, {...part, 'title': t.toUpperCase(), 'footer': footer.text.trim(), 'items': items});
              },
              child: Text(tx(ctx, 'حِفظ', 'Save')),
            ),
          ],
        );
      }),
    );
  }
}
