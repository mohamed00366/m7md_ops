import 'package:flutter/foundation.dart' show kIsWeb;

import 'device_session_service.dart';
import 'm7_log.dart';
import 'supabase_service.dart';

/// 🖥 خِدمة جَلسات نُقاط الدَوام
///
/// مَسؤولة عَن تَسجيل/تَحديث/إنهاء جَلسات Terminal في جَدول
/// `point_terminal_sessions` (مُنفَصِل عَن `employee_device_sessions`
/// الخاصّ بِالموَظَّفين العاديّين).
class PointTerminalSessionService {
  PointTerminalSessionService._();
  static final instance = PointTerminalSessionService._();

  /// 🆕 يَفتَح جَلسة جَديدة (أَو يُحَدِّث القائِمة) عِندَ دُخول Terminal
  Future<String?> registerOnLogin({
    required String accountId,
    required String pointId,
  }) async {
    final supa = SupabaseService();
    if (!supa.isReady) return null;
    try {
      final deviceId =
          await DeviceSessionService.instance.ensureDeviceId();

      // 1) ابحَث عَن جَلسة سابِقة (نَفس الجِهاز + الحِساب)
      final existing = await supa.client
          .from('point_terminal_sessions')
          .select('id')
          .eq('account_id', accountId)
          .eq('device_id', deviceId)
          .eq('is_active', true)
          .maybeSingle();

      if (existing != null) {
        // حَدِّث الجَلسة المَوجودة
        final id = existing['id'] as String;
        await supa.client.from('point_terminal_sessions').update({
          'last_login_at': DateTime.now().toUtc().toIso8601String(),
          'last_seen_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', id);
        return id;
      }

      // 2) عَطِّل أَيّ جَلسات أُخرى لِنَفس الحِساب (Terminal واحِد لِكُلّ حِساب)
      await supa.client
          .from('point_terminal_sessions')
          .update({
            'is_active': false,
            'deactivated_at':
                DateTime.now().toUtc().toIso8601String(),
            'deactivated_reason': 'replaced',
          })
          .eq('account_id', accountId)
          .eq('is_active', true);

      // 3) أَنشِئ جَلسة جَديدة
      final res = await supa.client
          .from('point_terminal_sessions')
          .insert({
            'account_id': accountId,
            'point_id': pointId,
            'device_id': deviceId,
            'device_name': _deviceName(),
            'platform': _platformKey(),
            'app_version': '1.0.0',
            'is_active': true,
          })
          .select('id')
          .single();
      return res['id'] as String?;
    } catch (e) {
      M7Log.error('PointTerminalSession', 'register', error: e);
      return null;
    }
  }

  /// 🆕 يُحَدِّث `last_seen_at` (Heartbeat — يُستَدعى دَورِيّاً مِن الـUI)
  Future<void> touch({required String accountId}) async {
    final supa = SupabaseService();
    if (!supa.isReady) return;
    try {
      final deviceId =
          await DeviceSessionService.instance.ensureDeviceId();
      await supa.client
          .from('point_terminal_sessions')
          .update({
            'last_seen_at':
                DateTime.now().toUtc().toIso8601String(),
          })
          .eq('account_id', accountId)
          .eq('device_id', deviceId)
          .eq('is_active', true);
    } catch (_) {/* ignore */}
  }

  /// 🆕 يُعَطِّل الجَلسة الحاليّة (عِندَ تَسجيل الخُروج)
  Future<void> deactivateOnLogout({required String accountId}) async {
    final supa = SupabaseService();
    if (!supa.isReady) return;
    try {
      final deviceId =
          await DeviceSessionService.instance.ensureDeviceId();
      await supa.client
          .from('point_terminal_sessions')
          .update({
            'is_active': false,
            'deactivated_at':
                DateTime.now().toUtc().toIso8601String(),
            'deactivated_reason': 'logout',
          })
          .eq('account_id', accountId)
          .eq('device_id', deviceId)
          .eq('is_active', true);
    } catch (_) {/* ignore */}
  }

  /// 🆕 قائِمة كُلّ الجَلسات (لِلمَسؤول)
  Future<List<TerminalSession>> listAll(
      {bool onlyActive = false}) async {
    final supa = SupabaseService();
    if (!supa.isReady) return [];
    try {
      final base = supa.client.from('point_terminal_sessions').select(
          'id, account_id, point_id, device_id, device_name, '
          'device_model, platform, os_version, app_version, ip_address, '
          'device_label, '
          'first_login_at, last_login_at, last_seen_at, '
          'is_active, deactivated_at, deactivated_reason, '
          'accounts(username, full_name), '
          'points(name, code)');
      final rows = onlyActive
          ? await base
              .eq('is_active', true)
              .order('last_seen_at', ascending: false)
          : await base.order('last_seen_at', ascending: false);
      return List<Map<String, dynamic>>.from(rows as List)
          .map((r) => TerminalSession.fromRow(r))
          .toList();
    } catch (e) {
      M7Log.error('PointTerminalSession', 'listAll', error: e);
      return [];
    }
  }

  /// 🆕 تَعيين/تَحديث اسم الجِهاز عَلى الجَلسة الحاليّة
  Future<bool> setDeviceLabel({
    required String accountId,
    required String label,
  }) async {
    final supa = SupabaseService();
    if (!supa.isReady) return false;
    try {
      final deviceId =
          await DeviceSessionService.instance.ensureDeviceId();
      await supa.client
          .from('point_terminal_sessions')
          .update({'device_label': label})
          .eq('account_id', accountId)
          .eq('device_id', deviceId)
          .eq('is_active', true);
      return true;
    } catch (e) {
      M7Log.error('PointTerminalSession', 'setDeviceLabel', error: e);
      return false;
    }
  }

  /// 🆕 يَفحَص هَل لِلجِهاز الحاليّ اسم على هذا الحِساب
  Future<String?> getCurrentDeviceLabel(String accountId) async {
    final supa = SupabaseService();
    if (!supa.isReady) return null;
    try {
      final deviceId =
          await DeviceSessionService.instance.ensureDeviceId();
      final row = await supa.client
          .from('point_terminal_sessions')
          .select('device_label')
          .eq('account_id', accountId)
          .eq('device_id', deviceId)
          .eq('is_active', true)
          .maybeSingle();
      return row?['device_label'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// 🆕 إنهاء جَلسة من قِبَل المَسؤول
  Future<bool> revokeSession(String sessionId) async {
    final supa = SupabaseService();
    if (!supa.isReady) return false;
    try {
      await supa.client.from('point_terminal_sessions').update({
        'is_active': false,
        'deactivated_at':
            DateTime.now().toUtc().toIso8601String(),
        'deactivated_reason': 'admin_revoked',
      }).eq('id', sessionId);
      return true;
    } catch (e) {
      M7Log.error('PointTerminalSession', 'revoke', error: e);
      return false;
    }
  }

  String _deviceName() {
    if (kIsWeb) return 'Web Browser';
    return 'Terminal Device';
  }

  String _platformKey() {
    if (kIsWeb) return 'web';
    return 'android'; // مَبدَئِيّاً
  }
}

/// نَموذَج جَلسة Terminal
class TerminalSession {
  final String id;
  final String accountId;
  final String pointId;
  final String deviceId;
  final String? deviceName;
  final String? deviceLabel;
  final String? deviceModel;
  final String? platform;
  final String? osVersion;
  final String? appVersion;
  final String? ipAddress;
  final DateTime? firstLoginAt;
  final DateTime? lastLoginAt;
  final DateTime? lastSeenAt;
  final bool isActive;
  final DateTime? deactivatedAt;
  final String? deactivatedReason;
  // مَن relationships
  final String? accountUsername;
  final String? accountFullName;
  final String? pointName;
  final String? pointCode;

  const TerminalSession({
    required this.id,
    required this.accountId,
    required this.pointId,
    required this.deviceId,
    this.deviceName,
    this.deviceLabel,
    this.deviceModel,
    this.platform,
    this.osVersion,
    this.appVersion,
    this.ipAddress,
    this.firstLoginAt,
    this.lastLoginAt,
    this.lastSeenAt,
    required this.isActive,
    this.deactivatedAt,
    this.deactivatedReason,
    this.accountUsername,
    this.accountFullName,
    this.pointName,
    this.pointCode,
  });

  static DateTime? _ts(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }

  factory TerminalSession.fromRow(Map<String, dynamic> r) {
    Map<String, dynamic>? accMap;
    final acc = r['accounts'];
    if (acc is Map) accMap = Map<String, dynamic>.from(acc);
    Map<String, dynamic>? pointMap;
    final pt = r['points'];
    if (pt is Map) pointMap = Map<String, dynamic>.from(pt);
    return TerminalSession(
      id: r['id'] as String,
      accountId: r['account_id'] as String,
      pointId: r['point_id'] as String,
      deviceId: r['device_id'] as String,
      deviceName: r['device_name'] as String?,
      deviceLabel: r['device_label'] as String?,
      deviceModel: r['device_model'] as String?,
      platform: r['platform'] as String?,
      osVersion: r['os_version'] as String?,
      appVersion: r['app_version'] as String?,
      ipAddress: r['ip_address'] as String?,
      firstLoginAt: _ts(r['first_login_at']),
      lastLoginAt: _ts(r['last_login_at']),
      lastSeenAt: _ts(r['last_seen_at']),
      isActive: r['is_active'] as bool? ?? false,
      deactivatedAt: _ts(r['deactivated_at']),
      deactivatedReason: r['deactivated_reason'] as String?,
      accountUsername: accMap?['username'] as String?,
      accountFullName: accMap?['full_name'] as String?,
      pointName: pointMap?['name'] as String?,
      pointCode: pointMap?['code'] as String?,
    );
  }
}
