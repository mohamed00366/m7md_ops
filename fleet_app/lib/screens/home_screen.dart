import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import '../core/background.dart';
import '../core/demo.dart';
import '../core/report.dart';
import '../core/rta.dart';
import '../core/store.dart';
import '../core/sync.dart';
import '../main.dart';
import 'settings_screen.dart';

/// Device status: the dashboard switches, the permissions, the protection, the last sync, and the records.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const _native = MethodChannel('vip_fleet/native');
  Prefs? _p;
  bool _sms = false, _calls = false, _admin = false, _busy = false;
  (int, int, int, int) _counts = (0, 0, 0, 0);
  String _last = '';
  List<SmsRow> _recent = const [];
  bool _demoAdmin = false;

  void _set(VoidCallback f) => setState(f);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh().then((_) {
      if (_sms && !FleetDemo.on) FleetBackground.listenSms(() => _sync(reason: 'sms'));
      _sync(reason: 'open');
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final p = await Prefs.get();
    await p.reload();
    bool admin = _demoAdmin;
    if (!FleetDemo.on) {
      try {
        admin = await _native.invokeMethod<bool>('adminActive') ?? false;
      } catch (_) {}
    }
    final db = await LocalDb.open();
    final c = await db.counts();
    final recent = await db.sms(limit: 30);
    final sms = FleetDemo.on || await Permission.sms.isGranted, calls = FleetDemo.on || await Permission.phone.isGranted;
    if (!mounted) return;
    setState(() {
      _p = p;
      _sms = sms;
      _calls = calls;
      _admin = admin;
      _counts = c;
      _recent = recent;
    });
  }

  Future<void> _sync({String reason = 'manual'}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final r = await FleetSync.run(reason: reason);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _last = r.toString();
    });
    await _refresh();
  }

  Future<void> _askSms() async {
    final s = await Permission.sms.request();
    if (!s.isGranted && mounted) _restricted('SMS');
    await _refresh();
    if (_sms) {
      FleetBackground.listenSms(() => _sync(reason: 'sms'));
      _sync();
    }
  }

  Future<void> _askCalls() async {
    final s = await Permission.phone.request();
    if (!s.isGranted && mounted) _restricted('Call logs');
    await _refresh();
    if (_calls) _sync();
  }

  /// Android blocks SMS / call-log for an app installed from a file: how to allow it.
  void _restricted(String what) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$what permission is blocked'),
        content: Text('Android blocks this for apps installed from a file. To allow it:\n\n'
            '1. Open App info (button below)\n2. ⋮ (top right) ▸ Allow restricted settings\n3. Permissions ▸ $what ▸ Allow'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Later')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _native.invokeMethod('appSettings');
            },
            child: const Text('Open App info'),
          ),
        ],
      ),
    );
  }

  Future<void> _share() async {
    final cfg = _p?.config ?? const {};
    if (FleetDemo.on) {
      // web preview: the same Excel, downloaded
      final db = await LocalDb.open();
      final bytes = FleetReport.build(sms: await db.sms(), calls: await db.calls(), withCalls: cfg['log_calls'] == true);
      await XFile.fromData(Uint8List.fromList(bytes), name: 'VIP-Fleet-demo.xlsx', mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
          .saveTo('VIP-Fleet-demo.xlsx');
      return;
    }
    final f = await FleetReport.write('${cfg['name'] ?? 'device'}', withCalls: cfg['log_calls'] == true);
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path)], text: 'VIP Fleet · ${cfg['name'] ?? ''}'));
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    final cfg = p?.config ?? const {};
    final (sAll, sWait, cAll, cWait) = _counts;
    Widget chip(String label, bool on) => Chip(
          avatar: Icon(on ? Icons.check_circle : Icons.cancel, size: 18, color: on ? FleetColors.ok : FleetColors.muted),
          label: Text(label),
          visualDensity: VisualDensity.compact,
        );
    Widget perm(IconData icon, String title, String sub, bool ok, VoidCallback onFix, {String fix = 'Allow'}) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon, color: ok ? FleetColors.ok : FleetColors.warn),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(sub),
          trailing: ok ? const Icon(Icons.check, color: FleetColors.ok) : FilledButton.tonal(style: FilledButton.styleFrom(minimumSize: const Size(0, 40)), onPressed: onFix, child: Text(fix)),
        );
    return Scaffold(
      appBar: AppBar(
        title: Text('VIP Fleet${cfg['name'] == null ? '' : ' · ${cfg['name']}'}'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
              _refresh();
            },
          ),
          IconButton(tooltip: 'Lock', icon: const Icon(Icons.lock_outline), onPressed: () => Navigator.of(context).pushReplacementNamed('/login')),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _sync(),
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (FleetDemo.on) _demoPanel(),
          if (cfg['active'] == false)
            const Card(
              color: Color(0xFFFFEDED),
              child: ListTile(leading: Icon(Icons.pause_circle, color: FleetColors.bad), title: Text('Turned off in the dashboard'), subtitle: Text('Nothing is recorded until it is turned on.')),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(cfg['point'] == null ? 'Company device' : 'Point: ${cfg['point']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  chip('Log SMS', cfg['log_sms'] != false),
                  chip('Log calls', cfg['log_calls'] == true),
                  chip('Upload', cfg['upload_enabled'] != false && (p?.uploadOn ?? true)),
                  chip('Excel', p?.excelOn ?? true),
                  chip('E-mail', p?.emailOn ?? false),
                ]),
                const SizedBox(height: 6),
                Text('Watched: ${Watched.of(cfg['numbers']).map((w) => w.label.isEmpty ? w.number : '${w.number} (${w.label})').join(' · ')}',
                    style: const TextStyle(color: FleetColors.muted)),
                const Text('The switches are set in the dashboard (VIP Fleet).', style: TextStyle(color: FleetColors.muted, fontSize: 12)),
              ]),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
              child: Column(children: [
                perm(Icons.sms_outlined, 'SMS', 'Read the watched numbers', _sms, _askSms),
                if (cfg['log_calls'] == true) perm(Icons.call_outlined, 'Call log', 'Number, type, duration (no audio)', _calls, _askCalls),
                perm(Icons.shield_outlined, 'Protection', _admin ? 'The app cannot be removed' : 'Stops the app being removed', _admin,
                    () async {
                  if (FleetDemo.on) {
                    setState(() => _demoAdmin = true);
                    return _refresh();
                  }
                  await _native.invokeMethod('adminRequest');
                }, fix: 'Turn on'),
              ]),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Expanded(child: Text('Records on this device', style: TextStyle(fontWeight: FontWeight.w800))),
                  if (_busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                ]),
                const SizedBox(height: 6),
                Text('SMS $sAll · waiting upload $sWait'),
                if (cfg['log_calls'] == true) Text('Calls $cAll · waiting upload $cWait'),
                Text('Last sync: ${p?.lastSync == null ? '-' : fmtDt(p!.lastSync!)}'),
                if ((_last.isNotEmpty ? _last : (p?.lastError ?? '')).isNotEmpty)
                  Text(_last.isNotEmpty ? _last : p!.lastError, style: const TextStyle(color: FleetColors.muted, fontSize: 12.5)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: FilledButton.icon(onPressed: _busy ? null : () => _sync(), icon: const Icon(Icons.sync), label: const Text('Sync now'))),
                  const SizedBox(width: 8),
                  Expanded(child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: _share, icon: const Icon(Icons.ios_share), label: const Text('Share Excel'))),
                ]),
              ]),
            ),
          ),
          const Padding(padding: EdgeInsets.fromLTRB(4, 8, 4, 4), child: Text('Latest messages', style: TextStyle(fontWeight: FontWeight.w800))),
          if (_recent.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Nothing recorded yet.', style: TextStyle(color: FleetColors.muted))),
          for (final s in _recent) _SmsTile(s),
        ]),
      ),
    );
  }
}

extension on _HomeScreenState {
  /// Web preview only: plays the dashboard switches and makes messages arrive on the "phone".
  Widget _demoPanel() {
    final c = FleetDemo.config;
    Widget sw(String k, String label) => FilterChip(
          label: Text(label),
          selected: c[k] != false,
          onSelected: (v) {
            _set(() => c[k] = v);
            _sync();
          },
        );
    Widget add(String kind, IconData icon, String label) => ActionChip(
          avatar: Icon(icon, size: 18),
          label: Text(label),
          onPressed: () {
            FleetDemo.newRta(kind);
            _sync(reason: 'sms');
          },
        );
    return Card(
      color: const Color(0xFFFFF8E1),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Preview with sample data', style: TextStyle(fontWeight: FontWeight.w800)),
          const Text('No real SMS here. The switches below are the dashboard ones; the buttons make messages arrive on the phone.',
              style: TextStyle(fontSize: 12.5, color: FleetColors.muted)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            sw('active', 'Active'),
            sw('log_sms', 'Log SMS'),
            sw('log_calls', 'Log calls'),
            sw('upload_enabled', 'Upload'),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            add('pay', Icons.local_parking, 'RTA payment + confirmation'),
            add('extension', Icons.more_time, 'Extension (Y)'),
            add('reminder', Icons.timer_outlined, 'Reminder'),
            add('error', Icons.error_outline, 'Invalid plate'),
            add('other', Icons.sms_outlined, 'SMS from another number'),
            add('call', Icons.call_received, 'Incoming call'),
          ]),
          const SizedBox(height: 6),
          Text('Reached the "server": ${FleetDemo.uploadedSms} SMS · ${FleetDemo.uploadedCalls} calls', style: const TextStyle(fontSize: 12.5)),
        ]),
      ),
    );
  }
}

class _SmsTile extends StatelessWidget {
  const _SmsTile(this.s);
  final SmsRow s;

  @override
  Widget build(BuildContext context) {
    final rta = isRtaNumber(s.address) ? (s.direction == 'out' ? parseRtaOut(s.body) : parseRtaIn(s.body)) : null;
    final color = switch (rta?.kind) {
      'confirm' || 'extension' => FleetColors.ok,
      'error' => FleetColors.bad,
      'reminder' => FleetColors.warn,
      _ => FleetColors.muted,
    };
    final info = rta == null
        ? ''
        : [
            if (rta.plate.isNotEmpty) rta.plate,
            if (rta.zone.isNotEmpty) rta.zone,
            if (rta.confirmed) 'AED ${rta.total().toStringAsFixed(2)}',
            if (rta.exp != null) 'till ${fmtDt(rta.exp!)}',
          ].join(' · ');
    return Card(
      child: ListTile(
        leading: Icon(s.direction == 'out' ? Icons.north_east : Icons.south_west, color: color),
        title: Text(s.body, maxLines: 3, overflow: TextOverflow.ellipsis),
        subtitle: Text('${fmtDt(s.ts)} · ${s.address}${rta == null ? '' : ' · ${rta.kind}'}${info.isEmpty ? '' : '\n$info'}'),
        trailing: Icon(s.uploaded ? Icons.cloud_done_outlined : Icons.cloud_upload_outlined, size: 18, color: s.uploaded ? FleetColors.ok : FleetColors.muted),
        isThreeLine: info.isNotEmpty,
      ),
    );
  }
}
