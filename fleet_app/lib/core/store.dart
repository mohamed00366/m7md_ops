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

  /// The last dashboard order done (its time).
  String get lastCommand => _p.getString('last_command') ?? '';
  Future<void> setLastCommand(String v) => _p.setString('last_command', v);

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
  // 1.0.5: the clean-up once a day; the last update tried in the background (build, time)
  DateTime? get lastCleanup => _t('last_cleanup');
  Future<void> setLastCleanup(DateTime v) => _p.setString('last_cleanup', v.toIso8601String());
  // 1.0.6: the persistent foreground service ("keep running"); default on
  bool get keepAlive => _p.getBool('keep_alive') ?? true;
  Future<void> setKeepAlive(bool v) => _p.setBool('keep_alive', v);
  // the dashboard "view only" flag, cached from the last config (so the UI locks even off line)
  bool get locked => _p.getBool('cfg_locked') ?? false;
  Future<void> setLocked(bool v) => _p.setBool('cfg_locked', v);
  // 1.0.7: difference between the device clock and the server (seconds); big value = the tablet clock is wrong
  int get clockSkewSec => _p.getInt('clock_skew') ?? 0;
  Future<void> setClockSkew(int v) => _p.setInt('clock_skew', v);

  int get updateTriedBuild => _p.getInt('update_tried_build') ?? 0;
  DateTime? get updateTriedAt => _t('update_tried_at');
  Future<void> setUpdateTried(int build) async {
    await _p.setInt('update_tried_build', build);
    await _p.setString('update_tried_at', DateTime.now().toIso8601String());
  }

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
/// [memory] (web preview / tests): the same, kept in memory.
class LocalDb {
  LocalDb._(this.db);
  final Database? db;
  static LocalDb? _i;

  /// Keep the records in memory (web preview, tests).
  static bool memory = false;
  final Map<String, Map<String, Object?>> _sms = {};
  final Map<String, Map<String, Object?>> _calls = {};

  static Future<LocalDb> open() async {
    if (_i != null) return _i!;
    if (memory) return _i = LocalDb._(null);
    final path = p.join(await getDatabasesPath(), 'vip_fleet.db');
    final db = await openDatabase(path, version: 1, onCreate: (db, v) async {
      await db.execute('create table sms (hash text primary key, ts integer, direction text, address text, label text, sim text, body text, uploaded integer default 0)');
      await db.execute('create index sms_ts on sms (ts)');
      await db.execute('create table calls (hash text primary key, ts integer, type text, number text, name text, duration integer, uploaded integer default 0)');
      await db.execute('create index calls_ts on calls (ts)');
    });
    return _i = LocalDb._(db);
  }

  Future<int> _add(String table, Map<String, Map<String, Object?>> mem, List<Map<String, Object?>> rows) async {
    var n = 0;
    final b = db!.batch();
    for (final r in rows) {
      b.insert(table, r, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    for (final x in await b.commit()) {
      if (x is int && x > 0) n++;
    }
    return n;
  }

  /// Adds new rows (same hash = kept once); returns how many were new.
  Future<int> addSms(List<SmsRow> rows) async {
    if (db == null) {
      var n = 0;
      for (final r in rows) {
        if (!_sms.containsKey(r.hash)) {
          _sms[r.hash] = r.toDb();
          n++;
        }
      }
      return n;
    }
    return _add('sms', _sms, [for (final r in rows) r.toDb()]);
  }

  Future<int> addCalls(List<CallRow> rows) async {
    if (db == null) {
      var n = 0;
      for (final r in rows) {
        if (!_calls.containsKey(r.hash)) {
          _calls[r.hash] = r.toDb();
          n++;
        }
      }
      return n;
    }
    return _add('calls', _calls, [for (final r in rows) r.toDb()]);
  }

  Future<List<Map<String, Object?>>> _query(String table, Map<String, Map<String, Object?>> mem, bool notUploaded, int limit, DateTime? since) async {
    final d = db;
    if (d == null) {
      final l = mem.values
          .where((r) => (!notUploaded || r['uploaded'] == 0) && (since == null || (r['ts'] as int) >= since.millisecondsSinceEpoch))
          .toList()
        ..sort((a, b) => (b['ts'] as int).compareTo(a['ts'] as int));
      return l.take(limit).toList();
    }
    final where = [if (notUploaded) 'uploaded = 0', if (since != null) 'ts >= ${since.millisecondsSinceEpoch}'].join(' and ');
    return d.query(table, where: where.isEmpty ? null : where, orderBy: 'ts desc', limit: limit);
  }

  Future<List<SmsRow>> sms({bool notUploaded = false, int limit = 100000, DateTime? since}) async =>
      [for (final r in await _query('sms', _sms, notUploaded, limit, since)) SmsRow.fromDb(r)];

  Future<List<CallRow>> calls({bool notUploaded = false, int limit = 100000, DateTime? since}) async =>
      [for (final r in await _query('calls', _calls, notUploaded, limit, since)) CallRow.fromDb(r)];

  Future<void> _mark(String table, Map<String, Map<String, Object?>> mem, Iterable<String> hashes) async {
    final d = db;
    if (d == null) {
      for (final h in hashes) {
        mem[h]?['uploaded'] = 1;
      }
      return;
    }
    final b = d.batch();
    for (final h in hashes) {
      b.update(table, {'uploaded': 1}, where: 'hash = ?', whereArgs: [h]);
    }
    await b.commit(noResult: true);
  }

  /// "Upload old data": everything kept on the device is sent again (the server keeps each one once).
  Future<void> unmarkAll() async {
    final d = db;
    if (d == null) {
      for (final r in [..._sms.values, ..._calls.values]) {
        r['uploaded'] = 0;
      }
      return;
    }
    await d.update('sms', {'uploaded': 0});
    await d.update('calls', {'uploaded': 0});
  }

  /// Clean-up: records already uploaded and older than [days] leave the device (they stay on the server).
  /// What is not uploaded yet is never removed. Returns how many were removed.
  Future<int> cleanup(int days) async {
    final cut = DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;
    final d = db;
    if (d == null) {
      var n = 0;
      for (final m in [_sms, _calls]) {
        final old = m.entries.where((e) => e.value['uploaded'] == 1 && (e.value['ts'] as int) < cut).map((e) => e.key).toList();
        n += old.length;
        old.forEach(m.remove);
      }
      return n;
    }
    final a = await d.delete('sms', where: 'uploaded = 1 and ts < ?', whereArgs: [cut]);
    final b = await d.delete('calls', where: 'uploaded = 1 and ts < ?', whereArgs: [cut]);
    return a + b;
  }

  Future<void> markSms(Iterable<String> hashes) => _mark('sms', _sms, hashes);
  Future<void> markCalls(Iterable<String> hashes) => _mark('calls', _calls, hashes);

  Future<(int, int, int, int)> counts() async {
    final d = db;
    if (d == null) {
      return (_sms.length, _sms.values.where((r) => r['uploaded'] == 0).length, _calls.length, _calls.values.where((r) => r['uploaded'] == 0).length);
    }
    final s = Sqflite.firstIntValue(await d.rawQuery('select count(*) from sms')) ?? 0;
    final sw = Sqflite.firstIntValue(await d.rawQuery('select count(*) from sms where uploaded = 0')) ?? 0;
    final k = Sqflite.firstIntValue(await d.rawQuery('select count(*) from calls')) ?? 0;
    final kw = Sqflite.firstIntValue(await d.rawQuery('select count(*) from calls where uploaded = 0')) ?? 0;
    return (s, sw, k, kw);
  }
}

