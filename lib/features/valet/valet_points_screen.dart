import 'package:flutter/material.dart';

import 'valet_admin.dart';
import 'valet_cards_screen.dart';
import 'valet_link_screen.dart';
import 'valet_staff_analytics_screen.dart';
import 'valet_voice_screen.dart';
import 'valet_key_boards_panel.dart';
import 'valet_hourly.dart';
import 'valet_hub_ui.dart';
import 'valet_parking_screen.dart';
import 'valet_pricing_rules.dart';
import 'valet_ticket_parts.dart';
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
  String _chip = 'all';
  String _sort = 'cars';
  static final _def = HubView('points', mode: 'cards', group: 'area', fields: {'area', 'device', 'stats', 'bar', 'actions'}, hideOff: true);
  HubView _view = _def;

  @override
  void initState() {
    super.initState();
    HubView.load(_def).then((v) {
      if (mounted) setState(() => _view = v);
    });
  }

  bool _isValet(VJson p) => p['configured'] == true || p['terminal'] != null;
  int _cars(VJson p) => vNum(p['active']).toInt();
  int _warn(VJson p) => (p['terminal'] == null ? 1 : 0) + (p['area'] == null ? 1 : 0) + (vNum(p['prices']) == 0 ? 1 : 0);

  Future<void> _open(VJson p, VoidCallback reload) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ValetPointDetailScreen(pointId: vStr(p['id']), title: vStr(p['name']))));
    reload();
  }

  @override
  Widget build(BuildContext context) => ValetGate(
        child: VLoader<List<VJson>>(
          load: () async {
            VPoints.clear();
            return VPoints.get();
          },
          builder: (context, all, reload) {
            final base = all.where((p) => !_view.hideOff || _isValet(p)).toList();
            final q = _q.toLowerCase();
            final areas = <String, int>{};
            for (final p in base) {
              final a = vStr(p['area']);
              if (a.isNotEmpty) areas[a] = (areas[a] ?? 0) + 1;
            }
            bool chipOk(VJson p) => switch (_chip) {
                  'all' => true,
                  'live' => _cars(p) > 0,
                  'setup' => _warn(p) > 0,
                  'noarea' => p['area'] == null,
                  _ => vStr(p['area']) == _chip,
                };
            final list = base.where((p) => chipOk(p) && (q.isEmpty || '${p['code']} ${p['name']} ${p['area'] ?? ''}'.toLowerCase().contains(q))).toList();
            list.sort((a, b) => switch (_sort) {
                  'name' => vStr(a['name']).toLowerCase().compareTo(vStr(b['name']).toLowerCase()),
                  'code' => vStr(a['code']).compareTo(vStr(b['code'])),
                  _ => _cars(b).compareTo(_cars(a)) != 0 ? _cars(b).compareTo(_cars(a)) : vStr(a['code']).compareTo(vStr(b['code'])),
                });
            final maxCars = base.fold<int>(1, (m, p) => _cars(p) > m ? _cars(p) : m);
            final carsNow = base.fold<int>(0, (s, p) => s + _cars(p));
            final live = base.where((p) => _cars(p) > 0).length;

            Widget body;
            if (_view.mode == 'cards') {
              Map<String, List<VJson>> groups;
              if (_view.group == 'area') {
                groups = {};
                for (final p in list) {
                  groups.putIfAbsent(p['area'] == null ? '' : vStr(p['area']), () => []).add(p);
                }
              } else if (_view.group == 'status') {
                groups = {};
                for (final p in list) {
                  groups.putIfAbsent(_cars(p) > 0 ? 'live' : (_warn(p) > 0 ? 'setup' : 'ready'), () => []).add(p);
                }
              } else {
                groups = {'': list};
              }
              String gTitle(String k) => _view.group == 'area'
                  ? (k.isEmpty ? tx(context, 'بِدون مَنطِقة', 'No area') : k)
                  : switch (k) {
                      'live' => tx(context, 'شَغّالة الآن', 'Live now'),
                      'setup' => tx(context, 'تَحتاج إعداد', 'Needs setup'),
                      'ready' => tx(context, 'جاهِزة', 'Ready'),
                      _ => '',
                    };
              body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final e in groups.entries) ...[
                  if (_view.group.isNotEmpty)
                    hubGroupTitle(gTitle(e.key),
                        tx(context, '· ${e.value.length} نُقطة · ${e.value.fold<int>(0, (s, p) => s + _cars(p))} سَيّارة الآن', '· ${e.value.length} points · ${e.value.fold<int>(0, (s, p) => s + _cars(p))} cars now')),
                  HubGrid(view: _view, children: [for (final p in e.value) _card(p, maxCars, reload)]),
                ],
              ]);
            } else {
              final compact = _view.mode == 'compact';
              body = hubPanel(VTable(dataRowMinHeight: compact ? 34 : 48, dataRowMaxHeight: compact ? 38 : 56, columns: [
                DataColumn(label: Text(tx(context, 'الكود', 'Code'))),
                DataColumn(label: Text(tx(context, 'النُقطة', 'Point'))),
                DataColumn(label: Text(tx(context, 'الحالة', 'Status'))),
                if (_view.show('area')) DataColumn(label: Text(tx(context, 'المَنطِقة', 'Area'))),
                if (_view.show('device')) DataColumn(label: Text(tx(context, 'حِساب الجِهاز', 'Device account'))),
                if (_view.show('stats')) ...[
                  DataColumn(label: Text(tx(context, 'العُمَلاء', 'Clients')), numeric: true),
                  DataColumn(label: Text(tx(context, 'الأَسعار', 'Prices')), numeric: true),
                ],
                DataColumn(label: Text(tx(context, 'سَيّارات الآن', 'Cars now')), numeric: true),
                const DataColumn(label: Text('')),
              ], rows: [
                for (final p in list)
                  DataRow(onSelectChanged: (_) => _open(p, reload), cells: [
                    DataCell(Text(vStr(p['code']))),
                    DataCell(Text(vStr(p['name']), style: const TextStyle(fontWeight: FontWeight.w700))),
                    DataCell(_status(p)),
                    if (_view.show('area')) DataCell(p['area'] == null ? hubTag(tx(context, 'بِدون مَنطِقة', 'No area'), missing: true) : hubTag(vStr(p['area']), icon: Icons.place_outlined)),
                    if (_view.show('device'))
                      DataCell(p['terminal'] == null ? hubTag(tx(context, 'بِدون جِهاز', 'No device'), missing: true) : hubTag(vStr(vMap(p['terminal'])['username']), icon: Icons.tablet_android)),
                    if (_view.show('stats')) ...[
                      DataCell(Text(vStr(p['clients']))),
                      DataCell(Text(vStr(p['prices']), style: TextStyle(color: vNum(p['prices']) == 0 ? VC.bad : null, fontWeight: FontWeight.w700))),
                    ],
                    DataCell(Text('${_cars(p)}', style: const TextStyle(fontWeight: FontWeight.w800))),
                    const DataCell(Icon(Icons.chevron_left)),
                  ]),
              ]));
            }

            return ListView(padding: const EdgeInsets.only(bottom: 28), children: [
              HubHead(
                title: tx(context, 'تَطبيق الفاليه — النِقاط', 'Valet app — points'),
                subtitle: tx(context, 'كُلّ نُقطة: الحالة، الجِهاز، المَنطِقة، العُمَلاء، الأَسعار وَالسَيّارات الآن', 'Each point: status, device, area, clients, prices and cars now'),
                actions: [
                  HubSearch(hint: tx(context, 'بَحث بِالكود أَو الاسم أَو المَنطِقة', 'Search code, name or area'), onChanged: (v) => setState(() => _q = v)),
                  PopupMenuButton<String>(
                    tooltip: tx(context, 'تَرتيب', 'Sort'),
                    onSelected: (v) => setState(() => _sort = v),
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 'cars', child: Text(tx(context, 'الأَكثَر سَيّارات', 'Most cars'))),
                      PopupMenuItem(value: 'name', child: Text(tx(context, 'الاسم', 'Name'))),
                      PopupMenuItem(value: 'code', child: Text(tx(context, 'الكود', 'Code'))),
                    ],
                    child: IgnorePointer(
                      child: HubButton(
                          icon: Icons.swap_vert,
                          label: switch (_sort) { 'name' => tx(context, 'الاسم', 'Name'), 'code' => tx(context, 'الكود', 'Code'), _ => tx(context, 'الأَكثَر سَيّارات', 'Most cars') },
                          onPressed: () {}),
                    ),
                  ),
                  HubButton(
                    icon: Icons.tune_rounded,
                    label: tx(context, 'العَرض', 'View'),
                    onPressed: () async {
                      final v = await showHubView(context, _view, _def,
                          fields: [
                            ('area', tx(context, 'المَنطِقة', 'Area')),
                            ('device', tx(context, 'حِساب الجِهاز', 'Device account')),
                            ('stats', tx(context, 'العُمَلاء وَالأَسعار', 'Clients and prices')),
                            ('bar', tx(context, 'شَريط السَيّارات', 'Cars bar')),
                            ('actions', tx(context, 'الأَزرار المُختَصَرة', 'Quick buttons')),
                          ],
                          groups: [('', tx(context, 'بِدون', 'None')), ('area', tx(context, 'المَنطِقة', 'Area')), ('status', tx(context, 'الحالة', 'Status'))],
                          hideOffLabel: tx(context, 'إخفاء النِقاط اللي مِش فاليه', 'Hide non-valet points'));
                      if (v != null && mounted) setState(() => _view = v);
                    },
                  ),
                ],
              ),
              HubKpis([
                HubKpi(Icons.local_parking, '${base.length}', tx(context, 'نُقطة فاليه', 'Valet points')),
                HubKpi(Icons.directions_car_filled_outlined, '$carsNow', tx(context, 'سَيّارة الآن · $live نُقطة شَغّالة', 'Cars now · $live live points')),
                HubKpi(Icons.tablet_android, '${base.where((p) => p['terminal'] != null).length}/${base.length}', tx(context, 'لَها حِساب جِهاز', 'With device account')),
                HubKpi(Icons.map_outlined, '${base.where((p) => p['area'] == null).length}', tx(context, 'بِدون مَنطِقة', 'No area')),
                HubKpi(Icons.sell_outlined, '${base.where((p) => vNum(p['prices']) == 0).length}', tx(context, 'بِدون أَسعار', 'No prices')),
              ]),
              HubChips(
                value: _chip,
                onChanged: (v) => setState(() => _chip = v),
                items: [
                  ('all', tx(context, 'الكُلّ', 'All'), base.length),
                  ('live', tx(context, 'شَغّالة الآن', 'Live now'), live),
                  ('setup', tx(context, 'تَحتاج إعداد', 'Needs setup'), base.where((p) => _warn(p) > 0).length),
                  for (final e in (areas.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))) (e.key, e.key, e.value),
                  ('noarea', tx(context, 'بِدون مَنطِقة', 'No area'), base.where((p) => p['area'] == null).length),
                ],
              ),
              if (list.isEmpty)
                Padding(padding: const EdgeInsets.all(40), child: Center(child: Text(tx(context, 'لا تُوجَد نِقاط.', 'No point.'), style: const TextStyle(color: VC.muted))))
              else
                body,
            ]);
          },
        ),
      );

  Widget _status(VJson p) {
    final w = _warn(p);
    if (_cars(p) > 0) return hubPill(tx(context, 'شَغّالة الآن', 'Live now'), kind: 'dark', pulse: true);
    if (w == 0) return hubPill(tx(context, 'جاهِزة', 'Ready'), kind: 'ok');
    return hubPill(tx(context, '$w تَنبيه', '$w alert(s)'), kind: 'bad');
  }

  Widget _card(VJson p, int maxCars, VoidCallback reload) {
    final cars = _cars(p);
    final big = _view.size == 'l', small = _view.size == 's';
    Future<void> openTab(int tab) async {
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ValetPointDetailScreen(pointId: vStr(p['id']), title: vStr(p['name']), initialTab: tab)));
      reload();
    }

    return HubCard(
      strong: cars > 0,
      onTap: () => _open(p, reload),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(vStr(p['code']), style: const TextStyle(fontSize: 11.5, color: VC.muted, fontWeight: FontWeight.w600, letterSpacing: .5)),
              Text(vStr(p['name']), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: big ? 17 : (small ? 14 : 15.5), fontWeight: FontWeight.w800, height: 1.3)),
            ]),
          ),
          const SizedBox(width: 6),
          _status(p),
        ]),
        if (_view.show('area') || _view.show('device')) ...[
          const SizedBox(height: 9),
          Wrap(spacing: 6, runSpacing: 6, children: [
            if (_view.show('area'))
              p['area'] == null ? hubTag(tx(context, 'بِدون مَنطِقة', 'No area'), missing: true) : hubTag(vStr(p['area']), icon: Icons.place_outlined),
            if (_view.show('device'))
              p['terminal'] == null
                  ? hubTag(tx(context, 'بِدون جِهاز', 'No device'), missing: true)
                  : hubTag(vStr(vMap(p['terminal'])['username']), icon: Icons.tablet_android),
          ]),
        ],
        if (!small || _view.show('stats')) ...[
          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: hubStat('$cars', tx(context, 'سَيّارات الآن', 'Cars now'))),
            if (_view.show('stats')) ...[
              Expanded(child: hubStat(vStr(p['clients']), tx(context, 'العُمَلاء', 'Clients'))),
              Expanded(child: hubStat(vStr(p['prices']), tx(context, 'الأَسعار', 'Prices'), color: vNum(p['prices']) == 0 ? VC.bad : null)),
            ],
          ]),
        ],
        if (_view.show('bar')) ...[const SizedBox(height: 9), hubBar(cars / maxCars)],
        if (_view.show('actions')) ...[
          const SizedBox(height: 11),
          Row(children: [
            hubAction(tx(context, 'الأَسعار', 'Prices'), () => openTab(1)),
            const SizedBox(width: 6),
            hubAction(tx(context, 'المَزايا', 'Features'), () => openTab(0)),
            const SizedBox(width: 6),
            hubAction(tx(context, 'المَواقِف', 'Parking'), () => openTab(2)),
            const Spacer(),
            Text(tx(context, 'فَتح', 'Open'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
            const Icon(Icons.chevron_left, size: 18),
          ]),
        ],
      ]),
    );
  }
}

// ================================================================ detail
class ValetPointDetailScreen extends StatefulWidget {
  const ValetPointDetailScreen({super.key, required this.pointId, required this.title, this.initialTab = 0});
  final String pointId;
  final String title;
  final int initialTab;

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
    final id = widget.pointId;
    // pages of the valet app that belong to one point (customer link, NFC cards, staff analysis)
    final extra = <(String, String, Widget)>[
      if (ValetAdmin.I.can(ValetAdmin.permSettings)) ('لِينك العَميل', 'Customer link', ValetLinkScreen(key: ValueKey('link$id'), pointId: id)),
      if (ValetAdmin.I.can(ValetAdmin.permSettings)) ('كُروت NFC', 'NFC cards', ValetCardsScreen(key: ValueKey('cards$id'), pointId: id)),
      if (ValetAdmin.I.can(ValetAdmin.permSettings)) ('الأَوامِر الصَوتيّة', 'Voice commands', ValetVoiceScreen(key: ValueKey('voice$id'), pointId: id)),
      if (ValetAdmin.I.can(ValetAdmin.permReports))
        ('تَحليل المُوظَّفين', 'Staff analysis', ValetStaffAnalyticsScreen(key: ValueKey('staff$id'), pointId: id)),
    ];
    final n = 5 + extra.length;
    return DefaultTabController(
      length: n,
      initialIndex: widget.initialTab.clamp(0, n - 1),
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
            Tab(text: tx(context, 'المَواقِف', 'Parking')),
            Tab(text: tx(context, 'حِساب الجِهاز', 'Device account')),
            Tab(text: tx(context, 'المُعِدّات وَالمَكَن وَالدَفاتِر', 'Equipment, machines & books')),
            for (final (ar, en, _) in extra) Tab(text: tx(context, ar, en)),
          ]),
        ),
        body: d == null
            ? Center(child: _err != null ? Text(vErr(context, _err!)) : const CircularProgressIndicator())
            : TabBarView(children: [_features(d), _prices(d), _parking(d), _terminal(d), _equipment(d), for (final (_, _, w) in extra) w]),
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
  /// (key, title ar, title en, ON ar, ON en, OFF ar, OFF en) – what the valet app does in each state.
  List<(String, String, String, String, String, String, String)> _flags(BuildContext c) => [
        ('photo_in_out', 'صورة السَيّارة', 'Car photo',
            'زِرّ الكاميرا في إضافة تَذكَرة يَقرَأ اللَوحة وَالنَوع وَاللَون', 'Camera on Add ticket reads plate, type and colour',
            'لا كاميرا – المُوَظَّف يَكتُب البَيانات', 'No camera – the staff type the details'),
        ('nfc_qr_in_out', 'كَرت التَذكَرة (NFC / QR)', 'Ticket card (NFC / QR)',
            'يُربَط كَرت بِكُلّ تَذكَرة (إجباريّ)، وَالعَميل يَطلُب سَيّارَته بِه', 'A card is linked to every ticket (required); the customer calls the car with it',
            'تَذكَرة بِدون كَرت', 'Tickets without a card'),
        ('price_group_customer', 'سِعر واحِد لِكُلّ العُمَلاء', 'One price for every client',
            'لا يُختار عَميل – سِعر النُقطة لِلجَميع', 'No client is picked – the point price for everyone',
            'المُوَظَّف يَختار العَميل وَتُطَبَّق أَسعاره', 'The staff pick the client and its prices apply'),
        ('show_driver_in', 'زِرّ سائِق الصَفّ (Driver in)', 'Driver in button',
            'يَظهَر في قائِمة التَذكَرة لِتَسجيل مَن صَفّ السَيّارة', 'Shown in the ticket menu to record who parked the car',
            'مَخفيّ – لا يُسَجَّل مَن صَفّ السَيّارة', 'Hidden – who parked the car is not recorded'),
        ('show_parking', 'زِرّ المَوقِف (Parking)', 'Parking button',
            'يَظهَر في قائِمة التَذكَرة، وَالمَواقِف تَظهَر في أَعلى اللَوحة', 'Shown in the ticket menu, and the parking areas show on top of the board',
            'مَخفيّ – بِدون مَوقِف وَرَقم', 'Hidden – no parking area or number'),
        ('show_driver_out', 'زِرّ سائِق التَسليم (Driver out)', 'Driver out button',
            'يَظهَر في قائِمة التَذكَرة لِتَسجيل مَن سَلَّم السَيّارة', 'Shown in the ticket menu to record who delivered the car',
            'مَخفيّ – لا يُسَجَّل مَن سَلَّم السَيّارة', 'Hidden – who delivered the car is not recorded'),
        ('drivers_in', 'سائِق الصَفّ', 'Parking driver',
            'إجباريّ – لا تُدفَع التَذكَرة بِدونه', 'Required – the ticket cannot be paid without it',
            'اختياريّ', 'Optional'),
        ('drivers_out', 'سائِق التَسليم', 'Delivering driver',
            'إجباريّ – لا تُدفَع التَذكَرة بِدونه', 'Required – the ticket cannot be paid without it',
            'اختياريّ', 'Optional'),
        ('parking_in_out', 'المَوقِف وَرَقمه', 'Parking area and number',
            'إجباريّ – لا تُدفَع التَذكَرة بِدونه', 'Required – the ticket cannot be paid without it',
            'اختياريّ', 'Optional'),
        ('dropdown_parkingcar', 'السائِق في الصَفّ وَالتَسليم', 'Driver on parking and delivery',
            'قائِمة بِالأَسماء أَو مَسح الكَرت', 'Name list or card scan',
            'مَسح كَرت السائِق فَقَط', 'Driver card scan only'),
        ('dropdown_time_in_out', 'السائِق في الحُضور', 'Driver in attendance',
            'قائِمة بِالأَسماء أَو مَسح الكَرت', 'Name list or card scan',
            'مَسح كَرت السائِق فَقَط', 'Driver card scan only'),
        ('paid_first_or_paid_after', 'الدَفع أَوَّلاً', 'Pay first',
            'كُلّ الوَرديّات: العَميل يَدفَع عِند الدُخول', 'Every shift: the customer pays on entry',
            'كُلّ الوَرديّات: العَميل يَدفَع عِند الخُروج', 'Every shift: the customer pays at check-out'),
        ('valet_validate', 'زِرّ "Validate for a client"', '"Validate for a client" button',
            'ظاهِر في شاشة الدَفع – المُوَظَّف يَعمَل فاليديشن لِعَميل', 'Shown on check-out – the staff validate for a client',
            'مَخفيّ', 'Hidden'),
        ('stamp_ticket', 'تَذاكِر الخَتم', 'Stamp tickets',
            'زِرّ في شاشة الدَفع: تَذكَرة مَجّانيّة بِصورة خَتم العَميل', 'Check-out button: free ticket with a stamp photo',
            'مَخفيّ', 'Hidden'),
        ('car_request', 'العَميل يَطلُب سَيّارَته', 'Customer calls the car',
            'مِن رابِط / QR التَذكَرة عَلى هاتِفه', 'From the ticket link / QR on their phone',
            'العَميل يَطلُب مِن المُوَظَّف فَقَط', 'Only by asking the staff'),
        ('require_gps', 'المَوقِع (GPS) إجباريّ', 'Location (GPS) required',
            'لا حُضور وَلا انصِراف وَلا فَتح أَو قَفل وَرديّة بِدون تَشغيل المَوقِع', 'No check-in / out and no opening or closing a shift without Location on',
            'التَطبيق يَعمَل بِدون المَوقِع، وَالحُضور يُسَجَّل بِدون مَكان', 'The app works without Location; attendance is saved without a place'),
        ('show_member_pick', 'المُشتَرِك تَحت رَقم السَيّارة', 'Member under the plate',
            'زِرّ المُشتَرِك (كَرت العُضويّة / الذَهَبيّ) يَظهَر تَحت رَقم السَيّارة؛ المُشتَرِك الفَعّال تَذكَرَته مَجّانيّة', 'The member button (member / gold card) shows under the plate; an active member gets a free ticket',
            'لا يَظهَر زِرّ المُشتَرِك في إضافة التَذكَرة', 'No member button when adding a ticket'),
        ('show_hotel_pick', 'الفُندُق / السَكَن تَحت رَقم السَيّارة', 'Hotel / residence under the plate',
            'زِرّ الفُندُق يَظهَر تَحت رَقم السَيّارة لِكِتابة الفِئة وَرَقم الغُرفة – لا يُغَيِّر السِعر (يَتَغَيَّر فَقَط بِالفاليديشن)', 'The hotel button shows under the plate for the category and room number – no price change (only a validation changes it)',
            'لا يَظهَر زِرّ الفُندُق في إضافة التَذكَرة', 'No hotel button when adding a ticket'),
        ('require_print', 'الطِباعة إجباريّة', 'Printing required',
            'Save & Print: لا تُحفَظ التَذكَرة إلّا مَعَ طابِعة مُتَّصِلة، وَلا يَخرُج المُوَظَّف مِن الصَفحة قَبل طِباعَتها', 'Save & Print: no ticket is saved without a connected printer, and the page cannot be left before it is printed',
            'الطِباعة اختياريّة – يُمكِن المُتابَعة بِدون طِباعة', 'Printing is optional – the staff can continue without printing'),
        ('preview_sound', 'صَوت الطِباعة', 'Printing sound',
            'صَوت طِباعة مَعَ الوَرَقة عَلى الشاشة', 'A printing sound with the paper on the screen',
            'بِدون صَوت', 'No sound'),
        ('color_states', 'أَلوان التَذاكِر في اللَوحة', 'Ticket colours on the board',
            'لَون لِكُلّ حالة: طَلَب العَميل، طَلَب الكي راك، مَدفوعة، وَقت إضافيّ، فاليديشن، VIP – وَشَريط يَشرَح الأَلوان وَيُفَلتِر بِها', 'A colour per state: customer request, key rack request, paid, extra time, validated, VIP – with a legend that filters',
            'كُلّ التَذاكِر بِنَفس الشَكل', 'All tickets look the same'),
        ('prepay_enabled', 'الدَفع قَبل وُصول السَيّارة', 'Pay before the car comes',
            'العَميل يَدفَع وَالتَذكَرة تَبقى خَضراء عَلى اللَوحة حَتّى التَسليم. السِعر الثابِت: بِدون وَقت. نِقاط الوَقت: وَقت خُروج اختِياريّ', 'The customer pays; the ticket stays green on the board until delivery. Fixed price: no time. Hourly points: optional time to leave',
            'الدَفع عِند التَسليم فَقَط', 'Payment only at delivery'),
        ('opener_must_close', 'مَن فَتَح الوَرديّة لا يَخرُج قَبل قَفلها', 'Shift opener stays until closing',
            'المُوَظَّف الذي فَتَح الوَرديّة لا يَستَطيع تَسجيل الخُروج مِن التَطبيق إلّا بَعد قَفل الوَرديّة', 'The staff member who opened the shift cannot log out of the app until the shift is closed',
            'يَستَطيع تَسجيل الخُروج وَالوَرديّة تَبقى مَفتوحة', 'Can log out while the shift stays open'),
        ('sinin_w_card', 'دُخول المُوَظَّفين', 'Staff sign-in',
            'اسم مُستَخدِم وَكَلِمة مُرور', 'User name + password',
            'كَرت المُوَظَّف NFC / QR فَقَط', 'Staff NFC / QR card only'),
        ('staff_eval', 'تَقييم المُوَظَّفين', 'Staff ratings',
            'المُشرِف الذي فَتَح الوَرديّة يُقَيِّم مِن التَطبيق', 'The supervisor who opened the shift rates in the app',
            'مِن الداشبورد فَقَط', 'From the dashboard only'),
        ('supervisor_roster', 'الروستر', 'Roster',
            'المُشرِف يُنشِئ روستر الأُسبوع مِن التَطبيق وَيُرسِله لِلعَمَليّات', 'The supervisor builds the weekly roster in the app and sends it to Operations',
            'مِن الداشبورد فَقَط', 'From the dashboard only'),
        ('show_policies', 'سياسات الشَركة', 'Company policies',
            'صَفحة لِلقِراءة في التَطبيق', 'Read-only page in the app',
            'مَخفيّة', 'Hidden'),
        ('key_rack_w_sites_or_allow', 'تَطبيق المَفاتيح', 'Key rack app',
            'Key Controller يَستَلِم المَفاتيح وَيَطلُب السَيّارات', 'The Key Controller holds the keys and calls the cars',
            'السائِقون يَعمَلون مِن لَوحة التَذاكِر مُباشَرة', 'Drivers work straight from the tickets board'),
        ('paid_with_app_or_keyrack', 'الدَفع عِند المَفاتيح', 'Payment at the key rack',
            'العَميل يَدفَع في تَطبيق المَفاتيح', 'The customer pays in the key rack app',
            'الدَفع في تَطبيق الفاليه', 'Paid in the valet app'),
        ('show_membership', 'صَفحة العُضويّات', 'Memberships page',
            'بَيع وَمُتابَعة العُضويّات الشَهريّة', 'Sell and check monthly members',
            'مَخفيّة', 'Hidden'),
        ('member_card_normal', 'كَرت العُضويّة', 'Member card',
            'خانة في إضافة تَذكَرة', 'Field on Add ticket',
            'مَخفيّة', 'Hidden'),
        ('member_card_gold', 'الكَرت الذَهَبيّ', 'Gold card',
            'خانة في إضافة تَذكَرة', 'Field on Add ticket',
            'مَخفيّة', 'Hidden'),
      ];

  static const _flagIcons = <String, IconData>{
    'car_request': Icons.directions_car_filled_outlined,
    'key_rack_w_sites_or_allow': Icons.key_outlined,
    'sinin_w_card': Icons.password_rounded,
    'require_gps': Icons.location_on_outlined,
    'require_print': Icons.print_outlined,
    'show_member_pick': Icons.card_membership,
    'show_driver_in': Icons.login_rounded,
    'show_parking': Icons.local_parking_rounded,
    'show_driver_out': Icons.logout_rounded,
    'show_hotel_pick': Icons.apartment,
    'color_states': Icons.palette_outlined,
    'prepay_enabled': Icons.timer_outlined,
    'preview_sound': Icons.volume_up_outlined,
    'opener_must_close': Icons.lock_clock_outlined,
    'paid_first_or_paid_after': Icons.payments_outlined,
    'price_group_customer': Icons.sell_outlined,
    'stamp_ticket': Icons.approval_outlined,
    'valet_validate': Icons.verified_outlined,
    'staff_eval': Icons.star_rate_rounded,
    'supervisor_roster': Icons.calendar_month_outlined,
    'show_policies': Icons.policy_outlined,
    'photo_in_out': Icons.photo_camera_outlined,
    'nfc_qr_in_out': Icons.nfc_rounded,
    'used_card_manual': Icons.qr_code_scanner_rounded,
    'drivers_in': Icons.login_rounded,
    'drivers_out': Icons.logout_rounded,
    'parking_in_out': Icons.local_parking_rounded,
    'dropdown_parkingcar': Icons.format_list_bulleted_rounded,
    'dropdown_time_in_out': Icons.schedule_rounded,
    'show_membership': Icons.card_membership_outlined,
    'member_card_normal': Icons.credit_card_outlined,
    'member_card_gold': Icons.workspace_premium_outlined,
    'paid_with_app_or_keyrack': Icons.point_of_sale_outlined,
  };

  Widget _features(VJson d) {
    final s = vMap(d['settings']);
    void toggle(String k, bool v) => _save('vva_point_settings_save', {'p_point': widget.pointId, 'p_data': {k: v}});
    void toggleValue(String k, Object v) => _save('vva_point_settings_save', {'p_point': widget.pointId, 'p_data': {k: v}});
    final flags = {for (final f in _flags(context)) f.$1: f};
    Widget sw(String k, {bool enabled = true, String? lockAr, String? lockEn}) {
      final f = flags[k]!;
      final on = vBool(s[k]);
      final accent = on ? VC.ok : VC.muted;
      // one state: icon + label + what the app does; the current state is highlighted
      Widget state(bool forOn, String ar, String en) {
        final cur = forOn == on;
        final c = forOn ? VC.ok : VC.bad;
        return Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            decoration: BoxDecoration(
              color: cur ? c.withValues(alpha: 0.10) : Colors.transparent,
              border: Border.all(color: cur ? c.withValues(alpha: 0.55) : VC.muted.withValues(alpha: 0.25)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Opacity(
              opacity: cur ? 1 : 0.6,
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(forOn ? Icons.check_circle_rounded : Icons.cancel_rounded, size: 16, color: c),
                const SizedBox(width: 6),
                Expanded(
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: forOn ? tx(context, 'تَشغيل: ', 'On: ') : tx(context, 'إيقاف: ', 'Off: '),
                        style: TextStyle(fontWeight: FontWeight.w700, color: c)),
                    TextSpan(text: tx(context, ar, en)),
                  ]), style: const TextStyle(fontSize: 12.5)),
                ),
              ]),
            ),
          ),
        );
      }

      return Container(
        width: 470,
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: BoxDecoration(
          border: Border.all(color: accent.withValues(alpha: on ? 0.45 : 0.25)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: (on ? VC.gold : VC.muted).withValues(alpha: 0.14), borderRadius: BorderRadius.circular(9)),
              child: Icon(_flagIcons[k] ?? Icons.tune_rounded, size: 19, color: on ? VC.gold : VC.muted),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(tx(context, f.$2, f.$3), style: const TextStyle(fontWeight: FontWeight.w700))),
            Switch(value: on, onChanged: !_edit || !enabled ? null : (v) => toggle(k, v)),
          ]),
          const SizedBox(height: 6),
          // ON on the reading side (right in Arabic), OFF on the other side
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              state(true, f.$4, f.$5),
              const SizedBox(width: 8),
              state(false, f.$6, f.$7),
            ]),
          ),
          if (!enabled && lockAr != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                const Icon(Icons.lock_outline, size: 14, color: VC.muted),
                const SizedBox(width: 4),
                Expanded(child: Text(tx(context, lockAr, lockEn ?? lockAr), style: const TextStyle(color: VC.muted, fontSize: 12))),
              ]),
            ),
        ]),
      );
    }

    Widget section(IconData icon, String ar, String en, String noteAr, String noteEn, List<Widget> children) => VPanel(
          title: tx(context, ar, en),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, size: 18, color: VC.gold),
              const SizedBox(width: 8),
              Expanded(child: Text(tx(context, noteAr, noteEn), style: const TextStyle(color: VC.muted, fontSize: 12.5))),
            ]),
            const SizedBox(height: 6),
            Wrap(spacing: 16, runSpacing: 2, children: children),
          ]),
        );

    // NFC / QR for the whole point (replaces the device switch)
    final reader = vStr(s['card_reader']).isNotEmpty ? vStr(s['card_reader']) : (vBool(s['used_card_manual']) ? 'device' : 'nfc');
    Widget readerPicker() => SizedBox(
          width: 470,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tx(context, 'قِراءة كُروت التَذاكِر', 'Ticket cards are read with'), style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: [
                  const ButtonSegment(value: 'nfc', icon: Icon(Icons.nfc_rounded), label: Text('NFC')),
                  const ButtonSegment(value: 'qr', icon: Icon(Icons.qr_code_scanner_rounded), label: Text('QR')),
                  ButtonSegment(value: 'both', icon: const Icon(Icons.all_inclusive_rounded), label: Text(tx(context, 'NFC + QR مَعاً', 'NFC + QR together'))),
                  ButtonSegment(value: 'device', icon: const Icon(Icons.phone_android), label: Text(tx(context, 'كُلّ جِهاز يَختار', 'Each device'))),
                ],
                selected: {reader},
                onSelectionChanged: !_edit
                    ? null
                    : (v) => _save('vva_point_settings_save', {
                          'p_point': widget.pointId,
                          'p_data': v.first == 'device'
                              ? {'card_reader': null, 'used_card_manual': true}
                              : {'card_reader': v.first, 'used_card_manual': false},
                        }),
              ),
            ]),
          ),
        );

    // "Pay several tickets" → Add a ticket: how the staff find the ticket (typing / QR / NFC)
    final findRaw = s['ticket_find'];
    final find = findRaw is List && findRaw.isNotEmpty ? findRaw.map((e) => '$e').toSet() : {'text', 'qr', 'nfc'};
    Widget findPicker() {
      Widget chip(String k, IconData icon, String ar, String en) => FilterChip(
            avatar: Icon(icon, size: 18, color: find.contains(k) ? VC.gold : VC.muted),
            label: Text(tx(context, ar, en)),
            selected: find.contains(k),
            onSelected: !_edit
                ? null
                : (on) {
                    final next = {...find};
                    on ? next.add(k) : next.remove(k);
                    if (next.isEmpty) return; // at least one way
                    _save('vva_point_settings_save', {
                      'p_point': widget.pointId,
                      'p_data': {'ticket_find': next.length == 3 ? null : next.toList()},
                    });
                  },
          );
      return SizedBox(
        width: 470,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tx(context, 'البَحث عَن تَذكَرة في "دَفع عِدّة تَذاكِر"', 'Finding a ticket in "Pay several tickets"'),
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(tx(context, 'اختَر طَريقة أَو أَكثَر. إيقاف الكِتابة يُخفي خانة البَحث وَيَكتَفي بِالمَسح.',
                    'Pick one or more. Turning typing off hides the search box – scanning only.'),
                style: const TextStyle(color: VC.muted, fontSize: 12.5)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, children: [
              chip('text', Icons.keyboard_outlined, 'كِتابة رَقم / لَوحة', 'Type number / plate'),
              chip('qr', Icons.qr_code_scanner_rounded, 'مَسح QR', 'Scan QR'),
              chip('nfc', Icons.nfc_rounded, 'كَرت NFC', 'NFC card'),
            ]),
          ]),
        ),
      );
    }

    // card payments: the 6-digit approval number from the card machine slip (matched later with the Paymob file)
    String approvalOf(String k) => const {'off', 'optional', 'required'}.contains(vStr(s[k])) ? vStr(s[k]) : 'off';
    Widget approvalPicker() => SizedBox(
          width: 470,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tx(context, 'رَقم المُوافَقة لِلدَفع بِالكارت (6 أَرقام)', 'Card payment approval number (6 digits)'),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(
                  tx(context, 'المُوَظَّف يَكتُب رَقم المُوافَقة مِن إيصال المَكينة عِند الدَفع بِالكارت. لا يَتَكَرَّر أَبَداً، وَيُطابَق مَعَ مِلَفّ شَرِكة الدَفع.',
                      'The employee types the approval number from the machine slip on a card payment. Never repeats; matched with the payment company file.'),
                  style: const TextStyle(color: VC.muted, fontSize: 12.5)),
              const SizedBox(height: 6),
              for (final (k, ar, en) in [
                ('card_approval_code', 'شاشة دَفع التَذكَرة', 'Ticket payment screen'),
                ('member_card_approval', 'بَيع وَتَجديد العُضويّات', 'Selling / renewing memberships'),
              ]) ...[
                const SizedBox(height: 8),
                Text(tx(context, ar, en), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'off', icon: const Icon(Icons.visibility_off_outlined), label: Text(tx(context, 'مَخفيّة', 'Hidden'))),
                    ButtonSegment(value: 'optional', icon: const Icon(Icons.edit_outlined), label: Text(tx(context, 'اختياريّة', 'Optional'))),
                    ButtonSegment(value: 'required', icon: const Icon(Icons.lock_outline), label: Text(tx(context, 'إجباريّة', 'Required'))),
                  ],
                  selected: {approvalOf(k)},
                  onSelectionChanged: !_edit ? null : (v) => toggleValue(k, v.first),
                ),
              ],
            ]),
          ),
        );

    // staff sign-in method of the point (enforced by the server: password vs card; NFC / QR by the app)
    // staff sign-in methods: any of password / NFC / QR (several at once); old rows: one value or sinin_w_card
    const loginOrder = ['password', 'nfc', 'qr'];
    final loginSet = <String>{
      for (final x in vStr(s['staff_login']).split(',')) if (loginOrder.contains(x.trim())) x.trim(),
    };
    if (loginSet.isEmpty) loginSet.addAll(s['sinin_w_card'] == false ? const ['nfc', 'qr'] : const ['password']);
    Widget loginPicker() => SizedBox(
          width: 470,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tx(context, 'طُرُق دُخول المُوَظَّف لِلوَرديّة', 'Staff sign-in methods for the shift'), style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(
                  tx(context, 'اختَر طَريقة أَو أَكثَر. التَطبيق يَعرِض المُختار فَقَط، وَالسيرفَر يَرفُض غَيره.',
                      'Pick one or more. The app shows only those, and the server refuses any other.'),
                  style: const TextStyle(color: VC.muted, fontSize: 12.5)),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                multiSelectionEnabled: true,
                emptySelectionAllowed: false,
                segments: [
                  ButtonSegment(value: 'password', icon: const Icon(Icons.password_rounded), label: Text(tx(context, 'اسم وَكَلِمة مُرور', 'User + password'))),
                  const ButtonSegment(value: 'nfc', icon: Icon(Icons.nfc_rounded), label: Text('NFC')),
                  const ButtonSegment(value: 'qr', icon: Icon(Icons.qr_code_2_rounded), label: Text('QR')),
                ],
                selected: loginSet,
                onSelectionChanged: !_edit
                    ? null
                    : (v) {
                        final list = [for (final x in loginOrder) if (v.contains(x)) x];
                        _save('vva_point_settings_save', {
                          'p_point': widget.pointId,
                          // sinin_w_card is kept in step for tablets on older versions
                          'p_data': {'staff_login': list.join(','), 'sinin_w_card': list.contains('password')},
                        });
                      },
              ),
            ]),
          ),
        );

    // pay before the car comes (hourly): minutes to leave + what happens after; validation: minutes to leave
    Widget minutesPicker(String k, String ar, String en, List<int> values, {bool zeroOff = false, bool enabled = true}) => SizedBox(
          width: 230,
          child: DropdownButtonFormField<int>(
            value: values.contains(vNum(s[k]).toInt()) ? vNum(s[k]).toInt() : values.first,
            isExpanded: true,
            decoration: InputDecoration(labelText: tx(context, ar, en), isDense: true, prefixIcon: const Icon(Icons.timer_outlined)),
            items: [
              for (final v in values)
                DropdownMenuItem(value: v, child: Text(v == 0 && zeroOff ? tx(context, 'مُطفَأ – بِدون وَقت خُروج', 'Off – no time to leave') : tx(context, '$v دَقيقة', '$v min'))),
            ],
            onChanged: !_edit || !enabled ? null : (v) => toggleValue(k, v ?? values.first),
          ),
        );
    final after = vStr(s['prepay_after']) == 'alert' ? 'alert' : 'recalc';
    Widget prepayBox() => SizedBox(
          width: 470,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 12, runSpacing: 10, children: [
                minutesPicker('prepay_grace_min', 'وَقت الخُروج بَعد الدَفع (نِقاط الوَقت)', 'Time to leave after paying (hourly)', const [0, 5, 10, 15, 20, 30, 45, 60],
                    zeroOff: true, enabled: vBool(s['prepay_enabled'])),
              ]),
              const SizedBox(height: 8),
              Text(tx(context, 'بَعد انتِهاء وَقت الخُروج', 'After the time to leave'), style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'recalc', icon: const Icon(Icons.calculate_outlined), label: Text(tx(context, 'إعادة الحِساب وَتَحصيل الفَرق', 'Charge again, collect the difference'))),
                  ButtonSegment(value: 'alert', icon: const Icon(Icons.notifications_none), label: Text(tx(context, 'تَنبيه فَقَط', 'Alert only'))),
                ],
                selected: {after},
                onSelectionChanged: !_edit || !vBool(s['prepay_enabled']) || vNum(s['prepay_grace_min']) <= 0 ? null : (v) => toggleValue('prepay_after', v.first),
              ),
              const SizedBox(height: 4),
              Text(
                  tx(context, 'إعادة الحِساب: السِعر مِن وَقت الدُخول حَتّى الخُروج الفِعليّ، ناقِص المَدفوع – وَالفَرق بِإيصال مُستَقِلّ.',
                      'Charge again: the price from the entry to the real exit, minus what was paid – the difference on its own receipt.'),
                  style: const TextStyle(color: VC.muted, fontSize: 12)),
            ]),
          ),
        );

    // on-screen paper per printout kind: on/off + seconds, and the printing sound
    Widget previewRow(String k, IconData icon, String ar, String en) {
      final secs = vNum(s[k]).toInt();
      final on = secs > 0;
      return Container(
        width: 470,
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
        decoration: BoxDecoration(
          border: Border.all(color: (on ? VC.ok : VC.muted).withValues(alpha: on ? 0.45 : 0.25)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Icon(icon, size: 20, color: on ? VC.gold : VC.muted),
          const SizedBox(width: 10),
          Expanded(child: Text(tx(context, ar, en), style: const TextStyle(fontWeight: FontWeight.w700))),
          if (on)
            DropdownButton<int>(
              value: secs.clamp(1, 30),
              underline: const SizedBox(),
              items: [for (final v in const [1, 2, 3, 4, 5, 6, 8, 10, 15, 20, 30]) DropdownMenuItem(value: v, child: Text(tx(context, '$v ث', '$v s')))],
              onChanged: !_edit ? null : (v) => toggleValue(k, v ?? 3),
            ),
          Switch(value: on, onChanged: !_edit ? null : (v) => toggleValue(k, v ? 3 : 0)),
        ]),
      );
    }

    // "Show / print" of a saved ticket: print it again – only the customer copy, every part, or not at all
    final again = const {'customer', 'all', 'off'}.contains(vStr(s['reprint_ticket'])) ? vStr(s['reprint_ticket']) : 'customer';
    Widget reprintPicker() => SizedBox(
          width: 470,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tx(context, 'إعادة طِباعة التَذكَرة عِند عَرضها', 'Print the ticket again when it is shown'), style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(
                  tx(context, 'مِن "Show / print" في تَفاصيل التَذكَرة وَ "Show ticket" في اللَوحة. الطِباعة الأُولى عِند الاستِلام لا تَتَغَيَّر (كُلّ الأَجزاء).',
                      'From "Show / print" in the ticket details and "Show ticket" on the board. The first print on receiving the car is unchanged (all parts).'),
                  style: const TextStyle(color: VC.muted, fontSize: 12)),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'customer', icon: const Icon(Icons.person_outline), label: Text(tx(context, 'جُزء العَميل فَقَط', 'Customer copy only'))),
                  ButtonSegment(value: 'all', icon: const Icon(Icons.copy_all_outlined), label: Text(tx(context, 'كُلّ الأَجزاء', 'All parts'))),
                  ButtonSegment(value: 'off', icon: const Icon(Icons.print_disabled_outlined), label: Text(tx(context, 'مُغلَقة', 'Off'))),
                ],
                selected: {again},
                onSelectionChanged: !_edit
                    ? null
                    : (v) => _save('vva_point_settings_save', {
                          'p_point': widget.pointId,
                          'p_data': {'reprint_ticket': v.first},
                        }),
              ),
            ]),
          ),
        );

    // devices of the point: limits per kind + the registered devices (approval is in Settings ▸ Numbering ▸ Tablets)
    Widget limitPicker(String k, IconData icon, String ar, String en) {
      final cur = s[k] == null ? null : vNum(s[k]).toInt();
      return SizedBox(
        width: 230,
        child: DropdownButtonFormField<int?>(
          value: cur,
          isExpanded: true,
          decoration: InputDecoration(labelText: tx(context, ar, en), prefixIcon: Icon(icon), isDense: true),
          items: [
            DropdownMenuItem<int?>(value: null, child: Text(tx(context, 'بِدون حَدّ', 'No limit'))),
            for (var i = 0; i <= 10; i++) DropdownMenuItem<int?>(value: i, child: Text('$i')),
          ],
          onChanged: !_edit ? null : (v) => _save('vva_point_settings_save', {'p_point': widget.pointId, 'p_data': {k: v}}),
        ),
      );
    }

    final devices = vList(d['devices']);
    int used(String kind) => devices.where((x) => vStr(x['kind']) == kind && vStr(x['status']) != 'blocked').length;
    Widget devicesSection() => VPanel(
          title: tx(context, 'الأَجهِزة', 'Devices'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.tablet_android_outlined, size: 18, color: VC.gold),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    tx(context,
                        'كُلّ جِهاز يُرسِل رَقمه وَبَياناته (المُوديل وَنُسخة أَندرويد وَنُسخة التَطبيق) عِند دُخول المُوَظَّف. الجِهاز الزائِد عَن الحَدّ يُوقَف تِلقائيّاً وَلا يَفتَح وَرديّة. المُوافَقة وَالإيقاف وَالاستِبدال مِن: الإعدادات ← نِظام التَرقيم ← الأَجهِزة.',
                        'Every device sends its number and details (model, Android and app version) when staff sign in. A device over the limit is blocked automatically and cannot open a shift. Approve, block or replace in Settings ▸ Numbering ▸ Tablets.'),
                    style: const TextStyle(color: VC.muted, fontSize: 12.5)),
              ),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 16, runSpacing: 12, children: [
              limitPicker('max_valet_devices', Icons.tablet_android_outlined, 'تابلت الفاليه (المَسموح)', 'Valet tablets (allowed)'),
              limitPicker('max_keyrack_devices', Icons.key_outlined, 'أَجهِزة الكي راك (المَسموح)', 'Key rack devices (allowed)'),
            ]),
            const SizedBox(height: 8),
            Text(
                tx(context, 'مُستَخدَم الآن: فاليه ${used('valet')} · كي راك ${used('keyrack')}',
                    'In use now: valet ${used('valet')} · key rack ${used('keyrack')}'),
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            if (devices.isEmpty)
              Text(tx(context, 'لا يوجَد جِهاز مُسَجَّل بَعد (يُسَجَّل مِن النُسخة 2.3.1).', 'No device registered yet (registered from version 2.3.1).'),
                  style: const TextStyle(color: VC.muted))
            else
              for (final x in devices)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(vStr(x['kind']) == 'keyrack' ? Icons.key_outlined : Icons.tablet_android_outlined,
                      color: switch (vStr(x['status'])) { 'active' => VC.ok, 'pending' => VC.warn, _ => VC.bad }),
                  title: Text(
                      '${x['short_code'] == null ? tx(context, 'بِدون رَقم', 'No number') : tx(context, 'رَقم ${'${x['short_code']}'.padLeft(2, '0')}', 'No. ${'${x['short_code']}'.padLeft(2, '0')}')}'
                      ' · ${switch (vStr(x['kind'])) { 'keyrack' => tx(context, 'كي راك', 'Key rack'), 'valet' => tx(context, 'فاليه', 'Valet'), _ => tx(context, 'غَير مَعروف', 'Unknown') }}'
                      ' · ${switch (vStr(x['status'])) { 'active' => tx(context, 'شَغّال', 'Active'), 'pending' => tx(context, 'مُستَنّي مُوافَقة', 'Waiting'), _ => tx(context, 'مَوقوف', 'Blocked') }}'),
                  subtitle: Text([
                    vStr(x['model']),
                    if (vStr(x['os_version']).isNotEmpty) 'Android ${vStr(x['os_version'])}',
                    if (vStr(x['app_version']).isNotEmpty) 'app ${vStr(x['app_version'])}',
                    if (x['last_seen_at'] != null) VF.dt(vTime(x['last_seen_at'])),
                    if (vStr(x['status']) == 'blocked' && vStr(x['note']).isNotEmpty) vStr(x['note']),
                  ].where((e) => e.isNotEmpty).join(' · ')),
                ),
          ]),
        );

    return _page([
      // in the order the app is used: sign in → open the shift → add a ticket → before payment → payment → …
      devicesSection(),
      KeyBoardsPanel(pointId: widget.pointId, edit: _edit),
      section(Icons.login_rounded, '1 · دُخول المُوَظَّف', '1 · Staff sign-in',
          'أَوَّل شاشة في التَطبيق: طَريقة الدُخول، المَوقِع، وَخُروج مَن فَتَح الوَرديّة.',
          'The first screen of the app: how staff sign in, Location, and logging out of the shift opener.', [
        loginPicker(),
        sw('require_gps'),
        sw('opener_must_close'),
      ]),
      section(Icons.play_circle_outline_rounded, '2 · فَتح الوَرديّة', '2 · Opening the shift',
          'يُحَدَّد هُنا فَقَط وَيُطَبَّق مِن الوَرديّة التالية؛ التَطبيق يَعرِضه فَقَط. رَقم مَكينة الكارت يُكتَب بِاليَد في كُلّ وَرديّة.',
          'Set here only and applied from the next shift; the app only shows it. The card machine number is typed by hand every shift.', [
        sw('paid_first_or_paid_after'),
      ]),
      section(Icons.add_box_outlined, '3 · إضافة تَذكَرة', '3 · Add ticket',
          'ما يَظهَر لِلمُوَظَّف عِند استِلام السَيّارة، وَطَريقة قِراءة الكُروت وَاختيار السائِق.',
          'What the staff fill in when receiving a car, how cards are read and how the driver is picked.', [
        sw('require_print'),
        sw('show_hotel_pick'),
        sw('photo_in_out'),
        sw('nfc_qr_in_out'),
        readerPicker(),
        sw('price_group_customer'),
        sw('dropdown_parkingcar'),
      ]),
      section(Icons.receipt_long_outlined, '4 · الوَرَقة عَلى الشاشة', '4 · Paper on the screen',
          'عِند الطِباعة تَظهَر الوَرَقة عَلى الشاشة وَهي تَخرُج مِن الطابِعة، بِنَفس شَكل الوَرَقة المَطبوعة، لِعَدد الثَواني المُختار (لِكُلّ نَوع). تَظهَر حَتّى بِدون طابِعة لِيُصَوِّرها العَميل، وَمِن لَوحة التَذاكِر: "Show ticket".',
          'On printing, the paper appears on the screen coming out of the printer, the same as the printed one, for the chosen seconds (per kind). It also appears without a printer so the customer can take a photo, and from the board: "Show ticket".', [
        previewRow('preview_ticket_secs', Icons.confirmation_number_outlined, 'التَذكَرة', 'Ticket'),
        previewRow('preview_receipt_secs', Icons.receipt_outlined, 'فاتورة الدَفع', 'Payment receipt'),
        previewRow('preview_member_secs', Icons.card_membership_outlined, 'فاتورة المُشتَرِكين', 'Membership receipt'),
        previewRow('preview_shift_secs', Icons.summarize_outlined, 'تَقرير الوَرديّة', 'Shift report'),
        sw('preview_sound'),
        reprintPicker(),
      ]),
      section(Icons.rule_rounded, '5 · الصَفّ وَالمَوقِف وَالتَسليم', '5 · Driver in, parking, driver out',
          'إظهار أَو إخفاء كُلّ زِرّ في التَطبيق، وَهَل هو إجباريّ قَبل الدَفع. المَخفيّ لا يَكون إجباريّاً.',
          'Show or hide each button in the app, and whether it is required before payment. A hidden one is never required.', [
        sw('show_driver_in'),
        sw('drivers_in', enabled: vBool(s['show_driver_in']), lockAr: 'الزِرّ مَخفيّ', lockEn: 'The button is hidden'),
        sw('show_parking'),
        sw('parking_in_out', enabled: vBool(s['show_parking']), lockAr: 'الزِرّ مَخفيّ', lockEn: 'The button is hidden'),
        sw('show_driver_out'),
        sw('drivers_out', enabled: vBool(s['show_driver_out']), lockAr: 'الزِرّ مَخفيّ', lockEn: 'The button is hidden'),
      ]),
      section(Icons.point_of_sale_outlined, '6 · الدَفع وَالخُروج', '6 · Payment and check-out',
          'أَزرار شاشة الدَفع، وَالبَحث عَن التَذكَرة، وَرَقم المُوافَقة لِلكارت.', 'Payment screen buttons, finding the ticket and the card approval number.', [
        sw('color_states'),
        sw('prepay_enabled'),
        prepayBox(),
        SizedBox(
          width: 470,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              minutesPicker('validation_grace_min', 'وَقت الخُروج بَعد الفاليديشن (نِقاط الوَقت)', 'Time to leave after a validation (hourly)',
                  const [0, 10, 15, 20, 30, 45, 60, 90, 120], zeroOff: true),
              const SizedBox(height: 4),
              Text(tx(context, 'بَعده يَبدَأ الحِساب مِن جَديد بِسِعر النُقطة. "مُطفَأ" = الفاليديشن يُغَطّي حَتّى الخُروج.',
                      'After it the time is charged again at the point price. "Off" = the validation covers until the exit.'),
                  style: const TextStyle(color: VC.muted, fontSize: 12)),
            ]),
          ),
        ),
        sw('valet_validate'),
        sw('stamp_ticket'),
        // the Finished screen: a checked-out car stays there N minutes (repark possible), then it is closed by itself
        SizedBox(
          width: 470,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 300,
                child: DropdownButtonFormField<int>(
                  value: const [0, 5, 10, 15, 20, 30, 45, 60, 90, 120].contains(s['finished_visible_min'] == null ? 30 : vNum(s['finished_visible_min']).toInt())
                      ? (s['finished_visible_min'] == null ? 30 : vNum(s['finished_visible_min']).toInt())
                      : 30,
                  isExpanded: true,
                  decoration: InputDecoration(
                      labelText: tx(context, 'بَقاء التَذكَرة في شاشة Finished', 'Time on the Finished screen'), isDense: true, prefixIcon: const Icon(Icons.timer_outlined)),
                  items: [
                    for (final v in const [0, 5, 10, 15, 20, 30, 45, 60, 90, 120])
                      DropdownMenuItem(value: v, child: Text(v == 0 ? tx(context, 'كُلّ الوَرديّة', 'The whole shift') : tx(context, '$v دَقيقة', '$v min'))),
                  ],
                  onChanged: !_edit ? null : (v) => toggleValue('finished_visible_min', v ?? 30),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                  tx(context, 'بَعد الخُروج تَظهَر التَذكَرة في شاشة Finished وَيُمكِن إرجاعها لِلباركِنج (Repark). بَعد هذا الوَقت تُقفَل وَتَختَفي تِلقائيّاً.',
                      'After check-out the ticket shows on the Finished screen and can be reparked. After this time it is closed and leaves the screen.'),
                  style: const TextStyle(color: VC.muted, fontSize: 12)),
            ]),
          ),
        ),
        // VIP numbering on the key board: its own numbers, or the same numbering as the other cars
        SizedBox(
          width: 470,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tx(context, 'تَرقيم سَيّارات VIP عَلى تابلو المَفاتيح', 'VIP numbering on the key board'), style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'separate', icon: const Icon(Icons.workspace_premium_outlined), label: Text(tx(context, 'تابلو مُنفَصِل لِلـ VIP', 'Own VIP numbers'))),
                  ButtonSegment(value: 'same', icon: const Icon(Icons.format_list_numbered), label: Text(tx(context, 'نَفس التابلو', 'Same board'))),
                ],
                selected: {vStr(s['vip_slots']) == 'same' ? 'same' : 'separate'},
                onSelectionChanged: !_edit ? null : (v) => toggleValue('vip_slots', v.first),
              ),
              const SizedBox(height: 4),
              Text(
                  vStr(s['vip_slots']) == 'same'
                      ? tx(context, 'VIP يَأخُذ أَصغَر رَقم فاضي مَعَ باقي السَيّارات (1، 2، 3 … لِلكُلّ).', 'VIP takes the lowest free number together with the other cars (1, 2, 3 … for all).')
                      : tx(context, 'VIP لَه تَرقيم خاصّ يَبدَأ مِن 1، مُنفَصِل عَن باقي السَيّارات.', 'VIP has its own numbers from 1, apart from the other cars.'),
                  style: const TextStyle(color: VC.muted, fontSize: 12)),
              Text(tx(context, 'يُطَبَّق عَلى التَذاكِر الجَديدة.', 'Applies to new tickets.'), style: const TextStyle(color: VC.muted, fontSize: 12)),
            ]),
          ),
        ),
        findPicker(),
        approvalPicker(),
      ]),
      section(Icons.person_pin_circle_outlined, '7 · العُمَلاء', '7 · Customers',
          'ما يَستَطيع عَميل السَيّارة فِعله مِن هاتِفه.', 'What the car owner can do from their phone.', [
        sw('car_request'),
      ]),
      section(Icons.schedule_rounded, '8 · الحُضور وَالانصِراف', '8 · Check-in and check-out',
          'حُضور وَانصِراف السائِقين في النُقطة.', 'Drivers checking in and out at the point.', [
        sw('dropdown_time_in_out'),
      ]),
      section(Icons.key_outlined, '9 · تَطبيق المَفاتيح', '9 · Key rack',
          'مُتَحَكِّم المَفاتيح وَالدَفع عِنده. الدَفع عِنده يَعمَل فَقَط مَعَ تَشغيل تَطبيق المَفاتيح.',
          'The key controller and paying at the key rack. Paying there works only when the key rack app is on.', [
        sw('key_rack_w_sites_or_allow'),
        sw('paid_with_app_or_keyrack', enabled: vBool(s['key_rack_w_sites_or_allow']),
            lockAr: 'شَغِّل تَطبيق المَفاتيح أَوَّلاً.', lockEn: 'Turn the key rack app on first.'),
      ]),
      section(Icons.card_membership_outlined, '10 · العُضويّات', '10 · Memberships',
          'صَفحة المُشتَرِكين وَزِرّ المُشتَرِكين في شاشة التَذكَرة: تَطبيق الفاليه ← الاشتِراكات ← تَبويب "النِقاط". رَقم المُوافَقة لِلعُضويّات في القِسم 6.',
          'Members page and the member button on the ticket screen: Valet app → Memberships → "Points" tab. The membership approval number is in section 6.', [
        SizedBox(
          width: 470,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
                tx(context, 'صَفحة المُشتَرِكين · زِرّ المُشتَرِكين في شاشة التَذكَرة',
                    'Members page · Member button on the ticket screen'),
                style: const TextStyle(color: VC.muted, fontSize: 12.5)),
          ),
        ),
      ]),
      section(Icons.supervisor_account_outlined, '11 · المُشرِف', '11 · Supervisor',
          'ما يَراه المُشرِف الذي فَتَح الوَرديّة في التَطبيق.', 'What the supervisor who opened the shift sees in the app.', [
        sw('staff_eval'),
        sw('supervisor_roster'),
        sw('show_policies'),
      ]),
      VPanel(
        title: tx(context, 'التَذاكِر وَالرُسوم', 'Tickets and charges'),
        child: Row(children: [
          const Icon(Icons.sell_outlined, color: VC.gold),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                tx(context, 'مَواعيد المَوقِع، المَبيت، التِكِت المَفقود، الدَقائِق المَجّانيّة وَالأَيّام الخاصّة اِتنَقَلِت لِتَبويب "الأَسعار" (لِلنُقطة وَلِكُلّ فَرع).',
                    'Site hours, overnight, lost ticket, free minutes and special days moved to the "Prices" tab (for the point and for each branch).'),
                style: const TextStyle(color: VC.muted)),
          ),
          TextButton(onPressed: () => DefaultTabController.of(context).animateTo(1), child: Text(tx(context, 'الأَسعار', 'Prices'))),
        ]),
      ),
      _branchesPanel(d),
      TicketPartsPanel(
        value: s['ticket_parts'],
        edit: _edit,
        pointId: widget.pointId,
        pointName: '${vMap(d['point'])['name'] ?? ''}',
        receiptLayout: s['receipt_layout'],
        shiftLayout: s['shift_layout'],
        onSaveLayout: (column, layout) => _save('vva_point_settings_save', {
          'p_point': widget.pointId,
          'p_data': {column: layout},
        }),
        onSave: (parts) => _save('vva_point_settings_save', {
          'p_point': widget.pointId,
          'p_data': {'ticket_parts': parts},
        }),
      ),
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
      PricingRulesPanel(
        pointId: widget.pointId,
        settings: vMap(d['settings']),
        clients: vList(d['clients']),
        edit: _edit,
        onSavePoint: (data) => _save('vva_point_settings_save', {'p_point': widget.pointId, 'p_data': data}),
      ),
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

  num _vat(VJson d) => vMap(d['settings'])['vat_rate'] == null ? 0.05 : vNum(vMap(d['settings'])['vat_rate']);

  /// VIP price / membership plan: name + amount typed with VAT included or added (stored NET).
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
      _CardMachines(pointId: widget.pointId, edit: _edit),
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

/// 💳 مَكَن الكُروت (Paymob) لِلنُقطة — يَختارها المُوَظَّف عِند فَتح الوَرديّة في تَطبيق الفاليه (أَو يُضيف رَقماً جَديداً)،
/// وَتُعَدَّل هُنا. الرَقم الجَديد مِن التَطبيق يُسَجَّل عَلى النُقطة تِلقائيّاً.
class _CardMachines extends StatefulWidget {
  const _CardMachines({required this.pointId, required this.edit});
  final String pointId;
  final bool edit;

  @override
  State<_CardMachines> createState() => _CardMachinesState();
}

class _CardMachinesState extends State<_CardMachines> {
  final _code = TextEditingController();
  final _label = TextEditingController();
  List<VJson>? _rows;
  Object? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await ValetAdmin.I.call('vva_card_terminals', {'p_point': widget.pointId});
      if (mounted) {
        setState(() {
          _rows = vList(d['terminals']);
          _err = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _err = e);
    }
  }

  Future<void> _save({String? id, required String code, String? label, bool active = true}) async {
    final r = await vGuard(
        context,
        () => ValetAdmin.I.call('vva_card_terminal_save',
            {'p_id': id, 'p_point': widget.pointId, 'p_code': code, 'p_label': label, 'p_active': active}),
        ok: tx(context, 'تَمّ الحِفظ.', 'Saved.'));
    if (r != null) {
      if (id == null) {
        _code.clear();
        _label.clear();
      }
      _load();
    }
  }

  Future<void> _editRow(VJson t) async {
    final code = TextEditingController(text: vStr(t['code']));
    final label = TextEditingController(text: vStr(t['label']));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tx(ctx, 'تَعديل الماكينة', 'Edit machine')),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: code, decoration: InputDecoration(labelText: tx(ctx, 'رَقم الماكينة *', 'Machine number *'))),
            const SizedBox(height: 10),
            TextField(controller: label, decoration: InputDecoration(labelText: tx(ctx, 'وَصف (اختِياريّ)', 'Label (optional)'))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tx(ctx, 'إلغاء', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tx(ctx, 'حِفظ', 'Save'))),
        ],
      ),
    );
    if (ok == true) await _save(id: vStr(t['id']), code: code.text, label: label.text, active: vBool(t['active']));
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return VPanel(
      title: tx(context, 'مَكَن الكُروت (Paymob)', 'Card machines (Paymob)'),
      actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            tx(context, 'المُوَظَّف يَختار الماكينة (أَو أَكتَر) عِند فَتح الوَرديّة في تَطبيق الفاليه، وَيِقدَر يُضيف رَقم جَديد. المَكَن هِنا هي الاختِيارات اللي بِتِظهَر لُه.',
                'Staff choose the machine(s) when opening the shift in the valet app and can add a new number. The machines here are the choices they see.'),
            style: const TextStyle(color: VC.muted, fontSize: 13)),
        const SizedBox(height: 10),
        if (widget.edit)
          Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(width: 200, child: TextField(controller: _code, decoration: InputDecoration(labelText: tx(context, 'رَقم الماكينة', 'Machine number')))),
            SizedBox(width: 220, child: TextField(controller: _label, decoration: InputDecoration(labelText: tx(context, 'وَصف (اختِياريّ)', 'Label (optional)')))),
            OutlinedButton.icon(
              icon: const Icon(Icons.add),
              label: Text(tx(context, 'إضافة ماكينة', 'Add machine')),
              onPressed: () {
                if (_code.text.trim().isEmpty) return;
                _save(code: _code.text, label: _label.text);
              },
            ),
          ]),
        const SizedBox(height: 10),
        if (_err != null) Text(vErr(context, _err!), style: const TextStyle(color: VC.bad)),
        if (rows == null && _err == null) const LinearProgressIndicator(minHeight: 2),
        if (rows != null)
          VTable(
            empty: tx(context, 'لا تُوجَد مَكَن لِهذه النُقطة.', 'No machine for this point.'),
            columns: [
              DataColumn(label: Text(tx(context, 'رَقم الماكينة', 'Machine'))),
              DataColumn(label: Text(tx(context, 'الوَصف', 'Label'))),
              DataColumn(label: Text(tx(context, 'أُضيفَت مِن', 'Added from'))),
              DataColumn(label: Text(tx(context, 'آخِر استِخدام', 'Last used'))),
              DataColumn(label: Text(tx(context, 'فَعّالة', 'Active'))),
              const DataColumn(label: Text('')),
            ],
            rows: [
              for (final t in rows)
                DataRow(cells: [
                  DataCell(Text(vStr(t['code']), style: const TextStyle(fontWeight: FontWeight.w700))),
                  DataCell(Text(vStr(t['label']).isEmpty ? '-' : vStr(t['label']))),
                  DataCell(Text(vStr(t['created_by']) == 'valet app' ? tx(context, 'تَطبيق الفاليه', 'Valet app') : tx(context, 'الداشبورد', 'Dashboard'))),
                  DataCell(Text(VF.dt(vTime(t['last_used'])))),
                  DataCell(Switch(
                    value: vBool(t['active']),
                    onChanged: !widget.edit ? null : (v) => _save(id: vStr(t['id']), code: vStr(t['code']), label: vStr(t['label']), active: v),
                  )),
                  DataCell(!widget.edit ? const SizedBox() : IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _editRow(t))),
                ]),
            ],
          ),
      ]),
    );
  }
}
