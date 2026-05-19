import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:network_info_plus/network_info_plus.dart';

import '../../models/login_zone.dart';
import 'geo_fence_settings.dart';
import 'm7_log.dart';

/// نتيجة فحص الموقع
class GeoFenceCheckResult {
  /// هل الدخول مسموح من حيث الموقع؟
  final bool allowed;

  /// سبب الرفض (للعرض للمستخدم)
  final GeoFenceRejection? rejection;

  /// المنطقة التي طابقها (إن وُجدت)
  final LoginZone? matchedZone;

  /// طريقة المطابقة (للسجلّ)
  final GeoFenceMethod? method;

  /// تحذير إن وُجد (مثل: VPN مكتشف)
  final String? warning;

  /// الإحداثيّات المُلتقطة
  final double? latitude;
  final double? longitude;
  final double? accuracyMeters;

  const GeoFenceCheckResult({
    required this.allowed,
    this.rejection,
    this.matchedZone,
    this.method,
    this.warning,
    this.latitude,
    this.longitude,
    this.accuracyMeters,
  });

  factory GeoFenceCheckResult.allow({
    LoginZone? zone,
    GeoFenceMethod? method,
    String? warning,
    double? lat,
    double? lng,
    double? accuracy,
  }) =>
      GeoFenceCheckResult(
        allowed: true,
        matchedZone: zone,
        method: method,
        warning: warning,
        latitude: lat,
        longitude: lng,
        accuracyMeters: accuracy,
      );

  factory GeoFenceCheckResult.reject(GeoFenceRejection reason,
          {double? lat, double? lng}) =>
      GeoFenceCheckResult(
        allowed: false,
        rejection: reason,
        latitude: lat,
        longitude: lng,
      );
}

enum GeoFenceMethod { wifi, gps, ipAddress }

enum GeoFenceRejection {
  outsideZone,
  mockLocationDetected,
  permissionDenied,
  serviceDisabled,
  unknown,
}

/// 🌍 خدمة الـ Geo-fence اللحظيّة
///
/// تتحقّق عند تسجيل الدخول من:
///   1) Wi-Fi SSID (إن مُفعَّل) — أسرع وأدقّ داخل المباني
///   2) GPS (إن مُفعَّل) — الأهمّ، مع كشف mock-location
///   3) IP geolocation (إن مُفعَّل) — احتياطي
///
/// منطق ذكيّ:
///   • Wi-Fi مطابق → ✅ قبول فوري
///   • GPS داخل منطقة → ✅ قبول
///   • GPS فشل + IP في البلد → ⚠️ قبول مع تحذير
///   • GPS مزيّف → ❌ رفض دائماً
///   • الكلّ فشل → ❌ رفض
class GeoFenceService {
  GeoFenceService._();
  static final instance = GeoFenceService._();

  /// ⏱️ مهلة GPS قبل الرجوع لـ IP (لتجنّب الانتظار طويلاً)
  static const Duration _gpsTimeout = Duration(seconds: 10);

  /// 🎯 الفحص الرئيسي — يُستدعى من AuthProvider بعد المصادقة
  ///
  /// إذا [enforce] = false (مثلاً override = exempt) فلا نفحص أصلاً.
  Future<GeoFenceCheckResult> check({required bool enforce}) async {
    if (!enforce) {
      return GeoFenceCheckResult.allow();
    }

    await GeoFenceSettings.instance.load();
    final settings = GeoFenceSettings.instance;

    // إن لم تكن السياسة مفعّلة عامّة، اسمح
    if (!settings.enabled) {
      return GeoFenceCheckResult.allow();
    }

    // إن لم تكن هناك أيّ مناطق محدّدة، اسمح (لا قيد فعليّ)
    final activeZones = settings.zones.where((z) => z.isActive).toList();
    if (activeZones.isEmpty) {
      return GeoFenceCheckResult.allow(
        warning: 'لا توجد مناطق محدّدة — اسمح افتراضياً',
      );
    }

    // ====== الطبقة 1: Wi-Fi SSID ======
    if (settings.checkWifi) {
      final wifiSsid = await _currentWifiSsid();
      if (wifiSsid != null && wifiSsid.isNotEmpty) {
        for (final z in activeZones) {
          if (z.wifiSsids.any((s) =>
              s.trim().toLowerCase() == wifiSsid.trim().toLowerCase())) {
            return GeoFenceCheckResult.allow(
              zone: z,
              method: GeoFenceMethod.wifi,
            );
          }
        }
      }
    }

    // ====== الطبقة 2: GPS ======
    Position? gpsPos;
    GeoFenceRejection? gpsBlock;
    if (settings.checkGps) {
      final gpsRes = await _getGps(settings.rejectMock);
      gpsPos = gpsRes.position;
      gpsBlock = gpsRes.rejection;

      // إذا تمّ كشف Mock-location
      if (gpsBlock == GeoFenceRejection.mockLocationDetected) {
        return GeoFenceCheckResult.reject(
          GeoFenceRejection.mockLocationDetected,
          lat: gpsPos?.latitude,
          lng: gpsPos?.longitude,
        );
      }

      if (gpsPos != null) {
        for (final z in activeZones) {
          final dKm = _haversineKm(
            gpsPos.latitude,
            gpsPos.longitude,
            z.centerLat,
            z.centerLng,
          );
          if (dKm <= z.radiusKm) {
            return GeoFenceCheckResult.allow(
              zone: z,
              method: GeoFenceMethod.gps,
              lat: gpsPos.latitude,
              lng: gpsPos.longitude,
              accuracy: gpsPos.accuracy,
            );
          }
        }
      }
    }

    // ====== الطبقة 3: IP Geolocation ======
    if (settings.checkIp) {
      final ipInfo = await _getIpLocation();
      if (ipInfo != null) {
        // أ) لو IP داخل دائرة منطقة (تطابق نقطة)
        for (final z in activeZones) {
          final dKm = _haversineKm(
            ipInfo.latitude,
            ipInfo.longitude,
            z.centerLat,
            z.centerLng,
          );
          // IP أقلّ دقّة → نوسّع نصف القطر مرّة ونصف
          if (dKm <= z.radiusKm * 1.5) {
            // إذا GPS كان مرفوضاً (خارج)، احتمال VPN
            String? warn;
            if (gpsPos != null) {
              warn = 'GPS وIP في مواقع مختلفة — احتمال VPN';
              if (!settings.allowVpn) {
                return GeoFenceCheckResult.reject(
                  GeoFenceRejection.outsideZone,
                  lat: gpsPos.latitude,
                  lng: gpsPos.longitude,
                );
              }
            }
            return GeoFenceCheckResult.allow(
              zone: z,
              method: GeoFenceMethod.ipAddress,
              warning: warn,
              lat: ipInfo.latitude,
              lng: ipInfo.longitude,
            );
          }
        }
        // ب) لو IP في نفس البلد (country code)
        for (final z in activeZones) {
          if (z.ipCountryCode != null &&
              ipInfo.countryCode.toUpperCase() ==
                  z.ipCountryCode!.toUpperCase()) {
            return GeoFenceCheckResult.allow(
              zone: z,
              method: GeoFenceMethod.ipAddress,
              warning: 'مطابقة بمستوى الدولة فقط',
            );
          }
        }
      }
    }

    // إذا وصلنا هنا → كلّ الطبقات فشلت
    if (gpsBlock == GeoFenceRejection.permissionDenied) {
      return GeoFenceCheckResult.reject(
          GeoFenceRejection.permissionDenied);
    }
    if (gpsBlock == GeoFenceRejection.serviceDisabled) {
      return GeoFenceCheckResult.reject(
          GeoFenceRejection.serviceDisabled);
    }
    return GeoFenceCheckResult.reject(
      GeoFenceRejection.outsideZone,
      lat: gpsPos?.latitude,
      lng: gpsPos?.longitude,
    );
  }

  // ============================================================
  // 🛰️ GPS
  // ============================================================
  Future<_GpsResult> _getGps(bool rejectMock) async {
    try {
      // 1) الخدمة مفعّلة؟
      final svc = await Geolocator.isLocationServiceEnabled();
      if (!svc) {
        return _GpsResult(rejection: GeoFenceRejection.serviceDisabled);
      }
      // 2) الإذن
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever ||
          perm == LocationPermission.denied) {
        return _GpsResult(
            rejection: GeoFenceRejection.permissionDenied);
      }
      // 3) القراءة
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: _gpsTimeout,
      );
      // 4) Mock-location
      if (rejectMock && pos.isMocked) {
        return _GpsResult(
          position: pos,
          rejection: GeoFenceRejection.mockLocationDetected,
        );
      }
      return _GpsResult(position: pos);
    } catch (e) {
      // ignore: avoid_print
      M7Log.error('GeoFence', 'GPS', error: e);
      return _GpsResult(rejection: GeoFenceRejection.unknown);
    }
  }

  // ============================================================
  // 📡 Wi-Fi SSID
  // ============================================================
  Future<String?> _currentWifiSsid() async {
    try {
      final info = NetworkInfo();
      final raw = await info.getWifiName();
      if (raw == null) return null;
      // بعض الأجهزة تُرجع الاسم بين علامتي تنصيص
      return raw.replaceAll('"', '').trim();
    } catch (e) {
      // ignore: avoid_print
      M7Log.error('GeoFence', 'Wi-Fi', error: e);
      return null;
    }
  }

  // ============================================================
  // 🌐 IP Geolocation (مجاني عبر ip-api.com)
  // ============================================================
  /// مخزَّن مؤقّتاً لمدّة 5 دقائق لتجنّب الاستدعاءات المتكرّرة
  _IpInfo? _ipCache;
  DateTime? _ipCacheAt;

  Future<_IpInfo?> _getIpLocation() async {
    // كاش 5 دقائق
    if (_ipCache != null && _ipCacheAt != null) {
      if (DateTime.now().difference(_ipCacheAt!).inMinutes < 5) {
        return _ipCache;
      }
    }
    try {
      final res = await http
          .get(Uri.parse(
              'http://ip-api.com/json/?fields=status,country,countryCode,city,lat,lon,query'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return null;
      final body = json.decode(res.body) as Map<String, dynamic>;
      if (body['status'] != 'success') return null;
      _ipCache = _IpInfo(
        latitude: (body['lat'] as num).toDouble(),
        longitude: (body['lon'] as num).toDouble(),
        countryCode: body['countryCode'] as String? ?? '',
        country: body['country'] as String? ?? '',
        city: body['city'] as String? ?? '',
        ip: body['query'] as String? ?? '',
      );
      _ipCacheAt = DateTime.now();
      return _ipCache;
    } catch (e) {
      // ignore: avoid_print
      M7Log.error('GeoFence', 'IP location', error: e);
      return null;
    }
  }

  // ============================================================
  // 📐 Haversine — مسافة بالكيلومتر بين نقطتين
  // ============================================================
  double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0; // نصف قطر الأرض (كم)
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  double _deg2rad(double d) => d * (math.pi / 180.0);

  /// متاح للاختبار من الواجهة
  double distanceKm(double lat1, double lng1, double lat2, double lng2) =>
      _haversineKm(lat1, lng1, lat2, lng2);
}

class _GpsResult {
  final Position? position;
  final GeoFenceRejection? rejection;
  _GpsResult({this.position, this.rejection});
}

class _IpInfo {
  final double latitude;
  final double longitude;
  final String countryCode;
  final String country;
  final String city;
  final String ip;
  _IpInfo({
    required this.latitude,
    required this.longitude,
    required this.countryCode,
    required this.country,
    required this.city,
    required this.ip,
  });
}
