import 'dart:convert';

import 'package:another_telephony/telephony.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vip_calls/vip_calls.dart';

import 'api.dart';
import 'demo.dart';
import 'report.dart';
import 'store.dart';
import 'update.dart';

const kAppVersion = '1.0.5';

/// A watched number from the dashboard: {"number":"7275","label":"RTA","in":true,"out":true}.
class Watched {
  const Watched(this.number, {this.label = '', this.inbound = true, this.outbound = true});
  final String number;
  final String label;
  final bool inbound;
  final bool outbound;

  static List<Watched> of(dynamic v) {
    final l = <Watched>[];
    for (final e in (v is List ? v : const [])) {
      if (e is Map && '${e['number'] ?? ''}'.trim().isNotEmpty) {
        l.add(Watched('${e['number']}'.trim(), label: '${e['label'] ?? ''}', inbound: e['in'] != false, outbound: e['out'] != false));
      }
    }
    return l.isEmpty ? const [Watched('7275', label: 'RTA parking')] : l;
  }

  /// "7275" matches "7275", "+9717275", "AD-7275"; a name (e.g. "RTA") matches the same name.
  bool matches(String address) {
    final a = address.toUpperCase().replaceAll(' ', '');
    final d = a.replaceAll(RegExp(r'\D'), '');
    final w = number.toUpperCase().replaceAll(' ', '');
    final wd = w.replaceAll(RegExp(r'\D'), '');
    if (wd.isEmpty) return a.contains(w); // a sender name
    if (d.isEmpty) return false;
    // a phone number: the last 9 digits (050 123 4567 = +971 50 123 4567)
    if (wd.length >= 9) return d.length >= 9 && d.substring(d.length - 9) == wd.substring(wd.length - 9);
    // a short code (7275): the same, or with a country code before it
    return d == wd || (d.endsWith(wd) && d.length <= wd.length + 4);
  }
}

String smsHash(String direction, int ms, String address, String body) =>
    sha1.convert(utf8.encode('$direction|$ms|$address|$body')).toString();

String callHash(int ms, String number, String type, int duration) => sha1.convert(utf8.encode('$ms|$number|$type|$duration')).toString();

/// Result of one sync (shown on the home page and in the log).
class SyncResult {
  SyncResult({this.newSms = 0, this.newCalls = 0, this.upSms = 0, this.upCalls = 0, this.error = '', this.mail = '', this.cleaned = 0});
  int newSms, newCalls, upSms, upCalls, cleaned;
  String error, mail;
  @override
  String toString() => error.isNotEmpty ? error : 'SMS +$newSms (up $upSms) · calls +$newCalls (up $upCalls)${cleaned > 0 ? ' · cleaned $cleaned old' : ''}${mail.isEmpty ? '' : ' · $mail'}';
}

/// Reads the SMS of the watched numbers and the call log, keeps them on the device, uploads what is new, writes the
/// Excel and sends the daily e-mail. Runs every 15 minutes (WorkManager), at once on a new SMS, and from the app.
class FleetSync {
  static bool _busy = false;
  static const _native = MethodChannel('vip_fleet/native');

  static Future<Map<String, dynamic>> deviceInfo() async {
    try {
      return (await _native.invokeMapMethod<String, dynamic>('info')) ?? {};
    } catch (_) {
      return {};
    }
  }

  /// What the dashboard shows about this device: permissions, protection, battery saving, waiting records, last error.
  static Future<Map<String, dynamic>> health() async {
    final h = <String, dynamic>{};
    try {
      if (FleetDemo.on) return {'sms': true, 'calls': true, 'admin': false, 'battery': true};
      h['sms'] = await Permission.sms.isGranted;
      h['calls'] = await VipCalls.granted();
      h['battery'] = await Permission.ignoreBatteryOptimizations.isGranted;
      h['owner'] = await VipDevice.owner();
      h['build'] = kAppBuild;
      try {
        h['admin'] = await _native.invokeMethod<bool>('adminActive') ?? false;
      } catch (_) {/* background: not known */}
      final (_, sw, _, kw) = await (await LocalDb.open()).counts();
      h['waiting'] = sw + kw;
      final p = await Prefs.get();
      if (p.lastError.isNotEmpty) h['error'] = p.lastError.length > 200 ? p.lastError.substring(0, 200) : p.lastError;
    } catch (_) {}
    return h;
  }

  static Future<SyncResult> run({String reason = 'manual'}) async {
    final res = SyncResult();
    if (_busy) return res..error = 'A sync is already running.';
    _busy = true;
    try {
      final p = await Prefs.get();
      await p.reload();
      if (p.deviceKey.isEmpty) return res..error = 'No device key yet.';
      // Device Owner (1.0.5): the permissions are given and removing is blocked, every run (cheap)
      if (!FleetDemo.on && await VipDevice.owner()) await VipDevice.ownerSetup();
      // 1) the switches of the dashboard (the last ones are used when off line)
      var cfg = p.config;
      try {
        cfg = await Api.pullConfig(p.deviceKey, kAppVersion, {...await deviceInfo(), 'health': await health()});
        await p.setConfig(cfg);
      } on ApiError catch (e) {
        if (e.message.contains('Unknown device key')) return res..error = 'This device key is not known (or was stopped) in the dashboard.';
      } catch (_) {/* off line */}
      if (cfg['active'] == false) return res..error = 'This device is turned off in the dashboard.';
      final watched = Watched.of(cfg['numbers']);
      final db = await LocalDb.open();
      final days = (cfg['history_days'] as num?)?.toInt() ?? 30;
      final first = DateTime.now().subtract(Duration(days: days >= 3650 ? 36500 : days)).millisecondsSinceEpoch;
      // an order from the dashboard: "Upload old data" (read the phone again from that date and send it all again)
      final cmd = cfg['command'] is Map ? (cfg['command'] as Map).cast<String, dynamic>() : null;
      final cmdAt = '${cmd?['at'] ?? ''}';
      final newCmd = cmd != null && cmdAt.isNotEmpty && cmdAt != p.lastCommand;
      if (newCmd && cmd['kind'] == 'resend') {
        final d = (cmd['days'] as num?)?.toInt() ?? 30;
        final from = d <= 0 ? 1 : DateTime.now().subtract(Duration(days: d)).millisecondsSinceEpoch;
        await p.setSmsSince(from);
        await p.setCallsSince(from);
        await db.unmarkAll();
      }

      // 2) SMS of the watched numbers
      if (cfg['log_sms'] != false && FleetDemo.on) {
        final rows = <SmsRow>[];
        for (final (dir, t, addr, body) in FleetDemo.inbox) {
          final w = watched.where((x) => x.matches(addr) && (dir == 'in' ? x.inbound : x.outbound)).firstOrNull;
          if (w == null) continue;
          rows.add(SmsRow(hash: smsHash(dir, t.millisecondsSinceEpoch, addr, body), ts: t, direction: dir, address: addr, label: w.label, sim: 'SIM 1', body: body));
        }
        res.newSms = await db.addSms(rows);
      } else if (cfg['log_sms'] != false && await Permission.sms.isGranted) {
        final since = p.smsSince > 0 ? p.smsSince : first;
        final t = Telephony.instance;
        final cols = [SmsColumn.ID, SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE, SmsColumn.SUBSCRIPTION_ID];
        final filter = SmsFilter.where(SmsColumn.DATE).greaterThan('$since');
        final rows = <SmsRow>[];
        var newest = since;
        for (final (dir, list) in [('in', await t.getInboxSms(columns: cols, filter: filter)), ('out', await t.getSentSms(columns: cols, filter: filter))]) {
          for (final m in list) {
            final addr = m.address ?? '';
            final ms = m.date ?? 0;
            if (ms > newest) newest = ms;
            final w = watched.where((x) => x.matches(addr) && (dir == 'in' ? x.inbound : x.outbound)).firstOrNull;
            if (w == null) continue;
            rows.add(SmsRow(
              hash: smsHash(dir, ms, addr, m.body ?? ''),
              ts: DateTime.fromMillisecondsSinceEpoch(ms),
              direction: dir,
              address: addr,
              label: w.label,
              sim: m.subscriptionId == null ? '' : 'SIM ${m.subscriptionId}',
              body: m.body ?? '',
            ));
          }
        }
        res.newSms = await db.addSms(rows);
        if (newest > since) await p.setSmsSince(newest);
      }

      // 3) the call log (number, type, duration – no audio)
      if (cfg['log_calls'] == true && FleetDemo.on) {
        res.newCalls = await db.addCalls([
          for (final (t, type, number, name, sec) in FleetDemo.calls)
            CallRow(hash: callHash(t.millisecondsSinceEpoch, number, type, sec), ts: t, type: type, number: number, name: name, duration: sec),
        ]);
      } else if (cfg['log_calls'] == true && await VipCalls.granted()) {
        final since = p.callsSince > 0 ? p.callsSince : first;
        final rows = <CallRow>[];
        var newest = since;
        for (final c in await VipCalls.since(since)) {
          if (c.ms > newest) newest = c.ms;
          rows.add(CallRow(hash: callHash(c.ms, c.number, c.type, c.duration), ts: DateTime.fromMillisecondsSinceEpoch(c.ms), type: c.type,
              number: c.number, name: c.name, duration: c.duration));
        }
        res.newCalls = await db.addCalls(rows);
        if (newest > since) await p.setCallsSince(newest);
      }

      // 4) upload (the dashboard switch and the device switch)
      if (cfg['upload_enabled'] != false && p.uploadOn) {
        try {
          final s = await db.sms(notUploaded: true, limit: 5000);
          for (var i = 0; i < s.length; i += 200) {
            final part = s.sublist(i, i + 200 > s.length ? s.length : i + 200);
            res.upSms += await Api.pushSms(p.deviceKey, [for (final r in part) r.toApi()]);
            await db.markSms(part.map((r) => r.hash));
          }
          if (cfg['log_calls'] == true) {
            final c = await db.calls(notUploaded: true, limit: 5000);
            for (var i = 0; i < c.length; i += 200) {
              final part = c.sublist(i, i + 200 > c.length ? c.length : i + 200);
              res.upCalls += await Api.pushCalls(p.deviceKey, [for (final r in part) r.toApi()]);
              await db.markCalls(part.map((r) => r.hash));
            }
          }
        } catch (e) {
          res.error = 'Upload later (no internet?): $e';
        }
      }

      // 4b) clean-up (1.0.5, set per device in the dashboard): uploaded records older than N days leave the device, once a day
      final cl = cfg['cleanup'] is Map ? (cfg['cleanup'] as Map) : const {};
      final lastCl = p.lastCleanup;
      if (cl['on'] == true && (lastCl == null || DateTime.now().difference(lastCl).inHours >= 20)) {
        try {
          final n = await db.cleanup(((cl['days'] as num?)?.toInt() ?? 90).clamp(7, 3650));
          await p.setLastCleanup(DateTime.now());
          if (n > 0) res.cleaned = n;
        } catch (e) {
          debugPrint('cleanup: $e');
        }
      }

      // 5) Excel on the device + the daily e-mail
      final name = '${cfg['name'] ?? 'device'}';
      if (!FleetDemo.on && p.excelOn && (res.newSms > 0 || res.newCalls > 0 || reason == 'manual')) {
        try {
          await FleetReport.write(name, withCalls: cfg['log_calls'] == true);
        } catch (e) {
          debugPrint('excel: $e');
        }
      }
      if (p.emailOn && mailDue(DateTime.now(), p.mailHour, p.lastMail)) {
        // DB 342: the device chosen in the dashboard also sends the company RTA summary of the day
        var extra = '';
        if (!FleetDemo.on) {
          try {
            final s = await Api.call('vip_daily_summary', {'p_key': p.deviceKey});
            if (s['mine'] == true) extra = '${s['text'] ?? ''}'.trim();
          } catch (_) {/* old database or off line: the e-mail goes without it */}
        }
        final e = FleetDemo.on ? null : await FleetReport.mail(p, name, withCalls: cfg['log_calls'] == true, extra: extra);
        res.mail = e == null ? 'e-mail sent' : 'e-mail: $e';
      }
      if (newCmd) {
        final release = cmd['kind'] == 'owner_release';
        final released = release && await VipDevice.ownerRelease();
        final done = release
            ? (released ? 'Device Owner released: the app can be removed normally now.' : 'Could not release Device Owner.')
            : cmd['kind'] == 'resend'
            ? 'Read again from ${(cmd['days'] as num?)?.toInt() == 0 ? 'the start' : '${cmd['days']} days'}: ${res.newSms} new SMS, ${res.upSms} sent, ${res.upCalls} calls sent${res.error.isEmpty ? '' : ' · ${res.error}'}'
            : 'Synced: ${res.upSms} SMS, ${res.upCalls} calls sent${res.error.isEmpty ? '' : ' · ${res.error}'}';
        try {
          await Api.call('vip_command_done', {'p_key': p.deviceKey, 'p_at': cmdAt, 'p_result': done});
          await p.setLastCommand(cmdAt);
        } catch (_) {/* told at the next sync */}
      }
      await p.setLastSync(DateTime.now());
      await p.setLastError(res.error);
      // 6) a newer version from the dashboard: a Device Owner installs it by itself (others see "Update" on the screen)
      final up = AppUpdate.of(cfg);
      if (up != null && !FleetDemo.on && reason != 'manual' && reason != 'open') {
        final m = await FleetUpdater.silent(p, up);
        if (m != null) res.mail = res.mail.isEmpty ? m : '${res.mail} · $m';
      }
      return res;
    } catch (e) {
      res.error = '$e';
      try {
        (await Prefs.get()).setLastError(res.error);
      } catch (_) {}
      return res;
    } finally {
      _busy = false;
    }
  }

  /// Once a day, after [hour] (Dubai time).
  static bool mailDue(DateTime now, int hour, DateTime? last) {
    final d = dubai(now);
    if (d.hour < hour) return false;
    if (last == null) return true;
    final l = dubai(last);
    return !(l.year == d.year && l.month == d.month && l.day == d.day);
  }
}
