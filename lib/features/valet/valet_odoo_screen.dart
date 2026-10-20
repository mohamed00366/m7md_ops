import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'valet_admin.dart';
import 'valet_odoo_analytic.dart';
import 'valet_ui.dart';

/// 🔗 رَبط Odoo — كُلّ تِكِت يُدفَع (Check-out) يَصِل إلى Odoo فاتورة عَميل تِلقائيّاً خِلال دَقيقة.
class ValetOdooScreen extends StatelessWidget {
  const ValetOdooScreen({super.key});

  @override
  Widget build(BuildContext context) => const ValetGate(perm: ValetAdmin.permReports, child: _OdooBody());
}

class _OdooBody extends StatefulWidget {
  const _OdooBody();

  @override
  State<_OdooBody> createState() => _OdooBodyState();
}

class _OdooBodyState extends State<_OdooBody> {
  VJson? _s;
  bool _hasKey = false;
  VJson _stats = {};
  List<VJson>? _rows;
  Object? _err;
  String _status = '';
  String _q = '';

  bool get _edit => ValetAdmin.I.can(ValetAdmin.permSettings);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([
        ValetAdmin.I.call('vva_odoo_settings'),
        ValetAdmin.I.call('vva_odoo_queue', {'p_status': _status, 'p_query': _q, 'p_limit': 300}),
      ]);
      if (!mounted) return;
      setState(() {
        _s = vMap(r[0]['settings']);
        _hasKey = vBool(r[0]['has_key']);
        _stats = vMap(r[0]['stats']);
        _rows = vList(r[1]['rows']);
        _err = null;
      });
    } catch (e) {
      if (mounted) setState(() => _err = e);
    }
  }

  // ---------------------------------------------------------------- actions
  Future<void> _toggle(bool on) async {
    if (on && (!_hasKey || vStr(_s?['base_url']).isEmpty)) {
      vToast(context, tx(context, 'أَدخِل عُنوان Odoo وَمِفتاح الـAPI أَوّلاً.', 'Enter the Odoo address and API key first.'), error: true);
      return;
    }
    if (on &&
        !await vConfirm(
            context,
            tx(context, 'تَشغيل الرَبط', 'Switch the link on'),
            tx(context, 'مِن الآن كُلّ تِكِت يُدفَع سَيُرسَل إلى Odoo فاتورة عَميل مُرَحَّلة مَع الدَفع. التِكِتات القَديمة لا تُرسَل إلّا مِن "إرسال فَترة سابِقة".',
                'From now on every paid ticket is sent to Odoo as a posted customer invoice with its payment. Older tickets are sent only from "Send a past period".'))) {
      return;
    }
    if (!mounted) return;
    final r = await vGuard(context, () => ValetAdmin.I.call('vva_odoo_settings_save', {'p_data': {'enabled': on}}),
        ok: on ? tx(context, 'تَمّ تَشغيل الرَبط', 'Link switched on') : tx(context, 'تَمّ إيقاف الرَبط', 'Link switched off'));
    if (r != null) _load();
  }

  Future<void> _test() async {
    final res = await vGuard(context, () async {
      final r = await Supabase.instance.client.functions
          .invoke('odoo-sync', body: {'mode': 'test', 'token': ValetAdmin.I.token}).timeout(const Duration(seconds: 40));
      final d = vMap(r.data);
      if (d['ok'] != true) throw ValetError('${d['error'] ?? 'فَشَل الاتِّصال'}', '${d['error'] ?? 'Connection failed'}');
      return vMap(d['odoo']);
    });
    if (res == null || !mounted) return;
    final tax = vMap(res['tax']);
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.check_circle, color: VC.ok),
          const SizedBox(width: 8),
          Text(tx(c, 'الاتِّصال بِـOdoo ناجِح', 'Connected to Odoo')),
        ]),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              _kv(c, tx(c, 'الشَرِكة', 'Company'),
                  vList(res['companies']).map((x) => '${x['name']} (${x['currency']}${vStr(x['trn']).isEmpty ? '' : ' · TRN ${x['trn']}'})').join('\n')),
              _kv(
                  c,
                  tx(c, 'الضَريبة', 'Tax'),
                  res['tax_error'] != null
                      ? '⚠ ${res['tax_error']}'
                      : tax.isEmpty
                          ? '-'
                          : (vBool(tax['included']) ? tx(c, 'مَوجودة – شامِلة في السِعر', 'found – price included') : tx(c, 'مَوجودة – تُضاف على السِعر', 'found – added on top'))),
              _kv(c, tx(c, 'المُنتَج', 'Product'), vStr(res['product'])),
              _kv(c, tx(c, 'العَميل', 'Customer'), vStr(res['partner'])),
              const Divider(),
              Text(tx(c, 'اليَوميّات (اِستَخدِم الكود في الإعدادات):', 'Journals (use the code in the settings):'),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              ...vList(res['journals']).map((j) => Text('• ${j['code']} — ${j['name']}  (${j['type']})')),
            ]),
          ),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: Text(tx(c, 'تَمّ', 'OK')))],
      ),
    );
  }

  Widget _kv(BuildContext c, String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 90, child: Text(k, style: const TextStyle(color: VC.muted))),
          Expanded(child: Text(v)),
        ]),
      );

  Future<void> _retry(List<String> ids) async {
    if (ids.isEmpty) return;
    final r = await vGuard(context, () => ValetAdmin.I.call('vva_odoo_retry', {'p_ticket_ids': ids}));
    if (r != null && mounted) {
      vToast(context, tx(context, 'أُعيد إرسال ${r['count']} تِكِت', '${r['count']} ticket(s) queued again'));
      _load();
    }
  }

  Future<void> _backfill() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime(now.year, now.month, now.day),
      helpText: tx(context, 'إرسال تِكِتات فَترة سابِقة', 'Send tickets of a past period'),
    );
    if (r == null || !mounted) return;
    if (!await vConfirm(
        context,
        tx(context, 'إرسال فَترة سابِقة', 'Send a past period'),
        tx(context, 'سَتُرسَل كُلّ التِكِتات المَدفوعة مِن ${VF.date(r.start)} إلى ${VF.date(r.end)} الّتي لَم تُرسَل بَعد. التِكِت المُرسَل سابِقاً لا يَتَكَرَّر.',
            'All paid tickets from ${VF.date(r.start)} to ${VF.date(r.end)} not sent yet will be sent. A ticket already sent is never sent twice.'))) {
      return;
    }
    if (!mounted) return;
    final d = await vGuard(context, () => ValetAdmin.I.call('vva_odoo_backfill', {'p_from': VF.iso(r.start), 'p_to': VF.iso(r.end)}));
    if (d != null && mounted) {
      vToast(context, tx(context, 'أُضيف ${d['count']} تِكِت لِلإرسال', '${d['count']} ticket(s) queued'));
      _load();
    }
  }

  // ---------------------------------------------------------------- settings dialog
  Future<void> _settings() async {
    final s = _s ?? {};
    final url = TextEditingController(text: vStr(s['base_url']));
    final db = TextEditingController(text: vStr(s['database']));
    final key = TextEditingController();
    final partner = TextEditingController(text: vStr(s['walkin_partner']));
    final pCode = TextEditingController(text: vStr(s['product_code']));
    final pName = TextEditingController(text: vStr(s['product_name']));
    final lCode = TextEditingController(text: vStr(s['lost_code']));
    final lName = TextEditingController(text: vStr(s['lost_name']));
    final sales = TextEditingController(text: vStr(s['sales_journal']));
    final cash = TextEditingController(text: vStr(s['cash_journal']));
    final card = TextEditingController(text: vStr(s['card_journal']));
    final countries = TextEditingController(text: (s['countries'] as List? ?? const ['AE']).join(', '));
    var post = s['post_invoice'] != false;
    var pay = s['register_payment'] != false;
    var hide = true;

    Widget f(TextEditingController c, String label, {String? hint, String? helper}) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(controller: c, decoration: InputDecoration(labelText: label, hintText: hint, helperText: helper, isDense: true)),
        );

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(tx(c, 'إعدادات رَبط Odoo', 'Odoo link settings')),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                f(url, tx(c, 'عُنوان Odoo', 'Odoo address'), hint: 'https://ahmed72.odoo.com'),
                f(db, tx(c, 'اسم قاعِدة البَيانات', 'Database name'), hint: 'ahmed72'),
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(
                    controller: key,
                    obscureText: hide,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: tx(c, 'مِفتاح الـAPI', 'API key'),
                      helperText: _hasKey
                          ? tx(c, 'المِفتاح مَحفوظ (مُشَفَّر). اترُكه فارِغاً لِلإبقاء عَلَيه.', 'A key is saved (encrypted). Leave empty to keep it.')
                          : tx(c, 'مِن Odoo: التَفضيلات ← أَمان الحِساب ← New API Key', 'In Odoo: Preferences → Account Security → New API Key'),
                      suffixIcon: IconButton(icon: Icon(hide ? Icons.visibility : Icons.visibility_off), onPressed: () => set(() => hide = !hide)),
                    ),
                  ),
                ),
                f(countries, tx(c, 'الدُوَل المُرسَلة', 'Countries sent'),
                    helper: tx(c, 'رُموز الدُوَل مَفصولة بِفاصِلة، مِثل AE', 'Country codes separated by commas, e.g. AE')),
                const Divider(),
                f(partner, tx(c, 'اسم العَميل في الفاتورة', 'Invoice customer name'),
                    helper: tx(c, 'يُنشَأ في Odoo إن لَم يَكُن مَوجوداً', 'Created in Odoo if missing')),
                Row(children: [
                  Expanded(child: f(pCode, tx(c, 'كود مُنتَج الفاليه', 'Valet product code'))),
                  const SizedBox(width: 10),
                  Expanded(flex: 2, child: f(pName, tx(c, 'اسم المُنتَج', 'Product name'))),
                ]),
                Row(children: [
                  Expanded(child: f(lCode, tx(c, 'كود فُقدان التِكِت', 'Lost-ticket code'))),
                  const SizedBox(width: 10),
                  Expanded(flex: 2, child: f(lName, tx(c, 'اسم المُنتَج', 'Product name'))),
                ]),
                const Divider(),
                Text(tx(c, 'أَكواد اليَوميّات في Odoo (اترُكها فارِغة لِلافتِراضيّ)', 'Odoo journal codes (empty = default)'),
                    style: const TextStyle(color: VC.muted, fontSize: 12)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: f(sales, tx(c, 'المَبيعات', 'Sales'), hint: 'INV')),
                  const SizedBox(width: 10),
                  Expanded(child: f(cash, tx(c, 'الكاش', 'Cash'), hint: 'CSH1')),
                  const SizedBox(width: 10),
                  Expanded(child: f(card, tx(c, 'البِطاقة', 'Card'), hint: 'BNK1')),
                ]),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: post,
                  onChanged: (v) => set(() => post = v),
                  title: Text(tx(c, 'تَرحيل الفاتورة (Post)', 'Post the invoice')),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: pay,
                  onChanged: (v) => set(() => pay = v),
                  title: Text(tx(c, 'تَسجيل الدَفع (كاش / بِطاقة)', 'Register the payment (cash / card)')),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tx(c, 'إلغاء', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tx(c, 'حِفظ', 'Save'))),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final data = {
      'base_url': url.text.trim(),
      'database': db.text.trim(),
      if (key.text.trim().isNotEmpty) 'api_key': key.text.trim(),
      'countries': countries.text.split(RegExp(r'[,\s]+')).where((x) => x.trim().isNotEmpty).toList(),
      'walkin_partner': partner.text,
      'product_code': pCode.text,
      'product_name': pName.text,
      'lost_code': lCode.text,
      'lost_name': lName.text,
      'sales_journal': sales.text,
      'cash_journal': cash.text,
      'card_journal': card.text,
      'post_invoice': post,
      'register_payment': pay,
    };
    final r = await vGuard(context, () => ValetAdmin.I.call('vva_odoo_settings_save', {'p_data': data}), ok: tx(context, 'تَمّ الحِفظ', 'Saved'));
    if (r != null) _load();
  }

  // ---------------------------------------------------------------- UI
  VPill _pill(BuildContext c, String s) => switch (s) {
        'done' => VPill(tx(c, 'تَمّ', 'Sent'), color: VC.ok, icon: Icons.check),
        'pending' => VPill(tx(c, 'بِالانتِظار', 'Waiting'), color: VC.info, icon: Icons.schedule),
        'sending' => VPill(tx(c, 'جارٍ الإرسال', 'Sending'), color: VC.info, icon: Icons.sync),
        'error' => VPill(tx(c, 'خَطَأ', 'Error'), color: VC.bad, icon: Icons.error_outline),
        'skipped' => VPill(tx(c, 'مَجّاني – بِلا فاتورة', 'Free – no invoice')),
        _ => VPill(s),
      };

  @override
  Widget build(BuildContext context) {
    if (_err != null && _s == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(vErr(context, _err!), style: const TextStyle(color: VC.bad)),
          const SizedBox(height: 10),
          FilledButton(onPressed: _load, child: Text(tx(context, 'إعادة المُحاوَلة', 'Retry'))),
        ]),
      );
    }
    if (_s == null) return const Center(child: CircularProgressIndicator());
    final s = _s!;
    final on = vBool(s['enabled']);
    final rows = _rows ?? const <VJson>[];
    final errors = rows.where((r) => r['status'] == 'error').map((r) => vStr(r['ticket_id'])).toList();
    final base = vStr(s['base_url']);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        VHead(
          tx(context, 'رَبط Odoo', 'Odoo link'),
          subtitle: tx(context, 'كُلّ تِكِت يُدفَع يَصِل إلى Odoo فاتورة عَميل مُرَحَّلة مَع الدَفع – تِلقائيّاً خِلال دَقيقة',
              'Every paid ticket reaches Odoo as a posted customer invoice with its payment – automatically within a minute'),
          actions: [
            IconButton.filledTonal(onPressed: _load, icon: const Icon(Icons.refresh)),
            if (_edit) OutlinedButton.icon(onPressed: _settings, icon: const Icon(Icons.settings), label: Text(tx(context, 'الإعدادات', 'Settings'))),
            if (_edit)
              OutlinedButton.icon(onPressed: _test, icon: const Icon(Icons.wifi_tethering), label: Text(tx(context, 'اختِبار الاتِّصال', 'Test connection'))),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: VPanel(
            child: Wrap(spacing: 16, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Switch(value: on, onChanged: _edit ? _toggle : null),
                const SizedBox(width: 6),
                Text(on ? tx(context, 'الرَبط يَعمَل', 'Link is ON') : tx(context, 'الرَبط مُتَوَقِّف', 'Link is OFF'),
                    style: TextStyle(fontWeight: FontWeight.w800, color: on ? VC.ok : VC.muted)),
              ]),
              VPill(base.isEmpty ? tx(context, 'لا يُوجَد عُنوان', 'No address') : base, icon: Icons.link),
              VPill(_hasKey ? tx(context, 'المِفتاح مَحفوظ', 'API key saved') : tx(context, 'لا يُوجَد مِفتاح', 'No API key'),
                  color: _hasKey ? VC.ok : VC.warn, icon: Icons.key),
              if (s['start_from'] != null)
                VPill(tx(context, 'يُرسِل التِكِتات مِن ${VF.dt(vTime(s['start_from']))}', 'Sends tickets from ${VF.dt(vTime(s['start_from']))}'),
                    icon: Icons.event),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 10, runSpacing: 10, children: [
            VKpi(tx(context, 'أُرسِلت', 'Sent'), VF.n(vNum(_stats['done'])), icon: Icons.check_circle, color: VC.ok),
            VKpi(tx(context, 'بِالانتِظار', 'Waiting'), VF.n(vNum(_stats['pending']) + vNum(_stats['sending'])), icon: Icons.schedule, color: VC.info),
            VKpi(tx(context, 'أَخطاء', 'Errors'), VF.n(vNum(_stats['error'])), icon: Icons.error_outline, color: VC.bad),
            VKpi(tx(context, 'مَجّانيّة', 'Free'), VF.n(vNum(_stats['skipped'])), icon: Icons.money_off, color: VC.muted),
          ]),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: OdooAnalyticPanel(enabled: _hasKey && base.isNotEmpty),
        ),        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: VPanel(
            title: tx(context, 'سِجِلّ الإرسال', 'Send log'),
            actions: [
              if (_edit && errors.isNotEmpty)
                TextButton.icon(
                    onPressed: () => _retry(errors),
                    icon: const Icon(Icons.replay),
                    label: Text(tx(context, 'إعادة إرسال الأَخطاء (${errors.length})', 'Retry errors (${errors.length})'))),
              if (_edit)
                TextButton.icon(onPressed: _backfill, icon: const Icon(Icons.history), label: Text(tx(context, 'إرسال فَترة سابِقة', 'Send a past period'))),
            ],
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                for (final st in const ['', 'error', 'pending', 'done', 'skipped'])
                  ChoiceChip(
                    label: Text(switch (st) {
                      '' => tx(context, 'الكُلّ', 'All'),
                      'error' => tx(context, 'أَخطاء', 'Errors'),
                      'pending' => tx(context, 'بِالانتِظار', 'Waiting'),
                      'done' => tx(context, 'تَمّ', 'Sent'),
                      _ => tx(context, 'مَجّانيّة', 'Free'),
                    }),
                    selected: _status == st,
                    onSelected: (_) {
                      setState(() => _status = st);
                      _load();
                    },
                  ),
                SizedBox(
                  width: 240,
                  child: TextField(
                    decoration: InputDecoration(
                        isDense: true, prefixIcon: const Icon(Icons.search), hintText: tx(context, 'رَقم التِكِت / اللَوحة / الفاتورة', 'Ticket / plate / invoice')),
                    onSubmitted: (v) {
                      _q = v.trim();
                      _load();
                    },
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              VTable(
                empty: tx(context, 'لا شَيء بَعد. بَعد تَشغيل الرَبط تَظهَر هُنا كُلّ التِكِتات المَدفوعة.',
                    'Nothing yet. Once the link is on, every paid ticket shows here.'),
                columns: [
                  DataColumn(label: Text(tx(context, 'التِكِت', 'Ticket'))),
                  DataColumn(label: Text(tx(context, 'النُقطة', 'Point'))),
                  DataColumn(label: Text(tx(context, 'اللَوحة', 'Plate'))),
                  DataColumn(label: Text(tx(context, 'الدَفع', 'Payment'))),
                  DataColumn(numeric: true, label: Text(tx(context, 'المَبلَغ', 'Amount'))),
                  DataColumn(label: Text(tx(context, 'الخُروج', 'Exit'))),
                  DataColumn(label: Text(tx(context, 'الحالة', 'Status'))),
                  DataColumn(label: Text(tx(context, 'فاتورة Odoo', 'Odoo invoice'))),
                  const DataColumn(label: Text('')),
                ],
                rows: [
                  for (final r in rows)
                    DataRow(cells: [
                      DataCell(Text(vStr(r['ticket_code']))),
                      DataCell(Text(vStr(r['point']))),
                      DataCell(Text(vStr(r['plate']))),
                      DataCell(Text(vStr(r['payment_mode']))),
                      DataCell(Text(VF.money(vNum(r['amount'])))),
                      DataCell(Text(VF.dt(vTime(r['exit_time'])))),
                      DataCell(Tooltip(
                        message: vStr(r['last_error']),
                        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          _pill(context, vStr(r['status'])),
                          if (r['status'] == 'error')
                            SizedBox(
                              width: 260,
                              child: Text(vStr(r['last_error']),
                                  maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: VC.bad, fontSize: 11)),
                            ),
                        ]),
                      )),
                      DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(vStr(r['odoo_move_name']).isNotEmpty ? vStr(r['odoo_move_name']) : (r['odoo_move_id'] != null ? '#${r['odoo_move_id']}' : '-')),
                        if (vBool(r['odoo_payment'])) ...[const SizedBox(width: 6), const Icon(Icons.paid, size: 16, color: VC.ok)],
                      ])),
                      DataCell(_edit && (r['status'] == 'error')
                          ? IconButton(
                              tooltip: tx(context, 'إعادة الإرسال', 'Send again'),
                              icon: const Icon(Icons.replay, size: 18),
                              onPressed: () => _retry([vStr(r['ticket_id'])]))
                          : const SizedBox()),
                    ]),
                ],
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
