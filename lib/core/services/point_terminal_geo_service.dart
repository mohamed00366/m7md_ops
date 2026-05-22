// =============================================================================
// 📍 PointTerminalGeoService — قُفل المَوقِع لِجِهاز Terminal
// =============================================================================
// يُغَلِّف RPCs:
//   • can_register_new_device — هَل يُمكِن تَسجيل جِهاز جَديد
//   • register_terminal_device — تَسجيل أَوَّل مَرَّة (مَع GPS)
//   • verify_device_in_zone — فَحص هَل الجِهاز ضِمن النِطاق
// =============================================================================
import 'package:geolocator/geolocator.dart';

import 'device_session_service.dart';
import 'supabase_service.dart';

class CanRegisterResult {
  final bool allowed;
  final int currentCount;
  final int maxAllowed;
  final String reason; // unlimited | within_limit | max_reached | account_not_found

  CanRegisterResult({
    required this.allowed,
    required this.currentCount,
    required this.maxAllowed,
    required this.reason,
  });
}

class RegisterResult {
  final bool success;
  final String? sessionId;
  final String reason; // updated | created | max_reached | account_not_found

  RegisterResult({
    required this.success,
    this.sessionId,
    required this.reason,
  });
}

class VerifyZoneResult {
  final bool inZone;
  final int? distanceM;
  final int? allowedM;
  final double? registeredLat;
  final double? registeredLng;
  final String reason; // in_zone | out_of_zone | not_registered | deactivated | invalid_gps

  VerifyZoneResult({
    required this.inZone,
    this.distanceM,
    this.allowedM,
    this.registeredLat,
    this.registeredLng,
    required this.reason,
  });

  bool get notRegistered => reason == 'not_registered';
  bool get outOfZone => reason == 'out_of_zone';
}

class PointTerminalGeoService {
  PointTerminalGeoService._();
  static final instance = PointTerminalGeoService._();

  String? lastError;

  /// طَلَب صَلاحيّة GPS وَإرجاع الإحداثيّات الحاليّة
  Future<Position?> getCurrentPosition() async {
    try {
      // فَحص خِدمة GPS
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        lastError = 'GPS service is disabled';
        return null;
      }

      // فَحص الصَلاحيّات
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        lastError = 'Location permission denied';
        return null;
      }

      // الإحداثيّات الحاليّة
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
      return pos;
    } catch (e) {
      lastError = e.toString();
      return null;
    }
  }

  /// فَحص هَل يُمكِن تَسجيل جِهاز جَديد لِهذا الحِساب
  Future<CanRegisterResult> canRegister(String accountId) async {
    try {
      final c = SupabaseService().client;
      final res = await c.rpc('can_register_new_device',
          params: {'p_account_id': accountId});
      if (res is List && res.isNotEmpty) {
        final m = Map<String, dynamic>.from(res.first as Map);
        return CanRegisterResult(
          allowed: m['allowed'] as bool? ?? false,
          currentCount: (m['current_count'] as num?)?.toInt() ?? 0,
          maxAllowed: (m['max_allowed'] as num?)?.toInt() ?? 0,
          reason: m['reason'] as String? ?? 'unknown',
        );
      }
      return CanRegisterResult(
        allowed: false,
        currentCount: 0,
        maxAllowed: 0,
        reason: 'no_response',
      );
    } catch (e) {
      lastError = e.toString();
      return CanRegisterResult(
        allowed: false,
        currentCount: 0,
        maxAllowed: 0,
        reason: 'error',
      );
    }
  }

  /// تَسجيل جِهاز جَديد (أَوَّل مَرَّة) مَع GPS
  Future<RegisterResult> registerDevice({
    required String accountId,
    required String deviceLabel,
    required double lat,
    required double lng,
  }) async {
    try {
      final deviceId = await DeviceSessionService.instance.ensureDeviceId();
      final c = SupabaseService().client;
      final res = await c.rpc('register_terminal_device', params: {
        'p_account_id': accountId,
        'p_device_id': deviceId,
        'p_device_label': deviceLabel,
        'p_lat': lat,
        'p_lng': lng,
      });
      if (res is List && res.isNotEmpty) {
        final m = Map<String, dynamic>.from(res.first as Map);
        return RegisterResult(
          success: m['success'] as bool? ?? false,
          sessionId: m['session_id'] as String?,
          reason: m['reason'] as String? ?? 'unknown',
        );
      }
      return RegisterResult(success: false, reason: 'no_response');
    } catch (e) {
      lastError = e.toString();
      return RegisterResult(success: false, reason: 'error');
    }
  }

  /// فَحص هَل الجِهاز ضِمن النِطاق المُسَجَّل
  Future<VerifyZoneResult> verifyZone({
    required String accountId,
    required double lat,
    required double lng,
  }) async {
    try {
      final deviceId = await DeviceSessionService.instance.ensureDeviceId();
      final c = SupabaseService().client;
      final res = await c.rpc('verify_device_in_zone', params: {
        'p_account_id': accountId,
        'p_device_id': deviceId,
        'p_lat': lat,
        'p_lng': lng,
      });
      if (res is List && res.isNotEmpty) {
        final m = Map<String, dynamic>.from(res.first as Map);
        return VerifyZoneResult(
          inZone: m['in_zone'] as bool? ?? false,
          distanceM: (m['distance_m'] as num?)?.toInt(),
          allowedM: (m['allowed_m'] as num?)?.toInt(),
          registeredLat: (m['registered_lat'] as num?)?.toDouble(),
          registeredLng: (m['registered_lng'] as num?)?.toDouble(),
          reason: m['reason'] as String? ?? 'unknown',
        );
      }
      return VerifyZoneResult(inZone: false, reason: 'no_response');
    } catch (e) {
      lastError = e.toString();
      return VerifyZoneResult(inZone: false, reason: 'error');
    }
  }

  /// التَدَفُّق المُوَحَّد: فَحص + تَسجيل تِلقائيّ إن لَزِم
  /// يُرجِع نَتيجة واحِدة تَصف ما يَنبَغي عَرضه لِلمُستَخدِم
  Future<TerminalGateResult> gate({
    required String accountId,
    String? deviceLabelIfNew,
  }) async {
    // 1) الحُصول عَلى GPS
    final pos = await getCurrentPosition();
    if (pos == null) {
      return TerminalGateResult(
        decision: TerminalGateDecision.gpsError,
        message: lastError ?? 'GPS unavailable',
      );
    }

    // 2) فَحص هَل الجِهاز مُسَجَّل وَضِمن النِطاق
    final verify = await verifyZone(
      accountId: accountId,
      lat: pos.latitude,
      lng: pos.longitude,
    );

    if (verify.inZone) {
      return TerminalGateResult(
        decision: TerminalGateDecision.allowed,
        position: pos,
        distanceM: verify.distanceM,
      );
    }

    if (verify.outOfZone) {
      return TerminalGateResult(
        decision: TerminalGateDecision.outOfZone,
        position: pos,
        distanceM: verify.distanceM,
        allowedM: verify.allowedM,
        registeredLat: verify.registeredLat,
        registeredLng: verify.registeredLng,
        message: 'out_of_zone',
      );
    }

    if (verify.notRegistered) {
      // يَحتاج تَسجيل أَوَّل مَرَّة
      // أَوَّلاً فَحص هَل يَستَطيع التَسجيل
      final can = await canRegister(accountId);
      if (!can.allowed) {
        return TerminalGateResult(
          decision: TerminalGateDecision.maxDevicesReached,
          currentCount: can.currentCount,
          maxAllowed: can.maxAllowed,
          message: can.reason,
        );
      }
      return TerminalGateResult(
        decision: TerminalGateDecision.needsSetup,
        position: pos,
      );
    }

    return TerminalGateResult(
      decision: TerminalGateDecision.gpsError,
      message: verify.reason,
    );
  }
}

enum TerminalGateDecision {
  allowed,
  needsSetup,        // أَوَّل فَتح — يَحتاج تَسمية + تَسجيل GPS
  outOfZone,         // خارِج النِطاق
  maxDevicesReached, // وَصَلَ الحَدّ الأَقصى لِلأَجهِزة
  gpsError,          // GPS غَير مُتاح أَو رُفِضَت الصَلاحيّة
}

class TerminalGateResult {
  final TerminalGateDecision decision;
  final Position? position;
  final int? distanceM;
  final int? allowedM;
  final double? registeredLat;
  final double? registeredLng;
  final int? currentCount;
  final int? maxAllowed;
  final String? message;

  TerminalGateResult({
    required this.decision,
    this.position,
    this.distanceM,
    this.allowedM,
    this.registeredLat,
    this.registeredLng,
    this.currentCount,
    this.maxAllowed,
    this.message,
  });
}
