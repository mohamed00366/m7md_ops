import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'valet_admin.dart';
import 'valet_hub_ui.dart';
import 'valet_ui.dart';

/// 🎨 تصميم كارت الـ NFC (DB 315): صورة الوش والضهر + مكان رقم الكارت والـ QR، ومعاينة، وتحميل / طباعة PDF.
/// تصميم واحد لكل النقاط، و«أوبشن» تصميم خاص للنقطة.

const _ink = Color(0xFF0B0C0E);
const _line = Color(0xFFE2E8F0);
const _muted = Color(0xFF64748B);

/// CR80 – the size of a bank card.
const kCardW = 85.6, kCardH = 54.0;

String cardLinkOf(String code) => 'https://vip-valet-uae.app/RequestCar?ticket=${Uri.encodeQueryComponent(code)}';

/// Where the number / QR go on the card (fractions of the card: x, y = centre).
class CardLayout {
  CardLayout(Map<String, dynamic> j)
      : numSide = _side(j['num_side'], 'front'),
        numX = _f(j['num_x'], 0.84),
        numY = _f(j['num_y'], 0.78),
        numSize = _f(j['num_size'], 0.22),
        numWhite = j['num_white'] == true,
        numBox = j['num_box'] != false,
        numPrefix = vStr(j['num_prefix']),
        qrSide = _side(j['qr_side'], 'back'),
        qrX = _f(j['qr_x'], 0.5),
        qrY = _f(j['qr_y'], 0.5),
        qrSize = _f(j['qr_size'], 0.5),
        qrCode = j['qr_code'] != false,
        landscape = j['portrait'] != true;

  String numSide, qrSide, numPrefix;
  double numX, numY, numSize, qrX, qrY, qrSize;
  bool numWhite, numBox, qrCode, landscape;

  static String _side(dynamic v, String d) => const {'front', 'back', 'none'}.contains(vStr(v)) ? vStr(v) : d;
  static double _f(dynamic v, double d) => v is num ? v.toDouble().clamp(0.0, 1.0) : d;

  Map<String, dynamic> toJson() => {
        'num_side': numSide, 'num_x': numX, 'num_y': numY, 'num_size': numSize, 'num_white': numWhite, 'num_box': numBox,
        'num_prefix': numPrefix, 'qr_side': qrSide, 'qr_x': qrX, 'qr_y': qrY, 'qr_size': qrSize, 'qr_code': qrCode, 'portrait': !landscape,
      };

  double get w => landscape ? kCardW : kCardH;
  double get h => landscape ? kCardH : kCardW;
}

class CardDesign {
  CardDesign(Map<String, dynamic>? j)
      : front = _img(j?['front']),
        back = _img(j?['back']),
        layout = CardLayout(Map<String, dynamic>.from((j?['layout'] as Map?) ?? {}));
  Uint8List? front, back;
  CardLayout layout;

  static Uint8List? _img(dynamic v) {
    final s = vStr(v);
    if (s.isEmpty) return null;
    try {
      return base64Decode(s.contains(',') ? s.split(',').last : s);
    } catch (_) {
      return null;
    }
  }
}

/// Picture → max 1400 px, JPEG 90 (≈ 300 dpi on a card), base64.
String? cardPictureBase64(Uint8List bytes) {
  var im = img.decodeImage(bytes);
  if (im == null) return null;
  final big = im.width > im.height ? im.width : im.height;
  if (big > 1400) {
    final s = 1400 / big;
    im = img.copyResize(im, width: (im.width * s).round(), height: (im.height * s).round(), interpolation: img.Interpolation.average);
  }
  final flat = img.Image(width: im.width, height: im.height);
  img.fill(flat, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(flat, im);
  return base64Encode(img.encodeJpg(flat, quality: 90));
}

// ================================================================ panel in the NFC cards tab

class CardDesignPanel extends StatefulWidget {
  const CardDesignPanel({super.key, required this.pointId, required this.pointName, required this.cards, this.edit = true});
  final String pointId;
  final String pointName;
  final List<VJson> cards;
  final bool edit;

  @override
  State<CardDesignPanel> createState() => _CardDesignPanelState();
}

class _CardDesignPanelState extends State<CardDesignPanel> {
  VJson? _d;
  Object? _err;
  bool _ownMode = false; // editing the own design of this point (else: all points)
  CardDesign? _cur;
  bool _dirty = false;
  bool _back = false; // preview side

  String get _scope => _ownMode ? widget.pointId : 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await ValetAdmin.I.call('vva_card_design', {'p_point': widget.pointId});
      if (!mounted) return;
      setState(() {
        _d = d;
        _err = null;
        _ownMode = d['own'] == true;
        _cur = CardDesign((_ownMode ? d['point'] : d['all']) as Map<String, dynamic>?);
        _dirty = false;
      });
    } catch (e) {
      if (mounted) setState(() => _err = e);
    }
  }

  void _switchScope(bool own) {
    final d = _d;
    if (d == null) return;
    setState(() {
      _ownMode = own;
      final src = own ? (d['point'] ?? d['all']) : d['all'];
      _cur = CardDesign(src as Map<String, dynamic>?);
      _dirty = own && d['own'] != true; // a new own design starts as a copy of "all points"
    });
  }

  Future<void> _pick(String side) async {
    final f = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final bytes = f?.files.single.bytes;
    if (bytes == null || !mounted) return;
    final b64 = cardPictureBase64(bytes);
    if (b64 == null) {
      vToast(context, tx(context, 'تعذّر قراءة الصورة', 'Could not read the picture'), error: true);
      return;
    }
    // a new own design: copy the other side + layout from "all points" first
    if (_ownMode && _d?['own'] != true) await _saveLayout(silent: true, withPictures: true);
    if (!mounted) return;
    final r = await vGuard(context, () => ValetAdmin.I.call('vva_card_design_save', {'p_scope': _scope, 'p_side': side, 'p_image': b64}),
        ok: tx(context, 'تم رفع الصورة', 'Picture uploaded'));
    if (r != null) await _load();
    if (mounted && _ownMode != (_d?['own'] == true)) _switchScope(_ownMode);
  }

  Future<void> _remove(String side) async {
    final r = await vGuard(context, () => ValetAdmin.I.call('vva_card_design_save', {'p_scope': _scope, 'p_side': side, 'p_image': null}),
        ok: tx(context, 'تم الحذف', 'Removed'));
    if (r != null) _load();
  }

  Future<void> _saveLayout({bool silent = false, bool withPictures = false}) async {
    final c = _cur;
    if (c == null) return;
    Future<VJson> save() async {
      if (withPictures) {
        for (final (side, b) in [('front', c.front), ('back', c.back)]) {
          if (b != null) await ValetAdmin.I.call('vva_card_design_save', {'p_scope': _scope, 'p_side': side, 'p_image': base64Encode(b)});
        }
      }
      return ValetAdmin.I.call('vva_card_design_save', {'p_scope': _scope, 'p_layout': c.layout.toJson()});
    }

    if (silent) {
      await save();
      return;
    }
    final r = await vGuard(context, save, ok: tx(context, 'تم حفظ التصميم', 'Design saved'));
    if (r != null) _load();
  }

  Future<void> _deleteOwn() async {
    if (!await vConfirm(context, tx(context, 'حذف تصميم النقطة', 'Remove the point design'),
        tx(context, 'النقطة هترجع تستخدم تصميم كل النقاط.', 'The point goes back to the design of all points.'))) {
      return;
    }
    if (!mounted) return;
    final r = await vGuard(context, () => ValetAdmin.I.call('vva_card_design_save', {'p_scope': widget.pointId, 'p_action': 'delete'}));
    if (r != null) _load();
  }

  void _l(void Function(CardLayout l) f) => setState(() {
        f(_cur!.layout);
        _dirty = true;
      });

  @override
  Widget build(BuildContext context) {
    if (_err != null && _d == null) return HubCard(child: Text(vErr(context, _err!)));
    final c = _cur;
    if (c == null) return const HubCard(child: Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator())));
    final l = c.layout;
    final sample = widget.cards.isEmpty ? <String, dynamic>{'card_no': 38, 'code': 'VLT-038-7KQ2XW'} : widget.cards.first;
    return HubCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, alignment: WrapAlignment.spaceBetween, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.palette_outlined),
            const SizedBox(width: 8),
            Text(tx(context, 'تصميم الكارت (وش وضهر)', 'Card design (front & back)'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ]),
          Wrap(spacing: 8, runSpacing: 8, children: [
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: false, label: Text(tx(context, 'تصميم كل النقاط', 'All points design'))),
                ButtonSegment(value: true, label: Text(tx(context, 'تصميم خاص بالنقطة دي', 'Own design of this point'))),
              ],
              selected: {_ownMode},
              onSelectionChanged: widget.edit ? (v) => _switchScope(v.first) : null,
            ),
            if (widget.edit) FilledButton.icon(onPressed: _dirty ? () => _saveLayout(withPictures: _ownMode && _d?['own'] != true) : null, icon: const Icon(Icons.save_outlined), label: Text(tx(context, 'حفظ', 'Save'))),
            HubButton(label: tx(context, 'تحميل / طباعة الكروت', 'Download / print cards'), icon: Icons.print_outlined, primary: true, onPressed: widget.cards.isEmpty ? null : _printDialog),
          ]),
        ]),
        const SizedBox(height: 4),
        Text(
            _ownMode
                ? tx(context, 'النقطة دي بتستخدم تصميمها الخاص. احذفه عشان ترجع لتصميم كل النقاط.', 'This point uses its own design. Remove it to go back to the design of all points.')
                : tx(context, 'التصميم ده لكل النقاط اللي ملهاش تصميم خاص.', 'This design is used by every point without its own design.'),
            style: const TextStyle(color: _muted, fontSize: 12.5)),
        if (_ownMode && _d?['own'] == true && widget.edit)
          Align(alignment: AlignmentDirectional.centerStart, child: TextButton.icon(onPressed: _deleteOwn, icon: const Icon(Icons.undo, size: 18), label: Text(tx(context, 'رجوع لتصميم كل النقاط', 'Back to the all points design')))),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth > 900;
          final preview = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              for (final (side, ar, en) in [('front', 'الوش', 'Front'), ('back', 'الضهر', 'Back')])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(end: 10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      InkWell(
                        onTap: () => setState(() => _back = side == 'back'),
                        child: Container(
                          decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: (_back == (side == 'back')) ? _ink : _line, width: (_back == (side == 'back')) ? 2 : 1)),
                          padding: const EdgeInsets.all(4),
                          child: CardFace(design: c, back: side == 'back', no: vNum(sample['card_no']).toInt(), code: vStr(sample['code'])),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(children: [
                        Text(tx(context, ar, en), style: const TextStyle(fontWeight: FontWeight.w800)),
                        const Spacer(),
                        if (widget.edit) TextButton.icon(onPressed: () => _pick(side), icon: const Icon(Icons.upload_outlined, size: 18), label: Text(tx(context, 'رفع صورة', 'Upload'))),
                        if (widget.edit && (side == 'front' ? c.front : c.back) != null)
                          IconButton(tooltip: tx(context, 'حذف', 'Remove'), onPressed: () => _remove(side), icon: const Icon(Icons.delete_outline, size: 18)),
                      ]),
                    ]),
                  ),
                ),
            ]),
            Text(tx(context, 'المقاس: كارت بنكي $kCardW × $kCardH مم · ارفع صورة بنفس النسبة (مثلاً 1011 × 638 بكسل) — الصورة بتتصغّر لوحدها.',
                    'Size: bank card $kCardW × $kCardH mm · upload a picture with the same ratio (e.g. 1011 × 638 px) — it is made smaller by itself.'),
                style: const TextStyle(color: _muted, fontSize: 12)),
          ]);
          final controls = _controls(l);
          return wide
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 6, child: preview), const SizedBox(width: 18), Expanded(flex: 5, child: controls)])
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [preview, const SizedBox(height: 14), controls]);
        }),
      ]),
    );
  }

  Widget _controls(CardLayout l) {
    Widget side(String label, String value, ValueChanged<String> on) => Row(children: [
          SizedBox(width: 110, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
          Expanded(
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 'front', label: Text(tx(context, 'الوش', 'Front'))),
                ButtonSegment(value: 'back', label: Text(tx(context, 'الضهر', 'Back'))),
                ButtonSegment(value: 'none', label: Text(tx(context, 'بدون', 'None'))),
              ],
              selected: {value},
              onSelectionChanged: widget.edit ? (v) => on(v.first) : null,
            ),
          ),
        ]);
    Widget slider(String label, double v, ValueChanged<double> on, {double min = 0, double max = 1}) => Row(children: [
          SizedBox(width: 110, child: Text(label, style: const TextStyle(fontSize: 12.5, color: _muted))),
          Expanded(child: Slider(value: v.clamp(min, max), min: min, max: max, onChanged: widget.edit ? on : null)),
        ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: [
          ButtonSegment(value: true, icon: const Icon(Icons.crop_landscape), label: Text(tx(context, 'عرضي', 'Landscape'))),
          ButtonSegment(value: false, icon: const Icon(Icons.crop_portrait), label: Text(tx(context, 'طولي', 'Portrait'))),
        ],
        selected: {l.landscape},
        onSelectionChanged: widget.edit ? (v) => _l((x) => x.landscape = v.first) : null,
      ),
      const Divider(height: 22),
      side(tx(context, 'رقم الكارت', 'Card number'), l.numSide, (v) => _l((x) => x.numSide = v)),
      if (l.numSide != 'none') ...[
        slider(tx(context, 'يمين / شمال', 'Left / right'), l.numX, (v) => _l((x) => x.numX = v)),
        slider(tx(context, 'فوق / تحت', 'Up / down'), l.numY, (v) => _l((x) => x.numY = v)),
        slider(tx(context, 'الحجم', 'Size'), l.numSize, (v) => _l((x) => x.numSize = v), min: 0.08, max: 0.6),
        Wrap(spacing: 8, runSpacing: 6, children: [
          FilterChip(label: Text(tx(context, 'خلفية بيضا', 'White box')), selected: l.numBox, onSelected: widget.edit ? (v) => _l((x) => x.numBox = v) : null),
          FilterChip(label: Text(tx(context, 'رقم أبيض', 'White number')), selected: l.numWhite, onSelected: widget.edit ? (v) => _l((x) => x.numWhite = v) : null),
          SizedBox(
            width: 150,
            child: TextFormField(
              key: ValueKey('pre${_scope}_${_d.hashCode}'),
              initialValue: l.numPrefix,
              enabled: widget.edit,
              decoration: InputDecoration(isDense: true, labelText: tx(context, 'قبل الرقم (اختياري)', 'Before the number'), hintText: 'No.'),
              onChanged: (v) => _l((x) => x.numPrefix = v.trim()),
            ),
          ),
        ]),
      ],
      const Divider(height: 22),
      side('QR', l.qrSide, (v) => _l((x) => x.qrSide = v)),
      if (l.qrSide != 'none') ...[
        slider(tx(context, 'يمين / شمال', 'Left / right'), l.qrX, (v) => _l((x) => x.qrX = v)),
        slider(tx(context, 'فوق / تحت', 'Up / down'), l.qrY, (v) => _l((x) => x.qrY = v)),
        slider(tx(context, 'الحجم', 'Size'), l.qrSize, (v) => _l((x) => x.qrSize = v), min: 0.2, max: 0.9),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: l.qrCode,
          onChanged: widget.edit ? (v) => _l((x) => x.qrCode = v ?? true) : null,
          title: Text(tx(context, 'الكود الصغير تحت الـ QR', 'Small code under the QR')),
        ),
      ],
      Text(tx(context, 'الـ QR بيفتح نفس لينك الكارت — للعميل اللي موبايله مفيهوش NFC.', 'The QR opens the same link as the card — for phones without NFC.'),
          style: const TextStyle(color: _muted, fontSize: 12)),
    ]);
  }

  // ---------------------------------------------------------------- download / print

  Future<void> _printDialog() async {
    final cards = widget.cards.where((c) => vStr(c['status']) != 'replaced').toList()
      ..sort((a, b) => vNum(a['card_no']).compareTo(vNum(b['card_no'])));
    if (cards.isEmpty || _cur == null) return;
    final from = TextEditingController(text: '${vNum(cards.first['card_no']).toInt()}');
    final to = TextEditingController(text: '${vNum(cards.last['card_no']).toInt()}');
    var format = 'cr80';
    var sides = 'both';
    final go = await showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(tx(c, 'تحميل / طباعة الكروت · ${widget.pointName}', 'Download / print cards · ${widget.pointName}')),
          content: SizedBox(
            width: 520,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(tx(c, 'الطابعة', 'Printer'), style: const TextStyle(fontWeight: FontWeight.w800)),
              RadioListTile<String>(
                value: 'cr80', groupValue: format, onChanged: (v) => set(() => format = v!), contentPadding: EdgeInsets.zero,
                title: Text(tx(c, 'طابعة كروت (Evolis / Zebra …)', 'Card printer (Evolis / Zebra …)')),
                subtitle: Text(tx(c, 'كل صفحة = كارت بمقاسه · الوش وبعده الضهر (طباعة على الوجهين)', 'One card per page · front then back (duplex)')),
              ),
              RadioListTile<String>(
                value: 'a4', groupValue: format, onChanged: (v) => set(() => format = v!), contentPadding: EdgeInsets.zero,
                title: Text(tx(c, 'ورق A4 — 10 كروت في الصفحة', 'A4 paper — 10 cards per page')),
                subtitle: Text(tx(c, 'صفحة وشوش وبعدها صفحة ضهور معكوسة للطباعة على الوجهين، مع علامات القص', 'A page of fronts then a mirrored page of backs for duplex, with cut marks')),
              ),
              const SizedBox(height: 6),
              Text(tx(c, 'الوجه', 'Sides'), style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 'both', label: Text(tx(c, 'وش وضهر', 'Both'))),
                  ButtonSegment(value: 'front', label: Text(tx(c, 'الوش بس', 'Front only'))),
                  ButtonSegment(value: 'back', label: Text(tx(c, 'الضهر بس', 'Back only'))),
                ],
                selected: {sides},
                onSelectionChanged: (v) => set(() => sides = v.first),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: TextField(controller: from, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tx(c, 'من كارت', 'From card')))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: to, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tx(c, 'لحد كارت', 'To card')))),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: Text(tx(c, 'إلغاء', 'Cancel'))),
            OutlinedButton.icon(onPressed: () => Navigator.pop(c, 'download'), icon: const Icon(Icons.download), label: Text(tx(c, 'تحميل PDF', 'Download PDF'))),
            FilledButton.icon(onPressed: () => Navigator.pop(c, 'print'), icon: const Icon(Icons.print), label: Text(tx(c, 'طباعة', 'Print'))),
          ],
        ),
      ),
    );
    final a = int.tryParse(from.text) ?? 0, b = int.tryParse(to.text) ?? 1 << 30;
    from.dispose();
    to.dispose();
    if (go == null || !mounted) return;
    final pick = cards.where((x) => vNum(x['card_no']) >= a && vNum(x['card_no']) <= b).toList();
    if (pick.isEmpty) {
      vToast(context, tx(context, 'مفيش كروت في المدى ده', 'No cards in this range'), error: true);
      return;
    }
    final bytes = await buildCardsPdf(_cur!, [for (final x in pick) (vNum(x['card_no']).toInt(), vStr(x['code']))], a4: format == 'a4', sides: sides);
    final name = 'cards_${widget.pointName.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}_${vNum(pick.first['card_no']).toInt()}-${vNum(pick.last['card_no']).toInt()}.pdf';
    if (go == 'print') {
      await Printing.layoutPdf(name: name, onLayout: (_) async => bytes);
    } else {
      await Printing.sharePdf(bytes: bytes, filename: name);
    }
  }
}

// ================================================================ preview of one side

class CardFace extends StatelessWidget {
  const CardFace({super.key, required this.design, required this.back, required this.no, required this.code});
  final CardDesign design;
  final bool back;
  final int no;
  final String code;

  @override
  Widget build(BuildContext context) {
    final l = design.layout;
    final pic = back ? design.back : design.front;
    final side = back ? 'back' : 'front';
    return AspectRatio(
      aspectRatio: l.w / l.h,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: LayoutBuilder(builder: (context, box) {
          final w = box.maxWidth, h = box.maxHeight, s = w < h ? w : h;
          final children = <Widget>[
            Positioned.fill(
              child: pic != null
                  ? Image.memory(pic, fit: BoxFit.cover)
                  : Container(
                      color: const Color(0xFFF1F5F9),
                      alignment: Alignment.center,
                      child: Text(back ? 'BACK' : 'FRONT', style: const TextStyle(color: _muted, fontWeight: FontWeight.w800, letterSpacing: 2)),
                    ),
            ),
          ];
          if (l.qrSide == side) {
            final q = s * l.qrSize;
            children.add(Positioned(
              left: (w * l.qrX - q / 2).clamp(0, w - q),
              top: (h * l.qrY - q / 2).clamp(0, h - q),
              width: q,
              child: Container(
                color: Colors.white,
                padding: EdgeInsets.all(q * 0.05),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  QrImageView(data: cardLinkOf(code), padding: EdgeInsets.zero, size: q * 0.9),
                  if (l.qrCode) FittedBox(child: Text(code, style: const TextStyle(fontSize: 8, color: Colors.black))),
                ]),
              ),
            ));
          }
          if (l.numSide == side) {
            final fs = h * l.numSize;
            children.add(Positioned(
              left: 0,
              right: 0,
              top: 0,
              bottom: 0,
              child: Align(
                alignment: Alignment(l.numX * 2 - 1, l.numY * 2 - 1),
                child: Container(
                  padding: l.numBox ? EdgeInsets.symmetric(horizontal: fs * 0.3, vertical: fs * 0.05) : EdgeInsets.zero,
                  decoration: l.numBox ? BoxDecoration(color: l.numWhite ? Colors.black : Colors.white, borderRadius: BorderRadius.circular(fs * 0.25)) : null,
                  child: Text('${l.numPrefix.isEmpty ? '' : '${l.numPrefix} '}$no',
                      textDirection: TextDirection.ltr,
                      style: TextStyle(fontSize: fs, height: 1.1, fontWeight: FontWeight.w900, color: l.numWhite ? Colors.white : Colors.black)),
                ),
              ),
            ));
          }
          return Stack(children: children);
        }),
      ),
    );
  }
}

// ================================================================ PDF

/// [cards] = (number, code). a4 = 10 per A4 page (backs mirrored for duplex), else one card per page (card printer).
Future<Uint8List> buildCardsPdf(CardDesign d, List<(int, String)> cards, {bool a4 = false, String sides = 'both'}) async {
  final l = d.layout;
  final cw = l.w * PdfPageFormat.mm, ch = l.h * PdfPageFormat.mm;
  final front = d.front == null ? null : pw.MemoryImage(d.front!);
  final back = d.back == null ? null : pw.MemoryImage(d.back!);
  final bold = pw.Font.helveticaBold();

  pw.Widget face((int, String) c, bool isBack) {
    final side = isBack ? 'back' : 'front';
    final pic = isBack ? back : front;
    final s = cw < ch ? cw : ch;
    final kids = <pw.Widget>[
      if (pic != null) pw.Positioned.fill(child: pw.Image(pic, fit: pw.BoxFit.cover)),
    ];
    if (l.qrSide == side) {
      final q = s * l.qrSize;
      kids.add(pw.Positioned(
        left: (cw * l.qrX - q / 2).clamp(0, cw - q).toDouble(),
        top: (ch * l.qrY - q / 2).clamp(0, ch - q).toDouble(),
        child: pw.Container(
          width: q,
          color: PdfColors.white,
          padding: pw.EdgeInsets.all(q * 0.05),
          child: pw.Column(mainAxisSize: pw.MainAxisSize.min, children: [
            pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: cardLinkOf(c.$2), width: q * 0.9, height: q * 0.9, drawText: false),
            if (l.qrCode) pw.FittedBox(child: pw.Text(c.$2, style: pw.TextStyle(font: bold, fontSize: 5))),
          ]),
        ),
      ));
    }
    if (l.numSide == side) {
      final fs = ch * l.numSize;
      final white = l.numWhite;
      kids.add(pw.Positioned.fill(
        child: pw.Align(
          alignment: pw.Alignment(l.numX * 2 - 1, -(l.numY * 2 - 1)),
          child: pw.Container(
            padding: l.numBox ? pw.EdgeInsets.symmetric(horizontal: fs * 0.3, vertical: fs * 0.05) : pw.EdgeInsets.zero,
            decoration: l.numBox ? pw.BoxDecoration(color: white ? PdfColors.black : PdfColors.white, borderRadius: pw.BorderRadius.circular(fs * 0.25)) : null,
            child: pw.Text('${l.numPrefix.isEmpty ? '' : '${l.numPrefix} '}${c.$1}',
                style: pw.TextStyle(font: bold, fontSize: fs, color: white ? PdfColors.white : PdfColors.black)),
          ),
        ),
      ));
    }
    return pw.SizedBox(width: cw, height: ch, child: pw.Stack(children: kids));
  }

  final doc = pw.Document(title: 'VIP Valet NFC cards');
  final wantFront = sides != 'back', wantBack = sides != 'front';
  if (!a4) {
    final fmt = PdfPageFormat(cw, ch, marginAll: 0);
    for (final c in cards) {
      if (wantFront) doc.addPage(pw.Page(pageFormat: fmt, build: (_) => face(c, false)));
      if (wantBack) doc.addPage(pw.Page(pageFormat: fmt, build: (_) => face(c, true)));
    }
  } else {
    // 2 columns × 5 rows (landscape cards) or 3 × 3 (portrait cards), centred, cut marks around each card
    final cols = l.landscape ? 2 : 3, rows = l.landscape ? 5 : 3, per = cols * rows;
    const page = PdfPageFormat.a4;
    const gap = 4 * PdfPageFormat.mm;
    final gw = cols * cw + (cols - 1) * gap, gh = rows * ch + (rows - 1) * gap;
    final ox = (page.width - gw) / 2, oy = (page.height - gh) / 2;
    pw.Widget sheet(List<(int, String)> chunk, bool isBack) {
      final kids = <pw.Widget>[];
      for (var i = 0; i < chunk.length; i++) {
        var col = i % cols;
        final row = i ~/ cols;
        if (isBack) col = cols - 1 - col; // mirrored: the back lands behind its front (long-edge flip)
        final x = ox + col * (cw + gap), y = oy + row * (ch + gap);
        kids.add(pw.Positioned(left: x, top: y, child: pw.Container(
          decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400, width: 0.25)),
          child: face(chunk[i], isBack),
        )));
      }
      return pw.Stack(children: kids);
    }

    for (var i = 0; i < cards.length; i += per) {
      final chunk = cards.sublist(i, (i + per).clamp(0, cards.length));
      if (wantFront) doc.addPage(pw.Page(pageFormat: page.copyWith(marginLeft: 0, marginRight: 0, marginTop: 0, marginBottom: 0), build: (_) => pw.SizedBox(width: page.width, height: page.height, child: sheet(chunk, false))));
      if (wantBack) doc.addPage(pw.Page(pageFormat: page.copyWith(marginLeft: 0, marginRight: 0, marginTop: 0, marginBottom: 0), build: (_) => pw.SizedBox(width: page.width, height: page.height, child: sheet(chunk, true))));
    }
  }
  return doc.save();
}
