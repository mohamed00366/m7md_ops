import 'package:flutter/material.dart';

import 'valet_admin.dart';
import 'valet_ui.dart';

/// 🤝 تَطبيق العُمَلاء — مَن يَتَحَقَّق مِن التَذاكِر، في أَيّ نِقاط، بِأَيّ حُدود وَخَصم، وَحِساباتهم.
class ValetClientsScreen extends StatefulWidget {
  const ValetClientsScreen({super.key});

  @override
  State<ValetClientsScreen> createState() => _ValetClientsScreenState();
}

class _ValetClientsScreenState extends State<ValetClientsScreen> {
  String _q = '';
  bool _linkedOnly = true;
  bool get _edit => ValetAdmin.I.can(ValetAdmin.permClients);

  @override
  Widget build(BuildContext context) => ValetGate(
        child: VLoader<VJson>(
          load: () => ValetAdmin.I.call('vva_clients'),
          builder: (context, d, reload) {
            final q = _q.toLowerCase();
            final clients = vList(d['clients']).where((c) {
              if (_linkedOnly && vList(c['points']).isEmpty) return false;
              return q.isEmpty || '${c['name']} ${c['master'] ?? ''}'.toLowerCase().contains(q);
            }).toList();
            final masters = vList(d['masters']).where((m) => vNum(m['branches']) > 0).toList();
            return DefaultTabController(
              length: 2,
              child: Column(children: [
                VHead(tx(context, 'تَطبيق العُمَلاء', 'Customer app'),
                    subtitle: tx(context, 'العُمَلاء الذين يَتَحَقَّقون مِن تَذاكِر ضُيوفهم، وَفي أَيّ نِقاط', 'Clients who validate their guests\' tickets, and at which points'),
                    actions: [
                      SizedBox(
                        width: 240,
                        child: TextField(
                          decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tx(context, 'بَحث', 'Search'), isDense: true),
                          onChanged: (v) => setState(() => _q = v),
                        ),
                      ),
                      FilterChip(
                        label: Text(tx(context, 'مَربوط بِنُقطة', 'Linked to a point')),
                        selected: _linkedOnly,
                        onSelected: (v) => setState(() => _linkedOnly = v),
                      ),
                    ]),
                TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
                  Tab(text: tx(context, 'الفُروع', 'Branches')),
                  Tab(text: tx(context, 'الشَرِكات الأُمّ', 'Parent companies')),
                ]),
                Expanded(
                  child: TabBarView(children: [
                    ListView(padding: const EdgeInsets.all(16), children: [
                      VPanel(
                        child: VTable(columns: [
                          DataColumn(label: Text(tx(context, 'العَميل', 'Client'))),
                          DataColumn(label: Text(tx(context, 'الشَرِكة الأُمّ', 'Parent'))),
                          DataColumn(label: Text(tx(context, 'النِقاط', 'Points'))),
                          DataColumn(label: Text(tx(context, 'التَطبيق', 'App'))),
                          DataColumn(label: Text(tx(context, 'الحِساب', 'Account'))),
                          DataColumn(label: Text(tx(context, 'تَحَقُّقات الشَهر', 'Validations (month)')), numeric: true),
                          const DataColumn(label: Text('')),
                        ], rows: [
                          for (final c in clients)
                            DataRow(
                              onSelectChanged: (_) async {
                                await Navigator.of(context).push(MaterialPageRoute(
                                    builder: (_) => ValetClientDetailScreen(siteId: vStr(c['id']), masters: vList(d['masters']))));
                                reload();
                              },
                              cells: [
                                DataCell(Text(vStr(c['name']), style: const TextStyle(fontWeight: FontWeight.w600))),
                                DataCell(Text(vStr(c['master']))),
                                DataCell(Text(vList(c['points']).map((p) => vStr(p['code']).replaceFirst('AE-POS-', '')).join(', '))),
                                DataCell(vBool(c['approved']) ? VPill(tx(context, 'مَسموح', 'Allowed'), color: VC.ok) : VPill(tx(context, 'غَير مَسموح', 'Not allowed'))),
                                DataCell(c['account'] == null
                                    ? const Text('-')
                                    : VPill(vStr(vMap(c['account'])['username']), color: vBool(vMap(c['account'])['active']) ? VC.info : VC.muted)),
                                DataCell(Text(vStr(c['validations_month']))),
                                const DataCell(Icon(Icons.chevron_right)),
                              ],
                            ),
                        ]),
                      ),
                    ]),
                    ListView(padding: const EdgeInsets.all(16), children: [
                      Text(tx(context, 'حِساب الشَرِكة الأُمّ يَرى كُلّ فُروعها وَيَتَحَقَّق لَها.', 'A parent company account sees and validates for all its branches.'),
                          style: const TextStyle(color: VC.muted)),
                      const SizedBox(height: 10),
                      VPanel(
                        child: VTable(columns: [
                          DataColumn(label: Text(tx(context, 'الشَرِكة', 'Company'))),
                          DataColumn(label: Text(tx(context, 'الفُروع', 'Branches')), numeric: true),
                          DataColumn(label: Text(tx(context, 'الحِساب', 'Account'))),
                          const DataColumn(label: Text('')),
                        ], rows: [
                          for (final m in masters)
                            DataRow(cells: [
                              DataCell(Text(vStr(m['name']), style: const TextStyle(fontWeight: FontWeight.w600))),
                              DataCell(Text(vStr(m['branches']))),
                              DataCell(m['account'] == null
                                  ? const Text('-')
                                  : VPill(vStr(vMap(m['account'])['username']), color: vBool(vMap(m['account'])['active']) ? VC.info : VC.muted)),
                              DataCell(!_edit
                                  ? const SizedBox()
                                  : TextButton.icon(
                                      icon: const Icon(Icons.manage_accounts_outlined),
                                      label: Text(m['account'] == null ? tx(context, 'إنشاء حِساب', 'Create account') : tx(context, 'الحِساب', 'Account')),
                                      onPressed: () async {
                                        if (await valetAccountDialog(context, master: m, account: m['account'] == null ? null : vMap(m['account']))) reload();
                                      },
                                    )),
                            ]),
                        ]),
                      ),
                    ]),
                  ]),
                ),
              ]),
            );
          },
        ),
      );
}

/// إنشاء / تَعديل حِساب تَطبيق العُمَلاء لِفَرع ([site]) أَو شَرِكة أُمّ ([master]).
Future<bool> valetAccountDialog(BuildContext context, {VJson? site, VJson? master, VJson? account}) async {
  final user = TextEditingController(text: vStr(account?['username']));
  final pass = TextEditingController();
  bool active = account == null ? true : vBool(account['active']);
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text('${tx(ctx, 'حِساب تَطبيق العُمَلاء', 'Customer app account')} · ${site?['name'] ?? master?['name']}'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: user, decoration: InputDecoration(labelText: tx(ctx, 'اسم المُستَخدِم *', 'User name *'))),
            const SizedBox(height: 12),
            TextField(
              controller: pass,
              decoration: InputDecoration(
                labelText: account == null
                    ? tx(ctx, 'كَلِمة المُرور * (6 أَحرُف عَلى الأَقَلّ)', 'Password * (min. 6)')
                    : tx(ctx, 'كَلِمة مُرور جَديدة (اترُكها فارِغة)', 'New password (leave empty to keep)'),
                helperText: tx(ctx, 'تُحفَظ مُشَفَّرة: سَجِّلها وَسَلِّمها لِلعَميل.', 'Stored encrypted: write it down and give it to the client.'),
              ),
            ),
            if (account != null)
              SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(tx(ctx, 'فَعّال', 'Active')), value: active, onChanged: (v) => set(() => active = v)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tx(ctx, 'إلغاء', 'Cancel'))),
          FilledButton(
            onPressed: () async {
              final ok = await vGuard(
                ctx,
                () => ValetAdmin.I.call('vva_client_account_save', {
                  'p_site': site?['id'],
                  'p_master': master?['id'],
                  'p_username': user.text.trim(),
                  'p_password': pass.text,
                  'p_active': active,
                }),
                ok: tx(ctx, 'تَمّ حِفظ الحِساب.', 'Account saved.'),
              );
              if (ok != null && ctx.mounted) Navigator.pop(ctx, true);
            },
            child: Text(tx(ctx, 'حِفظ', 'Save')),
          ),
        ],
      ),
    ),
  );
  return r == true;
}

// ================================================================ client detail
class ValetClientDetailScreen extends StatefulWidget {
  const ValetClientDetailScreen({super.key, required this.siteId, required this.masters});
  final String siteId;
  final List<VJson> masters;

  @override
  State<ValetClientDetailScreen> createState() => _ValetClientDetailScreenState();
}

class _ValetClientDetailScreenState extends State<ValetClientDetailScreen> {
  VJson? _d;
  Object? _err;
  bool get _edit => ValetAdmin.I.can(ValetAdmin.permClients);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await ValetAdmin.I.call('vva_client', {'p_site': widget.siteId});
      if (mounted) setState(() => _d = d);
    } catch (e) {
      if (mounted) setState(() => _err = e);
    }
  }

  Future<void> _save(Map<String, dynamic> data) async {
    final d = await vGuard(context, () => ValetAdmin.I.call('vva_client_settings_save', {'p_site': widget.siteId, 'p_data': data}),
        ok: tx(context, 'تَمّ الحِفظ.', 'Saved.'));
    if (d != null && mounted) setState(() => _d = d);
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return Scaffold(
      appBar: AppBar(title: Text(d == null ? tx(context, 'العَميل', 'Client') : vStr(vMap(d['client'])['name']))),
      body: d == null ? Center(child: _err != null ? Text(vErr(context, _err!)) : const CircularProgressIndicator()) : _body(d),
    );
  }

  Widget _body(VJson d) {
    final c = vMap(d['client']);
    final s = vMap(d['settings']);
    final points = vList(d['points']);
    final prices = vList(d['prices']);
    final account = d['account'] == null ? null : vMap(d['account']);
    final limit = TextEditingController(text: vStr(s['allowed_vehicles']));
    final discAmount = TextEditingController(text: vStr(s['discount_amount']));
    final lostPrice = TextEditingController(text: vStr(s['lost_card_price']));
    String period = vStr(s['duration_type']);
    String discType = vStr(s['discount_type']).toUpperCase();
    if (!['', 'PERCENTAGE', 'FIXED_AMOUNT', 'FULL_AMOUNT'].contains(discType)) discType = '';
    Widget sw(String key, String ar, String en, [String sub = '']) => SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tx(context, ar, en), style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: sub.isEmpty ? null : Text(sub),
          value: vBool(s[key]),
          onChanged: !_edit ? null : (v) => _save({key: v}),
        );
    return ListView(padding: const EdgeInsets.all(16), children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 14, runSpacing: 14, children: [
              SizedBox(
                width: 520,
                child: VPanel(
                  title: tx(context, 'تَطبيق العُمَلاء', 'Customer app'),
                  child: Column(children: [
                    sw('approved', 'مَسموح لَه بِاستِخدام التَطبيق', 'Allowed to use the customer app',
                        tx(context, 'التَحَقُّق مِن التَذاكِر وَالتَقارير', 'Validate tickets and see reports')),
                    sw('car_request', 'يَطلُب السَيّارات لِضُيوفه', 'Can request cars for guests'),
                    sw('stamp_ticket', 'تَذاكِر الخَتم', 'Stamp tickets'),
                    const Divider(),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.manage_accounts_outlined),
                      title: Text(account == null ? tx(context, 'لا يُوجَد حِساب', 'No account yet') : '${tx(context, 'المُستَخدِم', 'User')}: ${account['username']}'),
                      subtitle: account == null ? null : Text(vBool(account['active']) ? tx(context, 'فَعّال', 'Active') : tx(context, 'مُتَوَقِّف', 'Off')),
                      trailing: !_edit
                          ? null
                          : OutlinedButton(
                              onPressed: () async {
                                if (await valetAccountDialog(context, site: c, account: account)) _load();
                              },
                              child: Text(account == null ? tx(context, 'إنشاء', 'Create') : tx(context, 'تَغيير', 'Change')),
                            ),
                    ),
                    const Divider(),
                    DropdownButtonFormField<String?>(
                      value: vStr(c['master_id']).isEmpty ? null : vStr(c['master_id']),
                      isExpanded: true,
                      decoration: InputDecoration(labelText: tx(context, 'الشَرِكة الأُمّ (تَرى كُلّ فُروعها)', 'Parent company (sees all its branches)')),
                      items: [
                        DropdownMenuItem<String?>(value: null, child: Text(tx(context, 'لا يُوجَد', 'None'))),
                        for (final m in widget.masters) DropdownMenuItem<String?>(value: vStr(m['id']), child: Text(vStr(m['name']))),
                      ],
                      onChanged: !_edit ? null : (v) => _save({'master_id': v ?? ''}),
                    ),
                  ]),
                ),
              ),
              SizedBox(
                width: 520,
                child: VPanel(
                  title: tx(context, 'قَواعِد التَحَقُّق', 'Validation rules'),
                  actions: [
                    if (_edit)
                      FilledButton.icon(
                        icon: const Icon(Icons.save_outlined),
                        label: Text(tx(context, 'حِفظ', 'Save')),
                        onPressed: () => _save({
                          'allowed_vehicles': int.tryParse(limit.text),
                          'duration_type': period,
                          'discount_type': discType,
                          'discount_amount': num.tryParse(discAmount.text),
                          'lost_card_price': num.tryParse(lostPrice.text),
                        }),
                      ),
                  ],
                  child: StatefulBuilder(
                    builder: (ctx, set) => Column(children: [
                      Row(children: [
                        Expanded(
                          child: TextField(
                            controller: limit,
                            enabled: _edit,
                            decoration: InputDecoration(
                                labelText: tx(context, 'أَقصى عَدَد سَيّارات', 'Max. validated cars'),
                                helperText: tx(context, 'فارِغ أَو 0 = بِلا حَدّ', 'Empty or 0 = no limit')),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: ['', 'daily', 'weekly', 'monthly'].contains(period) ? period : '',
                            decoration: InputDecoration(labelText: tx(context, 'لِكُلّ', 'Per')),
                            items: [
                              const DropdownMenuItem(value: '', child: Text('-')),
                              DropdownMenuItem(value: 'daily', child: Text(tx(context, 'يَوم', 'Day'))),
                              DropdownMenuItem(value: 'weekly', child: Text(tx(context, 'أُسبوع', 'Week'))),
                              DropdownMenuItem(value: 'monthly', child: Text(tx(context, 'شَهر', 'Month'))),
                            ],
                            onChanged: !_edit ? null : (v) => set(() => period = v ?? ''),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(tx(context, 'خَصم عَلى التَذاكِر المُتَحَقَّق مِنها', 'Discount on validated tickets')),
                        value: vBool(s['discounts']),
                        onChanged: !_edit ? null : (v) => _save({'discounts': v}),
                      ),
                      Row(children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: discType,
                            decoration: InputDecoration(labelText: tx(context, 'نَوع الخَصم', 'Discount type')),
                            items: [
                              const DropdownMenuItem(value: '', child: Text('-')),
                              DropdownMenuItem(value: 'PERCENTAGE', child: Text(tx(context, 'نِسبة %', 'Percentage %'))),
                              DropdownMenuItem(value: 'FIXED_AMOUNT', child: Text(tx(context, 'مَبلَغ (AED)', 'Amount (AED)'))),
                              DropdownMenuItem(value: 'FULL_AMOUNT', child: Text(tx(context, 'مَجّانيّ (100%)', 'Free (100%)'))),
                            ],
                            onChanged: !_edit ? null : (v) => set(() => discType = v ?? ''),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: TextField(controller: discAmount, enabled: _edit, decoration: InputDecoration(labelText: tx(context, 'قيمة الخَصم', 'Discount value')))),
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(child: TextField(controller: lostPrice, enabled: _edit, decoration: InputDecoration(labelText: tx(context, 'رَسم الكَرت المَفقود (AED)', 'Lost card fee (AED)')))),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(tx(context, 'تَحصيل الكَرت المَفقود', 'Charge lost card')),
                            value: vBool(s['lost_card_active']),
                            onChanged: !_edit ? null : (v) => _save({'lost_card_active': v}),
                          ),
                        ),
                      ]),
                    ]),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            VPanel(
              title: tx(context, 'نِقاط هذا العَميل', 'Points of this client'),
              actions: [
                if (_edit)
                  OutlinedButton.icon(icon: const Icon(Icons.add_link), label: Text(tx(context, 'رَبط بِنُقطة', 'Link a point')), onPressed: () => _linkDialog(points)),
              ],
              child: points.isEmpty
                  ? Text(tx(context, 'غَير مَربوط بِأَيّ نُقطة.', 'Not linked to any point.'), style: const TextStyle(color: VC.muted))
                  : Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final p in points)
                        InputChip(
                          label: Text('${p['code']} · ${p['name']}'),
                          onDeleted: !_edit
                              ? null
                              : () async {
                                  if (await vConfirm(
                                      context,
                                      tx(context, 'فَكّ الرَبط', 'Unlink point'),
                                      tx(context, 'فَكّ رَبط ${c['name']} مِن ${p['name']}؟ تَتَوَقَّف أَسعاره في هذه النُقطة.',
                                          'Unlink ${c['name']} from ${p['name']}? Its prices at this point are turned off.'),
                                      button: tx(context, 'فَكّ', 'Unlink'))) {
                                    if (!mounted) return;
                                    final r = await vGuard(context,
                                        () => ValetAdmin.I.call('vva_client_link', {'p_point': p['id'], 'p_site': widget.siteId, 'p_linked': false}),
                                        ok: tx(context, 'تَمّ.', 'Done.'));
                                    if (r != null && mounted) setState(() => _d = r);
                                  }
                                },
                        ),
                    ]),
            ),
            const SizedBox(height: 14),
            VPanel(
              title: tx(context, 'أَسعار هذا العَميل', 'Prices of this client'),
              child: VTable(
                empty: tx(context, 'لا تُوجَد أَسعار خاصّة. أَضِفها مِن صَفحة النُقطة ← الأَسعار ← لِمَن: هذا العَميل.',
                    'No client price. Add it from the point page → Prices → For: this client.'),
                columns: [
                  DataColumn(label: Text(tx(context, 'النُقطة', 'Point'))),
                  DataColumn(label: Text(tx(context, 'الاسم', 'Name'))),
                  DataColumn(label: Text(tx(context, 'النَوع', 'Mode'))),
                  DataColumn(label: Text(tx(context, 'الإجماليّ', 'Total')), numeric: true),
                  DataColumn(label: Text(tx(context, 'الحالة', 'Status'))),
                ],
                rows: [
                  for (final p in prices)
                    DataRow(cells: [
                      DataCell(Text(vStr(p['point_name']))),
                      DataCell(Text(vStr(p['ticket_name']))),
                      DataCell(Text(p['ticket_mode'] == 'HOURLY'
                          ? '${tx(context, 'بِالسّاعة', 'Hourly')} · ${vBand(context, vStr(p['start_time']), vStr(p['finish_time']))} · ${vDaysLabel(context, p['days'])}'
                          : tx(context, 'ثابِت', 'Fixed'))),
                      DataCell(Text(VF.money(vNum(p['total'])))),
                      DataCell(vBool(p['is_active']) ? VPill(tx(context, 'فَعّال', 'Active'), color: VC.ok) : VPill(tx(context, 'مُتَوَقِّف', 'Off'))),
                    ]),
                ],
              ),
            ),
          ]),
        ),
      ),
    ]);
  }

  Future<void> _linkDialog(List<VJson> linked) async {
    final all = await vGuard(context, VPoints.get);
    if (all == null || !mounted) return;
    final ids = linked.map((p) => vStr(p['id'])).toSet();
    final options = all.where((p) => !ids.contains(vStr(p['id']))).toList();
    String q = '';
    final picked = await showDialog<VJson>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final list = options.where((p) => '${p['code']} ${p['name']}'.toLowerCase().contains(q.toLowerCase())).toList();
        return AlertDialog(
          title: Text(tx(ctx, 'رَبط بِنُقطة', 'Link a point')),
          content: SizedBox(
            width: 420,
            height: 440,
            child: Column(children: [
              TextField(
                autofocus: true,
                decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tx(ctx, 'بَحث', 'Search')),
                onChanged: (v) => set(() => q = v),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(children: [
                  for (final p in list)
                    ListTile(dense: true, title: Text(vStr(p['name'])), subtitle: Text(vStr(p['code'])), onTap: () => Navigator.pop(ctx, p)),
                ]),
              ),
            ]),
          ),
        );
      }),
    );
    if (picked == null || !mounted) return;
    final r = await vGuard(context, () => ValetAdmin.I.call('vva_client_link', {'p_point': picked['id'], 'p_site': widget.siteId, 'p_linked': true}),
        ok: tx(context, 'تَمّ الرَبط بِـ ${picked['name']}.', 'Linked to ${picked['name']}.'));
    if (r != null && mounted) setState(() => _d = r);
  }
}
