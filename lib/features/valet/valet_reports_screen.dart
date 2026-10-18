import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/services/excel_exporter.dart';
import 'valet_admin.dart';
import 'valet_ui.dart';

/// 📊 تَقارير الفاليه — التَذاكِر المُغلَقة في الفَترة (بِدون المُلغاة).
class ValetReportsScreen extends StatelessWidget {
  const ValetReportsScreen({super.key});

  @override
  Widget build(BuildContext context) => const ValetGate(perm: ValetAdmin.permReports, child: _ReportsBody());
}

class _ReportsBody extends StatefulWidget {
  const _ReportsBody();

  @override
  State<_ReportsBody> createState() => _ReportsBodyState();
}

class _ReportsBodyState extends State<_ReportsBody> {
  late DateTime _from;
  late DateTime _to;
  String? _point;
  List<VJson> _points = [];
  VJson? _d;
  Object? _err;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _from = DateTime(n.year, n.month);
    _to = DateTime(n.year, n.month, n.day);
    _init();
  }

  Future<void> _init() async {
    VPoints.get().then((p) => mounted ? setState(() => _points = p) : null).catchError((_) => null);
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final d = await ValetAdmin.I.call('vva_report', {'p_from': VF.iso(_from), 'p_to': VF.iso(_to), 'p_point': _point});
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

  Future<void> _export() async {
    final d = _d;
    if (d == null) return;
    final t = vMap(d['totals']);
    List<List<dynamic>> rows(String k, List<String> keys) => [for (final r in vList(d[k])) [for (final x in keys) r[x]]];
    await vExport(context, 'valet_report_${VF.iso(_from)}_${VF.iso(_to)}.xlsx', [
      ExcelSheet(name: 'Totals', headers: ['Item', 'Value'], rows: [for (final e in t.entries) [e.key, e.value]]),
      ExcelSheet(name: 'By point', headers: ['Code', 'Point', 'Cars', 'Tips', 'Revenue'], rows: rows('by_point', ['code', 'point', 'cars', 'tips', 'revenue'])),
      ExcelSheet(name: 'By day', headers: ['Day', 'Cars', 'Revenue'], rows: rows('by_day', ['day', 'cars', 'revenue'])),
      ExcelSheet(name: 'By payment', headers: ['Payment', 'Cars', 'Revenue'], rows: rows('by_payment', ['mode', 'cars', 'revenue'])),
      ExcelSheet(name: 'By ticket type', headers: ['Type', 'Cars', 'Revenue'], rows: rows('by_type', ['type', 'cars', 'revenue'])),
      ExcelSheet(name: 'Validations', headers: ['Client', 'Cars'], rows: rows('by_client', ['client', 'validations'])),
    ]);
  }

  @override
  Widget build(BuildContext context) {
          final d = _d;
          return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
            VHead(tx(context, 'تَقارير الفاليه', 'Valet reports'),
                subtitle: tx(context, 'التَذاكِر المُغلَقة في الفَترة (بِدون المُلغاة)', 'Closed tickets in the period (void excluded)'),
                actions: [
                  VPointFilter(points: _points, value: _point, onChanged: (v) {
                    _point = v;
                    _load();
                  }),
                  OutlinedButton.icon(onPressed: d == null ? null : _export, icon: const Icon(Icons.download), label: const Text('Excel')),
                ]),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: VRange(from: _from, to: _to, onChanged: (a, b) {
                _from = a;
                _to = b;
                _load();
              }),
            ),
            if (_busy) const Padding(padding: EdgeInsets.fromLTRB(16, 10, 16, 0), child: LinearProgressIndicator(minHeight: 2)),
            if (_err != null) Padding(padding: const EdgeInsets.all(16), child: Text(vErr(context, _err!), style: const TextStyle(color: VC.bad))),
            if (d != null) ..._content(d),
          ]);
  }

  List<Widget> _content(VJson d) {
    final t = vMap(d['totals']);
    final days = vList(d['by_day']);
    Widget table(String title, List<String> head, List<List<String>> rows, double w) => SizedBox(
          width: w,
          child: VPanel(
            title: title,
            child: VTable(
              columns: [for (var i = 0; i < head.length; i++) DataColumn(label: Text(head[i]), numeric: i > 0)],
              rows: [for (final r in rows) DataRow(cells: [for (final c in r) DataCell(Text(c))])],
            ),
          ),
        );
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Wrap(spacing: 10, runSpacing: 10, children: [
          VKpi(tx(context, 'الإيراد (AED)', 'Revenue (AED)'), VF.money(vNum(t['revenue'])), icon: Icons.payments_outlined, color: VC.ok,
              note: 'VAT ${VF.money(vNum(t['vat']))}'),
          VKpi(tx(context, 'نَقداً', 'Cash'), VF.money(vNum(t['cash'])), icon: Icons.money),
          VKpi(tx(context, 'بِطاقة', 'Card'), VF.money(vNum(t['card'])), icon: Icons.credit_card),
          VKpi(tx(context, 'الإكراميّات', 'Tips'), VF.money(vNum(t['tips'])), icon: Icons.volunteer_activism_outlined),
          VKpi(tx(context, 'سَيّارات دَخَلَت', 'Cars in'), VF.n(vNum(t['cars_in'])), icon: Icons.login),
          VKpi(tx(context, 'تَذاكِر مُغلَقة', 'Tickets closed'), VF.n(vNum(t['closed'])), icon: Icons.task_alt,
              note: tx(context, '${VF.n(vNum(t['free']))} مَجّانيّة', '${VF.n(vNum(t['free']))} free')),
          VKpi(tx(context, 'مُتَحَقَّق مِنها', 'Validated'), VF.n(vNum(t['validated'])), icon: Icons.verified_outlined, color: VC.info),
          VKpi(tx(context, 'مُلغاة', 'Void'), VF.n(vNum(t['voided'])), icon: Icons.block, color: vNum(t['voided']) > 0 ? VC.bad : null),
        ]),
      ),
      if (days.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: VPanel(title: tx(context, 'الإيراد اليَوميّ (AED)', 'Revenue per day (AED)'), child: SizedBox(height: 230, child: _chart(days))),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Wrap(spacing: 14, runSpacing: 14, children: [
          table(tx(context, 'حَسَب النُقطة', 'By point'),
              [tx(context, 'النُقطة', 'Point'), tx(context, 'سَيّارات', 'Cars'), tx(context, 'إكراميّات', 'Tips'), tx(context, 'إيراد', 'Revenue')],
              [for (final r in vList(d['by_point'])) [vStr(r['point']), VF.n(vNum(r['cars'])), VF.money(vNum(r['tips'])), VF.money(vNum(r['revenue']))]], 600),
          table(tx(context, 'حَسَب طَريقة الدَفع', 'By payment'), [tx(context, 'الدَفع', 'Payment'), tx(context, 'سَيّارات', 'Cars'), tx(context, 'إيراد', 'Revenue')],
              [for (final r in vList(d['by_payment'])) [vStr(r['mode']), VF.n(vNum(r['cars'])), VF.money(vNum(r['revenue']))]], 420),
          table(tx(context, 'حَسَب نَوع التَذكَرة', 'By ticket type'), [tx(context, 'النَوع', 'Type'), tx(context, 'سَيّارات', 'Cars'), tx(context, 'إيراد', 'Revenue')],
              [for (final r in vList(d['by_type'])) [vStr(r['type']), VF.n(vNum(r['cars'])), VF.money(vNum(r['revenue']))]], 600),
          table(tx(context, 'التَحَقُّقات حَسَب العَميل', 'Validations by client'), [tx(context, 'العَميل', 'Client'), tx(context, 'سَيّارات', 'Cars')],
              [for (final r in vList(d['by_client'])) [vStr(r['client']), VF.n(vNum(r['validations']))]], 420),
        ]),
      ),
    ];
  }

  Widget _chart(List<VJson> days) {
    final maxY = days.fold<num>(0, (a, r) => vNum(r['revenue']) > a ? vNum(r['revenue']) : a).toDouble();
    return BarChart(BarChartData(
      maxY: maxY <= 0 ? 10 : maxY * 1.15,
      gridData: const FlGridData(drawVerticalLine: false),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 46)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 22,
            getTitlesWidget: (v, _) {
              final i = v.toInt();
              if (i < 0 || i >= days.length) return const SizedBox();
              if (days.length > 16 && i % (days.length ~/ 8) != 0) return const SizedBox();
              final s = vStr(days[i]['day']);
              return Text(s.length >= 10 ? '${s.substring(8, 10)}/${s.substring(5, 7)}' : s, style: const TextStyle(fontSize: 11, color: VC.muted));
            },
          ),
        ),
      ),
      barGroups: [
        for (var i = 0; i < days.length; i++)
          BarChartGroupData(x: i, barRods: [
            BarChartRodData(
              toY: vNum(days[i]['revenue']).toDouble(),
              color: VC.gold,
              width: days.length > 20 ? 8 : 16,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            ),
          ]),
      ],
    ));
  }
}
