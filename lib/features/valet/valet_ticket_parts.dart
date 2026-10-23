import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
  'damage': ('رَسمة السَيّارة وَالضَرَر', 'Car drawing with damage'),
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
  'damage': 'Damage|None',
};

/// Text sizes of the ticket: key -> (Arabic, English, printer dots). 'm' and 'xl' are the printers' own
/// fonts (1x / 2x); the others print as a picture.
const Map<String, (String, String, double)> kTicketSizes = {
  's': ('صَغير', 'Small', 18),
  'm': ('عاديّ', 'Normal', 24),
  'l': ('كَبير', 'Large', 32),
  'xl': ('كَبير جِدّاً', 'X-large', 44),
  'xxl': ('ضَخم', 'Huge', 60),
};

/// Lines printed big by default.
const Set<String> kBigItems = {'number', 'plate_big'};

/// Size of a line: own size, else 'xl' for the big lines (and big free text), else the part's size.
String ticketSizeOf(Map<String, dynamic> part, String key) {
  final own = '${((part['sizes'] as Map?) ?? const {})[key] ?? ''}';
  if (kTicketSizes.containsKey(own)) return own;
  if (kBigItems.contains(key)) return 'xl';
  if (key.startsWith('text:') && ((part['texts'] as Map?)?[key] as Map?)?['big'] == true) return 'xl';
  final f = '${part['font'] ?? 'm'}';
  return kTicketSizes.containsKey(f) ? f : 'm';
}

/// Fonts a line can use (printed as a picture; the app has them). key -> (Arabic, English, preview style).
final Map<String, (String, String, TextStyle Function())> kTicketFonts = {
  'inter': ('Inter', 'Inter', () => GoogleFonts.inter()),
  'oswald': ('Oswald (طَويل)', 'Oswald (tall)', () => GoogleFonts.oswald()),
  'kalam': ('Kalam (خَطّ يَد)', 'Kalam (handwriting)', () => GoogleFonts.kalam()),
  'serif': ('Serif', 'Serif', () => GoogleFonts.notoSerif()),
  'mono': ('Mono', 'Mono', () => GoogleFonts.robotoMono()),
};

/// Lines every layout can have.
const Map<String, (String, String)> kCommonItems = {
  'company_name': ('اسم الشَرِكة', 'Company name'),
  'point_name': ('اسم النُقطة', 'Point name'),
  'part_title': ('العُنوان', 'Title'),
  'logo_company': ('لوجو الشَرِكة', 'Company logo'),
  'logo_point': ('لوجو النُقطة / العَميل', 'Point / client logo'),
  'logo_both': ('اللوجوهَين جَنب بَعض', 'Both logos side by side'),
  'blank': ('سَطر فارِغ', 'Empty line'),
  'divider': ('خَطّ فاصِل', 'Divider line'),
};

/// Payment receipt lines (vip_valet Receipts.serviceInvoice).
const Map<String, (String, String)> kReceiptItems = {
  'number': ('رَقم التَذكَرة (كَبير)', 'Ticket number (big)'),
  'code': ('كود التَذكَرة', 'Ticket code'),
  'plate': ('اللَوحة', 'Plate'),
  'ticket': ('نَوع التَذكَرة', 'Ticket type'),
  'time_in': ('وَقت الدُخول', 'Time in'),
  'time_out': ('وَقت الخُروج', 'Time out'),
  'duration': ('المُدّة', 'Duration'),
  'price': ('السِعر وَالضَريبة وَالإجماليّ', 'Price, VAT and total'),
  'extras': ('المَبيت / الكَرت المَفقود / البَقشيش', 'Overnight / lost card / tips'),
  'payment': ('طَريقة الدَفع', 'Payment mode'),
  'grace': ('مَجّانيّة الدَقائق الأولى', 'Free minutes note'),
  'card_ref': ('رَقم المُوافَقة', 'Approval number'),
  'paid_change': ('المَدفوع وَالباقي', 'Paid and change'),
  'thanks': ('شُكراً', 'Thank you'),
  ...kCommonItems,
};

const Map<String, String> kReceiptLabels = {
  'number': 'TICKET',
  'plate': 'Plate',
  'ticket': 'Ticket',
  'time_in': 'Time In',
  'time_out': 'Time Out',
  'duration': 'Duration',
  'price': 'Price|VAT|Total',
  'extras': 'Overnight|Lost card|Tips|Grand total',
  'payment': 'Payment',
  'grace': 'Free – car left within {min} min',
  'card_ref': 'Approval no.',
  'paid_change': 'Paid|Change',
  'thanks': 'Thank you!',
};

/// Shift report lines (vip_valet Receipts.shiftReport).
const Map<String, (String, String)> kShiftItems = {
  'shift': ('رَقم الوَرديّة', 'Shift code'),
  'closed_by': ('أَغلَقَها', 'Closed by'),
  'start': ('البِداية', 'Start'),
  'end': ('النِهاية', 'End'),
  'cars': ('السَيّارات (الإجماليّ / السابِقة / المُغلَقة / المُعَلَّقة)', 'Cars (total / previous / closed / pending)'),
  'tickets_range': ('أَوَّل وَآخِر تَذكَرة', 'First and last ticket'),
  'payments': ('جَدوَل طُرُق الدَفع', 'Payments table'),
  'types': ('جَدوَل أَنواع التَذاكِر', 'Ticket types table'),
  'tips': ('البَقشيش كاش / كَرت', 'Cash / card tips'),
  'totals': ('إجماليّ المَبيعات', 'Sales totals'),
  'machines': ('مَكينات الدَفع', 'Card machines'),
  'cash': ('الكاش المُتَوَقَّع / المَعدود / الفَرق', 'Cash expected / counted / difference'),
  'signature': ('تَوقيع المُشرِف ____', 'Supervisor signature ____'),
  ...kCommonItems,
};

const Map<String, String> kShiftLabels = {
  'shift': 'Shift',
  'closed_by': 'Closed by',
  'start': 'Start',
  'end': 'End',
  'cars': 'Total cars|From previous|Closed tickets|Pending cars',
  'tickets_range': 'First ticket|Last ticket',
  'payments': 'Payment|Cnt|Total|Tips',
  'types': 'Ticket type|Cnt|Total',
  'tips': 'Cash tips|Card tips',
  'totals': 'Total sales|Tips|Total with tips',
  'machines': 'Card machines',
  'cash': 'Cash expected|Cash counted|Difference|SHORT|Note',
  'signature': 'Supervisor signature',
};

/// A printed document: its lines, default wording and default layout.
class PrintDoc {
  const PrintDoc(this.id, this.items, this.labels, this.defaultItems, this.defaultTitle, this.name);
  final String id;
  final Map<String, (String, String)> items;
  final Map<String, String> labels;
  final List<String> defaultItems;
  final String defaultTitle;
  final (String, String) name;

  Map<String, dynamic> defaults() => {'id': id, 'title': defaultTitle, 'enabled': true, 'footer': '', 'items': defaultItems};
}

const kDocTicket = PrintDoc('ticket', kTicketItems, kItemLabels, [], 'TICKET', ('جُزء التَذكَرة', 'Ticket part'));
const kDocReceipt = PrintDoc(
    'receipt',
    kReceiptItems,
    kReceiptLabels,
    [
      'number',
      'divider',
      'plate',
      'ticket',
      'time_in',
      'time_out',
      'duration',
      'divider',
      'price',
      'extras',
      'payment',
      'grace',
      'card_ref',
      'paid_change',
      'divider',
      'thanks'
    ],
    'SERVICE INVOICE',
    ('فاتورة الدَفع', 'Payment receipt'));
const kDocShift = PrintDoc(
    'shift',
    kShiftItems,
    kShiftLabels,
    [
      'shift',
      'closed_by',
      'start',
      'end',
      'divider',
      'cars',
      'tickets_range',
      'divider',
      'payments',
      'divider',
      'types',
      'divider',
      'tips',
      'totals',
      'cash'
    ],
    'CLOSING SHIFT REPORT',
    ('تَقرير الوَرديّة', 'Shift report'));

/// Layout of the payment receipt / shift report (null = default).
Map<String, dynamic> docLayoutOf(dynamic v, PrintDoc doc) =>
    v is Map && v['items'] is List && (v['items'] as List).isNotEmpty ? _part({...doc.defaults(), ...v}) : _part(doc.defaults());

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
      'header_logo': '${e['header_logo'] ?? 'auto'}',
      'font': '${e['font'] ?? 'm'}',
      'sizes': {
        for (final x in ((e['sizes'] is Map) ? (e['sizes'] as Map) : const {}).entries)
          if (kTicketSizes.containsKey('${x.value}')) '${x.key}': '${x.value}',
      },
      'styles': {
        for (final x in ((e['styles'] is Map) ? (e['styles'] as Map) : const {}).entries)
          if (x.value is Map) '${x.key}': Map<String, dynamic>.from(x.value as Map),
      },
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

String _itemName(BuildContext c, String k, Map<String, dynamic> texts, [PrintDoc doc = kDocTicket]) {
  if (k.startsWith('text:')) {
    final t = '${(texts[k] as Map?)?['text'] ?? ''}'.replaceAll('\n', ' ');
    return '${tx(c, 'نَصّ', 'Text')}: ${t.isEmpty ? '…' : t}';
  }
  return tx(c, doc.items[k]?.$1 ?? k, doc.items[k]?.$2 ?? k);
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
  // plain black / white (sharp edges, no dots)
  im = img.ditherImage(im, quantizer: img.BinaryQuantizer(threshold: 0.55), kernel: img.DitherKernel.none);
  return base64Encode(img.encodePng(im));
}

/// Panel in the point's Features tab: logos, switch parts on / off, edit (with live preview), reorder, up to 6 parts.
class TicketPartsPanel extends StatefulWidget {
  const TicketPartsPanel(
      {super.key,
      required this.value,
      required this.edit,
      required this.onSave,
      required this.pointId,
      this.pointName = '',
      this.receiptLayout,
      this.shiftLayout,
      this.onSaveLayout});

  final dynamic value;

  /// valet_point_settings.receipt_layout / shift_layout (null = default).
  final dynamic receiptLayout;
  final dynamic shiftLayout;

  /// Saves a layout: column ('receipt_layout' / 'shift_layout') and value (null = back to default).
  final Future<void> Function(String column, Map<String, dynamic>? layout)? onSaveLayout;
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

  Widget _docRow(PrintDoc doc, dynamic value, String column) {
    final custom = value is Map && value['items'] is List && (value['items'] as List).isNotEmpty;
    final layout = docLayoutOf(value, doc);
    final save = widget.onSaveLayout;
    return Container(
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
          decoration: BoxDecoration(color: VC.info.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
          child: Icon(doc.id == 'receipt' ? Icons.receipt_long_outlined : Icons.summarize_outlined, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${tx(context, doc.name.$1, doc.name.$2)} · ${layout['title']}', style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(
              [for (final k in layout['items'] as List) _itemName(context, '$k', layout['texts'] as Map<String, dynamic>, doc)].join(' · '),
              style: const TextStyle(color: VC.muted, fontSize: 12),
            ),
          ]),
        ),
        IconButton(
          tooltip: tx(context, 'مُعايَنة', 'Preview'),
          icon: const Icon(Icons.visibility_outlined, size: 20),
          onPressed: () => _previewAll([layout], doc: doc),
        ),
        if (widget.edit && save != null) ...[
          IconButton(
            tooltip: tx(context, 'تَعديل', 'Edit'),
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: () async {
              final p = await editTicketPart(context, layout, _logos, widget.pointName, doc: doc);
              if (p != null) await save(column, p);
            },
          ),
          IconButton(
            tooltip: tx(context, 'الافتِراضيّ', 'Reset to default'),
            icon: const Icon(Icons.restart_alt, size: 20),
            onPressed: custom ? () => save(column, null) : null,
          ),
        ],
      ]),
    );
  }

  Future<void> _previewAll(List<Map<String, dynamic>> parts, {PrintDoc doc = kDocTicket}) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(doc.id == 'ticket' ? tx(ctx, 'مُعايَنة التَذكَرة', 'Ticket preview') : tx(ctx, doc.name.$1, doc.name.$2)),
          content: SizedBox(
            width: 340,
            child: SingleChildScrollView(
              child: Column(children: [
                for (final p in parts.where((p) => p['enabled'] == true)) ...[
                  TicketPreview(part: p, logos: _logos, pointName: widget.pointName, doc: doc),
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
        if (widget.onSaveLayout != null) ...[
          const SizedBox(height: 14),
          Text(tx(context, 'فاتورة الدَفع وَتَقرير الوَرديّة', 'Payment receipt and shift report'),
              style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(
            tx(
                context,
                'نَفس طَريقة التَعديل: تَرتيب السُطور وَالنُصوص وَالحَجم وَنَوع الخَطّ وَاللوجو. التَطبيق يَأخُذ التَعديل قَبل كُلّ طِباعة (2.1.7 أَو أَحدَث).',
                'Same editing: order of the lines, wording, size, font and logo. The app takes the change before each print (2.1.7 or later).'),
            style: const TextStyle(color: VC.muted, fontSize: 12.5),
          ),
          const SizedBox(height: 6),
          _docRow(kDocReceipt, widget.receiptLayout, 'receipt_layout'),
          _docRow(kDocShift, widget.shiftLayout, 'shift_layout'),
        ],
      ]),
    );
  }
}

/// Edits one part with a live preview: title, header, lines (order, own wording, empty lines, dividers,
/// free text, logos) and the footer.
Future<Map<String, dynamic>?> editTicketPart(BuildContext context, Map<String, dynamic> part, TicketLogos logos, String pointName,
    {PrintDoc doc = kDocTicket}) {
  final title = TextEditingController(text: '${part['title']}');
  final footer = TextEditingController(text: '${part['footer'] ?? ''}');
  final items = [for (final k in part['items'] as List) '$k'];
  final labels = Map<String, String>.from(part['labels'] as Map? ?? const {});
  final texts = <String, Map<String, dynamic>>{
    for (final e in ((part['texts'] as Map?) ?? const {}).entries) '${e.key}': Map<String, dynamic>.from(e.value as Map),
  };
  var header = part['header'] != false;
  var headerLogo = '${part['header_logo'] ?? 'auto'}';
  var font = '${part['font'] ?? 'm'}';
  final sizes = Map<String, String>.from(part['sizes'] as Map? ?? const {});

  final styles = <String, Map<String, dynamic>>{
    for (final e in ((part['styles'] as Map?) ?? const {}).entries) '${e.key}': Map<String, dynamic>.from(e.value as Map),
  };
  Map<String, dynamic> look() => {'font': font, 'sizes': sizes, 'texts': texts};

  // the line's look in one dialog: printed words (when it has some), size, bold, font
  Future<void> editLine(BuildContext ctx, String k, void Function(void Function()) set) async {
    final hasWords = doc.labels.containsKey(k);
    final c = TextEditingController(text: labels[k] ?? doc.labels[k] ?? '');
    String? size = sizes[k];
    final st = {...?styles[k]};
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (d) => StatefulBuilder(
        builder: (d, s2) => AlertDialog(
          title: Text(k == 'header'
              ? tx(d, 'رَأس الجُزء', 'Header')
              : k == 'footer'
                  ? tx(d, 'النَصّ في آخِر الجُزء', 'Footer text')
                  : _itemName(d, k, texts, doc)),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (hasWords) ...[
                  TextField(
                    controller: c,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: tx(d, 'النَصّ المَطبوع', 'Printed text'),
                      helperText: tx(d, 'الافتِراضيّ: ', 'Default: ') + (doc.labels[k] ?? ''),
                    ),
                  ),
                  if ((doc.labels[k] ?? '').contains('|'))
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                          tx(d, 'عِدّة كَلِمات بَينَها | بِنَفس تَرتيب الافتِراضيّ', 'Several words split by | in the default order'),
                          style: const TextStyle(color: VC.muted, fontSize: 12)),
                    ),
                  if (k == 'grace')
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(tx(d, '{min} = عَدَد الدَقائق', '{min} = the minutes'),
                          style: const TextStyle(color: VC.muted, fontSize: 12)),
                    ),
                  const SizedBox(height: 14),
                ],
                Text(tx(d, 'حَجم الخَطّ', 'Font size'), style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  ChoiceChip(
                    label: Text(tx(d, 'حَجم الجُزء', 'Part size')),
                    selected: size == null,
                    onSelected: (_) => s2(() => size = null),
                  ),
                  for (final e in kTicketSizes.entries)
                    ChoiceChip(
                      label: Text(tx(d, e.value.$1, e.value.$2)),
                      selected: size == e.key,
                      onSelected: (_) => s2(() => size = e.key),
                    ),
                ]),
                const SizedBox(height: 14),
                Text(tx(d, 'سُمك الخَطّ', 'Weight'), style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                SegmentedButton<int>(
                  segments: [
                    ButtonSegment(value: 0, label: Text(tx(d, 'تِلقائيّ', 'Auto'))),
                    ButtonSegment(value: 1, label: Text(tx(d, 'عَريض', 'Bold')), icon: const Icon(Icons.format_bold)),
                    ButtonSegment(value: 2, label: Text(tx(d, 'عاديّ', 'Regular'))),
                  ],
                  selected: {st['bold'] == true ? 1 : (st['bold'] == false ? 2 : 0)},
                  onSelectionChanged: (v) => s2(() => v.first == 0 ? st.remove('bold') : st['bold'] = v.first == 1),
                ),
                const SizedBox(height: 14),
                Text(tx(d, 'نَوع الخَطّ', 'Font'), style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  ChoiceChip(
                    label: Text(tx(d, 'خَطّ الطابِعة', 'Printer font')),
                    selected: (st['font'] ?? '') == '',
                    onSelected: (_) => s2(() => st.remove('font')),
                  ),
                  for (final e in kTicketFonts.entries)
                    ChoiceChip(
                      label: Text(tx(d, e.value.$1, e.value.$2), style: e.value.$3()),
                      selected: st['font'] == e.key,
                      onSelected: (_) => s2(() => st['font'] = e.key),
                    ),
                ]),
                const SizedBox(height: 8),
                Text(
                  tx(d, 'خَطّ الطابِعة بِالحَجم العاديّ أَو الكَبير جِدّاً هو الأَسرَع. غَيرُه يُطبَع كَصورة.',
                      'The printer font in Normal or X-large prints fastest; anything else prints as a picture.'),
                  style: const TextStyle(color: VC.muted, fontSize: 11.5),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tx(d, 'إلغاء', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(tx(d, 'حِفظ', 'Save'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    set(() {
      if (hasWords) {
        final w = c.text.trim();
        w.isEmpty || w == doc.labels[k] ? labels.remove(k) : labels[k] = w;
      }
      size == null ? sizes.remove(k) : sizes[k] = size!;
      st.isEmpty ? styles.remove(k) : styles[k] = st;
    });
  }

  // small badge with the line's size (+ B / font), opens the line dialog
  Widget styleButton(BuildContext ctx, String k, void Function(void Function()) set) {
    final own = sizes.containsKey(k) || styles.containsKey(k) || labels.containsKey(k);
    final f = '${styles[k]?['font'] ?? ''}';
    final tag = [
      ticketSizeOf(look(), k).toUpperCase(),
      if (styles[k]?['bold'] == true) 'B',
      if (f.isNotEmpty) kTicketFonts[f]?.$2.split(' ').first ?? f,
    ].join(' · ');
    return Tooltip(
      message: tx(ctx, 'النَصّ وَالحَجم وَنَوع الخَطّ', 'Text, size and font'),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => editLine(ctx, k, set),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: (own ? VC.gold : VC.muted).withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.text_fields, size: 14, color: own ? VC.gold : VC.muted),
            const SizedBox(width: 4),
            Text(tag, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: own ? VC.gold : VC.muted)),
          ]),
        ),
      ),
    );
  }

  Map<String, dynamic> current() => {
        ...part,
        'title': title.text.trim().toUpperCase(),
        'footer': footer.text.trim(),
        'header': header,
        'header_logo': headerLogo,
        'font': font,
        'sizes': {
          for (final e in sizes.entries)
            if (items.contains(e.key) || e.key == 'header' || e.key == 'footer') e.key: e.value
        },
        'styles': {
          for (final e in styles.entries)
            if (items.contains(e.key) || e.key == 'header' || e.key == 'footer') e.key: e.value
        },
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
      final others = doc.items.keys.where((k) => kRepeatItems.contains(k) || !items.contains(k)).toList();
      final editor = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: title,
          onChanged: (_) => set(() {}),
          decoration: InputDecoration(labelText: tx(ctx, 'العُنوان المَطبوع', 'Printed title'), hintText: doc.defaultTitle),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: header,
          onChanged: (v) => set(() => header = v),
          title: Text(tx(ctx, 'رَأس الجُزء: اسم الشَرِكة + النُقطة + العُنوان', 'Part header: company + point + title')),
          subtitle: Text(tx(ctx, 'أَطفِئه لِتَضَع اللوجو أَو الأَسماء بِتَرتيبك', 'Switch off to place the logo / names in your own order'),
              style: const TextStyle(fontSize: 12)),
        ),
        if (header) ...[
          Text(tx(ctx, 'اللوجو أَعلى الجُزء', 'Logo on top of the part'), style: const TextStyle(color: VC.muted, fontSize: 12.5)),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final o in const [
              ('auto', 'المَرفوع تِلقائيّاً', 'Uploaded logos'),
              ('company', 'الشَرِكة', 'Company'),
              ('point', 'النُقطة', 'Point'),
              ('both', 'الاِتنين', 'Both'),
              ('none', 'بِدون', 'None'),
            ])
              ChoiceChip(
                label: Text(tx(ctx, o.$2, o.$3)),
                selected: headerLogo == o.$1,
                onSelected: (_) => set(() => headerLogo = o.$1),
              ),
          ]),
        ],
        const SizedBox(height: 10),
        Row(children: [
          Text(tx(ctx, 'حَجم الخَطّ لِلجُزء', 'Font size of the part'), style: const TextStyle(color: VC.muted, fontSize: 12.5)),
          const Spacer(),
          if (header) ...[
            Text(tx(ctx, 'الرَأس', 'Header'), style: const TextStyle(color: VC.muted, fontSize: 12.5)),
            styleButton(ctx, 'header', set),
          ],
        ]),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final e in kTicketSizes.entries)
            ChoiceChip(
              label: Text(tx(ctx, e.value.$1, e.value.$2)),
              selected: font == e.key,
              onSelected: (_) => set(() => font = e.key),
            ),
        ]),
        const SizedBox(height: 4),
        Text(
          tx(ctx, 'لِكُلّ سَطر حَجم خاصّ مِن الزِرّ بِجانِبه. العاديّ وَالكَبير جِدّاً بِخَطّ الطابِعة، وَالباقي يُطبَع كَصورة.',
              'Each line can have its own size (button next to it). Normal and X-large use the printer font, the others print as a picture.'),
          style: const TextStyle(color: VC.muted, fontSize: 11.5),
        ),
        const SizedBox(height: 10),
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
                Text(_itemName(ctx, items[i], texts, doc), maxLines: 2, overflow: TextOverflow.ellipsis),
                if (labels[items[i]] != null)
                  Text('“${labels[items[i]]}”', style: const TextStyle(color: VC.gold, fontSize: 12, fontWeight: FontWeight.w700)),
              ]),
            ),
            if (!const {'blank', 'divider'}.contains(items[i]) && !items[i].startsWith('logo')) styleButton(ctx, items[i], set),
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
              label: Text(tx(ctx, doc.items[k]!.$1, doc.items[k]!.$2)),
              onPressed: () => set(() => items.add(k)),
            ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: TextField(
              controller: footer,
              maxLines: 2,
              onChanged: (_) => set(() {}),
              decoration: InputDecoration(
                labelText: tx(ctx, 'نَصّ في آخِر الجُزء (اختياريّ)', 'Text at the end of the part (optional)'),
                hintText: tx(ctx, 'مِثال: الشَرِكة غَير مَسؤولة عَن المُقتَنَيات', 'e.g. We are not responsible for valuables'),
              ),
            ),
          ),
          styleButton(ctx, 'footer', set),
        ]),
      ]);
      final preview = Column(children: [
        Text(tx(ctx, 'المُعايَنة (وَرَق 58 مم)', 'Preview (58 mm paper)'), style: const TextStyle(color: VC.muted, fontSize: 12)),
        const SizedBox(height: 6),
        TicketPreview(part: current(), logos: logos, pointName: pointName, doc: doc),
      ]);
      return AlertDialog(
        title: Text(tx(ctx, doc.name.$1, doc.name.$2)),
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
              if (title.text.trim().isEmpty) title.text = doc.defaultTitle;
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
  const TicketPreview({super.key, required this.part, required this.logos, this.pointName = '', this.doc = kDocTicket});
  final Map<String, dynamic> part;
  final TicketLogos logos;
  final String pointName;
  final PrintDoc doc;

  static const _w = 300.0; // 384 dots
  static const _k = _w / 384; // preview px per printer dot

  @override
  Widget build(BuildContext context) {
    final labels = (part['labels'] as Map?)?.cast<String, dynamic>() ?? const {};
    final texts = (part['texts'] as Map?)?.cast<String, dynamic>() ?? const {};
    String lb(String k) => '${labels[k] ?? doc.labels[k] ?? kItemLabels[k] ?? k}';
    // word i of an 'a|b|c' wording
    String wd(String k, int i, String d) {
      final w = lb(k).split('|');
      return i < w.length && w[i].trim().isNotEmpty ? w[i].trim() : d;
    }

    final styles = (part['styles'] as Map?)?.cast<String, dynamic>() ?? const {};
    const base = TextStyle(fontFamily: 'monospace', fontSize: 12.5, color: Colors.black, height: 1.3);
    TextStyle st(String k, {bool b = false}) {
      final z = ticketSizeOf(part, k);
      final own = (styles[k] as Map?) ?? const {};
      final f = kTicketFonts['${own['font'] ?? ''}'];
      final bold = own['bold'] is bool ? own['bold'] as bool : (b || z == 'xl' || z == 'xxl');
      final style = base.copyWith(fontSize: kTicketSizes[z]!.$3 * _k, fontWeight: bold ? FontWeight.w800 : FontWeight.w400);
      return f == null ? style : f.$3().merge(style.copyWith(fontFamily: f.$3().fontFamily));
    }

    Widget row(String k, List<String> cells, List<int> w, {bool b = false}) => Row(children: [
          for (var i = 0; i < cells.length; i++)
            Expanded(
              flex: w[i],
              child: Text(cells[i],
                  textAlign: i == 0 ? TextAlign.left : TextAlign.right,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: st(k, b: b)),
            ),
        ]);

    final out = <Widget>[];
    Widget c(String t, String k, {bool b = false}) => Center(child: Text(t, textAlign: TextAlign.center, style: st(k, b: b)));
    // an Arabic label is printed on the right (as the app prints it)
    Widget pair(String k, String l, String r, {bool b = false}) => Directionality(
          textDirection: _arabic.hasMatch(l) ? TextDirection.rtl : TextDirection.ltr,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text(l, style: st(k, b: b))),
            Text(r, style: st(k, b: b), textDirection: TextDirection.ltr),
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

    final all = [for (final i in part['items'] as List) '$i'];
    // logo lines at the start of the list print above the header (company details)
    final lead = all.takeWhile((k) => k.startsWith('logo_')).toList();
    if (part['header'] != false) {
      // logo on top: 'auto' = the uploaded ones (both side by side), unless the list starts with its own logo lines;
      // the company name is printed when no company logo is printed
      var hl = '${part['header_logo'] ?? 'auto'}';
      if (lead.isNotEmpty && hl == 'auto') hl = 'none';
      final co = hl == 'auto' || hl == 'company' || hl == 'both' ? logos.company : null;
      final pt = hl == 'auto' || hl == 'point' || hl == 'both' ? logos.point : null;
      if (co != null && pt != null) {
        out.add(Row(children: [Expanded(child: logo(co, h: 56)), const SizedBox(width: 8), Expanded(child: logo(pt, h: 56))]));
      } else if (co != null || pt != null) {
        out.add(logo(co ?? pt));
      }
      final leadCompany = logos.company != null && lead.any((k) => k == 'logo_company' || k == 'logo_both');
      if (co == null && !leadCompany) out.add(c('VIP Valet', 'header', b: true));
      out
        ..add(c(pointName.isEmpty ? 'POINT NAME' : pointName, 'header', b: true))
        ..add(c('${part['title']}'.isEmpty ? doc.defaultTitle : '${part['title']}', 'header'))
        ..add(dash());
    }
    // the header goes after the leading logo lines
    final head = [...out];
    out.clear();
    final headAt = part['header'] != false ? lead.length : 0;
    var n = 0;
    // payment receipt / shift report lines (sample data); true when [k] is one of them
    bool docLine(String k) {
      if (doc.id == 'receipt') {
        switch (k) {
          case 'number':
            out.add(c('${lb(k)} 0042', k, b: true));
          case 'code':
            out.add(c('T-0042-BEI-26', k));
          case 'plate':
            out.add(pair(k, lb(k), 'D 12345'));
          case 'ticket':
            out.add(pair(k, lb(k), 'Standard'));
          case 'time_in':
            out.add(pair(k, lb(k), '23/10/2026 19:05'));
          case 'time_out':
            out.add(pair(k, lb(k), '23/10/2026 21:15'));
          case 'duration':
            out.add(pair(k, lb(k), '2h 10m'));
          case 'price':
            out
              ..add(pair(k, wd(k, 0, 'Price'), '23.81'))
              ..add(pair(k, '${wd(k, 1, 'VAT')} 5%', '1.19'))
              ..add(pair(k, wd(k, 2, 'Total'), '25.00', b: true));
          case 'extras':
            out
              ..add(pair(k, wd(k, 0, 'Overnight'), '50.00'))
              ..add(pair(k, wd(k, 2, 'Tips'), '5.00'))
              ..add(pair(k, wd(k, 3, 'Grand total'), '80.00 AED', b: true));
          case 'payment':
            out.add(pair(k, lb(k), 'Cash'));
          case 'grace':
            out.add(c(lb(k).replaceAll('{min}', '10'), k, b: true));
          case 'card_ref':
            out.add(pair(k, lb(k), '458213'));
          case 'paid_change':
            out
              ..add(pair(k, wd(k, 0, 'Paid'), '100.00'))
              ..add(pair(k, wd(k, 1, 'Change'), '20.00'));
          case 'thanks':
            out.add(c(lb(k), k, b: true));
          default:
            return false;
        }
        return true;
      }
      if (doc.id == 'shift') {
        switch (k) {
          case 'shift':
            out.add(pair(k, lb(k), 'VS-0042', b: true));
          case 'closed_by':
            out.add(pair(k, lb(k), 'AE-V-866'));
          case 'start':
            out.add(pair(k, lb(k), '23/10/2026 07:00'));
          case 'end':
            out.add(pair(k, lb(k), '23/10/2026 15:00'));
          case 'cars':
            out
              ..add(pair(k, wd(k, 0, 'Total cars'), '64'))
              ..add(pair(k, wd(k, 1, 'From previous'), '3'))
              ..add(pair(k, wd(k, 2, 'Closed tickets'), '60'))
              ..add(pair(k, wd(k, 3, 'Pending cars'), '7', b: true));
          case 'tickets_range':
            out
              ..add(pair(k, wd(k, 0, 'First ticket'), '0042'))
              ..add(pair(k, wd(k, 1, 'Last ticket'), '0105'));
          case 'payments':
            out
              ..add(row(
                  k,
                  [
                    for (var i = 0; i < 4; i++) wd(k, i, const ['Payment', 'Cnt', 'Total', 'Tips'][i])
                  ],
                  [4, 2, 3, 3],
                  b: true))
              ..add(row(k, ['Cash', '40', '1000.00', '60.00'], [4, 2, 3, 3]))
              ..add(row(k, ['C-Card', '20', '500.00', '25.00'], [4, 2, 3, 3]));
          case 'types':
            out
              ..add(row(
                  k,
                  [
                    for (var i = 0; i < 3; i++) wd(k, i, const ['Ticket type', 'Cnt', 'Total'][i])
                  ],
                  [6, 2, 4],
                  b: true))
              ..add(row(k, ['Standard', '50', '1250.00'], [6, 2, 4]))
              ..add(row(k, ['VIP', '10', '250.00'], [6, 2, 4]));
          case 'tips':
            out
              ..add(pair(k, '${wd(k, 0, 'Cash tips')} (12)', '60.00'))
              ..add(pair(k, '${wd(k, 1, 'Card tips')} (5)', '25.00'));
          case 'totals':
            out
              ..add(pair(k, wd(k, 0, 'Total sales'), '1500.00', b: true))
              ..add(pair(k, wd(k, 1, 'Tips'), '85.00'))
              ..add(pair(k, wd(k, 2, 'Total with tips'), '1585.00 AED', b: true));
          case 'machines':
            out
              ..add(dash())
              ..add(Text(lb(k), style: st(k, b: true)))
              ..add(Text('1454547', style: st(k)));
          case 'cash':
            out
              ..add(dash())
              ..add(pair(k, wd(k, 0, 'Cash expected'), '1060.00'))
              ..add(pair(k, wd(k, 1, 'Cash counted'), '1050.00', b: true))
              ..add(pair(k, wd(k, 3, 'SHORT'), '-10.00', b: true));
          case 'signature':
            out
              ..add(const SizedBox(height: 16))
              ..add(pair(k, lb(k), '__________'));
          default:
            return false;
        }
        return true;
      }
      return false;
    }

    for (final k in all) {
      if (n++ == headAt) out.addAll(head);
      if (docLine(k)) continue;
      switch (k) {
        case 'number':
          out.add(c('${lb('number')} 0042', k, b: true));
        case 'code':
          out.add(c('T-0042-BEI-26', k));
        case 'plate':
          out.add(pair(k, lb('plate'), 'D 12345', b: true));
        case 'plate_big':
          out.add(c('D 12345', k, b: true));
        case 'color':
          out.add(pair(k, lb('color'), 'White'));
        case 'vehicle':
          out.add(pair(k, lb('vehicle'), 'Sedan'));
        case 'customer':
          out.add(pair(k, lb('customer'), 'Visitor'));
        case 'type':
          out.add(pair(k, lb('type'), 'Standard'));
        case 'mode':
          out.add(pair(k, lb('mode'), 'TICKET'));
        case 'card':
          out.add(pair(k, lb('card'), 'C-118'));
        case 'time_in':
          out.add(pair(k, lb('time_in'), '23/10/2026 21:15'));
        case 'time_big':
          out.add(c('23/10/2026 21:15', k));
        case 'price':
          final w = lb('price').split('|');
          String at(int i, String d) => i < w.length && w[i].trim().isNotEmpty ? w[i].trim() : d;
          out
            ..add(dash())
            ..add(pair(k, at(0, 'Price'), '23.81'))
            ..add(pair(k, '${at(1, 'VAT')} 5%', '1.19'))
            ..add(pair(k, at(2, 'Total'), '25.00 AED', b: true));
        case 'qr':
          out
            ..add(const SizedBox(height: 6))
            ..add(const Center(child: Icon(Icons.qr_code_2, size: 96, color: Colors.black)))
            ..add(c(lb('qr'), k));
        case 'received_by':
          out.add(pair(k, lb('received_by'), '__________'));
        case 'delivered_by':
          out.add(pair(k, lb('delivered_by'), '__________'));
        case 'parking':
          out.add(pair(k, lb('parking'), '__________'));
        case 'signature':
          out
            ..add(const SizedBox(height: 16))
            ..add(pair(k, lb('signature'), '__________'));
        case 'notes':
          out.add(pair(k, lb('notes'), 'Scratch on the left door'));
        case 'damage':
          out
            ..add(const AspectRatio(aspectRatio: 384 / 200, child: CustomPaint(painter: _DamagePainter({'3', '7', '12'}))))
            ..add(pair(k, wd(k, 0, 'Damage'), '3, 7, 12', b: true));
        case 'company_name':
          out.add(c('VIP Valet', k, b: true));
        case 'point_name':
          out.add(c(pointName.isEmpty ? 'POINT NAME' : pointName, k, b: true));
        case 'part_title':
          out.add(c('${part['title']}', k));
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
            final a = switch ('${t['align']}') { 'left' => TextAlign.left, 'right' => TextAlign.right, _ => TextAlign.center };
            out.add(SizedBox(width: double.infinity, child: Text('${t['text'] ?? ''}', textAlign: a, style: st(k, b: t['bold'] == true))));
          }
      }
    }
    if (n <= headAt) out.addAll(head); // only logo lines
    final f = '${part['footer'] ?? ''}'.trim();
    if (f.isNotEmpty) {
      out
        ..add(dash())
        ..add(c(f, 'footer'));
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

/// Damage points of the valet app (car seen from above, front on the left).
const Map<String, Offset> _kDamagePos = {
  '1': Offset(-0.80, 0.0),
  '2': Offset(-0.52, 0.0),
  '3': Offset(0.02, 0.0),
  '4': Offset(0.52, 0.0),
  '5': Offset(0.80, 0.0),
  '6': Offset(-0.36, 0.62),
  '7': Offset(-0.13, 0.62),
  '8': Offset(0.11, 0.62),
  '9': Offset(0.41, 0.58),
  '10': Offset(-0.36, -0.62),
  '11': Offset(-0.13, -0.62),
  '12': Offset(0.11, -0.62),
  '13': Offset(0.41, -0.58),
  '14': Offset(-0.50, -0.90),
  '15': Offset(0.48, -0.90),
  '16': Offset(0.48, 0.90),
  '17': Offset(-0.50, 0.90),
};

/// Same drawing as the printed one (vip_valet TicketRaster.damage).
class _DamagePainter extends CustomPainter {
  const _DamagePainter(this.marked);
  final Set<String> marked;

  @override
  void paint(Canvas c, Size size) {
    final k = size.width / 384;
    final w = size.width;
    final top = 8 * k, ch = size.height - 16 * k;
    Offset p(double ax, double ay) => Offset(w / 2 + ax * (w - 24 * k) / 2, top + ch / 2 + ay * ch / 2);
    final black = Paint()..color = Colors.black;
    final line = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5 * k;
    final thin = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 * k;
    for (final ax in [-0.50, 0.48]) {
      for (final ay in [-0.80, 0.80]) {
        c.drawRRect(
            RRect.fromRectAndRadius(Rect.fromCenter(center: p(ax, ay), width: w * 0.15, height: ch * 0.13), Radius.circular(5 * k)), black);
      }
    }
    final body = RRect.fromRectAndCorners(Rect.fromPoints(p(-0.92, -0.74), p(0.92, 0.74)),
        topLeft: Radius.circular(ch * 0.32),
        bottomLeft: Radius.circular(ch * 0.32),
        topRight: Radius.circular(ch * 0.18),
        bottomRight: Radius.circular(ch * 0.18));
    c.drawRRect(body, Paint()..color = Colors.white);
    c.drawRRect(body, line);
    c.drawPath(Path()..addPolygon([p(-0.38, -0.58), p(-0.24, -0.50), p(-0.24, 0.50), p(-0.38, 0.58)], true), thin);
    c.drawPath(Path()..addPolygon([p(0.60, -0.52), p(0.48, -0.46), p(0.48, 0.46), p(0.60, 0.52)], true), thin);
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromPoints(p(-0.22, -0.48), p(0.46, 0.48)), Radius.circular(6 * k)), thin);
    for (final ax in [-0.24, 0.0, 0.26]) {
      c.drawLine(p(ax, -0.74), p(ax, -0.50), thin);
      c.drawLine(p(ax, 0.50), p(ax, 0.74), thin);
    }
    TextPainter tp(String t, Color col, double fs, FontWeight fw) =>
        TextPainter(text: TextSpan(text: t, style: TextStyle(color: col, fontSize: fs, fontWeight: fw)), textDirection: TextDirection.ltr)
          ..layout();
    final f = tp('FRONT', Colors.black, 13 * k, FontWeight.w700);
    c.save();
    c.translate(2 * k, top + ch / 2 + f.width / 2);
    c.rotate(-1.5708);
    f.paint(c, Offset.zero);
    c.restore();
    for (final e in _kDamagePos.entries) {
      final o = p(e.value.dx, e.value.dy);
      if (marked.contains(e.key)) {
        c.drawCircle(o, 15 * k, black);
        final t = tp(e.key, Colors.white, 15 * k, FontWeight.w900);
        t.paint(c, o - Offset(t.width / 2, t.height / 2));
      } else {
        c.drawCircle(o, 9 * k, Paint()..color = Colors.white);
        c.drawCircle(o, 9 * k, thin);
        final t = tp(e.key, Colors.black, 10 * k, FontWeight.w400);
        t.paint(c, o - Offset(t.width / 2, t.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DamagePainter old) => old.marked != marked;
}
