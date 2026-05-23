// 🐛 ErrorTrackingService — طَبَقة رَفيعة فَوقَ Sentry
//
// **الفِكرة:** كُلّ الكود يَتَكَلَّم مَع هذه الخِدمة فَقَط، لا مَع Sentry مُباشَرةً.
// هكذا:
//   - لَو الـDSN غَير مُعَيَّن (تَطوير) → كُلّ شَيء no-op (لا أَخطاء، لا تَأخير)
//   - لَو المُستَخدِم فَعَّل "Opt-out" → لا نَرفَع أَيّ بَيانات
//   - لَو فَشِل Sentry نَفسه (شَبَكة، إلخ) → لا يَكسِر التَطبيق
//
// **DSN كَيف يُعَيَّن؟**
//   ‐ مِن `--dart-define=SENTRY_DSN=https://...@o.../...` عِندَ البِناء
//   ‐ أَو مِن `app_settings.sentry_dsn` (يُمكِن تَغييره مِن لَوحة الإعدادات)
//
// **opt-out مَحَلِّيّاً:**
//   ‐ مَفتاح `SharedPreferences = 'sentry_disabled' (bool)`
//   ‐ يَستَطيع المُستَخدِم تَعطيله مِن صَفحة الإعدادات الخاصّة بِه

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings_service.dart';
import 'm7_log.dart';

/// مَفتاح SharedPreferences لِتَعطيل تَتَبُّع الأَخطاء عَلى هذا الجِهاز
const String _kSentryDisabledKey = 'sentry_disabled';

/// مَفتاح app_settings الذي يَحمِل DSN (يُمكِن تَغييره مِن لَوحة الإعدادات)
const String _kSentryDsnSettingsKey = 'sentry_dsn';

/// مَفتاح dart-define الذي يَحمِل DSN عِندَ البِناء
const String _kSentryDsnFromBuild =
    String.fromEnvironment('SENTRY_DSN', defaultValue: '');

class ErrorTrackingService {
  ErrorTrackingService._();
  static final ErrorTrackingService instance = ErrorTrackingService._();

  bool _initialized = false;
  bool _enabled = false;
  String? _activeDsn;

  bool get isInitialized => _initialized;
  bool get isEnabled => _enabled && _initialized;
  String? get activeDsn => _activeDsn;

  /// تَهيئَة Sentry. تُستَدعى مِن main.dart قَبل runApp.
  ///
  /// التَدَفُّق:
  ///   1. اقرأ DSN: dart-define أَوَّلاً، ثُمَّ app_settings كَـfallback
  ///   2. اقرأ opt-out المُستَخدِم مِن SharedPreferences
  ///   3. لَو لا DSN أَو المُستَخدِم رَفَض → لا تَهيئَة، عَودة فَوريّة
  ///   4. وَإلّا → Sentry.init مَع تَكوين مَعقول
  ///
  /// لا تَرمي أَيّ خَطَأ — في أَسوَأ حالة، تُسَجِّل debug log وَتَستَمِرّ.
  Future<void> init({
    required String release,
    String environment = 'production',
  }) async {
    if (_initialized) return;
    try {
      // 1) ابحَث عَن DSN
      String? dsn = _kSentryDsnFromBuild.isNotEmpty
          ? _kSentryDsnFromBuild
          : null;
      if (dsn == null || dsn.isEmpty) {
        // جَرِّب app_settings
        try {
          final row = await AppSettingsService.instance
              .getJson(_kSentryDsnSettingsKey);
          final v = row?['value'];
          if (v is String && v.isNotEmpty) dsn = v;
        } catch (_) {/* بِدون اتّصال — لا مُشكِلة */}
      }

      if (dsn == null || dsn.isEmpty) {
        if (kDebugMode) {
          debugPrint(
              '🐛 Sentry: no DSN configured — error tracking disabled');
        }
        _activeDsn = null;
        _enabled = false;
        _initialized = true; // مَهَّأ، لكِن مُعَطَّل
        return;
      }

      // 2) اقرأ opt-out المُستَخدِم
      final prefs = await SharedPreferences.getInstance();
      final disabled = prefs.getBool(_kSentryDisabledKey) ?? false;
      if (disabled) {
        if (kDebugMode) {
          debugPrint('🐛 Sentry: user opted out — error tracking disabled');
        }
        _activeDsn = dsn;
        _enabled = false;
        _initialized = true;
        return;
      }

      // 3) Sentry.init
      await SentryFlutter.init((options) {
        options.dsn = dsn;
        options.release = release;
        options.environment = environment;
        // عَيِّنة المُعامَلات (transactions): 30% — لا نُريد تَكلِفة عالية
        options.tracesSampleRate = 0.30;
        // أَخطاء بَطيئة جِدّاً → ابعَثها كُلّها
        options.sampleRate = 1.0;
        // اسحَب stack traces مَع breadcrumbs
        options.attachStacktrace = true;
        // لا تَلتَقِط أَخطاء AndroidView أَو DartError قَبل التَهيئَة
        options.beforeSend = _beforeSend;
        // 50 breadcrumb كَحَدّ أَقصى
        options.maxBreadcrumbs = 50;
      });

      _activeDsn = dsn;
      _enabled = true;
      _initialized = true;

      if (kDebugMode) {
        debugPrint(
            '🐛 Sentry: initialized (env=$environment, release=$release)');
      }
    } catch (e, st) {
      // فَشِلَت التَهيئَة → سَجِّل لكِن لا تَكسِر التَطبيق
      _enabled = false;
      _initialized = true;
      if (kDebugMode) {
        M7Log.error('Sentry', 'init failed', error: e, stack: st);
      }
    }
  }

  /// مُرَشِّح يَمنَع رَفع أَخطاء غَير مُفيدة (مَثَلاً: في وَضع التَطوير)
  FutureOr<SentryEvent?> _beforeSend(SentryEvent event, Hint hint) {
    // في debug mode نَطبَع لكِن لا نَرفَع (تَجَنُّب ضَوضاء)
    if (kDebugMode) {
      debugPrint('🐛 Sentry (debug, NOT sent): ${event.message?.formatted ?? event.exceptions?.firstOrNull?.value}');
      return null;
    }
    // تَجاهَل بَعض الأَخطاء الشائِعة لِلشَبَكة (تَنتَهي بِها قَواعِد بَيانات Sentry)
    final value = event.exceptions?.firstOrNull?.value ?? '';
    if (value.contains('SocketException') ||
        value.contains('TimeoutException') ||
        value.contains('Connection closed') ||
        value.contains('Failed host lookup')) {
      // أَخطاء شَبَكة عابِرة — لا نُريدها
      return null;
    }
    return event;
  }

  /// تَفعيل/تَعطيل تَتَبُّع الأَخطاء مِن المُستَخدِم (Opt-out)
  /// التَغيير يَأخُذ مَفعولاً بَعد إعادة تَشغيل التَطبيق.
  Future<void> setUserOptOut(bool optedOut) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSentryDisabledKey, optedOut);
  }

  /// هَل المُستَخدِم رَفَض تَتَبُّع الأَخطاء؟
  Future<bool> isUserOptedOut() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kSentryDisabledKey) ?? false;
  }

  /// ضَع DSN جَديد في app_settings (لِلَوحة الإعدادات)
  Future<void> setDsn(String dsn) async {
    await AppSettingsService.instance.setJson(
      _kSentryDsnSettingsKey,
      {'value': dsn},
    );
  }

  // ============================================================
  // ✉️ APIs لِلكود الذي يَستَخدِم الخِدمة
  // ============================================================

  /// رَفع استثناء يَدَويّاً (مَع stack trace + سياق)
  ///
  /// مِثال:
  /// ```dart
  /// try { ... } catch (e, st) {
  ///   ErrorTrackingService.instance.captureException(e, st, context: {
  ///     'employee_id': empId,
  ///     'screen': 'EmployeeForm',
  ///   });
  /// }
  /// ```
  Future<void> captureException(
    Object error,
    StackTrace? stack, {
    Map<String, dynamic>? context,
    String? hint,
    SentryLevel level = SentryLevel.error,
  }) async {
    if (!isEnabled) return;
    try {
      await Sentry.captureException(
        error,
        stackTrace: stack,
        hint: hint == null ? null : Hint.withMap({'note': hint}),
        withScope: (scope) {
          scope.level = level;
          if (context != null) {
            for (final entry in context.entries) {
              scope.setExtra(entry.key, entry.value);
            }
          }
        },
      );
    } catch (_) {/* لا تَكسِر التَطبيق */}
  }

  /// رَفع رِسالة (لِلتَحذيرات وَالأَحداث المُهِمّة، لا أَخطاء)
  Future<void> captureMessage(
    String message, {
    SentryLevel level = SentryLevel.info,
    Map<String, dynamic>? context,
  }) async {
    if (!isEnabled) return;
    try {
      await Sentry.captureMessage(
        message,
        level: level,
        withScope: (scope) {
          if (context != null) {
            for (final entry in context.entries) {
              scope.setExtra(entry.key, entry.value);
            }
          }
        },
      );
    } catch (_) {/* لا تَكسِر التَطبيق */}
  }

  /// أَضِف breadcrumb (نُقطة في رَحلة المُستَخدِم) — تَظهَر مَع الخَطَأ التالي
  void addBreadcrumb({
    required String message,
    String? category,
    Map<String, dynamic>? data,
    SentryLevel level = SentryLevel.info,
  }) {
    if (!isEnabled) return;
    try {
      Sentry.addBreadcrumb(Breadcrumb(
        message: message,
        category: category,
        data: data,
        level: level,
        timestamp: DateTime.now().toUtc(),
      ));
    } catch (_) {/* لا تَكسِر التَطبيق */}
  }

  /// عَيِّن المُستَخدِم الحاليّ (بَعد تَسجيل الدُخول)
  ///
  /// **خُصوصيّة:** لا نُرسِل اسم المُستَخدِم أَو email لِـSentry — فَقَط ID وَدَور.
  void setUser({
    required String accountId,
    String? employeeId,
    String? role,
    String? accountType,
  }) {
    if (!isEnabled) return;
    try {
      Sentry.configureScope((scope) {
        scope.setUser(SentryUser(
          id: accountId,
          // لا نُرسِل username/email لِأَنّ هذا تَطبيق مُؤَسَّسة + GDPR
        ));
        if (employeeId != null) scope.setTag('employee_id', employeeId);
        if (role != null) scope.setTag('role', role);
        if (accountType != null) scope.setTag('account_type', accountType);
      });
    } catch (_) {/* لا تَكسِر التَطبيق */}
  }

  /// امسَح المُستَخدِم (بَعد تَسجيل الخُروج)
  void clearUser() {
    if (!isEnabled) return;
    try {
      Sentry.configureScope((scope) {
        scope.setUser(null);
        scope.removeTag('employee_id');
        scope.removeTag('role');
        scope.removeTag('account_type');
      });
    } catch (_) {/* لا تَكسِر التَطبيق */}
  }

  /// أَضِف tag عام لِكُلّ الأَحداث القادِمة
  void setTag(String key, String value) {
    if (!isEnabled) return;
    try {
      Sentry.configureScope((scope) => scope.setTag(key, value));
    } catch (_) {/* لا تَكسِر التَطبيق */}
  }
}
