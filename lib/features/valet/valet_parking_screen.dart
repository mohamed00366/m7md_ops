import 'package:flutter/material.dart';

import 'valet_admin.dart';
import 'valet_hub_ui.dart';
import 'valet_ui.dart';

/// 🅿️ المَواقِف — تُنشَأ مُستَقِلّة ثُمّ تُربَط بِنُقطة أَو أَكثَر (مَوقِف مُشتَرَك بَين عِدّة نِقاط).
class ValetParkingScreen extends StatelessWidget {
  const ValetParkingScreen({super.key});

  @override
  Widget build(BuildContext context) => const ValetGate(perm: ValetAdmin.permView, child: _ParkingBody());
}

class _ParkingBody extends StatefulWidget {
  const _ParkingBody();

  @override
  State<_ParkingBody> createState() => _ParkingBodyState();
}

class _ParkingBodyState extends State<_ParkingBody> {
  List<VJson>? _areas;
  Object? _err;
  String _q = '';

  bool get _edit => ValetAdmin.I.can(ValetAdmin.permSettings);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await ValetAdmin.I.call('vva_parking_areas');
      if (mounted) {
        setState(() {
          _areas = vList(d['areas']);
          _err = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _err = e);
    }
  }

  String _chip = 'all';
  static final _def = HubView('parking', mode: 'cards', fields: {'ring', 'points', 'actions'});
  HubView _view = _def;
  bool _viewLoaded = false;

  int _used(VJson a) => vNum(a['used']).toInt();
  int _cap(VJson a) => vNum(a['capacity']).toInt();
  double _fill(VJson a) => _cap(a) == 0 ? 0 : _used(a) / _cap(a);

  Future<void> _edit2(VJson a) async {
    final r = await showParkingAreaDialog(context, a);
    if (r != null) _load();
  }

  Future<void> _delete(VJson a) async {
    if (!await vConfirm(context, tx(context, 'حَذف المَوقِف', 'Delete area'), vStr(a['name']))) return;
    if (!mounted) return;
    final r = await vGuard(context, () => ValetAdmin.I.call('vva_parking_delete', {'p_id': a['id']}), ok: tx(context, 'تَمّ الحَذف.', 'Deleted.'));
    if (r != null && mounted) setState(() => _areas = vList(r['areas']));
  }

  @override
  Widget build(BuildContext context) {
    if (!_viewLoaded) {
      _viewLoaded = true;
      HubView.load(_def).then((v) {
        if (mounted) setState(() => _view = v);
      });
    }
    final all = _areas ?? const <VJson>[];
    final q = _q.toLowerCase();
    bool chipOk(VJson a) => switch (_chip) {
          'full' => _cap(a) > 0 && _fill(a) >= 0.9,
          'free' => vList(a['points']).isEmpty,
          'vip' => vBool(a['is_vip']),
          'off' => !vBool(a['approved']),
          _ => true,
        };
    final rows = _areas
        ?.where((a) =>
            chipOk(a) &&
            (q.isEmpty ||
                vStr(a['name']).toLowerCase().contains(q) ||
                vList(a['points']).any((p) => '${p['code']} ${p['name']}'.toLowerCase().contains(q))))
        .toList();
    final used = all.fold<int>(0, (s, a) => s + _used(a));
    final cap = all.fold<int>(0, (s, a) => s + _cap(a));
    return ListView(padding: const EdgeInsets.only(bottom: 28), children: [
      HubHead(
        title: tx(context, 'المَواقِف', 'Parking areas'),
        subtitle: tx(context, 'كُلّ المَواقِف: السَعة، المَشغول الآن، وَالنِقاط المَربوطة (السَعة مُشتَرَكة بَينها)', 'All areas: capacity, used now and linked points (capacity shared by them)'),
        actions: [
          HubSearch(hint: tx(context, 'بَحث بِالمَوقِف أَو النُقطة', 'Search area or point'), onChanged: (v) => setState(() => _q = v)),
          HubButton(icon: Icons.refresh, label: tx(context, 'تَحديث', 'Refresh'), onPressed: _load),
          HubButton(
            icon: Icons.tune_rounded,
            label: tx(context, 'العَرض', 'View'),
            onPressed: () async {
              final v = await showHubView(context, _view, _def, fields: [
                ('ring', tx(context, 'دايرة الامتِلاء', 'Fill ring')),
                ('points', tx(context, 'النِقاط المَربوطة', 'Linked points')),
                ('actions', tx(context, 'الأَزرار', 'Buttons')),
              ]);
              if (v != null && mounted) setState(() => _view = v);
            },
          ),
          if (_edit)
            HubButton(
              primary: true,
              icon: Icons.add,
              label: tx(context, 'مَوقِف جَديد', 'New area'),
              onPressed: () async {
                final r = await showParkingAreaDialog(context, null);
                if (r != null) _load();
              },
            ),
        ],
      ),
      HubKpis([
        HubKpi(Icons.garage_outlined, '${all.length}', tx(context, 'مَوقِف', 'Areas')),
        HubKpi(Icons.directions_car_filled_outlined, '$used', tx(context, 'سَيّارة الآن', 'Cars now')),
        HubKpi(Icons.pie_chart_outline, cap == 0 ? '—' : '${(used * 100 / cap).round()}%', tx(context, 'امتِلاء عامّ', 'Overall fill')),
        HubKpi(Icons.warning_amber_rounded, '${all.where((a) => _cap(a) > 0 && _fill(a) >= 0.9).length}', tx(context, 'فَوق 90%', 'Above 90%')),
        HubKpi(Icons.link_off, '${all.where((a) => vList(a['points']).isEmpty).length}', tx(context, 'غَير مَربوط', 'Not linked')),
      ]),
      HubChips(
        value: _chip,
        onChanged: (v) => setState(() => _chip = v),
        items: [
          ('all', tx(context, 'الكُلّ', 'All'), all.length),
          ('full', tx(context, 'شِبه مُمتَلِئ', 'Almost full'), all.where((a) => _cap(a) > 0 && _fill(a) >= 0.9).length),
          ('free', tx(context, 'غَير مَربوط', 'Not linked'), all.where((a) => vList(a['points']).isEmpty).length),
          ('vip', 'VIP', all.where((a) => vBool(a['is_vip'])).length),
          ('off', tx(context, 'مُتَوَقِّف', 'Off'), all.where((a) => !vBool(a['approved'])).length),
        ],
      ),
      if (_err != null) Padding(padding: const EdgeInsets.all(16), child: Text(vErr(context, _err!), style: const TextStyle(color: VC.bad))),
      if (rows == null && _err == null) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
      if (rows != null && rows.isEmpty) Padding(padding: const EdgeInsets.all(40), child: Center(child: Text(tx(context, 'لا تُوجَد مَواقِف.', 'No parking area.'), style: const TextStyle(color: VC.muted)))),
      if (rows != null && rows.isNotEmpty)
        if (_view.mode == 'cards') HubGrid(view: _view, children: [for (final a in rows) _card(a)]) else _table(rows),
    ]);
  }

  Widget _card(VJson a) {
    final f = _fill(a);
    final full = _cap(a) > 0 && f >= 0.9;
    final pts = vList(a['points']);
    return HubCard(
      onTap: _edit ? () => _edit2(a) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(vStr(a['name']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5))),
                if (vBool(a['is_vip'])) ...[const SizedBox(width: 6), hubPill('VIP', kind: 'dark')],
              ]),
              if (vStr(a['notes']).isNotEmpty) Text(vStr(a['notes']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: VC.muted, fontSize: 12)),
            ]),
          ),
          !vBool(a['approved'])
              ? hubPill(tx(context, 'مُتَوَقِّف', 'Off'), kind: 'bad')
              : pts.isEmpty
                  ? hubPill(tx(context, 'غَير مَربوط', 'Not linked'))
                  : full
                      ? hubPill(tx(context, 'شِبه مُمتَلِئ', 'Almost full'), kind: 'warn')
                      : hubPill(tx(context, 'مُستَخدَم', 'In use'), kind: 'ok'),
        ]),
        if (_view.show('ring')) ...[
          const SizedBox(height: 12),
          Row(children: [
            SizedBox(
              width: 70,
              height: 70,
              child: Stack(alignment: Alignment.center, children: [
                SizedBox(
                  width: 70,
                  height: 70,
                  child: CircularProgressIndicator(
                      value: _cap(a) == 0 ? 0 : f.clamp(0, 1).toDouble(), strokeWidth: 7, backgroundColor: const Color(0xFFE2E8F0), color: full ? VC.bad : const Color(0xFF0B0C0E)),
                ),
                Text(_cap(a) == 0 ? '∞' : '${(f * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              ]),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text.rich(TextSpan(children: [
                  TextSpan(text: '${_used(a)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  TextSpan(text: ' / ${_cap(a) == 0 ? '∞' : _cap(a)}', style: const TextStyle(fontSize: 14, color: VC.muted, fontWeight: FontWeight.w700)),
                ])),
                Text(
                    _cap(a) == 0
                        ? tx(context, 'مَشغول · بِدون حَدّ', 'Used · no limit')
                        : tx(context, 'مَشغول / السَعة · فاضي ${_cap(a) - _used(a)}', 'Used / capacity · ${_cap(a) - _used(a)} free'),
                    style: const TextStyle(color: VC.muted, fontSize: 12)),
              ]),
            ),
          ]),
        ],
        if (_view.show('points')) ...[
          const SizedBox(height: 11),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final p in pts) hubTag(vStr(p['name']), icon: Icons.link),
            if (pts.isEmpty) hubTag(tx(context, 'غَير مَربوط بِنُقطة', 'Not linked to a point'), missing: true),
          ]),
        ],
        if (_view.show('actions') && _edit) ...[
          const SizedBox(height: 11),
          Row(children: [
            hubAction(tx(context, 'تَعديل وَرَبط', 'Edit & link'), () => _edit2(a)),
            const Spacer(),
            hubAction(tx(context, 'حَذف', 'Delete'), () => _delete(a), color: VC.bad),
          ]),
        ],
      ]),
    );
  }

  Widget _table(List<VJson> rows) {
    return         Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: VPanel(
            child: VTable(
              empty: tx(context, 'لا تُوجَد مَواقِف.', 'No parking area.'),
              columns: [
                DataColumn(label: Text(tx(context, 'المَوقِف', 'Area'))),
                DataColumn(label: Text(tx(context, 'مَشغول / السَعة', 'Used / capacity')), numeric: true),
                DataColumn(label: Text(tx(context, 'النِقاط المَربوطة', 'Linked points'))),
                DataColumn(label: Text(tx(context, 'الحالة', 'Status'))),
                const DataColumn(label: Text('')),
              ],
              rows: [
                for (final a in rows)
                  DataRow(cells: [
                    DataCell(Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(vStr(a['name']), style: const TextStyle(fontWeight: FontWeight.w600)),
                        if (vBool(a['is_vip'])) ...[const SizedBox(width: 6), const VPill('VIP', color: VC.gold, icon: Icons.workspace_premium_outlined)],
                      ]),
                      if (vStr(a['notes']).isNotEmpty) Text(vStr(a['notes']), style: const TextStyle(color: VC.muted, fontSize: 12)),
                    ])),
                    DataCell(Text(
                      '${vNum(a['used']).toInt()} / ${vNum(a['capacity']).toInt() == 0 ? '∞' : vNum(a['capacity']).toInt()}',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: vNum(a['capacity']) > 0 && vNum(a['used']) >= vNum(a['capacity']) ? VC.bad : null),
                    )),
                    DataCell(SizedBox(
                      width: 420,
                      child: Wrap(spacing: 4, runSpacing: 4, children: [
                        for (final p in vList(a['points'])) VPill('${p['name']}', icon: Icons.place_outlined),
                        if (vList(a['points']).isEmpty) VPill(tx(context, 'غَير مَربوط', 'Not linked'), color: VC.warn),
                      ]),
                    )),
                    DataCell(vBool(a['approved']) ? VPill(tx(context, 'مُستَخدَم', 'In use'), color: VC.ok) : VPill(tx(context, 'مُتَوَقِّف', 'Off'))),
                    DataCell(!_edit
                        ? const SizedBox()
                        : Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(
                              tooltip: tx(context, 'تَعديل وَرَبط', 'Edit & link'),
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () async {
                                final r = await showParkingAreaDialog(context, a);
                                if (r != null) _load();
                              },
                            ),
                            IconButton(
                              tooltip: tx(context, 'حَذف', 'Delete'),
                              icon: const Icon(Icons.delete_outline, color: VC.bad),
                              onPressed: () => _delete(a),
                            ),
                          ])),
                  ]),
              ],
            ),
          ),
        );
  }
}

/// Creates / edits a parking area and its linked points. [withPoint] pre-links a new area to that point.
/// Returns the server answer (areas list + id) or null when cancelled.
Future<VJson?> showParkingAreaDialog(BuildContext context, VJson? area, {String? withPoint}) async {
  final points = await vGuard(context, VPoints.get);
  if (points == null || !context.mounted) return null;
  final name = TextEditingController(text: vStr(area?['name']));
  final capacity = TextEditingController(text: area == null ? '' : vNum(area['capacity']).toInt().toString());
  final notes = TextEditingController(text: vStr(area?['notes']));
  bool approved = area == null ? true : vBool(area['approved']);
  bool vip = area != null && vBool(area['is_vip']);
  final linked = <String>{
    for (final p in vList(area?['points'])) vStr(p['id']),
    if (withPoint != null) withPoint,
  };
  String q = '';
  return showDialog<VJson>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      final shown = points.where((p) => '${p['code']} ${p['name']}'.toLowerCase().contains(q.toLowerCase())).toList()
        ..sort((a, b) {
          final la = linked.contains(vStr(a['id'])) ? 0 : 1, lb = linked.contains(vStr(b['id'])) ? 0 : 1;
          return la != lb ? la - lb : vStr(a['code']).compareTo(vStr(b['code']));
        });
      return AlertDialog(
        title: Text(area == null ? tx(ctx, 'مَوقِف جَديد', 'New parking area') : tx(ctx, 'تَعديل المَوقِف', 'Edit parking area')),
        content: SizedBox(
          width: 520,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: name, decoration: InputDecoration(labelText: tx(ctx, 'اسم المَوقِف *', 'Area name *'), hintText: 'Basement B2')),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: capacity,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: tx(ctx, 'السَعة (سَيّارات)', 'Capacity (cars)'), helperText: tx(ctx, '0 = بِلا حَدّ', '0 = no limit')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tx(ctx, 'مُستَخدَم', 'In use')),
                  value: approved,
                  onChanged: (v) => set(() => approved = v),
                ),
              ),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.workspace_premium_outlined, color: VC.gold),
              title: Text(tx(ctx, 'باركِنج VIP', 'VIP parking')),
              subtitle: Text(tx(ctx, 'سَيّارات VIP تُصَفّ هُنا فَقَط (لَو مَوقِف واحِد يُختار تِلقائيّاً)، وَالمُشتَرِكون وَالعادي لا يَرَونه.',
                  'VIP cars are parked only here (one area = chosen by itself); members and normal tickets never see it.')),
              value: vip,
              onChanged: (v) => set(() => vip = v),
            ),
            const SizedBox(height: 6),
            TextField(controller: notes, decoration: InputDecoration(labelText: tx(ctx, 'مُلاحَظات / العُنوان', 'Notes / address'))),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: Text(tx(ctx, 'النِقاط التي تَستَخدِم هذا المَوقِف (${linked.length})', 'Points using this area (${linked.length})'),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              SizedBox(
                width: 180,
                child: TextField(
                  decoration: InputDecoration(isDense: true, prefixIcon: const Icon(Icons.search, size: 18), hintText: tx(ctx, 'بَحث', 'Search')),
                  onChanged: (v) => set(() => q = v),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView(shrinkWrap: true, children: [
                for (final p in shown)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: linked.contains(vStr(p['id'])),
                    title: Text('${p['code']} · ${p['name']}'),
                    onChanged: (v) => set(() => v == true ? linked.add(vStr(p['id'])) : linked.remove(vStr(p['id']))),
                  ),
              ]),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tx(ctx, 'إلغاء', 'Cancel'))),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty) {
                vToast(ctx, tx(ctx, 'أَدخِل اسم المَوقِف.', 'Enter the area name.'), error: true);
                return;
              }
              final r = await vGuard(
                ctx,
                () => ValetAdmin.I.call('vva_parking_save', {
                  'p_data': {
                    if (area != null) 'id': area['id'],
                    'name': name.text.trim(),
                    'capacity': int.tryParse(capacity.text.trim()) ?? 0,
                    'approved': approved,
                    'is_vip': vip,
                    'notes': notes.text.trim(),
                    'point_ids': linked.toList(),
                  },
                }),
                ok: tx(ctx, 'تَمّ الحِفظ.', 'Saved.'),
              );
              if (r != null && ctx.mounted) Navigator.pop(ctx, r);
            },
            child: Text(tx(ctx, 'حِفظ', 'Save')),
          ),
        ],
      );
    }),
  );
}
