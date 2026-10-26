import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/services/excel_exporter.dart';
import 'valet_admin.dart';
import 'valet_ui.dart';

/// 📊 تَقارير الفاليه — نُقطة أَو كُلّ النِقاط، فَترة مَع مُقارَنة بِالفَترة السابِقة.
/// المال مِثل الوَرديّة وَOdoo: السِعر + البِطاقة المَفقودة + المَبيت، الدَفع المُقَسَّم، الفُروقات المَدفوعة لاحِقاً،
/// وَيُخصَم الإشعار الدائِن المُعتَمَد. أَوقات الخِدمة تُسَجَّل على الخادِم مُنذُ 279.
class ValetReportsScreen extends StatelessWidget {
  const ValetReportsScreen({super.key, this.initialTab = 0, this.title});

  /// 0 الملخص · 1 التشغيل · 2 الاستثناءات · 3 تطبيق العملاء · 4 الكي راك
  final int initialTab;

  /// عند الفتح مِن مَركَز التَقارير: شاشة كامِلة بِعُنوان.
  final String? title;

  @override
  Widget build(BuildContext context) {
    final body = ValetGate(perm: ValetAdmin.permReports, child: _ReportsBody(initialTab: initialTab));
    if (title == null) return body;
    return Scaffold(appBar: AppBar(title: Text(title!)), body: body);
  }
}

class _ReportsBody extends StatefulWidget {
  const _ReportsBody({this.initialTab = 0});
  final int initialTab;

  @override
  State<_ReportsBody> createState() => _ReportsBodyState();
}

class _ReportsBodyState extends State<_ReportsBody> with SingleTickerProviderStateMixin {
  late DateTime _from;
  late DateTime _to;
  VScope _scope = VScope.all;
  VJson? _d;
  Object? _err;
  bool _busy = false;
  late final TabController _tabs = TabController(length: 5, vsync: this, initialIndex: widget.initialTab.clamp(0, 4));

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _from = DateTime(n.year, n.month);
    _to = DateTime(n.year, n.month, n.day);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final d = await ValetAdmin.I.call('vva_report', {'p_from': VF.iso(_from), 'p_to': VF.iso(_to), 'p_point': null, 'p_scope': _scope.json});
      if (mounted) {
        setState(() {
          _d = d;
          _err = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _err = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------- excel
  Future<void> _export() async {
    final d = _d;
    if (d == null) return;
    final t = vMap(d['totals']);
    final p = vMap(d['prev']);
    List<List<dynamic>> rows(dynamic list, List<String> keys) => [for (final r in vList(list)) [for (final x in keys) r[x]]];
    await vExport(context, 'valet_report_${VF.iso(_from)}_${VF.iso(_to)}.xlsx', [
      ExcelSheet(name: 'Summary', headers: ['Item', 'This period', 'Previous period'], rows: [for (final e in t.entries) [e.key, e.value, p[e.key]]]),
      ExcelSheet(name: 'By day', headers: ['Day', 'Cars', 'Revenue'], rows: rows(d['by_day'], ['day', 'cars', 'revenue'])),
      ExcelSheet(
          name: 'By point',
          headers: ['Code', 'Point', 'Cars', 'Revenue', 'Tips', 'Free', 'Avg wait (s)', 'Within 5 min %', 'Open now'],
          rows: rows(d['by_point'], ['code', 'point', 'cars', 'revenue', 'tips', 'free', 'avg_wait_s', 'sla', 'open'])),
      ExcelSheet(name: 'By area', headers: ['Area', 'Points', 'Cars', 'Revenue', 'Tips'], rows: rows(d['by_area'], ['area', 'points', 'cars', 'revenue', 'tips'])),
      ExcelSheet(name: 'By client', headers: ['Client', 'Branches', 'Cars', 'Revenue'], rows: rows(d['by_client_sales'], ['client', 'branches', 'cars', 'revenue'])),
      ExcelSheet(name: 'By payment', headers: ['Payment', 'Cars', 'Revenue'], rows: rows(d['by_payment'], ['mode', 'cars', 'revenue'])),
      ExcelSheet(name: 'By ticket type', headers: ['Type', 'Cars', 'Revenue'], rows: rows(d['by_type'], ['type', 'cars', 'revenue'])),
      ExcelSheet(name: 'Validations', headers: ['Client', 'Cars'], rows: rows(d['by_client'], ['client', 'validations'])),
      ExcelSheet(
          name: 'Staff',
          headers: ['Code', 'Name', 'Received', 'Delivered', 'Tips', 'Avg wait (s)', 'Free', 'Voids'],
          rows: rows(d['staff'], ['code', 'name', 'received', 'delivered', 'tips', 'avg_wait_s', 'free', 'voids'])),
      ExcelSheet(
          name: 'Shifts',
          headers: ['Code', 'Kind', 'Point', 'Status', 'Start', 'End', 'Opened by', 'Cars', 'Cash', 'Card', 'Counted', 'Difference', 'Note'],
          rows: rows(d['shifts'], ['code', 'kind', 'point', 'status', 'start', 'end', 'opened_by', 'cars', 'cash', 'card', 'counted', 'diff', 'note'])),
      ExcelSheet(
          name: 'Voids', headers: ['Ticket', 'Point', 'Plate', 'Reason', 'At', 'By'], rows: rows(vMap(d['exceptions'])['voids'], ['code', 'point', 'plate', 'reason', 'at', 'by'])),
      ExcelSheet(
          name: 'Open 24h+', headers: ['Ticket', 'Point', 'Plate', 'Entry'], rows: rows(vMap(d['exceptions'])['stale'], ['code', 'point', 'plate', 'entry'])),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return Column(children: [
      VHead(tx(context, 'تَقارير الفاليه', 'Valet reports'),
          subtitle: tx(context, 'مَنطِقة أَو عَميل أَو فَرع أَو نُقطة · مُقارَنة بِالفَترة السابِقة', 'Area, client, branch or point · compared with the previous period'),
          actions: [
            VScopeFilter(value: _scope, onChanged: (v) {
              _scope = v;
              _load();
            }),
            IconButton.filledTonal(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh)),
            OutlinedButton.icon(onPressed: d == null ? null : _export, icon: const Icon(Icons.download), label: const Text('Excel')),
          ]),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: VRange(from: _from, to: _to, onChanged: (a, b) {
            _from = a;
            _to = b;
            _load();
          }),
        ),
      ),
      SizedBox(height: 2, child: _busy ? const LinearProgressIndicator(minHeight: 2) : null),
      TabBar(controller: _tabs, isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
        Tab(icon: const Icon(Icons.insights, size: 18), text: tx(context, 'المُلَخَّص', 'Summary')),
        Tab(icon: const Icon(Icons.timer_outlined, size: 18), text: tx(context, 'التَشغيل', 'Operations')),
        Tab(icon: const Icon(Icons.report_gmailerrorred, size: 18), text: tx(context, 'الاستِثناءات', 'Exceptions')),
        Tab(icon: const Icon(Icons.phone_iphone, size: 18), text: tx(context, 'تَطبيق العُمَلاء', 'Customer app')),
        Tab(icon: const Icon(Icons.key, size: 18), text: tx(context, 'الكي راك', 'Key rack')),
      ]),
      const Divider(height: 1),
      Expanded(
        child: _err != null
            ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(vErr(context, _err!), style: const TextStyle(color: VC.bad))))
            : d == null
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(controller: _tabs, children: [
                    _page(_summary(d)),
                    _page(_operations(d)),
                    _page(_exceptions(d)),
                    _page(_customer(d)),
                    _page(_keyrack(d)),
                  ]),
      ),
    ]);
  }

  Widget _page(List<Widget> children) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [for (final c in children) Padding(padding: const EdgeInsets.only(bottom: 12), child: c)],
      );

  Widget _kpis(List<Widget> k) => Wrap(spacing: 10, runSpacing: 10, children: k);

  String get _prevLabel {
    final d = _d;
    if (d == null) return '';
    return '${VF.date(DateTime.tryParse(vStr(d['prev_from'])))} – ${VF.date(DateTime.tryParse(vStr(d['prev_to'])))}';
  }

  Widget _info(String ar, String en, {Color color = VC.info, IconData icon = Icons.info_outline}) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withValues(alpha: 0.3))),
        child: Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(tx(context, ar, en), style: TextStyle(color: color, fontSize: 13))),
        ]),
      );

  // ---------------------------------------------------------------- summary
  List<Widget> _summary(VJson d) {
    final t = vMap(d['totals']);
    final p = vMap(d['prev']);
    final days = vList(d['by_day']);
    final net = vNum(t['revenue']);
    return [
      _kpis([
        _Delta(tx(context, 'صافي الإيراد (AED)', 'Net revenue (AED)'), VF.money(net), vNum(t['revenue']), vNum(p['revenue']),
            icon: Icons.payments_outlined, color: VC.ok, note: 'VAT ${VF.money(vNum(t['vat']))}'),
        _Delta(tx(context, 'السَيّارات', 'Cars'), VF.n(vNum(t['cars'])), vNum(t['cars']), vNum(p['cars']),
            icon: Icons.directions_car, note: tx(context, '${VF.n(vNum(t['cars_in']))} دَخَلَت', '${VF.n(vNum(t['cars_in']))} came in')),
        _Delta(tx(context, 'مُتَوَسِّط التَذكَرة', 'Average ticket'), VF.money(vNum(t['avg_ticket'])), vNum(t['avg_ticket']), vNum(p['avg_ticket']),
            icon: Icons.receipt_long),
        _Delta(tx(context, 'الإكراميّات', 'Tips'), VF.money(vNum(t['tips'])), vNum(t['tips']), vNum(p['tips']),
            icon: Icons.volunteer_activism_outlined, note: tx(context, 'نَقد ${VF.money(vNum(t['cash_tips']))}', 'Cash ${VF.money(vNum(t['cash_tips']))}')),
        VKpi(tx(context, 'نَقداً', 'Cash'), VF.money(vNum(t['cash'])), icon: Icons.money),
        VKpi(tx(context, 'بِطاقة', 'Card'), VF.money(vNum(t['card'])), icon: Icons.credit_card),
        VKpi(tx(context, 'مَجّانيّة', 'Free'), VF.n(vNum(t['free'])), icon: Icons.money_off,
            note: tx(context, '${VF.n(vNum(t['validated']))} مُتَحَقَّق مِنها', '${VF.n(vNum(t['validated']))} validated')),
        VKpi(tx(context, 'مَفتوحة الآن', 'Open now'), VF.n(vNum(t['open_now'])), icon: Icons.local_parking,
            color: vNum(t['stale']) > 0 ? VC.warn : VC.info,
            note: vNum(t['stale']) > 0 ? tx(context, '${VF.n(vNum(t['stale']))} مُنذُ أَكثَر مِن 24 ساعة', '${VF.n(vNum(t['stale']))} older than 24h') : null),
      ]),
      Text(tx(context, 'الأَسهُم تُقارِن بِـ $_prevLabel', 'Arrows compare with $_prevLabel'), style: const TextStyle(color: VC.muted, fontSize: 12)),
      VPanel(
        title: tx(context, 'كَيف حُسِبَ الإيراد', 'How the revenue adds up'),
        child: Wrap(spacing: 18, runSpacing: 8, children: [
          _line(tx(context, 'مَبيعات التَذاكِر', 'Ticket sales'), vNum(t['sales'])),
          _line(tx(context, '+ فُروقات دُفِعَت لاحِقاً', '+ Paid later'), vNum(t['extra'])),
          _line(tx(context, '− إشعارات دائِنة (${VF.n(vNum(t['credits_n']))})', '− Credit notes (${VF.n(vNum(t['credits_n']))})'), vNum(t['credits']), bad: true),
          _line(tx(context, '= الصافي', '= Net'), net, bold: true),
          _line(tx(context, 'مِنها بِطاقات مَفقودة (${VF.n(vNum(t['lost_n']))})', 'Incl. lost tickets (${VF.n(vNum(t['lost_n']))})'), vNum(t['lost'])),
          _line(tx(context, 'مِنها مَبيت', 'Incl. overnight'), vNum(t['overnight'])),
          _line(tx(context, 'خُصومات القَسائِم (${VF.n(vNum(t['vouchers']))})', 'Voucher discounts (${VF.n(vNum(t['vouchers']))})'), vNum(t['voucher_discount'])),
          if (vNum(t['memberships']) > 0) _line(tx(context, 'اشتِراكات (عَدَد)', 'Memberships (count)'), vNum(t['memberships']), count: true),
          if (vNum(t['manual_cars']) > 0) _line(tx(context, 'تَذاكِر وَرَقيّة (سَيّارات)', 'Paper tickets (cars)'), vNum(t['manual_cars']), count: true),
        ]),
      ),
      if (days.isNotEmpty) VPanel(title: tx(context, 'الإيراد وَالسَيّارات يَوميّاً', 'Revenue and cars per day'), child: SizedBox(height: 240, child: _dayChart(days))),
      if (vList(d['by_area']).isNotEmpty)
        _table(tx(context, 'حَسَب المَنطِقة', 'By area'), [
          tx(context, 'المَنطِقة', 'Area'),
          tx(context, 'نِقاط', 'Points'),
          tx(context, 'سَيّارات', 'Cars'),
          tx(context, 'إيراد', 'Revenue'),
          tx(context, 'إكراميّات', 'Tips'),
        ], [
          for (final r in vList(d['by_area']))
            [vStr(r['area']) == '-' ? tx(context, 'بِلا مَنطِقة', 'No area') : vStr(r['area']), VF.n(vNum(r['points'])), VF.n(vNum(r['cars'])), VF.money(vNum(r['revenue'])), VF.money(vNum(r['tips']))]
        ]),
      if (vList(d['by_client_sales']).isNotEmpty)
        _table(tx(context, 'حَسَب العَميل', 'By client'), [
          tx(context, 'العَميل', 'Client'),
          tx(context, 'فُروع', 'Branches'),
          tx(context, 'سَيّارات', 'Cars'),
          tx(context, 'إيراد', 'Revenue'),
        ], [
          for (final r in vList(d['by_client_sales']))
            [vStr(r['client']) == '-' ? tx(context, 'بِلا عَميل (زُوّار)', 'No client (visitors)') : vStr(r['client']), VF.n(vNum(r['branches'])), VF.n(vNum(r['cars'])), VF.money(vNum(r['revenue']))]
        ]),
      _table(tx(context, 'حَسَب النُقطة', 'By point'), [
        tx(context, 'النُقطة', 'Point'),
        tx(context, 'سَيّارات', 'Cars'),
        tx(context, 'إيراد', 'Revenue'),
        tx(context, 'إكراميّات', 'Tips'),
        tx(context, 'مَجّانيّة', 'Free'),
        tx(context, 'انتِظار', 'Wait'),
        tx(context, 'مَفتوحة', 'Open'),
      ], [
        for (final r in vList(d['by_point']))
          [
            '${vStr(r['code'])}  ${vStr(r['point'])}',
            VF.n(vNum(r['cars'])),
            VF.money(vNum(r['revenue'])),
            VF.money(vNum(r['tips'])),
            VF.n(vNum(r['free'])),
            _dur(r['avg_wait_s']),
            VF.n(vNum(r['open'])),
          ]
      ]),
      Wrap(spacing: 12, runSpacing: 12, children: [
        SizedBox(
            width: 420,
            child: _table(tx(context, 'طَريقة الدَفع', 'Payment'), [tx(context, 'الدَفع', 'Payment'), tx(context, 'سَيّارات', 'Cars'), tx(context, 'إيراد', 'Revenue')],
                [for (final r in vList(d['by_payment'])) [vStr(r['mode']), VF.n(vNum(r['cars'])), VF.money(vNum(r['revenue']))]])),
        SizedBox(
            width: 420,
            child: _table(tx(context, 'التَحَقُّقات حَسَب العَميل', 'Validations by client'), [tx(context, 'العَميل', 'Client'), tx(context, 'سَيّارات', 'Cars')],
                [for (final r in vList(d['by_client'])) [vStr(r['client']), VF.n(vNum(r['validations']))]])),
      ]),
      _table(tx(context, 'نَوع التَذكَرة', 'Ticket type'), [tx(context, 'النَوع', 'Type'), tx(context, 'سَيّارات', 'Cars'), tx(context, 'إيراد', 'Revenue')],
          [for (final r in vList(d['by_type'])) [vStr(r['type']), VF.n(vNum(r['cars'])), VF.money(vNum(r['revenue']))]]),
    ];
  }

  Widget _line(String label, num v, {bool bold = false, bool bad = false, bool count = false}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: VC.muted, fontSize: 12)),
        Text(count ? VF.n(v) : VF.money(v), style: TextStyle(fontSize: bold ? 18 : 15, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: bad && v > 0 ? VC.bad : null)),
      ]);

  // ---------------------------------------------------------------- operations
  List<Widget> _operations(VJson d) {
    final s = vMap(d['service']);
    final b = vMap(s['buckets']);
    final measured = vNum(s['measured']);
    final staff = vList(d['staff']);
    return [
      if (measured == 0)
        _info('أَوقات الانتِظار تُسَجَّل تِلقائيّاً مِن الآن: وَقت الطَلَب (مِن التَطبيق أَو المُوَظَّف) وَوَقت تَسليم السَيّارة. سَتَظهَر هُنا مَع التَذاكِر الجَديدة.',
            'Waiting times are now recorded automatically: the request time (customer app or staff) and the hand-over time. They will show here with the new tickets.'),
      _kpis([
        VKpi(tx(context, 'مُتَوَسِّط الانتِظار', 'Average wait'), _dur(s['avg_wait_s']), icon: Icons.hourglass_bottom, color: _waitColor(s['avg_wait_s']),
            note: tx(context, 'مِن الطَلَب لِلتَسليم', 'Request to hand-over')),
        VKpi(tx(context, 'الوَسيط', 'Median wait'), _dur(s['median_wait_s']), icon: Icons.align_horizontal_center),
        VKpi(tx(context, '90٪ خِلال', '90% within'), _dur(s['p90_wait_s']), icon: Icons.speed),
        VKpi(tx(context, 'خِلال 5 دَقائِق', 'Within 5 min'), s['sla_pct'] == null ? '-' : '${vNum(s['sla_pct'])}%', icon: Icons.verified_outlined,
            color: s['sla_pct'] == null ? null : (vNum(s['sla_pct']) >= 80 ? VC.ok : VC.warn)),
        VKpi(tx(context, 'مُتَوَسِّط الرَكن', 'Average parking'), _dur(s['avg_park_s']), icon: Icons.local_parking,
            note: tx(context, 'مِن الدُخول لِلرَكن · ${VF.n(vNum(s['parked_measured']))}', 'Entry to parked · ${VF.n(vNum(s['parked_measured']))}')),
        VKpi(tx(context, 'طَلَبات مَقيسة', 'Measured requests'), '${VF.n(measured)} / ${VF.n(vNum(s['closed']))}', icon: Icons.fact_check_outlined),
      ]),
      if (measured > 0)
        VPanel(
          title: tx(context, 'تَوزيع الانتِظار', 'Waiting time spread'),
          child: _bars([
            (tx(context, '≤ 3 د', '≤ 3 min'), vNum(b['b3']), VC.ok),
            (tx(context, '3–5 د', '3–5 min'), vNum(b['b5']), VC.info),
            (tx(context, '5–10 د', '5–10 min'), vNum(b['b10']), VC.warn),
            (tx(context, '> 10 د', '> 10 min'), vNum(b['b10p']), VC.bad),
          ]),
        ),
      VPanel(
        title: tx(context, 'ساعات الذُروة (سَيّارات دَخَلَت)', 'Peak hours (cars in)'),
        child: _Heatmap(cells: [for (final e in (d['heat'] is List ? d['heat'] as List : const [])) if (e is List && e.length == 3) [for (final x in e) vNum(x).toInt()]]),
      ),
      if (vList(s['by_hour']).isNotEmpty)
        _table(tx(context, 'الانتِظار حَسَب ساعة الطَلَب', 'Wait by request hour'), [tx(context, 'الساعة', 'Hour'), tx(context, 'طَلَبات', 'Requests'), tx(context, 'مُتَوَسِّط', 'Average')], [
          for (final r in vList(s['by_hour'])) ['${vNum(r['hour']).toInt().toString().padLeft(2, '0')}:00', VF.n(vNum(r['n'])), _dur(r['avg_wait_s'])]
        ]),
      _table(tx(context, 'أَداء المُوَظَّفين', 'Staff performance'), [
        tx(context, 'المُوَظَّف', 'Staff'),
        tx(context, 'استَلَم', 'Received'),
        tx(context, 'سَلَّم', 'Delivered'),
        tx(context, 'إكراميّات', 'Tips'),
        tx(context, 'انتِظار', 'Wait'),
        tx(context, 'مَجّانيّة', 'Free'),
        tx(context, 'مُلغاة', 'Voids'),
      ], [
        for (final r in staff)
          [
            '${vStr(r['name'])}${vStr(r['code']).isEmpty ? '' : '  ·  ${vStr(r['code'])}'}',
            VF.n(vNum(r['received'])),
            VF.n(vNum(r['delivered'])),
            VF.money(vNum(r['tips'])),
            _dur(r['avg_wait_s']),
            VF.n(vNum(r['free'])),
            VF.n(vNum(r['voids'])),
          ]
      ]),
    ];
  }

  // ---------------------------------------------------------------- exceptions
  List<Widget> _exceptions(VJson d) {
    final x = vMap(d['exceptions']);
    final t = vMap(d['totals']);
    final voids = vList(x['voids']);
    final stale = vList(x['stale']);
    final shifts = vList(d['shifts']);
    final short = shifts.where((s) => s['diff'] != null && vNum(s['diff']) != 0).length;
    return [
      _kpis([
        VKpi(tx(context, 'مُلغاة', 'Voids'), VF.n(voids.length), icon: Icons.block, color: voids.isNotEmpty ? VC.bad : null),
        VKpi(tx(context, 'مَجّانيّة بِلا تَحَقُّق', 'Free, not validated'), VF.n(vNum(x['free_unvalidated'])), icon: Icons.money_off,
            color: vNum(x['free_unvalidated']) > 0 ? VC.warn : null, note: tx(context, 'مِن ${VF.n(vNum(x['free']))} مَجّانيّة', 'of ${VF.n(vNum(x['free']))} free')),
        VKpi(tx(context, 'خُصومات', 'Discounts'), VF.n(vNum(x['discounts'])), icon: Icons.percent, note: VF.money(vNum(t['discounts']))),
        VKpi(tx(context, 'تَذاكِر مَفقودة', 'Lost tickets'), VF.n(vNum(x['lost'])), icon: Icons.confirmation_number_outlined),
        VKpi(tx(context, 'بَقيَت +12 ساعة', 'Stayed 12h+'), VF.n(vNum(x['long_stay'])), icon: Icons.nightlight_outlined),
        VKpi(tx(context, 'مَفتوحة +24 ساعة', 'Open 24h+'), VF.n(stale.length), icon: Icons.warning_amber, color: stale.isNotEmpty ? VC.warn : null),
        VKpi(tx(context, 'وَرديّات بِفَرق نَقد', 'Shifts with cash difference'), VF.n(short), icon: Icons.account_balance_wallet_outlined, color: short > 0 ? VC.bad : null),
      ]),
      _table(tx(context, 'التَذاكِر المُلغاة', 'Void tickets'), [
        tx(context, 'التَذكَرة', 'Ticket'),
        tx(context, 'النُقطة', 'Point'),
        tx(context, 'اللَوحة', 'Plate'),
        tx(context, 'السَبَب', 'Reason'),
        tx(context, 'الوَقت', 'At'),
        tx(context, 'بِواسِطة', 'By'),
      ], [
        for (final r in voids) [VF.short(vStr(r['code'])), vStr(r['point']), vStr(r['plate']), vStr(r['reason']), VF.dt(DateTime.tryParse(vStr(r['at']))?.toLocal()), vStr(r['by'])]
      ]),
      _table(tx(context, 'تَذاكِر مَفتوحة مُنذُ أَكثَر مِن 24 ساعة', 'Tickets open for more than 24 hours'), [
        tx(context, 'التَذكَرة', 'Ticket'),
        tx(context, 'النُقطة', 'Point'),
        tx(context, 'اللَوحة', 'Plate'),
        tx(context, 'الدُخول', 'Entry'),
      ], [
        for (final r in stale) [VF.short(vStr(r['code'])), vStr(r['point']), vStr(r['plate']), VF.dt(DateTime.tryParse(vStr(r['entry']))?.toLocal())]
      ]),
      _table(tx(context, 'الوَرديّات وَالنَقد', 'Shifts and cash'), [
        tx(context, 'الوَرديّة', 'Shift'),
        tx(context, 'النُقطة', 'Point'),
        tx(context, 'البِداية', 'Start'),
        tx(context, 'فَتَحَها', 'Opened by'),
        tx(context, 'سَيّارات', 'Cars'),
        tx(context, 'نَقد مُتَوَقَّع', 'Cash expected'),
        tx(context, 'مَعدود', 'Counted'),
        tx(context, 'الفَرق', 'Difference'),
      ], [
        for (final r in shifts)
          [
            '${vStr(r['code'])}${vStr(r['kind']) == 'keyrack' ? ' 🔑' : ''}',
            vStr(r['point']),
            VF.dt(DateTime.tryParse(vStr(r['start']))?.toLocal()),
            vStr(r['opened_by']),
            VF.n(vNum(r['cars'])),
            VF.money(vNum(r['cash'])),
            r['counted'] == null ? '-' : VF.money(vNum(r['counted'])),
            r['diff'] == null ? '-' : VF.money(vNum(r['diff'])),
          ]
      ], highlight: (row) => row.last != '-' && row.last != VF.money(0)),
    ];
  }

  // ---------------------------------------------------------------- customer app
  List<Widget> _customer(VJson d) {
    final c = vMap(d['customer']);
    final app = vNum(c['app']);
    final staff = vNum(c['staff']);
    final all = app + staff;
    return [
      if (all == 0)
        _info('مِن الآن يُسَجَّل مَصدَر كُلّ طَلَب: تَطبيق العَميل (رابِط/QR التَذكَرة) أَو المُوَظَّف. الأَرقام تَبدَأ مَع التَذاكِر الجَديدة.',
            'From now on every request records its source: the customer app (ticket link / QR) or the staff. The numbers start with the new tickets.'),
      _kpis([
        VKpi(tx(context, 'طَلَبات مِن التَطبيق', 'Requests from the app'), VF.n(app), icon: Icons.phone_iphone, color: VC.info),
        VKpi(tx(context, 'طَلَبات مِن المُوَظَّف', 'Requests by staff'), VF.n(staff), icon: Icons.badge_outlined),
        VKpi(tx(context, 'نِسبة استِخدام التَطبيق', 'App adoption'), all == 0 ? '-' : '${(100 * app / all).round()}%', icon: Icons.trending_up, color: VC.ok),
        VKpi(tx(context, 'انتِظار طَلَب التَطبيق', 'Wait, app request'), _dur(c['app_wait_s']), icon: Icons.hourglass_bottom),
        VKpi(tx(context, 'انتِظار طَلَب المُوَظَّف', 'Wait, staff request'), _dur(c['staff_wait_s']), icon: Icons.hourglass_bottom),
      ]),
      _table(tx(context, 'استِخدام التَطبيق حَسَب النُقطة', 'App use by point'), [tx(context, 'النُقطة', 'Point'), tx(context, 'مِن التَطبيق', 'From app'), tx(context, 'كُلّ الطَلَبات', 'All requests'), '%'], [
        for (final r in vList(c['app_by_point']))
          [vStr(r['point']), VF.n(vNum(r['app'])), VF.n(vNum(r['all'])), vNum(r['all']) == 0 ? '-' : '${(100 * vNum(r['app']) / vNum(r['all'])).round()}%']
      ]),
      _table(tx(context, 'التَحَقُّقات (الفَنادِق وَالمَحَلّات)', 'Validations (hotels and shops)'), [tx(context, 'العَميل', 'Client'), tx(context, 'سَيّارات', 'Cars')],
          [for (final r in vList(d['by_client'])) [vStr(r['client']), VF.n(vNum(r['validations']))]]),
    ];
  }

  // ---------------------------------------------------------------- key rack
  List<Widget> _keyrack(VJson d) {
    final k = vMap(d['keyrack']);
    return [
      _kpis([
        VKpi(tx(context, 'مَفاتيح استُلِمَت', 'Keys received'), VF.n(vNum(k['received'])), icon: Icons.key),
        VKpi(tx(context, 'طَلَبات مَفاتيح', 'Key requests'), VF.n(vNum(k['requests'])), icon: Icons.notifications_active_outlined),
        VKpi(tx(context, 'مُتَوَسِّط إخراج المِفتاح', 'Average key out'), _dur(k['avg_out_s']), icon: Icons.timer_outlined, note: tx(context, 'مِن الطَلَب لِلتَسليم', 'Request to hand-out')),
        VKpi(tx(context, 'عَلى اللَوحة الآن', 'On the rack now'), VF.n(vNum(k['on_rack'])), icon: Icons.grid_view),
        VKpi(tx(context, 'عَلى اللَوحة +24 ساعة', 'On the rack 24h+'), VF.n(vNum(k['aging'])), icon: Icons.warning_amber, color: vNum(k['aging']) > 0 ? VC.warn : null),
        VKpi(tx(context, 'سُلِّمَت وَالمِفتاح لَم يُغلَق', 'Delivered, key not closed'), VF.n(vNum(k['mismatch'])), icon: Icons.link_off,
            color: vNum(k['mismatch']) > 0 ? VC.bad : null),
      ]),
      _table(tx(context, 'مُوَظَّفو المَفاتيح', 'Key controllers'), [tx(context, 'المُوَظَّف', 'Staff'), tx(context, 'مَفاتيح', 'Keys'), tx(context, 'مُتَوَسِّط الإخراج', 'Average key out')],
          [for (final r in vList(k['by_controller'])) [vStr(r['name']), VF.n(vNum(r['keys'])), _dur(r['avg_out_s'])]]),
    ];
  }

  // ---------------------------------------------------------------- helpers
  String _dur(dynamic s) {
    if (s == null) return '-';
    final v = vNum(s).round();
    if (v < 60) return '${v}s';
    final m = v ~/ 60;
    if (m < 60) return '${m}m ${(v % 60).toString().padLeft(2, '0')}s';
    return '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m';
  }

  Color? _waitColor(dynamic s) {
    if (s == null) return null;
    final v = vNum(s);
    return v <= 300 ? VC.ok : (v <= 600 ? VC.warn : VC.bad);
  }

  Widget _table(String title, List<String> head, List<List<String>> rows, {bool Function(List<String>)? highlight}) => VPanel(
        title: title,
        child: VTable(
          columns: [for (var i = 0; i < head.length; i++) DataColumn(label: Text(head[i]), numeric: i > 0)],
          rows: [
            for (final r in rows)
              DataRow(
                color: highlight != null && highlight(r) ? WidgetStatePropertyAll(VC.bad.withValues(alpha: 0.07)) : null,
                cells: [for (final c in r) DataCell(Text(c))],
              )
          ],
        ),
      );

  Widget _bars(List<(String, num, Color)> items) {
    final total = items.fold<num>(0, (a, e) => a + e.$2);
    return Column(children: [
      for (final e in items)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            SizedBox(width: 80, child: Text(e.$1, style: const TextStyle(fontSize: 13))),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(value: total == 0 ? 0 : e.$2 / total, minHeight: 14, color: e.$3, backgroundColor: e.$3.withValues(alpha: 0.12)),
              ),
            ),
            SizedBox(width: 90, child: Text('  ${VF.n(e.$2)}  ·  ${total == 0 ? 0 : (100 * e.$2 / total).round()}%', style: const TextStyle(fontSize: 12))),
          ]),
        ),
    ]);
  }

  Widget _dayChart(List<VJson> days) {
    final maxY = days.fold<num>(0, (a, r) => vNum(r['revenue']) > a ? vNum(r['revenue']) : a).toDouble();
    final maxC = days.fold<num>(0, (a, r) => vNum(r['cars']) > a ? vNum(r['cars']) : a).toDouble();
    final top = maxY <= 0 ? 10.0 : maxY * 1.15;
    final k = maxC <= 0 ? 1.0 : top / (maxC * 1.15);
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: top,
        gridData: const FlGridData(drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => [
              for (final s in spots)
                LineTooltipItem(
                  s.barIndex == 0
                      ? '${vStr(days[s.x.toInt()]['day'])}\nAED ${VF.money(vNum(days[s.x.toInt()]['revenue']))}'
                      : '${VF.n(vNum(days[s.x.toInt()]['cars']))} ${tx(context, 'سَيّارة', 'cars')}',
                  TextStyle(color: s.barIndex == 0 ? VC.gold : VC.info, fontWeight: FontWeight.w700, fontSize: 12),
                ),
            ],
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              getTitlesWidget: (v, _) => Text(VF.n(v / k), style: const TextStyle(fontSize: 10, color: VC.info)),
            ),
          ),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 46)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: 1,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= days.length || v != i) return const SizedBox();
                if (days.length > 16 && i % (days.length ~/ 8) != 0) return const SizedBox();
                final s = vStr(days[i]['day']);
                return Text(s.length >= 10 ? '${s.substring(8, 10)}/${s.substring(5, 7)}' : s, style: const TextStyle(fontSize: 11, color: VC.muted));
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [for (var i = 0; i < days.length; i++) FlSpot(i.toDouble(), vNum(days[i]['revenue']).toDouble())],
            color: VC.gold,
            barWidth: 3,
            isCurved: true,
            preventCurveOverShooting: true,
            dotData: FlDotData(show: days.length <= 31),
            belowBarData: BarAreaData(show: true, color: VC.gold.withValues(alpha: 0.12)),
          ),
          LineChartBarData(
            spots: [for (var i = 0; i < days.length; i++) FlSpot(i.toDouble(), vNum(days[i]['cars']).toDouble() * k)],
            color: VC.info,
            barWidth: 2,
            dashArray: const [6, 4],
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }
}

/// بِطاقة رَقم مَع سَهم المُقارَنة بِالفَترة السابِقة.
class _Delta extends StatelessWidget {
  const _Delta(this.label, this.value, this.now, this.prev, {required this.icon, this.color, this.note});
  final String label;
  final String value;
  final num now;
  final num prev;
  final IconData icon;
  final Color? color;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final pct = prev == 0 ? (now == 0 ? 0 : null) : ((now - prev) * 100 / prev).round();
    final up = now >= prev;
    final c = now == prev ? VC.muted : (up ? VC.ok : VC.bad);
    return Stack(children: [
      VKpi(label, value, icon: icon, color: color, note: note),
      PositionedDirectional(
        bottom: 8,
        end: 10,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(now == prev ? Icons.remove : (up ? Icons.arrow_upward : Icons.arrow_downward), size: 13, color: c),
          Text(pct == null ? tx(context, 'جَديد', 'new') : '${pct.abs()}%', style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w700)),
        ]),
      ),
    ]);
  }
}

/// خَريطة ساعات الذُروة: الأَيّام × الساعات (تَوقيت دُبَي).
class _Heatmap extends StatelessWidget {
  const _Heatmap({required this.cells});
  final List<List<int>> cells; // [isodow 1-7, hour 0-23, count]

  @override
  Widget build(BuildContext context) {
    final m = <int, int>{for (final c in cells) c[0] * 100 + c[1]: c[2]};
    final mx = cells.fold<int>(0, (a, c) => c[2] > a ? c[2] : a);
    if (mx == 0) return Padding(padding: const EdgeInsets.all(16), child: Text(tx(context, 'لا تُوجَد بَيانات.', 'Nothing to show.'), style: const TextStyle(color: VC.muted)));
    final names = [
      tx(context, 'الإثنَين', 'Mon'),
      tx(context, 'الثُلاثاء', 'Tue'),
      tx(context, 'الأَربِعاء', 'Wed'),
      tx(context, 'الخَميس', 'Thu'),
      tx(context, 'الجُمعة', 'Fri'),
      tx(context, 'السَبت', 'Sat'),
      tx(context, 'الأَحَد', 'Sun'),
    ];
    final best = cells.reduce((a, b) => b[2] > a[2] ? b : a);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Column(children: [
            Row(children: [
              const SizedBox(width: 74),
              for (var h = 0; h < 24; h++)
                SizedBox(width: 30, child: Text(h % 3 == 0 ? h.toString().padLeft(2, '0') : '', textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: VC.muted))),
            ]),
            for (var d = 1; d <= 7; d++)
              Row(children: [
                SizedBox(width: 74, child: Text(names[d - 1], style: const TextStyle(fontSize: 12))),
                for (var h = 0; h < 24; h++)
                  Tooltip(
                    message: '${names[d - 1]} ${h.toString().padLeft(2, '0')}:00 · ${m[d * 100 + h] ?? 0}',
                    child: Container(
                      width: 28,
                      height: 22,
                      margin: const EdgeInsets.all(1),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: (m[d * 100 + h] ?? 0) == 0 ? Colors.grey.withValues(alpha: 0.08) : VC.gold.withValues(alpha: 0.15 + 0.85 * (m[d * 100 + h]! / mx)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: (m[d * 100 + h] ?? 0) == 0
                          ? null
                          : Text('${m[d * 100 + h]}', style: TextStyle(fontSize: 10, color: m[d * 100 + h]! / mx > 0.55 ? Colors.white : Colors.black87)),
                    ),
                  ),
              ]),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        tx(context, 'الأَكثَر ازدِحاماً: ${names[best[0] - 1]} ${best[1].toString().padLeft(2, '0')}:00 (${best[2]} سَيّارة)',
            'Busiest: ${names[best[0] - 1]} ${best[1].toString().padLeft(2, '0')}:00 (${best[2]} cars)'),
        style: const TextStyle(color: VC.muted, fontSize: 12),
      ),
    ]);
  }
}
