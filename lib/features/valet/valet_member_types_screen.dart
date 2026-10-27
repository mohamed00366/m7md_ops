import 'package:flutter/material.dart';

import 'valet_admin.dart';
import 'valet_member_cards_panel.dart';
import 'valet_network_data.dart';
import 'valet_ui.dart';

/// 🎫 أَنواع الاشتِراكات — يُنشِئها المَكتَب: الاسم وَالسِعر (أَو مَجّانيّ) وَأَين يَصلُح:
/// نُقطة واحِدة · نِقاط مُحَدَّدة · مَنطِقة كامِلة · كُلّ المَواقِع. التَطبيق يَبيع الأَنواع الَّتي تُغَطّي نُقطَته.
class ValetMemberTypesScreen extends StatelessWidget {
  const ValetMemberTypesScreen({super.key});

  @override
  Widget build(BuildContext context) => const ValetGate(child: _Body());
}

class _Body extends StatefulWidget {
  const _Body();

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  Net? _net;
  List<VJson> _countries = const [];

  Future<VJson> _load() async {
    final r = await Future.wait([ValetAdmin.I.call('vva_member_types'), if (_net == null) ValetAdmin.I.call('vva_network')]);
    if (r.length > 1) _net = Net(r[1]);
    _countries = vList(r[0]['countries']);
    return r[0];
  }

  static const _vat = 0.05;

  @override
  Widget build(BuildContext context) {
    final edit = ValetAdmin.I.can(ValetAdmin.permSettings);
    return VLoader<VJson>(
      load: _load,
      builder: (context, d, reload) {
        final types = vList(d['types']);
        final active = types.where((t) => vBool(t['is_active'])).toList();
        final members = types.fold<num>(0, (a, t) => a + vNum(t['active_members']));
        return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
          VHead(
            tx(context, 'أَنواع الاشتِراكات', 'Membership types'),
            subtitle: tx(context, 'نُقطة: مَدفوع وَيُباع في التَطبيق وَهُنا · عِدّة نِقاط / مَنطِقة / دَولة / كُلّ الدُوَل: مَدفوع أَو مَجّانيّ وَمِن هُنا فَقَط · المُشتَرِك مَجّانيّ في كُلّ مَواقِع نَوعه',
                'One point: paid, sold in the app and here · several points / area / country / all countries: paid or free, from here only · a member parks free at every point of the type'),
            actions: [
              IconButton.filledTonal(onPressed: reload, icon: const Icon(Icons.refresh)),
              if (edit)
                FilledButton.icon(
                  onPressed: () async {
                    if (await _form(context, null) == true) reload();
                  },
                  icon: const Icon(Icons.add),
                  label: Text(tx(context, 'نَوع جَديد', 'New type')),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(spacing: 10, runSpacing: 10, children: [
              VKpi(tx(context, 'أَنواع فَعّالة', 'Active types'), VF.n(active.length), icon: Icons.style_outlined, color: VC.gold),
              VKpi(tx(context, 'مُشتَرِكون فَعّالون', 'Active members'), VF.n(members), icon: Icons.card_membership, color: VC.ok),
              VKpi(tx(context, 'مَجّانيّة', 'Free types'), VF.n(active.where((t) => vNum(t['price']) == 0).length), icon: Icons.card_giftcard, color: VC.info),
            ]),
          ),
          const SizedBox(height: 12),
          if (types.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(tx(context, 'لا تُوجَد أَنواع بَعد. أَضِف أَوَّل نَوع.', 'No types yet. Add the first one.'), style: const TextStyle(color: VC.muted)),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LayoutBuilder(builder: (context, c) {
              final cols = c.maxWidth > 1100 ? 3 : (c.maxWidth > 700 ? 2 : 1);
              final w = (c.maxWidth - (cols - 1) * 12) / cols;
              return Wrap(spacing: 12, runSpacing: 12, children: [
                for (final t in types) SizedBox(width: w, child: _card(context, t, edit, reload)),
              ]);
            }),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            // the raw maps from the server, so a saved switch survives a rebuild of the page
            child: _PointSwitches(points: [for (final e in (d['points'] is List ? d['points'] as List : const [])) if (e is Map) e.cast<String, dynamic>()], edit: edit),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: MemberCardsPanel(edit: edit),
          ),
        ]);
      },
    );
  }

  Widget _card(BuildContext context, VJson t, bool edit, Future<void> Function() reload) {
    final free = vNum(t['price']) == 0;
    final gross = vNum(t['price']) * (1 + _vat);
    final on = vBool(t['is_active']);
    final cov = vStr(t['coverage']);
    final icon = switch (cov) {
      'global' || 'all' => Icons.public,
      'country' => Icons.flag_outlined,
      'area' => Icons.map_outlined,
      'points' => Icons.scatter_plot_outlined,
      _ => Icons.place_outlined
    };
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: on ? VC.gold.withValues(alpha: 0.6) : VC.muted.withValues(alpha: 0.3))),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(vStr(t['name']), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
            if (!on) VPill(tx(context, 'مُتَوَقِّف', 'Off')),
            if (!vBool(t['sell_in_app'])) ...[const SizedBox(width: 6), VPill(tx(context, 'المَكتَب فَقَط', 'Office only'), color: VC.info, icon: Icons.business)],
          ]),
          const SizedBox(height: 6),
          Text(free ? tx(context, 'مَجّانيّ', 'FREE') : '${VF.money(gross)} AED / ${tx(context, 'شَهر', 'month')}',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: free ? VC.info : VC.gold)),
          if (!free) Text(tx(context, 'شامِل الضَريبة · ${VF.money(vNum(t['price']))} بِدون ضَريبة', 'VAT included · ${VF.money(vNum(t['price']))} before VAT'), style: const TextStyle(color: VC.muted, fontSize: 12)),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            VPill(vStr(t['label']), color: VC.info, icon: icon),
            VPill(tx(context, '${t['points_count']} نُقطة', '${t['points_count']} points'), icon: Icons.place_outlined),
            VPill(tx(context, '${t['max_cars']} سَيّارة', '${t['max_cars']} cars'), icon: Icons.directions_car_outlined),
            VPill(((t['durations'] as List?) ?? const []).map((m) => vNum(m) % 12 == 0 ? '${vNum(m) ~/ 12}y' : '${m}m').join(' · '), icon: Icons.date_range_outlined),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Text(tx(context, '${t['active_members']} فَعّال · ${t['members']} إجماليّ', '${t['active_members']} active · ${t['members']} total'), style: const TextStyle(color: VC.muted)),
            const Spacer(),
            TextButton.icon(
              icon: const Icon(Icons.people_outline, size: 18),
              label: Text(tx(context, 'المُشتَرِكون', 'Members')),
              onPressed: () => _members(context, t),
            ),
            if (edit) ...[
              IconButton(
                tooltip: tx(context, 'تَعديل', 'Edit'),
                icon: const Icon(Icons.edit_outlined),
                onPressed: () async {
                  if (await _form(context, t) == true) reload();
                },
              ),
              IconButton(
                tooltip: tx(context, 'حَذف', 'Delete'),
                icon: const Icon(Icons.delete_outline, color: VC.bad),
                onPressed: () async {
                  final n = vNum(t['members']);
                  final ok = await vConfirm(
                      context,
                      n > 0 ? tx(context, 'إيقاف النَوع؟', 'Turn the type off?') : tx(context, 'حَذف النَوع؟', 'Delete the type?'),
                      n > 0
                          ? tx(context, 'لَه $n مُشتَرِك: لا يُحذَف، يَتَوَقَّف بَيعه وَيَبقى المُشتَرِكون حَتّى نِهاية اشتِراكهم.', 'It has $n members: it is not deleted; it stops being sold and members keep it until their end date.')
                          : tx(context, 'يُحذَف نِهائيّاً.', 'It is deleted for good.'),
                      button: n > 0 ? tx(context, 'إيقاف', 'Turn off') : tx(context, 'حَذف', 'Delete'));
                  if (!ok || !context.mounted) return;
                  final r = await vGuard(context, () => ValetAdmin.I.call('vva_member_type_delete', {'p_id': t['id']}), ok: tx(context, 'تَمّ.', 'Done.'));
                  if (r != null) reload();
                },
              ),
            ],
          ]),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------------- form
  Future<bool?> _form(BuildContext context, VJson? t) {
    final n = _net!;
    final name = TextEditingController(text: vStr(t?['name']));
    final price = TextEditingController(text: t == null ? '' : (vNum(t['price']) * (1 + _vat)).toStringAsFixed(2));
    var free = t != null && vNum(t['price']) == 0;
    var cov = vStr(t?['coverage']).isEmpty ? 'point' : vStr(t!['coverage']);
    if (cov == 'all') cov = 'global';
    String? country = t?['country_id'] == null ? (_countries.length == 1 ? vStr(_countries.first['id']) : null) : vStr(t!['country_id']);
    var points = {for (final p in (t?['point_ids'] as List? ?? const [])) '$p'};
    var areas = {for (final a in (t?['area_ids'] as List? ?? const [])) '$a'};
    String? site = t?['site_id'] == null ? null : vStr(t!['site_id']);
    var cars = t == null ? 2 : vNum(t['max_cars']).toInt();
    var durations = {for (final m in (t?['durations'] as List? ?? const [1, 3, 6, 12])) vNum(m).toInt()};
    var active = t == null || vBool(t['is_active']);
    var busy = false;
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        Widget sec(String s) => Padding(padding: const EdgeInsets.only(top: 14, bottom: 6), child: Text(s, style: const TextStyle(fontWeight: FontWeight.w800)));
        return AlertDialog(
          title: Row(children: [
            const Icon(Icons.style_outlined),
            const SizedBox(width: 8),
            Text(t == null ? tx(ctx, 'نَوع اشتِراك جَديد', 'New membership type') : tx(ctx, 'تَعديل النَوع', 'Edit type')),
          ]),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: name,
                    autofocus: t == null,
                    decoration: InputDecoration(labelText: tx(ctx, 'الاسم *', 'Name *'), hintText: 'Downtown Monthly · Gold All Sites · Owner Free', isDense: true)),
                sec(tx(ctx, 'السِعر', 'Price')),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: price,
                      enabled: !free,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: tx(ctx, 'سِعر الشَهر شامِل الضَريبة (AED)', 'Monthly price incl. VAT (AED)'), isDense: true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilterChip(
                    selected: free,
                    avatar: const Icon(Icons.card_giftcard, size: 18),
                    label: Text(tx(ctx, 'مَجّانيّ', 'Free')),
                    // one point = sold in the app = always paid
                    onSelected: cov == 'point' ? null : (v) => set(() => free = v),
                  ),
                ]),
                sec(tx(ctx, 'أَين يَصلُح', 'Where it is valid')),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: 'point', icon: const Icon(Icons.place_outlined), label: Text(tx(ctx, 'نُقطة', 'One point'))),
                    ButtonSegment(value: 'points', icon: const Icon(Icons.scatter_plot_outlined), label: Text(tx(ctx, 'نِقاط', 'Points'))),
                    ButtonSegment(value: 'area', icon: const Icon(Icons.map_outlined), label: Text(tx(ctx, 'مَنطِقة', 'Area'))),
                    ButtonSegment(value: 'country', icon: const Icon(Icons.flag_outlined), label: Text(tx(ctx, 'دَولة', 'Country'))),
                    ButtonSegment(value: 'global', icon: const Icon(Icons.public), label: Text(tx(ctx, 'كُلّ الدُوَل', 'All countries'))),
                  ],
                  selected: {cov},
                  onSelectionChanged: (v) => set(() {
                    cov = v.first;
                    if (cov == 'point') free = false;
                  }),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: (cov == 'point' ? VC.gold : VC.info).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [
                    Icon(cov == 'point' ? Icons.phone_android : Icons.business, size: 18, color: cov == 'point' ? VC.gold : VC.info),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        cov == 'point'
                            ? tx(ctx, 'يُباع وَيُجَدَّد في تَطبيق الفاليه وَمِن الداشبورد · بِسِعر دائِماً', 'Sold and renewed in the valet app and from the dashboard · always paid')
                            : tx(ctx, 'يُنشَأ وَيُجَدَّد مِن الداشبورد فَقَط · مَدفوع أَو مَجّانيّ · المُشتَرِك يُعرَف في كُلّ نِقاط النَوع', 'Created and renewed from the dashboard only · paid or free · the member is recognised at every point of the type'),
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 8),
                if (cov == 'point' || cov == 'points')
                  NetPickField(
                    label: cov == 'point' ? tx(ctx, 'النُقطة', 'Point') : tx(ctx, 'النِقاط (${points.length})', 'Points (${points.length})'),
                    icon: Icons.place_outlined,
                    value: points.map(n.pointLabel).join(' · '),
                    onTap: () async {
                      final r = await netPick(ctx, tx(ctx, 'النِقاط', 'Points'), netPointOptions(n), selected: points, multi: cov == 'points');
                      if (r != null) set(() => points = r);
                    },
                  ),
                if (cov == 'area')
                  NetPickField(
                    label: tx(ctx, 'المَناطِق (${areas.length})', 'Areas (${areas.length})'),
                    icon: Icons.map_outlined,
                    value: areas.map(n.areaName).join(' · '),
                    onTap: () async {
                      final r = await netPick(ctx, tx(ctx, 'المَناطِق', 'Areas'),
                          [for (final a in n.areas) NetOption(vStr(a['id']), vStr(a['name']), sub: tx(ctx, '${(n.pointsOfArea[vStr(a['id'])] ?? const []).length} نُقطة', '${(n.pointsOfArea[vStr(a['id'])] ?? const []).length} points'), icon: Icons.map_outlined)],
                          selected: areas, multi: true);
                      if (r != null) set(() => areas = r);
                    },
                  ),
                if (cov == 'country')
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final c in _countries)
                      ChoiceChip(
                        label: Text(tx(ctx, vStr(c['name_ar']).isEmpty ? vStr(c['name']) : vStr(c['name_ar']), vStr(c['name']))),
                        selected: country == vStr(c['id']),
                        onSelected: (_) => set(() => country = vStr(c['id'])),
                      ),
                  ]),
                if (cov == 'global') Text(tx(ctx, 'يَصلُح في كُلّ نِقاط الفاليه في كُلّ الدُوَل.', 'Valid at every valet point in every country.'), style: const TextStyle(color: VC.muted)),
                const SizedBox(height: 10),
                NetPickField(
                  label: tx(ctx, 'لِعَميل مُعَيَّن (اختياريّ)', 'Only for a client (optional)'),
                  icon: Icons.storefront_outlined,
                  value: site == null ? tx(ctx, 'كُلّ العُمَلاء', 'Every client') : '${vStr(n.branch[site]?['name'])} · ${n.clientName(n.branch[site]?['client_id'])}',
                  onTap: () async {
                    final r = await netPick(ctx, tx(ctx, 'العَميل', 'Client'), [NetOption('', tx(ctx, 'كُلّ العُمَلاء', 'Every client')), ...netBranchOptions(n)], selected: {site ?? ''});
                    if (r != null) set(() => site = r.first.isEmpty ? null : r.first);
                  },
                ),
                sec(tx(ctx, 'السَيّارات وَالمُدَد', 'Cars and periods')),
                Row(children: [
                  Text(tx(ctx, 'عَدَد السَيّارات', 'Cars')),
                  const SizedBox(width: 12),
                  SegmentedButton<int>(
                    segments: [for (final c in const [1, 2, 3]) ButtonSegment(value: c, label: Text('$c'))],
                    selected: {cars.clamp(1, 3)},
                    onSelectionChanged: (v) => set(() => cars = v.first),
                  ),
                ]),
                const SizedBox(height: 8),
                Wrap(spacing: 6, children: [
                  for (final (m, l) in const [(1, '1 m'), (3, '3 m'), (6, '6 m'), (12, '1 y')])
                    FilterChip(selected: durations.contains(m), label: Text(l), onSelected: (v) => set(() => v ? durations.add(m) : (durations.length > 1 ? durations.remove(m) : null))),
                ]),
                const SizedBox(height: 8),
                SwitchListTile(contentPadding: EdgeInsets.zero, value: active, title: Text(tx(ctx, 'فَعّال', 'Active')), onChanged: (v) => set(() => active = v)),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: busy ? null : () => Navigator.pop(ctx), child: Text(tx(ctx, 'إلغاء', 'Cancel'))),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      final g = double.tryParse(price.text.trim()) ?? 0;
                      if (cov == 'point' && g <= 0) return vToast(ctx, tx(ctx, 'اشتِراك النُقطة يُباع في التَطبيق وَيَحتاج سِعراً.', 'A one-point membership is sold in the app and needs a price.'), error: true);
                      if (!free && g <= 0) return vToast(ctx, tx(ctx, 'اكتُب السِعر أَو اختَر مَجّانيّ.', 'Enter the price or choose Free.'), error: true);
                      if (cov == 'country' && country == null) return vToast(ctx, tx(ctx, 'اختَر الدَولة.', 'Choose the country.'), error: true);
                      set(() => busy = true);
                      final r = await vGuard(
                          ctx,
                          () => ValetAdmin.I.call('vva_member_type_save', {
                                'p_id': t?['id'],
                                'p_data': {
                                  'name': name.text.trim(),
                                  'price': free ? 0 : double.parse((g / (1 + _vat)).toStringAsFixed(2)),
                                  'coverage': cov,
                                  'point_ids': points.toList(),
                                  'area_ids': areas.toList(),
                                  'country_id': country,
                                  'site_id': site,
                                  'max_cars': cars,
                                  'durations': (durations.toList()..sort()),
                                  'is_active': active,
                                }
                              }),
                          ok: tx(ctx, 'تَمّ الحِفظ — يَظهَر في التَطبيق خِلال دَقيقَتَين.', 'Saved — shows in the app within two minutes.'));
                      if (!ctx.mounted) return;
                      set(() => busy = false);
                      if (r != null) Navigator.pop(ctx, true);
                    },
              child: Text(tx(ctx, 'حِفظ', 'Save')),
            ),
          ],
        );
      }),
    );
  }

  // ---------------------------------------------------------------- members of a type
  Future<void> _members(BuildContext context, VJson t) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${vStr(t['name'])} · ${tx(ctx, 'المُشتَرِكون', 'Members')}'),
          content: SizedBox(
            width: 760,
            height: 520,
            child: VLoader<VJson>(
              load: () => ValetAdmin.I.call('vva_type_members', {'p_type': t['id']}),
              builder: (ctx, d, reload) {
                final ms = vList(d['members']);
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (ValetAdmin.I.can(ValetAdmin.permClients))
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: FilledButton.icon(
                        icon: const Icon(Icons.person_add_alt_1),
                        label: Text(tx(ctx, 'إضافة مُشتَرِك', 'Add member')),
                        onPressed: () async {
                          if (await _addMember(ctx, t) == true) reload();
                        },
                      ),
                    ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      child: VTable(columns: [
                        DataColumn(label: Text(tx(ctx, 'الكود', 'Code'))),
                        DataColumn(label: Text(tx(ctx, 'الاسم', 'Name'))),
                        DataColumn(label: Text(tx(ctx, 'النِمَر', 'Plates'))),
                        DataColumn(label: Text(tx(ctx, 'مِن', 'From'))),
                        DataColumn(label: Text(tx(ctx, 'إلى', 'To'))),
                        DataColumn(label: Text(tx(ctx, 'الحالة', 'Status'))),
                        const DataColumn(label: Text('')),
                      ], rows: [
                        for (final m in ms)
                          DataRow(cells: [
                            DataCell(Text(vStr(m['member_code']))),
                            DataCell(Text(vStr(m['name']))),
                            DataCell(Text([vStr(m['vehicle_reg1']), vStr(m['vehicle_reg2'])].where((e) => e.isNotEmpty).join(' / '))),
                            DataCell(Text(vStr(m['start_date']))),
                            DataCell(Text(vStr(m['end_date']))),
                            DataCell(vStr(m['subscription_status']) == 'Active' ? VPill(tx(ctx, 'فَعّال', 'Active'), color: VC.ok) : VPill(tx(ctx, 'مُنتَهٍ', 'Expired'), color: VC.bad)),
                            DataCell(vStr(m['subscription_status']) == 'Active' && ValetAdmin.I.can(ValetAdmin.permClients)
                                ? TextButton(
                                    onPressed: () async {
                                      final ok = await vConfirm(ctx, tx(ctx, 'إنهاء الاشتِراك اليَوم؟', 'End the membership today?'), vStr(m['name']),
                                          button: tx(ctx, 'إنهاء', 'End'));
                                      if (!ok || !ctx.mounted) return;
                                      final y = DateTime.now().subtract(const Duration(days: 1));
                                      final r = await vGuard(ctx, () => ValetAdmin.I.call('vva_member_end', {'p_id': m['id'], 'p_end': VF.iso(y)}), ok: tx(ctx, 'تَمّ.', 'Done.'));
                                      if (r != null) reload();
                                    },
                                    child: Text(tx(ctx, 'إنهاء', 'End')))
                                : const SizedBox()),
                          ]),
                      ], empty: tx(ctx, 'لا مُشتَرِكين.', 'No members.')),
                    ),
                  ),
                ]);
              },
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tx(ctx, 'إغلاق', 'Close')))],
        ),
      );

  Future<bool?> _addMember(BuildContext context, VJson t) {
    final name = TextEditingController(), phone = TextEditingController(), p1 = TextEditingController(), p2 = TextEditingController(), card = TextEditingController();
    var from = DateTime.now();
    var to = DateTime(from.year + 1, from.month, from.day).subtract(const Duration(days: 1));
    return showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        Future<void> pick(bool start) async {
          final d = await showDatePicker(context: ctx, initialDate: start ? from : to, firstDate: DateTime(2025), lastDate: DateTime(2050));
          if (d != null) set(() => start ? from = d : to = d);
        }

        return AlertDialog(
          title: Text(tx(ctx, 'مُشتَرِك جَديد · ${t['name']}', 'New member · ${t['name']}')),
          content: SizedBox(
            width: 480,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: card,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                      labelText: tx(ctx, 'رَقم الكَرت المَطبوع (اختياريّ)', 'Printed card number (optional)'),
                      hintText: 'VIP-000001',
                      helperText: tx(ctx, 'يَصير رَقم المُشتَرِك · فارِغ = رَقم M- تِلقائيّ', 'Becomes the member code · empty = automatic M- number'),
                      prefixIcon: const Icon(Icons.credit_card),
                      isDense: true)),
              const SizedBox(height: 10),
              TextField(controller: name, decoration: InputDecoration(labelText: tx(ctx, 'الاسم *', 'Name *'), isDense: true)),
              const SizedBox(height: 10),
              TextField(controller: phone, decoration: InputDecoration(labelText: tx(ctx, 'الهاتِف', 'Phone'), isDense: true)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: TextField(controller: p1, decoration: InputDecoration(labelText: tx(ctx, 'نِمرة 1 *', 'Plate 1 *'), isDense: true))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: p2, decoration: InputDecoration(labelText: tx(ctx, 'نِمرة 2', 'Plate 2'), isDense: true))),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: OutlinedButton.icon(onPressed: () => pick(true), icon: const Icon(Icons.event), label: Text('${tx(ctx, 'مِن', 'From')} ${VF.date(from)}'))),
                const SizedBox(width: 10),
                Expanded(child: OutlinedButton.icon(onPressed: () => pick(false), icon: const Icon(Icons.event), label: Text('${tx(ctx, 'إلى', 'To')} ${VF.date(to)}'))),
              ]),
              const SizedBox(height: 8),
              Text(vNum(t['price']) == 0 ? tx(ctx, 'مَجّانيّ — بِدون بَيع.', 'Free — no sale.') : tx(ctx, 'يُضاف بِدون بَيع (المَبلَغ يُسَجَّل في Odoo يَدَويّاً).', 'Added without a sale (record the money in Odoo).'),
                  style: const TextStyle(color: VC.muted, fontSize: 12)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tx(ctx, 'إلغاء', 'Cancel'))),
            FilledButton(
              onPressed: () async {
                final r = await vGuard(
                    ctx,
                    () => ValetAdmin.I.call('vva_member_add', {
                          'p_data': {
                            'type_id': t['id'],
                            if (card.text.trim().isNotEmpty) 'card_no': card.text.trim(),
                            'name': name.text.trim(),
                            'phone': phone.text.trim(),
                            'vehicle_reg1': p1.text.trim(),
                            'vehicle_reg2': p2.text.trim(),
                            'start_date': VF.iso(from),
                            'end_date': VF.iso(to),
                          }
                        }),
                    ok: tx(ctx, 'تَمّت الإضافة.', 'Added.'));
                if (r != null && ctx.mounted) Navigator.pop(ctx, true);
              },
              child: Text(tx(ctx, 'إضافة', 'Add')),
            ),
          ],
        );
      }),
    );
  }
}


/// إظهار وَإخفاء العُضويّات في كُلّ نُقطة (كانَت في إعدادات النُقطة): صَفحة العُضويّات، الكُروت في إضافة تَذكَرة،
/// زِرّ المُشتَرِك تَحت اللَوحة، وَرَقم المُوافَقة لِلكارت عِند البَيع.
class _PointSwitches extends StatefulWidget {
  const _PointSwitches({required this.points, required this.edit});
  final List<VJson> points;
  final bool edit;

  @override
  State<_PointSwitches> createState() => _PointSwitchesState();
}

class _PointSwitchesState extends State<_PointSwitches> {
  String _q = '';
  bool _onlyOn = false;
  final _busy = <String>{};

  static const _flags = [
    ('show_membership', Icons.card_membership_outlined, 'صَفحة المُشتَرِكين في التَطبيق', 'Members page in the app'),
    ('show_member_pick', Icons.add_card_outlined, 'زِرّ المُشتَرِكين في شاشة التَذكَرة', 'Member button on the ticket screen'),
  ];

  Future<void> _set(VJson p, String k, Object v) async {
    final key = '${p['id']}:$k';
    final old = p[k];
    setState(() {
      _busy.add(key);
      p[k] = v;
    });
    final r = await vGuard(context, () => ValetAdmin.I.call('vva_point_settings_save', {'p_point': p['id'], 'p_data': {k: v}}),
        ok: tx(context, 'تَمّ الحِفظ.', 'Saved.'));
    if (!mounted) return;
    setState(() {
      _busy.remove(key);
      if (r == null) p[k] = old;
    });
  }

  Future<void> _setAll(String k, bool v, List<VJson> list) async {
    for (final p in list) {
      if (vBool(p[k]) != v) await _set(p, k, v);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final list = widget.points.where((p) {
      if (_onlyOn && !vBool(p['show_membership'])) return false;
      if (q.isEmpty) return true;
      return '${p['name']} ${p['code']} ${p['area']}'.toLowerCase().contains(q);
    }).toList();
    final onCount = widget.points.where((p) => vBool(p['show_membership'])).length;

    Widget sw(VJson p, String k) {
      final busy = _busy.contains('${p['id']}:$k');
      return busy
          ? const SizedBox(width: 40, height: 22, child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))))
          : Switch(value: vBool(p[k]), onChanged: !widget.edit ? null : (v) => _set(p, k, v));
    }

    return VPanel(
      title: tx(context, 'العُضويّات في كُلّ نُقطة ($onCount / ${widget.points.length})', 'Memberships per point ($onCount / ${widget.points.length})'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            tx(context,
                'زِرّان لِكُلّ نُقطة: صَفحة المُشتَرِكين (بَيع وَتَجديد وَمُتابَعة)، وَزِرّ المُشتَرِكين في شاشة التَذكَرة (يُقرَأ الكَرت بِـ NFC أَو QR فَقَط — عُضويّة أَو كَرت ذَهَبيّ). يُطَبَّق عَلى التابلت عِند التَحديث التالي.',
                'Two switches per point: the members page (sell, renew, follow up), and the member button on the ticket screen (the card is read by NFC or QR only — member or gold card). Tablets pick it up on the next refresh.'),
            style: const TextStyle(color: VC.muted, fontSize: 12.5)),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: 260,
            child: TextField(
              decoration: InputDecoration(
                  isDense: true, prefixIcon: const Icon(Icons.search), hintText: tx(context, 'بَحث بِالنُقطة أَو المَنطِقة', 'Search point or area'), border: const OutlineInputBorder()),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          FilterChip(
            label: Text(tx(context, 'صَفحة العُضويّات ظاهِرة فَقَط', 'Memberships page on only')),
            selected: _onlyOn,
            onSelected: (v) => setState(() => _onlyOn = v),
          ),
          if (widget.edit && list.isNotEmpty)
            PopupMenuButton<(String, bool)>(
              tooltip: tx(context, 'لِكُلّ النِقاط الظاهِرة', 'For all listed points'),
              onSelected: (e) => _setAll(e.$1, e.$2, list),
              itemBuilder: (_) => [
                for (final (k, _, ar, en) in _flags) ...[
                  PopupMenuItem(value: (k, true), child: Text(tx(context, 'إظهار: $ar', 'Show: $en'))),
                  PopupMenuItem(value: (k, false), child: Text(tx(context, 'إخفاء: $ar', 'Hide: $en'))),
                ],
              ],
              child: Chip(avatar: const Icon(Icons.done_all, size: 18), label: Text(tx(context, 'تَطبيق عَلى ${list.length} نُقطة', 'Apply to ${list.length} points'))),
            ),
        ]),
        const SizedBox(height: 8),
        VTable(columns: [
          DataColumn(label: Text(tx(context, 'النُقطة', 'Point'))),
          DataColumn(label: Text(tx(context, 'الأَنواع', 'Types')), numeric: true),
          DataColumn(label: Text(tx(context, 'مُشتَرِكون', 'Members')), numeric: true),
          for (final (_, icon, ar, en) in _flags)
            DataColumn(label: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 16, color: VC.gold), const SizedBox(width: 4), Text(tx(context, ar, en))])),
        ], rows: [
          for (final p in list)
            DataRow(cells: [
              DataCell(Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(vStr(p['name']), style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('${p['code'] ?? ''}${p['area'] == null ? '' : ' · ${p['area']}'}', style: const TextStyle(color: VC.muted, fontSize: 11.5)),
              ])),
              DataCell(vNum(p['types']) == 0
                  ? VPill(tx(context, 'لا نَوع', 'No type'), color: VC.warn)
                  : Text(VF.n(vNum(p['types'])))),
              DataCell(Text(VF.n(vNum(p['active_members'])))),
              for (final (k, _, _, _) in _flags) DataCell(sw(p, k)),
            ]),
        ]),
      ]),
    );
  }
}
