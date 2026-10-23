import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import 'valet_admin.dart';
import 'valet_ui.dart';

/// Printed ticket parts of a point (valet_point_settings.ticket_parts). Same keys and defaults
/// as the valet app (vip_valet lib/core/ticket_parts.dart).
///
/// A part: {id, title, enabled, footer, items:[keys], header:bool, labels:{key:text}, texts:{'text:<id>':{text,align,bold,big}}}
/// Item keys that can repeat: 'blank', 'divider', 'logo_*', 'text:<id>'. Older apps skip the keys they do not know.
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
  'company_name': ('اسم الشَرِكة', 'Company name'),
  'point_name': ('اسم النُقطة', 'Point name'),
  'part_title': ('عُنوان الجُزء', 'Part title'),
  'logo_company': ('لوجو الشَرِكة', 'Company logo'),
  'logo_point': ('لوجو النُقطة / العَميل', 'Point / client logo'),
  'logo_both': ('اللوجوهَين جَنب بَعض', 'Both logos side by side'),
  'blank': ('سَطر فارِغ', 'Empty line'),
  'divider': ('خَطّ فاصِل', 'Divider line'),
};

/// Items added any number of times.
const Set<String> kRepeatItems = {'blank', 'divider', 'logo_company', 'logo_point', 'logo_both'};

/// Printed text of the items whose wording can be changed (default = English as printed today).
const Map<String, String> kItemLabels = {
  'number': 'TICKET',
  'plate': 'Plate',
  'color': 'Color',
  'vehicle': 'Vehicle',
  'customer': 'Customer',
  'type': 'Type',
  'mode': 'Mode',
  'card': 'Card',
  'time_in': 'Time In',
  'price': 'Price|VAT|Total',
  'qr': 'Scan to request your car',
  'received_by': 'Received by',
  'delivered_by': 'Delivered by',
  'parking': 'Parking',
  'signature': 'Signature',
  'notes': 'Notes',
};

List<Map<String, dynamic>> defaultTicketParts() => [
      {
        'id': 'customer',
        'title': 'CUSTOMER COPY',
        'enabled': true,
        'footer': '',
        'items': ['number', 'code', 'plate', 'color', 'vehicle', 'customer', 'type', 'mode', 'card', 'time_in', 'price', 'qr'],
      },
      {
        'id': 'office',
        'title': 'OFFICE COPY',
        'enabled': true,
        'footer': '',
        'items': ['number', 'code', 'plate', 'color', 'vehicle', 'customer', 'type', 'mode', 'card', 'time_in', 'price'],
      },
      {
        'id': 'car',
        'title': 'CAR TAG',
        'enabled': true,
        'footer': '',
        'items': ['number', 'plate_big', 'time_big']
      },
      {
        'id': 'key',
        'title': 'KEY TAG',
        'enabled': true,
        'footer': '',
        'items': ['number', 'plate', 'received_by', 'delivered_by', 'parking']
      },
    ];

Map<String, dynamic> _part(Map e) => {
      'id': '${e['id'] ?? ''}',
      'title': '${e['title'] ?? ''}',
      'enabled': e['enabled'] != false,
      'footer': '${e['footer'] ?? ''}',
      'header': e['header'] != false,
      'items': [for (final i in (e['items'] is List ? e['items'] as List : const [])) '$i'],
      'labels': {
        for (final x in ((e['labels'] is Map) ? (e['labels'] as Map) : const {}).entries)
          if ('${x.value}'.trim().isNotEmpty) '${x.key}': '${x.value}',
      },
      'texts': {
        for (final x in ((e['texts'] is Map) ? (e['texts'] as Map) : const {}).entries)
          if (x.value is Map) '${x.key}': Map<String, dynamic>.from(x.value as Map),
      },
    };

List<Map<String, dynamic>> ticketPartsOf(dynamic v) {
  if (v is! List || v.isEmpty) return defaultTicketParts().map(_part).toList();
  return [
    for (final e in v)
      if (e is Map) _part(e)
  ];
}

String _itemName(BuildContext c, String k, Map<String, dynamic> texts) {
  if (k.startsWith('text:')) {
    final t = '${(texts[k] as Map?)?['text'] ?? ''}'.replaceAll('\n', ' ');
    return '${tx(c, 'نَصّ', 'Text')}: ${t.isEmpty ? '…' : t}';
  }
  return tx(c, kTicketItems[k]?.$1 ?? k, kTicketItems[k]?.$2 ?? k);
}

/// The logos of the ticket (company = all points, point = this point / its client) as PNG bytes.
class TicketLogos {
  const TicketLogos({this.company, this.point});
  final Uint8List? company;
  final Uint8List? point;

  static Uint8List? _png(dynamic v) {
    final s = v is Map ? '${v['png'] ?? ''}' : '';
    if (s.isEmpty) return null;
    try {
      return base64Decode(s);
    } catch (_) {
      return null;
    }
  }

  static TicketLogos of(Map d) => TicketLogos(company: _png(d['company']), point: _png(d['point']));
}

/// Image picked in the dashboard -> small black-and-white PNG for the 58 mm printer (max 384 dots wide).
String? printerLogoBase64(Uint8List bytes, {int maxWidth = 384, int maxHeight = 200}) {
  var im = img.decodeImage(bytes);
  if (im == null) return null;
  // transparent parts become white
  final flat = img.Image(width: im.width, height: im.height);
  img.fill(flat, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(flat, im);
  im = flat;
  final scale = [maxWidth / im.width, maxHeight / im.height, 1.0].reduce((a, b) => a < b ? a : b);
  if (scale < 1) {
    im = img.copyResize(im,
        width: (im.width * scale).round(), height: (im.height * scale).round(), interpolation: img.Interpolation.average);
  }
  im = img.grayscale(im);
  // thermal printers print black or nothing: dithering keeps grey parts readable
  im = img.ditherImage(im, quantizer: img.BinaryQuantizer(threshold: 0.6), kernel: img.DitherKernel.floydSteinberg);
  return base64Encode(img.encodePng(im));
}

/// Panel in the point's Features tab: logos, switch parts on / off, edit (with live preview), reorder, up to 6 parts.
class TicketPartsPanel extends StatefulWidget {
  const TicketPartsPanel(
      {super.key, required this.value, required this.edit, required this.onSave, required this.pointId, this.pointName = ''});

  final dynamic value;
  final bool edit;
  final Future<void> Function(List<Map<String, dynamic>>? parts) onSave;
  final String pointId;
  final String pointName;

  static const maxParts = 6;

  @override
  State<TicketPartsPanel> createState() => _TicketPartsPanelState();
}

class _TicketPartsPanelState extends State<TicketPartsPanel> {
  TicketLogos _logos = const TicketLogos();

  @override
  void initState() {
    super.initState();
    _loadLogos();
  }

  Future<void> _loadLogos() async {
    try {
      final d = await ValetAdmin.I.call('vva_ticket_logos', {'p_point': widget.pointId});
      if (mounted) setState(() => _logos = TicketLogos.of(d));
    } catch (_) {
      // old server: no logos
    }
  }

  Future<void> _pickLogo({required bool company}) async {
    final f = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final bytes = f?.files.single.bytes;
    if (bytes == null || !mounted) return;
    final b64 = printerLogoBase64(bytes);
    if (b64 == null) {
      vToast(context, tx(context, 'تَعَذَّر قِراءة الصورة.', 'Could not read the image.'));
      return;
    }
    final d = await vGuard(
      context,
      () => ValetAdmin.I.call('vva_ticket_logo_save', {'p_point': company ? null : widget.pointId, 'p_png': b64}),
      ok: tx(context, 'تَمّ حِفظ اللوجو.', 'Logo saved.'),
    );
    if (d != null && mounted) {
      // the saved company logo is answered with p_point null: reload both
      await _loadLogos();
    }
  }

  Future<void> _removeLogo({required bool company}) async {
    final d = await vGuard(
      context,
      () => ValetAdmin.I.call('vva_ticket_logo_save', {'p_point': company ? null : widget.pointId, 'p_png': null}),
      ok: tx(context, 'تَمّ حَذف اللوجو.', 'Logo removed.'),
    );
    if (d != null) await _loadLogos();
  }

  Widget _logoSlot({required bool company}) {
    final png = company ? _logos.company : _logos.point;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(color: VC.muted.withValues(alpha: 0.25)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            company
                ? tx(context, 'لوجو الشَرِكة (لِكُلّ النِقاط)', 'Company logo (all points)')
                : tx(context, 'لوجو النُقطة / العَميل', 'Point / client logo'),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Container(
            height: 70,
            color: Colors.white,
            alignment: Alignment.center,
            child: png == null
                ? Text(tx(context, 'لا يوجد', 'None'), style: const TextStyle(color: VC.muted))
                : Image.memory(png, fit: BoxFit.contain, filterQuality: FilterQuality.none),
          ),
          if (widget.edit) ...[
            const SizedBox(height: 6),
            Wrap(spacing: 6, children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.upload_outlined, size: 16),
                label: Text(png == null ? tx(context, 'رَفع', 'Upload') : tx(context, 'تَغيير', 'Change')),
                onPressed: () => _pickLogo(company: company),
              ),
              if (png != null)
                TextButton(
                  onPressed: () => _removeLogo(company: company),
                  child: Text(tx(context, 'حَذف', 'Remove'), style: const TextStyle(color: VC.bad)),
                ),
            ]),
          ],
        ]),
      ),
    );
  }

  Future<void> _previewAll(List<Map<String, dynamic>> parts) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tx(ctx, 'مُعايَنة التَذكَرة', 'Ticket preview')),
          content: SizedBox(
            width: 340,
            child: SingleChildScrollView(
              child: Column(children: [
                for (final p in parts.where((p) => p['enabled'] == true)) ...[
                  TicketPreview(part: p, logos: _logos, pointName: widget.pointName),
                  const _TearLine(),
                ],
              ]),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tx(ctx, 'إغلاق', 'Close')))],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    final edit = widget.edit;
    final custom = value is List && value.isNotEmpty;
    final parts = ticketPartsOf(value);
    Future<void> save(List<Map<String, dynamic>> p) => widget.onSave(p);
    return VPanel(
      title: tx(context, 'أَجزاء التَذكَرة المَطبوعة', 'Printed ticket parts'),
      actions: [
        OutlinedButton.icon(
          icon: const Icon(Icons.receipt_long_outlined, size: 18),
          label: Text(tx(context, 'مُعايَنة', 'Preview')),
          onPressed: () => _previewAll(parts),
        ),
        if (edit && custom)
          TextButton(
            onPressed: () => widget.onSave(null),
            child: Text(tx(context, 'الافتِراضيّ', 'Reset to default')),
          ),
        if (edit && parts.length < TicketPartsPanel.maxParts)
          FilledButton.icon(
            icon: const Icon(Icons.add),
            label: Text(tx(context, 'جُزء جَديد', 'New part')),
            onPressed: () async {
              final p = await editTicketPart(
                  context,
                  _part({
                    'id': 'part${DateTime.now().millisecondsSinceEpoch}',
                    'title': 'PART ${parts.length + 1}',
                    'enabled': true,
                    'footer': '',
                    'items': ['number', 'plate'],
                  }),
                  _logos,
                  widget.pointName);
              if (p != null) await save([...parts, p]);
            },
          ),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          tx(
              context,
              'تُطبَع الأَجزاء المُفعَّلة بِالتَرتيب عِند إضافة كُلّ تَذكَرة في هذه النُقطة. '
                  'اللوجو وَالنُصوص المُعَدَّلة وَالسُطور الفارِغة تَحتاج تَطبيق 2.1.3 أَو أَحدَث. '
                  '${custom ? '' : 'الآن: الأَجزاء الأَربَعة الافتِراضيّة — وَكُلّ جِهاز يَختار مِنها.'}',
              'The parts switched on are printed in this order for every new ticket at this point. '
                  'Logos, changed texts and empty lines need app 2.1.3 or later. '
                  '${custom ? '' : 'Now: the 4 default parts — each device picks among them.'}'),
          style: const TextStyle(color: VC.muted, fontSize: 12.5),
        ),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _logoSlot(company: true),
          const SizedBox(width: 10),
          _logoSlot(company: false),
        ]),
        const SizedBox(height: 10),
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
                    [for (final k in parts[i]['items'] as List) _itemName(context, '$k', parts[i]['texts'] as Map<String, dynamic>)]
                        .join(' · '),
                    style: const TextStyle(color: VC.muted, fontSize: 12),
                  ),
                ]),
              ),
              IconButton(
                tooltip: tx(context, 'مُعايَنة', 'Preview'),
                icon: const Icon(Icons.visibility_outlined, size: 20),
                onPressed: () => _previewAll([parts[i]]),
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
                    final p = await editTicketPart(context, parts[i], _logos, widget.pointName);
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
}

/// Edits one part with a live preview: title, header, lines (order, own wording, empty lines, dividers,
/// free text, logos) and the footer.
Future<Map<String, dynamic>?> editTicketPart(BuildContext context, Map<String, dynamic> part, TicketLogos logos, String pointName) {
  final title = TextEditingController(text: '${part['title']}');
  final footer = TextEditingController(text: '${part['footer'] ?? ''}');
  final items = [for (final k in part['items'] as List) '$k'];
  final labels = Map<String, String>.from(part['labels'] as Map? ?? const {});
  final texts = <String, Map<String, dynamic>>{
    for (final e in ((part['texts'] as Map?) ?? const {}).entries) '${e.key}': Map<String, dynamic>.from(e.value as Map),
  };
  var header = part['header'] != false;

  Map<String, dynamic> current() => {
        ...part,
        'title': title.text.trim().toUpperCase(),
        'footer': footer.text.trim(),
        'header': header,
        'items': [...items],
        'labels': {
          for (final e in labels.entries)
            if (e.value.trim().isNotEmpty) e.key: e.value.trim()
        },
        'texts': {
          for (final k in items)
            if (k.startsWith('text:') && texts[k] != null) k: texts[k]
        },
      };

  Future<void> editLabel(BuildContext ctx, String k, void Function(void Function()) set) async {
    final c = TextEditingController(text: labels[k] ?? kItemLabels[k] ?? '');
    final r = await showDialog<String>(
      context: ctx,
      builder: (d) => AlertDialog(
        title: Text(tx(d, 'النَصّ المَطبوع', 'Printed text')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
              controller: c,
              autofocus: true,
              decoration: InputDecoration(helperText: tx(d, 'الافتِراضيّ: ', 'Default: ') + (kItemLabels[k] ?? ''))),
          if (k == 'price')
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(tx(d, 'ثَلاث كَلِمات بَينَها | (السِعر|الضَريبة|الإجماليّ)', 'Three words split by | (Price|VAT|Total)'),
                  style: const TextStyle(color: VC.muted, fontSize: 12)),
            ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, ''), child: Text(tx(d, 'الافتِراضيّ', 'Default'))),
          FilledButton(onPressed: () => Navigator.pop(d, c.text), child: Text(tx(d, 'حِفظ', 'Save'))),
        ],
      ),
    );
    if (r == null) return;
    set(() => r.trim().isEmpty || r.trim() == kItemLabels[k] ? labels.remove(k) : labels[k] = r.trim());
  }

  Future<void> editText(BuildContext ctx, String? key, void Function(void Function()) set) async {
    final t = key == null ? <String, dynamic>{'text': '', 'align': 'center', 'bold': false, 'big': false} : {...?texts[key]};
    final c = TextEditingController(text: '${t['text'] ?? ''}');
    var align = '${t['align'] ?? 'center'}';
    var bold = t['bold'] == true;
    var big = t['big'] == true;
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (d) => StatefulBuilder(
        builder: (d, s2) => AlertDialog(
          title: Text(tx(d, 'سَطر نَصّ', 'Text line')),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(
                controller: c,
                autofocus: true,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(labelText: tx(d, 'النَصّ (عَرَبيّ أَو إنجليزيّ)', 'Text (Arabic or English)')),
              ),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'left', icon: const Icon(Icons.format_align_left), label: Text(tx(d, 'يَسار', 'Left'))),
                  ButtonSegment(value: 'center', icon: const Icon(Icons.format_align_center), label: Text(tx(d, 'وَسَط', 'Centre'))),
                  ButtonSegment(value: 'right', icon: const Icon(Icons.format_align_right), label: Text(tx(d, 'يَمين', 'Right'))),
                ],
                selected: {align},
                onSelectionChanged: (v) => s2(() => align = v.first),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: bold,
                onChanged: (v) => s2(() => bold = v ?? false),
                title: Text(tx(d, 'عَريض', 'Bold')),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: big,
                onChanged: (v) => s2(() => big = v ?? false),
                title: Text(tx(d, 'خَطّ كَبير', 'Big text')),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tx(d, 'إلغاء', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(tx(d, 'حِفظ', 'Save'))),
          ],
        ),
      ),
    );
    if (ok != true || c.text.trim().isEmpty) return;
    set(() {
      final k = key ?? 'text:${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
      texts[k] = {'text': c.text.trim(), 'align': align, 'bold': bold, 'big': big};
      if (key == null) items.add(k);
    });
  }

  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      final wide = MediaQuery.sizeOf(ctx).width >= 900;
      final others = kTicketItems.keys.where((k) => kRepeatItems.contains(k) || !items.contains(k)).toList();
      final editor = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: title,
          onChanged: (_) => set(() {}),
          decoration: InputDecoration(labelText: tx(ctx, 'العُنوان المَطبوع', 'Printed title'), hintText: 'CUSTOMER COPY'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: header,
          onChanged: (v) => set(() => header = v),
          title: Text(tx(ctx, 'رَأس الجُزء: اسم الشَرِكة + النُقطة + العُنوان', 'Part header: company + point + title')),
          subtitle: Text(tx(ctx, 'أَطفِئه لِتَضَع اللوجو أَو الأَسماء بِتَرتيبك', 'Switch off to place the logo / names in your own order'),
              style: const TextStyle(fontSize: 12)),
        ),
        const SizedBox(height: 6),
        Text(tx(ctx, 'السُطور المَطبوعة (بِالتَرتيب)', 'Printed lines (in order)'), style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        for (var i = 0; i < items.length; i++)
          Row(children: [
            Icon(
              items[i] == 'blank'
                  ? Icons.space_bar
                  : items[i] == 'divider'
                      ? Icons.horizontal_rule
                      : items[i].startsWith('logo')
                          ? Icons.image_outlined
                          : items[i].startsWith('text:')
                              ? Icons.notes
                              : Icons.check_box,
              size: 20,
              color: VC.ok,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_itemName(ctx, items[i], texts), maxLines: 2, overflow: TextOverflow.ellipsis),
                if (labels[items[i]] != null)
                  Text('“${labels[items[i]]}”', style: const TextStyle(color: VC.gold, fontSize: 12, fontWeight: FontWeight.w700)),
              ]),
            ),
            if (kItemLabels.containsKey(items[i]))
              IconButton(
                tooltip: tx(ctx, 'تَعديل النَصّ المَطبوع', 'Change the printed text'),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit_note, size: 20),
                onPressed: () => editLabel(ctx, items[i], set),
              ),
            if (items[i].startsWith('text:'))
              IconButton(
                tooltip: tx(ctx, 'تَعديل', 'Edit'),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit_note, size: 20),
                onPressed: () => editText(ctx, items[i], set),
              ),
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
              icon: const Icon(Icons.arrow_downward, size: 18),
              onPressed: i == items.length - 1
                  ? null
                  : () => set(() {
                        final t = items[i];
                        items[i] = items[i + 1];
                        items[i + 1] = t;
                      }),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 18, color: VC.bad),
              onPressed: items.length <= 1 ? null : () => set(() => items.removeAt(i)),
            ),
          ]),
        const SizedBox(height: 8),
        Text(tx(ctx, 'إضافة سَطر', 'Add a line'), style: const TextStyle(color: VC.muted, fontSize: 12.5)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          ActionChip(
            avatar: const Icon(Icons.notes, size: 16),
            label: Text(tx(ctx, 'نَصّ حُرّ', 'Free text')),
            onPressed: () => editText(ctx, null, set),
          ),
          for (final k in others)
            ActionChip(
              avatar: Icon(kRepeatItems.contains(k) ? Icons.add_box_outlined : Icons.add, size: 16),
              label: Text(tx(ctx, kTicketItems[k]!.$1, kTicketItems[k]!.$2)),
              onPressed: () => set(() => items.add(k)),
            ),
        ]),
        const SizedBox(height: 14),
        TextField(
          controller: footer,
          maxLines: 2,
          onChanged: (_) => set(() {}),
          decoration: InputDecoration(
            labelText: tx(ctx, 'نَصّ في آخِر الجُزء (اختياريّ)', 'Text at the end of the part (optional)'),
            hintText: tx(ctx, 'مِثال: الشَرِكة غَير مَسؤولة عَن المُقتَنَيات', 'e.g. We are not responsible for valuables'),
          ),
        ),
      ]);
      final preview = Column(children: [
        Text(tx(ctx, 'المُعايَنة (وَرَق 58 مم)', 'Preview (58 mm paper)'), style: const TextStyle(color: VC.muted, fontSize: 12)),
        const SizedBox(height: 6),
        TicketPreview(part: current(), logos: logos, pointName: pointName),
      ]);
      return AlertDialog(
        title: Text(tx(ctx, 'جُزء التَذكَرة', 'Ticket part')),
        content: SizedBox(
          width: wide ? 900 : 480,
          child: wide
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: SingleChildScrollView(child: editor)),
                  const SizedBox(width: 18),
                  SizedBox(width: 320, child: SingleChildScrollView(child: preview)),
                ])
              : SingleChildScrollView(child: Column(children: [editor, const SizedBox(height: 14), preview])),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tx(ctx, 'إلغاء', 'Cancel'))),
          FilledButton(
            onPressed: () {
              if (title.text.trim().isEmpty) return;
              Navigator.pop(ctx, current());
            },
            child: Text(tx(ctx, 'حِفظ', 'Save')),
          ),
        ],
      );
    }),
  );
}

class _TearLine extends StatelessWidget {
  const _TearLine();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          const Icon(Icons.content_cut, size: 14, color: VC.muted),
          const SizedBox(width: 6),
          Expanded(child: Container(height: 1, color: VC.muted.withValues(alpha: 0.4))),
        ]),
      );
}

/// What one part looks like on the 58 mm paper (sample ticket). Mirrors Receipts.ticket of the valet app.
class TicketPreview extends StatelessWidget {
  const TicketPreview({super.key, required this.part, required this.logos, this.pointName = ''});
  final Map<String, dynamic> part;
  final TicketLogos logos;
  final String pointName;

  static const _w = 300.0; // 384 dots

  @override
  Widget build(BuildContext context) {
    final labels = (part['labels'] as Map?)?.cast<String, dynamic>() ?? const {};
    final texts = (part['texts'] as Map?)?.cast<String, dynamic>() ?? const {};
    String lb(String k) => '${labels[k] ?? kItemLabels[k] ?? k}';
    const base = TextStyle(fontFamily: 'monospace', fontSize: 12.5, color: Colors.black, height: 1.35);
    final big = base.copyWith(fontSize: 22, fontWeight: FontWeight.w900);
    final bold = base.copyWith(fontWeight: FontWeight.w800);
    final out = <Widget>[];
    Widget c(String t, {TextStyle? s}) => Center(child: Text(t, textAlign: TextAlign.center, style: s ?? base));
    // an Arabic label is printed on the right (as the app prints it)
    Widget pair(String l, String r, {bool b = false}) => Directionality(
          textDirection: _arabic.hasMatch(l) ? TextDirection.rtl : TextDirection.ltr,
          child: Row(children: [
            Expanded(child: Text(l, style: b ? bold : base)),
            Text(r, style: b ? bold : base, textDirection: TextDirection.ltr),
          ]),
        );
    Widget dash() => Text('-' * 90, maxLines: 1, softWrap: false, overflow: TextOverflow.clip, style: base);
    Widget logo(Uint8List? png, {double h = 64}) => png == null
        ? Container(
            height: h,
            margin: const EdgeInsets.symmetric(vertical: 2),
            alignment: Alignment.center,
            decoration: BoxDecoration(border: Border.all(color: Colors.black26)),
            child: const Text('LOGO', style: TextStyle(color: Colors.black38, fontSize: 11)),
          )
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Image.memory(png, height: h, fit: BoxFit.contain, filterQuality: FilterQuality.none),
          );

    if (part['header'] != false) {
      out
        ..add(c('VIP Valet', s: bold))
        ..add(c(pointName.isEmpty ? 'POINT NAME' : pointName, s: bold))
        ..add(c('${part['title']}'.isEmpty ? 'TICKET' : '${part['title']}'))
        ..add(dash());
    }
    for (final k in [for (final i in part['items'] as List) '$i']) {
      switch (k) {
        case 'number':
          out.add(c('${lb('number')} 0042', s: big));
        case 'code':
          out.add(c('T-0042-BEI-26'));
        case 'plate':
          out.add(pair(lb('plate'), 'D 12345', b: true));
        case 'plate_big':
          out.add(c('D 12345', s: big));
        case 'color':
          out.add(pair(lb('color'), 'White'));
        case 'vehicle':
          out.add(pair(lb('vehicle'), 'Sedan'));
        case 'customer':
          out.add(pair(lb('customer'), 'Visitor'));
        case 'type':
          out.add(pair(lb('type'), 'Standard'));
        case 'mode':
          out.add(pair(lb('mode'), 'TICKET'));
        case 'card':
          out.add(pair(lb('card'), 'C-118'));
        case 'time_in':
          out.add(pair(lb('time_in'), '23/10/2026 21:15'));
        case 'time_big':
          out.add(c('23/10/2026 21:15'));
        case 'price':
          final w = lb('price').split('|');
          String at(int i, String d) => i < w.length && w[i].trim().isNotEmpty ? w[i].trim() : d;
          out
            ..add(dash())
            ..add(pair(at(0, 'Price'), '23.81'))
            ..add(pair('${at(1, 'VAT')} 5%', '1.19'))
            ..add(pair(at(2, 'Total'), '25.00 AED', b: true));
        case 'qr':
          out
            ..add(const SizedBox(height: 6))
            ..add(const Center(child: Icon(Icons.qr_code_2, size: 96, color: Colors.black)))
            ..add(c(lb('qr')));
        case 'received_by':
          out.add(pair(lb('received_by'), '__________'));
        case 'delivered_by':
          out.add(pair(lb('delivered_by'), '__________'));
        case 'parking':
          out.add(pair(lb('parking'), '__________'));
        case 'signature':
          out
            ..add(const SizedBox(height: 16))
            ..add(pair(lb('signature'), '__________'));
        case 'notes':
          out.add(pair(lb('notes'), 'Scratch on the left door'));
        case 'company_name':
          out.add(c('VIP Valet', s: bold));
        case 'point_name':
          out.add(c(pointName.isEmpty ? 'POINT NAME' : pointName, s: bold));
        case 'part_title':
          out.add(c('${part['title']}'));
        case 'logo_company':
          out.add(logo(logos.company));
        case 'logo_point':
          out.add(logo(logos.point));
        case 'logo_both':
          out.add(Row(children: [
            Expanded(child: logo(logos.company, h: 56)),
            const SizedBox(width: 8),
            Expanded(child: logo(logos.point, h: 56))
          ]));
        case 'blank':
          out.add(const SizedBox(height: 17));
        case 'divider':
          out.add(dash());
        default:
          if (k.startsWith('text:')) {
            final t = (texts[k] as Map?) ?? const {};
            final s = (t['big'] == true ? big : base).copyWith(fontWeight: t['bold'] == true || t['big'] == true ? FontWeight.w800 : null);
            final a = switch ('${t['align']}') { 'left' => TextAlign.left, 'right' => TextAlign.right, _ => TextAlign.center };
            out.add(SizedBox(width: double.infinity, child: Text('${t['text'] ?? ''}', textAlign: a, style: s)));
          }
      }
    }
    final f = '${part['footer'] ?? ''}'.trim();
    if (f.isNotEmpty) {
      out
        ..add(dash())
        ..add(c(f));
    }
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        width: _w,
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: out),
      ),
    );
  }
}

final _arabic = RegExp(r'[\u0600-\u06FF]');
