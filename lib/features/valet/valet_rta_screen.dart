import 'package:flutter/material.dart';

import '../../core/services/excel_exporter.dart';
import 'valet_admin.dart';
import 'valet_ui.dart';

/// RTA colours (same as the app's card strip).
class RtaC {
  static const frame = Color(0xFF2563EB);
  static const due = Color(0xFFD97706);
  static const paid = Color(0xFF16A34A);
  static const ending = Color(0xFFEA580C);
  static const expired = Color(0xFFDC2626);
  static const skip = Color(0xFF6B7280);
}

String _n(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');

/// 🅿️ DB 337 – RTA parking of one point: on/off, the zones near the site (code + price per hour), the SMS
/// (number, template, renew), the hours, the alerts, the RTA tablet (its SIM sends) and who may mark "No RTA".
/// Off = the point works as before.
class ValetRtaPointScreen extends StatefulWidget {
  const ValetRtaPointScreen({super.key, required this.pointId});
  final String pointId;

  @override
  State<ValetRtaPointScreen> createState() => _ValetRtaPointScreenState();
}

class _ValetRtaPointScreenState extends State<ValetRtaPointScreen> {
  VJson? _s;
  List<VJson> _devices = const [];
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
      if (mounted) setState(() => _s = vMap(d['settings']));
    } catch (e) {
      if (mounted) setState(() => _err = e);
    }
    try {
      final r = await ValetAdmin.I.call('vva_rta_devices', {'p_point': widget.pointId});
      if (mounted) setState(() => _devices = vList(r['items']));
    } catch (_) {/* old server */}
  }

  Future<void> _save(Map<String, dynamic> patch) async {
    final d = await vGuard(context, () => ValetAdmin.I.call('vva_point_settings_save', {'p_point': widget.pointId, 'p_data': patch}),
        ok: tx(context, 'تَمّ الحِفظ.', 'Saved.'));
    if (d != null && mounted) setState(() => _s = vMap(d['settings']));
  }

  List<VJson> get _zones => [for (final z in vList(_s?['rta_zones'])) Map<String, dynamic>.from(z)];

  Future<void> _zoneDialog([int? index]) async {
    final z = index == null ? <String, dynamic>{} : _zones[index];
    final code = TextEditingController(text: vStr(z['code']));
    final rate = TextEditingController(text: z['rate'] == null ? '' : _n(vNum(z['rate'])));
    final note = TextEditingController(text: vStr(z['note']));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(index == null ? tx(ctx, 'زون RTA جَديد', 'New RTA zone') : tx(ctx, 'تَعديل الزون', 'Edit zone')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: code, textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(labelText: tx(ctx, 'كود المِنطِقة (مِن اللافِتة البُرتُقاليّة)', 'Zone code (from the orange sign)'), hintText: '365A')),
          TextField(controller: rate, keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: tx(ctx, 'السِعر لِلساعة (دِرهَم)', 'Price per hour (AED)'), hintText: '4')),
          TextField(controller: note, decoration: InputDecoration(labelText: tx(ctx, 'مُلاحَظة (اختياريّ)', 'Note (optional)'), hintText: tx(ctx, 'قُدّام المَدخَل', 'In front of the entrance'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tx(ctx, 'إلغاء', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tx(ctx, 'حِفظ', 'Save'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final c = code.text.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
    if (c.isEmpty) return;
    final list = _zones;
    final item = {'code': c, 'rate': num.tryParse(rate.text.trim()) ?? 0, if (note.text.trim().isNotEmpty) 'note': note.text.trim()};
    if (index == null) {
      list.add(item);
    } else {
      list[index] = item;
    }
    await _save({'rta_zones': list});
  }

  Future<void> _text(String key, String ar, String en, String hint) async {
    final c = TextEditingController(text: vStr(_s?[key]));
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tx(ctx, ar, en)),
        content: TextField(controller: c, decoration: InputDecoration(hintText: hint, helperText: key == 'rta_template'
            ? tx(ctx, '{zone} الزون · {plate} اللوحة بِدون مَسافات · {plate_spaced} · {code} · {number} · {hours} الساعات',
                '{zone} · {plate} (no spaces) · {plate_spaced} · {code} · {number} · {hours}')
            : null, helperMaxLines: 3)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tx(ctx, 'إلغاء', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(tx(ctx, 'حِفظ', 'Save'))),
        ],
      ),
    );
    if (v == null || v.isEmpty || !mounted) return;
    await _save({key: v});
  }

  String _example() {
    final z = _zones.isEmpty ? '365A' : vStr(_zones.first['code']);
    final h = vNum(_s?['rta_hours_default'] ?? 1).toInt();
    final t = vStr(_s?['rta_template']).isEmpty ? '{zone} {plate} {hours}' : vStr(_s?['rta_template']);
    return t
        .replaceAll('{zone}', z)
        .replaceAll('{plate_spaced}', 'B 45120')
        .replaceAll('{plate}', 'B45120')
        .replaceAll('{code}', 'B')
        .replaceAll('{number}', '45120')
        .replaceAll('{hours}', '$h');
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (s == null) return Center(child: _err != null ? Text(vErr(context, _err!)) : const CircularProgressIndicator());
    final on = vBool(s['rta_on']);
    Widget seg<T>(String key, List<(T, String, String)> opts, {bool enabled = true}) {
      final cur = s[key] as T?;
      return SegmentedButton<T>(
        showSelectedIcon: false,
        segments: [for (final (v, ar, en) in opts) ButtonSegment<T>(value: v, label: Text(tx(context, ar, en)))],
        selected: {opts.any((o) => o.$1 == cur) ? cur as T : opts.first.$1},
        onSelectionChanged: !_edit || !enabled ? null : (v) => _save({key: v.first}),
      );
    }

    Widget row(String ar, String en, Widget control, {String? noteAr, String? noteEn}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Wrap(spacing: 16, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 220, maxWidth: 340),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tx(context, ar, en), style: const TextStyle(fontWeight: FontWeight.w700)),
                if (noteAr != null) Text(tx(context, noteAr, noteEn ?? noteAr), style: const TextStyle(color: VC.muted, fontSize: 12)),
              ]),
            ),
            control,
          ]),
        );
    final dev = vStr(s['rta_device']);
    final devItem = _devices.where((d) => vStr(d['id']) == dev).firstOrNull;
    String devName(VJson d) =>
        '${d['short_code'] == null ? '' : '#${vNum(d['short_code']).toInt().toString().padLeft(2, '0')} '}${vStr(d['model'])}${vStr(d['label']).isEmpty ? '' : ' · ${d['label']}'}';
    final online = devItem != null && (vTime(devItem['last_seen_at'])?.isAfter(DateTime.now().subtract(const Duration(minutes: 3))) ?? false);

    return ListView(padding: const EdgeInsets.all(16), children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: RtaC.frame.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: RtaC.frame.withValues(alpha: 0.45)),
        ),
        child: Row(children: [
          const Icon(Icons.local_parking, color: RtaC.frame, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tx(context, 'رُسوم مَواقِف RTA (رِسالة SMS)', 'RTA parking fees (SMS)'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text(
                  tx(context, 'كُلّ تَكت جَديد في النُقطة دي يِبدأ «RTA مُش مَدفوع» · الدَفع بِزِرار واحِد مِن التابلت · الرُسوم مَصروف عَلى المَوقِع',
                      'Every new ticket of this point starts "RTA not paid" · pay with one button from the tablet · the fees are a cost of the site'),
                  style: const TextStyle(color: VC.muted, fontSize: 12.5)),
            ]),
          ),
          Switch(value: on, onChanged: !_edit ? null : (v) => _save({'rta_on': v})),
        ]),
      ),
      const SizedBox(height: 12),
      VPanel(
        title: tx(context, 'الزونات القَريبة مِن المَوقِع', 'Zones near the site'),
        actions: [
          if (_edit) TextButton.icon(onPressed: () => _zoneDialog(), icon: const Icon(Icons.add), label: Text(tx(context, 'زون', 'Zone'))),
        ],
        child: _zones.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(8),
                child: Text(tx(context, 'لِسّه مَفيش زون · ضيف كود المِنطِقة وَسِعر الساعة', 'No zone yet · add the zone code and the price per hour'),
                    style: const TextStyle(color: VC.warn, fontWeight: FontWeight.w600)),
              )
            : Column(children: [
                for (final (i, z) in _zones.indexed)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: (i == 0 ? RtaC.frame : VC.muted).withValues(alpha: 0.15),
                      child: Text(vStr(z['code']).isEmpty ? '?' : vStr(z['code']).substring(0, vStr(z['code']).length.clamp(0, 4)),
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: i == 0 ? RtaC.frame : VC.muted)),
                    ),
                    title: Text('${z['code']} · ${_n(vNum(z['rate']))} ${tx(context, 'دِرهَم/ساعة', 'AED/h')}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text([
                      if (i == 0) tx(context, 'الافتِراضيّ', 'Default'),
                      if (vStr(z['note']).isNotEmpty) vStr(z['note']),
                    ].join(' · ')),
                    trailing: !_edit
                        ? null
                        : Row(mainAxisSize: MainAxisSize.min, children: [
                            if (i > 0)
                              IconButton(
                                tooltip: tx(context, 'خَلّيه الافتِراضيّ', 'Make default'),
                                icon: const Icon(Icons.vertical_align_top),
                                onPressed: () {
                                  final l = _zones;
                                  final x = l.removeAt(i);
                                  _save({'rta_zones': [x, ...l]});
                                },
                              ),
                            IconButton(tooltip: tx(context, 'تَعديل', 'Edit'), icon: const Icon(Icons.edit_outlined), onPressed: () => _zoneDialog(i)),
                            IconButton(
                              tooltip: tx(context, 'حَذف', 'Remove'),
                              icon: const Icon(Icons.delete_outline, color: VC.bad),
                              onPressed: () => _save({'rta_zones': [..._zones]..removeAt(i)}),
                            ),
                          ]),
                  ),
              ]),
      ),
      const SizedBox(height: 12),
      VPanel(
        title: tx(context, 'الرِسالة', 'The message'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: VC.muted.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              const Icon(Icons.sms_outlined, color: VC.muted),
              const SizedBox(width: 10),
              Text('${tx(context, 'إلى', 'To')} ${vStr(s['rta_number']).isEmpty ? '7275' : s['rta_number']}:', style: const TextStyle(color: VC.muted, fontWeight: FontWeight.w700)),
              const SizedBox(width: 12),
              // the SMS itself is read left to right (zone, plate, hours)
              Expanded(
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(_example(), textAlign: TextAlign.start, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, letterSpacing: 0.5)),
                ),
              ),
            ]),
          ),
          row('رَقَم الإرسال', 'SMS number', OutlinedButton(onPressed: !_edit ? null : () => _text('rta_number', 'رَقَم الإرسال', 'SMS number', '7275'), child: Text(vStr(s['rta_number']).isEmpty ? '7275' : vStr(s['rta_number'])))),
          row('شَكل الرِسالة', 'Message template',
              OutlinedButton(onPressed: !_edit ? null : () => _text('rta_template', 'شَكل الرِسالة', 'Message template', '{zone} {plate} {hours}'), child: Text(vStr(s['rta_template']).isEmpty ? '{zone} {plate} {hours}' : vStr(s['rta_template']))),
              noteAr: 'الافتِراضيّ: كود المِنطِقة ثُمّ رَقَم العَربيّة ثُمّ الساعات', noteEn: 'Default: zone code, then the plate, then the hours'),
          row('عَدَد الساعات الافتِراضيّ', 'Default hours', seg<int>('rta_hours_default', const [(1, '1', '1'), (2, '2', '2'), (3, '3', '3'), (4, '4', '4')])),
          row('أَقصى ساعات يِختارها المُوَظَّف', 'Most hours the staff can choose', seg<int>('rta_hours_max', const [(3, '3', '3'), (5, '5', '5'), (8, '8', '8'), (12, '12', '12')])),
        ]),
      ),
      const SizedBox(height: 12),
      VPanel(
        title: tx(context, 'التَجديد وَالتَنبيه', 'Renew and alerts'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          row('طَريقة التَجديد', 'How to renew',
              seg<String>('rta_renew_mode', const [('reply', 'رَدّ Y (ساعة)', 'Reply Y (1 hour)'), ('new', 'رِسالة جَديدة', 'New message')]),
              noteAr: 'رَدّ Y لازِم يِطلَع مِن نَفس الرَقَم اللي دَفَع', noteEn: 'The Y reply must come from the same number that paid'),
          if (vStr(s['rta_renew_mode']) == 'new')
            row('ساعات كُلّ تَجديد', 'Hours of each renew', seg<int>('rta_renew_hours', const [(1, '1', '1'), (2, '2', '2'), (3, '3', '3')])),
          row('التَنبيه قَبل نِهاية الوَقت', 'Alert before the end', seg<int>('rta_alert_min', const [(0, 'مَقفول', 'Off'), (5, '5 د', '5 min'), (10, '10 د', '10 min'), (15, '15 د', '15 min')])),
          row('تَجديد تِلقائيّ', 'Auto renew', Switch(value: vBool(s['rta_renew_auto']), onChanged: !_edit ? null : (v) => _save({'rta_renew_auto': v})),
              noteAr: 'قَبل النِهاية التابلت يِجَدِّد لِوَحده (مِن غَير ما حَدّ يِدوس)', noteEn: 'Before the end the tablet renews by itself (no one presses)'),
        ]),
      ),
      const SizedBox(height: 12),
      VPanel(
        title: tx(context, 'مين يِبعَت الرِسالة', 'Who sends the SMS'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          row('الإرسال', 'Sending', seg<String>('rta_sender', const [('tablet', 'تابلت RTA بَس (شَريحته)', 'RTA tablet only (its SIM)'), ('any', 'كُلّ جِهاز بِنَفسه', 'Every device itself')])),
          if (vStr(s['rta_sender']) != 'any') ...[
            row(
              'تابلت RTA', 'RTA tablet',
              DropdownButton<String>(
                value: _devices.any((d) => vStr(d['id']) == dev) ? dev : '',
                items: [
                  DropdownMenuItem(value: '', child: Text(tx(context, '— لِسّه ما اتحَدِّدش —', '— not chosen yet —'))),
                  for (final d in _devices) DropdownMenuItem(value: vStr(d['id']), child: Text(devName(d))),
                ],
                onChanged: !_edit ? null : (v) => _save({'rta_device': (v ?? '').isEmpty ? null : v}),
              ),
              noteAr: dev.isEmpty
                  ? 'أَو السوبرفايزر يِدوس «استَخدِم التابلت دَه لِلـ RTA» مِن إعدادات التَطبيق'
                  : (online ? 'مُتَّصِل الآن ✓' : 'مُش مُتَّصِل دِلوَقتي (آخِر ظُهور ${VF.dt(vTime(devItem?['last_seen_at']))})'),
              noteEn: dev.isEmpty
                  ? 'Or the supervisor presses "Use this tablet for RTA" in the app settings'
                  : (online ? 'Online now ✓' : 'Off line now (last seen ${VF.dt(vTime(devItem?['last_seen_at']))})'),
            ),
            row('لَو التابلت مُش مُتَّصِل', 'If the tablet is off line',
                Switch(value: vBool(s['rta_fallback'] ?? true), onChanged: !_edit ? null : (v) => _save({'rta_fallback': v})),
                noteAr: 'مَسموح لِلموبايل يِدفَع بِنَفسه (رِسالة كامِلة)', noteEn: 'A phone may pay itself (a full message)'),
          ],
          row('«مِن غَير RTA»', '"No RTA"', seg<String>('rta_skip_who', const [('lead', 'سوبرفايزر الوَرديّة بَس', 'Shift supervisor only'), ('all', 'أَيّ مُوَظَّف', 'Any staff')]),
              noteAr: 'مَثَلاً العَربيّة جُوّه المَوقِع · لازِم سَبَب وَيِتسَجِّل مين', noteEn: 'e.g. the car is inside the site · a reason is needed and who is kept'),
        ]),
      ),
      const SizedBox(height: 12),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: OutlinedButton.icon(
          icon: const Icon(Icons.receipt_long_outlined),
          label: Text(tx(context, 'رَسايل RTA وَالتَكلِفة لِلنُقطة دي', 'RTA messages and cost of this point')),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => Scaffold(appBar: AppBar(title: Text(tx(context, 'RTA', 'RTA'))), body: ValetRtaLogScreen(pointId: widget.pointId)))),
        ),
      ),
    ]);
  }
}

/// 🅿️ DB 337 – every RTA message (sent and replies) and the RTA cost per point, with the "No RTA" decisions.
class ValetRtaLogScreen extends StatefulWidget {
  const ValetRtaLogScreen({super.key, this.pointId});
  final String? pointId;

  @override
  State<ValetRtaLogScreen> createState() => _ValetRtaLogScreenState();
}

class _ValetRtaLogScreenState extends State<ValetRtaLogScreen> {
  late DateTime _from, _to;
  String? _point;
  List<VJson> _points = const [];
  VJson? _d;
  Object? _err;
  String _show = 'all';

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _to = DateTime(n.year, n.month, n.day);
    _from = _to.subtract(const Duration(days: 6));
    _point = widget.pointId;
    if (widget.pointId == null) {
      VPoints.get().then((p) {
        if (mounted) setState(() => _points = p);
      }).catchError((_) {});
    }
    _load();
  }

  Future<void> _load() async {
    setState(() => _err = null);
    try {
      final d = await ValetAdmin.I.call('vva_rta_log', {'p_point': _point, 'p_from': VF.iso(_from), 'p_to': VF.iso(_to), 'p_limit': 1000});
      if (mounted) setState(() => _d = d);
    } catch (e) {
      if (mounted) setState(() => _err = e);
    }
  }

  Future<void> _export() async {
    final d = _d;
    if (d == null) return;
    await vExport(context, 'rta_${VF.iso(_from)}_${VF.iso(_to)}', [
      ExcelSheet(
        name: 'Cost per point',
        headers: const ['Point', 'Sent SMS', 'Amount AED', 'Paid tickets', 'No RTA', 'Not paid', 'Over now', 'Failed', 'RTA errors'],
        rows: [
          for (final p in vList(d['points']))
            [vStr(p['name']), vNum(p['sent']), vNum(p['amount']), vNum(p['paid']), vNum(p['skip']), vNum(p['due']), vNum(p['expired']), vNum(p['failed']), vNum(p['errors'])],
        ],
      ),
      ExcelSheet(
        name: 'Messages',
        headers: const ['Time', 'Point', 'Ticket', 'Plate', 'Direction', 'Kind', 'Status', 'Message', 'Zone', 'Hours', 'Amount', 'By', 'Device', 'Error'],
        rows: [
          for (final m in vList(d['messages']))
            [
              vTime(m['at']), vStr(m['point']), vStr(m['ticket']), vStr(m['plate']), vStr(m['direction']), vStr(m['kind']), vStr(m['status']), vStr(m['body']),
              vStr(m['zone']), m['hours'] == null ? null : vNum(m['hours']), vNum(m['amount']), vStr(m['by']), vStr(m['device']), vStr(m['error']),
            ],
        ],
      ),
      ExcelSheet(
        name: 'No RTA',
        headers: const ['Time', 'Point', 'Ticket', 'Plate', 'Reason', 'By'],
        rows: [for (final x in vList(d['skips'])) [vTime(x['at']), vStr(x['point']), vStr(x['ticket']), vStr(x['plate']), vStr(x['reason']), vStr(x['by'])]],
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final pts = vList(d?['points']);
    num sum(String k) => pts.fold<num>(0, (a, p) => a + vNum(p[k]));
    final msgs = vList(d?['messages']).where((m) => switch (_show) {
          'out' => m['direction'] == 'out',
          'in' => m['direction'] == 'in',
          'bad' => m['status'] == 'failed' || m['status'] == 'cancelled' || m['kind'] == 'error',
          _ => true,
        }).toList();
    return ValetGate(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
          VHead(
            tx(context, 'رُسوم مَواقِف RTA', 'RTA parking fees'),
            subtitle: tx(context, 'كُلّ رِسالة اتبَعَتِت وَكُلّ رَدّ مِن 7275 · التَكلِفة مَصروف عَلى المَوقِع', 'Every SMS sent and every reply from 7275 · the cost is an expense of the site'),
            actions: [
              IconButton.filledTonal(tooltip: tx(context, 'Excel', 'Excel'), onPressed: d == null ? null : _export, icon: const Icon(Icons.download)),
              IconButton.filledTonal(tooltip: tx(context, 'تَحديث', 'Refresh'), onPressed: _load, icon: const Icon(Icons.refresh)),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
              VRange(from: _from, to: _to, onChanged: (a, b) {
                setState(() {
                  _from = a;
                  _to = b;
                });
                _load();
              }),
              if (widget.pointId == null && _points.isNotEmpty)
                SizedBox(
                  width: 300,
                  child: VPointFilter(points: _points, value: _point, onChanged: (v) {
                    setState(() => _point = v);
                    _load();
                  }),
                ),
            ]),
          ),
          if (_err != null) Padding(padding: const EdgeInsets.all(16), child: Text(vErr(context, _err!), style: const TextStyle(color: VC.bad))),
          if (d == null && _err == null) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          if (d != null) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(spacing: 10, runSpacing: 10, children: [
                VKpi(tx(context, 'تَكلِفة RTA', 'RTA cost'), VF.money(sum('amount')), icon: Icons.payments_outlined, color: RtaC.frame, note: 'AED'),
                VKpi(tx(context, 'رَسايل اتبَعَتِت', 'SMS sent'), VF.n(sum('sent')), icon: Icons.sms_outlined, color: VC.info),
                VKpi(tx(context, 'تَكتات مَدفوعة', 'Paid tickets'), VF.n(sum('paid')), icon: Icons.check_circle_outline, color: RtaC.paid),
                VKpi(tx(context, 'مِن غَير RTA', 'No RTA'), VF.n(sum('skip')), icon: Icons.block, color: RtaC.skip),
                VKpi(tx(context, 'مُش مَدفوعة', 'Not paid'), VF.n(sum('due')), icon: Icons.warning_amber_rounded, color: sum('due') > 0 ? RtaC.due : VC.muted),
                VKpi(tx(context, 'الوَقت خِلِص الآن', 'Over now'), VF.n(sum('expired')), icon: Icons.timer_off_outlined, color: sum('expired') > 0 ? RtaC.expired : VC.muted),
                VKpi(tx(context, 'فِشِلِت / رَفض RTA', 'Failed / RTA refused'), VF.n(sum('failed') + sum('errors')), icon: Icons.error_outline,
                    color: sum('failed') + sum('errors') > 0 ? RtaC.expired : VC.muted),
              ]),
            ),
            if (widget.pointId == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: VPanel(
                  title: tx(context, 'التَكلِفة لِكُلّ مَوقِع', 'Cost per site'),
                  child: VTable(
                    empty: tx(context, 'مَفيش نُقطة شَغّالة بِـ RTA', 'No point uses RTA'),
                    columns: [
                      DataColumn(label: Text(tx(context, 'النُقطة', 'Point'))),
                      DataColumn(label: Text(tx(context, 'التَكلِفة', 'Cost')), numeric: true),
                      DataColumn(label: Text(tx(context, 'رَسايل', 'SMS')), numeric: true),
                      DataColumn(label: Text(tx(context, 'مَدفوعة', 'Paid')), numeric: true),
                      DataColumn(label: Text(tx(context, 'مِن غَير RTA', 'No RTA')), numeric: true),
                      DataColumn(label: Text(tx(context, 'مُش مَدفوعة', 'Not paid')), numeric: true),
                      DataColumn(label: Text(tx(context, 'خِلِص الآن', 'Over now')), numeric: true),
                    ],
                    rows: [
                      for (final p in pts)
                        DataRow(cells: [
                          DataCell(Text(vStr(p['name']), style: const TextStyle(fontWeight: FontWeight.w600))),
                          DataCell(Text(VF.money(vNum(p['amount'])))),
                          DataCell(Text(VF.n(vNum(p['sent'])))),
                          DataCell(Text(VF.n(vNum(p['paid'])))),
                          DataCell(Text(VF.n(vNum(p['skip'])))),
                          DataCell(vNum(p['due']) > 0 ? VPill(VF.n(vNum(p['due'])), color: RtaC.due) : const Text('0')),
                          DataCell(vNum(p['expired']) > 0 ? VPill(VF.n(vNum(p['expired'])), color: RtaC.expired) : const Text('0')),
                        ]),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: VPanel(
                title: tx(context, 'الرَسايل (${msgs.length})', 'Messages (${msgs.length})'),
                actions: [
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(value: 'all', label: Text(tx(context, 'الكُلّ', 'All'))),
                      ButtonSegment(value: 'out', label: Text(tx(context, 'المُرسَلة', 'Sent'))),
                      ButtonSegment(value: 'in', label: Text(tx(context, 'الرُدود', 'Replies'))),
                      ButtonSegment(value: 'bad', label: Text(tx(context, 'المَشاكِل', 'Problems'))),
                    ],
                    selected: {_show},
                    onSelectionChanged: (v) => setState(() => _show = v.first),
                  ),
                ],
                child: VTable(
                  empty: tx(context, 'مَفيش رَسايل في الفَترة دي', 'No messages in this period'),
                  columns: [
                    DataColumn(label: Text(tx(context, 'الوَقت', 'Time'))),
                    if (widget.pointId == null) DataColumn(label: Text(tx(context, 'النُقطة', 'Point'))),
                    DataColumn(label: Text(tx(context, 'التَكت', 'Ticket'))),
                    DataColumn(label: Text(tx(context, 'اللوحة', 'Plate'))),
                    DataColumn(label: Text(tx(context, 'الرِسالة', 'Message'))),
                    DataColumn(label: Text(tx(context, 'الحالة', 'Status'))),
                    DataColumn(label: Text(tx(context, 'المَبلَغ', 'Amount')), numeric: true),
                    DataColumn(label: Text(tx(context, 'مين / الجِهاز', 'By / device'))),
                  ],
                  rows: [
                    for (final m in msgs)
                      DataRow(cells: [
                        DataCell(Text(VF.dt(vTime(m['at'])))),
                        if (widget.pointId == null) DataCell(Text(vStr(m['point']))),
                        DataCell(Text(VF.short(vStr(m['ticket'])))),
                        DataCell(Text(vStr(m['plate']))),
                        DataCell(ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 380),
                          child: Row(children: [
                            Icon(m['direction'] == 'out' ? Icons.north_east : Icons.south_west, size: 16, color: m['direction'] == 'out' ? RtaC.frame : RtaC.paid),
                            const SizedBox(width: 6),
                            Flexible(child: Text(vStr(m['body']), maxLines: 2, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr)),
                          ]),
                        )),
                        DataCell(_status(context, m)),
                        DataCell(Text(m['direction'] == 'out' && vNum(m['amount']) > 0 ? VF.money(vNum(m['amount'])) : '-')),
                        DataCell(Text([vStr(m['by']), vStr(m['device'])].where((x) => x.isNotEmpty).join(' · '))),
                      ]),
                  ],
                ),
              ),
            ),
            if (vList(d['skips']).isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: VPanel(
                  title: tx(context, '«مِن غَير RTA» (${vList(d['skips']).length})', '"No RTA" (${vList(d['skips']).length})'),
                  child: VTable(columns: [
                    DataColumn(label: Text(tx(context, 'الوَقت', 'Time'))),
                    DataColumn(label: Text(tx(context, 'النُقطة', 'Point'))),
                    DataColumn(label: Text(tx(context, 'التَكت', 'Ticket'))),
                    DataColumn(label: Text(tx(context, 'اللوحة', 'Plate'))),
                    DataColumn(label: Text(tx(context, 'السَبَب', 'Reason'))),
                    DataColumn(label: Text(tx(context, 'مين قَرَّر', 'Decided by'))),
                  ], rows: [
                    for (final x in vList(d['skips']))
                      DataRow(cells: [
                        DataCell(Text(VF.dt(vTime(x['at'])))),
                        DataCell(Text(vStr(x['point']))),
                        DataCell(Text(VF.short(vStr(x['ticket'])))),
                        DataCell(Text(vStr(x['plate']))),
                        DataCell(Text(vStr(x['reason']))),
                        DataCell(Text(vStr(x['by']))),
                      ]),
                  ]),
                ),
              ),
          ],
        ]),
      ),
    );
  }

  Widget _status(BuildContext context, VJson m) {
    if (m['direction'] == 'in') {
      return switch (vStr(m['kind'])) {
        'confirm' => VPill(tx(context, 'تَأكيد', 'Confirmed'), color: RtaC.paid, icon: Icons.check),
        'reminder' => VPill(tx(context, 'تَذكير', 'Reminder'), color: RtaC.ending, icon: Icons.timer_outlined),
        'error' => VPill(tx(context, 'رَفض', 'Refused'), color: RtaC.expired, icon: Icons.error_outline),
        _ => VPill(tx(context, 'رَدّ', 'Reply'), color: VC.muted),
      };
    }
    final kind = vStr(m['kind']) == 'renew' ? tx(context, 'تَجديد', 'Renew') : tx(context, 'دَفع', 'Pay');
    return switch (vStr(m['status'])) {
      'sent' => VPill('$kind · ${tx(context, 'اتبَعَتِت', 'sent')}${vStr(m['reply']) == 'error' ? ' ✕' : (vStr(m['reply']) == 'confirm' ? ' ✓' : '')}',
          color: vStr(m['reply']) == 'error' ? RtaC.expired : RtaC.paid),
      'queued' => VPill('$kind · ${tx(context, 'مُستَنّي التابلت', 'waiting for the tablet')}', color: RtaC.due),
      'sending' => VPill('$kind · ${tx(context, 'بِيِتبِعِت', 'sending')}', color: RtaC.due),
      'failed' => Tooltip(message: vStr(m['error']), child: VPill('$kind · ${tx(context, 'فِشِلِت', 'failed')}', color: RtaC.expired)),
      'cancelled' => Tooltip(message: vStr(m['error']), child: VPill('$kind · ${tx(context, 'اتلَغِت', 'cancelled')}', color: VC.muted)),
      _ => VPill(vStr(m['status'])),
    };
  }
}
