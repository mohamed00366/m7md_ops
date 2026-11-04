import 'package:another_telephony/telephony.dart' hide NetworkType;
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import 'sync.dart';

const kPeriodicTask = 'vip_fleet_sync';

/// WorkManager entry (every 15 minutes, kept after a restart of the device).
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    await FleetSync.run(reason: 'background');
    return true;
  });
}

/// A new SMS while the app is closed: sync at once (the message is read from the inbox with the others).
@pragma('vm:entry-point')
Future<void> onBackgroundSms(SmsMessage m) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Future<void>.delayed(const Duration(seconds: 3)); // the SMS reaches the inbox first
  await FleetSync.run(reason: 'sms');
}

class FleetBackground {
  static Future<void> start() async {
    await Workmanager().initialize(callbackDispatcher);
    await Workmanager().registerPeriodicTask(
      kPeriodicTask,
      kPeriodicTask,
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      constraints: Constraints(networkType: NetworkType.notRequired),
    );
  }

  /// Listens to new SMS (also when the app is closed). Needs the SMS permission.
  static void listenSms(void Function() onNew) {
    try {
      Telephony.instance.listenIncomingSms(
        onNewMessage: (_) => Future<void>.delayed(const Duration(seconds: 3), onNew),
        onBackgroundMessage: onBackgroundSms,
        listenInBackground: true,
      );
    } catch (_) {/* no telephony on this device */}
  }
}
