import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/excel_exporter.dart';
import 'valet_admin.dart';
import 'valet_hub_ui.dart';
import 'valet_ui.dart';

/// 🕵️ تحليل الموظفين (DB 312) — إزاي الموظف بيستخدم التطبيق:
/// تنبيهات (تكتات ورا بعض بسرعة، تكت من غير علامة عربية حقيقية، نفس اللوحة مرتين، إعادة طباعة،
/// فرق مكنة الكارت، تكتات كارت آخر الشيفت)، كارت لكل موظف، وإعادة تشغيل الشيفت خطوة بخطوة.
class ValetStaffAnalyticsScreen extends StatefulWidget {
  const ValetStaffAnalyticsScreen({super.key});

  /// Test hook (screenshots).
  static Future<VJson> Function()? debugLoad;

  @override
  State<ValetStaffAnalyticsScreen> createState() => _ValetStaffAnalyticsScreenState();
}

const _ink = Color(0xFF0B0C0E);
const _line = Color(0xFFE2E8F0);
const _muted = Color(0xFF64748B);

class _ValetStaffAnalyticsScreenState extends State<ValetStaffAnalyticsScreen> {
  VJson? _d;
  Object? _err;
  String _point = ''; // '' = all points
  int _days = 7;
  String _kind = 'all';
  VJson _set = {};
  bool _dirty = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final now = DateTime.now().toUtc();
      final d = await (ValetStaffAnalyticsScreen.debugLoad?.call() ??
          ValetAdmin.I.call('vva_staff_analytics', {
            'p_point': _point.isEmpty ? null : _point,
            'p_from': now.subtract(Duration(days: _days)).toIso8601String(),
            'p_to': now.toIso8601String(),
          }));
      if (!mounted) return;
      setState(() {
        _d = d;
        _err = null;
        _set = Map<String, dynamic>.from((d['settings'] as Map?) ?? {});
        _dirty = false;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _err = e;
          _loading = false;
        });
      }
    }
  }

  void _s(String k, dynamic v) => setState(() {
        _set[k] = v;
        _dirty = true;
      });

  Future<void> _saveSettings() async {
    final r = await vGuard(context, () => ValetAdmin.I.call('vva_analytics_settings', {'p_point': _point, 'p_settings': _set}),
        ok: tx(context, 'تم حفظ إعدادات التحليل لهذه النقطة', 'Analysis settings saved'));
    if (r != null) _load();
  }

  // ---------------------------------------------------------------- texts

  static const _kinds = ['all', 'ghost', 'burst', 'duplicate', 'reprint', 'pos_diff', 'pos_padding'];

  String _kindName(BuildContext c, String k) => switch (k) {
        'ghost' => tx(c, 'تكت بدون عربية؟', 'Ticket with no car?'),
        'burst' => tx(c, 'تكتات ورا بعض', 'Burst of tickets'),
        'duplicate' => tx(c, 'نفس اللوحة مرتين', 'Same plate twice'),
        'reprint' => tx(c, 'إعادة طباعة', 'Reprints'),
        'pos_diff' => tx(c, 'فرق مكنة الكارت', 'Card machine difference'),
        'pos_padding' => tx(c, 'تكميل رقم المكنة', 'Filling the card total'),
        _ => tx(c, 'الكل', 'All'),
      };

  String _kindHelp(BuildContext c, String k) => switch (k) {
        'ghost' => tx(c, 'علامات إن مفيش عربية حقيقية: من غير صورة / موقف، اتقفل بعد دقايق، لوحة قصيرة أو أرقام مكررة، آخر ربع ساعة في الشيفت',
            'Signs of no real car: no photo / slot, closed after minutes, short or repeated plate, last 15 min of the shift'),
        'burst' => tx(c, 'عدد كبير من التكتات من نفس الموظف في دقايق قليلة (الرقم والدقايق من الإعدادات)',
            'Many tickets by one person within a few minutes (count and minutes in the settings)'),
        'duplicate' => tx(c, 'نفس رقم اللوحة على تكتين في نص ساعة', 'Same plate on two tickets within 30 min'),
        'reprint' => tx(c, 'نفس التكت اتطبع أكتر من مرة في الشيفت', 'The same ticket printed again in one shift'),
        'pos_diff' => tx(c, 'إجمالي مكنة الكارت اللي كتبه الموظف عند قفل الشيفت ≠ مدفوعات الكارت في التطبيق',
            'Card machine total typed at shift close ≠ card payments in the app'),
        'pos_padding' => tx(c, 'تكتات كارت مشكوك فيها في آخر 20 دقيقة من الشيفت (ممكن تكون لتظبيط رقم المكنة)',
            'Doubtful card tickets in the last 20 min of the shift (may be to match the card machine)'),
        _ => '',
      };

  static String _time(dynamic v) {
    final t = DateTime.tryParse(vStr(v))?.toLocal();
    if (t == null) return '—';
    String two(int x) => x.toString().padLeft(2, '0');
    return '${two(t.day)}/${two(t.month)} ${two(t.hour)}:${two(t.minute)}';
  }

  static String _hm(dynamic v) {
    final t = DateTime.tryParse(vStr(v))?.toLocal();
    if (t == null) return '—';
    String two(int x) => x.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  static String _short(dynamic code) {
    final p = vStr(code).split('-');
    return p.length >= 2 ? p[1] : vStr(code);
  }

  // ---------------------------------------------------------------- export

  Future<void> _export() async {
    final d = _d;
    if (d == null) return;
    await vExport(context, 'staff_analysis', [
      ExcelSheet(name: 'Alerts', headers: const ['Level', 'Kind', 'Time', 'Point', 'Shift', 'Employee', 'Tickets', 'Details'], rows: [
        for (final a in vList(d['alerts']))
          [vStr(a['level']), vStr(a['kind']), _time(a['at']), vStr(a['point']), vStr(a['shift']), vStr(a['employee']),
            (a['tickets'] as List? ?? const []).join(' '), vStr(a['text'])],
      ]),
      ExcelSheet(
          name: 'Employees',
          headers: const ['Employee', 'Code', 'Tickets', 'Suspicious', 'Voids', 'Free', 'Discounts', 'Card', 'Cash', 'No photo', 'Avg form (s)', 'Reprints', 'Taps'],
          rows: [
            for (final e in vList(d['employees']))
              [vStr(e['employee']), vStr(e['code']), vNum(e['tickets']), vNum(e['suspicious']), vNum(e['voids']), vNum(e['free']), vNum(e['discounts']),
                vNum(e['card']), vNum(e['cash']), vNum(e['no_photo']), vStr(e['avg_save_sec']), vNum(e['reprints']), vNum(e['taps'])],
          ]),
    ]);
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    if (_err != null && _d == null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(vErr(context, _err!)),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: _load, child: Text(tx(context, 'إعادة المحاولة', 'Retry'))),
      ]));
    }
    final d = _d;
    if (d == null) return const Center(child: CircularProgressIndicator());
    final alerts = vList(d['alerts']);
    final shown = _kind == 'all' ? alerts : alerts.where((a) => vStr(a['kind']) == _kind).toList();
    final emps = vList(d['employees']);
    final pts = vList(d['points']);
    final red = alerts.where((a) => vStr(a['level']) == 'red').length;
    final suspicious = emps.fold<num>(0, (s, e) => s + vNum(e['suspicious']));
    final tickets = emps.fold<num>(0, (s, e) => s + vNum(e['tickets']));
    return ListView(padding: const EdgeInsets.only(bottom: 30), children: [
      HubHead(
        title: tx(context, 'تطبيق الفاليه — تحليل الموظفين', 'Valet app — staff analysis'),
        subtitle: tx(context, 'الموظف بيستخدم التطبيق إزاي: الضغطات، الطباعة، سرعة الإدخال، التكتات المشكوك فيها وقفل الشيفت',
            'How the staff use the app: taps, prints, entry speed, doubtful tickets and shift close'),
        actions: [
          if (_loading) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          HubButton(label: 'Excel', icon: Icons.table_view, onPressed: alerts.isEmpty && emps.isEmpty ? null : _export),
          HubButton(label: tx(context, 'تحديث', 'Refresh'), icon: Icons.refresh, onPressed: _load),
        ],
      ),
      HubChips(
        items: [
          ('', tx(context, 'كل النقاط', 'All points'), null),
          for (final p in pts) (vStr(p['id']), vStr(p['name']), null),
        ],
        value: _point,
        onChanged: (v) {
          setState(() => _point = v);
          _load();
        },
      ),
      HubChips(
        items: [
          ('1', tx(context, 'آخر 24 ساعة', 'Last 24 h'), null),
          ('7', tx(context, 'آخر 7 أيام', 'Last 7 days'), null),
          ('30', tx(context, 'آخر 30 يوم', 'Last 30 days'), null),
        ],
        value: '$_days',
        onChanged: (v) {
          setState(() => _days = int.parse(v));
          _load();
        },
      ),
      HubKpis([
        HubKpi(Icons.warning_amber_rounded, '${alerts.length}', tx(context, 'تنبيه', 'Alerts'), note: tx(context, '$red أحمر', '$red red')),
        HubKpi(Icons.confirmation_number_outlined, '${tickets.toInt()}', tx(context, 'تكت في الفترة', 'Tickets in the period')),
        HubKpi(Icons.help_outline, '${suspicious.toInt()}', tx(context, 'تكت مشكوك فيه', 'Doubtful tickets')),
        HubKpi(Icons.badge_outlined, '${emps.length}', tx(context, 'موظف', 'Employees')),
      ]),
      if (_point.isNotEmpty) _settingsPanel(context),
      _section(context, tx(context, 'التنبيهات', 'Alerts')),
      HubChips(
        items: [
          for (final k in _kinds) (k, _kindName(context, k), k == 'all' ? alerts.length : alerts.where((a) => vStr(a['kind']) == k).length),
        ],
        value: _kind,
        onChanged: (v) => setState(() => _kind = v),
      ),
      if (_kind != 'all')
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Text(_kindHelp(context, _kind), style: const TextStyle(color: _muted, fontSize: 12.5)),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
        child: shown.isEmpty
            ? HubCard(child: Text(tx(context, 'مفيش تنبيهات في الفترة دي 👌', 'No alerts in this period 👌'), style: const TextStyle(color: _muted)))
            : Column(children: [for (final a in shown.take(150)) Padding(padding: const EdgeInsets.only(bottom: 8), child: _alertCard(context, a))]),
      ),
      _section(context, tx(context, 'الموظفين', 'Employees')),
      Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 0), child: _empTable(context, emps)),
      _section(context, tx(context, 'التكتات حسب الساعة', 'Tickets by hour')),
      Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 0), child: _hours(context, vList(d['hours']))),
      _section(context, tx(context, 'الشيفتات — اضغط لإعادة التشغيل خطوة بخطوة', 'Shifts — tap to replay step by step')),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: Column(children: [
          for (final s in vList(d['shifts']).take(60))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: HubCard(
                onTap: () => _openShift(vStr(s['id']), vStr(s['code'])),
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
                child: Row(children: [
                  const Icon(Icons.play_circle_outline),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${vStr(s['code'])} · ${vStr(s['point'])}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text('${vStr(s['opened_by'])} · ${_time(s['start'])} → ${s['end'] == null ? tx(context, 'مفتوح', 'open') : _time(s['end'])}',
                          style: const TextStyle(color: _muted, fontSize: 12.5)),
                    ]),
                  ),
                  hubPill(tx(context, '${vNum(s['tickets']).toInt()} تكت', '${vNum(s['tickets']).toInt()} tickets')),
                  const SizedBox(width: 6),
                  hubPill(tx(context, '${vNum(s['events']).toInt()} حركة', '${vNum(s['events']).toInt()} events'), kind: vNum(s['events']) > 0 ? 'info' : 'mut'),
                  if (s['pos'] != null) ...[const SizedBox(width: 6), hubPill('POS ${vNum(s['pos'])}', kind: 'dark')],
                ]),
              ),
            ),
        ]),
      ),
    ]);
  }

  Widget _section(BuildContext c, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
        child: Text(t, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      );

  Widget _alertCard(BuildContext c, VJson a) {
    final lvl = vStr(a['level']);
    final tickets = (a['tickets'] as List? ?? const []).map(vStr).where((x) => x.isNotEmpty).toList();
    return HubCard(
      strong: lvl == 'red',
      onTap: vStr(a['shift_id']).isEmpty ? null : () => _openShift(vStr(a['shift_id']), vStr(a['shift'])),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.only(top: 5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: lvl == 'red' ? _ink : Colors.white,
            border: Border.all(color: _ink, width: lvl == 'yellow' ? 1 : 2.5),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              hubPill(_kindName(c, vStr(a['kind'])), kind: lvl == 'red' ? 'dark' : 'mut'),
              Text(vStr(a['employee']).isEmpty ? tx(c, 'غير معروف', 'Unknown') : vStr(a['employee']), style: const TextStyle(fontWeight: FontWeight.w800)),
              Text('· ${vStr(a['point'])} · ${vStr(a['shift'])}', style: const TextStyle(color: _muted, fontSize: 12.5)),
            ]),
            const SizedBox(height: 4),
            Text(vStr(a['text']), textDirection: TextDirection.ltr),
            if (tickets.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(tickets.take(12).map(_short).join(' · ') + (tickets.length > 12 ? ' …' : ''),
                    style: const TextStyle(color: _muted, fontSize: 12, fontFamily: 'monospace')),
              ),
          ]),
        ),
        const SizedBox(width: 8),
        Text(_time(a['at']), style: const TextStyle(color: _muted, fontSize: 12)),
      ]),
    );
  }

  Widget _empTable(BuildContext c, List<VJson> emps) {
    if (emps.isEmpty) return HubCard(child: Text(tx(c, 'مفيش تكتات في الفترة دي', 'No tickets in this period'), style: const TextStyle(color: _muted)));
    final cols = <(String, String)>[
      (tx(c, 'الموظف', 'Employee'), 'employee'),
      (tx(c, 'تكتات', 'Tickets'), 'tickets'),
      (tx(c, 'مشكوك', 'Doubtful'), 'suspicious'),
      (tx(c, 'ملغي', 'Void'), 'voids'),
      (tx(c, 'مجاني', 'Free'), 'free'),
      (tx(c, 'خصم', 'Discount'), 'discounts'),
      (tx(c, 'كارت', 'Card'), 'card'),
      (tx(c, 'كاش', 'Cash'), 'cash'),
      (tx(c, 'بدون صورة', 'No photo'), 'no_photo'),
      (tx(c, 'وقت التكت (ث)', 'Form time (s)'), 'avg_save_sec'),
      (tx(c, 'إعادة طباعة', 'Reprints'), 'reprints'),
      (tx(c, 'ضغطات', 'Taps'), 'taps'),
    ];
    return HubCard(
      padding: EdgeInsets.zero,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 40,
          dataRowMinHeight: 38,
          dataRowMaxHeight: 44,
          columnSpacing: 22,
          headingTextStyle: const TextStyle(fontWeight: FontWeight.w800, color: _ink, fontSize: 12.5),
          columns: [for (final (l, _) in cols) DataColumn(label: Text(l), numeric: l != cols.first.$1)],
          rows: [
            for (final e in emps)
              DataRow(cells: [
                for (final (_, k) in cols)
                  DataCell(Text(
                    k == 'employee' ? vStr(e[k]) : (e[k] == null ? '—' : '${k == 'avg_save_sec' ? vNum(e[k]) : vNum(e[k]).toInt()}'),
                    style: TextStyle(
                      fontWeight: k == 'employee' || (k == 'suspicious' && vNum(e[k]) > 0) ? FontWeight.w800 : FontWeight.w500,
                      decoration: k == 'suspicious' && vNum(e[k]) > 0 ? TextDecoration.underline : null,
                    ),
                  )),
              ]),
          ],
        ),
      ),
    );
  }

  Widget _hours(BuildContext c, List<VJson> hours) {
    final byH = {for (final h in hours) vNum(h['h']).toInt(): vNum(h['n']).toInt()};
    final mx = byH.values.fold<int>(1, (m, v) => v > m ? v : m);
    return HubCard(
      child: SizedBox(
        height: 120,
        child: Row(
          textDirection: TextDirection.ltr,crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var h = 0; h < 24; h++)
            Expanded(
              child: Tooltip(
                message: '$h:00 · ${byH[h] ?? 0}',
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Container(
                    height: 90 * (byH[h] ?? 0) / mx,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(color: _ink, borderRadius: BorderRadius.circular(3)),
                  ),
                  const SizedBox(height: 4),
                  Text(h % 3 == 0 ? '$h' : '', style: const TextStyle(fontSize: 10, color: _muted)),
                ]),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _settingsPanel(BuildContext c) {
    Widget sw(String k, String ar, String en, String hAr, String hEn, {bool d = false}) => SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _set[k] is bool ? _set[k] as bool : d,
          onChanged: (v) => _s(k, v),
          title: Text(tx(c, ar, en), style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(tx(c, hAr, hEn), style: const TextStyle(fontSize: 12)),
        );
    Widget num(String k, String ar, String en, int d) => SizedBox(
          width: 190,
          child: TextFormField(
            key: ValueKey('$k-$_point-${_d.hashCode}'),
            initialValue: '${vNum(_set[k] ?? d).toInt()}',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: tx(c, ar, en), isDense: true),
            onChanged: (v) => _s(k, int.tryParse(v) ?? d),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: HubCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.tune),
            const SizedBox(width: 8),
            Expanded(child: Text(tx(c, 'أوبشنز التحليل لهذه النقطة', 'Analysis options of this point'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
            FilledButton.icon(onPressed: _dirty ? _saveSettings : null, icon: const Icon(Icons.save_outlined), label: Text(tx(c, 'حفظ', 'Save'))),
          ]),
          sw('analytics_on', 'تسجيل استخدام التطبيق', 'Record app usage',
              'التطبيق يبعت الشاشات والضغطات والطباعة ووقت كل تكت. لو مقفول: التنبيهات المبنية على التكتات بس هي اللي تشتغل',
              'The app sends screens, taps, prints and the time of each ticket. Off: only the alerts from the tickets work',
              d: true),
          sw('analytics_gps', 'موقع GPS مع الحركات', 'GPS with the events', 'كل حركة يتسجل معاها مكان الجهاز (كل 3 دقايق تقريباً)',
              'Each event carries the device position (about every 3 min)'),
          sw('shift_pos_total', 'إجمالي مكنة الكارت عند قفل الشيفت', 'Card machine total at shift close',
              'الموظف يطبع إجمالي المكنة ويكتبه قبل ما يشوف رقم التطبيق — أي فرق يطلع تنبيه',
              'The valet prints the machine total and types it before seeing the app number — any difference is an alert'),
          const SizedBox(height: 8),
          Wrap(spacing: 14, runSpacing: 10, children: [
            num('burst_count', 'تكتات ورا بعض (عدد)', 'Burst: tickets', 4),
            num('burst_minutes', 'في خلال (دقيقة)', 'Within (minutes)', 2),
            num('quick_close_minutes', 'تكت اتقفل أسرع من (دقيقة)', 'Closed faster than (min)', 5),
          ]),
        ]),
      ),
    );
  }

  Future<void> _openShift(String id, String code) async {
    if (id.isEmpty) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _ShiftReplay(id: id, code: code)));
  }
}

/// إعادة تشغيل الشيفت: كل حركة وتكت على خط زمني واحد.
class _ShiftReplay extends StatefulWidget {
  const _ShiftReplay({required this.id, required this.code});
  final String id;
  final String code;

  @override
  State<_ShiftReplay> createState() => _ShiftReplayState();
}

class _ShiftReplayState extends State<_ShiftReplay> {
  VJson? _d;
  Object? _err;
  bool _taps = false;

  @override
  void initState() {
    super.initState();
    ValetAdmin.I.call('vva_shift_timeline', {'p_shift': widget.id}).then((d) {
      if (mounted) setState(() => _d = d);
    }).catchError((Object e) {
      if (mounted) setState(() => _err = e);
    });
  }

  static (IconData, String) _icon(BuildContext c, VJson i) {
    final k = vStr(i['kind']);
    return switch (k) {
      'ticket_in' => (Icons.login, tx(c, 'تكت دخول', 'Ticket in')),
      'ticket_out' => (Icons.logout, tx(c, 'تكت خروج', 'Ticket out')),
      'ticket_save' => (Icons.timer_outlined, tx(c, 'حفظ التكت', 'Ticket saved')),
      'print' => (Icons.print_outlined, tx(c, 'طباعة', 'Print')),
      'reprint' => (Icons.print, tx(c, 'إعادة طباعة', 'Reprint')),
      'print_fail' => (Icons.print_disabled_outlined, tx(c, 'الطباعة فشلت', 'Print failed')),
      'payment' => (Icons.payments_outlined, tx(c, 'دفع', 'Payment')),
      'shift_close' => (Icons.lock_outline, tx(c, 'قفل الشيفت', 'Shift close')),
      'pos_total' => (Icons.credit_card, tx(c, 'إجمالي مكنة الكارت', 'Card machine total')),
      'screen' => (Icons.phone_android, tx(c, 'شاشة', 'Screen')),
      'tap' => (Icons.touch_app_outlined, tx(c, 'ضغطة', 'Tap')),
      'pause' => (Icons.pause_circle_outline, tx(c, 'التطبيق في الخلفية', 'App in background')),
      'resume' => (Icons.play_circle_outline, tx(c, 'رجع للتطبيق', 'Back to the app')),
      'card' => (Icons.nfc, tx(c, 'كارت', 'Card')),
      _ => (Icons.bolt, k),
    };
  }

  String _detail(BuildContext c, VJson i) {
    final k = vStr(i['kind']);
    final m = (i['meta'] as Map?) ?? const {};
    final parts = <String>[
      if (vStr(i['ticket']).isNotEmpty) vStr(i['ticket']),
      if (vStr(i['plate']).isNotEmpty) vStr(i['plate']),
      if (k == 'screen') '${vStr(i['screen'])}${vStr(i['target']) == 'back' ? ' ←' : ''}',
      if (k == 'tap') '«${vStr(i['target'])}» · ${vStr(i['screen'])}',
      if (k == 'action') vStr(i['target']),
      if (k == 'ticket_save' && i['ms'] != null) tx(c, '${(vNum(i['ms']) / 1000).toStringAsFixed(0)} ثانية', '${(vNum(i['ms']) / 1000).toStringAsFixed(0)} s'),
      if (k == 'ticket_save' && m['voice'] == true) tx(c, 'بالصوت', 'by voice'),
      if (k == 'ticket_save' && m['photo'] == false) tx(c, 'بدون صورة', 'no photo'),
      if (k == 'ticket_out') '${vStr(i['pay'])} ${vStr(i['total'])}',
      if (m['pay'] != null) '${m['pay']}',
      if (m['total'] != null) '${m['total']} AED',
      if (k == 'pos_total') tx(c, 'المكنة ${m['pos']} · التطبيق ${m['app']}', 'machine ${m['pos']} · app ${m['app']}'),
      if (m['error'] != null && '${m['error']}'.isNotEmpty) '⚠ ${m['error']}',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final all = vList(d?['items']);
    final items = _taps ? all : all.where((i) => vStr(i['kind']) != 'tap').toList();
    final sh = (d?['shift'] as Map?) ?? const {};
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(tx(context, 'إعادة تشغيل الشيفت ${widget.code}', 'Shift replay ${widget.code}')),
        actions: [
          Row(children: [
            Text(tx(context, 'الضغطات', 'Taps')),
            Switch(value: _taps, onChanged: (v) => setState(() => _taps = v)),
            const SizedBox(width: 10),
          ]),
        ],
      ),
      body: _err != null
          ? Center(child: Text(vErr(context, _err!)))
          : d == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.all(20), children: [
                  HubCard(
                    child: Wrap(spacing: 18, runSpacing: 6, children: [
                      Text('${vStr(sh['point'])} · ${vStr(sh['opened_by'])}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text('${_ValetStaffAnalyticsScreenState._time(sh['start'])} → ${_ValetStaffAnalyticsScreenState._time(sh['end'])}'),
                      if (sh['cash_expected'] != null) Text(tx(context, 'كاش متوقع ${sh['cash_expected']} · معاه ${sh['cash_counted'] ?? '—'}', 'Cash expected ${sh['cash_expected']} · counted ${sh['cash_counted'] ?? '—'}')),
                      if (sh['card_expected'] != null) Text(tx(context, 'كارت التطبيق ${sh['card_expected']}', 'App card ${sh['card_expected']}')),
                      if (sh['pos'] != null) Text(tx(context, 'مكنة الكارت ${sh['pos']}', 'Card machine ${sh['pos']}'), style: const TextStyle(fontWeight: FontWeight.w800)),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  if (items.isEmpty)
                    Text(tx(context, 'مفيش حركات مسجلة للشيفت ده (التطبيق القديم أو التسجيل مقفول)', 'No events for this shift (old app or recording off)'),
                        style: const TextStyle(color: _muted)),
                  for (var n = 0; n < items.length; n++) _row(context, items[n], n == 0 ? null : items[n - 1]),
                ]),
    );
  }

  Widget _row(BuildContext c, VJson i, VJson? prev) {
    final (icon, name) = _icon(c, i);
    final flags = (i['flags'] as Map?) ?? const {};
    final score = vNum(flags['score']).toInt();
    final reasons = (flags['reasons'] as List? ?? const []).map(vStr).toList();
    final gap = prev == null ? null : DateTime.tryParse(vStr(i['at']))?.difference(DateTime.tryParse(vStr(prev['at'])) ?? DateTime.now());
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (gap != null && gap.inMinutes >= 20)
        Padding(
          padding: const EdgeInsets.only(left: 68, top: 2, bottom: 2),
          child: Text(tx(c, '— ${gap.inMinutes} دقيقة بدون حركة —', '— ${gap.inMinutes} min with nothing —'), style: const TextStyle(color: _muted, fontSize: 11.5)),
        ),
      Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: score >= 3 ? _ink : _line, width: score >= 3 ? 1.6 : 1),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 62, child: Text(_ValetStaffAnalyticsScreenState._hm(i['at']), style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5))),
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(TextSpan(children: [
                TextSpan(text: '$name  ', style: const TextStyle(fontWeight: FontWeight.w800)),
                TextSpan(text: _detail(c, i)),
              ])),
              if (reasons.isNotEmpty)
                Text(reasons.join(' · '), style: TextStyle(fontSize: 12, color: score >= 3 ? _ink : _muted, fontWeight: score >= 3 ? FontWeight.w700 : null)),
            ]),
          ),
          if (vStr(i['who']).isNotEmpty) Text(vStr(i['who']), style: const TextStyle(color: _muted, fontSize: 12)),
        ]),
      ),
    ]);
  }
}
