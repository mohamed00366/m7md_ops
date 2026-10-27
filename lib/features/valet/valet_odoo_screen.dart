import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'valet_admin.dart';
import 'valet_credits_screen.dart';
import 'valet_odoo_analytic.dart';
import 'valet_ui.dart';

/// 🧮 الرَبط مَعَ بَرنامِج الحِسابات (Odoo) — كُلّ تِكِت يُدفَع (Check-out) يَصِل إلى Odoo فاتورة عَميل تِلقائيّاً خِلال دَقيقة.
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

  Future<void> _load({bool refill = false}) async {
    try {
      final r = await Future.wait([
        ValetAdmin.I.call('vva_odoo_settings'),
        ValetAdmin.I.call('vva_odoo_queue', {'p_status': _status, 'p_query': _q, 'p_limit': 300}),
      ]);
      if (!mounted) return;
      final first = _s == null;
      setState(() {
        _s = vMap(r[0]['settings']);
        if (first || refill || !_dirty) _fill(_s!);
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
      if (d['ok'] != true) {
        if (mounted) setState(() => _testError = '${d['error'] ?? 'Connection failed'}');
        throw ValetError('${d['error'] ?? 'فَشَل الاتِّصال'}', '${d['error'] ?? 'Connection failed'}');
      }
      return vMap(d['odoo']);
    });
    if (res == null || !mounted) return;
    setState(() {
      _testedAt = DateTime.now();
      _testError = null;
    });
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

  // ---------------------------------------------------------------- settings (inline tab)
  final _c = <String, TextEditingController>{};
  bool _post = true, _pay = true, _hideKey = true, _dirty = false;
  DateTime? _testedAt;
  String? _testError;

  TextEditingController _ctl(String k) => _c.putIfAbsent(k, () => TextEditingController()..addListener(() => _dirty = true));

  void _fill(VJson s) {
    for (final k in const ['base_url', 'database', 'walkin_partner', 'product_code', 'product_name', 'lost_code', 'lost_name', 'sales_journal', 'cash_journal', 'card_journal']) {
      _ctl(k).text = vStr(s[k]);
    }
    _ctl('countries').text = (s['countries'] as List? ?? const ['AE']).join(', ');
    _ctl('api_key').text = '';
    _post = s['post_invoice'] != false;
    _pay = s['register_payment'] != false;
    _dirty = false;
  }

  Future<void> _saveSettings() async {
    final data = {
      'base_url': _ctl('base_url').text.trim(),
      'database': _ctl('database').text.trim(),
      if (_ctl('api_key').text.trim().isNotEmpty) 'api_key': _ctl('api_key').text.trim(),
      'countries': _ctl('countries').text.split(RegExp(r'[,\s]+')).where((x) => x.trim().isNotEmpty).map((x) => x.trim().toUpperCase()).toList(),
      'walkin_partner': _ctl('walkin_partner').text,
      'product_code': _ctl('product_code').text,
      'product_name': _ctl('product_name').text,
      'lost_code': _ctl('lost_code').text,
      'lost_name': _ctl('lost_name').text,
      'sales_journal': _ctl('sales_journal').text,
      'cash_journal': _ctl('cash_journal').text,
      'card_journal': _ctl('card_journal').text,
      'post_invoice': _post,
      'register_payment': _pay,
    };
    final r = await vGuard(context, () => ValetAdmin.I.call('vva_odoo_settings_save', {'p_data': data}), ok: tx(context, 'تَمّ الحِفظ', 'Saved'));
    if (r != null) {
      _dirty = false;
      _load(refill: true);
    }
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
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

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
    final rows = _rows ?? const <VJson>[];
    final errors = vNum(_stats['error']).toInt();
    return DefaultTabController(
      length: 4,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _header(context),
        const ValetOdooAlerts(),
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 0), child: _hero(context)),
        const SizedBox(height: 8),
        TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: VC.gold,
          tabs: [
            Tab(icon: const Icon(Icons.insights_outlined, size: 18), iconMargin: const EdgeInsets.only(bottom: 2), text: tx(context, 'نَظرة عامّة', 'Overview')),
            Tab(icon: const Icon(Icons.tune, size: 18), iconMargin: const EdgeInsets.only(bottom: 2), text: tx(context, 'إعدادات الرَبط', 'Link settings')),
            Tab(icon: const Icon(Icons.sell_outlined, size: 18), iconMargin: const EdgeInsets.only(bottom: 2), text: tx(context, 'الحِسابات التَحليليّة', 'Analytic accounts')),
            Tab(
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                iconMargin: const EdgeInsets.only(bottom: 2),
                text: errors > 0 ? tx(context, 'سِجِلّ الإرسال · $errors خَطَأ', 'Send log · $errors errors') : tx(context, 'سِجِلّ الإرسال', 'Send log')),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: TabBarView(children: [
            RefreshIndicator(onRefresh: _load, child: _overview(context, rows)),
            _settingsTab(context),
            ListView(padding: const EdgeInsets.all(16), children: [OdooAnalyticPanel(enabled: _hasKey && vStr(_s!['base_url']).isNotEmpty)]),
            RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [_log(context, rows)])),
          ]),
        ),
      ]),
    );
  }

  // ---------------------------------------------------------------- header + hero
  Widget _header(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Row(children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              gradient: const LinearGradient(colors: [Color(0xFFF3D77A), VC.gold], begin: Alignment.topLeft, end: Alignment.bottomRight),
              boxShadow: [BoxShadow(color: VC.gold.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 5))],
            ),
            child: const Icon(Icons.calculate_outlined, color: Color(0xFF16181D), size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tx(context, 'الرَبط مَعَ بَرنامِج الحِسابات', 'Accounting link'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              Text(
                  tx(context, 'كُلّ تِكِت يُدفَع يَصِل إلى بَرنامِج الحِسابات فاتورة عَميل مُرَحَّلة مَعَ الدَفع – تِلقائيّاً خِلال دَقيقة',
                      'Every paid ticket reaches the accounting system as a posted customer invoice with its payment – automatically within a minute'),
                  style: const TextStyle(color: VC.muted, fontSize: 13)),
            ]),
          ),
          const SizedBox(width: 10),
          IconButton.filledTonal(tooltip: tx(context, 'تَحديث', 'Refresh'), onPressed: _load, icon: const Icon(Icons.refresh)),
          if (_edit) ...[
            const SizedBox(width: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF16181D), foregroundColor: Colors.white),
              onPressed: _test,
              icon: const Icon(Icons.wifi_tethering),
              label: Text(tx(context, 'اختِبار الاتِّصال', 'Test connection')),
            ),
          ],
        ]),
      );

  DateTime? get _lastSent {
    DateTime? m;
    for (final r in _rows ?? const <VJson>[]) {
      final t = vTime(r['sent_at']);
      if (t != null && (m == null || t.isAfter(m))) m = t;
    }
    return m;
  }

  Widget _hero(BuildContext context) {
    final s = _s!;
    final on = vBool(s['enabled']);
    final base = vStr(s['base_url']);
    Widget chip(bool ok, String text, {IconData? icon}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon ?? (ok ? Icons.check_rounded : Icons.error_outline), size: 16, color: ok ? const Color(0xFF4ADE80) : const Color(0xFFFBBF24)),
            const SizedBox(width: 6),
            Text(text, style: const TextStyle(color: Colors.white, fontSize: 12.5)),
          ]),
        );
    final last = _lastSent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(colors: [Color(0xFF16181D), Color(0xFF2A2E36)], begin: Alignment.topRight, end: Alignment.bottomLeft),
      ),
      child: Wrap(spacing: 22, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Switch(value: on, activeTrackColor: VC.gold, onChanged: _edit ? _toggle : null),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 9, height: 9, decoration: BoxDecoration(shape: BoxShape.circle, color: on ? const Color(0xFF4ADE80) : VC.muted)),
              const SizedBox(width: 7),
              Text(on ? tx(context, 'الرَبط يَعمَل', 'Link is ON') : tx(context, 'الرَبط مُتَوَقِّف', 'Link is OFF'),
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
            ]),
            Text(
                last == null
                    ? 'Odoo'
                    : tx(context, 'Odoo · آخِر إرسال ${VF.since(context, last)}', 'Odoo · last sent ${VF.since(context, last)} ago'),
                style: const TextStyle(color: Color(0xFFB7BCC6), fontSize: 12.5)),
          ]),
        ]),
        chip(base.isNotEmpty, base.isEmpty ? tx(context, 'لا يُوجَد عُنوان', 'No address') : base.replaceFirst('https://', '')),
        chip(vStr(s['database']).isNotEmpty, vStr(s['database']).isEmpty ? tx(context, 'لا قاعِدة بَيانات', 'No database') : tx(context, 'قاعِدة البَيانات: ${s['database']}', 'Database: ${s['database']}')),
        chip(_hasKey, _hasKey ? tx(context, 'المِفتاح مَحفوظ (مُشَفَّر)', 'API key saved (encrypted)') : tx(context, 'لا يُوجَد مِفتاح', 'No API key')),
        if (s['start_from'] != null) chip(true, tx(context, 'يُرسِل مِن ${VF.dt(vTime(s['start_from']))}', 'Sends from ${VF.dt(vTime(s['start_from']))}')),
        chip(true, (s['countries'] as List? ?? const ['AE']).join(' · '), icon: Icons.public),
      ]),
    );
  }

  // ---------------------------------------------------------------- overview tab
  Widget _overview(BuildContext context, List<VJson> rows) {
    final s = _s!;
    final base = vStr(s['base_url']);
    String or(String v, String d) => v.trim().isEmpty ? d : v.trim();
    final journals = [or(vStr(s['sales_journal']), 'INV'), or(vStr(s['cash_journal']), tx(context, 'افتِراضي', 'default')), or(vStr(s['card_journal']), tx(context, 'افتِراضي', 'default'))];

    Widget step(int n, Color c, String t, String sub) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: VC.muted.withValues(alpha: 0.25))),
            child: Column(children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(11)),
                child: Text('$n', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 6),
              Text(t, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(sub, textAlign: TextAlign.center, style: const TextStyle(color: VC.muted, fontSize: 12)),
            ]),
          ),
        );
    Widget arrow() => const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Icon(Icons.arrow_back, size: 18, color: VC.muted));

    Widget ready(bool ok, String t, String v) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: VC.muted.withValues(alpha: 0.22))),
          child: Row(children: [
            Icon(ok ? Icons.check_circle : Icons.error, size: 20, color: ok ? VC.ok : VC.warn),
            const SizedBox(width: 10),
            Expanded(child: Text(t, style: const TextStyle(fontWeight: FontWeight.w600))),
            Text(v, style: const TextStyle(color: VC.muted, fontSize: 12.5)),
          ]),
        );

    final flow = VPanel(
      title: tx(context, 'كَيف يَعمَل الرَبط', 'How the link works'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          step(1, const Color(0xFF16181D), tx(context, 'دَفع التِكِت', 'Ticket paid'), tx(context, 'كاش / بِطاقة', 'Cash / card')),
          arrow(),
          step(2, const Color(0xFF714B67), tx(context, 'فاتورة عَميل', 'Customer invoice'),
              '${or(vStr(s['product_code']), 'VALET')} · ${journals[0]}'),
          arrow(),
          step(3, VC.gold, tx(context, 'تَرحيل', 'Posted'), vBool(s['post_invoice'] ?? true) ? tx(context, 'Post تِلقائي', 'Auto post') : tx(context, 'مُسَوَّدة', 'Draft')),
          arrow(),
          step(4, VC.ok, tx(context, 'تَسجيل الدَفع', 'Payment'),
              s['register_payment'] != false ? '${journals[1]} / ${journals[2]}' : tx(context, 'مُتَوَقِّف', 'Off')),
        ]),
        const SizedBox(height: 14),
        Text(tx(context, 'آخِر الفَواتير', 'Latest invoices'), style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        _table(context, rows.take(6).toList(), compact: true),
      ]),
    );

    final readiness = VPanel(
      title: tx(context, 'جاهِزيّة الرَبط', 'Link readiness'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ready(base.isNotEmpty && _hasKey && _testError == null, tx(context, 'الاتِّصال بِـ Odoo', 'Connection to Odoo'),
            _testError != null
                ? tx(context, 'فَشَل الاختِبار', 'Test failed')
                : _testedAt != null
                    ? tx(context, 'نَجَح الاختِبار ${VF.time(_testedAt)}', 'Test OK ${VF.time(_testedAt)}')
                    : (base.isNotEmpty && _hasKey ? tx(context, 'العُنوان وَالمِفتاح مَحفوظان', 'Address and key saved') : tx(context, 'أَكمِل الإعدادات', 'Complete the settings'))),
        ready(true, tx(context, 'مُنتَج الفاليه وَمُنتَج التِكِت المَفقود', 'Valet and lost-ticket products'),
            '${or(vStr(s['product_code']), 'VALET')} · ${or(vStr(s['lost_code']), tx(context, 'افتِراضي', 'default'))}'),
        ready(true, tx(context, 'اليَوميّات: مَبيعات / كاش / بِطاقة', 'Journals: sales / cash / card'), journals.join(' · ')),
        ready((s['countries'] as List? ?? const ['AE']).isNotEmpty, tx(context, 'الدُوَل المُرسَلة', 'Countries sent'), (s['countries'] as List? ?? const ['AE']).join(' · ')),
        ready(vNum(_stats['error']) == 0, tx(context, 'أَخطاء الإرسال', 'Send errors'), VF.n(vNum(_stats['error']))),
        if (_edit) ...[
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              onPressed: vNum(_stats['error']) == 0 ? null : () => _retry(rows.where((r) => r['status'] == 'error').map((r) => vStr(r['ticket_id'])).toList()),
              icon: const Icon(Icons.replay),
              label: Text(tx(context, 'إعادة إرسال الأَخطاء', 'Retry errors')),
            ),
            OutlinedButton.icon(onPressed: _backfill, icon: const Icon(Icons.history), label: Text(tx(context, 'إرسال فَترة سابِقة', 'Send a past period'))),
          ]),
        ],
      ]),
    );

    return LayoutBuilder(
      builder: (context, box) => ListView(padding: const EdgeInsets.all(16), children: [
        Wrap(spacing: 10, runSpacing: 10, children: [
          VKpi(tx(context, 'أُرسِلَت فَواتير', 'Invoices sent'), VF.n(vNum(_stats['done'])), icon: Icons.check_circle, color: VC.ok),
          VKpi(tx(context, 'بِالانتِظار', 'Waiting'), VF.n(vNum(_stats['pending']) + vNum(_stats['sending'])), icon: Icons.schedule, color: VC.info,
              note: tx(context, 'تُرسَل خِلال دَقيقة', 'sent within a minute')),
          VKpi(tx(context, 'أَخطاء', 'Errors'), VF.n(vNum(_stats['error'])), icon: Icons.error_outline, color: VC.bad),
          VKpi(tx(context, 'مَجّانيّة – بِلا فاتورة', 'Free – no invoice'), VF.n(vNum(_stats['skipped'])), icon: Icons.money_off, color: VC.muted),
        ]),
        const SizedBox(height: 14),
        if (box.maxWidth >= 1000)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 5, child: flow),
            const SizedBox(width: 14),
            Expanded(flex: 4, child: readiness),
          ])
        else ...[
          flow,
          const SizedBox(height: 14),
          readiness,
        ],
      ]),
    );
  }

  // ---------------------------------------------------------------- settings tab
  Widget _settingsTab(BuildContext context) {
    final s = _s!;
    final edit = _edit;
    Widget f(String k, String label, {String? hint, String? helper, bool mono = false, Widget? suffix, bool secret = false}) => TextField(
          controller: _ctl(k),
          enabled: edit,
          obscureText: secret && _hideKey,
          style: mono ? const TextStyle(fontFamily: 'monospace') : null,
          decoration: InputDecoration(isDense: true, labelText: label, hintText: hint, helperText: helper, helperMaxLines: 2, suffixIcon: suffix),
        );
    Widget card(IconData icon, String title, String hint, List<Widget> children) => VPanel(
          title: title,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(hint, style: const TextStyle(color: VC.muted, fontSize: 12.5)),
            const SizedBox(height: 12),
            ...children,
          ]),
        );
    Widget row(List<Widget> c) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = 0; i < c.length; i++) ...[if (i > 0) const SizedBox(width: 12), Expanded(child: c[i])],
          ]),
        );
    Widget opt(String t, String sub, bool v, ValueChanged<bool> on) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          decoration: BoxDecoration(
            color: v ? VC.gold.withValues(alpha: 0.07) : null,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: v ? VC.gold.withValues(alpha: 0.6) : VC.muted.withValues(alpha: 0.25)),
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(sub, style: const TextStyle(color: VC.muted, fontSize: 12.5)),
              ]),
            ),
            Switch(value: v, activeTrackColor: VC.gold, onChanged: edit ? (x) => setState(() => on(x)) : null),
          ]),
        );

    final connection = card(Icons.power_outlined, tx(context, 'الاتِّصال', 'Connection'), tx(context, 'بَرنامِج الحِسابات وَبَيانات الدُخول', 'The accounting system and its sign-in'), [
      row([
        InputDecorator(
          decoration: InputDecoration(isDense: true, labelText: tx(context, 'البَرنامِج', 'System')),
          child: Row(children: [
            const Text('Odoo', style: TextStyle(fontWeight: FontWeight.w800)),
            const Spacer(),
            if (_hasKey && vStr(s['base_url']).isNotEmpty) VPill(tx(context, 'مُتَّصِل', 'Connected'), color: VC.ok, icon: Icons.check),
          ]),
        ),
        f('base_url', tx(context, 'عُنوان Odoo', 'Odoo address'), hint: 'https://ahmed72.odoo.com', mono: true),
        f('database', tx(context, 'اسم قاعِدة البَيانات', 'Database name'), hint: 'ahmed72', mono: true),
      ]),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          flex: 2,
          child: f('api_key', tx(context, 'مِفتاح الـAPI', 'API key'),
              secret: true,
              hint: _hasKey ? '••••••••••••' : null,
              helper: _hasKey
                  ? tx(context, '🔒 مَحفوظ مُشَفَّر · اترُكه فارِغاً لِلإبقاء عَلَيه', '🔒 Saved encrypted · leave empty to keep it')
                  : tx(context, 'Odoo ← التَفضيلات ← أَمان الحِساب ← New API Key', 'Odoo → Preferences → Account Security → New API Key'),
              suffix: IconButton(icon: Icon(_hideKey ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => _hideKey = !_hideKey))),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (edit)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF16181D), foregroundColor: Colors.white),
                onPressed: _test,
                icon: const Icon(Icons.wifi_tethering),
                label: Text(tx(context, 'اختِبار الاتِّصال', 'Test connection')),
              ),
            if (_testedAt != null && _testError == null) VPill(tx(context, 'نَجَح ${VF.time(_testedAt)}', 'OK ${VF.time(_testedAt)}'), color: VC.ok, icon: Icons.check),
            if (_testError != null) VPill(tx(context, 'فَشَل', 'Failed'), color: VC.bad, icon: Icons.error_outline),
          ]),
        ),
      ]),
    ]);

    final what = card(Icons.outbox_outlined, tx(context, 'ماذا يُرسَل', 'What is sent'), tx(context, 'أَيّ تِكِتات تَصِل إلى الحِسابات', 'Which tickets reach the accounts'), [
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: f('countries', tx(context, 'الدُوَل', 'Countries'), hint: 'AE', helper: tx(context, 'رُموز الدُوَل مَفصولة بِفاصِلة، مِثل AE, SA', 'Country codes separated by commas, e.g. AE, SA'), mono: true),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: InputDecorator(
          decoration: InputDecoration(
              isDense: true,
              labelText: tx(context, 'يُرسِل مِن تاريخ', 'Sends from'),
              helperText: tx(context, 'ما قَبله يُرسَل فَقَط مِن «إرسال فَترة سابِقة»', 'Older tickets are sent only from "Send a past period"')),
          child: Text(s['start_from'] == null ? tx(context, 'مِن وَقت تَشغيل الرَبط', 'From when the link is switched on') : VF.dt(vTime(s['start_from']))),
        ),
      ),
      f('walkin_partner', tx(context, 'اسم العَميل في الفاتورة', 'Invoice customer name'), helper: tx(context, 'يُنشَأ في Odoo إن لَم يَكُن مَوجوداً', 'Created in Odoo if missing')),
    ]);

    final invoice = card(Icons.receipt_long_outlined, tx(context, 'الفاتورة وَالمُنتَجات', 'Invoice and products'), tx(context, 'بُنود الفاتورة في Odoo', 'Invoice lines in Odoo'), [
      row([f('product_code', tx(context, 'كود مُنتَج الفاليه', 'Valet product code'), mono: true), f('product_name', tx(context, 'اسم المُنتَج', 'Product name'))]),
      row([f('lost_code', tx(context, 'كود التِكِت المَفقود', 'Lost-ticket code'), mono: true), f('lost_name', tx(context, 'اسم المُنتَج', 'Product name'))]),
      ListenableBuilder(
        listenable: Listenable.merge([for (final k in const ['product_name', 'lost_name', 'walkin_partner']) _ctl(k)]),
        builder: (context, _) => _invoicePreview(context),
      ),
    ]);

    final journals = card(Icons.menu_book_outlined, tx(context, 'اليَوميّات', 'Journals'), tx(context, 'فارِغ = اليَوميّة الافتِراضيّة في Odoo', 'Empty = the default journal in Odoo'), [
      row([
        f('sales_journal', tx(context, 'المَبيعات', 'Sales'), hint: 'INV', mono: true),
        f('cash_journal', tx(context, 'الكاش', 'Cash'), hint: 'CSH1', mono: true),
        f('card_journal', tx(context, 'البِطاقة', 'Card'), hint: 'BNK1', mono: true),
      ]),
    ]);

    final posting = card(Icons.bolt_outlined, tx(context, 'خِيارات التَرحيل', 'Posting options'), tx(context, 'ماذا يَحدُث لِلفاتورة بَعد إنشائها', 'What happens to the invoice after it is created'), [
      opt(tx(context, 'تَرحيل الفاتورة (Post)', 'Post the invoice'), tx(context, 'الفاتورة تُرَحَّل فَوراً بَدَل مُسَوَّدة', 'The invoice is posted at once instead of a draft'), _post, (v) => _post = v),
      opt(tx(context, 'تَسجيل الدَفع', 'Register the payment'), tx(context, 'دَفعة كاش أَو بِطاقة عَلى نَفس الفاتورة', 'A cash or card payment on the same invoice'), _pay, (v) => _pay = v),
    ]);

    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 1000;
      Widget pair(Widget a, Widget b) => wide
          ? IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: a), const SizedBox(width: 14), Expanded(child: b)]))
          : Column(children: [a, const SizedBox(height: 14), b]);
      return ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          Expanded(
            child: Text(tx(context, 'التَغييرات تُطَبَّق عَلى التِكِتات القادِمة فَقَط.', 'Changes apply to the next tickets only.'),
                style: const TextStyle(color: VC.muted)),
          ),
          if (edit)
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: VC.gold, foregroundColor: const Color(0xFF16181D)),
              onPressed: _saveSettings,
              icon: const Icon(Icons.save_outlined),
              label: Text(tx(context, 'حِفظ الإعدادات', 'Save settings')),
            ),
        ]),
        const SizedBox(height: 12),
        connection,
        const SizedBox(height: 14),
        pair(what, invoice),
        const SizedBox(height: 14),
        pair(journals, posting),
      ]);
    });
  }

  Widget _invoicePreview(BuildContext context) {
    String or(String k, String d) => _ctl(k).text.trim().isEmpty ? d : _ctl(k).text.trim();
    Widget line(String a, String b, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(a, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w400))),
            Text(b, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w400)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: VC.muted.withValues(alpha: 0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tx(context, 'مُعايَنة فاتورة (مِثال)', 'Invoice preview (example)'), style: const TextStyle(color: VC.muted, fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        line('${or('product_name', 'Valet Parking')} · T-0054', '333.33'),
        line(or('lost_name', 'Lost ticket'), '0.00'),
        line('VAT 5%', '16.67'),
        const Divider(height: 12),
        line(tx(context, 'الإجمالي · ${or('walkin_partner', 'Walk-in')}', 'Total · ${or('walkin_partner', 'Walk-in')}'), '350.00 AED', bold: true),
      ]),
    );
  }

  // ---------------------------------------------------------------- send log tab
  Widget _log(BuildContext context, List<VJson> rows) {
    final errors = rows.where((r) => r['status'] == 'error').map((r) => vStr(r['ticket_id'])).toList();
    return VPanel(
      title: tx(context, 'سِجِلّ الإرسال', 'Send log'),
      actions: [
        if (_edit && errors.isNotEmpty)
          TextButton.icon(
              onPressed: () => _retry(errors),
              icon: const Icon(Icons.replay),
              label: Text(tx(context, 'إعادة إرسال الأَخطاء (${errors.length})', 'Retry errors (${errors.length})'))),
        if (_edit) TextButton.icon(onPressed: _backfill, icon: const Icon(Icons.history), label: Text(tx(context, 'إرسال فَترة سابِقة', 'Send a past period'))),
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
              decoration: InputDecoration(isDense: true, prefixIcon: const Icon(Icons.search), hintText: tx(context, 'رَقم التِكِت / اللَوحة / الفاتورة', 'Ticket / plate / invoice')),
              onSubmitted: (v) {
                _q = v.trim();
                _load();
              },
            ),
          ),
        ]),
        const SizedBox(height: 8),
        _table(context, rows),
      ]),
    );
  }

  Widget _table(BuildContext context, List<VJson> rows, {bool compact = false}) => VTable(
        empty: tx(context, 'لا شَيء بَعد. بَعد تَشغيل الرَبط تَظهَر هُنا كُلّ التِكِتات المَدفوعة.', 'Nothing yet. Once the link is on, every paid ticket shows here.'),
        columns: [
          DataColumn(label: Text(tx(context, 'التِكِت', 'Ticket'))),
          DataColumn(label: Text(tx(context, 'النُقطة', 'Point'))),
          if (!compact) DataColumn(label: Text(tx(context, 'اللَوحة', 'Plate'))),
          DataColumn(label: Text(tx(context, 'الدَفع', 'Payment'))),
          DataColumn(numeric: true, label: Text(tx(context, 'المَبلَغ', 'Amount'))),
          if (!compact) DataColumn(label: Text(tx(context, 'الخُروج', 'Exit'))),
          DataColumn(label: Text(tx(context, 'الحالة', 'Status'))),
          DataColumn(label: Text(tx(context, 'الفاتورة', 'Invoice'))),
          if (!compact) const DataColumn(label: Text('')),
        ],
        rows: [
          for (final r in rows)
            DataRow(cells: [
              DataCell(Text(vStr(r['ticket_code']))),
              DataCell(Text(vStr(r['point']))),
              if (!compact) DataCell(Text(vStr(r['plate']))),
              DataCell(Text(vStr(r['payment_mode']))),
              DataCell(Text(VF.money(vNum(r['amount'])))),
              if (!compact) DataCell(Text(VF.dt(vTime(r['exit_time'])))),
              DataCell(Tooltip(
                message: vStr(r['last_error']),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _pill(context, vStr(r['status'])),
                  if (!compact && r['status'] == 'error')
                    SizedBox(
                      width: 260,
                      child: Text(vStr(r['last_error']), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: VC.bad, fontSize: 11)),
                    ),
                ]),
              )),
              DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                Text(vStr(r['odoo_move_name']).isNotEmpty ? vStr(r['odoo_move_name']) : (r['odoo_move_id'] != null ? '#${r['odoo_move_id']}' : '-')),
                if (vBool(r['odoo_payment'])) ...[const SizedBox(width: 6), const Icon(Icons.paid, size: 16, color: VC.ok)],
              ])),
              if (!compact)
                DataCell(_edit && (r['status'] == 'error')
                    ? IconButton(tooltip: tx(context, 'إعادة الإرسال', 'Send again'), icon: const Icon(Icons.replay, size: 18), onPressed: () => _retry([vStr(r['ticket_id'])]))
                    : const SizedBox()),
            ]),
        ],
      );
}
