import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

/// Settings kept on the device (SharedPreferences). The device key and the SMTP password stay on the device only.
class Prefs {
  Prefs._(this._p);
  final SharedPreferences _p;
  static Prefs? _i;

  static Future<Prefs> get() async => _i ??= Prefs._(await SharedPreferences.getInstance());

  /// Fresh values written by another isolate (background sync).
  Future<void> reload() => _p.reload();

  String get deviceKey => _p.getString('device_key') ?? '';
  Future<void> setDeviceKey(String v) => _p.setString('device_key', v.trim());

  /// Last config from the server (vip_pull_config).
  Map<String, dynamic> get config {
    try {
      return (jsonDecode(_p.getString('config') ?? '{}') as Map).cast<String, dynamic>();
    } catch (_) {
      return {};
    }
  }

  Future<void> setConfig(Map<String, dynamic> v) => _p.setString('config', jsonEncode(v));

  // last read positions (ms since epoch)
  int get smsSince => _p.getInt('sms_since') ?? 0;
  Future<void> setSmsSince(int v) => _p.setInt('sms_since', v);
  int get callsSince => _p.getInt('calls_since') ?? 0;
  Future<void> setCallsSince(int v) => _p.setInt('calls_since', v);

  DateTime? get lastSync => _t('last_sync');
  Future<void> setLastSync(DateTime v) => _p.setString('last_sync', v.toIso8601String());
  String get lastError => _p.getString('last_error') ?? '';
  Future<void> setLastError(String v) => _p.setString('last_error', v);

  DateTime? _t(String k) => DateTime.tryParse(_p.getString(k) ?? '');

  // ---------------------------------------------------------------- login (hash only)
  String? get loginMain => _p.getString('login_main'); // "user|salt|sha256"
  String? get loginBackup => _p.getString('login_backup');
  Future<void> setLoginMain(String v) => _p.setString('login_main', v);
  Future<void> setLoginBackup(String v) => _p.setString('login_backup', v);
  int get failCount => _p.getInt('fail_count') ?? 0;
  Future<void> setFailCount(int v) => _p.setInt('fail_count', v);
  DateTime? get lockedUntil => _t('locked_until');
  Future<void> setLockedUntil(DateTime? v) => v == null ? _p.remove('locked_until') : _p.setString('locked_until', v.toIso8601String());

  // ---------------------------------------------------------------- Excel / email options (on the device)
  bool get excelOn => _p.getBool('excel_on') ?? true;
  Future<void> setExcelOn(bool v) => _p.setBool('excel_on', v);
  bool get uploadOn => _p.getBool('upload_on') ?? true; // the device side of "upload" (the dashboard has its own switch)
  Future<void> setUploadOn(bool v) => _p.setBool('upload_on', v);

  bool get emailOn => _p.getBool('email_on') ?? false;
  Future<void> setEmailOn(bool v) => _p.setBool('email_on', v);
  String get smtpHost => _p.getString('smtp_host') ?? 'smtp.gmail.com';
  int get smtpPort => _p.getInt('smtp_port') ?? 587;
  String get smtpUser => _p.getString('smtp_user') ?? '';
  String get smtpPass => _p.getString('smtp_pass') ?? '';
  String get mailTo => _p.getString('mail_to') ?? '';
  int get mailHour => _p.getInt('mail_hour') ?? 23;
  DateTime? get lastMail => _t('last_mail');
  Future<void> setLastMail(DateTime v) => _p.setString('last_mail', v.toIso8601String());
  Future<void> setMail({required String host, required int port, required String user, required String pass, required String to, required int hour}) async {
    await _p.setString('smtp_host', host.trim());
    await _p.setInt('smtp_port', port);
    await _p.setString('smtp_user', user.trim());
    await _p.setString('smtp_pass', pass.replaceAll(' ', ''));
    await _p.setString('mail_to', to.trim());
    await _p.setInt('mail_hour', hour);
  }
}

/// One SMS kept on the device.
class SmsRow {
  SmsRow({required this.hash, required this.ts, required this.direction, required this.address, this.label = '', this.sim = '', required this.body, this.uploaded = false});
  final String hash;
  final DateTime ts;
  final String direction; // in / out
  final String address;
  final String label;
  final String sim;
  final String body;
  final bool uploaded;

  Map<String, Object?> toDb() => {
        'hash': hash, 'ts': ts.millisecondsSinceEpoch, 'direction': direction, 'address': address, 'label': label, 'sim': sim, 'body': body,
        'uploaded': uploaded ? 1 : 0,
      };

  factory SmsRow.fromDb(Map<String, Object?> r) => SmsRow(
        hash: r['hash'] as String,
        ts: DateTime.fromMillisecondsSinceEpoch(r['ts'] as int),
        direction: r['direction'] as String,
        address: (r['address'] ?? '') as String,
        label: (r['label'] ?? '') as String,
        sim: (r['sim'] ?? '') as String,
        body: (r['body'] ?? '') as String,
        uploaded: r['uploaded'] == 1,
      );

  Map<String, dynamic> toApi() => {
        'hash': hash, 'ts': ts.toUtc().toIso8601String(), 'direction': direction, 'address': address, 'label': label, 'sim': sim, 'body': body,
      };
}

/// One call kept on the device (no audio).
class CallRow {
  CallRow({required this.hash, required this.ts, required this.type, required this.number, this.name = '', this.duration = 0, this.uploaded = false});
  final String hash;
  final DateTime ts;
  final String type;
  final String number;
  final String name;
  final int duration;
  final bool uploaded;

  Map<String, Object?> toDb() =>
      {'hash': hash, 'ts': ts.millisecondsSinceEpoch, 'type': type, 'number': number, 'name': name, 'duration': duration, 'uploaded': uploaded ? 1 : 0};

  factory CallRow.fromDb(Map<String, Object?> r) => CallRow(
        hash: r['hash'] as String,
        ts: DateTime.fromMillisecondsSinceEpoch(r['ts'] as int),
        type: (r['type'] ?? '') as String,
        number: (r['number'] ?? '') as String,
        name: (r['name'] ?? '') as String,
        duration: (r['duration'] ?? 0) as int,
        uploaded: r['uploaded'] == 1,
      );

  Map<String, dynamic> toApi() =>
      {'hash': hash, 'ts': ts.toUtc().toIso8601String(), 'type': type, 'number': number, 'name': name, 'duration_sec': duration};
}

/// The records kept on the device (sqflite): what was read, and whether it reached the server.
class LocalDb {
  LocalDb._(this.db);
  final Database db;
  static LocalDb? _i;

  static Future<LocalDb> open() async {
    if (_i != null) return _i!;
    final path = p.join(await getDatabasesPath(), 'vip_fleet.db');
    final db = await openDatabase(path, version: 1, onCreate: (db, v) async {
      await db.execute('create table sms (hash text primary key, ts integer, direction text, address text, label text, sim text, body text, uploaded integer default 0)');
      await db.execute('create index sms_ts on sms (ts)');
      await db.execute('create table calls (hash text primary key, ts integer, type text, number text, name text, duration integer, uploaded integer default 0)');
      await db.execute('create index calls_ts on calls (ts)');
    });
    return _i = LocalDb._(db);
  }

  /// Adds new rows (same hash = kept once); returns how many were new.
  Future<int> addSms(List<SmsRow> rows) async {
    var n = 0;
    final b = db.batch();
    for (final r in rows) {
      b.insert('sms', r.toDb(), conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    for (final x in await b.commit()) {
      if (x is int && x > 0) n++;
    }
    return n;
  }

  Future<int> addCalls(List<CallRow> rows) async {
    var n = 0;
    final b = db.batch();
    for (final r in rows) {
      b.insert('calls', r.toDb(), conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    for (final x in await b.commit()) {
      if (x is int && x > 0) n++;
    }
    return n;
  }

  Future<List<SmsRow>> sms({bool notUploaded = false, int limit = 100000, DateTime? since}) async => [
        for (final r in await db.query('sms',
            where: [if (notUploaded) 'uploaded = 0', if (since != null) 'ts >= ${since.millisecondsSinceEpoch}'].join(' and ').ifEmptyNull,
            orderBy: 'ts desc', limit: limit))
          SmsRow.fromDb(r),
      ];

  Future<List<CallRow>> calls({bool notUploaded = false, int limit = 100000, DateTime? since}) async => [
        for (final r in await db.query('calls',
            where: [if (notUploaded) 'uploaded = 0', if (since != null) 'ts >= ${since.millisecondsSinceEpoch}'].join(' and ').ifEmptyNull,
            orderBy: 'ts desc', limit: limit))
          CallRow.fromDb(r),
      ];

  Future<void> markSms(Iterable<String> hashes) async {
    final b = db.batch();
    for (final h in hashes) {
      b.update('sms', {'uploaded': 1}, where: 'hash = ?', whereArgs: [h]);
    }
    await b.commit(noResult: true);
  }

  Future<void> markCalls(Iterable<String> hashes) async {
    final b = db.batch();
    for (final h in hashes) {
      b.update('calls', {'uploaded': 1}, where: 'hash = ?', whereArgs: [h]);
    }
    await b.commit(noResult: true);
  }

  Future<(int, int, int, int)> counts() async {
    final s = Sqflite.firstIntValue(await db.rawQuery('select count(*) from sms')) ?? 0;
    final sw = Sqflite.firstIntValue(await db.rawQuery('select count(*) from sms where uploaded = 0')) ?? 0;
    final k = Sqflite.firstIntValue(await db.rawQuery('select count(*) from calls')) ?? 0;
    final kw = Sqflite.firstIntValue(await db.rawQuery('select count(*) from calls where uploaded = 0')) ?? 0;
    return (s, sw, k, kw);
  }
}

extension on String {
  String? get ifEmptyNull => isEmpty ? null : this;
}
