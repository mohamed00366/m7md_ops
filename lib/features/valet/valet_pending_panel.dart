import 'package:flutter/material.dart';

import 'valet_admin.dart';
import 'valet_credits_screen.dart';
import 'valet_shifts_screen.dart';
import 'valet_ui.dart';

/// ⏳ DB 336: what is left hanging at all points — shifts open too long, tickets on the board too long, key requests
/// and car requests waiting — plus the credit notes waiting approval. The limits are options (0 = that alert off).
class ValetPendingPanel extends StatefulWidget {
  const ValetPendingPanel({super.key});

  @override
  State<ValetPendingPanel> createState() => _ValetPendingPanelState();
}

class _ValetPendingPanelState extends State<ValetPendingPanel> {
  VJson? _d;
  int _credits = 0;

  /// DB 342: company devices with a problem and RTA refusals (null = old server / option off).
  VJson? _fleet;
  String _open = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await ValetAdmin.I.call('vva_pending');
      if (mounted) setState(() => _d = d);
    } catch (_) {/* old server: no panel */}
    try {
      final a = await ValetAdmin.I.call('vva_odoo_alerts');
      if (mounted) setState(() => _credits = vNum(a['credits_waiting_approval']).toInt());
    } catch (_) {}
    try {
      final f = await ValetAdmin.I.call('vva_fleet_alerts');
      if (mounted) setState(() => _fleet = f);
    } catch (_) {/* old server */}
  }

  static String _ago(BuildContext c, DateTime? t) {
    if (t == null) return '-';
    final m = DateTime.now().difference(t).inMinutes;
    if (m < 60) return tx(c, '$m د', '$m min');
    final h = m ~/ 60;
    if (h < 48) return tx(c, '$h س', '$h h');
    return tx(c, '${h ~/ 24} يوم', '${h ~/ 24} d');
  }

  Future<void> _limits() async {
    final l = vMap(_d?['limits']);
    final v = {for (final k in ['shift_hours', 'ticket_hours', 'key_min', 'request_min']) k: vNum(l[k]).toInt()};
    Widget seg(StateSetter set, String k, String ar, String en, List<int> opts, String unitAr, String unitEn) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tx(context, ar, en), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                for (final o in opts)
                  ButtonSegment(value: o, label: Text(o == 0 ? tx(context, 'مَقفول', 'Off') : '$o ${tx(context, unitAr, unitEn)}')),
              ],
              selected: {opts.contains(v[k]) ? v[k]! : opts[1]},
              onSelectionChanged: (s) => set(() => v[k] = s.first),
            ),
          ]),
        );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(tx(ctx, 'حُدود التَنبيه (كُلّ النِقاط)', 'Alert limits (all points)')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              seg(set, 'shift_hours', 'وَرديّة مَفتوحة أَكتَر مِن', 'Shift open longer than', const [0, 12, 24, 48], 'س', 'h'),
              seg(set, 'ticket_hours', 'تَكت عَلى البورد أَكتَر مِن', 'Ticket on the board longer than', const [0, 12, 24, 72], 'س', 'h'),
              seg(set, 'key_min', 'طَلَب مِفتاح مُستَنّي أَكتَر مِن', 'Key request waiting longer than', const [0, 15, 30, 60], 'د', 'min'),
              seg(set, 'request_min', 'طَلَب عَربيّة مُستَنّي أَكتَر مِن', 'Car request waiting longer than', const [0, 10, 15, 30], 'د', 'min'),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tx(ctx, 'إلغاء', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tx(ctx, 'حِفظ', 'Save'))),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final d = await vGuard(context, () => ValetAdmin.I.call('vva_pending_save', {'p_data': v}), ok: tx(context, 'تَمّ الحِفظ.', 'Saved.'));
    if (d != null && mounted) setState(() => _d = d);
  }

  Future<void> _resolve(VJson r) async {
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tx(ctx, 'رَفض RTA اتحَلّ؟', 'RTA refusal solved?')),
        content: TextField(controller: note, decoration: InputDecoration(labelText: tx(ctx, 'إزاي (اختياريّ)', 'How (optional)'), hintText: tx(ctx, 'اتدَفَع تاني بِاللوحة الصَحّ', 'Paid again with the right plate'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tx(ctx, 'إلغاء', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tx(ctx, 'اتحَلِّت', 'Solved'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await vGuard(context, () => ValetAdmin.I.call('vva_rta_issue_resolve', {'p_id': r['id'], 'p_note': note.text.trim()}));
    await _load();
  }

  void _push(Widget page, String ar, String en) => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(appBar: AppBar(title: Text(tx(context, ar, en))), body: page)));

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (d == null) return const SizedBox.shrink();
    final l = vMap(d['limits']);
    final shifts = vList(d['shifts']), tickets = vList(d['tickets']), keys = vList(d['keys']), reqs = vList(d['requests']);
    final ticketsN = vNum(d['tickets_count']).toInt();
    final groups = <(String, IconData, Color, String, String, int, List<VJson>, String Function(VJson))>[
      ('shifts', Icons.schedule, VC.bad, 'وَرديّات مَفتوحة +${l['shift_hours']} س', 'Shifts open ${l['shift_hours']}+ h', shifts.length, shifts,
          (r) => '${r['code']} · ${r['point']} · ${r['by'] ?? ''}'),
      ('tickets', Icons.confirmation_number_outlined, VC.warn, 'تَكت عَلى البورد +${l['ticket_hours']} س', 'Tickets on board ${l['ticket_hours']}+ h', ticketsN,
          tickets, (r) => '${r['code']} · ${r['plate'] ?? ''} · ${r['point']}'),
      ('keys', Icons.key, VC.warn, 'طَلَبات مَفاتيح +${l['key_min']} د', 'Key requests ${l['key_min']}+ min', keys.length, keys,
          (r) => '${r['code']} · ${r['plate'] ?? ''} · ${r['point']}'),
      ('requests', Icons.notifications_active, VC.bad, 'طَلَبات عَربيّات +${l['request_min']} د', 'Car requests ${l['request_min']}+ min', reqs.length, reqs,
          (r) => '${r['code']} · ${r['plate'] ?? ''} · ${r['point']}'),
    ];
    final devs = vList(_fleet?['devices']), refused = vList(_fleet?['rta']);
    final total = groups.fold<int>(0, (a, g) => a + g.$6) + _credits + devs.length + refused.length;
    final shown = groups.firstWhere((g) => g.$1 == _open, orElse: () => groups.first);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: VPanel(
        title: total == 0 ? tx(context, 'المُعَلَّق: مَفيش حاجة مُعَلَّقة ✓', 'Pending: nothing left hanging ✓') : tx(context, 'المُعَلَّق ($total)', 'Pending ($total)'),
        actions: [
          if (ValetAdmin.I.can(ValetAdmin.permSettings))
            IconButton(tooltip: tx(context, 'حُدود التَنبيه', 'Alert limits'), onPressed: _limits, icon: const Icon(Icons.tune)),
          IconButton(tooltip: tx(context, 'تَحديث', 'Refresh'), onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final g in groups)
              ChoiceChip(
                avatar: Icon(g.$2, size: 18, color: g.$6 > 0 ? g.$3 : VC.muted),
                label: Text('${tx(context, g.$4, g.$5)} · ${g.$6}'),
                selected: _open == g.$1,
                onSelected: g.$6 == 0 ? null : (v) => setState(() => _open = v ? g.$1 : ''),
              ),
            if (refused.isNotEmpty)
              ChoiceChip(
                avatar: const Icon(Icons.local_parking, size: 18, color: VC.bad),
                label: Text('${tx(context, 'رَفض RTA', 'RTA refused')} · ${refused.length}'),
                selected: _open == 'fleet_rta',
                onSelected: (v) => setState(() => _open = v ? 'fleet_rta' : ''),
              ),
            if (devs.isNotEmpty)
              ChoiceChip(
                avatar: const Icon(Icons.phone_android, size: 18, color: VC.bad),
                label: Text('${tx(context, 'أَجهِزة', 'Devices')} · ${devs.length}'),
                selected: _open == 'fleet_dev',
                onSelected: (v) => setState(() => _open = v ? 'fleet_dev' : ''),
              ),
            if (_credits > 0)
              ActionChip(
                avatar: const Icon(Icons.receipt_long_outlined, size: 18, color: VC.info),
                label: Text(tx(context, '$_credits إشعار دائِن مُستَنّي مُوافَقة', '$_credits credit note(s) waiting approval →')),
                onPressed: () => _push(const ValetCreditsScreen(), 'الإشعارات الدائِنة', 'Credit notes'),
              ),
          ]),
          if (_open == 'fleet_rta') ...[
            const SizedBox(height: 8),
            for (final r in refused)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.error_outline, color: VC.bad, size: 20),
                title: Text('${vStr(r['plate']).isEmpty ? '?' : r['plate']} · ${vStr(r['point']).isEmpty ? vStr(r['device']) : r['point']}${vStr(r['ticket']).isEmpty ? '' : ' · ${VF.short(vStr(r['ticket']))}'}'),
                subtitle: Text(vStr(r['body']), maxLines: 2, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr),
                trailing: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
                  Text(_ago(context, vTime(r['at'])), style: const TextStyle(color: VC.bad, fontWeight: FontWeight.w800)),
                  TextButton(onPressed: () => _resolve(r), child: Text(tx(context, 'اتحَلِّت', 'Solved'))),
                ]),
              ),
          ],
          if (_open == 'fleet_dev') ...[
            const SizedBox(height: 8),
            for (final d in devs)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.phone_android, color: VC.bad, size: 20),
                title: Text('${d['name']}${vStr(d['point']).isEmpty ? '' : ' · ${d['point']}'}'),
                subtitle: Text([for (final x in (d['problems'] is List ? d['problems'] as List : const [])) fleetProblem(context, '$x')].join(' · ')),
                trailing: Text(_ago(context, vTime(d['last_seen'])), style: const TextStyle(color: VC.muted)),
              ),
          ],
          if (_open.isNotEmpty && !_open.startsWith('fleet_') && shown.$7.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final r in shown.$7.take(50))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(shown.$2, color: shown.$3, size: 20),
                title: Text(shown.$8(r)),
                trailing: Text(_ago(context, vTime(r['since'])), style: TextStyle(color: shown.$3, fontWeight: FontWeight.w800)),
              ),
            if (shown.$6 > 50)
              Text(tx(context, '… و ${shown.$6 - 50} كمان', '… and ${shown.$6 - 50} more'), style: const TextStyle(color: VC.muted)),
            if (_open == 'shifts')
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(tx(context, 'صَفحة الوَرديّات (قَفل الوَرديّة)', 'Shifts page (close a shift)')),
                  onPressed: () => _push(const ValetShiftsScreen(), 'وَرديّات الفاليه', 'Valet shifts'),
                ),
              ),
          ],
        ]),
      ),
    );
  }
}

/// DB 342: the words of a device problem.
String fleetProblem(BuildContext context, String k) => switch (k) {
      'offline' => tx(context, 'مُش مُتَّصِل', 'Off line'),
      'sms' => tx(context, 'صَلاحيّة SMS مَقفولة', 'SMS permission off'),
      'calls' => tx(context, 'صَلاحيّة المُكالَمات مَقفولة', 'Call-log permission off'),
      'admin' => tx(context, 'الحِماية مَقفولة', 'Protection off'),
      'battery' => tx(context, 'تَوفير البَطّاريّة بِيوَقَّفه', 'Battery saving stops it'),
      'battery_low' => tx(context, 'البَطّاريّة ضَعيفة', 'Battery low'),
      'waiting' => tx(context, 'رَسايل مُستَنّية رَفع', 'Records waiting upload'),
      _ => k,
    };
