import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../config/fcm_config.dart';
import 'm7_log.dart';
import 'notifications_service.dart';
import 'supabase_service.dart';

/// 📲 FcmService — إدارة Push Notifications عَبر Firebase Cloud Messaging
///
/// مَسؤوليّاتها:
///   - طَلَب صلاحيّة الإشعارات من المُستخدِم
///   - الحصول على FCM token للجِهاز
///   - حِفظه في جَدول device_tokens مَربوطاً بالحساب
///   - الاستِماع لِرسائل foreground/background
///   - إظهار الإشعار محلّيّاً (foreground) عَبر flutter_local_notifications
///   - تَحديث NotificationsService cache عند وُصول إشعار
///
/// الاستِخدام:
///   ```dart
///   await FcmService.instance.initialize();           // عند bootstrap
///   await FcmService.instance.bindToUser(accountId); // بَعد الـlogin
///   await FcmService.instance.unbind();              // عند الـlogout
///   ```
class FcmService {
  FcmService._();
  static final instance = FcmService._();

  bool _initialized = false;
  String? _currentToken;
  String? _currentUserId;
  final _localNotifs = FlutterLocalNotificationsPlugin();

  String? get currentToken => _currentToken;

  /// تَهيئة عامّة — تُستَدعى مَرّة واحِدة عند bootstrap التَطبيق.
  Future<void> initialize() async {
    if (_initialized) return;

    // 🌐 Web path — يَحتاج VAPID key مَوضوع في fcm_config.dart
    if (kIsWeb) {
      if (!FcmConfig.webPushEnabled) {
        debugPrint('ℹ️ FCM: Web push disabled — set webVapidKey in fcm_config.dart');
        _initialized = true;
        return;
      }
      try {
        final settings = await FirebaseMessaging.instance.requestPermission(
          alert: true, badge: true, sound: true,
        );
        debugPrint('🔵 FCM Web permission: ${settings.authorizationStatus}');
        _currentToken = await FirebaseMessaging.instance.getToken(
          vapidKey: FcmConfig.webVapidKey,
        );
        debugPrint('🔵 FCM Web getToken: ${_currentToken?.substring(0, math.min(30, _currentToken!.length)) ?? "NULL"}');
        FirebaseMessaging.onMessage.listen(_onForegroundMessage);
        FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpened);
        FirebaseMessaging.instance.onTokenRefresh.listen(_onTokenRefresh);
      } catch (e) {
        debugPrint('❌ FCM Web initialize failed: $e');
      }
      _initialized = true;
      return;
    }

    try {
      // 1) تَهيئة flutter_local_notifications
      await _setupLocalNotifications();

      // 2) طَلَب صلاحيّة (iOS / Android 13+)
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        M7Log.info('FCM', 'permission denied');
      }

      // 3) iOS: نَتأكَّد من APNs token
      if (!kIsWeb && Platform.isIOS) {
        await FirebaseMessaging.instance.getAPNSToken();
      }

      // 4) جَلب FCM token
      _currentToken = await FirebaseMessaging.instance.getToken();

      // 5) المُستَمِعون
      FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpened);
      FirebaseMessaging.onBackgroundMessage(_backgroundHandler);
      FirebaseMessaging.instance.onTokenRefresh.listen(_onTokenRefresh);

      _initialized = true;
    } catch (e) {
      M7Log.error('FCM', 'initialize', error: e);
    }
  }

  /// رَبط الـtoken بِحساب — يُستَدعى بَعد الـlogin.
  Future<void> bindToUser(String userId) async {
    _currentUserId = userId;

    // 🌐 Web — يَحتاج VAPID key. إن لَم يُضَع في fcm_config.dart نَتَخَطّى بِهُدوء.
    if (kIsWeb && !FcmConfig.webPushEnabled) {
      debugPrint('ℹ️ FCM bindToUser skipped on Web (set webVapidKey in fcm_config.dart to enable)');
      return;
    }

    debugPrint('🔵 FCM bindToUser called for user=$userId, currentToken=${_currentToken?.substring(0, math.min(20, _currentToken!.length)) ?? "NULL"}');

    // 🆕 إذا الـ token لَم يَأتِ بَعد، حاوِل الحُصول عَليه مُباشَرَةً
    if (_currentToken == null) {
      debugPrint('⚠ FCM: token is null, trying to fetch...');
      try {
        // طَلَب صَلاحِيّة أَوّلاً (إذا لَم تُمنَح)
        final settings = await FirebaseMessaging.instance.requestPermission(
          alert: true, badge: true, sound: true,
        );
        debugPrint('🔵 FCM permission status: ${settings.authorizationStatus}');

        if (!kIsWeb && Platform.isIOS) {
          await FirebaseMessaging.instance.getAPNSToken();
        }
        // 🌐 على الـ Web يَجِب تَمرير VAPID key؛ على mobile لا يَلزَم
        _currentToken = kIsWeb
            ? await FirebaseMessaging.instance.getToken(
                vapidKey: FcmConfig.webVapidKey,
              )
            : await FirebaseMessaging.instance.getToken();
        debugPrint('🔵 FCM getToken result: ${_currentToken?.substring(0, math.min(30, _currentToken!.length)) ?? "STILL NULL"}');
      } catch (e) {
        debugPrint('❌ FCM getToken failed: $e');
      }
    }

    if (_currentToken == null) {
      debugPrint('❌ FCM bindToUser: cannot save (token is null)');
      return;
    }
    debugPrint('✅ FCM saving token for user=$userId...');
    await _saveToken(userId, _currentToken!);
  }

  /// فَكّ الرَبط — يُستَدعى عند الـlogout.
  Future<void> unbind() async {
    final userId = _currentUserId;
    final token = _currentToken;
    _currentUserId = null;
    if (userId == null || token == null) return;
    final supa = SupabaseService();
    if (!supa.isReady) return;
    try {
      await supa.client
          .from('device_tokens')
          .update({'is_active': false})
          .eq('user_id', userId)
          .eq('token', token);
    } catch (e) {
      M7Log.error('FCM', 'unbind', error: e);
    }
  }

  Future<void> _setupLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const init = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );
    await _localNotifs.initialize(init);

    // 🆕 أَنشِئ قَناة Android بِأَعلى أَهَمِّيّة لِظُهور heads-up + صَوت + اِهتِزاز
    // هذه القَناة تُستَخدَم عَنَدَ غَلق التَطبيق (FCM يُحَوِّل لَها مُباشَرَةً)
    if (!kIsWeb && Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        'm7_default', // ⚠ نَفس اسم channel_id في send-push Edge Function
        'M7 Nexus Notifications',
        description: 'إشعارات M7 Nexus الرَئيسيّة (الطَلَبات، الإشعارات، إلخ)',
        importance: Importance.max, // أَعلى مُستَوى — يُظهِر heads-up + صَوت
        playSound: true,
        enableVibration: true,
        showBadge: true,
      );
      final androidPlugin = _localNotifs
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(channel);
      debugPrint('✅ FCM: Android channel "m7_default" created (max importance)');
    }
  }

  Future<void> _saveToken(String userId, String token) async {
    final supa = SupabaseService();
    if (!supa.isReady) {
      debugPrint('❌ FCM _saveToken: Supabase not ready');
      return;
    }
    debugPrint('🔵 FCM _saveToken: starting for user=$userId');
    try {
      // اِجمَع مَعلومات الجِهاز
      final info = DeviceInfoPlugin();
      String platform = 'unknown';
      String? deviceName;
      String? osVersion;
      if (kIsWeb) {
        platform = 'web';
      } else if (Platform.isAndroid) {
        platform = 'android';
        final a = await info.androidInfo;
        deviceName = '${a.manufacturer} ${a.model}';
        osVersion = 'Android ${a.version.release} (API ${a.version.sdkInt})';
      } else if (Platform.isIOS) {
        platform = 'ios';
        final i = await info.iosInfo;
        deviceName = i.utsname.machine;
        osVersion = '${i.systemName} ${i.systemVersion}';
      }
      await supa.client.from('device_tokens').upsert({
        'user_id': userId,
        'token': token,
        'platform': platform,
        if (deviceName != null) 'device_name': deviceName,
        if (osVersion != null) 'os_version': osVersion,
        'app_version': '1.0.0+1',
        'last_seen_at': DateTime.now().toUtc().toIso8601String(),
        'is_active': true,
      }, onConflict: 'user_id,token');
      debugPrint('✅ FCM _saveToken: SUCCESS for user=$userId platform=$platform');
    } catch (e) {
      debugPrint('❌ FCM _saveToken failed: $e');
      M7Log.error('FCM', 'saveToken', error: e);
    }
  }

  // ============================================================
  // المُستَمِعون
  // ============================================================

  /// الإشعار يَصِل والتَطبيق مَفتوح
  Future<void> _onForegroundMessage(RemoteMessage msg) async {
    M7Log.info('FCM', 'foreground: ${msg.notification?.title}');
    // أَظهِر الإشعار محلّيّاً (لأنّ FCM لا يَعرضه تلقائيّاً في foreground)
    final n = msg.notification;
    if (n != null) {
      await _localNotifs.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        n.title,
        n.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'm7_default',
            'M7 Notifications',
            channelDescription: 'إشعارات M7 Nexus',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
      );
    }
    // حَدِّث cache الإشعارات (لِيَظهَر الـbadge فوراً)
    await NotificationsService.instance.refresh();
  }

  /// المُستَخدِم نَقَر على الإشعار وفَتح التَطبيق
  Future<void> _onMessageOpened(RemoteMessage msg) async {
    M7Log.info('FCM', 'opened: ${msg.data}');
    await NotificationsService.instance.refresh();
    // (لاحقاً) Deep link navigation حَسَب data['deep_link_key']
  }

  /// تَحديث Token تلقائيّاً (يَحدُث أحياناً من Firebase)
  Future<void> _onTokenRefresh(String newToken) async {
    _currentToken = newToken;
    if (_currentUserId != null) {
      await _saveToken(_currentUserId!, newToken);
    }
  }
}

// ============================================================
// 🚨 Background handler — يَجِب أن يَكون top-level function
// ============================================================
@pragma('vm:entry-point')
Future<void> _backgroundHandler(RemoteMessage message) async {
  // مَوجود هنا لِيَتَمَكَّن FCM من تَشغيله أَثناء غَلق التَطبيق.
  // Firebase يَعرض الإشعار تلقائيّاً — لا حاجة لِعَمَل شَيء.
  if (kDebugMode) {
    debugPrint('FCM background: ${message.notification?.title}');
  }
}
