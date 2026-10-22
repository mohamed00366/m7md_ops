import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:universal_html/html.dart' as html;

import '../../core/services/excel_exporter.dart';
import 'valet_admin.dart';
import 'valet_ui.dart';

/// 📄 العُقود — صَفحة واحِدة: الشَغّالة، التَجديدات المُستَحَقّة، الجَديدة (مُسوَدّة + مَواقِع جَديدة)، المُنتَهية.
/// البَيانات نُسخة لِلعَرض مِن Odoo (تَتَحَدَّث كُلّ 5 دَقائِق). الإنشاء وَالتَجديد وَالفَسخ مِن Odoo ▸ Contracts.
class ValetContractsScreen extends StatelessWidget {
  const ValetContractsScreen({super.key});

  @override
  Widget build(BuildContext context) => const ValetGate(perm: ValetAdmin.permContracts, child: _ContractsBody());
}

class _ContractsBody extends StatefulWidget {
  const _ContractsBody();

  @override
  State<_ContractsBody> createState() => _ContractsBodyState();
}

class _ContractsBodyState extends State<_ContractsBody> {
  static const _tabs = ['active', 'due', 'staffing', 'draft', 'new_sites', 'ended', 'all'];
  String _tab = 'active';
  final _q = TextEditingController();
  VJson? _d;
  VJson? _s; // staffing check
  int _days = 14;
  bool _onlyShort = false;
  Object? _err;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      if (_tab == 'staffing') {
        final now = DateTime.now();
        final s = await ValetAdmin.I.call('vva_contract_staffing',
            {'p_from': VF.iso(now.subtract(Duration(days: _days - 1))), 'p_to': VF.iso(now)});
        _d ??= await ValetAdmin.I.call('vva_contracts', {'p_tab': 'active', 'p_q': ''});
        if (mounted) setState(() { _s = s; _err = null; });
        return;
      }
      final d = await ValetAdmin.I.call('vva_contracts', {'p_tab': _tab, 'p_q': _q.text.trim()});
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

  String _tabLabel(BuildContext c, String t) => switch (t) {
        'active' => tx(c, 'الشَغّالة', 'Active'),
        'due' => tx(c, 'تَجديد مُستَحَقّ', 'Renewal due'),
        'staffing' => tx(c, 'السَوّاقين مُقابِل العَقد', 'Drivers vs contract'),
        'draft' => tx(c, 'جَديدة / مُسوَدّة', 'New / draft'),
        'new_sites' => tx(c, 'مَواقِع جَديدة', 'New sites'),
        'ended' => tx(c, 'مُنتَهية', 'Ended'),
        _ => tx(c, 'الكُلّ', 'All'),
      };

  Future<void> _export(List<VJson> rows) async {
    await vExport(context, 'contracts_$_tab.xlsx', [
      ExcelSheet(
        name: 'Contracts',
        headers: ['Contract', 'Client', 'Branches', 'Pricing', 'Price per car', 'Start', 'End', 'Auto renew', 'Notice days', 'Last notice day',
          'Drivers weekdays', 'Drivers weekend', 'Absence penalty', 'Status', 'Renewal due', 'Signed PDF'],
        rows: [
          for (final r in rows)
            () {
              final d = vMap(r['data']);
              return [
                r['name'], r['client'], vList(d['branches']).map((b) => b['name']).join(', '), d['pricing'], d['customer_price'],
                r['start_date'], r['end_date'], vBool(d['auto_renew']) ? 'Yes' : 'No', d['notice_days'], r['notice_deadline'],
                d['drivers_weekday'], d['drivers_weekend'], d['absence_penalty'], r['state'], vBool(r['alert']) ? 'Yes' : '', vBool(d['has_pdf']) ? 'Yes' : 'No',
              ];
            }(),
        ],
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final counts = vMap(d?['counts']);
    final rows = vList(d?['rows']);
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      VHead(tx(context, 'العُقود', 'Contracts'),
          subtitle: tx(context, 'مِن Odoo – تَتَحَدَّث كُلّ 5 دَقائِق. الإنشاء وَالتَجديد وَالفَسخ مِن Odoo ▸ Contracts.',
              'From Odoo – refreshed every 5 minutes. Create, renew and terminate in Odoo ▸ Contracts.'),
          actions: [
            SizedBox(
              width: 240,
              child: TextField(
                controller: _q,
                decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tx(context, 'عَميل، فَرع، عَقد…', 'Client, branch, contract…'), isDense: true),
                onSubmitted: (_) => _load(),
              ),
            ),
            IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
            OutlinedButton.icon(
                onPressed: _tab == 'staffing'
                    ? (vList(_s?['rows']).isEmpty ? null : () => _exportStaffing(vList(_s?['rows'])))
                    : (rows.isEmpty ? null : () => _export(rows)),
                icon: const Icon(Icons.download),
                label: const Text('Excel')),
          ]),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final t in _tabs)
            ChoiceChip(
              selected: _tab == t,
              label: Text('${_tabLabel(context, t)}${counts[t] == null ? '' : '  ${counts[t]}'}'),
              avatar: t == 'due' && vNum(counts['due']) > 0 ? const Icon(Icons.notifications_active, size: 16, color: VC.bad) : null,
              onSelected: (_) {
                setState(() => _tab = t);
                _load();
              },
            ),
        ]),
      ),
      if (counts['synced_at'] != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Text('${tx(context, 'آخِر تَحديث مِن Odoo', 'Last update from Odoo')}: ${VF.dt(vTime(counts['synced_at']))}',
              style: const TextStyle(color: VC.muted, fontSize: 12)),
        ),
      if (_busy) const Padding(padding: EdgeInsets.fromLTRB(16, 10, 16, 0), child: LinearProgressIndicator(minHeight: 2)),
      if (_err != null) Padding(padding: const EdgeInsets.all(16), child: Text(vErr(context, _err!), style: const TextStyle(color: VC.bad))),
      if (_tab == 'staffing' && _s != null) ..._staffing(context, _s!),
      if (d != null && _tab == 'new_sites') _newSites(context, vList(d['new_sites'])),
      if (d != null && _tab != 'new_sites' && _tab != 'staffing')
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: VPanel(
            child: VTable(
              empty: tx(context, 'لا تُوجَد عُقود هُنا.', 'No contract here.'),
              columns: [
                DataColumn(label: Text(tx(context, 'العَقد', 'Contract'))),
                DataColumn(label: Text(tx(context, 'الفُروع', 'Branches'))),
                DataColumn(label: Text(tx(context, 'التَسعير', 'Pricing'))),
                DataColumn(label: Text(tx(context, 'المُدّة', 'Term'))),
                DataColumn(label: Text(tx(context, 'آخِر يَوم إخطار', 'Last notice day'))),
                DataColumn(label: Text(tx(context, 'السَوّاقين', 'Drivers'))),
                DataColumn(label: Text(tx(context, 'الحالة', 'Status'))),
                const DataColumn(label: Text('PDF')),
              ],
              rows: [
                for (final r in rows)
                  () {
                    final x = vMap(r['data']);
                    return DataRow(
                      color: vBool(r['alert']) ? WidgetStatePropertyAll(VC.bad.withValues(alpha: 0.06)) : null,
                      onSelectChanged: (_) => _detail(context, r),
                      cells: [
                        DataCell(Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text(vStr(r['name']), style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text(vStr(r['client']), style: const TextStyle(color: VC.muted, fontSize: 12), overflow: TextOverflow.ellipsis),
                        ])),
                        DataCell(SizedBox(
                            width: 200,
                            child: Text(vList(x['branches']).map((b) => b['name']).join(', '), maxLines: 2, overflow: TextOverflow.ellipsis))),
                        DataCell(Text(_pricing(context, vStr(x['pricing']), x))),
                        DataCell(Text(r['end_date'] == null ? '-' : '${vStr(r['start_date'])} → ${vStr(r['end_date'])}${vBool(x['auto_renew']) ? '  ↻' : ''}')),
                        DataCell(Text(vStr(r['notice_deadline']).isEmpty ? '-' : vStr(r['notice_deadline']),
                            style: TextStyle(color: vBool(r['alert']) ? VC.bad : null, fontWeight: vBool(r['alert']) ? FontWeight.w700 : null))),
                        DataCell(Text(vNum(x['drivers_weekday']) + vNum(x['drivers_weekend']) == 0
                            ? '-'
                            : '${VF.n(vNum(x['drivers_weekday']))} / ${VF.n(vNum(x['drivers_weekend']))}')),
                        DataCell(_statePill(context, r)),
                        DataCell(vBool(x['has_pdf'])
                            ? IconButton(tooltip: tx(context, 'فَتح العَقد', 'Open contract'), icon: const Icon(Icons.picture_as_pdf, color: VC.bad), onPressed: () => _openPdf(context, r))
                            : const Text('-', style: TextStyle(color: VC.muted))),
                      ],
                    );
                  }(),
              ],
            ),
          ),
        ),
    ]);
  }

  Future<void> _exportStaffing(List<VJson> rows) async {
    await vExport(context, 'contract_drivers.xlsx', [
      ExcelSheet(
        name: 'Drivers vs contract',
        headers: ['Day', 'Weekend', 'Contract', 'Client', 'Point', 'Required', 'Clocked in', 'Missing', 'Penalty risk (AED)', 'Status', 'Who clocked in'],
        rows: [
          for (final r in rows)
            [r['day'], vBool(r['weekend']) ? 'Yes' : '', r['contract'], r['client'], r['point'], r['required'], r['present'], r['missing'],
              r['penalty'], r['status'], r['who']],
        ],
      ),
    ]);
  }

  List<Widget> _staffing(BuildContext context, VJson s) {
    final t = vMap(s['totals']);
    final all = vList(s['rows']);
    final rows = _onlyShort ? all.where((r) => r['status'] == 'short').toList() : all;
    Widget statusPill(VJson r) => switch (vStr(r['status'])) {
          'short' => VPill(tx(context, 'ناقِص ${VF.n(vNum(r['missing']))}', '${VF.n(vNum(r['missing']))} missing'), color: VC.bad, icon: Icons.warning_amber),
          'ok' => VPill(tx(context, 'مُكتَمِل', 'Complete'), color: VC.ok, icon: Icons.check),
          _ => VPill(tx(context, 'لا يوجَد حُضور مُسَجَّل', 'No attendance recorded'), color: VC.muted),
        };
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Text(
            tx(context,
                'عَدَد السَوّاقين المَطلوب في العَقد (أيّام الأُسبوع / الجُمعة–الأحَد) مُقابِل اللي سَجِّلوا حُضور في النُقطة كُلّ يَوم. الغَرامة المُتَوَقَّعة = غَرامة الغِياب الشَهريّة ÷ أيّام الشَهر × السَوّاقين النّاقصين.',
                'Drivers the contract requires (weekdays / Fri–Sun) vs drivers who clocked in at the point each day. Penalty risk = monthly absence penalty ÷ days of the month × missing drivers.'),
            style: const TextStyle(color: VC.muted, fontSize: 12)),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          VKpi(tx(context, 'عُقود لَيها عَدَد سَوّاقين', 'Contracts with drivers'), VF.n(vNum(t['contracts'])), icon: Icons.description_outlined, color: VC.info),
          VKpi(tx(context, 'أيّام فيها نَقص', 'Days short'), VF.n(vNum(t['short_days'])), icon: Icons.event_busy,
              color: vNum(t['short_days']) > 0 ? VC.bad : VC.ok),
          VKpi(tx(context, 'سَوّاق × يَوم ناقِص', 'Missing driver-days'), VF.n(vNum(t['missing_driver_days'])), icon: Icons.person_off_outlined,
              color: vNum(t['missing_driver_days']) > 0 ? VC.bad : VC.ok),
          VKpi(tx(context, 'غَرامة مُتَوَقَّعة (AED)', 'Penalty risk (AED)'), VF.money(vNum(t['penalty_risk'])), icon: Icons.gavel,
              color: vNum(t['penalty_risk']) > 0 ? VC.bad : VC.ok),
          if (vNum(t['no_data_points']) > 0)
            VKpi(tx(context, 'نِقاط بِدون حُضور مُسَجَّل', 'Points without attendance'), VF.n(vNum(t['no_data_points'])), icon: Icons.help_outline, color: VC.warn),
          DropdownButton<int>(
            value: _days,
            items: [for (final n in [7, 14, 30, 60, 90]) DropdownMenuItem(value: n, child: Text(tx(context, 'آخِر $n يَوم', 'Last $n days')))],
            onChanged: (v) {
              if (v == null) return;
              setState(() => _days = v);
              _load();
            },
          ),
          FilterChip(
              selected: _onlyShort,
              label: Text(tx(context, 'أيّام النَقص بَسّ', 'Short days only')),
              onSelected: (v) => setState(() => _onlyShort = v)),
        ]),
      ),
      if (vNum(t['no_data_points']) > 0 || vNum(t['unlinked_points']) > 0)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
              tx(context,
                  'النِقاط اللي ما فيهاش أيّ حُضور مُسَجَّل لِسّه مَش بتِتحِسِب نَقص – لازِم السَوّاقين يِسَجِّلوا حُضور مِن جِهاز النُقطة.${vNum(t['unlinked_points']) > 0 ? ' فيه فُروع في العُقود مَش مَربوطة بِنُقطة بِنَفس الاسم.' : ''}',
                  'Points with no attendance recorded yet are not counted as short – drivers must clock in on the point terminal.${vNum(t['unlinked_points']) > 0 ? ' Some contract branches are not matched to a point with the same name.' : ''}'),
              style: const TextStyle(color: VC.warn, fontSize: 12)),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: VPanel(
          child: VTable(
            empty: tx(context, 'لا تُوجَد عُقود شَغّالة فيها عَدَد سَوّاقين – املاه في Odoo ▸ Contracts.',
                'No active contract with a driver count – fill it in Odoo ▸ Contracts.'),
            columns: [
              DataColumn(label: Text(tx(context, 'اليَوم', 'Day'))),
              DataColumn(label: Text(tx(context, 'العَقد', 'Contract'))),
              DataColumn(label: Text(tx(context, 'النُقطة', 'Point'))),
              DataColumn(label: Text(tx(context, 'المَطلوب', 'Required')), numeric: true),
              DataColumn(label: Text(tx(context, 'حَضَروا', 'Clocked in')), numeric: true),
              DataColumn(label: Text(tx(context, 'غَرامة مُتَوَقَّعة', 'Penalty risk')), numeric: true),
              DataColumn(label: Text(tx(context, 'الحالة', 'Status'))),
            ],
            rows: [
              for (final r in rows)
                DataRow(
                  color: r['status'] == 'short' ? WidgetStatePropertyAll(VC.bad.withValues(alpha: 0.06)) : null,
                  cells: [
                    DataCell(Text('${vStr(r['day'])}${vBool(r['weekend']) ? '  •' : ''}')),
                    DataCell(Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(vStr(r['contract']), style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(vStr(r['client']), style: const TextStyle(color: VC.muted, fontSize: 12), overflow: TextOverflow.ellipsis),
                    ])),
                    DataCell(Text(vStr(r['point']))),
                    DataCell(Text(VF.n(vNum(r['required'])))),
                    DataCell(Tooltip(message: vStr(r['who']), child: Text(VF.n(vNum(r['present']))))),
                    DataCell(Text(vNum(r['penalty']) > 0 ? VF.money(vNum(r['penalty'])) : '-',
                        style: TextStyle(color: vNum(r['penalty']) > 0 ? VC.bad : null))),
                    DataCell(statusPill(r)),
                  ],
                ),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _newSites(BuildContext context, List<VJson> sites) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: VPanel(
          title: tx(context, 'مَواقِع اتعَمَدِت في New Sites Tracker وَعَقدها لِسّه بيتعِمِل في Odoo', 'Sites approved in the New Sites Tracker, contract being created in Odoo'),
          child: VTable(
            empty: tx(context, 'كُلّ المَواقِع الجَديدة لَيها عُقود.', 'Every new site has a contract.'),
            columns: [
              DataColumn(label: Text(tx(context, 'العَميل', 'Client'))),
              DataColumn(label: Text(tx(context, 'التَسعير', 'Pricing'))),
              DataColumn(label: Text(tx(context, 'البِداية', 'Start'))),
              DataColumn(label: Text(tx(context, 'المُدّة', 'Months')), numeric: true),
              DataColumn(label: Text(tx(context, 'اتعَمَد', 'Approved'))),
              const DataColumn(label: Text('Odoo')),
            ],
            rows: [
              for (final s in sites)
                DataRow(cells: [
                  DataCell(Text(vStr(s['client']))),
                  DataCell(Text(vStr(s['pricing_mode']))),
                  DataCell(Text(vStr(s['start']))),
                  DataCell(Text(vStr(s['months']))),
                  DataCell(Text(VF.date(vTime(s['approved_at'])))),
                  DataCell(s['error'] == null
                      ? VPill(tx(context, 'في الطَريق (5 دَقائِق)', 'On its way (5 min)'), color: VC.info)
                      : Tooltip(message: vStr(s['error']), child: VPill(tx(context, 'خَطَأ', 'Error'), color: VC.bad))),
                ]),
            ],
          ),
        ),
      );

  String _pricing(BuildContext c, String p, VJson x) => switch (p) {
        'customer_pays' => '${tx(c, 'العَميل يِدفَع', 'Customers pay')} ${VF.money(vNum(x['customer_price']))}${vBool(x['vat_included']) ? ' incl.' : ''}',
        'monthly' => tx(c, 'فاتورة شَهريّة', 'Monthly invoice'),
        'per_ticket' => tx(c, 'بِالتَذكَرة', 'Per ticket'),
        'client_invoices' => tx(c, 'العَميل بيفَوتِرنا', 'Client invoices us'),
        'mixed' => tx(c, 'مُختَلِط', 'Mixed'),
        _ => '-',
      };

  Widget _statePill(BuildContext c, VJson r) {
    if (vBool(r['alert'])) return VPill(tx(c, 'قَرار التَجديد', 'Renewal due'), color: VC.bad, icon: Icons.notifications_active);
    return switch (vStr(r['state'])) {
      'active' => VPill(tx(c, 'شَغّال', 'Active'), color: VC.ok),
      'draft' => VPill(tx(c, 'مُسوَدّة', 'Draft'), color: VC.info),
      'terminated' => VPill(tx(c, 'اتفَسَخ', 'Terminated'), color: VC.bad),
      'expired' => VPill(tx(c, 'انتَهى', 'Expired'), color: VC.warn),
      _ => VPill(vStr(r['state'])),
    };
  }

  Future<void> _openPdf(BuildContext context, VJson r) async {
    final res = await vGuard(context, () async {
      final x = await Supabase.instance.client.functions
          .invoke('odoo-sync', body: {'mode': 'contract_pdf', 'token': ValetAdmin.I.token, 'id': r['odoo_id']}).timeout(const Duration(seconds: 60));
      final d = vMap(x.data);
      if (d['ok'] != true) throw ValetError('${d['error'] ?? 'تَعَذَّر فَتح المِلَفّ'}', '${d['error'] ?? 'Could not open the file'}');
      return vMap(d['pdf']);
    });
    if (res == null) return;
    final bytes = base64Decode(vStr(res['data']));
    final name = vStr(res['name']).isEmpty ? 'contract.pdf' : vStr(res['name']);
    if (kIsWeb) {
      final url = html.Url.createObjectUrlFromBlob(html.Blob([bytes], 'application/pdf'));
      html.window.open(url, '_blank');
    } else {
      await Printing.sharePdf(bytes: bytes, filename: name);
    }
  }

  Future<void> _detail(BuildContext context, VJson r) async {
    final x = vMap(r['data']);
    Widget row(String ar, String en, Object? v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 190, child: Text(tx(context, ar, en), style: const TextStyle(color: VC.muted))),
            Expanded(child: SelectableText(v == null || '$v'.isEmpty || '$v' == 'null' ? '-' : '$v')),
          ]),
        );
    String yes(dynamic v) => vBool(v) ? tx(context, 'نَعَم', 'Yes') : tx(context, 'لا', 'No');
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760, maxHeight: 800),
          child: ListView(padding: const EdgeInsets.all(20), shrinkWrap: true, children: [
            Row(children: [
              Expanded(child: Text(vStr(r['name']), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
              _statePill(ctx, r),
              IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
            ]),
            Text(vStr(r['client']), style: const TextStyle(color: VC.muted)),
            if (vBool(r['alert']))
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: VC.bad.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                child: Text(tx(ctx, 'لازِم قَرار التَجديد: آخِر يَوم لِلإخطار ${r['notice_deadline']}. القَرار مِن Odoo ▸ Contracts.',
                    'Renewal decision due: last day to give notice is ${r['notice_deadline']}. Decide in Odoo ▸ Contracts.')),
              ),
            const Divider(height: 22),
            row('الفُروع', 'Branches', vList(x['branches']).map((b) => '${b['name']} (${b['point'] ?? '-'})').join('\n')),
            row('التَوقيع', 'Signed on', x['signed']),
            row('المُدّة', 'Term', r['end_date'] == null ? null : '${r['start_date']} → ${r['end_date']}'),
            row('تَجديد تِلقائيّ', 'Auto renew', vBool(x['auto_renew']) ? '${yes(true)} · ${x['renew_months']} ${tx(ctx, 'شَهر', 'months')}' : yes(false)),
            row('الإخطار قَبل الانتِهاء', 'Notice before expiry', x['notice_days'] == null ? null : '${x['notice_days']} ${tx(ctx, 'يَوم', 'days')}'),
            row('آخِر يَوم إخطار', 'Last notice day', r['notice_deadline']),
            row('الفَسخ في أَيّ وَقت', 'Termination notice', x['termination_days'] == null || vNum(x['termination_days']) == 0 ? null : '${x['termination_days']} ${tx(ctx, 'يَوم', 'days')}'),
            row('إصلاح الإخلال', 'Days to fix a breach', vNum(x['breach_days']) == 0 ? null : x['breach_days']),
            row('تَعديل شُروط الدَفع', 'Payment terms change', vNum(x['payment_change_days']) == 0 ? null : '${x['payment_change_days']} ${tx(ctx, 'يَوم', 'days')}'),
            if (x['termination_date'] != null) row('يَنتَهي بِالفَسخ', 'Ends on (termination)', x['termination_date']),
            const Divider(height: 22),
            row('التَسعير', 'Pricing', _pricing(ctx, vStr(x['pricing']), x)),
            row('شُروط الإيراد', 'Revenue terms', x['revenue_note']),
            row('السَوّاقين', 'Drivers', '${tx(ctx, 'أَيّام الأُسبوع', 'Weekdays')} ${x['drivers_weekday'] ?? '-'} · ${tx(ctx, 'الويك إند', 'Weekend')} ${x['drivers_weekend'] ?? '-'}'),
            row('الجَدوَل', 'Schedule', x['schedule']),
            row('غَرامة الغِياب', 'Absence penalty', vNum(x['absence_penalty']) == 0 ? null : '${VF.money(vNum(x['absence_penalty']))} AED / driver / month'),
            row('حَصريّة · عَدَم مُزاحَمة · تَأمين', 'Exclusive · non-compete · insurance', '${yes(x['exclusive'])} · ${yes(x['non_compete'])} · ${yes(x['insurance'])}'),
            row('النُسخة', 'Version', '${x['version'] ?? 1}${x['previous'] == null ? '' : ' (${tx(ctx, 'بَعد', 'after')} ${vMap(x['previous'])['name']})'}'),
            row('مُلاحَظات', 'Notes', x['notes']),
            if (vList(x['lines']).isNotEmpty) ...[
              const Divider(height: 22),
              Text(tx(ctx, 'سُطور الأَسعار', 'Price lines'), style: const TextStyle(fontWeight: FontWeight.w700)),
              VTable(
                columns: [
                  DataColumn(label: Text(tx(ctx, 'الفَرع', 'Branch'))),
                  DataColumn(label: Text(tx(ctx, 'الوَصف', 'Description'))),
                  DataColumn(label: Text(tx(ctx, 'الكَمّيّة × السِعر', 'Qty × price'))),
                  DataColumn(label: Text(tx(ctx, 'مِن – إلى', 'From – till'))),
                ],
                rows: [
                  for (final l in vList(x['lines']))
                    DataRow(cells: [
                      DataCell(Text(vStr(l['branch']))),
                      DataCell(Text(vStr(l['name']), style: TextStyle(color: vBool(l['active']) ? null : VC.muted))),
                      DataCell(Text('${l['qty']} × ${VF.money(vNum(l['price']))}')),
                      DataCell(Text('${l['start'] ?? '-'} – ${l['end'] ?? '…'}')),
                    ]),
                ],
              ),
            ],
            const SizedBox(height: 12),
            if (vBool(x['has_pdf']))
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FilledButton.icon(icon: const Icon(Icons.picture_as_pdf), label: Text(tx(ctx, 'فَتح العَقد الموَقَّع', 'Open signed contract')), onPressed: () => _openPdf(ctx, r)),
              ),
          ]),
        ),
      ),
    );
  }
}
