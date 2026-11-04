import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/auth.dart';
import '../core/store.dart';
import '../core/sync.dart';
import '../main.dart';

/// First start: the device key from the dashboard (Company devices ▸ New device), then the main and the backup login.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _key = TextEditingController();
  final _u1 = TextEditingController(text: 'admin');
  final _p1 = TextEditingController();
  final _u2 = TextEditingController(text: 'backup');
  final _p2 = TextEditingController();
  String _error = '';
  bool _busy = false;

  Future<void> _save() async {
    final key = _key.text.trim().toUpperCase();
    if (!key.startsWith('VF-') || key.length < 10) return setState(() => _error = 'Enter the device key from the dashboard (VF-…).');
    if (_u1.text.trim().isEmpty || _p1.text.length < 4) return setState(() => _error = 'Main login: a user and a password (4+ letters).');
    if (_u2.text.trim().isEmpty || _p2.text.length < 4) return setState(() => _error = 'Backup login: a user and a password (4+ letters).');
    if (_u1.text.trim().toLowerCase() == _u2.text.trim().toLowerCase()) return setState(() => _error = 'The backup user must be different.');
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final cfg = await Api.pullConfig(key, kAppVersion, await FleetSync.deviceInfo());
      final p = await Prefs.get();
      await p.setDeviceKey(key);
      await p.setConfig(cfg);
      await p.setLoginMain(FleetAuth.make(_u1.text, _p1.text));
      await p.setLoginBackup(FleetAuth.make(_u2.text, _p2.text));
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/home');
    } catch (e) {
      setState(() => _error = e is ApiError ? e.message : 'No connection to the server: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget field(TextEditingController c, String label, {bool pw = false, String? hint}) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(controller: c, obscureText: pw, decoration: InputDecoration(labelText: label, hintText: hint)),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('VIP Settings · set up')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const Icon(Icons.shield_outlined, size: 56, color: FleetColors.gold),
        const SizedBox(height: 8),
        const Text('Company device logger', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const Text('SMS of the watched numbers (RTA 7275) and the call log go to the M7MD dashboard.',
            textAlign: TextAlign.center, style: TextStyle(color: FleetColors.muted)),
        const SizedBox(height: 20),
        field(_key, 'Device key', hint: 'VF-…  (dashboard ▸ Company devices ▸ New device)'),
        const Divider(height: 28),
        const Text('Main login', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        field(_u1, 'User'),
        field(_p1, 'Password', pw: true),
        const Text('Backup login', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        field(_u2, 'User'),
        field(_p2, 'Password', pw: true),
        if (_error.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(_error, style: const TextStyle(color: FleetColors.bad, fontWeight: FontWeight.w700))),
        FilledButton.icon(
          onPressed: _busy ? null : _save,
          icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
          label: const Text('Connect this device'),
        ),
      ]),
    );
  }
}
