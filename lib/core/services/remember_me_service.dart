import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'session_settings.dart';

/// 🔐 خدمة "تذكّرني" — تحفظ token آمن للجلسات الطويلة
///
/// التخزين على الجهاز فقط (SharedPreferences). لا token يُرسل لسيرفر
/// خارجي حالياً — التحقّق يتمّ بمطابقة الـ token المحفوظ.
class RememberMeService {
  RememberMeService._();
  static final instance = RememberMeService._();

  static const _kToken = 'rm_token_v1';
  static const _kAccountId = 'rm_account_id_v1';
  static const _kUsername = 'rm_username_v1';
  static const _kCreatedAt = 'rm_created_at_v1';
  static const _kExpiresAt = 'rm_expires_at_v1';
  static const _kDeviceId = 'rm_device_id_v1';

  /// يحفظ token جلسة جديدة (يُستدعى عند تسجيل دخول مع "تذكّرني")
  Future<RememberedSession> save({
    required String accountId,
    required String username,
    required String deviceId,
  }) async {
    await SessionSettings.instance.load();
    final settings = SessionSettings.instance;
    final now = DateTime.now();
    final expires = now.add(settings.duration.toDuration());
    final token = _generateToken();

    final p = await SharedPreferences.getInstance();
    await p.setString(_kToken, token);
    await p.setString(_kAccountId, accountId);
    await p.setString(_kUsername, username);
    await p.setString(_kCreatedAt, now.toIso8601String());
    await p.setString(_kExpiresAt, expires.toIso8601String());
    await p.setString(_kDeviceId, deviceId);

    return RememberedSession(
      accountId: accountId,
      username: username,
      token: token,
      createdAt: now,
      expiresAt: expires,
      deviceId: deviceId,
    );
  }

  /// محاولة قراءة الـ token المحفوظ
  /// يُرجع null إن لم يوجد أو انتهت صلاحيته
  Future<RememberedSession?> tryLoad() async {
    try {
      final p = await SharedPreferences.getInstance();
      final token = p.getString(_kToken);
      final accountId = p.getString(_kAccountId);
      final username = p.getString(_kUsername);
      final createdAtStr = p.getString(_kCreatedAt);
      final expiresAtStr = p.getString(_kExpiresAt);
      final deviceId = p.getString(_kDeviceId) ?? '';

      if (token == null ||
          accountId == null ||
          username == null ||
          createdAtStr == null ||
          expiresAtStr == null) {
        return null;
      }

      final expiresAt = DateTime.tryParse(expiresAtStr);
      if (expiresAt == null) return null;
      if (DateTime.now().isAfter(expiresAt)) {
        // انتهت الصلاحيّة → امسح
        await clear();
        return null;
      }

      final createdAt = DateTime.tryParse(createdAtStr) ??
          DateTime.now();

      return RememberedSession(
        accountId: accountId,
        username: username,
        token: token,
        createdAt: createdAt,
        expiresAt: expiresAt,
        deviceId: deviceId,
      );
    } catch (_) {
      return null;
    }
  }

  /// يمسح الـ token المحفوظ (logout أو تغيير كلمة مرور)
  Future<void> clear() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_kToken);
      await p.remove(_kAccountId);
      await p.remove(_kUsername);
      await p.remove(_kCreatedAt);
      await p.remove(_kExpiresAt);
      await p.remove(_kDeviceId);
    } catch (_) {}
  }

  /// يُمسح الـ token عند تغيير كلمة مرور (إن السياسة تطلب ذلك)
  Future<void> onPasswordChanged(String accountId) async {
    await SessionSettings.instance.load();
    if (!SessionSettings.instance.invalidateOnPasswordChange) return;
    final current = await tryLoad();
    if (current?.accountId == accountId) {
      await clear();
    }
  }

  String _generateToken() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(32, (_) => rnd.nextInt(256));
    return base64UrlEncode(bytes);
  }
}

/// نموذج جلسة محفوظة محلّياً
class RememberedSession {
  final String accountId;
  final String username;
  final String token;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String deviceId;

  const RememberedSession({
    required this.accountId,
    required this.username,
    required this.token,
    required this.createdAt,
    required this.expiresAt,
    required this.deviceId,
  });

  Duration get remaining => expiresAt.difference(DateTime.now());
  bool get isExpired => remaining.isNegative;

  String remainingLabel({required bool isAr}) {
    final r = remaining;
    if (r.isNegative) return isAr ? 'منتهية' : 'expired';
    if (r.inDays >= 1) {
      return isAr ? '${r.inDays} يوم' : '${r.inDays}d';
    }
    if (r.inHours >= 1) {
      return isAr ? '${r.inHours} ساعة' : '${r.inHours}h';
    }
    return isAr ? '${r.inMinutes} دقيقة' : '${r.inMinutes}m';
  }
}
