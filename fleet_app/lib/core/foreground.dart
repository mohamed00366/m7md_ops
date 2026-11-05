import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'store.dart';
import 'sync.dart';

/// 1.0.6 — a persistent foreground service so Android (and Samsung/Xiaomi battery managers) don't kill the
/// background job. It shows one quiet notification, syncs on an interval, starts again after a reboot or an
/// app update, and restarts itself if the system stops it. This is an ADDED layer; WorkManager stays as a backup.
/// The whole thing is optional: the "keep running" switch (on by default) turns it off and leaves only WorkManager.

const _channelId = 'vip_settings_service';
const _syncIntervalMs = 15 * 60 * 1000;

@pragma('vm:entry-point')
void foregroundCallback() => FlutterForegroundTask.setTaskHandler(FleetTaskHandler());

/// Runs inside the service's own isolate. Plugins are registered there, so FleetSync works as usual.
class FleetTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await FleetSync.run(reason: 'service_start');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    FleetSync.run(reason: 'service');
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {}
}

class FleetForeground {
  static void initComms() {
    try {
      FlutterForegroundTask.initCommunicationPort();
    } catch (_) {}
  }

  static void _init() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _channelId,
        channelName: 'VIP Settings',
        channelDescription: 'Keeps recording running',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(_syncIntervalMs),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  /// Starts the service when "keep running" is on (default) and the device is set up. Safe to call again.
  static Future<void> startIfEnabled(Prefs p) async {
    if (kIsWeb || !p.keepAlive) return;
    try {
      _init();
      if (await FlutterForegroundTask.isRunningService) return;
      await FlutterForegroundTask.startService(
        serviceId: 7310,
        notificationTitle: 'VIP Settings',
        notificationText: 'شغّال · Recording is running',
        callback: foregroundCallback,
      );
    } catch (e) {
      debugPrint('foreground start: $e');
    }
  }

  /// A cheap watchdog: if "keep running" is on but the service died, bring it back.
  static Future<void> ensure(Prefs p) async {
    if (kIsWeb || !p.keepAlive) return;
    try {
      if (!await FlutterForegroundTask.isRunningService) await startIfEnabled(p);
    } catch (_) {}
  }

  static Future<void> stop() async {
    if (kIsWeb) return;
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}
  }
}
