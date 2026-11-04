import 'package:flutter/foundation.dart';

import 'api.dart';
import 'store.dart';

/// Web preview: the app runs with sample data – no SMS, no call log, no server. A "Dashboard (demo)" panel on the
/// home page plays the dashboard switches and makes new RTA messages arrive.
class FleetDemo {
  static bool get on => kIsWeb;

  static const key = 'VF-DEMO0000000000000000000';

  /// The dashboard switches of the demo device.
  static final Map<String, dynamic> config = {
    'ok': true,
    'id': 'demo',
    'name': 'Chaplin tablet',
    'point': 'Chaplin/Juns/Loona',
    'log_sms': true,
    'log_calls': true,
    'upload_enabled': true,
    'active': true,
    'history_days': 30,
    'numbers': [
      {'number': '7275', 'label': 'RTA parking', 'in': true, 'out': true},
    ],
  };

  /// Messages waiting in the "phone" (read at the next sync).
  static final List<(String, DateTime, String, String)> inbox = []; // direction, time, address, body
  static final List<(DateTime, String, String, String, int)> calls = []; // time, type, number, name, seconds
  static int uploadedSms = 0, uploadedCalls = 0;
  static int _plate = 57843;

  static void start() {
    LocalDb.memory = true;
    Api.transport = (fn, args) async {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      // any key "VF-…" is accepted in the preview
      if (!'${args['p_key']}'.trim().toUpperCase().startsWith('VF-')) return {'ok': false, 'error': 'Unknown device key.'};
      switch (fn) {
        case 'vip_pull_config':
          return {...config, 'server_time': DateTime.now().toUtc().toIso8601String()};
        case 'vip_push_sms':
          final n = (args['p_rows'] as List).length;
          if (config['active'] == false || config['upload_enabled'] == false) return {'ok': true, 'added': 0, 'off': true};
          uploadedSms += n;
          return {'ok': true, 'added': n};
        case 'vip_push_calls':
          final n = (args['p_rows'] as List).length;
          if (config['active'] == false || config['upload_enabled'] == false) return {'ok': true, 'added': 0, 'off': true};
          uploadedCalls += n;
          return {'ok': true, 'added': n};
      }
      return {'ok': true};
    };
    if (inbox.isEmpty) _history();
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
  static String _exp(DateTime t) {
    final d = t.toUtc().add(const Duration(hours: 4));
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '${_two(d.day)}/${_two(d.month)}/${d.year % 100} ${_two(h)}:${_two(d.minute)}${d.hour < 12 ? 'AM' : 'PM'}';
  }

  static String confirmation(String plate, DateTime exp, {bool extension = false, double fee = 6.30}) =>
      '${extension ? 'Extension\n' : ''}Plate-DXB ${plate.substring(0, 2)} ${plate.substring(2)}\nINV-9712${DateTime.now().millisecondsSinceEpoch % 100000}\n'
      'Valid-317AP,C,D,CP,DP\nFee-AED${fee.toStringAsFixed(2)}\ninc.Vat-5%\nTnxFee-AED0.30\nExp-${_exp(exp)}${extension ? '\nMax-4Hrs' : ''}';

  static void _history() {
    final now = DateTime.now();
    for (final (i, p) in ['CC57843', 'AB12045', 'DC90311'].indexed) {
      final t = now.subtract(Duration(hours: 5 - i * 2));
      inbox.add(('out', t, '7275', '$p 317AP1'));
      inbox.add(('in', t.add(const Duration(seconds: 20)), '7275', confirmation(p, t.add(const Duration(hours: 1)))));
    }
    inbox.add(('in', now.subtract(const Duration(minutes: 70)), '7275', 'Invalid plate details. Please check the plate and try again'));
    calls.add((now.subtract(const Duration(hours: 3)), 'incoming', '+971501234567', 'GM', 135));
    calls.add((now.subtract(const Duration(hours: 2)), 'missed', '+971559876543', '', 0));
    calls.add((now.subtract(const Duration(minutes: 40)), 'outgoing', '8009090', 'RTA', 312));
  }

  /// A new RTA payment + its confirmation (or a reminder / error).
  static void newRta(String kind) {
    final now = DateTime.now();
    final plate = 'CC${_plate++}';
    switch (kind) {
      case 'pay':
        inbox.add(('out', now, '7275', '$plate 317AP1'));
        inbox.add(('in', now.add(const Duration(seconds: 15)), '7275', confirmation(plate, now.add(const Duration(hours: 1)))));
      case 'reminder':
        inbox.add(('in', now, '7275', 'Reminder\nINV-971242636\nPlate-DXB CC 57843\nExp-${_exp(now.add(const Duration(minutes: 10)))}\nSend Y to extend in zone-357CP'));
      case 'extension':
        inbox.add(('out', now, '7275', 'Y'));
        inbox.add(('in', now.add(const Duration(seconds: 15)), '7275', confirmation('CC57843', now.add(const Duration(hours: 1)), extension: true, fee: 4.20)));
      case 'error':
        inbox.add(('out', now, '7275', '$plate 999ZZ1'));
        inbox.add(('in', now.add(const Duration(seconds: 15)), '7275', 'Invalid plate details. Please check the plate and try again'));
      case 'other':
        inbox.add(('in', now, '+971501234567', 'This number is not watched – it is not recorded'));
      case 'call':
        calls.add((now, 'incoming', '+971501234567', 'GM', 48));
    }
  }
}
