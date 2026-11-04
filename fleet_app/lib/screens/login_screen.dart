import 'package:flutter/material.dart';

import '../core/auth.dart';
import '../core/store.dart';
import '../main.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _u = TextEditingController();
  final _p = TextEditingController();
  String _error = '';

  Future<void> _go() async {
    final e = await FleetAuth.signIn(await Prefs.get(), _u.text, _p.text);
    if (!mounted) return;
    if (e != null) return setState(() => _error = e);
    Navigator.of(context).pushReplacementNamed('/home');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(24), children: [
              const Icon(Icons.shield_outlined, size: 64, color: FleetColors.gold),
              const SizedBox(height: 8),
              const Text('VIP Fleet', textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
              const Text('Company device', textAlign: TextAlign.center, style: TextStyle(color: FleetColors.muted)),
              const SizedBox(height: 24),
              TextField(controller: _u, decoration: const InputDecoration(labelText: 'User')),
              const SizedBox(height: 10),
              TextField(controller: _p, obscureText: true, decoration: const InputDecoration(labelText: 'Password'), onSubmitted: (_) => _go()),
              if (_error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error, style: const TextStyle(color: FleetColors.bad, fontWeight: FontWeight.w700))),
              const SizedBox(height: 16),
              FilledButton(onPressed: _go, child: const Text('Sign in')),
            ]),
          ),
        ),
      ),
    );
  }
}
