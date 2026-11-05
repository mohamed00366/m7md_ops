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
          length: 6,
          initialIndex: initialTab.clamp(0, 5),
          child: Column(children: [
            Material(
              color: Theme.of(context).colorScheme.surface,
              child: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
                Tab(icon: const Icon(Icons.phone_android, size: 18), text: tx(context, 'الأَجهِزة', 'Devices')),
                Tab(icon: const Icon(Icons.sms_outlined, size: 18), text: tx(context, 'الرَسايل', 'Messages')),
                Tab(icon: const Icon(Icons.call_outlined, size: 18), text: tx(context, 'المُكالَمات', 'Calls')),
                Tab(icon: const Icon(Icons.calendar_month_outlined, size: 18), text: tx(context, 'مُلَخَّص يَوميّ', 'Daily summary')),
                Tab(icon: const Icon(Icons.insights_outlined, size: 18), text: tx(context, 'تَقرير شَهريّ', 'Monthly report')),
                Tab(icon: const Icon(Icons.person_search_outlined, size: 18), text: tx(context, 'بَحث بِالرَقَم', 'Search a number')),
              ]),
            ),
            const Expanded(child: TabBarView(children: [_Devices(), _Log(kind: 'sms'), _Log(kind: 'calls'), _Log(kind: 'daily'), _Month(), _Search()])),
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
  VJson _latest = const {};
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
      if (mounted) {
        setState(() {
          _items = vList(r['items']);
          _latest = vMap(r['latest']);
        });
      }
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
                  if (v.containsKey('battery_min')) ...[
                    const SizedBox(height: 6),
                    Text(tx(ctx, 'تَنبيه لَو البَطّاريّة أَقَلّ مِن:', 'Alert when the battery is below:'), style: const TextStyle(fontSize: 12.5)),
                    const SizedBox(height: 4),
                    SegmentedButton<int>(
                      showSelectedIcon: false,
                      segments: [for (final b in const [0, 10, 15, 20, 30]) ButtonSegment(value: b, label: Text(b == 0 ? tx(ctx, 'مَقفول', 'Off') : '$b%'))],
                      selected: {const [0, 10, 15, 20, 30].contains(v['battery_min']) ? v['battery_min'] as int : 15},
                      onSelectionChanged: (x) => set(() => v['battery_min'] = x.first),
                    ),
                  ],
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
                  if (v.containsKey('monthly_email')) ...[
                    const Divider(),
                    Text(tx(ctx, 'التَقرير الشَهريّ', 'Monthly report'), style: const TextStyle(fontWeight: FontWeight.w800)),
                    sw('monthly_email', 'تَقرير الشَهر اللي فات في إيميل يوم 1', 'Last month in the e-mail of the 1st'),
                    const SizedBox(height: 4),
                    Text(tx(ctx, 'مُكالَمة فايتة تِعتِبِر «ما اترَدّش عَلَيها» لَو مَفيش رَدّ خِلال:', 'A missed call counts as "not called back" with no call within:'),
                        style: const TextStyle(fontSize: 12.5)),
                    const SizedBox(height: 4),
                    SegmentedButton<int>(
                      showSelectedIcon: false,
                      segments: [for (final h in const [1, 2, 4, 8, 24]) ButtonSegment(value: h, label: Text(tx(ctx, '$h س', '$h h')))],
                      selected: {const [1, 2, 4, 8, 24].contains(v['missed_hours']) ? v['missed_hours'] as int : 2},
                      onSelectionChanged: (x) => set(() => v['missed_hours'] = x.first),
                    ),
                  ],
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

  /// DB 343: the newest VIP Settings for the devices (links of the files, and whether it is a must).
  Future<void> _updateSettings() async {
    final st = vMap(_alerts?['settings']);
    if (!st.containsKey('update_mode')) return;
    final ver = TextEditingController(text: vStr(st['app_version']));
    final build = TextEditingController(text: st['app_build'] == null ? '' : '${st['app_build']}');
    final a64 = TextEditingController(text: vStr(st['apk_arm64']));
    final a32 = TextEditingController(text: vStr(st['apk_arm32']));
    final notes = TextEditingController(text: vStr(st['update_notes']));
    var mode = vStr(st['update_mode']).isEmpty ? 'off' : vStr(st['update_mode']);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(tx(ctx, 'تَحديث تَطبيق VIP Settings', 'VIP Settings app update')),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: 'off', label: Text(tx(ctx, 'مَقفول', 'Off'))),
                    ButtonSegment(value: 'notify', label: Text(tx(ctx, 'تَنبيه «حَدِّث»', 'Show "Update"'))),
                    ButtonSegment(value: 'force', label: Text(tx(ctx, 'لازِم يِتحَدِّث', 'Must update'))),
                  ],
                  selected: {mode},
                  onSelectionChanged: (x) => set(() => mode = x.first),
                ),
                const SizedBox(height: 4),
                Text(
                    tx(ctx, 'الأَجهِزة اللي عَليها إصدار أَقدَم بِيِظهَرلَها زُرار «حَدِّث». الـ Device Owner بِيِتحَدِّث لِوَحده مِن غير ما يِسأَل.',
                        'Devices with an older version see an "Update" button. A Device Owner updates by itself.'),
                    style: const TextStyle(color: VC.muted, fontSize: 12)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: TextField(controller: ver, decoration: InputDecoration(labelText: tx(ctx, 'الإصدار', 'Version'), hintText: '1.0.5'))),
                  const SizedBox(width: 10),
                  SizedBox(
                      width: 120,
                      child: TextField(
                          controller: build,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: InputDecoration(labelText: tx(ctx, 'رَقَم البِناء', 'Build'), hintText: '6'))),
                ]),
                const SizedBox(height: 8),
                TextField(controller: a64, decoration: InputDecoration(labelText: tx(ctx, 'رابِط arm64 (الأَجهِزة الحَديثة)', 'arm64 link (newer devices)'))),
                const SizedBox(height: 8),
                TextField(controller: a32, decoration: InputDecoration(labelText: tx(ctx, 'رابِط armeabi-v7a (الأَجهِزة القَديمة)', 'armeabi-v7a link (older devices)'))),
                const SizedBox(height: 8),
                TextField(controller: notes, maxLines: 2, decoration: InputDecoration(labelText: tx(ctx, 'إيه الجَديد (يِظهَر عَلى الجِهاز)', 'What is new (shown on the device)'))),
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
    if (ok != true || !mounted) return;
    final r = await vGuard(
        context,
        () => ValetAdmin.I.call('vva_fleet_alerts_save', {
              'p_data': {'update_mode': mode, 'app_version': ver.text.trim(), 'app_build': build.text.trim(), 'apk_arm64': a64.text.trim(), 'apk_arm32': a32.text.trim(), 'update_notes': notes.text.trim()}
            }),
        ok: tx(context, 'تَمّ الحِفظ.', 'Saved.'));
    if (r != null && mounted) {
      setState(() => _alerts = r);
      await _load();
    }
  }

  /// DB 343: clean-up of the device – uploaded records older than N days leave the device (they stay here).
  Future<void> _cleanup(VJson d) async {
    var on = vBool(d['cleanup_on']);
    var days = vNum(d['cleanup_days']).toInt();
    if (days < 7) days = 90;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(tx(ctx, 'تَنظيف الجِهاز · ${d['name']}', 'Device clean-up · ${d['name']}')),
          content: SizedBox(
            width: 440,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tx(ctx, 'امسَح السِجِلّات القَديمة مِن الجِهاز', 'Remove old records from the device')),
                value: on,
                onChanged: (x) => set(() => on = x),
              ),
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [for (final n in const [30, 60, 90, 180, 365]) ButtonSegment(value: n, label: Text(tx(ctx, '$n يوم', '$n d')))],
                selected: {const [30, 60, 90, 180, 365].contains(days) ? days : 90},
                onSelectionChanged: on ? (x) => set(() => days = x.first) : null,
              ),
              const SizedBox(height: 8),
              Text(
                  tx(ctx, 'بِيِتمِسِح بَسّ اللي اترَفَع لِلسيرفَر وَعَدّى عَلَيه المُدّة دي. اللي لِسّه ما اترَفَعش عُمره ما يِتمِسِح، وَكُلّه بِيِفضَل هِنا في الداشبورد. مَرّة في اليوم.',
                      'Only what reached the server and is older than this. What is not uploaded is never removed; everything stays here in the dashboard. Once a day.'),
                  style: const TextStyle(color: VC.muted, fontSize: 12)),
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
    await vGuard(context, () => ValetAdmin.I.call('vva_fleet_device_opts', {'p_id': d['id'], 'p_data': {'cleanup_on': on, 'cleanup_days': days}}),
        ok: tx(context, 'تَمّ الحِفظ.', 'Saved.'));
    await _load();
  }

  /// DB 344: "dashboard-only control" — the device app becomes view-only.
  Future<void> _lock(VJson d) async {
    final on = !vBool(d['settings_locked']);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(on ? tx(ctx, 'التَحكُّم مِن الداشبورد فَقَط', 'Dashboard-only control') : tx(ctx, 'فَكّ القَفل', 'Unlock')),
        content: Text(on
            ? tx(ctx, 'شاشة «${d['name']}» هَتبقى لِلعَرض فَقَط، وَكُلّ المَفاتيح مِن الداشبورد. حَتّى اللي ماسِك التابلت مُش هَيقدَر يغَيَّر إعداد. التَسجيل بِيكَمِّل عادي.',
                'The "${d['name']}" screen becomes view-only — every switch comes from the dashboard. Whoever holds the tablet cannot change a setting. Recording continues.')
            : tx(ctx, '«${d['name']}» هَيرجَع يقدَر يغَيَّر إعداداته مِن التابلت.', '"${d['name']}" can change its own settings again.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tx(ctx, 'إلغاء', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tx(ctx, 'تَمام', 'OK'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await vGuard(context, () => ValetAdmin.I.call('vva_fleet_device_opts', {'p_id': d['id'], 'p_data': {'settings_locked': on}}),
        ok: tx(context, 'تَمّ · هَيطبَّق في أَوِّل فَحص لِلجِهاز.', 'Saved · applies at the next device check.'));
    await _load();
  }

  /// DB 343: the device stops being Device Owner (then it can be removed like any app).
  Future<void> _release(VJson d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tx(ctx, 'فَكّ الـ Device Owner', 'Release Device Owner')),
        content: Text(tx(ctx, '«${d['name']}» هَيِبطَل Device Owner في أَوِّل فَحص، وَبَعدها التَطبيق يِتشال عادي. التَسجيل بِيِكَمِّل. مُتَأَكِّد؟',
            '"${d['name']}" stops being Device Owner at its next check; then the app can be removed normally. Recording goes on. Sure?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tx(ctx, 'لا', 'No'))),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: VC.bad), onPressed: () => Navigator.pop(ctx, true), child: Text(tx(ctx, 'فُكّ', 'Release'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await vGuard(context, () => ValetAdmin.I.call('vva_fleet_command', {'p_id': d['id'], 'p_cmd': 'owner_release', 'p_days': 0}),
        ok: tx(context, 'اتبَعَت لِلجِهاز.', 'Sent to the device.'));
    await _load();
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
              Text(tx(ctx, 'اكتِبه في تَطبيق VIP Settings عَلى الجِهاز. بِيِظهَر مَرّة واحدة بَس – لَو ضاع اعمِل مِفتاح جَديد.',
                  'Type it in the VIP Settings app on the device. It is shown ONCE – if it is lost, make a new key.'),
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
          tx(context, 'VIP Settings · أَجهِزة الشَرِكة', 'VIP Settings · company devices'),
          subtitle: tx(context, 'تَطبيق عَلى تابلِت/موبايل الشَرِكة بِيِسَجِّل رَسايل الأَرقام المُراقَبة (RTA 7275) وَسِجِلّ المُكالَمات · أَندرويد بَس',
              'An app on the company tablets / phones logs the SMS of the watched numbers (RTA 7275) and the call log · Android only'),
          actions: [
            if (_edit && _alerts != null)
              IconButton.filledTonal(tooltip: tx(context, 'التَنبيهات وَالمُلَخَّص', 'Alerts and summary'), onPressed: _alertSettings, icon: const Icon(Icons.notifications_active_outlined)),
            if (_edit && vMap(_alerts?['settings']).containsKey('update_mode'))
              IconButton.filledTonal(
                  tooltip: tx(context, 'تَحديث التَطبيق', 'App update'),
                  onPressed: _updateSettings,
                  icon: Badge(isLabelVisible: vStr(_latest['mode']) != 'off' && _latest['build'] != null, child: const Icon(Icons.system_update_outlined))),
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
              'clean' => _cleanup(d),
              'lock' => _lock(d),
              'release' => _release(d),
              _ => _stop(d),
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'edit', child: Text(tx(context, 'تَعديل · الأَرقام المُراقَبة', 'Edit · watched numbers'))),
              PopupMenuItem(value: 'key', child: Text(tx(context, 'مِفتاح جَديد', 'New key'))),
              if (d.containsKey('settings_locked'))
                PopupMenuItem(value: 'lock', child: Text(vBool(d['settings_locked']) ? tx(context, 'فَكّ القَفل (تَحكُّم مِن الجِهاز)', 'Unlock (allow device control)') : tx(context, 'التَحكُّم مِن الداشبورد فَقَط', 'Dashboard-only control'))),
              if (d.containsKey('cleanup_on')) PopupMenuItem(value: 'clean', child: Text(tx(context, 'تَنظيف الجِهاز', 'Device clean-up'))),
              if (vMap(d['health'])['owner'] == true) PopupMenuItem(value: 'release', child: Text(tx(context, 'فَكّ الـ Device Owner', 'Release Device Owner'))),
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
            if (vBool(d['cleanup_on'])) tx(context, 'تَنظيف: اللي اترَفَع وَأَقدَم مِن ${d['cleanup_days']} يوم بِيِتمِسِح مِن الجِهاز', 'Clean-up: uploaded records older than ${d['cleanup_days']} days leave the device'),
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
        if (vStr(d['battery_pct']).isNotEmpty)
          VPill('${d['battery_pct']}%',
              color: vNum(d['battery_pct']) < 15 ? VC.bad : (vNum(d['battery_pct']) < 30 ? VC.warn : VC.ok),
              icon: vNum(d['battery_pct']) < 15 ? Icons.battery_alert : Icons.battery_full),
        if (vBool(d['settings_locked'])) VPill(tx(context, 'تَحكُّم مِن الداشبورد', 'Dashboard-controlled'), color: VC.info, icon: Icons.lock_outline),
        if (h['owner'] == true) const VPill('Device Owner', color: VC.ok, icon: Icons.verified_user_outlined),
        if (_latest['build'] != null && vNum(h['build']) < vNum(_latest['build']))
          VPill(tx(context, 'إصدار قَديم v${d['app_version']} ← ${_latest['version']}', 'Old v${d['app_version']} → ${_latest['version']}'), color: VC.warn, icon: Icons.system_update_outlined),
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

// ================================================================ monthly report (DB 343)
class _Month extends StatefulWidget {
  const _Month();

  @override
  State<_Month> createState() => _MonthState();
}

class _MonthState extends State<_Month> {
  late DateTime _m;
  String? _device;
  List<VJson> _devices = const [];
  VJson? _d;
  Object? _err;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _m = DateTime(n.year, n.month);
    ValetAdmin.I.call('vva_fleet_devices').then((r) {
      if (mounted) setState(() => _devices = vList(r['items']));
    }).catchError((_) {});
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _err = null;
      _d = null;
    });
    try {
      final d = await ValetAdmin.I.call('vva_fleet_month', {'p_month': VF.iso(_m), 'p_device': _device});
      if (mounted) setState(() => _d = d);
    } catch (e) {
      if (mounted) setState(() => _err = e);
    }
  }

  void _move(int k) {
    setState(() => _m = DateTime(_m.year, _m.month + k));
    _load();
  }

  Future<void> _export() async {
    final d = _d;
    if (d == null) return;
    await vExport(context, 'vip_lines_${vStr(d['month'])}', [
      ExcelSheet(
        name: 'Lines',
        headers: const ['Device', 'Point', 'SMS sent', 'SMS received', 'Calls out', 'Calls in', 'Missed', 'Not called back', 'Talk (min)'],
        rows: [
          for (final x in vList(d['devices']))
            [vStr(x['name']), vStr(x['point']), vNum(x['sms_out']), vNum(x['sms_in']), vNum(x['calls_out']), vNum(x['calls_in']), vNum(x['missed']), vNum(x['not_called_back']), vNum(x['talk_min'])],
        ],
      ),
      ExcelSheet(
        name: 'Top numbers',
        headers: const ['Number', 'Name', 'SMS', 'Calls', 'Total'],
        rows: [for (final x in vList(d['top'])) [vStr(x['number']), vStr(x['name']), vNum(x['sms']), vNum(x['calls']), vNum(x['total'])]],
      ),
      ExcelSheet(
        name: 'Not called back',
        headers: const ['Time', 'Device', 'Number', 'Name', 'Type'],
        rows: [for (final x in vList(d['missed_list'])) [vTime(x['at']), vStr(x['device']), vStr(x['number']), vStr(x['name']), vStr(x['type'])]],
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final devs = vList(d?['devices']);
    num sum(String k) => devs.fold<num>(0, (a, x) => a + vNum(x[k]));
    final now = DateTime.now();
    final last = _m.year == now.year && _m.month == now.month;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            IconButton.filledTonal(tooltip: tx(context, 'الشَهر اللي فات', 'Previous month'), onPressed: () => _move(-1), icon: Icon(rtl ? Icons.chevron_right : Icons.chevron_left)),
            Text('${_m.month.toString().padLeft(2, '0')}/${_m.year}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            IconButton.filledTonal(tooltip: tx(context, 'الشَهر اللي بَعده', 'Next month'), onPressed: last ? null : () => _move(1), icon: Icon(rtl ? Icons.chevron_left : Icons.chevron_right)),
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
            IconButton.filledTonal(tooltip: 'Excel', onPressed: d == null ? null : _export, icon: const Icon(Icons.download)),
          ]),
        ),
        if (_err != null) Padding(padding: const EdgeInsets.all(16), child: Text(vErr(context, _err!), style: const TextStyle(color: VC.bad))),
        if (d == null && _err == null) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
        if (d != null) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(spacing: 10, runSpacing: 10, children: [
              VKpi(tx(context, 'رَسايل', 'SMS'), VF.n(sum('sms_out') + sum('sms_in')), icon: Icons.sms_outlined, color: VC.info,
                  note: tx(context, '${VF.n(sum('sms_out'))} صادِر · ${VF.n(sum('sms_in'))} وارِد', '${VF.n(sum('sms_out'))} out · ${VF.n(sum('sms_in'))} in')),
              VKpi(tx(context, 'مُكالَمات', 'Calls'), VF.n(sum('calls_out') + sum('calls_in')), icon: Icons.call_outlined, color: VC.ok,
                  note: tx(context, '${VF.n(sum('calls_out'))} صادِر · ${VF.n(sum('calls_in'))} وارِد', '${VF.n(sum('calls_out'))} out · ${VF.n(sum('calls_in'))} in')),
              VKpi(tx(context, 'فايتة', 'Missed'), VF.n(sum('missed')), icon: Icons.phone_missed_outlined, color: VC.warn),
              VKpi(tx(context, 'ما اترَدّش عَلَيها', 'Not called back'), VF.n(sum('not_called_back')), icon: Icons.phone_callback_outlined, color: VC.bad,
                  note: tx(context, 'مَفيش رَدّ خِلال ${d['missed_hours']} س', 'no call within ${d['missed_hours']} h')),
              VKpi(tx(context, 'دَقايق كَلام', 'Talk minutes'), VF.n(sum('talk_min')), icon: Icons.timer_outlined),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: VPanel(
              title: tx(context, 'كُلّ خَطّ', 'Each line'),
              child: VTable(
                empty: tx(context, 'مَفيش أَجهِزة', 'No devices'),
                columns: [
                  DataColumn(label: Text(tx(context, 'الجِهاز', 'Device'))),
                  DataColumn(label: Text(tx(context, 'رَسايل صادِر', 'SMS out')), numeric: true),
                  DataColumn(label: Text(tx(context, 'رَسايل وارِد', 'SMS in')), numeric: true),
                  DataColumn(label: Text(tx(context, 'مُكالَمات صادِر', 'Calls out')), numeric: true),
                  DataColumn(label: Text(tx(context, 'مُكالَمات وارِد', 'Calls in')), numeric: true),
                  DataColumn(label: Text(tx(context, 'فايتة', 'Missed')), numeric: true),
                  DataColumn(label: Text(tx(context, 'ما اترَدّش', 'Not called back')), numeric: true),
                  DataColumn(label: Text(tx(context, 'دَقايق', 'Minutes')), numeric: true),
                ],
                rows: [
                  for (final x in devs)
                    DataRow(cells: [
                      DataCell(Text('${x['name']}${vStr(x['point']).isEmpty ? '' : ' · ${x['point']}'}')),
                      DataCell(Text(VF.n(vNum(x['sms_out'])))),
                      DataCell(Text(VF.n(vNum(x['sms_in'])))),
                      DataCell(Text(VF.n(vNum(x['calls_out'])))),
                      DataCell(Text(VF.n(vNum(x['calls_in'])))),
                      DataCell(Text(VF.n(vNum(x['missed'])))),
                      DataCell(vNum(x['not_called_back']) > 0 ? VPill(VF.n(vNum(x['not_called_back'])), color: VC.bad) : const Text('0')),
                      DataCell(Text(VF.n(vNum(x['talk_min'])))),
                    ]),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: VPanel(
              title: tx(context, 'أَكتَر 10 أَرقام', 'Top 10 numbers'),
              child: VTable(
                empty: tx(context, 'مَفيش', 'None'),
                columns: [
                  DataColumn(label: Text(tx(context, 'الرَقَم', 'Number'))),
                  DataColumn(label: Text(tx(context, 'الاسم', 'Name'))),
                  const DataColumn(label: Text('SMS'), numeric: true),
                  DataColumn(label: Text(tx(context, 'مُكالَمات', 'Calls')), numeric: true),
                  DataColumn(label: Text(tx(context, 'الإجماليّ', 'Total')), numeric: true),
                ],
                rows: [
                  for (final x in vList(d['top']))
                    DataRow(cells: [
                      DataCell(Text(vStr(x['number']), textDirection: TextDirection.ltr)),
                      DataCell(Text(vStr(x['name']))),
                      DataCell(Text(VF.n(vNum(x['sms'])))),
                      DataCell(Text(VF.n(vNum(x['calls'])))),
                      DataCell(Text(VF.n(vNum(x['total'])), style: const TextStyle(fontWeight: FontWeight.w800))),
                    ]),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: VPanel(
              title: tx(context, 'مُكالَمات فايتة ما اترَدّش عَلَيها (${vList(d['missed_list']).length})', 'Missed calls not called back (${vList(d['missed_list']).length})'),
              child: VTable(
                empty: tx(context, 'كُلّه اترَدّ عَلَيه 👍', 'All called back 👍'),
                columns: [
                  DataColumn(label: Text(tx(context, 'الوَقت', 'Time'))),
                  DataColumn(label: Text(tx(context, 'الجِهاز', 'Device'))),
                  DataColumn(label: Text(tx(context, 'الرَقَم', 'Number'))),
                  DataColumn(label: Text(tx(context, 'الاسم', 'Name'))),
                ],
                rows: [
                  for (final x in vList(d['missed_list']))
                    DataRow(cells: [
                      DataCell(Text(VF.dt(vTime(x['at'])))),
                      DataCell(Text(vStr(x['device']))),
                      DataCell(Text(vStr(x['number']), textDirection: TextDirection.ltr)),
                      DataCell(Text(vStr(x['name']))),
                    ]),
                ],
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

// ================================================================ one number over all devices (DB 343)
class _Search extends StatefulWidget {
  const _Search();

  @override
  State<_Search> createState() => _SearchState();
}

class _SearchState extends State<_Search> {
  final _q = TextEditingController();
  List<VJson>? _items;
  String _msg = '';
  bool _busy = false;

  Future<void> _go() async {
    final q = _q.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _busy = true;
      _msg = '';
    });
    try {
      final r = await ValetAdmin.I.call('vva_fleet_search', {'p_q': q, 'p_limit': 500});
      if (!mounted) return;
      setState(() {
        if (r['ok'] == false) {
          _items = null;
          _msg = tx(context, 'اكتِب 4 أَرقام عَلى الأَقَلّ', 'Type at least 4 digits');
        } else {
          _items = vList(r['items']);
        }
      });
    } catch (e) {
      if (mounted) setState(() => _msg = vErr(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final sms = items?.where((x) => x['kind'] == 'sms').length ?? 0;
    final devs = items?.map((x) => vStr(x['device'])).toSet().length ?? 0;
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: 300,
            child: TextField(
              controller: _q,
              autofocus: true,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search),
                  labelText: tx(context, 'رَقَم العَميل (أَو آخِره)', 'Customer number (or its end)'),
                  hintText: '0501234567 · 1234567'),
              onSubmitted: (_) => _go(),
            ),
          ),
          FilledButton.icon(onPressed: _busy ? null : _go, icon: const Icon(Icons.person_search), label: Text(tx(context, 'دَوَّر في كُلّ الأَجهِزة', 'Search all devices'))),
          if (_busy) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
      ),
      if (_msg.isNotEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(_msg, style: const TextStyle(color: VC.bad))),
      if (items == null && _msg.isEmpty)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(tx(context, 'اكتِب رَقَم عَميل وَشوف كُلّ الرَسايل وَالمُكالَمات مَعاه مِن كُلّ أَجهِزة الشَرِكة عَلى خَطّ زَمَنيّ واحِد. 050 123 4567 هو نَفسه +971501234567.',
              'Type a customer number to see every SMS and call with it from all company devices on one timeline. 050 123 4567 is the same as +971501234567.'),
              style: const TextStyle(color: VC.muted)),
        ),
      if (items != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: VPanel(
            title: tx(context, '${items.length} نَتيجة · $sms رِسالة · ${items.length - sms} مُكالَمة · $devs جِهاز',
                '${items.length} results · $sms SMS · ${items.length - sms} calls · $devs device(s)'),
            child: VTable(
              empty: tx(context, 'مَفيش حاجة لِلرَقَم ده', 'Nothing for this number'),
              columns: [
                DataColumn(label: Text(tx(context, 'الوَقت', 'Time'))),
                DataColumn(label: Text(tx(context, 'الجِهاز', 'Device'))),
                DataColumn(label: Text(tx(context, 'النَوع', 'Type'))),
                DataColumn(label: Text(tx(context, 'الرَقَم', 'Number'))),
                DataColumn(label: Text(tx(context, 'التَفاصيل', 'Details'))),
              ],
              rows: [
                for (final x in items)
                  DataRow(cells: [
                    DataCell(Text(VF.dt(vTime(x['at'])))),
                    DataCell(Text(vStr(x['device']))),
                    DataCell(x['kind'] == 'sms'
                        ? VPill(x['dir'] == 'out' ? tx(context, 'SMS صادِر', 'SMS out') : tx(context, 'SMS وارِد', 'SMS in'), color: VC.info,
                            icon: x['dir'] == 'out' ? Icons.north_east : Icons.south_west)
                        : VPill(vStr(x['dir']), color: switch (vStr(x['dir'])) { 'missed' || 'rejected' => VC.bad, 'outgoing' => VC.info, _ => VC.ok },
                            icon: Icons.call_outlined)),
                    DataCell(Text('${x['number']}${vStr(x['name']).isEmpty ? '' : ' · ${x['name']}'}', textDirection: TextDirection.ltr)),
                    DataCell(ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 380),
                      child: x['kind'] == 'sms'
                          ? Tooltip(message: vStr(x['body']), child: Text(vStr(x['body']).replaceAll('\n', ' · '), maxLines: 2, overflow: TextOverflow.ellipsis))
                          : Text(tx(context, 'المُدّة ${vNum(x['sec']) ~/ 60}:${(vNum(x['sec']) % 60).toInt().toString().padLeft(2, '0')}',
                              'Duration ${vNum(x['sec']) ~/ 60}:${(vNum(x['sec']) % 60).toInt().toString().padLeft(2, '0')}')),
                    )),
                  ]),
              ],
            ),
          ),
        ),
    ]);
  }
}
