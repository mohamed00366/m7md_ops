import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../models/models.dart';
import '../../repositories/mock_repository.dart';
import 'driver_tracking_settings.dart';
import 'm7_log.dart';
import 'supabase_service.dart';

/// 📍 خدمة تتبّع السائق التلقائيّة
///
/// تعمل في الخلفيّة طالما التطبيق مفتوح:
///   • تستخدم Timer.periodic بفترة من الإعدادات
///   • ترسل موقع الباص إلى bus_locations
///   • تحترم ساعات الدوام (إن فُعّلت)
///   • تُوقف نفسها لو الإعدادات معطّلة
///
/// لا UI! خدمة في الخلفيّة فقط. السائق يرى فقط شارة "📍 يتم التتبّع"
/// في الـ AppBar للإشارة بأنّها تعمل.
///
/// ⚠️ ملاحظة: الموقع حالياً يُحاكى (بيانات عشوائيّة بجوار آخر موقع).
/// لربط Geolocator حقيقي، استبدل _getCurrentLocation() بمكتبة geolocator.
class DriverTrackingService extends ChangeNotifier {
  DriverTrackingService._();
  static final instance = DriverTrackingService._();

  Timer? _timer;
  bool _running = false;
  String? _driverEmployeeId;
  String? _busId;
  DateTime? _lastSent;
  int _sentCount = 0;
  String? _lastError;

  bool get isRunning => _running;
  DateTime? get lastSent => _lastSent;
  int get sentCount => _sentCount;
  String? get lastError => _lastError;
  String? get currentDriverId => _driverEmployeeId;

  /// متى آخر إرسال بصياغة بشريّة
  String get lastSentLabel {
    if (_lastSent == null) return '—';
    final diff = DateTime.now().difference(_lastSent!);
    if (diff.inSeconds < 60) return 'منذ ${diff.inSeconds}ث';
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes}د';
    return 'منذ ${diff.inHours}س';
  }

  /// ابدأ التتبّع لسائق معيّن (يُستدعى من driver_home عند الدخول)
  /// [accountId] الحساب المرتبط — يُستخدم لفحص السياسة المتشدّدة
  Future<void> start({
    required String driverEmployeeId,
    String? accountId,
  }) async {
    await DriverTrackingSettings.instance.load();
    final settings = DriverTrackingSettings.instance;
    if (!settings.enabled) {
      _lastError = 'التتبّع معطّل من الإعدادات';
      notifyListeners();
      return;
    }
    // 🆕 احترم سياسة النطاق (per-account/per-jobTitle)
    if (accountId != null && !settings.appliesTo(accountId)) {
      _lastError = 'هذا الحساب مُعفى من تتبّع الموقع';
      notifyListeners();
      return;
    }
    if (_running && _driverEmployeeId == driverEmployeeId) return;
    _driverEmployeeId = driverEmployeeId;
    final repo = MockRepository();
    final bus = repo.buses.firstWhere(
      (b) => b.driverId == driverEmployeeId,
      orElse: () => repo.buses.isEmpty
          ? Bus(id: '', name: '', plateNumber: '', capacity: 0)
          : repo.buses.first,
    );
    _busId = bus.id;
    if (_busId == null || _busId!.isEmpty) {
      _lastError = 'لا يوجد باص مُسند للسائق';
      notifyListeners();
      return;
    }
    _stopTimer();
    _running = true;
    _lastError = null;
    // أرسل الآن مرّة واحدة، ثمّ كرّر كل interval
    _tick();
    final intervalMinutes = settings.intervalMinutes;
    _timer = Timer.periodic(Duration(minutes: intervalMinutes), (_) {
      _tick();
    });
    notifyListeners();
  }

  /// أوقف التتبّع
  void stop() {
    _stopTimer();
    _running = false;
    notifyListeners();
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// نبضة واحدة — إرسال الموقع
  Future<void> _tick() async {
    final settings = DriverTrackingSettings.instance;
    if (!settings.enabled) {
      stop();
      return;
    }
    if (settings.workingHoursOnly && !settings.isWithinWorkingHours) {
      _lastError = 'خارج ساعات الدوام';
      notifyListeners();
      return;
    }
    if (_busId == null || _driverEmployeeId == null) return;
    try {
      final pos = await _getCurrentLocation();
      final repo = MockRepository();
      repo.recordLocation(BusLocation(
        busId: _busId!,
        driverId: _driverEmployeeId!,
        latitude: pos.lat,
        longitude: pos.lon,
        timestamp: DateTime.now(),
        speed: pos.speed,
      ));

      // 🆕 إرسال إلى Supabase (الجَدول الحَقيقيّ)
      final supa = SupabaseService();
      if (supa.isReady) {
        try {
          await supa.client.from('bus_locations').insert({
            'bus_id': _busId,
            'driver_id': _driverEmployeeId,
            'latitude': pos.lat,
            'longitude': pos.lon,
            'speed': pos.speed,
            'accuracy_meters': pos.accuracy,
            'timestamp': DateTime.now().toIso8601String(),
          });
        } catch (e) {
          // لا نوقف الإرسال — نَستَمِرّ في الـmock
          M7Log.error('DriverTracking', 'supabase_insert', error: e);
        }
      }

      _lastSent = DateTime.now();
      _sentCount++;
      _lastError = null;
      notifyListeners();
    } catch (e) {
      _lastError = 'فشل الإرسال: $e';
      notifyListeners();
    }
  }

  /// 🆕 يَستَخدِم geolocator حَقيقيّ — لا mock.
  /// إن لَم تَتَوَفَّر الصَلاحيّة أَو الـGPS مَغلَق، يَرجِع لِلـmock كَـfallback.
  Future<_LocPoint> _getCurrentLocation() async {
    try {
      // فَحص توافُر خِدمة GPS
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _lastError = 'خِدمة GPS غَير مُفَعَّلة على الجِهاز';
        return _mockLocation();
      }

      // فَحص الصَلاحيّة
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _lastError = 'صَلاحيّة الموقِع مَرفوضة';
        return _mockLocation();
      }

      // الحُصول على الموقِع الفِعليّ
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      return _LocPoint(
        lat: pos.latitude,
        lon: pos.longitude,
        speed: pos.speed,
        accuracy: pos.accuracy,
      );
    } catch (e) {
      _lastError = 'خَطَأ في قِراءة GPS: $e';
      return _mockLocation();
    }
  }

  /// Mock fallback عِندَ فَشل الـGPS الحَقيقيّ
  _LocPoint _mockLocation() {
    final repo = MockRepository();
    final last = _busId == null ? null : repo.latestLocation(_busId!);
    final rnd = Random();
    return _LocPoint(
      lat: (last?.latitude ?? 25.276) + (rnd.nextDouble() - 0.5) * 0.005,
      lon: (last?.longitude ?? 55.296) + (rnd.nextDouble() - 0.5) * 0.005,
      speed: 30 + rnd.nextDouble() * 50,
      accuracy: 50,
    );
  }

  /// إعادة ضبط (لو تغيّرت الإعدادات أثناء التشغيل)
  Future<void> applySettingsChange() async {
    if (_running && _driverEmployeeId != null) {
      final id = _driverEmployeeId!;
      stop();
      await start(driverEmployeeId: id);
    }
  }
}

class _LocPoint {
  final double lat;
  final double lon;
  final double speed;
  final double accuracy;
  _LocPoint({
    required this.lat,
    required this.lon,
    required this.speed,
    this.accuracy = 0,
  });
}
