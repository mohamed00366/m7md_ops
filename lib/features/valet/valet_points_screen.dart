import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'valet_admin.dart';
import 'valet_hourly.dart';
import 'valet_parking_screen.dart';
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
          bottom: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              indicatorColor: VC.gold,
              tabs: [
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
        ('stamp_ticket', 'تَذاكِر الخَتم', 'Stamp tickets', 'زِرّ في شاشة الدَفع: تَذكَرة مَجّانيّة بِصورة خَتم العَميل', 'Check-out button: free ticket with a stamp photo'),
        ('valet_validate', 'زِرّ "Validate for a client"', '"Validate for a client" button', 'في شاشة الدَفع: المُوَظَّف يَعمَل فاليديشن لِعَميل', 'On the check-out screen: the staff validates for a client'),
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

  static const _flagIcons = <String, IconData>{
    'car_request': Icons.directions_car_filled_outlined,
    'key_rack_w_sites_or_allow': Icons.key_outlined,
    'sinin_w_card': Icons.password_rounded,
    'paid_first_or_paid_after': Icons.payments_outlined,
    'price_group_customer': Icons.sell_outlined,
    'stamp_ticket': Icons.approval_outlined,
    'valet_validate': Icons.verified_outlined,
    'photo_in_out': Icons.photo_camera_outlined,
    'nfc_qr_in_out': Icons.nfc_rounded,
    'used_card_manual': Icons.qr_code_scanner_rounded,
    'drivers_in': Icons.login_rounded,
    'drivers_out': Icons.logout_rounded,
    'parking_in_out': Icons.local_parking_rounded,
    'dropdown_parkingcar': Icons.format_list_bulleted_rounded,
    'dropdown_time_in_out': Icons.schedule_rounded,
    'drivers_nfc_qr': Icons.badge_outlined,
    'show_membership': Icons.card_membership_outlined,
    'member_card_normal': Icons.credit_card_outlined,
    'member_card_gold': Icons.workspace_premium_outlined,
    'paid_with_app_or_keyrack': Icons.point_of_sale_outlined,
  };

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
                secondary: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: (vBool(s[f.$1]) ? VC.gold : VC.muted).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(_flagIcons[f.$1] ?? Icons.tune_rounded, size: 20, color: vBool(s[f.$1]) ? VC.gold : VC.muted),
                ),
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
                },
              }),
            ),
        ],
        child: Wrap(spacing: 14, runSpacing: 14, children: [
          _field(prefix, tx(context, 'بادِئة التَذكَرة', 'Ticket prefix'), help: 'T-0001-PREFIX-26', width: 220),
          SizedBox(
            width: 200,
            child: TextField(
              controller: vat,
              enabled: false,
              decoration: InputDecoration(
                isDense: true,
                labelText: tx(context, 'الضَريبة %', 'VAT %'),
                helperText: tx(context, 'مِن إعدادات الدَولة', 'From the country settings'),
              ),
            ),
          ),
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
      _branchesPanel(d),
    ]);
  }

  static String? _visitorId(VJson d) {
    for (final c in vList(d['clients'])) {
      if (c['system_kind'] == 'visitor') return vStr(c['id']);
    }
    return null;
  }

  static String _branchLabel(BuildContext ctx, VJson c) => switch (c['system_kind']) {
        'visitor' => '${vStr(c['name'])}  ·  ${tx(ctx, 'افتِراضيّ', 'default')}',
        'vip' => '${vStr(c['name'])}  ·  ${tx(ctx, 'زِرّ VIP', 'VIP switch')}',
        _ => vStr(c['name']),
      };

  /// Branches of the point in display order (Visitor / VIP are system branches linked to every point).
  Widget _branchesPanel(VJson d) {
    final list = vList(d['clients']);
    Future<void> move(int i, int by) async {
      final ids = [for (final c in list) vStr(c['id'])];
      final j = i + by;
      if (j < 0 || j >= ids.length) return;
      final t = ids[i];
      ids[i] = ids[j];
      ids[j] = t;
      await _save('vva_client_sort_save', {'p_point': widget.pointId, 'p_order': ids});
    }

    return VPanel(
      title: tx(context, 'فُروع هذه النُقطة · تَرتيب الظُهور', 'Branches at this point · display order'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          tx(context,
              'التَذكَرة الجَديدة تَبدأ على Visitor ولا يُغَيِّرها المُوَظَّف؛ عِند عَمَل فاليديشن مِن تَطبيق العُمَلاء تَتَحَوَّل إلى الفَرع الّذي قام بها وبِسِعره. VIP يَظهَر في التَطبيق فَقَط إذا كان له سِعر في هذه النُقطة. ضَع أَسعار Visitor وVIP لِكُلّ نُقطة مِن تَبويب "الأَسعار".',
              'A new ticket starts on Visitor and the staff cannot change it; a validation from the customer app moves it to that branch and its price. VIP shows in the app only when it has a price at this point. Set the Visitor and VIP prices of each point in the "Prices" tab.'),
          style: const TextStyle(color: VC.muted, fontSize: 12.5),
        ),
        const SizedBox(height: 10),
        if (list.isEmpty)
          Text(tx(context, 'لا يُوجَد فَرع مَربوط.', 'No branch is linked.'), style: const TextStyle(color: VC.muted))
        else
          for (var i = 0; i < list.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                SizedBox(width: 28, child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w700, color: VC.muted))),
                Icon(
                    switch (list[i]['system_kind']) {
                      'visitor' => Icons.directions_walk,
                      'vip' => Icons.workspace_premium_outlined,
                      _ => Icons.storefront_outlined,
                    },
                    size: 18,
                    color: list[i]['system_kind'] == null ? VC.muted : VC.gold),
                const SizedBox(width: 8),
                Expanded(child: Text(vStr(list[i]['name']), style: const TextStyle(fontWeight: FontWeight.w600))),
                if (list[i]['system_kind'] == 'visitor') VPill(tx(context, 'افتِراضيّ', 'Default'), color: VC.ok),
                if (list[i]['system_kind'] == 'vip') const VPill('VIP', color: VC.gold),
                if (list[i]['system_kind'] == null)
                  VPill(vBool(list[i]['approved']) ? tx(context, 'مُعتَمَد', 'Approved') : tx(context, 'غَير مُعتَمَد', 'Not approved'),
                      color: vBool(list[i]['approved']) ? VC.ok : VC.muted),
                if (_edit) ...[
                  const SizedBox(width: 6),
                  IconButton(
                      tooltip: tx(context, 'أَعلى', 'Up'),
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.arrow_upward, size: 18),
                      onPressed: i == 0 ? null : () => move(i, -1)),
                  IconButton(
                      tooltip: tx(context, 'أَسفَل', 'Down'),
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.arrow_downward, size: 18),
                      onPressed: i == list.length - 1 ? null : () => move(i, 1)),
                ],
              ]),
            ),
      ]),
    );
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
  /// Hourly rows grouped into tables: same client + ticket name + days.
  static List<List<VJson>> hourlyTables(List<VJson> prices) {
    final m = <String, List<VJson>>{};
    for (final p in prices.where((p) => p['ticket_mode'] == 'HOURLY')) {
      final key = '${p['site_id'] ?? ''}|${vStr(p['ticket_name']).trim()}|${vDays(p['days']).join(',')}';
      m.putIfAbsent(key, () => []).add(p);
    }
    for (final g in m.values) {
      g.sort((a, b) => vMinutes(vStr(a['start_time'])).compareTo(vMinutes(vStr(b['start_time']))));
    }
    final out = m.values.toList()
      ..sort((a, b) {
        final c = vStr(a.first['client_name']).compareTo(vStr(b.first['client_name']));
        if (c != 0) return c;
        final n = vStr(a.first['ticket_name']).compareTo(vStr(b.first['ticket_name']));
        if (n != 0) return n;
        final da = vDays(a.first['days']), db = vDays(b.first['days']);
        return (da.isEmpty ? 0 : da.first).compareTo(db.isEmpty ? 0 : db.first);
      });
    return out;
  }

  Widget _prices(VJson d) {
    final prices = vList(d['prices']);
    final fixed = prices.where((p) => p['ticket_mode'] != 'HOURLY').toList();
    final tables = hourlyTables(prices);
    String forWhom(VJson p) => p['client_name'] == null ? tx(context, 'الكُلّ (سِعر النُقطة)', 'All (point price)') : vStr(p['client_name']);
    Widget actions(VJson p, VoidCallback onEdit, Future<void> Function() onDelete) => !_edit
        ? const SizedBox()
        : Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(tooltip: tx(context, 'تَعديل', 'Edit'), icon: const Icon(Icons.edit_outlined), onPressed: onEdit),
            IconButton(tooltip: tx(context, 'حَذف', 'Delete'), icon: const Icon(Icons.delete_outline, color: VC.bad), onPressed: onDelete),
          ]);
    return _page([
      VPanel(
        title: tx(context, 'أَسعار ثابِتة (${fixed.length})', 'Fixed prices (${fixed.length})'),
        actions: [
          if (_edit) FilledButton.icon(icon: const Icon(Icons.add), label: Text(tx(context, 'سِعر ثابِت', 'Fixed price')), onPressed: () => _priceDialog(d, null)),
        ],
        child: VTable(
          empty: tx(context, 'لا تُوجَد أَسعار ثابِتة.', 'No fixed price.'),
          columns: [
            DataColumn(label: Text(tx(context, 'لِمَن', 'For'))),
            DataColumn(label: Text(tx(context, 'الاسم', 'Name'))),
            DataColumn(label: Text(tx(context, 'الأَيّام', 'Days'))),
            DataColumn(label: Text(tx(context, 'السِعر', 'Price')), numeric: true),
            DataColumn(label: Text(tx(context, 'الضَريبة', 'VAT')), numeric: true),
            DataColumn(label: Text(tx(context, 'الإجماليّ', 'Total')), numeric: true),
            DataColumn(label: Text(tx(context, 'الحالة', 'Status'))),
            const DataColumn(label: Text('')),
          ],
          rows: [
            for (final p in fixed)
              DataRow(cells: [
                DataCell(Text(forWhom(p))),
                DataCell(Text(vStr(p['ticket_name']), style: const TextStyle(fontWeight: FontWeight.w600))),
                DataCell(Text(vDaysLabel(context, p['days']), style: TextStyle(color: vDays(p['days']).isEmpty ? VC.muted : VC.warn))),
                DataCell(Text(VF.money(vNum(p['price'])))),
                DataCell(Text(VF.money(vNum(p['tax'])))),
                DataCell(Text(VF.money(vNum(p['total'])), style: const TextStyle(fontWeight: FontWeight.w700))),
                DataCell(vBool(p['is_active']) ? VPill(tx(context, 'فَعّال', 'Active'), color: VC.ok) : VPill(tx(context, 'مُتَوَقِّف', 'Off'))),
                DataCell(actions(p, () => _priceDialog(d, p), () async {
                  if (await vConfirm(context, tx(context, 'حَذف السِعر', 'Delete price'), '${p['ticket_name']}')) {
                    if (!mounted) return;
                    await _save('vva_row_delete', {'p_kind': 'price', 'p_id': p['id']}, ok: tx(context, 'تَمّ الحَذف.', 'Deleted.'));
                  }
                })),
              ]),
          ],
        ),
      ),
      VPanel(
        title: tx(context, 'جَداوِل بِالسّاعة (${tables.length})', 'Hourly tables (${tables.length})'),
        actions: [
          if (_edit) FilledButton.icon(icon: const Icon(Icons.add), label: Text(tx(context, 'جَدوَل بِالسّاعة', 'Hourly table')), onPressed: () => _hourlyDialog(d, null)),
        ],
        child: tables.isEmpty
            ? Padding(padding: const EdgeInsets.all(16), child: Text(tx(context, 'لا تُوجَد جَداوِل بِالسّاعة.', 'No hourly table.'), style: const TextStyle(color: VC.muted)))
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final g in tables)
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Row(children: [
                          const Icon(Icons.schedule, color: VC.gold),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                              Text(vStr(g.first['ticket_name']), style: const TextStyle(fontWeight: FontWeight.w700)),
                              VPill(forWhom(g.first)),
                              VPill(vDaysLabel(context, g.first['days']), color: vDays(g.first['days']).isEmpty ? VC.info : VC.warn, icon: Icons.calendar_month),
                              if (!vBool(g.first['is_active'])) VPill(tx(context, 'مُتَوَقِّف', 'Off')),
                            ]),
                          ),
                          actions(g.first, () => _hourlyDialog(d, g), () async {
                            if (await vConfirm(context, tx(context, 'حَذف الجَدوَل', 'Delete table'),
                                tx(context, '${g.first['ticket_name']} · ${vDaysLabel(context, g.first['days'])} — ${g.length} فَترة', '${g.first['ticket_name']} · ${vDaysLabel(context, g.first['days'])} — ${g.length} band(s)'))) {
                              if (!mounted) return;
                              for (final p in g.skip(1)) {
                                await ValetAdmin.I.call('vva_row_delete', {'p_kind': 'price', 'p_id': p['id']}).catchError((_) => <String, dynamic>{});
                              }
                              if (!mounted) return;
                              await _save('vva_row_delete', {'p_kind': 'price', 'p_id': g.first['id']}, ok: tx(context, 'تَمّ الحَذف.', 'Deleted.'));
                            }
                          }),
                        ]),
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final b in slabsToBands([
                            for (final p in g)
                              PriceSlab(
                                vMinutes(vStr(p['start_time'])),
                                vStr(p['finish_time']).isEmpty || vStr(p['finish_time']).toLowerCase().startsWith('inf')
                                    ? null
                                    : vMinutes(vStr(p['finish_time'])),
                                vNum(p['total']),
                              ),
                          ]))
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(border: Border.all(color: VC.muted.withValues(alpha: .35)), borderRadius: BorderRadius.circular(8)),
                              child: Text(
                                b.to == null
                                    ? tx(context, 'بَعد ${fmtMinutes(b.from)} س: ${VF.money(b.amount)} لِكُلّ ساعة', 'After ${fmtMinutes(b.from)} h: ${VF.money(b.amount)} per hour')
                                    : b.hourly
                                        ? tx(context, 'مِن ${fmtMinutes(b.from)} إلى ${fmtMinutes(b.to!)} س: ${VF.money(b.amount)} لِكُلّ ساعة',
                                            '${fmtMinutes(b.from)}–${fmtMinutes(b.to!)} h: ${VF.money(b.amount)} per hour')
                                        : tx(context, 'مِن ${fmtMinutes(b.from)} إلى ${fmtMinutes(b.to!)} س: +${VF.money(b.amount)}',
                                            '${fmtMinutes(b.from)}–${fmtMinutes(b.to!)} h: +${VF.money(b.amount)}'),
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                        ]),
                      ]),
                    ),
                  ),
              ]),
      ),
      Text(
        tx(context,
            'سِعر النُقطة ("الكُلّ") هو الذي يَظهَر عِند دُخول السَيّارة، وَبَعد الفاليديشن يَتَحَوَّل السِعر إلى سِعر العَميل (ثابِت أَو جَدوَل بِالسّاعة). '
                'جَدوَل بِالسّاعة = فَترات بِالسّاعات مِن دُخول السَيّارة (مَرّة واحِدة أَو لِكُلّ ساعة)، وَآخِرها مُمكِن "مَفتوح" لِكُلّ ساعة إضافيّة. '
                'اختَر أَيّام الأُسبوع لِجَدوَل خاصّ (مَثَلاً السَبت وَالأَحَد)؛ جَدوَل الأَيّام المُحَدَّدة يَغلِب جَدوَل "كُلّ الأَيّام" بِنَفس الاسم، وَاليَوم يُحسَب مِن وَقت دُخول السَيّارة.',
            'The point price ("All") applies when the car comes in; after a client validation the price becomes that client\'s price (fixed or hourly table). '
                'Hourly table = bands in hours since the car came in (once or every hour), the last one can be "open" for every extra hour. '
                'Pick days of the week for a special table (e.g. Saturday and Sunday); a table for given days wins over the "every day" table of the same name, and the day is the entry day of the car.'),
        style: const TextStyle(color: VC.muted),
      ),
    ]);
  }

  Future<void> _priceDialog(VJson d, VJson? p) async {
    final vatRate = _vat(d);
    final name = TextEditingController(text: vStr(p?['ticket_name']));
    bool incl = p == null ? true : (p['vat_included'] as bool? ?? true);
    final total = TextEditingController(text: p == null ? '' : vNum(incl ? p['total'] : p['price']).toString());
    final notes = TextEditingController(text: vStr(p?['notes']));
    String? site = (p?['site_id'] as String?) ?? _visitorId(d);
    bool active = p == null ? true : vBool(p['is_active']);
    final days = {...vDays(p?['days'])};
    final clients = vList(d['clients']);
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        return AlertDialog(
          title: Text(p == null ? tx(ctx, 'سِعر ثابِت جَديد', 'New fixed price') : tx(ctx, 'تَعديل السِعر', 'Edit price')),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _forField(ctx, clients, site, (v) => set(() => site = v)),
                const SizedBox(height: 12),
                TextField(controller: name, decoration: InputDecoration(labelText: tx(ctx, 'اسم التَذكَرة *', 'Ticket name *'), hintText: 'VALET 50 AED')),
                const SizedBox(height: 12),
                VatAmountField(
                  controller: total,
                  included: incl,
                  vatRate: vatRate,
                  label: tx(ctx, 'المَبلَغ (AED) *', 'Amount (AED) *'),
                  extra: tx(ctx, ' — 0 = مَجّاني', ' — 0 = free'),
                  onToggle: () => set(() => incl = !incl),
                  onChanged: () => set(() {}),
                ),
                const SizedBox(height: 12),
                _daysPicker(ctx, days, set),
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
                final amount = num.tryParse(total.text);
                if (name.text.trim().isEmpty || amount == null) {
                  vToast(ctx, tx(ctx, 'أَدخِل الاسم وَالمَبلَغ.', 'Enter the name and the amount.'), error: true);
                  return;
                }
                final (pr, tt) = vSplitVat(amount, vatRate, incl);
                Navigator.pop(ctx);
                await _save('vva_price_save', {
                  'p_data': {
                    if (p != null) 'id': p['id'],
                    'point_id': widget.pointId,
                    'site_id': site ?? '',
                    'ticket_name': name.text.trim(),
                    'ticket_mode': 'TICKET',
                    'days': (days.toList()..sort()),
                    'start_time': '0:00',
                    'finish_time': 'Infinity',
                    'payment_mode': vStr(p?['payment_mode']).isEmpty ? 'BASE_ONCE' : vStr(p?['payment_mode']),
                    'price': pr,
                    'tax': double.parse((tt - pr).toStringAsFixed(2)),
                    'total': tt,
                    'vat_included': incl,
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

  Widget _forField(BuildContext ctx, List<VJson> clients, String? site, ValueChanged<String?> onChanged) => DropdownButtonFormField<String?>(
        value: site,
        isExpanded: true,
        decoration: InputDecoration(labelText: tx(ctx, 'لِمَن', 'For')),
        items: [
          if (site == null) DropdownMenuItem(value: null, child: Text(tx(ctx, 'كُلّ العُمَلاء (سِعر النُقطة)', 'All customers (point price)'))),
          for (final c in clients) DropdownMenuItem(value: vStr(c['id']), child: Text(_branchLabel(ctx, c))),
        ],
        onChanged: onChanged,
      );

  Widget _daysPicker(BuildContext ctx, Set<int> days, StateSetter set) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(tx(ctx, 'أَيّام الأُسبوع', 'Days of the week'), style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            ChoiceChip(label: Text(tx(ctx, 'كُلّ الأَيّام', 'Every day')), selected: days.isEmpty, onSelected: (_) => set(days.clear)),
            for (final dd in const [6, 7, 1, 2, 3, 4, 5])
              FilterChip(
                label: Text(vDayName(ctx, dd)),
                selected: days.contains(dd),
                onSelected: (v) => set(() {
                  v ? days.add(dd) : days.remove(dd);
                  if (days.length == 7) days.clear();
                }),
              ),
          ]),
        ],
      );

  Widget _hourlyPreview(BuildContext ctx, List<PriceSlab> slabs) {
    final hours = [1, 2, 3, 4, 5, 6, 7, 8, 10, 12, 24, 30];
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: VC.gold.withValues(alpha: .08), borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tx(ctx, 'مُعايَنة: ما يَدفَعه العَميل إذا بَقِيَت السَيّارة… (شامِل الضَريبة)', 'Preview: what the customer pays if the car stays… (incl. VAT)'),
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
        const SizedBox(height: 6),
        Wrap(spacing: 12, runSpacing: 4, children: [
          for (final h in hours)
            Text('${tx(ctx, '$h س', '${h}h')} = ${VF.money(priceAt(slabs, h * 60 - 1))}', style: const TextStyle(fontSize: 12)),
        ]),
      ]),
    );
  }

  /// Editor of a whole hourly table: bands written as the manager thinks of them
  /// ("first 4 hours 10", "5th hour +20", "from 6 h: 10 every hour"), saved as the rows the app reads.
  Future<void> _hourlyDialog(VJson d, List<VJson>? g) async {
    final vatRate = _vat(d);
    final first = g?.first;
    final name = TextEditingController(text: first == null ? 'HOURLY' : vStr(first['ticket_name']));
    final notes = TextEditingController(text: vStr(first?['notes']));
    String? site = (first?['site_id'] as String?) ?? _visitorId(d);
    bool active = first == null ? true : vBool(first['is_active']);
    final days = {...vDays(first?['days'])};
    // saved rows -> bands (amounts incl. VAT), then each band shown the way it was typed
    final saved = g ?? const <VJson>[];
    final loaded = slabsToBands([
      for (final p in saved)
        PriceSlab(
          vMinutes(vStr(p['start_time'])),
          vStr(p['finish_time']).isEmpty || vStr(p['finish_time']).toLowerCase().startsWith('inf') ? null : vMinutes(vStr(p['finish_time'])),
          vNum(p['total']),
        ),
    ]);
    bool inclOf(HourBand b) {
      for (final p in saved) {
        if (vMinutes(vStr(p['start_time'])) >= b.from) return p['vat_included'] as bool? ?? true;
      }
      return true;
    }

    // one editable row per band: (to, amount, per hour?, VAT included?)
    final rows = <(TextEditingController, TextEditingController, ValueNotifier<bool>, ValueNotifier<bool>)>[
      for (final b in loaded)
        () {
          final inc = inclOf(b);
          final shown = inc ? b.amount : vNum((b.amount / (1 + vatRate)).toStringAsFixed(2));
          return (
            TextEditingController(text: b.to == null ? tx(context, 'مَفتوح', 'Open') : fmtMinutes(b.to!)),
            TextEditingController(text: '$shown'),
            ValueNotifier(b.hourly),
            ValueNotifier(inc),
          );
        }(),
    ];
    if (rows.isEmpty) {
      rows.add((TextEditingController(text: '4'), TextEditingController(), ValueNotifier(false), ValueNotifier(true)));
      rows.add((TextEditingController(text: tx(context, 'مَفتوح', 'Open')), TextEditingController(), ValueNotifier(true), ValueNotifier(true)));
    }
    final clients = vList(d['clients']);

    // bands from the rows; error text when something is wrong
    (List<HourBand>, String?) read() {
      final out = <HourBand>[];
      var from = 0;
      for (var i = 0; i < rows.length; i++) {
        final last = i == rows.length - 1;
        final to = parseBandTime(rows[i].$1.text, allowOpen: last);
        final amount = num.tryParse(rows[i].$2.text.trim());
        if (to == -1) return (out, tx(context, 'السَطر ${i + 1}: "إلى" غَير صَحيح.', 'Row ${i + 1}: wrong "to".'));
        if (to != null && to <= from) return (out, tx(context, 'السَطر ${i + 1}: "إلى" يَجِب أَن يَكون بَعد ${fmtMinutes(from)}.', 'Row ${i + 1}: "to" must be after ${fmtMinutes(from)}.'));
        if (amount == null) return (out, tx(context, 'السَطر ${i + 1}: أَدخِل المَبلَغ (0 = مَجّاني).', 'Row ${i + 1}: enter the amount (0 = free).'));
        // bands are computed with amounts INCLUDING VAT
        final incAmount = rows[i].$4.value ? amount : vSplitVat(amount, vatRate, false).$2;
        out.add(HourBand(from: from, to: to, amount: incAmount, hourly: to == null ? true : rows[i].$3.value));
        if (to == null) break;
        from = to;
      }
      return (out, null);
    }

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final (bands, err) = read();
        final slabs = bandsToSlabs(bands);
        // start of every row = end of the row before (computed before building the rows)
        final froms = <int>[];
        var f0 = 0;
        for (var i = 0; i < rows.length; i++) {
          froms.add(f0);
          final t = parseBandTime(rows[i].$1.text, allowOpen: i == rows.length - 1);
          if (t != null && t > f0) f0 = t;
        }
        return AlertDialog(
          title: Text(g == null ? tx(ctx, 'جَدوَل بِالسّاعة جَديد', 'New hourly table') : tx(ctx, 'تَعديل جَدوَل بِالسّاعة', 'Edit hourly table')),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _forField(ctx, clients, site, (v) => set(() => site = v)),
                const SizedBox(height: 12),
                TextField(controller: name, decoration: InputDecoration(labelText: tx(ctx, 'اسم التَذكَرة *', 'Ticket name *'), hintText: 'HOURLY')),
                const SizedBox(height: 14),
                _daysPicker(ctx, days, set),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                    child: Text(tx(ctx, 'الفَترات — بِالسّاعات مِن دُخول السَيّارة', 'Bands — hours since the car came in'),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: Text(tx(ctx, 'فَترة', 'Band')),
                    onPressed: () => set(() {
                      // the old last row becomes finite, the new row is the last one
                      final last = rows.last;
                      if (parseBandTime(last.$1.text, allowOpen: true) == null) {
                        final f = bands.isEmpty ? 0 : bands.last.from;
                        last.$1.text = fmtMinutes(f + 60);
                        last.$3.value = false;
                      }
                      rows.add((TextEditingController(text: tx(ctx, 'مَفتوح', 'Open')), TextEditingController(), ValueNotifier(true), ValueNotifier(last.$4.value)));
                    }),
                  ),
                ]),
                for (var i = 0; i < rows.length; i++)
                  Builder(builder: (_) {
                    final last = i == rows.length - 1;
                    final rowFrom = froms[i];
                    final to = parseBandTime(rows[i].$1.text, allowOpen: last);
                    final open = last && to == null;
                    return Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        SizedBox(
                          width: 86,
                          child: InputDecorator(
                            decoration: InputDecoration(isDense: true, labelText: tx(ctx, 'مِن', 'From')),
                            child: Text(rowFrom == 0 ? tx(ctx, 'الدُخول', 'Entry') : tx(ctx, '${fmtMinutes(rowFrom)} س', '${fmtMinutes(rowFrom)} h')),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 3,
                          child: BandTimeField(
                            controller: rows[i].$1,
                            label: tx(ctx, 'إلى (ساعات)', 'To (hours)'),
                            allowOpen: last,
                            onChanged: () => set(() {}),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 4,
                          child: VatAmountField(
                            controller: rows[i].$2,
                            included: rows[i].$4.value,
                            vatRate: vatRate,
                            dense: true,
                            label: tx(ctx, 'المَبلَغ', 'Amount'),
                            onToggle: () => set(() => rows[i].$4.value = !rows[i].$4.value),
                            onChanged: () => set(() {}),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 3,
                          child: open
                              ? InputDecorator(
                                  decoration: InputDecoration(isDense: true, labelText: tx(ctx, 'الطَريقة', 'How')),
                                  child: Text(tx(ctx, 'لِكُلّ ساعة إضافيّة', 'Every extra hour')),
                                )
                              : DropdownButtonFormField<bool>(
                                  value: rows[i].$3.value,
                                  isExpanded: true,
                                  decoration: InputDecoration(isDense: true, labelText: tx(ctx, 'الطَريقة', 'How')),
                                  items: [
                                    DropdownMenuItem(value: false, child: Text(tx(ctx, 'مَرّة واحِدة لِلفَترة', 'Once for the band'))),
                                    DropdownMenuItem(value: true, child: Text(tx(ctx, 'لِكُلّ ساعة في الفَترة', 'Every hour of the band'))),
                                  ],
                                  onChanged: (v) => set(() => rows[i].$3.value = v ?? false),
                                ),
                        ),
                        IconButton(
                          tooltip: tx(ctx, 'حَذف', 'Remove'),
                          icon: const Icon(Icons.close, color: VC.bad),
                          onPressed: rows.length == 1 ? null : () => set(() => rows.removeAt(i)),
                        ),
                      ]),
                    );
                  }),
                const SizedBox(height: 8),
                Text(
                  tx(ctx,
                      'اكتُب الساعة أَو اختَرها مِن القائِمة ▾. "مِن" تُؤخَذ تِلقائيّاً مِن نِهاية الفَترة السابِقة.\n'
                          '• مَرّة واحِدة: يُضاف المَبلَغ مَرّة إذا وَصَلَت السَيّارة لِهذه الفَترة.\n'
                          '• لِكُلّ ساعة: يُضاف المَبلَغ عَن كُلّ ساعة (أَو جُزء مِنها) داخِل الفَترة.\n'
                          '• مَفتوح (آخِر سَطر فَقَط): بَعد هذه الساعة يُضاف المَبلَغ عَن كُلّ ساعة بِلا نِهاية.\n'
                          '• نِهاية اليَوم = 24 ساعة. إذا لَم يَكُن آخِر سَطر مَفتوحاً يَبقى السِعر ثابِتاً بَعدَه.\n'
                          'مِثالك: إلى 4 = 10 مَرّة · إلى 5 = 20 مَرّة · إلى 6 = 5 مَرّة · مَفتوح = 10 لِكُلّ ساعة.',
                      'Type the hour or pick it from the list ▾. "From" is taken from the end of the previous band.\n'
                          '• Once: the amount is added once when the car reaches this band.\n'
                          '• Every hour: the amount is added for every (started) hour inside the band.\n'
                          '• Open (last row only): after this hour, the amount for every extra hour, no end.\n'
                          '• End of day = 24 h. If the last row is not open the price stays the same after it.\n'
                          'Example: to 4 = 10 once · to 5 = 20 once · to 6 = 5 once · open = 10 every hour.'),
                  style: const TextStyle(color: VC.muted, fontSize: 12, height: 1.5),
                ),
                if (err != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(err, style: const TextStyle(color: VC.bad))),
                const SizedBox(height: 8),
                _hourlyPreview(ctx, slabs),
                const SizedBox(height: 8),
                TextField(controller: notes, decoration: InputDecoration(labelText: tx(ctx, 'مُلاحَظات', 'Notes'))),
                SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(tx(ctx, 'فَعّال', 'Active')), value: active, onChanged: (v) => set(() => active = v)),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tx(ctx, 'إلغاء', 'Cancel'))),
            FilledButton(
              onPressed: () async {
                final (bands, err) = read();
                if (err != null || bands.isEmpty) {
                  vToast(ctx, err ?? tx(ctx, 'أَضِف فَترة.', 'Add a band.'), error: true);
                  return;
                }
                if (name.text.trim().isEmpty) {
                  vToast(ctx, tx(ctx, 'أَدخِل اسم التَذكَرة.', 'Enter the ticket name.'), error: true);
                  return;
                }
                bool bandIncl(int from) {
                  var f = 0;
                  for (var i = 0; i < rows.length; i++) {
                    final t = parseBandTime(rows[i].$1.text, allowOpen: i == rows.length - 1);
                    if (t == null || from < t) return rows[i].$4.value;
                    f = t;
                  }
                  return f >= 0 ? rows.last.$4.value : true;
                }
                final out = [
                  for (final s in bandsToSlabs(bands))
                    () {
                      final (pr, tt) = vSplitVat(s.total, vatRate, true);
                      return {
                        'start_time': slabTime(s.from),
                        'finish_time': s.to == null ? 'Infinity' : slabTime(s.to!),
                        'price': pr,
                        'tax': double.parse((tt - pr).toStringAsFixed(2)),
                        'total': tt,
                        'vat_included': bandIncl(s.from),
                      };
                    }(),
                ];
                Navigator.pop(ctx);
                await _save('vva_price_table_save', {
                  'p_data': {
                    'point_id': widget.pointId,
                    'site_id': site ?? '',
                    'ticket_name': name.text.trim(),
                    'days': (days.toList()..sort()),
                    'is_active': active,
                    'notes': notes.text.trim(),
                    'old_ids': [for (final p in g ?? const <VJson>[]) p['id']],
                    'bands': out,
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
      if (vList(d['vip_prices']).isEmpty)
        VPanel(
          title: tx(context, 'أَسعار VIP', 'VIP prices'),
          child: Text(
              tx(context, 'أَسعار VIP أَصبَحَت أَسعار فَرع VIP في تَبويب "الأَسعار" (ثابِت أَو بِالساعة، لِكُلّ نُقطة).',
                  'VIP prices are now the prices of the VIP branch in the "Prices" tab (fixed or hourly, per point).'),
              style: const TextStyle(color: VC.muted)),
        )
      else
      VPanel(
        title: tx(context, 'أَسعار VIP (قَديمة)', 'VIP prices (old)'),
        actions: [if (_edit) FilledButton.icon(icon: const Icon(Icons.add), label: Text(tx(context, 'إضافة', 'Add')), onPressed: () => _simple('vip_price', null, vipFields))],
        child: VTable(
          columns: [
            DataColumn(label: Text(tx(context, 'الاسم', 'Name'))),
            DataColumn(label: Text(tx(context, 'السِعر', 'Price')), numeric: true),
            DataColumn(label: Text(tx(context, 'الضَريبة', 'VAT')), numeric: true),
            DataColumn(label: Text(tx(context, 'الإجماليّ', 'Total')), numeric: true),
            DataColumn(label: Text(tx(context, 'الحالة', 'Status'))),
            const DataColumn(label: Text('')),
          ],
          rows: [
            for (final v in vList(d['vip_prices']))
              DataRow(cells: [
                DataCell(Text(vStr(v['ticket_name']))),
                DataCell(Text(VF.money(vNum(v['ticket_price'])))),
                DataCell(Text(VF.money(vSplitVat(vNum(v['ticket_price']), _vat(d), false).$2 - vNum(v['ticket_price'])))),
                DataCell(Text(VF.money(vSplitVat(vNum(v['ticket_price']), _vat(d), false).$2), style: const TextStyle(fontWeight: FontWeight.w700))),
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
            DataColumn(label: Text(tx(context, 'الضَريبة', 'VAT')), numeric: true),
            DataColumn(label: Text(tx(context, 'الإجماليّ', 'Total')), numeric: true),
            const DataColumn(label: Text('')),
          ],
          rows: [
            for (final m in vList(d['member_plans']))
              DataRow(cells: [
                DataCell(Text(vStr(m['name']))),
                DataCell(Text(VF.money(vNum(m['price'])))),
                DataCell(Text(VF.money(vSplitVat(vNum(m['price']), _vat(d), false).$2 - vNum(m['price'])))),
                DataCell(Text(VF.money(vSplitVat(vNum(m['price']), _vat(d), false).$2), style: const TextStyle(fontWeight: FontWeight.w700))),
                DataCell(_rowActions('member_plan', m, planFields)),
              ]),
          ],
        ),
      ),
    ]);
  }

  // ---------------------------------------------------------------- parking (linked areas)
  Future<VJson?> _areaById(String id) async {
    final all = await vGuard(context, () => ValetAdmin.I.call('vva_parking_areas'));
    if (all == null) return null;
    return vList(all['areas']).cast<VJson?>().firstWhere((a) => vStr(a?['id']) == id, orElse: () => null);
  }

  Future<void> _linkAreaDialog(VJson d) async {
    final all = await vGuard(context, () => ValetAdmin.I.call('vva_parking_areas'));
    if (all == null || !mounted) return;
    final linked = {for (final a in vList(d['parking_areas'])) vStr(a['id'])};
    final options = vList(all['areas']).where((a) => !linked.contains(vStr(a['id']))).toList();
    String q = '';
    final picked = await showDialog<VJson>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final list = options.where((a) => vStr(a['name']).toLowerCase().contains(q.toLowerCase())).toList();
        return AlertDialog(
          title: Text(tx(ctx, 'رَبط مَوقِف مَوجود', 'Link an existing area')),
          content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tx(ctx, 'بَحث', 'Search')),
                onChanged: (v) => set(() => q = v),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: list.isEmpty
                    ? Padding(padding: const EdgeInsets.all(16), child: Text(tx(ctx, 'لا تُوجَد مَواقِف أُخرى.', 'No other area.')))
                    : ListView(shrinkWrap: true, children: [
                        for (final a in list)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.local_parking),
                            title: Text(vStr(a['name'])),
                            subtitle: Text(vList(a['points']).isEmpty
                                ? tx(ctx, 'غَير مَربوط', 'Not linked')
                                : vList(a['points']).map((p) => vStr(p['name'])).join('، ')),
                            onTap: () => Navigator.pop(ctx, a),
                          ),
                      ]),
              ),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tx(ctx, 'إلغاء', 'Cancel')))],
        );
      }),
    );
    if (picked == null || !mounted) return;
    await _save('vva_parking_link', {'p_point': widget.pointId, 'p_area': picked['id'], 'p_on': true},
        ok: tx(context, 'تَمّ الرَبط.', 'Linked.'));
  }

  Widget _parking(VJson d) {
    final areas = vList(d['parking_areas']);
    return _page([
      VPanel(
        title: tx(context, 'المَواقِف المَربوطة بِهذه النُقطة (${areas.length})', 'Parking areas of this point (${areas.length})'),
        actions: [
          if (_edit)
            OutlinedButton.icon(icon: const Icon(Icons.link), label: Text(tx(context, 'رَبط مَوقِف', 'Link area')), onPressed: () => _linkAreaDialog(d)),
          if (_edit)
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: Text(tx(context, 'مَوقِف جَديد', 'New area')),
              onPressed: () async {
                final r = await showParkingAreaDialog(context, null, withPoint: widget.pointId);
                if (r != null) _load();
              },
            ),
        ],
        child: VTable(
          empty: tx(context, 'لا يوجد مَوقِف مَربوط. اربِط مَوقِفاً مَوجوداً أَو أَنشِئ جَديداً.', 'No linked area. Link an existing one or create a new one.'),
          columns: [
            DataColumn(label: Text(tx(context, 'المَوقِف', 'Area'))),
            DataColumn(label: Text(tx(context, 'السَعة', 'Capacity')), numeric: true),
            DataColumn(label: Text(tx(context, 'مُلاحَظات', 'Notes'))),
            DataColumn(label: Text(tx(context, 'الحالة', 'Status'))),
            const DataColumn(label: Text('')),
          ],
          rows: [
            for (final a in areas)
              DataRow(cells: [
                DataCell(Text(vStr(a['name']), style: const TextStyle(fontWeight: FontWeight.w600))),
                DataCell(Text(vNum(a['capacity']).toInt() == 0 ? '∞' : '${vNum(a['capacity']).toInt()}')),
                DataCell(Text(vStr(a['notes']))),
                DataCell(vBool(a['approved']) ? VPill(tx(context, 'مُستَخدَم', 'In use'), color: VC.ok) : VPill(tx(context, 'مُتَوَقِّف', 'Off'))),
                DataCell(!_edit
                    ? const SizedBox()
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          tooltip: tx(context, 'تَعديل وَرَبط بِنِقاط أُخرى', 'Edit & link to other points'),
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () async {
                            final full = await _areaById(vStr(a['id']));
                            if (full == null || !mounted) return;
                            final r = await showParkingAreaDialog(context, full);
                            if (r != null) _load();
                          },
                        ),
                        IconButton(
                          tooltip: tx(context, 'فَكّ الرَبط', 'Unlink'),
                          icon: const Icon(Icons.link_off, color: VC.bad),
                          onPressed: () async {
                            if (!await vConfirm(context, tx(context, 'فَكّ رَبط المَوقِف', 'Unlink area'),
                                tx(context, '${a['name']} — يَبقى المَوقِف لِلنِقاط الأُخرى.', '${a['name']} — the area stays for the other points.'))) {
                              return;
                            }
                            if (!mounted) return;
                            await _save('vva_parking_link', {'p_point': widget.pointId, 'p_area': a['id'], 'p_on': false},
                                ok: tx(context, 'تَمّ فَكّ الرَبط.', 'Unlinked.'));
                          },
                        ),
                      ])),
              ]),
          ],
        ),
      ),
      Text(
        tx(context, 'كُلّ المَواقِف وَرَبطها بِعِدّة نِقاط: قِسم الفاليه ← المَواقِف.', 'All areas and linking to several points: Valet → Parking areas.'),
        style: const TextStyle(color: VC.muted),
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

  num _vat(VJson d) => vMap(d['settings'])['vat_rate'] == null ? 0.05 : vNum(vMap(d['settings'])['vat_rate']);

  /// VIP price / membership plan: name + amount typed with VAT included or added (stored NET).
  Future<void> _netPriceDialog(String kind, VJson? row) async {
    final d = _d;
    if (d == null) return;
    final vatRate = _vat(d);
    final nameKey = kind == 'vip_price' ? 'ticket_name' : 'name';
    final priceKey = kind == 'vip_price' ? 'ticket_price' : 'price';
    bool incl = row == null ? true : (row['vat_included'] as bool? ?? false);
    final net = vNum(row?[priceKey]);
    final name = TextEditingController(text: vStr(row?[nameKey]));
    final amount = TextEditingController(text: row == null ? '' : (incl ? vSplitVat(net, vatRate, false).$2 : net).toString());
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        return AlertDialog(
          title: Text(row == null
              ? (kind == 'vip_price' ? tx(ctx, 'سِعر VIP جَديد', 'New VIP price') : tx(ctx, 'باقة عُضويّة جَديدة', 'New membership plan'))
              : tx(ctx, 'تَعديل', 'Edit')),
          content: SizedBox(
            width: 440,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(controller: name, decoration: InputDecoration(labelText: tx(ctx, 'الاسم *', 'Name *'))),
              const SizedBox(height: 12),
              VatAmountField(
                controller: amount,
                included: incl,
                vatRate: vatRate,
                label: tx(ctx, 'المَبلَغ (AED) *', 'Amount (AED) *'),
                extra: kind == 'member_plan' ? tx(ctx, ' شَهريّاً', ' per month') : '',
                onToggle: () => set(() => incl = !incl),
                onChanged: () => set(() {}),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tx(ctx, 'إلغاء', 'Cancel'))),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isEmpty || num.tryParse(amount.text) == null) {
                  vToast(ctx, tx(ctx, 'أَدخِل الاسم وَالمَبلَغ.', 'Enter the name and the amount.'), error: true);
                  return;
                }
                final (pr, _) = vSplitVat(num.parse(amount.text), vatRate, incl);
                Navigator.pop(ctx);
                _save('vva_item_save', {
                  'p_kind': kind,
                  'p_data': {
                    if (row != null) 'id': row['id'],
                    'point_id': widget.pointId,
                    nameKey: name.text.trim(),
                    priceKey: pr,
                    'vat_included': incl,
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

  Future<void> _simple(String kind, VJson? row, List<(String, String, bool)> fields) async {
    if (kind == 'vip_price' || kind == 'member_plan') return _netPriceDialog(kind, row);
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
