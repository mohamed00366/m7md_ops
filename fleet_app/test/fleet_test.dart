import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vip_fleet/core/auth.dart';
import 'package:vip_fleet/core/report.dart';
import 'package:vip_fleet/core/rta.dart';
import 'package:vip_fleet/core/store.dart';
import 'package:vip_fleet/core/sync.dart';

const confirm = 'Plate-DXB CC 57843\nINV-971242636\nValid-317AP,C,D,CP,DP\nFee-AED6.30\ninc.Vat-5%\nTnxFee-AED0.30\nExp-14/10/26 09:39AM';

void main() {
  test('RTA confirmation (real format)', () {
    final r = parseRtaIn(confirm);
    expect(r.kind, 'confirm');
    expect(r.emirate, 'DXB');
    expect(r.plate, 'CC57843');
    expect(r.inv, '971242636');
    expect(r.zone, '317AP');
    expect(r.fee, 6.30);
    expect(r.tnxFee, 0.30);
    expect(r.total(), closeTo(6.60, 0.001));
    expect(r.total(withTnx: false), closeTo(6.30, 0.001));
    expect(r.exp, DateTime.utc(2026, 10, 14, 5, 39)); // 09:39 Dubai
  });

  test('RTA extension, reminder, errors, free day', () {
    final e = parseRtaIn('Extension\nPlate-DXB CC 57843\nINV-1\nValid-317AP\nFee-AED4.20\nTnxFee-AED0.30\nExp-14/10/26 11:39PM\nMax-4Hrs');
    expect(e.kind, 'extension');
    expect(e.maxHours, 4);
    expect(e.exp, DateTime.utc(2026, 10, 14, 19, 39));
    final m = parseRtaIn('Reminder\nINV-971242636\nPlate-DXB CC 57843\nExp-14/10/26 09:39AM\nSend Y to extend in zone-357CP');
    expect(m.kind, 'reminder');
    expect(m.zone, '357CP');
    expect(parseRtaIn('Invalid plate details. Please check').kind, 'error');
    expect(parseRtaIn('Extension request is not allowed till 10:00AM').kind, 'error');
    expect(parseRtaIn('Parking is free today, paid parking will start on 02/01/25 08:00AM. Reply with 1').kind, 'free');
  });

  test('messages sent to 7275', () {
    RtaInfo o(String s) => parseRtaOut(s);
    expect([o('CC57843 317AP 1').plate, o('CC57843 317AP 1').zone, o('CC57843 317AP 1').hours], ['CC57843', '317AP', 1]);
    expect([o('CC 57843 129CP 2').plate, o('CC 57843 129CP 2').zone, o('CC 57843 129CP 2').hours], ['CC57843', '129CP', 2]);
    expect([o('CC 57843 129 CP').zone, o('CC 57843 129 CP').hours], ['129CP', 1]);
    expect([o('AUH13 12345 335A 1').plate, o('AUH13 12345 335A 1').zone], ['AUH1312345', '335A']);
    expect([o('CC57843 317AP1').zone, o('CC57843 317AP1').hours], ['317AP', 1]);
    expect([o('45492 375A1').plate, o('45492 375A1').zone], ['45492', '375A']);
    expect(o('Y').kind, 'extend');
    expect(o('hello').kind, 'other');
  });

  test('watched numbers', () {
    const w = Watched('7275');
    expect(w.matches('7275'), isTrue);
    expect(w.matches('+9717275'), isTrue);
    expect(w.matches('97150727512'), isFalse);
    const ph = Watched('0501234567');
    expect(ph.matches('+971501234567'), isTrue);
    expect(ph.matches('0509999999'), isFalse);
    const name = Watched('RTA');
    expect(name.matches('AD-RTA'), isTrue);
    expect(Watched.of(null).single.number, '7275');
    expect(Watched.of([{'number': '7275', 'in': true, 'out': false}]).single.outbound, isFalse);
  });

  test('login: hash only, backup works, lock after 5', () async {
    SharedPreferences.setMockInitialValues({});
    final p = await Prefs.get();
    await p.setLoginMain(FleetAuth.make('Admin', 'pass1234'));
    await p.setLoginBackup(FleetAuth.make('backup', 'bk-9999'));
    expect(p.loginMain!.contains('pass1234'), isFalse);
    expect(await FleetAuth.signIn(p, 'admin', 'pass1234'), isNull);
    expect(await FleetAuth.signIn(p, 'backup', 'bk-9999'), isNull);
    for (var i = 0; i < 4; i++) {
      expect(await FleetAuth.signIn(p, 'admin', 'x'), contains('tries left'));
    }
    expect(await FleetAuth.signIn(p, 'admin', 'x'), contains('locked'));
    expect(await FleetAuth.signIn(p, 'admin', 'pass1234'), contains('Locked'));
  });

  test('daily e-mail once a day after the hour (Dubai)', () {
    final at22 = DateTime.utc(2026, 11, 4, 18); // 22:00 Dubai
    expect(FleetSync.mailDue(at22, 23, null), isFalse);
    expect(FleetSync.mailDue(at22, 21, null), isTrue);
    expect(FleetSync.mailDue(at22, 21, DateTime.utc(2026, 11, 4, 17, 30)), isFalse);
    expect(FleetSync.mailDue(at22, 21, DateTime.utc(2026, 11, 3, 19)), isTrue);
  });

  test('Excel: four sheets, RTA row with the fee', () {
    final t = DateTime.utc(2026, 11, 4, 6);
    final bytes = FleetReport.build(sms: [
      SmsRow(hash: 'a', ts: t, direction: 'out', address: '7275', body: 'CC57843 317AP1'),
      SmsRow(hash: 'b', ts: t.add(const Duration(minutes: 1)), direction: 'in', address: '7275', body: confirm),
    ], calls: [
      CallRow(hash: 'c', ts: t, type: 'incoming', number: '0501234567', duration: 75),
    ]);
    final x = Excel.decodeBytes(bytes);
    expect(x.tables.keys, containsAll(['RTA parking', 'All SMS', 'Daily summary', 'Calls']));
    final rta = x.tables['RTA parking']!;
    expect(rta.maxRows, 3);
    expect('${rta.rows[2][2]?.value}', 'confirm');
    expect('${rta.rows[2][8]?.value}', '6.6');
    expect('${x.tables['Daily summary']!.rows[1][3]?.value}', '1');
    expect('${x.tables['Calls']!.rows[1][5]?.value}', '1:15');
  });
}
