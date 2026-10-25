import 'package:flutter/material.dart';

import '../../core/services/excel_exporter.dart';
import 'valet_admin.dart';
import 'valet_ui.dart';

/// 🚗💥 حَوادِث الفاليه — كُلّ تَقارير النِقاط (مِن تَطبيق الفاليه)، مَفتوحة / مُغلَقة، وَالمُتابَعة (تَكلِفة، إجراء، إغلاق).
class ValetAccidentsScreen extends StatelessWidget {
  const ValetAccidentsScreen({super.key});

  @override
  Widget build(BuildContext context) => const ValetGate(perm: ValetAdmin.permReports, child: _AccidentsBody());
}

/// 📦 عُهَد النِقاط — المُعَدّات وَحالَتها وَآخِر جَرد لِكُلّ نُقطة، دَفاتِر التَذاكِر اليَدَويّة، وَسِجِلّ الجَرد.
class ValetAssetsScreen extends StatelessWidget {
  const ValetAssetsScreen({super.key});

  @override
  Widget build(BuildContext context) => const ValetGate(perm: ValetAdmin.permReports, child: _AssetsBody());
}

const _red = Color(0xFFA32D2D);

String _typeAr(BuildContext c, String t) => switch (t) {
      'Accident Report' => tx(c, 'حادِث', 'Accident'),
      'Incident Report' => tx(c, 'واقِعة', 'Incident'),
      'Near Miss Report' => tx(c, 'كادَ يَقَع', 'Near miss'),
      'Property Damage' => tx(c, 'ضَرَر مُمتَلَكات', 'Property'),
      _ => t,
    };

String _stageAr(BuildContext c, String s) => switch (s) {
      'Receiving' => tx(c, 'الاستِلام', 'Receiving'),
      'Driving to park' => tx(c, 'القِيادة لِلمَوقِف', 'Driving to park'),
      'Parking' => tx(c, 'الصَفّ', 'Parking'),
      'Delivering' => tx(c, 'التَسليم', 'Delivering'),
      'Other' => tx(c, 'أُخرى', 'Other'),
      _ => s,
    };

bool _open(VJson a) => vStr(a['status']) != 'Closed';
DateTime? _when(VJson a) => vTime(a['accident_at']) ?? vTime(a['created_at']);
List<String> _photos(VJson a) => [
      ...((a['photos'] as List?) ?? const []).map((e) => '$e').where((s) => s.isNotEmpty),
      if (vStr(a['fine_photo']).isNotEmpty) vStr(a['fine_photo']),
    ];
List<String> _strs(dynamic v) => ((v as List?) ?? const []).map((e) => '$e').toList();

// ================================================================== accidents

class _AccidentsBody extends StatefulWidget {
  const _AccidentsBody();

  @override
  State<_AccidentsBody> createState() => _AccidentsBodyState();
}

class _AccidentsBodyState extends State<_AccidentsBody> {
  late DateTime _from;
  late DateTime _to;
  String? _point;
  String _status = 'all';
  String _q = '';
  List<VJson>? _rows;
  List<VJson> _points = [];
  Object? _err;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month);
    _to = DateTime(now.year, now.month, now.day);
    VPoints.get().then((p) {
      if (mounted) setState(() => _points = p);
    }).catchError((_) {});
    _load();
  }

  Future<void> _load() async {
    setState(() => _err = null);
    try {
      final d = await ValetAdmin.I.call('vva_accidents', {'p_from': VF.iso(_from), 'p_to': VF.iso(_to), 'p_point': _point});
      if (mounted) setState(() => _rows = vList(d['rows']));
    } catch (e) {
      if (mounted) setState(() => _err = e);
    }
  }

  List<VJson> get _shown {
    final q = _q.trim().toUpperCase();
    return (_rows ?? const <VJson>[]).where((a) {
      if (_status == 'open' && !_open(a)) return false;
      if (_status == 'closed' && _open(a)) return false;
      if (q.isEmpty) return true;
      return ['code', 'car_number1', 'employee_name', 'ticket_code', 'point_name', 'car_number2']
          .any((k) => vStr(a[k]).toUpperCase().contains(q));
    }).toList();
  }

  Future<void> _export(List<VJson> rows) async {
    await vExport(context, 'accidents_${VF.iso(_from)}_${VF.iso(_to)}.xlsx', [
      ExcelSheet(
        name: 'Accidents',
        headers: ['Code', 'When', 'Point', 'Type', 'Report for', 'Status', 'Car', 'Colour', 'Ticket', 'Owner', 'Owner phone', 'Driver code', 'Driver',
          'During', 'Place', 'What happened', 'New damage points', 'Second party driver', 'Second party phone', 'Second party car', 'Police report',
          'Customer informed', 'Action taken', 'Cost', 'Photos', 'Closed at'],
        rows: [
          for (final a in rows)
            [
              a['code'], VF.dt(_when(a)), a['point_name'], a['report_type'], a['report'], vStr(a['status']).isEmpty ? 'Open' : a['status'],
              a['car_number1'], a['car_color1'], a['ticket_code'], a['owner_name1'], a['phone_owner1'], a['employee_code'], a['employee_name'] ?? a['driver_name'],
              a['stage'], a['location'], a['description'], _strs(a['damage_points']).join(', '), a['name_driver2'], a['phone_driver2'], a['car_number2'],
              a['police_report_no'], a['customer_informed'] == true ? 'Yes' : 'No', a['action_taken'], vNum(a['cost_deduction']), _photos(a).length,
              VF.dt(vTime(a['closed_at'])),
            ],
        ],
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final all = _rows ?? const <VJson>[];
    final rows = _shown;
    final open = all.where(_open).length;
    final cost = all.fold<num>(0, (s, a) => s + vNum(a['cost_deduction']));
    final pts = all.map((a) => vStr(a['point_id'])).toSet().length;
    final near = all.where((a) => vStr(a['report_type']) == 'Near Miss Report').length;
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      VHead(
        tx(context, 'حَوادِث الفاليه', 'Valet accidents'),
        subtitle: tx(context, 'تَقارير الحَوادِث مِن تَطبيق الفاليه في كُلّ النِقاط وَمُتابَعَتها', 'Accident reports from the valet app at all points, with follow-up'),
        actions: [
          OutlinedButton.icon(
            onPressed: rows.isEmpty ? null : () => _export(rows),
            icon: const Icon(Icons.download_outlined, size: 18),
            label: const Text('Excel'),
          ),
          IconButton.filledTonal(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 12, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            VRange(
              from: _from,
              to: _to,
              onChanged: (a, b) {
                setState(() {
                  _from = a;
                  _to = b;
                });
                _load();
              },
            ),
            VPointFilter(
              points: _points,
              value: _point,
              onChanged: (v) {
                setState(() => _point = v);
                _load();
              },
            ),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 10, children: [
            VKpi(tx(context, 'التَقارير', 'Reports'), VF.n(all.length), icon: Icons.description_outlined, color: _red),
            VKpi(tx(context, 'مَفتوحة', 'Open'), VF.n(open), icon: Icons.pending_actions, color: open > 0 ? VC.warn : VC.ok),
            VKpi(tx(context, 'التَكلِفة', 'Cost'), VF.money(cost), icon: Icons.payments_outlined, color: VC.bad, note: 'AED'),
            VKpi(tx(context, 'نِقاط بِها حَوادِث', 'Points'), VF.n(pts), icon: Icons.place_outlined, color: VC.info),
            VKpi(tx(context, 'كادَ يَقَع', 'Near misses'), VF.n(near), icon: Icons.warning_amber_rounded, color: VC.gold),
          ]),
          const SizedBox(height: 12),
          VPanel(
            title: tx(context, 'التَقارير', 'Reports'),
            actions: [
              SizedBox(
                width: 240,
                child: TextField(
                  onChanged: (v) => setState(() => _q = v),
                  decoration: InputDecoration(isDense: true, prefixIcon: const Icon(Icons.search, size: 18), hintText: tx(context, 'كود، لَوحة، سائِق، نُقطة', 'Code, plate, driver, point')),
                ),
              ),
              const SizedBox(width: 8),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 'all', label: Text(tx(context, 'الكُلّ', 'All'))),
                  ButtonSegment(value: 'open', label: Text(tx(context, 'مَفتوحة', 'Open'))),
                  ButtonSegment(value: 'closed', label: Text(tx(context, 'مُغلَقة', 'Closed'))),
                ],
                selected: {_status},
                onSelectionChanged: (s) => setState(() => _status = s.first),
              ),
            ],
            child: _err != null && _rows == null
                ? Padding(padding: const EdgeInsets.all(20), child: Text(vErr(context, _err!), style: const TextStyle(color: VC.bad)))
                : _rows == null
                    ? const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
                    : VTable(
                        empty: tx(context, 'لا تُوجَد تَقارير في هذِهِ الفَترة.', 'No reports in this period.'),
                        columns: [
                          DataColumn(label: Text(tx(context, 'الكود', 'Code'))),
                          DataColumn(label: Text(tx(context, 'الوَقت', 'When'))),
                          DataColumn(label: Text(tx(context, 'النُقطة', 'Point'))),
                          DataColumn(label: Text(tx(context, 'النَوع', 'Type'))),
                          DataColumn(label: Text(tx(context, 'السَيّارة', 'Car'))),
                          DataColumn(label: Text(tx(context, 'السائِق', 'Driver'))),
                          DataColumn(label: Text(tx(context, 'أَثناء', 'During'))),
                          DataColumn(label: Text(tx(context, 'ضَرَر', 'Damage')), numeric: true),
                          DataColumn(label: Text(tx(context, 'صُوَر', 'Photos')), numeric: true),
                          DataColumn(label: Text(tx(context, 'التَكلِفة', 'Cost')), numeric: true),
                          DataColumn(label: Text(tx(context, 'الحالة', 'Status'))),
                        ],
                        rows: [
                          for (final a in rows)
                            DataRow(
                              onSelectChanged: (_) => _openDetails(a),
                              cells: [
                                DataCell(Text(vStr(a['code']), style: const TextStyle(fontWeight: FontWeight.w700))),
                                DataCell(Text(VF.dt(_when(a)))),
                                DataCell(Text(vStr(a['point_name']))),
                                DataCell(Text(_typeAr(context, vStr(a['report_type'])))),
                                DataCell(Text(vStr(a['car_number1']), style: const TextStyle(fontWeight: FontWeight.w700))),
                                DataCell(Text(vStr(a['employee_name']).isNotEmpty ? vStr(a['employee_name']) : vStr(a['driver_name']))),
                                DataCell(Text(_stageAr(context, vStr(a['stage'])))),
                                DataCell(Text('${_strs(a['damage_points']).length}')),
                                DataCell(Text('${_photos(a).length}')),
                                DataCell(Text(vNum(a['cost_deduction']) > 0 ? VF.money(vNum(a['cost_deduction'])) : '-')),
                                DataCell(VPill(_open(a) ? tx(context, 'مَفتوح', 'Open') : tx(context, 'مُغلَق', 'Closed'), color: _open(a) ? VC.warn : VC.ok)),
                              ],
                            ),
                        ],
                      ),
          ),
        ]),
      ),
    ]);
  }

  Future<void> _openDetails(VJson a) async {
    final changed = await showDialog<VJson>(context: context, builder: (_) => _AccidentDialog(a: a));
    if (changed != null && mounted) {
      setState(() {
        final i = _rows!.indexWhere((x) => x['id'] == a['id']);
        if (i >= 0) _rows![i] = {..._rows![i], ...changed};
      });
    }
  }
}

class _AccidentDialog extends StatefulWidget {
  const _AccidentDialog({required this.a});
  final VJson a;

  @override
  State<_AccidentDialog> createState() => _AccidentDialogState();
}

class _AccidentDialogState extends State<_AccidentDialog> {
  late VJson a = widget.a;
  late final _action = TextEditingController(text: vStr(a['action_taken']));
  late final _cost = TextEditingController(text: a['cost_deduction'] == null ? '' : vStr(a['cost_deduction']));
  late final _police = TextEditingController(text: vStr(a['police_report_no']));
  late bool _informed = a['customer_informed'] == true;

  @override
  void dispose() {
    _action.dispose();
    _cost.dispose();
    _police.dispose();
    super.dispose();
  }

  Future<void> _save({String? status}) async {
    final c = _cost.text.trim();
    if (c.isNotEmpty && num.tryParse(c) == null) {
      vToast(context, tx(context, 'التَكلِفة غَير صَحيحة.', 'The cost is not valid.'), error: true);
      return;
    }
    final r = await vGuard(
      context,
      () => ValetAdmin.I.call('vva_accident_update', {
        'p_id': a['id'],
        'p_data': {
          if (status != null) 'status': status,
          'action_taken': _action.text.trim(),
          'cost_deduction': c,
          'police_report_no': _police.text.trim(),
          'customer_informed': _informed,
        },
      }),
      ok: tx(context, 'تَمّ الحِفظ.', 'Saved.'),
    );
    if (r == null || !mounted) return;
    Navigator.pop(context, vMap(r['row']));
  }

  Widget _kv(String k, String v) => v.trim().isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 130, child: Text(k, style: const TextStyle(color: VC.muted))),
            Expanded(child: SelectableText(v, style: const TextStyle(fontWeight: FontWeight.w600))),
          ]),
        );

  @override
  Widget build(BuildContext context) {
    final photos = _photos(a);
    final dmg = _strs(a['damage_points']);
    final old = _strs(a['existing_damages']);
    final canEdit = ValetAdmin.I.can(ValetAdmin.permTickets);
    final isOpen = _open(a);
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
      title: Row(children: [
        const Icon(Icons.car_crash_outlined, color: _red),
        const SizedBox(width: 8),
        Expanded(child: Text('${vStr(a['code'])} · ${_typeAr(context, vStr(a['report_type']))}')),
        VPill(isOpen ? tx(context, 'مَفتوح', 'Open') : tx(context, 'مُغلَق', 'Closed'), color: isOpen ? VC.warn : VC.ok),
        IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
      ]),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            _kv(tx(context, 'الوَقت', 'When'), VF.dt(_when(a))),
            _kv(tx(context, 'النُقطة', 'Point'), vStr(a['point_name'])),
            _kv(tx(context, 'التَقرير لِـ', 'Report for'), vStr(a['report'])),
            _kv(tx(context, 'سَيّارة العَميل', 'Customer car'), [vStr(a['car_number1']), vStr(a['car_color1'])].where((s) => s.isNotEmpty).join(' · ')),
            _kv(tx(context, 'التَذكَرة', 'Ticket'), vStr(a['ticket_code'])),
            _kv(tx(context, 'المالِك', 'Owner'), [vStr(a['owner_name1']), vStr(a['phone_owner1'])].where((s) => s.isNotEmpty).join(' · ')),
            _kv(tx(context, 'السائِق', 'Driver'), [vStr(a['employee_code']), vStr(a['employee_name']).isNotEmpty ? vStr(a['employee_name']) : vStr(a['driver_name'])].where((s) => s.isNotEmpty).join(' – ')),
            _kv(tx(context, 'أَثناء', 'During'), _stageAr(context, vStr(a['stage']))),
            _kv(tx(context, 'المَكان', 'Place'), vStr(a['location'])),
            _kv(tx(context, 'ماذا حَدَث', 'What happened'), vStr(a['description'])),
            _kv(tx(context, 'الطَرَف الثاني', 'Second party'),
                [vStr(a['name_driver2']), vStr(a['phone_driver2']), vStr(a['car_number2']), vStr(a['owner_car2'])].where((s) => s.isNotEmpty).join(' · ')),
            if (dmg.isNotEmpty || old.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(tx(context, 'نِقاط الضَرَر (رَقم الجُزء عَلى رَسمة السَيّارة)', 'Damage points (part numbers on the car drawing)'), style: const TextStyle(color: VC.muted)),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final d in dmg) VPill(d, color: VC.bad, icon: Icons.circle),
                for (final d in old.where((o) => !dmg.contains(o))) VPill(d, color: VC.warn, icon: Icons.history),
              ]),
              const SizedBox(height: 2),
              Text(tx(context, 'أَحمَر: ضَرَر جَديد · بُرتُقاليّ: كانَ مُسَجَّلاً عَلى التَذكَرة عِند الاستِلام', 'Red: new damage · Orange: was on the ticket at receiving'),
                  style: const TextStyle(color: VC.muted, fontSize: 11.5)),
            ],
            if (photos.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final u in photos)
                  InkWell(
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (_) => Dialog(child: InteractiveViewer(maxScale: 5, child: Image.network(u, fit: BoxFit.contain))),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(u, width: 110, height: 90, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox(width: 110, height: 90, child: Icon(Icons.broken_image))),
                    ),
                  ),
              ]),
            ],
            const Divider(height: 26),
            Text(tx(context, 'المُتابَعة', 'Follow-up'), style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: _police, enabled: canEdit, decoration: InputDecoration(isDense: true, labelText: tx(context, 'رَقم بَلاغ الشُرطة', 'Police report no.')))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: _cost, enabled: canEdit, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(isDense: true, labelText: tx(context, 'التَكلِفة (دِرهَم)', 'Cost (AED)')))),
            ]),
            const SizedBox(height: 8),
            TextField(controller: _action, enabled: canEdit, minLines: 2, maxLines: 4, decoration: InputDecoration(isDense: true, labelText: tx(context, 'الإجراء المُتَّخَذ', 'Action taken'))),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              value: _informed,
              onChanged: canEdit ? (v) => setState(() => _informed = v ?? false) : null,
              title: Text(tx(context, 'تَمّ إبلاغ العَميل', 'Customer informed')),
            ),
            if (vTime(a['closed_at']) != null) Text('${tx(context, 'أُغلِقَ', 'Closed')} ${VF.dt(vTime(a['closed_at']))}', style: const TextStyle(color: VC.muted, fontSize: 12)),
          ]),
        ),
      ),
      actions: canEdit
          ? [
              OutlinedButton.icon(onPressed: () => _save(), icon: const Icon(Icons.save_outlined, size: 18), label: Text(tx(context, 'حِفظ', 'Save'))),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: isOpen ? VC.ok : VC.warn),
                onPressed: () => _save(status: isOpen ? 'Closed' : 'Open'),
                icon: Icon(isOpen ? Icons.lock_outline : Icons.lock_open, size: 18),
                label: Text(isOpen ? tx(context, 'إغلاق التَقرير', 'Close report') : tx(context, 'إعادة فَتح', 'Reopen')),
              ),
            ]
          : null,
    );
  }
}

// ================================================================== assets

Color _stateColor(String s) => switch (s) {
      'repair' => VC.warn,
      'missing' => VC.bad,
      _ => VC.ok,
    };

String _stateAr(BuildContext c, String s) => switch (s) {
      'repair' => tx(c, 'صِيانة', 'Repair'),
      'missing' => tx(c, 'ناقِص', 'Missing'),
      _ => tx(c, 'سَليم', 'Good'),
    };

/// items[] of a point; points never checked with the new list get the 4 old counters.
List<VJson> _itemsOf(VJson p) {
  final l = vList(p['items']);
  if (l.isNotEmpty) return l;
  return [
    for (final k in const [('podium', 'Podium'), ('tablet', 'Tablet'), ('printer', 'Printer'), ('umbrella', 'Umbrella')])
      if (p[k.$1] != null) {'key': k.$1, 'name': k.$2, 'qty': p[k.$1], 'state': 'good'},
  ];
}

class _AssetsBody extends StatefulWidget {
  const _AssetsBody();

  @override
  State<_AssetsBody> createState() => _AssetsBodyState();
}

class _AssetsBodyState extends State<_AssetsBody> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    return VLoader<VJson>(
      load: () => ValetAdmin.I.call('vva_assets'),
      builder: (context, d, reload) {
        final points = vList(d['points']);
        final checks = vList(d['checks']);
        final now = DateTime.now();
        bool stale(VJson p) {
          final t = vTime(p['checked_at']);
          return t == null || now.difference(t).inHours >= 24;
        }

        int left(VJson p) {
          final b = vList(p['books']);
          if (b.isEmpty) return -1;
          final c = b.first;
          return (vNum(c['ticket_to']) - vNum(c['ticket_from']) + 1 - vNum(c['used'])).toInt();
        }

        final withIssues = points.where((p) => vNum(p['issues']) > 0).length;
        final staleN = points.where(stale).length;
        final lowBooks = points.where((p) => left(p) >= 0 && left(p) <= 10).length;
        final shown = points.where((p) {
          if (_filter == 'issues') return vNum(p['issues']) > 0;
          if (_filter == 'stale') return stale(p);
          if (_filter == 'books') return left(p) >= 0 && left(p) <= 10;
          return true;
        }).toList();

        return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
          VHead(
            tx(context, 'عُهَد النِقاط', 'Point assets'),
            subtitle: tx(context, 'المُعَدّات وَحالَتها، آخِر جَرد، وَدَفاتِر التَذاكِر اليَدَويّة لِكُلّ نُقطة', 'Equipment and condition, last check and manual ticket books per point'),
            actions: [
              OutlinedButton.icon(
                onPressed: points.isEmpty ? null : () => _export(points),
                icon: const Icon(Icons.download_outlined, size: 18),
                label: const Text('Excel'),
              ),
              IconButton.filledTonal(onPressed: reload, icon: const Icon(Icons.refresh)),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Wrap(spacing: 10, runSpacing: 10, children: [
                VKpi(tx(context, 'النِقاط', 'Points'), VF.n(points.length), icon: Icons.place_outlined, color: VC.info),
                VKpi(tx(context, 'بِها مُشكِلة', 'With issues'), VF.n(withIssues), icon: Icons.report_problem_outlined, color: withIssues > 0 ? VC.bad : VC.ok),
                VKpi(tx(context, 'لَم تُجرَد اليَوم', 'Not checked 24h'), VF.n(staleN), icon: Icons.fact_check_outlined, color: staleN > 0 ? VC.warn : VC.ok),
                VKpi(tx(context, 'دَفتَر قارَب يَنتَهي', 'Book almost done'), VF.n(lowBooks), icon: Icons.menu_book_outlined, color: lowBooks > 0 ? VC.bad : VC.ok),
              ]),
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: 'all', label: Text(tx(context, 'الكُلّ', 'All'))),
                    ButtonSegment(value: 'issues', label: Text(tx(context, 'بِها مُشكِلة', 'Issues'))),
                    ButtonSegment(value: 'stale', label: Text(tx(context, 'لَم تُجرَد', 'Not checked'))),
                    ButtonSegment(value: 'books', label: Text(tx(context, 'دَفاتِر', 'Books'))),
                  ],
                  selected: {_filter},
                  onSelectionChanged: (s) => setState(() => _filter = s.first),
                ),
              ),
              const SizedBox(height: 12),
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(30),
                  child: Center(child: Text(tx(context, 'لا شَيء هُنا.', 'Nothing here.'), style: const TextStyle(color: VC.muted))),
                )
              else
                Wrap(spacing: 12, runSpacing: 12, children: [for (final p in shown) _pointCard(context, p, stale(p), left(p))]),
              const SizedBox(height: 16),
              VPanel(
                title: tx(context, 'سِجِلّ الجَرد (آخِر 100)', 'Check history (last 100)'),
                child: VTable(
                  empty: tx(context, 'لَم يَتِمّ أَيّ جَرد بَعد.', 'No checks yet.'),
                  columns: [
                    DataColumn(label: Text(tx(context, 'الوَقت', 'When'))),
                    DataColumn(label: Text(tx(context, 'النُقطة', 'Point'))),
                    DataColumn(label: Text(tx(context, 'المُوَظَّف', 'Employee'))),
                    DataColumn(label: Text(tx(context, 'المَشاكِل', 'Issues'))),
                    DataColumn(label: Text(tx(context, 'مُلاحَظة', 'Note'))),
                  ],
                  rows: [
                    for (final c in checks)
                      DataRow(cells: [
                        DataCell(Text(VF.dt(vTime(c['created_at'])))),
                        DataCell(Text(vStr(c['point_name']))),
                        DataCell(Text(vStr(c['employee_name']))),
                        DataCell(vNum(c['issues']) == 0
                            ? VPill(tx(context, 'سَليم', 'All good'), color: VC.ok)
                            : Wrap(spacing: 4, children: [
                                for (final i in vList(c['items']).where((i) => vStr(i['state']) != 'good'))
                                  VPill('${i['name']} · ${_stateAr(context, vStr(i['state']))}', color: _stateColor(vStr(i['state']))),
                              ])),
                        DataCell(SizedBox(width: 260, child: Text(vStr(c['note']), maxLines: 2, overflow: TextOverflow.ellipsis))),
                      ]),
                  ],
                ),
              ),
            ]),
          ),
        ]);
      },
    );
  }

  Widget _pointCard(BuildContext context, VJson p, bool stale, int left) {
    final items = _itemsOf(p);
    final books = vList(p['books']);
    final issues = vNum(p['issues']).toInt();
    final t = vTime(p['checked_at']);
    return SizedBox(
      width: 340,
      child: Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: issues > 0 ? VC.bad.withValues(alpha: 0.5) : Colors.black12, width: issues > 0 ? 1.5 : 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(vStr(p['point_name']), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text([vStr(p['point_code']), if (vStr(p['phone']).length > 3) vStr(p['phone'])].join(' · '), style: const TextStyle(color: VC.muted, fontSize: 12)),
                ]),
              ),
              if (issues > 0) VPill(tx(context, '$issues مُشكِلة', '$issues issue${issues == 1 ? '' : 's'}'), color: VC.bad) else VPill(tx(context, 'سَليم', 'All good'), color: VC.ok),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.fact_check_outlined, size: 15, color: stale ? VC.warn : VC.ok),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  t == null
                      ? tx(context, 'لَم يُجرَد', 'Never checked')
                      : '${tx(context, 'آخِر جَرد', 'Last check')} ${VF.dt(t)}${vStr(p['checked_by_name']).isEmpty ? '' : ' · ${p['checked_by_name']}'}',
                  style: TextStyle(fontSize: 12, color: stale ? VC.warn : VC.muted, fontWeight: stale ? FontWeight.w700 : FontWeight.w400),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
            const Divider(height: 18),
            for (final i in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Icon(Icons.circle, size: 8, color: _stateColor(vStr(i['state']))),
                  const SizedBox(width: 7),
                  Expanded(child: Text(vStr(i['name']), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (vStr(i['state']) != 'good') ...[
                    Text(_stateAr(context, vStr(i['state'])), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _stateColor(vStr(i['state'])))),
                    const SizedBox(width: 8),
                  ],
                  Text('× ${vNum(i['qty']).toInt()}', style: const TextStyle(fontWeight: FontWeight.w800)),
                ]),
              ),
            if (books.isNotEmpty) ...[
              const Divider(height: 18),
              Builder(builder: (context) {
                final b = books.first;
                final total = (vNum(b['ticket_to']) - vNum(b['ticket_from']) + 1).toInt();
                final used = vNum(b['used']).toInt();
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    const Icon(Icons.menu_book_outlined, size: 15, color: VC.muted),
                    const SizedBox(width: 5),
                    Expanded(child: Text('${tx(context, 'الدَفتَر', 'Book')} ${b['ticket_from']} → ${b['ticket_to']}', style: const TextStyle(fontSize: 12.5))),
                    Text(tx(context, 'باقي $left', '$left left'), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: left <= 10 ? VC.bad : VC.muted)),
                  ]),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: total <= 0 ? 0 : (used / total).clamp(0.0, 1.0),
                      minHeight: 6,
                      color: left <= 10 ? VC.bad : VC.info,
                      backgroundColor: Colors.black12,
                    ),
                  ),
                ]);
              }),
            ],
          ]),
        ),
      ),
    );
  }

  Future<void> _export(List<VJson> points) async {
    await vExport(context, 'point_assets.xlsx', [
      ExcelSheet(
        name: 'Assets',
        headers: ['Point code', 'Point', 'Item', 'Qty', 'Condition', 'Note', 'Last check', 'Checked by'],
        rows: [
          for (final p in points)
            for (final i in _itemsOf(p))
              [p['point_code'], p['point_name'], i['name'], vNum(i['qty']), vStr(i['state']).isEmpty ? 'good' : i['state'], i['note'], VF.dt(vTime(p['checked_at'])), p['checked_by_name']],
        ],
      ),
      ExcelSheet(
        name: 'Ticket books',
        headers: ['Point code', 'Point', 'From', 'To', 'Used', 'Left', 'Added'],
        rows: [
          for (final p in points)
            for (final b in vList(p['books']))
              [
                p['point_code'], p['point_name'], vNum(b['ticket_from']), vNum(b['ticket_to']), vNum(b['used']),
                vNum(b['ticket_to']) - vNum(b['ticket_from']) + 1 - vNum(b['used']), VF.dt(vTime(b['created_at'])),
              ],
        ],
      ),
    ]);
  }
}
