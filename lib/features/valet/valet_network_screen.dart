import 'package:flutter/material.dart';

import '../../core/services/excel_exporter.dart';
import 'valet_admin.dart';
import 'valet_clients_screen.dart';
import 'valet_network_data.dart';
import 'valet_network_forms.dart';
import 'valet_points_screen.dart';
import 'valet_reports_screen.dart';
import 'valet_ui.dart';

/// 🌐 الشَبَكة — المَناطِق (الجروبات) ▸ النِقاط ▸ الفُروع وَعُمَلاؤها في مَكان واحِد.
/// كُلّ تَعديل هُنا يُرسَل إلى Odoo خِلال دَقيقَتَين، وَما يَتَغَيَّر في Odoo يَظهَر هُنا خِلال 5 دَقائِق.
class ValetNetworkScreen extends StatelessWidget {
  const ValetNetworkScreen({super.key});

  @override
  Widget build(BuildContext context) => const ValetGate(child: _NetBody());
}

typedef _Sel = ({String kind, String id});

class _NetBody extends StatefulWidget {
  const _NetBody();

  @override
  State<_NetBody> createState() => _NetBodyState();
}

class _NetBodyState extends State<_NetBody> {
  Net? _net;
  Object? _err;
  bool _busy = false;
  final _q = TextEditingController();
  bool _tree = true;
  String _tab = 'point'; // tables: area | point | client | branch
  String? _type; // branch type filter (restaurants, hotels…)
  String? _filter; // no_area | unlinked | no_branches | pending | error
  _Sel? _sel;
  final _open = <String>{}; // expanded tree nodes
  int _statsKey = 0;

  bool get _canClients => ValetAdmin.I.can(ValetAdmin.permClients);
  bool get _canSettings => ValetAdmin.I.can(ValetAdmin.permSettings);
  bool _canEdit(String kind) => kind == 'client' || kind == 'branch' ? _canClients : _canSettings;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final d = await ValetAdmin.I.call('vva_network');
      if (!mounted) return;
      setState(() {
        _net = Net(d);
        _err = null;
        _statsKey++;
        if (_sel != null && _row(_sel!) == null) _sel = null;
      });
    } catch (e) {
      if (mounted) setState(() => _err = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  VJson? _row(_Sel s) {
    final n = _net;
    if (n == null) return null;
    return switch (s.kind) { 'area' => n.area[s.id], 'point' => n.point[s.id], 'client' => n.client[s.id], _ => n.branch[s.id] };
  }

  void _select(String kind, String id, {required bool wide}) {
    setState(() => _sel = (kind: kind, id: id));
    if (!wide) {
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => Scaffold(
                appBar: AppBar(title: Text(netKindName(context, kind))),
                body: StatefulBuilder(builder: (c, set) => _details(c, (kind: kind, id: id), onChanged: () => set(() {}))),
              )));
    }
  }

  // ---------------------------------------------------------------- actions
  Future<void> _after(String? id, String kind) async {
    if (id == null) return;
    await _load();
    if (mounted && kind != 'type') setState(() => _sel = (kind: kind, id: id));
  }

  Future<void> _new(String kind, {String? clientId, String? pointId, String? areaId}) async {
    final n = _net;
    if (n == null) return;
    switch (kind) {
      case 'setup':
        if (await netWizard(context, n, clientId: clientId, pointId: pointId) == true) await _load();
      case 'client':
        await _after(await netClientForm(context, n), 'client');
      case 'branch':
        await _after(await netBranchForm(context, n, clientId: clientId, pointId: pointId), 'branch');
      case 'point':
        await _after(await netPointForm(context, n, areaId: areaId), 'point');
      case 'area':
        await _after(await netAreaForm(context, n), 'area');
    }
  }

  Future<void> _edit(_Sel s) async {
    final n = _net, r = _row(s);
    if (n == null || r == null) return;
    final id = switch (s.kind) {
      'area' => await netAreaForm(context, n, row: r),
      'point' => await netPointForm(context, n, row: r),
      'client' => await netClientForm(context, n, row: r),
      _ => await netBranchForm(context, n, row: r),
    };
    await _after(id, s.kind);
  }

  Future<void> _delete(_Sel s) async {
    final r = _row(s);
    if (r == null) return;
    final dry = await vGuard(context, () => ValetAdmin.I.call('vva_network_delete', {'p_kind': s.kind, 'p_id': s.id, 'p_dry': true}));
    if (dry == null || !mounted) return;
    final u = vMap(dry['usage']);
    final archive = dry['action'] == 'archive';
    final uses = [
      if (vNum(u['tickets']) > 0) tx(context, '${VF.n(vNum(u['tickets']))} تَذكَرة', '${VF.n(vNum(u['tickets']))} tickets'),
      if (vNum(u['shifts']) > 0) tx(context, '${VF.n(vNum(u['shifts']))} وَرديّة', '${VF.n(vNum(u['shifts']))} shifts'),
      if (vNum(u['staff']) > 0) tx(context, '${VF.n(vNum(u['staff']))} مُوَظَّف', '${VF.n(vNum(u['staff']))} staff'),
      if (vNum(u['branches']) > 0) tx(context, '${VF.n(vNum(u['branches']))} فَرع', '${VF.n(vNum(u['branches']))} branches'),
      if (vNum(u['points']) > 0) tx(context, '${VF.n(vNum(u['points']))} نُقطة', '${VF.n(vNum(u['points']))} points'),
    ].join(' · ');
    final name = vStr(r['name']);
    final msg = archive
        ? tx(context, '$name مُستَخدَم ($uses).\nلا يُحذَف؛ يُغلَق هُنا وَفي Odoo وَتَبقى بَياناته في التَقارير.',
            '$name is used ($uses).\nIt is not deleted; it is closed here and in Odoo and its data stays in the reports.')
        : tx(context, 'يُحذَف $name هُنا وَمِن Odoo.${uses.isEmpty ? '' : '\n($uses)'}${s.kind == 'client' ? '\nتُحذَف فُروعه أَيضاً.' : ''}',
            '$name is deleted here and in Odoo.${uses.isEmpty ? '' : '\n($uses)'}${s.kind == 'client' ? '\nIts branches are deleted too.' : ''}');
    final ok = await vConfirm(context, archive ? tx(context, 'إغلاق بَدَل الحَذف', 'Close instead of delete') : tx(context, 'حَذف؟', 'Delete?'), msg,
        button: archive ? tx(context, 'إغلاق', 'Close') : tx(context, 'حَذف', 'Delete'));
    if (!ok || !mounted) return;
    final res = await vGuard(context, () => ValetAdmin.I.call('vva_network_delete', {'p_kind': s.kind, 'p_id': s.id}));
    if (res == null || !mounted) return;
    vToast(context, res['result'] == 'deleted' ? tx(context, 'تَمّ الحَذف.', 'Deleted.') : tx(context, 'تَمّ الإغلاق.', 'Closed.'));
    if (res['result'] == 'deleted') setState(() => _sel = null);
    await _load();
  }

  static String _entity(String kind) => switch (kind) { 'client' => 'master', 'branch' => 'site', _ => kind };

  Future<void> _retry([_Sel? s]) async {
    final r = await vGuard(context, () => ValetAdmin.I.call('vva_network_retry', {'p_entity': s == null ? null : _entity(s.kind), 'p_id': s?.id}),
        ok: tx(context, 'يُعاد الإرسال خِلال دَقيقَتَين.', 'Sent again within two minutes.'));
    if (r != null) await _load();
  }

  Future<void> _moveArea(String pointId, String? areaId) async {
    final p = _net?.point[pointId];
    if (p == null || vStr(p['area_id']) == (areaId ?? '')) return;
    final r = await vGuard(context, () => ValetAdmin.I.call('vva_network_save', {'p_kind': 'point', 'p_id': pointId, 'p_data': {'name': p['name'], 'area_id': areaId, 'is_active': p['is_active']}}),
        ok: tx(context, 'نُقِلَت ${p['code']} إلى ${areaId == null ? 'بِلا مَنطِقة' : _net!.areaName(areaId)}.',
            '${p['code']} moved to ${areaId == null ? 'no area' : _net!.areaName(areaId)}.'));
    if (r != null) await _load();
  }

  Future<void> _export() async {
    final n = _net!;
    await vExport(context, 'network', [
      ExcelSheet(name: 'Areas', headers: const ['Area', 'Code', 'Points', 'Open', 'Odoo'], rows: [
        for (final a in n.areas) [a['name'], a['code'], (n.pointsOfArea[vStr(a['id'])] ?? const []).length, vBool(a['is_active']) ? 'yes' : 'no', a['odoo_id']],
      ]),
      ExcelSheet(name: 'Points', headers: const ['Code', 'Point', 'Area', 'Branches', 'Address', 'Open', 'Odoo'], rows: [
        for (final p in n.points)
          [p['code'], p['name'], n.areaName(p['area_id']), (n.branchesOfPoint[vStr(p['id'])] ?? const []).length, p['address'], vBool(p['is_active']) ? 'yes' : 'no', p['odoo_id']],
      ]),
      ExcelSheet(name: 'Clients', headers: const ['Client', 'TRN', 'Type', 'Branches', 'Active', 'Odoo'], rows: [
        for (final c in n.clients)
          [c['name'], c['vat'], n.typeName(context, c['type_id']), (n.branchesOfClient[vStr(c['id'])] ?? const []).length, vBool(c['is_active']) ? 'yes' : 'no', c['odoo_id']],
      ]),
      ExcelSheet(name: 'Branches', headers: const ['Branch', 'Client', 'Type', 'Points', 'Area', 'TRN', 'Phone', 'Active', 'Odoo'], rows: [
        for (final b in n.branches)
          [
            b['name'],
            n.clientName(b['client_id']),
            n.typeName(context, b['type_id']),
            (n.pointsOfBranch[vStr(b['id'])] ?? const []).map((p) => vStr(n.point[p]?['code'])).join(', '),
            (n.pointsOfBranch[vStr(b['id'])] ?? const []).map((p) => n.areaName(n.point[p]?['area_id'])).toSet().join(', '),
            b['vat'],
            b['phone'],
            vBool(b['is_active']) ? 'yes' : 'no',
            b['odoo_id'],
          ],
      ]),
    ]);
  }

  // ---------------------------------------------------------------- build
  @override
  Widget build(BuildContext context) {
    final n = _net;
    if (n == null) {
      if (_err != null) {
        return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, color: VC.bad, size: 40),
            const SizedBox(height: 8),
            Text(vErr(context, _err!), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: Text(tx(context, 'إعادة المُحاوَلة', 'Try again'))),
          ]),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 1080;
      final list = _tree ? _treeView(n, wide) : _tables(n, wide);
      return Stack(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _header(n),
          _kpis(n),
          _alerts(n),
          _toolbar(),
          Expanded(
            child: wide
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Expanded(flex: 5, child: Card(margin: EdgeInsets.zero, clipBehavior: Clip.antiAlias, child: list)),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 6,
                        child: Card(
                          margin: EdgeInsets.zero,
                          clipBehavior: Clip.antiAlias,
                          child: _sel == null
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                                      const Icon(Icons.touch_app_outlined, size: 40, color: VC.muted),
                                      const SizedBox(height: 8),
                                      Text(tx(context, 'اختَر مَنطِقة أَو نُقطة أَو عَميلاً أَو فَرعاً لِعَرض تَفاصيله.', 'Pick an area, point, client or branch to see its details.'),
                                          textAlign: TextAlign.center, style: const TextStyle(color: VC.muted)),
                                    ]),
                                  ),
                                )
                              : _details(context, _sel!),
                        ),
                      ),
                    ]),
                  )
                : Padding(padding: const EdgeInsets.fromLTRB(8, 0, 8, 8), child: Card(margin: EdgeInsets.zero, clipBehavior: Clip.antiAlias, child: list)),
          ),
        ]),
        if (_busy) const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(minHeight: 2)),
      ]);
    });
  }

  Widget _header(Net n) => VHead(
        tx(context, 'الشَبَكة', 'Network'),
        subtitle: tx(context, 'المَناطِق ▸ النِقاط ▸ الفُروع وَعُمَلاؤها · مُتَزامِنة مَع Odoo في الاتِّجاهَين',
            'Areas ▸ points ▸ branches and their clients · synced with Odoo both ways'),
        actions: [
          IconButton.filledTonal(tooltip: tx(context, 'تَحديث', 'Refresh'), onPressed: _load, icon: const Icon(Icons.refresh)),
          PopupMenuButton<String>(
            tooltip: 'Excel',
            icon: const Icon(Icons.table_view_outlined),
            onSelected: (v) async {
              if (v == 'export') await _export();
              if (v == 'template' && mounted) await netImportTemplate(context);
              if (v == 'import' && mounted && await netImport(context)) await _load();
            },
            itemBuilder: (c) => [
              PopupMenuItem(value: 'export', child: ListTile(dense: true, leading: const Icon(Icons.download), title: Text(tx(c, 'تَصدير Excel', 'Export Excel')))),
              if (_canClients) ...[
                PopupMenuItem(value: 'template', child: ListTile(dense: true, leading: const Icon(Icons.description_outlined), title: Text(tx(c, 'قالَب الاستيراد', 'Import template')))),
                PopupMenuItem(value: 'import', child: ListTile(dense: true, leading: const Icon(Icons.upload_file), title: Text(tx(c, 'استيراد مِن Excel', 'Import from Excel')))),
              ],
            ],
          ),
          if (_canClients || _canSettings)
            MenuAnchor(
              builder: (c, ctl, _) => FilledButton.icon(
                onPressed: () => ctl.isOpen ? ctl.close() : ctl.open(),
                icon: const Icon(Icons.add),
                label: Text(tx(context, 'جَديد', 'New')),
              ),
              menuChildren: [
                if (_canClients)
                  MenuItemButton(
                    leadingIcon: const Icon(Icons.auto_awesome_outlined),
                    onPressed: () => _new('setup'),
                    child: Text(tx(context, 'إعداد كامِل  (عَميل ← فُروع ← نُقطة)', 'Full setup  (client → branches → point)')),
                  ),
                if (_canClients) MenuItemButton(leadingIcon: Icon(netIcon('client')), onPressed: () => _new('client'), child: Text(tx(context, 'عَميل', 'Client'))),
                if (_canClients) MenuItemButton(leadingIcon: Icon(netIcon('branch')), onPressed: () => _new('branch'), child: Text(tx(context, 'فَرع', 'Branch'))),
                if (_canSettings) MenuItemButton(leadingIcon: Icon(netIcon('point')), onPressed: () => _new('point'), child: Text(tx(context, 'نُقطة', 'Point'))),
                if (_canSettings) MenuItemButton(leadingIcon: Icon(netIcon('area')), onPressed: () => _new('area'), child: Text(tx(context, 'مَنطِقة (جروب)', 'Area (group)'))),
              ],
            ),
        ],
      );

  Widget _kpis(Net n) {
    Widget k(String kind, String ar, String en, int v) => InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() {
            _tree = false;
            _tab = kind;
            _filter = null;
          }),
          child: VKpi(tx(context, ar, en), VF.n(v), icon: netIcon(kind), color: netColor(kind)),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(spacing: 10, runSpacing: 10, children: [
        k('area', 'المَناطِق', 'Areas', n.areas.length),
        k('point', 'النِقاط', 'Points', n.points.length),
        k('client', 'العُمَلاء', 'Clients', n.clients.length),
        k('branch', 'الفُروع', 'Branches', n.branches.length),
      ]),
    );
  }

  Widget _alerts(Net n) {
    final noArea = n.pointsWithoutArea.length, unlinked = n.branchesUnlinked.length, noBr = n.clientsWithoutBranches.length;
    final pending = n.syncRows('pending').length, errors = n.syncRows('error').length;
    Widget chip(String key, String label, int count, Color color, IconData icon) => FilterChip(
          selected: _filter == key,
          showCheckmark: false,
          avatar: Icon(icon, size: 16, color: color),
          label: Text('$label  $count'),
          side: BorderSide(color: color.withValues(alpha: 0.5)),
          backgroundColor: color.withValues(alpha: 0.08),
          selectedColor: color.withValues(alpha: 0.22),
          onSelected: (v) => setState(() {
            _filter = v ? key : null;
            if (v && key == 'no_area') _tab = 'point';
            if (v && key == 'unlinked') _tab = 'branch';
            if (v && key == 'no_branches') _tab = 'client';
          }),
        );
    final chips = [
      if (noArea > 0) chip('no_area', tx(context, 'نِقاط بِلا مَنطِقة', 'Points without an area'), noArea, VC.warn, Icons.location_off_outlined),
      if (unlinked > 0) chip('unlinked', tx(context, 'فُروع غَير مَربوطة', 'Branches not linked'), unlinked, VC.warn, Icons.link_off),
      if (noBr > 0) chip('no_branches', tx(context, 'عُمَلاء بِلا فُروع', 'Clients without branches'), noBr, VC.muted, Icons.domain_disabled_outlined),
      if (pending > 0) chip('pending', tx(context, 'يُرسَل لـ Odoo', 'Sending to Odoo'), pending, VC.info, Icons.sync),
      if (errors > 0) chip('error', tx(context, 'أَخطاء Odoo', 'Odoo errors'), errors, VC.bad, Icons.error_outline),
    ];
    if (chips.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Row(children: [
          const Icon(Icons.verified_outlined, color: VC.ok, size: 18),
          const SizedBox(width: 6),
          Text(tx(context, 'كُلّ شَيء مَربوط وَمُتَزامِن مَع Odoo.', 'Everything is linked and synced with Odoo.'), style: const TextStyle(color: VC.ok)),
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        ...chips,
        if (errors > 0 && _canSettings) TextButton.icon(onPressed: _retry, icon: const Icon(Icons.replay, size: 18), label: Text(tx(context, 'إعادة إرسال الكُلّ', 'Send all again'))),
      ]),
    );
  }

  Widget _toolbar() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: 380,
            child: TextField(
              controller: _q,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                hintText: tx(context, 'ابحَث عَن عَميل أَو فَرع أَو نُقطة أَو مَنطِقة أَو TRN…', 'Search a client, branch, point, area or TRN…'),
                suffixIcon: _q.text.isEmpty ? null : IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(_q.clear)),
              ),
            ),
          ),
          _typeFilter(),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: true, icon: const Icon(Icons.account_tree_outlined), label: Text(tx(context, 'شَجَرة', 'Tree'))),
              ButtonSegment(value: false, icon: const Icon(Icons.table_rows_outlined), label: Text(tx(context, 'جَداوِل', 'Tables'))),
            ],
            selected: {_tree},
            onSelectionChanged: (v) => setState(() => _tree = v.first),
          ),
          if (!_tree)
            SegmentedButton<String>(
              segments: [
                for (final k in const ['area', 'point', 'client', 'branch'])
                  ButtonSegment(value: k, icon: Icon(netIcon(k), size: 18), label: Text(netKindName(context, k))),
              ],
              selected: {_tab},
              onSelectionChanged: (v) => setState(() => _tab = v.first),
            ),
          if (_filter != null)
            ActionChip(avatar: const Icon(Icons.filter_alt_off_outlined, size: 16), label: Text(tx(context, 'إلغاء الفِلتَر', 'Clear filter')), onPressed: () => setState(() => _filter = null)),
        ]),
      );

  Widget _typeFilter() {
    final n = _net!;
    final counts = <String, int>{};
    for (final b in n.branches) {
      final t = vStr(b['type_id']);
      if (t.isNotEmpty) counts[t] = (counts[t] ?? 0) + 1;
    }
    return MenuAnchor(
      builder: (c, ctl, _) => _type == null
          ? OutlinedButton.icon(
              onPressed: () => ctl.isOpen ? ctl.close() : ctl.open(),
              icon: const Icon(Icons.category_outlined, size: 18),
              label: Text(tx(context, 'النَوع: الكُلّ', 'Type: all')),
            )
          : InputChip(
              avatar: const Icon(Icons.category_outlined, size: 16),
              label: Text('${n.typeName(context, _type)} (${counts[_type] ?? 0})'),
              onPressed: () => ctl.isOpen ? ctl.close() : ctl.open(),
              onDeleted: () => setState(() => _type = null),
            ),
      menuChildren: [
        MenuItemButton(onPressed: () => setState(() => _type = null), child: Text(tx(context, 'كُلّ الأَنواع', 'All types'))),
        for (final t in [...n.types]..sort((a, b) => (counts[vStr(b['id'])] ?? 0) - (counts[vStr(a['id'])] ?? 0)))
          MenuItemButton(
            onPressed: () => setState(() {
              _type = vStr(t['id']);
              if (!_tree && (_tab == 'area')) _tab = 'branch';
            }),
            trailingIcon: Text('${counts[vStr(t['id'])] ?? 0}', style: const TextStyle(color: VC.muted)),
            child: Text(n.typeName(context, t['id'])),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------- search helpers
  String get _qs => _q.text.trim().toLowerCase();
  bool _hit(Net n, String kind, VJson r) {
    if (_type != null) {
      // a type filter keeps only branches of that type (and what leads to them)
      if (kind != 'branch' || vStr(r['type_id']) != _type) return false;
    }
    return _qs.isEmpty || n.hay(kind, r).contains(_qs);
  }

  bool get _searching => _qs.isNotEmpty || _type != null;

  // ---------------------------------------------------------------- tree
  Widget _treeView(Net n, bool wide) {
    final rows = <Widget>[];
    final searching = _searching;

    if (_filter == 'pending' || _filter == 'error') {
      for (final (kind, r) in n.syncRows(_filter!)) {
        if (kind == 'link') {
          final b = n.branch[vStr(r['branch_id'])];
          rows.add(_node(n, 'branch', b ?? r, 0, wide,
              title: '${n.pointLabel(r['point_id'])}  ↔  ${vStr(b?['name'])}', subtitle: vStr(r['sync_error']).isEmpty ? tx(context, 'رَبط', 'Link') : vStr(r['sync_error'])));
        } else {
          rows.add(_node(n, kind, r, 0, wide, subtitle: vStr(r['sync_error']).isEmpty ? netKindName(context, kind) : vStr(r['sync_error'])));
        }
      }
      return _listOrEmpty(rows);
    }

    if (_filter == null || _filter == 'no_area') {
      final groups = <(String, VJson?)>[
        if (_filter == null) for (final a in n.areas) (vStr(a['id']), a),
        ('', null),
      ];
      for (final (aid, a) in groups) {
        final pts = (aid.isEmpty ? n.pointsWithoutArea : (n.pointsOfArea[aid] ?? const <VJson>[])).toList()
          ..sort((x, y) => vStr(x['code']).compareTo(vStr(y['code'])));
        final areaHit = a != null && searching && _hit(n, 'area', a);
        final visible = <VJson>[];
        for (final p in pts) {
          final pid = vStr(p['id']);
          final brs = n.branchesOfPoint[pid] ?? const <String>[];
          if (!searching || areaHit || _hit(n, 'point', p) || brs.any((b) => _hit(n, 'branch', n.branch[b]!))) visible.add(p);
        }
        if (searching && !areaHit && visible.isEmpty) continue;
        if (aid.isEmpty && pts.isEmpty) continue;
        final key = 'a:$aid';
        final open = searching || _open.contains(key) || _filter == 'no_area';
        rows.add(DragTarget<String>(
          onWillAcceptWithDetails: (d) => _canSettings,
          onAcceptWithDetails: (d) => _moveArea(d.data, aid.isEmpty ? null : aid),
          builder: (c, cand, _) => Container(
            color: cand.isNotEmpty ? VC.info.withValues(alpha: 0.12) : null,
            child: a == null
                ? _groupRow(key, Icons.location_off_outlined, tx(context, 'بِلا مَنطِقة', 'Without an area'), tx(context, '${pts.length} نُقطة', '${pts.length} points'), VC.warn, open)
                : _node(n, 'area', a, 0, wide,
                    expandKey: key, expanded: open, subtitle: tx(context, '${pts.length} نُقطة', '${pts.length} points'), trailingAdd: _canSettings ? () => _new('point', areaId: aid) : null),
          ),
        ));
        if (!open) continue;
        for (final p in visible) {
          final pid = vStr(p['id']);
          final pKey = 'p:$pid';
          final brs = n.branchesOfPoint[pid] ?? const <String>[];
          final pHit = searching && (_hit(n, 'point', p) || areaHit);
          final shownBr = brs.where((b) => !searching || pHit || _hit(n, 'branch', n.branch[b]!)).toList();
          final pOpen = (searching && shownBr.isNotEmpty) || _open.contains(pKey);
          final node = _node(n, 'point', p, 1, wide,
              expandKey: pKey,
              expanded: pOpen,
              subtitle: [
                tx(context, '${brs.length} فَرع', '${brs.length} branches'),
                if (vNum(p['active_cars']) > 0) tx(context, '${p['active_cars']} سَيّارة الآن', '${p['active_cars']} cars now'),
              ].join(' · '));
          rows.add(_canSettings
              ? Draggable<String>(
                  data: pid,
                  feedback: Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(padding: const EdgeInsets.all(10), child: Text('${p['code']}  ${p['name']}')),
                  ),
                  childWhenDragging: Opacity(opacity: 0.4, child: node),
                  child: node,
                )
              : node);
          if (!pOpen) continue;
          for (final b in shownBr) {
            final br = n.branch[b]!;
            final l = n.link['$pid|$b'];
            rows.add(_node(n, 'branch', br, 2, wide,
                subtitle: [
                  n.clientName(br['client_id']),
                  n.typeName(context, br['type_id']),
                  if (vStr(l?['unit']).isNotEmpty) tx(context, 'وِحدة ${l!['unit']}', 'Unit ${l['unit']}'),
                ].where((e) => e.isNotEmpty).join(' · ')));
          }
          if (shownBr.isEmpty && !searching) {
            rows.add(Padding(
              padding: const EdgeInsetsDirectional.only(start: 76, top: 2, bottom: 6),
              child: Text(tx(context, 'لا فُروع مَربوطة.', 'No branches linked.'), style: const TextStyle(color: VC.muted, fontSize: 12)),
            ));
          }
        }
      }
    }

    if (_filter == null || _filter == 'unlinked') {
      final un = n.branchesUnlinked.where((b) => _hit(n, 'branch', b)).toList()..sort((a, b) => n.clientName(a['client_id']).compareTo(n.clientName(b['client_id'])));
      if (un.isNotEmpty) {
        const key = 'g:unlinked';
        final open = searching || _open.contains(key) || _filter == 'unlinked';
        rows.add(_groupRow(key, Icons.link_off, tx(context, 'فُروع غَير مَربوطة بِنُقطة', 'Branches not linked to a point'),
            tx(context, '${un.length} فَرع', '${un.length} branches'), VC.warn, open));
        if (open) {
          for (final b in un) {
            rows.add(_node(n, 'branch', b, 1, wide, subtitle: [n.clientName(b['client_id']), n.typeName(context, b['type_id'])].where((e) => e.isNotEmpty).join(' · ')));
          }
        }
      }
    }

    if (_filter == null || _filter == 'no_branches') {
      final nb = n.clientsWithoutBranches.where((c) => _hit(n, 'client', c)).toList();
      if (nb.isNotEmpty) {
        const key = 'g:nobranch';
        final open = searching || _open.contains(key) || _filter == 'no_branches';
        rows.add(_groupRow(key, Icons.domain_disabled_outlined, tx(context, 'عُمَلاء بِلا فُروع', 'Clients without branches'),
            tx(context, '${nb.length} عَميل', '${nb.length} clients'), VC.muted, open));
        if (open) {
          for (final c in nb) {
            rows.add(_node(n, 'client', c, 1, wide, subtitle: vStr(c['vat']), trailingAdd: _canClients ? () => _new('branch', clientId: vStr(c['id'])) : null));
          }
        }
      }
    }

    // clients found by the search (their page shows every branch)
    if (searching && _filter == null) {
      final cl = n.clients.where((c) => _hit(n, 'client', c) && (n.branchesOfClient[vStr(c['id'])] ?? const []).isNotEmpty).take(30).toList();
      if (cl.isNotEmpty) {
        rows.add(_groupRow('g:clients', Icons.apartment, tx(context, 'عُمَلاء مُطابِقون', 'Matching clients'), '${cl.length}', netColor('client'), true));
        for (final c in cl) {
          rows.add(_node(n, 'client', c, 1, wide,
              subtitle: tx(context, '${(n.branchesOfClient[vStr(c['id'])] ?? const []).length} فَرع', '${(n.branchesOfClient[vStr(c['id'])] ?? const []).length} branches')));
        }
      }
    }
    return _listOrEmpty(rows);
  }

  Widget _listOrEmpty(List<Widget> rows) => rows.isEmpty
      ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(tx(context, 'لا نَتائِج.', 'No results.'), style: const TextStyle(color: VC.muted))))
      : ListView(padding: const EdgeInsets.symmetric(vertical: 6), children: rows);

  Widget _groupRow(String key, IconData icon, String title, String sub, Color color, bool open) => InkWell(
        onTap: () => setState(() => _open.contains(key) ? _open.remove(key) : _open.add(key)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
          child: Row(children: [
            Icon(open ? Icons.expand_more : Icons.chevron_right, size: 20, color: VC.muted),
            const SizedBox(width: 4),
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800))),
            Text(sub, style: const TextStyle(color: VC.muted, fontSize: 12)),
          ]),
        ),
      );

  Widget _node(Net n, String kind, VJson r, int depth, bool wide,
      {String? title, String? subtitle, String? expandKey, bool expanded = false, VoidCallback? trailingAdd}) {
    final id = vStr(r['id']);
    final selected = _sel?.kind == kind && _sel?.id == id;
    final closed = !vBool(r['is_active']);
    final label = title ?? (kind == 'point' ? '${r['code']}  ${r['name']}' : vStr(r['name']));
    return Material(
      color: selected ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.10) : Colors.transparent,
      child: InkWell(
        onTap: () => _select(kind, id, wide: wide),
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(8.0 + depth * 26, 6, 8, 6),
          child: Row(children: [
            SizedBox(
              width: 28,
              child: expandKey == null
                  ? null
                  : IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      iconSize: 20,
                      icon: Icon(expanded ? Icons.expand_more : Icons.chevron_right, color: VC.muted),
                      onPressed: () => setState(() => _open.contains(expandKey) ? _open.remove(expandKey) : _open.add(expandKey)),
                    ),
            ),
            Icon(netIcon(kind), size: 20, color: closed ? VC.muted : netColor(kind)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: depth == 0 ? FontWeight.w800 : FontWeight.w600, decoration: closed ? TextDecoration.lineThrough : null, color: closed ? VC.muted : null)),
                if (subtitle != null && subtitle.isNotEmpty)
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: r['sync'] == 'error' ? VC.bad : VC.muted, fontSize: 12)),
              ]),
            ),
            if (r['sync'] == 'error')
              const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Icon(Icons.error_outline, size: 16, color: VC.bad))
            else if (r['sync'] == 'pending')
              const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Icon(Icons.sync, size: 16, color: VC.warn)),
            if (trailingAdd != null)
              IconButton(visualDensity: VisualDensity.compact, iconSize: 18, tooltip: tx(context, 'إضافة', 'Add'), icon: const Icon(Icons.add), onPressed: trailingAdd),
            if (kind == 'point' && _canSettings) const Icon(Icons.drag_indicator, size: 16, color: VC.muted),
          ]),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- tables
  Widget _tables(Net n, bool wide) {
    DataRow row(String kind, VJson r, List<Widget> cells) => DataRow(
          selected: _sel?.kind == kind && _sel?.id == vStr(r['id']),
          onSelectChanged: (_) => _select(kind, vStr(r['id']), wide: wide),
          cells: [for (final c in cells) DataCell(c)],
        );
    Widget status(VJson r) => vBool(r['is_active']) ? VPill(tx(context, 'نَشِط', 'Active'), color: VC.ok) : VPill(tx(context, 'مُغلَق', 'Closed'));
    late final Widget table;
    switch (_tab) {
      case 'area':
        table = VTable(columns: [
          DataColumn(label: Text(tx(context, 'المَنطِقة', 'Area'))),
          DataColumn(label: Text(tx(context, 'الكود', 'Code'))),
          DataColumn(label: Text(tx(context, 'النِقاط', 'Points')), numeric: true),
          DataColumn(label: Text(tx(context, 'الحالة', 'Status'))),
          const DataColumn(label: Text('Odoo')),
        ], rows: [
          for (final a in n.areas.where((a) => _hit(n, 'area', a)))
            row('area', a, [
              Text(vStr(a['name']), style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(vStr(a['code'])),
              Text('${(n.pointsOfArea[vStr(a['id'])] ?? const []).length}'),
              status(a),
              netSyncPill(context, a),
            ]),
        ]);
      case 'point':
        final pts = (_filter == 'no_area' ? n.pointsWithoutArea : n.points).where((p) => (_type == null
                ? _hit(n, 'point', p)
                : (n.branchesOfPoint[vStr(p['id'])] ?? const <String>[]).any((b) => _hit(n, 'branch', n.branch[b]!))) && _syncOk(p));
        table = VTable(columns: [
          DataColumn(label: Text(tx(context, 'الكود', 'Code'))),
          DataColumn(label: Text(tx(context, 'النُقطة', 'Point'))),
          DataColumn(label: Text(tx(context, 'المَنطِقة', 'Area'))),
          DataColumn(label: Text(tx(context, 'الفُروع', 'Branches')), numeric: true),
          DataColumn(label: Text(tx(context, 'سَيّارات الآن', 'Cars now')), numeric: true),
          DataColumn(label: Text(tx(context, 'الحالة', 'Status'))),
          const DataColumn(label: Text('Odoo')),
        ], rows: [
          for (final p in pts)
            row('point', p, [
              Text(vStr(p['code'])),
              Text(vStr(p['name']), style: const TextStyle(fontWeight: FontWeight.w600)),
              vStr(p['area_id']).isEmpty ? Text(tx(context, 'بِلا مَنطِقة', 'No area'), style: const TextStyle(color: VC.warn)) : Text(n.areaName(p['area_id'])),
              Text('${(n.branchesOfPoint[vStr(p['id'])] ?? const []).length}'),
              Text(VF.n(vNum(p['active_cars']))),
              status(p),
              netSyncPill(context, p),
            ]),
        ]);
      case 'client':
        final cl = (_filter == 'no_branches' ? n.clientsWithoutBranches : n.clients).where((c) => (_type == null
                ? _hit(n, 'client', c)
                : (n.branchesOfClient[vStr(c['id'])] ?? const <VJson>[]).any((b) => _hit(n, 'branch', b))) && _syncOk(c));
        table = VTable(columns: [
          DataColumn(label: Text(tx(context, 'العَميل', 'Client'))),
          const DataColumn(label: Text('TRN')),
          DataColumn(label: Text(tx(context, 'النَوع', 'Type'))),
          DataColumn(label: Text(tx(context, 'الفُروع', 'Branches')), numeric: true),
          DataColumn(label: Text(tx(context, 'النِقاط', 'Points')), numeric: true),
          DataColumn(label: Text(tx(context, 'الحالة', 'Status'))),
          const DataColumn(label: Text('Odoo')),
        ], rows: [
          for (final c in cl)
            row('client', c, [
              Text(vStr(c['name']), style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(vStr(c['vat'])),
              Text(n.typeName(context, c['type_id'])),
              Text('${(n.branchesOfClient[vStr(c['id'])] ?? const []).length}'),
              Text('${{for (final b in n.branchesOfClient[vStr(c['id'])] ?? const <VJson>[]) ...(n.pointsOfBranch[vStr(b['id'])] ?? const <String>[])}.length}'),
              status(c),
              netSyncPill(context, c),
            ]),
        ]);
      default:
        final br = (_filter == 'unlinked' ? n.branchesUnlinked : n.branches).where((b) => _hit(n, 'branch', b) && _syncOk(b));
        table = VTable(columns: [
          DataColumn(label: Text(tx(context, 'الفَرع', 'Branch'))),
          DataColumn(label: Text(tx(context, 'العَميل', 'Client'))),
          DataColumn(label: Text(tx(context, 'النَوع', 'Type'))),
          DataColumn(label: Text(tx(context, 'النِقاط', 'Points'))),
          DataColumn(label: Text(tx(context, 'الحالة', 'Status'))),
          const DataColumn(label: Text('Odoo')),
        ], rows: [
          for (final b in br)
            row('branch', b, [
              Text(vStr(b['name']), style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(n.clientName(b['client_id'])),
              Text(n.typeName(context, b['type_id'])),
              (n.pointsOfBranch[vStr(b['id'])] ?? const []).isEmpty
                  ? Text(tx(context, 'غَير مَربوط', 'Not linked'), style: const TextStyle(color: VC.warn))
                  : Text((n.pointsOfBranch[vStr(b['id'])] ?? const []).map((p) => vStr(n.point[p]?['code'])).join(', ')),
              status(b),
              netSyncPill(context, b),
            ]),
        ]);
    }
    return SingleChildScrollView(child: table);
  }

  bool _syncOk(VJson r) => _filter == 'pending' || _filter == 'error' ? r['sync'] == _filter : true;

  // ---------------------------------------------------------------- details
  Widget _details(BuildContext context, _Sel s, {VoidCallback? onChanged}) {
    final n = _net!;
    final r = _row(s);
    if (r == null) return Center(child: Text(tx(context, 'لَم يَعُد مَوجوداً.', 'It no longer exists.')));
    final edit = _canEdit(s.kind);
    final kind = s.kind, id = s.id;

    Widget chip(String k, String cid, String label, {String? sub}) => ActionChip(
          avatar: Icon(netIcon(k), size: 16, color: netColor(k)),
          label: Text(sub == null || sub.isEmpty ? label : '$label · $sub'),
          onPressed: () => _select(k, cid, wide: true),
        );

    final title = kind == 'point' ? '${r['code']} · ${r['name']}' : vStr(r['name']);
    final facts = <(String, String)>[];
    final relations = <Widget>[];
    final extra = <Widget>[];

    switch (kind) {
      case 'area':
        final pts = n.pointsOfArea[id] ?? const <VJson>[];
        facts.add((tx(context, 'الكود', 'Code'), vStr(r['code'])));
        relations.add(VPanel(
          title: tx(context, 'النِقاط (${pts.length})', 'Points (${pts.length})'),
          actions: [if (_canSettings) TextButton.icon(onPressed: () => _new('point', areaId: id), icon: const Icon(Icons.add, size: 18), label: Text(tx(context, 'نُقطة', 'Point')))],
          child: pts.isEmpty
              ? Text(tx(context, 'لا نِقاط. اسحَب نُقطة مِن الشَجَرة إلى هذه المَنطِقة، أَو عَدِّل المَنطِقة.', 'No points. Drag a point onto this area in the tree, or edit the area.'),
                  style: const TextStyle(color: VC.muted))
              : Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final p in pts) chip('point', vStr(p['id']), '${p['code']} ${p['name']}', sub: tx(context, '${(n.branchesOfPoint[vStr(p['id'])] ?? const []).length} فَرع', '${(n.branchesOfPoint[vStr(p['id'])] ?? const []).length} br.')),
                ]),
        ));
      case 'point':
        final brs = n.branchesOfPoint[id] ?? const <String>[];
        facts.addAll([
          (tx(context, 'المَنطِقة', 'Area'), vStr(r['area_id']).isEmpty ? tx(context, 'بِلا مَنطِقة', 'No area') : n.areaName(r['area_id'])),
          (tx(context, 'العُنوان', 'Address'), vStr(r['address'])),
          if (r['lat'] != null) (tx(context, 'المَوقِع', 'Location'), '${r['lat']}, ${r['lng']}'),
        ]);
        extra.addAll([
          if (_canSettings)
            OutlinedButton.icon(
              icon: const Icon(Icons.swap_horiz, size: 18),
              label: Text(tx(context, 'نَقل لِمَنطِقة', 'Move to area')),
              onPressed: () async {
                final pick = await netPick(context, tx(context, 'المَنطِقة', 'Area'), [
                  NetOption('', tx(context, 'بِلا مَنطِقة', 'No area')),
                  for (final a in n.areas) NetOption(vStr(a['id']), vStr(a['name']), sub: vStr(a['code']), icon: Icons.map_outlined),
                ], selected: {vStr(r['area_id'])});
                if (pick != null) await _moveArea(id, pick.first.isEmpty ? null : pick.first);
              },
            ),
          OutlinedButton.icon(
            icon: const Icon(Icons.phone_android, size: 18),
            label: Text(tx(context, 'إعدادات تَطبيق الفاليه', 'Valet app settings')),
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ValetPointDetailScreen(pointId: id, title: vStr(r['name']))));
              await _load();
            },
          ),
        ]);
        relations.add(VPanel(
          title: tx(context, 'الفُروع (${brs.length})', 'Branches (${brs.length})'),
          actions: [
            if (_canClients) ...[
              TextButton.icon(
                icon: const Icon(Icons.add_link, size: 18),
                label: Text(tx(context, 'رَبط فُروع', 'Link branches')),
                onPressed: () async {
                  final pick = await netPick(context, tx(context, 'فُروع ${r['name']}', 'Branches of ${r['name']}'), netBranchOptions(n), selected: brs.toSet(), multi: true);
                  if (pick == null || !context.mounted) return;
                  final ok = await vGuard(context, () => ValetAdmin.I.call('vva_network_save', {'p_kind': 'point', 'p_id': id, 'p_data': {'name': r['name'], 'is_active': r['is_active'], 'branches': pick.toList()}}),
                      ok: tx(context, 'تَمّ.', 'Done.'));
                  if (ok != null) await _load();
                },
              ),
              TextButton.icon(onPressed: () => _new('branch', pointId: id), icon: const Icon(Icons.add, size: 18), label: Text(tx(context, 'فَرع جَديد', 'New branch'))),
            ],
          ],
          child: brs.isEmpty
              ? Text(tx(context, 'لا فُروع مَربوطة — العُمَلاء لا يَظهَرون في التَطبيق.', 'No branches linked — no clients show in the app.'), style: const TextStyle(color: VC.warn))
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final b in brs)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(netIcon('branch'), color: netColor('branch')),
                      title: Text(vStr(n.branch[b]?['name'])),
                      subtitle: Text([n.clientName(n.branch[b]?['client_id']), n.typeName(context, n.branch[b]?['type_id']),
                        if (vStr(n.link['$id|$b']?['unit']).isNotEmpty) tx(context, 'وِحدة ${n.link['$id|$b']!['unit']}', 'Unit ${n.link['$id|$b']!['unit']}')]
                          .where((e) => e.isNotEmpty)
                          .join(' · ')),
                      trailing: n.link['$id|$b']?['sync'] == 'error' ? const Icon(Icons.error_outline, color: VC.bad, size: 18) : null,
                      onTap: () => _select('branch', b, wide: true),
                    ),
                ]),
        ));
      case 'client':
        final brs = n.branchesOfClient[id] ?? const <VJson>[];
        final pts = {for (final b in brs) ...(n.pointsOfBranch[vStr(b['id'])] ?? const <String>[])};
        facts.addAll([
          ('TRN', vStr(r['vat'])),
          (tx(context, 'الرُخصة', 'License'), vStr(r['trade_license'])),
          (tx(context, 'النَوع', 'Type'), n.typeName(context, r['type_id'])),
          (tx(context, 'مُلاحَظات', 'Notes'), vStr(r['notes'])),
        ]);
        relations.add(VPanel(
          title: tx(context, 'الفُروع (${brs.length})', 'Branches (${brs.length})'),
          actions: [
            if (_canClients) ...[
              TextButton.icon(onPressed: () => _new('branch', clientId: id), icon: const Icon(Icons.add, size: 18), label: Text(tx(context, 'فَرع', 'Branch'))),
              TextButton.icon(onPressed: () => _new('setup', clientId: id), icon: const Icon(Icons.auto_awesome_outlined, size: 18), label: Text(tx(context, 'إعداد كامِل', 'Full setup'))),
            ],
          ],
          child: brs.isEmpty
              ? Text(tx(context, 'لا فُروع بَعد.', 'No branches yet.'), style: const TextStyle(color: VC.muted))
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final b in brs)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(netIcon('branch'), color: vBool(b['is_active']) ? netColor('branch') : VC.muted),
                      title: Text(vStr(b['name'])),
                      subtitle: Text((n.pointsOfBranch[vStr(b['id'])] ?? const []).isEmpty
                          ? tx(context, 'غَير مَربوط بِنُقطة', 'Not linked to a point')
                          : (n.pointsOfBranch[vStr(b['id'])] ?? const []).map((p) => n.pointLabel(p)).join('  ·  ')),
                      onTap: () => _select('branch', vStr(b['id']), wide: true),
                    ),
                ]),
        ));
        if (pts.isNotEmpty) {
          relations.add(const SizedBox(height: 12));
          relations.add(VPanel(
            title: tx(context, 'يُخدَم في ${pts.length} نُقطة', 'Served at ${pts.length} points'),
            child: Wrap(spacing: 6, runSpacing: 6, children: [for (final p in pts) chip('point', p, n.pointLabel(p), sub: n.areaName(n.point[p]?['area_id']))]),
          ));
        }
      case 'branch':
        final pts = n.pointsOfBranch[id] ?? const <String>[];
        facts.addAll([
          (tx(context, 'النَوع', 'Type'), n.typeName(context, r['type_id'])),
          ('TRN', vStr(r['vat'])),
          (tx(context, 'الهاتِف', 'Phone'), vStr(r['phone'])),
          (tx(context, 'البَريد', 'Email'), vStr(r['email'])),
          (tx(context, 'المَسؤول', 'Contact'), [vStr(r['contact_name']), vStr(r['contact_phone'])].where((e) => e.isNotEmpty).join(' · ')),
          (tx(context, 'العُنوان', 'Address'), vStr(r['address'])),
        ]);
        extra.add(OutlinedButton.icon(
          icon: const Icon(Icons.handshake_outlined, size: 18),
          label: Text(tx(context, 'تَطبيق العُمَلاء (الأَسعار وَالحِساب)', 'Customer app (prices & account)')),
          onPressed: () async {
            await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ValetClientDetailScreen(siteId: id, masters: [for (final c in n.clients) {'id': c['id'], 'name': c['name']}])));
            await _load();
          },
        ));
        relations.add(VPanel(
          title: tx(context, 'العَميل', 'Client'),
          child: Align(alignment: AlignmentDirectional.centerStart, child: chip('client', vStr(r['client_id']), n.clientName(r['client_id']), sub: vStr(n.client[vStr(r['client_id'])]?['vat']))),
        ));
        relations.add(const SizedBox(height: 12));
        relations.add(VPanel(
          title: tx(context, 'النِقاط (${pts.length})', 'Points (${pts.length})'),
          actions: [
            if (_canClients)
              TextButton.icon(
                icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                label: Text(tx(context, 'رَبط / تَعديل', 'Link / edit')),
                onPressed: () => _edit(s),
              ),
          ],
          child: pts.isEmpty
              ? Text(tx(context, 'غَير مَربوط — لا يَظهَر في تَطبيق الفاليه.', 'Not linked — it does not show in the valet app.'), style: const TextStyle(color: VC.warn))
              : Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final p in pts)
                    chip('point', p, n.pointLabel(p),
                        sub: [n.areaName(n.point[p]?['area_id']), vStr(n.link['$p|$id']?['unit']), vStr(n.link['$p|$id']?['floor'])].where((e) => e.isNotEmpty).join(' · ')),
                ]),
        ));
    }

    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(color: netColor(kind).withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
          child: Icon(netIcon(kind), color: netColor(kind)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 6, children: [
              VPill(netKindName(context, kind), color: netColor(kind), icon: netIcon(kind)),
              vBool(r['is_active']) ? VPill(tx(context, 'نَشِط', 'Active'), color: VC.ok) : VPill(tx(context, 'مُغلَق', 'Closed')),
              netSyncPill(context, r),
              if (kind == 'branch' && vStr(r['client_id']).isNotEmpty) VPill(n.clientName(r['client_id']), color: netColor('client'), icon: Icons.apartment),
            ]),
          ]),
        ),
      ]),
      if (r['sync'] == 'error') ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: VC.bad.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: VC.bad.withValues(alpha: 0.4))),
          child: Row(children: [
            const Icon(Icons.error_outline, color: VC.bad),
            const SizedBox(width: 8),
            Expanded(child: Text('Odoo: ${vStr(r['sync_error'])}', style: const TextStyle(color: VC.bad))),
            if (_canSettings) TextButton(onPressed: () => _retry(s), child: Text(tx(context, 'إعادة إرسال', 'Send again'))),
          ]),
        ),
      ],
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (edit) FilledButton.tonalIcon(onPressed: () => _edit(s), icon: const Icon(Icons.edit_outlined, size: 18), label: Text(tx(context, 'تَعديل', 'Edit'))),
        ...extra,
        OutlinedButton.icon(
          icon: const Icon(Icons.insights_outlined, size: 18),
          label: Text(tx(context, 'التَقارير', 'Reports')),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ValetReportsScreen(title: '${tx(context, 'تَقارير', 'Reports')} · $title', initialScope: VScope(kind, id, title)))),
        ),
        if (edit)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: VC.bad),
            onPressed: () => _delete(s),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: Text(tx(context, 'حَذف', 'Delete')),
          ),
      ]),
      const SizedBox(height: 14),
      _NetStats(key: ValueKey('$kind|$id|$_statsKey'), kind: kind, id: id),
      if (facts.any((f) => f.$2.isNotEmpty)) ...[
        const SizedBox(height: 12),
        VPanel(
          child: Column(children: [
            for (final f in facts.where((f) => f.$2.isNotEmpty))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 110, child: Text(f.$1, style: const TextStyle(color: VC.muted))),
                  Expanded(child: SelectableText(f.$2)),
                ]),
              ),
          ]),
        ),
      ],
      const SizedBox(height: 12),
      ...relations,
    ]);
  }
}

/// أَرقام السِجِلّ: إيراد اليَوم وَالشَهر، السَيّارات، الاستِخدام.
class _NetStats extends StatefulWidget {
  const _NetStats({super.key, required this.kind, required this.id});
  final String kind;
  final String id;

  @override
  State<_NetStats> createState() => _NetStatsState();
}

class _NetStatsState extends State<_NetStats> {
  VJson? _d;

  @override
  void initState() {
    super.initState();
    ValetAdmin.I.call('vva_network_stats', {'p_kind': widget.kind, 'p_id': widget.id}).then((d) {
      if (mounted) setState(() => _d = d);
    }).catchError((_) {
      if (mounted) setState(() => _d = const {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (d == null) return const SizedBox(height: 70, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    if (d.isEmpty) return const SizedBox();
    final u = vMap(d['usage']);
    return Wrap(spacing: 10, runSpacing: 10, children: [
      VKpi(tx(context, 'إيراد اليَوم', 'Revenue today'), VF.money(vNum(d['today_revenue'])), icon: Icons.payments_outlined, color: VC.ok,
          note: tx(context, '${VF.n(vNum(d['today_cars']))} سَيّارة', '${VF.n(vNum(d['today_cars']))} cars')),
      VKpi(tx(context, 'إيراد الشَهر', 'Revenue this month'), VF.money(vNum(d['month_revenue'])), icon: Icons.calendar_month_outlined, color: VC.info,
          note: tx(context, '${VF.n(vNum(d['month_cars']))} سَيّارة', '${VF.n(vNum(d['month_cars']))} cars')),
      if (widget.kind != 'area')
        VKpi(tx(context, 'كُلّ التَذاكِر', 'All tickets'), VF.n(vNum(u['tickets'])), icon: Icons.confirmation_number_outlined, color: VC.gold,
            note: d['last_ticket'] == null ? null : '${tx(context, 'آخِر', 'Last')} ${VF.date(DateTime.tryParse(vStr(d['last_ticket']))?.toLocal())}'),
      if (vNum(u['active']) > 0) VKpi(tx(context, 'سَيّارات الآن', 'Cars now'), VF.n(vNum(u['active'])), icon: Icons.directions_car_outlined, color: VC.warn),
      if (widget.kind == 'point') VKpi(tx(context, 'وَرديّات مَفتوحة', 'Open shifts'), VF.n(vNum(d['staff_on'])), icon: Icons.badge_outlined, color: VC.muted),
    ]);
  }
}
