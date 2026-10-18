import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'valet_admin.dart';
import 'valet_ui.dart';

/// 🏪 تَطبيق الفاليه — إعدادات كُلّ نُقطة: المَزايا، الأَسعار، VIP، العُضويّات،
/// المَواقِف، حِساب الجِهاز، المُعِدّات وَدَفاتِر التَذاكِر.
class ValetPointsScreen extends StatefulWidget {
  const ValetPointsScreen({super.key});

  @override
  State<ValetPointsScreen> createState() => _ValetPointsScreenState();
}

class _ValetPointsScreenState extends State<ValetPointsScreen> {
  String _q = '';
  bool _valetOnly = true;

  @override
  Widget build(BuildContext context) => ValetGate(
        child: VLoader<List<VJson>>(
          load: () async {
            VPoints.clear();
            return VPoints.get();
          },
          builder: (context, all, reload) {
            final q = _q.toLowerCase();
            final list = all.where((p) {
              if (_valetOnly && p['configured'] != true && p['terminal'] == null) return false;
              return q.isEmpty || '${p['code']} ${p['name']}'.toLowerCase().contains(q);
            }).toList();
            return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
              VHead(tx(context, 'تَطبيق الفاليه — النِقاط', 'Valet app — points'),
                  subtitle: tx(context, 'المَزايا وَالأَسعار وَالمَواقِف وَحِساب الجِهاز لِكُلّ نُقطة', 'Features, prices, parking and the device account of each point'),
                  actions: [
                    SizedBox(
                      width: 240,
                      child: TextField(
                        decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tx(context, 'بَحث', 'Search'), isDense: true),
                        onChanged: (v) => setState(() => _q = v),
                      ),
                    ),
                    FilterChip(
                      label: Text(tx(context, 'نِقاط الفاليه فَقَط', 'Valet points only')),
                      selected: _valetOnly,
                      onSelected: (v) => setState(() => _valetOnly = v),
                    ),
                  ]),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: VPanel(
                  child: VTable(columns: [
                    DataColumn(label: Text(tx(context, 'الكود', 'Code'))),
                    DataColumn(label: Text(tx(context, 'النُقطة', 'Point'))),
                    DataColumn(label: Text(tx(context, 'حِساب الجِهاز', 'Device account'))),
                    DataColumn(label: Text(tx(context, 'العُمَلاء', 'Clients')), numeric: true),
                    DataColumn(label: Text(tx(context, 'الأَسعار', 'Prices')), numeric: true),
                    DataColumn(label: Text(tx(context, 'سَيّارات الآن', 'Cars now')), numeric: true),
                    const DataColumn(label: Text('')),
                  ], rows: [
                    for (final p in list)
                      DataRow(
                        onSelectChanged: (_) async {
                          await Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => ValetPointDetailScreen(pointId: vStr(p['id']), title: vStr(p['name']))));
                          reload();
                        },
                        cells: [
                          DataCell(Text(vStr(p['code']))),
                          DataCell(Text(vStr(p['name']), style: const TextStyle(fontWeight: FontWeight.w600))),
                          DataCell(p['terminal'] == null
                              ? VPill(tx(context, 'غَير مَوجود', 'Missing'), color: VC.bad)
                              : VPill(vStr(vMap(p['terminal'])['username']), color: vBool(vMap(p['terminal'])['active']) ? VC.ok : VC.muted)),
                          DataCell(Text(vStr(p['clients']))),
                          DataCell(Text(vStr(p['prices']))),
                          DataCell(Text(vStr(p['active']))),
                          const DataCell(Icon(Icons.chevron_right)),
                        ],
                      ),
                  ]),
                ),
              ),
            ]);
          },
        ),
      );
}

// ================================================================ detail
class ValetPointDetailScreen extends StatefulWidget {
  const ValetPointDetailScreen({super.key, required this.pointId, required this.title});
  final String pointId;
  final String title;

  @override
  State<ValetPointDetailScreen> createState() => _ValetPointDetailScreenState();
}

class _ValetPointDetailScreenState extends State<ValetPointDetailScreen> {
  VJson? _d;
  Object? _err;
  bool get _edit => ValetAdmin.I.can(ValetAdmin.permSettings);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await ValetAdmin.I.call('vva_point', {'p_point': widget.pointId});
      if (mounted) setState(() => _d = d);
    } catch (e) {
      if (mounted) setState(() => _err = e);
    }
  }

  Future<void> _save(String fn, Map<String, dynamic> args, {String? ok}) async {
    final d = await vGuard(context, () => ValetAdmin.I.call(fn, args), ok: ok ?? tx(context, 'تَمّ الحِفظ.', 'Saved.'));
    if (d != null && mounted) setState(() => _d = d);
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: Text(d == null ? widget.title : '${vMap(d['point'])['code']} · ${vMap(d['point'])['name']}'),
          bottom: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
            Tab(text: tx(context, 'المَزايا', 'Features')),
            Tab(text: tx(context, 'الأَسعار', 'Prices')),
            Tab(text: tx(context, 'VIP وَالعُضويّات', 'VIP & memberships')),
            Tab(text: tx(context, 'المَواقِف', 'Parking')),
            Tab(text: tx(context, 'حِساب الجِهاز', 'Device account')),
            Tab(text: tx(context, 'المُعِدّات وَالدَفاتِر', 'Equipment & books')),
          ]),
        ),
        body: d == null
            ? Center(child: _err != null ? Text(vErr(context, _err!)) : const CircularProgressIndicator())
            : TabBarView(children: [_features(d), _prices(d), _vipPlans(d), _parking(d), _terminal(d), _equipment(d)]),
      ),
    );
  }

  Widget _page(List<Widget> children) => ListView(padding: const EdgeInsets.all(16), children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final c in children) ...[c, const SizedBox(height: 14)],
            ]),
          ),
        ),
      ]);

  // ---------------------------------------------------------------- features
  List<(String, String, String, String, String)> _flags(BuildContext c) => [
        ('car_request', 'العَميل يَطلُب سَيّارَته', 'Customers can request their car', 'مِن رابِط / QR التَذكَرة المَطبوعة', 'From the ticket link / QR'),
        ('key_rack_w_sites_or_allow', 'تَطبيق المَفاتيح', 'Key rack app', 'المُوَظَّف بِمُسَمّى Key Controller يَفتَح تَطبيق المَفاتيح', 'Staff titled "Key Controller" open the key rack app'),
        ('sinin_w_card', 'دُخول المُوَظَّفين بِاسم المُستَخدِم وَكَلِمة المُرور', 'Staff sign in with user name + password', 'إيقاف = الدُخول بِكَرت NFC / QR فَقَط', 'Off = NFC / QR card only'),
        ('paid_first_or_paid_after', 'السَماح بِوَرديّة "الدَفع أَوَّلاً"', 'Allow "Pay first" shifts', 'وَإلّا يَدفَع العَميل عِند الخُروج دائِماً', 'Otherwise customers pay at check-out'),
        ('price_group_customer', 'أَسعار النُقطة لِكُلّ العُمَلاء', 'Point prices for every client', 'إيقاف = كُلّ عَميل بِأَسعاره', 'Off = each client uses its own prices'),
        ('stamp_ticket', 'تَذاكِر الخَتم', 'Stamp tickets', 'تَذكَرة مَجّانيّة بِصورة خَتم العَميل', 'Free ticket with a stamp photo'),
        ('photo_in_out', 'صورة السَيّارة عَلى التَذكَرة', 'Car photo on the ticket', '', ''),
        ('nfc_qr_in_out', 'كَرت التَذكَرة (NFC / QR) عِند الدُخول', 'Ticket card (NFC / QR) on entry', '', ''),
        ('used_card_manual', 'الجِهاز يَختار NFC أَو QR', 'Device may choose NFC or QR', '', ''),
        ('drivers_in', 'تَسجيل السائِق الذي يَصُفّ السَيّارة', 'Record the parking driver', '', ''),
        ('drivers_out', 'تَسجيل السائِق الذي يُحضِر السَيّارة', 'Record the delivering driver', '', ''),
        ('parking_in_out', 'المَوقِف وَرَقمه', 'Parking area and number', '', ''),
        ('dropdown_parkingcar', 'اختيار سائِق الصَفّ مِن قائِمة', 'Pick the parking driver from a list', 'إيقاف = مَسح كَرت السائِق', 'Off = scan the driver card'),
        ('dropdown_time_in_out', 'اختيار السائِقين مِن قائِمة لِلحُضور', 'Pick drivers from a list for check-in / out', 'إيقاف = مَسح كَرت السائِق', 'Off = scan the driver card'),
        ('drivers_nfc_qr', 'كُروت السائِقين (NFC / QR)', 'Driver cards (NFC / QR)', '', ''),
        ('show_membership', 'العُضويّات', 'Memberships', 'بَيع وَمُتابَعة العُضويّات الشَهريّة', 'Sell and check monthly members'),
        ('member_card_normal', 'كَرت العُضويّة عَلى التَذكَرة', 'Member card on tickets', '', ''),
        ('member_card_gold', 'الكَرت الذَهَبيّ عَلى التَذكَرة', 'Gold card on tickets', '', ''),
        ('paid_with_app_or_keyrack', 'الدَفع في تَطبيق المَفاتيح', 'Payment at the key rack', '', ''),
      ];

  Widget _features(VJson d) {
    final s = vMap(d['settings']);
    final prefix = TextEditingController(text: vStr(s['ticket_prefix']));
    final desc = TextEditingController(text: vStr(s['description']));
    final lost = TextEditingController(text: vNum(s['lost_ticket_price']).toString());
    final night = TextEditingController(text: vNum(s['over_night_price']).toString());
    final vat = TextEditingController(text: (vNum(s['vat_rate']) * 100).toStringAsFixed(2));
    void toggle(String k, bool v) => _save('vva_point_settings_save', {'p_point': widget.pointId, 'p_data': {k: v}});
    return _page([
      VPanel(
        title: tx(context, 'مَزايا التَطبيقات في هذه النُقطة', 'Features of the apps at this point'),
        child: Wrap(spacing: 16, runSpacing: 2, children: [
          for (final f in _flags(context))
            SizedBox(
              width: 500,
              child: SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(tx(context, f.$2, f.$3), style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: f.$4.isEmpty ? null : Text(tx(context, f.$4, f.$5)),
                value: vBool(s[f.$1]),
                onChanged: !_edit ? null : (v) => toggle(f.$1, v),
              ),
            ),
        ]),
      ),
      VPanel(
        title: tx(context, 'التَذاكِر وَالرُسوم', 'Tickets and charges'),
        actions: [
          if (_edit)
            FilledButton.icon(
              icon: const Icon(Icons.save_outlined),
              label: Text(tx(context, 'حِفظ', 'Save')),
              onPressed: () => _save('vva_point_settings_save', {
                'p_point': widget.pointId,
                'p_data': {
                  'ticket_prefix': prefix.text,
                  'description': desc.text,
                  'lost_ticket_price': num.tryParse(lost.text) ?? 0,
                  'over_night_price': num.tryParse(night.text) ?? 0,
                  'vat_rate': (num.tryParse(vat.text) ?? 5) / 100,
                },
              }),
            ),
        ],
        child: Wrap(spacing: 14, runSpacing: 14, children: [
          _field(prefix, tx(context, 'بادِئة التَذكَرة', 'Ticket prefix'), help: 'T-0001-PREFIX-26', width: 220),
          _field(vat, tx(context, 'الضَريبة %', 'VAT %'), width: 110, number: true),
          _field(desc, tx(context, 'وَصف يُطبَع عَلى التَذكَرة', 'Description printed on the ticket'), width: 460),
          SizedBox(
            width: 360,
            child: Row(children: [
              Switch(value: vBool(s['lost_ticket_enabled']), onChanged: !_edit ? null : (v) => toggle('lost_ticket_enabled', v)),
              const SizedBox(width: 8),
              Expanded(child: _field(lost, tx(context, 'رَسم التَذكَرة المَفقودة (AED)', 'Lost ticket fee (AED)'), number: true)),
            ]),
          ),
          SizedBox(
            width: 360,
            child: Row(children: [
              Switch(value: vBool(s['over_night_enabled']), onChanged: !_edit ? null : (v) => toggle('over_night_enabled', v)),
              const SizedBox(width: 8),
              Expanded(child: _field(night, tx(context, 'رَسم المَبيت (AED)', 'Overnight fee (AED)'), number: true)),
            ]),
          ),
        ]),
      ),
      VPanel(
        title: tx(context, 'عُمَلاء هذه النُقطة', 'Clients at this point'),
        child: vList(d['clients']).isEmpty
            ? Text(tx(context, 'لا يُوجَد عَميل مَربوط. اربُط العُمَلاء مِن صَفحة "تَطبيق العُمَلاء".', 'No client is linked. Link clients from "Customer app".'),
                style: const TextStyle(color: VC.muted))
            : Wrap(spacing: 8, runSpacing: 8, children: [
                for (final c in vList(d['clients']))
                  VPill(vStr(c['name']), color: vBool(c['approved']) ? VC.ok : VC.muted, icon: vBool(c['approved']) ? Icons.verified_outlined : Icons.hourglass_empty),
              ]),
      ),
    ]);
  }

  Widget _field(TextEditingController c, String label, {String? help, double width = 280, bool number = false}) => SizedBox(
        width: width,
        child: TextField(
          controller: c,
          enabled: _edit,
          keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : null,
          inputFormatters: number ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))] : null,
          decoration: InputDecoration(labelText: label, helperText: help, isDense: true),
        ),
      );

  // ---------------------------------------------------------------- prices
  Widget _prices(VJson d) {
    final prices = vList(d['prices']);
    return _page([
      VPanel(
        title: tx(context, 'الأَسعار (${prices.length})', 'Prices (${prices.length})'),
        actions: [
          if (_edit) FilledButton.icon(icon: const Icon(Icons.add), label: Text(tx(context, 'إضافة سِعر', 'Add price')), onPressed: () => _priceDialog(d, null)),
        ],
        child: VTable(
          empty: tx(context, 'لا تُوجَد أَسعار بَعد.', 'No price yet.'),
          columns: [
            DataColumn(label: Text(tx(context, 'لِمَن', 'For'))),
            DataColumn(label: Text(tx(context, 'الاسم', 'Name'))),
            DataColumn(label: Text(tx(context, 'النَوع', 'Mode'))),
            DataColumn(label: Text(tx(context, 'السّاعات', 'Hours'))),
            DataColumn(label: Text(tx(context, 'السِعر', 'Price')), numeric: true),
            DataColumn(label: Text(tx(context, 'الضَريبة', 'VAT')), numeric: true),
            DataColumn(label: Text(tx(context, 'الإجماليّ', 'Total')), numeric: true),
            DataColumn(label: Text(tx(context, 'الحالة', 'Status'))),
            const DataColumn(label: Text('')),
          ],
          rows: [
            for (final p in prices)
              DataRow(cells: [
                DataCell(Text(p['client_name'] == null ? tx(context, 'الكُلّ (سِعر النُقطة)', 'All (point price)') : vStr(p['client_name']))),
                DataCell(Text(vStr(p['ticket_name']), style: const TextStyle(fontWeight: FontWeight.w600))),
                DataCell(Text(p['ticket_mode'] == 'HOURLY' ? tx(context, 'بِالسّاعة', 'Hourly') : tx(context, 'ثابِت', 'Fixed'))),
                DataCell(Text(p['ticket_mode'] == 'HOURLY' ? '${p['start_time']} → ${p['finish_time']}' : '-')),
                DataCell(Text(VF.money(vNum(p['price'])))),
                DataCell(Text(VF.money(vNum(p['tax'])))),
                DataCell(Text(VF.money(vNum(p['total'])), style: const TextStyle(fontWeight: FontWeight.w700))),
                DataCell(vBool(p['is_active']) ? VPill(tx(context, 'فَعّال', 'Active'), color: VC.ok) : VPill(tx(context, 'مُتَوَقِّف', 'Off'))),
                DataCell(!_edit
                    ? const SizedBox()
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(tooltip: tx(context, 'تَعديل', 'Edit'), icon: const Icon(Icons.edit_outlined), onPressed: () => _priceDialog(d, p)),
                        IconButton(
                          tooltip: tx(context, 'حَذف', 'Delete'),
                          icon: const Icon(Icons.delete_outline, color: VC.bad),
                          onPressed: () async {
                            if (await vConfirm(context, tx(context, 'حَذف السِعر', 'Delete price'), '${p['ticket_name']}')) {
                              if (!mounted) return;
                              _save('vva_row_delete', {'p_kind': 'price', 'p_id': p['id']}, ok: tx(context, 'تَمّ الحَذف.', 'Deleted.'));
                            }
                          },
                        ),
                      ])),
              ]),
          ],
        ),
      ),
      Text(
        tx(context, 'الأَسعار بِالسّاعة: صَفّ لِكُلّ فَترة، مَثَلاً 0:00 ← 1:00 = 20، 1:00 ← 3:00 = 30، 3:00 ← Infinity = 10 لِكُلّ ساعة إضافيّة.',
            'Hourly prices: one row per band, e.g. 0:00 → 1:00 = 20, 1:00 → 3:00 = 30, 3:00 → Infinity = 10 for every extra hour.'),
        style: const TextStyle(color: VC.muted),
      ),
    ]);
  }

  Future<void> _priceDialog(VJson d, VJson? p) async {
    final vatRate = vNum(vMap(d['settings'])['vat_rate']) == 0 ? 0.05 : vNum(vMap(d['settings'])['vat_rate']);
    final name = TextEditingController(text: vStr(p?['ticket_name']));
    final total = TextEditingController(text: p == null ? '' : vNum(p['total']).toString());
    final start = TextEditingController(text: vStr(p?['start_time']).isEmpty ? '0:00' : vStr(p?['start_time']));
    final finish = TextEditingController(text: vStr(p?['finish_time']).isEmpty ? 'Infinity' : vStr(p?['finish_time']));
    final notes = TextEditingController(text: vStr(p?['notes']));
    String mode = vStr(p?['ticket_mode']).isEmpty ? 'TICKET' : vStr(p?['ticket_mode']);
    String? site = p?['site_id'] as String?;
    bool active = p == null ? true : vBool(p['is_active']);
    final clients = vList(d['clients']);
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final t = num.tryParse(total.text) ?? 0;
        final price = t / (1 + vatRate);
        return AlertDialog(
          title: Text(p == null ? tx(ctx, 'إضافة سِعر', 'Add price') : tx(ctx, 'تَعديل السِعر', 'Edit price')),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<String?>(
                  value: site,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: tx(ctx, 'لِمَن', 'For')),
                  items: [
                    DropdownMenuItem(value: null, child: Text(tx(ctx, 'كُلّ العُمَلاء (سِعر النُقطة)', 'All customers (point price)'))),
                    for (final c in clients) DropdownMenuItem(value: vStr(c['id']), child: Text(vStr(c['name']))),
                  ],
                  onChanged: (v) => set(() => site = v),
                ),
                const SizedBox(height: 12),
                TextField(controller: name, decoration: InputDecoration(labelText: tx(ctx, 'اسم التَذكَرة *', 'Ticket name *'), hintText: 'VALET 50 AED')),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'TICKET', label: Text(tx(ctx, 'سِعر ثابِت', 'Fixed price'))),
                    ButtonSegment(value: 'HOURLY', label: Text(tx(ctx, 'بِالسّاعة', 'Per hour'))),
                  ],
                  selected: {mode},
                  onSelectionChanged: (v) => set(() => mode = v.first),
                ),
                if (mode == 'HOURLY') ...[
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: TextField(controller: start, decoration: InputDecoration(labelText: tx(ctx, 'مِن ساعة', 'From hour')))),
                    const SizedBox(width: 12),
                    Expanded(child: TextField(controller: finish, decoration: InputDecoration(labelText: tx(ctx, 'إلى ساعة', 'To hour')))),
                  ]),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: total,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: tx(ctx, 'الإجماليّ شامِل الضَريبة (AED) *', 'Total incl. VAT (AED) *'),
                    helperText: '${VF.money(price)} + VAT ${VF.money(t - price)}',
                  ),
                  onChanged: (_) => set(() {}),
                ),
                const SizedBox(height: 12),
                TextField(controller: notes, decoration: InputDecoration(labelText: tx(ctx, 'مُلاحَظات', 'Notes'))),
                SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(tx(ctx, 'فَعّال', 'Active')), value: active, onChanged: (v) => set(() => active = v)),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tx(ctx, 'إلغاء', 'Cancel'))),
            FilledButton(
              onPressed: () async {
                final tt = num.tryParse(total.text);
                if (name.text.trim().isEmpty || tt == null) {
                  vToast(ctx, tx(ctx, 'أَدخِل الاسم وَالإجماليّ.', 'Enter the name and the total.'), error: true);
                  return;
                }
                final pr = double.parse((tt / (1 + vatRate)).toStringAsFixed(2));
                Navigator.pop(ctx);
                await _save('vva_price_save', {
                  'p_data': {
                    if (p != null) 'id': p['id'],
                    'point_id': widget.pointId,
                    'site_id': site ?? '',
                    'ticket_name': name.text.trim(),
                    'ticket_mode': mode,
                    'start_time': mode == 'HOURLY' ? start.text.trim() : '0:00',
                    'finish_time': mode == 'HOURLY' ? finish.text.trim() : 'Infinity',
                    'payment_mode': vStr(p?['payment_mode']).isEmpty ? 'BASE_ONCE' : vStr(p?['payment_mode']),
                    'price': pr,
                    'tax': double.parse((tt - pr).toStringAsFixed(2)),
                    'total': tt,
                    'is_active': active,
                    'notes': notes.text.trim(),
                  },
                });
              },
              child: Text(tx(ctx, 'حِفظ', 'Save')),
            ),
          ],
        );
      }),
    );
  }

  // ---------------------------------------------------------------- VIP + plans
  Widget _vipPlans(VJson d) {
    final vipFields = [('ticket_name', tx(context, 'الاسم', 'Name'), false), ('ticket_price', tx(context, 'السِعر (AED)', 'Price (AED)'), true)];
    final planFields = [('name', tx(context, 'الاسم', 'Name'), false), ('price', tx(context, 'السِعر (AED)', 'Price (AED)'), true)];
    return _page([
      VPanel(
        title: tx(context, 'أَسعار VIP', 'VIP prices'),
        actions: [if (_edit) FilledButton.icon(icon: const Icon(Icons.add), label: Text(tx(context, 'إضافة', 'Add')), onPressed: () => _simple('vip_price', null, vipFields))],
        child: VTable(
          columns: [
            DataColumn(label: Text(tx(context, 'الاسم', 'Name'))),
            DataColumn(label: Text(tx(context, 'السِعر', 'Price')), numeric: true),
            DataColumn(label: Text(tx(context, 'الحالة', 'Status'))),
            const DataColumn(label: Text('')),
          ],
          rows: [
            for (final v in vList(d['vip_prices']))
              DataRow(cells: [
                DataCell(Text(vStr(v['ticket_name']))),
                DataCell(Text(VF.money(vNum(v['ticket_price'])))),
                DataCell(vBool(v['is_active']) ? VPill(tx(context, 'فَعّال', 'Active'), color: VC.ok) : VPill(tx(context, 'مُتَوَقِّف', 'Off'))),
                DataCell(_rowActions('vip_price', v, vipFields)),
              ]),
          ],
        ),
      ),
      VPanel(
        title: tx(context, 'باقات العُضويّة', 'Membership plans'),
        actions: [if (_edit) FilledButton.icon(icon: const Icon(Icons.add), label: Text(tx(context, 'إضافة', 'Add')), onPressed: () => _simple('member_plan', null, planFields))],
        child: VTable(
          columns: [
            DataColumn(label: Text(tx(context, 'الاسم', 'Name'))),
            DataColumn(label: Text(tx(context, 'السِعر', 'Price')), numeric: true),
            const DataColumn(label: Text('')),
          ],
          rows: [
            for (final m in vList(d['member_plans']))
              DataRow(cells: [
                DataCell(Text(vStr(m['name']))),
                DataCell(Text(VF.money(vNum(m['price'])))),
                DataCell(_rowActions('member_plan', m, planFields)),
              ]),
          ],
        ),
      ),
    ]);
  }

  // ---------------------------------------------------------------- parking
  Widget _parking(VJson d) {
    final fields = [
      ('name', tx(context, 'الاسم', 'Name'), false),
      ('capacity', tx(context, 'السَعة (سَيّارات)', 'Capacity (cars)'), true),
      ('notes', tx(context, 'مُلاحَظات', 'Notes'), false),
    ];
    return _page([
      VPanel(
        title: tx(context, 'المَواقِف', 'Parking areas'),
        actions: [if (_edit) FilledButton.icon(icon: const Icon(Icons.add), label: Text(tx(context, 'إضافة', 'Add')), onPressed: () => _simple('parking_area', null, fields))],
        child: VTable(
          columns: [
            DataColumn(label: Text(tx(context, 'الاسم', 'Name'))),
            DataColumn(label: Text(tx(context, 'السَعة', 'Capacity')), numeric: true),
            DataColumn(label: Text(tx(context, 'مُلاحَظات', 'Notes'))),
            DataColumn(label: Text(tx(context, 'الحالة', 'Status'))),
            const DataColumn(label: Text('')),
          ],
          rows: [
            for (final a in vList(d['parking_areas']))
              DataRow(cells: [
                DataCell(Text(vStr(a['name']))),
                DataCell(Text(vStr(a['capacity']))),
                DataCell(Text(vStr(a['notes']))),
                DataCell(vBool(a['approved']) ? VPill(tx(context, 'مُستَخدَم', 'In use'), color: VC.ok) : VPill(tx(context, 'مُتَوَقِّف', 'Off'))),
                DataCell(_rowActions('parking_area', a, fields, activeKey: 'approved')),
              ]),
          ],
        ),
      ),
    ]);
  }

  Widget _rowActions(String kind, VJson row, List<(String, String, bool)> fields, {String activeKey = 'is_active'}) {
    if (!_edit) return const SizedBox();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (row.containsKey(activeKey))
        Switch(
          value: vBool(row[activeKey]),
          onChanged: (v) => _save('vva_item_save', {
            'p_kind': kind,
            'p_data': {'id': row['id'], 'point_id': widget.pointId, activeKey: v},
          }),
        ),
      IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _simple(kind, row, fields)),
      IconButton(
        icon: const Icon(Icons.delete_outline, color: VC.bad),
        onPressed: () async {
          if (await vConfirm(context, tx(context, 'حَذف', 'Delete'), '${row['name'] ?? row['ticket_name']}')) {
            if (!mounted) return;
            _save('vva_row_delete', {'p_kind': kind, 'p_id': row['id']}, ok: tx(context, 'تَمّ الحَذف.', 'Deleted.'));
          }
        },
      ),
    ]);
  }

  Future<void> _simple(String kind, VJson? row, List<(String, String, bool)> fields) async {
    final ctrls = {for (final f in fields) f.$1: TextEditingController(text: row == null ? '' : vStr(row[f.$1]))};
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(row == null ? tx(ctx, 'إضافة', 'Add') : tx(ctx, 'تَعديل', 'Edit')),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final f in fields)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: ctrls[f.$1],
                  keyboardType: f.$3 ? const TextInputType.numberWithOptions(decimal: true) : null,
                  decoration: InputDecoration(labelText: f.$2),
                ),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tx(ctx, 'إلغاء', 'Cancel'))),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _save('vva_item_save', {
                'p_kind': kind,
                'p_data': {
                  if (row != null) 'id': row['id'],
                  'point_id': widget.pointId,
                  for (final f in fields) f.$1: f.$3 ? (num.tryParse(ctrls[f.$1]!.text) ?? 0) : ctrls[f.$1]!.text.trim(),
                },
              });
            },
            child: Text(tx(ctx, 'حِفظ', 'Save')),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- device account
  Widget _terminal(VJson d) {
    final t = d['terminal'] == null ? null : vMap(d['terminal']);
    final user = TextEditingController(text: vStr(t?['username']));
    final pass = TextEditingController();
    bool active = t == null ? true : vBool(t['active']);
    return _page([
      VPanel(
        title: tx(context, 'حِساب الجِهاز (دُخول النُقطة)', 'Device account (point login)'),
        child: StatefulBuilder(
          builder: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              t == null
                  ? tx(context, 'لا يُوجَد حِساب: الأَجهِزة لا تَستَطيع الدُخول لِهذه النُقطة. أَنشِئه هُنا.',
                      'No account yet: devices cannot sign in to this point. Create one below.')
                  : tx(context, 'تَغيير كَلِمة المُرور أَو إيقاف الحِساب يُخرِج كُلّ أَجهِزة النُقطة.',
                      'Changing the password or turning the account off signs out every device of the point.'),
              style: const TextStyle(color: VC.muted),
            ),
            const SizedBox(height: 14),
            Wrap(spacing: 14, runSpacing: 14, crossAxisAlignment: WrapCrossAlignment.center, children: [
              SizedBox(width: 260, child: TextField(controller: user, enabled: _edit, decoration: InputDecoration(labelText: tx(context, 'اسم المُستَخدِم', 'User name')))),
              SizedBox(
                width: 260,
                child: TextField(
                  controller: pass,
                  enabled: _edit,
                  decoration: InputDecoration(
                      labelText: t == null ? tx(context, 'كَلِمة المُرور *', 'Password *') : tx(context, 'كَلِمة مُرور جَديدة (اترُكها فارِغة)', 'New password (leave empty to keep)')),
                ),
              ),
              if (t != null)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Switch(value: active, onChanged: !_edit ? null : (v) => set(() => active = v)),
                  Text(active ? tx(context, 'فَعّال', 'Active') : tx(context, 'مُتَوَقِّف', 'Off')),
                ]),
              if (_edit)
                FilledButton.icon(
                  icon: const Icon(Icons.save_outlined),
                  label: Text(t == null ? tx(context, 'إنشاء الحِساب', 'Create account') : tx(context, 'حِفظ', 'Save')),
                  onPressed: () => _save('vva_terminal_save', {
                    'p_point': widget.pointId,
                    'p_username': user.text.trim(),
                    'p_password': pass.text,
                    'p_active': active,
                  }),
                ),
            ]),
          ]),
        ),
      ),
    ]);
  }

  // ---------------------------------------------------------------- equipment + books
  Widget _equipment(VJson d) {
    final e = vMap(d['equipment']);
    final keys = [('podium', 'بوديوم', 'Podium'), ('tablet', 'تابلت', 'Tablet'), ('printer', 'طابِعة', 'Printer'), ('umbrella', 'مِظَلّة', 'Umbrella')];
    final ctrls = {for (final k in [...keys.map((x) => x.$1), 'phone_number']) k: TextEditingController(text: vStr(e[k]))};
    final from = TextEditingController();
    final to = TextEditingController();
    return _page([
      VPanel(
        title: tx(context, 'مُعِدّات المَوقِع', 'Equipment on site'),
        actions: [
          if (_edit)
            FilledButton.icon(
              icon: const Icon(Icons.save_outlined),
              label: Text(tx(context, 'حِفظ', 'Save')),
              onPressed: () => _save('vva_item_save', {
                'p_kind': 'equipment',
                'p_data': {
                  'point_id': widget.pointId,
                  for (final k in keys) k.$1: int.tryParse(ctrls[k.$1]!.text) ?? 0,
                  'phone_number': ctrls['phone_number']!.text.trim(),
                },
              }),
            ),
        ],
        child: Wrap(spacing: 14, runSpacing: 14, children: [
          for (final k in keys)
            SizedBox(width: 130, child: TextField(controller: ctrls[k.$1], enabled: _edit, decoration: InputDecoration(labelText: tx(context, k.$2, k.$3)))),
          SizedBox(width: 200, child: TextField(controller: ctrls['phone_number'], enabled: _edit, decoration: InputDecoration(labelText: tx(context, 'هاتِف المَوقِع', 'Site phone')))),
        ]),
      ),
      VPanel(
        title: tx(context, 'دَفاتِر التَذاكِر اليَدَويّة', 'Manual ticket books'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (_edit)
            Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
              SizedBox(width: 130, child: TextField(controller: from, decoration: InputDecoration(labelText: tx(context, 'مِن رَقم', 'From no.')))),
              SizedBox(width: 130, child: TextField(controller: to, decoration: InputDecoration(labelText: tx(context, 'إلى رَقم', 'To no.')))),
              OutlinedButton.icon(
                icon: const Icon(Icons.add),
                label: Text(tx(context, 'إضافة دَفتَر', 'Add book')),
                onPressed: () => _save('vva_item_save', {
                  'p_kind': 'manual_book',
                  'p_data': {'point_id': widget.pointId, 'ticket_from': int.tryParse(from.text), 'ticket_to': int.tryParse(to.text)},
                }),
              ),
            ]),
          const SizedBox(height: 10),
          VTable(
            columns: [
              DataColumn(label: Text(tx(context, 'مِن', 'From'))),
              DataColumn(label: Text(tx(context, 'إلى', 'To'))),
              DataColumn(label: Text(tx(context, 'أُضيف', 'Added'))),
              const DataColumn(label: Text('')),
            ],
            rows: [
              for (final b in vList(d['manual_books']))
                DataRow(cells: [
                  DataCell(Text(vStr(b['ticket_from']))),
                  DataCell(Text(vStr(b['ticket_to']))),
                  DataCell(Text(VF.date(vTime(b['created_at'])))),
                  DataCell(!_edit
                      ? const SizedBox()
                      : IconButton(
                          icon: const Icon(Icons.delete_outline, color: VC.bad),
                          onPressed: () async {
                            if (await vConfirm(context, tx(context, 'حَذف الدَفتَر', 'Delete book'), '${b['ticket_from']} – ${b['ticket_to']}')) {
                              if (!mounted) return;
                              _save('vva_row_delete', {'p_kind': 'manual_book', 'p_id': b['id']}, ok: tx(context, 'تَمّ الحَذف.', 'Deleted.'));
                            }
                          },
                        )),
                ]),
            ],
          ),
        ]),
      ),
    ]);
  }
}
