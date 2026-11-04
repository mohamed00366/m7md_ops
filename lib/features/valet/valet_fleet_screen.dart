import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/services/excel_exporter.dart';
import 'valet_admin.dart';
import 'valet_pending_panel.dart' show fleetProblem;
import 'valet_ui.dart';

/// 📱 DB 339 – VIP Fleet: the company phones / tablets that log the SMS of watched numbers (RTA 7275) and the call log.
/// Devices (on / off per device, the device key), messages, calls and the daily summary, with Excel.
class ValetFleetScreen extends StatelessWidget {
  const ValetFleetScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  Widget build(BuildContext context) => ValetGate(
        child: DefaultTabController(
          length: 4,
          initialIndex: initialTab.clamp(0, 3),
          child: Column(children: [
            Material(
              color: Theme.of(context).colorScheme.surface,
              child: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
                Tab(icon: const Icon(Icons.phone_android, size: 18), text: tx(context, 'الأَجهِزة', 'Devices')),
                Tab(icon: const Icon(Icons.sms_outlined, size: 18), text: tx(context, 'الرَسايل', 'Messages')),
                Tab(icon: const Icon(Icons.call_outlined, size: 18), text: tx(context, 'المُكالَمات', 'Calls')),
                Tab(icon: const Icon(Icons.calendar_month_outlined, size: 18), text: tx(context, 'مُلَخَّص يَوميّ', 'Daily summary')),
              ]),
            ),
            const Expanded(child: TabBarView(children: [_Devices(), _Log(kind: 'sms'), _Log(kind: 'calls'), _Log(kind: 'daily')])),
          ]),
        ),
      );
}

// ================================================================ devices
class _Devices extends StatefulWidget {
  const _Devices();

  @override
  State<_Devices> createState() => _DevicesState();
}

class _DevicesState extends State<_Devices> {
  List<VJson>? _items;
  VJson? _alerts;
  List<VJson> _points = const [];
  Object? _err;
  bool get _edit => ValetAdmin.I.can(ValetAdmin.permSettings);

  @override
  void initState() {
    super.initState();
    _load();
    VPoints.get().then((p) {
      if (mounted) setState(() => _points = p);
    }).catchError((_) {});
  }

  Future<void> _load() async {
    try {
      final r = await ValetAdmin.I.call('vva_fleet_devices');
      if (mounted) setState(() => _items = vList(r['items']));
    } catch (e) {
      if (mounted) setState(() => _err = e);
    }
    try {
      final a = await ValetAdmin.I.call('vva_fleet_alerts');
      if (mounted) setState(() => _alerts = a);
    } catch (_) {/* old server */}
  }

  /// DB 342: the options of the alerts and the daily summary.
  Future<void> _alertSettings() async {
    final a = _alerts;
    if (a == null) return;
    final v = Map<String, dynamic>.from(vMap(a['settings']));
    final devices = vList(a['summary_devices']);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          Widget sw(String k, String ar, String en) => SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(tx(ctx, ar, en)),
                value: v[k] != false,
                onChanged: (x) => set(() => v[k] = x),
              );
          return AlertDialog(
            title: Text(tx(ctx, 'التَنبيهات وَالمُلَخَّص اليَوميّ', 'Alerts and the daily summary')),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(tx(ctx, 'جِهاز وِقِف', 'A device stopped'), style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(value: 0, label: Text(tx(ctx, 'مَقفول', 'Off'))),
                      for (final h in const [1, 2, 4, 8]) ButtonSegment(value: h, label: Text(tx(ctx, '$h س', '$h h'))),
                    ],
                    selected: {const [0, 1, 2, 4, 8].contains(v['offline_hours']) ? v['offline_hours'] as int : 2},
                    onSelectionChanged: (x) => set(() => v['offline_hours'] = x.first),
                  ),
                  Text(tx(ctx, 'مُش مُتَّصِل أَكتَر مِن المُدّة دي', 'Not seen for longer than this'), style: const TextStyle(color: VC.muted, fontSize: 12)),
                  sw('check_sms', 'صَلاحيّة SMS اتقَفَلِت', 'SMS permission turned off'),
                  sw('check_calls', 'صَلاحيّة المُكالَمات اتقَفَلِت', 'Call-log permission turned off'),
                  sw('check_admin', 'الحِماية اتقَفَلِت', 'Protection turned off'),
                  sw('check_battery', 'تَوفير البَطّاريّة بِيوَقَّفه', 'Battery saving stops it'),
                  sw('check_waiting', 'رَسايل مُستَنّية رَفع أَكتَر مِن ساعة', 'Records waiting upload for over an hour'),
                  const Divider(),
                  sw('rta_errors', 'تَنبيه رَفض RTA', 'RTA refusal alert'),
                  const Divider(),
                  sw('summary_on', 'المُلَخَّص اليَوميّ في الإيميل', 'Daily summary in the e-mail'),
                  DropdownButton<String>(
                    isExpanded: true,
                    value: devices.any((d) => vStr(d['id']) == vStr(v['summary_device'])) ? vStr(v['summary_device']) : '',
                    items: [
                      DropdownMenuItem(value: '', child: Text(tx(ctx, '— مَفيش جِهاز —', '— no device —'))),
                      for (final d in devices) DropdownMenuItem(value: vStr(d['id']), child: Text(vStr(d['name']))),
                    ],
                    onChanged: (x) => set(() => v['summary_device'] = x ?? ''),
                  ),
                  Text(
                      tx(ctx, 'الجِهاز ده بِيِبعَت مُلَخَّص اليوم لِكُلّ الشَرِكة مَع إيميله اليَوميّ (لازِم الإيميل يِكون شَغّال في التَطبيق عَليه).',
                          'This device adds the summary of the whole company to its daily e-mail (its e-mail must be on in the app).'),
                      style: const TextStyle(color: VC.muted, fontSize: 12)),
                ]),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tx(ctx, 'إلغاء', 'Cancel'))),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tx(ctx, 'حِفظ', 'Save'))),
            ],
          );
        },
      ),
    );
    if (ok != true || !mounted) return;
    final r = await vGuard(context, () => ValetAdmin.I.call('vva_fleet_alerts_save', {'p_data': v}), ok: tx(context, 'تَمّ الحِفظ.', 'Saved.'));
    if (r != null && mounted) setState(() => _alerts = r);
  }

  Future<VJson?> _save(String? id, Map<String, dynamic> data, {bool newKey = false}) async {
    final r = await vGuard(context, () => ValetAdmin.I.call('vva_fleet_device_save', {'p_id': id, 'p_data': data, 'p_new_key': newKey}),
        ok: tx(context, 'تَمّ الحِفظ.', 'Saved.'));
    await _load();
    return r;
  }

  Future<void> _showKey(String name, String key) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tx(ctx, 'مِفتاح الجِهاز · $name', 'Device key · $name')),
          content: SizedBox(
            width: 360,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(tx(ctx, 'اكتِبه في تَطبيق VIP Fleet عَلى الجِهاز. بِيِظهَر مَرّة واحدة بَس – لَو ضاع اعمِل مِفتاح جَديد.',
                  'Type it in the VIP Fleet app on the device. It is shown ONCE – if it is lost, make a new key.'),
                  style: const TextStyle(color: VC.muted)),
              const SizedBox(height: 12),
              Container(color: Colors.white, padding: const EdgeInsets.all(8), child: QrImageView(data: key, size: 180)),
              const SizedBox(height: 10),
              SelectableText(key, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 1)),
            ]),
          ),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.copy),
              label: Text(tx(ctx, 'نَسخ', 'Copy')),
              onPressed: () => Clipboard.setData(ClipboardData(text: key)),
            ),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(tx(ctx, 'تَمام', 'Done'))),
          ],
        ),
      );

  Future<void> _add() async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tx(ctx, 'جِهاز جَديد', 'New device')),
        content: TextField(controller: c, autofocus: true, decoration: InputDecoration(labelText: tx(ctx, 'اسم الجِهاز', 'Device name'), hintText: 'Chaplin tablet')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tx(ctx, 'إلغاء', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(tx(ctx, 'إضافة', 'Add'))),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    final r = await _save(null, {'name': name});
    if (r != null && mounted && vStr(r['key']).isNotEmpty) await _showKey(name, vStr(r['key']));
  }

  Future<void> _editDevice(VJson d) async {
    final name = TextEditingController(text: vStr(d['name']));
    final holder = TextEditingController(text: vStr(d['holder']));
    final note = TextEditingController(text: vStr(d['note']));
    String? point = vStr(d['point_id']).isEmpty ? null : vStr(d['point_id']);
    var days = vNum(d['history_days'] ?? 30).toInt();
    final nums = [for (final n in vList(d['numbers'])) Map<String, dynamic>.from(n)];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(tx(ctx, 'تَعديل الجِهاز', 'Edit device')),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(controller: name, decoration: InputDecoration(labelText: tx(ctx, 'الاسم', 'Name'))),
                const SizedBox(height: 8),
                TextField(controller: holder, decoration: InputDecoration(labelText: tx(ctx, 'مَع مين', 'Who has it'))),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  value: _points.any((p) => vStr(p['id']) == point) ? point : null,
                  decoration: InputDecoration(labelText: tx(ctx, 'النُقطة (اختياريّ)', 'Point (optional)')),
                  items: [
                    DropdownMenuItem<String?>(value: null, child: Text(tx(ctx, '— بِدون —', '— none —'))),
                    for (final p in _points) DropdownMenuItem<String?>(value: vStr(p['id']), child: Text('${p['code'] ?? ''} ${p['name']}'.trim())),
                  ],
                  onChanged: (v) => set(() => point = v),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  value: const [0, 30, 90, 3650].contains(days) ? days : 30,
                  decoration: InputDecoration(labelText: tx(ctx, 'أَوِّل تَشغيل: يِسحَب الرَسايل القَديمة', 'First run: old messages to read')),
                  items: [
                    DropdownMenuItem(value: 0, child: Text(tx(ctx, 'مِن دِلوَقتي بَس', 'From now only'))),
                    DropdownMenuItem(value: 30, child: Text(tx(ctx, 'آخِر 30 يوم', 'Last 30 days'))),
                    DropdownMenuItem(value: 90, child: Text(tx(ctx, 'آخِر 90 يوم', 'Last 90 days'))),
                    DropdownMenuItem(value: 3650, child: Text(tx(ctx, 'الكُلّ', 'All'))),
                  ],
                  onChanged: (v) => set(() => days = v ?? 30),
                ),
                const SizedBox(height: 12),
                Text(tx(ctx, 'الأَرقام المُراقَبة (مَفيش تَسجيل لِأَيّ رَقَم تاني)', 'Watched numbers (nothing else is recorded)'),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                for (final (i, n) in nums.indexed)
                  Row(children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: vStr(n['number']),
                        decoration: InputDecoration(labelText: tx(ctx, 'الرَقَم', 'Number'), isDense: true),
                        onChanged: (v) => n['number'] = v.trim(),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextFormField(
                        initialValue: vStr(n['label']),
                        decoration: InputDecoration(labelText: tx(ctx, 'الوَصف', 'Label'), isDense: true),
                        onChanged: (v) => n['label'] = v.trim(),
                      ),
                    ),
                    FilterChip(label: Text(tx(ctx, 'وارِد', 'In')), selected: n['in'] != false, onSelected: (v) => set(() => n['in'] = v)),
                    const SizedBox(width: 4),
                    FilterChip(label: Text(tx(ctx, 'صادِر', 'Out')), selected: n['out'] != false, onSelected: (v) => set(() => n['out'] = v)),
                    IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => set(() => nums.removeAt(i))),
                  ]),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: Text(tx(ctx, 'رَقَم', 'Number')),
                    onPressed: () => set(() => nums.add({'number': '', 'label': '', 'in': true, 'out': true})),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(controller: note, decoration: InputDecoration(labelText: tx(ctx, 'مُلاحَظة', 'Note'))),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tx(ctx, 'إلغاء', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tx(ctx, 'حِفظ', 'Save'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _save(vStr(d['id']), {
      'name': name.text.trim(),
      'holder': holder.text.trim(),
      'note': note.text.trim(),
      'point_id': point ?? '',
      'history_days': days,
      'numbers': [for (final n in nums) if (vStr(n['number']).isNotEmpty) n],
    });
  }

  Future<void> _newKey(VJson d) async {
    final ok = await vConfirm(context, tx(context, 'مِفتاح جَديد؟', 'New key?'),
        tx(context, 'المِفتاح القَديم هَيِبطَل وَلازِم تِكتِب الجَديد في الجِهاز.', 'The old key stops; type the new one on the device.'));
    if (!ok) return;
    final r = await _save(vStr(d['id']), {}, newKey: true);
    if (r != null && mounted) await _showKey(vStr(d['name']), vStr(r['key']));
  }

  Future<void> _stop(VJson d) async {
    final ok = await vConfirm(context, tx(context, 'إيقاف الجِهاز؟', 'Stop this device?'),
        tx(context, 'الجِهاز هَيِقِف وَمِفتاحه هَيِبطَل. السِجِلّات اللي اترَفَعِت بِتِفضَل مَحفوظة.', 'The device stops and its key no longer works. Its records are kept.'));
    if (!ok || !mounted) return;
    await vGuard(context, () => ValetAdmin.I.call('vva_fleet_device_delete', {'p_id': d['id']}), ok: tx(context, 'اتوَقَّف.', 'Stopped.'));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items == null) return Center(child: _err != null ? Text(vErr(context, _err!)) : const CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        VHead(
          tx(context, 'VIP Fleet · أَجهِزة الشَرِكة', 'VIP Fleet · company devices'),
          subtitle: tx(context, 'تَطبيق عَلى تابلِت/موبايل الشَرِكة بِيِسَجِّل رَسايل الأَرقام المُراقَبة (RTA 7275) وَسِجِلّ المُكالَمات · أَندرويد بَس',
              'An app on the company tablets / phones logs the SMS of the watched numbers (RTA 7275) and the call log · Android only'),
          actions: [
            if (_edit && _alerts != null)
              IconButton.filledTonal(tooltip: tx(context, 'التَنبيهات وَالمُلَخَّص', 'Alerts and summary'), onPressed: _alertSettings, icon: const Icon(Icons.notifications_active_outlined)),
            if (_edit) FilledButton.icon(onPressed: _add, icon: const Icon(Icons.add), label: Text(tx(context, 'جِهاز جَديد', 'Add device'))),
            IconButton.filledTonal(tooltip: tx(context, 'تَحديث', 'Refresh'), onPressed: _load, icon: const Icon(Icons.refresh)),
          ],
        ),
        // DB 342: devices with a problem
        if (vList(_alerts?['devices']).isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: VC.bad.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12), border: Border.all(color: VC.bad.withValues(alpha: 0.5))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tx(context, '${vList(_alerts?['devices']).length} جِهاز مِحتاج مُراجَعة', '${vList(_alerts?['devices']).length} device(s) need a look'),
                    style: const TextStyle(fontWeight: FontWeight.w800, color: VC.bad)),
                const SizedBox(height: 4),
                for (final d in vList(_alerts?['devices']))
                  Text('• ${d['name']}: ${[for (final x in (d['problems'] is List ? d['problems'] as List : const [])) fleetProblem(context, '$x')].join(' · ')}'),
              ]),
            ),
          ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(tx(context, 'لِسّه مَفيش أَجهِزة · دوس «جِهاز جَديد»، وَاكتِب المِفتاح في التَطبيق.', 'No device yet · press "Add device" and type the key in the app.'),
                style: const TextStyle(color: VC.muted)),
          ),
        for (final d in items) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), child: _card(d)),
      ]),
    );
  }

  Widget _card(VJson d) {
    final seen = vTime(d['last_seen']);
    final online = seen != null && DateTime.now().difference(seen).inMinutes < 30;
    final active = vBool(d['active']);
    Widget sw(String k, String ar, String en) => FilterChip(
          label: Text(tx(context, ar, en)),
          selected: vBool(d[k]),
          onSelected: !_edit ? null : (v) => _save(vStr(d['id']), {k: v}),
        );
    return VPanel(
      title: '${d['name']}${vStr(d['point']).isEmpty ? '' : ' · ${d['point']}'}',
      actions: [
        VPill(
          !active ? tx(context, 'مُتَوَقِّف', 'Stopped') : (online ? tx(context, 'مُتَّصِل', 'Online') : tx(context, 'مُش مُتَّصِل', 'Off line')),
          color: !active ? VC.muted : (online ? VC.ok : VC.warn),
          icon: online ? Icons.wifi : Icons.wifi_off,
        ),
        if (_edit)
          PopupMenuButton<String>(
            onSelected: (v) => switch (v) {
              'edit' => _editDevice(d),
              'key' => _newKey(d),
              _ => _stop(d),
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'edit', child: Text(tx(context, 'تَعديل · الأَرقام المُراقَبة', 'Edit · watched numbers'))),
              PopupMenuItem(value: 'key', child: Text(tx(context, 'مِفتاح جَديد', 'New key'))),
              PopupMenuItem(value: 'stop', child: Text(tx(context, 'إيقاف الجِهاز', 'Stop the device'), style: const TextStyle(color: VC.bad))),
            ],
          ),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          sw('active', 'شَغّال', 'Active'),
          sw('log_sms', 'تَسجيل الرَسايل', 'Log SMS'),
          sw('log_calls', 'تَسجيل المُكالَمات', 'Log calls'),
          sw('upload_enabled', 'رَفع', 'Upload'),
          sw('link_rta', 'رَبط RTA بِتَكتات الفاليه', 'Link RTA to valet tickets'),
        ]),
        const SizedBox(height: 8),
        Text(
          [
            '${tx(context, 'الأَرقام', 'Numbers')}: ${vList(d['numbers']).map((n) => '${n['number']}${n['in'] == false ? '↑' : (n['out'] == false ? '↓' : '')}').join(' · ')}',
            '${tx(context, 'النَهارده', 'Today')}: ${d['sms_today']} SMS · ${d['calls_today']} ${tx(context, 'مُكالَمة', 'calls')}',
            '${tx(context, 'آخِر ظُهور', 'Last seen')}: ${VF.dt(seen)} · ${tx(context, 'آخِر رَفع', 'Last upload')}: ${VF.dt(vTime(d['last_upload']))}',
            [vStr(d['model']), if (vStr(d['app_version']).isNotEmpty) 'v${d['app_version']}', if (vStr(d['holder']).isNotEmpty) vStr(d['holder']),
              if (vStr(d['key_hint']).isNotEmpty) '${tx(context, 'المِفتاح', 'key')} …${d['key_hint']}'].where((x) => x.isNotEmpty).join(' · '),
            if (vStr(d['note']).isNotEmpty) vStr(d['note']),
          ].where((x) => x.trim().isNotEmpty).join('\n'),
          style: const TextStyle(color: VC.muted, fontSize: 12.5, height: 1.5),
        ),
        _health(d),
        if (_edit) ...[
          const SizedBox(height: 10),
          _orders(d),
        ],
      ]),
    );
  }

  /// DB 341: what the device reported – permissions, protection, battery saving, waiting records, last error.
  Widget _health(VJson d) {
    final h = vMap(d['health']);
    if (h.isEmpty) return const SizedBox.shrink();
    Widget pill(bool? ok, String ar, String en) => VPill(tx(context, ar, en),
        color: ok == null ? VC.muted : (ok ? VC.ok : VC.bad), icon: ok == null ? Icons.help_outline : (ok ? Icons.check : Icons.close));
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        pill(h['sms'] as bool?, 'صَلاحيّة SMS', 'SMS permission'),
        if (vBool(d['log_calls'])) pill(h['calls'] as bool?, 'سِجِلّ المُكالَمات', 'Call log'),
        pill(h['admin'] as bool?, 'الحِماية', 'Protection'),
        pill(h['battery'] as bool?, 'شَغّال مَع تَوفير البَطّاريّة', 'Kept running'),
        if (vNum(h['waiting']) > 0) VPill(tx(context, '${h['waiting']} مُستَنّي رَفع', '${h['waiting']} waiting upload'), color: VC.warn),
        if (vStr(h['error']).isNotEmpty) Tooltip(message: vStr(h['error']), child: VPill(tx(context, 'آخِر خَطَأ', 'Last error'), color: VC.bad, icon: Icons.error_outline)),
      ]),
    );
  }

  /// DB 341: orders to the device – read the phone again and upload the old data, or sync now.
  Widget _orders(VJson d) {
    final at = vTime(d['cmd_at']), done = vTime(d['cmd_done_at']);
    final waiting = at != null && (done == null || done.isBefore(at));
    Future<void> order(String cmd, [int days = 30]) async {
      final ok = await vGuard(context, () => ValetAdmin.I.call('vva_fleet_command', {'p_id': d['id'], 'p_cmd': cmd, 'p_days': days}),
          ok: tx(context, 'اتبَعَت لِلجِهاز – بِيِتنَفِّذ في أَوِّل فَحص (خِلال 15 دَقيقة، أَو عَلى طول لَو التَطبيق اتفَتَح).',
              'Sent to the device – done at its next check (within 15 minutes, or at once when the app is opened).'));
      if (ok != null) await _load();
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(tx(context, 'رَفع البَيانات القَديمة:', 'Upload old data:'), style: const TextStyle(fontWeight: FontWeight.w700)),
        OutlinedButton.icon(onPressed: () => order('resend', 30), icon: const Icon(Icons.history, size: 18), label: Text(tx(context, 'آخِر 30 يوم', 'Last 30 days'))),
        OutlinedButton.icon(onPressed: () => order('resend', 90), icon: const Icon(Icons.history, size: 18), label: Text(tx(context, 'آخِر 90 يوم', 'Last 90 days'))),
        OutlinedButton.icon(onPressed: () => order('resend', 0), icon: const Icon(Icons.all_inclusive, size: 18), label: Text(tx(context, 'الكُلّ', 'All'))),
        FilledButton.tonalIcon(onPressed: () => order('sync'), icon: const Icon(Icons.sync, size: 18), label: Text(tx(context, 'مُزامَنة الآن', 'Sync now'))),
      ]),
      if (at != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            waiting
                ? tx(context, '⏳ مُستَنّي الجِهاز (اتطَلَب ${VF.dt(at)})', '⏳ Waiting for the device (asked ${VF.dt(at)})')
                : '✓ ${VF.dt(done)} · ${vStr(d['cmd_result'])}',
            style: TextStyle(fontSize: 12.5, color: waiting ? VC.warn : VC.ok),
          ),
        ),
    ]);
  }
}

// ================================================================ messages / calls / daily
class _Log extends StatefulWidget {
  const _Log({required this.kind});
  final String kind; // sms / calls / daily

  @override
  State<_Log> createState() => _LogState();
}

class _LogState extends State<_Log> {
  late DateTime _from, _to;
  String? _device;
  String _filter = 'all';
  final _q = TextEditingController();
  List<VJson> _devices = const [];
  VJson? _d;
  Object? _err;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _to = DateTime(n.year, n.month, n.day);
    _from = _to.subtract(const Duration(days: 6));
    ValetAdmin.I.call('vva_fleet_devices').then((r) {
      if (mounted) setState(() => _devices = vList(r['items']));
    }).catchError((_) {});
    _load();
  }

  Future<void> _load() async {
    setState(() => _err = null);
    try {
      final d = await ValetAdmin.I.call('vva_fleet_log', {
        'p_device': _device, 'p_from': VF.iso(_from), 'p_to': VF.iso(_to), 'p_kind': _filter, 'p_search': _q.text.trim(), 'p_limit': 2000,
      });
      if (mounted) setState(() => _d = d);
    } catch (e) {
      if (mounted) setState(() => _err = e);
    }
  }

  static String _dur(num s) => '${s ~/ 60}:${(s % 60).toInt().toString().padLeft(2, '0')}';

  String _rtaText(BuildContext context, VJson? r) {
    if (r == null) return '';
    final fee = vNum(r['fee']) + vNum(r['tnx_fee']);
    return [
      vStr(r['kind']),
      if (vStr(r['plate']).isNotEmpty) vStr(r['plate']),
      if (vStr(r['zone']).isNotEmpty) vStr(r['zone']),
      if (r['hours'] != null) '${r['hours']}h',
      if (fee > 0) 'AED ${fee.toStringAsFixed(2)}',
      if (r['exp'] != null) '→ ${VF.dt(vTime(r['exp']))}',
    ].join(' · ');
  }

  Future<void> _export() async {
    final d = _d;
    if (d == null) return;
    await vExport(context, 'vip_fleet_${widget.kind}_${VF.iso(_from)}_${VF.iso(_to)}', [
      if (widget.kind == 'sms')
        ExcelSheet(
          name: 'Messages',
          headers: const ['Time', 'Device', 'Direction', 'Number', 'Label', 'SIM', 'Message', 'RTA kind', 'Plate', 'Zone', 'Hours', 'Fee', 'Tnx fee', 'Expires', 'Invoice', 'Valet ticket', 'Point'],
          rows: [
            for (final m in vList(d['sms']))
              () {
                final r = vMap(m['rta']);
                return [
                  vTime(m['ts']), vStr(m['device']), vStr(m['direction']), vStr(m['address']), vStr(m['label']), vStr(m['sim']), vStr(m['body']),
                  vStr(r['kind']), vStr(r['plate']), vStr(r['zone']), r['hours'] == null ? null : vNum(r['hours']), r['fee'] == null ? null : vNum(r['fee']),
                  r['tnx_fee'] == null ? null : vNum(r['tnx_fee']), vTime(r['exp']), vStr(r['inv']), vStr(m['ticket']), vStr(m['point']),
                ];
              }(),
          ],
        ),
      if (widget.kind == 'calls')
        ExcelSheet(
          name: 'Calls',
          headers: const ['Time', 'Device', 'Type', 'Number', 'Name', 'Duration (s)'],
          rows: [for (final c in vList(d['calls'])) [vTime(c['ts']), vStr(c['device']), vStr(c['type']), vStr(c['number']), vStr(c['name']), vNum(c['duration_sec'])]],
        ),
      if (widget.kind == 'daily')
        ExcelSheet(
          name: 'Daily',
          headers: const ['Day', 'Device', 'SMS sent', 'SMS received', 'RTA confirmed', 'RTA amount AED'],
          rows: [for (final x in vList(d['daily'])) [vStr(x['day']), vStr(x['device']), vNum(x['sms_out']), vNum(x['sms_in']), vNum(x['rta_confirmed']), vNum(x['rta_amount'])]],
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final rows = vList(d?[widget.kind]);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            VRange(from: _from, to: _to, onChanged: (a, b) {
              setState(() {
                _from = a;
                _to = b;
              });
              _load();
            }),
            DropdownButton<String?>(
              value: _devices.any((x) => vStr(x['id']) == _device) ? _device : null,
              hint: Text(tx(context, 'كُلّ الأَجهِزة', 'All devices')),
              items: [
                DropdownMenuItem<String?>(value: null, child: Text(tx(context, 'كُلّ الأَجهِزة', 'All devices'))),
                for (final x in _devices) DropdownMenuItem<String?>(value: vStr(x['id']), child: Text(vStr(x['name']))),
              ],
              onChanged: (v) {
                setState(() => _device = v);
                _load();
              },
            ),
            if (widget.kind == 'sms')
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 'all', label: Text(tx(context, 'الكُلّ', 'All'))),
                  const ButtonSegment(value: 'rta', label: Text('RTA')),
                  ButtonSegment(value: 'in', label: Text(tx(context, 'وارِد', 'In'))),
                  ButtonSegment(value: 'out', label: Text(tx(context, 'صادِر', 'Out'))),
                ],
                selected: {_filter},
                onSelectionChanged: (v) {
                  setState(() => _filter = v.first);
                  _load();
                },
              ),
            if (widget.kind != 'daily')
              SizedBox(
                width: 220,
                child: TextField(
                  controller: _q,
                  decoration: InputDecoration(isDense: true, prefixIcon: const Icon(Icons.search), hintText: tx(context, 'بَحث (لوحة، رَقَم، نَص)', 'Search (plate, number, text)')),
                  onSubmitted: (_) => _load(),
                ),
              ),
            IconButton.filledTonal(tooltip: 'Excel', onPressed: d == null ? null : _export, icon: const Icon(Icons.download)),
          ]),
        ),
        if (_err != null) Padding(padding: const EdgeInsets.all(16), child: Text(vErr(context, _err!), style: const TextStyle(color: VC.bad))),
        if (d == null && _err == null) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
        if (d != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: VPanel(
              title: '${switch (widget.kind) { 'sms' => tx(context, 'الرَسايل', 'Messages'), 'calls' => tx(context, 'المُكالَمات', 'Calls'), _ => tx(context, 'المُلَخَّص اليَوميّ', 'Daily summary') }} (${rows.length})',
              child: switch (widget.kind) {
                'sms' => VTable(
                    empty: tx(context, 'مَفيش رَسايل', 'No messages'),
                    columns: [
                      DataColumn(label: Text(tx(context, 'الوَقت', 'Time'))),
                      DataColumn(label: Text(tx(context, 'الجِهاز', 'Device'))),
                      DataColumn(label: Text(tx(context, 'الرَقَم', 'Number'))),
                      DataColumn(label: Text(tx(context, 'الرِسالة', 'Message'))),
                      const DataColumn(label: Text('RTA')),
                      DataColumn(label: Text(tx(context, 'تَكت الفاليه', 'Valet ticket'))),
                    ],
                    rows: [
                      for (final m in rows)
                        DataRow(cells: [
                          DataCell(Text(VF.dt(vTime(m['ts'])))),
                          DataCell(Text(vStr(m['device']))),
                          DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(m['direction'] == 'out' ? Icons.north_east : Icons.south_west, size: 16, color: m['direction'] == 'out' ? VC.info : VC.ok),
                            const SizedBox(width: 4),
                            Text(vStr(m['address'])),
                          ])),
                          DataCell(ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 360),
                            child: Tooltip(message: vStr(m['body']), child: Text(vStr(m['body']).replaceAll('\n', ' · '), maxLines: 2, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr)),
                          )),
                          DataCell(m['rta'] == null
                              ? const Text('-')
                              : VPill(_rtaText(context, vMap(m['rta'])),
                                  color: switch (vStr(vMap(m['rta'])['kind'])) {
                                    'confirm' || 'extension' => VC.ok,
                                    'error' => VC.bad,
                                    'reminder' => VC.warn,
                                    _ => VC.info,
                                  })),
                          DataCell(Text(vStr(m['ticket']).isEmpty ? '-' : '${VF.short(vStr(m['ticket']))} · ${vStr(m['point'])}')),
                        ]),
                    ],
                  ),
                'calls' => VTable(
                    empty: tx(context, 'مَفيش مُكالَمات', 'No calls'),
                    columns: [
                      DataColumn(label: Text(tx(context, 'الوَقت', 'Time'))),
                      DataColumn(label: Text(tx(context, 'الجِهاز', 'Device'))),
                      DataColumn(label: Text(tx(context, 'النَوع', 'Type'))),
                      DataColumn(label: Text(tx(context, 'الرَقَم', 'Number'))),
                      DataColumn(label: Text(tx(context, 'الاسم', 'Name'))),
                      DataColumn(label: Text(tx(context, 'المُدّة', 'Duration')), numeric: true),
                    ],
                    rows: [
                      for (final c in rows)
                        DataRow(cells: [
                          DataCell(Text(VF.dt(vTime(c['ts'])))),
                          DataCell(Text(vStr(c['device']))),
                          DataCell(VPill(vStr(c['type']), color: switch (vStr(c['type'])) { 'missed' || 'rejected' => VC.bad, 'outgoing' => VC.info, _ => VC.ok })),
                          DataCell(Text(vStr(c['number']))),
                          DataCell(Text(vStr(c['name']))),
                          DataCell(Text(_dur(vNum(c['duration_sec'])))),
                        ]),
                    ],
                  ),
                _ => VTable(
                    empty: tx(context, 'مَفيش بَيانات', 'No data'),
                    columns: [
                      DataColumn(label: Text(tx(context, 'اليَوم', 'Day'))),
                      DataColumn(label: Text(tx(context, 'الجِهاز', 'Device'))),
                      DataColumn(label: Text(tx(context, 'صادِر', 'Sent')), numeric: true),
                      DataColumn(label: Text(tx(context, 'وارِد', 'Received')), numeric: true),
                      DataColumn(label: Text(tx(context, 'RTA مُؤَكَّد', 'RTA confirmed')), numeric: true),
                      DataColumn(label: Text(tx(context, 'مَبلَغ RTA', 'RTA amount')), numeric: true),
                    ],
                    rows: [
                      for (final x in rows)
                        DataRow(cells: [
                          DataCell(Text(vStr(x['day']))),
                          DataCell(Text(vStr(x['device']))),
                          DataCell(Text(VF.n(vNum(x['sms_out'])))),
                          DataCell(Text(VF.n(vNum(x['sms_in'])))),
                          DataCell(Text(VF.n(vNum(x['rta_confirmed'])))),
                          DataCell(Text(VF.money(vNum(x['rta_amount'])))),
                        ]),
                    ],
                  ),
              },
            ),
          ),
      ]),
    );
  }
}
