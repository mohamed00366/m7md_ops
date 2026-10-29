import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:universal_html/html.dart' as html;

import 'valet_admin.dart';
import 'valet_excel_builder.dart';
import 'valet_hub_ui.dart';
import 'valet_ui.dart';

/// 📊 لينك الإكسل الحي (DB 325) — نسخة من كل فواتير العملاء في Odoo (كل الدفاتر) بتتحدث كل دقيقة تقريباً،
/// وملف إكسل متوصل بلينك سري بيتحدث لوحده لما يتفتح وكل N دقيقة. قراءة بس — مفيش حاجة بتتكتب في Odoo.
class OdooExcelLinkPanel extends StatefulWidget {
  const OdooExcelLinkPanel({super.key});

  @override
  State<OdooExcelLinkPanel> createState() => _OdooExcelLinkPanelState();
}

const _muted = Color(0xFF64748B);
const _bad = Color(0xFFB91C1C);

String _time(dynamic v) {
  final t = DateTime.tryParse(vStr(v))?.toLocal();
  if (t == null) return '—';
  String two(int x) => x.toString().padLeft(2, '0');
  return '${two(t.day)}/${two(t.month)} ${two(t.hour)}:${two(t.minute)}';
}

class _OdooExcelLinkPanelState extends State<OdooExcelLinkPanel> {
  VJson? _d;
  Object? _err;
  VJson _set = {};
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await ValetAdmin.I.call('vva_xl_get', {});
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

  Future<void> _act(String action, {String? ok}) async {
    final d = await vGuard(context, () => ValetAdmin.I.call('vva_xl_action', {'p_action': action, 'p_data': action == 'save' ? _set : <String, dynamic>{}}),
        ok: ok ?? tx(context, 'تم', 'Done'));
    if (d != null && mounted) {
      setState(() {
        _d = d;
        _set = Map<String, dynamic>.from((d['settings'] as Map?) ?? {});
        _dirty = false;
      });
    }
  }

  Future<void> _download() async {
    final d = _d;
    if (d == null) return;
    try {
      final t = await rootBundle.load('assets/excel/odoo_invoices_live.xlsx');
      final bytes = buildOdooExcel(t.buffer.asUint8List(), token: vStr(d['token']), refreshMin: vNum(_set['refresh_min']).toInt());
      final blob = html.Blob([Uint8List.fromList(bytes)], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..download = 'Odoo-invoices-live.xlsx'
        ..click();
      html.Url.revokeObjectUrl(url);
    } catch (e) {
      if (mounted) vToast(context, '${tx(context, 'ما قدرتش أعمل الملف', 'Could not build the file')}: $e', error: true);
    }
  }

  Future<void> _newToken() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tx(c, 'لينك جديد؟', 'New link?')),
        content: Text(tx(c, 'كل ملفات الإكسل اللي اتنزلت قبل كده هتقف فوراً، ولازم تنزّل الملف من جديد.',
            'Every Excel file downloaded before stops at once; the file must be downloaded again.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tx(c, 'إلغاء', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tx(c, 'لينك جديد', 'New link'))),
        ],
      ),
    );
    if (ok == true && mounted) await _act('new_token', ok: tx(context, 'اتعمل لينك جديد — نزّل الملف تاني', 'New link made — download the file again'));
  }

  Widget _num(String key, String ar, String en, String unitAr, String unitEn, String helpAr, String helpEn) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tx(context, ar, en), style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(tx(context, helpAr, helpEn), style: const TextStyle(fontSize: 12, color: _muted)),
            ]),
          ),
          SizedBox(
            width: 130,
            child: TextFormField(
              key: ValueKey('$key${_d.hashCode}'),
              initialValue: '${vNum(_set[key]).toInt()}',
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              decoration: InputDecoration(isDense: true, suffixText: tx(context, unitAr, unitEn), border: const OutlineInputBorder()),
              onChanged: (v) {
                _set[key] = int.tryParse(v.trim()) ?? 0;
                if (!_dirty) setState(() => _dirty = true);
              },
            ),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    if (_err != null && _d == null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(vErr(context, _err!)),
        OutlinedButton(onPressed: _load, child: Text(tx(context, 'إعادة المحاولة', 'Retry'))),
      ]));
    }
    final d = _d;
    if (d == null) return const Center(child: CircularProgressIndicator());
    final st = vMap(d['status']);
    final byMethod = vMap(st['by_method']);
    final byJournal = vMap(st['by_journal']);
    final err = vStr(st['last_error']);
    return ListView(padding: const EdgeInsets.only(bottom: 30), children: [
      HubHead(
        title: tx(context, 'لينك إكسل حي — فواتير Odoo', 'Excel live link — Odoo invoices'),
        subtitle: tx(context,
            'كل فواتير العملاء والـ Credit notes في Odoo (كل الدفاتر) في ملف إكسل بيتحدث لوحده لما يتفتح وكل كام دقيقة. قراءة بس من Odoo.',
            'Every customer invoice and credit note in Odoo (all journals) in an Excel file that refreshes itself on open and every few minutes. Read only from Odoo.'),
        actions: [
          HubButton(label: tx(context, 'تنزيل ملف الإكسل', 'Download the Excel file'), icon: Icons.download, onPressed: _download),
          HubButton(label: tx(context, 'تحديث', 'Refresh'), icon: Icons.refresh, onPressed: _load),
        ],
      ),
      HubKpis([
        HubKpi(Icons.receipt_long_outlined, '${vNum(st['count']).toInt()}', tx(context, 'فاتورة متنسخة من Odoo', 'Invoices copied from Odoo'),
            note: st['last_invoice'] == null ? null : tx(context, 'آخر تاريخ ${vStr(st['last_invoice'])}', 'Latest date ${vStr(st['last_invoice'])}')),
        HubKpi(Icons.sync, st['caught_up'] == true ? tx(context, 'محدّث', 'Up to date') : tx(context, 'بينسخ…', 'Copying…'),
            tx(context, 'آخر مزامنة ${_time(st['last_ok'])}', 'Last sync ${_time(st['last_ok'])}')),
        HubKpi(Icons.payments_outlined, '${vNum(byMethod['Cash']).toInt()} / ${vNum(byMethod['Card']).toInt()}', tx(context, 'كاش / كارت', 'Cash / card'),
            note: tx(context, '${vNum(byMethod['Free']).toInt()} مجاني · ${vNum(byMethod['Unpaid']).toInt()} مش مدفوع', '${vNum(byMethod['Free']).toInt()} free · ${vNum(byMethod['Unpaid']).toInt()} unpaid')),
      ]),
      if (err.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: HubCard(strong: true, child: Text(err, style: const TextStyle(color: _bad, fontWeight: FontWeight.w700))),
        ),
      // how to use
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        child: HubCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tx(context, 'إزاي تستخدمه', 'How to use it'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 6),
            for (final (ar, en) in const [
              ('1. نزّل الملف من «تنزيل ملف الإكسل» واحفظه عندك (أو على OneDrive / SharePoint).', '1. Download the file with "Download the Excel file" and keep it (or on OneDrive / SharePoint).'),
              ('2. أول مرة: «Enable content»، ولو سأل عن اللينك اختار Anonymous ← Connect.', '2. The first time: "Enable content", and if it asks about the link choose Anonymous → Connect.'),
              ('3. بيتحدث لوحده لما يتفتح وكل كام دقيقة وهو مفتوح · Data ← Refresh All للتحديث دلوقتي.', '3. It refreshes on open and every few minutes while open · Data → Refresh All to refresh now.'),
              ('الشيتات: كل الفواتير · Cash · Card · Free · Unpaid · Credit notes · فواتير مش فاليه · ملخص شهري ويومي.', 'Sheets: All invoices · Cash · Card · Free · Unpaid · Credit notes · Other invoices (not valet) · Summary per month and per day.'),
              ('محتاج Excel 365 / 2021 أو أحدث (شيتات الفلترة بتستخدم FILTER).', 'Needs Excel 365 / 2021 or newer (the filtered sheets use FILTER).'),
            ])
              Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(tx(context, ar, en), style: const TextStyle(fontSize: 13, height: 1.45))),
          ]),
        ),
      ),
      // options
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        child: HubCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Icon(Icons.tune),
              const SizedBox(width: 8),
              Expanded(child: Text(tx(context, 'الأوبشنز', 'Options'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
              FilledButton.icon(
                  onPressed: _dirty ? () => _act('save', ok: tx(context, 'تم الحفظ', 'Saved')) : null,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(tx(context, 'حفظ', 'Save'))),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _set['enabled'] != false,
              onChanged: (v) => setState(() {
                _set['enabled'] = v;
                _dirty = true;
              }),
              title: Text(tx(context, 'نسخ الفواتير من Odoo شغال', 'Copying the invoices from Odoo is on'), style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(tx(context, 'لو اتقفل: الملف بيفضل يقرا آخر نسخة', 'When off: the file keeps reading the last copy'), style: const TextStyle(fontSize: 12)),
            ),
            _num('refresh_min', 'الملف يتحدث كل', 'The file refreshes every', 'د', 'min', 'وهو مفتوح · 0 = لما يتفتح بس (بيتطبق على الملف اللي تنزّله بعد الحفظ)',
                'while open · 0 = on open only (applies to the file downloaded after saving)'),
            _num('recheck_min', 'مراجعة الفواتير المش مدفوعة كل', 'Recheck the unpaid invoices every', 'د', 'min', 'عشان حالة الدفع تتحدث', 'So the payment state stays right'),
            _num('batch', 'عدد الفواتير في كل طلب لـ Odoo', 'Invoices per Odoo call', '', '', '50 – 2000 · أكبر = أسرع في النسخ الأول', '50 – 2000 · bigger = faster first copy'),
            _num('page_size', 'صفوف كل صفحة في اللينك', 'Rows per link page', '', '', '500 – 10000', '500 – 10000'),
          ]),
        ),
      ),
      // breakdown + link actions
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        child: HubCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tx(context, 'التفاصيل', 'Breakdown'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final e in byMethod.entries) hubPill('${e.key}: ${vNum(e.value).toInt()}'),
            ]),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final e in byJournal.entries) hubPill('${e.key}: ${vNum(e.value).toInt()}', kind: 'dark'),
            ]),
            const Divider(height: 26),
            Wrap(spacing: 10, runSpacing: 10, children: [
              OutlinedButton.icon(onPressed: _newToken, icon: const Icon(Icons.key_outlined), label: Text(tx(context, 'لينك جديد (يوقف الملفات القديمة)', 'New link (stops the old files)'))),
              OutlinedButton.icon(
                onPressed: () => _act('resync', ok: tx(context, 'هيتنسخ كل حاجة من الأول خلال دقايق', 'Everything is copied again in a few minutes')),
                icon: const Icon(Icons.restart_alt),
                label: Text(tx(context, 'انسخ كل الفواتير من الأول', 'Copy all invoices again')),
              ),
            ]),
          ]),
        ),
      ),
    ]);
  }
}
