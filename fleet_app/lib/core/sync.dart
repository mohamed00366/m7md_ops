import 'dart:convert';

import 'package:another_telephony/telephony.dart';
import 'package:call_log/call_log.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'api.dart';
import 'demo.dart';
import 'report.dart';
import 'store.dart';

const kAppVersion = '1.0.0';

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
  SyncResult({this.newSms = 0, this.newCalls = 0, this.upSms = 0, this.upCalls = 0, this.error = '', this.mail = ''});
  int newSms, newCalls, upSms, upCalls;
  String error, mail;
  @override
  String toString() => error.isNotEmpty ? error : 'SMS +$newSms (up $upSms) · calls +$newCalls (up $upCalls)${mail.isEmpty ? '' : ' · $mail'}';
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

  static Future<SyncResult> run({String reason = 'manual'}) async {
    final res = SyncResult();
    if (_busy) return res..error = 'A sync is already running.';
    _busy = true;
    try {
      final p = await Prefs.get();
      await p.reload();
      if (p.deviceKey.isEmpty) return res..error = 'No device key yet.';
      // 1) the switches of the dashboard (the last ones are used when off line)
      var cfg = p.config;
      try {
        cfg = await Api.pullConfig(p.deviceKey, kAppVersion, await deviceInfo());
        await p.setConfig(cfg);
      } on ApiError catch (e) {
        if (e.message.contains('Unknown device key')) return res..error = 'This device key is not known (or was stopped) in the dashboard.';
      } catch (_) {/* off line */}
      if (cfg['active'] == false) return res..error = 'This device is turned off in the dashboard.';
      final watched = Watched.of(cfg['numbers']);
      final db = await LocalDb.open();
      final days = (cfg['history_days'] as num?)?.toInt() ?? 30;
      final first = DateTime.now().subtract(Duration(days: days >= 3650 ? 36500 : days)).millisecondsSinceEpoch;

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
      } else if (cfg['log_calls'] == true && await Permission.phone.isGranted) {
        final since = p.callsSince > 0 ? p.callsSince : first;
        final rows = <CallRow>[];
        var newest = since;
        for (final c in await CallLog.query(dateFrom: since + 1)) {
          final ms = c.timestamp ?? 0;
          if (ms > newest) newest = ms;
          final type = switch (c.callType) {
            CallType.incoming => 'incoming',
            CallType.outgoing => 'outgoing',
            CallType.missed => 'missed',
            CallType.rejected => 'rejected',
            CallType.blocked => 'blocked',
            _ => 'other',
          };
          rows.add(CallRow(hash: callHash(ms, c.number ?? '', type, c.duration ?? 0), ts: DateTime.fromMillisecondsSinceEpoch(ms), type: type,
              number: c.number ?? '', name: c.name ?? '', duration: c.duration ?? 0));
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
        final e = FleetDemo.on ? null : await FleetReport.mail(p, name, withCalls: cfg['log_calls'] == true);
        res.mail = e == null ? 'e-mail sent' : 'e-mail: $e';
      }
      await p.setLastSync(DateTime.now());
      await p.setLastError(res.error);
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
