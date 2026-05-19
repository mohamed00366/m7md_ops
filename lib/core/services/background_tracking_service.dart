import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';

import 'm7_log.dart';
import 'supabase_service.dart';

/// 🌙 خِدمة تَتَبُّع في الخَلفيّة (Foreground Service)
///
/// تَستَخدِم `flutter_foreground_task` لِتَشغيل خِدمة دائِمة في الإشعارات
/// تَضمَن استِمرار إرسال GPS حَتّى لو أُغلِق التَطبيق.
///
/// **الاستِخدام:**
/// ```dart
/// await BackgroundTrackingService.start(
///   busId: '...',
///   driverId: '...',
///   intervalSeconds: 30,
/// );
/// // ...
/// await BackgroundTrackingService.stop();
/// ```
class BackgroundTrackingService {
  static const _channelId = 'm7_fleet_tracking';
  static const _channelName = 'M7 Fleet Tracking';

  /// تَهيِئة (تُستَدعى مَرَّة في main.dart)
  static void initialize() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _channelId,
        channelName: _channelName,
        channelDescription: 'GPS tracking for buses',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(30000), // كُلّ 30 ثانية
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  /// بَدء التَتَبُّع في الخَلفيّة
  static Future<bool> start({
    required String busId,
    required String driverId,
    int intervalSeconds = 30,
  }) async {
    // فَحص الصَلاحيّات أَوّلاً
    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      M7Log.error('BackgroundTracking', 'start',
          error: 'Location permission denied');
      return false;
    }

    // فَحص الصَلاحيّات لِخِدمات الخَلفيّة
    final canRun = await FlutterForegroundTask.canDrawOverlays;
    if (!canRun && !kIsWeb) {
      M7Log.info('BackgroundTracking',
          'Overlay permission not granted (optional)');
    }

    try {
      await FlutterForegroundTask.startService(
        notificationTitle: '🚌 تَتَبُّع الباص نَشِط',
        notificationText: 'M7 يُرسِل الموقِع تلقائيّاً',
        notificationIcon: null,
        notificationButtons: [
          const NotificationButton(id: 'stop', text: 'إيقاف'),
        ],
        callback: backgroundTrackingCallback,
      );
      await FlutterForegroundTask.saveData(key: 'bus_id', value: busId);
      await FlutterForegroundTask.saveData(key: 'driver_id', value: driverId);
      await FlutterForegroundTask.saveData(
          key: 'interval', value: intervalSeconds);
      return true;
    } catch (e) {
      M7Log.error('BackgroundTracking', 'start', error: e);
      return false;
    }
  }

  /// إيقاف
  static Future<void> stop() async {
    try {
      await FlutterForegroundTask.stopService();
    } catch (e) {
      M7Log.error('BackgroundTracking', 'stop', error: e);
    }
  }

  /// هَل يَعمَل حاليّاً؟
  static Future<bool> isRunning() async {
    return await FlutterForegroundTask.isRunningService;
  }
}

/// 🔄 Callback يَعمَل في الخَلفيّة (isolate مُنفَصِل)
///
/// MUST be a top-level أَو static function لِأَنّ Flutter يَستَدعيها من
/// isolate آخَر. لا تَستَخدِم Provider هُنا.
@pragma('vm:entry-point')
void backgroundTrackingCallback() {
  FlutterForegroundTask.setTaskHandler(_FleetTrackingTaskHandler());
}

class _FleetTrackingTaskHandler extends TaskHandler {
  String? _busId;
  String? _driverId;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _busId = await FlutterForegroundTask.getData<String>(key: 'bus_id');
    _driverId =
        await FlutterForegroundTask.getData<String>(key: 'driver_id');
    if (kDebugMode) {
      print('🌙 BG tracking started — bus=$_busId driver=$_driverId');
    }
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {
    if (_busId == null || _driverId == null) return;
    try {
      // فَحص خِدمة الموقِع
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return;

      // جَلب الموقِع
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      // إرسال لـSupabase
      final supa = SupabaseService();
      if (supa.isReady) {
        await supa.client.from('bus_locations').insert({
          'bus_id': _busId,
          'driver_id': _driverId,
          'latitude': pos.latitude,
          'longitude': pos.longitude,
          'speed': pos.speed,
          'accuracy_meters': pos.accuracy,
          'timestamp': DateTime.now().toIso8601String(),
        });
      }

      if (kDebugMode) {
        print(
            '📍 BG ping → ${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}');
      }
    } catch (e) {
      if (kDebugMode) print('❌ BG ping error: $e');
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    if (kDebugMode) print('🛑 BG tracking stopped');
  }

  @override
  void onReceiveData(Object data) {
    // لا شَيء حاليّاً
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'stop') {
      FlutterForegroundTask.stopService();
    }
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp();
  }

  @override
  void onNotificationDismissed() {
    // يَتَجاهَل
  }
}
