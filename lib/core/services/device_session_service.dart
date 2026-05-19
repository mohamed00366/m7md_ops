import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'supabase_service.dart';
import 'm7_log.dart';

/// 📱 خدمة جلسات الأجهزة
///
/// تحلّ المشكلة: "جهاز واحد لكل موظف"
///   • عند تسجيل الدخول، نلتقط معرّف الجهاز ونسجّله في قاعدة البيانات
///   • إذا كان لنفس الحساب جلسة فعّالة على جهاز آخر، نُعطّلها تلقائياً
///   • Admin يستطيع حذف الجلسات يدوياً ليُتيح الدخول من جهاز آخر
///
/// نقطة الاستعمال:
///   final r = await DeviceSessionService.instance.registerOnLogin(
///     accountId: account.id, employeeId: account.employeeId);
///
/// لا يلزم package جديد — نستخدم shared_preferences لإنشاء/حفظ
/// device_id ثابت لكل جهاز (يبقى ما لم يحذف المستخدم بيانات التطبيق).
class DeviceSessionService {
  DeviceSessionService._();
  static final instance = DeviceSessionService._();

  static const _kDeviceIdKey = 'm7_device_id_v1';
  static const _kDeviceNameKey = 'm7_device_name_v1';

  String? _deviceId;
  String? _deviceName;

  String get deviceIdSync => _deviceId ?? '';
  String get deviceNameSync => _deviceName ?? _platformLabel();

  /// 🔑 يحصل على device_id الثابت (ينشئه أوّل مرّة فقط)
  Future<String> ensureDeviceId() async {
    if (_deviceId != null && _deviceId!.isNotEmpty) return _deviceId!;
    try {
      final p = await SharedPreferences.getInstance();
      var id = p.getString(_kDeviceIdKey);
      if (id == null || id.isEmpty) {
        id = _generateDeviceId();
        await p.setString(_kDeviceIdKey, id);
      }
      _deviceId = id;
      _deviceName = p.getString(_kDeviceNameKey);
      return id;
    } catch (_) {
      _deviceId ??= _generateDeviceId();
      return _deviceId!;
    }
  }

  /// يسمح للمستخدم/المسؤول بإعادة تسمية الجهاز
  Future<void> setDeviceName(String name) async {
    _deviceName = name;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kDeviceNameKey, name);
    } catch (_) {}
  }

  String _generateDeviceId() {
    // 24-char base16 من timestamp + random — مستقرّ بعد الإنشاء
    final rnd = Random.secure();
    final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(16);
    final r1 = rnd.nextInt(0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
    final r2 = rnd.nextInt(0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
    return '$ts-$r1$r2';
  }

  String _platformLabel() {
    if (kIsWeb) return 'Web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'Android Device';
      case TargetPlatform.iOS:
        return 'iOS Device';
      case TargetPlatform.windows:
        return 'Windows PC';
      case TargetPlatform.macOS:
        return 'Mac';
      case TargetPlatform.linux:
        return 'Linux';
      default:
        return 'Unknown Device';
    }
  }

  String _platformKey() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.linux:
        return 'linux';
      default:
        return 'unknown';
    }
  }

  /// 🔥 الواجهة الرئيسيّة: يُستدعى من AuthProvider بعد نجاح تسجيل الدخول
  ///
  /// [strictOneDevice] إذا true ⇒ نمنع الدخول لو هناك جهاز فعّال آخر،
  ///                  بدلاً من الإحلال التلقائي. (افتراضي: false → استبدال)
  ///
  /// يُرجع DeviceSessionResult يصف ما حصل.
  Future<DeviceSessionResult> registerOnLogin({
    required String accountId,
    String? employeeId,
    bool strictOneDevice = false,
  }) async {
    final deviceId = await ensureDeviceId();
    final supa = SupabaseService();
    if (!supa.isReady) {
      return DeviceSessionResult.localOnly(deviceId: deviceId);
    }

    try {
      // 1) في الوضع المتشدّد، تحقّق أوّلاً من وجود جهاز آخر فعّال
      if (strictOneDevice) {
        final existing = await supa.client
            .from('employee_device_sessions')
            .select('id, device_id, device_name, last_login_at')
            .eq('account_id', accountId)
            .eq('is_active', true)
            .maybeSingle();
        if (existing != null && existing['device_id'] != deviceId) {
          return DeviceSessionResult(
            ok: false,
            blocked: true,
            blockingDeviceName: existing['device_name'] as String?,
            blockingDeviceId: existing['device_id'] as String?,
            deviceId: deviceId,
          );
        }
      }

      // 2) سجّل/حدّث الجلسة عبر RPC (يتعامل مع الإحلال + حدّ "جهاز واحد")
      final rpc = await supa.client.rpc(
        'register_device_session',
        params: {
          'p_account_id': accountId,
          'p_employee_id': employeeId,
          'p_device_id': deviceId,
          'p_device_name': _deviceName ?? _platformLabel(),
          'p_device_model': null,
          'p_platform': _platformKey(),
          'p_os_version': null,
          'p_app_version': '1.0.0',
          'p_ip': null,
          'p_user_agent': null,
        },
      );
      String? sessionId;
      bool isNewDevice = false;
      String? replacedSessionId;
      if (rpc is List && rpc.isNotEmpty) {
        final row = rpc.first as Map;
        sessionId = row['session_id'] as String?;
        isNewDevice = row['is_new_device'] as bool? ?? false;
        replacedSessionId = row['replaced_session_id'] as String?;
      }
      return DeviceSessionResult(
        ok: true,
        sessionId: sessionId,
        deviceId: deviceId,
        isNewDevice: isNewDevice,
        replacedSessionId: replacedSessionId,
      );
    } catch (e) {
      // ignore: avoid_print
      M7Log.error('DeviceSession', 'register', error: e);
      // fallback: insert manual (في حال RPC غير منشورة بعد)
      try {
        // أوّلاً: عطّل الجلسات الفعّالة الأخرى لنفس الحساب
        await supa.client
            .from('employee_device_sessions')
            .update({
              'is_active': false,
              'deactivated_at': DateTime.now().toIso8601String(),
              'deactivated_reason': 'replaced',
            })
            .eq('account_id', accountId)
            .eq('is_active', true)
            .neq('device_id', deviceId);
        // ثانياً: upsert جلستنا
        final res = await supa.client
            .from('employee_device_sessions')
            .insert({
              'account_id': accountId,
              'employee_id': employeeId,
              'device_id': deviceId,
              'device_name': _deviceName ?? _platformLabel(),
              'platform': _platformKey(),
              'app_version': '1.0.0',
              'is_active': true,
            })
            .select('id')
            .maybeSingle();
        return DeviceSessionResult(
          ok: true,
          deviceId: deviceId,
          sessionId: res?['id'] as String?,
          isNewDevice: true,
        );
      } catch (e2) {
        // ignore: avoid_print
        M7Log.info('DeviceSession', 'fallback insert failed: $e2');
        return DeviceSessionResult.error(
          deviceId: deviceId,
          message: e2.toString(),
        );
      }
    }
  }

  /// عند تسجيل الخروج، نُعطّل جلسة الجهاز الحالي (لكن لا نحذفها)
  Future<void> deactivateOnLogout({required String accountId}) async {
    final deviceId = await ensureDeviceId();
    final supa = SupabaseService();
    if (!supa.isReady) return;
    try {
      await supa.client
          .from('employee_device_sessions')
          .update({
            'is_active': false,
            'deactivated_at': DateTime.now().toIso8601String(),
            'deactivated_reason': 'logout',
          })
          .eq('account_id', accountId)
          .eq('device_id', deviceId);
    } catch (_) {}
  }

  /// تحديث last_seen (تُستدعى دوريّاً لو رغبنا في تتبّع نشاط)
  Future<void> heartbeat({required String accountId}) async {
    final deviceId = await ensureDeviceId();
    final supa = SupabaseService();
    if (!supa.isReady) return;
    try {
      await supa.client
          .from('employee_device_sessions')
          .update({'last_seen_at': DateTime.now().toIso8601String()})
          .eq('account_id', accountId)
          .eq('device_id', deviceId)
          .eq('is_active', true);
    } catch (_) {}
  }

  // ====== Admin ops ======

  /// قائمة كل جلسات الأجهزة (للمسؤول)
  Future<List<DeviceSession>> listAll({bool onlyActive = false}) async {
    final supa = SupabaseService();
    if (!supa.isReady) return [];
    try {
      final base = supa.client.from('employee_device_sessions').select(
          'id, account_id, employee_id, device_id, device_name, device_model, '
          'platform, os_version, app_version, '
          'first_login_at, last_login_at, last_seen_at, '
          'ip_address, is_active, deactivated_at, deactivated_reason, '
          'accounts(username, full_name)');
      final rows = onlyActive
          ? await base
              .eq('is_active', true)
              .order('last_login_at', ascending: false)
          : await base.order('last_login_at', ascending: false);
      return List<Map<String, dynamic>>.from(rows as List)
          .map((r) => DeviceSession.fromRow(r))
          .toList();
    } catch (e) {
      // ignore: avoid_print
      M7Log.error('DeviceSession', 'listAll', error: e);
      return [];
    }
  }

  /// حذف جلسة (admin) — يُمكّن الموظّف من الدخول من جهاز آخر
  Future<bool> deleteSession(String sessionId) async {
    final supa = SupabaseService();
    if (!supa.isReady) return false;
    try {
      await supa.client
          .from('employee_device_sessions')
          .delete()
          .eq('id', sessionId);
      return true;
    } catch (e) {
      // ignore: avoid_print
      M7Log.error('DeviceSession', 'delete', error: e);
      return false;
    }
  }

  /// تعطيل جلسة (دون حذف) — admin
  Future<bool> revokeSession(String sessionId) async {
    final supa = SupabaseService();
    if (!supa.isReady) return false;
    try {
      await supa.client
          .from('employee_device_sessions')
          .update({
            'is_active': false,
            'deactivated_at': DateTime.now().toIso8601String(),
            'deactivated_reason': 'admin_revoked',
          })
          .eq('id', sessionId);
      return true;
    } catch (e) {
      // ignore: avoid_print
      M7Log.error('DeviceSession', 'revoke', error: e);
      return false;
    }
  }
}

/// نتيجة محاولة تسجيل جهاز
class DeviceSessionResult {
  final bool ok;
  final bool blocked;
  final String? sessionId;
  final String deviceId;
  final bool isNewDevice;
  final String? replacedSessionId;
  final String? blockingDeviceName;
  final String? blockingDeviceId;
  final String? errorMessage;

  const DeviceSessionResult({
    required this.ok,
    this.blocked = false,
    this.sessionId,
    required this.deviceId,
    this.isNewDevice = false,
    this.replacedSessionId,
    this.blockingDeviceName,
    this.blockingDeviceId,
    this.errorMessage,
  });

  factory DeviceSessionResult.localOnly({required String deviceId}) =>
      DeviceSessionResult(ok: true, deviceId: deviceId);

  factory DeviceSessionResult.error(
          {required String deviceId, required String message}) =>
      DeviceSessionResult(
          ok: false, deviceId: deviceId, errorMessage: message);
}

/// نموذج جلسة جهاز
class DeviceSession {
  final String id;
  final String accountId;
  final String? employeeId;
  final String deviceId;
  final String? deviceName;
  final String? deviceModel;
  final String? platform;
  final String? osVersion;
  final String? appVersion;
  final DateTime? firstLoginAt;
  final DateTime? lastLoginAt;
  final DateTime? lastSeenAt;
  final String? ipAddress;
  final bool isActive;
  final DateTime? deactivatedAt;
  final String? deactivatedReason;
  final String? accountUsername;
  final String? accountFullName;

  const DeviceSession({
    required this.id,
    required this.accountId,
    this.employeeId,
    required this.deviceId,
    this.deviceName,
    this.deviceModel,
    this.platform,
    this.osVersion,
    this.appVersion,
    this.firstLoginAt,
    this.lastLoginAt,
    this.lastSeenAt,
    this.ipAddress,
    required this.isActive,
    this.deactivatedAt,
    this.deactivatedReason,
    this.accountUsername,
    this.accountFullName,
  });

  static DateTime? _ts(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }

  factory DeviceSession.fromRow(Map<String, dynamic> r) {
    final acc = r['accounts'];
    Map<String, dynamic>? accMap;
    if (acc is Map) accMap = Map<String, dynamic>.from(acc);
    return DeviceSession(
      id: r['id'] as String,
      accountId: r['account_id'] as String,
      employeeId: r['employee_id'] as String?,
      deviceId: r['device_id'] as String,
      deviceName: r['device_name'] as String?,
      deviceModel: r['device_model'] as String?,
      platform: r['platform'] as String?,
      osVersion: r['os_version'] as String?,
      appVersion: r['app_version'] as String?,
      firstLoginAt: _ts(r['first_login_at']),
      lastLoginAt: _ts(r['last_login_at']),
      lastSeenAt: _ts(r['last_seen_at']),
      ipAddress: r['ip_address'] as String?,
      isActive: r['is_active'] as bool? ?? false,
      deactivatedAt: _ts(r['deactivated_at']),
      deactivatedReason: r['deactivated_reason'] as String?,
      accountUsername: accMap?['username'] as String?,
      accountFullName: accMap?['full_name'] as String?,
    );
  }

  String get displayDeviceLabel {
    final name = (deviceName?.isNotEmpty ?? false) ? deviceName! : 'Device';
    return name;
  }

  String get shortDeviceId {
    if (deviceId.length <= 12) return deviceId;
    return '${deviceId.substring(0, 6)}…${deviceId.substring(deviceId.length - 6)}';
  }
}
