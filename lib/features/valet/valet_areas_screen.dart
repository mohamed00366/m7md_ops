import 'package:flutter/material.dart';

import 'valet_admin.dart';
import 'valet_ui.dart';

/// 🗺 مَناطِق الفاليه — كُلّ نُقطة في مَنطِقة واحِدة. تُنشَأ هُنا أَو في Odoo (Valet ▸ Areas) وَتُزامَن في الاتِّجاهَين.
class ValetAreasScreen extends StatelessWidget {
  const ValetAreasScreen({super.key});

  @override
  Widget build(BuildContext context) => ValetGate(
        child: VLoader<VJson>(
          load: () => ValetAdmin.I.call('vva_areas'),
          builder: (context, d, reload) {
            final areas = vList(d['areas']);
            final free = vList(d['unassigned']);
            final edit = ValetAdmin.I.can(ValetAdmin.permSettings);
            final allPoints = [
              for (final a in areas)
                for (final p in vList(a['points'])) {...p, 'area': a['name'], 'area_id': a['id']},
              ...free,
            ];
            return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
              VHead(tx(context, 'المَناطِق', 'Areas'),
                  subtitle: tx(context, 'كُلّ نُقطة في مَنطِقة واحِدة · تُزامَن مَع Odoo في الاتِّجاهَين خِلال دَقائِق',
                      'One area per point · synced with Odoo both ways within minutes'),
                  actions: [
                    IconButton.filledTonal(onPressed: reload, icon: const Icon(Icons.refresh)),
                    if (edit)
                      FilledButton.icon(
                        onPressed: () async {
                          if (await _edit(context, null, allPoints) == true) reload();
                        },
                        icon: const Icon(Icons.add),
                        label: Text(tx(context, 'مَنطِقة جَديدة', 'New area')),
                      ),
                  ]),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(spacing: 10, runSpacing: 10, children: [
                  VKpi(tx(context, 'مَناطِق', 'Areas'), VF.n(areas.length), icon: Icons.map_outlined, color: VC.info),
                  VKpi(tx(context, 'نِقاط في مَناطِق', 'Points in areas'), VF.n(allPoints.length - free.length), icon: Icons.place, color: VC.ok),
                  VKpi(tx(context, 'نِقاط بِلا مَنطِقة', 'Points without an area'), VF.n(free.length), icon: Icons.location_off_outlined,
                      color: free.isNotEmpty ? VC.warn : null),
                ]),
              ),
              if (areas.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(tx(context, 'لا تُوجَد مَناطِق بَعد. أَضِف أَوَّل مَنطِقة وَاختَر نِقاطها.', 'No areas yet. Add the first area and choose its points.'),
                      style: const TextStyle(color: VC.muted)),
                ),
              for (final a in areas)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: VPanel(
                    title: '${vStr(a['name'])}${vStr(a['code']).isEmpty ? '' : '  ·  ${vStr(a['code'])}'}',
                    actions: [
                      if (vBool(a['pending']))
                        VPill(tx(context, 'يُرسَل لـ Odoo', 'Sending to Odoo'), color: VC.warn, icon: Icons.sync)
                      else if (a['odoo_id'] != null)
                        const VPill('Odoo', color: VC.ok, icon: Icons.check),
                      if (!vBool(a['is_active'])) ...[const SizedBox(width: 6), VPill(tx(context, 'مُغلَقة', 'Closed'), color: VC.muted)],
                      if (edit) ...[
                        IconButton(
                          tooltip: tx(context, 'تَعديل', 'Edit'),
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () async {
                            if (await _edit(context, a, allPoints) == true) reload();
                          },
                        ),
                        IconButton(
                          tooltip: tx(context, 'حَذف', 'Delete'),
                          icon: const Icon(Icons.delete_outline, color: VC.bad),
                          onPressed: () async {
                            final ok = await vConfirm(context, tx(context, 'حَذف المَنطِقة؟', 'Delete the area?'),
                                tx(context, 'نِقاطها تَبقى بِلا مَنطِقة، وَتُحذَف مِن Odoo أَيضاً.', 'Its points stay without an area; it is deleted in Odoo too.'),
                                button: tx(context, 'حَذف', 'Delete'));
                            if (!ok || !context.mounted) return;
                            final r = await vGuard(context, () => ValetAdmin.I.call('vva_area_delete', {'p_id': a['id']}), ok: tx(context, 'تَمّ الحَذف.', 'Deleted.'));
                            if (r != null) reload();
                          },
                        ),
                      ],
                    ],
                    child: vList(a['points']).isEmpty
                        ? Text(tx(context, 'لا تُوجَد نِقاط في هذه المَنطِقة.', 'No points in this area.'), style: const TextStyle(color: VC.muted))
                        : Wrap(spacing: 8, runSpacing: 8, children: [
                            for (final p in vList(a['points']))
                              Chip(
                                avatar: Icon(Icons.place, size: 16, color: vBool(p['is_active']) ? VC.ok : VC.muted),
                                label: Text('${vStr(p['code'])}  ${vStr(p['name'])}  ·  ${tx(context, '${vStr(p['clients'])} فَرع', '${vStr(p['clients'])} branches')}'),
                              ),
                          ]),
                  ),
                ),
              if (free.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: VPanel(
                    title: tx(context, 'نِقاط بِلا مَنطِقة (${free.length})', 'Points without an area (${free.length})'),
                    child: Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final p in free) Chip(avatar: const Icon(Icons.location_off_outlined, size: 16, color: VC.warn), label: Text('${vStr(p['code'])}  ${vStr(p['name'])}')),
                    ]),
                  ),
                ),
            ]);
          },
        ),
      );

  /// إضافة / تَعديل مَنطِقة مَع اختيار نِقاطها (النُقطة المُختارة تَنتَقِل مِن مَنطِقتها السابِقة).
  Future<bool?> _edit(BuildContext context, VJson? area, List<VJson> points) {
    final name = TextEditingController(text: vStr(area?['name']));
    final code = TextEditingController(text: vStr(area?['code']));
    final search = TextEditingController();
    var active = area == null ? true : vBool(area['is_active']);
    final sel = <String>{for (final p in vList(area?['points'])) vStr(p['id'])};
    return showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final q = search.text.trim().toLowerCase();
        final list = points.where((p) => q.isEmpty || '${p['code']} ${p['name']} ${p['area'] ?? ''}'.toLowerCase().contains(q)).toList()
          ..sort((a, b) {
            final sa = sel.contains(vStr(a['id'])) ? 0 : 1, sb = sel.contains(vStr(b['id'])) ? 0 : 1;
            return sa != sb ? sa - sb : vStr(a['code']).compareTo(vStr(b['code']));
          });
        return AlertDialog(
          title: Text(area == null ? tx(ctx, 'مَنطِقة جَديدة', 'New area') : tx(ctx, 'تَعديل المَنطِقة', 'Edit area')),
          content: SizedBox(
            width: 520,
            height: 560,
            child: Column(children: [
              Row(children: [
                Expanded(flex: 3, child: TextField(controller: name, decoration: InputDecoration(labelText: tx(ctx, 'اسم المَنطِقة', 'Area name'), hintText: 'Dubai Hills'))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: code, decoration: InputDecoration(labelText: tx(ctx, 'الكود', 'Code')))),
              ]),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: active,
                title: Text(tx(ctx, 'مَفتوحة', 'Open')),
                onChanged: (v) => set(() => active = v),
              ),
              TextField(
                controller: search,
                decoration: InputDecoration(isDense: true, prefixIcon: const Icon(Icons.search), hintText: tx(ctx, 'ابحَث عَن نُقطة', 'Search a point')),
                onChanged: (_) => set(() {}),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(tx(ctx, 'نِقاط هذه المَنطِقة (${sel.length}) — النُقطة تَكون في مَنطِقة واحِدة', 'Points of this area (${sel.length}) — a point is in one area'),
                    style: const TextStyle(color: VC.muted, fontSize: 12)),
              ),
              Expanded(
                child: ListView(children: [
                  for (final p in list)
                    CheckboxListTile(
                      dense: true,
                      value: sel.contains(vStr(p['id'])),
                      title: Text('${vStr(p['code'])}  ${vStr(p['name'])}'),
                      subtitle: p['area'] == null || p['area_id'] == area?['id']
                          ? null
                          : Text(tx(ctx, 'الآن في: ${vStr(p['area'])}', 'Now in: ${vStr(p['area'])}'), style: const TextStyle(color: VC.warn, fontSize: 12)),
                      onChanged: (v) => set(() => v == true ? sel.add(vStr(p['id'])) : sel.remove(vStr(p['id']))),
                    ),
                ]),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tx(ctx, 'إلغاء', 'Cancel'))),
            FilledButton(
              onPressed: () async {
                final r = await vGuard(ctx, () => ValetAdmin.I.call('vva_area_save', {
                      'p_id': area?['id'],
                      'p_name': name.text.trim(),
                      'p_code': code.text.trim(),
                      'p_active': active,
                      'p_points': sel.toList(),
                    }), ok: tx(ctx, 'تَمّ الحِفظ — يُرسَل لـ Odoo خِلال دَقيقَتَين.', 'Saved — sent to Odoo within two minutes.'));
                if (r != null && ctx.mounted) Navigator.pop(ctx, true);
              },
              child: Text(tx(ctx, 'حِفظ', 'Save')),
            ),
          ],
        );
      }),
    );
  }
}
