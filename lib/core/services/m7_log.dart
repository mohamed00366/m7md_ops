import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// 📝 خدمة Logging موحّدة للتطبيق.
///
/// يستبدل كلّ `print()` المتفرّقة بنقطة واحدة:
///   • مستويات: debug / info / warn / error
///   • Tags لكل وحدة (`M7Log.debug('Auth', 'login attempt')`)
///   • Timestamp تلقائي
///   • على الويب يستخدم `console.log` نظيف
///   • على الإنتاج يمكن وصله لاحقاً بـ Sentry/Crashlytics في `_emit`
///
/// الاستخدام:
/// ```dart
/// M7Log.debug('DataService', 'fetched 12 rosters');
/// M7Log.error('Auth', 'login failed', error: e, stack: stack);
/// ```
class M7Log {
  M7Log._();

  /// عتبة المستوى — في الإنتاج يمكن رفعها لـ warn فقط.
  static M7LogLevel minLevel = kDebugMode ? M7LogLevel.debug : M7LogLevel.info;

  /// معالجات إضافيّة (مثلاً Sentry). تُستدعى بعد الطباعة.
  static final List<M7LogSink> sinks = <M7LogSink>[];

  static void debug(String tag, String message, {Object? data}) {
    _emit(M7LogLevel.debug, tag, message, data: data);
  }

  static void info(String tag, String message, {Object? data}) {
    _emit(M7LogLevel.info, tag, message, data: data);
  }

  static void warn(String tag, String message,
      {Object? data, Object? error, StackTrace? stack}) {
    _emit(M7LogLevel.warn, tag, message,
        data: data, error: error, stack: stack);
  }

  static void error(String tag, String message,
      {Object? data, Object? error, StackTrace? stack}) {
    _emit(M7LogLevel.error, tag, message,
        data: data, error: error, stack: stack);
  }

  static void _emit(
    M7LogLevel level,
    String tag,
    String message, {
    Object? data,
    Object? error,
    StackTrace? stack,
  }) {
    if (level.priority < minLevel.priority) return;

    final ts = DateTime.now().toIso8601String().substring(11, 23); // HH:mm:ss.SSS
    final prefix = '[$ts] ${level.symbol} $tag:';
    final dataStr = data == null ? '' : '\n    data: $data';
    final errorStr = error == null ? '' : '\n    error: $error';
    final stackStr = stack == null ? '' : '\n$stack';
    final fullMessage = '$prefix $message$dataStr$errorStr$stackStr';

    // dart:developer.log يظهر في Flutter DevTools و Chrome console بشكل أنظف
    developer.log(
      fullMessage,
      name: 'M7',
      level: level.priority,
      error: error,
      stackTrace: stack,
    );

    // ضع التسجيل في كلّ Sink مرتبط (Sentry, إلخ)
    for (final sink in sinks) {
      try {
        sink.add(M7LogEntry(
          level: level,
          tag: tag,
          message: message,
          data: data,
          error: error,
          stack: stack,
          timestamp: DateTime.now(),
        ));
      } catch (_) {
        // لا نريد كسر الـ flow بسبب sink
      }
    }
  }
}

enum M7LogLevel {
  debug(0, '🔍'),
  info(1, 'ℹ️'),
  warn(2, '⚠️'),
  error(3, '❌');

  final int priority;
  final String symbol;
  const M7LogLevel(this.priority, this.symbol);
}

class M7LogEntry {
  final M7LogLevel level;
  final String tag;
  final String message;
  final Object? data;
  final Object? error;
  final StackTrace? stack;
  final DateTime timestamp;
  const M7LogEntry({
    required this.level,
    required this.tag,
    required this.message,
    required this.timestamp,
    this.data,
    this.error,
    this.stack,
  });
}

/// واجهة Sink — استخدمها لربط Sentry/Crashlytics لاحقاً.
abstract class M7LogSink {
  void add(M7LogEntry entry);
}
