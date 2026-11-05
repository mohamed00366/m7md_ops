import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/auth.dart';
import '../core/demo.dart';
import '../core/foreground.dart';
import '../core/report.dart';
import '../core/store.dart';
import '../core/sync.dart';
import '../main.dart';

/// Device options: upload / Excel / daily e-mail (SMTP), the logins, the device key, the protection.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _native = MethodChannel('vip_fleet/native');
  Prefs? _p;
  final _host = TextEditingController(), _port = TextEditingController(), _user = TextEditingController();
  final _pass = TextEditingController(), _to = TextEditingController();
  int _hour = 23;
  String _msg = '';

  @override
  void initState() {
    super.initState();
    Prefs.get().then((p) {
      _host.text = p.smtpHost;
      _port.text = '${p.smtpPort}';
      _user.text = p.smtpUser;
      _pass.text = p.smtpPass;
      _to.text = p.mailTo;
      _hour = p.mailHour;
      if (mounted) setState(() => _p = p);
    });
  }

  Future<void> _saveMail() async {
    await _p!.setMail(host: _host.text, port: int.tryParse(_port.text) ?? 587, user: _user.text, pass: _pass.text, to: _to.text, hour: _hour);
    setState(() => _msg = 'E-mail settings saved.');
  }

  Future<void> _testMail() async {
    await _saveMail();
    setState(() => _msg = 'Sending…');
    if (FleetDemo.on) return setState(() => _msg = 'Preview: no e-mail is sent here (on the device it sends the Excel to ${_p!.mailTo}).');
    final e = await FleetReport.mail(_p!, '${_p!.config['name'] ?? 'device'}', withCalls: _p!.config['log_calls'] == true);
    if (mounted) setState(() => _msg = e ?? 'Test e-mail sent to ${_p!.mailTo}.');
  }

  Future<void> _changeLogin(bool backup) async {
    final u = TextEditingController(text: backup ? 'backup' : 'admin'), pw = TextEditingController(), pw2 = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(backup ? 'Backup login' : 'Main login'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: u, decoration: const InputDecoration(labelText: 'User')),
          const SizedBox(height: 8),
          TextField(controller: pw, obscureText: true, decoration: const InputDecoration(labelText: 'New password')),
          const SizedBox(height: 8),
          TextField(controller: pw2, obscureText: true, decoration: const InputDecoration(labelText: 'Again')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    if (u.text.trim().isEmpty || pw.text.length < 4 || pw.text != pw2.text) return setState(() => _msg = 'Not saved: user + the same password twice (4+ letters).');
    final v = FleetAuth.make(u.text, pw.text);
    backup ? await _p!.setLoginBackup(v) : await _p!.setLoginMain(v);
    setState(() => _msg = '${backup ? 'Backup' : 'Main'} login changed.');
  }

  Future<void> _changeKey() async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New device key'),
        content: TextField(controller: c, decoration: const InputDecoration(labelText: 'VF-…')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Check and save')),
        ],
      ),
    );
    if (ok != true) return;
    final key = c.text.trim().toUpperCase();
    try {
      final cfg = await Api.pullConfig(key, kAppVersion, await FleetSync.deviceInfo());
      await _p!.setDeviceKey(key);
      await _p!.setConfig(cfg);
      setState(() => _msg = 'Device key saved · ${cfg['name']}');
    } catch (e) {
      setState(() => _msg = 'Not saved: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    if (p == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    Widget head(String t) => Padding(padding: const EdgeInsets.fromLTRB(4, 18, 4, 6), child: Text(t, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)));
    // 1.0.6: "dashboard only" — the whole settings page is view-only; every switch comes from the dashboard
    final locked = !FleetDemo.on && p.locked;
    return Scaffold(
      appBar: AppBar(flexibleSpace: kBarFlex, title: const Text('Settings')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (_msg.isNotEmpty) Card(color: const Color(0xFFFFF8E1), child: Padding(padding: const EdgeInsets.all(12), child: Text(_msg))),
        if (locked)
          Card(
            color: const Color(0xFFE8EEF6),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: const [
                Icon(Icons.lock_outline, color: FleetColors.ink),
                SizedBox(width: 10),
                Expanded(child: Text('هذا الجهاز يُدار من الداشبورد فقط. الإعدادات للعرض فقط.\nManaged from the dashboard — view only.')),
              ]),
            ),
          ),
        head('On this device'),
        SwitchListTile(
          title: const Text('Keep running (recommended)'),
          subtitle: const Text('A small permanent notification so the system does not stop recording'),
          value: p.keepAlive,
          onChanged: locked ? null : (v) async {
            await p.setKeepAlive(v);
            if (v) {
              await FleetForeground.startIfEnabled(p);
            } else {
              await FleetForeground.stop();
            }
            setState(() {});
          },
        ),
        SwitchListTile(
          title: const Text('Upload to the dashboard'),
          subtitle: const Text('Also needs "Upload" on in the dashboard'),
          value: p.uploadOn,
          onChanged: locked ? null : (v) async {
            await p.setUploadOn(v);
            setState(() {});
          },
        ),
        SwitchListTile(
          title: const Text('Excel on the device'),
          subtitle: const Text('RTA parking · All SMS · Daily summary · Calls (Share from the home page)'),
          value: p.excelOn,
          onChanged: locked ? null : (v) async {
            await p.setExcelOn(v);
            setState(() {});
          },
        ),
        SwitchListTile(
          title: const Text('Daily e-mail with the Excel'),
          value: p.emailOn,
          onChanged: locked ? null : (v) async {
            await p.setEmailOn(v);
            setState(() {});
          },
        ),
        if (p.emailOn && !locked) ...[
          const Text('Gmail: turn on 2-Step Verification, then make an App Password (16 letters) and put it here – the normal password is refused (535).',
              style: TextStyle(color: FleetColors.muted, fontSize: 12.5)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(flex: 3, child: TextField(controller: _host, decoration: const InputDecoration(labelText: 'SMTP server'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _port, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Port'))),
          ]),
          const SizedBox(height: 8),
          TextField(controller: _user, decoration: const InputDecoration(labelText: 'From (e-mail)')),
          const SizedBox(height: 8),
          TextField(controller: _pass, obscureText: true, decoration: const InputDecoration(labelText: 'App password')),
          const SizedBox(height: 8),
          TextField(controller: _to, decoration: const InputDecoration(labelText: 'Send to (comma between several)')),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: _hour,
            decoration: const InputDecoration(labelText: 'Send every day after'),
            items: [for (var h = 0; h < 24; h++) DropdownMenuItem(value: h, child: Text('${h.toString().padLeft(2, '0')}:00 (Dubai)'))],
            onChanged: (v) => setState(() => _hour = v ?? 23),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: _saveMail, child: const Text('Save'))),
            const SizedBox(width: 8),
            Expanded(child: FilledButton(onPressed: _testMail, child: const Text('Send a test'))),
          ]),
        ],
        head('Logins'),
        ListTile(leading: const Icon(Icons.person_outline), title: const Text('Change the main login'), enabled: !locked, onTap: locked ? null : () => _changeLogin(false)),
        ListTile(leading: const Icon(Icons.person_add_alt), title: const Text('Change the backup login'), enabled: !locked, onTap: locked ? null : () => _changeLogin(true)),
        head('Device'),
        ListTile(leading: const Icon(Icons.key_outlined), title: const Text('Change the device key'), enabled: !locked, subtitle: Text('Now: …${p.deviceKey.length > 4 ? p.deviceKey.substring(p.deviceKey.length - 4) : ''}'), onTap: locked ? null : _changeKey),
        ListTile(
          leading: const Icon(Icons.shield_outlined),
          title: const Text('Turn protection off'),
          subtitle: const Text('Needed before the app can be removed'),
          enabled: !locked,
          onTap: locked ? null : () async {
            final ok = FleetDemo.on || (await _native.invokeMethod<bool>('adminRemove') ?? false);
            setState(() => _msg = ok ? 'Protection is off.' : 'Could not turn it off.');
          },
        ),
        const SizedBox(height: 12),
        const Text('VIP Settings $kAppVersion · M7 NEXUS', textAlign: TextAlign.center, style: TextStyle(color: FleetColors.muted)),
      ]),
    );
  }
}
