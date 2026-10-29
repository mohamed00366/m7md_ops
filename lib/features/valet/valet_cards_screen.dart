import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/services/excel_exporter.dart';
import 'valet_admin.dart';
import 'valet_card_design.dart';
import 'valet_card_ranges.dart';
import 'valet_hub_ui.dart';
import 'valet_ui.dart';

/// 📇 كروت NFC (DB 311) — سجل كروت التذاكر المرقّمة لكل نقطة، وطريقة ربط الكارت بالتكت «أوبشن» للنقطة:
/// ① مسح الكارت (الطريقة الحالية) · ② ربط تلقائي بالترتيب · ③ بدون كروت — مع فترة الانتظار والكارت الضايع.
class ValetCardsScreen extends StatefulWidget {
  const ValetCardsScreen({super.key, this.pointId});

  /// Opened inside a point (point screen → tab): only this point, no point chips.
  final String? pointId;

  /// Test hook (screenshots).
  static Future<VJson> Function()? debugLoad;

  @override
  State<ValetCardsScreen> createState() => _ValetCardsScreenState();
}

const _ink = Color(0xFF0B0C0E);
const _line = Color(0xFFE2E8F0);
const _muted = Color(0xFF64748B);
const _lost = Color(0xFFB91C1C);
const _wait = Color(0xFFC2410C);

String cardUrl(String code) => 'https://vip-valet-uae.app/RequestCar?ticket=${Uri.encodeQueryComponent(code)}';

class _ValetCardsScreenState extends State<ValetCardsScreen> {
  VJson? _d;
  Object? _err;
  late String? _point = widget.pointId;
  VJson _set = {};
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (_point == null && ValetCardsScreen.debugLoad == null) {
        // first point that has cards, else the first point
        final first = await ValetAdmin.I.call('vva_cards', {'p_point': null});
        final pts = vList(first['points']);
        if (pts.isEmpty) {
          if (mounted) setState(() => _d = first);
          return;
        }
        _point = vStr((pts.where((p) => vNum(p['cards']) > 0).firstOrNull ?? pts.first)['id']);
      }
      final d = await (ValetCardsScreen.debugLoad?.call() ?? ValetAdmin.I.call('vva_cards', {'p_point': _point}));
      if (!mounted) return;
      setState(() {
        _d = d;
        _err = null;
        _set = Map<String, dynamic>.from((d['settings'] as Map?) ?? {});
        _dirty = false;
      });
    } catch (e) {
      if (mounted) setState(() => _err = e);
    }
  }

  void _s(String k, dynamic v) => setState(() {
        _set[k] = v;
        _dirty = true;
      });

  Future<void> _saveSettings() async {
    final r = await vGuard(context, () => ValetAdmin.I.call('vva_cards_settings', {'p_point': _point, 'p_settings': _set}),
        ok: tx(context, 'تم حفظ إعدادات الكروت لهذه النقطة', 'Card settings saved'));
    if (r != null) _load();
  }

  List<VJson> get _cards => vList(_d?['cards']);

  // ---------------------------------------------------------------- actions

  Future<void> _newBatch() async {
    final pts = vList(_d?['points']);
    final p = pts.where((x) => vStr(x['id']) == _point).firstOrNull;
    final maxNo = _cards.fold<int>(0, (m, c) => vNum(c['card_no']).toInt() > m ? vNum(c['card_no']).toInt() : m);
    final prefix = TextEditingController(text: _defaultPrefix(vStr(p?['code']), vStr(p?['name'])));
    final start = TextEditingController(text: '${maxNo + 1}');
    final count = TextEditingController(text: '100');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tx(c, 'دفعة كروت جديدة · ${vStr(p?['name'])}', 'New cards · ${vStr(p?['name'])}')),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: count, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(labelText: tx(c, 'عدد الكروت', 'Number of cards'))),
            TextField(controller: start, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(labelText: tx(c, 'تبدأ من رقم', 'Start from number'))),
            TextField(controller: prefix, textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(labelText: tx(c, 'البادئة (2 – 6 حروف / أرقام)', 'Prefix (2 – 6 letters / digits)'))),
            const SizedBox(height: 10),
            Text(tx(c, 'كل كارت = رقمه + كود سري عشوائي، مثال: ${prefix.text.toUpperCase()}-001-7KQ2XW', 'Each card = its number + a random secret, e.g. ${prefix.text.toUpperCase()}-001-7KQ2XW'),
                style: const TextStyle(color: _muted, fontSize: 12)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tx(c, 'إلغاء', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tx(c, 'إنشاء', 'Create'))),
        ],
      ),
    );
    final args = {'p_point': _point, 'p_prefix': prefix.text.trim(), 'p_start': int.tryParse(start.text) ?? 1, 'p_count': int.tryParse(count.text) ?? 0};
    prefix.dispose();
    start.dispose();
    count.dispose();
    if (ok != true || !mounted) return;
    final r = await vGuard(context, () => ValetAdmin.I.call('vva_cards_batch', args), ok: tx(context, 'تم إنشاء الكروت', 'Cards created'));
    if (r == null) return;
    await _load();
  }

  static String _defaultPrefix(String code, String name) {
    final c = code.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    if (c.length >= 2 && c.length <= 6) return c;
    final n = name.replaceAll(RegExp(r'[^A-Za-z]'), '').toUpperCase();
    return n.length >= 3 ? n.substring(0, 3) : 'VLT';
  }

  Future<void> _cardSheet(VJson c) async {
    final no = vNum(c['card_no']).toInt();
    final problem = vStr(c['problem']);
    final status = vStr(c['status']);
    final act = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Text(tx(ctx, 'كارت $no', 'Card $no'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(width: 10),
              _stateTag(c),
            ]),
            const SizedBox(height: 4),
            SelectableText(vStr(c['code']), style: const TextStyle(fontFamily: 'monospace', color: _muted)),
            const SizedBox(height: 8),
            if (vStr(c['in_use']).isNotEmpty) Text(tx(ctx, 'مع التكت ${vStr(c['in_use'])} · ${vStr(c['in_use_plate'])}', 'With ticket ${vStr(c['in_use'])} · ${vStr(c['in_use_plate'])}')),
            if (vStr(c['prev_ticket']).isNotEmpty)
              Text(tx(ctx, 'آخر سيارة: ${vStr(c['prev_plate'])} (${vStr(c['prev_ticket'])}) · ${_time(c['released_at'])}',
                  'Last car: ${vStr(c['prev_plate'])} (${vStr(c['prev_ticket'])}) · ${_time(c['released_at'])}'), style: const TextStyle(color: _muted)),
            if (status == 'lost') Text(tx(ctx, 'ضايع من ${_time(c['lost_at'])} ${vStr(c['lost_ticket'])}', 'Lost since ${_time(c['lost_at'])} ${vStr(c['lost_ticket'])}'), style: const TextStyle(color: _lost)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (status != 'lost') OutlinedButton.icon(onPressed: () => Navigator.pop(ctx, 'lost'), icon: const Icon(Icons.report_gmailerrorred, color: _lost), label: Text(tx(ctx, 'ضايع', 'Lost'))),
              if (status == 'lost') OutlinedButton.icon(onPressed: () => Navigator.pop(ctx, 'found'), icon: const Icon(Icons.undo), label: Text(tx(ctx, 'اتلقى', 'Found'))),
              if (status == 'ready') OutlinedButton.icon(onPressed: () => Navigator.pop(ctx, 'off'), icon: const Icon(Icons.block), label: Text(tx(ctx, 'إيقاف', 'Stop'))),
              if (status == 'off') OutlinedButton.icon(onPressed: () => Navigator.pop(ctx, 'on'), icon: const Icon(Icons.play_arrow), label: Text(tx(ctx, 'تشغيل', 'Start'))),
              OutlinedButton.icon(onPressed: () => Navigator.pop(ctx, 'replace'), icon: const Icon(Icons.autorenew), label: Text(tx(ctx, 'استبدال بكارت جديد', 'Replace with a new card'))),
              OutlinedButton.icon(onPressed: () => Navigator.pop(ctx, 'copy'), icon: const Icon(Icons.copy), label: Text(tx(ctx, 'نسخ اللينك', 'Copy link'))),
            ]),
            if (problem == 'cooldown') ...[
              const SizedBox(height: 8),
              Text(tx(ctx, 'في فترة الانتظار: باقي ${_mmss(vNum(c['cooldown_left']).toInt())}', 'Waiting time: ${_mmss(vNum(c['cooldown_left']).toInt())} left'), style: const TextStyle(color: _wait)),
            ],
          ]),
        ),
      ),
    );
    if (act == null || !mounted) return;
    if (act == 'copy') {
      await Clipboard.setData(ClipboardData(text: cardUrl(vStr(c['code']))));
      if (mounted) vToast(context, tx(context, 'تم النسخ', 'Copied'));
      return;
    }
    if (act == 'replace') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (x) => AlertDialog(
          content: Text(tx(x, 'كارت جديد بنفس الرقم $no وكود سري جديد. الكارت القديم يبطل تماماً. برمج الكارت الجديد من التطبيق.',
              'A new card with the same number $no and a new secret. The old card stops working. Write the new card in the app.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(x, false), child: Text(tx(x, 'إلغاء', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(x, true), child: Text(tx(x, 'استبدال', 'Replace'))),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    final r = await vGuard(context, () => ValetAdmin.I.call('vva_card_action', {'p_card': c['id'], 'p_action': act, 'p_note': 'dashboard'}),
        ok: tx(context, 'تم', 'Done'));
    if (r != null) _load();
  }

  static String _mmss(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  static String _time(dynamic v) {
    final d = DateTime.tryParse(vStr(v))?.toLocal();
    if (d == null) return '';
    return '${d.day}/${d.month} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _exportPdf() async {
    final cards = _cards.where((c) => vStr(c['status']) != 'replaced').toList();
    if (cards.isEmpty) return;
    final doc = pw.Document();
    const perPage = 24; // 4 × 6 labels
    for (var i = 0; i < cards.length; i += perPage) {
      final page = cards.sublist(i, (i + perPage).clamp(0, cards.length));
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(16),
        build: (_) => pw.Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in page)
            pw.Container(
              width: 132,
              height: 124,
              padding: const pw.EdgeInsets.all(6),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey600, width: 0.6), borderRadius: pw.BorderRadius.circular(8)),
              child: pw.Column(mainAxisAlignment: pw.MainAxisAlignment.center, children: [
                pw.Text('${vNum(c['card_no']).toInt()}', style: pw.TextStyle(fontSize: 34, fontWeight: pw.FontWeight.bold)),
                pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: cardUrl(vStr(c['code'])), width: 52, height: 52),
                pw.SizedBox(height: 3),
                pw.Text(vStr(c['code']), style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
              ]),
            ),
        ]),
      ));
    }
    await Printing.sharePdf(bytes: await doc.save(), filename: 'nfc_cards_${cards.length}.pdf');
  }

  Future<void> _exportExcel() async {
    final cards = _cards;
    if (cards.isEmpty) return;
    await vExport(context, 'nfc_cards', [
      ExcelSheet(
        name: 'Cards',
        headers: const ['No', 'Code', 'Link (write on the card)', 'Status'],
        rows: [for (final c in cards) [vNum(c['card_no']).toInt(), vStr(c['code']), cardUrl(vStr(c['code'])), vStr(c['problem']).isEmpty ? vStr(c['status']) : vStr(c['problem'])]],
      ),
    ]);
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    if (_err != null && _d == null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(vErr(context, _err!)),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: _load, child: Text(tx(context, 'إعادة المحاولة', 'Retry'))),
      ]));
    }
    final d = _d;
    if (d == null) return const Center(child: CircularProgressIndicator());
    final cards = _cards;
    final free = cards.where((c) => vStr(c['problem']).isEmpty).length;
    final inUse = cards.where((c) => vStr(c['problem']) == 'in_use').length;
    final lost = cards.where((c) => vStr(c['problem']) == 'lost').length;
    final waiting = cards.where((c) => vStr(c['problem']) == 'cooldown').length;
    final pts = vList(d['points']);
    final nextNo = _nextNo(cards);
    return ListView(padding: const EdgeInsets.only(bottom: 30), children: [
      HubHead(
        title: tx(context, 'تطبيق الفاليه — كروت NFC', 'Valet app — NFC cards'),
        subtitle: tx(context, 'تعريف الكروت وأرقامها مشترك · طريقة ربط الكارت بالتكت «أوبشن» تختاره لكل نقطة',
            'One card registry · how a card is linked to a ticket is an option of each point'),
        actions: [
          HubButton(label: tx(context, 'Excel / ملف البرمجة', 'Excel / write file'), icon: Icons.table_view, onPressed: cards.isEmpty ? null : _exportExcel),
          HubButton(label: tx(context, 'ملصقات بسيطة PDF', 'Simple labels PDF'), icon: Icons.picture_as_pdf_outlined, onPressed: cards.isEmpty ? null : _exportPdf),
          HubButton(label: tx(context, 'دفعة كروت جديدة', 'New cards'), icon: Icons.add, primary: true, onPressed: _point == null ? null : _newBatch),
        ],
      ),
      HubKpis([
        HubKpi(Icons.style_outlined, '${cards.length}', tx(context, 'كارت في هذه النقطة', 'Cards at this point')),
        HubKpi(Icons.check_circle_outline, '$free', tx(context, 'فاضي وجاهز', 'Free')),
        HubKpi(Icons.directions_car, '$inUse', tx(context, 'مع عربيات دلوقتي', 'With cars')),
        HubKpi(Icons.hourglass_top, '$waiting', tx(context, 'في فترة الانتظار', 'Waiting time')),
        HubKpi(Icons.report_gmailerrorred, '$lost', tx(context, 'ضايع', 'Lost')),
      ]),
      if (widget.pointId == null) HubChips(
        items: [for (final p in pts) (vStr(p['id']), '${vStr(p['name'])}${vNum(p['cards']) > 0 ? ' · ${vNum(p['cards']).toInt()}' : ''}', null)],
        value: _point ?? '',
        onChanged: (v) {
          setState(() {
            _point = v;
            _d = null;
          });
          _load();
        },
      ),
      Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 0), child: _modesCard()),
      if (_point != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: CardDesignPanel(
            key: ValueKey('design$_point'),
            pointId: _point!,
            pointName: vStr(pts.where((p) => vStr(p['id']) == _point).firstOrNull?['name']),
            cards: cards,
            edit: ValetAdmin.I.can(ValetAdmin.permSettings),
          ),
        ),
      if (_point != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: CardRangesPanel(key: ValueKey('ranges$_point'), pointId: _point!, edit: ValetAdmin.I.can(ValetAdmin.permSettings)),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: LayoutBuilder(builder: (context, c) {
          final grid = _gridCard(cards, nextNo);
          final side = _eventsCard();
          if (c.maxWidth < 1100) return Column(children: [grid, const SizedBox(height: 14), side]);
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: grid), const SizedBox(width: 16), SizedBox(width: 460, child: side)]);
        }),
      ),
    ]);
  }

  /// The card the next ticket gets in option ② (first free card from the pointer, then from the start).
  int? _nextNo(List<VJson> cards) {
    final from = vNum(_set['card_next_no']).toInt();
    final free = cards.where((c) => vStr(c['problem']).isEmpty && vStr(c['status']) == 'ready').map((c) => vNum(c['card_no']).toInt()).toList()..sort();
    if (free.isEmpty) return null;
    return free.firstWhere((n) => n >= from, orElse: () => free.first);
  }

  Widget _modesCard() {
    final mode = vStr(_set['card_mode']).isEmpty ? 'scan' : vStr(_set['card_mode']);
    Widget m(String key, String n, String t, String desc, {String? tag}) {
      final on = mode == key;
      return InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _s('card_mode', key),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: on ? _ink : _line, width: on ? 2 : 1.2)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('$n  $t', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5))),
              Icon(on ? Icons.radio_button_checked : Icons.radio_button_off, color: on ? _ink : _muted),
            ]),
            const SizedBox(height: 6),
            Text(desc, style: const TextStyle(fontSize: 12.8, color: Color(0xFF475569), height: 1.5)),
            if (tag != null || on) ...[const SizedBox(height: 8), hubPill(on ? tx(context, 'مختار', 'Selected') : tag!, kind: on ? 'dark' : 'mut')],
          ]),
        ),
      );
    }

    Widget sw(String k, String t, String? sub, {bool def = false}) => _opt(t, sub, Switch(activeTrackColor: _ink, value: _set[k] == null ? def : _set[k] == true, onChanged: (v) => _s(k, v)));
    return HubCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(tx(context, 'طريقة التشغيل في هذه النقطة', 'How cards work at this point'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _ink),
            onPressed: _dirty ? _saveSettings : null,
            icon: const Icon(Icons.check, size: 18),
            label: Text(_dirty ? tx(context, 'حفظ', 'Save') : tx(context, 'محفوظ', 'Saved')),
          ),
        ]),
        const SizedBox(height: 4),
        Text(tx(context, 'كل طريقة أوبشن مستقل · تقدر تغيّر في أي وقت · طرق جديدة تتضاف هنا', 'Each way is a separate option · change any time · new options will be added here'),
            style: const TextStyle(color: _muted, fontSize: 12.5)),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, c) {
          final per = c.maxWidth >= 1000 ? 4 : (c.maxWidth >= 600 ? 2 : 1);
          final w = (c.maxWidth - 12 * (per - 1)) / per;
          return Wrap(spacing: 12, runSpacing: 12, children: [
            SizedBox(width: w, child: m('scan', '①', tx(context, 'مسح الكارت', 'Scan the card'),
                tx(context, 'الطريقة الحالية: الموظف يقرّب الكارت (أو يمسح QR) وهو بيقطع التكت.', 'The current way: the valet taps the card (or scans its QR) when cutting the ticket.'),
                tag: tx(context, 'الأوبشن الحالي', 'Current option'))),
            SizedBox(width: w, child: m('auto', '②', tx(context, 'ربط تلقائي بالترتيب', 'Automatic, in order'),
                tx(context, 'التكت الجديد ياخد الكارت الفاضي التالي من غير مسح. الكارت اللي مع عربية أو في فترة الانتظار أو ضايع يتخطّى.',
                    'A new ticket gets the next free card, no scan. Cards with a car, waiting or lost are skipped.'),
                tag: tx(context, 'أوبشن', 'Option'))),
            SizedBox(width: w, child: m('none', '③', tx(context, 'بدون كروت', 'No cards'),
                tx(context, 'التكت المطبوع فيه QR للعميل بس.', 'Only the QR on the printed ticket.'), tag: tx(context, 'أوبشن', 'Option'))),
            SizedBox(
              width: w,
              child: Container(
                height: 120,
                alignment: Alignment.center,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: _line, width: 1.2)),
                child: Text(tx(context, '+ أوبشن جديد في المستقبل', '+ A new option later'), style: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.w800)),
              ),
            ),
          ]);
        }),
        const Divider(height: 28),
        LayoutBuilder(builder: (context, c) {
          final per = c.maxWidth >= 1000 ? 3 : (c.maxWidth >= 600 ? 2 : 1);
          final w = (c.maxWidth - 12 * (per - 1)) / per;
          final items = <Widget>[
            sw('nfc_qr_in_out', tx(context, 'الكارت إجباري على كل تكت', 'A card on every ticket'), tx(context, 'من غير كارت ما يتحفظش التكت', 'No card = the ticket is not saved')),
            sw('card_allow_other', tx(context, 'السماح بمسح كارت تاني بدل المقترح', 'Valet may take another card'), tx(context, 'في الأوبشن ②', 'In option ②'), def: true),
            sw('card_print_no', tx(context, 'طباعة رقم الكارت على التكت', 'Print the card number'), null, def: true),
            sw('card_cooldown_on', tx(context, 'فترة انتظار بعد خروج السيارة', 'Waiting time after the car leaves'), tx(context, 'الكارت ما يتربطش بسيارة جديدة قبلها', 'The card is not linked to a new car before it'), def: true),
            _opt(
              tx(context, 'مدة الانتظار', 'Waiting time'),
              null,
              Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(onPressed: () => _s('card_cooldown_min', (vNum(_set['card_cooldown_min']).toInt() - 1).clamp(1, 120)), icon: const Icon(Icons.remove_circle_outline)),
                Text('${vNum(_set['card_cooldown_min']).toInt()} ${tx(context, 'د', 'min')}', style: const TextStyle(fontWeight: FontWeight.w800)),
                IconButton(onPressed: () => _s('card_cooldown_min', (vNum(_set['card_cooldown_min']).toInt() + 1).clamp(1, 120)), icon: const Icon(Icons.add_circle_outline)),
              ]),
            ),
            sw('card_cooldown_override', tx(context, 'المشرف يقدر يتخطى الانتظار', 'Supervisor may skip the wait'), tx(context, 'زرار في رسالة الانتظار', 'A button in the waiting message')),
            sw('card_lost_fee_on', tx(context, 'رسوم الكارت الضايع', 'Lost card fee'), tx(context, 'تتضاف على التكت المربوط بالكارت', 'Added to the ticket of the card')),
            _opt(
              tx(context, 'مبلغ رسوم الكارت الضايع', 'Lost card fee amount'),
              null,
              SizedBox(
                width: 110,
                child: TextFormField(
                  key: ValueKey('fee$_point'),
                  initialValue: '${vNum(_set['card_lost_fee'])}',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(isDense: true, suffixText: 'AED'),
                  onChanged: (v) => _s('card_lost_fee', num.tryParse(v) ?? 0),
                ),
              ),
            ),
          ];
          return Wrap(spacing: 12, runSpacing: 12, children: [for (final i in items) SizedBox(width: w, child: i)]);
        }),
      ]),
    );
  }

  Widget _opt(String t, String? sub, Widget trailing) => Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(14), border: Border.all(color: _line)),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
              if (sub != null) Text(sub, style: const TextStyle(color: _muted, fontSize: 11.5)),
            ]),
          ),
          trailing,
        ]),
      );

  Widget _stateTag(VJson c) {
    final p = vStr(c['problem']);
    return switch (p) {
      'in_use' => hubPill(tx(context, 'مع عربية', 'With a car'), kind: 'dark'),
      'cooldown' => hubPill(tx(context, 'انتظار ${_mmss(vNum(c['cooldown_left']).toInt())}', 'Waiting ${_mmss(vNum(c['cooldown_left']).toInt())}'), kind: 'warn'),
      'lost' => hubPill(tx(context, 'ضايع', 'Lost'), kind: 'bad'),
      'off' => hubPill(tx(context, 'موقوف', 'Stopped')),
      _ => hubPill(tx(context, 'فاضي', 'Free'), kind: 'ok'),
    };
  }

  Widget _gridCard(List<VJson> cards, int? nextNo) {
    final auto = vStr(_set['card_mode']) == 'auto';
    return HubCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text(
                cards.isEmpty ? tx(context, 'الكروت', 'Cards') : tx(context, 'الكروت ${vNum(cards.first['card_no']).toInt()} – ${vNum(cards.last['card_no']).toInt()}', 'Cards ${vNum(cards.first['card_no']).toInt()} – ${vNum(cards.last['card_no']).toInt()}'),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          ),
          Text(tx(context, 'اضغط على كارت: سجله · ضايع · استبدال · إيقاف', 'Tap a card: history · lost · replace · stop'), style: const TextStyle(color: _muted, fontSize: 12)),
        ]),
        const SizedBox(height: 12),
        if (cards.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              Text(tx(context, 'مفيش كروت للنقطة دي لسه', 'No cards for this point yet'), style: const TextStyle(color: _muted)),
              const SizedBox(height: 8),
              FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: _ink), onPressed: _newBatch, icon: const Icon(Icons.add), label: Text(tx(context, 'دفعة كروت جديدة', 'New cards'))),
            ]),
          )
        else
          LayoutBuilder(builder: (context, c) {
            final per = (c.maxWidth / 62).floor().clamp(5, 20);
            final w = (c.maxWidth - 6 * (per - 1)) / per;
            return Wrap(spacing: 6, runSpacing: 6, children: [
              for (final card in cards) SizedBox(width: w, child: _cell(card, auto && vNum(card['card_no']).toInt() == nextNo)),
            ]);
          }),
        const SizedBox(height: 12),
        Wrap(spacing: 14, runSpacing: 6, children: [
          _legend(Colors.white, _line, tx(context, 'فاضي', 'Free')),
          _legend(_ink, _ink, tx(context, 'مع عربية', 'With a car')),
          if (auto) _legend(Colors.white, _ink, tx(context, 'التالي في الدور', 'Next')),
          _legend(const Color(0xFFFFF7ED), const Color(0xFFFDBA74), tx(context, 'فترة انتظار', 'Waiting')),
          _legend(const Color(0xFFFEF2F2), const Color(0xFFFCA5A5), tx(context, 'ضايع', 'Lost')),
          _legend(const Color(0xFFF1F5F9), const Color(0xFFE2E8F0), tx(context, 'موقوف', 'Stopped')),
        ]),
      ]),
    );
  }

  Widget _legend(Color bg, Color border, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 14, height: 14, decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4), border: Border.all(color: border, width: 1.5))),
        const SizedBox(width: 6),
        Text(t, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF475569))),
      ]);

  Widget _cell(VJson c, bool next) {
    final p = vStr(c['problem']);
    final (bg, fg, border, sub) = switch (p) {
      'in_use' => (_ink, Colors.white, _ink, _short(vStr(c['in_use']))),
      'cooldown' => (const Color(0xFFFFF7ED), _wait, const Color(0xFFFDBA74), _mmss(vNum(c['cooldown_left']).toInt())),
      'lost' => (const Color(0xFFFEF2F2), _lost, const Color(0xFFFCA5A5), tx(context, 'ضايع', 'lost')),
      'off' => (const Color(0xFFF1F5F9), const Color(0xFF94A3B8), _line, tx(context, 'موقوف', 'off')),
      _ => (Colors.white, _ink, next ? _ink : _line, next ? tx(context, 'التالي', 'next') : ''),
    };
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _cardSheet(c),
      child: Container(
        height: 46,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: border, width: next ? 2.4 : 1.4)),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('${vNum(c['card_no']).toInt()}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: fg)),
          if (sub.isNotEmpty) Text(sub, maxLines: 1, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: fg.withValues(alpha: 0.75))),
        ]),
      ),
    );
  }

  static String _short(String code) {
    final m = RegExp(r'^T-(\d+)-').firstMatch(code);
    return m == null ? code : 'T-${m.group(1)}';
  }

  Widget _eventsCard() {
    final ev = vList(_d?['events']);
    String kind(String k) => switch (k) {
          'linked' => tx(context, 'اتربط', 'Linked'),
          'lost' => tx(context, 'ضايع', 'Lost'),
          'replaced' => tx(context, 'اتبدل', 'Replaced'),
          'off' => tx(context, 'اتوقف', 'Stopped'),
          'on' => tx(context, 'اتشغل', 'Started'),
          _ => k,
        };
    String pill(String k) => switch (k) { 'linked' => 'info', 'lost' => 'bad', 'replaced' => 'warn', _ => 'mut' };
    return HubCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tx(context, 'آخر الحركات', 'Last events'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        const SizedBox(height: 8),
        if (ev.isEmpty)
          Padding(padding: const EdgeInsets.all(16), child: Text(tx(context, 'لا توجد حركات بعد', 'No events yet'), style: const TextStyle(color: _muted)))
        else
          for (final e in ev.take(20))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                SizedBox(width: 34, child: Text('${vNum(e['card_no']).toInt()}', style: const TextStyle(fontWeight: FontWeight.w800))),
                hubPill(kind(vStr(e['kind'])), kind: pill(vStr(e['kind']))),
                const SizedBox(width: 8),
                Expanded(child: Text([_short(vStr(e['ticket_code'])), vStr(e['employee'])].where((x) => x.isNotEmpty).join(' · '), overflow: TextOverflow.ellipsis)),
                Text(_time(e['at']), style: const TextStyle(color: _muted, fontSize: 12)),
              ]),
            ),
      ]),
    );
  }
}
