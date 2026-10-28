import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/services/excel_exporter.dart';
import 'valet_admin.dart';
import 'valet_ui.dart';

/// 🎟️ القَسائِم — QR / سيريال يُباع لِفُندُق أَو شَرِكة أَو عَميل: خَصم (مَبلَغ / سِعر نِهائيّ / نِسبة) عَلى نُقطة أَو أَكثَر أَو كُلّ النِقاط،
/// مِن تاريخ وَلِمُدّة، وَعَدَد مَرّات استِخدام لِكُلّ قَسيمة. يُستَخدَم في شاشة الدَفع بِالتَطبيق (لِلتَذاكِر التي لَها سِعر فَقَط).
class ValetVouchersScreen extends StatelessWidget {
  const ValetVouchersScreen({super.key});

  @override
  Widget build(BuildContext context) => const ValetGate(perm: ValetAdmin.permSettings, child: _VouchersBody());
}

String _discountText(BuildContext c, VJson b) {
  final v = vNum(b['value']);
  final money = v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
  return switch (vStr(b['kind'])) {
    'amount' => tx(c, 'خَصم $money دِرهَم', '$money AED off'),
    'price' => tx(c, 'سِعر ثابِت $money دِرهَم', 'Fixed price $money AED'),
    _ => tx(c, 'خَصم $money%', '$money% off') +
        (vNum(b['max']) > 0 ? tx(c, ' (حَدّ أَقصى ${vNum(b['max']).toStringAsFixed(0)})', ' (max ${vNum(b['max']).toStringAsFixed(0)})') : ''),
  };
}

String _discountEn(VJson b) {
  final v = vNum(b['value']);
  final money = v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
  return switch (vStr(b['kind'])) {
    'amount' => '$money AED off',
    'price' => 'Fixed price $money AED',
    _ => '$money% off${vNum(b['max']) > 0 ? ' (max ${vNum(b['max']).toStringAsFixed(0)} AED)' : ''}',
  };
}

String _usesText(BuildContext c, VJson b) {
  final n = vNum(b['uses_per_code']).toInt();
  return n <= 0 ? tx(c, 'غَير مَحدود خِلال المُدّة', 'Unlimited in the period') : (n == 1 ? tx(c, 'مَرّة واحِدة', 'Once') : tx(c, '$n مَرّات', '$n times'));
}

String _d(dynamic v) {
  final s = vStr(v);
  if (s.length < 10) return s;
  return '${s.substring(8, 10)}/${s.substring(5, 7)}/${s.substring(0, 4)}';
}

class _VouchersBody extends StatefulWidget {
  const _VouchersBody();

  @override
  State<_VouchersBody> createState() => _VouchersBodyState();
}

class _VouchersBodyState extends State<_VouchersBody> {
  List<VJson>? _rows;
  Object? _err;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await ValetAdmin.I.call('vva_voucher_batches');
      if (mounted) {
        setState(() {
          _rows = vList(d['rows']);
          _err = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _err = e);
    }
  }

  Future<List<VJson>?> _codes(VJson b) async {
    final r = await vGuard(context, () => ValetAdmin.I.call('vva_voucher_codes', {'p_batch': b['id']}));
    return r == null ? null : vList(r['rows']);
  }

  Future<void> _pdf(VJson b) async {
    final codes = await _codes(b);
    if (codes == null || !mounted) return;
    final doc = pw.Document();
    final title = vStr(b['name']);
    final disc = _discountEn(b);
    final valid = 'Valid ${_d(b['valid_from'])} – ${_d(b['valid_to'])}';
    final where = (vStr(b['point_names']).isEmpty ? 'All points' : vStr(b['point_names'])) +
        (vStr(b['site_names']).isEmpty ? '' : ' · ${vStr(b['site_names'])} only');
    // 3 × 7 cards on an A4 page, each with its QR and serial
    const perPage = 21;
    for (var i = 0; i < codes.length; i += perPage) {
      final page = codes.sublist(i, (i + perPage).clamp(0, codes.length));
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(18),
        build: (_) => pw.Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in page)
              pw.Container(
                width: 180,
                height: 108,
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey600, width: 0.6), borderRadius: pw.BorderRadius.circular(6)),
                child: pw.Row(children: [
                  pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: vStr(c['code']), width: 70, height: 70),
                  pw.SizedBox(width: 6),
                  pw.Expanded(
                    child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, mainAxisAlignment: pw.MainAxisAlignment.center, children: [
                      pw.Text('VALET VOUCHER', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700, letterSpacing: 1)),
                      pw.Text(title, maxLines: 1, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 2),
                      pw.Text(disc, style: const pw.TextStyle(fontSize: 8.5)),
                      pw.Text(valid, style: const pw.TextStyle(fontSize: 7)),
                      pw.Text(where, maxLines: 2, style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey700)),
                      pw.SizedBox(height: 3),
                      pw.Text(vStr(c['code']), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, letterSpacing: 0.8)),
                    ]),
                  ),
                ]),
              ),
          ],
        ),
      ));
    }
    await Printing.sharePdf(bytes: await doc.save(), filename: 'vouchers_${vStr(b['prefix'])}_${codes.length}.pdf');
  }

  Future<void> _excel(VJson b) async {
    final codes = await _codes(b);
    if (codes == null || !mounted) return;
    await vExport(context, 'vouchers_${vStr(b['prefix'])}', [
      ExcelSheet(
        name: 'Vouchers',
        headers: const ['Code', 'Name', 'Discount', 'Valid from', 'Valid to', 'Points', 'Uses', 'Uses allowed', 'Discount given', 'Active'],
        rows: [
          for (final c in codes)
            [
              vStr(c['code']),
              vStr(b['name']),
              _discountEn(b),
              _d(b['valid_from']),
              _d(b['valid_to']),
              vStr(b['point_names']).isEmpty ? 'All points' : vStr(b['point_names']),
              vNum(c['uses']).toInt(),
              vNum(b['uses_per_code']) <= 0 ? 'Unlimited' : vNum(b['uses_per_code']).toInt(),
              vNum(c['discount_total']),
              vBool(c['active']) ? 'Yes' : 'No',
            ],
        ],
      ),
    ]);
  }

  Future<void> _active(VJson b, bool on) async {
    final r = await vGuard(context, () => ValetAdmin.I.call('vva_voucher_active', {'p_batch': b['id'], 'p_voucher': null, 'p_active': on}),
        ok: on ? tx(context, 'تَمّ التَشغيل.', 'Started.') : tx(context, 'تَمّ الإيقاف.', 'Stopped.'));
    if (r != null) _load();
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final rows = _rows?.where((b) => q.isEmpty || '${b['name']} ${b['buyer']} ${b['prefix']}'.toLowerCase().contains(q)).toList();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      VHead(
        tx(context, 'القَسائِم (QR / سيريال)', 'Vouchers (QR / serial)'),
        subtitle: tx(context, 'تُنشَأ مَجموعة قَسائِم بِخَصم ثابِت أَو سِعر ثابِت أَو نِسبة، لِنُقطة أَو أَكثَر، مِن تاريخ وَلِمُدّة – وَتُستَخدَم في شاشة الدَفع بِالتَطبيق',
            'Create a batch with an amount off, a fixed price or a percent, for one or more points, from a date for a period – used on the app payment screen'),
        actions: [
          SizedBox(
            width: 220,
            child: TextField(
              decoration: InputDecoration(isDense: true, prefixIcon: const Icon(Icons.search), hintText: tx(context, 'بَحث', 'Search')),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          IconButton.filledTonal(onPressed: _load, icon: const Icon(Icons.refresh)),
          FilledButton.icon(
            icon: const Icon(Icons.add),
            label: Text(tx(context, 'قَسائِم جَديدة', 'New vouchers')),
            onPressed: () async {
              final r = await _showCreateDialog(context);
              if (r != null) _load();
            },
          ),
        ],
      ),
      if (_err != null) Padding(padding: const EdgeInsets.all(16), child: Text(vErr(context, _err!), style: const TextStyle(color: VC.bad))),
      if (rows == null && _err == null) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
      if (rows != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: VPanel(
            child: VTable(
              empty: tx(context, 'لا تُوجَد قَسائِم بَعد.', 'No vouchers yet.'),
              columns: [
                DataColumn(label: Text(tx(context, 'المَجموعة', 'Batch'))),
                DataColumn(label: Text(tx(context, 'الخَصم', 'Discount'))),
                DataColumn(label: Text(tx(context, 'النِقاط', 'Points'))),
                DataColumn(label: Text(tx(context, 'الصَلاحيّة', 'Valid'))),
                DataColumn(label: Text(tx(context, 'المُستَخدَم', 'Used')), numeric: true),
                DataColumn(label: Text(tx(context, 'البَيع', 'Sale')), numeric: true),
                DataColumn(label: Text(tx(context, 'الحالة', 'Status'))),
                const DataColumn(label: Text('')),
              ],
              rows: [
                for (final b in rows)
                  DataRow(cells: [
                    DataCell(Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(vStr(b['name']), style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text('${vStr(b['prefix'])}-···· · ${vNum(b['count']).toInt()} ${tx(context, 'قَسيمة', 'codes')} · ${_usesText(context, b)}',
                          style: const TextStyle(color: VC.muted, fontSize: 12)),
                    ])),
                    DataCell(Text(_discountText(context, b))),
                    DataCell(SizedBox(
                      width: 220,
                      child: Text(
                          [
                            vStr(b['point_names']).isEmpty ? tx(context, 'كُلّ النِقاط', 'All points') : vStr(b['point_names']),
                            if (vStr(b['site_names']).isNotEmpty) '${tx(context, 'فَرع', 'Branch')}: ${vStr(b['site_names'])}',
                          ].join('\n'),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis),
                    )),
                    DataCell(Text('${_d(b['valid_from'])} → ${_d(b['valid_to'])}',
                        style: TextStyle(color: vStr(b['valid_to']).compareTo(today) < 0 ? VC.bad : null))),
                    DataCell(Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('${vNum(b['used_codes']).toInt()} / ${vNum(b['count']).toInt()}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(tx(context, 'خَصم ${vNum(b['discount_total']).toStringAsFixed(2)}', '${vNum(b['discount_total']).toStringAsFixed(2)} off'),
                          style: const TextStyle(color: VC.muted, fontSize: 12)),
                    ])),
                    DataCell(Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(b['sale_price'] == null ? '—' : vNum(b['sale_price']).toStringAsFixed(2)),
                      if (vStr(b['buyer']).isNotEmpty) Text(vStr(b['buyer']), style: const TextStyle(color: VC.muted, fontSize: 12)),
                    ])),
                    DataCell(Switch(value: vBool(b['active']), onChanged: (v) => _active(b, v))),
                    DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: tx(context, 'الأَكواد', 'Codes'),
                        icon: const Icon(Icons.qr_code_2),
                        onPressed: () async {
                          final codes = await _codes(b);
                          if (codes != null && context.mounted) await _showCodes(context, b, codes);
                          _load();
                        },
                      ),
                      IconButton(tooltip: tx(context, 'PDF لِلطِباعة', 'PDF to print'), icon: const Icon(Icons.picture_as_pdf_outlined), onPressed: () => _pdf(b)),
                      IconButton(tooltip: 'Excel', icon: const Icon(Icons.table_view_outlined), onPressed: () => _excel(b)),
                    ])),
                  ]),
              ],
            ),
          ),
        ),
    ]);
  }
}

/// Codes of a batch: QR, uses, stop / start one code.
Future<void> _showCodes(BuildContext context, VJson b, List<VJson> codes) {
  String q = '';
  return showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      final shown = codes.where((c) => vStr(c['code']).toLowerCase().contains(q.toLowerCase())).toList();
      return AlertDialog(
        title: Text('${vStr(b['name'])} · ${codes.length}'),
        content: SizedBox(
          width: 620,
          height: 520,
          child: Column(children: [
            TextField(
              decoration: InputDecoration(isDense: true, prefixIcon: const Icon(Icons.search), hintText: tx(ctx, 'بَحث بِالكود', 'Search code')),
              onChanged: (v) => set(() => q = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                itemCount: shown.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final c = shown[i];
                  return ListTile(
                    leading: InkWell(
                      onTap: () => showDialog(
                        context: ctx,
                        builder: (_) => AlertDialog(
                          content: Column(mainAxisSize: MainAxisSize.min, children: [
                            SizedBox(width: 240, height: 240, child: QrImageView(data: vStr(c['code']), backgroundColor: Colors.white)),
                            const SizedBox(height: 8),
                            SelectableText(vStr(c['code']), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 2)),
                          ]),
                        ),
                      ),
                      child: SizedBox(width: 44, height: 44, child: QrImageView(data: vStr(c['code']), padding: EdgeInsets.zero, backgroundColor: Colors.white)),
                    ),
                    title: SelectableText(vStr(c['code']), style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1)),
                    subtitle: Text(tx(ctx, 'استُخدِمَت ${vNum(c['uses']).toInt()} · خَصم ${vNum(c['discount_total']).toStringAsFixed(2)}',
                        'Used ${vNum(c['uses']).toInt()} · ${vNum(c['discount_total']).toStringAsFixed(2)} off')),
                    trailing: Switch(
                      value: vBool(c['active']),
                      onChanged: (v) async {
                        final r = await vGuard(ctx, () => ValetAdmin.I.call('vva_voucher_active', {'p_batch': null, 'p_voucher': c['id'], 'p_active': v}));
                        if (r != null) set(() => c['active'] = v);
                      },
                    ),
                  );
                },
              ),
            ),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tx(ctx, 'إغلاق', 'Close')))],
      );
    }),
  );
}

/// New batch: rule + how many codes. Returns the server answer or null.
Future<VJson?> _showCreateDialog(BuildContext context) async {
  final points = await vGuard(context, VPoints.get);
  if (points == null || !context.mounted) return null;
  // DB 306: codes only for some branches (validated by them / given to them for their customer app)
  final clientsRes = await vGuard(context, () => ValetAdmin.I.call('vva_clients'));
  if (clientsRes == null || !context.mounted) return null;
  final branches = vList(clientsRes['clients']).where((c) => vList(c['points']).isNotEmpty).toList()
    ..sort((a, b) => vStr(a['name']).toLowerCase().compareTo(vStr(b['name']).toLowerCase()));
  var allBranches = true;
  final chosenSites = <String>{};
  String qb = '';
  final name = TextEditingController();
  final buyer = TextEditingController();
  final sale = TextEditingController();
  final value = TextEditingController();
  final max = TextEditingController();
  final usesN = TextEditingController(text: '10');
  final days = TextEditingController(text: '30');
  final count = TextEditingController(text: '1');
  final prefix = TextEditingController(text: 'VIP');
  final note = TextEditingController();
  var kind = 'percent';
  var uses = 'once'; // once / n / unlimited
  var allPoints = true;
  final chosen = <String>{};
  var from = DateTime.now();
  String q = '';
  return showDialog<VJson>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      final shown = points.where((p) => '${p['code']} ${p['name']}'.toLowerCase().contains(q.toLowerCase())).toList();
      final d = int.tryParse(days.text.trim()) ?? 0;
      final to = from.add(Duration(days: d > 0 ? d - 1 : 0));
      String f(DateTime x) => '${x.day.toString().padLeft(2, '0')}/${x.month.toString().padLeft(2, '0')}/${x.year}';
      return AlertDialog(
        title: Text(tx(ctx, 'قَسائِم جَديدة', 'New vouchers')),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(controller: name, decoration: InputDecoration(labelText: tx(ctx, 'الاسم *', 'Name *'), hintText: 'Hilton guests – November')),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: TextField(controller: buyer, decoration: InputDecoration(labelText: tx(ctx, 'المُشتَري (فُندُق / شَرِكة / عَميل)', 'Buyer (hotel / company / customer)')))),
                const SizedBox(width: 10),
                SizedBox(
                  width: 170,
                  child: TextField(
                    controller: sale,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: tx(ctx, 'سِعر البَيع (لِلمَجموعة)', 'Sale price (batch)'), suffixText: 'AED'),
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              Text(tx(ctx, 'نَوع الخَصم', 'Discount type'), style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'amount', icon: const Icon(Icons.remove_circle_outline), label: Text(tx(ctx, 'مَبلَغ يُخصَم', 'Amount off'))),
                  ButtonSegment(value: 'price', icon: const Icon(Icons.price_check), label: Text(tx(ctx, 'سِعر نِهائيّ ثابِت', 'Fixed final price'))),
                  ButtonSegment(value: 'percent', icon: const Icon(Icons.percent), label: Text(tx(ctx, 'نِسبة مِن السِعر', 'Percent of price'))),
                ],
                selected: {kind},
                onSelectionChanged: (v) => set(() => kind = v.first),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: value,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: switch (kind) {
                        'amount' => tx(ctx, 'المَبلَغ المَخصوم *', 'Amount off *'),
                        'price' => tx(ctx, 'السِعر الذي يَدفَعه العَميل *', 'Price the customer pays *'),
                        _ => tx(ctx, 'النِسبة *', 'Percent *'),
                      },
                      suffixText: kind == 'percent' ? '%' : 'AED',
                    ),
                  ),
                ),
                if (kind == 'percent') ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: max,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: tx(ctx, 'حَدّ أَقصى لِلخَصم (اختِياريّ)', 'Max discount (optional)'), suffixText: 'AED'),
                    ),
                  ),
                ],
              ]),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(tx(ctx, 'لِلتَذاكِر التي لَها سِعر فَقَط – التَذكَرة المَجّانيّة لا تَقبَل قَسيمة.', 'Only for tickets with a price – a free ticket does not take a voucher.'),
                    style: const TextStyle(color: VC.muted, fontSize: 12)),
              ),
              const SizedBox(height: 14),
              Text(tx(ctx, 'عَدَد مَرّات استِخدام القَسيمة الواحِدة', 'Uses per voucher'), style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Row(children: [
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'once', label: Text(tx(ctx, 'مَرّة واحِدة', 'Once'))),
                    ButtonSegment(value: 'n', label: Text(tx(ctx, 'عَدَد مُحَدَّد', 'Set number'))),
                    ButtonSegment(value: 'unlimited', label: Text(tx(ctx, 'غَير مَحدود', 'Unlimited'))),
                  ],
                  selected: {uses},
                  onSelectionChanged: (v) => set(() => uses = v.first),
                ),
                if (uses == 'n') ...[
                  const SizedBox(width: 10),
                  SizedBox(width: 110, child: TextField(controller: usesN, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tx(ctx, 'المَرّات', 'Times')))),
                ],
              ]),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.event),
                    label: Text(tx(ctx, 'يَبدَأ ${f(from)}', 'Starts ${f(from)}')),
                    onPressed: () async {
                      final p = await showDatePicker(
                          context: ctx, initialDate: from, firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime.now().add(const Duration(days: 3650)));
                      if (p != null) set(() => from = p);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: days,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => set(() {}),
                    decoration: InputDecoration(labelText: tx(ctx, 'المُدّة (أَيّام)', 'Days')),
                  ),
                ),
                const SizedBox(width: 10),
                Text(tx(ctx, 'حَتّى ${f(to)}', 'until ${f(to)}'), style: const TextStyle(fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 6),
              Wrap(spacing: 6, children: [
                for (final (n, ar, en) in const [(1, 'يَوم', '1 day'), (7, 'أُسبوع', '1 week'), (30, 'شَهر', '1 month'), (90, '3 أَشهُر', '3 months'), (365, 'سَنة', '1 year')])
                  ActionChip(label: Text(tx(ctx, ar, en)), onPressed: () => set(() => days.text = '$n')),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: Text(tx(ctx, 'النِقاط', 'Points'), style: const TextStyle(fontWeight: FontWeight.w600))),
                Text(tx(ctx, 'كُلّ النِقاط', 'All points')),
                Switch(value: allPoints, onChanged: (v) => set(() => allPoints = v)),
              ]),
              if (!allPoints) ...[
                TextField(
                  decoration: InputDecoration(isDense: true, prefixIcon: const Icon(Icons.search, size: 18), hintText: tx(ctx, 'بَحث (${chosen.length} مُختارة)', 'Search (${chosen.length} chosen)')),
                  onChanged: (v) => set(() => q = v),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView(shrinkWrap: true, children: [
                    for (final p in shown)
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: chosen.contains(vStr(p['id'])),
                        title: Text('${p['code']} · ${p['name']}'),
                        onChanged: (v) => set(() => v == true ? chosen.add(vStr(p['id'])) : chosen.remove(vStr(p['id']))),
                      ),
                  ]),
                ),
              ],
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tx(ctx, 'الفُروع', 'Branches'), style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(
                        tx(ctx, 'كود فَرع: يَنفَع لِلتَذاكِر اللي الفَرع عَمَل لَها فاليديشن، وَالفَرع يِقدَر يِستَخدِمه مِن تَطبيق العُمَلاء.',
                            'Branch code: works on tickets that branch validated; the branch can use it from the customer app.'),
                        style: const TextStyle(color: VC.muted, fontSize: 12)),
                  ]),
                ),
                Text(tx(ctx, 'كُلّ التَذاكِر', 'Every ticket')),
                Switch(value: allBranches, onChanged: (v) => set(() => allBranches = v)),
              ]),
              if (!allBranches) ...[
                TextField(
                  decoration: InputDecoration(isDense: true, prefixIcon: const Icon(Icons.search, size: 18), hintText: tx(ctx, 'بَحث (${chosenSites.length} مُختار)', 'Search (${chosenSites.length} chosen)')),
                  onChanged: (v) => set(() => qb = v),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView(shrinkWrap: true, children: [
                    for (final c in branches.where((c) => vStr(c['name']).toLowerCase().contains(qb.toLowerCase())))
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: chosenSites.contains(vStr(c['id'])),
                        title: Text(vStr(c['name'])),
                        onChanged: (v) => set(() => v == true ? chosenSites.add(vStr(c['id'])) : chosenSites.remove(vStr(c['id']))),
                      ),
                  ]),
                ),
              ],
              const SizedBox(height: 14),
              Row(children: [
                SizedBox(
                  width: 150,
                  child: TextField(controller: count, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tx(ctx, 'عَدَد القَسائِم *', 'Number of codes *'), helperText: '1 – 5000')),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 150,
                  child: TextField(controller: prefix, decoration: InputDecoration(labelText: tx(ctx, 'بِدايَة الكود', 'Code prefix'), helperText: 'VIP-7K3Q-92HD')),
                ),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: note, decoration: InputDecoration(labelText: tx(ctx, 'مُلاحَظة', 'Note')))),
              ]),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tx(ctx, 'إلغاء', 'Cancel'))),
          FilledButton.icon(
            icon: const Icon(Icons.qr_code_2),
            label: Text(tx(ctx, 'تَوليد القَسائِم', 'Generate')),
            onPressed: () async {
              if (!allBranches && chosenSites.isEmpty) {
                vToast(ctx, tx(ctx, 'اختَر فَرع واحِد عَلى الأَقَلّ.', 'Choose at least one branch.'), error: true);
                return;
              }
              if (!allPoints && chosen.isEmpty) {
                vToast(ctx, tx(ctx, 'اختَر نُقطة واحِدة عَلى الأَقَلّ.', 'Choose at least one point.'), error: true);
                return;
              }
              final r = await vGuard(
                ctx,
                () => ValetAdmin.I.call('vva_voucher_batch_create', {
                  'p_data': {
                    'name': name.text.trim(),
                    'buyer': buyer.text.trim(),
                    'sale_price': sale.text.trim(),
                    'kind': kind,
                    'value': value.text.trim(),
                    'max': kind == 'percent' ? max.text.trim() : '',
                    'uses': switch (uses) { 'once' => '1', 'n' => usesN.text.trim(), _ => '' },
                    'points': allPoints ? <String>[] : chosen.toList(),
                    'sites': allBranches ? <String>[] : chosenSites.toList(),
                    'valid_from': from.toIso8601String().substring(0, 10),
                    'valid_days': days.text.trim(),
                    'count': count.text.trim(),
                    'prefix': prefix.text.trim(),
                    'note': note.text.trim(),
                  },
                }),
                ok: tx(ctx, 'تَمّ التَوليد.', 'Generated.'),
              );
              if (r != null && ctx.mounted) Navigator.pop(ctx, r);
            },
          ),
        ],
      );
    }),
  );
}
