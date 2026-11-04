import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'store.dart';

/// The fixed login of the app (a main account and a backup account). Only a salted sha256 is kept on the device.
/// 5 wrong tries lock the login for 5 minutes.
class FleetAuth {
  static String _hash(String salt, String pw) => sha256.convert(utf8.encode('$salt|$pw')).toString();

  static String make(String user, String pw) {
    final r = Random.secure();
    final salt = base64Url.encode(List.generate(12, (_) => r.nextInt(256)));
    return '${user.trim().toLowerCase()}|$salt|${_hash(salt, pw)}';
  }

  static bool check(String? stored, String user, String pw) {
    if (stored == null) return false;
    final parts = stored.split('|');
    if (parts.length != 3) return false;
    return parts[0] == user.trim().toLowerCase() && parts[2] == _hash(parts[1], pw);
  }

  static bool isSetUp(Prefs p) => p.loginMain != null && p.loginBackup != null && p.deviceKey.isNotEmpty;

  /// null = signed in · else the reason.
  static Future<String?> signIn(Prefs p, String user, String pw) async {
    final until = p.lockedUntil;
    if (until != null && DateTime.now().isBefore(until)) {
      return 'Locked – try again in ${until.difference(DateTime.now()).inMinutes + 1} min.';
    }
    if (check(p.loginMain, user, pw) || check(p.loginBackup, user, pw)) {
      await p.setFailCount(0);
      await p.setLockedUntil(null);
      return null;
    }
    final n = p.failCount + 1;
    await p.setFailCount(n);
    if (n >= 5) {
      await p.setFailCount(0);
      await p.setLockedUntil(DateTime.now().add(const Duration(minutes: 5)));
      return 'Wrong 5 times – locked for 5 minutes.';
    }
    return 'Wrong user or password (${5 - n} tries left).';
  }
}
