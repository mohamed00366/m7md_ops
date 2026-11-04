import 'dart:io';

import 'package:excel/excel.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:path_provider/path_provider.dart';

import 'rta.dart';
import 'store.dart';

/// Dubai time (UTC+4, no summer time) – the Excel shows the local time of the company.
DateTime dubai(DateTime t) => t.toUtc().add(const Duration(hours: 4));

String _two(int v) => v.toString().padLeft(2, '0');
String fmtDt(DateTime t) {
  final d = dubai(t);
  return '${_two(d.day)}/${_two(d.month)}/${d.year} ${_two(d.hour)}:${_two(d.minute)}';
}

String fmtDay(DateTime t) {
  final d = dubai(t);
  return '${d.year}-${_two(d.month)}-${_two(d.day)}';
}

/// The cumulative Excel of the device: RTA parking · All SMS · Daily summary · Calls (every record kept on the device).
class FleetReport {
  static Future<File> file(String deviceName) async {
    final dir = await getApplicationDocumentsDirectory();
    final safe = deviceName.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    return File('${dir.path}/VIP-Fleet-${safe.isEmpty ? 'device' : safe}.xlsx');
  }

  static CellValue _t(String v) => TextCellValue(v);
  static CellValue? _n(num? v) => v == null ? null : DoubleCellValue(v.toDouble());

  /// Builds the workbook from the records (pure – tested).
  static List<int> build({required List<SmsRow> sms, required List<CallRow> calls, bool feeWithTnx = true, bool withCalls = true}) {
    final x = Excel.createExcel();
    final first = x.getDefaultSheet() ?? 'Sheet1';
    x.rename(first, 'RTA parking');
    final rta = x['RTA parking'];
    rta.appendRow([
      for (final h in ['Time (Dubai)', 'Direction', 'Kind', 'Plate', 'Zone', 'Hours', 'Fee AED', 'Tnx fee AED', 'Total AED', 'Expires', 'Invoice', 'SIM', 'Message']) _t(h),
    ]);
    final all = x['All SMS'];
    all.appendRow([for (final h in ['Time (Dubai)', 'Direction', 'Number', 'Label', 'SIM', 'Message', 'Uploaded']) _t(h)]);
    final daily = <String, List<num>>{}; // day → [out, in, confirmed, amount]
    final asc = [...sms]..sort((a, b) => a.ts.compareTo(b.ts));
    for (final s in asc) {
      all.appendRow([_t(fmtDt(s.ts)), _t(s.direction == 'out' ? 'Sent' : 'Received'), _t(s.address), _t(s.label), _t(s.sim), _t(s.body), _t(s.uploaded ? 'Yes' : 'No')]);
      final d = daily.putIfAbsent(fmtDay(s.ts), () => [0, 0, 0, 0]);
      d[s.direction == 'out' ? 0 : 1] += 1;
      if (!isRtaNumber(s.address)) continue;
      final r = s.direction == 'out' ? parseRtaOut(s.body) : parseRtaIn(s.body);
      if (r.confirmed) {
        d[2] += 1;
        d[3] += r.total(withTnx: feeWithTnx);
      }
      rta.appendRow([
        _t(fmtDt(s.ts)),
        _t(s.direction == 'out' ? 'Sent' : 'Received'),
        _t(r.kind),
        _t(r.plate),
        _t(r.zone),
        _n(r.hours ?? r.maxHours),
        _n(r.fee),
        _n(r.tnxFee),
        r.confirmed ? _n(r.total(withTnx: feeWithTnx)) : null,
        _t(r.exp == null ? '' : fmtDt(r.exp!)),
        _t(r.inv),
        _t(s.sim),
        _t(s.body),
      ]);
    }
    final sum = x['Daily summary'];
    sum.appendRow([for (final h in ['Day', 'SMS sent', 'SMS received', 'RTA confirmed', 'RTA amount AED']) _t(h)]);
    for (final e in (daily.entries.toList()..sort((a, b) => b.key.compareTo(a.key)))) {
      sum.appendRow([_t(e.key), _n(e.value[0]), _n(e.value[1]), _n(e.value[2]), _n(double.parse(e.value[3].toStringAsFixed(2)))]);
    }
    if (withCalls) {
      final c = x['Calls'];
      c.appendRow([for (final h in ['Time (Dubai)', 'Type', 'Number', 'Name', 'Duration (s)', 'Duration']) _t(h)]);
      for (final k in ([...calls]..sort((a, b) => a.ts.compareTo(b.ts)))) {
        c.appendRow([_t(fmtDt(k.ts)), _t(k.type), _t(k.number), _t(k.name), _n(k.duration), _t('${k.duration ~/ 60}:${_two(k.duration % 60)}')]);
      }
    }
    return x.encode() ?? const [];
  }

  /// Writes the Excel of all the records on the device.
  static Future<File> write(String deviceName, {bool withCalls = true}) async {
    final db = await LocalDb.open();
    final bytes = build(sms: await db.sms(), calls: await db.calls(), withCalls: withCalls);
    final f = await file(deviceName);
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  /// Sends the Excel by e-mail (SMTP; Gmail needs an App Password of 16 letters). Returns null or the error.
  static Future<String?> mail(Prefs p, String deviceName, {bool withCalls = true, String extra = ''}) async {
    if (p.smtpUser.isEmpty || p.smtpPass.isEmpty || p.mailTo.isEmpty) return 'E-mail is not set (user, app password, to).';
    final f = await write(deviceName, withCalls: withCalls);
    final server = SmtpServer(p.smtpHost, port: p.smtpPort, ssl: p.smtpPort == 465, username: p.smtpUser, password: p.smtpPass);
    final now = DateTime.now();
    final msg = Message()
      ..from = Address(p.smtpUser, 'VIP Settings')
      ..recipients.addAll(p.mailTo.split(RegExp(r'[,; ]+')).where((e) => e.contains('@')))
      ..subject = 'VIP Settings · $deviceName · ${fmtDay(now)}'
      ..text = '${extra.isEmpty ? '' : '$extra\n\n'}Daily SMS / calls of $deviceName (all records kept on the device). Sent by VIP Settings.'
      ..attachments = [FileAttachment(f)];
    try {
      await send(msg, server, timeout: const Duration(seconds: 60));
      await p.setLastMail(now);
      return null;
    } on MailerException catch (e) {
      final t = e.problems.map((x) => '${x.code}: ${x.msg}').join('; ');
      return t.contains('535') ? 'The e-mail password was refused (535). Gmail needs an App Password (16 letters) with 2-Step Verification.' : (t.isEmpty ? e.message : t);
    } catch (e) {
      return '$e';
    }
  }
}
